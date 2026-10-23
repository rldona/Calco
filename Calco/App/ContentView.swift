import SwiftUI
import Metal

/// Estudio layout: the canvas fills the whole screen and the panels float over it, Procreate
/// style: tools on the left and animation on the right, both centred, and a narrower timeline at
/// the bottom. In portrait the tools lie across the top and the animation rail above the timeline. The drawing fits in the space the
/// panels leave free. Zen mode hides all of it except a small floating bar.
struct ContentView: View {
    @Bindable var state: EditorState
    @State private var latencyMs: Double = 0
    /// Where each floating panel is, to keep the drawing out from under them.
    @State private var panels: [PanelSlot: CGRect] = [:]

    @AppStorage("timeline.collapsed") private var timelineCollapsed = false

    var body: some View {
        GeometryReader { geo in
            let portrait = geo.size.height > geo.size.width
            ZStack {
                canvas
                if !state.isZen {
                    TopBar(state: state, latencyMs: latencyMs)
                        .reportFrame(.top)
                        .padding(.horizontal, Theme.gap).padding(.top, Theme.gap)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    // The rails float centred on each side, whatever the timeline does. In portrait,
                    // where width is what the canvas lacks, the tools lie across the top instead.
                    if portrait {
                        ToolRail(state: state, axis: .horizontal)
                            .reportFrame(.tools)
                            .padding(.top, Self.topBarRoom)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    } else {
                        ToolRail(state: state)
                            .reportFrame(.left)
                            .padding(.leading, Theme.gap)
                            .padding(.vertical, Self.topBarRoom)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    if !portrait {
                        AnimationRail(state: state, axis: .vertical)
                            .reportFrame(.right)
                            .padding(.trailing, Theme.gap)
                            .padding(.vertical, Self.topBarRoom)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                    VStack(spacing: Theme.gap) {
                        if portrait { AnimationRail(state: state, axis: .horizontal) }
                        TimelineView(state: state)
                    }
                    .frame(maxWidth: portrait ? geo.size.width - 2 * Theme.gap : Self.timelineWidth)
                    .reportFrame(.bottom)
                    .padding(.bottom, Theme.gap)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .coordinateSpace(name: Self.space)
            .onPreferenceChange(PanelFramesKey.self) { panels = $0 }
            .onChange(of: panels) { _, _ in updateInsets(size: geo.size, portrait: portrait) }
            .onChange(of: geo.size) { _, size in updateInsets(size: size, portrait: size.height > size.width) }
            .onChange(of: state.isZen) { _, _ in updateInsets(size: geo.size, portrait: portrait) }
        }
        .background(Theme.background.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.22), value: state.isZen)
        .animation(.easeInOut(duration: 0.22), value: timelineCollapsed)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }

    static let space = "editor"
    /// Room the rails leave above and below them: the top bar's height, and the same below.
    private static let topBarRoom: CGFloat = 52
    /// The timeline floats narrower than the screen, centred under the canvas.
    private static let timelineWidth: CGFloat = 820

    /// The canvas fits in what the panels leave free, with a gap.
    private func updateInsets(size: CGSize, portrait: Bool) {
        var insets = CanvasTransform.Insets()
        if !state.isZen {
            let g = Theme.gap * 2
            if let r = panels[.top] { insets.top = r.maxY + g }
            if let r = panels[.bottom] { insets.bottom = size.height - r.minY + g }
            if portrait {
                // Tools across the top: the drawing gets the whole width.
                if let r = panels[.tools] { insets.top = max(insets.top, r.maxY + g) }
                insets.left = Theme.gap
                insets.right = Theme.gap
            } else {
                if let r = panels[.left] { insets.left = r.maxX + g }
                if let r = panels[.right] { insets.right = size.width - r.minX + g }
            }
        }
        if state.canvasTransform.insets != insets { state.canvasTransform.insets = insets }
    }

    private var canvas: some View {
        CanvasView(state: state, latencyMs: $latencyMs)
            .ignoresSafeArea()
            // Drawn over the canvas in its own space: the whole screen, like the canvas, or what
            // they draw would sit a little off it, more so the further from the middle.
            .overlay {
                if state.showPivot { PivotOverlay(state: state).ignoresSafeArea() }
            }
            .overlay { GridOverlay(state: state).ignoresSafeArea() }
            .overlay { SymmetryOverlay(state: state).ignoresSafeArea() }
            .overlay { SelectionOverlay(state: state).ignoresSafeArea() }
            // Above the selection, so the arc's handle can be grabbed; nothing else catches touches.
            .overlay { TweenOverlay(state: state).ignoresSafeArea() }
            .overlay { ShapeDraftOverlay(state: state).ignoresSafeArea() }
            .overlay { PenOverlay(state: state).ignoresSafeArea() }
            .overlay(alignment: .bottom) {
                if state.penEditing != nil {
                    PenBar(state: state)
                        .padding(.bottom, state.bottomInset + 6)
                } else if state.tween != nil {
                    TweenBar(state: state)
                        .padding(.bottom, state.bottomInset + 6)
                } else if state.frameRange != nil {
                    FrameRangeBar(state: state)
                        .padding(.bottom, state.bottomInset + 6)
                } else if state.tool == .move, let id = state.moveBlockedLayer,
                   let layer = state.layers.first(where: { $0.id == id }) {
                    MoveLockedHint(state: state, layerName: layer.name)
                        .padding(.bottom, state.bottomInset + 6)
                } else if state.tool == .move && state.hasSelection {
                    MoveStrokesHint(state: state)
                        .padding(.bottom, state.bottomInset + 6)
                } else if let notice = state.selectNotice {
                    Label(notice, systemImage: "exclamationmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 13))
                        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Theme.hairline))
                        .padding(.bottom, state.bottomInset + 6)
                        .transition(.opacity)
                } else if state.tool == .lasso && !state.hasSelection {
                    SelectModeBar(state: state)
                        .padding(.bottom, state.bottomInset + 6)
                } else if state.hasSelection {
                    ScaleModePicker()
                        .padding(3)
                        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 13))
                        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Theme.hairline))
                        .padding(.bottom, state.bottomInset + 6)
                }
            }
            .overlay(alignment: .top) {
                if state.isZen { ZenBar(state: state).padding(.top, 6) }
            }
            .overlay(alignment: .bottomTrailing) {
                if state.isZen {
                    Text("\(state.clip.name) · \(state.frameIndex + 1) / \(state.frames.count)")
                        .font(.caption)
                        .foregroundStyle(Theme.textFaint)
                        .padding(10)
                }
            }
    }
}

