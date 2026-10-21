import CoreGraphics
import Foundation

/// A path drawn with the Pen: points joined by straight lines, or curves where a point has
/// handles. Canvas pixels. Pure geometry, so it can be tested without Metal.
struct PenPath: Codable, Equatable {
    struct Node: Codable, Equatable {
        var point: CGPoint
        /// Where the curve comes in and goes out (absolute); nil on a corner's straight side.
        var handleIn: CGPoint?
        var handleOut: CGPoint?
        /// A smooth point keeps its two handles in line: pulling one turns the other.
        var smooth = false

        var isCurve: Bool { handleIn != nil || handleOut != nil }
    }

    var nodes: [Node] = []
    var closed = false

    /// Segments between nodes: n − 1, and one more back to the start when closed.
    var segmentCount: Int { nodes.count < 2 ? 0 : closed ? nodes.count : nodes.count - 1 }

    /// The cubic Bézier of segment `i`: its start, two control points and end.
    func segment(_ i: Int) -> (CGPoint, CGPoint, CGPoint, CGPoint) {
        let a = nodes[i], b = nodes[(i + 1) % nodes.count]
        return (a.point, a.handleOut ?? a.point, b.handleIn ?? b.point, b.point)
    }

    static func point(_ s: (CGPoint, CGPoint, CGPoint, CGPoint), _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        return CGPoint(x: a * s.0.x + b * s.1.x + c * s.2.x + d * s.3.x,
                       y: a * s.0.y + b * s.1.y + c * s.2.y + d * s.3.y)
    }

    /// The path as a polyline, a point every `step` canvas pixels or so along each curve
    /// (straight segments need only their ends).
    func polyline(step: CGFloat = 2) -> [CGPoint] {
        guard let first = nodes.first else { return [] }
        var out = [first.point]
        for i in 0..<segmentCount {
            let s = segment(i)
            let straight = s.1 == s.0 && s.2 == s.3
            let rough = Self.distance(s.0, s.1) + Self.distance(s.1, s.2) + Self.distance(s.2, s.3)
            let n = straight ? 1 : max(4, min(400, Int(rough / max(step, 0.25))))
            for k in 1...n { out.append(Self.point(s, CGFloat(k) / CGFloat(n))) }
        }
        if closed, out.count > 1 { out.removeLast() }      // the start again; the stamps close it
        return out
    }

    /// The closest point of the path to `p`: which segment, where along it, and how far.
    func nearest(to p: CGPoint) -> (segment: Int, t: CGFloat, distance: CGFloat)? {
        var best: (Int, CGFloat, CGFloat)?
        for i in 0..<segmentCount {
            let s = segment(i)
            let n = 48
            for k in 0...n {
                let t = CGFloat(k) / CGFloat(n)
                let d = Self.distance(Self.point(s, t), p)
                if best == nil || d < best!.2 { best = (i, t, d) }
            }
        }
        return best.map { (segment: $0.0, t: $0.1, distance: $0.2) }
    }

