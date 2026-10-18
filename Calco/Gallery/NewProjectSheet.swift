import SwiftUI

/// "New project": a name, a sprite size (presets plus custom), a speed explained in game terms,
/// and the clips to start with. One button and you're drawing.
struct NewProjectSheet: View {
    let create: (EditorState.NewProjectConfig) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var config = EditorState.NewProjectConfig()
    @State private var customSize = false
    @State private var extraClip = ""

    private typealias Config = EditorState.NewProjectConfig

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    TextField("Name", text: $config.name)
                        .font(.title3)
                        .padding(12)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: 10))

                    section("Sprite size") {
                        HStack(alignment: .top, spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                                    ForEach(Config.sizes, id: \.self) { side in
                                        Chip(title: "\(side)",
                                             on: !customSize && config.width == side && config.height == side) {
                                            customSize = false
                                            config.width = side; config.height = side
                                        }
                                    }
                                    Chip(title: "Custom", on: customSize) { customSize = true }
                                }
                                if customSize {
                                    HStack {
                                        CompactStepper(title: "W", value: $config.width, range: Config.sideRange)
                                        CompactStepper(title: "H", value: $config.height, range: Config.sideRange)
                                    }
                                }
                                Text("\(config.width) × \(config.height) px")
                                    .font(.caption).foregroundStyle(Theme.textFaint)
                            }
                            SizePreview(width: config.width, height: config.height)
                        }
                    }

                    section("Speed") {
                        HStack(spacing: 6) {
                            fps(8, "Retro, few poses")
                            fps(12, "The usual for games")
                            fps(24, "Very smooth")
                        }
                    }

                    section("Start with these clips") {
                        FlowChips(items: Config.suggestedClips + config.clips.filter { !Config.suggestedClips.contains($0) },
                                  isOn: { config.clips.contains($0) },
                                  toggle: toggleClip)
                        HStack {
                            TextField("Another clip (crouch, dash…)", text: $extraClip)
                                .onSubmit(addExtraClip)
                            Button("Add", action: addExtraClip)
                                .disabled(ProjectLibrary.cleanName(extraClip).isEmpty)
                        }
                        .padding(10)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
                        if config.clips.isEmpty {
                            Text("Starts with one Idle clip.").font(.caption).foregroundStyle(Theme.textFaint)
                        }
                    }
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) {
                Button { create(config) } label: {
                    Text("Create and start drawing")
                        .font(.headline)
                        .foregroundStyle(Theme.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(20)
                .background(Theme.panel)
            }
            .background(Theme.panel)
            .navigationTitle("New project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(Theme.textFaint)
            content()
        }
    }

    private func fps(_ value: Int, _ note: String) -> some View {
        Button { config.fps = value } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(value) fps").font(.callout.weight(.semibold))
                Text(note).font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .foregroundStyle(config.fps == value ? Theme.accentText : Theme.textDim)
            .background(config.fps == value ? Theme.accentWash : .clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(config.fps == value ? Theme.accent : Theme.hairline))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(config.fps == value ? .isSelected : [])
    }

    private func toggleClip(_ name: String) {
        if let i = config.clips.firstIndex(of: name) { config.clips.remove(at: i) } else { config.clips.append(name) }
    }

    private func addExtraClip() {
        let name = ProjectLibrary.cleanName(extraClip)
        guard !name.isEmpty else { return }
        if !config.clips.contains(name) { config.clips.append(name) }
        extraClip = ""
    }
}

/// A selectable rounded tag.
struct Chip: View {
    let title: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout)
                .foregroundStyle(on ? Theme.accentText : Theme.textDim)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8).padding(.horizontal, 10)
                .background(on ? Theme.accentWash : .clear, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(on ? Theme.accent : Theme.hairline))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Chips that wrap onto as many rows as they need.
private struct FlowChips: View {
    let items: [String]
    let isOn: (String) -> Bool
    let toggle: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 6)], spacing: 6) {
            ForEach(items, id: \.self) { item in
                Chip(title: isOn(item) ? "✓ \(item)" : item, on: isOn(item)) { toggle(item) }
            }
        }
    }
}

/// How big the sprite is next to the largest preset, so 64 px reads as small and 1024 as big.
private struct SizePreview: View {
    let width: Int
    let height: Int
    private let box: CGFloat = 110

    var body: some View {
        let biggest = CGFloat(max(width, height, EditorState.NewProjectConfig.sizes.last ?? 1024))
        let w = max(4, box * CGFloat(width) / biggest), h = max(4, box * CGFloat(height) / biggest)
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline)
                RoundedRectangle(cornerRadius: 2).fill(Theme.text).frame(width: w, height: h)
            }
            .frame(width: box, height: box)
            Text("vs. 1024").font(.caption2).foregroundStyle(Theme.textFaint)
        }
        .accessibilityHidden(true)
    }
}
