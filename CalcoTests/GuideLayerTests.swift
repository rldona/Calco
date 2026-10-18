import XCTest
import Metal
import CoreGraphics
@testable import Calco

/// Images imported as guide layers: to draw over, never exported.
@MainActor
final class GuideLayerTests: XCTestCase {

    private func makeState() throws -> EditorState {
        guard let device = MTLCreateSystemDefaultDevice(),
              let state = EditorState(device: device, screenFormat: .bgra8Unorm) else {
            throw XCTSkip("Metal unavailable in this environment")
        }
        AppLanguage.apply(.english, save: false)
        return state
    }

    /// A solid image `w` x `h`.
    private func image(_ w: Int, _ h: Int, red: CGFloat = 1) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: red, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()!
    }

    private func alpha(_ img: CGImage?, _ x: Int, _ y: Int) -> UInt8 {
        guard let img else { return 0 }
        var px = [UInt8](repeating: 0, count: img.width * img.height * 4)
        let ctx = CGContext(data: &px, width: img.width, height: img.height, bitsPerComponent: 8,
                            bytesPerRow: img.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        return px[(y * img.width + x) * 4 + 3]
    }

    func testFittingKeepsTheAspectAndCentres() {
        let px = EditorState.fitted(image(4, 2), width: 8, height: 8)
        let a = { (x: Int, y: Int) in px[(y * 8 + x) * 4 + 3] }
        XCTAssertEqual(a(0, 1), 0, "letterboxed above")
        XCTAssertEqual(a(0, 2), 255)
        XCTAssertEqual(a(7, 5), 255)
        XCTAssertEqual(a(7, 6), 0, "and below")
    }

    func testImportAddsALockedFadedGuideUnderEverythingForTheWholeClip() throws {
        let state = try makeState()
        state.addDrawing(); state.addDrawing()               // three frames
        state.layerIndex = 1                                  // Line
        state.importImageLayer(image(64, 64), name: "sketch.png")

        let guide = state.layers[0]
        XCTAssertEqual(guide.name, "sketch.png")
        XCTAssertTrue(guide.guide)
        XCTAssertTrue(guide.locked)
        XCTAssertEqual(guide.opacity, 0.4)
        XCTAssertEqual(state.currentLayer?.name, "Line", "you keep drawing where you were")
        XCTAssertTrue((1..<3).allSatisfy { state.clip.isHeld(layer: guide.id, at: $0) })
        XCTAssertNotNil(state.store.existingTexture(clip: state.clip.id, frame: state.frames[0].id, layer: guide.id))

        state.undo()
        XCTAssertFalse(state.layers.contains { $0.guide })
        XCTAssertEqual(state.currentLayer?.name, "Line")
    }

    func testDefaultNameIsReference() throws {
        let state = try makeState()
        state.importImageLayer(image(8, 8))
        state.importImageLayer(image(8, 8))
        XCTAssertEqual(state.layers.prefix(2).map(\.name).sorted(), ["Reference", "Reference 2"])
    }

    func testGuidesAreLeftOutOfExportsButNotOutOfTheEditor() throws {
        let state = try makeState()
        state.importImageLayer(image(64, 64))
        XCTAssertEqual(alpha(state.flattenedImage(clip: state.clip, frameID: state.frames[0].id), 20, 20), 0,
                       "nothing but the guide: the exported frame is empty")
        XCTAssertGreaterThan(state.visibleLayers().count, 0, "the editor still shows it")

        state.toggleLayerGuide(0)
        XCTAssertFalse(state.layers[0].guide)
        XCTAssertGreaterThan(alpha(state.flattenedImage(clip: state.clip, frameID: state.frames[0].id), 20, 20), 0,
                             "made part of the sprite, it exports")
    }

    func testTheFillDoesntUseTheGuideAsAnOutline() throws {
        let state = try makeState()
        // A guide with a hole in the middle: as an outline it would stop the fill at its edges.
        let ctx = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        ctx.clear(CGRect(x: 16, y: 16, width: 32, height: 32))
        state.importImageLayer(ctx.makeImage()!)
        state.fillGaps = .off
        let w = state.renderer.canvasSize.x
        state.fill(at: SIMD2(Float(w) / 2, Float(w) / 2))
        let target = try XCTUnwrap(state.paintTarget)
        let px = try XCTUnwrap(state.renderer.readbackBytes(target))
        XCTAssertEqual(px[(2 * w + 2) * 4 + 3], 255, "the paint reached the corner, past the guide's edge")
    }

    func testAHiddenGuideIsNotWarnedAbout() {
        var p = Project(name: "P", canvas: CanvasSize(width: 8, height: 8))
        p.clips = [Clip(id: "c", name: "C", layers: [Layer(id: "ref", name: "Ref", visible: false, guide: true),
                                                     Layer(id: "line", name: "Line")],
                        frames: [Frame(id: "0")])]
        let issues = ExportChecks.run(project: p, clips: nil, frameImage: { _, _ in nil }, hiddenDrawing: { _, _ in true })
        XCTAssertFalse(issues.contains { $0.kind == .hiddenLayer })
    }

    func testGuideIsWrittenOnlyWhenOn() throws {
        XCTAssertFalse(String(data: try JSONEncoder().encode(Layer(id: "a", name: "A")), encoding: .utf8)!.contains("guide"))
        let back = try JSONDecoder().decode(Layer.self, from: JSONEncoder().encode(Layer(id: "a", name: "A", guide: true)))
        XCTAssertTrue(back.guide)
    }
}
