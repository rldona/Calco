import XCTest
import Metal
@testable import Calco

/// Growing or shrinking the canvas around the drawing, without scaling it.
final class CanvasResizeTests: XCTestCase {

    func testTheAnchorSaysWhereTheRoomGoes() {
        let old = CanvasSize(width: 100, height: 100), new = CanvasSize(width: 200, height: 160)
        XCTAssertTrue(CanvasResize.offset(from: old, to: new, anchor: .topLeft) == (0, 0))
        XCTAssertTrue(CanvasResize.offset(from: old, to: new, anchor: .center) == (50, 30))
        XCTAssertTrue(CanvasResize.offset(from: old, to: new, anchor: .bottomRight) == (100, 60))
        XCTAssertTrue(CanvasResize.offset(from: new, to: old, anchor: .center) == (-50, -30), "shrinking cuts evenly")
    }

    func testPixelsMoveAndWhatFallsOutsideIsCut() {
        let old = CanvasSize(width: 2, height: 2)
        let px: [UInt8] = [1, 1, 1, 1, 2, 2, 2, 2,
                           3, 3, 3, 3, 4, 4, 4, 4]
        let grown = CanvasResize.shifted(px, from: old, to: CanvasSize(width: 3, height: 3), dx: 1, dy: 1)
        XCTAssertEqual(grown[(1 * 3 + 1) * 4], 1)
        XCTAssertEqual(grown[(2 * 3 + 2) * 4], 4)
        XCTAssertEqual(grown[0], 0)
        let cut = CanvasResize.shifted(px, from: old, to: CanvasSize(width: 1, height: 1), dx: -1, dy: -1)
        XCTAssertEqual(cut, [4, 4, 4, 4])
    }

    func testPiecesMoveWithTheirRecipeAndAreCut() throws {
        let recipe = StrokeRecipe(stamps: [.init(position: SIMD2(5, 5), radius: 2, alpha: 1)], color: .zero,
                                  tip: .init(), opacity: 1, hard: false)
        let piece = StrokePiece(x: 4, y: 4, width: 2, height: 2, pixels: [UInt8](repeating: 255, count: 16), recipe: recipe)
        let moved = try XCTUnwrap(CanvasResize.shifted(piece, dx: 10, dy: 3, in: CanvasSize(width: 50, height: 50)))
        XCTAssertEqual(moved.rect, CGRect(x: 14, y: 7, width: 2, height: 2))
        XCTAssertEqual(moved.recipe?.stamps.first?.position, SIMD2(15, 8))
        let half = try XCTUnwrap(CanvasResize.shifted(piece, dx: -5, dy: 0, in: CanvasSize(width: 50, height: 50)))
        XCTAssertEqual(half.rect, CGRect(x: 0, y: 4, width: 1, height: 2))
        XCTAssertNil(CanvasResize.shifted(piece, dx: -10, dy: 0, in: CanvasSize(width: 50, height: 50)))
    }

    func testThePivotStaysOnTheSamePixel() {
        // The feet: middle bottom of a 100 px canvas, which grows 100 px to the right and 50 on top.
        let p = CanvasResize.pivot(Pivot(x: 0.5, y: 0), from: CanvasSize(width: 100, height: 100),
                                   to: CanvasSize(width: 200, height: 150), dx: 0, dy: 50)
        XCTAssertEqual(p.x, 0.25, accuracy: 1e-9)
        XCTAssertEqual(p.y, 0, accuracy: 1e-9)
    }
}

@MainActor
final class CanvasResizeEditorTests: XCTestCase {

    private func makeState() throws -> EditorState {
        guard let device = MTLCreateSystemDefaultDevice(),
              let state = EditorState(device: device, screenFormat: .bgra8Unorm) else {
            throw XCTSkip("Metal unavailable in this environment")
        }
        return state
    }

    private func alpha(_ state: EditorState, _ x: Int, _ y: Int) -> UInt8 {
        guard let key = state.currentDrawingKey,
              let t = state.store.existingTexture(clip: key.clip, frame: key.frame, layer: key.layer),
              let px = state.renderer.readbackBytes(t) else { return 0 }
        return px[(y * state.renderer.canvasSize.x + x) * 4 + 3]
    }

    private func line(_ state: EditorState, from a: SIMD2<Float>, to b: SIMD2<Float>) throws {
        let target = try XCTUnwrap(state.beginStroke())
        let stamps = (0...20).map { i in
            CanvasRenderer.Stamp(position: a + (b - a) * Float(i) / 20, radius: 4, alpha: 1)
        }
        state.paintStroke(stamps, into: target)
        state.strokeEnded()
    }

    func testGrowingKeepsTheDrawingAndItsStrokes() throws {
        let state = try makeState()
        try line(state, from: SIMD2(100, 100), to: SIMD2(200, 100))
        state.resizeCanvas(to: CanvasSize(width: 768, height: 512), dx: 0, dy: 0)
        XCTAssertEqual(state.project.canvas, CanvasSize(width: 768, height: 512))
        XCTAssertEqual(state.renderer.canvasSize, SIMD2(768, 512))
        XCTAssertGreaterThan(alpha(state, 150, 100), 200, "the drawing stays where it was")

        state.tool = .move
        let sel = try XCTUnwrap(state.selection, "Move still picks the stroke")
        XCTAssertEqual(sel.bounds.minX, 94, accuracy: 3)
        state.cancelSelection()
        state.tool = .brush

        state.undo()
        XCTAssertEqual(state.project.canvas, CanvasSize(width: 512, height: 512))
        XCTAssertGreaterThan(alpha(state, 150, 100), 200)
        state.redo()
        XCTAssertEqual(state.project.canvas, CanvasSize(width: 768, height: 512))
    }

    func testShrinkingCutsAndUndoBringsItBack() throws {
        let state = try makeState()
        try line(state, from: SIMD2(20, 20), to: SIMD2(60, 20))       // will be cut
        try line(state, from: SIMD2(300, 300), to: SIMD2(400, 300))   // will stay
        state.resizeCanvas(to: CanvasSize(width: 256, height: 256), dx: -200, dy: -200)
        XCTAssertGreaterThan(alpha(state, 150, 100), 200, "moved up and left by 200")
        XCTAssertEqual(alpha(state, 20, 20), 0)
        XCTAssertNotNil(state.drawingBounds())

        state.undo()
        XCTAssertGreaterThan(alpha(state, 40, 20), 200, "what was cut is back")
        XCTAssertGreaterThan(alpha(state, 350, 300), 200)
    }

    func testFitCropsToTheDrawing() throws {
        let state = try makeState()
        try line(state, from: SIMD2(100, 200), to: SIMD2(300, 200))
        let b = try XCTUnwrap(state.drawingBounds())
        XCTAssertEqual(b.minX, 96, accuracy: 2)
        XCTAssertEqual(b.maxX, 304, accuracy: 2)
        state.resizeCanvas(to: CanvasSize(width: Int(b.width), height: max(16, Int(b.height))), dx: -Int(b.minX), dy: -Int(b.minY))
        XCTAssertEqual(state.project.canvas.width, Int(b.width))
        XCTAssertGreaterThan(alpha(state, Int(b.width) / 2, 4), 200)
    }
}
