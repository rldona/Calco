import SwiftUI
import Metal

struct OnionSkin: Equatable {
    var enabled = true
    var before = 2
    var after = 1
    var opacity: Float = 0.35
    /// Ghost only the layer being drawn on, not the whole frame.
    var currentLayerOnly = false
    var beforeTint = SIMD3<Float>(0.85, 0.25, 0.25)
    var afterTint  = SIMD3<Float>(0.25, 0.55, 0.85)
}

/// Everything the editor UI and the canvas view share.
/// Owns the project model, the pixel store, and the current selection.
@MainActor
final class EditorState: ObservableObject {

    @Published var project: Project
    @Published var clipIndex = 0
    @Published var frameIndex = 0 { didSet { if frameIndex != oldValue { commitSelection() } } }
    @Published var layerIndex = 0 { didSet { if layerIndex != oldValue { commitSelection() } } }
    @Published var tool: CanvasRenderer.Tool = .brush {
        didSet {
            if tool == .eyedropper && oldValue != .eyedropper { toolBeforeEyedropper = oldValue }
            if tool != .lasso { commitSelection() }
        }
    }
    /// The eyedropper is one-shot: after a pick you're back on this.
    private var toolBeforeEyedropper: CanvasRenderer.Tool = .brush
    /// Radii in canvas pixels at full pressure, one per tool. Remembered across launches.
    @Published var brushSize: Float = 6 { didSet { saveToolSettings() } }
    @Published var eraserSize: Float = 18 { didSet { saveToolSettings() } }
    /// Brush stabiliser 0–1 and whether the Pencil's pressure changes the size. Remembered.
    @Published var smoothing: Float = 0.3 { didSet { saveToolSettings() } }
    @Published var usePressure = true { didSet { saveToolSettings() } }
    /// How big a break in a line the fill bucket bridges. Remembered across launches.
    @Published var fillGaps: FillGaps = .small { didSet { saveToolSettings() } }
    /// Brush colour, straight RGBA. Always opaque for now: overlapping stamps would build up any translucency.
    @Published var color = SIMD4<Float>(0, 0, 0, 1) { didSet { saveToolSettings() } }
    static let sizeRange: ClosedRange<Float> = 1...64
    @Published var onion = OnionSkin()
    @Published var isPlaying = false
    /// Show the draggable pivot handle over the canvas.
    @Published var showPivot = false
    /// The project gallery is showing instead of the editor. The app starts there.
    @Published var isInGallery = true
    /// The lasso being drawn, in canvas pixels. Empty when not drawing one.
    @Published var lassoPoints: [CGPoint] = []
    /// What the lasso lifted, while it's being transformed. Nil when nothing is selected.
    @Published private(set) var selection: FloatingSelection?
    /// The layer's pixels from before the lift: one undo step covers lift, transform and drop.
    private var selectionBefore: MTLTexture?
    /// The selection drawn at its current transform, composited above its layer.
    private var selectionPreview: MTLTexture?
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

    nonisolated static func defaultProject(name: String = "Untitled") -> Project {
        Project(name: name,
                canvas: CanvasSize(width: 512, height: 512),
                fps: 12,
                clips: [defaultClip()])
    }

