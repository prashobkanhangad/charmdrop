import AppKit

/// The transparent, borderless, non-activating window the charm lives in.
///
/// It covers an entire display. A panel sized to just the charm would clip the
/// rope, break hit-testing during fast drags, and need constant repositioning,
/// so full-screen coverage plus `ignoresMouseEvents` is both simpler and
/// cheaper.
final class CharmPanel: NSPanel {

    init(screen: NSScreen) {
        // `init(contentRect:styleMask:backing:defer:)` is the designated
        // initializer; the `screen:` variant is a convenience initializer and
        // cannot be called from a subclass, so the frame is applied afterwards.
        super.init(
            contentRect: screen.frame,
            // `.nonactivatingPanel` is what keeps clicks from pulling focus
            // away from the app the user is actually working in.
            // `.fullSizeContentView` is what lets the content view occupy the
            // menu-bar strip; without it AppKit insets the content below the
            // menu bar even when the window frame itself covers the display.
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        setFrame(screen.frame, display: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        isMovable = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        // Above the menu bar *and* the status items that share its strip, so
        // a rope pinned to the physical top edge is visible along its whole
        // length instead of vanishing behind them. Open menus sit at a much
        // higher level and continue to draw over the charm.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        animationBehavior = .none

        // Released manually; without this, closing the panel would deallocate
        // it out from under the controller.
        isReleasedWhenClosed = false

        // Click-through is the default state. The overlay only accepts events
        // while the pointer is inside the charm's hitbox.
        ignoresMouseEvents = true

        // Excluded from window cycling and screenshot-style window lists.
        isExcludedFromWindowsMenu = true
    }

    /// A charm must never take keyboard focus away from the user's work.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// AppKit's default constraint parks a window *below* the menu bar. That
    /// would put the rope's origin 24–38pt down from the bezel, which is
    /// exactly the gap this panel exists to close.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    /// Content and frame are the same rectangle: the overlay draws in the
    /// menu-bar strip, it is not a titled document window.
    override func contentRect(forFrameRect frameRect: NSRect) -> NSRect { frameRect }
    override func frameRect(forContentRect contentRect: NSRect) -> NSRect { contentRect }

    /// Keeps the panel exactly over its display after a resolution or
    /// arrangement change.
    func synchronizeFrame(with screen: NSScreen) {
        guard frame != screen.frame else { return }
        setFrame(screen.frame, display: true)
    }

    func applyCollectionBehavior(showOnAllSpaces: Bool, showInFullscreenApps: Bool) {
        // `.stationary` keeps the overlay from being swept up into Mission
        // Control animations; `.ignoresCycle` keeps it out of Cmd-` cycling.
        var behavior: NSWindow.CollectionBehavior = [.stationary, .ignoresCycle]
        behavior.insert(showOnAllSpaces ? .canJoinAllSpaces : .moveToActiveSpace)
        if showInFullscreenApps {
            behavior.insert(.fullScreenAuxiliary)
        }
        collectionBehavior = behavior
    }

    /// Shows the panel without activating the app or disturbing the key window.
    func presentWithoutActivating() {
        orderFrontRegardless()
    }
}
