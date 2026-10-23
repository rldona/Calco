import SwiftUI
import UIKit
import simd

/// Left rail: brush / eraser, colour, size, undo / redo. The size is a slider you can drag with
/// a finger; tapping the number opens the precise popover. In portrait it lies across the top
/// (`axis: .horizontal`), where there's height to spare, and the canvas gets the whole width.
/// Keyboard shortcuts (B, E, [ and ]) live in CalcoCommands.
struct ToolRail: View {
    @Bindable var state: EditorState
    var axis: Axis = .vertical
    @State private var editingSize = false
    @State private var editingColor = false
    @State private var editingFill = false
    @State private var editingBrush = false
    @State private var editingEraser = false
    @State private var editingLasso = false
    @State private var editingShape = false
    @State private var editingPen = false
    @State private var editingNode = false
    @State private var editingSmudge = false

    var body: some View {
        Group {
            if axis == .vertical {
                // Full size while there's room; tighter when the timeline is tall (or many layers) so
                // the canvas, not the timeline, gives up the space.
                ViewThatFits(in: .vertical) {
                    tools(compact: false).fixedSize(horizontal: false, vertical: true)
                    tools(compact: true).fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 40)
            } else {
                tools(compact: false).fixedSize().frame(height: 40)
            }
        }
        .calcoPanel(padding: 5)
        .onChange(of: state.colorPickerRequest) { editingColor = true }
    }

    static let penIcon = "point.topleft.down.to.point.bottomright.curvepath"
    static let smudgeIcon = "hand.point.up.left"
    static let nodeIcon = "cursorarrow"

    /// Popovers point away from the rail: right of it on the side, below it on top.
    private var edge: Edge { axis == .vertical ? .leading : .top }

