import XCTest
import Metal
@testable import Calco

@MainActor
final class EditorStateLayerTests: XCTestCase {

    private func makeState() throws -> EditorState {
        guard let device = MTLCreateSystemDefaultDevice(),
              let state = EditorState(device: device, screenFormat: .bgra8Unorm) else {
            throw XCTSkip("Metal unavailable in this environment")
        }
        return state
    }

    private func dot(_ state: EditorState) throws {
        let target = try XCTUnwrap(state.beginStroke())
        state.renderer.paint([.init(position: SIMD2<Float>(100, 200), radius: 10, alpha: 1)],
                             into: target, color: SIMD4<Float>(0, 0, 0, 1), tool: .brush)
        state.strokeEnded()
    }

    func testAddLayerGoesAboveCurrentWithAUniqueID() throws {
        let state = try makeState()
        XCTAssertEqual(state.layers.map(\.id), ["color", "line"])
        state.layerIndex = 0
        state.addLayer(name: "Line")
        XCTAssertEqual(state.layers.map(\.id), ["color", "line-2", "line"])
        XCTAssertEqual(state.currentLayer?.id, "line-2")
        state.addLayer(name: "   ")
        XCTAssertEqual(state.layers.count, 3, "blank names are ignored")
    }

    func testDeleteLayerTakesItsPixelsAndUndoBringsThemBack() throws {
        let state = try makeState()
        try dot(state)                              // on "line", frame 000
        state.addFrame()
        state.frameIndex = 0
        state.deleteLayer(1)
        XCTAssertEqual(state.layers.map(\.id), ["color"])
        XCTAssertEqual(state.layerIndex, 0)
        XCTAssertNil(state.store.raw(LayerKey(clip: "idle", frame: "000", layer: "line")))

        state.undo()
        XCTAssertEqual(state.layers.map(\.id), ["color", "line"])
        XCTAssertNotNil(state.store.image(clip: "idle", frame: "000", layer: "line"))

        state.deleteLayer(0)
        state.deleteLayer(0)
        XCTAssertEqual(state.layers.count, 1, "the last layer stays")
    }

    func testDeletingBelowKeepsTheCurrentLayer() throws {
        let state = try makeState()
        state.addLayer(name: "Shadow")              // color, line, shadow; current = shadow
        state.deleteLayer(0)
        XCTAssertEqual(state.currentLayer?.id, "shadow")
    }

    func testMoveLayerKeepsSelectionAndIsUndoable() throws {
        let state = try makeState()
        state.addLayer(name: "Sketch")              // color, line, sketch
        state.layerIndex = 0                        // color
        state.moveLayer(from: 2, to: 0)
        XCTAssertEqual(state.layers.map(\.id), ["sketch", "color", "line"])
        XCTAssertEqual(state.currentLayer?.id, "color")
        state.undo()
        XCTAssertEqual(state.layers.map(\.id), ["color", "line", "sketch"])
    }

    func testRenameKeepsTheFileID() throws {
        let state = try makeState()
        state.renameLayer(1, to: "Ink")
        XCTAssertEqual(state.layers[1].name, "Ink")
        XCTAssertEqual(state.layers[1].id, "line")
    }

    func testLockedLayerCantBePaintedOrCleared() throws {
        let state = try makeState()
        try dot(state)
        state.toggleLayerLock(1)
        XCTAssertNil(state.beginStroke())
        state.clearCurrentLayer()
        XCTAssertNotNil(state.store.image(clip: "idle", frame: "000", layer: "line"), "clear respects the lock")
        state.undo()
        XCTAssertFalse(state.layers[1].locked)
    }

    func testOpacityDragIsOneUndoStepAndClamped() throws {
        let state = try makeState()
        state.setLayerOpacity(1, 0.8)
        state.setLayerOpacity(1, 0.5)
        state.setLayerOpacity(1, -2)
        state.layerOpacityEditingEnded()
        XCTAssertEqual(state.layers[1].opacity, 0)
        state.undo()
        XCTAssertEqual(state.layers[1].opacity, 1)
        XCTAssertFalse(state.canUndo)
    }

    func testLayerChangesSurviveSaveAndOpen() throws {
        let state = try makeState()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("EditorStateLayerTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Hero.calco", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        state.addLayer(name: "Shadow")
        try dot(state)
        state.setLayerOpacity(2, 0.4)
        state.moveLayer(from: 2, to: 0)
        state.save(to: url)
        XCTAssertNil(state.lastError)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathComponent("clips/idle/000/shadow.png").path))

        let other = try makeState()
        other.open(url)
        XCTAssertEqual(other.layers.map(\.id), ["shadow", "color", "line"])
        XCTAssertEqual(other.layers[0].opacity, 0.4)
        XCTAssertNotNil(other.store.image(clip: "idle", frame: "000", layer: "shadow"))
    }
}
