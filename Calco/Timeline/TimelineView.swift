import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import ImageIO

/// Bottom panel, an exposure sheet: one row per layer (top layer first), one column per frame,
/// columns as wide as their hold. A drawing spans the frames that hold it, so a background held
/// for the whole clip is a single long cell. Tap a cell to go to that frame and layer. What you do
/// to the drawings lives in the AnimationRail.
struct TimelineView: View {
    @ObservedObject var state: EditorState
    @State private var labeling = false
    @State private var labelText = ""

    /// Width of one tick (one `hold` unit).
    private let tick: CGFloat = 58
    private let labelWidth: CGFloat = 168

    /// Height of the layer grid set with the grip, remembered; 0 = automatic (up to 6 rows).
    @AppStorage("timeline.gridHeight") private var gridHeight: Double = 0
    /// Pushed all the way down: only a slim bar with the grip, so the canvas gets the screen.
    @AppStorage("timeline.collapsed") private var collapsed = false
    @State private var dragStartHeight: CGFloat?

    private static let minRow: CGFloat = 56, maxRow: CGFloat = 72, rowGap: CGFloat = 3, rulerHeight: CGFloat = 28
    /// Tall enough for 5 big rows or 6 small ones, and leaves the canvas room on an 11" iPad in landscape.
    private static let maxGridHeight: CGFloat = 340

    /// Rows grow (up to `maxRow`) to fill a grid stretched taller than the layers need.
    private var rowHeight: CGFloat {
        guard gridHeight > 0, !state.layers.isEmpty else { return Self.minRow }
        let fit = (CGFloat(gridHeight) - Self.rulerHeight) / CGFloat(state.layers.count) - Self.rowGap
        return min(max(fit, Self.minRow), Self.maxRow)
    }

    private var automaticGridHeight: CGFloat {
        Self.rulerHeight + CGFloat(min(state.layers.count, 4)) * (Self.minRow + Self.rowGap)
    }

    /// A height saved with smaller rows never cuts a row in half: at least two whole rows.
    private var gridMaxHeight: CGFloat {
        guard gridHeight > 0 else { return automaticGridHeight }
        let least = Self.rulerHeight + CGFloat(min(state.layers.count, 2)) * (Self.minRow + Self.rowGap)
        return min(max(CGFloat(gridHeight), least), Self.maxGridHeight)
    }

