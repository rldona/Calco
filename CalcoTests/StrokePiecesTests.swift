import XCTest
import Metal
@testable import Calco

/// Pieces on their own: crop, stack, split, erase, save.
final class StrokePiecesTests: XCTestCase {

    /// A canvas with an opaque w×h block at (x, y) of grey `v`.
    private func block(_ cw: Int, _ ch: Int, x: Int, y: Int, w: Int, h: Int, v: UInt8 = 200) -> [UInt8] {
        var px = [UInt8](repeating: 0, count: cw * ch * 4)
        for yy in y..<(y + h) { for xx in x..<(x + w) {
            let i = (yy * cw + xx) * 4
            px[i] = v; px[i + 1] = v; px[i + 2] = v; px[i + 3] = 255
        } }
        return px
    }

    func testAPieceIsCroppedToItsPaintAndGoesBack() throws {
        let canvas = block(10, 10, x: 2, y: 3, w: 4, h: 2)
        let p = try XCTUnwrap(StrokePiece(canvas: canvas, width: 10, height: 10))
        XCTAssertEqual(p.rect, CGRect(x: 2, y: 3, width: 4, height: 2))
        XCTAssertEqual(p.canvas(width: 10, height: 10), canvas)
        XCTAssertNil(StrokePiece(canvas: [UInt8](repeating: 0, count: 400), width: 10, height: 10))
    }

    func testTheTopPieceWinsWhereTheyOverlap() throws {
        let low = try XCTUnwrap(StrokePiece(canvas: block(10, 10, x: 0, y: 0, w: 6, h: 6, v: 50), width: 10, height: 10))
        let high = try XCTUnwrap(StrokePiece(canvas: block(10, 10, x: 3, y: 3, w: 6, h: 6, v: 250), width: 10, height: 10))
        let out = StrokePieces.composite([low, high], width: 10, height: 10)
        XCTAssertEqual(out[(4 * 10 + 4) * 4], 250)
        XCTAssertEqual(out[(1 * 10 + 1) * 4], 50)
    }

    func testAnUnknownDrawingSplitsIntoItsShapes() {
        var px = block(20, 20, x: 1, y: 1, w: 3, h: 3)
        let other = block(20, 20, x: 10, y: 10, w: 4, h: 4)
        for i in 0..<px.count where other[i] != 0 { px[i] = other[i] }
        let shapes = StrokePieces.shapes(of: px, width: 20, height: 20)
        XCTAssertEqual(shapes.count, 2)
        XCTAssertEqual(StrokePieces.composite(shapes, width: 20, height: 20), px, "nothing lost")
    }

    func testTheEraserTrimsAPieceAndCanRemoveIt() throws {
        let p = try XCTUnwrap(StrokePiece(canvas: block(10, 10, x: 0, y: 0, w: 4, h: 1), width: 10, height: 10))
        var cover = [UInt8](repeating: 0, count: 100)
        cover[0] = 255; cover[1] = 255
        let trimmed = try XCTUnwrap(p.erased(by: cover, canvasWidth: 10))
        XCTAssertEqual(trimmed.pixels[3], 0)
        XCTAssertEqual(trimmed.pixels[2 * 4 + 3], 255)
        XCTAssertNil(p.erased(by: [UInt8](repeating: 255, count: 100), canvasWidth: 10), "erased away")
    }

    func testMatchToleratesASoftEdgeButNotARepaint() {
        let a = block(20, 20, x: 2, y: 2, w: 10, h: 10)
        var b = a
        b[(5 * 20 + 2) * 4 + 3] = 230                         // one edge pixel a bit off
        XCTAssertTrue(StrokePieces.match(a, b))
        let filled = block(20, 20, x: 0, y: 0, w: 20, h: 20)
        XCTAssertFalse(StrokePieces.match(a, filled))
    }

    func testPiecesSurviveTheFile() throws {
        let pieces = [try XCTUnwrap(StrokePiece(canvas: block(10, 10, x: 1, y: 2, w: 3, h: 4), width: 10, height: 10)),
                      try XCTUnwrap(StrokePiece(canvas: block(10, 10, x: 5, y: 5, w: 2, h: 2, v: 9), width: 10, height: 10))]
        let data = try XCTUnwrap(StrokePieces.encode(pieces))
        XCTAssertEqual(StrokePieces.decode(data), pieces)
        XCTAssertNil(StrokePieces.decode(Data("nope".utf8)))
    }
}

/// Strokes remembered by the editor and picked one by one with Move.
@MainActor
final class StrokeMoveTests: XCTestCase {

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

    /// A pencil stroke from `a` to `b`, as the canvas would paint it.
    private func stroke(_ state: EditorState, _ a: SIMD2<Float>, _ b: SIMD2<Float>, radius: Float = 4) throws {
        let target = try XCTUnwrap(state.beginStroke())
        let stamps = (0...40).map { i -> CanvasRenderer.Stamp in
            .init(position: a + (b - a) * Float(i) / 40, radius: radius, alpha: 1)
        }
        state.paintStroke(stamps, into: target)
        state.strokeEnded()
    }

