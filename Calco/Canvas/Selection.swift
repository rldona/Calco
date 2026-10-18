import CoreGraphics
import Foundation

/// A lasso selection lifted off a layer, being moved / scaled / rotated before it's put back.
/// Canvas coordinates throughout (pixels, origin top-left, y down).
struct FloatingSelection: Equatable {
    let key: LayerKey
    /// Canvas-sized pixels of what was lifted (everything else transparent).
    let lifted: [UInt8]
    /// The lasso as drawn, before any transform.
    let outline: [CGPoint]
    /// Bounding box of `outline`, clipped to the canvas.
    let bounds: CGRect

    /// What scaling and rotating pivot around, in the selection's own (untransformed) space.
    var anchor: CGPoint
    var offset = CGVector.zero
    var scale: CGFloat = 1
    var rotation: CGFloat = 0
    var flipped = false

    static let scaleRange: ClosedRange<CGFloat> = 0.05...20

    /// Untransformed selection space → canvas.
    var transform: CGAffineTransform {
        CGAffineTransform(translationX: -anchor.x, y: -anchor.y)
            .concatenating(linear)
            .concatenating(CGAffineTransform(translationX: anchor.x + offset.dx, y: anchor.y + offset.dy))
    }

    /// Scale, flip and rotation only.
    var linear: CGAffineTransform {
        CGAffineTransform(scaleX: flipped ? -scale : scale, y: scale)
            .concatenating(CGAffineTransform(rotationAngle: rotation))
    }

    /// Where the anchor is on the canvas right now.
    var placedAnchor: CGPoint { CGPoint(x: anchor.x + offset.dx, y: anchor.y + offset.dy) }

    /// Moves the pivot to canvas point `q` without moving the drawing: the offset absorbs the
    /// change, so only what later scaling and rotation pivot around changes.
    mutating func moveAnchor(to q: CGPoint) {
        let newAnchor = q.applying(transform.inverted())
        let d = CGPoint(x: anchor.x - newAnchor.x, y: anchor.y - newAnchor.y)
        let md = d.applying(linear)
        offset.dx += d.x - md.x
        offset.dy += d.y - md.y
        anchor = newAnchor
    }

    var isIdentity: Bool { offset == .zero && scale == 1 && rotation == 0 && !flipped }
}

/// The pixel work behind the lasso, on CPU buffers (RGBA8 premultiplied, row 0 at the top).
/// Pure CoreGraphics so it's testable without Metal.
enum SelectionPixels {

    /// Anti-aliased coverage (0–255) of a closed polygon, one byte per pixel.
    static func rasterize(_ polygon: [CGPoint], width: Int, height: Int) -> [UInt8] {
        var mask = [UInt8](repeating: 0, count: width * height)
        guard polygon.count >= 3 else { return mask }
        mask.withUnsafeMutableBytes { ptr in
            guard let ctx = CGContext(data: ptr.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            flipToCanvas(ctx, height: height)
            ctx.setFillColor(gray: 1, alpha: 1)
            ctx.addLines(between: polygon)
            ctx.closePath()
            ctx.fillPath(using: .evenOdd)
        }
        return mask
    }

    /// Splits a layer by a coverage mask: what's inside (lifted) and what's left behind.
    static func split(_ rgba: [UInt8], mask: [UInt8]) -> (lifted: [UInt8], remaining: [UInt8]) {
        guard rgba.count == mask.count * 4 else { return ([], rgba) }
        var lifted = [UInt8](repeating: 0, count: rgba.count)
        var remaining = rgba
        for (i, m) in mask.enumerated() where m > 0 {
            for c in 0..<4 {
                let v = Int(rgba[i * 4 + c])
                let inside = (v * Int(m) + 127) / 255
                lifted[i * 4 + c] = UInt8(inside)
                remaining[i * 4 + c] = UInt8(v - inside)
            }
        }
        return (lifted, remaining)
    }

    static func isEmpty(_ rgba: [UInt8]) -> Bool {
        stride(from: 3, to: rgba.count, by: 4).allSatisfy { rgba[$0] == 0 }
    }

    /// `rgba` drawn through a canvas-space affine transform (high-quality resampling).
    static func render(_ rgba: [UInt8], width: Int, height: Int, transform: CGAffineTransform) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: width * height * 4)
        guard rgba.count == out.count, let image = image(rgba, width: width, height: height) else { return out }
        out.withUnsafeMutableBytes { ptr in
            guard let ctx = CGContext(data: ptr.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: bitmapInfo) else { return }
            ctx.interpolationQuality = .high
            flipToCanvas(ctx, height: height)
            ctx.concatenate(transform)
            // The image's row 0 is the canvas top; undo the flip just for drawing it upright.
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return out
    }

    /// Premultiplied source-over.
    static func composite(_ top: [UInt8], over bottom: [UInt8]) -> [UInt8] {
        guard top.count == bottom.count else { return bottom }
        var out = bottom
        for p in stride(from: 0, to: top.count, by: 4) {
            let inv = 255 - Int(top[p + 3])
            for c in 0..<4 {
                out[p + c] = UInt8(min(255, Int(top[p + c]) + (Int(bottom[p + c]) * inv + 127) / 255))
            }
        }
        return out
    }

    // MARK: -

    private static let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

    /// Makes the context's user space the canvas's: origin top-left, y down.
    private static func flipToCanvas(_ ctx: CGContext, height: Int) {
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
    }

    private static func image(_ rgba: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

