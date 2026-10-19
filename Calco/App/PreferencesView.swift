import SwiftUI

/// App-wide preferences (⌘,): the language and a performance readout.
struct PreferencesView: View {
    @ObservedObject var state: EditorState
    @Environment(\.dismiss) private var dismiss
    @AppStorage("showLatency") private var showLatency = false

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
                Section {
                    Toggle("Show drawing latency", isOn: $showLatency)
                } footer: {
                    Text("Milliseconds from the Pencil to the screen, in the top bar. For checking performance.")
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
