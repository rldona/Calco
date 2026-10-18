import XCTest
import Metal
@testable import Calco

@MainActor
final class EditorStateClipTests: XCTestCase {

    private func makeState() throws -> EditorState {
        guard let device = MTLCreateSystemDefaultDevice(),
              let state = EditorState(device: device, screenFormat: .bgra8Unorm) else {
            throw XCTSkip("Metal unavailable in this environment")
        }
        return state
    }

    func testClipIDsAreFolderSafeAndUnique() {
        XCTAssertEqual(EditorState.clipID(for: "Run Fast!", existing: []), "run-fast")
        XCTAssertEqual(EditorState.clipID(for: "  Ídle  ", existing: []), "ídle")
        XCTAssertEqual(EditorState.clipID(for: "###", existing: []), "clip")
        XCTAssertEqual(EditorState.clipID(for: "Idle", existing: ["idle"]), "idle-2")
        XCTAssertEqual(EditorState.clipID(for: "Idle", existing: ["idle", "idle-2"]), "idle-3")
    }

    func testAddSelectRenameDeleteClip() throws {
        let state = try makeState()
        XCTAssertEqual(state.project.clips.count, 1)
        state.addFrame()  // idle has 2 frames: 000, 001

        state.addClip(name: "Run")
        XCTAssertEqual(state.project.clips.map(\.id), ["idle", "run"])
        XCTAssertEqual(state.clipIndex, 1)
        XCTAssertEqual(state.clip.layers, state.project.clips[0].layers, "new clip copies the layer setup")
        XCTAssertEqual(state.frames.map(\.id), ["002"], "frame ids stay unique across clips")
        XCTAssertEqual(state.frameIndex, 0)
        XCTAssertTrue(state.isDirty)

        state.renameClip("Run cycle")
        XCTAssertEqual(state.clip.name, "Run cycle")
        XCTAssertEqual(state.clip.id, "run", "renaming keeps the folder id")

        state.selectClip(0)
        XCTAssertEqual(state.frames.count, 2)
        state.frameIndex = 1
        state.selectClip(1)
        XCTAssertEqual(state.frameIndex, 0, "switching clips resets the frame")

        state.deleteClip()
        XCTAssertEqual(state.project.clips.map(\.id), ["idle"])
        XCTAssertEqual(state.clipIndex, 0)
        state.deleteClip()
        XCTAssertEqual(state.project.clips.count, 1, "the last clip can't be deleted")
    }

    func testPivotIsClamped() throws {
        let state = try makeState()
        state.setPivot(Pivot(x: 1.7, y: -0.2))
        XCTAssertEqual(state.clip.pivot, Pivot(x: 1, y: 0))
        state.setPivot(Pivot(x: 0.25, y: 0.5))
        XCTAssertEqual(state.clip.pivot, Pivot(x: 0.25, y: 0.5))
    }

    func testClipFPSOverrideAndLoop() throws {
        let state = try makeState()
        XCTAssertEqual(state.clipFPS, 12)
        state.setClipFPS(24)
        XCTAssertEqual(state.clip.fps, 24)
        XCTAssertEqual(state.clipFPS, 24)
        state.setClipFPS(nil)
        XCTAssertNil(state.clip.fps)
        XCTAssertEqual(state.clipFPS, 12)
        XCTAssertTrue(state.clip.loop)
        state.toggleLoop()
        XCTAssertFalse(state.clip.loop)
    }

    func testTwoClipsSurviveSaveAndOpen() throws {
        let state = try makeState()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("EditorStateClipTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Hero.calco", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        state.addClip(name: "Run")
        state.setPivot(Pivot(x: 0.5, y: 0.1))
        state.setClipFPS(24)
        let target = try XCTUnwrap(state.paintTarget)
        state.renderer.paint([.init(position: SIMD2<Float>(50, 50), radius: 8, alpha: 1)],
                             into: target, color: SIMD4<Float>(0, 0, 0, 1), tool: .brush)
        state.strokeEnded()
        state.save(to: url)
        XCTAssertNil(state.lastError)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathComponent("clips/run/001/line.png").path))

        let other = try makeState()
        other.open(url)
        XCTAssertEqual(other.project, state.project)
        other.selectClip(1)
        XCTAssertEqual(other.clip.pivot, Pivot(x: 0.5, y: 0.1))
        XCTAssertEqual(other.clipFPS, 24)
        XCTAssertNotNil(other.store.image(clip: "run", frame: "001", layer: "line"))
    }
}
