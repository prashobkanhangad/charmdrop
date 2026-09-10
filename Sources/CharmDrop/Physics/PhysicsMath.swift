import CoreGraphics
import Foundation

/// Small numeric helpers shared by the solver and the renderer.
enum PhysicsMath {

    /// Wraps an angle into `-π...π`, so smoothing across the ±π seam does not
    /// spin the charm the long way round.
    static func normalizeAngle(_ angle: CGFloat) -> CGFloat {
        var result = angle.remainder(dividingBy: 2 * .pi)
        if result > .pi { result -= 2 * .pi }
        if result < -.pi { result += 2 * .pi }
        return result
    }

    /// Shortest signed rotation from `from` to `to`.
    static func angleDelta(from: CGFloat, to: CGFloat) -> CGFloat {
        normalizeAngle(to - from)
    }

    /// Interpolates between two angles along the shorter arc.
    static func lerpAngle(from: CGFloat, to: CGFloat, factor: CGFloat) -> CGFloat {
        normalizeAngle(from + angleDelta(from: from, to: to) * factor.clamped(to: 0...1))
    }

    /// Rotation of a charm hanging from a rope whose last segment runs from
    /// `previous` to `last`.
    ///
    /// A charm asset is authored hanging straight down, which corresponds to a
    /// segment direction of `(0, -1)`. Adding π/2 makes that orientation read as
    /// zero rotation, so `rotationOffset` values in charm metadata stay
    /// intuitive.
    static func charmRotation(previous: CGPoint, last: CGPoint) -> CGFloat {
        let delta = last - previous
        guard delta.length > 0.0001 else { return 0 }
        return normalizeAngle(atan2(delta.dy, delta.dx) + .pi / 2)
    }

    /// Replaces a non-finite value with a fallback. Cheap insurance against a
    /// single NaN poisoning the whole simulation.
    static func sanitized(_ value: CGFloat, fallback: CGFloat = 0) -> CGFloat {
        value.isFinite ? value : fallback
    }

    static func sanitized(_ point: CGPoint, fallback: CGPoint) -> CGPoint {
        point.isFinite ? point : fallback
    }
}