    /// Drag up to make the grid taller (the canvas gives up the space), down to make it shorter.
    /// It never grows past what the layers can fill at the largest row height. Pushing on past the
    /// smallest height hides the timeline. Double tap: automatic.
    private var grip: some View {
        Capsule()
            .fill(gridHeight > 0 ? Theme.accent : Theme.textFaint)
            .frame(width: 46, height: 5)
            .frame(maxWidth: .infinity)
            .frame(height: 16)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 1)
                .onChanged { g in
                    let start = dragStartHeight ?? gridMaxHeight
                    if dragStartHeight == nil { dragStartHeight = start }
                    let most = Self.rulerHeight + CGFloat(max(state.layers.count, 1)) * (Self.maxRow + Self.rowGap)
                    let least = Self.rulerHeight + 2 * (Self.minRow + Self.rowGap)
                    let wanted = start - g.translation.height
                    gridHeight = Double(min(max(wanted, least), max(most, least), Self.maxGridHeight))
                }
                .onEnded { g in
                    // Pushed on past the smallest height: hide it, once the finger lifts (hiding
                    // mid-drag would hand the rest of the drag to the canvas).
                    let least = Self.rulerHeight + 2 * (Self.minRow + Self.rowGap)
                    if let start = dragStartHeight, start - g.translation.height < least - Self.collapseOvershoot {
                        withAnimation(.easeInOut(duration: 0.22)) { collapsed = true }
                    }
                    dragStartHeight = nil
                })
            .onTapGesture(count: 2) { withAnimation(.easeOut(duration: 0.2)) { gridHeight = 0 } }
            .accessibilityLabel("Timeline height")
            .accessibilityHint("Drag up or down to resize. Double tap for the automatic height.")
    }

    private static let collapseOvershoot: CGFloat = 50

    /// The hidden timeline: a slim bar; drag it up or tap it to bring the timeline back.
    private var collapsedBar: some View {
        HStack(spacing: 10) {
            Button { state.togglePlayback() } label: {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 36, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(state.isPlaying ? "Pause" : "Play")
            Text("\(state.frameIndex + 1) / \(state.frames.count)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.textDim)
            Capsule().fill(Theme.textFaint).frame(width: 46, height: 5)
            Image(systemName: "chevron.up").font(.caption.weight(.semibold)).foregroundStyle(Theme.textDim)
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background(Theme.panel, in: Capsule())
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.22)) { collapsed = false } }
        .gesture(DragGesture(minimumDistance: 4).onEnded { g in
            if g.translation.height < -20 { withAnimation(.easeInOut(duration: 0.22)) { collapsed = false } }
        })
        .accessibilityLabel("Show the timeline")
        .accessibilityAddTraits(.isButton)
    }

    var body: some View {
        Group {
            if collapsed {
                collapsedBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                expanded
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: collapsed)
    }

    private var expanded: some View {
        VStack(alignment: .leading, spacing: 6) {
            grip
                .padding(.top, -6)
                .padding(.bottom, -4)
            header
            ScrollView(.vertical, showsIndicators: false) {
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 3) {
                        layersHeader.frame(height: Self.rulerHeight)
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
            .frame(maxHeight: gridMaxHeight)
            .fixedSize(horizontal: false, vertical: true)
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

    /// A drawing's right edge dragged to `dragX`: it lasts up to there, pushing what follows.
    private func dragEdge(layer: String, start: Int, toX dragX: CGFloat) {
        let ticks = Int(((dragX - x(ofFrame: start)) / tick).rounded(.up))
        state.setDrawingDuration(layer: layer, start: start, ticks: ticks)
    }

    private func select(frame: Int, layer: String) {
        state.frameIndex = frame
        if let i = state.layers.firstIndex(where: { $0.id == layer }) { state.layerIndex = i }
    }

    /// Top layer first, like the canvas stacks them.
    private var rows: [Layer] { state.layers.reversed() }

    private func width(_ frame: Frame) -> CGFloat { tick * CGFloat(frame.hold) }

    private func ticks(_ frames: ArraySlice<Frame>) -> Int { frames.reduce(0) { $0 + $1.hold } }

    private func x(ofFrame index: Int) -> CGFloat {
        state.frames.prefix(index).reduce(0) { $0 + width($1) }
    }

    // MARK: Header: transport, clips, clip settings, frame length

    private var header: some View {
        HStack(spacing: 12) {
            Button { state.togglePlayback() } label: {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 48, height: 36)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(state.isPlaying ? "Pause" : "Play")

            Text("\(state.frameIndex + 1) / \(state.frames.count)")
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(Theme.textDim)
                .fixedSize()

            ClipTabs(state: state)

            ClipSettingsButton(state: state)

            Spacer(minLength: 8)

            HoldControl(state: state)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Theme.textDim)
        .font(.body)
    }

    /// Above the layer names: add a layer, or open the full layers panel.
    private var layersHeader: some View {
        HStack(spacing: 6) {
            Text("Layers").font(.caption).foregroundStyle(Theme.textFaint)
            Spacer(minLength: 2)
            NewLayerMenu(state: state)
            LayersButton(state: state, iconOnly: true)
        }
        .padding(.leading, 6)
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
                    .frame(width: width(frame), height: Self.rulerHeight, alignment: .bottomLeading)
                    .background(state.playRange != nil && range.contains(i) ? Theme.accent.opacity(0.12) : .clear)
                    .overlay(alignment: .bottomLeading) { Rectangle().fill(Theme.hairline).frame(width: 1, height: 8) }
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
            .frame(width: w, height: Self.rulerHeight + CGFloat(state.layers.count) * (rowHeight + Self.rowGap))
            .overlay(alignment: .leading) { Rectangle().fill(Theme.accent).frame(width: 2) }
            .offset(x: x)
            .allowsHitTesting(false)
    }

    /// One layer's exposures: each drawing a cell spanning its own frame and the frames holding it.
    private func row(_ layer: Layer) -> some View {
        let clip = state.clip
        let isCurrentLayer = layer.id == state.currentLayer?.id
        let currentRun = clip.cellStart(layer: layer.id, at: state.frameIndex)
        let runs = clip.runs(of: layer.id)
        let runIndex = Dictionary(uniqueKeysWithValues: runs.enumerated().map { ($1.start, $0) })
        return HStack(spacing: 0) {
            ForEach(Array(runs.enumerated()), id: \.offset) { n, run in
                let span = clip.frames[run.start..<(run.start + run.count)]
                let w = span.reduce(0) { $0 + width($1) }
                let selected = isCurrentLayer && run.start == currentRun
                let key = state.drawingKey(layer: layer.id, at: run.start)
                let drawn = key.flatMap { state.store.existingTexture(clip: $0.clip, frame: $0.frame, layer: $0.layer) } != nil
                let linkedTo = clip.isLinked(layer: layer.id, at: run.start)
                    ? runIndex[clip.sourceIndex(layer: layer.id, at: run.start)]
                    : nil
                let preview = key.flatMap { state.drawingThumbnails[$0] }
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(selected ? Theme.accentWash : (drawn ? Theme.raised : Color.clear))
                    if drawn, let preview {
                        // What the drawing looks like, on white paper.
                        Image(decorative: preview, scale: 2)
                            .resizable().interpolation(.medium).scaledToFit()
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .padding(3)
                            .frame(maxWidth: max(4, w - 2), maxHeight: rowHeight, alignment: .leading)
                            // Only a picture: taps go to the cell (an Image would swallow them).
                            .allowsHitTesting(false)
                    }
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(selected ? Theme.accent : Theme.hairline,
                                      style: StrokeStyle(lineWidth: selected ? 1.5 : 0.75, dash: drawn ? [] : [3, 3]))
                    HStack(spacing: 4) {
                        if let linkedTo {
                            Image(systemName: "link").font(.system(size: 8, weight: .semibold))
                            Text(state.drawingLabel(layer: layer.id, at: run.start) ?? "\(linkedTo + 1)")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .lineLimit(1)
                        } else {
                        Text(clip.frames[run.start].labels[layer.id] ?? "\(n + 1)")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .lineLimit(1)
                        }
                        if run.count > 1 {
                            Image(systemName: "arrow.right").font(.system(size: 8, weight: .semibold))
                        }
                    }
                    .foregroundStyle(drawn && preview != nil ? Theme.text : (selected ? Theme.accentText : Theme.textFaint))
                    .padding(.horizontal, drawn && preview != nil ? 4 : 0)
                    .background(drawn && preview != nil ? Theme.background.opacity(0.75) : .clear, in: Capsule())
                    .scaleEffect(drawn && preview != nil ? 0.8 : 1, anchor: .bottomLeading)
                    .frame(maxHeight: .infinity, alignment: drawn && preview != nil ? .bottomLeading : .center)
                    .padding(.leading, drawn && preview != nil ? 2 : 5)
                    .padding(.bottom, drawn && preview != nil ? 2 : 0)
                    .allowsHitTesting(false)
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
                    // Drag the right edge (Pencil or finger) to make the drawing last more or fewer
                    // frames; what comes after moves along.
                    if !layer.locked {
                        Capsule()
                            .fill(selected ? Theme.accent : Theme.textDim)
                            .frame(width: 4, height: rowHeight * 0.65)
                            .frame(width: 22, height: rowHeight)
                            .contentShape(Rectangle())
                            .highPriorityGesture(DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.sheet))
                                .onChanged { g in dragEdge(layer: layer.id, start: run.start, toX: g.location.x) }
                                .onEnded { _ in state.endCoalescing() })
                            .accessibilityLabel("Drawing length")
                            .accessibilityValue("\(ticks(span)) frames")
                            .accessibilityAdjustableAction { dir in
                                state.setDrawingDuration(layer: layer.id, start: run.start,
                                                         ticks: ticks(span) + (dir == .increment ? 1 : -1))
                                state.endCoalescing()
                            }
                    }
                }
                .accessibilityElement()
                .accessibilityLabel(linkedTo.map { "\(layer.name), repeat of drawing \($0 + 1)" } ?? "\(layer.name), drawing \(n + 1)")
                .accessibilityValue(run.count > 1 ? "held \(run.count) frames" : "")
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
            if isCurrentLayer && !layer.locked {
                // After the last drawing: one more, right where you're looking.
                Button {
                    state.frameIndex = state.frames.count - 1
                    state.addDrawing()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: tick, height: rowHeight)
                        .overlay(RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Theme.accent.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(state.syncLayers ? "Add frame at the end" : "Add drawing at the end")
            }
        }
    }

    /// Long-press a cell: what the exposure sheet can do with it.
    @ViewBuilder
    private func cellMenu(frame: Int, layer: String) -> some View {
        let held = state.clip.isHeld(layer: layer, at: frame)
        if state.clip.isLinked(layer: layer, at: state.clip.cellStart(layer: layer, at: frame)) {
            Button { select(frame: frame, layer: layer); state.releaseCurrentCell(copying: true) } label: {
                Label("Unlink (keep a copy)", systemImage: "link.badge.plus")
            }
        }
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
            HStack(spacing: 5) {
                Button { state.toggleLayerVisibility(index) } label: {
                    Image(systemName: layer.visible ? "eye" : "eye.slash").frame(width: 20)
                }
                if layer.maskBelow && index > 0 {
                    Image(systemName: "arrow.turn.left.down").font(.system(size: 9, weight: .semibold))
                        .accessibilityLabel("Masked to the layer below")
                }
                if layer.guide {
                    Image(systemName: "photo").font(.system(size: 10, weight: .semibold))
                        .accessibilityLabel("Guide layer, not exported")
                }
                Text(layer.name)
                    .font(.caption.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.accentText : (layer.visible ? Theme.text : Theme.textFaint))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)      // "Reference" fits next to its badge, 40 % and lock
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
                Button { state.toggleLayerMask(index) } label: {
                    Label(layer.maskBelow ? "Stop masking to layer below" : "Mask to layer below",
                          systemImage: "arrow.turn.left.down")
                }
                .disabled(index == 0 && !layer.maskBelow)
                Button { state.toggleLayerGuide(index) } label: {
                    Label(layer.guide ? "Export this layer" : "Guide only (not exported)",
                          systemImage: layer.guide ? "square.and.arrow.up" : "eye.slash.circle")
                }
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
                        .font(.subheadline.weight(on ? .semibold : .regular))
                        .lineLimit(1)
                        .foregroundStyle(on ? Theme.accentText : Theme.textDim)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(on ? Theme.accentWash : .clear, in: RoundedRectangle(cornerRadius: 8))
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

/// How long the frame at the playhead stays on screen (every layer). Lit up when it's held, so a
/// long frame is easy to spot.
private struct HoldControl: View {
    @ObservedObject var state: EditorState

    private var hold: Int { state.currentFrame?.hold ?? 1 }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "timer")
            Text(hold == 1 ? "Lasts 1 frame" : "Lasts \(hold) frames")
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .fixedSize()
            step("minus", by: -1).disabled(hold <= 1)
            step("plus", by: 1).disabled(hold >= 24)
        }
        .labelStyle(.titleAndIcon)
        .foregroundStyle(hold > 1 ? Theme.accentText : Theme.text)
        .padding(.leading, 12).padding(.trailing, 4).padding(.vertical, 3)
        .background(hold > 1 ? Theme.accentWash : Color.white.opacity(0.06), in: Capsule())
        .overlay(Capsule().strokeBorder(hold > 1 ? Theme.accent.opacity(0.6) : Theme.hairline))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Frame length")
        .accessibilityValue(hold == 1 ? "1 frame" : "\(hold) frames")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: state.setHold(hold + 1)
            case .decrement: state.setHold(hold - 1)
            @unknown default: break
            }
        }
    }

    private func step(_ icon: String, by delta: Int) -> some View {
        Button { state.setHold(hold + delta) } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 40, height: 32)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
    }
}

