import XCTest
import Metal
@testable import Calco

/// Cycles: cells linked to an earlier drawing, so a walk repeats and stays one set of drawings.
@MainActor
final class CycleTests: XCTestCase {

    private func makeState() throws -> EditorState {
        guard let device = MTLCreateSystemDefaultDevice(),
              let state = EditorState(device: device, screenFormat: .bgra8Unorm) else {
            throw XCTSkip("Metal unavailable in this environment")
        }
        return state
    }

    private func dot(_ state: EditorState, x: Float = 20) throws {
        let target = try XCTUnwrap(state.beginStroke())
        state.renderer.paint([.init(position: SIMD2(x, 20), radius: 4, alpha: 1)], into: target,
                             color: SIMD4(0, 0, 0, 1), tool: .brush)
        state.strokeEnded()
    }

    private func texture(_ state: EditorState, layer: String, at i: Int) -> MTLTexture? {
        state.drawingKey(layer: layer, at: i).flatMap { state.store.existingTexture(clip: $0.clip, frame: $0.frame, layer: $0.layer) }
    }

    /// Colour drawn once at frame 0; line drawings at frames 0, 1, 2 (colour holds).
    private func walk(_ state: EditorState) throws {
        state.layerIndex = 0; try dot(state, x: 50)
        state.layerIndex = 1; try dot(state)
        state.addDrawing(); try dot(state, x: 25)
        state.addDrawing(); try dot(state, x: 30)
    }

    func testRepeatLinksTheLastDrawingsAfterThePlayhead() throws {
        let state = try makeState()
        try walk(state)
        state.setHold(2)                                       // the last pose is held for 2 ticks
        XCTAssertEqual(state.drawingsUpToPlayhead, 3)

        state.repeatDrawings(count: 3)
        XCTAssertEqual(state.frames.count, 6)
        XCTAssertEqual(state.frameIndex, 3, "lands on the first repeat")
        for k in 0..<3 {
            XCTAssertTrue(texture(state, layer: "line", at: 3 + k) === texture(state, layer: "line", at: k), "repeat \(k)")
        }
        XCTAssertEqual(state.frames[5].hold, 2, "timing repeats too")
        XCTAssertTrue((3..<6).allSatisfy { state.clip.isHeld(layer: "color", at: $0) }, "colour carries on")
    }

    func testDrawingOnARepeatChangesTheOriginal() throws {
        let state = try makeState()
        try walk(state)
        state.repeatDrawings(count: 3)
        state.frameIndex = 4
        let target = try XCTUnwrap(state.beginStroke())
        state.strokeEnded()
        XCTAssertTrue(target === texture(state, layer: "line", at: 1), "painting the repeat paints drawing 2")
    }

    func testDeletingARepeatKeepsTheOriginal() throws {
        let state = try makeState()
        try walk(state)
        state.repeatDrawings(count: 3)
        state.frameIndex = 4
        state.deleteDrawing()
        XCTAssertEqual(state.frames.count, 5, "that repeat's frame had nothing else of its own")
        XCTAssertNotNil(texture(state, layer: "line", at: 1), "drawing 2 is still there")
    }

    func testUnlinkMakesAnIndependentCopy() throws {
        let state = try makeState()
        try walk(state)
        state.repeatDrawings(count: 1)                         // repeats drawing 3 at frame 3
        XCTAssertTrue(state.currentCellIsLinked)
        state.releaseCurrentCell(copying: true)
        XCTAssertFalse(state.currentCellIsLinked)
        let copy = try XCTUnwrap(texture(state, layer: "line", at: 3))
        XCTAssertFalse(copy === texture(state, layer: "line", at: 2))
    }

    func testRemovingTheOriginalFrameKeepsTheRepeatLooking() throws {
        let state = try makeState()
        try walk(state)
        state.repeatDrawings(count: 3)
        state.frameIndex = 1
        state.deleteFrame()
        XCTAssertEqual(state.frames.count, 5)
        XCTAssertNotNil(texture(state, layer: "line", at: 3), "the repeat of the deleted frame got its own copy")
        XCTAssertFalse(state.clip.isLinked(layer: "line", at: 3))
    }

    func testSyncLayersRepeatsEveryLayer() throws {
        let state = try makeState()
        try walk(state)
        state.syncLayers = true
        state.repeatDrawings(count: 3)
        XCTAssertTrue(texture(state, layer: "color", at: 3) === texture(state, layer: "color", at: 0))
        XCTAssertTrue(state.clip.isLinked(layer: "color", at: 3), "linked, not held from frame 2")
    }

    func testLinksSaveWithoutTheirOwnFilesAndLoadBack() throws {
        let state = try makeState()
        try walk(state)
        state.repeatDrawings(count: 3)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Cycle-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Walk.calco", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        state.save(to: url)
        XCTAssertNil(state.lastError)
        let repeatFolder = url.appendingPathComponent("clips/\(state.clip.id)/\(state.frames[3].id)/line.png")
        XCTAssertFalse(FileManager.default.fileExists(atPath: repeatFolder.path))

        let other = try makeState()
        other.open(url)
        XCTAssertEqual(other.project.version, 3)
        XCTAssertEqual(other.frames[3].links["line"], other.frames[0].id)
        XCTAssertNotNil(texture(other, layer: "line", at: 3))
    }

    func testARepeatCarriesItsLabelIntoTheExport() throws {
        let state = try makeState()
        try walk(state)
        state.frameIndex = 0
        state.setCurrentDrawingLabel("step")
        state.frameIndex = 2
        state.repeatDrawings(count: 3)
        let sheet = SpriteSheet.build(project: state.project, options: .init(labels: true)) { _, _ in nil }
        XCTAssertEqual(sheet.cells.map(SpriteSheet.label), ["step", nil, nil, "step", nil, nil])
    }

    func testCircularLinksDontHang() {
        let c = Clip(id: "c", name: "C", layers: [Layer(id: "a", name: "A")],
                     frames: [Frame(id: "0", links: ["a": "1"]), Frame(id: "1", links: ["a": "0"])])
        XCTAssertEqual(c.sourceIndex(layer: "a", at: 0), 0)
    }
}
