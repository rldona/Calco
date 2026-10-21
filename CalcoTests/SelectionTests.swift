import XCTest
import Metal
@testable import Calco

final class GapClosingTests: XCTestCase {

    /// 20×20 transparent canvas, opaque square outline (4,4)–(15,15) with a 2 px gap in the top edge.
    private func leakyBox() -> [UInt8] {
        let w = 20
        var px = [UInt8](repeating: 0, count: w * w * 4)
        for y in 4...15 { for x in 4...15 where x == 4 || x == 15 || y == 4 || y == 15 {
            if y == 4 && (9...10).contains(x) { continue }      // the gap
            px[(y * w + x) * 4 + 3] = 255
        } }
        return px
    }

    private func count(_ m: [Bool]) -> Int { m.filter { $0 }.count }

    func testWithoutClosingTheFillLeaks() {
        let m = FloodFill.region(in: leakyBox(), width: 20, height: 20, seed: (10, 10), tolerance: 10)
        XCTAssertTrue(m[0], "escapes through the gap to the corner")
    }

    func testClosingGapsKeepsItInsideAndStillReachesTheLine() {
        let m = FloodFill.region(in: leakyBox(), width: 20, height: 20, seed: (10, 10), tolerance: 10, closingGaps: 1)
        XCTAssertFalse(m[0], "doesn't reach the outside")
        XCTAssertFalse(m[2 * 20 + 10], "nor the area just above the gap")
        XCTAssertTrue(m[5 * 20 + 5], "but fills right up to the inner corner")
        XCTAssertTrue(m[14 * 20 + 14])
        XCTAssertFalse(m[15 * 20 + 15], "the line itself isn't part of the region")
    }

    func testSeedInsideAThickenedLineFallsBackToAPlainFill() {
        // Seed right next to the wall: within the closing radius, so plain fill.
        let m = FloodFill.region(in: leakyBox(), width: 20, height: 20, seed: (5, 5), tolerance: 10, closingGaps: 2)
        XCTAssertTrue(m[5 * 20 + 5])
        XCTAssertGreaterThan(count(m), 1)
    }

    func testGapRadiusScalesWithTheCanvas() {
        XCTAssertEqual(EditorState.FillGaps.off.radius(forCanvasSide: 512), 0)
        XCTAssertEqual(EditorState.FillGaps.small.radius(forCanvasSide: 512), 2)
        XCTAssertEqual(EditorState.FillGaps.large.radius(forCanvasSide: 512), 8)
        XCTAssertEqual(EditorState.FillGaps.small.radius(forCanvasSide: 64), 1, "never zero when on")
    }
}

final class SelectionPixelsTests: XCTestCase {

    func testRasterizeFillsTheInsideOnly() {
        let square = [CGPoint(x: 2, y: 2), CGPoint(x: 8, y: 2), CGPoint(x: 8, y: 8), CGPoint(x: 2, y: 8)]
        let m = SelectionPixels.rasterize(square, width: 10, height: 10)
        XCTAssertEqual(m[5 * 10 + 5], 255)
        XCTAssertEqual(m[0], 0)
        XCTAssertEqual(m[9 * 10 + 9], 0)
        XCTAssertEqual(m[3 * 10 + 1], 0, "row 3 col 1 is left of the square")
        XCTAssertEqual(SelectionPixels.rasterize([], width: 10, height: 10).max(), 0)
    }

    func testSplitConservesPixels() {
        let rgba: [UInt8] = [200, 100, 50, 255,  10, 20, 30, 40]
        let (lifted, remaining) = SelectionPixels.split(rgba, mask: [255, 128])
        XCTAssertEqual(Array(lifted[0..<4]), [200, 100, 50, 255])
        XCTAssertEqual(Array(remaining[0..<4]), [0, 0, 0, 0])
        XCTAssertEqual(zip(lifted, remaining).map { Int($0) + Int($1) }, rgba.map(Int.init), "nothing lost or gained")
    }

    func testRenderMovesInCanvasCoordinates() {
        let w = 8, h = 8
        var px = [UInt8](repeating: 0, count: w * h * 4)
        px[(1 * w + 1) * 4 + 3] = 255                           // pixel at (1, 1)
        let moved = SelectionPixels.render(px, width: w, height: h,
                                           transform: CGAffineTransform(translationX: 3, y: 2))
        XCTAssertEqual(moved[(3 * w + 4) * 4 + 3], 255, "right 3, down 2: canvas y points down")
        XCTAssertEqual(moved[(1 * w + 1) * 4 + 3], 0)
        XCTAssertEqual(SelectionPixels.render(px, width: w, height: h, transform: .identity), px)
    }

