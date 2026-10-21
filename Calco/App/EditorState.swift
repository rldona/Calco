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
@Observable
final class EditorState {

    var project: Project
    var clipIndex = 0
    var frameIndex = 0 {
        didSet {
            if frameIndex != oldValue { selectionTargetChanged() }
            if !isPlaying { markFrame() }
        }
    }
    /// The frame the timeline marks as current: the playhead, except while playing, when it stays
    /// where playback started. So playing moves only the playhead, its counter and the canvas, not
    /// every cell of the timeline.
    private(set) var markedFrameIndex = 0
    private func markFrame() { if markedFrameIndex != frameIndex { markedFrameIndex = frameIndex } }
    var layerIndex = 0 { didSet { if layerIndex != oldValue { selectionTargetChanged() } } }
    var tool: CanvasRenderer.Tool = .brush {
        didSet {
            // A path being edited is off the drawing: put it back before anything else looks at
            // the drawing (Move would lift it without the path, and lose it).
            if tool != .pen && tool != .node { finishPen() }
            if tool == .eyedropper && oldValue != .eyedropper { toolBeforeEyedropper = oldValue }
            if tool != oldValue { previousTool = oldValue }
            if tool != .lasso && !(tool == .move && oldValue == .move) { commitSelection() }
            if tool != .move { moveBlockedLayer = nil; addingStrokes = false }
            if tool == .move && oldValue != .move { liftForMove() }
        }
    }
    /// The eyedropper is one-shot: after a pick you're back on this.
    @ObservationIgnored private var toolBeforeEyedropper: CanvasRenderer.Tool = .brush
    /// The brush the brush tool paints with, and the one whose tip the eraser rubs out with.
    var brushID = Brush.inker.id { didSet { saveToolSettings() } }
    var eraserBrushID = Brush.inker.id { didSet { saveToolSettings() } }
    /// Each brush's own size (radius in canvas pixels at full pressure) and opacity, once changed.
    private var brushSizes: [String: Float] = [:] { didSet { saveToolSettings() } }
    private var brushOpacities: [String: Float] = [:] { didSet { saveToolSettings() } }
    var eraserSize: Float = 18 { didSet { saveToolSettings() } }
    /// The faint grid around the canvas (Preferences).
    var workspaceGrid = true { didSet { saveToolSettings() } }

    var brush: Brush { Brush.named(brushID) }
    var eraserBrush: Brush { Brush.named(eraserBrushID) }
    /// What the current tool lays down with.
    var activeBrush: Brush {
        tool == .eraser ? eraserBrush : tool == .smudge ? (smudge.useBrushTip ? brush : .smudgeTip) : brush
    }

    /// The current brush's size.
    var brushSize: Float {
        get { size(of: brush) }
        set { brushSizes[brushID] = newValue }
    }

    func size(of brush: Brush) -> Float { brushSizes[brush.id] ?? brush.defaultSize }

    /// The current brush's opacity, 0.05–1.
    var brushOpacity: Float {
        get { opacity(of: brush) }
        set { brushOpacities[brushID] = min(max(newValue, 0.05), 1) }
    }

    func opacity(of brush: Brush) -> Float { brushOpacities[brush.id] ?? brush.defaultOpacity }

    /// The stroke in progress on its own, composited onto the layer as it grows.
    @ObservationIgnored private var strokeTexture: MTLTexture?
    @ObservationIgnored private var strokeBase: MTLTexture?
    /// Brush stabiliser 0–1 and whether the Pencil's pressure changes the size. Remembered.
    var smoothing: Float = 0.3 { didSet { saveToolSettings() } }
    var usePressure = true { didSet { saveToolSettings() } }
    /// Brush and fill: over what's on the layer, behind it, or only inside it.
    var paintMode: CanvasRenderer.PaintMode = .front { didSet { saveToolSettings() } }
    /// Fingers never draw (they still zoom, pan and undo); only the Apple Pencil does. Starts as the
    /// system's "Only draw with Apple Pencil" setting.
    var pencilOnly = false { didSet { saveToolSettings() } }
    /// The tool before the current one, for the Pencil's "switch to previous tool".
    private(set) var previousTool: CanvasRenderer.Tool = .eraser
    /// Bumped when the Pencil asks for the colour palette (double tap / squeeze set to show it).
    var colorPickerRequest = 0
    /// The bar's add / duplicate / delete act on every layer's frame instead of the current layer's drawing.
    var syncLayers = false { didSet { saveToolSettings() } }
    /// How big a break in a line the fill bucket bridges. Remembered across launches.
    var fillGaps: FillGaps = .small { didSet { saveToolSettings() } }
    /// The Shapes tool: which shape, its outline, fill and size.
    var shapeOptions = ShapeOptions() { didSet { saveToolSettings() } }
    /// The shape being dragged out, from where the finger went down to where it is (canvas
    /// pixels), and what it clicked into; drawn over the canvas until the finger lifts.
    var shapeDraft: ShapeDraft?
    struct ShapeDraft: Equatable {
        var from: CGPoint
        var to: CGPoint
        var snap: ShapeGeometry.Snap
    }
    /// The Smudge tool: smudge, blur or motion, how strongly, its size, and its tip.
    struct SmudgeOptions: Codable, Equatable {
        var mode = CanvasRenderer.SmudgeMode.smudge
        var strength: Float = 0.6
        var size: Float = 16
        /// Smudge with the brush's tip (a grainy pencil smear) instead of a soft one.
        var useBrushTip = false
    }
    var smudge = SmudgeOptions() { didSet { saveToolSettings() } }
    @ObservationIgnored private var smudgeScratch: MTLTexture?
    /// Where the last smudge dab was, so the next knows which way the finger is going.
    @ObservationIgnored private var lastSmudgeDab: SIMD2<Float>?

    /// A shape just painted, waiting to be kept as a piece when the stroke ends.
    @ObservationIgnored private var pendingShape: StrokeRecipe?

    /// A Pen path being drawn or edited: its points, the one picked, and the drawing it's on.
    struct PenEditing: Equatable {
        var path: PenPath
        /// The points picked: one with the Pen, any number with the Node tool.
        var picked: Set<Int> = []
        let key: LayerKey
        /// Editing a path already in the drawing: which piece it is (hidden while it's edited).
        var piece: Int?
        /// Its colour: the one it was painted in, or the bar's for a new path.
        var ink = SIMD3<Float>(0, 0, 0)

        /// The one picked point, whose handles show; nil when none or several are picked.
        var selected: Int? {
            get { picked.count == 1 ? picked.first : nil }
            set { picked = newValue.map { [$0] } ?? [] }
        }

        init(path: PenPath, selected: Int? = nil, key: LayerKey, piece: Int? = nil, ink: SIMD3<Float>) {
            self.path = path
            self.key = key
            self.piece = piece
            self.ink = ink
            self.selected = selected
        }
    }
    private(set) var penEditing: PenEditing?
    /// The drawing's pixels from before an existing path was opened, for Cancel and undo.
    @ObservationIgnored private var penBefore: MTLTexture?
    /// What a finger grabbed with the Pen: a point, one of its handles, or a point just placed
    /// (dragging pulls its handles out, curving it).
    enum PenGrab: Equatable { case node(Int), handle(Int, outgoing: Bool), newNode(Int) }
    /// Brush colour, straight RGBA. Always opaque for now: overlapping stamps would build up any translucency.
    var color = SIMD4<Float>(0, 0, 0, 1) {
        didSet {
            saveToolSettings()
            // With a path open, a new colour is for that path.
            if penEditing != nil { penEditing?.ink = SIMD3(color.x, color.y, color.z) }
        }
    }
    static let sizeRange: ClosedRange<Float> = 1...64
    var onion = OnionSkin()
    var isPlaying = false { didSet { if !isPlaying { markFrame() } } }
    /// Show the draggable pivot handle over the canvas.
    var showPivot = false
    /// The project gallery is showing instead of the editor. The app starts there.
    var isInGallery = true
    /// English unless changed in Preferences; applies at once and is remembered.
    var language: AppLanguage = AppLanguage.saved {
        didSet { if language != oldValue { AppLanguage.apply(language) } }
    }
    var showingPreferences = false
    /// The lasso being drawn, in canvas pixels. Empty when not drawing one.
    var lassoPoints: [CGPoint] = []
    /// What the lasso lifted, while it's being transformed. Nil when nothing is selected.
    private(set) var selection: FloatingSelection? {
        didSet { if (selection != nil) != hasSelection { hasSelection = selection != nil } }
    }
    /// Whether something floats, apart from where: the chrome only needs this much, and so isn't
    /// redrawn on every step of a drag.
    private(set) var hasSelection = false
    /// The layer's pixels from before the lift: one undo step covers lift, transform and drop.
    @ObservationIgnored private var selectionBefore: MTLTexture?
    /// The selection was lifted off the layer (lasso or Move), not pasted: left where it was, it's no change.
    @ObservationIgnored private var selectionIsLift = false
    /// With Move: the current layer is locked, so nothing was lifted. The editor offers to unlock it.
    private(set) var moveBlockedLayer: String?
    /// A layer Move unlocked for a moment; it's locked again when the move is dropped.
    @ObservationIgnored private var relockAfterMove: String?
    /// The selection drawn at its current transform, composited above its layer.
    @ObservationIgnored private var selectionPreview: MTLTexture?
    /// Where strokes are painted again from their recipes: the stroke, and the other half of a
    /// ping-pong with `selectionPreview`.
    @ObservationIgnored private var recipeStroke: MTLTexture?
    @ObservationIgnored private var recipeScratch: MTLTexture?
    /// A shape's inside in its own colour, before its line goes on top.
    @ObservationIgnored private var fillScratch: MTLTexture?
    /// Zen mode: only the canvas and a small floating bar. View state only.
    var isZen = false
    /// Zoom / pan / rotation of the canvas on screen. View state only: not saved, not undoable.
    var canvasTransform = CanvasTransform.identity {
        didSet {
            if canvasTransform.flipped != viewFlipped { viewFlipped = canvasTransform.flipped }
            if canvasTransform.isFit != canvasIsFit { canvasIsFit = canvasTransform.isFit }
            if canvasTransform.insets.bottom != bottomInset { bottomInset = canvasTransform.insets.bottom }
        }
    }
    /// The bits of `canvasTransform` the chrome shows, apart, so a pinch or a pan doesn't redraw
    /// the chrome on every frame.
    private(set) var viewFlipped = false
    private(set) var canvasIsFit = true
    private(set) var bottomInset: CGFloat = 0

    /// Back to the fitted, upright canvas; a flipped view stays flipped.
    func fitCanvas() { canvasTransform = CanvasTransform(flipped: canvasTransform.flipped, insets: canvasTransform.insets) }
    /// Each drawing on its own over white paper, for the timeline's cells.
    private(set) var drawingThumbnails: [LayerKey: CGImage] = [:]
    /// Which texture each preview was made from, to skip the ones that haven't changed.
    @ObservationIgnored private var drawingThumbnailSource: [LayerKey: ObjectIdentifier] = [:]
    @ObservationIgnored private var pendingThumbnails: [LayerKey: CGImage?] = [:]
    @ObservationIgnored private var thumbnailFlushScheduled = false

    /// Where the project lives on disk. Nil until the first save.
    private(set) var documentURL: URL?
    /// True when there are changes since the last save or load.
    private(set) var isDirty = false { didSet { canvasVersion &+= 1 } }
    /// Bumped whenever the drawings' pixels may have changed (every edit marks the document
    /// dirty), so the canvas, which watches what it draws, knows to draw again.
    private(set) var canvasVersion = 0
    /// Last file error, shown by the UI and cleared by it.
    var lastError: String?

