import SwiftUI

/// The move grid over the canvas, faint, when it's on and shown. Lines too close together on
/// screen (zoomed far out) are skipped to every other one, so it never turns into a wash.
struct GridOverlay: View {
    @Bindable var state: EditorState

    var body: some View {
        if let grid = state.project.grid, grid.visible, !state.isPlaying {
            GeometryReader { geo in
                let size = state.renderer.canvasSize
                let toView = state.canvasTransform.canvasToView(canvas: size, viewSize: geo.size)
                let zoom = max(hypot(toView.a, toView.b), 0.0001)
                var step = max(grid.step, 1)
                let _ = { while CGFloat(step) * zoom < 6 { step *= 2 } }()
                Path { p in
                    for x in stride(from: 0, through: size.x, by: step) {
                        p.move(to: CGPoint(x: x, y: 0).applying(toView))
                        p.addLine(to: CGPoint(x: x, y: size.y).applying(toView))
                    }
                    for y in stride(from: 0, through: size.y, by: step) {
                        p.move(to: CGPoint(x: 0, y: y).applying(toView))
                        p.addLine(to: CGPoint(x: size.x, y: y).applying(toView))
                    }
                }
                .stroke(Theme.accent.opacity(0.28), lineWidth: 0.75)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// The grid button's options: on or off, the step, and whether the lines show.
struct GridPanel: View {
    @Bindable var state: EditorState

    private var grid: GridSnap { state.project.grid ?? GridSnap() }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(get: { state.project.grid != nil },
                                 set: { state.setGrid($0 ? grid : nil) })) {
                Text("Move on a grid").font(.headline)
            }
            .tint(Theme.accent)
            VStack(alignment: .leading, spacing: 6) {
                Text("Step").font(.subheadline).foregroundStyle(.secondary)
                Picker("Step", selection: Binding(get: { grid.step }, set: { var g = grid; g.step = $0; state.setGrid(g) })) {
                    ForEach(GridSnap.steps, id: \.self) { Text(verbatim: "\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
            }
            .disabled(state.project.grid == nil)
            Toggle("Show the grid", isOn: Binding(get: { grid.visible }, set: { var g = grid; g.visible = $0; state.setGrid(g) }))
                .tint(Theme.accent)
                .disabled(state.project.grid == nil)
            Text("What you move with Move, Transform or Paste sits down on the grid, its top-left corner on a line, in steps of this many pixels. It still clicks back to where it started.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 360)
    }
}
