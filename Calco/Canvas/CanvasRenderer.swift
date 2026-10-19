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
        var hard: Float = 0
        var hardness: Float = 1
        var grain: Float = 0
        var grainScale: Float = 2
    }

    /// The tip of a brush, as the stamp shader sees it.
    struct BrushTip {
        var hardness: Float = 1
        var grain: Float = 0
        var grainScale: Float = 2
        /// Stamps add up (over); otherwise the stroke keeps the strongest stamp at each pixel (max).
        var buildsUp = false

        init(hardness: Float = 1, grain: Float = 0, grainScale: Float = 2, buildsUp: Bool = false) {
            self.hardness = hardness; self.grain = grain; self.grainScale = grainScale; self.buildsUp = buildsUp
        }

        init(_ brush: Brush) {
            self.init(hardness: brush.hardness, grain: brush.grain, grainScale: brush.grainScale, buildsUp: brush.buildsUp)
        }
    }

    /// One layer to composite, bottom to top.
    struct CompositeLayer {
        var texture: MTLTexture
        var opacity: Float = 1
        var tint: SIMD3<Float> = .zero
        var tintAmount: Float = 0
        /// Only shows where this texture has paint: the base of a layer masked to the one below.
        var mask: MTLTexture? = nil
    }

    private struct CompositeUniforms {
        var origin: SIMD2<Float>
        var axisX: SIMD2<Float>
        var axisY: SIMD2<Float>
        var pad = SIMD2<Float>()
        var tint: SIMD4<Float>
        var opacity: Float
        var tintAmount: Float
        var canvasSize: SIMD2<Float>
        /// 1 = multiply by the mask texture's alpha (a layer masked to the one below).
        var useMask: Float = 0
    }

    /// Fill and eyedropper never reach `paint`; they act on a tap (see CanvasUIView).
    enum Tool { case brush, eraser, fill, eyedropper, lasso, move }

    /// Where new paint goes on the layer: over what's there, under it (colour under line art), or
    /// only on what's already drawn, keeping its transparency (shading).
    enum PaintMode: String, CaseIterable, Identifiable {
        case front, behind, inside
        var id: String { rawValue }
        var title: String {
            switch self {
            case .front: String(localized: "In front", bundle: AppLanguage.bundle)
            case .behind: String(localized: "Behind", bundle: AppLanguage.bundle)
            case .inside: String(localized: "Inside", bundle: AppLanguage.bundle)
            }
        }
    }

    let device: MTLDevice
    let canvasSize: SIMD2<Int>
    private let queue: MTLCommandQueue
    private let brushPipeline: MTLRenderPipelineState
    private let brushBehindPipeline: MTLRenderPipelineState
    private let brushInsidePipeline: MTLRenderPipelineState
    private let eraserPipeline: MTLRenderPipelineState
    /// Stamps into a stroke's own texture: adding up, or keeping the strongest.
    private let strokeMaxPipeline: MTLRenderPipelineState
    /// A finished-so-far stroke onto its layer: in front, behind, inside, or erasing.
    private let strokeFrontPipeline: MTLRenderPipelineState
    private let strokeBehindPipeline: MTLRenderPipelineState
    private let strokeInsidePipeline: MTLRenderPipelineState
    private let strokeErasePipeline: MTLRenderPipelineState
    private let screenCompositePipeline: MTLRenderPipelineState
    private let screenCheckerPipeline: MTLRenderPipelineState
    private let workspacePipeline: MTLRenderPipelineState
    /// The grid behind the canvas (Preferences).
    var showsWorkspaceGrid = true
    private let thumbCompositePipeline: MTLRenderPipelineState
    private let thumbCheckerPipeline: MTLRenderPipelineState


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

        // Destination over: new paint only shows where the layer is still see-through.
        let behind = MTLRenderPipelineDescriptor()
        behind.vertexFunction = brush.vertexFunction
        behind.fragmentFunction = brush.fragmentFunction
        premultipliedOver(behind, format: Self.layerFormat)
        behind.colorAttachments[0].sourceRGBBlendFactor = .oneMinusDestinationAlpha
        behind.colorAttachments[0].sourceAlphaBlendFactor = .oneMinusDestinationAlpha
        behind.colorAttachments[0].destinationRGBBlendFactor = .one
        behind.colorAttachments[0].destinationAlphaBlendFactor = .one

        // Source atop: colour lands only where there's already paint, and coverage never changes.
        let inside = MTLRenderPipelineDescriptor()
        inside.vertexFunction = brush.vertexFunction
        inside.fragmentFunction = brush.fragmentFunction
        premultipliedOver(inside, format: Self.layerFormat)
        inside.colorAttachments[0].sourceRGBBlendFactor = .destinationAlpha
        inside.colorAttachments[0].sourceAlphaBlendFactor = .zero
        inside.colorAttachments[0].destinationAlphaBlendFactor = .one

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

        let strokeMax = MTLRenderPipelineDescriptor()
        strokeMax.vertexFunction = brush.vertexFunction
        strokeMax.fragmentFunction = brush.fragmentFunction
        premultipliedOver(strokeMax, format: Self.layerFormat)
        for a in [strokeMax.colorAttachments[0]!] {
            a.rgbBlendOperation = .max; a.alphaBlendOperation = .max
            a.sourceRGBBlendFactor = .one; a.sourceAlphaBlendFactor = .one
            a.destinationRGBBlendFactor = .one; a.destinationAlphaBlendFactor = .one
        }

        /// The stroke texture drawn over a layer, with the same blending as the brush modes.
        func strokeComposite(_ shape: (MTLRenderPipelineColorAttachmentDescriptor) -> Void) -> MTLRenderPipelineDescriptor {
            let d = composite("composite_fragment", format: Self.layerFormat)
            shape(d.colorAttachments[0])
            return d
        }

        do {
            strokeMaxPipeline = try device.makeRenderPipelineState(descriptor: strokeMax)
            strokeFrontPipeline = try device.makeRenderPipelineState(descriptor: strokeComposite { _ in })
            strokeBehindPipeline = try device.makeRenderPipelineState(descriptor: strokeComposite {
                $0.sourceRGBBlendFactor = .oneMinusDestinationAlpha; $0.sourceAlphaBlendFactor = .oneMinusDestinationAlpha
                $0.destinationRGBBlendFactor = .one; $0.destinationAlphaBlendFactor = .one
            })
            strokeInsidePipeline = try device.makeRenderPipelineState(descriptor: strokeComposite {
                $0.sourceRGBBlendFactor = .destinationAlpha; $0.sourceAlphaBlendFactor = .zero
                $0.destinationAlphaBlendFactor = .one
            })
            strokeErasePipeline = try device.makeRenderPipelineState(descriptor: strokeComposite {
                $0.sourceRGBBlendFactor = .zero; $0.sourceAlphaBlendFactor = .zero
            })
            brushPipeline = try device.makeRenderPipelineState(descriptor: brush)
            brushBehindPipeline = try device.makeRenderPipelineState(descriptor: behind)
            brushInsidePipeline = try device.makeRenderPipelineState(descriptor: inside)
            eraserPipeline = try device.makeRenderPipelineState(descriptor: eraser)
            screenCompositePipeline = try device.makeRenderPipelineState(descriptor: composite("composite_fragment", format: screenFormat))
            screenCheckerPipeline = try device.makeRenderPipelineState(descriptor: composite("checker_fragment", format: screenFormat))
            workspacePipeline = try device.makeRenderPipelineState(descriptor: composite("workspace_fragment", format: screenFormat))
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
    /// `hard` is pixel art: every stamp sits on a pixel centre and covers whole pixels only.
    func paint(_ stamps: [Stamp], into target: MTLTexture, color: SIMD4<Float>, tool: Tool, hard: Bool = false,
               mode: PaintMode = .front) {
        guard !stamps.isEmpty, let cmd = queue.makeCommandBuffer() else { return }
        let stamps = hard ? stamps.map(Self.snappedToPixel) : stamps
        let count = stamps.count
        // One buffer per call: a shared, reused buffer would be overwritten by the next paint
        // before the GPU has read it, since we commit without waiting.
        guard let buffer = stamps.withUnsafeBytes({ src in
            device.makeBuffer(bytes: src.baseAddress!, length: src.count, options: .storageModeShared)
        }) else { return }
        var uniforms = StampUniforms(canvasSize: SIMD2<Float>(Float(canvasSize.x), Float(canvasSize.y)), color: color,
                                     hard: hard ? 1 : 0)

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .load
        pass.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(tool == .eraser ? eraserPipeline
                                   : mode == .behind ? brushBehindPipeline
                                   : mode == .inside ? brushInsidePipeline : brushPipeline)
        enc.setVertexBuffer(buffer, offset: 0, index: 0)
        enc.setVertexBytes(&uniforms, length: MemoryLayout<StampUniforms>.stride, index: 1)
        enc.setFragmentBytes(&uniforms, length: MemoryLayout<StampUniforms>.stride, index: 1)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: count)
        enc.endEncoding()
        cmd.commit()
    }

    /// Stamps into a stroke's own texture (cleared when the stroke began), in `color` at full
    /// strength: the stroke's opacity is applied when it's composited onto the layer.
    func paintStroke(_ stamps: [Stamp], into stroke: MTLTexture, color: SIMD3<Float>, tip: BrushTip, hard: Bool) {
        guard !stamps.isEmpty, let cmd = queue.makeCommandBuffer() else { return }
        let stamps = hard ? stamps.map(Self.snappedToPixel) : stamps
        guard let buffer = stamps.withUnsafeBytes({ src in
            device.makeBuffer(bytes: src.baseAddress!, length: src.count, options: .storageModeShared)
        }) else { return }
        var uniforms = StampUniforms(canvasSize: SIMD2<Float>(Float(canvasSize.x), Float(canvasSize.y)),
                                     color: SIMD4(color, 1), hard: hard ? 1 : 0,
                                     hardness: hard ? 1 : tip.hardness, grain: hard ? 0 : tip.grain,
                                     grainScale: max(tip.grainScale, 0.5))
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = stroke
        pass.colorAttachments[0].loadAction = .load
        pass.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(tip.buildsUp ? brushPipeline : strokeMaxPipeline)
        enc.setVertexBuffer(buffer, offset: 0, index: 0)
        enc.setVertexBytes(&uniforms, length: MemoryLayout<StampUniforms>.stride, index: 1)
        enc.setFragmentBytes(&uniforms, length: MemoryLayout<StampUniforms>.stride, index: 1)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: stamps.count)
        enc.endEncoding()
        cmd.commit()
    }

    /// The layer as it was before the stroke (`base`, nil = blank) with the stroke so far on top,
    /// at `opacity`, in front / behind / inside, or rubbed out of it with the eraser.
    func compositeStroke(_ stroke: MTLTexture, base: MTLTexture?, into target: MTLTexture,
                         opacity: Float, mode: PaintMode, erase: Bool) {
        guard let cmd = queue.makeCommandBuffer() else { return }
        if let base, let blit = cmd.makeBlitCommandEncoder() {
            blit.copy(from: base, to: target)
            blit.endEncoding()
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = base == nil ? .clear : .load
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }
        let rect = Quad.fullScreen
        var u = CompositeUniforms(origin: rect.origin, axisX: rect.axisX, axisY: rect.axisY, tint: .zero,
                                  opacity: opacity, tintAmount: 0,
                                  canvasSize: SIMD2<Float>(Float(canvasSize.x), Float(canvasSize.y)))
        enc.setRenderPipelineState(erase ? strokeErasePipeline
                                   : mode == .behind ? strokeBehindPipeline
                                   : mode == .inside ? strokeInsidePipeline : strokeFrontPipeline)
        enc.setVertexBytes(&u, length: MemoryLayout<CompositeUniforms>.stride, index: 0)
        enc.setFragmentBytes(&u, length: MemoryLayout<CompositeUniforms>.stride, index: 0)
        enc.setFragmentTexture(stroke, index: 0)
        enc.setFragmentTexture(stroke, index: 1)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        enc.endEncoding()
        cmd.commit()
    }

    /// A pixel-art stamp: centred on the pixel under it, and the brush size read as a width in
    /// pixels (size 1 is one pixel, 3 a 3×3 block) instead of a radius.
    static func snappedToPixel(_ s: Stamp) -> Stamp {
        Stamp(position: s.position.rounded(.down) + 0.5, radius: max(0.5, s.radius / 2), alpha: 1)
    }

    // MARK: - Compositing

    /// Composite `layers` (bottom to top) over a checkerboard into the drawable.
    /// Where the canvas lands in normalized device coordinates.
    struct Quad {
        var origin: SIMD2<Float>
        var axisX: SIMD2<Float>
        var axisY: SIMD2<Float>
        static let fullScreen = Quad(origin: [-1, -1], axisX: [2, 0], axisY: [0, 2])
    }

    func quad(_ transform: CanvasTransform, viewSize: CGSize, unitsPerPoint: CGFloat) -> Quad {
        let t = transform.canvasToView(canvas: canvasSize, viewSize: viewSize, unitsPerPoint: unitsPerPoint)
        func ndc(_ x: Int, _ y: Int) -> SIMD2<Float> {
            let p = CGPoint(x: x, y: y).applying(t)
            return SIMD2<Float>(Float(p.x / viewSize.width) * 2 - 1, 1 - Float(p.y / viewSize.height) * 2)
        }
        let bottomLeft = ndc(0, canvasSize.y)
        return Quad(origin: bottomLeft,
                    axisX: ndc(canvasSize.x, canvasSize.y) - bottomLeft,
                    axisY: ndc(0, 0) - bottomLeft)
    }

    func present(_ layers: [CompositeLayer], to drawable: CAMetalDrawable, viewSize: CGSize,
                 transform: CanvasTransform, unitsPerPoint: CGFloat) {
        guard let cmd = queue.makeCommandBuffer() else { return }
        let rect = quad(transform, viewSize: viewSize, unitsPerPoint: unitsPerPoint)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }
        // 24 points per cell, so it looks the same on every iPad.
        var w = CompositeUniforms(origin: Quad.fullScreen.origin, axisX: Quad.fullScreen.axisX, axisY: Quad.fullScreen.axisY,
                                  tint: .zero, opacity: 1, tintAmount: 0,
                                  canvasSize: SIMD2(Float(24 * unitsPerPoint), showsWorkspaceGrid ? 1 : 0))
        enc.setRenderPipelineState(workspacePipeline)
        enc.setVertexBytes(&w, length: MemoryLayout<CompositeUniforms>.stride, index: 0)
        enc.setFragmentBytes(&w, length: MemoryLayout<CompositeUniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        encodeComposite(enc, layers: layers, rect: rect,
                        checker: screenCheckerPipeline, composite: screenCompositePipeline)
        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }

    /// Render a small preview of `layers` and hand back a CGImage on a background queue.
    func thumbnail(_ layers: [CompositeLayer], maxSide: Int = 160, checker: Bool = true,
                   completion: @escaping (CGImage?) -> Void) {
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
        encodeComposite(enc, layers: layers, rect: .fullScreen,
                        checker: checker ? thumbCheckerPipeline : nil, composite: thumbCompositePipeline)
        enc.endEncoding()

        cmd.addCompletedHandler { _ in
            completion(Self.image(width: target.width, height: target.height, bytes: Self.bytes(from: target)))
        }
        cmd.commit()
    }

    /// Composites `layers` (bottom to top) onto a transparent, canvas-sized image. Blocking. Used by export.
    /// Visible layers composited at full size over transparency: what fill and the eyedropper "see".
    func flattenBytes(_ layers: [CompositeLayer]) -> [UInt8]? {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Self.layerFormat, width: canvasSize.x, height: canvasSize.y, mipmapped: false)
        d.usage = [.renderTarget]
        d.storageMode = .shared
        guard let target = device.makeTexture(descriptor: d),
              let cmd = queue.makeCommandBuffer() else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        encodeComposite(enc, layers: layers, rect: .fullScreen,
                        checker: nil, composite: thumbCompositePipeline)
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        return Self.bytes(from: target)
    }

    /// Visible layers composited at full size, as an image.
    func flatten(_ layers: [CompositeLayer]) -> CGImage? {
        flattenBytes(layers).flatMap { Self.image(width: canvasSize.x, height: canvasSize.y, bytes: $0) }
    }

    // MARK: - CPU transfer
    //
    // Pixels on the CPU are RGBA8, premultiplied, row 0 at the top (canvas y down), 4 bytes per
    // pixel, tightly packed: the same memory layout as `layerFormat`.

    /// Full-resolution copy of a layer's pixels.
    /// Blocks until the GPU has finished every command queued before it on `texture`.
    func readbackBytes(_ texture: MTLTexture) -> [UInt8]? {
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
        return Self.bytes(from: staging)
    }

    /// Full-resolution copy of a layer as a premultiplied RGBA `CGImage`.
    func readback(_ texture: MTLTexture) -> CGImage? {
        readbackBytes(texture).flatMap { Self.image(width: texture.width, height: texture.height, bytes: $0) }
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
        upload(bytes: bytes, into: texture)
    }

    /// Replaces the contents of `texture` with canvas-sized pixels (see the layout above).
    func upload(bytes: [UInt8], into texture: MTLTexture) {
        let w = texture.width, h = texture.height
        guard bytes.count == w * h * 4 else { return }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.layerFormat, width: w, height: h, mipmapped: false)
        d.storageMode = .shared
        guard let staging = device.makeTexture(descriptor: d),
              let cmd = queue.makeCommandBuffer(),
              let blit = cmd.makeBlitCommandEncoder() else { return }
        bytes.withUnsafeBytes { ptr in
            staging.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0,
                            withBytes: ptr.baseAddress!, bytesPerRow: w * 4)
        }
        blit.copy(from: staging, to: texture)
        blit.endEncoding()
        cmd.commit()
    }

    /// RGBA8, premultiplied, row 0 at the top: the same memory layout as `layerFormat`.
    private static let cgBitmapInfo = CGBitmapInfo(
        rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)

    /// The pixels of a shared-storage texture. The GPU must already be done with it.
    private static func bytes(from texture: MTLTexture) -> [UInt8] {
        let w = texture.width, h = texture.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        bytes.withUnsafeMutableBytes { ptr in
            texture.getBytes(ptr.baseAddress!, bytesPerRow: w * 4,
                             from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        }
        return bytes
    }

    private static func image(width w: Int, height h: Int, bytes: [UInt8]) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: cgBitmapInfo, provider: provider, decode: nil,
                       shouldInterpolate: true, intent: .defaultIntent)
    }

    private func encodeComposite(_ enc: MTLRenderCommandEncoder, layers: [CompositeLayer], rect: Quad,
                                 checker: MTLRenderPipelineState?, composite: MTLRenderPipelineState) {
        var u = CompositeUniforms(origin: rect.origin, axisX: rect.axisX, axisY: rect.axisY, tint: .zero, opacity: 1, tintAmount: 0,
                                  canvasSize: SIMD2<Float>(Float(canvasSize.x), Float(canvasSize.y)))
        if let checker {
            enc.setRenderPipelineState(checker)
            enc.setVertexBytes(&u, length: MemoryLayout<CompositeUniforms>.stride, index: 0)
            enc.setFragmentBytes(&u, length: MemoryLayout<CompositeUniforms>.stride, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }

        enc.setRenderPipelineState(composite)
        for layer in layers {
            u.opacity = layer.opacity
            u.tint = SIMD4<Float>(layer.tint, 1)
            u.tintAmount = layer.tintAmount
            u.useMask = layer.mask == nil ? 0 : 1
            enc.setVertexBytes(&u, length: MemoryLayout<CompositeUniforms>.stride, index: 0)
            enc.setFragmentBytes(&u, length: MemoryLayout<CompositeUniforms>.stride, index: 0)
            enc.setFragmentTexture(layer.texture, index: 0)
            enc.setFragmentTexture(layer.mask ?? layer.texture, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        }
    }

    // MARK: - Geometry

    static func fitRect(canvas: SIMD2<Int>, in view: CGSize, margin: CGFloat = 0.9) -> CGRect {
        let cw = CGFloat(canvas.x), ch = CGFloat(canvas.y)
        let scale = min(view.width / cw, view.height / ch) * margin
        let w = cw * scale, h = ch * scale
        return CGRect(x: (view.width - w) / 2, y: (view.height - h) / 2, width: w, height: h)
    }

    /// View point → canvas pixel under it, for the current zoom/pan/rotation.
    func canvasPoint(fromViewPoint p: CGPoint, viewSize: CGSize, transform: CanvasTransform) -> SIMD2<Float> {
        let c = p.applying(transform.viewToCanvas(canvas: canvasSize, viewSize: viewSize))
        return SIMD2<Float>(Float(c.x), Float(c.y))
    }
}
