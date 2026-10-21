import SwiftUI
import Metal

@main
struct CalcoApp: App {
    @State private var state = EditorState.make()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Before any text is drawn: English by default, whatever the iPad's language.
        AppLanguage.apply(AppLanguage.saved, save: false)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if state.isInGallery { GalleryView(state: state) } else { ContentView(state: state) }
            }
            // A new language redraws every view in it.
            .id(state.language)
            .sheet(isPresented: $state.showingPreferences) { PreferencesView(state: state) }
            .environment(\.locale, state.language.locale)
            // Tapping a .calco package in Files.
            .onOpenURL { url in state.open(url) }
            // The whole screen is the studio: no clock or battery over it, like Procreate.
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
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
