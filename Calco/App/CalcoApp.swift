import SwiftUI
import Metal

@main
struct CalcoApp: App {
    @StateObject private var state = EditorState.make()

    var body: some Scene {
        WindowGroup {
            ContentView(state: state)
        }
    }
}

extension EditorState {
    /// Every supported iPad has a Metal device; failing here means a broken build, not a user error.
    static func make() -> EditorState {
        guard let device = MTLCreateSystemDefaultDevice(),
              let state = EditorState(device: device, screenFormat: CanvasUIView.screenFormat) else {
            fatalError("Metal is unavailable or the shader library failed to load")
        }
        return state
    }
}
