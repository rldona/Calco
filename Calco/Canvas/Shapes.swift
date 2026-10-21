import CoreGraphics
import Foundation
import simd

/// The Shapes tool's options: which shape, how its outline is drawn, and whether it's filled.
struct ShapeOptions: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case line, arrow, rectangle, ellipse, triangle, polygon, star, roundedRectangle
        var id: String { rawValue }
    }
    enum Outline: String, Codable, CaseIterable, Identifiable {
        case solid, dashed, dotted
        var id: String { rawValue }
    }
    enum Fill: String, Codable, CaseIterable, Identifiable {
        case none, filled, only
        var id: String { rawValue }
    }

    var kind = Kind.rectangle
    var outline = Outline.solid
    var fill = Fill.none
    /// Radius of the outline in canvas pixels, like a brush size.
    var size: Float = 4
    /// Sides of the polygon, points of the star.
    var sides = 6
    var points = 5
    /// Paint the outline with the brush chosen for the brush tool (a grainy pencil square); off,
    /// with the inker's clean line.
    var useBrush = false

    static let sidesRange = 3...12
    static let pointsRange = 3...12

    /// Lines and arrows have no inside.
    var canFill: Bool { kind != .line && kind != .arrow }
}

extension ShapeOptions.Kind {
    var icon: String {
        switch self {
        case .line: "line.diagonal"
        case .arrow: "arrow.up.right"
        case .rectangle: "square"
        case .ellipse: "circle"
        case .triangle: "triangle"
        case .polygon: "hexagon"
        case .star: "star"
        case .roundedRectangle: "app"
        }
    }

    var name: String {
        switch self {
        case .line: String(localized: "Line", bundle: AppLanguage.bundle)
        case .arrow: String(localized: "Arrow", bundle: AppLanguage.bundle)
        case .rectangle: String(localized: "Rectangle", bundle: AppLanguage.bundle)
        case .ellipse: String(localized: "Ellipse", bundle: AppLanguage.bundle)
        case .triangle: String(localized: "Triangle", bundle: AppLanguage.bundle)
        case .polygon: String(localized: "Polygon", bundle: AppLanguage.bundle)
        case .star: String(localized: "Star", bundle: AppLanguage.bundle)
        case .roundedRectangle: String(localized: "Rounded rectangle", bundle: AppLanguage.bundle)
        }
    }
}

/// Shapes as outlines, from where the finger went down to where it is. Pure geometry, canvas
/// pixels, so it can be tested without Metal.
enum ShapeGeometry {

    /// What the drag clicked into: a square or circle (equal sides), or a line at a multiple of 45°.
    enum Snap: Equatable { case none, even, angle(Int) }

    /// The drag from `a` to `b`, clicked into place near an even shape or a 45° line. Returns the
    /// end point to use and what it clicked into.
    static func snapped(_ kind: ShapeOptions.Kind, from a: CGPoint, to b: CGPoint) -> (end: CGPoint, snap: Snap) {
        let dx = b.x - a.x, dy = b.y - a.y
        switch kind {
        case .line, .arrow:
            let length = hypot(dx, dy)
            guard length > 1 else { return (b, .none) }
            let angle = atan2(dy, dx)
            let step = CGFloat.pi / 4
            let nearest = (angle / step).rounded() * step
            guard abs(angle - nearest) < 4 * .pi / 180 else { return (b, .none) }
            let degrees = (Int((nearest * 180 / .pi).rounded()) + 360) % 360
            return (CGPoint(x: a.x + cos(nearest) * length, y: a.y + sin(nearest) * length), .angle(degrees))
        default:
            let w = abs(dx), h = abs(dy)
            guard max(w, h) > 1, abs(w - h) < 0.06 * max(w, h) else { return (b, .none) }
            let side = max(w, h)
            return (CGPoint(x: a.x + (dx < 0 ? -side : side), y: a.y + (dy < 0 ? -side : side)), .even)
        }
    }