    /// Adds a point on segment `i` at `t` without changing the path's shape (de Casteljau):
    /// a curve gets handles on both sides of the new point. Returns its index.
    @discardableResult
    mutating func insert(onSegment i: Int, at t: CGFloat) -> Int {
        let s = segment(i)
        func lerp(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t) }
        let p01 = lerp(s.0, s.1), p12 = lerp(s.1, s.2), p23 = lerp(s.2, s.3)
        let p012 = lerp(p01, p12), p123 = lerp(p12, p23)
        let mid = lerp(p012, p123)
        let straight = s.1 == s.0 && s.2 == s.3
        let j = (i + 1) % nodes.count
        if !straight {
            nodes[i].handleOut = p01
            nodes[j].handleIn = p23
        }
        let node = Node(point: mid, handleIn: straight ? nil : p012, handleOut: straight ? nil : p123, smooth: !straight)
        let at = i + 1
        nodes.insert(node, at: at)
        return at
    }

    /// Moves a point, its handles along with it.
    mutating func move(node i: Int, to p: CGPoint) {
        let d = CGPoint(x: p.x - nodes[i].point.x, y: p.y - nodes[i].point.y)
        func shift(_ q: CGPoint?) -> CGPoint? { q.map { CGPoint(x: $0.x + d.x, y: $0.y + d.y) } }
        nodes[i].point = p
        nodes[i].handleIn = shift(nodes[i].handleIn)
        nodes[i].handleOut = shift(nodes[i].handleOut)
    }

    /// Sets the outgoing (or incoming) handle of point `i`. On a smooth point the other handle
    /// turns to stay in line, keeping its own length.
    mutating func setHandle(of i: Int, outgoing: Bool, to h: CGPoint) {
        let p = nodes[i].point
        if outgoing { nodes[i].handleOut = h } else { nodes[i].handleIn = h }
        guard nodes[i].smooth else { return }
        let other = outgoing ? nodes[i].handleIn : nodes[i].handleOut
        let length = other.map { Self.distance($0, p) } ?? Self.distance(h, p)
        let d = Self.distance(h, p)
        guard d > 0.01 else { return }
        let mirrored = CGPoint(x: p.x - (h.x - p.x) / d * length, y: p.y - (h.y - p.y) / d * length)
        if outgoing { nodes[i].handleIn = mirrored } else { nodes[i].handleOut = mirrored }
    }

    /// Pulls both handles out of point `i` towards `h`, mirrored: the drag right after placing a
    /// point, or after tapping a corner to curve it.
    mutating func pullHandles(of i: Int, to h: CGPoint) {
        nodes[i].smooth = true
        nodes[i].handleOut = h
        nodes[i].handleIn = CGPoint(x: 2 * nodes[i].point.x - h.x, y: 2 * nodes[i].point.y - h.y)
    }

    /// Turns point `i` into a curve (handles along the line through its neighbours, a third of
    /// the way to each) or back into a corner.
    mutating func setCurve(_ curve: Bool, at i: Int) {
        guard curve else {
            nodes[i].handleIn = nil; nodes[i].handleOut = nil; nodes[i].smooth = false
            return
        }
        let p = nodes[i].point
        let hasPrev = i > 0 || closed, hasNext = i < nodes.count - 1 || closed
        let prev = hasPrev ? nodes[(i - 1 + nodes.count) % nodes.count].point : p
        let next = hasNext ? nodes[(i + 1) % nodes.count].point : p
        var dir = CGPoint(x: next.x - prev.x, y: next.y - prev.y)
        var len = Self.distance(dir, .zero)
        if len < 0.01 { dir = CGPoint(x: 1, y: 0); len = 1 }
        let ux = dir.x / len, uy = dir.y / len
        let back = Self.distance(p, prev) / 3, ahead = Self.distance(p, next) / 3
        nodes[i].handleIn = hasPrev ? CGPoint(x: p.x - ux * back, y: p.y - uy * back) : nil
        nodes[i].handleOut = hasNext ? CGPoint(x: p.x + ux * ahead, y: p.y + uy * ahead) : nil
        nodes[i].smooth = true
    }

    /// Every point and handle moved by `t`.
    func applying(_ t: CGAffineTransform) -> PenPath {
        var out = self
        for i in out.nodes.indices {
            out.nodes[i].point = out.nodes[i].point.applying(t)
            out.nodes[i].handleIn = out.nodes[i].handleIn?.applying(t)
            out.nodes[i].handleOut = out.nodes[i].handleOut?.applying(t)
        }
        return out
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
}

/// A Pen path and how it's drawn (the Shapes tool's outline, fill, size and brush), kept with
/// the stroke so it can be edited again.
struct PenDrawing: Codable, Equatable {
    var path: PenPath
    var style: ShapeOptions
}
