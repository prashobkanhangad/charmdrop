import Foundation

/// Source of charm definitions.
///
/// Behind a protocol so a future remote catalog, charm pack, or user-imported
/// charm directory can be dropped in without touching the overlay or menus.
protocol CharmCatalogProviding {
    var charms: [Charm] { get }
    var defaultCharm: Charm { get }
    func charm(withID id: String) -> Charm?
}

extension CharmCatalogProviding {

    /// Resolves an identifier, falling back to the default charm rather than
    /// failing. A stale identifier in user defaults must never leave the app
    /// without a charm.
    func resolve(id: String?) -> Charm {
        guard let id, let match = charm(withID: id) else { return defaultCharm }
        return match
    }
}

/// The charms shipped with the app.
struct BuiltInCharmCatalog: CharmCatalogProviding {

    let charms: [Charm] = [
        Charm(
            id: "nimbu-mirchi",
            displayName: "Nimbu Mirchi",
            assetName: "charm_nimbu_mirchi",
            visualSize: CGSize(width: 90, height: 110),
            defaultRopeLength: 185,
            ritualType: .replace,
            description: "A lemon and chillies strung on a thread. Click to hang a fresh one.",
            hasAlternateArtwork: true
        ),
        Charm(
            id: "nazar",
            displayName: "Nazar",
            assetName: "charm_nazar",
            visualSize: CGSize(width: 84, height: 96),
            defaultRopeLength: 175,
            ritualType: .pulse,
            description: "A blue eye that watches the desktop. Click to make it glow."
        ),
        Charm(
            id: "bell",
            displayName: "Temple Bell",
            assetName: "charm_bell",
            visualSize: CGSize(width: 82, height: 104),
            defaultRopeLength: 165,
            ritualType: .swing,
            soundName: "bell",
            description: "A brass bell. Click to ring it."
        ),
        Charm(
            id: "diya",
            displayName: "Diya",
            assetName: "charm_diya",
            visualSize: CGSize(width: 88, height: 100),
            defaultRopeLength: 190,
            ritualType: .toggle,
            description: "An oil lamp. Click to light it; the flame flickers while lit.",
            hasAlternateArtwork: true
        )
    ]

    var defaultCharm: Charm {
        // The array is a compile-time literal, but avoid a force unwrap so a
        // future edit cannot introduce a launch crash.
        charms.first ?? Charm(
            id: "fallback",
            displayName: Constants.App.displayName,
            assetName: "charm_fallback",
            ritualType: .pulse
        )
    }

    func charm(withID id: String) -> Charm? {
        charms.first { $0.id == id }
    }
}
