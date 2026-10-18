import SwiftUI
import UIKit
import simd

/// Brush / eraser, size and colour, in the top toolbar.
/// Keyboard shortcuts (B, E, [ and ]) live in CalcoCommands.
struct ToolControls: View {
    @ObservedObject var state: EditorState
    @State private var editingSize = false
    @State private var editingColor = false

    var body: some View {
        HStack(spacing: 10) {
            Picker("Tool", selection: $state.tool) {
                Image(systemName: "pencil.tip").tag(CanvasRenderer.Tool.brush)
                Image(systemName: "eraser").tag(CanvasRenderer.Tool.eraser)
            }
            .pickerStyle(.segmented)
            .frame(width: 110)

            Button { editingSize = true } label: {
                HStack(spacing: 5) {
                    SizeDot(size: state.toolSize, maxDiameter: 18)
                    Text("\(Int(state.toolSize))")
                        .font(.system(.caption, design: .monospaced))
                        .frame(minWidth: 18, alignment: .leading)
                }
            }
            .help("Size")
            .popover(isPresented: $editingSize) { SizePopover(state: state) }

            Button { editingColor = true } label: {
                Circle()
                    .fill(Color(rgba: state.color))
                    .frame(width: 22, height: 22)
                    .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 2))
                    .shadow(radius: 1)
                    .opacity(state.tool == .eraser ? 0.4 : 1)
            }
            .help("Colour")
            .popover(isPresented: $editingColor) { ColorPopover(state: state) }
        }
    }
}

/// A dot whose diameter follows the tool size (capped so it fits the toolbar).
private struct SizeDot: View {
    let size: Float
    let maxDiameter: CGFloat

    var body: some View {
        let range = EditorState.sizeRange
        let t = CGFloat((size - range.lowerBound) / (range.upperBound - range.lowerBound))
        Circle()
            .fill(.primary)
            .frame(width: 3 + sqrt(t) * (maxDiameter - 3), height: 3 + sqrt(t) * (maxDiameter - 3))
            .frame(width: maxDiameter, height: maxDiameter)
    }
}

private struct SizePopover: View {
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

private struct ColorPopover: View {
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
                                .strokeBorder(c == state.color ? Color.accentColor : .white.opacity(0.2),
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
