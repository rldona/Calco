import XCTest
import Metal
@testable import Calco

/// The project palette: recolouring drawings and finding their colours.
final class PalettePixelsTests: XCTestCase {

    private let red = SIMD3<Float>(1, 0, 0), blue = SIMD3<Float>(0, 0, 1)

    func testHexRoundTrip() {
        XCTAssertEqual(Palette.hex(SIMD3(0.97, 0.66, 0.29)), "#F7A84A")
        XCTAssertEqual(Palette.rgb("#F7A84A").map(Palette.hex), "#F7A84A")
        XCTAssertNil(Palette.rgb("orange"))
    }

    func testRecolourKeepsSoftEdgesAndLeavesOtherColoursAlone() throws {
        // Solid red, half-transparent red (a soft edge), green, and nothing.
        let px: [UInt8] = [255, 0, 0, 255,   128, 0, 0, 128,   0, 255, 0, 255,   0, 0, 0, 0]
        let out = try XCTUnwrap(Palette.recolor(px, width: 4, from: red, to: blue, hard: false))
        XCTAssertEqual(Array(out[0..<4]), [0, 0, 255, 255])
        XCTAssertEqual(Array(out[4..<8]), [0, 0, 128, 128], "the edge stays as soft, in the new colour")
        XCTAssertEqual(Array(out[8..<16]), Array(px[8..<16]), "green and nothing don't change")
        XCTAssertNil(Palette.recolor([0, 255, 0, 255], width: 1, from: red, to: blue, hard: false), "nothing of that colour")
    }

    func testTheEdgeWhereItMeetsAnotherColourGoesToo() throws {
        // Red, a half red / half white edge pixel, white.
        let px: [UInt8] = [255, 0, 0, 255,   255, 128, 128, 255,   255, 255, 255, 255]
        let out = try XCTUnwrap(Palette.recolor(px, width: 3, from: red, to: blue, hard: false))
        XCTAssertEqual(Array(out[0..<4]), [0, 0, 255, 255])
        XCTAssertEqual(Array(out[4..<8]), [128, 128, 255, 255], "half blue / half white now: no red ring left")
        XCTAssertEqual(Array(out[8..<12]), [255, 255, 255, 255])
    }

    func testPixelArtIsExact() {
        let nearlyRed: [UInt8] = [250, 4, 0, 255]
        XCTAssertNotNil(Palette.recolor(nearlyRed, width: 1, from: red, to: blue, hard: false))
        XCTAssertNil(Palette.recolor(nearlyRed, width: 1, from: red, to: blue, hard: true))
    }

    func testDominantColoursMostUsedFirst() {
        var px: [UInt8] = []
        for _ in 0..<300 { px += [255, 0, 0, 255] }
        for _ in 0..<100 { px += [0, 0, 255, 255] }
        for _ in 0..<50 { px += [250, 5, 3, 255] }            // red, give or take
        for _ in 0..<500 { px += [0, 255, 0, 40] }             // soft, not counted
        px += [9, 9, 9, 255]                                    // a stray pixel, too little
        let colors = Palette.dominantColors([px], share: 0.01)
        XCTAssertEqual(colors.map(Palette.hex), ["#FF0000", "#0000FF"])
    }

    func testThePaletteIsOptionalInTheFile() throws {
        let p = Project(name: "P", canvas: CanvasSize(width: 8, height: 8))
        XCTAssertFalse(String(data: try JSONEncoder().encode(p), encoding: .utf8)!.contains("palette"))
        var q = p
        q.palette = [PaletteColor(name: "Body", color: "#F7A94A")]
        let back = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(q))
        XCTAssertEqual(back.palette, q.palette)
    }
}

@MainActor
final class PaletteEditorTests: XCTestCase {

    private func makeState() throws -> EditorState {
        guard let device = MTLCreateSystemDefaultDevice(),
              let state = EditorState(device: device, screenFormat: .bgra8Unorm) else {
            throw XCTSkip("Metal unavailable in this environment")
        }
        AppLanguage.apply(.english, save: false)
        return state
    }

    private func pixel(_ state: EditorState, frame: Int, x: Int, y: Int) -> [UInt8] {
        guard let l = state.currentLayer,
              let t = state.store.existingTexture(clip: state.clip.id, frame: state.frames[frame].id, layer: l.id),
              let px = state.renderer.readbackBytes(t) else { return [] }
        let i = (y * state.renderer.canvasSize.x + x) * 4
        return Array(px[i..<(i + 4)])
    }

    private func stroke(_ state: EditorState, at x: Float) throws {
        let target = try XCTUnwrap(state.beginStroke())
        state.paintStroke((0...20).map { .init(position: SIMD2(x, 100 + Float($0)), radius: 4, alpha: 1) }, into: target)
        state.strokeEnded()
    }

    func testChangingAColourEverywhereRepaintsEveryFrameAndUndoesInOne() throws {
        let state = try makeState()
        state.setColor(SIMD4(1, 0, 0, 1))
        try stroke(state, at: 100)
        state.addDrawing()
        try stroke(state, at: 100)
        state.setColor(SIMD4(0, 1, 0, 1))
        try stroke(state, at: 200)                             // green stays green
        state.setColor(SIMD4(1, 0, 0, 1))
        state.addColorToPalette(name: "Body")
        let id = try XCTUnwrap(state.project.palette.first?.id)

        XCTAssertEqual(state.changePaletteColorEverywhere(id, to: SIMD3(0, 0, 1)), 2)
        XCTAssertEqual(pixel(state, frame: 0, x: 100, y: 110), [0, 0, 255, 255])
        XCTAssertEqual(pixel(state, frame: 1, x: 100, y: 110), [0, 0, 255, 255])
        XCTAssertEqual(pixel(state, frame: 1, x: 200, y: 110), [0, 255, 0, 255])
        XCTAssertEqual(state.project.palette[0].color, "#0000FF")
        XCTAssertEqual(state.color, SIMD4(0, 0, 1, 1), "the bar follows its colour")
        let key = try XCTUnwrap(state.currentDrawingKey)
        XCTAssertEqual(state.strokes[key]?.first?.recipe?.color, SIMD3(0, 0, 1), "remembered strokes too, to stay sharp")

        state.undo()
        XCTAssertEqual(pixel(state, frame: 0, x: 100, y: 110), [255, 0, 0, 255])
        XCTAssertEqual(pixel(state, frame: 1, x: 100, y: 110), [255, 0, 0, 255])
        XCTAssertEqual(state.project.palette[0].color, "#FF0000")
    }

    func testPaletteEditsAndSuggestion() throws {
        let state = try makeState()
        state.setColor(SIMD4(1, 0, 0, 1))
        try stroke(state, at: 100)
        state.suggestPalette()
        XCTAssertEqual(state.project.palette.map(\.color), ["#FF0000"])
        let id = state.project.palette[0].id
        state.renamePaletteColor(id, to: "Cape")
        state.duplicatePaletteColor(id)
        XCTAssertEqual(state.project.palette.map(\.name), ["Cape", "Cape variant"])
        state.removePaletteColor(id)
        XCTAssertEqual(state.project.palette.map(\.name), ["Cape variant"])
        state.undo()
        XCTAssertEqual(state.project.palette.count, 2)
    }
}
