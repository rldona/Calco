import XCTest
import Metal
@testable import Calco

/// Picking a range of frames in the timeline: copy, cut, paste, reverse, duplicate, delete.
@MainActor
final class FrameRangeTests: XCTestCase {

    private func makeState() throws -> EditorState {
        guard let device = MTLCreateSystemDefaultDevice(),
              let state = EditorState(device: device, screenFormat: .bgra8Unorm) else {
            throw XCTSkip("Metal unavailable in this environment")
        }
        state.syncLayers = false
        return state
    }

    /// Frame `i` of the current layer gets a dot at x = 20 + 20·mark, so drawings can be told apart.
    private func mark(_ state: EditorState, _ m: Int) throws {
        let target = try XCTUnwrap(state.beginStroke())
        state.renderer.paint([.init(position: SIMD2(Float(20 + 20 * m), 50), radius: 4, alpha: 1)], into: target,
                             color: SIMD4(0, 0, 0, 1), tool: .brush)
        state.strokeEnded()
    }

    /// Which mark the current layer shows at frame `i` (nil: nothing).
    private func shown(_ state: EditorState, _ i: Int, layer: String? = nil) -> Int? {
        let l = layer ?? state.currentLayer!.id
        guard let key = state.drawingKey(layer: l, at: i),
              let t = state.store.existingTexture(clip: key.clip, frame: key.frame, layer: key.layer),
              let px = state.renderer.readbackBytes(t) else { return nil }
        let w = state.renderer.canvasSize.x
        return (0..<10).first { px[(50 * w + 20 + 20 * $0) * 4 + 3] > 200 }
    }

    /// Five frames with marks 0…4 on the current layer.
    private func five(_ state: EditorState) throws {
        try mark(state, 0)
        for m in 1...4 { state.addDrawing(); try mark(state, m) }
    }

    func testReverseOneLayer() throws {
        let state = try makeState()
        try five(state)
        state.beginFrameRange(at: 1); state.extendFrameRange(to: 3)
        state.reverseFrames()
        XCTAssertEqual((0..<5).map { shown(state, $0) }, [0, 3, 2, 1, 4])
        state.undo()
        XCTAssertEqual((0..<5).map { shown(state, $0) }, [0, 1, 2, 3, 4])
    }

    func testCopyAndPasteAfterThePlayhead() throws {
        let state = try makeState()
        try five(state)
        state.beginFrameRange(at: 0); state.extendFrameRange(to: 1)
        state.copyFrames()
        state.frameIndex = 4
        state.pasteFrames()
        XCTAssertEqual(state.frames.count, 7)
        XCTAssertEqual((0..<7).map { shown(state, $0) }, [0, 1, 2, 3, 4, 0, 1])
        XCTAssertEqual(state.frameIndex, 5)
        state.undo()
        XCTAssertEqual(state.frames.count, 5)
    }

    func testDuplicateKeepsTheRangeOnTheCopy() throws {
        let state = try makeState()
        try five(state)
        state.beginFrameRange(at: 1); state.extendFrameRange(to: 2)
        state.duplicateFrames()
        XCTAssertEqual((0..<7).map { shown(state, $0) }, [0, 1, 2, 1, 2, 3, 4])
        XCTAssertEqual(state.frameRange, 3...4)
    }

    func testDeleteEmptiesOneLayerOrRemovesWholeFrames() throws {
        let state = try makeState()
        try five(state)
        state.beginFrameRange(at: 1); state.extendFrameRange(to: 2)
        state.deleteFrames()
        XCTAssertEqual(state.frames.count, 5, "with Layer the frames stay")
        XCTAssertEqual((0..<5).map { shown(state, $0) }, [0, nil, nil, 3, 4])
        state.undo()
        state.syncLayers = true
        state.beginFrameRange(at: 1); state.extendFrameRange(to: 2)
        state.cutFrames()
        XCTAssertEqual((0..<3).map { shown(state, $0) }, [0, 3, 4])
        state.frameIndex = 2
        state.pasteFrames()
        XCTAssertEqual((0..<5).map { shown(state, $0) }, [0, 3, 4, 1, 2], "cut and pasted at the end")
    }

    func testAHoldAfterTheRangeKeepsItsDrawing() throws {
        let state = try makeState()
        try five(state)
        state.frameIndex = 4
        state.addDrawing()                                   // frame 5, held? make it hold frame 4
        state.holdCurrentCell()
        XCTAssertEqual(shown(state, 5), 4)
        state.beginFrameRange(at: 3); state.extendFrameRange(to: 4)
        state.reverseFrames()
        XCTAssertEqual((3...5).map { shown(state, $0) }, [4, 3, 4], "the frame after still shows what it did")
    }

    func testSomeLayersOfTheRange() throws {
        let state = try makeState()
        try five(state)                                      // on the top layer
        let top = state.currentLayer!.id
        state.layerIndex = 0                                 // the bottom layer: one drawing held
        let bottom = state.currentLayer!.id
        state.frameIndex = 0
        try mark(state, 9)
        state.layerIndex = state.layers.firstIndex { $0.id == top }!
        state.beginFrameRange(at: 1); state.extendFrameRange(to: 3)
        XCTAssertEqual(state.rangeLayerIDs, [top])
        state.toggleRangeLayer(bottom)
        XCTAssertEqual(state.rangeLayerIDs, [top, bottom])
        state.toggleRangeLayer(top); state.toggleRangeLayer(bottom)
        XCTAssertEqual(state.rangeLayerIDs, [bottom], "at least one stays in")
        state.toggleRangeLayer(top)
        if state.layers.count == 2 {
            // Two layers of two is whole frames: reversing swaps the frames themselves.
            state.reverseFrames()
            XCTAssertEqual((0..<5).map { shown(state, $0, layer: top) }, [0, 3, 2, 1, 4])
            XCTAssertEqual((0..<5).map { shown(state, $0, layer: bottom) }, [9, 9, 9, 9, 9])
        }
        state.undo()
        state.beginFrameRange(at: 1); state.extendFrameRange(to: 2)
        state.toggleRangeLayer(bottom)
        state.copyFrames()
        XCTAssertEqual(state.frameClipboard?.layers.count, 2)
        state.frameIndex = 4
        state.pasteFrames()
        XCTAssertEqual(state.frames.count, 7)
        XCTAssertEqual((5...6).map { shown(state, $0, layer: top) }, [1, 2], "each layer back into itself")
        XCTAssertEqual((5...6).map { shown(state, $0, layer: bottom) }, [9, 9])
    }

    func testDrawingOnAFrameAfterTheEndFillsTheGap() throws {
        let state = try makeState()
        try five(state)
        let line = state.currentLayer!.id
        state.addDrawing(at: 8, layer: line)
        XCTAssertEqual(state.frames.count, 9)
        XCTAssertEqual(state.frameIndex, 8)
        XCTAssertEqual((5...7).map { shown(state, $0) }, [4, 4, 4], "the gap holds the last drawing")
        XCTAssertNil(shown(state, 8), "a blank drawing to draw on")
        XCTAssertFalse(state.clip.isHeld(layer: line, at: 8))
        state.undo()
        XCTAssertEqual(state.frames.count, 5)
    }
}
