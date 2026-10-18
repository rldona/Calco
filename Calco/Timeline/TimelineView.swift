import SwiftUI
import UniformTypeIdentifiers

/// Bottom panel: transport and frame actions on top, then one track per clip.
/// The active clip shows its frames as thumbnails; the others as exposure bars on the same time
/// scale, so the rhythm of idle / run / jump can be compared at a glance. Tap a track to edit it.
/// Reorder frames by long-pressing a thumbnail and dragging it.
struct TimelineView: View {
    @ObservedObject var state: EditorState
    @State private var draggingFrameID: String?

    /// Width of one tick (one `hold` unit) on every track.
    private let tick: CGFloat = 44
    private let thumbHeight: CGFloat = 40
    private let barHeight: CGFloat = 14
    private let labelWidth: CGFloat = 56

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ScrollView(.vertical, showsIndicators: false) {
                HStack(alignment: .top, spacing: 8) {
                    labels
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(state.project.clips.enumerated()), id: \.element.id) { i, clip in
                                    if i == state.clipIndex { activeTrack } else { barTrack(clip, index: i) }
                                }
                            }
                            .padding(.trailing, 8)
                        }
                        .onChange(of: state.frameIndex) { _, _ in
                            if let f = state.currentFrame {
                                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(f.id, anchor: .center) }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 150)
            .fixedSize(horizontal: false, vertical: true)
        }
        .calcoPanel(padding: 10)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            Button { state.togglePlayback() } label: {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 28, height: 28)
            }
            .accessibilityLabel(state.isPlaying ? "Pause" : "Play")

            Text("\(state.frameIndex + 1) / \(state.frames.count)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.textDim)
                .frame(minWidth: 44, alignment: .leading)

            ClipMenu(state: state)

            Toggle(isOn: Binding(get: { state.clip.loop }, set: { _ in state.toggleLoop() })) {
                Image(systemName: "repeat")
            }
            .toggleStyle(.button)
            .help("Loop")

            HStack(spacing: 2) {
                CompactStepper(title: "fps",
                               value: Binding(get: { state.clipFPS }, set: { state.setClipFPS($0) }),
                               range: 1...60, inherited: state.clip.fps == nil)
                if state.clip.fps != nil {
                    Button { state.setClipFPS(nil) } label: { Image(systemName: "arrow.uturn.backward") }
                        .font(.caption)
                        .help("Use project fps")
                }
            }

            Toggle(isOn: $state.showPivot) { Image(systemName: "scope") }
                .toggleStyle(.button)
                .help("Pivot")
            if state.showPivot {
                Text(String(format: "%.2f · %.2f", state.clip.pivot.x, state.clip.pivot.y))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.textDim)
            }

            Spacer(minLength: 8)

            CompactStepper(title: "Hold", value: Binding(
                get: { state.currentFrame?.hold ?? 1 },
                set: { state.setHold($0) }), range: 1...24)

            Button { state.moveFrame(by: -1) } label: { Label("Move earlier", systemImage: "arrowshape.left") }
                .disabled(state.frameIndex == 0)
            Button { state.moveFrame(by: 1) } label: { Label("Move later", systemImage: "arrowshape.right") }
                .disabled(state.frameIndex >= state.frames.count - 1)

            Button { state.duplicateFrame() } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            Button(role: .destructive) { state.deleteFrame() } label: { Label("Delete", systemImage: "trash") }
                .disabled(state.frames.count <= 1)
            Button { state.addFrame() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 32, height: 28)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 8))
            }
            .accessibilityLabel("Add frame")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .foregroundStyle(Theme.textDim)
        .font(.body)
    }

    // MARK: Tracks

    private var labels: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(state.project.clips.enumerated()), id: \.element.id) { i, clip in
                let active = i == state.clipIndex
                Text(clip.name)
                    .font(.caption.weight(active ? .semibold : .regular))
                    .foregroundStyle(active ? Theme.accentText : Theme.textDim)
                    .lineLimit(1)
                    .frame(width: labelWidth, height: active ? thumbHeight : barHeight, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { state.selectClip(i) }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
    }

    private var activeTrack: some View {
        HStack(spacing: 2) {
            ForEach(Array(state.frames.enumerated()), id: \.element.id) { index, frame in
                FrameCell(image: state.thumbnails[frame.id],
                          index: index,
                          hold: frame.hold,
                          width: tick * CGFloat(frame.hold) - 2,
                          height: thumbHeight,
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
    }

    private func barTrack(_ clip: Clip, index: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(clip.frames) { frame in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Theme.raised)
                    .frame(width: tick * CGFloat(frame.hold) - 2, height: barHeight)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { state.selectClip(index) }
        .accessibilityElement()
        .accessibilityLabel("\(clip.name), \(clip.frames.count) frames")
        .accessibilityAddTraits(.isButton)
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

/// Clip picker plus new / rename / delete.
struct ClipMenu: View {
    @ObservedObject var state: EditorState
    @State private var addingClip = false
    @State private var renamingClip = false
    @State private var confirmingDelete = false
    @State private var clipName = ""

    var body: some View {
        Menu {
            ForEach(Array(state.project.clips.enumerated()), id: \.element.id) { index, clip in
                Button { state.selectClip(index) } label: {
                    if index == state.clipIndex { Label(clip.name, systemImage: "checkmark") } else { Text(clip.name) }
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
                Text(state.clip.name).font(.callout.weight(.semibold)).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
            .foregroundStyle(Theme.text)
        }
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

/// One frame on the active track: the thumbnail, then an exposure bar for the extra ticks it's held.
struct FrameCell: View {
    let image: CGImage?
    let index: Int
    let hold: Int
    let width: CGFloat
    let height: CGFloat
    let aspect: CGFloat
    let selected: Bool

    var body: some View {
        let thumbWidth = min(width, height * aspect)
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 5)
                .fill(selected ? Theme.accentWash : Theme.raised)
            Group {
                if let image {
                    Image(decorative: image, scale: 1).resizable().interpolation(.high)
                } else {
                    Theme.text
                }
            }
            .frame(width: thumbWidth, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .frame(width: width, height: height)
        .overlay(RoundedRectangle(cornerRadius: 5)
            .strokeBorder(selected ? Theme.accent : Theme.hairline, lineWidth: selected ? 2 : 0.5))
        .overlay(alignment: .topLeading) {
            Text("\(index + 1)")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(.black.opacity(0.6), in: Capsule())
                .foregroundStyle(.white)
                .padding(3)
        }
        .overlay(alignment: .trailing) {
            if hold > 1 {
                Text("×\(hold)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(selected ? Theme.accentText : Theme.textDim)
                    .padding(.trailing, 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Frame \(index + 1)\(hold > 1 ? ", held \(hold)" : "")")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
