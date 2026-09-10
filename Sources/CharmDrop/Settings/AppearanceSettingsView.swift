import SwiftUI

struct AppearanceSettingsView: View {

    @ObservedObject var settings: SettingsManager

    var body: some View {
        Form {
            Section("Charm") {
                LabeledSlider(
                    title: "Size",
                    value: $settings.charmScale,
                    range: Constants.CharmScale.minimum...Constants.CharmScale.maximum,
                    format: { String(format: "%.2f×", $0) }
                )
            }

            Section("Rope") {
                LabeledSlider(
                    title: "Length",
                    value: $settings.ropeLength,
                    range: Constants.Rope.minimumLength...Constants.Rope.maximumLength,
                    format: { String(format: "%.0f px", $0) }
                )

                LabeledSlider(
                    title: "Thickness",
                    value: $settings.ropeThickness,
                    range: 1...6,
                    format: { String(format: "%.1f px", $0) }
                )

                LabeledSlider(
                    title: "Opacity",
                    value: $settings.ropeOpacity,
                    range: 0.2...1.0,
                    format: { String(format: "%.0f%%", $0 * 100) }
                )
            }

            Section("Anchor") {
                Picker("Position", selection: $settings.anchorPosition) {
                    ForEach(AnchorPosition.allCases) { position in
                        Text(position.displayName).tag(position)
                    }
                }
                .pickerStyle(.segmented)

                if settings.anchorPosition == .custom {
                    LabeledSlider(
                        title: "Offset",
                        value: $settings.customAnchorFraction,
                        range: 0.02...0.98,
                        format: { String(format: "%.0f%% from left", $0 * 100) }
                    )
                } else {
                    Text("Anchor offsets are stored as a percentage of screen width, so the charm stays in place when the resolution changes.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// A slider with a title and a live numeric read-out, matching the layout used
/// throughout System Settings.
struct LabeledSlider: View {

    let title: String
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    let format: (CGFloat) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range)
                .accessibilityLabel(title)
                .accessibilityValue(format(value))
        }
    }
}
