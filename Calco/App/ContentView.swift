import SwiftUI

/// Placeholder root view. Replaced by the editor once the canvas PoC lands.
struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Calco")
                .font(.system(size: 48, weight: .bold, design: .rounded))
            Text("Hand-drawn sprites for games.")
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ContentView()
}
