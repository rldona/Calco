import XCTest
import Metal
@testable import Calco

/// Held cells: a layer showing an earlier frame's drawing instead of its own.
final class ClipHoldTests: XCTestCase {

    private func clip(_ frames: [Frame]) -> Clip {
        Clip(id: "c", name: "C", layers: [Layer(id: "bg", name: "BG"), Layer(id: "fg", name: "FG")], frames: frames)
    }

    func testSourceWalksBackOverHolds() {
        let c = clip([Frame(id: "0"), Frame(id: "1", held: ["bg"]), Frame(id: "2", held: ["bg", "fg"]), Frame(id: "3")])
        XCTAssertEqual((0..<4).map { c.sourceFrameID(layer: "bg", at: $0) }, ["0", "0", "0", "3"])
        XCTAssertEqual((0..<4).map { c.sourceFrameID(layer: "fg", at: $0) }, ["0", "1", "1", "3"])
        XCTAssertNil(c.sourceFrameID(layer: "bg", at: 9))
    }

    func testFirstFrameNeverHolds() {
        let c = clip([Frame(id: "0", held: ["bg"]), Frame(id: "1", held: ["bg"])])
        XCTAssertFalse(c.isHeld(layer: "bg", at: 0))
        XCTAssertEqual(c.sourceFrameID(layer: "bg", at: 1), "0")
    }

    func testRunsGroupHeldFrames() {
        let c = clip([Frame(id: "0"), Frame(id: "1", held: ["bg"]), Frame(id: "2", held: ["bg"]), Frame(id: "3")])
        XCTAssertEqual(c.runs(of: "bg").map { [$0.start, $0.count] }, [[0, 3], [3, 1]])
        XCTAssertEqual(c.runs(of: "fg").map(\.count), [1, 1, 1, 1])
    }

    func testFormatOneFilesDecodeWithNothingHeldAndEmptyHoldsAreNotWritten() throws {
        let v1 = #"{"id":"000","hold":2}"#.data(using: .utf8)!
        let f = try JSONDecoder().decode(Frame.self, from: v1)
        XCTAssertEqual(f, Frame(id: "000", hold: 2))
        let out = String(data: try JSONEncoder().encode(Frame(id: "a")), encoding: .utf8)!
        XCTAssertFalse(out.contains("held"))
        let round = try JSONDecoder().decode(Frame.self, from: JSONEncoder().encode(Frame(id: "b", held: ["bg"])))
        XCTAssertEqual(round.held, ["bg"])
    }

    func testHeldCellsHaveNoFile() {
        let p = Project(name: "P", canvas: CanvasSize(width: 8, height: 8),
                        clips: [clip([Frame(id: "0"), Frame(id: "1", held: ["bg"])])])
        XCTAssertEqual(ProjectDocument.layerKeys(of: p).map { "\($0.frame)/\($0.layer)" }, ["0/bg", "0/fg", "1/fg"])
    }
}

/// The exposure sheet through the editor.
@MainActor
final class EditorStateExposureTests: XCTestCase {

    private func makeState() throws -> EditorState {
        guard let device = MTLCreateSystemDefaultDevice(),
              let state = EditorState(device: device, screenFormat: .bgra8Unorm) else {
            throw XCTSkip("Metal unavailable in this environment")
        }
        return state
    }

