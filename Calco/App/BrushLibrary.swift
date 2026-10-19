import SwiftUI
import Metal

/// The brush's popover: the library (every brush with a sample stroke) and its settings.
struct BrushPanel: View {
    @ObservedObject var state: EditorState
    @State private var tab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("", selection: $tab) {
                Text("Brushes").tag(0)
                Text("Settings").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding([.horizontal, .top], 16)
            .padding(.bottom, 8)
            if tab == 0 {
                BrushList(state: state, selected: state.brushID) { state.brushID = $0 }
                OpacityRow(state: state).padding(16)
            } else {
                ScrollView { BrushOptions(state: state) }
            }
        }
        .frame(width: 380, height: 560)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }
}

/// The eraser's popover: which brush tip it rubs out with.
struct EraserPanel: View {
    @ObservedObject var state: EditorState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Eraser tip").font(.headline).padding([.horizontal, .top], 16).padding(.bottom, 4)
            Text("Rub out with the edge of any brush: a soft airbrush, a grainy pencil…")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.bottom, 8)
            BrushList(state: state, selected: state.eraserBrushID, ink: false) { state.eraserBrushID = $0 }
        }
        .frame(width: 380, height: 520)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }
}

/// The current brush's opacity.
private struct OpacityRow: View {
    @ObservedObject var state: EditorState

    var body: some View {
        HStack {
            Text("Opacity").font(.subheadline)
            Slider(value: Binding(get: { Double(state.brushOpacity) }, set: { state.brushOpacity = Float($0) }),
                   in: 0.05...1)
            Text("\(Int((state.brushOpacity * 100).rounded()))%")
                .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }
}

/// Every brush, by section, each with a stroke painted by the real engine.
private struct BrushList: View {
    @ObservedObject var state: EditorState
    let selected: String
    var ink = true
    let choose: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Brush.Section.allCases, id: \.self) { section in
                    let brushes = Brush.all.filter { $0.section == section }
                    Text(brushes[0].sectionTitle.uppercased())
                        .font(.caption2.weight(.bold)).foregroundStyle(Theme.textFaint)
                        .padding(.horizontal, 6).padding(.top, 8)
                    ForEach(brushes) { brush in row(brush) }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
    }

    private func row(_ brush: Brush) -> some View {
        let on = brush.id == selected
        return Button { choose(brush.id) } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Label(brush.name, systemImage: brush.icon)
                        .font(.subheadline.weight(on ? .semibold : .regular))
                        .foregroundStyle(on ? Theme.accentText : Theme.text)
                    Text(brush.detail).font(.caption2).foregroundStyle(Theme.textDim)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 140, alignment: .leading)
                BrushSample(brush: brush, ink: ink, device: state.renderer.device)
                    .frame(height: 40)
                    .frame(maxWidth: .infinity)
                    .background(Color(red: 0.957, green: 0.945, blue: 0.918), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(8)
            .background(on ? Theme.accentWash : .clear, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(on ? Theme.accent : .clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(brush.name)
        .accessibilityHint(brush.detail)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// One brush's sample stroke.
private struct BrushSample: View {
    let brush: Brush
    let ink: Bool
    let device: MTLDevice

    var body: some View {
        if let image = BrushSamples.shared.image(for: brush, ink: ink, device: device) {
            Image(decorative: image, scale: 2).resizable().interpolation(.medium).scaledToFit()
        }
    }
}

/// Sample strokes, painted once with the real engine on a small canvas.
@MainActor
final class BrushSamples {
    static let shared = BrushSamples()
    private var cache: [String: CGImage] = [:]
    private var renderer: CanvasRenderer?

    static let size = SIMD2<Int>(400, 80)

    func image(for brush: Brush, ink: Bool, device: MTLDevice) -> CGImage? {
        let key = brush.id + (ink ? "" : "-tip")
        if let image = cache[key] { return image }
        if renderer == nil { renderer = CanvasRenderer(device: device, canvasSize: Self.size, screenFormat: .bgra8Unorm) }
        guard let renderer, let stroke = renderer.makeLayerTexture(), let layer = renderer.makeLayerTexture()
        else { return nil }

        var builder = StrokeBuilder()
        builder.baseRadius = min(max(brush.defaultSize * 1.3, 2.5), 13)
        builder.use(brush)
        builder.begin()
        var stamps: [CanvasRenderer.Stamp] = []
        let n = 120
        for i in 0...n {
            let t = Float(i) / Float(n)
            // An S across the sample, pressing harder in the middle.
            let x = 20 + t * Float(Self.size.x - 40)
            let y = Float(Self.size.y) / 2 + sin(t * .pi * 2) * Float(Self.size.y) * 0.22
            let force = 0.25 + 0.75 * sin(t * .pi)
            stamps += builder.add(.init(position: SIMD2(x, y), force: force))
        }
        let color: SIMD3<Float> = !ink ? SIMD3(0.35, 0.35, 0.38)
            : brush.fixedColor ?? (brush.section == .color ? SIMD3(0.91, 0.45, 0.23) : SIMD3(0.11, 0.10, 0.13))
        renderer.paintStroke(stamps, into: stroke, color: color, tip: .init(brush), hard: false)
        renderer.compositeStroke(stroke, base: nil, into: layer, opacity: ink ? brush.defaultOpacity : 1,
                                 mode: .front, erase: false)
        let image = renderer.readback(layer)
        cache[key] = image
        return image
    }
}
