import Metal
import MetalKit
import simd
import CoreGraphics

/// Low-level GPU work: allocate layer textures, paint stamps into them,
/// composite a list of layers onto a drawable or a thumbnail.
/// Knows nothing about frames, clips, UIKit or SwiftUI.
final class CanvasRenderer {

    struct Stamp {
        var position: SIMD2<Float>
        var radius: Float
        var alpha: Float
    }

    private struct StampUniforms {
        var canvasSize: SIMD2<Float>
        var color: SIMD4<Float>
    }

    /// One layer to composite, bottom to top.
    struct CompositeLayer {
        var texture: MTLTexture
        var opacity: Float = 1
        var tint: SIMD3<Float> = .zero
        var tintAmount: Float = 0
    }

    private struct CompositeUniforms {
        var rect: SIMD4<Float>
        var tint: SIMD4<Float>
        var opacity: Float
        var tintAmount: Float
        var canvasSize: SIMD2<Float>
    }

    enum Tool { case brush, eraser }

    let device: MTLDevice
    let canvasSize: SIMD2<Int>
    private let queue: MTLCommandQueue
    private let brushPipeline: MTLRenderPipelineState
    private let eraserPipeline: MTLRenderPipelineState
    private let screenCompositePipeline: MTLRenderPipelineState
    private let screenCheckerPipeline: MTLRenderPipelineState
    private let thumbCompositePipeline: MTLRenderPipelineState
    private let thumbCheckerPipeline: MTLRenderPipelineState

    private var stampBuffer: MTLBuffer?
    private var stampBufferCapacity = 0

    private static let layerFormat: MTLPixelFormat = .rgba8Unorm

    init?(device: MTLDevice, canvasSize: SIMD2<Int>, screenFormat: MTLPixelFormat) {
        self.device = device
        self.canvasSize = canvasSize
        guard let queue = device.makeCommandQueue(),
              let lib = device.makeDefaultLibrary() else { return nil }
        self.queue = queue

        func premultipliedOver(_ d: MTLRenderPipelineDescriptor, format: MTLPixelFormat) {
            let a = d.colorAttachments[0]!
            a.pixelFormat = format
            a.isBlendingEnabled = true
            a.sourceRGBBlendFactor = .one
            a.sourceAlphaBlendFactor = .one
            a.destinationRGBBlendFactor = .oneMinusSourceAlpha
            a.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }

        let brush = MTLRenderPipelineDescriptor()
        brush.vertexFunction = lib.makeFunction(name: "stamp_vertex")
        brush.fragmentFunction = lib.makeFunction(name: "stamp_fragment")
        premultipliedOver(brush, format: Self.layerFormat)

        let eraser = MTLRenderPipelineDescriptor()
        eraser.vertexFunction = lib.makeFunction(name: "stamp_vertex")
        eraser.fragmentFunction = lib.makeFunction(name: "eraser_fragment")
        premultipliedOver(eraser, format: Self.layerFormat)
        eraser.colorAttachments[0].sourceRGBBlendFactor = .zero
        eraser.colorAttachments[0].sourceAlphaBlendFactor = .zero

        func composite(_ fragment: String, format: MTLPixelFormat) -> MTLRenderPipelineDescriptor {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = lib.makeFunction(name: "composite_vertex")
            d.fragmentFunction = lib.makeFunction(name: fragment)
            premultipliedOver(d, format: format)
            return d
        }

        do {
            brushPipeline = try device.makeRenderPipelineState(descriptor: brush)
            eraserPipeline = try device.makeRenderPipelineState(descriptor: eraser)
            screenCompositePipeline = try device.makeRenderPipelineState(descriptor: composite("composite_fragment", format: screenFormat))
            screenCheckerPipeline = try device.makeRenderPipelineState(descriptor: composite("checker_fragment", format: screenFormat))
            thumbCompositePipeline = try device.makeRenderPipelineState(descriptor: composite("composite_fragment", format: Self.layerFormat))
            thumbCheckerPipeline = try device.makeRenderPipelineState(descriptor: composite("checker_fragment", format: Self.layerFormat))
        } catch {
            assertionFailure("Pipeline creation failed: \(error)")
            return nil
        }
    }

    // MARK: - Layer textures

