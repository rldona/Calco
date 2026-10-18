import UIKit
import MetalKit
import SwiftUI

/// UIKit view that owns the MTKView and handles Apple Pencil input.
/// Paints into whatever `EditorState.paintTarget` says, and composites
/// `EditorState.visibleLayers()` every display refresh.
final class CanvasUIView: UIView {

    private let mtkView = MTKView()
    private var builder = StrokeBuilder()
    private var activeTouch: UITouch?
    private var strokeTarget: MTLTexture?

    weak var state: EditorState?
    var onLatencySample: ((Double) -> Void)?

    static let screenFormat: MTLPixelFormat = .bgra8Unorm

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = false
        backgroundColor = .clear

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

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let t = touches.first,
              let state, !state.isPlaying,
              let target = state.beginStroke() else { return }
        activeTouch = t
        strokeTarget = target
        builder.begin()
        feed(touch: t, event: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = activeTouch, touches.contains(t) else { return }
        feed(touch: t, event: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = activeTouch, touches.contains(t) else { return }
        feed(touch: t, event: event)
        endStroke()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        endStroke()
    }

    private func endStroke() {
        activeTouch = nil
        strokeTarget = nil
        state?.strokeEnded()
    }

    private func feed(touch: UITouch, event: UIEvent?) {
        guard let state, let target = strokeTarget else { return }
        let renderer = state.renderer
        let samples = event?.coalescedTouches(for: touch) ?? [touch]
        let scale = window?.screen.scale ?? UIScreen.main.scale
        let viewSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)

        builder.baseRadius = state.tool == .eraser ? 18 : 6
        var stamps: [CanvasRenderer.Stamp] = []
        for s in samples {
            let p = s.preciseLocation(in: self)
            let px = CGPoint(x: p.x * scale, y: p.y * scale)
            let canvasPos = renderer.canvasPoint(fromViewPixel: px, viewSize: viewSize)
            let force: Float = s.type == .pencil
                ? Float(s.force / max(s.maximumPossibleForce, 1))
                : 0.5
            stamps += builder.add(.init(position: canvasPos, force: force))
        }
        renderer.paint(stamps, into: target, color: SIMD4<Float>(0, 0, 0, 1), tool: state.tool)

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
            state.renderer.present(state.visibleLayers(), to: drawable, viewSize: view.drawableSize)
        }
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
