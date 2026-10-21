import SwiftUI

/// "Export…": pick or tweak a profile, then export. Edits save straight into the profile, so the
/// next project exports the same way; "Export again" (⇧⌘E) reruns the last one without this sheet.
struct ExportProfilesSheet: View {
    @Bindable var state: EditorState
    let finished: ([URL], String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selection: UUID?
    @State private var confirmingDelete = false

    private var index: Int? { state.exportProfiles.firstIndex { $0.id == selection } }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                list.frame(width: 250)
                Divider()
                if let i = index {
                    ProfileEditor(state: state, profile: $state.exportProfiles[i])
                } else {
                    Text("Pick a profile").foregroundStyle(Theme.textFaint).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Export \(state.project.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export") {
                        guard let i = index else { return }
                        let profile = state.exportProfiles[i]
                        if let urls = state.export(profile) {
                            dismiss()
                            finished(urls, profile.name)
                        }
                    }
                    .bold()
                    .disabled(index == nil)
                }
            }
            .alert("Delete \(index.map { state.exportProfiles[$0].name } ?? "profile")?", isPresented: $confirmingDelete) {
                Button("Delete", role: .destructive) {
                    if let i = index { state.exportProfiles.remove(at: i) }
                    selection = state.exportProfiles.first?.id
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .onAppear { selection = state.lastExportProfileID ?? state.exportProfiles.first?.id }
    }

    private var list: some View {
        List(selection: $selection) {
            ForEach(state.exportProfiles) { p in
                let on = p.id == selection
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).font(.callout.weight(.medium))
                        .foregroundStyle(on ? Theme.onAccent : Theme.text)
                    Text(p.summary).font(.caption).lineLimit(1)
                        .foregroundStyle(on ? Theme.onAccent.opacity(0.75) : Theme.textDim)
                }
                .tag(p.id)
            }
            Section {
                Button {
                    var copy = index.map { state.exportProfiles[$0] } ?? ExportProfile(name: "Profile")
                    copy.id = UUID()
                    copy.name = "\(copy.name) copy"
                    state.exportProfiles.append(copy)
                    selection = copy.id
                } label: { Label("Duplicate profile", systemImage: "plus.square.on.square") }
                Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete profile", systemImage: "trash") }
                    .disabled(index == nil || state.exportProfiles.count <= 1)
                Button { state.exportProfiles = ExportProfile.presets; selection = state.exportProfiles.first?.id } label: {
                    Label("Restore presets", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct ProfileEditor: View {
    @Bindable var state: EditorState
    @Binding var profile: ExportProfile
    @State private var issues: [ExportChecks.Issue] = []

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $profile.name)
                Picker("Export as", selection: $profile.target) {
                    ForEach(ExportProfile.Target.allCases) { Text($0.title).tag($0) }
                }
            }
            Section("Clips") {
                Toggle("Every clip", isOn: Binding(
                    get: { profile.clips == nil },
                    set: { profile.clips = $0 ? nil : state.project.clips.map(\.id) }))
                if let chosen = profile.clips {
                    ForEach(state.project.clips) { clip in
                        Toggle(clip.name, isOn: Binding(
                            get: { chosen.contains(clip.id) },
                            set: { on in profile.clips = on ? chosen + [clip.id] : chosen.filter { $0 != clip.id } }))
                    }
                }
            }
            Section {
                Picker("Scale", selection: $profile.scale) {
                    ForEach(ExportProfile.scales, id: \.self) { s in Text(s < 1 ? "½×" : "\(Int(s))×").tag(s) }
                }
                .pickerStyle(.segmented)
                if profile.target.isSheet {
                    Toggle("Trim transparent borders", isOn: $profile.trim)
                    Stepper("Padding \(profile.padding) px", value: $profile.padding, in: 0...16)
                    Toggle("Power-of-two sheet", isOn: $profile.powerOfTwo)
                }
            } header: {
                Text("Pixels")
            } footer: {
                Text(footnote).font(.caption)
            }
            Section {
                if issues.isEmpty {
                    Label("Nothing to fix", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                } else {
                    ForEach(issues) { issue in
                        Label(issue.message, systemImage: icon(issue.kind))
                            .font(.callout)
                            .foregroundStyle(Theme.accentText)
                    }
                }
            } header: {
                Text("Before you export")
            } footer: {
                Text("Advice only: a jump lifts the feet on purpose, for example.").font(.caption)
            }
            if profile.target == .spriteSheet {
                Section {
                    Toggle("Set pixels per unit", isOn: Binding(
                        get: { profile.pixelsPerUnit != nil },
                        set: { profile.pixelsPerUnit = $0 ? (profile.pixelsPerUnit ?? 100) : nil }))
                    if let ppu = profile.pixelsPerUnit {
                        Stepper("\(ppu) pixels per unit", value: Binding(
                            get: { ppu }, set: { profile.pixelsPerUnit = $0 }), in: 1...1024, step: ppu < 32 ? 1 : 8)
                    }
                    Toggle("Labels as animation events", isOn: $profile.labelEvents)
                } header: {
                    Text("Unity")
                } footer: {
                    Text(profile.labelEvents
                         ? "A drawing labelled \"step\" calls OnCalcoLabel(\"step\") on the GameObject when its frame plays. Add that method to a script on the same object."
                         : "Pixels per unit is written for calco-unity; leave it off to keep the texture's own setting.")
                    .font(.caption)
                }
            }
        }
        .task(id: profile.clips) { issues = state.exportChecks(clips: profile.clips) }
    }

    private func icon(_ kind: ExportChecks.Issue.Kind) -> String {
        switch kind {
        case .emptyFrame: "square.dashed"
        case .hiddenLayer: "eye.slash"
        case .feetDrift: "figure.walk.motion"
        case .loopRepeats: "repeat.1"
        }
    }

    private var footnote: String {
        let w = Int((Double(state.project.canvas.width) * profile.scale).rounded())
        let h = Int((Double(state.project.canvas.height) * profile.scale).rounded())
        switch profile.target {
        case .spriteSheet:
            return profile.trim
                ? String(localized: "Frames \(w) × \(h) px before trimming. Each clip is trimmed to the box its drawings use; the JSON keeps the pivot in place for Unity.", bundle: AppLanguage.bundle)
                : String(localized: "Frames \(w) × \(h) px.", bundle: AppLanguage.bundle)
        case .gif: return String(localized: "One GIF per clip, \(w) × \(h) px.", bundle: AppLanguage.bundle)
        case .pngSequence: return String(localized: "A folder per clip, one \(w) × \(h) PNG per tick (holds repeated).", bundle: AppLanguage.bundle)
        case .godot: return String(localized: "PNG + SpriteFrames .tres with one animation per clip, \(w) × \(h) px frames. Keep both files together; set the AnimatedSprite2D offset for the pivot.", bundle: AppLanguage.bundle)
        }
    }
}
