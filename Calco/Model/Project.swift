import Foundation
import simd

/// In-memory representation of a `.calco` project.
/// Mirrors `docs/format.md` 1:1. Keep it Codable and free of UI concerns.
struct Project: Codable, Equatable {
    /// 2 added `frames[].held`, 3 `frames[].links` (cycles). Older files load as-is.
    static let currentFormatVersion = 3

    var version: Int = Project.currentFormatVersion
    var name: String
    var canvas: CanvasSize
    var fps: Int = 12
    var clips: [Clip] = []
    var references: [Reference] = []
    /// Hard-edged brush, eraser, fill and lasso: every pixel is fully on or off. Optional in the
    /// file, written only when true.
    var pixelArt = false
    /// The character's colours, named. Optional in the file, written when there are any.
    var palette: [PaletteColor] = []
    /// Drawing with a mirror, and where its axes are. Optional in the file, written when on.
    var symmetry: Symmetry?

    init(version: Int = Project.currentFormatVersion, name: String, canvas: CanvasSize, fps: Int = 12,
         clips: [Clip] = [], references: [Reference] = [], pixelArt: Bool = false, palette: [PaletteColor] = []) {
        self.version = version; self.name = name; self.canvas = canvas; self.fps = fps
        self.clips = clips; self.references = references; self.pixelArt = pixelArt; self.palette = palette
    }

    private enum CodingKeys: String, CodingKey { case version, name, canvas, fps, clips, references, pixelArt, palette, symmetry }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Project.currentFormatVersion
        name = try c.decode(String.self, forKey: .name)
        canvas = try c.decode(CanvasSize.self, forKey: .canvas)
        fps = try c.decodeIfPresent(Int.self, forKey: .fps) ?? 12
        clips = try c.decodeIfPresent([Clip].self, forKey: .clips) ?? []
        references = try c.decodeIfPresent([Reference].self, forKey: .references) ?? []
        pixelArt = try c.decodeIfPresent(Bool.self, forKey: .pixelArt) ?? false
        palette = try c.decodeIfPresent([PaletteColor].self, forKey: .palette) ?? []
        symmetry = try c.decodeIfPresent(Symmetry.self, forKey: .symmetry)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(name, forKey: .name)
        try c.encode(canvas, forKey: .canvas)
        try c.encode(fps, forKey: .fps)
        try c.encode(clips, forKey: .clips)
        try c.encode(references, forKey: .references)
        if pixelArt { try c.encode(pixelArt, forKey: .pixelArt) }
        if !palette.isEmpty { try c.encode(palette, forKey: .palette) }
        if let symmetry { try c.encode(symmetry, forKey: .symmetry) }
    }
}

/// A named colour of the project's palette. `color` is "#RRGGBB".
struct PaletteColor: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var color: String

    init(id: String = UUID().uuidString, name: String, color: String) {
        self.id = id; self.name = name; self.color = color
    }

    init(id: String = UUID().uuidString, name: String, rgb: SIMD3<Float>) {
        self.init(id: id, name: name, color: Palette.hex(rgb))
    }

    /// RGB 0–1; black if the string isn't a colour.
    var rgb: SIMD3<Float> { Palette.rgb(color) ?? .zero }
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
    /// Only shows where the layer below has paint (a clipping mask), for shading over a colour pass.
    /// Several masked layers in a row share the same base. Optional in the file, written when true.
    var maskBelow = false
    /// A guide to draw over (an imported reference image): shown in the editor, never exported, and
    /// not an outline for the fill. Optional in the file, written when true.
    var guide = false
    /// A guide's lines in one colour, "#RRGGBB", so they don't read as drawing. Only guide layers
    /// show it. Optional in the file.
    var tint: String?

    init(id: String, name: String, opacity: Double = 1.0, visible: Bool = true, locked: Bool = false,
         maskBelow: Bool = false, guide: Bool = false, tint: String? = nil) {
        self.id = id; self.name = name; self.opacity = opacity; self.visible = visible
        self.locked = locked; self.maskBelow = maskBelow; self.guide = guide; self.tint = tint
    }

    /// The tint as RGB 0–1, when this is a guide with a valid one.
    var guideTint: SIMD3<Float>? {
        guard guide, let tint, tint.count == 7, tint.first == "#", let v = UInt32(tint.dropFirst(), radix: 16) else { return nil }
        return SIMD3(Float((v >> 16) & 0xFF), Float((v >> 8) & 0xFF), Float(v & 0xFF)) / 255
    }

    private enum CodingKeys: String, CodingKey { case id, name, opacity, visible, locked, maskBelow, guide, tint }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        visible = try c.decodeIfPresent(Bool.self, forKey: .visible) ?? true
        locked = try c.decodeIfPresent(Bool.self, forKey: .locked) ?? false
        maskBelow = try c.decodeIfPresent(Bool.self, forKey: .maskBelow) ?? false
        guide = try c.decodeIfPresent(Bool.self, forKey: .guide) ?? false
        tint = try c.decodeIfPresent(String.self, forKey: .tint)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(opacity, forKey: .opacity)
        try c.encode(visible, forKey: .visible)
        try c.encode(locked, forKey: .locked)
        if maskBelow { try c.encode(maskBelow, forKey: .maskBelow) }
        if guide { try c.encode(guide, forKey: .guide) }
        try c.encodeIfPresent(tint, forKey: .tint)
    }
}

