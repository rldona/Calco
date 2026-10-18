import SwiftUI

/// "fps 12 − +" in the space of a label. Used for fps, hold and onion skin instead of the
/// system Stepper, whose pill is about as wide as the rest of a toolbar group.
struct CompactStepper: View {
    let title: LocalizedStringKey
    @Binding var value: Int
    let range: ClosedRange<Int>
    /// Dimmed value, e.g. an fps that falls back to the project's.
    var inherited = false

    var body: some View {
        HStack(spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .padding(.trailing, 2)
            Text("\(value)")
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .foregroundStyle(inherited ? .secondary : .primary)
                .frame(minWidth: 18)
            step("minus", by: -1).disabled(value <= range.lowerBound)
            step("plus", by: 1).disabled(value >= range.upperBound)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + 1, range.upperBound)
            case .decrement: value = max(value - 1, range.lowerBound)
            @unknown default: break
            }
        }
    }

    private func step(_ icon: String, by delta: Int) -> some View {
        Button { value = min(max(value + delta, range.lowerBound), range.upperBound) } label: {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }
}
