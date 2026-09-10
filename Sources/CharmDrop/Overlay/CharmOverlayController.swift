import AppKit
import Foundation

/// Owns one screen's worth of charm: the panel, the view, the physics engine
/// and the render loop.
///
/// One controller per display keeps each charm's simulation independent, which
/// is what multi-monitor mode needs, and keeps `OverlayManager` free of any
/// per-screen state.
@MainActor
final class CharmOverlayController: NSObject, CharmOverlayViewDelegate {

    /// Invoked when a click on the charm should be treated as a ritual rather
    /// than a drag.
    var onRitualRequested: (() -> Void)?

    private let panel: CharmPanel
    private let overlayView: CharmOverlayView
    private let renderLayer = CharmRenderLayer()
    private let engine: RopePhysicsEngine
    private let displayLoop = DisplayLoop()
    private let renderer: CharmRenderer
    private let ritualManager = RitualManager()
    private let audio: SoundPlaying

    /// Rebuilt when the charm changes; carries persistent ritual state such as
    /// whether the Diya is lit.
    private var ritualContext: RitualContext

    /// Remembers each charm's toggle state so switching away from a lit Diya
    /// and back again finds it still lit.
    private var variantsByCharmID: [String: CharmArtworkVariant] = [:]

    /// Last variant handed to the render layer, so artwork is only re-uploaded
    /// on an actual swap.
    private var renderedVariant: CharmArtworkVariant = .primary

    private var configuration: OverlayConfiguration
    private var screen: NSScreen

    private var velocityTracker = PointerVelocityTracker()
    private var isPointerInsideHitbox = false
    private var lastHoverCheckCharmPosition: CGPoint?
    private var pressLocation: CGPoint?
    private var pressTimestamp: CFTimeInterval = 0
    private var dragGrabOrigin: CGPoint = .zero

    /// A press that stays within this distance and duration counts as a click.
    private static let clickDistanceThreshold: CGFloat = 5
    private static let clickDurationThreshold: CFTimeInterval = 0.4

    var displayIdentifier: CGDirectDisplayID? { screen.displayIdentifier }

    init(
        screen: NSScreen,
        configuration: OverlayConfiguration,
        renderer: CharmRenderer,
        audio: SoundPlaying
    ) {
        self.screen = screen
        self.configuration = configuration
        self.renderer = renderer
        self.audio = audio

        // Built locally so both properties can be initialised before
        // `super.init()`, where `self` is not yet available.
        let engine = RopePhysicsEngine()
        self.engine = engine
        self.ritualContext = RitualContext(
            charm: configuration.charm,
            physics: engine,
            audio: audio
        )

        panel = CharmPanel(screen: screen)
        overlayView = CharmOverlayView(frame: CGRect(origin: .zero, size: screen.frame.size))

        super.init()

        overlayView.delegate = self
        panel.contentView = overlayView
        overlayView.layer?.addSublayer(renderLayer.container)

        panel.applyCollectionBehavior(
            showOnAllSpaces: configuration.showOnAllSpaces,
            showInFullscreenApps: configuration.showInFullscreenApps
        )

        displayLoop.onFrame = { [weak self] delta in
            self?.handleFrame(delta: delta)
        }

        configureGeometry()
        engine.reset()
        applyConfigurationToRenderLayer()
        renderFrame()

        Log.overlay.info(
            "Overlay created for display \(self.displayIdentifier ?? 0) at \(String(describing: screen.frame.size))"
        )
    }

    // MARK: - Presentation

    func show() {
        panel.synchronizeFrame(with: screen)
        panel.presentWithoutActivating()
        wakeSimulation()
    }

    func hide() {
        displayLoop.stop()
        panel.orderOut(nil)
        setPointerInside(false)
    }

    func teardown() {
        displayLoop.stop()
        displayLoop.onFrame = nil
        overlayView.delegate = nil
        panel.orderOut(nil)
        panel.contentView = nil
    }

    // MARK: - Configuration