/// Document on the left; symmetry and view toggles (fit, flip, Zen) on the right.
struct TopBar: View {
    @Bindable var state: EditorState
    let latencyMs: Double
    @AppStorage("showLatency") private var showLatency = false
    @State private var editingSymmetry = false
    @State private var editingGrid = false

    var body: some View {
        HStack(spacing: 16) {
            FileMenu(state: state)
            Spacer()
            if !state.canvasIsFit {
                Button { state.fitCanvas() } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                }
                .help("Fit canvas")
            }
            Button { editingGrid = true } label: {
                Image(systemName: "square.grid.3x3.topleft.filled")
                    .foregroundStyle(state.project.grid != nil ? Theme.accent : Theme.textDim)
            }
            .help("Grid: move things in steps")
            .accessibilityLabel("Grid")
            .popover(isPresented: $editingGrid) { GridPanel(state: state) }
            Button { editingSymmetry = true } label: {
                Image(systemName: state.project.symmetry?.mode == .horizontal ? "square.split.1x2"
                                  : state.project.symmetry?.mode == .both ? "square.grid.2x2" : "square.split.2x1")
                    .foregroundStyle(state.project.symmetry != nil ? Theme.accent : Theme.textDim)
            }
            .help("Symmetry: paint with a mirror")
            .accessibilityLabel("Symmetry")
            .popover(isPresented: $editingSymmetry) { SymmetryPanel(state: state) }
            Button { state.canvasTransform.flipped.toggle() } label: {
                Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                    .foregroundStyle(state.viewFlipped ? Theme.accent : Theme.textDim)
            }
            .help("Flip the view (H): see the drawing mirrored without changing it")
            .accessibilityLabel(state.viewFlipped ? "Unflip view" : "Flip view")
            Button { state.isZen = true } label: {
                Label("Zen", systemImage: "circle.dashed.inset.filled")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .overlay(Capsule().strokeBorder(Theme.textFaint, lineWidth: 1))
            }
            .help("Zen mode: hide everything but the canvas")
            if showLatency {
                Text(String(format: "%.1f ms", latencyMs))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Theme.textFaint)
                    .frame(width: 44, alignment: .trailing)
            }
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Theme.textDim)
        .padding(.horizontal, 6)
        .frame(height: 30)
    }
}

