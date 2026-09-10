import AppKit
import SwiftUI

/// Contents of the menu bar item.
///
/// Rendered with `MenuBarExtra`'s `.menu` style, so SwiftUI controls map onto
/// real `NSMenu` items: `Toggle` becomes a checkable item and `Picker` becomes
/// a submenu with a checkmark on the selection.
struct MenuBarView: View {

    @ObservedObject var appState: AppStateManager
    let updateManager: UpdateManaging

    var body: some View {
        Group {
            Toggle("Show Charm", isOn: showCharmBinding)

            Divider()

            Picker("Charm", selection: charmBinding) {
                ForEach(appState.catalog.charms) { charm in
                    Text(charm.displayName).tag(charm.id)
                }
            }

            Button("Perform Ritual") {
                appState.performRitual()
            }
            .disabled(!appState.isCharmVisible)

            Divider()

            Picker("Position", selection: anchorBinding) {
                ForEach(AnchorPosition.allCases) { position in
                    Text(position.displayName).tag(position)
                }
            }

            Button("Reset Position") {
                appState.resetCharm()
            }
            .disabled(!appState.isCharmVisible)

            Divider()

            SettingsLink {
                Text("Settings…")
            }
            .keyboardShortcut(",", modifiers: .command)

            Button("Check for Updates…") {
                updateManager.checkForUpdates()
            }

            Divider()

            Button("Quit \(Constants.App.displayName)") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    // MARK: - Bindings

    /// Menu controls write through `AppStateManager` rather than mutating
    /// settings directly, so logging and validation stay in one place.
    private var showCharmBinding: Binding<Bool> {
        Binding(
            get: { appState.isCharmVisible },
            set: { appState.setCharmVisible($0) }
        )
    }

    private var charmBinding: Binding<String> {
        Binding(
            get: { appState.selectedCharm.id },
            set: { appState.selectCharm(id: $0) }
        )
    }

    private var anchorBinding: Binding<AnchorPosition> {
        Binding(
            get: { appState.settings.anchorPosition },
            set: { appState.setAnchorPosition($0) }
        )
    }
}
