import SwiftUI

/// What Calco opens on: the projects in Documents as cards that play their first clip, with the
/// most recent one up top as "Continue" (whose clips can be played one by one). Search and sort
/// up top; each card's ⋯ (or a long-press) opens, renames, duplicates, exports or deletes it. A
/// `.calco` dropped on the window is copied in and opened.
struct GalleryView: View {
    @Bindable var state: EditorState
    @State private var entries: [ProjectLibrary.Entry] = []
    @State private var previews: [URL: ProjectLibrary.Preview] = [:]
    /// The Continue card's clip previews, by clip index, loaded when picked.
    @State private var clipPreviews: [Int: ProjectLibrary.Preview] = [:]
    @State private var continueClip = 0
    @State private var search = ""
    @AppStorage("gallery.sort") private var sort = Sort.recent
    @State private var dropping = false

    enum Sort: String, CaseIterable, Identifiable {
        case recent, name, size
        var id: String { rawValue }
    }

    /// The projects in the grid: matching the search, in the chosen order; without a search, the
    /// one in Continue isn't repeated.
    private var listed: [ProjectLibrary.Entry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        var list = query.isEmpty ? Array(entries.dropFirst())
            : entries.filter { $0.name.localizedCaseInsensitiveContains(query)
                || $0.project.clips.contains { $0.name.localizedCaseInsensitiveContains(query) } }
        switch sort {
        case .recent: break
        case .name: list.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .size: list.sort { $0.project.canvas.width * $0.project.canvas.height > $1.project.canvas.width * $1.project.canvas.height }
        }
        return list
    }
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
                        if search.isEmpty {
                            ContinueCard(entry: entries[0],
                                         preview: continueClip == 0 ? previews[entries[0].url] : clipPreviews[continueClip],
                                         clip: $continueClip,
                                         open: { open(entries[0]) },
                                         export: { export(entries[0]) },
                                         duplicate: { attempt { try library.duplicate(entries[0]) } })
                                .contextMenu { menu(for: entries[0]) }
                        }
                        HStack {
                            Text(search.isEmpty ? "All projects · \(entries.count)" : "\(listed.count) found")
                                .font(.subheadline).foregroundStyle(Theme.textFaint)
                            Spacer()
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                            ForEach(listed) { entry in
                                ProjectCard(entry: entry, preview: previews[entry.url], open: { open(entry) }) {
                                    menu(for: entry)
                                }
                                .contextMenu { menu(for: entry) }
                            }
                            if search.isEmpty { NewCard(dropping: dropping) { showingNew = true } }
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
        .onChange(of: continueClip) { _, i in loadClipPreview(i) }
        // A .calco from Files dropped anywhere on the gallery: copied in and opened.
        .onDrop(of: [ProjectDocument.contentType], isTargeted: $dropping) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadFileRepresentation(forTypeIdentifier: ProjectDocument.contentType.identifier) { url, _ in
                guard let url else { return }
                // The file only exists during this call: copy it in now.
                let copied = try? library.importPackage(at: url)
                DispatchQueue.main.async {
                    reload()
                    if let copied { state.open(copied) }
                }
            }
            return true
        }
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
            Image("Logo")
                .resizable()
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            Text("Calco").font(.title2.weight(.semibold)).foregroundStyle(Theme.text)
            if !entries.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.textFaint)
                    TextField("Search projects", text: $search)
                        .textFieldStyle(.plain)
                        .foregroundStyle(Theme.text)
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .foregroundStyle(Theme.textFaint)
                            .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 10).frame(height: 34)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 9))
                .frame(maxWidth: 360)
                Menu {
                    Picker("Sort", selection: $sort) {
                        Text("Recent").tag(Sort.recent)
                        Text("Name").tag(Sort.name)
                        Text("Size").tag(Sort.size)
                    }
                } label: {
                    Label(sortTitle, systemImage: "arrow.up.arrow.down")
                        .font(.callout)
                        .foregroundStyle(Theme.textDim)
                }
            }
            Spacer()
            Button { showingImport = true } label: { Label("Open from Files", systemImage: "folder") }
                .labelStyle(.iconOnly)
                .foregroundStyle(Theme.textDim)
            Button { state.showingPreferences = true } label: { Label("Preferences", systemImage: "gearshape") }
                .labelStyle(.iconOnly)
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

    private var sortTitle: String {
        switch sort {
        case .recent: String(localized: "Recent", bundle: AppLanguage.bundle)
        case .name: String(localized: "Name", bundle: AppLanguage.bundle)
        case .size: String(localized: "Size", bundle: AppLanguage.bundle)
        }
    }

    @ViewBuilder
    private func menu(for entry: ProjectLibrary.Entry) -> some View {
        Button { open(entry) } label: { Label("Open", systemImage: "pencil.tip") }
        Button { newName = entry.name; renaming = entry } label: { Label("Rename…", systemImage: "character.cursor.ibeam") }
        Button { attempt { try library.duplicate(entry) } } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
        Button { export(entry) } label: { Label("Export…", systemImage: "square.and.arrow.up.on.square") }
        Divider()
        Button(role: .destructive) { deleting = entry } label: { Label("Delete…", systemImage: "trash") }
    }

    private func open(_ entry: ProjectLibrary.Entry) {
        state.open(entry.url)
    }

    /// Opens the project and its export sheet.
    private func export(_ entry: ProjectLibrary.Entry) {
        state.open(entry.url)
        guard !state.isInGallery else { return }
        // Once the editor is up, its file menu takes the request.
        DispatchQueue.main.async { state.request = .export }
    }

    private func loadClipPreview(_ i: Int) {
        guard i > 0, clipPreviews[i] == nil, let entry = entries.first else { return }
        Task.detached(priority: .userInitiated) {
            let preview = ProjectLibrary.preview(of: entry, clipIndex: i)
            await MainActor.run { clipPreviews[i] = preview }
        }
    }

    private func attempt(_ work: () throws -> Void) {
        do { try work() } catch { state.lastError = error.localizedDescription }
        reload()
    }

    /// Lists projects now; builds the card animations off the main thread.
    private func reload() {
        let found = library.entries()
        if found.first?.url != entries.first?.url { continueClip = 0; clipPreviews = [:] }
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
    @Binding var clip: Int
    let open: () -> Void
    let export: () -> Void
    let duplicate: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            AnimatedPreview(preview: preview).frame(width: 150, height: 150)
                .onTapGesture(perform: open)
            VStack(alignment: .leading, spacing: 4) {
                Text("Continue").font(.caption.weight(.semibold)).foregroundStyle(Theme.accentText)
                Text(entry.name).font(.title3.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                HStack(spacing: 4) {
                    Text(verbatim: "\(entry.project.canvas.width)×\(entry.project.canvas.height) · \(entry.project.fps) fps ·")
                    Text(entry.modified, format: .relative(presentation: .named))
                }
                .font(.callout).foregroundStyle(Theme.textDim).lineLimit(1)
                // Each clip plays in the preview when picked.
                HStack(spacing: 6) {
                    ForEach(Array(entry.project.clips.prefix(8).enumerated()), id: \.element.id) { i, c in
                        let on = i == clip
                        Button { clip = i } label: {
                            HStack(spacing: 3) {
                                if on { Image(systemName: "play.fill").font(.system(size: 8)) }
                                Text(c.name)
                            }
                            .font(.caption.weight(on ? .semibold : .regular))
                            .foregroundStyle(on ? Theme.accentText : Theme.textDim)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(on ? Theme.accentWash : .clear, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(on ? Theme.accent.opacity(0.6) : Theme.hairline))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(.top, 4)
                HStack(spacing: 8) {
                    Button(action: export) { Label("Export…", systemImage: "square.and.arrow.up.on.square") }
                    Button(action: duplicate) { Label("Duplicate", systemImage: "plus.square.on.square") }
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .padding(.top, 6)
            }
            Spacer()
            Button(action: open) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 52, height: 52)
                    .background(Theme.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Continue \(entry.name)")
        }
        .padding(12)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.corner))
    }
}

private struct ProjectCard<Actions: View>: View {
    let entry: ProjectLibrary.Entry
    let preview: ProjectLibrary.Preview?
    let open: () -> Void
    @ViewBuilder let actions: () -> Actions

    static func summary(_ entry: ProjectLibrary.Entry) -> String {
        let clips = entry.project.clips.count
        let c = entry.project.canvas
        let count = clips == 1 ? String(localized: "1 clip", bundle: AppLanguage.bundle) : String(localized: "\(clips) clips", bundle: AppLanguage.bundle)
        return "\(count) · \(c.width)×\(c.height) · \(entry.project.fps) fps"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AnimatedPreview(preview: preview).aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .topTrailing) {
                    // The card's actions, in sight (a long-press opens them too).
                    Menu { actions() } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(.black.opacity(0.5), in: Circle())
                            .padding(6)
                    }
                    .accessibilityLabel("Actions for \(entry.name)")
                }
            Text(entry.name).font(.callout.weight(.medium)).foregroundStyle(Theme.text).lineLimit(1)
            HStack(spacing: 4) {
                Text(entry.project.clips.count == 1 ? "1 clip ·" : "\(entry.project.clips.count) clips ·")
                Text(verbatim: "\(entry.project.canvas.width)×\(entry.project.canvas.height) ·")
                Text(entry.modified, format: .relative(presentation: .named))
            }
            .font(.caption).foregroundStyle(Theme.textFaint).lineLimit(1)
        }
        .padding(8)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.corner))
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(entry.name), \(Self.summary(entry))")
        .accessibilityAddTraits(.isButton)
    }
}

private struct NewCard: View {
    /// A .calco is being dragged over the gallery.
    var dropping = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: dropping ? "square.and.arrow.down" : "plus").font(.system(size: 24))
                Text(dropping ? "Drop to open" : "New").font(.callout)
                if !dropping {
                    Text("or drop a .calco here").font(.caption2).foregroundStyle(Theme.textFaint)
                }
            }
            .foregroundStyle(dropping ? Theme.accentText : Theme.textFaint)
            .frame(maxWidth: .infinity, minHeight: 200)
            .background(dropping ? Theme.accentWash : .clear, in: RoundedRectangle(cornerRadius: Theme.corner))
            .overlay(RoundedRectangle(cornerRadius: Theme.corner)
                .strokeBorder(dropping ? Theme.accent : Theme.hairline, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New project")
    }
}
