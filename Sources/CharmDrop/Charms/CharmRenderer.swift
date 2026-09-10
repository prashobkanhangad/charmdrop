import AppKit
import CoreGraphics

/// Supplies charm artwork. Implementations may load from the bundle, generate
/// it, or later fetch user-imported files.
protocol CharmArtworkProviding {
    func image(for charm: Charm, variant: CharmArtworkVariant, pixelScale: CGFloat) -> CGImage?
}

/// Loads artwork from the app bundle by asset name.
struct BundledCharmArtwork: CharmArtworkProviding {

    func image(for charm: Charm, variant: CharmArtworkVariant, pixelScale: CGFloat) -> CGImage? {
        guard let name = charm.assetName(for: variant),
              let image = NSImage(named: name)
        else { return nil }

        var rect = CGRect(origin: .zero, size: charm.visualSize)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}

/// Resolves and caches the rasterised artwork used by the overlay layer.
///
/// Bundled assets win; generated placeholders are the fallback. Because both
/// paths are behind `CharmArtworkProviding`, dropping real PNGs into the bundle
/// later requires no code change at all.
final class CharmRenderer {

    private let providers: [CharmArtworkProviding]
    private var cache: [CacheKey: CGImage] = [:]

    private struct CacheKey: Hashable {
        let charmID: String
        let variant: CharmArtworkVariant
        /// Quantised so tiny scale differences do not defeat the cache.
        let scaleBucket: Int
    }

    init(providers: [CharmArtworkProviding] = [BundledCharmArtwork(), PlaceholderCharmArtwork()]) {
        self.providers = providers
    }

    /// Returns artwork for `charm` rasterised for a display with the given
    /// backing scale factor. Never throws; a nil result simply means the charm
    /// draws nothing, which the overlay tolerates.
    ///
    /// A variant the charm does not declare resolves to `.primary` rather than
    /// returning nil, so a stale toggle state can never blank the charm.
    func image(
        for charm: Charm,
        variant: CharmArtworkVariant = .primary,
        pixelScale: CGFloat
    ) -> CGImage? {
        let variant = charm.supportedVariant(variant)
        let key = CacheKey(
            charmID: charm.id,
            variant: variant,
            scaleBucket: Int((pixelScale * 100).rounded())
        )
        if let cached = cache[key] { return cached }

        for provider in providers {
            if let image = provider.image(for: charm, variant: variant, pixelScale: pixelScale) {
                cache[key] = image
                return image
            }
        }

        Log.charms.error(
            "No artwork available for charm \(charm.id, privacy: .public) variant \(variant.rawValue, privacy: .public)"
        )

        // A missing alternate must not leave the charm invisible mid-ritual.
        if variant != .primary {
            return self.image(for: charm, variant: .primary, pixelScale: pixelScale)
        }
        return nil
    }

    func invalidateCache() {
        cache.removeAll()
    }
}