    private func tools(compact: Bool) -> some View {
        let size: CGFloat = compact ? 32 : 36
        let layout = axis == .vertical ? AnyLayout(VStackLayout(spacing: compact ? 1 : 6))
                                       : AnyLayout(HStackLayout(spacing: 4))
        return layout {
            // Like the bucket: tap once to pick the brush, again for its options.
            RailButton(icon: state.brush.icon, label: "Brush", active: state.tool == .brush, size: size) {
                if state.tool == .brush { editingBrush = true } else { state.tool = .brush }
            }
            .popover(isPresented: $editingBrush, arrowEdge: edge) { BrushPanel(state: state) }
            // Tap once for the eraser, again for its tip.
            RailButton(icon: "eraser", label: "Eraser", active: state.tool == .eraser, size: size) {
                if state.tool == .eraser { editingEraser = true } else { state.tool = .eraser }
            }
            .popover(isPresented: $editingEraser, arrowEdge: edge) { EraserPanel(state: state) }
            // Tap once to pick the bucket, again for its options.
            RailButton(icon: "FillBucket", label: "Fill", active: state.tool == .fill, size: size) {
                if state.tool == .fill { editingFill = true } else { state.tool = .fill }
            }
            .popover(isPresented: $editingFill, arrowEdge: edge) { FillOptions(state: state) }
            RailButton(icon: "eyedropper", label: "Eyedropper", active: state.tool == .eyedropper, size: size) {
                state.tool = .eyedropper
            }
            // Shows how it marks; tap again for freehand, rectangle or wand, and select all, invert and paste.
            RailButton(icon: state.select.shape.icon, label: "Select", active: state.tool == .lasso, size: size) {
                if state.tool == .lasso { editingLasso = true } else { state.tool = .lasso }
            }
            .popover(isPresented: $editingLasso, arrowEdge: edge) { LassoOptions(state: state) { editingLasso = false } }
            // Picks up the whole drawing; tap a shape on the canvas to move just that one.
            RailButton(icon: "arrow.up.and.down.and.arrow.left.and.right", label: "Move", active: state.tool == .move, size: size) {
                if state.tool == .move { state.liftForMove() } else { state.tool = .move }
            }
            // Shows the shape it draws; tap again for the shapes and their outline and fill.
            RailButton(icon: state.shapeOptions.kind.icon, label: "Shapes", active: state.tool == .shape, size: size) {
                if state.tool == .shape { editingShape = true } else { state.tool = .shape }
            }
            .popover(isPresented: $editingShape, arrowEdge: edge) { ShapePanel(state: state) }
            // Points joined by lines and curves; tap again for its outline and fill.
            RailButton(icon: Self.penIcon, label: "Pen", active: state.tool == .pen, size: size) {
                if state.tool == .pen { editingPen = true } else { state.tool = .pen }
            }
            .popover(isPresented: $editingPen, arrowEdge: edge) { ShapePanel(state: state, pen: true) }
            // Edits paths and shapes point by point, and never draws; tap again for their style.
            RailButton(icon: Self.nodeIcon, label: "Node", active: state.tool == .node, size: size) {
                if state.tool == .node { editingNode = true } else { state.tool = .node }
            }
            .popover(isPresented: $editingNode, arrowEdge: edge) { ShapePanel(state: state, pen: true, node: true) }
            // Smudge, blur or motion; tap again for which and how strongly.
            RailButton(icon: Self.smudgeIcon, label: "Smudge", active: state.tool == .smudge, size: size) {
                if state.tool == .smudge { editingSmudge = true } else { state.tool = .smudge }
            }
            .popover(isPresented: $editingSmudge, arrowEdge: edge) { SmudgePanel(state: state) }

            if axis == .vertical {
                Divider().overlay(Theme.hairline).padding(.horizontal, 8).padding(.vertical, compact ? 2 : 4)
            } else {
                Divider().overlay(Theme.hairline).frame(height: 22).padding(.horizontal, 4)
            }

            ColorSwatch(state: state, editing: $editingColor)

            if axis == .vertical {
                // Gives up height first when the timeline is stretched, so the canvas can shrink.
                SizeSlider(state: state, axis: .vertical)
                    .frame(minHeight: compact ? 28 : 44, maxHeight: 120)
                    .padding(.top, compact ? 2 : 6)
            } else {
                SizeSlider(state: state, axis: .horizontal)
                    .frame(width: 120)
                    .padding(.leading, 6)
            }
            Button { editingSize = true } label: {
                Text("\(Int(state.toolSize))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.textDim)
                    .frame(width: 36, height: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Size \(Int(state.toolSize))")
            .popover(isPresented: $editingSize, arrowEdge: edge) { SizePopover(state: state) }

            if axis == .vertical {
                Spacer(minLength: 4)
            } else {
                Divider().overlay(Theme.hairline).frame(height: 22).padding(.horizontal, 4)
            }

            RailButton(icon: "arrow.uturn.backward", label: "Undo", size: size) { state.undo() }
                .opacity(state.canUndo ? 1 : 0.35)
            RailButton(icon: "arrow.uturn.forward", label: "Redo", size: size) { state.redo() }
                .opacity(state.canRedo ? 1 : 0.35)
        }
    }
}

/// The brush colour; dims while erasing. Tapping opens the palette.
struct ColorSwatch: View {
    @Bindable var state: EditorState
    @Binding var editing: Bool
    var diameter: CGFloat = 24

    var body: some View {
        Button { editing = true } label: {
            Circle()
                .fill(Color(rgba: state.color))
                .frame(width: diameter, height: diameter)
                .overlay(Circle().strokeBorder(Theme.text.opacity(0.85), lineWidth: 2))
                .opacity(state.tool == .eraser ? 0.4 : 1)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Colour")
        .help("Colour")
        .popover(isPresented: $editing) { ColorPopover(state: state) }
    }
}

/// Drag up (or right) for bigger. Square-root mapping so small sizes get most of the travel.
private struct SizeSlider: View {
    @Bindable var state: EditorState
    let axis: Axis

    var body: some View {
        GeometryReader { geo in
            let range = EditorState.sizeRange
            let t = CGFloat(sqrt((state.toolSize - range.lowerBound) / (range.upperBound - range.lowerBound)))
            let length = axis == .vertical ? geo.size.height : geo.size.width
            ZStack(alignment: axis == .vertical ? .bottom : .leading) {
                if axis == .vertical {
                    Capsule().fill(Theme.hairline).frame(width: 4)
                    Capsule().fill(Theme.accent).frame(width: 4, height: max(4, length * t))
                } else {
                    Capsule().fill(Theme.hairline).frame(height: 4)
                    Capsule().fill(Theme.accent).frame(width: max(4, length * t), height: 4)
                }
                Circle()
                    .fill(Theme.text)
                    .frame(width: 14, height: 14)
                    .offset(x: axis == .vertical ? 0 : (length - 14) * t,
                            y: axis == .vertical ? -(length - 14) * t : 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let along = axis == .vertical ? 1 - g.location.y / length : g.location.x / length
                let f = Float(min(max(along, 0), 1))
                state.toolSize = range.lowerBound + f * f * (range.upperBound - range.lowerBound)
            })
        }
        .accessibilityElement()
        .accessibilityLabel(state.tool == .eraser ? "Eraser size" : "Brush size")
        .accessibilityValue("\(Int(state.toolSize))")
        .accessibilityAdjustableAction { direction in
            state.stepToolSize(direction == .increment ? 1 : -1)
        }
    }
}

/// The brush's options: where it draws, stabiliser, pressure and pixel art.
struct BrushOptions: View {
    @Bindable var state: EditorState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(state.brush.name).font(.headline)
            PaintModePicker(state: state)
            Divider()
            HStack {
                Text("Smoothing").font(.subheadline)
                Spacer()
                Text(state.smoothing == 0 ? "Off" : "\(Int((state.smoothing * 100).rounded()))%")
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { Double(state.smoothing) }, set: { state.smoothing = Float($0) }), in: 0...1)
            Text("Steadies the line: it trails the pen a little and irons out wobble. Higher is calmer, with more lag.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            Toggle("Pencil pressure changes size", isOn: $state.usePressure).font(.subheadline)
            Toggle("Only Apple Pencil draws", isOn: $state.pencilOnly).font(.subheadline)
            Text("Fingers still zoom, pan and undo. Double tap or squeeze the Pencil does what you chose in Settings → Apple Pencil.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            Toggle("Pixel art", isOn: Binding(get: { state.project.pixelArt }, set: { state.setPixelArt($0) }))
                .font(.subheadline)
            Text("This project: brush, eraser, fill and lasso with hard edges, every pixel fully on or off.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 300)
    }
}

/// The bucket's options: how big a gap in a line it bridges.
struct FillOptions: View {
    @Bindable var state: EditorState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fill").font(.headline)
            PaintModePicker(state: state)
            Divider()
            Text("Close gaps").font(.subheadline).foregroundStyle(.secondary)
            Picker("Close gaps", selection: $state.fillGaps) {
                ForEach(EditorState.FillGaps.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Text("Bridges small breaks in a line so the paint doesn't leak out. Uses every visible layer as the outline.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 300)
    }
}

struct SizePopover: View {
    @Bindable var state: EditorState

    var body: some View {
        VStack(spacing: 14) {
            Text(state.tool == .eraser ? "Eraser size" : "Brush size")
                .font(.headline)
            // Preview at canvas scale (fit, unzoomed would be smaller; this is the radius ×2 in points).
            Circle()
                .fill(state.tool == .eraser ? Color.secondary : Color(rgba: state.color))
                .frame(width: CGFloat(state.toolSize) * 2, height: CGFloat(state.toolSize) * 2)
                .frame(width: 136, height: 136)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Button { state.stepToolSize(-1) } label: { Image(systemName: "minus") }
                Slider(value: Binding(get: { state.toolSize }, set: { state.toolSize = $0 }),
                       in: EditorState.sizeRange)
                Button { state.stepToolSize(1) } label: { Image(systemName: "plus") }
            }
            Text("\(Int(state.toolSize)) px")
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .padding(20)
        .frame(width: 280)
    }
}

struct ColorPopover: View {
    @Bindable var state: EditorState

    /// Neutrals first, then a hue wheel, then skin and earth tones.
    static let palette: [UInt32] = [
        0x000000, 0x4A4A4A, 0x9B9B9B, 0xFFFFFF,
        0xE53935, 0xFB8C00, 0xFDD835, 0x43A047,
        0x00ACC1, 0x1E88E5, 0x8E24AA, 0xD81B60,
        0xF6D2B8, 0xD9A066, 0x8D5A3B, 0x4E342E,
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Colour").font(.headline)
            ProjectPalette(state: state)
            Text("Basics").font(.caption2.weight(.bold)).textCase(.uppercase).foregroundStyle(Theme.textFaint)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(40), spacing: 10), count: 4), spacing: 10) {
                ForEach(Self.palette, id: \.self) { hex in
                    let c = SIMD4<Float>(hex: hex)
                    Button { state.setColor(c) } label: {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(rgba: c))
                            .frame(width: 40, height: 40)
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(c == state.color ? Theme.accent : .white.opacity(0.2),
                                              lineWidth: c == state.color ? 3 : 1))
                    }
                    .accessibilityLabel(String(format: "#%06X", hex))
                }
            }
            ColorPicker("Custom", selection: Binding(
                get: { Color(rgba: state.color) },
                set: { state.setColor(SIMD4<Float>($0)) }),
                        supportsOpacity: false)
        }
        .buttonStyle(.plain)
        .padding(20)
        .frame(width: 250)
    }
}

/// The project's own colours, named, above the basics: tap one to paint with it, + to keep the
/// current colour, and long-press one to rename it, change it everywhere, make a variant or
/// remove it.
private struct ProjectPalette: View {
    @Bindable var state: EditorState
    @State private var renaming: PaletteColor?
    @State private var newName = ""
    @State private var changing: PaletteColor?

