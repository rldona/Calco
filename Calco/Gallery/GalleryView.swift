import SwiftUI

/// What Calco opens on: the projects in Documents as cards that play their first clip, with the
/// most recent one up top as "Continue". Long-press a card to rename, duplicate or delete it.
struct GalleryView: View {
    @ObservedObject var state: EditorState
    @State private var entries: [ProjectLibrary.Entry] = []
    @State private var previews: [URL: ProjectLibrary.Preview] = [:]
    @State private var showingNew = false
    @State private var showingImport = false
    @State private var renaming: ProjectLibrary.Entry?
    @State private var newName = ""
    @State private var deleting: ProjectLibrary.Entry?

    private var library: ProjectLibrary { ProjectLibrary(directory: EditorState.documentsDirectory) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if entries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ContinueCard(entry: entries[0], preview: previews[entries[0].url]) { open(entries[0]) }
                            .contextMenu { menu(for: entries[0]) }
                        if entries.count > 1 {
                            Text("All projects").font(.subheadline).foregroundStyle(Theme.textFaint)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                            ForEach(entries.dropFirst()) { entry in
                                ProjectCard(entry: entry, preview: previews[entry.url]) { open(entry) }
                                    .contextMenu { menu(for: entry) }
                            }
                            NewCard { showingNew = true }
                        }
                    }
                    .padding(.bottom, 16)
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background.ignoresSafeArea())
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .onAppear(perform: reload)
        .onChange(of: state.isInGallery) { _, inGallery in if inGallery { reload() } }
        // ⌘N / ⌘O from CalcoCommands land here while the gallery is showing.
        .onChange(of: state.request) { _, request in
            guard state.isInGallery, let request else { return }
            state.request = nil
            if request == .newProject { showingNew = true }
            if request == .open { showingImport = true }
        }
        .sheet(isPresented: $showingNew) {
            NewProjectSheet { config in
                showingNew = false
                state.createProject(config)
            }
        }
        .fileImporter(isPresented: $showingImport, allowedContentTypes: [ProjectDocument.contentType]) { result in
            if case .success(let url) = result { state.open(url) }
        }
        .alert("Rename project", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") {
                if let e = renaming { attempt { try library.rename(e, to: newName) } }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .alert("Delete \(deleting?.name ?? "project")?",
               isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) {
                if let e = deleting { attempt { try library.delete(e) } }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text("All its clips and drawings will be removed from this iPad. This can't be undone.")
        }
        .alert("File error", isPresented: Binding(get: { state.lastError != nil },
                                                 set: { if !$0 { state.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(state.lastError ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Text("Calco").font(.title2.weight(.semibold)).foregroundStyle(Theme.text)
            Spacer()
            Button { showingImport = true } label: { Label("Open from Files", systemImage: "folder") }
                .foregroundStyle(Theme.textDim)
            Button { showingNew = true } label: {
                Label("New", systemImage: "plus")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 9))
            }
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "figure.run").font(.system(size: 48)).foregroundStyle(Theme.textFaint)
            Text("Start your first animation").font(.title3.weight(.semibold)).foregroundStyle(Theme.text)
            Text("Pick a sprite size and the clips you need. Everything saves here on its own.")
                .font(.callout).foregroundStyle(Theme.textDim).multilineTextAlignment(.center)
            Button { showingNew = true } label: {
                Text("New project")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 22).padding(.vertical, 10)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func menu(for entry: ProjectLibrary.Entry) -> some View {
        Button { open(entry) } label: { Label("Open", systemImage: "pencil.tip") }
        Button { newName = entry.name; renaming = entry } label: { Label("Rename…", systemImage: "character.cursor.ibeam") }
        Button { attempt { try library.duplicate(entry) } } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
        Divider()
        Button(role: .destructive) { deleting = entry } label: { Label("Delete…", systemImage: "trash") }
    }

    private func open(_ entry: ProjectLibrary.Entry) {
        state.open(entry.url)
    }

    private func attempt(_ work: () throws -> Void) {
        do { try work() } catch { state.lastError = error.localizedDescription }
        reload()
    }

    /// Lists projects now; builds the card animations off the main thread.
    private func reload() {
        let found = library.entries()
        entries = found
        previews = previews.filter { url, _ in found.contains { $0.url == url } }
        Task.detached(priority: .utility) {
            for entry in found {
                guard let preview = ProjectLibrary.preview(of: entry) else { continue }
                await MainActor.run { previews[entry.url] = preview }
            }
        }
    }
}

// MARK: - Cards

/// Plays a project's first clip at its own fps and holds; a still image if it has one frame.
struct AnimatedPreview: View {
    let preview: ProjectLibrary.Preview?

    var body: some View {
        ZStack {
            Theme.text
            if let preview, !preview.frames.isEmpty {
                if preview.frames.count == 1 {
                    frame(preview.frames[0], preview.aspect)
                } else {
                    SwiftUI.TimelineView(.periodic(from: .now, by: 1 / Double(max(preview.fps, 1)))) { context in
                        let i = preview.frameIndex(at: context.date.timeIntervalSinceReferenceDate)
                        frame(preview.frames[i], preview.aspect)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
    }

    private func frame(_ image: CGImage, _ aspect: CGFloat) -> some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.medium)
            .aspectRatio(aspect, contentMode: .fit)
    }
}

private struct ContinueCard: View {
    let entry: ProjectLibrary.Entry
    let preview: ProjectLibrary.Preview?
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 16) {
                AnimatedPreview(preview: preview).frame(width: 120, height: 120)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Continue").font(.caption.weight(.semibold)).foregroundStyle(Theme.accentText)
                    Text(entry.name).font(.title3.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(ProjectCard.summary(entry)).font(.callout).foregroundStyle(Theme.textDim)
                    HStack(spacing: 6) {
                        ForEach(entry.project.clips.prefix(6)) { clip in
                            Text(clip.name)
                                .font(.caption)
                                .foregroundStyle(Theme.textDim)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.hairline))
                        }
                    }
                    .padding(.top, 4)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 48, height: 48)
                    .background(Theme.accent, in: Circle())
            }
            .padding(12)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.corner))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Continue \(entry.name)")
    }
}

private struct ProjectCard: View {
    let entry: ProjectLibrary.Entry
    let preview: ProjectLibrary.Preview?
    let open: () -> Void

    static func summary(_ entry: ProjectLibrary.Entry) -> String {
        let clips = entry.project.clips.count
        let c = entry.project.canvas
        return "\(clips) \(clips == 1 ? "clip" : "clips") · \(c.width)×\(c.height) · \(entry.project.fps) fps"
    }

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 6) {
                AnimatedPreview(preview: preview).aspectRatio(1, contentMode: .fit)
                Text(entry.name).font(.callout.weight(.medium)).foregroundStyle(Theme.text).lineLimit(1)
                HStack(spacing: 4) {
                    Text("\(entry.project.clips.count) \(entry.project.clips.count == 1 ? "clip" : "clips") ·")
                    Text(entry.modified, format: .relative(presentation: .named))
                }
                .font(.caption).foregroundStyle(Theme.textFaint).lineLimit(1)
            }
            .padding(8)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.corner))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(entry.name), \(Self.summary(entry))")
    }
}

private struct NewCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 24))
                Text("New").font(.callout)
            }
            .foregroundStyle(Theme.textFaint)
            .frame(maxWidth: .infinity, minHeight: 200)
            .overlay(RoundedRectangle(cornerRadius: Theme.corner)
                .strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New project")
    }
}
