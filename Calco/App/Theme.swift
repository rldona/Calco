import SwiftUI

/// Calco's look ("Estudio"): dark neutral chrome so the drawing is the brightest thing on screen,
/// one warm accent for whatever is active. The app is dark-only on purpose.
enum Theme {
    /// Behind everything; matches the renderer's clear colour around the canvas.
    static let background = Color(red: 0.106, green: 0.106, blue: 0.114)   // #1B1B1D
    static let panel      = Color(red: 0.149, green: 0.149, blue: 0.157)   // #262628
    static let raised     = Color(red: 0.227, green: 0.227, blue: 0.235)   // #3A3A3C
    static let hairline   = Color(red: 0.267, green: 0.267, blue: 0.255)   // #444441

    static let text       = Color(red: 0.945, green: 0.937, blue: 0.910)   // #F1EFE8
    static let textDim    = Color(red: 0.706, green: 0.698, blue: 0.663)   // #B4B2A9
    static let textFaint  = Color(red: 0.373, green: 0.369, blue: 0.353)   // #5F5E5A

    static let accent     = Color(red: 0.937, green: 0.624, blue: 0.153)   // #EF9F27
    static let onAccent   = Color(red: 0.255, green: 0.141, blue: 0.008)   // #412402
    static let accentWash = Color(red: 0.227, green: 0.165, blue: 0.063)   // #3A2A10
    static let accentText = Color(red: 0.980, green: 0.780, blue: 0.459)   // #FAC775

    static let corner: CGFloat = 12
    static let gap: CGFloat = 8
}

extension View {
    /// A chrome panel: flat, rounded, no material blur (blur over a live Metal view costs frames).
    func calcoPanel(padding: CGFloat = 8) -> some View {
        self.padding(padding)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.corner))
            // Floating over the canvas.
            .shadow(color: .black.opacity(0.35), radius: 10, y: 3)
    }
}

/// Square icon button for the rail and bars. `active` paints it with the accent.
struct RailButton: View {
    let icon: String
    let label: LocalizedStringKey
    var active = false
    var size: CGFloat = 36
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // An SF Symbol, or one of Calco's own drawn icons (the fill bucket) from the asset catalog.
            (UIImage(systemName: icon) != nil ? Image(systemName: icon) : Image(icon))
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(active ? Theme.onAccent : Theme.textDim)
                .frame(width: size, height: size)
                .background(active ? Theme.accent : .clear, in: RoundedRectangle(cornerRadius: 9))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(active ? .isSelected : [])
        .help(label)
    }
}