    func testCompositeIsSourceOver() {
        let top: [UInt8] = [128, 0, 0, 128]                     // half-transparent red
        let bottom: [UInt8] = [0, 0, 255, 255]                  // opaque blue
        XCTAssertEqual(SelectionPixels.composite(top, over: bottom), [128, 0, 127, 255])
    }

    func testMovingTheAnchorDoesntMoveTheDrawing() {
        var sel = FloatingSelection(key: LayerKey(clip: "c", frame: "f", layer: "l"), lifted: [],
                                    outline: [], bounds: CGRect(x: 0, y: 0, width: 10, height: 10),
                                    anchor: CGPoint(x: 5, y: 5))
        sel.scale = 2; sel.rotation = 0.7; sel.offset = CGVector(dx: 3, dy: -4); sel.flipped = true
        let probe = CGPoint(x: 9, y: 1)
        let before = probe.applying(sel.transform)
        sel.moveAnchor(to: CGPoint(x: 40, y: 12))
        let after = probe.applying(sel.transform)
        XCTAssertEqual(before.x, after.x, accuracy: 0.0001)
        XCTAssertEqual(before.y, after.y, accuracy: 0.0001)
        XCTAssertEqual(sel.placedAnchor.x, 40, accuracy: 0.0001, "the anchor is where it was dropped")
        XCTAssertEqual(sel.placedAnchor.y, 12, accuracy: 0.0001)
    }

    func testStretchingOneAxisLeavesTheOtherAndTheAnchor() {
        var sel = FloatingSelection(key: LayerKey(clip: "c", frame: "f", layer: "l"), lifted: [],
                                    outline: [], bounds: CGRect(x: 0, y: 0, width: 10, height: 10),
                                    anchor: CGPoint(x: 5, y: 10))
        sel.stretch = CGSize(width: 1.5, height: 0.5)
        XCTAssertFalse(sel.isIdentity)
        let right = CGPoint(x: 10, y: 10).applying(sel.transform)
        XCTAssertEqual(right.x, 12.5, accuracy: 0.0001, "1.5× as wide around the anchor")
        let top = CGPoint(x: 5, y: 0).applying(sel.transform)
        XCTAssertEqual(top.y, 5, accuracy: 0.0001, "half as tall, the feet stay put")
        let anchor = sel.anchor.applying(sel.transform)
        XCTAssertEqual(anchor.x, 5, accuracy: 0.0001)
        XCTAssertEqual(anchor.y, 10, accuracy: 0.0001)
    }

    func testStretchStacksOnScaleAndStaysWithRotation() {
        var sel = FloatingSelection(key: LayerKey(clip: "c", frame: "f", layer: "l"), lifted: [],
                                    outline: [], bounds: CGRect(x: 0, y: 0, width: 10, height: 10),
                                    anchor: .zero)
        sel.scale = 2; sel.stretch.width = 1.5
        XCTAssertEqual(sel.scaleX, 3); XCTAssertEqual(sel.scaleY, 2)
        sel.rotation = .pi / 2
        // Along its own width even when turned: the right edge now points down.
        let p = CGPoint(x: 1, y: 0).applying(sel.transform)
        XCTAssertEqual(p.x, 0, accuracy: 0.0001)
        XCTAssertEqual(p.y, 3, accuracy: 0.0001)
    }

    func testStretchClicksToItsOwnSizeOrToTheOtherAxis() {
        XCTAssertEqual(FloatingSelection.snappedStretch(1.03, scale: 1, other: 0.6), 1, "back to its own size")
        XCTAssertEqual(FloatingSelection.snappedStretch(0.62, scale: 1, other: 0.6), 0.6, "proportional again")
        XCTAssertEqual(FloatingSelection.snappedStretch(0.51, scale: 2, other: 1), 0.5, "100 % on screen at 2×")
        XCTAssertNil(FloatingSelection.snappedStretch(1.3, scale: 1, other: 1))
    }
}

/// Lasso through the editor: lift, move, drop, undo; cancel; auto-drop.
@MainActor
final class EditorStateSelectionTests: XCTestCase {

    private func makeState() throws -> EditorState {
        guard let device = MTLCreateSystemDefaultDevice(),
              let state = EditorState(device: device, screenFormat: .bgra8Unorm) else {
            throw XCTSkip("Metal unavailable in this environment")
        }
        return state
    }

    private func alpha(_ state: EditorState, x: Int, y: Int, layer: String = "line") -> UInt8 {
        guard let t = state.store.existingTexture(clip: state.clip.id, frame: state.currentFrame!.id, layer: layer),
              let px = state.renderer.readbackBytes(t) else { return 0 }
        return px[(y * state.renderer.canvasSize.x + x) * 4 + 3]
    }

