import SwiftUI

/// "Export…": pick or tweak a profile, then export. Edits save straight into the profile, so the
/// next project exports the same way; "Export again" (⇧⌘E) reruns the last one without this sheet.
struct ExportProfilesSheet: View {
    @ObservedObject var state: EditorState
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
    @ObservedObject var state: EditorState
    @Binding var profile: ExportProfile

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
                if profile.target == .spriteSheet {
                    Toggle("Trim transparent borders", isOn: $profile.trim)
                    Stepper("Padding \(profile.padding) px", value: $profile.padding, in: 0...16)
                    Toggle("Power-of-two sheet", isOn: $profile.powerOfTwo)
                }
            } header: {
                Text("Pixels")
            } footer: {
                Text(footnote).font(.caption)
            }
        }
    }

    private var footnote: String {
        let w = Int((Double(state.project.canvas.width) * profile.scale).rounded())
        let h = Int((Double(state.project.canvas.height) * profile.scale).rounded())
        switch profile.target {
        case .spriteSheet:
            return "Frames \(w) × \(h) px\(profile.trim ? " before trimming. Each clip is trimmed to the box its drawings use; the JSON keeps the pivot in place for Unity" : "")."
        case .gif: return "One GIF per clip, \(w) × \(h) px."
        case .pngSequence: return "A folder per clip, one \(w) × \(h) PNG per tick (holds repeated)."
        }
    }
}
