import CoreGraphics

/// How the canvas sits on screen: zoom, rotation and pan on top of the centered "fit" placement.
/// Pure geometry so the renderer, the Pencil and the pivot overlay all agree on where a pixel is.
///
/// `offset` is in points. Functions take the view size in whatever unit the caller works in
/// (points for touches, pixels for Metal) plus `unitsPerPoint` to scale the offset to match.
struct CanvasTransform: Equatable {
    var scale: CGFloat = 1
    var rotation: CGFloat = 0
    var offset: CGSize = .zero

    static let identity = CanvasTransform()
    static let scaleRange: ClosedRange<CGFloat> = 0.25...16

    /// Canvas pixels (origin top-left) → view coordinates (origin top-left).
    func canvasToView(canvas: SIMD2<Int>, viewSize: CGSize, unitsPerPoint: CGFloat = 1) -> CGAffineTransform {
        let fit = CanvasRenderer.fitRect(canvas: canvas, in: viewSize)
        let base = fit.width / CGFloat(canvas.x)
        return CGAffineTransform(translationX: -CGFloat(canvas.x) / 2, y: -CGFloat(canvas.y) / 2)
            .concatenating(CGAffineTransform(scaleX: base * scale, y: base * scale))
            .concatenating(CGAffineTransform(rotationAngle: rotation))
            .concatenating(CGAffineTransform(translationX: fit.midX + offset.width * unitsPerPoint,
                                             y: fit.midY + offset.height * unitsPerPoint))
    }

    func viewToCanvas(canvas: SIMD2<Int>, viewSize: CGSize, unitsPerPoint: CGFloat = 1) -> CGAffineTransform {
        canvasToView(canvas: canvas, viewSize: viewSize, unitsPerPoint: unitsPerPoint).inverted()
    }

    // MARK: - Gestures (view points)

    /// Zooms by `factor` keeping the point under `anchor` fixed. Scale is clamped.
    mutating func zoom(by factor: CGFloat, around anchor: CGPoint, viewSize: CGSize) {
        let newScale = min(max(scale * factor, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
        let f = newScale / scale
        let center = CGPoint(x: viewSize.width / 2 + offset.width, y: viewSize.height / 2 + offset.height)
        let moved = CGPoint(x: anchor.x + (center.x - anchor.x) * f, y: anchor.y + (center.y - anchor.y) * f)
        offset = CGSize(width: moved.x - viewSize.width / 2, height: moved.y - viewSize.height / 2)
        scale = newScale
    }

    /// Rotates by `angle` radians around `anchor`.
    mutating func rotate(by angle: CGFloat, around anchor: CGPoint, viewSize: CGSize) {
        let center = CGPoint(x: viewSize.width / 2 + offset.width, y: viewSize.height / 2 + offset.height)
        let d = CGPoint(x: center.x - anchor.x, y: center.y - anchor.y)
        let c = cos(angle), s = sin(angle)
        let moved = CGPoint(x: anchor.x + d.x * c - d.y * s, y: anchor.y + d.x * s + d.y * c)
        offset = CGSize(width: moved.x - viewSize.width / 2, height: moved.y - viewSize.height / 2)
        rotation += angle
    }

    mutating func pan(by delta: CGSize) {
        offset.width += delta.width
        offset.height += delta.height
    }
}
