import SwiftUI

/// Toolbar button showing the current layer; opens the layers panel.
struct LayersButton: View {
    @ObservedObject var state: EditorState
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            HStack(spacing: 5) {
                Image(systemName: "square.3.layers.3d")
                Text(state.currentLayer?.name ?? "—")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .frame(maxWidth: 110)
                    .fixedSize()
                if state.currentLayer?.locked == true {
                    Image(systemName: "lock.fill").font(.caption2)
                }
            }
        }
        .help("Layers")
        .popover(isPresented: $showing) { LayersPanel(state: state) }
    }
}

/// The clip's layer stack, top layer first like every drawing app.
/// Tap a row to paint on it; drag the handle to reorder.
struct LayersPanel: View {
    @ObservedObject var state: EditorState
    @State private var naming: Naming?
    @State private var name = ""
    @State private var confirmingDelete = false

    private enum Naming: Identifiable {
        case add, rename(Int)
        var id: String { if case .rename(let i) = self { "rename\(i)" } else { "add" } }
    }

    /// Rows are shown top to bottom; the model is bottom to top.
    /// Keyed by layer id so a moved row keeps its own view (and slider) while it moves.
    private var rows: [Layer] { state.layers.reversed() }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Layers").font(.headline)
                Spacer()
                Text(state.clip.name).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)

            List {
                ForEach(rows) { layer in
                    LayerRow(state: state, layerID: layer.id)
                }
                .onMove { source, destination in
                    // Translate positions in the reversed list back to model indices.
                    guard let from = source.first else { return }
                    let count = state.layers.count
                    let fromIndex = count - 1 - from
                    let toRow = destination > from ? destination - 1 : destination
                    state.moveLayer(from: fromIndex, to: count - 1 - toRow)
                }
            }
            .listStyle(.plain)
            .environment(\.editMode, .constant(.active))
            .frame(height: min(CGFloat(state.layers.count) * 64 + 8, 360))

            Divider()
            HStack(spacing: 18) {
                Button { name = ""; naming = .add } label: { Label("New layer", systemImage: "plus") }
                Button {
                    name = state.currentLayer?.name ?? ""
                    naming = .rename(state.layerIndex)
                } label: { Label("Rename", systemImage: "pencil") }
                Spacer()
                Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete", systemImage: "trash") }
                    .disabled(state.layers.count <= 1)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .padding(14)
        }
        .frame(width: 320)
        .alert(naming.map { if case .add = $0 { "New layer" } else { "Rename layer" } } ?? "",
               isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("Name (sketch, line, shadow…)", text: $name)
            Button(naming.map { if case .add = $0 { "Add" } else { "Rename" } } ?? "OK") {
                switch naming {
                case .add: state.addLayer(name: name)
                case .rename(let i): state.renameLayer(i, to: name)
                case nil: break
                }
                naming = nil
            }
            Button("Cancel", role: .cancel) { naming = nil }
        }
        .alert("Delete \(state.currentLayer?.name ?? "layer")?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { state.deleteLayer(state.layerIndex) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its drawing in all \(state.frames.count) frames of \(state.clip.name) goes with it. You can undo this.")
        }
    }
}

private struct LayerRow: View {
    @ObservedObject var state: EditorState
    let layerID: String

    var body: some View {
        if let index = state.layers.firstIndex(where: { $0.id == layerID }) {
            row(index: index, layer: state.layers[index])
        }
    }

    @ViewBuilder
    private func row(index: Int, layer: Layer) -> some View {
        let selected = index == state.layerIndex
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Button { state.toggleLayerVisibility(index) } label: {
                    Image(systemName: layer.visible ? "eye" : "eye.slash")
                        .foregroundStyle(layer.visible ? .primary : .secondary)
                        .frame(width: 24)
                }
                Text(layer.name)
                    .font(.body.weight(selected ? .semibold : .regular))
                    .lineLimit(1)
                    .foregroundStyle(layer.visible ? .primary : .secondary)
                Spacer(minLength: 4)
                Text("\(Int((layer.opacity * 100).rounded()))%")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Button { state.toggleLayerLock(index) } label: {
                    Image(systemName: layer.locked ? "lock.fill" : "lock.open")
                        .foregroundStyle(layer.locked ? .primary : .tertiary)
                        .frame(width: 22)
                }
            }
            if selected {
                Slider(value: Binding(get: { state.layers[index].opacity },
                                      set: { state.setLayerOpacity(index, $0) }),
                       in: 0...1) { editing in
                    if !editing { state.layerOpacityEditingEnded() }
                }
            }
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { state.layerIndex = index }
        .listRowBackground(selected ? Color.accentColor.opacity(0.18) : Color.clear)
    }
}
