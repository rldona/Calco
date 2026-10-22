import XCTest
import Metal
@testable import Calco

/// The Move tool: the whole drawing, or the shape under a tap, floated to move / scale / rotate.
@MainActor
final class MoveToolTests: XCTestCase {

    private func makeState() throws -> EditorState {
        guard let device = MTLCreateSystemDefaultDevice(),
              let state = EditorState(device: device, screenFormat: .bgra8Unorm) else {
            throw XCTSkip("Metal unavailable in this environment")
        }
        return state
    }

    private func alpha(_ state: EditorState, x: Int, y: Int) -> UInt8 {
        guard let l = state.currentLayer,
              let t = state.store.existingTexture(clip: state.clip.id, frame: state.currentFrame!.id, layer: l.id),
              let px = state.renderer.readbackBytes(t) else { return 0 }
        return px[(y * state.renderer.canvasSize.x + x) * 4 + 3]
    }

    private func dot(_ state: EditorState, at p: SIMD2<Float>) throws {
        let target = try XCTUnwrap(state.beginStroke())
        state.renderer.paint([.init(position: p, radius: 10, alpha: 1)], into: target, color: SIMD4(0, 0, 0, 1), tool: .brush)
        state.strokeEnded()
    }

    // MARK: Pixels

    func testContentBoundsHugThePaint() {
        var px = [UInt8](repeating: 0, count: 10 * 10 * 4)
        px[(2 * 10 + 3) * 4 + 3] = 255
        px[(7 * 10 + 6) * 4 + 3] = 40
        XCTAssertEqual(SelectionPixels.contentBounds(px, width: 10, height: 10), CGRect(x: 3, y: 2, width: 4, height: 6))
        XCTAssertNil(SelectionPixels.contentBounds([UInt8](repeating: 0, count: 400), width: 10, height: 10))
    }

    func testConnectedShapePicksOneShapeAndForgivesANearMiss() {
        // Two separate 3×3 blots on a 20×20 canvas.
        var px = [UInt8](repeating: 0, count: 20 * 20 * 4)
        for y in 2...4 { for x in 2...4 { px[(y * 20 + x) * 4 + 3] = 255 } }
        for y in 12...14 { for x in 12...14 { px[(y * 20 + x) * 4 + 3] = 255 } }

        let m = try! XCTUnwrap(SelectionPixels.connectedShape(px, width: 20, height: 20, at: (3, 3)))
        XCTAssertEqual(m[3 * 20 + 3], 255)
        XCTAssertEqual(m[13 * 20 + 13], 0, "the other blot stays")

        let near = try! XCTUnwrap(SelectionPixels.connectedShape(px, width: 20, height: 20, at: (7, 3), reach: 4))
        XCTAssertEqual(near[3 * 20 + 3], 255, "3 px off the edge still picks it")
        XCTAssertNil(SelectionPixels.connectedShape(px, width: 20, height: 20, at: (8, 8), reach: 2))
    }

    // MARK: Editor

    func testChoosingMoveLiftsTheWholeDrawingBoxedTight() throws {
        let state = try makeState()
        try dot(state, at: SIMD2(100, 100))
        try dot(state, at: SIMD2(300, 300))
        state.tool = .move
        let sel = try XCTUnwrap(state.selection)
        XCTAssertEqual(sel.bounds.minX, 88, accuracy: 3, "starts at the paint, not at the canvas edge")
        XCTAssertEqual(sel.bounds.maxX, 312, accuracy: 3)
        XCTAssertEqual(alpha(state, x: 100, y: 100), 0)
        XCTAssertEqual(alpha(state, x: 300, y: 300), 0, "both dots float")
    }

    func testTappingAShapeLiftsOnlyThatOne() throws {
        let state = try makeState()
        try dot(state, at: SIMD2(100, 100))
        try dot(state, at: SIMD2(300, 300))
        state.tool = .move
        state.liftForMove(at: CGPoint(x: 300, y: 300))
        XCTAssertGreaterThan(alpha(state, x: 100, y: 100), 200, "the other dot stays on the layer")
        XCTAssertEqual(alpha(state, x: 300, y: 300), 0)

        state.updateSelection { $0.offset = CGVector(dx: 40, dy: 0) }
        state.commitSelection()
        XCTAssertGreaterThan(alpha(state, x: 340, y: 300), 200, "moved 40 px right")
        state.undo()
        XCTAssertGreaterThan(alpha(state, x: 300, y: 300), 200, "one undo puts it back")
    }

    func testPickingUpAndPuttingDownUnmovedIsNoChange() throws {
        let state = try makeState()
        try dot(state, at: SIMD2(100, 100))
        state.tool = .move
        state.tool = .brush
        XCTAssertGreaterThan(alpha(state, x: 100, y: 100), 200)
        state.undo()
        XCTAssertEqual(alpha(state, x: 100, y: 100), 0, "the undo step was the stroke, not an empty move")
    }

