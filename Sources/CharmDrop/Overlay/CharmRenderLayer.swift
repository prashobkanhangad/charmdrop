import AppKit
import QuartzCore

/// Everything the overlay draws, expressed as Core Animation layers.
///
/// This type owns the *look* of the rope and charm; it holds no physics state
/// and makes no decisions. Per-frame updates go straight into layer properties
/// with implicit animations disabled, which keeps the 60/120Hz path away from
/// SwiftUI entirely.
final class CharmRenderLayer {

    /// Extra information drawn only when the developer overlay is enabled.
    struct DebugInfo {
        var hitbox: CGRect
        var anchor: CGPoint
        var framesPerSecond: Double
        var charmSpeed: CGFloat
        var isDragging: Bool
    }

    let container = CALayer()

    private let ropeLayer = CAShapeLayer()
    private let anchorLayer = CAShapeLayer()
    private let charmLayer = CALayer()
    private let debugShapeLayer = CAShapeLayer()
    private let debugTextLayer = CATextLayer()

    private var currentCharmID: String?
    private var currentScale: CGFloat = 0
    private var currentGlow: RitualPresentation.Glow?

    /// The charm's resting drop shadow, restored whenever no ritual glow is
    /// active.
    private enum RestingShadow {
        static let color = NSColor.black.cgColor
        static let opacity: Float = 0.22
        static let radius: CGFloat = 6
        static let offset = CGSize(width: 0, height: -2)
    }

    init() {
        container.isGeometryFlipped = false
        container.masksToBounds = false

        ropeLayer.fillColor = nil
        ropeLayer.lineCap = .round
        ropeLayer.lineJoin = .round
        ropeLayer.strokeColor = NSColor(
            calibratedRed: 0.36, green: 0.31, blue: 0.27, alpha: 1
        ).cgColor
        // Deliberately no shadow on the rope. This layer spans the whole
        // display, and a shadow on a shaped layer forces Core Animation to
        // rasterise an offscreen buffer the size of the layer on every frame
        // the path changes — which is every frame. It measured as the single
        // largest cost while the charm was swinging, for an effect invisible on
        // a 2pt line.

        anchorLayer.fillColor = NSColor(
            calibratedRed: 0.26, green: 0.22, blue: 0.19, alpha: 0.9
        ).cgColor
        anchorLayer.strokeColor = nil

        // The charm hangs from the rope's end, so it pivots about its own top
        // centre rather than its middle.
        charmLayer.anchorPoint = CGPoint(x: 0.5, y: 1.0)
        charmLayer.contentsGravity = .resizeAspect
        charmLayer.shadowColor = RestingShadow.color
        charmLayer.shadowOpacity = RestingShadow.opacity
        charmLayer.shadowRadius = RestingShadow.radius
        charmLayer.shadowOffset = RestingShadow.offset
        charmLayer.allowsEdgeAntialiasing = true

        debugShapeLayer.fillColor = nil
        debugShapeLayer.isHidden = true
        debugTextLayer.isHidden = true
        debugTextLayer.fontSize = 11
        debugTextLayer.foregroundColor = NSColor.systemGreen.cgColor
        debugTextLayer.alignmentMode = .left

        // Position and path changes must land on the exact frame they are set;
        // Core Animation's default implicit animation would smear the rope.
        let identity: [String: CAAction] = [
            "position": NSNull(),
            "path": NSNull(),
            "bounds": NSNull(),
            "transform": NSNull(),
            "contents": NSNull()
        ]
        for layer in [ropeLayer, anchorLayer, charmLayer, debugShapeLayer] as [CALayer] {
            layer.actions = identity
        }
        debugTextLayer.actions = identity

        container.addSublayer(ropeLayer)
        // The mount is the screen bezel itself; a drawn bead there reads as
        // the rope starting a few pixels down.
        anchorLayer.isHidden = true
        container.addSublayer(anchorLayer)
        container.addSublayer(charmLayer)
        container.addSublayer(debugShapeLayer)
        container.addSublayer(debugTextLayer)
    }

    // MARK: - Geometry