    nonisolated static func defaultClip() -> Clip {
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

    /// The drawing `layer` shows at frame `index`: its own, or the one it holds from earlier.
    func drawingKey(layer: String, at index: Int) -> LayerKey? {
        clip.sourceFrameID(layer: layer, at: index).map { LayerKey(clip: clip.id, frame: $0, layer: layer) }
    }

    /// What painting, fill, clear and the lasso act on: the current layer's drawing at the playhead.
    /// On a held cell that's the drawing being held, so editing it changes every frame showing it.
    var currentDrawingKey: LayerKey? {
        currentLayer.flatMap { drawingKey(layer: $0.id, at: frameIndex) }
    }

    /// Whether the current layer holds the previous drawing at the playhead.
    var currentCellIsHeld: Bool {
        currentLayer.map { clip.isHeld(layer: $0.id, at: frameIndex) } ?? false
    }

    /// Texture the Pencil should paint into right now.
    var paintTarget: MTLTexture? {
        guard let k = currentDrawingKey, currentLayer?.locked == false else { return nil }
        return store.texture(clip: k.clip, frame: k.frame, layer: k.layer)
    }

    // MARK: - Document

    nonisolated static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static func packageURL(named name: String) -> URL {
        documentsDirectory
            .appendingPathComponent(name)
            .appendingPathExtension(ProjectDocument.fileExtension)
    }

    /// What the "New project" sheet asks for. Sprite-sized presets rather than video "camera" sizes.
    struct NewProjectConfig: Equatable {
        var name = "Untitled character"
        var width = 256
        var height = 256
        var fps = 12
        var clips = ["Idle", "Run"]

        static let sizes = [64, 128, 256, 512, 1024]
        static let fpsChoices = [8, 12, 24]
        static let suggestedClips = ["Idle", "Run", "Jump", "Attack", "Hurt"]
        static let sideRange = 16...2048
    }

    /// Builds the project, saves it straight into `directory` (so it's in the gallery from the
    /// start) and opens it in the editor. Each clip gets one blank frame and the usual two layers.
    func createProject(_ config: NewProjectConfig, in directory: URL = EditorState.documentsDirectory) {
        stop()
        let library = ProjectLibrary(directory: directory)
        let name = library.uniqueName(config.name)
        let side = NewProjectConfig.sideRange
        var clips: [Clip] = []
        for (i, clipName) in config.clips.map({ ProjectLibrary.cleanName($0) }).filter({ !$0.isEmpty }).enumerated() {
            var c = Self.defaultClip()
            c.id = Self.clipID(for: clipName, existing: clips.map(\.id))
            c.name = clipName
            c.frames = [Frame(id: String(format: "%03d", i), hold: 1)]
            clips.append(c)
        }
        if clips.isEmpty { clips = [Self.defaultClip()] }
        let project = Project(name: name,
                              canvas: CanvasSize(width: min(max(config.width, side.lowerBound), side.upperBound),
                                                 height: min(max(config.height, side.lowerBound), side.upperBound)),
                              fps: min(max(config.fps, 1), 60),
                              clips: clips)
        do {
            try install(project, images: [:])
        } catch {
            lastError = "Couldn't create \(name).\n\(error.localizedDescription)"
            return
        }
        save(to: library.url(for: name))
        isInGallery = false
    }

    /// Back to the gallery. Saves first: a project with a file is saved in place, one without
    /// (drawn on before there was a gallery) gets a file in Documents if it has changes.
    func closeToGallery() {
        stop()
        if documentURL != nil {
            saveIfNeeded()
        } else if isDirty {
            let library = ProjectLibrary(directory: Self.documentsDirectory)
            save(to: library.url(for: library.uniqueName(project.name)))
        }
        isZen = false
        isInGallery = true
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
            isInGallery = false
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
        commitSelection()
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
        selection = nil; selectionBefore = nil; selectionPreview = nil; lassoPoints = []
        playRange = nil
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
        commitSelection()
        playRange = nil
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

    /// New frame after the current one. Only the current layer gets a fresh, blank drawing; every
    /// other layer holds what it was showing, so a background or a colour pass carries on by itself.
    func addFrame() {
        let id = newFrameID()
        recordUndo(textures: allCellKeys() + layerKeys(clip, frame: id))
        keepingPicture { insertBlankFrame(id: id, holdingOthers: true) }
        refreshClipThumbnails()
    }

    private func insertBlankFrame(id: String? = nil, holdingOthers: Bool = false) {
        let at = frames.isEmpty ? 0 : frameIndex + 1
        let others = at > 0 && holdingOthers ? layers.map(\.id).filter { $0 != currentLayer?.id } : []
        clip.frames.insert(Frame(id: id ?? newFrameID(), hold: 1, held: others), at: at)
        frameIndex = at
        isDirty = true
    }

    /// Copies the current frame after itself: its own drawings are duplicated, its holds stay holds.
    func duplicateFrame() {
        guard let src = currentFrame else { return }
        let f = Frame(id: newFrameID(), hold: src.hold,
                      held: layers.map(\.id).filter { clip.isHeld(layer: $0, at: frameIndex) })
        recordUndo(textures: allCellKeys() + layerKeys(clip, frame: f.id))
        let at = frameIndex + 1
        keepingPicture {
            clip.frames.insert(f, at: at)
            for l in layers where !f.held.contains(l.id) {
                store.set(store.copy(of: LayerKey(clip: clip.id, frame: src.id, layer: l.id)),
                          for: LayerKey(clip: clip.id, frame: f.id, layer: l.id))
            }
        }
        frameIndex = at
        isDirty = true
        refreshClipThumbnails()
    }

    /// Removes the current frame. A drawing it owned that later frames were holding moves to the
    /// first of them, so nothing else changes on screen.
    func deleteFrame() {
        guard frames.count > 1, let f = currentFrame else { return }
        recordUndo(textures: allCellKeys())
        let at = frameIndex
        keepingPicture { clip.frames.remove(at: at) }
        store.remove(clip: clip.id, frame: f.id, layers: layers.map(\.id))
        thumbnails.removeValue(forKey: f.id)
        frameIndex = min(frameIndex, frames.count - 1)
        isDirty = true
        refreshClipThumbnails()
    }

    func moveFrame(by offset: Int) {
        let to = frameIndex + offset
        guard frames.indices.contains(to) else { return }
        recordUndo(textures: allCellKeys())
        let from = frameIndex
        keepingPicture { clip.frames.swapAt(from, to) }
        frameIndex = to
        isDirty = true
        refreshClipThumbnails()
    }

    /// Moves frame `id` so it ends up at `index`. The selection stays on the frame that was selected.
    func moveFrame(id: String, to index: Int) {
        guard let from = frames.firstIndex(where: { $0.id == id }) else { return }
        let to = min(max(index, 0), frames.count - 1)
        guard from != to else { return }
        recordUndo(textures: allCellKeys(), coalescing: "move:\(id)")
        let selectedID = currentFrame?.id
        keepingPicture { clip.frames.insert(clip.frames.remove(at: from), at: to) }
        if let selectedID, let i = frames.firstIndex(where: { $0.id == selectedID }) {
            frameIndex = i
        }
        isDirty = true
        refreshClipThumbnails()
    }

    // MARK: - Exposure sheet cells

    /// The current layer shows the previous frame's drawing here instead of its own (a hold).
    /// Its own drawing at this frame is dropped; undo brings it back.
    func holdCurrentCell() {
        guard frameIndex > 0, let l = currentLayer, !l.locked, !currentCellIsHeld, let f = currentFrame else { return }
        let own = LayerKey(clip: clip.id, frame: f.id, layer: l.id)
        recordUndo(textures: [own])
        clip.frames[frameIndex].held.append(l.id)
        store.set(nil, for: own)
        isDirty = true
        refreshClipThumbnails()
    }

    /// Gives the current layer a drawing of its own here, blank or a copy of the one it was holding.
    /// Later frames that were holding through here now hold this new drawing.
    func releaseCurrentCell(copying: Bool) {
        guard currentCellIsHeld, let l = currentLayer, !l.locked, let f = currentFrame,
              let source = currentDrawingKey else { return }
        let own = LayerKey(clip: clip.id, frame: f.id, layer: l.id)
        recordUndo(textures: [own])
        clip.frames[frameIndex].held.removeAll { $0 == l.id }
        store.set(copying ? store.copy(of: source) : nil, for: own)
        isDirty = true
        refreshClipThumbnails()
    }

    /// Makes the drawing that starts at frame `start` on `layer` span `count` frames: frames after
    /// it become holds of it (their own drawings on that layer are dropped), or, when shortened,
    /// the frames it no longer covers get blank drawings of their own. A drag is one undo step.
    func setDrawingSpan(layer: String, start: Int, count: Int) {
        guard frames.indices.contains(start), !clip.isHeld(layer: layer, at: start),
              layers.first(where: { $0.id == layer })?.locked == false else { return }
        let old = clip.runs(of: layer).first { $0.start == start }?.count ?? 1
        let new = min(max(1, count), frames.count - start)
        guard new != old else { return }
        let touched = (start + 1)..<(start + max(old, new))
        // A drag reaches further as it goes, but only its first step records the undo: save every
        // cell it could still cover on this layer, not just the ones it touches now.
        recordUndo(textures: ((start + 1)..<frames.count).map { LayerKey(clip: clip.id, frame: frames[$0].id, layer: layer) },
                   coalescing: "span:\(layer):\(frames[start].id)")
        for i in touched {
            let own = LayerKey(clip: clip.id, frame: frames[i].id, layer: layer)
            if i < start + new {
                if !clip.frames[i].held.contains(layer) { clip.frames[i].held.append(layer) }
                clip.frames[i].labels[layer] = nil
                store.set(nil, for: own)
            } else {
                clip.frames[i].held.removeAll { $0 == layer }
            }
        }
        isDirty = true
        refreshClipThumbnails()
    }

    /// The label of the drawing `layer` shows at frame `index`, if it has one.
    func drawingLabel(layer: String, at index: Int) -> String? {
        guard frames.indices.contains(index) else { return nil }
        return frames[clip.sourceIndex(layer: layer, at: index)].labels[layer]
    }

    /// Names (or, with an empty name, un-names) the current layer's drawing at the playhead.
    func setCurrentDrawingLabel(_ name: String) {
        guard let l = currentLayer, frames.indices.contains(frameIndex) else { return }
        let i = clip.sourceIndex(layer: l.id, at: frameIndex)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clip.frames[i].labels[l.id] != (trimmed.isEmpty ? nil : trimmed) else { return }
        recordUndo()
        clip.frames[i].labels[l.id] = trimmed.isEmpty ? nil : trimmed
        isDirty = true
    }

    /// Every (frame, layer) cell of the current clip, held or not.
    private func allCellKeys() -> [LayerKey] {
        frames.flatMap { layerKeys(clip, frame: $0.id) }
    }

    /// Runs a change to the clip's frame list and keeps every frame that's still there looking the
    /// same: a cell whose drawing would change (it held from a frame that moved or went away, or it
    /// ended up first) gets the drawing it was showing as its own copy. The first frame never holds.
    private func keepingPicture(_ change: () -> Void) {
        var before: [LayerKey: MTLTexture?] = [:]
        var labelBefore: [LayerKey: String] = [:]
        for i in frames.indices {
            for l in layers {
                let cell = LayerKey(clip: clip.id, frame: frames[i].id, layer: l.id)
                before.updateValue(drawingKey(layer: l.id, at: i).flatMap(store.raw), forKey: cell)
                labelBefore[cell] = drawingLabel(layer: l.id, at: i)
            }
        }
        change()
        if !clip.frames.isEmpty { clip.frames[0].held = [] }
        // One copy per old drawing: frames after the first materialised one hold it again.
        var copies: [ObjectIdentifier: MTLTexture] = [:]
        for i in frames.indices {
            for l in layers {
                let cell = LayerKey(clip: clip.id, frame: frames[i].id, layer: l.id)
                guard let entry = before[cell] else { continue }
                let expected: MTLTexture? = entry.map { copies[ObjectIdentifier($0)] ?? $0 }
                let now = drawingKey(layer: l.id, at: i).flatMap(store.raw)
                if (now as AnyObject?) === (expected as AnyObject?) { continue }
                clip.frames[i].held.removeAll { $0 == l.id }
                clip.frames[i].labels[l.id] = labelBefore[cell]
                if let old = entry, let c = store.copy(old) {
                    store.set(c, for: cell)
                    copies[ObjectIdentifier(old)] = c
                } else {
                    store.set(nil, for: cell)
                }
            }
        }
    }

    func setHold(_ hold: Int) {
        guard let f = currentFrame, max(1, hold) != f.hold else { return }
        recordUndo(coalescing: "hold:\(f.id)")
        clip.frames[frameIndex].hold = max(1, hold)
        isDirty = true
    }

    func clearCurrentLayer() {
        guard let k = currentDrawingKey, currentLayer?.locked == false else { return }
        recordUndo(textures: [k], copyPixels: true)
        store.clear(clip: k.clip, frame: k.frame, layer: k.layer)
        isDirty = true
        refreshThumbnails(showing: k)
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
        for i in clip.frames.indices { clip.frames[i].held.removeAll { $0 == doomed.id } }
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
        commitSelection()
        isPlaying ? stop() : play()
    }

    /// Frames playback runs over: the whole clip, or the in / out range when one is set.
    /// View state: not saved, and it never affects export.
    @Published var playRange: ClosedRange<Int>?

    var effectivePlayRange: ClosedRange<Int> {
        let all = 0...max(0, frames.count - 1)
        guard let r = playRange, r.lowerBound <= all.upperBound else { return all }
        return r.clamped(to: all)
    }

    /// Sets the in (start) or out (end) point at the current frame, keeping in ≤ out.
    func setPlayRange(start: Bool) {
        let r = effectivePlayRange
        playRange = start ? frameIndex...max(frameIndex, r.upperBound) : min(frameIndex, r.lowerBound)...frameIndex
        if playRange == 0...max(0, frames.count - 1) { playRange = nil }
    }

    private func play() {
        let range = effectivePlayRange
        guard range.count > 1 else { return }
        if !range.contains(frameIndex) || (!clip.loop && frameIndex == range.upperBound) { frameIndex = range.lowerBound }
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
            let range = self.effectivePlayRange
            let next = self.frameIndex + 1
            if next <= range.upperBound {
                self.frameIndex = next
            } else if self.clip.loop {
                self.frameIndex = range.lowerBound
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
                out += onionLayers(at: idx, opacity: onion.opacity * fade, tint: onion.beforeTint)
            }
            for i in stride(from: onion.after, through: 1, by: -1) {
                let idx = frameIndex + i
                guard frames.indices.contains(idx) else { continue }
                let fade = 1 - Float(i - 1) / Float(max(onion.after, 1)) * 0.6
                out += onionLayers(at: idx, opacity: onion.opacity * fade, tint: onion.afterTint)
            }
        }
        if currentFrame != nil {
            for layer in clip.layers where layer.visible {
                let key = drawingKey(layer: layer.id, at: frameIndex)
                if let key, let t = store.existingTexture(clip: key.clip, frame: key.frame, layer: key.layer) {
                    out.append(.init(texture: t, opacity: Float(layer.opacity), tint: .zero, tintAmount: 0))
                }
                // A floating selection shows right above its own layer, where it'll land.
                if let sel = selection, sel.key == key, let preview = selectionPreview {
                    out.append(.init(texture: preview, opacity: Float(layer.opacity), tint: .zero, tintAmount: 0))
                }
            }
        }
        return out
    }

    /// A neighbouring frame for onion skin: only layers whose drawing there differs from the one on
    /// screen now, so a held background doesn't ghost over itself.
    private func onionLayers(at idx: Int, opacity: Float, tint: SIMD3<Float>) -> [CanvasRenderer.CompositeLayer] {
        if onion.currentLayerOnly, let l = currentLayer {
            guard let k = drawingKey(layer: l.id, at: idx), k != drawingKey(layer: l.id, at: frameIndex),
                  l.visible, let t = store.existingTexture(clip: k.clip, frame: k.frame, layer: k.layer) else { return [] }
            return [.init(texture: t, opacity: Float(l.opacity) * opacity, tint: tint, tintAmount: 1)]
        }
        return clip.layers.compactMap { layer in
            guard layer.visible, let k = drawingKey(layer: layer.id, at: idx),
                  k != drawingKey(layer: layer.id, at: frameIndex),
                  let t = store.existingTexture(clip: k.clip, frame: k.frame, layer: k.layer) else { return nil }
            return .init(texture: t, opacity: Float(layer.opacity) * opacity, tint: tint, tintAmount: 1)
        }
    }

    private func frameLayers(_ frameID: String, opacity: Float, tint: SIMD3<Float>?) -> [CanvasRenderer.CompositeLayer] {
        frameLayers(of: clip, frameID, opacity: opacity, tint: tint)
    }

    /// Every visible layer as it shows at frame `frameID` of `clip`, holds resolved.
    private func frameLayers(of clip: Clip, _ frameID: String, opacity: Float, tint: SIMD3<Float>?) -> [CanvasRenderer.CompositeLayer] {
        let index = clip.frames.firstIndex { $0.id == frameID }
        return clip.layers.compactMap { layer in
            let source = index.flatMap { clip.sourceFrameID(layer: layer.id, at: $0) } ?? frameID
            guard layer.visible,
                  let t = store.existingTexture(clip: clip.id, frame: source, layer: layer.id) else { return nil }
            return CanvasRenderer.CompositeLayer(
                texture: t,
                opacity: Float(layer.opacity) * opacity,
                tint: tint ?? .zero,
                tintAmount: tint == nil ? 0 : 1)
        }
    }

    // MARK: - Thumbnails

    /// Refreshes every frame of the current clip that shows drawing `key` (its own frame and the
    /// frames holding it).
    func refreshThumbnails(showing key: LayerKey) {
        for i in frames.indices where drawingKey(layer: key.layer, at: i) == key {
            refreshThumbnail(for: frames[i].id)
        }
    }

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
        guard let key = currentDrawingKey, currentLayer?.locked == false else { return nil }
        var saved: [LayerKey: MTLTexture?] = [:]
        saved.updateValue(store.copy(of: key), forKey: key)
        pendingStroke = snapshot(saved)
        return paintTarget
    }

