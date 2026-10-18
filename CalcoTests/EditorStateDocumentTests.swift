import XCTest
import Metal
@testable import Calco

/// End-to-end: paint on the GPU, save the package, open it in a fresh editor, read the pixels back.
@MainActor
final class EditorStateDocumentTests: XCTestCase {

    private func makeState() throws -> EditorState {
        guard let device = MTLCreateSystemDefaultDevice(),
              let state = EditorState(device: device, screenFormat: .bgra8Unorm) else {
            throw XCTSkip("Metal unavailable in this environment")
        }
        return state
    }

    private func alpha(_ image: CGImage, x: Int, y: Int) -> UInt8 {
        let w = image.width, h = image.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return bytes[(y * w + x) * 4 + 3]
    }

    func testStrokeSurvivesSaveAndOpen() throws {
        let state = try makeState()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("EditorStateDocumentTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Hero.calco", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        // Paint one dot on the Line layer of frame 000, add an empty frame with a hold.
        XCTAssertEqual(state.currentLayer?.id, "line")
        let target = try XCTUnwrap(state.paintTarget)
        state.renderer.paint([.init(position: SIMD2<Float>(100, 200), radius: 10, alpha: 1)],
                             into: target, color: SIMD4<Float>(0, 0, 0, 1), tool: .brush)
        state.strokeEnded()
        state.addFrame()
        state.setHold(3)
        XCTAssertTrue(state.isDirty)

        state.save(to: url)
        XCTAssertNil(state.lastError)
        XCTAssertFalse(state.isDirty)
        XCTAssertEqual(state.documentURL, url)

        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: url.appendingPathComponent("clips/idle/000/line.png").path))
        XCTAssertFalse(fm.fileExists(atPath: url.appendingPathComponent("clips/idle/000/color.png").path))
        XCTAssertFalse(fm.fileExists(atPath: url.appendingPathComponent("clips/idle/001").path),
                       "a frame nobody drew on has no folder")

        // Open in a brand-new editor.
        let other = try makeState()
        other.open(url)
        XCTAssertNil(other.lastError)
        XCTAssertEqual(other.project, state.project)
        XCTAssertEqual(other.frames.map(\.hold), [1, 3])
        XCTAssertFalse(other.isDirty)

        let line = try XCTUnwrap(other.store.image(clip: "idle", frame: "000", layer: "line"))
        XCTAssertEqual(line.width, 512)
        XCTAssertGreaterThan(alpha(line, x: 100, y: 200), 200, "dot center is opaque")
        XCTAssertEqual(alpha(line, x: 10, y: 10), 0, "far away stays transparent")
        XCTAssertNil(other.store.image(clip: "idle", frame: "000", layer: "color"), "blank layer stays blank")

        // New frames keep unique ids after a load.
        other.addFrame()
        XCTAssertEqual(other.frames.map(\.id), ["000", "002", "001"])
    }

    func testOpenWithDifferentCanvasSizeRebuildsRenderer() throws {
        let state = try makeState()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("EditorStateDocumentTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Wide.calco", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        var wide = EditorState.defaultProject(name: "Wide")
        wide.canvas = CanvasSize(width: 256, height: 128)
        wide.clips[0].frames = [Frame(id: "000")]
        try ProjectDocument.save(wide, to: url)

        state.open(url)
        XCTAssertNil(state.lastError)
        XCTAssertEqual(state.renderer.canvasSize, SIMD2<Int>(256, 128))
        XCTAssertEqual(state.paintTarget?.width, 256)
        XCTAssertEqual(state.paintTarget?.height, 128)
    }
}

@MainActor
final class EditorStateExportTests: XCTestCase {
    func testExportFlattensVisibleLayers() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let state = EditorState(device: device, screenFormat: .bgra8Unorm) else {
            throw XCTSkip("Metal unavailable in this environment")
        }
        // Paint on Line, then hide Color (blank anyway) and check the flattened frame.
        let target = try XCTUnwrap(state.paintTarget)
        state.renderer.paint([.init(position: SIMD2<Float>(100, 200), radius: 10, alpha: 1)],
                             into: target, color: SIMD4<Float>(0, 0, 0, 1), tool: .brush)
        let flat = try XCTUnwrap(state.flattenedImage(clip: state.clip, frameID: state.frames[0].id))
        XCTAssertEqual(flat.width, 512)

        var bytes = [UInt8](repeating: 0, count: 512 * 512 * 4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let ctx = CGContext(data: &bytes, width: 512, height: 512, bitsPerComponent: 8, bytesPerRow: 512 * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info)!
        ctx.draw(flat, in: CGRect(x: 0, y: 0, width: 512, height: 512))
        XCTAssertGreaterThan(bytes[(200 * 512 + 100) * 4 + 3], 200, "stroke is opaque in the flattened frame")
        XCTAssertEqual(bytes[(10 * 512 + 10) * 4 + 3], 0, "background stays transparent (no checkerboard)")

        // Hiding the only painted layer removes it from the export.
        state.toggleLayerVisibility(1)
        XCTAssertNil(state.flattenedImage(clip: state.clip, frameID: state.frames[0].id))
        state.toggleLayerVisibility(1)

        let urls = try XCTUnwrap(state.exportSpriteSheet())
        defer { try? FileManager.default.removeItem(at: urls[0].deletingLastPathComponent()) }
        XCTAssertNil(state.lastError)
        XCTAssertEqual(urls.map(\.pathExtension), ["png", "json"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: urls[1].path))
    }
}

@MainActor
final class EditorStateGIFExportTests: XCTestCase {
    func testExportGIFWritesCurrentClip() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let state = EditorState(device: device, screenFormat: .bgra8Unorm) else {
            throw XCTSkip("Metal unavailable in this environment")
        }
        let target = try XCTUnwrap(state.paintTarget)
        state.renderer.paint([.init(position: SIMD2<Float>(100, 200), radius: 10, alpha: 1)],
                             into: target, color: SIMD4<Float>(0, 0, 0, 1), tool: .brush)
        state.addFrame()
        state.setHold(3)

        let url = try XCTUnwrap(state.exportGIF())
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        XCTAssertNil(state.lastError)
        XCTAssertEqual(url.lastPathComponent, "Untitled-idle.gif")

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), 2)
        let p = CGImageSourceCopyPropertiesAtIndex(source, 1, nil) as? [CFString: Any]
        let g = p?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        XCTAssertEqual(try XCTUnwrap(g?[kCGImagePropertyGIFUnclampedDelayTime] as? Double), 0.25, accuracy: 0.011, "hold 3 at 12 fps")
    }
}
