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
    /// Show the draggable pivot handle over the canvas.
    @Published var showPivot = false
    @Published private(set) var thumbnails: [String: CGImage] = [:]

    /// Where the project lives on disk. Nil until the first save.
    @Published private(set) var documentURL: URL?
    /// True when there are changes since the last save or load.
    @Published private(set) var isDirty = false
    /// Last file error, shown by the UI and cleared by it.
    @Published var lastError: String?

    private(set) var renderer: CanvasRenderer
    private(set) var store: FrameStore
    private let screenFormat: MTLPixelFormat

    private var nextFrameNumber = 0
    private var playTask: Task<Void, Never>?

    init?(device: MTLDevice, screenFormat: MTLPixelFormat) {
        let project = Self.defaultProject()
        guard let renderer = CanvasRenderer(
            device: device,
            canvasSize: SIMD2<Int>(project.canvas.width, project.canvas.height),
            screenFormat: screenFormat) else { return nil }
        self.project = project
        self.renderer = renderer
        self.store = FrameStore(renderer: renderer)
        self.screenFormat = screenFormat
        try? install(project, images: [:])
        isDirty = false
    }

    static func defaultProject(name: String = "Untitled") -> Project {
        Project(name: name,
                canvas: CanvasSize(width: 512, height: 512),
                fps: 12,
                clips: [defaultClip()])
    }

    static func defaultClip() -> Clip {
        Clip(id: "idle", name: "Idle",
             layers: [Layer(id: "color", name: "Color"),
                      Layer(id: "line", name: "Line")],
             frames: [])
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

    // MARK: - Document

    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static func packageURL(named name: String) -> URL {
        documentsDirectory
            .appendingPathComponent(name)
            .appendingPathExtension(ProjectDocument.fileExtension)
    }

    /// Blank project; forgets the current file. The UI confirms unsaved changes first.
    func newProject() {
        stop()
        try? install(Self.defaultProject(), images: [:])
        documentURL = nil
        isDirty = false
    }

    /// Loads a `.calco` package (from Files, the document picker or `onOpenURL`).
    func open(_ url: URL) {
        stop()
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let loaded = try ProjectDocument.load(from: url)
            let images = ProjectDocument.loadLayerImages(from: url, project: loaded)
            try install(loaded, images: images)
            documentURL = url
            isDirty = false
        } catch {
            lastError = "Couldn't open \(url.lastPathComponent).\n\(error.localizedDescription)"
        }
    }

    /// Saves where the project was opened from, or to Documents/<name>.calco the first time.
    func save() {
        save(to: documentURL ?? Self.packageURL(named: project.name))
    }

    /// Renames the project and writes it as a new package in Documents.
    func saveAs(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        guard !trimmed.isEmpty else { return }
        project.name = trimmed
        save(to: Self.packageURL(named: trimmed))
    }

    /// Writes the current project if it already has a file. Used when the app goes to the background.
    func saveIfNeeded() {
        guard isDirty, let url = documentURL else { return }
        save(to: url)
    }

    /// Writes the package to `url` and makes it the current document.
    func save(to url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            try ProjectDocument.save(project, to: url) { key in
                store.image(clip: key.clip, frame: key.frame, layer: key.layer)
            }
            documentURL = url
            isDirty = false
        } catch {
            lastError = "Couldn't save \(url.lastPathComponent).\n\(error.localizedDescription)"
        }
    }

    /// Swaps in a project and its pixels, recreating the renderer if the canvas size changed.
    private func install(_ newProject: Project, images: [LayerKey: CGImage]) throws {
        let size = SIMD2<Int>(newProject.canvas.width, newProject.canvas.height)
        if size != renderer.canvasSize {
            guard let r = CanvasRenderer(device: renderer.device, canvasSize: size, screenFormat: screenFormat) else {
                throw ProjectDocument.Error.invalidCanvas(newProject.canvas)
            }
            renderer = r
        }
        store = FrameStore(renderer: renderer)
        thumbnails = [:]

        project = newProject
        if project.clips.isEmpty { project.clips = [Self.defaultClip()] }
        clipIndex = 0
        frameIndex = 0
        layerIndex = max(0, layers.count - 1)

        for (key, image) in images {
            store.load(image, clip: key.clip, frame: key.frame, layer: key.layer)
        }
        nextFrameNumber = (project.clips.flatMap(\.frames).compactMap { Int($0.id) }.max() ?? -1) + 1
        if frames.isEmpty { addFrame() }
        for f in frames { refreshThumbnail(for: f.id) }
    }

    // MARK: - Clips

    /// Folder-safe id derived from a name ("Run Fast!" → "run-fast"), made unique within the project.
    static func clipID(for name: String, existing: [String]) -> String {
        let base = name.lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined()
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        let root = base.isEmpty ? "clip" : base
        var id = root
        var n = 2
        while existing.contains(id) { id = "\(root)-\(n)"; n += 1 }
        return id
    }

    /// New clip with the current clip's layer setup and one blank frame; becomes the current clip.
    func addClip(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stop()
        var c = Clip(id: Self.clipID(for: trimmed, existing: project.clips.map(\.id)), name: trimmed)
        c.layers = clip.layers
        c.fps = clip.fps
        project.clips.append(c)
        selectClip(project.clips.count - 1)
        addFrame()
    }

    /// Keeps the id (it's the folder name on disk); only the display name changes.
    func renameClip(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != clip.name else { return }
        clip.name = trimmed
        isDirty = true
    }

    func deleteClip() {
        guard project.clips.count > 1 else { return }
        stop()
        let doomed = clip
        for f in doomed.frames {
            store.remove(clip: doomed.id, frame: f.id, layers: doomed.layers.map(\.id))
            thumbnails.removeValue(forKey: f.id)
        }
        project.clips.remove(at: clipIndex)
        selectClip(min(clipIndex, project.clips.count - 1))
        isDirty = true
    }

    func selectClip(_ index: Int) {
        guard project.clips.indices.contains(index) else { return }
        stop()
        clipIndex = index
        frameIndex = 0
        layerIndex = min(layerIndex, max(0, layers.count - 1))
        for f in frames where thumbnails[f.id] == nil { refreshThumbnail(for: f.id) }
    }

    /// Normalized, origin bottom-left. Clamped to the canvas.
    func setPivot(_ p: Pivot) {
        let clamped = Pivot(x: min(max(p.x, 0), 1), y: min(max(p.y, 0), 1))
        guard clamped != clip.pivot else { return }
        clip.pivot = clamped
        isDirty = true
    }

    func toggleLoop() {
        clip.loop.toggle()
        isDirty = true
    }

    /// Per-clip fps override; nil falls back to the project fps.
    func setClipFPS(_ fps: Int?) {
        let v = fps.map { min(max($0, 1), 60) }
        guard v != clip.fps else { return }
        clip.fps = v
        isDirty = true
    }

    // MARK: - Export

    /// Flattened, canvas-sized image of one frame (visible layers only). Nil when nothing was drawn.
    func flattenedImage(clip: Clip, frameID: String) -> CGImage? {
        let layers = frameLayers(of: clip, frameID, opacity: 1, tint: nil)
        guard !layers.isEmpty else { return nil }
        return renderer.flatten(layers)
    }

    /// Writes `<name>.png` + `<name>.json` (Aseprite array format) into Documents/Exports/<name>/.
    /// Returns the two files for sharing, or nil after setting `lastError`.
    func exportSpriteSheet() -> [URL]? {
        stop()
        let sheet = SpriteSheet.build(project: project) { clip, frame in
            flattenedImage(clip: clip, frameID: frame.id)
        }
        let folder = Self.documentsDirectory
            .appendingPathComponent("Exports", isDirectory: true)
            .appendingPathComponent(project.name, isDirectory: true)
        do {
            return try sheet.write(to: folder, baseName: project.name)
        } catch {
            lastError = "Couldn't export \(project.name).\n\(error.localizedDescription)"
            return nil
        }
    }

    /// Writes the current clip as Documents/Exports/<name>/<name>-<clip>.gif. Nil after setting `lastError`.
    func exportGIF() -> URL? {
        stop()
        let fps = Double(max(clipFPS, 1))
        let frames = clip.frames.map { f in
            GIFExport.Frame(image: flattenedImage(clip: clip, frameID: f.id),
                            durationSeconds: Double(f.hold) / fps)
        }
        let url = Self.documentsDirectory
            .appendingPathComponent("Exports", isDirectory: true)
            .appendingPathComponent(project.name, isDirectory: true)
            .appendingPathComponent("\(project.name)-\(clip.id).gif")
        do {
            try GIFExport.write(frames, canvas: project.canvas, loop: clip.loop, to: url)
            return url
        } catch {
            lastError = "Couldn't export \(url.lastPathComponent).\n\(error.localizedDescription)"
            return nil
        }
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
        isDirty = true
    }

    func duplicateFrame() {
        guard let src = currentFrame else { return }
        let f = Frame(id: newFrameID(), hold: src.hold)
        clip.frames.insert(f, at: frameIndex + 1)
        store.duplicate(clip: clip.id, from: src.id, to: f.id, layers: layers.map(\.id))
        frameIndex += 1
        isDirty = true
        refreshThumbnail(for: f.id)
    }

    func deleteFrame() {
        guard frames.count > 1, let f = currentFrame else { return }
        clip.frames.remove(at: frameIndex)
        store.remove(clip: clip.id, frame: f.id, layers: layers.map(\.id))
        thumbnails.removeValue(forKey: f.id)
        frameIndex = min(frameIndex, frames.count - 1)
        isDirty = true
    }

    func moveFrame(by offset: Int) {
        let to = frameIndex + offset
        guard frames.indices.contains(to) else { return }
        clip.frames.swapAt(frameIndex, to)
        frameIndex = to
        isDirty = true
    }

    func setHold(_ hold: Int) {
        guard currentFrame != nil else { return }
        clip.frames[frameIndex].hold = max(1, hold)
        isDirty = true
    }

    func clearCurrentLayer() {
        guard let f = currentFrame, let l = currentLayer else { return }
        store.clear(clip: clip.id, frame: f.id, layer: l.id)
        isDirty = true
        refreshThumbnail(for: f.id)
    }

    // MARK: - Layers

    func toggleLayerVisibility(_ index: Int) {
        guard layers.indices.contains(index) else { return }
        clip.layers[index].visible.toggle()
        isDirty = true
    }

    // MARK: - Playback

    func togglePlayback() {
        isPlaying ? stop() : play()
    }

    private func play() {
        guard frames.count > 1 else { return }
        if !clip.loop && frameIndex == frames.count - 1 { frameIndex = 0 }
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
            let next = self.frameIndex + 1
            if next < self.frames.count {
                self.frameIndex = next
            } else if self.clip.loop {
                self.frameIndex = 0
            } else {
                self.stop()
                return
            }
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
        frameLayers(of: clip, frameID, opacity: opacity, tint: tint)
    }

    private func frameLayers(of clip: Clip, _ frameID: String, opacity: Float, tint: SIMD3<Float>?) -> [CanvasRenderer.CompositeLayer] {
        clip.layers.compactMap { layer in
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
        isDirty = true
        if let f = currentFrame { refreshThumbnail(for: f.id) }
    }
}
