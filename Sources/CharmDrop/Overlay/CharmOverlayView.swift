import AppKit

/// Main-actor bound: every call originates from AppKit's event delivery on the
/// main thread.
@MainActor
protocol CharmOverlayViewDelegate: AnyObject {
    /// Interactive region in view coordinates. Everything outside it is
    /// click-through.
    func overlayViewHitbox(_ view: CharmOverlayView) -> CGRect
    func overlayView(_ view: CharmOverlayView, didPressAt location: CGPoint, clickCount: Int)
    func overlayView(_ view: CharmOverlayView, didDragTo location: CGPoint, timestamp: CFTimeInterval)
    func overlayView(_ view: CharmOverlayView, didReleaseAt location: CGPoint, timestamp: CFTimeInterval)
}

/// Layer-backed canvas for the rope and charm, and the receiver of drag events.
///
/// The view keeps AppKit's default non-flipped, y-up coordinate space so view,
/// layer and physics coordinates are all the same space. No conversion happens
/// anywhere except at the screen boundary.
final class CharmOverlayView: NSView {

    weak var delegate: CharmOverlayViewDelegate?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.isGeometryFlipped = false
        layer?.masksToBounds = false
        clipsToBounds = false
        layerContentsRedrawPolicy = .never
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CharmOverlayView is created programmatically only")
    }

    override var isFlipped: Bool { false }

    /// Never true: the overlay must not participate in keyboard focus.
    override var acceptsFirstResponder: Bool { false }

    /// Accept the very first click even though the app is not active, so the
    /// user does not have to click once to focus and again to grab.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Second line of defence behind the window's `ignoresMouseEvents`: even if
    /// the window is interactive, only the charm's hitbox claims the pointer.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hitbox = delegate?.overlayViewHitbox(self) else { return nil }
        let local = convert(point, from: superview)
        return hitbox.contains(local) ? self : nil
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        delegate?.overlayView(self, didPressAt: location, clickCount: event.clickCount)
    }

    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        delegate?.overlayView(self, didDragTo: location, timestamp: event.timestamp)
    }

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        delegate?.overlayView(self, didReleaseAt: location, timestamp: event.timestamp)
    }
}
