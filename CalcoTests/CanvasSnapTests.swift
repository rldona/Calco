import XCTest
@testable import Calco

/// The canvas clicks into upright, fitted and centred while you move it with two fingers.
final class CanvasSnapTests: XCTestCase {
    private let deg = CGFloat.pi / 180

    func testRotationClicksOnEveryQuarterTurn() {
        XCTAssertEqual(CanvasTransform.snappedRotation(4 * deg), 0)
        XCTAssertEqual(CanvasTransform.snappedRotation(-3 * deg), 0)
        XCTAssertEqual(CanvasTransform.snappedRotation(93 * deg)!, .pi / 2, accuracy: 1e-9)
        XCTAssertEqual(CanvasTransform.snappedRotation(-178 * deg)!, -.pi, accuracy: 1e-9)
        XCTAssertNil(CanvasTransform.snappedRotation(12 * deg))
        XCTAssertNil(CanvasTransform.snappedRotation(45 * deg))
    }

    func testScaleClicksToTheFittedSize() {
        XCTAssertEqual(CanvasTransform.snappedScale(1.04), 1)
        XCTAssertEqual(CanvasTransform.snappedScale(0.95), 1)
        XCTAssertNil(CanvasTransform.snappedScale(1.3))
    }

    func testPositionClicksToTheMiddle() {
        XCTAssertEqual(CanvasTransform.snappedOffset(CGSize(width: 6, height: -8)), .zero)
        XCTAssertNil(CanvasTransform.snappedOffset(CGSize(width: 30, height: 0)))
    }

    func testAllThreeTogetherIsTheFittedCanvas() {
        var t = CanvasTransform(scale: 1.03, rotation: 2 * deg, offset: CGSize(width: 5, height: 5))
        t.scale = CanvasTransform.snappedScale(t.scale)!
        t.rotation = CanvasTransform.snappedRotation(t.rotation)!
        t.offset = CanvasTransform.snappedOffset(t.offset)!
        XCTAssertTrue(t.isFit)
    }
}
