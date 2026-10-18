import XCTest
import Metal
@testable import Calco

/// The state side of the keyboard shortcuts in CalcoCommands.
@MainActor
final class EditorStateKeyboardTests: XCTestCase {

    private func makeState() throws -> EditorState {
        guard let device = MTLCreateSystemDefaultDevice(),
              let state = EditorState(device: device, screenFormat: .bgra8Unorm) else {
            throw XCTSkip("Metal unavailable in this environment")
        }
        return state
    }

    func testFrameAndLayerSteppingStopsAtTheEnds() throws {
        let state = try makeState()
        state.addFrame(); state.addFrame()      // 3 frames, current = last
        state.stepFrame(1)
        XCTAssertEqual(state.frameIndex, 2)
        state.stepFrame(-1); state.stepFrame(-1); state.stepFrame(-1)
        XCTAssertEqual(state.frameIndex, 0)

        XCTAssertEqual(state.layerIndex, 1)     // "line", the top layer
        state.stepLayer(1)
        XCTAssertEqual(state.layerIndex, 1)
        state.stepLayer(-1)
        XCTAssertEqual(state.currentLayer?.id, "color")
    }

    func testHoldStepsNeverGoBelowOne() throws {
        let state = try makeState()
        state.stepHold(1); state.stepHold(1)
        XCTAssertEqual(state.currentFrame?.hold, 3)
        state.stepHold(-5)
        XCTAssertEqual(state.currentFrame?.hold, 1)
    }

    func testNewLayerFromKeyboardGetsAFreeName() throws {
        let state = try makeState()
        state.addLayerWithDefaultName()
        XCTAssertEqual(state.currentLayer?.name, "Layer 3")
        state.addLayerWithDefaultName()
        XCTAssertEqual(state.currentLayer?.name, "Layer 4")
        XCTAssertEqual(Set(state.layers.map(\.id)).count, state.layers.count, "ids stay unique")
    }

    func testCentredZoomKeepsTheViewCentreOnTheSameCanvasPixel() {
        let canvas = SIMD2<Int>(512, 512)
        let view = CGSize(width: 800, height: 1000)
        let centre = CGPoint(x: 400, y: 500)
        var t = CanvasTransform()
        t.pan(by: CGSize(width: 60, height: -30))
        let before = centre.applying(t.viewToCanvas(canvas: canvas, viewSize: view))
        t.zoom(by: 1.25)
        let after = centre.applying(t.viewToCanvas(canvas: canvas, viewSize: view))
        XCTAssertEqual(before.x, after.x, accuracy: 0.001)
        XCTAssertEqual(before.y, after.y, accuracy: 0.001)
        XCTAssertEqual(t.scale, 1.25, accuracy: 0.0001)
    }
}
