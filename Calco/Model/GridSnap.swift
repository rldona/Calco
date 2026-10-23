import CoreGraphics
import Foundation

/// Moving on a grid: what's moved sits down on it at fixed steps instead of sliding freely, its
/// box's top-left corner on a grid line (a 16 px block lands on a 16 px tile). Saved with the
/// project, like symmetry.
struct GridSnap: Codable, Equatable {
    /// Canvas pixels between grid lines.
    var step: Int = 8
    /// Faint lines over the canvas, to see where things will land.
    var visible = true

    static let steps = [1, 2, 4, 8, 16, 32]

    /// The offset that puts `box` (where the drawing sits before any move) moved by `offset` with
    /// its top-left corner on the nearest grid line.
    func snapped(_ offset: CGVector, box: CGRect) -> CGVector {
        let s = CGFloat(max(step, 1))
        let x = ((box.minX + offset.dx) / s).rounded() * s, y = ((box.minY + offset.dy) / s).rounded() * s
        return CGVector(dx: x - box.minX, dy: y - box.minY)
    }
}
