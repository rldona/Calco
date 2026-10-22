import XCTest
import Metal
@testable import Calco

/// Motion tweens: the poses in between, and painting them onto the frames after the start.
final class TweenMathTests: XCTestCase {

    private func end() -> FloatingSelection {
        var s = FloatingSelection(key: LayerKey(clip: "c", frame: "f", layer: "l"), lifted: [], outline: [],
                                  bounds: CGRect(x: 0, y: 0, width: 10, height: 10), anchor: CGPoint(x: 5, y: 5))
        s.offset = CGVector(dx: 100, dy: 0)
        s.scale = 3
        s.rotation = .pi
        return s
    }

    func testEasings() {
        for e in Tween.Easing.allCases {
            XCTAssertEqual(e.apply(0), 0, accuracy: 1e-6)
            XCTAssertEqual(e.apply(1), 1, accuracy: 1e-6)
        }
        XCTAssertEqual(Tween.Easing.linear.apply(0.25), 0.25, accuracy: 1e-6)
        XCTAssertLessThan(Tween.Easing.easeIn.apply(0.25), 0.25, "starts slow")
        XCTAssertGreaterThan(Tween.Easing.easeOut.apply(0.25), 0.25, "ends slow")
        XCTAssertEqual(Tween.Easing.easeInOut.apply(0.5), 0.5, accuracy: 1e-6)
    }

    func testPosesGoEvenlyToTheEndPose() {
        let p = Tween.pose(2, of: 4, to: end(), easing: .linear)
        XCTAssertEqual(p.offset.dx, 50, accuracy: 1e-6)
        XCTAssertEqual(p.scale, 2, accuracy: 1e-6)
        XCTAssertEqual(p.rotation, .pi / 2, accuracy: 1e-6)
        let last = Tween.pose(4, of: 4, to: end(), easing: .easeInOut)
        XCTAssertEqual(last.offset.dx, 100, accuracy: 1e-6)
        XCTAssertEqual(last.scale, 3, accuracy: 1e-6)
    }

    func testAnArcPassesItsBendHalfway() {
        let mid = Tween.path(CGVector(dx: 100, dy: 0), bend: CGVector(dx: 0, dy: -40), at: 0.5)
        XCTAssertEqual(mid.dx, 50, accuracy: 1e-6)
        XCTAssertEqual(mid.dy, -40, accuracy: 1e-6)
        let end = Tween.path(CGVector(dx: 100, dy: 0), bend: CGVector(dx: 0, dy: -40), at: 1)
        XCTAssertEqual(end.dx, 100, accuracy: 1e-6)
        XCTAssertEqual(end.dy, 0, accuracy: 1e-6)
    }
}

@MainActor
final class TweenEditorTests: XCTestCase {

    private func makeState() throws -> EditorState {
        guard let device = MTLCreateSystemDefaultDevice(),
              let state = EditorState(device: device, screenFormat: .bgra8Unorm) else {
            throw XCTSkip("Metal unavailable in this environment")
        }
        return state
    }

    private func alpha(_ state: EditorState, frame: Int, x: Int, y: Int) -> UInt8 {
        guard let l = state.currentLayer, let key = state.drawingKey(layer: l.id, at: frame),
              let t = state.store.existingTexture(clip: key.clip, frame: key.frame, layer: key.layer),
              let px = state.renderer.readbackBytes(t) else { return 0 }
        return px[(y * state.renderer.canvasSize.x + x) * 4 + 3]
    }

    private func dot(_ state: EditorState, at p: SIMD2<Float>) throws {
        let target = try XCTUnwrap(state.beginStroke())
        state.paintStroke([.init(position: p, radius: 6, alpha: 1)], into: target)
        state.strokeEnded()
    }

    func testATweenPaintsEachPoseAndUndoesInOne() throws {
        let state = try makeState()
        try dot(state, at: SIMD2(40, 100))
        state.beginTween()
        XCTAssertNotNil(state.tween)
        state.updateTween { $0.count = 4; $0.easing = .linear }
        state.updateSelection { $0.offset = CGVector(dx: 160, dy: 0) }
        XCTAssertEqual(state.tweenPoses.count, 3)
        state.applyTween()

        XCTAssertNil(state.tween)
        XCTAssertNil(state.selection)
        XCTAssertEqual(state.frames.count, 5, "four frames added after the one there was")
        XCTAssertGreaterThan(alpha(state, frame: 0, x: 40, y: 100), 200, "the start stays where it was")
        for k in 1...4 {
            XCTAssertGreaterThan(alpha(state, frame: k, x: 40 + 40 * k, y: 100), 200, "pose \(k) 40 px further")
            XCTAssertEqual(alpha(state, frame: k, x: 40, y: 100), 0)
        }
        state.undo()
        XCTAssertEqual(state.frames.count, 1)
        XCTAssertGreaterThan(alpha(state, frame: 0, x: 40, y: 100), 200)
    }

    func testOnlyThePickedStrokesMoveTheRestStays() throws {
        let state = try makeState()
        try dot(state, at: SIMD2(40, 100))                    // the arm
        try dot(state, at: SIMD2(40, 200))                    // the body
        state.tool = .move
        state.liftForMove(at: CGPoint(x: 40, y: 100))
        state.beginTween()
        state.updateTween { $0.count = 2; $0.easing = .linear }
        state.updateSelection { $0.offset = CGVector(dx: 0, dy: -60) }
        state.applyTween()
        XCTAssertGreaterThan(alpha(state, frame: 2, x: 40, y: 40), 200, "the arm went up")
        XCTAssertGreaterThan(alpha(state, frame: 2, x: 40, y: 200), 200, "the body is in every pose")
        XCTAssertGreaterThan(alpha(state, frame: 1, x: 40, y: 200), 200)
    }

    func testCancelLeavesEverythingAsItWas() throws {
        let state = try makeState()
        try dot(state, at: SIMD2(40, 100))
        state.beginTween()
        state.updateSelection { $0.offset = CGVector(dx: 100, dy: 0) }
        state.cancelTween()
        XCTAssertNil(state.selection)
        XCTAssertEqual(state.frames.count, 1)
        XCTAssertGreaterThan(alpha(state, frame: 0, x: 40, y: 100), 200)
        XCTAssertEqual(alpha(state, frame: 0, x: 140, y: 100), 0)
    }
}
