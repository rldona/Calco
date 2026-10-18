import SwiftUI

/// Bottom panel, an exposure sheet: one row per layer (top layer first), one column per frame,
/// columns as wide as their hold. A drawing spans the frames that hold it, so a background held
/// for the whole clip is a single long cell. Tap a cell to go to that frame and layer.
struct TimelineView: View {
    @ObservedObject var state: EditorState
    @State private var labeling = false
    @State private var labelText = ""

    /// Width of one tick (one `hold` unit).
    private let tick: CGFloat = 40
    private let rowHeight: CGFloat = 26
    private let labelWidth: CGFloat = 168

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            ScrollView(.vertical, showsIndicators: false) {
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 3) {
                        Color.clear.frame(height: 16)
                        ForEach(rows) { layer in LayerLabel(state: state, layerID: layer.id, height: rowHeight) }
                    }
                    .frame(width: labelWidth)
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 3) {
                                ruler
                                ForEach(rows) { layer in row(layer) }
                            }
                            .overlay(alignment: .topLeading) { playhead }
                            .coordinateSpace(name: Self.sheet)
                            .padding(.trailing, 8)
                        }
                        .onChange(of: state.frameIndex) { _, _ in
                            if let f = state.currentFrame {
                                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(f.id, anchor: .center) }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 16 + CGFloat(min(state.layers.count, 6)) * (rowHeight + 3))
            .fixedSize(horizontal: false, vertical: true)
            footer
        }
        .calcoPanel(padding: 10)
        .alert("Label drawing", isPresented: $labeling) {
            TextField("contact, passing, up…", text: $labelText)
            Button("Save") { state.setCurrentDrawingLabel(labelText) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Shown in the cell instead of its number. Leave empty to remove it.")
        }
    }

    private static let sheet = "sheet"

    /// The frame under x (in the sheet's coordinates), clamped to the clip.
    private func frameIndex(atX x: CGFloat) -> Int {
        var edge: CGFloat = 0
        for (i, f) in state.frames.enumerated() {
            edge += width(f)
            if x < edge { return i }
        }
        return max(0, state.frames.count - 1)
    }

    private func select(frame: Int, layer: String) {
        state.frameIndex = frame
        if let i = state.layers.firstIndex(where: { $0.id == layer }) { state.layerIndex = i }
    }

    /// Top layer first, like the canvas stacks them.
    private var rows: [Layer] { state.layers.reversed() }

    private func width(_ frame: Frame) -> CGFloat { tick * CGFloat(frame.hold) }

    private func x(ofFrame index: Int) -> CGFloat {
        state.frames.prefix(index).reduce(0) { $0 + width($1) }
    }

    // MARK: Header: transport, clips, onion skin

    private var header: some View {
        HStack(spacing: 12) {
            Button { state.togglePlayback() } label: {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 26, height: 26)
            }
            .accessibilityLabel(state.isPlaying ? "Pause" : "Play")

            Text("\(state.frameIndex + 1) / \(state.frames.count)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.textDim)
                .frame(minWidth: 40, alignment: .leading)

            ClipTabs(state: state)

            Toggle(isOn: Binding(get: { state.clip.loop }, set: { _ in state.toggleLoop() })) {
                Image(systemName: "repeat")
            }
            .toggleStyle(.button)
            .help("Loop")

            HStack(spacing: 2) {
                CompactStepper(title: "fps",
                               value: Binding(get: { state.clipFPS }, set: { state.setClipFPS($0) }),
                               range: 1...60, inherited: state.clip.fps == nil)
                if state.clip.fps != nil {
                    Button { state.setClipFPS(nil) } label: { Image(systemName: "arrow.uturn.backward") }
                        .font(.caption)
                        .help("Use project fps")
                }
            }

            Toggle(isOn: $state.showPivot) { Image(systemName: "scope") }
                .toggleStyle(.button)
                .help("Pivot")

            Spacer(minLength: 8)

            onionControls
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Theme.textDim)
        .font(.body)
    }

    /// Quick onion skin: on/off and how many frames each way, without opening the popover.
    private var onionControls: some View {
        HStack(spacing: 6) {
            Toggle(isOn: $state.onion.enabled) { Image(systemName: "circle.lefthalf.filled.righthalf.striped.horizontal") }
                .toggleStyle(.button)
                .help("Onion skin")
            Group {
                Circle().fill(Color(rgba: SIMD4(state.onion.beforeTint, 1))).frame(width: 8, height: 8)
                CompactStepper(title: "", value: $state.onion.before, range: 0...5)
                CompactStepper(title: "", value: $state.onion.after, range: 0...5)
                Circle().fill(Color(rgba: SIMD4(state.onion.afterTint, 1))).frame(width: 8, height: 8)
            }
            .opacity(state.onion.enabled ? 1 : 0.35)
        }
    }

    // MARK: Grid

    /// Frame numbers, the in / out range, and long-press to set them.
    private var ruler: some View {
        let range = state.effectivePlayRange
        return HStack(spacing: 0) {
            ForEach(Array(state.frames.enumerated()), id: \.element.id) { i, frame in
                Text("\(i + 1)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(i == state.frameIndex ? Theme.accentText : Theme.textFaint)
                    .padding(.leading, 3)
                    .frame(width: width(frame), height: 16, alignment: .leading)
                    .background(state.playRange != nil && range.contains(i) ? Theme.accent.opacity(0.12) : .clear)
                    .overlay(alignment: .leading) { Rectangle().fill(Theme.hairline).frame(width: 1, height: 6) }
                    .contentShape(Rectangle())
                    .onTapGesture { state.frameIndex = i }
                    // Hold the number, then drag: the frame (all its layers) moves along the sheet.
                    .gesture(LongPressGesture(minimumDuration: 0.25)
                        .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.sheet)))
                        .onChanged { value in
                            guard case .second(true, let drag?) = value else { return }
                            state.moveFrame(id: frame.id, to: frameIndex(atX: drag.location.x))
                        }
                        .onEnded { _ in state.endCoalescing() })
                    .accessibilityLabel("Frame \(i + 1)")
                    .accessibilityHint("Hold and drag to move the frame")
                    .id(frame.id)
            }
        }
    }

    private var playhead: some View {
        let x = x(ofFrame: state.frameIndex)
        let w = state.currentFrame.map(width) ?? tick
        return Rectangle()
            .fill(Theme.accent.opacity(0.10))
            .frame(width: w, height: 16 + CGFloat(state.layers.count) * (rowHeight + 3))
            .overlay(alignment: .leading) { Rectangle().fill(Theme.accent).frame(width: 2) }
            .offset(x: x)
            .allowsHitTesting(false)
    }

    /// One layer's exposures: each drawing a cell spanning its own frame and the frames holding it.
    private func row(_ layer: Layer) -> some View {
        let clip = state.clip
        let isCurrentLayer = layer.id == state.currentLayer?.id
        let currentRun = clip.sourceIndex(layer: layer.id, at: state.frameIndex)
        return HStack(spacing: 0) {
            ForEach(Array(clip.runs(of: layer.id).enumerated()), id: \.offset) { n, run in
                let span = clip.frames[run.start..<(run.start + run.count)]
                let w = span.reduce(0) { $0 + width($1) }
                let selected = isCurrentLayer && run.start == currentRun
                let drawn = state.store.existingTexture(clip: clip.id, frame: clip.frames[run.start].id, layer: layer.id) != nil
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(selected ? Theme.accentWash : (drawn ? Theme.raised : Color.clear))
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(selected ? Theme.accent : Theme.hairline,
                                      style: StrokeStyle(lineWidth: selected ? 1.5 : 0.75, dash: drawn ? [] : [3, 3]))
                    HStack(spacing: 4) {
                        Text(clip.frames[run.start].labels[layer.id] ?? "\(n + 1)")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .lineLimit(1)
                        if run.count > 1 {
                            Image(systemName: "arrow.right").font(.system(size: 8, weight: .semibold))
                        }
                    }
                    .foregroundStyle(selected ? Theme.accentText : Theme.textFaint)
                    .padding(.leading, 5)
                }
                .frame(width: max(4, w - 2), height: rowHeight)
                .padding(.trailing, 2)
                .opacity(layer.visible ? 1 : 0.45)
                .overlay {
                    // A tap lands on the frame under the finger, not just the drawing's first frame.
                    HStack(spacing: 0) {
                        ForEach(Array(span.enumerated()), id: \.element.id) { k, frame in
                            Color.clear.contentShape(Rectangle())
                                .frame(width: width(frame))
                                .onTapGesture { select(frame: run.start + k, layer: layer.id) }
                                .contextMenu { cellMenu(frame: run.start + k, layer: layer.id) }
                        }
                    }
                }
                .overlay(alignment: .trailing) {
                    // Drag the right edge to make the drawing last more or fewer frames.
                    if !layer.locked {
                        Capsule()
                            .fill(selected ? Theme.accent : Theme.textFaint.opacity(0.5))
                            .frame(width: 3, height: rowHeight * 0.5)
                            .frame(width: 14, height: rowHeight)
                            .contentShape(Rectangle())
                            .highPriorityGesture(DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.sheet))
                                .onChanged { g in
                                    state.setDrawingSpan(layer: layer.id, start: run.start,
                                                         count: frameIndex(atX: g.location.x) - run.start + 1)
                                }
                                .onEnded { _ in state.endCoalescing() })
                            .accessibilityLabel("Drawing length")
                            .accessibilityValue("\(run.count) frames")
                            .accessibilityAdjustableAction { dir in
                                state.setDrawingSpan(layer: layer.id, start: run.start,
                                                     count: run.count + (dir == .increment ? 1 : -1))
                                state.endCoalescing()
                            }
                    }
                }
                .accessibilityElement()
                .accessibilityLabel("\(layer.name), drawing \(n + 1)\(run.count > 1 ? ", held \(run.count) frames" : "")")
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    /// Long-press a cell: what the exposure sheet can do with it.
    @ViewBuilder
    private func cellMenu(frame: Int, layer: String) -> some View {
        let held = state.clip.isHeld(layer: layer, at: frame)
        if held {
            Button { select(frame: frame, layer: layer); state.releaseCurrentCell(copying: false) } label: {
                Label("New drawing here", systemImage: "square.dashed")
            }
            Button { select(frame: frame, layer: layer); state.releaseCurrentCell(copying: true) } label: {
                Label("Copy drawing here", systemImage: "square.on.square")
            }
        } else if frame > 0 {
            Button { select(frame: frame, layer: layer); state.holdCurrentCell() } label: {
                Label("Hold previous drawing", systemImage: "arrow.right.to.line")
            }
        }
        Button {
            select(frame: frame, layer: layer)
            labelText = state.drawingLabel(layer: layer, at: frame) ?? ""
            labeling = true
        } label: { Label("Label…", systemImage: "tag") }
        Divider()
        Button(role: .destructive) { select(frame: frame, layer: layer); state.clearCurrentLayer() } label: {
            Label("Clear drawing", systemImage: "eraser.line.dashed")
        }
    }

    // MARK: Footer: layer and cell actions

    private var footer: some View {
        HStack(spacing: 14) {
            Button { state.addLayerWithDefaultName() } label: {
                Label("New layer", systemImage: "plus").labelStyle(.titleAndIcon).font(.caption)
            }
            LayersButton(state: state)

            Spacer(minLength: 8)

            // The current cell: hold the previous drawing, or give it its own.
            if state.currentCellIsHeld {
                Button { state.releaseCurrentCell(copying: false) } label: {
                    Label("New drawing", systemImage: "square.dashed").labelStyle(.titleAndIcon).font(.caption)
                }
                Button { state.releaseCurrentCell(copying: true) } label: {
                    Label("Copy drawing", systemImage: "square.on.square").labelStyle(.titleAndIcon).font(.caption)
                }
            } else {
                Button { state.holdCurrentCell() } label: {
                    Label("Hold previous", systemImage: "arrow.right.to.line").labelStyle(.titleAndIcon).font(.caption)
                }
                .disabled(state.frameIndex == 0)
            }

            Button { labelText = state.currentLayer.flatMap { state.drawingLabel(layer: $0.id, at: state.frameIndex) } ?? ""
                     labeling = true } label: { Label("Label drawing", systemImage: "tag") }

            Menu {
                Button { state.setPlayRange(start: true) } label: { Label("Play from this frame", systemImage: "arrow.right.to.line") }
                Button { state.setPlayRange(start: false) } label: { Label("Play up to this frame", systemImage: "arrow.left.to.line") }
                if state.playRange != nil {
                    Button { state.playRange = nil } label: { Label("Play whole clip", systemImage: "arrow.left.and.right") }
                }
            } label: {
                Label("Playback range", systemImage: "arrow.left.and.right.square")
                    .foregroundStyle(state.playRange == nil ? Theme.textDim : Theme.accent)
            }

            Divider().overlay(Theme.hairline).frame(height: 16)

            CompactStepper(title: "Hold", value: Binding(
                get: { state.currentFrame?.hold ?? 1 },
                set: { state.setHold($0) }), range: 1...24)
            Button { state.moveFrame(by: -1) } label: { Label("Move frame earlier", systemImage: "arrowshape.left") }
                .disabled(state.frameIndex == 0)
            Button { state.moveFrame(by: 1) } label: { Label("Move frame later", systemImage: "arrowshape.right") }
                .disabled(state.frameIndex >= state.frames.count - 1)
            Button { state.duplicateFrame() } label: { Label("Duplicate frame", systemImage: "plus.square.on.square") }
            Button(role: .destructive) { state.deleteFrame() } label: { Label("Delete frame", systemImage: "trash") }
                .disabled(state.frames.count <= 1)
            Button { state.addFrame() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 30, height: 26)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 7))
            }
            .accessibilityLabel("Add frame")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .foregroundStyle(Theme.textDim)
    }
}

