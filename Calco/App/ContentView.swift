import SwiftUI

/// Canvas PoC: one brush, one layer, a latency readout and a clear button.
/// Everything here is throwaway; it exists to judge how the Pencil feels.
struct ContentView: View {
    @State private var latencyMs: Double = 0
    @State private var clearToken = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            CanvasView(latencyMs: $latencyMs, clearToken: clearToken)
                .ignoresSafeArea()

            HStack(spacing: 16) {
                Text(String(format: "input→enqueue %.1f ms", latencyMs))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Button("Clear") { clearToken += 1 }
                    .buttonStyle(.bordered)
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding()
        }
    }
}

#Preview {
    ContentView()
}
