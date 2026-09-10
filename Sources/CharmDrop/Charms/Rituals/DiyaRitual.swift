import CoreGraphics
import Foundation

/// Diya: clicking lights or extinguishes the lamp, and the flame flickers for
/// as long as it stays lit.
///
/// The only built-in ritual with a persistent result and a continuous ambient
/// effect. The lit state lives on the context, so it survives the ritual
/// ending and is what `ambient` keys off.
final class DiyaRitual: CharmRitual {

    let duration: CFTimeInterval = 0.55

    private let litScalePop: CGFloat = 1.07

    func begin(_ context: RitualContext) {
        context.variant = context.charm.supportedVariant(context.variant.toggled)
        context.playCharmSound()
        // Lighting a lamp should barely disturb it.
        context.physics.applyImpulse(CGVector(dx: 90, dy: 20))
    }

    func update(_ context: RitualContext, progress: Double) {
        let arc = CGFloat(RitualEasing.arc(progress))
        context.presentation.scale = 1 + (litScalePop - 1) * arc

        if isLit(context) {
            // Catching light: ramps up and stays up, handing over to `ambient`.
            let ramp = CGFloat(RitualEasing.easeOut(progress))
            context.presentation.glow = .warm(
                opacity: Self.baseGlowOpacity * ramp,
                radius: Self.baseGlowRadius
            )
        } else {
            // Being snuffed out: the glow falls away.
            let fade = CGFloat(1 - RitualEasing.easeOut(progress))
            context.presentation.glow = .warm(
                opacity: Self.baseGlowOpacity * fade,
                radius: Self.baseGlowRadius
            )
        }
    }

    /// Flame flicker. Three detuned sines beat against each other, which reads
    /// as organic where a single sine reads as a pulsing LED.
    func ambient(_ context: RitualContext, time: CFTimeInterval) {
        guard isLit(context) else { return }

        let t = Double(time)
        let flicker = 0.70
            + 0.16 * sin(t * 11.3)
            + 0.09 * sin(t * 17.7 + 1.3)
            + 0.05 * sin(t * 29.1 + 0.7)

        let normalised = CGFloat(flicker.clamped(to: 0.35...1.0))

        context.presentation.glow = .warm(
            opacity: Self.baseGlowOpacity * normalised,
            radius: Self.baseGlowRadius * (0.82 + 0.28 * normalised)
        )
        // A barely-there breathing motion. Any more and it looks like the charm
        // itself is throbbing rather than the flame guttering.
        context.presentation.scale = 1 + 0.012 * normalised
    }

    func wantsAmbientFrames(_ context: RitualContext) -> Bool {
        isLit(context)
    }

    private func isLit(_ context: RitualContext) -> Bool {
        context.variant == .alternate
    }

    private static let baseGlowOpacity: CGFloat = 0.9
    private static let baseGlowRadius: CGFloat = 20
}
