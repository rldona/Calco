import SwiftUI

/// "Canvas size": room added around the drawing, or cut from it, without scaling it. The width
/// and height are typed; the anchor says which side the drawing stays against; Fit crops to
/// what's drawn. Every clip, frame and layer at once.
struct CanvasSizeSheet: View {
    @Bindable var state: EditorState
    @Environment(\.dismiss) private var dismiss
    @State private var width = 0
    @State private var height = 0
    @State private var anchor = CanvasResize.Anchor.center
    /// Fit to the drawing: where its box starts on the canvas now. Typing a size or picking an
    /// anchor leaves it.
    @State private var fitOrigin: CGPoint?
    /// The frame at the playhead, for the preview.
    @State private var picture: CGImage?

    private var old: CanvasSize { state.project.canvas }
    private var new: CanvasSize { CanvasSize(width: width, height: height) }
    private var offset: (dx: Int, dy: Int) {
        if let fitOrigin { return (-Int(fitOrigin.x), -Int(fitOrigin.y)) }
        return CanvasResize.offset(from: old, to: new, anchor: anchor)
    }
    private var cuts: Bool {
        let o = offset
        return o.dx < 0 || o.dy < 0 || o.dx + old.width > width || o.dy + old.height > height
    }

    private var note: Text {
        cuts ? Text("Smaller than the drawing: what falls outside is cut. Undo brings it back.")
             : Text("Every clip, frame and layer. Strokes stay sharp and the pivot stays on the same pixel.")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Now \(old.width) × \(old.height) px")
                        .font(.subheadline).foregroundStyle(Theme.textFaint)
                    HStack {
                        PixelField(title: "Width", value: $width, range: EditorState.NewProjectConfig.sideRange)
                        PixelField(title: "Height", value: $height, range: EditorState.NewProjectConfig.sideRange)
                    }
                    HStack(spacing: 6) {
                        Chip(title: Text(verbatim: "+25 %"), on: false) { grow(1.25) }
                        Chip(title: Text(verbatim: "+50 %"), on: false) { grow(1.5) }
                        Chip(title: Text(verbatim: "× 2"), on: false) { grow(2) }
                        Chip(title: Text("Fit to drawing"), on: fitOrigin != nil, action: fit)
                    }
                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Where the drawing stays").font(.subheadline).foregroundStyle(Theme.textFaint)
                            AnchorPicker(anchor: Binding(get: { anchor }, set: { anchor = $0; fitOrigin = nil }))
                                .opacity(fitOrigin == nil ? 1 : 0.4)
                        }
                        Spacer(minLength: 0)
                        Preview(old: old, new: new, offset: offset, picture: picture)
                    }
                    note
                        .font(.caption)
                        .foregroundStyle(cuts ? Color.red.opacity(0.85) : Theme.textFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    state.resizeCanvas(to: new, dx: offset.dx, dy: offset.dy)
                    dismiss()
                } label: {
                    Text("Make it \(width) × \(height)")
                        .font(.headline)
                        .foregroundStyle(Theme.onAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(new == old && offset.dx == 0 && offset.dy == 0)
                .opacity(new == old && offset.dx == 0 && offset.dy == 0 ? 0.4 : 1)
                .padding(20)
                .background(Theme.panel)
            }
            .background(Theme.panel)
            .navigationTitle("Canvas size")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .onAppear {
            width = old.width; height = old.height
            if let f = state.currentFrame { picture = state.flattenedImage(clip: state.clip, frameID: f.id) }
        }
        .onChange(of: width) { _, w in if fitOrigin != nil, w != Int(fitSize.width) { fitOrigin = nil } }
        .onChange(of: height) { _, h in if fitOrigin != nil, h != Int(fitSize.height) { fitOrigin = nil } }
    }

    /// The size Fit picked, so typing anything else leaves Fit.
    @State private var fitSize = CGSize.zero

    private func grow(_ factor: Double) {
        fitOrigin = nil
        let range = EditorState.NewProjectConfig.sideRange
        width = min(max(Int((Double(old.width) * factor).rounded()), range.lowerBound), range.upperBound)
        height = min(max(Int((Double(old.height) * factor).rounded()), range.lowerBound), range.upperBound)
    }

    private func fit() {
        guard let b = state.drawingBounds() else { return }
        let range = EditorState.NewProjectConfig.sideRange
        fitSize = CGSize(width: max(CGFloat(range.lowerBound), b.width), height: max(CGFloat(range.lowerBound), b.height))
        fitOrigin = b.origin
        width = Int(fitSize.width)
        height = Int(fitSize.height)
    }
}

/// Nine squares: which side of the new canvas the drawing stays against.
private struct AnchorPicker: View {
    @Binding var anchor: CanvasResize.Anchor
    private static let arrows = ["arrow.up.left", "arrow.up", "arrow.up.right", "arrow.left", "circle.fill",
                                 "arrow.right", "arrow.down.left", "arrow.down", "arrow.down.right"]

    var body: some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            ForEach(0..<3, id: \.self) { row in
                GridRow {
                    ForEach(0..<3, id: \.self) { col in
                        let a = CanvasResize.Anchor(rawValue: row * 3 + col)!
                        Button { anchor = a } label: {
                            Image(systemName: a == anchor ? "photo" : Self.arrows[a.rawValue])
                                .font(.system(size: a == anchor ? 14 : 11, weight: .semibold))
                                .foregroundStyle(a == anchor ? Theme.onAccent : Theme.textDim)
                                .frame(width: 34, height: 34)
                                .background(a == anchor ? Theme.accent : Theme.background, in: RoundedRectangle(cornerRadius: 7))
                                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(a == anchor ? Theme.accent : Theme.hairline))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(a == anchor ? .isSelected : [])
                    }
                }
            }
        }
    }
}

/// The new canvas (dashed) with the current one placed in it, to scale.
private struct Preview: View {
    let old: CanvasSize
    let new: CanvasSize
    let offset: (dx: Int, dy: Int)
    let picture: CGImage?
    private let box: CGFloat = 150

    var body: some View {
        let minX = min(0, offset.dx), minY = min(0, offset.dy)
        let maxX = max(new.width, offset.dx + old.width), maxY = max(new.height, offset.dy + old.height)
        let k = box / CGFloat(max(maxX - minX, maxY - minY, 1))
        func r(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> CGRect {
            CGRect(x: CGFloat(x - minX) * k, y: CGFloat(y - minY) * k, width: CGFloat(w) * k, height: CGFloat(h) * k)
        }
        let canvas = r(0, 0, new.width, new.height), drawing = r(offset.dx, offset.dy, old.width, old.height)
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(Theme.background)
                .frame(width: canvas.width, height: canvas.height).offset(x: canvas.minX, y: canvas.minY)
            Group {
                if let picture {
                    Image(decorative: picture, scale: 1).resizable().interpolation(.none)
                        .background(Theme.text.opacity(0.85))
                } else {
                    Rectangle().fill(Theme.text.opacity(0.85))
                }
            }
            .frame(width: drawing.width, height: drawing.height).offset(x: drawing.minX, y: drawing.minY)
            Rectangle().strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(width: canvas.width, height: canvas.height).offset(x: canvas.minX, y: canvas.minY)
        }
        .frame(width: box, height: box, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}