    func strokeEnded() {
        let key = pendingStroke?.textures.keys.first
        if let s = pendingStroke {
            coalesceTag = nil
            push(s)
            pendingStroke = nil
        }
        isDirty = true
        if let key { refreshThumbnails(showing: key) } else if let f = currentFrame { refreshThumbnail(for: f.id) }
    }

    /// A gesture took over (two-finger tap, pinch): put the pixels back as if the stroke never happened.
    func cancelStroke() {
        guard let s = pendingStroke else { return }
        pendingStroke = nil
        for (k, t) in s.textures { store.set(t, for: k); refreshThumbnails(showing: k) }
    }

    // MARK: - Fill and eyedropper

    enum FillGaps: Int, CaseIterable, Identifiable {
        case off, small, medium, large
        var id: Int { rawValue }
        var title: String { ["Off", "Small", "Medium", "Large"][rawValue] }

        /// Thickening radius in canvas pixels, proportional to the canvas so "small" means the
        /// same on a 64 px sprite and a 1024 px one.
        func radius(forCanvasSide side: Int) -> Int {
            switch self {
            case .off: 0
            case .small: max(1, side / 256)
            case .medium: max(2, side / 128)
            case .large: max(3, side / 64)
            }
        }
    }

    /// How different a pixel may be from the one tapped and still be filled (0–255 per channel).
    static let fillTolerance = 40
    /// Extra pixels the fill grows by, so it tucks under anti-aliased line edges.
    static let fillGrow = 2