    /// Actions that need a dialog or sheet owned by a view (the file menu). Menus and keyboard
    /// shortcuts set it; the view presents what's needed and clears it.
    enum Request: Equatable { case newProject, open, saveAs, export, exportAgain, exportGIF }
    var request: Request?

    private(set) var renderer: CanvasRenderer
    private(set) var store: FrameStore
    private let screenFormat: MTLPixelFormat
    /// Where tool settings are remembered. Nil (tests, previews) keeps them in memory only.
    private let defaults: UserDefaults?

    /// Saved export profiles (app-wide) and the one used last.
    var exportProfiles: [ExportProfile] = ExportProfile.presets {
        didSet { ExportProfileStore(defaults: defaults).save(exportProfiles) }
    }
    var lastExportProfileID: UUID? {
        didSet { ExportProfileStore(defaults: defaults).lastUsed = lastExportProfileID }
    }
    var lastExportProfile: ExportProfile? {
        exportProfiles.first { $0.id == lastExportProfileID }
    }

    @ObservationIgnored private var nextFrameNumber = 0
    @ObservationIgnored private var playTask: Task<Void, Never>?

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    @ObservationIgnored private var coalesceTag: String?
    /// Pixels from before the stroke in progress; enters the history only when the stroke ends.
    @ObservationIgnored private var pendingStroke: Snapshot?
    /// The stamps of the stroke in progress, so it can be kept as a piece of its own.
    @ObservationIgnored private var pendingStamps: [CanvasRenderer.Stamp] = []

    /// Each drawing's pieces, bottom to top: its pencil strokes, and shapes for what can't be told
    /// apart any more. Move picks them one by one. Missing means not known: the drawing is split
    /// into its separate shapes when Move needs it.
    @ObservationIgnored private(set) var strokes: [LayerKey: [StrokePiece]] = [:]
    /// When Move picked pieces: which ones float, so they go back as pieces.
    @ObservationIgnored private var movingPieces: (key: LayerKey, indices: [Int])?
    /// Where the last tap picked, so tapping the same spot again goes to the piece underneath.
    @ObservationIgnored private var lastPick: (key: LayerKey, point: CGPoint, index: Int)?
    /// Move: taps add pieces to (or take them out of) what's floating instead of replacing it.
    var addingStrokes = false
    /// What Move picked with the last tap, for the hint under the canvas.
    private(set) var moveHint: MoveHint?

    struct MoveHint: Equatable {
        /// Pieces under the tap, and which of them (1 = the bottom one) is picked.
        var here: Int
        var number: Int
        /// Pieces floating in all.
        var selected: Int
    }
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
        let profiles = ExportProfileStore(defaults: defaults)
        self.exportProfiles = profiles.load()
        self.lastExportProfileID = profiles.lastUsed
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

    /// Whether the current layer's cell at the playhead repeats another drawing, linked (a cycle).
    var currentCellIsLinked: Bool {
        currentLayer.map { clip.isLinked(layer: $0.id, at: clip.cellStart(layer: $0.id, at: frameIndex)) } ?? false
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
        var pixelArt = false

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
                              clips: clips,
                              pixelArt: config.pixelArt)
        do {
            try install(project, images: [:])
        } catch {
            lastError = String(localized: "Couldn't create \(name).\n\(error.localizedDescription)", bundle: AppLanguage.bundle)
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
        finishPen()
        try? install(Self.defaultProject(), images: [:])
        documentURL = nil
        isDirty = false
    }

