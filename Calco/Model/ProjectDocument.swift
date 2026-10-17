import Foundation

/// Reads and writes the `.calco` package on disk.
/// Only `project.json` for now; layer PNGs come with the canvas work.
enum ProjectDocument {
    static let manifestName = "project.json"

    static func load(from packageURL: URL) throws -> Project {
        let data = try Data(contentsOf: packageURL.appendingPathComponent(manifestName))
        let decoder = JSONDecoder()
        return try decoder.decode(Project.self, from: data)
    }

    static func save(_ project: Project, to packageURL: URL) throws {
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(project)
        try data.write(to: packageURL.appendingPathComponent(manifestName), options: .atomic)
    }
}
