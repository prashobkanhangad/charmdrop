import CoreGraphics

/// Immutable snapshot of everything the overlay needs in order to draw and
/// behave.
///
/// Passing a value type across the SwiftUI/AppKit boundary means the render
/// layer never reads `SettingsManager`, and `Equatable` lets the overlay skip
/// work when an unrelated preference changes.
struct OverlayConfiguration: Equatable {

    var charm: Charm
    var isVisible: Bool

    var charmScale: CGFloat
    var ropeLength: CGFloat
    var ropeThickness: CGFloat
    var ropeOpacity: CGFloat

    var anchorPosition: AnchorPosition
    var customAnchorFraction: CGFloat

    var showOnAllSpaces: Bool
    var showInFullscreenApps: Bool

    var flickStrength: CGFloat
    var dragSensitivity: CGFloat
    var ritualTrigger: RitualTrigger

    var debugOverlayEnabled: Bool

    /// Horizontal anchor as a fraction of screen width.
    var anchorFraction: CGFloat {
        anchorPosition.fraction(custom: customAnchorFraction)
    }

    /// Physics settings derived from the user's preferences. The engine's other
    /// values stay at their tuned defaults.
    var physics: PhysicsConfiguration {
        var configuration = PhysicsConfiguration.default
        configuration.ropeLength = ropeLength
        return configuration
    }

    /// True when a change between two configurations requires the panels to be
    /// torn down and rebuilt rather than merely updated. Window collection
    /// behaviour cannot be changed reliably on a visible panel.
    func requiresPanelRebuild(comparedTo other: OverlayConfiguration) -> Bool {
        showOnAllSpaces != other.showOnAllSpaces
            || showInFullscreenApps != other.showInFullscreenApps
    }
}
