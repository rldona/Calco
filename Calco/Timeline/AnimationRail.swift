import SwiftUI

/// Right rail, the tool rail's twin for animating: a big New, then what you do to the drawing at
/// the playhead (duplicate, hold, delete, more), the onion skin, and whether the buttons act on the
/// current layer or on every layer. Upright beside the canvas in landscape; lying down above the
/// timeline in portrait.
struct AnimationRail: View {
    @Bindable var state: EditorState
    var axis: Axis = .vertical
    @State private var labeling = false
    @State private var labelText = ""
    @State private var repeating = false
    @State private var editingOnion = false

    var body: some View {
        Group {
            if axis == .vertical {
                // Captions while there's room; icons only when the timeline is stretched tall.
                ViewThatFits(in: .vertical) {
                    column(compact: false).fixedSize(horizontal: false, vertical: true)
                    column(compact: true).fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 64)
            } else {
                row
            }
        }
        .calcoPanel(padding: 6)
        .alert("Label drawing", isPresented: $labeling) {
            TextField("contact, passing, up…", text: $labelText)
            Button("Save") { state.setCurrentDrawingLabel(labelText) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Shown in the cell instead of its number. Leave empty to remove it.")
        }
    }

    private func column(compact: Bool) -> some View {
        VStack(spacing: compact ? 4 : 6) {
            newButton(width: 60, height: compact ? 48 : 60, caption: !compact)
            duplicate(compact: compact)
            cell(compact: compact)
            delete(compact: compact)
            more(compact: compact)
            Divider().overlay(Theme.hairline).padding(.horizontal, 6).padding(.vertical, 2)
            onion(compact: compact)
            Spacer(minLength: 4)
            scope(vertical: true)
        }
    }

    private var row: some View {
        HStack(spacing: 8) {
            onion(compact: false)
            scope(vertical: false)
            Spacer(minLength: 4)
            duplicate(compact: false)
            cell(compact: false)
            delete(compact: false)
            more(compact: false)
            newButton(width: 150, height: 52, caption: true)
        }
        .frame(height: 56)
    }

    // MARK: Buttons

    /// The one you press most: a new blank drawing after the playhead (a whole frame with All).
    private func newButton(width: CGFloat, height: CGFloat, caption: Bool) -> some View {
        Button { state.addDrawing() } label: {
            Group {
                if axis == .horizontal {
                    Label(state.syncLayers ? "New frame" : "New drawing", systemImage: "plus")
                        .font(.headline)
                } else {
                    VStack(spacing: 2) {
                        Image(systemName: "plus").font(.system(size: 24, weight: .bold))
                        if caption { Text("New").font(.caption2.weight(.bold)) }
                    }
                }
            }
            .foregroundStyle(Theme.onAccent)
            .frame(width: width, height: height)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.syncLayers ? "Add frame" : "Add drawing")
        .help(state.syncLayers ? "Add frame" : "Add drawing")
    }

    private func duplicate(compact: Bool) -> some View {
        AnimationButton(icon: "plus.square.on.square", caption: "Duplicate", compact: compact,
                        label: state.syncLayers ? "Duplicate frame" : "Duplicate drawing") {
            state.duplicateDrawing()
        }
    }

    /// Its own view, so only it follows the playhead (playing, it changes every frame).
    private func cell(compact: Bool) -> some View {
        CellButton(state: state, compact: compact)
    }

    private func delete(compact: Bool) -> some View {
        AnimationButton(icon: "trash", caption: "Delete", compact: compact,
                        label: state.syncLayers ? "Delete frame" : "Delete drawing") {
            state.deleteDrawing()
        }
        .disabled(state.syncLayers && state.frames.count <= 1)
    }

    /// Everything used less often: label, inbetweens, cycles, and the whole-frame actions.
    private func more(compact: Bool) -> some View {
        Menu {
            // Its own view, so the rail doesn't follow the playhead for it.
            MoreMenuItems(state: state, labeling: $labeling, labelText: $labelText, repeating: $repeating)
        } label: {
            AnimationButtonLabel(icon: "ellipsis", caption: "More", compact: compact,
                                 tint: state.playRange == nil ? nil : Theme.accentText)
        }
        .accessibilityLabel("More drawing actions")
        .popover(isPresented: $repeating) { RepeatOptions(state: state) { repeating = false } }
    }

    /// Tap to switch the onion skin on or off; the numbers under it (before · after) open its options.
    private func onion(compact: Bool) -> some View {
        let on = state.onion.enabled
        let layout = axis == .vertical ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: 4))
        return layout {
            Button { state.onion.enabled.toggle() } label: {
                AnimationButtonLabel(icon: on ? "circle.lefthalf.filled.righthalf.striped.horizontal" : "circle.dashed",
                                     caption: "Onion", compact: compact, on: on)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Onion skin")
            .accessibilityValue(on ? "On" : "Off")
            .help("See the drawings before and after this one, faded, to draw in between")
            Button { editingOnion = true } label: {
                Text(verbatim: "\(state.onion.before) · \(state.onion.after)")
                    .font(.system(.caption2, design: .monospaced).weight(.medium))
                    .foregroundStyle(on ? Theme.accentText : Theme.textFaint)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 44, minHeight: 26)
                    .background(Color.white.opacity(0.06), in: Capsule())
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Onion skin options")
            .popover(isPresented: $editingOnion) { OnionOptions(state: state) }
        }
    }