/// "12 fps · loop ⌄": the clip's speed, looping and pivot in one popover.
private struct ClipSettingsButton: View {
    @ObservedObject var state: EditorState
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            HStack(spacing: 6) {
                Text("\(state.clipFPS) fps").monospacedDigit()
                if state.clip.loop { Image(systemName: "repeat").imageScale(.small) }
                if state.showPivot { Image(systemName: "scope").imageScale(.small).foregroundStyle(Theme.accent) }
                Image(systemName: "chevron.down").imageScale(.small).foregroundStyle(Theme.textFaint)
            }
            .font(.subheadline)
            .foregroundStyle(Theme.textDim)
            .padding(.horizontal, 12).frame(height: 36)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clip settings")
        .accessibilityValue("\(state.clipFPS) fps")
        .popover(isPresented: $showing) {
            VStack(alignment: .leading, spacing: 14) {
                Text(state.clip.name).font(.headline)
                HStack {
                    CompactStepper(title: "fps",
                                   value: Binding(get: { state.clipFPS }, set: { state.setClipFPS($0) }),
                                   range: 1...60, inherited: state.clip.fps == nil)
                    Spacer()
                    if state.clip.fps != nil {
                        Button("Use project fps") { state.setClipFPS(nil) }.font(.caption)
                    }
                }
                Toggle("Loop", isOn: Binding(get: { state.clip.loop }, set: { _ in state.toggleLoop() }))
                Toggle("Show pivot", isOn: $state.showPivot)
            }
            .padding(20)
            .frame(width: 280)
            .tint(Theme.accent)
            .preferredColorScheme(.dark)
        }
    }
}

