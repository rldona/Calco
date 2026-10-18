import SwiftUI

/// Bottom strip: play, frame thumbnails, and per-frame actions.
/// Reordering is by arrows for now; drag comes once the strip is stable.
struct TimelineView: View {
    @ObservedObject var state: EditorState

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                Button {
                    state.togglePlayback()
                } label: {
                    Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 28)
                }
                .keyboardShortcut(.space, modifiers: [])

                Text("\(state.frameIndex + 1) / \(state.frames.count)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 56)

                Divider().frame(height: 18)

                Button { state.moveFrame(by: -1) } label: { Image(systemName: "arrow.left") }
                    .disabled(state.frameIndex == 0)
                Button { state.moveFrame(by: 1) } label: { Image(systemName: "arrow.right") }
                    .disabled(state.frameIndex >= state.frames.count - 1)

                Divider().frame(height: 18)

                HStack(spacing: 4) {
                    Text("Hold")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Stepper(value: Binding(
                        get: { state.currentFrame?.hold ?? 1 },
                        set: { state.setHold($0) }),
                            in: 1...24) {
                        Text("\(state.currentFrame?.hold ?? 1)")
                            .font(.system(.caption, design: .monospaced))
                            .frame(minWidth: 20)
                    }
                    .labelsHidden()
                }

                Spacer()

                Button { state.duplicateFrame() } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                Button(role: .destructive) { state.deleteFrame() } label: { Label("Delete", systemImage: "trash") }
                    .disabled(state.frames.count <= 1)
                Button { state.addFrame() } label: { Label("Add frame", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
            }
            .labelStyle(.iconOnly)
            .font(.body)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(state.frames.enumerated()), id: \.element.id) { index, frame in
                            FrameThumbnail(
                                image: state.thumbnails[frame.id],
                                index: index,
                                hold: frame.hold,
                                aspect: CGFloat(state.project.canvas.width) / CGFloat(state.project.canvas.height),
                                selected: index == state.frameIndex)
                            .id(frame.id)
                            .onTapGesture { state.frameIndex = index }
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .onChange(of: state.frameIndex) { _, _ in
                    if let f = state.currentFrame {
                        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(f.id, anchor: .center) }
                    }
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct FrameThumbnail: View {
    let image: CGImage?
    let index: Int
    let hold: Int
    let aspect: CGFloat
    let selected: Bool

    private let height: CGFloat = 64

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                } else {
                    Color.white
                }
            }
            .frame(width: height * aspect, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(selected ? Color.accentColor : Color.white.opacity(0.15),
                                  lineWidth: selected ? 2.5 : 1)
            )

            if hold > 1 {
                Text("×\(hold)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(.black.opacity(0.65), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(4)
            }
        }
        .overlay(alignment: .topLeading) {
            Text("\(index + 1)")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(.black.opacity(0.65), in: Capsule())
                .foregroundStyle(.white)
                .padding(4)
        }
    }
}