    func updateGeometry(bounds: CGRect, contentsScale: CGFloat) {
        container.frame = bounds
        for layer in [container, ropeLayer, anchorLayer, charmLayer, debugShapeLayer, debugTextLayer] as [CALayer] {
            layer.contentsScale = contentsScale
        }
        ropeLayer.frame = bounds
        anchorLayer.frame = bounds
        debugShapeLayer.frame = bounds
        debugTextLayer.frame = CGRect(x: 12, y: bounds.height - 90, width: 240, height: 76)
    }

    // MARK: - Configuration

    /// Applies appearance settings. Artwork is only re-uploaded when the charm
    /// or its size actually changed, since assigning `contents` is comparatively
    /// expensive.
    func apply(configuration: OverlayConfiguration, artwork: CGImage?, contentsScale: CGFloat) {
        ropeLayer.lineWidth = configuration.ropeThickness
        ropeLayer.opacity = Float(configuration.ropeOpacity)
        anchorLayer.opacity = Float(configuration.ropeOpacity)

        let size = configuration.charm.scaledVisualSize(configuration.charmScale)
        let charmChanged = currentCharmID != configuration.charm.id
        let scaleChanged = abs(currentScale - configuration.charmScale) > 0.0001

        if charmChanged || scaleChanged {
            charmLayer.bounds = CGRect(origin: .zero, size: size)
            currentScale = configuration.charmScale
        }

        if charmChanged {
            charmLayer.contents = artwork
            charmLayer.contentsScale = contentsScale
            currentCharmID = configuration.charm.id
        } else if charmLayer.contents == nil, let artwork {
            charmLayer.contents = artwork
        }

        debugShapeLayer.isHidden = !configuration.debugOverlayEnabled
        debugTextLayer.isHidden = !configuration.debugOverlayEnabled

        let anchorRadius: CGFloat = max(2, configuration.ropeThickness * 1.6)
        anchorLayer.path = CGPath(
            ellipseIn: CGRect(
                x: -anchorRadius, y: -anchorRadius,
                width: anchorRadius * 2, height: anchorRadius * 2
            ),
            transform: nil
        )
    }

    /// Forces the artwork to be re-read on the next `apply`, e.g. after the
    /// charm renderer's cache has been invalidated.
    func invalidateArtwork() {
        currentCharmID = nil
        charmLayer.contents = nil
    }

    // MARK: - Per-frame render

    /// - Parameter updateRope: false when the rope has not moved since the last
    ///   frame, which lets an ambient-only frame (a flickering flame over a
    ///   settled rope) skip rebuilding and re-uploading the rope path.
    func render(
        points: [RopePoint],
        rotation: CGFloat,
        rotationOffset: CGFloat,
        anchor: CGPoint,
        presentation: RitualPresentation,
        updateRope: Bool = true,
        debug: DebugInfo?
    ) {
        guard points.count >= 2 else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        if updateRope {
            // The stroke is centred on the path, so a path that ends on the
            // bezel would have its top half clipped by the window. Overdrawing
            // past the mount makes the visible rope flush with the screen edge.
            let positions = Self.pathPointsByOverdrawingMount(
                points.map(\.position),
                extra: max(12, ropeLayer.lineWidth * 4)
            )
            ropeLayer.path = Self.smoothedPath(through: positions)
            anchorLayer.position = anchor
        }

        let attachment = points[points.count - 1].position
        charmLayer.position = attachment

        charmLayer.transform = Self.charmTransform(
            rotation: rotation,
            rotationOffset: rotationOffset,
            presentation: presentation
        )

        applyGlow(presentation.glow)

        if let debug {
            renderDebug(points: points, debug: debug)
        }

        CATransaction.commit()
    }

    /// Composes the rope's physics rotation with a ritual's scale and twist.
    ///
    /// Scale is applied before rotation, both about the charm's attachment
    /// point, so a pulsing charm grows along its own axis rather than shearing.
    /// `CATransform3DConcat(a, b)` applies `a` first.
    ///
    /// Pure and static so the composition can be verified without a layer tree.
    static func charmTransform(
        rotation: CGFloat,
        rotationOffset: CGFloat,
        presentation: RitualPresentation
    ) -> CATransform3D {
        let safeScale = presentation.scale.isFinite ? max(0.01, presentation.scale) : 1
        let angle = rotation + rotationOffset + presentation.rotationBias

        let scale = CATransform3DMakeScale(safeScale, safeScale, 1)
        let spin = CATransform3DMakeRotation(angle.isFinite ? angle : 0, 0, 0, 1)
        return CATransform3DConcat(scale, spin)
    }

