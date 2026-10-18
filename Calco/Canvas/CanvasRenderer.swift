import Metal
import MetalKit
import simd

/// Owns the canvas texture and draws strokes into it.
/// Knows nothing about UIKit or SwiftUI; feed it points, ask it to present.
final class CanvasRenderer {

    struct Stamp {
        var position: SIMD2<Float>
        var radius: Float
        var alpha: Float
    }

    private struct Uniforms {
        var canvasSize: SIMD2<Float>
        var color: SIMD4<Float>
    }

    let device: MTLDevice
    let canvasSize: SIMD2<Int>
    private let queue: MTLCommandQueue
    private let stampPipeline: MTLRenderPipelineState
    private let blitPipeline: MTLRenderPipelineState
    private(set) var canvasTexture: MTLTexture

    /// Straight-alpha ink color.
    var color = SIMD4<Float>(0, 0, 0, 1)

    private var pendingStamps: [Stamp] = []
    private var stampBuffer: MTLBuffer?
    private var stampBufferCapacity = 0

    init?(device: MTLDevice, canvasSize: SIMD2<Int>, pixelFormat: MTLPixelFormat) {
        self.device = device
        self.canvasSize = canvasSize
        guard let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else { return nil }
        self.queue = queue

        // Stroke pipeline: premultiplied "over" onto the canvas texture
        let stampDesc = MTLRenderPipelineDescriptor()
        stampDesc.vertexFunction = library.makeFunction(name: "stamp_vertex")
        stampDesc.fragmentFunction = library.makeFunction(name: "stamp_fragment")
        stampDesc.colorAttachments[0].pixelFormat = .rgba8Unorm
        stampDesc.colorAttachments[0].isBlendingEnabled = true
        stampDesc.colorAttachments[0].sourceRGBBlendFactor = .one
        stampDesc.colorAttachments[0].sourceAlphaBlendFactor = .one
        stampDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        stampDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        // Blit pipeline: canvas texture -> screen
        let blitDesc = MTLRenderPipelineDescriptor()
        blitDesc.vertexFunction = library.makeFunction(name: "blit_vertex")
        blitDesc.fragmentFunction = library.makeFunction(name: "blit_fragment")
        blitDesc.colorAttachments[0].pixelFormat = pixelFormat
        blitDesc.colorAttachments[0].isBlendingEnabled = true
        blitDesc.colorAttachments[0].sourceRGBBlendFactor = .one
        blitDesc.colorAttachments[0].sourceAlphaBlendFactor = .one
        blitDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        blitDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: canvasSize.x, height: canvasSize.y, mipmapped: false)
        texDesc.usage = [.renderTarget, .shaderRead]
        texDesc.storageMode = .private

        do {
            stampPipeline = try device.makeRenderPipelineState(descriptor: stampDesc)
            blitPipeline = try device.makeRenderPipelineState(descriptor: blitDesc)
            guard let tex = device.makeTexture(descriptor: texDesc) else { return nil }
            canvasTexture = tex
        } catch {
            assertionFailure("Pipeline creation failed: \(error)")
            return nil
        }
        clear()
    }

    // MARK: - Input

    /// Queue stamps for the next flush. Positions are in canvas pixels.
    func enqueue(_ stamps: [Stamp]) {
        pendingStamps.append(contentsOf: stamps)
    }

    func clear() {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = canvasTexture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let cmd = queue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.endEncoding()
        cmd.commit()
    }

    // MARK: - Rendering

    /// Flush pending stamps into the canvas texture, then present the canvas
    /// into `drawable`, letterboxed inside `viewSize` (points * scale).
    func draw(to drawable: CAMetalDrawable, viewSize: CGSize) {
        guard let cmd = queue.makeCommandBuffer() else { return }

        if !pendingStamps.isEmpty {
            encodeStamps(into: cmd)
            pendingStamps.removeAll(keepingCapacity: true)
        }

        encodeBlit(into: cmd, drawable: drawable, viewSize: viewSize)
        cmd.present(drawable)
        cmd.commit()
    }

    private func encodeStamps(into cmd: MTLCommandBuffer) {
        let count = pendingStamps.count
        let bytes = count * MemoryLayout<Stamp>.stride
        if stampBufferCapacity < count {
            stampBufferCapacity = max(count, 4096)
            stampBuffer = device.makeBuffer(length: stampBufferCapacity * MemoryLayout<Stamp>.stride,
                                            options: .storageModeShared)
        }
        guard let buffer = stampBuffer else { return }
        pendingStamps.withUnsafeBytes { src in
            buffer.contents().copyMemory(from: src.baseAddress!, byteCount: bytes)
        }

        var uniforms = Uniforms(canvasSize: SIMD2<Float>(Float(canvasSize.x), Float(canvasSize.y)),
                                color: color)

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = canvasTexture
        pass.colorAttachments[0].loadAction = .load
        pass.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(stampPipeline)
        enc.setVertexBuffer(buffer, offset: 0, index: 0)
        enc.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        enc.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: count)
        enc.endEncoding()
    }

    private func encodeBlit(into cmd: MTLCommandBuffer, drawable: CAMetalDrawable, viewSize: CGSize) {
        var rect = Self.fitRectNDC(canvas: canvasSize, in: viewSize)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(blitPipeline)
        enc.setVertexBytes(&rect, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        enc.setFragmentTexture(canvasTexture, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        enc.endEncoding()
    }

    // MARK: - Geometry

    /// Where the canvas sits on screen, in NDC (x, y, w, h), aspect-fit with margin.
    static func fitRectNDC(canvas: SIMD2<Int>, in view: CGSize) -> SIMD4<Float> {
        let r = fitRect(canvas: canvas, in: view)
        let x = Float(r.minX / view.width) * 2 - 1
        let y = Float(1 - r.maxY / view.height) * 2 - 1
        let w = Float(r.width / view.width) * 2
        let h = Float(r.height / view.height) * 2
        return SIMD4<Float>(x, y, w, h)
    }

    /// Same, in view pixel coordinates (origin top-left).
    static func fitRect(canvas: SIMD2<Int>, in view: CGSize, margin: CGFloat = 0.9) -> CGRect {
        let cw = CGFloat(canvas.x), ch = CGFloat(canvas.y)
        let scale = min(view.width / cw, view.height / ch) * margin
        let w = cw * scale, h = ch * scale
        return CGRect(x: (view.width - w) / 2, y: (view.height - h) / 2, width: w, height: h)
    }

    /// Convert a point in view pixels to canvas pixels.
    func canvasPoint(fromViewPixel p: CGPoint, viewSize: CGSize) -> SIMD2<Float> {
        let r = Self.fitRect(canvas: canvasSize, in: viewSize)
        let x = (p.x - r.minX) / r.width * CGFloat(canvasSize.x)
        let y = (p.y - r.minY) / r.height * CGFloat(canvasSize.y)
        return SIMD2<Float>(Float(x), Float(y))
    }
}
