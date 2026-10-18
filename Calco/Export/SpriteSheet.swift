import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Packs the frames of the chosen clips into one PNG and describes it in the
/// Aseprite JSON "array" format, which Unity, Godot and most engines read.
///
/// Pure CoreGraphics: the caller supplies a flattened, canvas-sized `CGImage` per frame.
/// Frames are laid out in a near-square grid with a transparent `padding` between cells and
/// around the sheet, so bilinear filtering in the engine never samples a neighbouring frame.
/// Options scale the frames and trim each clip to the box its drawings actually use (one box
/// per clip, so the clip doesn't jitter; the JSON says where the box sits in the canvas).
struct SpriteSheet {
    struct Cell {
        var clip: Clip
        var frame: Frame
        /// Where the frame sits in the sheet, top-left origin.
        var rect: CGRect
        /// The part of the canvas it shows (all of it unless trimmed), top-left origin.
        var source: CGRect
        var durationMs: Int
    }

    struct Options: Equatable {
        var padding = SpriteSheet.defaultPadding
        /// 0.5, 1, 2, 4… Upscaling keeps hard pixel edges; downscaling smooths.
        var scale: Double = 1
        var trim = false
        var powerOfTwo = false
        /// Clip ids to include, in project order. Nil = every clip.
        var clips: [String]? = nil
    }

    /// Default gap, in pixels, between cells and around the sheet's edge.
    static let defaultPadding = 2

    var canvas: CanvasSize
    var columns: Int
    var padding: Int
    var scale: Double = 1
    var trimmed = false
    var size: CGSize
    var cells: [Cell]
    var image: CGImage?

    // MARK: - Build

    static func build(project: Project, padding: Int = defaultPadding,
                      frameImage: (Clip, Frame) -> CGImage?) -> SpriteSheet {
        build(project: project, options: Options(padding: padding), frameImage: frameImage)
    }

    static func build(project: Project, options: Options, frameImage: (Clip, Frame) -> CGImage?) -> SpriteSheet {
        let canvasRect = CGRect(x: 0, y: 0, width: project.canvas.width, height: project.canvas.height)
        let pad = max(options.padding, 0)
        let scale = options.scale > 0 ? options.scale : 1
        let clips = project.clips.filter { options.clips?.contains($0.id) ?? true }
        let all: [(Clip, Frame)] = clips.flatMap { clip in clip.frames.map { (clip, $0) } }
        // Every image once: trimming needs them before layout, rendering after.
        let images = all.map { frameImage($0.0, $0.1) }

        // One source box per clip: the canvas, or the union of what its frames draw.
        var sources: [String: CGRect] = [:]
        for clip in clips {
            guard options.trim else { sources[clip.id] = canvasRect; continue }
            let box = zip(all, images).filter { $0.0.0.id == clip.id }
                .compactMap { $0.1.flatMap(Self.opaqueBounds) }
                .reduce(CGRect.null) { $0.union($1) }
            sources[clip.id] = box.isNull ? CGRect(x: 0, y: 0, width: 1, height: 1) : box
        }
        func scaled(_ v: CGFloat) -> Int { max(1, Int((v * scale).rounded())) }
        let cellW = sources.values.map { scaled($0.width) }.max() ?? scaled(canvasRect.width)
        let cellH = sources.values.map { scaled($0.height) }.max() ?? scaled(canvasRect.height)

        let count = max(all.count, 1)
        let columns = Int(Double(count).squareRoot().rounded(.up))
        let rows = Int((Double(count) / Double(columns)).rounded(.up))
        // `pad` on the outside plus `pad` after every cell: pad + n * (cell + pad).
        var size = CGSize(width: pad + columns * (cellW + pad), height: pad + rows * (cellH + pad))
        if options.powerOfTwo { size = CGSize(width: nextPowerOfTwo(Int(size.width)), height: nextPowerOfTwo(Int(size.height))) }

        var cells: [Cell] = []
        for (i, (clip, frame)) in all.enumerated() {
            let fps = clip.fps ?? project.fps
            let source = sources[clip.id] ?? canvasRect
            cells.append(Cell(
                clip: clip, frame: frame,
                rect: CGRect(x: pad + (i % columns) * (cellW + pad), y: pad + (i / columns) * (cellH + pad),
                             width: scaled(source.width), height: scaled(source.height)),
                source: source,
                durationMs: Int((Double(frame.hold) * 1000 / Double(max(fps, 1))).rounded())))
        }

        var sheet = SpriteSheet(canvas: project.canvas, columns: columns, padding: pad, scale: scale,
                                trimmed: options.trim, size: size, cells: cells, image: nil)
        sheet.image = sheet.render(images)
        return sheet
    }

    static func nextPowerOfTwo(_ n: Int) -> Int {
        var p = 1
        while p < n { p <<= 1 }
        return p
    }

