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
}
