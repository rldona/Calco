import XCTest
import Metal
@testable import Calco

/// The Select tool's mask on its own: combining, inverting, its outline and moving it.
final class SelectionMaskTests: XCTestCase {

    private func square(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, size: Int = 10) -> [UInt8] {
        var m = [UInt8](repeating: 0, count: size * size)
        for y in y0..<y1 { for x in x0..<x1 { m[y * size + x] = 255 } }
        return m
    }

    func testAddSubtractReplaceAndInvert() {
        let a = SelectionMask(width: 10, height: 10, coverage: square(0, 0, 4, 4))
        let added = a.combined(with: square(6, 6, 10, 10), .add)
        XCTAssertEqual(added.bounds, CGRect(x: 0, y: 0, width: 10, height: 10))
        let cut = added.combined(with: square(0, 0, 2, 4), .subtract)
        XCTAssertEqual(cut.coverage[0], 0)
        XCTAssertEqual(cut.coverage[3], 255)
        XCTAssertEqual(cut.combined(with: square(5, 5, 6, 6), .replace).bounds, CGRect(x: 5, y: 5, width: 1, height: 1))
        XCTAssertTrue(SelectionMask.all(width: 10, height: 10).inverted.isEmpty)
        XCTAssertEqual(a.inverted.coverage[0], 0)
        XCTAssertEqual(a.inverted.coverage[99], 255)
    }

    func testOutlineRunsAlongThePixelEdges() {
        let m = SelectionMask(width: 10, height: 10, coverage: square(2, 3, 6, 8))
        XCTAssertEqual(m.outline.boundingBoxOfPath, CGRect(x: 2, y: 3, width: 4, height: 5))
        XCTAssertNil(SelectionMask(width: 10, height: 10, coverage: []).bounds)
    }

    func testMovingItCarriesTheCoverage() {
        let m = SelectionMask(width: 10, height: 10, coverage: square(0, 0, 2, 2))
        let moved = m.transformed(CGAffineTransform(translationX: 5, y: 3), hard: true)
        XCTAssertEqual(moved.bounds, CGRect(x: 5, y: 3, width: 2, height: 2))
    }

    func testFillThroughAMaskKeepsTheOutsideAndBlendsTheEdge() {
        var px = [UInt8](repeating: 0, count: 3 * 4)
        px[8] = 0; px[9] = 0; px[10] = 255; px[11] = 255               // third pixel: opaque blue
        let out = SelectionPixels.fill(px, mask: [255, 128, 0], color: SIMD3(1, 0, 0))
        XCTAssertEqual(Array(out[0..<4]), [255, 0, 0, 255])
        XCTAssertEqual(out[3 + 4], 128, "half covered: half the colour")
        XCTAssertEqual(Array(out[8..<12]), [0, 0, 255, 255], "outside untouched")
        XCTAssertEqual(SelectionPixels.blend([255, 255, 255, 255], [0, 0, 0, 0], mask: [0]), [0, 0, 0, 0])
    }
}

/// The Select tool in the editor: marking, then painting, filling, clearing, copying and
/// transforming only what's marked.
@MainActor
final class SelectToolTests: XCTestCase {

    private func makeState() throws -> EditorState {
        guard let device = MTLCreateSystemDefaultDevice(),
              let state = EditorState(device: device, screenFormat: .bgra8Unorm) else {
            throw XCTSkip("Metal unavailable in this environment")
        }
        return state
    }

    private func pixel(_ state: EditorState, _ x: Int, _ y: Int) -> [UInt8] {
        guard let key = state.currentDrawingKey,
              let t = state.store.existingTexture(clip: key.clip, frame: key.frame, layer: key.layer),
              let px = state.renderer.readbackBytes(t) else { return [0, 0, 0, 0] }
        let i = (y * state.renderer.canvasSize.x + x) * 4
        return Array(px[i..<i + 4])
    }

    /// A brush stroke across the canvas at height `y`, from x = 20 to 300.
    private func line(_ state: EditorState, y: Float) throws {
        let target = try XCTUnwrap(state.beginStroke())
        let stamps = stride(from: Float(20), through: 300, by: 2).map { CanvasRenderer.Stamp(position: SIMD2($0, y), radius: 6, alpha: 1) }
        state.paintStroke(stamps, into: target)
        state.strokeEnded()
    }

