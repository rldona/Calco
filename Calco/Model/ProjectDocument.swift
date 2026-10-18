import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// One PNG inside the package: `clips/<clip>/<frame>/<layer>.png`.
struct LayerKey: Hashable {
    var clip: String
    var frame: String
    var layer: String
}

/// Reads and writes the `.calco` package on disk (see `docs/format.md`).
/// Pure Foundation + ImageIO: no Metal, no UI, so it is testable on its own.
enum ProjectDocument {
    static let manifestName = "project.json"
    static let clipsFolder = "clips"
    static let referencesFolder = "references"
    static let fileExtension = "calco"
    static let contentType = UTType(exportedAs: "dev.plazoleta.calco.project")

    enum Error: LocalizedError {
        case unsupportedVersion(Int)
        case invalidCanvas(CanvasSize)
        case pngEncodingFailed(LayerKey)

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let v):
                return "This project was saved by a newer Calco (format \(v), this app reads up to \(Project.currentFormatVersion))."
            case .invalidCanvas(let c):
                return "Invalid canvas size \(c.width)×\(c.height)."
            case .pngEncodingFailed(let k):
                return "Couldn't encode \(k.clip)/\(k.frame)/\(k.layer).png."
            }
        }
    }

    // MARK: - Paths

    static func layerURL(in packageURL: URL, _ key: LayerKey) -> URL {
        packageURL
            .appendingPathComponent(clipsFolder, isDirectory: true)
            .appendingPathComponent(key.clip, isDirectory: true)
            .appendingPathComponent(key.frame, isDirectory: true)
            .appendingPathComponent("\(key.layer).png")
    }

    /// Every (clip, frame, layer) the manifest refers to, whether or not a PNG exists for it.
    static func layerKeys(of project: Project) -> [LayerKey] {
        project.clips.flatMap { clip in
            clip.frames.flatMap { frame in
                clip.layers.map { LayerKey(clip: clip.id, frame: frame.id, layer: $0.id) }
            }
        }
    }

    // MARK: - Load

    static func load(from packageURL: URL) throws -> Project {
        let data = try Data(contentsOf: packageURL.appendingPathComponent(manifestName))
        let project = try JSONDecoder().decode(Project.self, from: data)
        guard project.version <= Project.currentFormatVersion else {
            throw Error.unsupportedVersion(project.version)
        }
        guard (1...8192).contains(project.canvas.width), (1...8192).contains(project.canvas.height) else {
            throw Error.invalidCanvas(project.canvas)
        }
        return project
    }

    /// Reads every layer PNG the manifest refers to. A missing file is a blank layer, not an error.
    static func loadLayerImages(from packageURL: URL, project: Project) -> [LayerKey: CGImage] {
        var out: [LayerKey: CGImage] = [:]
        for key in layerKeys(of: project) {
            let url = layerURL(in: packageURL, key)
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
            out[key] = image
        }
        return out
    }

    // MARK: - Save

    /// Writes the whole package. `layerImage` returns nil for blank layers, which are omitted.
    ///
    /// The package is assembled in a staging folder and swapped in at the end, so a save that fails
    /// halfway never leaves a half-written project behind, and frames deleted since the last save
    /// don't linger as orphan folders. `references/` is carried over untouched; Calco doesn't edit it yet.
    static func save(_ project: Project, to packageURL: URL,
                     layerImage: (LayerKey) -> CGImage? = { _ in nil }) throws {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory
            .appendingPathComponent("calco-save-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(project).write(to: staging.appendingPathComponent(manifestName))

        for key in layerKeys(of: project) {
            guard let image = layerImage(key) else { continue }
            let url = layerURL(in: staging, key)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try writePNG(image, to: url, key: key)
        }

        let oldReferences = packageURL.appendingPathComponent(referencesFolder, isDirectory: true)
        if fm.fileExists(atPath: oldReferences.path) {
            try fm.copyItem(at: oldReferences, to: staging.appendingPathComponent(referencesFolder, isDirectory: true))
        }

        if fm.fileExists(atPath: packageURL.path) {
            do {
                _ = try fm.replaceItemAt(packageURL, withItemAt: staging)
            } catch {
                // Some file providers refuse the swap. Fall back to rewriting in place.
                try fm.removeItem(at: packageURL)
                try fm.copyItem(at: staging, to: packageURL)
            }
        } else {
            try fm.createDirectory(at: packageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: staging, to: packageURL)
        }
    }

    private static func writePNG(_ image: CGImage, to url: URL, key: LayerKey) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw Error.pngEncodingFailed(key)
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw Error.pngEncodingFailed(key) }
    }
}
