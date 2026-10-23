import Foundation
import simd

/// Drawing with symmetry: every stamp is painted again in a mirror across a vertical axis
/// (left and right), a horizontal one (top and bottom), or both (four ways). The axes are canvas
/// positions, always on a pixel edge or a pixel centre, so a pixel-art mirror is exact.
/// Saved with the project, since a symmetric sprite stays symmetric.
struct Symmetry: Codable, Equatable {
    enum Mode: String, Codable, CaseIterable, Identifiable {
        /// A vertical axis: left mirrors right.
        case vertical
        /// A horizontal axis: top mirrors bottom.
        case horizontal
        /// Both: four ways.
        case both
        var id: String { rawValue }
    }

    var mode: Mode
    /// Where the vertical axis is, in canvas pixels from the left.
    var x: Double
    /// Where the horizontal axis is, in canvas pixels from the top.
    var y: Double

    /// The axes through the middle of a canvas.
    static func centered(_ mode: Mode, width: Int, height: Int) -> Symmetry {
        Symmetry(mode: mode, x: Double(width) / 2, y: Double(height) / 2)
    }

    /// To the nearest half pixel, inside `0...limit`: an edge or a centre, so mirrors are exact.
    static func snapped(_ v: Double, limit: Int) -> Double {
        min(max((v * 2).rounded() / 2, 0), Double(limit))
    }

    var mirrorsX: Bool { mode != .horizontal }
    var mirrorsY: Bool { mode != .vertical }

    /// `p` and its mirror images, itself first.
    func images(of p: SIMD2<Float>) -> [SIMD2<Float>] {
        let mx = Float(2 * x) - p.x, my = Float(2 * y) - p.y
        switch mode {
        case .vertical: return [p, SIMD2(mx, p.y)]
        case .horizontal: return [p, SIMD2(p.x, my)]
        case .both: return [p, SIMD2(mx, p.y), SIMD2(p.x, my), SIMD2(mx, my)]
        }
    }

    /// How a movement looks in each image (the same order as `images`): mirrored along with it.
    func images(ofDelta d: SIMD2<Float>) -> [SIMD2<Float>] {
        switch mode {
        case .vertical: return [d, SIMD2(-d.x, d.y)]
        case .horizontal: return [d, SIMD2(d.x, -d.y)]
        case .both: return [d, SIMD2(-d.x, d.y), SIMD2(d.x, -d.y), SIMD2(-d.x, -d.y)]
        }
    }

    /// Stamps with their mirror images, image by image. With `hard` (pixel art) each stamp sits
    /// on whole pixels first, so its mirror lands on the mirrored pixels exactly.
    func mirrored(_ stamps: [CanvasRenderer.Stamp], hard: Bool) -> [CanvasRenderer.Stamp] {
        let base = hard ? stamps.map { s in
            var s = s; s.position = CanvasRenderer.pixelPosition(s); return s
        } : stamps
        let count = images(of: .zero).count
        var out: [CanvasRenderer.Stamp] = []
        out.reserveCapacity(base.count * count)
        for i in 0..<count {
            for s in base {
                var m = s
                m.position = images(of: s.position)[i]
                out.append(m)
            }
        }
        return out
    }
}
