import SwiftUI

/// App-wide preferences (⌘,): for now, the language. More app-wide settings go here.
struct PreferencesView: View {
    @ObservedObject var state: EditorState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Language", selection: $state.language) {
                        ForEach(AppLanguage.allCases) { Text(verbatim: $0.name).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Language")
                } footer: {
                    Text("Calco is in English unless you choose otherwise. Your projects, layer and clip names don't change.")
                }
            }
            .navigationTitle("Preferences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        // The navigation bar keeps its title otherwise; redraw it in the new language.
        .id(state.language)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }
}
