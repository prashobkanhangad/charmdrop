import CoreGraphics
import Foundation

/// Nazar: the eye briefly opens wider and glows blue, then settles.
///
/// A watchful charm should feel like it noticed you, so the impulse is small
/// and the emphasis is on the glow rather than on movement.
final class NazarRitual: CharmRitual {

    let duration: CFTimeInterval = 0.75

    private let peakScale: CGFloat = 1.12
    private let peakGlowOpacity: CGFloat = 0.85

    /// Alternates so repeated clicks do not always nudge the same way.
    private var nextImpulseDirection: CGFloat = 1

    func begin(_ context: RitualContext) {
        context.physics.applyImpulse(CGVector(dx: 165 * nextImpulseDirection, dy: 30))
        nextImpulseDirection *= -1
        context.playCharmSound()
    }

    func update(_ context: RitualContext, progress: Double) {
        let arc = CGFloat(RitualEasing.arc(progress))

        context.presentation.scale = 1 + (peakScale - 1) * arc
        context.presentation.glow = .cool(
            opacity: peakGlowOpacity * arc,
            radius: 14 + 10 * arc
        )
    }
}
