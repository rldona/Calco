import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Small CoreGraphics helpers shared by the exporters.
enum ImageScaling {
    private static let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

    /// `image` resized by `factor`. Up keeps hard pixel edges; down blends so lines don't break up.
    static func scale(_ image: CGImage, by factor: Double) -> CGImage? {
        guard factor != 1 else { return image }
        let w = max(1, Int((Double(image.width) * factor).rounded()))
        let h = max(1, Int((Double(image.height) * factor).rounded()))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else { return nil }
        ctx.interpolationQuality = factor < 1 ? .high : .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    static func blank(width: Int, height: Int) -> CGImage? {
        CGContext(data: nil, width: max(1, width), height: max(1, height), bitsPerComponent: 8,
                  bytesPerRow: max(1, width) * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info)?.makeImage()
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw SpriteSheet.Error.pngEncodingFailed
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw SpriteSheet.Error.pngEncodingFailed }
    }
}
