import XCTest
import CoreGraphics
@testable import Calco

final class SpriteSheetTests: XCTestCase {

    private func solid(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, size: Int = 4) -> CGImage {
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info)!
        ctx.setFillColor(red: r, green: g, blue: b, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return ctx.makeImage()!
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        let w = image.width, h = image.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let i = (y * w + x) * 4
        return Array(bytes[i..<i + 4])
    }

    private var project: Project {
        var p = Project(name: "Hero", canvas: CanvasSize(width: 4, height: 4), fps: 12)
        p.clips = [
            Clip(id: "idle", name: "Idle", pivot: Pivot(x: 0.5, y: 0),
                 layers: [Layer(id: "line", name: "Line")],
                 frames: [Frame(id: "000", hold: 1), Frame(id: "001", hold: 2)]),
            Clip(id: "run", name: "Run", fps: 24, loop: false, pivot: Pivot(x: 0.25, y: 0.5),
                 layers: [Layer(id: "line", name: "Line")],
                 frames: [Frame(id: "002", hold: 3)]),
        ]
        return p
    }

    func testGridLayoutAndPixels() throws {
        let red = solid(1, 0, 0), green = solid(0, 1, 0), blue = solid(0, 0, 1)
        let sheet = SpriteSheet.build(project: project) { clip, frame in
            switch frame.id { case "000": return red; case "001": return green; default: return blue }
        }
        // 3 frames → 2 columns, 2 rows of 4×4 cells.
        XCTAssertEqual(sheet.columns, 2)
        XCTAssertEqual(sheet.size, CGSize(width: 8, height: 8))
        XCTAssertEqual(sheet.cells.map(\.rect), [
            CGRect(x: 0, y: 0, width: 4, height: 4),
            CGRect(x: 4, y: 0, width: 4, height: 4),
            CGRect(x: 0, y: 4, width: 4, height: 4),
        ])
        let image = try XCTUnwrap(sheet.image)
        XCTAssertEqual(pixel(image, x: 1, y: 1), [255, 0, 0, 255], "frame 0 top-left")
        XCTAssertEqual(pixel(image, x: 5, y: 1), [0, 255, 0, 255], "frame 1 top-right")
        XCTAssertEqual(pixel(image, x: 1, y: 5), [0, 0, 255, 255], "frame 2 bottom-left")
        XCTAssertEqual(pixel(image, x: 5, y: 5)[3], 0, "unused cell stays transparent")
    }

    func testBlankFramesAreTransparentCells() throws {
        let sheet = SpriteSheet.build(project: project) { _, _ in nil }
        let image = try XCTUnwrap(sheet.image)
        XCTAssertEqual(pixel(image, x: 1, y: 1)[3], 0)
    }

    func testAsepriteJSON() throws {
        let sheet = SpriteSheet.build(project: project) { _, _ in nil }
        let ase = sheet.aseprite(projectName: "Hero", imageName: "Hero.png")

        XCTAssertEqual(ase.frames.count, 3)
        XCTAssertEqual(ase.frames.map(\.filename), ["Hero idle 0.png", "Hero idle 1.png", "Hero run 0.png"])
        XCTAssertEqual(ase.frames.map(\.duration), [83, 167, 125], "hold / fps in ms: 1/12, 2/12, 3/24")
        XCTAssertEqual(ase.frames[1].frame.x, 4)
        XCTAssertEqual(ase.frames[2].frame.y, 4)

        XCTAssertEqual(ase.meta.image, "Hero.png")
        XCTAssertEqual(ase.meta.size.w, 8)
        XCTAssertEqual(ase.meta.frameTags.map(\.name), ["idle", "run"])
        XCTAssertEqual(ase.meta.frameTags.map { [$0.from, $0.to] }, [[0, 1], [2, 2]])
        XCTAssertEqual(ase.meta.frameTags.map(\.loop), [true, false])

        XCTAssertEqual(ase.meta.slices.map(\.name), ["idle", "run"])
        let idle = ase.meta.slices[0].keys[0]
        XCTAssertEqual(idle.frame, 0)
        XCTAssertEqual([idle.pivot.x, idle.pivot.y], [2, 4], "bottom-center → (w/2, h) in Aseprite's top-left pixels")
        let run = ase.meta.slices[1].keys[0]
        XCTAssertEqual(run.frame, 2)
        XCTAssertEqual([run.pivot.x, run.pivot.y], [1, 2])
    }

    func testWriteProducesPNGAndJSON() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpriteSheetTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let sheet = SpriteSheet.build(project: project) { _, _ in self.solid(1, 0, 0) }
        let urls = try sheet.write(to: folder, baseName: "Hero")
        XCTAssertEqual(urls.map(\.lastPathComponent), ["Hero.png", "Hero.json"])

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(urls[0] as CFURL, nil))
        let png = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(png.width, 8)

        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: urls[1])) as? [String: Any]
        let meta = try XCTUnwrap(json?["meta"] as? [String: Any])
        XCTAssertEqual(meta["app"] as? String, "Calco")
        XCTAssertEqual((json?["frames"] as? [Any])?.count, 3)
        XCTAssertEqual((meta["frameTags"] as? [Any])?.count, 2)
    }
}
