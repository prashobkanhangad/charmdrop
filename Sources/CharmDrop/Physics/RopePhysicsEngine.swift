import CoreGraphics
import Foundation

/// Verlet-integrated rope with a pinned anchor at the top and a charm at the
/// bottom.
///
/// The engine is deliberately free of AppKit, Core Animation and settings
/// types. It knows about points, constraints and a rectangle it must stay
/// inside; everything visual is somebody else's problem. That separation is
/// what lets new charms and ropes be added without touching the solver.
///
/// Coordinate space: panel-local, **y-up** (AppKit's default). Gravity is
/// therefore negative on y. Nothing in this file flips coordinates.
final class RopePhysicsEngine {

    // MARK: - Configuration

    var configuration: PhysicsConfiguration {
        didSet {
            guard configuration != oldValue else { return }
            if configuration.segmentCount != oldValue.segmentCount {
                rebuild()
            } else if configuration.ropeLength != oldValue.ropeLength {
                updateConstraintLengths()
            }
        }
    }

    /// Rectangle the simulation must stay within, in panel-local coordinates.
    var bounds: CGRect = .zero

    /// Half-extents of the charm, used to keep it fully on screen.
    var charmHalfExtent: CGSize = CGSize(width: 45, height: 55)

    /// Pinned top of the rope. Setting it moves the anchor without disturbing
    /// the rest of the rope, so dragging the anchor makes the charm trail
    /// behind naturally.
    var anchor: CGPoint = .zero {
        didSet {
            guard !points.isEmpty else { return }
            points[0].position = anchor
            points[0].previousPosition = anchor
        }
    }

    // MARK: - State

    private(set) var points: [RopePoint] = []
    private(set) var constraints: [RopeConstraint] = []

    private(set) var isDragging = false
    private var dragGrabOffset = CGVector.zero

    /// Rotation of the charm in radians, exponentially smoothed to remove the
    /// high-frequency jitter present in the raw segment direction.
    private(set) var charmRotation: CGFloat = 0

    private var timeAccumulator: CFTimeInterval = 0
    private var restFrameCount = 0

    /// True once the rope has been still long enough that rendering can be
    /// throttled. Dragging always counts as awake.
    var isAtRest: Bool { !isDragging && restFrameCount > Self.restFrameThreshold }

    private static let restFrameThreshold = 30
    private static let restSpeedThreshold: CGFloat = 1.2

    // MARK: - Lifecycle

    init(configuration: PhysicsConfiguration = .default) {
        self.configuration = configuration
    }

    /// Lays the rope out straight down from the anchor with zero momentum.
    func reset() {
        rebuild()
    }

    private func rebuild() {
        let count = max(2, configuration.segmentCount)
        let spacing = configuration.segmentSpacing

        points = (0..<count).map { index in
            let position = CGPoint(
                x: anchor.x,
                y: anchor.y - spacing * CGFloat(index)
            )
            return RopePoint(position: position, isPinned: index == 0)
        }

        constraints = (0..<(count - 1)).map { index in
            RopeConstraint(indexA: index, indexB: index + 1, restLength: spacing)
        }

        isDragging = false
        charmRotation = 0
        timeAccumulator = 0
        restFrameCount = 0
    }

    private func updateConstraintLengths() {
        let spacing = configuration.segmentSpacing
        for index in constraints.indices {
            constraints[index].restLength = spacing
        }
        wake()
    }

    /// Clears accumulated frame time. Call after sleep/wake or after the
    /// render loop has been paused, so the first frame back does not integrate
    /// a huge delta.
    func resetTiming() {
        timeAccumulator = 0
    }

    private func wake() {
        restFrameCount = 0
    }

    // MARK: - Queries

    var charmIndex: Int { max(0, points.count - 1) }

    var charmPosition: CGPoint {
        points.last?.position ?? anchor
    }

    /// Rope direction at the charm, unsmoothed. Exposed for debug rendering.
    var rawCharmRotation: CGFloat {
        guard points.count >= 2 else { return 0 }
        return PhysicsMath.charmRotation(
            previous: points[points.count - 2].position,
            last: points[points.count - 1].position
        )
    }

    var charmVelocity: CGVector {
        guard let last = points.last else { return .zero }
        return last.velocity(timeStep: CGFloat(configuration.fixedTimeStep))
    }

    // MARK: - Simulation

    /// Advances the simulation by a wall-clock delta, internally split into
    /// fixed substeps so behaviour is refresh-rate independent.
    func step(deltaTime: CFTimeInterval) {
        guard points.count >= 2, deltaTime > 0 else { return }

        let clamped = min(deltaTime, configuration.maximumDeltaTime)
        timeAccumulator += clamped

        let fixedStep = configuration.fixedTimeStep
        var substeps = 0

        while timeAccumulator >= fixedStep && substeps < configuration.maximumSubstepsPerFrame {
            integrate(timeStep: fixedStep)
            solveConstraints()
            applyBoundaries()
            substeps += 1
            timeAccumulator -= fixedStep
        }

        // Discard any backlog we refused to simulate; catching up later would
        // manifest as a visible lurch.
        if timeAccumulator >= fixedStep {
            timeAccumulator = 0
        }

        if substeps > 0 {
            updateRotation()
            updateRestState()
        }
    }

