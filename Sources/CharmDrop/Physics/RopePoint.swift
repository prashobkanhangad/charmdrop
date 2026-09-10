import CoreGraphics

/// A single Verlet particle. Velocity is implicit in the gap between
/// `position` and `previousPosition`, which is what makes injecting an impulse
/// a matter of moving history rather than storing a separate velocity term.
struct RopePoint: Equatable {

    var position: CGPoint
    var previousPosition: CGPoint

    /// Pinned points are never moved by integration or constraint solving.
    /// The anchor is permanently pinned; the charm is pinned while dragged.
    var isPinned: Bool

    init(position: CGPoint, previousPosition: CGPoint? = nil, isPinned: Bool = false) {
        self.position = position
        self.previousPosition = previousPosition ?? position
        self.isPinned = isPinned
    }

    /// Implicit velocity in points per second for the given substep length.
    func velocity(timeStep: CGFloat) -> CGVector {
        guard timeStep > 0 else { return .zero }
        return (position - previousPosition) * (1 / timeStep)
    }

    /// Rewrites history so the particle carries `velocity` from the next
    /// substep onwards.
    mutating func setVelocity(_ velocity: CGVector, timeStep: CGFloat) {
        previousPosition = position - (velocity * timeStep)
    }

    /// Drops all momentum without moving the particle.
    mutating func clearVelocity() {
        previousPosition = position
    }
}
