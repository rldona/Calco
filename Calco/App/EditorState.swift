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
    /// Radii in canvas pixels at full pressure, one per tool. Remembered across launches.
    @Published var brushSize: Float = 6 { didSet { saveToolSettings() } }
    @Published var eraserSize: Float = 18 { didSet { saveToolSettings() } }
    /// Brush colour, straight RGBA. Always opaque for now: overlapping stamps would build up any translucency.
    @Published var color = SIMD4<Float>(0, 0, 0, 1) { didSet { saveToolSettings() } }
    static let sizeRange: ClosedRange<Float> = 1...64
    @Published var onion = OnionSkin()
    @Published var isPlaying = false
    /// Show the draggable pivot handle over the canvas.
    @Published var showPivot = false
    /// Zen mode: only the canvas and a small floating bar. View state only.
    @Published var isZen = false
    /// Zoom / pan / rotation of the canvas on screen. View state only: not saved, not undoable.
    @Published var canvasTransform = CanvasTransform.identity
    @Published private(set) var thumbnails: [String: CGImage] = [:]

    /// Where the project lives on disk. Nil until the first save.
    @Published private(set) var documentURL: URL?
    /// True when there are changes since the last save or load.
    @Published private(set) var isDirty = false
    /// Last file error, shown by the UI and cleared by it.
    @Published var lastError: String?

    /// Actions that need a dialog or sheet owned by a view (the file menu). Menus and keyboard
    /// shortcuts set it; the view presents what's needed and clears it.
    enum Request: Equatable { case newProject, open, saveAs, exportSpriteSheet, exportGIF }
    @Published var request: Request?

    private(set) var renderer: CanvasRenderer
    private(set) var store: FrameStore
    private let screenFormat: MTLPixelFormat
    /// Where tool settings are remembered. Nil (tests, previews) keeps them in memory only.
    private let defaults: UserDefaults?

    private var nextFrameNumber = 0
    private var playTask: Task<Void, Never>?

    @Published private var undoStack: [Snapshot] = []
    @Published private var redoStack: [Snapshot] = []
    private var coalesceTag: String?
    /// Pixels from before the stroke in progress; enters the history only when the stroke ends.
    private var pendingStroke: Snapshot?
    static let historyLimit = 50

    init?(device: MTLDevice, screenFormat: MTLPixelFormat, defaults: UserDefaults? = nil) {
        let project = Self.defaultProject()
        guard let renderer = CanvasRenderer(
            device: device,
            canvasSize: SIMD2<Int>(project.canvas.width, project.canvas.height),
            screenFormat: screenFormat) else { return nil }
        self.project = project
        self.renderer = renderer
        self.store = FrameStore(renderer: renderer)
        self.screenFormat = screenFormat
        self.defaults = defaults
        try? install(project, images: [:])
        isDirty = false
        loadToolSettings()
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
        if frames.isEmpty { insertBlankFrame() }
        for f in frames { refreshThumbnail(for: f.id) }
        undoStack = []
        redoStack = []
        coalesceTag = nil
        pendingStroke = nil
        canvasTransform = .identity
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
        recordUndo()
        var c = Clip(id: Self.clipID(for: trimmed, existing: project.clips.map(\.id)), name: trimmed)
        c.layers = clip.layers
        c.fps = clip.fps
        project.clips.append(c)
        selectClip(project.clips.count - 1)
        insertBlankFrame()
    }

    /// Keeps the id (it's the folder name on disk); only the display name changes.
    func renameClip(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != clip.name else { return }
        recordUndo()
        clip.name = trimmed
        isDirty = true
    }

    func deleteClip() {
        guard project.clips.count > 1 else { return }
        stop()
        let doomed = clip
        recordUndo(textures: doomed.frames.flatMap { layerKeys(doomed, frame: $0.id) })
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
        recordUndo(coalescing: "pivot:\(clip.id)")
        clip.pivot = clamped
        isDirty = true
    }

    func toggleLoop() {
        recordUndo()
        clip.loop.toggle()
        isDirty = true
    }

    /// Per-clip fps override; nil falls back to the project fps.
    func setClipFPS(_ fps: Int?) {
        let v = fps.map { min(max($0, 1), 60) }
        guard v != clip.fps else { return }
        recordUndo(coalescing: "fps:\(clip.id)")
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
        recordUndo()
        insertBlankFrame()
    }

    private func insertBlankFrame() {
        let f = Frame(id: newFrameID(), hold: 1)
        let at = frames.isEmpty ? 0 : frameIndex + 1
        clip.frames.insert(f, at: at)
        frameIndex = at
        isDirty = true
    }

    func duplicateFrame() {
        guard let src = currentFrame else { return }
        let f = Frame(id: newFrameID(), hold: src.hold)
        recordUndo(textures: layerKeys(clip, frame: f.id))
        clip.frames.insert(f, at: frameIndex + 1)
        store.duplicate(clip: clip.id, from: src.id, to: f.id, layers: layers.map(\.id))
        frameIndex += 1
        isDirty = true
        refreshThumbnail(for: f.id)
    }

    func deleteFrame() {
        guard frames.count > 1, let f = currentFrame else { return }
        recordUndo(textures: layerKeys(clip, frame: f.id))
        clip.frames.remove(at: frameIndex)
        store.remove(clip: clip.id, frame: f.id, layers: layers.map(\.id))
        thumbnails.removeValue(forKey: f.id)
        frameIndex = min(frameIndex, frames.count - 1)
        isDirty = true
    }

    func moveFrame(by offset: Int) {
        let to = frameIndex + offset
        guard frames.indices.contains(to) else { return }
        recordUndo()
        clip.frames.swapAt(frameIndex, to)
        frameIndex = to
        isDirty = true
    }

    /// Moves frame `id` so it ends up at `index`. The selection stays on the frame that was selected.
    func moveFrame(id: String, to index: Int) {
        guard let from = frames.firstIndex(where: { $0.id == id }) else { return }
        let to = min(max(index, 0), frames.count - 1)
        guard from != to else { return }
        recordUndo(coalescing: "move:\(id)")
        let selectedID = currentFrame?.id
        clip.frames.insert(clip.frames.remove(at: from), at: to)
        if let selectedID, let i = frames.firstIndex(where: { $0.id == selectedID }) {
            frameIndex = i
        }
        isDirty = true
    }

    func setHold(_ hold: Int) {
        guard let f = currentFrame, max(1, hold) != f.hold else { return }
        recordUndo(coalescing: "hold:\(f.id)")
        clip.frames[frameIndex].hold = max(1, hold)
        isDirty = true
    }

    func clearCurrentLayer() {
        guard let f = currentFrame, let l = currentLayer, !l.locked else { return }
        recordUndo(textures: [LayerKey(clip: clip.id, frame: f.id, layer: l.id)], copyPixels: true)
        store.clear(clip: clip.id, frame: f.id, layer: l.id)
        isDirty = true
        refreshThumbnail(for: f.id)
    }

    // MARK: - Layers

    // Layers belong to the clip: every frame of the clip has the same stack, ordered bottom to top.
    // `id` is the PNG name inside each frame folder, so renaming only changes `name`.

    /// New empty layer just above the current one; becomes the current layer.
    func addLayer(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recordUndo()
        let layer = Layer(id: Self.clipID(for: trimmed, existing: layers.map(\.id)), name: trimmed)
        let at = layers.isEmpty ? 0 : layerIndex + 1
        clip.layers.insert(layer, at: at)
        layerIndex = at
        isDirty = true
    }

    /// Removes the layer and its pixels in every frame of the clip. The last layer can't go.
    func deleteLayer(_ index: Int) {
        guard layers.count > 1, layers.indices.contains(index) else { return }
        let doomed = layers[index]
        let keys = frames.map { LayerKey(clip: clip.id, frame: $0.id, layer: doomed.id) }
        recordUndo(textures: keys)
        for k in keys { store.set(nil, for: k) }
        clip.layers.remove(at: index)
        if layerIndex > index || layerIndex >= layers.count { layerIndex = max(0, layerIndex - 1) }
        isDirty = true
        refreshClipThumbnails()
    }

    func renameLayer(_ index: Int, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard layers.indices.contains(index), !trimmed.isEmpty, trimmed != layers[index].name else { return }
        recordUndo()
        clip.layers[index].name = trimmed
        isDirty = true
    }

    /// Moves a layer in the stack (indices bottom to top). The current layer stays current.
    func moveLayer(from: Int, to: Int) {
        guard layers.indices.contains(from) else { return }
        let to = min(max(to, 0), layers.count - 1)
        guard from != to else { return }
        recordUndo()
        let currentID = currentLayer?.id
        clip.layers.insert(clip.layers.remove(at: from), at: to)
        if let currentID, let i = layers.firstIndex(where: { $0.id == currentID }) { layerIndex = i }
        isDirty = true
        refreshClipThumbnails()
    }

    func toggleLayerVisibility(_ index: Int) {
        guard layers.indices.contains(index) else { return }
        recordUndo()
        clip.layers[index].visible.toggle()
        isDirty = true
        refreshClipThumbnails()
    }

    func toggleLayerLock(_ index: Int) {
        guard layers.indices.contains(index) else { return }
        recordUndo()
        clip.layers[index].locked.toggle()
        isDirty = true
    }

    /// Slider-friendly: a drag is one undo step. Call `layerOpacityEditingEnded` when it lets go.
    func setLayerOpacity(_ index: Int, _ opacity: Double) {
        guard layers.indices.contains(index) else { return }
        let v = min(max(opacity, 0), 1)
        guard v != layers[index].opacity else { return }
        recordUndo(coalescing: "opacity:\(clip.id):\(layers[index].id)")
        clip.layers[index].opacity = v
        isDirty = true
    }

    func layerOpacityEditingEnded() {
        endCoalescing()
        refreshClipThumbnails()
    }

    private func refreshClipThumbnails() {
        for f in frames { refreshThumbnail(for: f.id) }
    }

    // MARK: - Stepping (keyboard)

    func stepFrame(_ offset: Int) {
        guard !frames.isEmpty else { return }
        frameIndex = min(max(frameIndex + offset, 0), frames.count - 1)
    }

    /// `offset` is in stack order: +1 is the layer above.
    func stepLayer(_ offset: Int) {
        guard !layers.isEmpty else { return }
        layerIndex = min(max(layerIndex + offset, 0), layers.count - 1)
    }

    func stepHold(_ offset: Int) {
        guard let f = currentFrame else { return }
        setHold(f.hold + offset)
    }

    /// "Layer 3", "Layer 4"… for a layer made without a name dialog.
    func addLayerWithDefaultName() {
        var n = layers.count + 1
        while layers.contains(where: { $0.name == "Layer \(n)" }) { n += 1 }
        addLayer(name: "Layer \(n)")
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

    /// Keeps the layer's pixels aside and returns the texture to paint into, or nil if painting isn't allowed.
    /// The stroke becomes an undo step in `strokeEnded`; `cancelStroke` throws it away.
    func beginStroke() -> MTLTexture? {
        guard let f = currentFrame, let l = currentLayer, !l.locked else { return nil }
        let key = LayerKey(clip: clip.id, frame: f.id, layer: l.id)
        var saved: [LayerKey: MTLTexture?] = [:]
        saved.updateValue(store.copy(of: key), forKey: key)
        pendingStroke = snapshot(saved)
        return paintTarget
    }

    func strokeEnded() {
        if let s = pendingStroke {
            coalesceTag = nil
            push(s)
            pendingStroke = nil
        }
        isDirty = true
        if let f = currentFrame { refreshThumbnail(for: f.id) }
    }

    /// A gesture took over (two-finger tap, pinch): put the pixels back as if the stroke never happened.
    func cancelStroke() {
        guard let s = pendingStroke else { return }
        pendingStroke = nil
        for (k, t) in s.textures { store.set(t, for: k) }
        if let f = currentFrame { refreshThumbnail(for: f.id) }
    }

    // MARK: - Tool settings

    /// Size of whichever tool is active.
    var toolSize: Float {
        get { tool == .eraser ? eraserSize : brushSize }
        set {
            let v = min(max(newValue.rounded(), Self.sizeRange.lowerBound), Self.sizeRange.upperBound)
            if tool == .eraser { eraserSize = v } else { brushSize = v }
        }
    }

    /// `[` / `]`: small steps for fine brushes, bigger ones as the brush grows.
    func stepToolSize(_ direction: Int) {
        let step: Float = toolSize < 10 ? 1 : toolSize < 30 ? 2 : 4
        toolSize += Float(direction) * step
    }

    private enum ToolKey {
        static let brushSize = "tool.brushSize"
        static let eraserSize = "tool.eraserSize"
        static let color = "tool.color"
    }

    private var loadingToolSettings = false

    /// Missing or out-of-range values keep the defaults.
    private func loadToolSettings() {
        guard let defaults else { return }
        loadingToolSettings = true
        defer { loadingToolSettings = false }
        let range = Self.sizeRange
        if let v = defaults.object(forKey: ToolKey.brushSize) as? Float, range.contains(v) { brushSize = v }
        if let v = defaults.object(forKey: ToolKey.eraserSize) as? Float, range.contains(v) { eraserSize = v }
        if let c = defaults.array(forKey: ToolKey.color) as? [Float], c.count == 3,
           c.allSatisfy({ (0...1).contains($0) }) {
            color = SIMD4<Float>(c[0], c[1], c[2], 1)
        }
    }

    private func saveToolSettings() {
        guard let defaults, !loadingToolSettings else { return }
        defaults.set(brushSize, forKey: ToolKey.brushSize)
        defaults.set(eraserSize, forKey: ToolKey.eraserSize)
        defaults.set([color.x, color.y, color.z], forKey: ToolKey.color)
    }

    func setColor(_ c: SIMD4<Float>) {
        color = SIMD4<Float>(min(max(c.x, 0), 1), min(max(c.y, 0), 1), min(max(c.z, 0), 1), 1)
        tool = .brush
    }

    // MARK: - Undo / redo

    /// The model, the selection, and the layer textures one edit touched, as they were before (or after) it.
    /// A nil texture means the layer had none (blank). Textures are swapped, not copied, on undo/redo.
    private struct Snapshot {
        var project: Project
        var clipIndex: Int
        var frameIndex: Int
        var layerIndex: Int
        var textures: [LayerKey: MTLTexture?]
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    private func layerKeys(_ clip: Clip, frame: String) -> [LayerKey] {
        clip.layers.map { LayerKey(clip: clip.id, frame: frame, layer: $0.id) }
    }

    private func snapshot(_ textures: [LayerKey: MTLTexture?]) -> Snapshot {
        Snapshot(project: project, clipIndex: clipIndex, frameIndex: frameIndex,
                 layerIndex: layerIndex, textures: textures)
    }

    /// Call right before an edit. `textures` are the layers the edit creates, removes or paints into;
    /// `copyPixels` when it changes them in place (strokes, clear). Edits sharing a `coalescing` tag
    /// in a row (a drag, a stepper) become one undo step.
    private func recordUndo(textures keys: [LayerKey] = [], copyPixels: Bool = false, coalescing tag: String? = nil) {
        if let tag, tag == coalesceTag, !undoStack.isEmpty { return }
        coalesceTag = tag
        var saved: [LayerKey: MTLTexture?] = [:]
        for k in keys { saved.updateValue(copyPixels ? store.copy(of: k) : store.raw(k), forKey: k) }
        push(snapshot(saved))
    }

    private func push(_ s: Snapshot) {
        undoStack.append(s)
        if undoStack.count > Self.historyLimit { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    /// Ends a coalesced run early, so the next drag of the same thing is its own undo step.
    func endCoalescing() {
        coalesceTag = nil
    }

    func undo() {
        cancelStroke()
        guard let s = undoStack.popLast() else { return }
        redoStack.append(snapshot(currentTextures(s)))
        apply(s)
    }

    func redo() {
        cancelStroke()
        guard let s = redoStack.popLast() else { return }
        undoStack.append(snapshot(currentTextures(s)))
        apply(s)
    }

    private func currentTextures(_ s: Snapshot) -> [LayerKey: MTLTexture?] {
        var out: [LayerKey: MTLTexture?] = [:]
        for k in s.textures.keys { out.updateValue(store.raw(k), forKey: k) }
        return out
    }

    private func apply(_ s: Snapshot) {
        stop()
        coalesceTag = nil
        project = s.project
        clipIndex = min(s.clipIndex, project.clips.count - 1)
        frameIndex = min(s.frameIndex, max(0, frames.count - 1))
        layerIndex = min(s.layerIndex, max(0, layers.count - 1))
        for (k, t) in s.textures { store.set(t, for: k) }
        isDirty = true
        for f in frames { refreshThumbnail(for: f.id) }
    }
}