    /// The smallest box (canvas pixels, top-left origin) holding every pixel with any alpha, or nil if empty.
    static func opaqueBounds(_ image: CGImage) -> CGRect? {
        let w = image.width, h = image.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where px[(y * w + x) * 4 + 3] > 0 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        return maxX < 0 ? nil : CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    private func render(_ images: [CGImage?]) -> CGImage? {
        let w = Int(size.width), h = Int(size.height)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else { return nil }
        // Up keeps the drawing's pixels crisp; down blends them so lines don't break up.
        ctx.interpolationQuality = scale < 1 ? .high : .none
        for (cell, img) in zip(cells, images) {
            guard let img, let part = img.cropping(to: cell.source) else { continue }
            // CGContext's origin is bottom-left; the sheet's rects are top-left.
            let flipped = CGRect(x: cell.rect.minX, y: size.height - cell.rect.maxY,
                                 width: cell.rect.width, height: cell.rect.height)
            ctx.draw(part, in: flipped)
        }
        return ctx.makeImage()
    }

    // MARK: - Aseprite JSON

    struct Aseprite: Encodable {
        struct Rect: Encodable { var x, y, w, h: Int }
        struct Size: Encodable { var w, h: Int }
        struct Point: Encodable { var x, y: Int }
        struct FrameEntry: Encodable {
            var filename: String
            var frame: Rect
            var rotated = false
            var trimmed = false
            var spriteSourceSize: Rect
            var sourceSize: Size
            var duration: Int
        }
        struct Tag: Encodable {
            var name: String
            var from: Int
            var to: Int
            var direction = "forward"
            /// Not part of Aseprite's schema; `calco-unity` reads it to set the AnimationClip's wrap mode.
            var loop: Bool
        }
        struct SliceKey: Encodable {
            var frame: Int
            var bounds: Rect
            var pivot: Point
        }
        struct Slice: Encodable {
            var name: String
            var color = "#0000ffff"
            var keys: [SliceKey]
        }
        struct Meta: Encodable {
            var app = "Calco"
            var version = "0.1"
            var image: String
            var format = "RGBA8888"
            var size: Size
            var scale = "1"
            var frameTags: [Tag]
            var slices: [Slice]
        }
        var frames: [FrameEntry]
        var meta: Meta
    }

    func aseprite(projectName: String, imageName: String) -> Aseprite {
        // The (scaled) canvas each frame comes from; trimmed frames say where their box sits in it.
        let w = Int((Double(canvas.width) * scale).rounded()), h = Int((Double(canvas.height) * scale).rounded())
        func s(_ v: CGFloat) -> Int { Int((Double(v) * scale).rounded()) }
        var frames: [Aseprite.FrameEntry] = []
        var tags: [Aseprite.Tag] = []
        var slices: [Aseprite.Slice] = []
        var index = 0
        for clip in orderedClips {
            let clipCells = cells.filter { $0.clip.id == clip.id }
            guard !clipCells.isEmpty else { continue }
            let from = index
            for (i, cell) in clipCells.enumerated() {
                let fw = Int(cell.rect.width), fh = Int(cell.rect.height)
                frames.append(.init(
                    filename: "\(projectName) \(clip.id) \(i).png",
                    frame: .init(x: Int(cell.rect.minX), y: Int(cell.rect.minY), w: fw, h: fh),
                    trimmed: trimmed,
                    spriteSourceSize: .init(x: s(cell.source.minX), y: s(cell.source.minY), w: fw, h: fh),
                    sourceSize: .init(w: w, h: h),
                    duration: cell.durationMs))
                index += 1
            }
            tags.append(.init(name: clip.id, from: from, to: index - 1, loop: clip.loop))
            // Our pivot is normalized, origin bottom-left. Aseprite's is in pixels from the slice's top-left.
            slices.append(.init(name: clip.id, keys: [.init(
                frame: from,
                bounds: .init(x: 0, y: 0, w: w, h: h),
                pivot: .init(x: Int((clip.pivot.x * Double(w)).rounded()),
                             y: Int(((1 - clip.pivot.y) * Double(h)).rounded())))]))
        }
        return Aseprite(frames: frames,
                        meta: .init(image: imageName, size: .init(w: Int(size.width), h: Int(size.height)),
                                    scale: scale == scale.rounded() ? "\(Int(scale))" : "\(scale)",
                                    frameTags: tags, slices: slices))
    }

    /// Clips in the order their cells appear, which is project order.
    private var orderedClips: [Clip] {
        var seen = Set<String>()
        return cells.compactMap { seen.insert($0.clip.id).inserted ? $0.clip : nil }
    }

    // MARK: - Write

    enum Error: LocalizedError {
        case noImage
        case pngEncodingFailed
        var errorDescription: String? {
            switch self {
            case .noImage: return "The sprite sheet couldn't be rendered."
            case .pngEncodingFailed: return "Couldn't encode the sprite sheet PNG."
            }
        }
    }

    /// Writes `<baseName>.png` and `<baseName>.json` into `folder`, returning both URLs (PNG first).
    @discardableResult
    func write(to folder: URL, baseName: String) throws -> [URL] {
        guard let image else { throw Error.noImage }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let png = folder.appendingPathComponent("\(baseName).png")
        let json = folder.appendingPathComponent("\(baseName).json")

        guard let dest = CGImageDestinationCreateWithURL(png as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw Error.pngEncodingFailed
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw Error.pngEncodingFailed }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(aseprite(projectName: baseName, imageName: png.lastPathComponent)).write(to: json, options: .atomic)
        return [png, json]
    }
}
