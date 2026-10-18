import SwiftUI
import Metal

struct ContentView: View {
    @ObservedObject var state: EditorState
    @State private var latencyMs: Double = 0

    var body: some View {
        ZStack {
            CanvasView(state: state, latencyMs: $latencyMs)
                .ignoresSafeArea()

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

    var body: some View {
        HStack(spacing: 14) {
            FileMenu(state: state)

            Divider().frame(height: 18)

            // Tools
            Picker("Tool", selection: $state.tool) {
                Image(systemName: "pencil.tip").tag(CanvasRenderer.Tool.brush)
                Image(systemName: "eraser").tag(CanvasRenderer.Tool.eraser)
            }
            .pickerStyle(.segmented)
            .frame(width: 110)

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
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// New / Open / Save / Save As, plus the project name with an unsaved-changes dot.
struct FileMenu: View {
    @ObservedObject var state: EditorState
    @State private var showingOpen = false
    @State private var showingSaveAs = false
    @State private var confirmingNew = false
    @State private var saveAsName = ""

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

#Preview {
    ContentView(state: EditorState.make())
}
