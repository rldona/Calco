import SwiftUI
import Metal

/// Estudio layout: tool rail on the left, layers on the right, clip tracks at the bottom, and the
/// canvas in whatever space is left (so panels never cover the drawing). Zen mode hides all of it
/// except a small floating bar.
struct ContentView: View {
    @ObservedObject var state: EditorState
    @State private var latencyMs: Double = 0

    var body: some View {
        VStack(spacing: Theme.gap) {
            if !state.isZen {
                TopBar(state: state, latencyMs: latencyMs)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            HStack(spacing: Theme.gap) {
                if !state.isZen {
                    ToolRail(state: state)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                canvas
            }
            if !state.isZen {
                TimelineView(state: state)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(Theme.gap)
        .background(Theme.background.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.22), value: state.isZen)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }

    private var canvas: some View {
        CanvasView(state: state, latencyMs: $latencyMs)
            .clipShape(RoundedRectangle(cornerRadius: state.isZen ? 0 : Theme.corner))
            .overlay {
                if state.showPivot { PivotOverlay(state: state) }
            }
            .overlay { SelectionOverlay(state: state) }
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

/// Document on the left; view toggles (fit, onion skin, Zen) on the right.
struct TopBar: View {
    @ObservedObject var state: EditorState
    let latencyMs: Double

    var body: some View {
        HStack(spacing: 16) {
            FileMenu(state: state)
            Spacer()
            if !state.canvasTransform.isFit {
                Button { state.fitCanvas() } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                }
                .help("Fit canvas")
            }
            Button { state.canvasTransform.flipped.toggle() } label: {
                Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                    .foregroundStyle(state.canvasTransform.flipped ? Theme.accent : Theme.textDim)
            }
            .help("Flip the view (H): see the drawing mirrored without changing it")
            .accessibilityLabel(state.canvasTransform.flipped ? "Unflip view" : "Flip view")
            OnionSkinButton(state: state)
            Button { state.isZen = true } label: {
                Label("Zen", systemImage: "circle.dashed.inset.filled")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .overlay(Capsule().strokeBorder(Theme.textFaint, lineWidth: 1))
            }
            .help("Zen mode: hide everything but the canvas")
            #if DEBUG
            Text(String(format: "%.1f ms", latencyMs))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Theme.textFaint)
                .frame(width: 44, alignment: .trailing)
            #endif
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Theme.textDim)
        .padding(.horizontal, 6)
        .frame(height: 30)
    }
}

/// Zen mode's only chrome: undo, brush, eraser, colour, and the way back.
struct ZenBar: View {
    @ObservedObject var state: EditorState
    @State private var editingColor = false

    var body: some View {
        HStack(spacing: 4) {
            RailButton(icon: "arrow.uturn.backward", label: "Undo", size: 34) { state.undo() }
                .opacity(state.canUndo ? 1 : 0.35)
            RailButton(icon: "pencil.tip", label: "Brush", active: state.tool == .brush, size: 34) { state.tool = .brush }
            RailButton(icon: "eraser", label: "Eraser", active: state.tool == .eraser, size: 34) { state.tool = .eraser }
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

/// Onion skin on/off, with how many frames before / after and how strong, in a popover.
struct OnionSkinButton: View {
    @ObservedObject var state: EditorState
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            Image(systemName: state.onion.enabled ? "circle.lefthalf.filled.righthalf.striped.horizontal"
                                                  : "circle.dashed")
                .foregroundStyle(state.onion.enabled ? Theme.accent : Theme.textDim)
        }
        .help("Onion skin")
        .popover(isPresented: $showing) {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Onion skin", isOn: $state.onion.enabled).font(.headline)
                Group {
                    HStack {
                        CompactStepper(title: "Drawings before", value: $state.onion.before, range: 0...5)
                        Spacer()
                        ColorPicker("Drawings before colour", selection: Binding(
                            get: { Color(rgba: SIMD4(state.onion.beforeTint, 1)) },
                            set: { let c = SIMD4<Float>($0); state.onion.beforeTint = SIMD3(c.x, c.y, c.z) }),
                                    supportsOpacity: false)
                            .labelsHidden()
                    }
                    HStack {
                        CompactStepper(title: "Drawings after", value: $state.onion.after, range: 0...5)
                        Spacer()
                        ColorPicker("Drawings after colour", selection: Binding(
                            get: { Color(rgba: SIMD4(state.onion.afterTint, 1)) },
                            set: { let c = SIMD4<Float>($0); state.onion.afterTint = SIMD3(c.x, c.y, c.z) }),
                                    supportsOpacity: false)
                            .labelsHidden()
                    }
                    HStack {
                        Text("Strength").font(.caption).foregroundStyle(.secondary)
                        Slider(value: Binding(get: { Double(state.onion.opacity) },
                                              set: { state.onion.opacity = Float($0) }), in: 0.1...0.8)
                    }
                    Toggle("Current layer only", isOn: $state.onion.currentLayerOnly).font(.subheadline)
                }
                .disabled(!state.onion.enabled)
            }
            .padding(20)
            .frame(width: 300)
        }
    }
}

/// New / Open / Save / Save As, plus the project name with an unsaved-changes dot.
struct FileMenu: View {
    @ObservedObject var state: EditorState
    @State private var showingOpen = false
    @State private var showingSaveAs = false
    @State private var showingNewProject = false
    @State private var saveAsName = ""
    @State private var exported: [URL] = []
    @State private var exportTitle = ""
    @State private var showingExport = false
    @State private var showingProfiles = false

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
    @ObservedObject var state: EditorState
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
