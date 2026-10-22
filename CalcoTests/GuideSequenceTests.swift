import XCTest
import Metal
import CoreGraphics
@testable import Calco

/// Importing an image sequence as a guide, one image per frame (docs/specs/import-guide-sequence.md).
final class GuideSequencePlanTests: XCTestCase {

    func testEveryImageOnItsOwnFrameAddingFramesAsNeeded() {
        // Criterion 1: an empty clip (one blank frame) and 12 images.
        let p = GuideSequence.plan(count: 12, step: 1, start: 0, existing: 1, createMissing: true)
        XCTAssertEqual(p.images, Array(0..<12))
        XCTAssertEqual(p.frames, Array(0..<12))
        XCTAssertEqual(p.newFrames, 11)
        XCTAssertEqual(p.leftOut, 0)
    }

    func testEveryOtherImageIntoALongerClip() {
        // Criterion 2: 6 frames, 24 images, one in 2.
        let p = GuideSequence.plan(count: 24, step: 2, start: 0, existing: 6, createMissing: true)
        XCTAssertEqual(p.images, Array(stride(from: 0, to: 24, by: 2)))
        XCTAssertEqual(p.frames, Array(0..<12))
        XCTAssertEqual(p.newFrames, 6)
    }

    func testWithoutNewFramesOnlyWhatFits() {
        // Criterion 3: "6 of 12 fit".
        let p = GuideSequence.plan(count: 24, step: 2, start: 0, existing: 6, createMissing: false)
        XCTAssertEqual(p.images.count, 6)
        XCTAssertEqual(p.newFrames, 0)
        XCTAssertEqual(p.leftOut, 6)
        let late = GuideSequence.plan(count: 5, step: 1, start: 4, existing: 6, createMissing: false)
        XCTAssertEqual(late.frames, [4, 5], "from the playhead, to the end")
        XCTAssertEqual(GuideSequence.plan(count: 3, step: 1, start: 8, existing: 6, createMissing: false).images, [])
    }

    func testStartingAtThePlayhead() {
        let p = GuideSequence.plan(count: 4, step: 1, start: 3, existing: 5, createMissing: true)
        XCTAssertEqual(p.frames, [3, 4, 5, 6])
        XCTAssertEqual(p.newFrames, 2)
    }

    func testNaturalOrder() {
        // Criterion 7.
        XCTAssertEqual(GuideSequence.naturalOrder(["f10.png", "f2.png", "f1.png"]), ["f1.png", "f2.png", "f10.png"])
        XCTAssertEqual(GuideSequence.naturalOrder(["Frame_3.png", "frame_12.png", "frame_002.png"]),
                       ["frame_002.png", "Frame_3.png", "frame_12.png"])
    }

    func testTheThreeFits() {
        let canvas = CGSize(width: 256, height: 128)
        let tall = CGSize(width: 100, height: 200)
        XCTAssertEqual(GuideSequence.rect(for: tall, in: canvas, fit: .fit), CGRect(x: 96, y: 0, width: 64, height: 128))
        XCTAssertEqual(GuideSequence.rect(for: tall, in: canvas, fit: .fill), CGRect(x: 0, y: -192, width: 256, height: 512))
        XCTAssertEqual(GuideSequence.rect(for: tall, in: canvas, fit: .actual), CGRect(x: 78, y: -36, width: 100, height: 200))
        XCTAssertEqual(GuideSequence.rect(for: tall, in: canvas, fit: .fit, offset: CGPoint(x: 5, y: -3)),
                       CGRect(x: 101, y: -3, width: 64, height: 128))
    }

