import SwiftUI

/// A button that always shows its grey background, so it reads as something
/// to press even when it's the only thing on an otherwise empty tab. The
/// background deepens while it's held. Matches `SegmentedPicker`'s track.
struct FilledButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .frame(maxWidth: .infinity)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.22 : 0.12))
            )
            .contentShape(Rectangle())
    }
}

/// A segmented control drawn by hand.
///
/// AppKit's own segmented control styles two- and three-segment pickers
/// differently — with three segments it draws a separator between the two
/// unselected ones and tints the track slightly differently — so the LED mode
/// picker never matched the tab picker above it. Drawing both makes them
/// identical, and gives every segment the same width.
struct SegmentedPicker<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let title: String
        var id: Value { value }

        init(_ value: Value, _ title: String) {
            self.value = value
            self.title = title
        }
    }

    @Binding var selection: Value
    let options: [Option]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                segment(option)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.12))
        )
    }

    private func segment(_ option: Option) -> some View {
        let isSelected = option.value == selection
        return Button {
            selection = option.value
        } label: {
            Text(option.title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
