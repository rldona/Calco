import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Packs every frame of every clip into one PNG and describes it in the
/// Aseprite JSON "array" format, which Unity, Godot and most engines read.
///
/// Pure CoreGraphics: the caller supplies a flattened `CGImage` per frame.
/// Frames are laid out in a near-square grid, canvas-sized cells, no trimming.
struct SpriteSheet {
    struct Cell {
        var clip: Clip
        var frame: Frame
        var rect: CGRect
        var durationMs: Int
    }

    var canvas: CanvasSize
    var columns: Int
    var size: CGSize
    var cells: [Cell]
    var image: CGImage?

    // MARK: - Build

    static func build(project: Project, frameImage: (Clip, Frame) -> CGImage?) -> SpriteSheet {
        let w = project.canvas.width, h = project.canvas.height
        let all: [(Clip, Frame)] = project.clips.flatMap { clip in clip.frames.map { (clip, $0) } }
        let count = max(all.count, 1)
        let columns = Int(Double(count).squareRoot().rounded(.up))
        let rows = Int((Double(count) / Double(columns)).rounded(.up))
        let size = CGSize(width: columns * w, height: rows * h)

        var cells: [Cell] = []
        for (i, (clip, frame)) in all.enumerated() {
            let fps = clip.fps ?? project.fps
            cells.append(Cell(
                clip: clip, frame: frame,
                rect: CGRect(x: (i % columns) * w, y: (i / columns) * h, width: w, height: h),
                durationMs: Int((Double(frame.hold) * 1000 / Double(max(fps, 1))).rounded())))
        }

        var sheet = SpriteSheet(canvas: project.canvas, columns: columns, size: size, cells: cells, image: nil)
        sheet.image = sheet.render(frameImage)
        return sheet
    }

    private func render(_ frameImage: (Clip, Frame) -> CGImage?) -> CGImage? {
        let w = Int(size.width), h = Int(size.height)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else { return nil }
        ctx.interpolationQuality = .none
        for cell in cells {
            guard let img = frameImage(cell.clip, cell.frame) else { continue }
            // CGContext's origin is bottom-left; the sheet's rects are top-left.
            let flipped = CGRect(x: cell.rect.minX, y: size.height - cell.rect.maxY,
                                 width: cell.rect.width, height: cell.rect.height)
            ctx.draw(img, in: flipped)
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
        let w = canvas.width, h = canvas.height
        var frames: [Aseprite.FrameEntry] = []
        var tags: [Aseprite.Tag] = []
        var slices: [Aseprite.Slice] = []
        var index = 0
        for clip in orderedClips {
            let clipCells = cells.filter { $0.clip.id == clip.id }
            guard !clipCells.isEmpty else { continue }
            let from = index
            for (i, cell) in clipCells.enumerated() {
                frames.append(.init(
                    filename: "\(projectName) \(clip.id) \(i).png",
                    frame: .init(x: Int(cell.rect.minX), y: Int(cell.rect.minY), w: w, h: h),
                    spriteSourceSize: .init(x: 0, y: 0, w: w, h: h),
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
