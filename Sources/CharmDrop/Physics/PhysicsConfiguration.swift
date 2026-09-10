import CoreGraphics
import Foundation

/// Every tunable number the solver reads. The engine holds one of these and
/// never reaches out to user defaults or view code for values.
struct PhysicsConfiguration: Equatable {

    /// Total resting length of the rope in points.
    var ropeLength: CGFloat = 180

    /// Number of particles, including the pinned anchor and the charm.
    var segmentCount: Int = 15

    /// Downward acceleration in points per second squared. Negative because the
    /// engine works in a y-up coordinate space.
    var gravity: CGVector = CGVector(dx: 0, dy: -900)

    /// Fraction of velocity retained each substep. Below 1 to bleed energy.
    var damping: CGFloat = 0.985

    /// Relaxation passes per substep. More passes make the rope less stretchy.
    var constraintIterations: Int = 8

    /// The solver advances in fixed substeps so behaviour is identical at 60Hz
    /// and 120Hz.
    var fixedTimeStep: CFTimeInterval = 1.0 / 120.0

    /// Upper bound on a single frame's delta. Protects against the enormous
    /// delta produced when the machine wakes from sleep.
    var maximumDeltaTime: CFTimeInterval = 1.0 / 20.0

    /// Cap on substeps per frame so a stalled main thread cannot cause a
    /// runaway catch-up loop.
    var maximumSubstepsPerFrame: Int = 6

    /// Hard ceiling on particle speed in points per second.
    var maximumParticleSpeed: CGFloat = 4000

    /// Energy retained when a particle is pushed back inside the screen bounds.
    var boundaryRestitution: CGFloat = 0.35

    /// Exponential smoothing factor for charm rotation. Higher follows the rope
    /// more tightly; lower removes jitter.
    var rotationSmoothing: CGFloat = 0.35

    /// Resting distance between two adjacent particles.
    var segmentSpacing: CGFloat {
        guard segmentCount > 1 else { return ropeLength }
        return ropeLength / CGFloat(segmentCount - 1)
    }

    static let `default` = PhysicsConfiguration()
}
