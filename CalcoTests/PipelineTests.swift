import XCTest
import CoreGraphics
@testable import Calco

/// v0.6: Godot SpriteFrames, Unity extensions (pixels per unit, label events), export checks.
final class PipelineTests: XCTestCase {

    /// 8×8 canvas with a 2×2 opaque block whose top-left is at (`x`, `y`); nil for nothing drawn.
    private func block(x: Int, y: Int) -> CGImage {
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let ctx = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info)!
        ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: x, y: 8 - y - 2, width: 2, height: 2))
        return ctx.makeImage()!
    }

    private func project(frames: [Frame], loop: Bool = true, pivotY: Double = 0) -> Project {
        var p = Project(name: "P", canvas: CanvasSize(width: 8, height: 8), fps: 12)
        p.clips = [Clip(id: "walk", name: "Walk", fps: 8, loop: loop, pivot: Pivot(x: 0.5, y: pivotY),
                        layers: [Layer(id: "line", name: "Line"), Layer(id: "sketch", name: "Sketch", visible: false)],
                        frames: frames)]
        return p
    }

    // MARK: Godot

    func testGodotSpriteFramesHasOneAnimationPerClipWithHoldsAndMargins() {
        let p = project(frames: [Frame(id: "0", hold: 2), Frame(id: "1")], loop: false)
        let sheet = SpriteSheet.build(project: p, options: .init(padding: 0, trim: true)) { _, f in
            f.id == "0" ? self.block(x: 2, y: 4) : self.block(x: 4, y: 4)
        }
        let tres = GodotExport.spriteFrames(sheet, project: p, imageName: "P.png")
        XCTAssertTrue(tres.hasPrefix("[gd_resource type=\"SpriteFrames\" load_steps=4 format=3]"))
        XCTAssertTrue(tres.contains("[ext_resource type=\"Texture2D\" path=\"P.png\" id=\"1_sheet\"]"))
        // Trimmed to the clip's box (2,4)…(6,6): region 4×2, margin = offset + what's left of the 8×8 canvas.
        XCTAssertTrue(tres.contains("region = Rect2(0, 0, 4, 2)"))
        XCTAssertTrue(tres.contains("margin = Rect2(2, 4, 4, 6)"))
        XCTAssertTrue(tres.contains("\"duration\": 2.0"))
        XCTAssertTrue(tres.contains("\"name\": &\"walk\""))
        XCTAssertTrue(tres.contains("\"loop\": false"))
        XCTAssertTrue(tres.contains("\"speed\": 8.0"), "the clip's own fps")
        XCTAssertEqual(tres.components(separatedBy: "[sub_resource type=\"AtlasTexture\"").count - 1, 2)
    }

    // MARK: Unity extensions

    func testLabelsAndPixelsPerUnitAreWrittenOnlyWhenAsked() throws {
        let p = project(frames: [Frame(id: "0", labels: ["line": "contact", "sketch": "x"]), Frame(id: "1")])
        let plain = SpriteSheet.build(project: p, options: .init()) { _, _ in nil }
        let plainJSON = String(data: try JSONEncoder().encode(plain.aseprite(projectName: "P", imageName: "P.png")), encoding: .utf8)!
        XCTAssertFalse(plainJSON.contains("\"label\""))
        XCTAssertFalse(plainJSON.contains("pixelsPerUnit"))

        let sheet = SpriteSheet.build(project: p, options: .init(labels: true, pixelsPerUnit: 32)) { _, _ in nil }
        let json = sheet.aseprite(projectName: "P", imageName: "P.png")
        XCTAssertEqual(json.frames.map(\.label), ["contact,x", nil], "layer order, held frames have none")
        XCTAssertEqual(json.meta.pixelsPerUnit, 32)
    }

    func testOldSavedProfilesStillLoad() throws {
        let old = #"[{"id":"00000000-0000-0000-0000-00000000C001","name":"Unity","target":"spriteSheet","scale":2,"trim":true,"padding":2,"powerOfTwo":false}]"#
        let profiles = try JSONDecoder().decode([ExportProfile].self, from: Data(old.utf8))
        XCTAssertEqual(profiles.first?.scale, 2)
        XCTAssertFalse(profiles[0].labelEvents)
        XCTAssertNil(profiles[0].pixelsPerUnit)
        let unknownTarget = #"[{"id":"00000000-0000-0000-0000-00000000C009","name":"X","target":"spine"}]"#
        XCTAssertEqual(try JSONDecoder().decode([ExportProfile].self, from: Data(unknownTarget.utf8))[0].target, .spriteSheet)
    }

    // MARK: Checks

    private func check(_ p: Project, hidden: Bool = false, _ image: @escaping (Frame) -> CGImage?) -> [ExportChecks.Issue.Kind] {
        ExportChecks.run(project: p, clips: nil, frameImage: { _, f in image(f) }, hiddenDrawing: { _, _ in hidden })
            .map(\.kind)
    }

    func testCleanCycleHasNoIssues() {
        let p = project(frames: [Frame(id: "0"), Frame(id: "1")])
        XCTAssertEqual(check(p) { $0.id == "0" ? self.block(x: 2, y: 6) : self.block(x: 4, y: 6) }, [])
    }

    func testEmptyFramesHiddenLayersFeetAndRepeatedLoopFrames() {
        let p = project(frames: [Frame(id: "0"), Frame(id: "1"), Frame(id: "2")])
        let kinds = check(p, hidden: true) { f in
            switch f.id {
            case "0": self.block(x: 2, y: 6)       // feet on the ground
            case "1": nil                           // empty
            default: self.block(x: 2, y: 6)        // same as the first: the loop repeats it
            }
        }
        XCTAssertEqual(Set(kinds), [.emptyFrame, .hiddenLayer, .loopRepeats])

        // Every frame different (so the loop doesn't repeat), the middle one lifted.
        let sliding = check(p) { f in self.block(x: 1 + 2 * (Int(f.id) ?? 0), y: f.id == "1" ? 1 : 6) }
        XCTAssertEqual(sliding, [.feetDrift])

        let floating = project(frames: [Frame(id: "0"), Frame(id: "1")], pivotY: 0.5)
        XCTAssertEqual(check(floating) { f in self.block(x: 2, y: f.id == "1" ? 1 : 6) }, [],
                       "only clips anchored at the feet are checked for drift")
    }
}
