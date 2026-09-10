import CoreGraphics
import Foundation

/// The visual state a ritual wants the charm drawn in on this frame.
///
/// Rituals never touch a layer. They describe an appearance and the render
/// layer composes it with the rope's physics rotation. That indirection is what
/// keeps rituals testable without a window, and what lets a ritual animate the
/// same transform the physics loop rewrites 120 times a second.
struct RitualPresentation: Equatable {

    /// A soft coloured halo around the charm.
    struct Glow: Equatable {
        var red: CGFloat
        var green: CGFloat
        var blue: CGFloat
        var opacity: CGFloat
        var radius: CGFloat

        static func warm(opacity: CGFloat, radius: CGFloat = 18) -> Glow {
            Glow(red: 1.0, green: 0.68, blue: 0.26, opacity: opacity, radius: radius)
        }

        static func cool(opacity: CGFloat, radius: CGFloat = 18) -> Glow {
            Glow(red: 0.35, green: 0.62, blue: 1.0, opacity: opacity, radius: radius)
        }
    }

    /// Which artwork to draw.
    var variant: CharmArtworkVariant = .primary

    /// Multiplier on the charm's size, on top of the user's scale setting.
    var scale: CGFloat = 1

    /// Extra rotation in radians, added to the rope angle.
    var rotationBias: CGFloat = 0

    /// Nil means the charm's ordinary drop shadow.
    var glow: Glow?

    static let neutral = RitualPresentation()

    /// True when nothing needs compositing beyond the artwork itself.
    var isNeutral: Bool {
        scale == 1 && rotationBias == 0 && glow == nil
    }
}

/// The slice of physics a ritual is allowed to touch.
///
/// Narrow on purpose: a ritual can push the charm, but it cannot move
/// particles, repin the anchor or change the configuration. That is why adding
/// rituals cannot destabilise the solver.
protocol RitualPhysicsControlling: AnyObject {
    func applyImpulse(_ impulse: CGVector)
    var charmVelocity: CGVector { get }
}

extension RopePhysicsEngine: RitualPhysicsControlling {
    /// The engine's own method takes an optional index; rituals only ever push
    /// the charm.
    func applyImpulse(_ impulse: CGVector) {
        applyImpulse(impulse, atIndex: nil)
    }
}

/// Everything a ritual can read or affect.
///
/// One context is kept per charm by the overlay controller, which is how a
/// toggle ritual remembers whether the Diya is lit between invocations.
final class RitualContext {

    let charm: Charm
    let physics: RitualPhysicsControlling
    let audio: SoundPlaying

    /// Persists across ritual invocations. Toggle rituals mutate it; the render
    /// layer reads it through `presentation`.
    var variant: CharmArtworkVariant

    /// Reset to neutral before each frame's update, then written by the ritual.
    var presentation: RitualPresentation

    init(
        charm: Charm,
        physics: RitualPhysicsControlling,
        audio: SoundPlaying,
        variant: CharmArtworkVariant = .primary
    ) {
        self.charm = charm
        self.physics = physics
        self.audio = audio
        self.variant = charm.supportedVariant(variant)
        self.presentation = RitualPresentation(variant: self.variant)
    }

    /// Plays the charm's sound, if it declares one and audio is enabled.
    func playCharmSound() {
        guard let name = charm.soundName else { return }
        audio.play(name)
    }
}

/// A short, self-contained charm behaviour.
///
/// Reference type because rituals hold per-invocation state, such as which
/// direction the bell last swung or whether the artwork has been swapped yet.
///
/// Every method has a default no-op implementation, so a new ritual only
/// overrides the phases it cares about.
protocol CharmRitual: AnyObject {

    /// How long the ritual runs. Kept in the 0.5–2s range: long enough to read,
    /// short enough that clicking the charm never feels like waiting.
    var duration: CFTimeInterval { get }

    /// One-shot effects: impulses, sound, artwork swaps.
    func begin(_ context: RitualContext)

    /// Called every frame with `progress` in 0...1. Writes presentation.
    func update(_ context: RitualContext, progress: Double)

    /// Cleanup once `duration` has elapsed.
    func finish(_ context: RitualContext)

    /// Continuous appearance applied when no ritual is running — a lit flame
    /// flickering, for instance. `time` is monotonic seconds.
    func ambient(_ context: RitualContext, time: CFTimeInterval)

    /// Whether `ambient` actually changes anything right now. When false the
    /// overlay is allowed to stop rendering entirely, which is what keeps a
    /// settled charm at zero frames.
    func wantsAmbientFrames(_ context: RitualContext) -> Bool
}

extension CharmRitual {
    func begin(_ context: RitualContext) {}
    func update(_ context: RitualContext, progress: Double) {}
    func finish(_ context: RitualContext) {}
    func ambient(_ context: RitualContext, time: CFTimeInterval) {}
    func wantsAmbientFrames(_ context: RitualContext) -> Bool { false }
}

// MARK: - Easing

/// Shaping functions shared by the built-in rituals.
///
/// Ritual timing is where "polished" is won or lost, so these are centralised
/// rather than open-coded per ritual.
enum RitualEasing {

    /// Rises from 0 to 1 and back to 0 over the full progress range. The basis
    /// of every "pulse and return" effect.
    static func arc(_ progress: Double) -> Double {
        sin(Double.pi * progress.clamped(to: 0...1))
    }

    /// Decelerating ramp from 0 to 1.
    static func easeOut(_ progress: Double) -> Double {
        let clamped = progress.clamped(to: 0...1)
        return 1 - pow(1 - clamped, 3)
    }

    /// Accelerating ramp from 0 to 1.
    static func easeIn(_ progress: Double) -> Double {
        let clamped = progress.clamped(to: 0...1)
        return clamped * clamped * clamped
    }

    /// Overshoots past 1 before settling, giving a springy "pop".
    static func easeOutBack(_ progress: Double, overshoot: Double = 1.7) -> Double {
        let clamped = progress.clamped(to: 0...1)
        let shifted = clamped - 1
        return 1 + (overshoot + 1) * pow(shifted, 3) + overshoot * pow(shifted, 2)
    }

    /// A decaying oscillation, for a strike that rings out.
    static func decayingOscillation(_ progress: Double, cycles: Double, decay: Double) -> Double {
        let clamped = progress.clamped(to: 0...1)
        return sin(2 * Double.pi * cycles * clamped) * exp(-decay * clamped)
    }

    /// Remaps a sub-range of overall progress onto 0...1, for multi-phase
    /// rituals.
    static func phase(_ progress: Double, from start: Double, to end: Double) -> Double {
        guard end > start else { return progress >= end ? 1 : 0 }
        return ((progress - start) / (end - start)).clamped(to: 0...1)
    }
}
