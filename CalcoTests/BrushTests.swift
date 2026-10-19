import XCTest
import Metal
@testable import Calco

/// The brush library: presets, per-brush settings, and how each lays paint.
@MainActor
final class BrushTests: XCTestCase {

    private func makeState() throws -> EditorState {
        guard let device = MTLCreateSystemDefaultDevice(),
              let state = EditorState(device: device, screenFormat: .bgra8Unorm) else {
            throw XCTSkip("Metal unavailable in this environment")
        }
        return state
    }

    private func pixel(_ state: EditorState, x: Int, y: Int) -> [UInt8] {
        guard let l = state.currentLayer,
              let t = state.store.existingTexture(clip: state.clip.id, frame: state.currentFrame!.id, layer: l.id),
              let px = state.renderer.readbackBytes(t) else { return [0, 0, 0, 0] }
        let i = (y * state.renderer.canvasSize.x + x) * 4
        return Array(px[i..<(i + 4)])
    }

    /// A stroke with the current brush, as the canvas builds it.
    private func stroke(_ state: EditorState, _ points: [SIMD2<Float>], force: Float = 1) throws {
        let target = try XCTUnwrap(state.beginStroke())
        var b = StrokeBuilder()
        b.baseRadius = state.toolSize
        b.use(state.activeBrush)
        b.begin()
        var stamps: [CanvasRenderer.Stamp] = []
        for i in 0..<(points.count - 1) {
            for k in 0...20 {
                stamps += b.add(.init(position: points[i] + (points[i + 1] - points[i]) * Float(k) / 20, force: force))
            }
        }
        state.paintStroke(stamps, into: target)
        state.strokeEnded()
    }

    func testEveryBrushHasAName() {
        XCTAssertEqual(Set(Brush.all.map(\.id)).count, Brush.all.count)
        for b in Brush.all { XCTAssertFalse(b.name.isEmpty); XCTAssertFalse(b.detail.isEmpty) }
        XCTAssertEqual(Brush.named("nope"), .inker)
    }

    func testEachBrushRemembersItsSizeAndOpacity() throws {
        let state = try makeState()
        state.brushID = Brush.marker.id
        XCTAssertEqual(state.brushSize, Brush.marker.defaultSize)
        XCTAssertEqual(state.brushOpacity, 0.7)
        state.toolSize = 20
        state.brushOpacity = 0.4
        state.brushID = Brush.ballpoint.id
        XCTAssertEqual(state.brushSize, Brush.ballpoint.defaultSize)
        XCTAssertEqual(state.brushOpacity, 1)
        state.brushID = Brush.marker.id
        XCTAssertEqual(state.brushSize, 20)
        XCTAssertEqual(state.brushOpacity, 0.4, accuracy: 1e-6)
    }

    func testMarkerStaysEvenWhereItCrossesItself() throws {
        let state = try makeState()
        state.brushID = Brush.marker.id
        state.toolSize = 10
        // Out and back over the same line.
        try stroke(state, [SIMD2(50, 100), SIMD2(200, 100), SIMD2(50, 100)])
        let once = pixel(state, x: 204, y: 100)            // the round end, painted once
        let twice = pixel(state, x: 120, y: 100)           // gone over twice
        XCTAssertEqual(Int(twice[3]), Int(once[3]), accuracy: 3, "no darker where it overlaps")
        XCTAssertEqual(Int(twice[3]), Int(0.7 * 255), accuracy: 4, "at the marker's opacity")
    }

    func testAirbrushBuildsUpAndBluePencilKeepsItsColour() throws {
        let state = try makeState()
        state.brushID = Brush.airbrush.id
        try stroke(state, [SIMD2(50, 50), SIMD2(200, 50)])
        let light = pixel(state, x: 120, y: 50)[3]
        try stroke(state, [SIMD2(50, 50), SIMD2(200, 50)])
        XCTAssertGreaterThan(pixel(state, x: 120, y: 50)[3], light, "a second pass is darker")

        state.color = SIMD4(1, 0, 0, 1)
        state.brushID = Brush.bluePencil.id
        state.toolSize = 6
        try stroke(state, [SIMD2(50, 150), SIMD2(200, 150)])
        let p = pixel(state, x: 120, y: 150)
        XCTAssertGreaterThan(p[2], p[0], "blue, whatever the chosen colour")
    }

    func testPressureAndTaper() {
        var b = StrokeBuilder()
        b.baseRadius = 10
        b.use(.pencil)
        b.begin()
        let soft = b.add(.init(position: SIMD2(0, 0), force: 0.1))[0]
        b.begin()
        let firm = b.add(.init(position: SIMD2(0, 0), force: 1))[0]
        XCTAssertLessThan(soft.alpha, firm.alpha, "the pencil is lighter when you press lightly")

        b.use(.paintbrush)
        b.begin()
        let start = b.add(.init(position: SIMD2(0, 0), force: 1))[0]
        var later: [CanvasRenderer.Stamp] = []
        for x in stride(from: Float(1), through: 200, by: 1) { later += b.add(.init(position: SIMD2(x, 0), force: 1)) }
        XCTAssertLessThan(start.radius, later.last!.radius, "the paintbrush starts thin")

        b.use(.pencil)
        b.begin()
        let upright = b.add(.init(position: SIMD2(0, 0), force: 1, tilt: 0))[0]
        b.begin()
        let leaning = b.add(.init(position: SIMD2(0, 0), force: 1, tilt: 0.9))[0]
        XCTAssertGreaterThan(leaning.radius, upright.radius, "tilted: wider")
        XCTAssertLessThan(leaning.alpha, upright.alpha, "and lighter")
    }

    func testEraserUsesItsOwnTipAndStrokesStayPieces() throws {
        let state = try makeState()
        try stroke(state, [SIMD2(40, 100), SIMD2(200, 100)])
        try stroke(state, [SIMD2(120, 30), SIMD2(120, 170)])
        let key = try XCTUnwrap(state.currentDrawingKey)
        XCTAssertEqual(state.strokes[key]?.count, 2)
        state.tool = .eraser
        state.eraserBrushID = Brush.airbrush.id
        XCTAssertEqual(state.activeBrush, .airbrush)
        state.toolSize = 30
        try stroke(state, [SIMD2(60, 100), SIMD2(70, 100)])
        XCTAssertLessThan(pixel(state, x: 65, y: 100)[3], 255, "softly rubbed out")
        XCTAssertNotNil(state.strokes[key])
    }
}