    /// Bucket fill at a canvas point. The region comes from all visible layers of the frame (so
    /// lines on "Line" bound a fill on "Color"); the paint goes on the current layer. Undoable.
    func fill(at point: SIMD2<Float>) {
        guard !isPlaying, let f = currentFrame, let key = currentDrawingKey, currentLayer?.locked == false else { return }
        let w = renderer.canvasSize.x, h = renderer.canvasSize.y
        let seed = (x: Int(point.x.rounded(.down)), y: Int(point.y.rounded(.down)))
        guard (0..<w).contains(seed.x), (0..<h).contains(seed.y),
              let seen = renderer.flattenBytes(frameLayers(f.id, opacity: 1, tint: nil)) else { return }
        let region = FloodFill.region(in: seen, width: w, height: h, seed: seed, tolerance: Self.fillTolerance,
                                      closingGaps: fillGaps.radius(forCanvasSide: max(w, h)))
        guard !region.isEmpty else { return }
        let mask = FloodFill.grow(region, width: w, height: h, by: Self.fillGrow)

        recordUndo(textures: [key], copyPixels: true)
        guard let target = store.texture(clip: key.clip, frame: key.frame, layer: key.layer),
              var pixels = renderer.readbackBytes(target) else { return }
        FloodFill.paint(mask, color: SIMD3(color.x, color.y, color.z), into: &pixels)
        renderer.upload(bytes: pixels, into: target)
        isDirty = true
        refreshThumbnails(showing: key)
    }

