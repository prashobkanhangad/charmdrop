import CoreGraphics
import Foundation

/// What kind of short animation a charm performs when its ritual is invoked.
/// The behaviour itself lives in the ritual engine (a later module); this is
/// metadata only, which keeps charm definitions declarative.
enum RitualType: String, Codable, CaseIterable {
    /// Swap the artwork for a "refreshed" variant.
    case replace
    /// Scale up briefly with a soft glow.
    case pulse
    /// Strong horizontal impulse, optionally with a sound.
    case swing
    /// Flip between two persistent visual states.
    case toggle
}

enum CharmCategory: String, Codable, CaseIterable {
    case traditional
    case seasonal
    case custom
}

/// A charm definition. Purely declarative data: no rendering, no physics, no
/// behaviour. Adding a charm means adding one of these to the catalog.
struct Charm: Identifiable, Equatable, Codable {

    let id: String
    let displayName: String

    /// Image name looked up in the app bundle. When absent, the renderer falls
    /// back to generated placeholder artwork keyed on `id`.
    let assetName: String
    let thumbnailName: String?

    /// Untransformed on-screen size in points, before the user's scale slider.
    let visualSize: CGSize

    let defaultScale: CGFloat
    let defaultRopeLength: CGFloat

    /// Additional rotation in radians applied on top of the rope angle, for
    /// artwork that is not authored hanging straight down.
    let rotationOffset: CGFloat

    /// Mouse hitbox, normally the visual size plus padding.
    let hitboxSize: CGSize

    let ritualType: RitualType
    let soundName: String?
    let category: CharmCategory
    let description: String

    /// Whether the charm has a second appearance, used by rituals that swap or
    /// toggle artwork. Charms without one always render `.primary`.
    let hasAlternateArtwork: Bool

    init(
        id: String,
        displayName: String,
        assetName: String,
        thumbnailName: String? = nil,
        visualSize: CGSize = CGSize(width: 90, height: 110),
        defaultScale: CGFloat = 1.0,
        defaultRopeLength: CGFloat = 180,
        rotationOffset: CGFloat = 0,
        hitboxSize: CGSize? = nil,
        ritualType: RitualType,
        soundName: String? = nil,
        category: CharmCategory = .traditional,
        description: String = "",
        hasAlternateArtwork: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.assetName = assetName
        self.thumbnailName = thumbnailName
        self.visualSize = visualSize
        self.defaultScale = defaultScale
        self.defaultRopeLength = defaultRopeLength
        self.rotationOffset = rotationOffset
        self.hitboxSize = hitboxSize ?? CGSize(
            width: visualSize.width + Constants.Overlay.hitboxPadding.width,
            height: visualSize.height + Constants.Overlay.hitboxPadding.height
        )
        self.ritualType = ritualType
        self.soundName = soundName
        self.category = category
        self.description = description
        self.hasAlternateArtwork = hasAlternateArtwork
    }

    /// Bundled asset name for a variant, or nil when the charm has no such
    /// variant. Callers fall back to `.primary`.
    func assetName(for variant: CharmArtworkVariant) -> String? {
        switch variant {
        case .primary:
            return assetName
        case .alternate:
            return hasAlternateArtwork ? assetName + variant.assetNameSuffix : nil
        }
    }

    /// The variants this charm can actually display.
    var availableVariants: [CharmArtworkVariant] {
        hasAlternateArtwork ? [.primary, .alternate] : [.primary]
    }

    /// Clamps a variant to one the charm supports, so a stale toggle state
    /// cannot ask for artwork that does not exist.
    func supportedVariant(_ variant: CharmArtworkVariant) -> CharmArtworkVariant {
        availableVariants.contains(variant) ? variant : .primary
    }

    /// Visual size after applying a user scale factor.
    func scaledVisualSize(_ scale: CGFloat) -> CGSize {
        visualSize * scale
    }

    /// Hitbox after applying a user scale factor. Padding is not scaled, so
    /// small charms stay comfortably clickable.
    func scaledHitboxSize(_ scale: CGFloat) -> CGSize {
        CGSize(
            width: visualSize.width * scale + Constants.Overlay.hitboxPadding.width,
            height: visualSize.height * scale + Constants.Overlay.hitboxPadding.height
        )
    }
}
