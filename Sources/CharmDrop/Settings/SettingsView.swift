import SwiftUI

/// Root of the Settings window, opened by `SettingsLink` or ⌘,.
///
/// Tabs mirror the grouping used by macOS System Settings so the app feels
/// native rather than like a port.
struct SettingsView: View {

    @ObservedObject var appState: AppStateManager
    @ObservedObject var launchAtLogin: LaunchAtLoginManager
    let renderer: CharmRenderer
    let updateManager: UpdateManaging

    private enum Tab: Hashable {
        case general, appearance, interactions, advanced
    }

    @State private var selection: Tab = .general

    var body: some View {
        TabView(selection: $selection) {
            GeneralSettingsView(
                appState: appState,
                settings: appState.settings,
                launchAtLogin: launchAtLogin,
                renderer: renderer
            )
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Tab.general)

            AppearanceSettingsView(settings: appState.settings)
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
                .tag(Tab.appearance)

            InteractionSettingsView(settings: appState.settings)
                .tabItem { Label("Interactions", systemImage: "hand.tap") }
                .tag(Tab.interactions)

            AdvancedSettingsView(
                appState: appState,
                settings: appState.settings,
                updateManager: updateManager
            )
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
                .tag(Tab.advanced)
        }
        .frame(width: 480)
        .frame(minHeight: 380)
    }
}
