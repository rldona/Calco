import XCTest
import Metal
@testable import Calco

@MainActor
final class ProjectLibraryTests: XCTestCase {

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectLibraryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeState() throws -> EditorState {
        guard let device = MTLCreateSystemDefaultDevice(),
              let state = EditorState(device: device, screenFormat: .bgra8Unorm) else {
            throw XCTSkip("Metal unavailable in this environment")
        }
        return state
    }

    private func write(_ name: String, clips: [Clip] = [EditorState.defaultClip()]) throws -> URL {
        let url = ProjectLibrary(directory: dir).url(for: name)
        try ProjectDocument.save(Project(name: name, canvas: CanvasSize(width: 64, height: 32), fps: 8, clips: clips), to: url)
        return url
    }

    func testCreateProjectUsesTheConfigAndLandsInTheLibrary() throws {
        let state = try makeState()
        var config = EditorState.NewProjectConfig()
        config.name = "  Slime  "
        config.width = 128; config.height = 64
        config.fps = 8
        config.clips = ["Idle", "Jump", "Jump attack"]
        state.createProject(config, in: dir)

        XCTAssertNil(state.lastError)
        XCTAssertFalse(state.isInGallery)
        XCTAssertFalse(state.isDirty)
        XCTAssertEqual(state.project.name, "Slime")
        XCTAssertEqual(state.project.canvas, CanvasSize(width: 128, height: 64))
        XCTAssertEqual(state.renderer.canvasSize, SIMD2(128, 64))
        XCTAssertEqual(state.project.fps, 8)
        XCTAssertEqual(state.project.clips.map(\.id), ["idle", "jump", "jump-attack"])
        XCTAssertTrue(state.project.clips.allSatisfy { $0.frames.count == 1 }, "every track starts with a frame")
        XCTAssertEqual(Set(state.project.clips.flatMap(\.frames).map(\.id)).count, 3, "frame ids stay unique")
        XCTAssertEqual(state.documentURL, ProjectLibrary(directory: dir).url(for: "Slime"))

        let entries = ProjectLibrary(directory: dir).entries()
        XCTAssertEqual(entries.map(\.name), ["Slime"])

        // Same name again gets a suffix instead of overwriting.
        state.createProject(config, in: dir)
        XCTAssertEqual(state.project.name, "Slime 2")
    }

    func testNoClipsFallsBackToIdleAndSizesAreClamped() throws {
        let state = try makeState()
        var config = EditorState.NewProjectConfig()
        config.clips = ["   "]
        config.width = 1; config.height = 99_999
        state.createProject(config, in: dir)
        XCTAssertEqual(state.project.clips.map(\.id), ["idle"])
        XCTAssertEqual(state.project.canvas, CanvasSize(width: 16, height: 2048))
    }

    func testEntriesAreNewestFirstAndSkipJunk() throws {
        _ = try write("Old")
        Thread.sleep(forTimeInterval: 1.1)
        _ = try write("New")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Broken.calco"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: dir.appendingPathComponent("notes.txt"))

        XCTAssertEqual(ProjectLibrary(directory: dir).entries().map(\.name), ["New", "Old"])
    }

    func testRenameDuplicateDelete() throws {
        _ = try write("Hero")
        _ = try write("Villain")
        let library = ProjectLibrary(directory: dir)
        let hero = try XCTUnwrap(library.entries().first { $0.name == "Hero" })

        let renamed = try library.rename(hero, to: "Villain")
        XCTAssertEqual(renamed.lastPathComponent, "Villain 2.calco", "never overwrites another project")
        XCTAssertEqual(try ProjectDocument.load(from: renamed).name, "Villain 2", "manifest name follows")

        let entry = try XCTUnwrap(library.entries().first { $0.name == "Villain 2" })
        let copy = try library.duplicate(entry)
        XCTAssertEqual(copy.lastPathComponent, "Villain 2 copy.calco")
        XCTAssertEqual(try ProjectDocument.load(from: copy).name, "Villain 2 copy")

        try library.delete(entry)
        XCTAssertEqual(Set(library.entries().map(\.name)), ["Villain", "Villain 2 copy"])
    }