    func update(configuration newValue: OverlayConfiguration) {
        let previous = configuration
        configuration = newValue

        if newValue.showOnAllSpaces != previous.showOnAllSpaces
            || newValue.showInFullscreenApps != previous.showInFullscreenApps {
            panel.applyCollectionBehavior(
                showOnAllSpaces: newValue.showOnAllSpaces,
                showInFullscreenApps: newValue.showInFullscreenApps
            )
        }

        // Rope length and anchor changes flow into the live simulation, so the
        // charm eases to its new resting place instead of teleporting.
        engine.configuration = newValue.physics
        engine.charmHalfExtent = charmHalfExtent
        engine.anchor = anchorPoint

        if newValue.charm.id != previous.charm.id {
            rebuildRitualContext(for: newValue.charm)
        }

        applyConfigurationToRenderLayer()
        wakeSimulation()
    }

    /// A charm swap abandons any ritual in progress and restores that charm's
    /// remembered toggle state.
    private func rebuildRitualContext(for charm: Charm) {
        variantsByCharmID[ritualContext.charm.id] = ritualContext.variant
        ritualManager.reset(ritualContext)

        ritualContext = RitualContext(
            charm: charm,
            physics: engine,
            audio: audio,
            variant: variantsByCharmID[charm.id] ?? .primary
        )
        renderedVariant = ritualContext.variant
    }

    /// Re-binds this controller to a screen after a resolution or arrangement
    /// change.
    func update(screen newScreen: NSScreen) {
        screen = newScreen
        configureGeometry()
        displayLoop.resetTiming()
        engine.resetTiming()
        wakeSimulation()
    }

    func perform(_ command: OverlayCommand) {
        switch command {
        case .reset:
            engine.reset()
            engine.anchor = anchorPoint
            renderFrame()
            wakeSimulation()
        case .performRitual:
            ritualManager.perform(ritualContext)
            wakeSimulation()
        }
    }

    // MARK: - Geometry

    private func configureGeometry() {
        panel.synchronizeFrame(with: screen)

        // The overlay *is* the content view. Size it from the panel's content
        // rect (which CharmPanel keeps equal to the display) rather than from
        // `screen.frame` a second time, so a future AppKit inset cannot silently
        // desynchronise the view from the window.
        let contentSize = panel.contentRect(forFrameRect: panel.frame).size
        overlayView.setFrameSize(contentSize)

        let bounds = overlayView.bounds
        renderLayer.updateGeometry(bounds: bounds, contentsScale: screen.backingScaleFactor)

        engine.bounds = bounds
        engine.charmHalfExtent = charmHalfExtent
        engine.anchor = anchorPoint

        Log.overlay.info(
            "Overlay geometry screen=\(String(describing: self.screen.frame.size), privacy: .public) panel=\(String(describing: self.panel.frame.size), privacy: .public) content=\(String(describing: contentSize), privacy: .public) anchorY=\(String(describing: self.anchorPoint.y), privacy: .public)"
        )
    }

    /// The rope's mount point: the physical top edge of the display, so the
    /// rope reads as hanging from the very end of the screen.
    ///
    /// Converted from screen space rather than assumed as `bounds.height`, so
    /// the pin stays on the bezel even if the view origin is not (0, 0). The
    /// panel sits above the menu bar; only the rope ever crosses that band —
    /// boundary clamping keeps the charm body a full artwork height below the
    /// top edge — so menu bar clicks are unaffected.
    private var anchorPoint: CGPoint {
        let bounds = overlayView.bounds
        let x = (bounds.width * configuration.anchorFraction).clamped(to: 0...bounds.width)
        let topOfScreen = CGPoint(x: screen.frame.minX + x, y: screen.frame.maxY)
        let inView = overlayView.convert(panel.convertPoint(fromScreen: topOfScreen), from: nil)
        let y = inView.y.isFinite ? inView.y : bounds.maxY
        return CGPoint(x: x, y: y)
    }