    private func integrate(timeStep: CFTimeInterval) {
        let dt = CGFloat(timeStep)
        let acceleration = configuration.gravity * (dt * dt)
        let maximumDisplacement = configuration.maximumParticleSpeed * dt

        for index in points.indices where !points[index].isPinned {
            var point = points[index]

            let displacement = (point.position - point.previousPosition)
                .clampedLength(to: maximumDisplacement)

            let next = point.position + (displacement * configuration.damping) + acceleration

            point.previousPosition = point.position
            point.position = PhysicsMath.sanitized(next, fallback: point.position)
            points[index] = point
        }
    }

    private func solveConstraints() {
        for _ in 0..<max(1, configuration.constraintIterations) {
            for constraint in constraints {
                constraint.resolve(in: &points)
            }
            // The anchor is authoritative: re-pin it every pass so accumulated
            // float error cannot let the rope drift off its mount.
            points[0].position = anchor
            points[0].previousPosition = anchor
        }
    }

    /// Keeps the rope, and especially the charm, inside the visible screen.
    private func applyBoundaries() {
        guard !bounds.isEmpty else { return }

        for index in points.indices where !points[index].isPinned {
            let isCharm = index == charmIndex
            let insetX = isCharm ? charmHalfExtent.width : 1
            let insetY = isCharm ? charmHalfExtent.height : 1

            let minX = bounds.minX + insetX
            let maxX = bounds.maxX - insetX
            let minY = bounds.minY + insetY
            let maxY = bounds.maxY - insetY

            guard minX <= maxX, minY <= maxY else { continue }

            var point = points[index]
            let restitution = configuration.boundaryRestitution

            if point.position.x < minX {
                Self.reflect(&point.position.x, &point.previousPosition.x, at: minX, restitution: restitution)
            } else if point.position.x > maxX {
                Self.reflect(&point.position.x, &point.previousPosition.x, at: maxX, restitution: restitution)
            }

            if point.position.y < minY {
                Self.reflect(&point.position.y, &point.previousPosition.y, at: minY, restitution: restitution)
            } else if point.position.y > maxY {
                Self.reflect(&point.position.y, &point.previousPosition.y, at: maxY, restitution: restitution)
            }

            points[index] = point
        }
    }

    /// Places a particle exactly on a wall and reverses the component of its
    /// implicit velocity that was carrying it through, scaled by restitution.
    ///
    /// Because Verlet stores velocity as the gap to the previous position, a
    /// bounce is expressed by rewriting history rather than by negating a
    /// velocity field.
    private static func reflect(
        _ position: inout CGFloat,
        _ previous: inout CGFloat,
        at wall: CGFloat,
        restitution: CGFloat
    ) {
        let incomingVelocity = position - previous
        position = wall
        previous = wall + incomingVelocity * restitution
    }

    private func updateRotation() {
        charmRotation = PhysicsMath.lerpAngle(
            from: charmRotation,
            to: rawCharmRotation,
            factor: configuration.rotationSmoothing
        )
    }

    private func updateRestState() {
        guard !isDragging else {
            restFrameCount = 0
            return
        }

        let dt = CGFloat(configuration.fixedTimeStep)
        var peakSpeed: CGFloat = 0
        for point in points where !point.isPinned {
            peakSpeed = max(peakSpeed, point.velocity(timeStep: dt).length)
        }

        if peakSpeed < Self.restSpeedThreshold {
            restFrameCount += 1
        } else {
            restFrameCount = 0
        }
    }

    // MARK: - Interaction

    /// Starts a drag. `location` is where the pointer grabbed the charm; the
    /// offset between it and the charm centre is preserved so the charm does
    /// not snap under the cursor.
    func beginDrag(at location: CGPoint) {
        guard let charm = points.last else { return }
        isDragging = true
        dragGrabOffset = charm.position - location
        points[charmIndex].isPinned = true
        points[charmIndex].clearVelocity()
        wake()
    }

    /// Moves only the charm particle. The rest of the rope catches up through
    /// constraint solving, which is what makes dragging feel like rope rather
    /// than a rigid stick.
    func updateDrag(to location: CGPoint) {
        guard isDragging, !points.isEmpty else { return }
        let target = location + dragGrabOffset
        points[charmIndex].position = PhysicsMath.sanitized(
            target,
            fallback: points[charmIndex].position
        )
        points[charmIndex].clearVelocity()
        wake()
    }

    /// Releases the charm, converting pointer velocity into Verlet history.
    func endDrag(velocity: CGVector) {
        guard isDragging else { return }
        isDragging = false
        points[charmIndex].isPinned = false

        let safe = velocity.isFinite ? velocity : .zero
        points[charmIndex].setVelocity(
            safe.clampedLength(to: configuration.maximumParticleSpeed),
            timeStep: CGFloat(configuration.fixedTimeStep)
        )
        wake()
    }

    /// Adds velocity to a particle. Used by rituals and by the "flick" menu
    /// command; index defaults to the charm.
    func applyImpulse(_ impulse: CGVector, atIndex index: Int? = nil) {
        let target = index ?? charmIndex
        guard points.indices.contains(target), !points[target].isPinned else { return }

        let dt = CGFloat(configuration.fixedTimeStep)
        let combined = points[target].velocity(timeStep: dt) + impulse
        points[target].setVelocity(
            combined.clampedLength(to: configuration.maximumParticleSpeed),
            timeStep: dt
        )
        wake()
    }
}
