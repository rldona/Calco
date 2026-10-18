import XCTest
@testable import Calco

final class StrokeBuilderTests: XCTestCase {
    func testFirstSampleProducesOneStamp() {
        var b = StrokeBuilder()
        b.begin()
        let s = b.add(.init(position: [10, 10], force: 1))
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s[0].radius, 6, accuracy: 0.001)
    }

    func testStampsAreEvenlySpaced() {
        var b = StrokeBuilder(baseRadius: 8, spacing: 0.5)
        b.begin()
        _ = b.add(.init(position: [0, 0], force: 1))
        let s = b.add(.init(position: [100, 0], force: 1))
        // radius 8 * spacing 0.5 = 4px apart along 100px => ~25 stamps
        XCTAssertGreaterThan(s.count, 20)
        for pair in zip(s, s.dropFirst()) {
            XCTAssertEqual(pair.1.position.x - pair.0.position.x, 4, accuracy: 0.01)
        }
    }

    func testPressureShrinksRadius() {
        var b = StrokeBuilder(baseRadius: 10, minRadiusFactor: 0.2)
        b.begin()
        let light = b.add(.init(position: [0, 0], force: 0))
        XCTAssertEqual(light[0].radius, 2, accuracy: 0.001)
    }

    func testSmoothingIronsOutWobbleAndFinishCatchesUp() {
        // A zig-zag along x: y jumps ±10 every sample.
        func run(_ smoothing: Float) -> (maxY: Float, end: SIMD2<Float>) {
            var b = StrokeBuilder(baseRadius: 4, spacing: 0.5)
            b.smoothing = smoothing
            b.begin()
            var stamps: [CanvasRenderer.Stamp] = []
            for i in 0...40 { stamps += b.add(.init(position: [Float(i) * 5, i % 2 == 0 ? 10 : -10], force: 1)) }
            stamps += b.finish()
            // Wobble in the middle of the stroke: the start begins at the pen and finish() runs out
            // to where it lifted (y = +10), so both ends legitimately touch the zig-zag.
            let middle = stamps.filter { (50...150).contains($0.position.x) }
            return (middle.map { abs($0.position.y) }.max() ?? 0, stamps.last!.position)
        }
        let raw = run(0), smooth = run(0.8)
        XCTAssertGreaterThan(raw.maxY, 9)
        XCTAssertLessThan(smooth.maxY, raw.maxY / 2, "the wobble shrinks")
        // Stamps land every radius × spacing = 2 px, so "where the pen lifted" means within one step.
        XCTAssertEqual(smooth.end.x, 200, accuracy: 2, "finish draws to where the pen lifted")
        XCTAssertEqual(raw.end.x, 200, accuracy: 2)
        XCTAssertLessThan(abs(smooth.end.x - raw.end.x), 2, "smoothing doesn't cut the stroke short")
    }

    func testNoSmoothingFinishAddsNothing() {
        var b = StrokeBuilder()
        b.begin()
        _ = b.add(.init(position: [0, 0], force: 1))
        _ = b.add(.init(position: [50, 0], force: 1))
        XCTAssertTrue(b.finish().isEmpty)
    }
}