    private let columns = Array(repeating: GridItem(.fixed(40), spacing: 10), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(state.project.name) palette").font(.caption2.weight(.bold)).textCase(.uppercase)
                .foregroundStyle(Theme.textFaint).lineLimit(1)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(state.project.palette) { entry in swatch(entry) }
                Button { state.addColorToPalette() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 40, height: 40)
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                }
                .accessibilityLabel("Add the current colour to the palette")
            }
            if state.project.palette.isEmpty {
                Button { state.suggestPalette() } label: {
                    Label("From the drawings", systemImage: "wand.and.stars").font(.caption)
                }
                .buttonStyle(.bordered)
                .help("Picks the colours the drawings are mostly made of")
            }
        }
        .alert("Rename colour", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") { if let r = renaming { state.renamePaletteColor(r.id, to: newName) } }
            Button("Cancel", role: .cancel) {}
        }
        // A sheet, not a popover: from inside the colour popover the system picker couldn't open.
        .sheet(item: $changing) { entry in PaletteChangeSheet(state: state, entry: entry) }
    }

    private func swatch(_ entry: PaletteColor) -> some View {
        let rgb = entry.rgb
        let on = simd_reduce_max(simd_abs(rgb - SIMD3(state.color.x, state.color.y, state.color.z))) < 1.5 / 255
        return Button { state.setColor(SIMD4(rgb, 1)) } label: {
            VStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(rgba: SIMD4(rgb, 1)))
                    .frame(width: 40, height: 40)
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(on ? Theme.accent : .white.opacity(0.2), lineWidth: on ? 3 : 1))
                Text(entry.name).font(.system(size: 9)).foregroundStyle(Theme.textDim).lineLimit(1).frame(width: 46)
            }
        }
        .accessibilityLabel(entry.name)
        .contextMenu {
            Button { changing = entry } label: {
                Label("Change everywhere…", systemImage: "paintpalette")
            }
            Button { newName = entry.name; renaming = entry } label: { Label("Rename…", systemImage: "pencil") }
            Button { state.duplicatePaletteColor(entry.id) } label: { Label("Duplicate as variant", systemImage: "plus.square.on.square") }
            Button(role: .destructive) { state.removePaletteColor(entry.id) } label: { Label("Remove from palette", systemImage: "trash") }
        }
    }
}

