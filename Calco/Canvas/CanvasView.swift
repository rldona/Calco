import UIKit
import MetalKit
import SwiftUI

/// UIKit view that owns the MTKView and handles Apple Pencil input.
/// Uses coalesced touches for full 240 Hz sampling and renders on every
/// display refresh. No predicted touches yet (they need an overlay layer
/// that gets rewound); measure latency first, add prediction if needed.
final class CanvasUIView: UIView {

    private let mtkView = MTKView()
    private var renderer: CanvasRenderer?
    private var builder = StrokeBuilder()
    private var activeTouch: UITouch?

    /// Called on the main thread with the latency estimate (ms) of the last stroke segment.
    var onLatencySample: ((Double) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = false
        backgroundColor = .clear

        guard let device = MTLCreateSystemDefaultDevice() else { return }
        mtkView.device = device
        mtkView.colorPixelFormat = .bgra8Unorm
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

        renderer = CanvasRenderer(device: device,
                                  canvasSize: SIMD2<Int>(1024, 1024),
                                  pixelFormat: mtkView.colorPixelFormat)
    }

    required init?(coder: NSCoder) { fatalError() }

    func clear() { renderer?.clear() }

    // MARK: - Touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let t = touches.first else { return }
        activeTouch = t
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
        activeTouch = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        activeTouch = nil
    }

    private func feed(touch: UITouch, event: UIEvent?) {
        guard let renderer else { return }
        let samples = event?.coalescedTouches(for: touch) ?? [touch]
        let scale = window?.screen.scale ?? UIScreen.main.scale
        let viewSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)

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
        renderer.enqueue(stamps)

        if let lastSample = samples.last {
            let ms = (CACurrentMediaTime() - lastSample.timestamp) * 1000
            onLatencySample?(ms)
        }
    }
}

extension CanvasUIView: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let renderer, let drawable = view.currentDrawable else { return }
        renderer.draw(to: drawable, viewSize: view.drawableSize)
    }
}

// MARK: - SwiftUI bridge

struct CanvasView: UIViewRepresentable {
    @Binding var latencyMs: Double
    var clearToken: Int

    func makeUIView(context: Context) -> CanvasUIView {
        let v = CanvasUIView(frame: .zero)
        v.onLatencySample = { ms in
            DispatchQueue.main.async { latencyMs = ms }
        }
        return v
    }

    func updateUIView(_ uiView: CanvasUIView, context: Context) {
        if context.coordinator.lastClearToken != clearToken {
            context.coordinator.lastClearToken = clearToken
            uiView.clear()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastClearToken = 0
    }
}
