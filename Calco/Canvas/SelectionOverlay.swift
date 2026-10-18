import SwiftUI

/// Draws the lasso while it's being drawn, then the floating selection with its handles:
/// drag inside to move, the corner to scale, the knob above to rotate, the dot to move the
/// anchor (what scaling and rotation pivot around) without moving the drawing.
/// Sits over the canvas view; everywhere it draws nothing, touches reach the canvas.
struct SelectionOverlay: View {
    @ObservedObject var state: EditorState
    @State private var start: FloatingSelection?

    private let handle: CGFloat = 26
    private let rotateReach: CGFloat = 34

    var body: some View {
        GeometryReader { geo in
            let toView = state.canvasTransform.canvasToView(canvas: state.renderer.canvasSize, viewSize: geo.size)
            ZStack {
                if !state.lassoPoints.isEmpty {
                    Path { p in p.addLines(state.lassoPoints.map { $0.applying(toView) }) }
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .allowsHitTesting(false)
                }
                if let sel = state.selection {
                    selection(sel, toView: toView)
                }
            }
        }
    }

    @ViewBuilder
    private func selection(_ sel: FloatingSelection, toView: CGAffineTransform) -> some View {
        let toCanvas = toView.inverted()
        let place = sel.transform.concatenating(toView)
        let outline = sel.outline.map { $0.applying(place) }
        let b = sel.bounds
        let corners = [CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.maxX, y: b.minY),
                       CGPoint(x: b.maxX, y: b.maxY), CGPoint(x: b.minX, y: b.maxY)].map { $0.applying(place) }
        let anchor = sel.placedAnchor.applying(toView)
        let topMid = CGPoint(x: b.midX, y: b.minY).applying(place)
        let centre = CGPoint(x: b.midX, y: b.midY).applying(place)
        let rotateKnob = Self.extend(from: centre, through: topMid, by: rotateReach)

        // Body: drag to move.
        Path { p in p.addLines(outline); p.closeSubpath() }
            .fill(Theme.accent.opacity(0.08))
            .overlay(Path { p in p.addLines(outline); p.closeSubpath() }
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            .contentShape(Path { p in p.addLines(outline); p.closeSubpath() })
            .gesture(DragGesture(minimumDistance: 1).onChanged { g in
                let s = begin(sel)
                let a = g.startLocation.applying(toCanvas), c = g.location.applying(toCanvas)
                state.updateSelection { $0.offset = CGVector(dx: s.offset.dx + c.x - a.x, dy: s.offset.dy + c.y - a.y) }
            }.onEnded { _ in start = nil })
            .accessibilityLabel("Selection")

        // Bounding box.
        Path { p in p.addLines(corners); p.closeSubpath() }
            .stroke(Theme.textDim.opacity(0.6), lineWidth: 0.75)
            .allowsHitTesting(false)
        Path { p in p.move(to: topMid); p.addLine(to: rotateKnob) }
            .stroke(Theme.textDim.opacity(0.6), lineWidth: 0.75)
            .allowsHitTesting(false)

        // Scale: the bottom-right corner, uniform, around the anchor.
        knob(systemImage: "arrow.up.left.and.arrow.down.right", at: corners[2])
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let s = begin(sel)
                let d0 = Self.distance(g.startLocation, anchor), d1 = Self.distance(g.location, anchor)
                guard d0 > 1 else { return }
                state.updateSelection { $0.scale = s.scale * d1 / d0 }
            }.onEnded { _ in start = nil })
            .accessibilityLabel("Scale selection")

        // Rotate: the knob above the top edge, around the anchor.
        knob(systemImage: "arrow.clockwise", at: rotateKnob)
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let s = begin(sel)
                let a0 = atan2(g.startLocation.y - anchor.y, g.startLocation.x - anchor.x)
                let a1 = atan2(g.location.y - anchor.y, g.location.x - anchor.x)
                // The view may be rotated too; canvas rotation is the same angle either way.
                state.updateSelection { $0.rotation = s.rotation + (a1 - a0) }
            }.onEnded { _ in start = nil })
            .accessibilityLabel("Rotate selection")

        // Anchor: drag it anywhere; the drawing stays put.
        Circle()
            .fill(Theme.background)
            .overlay(Circle().strokeBorder(Theme.accent, lineWidth: 2.5))
            .overlay(Circle().fill(Theme.accent).frame(width: 5, height: 5))
            .frame(width: 18, height: 18)
            .contentShape(Circle().scale(2.4))
            .position(anchor)
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                state.updateSelection { $0.moveAnchor(to: g.location.applying(toCanvas)) }
            })
            .accessibilityLabel("Selection anchor")

        SelectionBar(state: state)
            .position(x: (corners.map(\.x).min()! + corners.map(\.x).max()!) / 2,
                      y: max(28, corners.map(\.y).min()! - 56))
    }

    private func knob(systemImage: String, at point: CGPoint) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Theme.onAccent)
            .frame(width: handle, height: handle)
            .background(Theme.accent, in: Circle())
            .overlay(Circle().strokeBorder(Theme.background, lineWidth: 2))
            .contentShape(Circle().scale(1.6))
            .position(point)
    }

    /// The selection as it was when the current drag began.
    private func begin(_ sel: FloatingSelection) -> FloatingSelection {
        if let start { return start }
        start = sel
        return sel
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    private static func extend(from a: CGPoint, through b: CGPoint, by reach: CGFloat) -> CGPoint {
        let d = distance(a, b)
        guard d > 0.5 else { return CGPoint(x: b.x, y: b.y - reach) }
        return CGPoint(x: b.x + (b.x - a.x) / d * reach, y: b.y + (b.y - a.y) / d * reach)
    }
}

/// Flip, cancel and apply, floating above the selection.
private struct SelectionBar: View {
    @ObservedObject var state: EditorState

    var body: some View {
        HStack(spacing: 2) {
            RailButton(icon: "arrow.left.and.right.righttriangle.left.righttriangle.right", label: "Flip horizontally", size: 32) {
                state.updateSelection { $0.flipped.toggle() }
            }
            RailButton(icon: "xmark", label: "Cancel selection", size: 32) { state.cancelSelection() }
            RailButton(icon: "checkmark", label: "Apply selection", active: true, size: 32) { state.commitSelection() }
        }
        .padding(3)
        .background(Theme.panel, in: Capsule())
    }
}
