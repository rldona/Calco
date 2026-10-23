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

/// An area marked on the canvas without lifting anything: brush, eraser, fill, shapes and smudge
/// only reach inside it, and the bar over it fills, clears, copies, cuts or lifts it to transform.
/// One coverage byte per canvas pixel: 0 outside, 255 inside, in between on a soft edge.
struct SelectionMask: Equatable {
    let width: Int
    let height: Int
    private(set) var coverage: [UInt8]

    /// How a new lasso, rectangle or wand pick meets the selection already there.
    enum Combine: String, Codable, CaseIterable, Identifiable {
        case replace, add, subtract
        var id: String { rawValue }
    }

    init(width: Int, height: Int, coverage: [UInt8]) {
        self.width = width
        self.height = height
        self.coverage = coverage.count == width * height ? coverage : [UInt8](repeating: 0, count: width * height)
    }

    static func all(width: Int, height: Int) -> SelectionMask {
        SelectionMask(width: width, height: height, coverage: [UInt8](repeating: 255, count: width * height))
    }

    /// `area` (same size) taking the selection's place, added to it, or taken out of it.
    func combined(with area: [UInt8], _ how: Combine) -> SelectionMask {
        guard area.count == coverage.count else { return self }
        switch how {
        case .replace: return SelectionMask(width: width, height: height, coverage: area)
        case .add: return SelectionMask(width: width, height: height, coverage: zip(coverage, area).map { max($0, $1) })
        case .subtract:
            return SelectionMask(width: width, height: height,
                                 coverage: zip(coverage, area).map { UInt8((Int($0) * (255 - Int($1)) + 127) / 255) })
        }
    }

    /// Everything that wasn't selected, and nothing that was.
    var inverted: SelectionMask {
        SelectionMask(width: width, height: height, coverage: coverage.map { 255 - $0 })
    }

    var isEmpty: Bool { !coverage.contains { $0 != 0 } }

    /// The smallest pixel rectangle holding the selection; nil when it's empty.
    var bounds: CGRect? {
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = y * width
            for x in 0..<width where coverage[row + x] != 0 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// Canvas pixels with the coverage as alpha (premultiplied white): the mask the GPU clips
    /// strokes with, and what's resampled when a transformed selection is put down.
    var rgba: [UInt8] {
        var out = [UInt8](repeating: 0, count: coverage.count * 4)
        for (i, c) in coverage.enumerated() where c != 0 {
            out[i * 4] = c; out[i * 4 + 1] = c; out[i * 4 + 2] = c; out[i * 4 + 3] = c
        }
        return out
    }

    /// Where the selection ends up when what's inside it is moved by `transform` (canvas space).
    func transformed(_ transform: CGAffineTransform, hard: Bool) -> SelectionMask {
        let placed = SelectionPixels.render(rgba, width: width, height: height, transform: transform, hard: hard)
        return SelectionMask(width: width, height: height, coverage: stride(from: 3, to: placed.count, by: 4).map { placed[$0] })
    }

    /// The border between selected and unselected pixels (half coverage or more counts as in),
    /// as a path along the pixel edges in canvas coordinates: what the marching ants trace.
    var outline: CGPath {
        let path = CGMutablePath()
        func inside(_ x: Int, _ y: Int) -> Bool {
            x >= 0 && y >= 0 && x < width && y < height && coverage[y * width + x] >= 128
        }
        // Horizontal edges, between row y - 1 and row y, joined into runs.
        for y in 0...height {
            var start: Int?
            for x in 0...width {
                let edge = x < width && inside(x, y - 1) != inside(x, y)
                if edge, start == nil { start = x }
                if !edge, let s = start {
                    path.move(to: CGPoint(x: s, y: y)); path.addLine(to: CGPoint(x: x, y: y))
                    start = nil
                }
            }
        }
        // Vertical edges, between column x - 1 and column x.
        for x in 0...width {
            var start: Int?
            for y in 0...height {
                let edge = y < height && inside(x - 1, y) != inside(x, y)
                if edge, start == nil { start = y }
                if !edge, let s = start {
                    path.move(to: CGPoint(x: x, y: s)); path.addLine(to: CGPoint(x: x, y: y))
                    start = nil
                }
            }
        }
        return path
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

    /// `color` (0–1 RGB, opaque) laid into `rgba` through a coverage mask: over what's there,
    /// behind it, or (inside) recolouring what's drawn while keeping its coverage.
    static func fill(_ rgba: [UInt8], mask: [UInt8], color: SIMD3<Float>,
                     mode: CanvasRenderer.PaintMode = .front) -> [UInt8] {
        guard rgba.count == mask.count * 4 else { return rgba }
        let rgb = [color.x, color.y, color.z].map { Int((min(max($0, 0), 1) * 255).rounded()) }
        var out = rgba
        for (i, m) in mask.enumerated() where m > 0 {
            let p = i * 4, cov = Int(m), a = Int(rgba[p + 3])
            switch mode {
            case .front:
                // The colour at `cov` over what's there.
                for c in 0..<3 { out[p + c] = UInt8((rgb[c] * cov + Int(rgba[p + c]) * (255 - cov) + 127) / 255) }
                out[p + 3] = UInt8((255 * cov + a * (255 - cov) + 127) / 255)
            case .behind:
                // What's there over the colour at `cov`.
                let under = (255 - a) * cov
                for c in 0..<3 { out[p + c] = UInt8(min(255, Int(rgba[p + c]) + (rgb[c] * under / 255 + 127) / 255)) }
                out[p + 3] = UInt8(min(255, a + (under + 127) / 255))
            case .inside:
                for c in 0..<3 {
                    let recoloured = rgb[c] * a / 255
                    out[p + c] = UInt8((recoloured * cov + Int(rgba[p + c]) * (255 - cov) + 127) / 255)
                }
            }
        }
        return out
    }

    /// `after` inside the mask and `before` outside it: an edit kept to the selection.
    static func blend(_ after: [UInt8], _ before: [UInt8], mask: [UInt8]) -> [UInt8] {
        guard after.count == before.count, after.count == mask.count * 4 else { return after }
        var out = before
        for (i, m) in mask.enumerated() where m > 0 {
            for c in 0..<4 {
                let p = i * 4 + c
                out[p] = UInt8((Int(after[p]) * Int(m) + Int(before[p]) * (255 - Int(m)) + 127) / 255)
            }
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

