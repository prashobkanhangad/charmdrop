import Foundation

/// Which piece of artwork a charm is currently showing.
///
/// Two states cover every built-in ritual: an unlit and a lit Diya, a dried and
/// a fresh Nimbu Mirchi. Charms that never change appearance simply declare no
/// alternate and always render `.primary`.
///
/// Deliberately not an open-ended string. A closed set means the artwork cache,
/// the placeholder generator and the asset naming convention all stay
/// exhaustive, and a typo cannot silently produce a blank charm.
enum CharmArtworkVariant: String, CaseIterable, Codable {
    case primary
    case alternate

    /// The other variant. Toggle rituals are the main caller.
    var toggled: CharmArtworkVariant {
        self == .primary ? .alternate : .primary
    }

    /// Suffix appended to a charm's `assetName` when looking up bundled art.
    var assetNameSuffix: String {
        switch self {
        case .primary: return ""
        case .alternate: return "_alt"
        }
    }
}
