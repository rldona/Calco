import UIKit
import MetalKit
import SwiftUI

/// UIKit view that owns the MTKView and handles Apple Pencil input.
/// Paints into whatever `EditorState.beginStroke()` hands out, and composites
/// `EditorState.visibleLayers()`: every display refresh while something moves (a stroke, a
/// gesture, playback), otherwise only when the editor changes, so the main thread stays free
/// for the buttons.
///
/// Finger gestures (Pencil never triggers them): two-finger tap undo, three-finger tap redo,
/// pinch / two-finger drag / twist to zoom, pan and rotate. A finger stroke that turns into
/// one of these is cancelled and leaves no trace.
final class CanvasUIView: UIView {

    private let mtkView = MTKView()
    private var builder = StrokeBuilder()
    private var activeTouch: UITouch?
    /// What the active touch is doing: painting, a tap for fill / eyedropper (acted on when it
    /// lifts), drawing a lasso, dragging out a shape, or working a Pen path.
    private enum Mode { case stroke, tap, lasso, moveDrag, shape, pen, node }
    /// The Node tool: what the touch grabbed (it shares where it went down and whether it moved
    /// with the Pen).
    private var nodeGrab: EditorState.NodeGrab = .nothing
    /// The Pen: what the touch grabbed, where it went down (view points), and whether it moved.
    private var penGrab: EditorState.PenGrab?
    private var penStart: CGPoint = .zero
    private var penMoved = false
    /// Two-finger gestures, before snapping (see `pinched`, `rotated`, `panned`).
    fileprivate var scaleIntent: CGFloat = 1
    fileprivate var rotationIntent: CGFloat = 0
    fileprivate var offsetIntent: CGSize = .zero
    fileprivate struct Snap: OptionSet { let rawValue: Int; static let scale = Snap(rawValue: 1), rotation = Snap(rawValue: 2), offset = Snap(rawValue: 4) }
    fileprivate var snaps: Snap = []
    fileprivate let haptics = UIImpactFeedbackGenerator(style: .light)
    private var mode = Mode.stroke
    /// Move: where the finger came down (canvas pixels and view points), to pick and drag in one go.
    private var moveStart: (canvas: CGPoint, view: CGPoint)?
    private var strokeTarget: MTLTexture?

    weak var state: EditorState? {
        didSet { redraw() }
    }
    private var touchLive = false { didSet { if touchLive != oldValue { live += touchLive ? 1 : -1 } } }
    /// Two-finger gestures in progress (pinch, twist, drag), each counted once.
    private var gesturesLive: Set<ObjectIdentifier> = [] { didSet { live = (touchLive ? 1 : 0) + gesturesLive.count } }
    /// Touches and gestures in progress that need the canvas redrawn every frame.
    private var live = 0 { didSet { updateLoop() } }
    /// The panels' insets as drawn: they glide to the editor's over a moment when a panel opens or
    /// hides, so the drawing slides into its new place instead of jumping.
    private var shownInsets: CanvasTransform.Insets?
    private var insetsFrom = CanvasTransform.Insets()
    private var insetsTarget = CanvasTransform.Insets()
    private var insetsStart: CFTimeInterval = 0
    private var gliding = false { didSet { if gliding != oldValue { live += gliding ? 1 : -1 } } }
    private static let glide: CFTimeInterval = 0.25

