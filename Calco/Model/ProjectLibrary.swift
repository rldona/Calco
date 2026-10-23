import Foundation
import CoreGraphics

/// The `.calco` packages in one folder (the app's Documents) and in its folders, one level deep,
/// for the gallery. Folders are plain folders, so Files shows the same thing.
/// Pure Foundation + CoreGraphics like ProjectDocument, so it's testable without UI or Metal.
struct ProjectLibrary {
    let directory: URL

    struct Entry: Identifiable, Equatable {
        var url: URL
        var project: Project
        var modified: Date
        /// The folder it's in, nil at the top.
        var folder: String?
        var id: URL { url }
        var name: String { url.deletingPathExtension().lastPathComponent }
    }

    /// Folders the app writes itself, never shown as the person's folders.
    static let reservedFolders: Set<String> = ["Exports", "Inbox"]

    /// Every readable project, at the top and in the folders, most recently edited first.
    /// Unreadable packages are skipped.
    func entries() -> [Entry] {
        ([nil] + folders().map(Optional.some))
            .flatMap { folder in
                packages(in: folderURL(folder)).compactMap { url -> Entry? in
                    guard let project = try? ProjectDocument.load(from: url) else { return nil }
                    return Entry(url: url, project: project, modified: Self.modified(url), folder: folder)
                }
            }
            .sorted { $0.modified > $1.modified }
    }

