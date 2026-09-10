import SwiftUI

struct InteractionSettingsView: View {

    @ObservedObject var settings: SettingsManager

    var body: some View {
        Form {
            Section("Dragging") {
                LabeledSlider(
                    title: "Drag sensitivity",
                    value: $settings.dragSensitivity,
                    range: 0.3...2.0,
                    format: { String(format: "%.2f×", $0) }
                )

                LabeledSlider(
                    title: "Flick strength",
                    value: $settings.flickStrength,
                    range: Constants.Interaction.minimumFlickStrength...Constants.Interaction.maximumFlickStrength,
                    format: { String(format: "%.2f×", $0) }
                )

                Text("Flick strength scales the speed the charm keeps when you let go.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Rituals") {
                Picker("Perform ritual on", selection: $settings.ritualTrigger) {
                    ForEach(RitualTrigger.allCases) { trigger in
                        Text(trigger.displayName).tag(trigger)
                    }
                }

                Toggle("Play sounds", isOn: $settings.soundEnabled)
                    .accessibilityHint("Plays a short sound when a charm's ritual makes one.")

                Text("Only some charms make a sound. Effects are quiet by design.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
