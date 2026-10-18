import SwiftUI
import UniformTypeIdentifiers

/// Bottom strip: play, frame thumbnails, and per-frame actions.
/// Reorder by long-pressing a thumbnail and dragging it, or step by step with the arrows.
struct TimelineView: View {
    @ObservedObject var state: EditorState
    @State private var draggingFrameID: String?

    var body: some View {
        VStack(spacing: 8) {
            ClipBar(state: state)

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
                    Text("\(state.currentFrame?.hold ?? 1)")
                        .font(.system(.caption, design: .monospaced))
                        .frame(minWidth: 20)
                    Stepper("Hold", value: Binding(
                        get: { state.currentFrame?.hold ?? 1 },
                        set: { state.setHold($0) }),
                            in: 1...24)
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
                            .onDrag {
                                draggingFrameID = frame.id
                                return NSItemProvider(object: frame.id as NSString)
                            }
                            .onDrop(of: [.text], delegate: FrameDropDelegate(
                                targetID: frame.id, state: state, dragging: $draggingFrameID))
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

/// Live reorder: the dragged frame takes the slot of whichever thumbnail it is over.
private struct FrameDropDelegate: DropDelegate {
    let targetID: String
    let state: EditorState
    @Binding var dragging: String?

    func dropEntered(info: DropInfo) {
        guard let id = dragging, id != targetID,
              let to = state.frames.firstIndex(where: { $0.id == targetID }) else { return }
        withAnimation(.easeOut(duration: 0.15)) { state.moveFrame(id: id, to: to) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        state.endCoalescing()
        return true
    }
}

/// Clip picker plus per-clip settings: rename/delete, loop, fps override, pivot handle.
struct ClipBar: View {
    @ObservedObject var state: EditorState
    @State private var addingClip = false
    @State private var renamingClip = false
    @State private var confirmingDelete = false
    @State private var clipName = ""

    var body: some View {
        HStack(spacing: 14) {
            Menu {
                ForEach(Array(state.project.clips.enumerated()), id: \.element.id) { index, clip in
                    Button {
                        state.selectClip(index)
                    } label: {
                        if index == state.clipIndex {
                            Label(clip.name, systemImage: "checkmark")
                        } else {
                            Text(clip.name)
                        }
                    }
                }
                Divider()
                Button { clipName = ""; addingClip = true } label: { Label("New clip…", systemImage: "plus") }
                Button { clipName = state.clip.name; renamingClip = true } label: { Label("Rename…", systemImage: "pencil") }
                Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete clip", systemImage: "trash") }
                    .disabled(state.project.clips.count <= 1)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "film.stack")
                    Text(state.clip.name).font(.callout.weight(.semibold))
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
            }

            Text("\(state.clip.frames.count) frames")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            Divider().frame(height: 18)

            Toggle(isOn: Binding(get: { state.clip.loop }, set: { _ in state.toggleLoop() })) {
                Image(systemName: "repeat")
            }
            .toggleStyle(.button)
            .help("Loop")

            HStack(spacing: 4) {
                Text("fps").font(.caption).foregroundStyle(.secondary)
                Text("\(state.clipFPS)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(state.clip.fps == nil ? .secondary : .primary)
                    .frame(minWidth: 20)
                Stepper("fps", value: Binding(get: { state.clipFPS }, set: { state.setClipFPS($0) }), in: 1...60)
                    .labelsHidden()
                if state.clip.fps != nil {
                    Button { state.setClipFPS(nil) } label: { Image(systemName: "arrow.uturn.backward") }
                        .font(.caption)
                        .help("Use project fps")
                }
            }

            Divider().frame(height: 18)

            Toggle(isOn: $state.showPivot) {
                Image(systemName: "scope")
            }
            .toggleStyle(.button)
            .help("Pivot")
            Text(String(format: "%.2f · %.2f", state.clip.pivot.x, state.clip.pivot.y))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            Spacer()
        }
        .buttonStyle(.borderless)
        .font(.body)
        .alert("New clip", isPresented: $addingClip) {
            TextField("Name (idle, run, jump…)", text: $clipName)
            Button("Add") { state.addClip(name: clipName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Starts with one blank frame and the same layers as \(state.clip.name).")
        }
        .alert("Rename clip", isPresented: $renamingClip) {
            TextField("Name", text: $clipName)
            Button("Rename") { state.renameClip(clipName) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete \(state.clip.name)?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) { state.deleteClip() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All \(state.clip.frames.count) frames of this clip will be removed.")
        }
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
