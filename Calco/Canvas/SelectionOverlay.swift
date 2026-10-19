import SwiftUI
import UIKit

/// Draws the lasso while it's being drawn, then the floating selection with its handles:
/// drag inside to move, the corner to scale, the knob above to rotate, the dot to move the
/// anchor (what scaling and rotation pivot around) without moving the drawing.
/// Sits over the canvas view; everywhere it draws nothing, touches reach the canvas.
struct SelectionOverlay: View {
    @ObservedObject var state: EditorState
    @State private var start: FloatingSelection?
    /// Whether the drag in progress is clicked into place; a light tap of haptics when it gets there.
    @State private var snapped = false
    private let haptics = UIImpactFeedbackGenerator(style: .light)

    private let handle: CGFloat = 26
    private let rotateReach: CGFloat = 34
    private static let fingerSize: CGFloat = 72

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
        let xs = corners.map(\.x), ys = corners.map(\.y)
        let box = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        // A small shape (an eye, a button) is hard to hit and the anchor would cover it: grab it
        // anywhere in a finger-sized square around it, and leave the anchor out.
        let small = min(box.width, box.height) < Self.fingerSize
        let grab = box.insetBy(dx: -max(0, (Self.fingerSize - box.width) / 2), dy: -max(0, (Self.fingerSize - box.height) / 2))

        // Body: drag to move.
        Path { p in p.addLines(outline); p.closeSubpath() }
            .fill(Theme.accent.opacity(0.08))
            .overlay(Path { p in p.addLines(outline); p.closeSubpath() }
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            .contentShape(small ? Path(grab) : Path { p in p.addLines(outline); p.closeSubpath() })
            .gesture(DragGesture(minimumDistance: 1).onChanged { g in
                let s = begin(sel)
                let a = g.startLocation.applying(toCanvas), c = g.location.applying(toCanvas)
                let moved = CGVector(dx: s.offset.dx + c.x - a.x, dy: s.offset.dy + c.y - a.y)
                // 12 points on screen, whatever the zoom.
                let snap = FloatingSelection.snappedOffset(moved, tolerance: Self.snapPoints / Self.zoom(toView))
                click(snap != nil)
                state.updateSelection { $0.offset = snap ?? moved }
            }.onEnded { _ in start = nil; snapped = false })
            // With Move, a tap (not a drag) on a shape inside the box picks just that shape.
            .onTapGesture { p in
                if state.tool == .move { state.liftForMove(at: p.applying(toCanvas)) }
            }
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
                let scale = s.scale * d1 / d0
                let snap = FloatingSelection.snappedScale(scale)
                click(snap != nil)
                state.updateSelection { $0.scale = snap ?? scale }
            }.onEnded { _ in start = nil; snapped = false })
            .accessibilityLabel("Scale selection")

        // Rotate: the knob above the top edge, around the anchor.
        knob(systemImage: "arrow.clockwise", at: rotateKnob)
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let s = begin(sel)
                let a0 = atan2(g.startLocation.y - anchor.y, g.startLocation.x - anchor.x)
                let a1 = atan2(g.location.y - anchor.y, g.location.x - anchor.x)
                // The view may be rotated too; canvas rotation is the same angle either way.
                let rotation = s.rotation + (a1 - a0)
                let snap = FloatingSelection.snappedRotation(rotation)
                click(snap != nil)
                state.updateSelection { $0.rotation = snap ?? rotation }
            }.onEnded { _ in start = nil; snapped = false })
            .accessibilityLabel("Rotate selection")

        // Anchor: drag it anywhere; the drawing stays put. Near the middle it clicks back to it.
        if !small {
        Circle()
            .fill(Theme.background)
            .overlay(Circle().strokeBorder(Theme.accent, lineWidth: 2.5))
            .overlay(Circle().fill(Theme.accent).frame(width: 5, height: 5))
            .frame(width: 18, height: 18)
            .contentShape(Circle().scale(2.4))
            .position(anchor)
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let middle = Self.distance(g.location, centre) < Self.snapPoints
                click(middle)
                state.updateSelection { $0.moveAnchor(to: (middle ? centre : g.location).applying(toCanvas)) }
            }.onEnded { _ in snapped = false })
            .accessibilityLabel("Selection anchor")
        }

        // Above the rotate knob, or under the box when there's no room above.
        SelectionBar(state: state)
            .position(x: box.midX, y: box.minY - 82 >= 28 ? box.minY - 82 : box.maxY + 52)
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

    /// A haptic tap when a drag clicks into place (not while it stays there).
    private func click(_ now: Bool) {
        if now && !snapped { haptics.impactOccurred() }
        snapped = now
    }

    private static let snapPoints: CGFloat = 12

    /// Screen points per canvas pixel.
    private static func zoom(_ toView: CGAffineTransform) -> CGFloat {
        max(hypot(toView.a, toView.b), 0.0001)
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

/// Copy, cut, delete, flip, cancel and apply, floating above the selection.
private struct SelectionBar: View {
    @ObservedObject var state: EditorState

    var body: some View {
        HStack(spacing: 2) {
            RailButton(icon: "doc.on.doc", label: "Copy", size: 32) { state.copySelection() }
            RailButton(icon: "scissors", label: "Cut", size: 32) { state.cutSelection() }
            RailButton(icon: "trash", label: "Delete selection", size: 32) { state.deleteSelection() }
            RailButton(icon: "arrow.left.and.right.righttriangle.left.righttriangle.right", label: "Flip horizontally", size: 32) {
                state.updateSelection { $0.flipped.toggle() }
            }
            RailButton(icon: "xmark", label: "Cancel selection", size: 32) { state.cancelSelection() }
            RailButton(icon: "checkmark", label: "Apply selection", active: true, size: 32) { state.commitSelection() }
        }
        // Corners concentric with the buttons' (9 + 4), so the lit ✓ sits inside the bar.
        .padding(4)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Theme.hairline))
    }
}