    func testChangingFrameWithMovePicksUpTheNextDrawing() throws {
        let state = try makeState()
        try dot(state, at: SIMD2(100, 100))
        state.addFrame()
        try dot(state, at: SIMD2(200, 200))
        state.frameIndex = 0
        state.tool = .move
        state.updateSelection { $0.offset = CGVector(dx: 10, dy: 0) }
        state.frameIndex = 1
        XCTAssertEqual(state.selection?.key.frame, state.frames[1].id)
        state.frameIndex = 0
        state.tool = .brush
        XCTAssertGreaterThan(alpha(state, x: 110, y: 100), 200, "the first move was dropped in place")
    }

    func testALockedLayerOffersToUnlockAndLocksAgainAfter() throws {
        let state = try makeState()
        try dot(state, at: SIMD2(100, 100))
        state.toggleLayerLock(state.layerIndex)
        state.tool = .move
        XCTAssertNil(state.selection)
        XCTAssertEqual(state.moveBlockedLayer, state.currentLayer?.id)

        state.unlockAndMove()
        XCTAssertNotNil(state.selection)
        XCTAssertEqual(state.currentLayer?.locked, false)
        state.updateSelection { $0.offset = CGVector(dx: 30, dy: 0) }
        state.commitSelection()
        XCTAssertEqual(state.currentLayer?.locked, true, "locked again once it's put down")
        XCTAssertGreaterThan(alpha(state, x: 130, y: 100), 200)
    }

    // MARK: Snapping back

    func testRotationClicksUprightAndOnQuarterTurns() {
        let deg = CGFloat.pi / 180
        XCTAssertEqual(FloatingSelection.snappedRotation(3 * deg), 0)
        XCTAssertEqual(FloatingSelection.snappedRotation(-2 * deg), 0)
        XCTAssertEqual(FloatingSelection.snappedRotation(88 * deg)!, .pi / 2, accuracy: 1e-9)
        XCTAssertEqual(FloatingSelection.snappedRotation(362 * deg)!, 2 * .pi, accuracy: 1e-9, "upright after a full turn too")
        XCTAssertNil(FloatingSelection.snappedRotation(10 * deg))
    }

    func testPositionAndSizeClickBackToWhereTheyStarted() {
        XCTAssertEqual(FloatingSelection.snappedOffset(CGVector(dx: 3, dy: -4), tolerance: 6), .zero)
        XCTAssertNil(FloatingSelection.snappedOffset(CGVector(dx: 3, dy: -4), tolerance: 5))
        XCTAssertEqual(FloatingSelection.snappedScale(1.03), 1)
        XCTAssertNil(FloatingSelection.snappedScale(1.2))
    }

    func testAMoveSnappedBackIsNoChange() throws {
        let state = try makeState()
        try dot(state, at: SIMD2(100, 100))
        state.tool = .move
        state.updateSelection { $0.offset = CGVector(dx: 30, dy: 0) }
        state.updateSelection { $0.offset = FloatingSelection.snappedOffset(CGVector(dx: 2, dy: 1), tolerance: 6)! }
        state.tool = .brush
        state.undo()
        XCTAssertEqual(alpha(state, x: 100, y: 100), 0, "the only undo step left was the stroke")
    }

    func testAPencilStrokeScaledUpStaysSharp() throws {
        let state = try makeState()
        let target = try XCTUnwrap(state.beginStroke())
        state.paintStroke((0...40).map { .init(position: SIMD2(Float(100 + $0), 200), radius: 3, alpha: 1) }, into: target)
        state.strokeEnded()
        state.tool = .move
        state.updateSelection { $0.scale = 4 }
        state.commitSelection()
        // Across the line, 4× as thick: painted again, its edge is still about one pixel soft.
        let soft = (150...250).filter { (1...254).contains(alpha(state, x: 120, y: $0)) }.count
        let solid = (150...250).filter { alpha(state, x: 120, y: $0) == 255 }.count
        XCTAssertGreaterThan(solid, 18, "about 24 px thick")
        XCTAssertLessThanOrEqual(soft, 4, "a sharp edge, not a blur")
    }

    func testATapOnABlankSpotPutsDownWhatFloats() throws {
        let state = try makeState()
        try dot(state, at: SIMD2(100, 100))
        try dot(state, at: SIMD2(300, 300))
        state.tool = .move
        state.liftForMove(at: CGPoint(x: 300, y: 300))
        state.updateSelection { $0.offset = CGVector(dx: 40, dy: 0) }
        state.liftForMove(at: CGPoint(x: 500, y: 40), dropOnMiss: true)
        XCTAssertNil(state.selection, "nothing floats")
        XCTAssertGreaterThan(alpha(state, x: 340, y: 300), 200, "dropped where it was moved")
        state.liftForMove(at: CGPoint(x: 100, y: 100), dropOnMiss: true)
        XCTAssertNotNil(state.selection, "a tap on a stroke still picks it")
    }
}