    /// Loads a `.calco` package (from Files, the document picker or `onOpenURL`).
    func open(_ url: URL) {
        stop()
        finishPen()
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let loaded = try ProjectDocument.load(from: url)
            let images = ProjectDocument.loadLayerImages(from: url, project: loaded)
            let pieces = ProjectDocument.loadLayerStrokes(from: url, project: loaded).compactMapValues(StrokePieces.decode)
            try install(loaded, images: images, strokes: pieces)
            documentURL = url
            isDirty = false
            isInGallery = false
        } catch {
            lastError = String(localized: "Couldn't open \(url.lastPathComponent).\n\(error.localizedDescription)", bundle: AppLanguage.bundle)
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
        finishPen()
        commitSelection()
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            try ProjectDocument.save(project, to: url, layerImage: { key in
                store.image(clip: key.clip, frame: key.frame, layer: key.layer)
            }, layerStrokes: { key in
                // One piece tells nothing the PNG doesn't.
                strokes[key].flatMap { $0.count > 1 ? StrokePieces.encode($0) : nil }
            })
            documentURL = url
            isDirty = false
        } catch {
            lastError = String(localized: "Couldn't save \(url.lastPathComponent).\n\(error.localizedDescription)", bundle: AppLanguage.bundle)
        }
    }

    /// Swaps in a project and its pixels, recreating the renderer if the canvas size changed.
    private func install(_ newProject: Project, images: [LayerKey: CGImage],
                         strokes loadedStrokes: [LayerKey: [StrokePiece]] = [:]) throws {
        selection = nil; selectionBefore = nil; selectionPreview = nil; lassoPoints = []
        recipeStroke = nil; recipeScratch = nil; fillScratch = nil; smudgeScratch = nil; penEditing = nil; penBefore = nil
        strokes = loadedStrokes; movingPieces = nil; lastPick = nil; moveHint = nil; strokeTexture = nil; strokeBase = nil
        playRange = nil
        let size = SIMD2<Int>(newProject.canvas.width, newProject.canvas.height)
        if size != renderer.canvasSize {
            guard let r = CanvasRenderer(device: renderer.device, canvasSize: size, screenFormat: screenFormat) else {
                throw ProjectDocument.Error.invalidCanvas(newProject.canvas)
            }
            renderer = r
        }
        store = FrameStore(renderer: renderer)
        drawingThumbnails = [:]
        drawingThumbnailSource = [:]
        pendingThumbnails = [:]

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
        canvasTransform = CanvasTransform(insets: canvasTransform.insets)
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
        for f in frames { refreshThumbnail(for: f.id) }
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
    /// A frame as it exports: visible layers flattened, guides left out.
    func flattenedImage(clip: Clip, frameID: String) -> CGImage? {
        let layers = frameLayers(of: clip, frameID, opacity: 1, tint: nil, guides: false)
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
            lastError = String(localized: "Couldn't export \(project.name).\n\(error.localizedDescription)", bundle: AppLanguage.bundle)
            return nil
        }
    }

    /// What's worth fixing before exporting these clips (nil = all). Advice only.
    func exportChecks(clips: [String]?) -> [ExportChecks.Issue] {
        ExportChecks.run(project: project, clips: clips,
                         frameImage: { clip, frame in flattenedImage(clip: clip, frameID: frame.id) },
                         hiddenDrawing: { clip, layer in
                             clip.frames.contains { store.existingTexture(clip: clip.id, frame: $0.id, layer: layer.id) != nil }
                         })
    }

    /// Runs an export profile into `directory`/Exports/<project>/<profile>/ and returns the files
    /// written (for sharing), or nil after setting `lastError`.
    func export(_ profile: ExportProfile, in directory: URL = EditorState.documentsDirectory) -> [URL]? {
        stop()
        finishPen()
        commitSelection()
        let folder = directory
            .appendingPathComponent("Exports", isDirectory: true)
            .appendingPathComponent(project.name, isDirectory: true)
            .appendingPathComponent(ProjectLibrary.cleanName(profile.name), isDirectory: true)
        let clips = project.clips.filter { profile.clips?.contains($0.id) ?? true }
        guard !clips.isEmpty else {
            lastError = String(localized: "\(profile.name) doesn't include any clip of \(project.name).", bundle: AppLanguage.bundle)
            return nil
        }
        do {
            try? FileManager.default.removeItem(at: folder)   // a profile's folder is always its latest run
            let urls: [URL]
            switch profile.target {
            case .spriteSheet:
                let sheet = SpriteSheet.build(project: project, options: profile.sheetOptions) { clip, frame in
                    flattenedImage(clip: clip, frameID: frame.id)
                }
                urls = try sheet.write(to: folder, baseName: project.name)
            case .godot:
                let sheet = SpriteSheet.build(project: project, options: profile.sheetOptions) { clip, frame in
                    flattenedImage(clip: clip, frameID: frame.id)
                }
                urls = try GodotExport.write(sheet, project: project, to: folder, baseName: project.name)
            case .gif:
                let canvas = CanvasSize(width: max(1, Int((Double(project.canvas.width) * profile.scale).rounded())),
                                        height: max(1, Int((Double(project.canvas.height) * profile.scale).rounded())))
                urls = try clips.map { clip in
                    let fps = Double(max(clip.fps ?? project.fps, 1))
                    let frames = clip.frames.map { f in
                        GIFExport.Frame(image: flattenedImage(clip: clip, frameID: f.id).flatMap { ImageScaling.scale($0, by: profile.scale) },
                                        durationSeconds: Double(f.hold) / fps)
                    }
                    let url = folder.appendingPathComponent("\(project.name)-\(clip.id).gif")
                    try GIFExport.write(frames, canvas: canvas, loop: clip.loop, to: url)
                    return url
                }
            case .pngSequence:
                for clip in clips {
                    let clipFolder = folder.appendingPathComponent(clip.id, isDirectory: true)
                    var tick = 0
                    for f in clip.frames {
                        let image = flattenedImage(clip: clip, frameID: f.id).flatMap { ImageScaling.scale($0, by: profile.scale) }
                            ?? ImageScaling.blank(width: Int((Double(project.canvas.width) * profile.scale).rounded()),
                                                  height: Int((Double(project.canvas.height) * profile.scale).rounded()))
                        for _ in 0..<max(f.hold, 1) {
                            let url = clipFolder.appendingPathComponent(String(format: "%@_%03d.png", clip.id, tick))
                            if let image { try ImageScaling.writePNG(image, to: url) }
                            tick += 1
                        }
                    }
                }
                // A folder per clip, a file per tick: share the export folder itself.
                urls = [folder]
            }
            lastExportProfileID = profile.id
            return urls
        } catch {
            lastError = String(localized: "Couldn't export with \(profile.name).\n\(error.localizedDescription)", bundle: AppLanguage.bundle)
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
            lastError = String(localized: "Couldn't export \(url.lastPathComponent).\n\(error.localizedDescription)", bundle: AppLanguage.bundle)
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
                      held: layers.map(\.id).filter { clip.isHeld(layer: $0, at: frameIndex) },
                      links: src.links.filter { !clip.isHeld(layer: $0.key, at: frameIndex) })
        recordUndo(textures: allCellKeys() + layerKeys(clip, frame: f.id))
        let at = frameIndex + 1
        keepingPicture {
            clip.frames.insert(f, at: at)
            for l in layers where !f.held.contains(l.id) && f.links[l.id] == nil {
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
        clip.frames[frameIndex].links[l.id] = nil
        store.set(nil, for: own)
        isDirty = true
        refreshClipThumbnails()
    }

    /// Gives the current layer a drawing of its own here, blank or a copy of the one it was holding
    /// (or repeating, linked: unlinking keeps the picture and stops following the original).
    /// Later frames that were holding through here now hold this new drawing.
    func releaseCurrentCell(copying: Bool) {
        guard currentCellIsHeld || currentCellIsLinked, let l = currentLayer, !l.locked,
              let source = currentDrawingKey else { return }
        if currentCellIsLinked { frameIndex = clip.cellStart(layer: l.id, at: frameIndex) }
        guard let f = currentFrame else { return }
        let own = LayerKey(clip: clip.id, frame: f.id, layer: l.id)
        recordUndo(textures: [own])
        clip.frames[frameIndex].ownDrawing(l.id)
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
                clip.frames[i].links[layer] = nil
                clip.frames[i].labels[layer] = nil
                store.set(nil, for: own)
            } else {
                clip.frames[i].held.removeAll { $0 == layer }
            }
        }
        isDirty = true
        refreshClipThumbnails()
    }

    /// Makes the drawing that starts at frame `start` on `layer` last `ticks` ticks, pushing what
    /// comes after it: longer holds the drawing's last frame longer; shorter takes that time back,
    /// then drops frames of the drawing that nothing on any layer draws on. A frame where another
    /// layer has a drawing of its own stays, so it never eats a drawing. A drag is one undo step.
    func setDrawingDuration(layer: String, start: Int, ticks: Int) {
        guard frames.indices.contains(start), !clip.isHeld(layer: layer, at: start),
              layers.first(where: { $0.id == layer })?.locked == false,
              let run = clip.runs(of: layer).first(where: { $0.start == start }) else { return }
        var end = start + run.count - 1
        let current = frames[start...end].reduce(0) { $0 + $1.hold }
        let target = max(1, ticks)
        guard target != current else { return }
        recordUndo(coalescing: "duration:\(layer):\(frames[start].id)")
        let wasCurrent = currentFrame?.id
        if target > current {
            clip.frames[end].hold += target - current
        } else {
            var excess = current - target
            while excess > 0 {
                if clip.frames[end].hold > 1 {
                    let cut = min(excess, clip.frames[end].hold - 1)
                    clip.frames[end].hold -= cut
                    excess -= cut
                } else if end > start, layers.allSatisfy({ clip.frames[end].held.contains($0.id) }) {
                    excess -= clip.frames[end].hold
                    clip.frames.remove(at: end)
                    end -= 1
                } else {
                    break
                }
            }
        }
        frameIndex = wasCurrent.flatMap { id in frames.firstIndex { $0.id == id } } ?? start
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
                clip.frames[i].ownDrawing(l.id)
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

    /// Pixel art on or off for this project (hard-edged brush, eraser, fill and lasso). Undoable.
    func setPixelArt(_ on: Bool) {
        guard project.pixelArt != on else { return }
        recordUndo()
        project.pixelArt = on
        isDirty = true
    }

    // MARK: - Drawings (the bar's add / duplicate / delete)

    // The bar acts on the current layer's drawing, like RoughAnimator's "Independent" timing: other
    // layers keep showing what they showed. With Sync layers on it acts on whole frames instead.

    /// Which of the current layer's drawings the playhead is on, counting from 1.
    var currentDrawingNumber: Int? {
        guard let l = currentLayer, frames.indices.contains(frameIndex) else { return nil }
        let src = clip.sourceIndex(layer: l.id, at: frameIndex)
        return clip.runs(of: l.id).firstIndex { $0.start == src }.map { $0 + 1 }
    }

    /// A new blank drawing after the playhead: on the current layer (others hold), or on every layer.
    func addDrawing() {
        if syncLayers { addBlankFrame() } else { addFrame() }
    }

    /// A new frame after the playhead with a blank drawing on every layer.
    func addBlankFrame() {
        let id = newFrameID()
        recordUndo(textures: allCellKeys() + layerKeys(clip, frame: id))
        keepingPicture { insertBlankFrame(id: id) }
        refreshClipThumbnails()
    }

    /// Copies the current layer's drawing into a new frame after the playhead; other layers hold.
    /// With Sync layers on, copies the whole frame.
    func duplicateDrawing() {
        guard !syncLayers else { duplicateFrame(); return }
        guard let l = currentLayer, !l.locked, let src = currentFrame, let source = currentDrawingKey else { return }
        let f = Frame(id: newFrameID(), hold: src.hold, held: layers.map(\.id).filter { $0 != l.id })
        recordUndo(textures: allCellKeys() + layerKeys(clip, frame: f.id))
        let copy = store.copy(of: source)
        let label = drawingLabel(layer: l.id, at: frameIndex)
        let at = frameIndex + 1
        keepingPicture { clip.frames.insert(f, at: at) }
        store.set(copy, for: LayerKey(clip: clip.id, frame: f.id, layer: l.id))
        clip.frames[at].labels[l.id] = label
        frameIndex = at
        isDirty = true
        refreshClipThumbnails()
    }

    /// Whether the current layer's drawing at the playhead lasts long enough (2 ticks or more) to split.
    var canSplitCurrentDrawing: Bool {
        guard let l = currentLayer, !l.locked, frames.indices.contains(frameIndex) else { return false }
        let cell = clip.cellStart(layer: l.id, at: frameIndex)
        guard let run = clip.runs(of: l.id).first(where: { $0.start == cell }) else { return false }
        return frames[cell..<(cell + run.count)].reduce(0) { $0 + $1.hold } >= 2
    }

    /// Splits the current layer's drawing at the playhead halfway through its time: the second half
    /// becomes a new drawing, blank (an inbetween to draw) or a copy (duplicate split). The clip's
    /// length and every other layer stay as they were. The first half keeps the extra tick of an
    /// odd length.
    func splitCurrentDrawing(copying: Bool) {
        guard canSplitCurrentDrawing, let l = currentLayer, let source = currentDrawingKey else { return }
        let cell = clip.cellStart(layer: l.id, at: frameIndex)
        guard let run = clip.runs(of: l.id).first(where: { $0.start == cell }) else { return }
        let total = frames[cell..<(cell + run.count)].reduce(0) { $0 + $1.hold }
        let firstHalf = (total + 1) / 2
        recordUndo(textures: allCellKeys())
        let copy = copying ? store.copy(of: source) : nil

        // Find where the second half starts; cut a frame in two if the middle falls inside it.
        var ticks = 0, boundary = cell + run.count
        for c in cell..<(cell + run.count) {
            let hold = clip.frames[c].hold
            if ticks + hold > firstHalf {
                let a = firstHalf - ticks
                clip.frames[c].hold = a
                // The cut-off part shows exactly what the frame showed: every layer holds.
                clip.frames.insert(Frame(id: newFrameID(), hold: hold - a, held: layers.map(\.id)), at: c + 1)
                boundary = c + 1
                break
            }
            ticks += hold
            if ticks == firstHalf { boundary = c + 1; break }
        }
        clip.frames[boundary].ownDrawing(l.id)
        store.set(copy, for: LayerKey(clip: clip.id, frame: frames[boundary].id, layer: l.id))
        frameIndex = boundary
        isDirty = true
        refreshClipThumbnails()
    }

    /// How many drawings the current layer has up to and including the one at the playhead: the
    /// most a cycle can repeat.
    var drawingsUpToPlayhead: Int {
        guard let l = currentLayer, frames.indices.contains(frameIndex) else { return 0 }
        let cell = clip.cellStart(layer: l.id, at: frameIndex)
        return (clip.runs(of: l.id).firstIndex { $0.start == cell } ?? -1) + 1
    }

    /// A cycle: right after the drawing at the playhead, repeats the current layer's last `count`
    /// drawings (that one included), linked and with the same timing, so changing a drawing changes
    /// every repeat. Other layers carry on with what they show. With Sync layers on, the frames
    /// those drawings span repeat on every layer.
    func repeatDrawings(count: Int) {
        guard let l = currentLayer, !l.locked, frames.indices.contains(frameIndex) else { return }
        let runs = clip.runs(of: l.id)
        let cell = clip.cellStart(layer: l.id, at: frameIndex)
        guard let r = runs.firstIndex(where: { $0.start == cell }) else { return }
        let n = min(max(1, count), r + 1)
        let first = runs[r - n + 1].start, end = runs[r].start + runs[r].count     // source frames first..<end
        let ids = layers.map(\.id)

        var repeats: [Frame] = []
        for c in first..<end {
            var f = Frame(id: newFrameID(), hold: frames[c].hold)
            for layer in ids where syncLayers || layer == l.id {
                // The first repeated frame links every layer it covers, so a layer held there
                // shows the drawing it was holding, not whatever came just before the repeat.
                if c > first && clip.isHeld(layer: layer, at: c) { f.held.append(layer) }
                else { f.links[layer] = frames[clip.sourceIndex(layer: layer, at: c)].id }
            }
            if !syncLayers { f.held += ids.filter { $0 != l.id } }
            repeats.append(f)
        }
        recordUndo(textures: allCellKeys())
        keepingPicture { clip.frames.insert(contentsOf: repeats, at: end) }
        frameIndex = end
        isDirty = true
        refreshClipThumbnails()
    }

    /// Removes the current layer's drawing at the playhead: the drawing before it stays on screen
    /// in its place (on the first frame the layer is left blank). Other layers don't change. A frame
    /// left with no drawing of its own on any layer goes away, so the clip gets shorter.
    /// With Sync layers on, deletes the whole frame.
    func deleteDrawing() {
        guard !syncLayers else { deleteFrame(); return }
        guard let l = currentLayer, !l.locked, frames.indices.contains(frameIndex) else { return }
        // A linked repeat is its own cell: deleting it removes the repeat, never the original.
        let cell = clip.cellStart(layer: l.id, at: frameIndex)
        let src = clip.isLinked(layer: l.id, at: cell) ? cell : clip.sourceIndex(layer: l.id, at: frameIndex)
        recordUndo(textures: allCellKeys())
        clip.frames[src].links[l.id] = nil
        store.set(nil, for: LayerKey(clip: clip.id, frame: frames[src].id, layer: l.id))
        clip.frames[src].labels[l.id] = nil
        if src > 0 {
            clip.frames[src].held.append(l.id)
            if layers.allSatisfy({ clip.frames[src].held.contains($0.id) }) {
                clip.frames.remove(at: src)
                if frameIndex >= src { frameIndex -= 1 }
            }
        }
        isDirty = true
        refreshClipThumbnails()
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
        for i in clip.frames.indices { clip.frames[i].ownDrawing(doomed.id) }
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

    /// Masks the layer to the one below (it only shows where that one has paint), or un-masks it.
    /// The bottom layer has nothing below, so it can't be masked.
    func toggleLayerMask(_ index: Int) {
        guard layers.indices.contains(index), index > 0 || layers[index].maskBelow else { return }
        recordUndo()
        clip.layers[index].maskBelow.toggle()
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

    /// A blank layer just below the current one, with the same drawings-and-holds timing: a colour
    /// pass under line art, one empty drawing per line drawing. Becomes the current layer.
    func addLayerMatchingTiming() {
        guard let src = currentLayer else { return }
        recordUndo()
        let name = uniqueLayerName(String(localized: "\(src.name) color", bundle: AppLanguage.bundle))
        let layer = Layer(id: Self.clipID(for: name, existing: layers.map(\.id)), name: name)
        let at = layerIndex
        clip.layers.insert(layer, at: at)
        for i in clip.frames.indices where clip.frames[i].held.contains(src.id) { clip.frames[i].held.append(layer.id) }
        layerIndex = at
        isDirty = true
    }

    /// An image to draw over, as a new layer under all the others: fitted to the canvas without
    /// distortion, one drawing held through the whole clip, at 40 %, locked and marked as a guide
    /// (never exported). Every one of those can be changed afterwards. One undo step.
    func importImageLayer(_ image: CGImage, name: String? = nil) {
        guard !frames.isEmpty else { return }
        let w = renderer.canvasSize.x, h = renderer.canvasSize.y
        let layerName = uniqueLayerName(name.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "Reference", bundle: AppLanguage.bundle))
        let layer = Layer(id: Self.clipID(for: layerName, existing: layers.map(\.id)), name: layerName,
                          opacity: 0.4, locked: true, guide: true)
        let key = LayerKey(clip: clip.id, frame: frames[0].id, layer: layer.id)
        recordUndo(textures: [key])
        clip.layers.insert(layer, at: 0)
        for i in clip.frames.indices.dropFirst() { clip.frames[i].held.append(layer.id) }
        layerIndex += 1                                     // the layer you were drawing on stays current
        if let target = store.texture(clip: key.clip, frame: key.frame, layer: key.layer) {
            renderer.upload(bytes: Self.fitted(image, width: w, height: h, hard: project.pixelArt), into: target)
        }
        isDirty = true
        refreshClipThumbnails()
    }

    /// `image` scaled to fit a `width` x `height` canvas and centred, as premultiplied RGBA with row 0
    /// at the top, like layer textures. `hard` keeps pixels sharp (pixel art).
    static func fitted(_ image: CGImage, width: Int, height: Int, hard: Bool = false) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: width * height * 4)
        let s = min(Double(width) / Double(image.width), Double(height) / Double(image.height))
        let w = Double(image.width) * s, h = Double(image.height) * s
        out.withUnsafeMutableBytes { ptr in
            guard let ctx = CGContext(data: ptr.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.interpolationQuality = hard ? .none : .high
            // CoreGraphics draws bottom-up, which in memory lands the image's top row at the top.
            ctx.draw(image, in: CGRect(x: (Double(width) - w) / 2, y: (Double(height) - h) / 2, width: w, height: h))
        }
        return out
    }

    /// Guide (shown, not exported) or part of the sprite. Undoable.
    func toggleLayerGuide(_ index: Int) {
        guard layers.indices.contains(index) else { return }
        recordUndo()
        clip.layers[index].guide.toggle()
        isDirty = true
    }

    /// A copy of the current layer, drawings, holds and labels included, just above it.
    func duplicateCurrentLayer() {
        guard let src = currentLayer else { return }
        let name = uniqueLayerName(String(localized: "\(src.name) copy", bundle: AppLanguage.bundle))
        let layer = Layer(id: Self.clipID(for: name, existing: layers.map(\.id)), name: name,
                          opacity: src.opacity, visible: src.visible)
        recordUndo(textures: frames.map { LayerKey(clip: clip.id, frame: $0.id, layer: layer.id) })
        let at = layerIndex + 1
        clip.layers.insert(layer, at: at)
        for i in clip.frames.indices {
            let f = clip.frames[i]
            if f.held.contains(src.id) { clip.frames[i].held.append(layer.id); continue }
            if let link = f.links[src.id] { clip.frames[i].links[layer.id] = link; continue }
            clip.frames[i].labels[layer.id] = f.labels[src.id]
            store.set(store.copy(of: LayerKey(clip: clip.id, frame: f.id, layer: src.id)),
                      for: LayerKey(clip: clip.id, frame: f.id, layer: layer.id))
        }
        layerIndex = at
        isDirty = true
        refreshClipThumbnails()
    }

    private func uniqueLayerName(_ base: String) -> String {
        guard layers.contains(where: { $0.name == base }) else { return base }
        var n = 2
        while layers.contains(where: { $0.name == "\(base) \(n)" }) { n += 1 }
        return "\(base) \(n)"
    }

    /// "Layer 3", "Layer 4"… for a layer made without a name dialog.
    func addLayerWithDefaultName() {
        var n = layers.count + 1
        while layers.contains(where: { $0.name == String(localized: "Layer \(n)", bundle: AppLanguage.bundle) }) { n += 1 }
        addLayer(name: String(localized: "Layer \(n)", bundle: AppLanguage.bundle))
    }

    // MARK: - Playback

    func togglePlayback() {
        finishPen()
        commitSelection()
        isPlaying ? stop() : play()
    }

    /// Frames playback runs over: the whole clip, or the in / out range when one is set.
    /// View state: not saved, and it never affects export.
    var playRange: ClosedRange<Int>?

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
            // Far ghosts first, so the nearest drawings sit on top.
            for k in stride(from: onion.before, through: 1, by: -1) {
                let fade = 1 - Float(k - 1) / Float(max(onion.before, 1)) * 0.6
                out += onionLayers(drawingsAway: -k, opacity: onion.opacity * fade, tint: onion.beforeTint)
            }
            for k in stride(from: onion.after, through: 1, by: -1) {
                let fade = 1 - Float(k - 1) / Float(max(onion.after, 1)) * 0.6
                out += onionLayers(drawingsAway: k, opacity: onion.opacity * fade, tint: onion.afterTint)
            }
        }
        if currentFrame != nil {
            let shown = Self.masked(clip.layers) { layer in
                drawingKey(layer: layer.id, at: frameIndex).flatMap { store.existingTexture(clip: $0.clip, frame: $0.frame, layer: $0.layer) }
            }
            for (layer, texture, mask) in shown {
                let key = drawingKey(layer: layer.id, at: frameIndex)
                if let texture {
                    out.append(.init(texture: texture, opacity: Float(layer.opacity), tint: .zero, tintAmount: 0, mask: mask))
                }
                // A floating selection shows right above its own layer, where it'll land.
                if let sel = selection, sel.key == key, let preview = selectionPreview {
                    out.append(.init(texture: preview, opacity: Float(layer.opacity), tint: .zero, tintAmount: 0, mask: mask))
                }
            }
        }
        return out
    }

    /// The visible layers of a stack (bottom to top) with what each shows through: a layer masked to
    /// the one below gets the nearest unmasked layer under it as its mask, and disappears when that
    /// base is hidden or has nothing drawn. The bottom layer is never masked.
    static func masked(_ layers: [Layer], texture: (Layer) -> MTLTexture?) -> [(Layer, MTLTexture?, MTLTexture?)] {
        var out: [(Layer, MTLTexture?, MTLTexture?)] = []
        var base: MTLTexture?
        var baseShown = false
        for (i, layer) in layers.enumerated() {
            if i == 0 || !layer.maskBelow {
                base = texture(layer)
                baseShown = layer.visible
                if layer.visible { out.append((layer, base, nil)) }
            } else if layer.visible, baseShown, let base {
                out.append((layer, texture(layer), base))
            }
        }
        return out
    }

    /// Onion skin counts drawings, not frames, on each layer: `offset` -1 is the drawing before the
    /// one on screen (however long it's held), +1 the next. Blank drawings are skipped, so an empty
    /// frame or a hold doesn't hide the pose you're tracing. A layer whose drawing doesn't change
    /// (a held background) has nothing to ghost.
    private func onionLayers(drawingsAway offset: Int, opacity: Float, tint: SIMD3<Float>) -> [CanvasRenderer.CompositeLayer] {
        let ghosted = onion.currentLayerOnly ? (currentLayer.map { [$0] } ?? []) : clip.layers
        return ghosted.compactMap { layer in
            guard layer.visible, let t = onionTexture(layer: layer.id, drawingsAway: offset) else { return nil }
            return .init(texture: t, opacity: Float(layer.opacity) * opacity, tint: tint, tintAmount: 1)
        }
    }

    private func onionTexture(layer: String, drawingsAway offset: Int) -> MTLTexture? {
        guard offset != 0, frames.indices.contains(frameIndex) else { return nil }
        let current = clip.cellStart(layer: layer, at: frameIndex)
        func texture(_ start: Int) -> MTLTexture? {
            drawingKey(layer: layer, at: start).flatMap { store.existingTexture(clip: $0.clip, frame: $0.frame, layer: $0.layer) }
        }
        let onScreen = texture(current)
        let drawn = clip.runs(of: layer).map(\.start).filter { $0 == current || texture($0) != nil }
        guard let here = drawn.firstIndex(of: current) else { return nil }
        let i = here + offset
        guard drawn.indices.contains(i), let t = texture(drawn[i]), t !== onScreen else { return nil }
        return t
    }

    private func frameLayers(_ frameID: String, opacity: Float, tint: SIMD3<Float>?,
                             guides: Bool = true) -> [CanvasRenderer.CompositeLayer] {
        frameLayers(of: clip, frameID, opacity: opacity, tint: tint, guides: guides)
    }

    /// Every visible layer as it shows at frame `frameID` of `clip`, holds resolved.
    /// `guides: false` leaves guide layers out, as exports and the fill's outline do.
    private func frameLayers(of clip: Clip, _ frameID: String, opacity: Float, tint: SIMD3<Float>?,
                             guides: Bool = true) -> [CanvasRenderer.CompositeLayer] {
        let index = clip.frames.firstIndex { $0.id == frameID }
        let shown = Self.masked(guides ? clip.layers : clip.layers.filter { !$0.guide }) { layer in
            let source = index.flatMap { clip.sourceFrameID(layer: layer.id, at: $0) } ?? frameID
            return store.existingTexture(clip: clip.id, frame: source, layer: layer.id)
        }
        return shown.compactMap { layer, texture, mask in
            texture.map {
                CanvasRenderer.CompositeLayer(texture: $0, opacity: Float(layer.opacity) * opacity,
                                              tint: tint ?? .zero, tintAmount: tint == nil ? 0 : 1, mask: mask)
            }
        }
    }

    // MARK: - Thumbnails

    /// Refreshes every frame of the current clip that shows drawing `key` (its own frame and the
    /// frames holding it).
    func refreshThumbnails(showing key: LayerKey) {
        // Its pixels changed in place: the texture is the same object, so say so.
        drawingThumbnailSource[key] = nil
        refreshThumbnail(for: key.frame)
    }

    /// Re-renders the cell previews of frame `frameID`'s own drawings that changed: a drawing
    /// whose texture is the same object as last time (and wasn't painted since) is skipped, so
    /// adding or moving frames doesn't redraw every preview.
    func refreshThumbnail(for frameID: String) {
        for layer in clip.layers {
            let key = LayerKey(clip: clip.id, frame: frameID, layer: layer.id)
            guard let texture = store.existingTexture(clip: key.clip, frame: key.frame, layer: key.layer) else {
                if drawingThumbnails[key] != nil { pendingThumbnails[key] = .some(nil); scheduleThumbnailFlush() }
                drawingThumbnailSource[key] = nil
                continue
            }
            let id = ObjectIdentifier(texture)
            if drawingThumbnailSource[key] == id, drawingThumbnails[key] != nil { continue }
            drawingThumbnailSource[key] = id
            renderer.thumbnail([.init(texture: texture, opacity: 1, tint: .zero, tintAmount: 0, mask: nil)],
                               maxSide: 96, checker: false) { [weak self] image in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.pendingThumbnails[key] = .some(image)
                    self.scheduleThumbnailFlush()
                }
            }
        }
    }

    /// Previews arrive one by one from the GPU; they're published together, once per run-loop
    /// turn, so the editor redraws once instead of once per preview.
    private func scheduleThumbnailFlush() {
        guard !thumbnailFlushScheduled else { return }
        thumbnailFlushScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.thumbnailFlushScheduled = false
            var next = self.drawingThumbnails
            for (k, v) in self.pendingThumbnails { next[k] = v }
            self.pendingThumbnails = [:]
            self.drawingThumbnails = next
        }
    }

    /// Keeps the layer's pixels aside and returns the texture to paint into, or nil if painting isn't allowed.
    /// The stroke becomes an undo step in `strokeEnded`; `cancelStroke` throws it away.
    func beginStroke() -> MTLTexture? {
        guard let key = currentDrawingKey, currentLayer?.locked == false else { return nil }
        var saved: [LayerKey: MTLTexture?] = [:]
        saved.updateValue(store.copy(of: key), forKey: key)
        pendingStroke = snapshot(saved)
        pendingStamps = []
        lastSmudgeDab = nil
        strokeBase = saved[key] ?? nil
        strokeTexture = strokeTexture ?? renderer.makeLayerTexture()
        if let strokeTexture { renderer.clear(strokeTexture) }
        return paintTarget
    }

    /// Paints part of the stroke in progress with the current tool and brush, and keeps its stamps.
    /// The stroke builds up on its own texture, then the layer is redrawn as it was plus the
    /// stroke, at the brush's opacity: so a marker stays even where it crosses itself.
    func paintStroke(_ stamps: [CanvasRenderer.Stamp], into target: MTLTexture) {
        pendingStamps += stamps
        if tool == .smudge { smudgeStroke(stamps, into: target); return }
        guard let strokeTexture else {
            renderer.paint(stamps, into: target, color: color, tool: tool, hard: project.pixelArt, mode: paintMode)
            return
        }
        let b = activeBrush
        renderer.paintStroke(stamps, into: strokeTexture, color: b.fixedColor ?? SIMD3(color.x, color.y, color.z),
                             tip: .init(b), hard: project.pixelArt)
        renderer.compositeStroke(strokeTexture, base: strokeBase, into: target,
                                 opacity: tool == .eraser ? 1 : brushOpacity, mode: paintMode, erase: tool == .eraser)
    }

    /// Smudge dabs straight on the layer, each knowing how far the finger moved before it.
    private func smudgeStroke(_ stamps: [CanvasRenderer.Stamp], into target: MTLTexture) {
        guard let first = stamps.first else { return }
        if smudgeScratch == nil { smudgeScratch = renderer.makeLayerTexture() }
        guard let scratch = smudgeScratch else { return }
        var last = lastSmudgeDab ?? first.position
        let deltas = stamps.map { s -> SIMD2<Float> in
            defer { last = s.position }
            return s.position - last
        }
        lastSmudgeDab = last
        renderer.smudge(stamps, deltas: deltas, in: target, scratch: scratch, mode: smudge.mode,
                        strength: smudge.strength, hardness: activeBrush.hardness)
    }

    /// The stroke that just ended on its own, as the layer got it (at the brush's opacity).
    private func strokeAlone() -> [UInt8]? {
        guard let strokeTexture, var px = renderer.readbackBytes(strokeTexture) else { return nil }
        let o = tool == .eraser ? 1 : brushOpacity
        if o < 1 { for i in px.indices { px[i] = UInt8(Float(px[i]) * o + 0.5) } }
        return px
    }

    func strokeEnded() {
        let key = pendingStroke?.textures.keys.first
        if let s = pendingStroke {
            coalesceTag = nil
            push(s)
            pendingStroke = nil
            if let key { recordPieces(key, before: s.textures[key] ?? nil) }
        }
        isDirty = true
        if let key { refreshThumbnails(showing: key) } else if let f = currentFrame { refreshThumbnail(for: f.id) }
    }

    /// A gesture took over (two-finger tap, pinch): put the pixels back as if the stroke never happened.
    func cancelStroke() {
        guard let s = pendingStroke else { return }
        pendingStroke = nil
        pendingStamps = []
        for (k, t) in s.textures { store.set(t, for: k); refreshThumbnails(showing: k) }
        canvasVersion &+= 1
    }

    // MARK: - Pieces

    /// Keeps the stroke that just ended as a piece of its drawing. A pencil stroke drawn in front
    /// becomes a new piece on top; the eraser trims the pieces it crosses; anything else (behind,
    /// inside, or paint we didn't see) means the pieces are no longer known.
    private func recordPieces(_ key: LayerKey, before: MTLTexture?) {
        let stamps = pendingStamps
        pendingStamps = []
        let w = renderer.canvasSize.x, h = renderer.canvasSize.y
        if let shape = pendingShape {
            // A shape is a piece of its own, painted again from its recipe wherever Move takes it.
            pendingShape = nil
            guard paintMode == .front else { strokes[key] = nil; return }
            var pieces = strokes[key] ?? before.flatMap { renderer.readbackBytes($0) }
                .map { StrokePieces.shapes(of: $0, width: w, height: h) } ?? []
            if let piece = paint(shape) { pieces.append(piece) }
            strokes[key] = pieces
            return
        }
        guard !stamps.isEmpty else { strokes[key] = nil; return }
        switch tool {
        case .brush where paintMode == .front:
            var pieces = strokes[key] ?? before.flatMap { renderer.readbackBytes($0) }
                .map { StrokePieces.shapes(of: $0, width: w, height: h) } ?? []
            if let alone = strokeAlone(), var piece = StrokePiece(canvas: alone, width: w, height: h) {
                let b = activeBrush
                piece.recipe = StrokeRecipe(stamps: stamps, color: b.fixedColor ?? SIMD3(color.x, color.y, color.z),
                                            tip: .init(b), opacity: brushOpacity, hard: project.pixelArt)
                pieces.append(piece)
            }
            strokes[key] = pieces
        case .eraser:
            guard let pieces = strokes[key], let cover = strokeAlone() else { return }
            let coverage = stride(from: 3, to: cover.count, by: 4).map { cover[$0] }
            strokes[key] = pieces.compactMap { $0.erased(by: coverage, canvasWidth: w) }
        default:
            strokes[key] = nil
        }
    }

    /// A stroke painted again from its recipe, on its own, as a piece; nil if it's off the canvas.
    private func paint(_ recipe: StrokeRecipe) -> StrokePiece? {
        guard let stroke = recipeTexture(\.recipeStroke), let out = recipeTexture(\.recipeScratch) else { return nil }
        paintRecipe(recipe, stroke: stroke, base: nil, into: out)
        let w = renderer.canvasSize.x, h = renderer.canvasSize.y
        guard let px = renderer.readbackBytes(out), var piece = StrokePiece(canvas: px, width: w, height: h) else { return nil }
        piece.recipe = recipe
        return piece
    }

    /// `recipe`'s stroke over `base` (nil = blank) into `target`, as the brush laid it.
    private func paintRecipe(_ recipe: StrokeRecipe, stroke: MTLTexture, base: MTLTexture?, into target: MTLTexture,
                             mode: CanvasRenderer.PaintMode = .front) {
        var base = base
        if let fill = recipe.fill, fill.count >= 3 {
            renderer.upload(bytes: Self.fillPixels(fill, color: recipe.fillColor, hard: recipe.hard,
                                                   width: renderer.canvasSize.x, height: renderer.canvasSize.y),
                            into: stroke)
            // An inside of its own colour goes down first and the line over it: in one texture
            // the two colours would mix where they meet. In the line's colour they're one shape.
            if recipe.fillColor != recipe.color, !recipe.stamps.isEmpty, let under = recipeTexture(\.fillScratch) {
                renderer.compositeStroke(stroke, base: base, into: under, opacity: recipe.opacity, mode: mode, erase: false)
                base = under
                renderer.clear(stroke)
            }
        } else {
            renderer.clear(stroke)
        }
        renderer.paintStroke(recipe.stamps, into: stroke, color: recipe.color, tip: recipe.tip, hard: recipe.hard)
        renderer.compositeStroke(stroke, base: base, into: target, opacity: recipe.opacity, mode: mode, erase: false)
    }

    /// A shape's inside in one colour (premultiplied), the rest clear.
    private static func fillPixels(_ polygon: [SIMD2<Float>], color: SIMD3<Float>, hard: Bool,
                                   width w: Int, height h: Int) -> [UInt8] {
        let points = polygon.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
        let coverage = SelectionPixels.rasterize(points, width: w, height: h, hard: hard)
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let c = color * 255
        for i in coverage.indices where coverage[i] != 0 {
            let a = Float(coverage[i]) / 255
            px[i * 4] = UInt8(c.x * a + 0.5); px[i * 4 + 1] = UInt8(c.y * a + 0.5)
            px[i * 4 + 2] = UInt8(c.z * a + 0.5); px[i * 4 + 3] = coverage[i]
        }
        return px
    }

    // MARK: - Shapes

    /// The shape from `a` to `b` with the Shapes tool's options, as a stroke recipe in the current
    /// colour; nil when it's too small to draw.
    func shapeRecipe(from a: CGPoint, to b: CGPoint) -> StrokeRecipe? {
        guard hypot(b.x - a.x, b.y - a.y) >= 2 else { return nil }
        let o = shapeOptions
        // Kept as a Pen path too, so the Pen and the Node tool can edit it point by point later.
        return recipe(outline: ShapeGeometry.paths(o, from: a, to: b), fill: ShapeGeometry.fillPolygon(o, from: a, to: b),
                      hasInside: o.canFill, pen: ShapeGeometry.penPath(o, from: a, to: b))
    }

    /// An outline and its inside, with the Shapes tool's style, in the current colour.
    private func recipe(outline paths: [(points: [CGPoint], closed: Bool)], fill polygon: [CGPoint]?, hasInside: Bool,
                        pen: PenPath? = nil, ink: SIMD3<Float>? = nil) -> StrokeRecipe? {
        let o = shapeOptions
        let brush = o.useBrush ? self.brush : .inker
        let outline = o.fill == .only && hasInside ? []
            : ShapeGeometry.stamps(along: paths, radius: o.size, spacing: brush.spacing, outline: o.outline, alpha: brush.flow)
        let fill = o.fill == .none || !hasInside ? nil : polygon?.map { SIMD2(Float($0.x), Float($0.y)) }
        guard !outline.isEmpty || fill != nil else { return nil }
        return StrokeRecipe(stamps: outline, color: brush.fixedColor ?? ink ?? SIMD3(color.x, color.y, color.z),
                            tip: .init(brush), opacity: o.useBrush ? brushOpacity : 1, hard: project.pixelArt, fill: fill,
                            pen: pen.map { PenDrawing(path: $0, style: o) })
    }

    /// Paints the shape from `a` to `b` on the drawing at the playhead: one undo step, and a piece
    /// Move picks with one tap and keeps sharp.
    func drawShape(from a: CGPoint, to b: CGPoint) {
        shapeDraft = nil
        guard let recipe = shapeRecipe(from: a, to: b), let target = beginStroke(), let stroke = strokeTexture else { return }
        paintRecipe(recipe, stroke: stroke, base: strokeBase, into: target, mode: paintMode)
        pendingShape = recipe
        strokeEnded()
    }

    // MARK: - Pen

    /// A finger (or the Pencil) down with the Pen, at canvas point `p`; `tolerance` is how near, in
    /// canvas pixels, counts as on a point or the line. Picks a handle or a point, adds a point on
    /// the line, closes the path on its first point, or adds a point at the end. With no path open,
    /// a touch on a Pen path in the drawing opens it for editing; anywhere else starts a new one.
    func penTouchDown(at p: CGPoint, tolerance tol: CGFloat) -> PenGrab? {
        guard !isPlaying, let key = currentDrawingKey, currentLayer?.locked == false else { return nil }
        if var e = penEditing, e.key == key {
            if let s = e.selected, e.path.nodes.indices.contains(s) {
                let n = e.path.nodes[s]
                if let h = n.handleOut, PenPath.distance(h, p) < tol { return .handle(s, outgoing: true) }
                if let h = n.handleIn, PenPath.distance(h, p) < tol { return .handle(s, outgoing: false) }
            }
            let near = e.path.nodes.indices.min { PenPath.distance(e.path.nodes[$0].point, p) < PenPath.distance(e.path.nodes[$1].point, p) }
            if let i = near, PenPath.distance(e.path.nodes[i].point, p) < tol {
                e.selected = i
                penEditing = e
                return .node(i)
            }
            if let n = e.path.nearest(to: p), n.distance < tol * 0.8 {
                let i = e.path.insert(onSegment: n.segment, at: n.t)
                e.selected = i
                penEditing = e
                return .node(i)
            }
            if !e.path.closed {
                e.path.nodes.append(.init(point: p))
                e.selected = e.path.nodes.count - 1
                penEditing = e
                return .newNode(e.path.nodes.count - 1)
            }
            // A closed path is done: a touch elsewhere puts it down and carries on below.
            finishPen()
        } else if penEditing != nil {
            finishPen()
        }
        if let (index, drawing) = penPiece(at: p, tolerance: tol, key: key) {
            openPen(piece: index, drawing: drawing, key: key)
            return nil
        }
        commitSelection()
        penEditing = PenEditing(path: PenPath(nodes: [.init(point: p)]), selected: 0, key: key,
                                ink: SIMD3(color.x, color.y, color.z))
        return .newNode(0)
    }

    /// The grabbed point or handle dragged to `p`; a point just placed pulls out its handles.
    func penDrag(_ grab: PenGrab, to p: CGPoint, tolerance tol: CGFloat) {
        guard var e = penEditing else { return }
        switch grab {
        case .node(let i) where e.path.nodes.indices.contains(i):
            e.path.move(node: i, to: p)
        case .handle(let i, let outgoing) where e.path.nodes.indices.contains(i):
            e.path.setHandle(of: i, outgoing: outgoing, to: p)
        case .newNode(let i) where e.path.nodes.indices.contains(i):
            if PenPath.distance(e.path.nodes[i].point, p) > tol * 0.3 { e.path.pullHandles(of: i, to: p) }
        default:
            return
        }
        penEditing = e
    }

    /// The finger lifted: a tap on the first point closes the path.
    func penTouchUp(_ grab: PenGrab, moved: Bool) {
        guard var e = penEditing, !moved, case .node(0) = grab, !e.path.closed, e.path.nodes.count >= 3 else { return }
        e.path.closed = true
        penEditing = e
    }

    /// The picked points as corners (straight sides) or curves.
    func penSetCurve(_ curve: Bool) {
        guard var e = penEditing, !e.picked.isEmpty else { return }
        for i in e.picked.sorted() where e.path.nodes.indices.contains(i) { e.path.setCurve(curve, at: i) }
        penEditing = e
    }

    func penToggleClosed() {
        guard var e = penEditing, e.path.nodes.count >= 3 || e.path.closed else { return }
        e.path.closed.toggle()
        penEditing = e
    }

    func penDeleteSelected() {
        guard var e = penEditing, let first = e.picked.min() else { return }
        for i in e.picked.sorted(by: >) where e.path.nodes.indices.contains(i) { e.path.nodes.remove(at: i) }
        if e.path.nodes.count < 3 { e.path.closed = false }
        e.selected = e.path.nodes.isEmpty ? nil : min(first, e.path.nodes.count - 1)
        if e.path.nodes.isEmpty { cancelPen() } else { penEditing = e }
    }

    // MARK: - Node tool

    /// What a finger grabbed with the Node tool: the picked points (dragged together), a handle,
    /// or empty canvas (dragging draws a box that picks the points inside it).
    enum NodeGrab: Equatable { case nodes, handle(Int, outgoing: Bool), marquee(CGPoint), nothing }
    /// The box being dragged out with the Node tool (canvas pixels).
    private(set) var nodeMarquee: CGRect?
    @ObservationIgnored private var nodeDragFrom: CGPoint = .zero
    @ObservationIgnored private var lastNodeTap: (index: Int, time: TimeInterval)?

    /// A touch with the Node tool. It only edits the points there are, never adds one (that's the
    /// Pen's): on a point it picks it (a second tap soon after turns it into a corner or a curve),
    /// on a path or a shape in the drawing it opens it; anywhere else, the line of the open path
    /// included, it starts a box to pick points with.
    func nodeTouchDown(at p: CGPoint, tolerance tol: CGFloat, time: TimeInterval) -> NodeGrab {
        guard !isPlaying, let key = currentDrawingKey, currentLayer?.locked == false else { return .nothing }
        nodeDragFrom = p
        if var e = penEditing, e.key == key {
            if let s = e.selected, e.path.nodes.indices.contains(s) {
                let n = e.path.nodes[s]
                if let h = n.handleOut, PenPath.distance(h, p) < tol { return .handle(s, outgoing: true) }
                if let h = n.handleIn, PenPath.distance(h, p) < tol { return .handle(s, outgoing: false) }
            }
            let near = e.path.nodes.indices.min { PenPath.distance(e.path.nodes[$0].point, p) < PenPath.distance(e.path.nodes[$1].point, p) }
            if let i = near, PenPath.distance(e.path.nodes[i].point, p) < tol {
                if let last = lastNodeTap, last.index == i, time - last.time < 0.35 {
                    e.path.setCurve(!e.path.nodes[i].isCurve, at: i)
                    lastNodeTap = nil
                } else {
                    lastNodeTap = (i, time)
                }
                // A point already in the picked group drags the group; any other is picked alone.
                if !e.picked.contains(i) { e.selected = i }
                penEditing = e
                return .nodes
            }
            if let n = e.path.nearest(to: p), n.distance < tol { return .marquee(p) }
            if penPiece(at: p, tolerance: tol, key: key) == nil { return .marquee(p) }
            finishPen()
        } else if penEditing != nil {
            finishPen()
        }
        if let (index, drawing) = penPiece(at: p, tolerance: tol, key: key) {
            openPen(piece: index, drawing: drawing, key: key)
        }
        return .nothing
    }

    /// A pinch or a pan took the touch over: no box.
    func nodeTouchCancelled() { nodeMarquee = nil }

    func nodeDrag(_ grab: NodeGrab, to p: CGPoint) {
        switch grab {
        case .nodes:
            guard var e = penEditing else { return }
            let d = CGPoint(x: p.x - nodeDragFrom.x, y: p.y - nodeDragFrom.y)
            for i in e.picked where e.path.nodes.indices.contains(i) {
                let q = e.path.nodes[i].point
                e.path.move(node: i, to: CGPoint(x: q.x + d.x, y: q.y + d.y))
            }
            nodeDragFrom = p
            penEditing = e
        case .handle(let i, let outgoing):
            guard var e = penEditing, e.path.nodes.indices.contains(i) else { return }
            e.path.setHandle(of: i, outgoing: outgoing, to: p)
            penEditing = e
        case .marquee(let start):
            nodeMarquee = CGRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(p.x - start.x), height: abs(p.y - start.y))
        case .nothing:
            break
        }
    }

    /// The finger lifted: a box picks the points inside it; a tap on empty canvas lets go of the
    /// picked points, and with none picked puts the path down.
    func nodeTouchUp(_ grab: NodeGrab, moved: Bool) {
        guard case .marquee = grab else { return }
        defer { nodeMarquee = nil }
        guard var e = penEditing else { return }
        if moved, let box = nodeMarquee {
            e.picked = Set(e.path.nodes.indices.filter { box.contains(e.path.nodes[$0].point) })
            penEditing = e
        } else if !e.picked.isEmpty {
            e.picked = []
            penEditing = e
        } else {
            finishPen()
        }
    }

    /// Paints the path: a new one as one undo step, an edited one in place of what it was. Each
    /// stays a piece that keeps its points, to edit again.
    func finishPen() {
        guard let e = penEditing else { return }
        penEditing = nil
        let path = e.path
        let line = path.polyline(step: 1.5)
        let recipe = path.nodes.count >= 2
            ? recipe(outline: [(line, path.closed)], fill: path.closed ? line : nil, hasInside: path.closed, pen: path,
                     ink: e.ink)
            : nil
        if let index = e.piece {
            // Back in its place among the drawing's pieces, as one undo step from before it opened.
            defer { penBefore = nil }
            guard let target = store.texture(clip: e.key.clip, frame: e.key.frame, layer: e.key.layer),
                  var pieces = strokes[e.key], pieces.indices.contains(index) else { return }
            var before: [LayerKey: MTLTexture?] = [:]
            before.updateValue(penBefore, forKey: e.key)
            coalesceTag = nil
            push(snapshot(before))
            if let recipe, let piece = paint(recipe) { pieces[index] = piece } else { pieces.remove(at: index) }
            strokes[e.key] = pieces
            renderer.upload(bytes: StrokePieces.composite(pieces, width: renderer.canvasSize.x, height: renderer.canvasSize.y),
                            into: target)
            isDirty = true
            refreshThumbnails(showing: e.key)
            return
        }
        guard let recipe, e.key == currentDrawingKey, let target = beginStroke(), let stroke = strokeTexture else { return }
        paintRecipe(recipe, stroke: stroke, base: strokeBase, into: target, mode: paintMode)
        pendingShape = recipe
        strokeEnded()
    }

    /// Leaves the drawing as it was before the path was opened (or started).
    func cancelPen() {
        guard let e = penEditing else { return }
        penEditing = nil
        if e.piece != nil, let before = penBefore { store.set(before, for: e.key) }
        penBefore = nil
        refreshThumbnails(showing: e.key)
        canvasVersion &+= 1
    }

    /// The topmost Pen path in the drawing under `p` (on its line, or inside it when filled).
    private func penPiece(at p: CGPoint, tolerance tol: CGFloat, key: LayerKey) -> (Int, PenDrawing)? {
        guard let t = store.existingTexture(clip: key.clip, frame: key.frame, layer: key.layer),
              let pixels = renderer.readbackBytes(t) else { return nil }
        let pieces = currentPieces(key, pixels: pixels)
        for i in pieces.indices.reversed() {
            guard let d = pieces[i].recipe?.pen else { continue }
            if let n = d.path.nearest(to: p), n.distance < tol + CGFloat(d.style.size) { return (i, d) }
            if d.path.closed, d.style.fill != .none {
                let shape = CGMutablePath()
                shape.addLines(between: d.path.polyline())
                shape.closeSubpath()
                if shape.contains(p) { return (i, d) }
            }
        }
        return nil
    }

    /// Opens a path in the drawing to edit: its style becomes the Pen's, and it's taken off the
    /// drawing (shown by the overlay) until it's finished.
    private func openPen(piece index: Int, drawing: PenDrawing, key: LayerKey) {
        guard let target = store.texture(clip: key.clip, frame: key.frame, layer: key.layer),
              let pieces = strokes[key], pieces.indices.contains(index) else { return }
        commitSelection()
        var style = shapeOptions
        style.outline = drawing.style.outline
        style.fill = drawing.style.fill
        style.size = min(max(drawing.style.size.rounded(), Self.sizeRange.lowerBound), Self.sizeRange.upperBound)
        style.useBrush = drawing.style.useBrush
        style.fillColor = drawing.style.fillColor
        shapeOptions = style
        penBefore = store.copy(of: key)
        let others = pieces.indices.filter { $0 != index }.map { pieces[$0] }
        renderer.upload(bytes: StrokePieces.composite(others, width: renderer.canvasSize.x, height: renderer.canvasSize.y),
                        into: target)
        // Its colour too, so the bar shows it and a new colour goes to it.
        let ink = pieces[index].recipe?.color ?? SIMD3(color.x, color.y, color.z)
        color = SIMD4(ink, 1)
        penEditing = PenEditing(path: drawing.path, selected: nil, key: key, piece: index, ink: ink)
        canvasVersion &+= 1
    }

    private func recipeTexture(_ slot: ReferenceWritableKeyPath<EditorState, MTLTexture?>) -> MTLTexture? {
        if self[keyPath: slot] == nil { self[keyPath: slot] = renderer.makeLayerTexture() }
        return self[keyPath: slot]
    }

    /// The drawing's pieces, checked against its pixels: if they no longer add up (it was filled,
    /// lassoed, restored…), it's split into its shapes again.
    private func currentPieces(_ key: LayerKey, pixels: [UInt8]) -> [StrokePiece] {
        let w = renderer.canvasSize.x, h = renderer.canvasSize.y
        if let p = strokes[key], StrokePieces.match(StrokePieces.composite(p, width: w, height: h), pixels) { return p }
        let p = StrokePieces.shapes(of: pixels, width: w, height: h)
        strokes[key] = p
        return p
    }

    // MARK: - Fill and eyedropper

    enum FillGaps: Int, CaseIterable, Identifiable {
        case off, small, medium, large
        var id: Int { rawValue }
        var title: String {
            [String(localized: "Off", bundle: AppLanguage.bundle), String(localized: "Small", bundle: AppLanguage.bundle), String(localized: "Medium", bundle: AppLanguage.bundle), String(localized: "Large", bundle: AppLanguage.bundle)][rawValue]
        }

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
              let seen = renderer.flattenBytes(frameLayers(f.id, opacity: 1, tint: nil, guides: false)) else { return }
        let region = FloodFill.region(in: seen, width: w, height: h, seed: seed, tolerance: Self.fillTolerance,
                                      closingGaps: fillGaps.radius(forCanvasSide: max(w, h)))
        guard !region.isEmpty else { return }
        // Pixel-art lines are hard, so there's no soft edge to slide under (it would eat the line).
        let mask = FloodFill.grow(region, width: w, height: h, by: project.pixelArt ? 0 : Self.fillGrow)

        recordUndo(textures: [key], copyPixels: true)
        guard let target = store.texture(clip: key.clip, frame: key.frame, layer: key.layer),
              var pixels = renderer.readbackBytes(target) else { return }
        FloodFill.paint(mask, color: SIMD3(color.x, color.y, color.z), into: &pixels, mode: paintMode)
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
        let bounds = Self.boundingBox(polygon).intersection(CGRect(x: 0, y: 0, width: w, height: h))
        lift(pixels, mask: SelectionPixels.rasterize(polygon, width: w, height: h, hard: project.pixelArt),
             outline: polygon, bounds: bounds, key: key, target: target)
    }

    /// Splits `mask` off the layer's pixels into a floating selection; nothing if it holds no paint.
    private func lift(_ pixels: [UInt8], mask: [UInt8], outline: [CGPoint], bounds: CGRect, key: LayerKey, target: MTLTexture) {
        let (lifted, remaining) = SelectionPixels.split(pixels, mask: mask)
        guard !SelectionPixels.isEmpty(lifted) else { return }
        selectionBefore = store.copy(of: key)
        selectionIsLift = true
        movingPieces = nil
        renderer.upload(bytes: remaining, into: target)
        selectionPreview = selectionPreview ?? renderer.makeLayerTexture()
        selection = FloatingSelection(key: key, lifted: lifted, outline: outline, bounds: bounds,
                                      anchor: CGPoint(x: bounds.midX, y: bounds.midY))
        renderSelectionPreview()
    }

    // MARK: - Move

    /// Move: lifts the current layer's drawing at the playhead, all of it or (with `point`) the
    /// piece under it (a stroke, or a shape), boxed tight. Tapping the same spot again picks the
    /// piece underneath; with `addingStrokes`, taps add pieces or take them out. A locked layer
    /// lifts nothing and sets `moveBlockedLayer`, so the editor can offer to unlock it.
    func liftForMove(at point: CGPoint? = nil) {
        finishPen()
        let previous = movingPieces
        lassoPoints = []
        commitSelection()
        moveBlockedLayer = nil
        moveHint = nil
        guard !isPlaying, let layer = currentLayer, let key = currentDrawingKey else { return }
        if layer.locked { moveBlockedLayer = layer.id; return }
        guard let target = store.existingTexture(clip: key.clip, frame: key.frame, layer: key.layer),
              let pixels = renderer.readbackBytes(target) else { return }
        let w = renderer.canvasSize.x, h = renderer.canvasSize.y
        let pieces = currentPieces(key, pixels: pixels)
        guard !pieces.isEmpty else { return }

        var chosen = Array(pieces.indices)
        if let point {
            let px = Int(point.x.rounded(.down)), py = Int(point.y.rounded(.down))
            let here = pieces.indices.reversed().filter { pieces[$0].hits(px, py, reach: 8) }    // top first
            if let top = here.first {
                var pick = top
                if let last = lastPick, last.key == key, hypot(last.point.x - point.x, last.point.y - point.y) < 10,
                   let at = here.firstIndex(of: last.index) {
                    pick = here[(at + 1) % here.count]
                }
                lastPick = (key, point, pick)
                if addingStrokes, let previous, previous.key == key {
                    var set = Set(previous.indices)
                    if set.remove(pick) == nil { set.insert(pick) }
                    chosen = set.sorted()
                } else {
                    chosen = [pick]
                }
                moveHint = MoveHint(here: here.count, number: here.count - here.firstIndex(of: pick)!, selected: chosen.count)
            } else {
                lastPick = nil
            }
        } else {
            lastPick = nil
        }
        guard !chosen.isEmpty else { return }

        let picked = Set(chosen)
        let lifted = StrokePieces.composite(chosen.map { pieces[$0] }, width: w, height: h)
        let remaining = StrokePieces.composite(pieces.indices.filter { !picked.contains($0) }.map { pieces[$0] }, width: w, height: h)
        let content = chosen.map { pieces[$0].rect }.reduce(CGRect.null) { $0.union($1) }
        let box = content.insetBy(dx: -2, dy: -2).intersection(CGRect(x: 0, y: 0, width: w, height: h))
        let outline = [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                       CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)]
        selectionBefore = store.copy(of: key)
        selectionIsLift = true
        renderer.upload(bytes: remaining, into: target)
        selectionPreview = selectionPreview ?? renderer.makeLayerTexture()
        selection = FloatingSelection(key: key, lifted: lifted, outline: outline, bounds: box,
                                      anchor: CGPoint(x: box.midX, y: box.midY))
        movingPieces = (key, chosen)
        renderSelectionPreview()
    }

    /// "Unlock and move": unlocks the blocked layer until the move is dropped, then lifts it.
    func unlockAndMove() {
        guard let id = moveBlockedLayer, let i = layers.firstIndex(where: { $0.id == id }) else { return }
        clip.layers[i].locked = false
        relockAfterMove = id
        liftForMove()
    }

    /// Frame or layer changed: drop what's floating; with Move, pick up the drawing that's now current.
    private func selectionTargetChanged() {
        finishPen()
        commitSelection()
        moveBlockedLayer = nil
        if tool == .move && !isPlaying { liftForMove() }
    }

    private func relockIfNeeded() {
        guard let id = relockAfterMove else { return }
        relockAfterMove = nil
        if let i = layers.firstIndex(where: { $0.id == id }) { clip.layers[i].locked = true }
    }

    /// Changes the floating selection's transform (move, scale, stretch, rotate, flip, anchor).
    func updateSelection(_ change: (inout FloatingSelection) -> Void) {
        guard var sel = selection else { return }
        change(&sel)
        let range = FloatingSelection.scaleRange
        sel.scale = min(max(sel.scale, range.lowerBound), range.upperBound)
        // Each axis on its own stays within the same range.
        sel.stretch.width = min(max(sel.scaleX, range.lowerBound), range.upperBound) / sel.scale
        sel.stretch.height = min(max(sel.scaleY, range.lowerBound), range.upperBound) / sel.scale
        selection = sel
        renderSelectionPreview()
    }

    /// Drops the selection where it is, as one undo step with the lift.
    func commitSelection() {
        guard let sel = selection else { return }
        // Lifted and put back where it was: no change, no undo step.
        if selectionIsLift && sel.isIdentity { cancelSelection(); return }
        relockIfNeeded()
        selection = nil
        lassoPoints = []
        moveHint = nil
        let moving = movingPieces
        movingPieces = nil
        guard let target = store.texture(clip: sel.key.clip, frame: sel.key.frame, layer: sel.key.layer),
              let base = renderer.readbackBytes(target) else { return }
        let w = renderer.canvasSize.x, h = renderer.canvasSize.y
        var before: [LayerKey: MTLTexture?] = [:]
        before.updateValue(selectionBefore, forKey: sel.key)
        coalesceTag = nil
        push(snapshot(before))                  // with the pieces as they were
        if let moving, moving.key == sel.key, var pieces = strokes[sel.key] {
            // Each piece moves on its own and stays a piece, in its place in the stack. A pencil
            // stroke is painted again where it lands, so it stays as sharp as when it was drawn.
            for i in moving.indices.sorted(by: >) where pieces.indices.contains(i) {
                if let recipe = pieces[i].recipe {
                    if let t = paint(recipe.transformed(sel.transform)) { pieces[i] = t } else { pieces.remove(at: i) }
                } else if let t = pieces[i].transformed(sel.transform, canvasWidth: w, height: h, hard: project.pixelArt) {
                    pieces[i] = t
                } else {
                    pieces.remove(at: i)
                }
            }
            strokes[sel.key] = pieces
            renderer.upload(bytes: StrokePieces.composite(pieces, width: w, height: h), into: target)
        } else {
            let placed = SelectionPixels.render(sel.lifted, width: w, height: h, transform: sel.transform, hard: project.pixelArt)
            renderer.upload(bytes: SelectionPixels.composite(placed, over: base), into: target)
            strokes[sel.key] = nil              // lassoed or pasted pixels: the pieces are gone
        }
        selectionBefore = nil
        isDirty = true
        refreshThumbnails(showing: sel.key)
    }

    /// Puts the lifted pixels back untouched, as if the lasso never happened.
    func cancelSelection() {
        guard let sel = selection else { return }
        selection = nil
        lassoPoints = []
        movingPieces = nil
        moveHint = nil
        if let before = selectionBefore { store.set(before, for: sel.key) }
        selectionBefore = nil
        relockIfNeeded()
        refreshThumbnails(showing: sel.key)
    }

    /// What Copy and Cut put aside: canvas-sized pixels where they sat, and their outline, so Paste
    /// floats them in the same place on whichever frame and layer you're on. Calco's own, not the
    /// system pasteboard: drawings stay full-quality pixels with their position.
    struct Clipboard: Equatable {
        var pixels: [UInt8]
        var outline: [CGPoint]
    }
    private(set) var clipboard: Clipboard?

    /// Lifts the whole drawing at the playhead into a selection, ready to move, copy or cut.
    func selectAll() {
        let w = CGFloat(renderer.canvasSize.x), h = CGFloat(renderer.canvasSize.y)
        tool = .lasso
        liftSelection([CGPoint(x: 0, y: 0), CGPoint(x: w, y: 0), CGPoint(x: w, y: h), CGPoint(x: 0, y: h)])
    }

    /// Copies the selection as it's placed now, or the whole drawing at the playhead when nothing
    /// is selected.
    func copySelection() {
        let w = renderer.canvasSize.x, h = renderer.canvasSize.y
        if let sel = selection {
            let placed = SelectionPixels.render(sel.lifted, width: w, height: h, transform: sel.transform, hard: project.pixelArt)
            guard !SelectionPixels.isEmpty(placed) else { return }
            clipboard = Clipboard(pixels: placed, outline: sel.outline.map { $0.applying(sel.transform) })
        } else if let key = currentDrawingKey,
                  let t = store.existingTexture(clip: key.clip, frame: key.frame, layer: key.layer),
                  let pixels = renderer.readbackBytes(t), !SelectionPixels.isEmpty(pixels) {
            let cw = CGFloat(w), ch = CGFloat(h)
            clipboard = Clipboard(pixels: pixels, outline: [CGPoint(x: 0, y: 0), CGPoint(x: cw, y: 0),
                                                             CGPoint(x: cw, y: ch), CGPoint(x: 0, y: ch)])
        }
    }

    /// Copy, then take it away: the selection, or the whole drawing when nothing is selected.
    func cutSelection() {
        copySelection()
        if selection != nil { deleteSelection() } else { clearCurrentLayer() }
    }

    /// Throws the floating selection away, leaving the hole it was lifted from. One undo step.
    func deleteSelection() {
        guard let sel = selection else { return }
        relockIfNeeded()
        selection = nil
        lassoPoints = []
        moveHint = nil
        let moving = movingPieces
        movingPieces = nil
        var before: [LayerKey: MTLTexture?] = [:]
        before.updateValue(selectionBefore, forKey: sel.key)
        coalesceTag = nil
        push(snapshot(before))
        if let moving, moving.key == sel.key, var pieces = strokes[sel.key] {
            for i in moving.indices.sorted(by: >) where pieces.indices.contains(i) { pieces.remove(at: i) }
            strokes[sel.key] = pieces
        } else {
            strokes[sel.key] = nil
        }
        selectionBefore = nil
        isDirty = true
        refreshThumbnails(showing: sel.key)
    }

    /// Floats the clipboard over the drawing at the playhead, where it was copied from, ready to
    /// move; apply (✓) drops it, cancel (✕) leaves the drawing as it was.
    func paste() {
        guard let clip = clipboard, !isPlaying, currentLayer?.locked == false, let key = currentDrawingKey else { return }
        tool = .lasso
        commitSelection()
        guard store.texture(clip: key.clip, frame: key.frame, layer: key.layer) != nil else { return }
        let w = CGFloat(renderer.canvasSize.x), h = CGFloat(renderer.canvasSize.y)
        let bounds = Self.boundingBox(clip.outline).intersection(CGRect(x: 0, y: 0, width: w, height: h))
        selectionBefore = store.copy(of: key)
        selectionIsLift = false
        movingPieces = nil
        selectionPreview = selectionPreview ?? renderer.makeLayerTexture()
        selection = FloatingSelection(key: key, lifted: clip.pixels, outline: clip.outline, bounds: bounds,
                                      anchor: CGPoint(x: bounds.midX, y: bounds.midY))
        renderSelectionPreview()
    }

    /// The selection where it's placed now. Pencil strokes are painted again from their recipes,
    /// sharp at any size; the rest (shapes, lassoed or pasted pixels) is resampled, beneath them.
    private func renderSelectionPreview() {
        guard let sel = selection, var preview = selectionPreview else { return }
        let w = renderer.canvasSize.x, h = renderer.canvasSize.y
        var recipes: [StrokeRecipe] = []
        var lifted = sel.lifted
        if let moving = movingPieces, moving.key == sel.key, let pieces = strokes[sel.key] {
            let chosen = moving.indices.filter { pieces.indices.contains($0) }.map { pieces[$0] }
            recipes = chosen.compactMap { $0.recipe?.transformed(sel.transform) }
            if !recipes.isEmpty {
                lifted = StrokePieces.composite(chosen.filter { $0.recipe == nil }, width: w, height: h)
            }
        }
        if recipes.isEmpty || !SelectionPixels.isEmpty(lifted) {
            renderer.upload(bytes: SelectionPixels.render(lifted, width: w, height: h, transform: sel.transform,
                                                          hard: project.pixelArt), into: preview)
        } else {
            renderer.clear(preview)
        }
        guard !recipes.isEmpty, let stroke = recipeTexture(\.recipeStroke), var other = recipeTexture(\.recipeScratch)
        else { return }
        for r in recipes {
            paintRecipe(r, stroke: stroke, base: preview, into: other)
            swap(&preview, &other)
        }
        selectionPreview = preview
        recipeScratch = other
    }

    private static func boundingBox(_ points: [CGPoint]) -> CGRect {
        let xs = points.map(\.x), ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return .null }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: - Tool settings

    /// Size of whichever tool is active.
    var toolSize: Float {
        get {
            switch tool {
            case .eraser: eraserSize
            case .shape, .pen, .node: shapeOptions.size
            case .smudge: smudge.size
            default: brushSize
            }
        }
        set {
            let v = min(max(newValue.rounded(), Self.sizeRange.lowerBound), Self.sizeRange.upperBound)
            switch tool {
            case .eraser: eraserSize = v
            case .shape, .pen, .node: shapeOptions.size = v
            case .smudge: smudge.size = v
            default: brushSize = v
            }
        }
    }

    /// `[` / `]`: small steps for fine brushes, bigger ones as the brush grows.
    func stepToolSize(_ direction: Int) {
        let step: Float = toolSize < 10 ? 1 : toolSize < 30 ? 2 : 4
        toolSize += Float(direction) * step
    }

    private enum ToolKey {
        static let brushSize = "tool.brushSize"
        static let brush = "tool.brush"
        static let workspaceGrid = "view.workspaceGrid"
        static let eraserBrush = "tool.eraserBrush"
        static let brushSizes = "tool.brushSizes"
        static let brushOpacities = "tool.brushOpacities"
        static let eraserSize = "tool.eraserSize"
        static let color = "tool.color"
        static let fillGaps = "tool.fillGaps"
        static let smoothing = "tool.smoothing"
        static let usePressure = "tool.usePressure"
        static let syncLayers = "timeline.syncLayers"
        static let paintMode = "tool.paintMode"
        static let pencilOnly = "tool.pencilOnly"
        static let shapes = "tool.shapes"
        static let smudge = "tool.smudge"
    }

    @ObservationIgnored private var loadingToolSettings = false

    /// Missing or out-of-range values keep the defaults.
    private func loadToolSettings() {
        guard let defaults else { return }
        loadingToolSettings = true
        defer { loadingToolSettings = false }
        let range = Self.sizeRange
        if let id = defaults.string(forKey: ToolKey.brush), Brush.all.contains(where: { $0.id == id }) { brushID = id }
        if let id = defaults.string(forKey: ToolKey.eraserBrush), Brush.all.contains(where: { $0.id == id }) { eraserBrushID = id }
        if let d = defaults.dictionary(forKey: ToolKey.brushSizes) as? [String: Float] {
            brushSizes = d.filter { range.contains($0.value) }
        } else if let v = defaults.object(forKey: ToolKey.brushSize) as? Float, range.contains(v) {
            brushSizes[Brush.inker.id] = v                       // the one brush before there were several
        }
        if let v = defaults.object(forKey: ToolKey.workspaceGrid) as? Bool { workspaceGrid = v }
        if let d = defaults.dictionary(forKey: ToolKey.brushOpacities) as? [String: Float] {
            brushOpacities = d.filter { (0.05...1).contains($0.value) }
        }
        if let v = defaults.object(forKey: ToolKey.eraserSize) as? Float, range.contains(v) { eraserSize = v }
        if let c = defaults.array(forKey: ToolKey.color) as? [Float], c.count == 3,
           c.allSatisfy({ (0...1).contains($0) }) {
            color = SIMD4<Float>(c[0], c[1], c[2], 1)
        }
        if let raw = defaults.object(forKey: ToolKey.fillGaps) as? Int, let g = FillGaps(rawValue: raw) { fillGaps = g }
        if let v = defaults.object(forKey: ToolKey.smoothing) as? Float, (0...1).contains(v) { smoothing = v }
        if let v = defaults.object(forKey: ToolKey.usePressure) as? Bool { usePressure = v }
        if let v = defaults.object(forKey: ToolKey.syncLayers) as? Bool { syncLayers = v }
        if let raw = defaults.string(forKey: ToolKey.paintMode), let m = CanvasRenderer.PaintMode(rawValue: raw) { paintMode = m }
        pencilOnly = defaults.object(forKey: ToolKey.pencilOnly) as? Bool ?? UIPencilInteraction.prefersPencilOnlyDrawing
        if let data = defaults.data(forKey: ToolKey.shapes), var o = try? JSONDecoder().decode(ShapeOptions.self, from: data) {
            o.size = min(max(o.size, range.lowerBound), range.upperBound)
            shapeOptions = o
        }
        if let data = defaults.data(forKey: ToolKey.smudge), var o = try? JSONDecoder().decode(SmudgeOptions.self, from: data) {
            o.size = min(max(o.size, range.lowerBound), range.upperBound)
            o.strength = min(max(o.strength, 0.05), 1)
            smudge = o
        }
    }

    private func saveToolSettings() {
        guard let defaults, !loadingToolSettings else { return }
        defaults.set(brushID, forKey: ToolKey.brush)
        defaults.set(eraserBrushID, forKey: ToolKey.eraserBrush)
        defaults.set(brushSizes, forKey: ToolKey.brushSizes)
        defaults.set(brushOpacities, forKey: ToolKey.brushOpacities)
        defaults.set(workspaceGrid, forKey: ToolKey.workspaceGrid)
        defaults.set(eraserSize, forKey: ToolKey.eraserSize)
        defaults.set([color.x, color.y, color.z], forKey: ToolKey.color)
        defaults.set(fillGaps.rawValue, forKey: ToolKey.fillGaps)
        defaults.set(smoothing, forKey: ToolKey.smoothing)
        defaults.set(usePressure, forKey: ToolKey.usePressure)
        defaults.set(syncLayers, forKey: ToolKey.syncLayers)
        defaults.set(paintMode.rawValue, forKey: ToolKey.paintMode)
        defaults.set(pencilOnly, forKey: ToolKey.pencilOnly)
        defaults.set(try? JSONEncoder().encode(shapeOptions), forKey: ToolKey.shapes)
        defaults.set(try? JSONEncoder().encode(smudge), forKey: ToolKey.smudge)
    }

    /// Apple Pencil double tap / squeeze set to "switch to eraser": eraser, and back to what you had.
    func pencilSwitchEraser() {
        tool = tool == .eraser ? (previousTool == .eraser ? .brush : previousTool) : .eraser
    }

    /// Apple Pencil double tap / squeeze set to "switch to previous tool".
    func pencilSwitchPrevious() { tool = previousTool }

    func setColor(_ c: SIMD4<Float>) {
        color = SIMD4<Float>(min(max(c.x, 0), 1), min(max(c.y, 0), 1), min(max(c.z, 0), 1), 1)
        // A colour is for painting: leave the eraser, but keep filling, or drawing shapes and paths
        // (an open path takes the colour), if that's what you were doing.
        if ![.fill, .shape, .pen, .node].contains(tool) { tool = .brush }
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
        /// The same drawings' pieces (nil: not known).
        var pieces: [LayerKey: [StrokePiece]?] = [:]
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    private func layerKeys(_ clip: Clip, frame: String) -> [LayerKey] {
        clip.layers.map { LayerKey(clip: clip.id, frame: frame, layer: $0.id) }
    }

    private func snapshot(_ textures: [LayerKey: MTLTexture?]) -> Snapshot {
        var pieces: [LayerKey: [StrokePiece]?] = [:]
        for k in textures.keys { pieces.updateValue(strokes[k], forKey: k) }
        return Snapshot(project: project, clipIndex: clipIndex, frameIndex: frameIndex,
                        layerIndex: layerIndex, textures: textures, pieces: pieces)
    }

    /// Call right before an edit. `textures` are the layers the edit creates, removes or paints into;
    /// `copyPixels` when it changes them in place (strokes, clear). Edits sharing a `coalescing` tag
    /// in a row (a drag, a stepper) become one undo step.
    private func recordUndo(textures keys: [LayerKey] = [], copyPixels: Bool = false, coalescing tag: String? = nil) {
        // An open path goes back on the drawing first: every edit sees it, and undoes after it.
        finishPen()
        commitSelection()
        if let tag, tag == coalesceTag, !undoStack.isEmpty { return }
        coalesceTag = tag
        var saved: [LayerKey: MTLTexture?] = [:]
        for k in keys { saved.updateValue(copyPixels ? store.copy(of: k) : store.raw(k), forKey: k) }
        push(snapshot(saved))
        // Painted over in place (fill, clear, import…): its pieces can't be told apart any more.
        if copyPixels { for k in keys { strokes[k] = nil } }
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
        // With a selection floating or a path open, undo means "never mind".
        if selection != nil { cancelSelection(); return }
        if penEditing != nil { cancelPen(); return }
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
        for (k, p) in s.pieces { strokes[k] = p }
        isDirty = true
        for f in frames { refreshThumbnail(for: f.id) }
    }
}