    /// The shape's outline: one or more polylines, and whether each closes on itself. The first
    /// closed one is also what a fill covers.
    static func paths(_ options: ShapeOptions, from a: CGPoint, to b: CGPoint) -> [(points: [CGPoint], closed: Bool)] {
        let r = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
        let c = CGPoint(x: r.midX, y: r.midY)
        switch options.kind {
        case .line:
            return [([a, b], false)]
        case .arrow:
            let length = hypot(b.x - a.x, b.y - a.y)
            guard length > 0.5 else { return [([a, b], false)] }
            let angle = atan2(b.y - a.y, b.x - a.x)
            // The head grows with the arrow and the line, within reason.
            let head = min(length * 0.35, max(14, CGFloat(options.size) * 5))
            func wing(_ turn: CGFloat) -> CGPoint {
                CGPoint(x: b.x - cos(angle + turn) * head, y: b.y - sin(angle + turn) * head)
            }
            return [([a, b], false), ([wing(.pi / 6), b, wing(-.pi / 6)], false)]
        case .rectangle:
            return [([CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                      CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)], true)]
        case .ellipse:
            return [(ring(c, rx: r.width / 2, ry: r.height / 2, count: segments(r), start: 0), true)]
        case .triangle:
            return [([CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)], true)]
        case .polygon:
            let n = min(max(options.sides, ShapeOptions.sidesRange.lowerBound), ShapeOptions.sidesRange.upperBound)
            return [(ring(c, rx: r.width / 2, ry: r.height / 2, count: n, start: -.pi / 2), true)]
        case .star:
            let n = min(max(options.points, ShapeOptions.pointsRange.lowerBound), ShapeOptions.pointsRange.upperBound)
            let outer = ring(c, rx: r.width / 2, ry: r.height / 2, count: n, start: -.pi / 2)
            let inner = ring(c, rx: r.width / 2 * 0.45, ry: r.height / 2 * 0.45, count: n, start: -.pi / 2 + .pi / CGFloat(n))
            return [(zip(outer, inner).flatMap { [$0, $1] }, true)]
        case .roundedRectangle:
            let k = min(r.width, r.height) * 0.22
            var pts: [CGPoint] = []
            let corners = [(CGPoint(x: r.maxX - k, y: r.minY + k), -CGFloat.pi / 2),
                           (CGPoint(x: r.maxX - k, y: r.maxY - k), 0),
                           (CGPoint(x: r.minX + k, y: r.maxY - k), CGFloat.pi / 2),
                           (CGPoint(x: r.minX + k, y: r.minY + k), CGFloat.pi)]
            for (centre, start) in corners {
                for i in 0...8 {
                    let t = start + CGFloat(i) / 8 * .pi / 2
                    pts.append(CGPoint(x: centre.x + cos(t) * k, y: centre.y + sin(t) * k))
                }
            }
            return [(pts, true)]
        }
    }

    /// Stamps along the outline, `radius` each: every `spacing` (a fraction of the radius) for a
    /// solid line, in dashes, or one dot every few widths. Dashes and dots are spread evenly so a
    /// closed shape doesn't end on a stub.
    static func stamps(along paths: [(points: [CGPoint], closed: Bool)], radius: Float, spacing: Float,
                       outline: ShapeOptions.Outline, alpha: Float = 1) -> [CanvasRenderer.Stamp] {
        let r = CGFloat(max(radius, 0.5))
        var out: [CanvasRenderer.Stamp] = []
        for path in paths {
            var pts = path.points
            if path.closed, let first = pts.first { pts.append(first) }
            guard pts.count >= 2 else { continue }
            let total = zip(pts, pts.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
            guard total > 0 else { continue }
            let step: CGFloat
            var isOn: (CGFloat) -> Bool = { _ in true }
            switch outline {
            case .solid:
                step = max(r * CGFloat(spacing), 0.3)
            case .dashed:
                step = max(r * CGFloat(spacing), 0.3)
                // A dash 4 widths long and a gap of 3, stretched so a whole number fit; an open
                // line also ends on a dash, not on a gap.
                let on: CGFloat = 4 / 7
                let period = path.closed ? total / max(1, (total / (r * 14)).rounded())
                    : total / (max(0, ((total - r * 8) / (r * 14)).rounded()) + on)
                isOn = { d in d.truncatingRemainder(dividingBy: period) <= period * on + 0.001 }
            case .dotted:
                step = total / max(1, (total / (r * 3)).rounded())
            }
            var d: CGFloat = 0
            var segment = 0, segStart: CGFloat = 0
            let end = path.closed && outline != .solid ? total - step * 0.5 : total
            while d <= end + 0.001 {
                // Walk to the segment holding distance d.
                while segment < pts.count - 2 {
                    let len = hypot(pts[segment + 1].x - pts[segment].x, pts[segment + 1].y - pts[segment].y)
                    if d <= segStart + len { break }
                    segStart += len
                    segment += 1
                }
                let p0 = pts[segment], p1 = pts[segment + 1]
                let len = max(hypot(p1.x - p0.x, p1.y - p0.y), 0.0001)
                let t = min(max((d - segStart) / len, 0), 1)
                if isOn(d) {
                    out.append(.init(position: SIMD2(Float(p0.x + (p1.x - p0.x) * t), Float(p0.y + (p1.y - p0.y) * t)),
                                     radius: Float(r), alpha: alpha))
                }
                d += step
            }
        }
        return out
    }

    /// The area a fill covers, or nil when the shape has no inside.
    static func fillPolygon(_ options: ShapeOptions, from a: CGPoint, to b: CGPoint) -> [CGPoint]? {
        guard options.canFill else { return nil }
        return paths(options, from: a, to: b).first { $0.closed }?.points
    }

    private static func ring(_ c: CGPoint, rx: CGFloat, ry: CGFloat, count: Int, start: CGFloat) -> [CGPoint] {
        (0..<count).map { i in
            let t = start + CGFloat(i) / CGFloat(count) * 2 * .pi
            return CGPoint(x: c.x + cos(t) * rx, y: c.y + sin(t) * ry)
        }
    }

    /// Enough segments that a big ellipse stays round.
    private static func segments(_ r: CGRect) -> Int {
        min(256, max(32, Int((r.width + r.height) / 4)))
    }
}