    /// Alpha at (x, y) of what frame `index` shows (all visible layers flattened).
    private func shown(_ state: EditorState, frame index: Int, x: Int, y: Int) -> UInt8 {
        guard let img = state.flattenedImage(clip: state.clip, frameID: state.frames[index].id) else { return 0 }
        var px = [UInt8](repeating: 0, count: img.width * img.height * 4)
        let ctx = CGContext(data: &px, width: img.width, height: img.height, bitsPerComponent: 8,
                            bytesPerRow: img.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        return px[(y * img.width + x) * 4 + 3]     // bitmap memory is top-down, like canvas y
    }

    private func dot(_ state: EditorState, at p: SIMD2<Float>) throws {
        let target = try XCTUnwrap(state.beginStroke())
        state.renderer.paint([.init(position: p, radius: 10, alpha: 1)], into: target, color: SIMD4(0, 0, 0, 1), tool: .brush)
        state.strokeEnded()
    }

    /// Background on "color" (layer 0) at frame 0, then line work on "line" (layer 1).
    private func backgroundAndThreeFrames(_ state: EditorState) throws {
        state.layerIndex = 0
        try dot(state, at: SIMD2(50, 50))           // background mark
        state.layerIndex = 1
        state.addFrame(); state.addFrame()          // 000 001 002
    }

    func testNewFramesHoldTheOtherLayers() throws {
        let state = try makeState()
        try backgroundAndThreeFrames(state)
        XCTAssertEqual(state.frames.map(\.held), [[], ["color"], ["color"]])
        XCTAssertGreaterThan(shown(state, frame: 2, x: 50, y: 50), 200, "the background carries on")
        XCTAssertFalse(state.currentCellIsHeld, "the layer being drawn gets its own blank drawing")
    }

    func testPaintingAHeldCellEditsTheHeldDrawing() throws {
        let state = try makeState()
        try backgroundAndThreeFrames(state)
        state.layerIndex = 0                        // color, held at frame 2
        XCTAssertTrue(state.currentCellIsHeld)
        try dot(state, at: SIMD2(200, 200))
        for i in 0..<3 { XCTAssertGreaterThan(shown(state, frame: i, x: 200, y: 200), 200, "frame \(i)") }
        XCTAssertNil(state.store.existingTexture(clip: "idle", frame: "002", layer: "color"), "still a hold")
        state.undo()
        XCTAssertEqual(shown(state, frame: 0, x: 200, y: 200), 0)
    }

    func testHoldAndReleaseACell() throws {
        let state = try makeState()
        try dot(state, at: SIMD2(80, 80))           // line @ 000
        state.addFrame()                            // line own blank @ 001
        try dot(state, at: SIMD2(300, 300))         // line @ 001
        state.holdCurrentCell()
        XCTAssertTrue(state.currentCellIsHeld)
        XCTAssertGreaterThan(shown(state, frame: 1, x: 80, y: 80), 200, "shows frame 0's drawing")
        XCTAssertEqual(shown(state, frame: 1, x: 300, y: 300), 0)

        state.releaseCurrentCell(copying: true)
        XCTAssertFalse(state.currentCellIsHeld)
        XCTAssertGreaterThan(shown(state, frame: 1, x: 80, y: 80), 200, "a copy to keep working on")
        state.undo(); state.undo()
        XCTAssertGreaterThan(shown(state, frame: 1, x: 300, y: 300), 200, "undo brings the own drawing back")

        state.frameIndex = 0
        state.holdCurrentCell()
        XCTAssertFalse(state.currentCellIsHeld, "the first frame can't hold")
    }

    func testDeletingAFrameKeepsWhatLaterFramesShowed() throws {
        let state = try makeState()
        try backgroundAndThreeFrames(state)         // color owned by 000, held by 001 and 002
        state.frameIndex = 0
        state.deleteFrame()
        XCTAssertEqual(state.frames.map(\.id), ["001", "002"])
        XCTAssertEqual(state.frames.map(\.held), [[], ["color"]], "001 takes over the background, 002 keeps holding")
        XCTAssertGreaterThan(shown(state, frame: 0, x: 50, y: 50), 200)
        XCTAssertGreaterThan(shown(state, frame: 1, x: 50, y: 50), 200)
        state.undo()
        XCTAssertEqual(state.frames.map(\.id), ["000", "001", "002"])
        XCTAssertNil(state.store.existingTexture(clip: "idle", frame: "001", layer: "color"))
        XCTAssertGreaterThan(shown(state, frame: 2, x: 50, y: 50), 200)
    }

    func testMovingFramesKeepsEveryFramesPicture() throws {
        let state = try makeState()
        try backgroundAndThreeFrames(state)
        try dot(state, at: SIMD2(300, 100))         // line @ 002
        let before = (0..<3).map { i in [shown(state, frame: i, x: 50, y: 50), shown(state, frame: i, x: 300, y: 100)] }
        state.moveFrame(id: "002", to: 0)
        XCTAssertEqual(state.frames.map(\.id), ["002", "000", "001"])
        XCTAssertEqual(state.frames[0].held, [])
        let after = ["002", "000", "001"].map { id -> [UInt8] in
            let i = state.frames.firstIndex { $0.id == id }!
            return [shown(state, frame: i, x: 50, y: 50), shown(state, frame: i, x: 300, y: 100)]
        }
        XCTAssertEqual(after, [before[2], before[0], before[1]], "each frame looks exactly as before")
    }

    func testHoldsSurviveSaveAndOpenAndExportFlattened() throws {
        let state = try makeState()
        try backgroundAndThreeFrames(state)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Exposure-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Hero.calco", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        state.save(to: url)
        XCTAssertNil(state.lastError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.appendingPathComponent("clips/idle/001/color.png").path))

        let other = try makeState()
        other.open(url)
        XCTAssertEqual(other.project.version, Project.currentFormatVersion)
        XCTAssertEqual(other.frames.map(\.held), [[], ["color"], ["color"]])
        XCTAssertGreaterThan(shown(other, frame: 2, x: 50, y: 50), 200, "export and thumbnails see the hold")
    }

