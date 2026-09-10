import CoreGraphics
import Foundation

/// Temple Bell: a hard shove, a ring, then a lighter shove back the other way
/// so it reads as ringing rather than as being pushed once.
final class BellRitual: CharmRitual {

    let duration: CFTimeInterval = 1.4

    private let strikeImpulse: CGFloat = 840
    /// The return swing is weaker; the physics is already carrying the bell
    /// back, so this only reinforces it.
    private let returnImpulse: CGFloat = 520

    /// Fraction of the ritual at which the bell is pushed back.
    private let returnImpulseProgress = 0.42

    private var direction: CGFloat = 1
    private var hasAppliedReturnImpulse = false

    func begin(_ context: RitualContext) {
        hasAppliedReturnImpulse = false
        // Swing away from wherever it is already heading, so a second click
        // during the ring adds energy instead of cancelling it.
        if context.physics.charmVelocity.dx > 40 {
            direction = -1
        } else if context.physics.charmVelocity.dx < -40 {
            direction = 1
        }

        context.physics.applyImpulse(CGVector(dx: strikeImpulse * direction, dy: 0))
        context.playCharmSound()
    }

    func update(_ context: RitualContext, progress: Double) {
        if !hasAppliedReturnImpulse, progress >= returnImpulseProgress {
            hasAppliedReturnImpulse = true
            context.physics.applyImpulse(CGVector(dx: -returnImpulse * direction, dy: 0))
        }

        // A brief squash on the strike, ringing out with the sound.
        let ring = RitualEasing.decayingOscillation(progress, cycles: 2.5, decay: 5.5)
        context.presentation.scale = 1 + CGFloat(ring) * 0.045

        // The brass catches a little light as it moves.
        let sheen = CGFloat(RitualEasing.arc(progress)) * 0.35
        context.presentation.glow = .warm(opacity: sheen, radius: 12)
    }

    func finish(_ context: RitualContext) {
        direction *= -1
    }
}