/// Pick the new colour for a palette entry; Change everywhere repaints it in every drawing.
private struct PaletteChangeSheet: View {
    @Bindable var state: EditorState
    let entry: PaletteColor
    @State private var newColor: Color
    @Environment(\.dismiss) private var dismiss

    init(state: EditorState, entry: PaletteColor) {
        self.state = state
        self.entry = entry
        _newColor = State(initialValue: Color(rgba: SIMD4(entry.rgb, 1)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(entry.name).font(.headline)
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8).fill(Color(rgba: SIMD4(entry.rgb, 1))).frame(width: 44, height: 44)
                Image(systemName: "arrow.right").foregroundStyle(Theme.textDim)
                RoundedRectangle(cornerRadius: 8).fill(newColor).frame(width: 44, height: 44)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.accent, lineWidth: 2))
                Spacer()
                ColorPicker("Custom", selection: $newColor, supportsOpacity: false)
                    .fixedSize()
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 8), count: 8), spacing: 8) {
                ForEach(state.project.palette.map(\.rgb).map { SIMD4($0, 1) } + ColorPopover.palette.map { SIMD4<Float>(hex: $0) },
                        id: \.self) { c in
                    Button { newColor = Color(rgba: c) } label: {
                        RoundedRectangle(cornerRadius: 7).fill(Color(rgba: c)).frame(width: 36, height: 36)
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(0.2)))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Repaints every pixel of this colour, soft edges too, in every drawing of every clip. One undo.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                let v = SIMD4<Float>(newColor)
                state.changePaletteColorEverywhere(entry.id, to: SIMD3(v.x, v.y, v.z))
                dismiss()
            } label: {
                Text("Change everywhere").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            Button("Cancel", role: .cancel) { dismiss() }
                .frame(maxWidth: .infinity)
        }
        .padding(24)
        .presentationDetents([.medium])
        .frame(maxWidth: 420)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Colour conversion