    func makeLayerTexture() -> MTLTexture? {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Self.layerFormat, width: canvasSize.x, height: canvasSize.y, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .private
        guard let t = device.makeTexture(descriptor: d) else { return nil }
        clear(t)
        return t
    }

    func clear(_ texture: MTLTexture) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let cmd = queue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.endEncoding()
        cmd.commit()
    }

    func copy(_ source: MTLTexture, to destination: MTLTexture) {
        guard let cmd = queue.makeCommandBuffer(),
              let blit = cmd.makeBlitCommandEncoder() else { return }
        blit.copy(from: source, to: destination)
        blit.endEncoding()
        cmd.commit()
    }

    // MARK: - Painting

    /// Paint stamps into `target` immediately (own command buffer).
    func paint(_ stamps: [Stamp], into target: MTLTexture, color: SIMD4<Float>, tool: Tool) {
        guard !stamps.isEmpty, let cmd = queue.makeCommandBuffer() else { return }
        let count = stamps.count
        if stampBufferCapacity < count {
            stampBufferCapacity = max(count, 4096)
            stampBuffer = device.makeBuffer(length: stampBufferCapacity * MemoryLayout<Stamp>.stride,
                                            options: .storageModeShared)
        }
        guard let buffer = stampBuffer else { return }
        stamps.withUnsafeBytes { src in
            buffer.contents().copyMemory(from: src.baseAddress!, byteCount: count * MemoryLayout<Stamp>.stride)
        }
        var uniforms = StampUniforms(canvasSize: SIMD2<Float>(Float(canvasSize.x), Float(canvasSize.y)), color: color)

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .load
        pass.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(tool == .brush ? brushPipeline : eraserPipeline)
        enc.setVertexBuffer(buffer, offset: 0, index: 0)
        enc.setVertexBytes(&uniforms, length: MemoryLayout<StampUniforms>.stride, index: 1)
        enc.setFragmentBytes(&uniforms, length: MemoryLayout<StampUniforms>.stride, index: 1)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: count)
        enc.endEncoding()
        cmd.commit()
    }

    // MARK: - Compositing

    /// Composite `layers` (bottom to top) over a checkerboard into the drawable.
    func present(_ layers: [CompositeLayer], to drawable: CAMetalDrawable, viewSize: CGSize) {
        guard let cmd = queue.makeCommandBuffer() else { return }
        let rect = Self.fitRectNDC(canvas: canvasSize, in: viewSize)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }
        encodeComposite(enc, layers: layers, rect: rect,
                        checker: screenCheckerPipeline, composite: screenCompositePipeline)
        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }

    /// Render a small preview of `layers` and hand back a CGImage on a background queue.
    func thumbnail(_ layers: [CompositeLayer], maxSide: Int = 160, completion: @escaping (CGImage?) -> Void) {
        let aspect = Double(canvasSize.x) / Double(canvasSize.y)
        let w = aspect >= 1 ? maxSide : Int(Double(maxSide) * aspect)
        let h = aspect >= 1 ? Int(Double(maxSide) / aspect) : maxSide

        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.layerFormat, width: w, height: h, mipmapped: false)
        d.usage = [.renderTarget]
        d.storageMode = .shared
        guard let target = device.makeTexture(descriptor: d),
              let cmd = queue.makeCommandBuffer() else { completion(nil); return }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 1, green: 1, blue: 1, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { completion(nil); return }
        encodeComposite(enc, layers: layers, rect: SIMD4<Float>(-1, -1, 2, 2),
                        checker: thumbCheckerPipeline, composite: thumbCompositePipeline)
        enc.endEncoding()

        cmd.addCompletedHandler { _ in
            completion(Self.image(from: target))
        }
        cmd.commit()
    }

    // MARK: - CPU transfer

    /// Full-resolution copy of a layer as a premultiplied RGBA `CGImage`.
    /// Blocks until the GPU has finished every command queued before it on `texture`.
    func readback(_ texture: MTLTexture) -> CGImage? {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Self.layerFormat, width: texture.width, height: texture.height, mipmapped: false)
        d.storageMode = .shared
        guard let staging = device.makeTexture(descriptor: d),
              let cmd = queue.makeCommandBuffer(),
              let blit = cmd.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: texture, to: staging)
        blit.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        return Self.image(from: staging)
    }

    /// Replaces the contents of `texture` with `image`, scaled to fit if the sizes differ.
    func upload(_ image: CGImage, into texture: MTLTexture) {
        let w = texture.width, h = texture.height
        let bytesPerRow = w * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * h)
        let drawn = bytes.withUnsafeMutableBytes { ptr -> Bool in
            guard let ctx = CGContext(data: ptr.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: Self.cgBitmapInfo.rawValue) else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return }

        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.layerFormat, width: w, height: h, mipmapped: false)
        d.storageMode = .shared
        guard let staging = device.makeTexture(descriptor: d),
              let cmd = queue.makeCommandBuffer(),
              let blit = cmd.makeBlitCommandEncoder() else { return }
        bytes.withUnsafeBytes { ptr in
            staging.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0,
                            withBytes: ptr.baseAddress!, bytesPerRow: bytesPerRow)
        }
        blit.copy(from: staging, to: texture)
        blit.endEncoding()
        cmd.commit()
    }

    /// RGBA8, premultiplied, row 0 at the top: the same memory layout as `layerFormat`.
    private static let cgBitmapInfo = CGBitmapInfo(
        rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)

    /// Wraps the pixels of a shared-storage texture in a `CGImage`. The GPU must already be done with it.
    private static func image(from texture: MTLTexture) -> CGImage? {
        let w = texture.width, h = texture.height
        let bytesPerRow = w * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * h)
        bytes.withUnsafeMutableBytes { ptr in
            texture.getBytes(ptr.baseAddress!, bytesPerRow: bytesPerRow,
                             from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: cgBitmapInfo, provider: provider, decode: nil,
                       shouldInterpolate: true, intent: .defaultIntent)
    }

    private func encodeComposite(_ enc: MTLRenderCommandEncoder, layers: [CompositeLayer], rect: SIMD4<Float>,
                                 checker: MTLRenderPipelineState, composite: MTLRenderPipelineState) {
        var u = CompositeUniforms(rect: rect, tint: .zero, opacity: 1, tintAmount: 0,
                                  canvasSize: SIMD2<Float>(Float(canvasSize.x), Float(canvasSize.y)))
        enc.setRenderPipelineState(checker)
        enc.setVertexBytes(&u, length: MemoryLayout<CompositeUniforms>.stride, index: 0)
        enc.setFragmentBytes(&u, length: MemoryLayout<CompositeUniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)

        enc.setRenderPipelineState(composite)
        for layer in layers {
            u.opacity = layer.opacity
            u.tint = SIMD4<Float>(layer.tint, 1)
            u.tintAmount = layer.tintAmount
            enc.setVertexBytes(&u, length: MemoryLayout<CompositeUniforms>.stride, index: 0)
            enc.setFragmentBytes(&u, length: MemoryLayout<CompositeUniforms>.stride, index: 0)
            enc.setFragmentTexture(layer.texture, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }
    }

    // MARK: - Geometry

    static func fitRectNDC(canvas: SIMD2<Int>, in view: CGSize) -> SIMD4<Float> {
        let r = fitRect(canvas: canvas, in: view)
        let x = Float(r.minX / view.width) * 2 - 1
        let y = Float(1 - r.maxY / view.height) * 2 - 1
        let w = Float(r.width / view.width) * 2
        let h = Float(r.height / view.height) * 2
        return SIMD4<Float>(x, y, w, h)
    }

    static func fitRect(canvas: SIMD2<Int>, in view: CGSize, margin: CGFloat = 0.9) -> CGRect {
        let cw = CGFloat(canvas.x), ch = CGFloat(canvas.y)
        let scale = min(view.width / cw, view.height / ch) * margin
        let w = cw * scale, h = ch * scale
        return CGRect(x: (view.width - w) / 2, y: (view.height - h) / 2, width: w, height: h)
    }

    func canvasPoint(fromViewPixel p: CGPoint, viewSize: CGSize) -> SIMD2<Float> {
        let r = Self.fitRect(canvas: canvasSize, in: viewSize)
        let x = (p.x - r.minX) / r.width * CGFloat(canvasSize.x)
        let y = (p.y - r.minY) / r.height * CGFloat(canvasSize.y)
        return SIMD2<Float>(Float(x), Float(y))
    }
}
