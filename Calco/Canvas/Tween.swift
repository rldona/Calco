import CoreGraphics
import Foundation

/// Motion tweens: from a drawing's pose to an end pose, the poses in between. Pure, so it can be
/// tested without the editor.
enum Tween {

    /// How the motion speeds up and slows down.
    enum Easing: String, Codable, CaseIterable, Identifiable {
        case linear, easeIn, easeOut, easeInOut
        var id: String { rawValue }

        /// `t` 0–1 → how far along, 0–1.
        func apply(_ t: CGFloat) -> CGFloat {
            let t = min(max(t, 0), 1)
            switch self {
            case .linear: return t
            case .easeIn: return t * t
            case .easeOut: return 1 - (1 - t) * (1 - t)
            case .easeInOut: return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
            }
        }
    }

    /// The pose `k` of `count` on the way from `start` (identity) to `end`: position (along a
    /// curve through `bend` when it isn't zero), scale, stretch and turn eased. A flip happens on
    /// the last pose only.
    static func pose(_ k: Int, of count: Int, to end: FloatingSelection, easing: Easing, bend: CGVector = .zero) -> FloatingSelection {
        var p = end
        guard count > 0 else { return p }
        let t = easing.apply(CGFloat(k) / CGFloat(count))
        let o = path(end.offset, bend: bend, at: t)
        p.offset = o
        p.scale = 1 + (end.scale - 1) * t
        p.stretch = CGSize(width: 1 + (end.stretch.width - 1) * t, height: 1 + (end.stretch.height - 1) * t)
        p.rotation = end.rotation * t
        p.flipped = k == count ? end.flipped : false
        return p
    }

    /// Where the anchor is at `t` on the way to `end`: a straight line, or with `bend` a curve
    /// that passes `bend` away from the line's middle, halfway.
    static func path(_ end: CGVector, bend: CGVector, at t: CGFloat) -> CGVector {
        // A quadratic Bézier whose control point puts the curve's middle at mid + bend.
        let control = CGVector(dx: end.dx / 2 + 2 * bend.dx, dy: end.dy / 2 + 2 * bend.dy)
        let u = 1 - t
        return CGVector(dx: 2 * u * t * control.dx + t * t * end.dx, dy: 2 * u * t * control.dy + t * t * end.dy)
    }
}