    /// The person's folders, by name.
    func folders() -> [String] {
        contents(of: directory)
            .filter { url in
                url.pathExtension != ProjectDocument.fileExtension
                    && !Self.reservedFolders.contains(url.lastPathComponent)
                    && (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            }
            .map(\.lastPathComponent)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// The top (nil) or a folder.
    func folderURL(_ folder: String?) -> URL {
        folder.map { directory.appendingPathComponent($0, isDirectory: true) } ?? directory
    }

    private func contents(of url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey],
                                                      options: [.skipsHiddenFiles])) ?? []
    }

    private func packages(in url: URL) -> [URL] {
        contents(of: url).filter { $0.pathExtension == ProjectDocument.fileExtension }
    }

    /// The manifest is rewritten on every save, so its date is the project's "last edited".
    private static func modified(_ url: URL) -> Date {
        let manifest = url.appendingPathComponent(ProjectDocument.manifestName)
        return (try? manifest.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            ?? .distantPast
    }

    func url(for name: String, in folder: String? = nil) -> URL {
        folderURL(folder).appendingPathComponent(name).appendingPathExtension(ProjectDocument.fileExtension)
    }

    /// `name`, or `name 2`, `name 3`… so it doesn't clash with an existing package in `folder`.
    func uniqueName(_ name: String, in folder: String? = nil) -> String {
        let base = Self.cleanName(name).isEmpty ? "Untitled" : Self.cleanName(name)
        var candidate = base
        var n = 2
        while FileManager.default.fileExists(atPath: url(for: candidate, in: folder).path) {
            candidate = "\(base) \(n)"; n += 1
        }
        return candidate
    }

    static func cleanName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
    }

    // MARK: - Managing

    @discardableResult
    func duplicate(_ entry: Entry) throws -> URL {
        let copy = url(for: uniqueName("\(entry.name) copy", in: entry.folder), in: entry.folder)
        try FileManager.default.copyItem(at: entry.url, to: copy)
        var project = try ProjectDocument.load(from: copy)
        project.name = copy.deletingPathExtension().lastPathComponent
        try writeManifest(project, in: copy)
        return copy
    }

    /// Renames the package and the project name inside it, in the same folder. Returns the new URL.
    @discardableResult
    func rename(_ entry: Entry, to newName: String) throws -> URL {
        let clean = Self.cleanName(newName)
        guard !clean.isEmpty, clean != entry.name else { return entry.url }
        let target = url(for: uniqueName(clean, in: entry.folder), in: entry.folder)
        try FileManager.default.moveItem(at: entry.url, to: target)
        var project = entry.project
        project.name = target.deletingPathExtension().lastPathComponent
        try writeManifest(project, in: target)
        return target
    }

    /// Copies a `.calco` package from elsewhere (a drop from Files) into `folder`, under a name
    /// that doesn't clash. Returns the copy.
    @discardableResult
    func importPackage(at source: URL, into folder: String? = nil) throws -> URL {
        let name = uniqueName(source.deletingPathExtension().lastPathComponent, in: folder)
        let target = url(for: name, in: folder)
        try FileManager.default.copyItem(at: source, to: target)
        return target
    }

    func delete(_ entry: Entry) throws {
        try FileManager.default.removeItem(at: entry.url)
    }

    /// Moves the project into `folder` (nil: the top), renamed if one there has its name.
    /// Returns where it is now.
    @discardableResult
    func move(_ entry: Entry, to folder: String?) throws -> URL {
        guard folder != entry.folder else { return entry.url }
        let name = uniqueName(entry.name, in: folder)
        let target = url(for: name, in: folder)
        try FileManager.default.moveItem(at: entry.url, to: target)
        if name != entry.name {
            var project = entry.project
            project.name = name
            try writeManifest(project, in: target)
        }
        return target
    }

    // MARK: - Folders

    /// A folder name that's safe on disk: no slashes, no leading dots (hidden), and not a
    /// package's extension.
    static func cleanFolderName(_ name: String) -> String {
        var clean = cleanName(name)
        while clean.hasPrefix(".") { clean.removeFirst() }
        if (clean as NSString).pathExtension.lowercased() == ProjectDocument.fileExtension {
            clean = (clean as NSString).deletingPathExtension
        }
        return clean.trimmingCharacters(in: .whitespaces)
    }

    /// `name`, or `name 2`… so it doesn't clash with a folder, a project or the app's own folders.
    func uniqueFolderName(_ name: String) -> String {
        let base = Self.cleanFolderName(name).isEmpty ? "Folder" : Self.cleanFolderName(name)
        let taken = Set(contents(of: directory).map { $0.lastPathComponent.lowercased() })
            .union(Self.reservedFolders.map { $0.lowercased() })
        var candidate = base
        var n = 2
        while taken.contains(candidate.lowercased()) {
            candidate = "\(base) \(n)"; n += 1
        }
        return candidate
    }

    /// Makes a folder and returns its name, which may have a number added.
    @discardableResult
    func createFolder(_ name: String) throws -> String {
        let unique = uniqueFolderName(name)
        try FileManager.default.createDirectory(at: folderURL(unique), withIntermediateDirectories: false)
        return unique
    }

    @discardableResult
    func renameFolder(_ folder: String, to newName: String) throws -> String {
        let clean = Self.cleanFolderName(newName)
        guard !clean.isEmpty, clean != folder else { return folder }
        // Only a change of case: no clash with itself.
        let unique = clean.lowercased() == folder.lowercased() ? clean : uniqueFolderName(clean)
        try FileManager.default.moveItem(at: folderURL(folder), to: folderURL(unique))
        return unique
    }

    /// Removes the folder but never its projects: they go back to the top (renamed where one
    /// there has the name), and so does anything else that was in it.
    func deleteFolder(_ folder: String) throws {
        let fm = FileManager.default
        for url in contents(of: folderURL(folder)) {
            if url.pathExtension == ProjectDocument.fileExtension,
               let project = try? ProjectDocument.load(from: url) {
                try move(Entry(url: url, project: project, modified: .distantPast, folder: folder), to: nil)
            } else {
                var target = directory.appendingPathComponent(url.lastPathComponent)
                var n = 2
                while fm.fileExists(atPath: target.path) {
                    let base = url.deletingPathExtension().lastPathComponent
                    target = directory.appendingPathComponent("\(base) \(n)").appendingPathExtension(url.pathExtension)
                    n += 1
                }
                try fm.moveItem(at: url, to: target)
            }
        }
        try fm.removeItem(at: folderURL(folder))
    }

    private func writeManifest(_ project: Project, in url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(project).write(to: url.appendingPathComponent(ProjectDocument.manifestName), options: .atomic)
    }

    // MARK: - Previews

    /// A gallery card's animation: the first clip's frames flattened small, with their holds.
    struct Preview {
        var frames: [CGImage]
        var holds: [Int]
        var fps: Int
        var aspect: CGFloat

        /// Which frame shows at `time` seconds, looping over the clip's total ticks.
        func frameIndex(at time: TimeInterval) -> Int {
            let total = holds.reduce(0, +)
            guard total > 0, !frames.isEmpty else { return 0 }
            var tick = Int(time * Double(fps)) % total
            for (i, h) in holds.enumerated() {
                if tick < h { return min(i, frames.count - 1) }
                tick -= h
            }
            return frames.count - 1
        }
    }

    /// Reads PNGs and composites visible layers onto white, at most `maxSide` pixels: clip
    /// `clipIndex` (the first by default), holds resolved, guides left out as in an export.
    static func preview(of entry: Entry, clipIndex: Int = 0, maxSide: Int = 192) -> Preview? {
        guard entry.project.clips.indices.contains(clipIndex) else { return nil }
        let clip = entry.project.clips[clipIndex]
        guard !clip.frames.isEmpty else { return nil }
        let canvas = entry.project.canvas
        let scale = min(1, CGFloat(maxSide) / CGFloat(max(canvas.width, canvas.height)))
        let w = max(1, Int(CGFloat(canvas.width) * scale)), h = max(1, Int(CGFloat(canvas.height) * scale))
        let space = CGColorSpaceCreateDeviceRGB()
        var images: [CGImage] = []
        for index in clip.frames.indices {
            guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.interpolationQuality = .medium
            for layer in clip.layers where layer.visible && !layer.guide {
                // A held or linked cell shows another frame's drawing.
                guard let source = clip.sourceFrameID(layer: layer.id, at: index) else { continue }
                let key = LayerKey(clip: clip.id, frame: source, layer: layer.id)
                guard let image = ProjectDocument.image(at: ProjectDocument.layerURL(in: entry.url, key)) else { continue }
                ctx.setAlpha(CGFloat(layer.opacity))
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
            if let image = ctx.makeImage() { images.append(image) }
        }
        return Preview(frames: images, holds: clip.frames.map(\.hold), fps: clip.fps ?? entry.project.fps,
                       aspect: CGFloat(canvas.width) / CGFloat(canvas.height))
    }
}
