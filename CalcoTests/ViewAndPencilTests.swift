import XCTest
import Metal
@testable import Calco

/// Flipped view and Apple Pencil double tap / squeeze.
@MainActor
final class ViewAndPencilTests: XCTestCase {

    func testFlippedViewMirrorsLeftAndRightAndTouchesFollow() {
        let canvas = SIMD2(100, 100), view = CGSize(width: 400, height: 400)
        var t = CanvasTransform()
        let left = CGPoint(x: 10, y: 50).applying(t.canvasToView(canvas: canvas, viewSize: view))
        t.flipped = true
        let mirrored = CGPoint(x: 10, y: 50).applying(t.canvasToView(canvas: canvas, viewSize: view))
        XCTAssertEqual(mirrored.x, view.width - left.x, accuracy: 0.001, "the left edge shows on the right")
        XCTAssertEqual(mirrored.y, left.y, accuracy: 0.001)
        let back = mirrored.applying(t.viewToCanvas(canvas: canvas, viewSize: view))
        XCTAssertEqual(back.x, 10, accuracy: 0.001, "a touch there still paints the same pixel")
        XCTAssertTrue(t.isFit, "mirroring isn't zooming")
    }

    private func makeState() throws -> EditorState {
        guard let device = MTLCreateSystemDefaultDevice(),
              let state = EditorState(device: device, screenFormat: .bgra8Unorm) else {
            throw XCTSkip("Metal unavailable in this environment")
        }
        return state
    }

    func testFitKeepsTheViewFlipped() throws {
        let state = try makeState()
        state.canvasTransform.flipped = true
        state.canvasTransform.scale = 3
        state.fitCanvas()
        XCTAssertTrue(state.canvasTransform.isFit)
        XCTAssertTrue(state.canvasTransform.flipped)
    }

    func testPencilSwitchesToTheEraserAndBack() throws {
        let state = try makeState()
        state.tool = .lasso
        state.pencilSwitchEraser()
        XCTAssertEqual(state.tool, .eraser)
        state.pencilSwitchEraser()
        XCTAssertEqual(state.tool, .lasso, "back to what you had")

        state.tool = .fill
        state.pencilSwitchPrevious()
        XCTAssertEqual(state.tool, .lasso)
        state.pencilSwitchPrevious()
        XCTAssertEqual(state.tool, .fill)
    }

    func testPencilOnlyIsOffWithoutSavedSettings() throws {
        XCTAssertFalse(try makeState().pencilOnly)
    }
}
