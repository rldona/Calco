import XCTest
import Metal
import CoreGraphics
@testable import Calco

final class SpriteSheetOptionsTests: XCTestCase {

    /// 8×8 canvas, a 2×3 opaque block whose top-left is at (`x`, `y`).
    private func block(x: Int, y: Int) -> CGImage {
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let ctx = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info)!
        ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: x, y: 8 - y - 3, width: 2, height: 3))   // CG is bottom-left
        return ctx.makeImage()!
    }

    private var project: Project {
        var p = Project(name: "P", canvas: CanvasSize(width: 8, height: 8), fps: 10)
        let layers = [Layer(id: "line", name: "Line")]
        p.clips = [
            Clip(id: "idle", name: "Idle", pivot: Pivot(x: 0.5, y: 0), layers: layers,
                 frames: [Frame(id: "0"), Frame(id: "1")]),
            Clip(id: "run", name: "Run", pivot: Pivot(x: 0.5, y: 0), layers: layers, frames: [Frame(id: "2")]),
        ]
        return p
    }

    /// idle frame 0 block at (1,1), frame 1 at (4,2); run at (3,3).
    private func images(_ clip: Clip, _ frame: Frame) -> CGImage? {
        switch frame.id {
        case "0": block(x: 1, y: 1)
        case "1": block(x: 4, y: 2)
        default: block(x: 3, y: 3)
        }
    }

    func testOpaqueBounds() {
        XCTAssertEqual(SpriteSheet.opaqueBounds(block(x: 1, y: 1)), CGRect(x: 1, y: 1, width: 2, height: 3))
    }

    func testClipFilterAndScale() throws {
        let sheet = SpriteSheet.build(project: project, options: .init(padding: 0, scale: 2, clips: ["run"]), frameImage: images)
        XCTAssertEqual(sheet.cells.map(\.frame.id), ["2"])
        XCTAssertEqual(sheet.cells[0].rect.size, CGSize(width: 16, height: 16))
        let json = sheet.aseprite(projectName: "P", imageName: "P.png")
        XCTAssertEqual(json.meta.frameTags.map(\.name), ["run"])
        XCTAssertEqual(json.meta.scale, "2")
        XCTAssertEqual(json.frames[0].sourceSize.w, 16)
        XCTAssertEqual(json.meta.slices[0].keys[0].pivot.x, 8, "pivot scales with the frames")
        XCTAssertEqual(json.meta.slices[0].keys[0].pivot.y, 16)
    }

    func testTrimIsOneBoxPerClipAndKeepsThePivotInPlace() throws {
        let sheet = SpriteSheet.build(project: project, options: .init(padding: 0, trim: true), frameImage: images)
        let idle = sheet.cells.filter { $0.clip.id == "idle" }
        // Union of (1,1,2,3) and (4,2,2,3) = (1,1)…(6,5).
        XCTAssertEqual(idle.map(\.source), [CGRect(x: 1, y: 1, width: 5, height: 4), CGRect(x: 1, y: 1, width: 5, height: 4)])
        XCTAssertEqual(sheet.cells.first { $0.clip.id == "run" }?.source, CGRect(x: 3, y: 3, width: 2, height: 3))

        let json = sheet.aseprite(projectName: "P", imageName: "P.png")
        let f = json.frames[0]
        XCTAssertTrue(f.trimmed)
        XCTAssertEqual([f.spriteSourceSize.x, f.spriteSourceSize.y, f.spriteSourceSize.w, f.spriteSourceSize.h], [1, 1, 5, 4])
        XCTAssertEqual([f.sourceSize.w, f.sourceSize.h], [8, 8])

        // What calco-unity does with it (CalcoSheet.PivotFor(tag, frame)): canvas pivot onto the box.
        let canvasPivot = (x: 0.5, y: 0.0)                  // bottom-centre of the 8×8 canvas
        let px = canvasPivot.x * 8, py = (1 - canvasPivot.y) * 8
        let local = (x: (px - 1) / 5, y: 1 - (py - 1) / 4)
        // Back in canvas pixels from the box: the same point, (4, 8).
        XCTAssertEqual(1 + local.x * 5, 4, accuracy: 1e-9)
        XCTAssertEqual(1 + (1 - local.y) * 4, 8, accuracy: 1e-9)
    }

    func testPowerOfTwoAndPixels() throws {
        let sheet = SpriteSheet.build(project: project, options: .init(padding: 1, scale: 1, powerOfTwo: true), frameImage: images)
        XCTAssertEqual(sheet.size, CGSize(width: 32, height: 32), "pad + 2 × (8 + pad) = 19 → 32")
        let trimmed = SpriteSheet.build(project: project, options: .init(padding: 0, trim: true), frameImage: images)
        // The run cell's first pixel is the block's top-left.
        let img = try XCTUnwrap(trimmed.image)
        var px = [UInt8](repeating: 0, count: img.width * img.height * 4)
        let ctx = CGContext(data: &px, width: img.width, height: img.height, bitsPerComponent: 8, bytesPerRow: img.width * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        let run = try XCTUnwrap(trimmed.cells.first { $0.clip.id == "run" })
        XCTAssertEqual(px[(Int(run.rect.minY) * img.width + Int(run.rect.minX)) * 4 + 3], 255)
    }
}

