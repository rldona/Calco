import Foundation

/// A saved way of exporting: what to write, which clips, and how. Profiles are app-wide, so the
/// same "Unity 2×" works for every project. Pure data; `EditorState.export(_:)` runs it.
struct ExportProfile: Codable, Equatable, Identifiable {
    enum Target: String, Codable, CaseIterable, Identifiable {
        /// One PNG + Aseprite JSON with tags, durations and pivots (Unity via calco-unity, Godot, others).
        case spriteSheet
        /// One animated GIF per clip, for sharing.
        case gif
        /// One PNG per tick of each clip, holds expanded, for engines that play image sequences.
        case pngSequence
        /// The sprite sheet PNG plus a Godot 4 SpriteFrames resource (.tres): one animation per clip.
        case godot

        var id: String { rawValue }
        var title: String {
            switch self {
            case .spriteSheet: String(localized: "Sprite sheet + JSON", bundle: AppLanguage.bundle)
            case .gif: String(localized: "GIF", bundle: AppLanguage.bundle)
            case .pngSequence: String(localized: "PNG sequence", bundle: AppLanguage.bundle)
            case .godot: String(localized: "Godot SpriteFrames", bundle: AppLanguage.bundle)
            }
        }

        /// Targets that pack a sheet (scale, trim, padding, power of two all apply).
        var isSheet: Bool { self == .spriteSheet || self == .godot }
    }

    var id = UUID()
    var name: String
    var target: Target = .spriteSheet
    /// Clip ids; nil means every clip in the project.
    var clips: [String]? = nil
    var scale: Double = 1
    /// Sprite sheet only: shrink each clip to the box its drawings use.
    var trim = false
    var padding = SpriteSheet.defaultPadding
    var powerOfTwo = false
    /// Sprite sheet only: tells calco-unity the texture's pixels per unit. Nil leaves Unity's setting alone.
    var pixelsPerUnit: Int? = nil
    /// Sprite sheet only: drawing labels become Unity animation events (`OnCalcoLabel(string)`).
    var labelEvents = false

    static let scales: [Double] = [0.5, 1, 2, 4]

    var sheetOptions: SpriteSheet.Options {
        SpriteSheet.Options(padding: padding, scale: scale, trim: trim, powerOfTwo: powerOfTwo, clips: clips,
                            labels: labelEvents, pixelsPerUnit: pixelsPerUnit)
    }

    init(id: UUID = UUID(), name: String, target: Target = .spriteSheet, clips: [String]? = nil, scale: Double = 1,
         trim: Bool = false, padding: Int = SpriteSheet.defaultPadding, powerOfTwo: Bool = false,
         pixelsPerUnit: Int? = nil, labelEvents: Bool = false) {
        self.id = id; self.name = name; self.target = target; self.clips = clips; self.scale = scale
        self.trim = trim; self.padding = padding; self.powerOfTwo = powerOfTwo
        self.pixelsPerUnit = pixelsPerUnit; self.labelEvents = labelEvents
    }

    // Lenient decoding: profiles saved by an older Calco miss newer fields and keep their defaults.
    private enum CodingKeys: String, CodingKey {
        case id, name, target, clips, scale, trim, padding, powerOfTwo, pixelsPerUnit, labelEvents
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        target = (try? c.decode(Target.self, forKey: .target)) ?? .spriteSheet
        clips = try c.decodeIfPresent([String].self, forKey: .clips)
        scale = try c.decodeIfPresent(Double.self, forKey: .scale) ?? 1
        trim = try c.decodeIfPresent(Bool.self, forKey: .trim) ?? false
        padding = try c.decodeIfPresent(Int.self, forKey: .padding) ?? SpriteSheet.defaultPadding
        powerOfTwo = try c.decodeIfPresent(Bool.self, forKey: .powerOfTwo) ?? false
        pixelsPerUnit = try c.decodeIfPresent(Int.self, forKey: .pixelsPerUnit)
        labelEvents = try c.decodeIfPresent(Bool.self, forKey: .labelEvents) ?? false
    }

    /// One line for lists: "Sprite sheet · 2× · trimmed".
    var summary: String {
        var parts = [target.title]
        if scale != 1 { parts.append(scale < 1 ? "½×" : "\(Int(scale))×") }
        if target.isSheet && trim { parts.append(String(localized: "trimmed", bundle: AppLanguage.bundle)) }
        if target.isSheet && powerOfTwo { parts.append(String(localized: "power of two", bundle: AppLanguage.bundle)) }
        if target == .spriteSheet, let ppu = pixelsPerUnit { parts.append(String(localized: "\(ppu) PPU", bundle: AppLanguage.bundle)) }
        if target == .spriteSheet && labelEvents { parts.append(String(localized: "events", bundle: AppLanguage.bundle)) }
        if let clips { parts.append(clips.count == 1 ? String(localized: "1 clip", bundle: AppLanguage.bundle) : String(localized: "\(clips.count) clips", bundle: AppLanguage.bundle)) }
        return parts.joined(separator: " · ")
    }

    /// What a fresh install offers. Fixed ids so "last used" survives relaunches.
    static let presets: [ExportProfile] = [
        ExportProfile(id: UUID(uuidString: "00000000-0000-0000-0000-00000000C001")!, name: "Unity"),
        ExportProfile(id: UUID(uuidString: "00000000-0000-0000-0000-00000000C002")!, name: "Unity · trimmed",
                      trim: true, powerOfTwo: true),
        ExportProfile(id: UUID(uuidString: "00000000-0000-0000-0000-00000000C003")!, name: "Pixel art 4×",
                      scale: 4, padding: 4),
        ExportProfile(id: UUID(uuidString: "00000000-0000-0000-0000-00000000C004")!, name: "GIF to share",
                      target: .gif),
        ExportProfile(id: UUID(uuidString: "00000000-0000-0000-0000-00000000C005")!, name: "PNG frames",
                      target: .pngSequence),
        ExportProfile(id: UUID(uuidString: "00000000-0000-0000-0000-00000000C006")!, name: "Godot",
                      target: .godot),
    ]
}

/// Profiles kept in UserDefaults as JSON. Nil defaults (tests, previews) keep them in memory.
struct ExportProfileStore {
    let defaults: UserDefaults?
    private static let key = "export.profiles"
    private static let lastKey = "export.lastProfile"

    func load() -> [ExportProfile] {
        guard let data = defaults?.data(forKey: Self.key),
              let saved = try? JSONDecoder().decode([ExportProfile].self, from: data), !saved.isEmpty
        else { return ExportProfile.presets }
        return saved
    }

    func save(_ profiles: [ExportProfile]) {
        guard let defaults, let data = try? JSONEncoder().encode(profiles) else { return }
        defaults.set(data, forKey: Self.key)
    }

    var lastUsed: UUID? {
        get { defaults?.string(forKey: Self.lastKey).flatMap(UUID.init(uuidString:)) }
        nonmutating set { defaults?.set(newValue?.uuidString, forKey: Self.lastKey) }
    }
}
