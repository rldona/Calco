import XCTest
import Metal
@testable import Calco

/// Pixel-art mode: every pixel fully on or off, for brush, eraser, lasso and the file.
@MainActor
final class PixelArtTests: XCTestCase {

    private func makeState() throws -> EditorState {
        guard let device = MTLCreateSystemDefaultDevice(),
              let state = EditorState(device: device, screenFormat: .bgra8Unorm) else {
            throw XCTSkip("Metal unavailable in this environment")
        }
        return state
    }

    /// Alpha of every pixel of the current layer's drawing after one stamp.
    private func alphas(_ state: EditorState, stamp: CanvasRenderer.Stamp, hard: Bool) throws -> [UInt8] {
        let target = try XCTUnwrap(state.beginStroke())
        state.renderer.paint([stamp], into: target, color: SIMD4(0, 0, 0, 1), tool: .brush, hard: hard)
        state.strokeEnded()
        let bytes = try XCTUnwrap(state.renderer.readbackBytes(target))
        return stride(from: 3, to: bytes.count, by: 4).map { bytes[$0] }
    }

    func testHardStampsHaveNoPartlyCoveredPixels() throws {
        let state = try makeState()
        let soft = try alphas(state, stamp: .init(position: SIMD2(20.3, 20.7), radius: 4, alpha: 1), hard: false)
        XCTAssertTrue(soft.contains { $0 > 0 && $0 < 255 }, "the normal brush has an antialiased edge")

        state.clearCurrentLayer()
        let hard = try alphas(state, stamp: .init(position: SIMD2(20.3, 20.7), radius: 4, alpha: 0.4), hard: true)
        XCTAssertTrue(hard.allSatisfy { $0 == 0 || $0 == 255 })
        XCTAssertGreaterThan(hard.filter { $0 == 255 }.count, 8, "a 4-pixel-wide disc")
    }

    func testSizeOnePaintsExactlyOnePixelAndSizeThreeA3x3Block() throws {
        let state = try makeState()
        let a = try alphas(state, stamp: .init(position: SIMD2(10.9, 5.2), radius: 1, alpha: 1), hard: true)
        let on = a.indices.filter { a[$0] == 255 }
        XCTAssertEqual(on.count, 1)
        let w = state.renderer.canvasSize.x
        XCTAssertEqual(on.first.map { [$0 % w, $0 / w] }, [10, 5], "the pixel under the pen")

        state.clearCurrentLayer()
        let b = try alphas(state, stamp: .init(position: SIMD2(10.9, 5.2), radius: 3, alpha: 1), hard: true)
        let block = b.indices.filter { b[$0] == 255 }.map { [$0 % w, $0 / w] }
        XCTAssertEqual(Set(block.map { $0[0] }), [9, 10, 11])
        XCTAssertEqual(Set(block.map { $0[1] }), [4, 5, 6])
        XCTAssertEqual(block.count, 9)
    }

    func testHardLassoMaskIsAllOrNothing() {
        let square = [CGPoint(x: 2.5, y: 2.5), CGPoint(x: 9.3, y: 2.5), CGPoint(x: 9.3, y: 8.7), CGPoint(x: 2.5, y: 8.7)]
        XCTAssertTrue(SelectionPixels.rasterize(square, width: 12, height: 12).contains { $0 > 0 && $0 < 255 })
        XCTAssertTrue(SelectionPixels.rasterize(square, width: 12, height: 12, hard: true).allSatisfy { $0 == 0 || $0 == 255 })
    }

    func testPixelArtIsSavedOnlyWhenOnAndOldFilesLoad() throws {
        var p = Project(name: "P", canvas: CanvasSize(width: 8, height: 8))
        XCTAssertFalse(String(data: try JSONEncoder().encode(p), encoding: .utf8)!.contains("pixelArt"))
        p.pixelArt = true
        XCTAssertTrue(try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(p)).pixelArt)
        let old = #"{"version":2,"name":"Old","canvas":{"width":8,"height":8},"fps":12,"clips":[],"references":[]}"#
        XCTAssertFalse(try JSONDecoder().decode(Project.self, from: Data(old.utf8)).pixelArt)
    }

    func testTurningPixelArtOnIsUndoable() throws {
        let state = try makeState()
        state.setPixelArt(true)
        XCTAssertTrue(state.project.pixelArt)
        XCTAssertTrue(state.isDirty)
        state.undo()
        XCTAssertFalse(state.project.pixelArt)
    }
}
