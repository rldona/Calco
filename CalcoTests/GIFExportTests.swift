import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import Calco

final class GIFExportTests: XCTestCase {

    private func solid(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, size: Int = 8) -> CGImage {
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info)!
        ctx.setFillColor(red: r, green: g, blue: b, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: size / 2, height: size))   // left half opaque, right half transparent
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

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("GIFExportTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("clip.gif")
    }

    func testFramesDelaysLoopAndTransparency() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        try GIFExport.write([
            .init(image: solid(1, 0, 0), durationSeconds: 1.0 / 12),
            .init(image: nil, durationSeconds: 2.0 / 12),
            .init(image: solid(0, 0, 1), durationSeconds: 0.5),
        ], canvas: CanvasSize(width: 8, height: 8), loop: true, to: url)

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.gif.identifier)
        XCTAssertEqual(CGImageSourceGetCount(source), 3)

        let fileProps = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
        let gif = fileProps?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        XCTAssertEqual(gif?[kCGImagePropertyGIFLoopCount] as? Int, 0, "0 = loop forever")

        func delay(_ i: Int) -> Double? {
            let p = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any]
            let g = p?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            return g?[kCGImagePropertyGIFUnclampedDelayTime] as? Double
        }
        XCTAssertEqual(try XCTUnwrap(delay(0)), 0.08, accuracy: 0.011, "GIF stores hundredths of a second")
        XCTAssertEqual(try XCTUnwrap(delay(1)), 0.17, accuracy: 0.011)
        XCTAssertEqual(try XCTUnwrap(delay(2)), 0.5, accuracy: 0.011)

        let first = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(first.width, 8)
        XCTAssertEqual(pixel(first, x: 1, y: 1), [255, 0, 0, 255], "left half red")
        XCTAssertEqual(pixel(first, x: 6, y: 1)[3], 0, "right half transparent")
        let blank = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 1, nil))
        XCTAssertEqual(pixel(blank, x: 1, y: 1)[3], 0, "undrawn frame is fully transparent")
    }

    func testPlayOnceWritesLoopCountOne() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try GIFExport.write([.init(image: solid(0, 1, 0), durationSeconds: 0.1)],
                            canvas: CanvasSize(width: 8, height: 8), loop: false, to: url)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let gif = (CGImageSourceCopyProperties(source, nil) as? [CFString: Any])?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        XCTAssertEqual(gif?[kCGImagePropertyGIFLoopCount] as? Int, 1, "plays once")
    }

    func testEmptyClipThrows() {
        XCTAssertThrowsError(try GIFExport.write([], canvas: CanvasSize(width: 8, height: 8), loop: true, to: tempURL()))
    }
}
