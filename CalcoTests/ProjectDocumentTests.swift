import XCTest
import CoreGraphics
@testable import Calco

final class ProjectDocumentTests: XCTestCase {

    private var packageURL: URL!

    override func setUpWithError() throws {
        packageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectDocumentTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Hero.calco", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: packageURL.deletingLastPathComponent())
    }

    private func makeProject(frames: [Frame]) -> Project {
        Project(
            name: "Hero",
            canvas: CanvasSize(width: 8, height: 8),
            clips: [
                Clip(id: "idle", name: "Idle",
                     layers: [Layer(id: "color", name: "Color"), Layer(id: "line", name: "Line")],
                     frames: frames)
            ]
        )
    }

    /// 8×8 transparent image with one opaque red pixel at (2, 3), top-left origin.
    private func makeImage() -> CGImage {
        let w = 8, h = 8
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info)!
        ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        // CGContext's origin is bottom-left; row 3 from the top is y = h - 1 - 3.
        ctx.fill(CGRect(x: 2, y: h - 1 - 3, width: 1, height: 1))
        return ctx.makeImage()!
    }

    private func pixels(_ image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return bytes
    }

    func testManifestRoundTrip() throws {
        let project = makeProject(frames: [Frame(id: "000", hold: 2), Frame(id: "001", hold: 2)])
        try ProjectDocument.save(project, to: packageURL)
        let loaded = try ProjectDocument.load(from: packageURL)
        XCTAssertEqual(project, loaded)
    }

    func testLayerPNGsRoundTripAndBlankLayersAreOmitted() throws {
        let project = makeProject(frames: [Frame(id: "000")])
        let lineKey = LayerKey(clip: "idle", frame: "000", layer: "line")
        let image = makeImage()

        try ProjectDocument.save(project, to: packageURL) { key in key == lineKey ? image : nil }

        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: packageURL.appendingPathComponent("clips/idle/000/line.png").path))
        XCTAssertFalse(fm.fileExists(atPath: packageURL.appendingPathComponent("clips/idle/000/color.png").path),
                       "a layer that was never drawn on must not produce a file")

        let images = ProjectDocument.loadLayerImages(from: packageURL, project: project)
        XCTAssertEqual(images.count, 1)
        let loaded = try XCTUnwrap(images[lineKey])
        XCTAssertEqual(loaded.width, 8)
        XCTAssertEqual(loaded.height, 8)

        let px = pixels(loaded)
        let i = (3 * 8 + 2) * 4
        XCTAssertEqual(Array(px[i..<i + 4]), [255, 0, 0, 255], "red pixel survives at (2, 3), top-left origin")
        XCTAssertEqual(px[0..<4].reduce(0, { $0 + Int($1) }), 0, "corner stays transparent")
    }

    func testResaveDropsDeletedFrames() throws {
        let image = makeImage()
        let two = makeProject(frames: [Frame(id: "000"), Frame(id: "001")])
        try ProjectDocument.save(two, to: packageURL) { _ in image }
        XCTAssertTrue(FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("clips/idle/001").path))

        let one = makeProject(frames: [Frame(id: "000")])
        try ProjectDocument.save(one, to: packageURL) { _ in image }

        XCTAssertFalse(FileManager.default.fileExists(atPath: packageURL.appendingPathComponent("clips/idle/001").path),
                       "stale frame folders must not survive a save")
        XCTAssertEqual(try ProjectDocument.load(from: packageURL), one)
        XCTAssertEqual(ProjectDocument.loadLayerImages(from: packageURL, project: one).count, 2)
    }

    func testReferencesFolderSurvivesSave() throws {
        let project = makeProject(frames: [Frame(id: "000")])
        try ProjectDocument.save(project, to: packageURL)
        let refs = packageURL.appendingPathComponent("references", isDirectory: true)
        try FileManager.default.createDirectory(at: refs, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: refs.appendingPathComponent("silhouette.png"))

        try ProjectDocument.save(project, to: packageURL)

        XCTAssertEqual(try Data(contentsOf: refs.appendingPathComponent("silhouette.png")), Data([1, 2, 3]))
    }

    func testRejectsNewerFormatVersion() throws {
        var project = makeProject(frames: [])
        project.version = Project.currentFormatVersion + 1
        try ProjectDocument.save(project, to: packageURL)
        XCTAssertThrowsError(try ProjectDocument.load(from: packageURL)) { error in
            guard case ProjectDocument.Error.unsupportedVersion = error else {
                return XCTFail("unexpected error \(error)")
            }
        }
    }

    func testRejectsInvalidCanvas() throws {
        var project = makeProject(frames: [])
        project.canvas = CanvasSize(width: 0, height: 512)
        try ProjectDocument.save(project, to: packageURL)
        XCTAssertThrowsError(try ProjectDocument.load(from: packageURL))
    }
}
