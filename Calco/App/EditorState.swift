import SwiftUI
import Metal

struct OnionSkin: Equatable {
    var enabled = true
    var before = 2
    var after = 1
    var opacity: Float = 0.35
    static let beforeTint = SIMD3<Float>(0.85, 0.25, 0.25)
    static let afterTint  = SIMD3<Float>(0.25, 0.55, 0.85)
}

/// Everything the editor UI and the canvas view share.
/// Owns the project model, the pixel store, and the current selection.
@MainActor
final class EditorState: ObservableObject {

    @Published var project: Project
    @Published var clipIndex = 0
    @Published var frameIndex = 0
    @Published var layerIndex = 0
    @Published var tool: CanvasRenderer.Tool = .brush
    @Published var onion = OnionSkin()
    @Published var isPlaying = false
    @Published private(set) var thumbnails: [String: CGImage] = [:]

    let renderer: CanvasRenderer
    let store: FrameStore

    private var nextFrameNumber = 0
    private var playTask: Task<Void, Never>?

    init?(device: MTLDevice, screenFormat: MTLPixelFormat) {
        let project = Project(
            name: "Untitled",
            canvas: CanvasSize(width: 512, height: 512),
            fps: 12,
            clips: [Clip(id: "idle", name: "Idle",
                         layers: [Layer(id: "color", name: "Color"),
                                  Layer(id: "line", name: "Line")],
                         frames: [])]
        )
        guard let renderer = CanvasRenderer(
            device: device,
            canvasSize: SIMD2<Int>(project.canvas.width, project.canvas.height),
            screenFormat: screenFormat) else { return nil }
        self.project = project
        self.renderer = renderer
        self.store = FrameStore(renderer: renderer)
        self.layerIndex = 1 // start on Line
        addFrame()
    }

    // MARK: - Accessors

    var clip: Clip {
        get { project.clips[clipIndex] }
        set { project.clips[clipIndex] = newValue }
    }
    var frames: [Frame] { clip.frames }
    var layers: [Layer] { clip.layers }
    var currentFrame: Frame? { frames.indices.contains(frameIndex) ? frames[frameIndex] : nil }
    var currentLayer: Layer? { layers.indices.contains(layerIndex) ? layers[layerIndex] : nil }
    var clipFPS: Int { clip.fps ?? project.fps }

    /// Texture the Pencil should paint into right now.
    var paintTarget: MTLTexture? {
        guard let f = currentFrame, let l = currentLayer, !l.locked else { return nil }
        return store.texture(clip: clip.id, frame: f.id, layer: l.id)
    }

    // MARK: - Frames

    private func newFrameID() -> String {
        defer { nextFrameNumber += 1 }
        return String(format: "%03d", nextFrameNumber)
    }

    func addFrame() {
        let f = Frame(id: newFrameID(), hold: 1)
        let at = frames.isEmpty ? 0 : frameIndex + 1
        clip.frames.insert(f, at: at)
        frameIndex = at
    }

    func duplicateFrame() {
        guard let src = currentFrame else { return }
        let f = Frame(id: newFrameID(), hold: src.hold)
        clip.frames.insert(f, at: frameIndex + 1)
        store.duplicate(clip: clip.id, from: src.id, to: f.id, layers: layers.map(\.id))
        frameIndex += 1
        refreshThumbnail(for: f.id)
    }

    func deleteFrame() {
        guard frames.count > 1, let f = currentFrame else { return }
        clip.frames.remove(at: frameIndex)
        store.remove(clip: clip.id, frame: f.id, layers: layers.map(\.id))
        thumbnails.removeValue(forKey: f.id)
        frameIndex = min(frameIndex, frames.count - 1)
    }

    func moveFrame(by offset: Int) {
        let to = frameIndex + offset
        guard frames.indices.contains(to) else { return }
        clip.frames.swapAt(frameIndex, to)
        frameIndex = to
    }

    func setHold(_ hold: Int) {
        guard currentFrame != nil else { return }
        clip.frames[frameIndex].hold = max(1, hold)
    }

    func clearCurrentLayer() {
        guard let f = currentFrame, let l = currentLayer else { return }
        store.clear(clip: clip.id, frame: f.id, layer: l.id)
        refreshThumbnail(for: f.id)
    }

    // MARK: - Layers

    func toggleLayerVisibility(_ index: Int) {
        guard layers.indices.contains(index) else { return }
        clip.layers[index].visible.toggle()
    }

    // MARK: - Playback

    func togglePlayback() {
        isPlaying ? stop() : play()
    }

    private func play() {
        guard frames.count > 1 else { return }
        isPlaying = true
        scheduleNextTick()
    }

    private func stop() {
        isPlaying = false
        playTask?.cancel()
        playTask = nil
    }

    private func scheduleNextTick() {
        guard isPlaying, let f = currentFrame else { return }
        let nanos = UInt64(Double(f.hold) / Double(clipFPS) * 1_000_000_000)
        playTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            guard let self, self.isPlaying, !Task.isCancelled else { return }
            self.frameIndex = (self.frameIndex + 1) % self.frames.count
            self.scheduleNextTick()
        }
    }

    // MARK: - Compositing

    /// What the canvas should show right now, bottom to top.
    func visibleLayers() -> [CanvasRenderer.CompositeLayer] {
        var out: [CanvasRenderer.CompositeLayer] = []
        guard !frames.isEmpty else { return out }

        if onion.enabled && !isPlaying {
            for i in stride(from: onion.before, through: 1, by: -1) {
                let idx = frameIndex - i
                guard frames.indices.contains(idx) else { continue }
                let fade = 1 - Float(i - 1) / Float(max(onion.before, 1)) * 0.6
                out += frameLayers(frames[idx].id, opacity: onion.opacity * fade, tint: OnionSkin.beforeTint)
            }
            for i in stride(from: onion.after, through: 1, by: -1) {
                let idx = frameIndex + i
                guard frames.indices.contains(idx) else { continue }
                let fade = 1 - Float(i - 1) / Float(max(onion.after, 1)) * 0.6
                out += frameLayers(frames[idx].id, opacity: onion.opacity * fade, tint: OnionSkin.afterTint)
            }
        }
        if let f = currentFrame {
            out += frameLayers(f.id, opacity: 1, tint: nil)
        }
        return out
    }

    private func frameLayers(_ frameID: String, opacity: Float, tint: SIMD3<Float>?) -> [CanvasRenderer.CompositeLayer] {
        layers.compactMap { layer in
            guard layer.visible,
                  let t = store.existingTexture(clip: clip.id, frame: frameID, layer: layer.id) else { return nil }
            return CanvasRenderer.CompositeLayer(
                texture: t,
                opacity: Float(layer.opacity) * opacity,
                tint: tint ?? .zero,
                tintAmount: tint == nil ? 0 : 1)
        }
    }

    // MARK: - Thumbnails

    func refreshThumbnail(for frameID: String) {
        let layersToDraw = frameLayers(frameID, opacity: 1, tint: nil)
        renderer.thumbnail(layersToDraw) { [weak self] image in
            DispatchQueue.main.async {
                guard let self, let image else { return }
                self.thumbnails[frameID] = image
            }
        }
    }

    func strokeEnded() {
        if let f = currentFrame { refreshThumbnail(for: f.id) }
    }
}