    private var key: (EditorState) -> LayerKey? { { $0.currentDrawingKey } }

    /// A horizontal stroke, then a vertical one crossing it at (100, 100).
    private func cross() throws -> EditorState {
        let state = try makeState()
        try stroke(state, SIMD2(40, 100), SIMD2(160, 100))
        try stroke(state, SIMD2(100, 40), SIMD2(100, 160))
        return state
    }

    func testEachPencilStrokeIsAPiece() throws {
        let state = try cross()
        XCTAssertEqual(state.strokes[try XCTUnwrap(key(state))]?.count, 2)
    }

    func testTappingWhereTheyCrossPicksTheTopOneThenTheOneBelow() throws {
        let state = try cross()
        state.tool = .move
        state.liftForMove(at: CGPoint(x: 100, y: 100))
        XCTAssertEqual(state.moveHint, .init(here: 2, number: 2, selected: 1))
        XCTAssertEqual(alpha(state, x: 100, y: 50), 0, "the vertical stroke floats")
        XCTAssertGreaterThan(alpha(state, x: 50, y: 100), 200, "the horizontal one stays")

        state.liftForMove(at: CGPoint(x: 101, y: 100))
        XCTAssertEqual(state.moveHint, .init(here: 2, number: 1, selected: 1))
        XCTAssertEqual(alpha(state, x: 50, y: 100), 0, "now the one underneath")
        XCTAssertGreaterThan(alpha(state, x: 100, y: 50), 200)
    }

    func testAMovedStrokeStaysAStroke() throws {
        let state = try cross()
        state.tool = .move
        state.liftForMove(at: CGPoint(x: 100, y: 50))
        state.updateSelection { $0.offset = CGVector(dx: 30, dy: 0) }
        state.commitSelection()
        XCTAssertEqual(state.strokes[try XCTUnwrap(key(state))]?.count, 2)
        XCTAssertGreaterThan(alpha(state, x: 130, y: 50), 200)

        state.liftForMove(at: CGPoint(x: 130, y: 50))            // pick it again where it is now
        XCTAssertEqual(alpha(state, x: 130, y: 50), 0)
        XCTAssertGreaterThan(alpha(state, x: 50, y: 100), 200, "alone")
    }

    func testAddingStrokesPicksSeveral() throws {
        let state = try cross()
        state.tool = .move
        state.liftForMove(at: CGPoint(x: 100, y: 50))
        state.addingStrokes = true
        state.liftForMove(at: CGPoint(x: 50, y: 100))
        XCTAssertEqual(state.moveHint?.selected, 2)
        XCTAssertEqual(alpha(state, x: 100, y: 50), 0)
        XCTAssertEqual(alpha(state, x: 50, y: 100), 0)
        state.liftForMove(at: CGPoint(x: 50, y: 100))            // and out again
        XCTAssertEqual(state.moveHint?.selected, 1)
    }

    func testDraggingAStrokeAwayAndUndoing() throws {
        let state = try cross()
        let k = try XCTUnwrap(key(state))
        state.tool = .move
        state.liftForMove(at: CGPoint(x: 100, y: 50))
        state.updateSelection { $0.offset = CGVector(dx: 0, dy: 40) }
        state.commitSelection()
        state.undo()
        XCTAssertGreaterThan(alpha(state, x: 100, y: 50), 200, "back where it was")
        XCTAssertEqual(state.strokes[k]?.count, 2, "and still two strokes")
    }

    func testTheEraserTrimsStrokesAndAFillMergesThem() throws {
        let state = try cross()
        let k = try XCTUnwrap(key(state))
        state.tool = .eraser
        try stroke(state, SIMD2(100, 30), SIMD2(100, 170), radius: 10)     // rubs out the vertical stroke
        XCTAssertEqual(state.strokes[k]?.count, 1, "only the horizontal one is left")

        state.tool = .fill
        state.fill(at: SIMD2(10, 10))
        XCTAssertNil(state.strokes[k], "filled: no longer known stroke by stroke")
        state.tool = .move
        XCTAssertNotNil(state.selection, "Move still works, on the drawing's shapes")
    }

    func testStrokesAreSavedWithTheProject() throws {
        let state = try cross()
        let k = try XCTUnwrap(key(state))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("strokes-\(UUID().uuidString).calco")
        defer { try? FileManager.default.removeItem(at: url) }
        state.save(to: url)
        XCTAssertNil(state.lastError)
        let loaded = try ProjectDocument.load(from: url)
        let files = ProjectDocument.loadLayerStrokes(from: url, project: loaded)
        XCTAssertEqual(files[k].flatMap(StrokePieces.decode), state.strokes[k])

        state.open(url)
        XCTAssertEqual(state.strokes[k]?.count, 2, "reopened, still two strokes")
    }
}
