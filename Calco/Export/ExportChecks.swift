import CoreGraphics
import Foundation

/// Things worth knowing before a sprite sheet goes into a game. Advice, never a blocker:
/// every check can be a deliberate choice (a jump lifts the feet, a held pose repeats).
/// Pure CoreGraphics over flattened frames, so it's testable without Metal.
enum ExportChecks {

    struct Issue: Equatable, Identifiable {
        enum Kind: String { case emptyFrame, hiddenLayer, feetDrift, loopRepeats }
        var kind: Kind
        var clip: String
        var message: String
        var id: String { "\(kind.rawValue):\(clip):\(message)" }
    }

    /// `frameImage` gives a frame as it exports (visible layers flattened); `hiddenDrawing` says whether
    /// a hidden layer has anything drawn in that clip (it would be left out of the export).
    static func run(project: Project, clips: [String]?,
                    frameImage: (Clip, Frame) -> CGImage?,
                    hiddenDrawing: (Clip, Layer) -> Bool) -> [Issue] {
        var issues: [Issue] = []
        let canvasH = project.canvas.height
        for clip in project.clips where clips?.contains(clip.id) ?? true {
            let pixels = clip.frames.map { f in frameImage(clip, f).flatMap(Self.pixels) }
            let bounds = pixels.map { $0.flatMap { Self.bounds($0, width: project.canvas.width, height: canvasH) } }

            // Empty frames in a clip that has drawings elsewhere.
            let empty = bounds.indices.filter { bounds[$0] == nil }
            if !empty.isEmpty && empty.count < clip.frames.count {
                let list = empty.map { "\($0 + 1)" }.joined(separator: ", ")
                issues.append(Issue(kind: .emptyFrame, clip: clip.id,
                                    message: empty.count == 1 ? String(localized: "\(clip.name): frame \(list) is empty", bundle: AppLanguage.bundle)
                                        : String(localized: "\(clip.name): frames \(list) are empty", bundle: AppLanguage.bundle)))
            }

            // Hidden layers with drawings don't export.
            for layer in clip.layers where !layer.visible && hiddenDrawing(clip, layer) {
                issues.append(Issue(kind: .hiddenLayer, clip: clip.id,
                                    message: String(localized: "\(clip.name): \(layer.name) is hidden and won't be exported", bundle: AppLanguage.bundle)))
            }

            // Grounded clip (pivot on the bottom edge): the lowest drawn row should stay put.
            if clip.pivot.y <= 0.05 {
                let bottoms = bounds.compactMap { $0.map { Int($0.maxY) } }
                if let lo = bottoms.min(), let hi = bottoms.max(), hi - lo > max(2, canvasH / 50) {
                    issues.append(Issue(kind: .feetDrift, clip: clip.id,
                                        message: String(localized: "\(clip.name): the lowest point moves \(hi - lo) px between frames (feet sliding?)", bundle: AppLanguage.bundle)))
                }
            }

            // A loop whose last frame repeats the first plays that pose twice: a visible hitch.
            if clip.loop, clip.frames.count > 1, let first = pixels.first ?? nil, let last = pixels.last ?? nil, first == last,
               bounds.first != nil {
                issues.append(Issue(kind: .loopRepeats, clip: clip.id,
                                    message: String(localized: "\(clip.name): the last frame is the same as the first, so the loop stutters", bundle: AppLanguage.bundle)))
            }
        }
        return issues
    }

    // MARK: -

    private static func pixels(_ image: CGImage) -> [UInt8]? {
        let w = image.width, h = image.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return px
    }

    /// Box of every pixel with alpha, top-left origin; nil when the frame is empty.
    private static func bounds(_ px: [UInt8], width w: Int, height h: Int) -> CGRect? {
        guard px.count == w * h * 4 else { return nil }
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where px[(y * w + x) * 4 + 3] > 8 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        return maxX < 0 ? nil : CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