    func testPaintingStaysInsideTheRectangle() throws {
        let state = try makeState()
        state.tool = .lasso
        state.select.shape = .rect
        state.select.combine = .replace
        state.selectRect(from: CGPoint(x: 100, y: 0), to: CGPoint(x: 200, y: 512))
        XCTAssertNotNil(state.selectionMask)
        XCTAssertNotNil(state.selectionOutline)

        state.tool = .brush
        XCTAssertNotNil(state.selectionMask, "the selection stays while you paint")
        try line(state, y: 50)
        XCTAssertGreaterThan(pixel(state, 150, 50)[3], 200, "inside, painted")
        XCTAssertEqual(pixel(state, 50, 50)[3], 0, "left of it, not")
        XCTAssertEqual(pixel(state, 250, 50)[3], 0, "right of it, not")

        state.deselect()
        try line(state, y: 80)
        XCTAssertGreaterThan(pixel(state, 50, 80)[3], 200, "deselected, it reaches everywhere again")
    }

    func testFillClearAndUndoOnlyInside() throws {
        let state = try makeState()
        state.select.combine = .replace
        state.selectRect(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 30, y: 30))
        state.color = SIMD4(1, 0, 0, 1)
        state.fillSelection()
        XCTAssertEqual(pixel(state, 20, 20), [255, 0, 0, 255])
        XCTAssertEqual(pixel(state, 40, 40)[3], 0)
        state.undo()
        XCTAssertEqual(pixel(state, 20, 20)[3], 0, "one undo step")

