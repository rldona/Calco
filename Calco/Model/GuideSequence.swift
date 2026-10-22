import CoreGraphics
import Foundation

/// Importing an image sequence as a guide, one image per frame: which images go to which frames,
/// how they fit the canvas, and in what order the files come. Pure, so it can be tested without
/// the editor. See docs/specs/import-guide-sequence.md.
enum GuideSequence {

    /// How an image fits the canvas. Worked out once, from the first image, and used for all of
    /// them so the figure doesn't jump between frames.
    enum Fit: String, Codable, CaseIterable, Identifiable {
        /// Scaled uniformly to fit whole, centred.
        case fit
        /// Scaled uniformly to cover the canvas, centred (the edges may be cut).
        case fill
        /// Not scaled, centred (cut if bigger than the canvas).
        case actual
        var id: String { rawValue }
    }

    /// A tint for the guide's lines, so they don't read as drawing.
    enum Tint: String, Codable, CaseIterable, Identifiable {
        case none, red, blue, green
        var id: String { rawValue }
        /// As stored on the layer ("#RRGGBB"), nil for none.
        var hex: String? {
            switch self {
            case .none: nil
            case .red: "#E5484D"
            case .blue: "#3E7BFA"
            case .green: "#30A46C"
            }
        }
    }

    /// The import sheet's choices, remembered for next time.
    struct Options: Codable, Equatable {
        /// Use one image in every `step`.
        var step = 1
        /// Ticks each frame the import creates lasts.
        var hold = 1
        /// Start at the playhead instead of the first frame.
        var startAtPlayhead = false
        /// Add frames at the end when the clip runs out.
        var createMissing = true
        var fit = Fit.fit
        /// Moves the images, in canvas pixels (x right, y down).
        var offsetX: Double = 0
        var offsetY: Double = 0
        var opacity: Double = 0.4
        var tint = Tint.none

        static let defaultsKey = "guideSequence.options"

        static func load(_ defaults: UserDefaults = .standard) -> Options {
            guard let data = defaults.data(forKey: defaultsKey),
                  var o = try? JSONDecoder().decode(Options.self, from: data) else { return Options() }
            o.step = max(1, o.step); o.hold = min(max(1, o.hold), 24)
            o.opacity = min(max(o.opacity, 0.05), 1)
            return o
        }

        func save(_ defaults: UserDefaults = .standard) {
            defaults.set(try? JSONEncoder().encode(self), forKey: Self.defaultsKey)
        }
    }

    /// Where the images go.
    struct Plan: Equatable {
        /// Indices of the images used, in order.
        var images: [Int]
        /// The clip's frame index for each image used.
        var frames: [Int]
        /// Frames to add at the end of the clip first.
        var newFrames: Int
        /// Images that would be used but don't fit (the clip is too short and won't grow).
        var leftOut: Int
    }

    /// Images `0, step, 2·step…` of `count` go to frames `start, start+1…` of a clip with
    /// `existing` frames, adding frames at the end if `createMissing`, otherwise stopping at the
    /// last one.
    static func plan(count: Int, step: Int, start: Int, existing: Int, createMissing: Bool) -> Plan {
        let used = Array(stride(from: 0, to: max(count, 0), by: max(step, 1)))
        let start = max(0, start)
        let room = createMissing ? used.count : max(0, min(used.count, existing - start))
        let images = Array(used.prefix(room))
        let frames = images.indices.map { start + $0 }
        let newFrames = max(0, (frames.last.map { $0 + 1 } ?? 0) - existing)
        return Plan(images: images, frames: frames, newFrames: newFrames, leftOut: used.count - images.count)
    }

    /// Where an image of `size` lands on a canvas of `canvas`, in canvas pixels (origin top-left).
    static func rect(for size: CGSize, in canvas: CGSize, fit: Fit, offset: CGPoint = .zero) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let sx = canvas.width / size.width, sy = canvas.height / size.height
        let s: CGFloat = switch fit {
        case .fit: min(sx, sy)
        case .fill: max(sx, sy)
        case .actual: 1
        }
        let w = size.width * s, h = size.height * s
        return CGRect(x: (canvas.width - w) / 2 + offset.x, y: (canvas.height - h) / 2 + offset.y, width: w, height: h)
    }

    /// `image` drawn into `rect` on a `width` x `height` canvas: premultiplied RGBA, row 0 at the
    /// top, like layer textures. Any pixel format or size goes in. `hard` keeps pixels sharp.
    static func rasterize(_ image: CGImage, into rect: CGRect, width: Int, height: Int, hard: Bool = false) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: width * height * 4)
        out.withUnsafeMutableBytes { ptr in
            guard let ctx = CGContext(data: ptr.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.interpolationQuality = hard ? .none : .high
            // CoreGraphics is y-up; the buffer's row 0 is the canvas top, so flip the rect's y.
            ctx.draw(image, in: CGRect(x: rect.minX, y: CGFloat(height) - rect.maxY, width: rect.width, height: rect.height))
        }
        return out
    }

    /// File names in natural order: `f2` before `f10`, ignoring case.
    static func naturalOrder(_ names: [String]) -> [String] {
        names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
