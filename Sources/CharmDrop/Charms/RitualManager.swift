import CoreGraphics
import Foundation

/// Runs charm rituals as time-based state machines advanced by the render loop.
///
/// Rituals are **not** `CAAnimation`s. The overlay's display loop rewrites the
/// charm's transform every frame with implicit animations disabled, so a Core
/// Animation animation on that property would be overwritten immediately.
/// Instead a ritual is stepped with the same delta as the physics and produces
/// a `RitualPresentation` the render layer composes with the rope's rotation.
/// One clock, one writer, no fighting.
///
/// One manager per overlay controller, so each display's charm animates
/// independently and rituals keep their own per-invocation state.
final class RitualManager {

    private let rituals: [RitualType: CharmRitual]

    private var activeRitual: CharmRitual?
    private var elapsed: CFTimeInterval = 0
    private var ambientTime: CFTimeInterval = 0

    init(rituals: [RitualType: CharmRitual]? = nil) {
        self.rituals = rituals ?? Self.makeBuiltInRituals()
    }

    /// Fresh instances per manager, because rituals carry state such as which
    /// way the bell last swung.
    static func makeBuiltInRituals() -> [RitualType: CharmRitual] {
        [
            .pulse: NazarRitual(),
            .swing: BellRitual(),
            .replace: NimbuMirchiRitual(),
            .toggle: DiyaRitual()
        ]
    }

    var isPerforming: Bool { activeRitual != nil }

    /// The ritual registered for a charm, or nil when its type has no
    /// implementation. An unregistered type is a no-op, never a crash.
    func ritual(for charm: Charm) -> CharmRitual? {
        rituals[charm.ritualType]
    }

    // MARK: - Control

    /// Starts the charm's ritual, restarting it if one is already running.
    ///
    /// Restarting rather than ignoring keeps repeated clicks feeling
    /// responsive: hitting the bell twice should ring it twice.
    func perform(_ context: RitualContext) {
        guard let ritual = ritual(for: context.charm) else {
            Log.charms.notice(
                "No ritual registered for type \(context.charm.ritualType.rawValue, privacy: .public)"
            )
            return
        }

        if let activeRitual {
            activeRitual.finish(context)
        }

        activeRitual = ritual
        elapsed = 0
        ritual.begin(context)

        Log.charms.info(
            "Performing \(context.charm.ritualType.rawValue, privacy: .public) ritual for \(context.charm.id, privacy: .public), \(ritual.duration, format: .fixed(precision: 2))s"
        )
    }

    /// Ends any ritual in progress without running the remaining frames. Used
    /// when the charm changes underneath a running ritual.
    func reset(_ context: RitualContext?) {
        if let activeRitual, let context {
            activeRitual.finish(context)
        }
        activeRitual = nil
        elapsed = 0
    }

    // MARK: - Per-frame

    /// Advances the active ritual, or applies the charm's ambient effect when
    /// none is running. Writes `context.presentation`.
    func update(_ context: RitualContext, deltaTime: CFTimeInterval) {
        ambientTime += max(0, deltaTime)

        // Each frame starts from a clean slate, so a ritual only has to
        // describe the current frame rather than undo the previous one.
        context.presentation = RitualPresentation()

        if let active = activeRitual {
            elapsed += max(0, deltaTime)
            let progress = active.duration > 0
                ? min(1, elapsed / active.duration)
                : 1

            active.update(context, progress: progress)

            if elapsed >= active.duration {
                active.finish(context)
                activeRitual = nil
                elapsed = 0
                // Hand straight over to the ambient effect, otherwise a charm
                // with one (a lit Diya) flashes neutral for a single frame.
                applyAmbient(context)
            }
        } else {
            applyAmbient(context)
        }

        // The context is the authority on which artwork is showing, so rituals
        // never have to remember to publish it.
        context.presentation.variant = context.charm.supportedVariant(context.variant)
    }

    private func applyAmbient(_ context: RitualContext) {
        ritual(for: context.charm)?.ambient(context, time: ambientTime)
    }

    /// Whether the overlay must keep rendering frames.
    ///
    /// This is what allows a settled charm to cost nothing: only a running
    /// ritual or a live ambient effect (a flickering flame) keeps the display
    /// link alive.
    func wantsContinuousFrames(_ context: RitualContext) -> Bool {
        if isPerforming { return true }
        return ritual(for: context.charm)?.wantsAmbientFrames(context) ?? false
    }
}