        state.fillSelection()
        state.selectRect(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 20, y: 30))
        state.clearSelection()
        XCTAssertEqual(pixel(state, 15, 20)[3], 0, "cleared inside")
        XCTAssertEqual(pixel(state, 25, 20)[3], 255, "the rest stays")
    }

    func testAddAndSubtractShapeTheSelection() throws {
        let state = try makeState()
        state.select.combine = .replace
        state.selectRect(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 100))
        state.select.combine = .subtract
        state.selectRect(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 50, y: 100))
        XCTAssertEqual(state.selectionMask?.bounds, CGRect(x: 50, y: 0, width: 50, height: 100))
        state.select.combine = .add
        state.selectRect(from: CGPoint(x: 200, y: 200), to: CGPoint(x: 210, y: 210))
        XCTAssertEqual(state.selectionMask?.bounds, CGRect(x: 50, y: 0, width: 160, height: 210))
        state.select.combine = .replace
        state.selectRect(from: CGPoint(x: 5, y: 5), to: CGPoint(x: 5.2, y: 5.2))     // a tap
        XCTAssertNil(state.selectionMask, "a tap in New lets the selection go")
    }

    func testWandPicksThePatchOfColour() throws {
        let state = try makeState()
        state.selectRect(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 30, y: 30))
        state.color = SIMD4(0, 0, 1, 1)
        state.fillSelection()
        state.deselect()
        state.select.combine = .replace
        state.wandSelect(at: CGPoint(x: 20, y: 20))
        XCTAssertEqual(state.selectionMask?.bounds, CGRect(x: 9, y: 9, width: 22, height: 22), "with a pixel of soft edge")
        state.invertSelection()
        XCTAssertEqual(state.selectionMask?.coverage[20 * 512 + 20], 0)
        XCTAssertEqual(state.selectionMask?.coverage[0], 255)
    }

    func testCopyTransformAndTheSelectionFollows() throws {
        let state = try makeState()
        state.selectRect(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 30, y: 30))
        state.color = SIMD4(0, 0, 0, 1)
        state.fillSelection()
        state.selectRect(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 20, y: 30))

        state.copySelection()
        let copied = try XCTUnwrap(state.clipboard)
        XCTAssertEqual(copied.pixels[(20 * 512 + 15) * 4 + 3], 255)
        XCTAssertEqual(copied.pixels[(20 * 512 + 25) * 4 + 3], 0, "only what's selected")

        state.transformSelection()
        XCTAssertNotNil(state.selection, "lifted to transform")
        XCTAssertEqual(pixel(state, 15, 20)[3], 0)
        state.updateSelection { $0.offset = CGVector(dx: 100, dy: 0) }
        state.commitSelection()
        XCTAssertEqual(pixel(state, 115, 20)[3], 255, "put down 100 px to the right")
        XCTAssertEqual(state.selectionMask?.bounds, CGRect(x: 110, y: 10, width: 10, height: 20), "and the selection with it")
    }

    /// Alpha at a point on a given layer of the current frame.
    private func alpha(_ state: EditorState, layer: String, _ x: Int, _ y: Int) -> UInt8 {
        guard let key = state.drawingKey(layer: layer, at: state.frameIndex),
              let t = state.store.existingTexture(clip: key.clip, frame: key.frame, layer: key.layer),
              let px = state.renderer.readbackBytes(t) else { return 0 }
        return px[(y * state.renderer.canvasSize.x + x) * 4 + 3]
    }

    func testTransformMovesTheLinesAndTheirColourTogether() throws {
        let state = try makeState()
        state.selectRect(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 30, y: 30))
        state.color = SIMD4(0, 0, 0, 1)
        state.fillSelection()                                    // the lines, on Line
        state.layerIndex = 0                                     // Color, with some colour there
        state.selectRect(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 20, y: 30))
        state.color = SIMD4(1, 0.5, 0, 1)
        state.fillSelection()
        state.selectRect(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 30, y: 30))

        state.transformSelection()
        XCTAssertNotNil(state.selection)
        XCTAssertEqual(state.currentLayer?.id, "color", "the current layer leads")
        XCTAssertEqual(alpha(state, layer: "line", 15, 20), 0, "the lines are lifted too")
        state.updateSelection { $0.offset = CGVector(dx: 100, dy: 0) }
        state.commitSelection()
        XCTAssertEqual(alpha(state, layer: "line", 115, 20), 255, "both land 100 px to the right")
        XCTAssertEqual(alpha(state, layer: "color", 115, 20), 255)
        XCTAssertEqual(alpha(state, layer: "line", 15, 20), 0)

        state.undo()
        XCTAssertEqual(alpha(state, layer: "line", 15, 20), 255, "one undo puts both back")
        XCTAssertEqual(alpha(state, layer: "color", 15, 20), 255)
        XCTAssertEqual(alpha(state, layer: "line", 115, 20), 0)

        state.transformSelection()
        state.cancelSelection()
        XCTAssertEqual(alpha(state, layer: "line", 15, 20), 255, "cancel puts both back")

        state.selectRect(from: CGPoint(x: 200, y: 200), to: CGPoint(x: 220, y: 220))
        state.transformSelection()
        XCTAssertNil(state.selection)
        XCTAssertNotNil(state.selectNotice, "says why nothing happened")
    }

    func testInPixelArtASelectionHugsTheDrawnPixels() throws {
        let state = try makeState()
        state.selectRect(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 20, y: 20))
        state.color = SIMD4(0, 0, 0, 1)
        state.fillSelection()
        state.deselect()
        state.setPixelArt(true)
        state.selectRect(from: CGPoint(x: 200, y: 200), to: CGPoint(x: 220, y: 220))
        XCTAssertNil(state.selectionMask, "a box over nothing selects nothing")
        state.selectRect(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 100))
        XCTAssertEqual(state.selectionMask?.bounds, CGRect(x: 10, y: 10, width: 10, height: 10), "only the drawn pixels")
        state.selectAll()
        XCTAssertEqual(state.selectionMask?.bounds, CGRect(x: 10, y: 10, width: 10, height: 10))
    }

    func testUndoPutsTheSelectionBackWithTheDrawing() throws {
        let state = try makeState()
        state.selectRect(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 30, y: 30))
        state.color = SIMD4(0, 0, 0, 1)
        state.fillSelection()
        state.transformSelection()
        state.updateSelection { $0.offset = CGVector(dx: 100, dy: 0) }
        state.commitSelection()
        XCTAssertEqual(state.selectionMask?.bounds, CGRect(x: 110, y: 10, width: 20, height: 20))
        state.undo()
        XCTAssertEqual(state.selectionMask?.bounds, CGRect(x: 10, y: 10, width: 20, height: 20),
                       "back on the drawing, not floating where it had gone")
        state.redo()
        XCTAssertEqual(state.selectionMask?.bounds, CGRect(x: 110, y: 10, width: 20, height: 20))
    }

    func testWandBlockTakesEverythingTouchingWhateverTheColour() throws {
        let state = try makeState()
        state.selectRect(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 20, y: 20))
        state.color = SIMD4(1, 0, 0, 1)
        state.fillSelection()
        state.selectRect(from: CGPoint(x: 20, y: 10), to: CGPoint(x: 30, y: 20))
        state.color = SIMD4(0, 0, 1, 1)
        state.fillSelection()                                   // touching, another colour
        state.selectRect(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 110, y: 110))
        state.fillSelection()                                   // apart
        state.deselect()
        state.select.wandBlock = true
        state.wandSelect(at: CGPoint(x: 12, y: 12))
        XCTAssertEqual(state.selectionMask?.bounds, CGRect(x: 10, y: 10, width: 20, height: 10))
        state.select.wandBlock = false
        state.wandSelect(at: CGPoint(x: 12, y: 12))
        XCTAssertEqual(state.selectionMask?.bounds?.maxX ?? 0, 21, accuracy: 1, "by colour: only the red")
    }
}
