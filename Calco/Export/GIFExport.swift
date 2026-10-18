import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Writes one clip as an animated GIF through ImageIO. No third-party code.
/// GIF timing is in hundredths of a second and most viewers clamp anything under 20 ms to 100 ms,
/// so a 1-tick hold at 60 fps will play slower than in Calco. That's the format, not a bug.
enum GIFExport {
    struct Frame {
        /// Flattened, canvas-sized image. Nil for a frame nobody drew on (exported transparent).
        var image: CGImage?
        var durationSeconds: Double
    }

    enum Error: LocalizedError {
        case noFrames
        case encodingFailed
        var errorDescription: String? {
            switch self {
            case .noFrames: return "The clip has no frames."
            case .encodingFailed: return "Couldn't encode the GIF."
            }
        }
    }

    /// `loop` false writes a GIF that plays once; true loops forever.
    static func write(_ frames: [Frame], canvas: CanvasSize, loop: Bool, to url: URL) throws {
        guard !frames.isEmpty else { throw Error.noFrames }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else {
            throw Error.encodingFailed
        }
        // NETSCAPE loop block: 0 = forever, 1 = play once.
        let gif: [CFString: Any] = [kCGImagePropertyGIFLoopCount: loop ? 0 : 1]
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: gif] as CFDictionary)

        let blank = transparentImage(width: canvas.width, height: canvas.height)
        for frame in frames {
            guard let image = frame.image ?? blank else { throw Error.encodingFailed }
            let delay = max(frame.durationSeconds, 0.02)
            let props: [CFString: Any] = [kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: delay,
                kCGImagePropertyGIFUnclampedDelayTime: delay,
            ]]
            CGImageDestinationAddImage(dest, image, props as CFDictionary)
        }
        guard CGImageDestinationFinalize(dest) else { throw Error.encodingFailed }
    }

    private static func transparentImage(width: Int, height: Int) -> CGImage? {
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info)?.makeImage()
    }
}
