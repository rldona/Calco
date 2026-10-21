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
            RailButton(icon: "drop.halffull", label: "Fill", active: state.tool == .fill, size: size) {
                if state.tool == .fill { editingFill = true } else { state.tool = .fill }
            }
            .popover(isPresented: $editingFill, arrowEdge: edge) { FillOptions(state: state) }
            RailButton(icon: "eyedropper", label: "Eyedropper", active: state.tool == .eyedropper, size: size) {
                state.tool = .eyedropper
            }
            // Tap once for the lasso, again for select all and paste.
            RailButton(icon: "lasso", label: "Lasso", active: state.tool == .lasso, size: size) {
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
        .frame(width: 230)
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

/// The lasso's options: select the whole drawing, or paste what was copied.
struct LassoOptions: View {
    @Bindable var state: EditorState
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Lasso").font(.headline)
            Button { state.selectAll(); done() } label: {
                Label("Select all", systemImage: "selection.pin.in.out").frame(maxWidth: .infinity, alignment: .leading)
            }
            Button { state.paste(); done() } label: {
                Label("Paste", systemImage: "doc.on.clipboard").frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(state.clipboard == nil)
            Text("Copy or cut from the bar above a selection. Paste lands where it was copied, on whichever frame and layer you're on.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.bordered)
        .padding(20)
        .frame(width: 280)
    }
}