    /// Half-extents used for boundary clamping.
    ///
    /// The charm hangs *below* its attachment point, so the vertical extent is
    /// the full artwork height. Applying it symmetrically also has the useful
    /// side effect of stopping a hard upward flick from covering the menu bar.
    private var charmHalfExtent: CGSize {
        let size = configuration.charm.scaledVisualSize(configuration.charmScale)
        return CGSize(width: size.width / 2, height: size.height)
    }

    /// Interactive region, centred on the charm body rather than its
    /// attachment point.
    private var hitbox: CGRect {
        let attachment = engine.charmPosition
        let visual = configuration.charm.scaledVisualSize(configuration.charmScale)
        let hitboxSize = configuration.charm.scaledHitboxSize(configuration.charmScale)
        let center = CGPoint(x: attachment.x, y: attachment.y - visual.height / 2)
        return CGRect(
            x: center.x - hitboxSize.width / 2,
            y: center.y - hitboxSize.height / 2,
            width: hitboxSize.width,
            height: hitboxSize.height
        )
    }

    private func applyConfigurationToRenderLayer() {
        let artwork = renderer.image(
            for: configuration.charm,
            variant: ritualContext.variant,
            pixelScale: screen.backingScaleFactor
        )
        renderLayer.apply(
            configuration: configuration,
            artwork: artwork,
            contentsScale: screen.backingScaleFactor
        )
        renderedVariant = ritualContext.variant
    }

    /// Uploads new artwork only when a ritual has actually swapped the variant.
    private func synchronizeArtworkVariant(_ variant: CharmArtworkVariant) {
        guard variant != renderedVariant else { return }
        renderedVariant = variant

        let artwork = renderer.image(
            for: configuration.charm,
            variant: variant,
            pixelScale: screen.backingScaleFactor
        )
        renderLayer.setArtwork(artwork, contentsScale: screen.backingScaleFactor)

        Log.charms.debug(
            "Charm \(self.configuration.charm.id, privacy: .public) now showing \(variant.rawValue, privacy: .public) artwork"
        )
    }

    // MARK: - Render loop

    private func wakeSimulation() {
        guard configuration.isVisible, panel.isVisible else { return }
        engine.resetTiming()
        displayLoop.resetTiming()
        if !displayLoop.isRunning {
            displayLoop.start(in: overlayView)
        }
    }

    private func handleFrame(delta: CFTimeInterval) {
        let ropeWasAtRest = engine.isAtRest

        engine.step(deltaTime: delta)

        // Rituals are stepped on the same clock as the physics, so their
        // timing is frame-rate independent for the same reason the rope's is.
        ritualManager.update(ritualContext, deltaTime: delta)
        synchronizeArtworkVariant(ritualContext.presentation.variant)

        // An ambient-only frame over a settled rope does not need the rope path
        // rebuilt, which is most of the cost of a frame.
        renderFrame(updateRope: !ropeWasAtRest || !engine.isAtRest)
        refreshPointerStateFromCurrentLocation()

        // A settled rope with nothing animating needs no frames at all. Any
        // interaction, command or configuration change calls `wakeSimulation`
        // to restart the loop.
        if engine.isAtRest, !ritualManager.wantsContinuousFrames(ritualContext) {
            displayLoop.stop()
        }
    }

    private func renderFrame(updateRope: Bool = true) {
        let debug: CharmRenderLayer.DebugInfo? = configuration.debugOverlayEnabled
            ? CharmRenderLayer.DebugInfo(
                hitbox: hitbox,
                anchor: engine.anchor,
                framesPerSecond: displayLoop.framesPerSecond,
                charmSpeed: engine.charmVelocity.length,
                isDragging: engine.isDragging
            )
            : nil

        renderLayer.render(
            points: engine.points,
            rotation: engine.charmRotation,
            rotationOffset: configuration.charm.rotationOffset,
            anchor: engine.anchor,
            presentation: ritualContext.presentation,
            updateRope: updateRope || debug != nil,
            debug: debug
        )
    }

    // MARK: - Pointer tracking

