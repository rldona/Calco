import SwiftUI
import Metal

@main
struct CalcoApp: App {
    @StateObject private var state = EditorState.make()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(state: state)
                // Tapping a .calco package in Files.
                .onOpenURL { url in state.open(url) }
        }
        .commands { CalcoCommands(state: state) }
        .onChange(of: scenePhase) { _, phase in
            // iPadOS can kill a backgrounded app at any time; don't lose work that already has a file.
            if phase == .background { state.saveIfNeeded() }
        }
    }
}

extension EditorState {
    /// Every supported iPad has a Metal device; failing here means a broken build, not a user error.
    static func make() -> EditorState {
        guard let device = MTLCreateSystemDefaultDevice(),
              let state = EditorState(device: device, screenFormat: CanvasUIView.screenFormat,
                                      defaults: .standard) else {
            fatalError("Metal is unavailable or the shader library failed to load")
        }
        return state
    }
}
