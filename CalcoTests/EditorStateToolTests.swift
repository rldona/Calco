import XCTest
import Metal
import SwiftUI
@testable import Calco

@MainActor
final class EditorStateToolTests: XCTestCase {

    private func makeState() throws -> EditorState {
        guard let device = MTLCreateSystemDefaultDevice(),
              let state = EditorState(device: device, screenFormat: .bgra8Unorm) else {
            throw XCTSkip("Metal unavailable in this environment")
        }
        return state
    }

    func testEachToolKeepsItsOwnSize() throws {
        let state = try makeState()
        state.toolSize = 12
        state.tool = .eraser
        XCTAssertEqual(state.toolSize, 18, "eraser default")
        state.toolSize = 40
        state.tool = .brush
        XCTAssertEqual(state.toolSize, 12)
        XCTAssertEqual(state.eraserSize, 40)
    }

    func testSizeIsRoundedAndClamped() throws {
        let state = try makeState()
        state.toolSize = 7.6
        XCTAssertEqual(state.toolSize, 8)
        state.toolSize = 500
        XCTAssertEqual(state.toolSize, EditorState.sizeRange.upperBound)
        state.toolSize = -3
        XCTAssertEqual(state.toolSize, EditorState.sizeRange.lowerBound)
    }

    func testSizeStepsGrowWithTheBrush() throws {
        let state = try makeState()
        state.toolSize = 5
        state.stepToolSize(1)
        XCTAssertEqual(state.toolSize, 6)
        state.toolSize = 20
        state.stepToolSize(1)
        XCTAssertEqual(state.toolSize, 22)
        state.toolSize = 40
        state.stepToolSize(-1)
        XCTAssertEqual(state.toolSize, 36)
        state.toolSize = 1
        state.stepToolSize(-1)
        XCTAssertEqual(state.toolSize, 1)
    }

    func testPickingAColourIsOpaqueAndSelectsTheBrush() throws {
        let state = try makeState()
        state.tool = .eraser
        state.setColor(SIMD4<Float>(1.4, 0.5, -0.2, 0.3))
        XCTAssertEqual(state.color, SIMD4<Float>(1, 0.5, 0, 1))
        XCTAssertEqual(state.tool, .brush)
    }

    func testSizesAndColourAreRememberedAcrossLaunches() throws {
        let suite = "EditorStateToolTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("Metal unavailable") }

        let first = try XCTUnwrap(EditorState(device: device, screenFormat: .bgra8Unorm, defaults: defaults))
        XCTAssertEqual(first.brushSize, 6, "fresh install keeps the defaults")
        first.toolSize = 14
        first.tool = .eraser
        first.toolSize = 30
        first.setColor(SIMD4<Float>(0.2, 0.4, 0.6, 1))

        let second = try XCTUnwrap(EditorState(device: device, screenFormat: .bgra8Unorm, defaults: defaults))
        XCTAssertEqual(second.brushSize, 14)
        XCTAssertEqual(second.eraserSize, 30)
        XCTAssertEqual(second.color, SIMD4<Float>(0.2, 0.4, 0.6, 1))
    }

    func testGarbageInDefaultsFallsBackToDefaults() throws {
        let suite = "EditorStateToolTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("Metal unavailable") }
        defaults.set(Float(900), forKey: "tool.brushSize")
        defaults.set("big", forKey: "tool.eraserSize")
        defaults.set([Float(2), 0, 0], forKey: "tool.color")

        let state = try XCTUnwrap(EditorState(device: device, screenFormat: .bgra8Unorm, defaults: defaults))
        XCTAssertEqual(state.brushSize, 6)
        XCTAssertEqual(state.eraserSize, 18)
        XCTAssertEqual(state.color, SIMD4<Float>(0, 0, 0, 1))
    }

    func testHexAndSwiftUIColourConversion() {
        XCTAssertEqual(SIMD4<Float>(hex: 0xFF8000), SIMD4<Float>(1, 128.0 / 255, 0, 1))
        let c = SIMD4<Float>(0.2, 0.4, 0.6, 1)
        let back = SIMD4<Float>(Color(rgba: c))
        XCTAssertEqual(back.x, 0.2, accuracy: 0.001)
        XCTAssertEqual(back.y, 0.4, accuracy: 0.001)
        XCTAssertEqual(back.z, 0.6, accuracy: 0.001)
        XCTAssertEqual(back.w, 1)
    }
}