@MainActor
final class ExportProfileTests: XCTestCase {

    private func makeState(defaults: UserDefaults? = nil) throws -> EditorState {
        guard let device = MTLCreateSystemDefaultDevice(),
              let state = EditorState(device: device, screenFormat: .bgra8Unorm, defaults: defaults) else {
            throw XCTSkip("Metal unavailable in this environment")
        }
        return state
    }

    func testProfilesAndLastUsedAreRemembered() throws {
        let suite = "ExportProfileTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = try makeState(defaults: defaults)
        XCTAssertEqual(first.exportProfiles, ExportProfile.presets, "a fresh install offers the presets")
        first.exportProfiles.append(ExportProfile(name: "Mine", scale: 2, trim: true))
        first.lastExportProfileID = first.exportProfiles.last?.id

        let second = try makeState(defaults: defaults)
        XCTAssertEqual(second.exportProfiles.last?.name, "Mine")
        XCTAssertEqual(second.lastExportProfile?.scale, 2)
    }

    func testEveryTargetWritesFiles() throws {
        let state = try makeState()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ExportProfile-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = try XCTUnwrap(state.beginStroke())
        state.renderer.paint([.init(position: SIMD2(100, 100), radius: 20, alpha: 1)], into: target,
                             color: SIMD4(0, 0, 0, 1), tool: .brush)
        state.strokeEnded()
        state.addFrame()
        state.setHold(3)
        state.addClip(name: "Run")

        let sheet = try XCTUnwrap(state.export(ExportProfile(name: "Unity · trimmed", trim: true), in: dir))
        XCTAssertEqual(sheet.map(\.lastPathComponent), ["Untitled.png", "Untitled.json"])
        XCTAssertEqual(state.lastExportProfile?.name, nil, "an unsaved profile isn't 'last used' by id")

        let gifs = try XCTUnwrap(state.export(ExportProfile(name: "GIF", target: .gif, scale: 0.5), in: dir))
        XCTAssertEqual(gifs.map(\.lastPathComponent), ["Untitled-idle.gif", "Untitled-run.gif"])

        let seq = try XCTUnwrap(state.export(ExportProfile(name: "Frames", target: .pngSequence, clips: ["idle"]), in: dir))
        let files = try FileManager.default.contentsOfDirectory(atPath: seq[0].appendingPathComponent("idle").path).sorted()
        XCTAssertEqual(files, ["idle_000.png", "idle_001.png", "idle_002.png", "idle_003.png"], "1 + 3 ticks")

        XCTAssertNil(state.export(ExportProfile(name: "None", clips: []), in: dir))
        XCTAssertNotNil(state.lastError)
    }

    func testRunningASavedProfileMakesItLastUsed() throws {
        let state = try makeState()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ExportProfile-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let gif = try XCTUnwrap(state.exportProfiles.first { $0.target == .gif })
        _ = state.export(gif, in: dir)
        XCTAssertEqual(state.lastExportProfile, gif)
    }
}
