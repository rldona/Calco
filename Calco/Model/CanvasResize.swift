import CoreGraphics
import Foundation

/// Making the canvas bigger or smaller without scaling the drawing: space is added, or cut, around
/// it, and the anchor says which side the drawing stays against. Pure, so it's testable without Metal.
enum CanvasResize {

    /// Where the drawing stays: the space goes on the other sides (centre: around it evenly).
    enum Anchor: Int, CaseIterable, Identifiable {
        case topLeft, top, topRight, left, center, right, bottomLeft, bottom, bottomRight
        var id: Int { rawValue }
        /// 0 left, 1 centre, 2 right.
        var column: Int { rawValue % 3 }
        /// 0 top, 1 middle, 2 bottom.
        var row: Int { rawValue / 3 }
    }

    /// How far the drawing moves, in canvas pixels (y down), going from `old` to `new`.
    static func offset(from old: CanvasSize, to new: CanvasSize, anchor: Anchor) -> (dx: Int, dy: Int) {
        func shift(_ grow: Int, _ place: Int) -> Int { Int((Double(grow * place) / 2).rounded(.down)) }
        return (shift(new.width - old.width, anchor.column), shift(new.height - old.height, anchor.row))
    }

    /// Canvas pixels (RGBA8) moved into a canvas of the new size; what falls outside is cut.
    static func shifted(_ rgba: [UInt8], from old: CanvasSize, to new: CanvasSize, dx: Int, dy: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: new.width * new.height * 4)
        guard rgba.count == old.width * old.height * 4 else { return out }
        let x0 = max(0, -dx), x1 = min(old.width, new.width - dx)
        guard x1 > x0 else { return out }
        for y in 0..<old.height {
            let ny = y + dy
            guard ny >= 0, ny < new.height else { continue }
            let src = (y * old.width + x0) * 4, dst = (ny * new.width + x0 + dx) * 4
            out.replaceSubrange(dst..<(dst + (x1 - x0) * 4), with: rgba[src..<(src + (x1 - x0) * 4)])
        }
        return out
    }

    /// A piece moved by (dx, dy) and cut to a canvas of `size`; nil when nothing of it is left.
    /// A stroke's recipe moves with it, so it stays sharp and editable.
    static func shifted(_ piece: StrokePiece, dx: Int, dy: Int, in size: CanvasSize) -> StrokePiece? {
        let nx = piece.x + dx, ny = piece.y + dy
        let x0 = max(nx, 0), y0 = max(ny, 0)
        let x1 = min(nx + piece.width, size.width), y1 = min(ny + piece.height, size.height)
        guard x1 > x0, y1 > y0 else { return nil }
        let w = x1 - x0, h = y1 - y0
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        for row in 0..<h {
            let src = ((y0 - ny + row) * piece.width + (x0 - nx)) * 4, dst = row * w * 4
            pixels.replaceSubrange(dst..<(dst + w * 4), with: piece.pixels[src..<(src + w * 4)])
        }
        guard !SelectionPixels.isEmpty(pixels) else { return nil }
        let move = CGAffineTransform(translationX: CGFloat(dx), y: CGFloat(dy))
        return StrokePiece(x: x0, y: y0, width: w, height: h, pixels: pixels, recipe: piece.recipe?.transformed(move))
    }

    /// The pivot (0–1, origin bottom-left) kept on the same pixel of the drawing.
    static func pivot(_ p: Pivot, from old: CanvasSize, to new: CanvasSize, dx: Int, dy: Int) -> Pivot {
        let x = p.x * Double(old.width) + Double(dx)
        let fromTop = (1 - p.y) * Double(old.height) + Double(dy)
        return Pivot(x: x / Double(new.width), y: 1 - fromTop / Double(new.height))
    }

    /// The smallest canvas holding every drawing, given their painted bounds (canvas pixels):
    /// the size, and where its top-left corner sits on the current canvas. Nil when nothing's drawn.
    static func fit(_ bounds: [CGRect]) -> CGRect? {
        let all = bounds.reduce(CGRect.null) { $0.union($1) }
        return all.isNull ? nil : all.integral
    }
}
