import SwiftUI

struct GeneralSettingsView: View {

    @ObservedObject var appState: AppStateManager
    @ObservedObject var settings: SettingsManager
    @ObservedObject var launchAtLogin: LaunchAtLoginManager
    let renderer: CharmRenderer

    var body: some View {
        Form {
            Section("Charm") {
                CharmPickerView(
                    charms: appState.catalog.charms,
                    selectedID: appState.selectedCharm.id,
                    renderer: renderer,
                    onSelect: { appState.selectCharm(id: $0) }
                )

                if !appState.selectedCharm.description.isEmpty {
                    Text(appState.selectedCharm.description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Visibility") {
                Toggle("Show charm on the desktop", isOn: Binding(
                    get: { appState.isCharmVisible },
                    set: { appState.setCharmVisible($0) }
                ))
                .accessibilityHint("Hides or shows the hanging charm overlay.")

                Toggle("Show on all Spaces", isOn: $settings.showOnAllSpaces)
                    .accessibilityHint("Keeps the charm visible on every virtual desktop.")

                Toggle("Show in fullscreen apps", isOn: $settings.showInFullscreenApps)
                    .accessibilityHint("Allows the charm to float above apps in fullscreen.")
            }

            Section("Startup") {
                // Bound to the manager rather than to the stored preference,
                // because macOS is the authority here: the toggle should show
                // what the system actually did, not what was asked of it.
                Toggle("Launch CharmDrop at login", isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                .disabled(!launchAtLogin.status.isActionable)
                .accessibilityHint("Starts CharmDrop automatically when you log in.")

                if let explanation = launchAtLogin.status.explanation {
                    Text(explanation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if launchAtLogin.status == .requiresApproval,
                   let url = LaunchAtLoginManager.loginItemsSettingsURL {
                    Button("Open Login Items…") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .formStyle(.grouped)
        // The user can change login items behind the app's back, so the state
        // is re-read whenever this pane appears.
        .onAppear { launchAtLogin.synchronize() }
    }
}

/// Horizontal thumbnail picker. Thumbnails come from the same renderer the
/// overlay uses, so settings always show exactly what will hang on screen.
private struct CharmPickerView: View {

    let charms: [Charm]
    let selectedID: String
    let renderer: CharmRenderer
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(charms) { charm in
                Button {
                    onSelect(charm.id)
                } label: {
                    VStack(spacing: 6) {
                        thumbnail(for: charm)
                            .frame(width: 44, height: 54)
                        Text(charm.displayName)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .padding(8)
                    .frame(width: 88)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(charm.id == selectedID
                                  ? Color.accentColor.opacity(0.18)
                                  : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                charm.id == selectedID ? Color.accentColor : Color.secondary.opacity(0.25),
                                lineWidth: charm.id == selectedID ? 1.5 : 1
                            )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(charm.displayName)
                .accessibilityAddTraits(charm.id == selectedID ? [.isSelected] : [])
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func thumbnail(for charm: Charm) -> some View {
        if let image = renderer.image(for: charm, pixelScale: 2) {
            Image(decorative: image, scale: 2)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "questionmark.square.dashed")
                .foregroundStyle(.secondary)
        }
    }
}