struct Frame: Codable, Equatable, Identifiable {
    var id: String
    /// Ticks at the clip's fps this frame stays on screen.
    var hold: Int = 1
    /// Layers that keep showing the drawing from the frame before (an exposure-sheet hold), so
    /// they have no drawing of their own here. Never applies to a clip's first frame.
    var held: [String] = []
    /// Optional names for this frame's own drawings, by layer id ("contact", "passing"…).
    var labels: [String: String] = [:]
    /// Layers that show another frame's drawing here, linked (a cycle): layer id → frame id. Editing
    /// it edits that drawing, so every repeat changes with it. No drawing of their own here either.
    var links: [String: String] = [:]

    init(id: String, hold: Int = 1, held: [String] = [], labels: [String: String] = [:],
         links: [String: String] = [:]) {
        self.id = id
        self.hold = hold
        self.held = held
        self.labels = labels
        self.links = links
    }

    private enum CodingKeys: String, CodingKey { case id, hold, held, labels, links }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        hold = try c.decodeIfPresent(Int.self, forKey: .hold) ?? 1
        held = try c.decodeIfPresent([String].self, forKey: .held) ?? []
        labels = try c.decodeIfPresent([String: String].self, forKey: .labels) ?? [:]
        links = try c.decodeIfPresent([String: String].self, forKey: .links) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(hold, forKey: .hold)
        if !held.isEmpty { try c.encode(held, forKey: .held) }
        if !labels.isEmpty { try c.encode(labels, forKey: .labels) }
        if !links.isEmpty { try c.encode(links, forKey: .links) }
    }

    /// Makes `layer` show a drawing of its own here: not held, not linked.
    mutating func ownDrawing(_ layer: String) {
        held.removeAll { $0 == layer }
        links[layer] = nil
    }
}

extension Clip {
    /// Whether `layer` holds the previous frame's drawing at frame `index`.
    func isHeld(layer: String, at index: Int) -> Bool {
        index > 0 && frames.indices.contains(index) && frames[index].held.contains(layer)
    }

    /// Frame `id` that `layer` links to at frame `index` (a cycle repeat), if it's linked there.
    func linkTarget(layer: String, at index: Int) -> Int? {
        guard !isHeld(layer: layer, at: index), frames.indices.contains(index),
              let id = frames[index].links[layer], id != frames[index].id else { return nil }
        return frames.firstIndex { $0.id == id }
    }

    /// Whether `layer` shows a linked drawing at frame `index` (the start of a cycle repeat).
    func isLinked(layer: String, at index: Int) -> Bool { linkTarget(layer: layer, at: index) != nil }

    /// The frame whose drawing `layer` shows at frame `index`: walks back over holds and follows
    /// links. A broken or circular link stops where it is (that cell then has no drawing).
    func sourceIndex(layer: String, at index: Int) -> Int {
        var i = index
        for _ in 0...(frames.count * 2) {
            if isHeld(layer: layer, at: i) { i -= 1 }
            else if let j = linkTarget(layer: layer, at: i) { i = j }
            else { return i }
        }
        return index
    }

    /// Where the cell showing frame `index` starts on `layer`: walks back over holds only, so a
    /// linked repeat is its own cell.
    func cellStart(layer: String, at index: Int) -> Int {
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
