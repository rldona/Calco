import XCTest
import Metal
@testable import Calco

/// The bar's add / duplicate / delete: the current layer's drawing, or whole frames with Sync layers.
@MainActor
final class LayerDrawingTests: XCTestCase {

    private func makeState() throws -> EditorState {
        guard let device = MTLCreateSystemDefaultDevice(),
              let state = EditorState(device: device, screenFormat: .bgra8Unorm) else {
            throw XCTSkip("Metal unavailable in this environment")
        }
        return state
    }

    private func dot(_ state: EditorState) throws {
        let target = try XCTUnwrap(state.beginStroke())
        state.renderer.paint([.init(position: SIMD2(20, 20), radius: 6, alpha: 1)], into: target,
                             color: SIMD4(0, 0, 0, 1), tool: .brush)
        state.strokeEnded()
    }

    private func drawn(_ state: EditorState, frame: Int, layer: String) -> Bool {
        state.store.existingTexture(clip: state.clip.id, frame: state.frames[frame].id, layer: layer) != nil
    }

    private let color = 0, line = 1

    /// Frame 0: colour and line drawn. Frame 1: a new line drawing, colour holding frame 0's.
    private func twoFrames(_ state: EditorState) throws {
        state.layerIndex = color; try dot(state)
        state.layerIndex = line; try dot(state)
        state.addDrawing()
        try dot(state)
    }

    func testDeletingALineDrawingLeavesColourAndDropsTheEmptyFrame() throws {
        let state = try makeState()
        try twoFrames(state)
        XCTAssertEqual(state.frames.count, 2)

        state.deleteDrawing()
        // Frame 1 had nothing of its own left, so it went away: the clip is one frame shorter.
        XCTAssertEqual(state.frames.count, 1)
        XCTAssertEqual(state.frames[0].hold, 1)
        XCTAssertTrue(drawn(state, frame: 0, layer: "color"))
        XCTAssertTrue(drawn(state, frame: 0, layer: "line"))

        state.undo()
        XCTAssertEqual(state.frames.count, 2)
        XCTAssertTrue(drawn(state, frame: 1, layer: "line"))
    }

    func testDeletingKeepsTheFrameWhenAnotherLayerHasADrawingThere() throws {
        let state = try makeState()
        try twoFrames(state)
        state.layerIndex = color
        state.releaseCurrentCell(copying: true)            // colour gets its own drawing at frame 1
        state.layerIndex = line

        state.deleteDrawing()
        XCTAssertEqual(state.frames.count, 2)
        XCTAssertTrue(state.clip.isHeld(layer: "line", at: 1), "line shows its previous drawing")
        XCTAssertFalse(state.clip.isHeld(layer: "color", at: 1))
        XCTAssertTrue(drawn(state, frame: 1, layer: "color"))
    }

    func testDeletingOnTheFirstFrameBlanksOnlyThatLayer() throws {
        let state = try makeState()
        try twoFrames(state)
        state.frameIndex = 0

        state.deleteDrawing()
        XCTAssertEqual(state.frames.count, 2)
        XCTAssertFalse(drawn(state, frame: 0, layer: "line"))
        XCTAssertTrue(drawn(state, frame: 0, layer: "color"))
    }

    func testDeletingOnAHeldCellRemovesTheDrawingBeingHeld() throws {
        let state = try makeState()
        try twoFrames(state)
        state.layerIndex = color
        state.frameIndex = 1                               // colour holds frame 0's drawing here

        state.deleteDrawing()
        XCTAssertFalse(drawn(state, frame: 0, layer: "color"))
        XCTAssertTrue(drawn(state, frame: 0, layer: "line"))
        XCTAssertEqual(state.frames.count, 2)
    }

    func testDuplicatingCopiesOnlyTheCurrentLayer() throws {
        let state = try makeState()
        state.layerIndex = color; try dot(state)
        state.layerIndex = line; try dot(state)

        state.duplicateDrawing()
        XCTAssertEqual(state.frameIndex, 1)
        XCTAssertTrue(drawn(state, frame: 1, layer: "line"))
        XCTAssertTrue(state.clip.isHeld(layer: "color", at: 1))
    }

    func testSyncLayersActsOnWholeFrames() throws {
        let state = try makeState()
        try twoFrames(state)
        state.syncLayers = true

        state.addDrawing()
        XCTAssertEqual(state.frames.count, 3)
        XCTAssertEqual(state.frames[2].held, [], "a blank drawing on every layer")

        state.deleteDrawing()
        XCTAssertEqual(state.frames.count, 2)
        state.duplicateDrawing()
        XCTAssertEqual(state.frames.count, 3)
        XCTAssertTrue(drawn(state, frame: 2, layer: "line"))
        XCTAssertTrue(drawn(state, frame: 1, layer: "line"))
    }

    func testNewLayerWithTheSameTimingGoesBelowAndHoldsWhereTheSourceHolds() throws {
        let state = try makeState()
        try twoFrames(state)
        state.addDrawing()
        state.layerIndex = line
        state.frameIndex = 2
        state.holdCurrentCell()                            // line: drawings at 0, 1; frame 2 holds 1

        state.addLayerMatchingTiming()
        XCTAssertEqual(state.layers.map(\.name), ["Color", "Line color", "Line"])
        XCTAssertEqual(state.currentLayer?.name, "Line color")
        let id = try XCTUnwrap(state.currentLayer?.id)
        XCTAssertEqual((0..<3).map { state.clip.isHeld(layer: id, at: $0) }, [false, false, true])
        XCTAssertFalse(drawn(state, frame: 0, layer: id), "blank, ready to colour")
    }

