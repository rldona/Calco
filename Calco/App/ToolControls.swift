import SwiftUI
import UIKit
import simd

/// Left rail: brush / eraser, colour, size, undo / redo. The size is a vertical slider you can
/// drag with a finger; tapping the number opens the precise popover.
/// Keyboard shortcuts (B, E, [ and ]) live in CalcoCommands.
struct ToolRail: View {
    @ObservedObject var state: EditorState
    @State private var editingSize = false
    @State private var editingColor = false
    @State private var editingFill = false

    var body: some View {
        VStack(spacing: 6) {
            RailButton(icon: "pencil.tip", label: "Brush", active: state.tool == .brush) { state.tool = .brush }
            RailButton(icon: "eraser", label: "Eraser", active: state.tool == .eraser) { state.tool = .eraser }
            // Tap once to pick the bucket, again for its options.
            RailButton(icon: "drop.halffull", label: "Fill", active: state.tool == .fill) {
                if state.tool == .fill { editingFill = true } else { state.tool = .fill }
            }
            .popover(isPresented: $editingFill, arrowEdge: .leading) { FillOptions(state: state) }
            RailButton(icon: "eyedropper", label: "Eyedropper", active: state.tool == .eyedropper) {
                state.tool = .eyedropper
            }
            RailButton(icon: "lasso", label: "Lasso", active: state.tool == .lasso) { state.tool = .lasso }

            Divider().overlay(Theme.hairline).padding(.horizontal, 8).padding(.vertical, 4)

            ColorSwatch(state: state, editing: $editingColor)

            VerticalSizeSlider(state: state)
                .frame(height: 120)
                .padding(.top, 6)
            Button { editingSize = true } label: {
                Text("\(Int(state.toolSize))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.textDim)
                    .frame(width: 36, height: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Size \(Int(state.toolSize))")
            .popover(isPresented: $editingSize, arrowEdge: .leading) { SizePopover(state: state) }

            Spacer(minLength: 12)

            RailButton(icon: "arrow.uturn.backward", label: "Undo") { state.undo() }
                .opacity(state.canUndo ? 1 : 0.35)
            RailButton(icon: "arrow.uturn.forward", label: "Redo") { state.redo() }
                .opacity(state.canRedo ? 1 : 0.35)
        }
        .frame(width: 40)
        .calcoPanel(padding: 5)
    }
}

/// The brush colour; dims while erasing. Tapping opens the palette.
struct ColorSwatch: View {
    @ObservedObject var state: EditorState
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

/// Drag up for bigger, down for smaller. Square-root mapping so small sizes get most of the travel.
private struct VerticalSizeSlider: View {
    @ObservedObject var state: EditorState

    var body: some View {
        GeometryReader { geo in
            let range = EditorState.sizeRange
            let t = CGFloat(sqrt((state.toolSize - range.lowerBound) / (range.upperBound - range.lowerBound)))
            ZStack(alignment: .bottom) {
                Capsule().fill(Theme.hairline).frame(width: 4)
                Capsule().fill(Theme.accent).frame(width: 4, height: max(4, geo.size.height * t))
                Circle()
                    .fill(Theme.text)
                    .frame(width: 14, height: 14)
                    .offset(y: -(geo.size.height - 14) * t)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let f = Float(min(max(1 - g.location.y / geo.size.height, 0), 1))
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

/// The bucket's options: how big a gap in a line it bridges.
struct FillOptions: View {
    @ObservedObject var state: EditorState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fill").font(.headline)
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
    @ObservedObject var state: EditorState

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
    @ObservedObject var state: EditorState

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
