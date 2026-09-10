import AppKit
import CoreGraphics
import Foundation

extension CGPoint {

    static func + (lhs: CGPoint, rhs: CGVector) -> CGPoint {
        CGPoint(x: lhs.x + rhs.dx, y: lhs.y + rhs.dy)
    }

    static func - (lhs: CGPoint, rhs: CGVector) -> CGPoint {
        CGPoint(x: lhs.x - rhs.dx, y: lhs.y - rhs.dy)
    }

    static func - (lhs: CGPoint, rhs: CGPoint) -> CGVector {
        CGVector(dx: lhs.x - rhs.x, dy: lhs.y - rhs.y)
    }

    func distance(to other: CGPoint) -> CGFloat {
        (self - other).length
    }

    var isFinite: Bool { x.isFinite && y.isFinite }
}

extension CGVector {

    static let zero = CGVector(dx: 0, dy: 0)

    var length: CGFloat { (dx * dx + dy * dy).squareRoot() }

    static func * (lhs: CGVector, rhs: CGFloat) -> CGVector {
        CGVector(dx: lhs.dx * rhs, dy: lhs.dy * rhs)
    }

    static func + (lhs: CGVector, rhs: CGVector) -> CGVector {
        CGVector(dx: lhs.dx + rhs.dx, dy: lhs.dy + rhs.dy)
    }

    /// Shortens the vector to `maximum` while preserving direction. Used to keep
    /// a violent flick from destabilising the Verlet integrator.
    func clampedLength(to maximum: CGFloat) -> CGVector {
        let current = length
        guard current > maximum, current > 0 else { return self }
        return self * (maximum / current)
    }

    var isFinite: Bool { dx.isFinite && dy.isFinite }
}

extension CGSize {

    static func * (lhs: CGSize, rhs: CGFloat) -> CGSize {
        CGSize(width: lhs.width * rhs, height: lhs.height * rhs)
    }
}

extension Comparable {

    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

extension NSScreen {

    /// Stable-ish identifier for a physical display. `CGDirectDisplayID` survives
    /// resolution changes, which `NSScreen` instances do not.
    var displayIdentifier: CGDirectDisplayID? {
        guard let number = deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber else { return nil }
        return CGDirectDisplayID(number.uint32Value)
    }
}