    /// What the buttons act on: the current layer's drawing, or whole frames (every layer).
    private func scope(vertical: Bool) -> some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: 2))
        return layout {
            scopeOption("Layer", on: !state.syncLayers) { state.syncLayers = false }
            scopeOption("All", on: state.syncLayers) { state.syncLayers = true }
        }
        .padding(3)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Act on")
    }

    private func scopeOption(_ title: LocalizedStringKey, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(on ? .semibold : .regular))
                .foregroundStyle(on ? Theme.text : Theme.textDim)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 52, height: 28)
                .background(on ? Theme.raised : .clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A rail action: icon over a short caption, 60 pt wide.
private struct AnimationButton: View {
    let icon: String
    let caption: LocalizedStringKey
    let compact: Bool
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) { AnimationButtonLabel(icon: icon, caption: caption, compact: compact) }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .help(label)
    }
}

private struct AnimationButtonLabel: View {
    let icon: String
    let caption: LocalizedStringKey
    let compact: Bool
    var on = false
    var tint: Color?
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 18, weight: .medium))
            if !compact {
                Text(caption).font(.system(size: 10, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .foregroundStyle(on ? Theme.accentText : (tint ?? Theme.text))
        .frame(width: 60, height: compact ? 40 : 50)
        .background(on ? Theme.accentWash : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(on ? Theme.accent.opacity(0.6) : .clear))
        .opacity(isEnabled ? 1 : 0.35)
        .contentShape(Rectangle())
    }
}

/// How many drawings before / after show through, their colours and strength.
struct OnionOptions: View {
    @Bindable var state: EditorState

    var body: some View {
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
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }
}

/// "Repeat": a cycle of the last few drawings, linked, right after the one at the playhead.
struct RepeatOptions: View {
    @Bindable var state: EditorState
    let done: () -> Void
    @State private var count = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Repeat as a cycle").font(.headline)
            CompactStepper(title: state.syncLayers ? "Last drawings, every layer" : "Last drawings",
                           value: $count, range: 1...max(1, state.drawingsUpToPlayhead))
            Text(count == 1 ? "Adds this drawing again after itself, linked: change one and every repeat changes. Unlink a repeat to make it its own drawing."
                 : "Adds the last \(count) drawings again after this one, linked: change one and every repeat changes. Unlink a repeat to make it its own drawing.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                state.repeatDrawings(count: count)
                done()
            } label: {
                Text(count == 1 ? "Repeat 1 drawing" : "Repeat \(count) drawings")
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.onAccent)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .frame(width: 300)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .onAppear { count = max(1, min(count, state.drawingsUpToPlayhead)) }
    }
}

