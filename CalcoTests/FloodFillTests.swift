import XCTest
import Metal
@testable import Calco

final class FloodFillTests: XCTestCase {

    /// 9×9 transparent canvas with an opaque black square outline from (2,2) to (6,6).
    private func boxed() -> (rgba: [UInt8], w: Int, h: Int) {
        let w = 9, h = 9
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for y in 2...6 { for x in 2...6 where x == 2 || x == 6 || y == 2 || y == 6 { px[(y * w + x) * 4 + 3] = 255 } }
        return (px, w, h)
    }

    private func count(_ m: [Bool]) -> Int { m.filter { $0 }.count }

    func testFillStaysInsideTheOutline() {
        let b = boxed()
        let inside = FloodFill.region(in: b.rgba, width: b.w, height: b.h, seed: (4, 4), tolerance: 10)
        XCTAssertEqual(count(inside), 9, "the 3×3 hole")
        XCTAssertTrue(inside[4 * b.w + 4])
        XCTAssertFalse(inside[2 * b.w + 2], "outline isn't filled")

        let outside = FloodFill.region(in: b.rgba, width: b.w, height: b.h, seed: (0, 0), tolerance: 10)
        XCTAssertEqual(count(outside), 81 - 25, "everything around the box")
    }

    func testToleranceLetsSimilarColoursThrough() {
        var b = boxed()
        b.rgba[(2 * b.w + 4) * 4 + 3] = 30          // a faint gap in the top edge
        let strict = FloodFill.region(in: b.rgba, width: b.w, height: b.h, seed: (4, 4), tolerance: 10)
        let loose = FloodFill.region(in: b.rgba, width: b.w, height: b.h, seed: (4, 4), tolerance: 40)
        XCTAssertEqual(count(strict), 9)
        XCTAssertGreaterThan(count(loose), 9, "leaks through the faint pixel")
    }

    func testSeedOutsideOrBadBufferGivesNothing() {
        let b = boxed()
        XCTAssertTrue(FloodFill.region(in: b.rgba, width: b.w, height: b.h, seed: (-1, 0), tolerance: 0).isEmpty)
        XCTAssertTrue(FloodFill.region(in: [0, 0], width: b.w, height: b.h, seed: (0, 0), tolerance: 0).isEmpty)
    }

    func testGrowIsASquareOfTheRadius() {
        var m = [Bool](repeating: false, count: 49)
        m[3 * 7 + 3] = true
        let grown = FloodFill.grow(m, width: 7, height: 7, by: 2)
        XCTAssertEqual(count(grown), 25)
        XCTAssertTrue(grown[1 * 7 + 1] && grown[5 * 7 + 5])
        XCTAssertFalse(grown[0])
        XCTAssertEqual(FloodFill.grow(m, width: 7, height: 7, by: 0), m)
    }

    func testPaintAndPickRoundTrip() {
        var px = [UInt8](repeating: 0, count: 4 * 4)
        FloodFill.paint([false, true, false, false], color: SIMD3(1, 0.5, 0), into: &px)
        XCTAssertEqual(Array(px[4..<8]), [255, 128, 0, 255])
        XCTAssertNil(FloodFill.color(in: px, width: 4, height: 1, at: (0, 0)), "transparent picks nothing")
        let c = FloodFill.color(in: px, width: 4, height: 1, at: (1, 0))
        XCTAssertEqual(c?.x ?? 0, 1, accuracy: 0.01)
        XCTAssertEqual(c?.y ?? 0, 0.5, accuracy: 0.01)

        // Half-transparent premultiplied red still reads as pure red.
        let half: [UInt8] = [128, 0, 0, 128]
        XCTAssertEqual(FloodFill.color(in: half, width: 1, height: 1, at: (0, 0))?.x ?? 0, 1, accuracy: 0.01)
    }
}

/// Fill and eyedropper through the editor: line on one layer, fill on another, undo.
@MainActor
final class EditorStateFillTests: XCTestCase {