    func testDraggingADrawingsEdgeExtendsAndShrinksIt() throws {
        let state = try makeState()
        try dot(state, at: SIMD2(60, 60))           // line @ 000
        state.addFrame(); state.addFrame(); state.addFrame()
        try dot(state, at: SIMD2(300, 300))         // line @ 003
        // Drag frame 0's line out over three frames, as one gesture.
        state.setDrawingSpan(layer: "line", start: 0, count: 2)
        state.setDrawingSpan(layer: "line", start: 0, count: 4)
        state.endCoalescing()
        XCTAssertEqual(state.clip.runs(of: "line").map(\.count), [4])
        XCTAssertEqual(shown(state, frame: 3, x: 300, y: 300), 0, "covered drawing is replaced by the hold")
        XCTAssertGreaterThan(shown(state, frame: 3, x: 60, y: 60), 200)

        state.setDrawingSpan(layer: "line", start: 0, count: 2)
        state.endCoalescing()
        XCTAssertEqual(state.clip.runs(of: "line").map(\.count), [2, 1, 1], "frames it leaves get their own blank drawings")
        XCTAssertEqual(shown(state, frame: 2, x: 60, y: 60), 0)

        state.undo(); state.undo()
        XCTAssertEqual(state.clip.runs(of: "line").map(\.count), [1, 1, 1, 1], "each drag undoes in one step")
        XCTAssertGreaterThan(shown(state, frame: 3, x: 300, y: 300), 200)
    }

    func testSpanStaysInsideTheClipAndRespectsTheLock() throws {
        let state = try makeState()
        state.addFrame()
        state.setDrawingSpan(layer: "line", start: 0, count: 99)
        XCTAssertEqual(state.clip.runs(of: "line").map(\.count), [2])
        state.toggleLayerLock(1)
        state.setDrawingSpan(layer: "line", start: 0, count: 1)
        XCTAssertEqual(state.clip.runs(of: "line").map(\.count), [2])
    }

    func testLabelsFollowTheDrawingAndSurviveSaving() throws {
        let state = try makeState()
        try backgroundAndThreeFrames(state)
        state.layerIndex = 0
        state.frameIndex = 2                        // held cell: labels the held drawing
        state.setCurrentDrawingLabel("  room  ")
        XCTAssertEqual(state.frames[0].labels, ["color": "room"])
        XCTAssertEqual(state.drawingLabel(layer: "color", at: 1), "room")

        state.frameIndex = 0
        state.deleteFrame()                         // the drawing moves to 001, and its name with it
        XCTAssertEqual(state.drawingLabel(layer: "color", at: 0), "room")

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Labels-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("L.calco", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        state.save(to: url)
        let other = try makeState()
        other.open(url)
        XCTAssertEqual(other.drawingLabel(layer: "color", at: 1), "room")

        state.setCurrentDrawingLabel("")
        XCTAssertNil(state.drawingLabel(layer: "color", at: 0))
    }
}
