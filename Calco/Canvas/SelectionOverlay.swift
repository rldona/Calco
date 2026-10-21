import SwiftUI
import UIKit

/// Draws the lasso while it's being drawn, then the floating selection with its handles:
/// drag inside to move, the corner to scale, the side handles to stretch it wider or taller
/// (squash and stretch), the knob above to rotate, the dot to move the anchor (what scaling and
/// rotation pivot around) without moving the drawing. With Free scaling the corner stretches too.
/// Sits over the canvas view; everywhere it draws nothing, touches reach the canvas.
struct SelectionOverlay: View {
    @ObservedObject var state: EditorState
    @State private var start: FloatingSelection?
    /// Whether the drag in progress is clicked into place; a light tap of haptics when it gets there.
    @State private var snapped = false
    /// Showing the width and height chip: while scaling or stretching.
    @State private var sizing = false
    @AppStorage(ScaleModePicker.key) private var freeScale = false
    private let haptics = UIImpactFeedbackGenerator(style: .light)

    private let handle: CGFloat = 26
    private let rotateReach: CGFloat = 44
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
        let sides: [(point: CGPoint, horizontal: Bool)] = [
            (CGPoint(x: b.maxX, y: b.midY).applying(place), true), (CGPoint(x: b.minX, y: b.midY).applying(place), true),
            (CGPoint(x: b.midX, y: b.maxY).applying(place), false), (topMid, false),
        ]
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

        // Stretch: the middle of each side, along the selection's own width or height, around the
        // anchor. Too small a box has no room for them; the corner in Free mode still stretches.
        if !small {
            ForEach(sides.indices, id: \.self) { i in
                sideHandle(at: sides[i].point, horizontal: sides[i].horizontal, rotation: sel.rotation)
                    .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                        let s = begin(sel)
                        sizing = true
                        let toLocal = s.transform.concatenating(toView).inverted()
                        let snap = stretch(s, horizontal: sides[i].horizontal,
                                           from: g.startLocation.applying(toLocal), to: g.location.applying(toLocal))
                        click(snap)
                    }.onEnded { _ in start = nil; snapped = false; sizing = false })
                    .accessibilityLabel(sides[i].horizontal ? "Stretch width" : "Stretch height")
            }
        }

        // Scale: the bottom-right corner, around the anchor. Uniform keeps the proportions; Free
        // stretches width and height on their own.
        knob(systemImage: "arrow.up.left.and.arrow.down.right", at: corners[2])
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let s = begin(sel)
                sizing = true
                if freeScale {
                    let toLocal = s.transform.concatenating(toView).inverted()
                    let a = g.startLocation.applying(toLocal), c = g.location.applying(toLocal)
                    let x = stretch(s, horizontal: true, from: a, to: c)
                    let y = stretch(s, horizontal: false, from: a, to: c, keepingOther: true)
                    click(x || y)
                    return
                }
                let d0 = Self.distance(g.startLocation, anchor), d1 = Self.distance(g.location, anchor)
                guard d0 > 1 else { return }
                let scale = s.scale * d1 / d0
                let snap = FloatingSelection.snappedScale(scale)
                click(snap != nil)
                state.updateSelection { $0.scale = snap ?? scale }
            }.onEnded { _ in start = nil; snapped = false; sizing = false })
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
            }.onEnded { g in
                snapped = false
                // A tap on the pivot, not a drag: with Move it picks the stroke under it, like anywhere else.
                if state.tool == .move, hypot(g.translation.width, g.translation.height) < 4 {
                    state.liftForMove(at: g.location.applying(toCanvas))
                }
            })
            .accessibilityLabel("Selection anchor")
        }

        // Above the rotate knob, or under the box when there's no room above.
        let barAbove = box.minY - 92 >= 28
        SelectionBar(state: state)
            .position(x: box.midX, y: barAbove ? box.minY - 92 : box.maxY + 52)

        if sizing {
            SizeChip(width: sel.scaleX, height: sel.scaleY)
                .position(x: box.midX, y: barAbove ? box.maxY + 30 : box.minY - 64)
                .allowsHitTesting(false)
        }
    }

    /// Stretches `s` along one of its own axes by how far the finger went from the anchor, from
    /// `a` to `c` (both in the selection's own space). With `keepingOther`, the other axis's
    /// stretch is the one already set in this drag (the corner does both). True when it clicked
    /// into place.
    @discardableResult
    private func stretch(_ s: FloatingSelection, horizontal: Bool, from a: CGPoint, to c: CGPoint,
                         keepingOther: Bool = false) -> Bool {
        let d0 = horizontal ? a.x - s.anchor.x : a.y - s.anchor.y
        let d1 = horizontal ? c.x - s.anchor.x : c.y - s.anchor.y
        guard abs(d0) > 1 else { return false }
        // Past the anchor it would turn inside out: it stops thin instead (Flip is in the bar).
        let ratio = max(d1 / d0, 0.02)
        let current = state.selection?.stretch ?? s.stretch
        let other = horizontal ? (keepingOther ? current.height : s.stretch.height)
                               : (keepingOther ? current.width : s.stretch.width)
        let value = (horizontal ? s.stretch.width : s.stretch.height) * ratio
        let snap = FloatingSelection.snappedStretch(value, scale: s.scale, other: other)
        state.updateSelection {
            if horizontal { $0.stretch.width = snap ?? value } else { $0.stretch.height = snap ?? value }
        }
        return snap != nil
    }

    private func sideHandle(at point: CGPoint, horizontal: Bool, rotation: CGFloat) -> some View {
        Capsule()
            .fill(Theme.accent)
            .overlay(Capsule().strokeBorder(Theme.background, lineWidth: 2))
            .frame(width: horizontal ? 12 : 26, height: horizontal ? 26 : 12)
            .rotationEffect(.radians(rotation))
            .frame(width: 34, height: 34)
            .contentShape(Rectangle())
            .position(point)
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

/// Width and height as a percentage of the original, while scaling or stretching.
private struct SizeChip: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Text("W \(Int((width * 100).rounded()))% · H \(Int((height * 100).rounded()))%")
            .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Theme.panel, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.hairline))
    }
}

/// How the corner handle scales a selection: keeping its proportions, or width and height apart.
/// The side handles always stretch one axis.
struct ScaleModePicker: View {
    static let key = "selection.freeScale"
    @AppStorage(Self.key) private var free = false

    var body: some View {
        HStack(spacing: 2) {
            option("Uniform", icon: "aspectratio", on: !free) { free = false }
            option("Free", icon: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left", on: free) { free = true }
        }
        .padding(3)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10))
        .help("Uniform keeps the proportions when you drag the corner; Free stretches width and height apart")
    }

    private func option(_ title: LocalizedStringKey, icon: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(on ? .semibold : .regular))
                .foregroundStyle(on ? Theme.text : Theme.textDim)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(on ? Theme.panel : .clear, in: RoundedRectangle(cornerRadius: 7))
                .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
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
