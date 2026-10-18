import UIKit
import MetalKit
import SwiftUI

/// UIKit view that owns the MTKView and handles Apple Pencil input.
/// Paints into whatever `EditorState.beginStroke()` hands out, and composites
/// `EditorState.visibleLayers()` every display refresh.
///
/// Finger gestures (Pencil never triggers them): two-finger tap undo, three-finger tap redo,
/// pinch / two-finger drag / twist to zoom, pan and rotate. A finger stroke that turns into
/// one of these is cancelled and leaves no trace.
final class CanvasUIView: UIView {

    private let mtkView = MTKView()
    private var builder = StrokeBuilder()
    private var activeTouch: UITouch?
    /// What the active touch is doing: painting, a tap for fill / eyedropper (acted on when it
    /// lifts), or drawing a lasso.
    private enum Mode { case stroke, tap, lasso }
    private var mode = Mode.stroke
    private var strokeTarget: MTLTexture?

    weak var state: EditorState?
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
        mtkView.isPaused = false
        mtkView.enableSetNeedsDisplay = false
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

    // MARK: - Touch handling

    private func canvasPoint(_ t: UITouch, in state: EditorState) -> CGPoint {
        let p = state.renderer.canvasPoint(fromViewPoint: t.location(in: self), viewSize: bounds.size,
                                           transform: state.canvasTransform)
        return CGPoint(x: CGFloat(p.x), y: CGFloat(p.y))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let t = touches.first, let state, !state.isPlaying else { return }
        // Pencil only: a finger on the canvas is for gestures, never a mark.
        if state.pencilOnly && t.type != .pencil { return }
        switch state.tool {
        case .fill, .eyedropper:
            // Wait for the lift: if it turns into a pinch or two-finger tap, touchesCancelled drops it.
            activeTouch = t
            mode = .tap
        case .lasso:
            // Touching the canvas outside a floating selection drops it and starts a new lasso.
            state.commitSelection()
            activeTouch = t
            mode = .lasso
            state.lassoPoints = [canvasPoint(t, in: state)]
        case .brush, .eraser:
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
        case .lasso:
            for s in event?.coalescedTouches(for: t) ?? [t] {
                let p = canvasPoint(s, in: state)
                if let last = state.lassoPoints.last, hypot(p.x - last.x, p.y - last.y) < 1.5 { continue }
                state.lassoPoints.append(p)
            }
        case .tap: break
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = activeTouch, touches.contains(t), let state else { return }
        activeTouch = nil
        switch mode {
        case .tap:
            let p = canvasPoint(t, in: state)
            let point = SIMD2<Float>(Float(p.x), Float(p.y))
            if state.tool == .fill { state.fill(at: point) } else { state.pickColor(at: point) }
        case .lasso:
            state.liftSelection(state.lassoPoints)
        case .stroke:
            feed(touch: t, event: event)
            endStroke()
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch != nil else { return }
        activeTouch = nil
        switch mode {
        case .tap: break
        case .lasso: state?.lassoPoints = []
        case .stroke:
            strokeTarget = nil
            state?.cancelStroke()
        }
    }

    private func endStroke() {
        if let state, let target = strokeTarget {
            let tail = builder.finish()
            if !tail.isEmpty { state.renderer.paint(tail, into: target, color: state.color, tool: state.tool, hard: state.project.pixelArt, mode: state.paintMode) }
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
        builder.smoothing = state.tool == .eraser ? 0 : state.smoothing
        var stamps: [CanvasRenderer.Stamp] = []
        for s in samples {
            let canvasPos = renderer.canvasPoint(fromViewPoint: s.preciseLocation(in: self),
                                                 viewSize: bounds.size, transform: state.canvasTransform)
            // Without pressure every stroke is the full size, Pencil or finger.
            let force: Float = !state.usePressure ? 1
                : s.type == .pencil ? Float(s.force / max(s.maximumPossibleForce, 1))
                : 0.5
            stamps += builder.add(.init(position: canvasPos, force: force))
        }
        renderer.paint(stamps, into: target, color: state.color, tool: state.tool, hard: state.project.pixelArt, mode: state.paintMode)

        if let lastSample = samples.last {
            let ms = (CACurrentMediaTime() - lastSample.timestamp) * 1000
            onLatencySample?(ms)
        }
    }
}

extension CanvasUIView: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        // MTKView calls this on the main thread.
        MainActor.assumeIsolated {
            guard let state, let drawable = view.currentDrawable else { return }
            state.renderer.present(state.visibleLayers(), to: drawable, viewSize: view.drawableSize,
                                   transform: state.canvasTransform, unitsPerPoint: view.contentScaleFactor)
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

        for g in [undoTap, redoTap, pinch, rotate, pan] as [UIGestureRecognizer] {
            g.allowedTouchTypes = fingers
            g.delegate = self
            addGestureRecognizer(g)
        }
    }

    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // Pinch, twist and drag happen together; taps stay exclusive.
        !(g is UITapGestureRecognizer) && !(other is UITapGestureRecognizer)
    }

    @objc private func undoTapped() { state?.undo() }
    @objc private func redoTapped() { state?.redo() }

    @objc private func pinched(_ g: UIPinchGestureRecognizer) {
        guard let state, g.state == .changed else { return }
        state.canvasTransform.zoom(by: g.scale, around: g.location(in: self), viewSize: bounds.size)
        g.scale = 1
    }

    @objc private func rotated(_ g: UIRotationGestureRecognizer) {
        guard let state, g.state == .changed else { return }
        state.canvasTransform.rotate(by: g.rotation, around: g.location(in: self), viewSize: bounds.size)
        g.rotation = 0
    }

    @objc private func panned(_ g: UIPanGestureRecognizer) {
        guard let state, g.state == .changed else { return }
        let t = g.translation(in: self)
        state.canvasTransform.pan(by: CGSize(width: t.x, height: t.y))
        g.setTranslation(.zero, in: self)
    }
}

// MARK: - SwiftUI bridge

struct CanvasView: UIViewRepresentable {
    @ObservedObject var state: EditorState
    @Binding var latencyMs: Double

    func makeUIView(context: Context) -> CanvasUIView {
        let v = CanvasUIView(frame: .zero)
        v.state = state
        v.onLatencySample = { ms in
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