extension SIMD4 where Scalar == Float {
    init(hex: UInt32) {
        self.init(Float((hex >> 16) & 0xFF) / 255, Float((hex >> 8) & 0xFF) / 255, Float(hex & 0xFF) / 255, 1)
    }

    /// sRGB components of a SwiftUI colour, clamped to 0...1.
    init(_ color: Color) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(simd_clamp(SIMD3<Float>(Float(r), Float(g), Float(b)), .zero, .one), Float(a))
    }
}

extension Color {
    init(rgba c: SIMD4<Float>) {
        self.init(.sRGB, red: Double(c.x), green: Double(c.y), blue: Double(c.z), opacity: Double(c.w))
    }
}

/// Where new paint lands on the layer, shared by brush and fill.
struct PaintModePicker: View {
    @Bindable var state: EditorState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Draws").font(.subheadline).foregroundStyle(.secondary)
            Picker("Draws", selection: $state.paintMode) {
                ForEach(CanvasRenderer.PaintMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(state.paintMode.explanation)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension CanvasRenderer.PaintMode {
    var explanation: String {
        switch self {
        case .front: String(localized: "Over what's already on the layer.", bundle: AppLanguage.bundle)
        case .behind: String(localized: "Under what's already on the layer: colour under line art without touching the lines.", bundle: AppLanguage.bundle)
        case .inside: String(localized: "Only on what's already drawn, keeping its edges: shading and recolouring.", bundle: AppLanguage.bundle)
        }
    }
}

/// The Select tool's options: how it marks, how a new mark meets the selection, the wand's
/// tolerance, then select all, invert and paste.
struct LassoOptions: View {
    @Bindable var state: EditorState
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select").font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                Text("Shape").font(.subheadline).foregroundStyle(.secondary)
                Picker("Shape", selection: $state.select.shape) {
                    ForEach(EditorState.SelectOptions.Shape.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("When you mark").font(.subheadline).foregroundStyle(.secondary)
                Picker("When you mark", selection: $state.select.combine) {
                    ForEach(SelectionMask.Combine.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            if state.select.shape == .wand {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tolerance · \(Int((state.select.tolerance * 100).rounded())) %")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Slider(value: $state.select.tolerance, in: 0...1, step: 0.01)
                    Text("How alike a colour must be to the one you tap to be picked too.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Divider()
            Button { state.selectAll(); done() } label: {
                Label("Select all", systemImage: "selection.pin.in.out").frame(maxWidth: .infinity, alignment: .leading)
            }
            Button { state.invertSelection(); done() } label: {
                Label("Invert selection", systemImage: "arrow.left.arrow.right.square").frame(maxWidth: .infinity, alignment: .leading)
            }
            Button { state.paste(); done() } label: {
                Label("Paste", systemImage: "doc.on.clipboard").frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(state.clipboard == nil)
            Text("While something is selected, the brush, eraser, fill, shapes and smudge only reach inside it.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.bordered)
        .padding(20)
        .frame(width: 320)
    }
}

extension EditorState.SelectOptions.Shape {
    var icon: String {
        switch self {
        case .free: "lasso"
        case .rect: "rectangle.dashed"
        case .wand: "wand.and.stars"
        }
    }
    var title: String {
        switch self {
        case .free: String(localized: "Freehand", bundle: AppLanguage.bundle)
        case .rect: String(localized: "Rectangle", bundle: AppLanguage.bundle)
        case .wand: String(localized: "Wand", bundle: AppLanguage.bundle)
        }
    }
}

extension SelectionMask.Combine {
    var title: String {
        switch self {
        case .replace: String(localized: "Replace", bundle: AppLanguage.bundle)
        case .add: String(localized: "Add", bundle: AppLanguage.bundle)
        case .subtract: String(localized: "Subtract", bundle: AppLanguage.bundle)
        }
    }
}