    private func makeState() throws -> EditorState {
        guard let device = MTLCreateSystemDefaultDevice(),
              let state = EditorState(device: device, screenFormat: .bgra8Unorm) else {
            throw XCTSkip("Metal unavailable in this environment")
        }
        return state
    }

    private func alpha(_ state: EditorState, layer: String, x: Int, y: Int) -> UInt8 {
        guard let t = state.store.existingTexture(clip: state.clip.id, frame: state.currentFrame!.id, layer: layer),
              let px = state.renderer.readbackBytes(t) else { return 0 }
        return px[(y * state.renderer.canvasSize.x + x) * 4 + 3]
    }

    /// A ring on "line": stamps every few degrees, radius 100 around (256, 256).
    private func drawRing(_ state: EditorState) throws {
        state.layerIndex = 1
        let target = try XCTUnwrap(state.beginStroke())
        let stamps = stride(from: 0.0, to: 2 * Double.pi, by: 0.02).map { a in
            CanvasRenderer.Stamp(position: SIMD2(Float(256 + 100 * cos(a)), Float(256 + 100 * sin(a))), radius: 6, alpha: 1)
        }
        state.renderer.paint(stamps, into: target, color: SIMD4(0, 0, 0, 1), tool: .brush)
        state.strokeEnded()
    }

    func testFillOnColourLayerIsBoundedByTheLineLayer() throws {
        let state = try makeState()
        try drawRing(state)
        state.layerIndex = 0                        // "color"
        state.setColor(SIMD4(1, 0, 0, 1))
        state.tool = .fill
        state.fill(at: SIMD2(256, 256))

        XCTAssertEqual(alpha(state, layer: "color", x: 256, y: 256), 255, "inside the ring")
        XCTAssertEqual(alpha(state, layer: "color", x: 20, y: 20), 0, "outside stays empty")
        let overlap = (85...105).contains { dx in
            alpha(state, layer: "color", x: 256 + dx, y: 256) == 255 && alpha(state, layer: "line", x: 256 + dx, y: 256) > 0
        }
        XCTAssertTrue(overlap, "the fill tucks under the line's anti-aliased inner edge, no halo")
        XCTAssertEqual(alpha(state, layer: "color", x: 256 + 104, y: 256), 0, "but doesn't cross the line")
        XCTAssertEqual(state.tool, .fill, "picking a colour while filling keeps the bucket")

        state.undo()
        XCTAssertEqual(alpha(state, layer: "color", x: 256, y: 256), 0)
        XCTAssertGreaterThan(alpha(state, layer: "line", x: 356, y: 256), 200, "the line is untouched")
    }

    func testFillRespectsLockAndCanvasBounds() throws {
        let state = try makeState()
        state.toggleLayerLock(1)
        state.fill(at: SIMD2(10, 10))
        XCTAssertNil(state.store.existingTexture(clip: "idle", frame: "000", layer: "line"))
        state.toggleLayerLock(1)
        state.fill(at: SIMD2(-5, 10))
        XCTAssertNil(state.store.existingTexture(clip: "idle", frame: "000", layer: "line"))
    }

    func testEyedropperPicksAndHandsTheToolBack() throws {
        let state = try makeState()
        let target = try XCTUnwrap(state.beginStroke())
        state.renderer.paint([.init(position: SIMD2(100, 100), radius: 20, alpha: 1)],
                             into: target, color: SIMD4(0, 0.5, 1, 1), tool: .brush)
        state.strokeEnded()

        state.tool = .fill
        state.tool = .eyedropper
        XCTAssertFalse(state.pickColor(at: SIMD2(400, 400)), "empty canvas")
        XCTAssertEqual(state.color, SIMD4(0, 0, 0, 1))
        XCTAssertEqual(state.tool, .fill)

        state.tool = .eyedropper
        XCTAssertTrue(state.pickColor(at: SIMD2(100, 100)))
        XCTAssertEqual(state.color.y, 0.5, accuracy: 0.01)
        XCTAssertEqual(state.color.z, 1, accuracy: 0.01)
        XCTAssertEqual(state.tool, .fill, "back to what you had")
    }
}
