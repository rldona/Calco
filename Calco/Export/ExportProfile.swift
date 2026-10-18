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

        var id: String { rawValue }
        var title: String {
            switch self {
            case .spriteSheet: "Sprite sheet + JSON"
            case .gif: "GIF"
            case .pngSequence: "PNG sequence"
            }
        }
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

    static let scales: [Double] = [0.5, 1, 2, 4]

    var sheetOptions: SpriteSheet.Options {
        SpriteSheet.Options(padding: padding, scale: scale, trim: trim, powerOfTwo: powerOfTwo, clips: clips)
    }

    /// One line for lists: "Sprite sheet · 2× · trimmed".
    var summary: String {
        var parts = [target.title]
        if scale != 1 { parts.append(scale < 1 ? "½×" : "\(Int(scale))×") }
        if target == .spriteSheet && trim { parts.append("trimmed") }
        if target == .spriteSheet && powerOfTwo { parts.append("power of two") }
        if let clips { parts.append(clips.count == 1 ? "1 clip" : "\(clips.count) clips") }
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