    /// Glow is drawn as the charm layer's own shadow with no offset.
    ///
    /// Reusing the shadow avoids a second layer and a second compositing pass;
    /// the charm layer is small, so unlike the rope this is cheap. Only written
    /// when it changes, since shadow changes force the layer to re-render.
    private func applyGlow(_ glow: RitualPresentation.Glow?) {
        guard glow != currentGlow else { return }
        currentGlow = glow

        guard let glow else {
            charmLayer.shadowColor = RestingShadow.color
            charmLayer.shadowOpacity = RestingShadow.opacity
            charmLayer.shadowRadius = RestingShadow.radius
            charmLayer.shadowOffset = RestingShadow.offset
            return
        }

        charmLayer.shadowColor = CGColor(
            srgbRed: glow.red, green: glow.green, blue: glow.blue, alpha: 1
        )
        charmLayer.shadowOpacity = Float(glow.opacity.clamped(to: 0...1))
        charmLayer.shadowRadius = glow.radius
        charmLayer.shadowOffset = .zero
    }

    /// Replaces the charm artwork mid-flight, for rituals that swap variants.
    func setArtwork(_ image: CGImage?, contentsScale: CGFloat) {
        guard let image else { return }
        charmLayer.contents = image
        charmLayer.contentsScale = contentsScale
    }

    /// Prepends a point past the pinned mount so the rope stroke is not
    /// clipped in half by the top of the window.
    static func pathPointsByOverdrawingMount(_ positions: [CGPoint], extra: CGFloat) -> [CGPoint] {
        guard positions.count >= 2, extra > 0 else { return positions }
        let mount = positions[0]
        let next = positions[1]
        let delta = mount - next
        let length = delta.length
        guard length > 0, delta.isFinite else { return positions }

        let overdrawn = CGPoint(
            x: mount.x + delta.dx / length * extra,
            y: mount.y + delta.dy / length * extra
        )
        guard overdrawn.isFinite else { return positions }

        var extended = positions
        extended.insert(overdrawn, at: 0)
        return extended
    }

    /// Smooths the polyline by curving through segment midpoints, which removes
    /// the faceted look of straight lines between particles without needing
    /// more particles.
    static func smoothedPath(through positions: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = positions.first else { return path }
        guard positions.count > 2 else {
            path.move(to: first)
            for point in positions.dropFirst() { path.addLine(to: point) }
            return path
        }

        path.move(to: first)
        for index in 1..<(positions.count - 1) {
            let current = positions[index]
            let next = positions[index + 1]
            let midpoint = CGPoint(
                x: (current.x + next.x) / 2,
                y: (current.y + next.y) / 2
            )
            path.addQuadCurve(to: midpoint, control: current)
        }
        if let last = positions.last {
            path.addLine(to: last)
        }
        return path
    }

    private func renderDebug(points: [RopePoint], debug: DebugInfo) {
        let path = CGMutablePath()

        // Constraint lines.
        path.move(to: points[0].position)
        for point in points.dropFirst() {
            path.addLine(to: point.position)
        }

        // Particles.
        for point in points {
            let radius: CGFloat = point.isPinned ? 3.5 : 2.5
            path.addEllipse(in: CGRect(
                x: point.position.x - radius,
                y: point.position.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
        }

        path.addRect(debug.hitbox)

        debugShapeLayer.path = path
        debugShapeLayer.strokeColor = NSColor.systemGreen.withAlphaComponent(0.8).cgColor
        debugShapeLayer.lineWidth = 1

        debugTextLayer.string = String(
            format: "FPS %.0f\nspeed %.0f px/s\npoints %d\n%@",
            debug.framesPerSecond,
            debug.charmSpeed,
            points.count,
            debug.isDragging ? "dragging" : "free"
        )
    }
}
