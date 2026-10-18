import XCTest
import Metal
@testable import Calco

/// Draw in front / behind / inside, and layers masked to the one below.
@MainActor
final class PaintModeTests: XCTestCase {

    private func makeState() throws -> EditorState {
        guard let device = MTLCreateSystemDefaultDevice(),
              let state = EditorState(device: device, screenFormat: .bgra8Unorm) else {
            throw XCTSkip("Metal unavailable in this environment")
        }
        return state
    }

    private let black = SIMD4<Float>(0, 0, 0, 1), red = SIMD4<Float>(1, 0, 0, 1)

    private func stamp(_ state: EditorState, at p: SIMD2<Float>, radius: Float, color: SIMD4<Float>,
                       mode: CanvasRenderer.PaintMode = .front) throws {
        let target = try XCTUnwrap(state.beginStroke())
        state.renderer.paint([.init(position: p, radius: radius, alpha: 1)], into: target, color: color,
                             tool: .brush, hard: true, mode: mode)
        state.strokeEnded()
    }

    /// Premultiplied RGBA of the current layer's drawing at (x, y).
    private func pixel(_ state: EditorState, _ x: Int, _ y: Int) throws -> [UInt8] {
        let t = try XCTUnwrap(state.paintTarget)
        let b = try XCTUnwrap(state.renderer.readbackBytes(t))
        let i = (y * state.renderer.canvasSize.x + x) * 4
        return Array(b[i..<(i + 4)])
    }

    /// What frame 0 shows at (x, y), every visible layer flattened (nothing visible is transparent).
    private func shown(_ state: EditorState, _ x: Int, _ y: Int) throws -> [UInt8] {
        guard let img = state.flattenedImage(clip: state.clip, frameID: state.frames[0].id) else { return [0, 0, 0, 0] }
        var px = [UInt8](repeating: 0, count: img.width * img.height * 4)
        let ctx = CGContext(data: &px, width: img.width, height: img.height, bitsPerComponent: 8,
                            bytesPerRow: img.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        let i = (y * img.width + x) * 4
        return Array(px[i..<(i + 4)])
    }

    func testInsideOnlyRecoloursWhatIsDrawn() throws {
        let state = try makeState()
        try stamp(state, at: SIMD2(20, 20), radius: 6, color: black)
        try stamp(state, at: SIMD2(20, 20), radius: 30, color: red, mode: .inside)
        XCTAssertEqual(try pixel(state, 20, 20), [255, 0, 0, 255], "the dot turned red")
        XCTAssertEqual(try pixel(state, 30, 20)[3], 0, "nothing new outside the dot")
    }

    func testBehindKeepsWhatIsDrawnOnTop() throws {
        let state = try makeState()
        try stamp(state, at: SIMD2(20, 20), radius: 6, color: black)
        try stamp(state, at: SIMD2(20, 20), radius: 30, color: red, mode: .behind)
        XCTAssertEqual(try pixel(state, 20, 20), [0, 0, 0, 255], "the line stays black")
        XCTAssertEqual(try pixel(state, 30, 20), [255, 0, 0, 255], "red fills around it")
    }

    func testFillModes() {
        var rgba: [UInt8] = [0, 0, 0, 255,   0, 0, 0, 0,   0, 0, 0, 128]
        let all = [true, true, true]
        var inside = rgba
        FloodFill.paint(all, color: SIMD3(1, 0, 0), into: &inside, mode: .inside)
        XCTAssertEqual(inside, [255, 0, 0, 255,   0, 0, 0, 0,   128, 0, 0, 128])
        FloodFill.paint(all, color: SIMD3(1, 0, 0), into: &rgba, mode: .behind)
        XCTAssertEqual(rgba, [0, 0, 0, 255,   255, 0, 0, 255,   127, 0, 0, 255])
    }

    func testMaskedLayerOnlyShowsWhereTheLayerBelowHasPaint() throws {
        let state = try makeState()
        state.layerIndex = 0                                   // colour: a dot
        try stamp(state, at: SIMD2(20, 20), radius: 6, color: black)
        state.layerIndex = 1                                   // line: a big red blot over it
        try stamp(state, at: SIMD2(20, 20), radius: 40, color: red)
        XCTAssertEqual(try shown(state, 32, 20)[3], 255, "unmasked, the blot shows everywhere")

        state.toggleLayerMask(1)
        XCTAssertTrue(state.layers[1].maskBelow)
        XCTAssertEqual(try shown(state, 20, 20), [255, 0, 0, 255], "inside the dot: the masked layer")
        XCTAssertEqual(try shown(state, 32, 20)[3], 0, "outside the dot: nothing")

        state.toggleLayerVisibility(0)
        XCTAssertEqual(try shown(state, 20, 20)[3], 0, "its base hidden, the masked layer goes too")
        state.undo(); state.undo()
        XCTAssertFalse(state.layers[1].maskBelow)
    }

    func testTheBottomLayerCannotBeMasked() throws {
        let state = try makeState()
        state.toggleLayerMask(0)
        XCTAssertFalse(state.layers[0].maskBelow)
    }

    func testMaskIsWrittenOnlyWhenOnAndOldLayersLoad() throws {
        XCTAssertFalse(String(data: try JSONEncoder().encode(Layer(id: "a", name: "A")), encoding: .utf8)!.contains("maskBelow"))
        let round = try JSONDecoder().decode(Layer.self, from: JSONEncoder().encode(Layer(id: "a", name: "A", maskBelow: true)))
        XCTAssertTrue(round.maskBelow)
        let old = #"{"id":"line","name":"Line","opacity":1,"visible":true,"locked":false}"#
        XCTAssertFalse(try JSONDecoder().decode(Layer.self, from: Data(old.utf8)).maskBelow)
    }
}
