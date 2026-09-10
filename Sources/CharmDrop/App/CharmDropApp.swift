import SwiftUI

/// The SwiftUI application.
///
/// There is deliberately no `WindowGroup`: the app is a menu bar accessory and
/// only ever opens the Settings window on request. Launched from `main.swift`
/// rather than via `@main` so diagnostic command-line modes can run without
/// starting the UI.
struct CharmDropApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                appState: appDelegate.environment.appState,
                updateManager: appDelegate.environment.updateManager
            )
        } label: {
            Image(nsImage: MenuBarIcon.makeImage())
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(
                appState: appDelegate.environment.appState,
                launchAtLogin: appDelegate.environment.launchAtLogin,
                renderer: appDelegate.environment.charmRenderer,
                updateManager: appDelegate.environment.updateManager
            )
        }
    }
}