    func testOnionSkinCountsDrawingsNotFrames() throws {
        let state = try makeState()
        state.onion = OnionSkin(enabled: true, before: 1, after: 0)
        state.layerIndex = color; try dot(state)
        state.layerIndex = line; try dot(state)
        state.addDrawing()                                 // blank line drawing, colour holds
        state.addDrawing()                                 // another blank one
        let lineAt0 = try XCTUnwrap(state.store.existingTexture(clip: state.clip.id, frame: state.frames[0].id, layer: "line"))
        let colorAt0 = try XCTUnwrap(state.store.existingTexture(clip: state.clip.id, frame: state.frames[0].id, layer: "color"))

        let ghosts = state.visibleLayers().filter { $0.tintAmount > 0 }.map { $0.texture as AnyObject }
        XCTAssertTrue(ghosts.contains { $0 === lineAt0 }, "two blank frames back, the last real line drawing still ghosts")
        XCTAssertFalse(ghosts.contains { $0 === colorAt0 }, "the held colour is on screen, not ghosted")
    }

    func testLengtheningADrawingPushesTheNextOneInsteadOfEatingIt() throws {
        let state = try makeState()
        try twoFrames(state)                               // line: drawing at 0, drawing at 1

        state.setDrawingDuration(layer: "line", start: 0, ticks: 3)
        XCTAssertEqual(state.frames.map(\.hold), [3, 1])
        XCTAssertTrue(drawn(state, frame: 1, layer: "line"), "the next drawing is still there, later")

        state.setDrawingDuration(layer: "line", start: 0, ticks: 1)
        XCTAssertEqual(state.frames.map(\.hold), [1, 1])
        state.endCoalescing()
        state.undo()
        XCTAssertEqual(state.frames.map(\.hold), [1, 1], "the whole drag undoes in one step")
    }

    func testShorteningDropsFramesOnlyHeldButNeverAnotherLayersDrawing() throws {
        let state = try makeState()
        try twoFrames(state)
        state.addDrawing()
        state.holdCurrentCell()                            // line: 0, 1, 2 holds 1; colour holds 0 throughout
        XCTAssertEqual(state.frames.count, 3)

        state.setDrawingDuration(layer: "line", start: 1, ticks: 1)
        XCTAssertEqual(state.frames.count, 2, "frame 2 drew nothing on any layer, so it went")

        // Colour's drawing spans both frames, but line draws its own at frame 1: that frame stays.
        state.setDrawingDuration(layer: "color", start: 0, ticks: 1)
        XCTAssertEqual(state.frames.count, 2)
        XCTAssertTrue(drawn(state, frame: 1, layer: "line"))
    }

    func testDuplicatingALayerCopiesItsDrawings() throws {
        let state = try makeState()
        try twoFrames(state)
        state.duplicateCurrentLayer()
        XCTAssertEqual(state.layers.map(\.name), ["Color", "Line", "Line copy"])
        let id = try XCTUnwrap(state.currentLayer?.id)
        XCTAssertTrue(drawn(state, frame: 0, layer: id))
        XCTAssertTrue(drawn(state, frame: 1, layer: id))
        state.undo()
        XCTAssertEqual(state.layers.count, 2)
    }
}

/// Inbetween halfway and duplicate split.
@MainActor
final class SplitDrawingTests: XCTestCase {

    private func makeState() throws -> EditorState {
        guard let device = MTLCreateSystemDefaultDevice(),
              let state = EditorState(device: device, screenFormat: .bgra8Unorm) else {
            throw XCTSkip("Metal unavailable in this environment")
        }
        return state
    }

    private func dot(_ state: EditorState) throws {
        let target = try XCTUnwrap(state.beginStroke())
        state.renderer.paint([.init(position: SIMD2(20, 20), radius: 4, alpha: 1)], into: target,
                             color: SIMD4(0, 0, 0, 1), tool: .brush)
        state.strokeEnded()
    }

    private func texture(_ state: EditorState, layer: String, at i: Int) -> MTLTexture? {
        state.drawingKey(layer: layer, at: i).flatMap { state.store.existingTexture(clip: $0.clip, frame: $0.frame, layer: $0.layer) }
    }

    func testBlankInbetweenSplitsAHeldFrameInTwo() throws {
        let state = try makeState()
        state.layerIndex = 0; try dot(state)
        state.layerIndex = 1; try dot(state)
        state.setHold(4)
        state.splitCurrentDrawing(copying: false)
        XCTAssertEqual(state.frames.map(\.hold), [2, 2], "same total length")
        XCTAssertEqual(state.frameIndex, 1, "on the new inbetween")
        XCTAssertNil(texture(state, layer: "line", at: 1), "blank, ready to draw")
        XCTAssertTrue(texture(state, layer: "color", at: 1) === texture(state, layer: "color", at: 0), "colour unchanged")
    }

    func testDuplicateSplitOverHeldFramesCopiesAndOddLengthsFavourTheFirstHalf() throws {
        let state = try makeState()
        state.layerIndex = 1; try dot(state)
        state.setDrawingDuration(layer: "line", start: 0, ticks: 3)
        state.addDrawing()                                     // a second drawing after it
        state.frameIndex = 0
        state.splitCurrentDrawing(copying: true)
        XCTAssertEqual(state.frames.map(\.hold), [2, 1, 1])
        let a = try XCTUnwrap(texture(state, layer: "line", at: 0)), b = try XCTUnwrap(texture(state, layer: "line", at: 1))
        XCTAssertFalse(a === b, "a copy, not the same drawing")
    }

    func testAOneTickDrawingCantBeSplit() throws {
        let state = try makeState()
        XCTAssertFalse(state.canSplitCurrentDrawing)
        state.splitCurrentDrawing(copying: false)
        XCTAssertEqual(state.frames.count, 1)
    }
}
