import SwiftUI

/// The Shapes tool's popover: which shape, its outline, size, fill and brush.
struct ShapePanel: View {
    @Bindable var state: EditorState

    private var o: ShapeOptions { state.shapeOptions }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Shapes").font(.headline)

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

            caption("Outline")
            Picker("Outline", selection: $state.shapeOptions.outline) {
                Text("Solid").tag(ShapeOptions.Outline.solid)
                Text("Dashed").tag(ShapeOptions.Outline.dashed)
                Text("Dotted").tag(ShapeOptions.Outline.dotted)
            }
            .pickerStyle(.segmented)
            .disabled(o.fill == .only && o.canFill)

            HStack {
                caption("Thickness")
                Spacer()
                Text("\(Int(o.size)) px").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { Double(o.size) }, set: { state.shapeOptions.size = Float($0.rounded()) }),
                   in: Double(EditorState.sizeRange.lowerBound)...Double(min(EditorState.sizeRange.upperBound, 60)))
                .disabled(o.fill == .only && o.canFill)

            caption("Fill")
            Picker("Fill", selection: $state.shapeOptions.fill) {
                Text("No fill").tag(ShapeOptions.Fill.none)
                Text("Filled").tag(ShapeOptions.Fill.filled)
                Text("Fill only").tag(ShapeOptions.Fill.only)
            }
            .pickerStyle(.segmented)
            .disabled(!o.canFill)

            caption("Brush")
            Picker("Brush", selection: $state.shapeOptions.useBrush) {
                Text(Brush.inker.name).tag(false)
                Text(state.brush.name).tag(true)
            }
            .pickerStyle(.segmented)

            Text("Drag from corner to corner. Near even, it clicks into a square or a circle; lines click every 45°. In the bar's colour.")
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
                                                               dash: dash(o.outline, width: width)))
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

    private func dash(_ outline: ShapeOptions.Outline, width: CGFloat) -> [CGFloat] {
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
