import SwiftUI
import UIKit

/// The symmetry axes over the canvas, dashed, each with a knob just outside the canvas to drag
/// it (it clicks onto half pixels, and back to the middle); a double tap on a knob centres both.
/// Only the knobs catch touches: drawing goes through the lines.
struct SymmetryOverlay: View {
    @Bindable var state: EditorState
    @State private var snapped = false
    private let haptics = UIImpactFeedbackGenerator(style: .light)
    private static let knob: CGFloat = 22

    var body: some View {
        if let sym = state.project.symmetry, !state.isPlaying {
            GeometryReader { geo in
                let size = state.renderer.canvasSize
                let toView = state.canvasTransform.canvasToView(canvas: size, viewSize: geo.size)
                let toCanvas = toView.inverted()
                let w = CGFloat(size.x), h = CGFloat(size.y)
                ZStack {
                    if sym.mirrorsX {
                        let top = CGPoint(x: sym.x, y: 0).applying(toView), bottom = CGPoint(x: sym.x, y: h).applying(toView)
                        axis(from: top, to: bottom)
                        handle(at: Self.beyond(top, from: bottom))
                            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                                let x = g.location.applying(toCanvas).x
                                let middle = abs(x - w / 2) * Self.zoom(toView) < 10
                                click(middle)
                                state.moveSymmetryAxis(x: middle ? Double(w / 2) : Double(x))
                            }.onEnded { _ in snapped = false })
                            .onTapGesture(count: 2) { state.centerSymmetryAxes() }
                            .accessibilityLabel("Vertical symmetry axis")
                    }
                    if sym.mirrorsY {
                        let left = CGPoint(x: 0, y: sym.y).applying(toView), right = CGPoint(x: w, y: sym.y).applying(toView)
                        axis(from: left, to: right)
                        handle(at: Self.beyond(left, from: right))
                            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                                let y = g.location.applying(toCanvas).y
                                let middle = abs(y - h / 2) * Self.zoom(toView) < 10
                                click(middle)
                                state.moveSymmetryAxis(y: middle ? Double(h / 2) : Double(y))
                            }.onEnded { _ in snapped = false })
                            .onTapGesture(count: 2) { state.centerSymmetryAxes() }
                            .accessibilityLabel("Horizontal symmetry axis")
                    }
                }
            }
        }
    }

    private func axis(from a: CGPoint, to b: CGPoint) -> some View {
        Path { p in p.move(to: a); p.addLine(to: b) }
            .stroke(Theme.accent.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            .allowsHitTesting(false)
    }

    private func handle(at p: CGPoint) -> some View {
        Circle()
            .fill(Theme.accent)
            .overlay(Circle().strokeBorder(Theme.background, lineWidth: 2))
            .frame(width: Self.knob, height: Self.knob)
            .contentShape(Circle().scale(2))
            .position(p)
    }

    /// A haptic tap when the axis clicks back to the middle.
    private func click(_ now: Bool) {
        if now && !snapped { haptics.impactOccurred() }
        snapped = now
    }

    /// 18 points past `end`, along the line from `other`: just outside the canvas.
    private static func beyond(_ end: CGPoint, from other: CGPoint) -> CGPoint {
        let d = hypot(end.x - other.x, end.y - other.y)
        guard d > 0.5 else { return CGPoint(x: end.x, y: end.y - 18) }
        return CGPoint(x: end.x + (end.x - other.x) / d * 18, y: end.y + (end.y - other.y) / d * 18)
    }

    /// Screen points per canvas pixel.
    private static func zoom(_ t: CGAffineTransform) -> CGFloat { max(hypot(t.a, t.b), 0.0001) }
}

/// The symmetry button's options: off, left–right, top–bottom or four ways, and centring the axes.
struct SymmetryPanel: View {
    @Bindable var state: EditorState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Symmetry").font(.headline)
            Picker("Symmetry", selection: Binding(get: { state.project.symmetry?.mode }, set: { state.setSymmetry($0) })) {
                Text("Off").tag(Symmetry.Mode?.none)
                Label("Left–right", systemImage: "square.split.2x1").tag(Symmetry.Mode?.some(.vertical))
                Label("Top–bottom", systemImage: "square.split.1x2").tag(Symmetry.Mode?.some(.horizontal))
                Label("Four ways", systemImage: "square.grid.2x2").tag(Symmetry.Mode?.some(.both))
            }
            .pickerStyle(.segmented)
            Text("The brush, eraser and smudge paint again in the mirror. Drag the dot at the end of an axis to move it; a double tap centres it.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button { state.centerSymmetryAxes() } label: {
                Label("Centre the axes", systemImage: "scope").frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .disabled(state.project.symmetry == nil)
        }
        .padding(20)
        .frame(width: 400)
    }
}