/// A layer's label in the sheet: eye, name, opacity when not 100%, lock. Tap to draw on it;
/// long-press for rename, opacity, order and delete.
private struct LayerLabel: View {
    @ObservedObject var state: EditorState
    let layerID: String
    let height: CGFloat
    @State private var renaming = false
    @State private var editingOpacity = false
    @State private var confirmingDelete = false
    @State private var name = ""

    var body: some View {
        if let index = state.layers.firstIndex(where: { $0.id == layerID }) {
            let layer = state.layers[index]
            let selected = index == state.layerIndex
            HStack(spacing: 6) {
                Button { state.toggleLayerVisibility(index) } label: {
                    Image(systemName: layer.visible ? "eye" : "eye.slash").frame(width: 20)
                }
                Text(layer.name)
                    .font(.caption.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.accentText : (layer.visible ? Theme.text : Theme.textFaint))
                    .lineLimit(1)
                Spacer(minLength: 2)
                if layer.opacity < 1 {
                    Button { editingOpacity = true } label: {
                        Text("\(Int((layer.opacity * 100).rounded()))%").font(.system(size: 10, design: .monospaced))
                    }
                }
                Button { state.toggleLayerLock(index) } label: {
                    Image(systemName: layer.locked ? "lock.fill" : "lock.open")
                        .foregroundStyle(layer.locked ? Theme.text : Theme.textFaint)
                        .frame(width: 18)
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.textDim)
            .buttonStyle(.borderless)
            .padding(.horizontal, 6)
            .frame(height: height)
            .background(selected ? Theme.accentWash : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onTapGesture { state.layerIndex = index }
            .contextMenu {
                Button { name = layer.name; renaming = true } label: { Label("Rename…", systemImage: "pencil") }
                Button { editingOpacity = true } label: { Label("Opacity…", systemImage: "circle.lefthalf.filled") }
                Button { state.moveLayer(from: index, to: index + 1) } label: { Label("Move up", systemImage: "arrow.up") }
                    .disabled(index == state.layers.count - 1)
                Button { state.moveLayer(from: index, to: index - 1) } label: { Label("Move down", systemImage: "arrow.down") }
                    .disabled(index == 0)
                Divider()
                Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete layer…", systemImage: "trash") }
                    .disabled(state.layers.count <= 1)
            }
            .popover(isPresented: $editingOpacity) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(layer.name) opacity").font(.headline)
                    Slider(value: Binding(get: { state.layers[index].opacity }, set: { state.setLayerOpacity(index, $0) }),
                           in: 0...1) { editing in if !editing { state.layerOpacityEditingEnded() } }
                    Text("\(Int((state.layers[index].opacity * 100).rounded()))%")
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                }
                .padding(20).frame(width: 260)
            }
            .alert("Rename layer", isPresented: $renaming) {
                TextField("Name", text: $name)
                Button("Rename") { state.renameLayer(index, to: name) }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Delete \(layer.name)?", isPresented: $confirmingDelete) {
                Button("Delete", role: .destructive) { state.deleteLayer(index) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Its drawings in all \(state.frames.count) frames of \(state.clip.name) go with it. You can undo this.")
            }
        }
    }
}

/// The clips as tabs; the last tab's menu adds, renames and deletes.
private struct ClipTabs: View {
    @ObservedObject var state: EditorState
    @State private var addingClip = false
    @State private var renamingClip = false
    @State private var confirmingDelete = false
    @State private var clipName = ""

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(state.project.clips.enumerated()), id: \.element.id) { i, clip in
                let on = i == state.clipIndex
                Button { state.selectClip(i) } label: {
                    Text(clip.name)
                        .font(.caption.weight(on ? .semibold : .regular))
                        .lineLimit(1)
                        .foregroundStyle(on ? Theme.accentText : Theme.textFaint)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(on ? Theme.accentWash : .clear, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            Menu {
                Button { clipName = ""; addingClip = true } label: { Label("New clip…", systemImage: "plus") }
                Button { clipName = state.clip.name; renamingClip = true } label: { Label("Rename \(state.clip.name)…", systemImage: "pencil") }
                Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete \(state.clip.name)", systemImage: "trash") }
                    .disabled(state.project.clips.count <= 1)
            } label: {
                Image(systemName: "ellipsis.circle").foregroundStyle(Theme.textDim)
            }
            .accessibilityLabel("Clip actions")
        }
        .alert("New clip", isPresented: $addingClip) {
            TextField("Name (idle, run, jump…)", text: $clipName)
            Button("Add") { state.addClip(name: clipName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Starts with one blank frame and the same layers as \(state.clip.name).")
        }
        .alert("Rename clip", isPresented: $renamingClip) {
            TextField("Name", text: $clipName)
            Button("Rename") { state.renameClip(clipName) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete \(state.clip.name)?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { state.deleteClip() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All \(state.clip.frames.count) frames of this clip will be removed.")
        }
    }
}