    func testFoldersListTheirProjectsOneLevelDeep() throws {
        _ = try write("Top")
        let library = ProjectLibrary(directory: dir)
        XCTAssertEqual(try library.createFolder("Enemies"), "Enemies")
        XCTAssertEqual(try library.createFolder("enemies"), "enemies 2", "names don't clash, whatever the case")
        XCTAssertEqual(try library.createFolder(".hidden.calco"), "hidden", "never hidden, never a package")
        XCTAssertEqual(try library.createFolder("Exports"), "Exports 2", "the app's own folders are kept apart")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Exports"), withIntermediateDirectories: true)
        try ProjectDocument.save(Project(name: "Slime", canvas: CanvasSize(width: 8, height: 8), fps: 8,
                                         clips: [EditorState.defaultClip()]), to: library.url(for: "Slime", in: "Enemies"))

        XCTAssertEqual(library.folders(), ["enemies 2", "Enemies", "Exports 2", "hidden"].sorted {
            $0.localizedStandardCompare($1) == .orderedAscending })
        let entries = library.entries()
        XCTAssertEqual(Set(entries.map(\.name)), ["Top", "Slime"])
        XCTAssertEqual(entries.first { $0.name == "Slime" }?.folder, "Enemies")
        XCTAssertNil(entries.first { $0.name == "Top" }?.folder)
    }

    func testMoveKeepsNamesApartAndRenameStaysInTheFolder() throws {
        _ = try write("Hero")
        let library = ProjectLibrary(directory: dir)
        try library.createFolder("Cast")
        _ = try ProjectDocument.save(Project(name: "Hero", canvas: CanvasSize(width: 8, height: 8), fps: 8,
                                             clips: [EditorState.defaultClip()]), to: library.url(for: "Hero", in: "Cast"))
        let top = try XCTUnwrap(library.entries().first { $0.folder == nil })

        let moved = try library.move(top, to: "Cast")
        XCTAssertEqual(moved, library.url(for: "Hero 2", in: "Cast"), "never overwrites the one already there")
        XCTAssertEqual(try ProjectDocument.load(from: moved).name, "Hero 2")
        XCTAssertTrue(library.entries().allSatisfy { $0.folder == "Cast" })

        let entry = try XCTUnwrap(library.entries().first { $0.name == "Hero 2" })
        XCTAssertEqual(try library.rename(entry, to: "Rival"), library.url(for: "Rival", in: "Cast"))
        let rival = try XCTUnwrap(library.entries().first { $0.name == "Rival" })
        XCTAssertEqual(try library.duplicate(rival), library.url(for: "Rival copy", in: "Cast"))

        let back = try library.move(rival, to: nil)
        XCTAssertEqual(back, library.url(for: "Rival"))
    }

    func testRenameAndDeleteAFolderKeepItsProjects() throws {
        _ = try write("Hero")
        let library = ProjectLibrary(directory: dir)
        try library.createFolder("Cast")
        _ = try ProjectDocument.save(Project(name: "Hero", canvas: CanvasSize(width: 8, height: 8), fps: 8,
                                             clips: [EditorState.defaultClip()]), to: library.url(for: "Hero", in: "Cast"))
        XCTAssertEqual(try library.renameFolder("Cast", to: "cast"), "cast", "a change of case is fine")
        XCTAssertEqual(try library.renameFolder("cast", to: "Heroes"), "Heroes")

        try library.deleteFolder("Heroes")
        XCTAssertEqual(library.folders(), [])
        XCTAssertEqual(Set(library.entries().map(\.name)), ["Hero", "Hero 2"], "projects come back to the top")
        XCTAssertTrue(library.entries().allSatisfy { $0.folder == nil })
    }

    func testPreviewFollowsHoldsAndLoops() {
        let blank = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        let p = ProjectLibrary.Preview(frames: [blank, blank, blank], holds: [2, 1, 3], fps: 10, aspect: 1)
        // Ticks: 0 1 → frame 0, 2 → frame 1, 3 4 5 → frame 2, then loops.
        XCTAssertEqual([0.0, 0.15, 0.2, 0.35, 0.55, 0.6].map(p.frameIndex(at:)), [0, 0, 1, 2, 2, 0])
    }

    func testPreviewFlattensTheFirstClip() throws {
        let state = try makeState()
        state.createProject(EditorState.NewProjectConfig(), in: dir)
        let target = try XCTUnwrap(state.beginStroke())
        state.renderer.paint([.init(position: SIMD2<Float>(128, 128), radius: 40, alpha: 1)],
                             into: target, color: SIMD4<Float>(0, 0, 0, 1), tool: .brush)
        state.strokeEnded()
        state.addFrame()
        state.save()

        let entry = try XCTUnwrap(ProjectLibrary(directory: dir).entries().first)
        let preview = try XCTUnwrap(ProjectLibrary.preview(of: entry, maxSide: 64))
        XCTAssertEqual(preview.frames.count, 2)
        XCTAssertEqual(preview.frames[0].width, 64)
        XCTAssertEqual(preview.fps, 12)
    }
}