    /// The insets for this frame, easing toward `target`.
    fileprivate func insets(toward target: CanvasTransform.Insets) -> CanvasTransform.Insets {
        guard let shown = shownInsets else { shownInsets = target; insetsTarget = target; return target }
        if target != insetsTarget {
            insetsFrom = shown; insetsTarget = target; insetsStart = CACurrentMediaTime(); gliding = true
        }
        guard gliding else { return target }
        let t = min(1, (CACurrentMediaTime() - insetsStart) / Self.glide)
        let e = CGFloat(t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2)      // ease in-out
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * e }
        let now = CanvasTransform.Insets(top: mix(insetsFrom.top, target.top), left: mix(insetsFrom.left, target.left),
                                         bottom: mix(insetsFrom.bottom, target.bottom), right: mix(insetsFrom.right, target.right))
        shownInsets = now
        if t >= 1 { gliding = false; shownInsets = target }
        return now
    }
    var onLatencySample: ((Double) -> Void)?

    static let screenFormat: MTLPixelFormat = .bgra8Unorm

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        installGestures()
        let pencil = UIPencilInteraction()
        pencil.delegate = self
        addInteraction(pencil)

        guard let device = MTLCreateSystemDefaultDevice() else { return }
        mtkView.device = device
        mtkView.colorPixelFormat = Self.screenFormat
        mtkView.framebufferOnly = true
        mtkView.preferredFramesPerSecond = 120
        mtkView.isPaused = true
        mtkView.enableSetNeedsDisplay = true
        mtkView.delegate = self
        mtkView.isUserInteractionEnabled = false
        mtkView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mtkView)
        NSLayoutConstraint.activate([
            mtkView.leadingAnchor.constraint(equalTo: leadingAnchor),
            mtkView.trailingAnchor.constraint(equalTo: trailingAnchor),
            mtkView.topAnchor.constraint(equalTo: topAnchor),
            mtkView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    /// A new size (timeline resized or hidden, rotation): draw again at the new size, or the old
    /// picture is stretched to fit.
    override func layoutSubviews() {
        super.layoutSubviews()
        redraw()
    }

    /// One more frame, on the next display refresh.
    fileprivate func redraw() {
        if mtkView.isPaused { mtkView.setNeedsDisplay() }
    }

    /// Continuous while a touch or a gesture is going on; on demand otherwise (playback redraws
    /// on each frame change).
    private func updateLoop() {
        let continuous = live > 0
        guard continuous == mtkView.isPaused else { return }
        mtkView.enableSetNeedsDisplay = !continuous
        mtkView.isPaused = !continuous
        redraw()
    }

    // MARK: - Touch handling

    private func canvasPoint(_ t: UITouch, in state: EditorState) -> CGPoint {
        let p = state.renderer.canvasPoint(fromViewPoint: t.location(in: self), viewSize: bounds.size,
                                           transform: state.canvasTransform)
        return CGPoint(x: CGFloat(p.x), y: CGFloat(p.y))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let t = touches.first, let state, !state.isPlaying else { return }
        touchLive = true
        // Pencil only: a finger on the canvas is for gestures, never a mark.
        if state.pencilOnly && t.type != .pencil { return }
        switch state.tool {
        case .move where state.tween != nil:
            // Placing a tween's end pose: the handles on the selection do it; the canvas doesn't.
            return
        case .fill, .eyedropper, .move:
            // Wait for the lift: if it turns into a pinch or two-finger tap, touchesCancelled drops it.
            activeTouch = t
            mode = .tap
            moveStart = (canvasPoint(t, in: state), t.location(in: self))
        case .lasso:
            // Touching the canvas outside a floating selection drops it and starts a new mark.
            state.commitSelection()
            activeTouch = t
            let p = canvasPoint(t, in: state)
            moveStart = (p, t.location(in: self))
            switch state.select.shape {
            case .wand: mode = .tap                          // picks on the lift
            case .rect: mode = .lasso; state.lassoPoints = state.selectionRect(from: p, to: p)
            case .free: mode = .lasso; state.lassoPoints = [p]
            }
        case .shape:
            state.commitSelection()
            guard state.currentLayer?.locked == false else { return }
            activeTouch = t
            mode = .shape
            let p = canvasPoint(t, in: state)
            state.shapeDraft = .init(from: p, to: p, snap: .none)
        case .pen:
            activeTouch = t
            mode = .pen
            penStart = t.location(in: self)
            penMoved = false
            penGrab = state.penTouchDown(at: canvasPoint(t, in: state), tolerance: penTolerance(state))
        case .node:
            activeTouch = t
            mode = .node
            penStart = t.location(in: self)
            penMoved = false
            nodeGrab = state.nodeTouchDown(at: canvasPoint(t, in: state), tolerance: penTolerance(state), time: t.timestamp)
        case .brush, .eraser, .smudge:
            guard let target = state.beginStroke() else { return }
            activeTouch = t
            mode = .stroke
            strokeTarget = target
            builder.begin()
            feed(touch: t, event: event)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = activeTouch, touches.contains(t), let state else { return }
        switch mode {
        case .stroke: feed(touch: t, event: event)
        case .pen:
            let v = t.location(in: self)
            if hypot(v.x - penStart.x, v.y - penStart.y) > 4 { penMoved = true }
            if penMoved, let grab = penGrab {
                state.penDrag(grab, to: canvasPoint(t, in: state), tolerance: penTolerance(state))
            }
        case .node:
            let v = t.location(in: self)
            if hypot(v.x - penStart.x, v.y - penStart.y) > 4 { penMoved = true }
            if penMoved { state.nodeDrag(nodeGrab, to: canvasPoint(t, in: state)) }
        case .shape:
            guard var draft = state.shapeDraft else { break }
            let (end, snap) = ShapeGeometry.snapped(state.shapeOptions.kind, from: draft.from, to: canvasPoint(t, in: state))
            // A light tap when it clicks into a square, a circle or a 45° line.
            if snap != .none && snap != draft.snap { haptics.impactOccurred() }
            draft.to = end
            draft.snap = snap
            state.shapeDraft = draft
        case .lasso where state.select.shape == .rect:
            guard let start = moveStart else { break }
            state.lassoPoints = state.selectionRect(from: start.canvas, to: canvasPoint(t, in: state))
        case .lasso:
            for s in event?.coalescedTouches(for: t) ?? [t] {
                let p = canvasPoint(s, in: state)
                if let last = state.lassoPoints.last, hypot(p.x - last.x, p.y - last.y) < 1.5 { continue }
                state.lassoPoints.append(p)
            }
        case .tap:
            // Move: dragging a stroke picks it up and moves it in one gesture.
            guard state.tool == .move, let start = moveStart,
                  hypot(t.location(in: self).x - start.view.x, t.location(in: self).y - start.view.y) > 6 else { break }
            state.liftForMove(at: start.canvas)
            mode = state.selection == nil ? .tap : .moveDrag
            if mode == .tap { moveStart = nil }
            fallthrough
        case .moveDrag:
            guard mode == .moveDrag, let start = moveStart else { break }
            let p = canvasPoint(t, in: state)
            let placed = state.movedOffset(CGVector(dx: p.x - start.canvas.x, dy: p.y - start.canvas.y), home: 0)
            state.updateSelection { $0.offset = placed }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = activeTouch, touches.contains(t), let state else { return }
        activeTouch = nil
        defer { touchLive = false }
        switch mode {
        case .moveDrag:
            moveStart = nil
        case .tap:
            moveStart = nil
            let p = canvasPoint(t, in: state)
            let point = SIMD2<Float>(Float(p.x), Float(p.y))
            switch state.tool {
            case .fill: state.fill(at: point)
            // The stroke under the tap; on a blank spot, puts down what's floating (or, with
            // nothing floating, picks up the whole drawing).
            case .move: state.liftForMove(at: p, dropOnMiss: state.selection != nil)
            case .lasso: state.wandSelect(at: p)
            default: state.pickColor(at: point)
            }
        case .lasso:
            let start = moveStart?.canvas
            moveStart = nil
            if state.select.shape == .rect, let start {
                state.selectRect(from: start, to: canvasPoint(t, in: state))
            } else {
                state.selectPolygon(state.lassoPoints)
            }
        case .shape:
            if let draft = state.shapeDraft { state.drawShape(from: draft.from, to: draft.to) }
        case .pen:
            if let grab = penGrab { state.penTouchUp(grab, moved: penMoved) }
            penGrab = nil
        case .node:
            state.nodeTouchUp(nodeGrab, moved: penMoved)
            nodeGrab = .nothing
        case .stroke:
            feed(touch: t, event: event)
            endStroke()
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch != nil else { return }
        activeTouch = nil
        touchLive = false
        switch mode {
        case .tap, .moveDrag: moveStart = nil
        case .lasso: state?.lassoPoints = []; moveStart = nil
        case .shape: state?.shapeDraft = nil
        case .pen: penGrab = nil
        case .node:
            state?.nodeTouchCancelled()
            nodeGrab = .nothing
        case .stroke:
            strokeTarget = nil
            state?.cancelStroke()
        }
    }

    /// How near a point or the line counts as on it, in canvas pixels: a fingertip, whatever the zoom.
    private func penTolerance(_ state: EditorState) -> CGFloat {
        let t = state.canvasTransform.canvasToView(canvas: state.renderer.canvasSize, viewSize: bounds.size)
        return 22 / max(hypot(t.a, t.b), 0.0001)
    }

    private func endStroke() {
        if let state, let target = strokeTarget {
            let tail = builder.finish()
            if !tail.isEmpty { state.paintStroke(tail, into: target) }
        }
        activeTouch = nil
        strokeTarget = nil
        state?.strokeEnded()
    }

    private func feed(touch: UITouch, event: UIEvent?) {
        guard let state, let target = strokeTarget else { return }
        let renderer = state.renderer
        let samples = event?.coalescedTouches(for: touch) ?? [touch]

        builder.baseRadius = state.toolSize
        builder.use(state.activeBrush)
        builder.smoothing = state.tool == .eraser || state.tool == .smudge ? 0 : state.smoothing
        var stamps: [CanvasRenderer.Stamp] = []
        for s in samples {
            let canvasPos = renderer.canvasPoint(fromViewPoint: s.preciseLocation(in: self),
                                                 viewSize: bounds.size, transform: state.canvasTransform)
            // Without pressure every stroke is the full size, Pencil or finger. Pixel art never
            // follows it: a line one pixel wide stays one pixel wide.
            let force: Float = !state.usePressure || state.project.pixelArt ? 1
                : s.type == .pencil ? Float(s.force / max(s.maximumPossibleForce, 1))
                : 0.5
            // 0 upright, 1 flat on the glass; fingers don't lean.
            let tilt: Float = s.type == .pencil && !state.project.pixelArt ? Float(1 - s.altitudeAngle / (.pi / 2)) : 0
            stamps += builder.add(.init(position: canvasPos, force: force, tilt: tilt))
        }
        state.paintStroke(stamps, into: target)

        if let lastSample = samples.last {
            let ms = (CACurrentMediaTime() - lastSample.timestamp) * 1000
            onLatencySample?(ms)
        }
    }
}

extension CanvasUIView: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { redraw() }

    func draw(in view: MTKView) {
        // MTKView calls this on the main thread.
        MainActor.assumeIsolated {
            guard let state else { return }
            // Whatever this frame reads from the editor is watched: the next change to any of it
            // (the playhead, a layer, the zoom, an edit…) asks for another frame. Nothing else does.
            let (layers, grid, target) = withObservationTracking {
                _ = state.canvasVersion
                return (state.visibleLayers(), state.workspaceGrid, state.canvasTransform)
            } onChange: { [weak self] in
                DispatchQueue.main.async { self?.redraw() }
            }
            guard let drawable = view.currentDrawable else { return }
            state.renderer.showsWorkspaceGrid = grid
            var transform = target
            transform.insets = insets(toward: transform.insets)
            state.renderer.present(layers, to: drawable, viewSize: view.drawableSize,
                                   transform: transform, unitsPerPoint: view.contentScaleFactor)
        }
    }
}

// MARK: - Gestures

extension CanvasUIView: UIGestureRecognizerDelegate {
    private func installGestures() {
        let fingers = [NSNumber(value: UITouch.TouchType.direct.rawValue)]

        let undoTap = UITapGestureRecognizer(target: self, action: #selector(undoTapped))
        undoTap.numberOfTouchesRequired = 2
        let redoTap = UITapGestureRecognizer(target: self, action: #selector(redoTapped))
        redoTap.numberOfTouchesRequired = 3

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched))
        let rotate = UIRotationGestureRecognizer(target: self, action: #selector(rotated))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2

        // Three fingers down pushes everything but the canvas away (Zen); three fingers up brings it
        // back. The same way the timeline's grip hides it and shows it again.
        let zenIn = UISwipeGestureRecognizer(target: self, action: #selector(swipedIntoZen))
        zenIn.direction = .down
        let zenOut = UISwipeGestureRecognizer(target: self, action: #selector(swipedOutOfZen))
        zenOut.direction = .up

        for g in [zenIn, zenOut] {
            g.numberOfTouchesRequired = 3
            redoTap.require(toFail: g)
        }

        for g in [undoTap, redoTap, pinch, rotate, pan, zenIn, zenOut] as [UIGestureRecognizer] {
            g.allowedTouchTypes = fingers
            g.delegate = self
            addGestureRecognizer(g)
        }
    }

    /// Zoom and twist are two-finger gestures: with three down, it's a swipe for Zen.
    override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        if g is UIPinchGestureRecognizer || g is UIRotationGestureRecognizer { return g.numberOfTouches <= 2 }
        return true
    }

    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // Pinch, twist and drag happen together; taps stay exclusive.
        !(g is UITapGestureRecognizer) && !(other is UITapGestureRecognizer)
    }

    @objc private func undoTapped() { state?.undo() }
    @objc private func redoTapped() { state?.redo() }

    @objc private func swipedIntoZen() {
        guard let state, !state.isZen else { return }
        state.isZen = true
        haptics.impactOccurred()
    }

    @objc private func swipedOutOfZen() {
        guard let state, state.isZen else { return }
        state.isZen = false
        haptics.impactOccurred()
    }

    // The fingers' own scale, rotation and position, before snapping; the canvas follows them
    // except near upright, fitted or centred, where it clicks in place (with a light haptic tap).

    @objc private func pinched(_ g: UIPinchGestureRecognizer) {
        guard let state else { return }
        track(g)
        if g.state == .began { scaleIntent = state.canvasTransform.scale }
        guard g.state == .changed else { snaps.remove(.scale); return }
        let range = CanvasTransform.scaleRange
        scaleIntent = min(max(scaleIntent * g.scale, range.lowerBound), range.upperBound)
        let snap = CanvasTransform.snappedScale(scaleIntent)
        click(.scale, snap != nil)
        let target = snap ?? scaleIntent
        if target != state.canvasTransform.scale {
            state.canvasTransform.zoom(by: target / state.canvasTransform.scale, around: g.location(in: self), viewSize: bounds.size)
        }
        if let snap { state.canvasTransform.scale = snap }      // exactly, so "fitted" is fitted
        g.scale = 1
    }

    @objc private func rotated(_ g: UIRotationGestureRecognizer) {
        guard let state else { return }
        track(g)
        if g.state == .began { rotationIntent = state.canvasTransform.rotation }
        guard g.state == .changed else { snaps.remove(.rotation); return }
        rotationIntent += g.rotation
        let snap = CanvasTransform.snappedRotation(rotationIntent)
        click(.rotation, snap != nil)
        let target = snap ?? rotationIntent
        if target != state.canvasTransform.rotation {
            state.canvasTransform.rotate(by: target - state.canvasTransform.rotation, around: g.location(in: self), viewSize: bounds.size)
        }
        if let snap { state.canvasTransform.rotation = snap }
        g.rotation = 0
    }

    @objc private func panned(_ g: UIPanGestureRecognizer) {
        guard let state else { return }
        track(g)
        if g.state == .began { offsetIntent = state.canvasTransform.offset }
        guard g.state == .changed else { snaps.remove(.offset); return }
        let t = g.translation(in: self)
        // Zoom and twist move the offset too; follow them, then add the drag.
        if snaps.contains(.offset) == false { offsetIntent = state.canvasTransform.offset }
        offsetIntent.width += t.x
        offsetIntent.height += t.y
        let snap = CanvasTransform.snappedOffset(offsetIntent)
        click(.offset, snap != nil)
        state.canvasTransform.offset = snap ?? offsetIntent
        g.setTranslation(.zero, in: self)
    }

    private func track(_ g: UIGestureRecognizer) {
        let id = ObjectIdentifier(g)
        switch g.state {
        case .began, .changed: if !gesturesLive.contains(id) { gesturesLive.insert(id) }
        default: gesturesLive.remove(id)
        }
    }

    /// A haptic tap when something clicks into place (not while it stays there).
    private func click(_ kind: Snap, _ now: Bool) {
        if now && !snaps.contains(kind) { haptics.impactOccurred() }
        if now { snaps.insert(kind) } else { snaps.remove(kind) }
    }
}

// MARK: - SwiftUI bridge

struct CanvasView: UIViewRepresentable {
    @Bindable var state: EditorState
    @Binding var latencyMs: Double

    func makeUIView(context: Context) -> CanvasUIView {
        let v = CanvasUIView(frame: .zero)
        v.state = state
        // Only when the readout is on, and at most 10 times a second: every sample would redraw
        // the whole editor while you draw.
        var last: CFTimeInterval = 0
        v.onLatencySample = { ms in
            guard UserDefaults.standard.bool(forKey: "showLatency") else { return }
            let now = CACurrentMediaTime()
            guard now - last > 0.1 else { return }
            last = now
            DispatchQueue.main.async { latencyMs = ms }
        }
        return v
    }

    func updateUIView(_ uiView: CanvasUIView, context: Context) {
        uiView.state = state
    }
}

// MARK: - Apple Pencil double tap / squeeze

/// Does what the user picked in Settings → Apple Pencil: switch to the eraser and back, switch to
/// the previous tool, or show the colours.
extension CanvasUIView: UIPencilInteractionDelegate {
    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
        perform(UIPencilInteraction.preferredTapAction)
    }

    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        guard squeeze.phase == .ended else { return }
        perform(UIPencilInteraction.preferredSqueezeAction)
    }

    /// Before iPadOS 17.5.
    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        perform(UIPencilInteraction.preferredTapAction)
    }

    private func perform(_ action: UIPencilPreferredAction) {
        guard let state, !state.isPlaying else { return }
        switch action {
        case .switchEraser: state.pencilSwitchEraser()
        case .switchPrevious: state.pencilSwitchPrevious()
        case .showColorPalette: state.colorPickerRequest += 1
        default:
            if #available(iOS 17.5, *), action == .showContextualPalette { state.colorPickerRequest += 1 }
        }
    }
}
