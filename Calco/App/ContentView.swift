import SwiftUI
import Metal

struct ContentView: View {
    @ObservedObject var state: EditorState
    @State private var latencyMs: Double = 0

    var body: some View {
        ZStack {
            CanvasView(state: state, latencyMs: $latencyMs)
                .ignoresSafeArea()

            if state.showPivot {
                PivotOverlay(state: state)
                    .ignoresSafeArea()
            }

            VStack {
                ToolbarView(state: state, latencyMs: latencyMs)
                Spacer()
                TimelineView(state: state)
            }
            .padding(12)
        }
    }
}

struct ToolbarView: View {
    @ObservedObject var state: EditorState
    let latencyMs: Double

    /// Scrolls sideways when the controls don't fit (portrait); the layout pass in v0.2 replaces this.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            controls
            ScrollView(.horizontal, showsIndicators: false) { controls }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var controls: some View {
        HStack(spacing: 14) {
            FileMenu(state: state)

            Divider().frame(height: 18)

            Button { state.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .keyboardShortcut("z")
                .disabled(!state.canUndo)
                .help("Undo")
            Button { state.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!state.canRedo)
                .help("Redo")

            if state.canvasTransform != .identity {
                Button { state.canvasTransform = .identity } label: { Image(systemName: "arrow.down.right.and.arrow.up.left") }
                    .keyboardShortcut("0")
                    .help("Fit canvas")
            }

            Divider().frame(height: 18)

            ToolControls(state: state)

            Button { state.clearCurrentLayer() } label: { Image(systemName: "xmark.circle") }
                .help("Clear layer")

            Divider().frame(height: 18)

            // Layers: tap name to select, tap eye to toggle visibility
            HStack(spacing: 6) {
                ForEach(Array(state.layers.enumerated()).reversed(), id: \.element.id) { index, layer in
                    HStack(spacing: 4) {
                        Button { state.layerIndex = index } label: {
                            Text(layer.name)
                                .font(.caption.weight(index == state.layerIndex ? .semibold : .regular))
                                .lineLimit(1)
                                .fixedSize()
                        }
                        Button { state.toggleLayerVisibility(index) } label: {
                            Image(systemName: layer.visible ? "eye" : "eye.slash")
                                .font(.caption)
                                .foregroundStyle(layer.visible ? .primary : .secondary)
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(index == state.layerIndex ? Color.accentColor.opacity(0.25) : Color.clear,
                                in: Capsule())
                }
            }

            Divider().frame(height: 18)

            // Onion skin
            Toggle(isOn: $state.onion.enabled) {
                Image(systemName: "square.3.layers.3d.down.left")
            }
            .toggleStyle(.button)
            Stepper("", value: $state.onion.before, in: 0...5).labelsHidden()
            Text("\(state.onion.before)·\(state.onion.after)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            Stepper("", value: $state.onion.after, in: 0...5).labelsHidden()

            Spacer()

            Text(String(format: "%.1f ms", latencyMs))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.borderless)
    }
}

/// New / Open / Save / Save As, plus the project name with an unsaved-changes dot.
struct FileMenu: View {
    @ObservedObject var state: EditorState
    @State private var showingOpen = false
    @State private var showingSaveAs = false
    @State private var confirmingNew = false
    @State private var saveAsName = ""
    @State private var exported: [URL] = []
    @State private var exportTitle = ""
    @State private var showingExport = false

    var body: some View {
        Menu {
            Button { state.isDirty ? (confirmingNew = true) : state.newProject() } label: {
                Label("New", systemImage: "doc")
            }
            .keyboardShortcut("n")
            Button { showingOpen = true } label: { Label("Open…", systemImage: "folder") }
                .keyboardShortcut("o")
            Divider()
            Button { state.save() } label: { Label("Save", systemImage: "square.and.arrow.down") }
                .keyboardShortcut("s")
            Button {
                saveAsName = state.project.name
                showingSaveAs = true
            } label: { Label("Save As…", systemImage: "square.and.arrow.down.on.square") }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            Divider()
            Button {
                if let urls = state.exportSpriteSheet() {
                    exported = urls
                    exportTitle = "Sprite sheet"
                    showingExport = true
                }
            } label: { Label("Export sprite sheet…", systemImage: "square.grid.3x3.square") }
            .keyboardShortcut("e")
            Button {
                if let url = state.exportGIF() {
                    exported = [url]
                    exportTitle = "GIF · \(state.clip.name)"
                    showingExport = true
                }
            } label: { Label("Export GIF (\(state.clip.name))…", systemImage: "film") }
            .keyboardShortcut("g")
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
        .sheet(isPresented: $showingExport) {
            ExportSheet(title: exportTitle, urls: exported, name: state.project.name)
        }
        .alert("Discard unsaved changes?", isPresented: $confirmingNew) {
            Button("Discard", role: .destructive) { state.newProject() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(state.project.name) has changes that haven't been saved.")
        }
        .alert("File error", isPresented: Binding(
            get: { state.lastError != nil },
            set: { if !$0 { state.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(state.lastError ?? "")
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
                    Label(urls.count > 1 ? "Share PNG + JSON" : "Share GIF", systemImage: "square.and.arrow.up")
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

    private func icon(for url: URL) -> String {
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
                .stroke(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .allowsHitTesting(false)

                Circle()
                    .fill(Color.accentColor.opacity(dragging ? 0.9 : 0.7))
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
