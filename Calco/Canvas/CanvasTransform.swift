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
    /// Mirrored left to right on screen only (the drawing isn't touched), to catch mistakes with
    /// fresh eyes. Survives fitting the canvas.
    var flipped = false

    static let identity = CanvasTransform()
    static let scaleRange: ClosedRange<CGFloat> = 0.25...16

    /// Canvas pixels (origin top-left) → view coordinates (origin top-left).
    func canvasToView(canvas: SIMD2<Int>, viewSize: CGSize, unitsPerPoint: CGFloat = 1) -> CGAffineTransform {
        let fit = CanvasRenderer.fitRect(canvas: canvas, in: viewSize)
        let base = fit.width / CGFloat(canvas.x)
        return CGAffineTransform(translationX: -CGFloat(canvas.x) / 2, y: -CGFloat(canvas.y) / 2)
            .concatenating(CGAffineTransform(scaleX: (flipped ? -1 : 1) * base * scale, y: base * scale))
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

    /// Zooms around the middle of the view (keyboard / menu zoom). No view size needed:
    /// keeping the view centre fixed just scales the offset.
    mutating func zoom(by factor: CGFloat) {
        let newScale = min(max(scale * factor, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
        let f = newScale / scale
        offset = CGSize(width: offset.width * f, height: offset.height * f)
        scale = newScale
    }

    /// Fitted and upright, whether or not it's mirrored.
    var isFit: Bool {
        // A hair's breadth of floating-point drift from gestures still counts.
        abs(scale - 1) < 1e-6 && abs(rotation) < 1e-6 && abs(offset.width) < 0.01 && abs(offset.height) < 0.01
    }

    mutating func pan(by delta: CGSize) {
        offset.width += delta.width
        offset.height += delta.height
    }

    // MARK: - Snapping

    // While you twist, pinch or drag with two fingers, the canvas clicks into upright (and every
    // quarter turn), its fitted size and the middle, so it's easy to put back straight.

    /// Within 5° of a quarter turn (0°, 90°, 180°, 270°…), exactly that.
    static func snappedRotation(_ r: CGFloat) -> CGFloat? {
        let quarter = CGFloat.pi / 2
        let nearest = (r / quarter).rounded() * quarter
        return abs(r - nearest) < 5 * .pi / 180 ? nearest : nil
    }

    /// Within 6 % of the fitted size, the fitted size.
    static func snappedScale(_ s: CGFloat) -> CGFloat? {
        abs(s - 1) < 0.06 ? 1 : nil
    }

    /// Within `tolerance` points of the middle, the middle.
    static func snappedOffset(_ o: CGSize, tolerance: CGFloat = 14) -> CGSize? {
        hypot(o.width, o.height) < tolerance ? .zero : nil
    }
}
