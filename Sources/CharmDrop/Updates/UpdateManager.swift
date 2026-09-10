import AppKit
import Foundation

/// Update checking, behind a protocol so Sparkle can be introduced without the
/// menu bar or settings code changing.
protocol UpdateManaging: AnyObject {
    var isConfigured: Bool { get }
    var canCheckAutomatically: Bool { get }
    func checkForUpdates()
}

/// The shipping default until Sparkle is wired up.
///
/// It deliberately does nothing but explain itself: pointing an updater at a
/// placeholder feed URL would either fail silently or, worse, look like it
/// worked.
///
/// **To enable updates** add the Sparkle 2 Swift package, replace this type with
/// a `SparkleUpdateManager` wrapping `SPUStandardUpdaterController`, and set
/// `SUFeedURL` in `Scripts/Info.plist.template` (currently
/// `SUFeedURL_PLACEHOLDER`). See `DISTRIBUTION.md`.
final class UnconfiguredUpdateManager: UpdateManaging {

    var isConfigured: Bool { false }
    var canCheckAutomatically: Bool { false }

    func checkForUpdates() {
        Log.app.notice("Update check requested but no appcast feed is configured")

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Updates Are Not Configured Yet"
        alert.informativeText = """
        \(Constants.App.displayName) has no update feed set for this build. \
        Configure Sparkle and the appcast URL before distributing, as described \
        in DISTRIBUTION.md.
        """
        alert.addButton(withTitle: "OK")

        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