/// Move on a locked layer (an imported image, say): one tap unlocks it for this move.
struct MoveLockedHint: View {
    @Bindable var state: EditorState
    let layerName: String

    var body: some View {
        HStack(spacing: 12) {
            Label("\(layerName) is locked", systemImage: "lock.fill")
                .font(.subheadline)
                .foregroundStyle(Theme.text)
            Button { state.unlockAndMove() } label: {
                Text("Unlock and move")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Theme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 16).padding(.trailing, 6).padding(.vertical, 6)
        .background(Theme.panel, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline))
    }
}

/// Under the canvas while Move holds something: which stroke of the ones under the finger it
/// is, the switch to pick several, and how the corner scales.
/// Under the canvas while Select is on: how it marks (lasso, rectangle, wand), how a new mark
/// meets the selection, the wand's tolerance, and Paste once something is copied. Always in
/// view, so the modes don't hide in the tool's panel.
struct SelectModeBar: View {
    @Bindable var state: EditorState

    var body: some View {
        HStack(spacing: 6) {
            segment {
                ForEach(EditorState.SelectOptions.Shape.allCases) { shape in
                    option(on: state.select.shape == shape, label: shape.title) {
                        Image(systemName: shape.icon)
                    } action: { state.select.shape = shape }
                }
            }
            segment {
                ForEach(SelectionMask.Combine.allCases) { c in
                    option(on: state.select.combine == c, label: c.title) {
                        Text(c.title)
                    } action: { state.select.combine = c }
                }
            }
            if state.select.shape == .wand {
                segment {
                    option(on: !state.select.wandBlock, label: String(localized: "By colour", bundle: AppLanguage.bundle)) {
                        Text("By colour")
                    } action: { state.select.wandBlock = false }
                    option(on: state.select.wandBlock, label: String(localized: "Block", bundle: AppLanguage.bundle)) {
                        Text("Block")
                    } action: { state.select.wandBlock = true }
                }
            }
            if state.select.shape == .wand && !state.select.wandBlock {
                HStack(spacing: 6) {
                    Text("Tolerance").foregroundStyle(Theme.textDim)
                    Slider(value: $state.select.tolerance, in: 0...1, step: 0.01).frame(width: 110)
                    Text(verbatim: "\(Int((state.select.tolerance * 100).rounded())) %")
                        .monospacedDigit().foregroundStyle(Theme.textDim).frame(width: 40, alignment: .trailing)
                }
                .font(.subheadline)
                .padding(.horizontal, 6)
            }
            if state.clipboard != nil && state.selectionMask == nil {
                Button { state.paste() } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 9))
                        .fixedSize()
                }
                .buttonStyle(.plain)
                .help("Floats what you copied where it was, on this frame and layer")
            }
        }
        .padding(4)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Theme.hairline))
    }

    private func segment<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 2) { content() }
            .padding(3)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10))
    }

    private func option<Label: View>(on: Bool, label: String, @ViewBuilder _ content: () -> Label,
                                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            content()
                .font(.subheadline.weight(on ? .semibold : .regular))
                .foregroundStyle(on ? Theme.text : Theme.textDim)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(on ? Theme.panel : .clear, in: RoundedRectangle(cornerRadius: 7))
                .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

struct MoveStrokesHint: View {
    @Bindable var state: EditorState

    private var caption: String {
        guard let hint = state.moveHint else { return String(localized: "The whole drawing", bundle: AppLanguage.bundle) }
        if hint.selected > 1 { return String(localized: "\(hint.selected) strokes", bundle: AppLanguage.bundle) }
        if hint.here > 1 {
            return String(localized: "Stroke \(hint.number) of \(hint.here) here · tap again for the one below", bundle: AppLanguage.bundle)
        }
        return String(localized: "One stroke", bundle: AppLanguage.bundle)
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(caption)
                .font(.subheadline)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .fixedSize()
            Button { state.addingStrokes.toggle() } label: {
                Label(state.addingStrokes ? "Adding" : "Add strokes",
                      systemImage: state.addingStrokes ? "checkmark" : "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(state.addingStrokes ? Theme.onAccent : Theme.text)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(state.addingStrokes ? Theme.accent : Theme.raised, in: RoundedRectangle(cornerRadius: 9))
                    .fixedSize()
            }
            .buttonStyle(.plain)
            .accessibilityValue(state.addingStrokes ? "On" : "Off")
            .help("Taps add strokes to what you're moving, or take them out")
            Divider().overlay(Theme.hairline).frame(height: 22)
            ScaleModePicker()
        }
        .padding(.leading, 14).padding(.trailing, 5).padding(.vertical, 5)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Theme.hairline))
    }
}

