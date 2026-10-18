import Foundation
import CoreGraphics

/// The `.calco` packages in one folder (the app's Documents), for the gallery.
/// Pure Foundation + CoreGraphics like ProjectDocument, so it's testable without UI or Metal.
struct ProjectLibrary {
    let directory: URL

    struct Entry: Identifiable, Equatable {
        var url: URL
        var project: Project
        var modified: Date
        var id: URL { url }
        var name: String { url.deletingPathExtension().lastPathComponent }
    }

    /// Every readable project, most recently edited first. Unreadable packages are skipped.
    func entries() -> [Entry] {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey],
                                                options: [.skipsHiddenFiles])) ?? []
        return urls
            .filter { $0.pathExtension == ProjectDocument.fileExtension }
            .compactMap { url in
                guard let project = try? ProjectDocument.load(from: url) else { return nil }
                return Entry(url: url, project: project, modified: Self.modified(url))
            }
            .sorted { $0.modified > $1.modified }
    }

    /// The manifest is rewritten on every save, so its date is the project's "last edited".
    private static func modified(_ url: URL) -> Date {
        let manifest = url.appendingPathComponent(ProjectDocument.manifestName)
        return (try? manifest.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            ?? .distantPast
    }

    func url(for name: String) -> URL {
        directory.appendingPathComponent(name).appendingPathExtension(ProjectDocument.fileExtension)
    }

    /// `name`, or `name 2`, `name 3`… so it doesn't clash with an existing package.
    func uniqueName(_ name: String) -> String {
        let base = Self.cleanName(name).isEmpty ? "Untitled" : Self.cleanName(name)
        var candidate = base
        var n = 2
        while FileManager.default.fileExists(atPath: url(for: candidate).path) {
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
        let copy = url(for: uniqueName("\(entry.name) copy"))
        try FileManager.default.copyItem(at: entry.url, to: copy)
        var project = try ProjectDocument.load(from: copy)
        project.name = copy.deletingPathExtension().lastPathComponent
        try writeManifest(project, in: copy)
        return copy
    }

    /// Renames the package and the project name inside it. Returns the new URL.
    @discardableResult
    func rename(_ entry: Entry, to newName: String) throws -> URL {
        let clean = Self.cleanName(newName)
        guard !clean.isEmpty, clean != entry.name else { return entry.url }
        let target = url(for: uniqueName(clean))
        try FileManager.default.moveItem(at: entry.url, to: target)
        var project = entry.project
        project.name = target.deletingPathExtension().lastPathComponent
        try writeManifest(project, in: target)
        return target
    }

    func delete(_ entry: Entry) throws {
        try FileManager.default.removeItem(at: entry.url)
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

    /// Reads PNGs and composites visible layers onto white, at most `maxSide` pixels.
    static func preview(of entry: Entry, maxSide: Int = 192) -> Preview? {
        guard let clip = entry.project.clips.first, !clip.frames.isEmpty else { return nil }
        let canvas = entry.project.canvas
        let scale = min(1, CGFloat(maxSide) / CGFloat(max(canvas.width, canvas.height)))
        let w = max(1, Int(CGFloat(canvas.width) * scale)), h = max(1, Int(CGFloat(canvas.height) * scale))
        let space = CGColorSpaceCreateDeviceRGB()
        var images: [CGImage] = []
        for frame in clip.frames {
            guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.interpolationQuality = .medium
            for layer in clip.layers where layer.visible {
                let key = LayerKey(clip: clip.id, frame: frame.id, layer: layer.id)
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