    /// Called by `OverlayManager` from the shared pointer poll.
    func handlePointerMoved(globalLocation: CGPoint) {
        guard !engine.isDragging else { return }
        guard let local = convertToViewCoordinates(globalLocation) else {
            setPointerInside(false)
            return
        }
        setPointerInside(hitbox.contains(local))
    }

    /// Re-evaluates hover while the charm is moving, which the pointer poll
    /// cannot detect: the charm can swing out from under a stationary cursor.
    ///
    /// Skipped when the charm has barely moved, because querying the pointer is
    /// a window-server round trip and pointer *movement* is already covered by
    /// `MouseInteractionManager`.
    private func refreshPointerStateFromCurrentLocation() {
        guard !engine.isDragging else { return }

        let charm = engine.charmPosition
        if let last = lastHoverCheckCharmPosition, charm.distance(to: last) < 1.0 {
            return
        }
        lastHoverCheckCharmPosition = charm

        handlePointerMoved(globalLocation: NSEvent.mouseLocation)
    }

    private func setPointerInside(_ inside: Bool) {
        guard inside != isPointerInsideHitbox else { return }
        isPointerInsideHitbox = inside

        // This is the whole of the click-through mechanism: the panel is inert
        // unless the pointer is over the charm.
        panel.ignoresMouseEvents = !inside
        (inside ? NSCursor.openHand : NSCursor.arrow).set()

        Log.overlay.debug(
            "Charm hitbox \(inside ? "entered" : "exited", privacy: .public), click-through \(inside ? "disabled" : "enabled", privacy: .public)"
        )
    }

    /// Converts a global screen point into view coordinates, returning nil when
    /// the point is not over this controller's screen.
    private func convertToViewCoordinates(_ globalLocation: CGPoint) -> CGPoint? {
        guard screen.frame.contains(globalLocation) else { return nil }
        let windowPoint = panel.convertPoint(fromScreen: globalLocation)
        return overlayView.convert(windowPoint, from: nil)
    }

    // MARK: - CharmOverlayViewDelegate

    func overlayViewHitbox(_ view: CharmOverlayView) -> CGRect {
        hitbox
    }

    func overlayView(_ view: CharmOverlayView, didPressAt location: CGPoint, clickCount: Int) {
        pressLocation = location
        pressTimestamp = CACurrentMediaTime()
        dragGrabOrigin = location

        engine.beginDrag(at: location)
        velocityTracker.reset()
        velocityTracker.record(location, at: pressTimestamp)
        NSCursor.closedHand.set()
        wakeSimulation()

        if configuration.ritualTrigger == .doubleClick, clickCount >= 2 {
            onRitualRequested?()
        }
    }

    func overlayView(_ view: CharmOverlayView, didDragTo location: CGPoint, timestamp: CFTimeInterval) {
        // Sensitivity scales pointer travel relative to where the charm was
        // grabbed, so the charm still tracks the cursor at the default of 1.0.
        let sensitivity = configuration.dragSensitivity
        let amplified = CGPoint(
            x: dragGrabOrigin.x + (location.x - dragGrabOrigin.x) * sensitivity,
            y: dragGrabOrigin.y + (location.y - dragGrabOrigin.y) * sensitivity
        )

        engine.updateDrag(to: amplified)
        velocityTracker.record(amplified, at: timestamp)
        wakeSimulation()
    }

    func overlayView(_ view: CharmOverlayView, didReleaseAt location: CGPoint, timestamp: CFTimeInterval) {
        let velocity = velocityTracker.velocity(at: timestamp) * configuration.flickStrength
        engine.endDrag(velocity: velocity)
        velocityTracker.reset()

        let travel = pressLocation.map { location.distance(to: $0) } ?? .greatestFiniteMagnitude
        let duration = CACurrentMediaTime() - pressTimestamp
        let wasClick = travel <= Self.clickDistanceThreshold
            && duration <= Self.clickDurationThreshold

        pressLocation = nil
        NSCursor.openHand.set()
        wakeSimulation()

        if wasClick, configuration.ritualTrigger == .singleClick {
            onRitualRequested?()
        }
    }
}