/// The rail's button for the cell at the playhead: hold the drawing before, or (when held) give it
/// one of its own.
private struct CellButton: View {
    @Bindable var state: EditorState
    let compact: Bool

    var body: some View {
        if state.syncLayers {
            EmptyView()
        } else if state.currentCellIsLinked {
            AnimationButton(icon: "link", caption: "Unlink", compact: compact, label: "Unlink (keep a copy)") {
                state.releaseCurrentCell(copying: true)
            }
        } else if state.currentCellIsHeld {
            Menu {
                Button { state.releaseCurrentCell(copying: false) } label: {
                    Label("New drawing here", systemImage: "square.dashed")
                }
                Button { state.releaseCurrentCell(copying: true) } label: {
                    Label("Copy drawing here", systemImage: "square.on.square")
                }
            } label: {
                AnimationButtonLabel(icon: "square.dashed", caption: "Own drawing", compact: compact)
            }
            .accessibilityLabel("Own drawing")
        } else {
            AnimationButton(icon: "arrow.right.to.line", caption: "Hold", compact: compact, label: "Hold previous drawing") {
                state.holdCurrentCell()
            }
            .disabled(state.frameIndex == 0)
        }
    }
}

/// The More menu: label, inbetweens, cycles, and the whole-frame actions.
private struct MoreMenuItems: View {
    @Bindable var state: EditorState
    @Binding var labeling: Bool
    @Binding var labelText: String
    @Binding var repeating: Bool

    var body: some View {
        if !state.syncLayers {
            Button {
                labelText = state.currentLayer.flatMap { state.drawingLabel(layer: $0.id, at: state.frameIndex) } ?? ""
                labeling = true
            } label: { Label("Label drawing", systemImage: "tag") }
        }
        Menu {
            Button { state.splitCurrentDrawing(copying: false) } label: {
                Label("Blank inbetween halfway", systemImage: "square.split.2x1")
            }
            Button { state.splitCurrentDrawing(copying: true) } label: {
                Label("Duplicate split halfway", systemImage: "square.on.square")
            }
        } label: { Label("Split drawing halfway", systemImage: "square.split.2x1") }
        .disabled(!state.canSplitCurrentDrawing)
        Button { state.beginFrameRange(at: state.frameIndex) } label: {
            Label("Select frames", systemImage: "rectangle.dashed")
        }
        Button { state.beginTween() } label: { Label("Tween motion…", systemImage: "point.bottomleft.forward.to.point.topright.scurvepath") }
            .disabled(state.currentLayer?.locked != false || state.currentDrawingKey == nil)
        Button { repeating = true } label: { Label("Repeat drawings…", systemImage: "repeat") }
            .disabled(state.drawingsUpToPlayhead == 0)
        Section("Frame \(state.frameIndex + 1), all layers") {
            Button { state.addBlankFrame() } label: { Label("Add frame", systemImage: "plus") }
            Button { state.duplicateFrame() } label: { Label("Duplicate frame", systemImage: "plus.square.on.square") }
            Button { state.moveFrame(by: -1) } label: { Label("Move earlier", systemImage: "arrowshape.left") }
                .disabled(state.frameIndex == 0)
            Button { state.moveFrame(by: 1) } label: { Label("Move later", systemImage: "arrowshape.right") }
                .disabled(state.frameIndex >= state.frames.count - 1)
            Button { state.setPlayRange(start: true) } label: { Label("Play from this frame", systemImage: "arrow.right.to.line") }
            Button { state.setPlayRange(start: false) } label: { Label("Play up to this frame", systemImage: "arrow.left.to.line") }
            if state.playRange != nil {
                Button { state.playRange = nil } label: { Label("Play whole clip", systemImage: "arrow.left.and.right") }
            }
            Button(role: .destructive) { state.deleteFrame() } label: { Label("Delete frame", systemImage: "trash") }
                .disabled(state.frames.count <= 1)
        }
    }
}
