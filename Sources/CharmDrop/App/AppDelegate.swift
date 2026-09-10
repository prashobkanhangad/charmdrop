import AppKit
import SwiftUI

/// Handles the NSApplication-level concerns SwiftUI does not cover: activation
/// policy, power notifications, and teardown.
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {

    /// Created lazily but before any scene body runs, because
    /// `applicationWillFinishLaunching` precedes scene evaluation.
    @MainActor
    lazy var environment = AppEnvironment()

    private var workspaceObservers: [NSObjectProtocol] = []

    @MainActor
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Menu bar only: no Dock icon, no default main window. `LSUIElement` in
        // Info.plist does the same thing, but setting it here keeps behaviour
        // correct when running the binary directly during development.
        NSApp.setActivationPolicy(.accessory)
    }

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        registerPowerObservers()
        environment.appState.onOpenSettings = { Self.openSettingsWindow() }
        environment.start()
    }

    // MARK: - Deep links

    /// Entry point for `charmdrop://` URLs, whether the app was already running
    /// or was launched by the link.
    @MainActor
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            environment.appState.handleDeepLink(url)
        }
    }

    /// Opens the Settings scene from outside SwiftUI.
    ///
    /// SwiftUI only exposes `SettingsLink`, which cannot be triggered
    /// programmatically, so this goes through the action AppKit sends for the
    /// Settings menu item. The selector was renamed in macOS 13, hence the
    /// fallback.
    @MainActor
    private static func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)

        let selectors = [
            Selector(("showSettingsWindow:")),
            Selector(("showPreferencesWindow:"))
        ]
        for selector in selectors where NSApp.sendAction(selector, to: nil, from: nil) {
            return
        }

        Log.app.error("Could not open the Settings window")
    }

    @MainActor
    func applicationWillTerminate(_ notification: Notification) {
        environment.stop()
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
    }

    /// The app has no windows of its own to speak of, so closing Settings must
    /// not quit it.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Power

    /// Sleep and wake matter because a paused render loop would otherwise
    /// resume with a delta measured in minutes and fling the charm off screen.
    /// The engine clamps deltas as a backstop; restarting the clock here is the
    /// clean fix.
    @MainActor
    private func registerPowerObservers() {
        let center = NSWorkspace.shared.notificationCenter

        let sleepNames: [Notification.Name] = [
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification
        ]
        let wakeNames: [Notification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification
        ]

        for name in sleepNames {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.environment.overlayManager.handleSystemSleep()
                }
            }
            workspaceObservers.append(observer)
        }

        for name in wakeNames {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.environment.overlayManager.handleSystemWake()
                }
            }
            workspaceObservers.append(observer)
        }
    }
}