    private func dot(_ state: EditorState, at p: SIMD2<Float>) throws {
        let target = try XCTUnwrap(state.beginStroke())
        state.renderer.paint([.init(position: p, radius: 10, alpha: 1)], into: target, color: SIMD4(0, 0, 0, 1), tool: .brush)
        state.strokeEnded()
    }

    private let box = [CGPoint(x: 80, y: 80), CGPoint(x: 120, y: 80), CGPoint(x: 120, y: 120), CGPoint(x: 80, y: 120)]

    func testLiftMoveDropIsOneUndoStep() throws {
        let state = try makeState()
        try dot(state, at: SIMD2(100, 100))
        try dot(state, at: SIMD2(300, 300))                     // outside the lasso
        let undoDepthBefore = state.canUndo
        state.tool = .lasso
        state.liftSelection(box)

        let sel = try XCTUnwrap(state.selection)
        XCTAssertEqual(sel.anchor, CGPoint(x: 100, y: 100))
        XCTAssertEqual(alpha(state, x: 100, y: 100), 0, "lifted off the layer while floating")
        XCTAssertGreaterThan(alpha(state, x: 300, y: 300), 200, "the rest stays")

        state.updateSelection { $0.offset = CGVector(dx: 50, dy: 0) }
        state.commitSelection()
        XCTAssertNil(state.selection)
        XCTAssertGreaterThan(alpha(state, x: 150, y: 100), 200, "dropped 50 px to the right")
        XCTAssertEqual(alpha(state, x: 100, y: 100), 0)

        state.undo()
        XCTAssertGreaterThan(alpha(state, x: 100, y: 100), 200, "one undo puts it back")
        XCTAssertEqual(alpha(state, x: 150, y: 100), 0)
        XCTAssertEqual(state.canUndo, undoDepthBefore)
    }

    func testCancelAndUndoWhileFloatingRestore() throws {
        let state = try makeState()
        try dot(state, at: SIMD2(100, 100))
        state.tool = .lasso
        state.liftSelection(box)
        state.updateSelection { $0.offset = CGVector(dx: 50, dy: 0) }
        state.cancelSelection()
        XCTAssertGreaterThan(alpha(state, x: 100, y: 100), 200)
        XCTAssertEqual(alpha(state, x: 150, y: 100), 0)

        state.liftSelection(box)
        state.updateSelection { $0.offset = CGVector(dx: 50, dy: 0) }
        state.undo()                                            // undo while floating = cancel
        XCTAssertNil(state.selection)
        XCTAssertGreaterThan(alpha(state, x: 100, y: 100), 200)
        XCTAssertTrue(state.canUndo, "the stroke is still in the history")
    }

    func testChangingFrameOrToolDropsTheSelection() throws {
        let state = try makeState()
        try dot(state, at: SIMD2(100, 100))
        state.addFrame()
        state.frameIndex = 0
        state.tool = .lasso
        state.liftSelection(box)
        state.updateSelection { $0.offset = CGVector(dx: 0, dy: 50) }
        state.frameIndex = 1
        XCTAssertNil(state.selection)
        state.frameIndex = 0
        XCTAssertGreaterThan(alpha(state, x: 100, y: 150), 200, "dropped where it was moved")

        state.liftSelection([CGPoint(x: 80, y: 130), CGPoint(x: 120, y: 130), CGPoint(x: 120, y: 170), CGPoint(x: 80, y: 170)])
        XCTAssertNotNil(state.selection)
        state.tool = .brush
        XCTAssertNil(state.selection)
    }

    func testEmptyLassoOrLockedLayerLiftsNothing() throws {
        let state = try makeState()
        try dot(state, at: SIMD2(100, 100))
        state.liftSelection([CGPoint(x: 300, y: 300), CGPoint(x: 340, y: 300), CGPoint(x: 340, y: 340)])
        XCTAssertNil(state.selection, "nothing under the lasso")
        state.toggleLayerLock(1)
        state.liftSelection(box)
        XCTAssertNil(state.selection)
        XCTAssertGreaterThan(alpha(state, x: 100, y: 100), 200)
    }

    func testFloatingSelectionIsDrawnAboveItsLayer() throws {
        let state = try makeState()
        try dot(state, at: SIMD2(100, 100))
        state.onion.enabled = false
        let before = state.visibleLayers().count
        state.liftSelection(box)
        XCTAssertEqual(state.visibleLayers().count, before + 1)
    }
}