    /// Takes the colour of what's on screen at a canvas point (all visible layers), then returns
    /// to the tool used before the eyedropper. Tapping empty canvas changes nothing.
    @discardableResult
    func pickColor(at point: SIMD2<Float>) -> Bool {
        defer { if tool == .eyedropper { tool = toolBeforeEyedropper } }
        guard let f = currentFrame,
              let seen = renderer.flattenBytes(frameLayers(f.id, opacity: 1, tint: nil)),
              let picked = FloodFill.color(in: seen, width: renderer.canvasSize.x, height: renderer.canvasSize.y,
                                           at: (Int(point.x.rounded(.down)), Int(point.y.rounded(.down))))
        else { return false }
        color = SIMD4(picked, 1)
        return true
    }

    // MARK: - Lasso

    /// Lifts what's inside the closed lasso off the current layer into a floating selection.
    /// Nothing happens on a locked layer, or if the lasso holds no pixels.
    func liftSelection(_ polygon: [CGPoint]) {
        lassoPoints = []
        commitSelection()
        guard !isPlaying, polygon.count >= 3, let key = currentDrawingKey, currentLayer?.locked == false else { return }
        guard let target = store.existingTexture(clip: key.clip, frame: key.frame, layer: key.layer),
              let pixels = renderer.readbackBytes(target) else { return }
        let w = renderer.canvasSize.x, h = renderer.canvasSize.y
        let (lifted, remaining) = SelectionPixels.split(pixels, mask: SelectionPixels.rasterize(polygon, width: w, height: h))
        guard !SelectionPixels.isEmpty(lifted) else { return }

        let bounds = Self.boundingBox(polygon).intersection(CGRect(x: 0, y: 0, width: w, height: h))
        selectionBefore = store.copy(of: key)
        renderer.upload(bytes: remaining, into: target)
        selectionPreview = selectionPreview ?? renderer.makeLayerTexture()
        selection = FloatingSelection(key: key, lifted: lifted, outline: polygon, bounds: bounds,
                                      anchor: CGPoint(x: bounds.midX, y: bounds.midY))
        renderSelectionPreview()
    }

