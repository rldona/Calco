import XCTest
import Metal
@testable import Calco

/// The mirror images of a stamp, on their own.
final class SymmetryTests: XCTestCase {

    func testImagesMirrorAcrossTheAxes() {
        let sym = Symmetry(mode: .both, x: 50, y: 20)
        XCTAssertEqual(sym.images(of: SIMD2(40, 10)), [SIMD2(40, 10), SIMD2(60, 10), SIMD2(40, 30), SIMD2(60, 30)])
        XCTAssertEqual(Symmetry(mode: .vertical, x: 50, y: 20).images(ofDelta: SIMD2(3, 1)), [SIMD2(3, 1), SIMD2(-3, 1)])
    }

    func testPixelArtMirrorsLandOnTheMirroredPixel() {
        // Axis on the edge between pixels 49 and 50: pixel 40 mirrors to pixel 59.
        let sym = Symmetry(mode: .vertical, x: 50, y: 0)
        let out = sym.mirrored([.init(position: SIMD2(40.8, 5.2), radius: 1, alpha: 1)], hard: true)
        XCTAssertEqual(out.map(\.position), [SIMD2(40.5, 5.5), SIMD2(59.5, 5.5)])
        // On a pixel's centre, it mirrors around that pixel.
        XCTAssertEqual(Symmetry(mode: .vertical, x: 50.5, y: 0)
            .mirrored([.init(position: SIMD2(48.1, 0.1), radius: 1, alpha: 1)], hard: true)[1].position, SIMD2(52.5, 0.5))
        // Pixel-art blocks sit on whole pixels: odd widths on a centre, even ones on a corner.
        let two = CanvasRenderer.snappedToPixel(.init(position: SIMD2(10.3, 10.7), radius: 2, alpha: 0.4))
        XCTAssertEqual(two.position, SIMD2(10, 11))
        XCTAssertEqual(two.radius, 1)
        XCTAssertEqual(two.alpha, 1)
        XCTAssertEqual(CanvasRenderer.snappedToPixel(.init(position: SIMD2(10.3, 10.7), radius: 3, alpha: 1)).position,
                       SIMD2(10.5, 10.5))
        XCTAssertEqual(Symmetry.snapped(12.3, limit: 100), 12.5)
        XCTAssertEqual(Symmetry.snapped(140, limit: 100), 100)
    }
}

/// Arrange, flip layer and symmetry in the editor.
@MainActor
final class ArrangeFlipSymmetryEditorTests: XCTestCase {

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

    /// A pencil stroke along a line, through `paintStroke`, so it's a piece with a recipe.
    private func line(_ state: EditorState, from a: SIMD2<Float>, to b: SIMD2<Float>, color: SIMD3<Float>) throws {
        state.color = SIMD4(color, 1)
        let target = try XCTUnwrap(state.beginStroke())
        state.paintStroke((0...20).map { .init(position: a + (b - a) * Float($0) / 20, radius: 6, alpha: 1) }, into: target)
        state.strokeEnded()
    }

    func testArrangeChangesWhichStrokeIsOnTop() throws {
        let state = try makeState()
        try line(state, from: SIMD2(100, 100), to: SIMD2(200, 100), color: SIMD3(1, 0, 0))   // red, below
        try line(state, from: SIMD2(150, 50), to: SIMD2(150, 150), color: SIMD3(0, 0, 1))    // blue, on top
        XCTAssertEqual(pixel(state, 150, 100)[2], 255, "blue crosses over red")

        state.tool = .move
        state.liftForMove(at: CGPoint(x: 110, y: 100))                                      // the red one
        XCTAssertTrue(state.canArrange)
        state.arrange(.front)
        state.commitSelection()
        XCTAssertEqual(pixel(state, 150, 100)[0], 255, "red is in front now")
        XCTAssertEqual(pixel(state, 150, 100)[2], 0)

        state.undo()
        XCTAssertEqual(pixel(state, 150, 100)[2], 255, "undo brings blue back on top")

        state.liftForMove(at: CGPoint(x: 150, y: 60))                                       // blue
        state.arrange(.backward)
        state.cancelSelection()
        XCTAssertEqual(pixel(state, 150, 100)[2], 255, "cancel keeps the order")
    }

    func testFlipLayerMirrorsTheDrawingAndKeepsItsStrokes() throws {
        let state = try makeState()
        try line(state, from: SIMD2(20, 30), to: SIMD2(60, 30), color: SIMD3(0, 0, 0))
        state.flipLayer()
        XCTAssertEqual(pixel(state, 40, 30)[3], 0)
        XCTAssertGreaterThan(pixel(state, 511 - 40, 30)[3], 200, "mirrored left to right")
        state.tool = .move
        XCTAssertNotNil(state.selection, "still a stroke Move picks up")
        state.cancelSelection()
        state.tool = .brush
        state.flipLayer(vertically: true)
        XCTAssertGreaterThan(pixel(state, 511 - 40, 511 - 30)[3], 200)
        state.undo()
        state.undo()
        XCTAssertGreaterThan(pixel(state, 40, 30)[3], 200, "two undos and it's back")
    }

    func testSymmetryPaintsTheMirrorToo() throws {
        let state = try makeState()
        state.setSymmetry(.vertical)
        XCTAssertEqual(state.project.symmetry?.x, 256)
        try line(state, from: SIMD2(100, 50), to: SIMD2(120, 50), color: SIMD3(0, 0, 0))
        XCTAssertGreaterThan(pixel(state, 110, 50)[3], 200)
        XCTAssertGreaterThan(pixel(state, 512 - 110, 50)[3], 200, "and its mirror")

        state.moveSymmetryAxis(x: 300.3)
        XCTAssertEqual(state.project.symmetry?.x, 300.5, "on a half pixel")
        state.setSymmetry(nil)
        try line(state, from: SIMD2(100, 200), to: SIMD2(120, 200), color: SIMD3(0, 0, 0))
        XCTAssertEqual(pixel(state, 512 - 110, 200)[3], 0, "off, no mirror")

        let data = try JSONEncoder().encode(state.project)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("symmetry"), "off isn't written")
        state.setSymmetry(.both)
        let back = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(state.project))
        XCTAssertEqual(back.symmetry?.mode, .both, "saved with the project")
    }
}
