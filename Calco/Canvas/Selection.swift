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
    /// Stretch along the selection's own width and height, on top of `scale`: squash and stretch.
    /// Both 1 while it keeps its proportions.
    var stretch = CGSize(width: 1, height: 1)
    var rotation: CGFloat = 0
    var flipped = false

    static let scaleRange: ClosedRange<CGFloat> = 0.05...20

    /// Untransformed selection space → canvas.
    var transform: CGAffineTransform {
        CGAffineTransform(translationX: -anchor.x, y: -anchor.y)
            .concatenating(linear)
            .concatenating(CGAffineTransform(translationX: anchor.x + offset.dx, y: anchor.y + offset.dy))
    }

    /// Scale on each axis, stretch included.
    var scaleX: CGFloat { scale * stretch.width }
    var scaleY: CGFloat { scale * stretch.height }

    /// Scale, stretch, flip and rotation only.
    var linear: CGAffineTransform {
        CGAffineTransform(scaleX: flipped ? -scaleX : scaleX, y: scaleY)
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

    var isIdentity: Bool {
        offset == .zero && scale == 1 && stretch == CGSize(width: 1, height: 1) && rotation == 0 && !flipped
    }

    // Snapping: near where it started, it clicks back into place, so you can always return to it.

    /// Within 4° of upright or of a quarter turn, exactly that.
    static func snappedRotation(_ r: CGFloat) -> CGFloat? {
        let quarter = CGFloat.pi / 2
        let nearest = (r / quarter).rounded() * quarter
        return abs(r - nearest) < 4 * .pi / 180 ? nearest : nil
    }

    /// Within `tolerance` canvas pixels of where it was lifted, back there.
    static func snappedOffset(_ o: CGVector, tolerance: CGFloat) -> CGVector? {
        hypot(o.dx, o.dy) < tolerance ? .zero : nil
    }

    /// Within 4 % of its own size, its own size.
    static func snappedScale(_ s: CGFloat) -> CGFloat? {
        abs(s - 1) < 0.04 ? 1 : nil
    }

    /// Stretching one axis to `stretch` (with the other at `other`, both times `scale`): within 4 %
    /// it clicks to its original size on that axis, or back to the proportions of the other axis.
    static func snappedStretch(_ stretch: CGFloat, scale: CGFloat, other: CGFloat) -> CGFloat? {
        for target in [1 / scale, other] where abs(stretch - target) < 0.04 * target {
            return target
        }
        return nil
    }
}

/// The pixel work behind the lasso, on CPU buffers (RGBA8 premultiplied, row 0 at the top).
/// Pure CoreGraphics so it's testable without Metal.
enum SelectionPixels {

    /// Coverage (0–255) of a closed polygon, one byte per pixel: anti-aliased, or (`hard`) all or nothing.
    static func rasterize(_ polygon: [CGPoint], width: Int, height: Int, hard: Bool = false) -> [UInt8] {
        var mask = [UInt8](repeating: 0, count: width * height)
        guard polygon.count >= 3 else { return mask }
        mask.withUnsafeMutableBytes { ptr in
            guard let ctx = CGContext(data: ptr.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            flipToCanvas(ctx, height: height)
            ctx.setShouldAntialias(!hard)
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

    /// The smallest pixel rectangle holding everything with any opacity; nil when it's all clear.
    static func contentBounds(_ rgba: [UInt8], width: Int, height: Int) -> CGRect? {
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = y * width
            for x in 0..<width where rgba[(row + x) * 4 + 3] != 0 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// The shape under a tap, as a mask: every painted pixel connected to it (diagonals count).
    /// A tap that misses a thin line by up to `reach` pixels still picks it. Nil if there's no paint there.
    static func connectedShape(_ rgba: [UInt8], width: Int, height: Int, at point: (x: Int, y: Int),
                               reach: Int = 8) -> [UInt8]? {
        guard rgba.count == width * height * 4 else { return nil }
        func painted(_ x: Int, _ y: Int) -> Bool { rgba[(y * width + x) * 4 + 3] != 0 }
        // The nearest painted pixel within reach of the tap.
        var seed: (Int, Int)?
        var best = Int.max
        for dy in -reach...reach {
            for dx in -reach...reach {
                let x = point.x + dx, y = point.y + dy
                guard x >= 0, y >= 0, x < width, y < height, painted(x, y) else { continue }
                let d = dx * dx + dy * dy
                if d < best && d <= reach * reach { best = d; seed = (x, y) }
            }
        }
        guard let (sx, sy) = seed else { return nil }
        var mask = [UInt8](repeating: 0, count: width * height)
        var stack = [(sx, sy)]
        mask[sy * width + sx] = 255
        while let (x, y) = stack.popLast() {
            for dy in -1...1 {
                for dx in -1...1 where dx != 0 || dy != 0 {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                    let i = ny * width + nx
                    if mask[i] == 0 && painted(nx, ny) { mask[i] = 255; stack.append((nx, ny)) }
                }
            }
        }
        return mask
    }

    /// `rgba` drawn through a canvas-space affine transform: high-quality resampling, or (`hard`)
    /// nearest pixel, so pixel art stays crisp when moved, scaled or rotated.
    static func render(_ rgba: [UInt8], width: Int, height: Int, transform: CGAffineTransform,
                       hard: Bool = false) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: width * height * 4)
        guard rgba.count == out.count, let image = image(rgba, width: width, height: height) else { return out }
        out.withUnsafeMutableBytes { ptr in
            guard let ctx = CGContext(data: ptr.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: bitmapInfo) else { return }
            ctx.interpolationQuality = hard ? .none : .high
            ctx.setShouldAntialias(!hard)
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

