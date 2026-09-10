import AppKit
import Combine

/// Tracks the connected displays and resolves which of them should host an
/// overlay.
///
/// `NSScreen` objects are recreated when the display arrangement changes, so
/// nothing here holds on to one; screens are always looked up fresh and
/// identified by `CGDirectDisplayID`.
final class ScreenManager {

    /// Emits whenever displays are added, removed, rearranged, or change
    /// resolution.
    let screensDidChange = PassthroughSubject<Void, Never>()

    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Log.screens.info("Display configuration changed: \(NSScreen.screens.count) screen(s)")
            self?.screensDidChange.send()
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    var allScreens: [NSScreen] { NSScreen.screens }

    func screen(withNumber number: Int) -> NSScreen? {
        guard number != 0 else { return nil }
        return NSScreen.screens.first { $0.displayIdentifier == CGDirectDisplayID(number) }
    }

    /// The displays that should currently show a charm.
    ///
    /// Falls back to the main display when a specifically chosen display has
    /// been disconnected, so the charm relocates instead of vanishing.
    func targetScreens(selection: ScreenSelection, selectedScreenNumber: Int) -> [NSScreen] {
        switch selection {
        case .all:
            return allScreens
        case .main:
            return [NSScreen.main].compactMap { $0 }
        case .specific:
            if let match = screen(withNumber: selectedScreenNumber) {
                return [match]
            }
            Log.screens.notice("Selected display unavailable; falling back to the main display")
            return [NSScreen.main].compactMap { $0 }
        }
    }
}
