import XCTest
import Metal
@testable import Calco

/// Undo/redo: pixels (strokes, clear), structure (frames, clips) and coalescing of continuous edits.
@MainActor
final class EditorStateHistoryTests: XCTestCase {

    private func makeState() throws -> EditorState {
        guard let device = MTLCreateSystemDefaultDevice(),
              let state = EditorState(device: device, screenFormat: .bgra8Unorm) else {
            throw XCTSkip("Metal unavailable in this environment")
        }
        return state
    }

    private func alpha(_ image: CGImage?, x: Int, y: Int) -> UInt8 {
        guard let image else { return 0 }
        let w = image.width, h = image.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return bytes[(y * w + x) * 4 + 3]
    }

    /// One dot on the current layer, the way CanvasView does it.
    private func stroke(_ state: EditorState, x: Float, y: Float) throws {
        let target = try XCTUnwrap(state.beginStroke())
        state.renderer.paint([.init(position: SIMD2<Float>(x, y), radius: 10, alpha: 1)],
                             into: target, color: SIMD4<Float>(0, 0, 0, 1), tool: .brush)
        state.strokeEnded()
    }

    private func lineImage(_ state: EditorState, frame: String = "000") -> CGImage? {
        state.store.image(clip: state.clip.id, frame: frame, layer: "line")
    }

    func testStrokesUndoAndRedo() throws {
        let state = try makeState()
        XCTAssertFalse(state.canUndo)

        try stroke(state, x: 100, y: 200)
        try stroke(state, x: 300, y: 300)
        XCTAssertGreaterThan(alpha(lineImage(state), x: 300, y: 300), 200)

        state.undo()
        XCTAssertEqual(alpha(lineImage(state), x: 300, y: 300), 0, "second stroke is gone")
        XCTAssertGreaterThan(alpha(lineImage(state), x: 100, y: 200), 200, "first stroke stays")

        state.undo()
        XCTAssertNil(lineImage(state), "back to a never-drawn layer")
        XCTAssertFalse(state.canUndo)

        state.redo()
        state.redo()
        XCTAssertGreaterThan(alpha(lineImage(state), x: 100, y: 200), 200)
        XCTAssertGreaterThan(alpha(lineImage(state), x: 300, y: 300), 200)
        XCTAssertFalse(state.canRedo)
    }

    func testCancelledStrokeLeavesNoTraceAndKeepsRedo() throws {
        let state = try makeState()
        try stroke(state, x: 100, y: 200)
        state.undo()
        XCTAssertTrue(state.canRedo)

        // A finger starts painting, then turns out to be a three-finger tap.
        let target = try XCTUnwrap(state.beginStroke())
        state.renderer.paint([.init(position: SIMD2<Float>(300, 300), radius: 10, alpha: 1)],
                             into: target, color: SIMD4<Float>(0, 0, 0, 1), tool: .brush)
        state.cancelStroke()
        XCTAssertEqual(alpha(lineImage(state), x: 300, y: 300), 0)
        XCTAssertTrue(state.canRedo, "a cancelled stroke doesn't clear redo")
        XCTAssertFalse(state.canUndo)

        state.redo()
        XCTAssertGreaterThan(alpha(lineImage(state), x: 100, y: 200), 200)
    }

    func testUndoMidStrokeDropsTheStroke() throws {
        let state = try makeState()
        try stroke(state, x: 100, y: 200)
        let target = try XCTUnwrap(state.beginStroke())
        state.renderer.paint([.init(position: SIMD2<Float>(300, 300), radius: 10, alpha: 1)],
                             into: target, color: SIMD4<Float>(0, 0, 0, 1), tool: .brush)
        state.undo()   // two-finger tap while the first finger was already painting
        XCTAssertNil(lineImage(state), "both the half stroke and the previous one are gone")
        state.strokeEnded()
        XCTAssertFalse(state.canUndo, "the cancelled stroke never enters the history")
    }

    func testClearLayerIsUndoable() throws {
        let state = try makeState()
        try stroke(state, x: 100, y: 200)
        state.clearCurrentLayer()
        XCTAssertEqual(alpha(lineImage(state), x: 100, y: 200), 0)
        state.undo()
        XCTAssertGreaterThan(alpha(lineImage(state), x: 100, y: 200), 200)
    }

    func testDeleteFrameRestoresItsPixelsAndSelection() throws {
        let state = try makeState()
        try stroke(state, x: 100, y: 200)      // on 000
        state.addFrame()                        // 001, selected
        state.frameIndex = 0
        state.deleteFrame()
        XCTAssertEqual(state.frames.map(\.id), ["001"])
        XCTAssertNil(lineImage(state, frame: "000"))

        state.undo()
        XCTAssertEqual(state.frames.map(\.id), ["000", "001"])
        XCTAssertEqual(state.frameIndex, 0)
        XCTAssertGreaterThan(alpha(lineImage(state, frame: "000"), x: 100, y: 200), 200)

        state.redo()
        XCTAssertEqual(state.frames.map(\.id), ["001"])
        XCTAssertNil(lineImage(state, frame: "000"))
    }

    func testDuplicateUndoDropsTheCopy() throws {
        let state = try makeState()
        try stroke(state, x: 100, y: 200)
        state.duplicateFrame()
        XCTAssertEqual(state.frames.map(\.id), ["000", "001"])
        XCTAssertGreaterThan(alpha(lineImage(state, frame: "001"), x: 100, y: 200), 200)

        state.undo()
        XCTAssertEqual(state.frames.map(\.id), ["000"])
        XCTAssertNil(lineImage(state, frame: "001"))
        state.redo()
        XCTAssertGreaterThan(alpha(lineImage(state, frame: "001"), x: 100, y: 200), 200)
    }

    func testContinuousEditsCoalesce() throws {
        let state = try makeState()
        state.addFrame(); state.addFrame()      // 000 001 002, 3 undo steps

        state.setHold(2); state.setHold(3); state.setHold(4)
        state.undo()
        XCTAssertEqual(state.currentFrame?.hold, 1, "stepper run is one step")

        // A drag: many moves of the same frame, then the drop.
        state.moveFrame(id: "000", to: 1)
        state.moveFrame(id: "000", to: 2)
        state.endCoalescing()
        state.moveFrame(id: "000", to: 0)        // a second drag
        state.undo()
        XCTAssertEqual(state.frames.map(\.id), ["001", "002", "000"], "second drag undone on its own")
        state.undo()
        XCTAssertEqual(state.frames.map(\.id), ["000", "001", "002"], "whole first drag undone in one step")
    }

    func testNewEditClearsRedoAndHistoryIsCapped() throws {
        let state = try makeState()
        state.addFrame()
        state.undo()
        XCTAssertTrue(state.canRedo)
        state.toggleLoop()
        XCTAssertFalse(state.canRedo)

        for _ in 0..<(EditorState.historyLimit + 10) { state.toggleLoop() }
        var steps = 0
        while state.canUndo { state.undo(); steps += 1 }
        XCTAssertEqual(steps, EditorState.historyLimit)
    }

    func testAddClipIsOneStepAndNewProjectForgetsHistory() throws {
        let state = try makeState()
        state.addClip(name: "Run")
        XCTAssertEqual(state.project.clips.count, 2)
        state.undo()
        XCTAssertEqual(state.project.clips.map(\.id), ["idle"])
        XCTAssertEqual(state.clipIndex, 0)
        XCTAssertFalse(state.canUndo)

        state.addFrame()
        state.newProject()
        XCTAssertFalse(state.canUndo)
        XCTAssertFalse(state.canRedo)
    }
}
