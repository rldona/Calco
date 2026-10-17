import Foundation

/// In-memory representation of a `.calco` project.
/// Mirrors `docs/format.md` 1:1. Keep it Codable and free of UI concerns.
struct Project: Codable, Equatable {
    static let currentFormatVersion = 1

    var version: Int = Project.currentFormatVersion
    var name: String
    var canvas: CanvasSize
    var fps: Int = 12
    var clips: [Clip] = []
    var references: [Reference] = []
}

struct CanvasSize: Codable, Equatable {
    var width: Int
    var height: Int
}

struct Clip: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var fps: Int?
    var loop: Bool = true
    /// Normalized 0...1, origin bottom-left (Unity convention).
    var pivot: Pivot = Pivot(x: 0.5, y: 0.0)
    var layers: [Layer] = []
    var frames: [Frame] = []
}

struct Pivot: Codable, Equatable {
    var x: Double
    var y: Double
}

struct Layer: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var opacity: Double = 1.0
    var visible: Bool = true
    var locked: Bool = false
}

struct Frame: Codable, Equatable, Identifiable {
    var id: String
    /// Ticks at the clip's fps this frame stays on screen.
    var hold: Int = 1
}

struct Reference: Codable, Equatable, Identifiable {
    var id: String
    var file: String
    var opacity: Double = 0.3
}