/// "+" over the layer names: a blank layer, one with the current layer's timing, a duplicate, or
/// an image to trace over (a guide layer).
private struct NewLayerMenu: View {
    @ObservedObject var state: EditorState
    @State private var pickingPhoto = false
    @State private var photo: PhotosPickerItem?
    @State private var importingFile = false

    var body: some View {
        Menu {
            Button { state.addLayerWithDefaultName() } label: { Label("Empty layer", systemImage: "square") }
            if let name = state.currentLayer?.name {
                Button { state.addLayerMatchingTiming() } label: {
                    Label("Same timing as \(name), blank", systemImage: "square.on.square.dashed")
                }
                Button { state.duplicateCurrentLayer() } label: { Label("Duplicate \(name)", systemImage: "square.on.square") }
            }
            Divider()
            Button { pickingPhoto = true } label: { Label("Image from Photos…", systemImage: "photo.badge.plus") }
            Button { importingFile = true } label: { Label("Image from Files…", systemImage: "doc.badge.plus") }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 32, height: 26)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
        }
        .accessibilityLabel("New layer")
        .photosPicker(isPresented: $pickingPhoto, selection: $photo, matching: .images)
        .onChange(of: photo) { _, item in
            guard let item else { return }
            photo = nil
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                await MainActor.run { importImage(data, name: nil) }
            }
        }
        .fileImporter(isPresented: $importingFile, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            importImage(try? Data(contentsOf: url), name: url.deletingPathExtension().lastPathComponent)
        }
    }

    /// Decodes picked image data (any format ImageIO reads, with its orientation applied) and adds
    /// it as a guide layer.
    private func importImage(_ data: Data?, name: String?) {
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                       kCGImageSourceCreateThumbnailWithTransform: true,
                       kCGImageSourceThumbnailMaxPixelSize: 4096] as CFDictionary
        guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            state.lastError = String(localized: "Couldn't read that image.", bundle: AppLanguage.bundle)
            return
        }
        state.importImageLayer(image, name: name)
    }
}
