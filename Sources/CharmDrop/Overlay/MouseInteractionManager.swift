import AppKit
import Foundation

/// Tracks the pointer so the overlay can switch between click-through and
/// interactive.
///
/// Polling `NSEvent.mouseLocation` rather than installing event monitors is a
/// deliberate choice:
///
/// * A *global* monitor never sees events that are delivered to our own
///   process, so the moment the overlay became interactive we would stop
///   hearing about movement and could never detect the pointer leaving.
/// * A *local* monitor is unreliable for a non-activating panel belonging to an
///   inactive app, which is the overlay's normal state.
/// * `NSEvent.mouseLocation` needs no Accessibility permission and is a cheap
///   window-server query.
///
/// The poll only runs while a charm is actually on screen.
final class MouseInteractionManager {

    /// Called with the pointer position in global screen coordinates.
    var onPointerMoved: ((CGPoint) -> Void)?

    /// 30Hz is imperceptible for a hover transition and costs far less than a
    /// display-synced poll.
    private let interval: TimeInterval = 1.0 / 30.0

    private var timer: Timer?
    private var lastLocation: CGPoint?

    private(set) var isTracking = false

    deinit {
        stop()
    }

    func start() {
        guard !isTracking else { return }
        isTracking = true

        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        // Tolerance lets the OS coalesce our wakeups with other timers, which
        // matters for battery life.
        timer.tolerance = interval * 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastLocation = nil
        isTracking = false
    }

    private func poll() {
        let location = NSEvent.mouseLocation
        guard location.isFinite else { return }

        // Skip the notification entirely when the pointer has not moved.
        if let lastLocation,
           abs(lastLocation.x - location.x) < 0.5,
           abs(lastLocation.y - location.y) < 0.5 {
            return
        }

        lastLocation = location
        onPointerMoved?(location)
    }

    /// Forces the next poll to report, even if the pointer has not moved. Used
    /// after the charm itself moves under a stationary pointer.
    func invalidateCachedLocation() {
        lastLocation = nil
    }
}

/// Rolling window of pointer samples used to estimate release velocity.
///
/// Old samples are discarded so pausing mid-drag before letting go produces a
/// gentle drop rather than replaying a stale flick.
struct PointerVelocityTracker {

    private struct Sample {
        let location: CGPoint
        let timestamp: CFTimeInterval
    }

    private var samples: [Sample] = []
    private let capacity: Int
    private let maximumAge: CFTimeInterval

    init(
        capacity: Int = Constants.Interaction.velocitySampleCount,
        maximumAge: CFTimeInterval = Constants.Interaction.velocitySampleMaxAge
    ) {
        self.capacity = max(2, capacity)
        self.maximumAge = maximumAge
    }

    mutating func reset() {
        samples.removeAll(keepingCapacity: true)
    }

    mutating func record(_ location: CGPoint, at timestamp: CFTimeInterval) {
        samples.append(Sample(location: location, timestamp: timestamp))
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }

    /// Average velocity in points per second over the recent samples, or zero
    /// when there is not enough recent movement to be meaningful.
    func velocity(at timestamp: CFTimeInterval) -> CGVector {
        guard let latest = samples.last else { return .zero }
        guard timestamp - latest.timestamp <= maximumAge else { return .zero }

        let recent = samples.filter { latest.timestamp - $0.timestamp <= maximumAge }
        guard let oldest = recent.first, recent.count >= 2 else { return .zero }

        let elapsed = latest.timestamp - oldest.timestamp
        guard elapsed > 0.0001 else { return .zero }

        let displacement = latest.location - oldest.location
        return displacement * (1 / CGFloat(elapsed))
    }
}