    /// Changes the floating selection's transform (move, scale, rotate, flip, anchor).
    func updateSelection(_ change: (inout FloatingSelection) -> Void) {
        guard var sel = selection else { return }
        change(&sel)
        sel.scale = min(max(sel.scale, FloatingSelection.scaleRange.lowerBound), FloatingSelection.scaleRange.upperBound)
        selection = sel
        renderSelectionPreview()
    }

    /// Drops the selection where it is, as one undo step with the lift.
    func commitSelection() {
        guard let sel = selection else { return }
        selection = nil
        lassoPoints = []
        guard let target = store.texture(clip: sel.key.clip, frame: sel.key.frame, layer: sel.key.layer),
              let base = renderer.readbackBytes(target) else { return }
        let w = renderer.canvasSize.x, h = renderer.canvasSize.y
        let placed = SelectionPixels.render(sel.lifted, width: w, height: h, transform: sel.transform)
        renderer.upload(bytes: SelectionPixels.composite(placed, over: base), into: target)
        var before: [LayerKey: MTLTexture?] = [:]
        before.updateValue(selectionBefore, forKey: sel.key)
        coalesceTag = nil
        push(snapshot(before))
        selectionBefore = nil
        isDirty = true
        refreshThumbnails(showing: sel.key)
    }

