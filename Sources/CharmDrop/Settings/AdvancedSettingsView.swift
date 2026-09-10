import AppKit
import SwiftUI

struct AdvancedSettingsView: View {

    @ObservedObject var appState: AppStateManager
    @ObservedObject var settings: SettingsManager
    let updateManager: UpdateManaging

    @State private var isConfirmingReset = false

    var body: some View {
        Form {
            Section("Developer") {
                Toggle("Show physics debug overlay", isOn: $settings.debugOverlayEnabled)
                    .accessibilityHint("Draws rope particles, constraints, the charm hitbox and the frame rate.")

                Text("Debug drawing is intended for development and is off by default.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Updates") {
                Button("Check for Updates…") {
                    updateManager.checkForUpdates()
                }
                if !updateManager.isConfigured {
                    Text("No update feed is configured for this build.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Reset") {
                Button("Reset All Settings…", role: .destructive) {
                    isConfirmingReset = true
                }
                .confirmationDialog(
                    "Reset all settings to their defaults?",
                    isPresented: $isConfirmingReset
                ) {
                    Button("Reset", role: .destructive) {
                        settings.resetAll()
                        appState.resetCharm()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Your charm choice, sizes and interaction preferences will be restored to defaults.")
                }
            }

            Section("About") {
                LabeledContent("Version", value: Self.versionString)
                LabeledContent("Bundle Identifier", value: Bundle.main.bundleIdentifier ?? Constants.App.bundleIdentifier)
            }
        }
        .formStyle(.grouped)
    }

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}
