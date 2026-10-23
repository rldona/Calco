import XCTest
import Metal
@testable import Calco

/// Copy / cut / paste / select all with the lasso.
@MainActor
final class ClipboardTests: XCTestCase {

    private func makeState() throws -> EditorState {
        guard let device = MTLCreateSystemDefaultDevice(),
              let state = EditorState(device: device, screenFormat: .bgra8Unorm) else {
            throw XCTSkip("Metal unavailable in this environment")
        }
        return state
    }

    private func dot(_ state: EditorState, at p: SIMD2<Float>) throws {
        let target = try XCTUnwrap(state.beginStroke())
        state.renderer.paint([.init(position: p, radius: 4, alpha: 1)], into: target, color: SIMD4(0, 0, 0, 1), tool: .brush)
        state.strokeEnded()
    }

    private func alpha(_ state: EditorState, frame: Int, _ x: Int, _ y: Int) throws -> UInt8 {
        guard let key = state.drawingKey(layer: try XCTUnwrap(state.currentLayer).id, at: frame),
              let t = state.store.existingTexture(clip: key.clip, frame: key.frame, layer: key.layer),
              let b = state.renderer.readbackBytes(t) else { return 0 }
        return b[(y * state.renderer.canvasSize.x + x) * 4 + 3]
    }

    private let box = [CGPoint(x: 10, y: 10), CGPoint(x: 30, y: 10), CGPoint(x: 30, y: 30), CGPoint(x: 10, y: 30)]

    func testCopyThenPasteOnAnotherFrameLandsInTheSamePlace() throws {
        let state = try makeState()
        try dot(state, at: SIMD2(20, 20))
        try dot(state, at: SIMD2(60, 60))                  // outside the lasso
        state.liftSelection(box)
        state.copySelection()
        state.cancelSelection()
        XCTAssertGreaterThan(try alpha(state, frame: 0, 20, 20), 200, "copy leaves the drawing alone")

        state.addDrawing()
        state.paste()
        XCTAssertNotNil(state.selection, "pasted as a floating selection to move")
        state.commitSelection()
        XCTAssertGreaterThan(try alpha(state, frame: 1, 20, 20), 200)
        XCTAssertEqual(try alpha(state, frame: 1, 60, 60), 0, "only what was inside the lasso")

        state.undo()
        XCTAssertEqual(try alpha(state, frame: 1, 20, 20), 0, "paste undoes in one step")
    }

    func testCutTakesItAwayAndDeleteThrowsItAway() throws {
        let state = try makeState()
        try dot(state, at: SIMD2(20, 20))
        try dot(state, at: SIMD2(60, 60))
        state.liftSelection(box)
        state.cutSelection()
        XCTAssertNil(state.selection)
        XCTAssertEqual(try alpha(state, frame: 0, 20, 20), 0)
        XCTAssertNotNil(state.clipboard)

        state.liftSelection([CGPoint(x: 50, y: 50), CGPoint(x: 70, y: 50), CGPoint(x: 70, y: 70), CGPoint(x: 50, y: 70)])
        state.deleteSelection()
        XCTAssertEqual(try alpha(state, frame: 0, 60, 60), 0)
        state.undo()
        XCTAssertGreaterThan(try alpha(state, frame: 0, 60, 60), 200, "delete undoes")
    }

    func testSelectAllMarksTheWholeCanvasAndCopyWithoutASelectionTakesItAll() throws {
        let state = try makeState()
        try dot(state, at: SIMD2(20, 20))
        try dot(state, at: SIMD2(60, 60))
        state.copySelection()                               // nothing selected: the whole drawing
        XCTAssertEqual(state.clipboard?.outline.count, 4)

        state.selectAll()
        XCTAssertEqual(state.tool, .lasso)
        XCTAssertNil(state.selection, "marked, not lifted")
        XCTAssertEqual(state.selectionMask?.bounds, CGRect(x: 0, y: 0, width: 512, height: 512))
        XCTAssertGreaterThan(try alpha(state, frame: 0, 60, 60), 200, "the drawing stays where it is")
        state.transformSelection()
        XCTAssertEqual(try alpha(state, frame: 0, 60, 60), 0, "lifted off the layer while it floats")
        state.cancelSelection()
        XCTAssertGreaterThan(try alpha(state, frame: 0, 60, 60), 200)
    }

    func testPasteNeedsSomethingCopied() throws {
        let state = try makeState()
        state.paste()
        XCTAssertNil(state.selection)
    }
}