    /// Puts the lifted pixels back untouched, as if the lasso never happened.
    func cancelSelection() {
        guard let sel = selection else { return }
        selection = nil
        lassoPoints = []
        if let before = selectionBefore { store.set(before, for: sel.key) }
        selectionBefore = nil
        refreshThumbnails(showing: sel.key)
    }

    private func renderSelectionPreview() {
        guard let sel = selection, let preview = selectionPreview else { return }
        let w = renderer.canvasSize.x, h = renderer.canvasSize.y
        renderer.upload(bytes: SelectionPixels.render(sel.lifted, width: w, height: h, transform: sel.transform),
                        into: preview)
    }

    private static func boundingBox(_ points: [CGPoint]) -> CGRect {
        let xs = points.map(\.x), ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return .null }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
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
        static let fillGaps = "tool.fillGaps"
        static let smoothing = "tool.smoothing"
        static let usePressure = "tool.usePressure"
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
        if let raw = defaults.object(forKey: ToolKey.fillGaps) as? Int, let g = FillGaps(rawValue: raw) { fillGaps = g }
        if let v = defaults.object(forKey: ToolKey.smoothing) as? Float, (0...1).contains(v) { smoothing = v }
        if let v = defaults.object(forKey: ToolKey.usePressure) as? Bool { usePressure = v }
    }

    private func saveToolSettings() {
        guard let defaults, !loadingToolSettings else { return }
        defaults.set(brushSize, forKey: ToolKey.brushSize)
        defaults.set(eraserSize, forKey: ToolKey.eraserSize)
        defaults.set([color.x, color.y, color.z], forKey: ToolKey.color)
        defaults.set(fillGaps.rawValue, forKey: ToolKey.fillGaps)
        defaults.set(smoothing, forKey: ToolKey.smoothing)
        defaults.set(usePressure, forKey: ToolKey.usePressure)
    }

    func setColor(_ c: SIMD4<Float>) {
        color = SIMD4<Float>(min(max(c.x, 0), 1), min(max(c.y, 0), 1), min(max(c.z, 0), 1), 1)
        // A colour is for painting: leave the eraser, but keep filling if that's what you were doing.
        if tool != .fill { tool = .brush }
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
        commitSelection()
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
        // With a selection floating, undo means "never mind": put it back where it was.
        if selection != nil { cancelSelection(); return }
        guard let s = undoStack.popLast() else { return }
        redoStack.append(snapshot(currentTextures(s)))
        apply(s)
    }

    func redo() {
        cancelStroke()
        commitSelection()
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
