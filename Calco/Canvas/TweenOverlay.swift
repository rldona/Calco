import SwiftUI

/// While a motion tween is set up: the way from the start pose to the end pose (straight, or the
/// arc), each pose in between as a dashed box, and, for an arc, the handle that bends it.
struct TweenOverlay: View {
    @Bindable var state: EditorState

    var body: some View {
        if let session = state.tween, let end = state.selection {
            GeometryReader { geo in
                let toView = state.canvasTransform.canvasToView(canvas: state.renderer.canvasSize, viewSize: geo.size)
                let toCanvas = toView.inverted()
                let a = end.anchor
                let bend = session.curved ? session.bend : .zero
                let point = { (t: CGFloat) -> CGPoint in
                    let o = Tween.path(end.offset, bend: bend, at: t)
                    return CGPoint(x: a.x + o.dx, y: a.y + o.dy).applying(toView)
                }
                ZStack {
                    Path { p in
                        p.move(to: point(0))
                        for i in 1...32 { p.addLine(to: point(CGFloat(i) / 32)) }
                    }
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                    .allowsHitTesting(false)
                    ForEach(Array(state.tweenPoses.enumerated()), id: \.offset) { _, pose in
                        let b = pose.bounds
                        let corners = [CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.maxX, y: b.minY),
                                       CGPoint(x: b.maxX, y: b.maxY), CGPoint(x: b.minX, y: b.maxY)]
                            .map { $0.applying(pose.transform.concatenating(toView)) }
                        Path { p in p.addLines(corners); p.closeSubpath() }
                            .stroke(Theme.accent.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        Circle().fill(Theme.accent.opacity(0.6)).frame(width: 6, height: 6)
                            .position(pose.placedAnchor.applying(toView))
                    }
                    .allowsHitTesting(false)
                    if session.curved {
                        // Drag the arc's middle; near the straight line it clicks back to it.
                        Circle()
                            .fill(Theme.background)
                            .overlay(Circle().strokeBorder(Theme.accent, lineWidth: 2.5))
                            .frame(width: 22, height: 22)
                            .contentShape(Circle().scale(2))
                            .position(point(0.5))
                            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                                let c = g.location.applying(toCanvas)
                                let mid = CGPoint(x: a.x + end.offset.dx / 2, y: a.y + end.offset.dy / 2)
                                var b = CGVector(dx: c.x - mid.x, dy: c.y - mid.y)
                                let zoom = max(hypot(toView.a, toView.b), 0.0001)
                                if hypot(b.dx, b.dy) * zoom < 12 { b = .zero }
                                state.updateTween { $0.bend = b }
                            })
                            .accessibilityLabel("Bend the arc")
                    }
                }
            }
        }
    }
}

/// Under the canvas while a tween is set up: how many frames, the easing, straight or curved,
/// cancel and apply.
struct TweenBar: View {
    @Bindable var state: EditorState

    var body: some View {
        let t = state.tween
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Text("Frames").font(.subheadline).foregroundStyle(Theme.textDim)
                Text("\(t?.count ?? 0)").font(.subheadline.weight(.semibold).monospacedDigit()).frame(minWidth: 20)
                step("minus", -1)
                step("plus", 1)
            }
            .padding(.leading, 10)
            Divider().overlay(Theme.hairline).frame(height: 22)
            Picker("Easing", selection: Binding(get: { t?.easing ?? .easeInOut }, set: { e in state.updateTween { $0.easing = e } })) {
                Text("Linear").tag(Tween.Easing.linear)
                Text("Ease in").tag(Tween.Easing.easeIn)
                Text("Ease out").tag(Tween.Easing.easeOut)
                Text("Smooth").tag(Tween.Easing.easeInOut)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            Toggle(isOn: Binding(get: { t?.curved ?? false }, set: { c in state.updateTween { $0.curved = c } })) {
                Text("Arc").font(.subheadline)
            }
            .toggleStyle(.button)
            if state.tweenReplaces > 0 {
                Text(state.tweenReplaces == 1 ? "Replaces 1 drawing" : "Replaces \(state.tweenReplaces) drawings")
                    .font(.caption).foregroundStyle(Theme.accentText).fixedSize()
            }
            RailButton(icon: "xmark", label: "Cancel tween", size: 34) { state.cancelTween() }
            RailButton(icon: "checkmark", label: "Tween", active: true, size: 34) { state.applyTween() }
        }
        .padding(4)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Theme.hairline))
        .tint(Theme.accent)
    }

    private func step(_ icon: String, _ d: Int) -> some View {
        Button { state.updateTween { $0.count += d } } label: {
            Image(systemName: icon).font(.system(size: 12, weight: .bold))
                .frame(width: 30, height: 28)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }
}
