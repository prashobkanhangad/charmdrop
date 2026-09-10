import CoreGraphics
import Foundation

/// Centralised, non-tunable constants. Anything the user can change belongs in
/// `SettingsManager`; anything the physics solver reads belongs in
/// `PhysicsConfiguration`.
enum Constants {

    enum App {
        /// Product name is referenced in one place so renaming stays cheap.
        static let displayName = "CharmDrop"
        static let urlScheme = "charmdrop"
        static let bundleIdentifier = "com.company.charmdrop"
    }

    enum Overlay {
        /// Extra padding added around the charm's visual bounds to form the
        /// mouse hitbox. See `Charm.hitboxSize`.
        static let hitboxPadding = CGSize(width: 30, height: 30)
    }

    enum Rope {
        static let defaultThickness: CGFloat = 2
        static let defaultOpacity: CGFloat = 0.85
        static let minimumLength: CGFloat = 100
        static let maximumLength: CGFloat = 300
    }

    enum CharmScale {
        static let minimum: CGFloat = 0.7
        static let maximum: CGFloat = 1.5
    }

    enum Interaction {
        /// Number of recent mouse samples retained for release-velocity
        /// estimation.
        static let velocitySampleCount = 8

        /// Samples older than this are ignored so a pause before release
        /// produces a gentle drop rather than a stale flick.
        static let velocitySampleMaxAge: CFTimeInterval = 0.09

        static let minimumFlickStrength: CGFloat = 0.2
        static let maximumFlickStrength: CGFloat = 2.0
    }
}
