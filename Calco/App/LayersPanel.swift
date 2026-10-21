import SwiftUI

/// Opens the full layers panel (drag to reorder, opacity sliders) from the exposure sheet.
struct LayersButton: View {
    @Bindable var state: EditorState
    var iconOnly = false
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            if iconOnly {
                Image(systemName: "square.3.layers.3d")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .frame(width: 32, height: 26)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
            } else {
                Label("Layers", systemImage: "square.3.layers.3d").labelStyle(.titleAndIcon).font(.caption)
            }
        }
        .accessibilityLabel("Layers")
        .popover(isPresented: $showing) { LayersPanel(state: state).frame(height: 360) }
    }
}

/// The clip's layer stack, top layer first like every drawing app. Tap a row to paint on it; drag the handle to reorder.
struct LayersPanel: View {
    @Bindable var state: EditorState
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
                Text("Layers").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                Spacer()
                Text(state.clip.name).font(.caption).foregroundStyle(Theme.textFaint).lineLimit(1)
            }
            .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 4)

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
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(.active))

            Divider().overlay(Theme.hairline)
            HStack(spacing: 14) {
                Button { name = ""; naming = .add } label: { Label("New layer", systemImage: "plus") }
                Button {
                    name = state.currentLayer?.name ?? ""
                    naming = .rename(state.layerIndex)
                } label: { Label("Rename", systemImage: "pencil") }
                Button { state.clearCurrentLayer() } label: { Label("Clear layer", systemImage: "eraser.line.dashed") }
                Button { state.toggleLayerMask(state.layerIndex) } label: {
                    Label("Mask to layer below", systemImage: "arrow.turn.left.down")
                }
                .foregroundStyle(state.currentLayer?.maskBelow == true ? Theme.accent : Theme.textDim)
                .disabled(state.layerIndex == 0 && state.currentLayer?.maskBelow != true)
                    .disabled(state.currentLayer?.locked ?? true)
                    .help("Clear this frame's drawing on the layer")
                Spacer()
                Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete", systemImage: "trash") }
                    .disabled(state.layers.count <= 1)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .foregroundStyle(Theme.textDim)
            .padding(.horizontal, 10).padding(.vertical, 8)
        }
        .frame(width: 210)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.corner))
        .alert(naming.map { if case .add = $0 { LocalizedStringKey("New layer") } else { LocalizedStringKey("Rename layer") } } ?? "",
               isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("Name (sketch, line, shadow…)", text: $name)
            Button(naming.map { if case .add = $0 { LocalizedStringKey("Add") } else { LocalizedStringKey("Rename") } } ?? "OK") {
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
    @Bindable var state: EditorState
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
            HStack(spacing: 8) {
                Button { state.toggleLayerVisibility(index) } label: {
                    Image(systemName: layer.visible ? "eye" : "eye.slash")
                        .foregroundStyle(layer.visible ? .primary : .secondary)
                        .frame(width: 22)
                }
                if layer.maskBelow && index > 0 {
                    Button { state.toggleLayerMask(index) } label: {
                        Image(systemName: "arrow.turn.left.down").font(.caption)
                    }
                    .accessibilityLabel("Masked to the layer below; tap to stop")
                }
                Text(layer.name)
                    .font(.callout.weight(selected ? .semibold : .regular))
                    .lineLimit(1)
                    .layoutPriority(1)
                    .foregroundStyle(layer.visible ? .primary : .secondary)
                Spacer(minLength: 2)
                // Only worth the space when it isn't 100%; the selected row has the slider anyway.
                if layer.opacity < 1 {
                    Text("\(Int((layer.opacity * 100).rounded()))%")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
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
        .foregroundStyle(selected ? Theme.accentText : Theme.textDim)
        .listRowBackground(RoundedRectangle(cornerRadius: 8)
            .fill(selected ? Theme.accentWash : Color.clear)
            .padding(.horizontal, 4))
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 6))
    }
}
