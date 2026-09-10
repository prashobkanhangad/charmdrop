import CoreGraphics

/// A distance constraint between two particles, solved by shifting both toward
/// or away from each other until they sit `restLength` apart.
///
/// Kept as a standalone type so future rope variants (elastic ropes, chains
/// with differing link lengths, multi-charm ropes) can supply their own
/// constraint lists without the solver changing.
struct RopeConstraint: Equatable {

    let indexA: Int
    let indexB: Int
    var restLength: CGFloat

    /// 0 = fully slack, 1 = fully rigid. Values below 1 make the rope stretchy.
    var stiffness: CGFloat = 1.0

    /// Moves the two referenced particles toward their rest separation.
    /// Pinned particles absorb none of the correction, so their partner takes
    /// the whole of it.
    func resolve(in points: inout [RopePoint]) {
        guard points.indices.contains(indexA), points.indices.contains(indexB) else { return }

        var a = points[indexA]
        var b = points[indexB]

        let delta = b.position - a.position
        let distance = delta.length

        // Coincident particles have no defined direction to separate along.
        // Nudging on a fixed axis lets the next iteration recover instead of
        // producing NaN.
        guard distance > 0.0001 else {
            if !b.isPinned {
                points[indexB].position.y -= restLength * 0.5
            } else if !a.isPinned {
                points[indexA].position.y += restLength * 0.5
            }
            return
        }

        let difference = (distance - restLength) / distance
        let correction = delta * (difference * 0.5 * stiffness)

        switch (a.isPinned, b.isPinned) {
        case (true, true):
            return
        case (true, false):
            b.position = b.position - (correction * 2)
        case (false, true):
            a.position = a.position + (correction * 2)
        case (false, false):
            a.position = a.position + correction
            b.position = b.position - correction
        }

        points[indexA] = a
        points[indexB] = b
    }
}
