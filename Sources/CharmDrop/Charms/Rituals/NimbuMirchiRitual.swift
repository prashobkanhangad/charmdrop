import CoreGraphics
import Foundation

/// Nimbu Mirchi: the old charm twists away and shrinks out, and a fresh one
/// pops back in its place.
///
/// Two phases with the artwork swapped at the seam, which is what sells it as a
/// replacement rather than as the same charm wobbling.
final class NimbuMirchiRitual: CharmRitual {

    let duration: CFTimeInterval = 0.85

    /// Progress at which the old charm is fully shrunk and the swap happens.
    private let swapProgress = 0.42

    private let shrinkScale: CGFloat = 0.62
    private let twistRadians: CGFloat = 0.42

    private var hasSwapped = false

    func begin(_ context: RitualContext) {
        hasSwapped = false
        context.physics.applyImpulse(CGVector(dx: 210, dy: 40))
        context.playCharmSound()
    }

    func update(_ context: RitualContext, progress: Double) {
        if progress < swapProgress {
            // Phase one: twist and shrink out.
            let phase = CGFloat(RitualEasing.easeIn(
                RitualEasing.phase(progress, from: 0, to: swapProgress)
            ))
            context.presentation.scale = 1 - (1 - shrinkScale) * phase
            context.presentation.rotationBias = twistRadians * phase
            return
        }

        if !hasSwapped {
            hasSwapped = true
            // The charm genuinely changes here: the variant persists after the
            // ritual, so the next click swaps it back.
            context.variant = context.charm.supportedVariant(context.variant.toggled)
        }

        // Phase two: pop back with an overshoot, untwisting as it goes.
        let phase = RitualEasing.phase(progress, from: swapProgress, to: 1)
        let popped = CGFloat(RitualEasing.easeOutBack(phase, overshoot: 2.1))
        context.presentation.scale = shrinkScale + (1 - shrinkScale) * popped
        context.presentation.rotationBias = twistRadians * CGFloat(1 - phase) * -1

        // A brief flash of freshness as the new charm lands.
        let flash = CGFloat(RitualEasing.arc(phase)) * 0.4
        context.presentation.glow = .warm(opacity: flash, radius: 12)
    }

    func finish(_ context: RitualContext) {
        // Guard against a ritual that was cut short before the swap frame.
        if !hasSwapped {
            context.variant = context.charm.supportedVariant(context.variant.toggled)
            hasSwapped = true
        }
    }
}