    func testFittingABigImageScalesItDownCentredAndActualSizeCropsIt() {
        // Criterion 4, on a small canvas: a 1024 square with a 64 px black bar along its top.
        let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 960, width: 1024, height: 64))       // y-up: the top
        let image = ctx.makeImage()!
        let canvas = CGSize(width: 256, height: 256)
        let fit = GuideSequence.rasterize(image, into: GuideSequence.rect(for: CGSize(width: 1024, height: 1024), in: canvas, fit: .fit),
                                          width: 256, height: 256)
        // Red or black, give or take the colour space.
        func px(_ b: [UInt8], _ x: Int, _ y: Int) -> String {
            let i = (y * 256 + x) * 4
            guard b[i + 3] > 250 else { return "clear" }
            return b[i] > 200 ? "red" : b[i] < 40 ? "black" : "other"
        }
        XCTAssertEqual(fit.count, 256 * 256 * 4)
        XCTAssertEqual(px(fit, 128, 2), "black", "the bar, scaled to 16 px, at the very top")
        XCTAssertEqual(px(fit, 128, 20), "red")
        XCTAssertEqual(px(fit, 0, 255), "red", "the whole height, corner to corner")
        let actual = GuideSequence.rasterize(image, into: GuideSequence.rect(for: CGSize(width: 1024, height: 1024), in: canvas, fit: .actual),
                                             width: 256, height: 256)
        XCTAssertEqual(px(actual, 128, 2), "red", "1:1 shows the middle: the bar is cut off")
    }

    func testOptionsAreRemembered() {
        let defaults = UserDefaults(suiteName: "GuideSequenceTests")!
        defaults.removePersistentDomain(forName: "GuideSequenceTests")
        XCTAssertEqual(GuideSequence.Options.load(defaults), GuideSequence.Options())
        var o = GuideSequence.Options()
        o.step = 3; o.hold = 2; o.fit = .fill; o.opacity = 0.6; o.tint = .blue
        o.save(defaults)
        XCTAssertEqual(GuideSequence.Options.load(defaults), o)
    }

    func testTintIsOptionalInTheFile() throws {
        // Criterion 9: an old file without tint opens; a tint survives a round trip.
        let old = try JSONDecoder().decode(Layer.self, from: Data(#"{"id":"g","name":"Guide","guide":true}"#.utf8))
        XCTAssertNil(old.tint)
        var l = old
        l.tint = "#3E7BFA"
        let back = try JSONDecoder().decode(Layer.self, from: JSONEncoder().encode(l))
        XCTAssertEqual(back.tint, "#3E7BFA")
        XCTAssertEqual(back.guideTint, SIMD3(0x3E, 0x7B, 0xFA) / 255)
        XCTAssertFalse(String(data: try JSONEncoder().encode(old), encoding: .utf8)!.contains("tint"), "absent stays absent")
        var drawing = back; drawing.guide = false
        XCTAssertNil(drawing.guideTint, "only guides show it")
    }
}

@MainActor
final class GuideSequenceImportTests: XCTestCase {

    private func makeState() throws -> EditorState {
        guard let device = MTLCreateSystemDefaultDevice(),
              let state = EditorState(device: device, screenFormat: .bgra8Unorm) else {
            throw XCTSkip("Metal unavailable in this environment")
        }
        AppLanguage.apply(.english, save: false)
        return state
    }

    /// Canvas-size pixels with one opaque pixel, so frames can be told apart.
    private func pixels(_ state: EditorState, mark: Int) -> [UInt8] {
        var px = [UInt8](repeating: 0, count: state.renderer.canvasSize.x * state.renderer.canvasSize.y * 4)
        for c in 0..<4 { px[mark * 4 + c] = 255 }
        return px
    }

    private func mark(_ state: EditorState, layer: String, frame: Int) -> Int? {
        guard let t = state.store.existingTexture(clip: state.clip.id, frame: state.frames[frame].id, layer: layer),
              let px = state.renderer.readbackBytes(t) else { return nil }
        return stride(from: 3, to: px.count, by: 4).first { px[$0] == 255 }.map { $0 / 4 }
    }

    private func importSequence(_ state: EditorState, count: Int, step: Int = 1, hold: Int = 1, start: Int = 0,
                                createMissing: Bool = true, replacing: String? = nil, broken: Set<Int> = []) -> String? {
        let plan = GuideSequence.plan(count: count, step: step, start: start, existing: state.frames.count, createMissing: createMissing)
        let images = plan.images.map { broken.contains($0) ? nil : pixels(state, mark: $0) }
        return state.importGuideSequence(images, plan: plan, hold: hold, replacing: replacing, opacity: 0.4, tint: nil)
    }

    func testTwelveImagesIntoAnEmptyClipAndOutOfTheExport() throws {
        // Criteria 1 and 6.
        let state = try makeState()
        let lineBefore = state.layers.count
        let id = try XCTUnwrap(importSequence(state, count: 12))
        XCTAssertEqual(state.frames.count, 12)
        XCTAssertEqual(state.layers.count, lineBefore + 1)
        let guide = state.layers[0]
        XCTAssertEqual(guide.id, id)
        XCTAssertEqual(guide.name, "Guide")
        XCTAssertTrue(guide.guide && guide.locked)
        XCTAssertEqual(guide.opacity, 0.4)
        XCTAssertEqual(state.currentLayer?.id, id, "the guide ends up current")
        XCTAssertTrue(state.frames.allSatisfy { $0.hold == 1 })
        for f in 0..<12 { XCTAssertEqual(mark(state, layer: id, frame: f), f, "image \(f) on frame \(f)") }
        XCTAssertNil(state.flattenedImage(clip: state.clip, frameID: state.frames[3].id).flatMap { img -> Int? in
            var px = [UInt8](repeating: 0, count: img.width * img.height * 4)
            let ctx = CGContext(data: &px, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: img.width * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
            return stride(from: 3, to: px.count, by: 4).first { px[$0] != 0 }
        }, "the export has nothing of the guide")

        state.undo()
        XCTAssertEqual(state.frames.count, 1)
        XCTAssertFalse(state.layers.contains { $0.guide })
        state.redo()
        XCTAssertEqual(state.frames.count, 12)
        XCTAssertEqual(mark(state, layer: id, frame: 7), 7)
    }

    func testExistingFramesKeepTheirHold() throws {
        // Criterion 2.
        let state = try makeState()
        for _ in 0..<5 { state.addDrawing() }
        state.setHold(3)
        let holds = state.frames.map(\.hold)
        let id = try XCTUnwrap(importSequence(state, count: 24, step: 2, hold: 2))
        XCTAssertEqual(state.frames.count, 12)
        XCTAssertEqual(Array(state.frames.prefix(6).map(\.hold)), holds)
        XCTAssertTrue(state.frames.suffix(6).allSatisfy { $0.hold == 2 })
        XCTAssertEqual(mark(state, layer: id, frame: 5), 10, "image 10 (every other one) on frame 5")
    }

    func testReplacingASequenceClearsTheRestAndUndoesBack() throws {
        // Criteria 5 and 6.
        let state = try makeState()
        let id = try XCTUnwrap(importSequence(state, count: 10))
        let line = state.layers[1].id
        let lineTextures = state.frames.map { state.store.existingTexture(clip: state.clip.id, frame: $0.id, layer: line) }
        XCTAssertEqual(importSequence(state, count: 4, replacing: id), id)
        XCTAssertEqual(state.layers.filter(\.guide).count, 1, "the same guide, not a new one")
        XCTAssertEqual(state.frames.count, 10)
        for f in 0..<4 { XCTAssertEqual(mark(state, layer: id, frame: f), f) }
        for f in 4..<10 { XCTAssertNil(mark(state, layer: id, frame: f), "frame \(f) has no guide now") }
        XCTAssertFalse((4..<10).contains { state.clip.isHeld(layer: id, at: $0) }, "and doesn't hold the last one")
        let after = state.frames.map { state.store.existingTexture(clip: state.clip.id, frame: $0.id, layer: line) }
        XCTAssertTrue(zip(lineTextures, after).allSatisfy { $0 === $1 }, "no other layer changes")
        state.undo()
        for f in 0..<10 { XCTAssertEqual(mark(state, layer: id, frame: f), f, "the old ten are back") }
    }

    func testAnUnreadableImageLeavesItsFrameEmpty() throws {
        // Criterion 8.
        let state = try makeState()
        let id = try XCTUnwrap(importSequence(state, count: 12, broken: [5]))
        XCTAssertEqual(state.frames.count, 12)
        XCTAssertNil(mark(state, layer: id, frame: 5))
        XCTAssertEqual(mark(state, layer: id, frame: 6), 6)
    }

    func testTheGuideSurvivesSavingAndOpening() throws {
        // Criterion 9.
        let state = try makeState()
        let plan = GuideSequence.plan(count: 3, step: 1, start: 0, existing: 1, createMissing: true)
        let id = try XCTUnwrap(state.importGuideSequence(plan.images.map { pixels(state, mark: $0) }, plan: plan, hold: 1,
                                                         opacity: 0.6, tint: "#E5484D"))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("GuideSequence-\(UUID().uuidString).calco")
        defer { try? FileManager.default.removeItem(at: url) }
        state.save(to: url)
        let other = try makeState()
        other.open(url)
        let guide = try XCTUnwrap(other.layers.first { $0.id == id })
        XCTAssertTrue(guide.guide && guide.locked)
        XCTAssertEqual(guide.opacity, 0.6)
        XCTAssertEqual(guide.tint, "#E5484D")
        XCTAssertEqual(mark(other, layer: id, frame: 2), 2)
    }

    func testTheOnionSkinLeavesGuidesOut() throws {
        // Criterion 10: a guide on every frame shouldn't ghost a second figure.
        let state = try makeState()
        _ = importSequence(state, count: 3)
        state.frameIndex = 1
        state.onion.enabled = true
        state.onion.before = 1; state.onion.after = 1
        let tinted = state.visibleLayers().filter { $0.tintAmount > 0 }
        XCTAssertTrue(tinted.isEmpty, "no ghosts: only the guide had drawings")
    }
}
