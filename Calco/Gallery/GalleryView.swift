import SwiftUI

/// What Calco opens on: the projects in Documents as cards that play their first clip, with the
/// most recent one up top as "Continue" (whose clips can be played one by one). Search and sort
/// up top; each card's ⋯ (or a long-press) opens, renames, duplicates, exports, moves or deletes
/// it. Folders, one level deep, hold projects: drag a card onto one, or onto "All projects" to
/// take it out. A `.calco` dropped on the window is copied in and opened.
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
    @State private var folders: [String] = []
    /// The folder being shown, "" for the top. Remembered across visits to the editor.
    @AppStorage("gallery.folder") private var folderName = ""
    private var folder: String? { folderName.isEmpty ? nil : folderName }
    /// A project card is being dragged over this folder, or over "All projects".
    @State private var dropFolder: String?
    @State private var dropTop = false
    @State private var moves = 0
    @State private var naming: FolderNaming?
    @State private var folderText = ""
    @State private var deletingFolder: String?

    private enum FolderNaming: Equatable {
        /// A new folder, and the project to move into it once it's made.
        case new(moving: URL?)
        case rename(String)
    }

    enum Sort: String, CaseIterable, Identifiable {
        case recent, name, size
        var id: String { rawValue }
    }

    /// The projects in the grid: matching the search (everywhere at the top, inside the folder in
    /// one), in the chosen order. Without a search, the folder's projects, or at the top the ones in
    /// no folder but the one in Continue.
    private var listed: [ProjectLibrary.Entry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        var list: [ProjectLibrary.Entry]
        if !query.isEmpty {
            list = entries.filter { (folder == nil || $0.folder == folder)
                && ($0.name.localizedCaseInsensitiveContains(query)
                    || $0.project.clips.contains { $0.name.localizedCaseInsensitiveContains(query) }) }
        } else if let folder {
            list = entries.filter { $0.folder == folder }
        } else {
            list = entries.filter { $0.folder == nil && $0.url != entries.first?.url }
        }
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
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if entries.isEmpty && folders.isEmpty { welcome }
                    if search.isEmpty, folder == nil, !entries.isEmpty {
                        ContinueCard(entry: entries[0],
                                     preview: continueClip == 0 ? previews[entries[0].url] : clipPreviews[continueClip],
                                     clip: $continueClip,
                                     open: { open(entries[0]) },
                                     export: { export(entries[0]) },
                                     duplicate: { attempt { try library.duplicate(entries[0]) } })
                            .contextMenu { menu(for: entries[0]) }
                    }
                    if let folder {
                        breadcrumb(folder)
                    } else if search.isEmpty {
                        // Making a folder is always one tap away, first in the row.
                        sectionTitle("Folders · \(folders.count)")
                        LazyVGrid(columns: columns, spacing: 12) {
                            NewFolderCard { startNewFolder(moving: nil) }
                            ForEach(folders, id: \.self) { name in folderCard(name) }
                        }
                    }
                    if !search.isEmpty {
                        sectionTitle("\(listed.count) found")
                    } else if folder == nil {
                        sectionTitle("Projects · \(listed.count)")
                    } else if listed.isEmpty {
                        Text("This folder is empty. Drag projects here from All projects, or make a new one.")
                            .font(.callout).foregroundStyle(Theme.textDim)
                    }
                    LazyVGrid(columns: columns, spacing: 12) {
                        // Likewise a new project, first in the grid.
                        if search.isEmpty { NewCard(dropping: dropping) { showingNew = true } }
                        ForEach(listed) { entry in
                            ProjectCard(entry: entry, preview: previews[entry.url],
                                        place: search.isEmpty || folder != nil ? nil : entry.folder,
                                        open: { open(entry) }) {
                                menu(for: entry)
                            }
                            .contextMenu { menu(for: entry) }
                            .draggable(entry.url) {
                                AnimatedPreview(preview: previews[entry.url]).frame(width: 120, height: 120)
                            }
                        }
                    }
                }
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background.ignoresSafeArea())
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .onAppear(perform: reload)
        .sensoryFeedback(.success, trigger: moves)
        .sensoryFeedback(.selection, trigger: dropFolder) { _, new in new != nil }
        .animation(.easeOut(duration: 0.15), value: dropFolder)
        .onChange(of: continueClip) { _, i in loadClipPreview(i) }
        // A .calco from Files dropped anywhere on the gallery: copied in and opened.
        .onDrop(of: [ProjectDocument.contentType], isTargeted: $dropping) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadFileRepresentation(forTypeIdentifier: ProjectDocument.contentType.identifier) { url, _ in
                guard let url else { return }
                // The file only exists during this call: copy it in now.
                let copied = try? library.importPackage(at: url, into: folder)
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
                state.createProject(config, in: library.folderURL(folder))
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
        .alert(namingTitle, isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("Name", text: $folderText)
            Button(namingIsNew ? "Create" : "Rename") { finishNaming() }
            Button("Cancel", role: .cancel) { naming = nil }
        }
        .alert("Delete the folder \(deletingFolder ?? "")?",
               isPresented: Binding(get: { deletingFolder != nil }, set: { if !$0 { deletingFolder = nil } })) {
            Button("Delete", role: .destructive) {
                if let f = deletingFolder {
                    attempt { try library.deleteFolder(f) }
                    if folder == f { folderName = "" }
                }
                deletingFolder = nil
            }
            Button("Cancel", role: .cancel) { deletingFolder = nil }
        } message: {
            Text("Its projects aren't deleted: they go back to All projects.")
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
            if !entries.isEmpty || !folders.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.textFaint)
                    TextField(folder == nil ? "Search projects" : "Search in this folder", text: $search)
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
            if folder == nil, !entries.isEmpty || !folders.isEmpty {
                Button { startNewFolder(moving: nil) } label: { Label("New folder", systemImage: "folder.badge.plus") }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(Theme.textDim)
            }
            Button { showingImport = true } label: { Label("Open from Files", systemImage: "square.and.arrow.down") }
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

    /// Above the shortcuts the first time, before there's anything else.
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Start your first animation").font(.title3.weight(.semibold)).foregroundStyle(Theme.text)
            Text("Pick a sprite size and the clips you need. Everything saves here on its own.")
                .font(.callout).foregroundStyle(Theme.textDim)
        }
        .padding(.vertical, 8)
    }

    private var sortTitle: String {
        switch sort {
        case .recent: String(localized: "Recent", bundle: AppLanguage.bundle)
        case .name: String(localized: "Name", bundle: AppLanguage.bundle)
        case .size: String(localized: "Size", bundle: AppLanguage.bundle)
        }
    }

    private var columns: [GridItem] { [GridItem(.adaptive(minimum: 170), spacing: 12)] }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title).font(.subheadline).foregroundStyle(Theme.textFaint)
    }

    /// Inside a folder: back to the top (a project dropped there leaves the folder), its name and
    /// its actions.
    private func breadcrumb(_ folder: String) -> some View {
        HStack(spacing: 8) {
            Button { folderName = ""; search = "" } label: {
                Label("All projects", systemImage: "chevron.left")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(dropTop ? Theme.accentText : Theme.textDim)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(dropTop ? Theme.accentWash : Theme.panel, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(dropTop ? Theme.accent : .clear))
            }
            .buttonStyle(.plain)
            .dropDestination(for: URL.self) { urls, _ in moveDropped(urls, to: nil) } isTargeted: { dropTop = $0 }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textFaint)
            Label(folder, systemImage: "folder").font(.headline).foregroundStyle(Theme.text)
            Text(verbatim: "· \(entries.filter { $0.folder == folder }.count)").foregroundStyle(Theme.textFaint)
            Menu { folderMenu(folder) } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 18)).foregroundStyle(Theme.textDim)
                    .frame(width: 34, height: 34)
            }
            .accessibilityLabel("Actions for \(folder)")
            Spacer()
        }
    }

    private func folderCard(_ name: String) -> some View {
        let inside = entries.filter { $0.folder == name }
        return FolderCard(name: name, count: inside.count,
                          thumbnails: inside.prefix(4).map { previews[$0.url]?.frames.first },
                          targeted: dropFolder == name,
                          open: { folderName = name; search = "" }) { folderMenu(name) }
            .contextMenu { folderMenu(name) }
            .dropDestination(for: URL.self) { urls, _ in moveDropped(urls, to: name) } isTargeted: { on in
                if on { dropFolder = name } else if dropFolder == name { dropFolder = nil }
            }
    }

    @ViewBuilder
    private func folderMenu(_ name: String) -> some View {
        if folder != name {
            Button { folderName = name; search = "" } label: { Label("Open", systemImage: "folder") }
        }
        Button { folderText = name; naming = .rename(name) } label: { Label("Rename…", systemImage: "character.cursor.ibeam") }
        Divider()
        Button(role: .destructive) { deletingFolder = name } label: { Label("Delete…", systemImage: "trash") }
    }

    @ViewBuilder
    private func menu(for entry: ProjectLibrary.Entry) -> some View {
        Button { open(entry) } label: { Label("Open", systemImage: "pencil.tip") }
        Button { newName = entry.name; renaming = entry } label: { Label("Rename…", systemImage: "character.cursor.ibeam") }
        Button { attempt { try library.duplicate(entry) } } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
        Button { export(entry) } label: { Label("Export…", systemImage: "square.and.arrow.up.on.square") }
        Menu {
            if entry.folder != nil {
                Button { move(entry, to: nil) } label: { Label("All projects", systemImage: "square.grid.2x2") }
            }
            ForEach(folders.filter { $0 != entry.folder }, id: \.self) { name in
                Button { move(entry, to: name) } label: { Label(name, systemImage: "folder") }
            }
            Divider()
            Button { startNewFolder(moving: entry.url) } label: { Label("New folder…", systemImage: "folder.badge.plus") }
        } label: { Label("Move to", systemImage: "folder") }
        Divider()
        Button(role: .destructive) { deleting = entry } label: { Label("Delete…", systemImage: "trash") }
    }

    // MARK: - Folders

    private var namingIsNew: Bool { if case .new = naming { true } else { false } }

    private var namingTitle: LocalizedStringKey { namingIsNew ? "New folder" : "Rename folder" }

    private func startNewFolder(moving: URL?) {
        folderText = ""
        naming = .new(moving: moving)
    }

    private func finishNaming() {
        let text = folderText
        switch naming {
        case .new(let moving):
            // No name: "New folder", numbered if there's one already.
            let name = ProjectLibrary.cleanFolderName(text).isEmpty
                ? String(localized: "New folder", bundle: AppLanguage.bundle) : text
            attempt {
                let made = try library.createFolder(name)
                if let moving, let entry = entries.first(where: { $0.url == moving }) {
                    try library.move(entry, to: made)
                    moves += 1
                }
            }
        case .rename(let old):
            attempt {
                let renamed = try library.renameFolder(old, to: text)
                if folder == old { folderName = renamed }
            }
        case nil: break
        }
        naming = nil
    }

    private func move(_ entry: ProjectLibrary.Entry, to folder: String?) {
        attempt { try library.move(entry, to: folder) }
        moves += 1
    }

    /// Projects of this gallery dragged onto a folder (or onto "All projects": nil).
    private func moveDropped(_ urls: [URL], to folder: String?) -> Bool {
        let wanted = Set(urls.map(\.standardizedFileURL))
        let moving = entries.filter { wanted.contains($0.url.standardizedFileURL) && $0.folder != folder }
        dropFolder = nil; dropTop = false
        guard !moving.isEmpty else { return false }
        attempt { for entry in moving { try library.move(entry, to: folder) } }
        moves += 1
        return true
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
        folders = library.folders()
        if let folder, !folders.contains(folder) { folderName = "" }
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
                HStack(spacing: 6) {
                    Text("Continue").font(.caption.weight(.semibold)).foregroundStyle(Theme.accentText)
                    if let folder = entry.folder {
                        Label(folder, systemImage: "folder").font(.caption).foregroundStyle(Theme.textFaint)
                    }
                }
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
    /// The folder it's in, shown in search results.
    var place: String?
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
            if let place {
                Label(place, systemImage: "folder").font(.caption2).foregroundStyle(Theme.textDim).lineLimit(1)
            }
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

/// A folder: a peek at its first four projects, its name and how many it holds. Lights up while
/// a project is dragged over it.
private struct FolderCard<Actions: View>: View {
    let name: String
    let count: Int
    let thumbnails: [CGImage?]
    var targeted = false
    let open: () -> Void
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                ForEach(0..<2, id: \.self) { row in
                    GridRow {
                        ForEach(0..<2, id: \.self) { col in tile(row * 2 + col) }
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .topTrailing) {
                Menu { actions() } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(.black.opacity(0.5), in: Circle())
                        .padding(6)
                }
                .accessibilityLabel("Actions for \(name)")
            }
            Label(name, systemImage: "folder")
                .font(.callout.weight(.medium))
                .foregroundStyle(targeted ? Theme.accentText : Theme.text)
                .lineLimit(1)
            Text(targeted ? "Drop to move" : (count == 1 ? "1 project" : "\(count) projects"))
                .font(.caption).foregroundStyle(targeted ? Theme.accentText : Theme.textFaint).lineLimit(1)
        }
        .padding(8)
        .background(targeted ? Theme.accentWash : Theme.panel, in: RoundedRectangle(cornerRadius: Theme.corner))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner).strokeBorder(Theme.accent, lineWidth: targeted ? 2 : 0))
        .scaleEffect(targeted ? 1.03 : 1)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityAddTraits(.isButton)
    }

    private func tile(_ i: Int) -> some View {
        ZStack {
            if i < thumbnails.count {
                Theme.text
                if let image = thumbnails[i] {
                    Image(decorative: image, scale: 1).resizable().interpolation(.medium).scaledToFit()
                }
            } else {
                Theme.raised.opacity(0.5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct NewFolderCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: "folder.badge.plus").font(.system(size: 24))
                Text("New folder").font(.callout)
            }
            .foregroundStyle(Theme.textFaint)
            .frame(maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
            .overlay(RoundedRectangle(cornerRadius: Theme.corner)
                .strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        }
        .buttonStyle(.plain)
    }
}

private struct NewCard: View {
    /// A .calco is being dragged over the gallery.
    var dropping = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: dropping ? "square.and.arrow.down" : "pencil.tip").font(.system(size: 24))
                Text(dropping ? "Drop to open" : "New project").font(.callout)
                if !dropping {
                    Text("or drop a .calco here").font(.caption2).foregroundStyle(Theme.textFaint)
                }
            }
            .foregroundStyle(dropping ? Theme.accentText : Theme.textFaint)
            .frame(maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
            .background(dropping ? Theme.accentWash : .clear, in: RoundedRectangle(cornerRadius: Theme.corner))
            .overlay(RoundedRectangle(cornerRadius: Theme.corner)
                .strokeBorder(dropping ? Theme.accent : Theme.hairline, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New project")
    }
}