/// Zen mode's only chrome: undo / redo, every tool, the colour, and the way back.
struct ZenBar: View {
    @Bindable var state: EditorState
    @State private var editingColor = false

    var body: some View {
        HStack(spacing: 4) {
            RailButton(icon: "arrow.uturn.backward", label: "Undo", size: 34) { state.undo() }
                .opacity(state.canUndo ? 1 : 0.35)
            RailButton(icon: "arrow.uturn.forward", label: "Redo", size: 34) { state.redo() }
                .opacity(state.canRedo ? 1 : 0.35)
            Divider().overlay(Theme.hairline).frame(height: 20).padding(.horizontal, 2)
            RailButton(icon: state.brush.icon, label: "Brush", active: state.tool == .brush, size: 34) { state.tool = .brush }
            RailButton(icon: "eraser", label: "Eraser", active: state.tool == .eraser, size: 34) { state.tool = .eraser }
            RailButton(icon: "FillBucket", label: "Fill", active: state.tool == .fill, size: 34) { state.tool = .fill }
            RailButton(icon: "eyedropper", label: "Eyedropper", active: state.tool == .eyedropper, size: 34) { state.tool = .eyedropper }
            RailButton(icon: state.select.shape.icon, label: "Select", active: state.tool == .lasso, size: 34) { state.tool = .lasso }
            RailButton(icon: "arrow.up.and.down.and.arrow.left.and.right", label: "Move", active: state.tool == .move, size: 34) {
                if state.tool == .move { state.liftForMove() } else { state.tool = .move }
            }
            RailButton(icon: state.shapeOptions.kind.icon, label: "Shapes", active: state.tool == .shape, size: 34) {
                state.tool = .shape
            }
            RailButton(icon: ToolRail.penIcon, label: "Pen", active: state.tool == .pen, size: 34) { state.tool = .pen }
            RailButton(icon: ToolRail.nodeIcon, label: "Node", active: state.tool == .node, size: 34) { state.tool = .node }
            RailButton(icon: ToolRail.smudgeIcon, label: "Smudge", active: state.tool == .smudge, size: 34) { state.tool = .smudge }
            ColorSwatch(state: state, editing: $editingColor, diameter: 20)
            Divider().overlay(Theme.hairline).frame(height: 20).padding(.horizontal, 2)
            RailButton(icon: "arrow.down.right.and.arrow.up.left.circle", label: "Leave Zen mode", size: 34) {
                state.isZen = false
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(Theme.panel, in: Capsule())
    }
}

/// New / Open / Save / Save As, plus the project name with an unsaved-changes dot.
struct FileMenu: View {
    @Bindable var state: EditorState
    @State private var showingOpen = false
    @State private var showingSaveAs = false
    @State private var showingNewProject = false
    @State private var saveAsName = ""
    @State private var exported: [URL] = []
    @State private var exportTitle = ""
    @State private var showingExport = false
    @State private var showingProfiles = false
    @State private var showingCanvasSize = false

    var body: some View {
        Menu {
            Button { state.closeToGallery() } label: { Label("All projects", systemImage: "square.grid.2x2") }
            Button { state.showingPreferences = true } label: { Label("Preferences…", systemImage: "gearshape") }
            Button { state.request = .newProject } label: { Label("New project…", systemImage: "plus") }
            Button { state.request = .open } label: { Label("Open from Files…", systemImage: "folder") }
            Divider()
            Button { state.save() } label: { Label("Save", systemImage: "square.and.arrow.down") }
            Button { state.request = .saveAs } label: {
                Label("Save As…", systemImage: "square.and.arrow.down.on.square")
            }
            Button { showingCanvasSize = true } label: {
                Label("Canvas size…", systemImage: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left")
            }
            Divider()
            Button { state.request = .export } label: {
                Label("Export…", systemImage: "square.and.arrow.up.on.square")
            }
            if let last = state.lastExportProfile {
                Button { state.request = .exportAgain } label: {
                    Label("Export again · \(last.name)", systemImage: "arrow.clockwise")
                }
            }
            Button { state.request = .exportGIF } label: {
                Label("Export GIF (\(state.clip.name))…", systemImage: "film")
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "folder")
                Text(state.project.name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                if state.isDirty {
                    Circle().frame(width: 6, height: 6).foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: state.request) { _, request in
            guard let request else { return }
            state.request = nil
            handle(request)
        }
        // A request made just before the editor came up (Export from the gallery).
        .onAppear {
            guard let request = state.request else { return }
            state.request = nil
            handle(request)
        }
        .fileImporter(isPresented: $showingOpen, allowedContentTypes: [ProjectDocument.contentType]) { result in
            if case .success(let url) = result { state.open(url) }
        }
        .alert("Save As", isPresented: $showingSaveAs) {
            TextField("Project name", text: $saveAsName)
            Button("Save") { state.saveAs(name: saveAsName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saved to On My iPad › Calco as a .calco package.")
        }
        .sheet(isPresented: $showingProfiles) {
            ExportProfilesSheet(state: state) { urls, name in
                exported = urls
                exportTitle = name
                showingExport = true
            }
        }
        .sheet(isPresented: $showingCanvasSize) { CanvasSizeSheet(state: state) }
        .sheet(isPresented: $showingExport) {
            ExportSheet(title: exportTitle, urls: exported, name: state.project.name)
        }
        .sheet(isPresented: $showingNewProject) {
            NewProjectSheet { config in
                showingNewProject = false
                // The current project has a file (it's in the gallery), so saving keeps its work.
                state.saveIfNeeded()
                state.createProject(config)
            }
        }
        .alert("File error", isPresented: Binding(
            get: { state.lastError != nil },
            set: { if !$0 { state.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(state.lastError ?? "")
        }
    }

    /// Same path for the menu items and the keyboard shortcuts (CalcoCommands).
    private func handle(_ request: EditorState.Request) {
        switch request {
        case .newProject:
            showingNewProject = true
        case .open:
            showingOpen = true
        case .saveAs:
            saveAsName = state.project.name
            showingSaveAs = true
        case .export:
            showingProfiles = true
        case .exportAgain:
            if let profile = state.lastExportProfile, let urls = state.export(profile) {
                exported = urls
                exportTitle = profile.name
                showingExport = true
            }
        case .exportGIF:
            if let url = state.exportGIF() {
                exported = [url]
                exportTitle = "GIF · \(state.clip.name)"
                showingExport = true
            }
        }
    }
}

/// Shows the exported PNG + JSON and hands them to the share sheet (AirDrop, Files, Unity project…).
struct ExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let urls: [URL]
    let name: String

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let png = urls.first, let image = UIImage(contentsOfFile: png.path) {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .background(Color.white.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .frame(maxHeight: 320)
                    Text("\(Int(image.size.width)) × \(Int(image.size.height)) px")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(urls, id: \.self) { url in
                        Label(url.lastPathComponent, systemImage: icon(for: url))
                            .font(.callout)
                    }
                }
                Text("Also saved in On My iPad › Calco › Exports › \(name).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                ShareLink(items: urls) {
                    Label(shareTitle, systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var shareTitle: String {
        if urls.count == 1, urls[0].hasDirectoryPath { return String(localized: "Share folder", bundle: AppLanguage.bundle) }
        if urls.map(\.pathExtension) == ["png", "json"] { return String(localized: "Share PNG + JSON", bundle: AppLanguage.bundle) }
        return urls.count == 1 ? String(localized: "Share \(urls[0].pathExtension.uppercased())", bundle: AppLanguage.bundle)
            : String(localized: "Share \(urls.count) files", bundle: AppLanguage.bundle)
    }

    private func icon(for url: URL) -> String {
        if url.hasDirectoryPath { return "folder" }
        switch url.pathExtension {
        case "png": return "photo"
        case "gif": return "film"
        default: return "doc.text"
        }
    }
}

/// Draggable pivot marker drawn in canvas space. Only the handle takes touches; the rest passes to the canvas.
struct PivotOverlay: View {
    @Bindable var state: EditorState
    @GestureState private var dragging = false

    var body: some View {
        GeometryReader { geo in
            let canvas = state.renderer.canvasSize
            let w = CGFloat(canvas.x), h = CGFloat(canvas.y)
            let toView = state.canvasTransform.canvasToView(canvas: canvas, viewSize: geo.size)
            let pivot = state.clip.pivot
            // Pivot origin is bottom-left; canvas pixels are top-left.
            let point = CGPoint(x: w * pivot.x, y: h * (1 - pivot.y)).applying(toView)
            let guideX = (CGPoint(x: 0, y: h * (1 - pivot.y)).applying(toView),
                          CGPoint(x: w, y: h * (1 - pivot.y)).applying(toView))
            let guideY = (CGPoint(x: w * pivot.x, y: 0).applying(toView),
                          CGPoint(x: w * pivot.x, y: h).applying(toView))

            ZStack {
                // Guides across the canvas
                Path { p in
                    p.move(to: guideX.0); p.addLine(to: guideX.1)
                    p.move(to: guideY.0); p.addLine(to: guideY.1)
                }
                .stroke(Theme.accent.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .allowsHitTesting(false)

                Circle()
                    .fill(Theme.accent.opacity(dragging ? 0.95 : 0.8))
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .frame(width: 22, height: 22)
                    .shadow(radius: 3)
                    .contentShape(Circle().scale(2.5))
                    .position(point)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .updating($dragging) { _, s, _ in s = true }
                            .onChanged { g in
                                let c = g.location.applying(toView.inverted())
                                state.setPivot(Pivot(x: c.x / w, y: 1 - c.y / h))
                            }
                            .onEnded { _ in state.endCoalescing() }
                    )
            }
        }
    }
}

#Preview {
    ContentView(state: EditorState.make())
}

/// The floating panels the canvas keeps clear of.
enum PanelSlot: Hashable { case top, tools, left, right, bottom }

struct PanelFramesKey: PreferenceKey {
    static let defaultValue: [PanelSlot: CGRect] = [:]
    static func reduce(value: inout [PanelSlot: CGRect], nextValue: () -> [PanelSlot: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Reports this panel's frame in the editor, so the canvas fits around it.
    func reportFrame(_ slot: PanelSlot) -> some View {
        background(GeometryReader { g in
            Color.clear.preference(key: PanelFramesKey.self, value: [slot: g.frame(in: .named(ContentView.space))])
        })
    }
}

