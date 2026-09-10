import AppKit
import QuartzCore

/// Display-synchronised animation clock.
///
/// Uses `CADisplayLink` (available on macOS 14+ via `NSView.displayLink`) so
/// the rope is stepped once per frame on 60Hz, 120Hz and ProMotion panels
/// alike, and pauses automatically when the display sleeps. A timer-based
/// fallback exists only for the case where the view has no window yet.
final class DisplayLoop {

    /// Called once per frame with the elapsed wall-clock time since the
    /// previous frame.
    var onFrame: ((CFTimeInterval) -> Void)?

    private(set) var isRunning = false

    /// Smoothed frames per second, for the debug overlay.
    private(set) var framesPerSecond: Double = 0

    private var displayLink: CADisplayLink?
    private var fallbackTimer: Timer?
    private var lastTimestamp: CFTimeInterval = 0

    /// `CADisplayLink` retains its target, so the loop is reached through a
    /// weak proxy to avoid a retain cycle with the owning view/controller.
    private final class Proxy: NSObject {
        weak var loop: DisplayLoop?

        @objc func handleFrame(_ sender: Any) {
            loop?.tick(timestamp: (sender as? CADisplayLink)?.timestamp ?? CACurrentMediaTime())
        }

        @objc func handleTimer(_ timer: Timer) {
            loop?.tick(timestamp: CACurrentMediaTime())
        }
    }

    private lazy var proxy: Proxy = {
        let proxy = Proxy()
        proxy.loop = self
        return proxy
    }()

    deinit {
        invalidate()
    }

    /// Starts the loop, driven by the display that `view` currently occupies.
    func start(in view: NSView) {
        guard !isRunning else { return }
        resetTiming()

        if view.window != nil {
            let link = view.displayLink(target: proxy, selector: #selector(Proxy.handleFrame(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else {
            Log.overlay.notice("View has no window; using timer fallback for the render loop")
            startFallbackTimer()
        }

        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        invalidate()
        isRunning = false
        framesPerSecond = 0
    }

    /// Forgets the previous frame's timestamp. Call after a pause, a
    /// sleep/wake cycle, or a display change so the next frame does not
    /// integrate a huge delta.
    func resetTiming() {
        lastTimestamp = 0
    }

    private func startFallbackTimer() {
        let timer = Timer(
            timeInterval: 1.0 / 60.0,
            target: proxy,
            selector: #selector(Proxy.handleTimer(_:)),
            userInfo: nil,
            repeats: true
        )
        timer.tolerance = 1.0 / 240.0
        RunLoop.main.add(timer, forMode: .common)
        fallbackTimer = timer
    }

    private func invalidate() {
        displayLink?.invalidate()
        displayLink = nil
        fallbackTimer?.invalidate()
        fallbackTimer = nil
    }

    private func tick(timestamp: CFTimeInterval) {
        defer { lastTimestamp = timestamp }

        // First frame after a start or reset has no meaningful delta.
        guard lastTimestamp > 0 else { return }

        let delta = timestamp - lastTimestamp
        guard delta > 0 else { return }

        if delta < 0.5 {
            let instantaneous = 1.0 / delta
            framesPerSecond = framesPerSecond == 0
                ? instantaneous
                : framesPerSecond * 0.9 + instantaneous * 0.1
        }

        onFrame?(delta)
    }
}
