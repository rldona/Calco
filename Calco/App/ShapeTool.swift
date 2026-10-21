import SwiftUI

/// The Shapes tool's popover: which shape, its outline, size, fill and brush. The Pen uses it too,
/// without the shapes.
struct ShapePanel: View {
    @Bindable var state: EditorState
    var pen = false

    private var o: ShapeOptions { state.shapeOptions }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(pen ? "Pen" : "Shapes").font(.headline)

            if !pen {
            caption("Shape")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(ShapeOptions.Kind.allCases) { kind in
                    let on = kind == o.kind
                    Button { state.shapeOptions.kind = kind } label: {
                        Image(systemName: kind.icon)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(on ? Theme.accentText : Theme.text)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(on ? Theme.accentWash : Theme.raised, in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(on ? Theme.accent : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(kind.name)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            if o.kind == .polygon {
                Stepper(value: $state.shapeOptions.sides, in: ShapeOptions.sidesRange) {
                    Text("\(o.sides) sides").font(.subheadline)
                }
            } else if o.kind == .star {
                Stepper(value: $state.shapeOptions.points, in: ShapeOptions.pointsRange) {
                    Text("\(o.points) points").font(.subheadline)
                }
            }
            }

            caption("Outline")
            Picker("Outline", selection: $state.shapeOptions.outline) {
                Text("Solid").tag(ShapeOptions.Outline.solid)
                Text("Dashed").tag(ShapeOptions.Outline.dashed)
                Text("Dotted").tag(ShapeOptions.Outline.dotted)
            }
            .pickerStyle(.segmented)
            .disabled(o.fill == .only && (o.canFill || pen))

            HStack {
                caption("Thickness")
                Spacer()
                Text("\(Int(o.size)) px").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { Double(o.size) }, set: { state.shapeOptions.size = Float($0.rounded()) }),
                   in: Double(EditorState.sizeRange.lowerBound)...Double(min(EditorState.sizeRange.upperBound, 60)))
                .disabled(o.fill == .only && (o.canFill || pen))

            caption("Fill")
            Picker("Fill", selection: $state.shapeOptions.fill) {
                Text("No fill").tag(ShapeOptions.Fill.none)
                Text("Filled").tag(ShapeOptions.Fill.filled)
                Text("Fill only").tag(ShapeOptions.Fill.only)
            }
            .pickerStyle(.segmented)
            .disabled(!o.canFill && !pen)

            caption("Brush")
            Picker("Brush", selection: $state.shapeOptions.useBrush) {
                Text(Brush.inker.name).tag(false)
                Text(state.brush.name).tag(true)
            }
            .pickerStyle(.segmented)

            Text(pen ? "Tap to place points; drag as you place one, or pull a point, to curve it. Tap the line to add a point, the first point to close the path. The fill is for closed paths."
                     : "Drag from corner to corner. Near even, it clicks into a square or a circle; lines click every 45°. In the bar's colour.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 320)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }

    private func caption(_ title: LocalizedStringKey) -> some View {
        Text(title).font(.caption2.weight(.bold)).textCase(.uppercase).foregroundStyle(Theme.textFaint)
    }
}

/// The shape being dragged out, drawn over the canvas until the finger lifts, and what it
/// clicked into.
struct ShapeDraftOverlay: View {
    @Bindable var state: EditorState

    var body: some View {
        if let draft = state.shapeDraft {
            GeometryReader { geo in
                let toView = state.canvasTransform.canvasToView(canvas: state.renderer.canvasSize, viewSize: geo.size)
                let zoom = max(hypot(toView.a, toView.b), 0.0001)
                let o = state.shapeOptions
                let paths = ShapeGeometry.paths(o, from: draft.from, to: draft.to)
                let ink = Color(rgba: state.shapeInk).opacity(o.useBrush ? Double(state.brushOpacity) : 1)
                let width = CGFloat(o.size) * 2 * zoom
                let outline = Path { p in
                    for path in paths {
                        p.addLines(path.points.map { $0.applying(toView) })
                        if path.closed { p.closeSubpath() }
                    }
                }
                ZStack {
                    if o.fill != .none, let fill = ShapeGeometry.fillPolygon(o, from: draft.from, to: draft.to) {
                        Path { p in p.addLines(fill.map { $0.applying(toView) }); p.closeSubpath() }.fill(ink)
                    }
                    if !(o.fill == .only && o.canFill) {
                        outline.stroke(ink, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round,
                                                               dash: Self.dash(o.outline, width: width)))
                    }
                    chip(draft, o)
                        .position(x: CGRect(origin: draft.from.applying(toView), size: .zero)
                                    .union(CGRect(origin: draft.to.applying(toView), size: .zero)).midX,
                                  y: max(draft.from.applying(toView).y, draft.to.applying(toView).y) + width / 2 + 26)
                }
            }
            .allowsHitTesting(false)
        }
    }

    static func dash(_ outline: ShapeOptions.Outline, width: CGFloat) -> [CGFloat] {
        switch outline {
        case .solid: []
        // As the stamps lay them: a dash every 7 widths, 4 of them painted; a dot every 1.5 widths.
        case .dashed: [width * 4, width * 3]
        case .dotted: [0.001, width * 1.5]
        }
    }

    private func chip(_ draft: EditorState.ShapeDraft, _ o: ShapeOptions) -> some View {
        let w = Int(abs(draft.to.x - draft.from.x).rounded()), h = Int(abs(draft.to.y - draft.from.y).rounded())
        let size = o.kind == .line || o.kind == .arrow
            ? "\(Int(hypot(draft.to.x - draft.from.x, draft.to.y - draft.from.y).rounded())) px"
            : "\(w) × \(h)"
        let snap: String? = switch draft.snap {
        case .none: nil
        case .angle(let degrees): "\(degrees)°"
        case .even:
            o.kind == .ellipse ? String(localized: "Circle", bundle: AppLanguage.bundle)
                : o.kind == .rectangle || o.kind == .roundedRectangle ? String(localized: "Square", bundle: AppLanguage.bundle)
                : String(localized: "Even", bundle: AppLanguage.bundle)
        }
        return Text(verbatim: [snap, size].compactMap { $0 }.joined(separator: " · "))
            .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
            .foregroundStyle(draft.snap == .none ? Theme.text : Theme.accentText)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Theme.panel, in: Capsule())
            .overlay(Capsule().strokeBorder(draft.snap == .none ? Theme.hairline : Theme.accent.opacity(0.6)))
            .fixedSize()
    }
}

extension EditorState {
    /// The colour shapes come out in: the bar's, unless the chosen brush always paints in its own.
    var shapeInk: SIMD4<Float> {
        if shapeOptions.useBrush, let c = brush.fixedColor { return SIMD4(c, 1) }
        return color
    }
}

/// A Pen path being drawn or edited: the line as it will come out, its points (square corners,
/// round curves; the picked one filled) and the picked point's handles. Touches go through to
/// the canvas, where the Pen works.
struct PenOverlay: View {
    @Bindable var state: EditorState

    var body: some View {
        if let e = state.penEditing {
            GeometryReader { geo in
                let toView = state.canvasTransform.canvasToView(canvas: state.renderer.canvasSize, viewSize: geo.size)
                let zoom = max(hypot(toView.a, toView.b), 0.0001)
                let o = state.shapeOptions
                let path = e.path
                let ink = Color(rgba: state.shapeInk).opacity(o.useBrush ? Double(state.brushOpacity) : 1)
                let width = CGFloat(o.size) * 2 * zoom
                let line = Path { p in
                    guard let first = path.nodes.first else { return }
                    p.move(to: first.point.applying(toView))
                    for i in 0..<path.segmentCount {
                        let s = path.segment(i)
                        p.addCurve(to: s.3.applying(toView), control1: s.1.applying(toView), control2: s.2.applying(toView))
                    }
                    if path.closed { p.closeSubpath() }
                }
                ZStack {
                    if path.closed && o.fill != .none { line.fill(ink) }
                    if !(path.closed && o.fill == .only) {
                        line.stroke(ink, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round,
                                                            dash: ShapeDraftOverlay.dash(o.outline, width: width)))
                    }
                    // A thin guide over it, so the path shows whatever its colour and thickness.
                    line.stroke(Theme.accent.opacity(0.9), lineWidth: 1)
                    if let s = e.selected, path.nodes.indices.contains(s) {
                        let n = path.nodes[s]
                        ForEach([n.handleIn, n.handleOut].compactMap { $0 }.indices, id: \.self) { k in
                            let h = [n.handleIn, n.handleOut].compactMap { $0 }[k].applying(toView)
                            Path { p in p.move(to: n.point.applying(toView)); p.addLine(to: h) }
                                .stroke(Theme.accent, lineWidth: 1.2)
                            Circle().fill(Theme.background).overlay(Circle().strokeBorder(Theme.accent, lineWidth: 2))
                                .frame(width: 12, height: 12).position(h)
                        }
                    }
                    ForEach(path.nodes.indices, id: \.self) { i in
                        let n = path.nodes[i]
                        let picked = i == e.selected
                        let shape = n.isCurve ? AnyShape(Circle()) : AnyShape(Rectangle())
                        shape.fill(picked ? Theme.accent : Theme.background)
                            .overlay(shape.stroke(picked ? Theme.onAccent : Theme.accent, lineWidth: 2))
                            .frame(width: 13, height: 13)
                            // The first point of an open path, bigger: tap it to close the path.
                            .padding(i == 0 && !path.closed && path.nodes.count >= 3 ? 3 : 0)
                            .overlay {
                                if i == 0 && !path.closed && path.nodes.count >= 3 {
                                    Circle().strokeBorder(Theme.accent.opacity(0.6), lineWidth: 1.5)
                                }
                            }
                            .position(n.point.applying(toView))
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }
}

/// Under the canvas while a Pen path is open: the picked point as a corner or a curve, close or
/// open the path, delete the point, cancel, and done.
struct PenBar: View {
    @Bindable var state: EditorState

    var body: some View {
        let e = state.penEditing
        let picked = e.flatMap { e in e.selected.flatMap { e.path.nodes.indices.contains($0) ? e.path.nodes[$0] : nil } }
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                option("Corner", icon: "square", on: picked.map { !$0.isCurve } ?? false) { state.penSetCurve(false) }
                option("Curve", icon: "circle", on: picked?.isCurve ?? false) { state.penSetCurve(true) }
            }
            .padding(3)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10))
            .disabled(picked == nil)
            .opacity(picked == nil ? 0.4 : 1)
            Divider().overlay(Theme.hairline).frame(height: 22)
            RailButton(icon: e?.path.closed == true ? "point.topleft.down.to.point.bottomright.curvepath" : "circle.dashed",
                       label: e?.path.closed == true ? "Open path" : "Close path", size: 34) { state.penToggleClosed() }
            RailButton(icon: "trash", label: "Delete point", size: 34) { state.penDeleteSelected() }
                .disabled(picked == nil)
                .opacity(picked == nil ? 0.4 : 1)
            RailButton(icon: "xmark", label: "Cancel path", size: 34) { state.cancelPen() }
            RailButton(icon: "checkmark", label: "Done", active: true, size: 34) { state.finishPen() }
        }
        .padding(4)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Theme.hairline))
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

/// The Smudge tool's popover: smudge, blur or motion, its strength, and its tip.
struct SmudgePanel: View {
    @Bindable var state: EditorState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Smudge").font(.headline)
            Picker("Mode", selection: $state.smudge.mode) {
                Text("Smear").tag(CanvasRenderer.SmudgeMode.smudge)
                Text("Blur").tag(CanvasRenderer.SmudgeMode.blur)
                Text("Motion").tag(CanvasRenderer.SmudgeMode.motion)
            }
            .pickerStyle(.segmented)
            Text(explanation).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("Strength").font(.subheadline)
                Spacer()
                Text("\(Int((state.smudge.strength * 100).rounded()))%")
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { Double(state.smudge.strength) }, set: { state.smudge.strength = Float($0) }),
                   in: 0.05...1)
            Picker("Tip", selection: $state.smudge.useBrushTip) {
                Text(Brush.smudgeTip.name).tag(false)
                Text(state.brush.name).tag(true)
            }
            .pickerStyle(.segmented)
            Text("Pressing harder works the paint more. The size is the bar's.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 320)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }

    private var explanation: String {
        switch state.smudge.mode {
        case .smudge: String(localized: "Drags the paint along with your finger.", bundle: AppLanguage.bundle)
        case .blur: String(localized: "Softens the paint where you go over it.", bundle: AppLanguage.bundle)
        case .motion: String(localized: "Blurs the paint along the way you move, like a trail.", bundle: AppLanguage.bundle)
        }
    }
}
