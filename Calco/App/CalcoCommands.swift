import SwiftUI

/// Every keyboard shortcut lives here, as app menu commands, so iPadOS lists them in the
/// overlay you get by holding ⌘. Views keep their buttons but don't register shortcuts.
struct CalcoCommands: Commands {
    @ObservedObject var state: EditorState

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
            Button("Export Sprite Sheet…") { state.request = .exportSpriteSheet }.keyboardShortcut("e").disabled(state.isInGallery)
            Button("Export GIF…") { state.request = .exportGIF }.keyboardShortcut("g").disabled(state.isInGallery)
        }

        // Edit
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { state.undo() }.keyboardShortcut("z").disabled(!state.canUndo)
            Button("Redo") { state.redo() }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!state.canRedo)
        }

        CommandMenu("Draw") {
            Button("Brush") { state.tool = .brush }.keyboardShortcut("b", modifiers: [])
            Button("Eraser") { state.tool = .eraser }.keyboardShortcut("e", modifiers: [])
            Button("Fill") { state.tool = .fill }.keyboardShortcut("g", modifiers: [])
            Button("Eyedropper") { state.tool = .eyedropper }.keyboardShortcut("i", modifiers: [])
            Button("Smaller") { state.stepToolSize(-1) }.keyboardShortcut("[", modifiers: [])
            Button("Bigger") { state.stepToolSize(1) }.keyboardShortcut("]", modifiers: [])
            Divider()
            Button("Clear Layer") { state.clearCurrentLayer() }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
            Divider()
            Button("Zoom In") { state.canvasTransform.zoom(by: 1.25) }.keyboardShortcut("=")
            Button("Zoom Out") { state.canvasTransform.zoom(by: 0.8) }.keyboardShortcut("-")
            Button("Fit Canvas") { state.canvasTransform = .identity }.keyboardShortcut("0")
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
            Button("New Frame") { state.addFrame() }.keyboardShortcut("n", modifiers: [.option])
            Button("Duplicate Frame") { state.duplicateFrame() }.keyboardShortcut("d")
            Button("Delete Frame") { state.deleteFrame() }.keyboardShortcut(.delete)
                .disabled(state.frames.count <= 1)
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
