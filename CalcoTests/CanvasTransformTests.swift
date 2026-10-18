import XCTest
@testable import Calco

final class CanvasTransformTests: XCTestCase {

    private let canvas = SIMD2<Int>(512, 256)
    private let view = CGSize(width: 1000, height: 800)

    private func assertClose(_ a: CGPoint, _ b: CGPoint, _ message: String = "", line: UInt = #line) {
        XCTAssertEqual(a.x, b.x, accuracy: 0.001, message, line: line)
        XCTAssertEqual(a.y, b.y, accuracy: 0.001, message, line: line)
    }

    func testIdentityIsTheCenteredFit() {
        let fit = CanvasRenderer.fitRect(canvas: canvas, in: view)
        let t = CanvasTransform.identity.canvasToView(canvas: canvas, viewSize: view)
        assertClose(CGPoint(x: 0, y: 0).applying(t), CGPoint(x: fit.minX, y: fit.minY))
        assertClose(CGPoint(x: 512, y: 256).applying(t), CGPoint(x: fit.maxX, y: fit.maxY))
    }

    func testViewToCanvasInvertsCanvasToView() {
        var tr = CanvasTransform()
        tr.zoom(by: 2.5, around: CGPoint(x: 300, y: 200), viewSize: view)
        tr.rotate(by: 0.7, around: CGPoint(x: 600, y: 500), viewSize: view)
        tr.pan(by: CGSize(width: -40, height: 90))
        let p = CGPoint(x: 123, y: 45)
        let back = p.applying(tr.canvasToView(canvas: canvas, viewSize: view))
                    .applying(tr.viewToCanvas(canvas: canvas, viewSize: view))
        assertClose(back, p)
    }

    func testZoomAndRotateKeepTheAnchorStill() {
        let anchor = CGPoint(x: 310, y: 420)
        var tr = CanvasTransform()
        let before = anchor.applying(tr.viewToCanvas(canvas: canvas, viewSize: view))

        tr.zoom(by: 3, around: anchor, viewSize: view)
        assertClose(anchor.applying(tr.viewToCanvas(canvas: canvas, viewSize: view)), before, "zoom")

        tr.rotate(by: .pi / 3, around: anchor, viewSize: view)
        assertClose(anchor.applying(tr.viewToCanvas(canvas: canvas, viewSize: view)), before, "rotate")
    }

    func testScaleIsClampedWithoutDrift() {
        let anchor = CGPoint(x: 100, y: 100)
        var tr = CanvasTransform()
        let before = anchor.applying(tr.viewToCanvas(canvas: canvas, viewSize: view))
        tr.zoom(by: 1000, around: anchor, viewSize: view)
        XCTAssertEqual(tr.scale, CanvasTransform.scaleRange.upperBound)
        assertClose(anchor.applying(tr.viewToCanvas(canvas: canvas, viewSize: view)), before)
        tr.zoom(by: 0.00001, around: anchor, viewSize: view)
        XCTAssertEqual(tr.scale, CanvasTransform.scaleRange.lowerBound)
    }

    func testOffsetScalesWithUnitsPerPoint() {
        var tr = CanvasTransform()
        tr.pan(by: CGSize(width: 10, height: 0))
        let points = CGPoint.zero.applying(tr.canvasToView(canvas: canvas, viewSize: view))
        let pixels = CGPoint.zero.applying(tr.canvasToView(
            canvas: canvas, viewSize: CGSize(width: 2000, height: 1600), unitsPerPoint: 2))
        assertClose(CGPoint(x: points.x * 2, y: points.y * 2), pixels)
    }
}
