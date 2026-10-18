import Foundation

/// In-memory representation of a `.calco` project.
/// Mirrors `docs/format.md` 1:1. Keep it Codable and free of UI concerns.
struct Project: Codable, Equatable {
    /// 2 added `frames[].held`. Version 1 files load as-is (nothing held).
    static let currentFormatVersion = 2

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
    /// Layers that keep showing the drawing from the frame before (an exposure-sheet hold), so
    /// they have no drawing of their own here. Never applies to a clip's first frame.
    var held: [String] = []

    init(id: String, hold: Int = 1, held: [String] = []) {
        self.id = id
        self.hold = hold
        self.held = held
    }

    private enum CodingKeys: String, CodingKey { case id, hold, held }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        hold = try c.decodeIfPresent(Int.self, forKey: .hold) ?? 1
        held = try c.decodeIfPresent([String].self, forKey: .held) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(hold, forKey: .hold)
        if !held.isEmpty { try c.encode(held, forKey: .held) }
    }
}

extension Clip {
    /// Whether `layer` holds the previous frame's drawing at frame `index`.
    func isHeld(layer: String, at index: Int) -> Bool {
        index > 0 && frames.indices.contains(index) && frames[index].held.contains(layer)
    }

    /// The frame whose drawing `layer` shows at frame `index`: walks back over holds.
    func sourceIndex(layer: String, at index: Int) -> Int {
        var i = index
        while isHeld(layer: layer, at: i) { i -= 1 }
        return i
    }

    /// Frame id of the drawing `layer` shows at frame `index`, or nil if `index` is out of range.
    func sourceFrameID(layer: String, at index: Int) -> String? {
        frames.indices.contains(index) ? frames[sourceIndex(layer: layer, at: index)].id : nil
    }

    /// Where each drawing of `layer` starts and how many frames it spans (its own frame + the
    /// frames holding it). Runs cover the whole clip, in order.
    func runs(of layer: String) -> [(start: Int, count: Int)] {
        var out: [(start: Int, count: Int)] = []
        for i in frames.indices {
            if isHeld(layer: layer, at: i), !out.isEmpty { out[out.count - 1].count += 1 }
            else { out.append((i, 1)) }
        }
        return out
    }
}

struct Reference: Codable, Equatable, Identifiable {
    var id: String
    var file: String
    var opacity: Double = 0.3
}
