import SwiftUI

/// Every keyboard shortcut lives here, as app menu commands, so iPadOS lists them in the
/// overlay you get by holding ⌘. Views keep their buttons but don't register shortcuts.
struct CalcoCommands: Commands {
    @Bindable var state: EditorState

    var body: some Commands {
        // File
        CommandGroup(replacing: .newItem) {
            Button("New Project…") { state.request = .newProject }.keyboardShortcut("n")
            Button("Open from Files…") { state.request = .open }.keyboardShortcut("o")
            Button("All Projects") { state.closeToGallery() }.keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(state.isInGallery)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save") { state.save() }.keyboardShortcut("s").disabled(state.isInGallery)
            Button("Save As…") { state.request = .saveAs }.keyboardShortcut("s", modifiers: [.command, .shift]).disabled(state.isInGallery)
        }
        CommandGroup(replacing: .importExport) {
            Button("Export…") { state.request = .export }.keyboardShortcut("e").disabled(state.isInGallery)
            Button("Export Again\(state.lastExportProfile.map { " (\($0.name))" } ?? "")") { state.request = .exportAgain }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(state.isInGallery || state.lastExportProfile == nil)
            Button("Export GIF…") { state.request = .exportGIF }.keyboardShortcut("g").disabled(state.isInGallery)
        }

        // Edit
        CommandGroup(replacing: .appSettings) {
            Button("Preferences…") { state.showingPreferences = true }.keyboardShortcut(",")
        }
        CommandGroup(replacing: .pasteboard) {
            Button("Cut") { state.cutSelection() }.keyboardShortcut("x").disabled(state.isInGallery)
            Button("Copy") { state.copySelection() }.keyboardShortcut("c").disabled(state.isInGallery)
            Button("Paste") { state.paste() }.keyboardShortcut("v").disabled(state.isInGallery || state.clipboard == nil)
            Button("Select All") { state.selectAll() }.keyboardShortcut("a").disabled(state.isInGallery)
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { state.undo() }.keyboardShortcut("z").disabled(!state.canUndo)
            Button("Redo") { state.redo() }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!state.canRedo)
        }

        CommandMenu("Draw") {
            Button("Brush") { state.tool = .brush }.keyboardShortcut("b", modifiers: [])
            Button("Eraser") { state.tool = .eraser }.keyboardShortcut("e", modifiers: [])
            Button("Fill") { state.tool = .fill }.keyboardShortcut("g", modifiers: [])
            Button("Eyedropper") { state.tool = .eyedropper }.keyboardShortcut("i", modifiers: [])
            Button("Lasso") { state.tool = .lasso }.keyboardShortcut("l", modifiers: [])
            Button("Move") { state.tool = .move }.keyboardShortcut("v", modifiers: [])
            Button("Shapes") { state.tool = .shape }.keyboardShortcut("u", modifiers: [])
            Button("Pen") { state.tool = .pen }.keyboardShortcut("p", modifiers: [])
            Button("Node") { state.tool = .node }.keyboardShortcut("a", modifiers: [])
            Button("Smudge") { state.tool = .smudge }.keyboardShortcut("s", modifiers: [])
            Button("Apply Selection") { state.commitSelection() }.keyboardShortcut(.return, modifiers: [])
                .disabled(!state.hasSelection)
            Button("Cancel Selection") { state.cancelSelection() }.keyboardShortcut(.escape, modifiers: [])
                .disabled(!state.hasSelection)
            Button("Flip Selection") { state.updateSelection { $0.flipped.toggle() } }
                .keyboardShortcut("h", modifiers: [.shift])
                .disabled(!state.hasSelection)
            Button("Smaller") { state.stepToolSize(-1) }.keyboardShortcut("[", modifiers: [])
            Button("Bigger") { state.stepToolSize(1) }.keyboardShortcut("]", modifiers: [])
            Divider()
            Button("Clear Layer") { state.clearCurrentLayer() }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
            Divider()
            Button("Zoom In") { state.canvasTransform.zoom(by: 1.25) }.keyboardShortcut("=")
            Button("Zoom Out") { state.canvasTransform.zoom(by: 0.8) }.keyboardShortcut("-")
            Button("Fit Canvas") { state.fitCanvas() }.keyboardShortcut("0")
            Button(state.viewFlipped ? "Unflip View" : "Flip View") { state.canvasTransform.flipped.toggle() }
                .keyboardShortcut("h", modifiers: [])
            Button(state.isZen ? "Leave Zen Mode" : "Zen Mode") { state.isZen.toggle() }
                .keyboardShortcut("f", modifiers: [.command, .control])
            Divider()
            Button(state.onion.enabled ? "Hide Onion Skin" : "Show Onion Skin") { state.onion.enabled.toggle() }
                .keyboardShortcut("o", modifiers: [])
        }

        CommandMenu("Frame") {
            Button(state.isPlaying ? "Pause" : "Play") { state.togglePlayback() }
                .keyboardShortcut(.space, modifiers: [])
            Divider()
            Button("Previous Frame") { state.stepFrame(-1) }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("Next Frame") { state.stepFrame(1) }.keyboardShortcut(.rightArrow, modifiers: [])
            Divider()
            // Same as the bar: the current layer's drawing, or whole frames with Sync Layers on.
            Button(state.syncLayers ? "New Frame" : "New Drawing") { state.addDrawing() }.keyboardShortcut("n", modifiers: [.option])
            Button(state.syncLayers ? "Duplicate Frame" : "Duplicate Drawing") { state.duplicateDrawing() }.keyboardShortcut("d")
            Button(state.syncLayers ? "Delete Frame" : "Delete Drawing") { state.deleteDrawing() }.keyboardShortcut(.delete)
                .disabled(state.syncLayers && state.frames.count <= 1)
            Toggle("Sync Layers", isOn: $state.syncLayers)
            Divider()
            Button("Move Frame Earlier") { state.moveFrame(by: -1) }.keyboardShortcut(.leftArrow, modifiers: [.option])
            Button("Move Frame Later") { state.moveFrame(by: 1) }.keyboardShortcut(.rightArrow, modifiers: [.option])
            Button("Hold Longer") { state.stepHold(1) }.keyboardShortcut("=", modifiers: [.option])
            Button("Hold Shorter") { state.stepHold(-1) }.keyboardShortcut("-", modifiers: [.option])
        }

        CommandMenu("Layer") {
            Button("Layer Above") { state.stepLayer(1) }.keyboardShortcut(.upArrow, modifiers: [])
            Button("Layer Below") { state.stepLayer(-1) }.keyboardShortcut(.downArrow, modifiers: [])
            Divider()
            Button("New Layer") { state.addLayerWithDefaultName() }.keyboardShortcut("n", modifiers: [.command, .shift])
        }
    }
}
