import AppKit
import AVFoundation
import ServiceManagement
import Combine
import CoreGraphics
import Foundation

/// Executable invariant checks for the physics engine, settings persistence and
/// charm catalog.
///
/// This is the single definition of those invariants: the XCTest suite in
/// `Tests/CharmDropTests` enumerates `SelfCheck.allChecks` and asserts on each
/// one, and `CharmDrop --self-check` runs the same list from the command line.
/// Keeping one list avoids two drifting copies of the same expectations.
enum SelfCheck {

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    struct Check {
        let name: String
        let run: () throws -> Void
    }

    // MARK: - Assertions

    static func expect(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure(message: message) }
    }

    static func expect(
        _ value: CGFloat,
        approximately expected: CGFloat,
        tolerance: CGFloat,
        _ label: String
    ) throws {
        guard abs(value - expected) <= tolerance else {
            throw Failure(
                message: "\(label): expected \(expected) ± \(tolerance), got \(value)"
            )
        }
    }

    // MARK: - Registry

    static var allChecks: [Check] {
        physicsChecks
            + interactionChecks
            + settingsChecks
            + catalogChecks
            + renderChecks
            + overlayChecks
            + ritualChecks
            + soundChecks
            + deepLinkChecks
            + launchAtLoginChecks
    }

    // MARK: - Physics

    static var physicsChecks: [Check] {
        [
            Check(name: "physics/rope hangs below the anchor at rest") {
                let engine = makeEngine()
                settle(engine)
                let charm = engine.charmPosition
                try expect(charm.y < engine.anchor.y, "charm should hang below the anchor")
                try expect(charm.x, approximately: engine.anchor.x, tolerance: 1.0, "resting charm x")
            },

            Check(name: "physics/segment lengths converge on the rest length") {
                let engine = makeEngine()
                settle(engine)
                let expected = engine.configuration.segmentSpacing
                for index in 0..<(engine.points.count - 1) {
                    let measured = engine.points[index].position
                        .distance(to: engine.points[index + 1].position)
                    try expect(
                        measured,
                        approximately: expected,
                        tolerance: expected * 0.12,
                        "segment \(index) length"
                    )
                }
            },

            Check(name: "physics/total rope length matches the configured length") {
                let engine = makeEngine()
                settle(engine)
                var total: CGFloat = 0
                for index in 0..<(engine.points.count - 1) {
                    total += engine.points[index].position
                        .distance(to: engine.points[index + 1].position)
                }
                try expect(
                    total,
                    approximately: engine.configuration.ropeLength,
                    tolerance: engine.configuration.ropeLength * 0.1,
                    "total rope length"
                )
            },

            Check(name: "physics/anchor stays pinned under a violent flick") {
                let engine = makeEngine()
                let anchor = engine.anchor
                engine.applyImpulse(CGVector(dx: 90_000, dy: 60_000))
                advance(engine, seconds: 2)
                try expect(engine.points[0].isPinned, "anchor must remain pinned")
                try expect(
                    engine.points[0].position.distance(to: anchor) < 0.001,
                    "anchor moved to \(engine.points[0].position)"
                )
            },

            Check(name: "physics/simulation stays finite after extreme input") {
                let engine = makeEngine()
                for _ in 0..<40 {
                    engine.applyImpulse(CGVector(dx: 250_000, dy: -250_000))
                    advance(engine, seconds: 0.05)
                }
                advance(engine, seconds: 3)
                for point in engine.points {
                    try expect(point.position.isFinite, "non-finite position \(point.position)")
                    try expect(point.previousPosition.isFinite, "non-finite history")
                }
                try expect(engine.charmRotation.isFinite, "non-finite rotation")
            },

            Check(name: "physics/particle speed is clamped") {
                let engine = makeEngine()
                engine.applyImpulse(CGVector(dx: 500_000, dy: 0))
                advance(engine, seconds: 0.05)
                let limit = engine.configuration.maximumParticleSpeed
                for point in engine.points {
                    let speed = point.velocity(
                        timeStep: CGFloat(engine.configuration.fixedTimeStep)
                    ).length
                    // A small margin allows for the correction constraints
                    // apply within the same substep.
                    try expect(speed <= limit * 1.5, "speed \(speed) exceeded clamp \(limit)")
                }
            },

            Check(name: "physics/charm stays inside the screen bounds") {
                let engine = makeEngine()
                for _ in 0..<30 {
                    engine.applyImpulse(CGVector(dx: 40_000, dy: 0))
                    advance(engine, seconds: 0.1)
                }
                let charm = engine.charmPosition
                try expect(
                    charm.x >= engine.bounds.minX && charm.x <= engine.bounds.maxX,
                    "charm x \(charm.x) escaped bounds \(engine.bounds)"
                )
                try expect(
                    charm.y >= engine.bounds.minY && charm.y <= engine.bounds.maxY,
                    "charm y \(charm.y) escaped bounds \(engine.bounds)"
                )
            },

            Check(name: "physics/an oversized delta cannot explode the rope") {
                let engine = makeEngine()
                settle(engine)
                let before = engine.charmPosition
                // Simulates the delta produced by waking from sleep.
                engine.step(deltaTime: 600)
                let after = engine.charmPosition
                try expect(after.isFinite, "non-finite position after huge delta")
                try expect(
                    after.distance(to: before) < 200,
                    "charm jumped \(after.distance(to: before))px on a 600s delta"
                )
            },

            Check(name: "physics/changing rope length mid-swing stays stable") {
                let engine = makeEngine()
                engine.applyImpulse(CGVector(dx: 1_500, dy: 0))
                advance(engine, seconds: 0.3)

                var configuration = engine.configuration
                configuration.ropeLength = 300
                engine.configuration = configuration
                advance(engine, seconds: 0.3)

                configuration.ropeLength = 100
                engine.configuration = configuration
                advance(engine, seconds: 2)

                for point in engine.points {
                    try expect(point.position.isFinite, "non-finite position after resize")
                }
                let expected = engine.configuration.segmentSpacing
                let measured = engine.points[0].position.distance(to: engine.points[1].position)
                try expect(measured, approximately: expected, tolerance: expected * 0.2, "resized segment")
            },

            Check(name: "physics/changing segment count rebuilds the rope") {
                let engine = makeEngine()
                var configuration = engine.configuration
                configuration.segmentCount = 24
                engine.configuration = configuration
                try expect(engine.points.count == 24, "expected 24 points, got \(engine.points.count)")
                try expect(engine.constraints.count == 23, "expected 23 constraints")
                try expect(engine.points[0].isPinned, "rebuilt rope lost its pin")
            },

            Check(name: "physics/rope settles into a rest state") {
                let engine = makeEngine()
                engine.applyImpulse(CGVector(dx: 800, dy: 0))
                try expect(!engine.isAtRest, "rope should be awake right after an impulse")
                advance(engine, seconds: 20)
                try expect(engine.isAtRest, "rope should settle so rendering can pause")
            },

            Check(name: "physics/dragging pins the charm to the pointer") {
                let engine = makeEngine()
                settle(engine)
                let target = CGPoint(x: engine.anchor.x + 120, y: engine.anchor.y - 90)
                engine.beginDrag(at: engine.charmPosition)
                engine.updateDrag(to: target)
                advance(engine, seconds: 0.2)
                try expect(
                    engine.charmPosition.distance(to: target) < 1.0,
                    "charm should track the pointer, was \(engine.charmPosition) vs \(target)"
                )
                try expect(engine.isDragging, "engine should report dragging")
            },

            Check(name: "physics/releasing transfers pointer velocity") {
                let slow = makeEngine()
                settle(slow)
                slow.beginDrag(at: slow.charmPosition)
                slow.endDrag(velocity: CGVector(dx: 60, dy: 0))
                advance(slow, seconds: 0.25)
                let slowTravel = abs(slow.charmPosition.x - slow.anchor.x)

                let fast = makeEngine()
                settle(fast)
                fast.beginDrag(at: fast.charmPosition)
                fast.endDrag(velocity: CGVector(dx: 1_800, dy: 0))
                advance(fast, seconds: 0.25)
                let fastTravel = abs(fast.charmPosition.x - fast.anchor.x)

                try expect(
                    fastTravel > slowTravel * 2,
                    "a fast flick (\(fastTravel)px) should travel much further than a slow one (\(slowTravel)px)"
                )
                try expect(!fast.isDragging, "engine should stop reporting dragging after release")
            },

            Check(name: "physics/reset returns the rope to a straight hang") {
                let engine = makeEngine()
                engine.applyImpulse(CGVector(dx: 2_000, dy: 0))
                advance(engine, seconds: 0.4)
                engine.reset()
                try expect(
                    engine.charmPosition.x == engine.anchor.x,
                    "reset should centre the charm under the anchor"
                )
                try expect(engine.charmVelocity.length < 0.001, "reset should clear momentum")
            }
        ]
    }

    // MARK: - Interaction maths

    static var interactionChecks: [Check] {
        [
            Check(name: "math/rotation is zero when hanging straight down") {
                let rotation = PhysicsMath.charmRotation(
                    previous: CGPoint(x: 100, y: 100),
                    last: CGPoint(x: 100, y: 60)
                )
                try expect(rotation, approximately: 0, tolerance: 0.0001, "hanging rotation")
            },

            Check(name: "math/rotation follows the rope when displaced") {
                let right = PhysicsMath.charmRotation(
                    previous: CGPoint(x: 100, y: 100),
                    last: CGPoint(x: 140, y: 60)
                )
                try expect(right, approximately: .pi / 4, tolerance: 0.0001, "rightward rotation")

                let left = PhysicsMath.charmRotation(
                    previous: CGPoint(x: 100, y: 100),
                    last: CGPoint(x: 60, y: 60)
                )
                try expect(left, approximately: -.pi / 4, tolerance: 0.0001, "leftward rotation")
            },

            Check(name: "math/angle smoothing takes the short way round") {
                let result = PhysicsMath.lerpAngle(from: .pi - 0.1, to: -.pi + 0.1, factor: 0.5)
                try expect(
                    abs(result) > .pi - 0.15,
                    "smoothing across the ±π seam should not swing through zero, got \(result)"
                )
            },

            Check(name: "interaction/velocity tracker measures linear motion") {
                var tracker = PointerVelocityTracker()
                for step in 0...4 {
                    let time = Double(step) * 0.01
                    tracker.record(CGPoint(x: Double(step) * 10, y: 0), at: time)
                }
                let velocity = tracker.velocity(at: 0.04)
                try expect(velocity.dx, approximately: 1_000, tolerance: 1, "tracked velocity")
            },

            Check(name: "interaction/velocity tracker ignores stale samples") {
                var tracker = PointerVelocityTracker()
                tracker.record(CGPoint(x: 0, y: 0), at: 0)
                tracker.record(CGPoint(x: 200, y: 0), at: 0.01)
                // Releasing long after the last movement must not replay it.
                let velocity = tracker.velocity(at: 1.0)
                try expect(velocity.length == 0, "stale samples produced \(velocity)")
            },

            Check(name: "interaction/hitbox padding survives small charm scales") {
                let charm = BuiltInCharmCatalog().defaultCharm
                let small = charm.scaledHitboxSize(Constants.CharmScale.minimum)
                let visual = charm.scaledVisualSize(Constants.CharmScale.minimum)
                try expect(
                    small.width > visual.width && small.height > visual.height,
                    "hitbox \(small) should exceed visual size \(visual)"
                )
            },

            Check(name: "interaction/anchor fractions are ordered and clamped") {
                try expect(
                    AnchorPosition.left.fraction(custom: 0.5) < AnchorPosition.center.fraction(custom: 0.5),
                    "left should sit before centre"
                )
                try expect(
                    AnchorPosition.center.fraction(custom: 0.5) < AnchorPosition.right.fraction(custom: 0.5),
                    "centre should sit before right"
                )
                try expect(
                    AnchorPosition.custom.fraction(custom: 99) <= 0.98,
                    "custom fractions must be clamped"
                )
                try expect(
                    AnchorPosition.custom.fraction(custom: -5) >= 0.02,
                    "custom fractions must be clamped"
                )
            }
        ]
    }

    // MARK: - Settings

    static var settingsChecks: [Check] {
        [
            Check(name: "settings/values round-trip through user defaults") {
                let defaults = try makeScratchDefaults(suffix: "roundtrip")
                let first = SettingsManager(defaults: defaults)
                first.selectedCharmID = "bell"
                first.ropeLength = 240
                first.charmScale = 1.3
                first.anchorPosition = .right
                first.showCharm = false
                first.flickStrength = 1.7

                let second = SettingsManager(defaults: defaults)
                try expect(second.selectedCharmID == "bell", "charm id did not persist")
                try expect(second.ropeLength == 240, "rope length did not persist")
                try expect(second.charmScale == 1.3, "charm scale did not persist")
                try expect(second.anchorPosition == .right, "anchor did not persist")
                try expect(second.showCharm == false, "visibility did not persist")
                try expect(second.flickStrength == 1.7, "flick strength did not persist")
            },

            Check(name: "settings/out-of-range stored values are clamped") {
                let defaults = try makeScratchDefaults(suffix: "clamp")
                defaults.set(99_999.0, forKey: "ropeLength")
                defaults.set(-40.0, forKey: "charmScale")
                defaults.set(Double.nan, forKey: "ropeOpacity")

                let settings = SettingsManager(defaults: defaults)
                try expect(
                    settings.ropeLength <= Constants.Rope.maximumLength,
                    "rope length not clamped: \(settings.ropeLength)"
                )
                try expect(
                    settings.charmScale >= Constants.CharmScale.minimum,
                    "charm scale not clamped: \(settings.charmScale)"
                )
                try expect(settings.ropeOpacity.isFinite, "NaN opacity was accepted")
            },

            Check(name: "settings/unknown enum values fall back to defaults") {
                let defaults = try makeScratchDefaults(suffix: "enums")
                defaults.set("diagonally", forKey: "anchorPosition")
                defaults.set("hologram", forKey: "screenSelection")
                defaults.set("telepathy", forKey: "ritualTrigger")

                let settings = SettingsManager(defaults: defaults)
                try expect(settings.anchorPosition == .center, "anchor fallback failed")
                try expect(settings.screenSelection == .main, "screen fallback failed")
                try expect(settings.ritualTrigger == .singleClick, "ritual trigger fallback failed")
            },

            Check(name: "settings/reset restores defaults and notifies once") {
                let defaults = try makeScratchDefaults(suffix: "reset")
                let settings = SettingsManager(defaults: defaults)
                settings.ropeLength = 275
                settings.selectedCharmID = "diya"

                var notifications = 0
                let subscription = settings.didChange.sink { notifications += 1 }
                settings.resetAll()
                subscription.cancel()

                try expect(
                    settings.ropeLength == PhysicsConfiguration.default.ropeLength,
                    "rope length not reset"
                )
                try expect(settings.selectedCharmID == "nimbu-mirchi", "charm not reset")
                try expect(
                    notifications == 1,
                    "reset should emit a single change, emitted \(notifications)"
                )
            },

            Check(name: "settings/configuration derives physics from preferences") {
                let defaults = try makeScratchDefaults(suffix: "derive")
                let settings = SettingsManager(defaults: defaults)
                settings.ropeLength = 210
                let configuration = OverlayConfiguration(
                    charm: BuiltInCharmCatalog().defaultCharm,
                    isVisible: settings.showCharm,
                    charmScale: settings.charmScale,
                    ropeLength: settings.ropeLength,
                    ropeThickness: settings.ropeThickness,
                    ropeOpacity: settings.ropeOpacity,
                    anchorPosition: settings.anchorPosition,
                    customAnchorFraction: settings.customAnchorFraction,
                    showOnAllSpaces: settings.showOnAllSpaces,
                    showInFullscreenApps: settings.showInFullscreenApps,
                    flickStrength: settings.flickStrength,
                    dragSensitivity: settings.dragSensitivity,
                    ritualTrigger: settings.ritualTrigger,
                    debugOverlayEnabled: settings.debugOverlayEnabled
                )
                try expect(configuration.physics.ropeLength == 210, "physics rope length mismatch")

                var other = configuration
                other.showOnAllSpaces.toggle()
                try expect(
                    other.requiresPanelRebuild(comparedTo: configuration),
                    "spaces change should force a panel rebuild"
                )

                var cosmetic = configuration
                cosmetic.ropeThickness += 1
                try expect(
                    !cosmetic.requiresPanelRebuild(comparedTo: configuration),
                    "a cosmetic change should not rebuild panels"
                )
            }
        ]
    }

    // MARK: - Catalog

    static var catalogChecks: [Check] {
        [
            Check(name: "catalog/identifiers are unique and non-empty") {
                let catalog = BuiltInCharmCatalog()
                let identifiers = catalog.charms.map(\.id)
                try expect(
                    Set(identifiers).count == identifiers.count,
                    "duplicate charm identifiers in \(identifiers)"
                )
                try expect(
                    identifiers.allSatisfy { !$0.isEmpty },
                    "empty charm identifier"
                )
            },

            Check(name: "catalog/every charm has usable geometry") {
                for charm in BuiltInCharmCatalog().charms {
                    try expect(
                        charm.visualSize.width > 0 && charm.visualSize.height > 0,
                        "\(charm.id) has a degenerate visual size"
                    )
                    try expect(
                        charm.defaultRopeLength >= Constants.Rope.minimumLength
                            && charm.defaultRopeLength <= Constants.Rope.maximumLength,
                        "\(charm.id) default rope length is outside the allowed range"
                    )
                    try expect(!charm.displayName.isEmpty, "\(charm.id) has no display name")
                }
            },

            Check(name: "catalog/unknown identifiers resolve to the default charm") {
                let catalog = BuiltInCharmCatalog()
                try expect(
                    catalog.resolve(id: "charm-that-was-deleted").id == catalog.defaultCharm.id,
                    "stale identifier did not fall back"
                )
                try expect(
                    catalog.resolve(id: nil).id == catalog.defaultCharm.id,
                    "nil identifier did not fall back"
                )
                try expect(catalog.charm(withID: "nazar")?.id == "nazar", "lookup failed")
            },

            Check(name: "catalog/all charms produce artwork") {
                let renderer = CharmRenderer(providers: [PlaceholderCharmArtwork()])
                for charm in BuiltInCharmCatalog().charms {
                    let image = renderer.image(for: charm, pixelScale: 2)
                    try expect(image != nil, "no artwork generated for \(charm.id)")
                    try expect(
                        (image?.width ?? 0) > 0 && (image?.height ?? 0) > 0,
                        "degenerate artwork for \(charm.id)"
                    )
                }
            }
        ]
    }

    // MARK: - Rendering

    static var renderChecks: [Check] {
        [
            Check(name: "render/smoothed rope path spans the whole rope") {
                let engine = makeEngine()
                settle(engine)
                let path = CharmRenderLayer.smoothedPath(through: engine.points.map(\.position))
                try expect(!path.isEmpty, "rope path was empty")

                let box = path.boundingBox
                try expect(box.height > engine.configuration.ropeLength * 0.7,
                           "rope path height \(box.height) is too short")
            },

            Check(name: "render/the rope stroke is overdrawn past the mount") {
                let positions = [
                    CGPoint(x: 200, y: 900),
                    CGPoint(x: 200, y: 800),
                    CGPoint(x: 200, y: 700)
                ]
                let extended = CharmRenderLayer.pathPointsByOverdrawingMount(positions, extra: 12)
                try expect(extended.count == positions.count + 1, "inserts one extra point")
                try expect(extended[1] == positions[0], "original mount stays in the path")
                try expect(extended[0].x, approximately: 200, tolerance: 0.01, "overdraw x")
                try expect(extended[0].y, approximately: 912, tolerance: 0.01, "overdraw y")

                let untouched = CharmRenderLayer.pathPointsByOverdrawingMount(positions, extra: 0)
                try expect(untouched.count == positions.count, "zero extra is a no-op")
            },

            Check(name: "render/a neutral presentation is a pure rotation") {
                let transform = CharmRenderLayer.charmTransform(
                    rotation: 0,
                    rotationOffset: 0,
                    presentation: .neutral
                )
                try expect(
                    CATransform3DIsIdentity(transform),
                    "a hanging charm with no ritual should have no transform"
                )

                let quarterTurn = CharmRenderLayer.charmTransform(
                    rotation: .pi / 2,
                    rotationOffset: 0,
                    presentation: .neutral
                )
                // A 90 degree rotation about z maps x onto y.
                try expect(quarterTurn.m11, approximately: 0, tolerance: 0.0001, "m11")
                try expect(quarterTurn.m12, approximately: 1, tolerance: 0.0001, "m12")
            },

            Check(name: "render/ritual scale and twist compose with rope rotation") {
                var presentation = RitualPresentation.neutral
                presentation.scale = 1.25

                let scaled = CharmRenderLayer.charmTransform(
                    rotation: 0,
                    rotationOffset: 0,
                    presentation: presentation
                )
                try expect(scaled.m11, approximately: 1.25, tolerance: 0.0001, "scaled m11")
                try expect(scaled.m22, approximately: 1.25, tolerance: 0.0001, "scaled m22")

                // A twist must add to the rope angle, not replace it.
                var twisted = RitualPresentation.neutral
                twisted.rotationBias = 0.3
                let combined = CharmRenderLayer.charmTransform(
                    rotation: 0.2,
                    rotationOffset: 0.1,
                    presentation: twisted
                )
                let expected = CATransform3DMakeRotation(0.6, 0, 0, 1)
                try expect(combined.m11, approximately: expected.m11, tolerance: 0.0001, "combined angle")
                try expect(combined.m12, approximately: expected.m12, tolerance: 0.0001, "combined angle")
            },

            Check(name: "render/a corrupt presentation cannot produce an invalid transform") {
                var broken = RitualPresentation.neutral
                broken.scale = .nan
                broken.rotationBias = .infinity

                let transform = CharmRenderLayer.charmTransform(
                    rotation: .nan,
                    rotationOffset: 0,
                    presentation: broken
                )
                try expect(transform.m11.isFinite, "m11 must stay finite")
                try expect(transform.m22.isFinite, "m22 must stay finite")

                var collapsed = RitualPresentation.neutral
                collapsed.scale = 0
                let floor = CharmRenderLayer.charmTransform(
                    rotation: 0,
                    rotationOffset: 0,
                    presentation: collapsed
                )
                try expect(
                    floor.m11 > 0,
                    "a zero scale would make the charm vanish and is clamped"
                )
            },

            Check(name: "render/degenerate point lists do not crash the path builder") {
                try expect(CharmRenderLayer.smoothedPath(through: []).isEmpty, "empty input")
                let single = CharmRenderLayer.smoothedPath(through: [CGPoint(x: 5, y: 5)])
                try expect(!single.isEmpty, "single point should still produce a path")
                let pair = CharmRenderLayer.smoothedPath(
                    through: [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 10)]
                )
                try expect(pair.boundingBox.height == 10, "two-point path geometry")
            }
        ]
    }

    // MARK: - Overlay panel

    static var overlayChecks: [Check] {
        [
            Check(name: "overlay/the panel is allowed to cover the menu bar") {
                let screen = try requiredScreen()
                let panel = CharmPanel(screen: screen)
                defer { panel.close() }

                let constrained = panel.constrainFrameRect(screen.frame, to: screen)
                try expect(
                    constrained == screen.frame,
                    "constrainFrameRect shrank the panel to \(constrained)"
                )
            },

            Check(name: "overlay/content fills the window frame") {
                let screen = try requiredScreen()
                let panel = CharmPanel(screen: screen)
                defer { panel.close() }

                let frame = CGRect(x: 40, y: 80, width: 800, height: 600)
                try expect(
                    panel.contentRect(forFrameRect: frame) == frame,
                    "content rect must not be inset from the frame"
                )
                try expect(
                    panel.frameRect(forContentRect: frame) == frame,
                    "frame rect must not grow a titlebar around the content"
                )
            },

            Check(name: "overlay/the live panel matches the display") {
                let screen = try requiredScreen()
                let panel = CharmPanel(screen: screen)
                defer { panel.close() }

                try expect(
                    panel.frame.size == screen.frame.size,
                    "panel size \(panel.frame.size) != display \(screen.frame.size)"
                )
                try expect(
                    abs(panel.frame.minX - screen.frame.minX) < 0.5
                        && abs(panel.frame.minY - screen.frame.minY) < 0.5,
                    "panel origin \(panel.frame.origin) is not the display origin \(screen.frame.origin)"
                )
                try expect(
                    abs(panel.frame.maxY - screen.frame.maxY) < 0.5,
                    "panel top \(panel.frame.maxY) is not the display top \(screen.frame.maxY)"
                )
            }
        ]
    }

    // MARK: - Rituals

    static var ritualChecks: [Check] {
        [
            Check(name: "ritual/every built-in charm has a ritual") {
                let manager = RitualManager()
                for charm in BuiltInCharmCatalog().charms {
                    try expect(
                        manager.ritual(for: charm) != nil,
                        "no ritual registered for \(charm.id) (\(charm.ritualType.rawValue))"
                    )
                }
            },

            Check(name: "ritual/durations stay in the 0.5-2s window") {
                let manager = RitualManager()
                for charm in BuiltInCharmCatalog().charms {
                    guard let ritual = manager.ritual(for: charm) else { continue }
                    try expect(
                        ritual.duration >= 0.5 && ritual.duration <= 2.0,
                        "\(charm.id) ritual lasts \(ritual.duration)s, outside 0.5-2.0s"
                    )
                }
            },

            Check(name: "ritual/a pulse returns the charm to neutral") {
                let harness = try makeRitualHarness(charmID: "nazar")
                harness.manager.perform(harness.context)
                try expect(harness.manager.isPerforming, "ritual should be running after perform")

                advanceRitual(harness, seconds: 2.0)

                try expect(!harness.manager.isPerforming, "ritual should have finished")
                try expect(
                    harness.context.presentation.isNeutral,
                    "expected neutral presentation, got \(harness.context.presentation)"
                )
            },

            Check(name: "ritual/a pulse pushes the charm and needs no artwork swap") {
                let harness = try makeRitualHarness(charmID: "nazar")
                harness.manager.perform(harness.context)
                advanceRitual(harness, seconds: 1.0)

                try expect(!harness.physics.impulses.isEmpty, "pulse should nudge the charm")
                try expect(
                    harness.context.variant == .primary,
                    "a charm with no alternate artwork must stay on .primary"
                )
            },

            Check(name: "ritual/toggle flips the variant and remembers it") {
                let harness = try makeRitualHarness(charmID: "diya")
                try expect(harness.context.variant == .primary, "diya should start unlit")

                harness.manager.perform(harness.context)
                advanceRitual(harness, seconds: 1.0)
                try expect(harness.context.variant == .alternate, "diya should now be lit")

                harness.manager.perform(harness.context)
                advanceRitual(harness, seconds: 1.0)
                try expect(harness.context.variant == .primary, "diya should be unlit again")
            },

            Check(name: "ritual/only a lit lamp asks for continuous frames") {
                let harness = try makeRitualHarness(charmID: "diya")
                try expect(
                    !harness.manager.wantsContinuousFrames(harness.context),
                    "an unlit diya must let the render loop stop"
                )

                harness.manager.perform(harness.context)
                advanceRitual(harness, seconds: 1.0)

                try expect(
                    harness.manager.wantsContinuousFrames(harness.context),
                    "a lit diya must keep frames alive so the flame can flicker"
                )
            },

            Check(name: "ritual/a lit flame actually flickers") {
                let harness = try makeRitualHarness(charmID: "diya")
                harness.context.variant = .alternate

                var opacities: [CGFloat] = []
                for _ in 0..<120 {
                    harness.manager.update(harness.context, deltaTime: 1.0 / 60.0)
                    opacities.append(harness.context.presentation.glow?.opacity ?? 0)
                }

                guard let lowest = opacities.min(), let highest = opacities.max() else {
                    throw Failure(message: "no ambient frames were produced")
                }
                try expect(lowest > 0, "a lit flame should always glow, saw \(lowest)")
                try expect(
                    highest - lowest > 0.05,
                    "flicker range \(highest - lowest) is too flat to read as a flame"
                )
            },

            Check(name: "ritual/an unlit lamp produces no glow") {
                let harness = try makeRitualHarness(charmID: "diya")
                for _ in 0..<30 {
                    harness.manager.update(harness.context, deltaTime: 1.0 / 60.0)
                }
                try expect(
                    harness.context.presentation.glow == nil,
                    "an unlit diya should have no ambient glow"
                )
            },

            Check(name: "ritual/the bell rings and swings both ways") {
                let harness = try makeRitualHarness(charmID: "bell")
                harness.manager.perform(harness.context)
                advanceRitual(harness, seconds: 2.0)

                try expect(
                    harness.audio.played == ["bell"],
                    "expected one bell sound, got \(harness.audio.played)"
                )
                try expect(
                    harness.physics.impulses.count >= 2,
                    "expected a strike and a return impulse, got \(harness.physics.impulses.count)"
                )

                let horizontal = harness.physics.impulses.map(\.dx)
                let hasOpposing = horizontal.contains { $0 > 0 } && horizontal.contains { $0 < 0 }
                try expect(hasOpposing, "the return swing should oppose the strike: \(horizontal)")
            },

            Check(name: "ritual/a silent charm requests no sound") {
                let harness = try makeRitualHarness(charmID: "nazar")
                harness.manager.perform(harness.context)
                advanceRitual(harness, seconds: 1.5)
                try expect(
                    harness.audio.played.isEmpty,
                    "a charm with no sound name should play nothing, got \(harness.audio.played)"
                )
            },

            Check(name: "ritual/replace swaps artwork and lands back at full size") {
                let harness = try makeRitualHarness(charmID: "nimbu-mirchi")
                harness.manager.perform(harness.context)
                advanceRitual(harness, seconds: 1.5)

                try expect(
                    harness.context.variant == .alternate,
                    "the replacement should leave the fresh charm hanging"
                )
                try expect(
                    abs(harness.context.presentation.scale - 1) < 0.02,
                    "charm should settle at its normal size, got \(harness.context.presentation.scale)"
                )
                try expect(
                    abs(harness.context.presentation.rotationBias) < 0.02,
                    "charm should settle untwisted, got \(harness.context.presentation.rotationBias)"
                )
            },

            Check(name: "ritual/presentation stays sane across every timeline") {
                for charm in BuiltInCharmCatalog().charms {
                    let harness = try makeRitualHarness(charmID: charm.id)
                    harness.manager.perform(harness.context)

                    var frames = 0
                    while harness.manager.isPerforming, frames < 600 {
                        harness.manager.update(harness.context, deltaTime: 1.0 / 240.0)
                        frames += 1

                        let presentation = harness.context.presentation
                        try expect(
                            presentation.scale.isFinite && presentation.rotationBias.isFinite,
                            "\(charm.id) produced a non-finite presentation"
                        )
                        try expect(
                            presentation.scale >= 0.4 && presentation.scale <= 1.4,
                            "\(charm.id) scaled to \(presentation.scale), which would look broken"
                        )
                        try expect(
                            abs(presentation.rotationBias) <= .pi / 2,
                            "\(charm.id) twisted by \(presentation.rotationBias) radians"
                        )
                        if let glow = presentation.glow {
                            try expect(
                                glow.opacity >= 0 && glow.opacity <= 1,
                                "\(charm.id) glow opacity \(glow.opacity) is out of range"
                            )
                            try expect(glow.radius > 0, "\(charm.id) glow radius must be positive")
                        }
                        try expect(
                            charm.availableVariants.contains(presentation.variant),
                            "\(charm.id) asked for unavailable variant \(presentation.variant)"
                        )
                    }

                    try expect(frames < 600, "\(charm.id) ritual never finished")
                }
            },

            Check(name: "ritual/timing is frame-rate independent") {
                let slow = try makeRitualHarness(charmID: "diya")
                let fast = try makeRitualHarness(charmID: "diya")

                slow.manager.perform(slow.context)
                fast.manager.perform(fast.context)

                advanceRitual(slow, seconds: 1.0, frameRate: 60)
                advanceRitual(fast, seconds: 1.0, frameRate: 240)

                try expect(
                    slow.context.variant == fast.context.variant,
                    "60Hz and 240Hz disagreed on the outcome"
                )
                try expect(
                    !slow.manager.isPerforming && !fast.manager.isPerforming,
                    "both should have completed within the same wall-clock time"
                )
            },

            Check(name: "ritual/restarting mid-ritual stays consistent") {
                let harness = try makeRitualHarness(charmID: "bell")
                harness.manager.perform(harness.context)
                advanceRitual(harness, seconds: 0.3)

                // Interrupt with a second click, as an impatient user would.
                harness.manager.perform(harness.context)
                try expect(harness.manager.isPerforming, "the restart should be running")

                advanceRitual(harness, seconds: 2.0)
                try expect(!harness.manager.isPerforming, "the restart should have finished")
                try expect(
                    harness.audio.played.count == 2,
                    "each click should ring the bell, got \(harness.audio.played.count)"
                )
            },

            Check(name: "ritual/an unregistered ritual type is a no-op") {
                let manager = RitualManager(rituals: [:])
                let harness = try makeRitualHarness(charmID: "bell", manager: manager)

                manager.perform(harness.context)
                try expect(!manager.isPerforming, "nothing should be running")

                manager.update(harness.context, deltaTime: 1.0 / 60.0)
                try expect(
                    harness.context.presentation.isNeutral,
                    "an unregistered type should leave the charm untouched"
                )
                try expect(harness.physics.impulses.isEmpty, "no impulse should be applied")
            },

            Check(name: "ritual/easing helpers behave at their boundaries") {
                try expect(RitualEasing.arc(0), approximately: 0, tolerance: 0.0001, "arc at 0")
                try expect(RitualEasing.arc(1), approximately: 0, tolerance: 0.0001, "arc at 1")
                try expect(RitualEasing.arc(0.5), approximately: 1, tolerance: 0.0001, "arc peak")

                try expect(RitualEasing.easeOut(0), approximately: 0, tolerance: 0.0001, "easeOut at 0")
                try expect(RitualEasing.easeOut(1), approximately: 1, tolerance: 0.0001, "easeOut at 1")
                try expect(RitualEasing.easeIn(0), approximately: 0, tolerance: 0.0001, "easeIn at 0")
                try expect(RitualEasing.easeIn(1), approximately: 1, tolerance: 0.0001, "easeIn at 1")

                // Out-of-range input must be clamped, not extrapolated.
                try expect(RitualEasing.easeOut(-3), approximately: 0, tolerance: 0.0001, "clamped low")
                try expect(RitualEasing.easeOut(9), approximately: 1, tolerance: 0.0001, "clamped high")

                try expect(
                    RitualEasing.easeOutBack(0.7) > 1,
                    "easeOutBack should overshoot before settling"
                )
                try expect(
                    RitualEasing.easeOutBack(1),
                    approximately: 1,
                    tolerance: 0.0001,
                    "easeOutBack at 1"
                )

                try expect(RitualEasing.phase(0.5, from: 0.4, to: 0.6), approximately: 0.5, tolerance: 0.0001, "phase midpoint")
                try expect(RitualEasing.phase(0.1, from: 0.4, to: 0.6), approximately: 0, tolerance: 0.0001, "phase before")
                try expect(RitualEasing.phase(0.9, from: 0.4, to: 0.6), approximately: 1, tolerance: 0.0001, "phase after")
            },

            Check(name: "ritual/artwork exists for every variant a charm declares") {
                let renderer = CharmRenderer(providers: [PlaceholderCharmArtwork()])
                for charm in BuiltInCharmCatalog().charms {
                    for variant in charm.availableVariants {
                        let image = renderer.image(for: charm, variant: variant, pixelScale: 2)
                        try expect(
                            image != nil,
                            "no artwork for \(charm.id) variant \(variant.rawValue)"
                        )
                    }
                }
            },

            Check(name: "ritual/an unsupported variant falls back to primary") {
                let charm = BuiltInCharmCatalog().charm(withID: "nazar")
                guard let charm else { throw Failure(message: "nazar missing from the catalog") }

                try expect(
                    charm.supportedVariant(.alternate) == .primary,
                    "a charm without alternate art should clamp to primary"
                )
                try expect(
                    charm.assetName(for: .alternate) == nil,
                    "a charm without alternate art should expose no alternate asset name"
                )

                let renderer = CharmRenderer(providers: [PlaceholderCharmArtwork()])
                try expect(
                    renderer.image(for: charm, variant: .alternate, pixelScale: 2) != nil,
                    "requesting a missing variant must still return drawable artwork"
                )
            }
        ]
    }

    // MARK: - Sound

    static var soundChecks: [Check] {
        [
            Check(name: "sound/the bell tone renders a usable buffer") {
                guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2) else {
                    throw Failure(message: "could not create an audio format")
                }
                guard let buffer = ProceduralTone.templeBell.render(format: format) else {
                    throw Failure(message: "the bell tone did not render")
                }

                try expect(buffer.frameLength > 0, "rendered an empty buffer")
                try expect(
                    Double(buffer.frameLength) / format.sampleRate > 1.0,
                    "the bell should ring for over a second"
                )

                guard let samples = buffer.floatChannelData?[0] else {
                    throw Failure(message: "buffer had no channel data")
                }

                var peak: Float = 0
                for frame in 0..<Int(buffer.frameLength) {
                    let value = samples[frame]
                    try expect(value.isFinite, "non-finite sample at frame \(frame)")
                    try expect(abs(value) <= 1.0, "sample \(value) would clip")
                    peak = max(peak, abs(value))
                }
                try expect(peak > 0.1, "the tone is inaudibly quiet (peak \(peak))")

                // A buffer that does not start and end near silence clicks.
                try expect(abs(samples[0]) < 0.01, "the attack should start from silence")
                let last = Int(buffer.frameLength) - 1
                try expect(abs(samples[last]) < 0.01, "the tail should decay to silence")
            },

            Check(name: "sound/unknown sound names resolve to nothing") {
                try expect(
                    ProceduralTone.tone(named: "not-a-real-sound") == nil,
                    "unknown names must not resolve to a tone"
                )
                try expect(ProceduralTone.tone(named: "bell") != nil, "the bell should resolve")
            },

            Check(name: "sound/a disabled player stays silent") {
                let player = RecordingSoundPlayer()
                player.isEnabled = false
                player.play("bell")
                try expect(player.played.isEmpty, "a disabled player must not play")

                let silent = SilentSoundPlayer()
                silent.play("bell")
                try expect(!silent.isEnabled, "the silent player is never enabled")
            }
        ]
    }

    // MARK: - Deep links

    static var deepLinkChecks: [Check] {
        [
            Check(name: "deeplink/every documented URL parses") {
                let expected: [String: DeepLinkAction] = [
                    "charmdrop://show": .show,
                    "charmdrop://hide": .hide,
                    "charmdrop://toggle": .toggleVisibility,
                    "charmdrop://ritual": .performRitual,
                    "charmdrop://reset": .reset,
                    "charmdrop://settings": .openSettings,
                    "charmdrop://charm/diya": .selectCharm(id: "diya")
                ]

                for (string, action) in expected {
                    guard let url = URL(string: string) else {
                        throw Failure(message: "\(string) is not a valid URL")
                    }
                    let parsed = DeepLink.action(for: url)
                    try expect(
                        parsed == action,
                        "\(string) parsed as \(String(describing: parsed)), expected \(action)"
                    )
                }
            },

            Check(name: "deeplink/the documented examples are all real commands") {
                for example in DeepLink.examples where !example.contains("<") {
                    guard let url = URL(string: example) else {
                        throw Failure(message: "example \(example) is not a valid URL")
                    }
                    try expect(
                        DeepLink.action(for: url) != nil,
                        "documented example \(example) does not parse"
                    )
                }
            },

            Check(name: "deeplink/hosts and charm ids are case-insensitive") {
                let variants = ["charmdrop://RITUAL", "CHARMDROP://ritual", "ChArmDrop://Ritual"]
                for string in variants {
                    guard let url = URL(string: string) else {
                        throw Failure(message: "\(string) is not a valid URL")
                    }
                    try expect(
                        DeepLink.action(for: url) == .performRitual,
                        "\(string) should be understood regardless of case"
                    )
                }

                guard let url = URL(string: "charmdrop://charm/DIYA") else {
                    throw Failure(message: "could not build the charm URL")
                }
                try expect(
                    DeepLink.action(for: url) == .selectCharm(id: "diya"),
                    "charm identifiers should normalise to lower case"
                )
            },

            Check(name: "deeplink/the schemeless and trailing-slash forms work") {
                let equivalent = [
                    "charmdrop:ritual",
                    "charmdrop://ritual/",
                    "charmdrop://ritual//"
                ]
                for string in equivalent {
                    guard let url = URL(string: string) else {
                        throw Failure(message: "\(string) is not a valid URL")
                    }
                    try expect(
                        DeepLink.action(for: url) == .performRitual,
                        "\(string) should be equivalent to charmdrop://ritual"
                    )
                }
            },

            Check(name: "deeplink/foreign and malformed URLs are rejected") {
                let rejected = [
                    "https://example.com/ritual",
                    "charmdropx://ritual",
                    "charmdrop://",
                    "charmdrop://explode",
                    "charmdrop://charm",
                    "charmdrop://charm/",
                    "charmdrop://ritual/extra",
                    "charmdrop://show/please",
                    "charmdrop://settings/general",
                    "charmdrop:///",
                    "file:///etc/passwd",
                    "charmdrop://../../etc/passwd"
                ]

                for string in rejected {
                    guard let url = URL(string: string) else { continue }
                    let action = DeepLink.action(for: url)
                    try expect(
                        action == nil,
                        "\(string) should have been rejected, parsed as \(String(describing: action))"
                    )
                }
            },

            Check(name: "deeplink/hostile input does not crash the parser") {
                let nasty = [
                    "charmdrop://charm/" + String(repeating: "a", count: 5_000),
                    "charmdrop://charm/%00%01%02",
                    "charmdrop://charm/../../secret",
                    "charmdrop://charm/diya?then=hide",
                    "charmdrop://charm/diya#fragment",
                    "charmdrop://%20",
                    "charmdrop://charm/%E2%9C%93"
                ]

                for string in nasty {
                    guard let url = URL(string: string) else { continue }
                    // The only requirement is that nothing traps and nothing
                    // unexpected is granted.
                    if let action = DeepLink.action(for: url) {
                        switch action {
                        case .selectCharm(let id):
                            try expect(
                                !id.isEmpty && !id.contains("/"),
                                "\(string) produced a suspicious charm id: \(id)"
                            )
                        default:
                            throw Failure(message: "\(string) unexpectedly produced \(action)")
                        }
                    }
                }
            },

            Check(name: "deeplink/a charm link never selects an unknown charm") {
                // Parsing accepts any identifier; the catalog is what refuses
                // to act on one it does not know.
                guard let url = URL(string: "charmdrop://charm/not-a-charm") else {
                    throw Failure(message: "could not build the URL")
                }
                try expect(
                    DeepLink.action(for: url) == .selectCharm(id: "not-a-charm"),
                    "parsing should pass the identifier through"
                )
                try expect(
                    BuiltInCharmCatalog().charm(withID: "not-a-charm") == nil,
                    "the catalog should not recognise it"
                )
            }
        ]
    }

    // MARK: - Launch at login

    static var launchAtLoginChecks: [Check] {
        [
            Check(name: "launch/an enabled login item is reflected in preferences") {
                let defaults = try makeScratchDefaults(suffix: "launchenabled")
                let settings = SettingsManager(defaults: defaults)

                let backend = StubLaunchAtLoginBackend(status: .enabled)
                let manager = LaunchAtLoginManager(settings: settings, backend: backend)

                manager.synchronize()
                try expect(manager.isEnabled, "manager should report enabled")
                try expect(
                    settings.launchAtLogin,
                    "the preference should agree with the system"
                )
            },

            Check(name: "launch/removing the login item externally updates the preference") {
                let defaults = try makeScratchDefaults(suffix: "launchexternal")
                let settings = SettingsManager(defaults: defaults)

                // The user turned it on previously...
                settings.launchAtLogin = true

                // ...then removed it in System Settings while the app was closed.
                let backend = StubLaunchAtLoginBackend(status: .disabled)
                let manager = LaunchAtLoginManager(settings: settings, backend: backend)
                manager.synchronize()

                try expect(
                    !settings.launchAtLogin,
                    "the system is the source of truth and the preference must follow it"
                )
                try expect(!manager.isEnabled, "manager should report disabled")
            },

            Check(name: "launch/enabling registers exactly once") {
                let defaults = try makeScratchDefaults(suffix: "launchregister")
                let settings = SettingsManager(defaults: defaults)

                let backend = StubLaunchAtLoginBackend(status: .disabled)
                let manager = LaunchAtLoginManager(settings: settings, backend: backend)

                manager.setEnabled(true)
                try expect(backend.registerCount == 1, "expected one register call")
                try expect(manager.isEnabled, "manager should now report enabled")
                try expect(settings.launchAtLogin, "preference should be true")

                // Toggling to the same value must not re-register.
                manager.setEnabled(true)
                try expect(
                    backend.registerCount == 1,
                    "re-enabling should be a no-op, saw \(backend.registerCount) calls"
                )

                manager.setEnabled(false)
                try expect(backend.unregisterCount == 1, "expected one unregister call")
                try expect(!settings.launchAtLogin, "preference should be false")
            },

            Check(name: "launch/a refused registration does not claim success") {
                let defaults = try makeScratchDefaults(suffix: "launchrefused")
                let settings = SettingsManager(defaults: defaults)

                let backend = StubLaunchAtLoginBackend(status: .disabled)
                backend.errorToThrow = LaunchAtLoginError.notInAppBundle
                let manager = LaunchAtLoginManager(settings: settings, backend: backend)

                manager.setEnabled(true)

                try expect(!manager.isEnabled, "a failed registration must not report enabled")
                try expect(
                    !settings.launchAtLogin,
                    "a failed registration must not persist as enabled"
                )
                if case .unavailable = manager.status {
                    // Expected: the reason is surfaced to the user.
                    try expect(
                        manager.status.explanation?.isEmpty == false,
                        "an unavailable status must explain itself"
                    )
                } else {
                    throw Failure(message: "expected .unavailable, got \(manager.status)")
                }
            },

            Check(name: "launch/pending approval is not reported as enabled") {
                let defaults = try makeScratchDefaults(suffix: "launchapproval")
                let settings = SettingsManager(defaults: defaults)

                let backend = StubLaunchAtLoginBackend(status: .requiresApproval)
                let manager = LaunchAtLoginManager(settings: settings, backend: backend)
                manager.synchronize()

                try expect(!manager.isEnabled, "approval pending is not the same as enabled")
                try expect(
                    manager.status.isActionable,
                    "the user should still be able to turn it off"
                )
                try expect(
                    manager.status.explanation?.isEmpty == false,
                    "the pending state must explain itself"
                )

                // Registration already happened, so asking again must not repeat it.
                manager.setEnabled(true)
                try expect(
                    backend.registerCount == 0,
                    "an already-registered item should not be registered again"
                )
            },

            Check(name: "launch/a never-registered app can still be switched on") {
                // The regression this guards: macOS reports `.notFound` for an
                // app it has never registered, and the only escape from that
                // state is to call register(). Reporting it as unavailable
                // would disable the toggle and make the feature unreachable.
                let notFound = SMAppServiceBackend.status(
                    from: .notFound,
                    isRunningInAppBundle: true
                )
                try expect(
                    notFound == .disabled,
                    "a never-registered app must be offered the toggle, got \(notFound)"
                )
                try expect(notFound.isActionable, "the toggle must be usable")
            },

            Check(name: "launch/system statuses map correctly") {
                let expected: [(SMAppService.Status, LaunchAtLoginStatus)] = [
                    (.enabled, .enabled),
                    (.notRegistered, .disabled),
                    (.notFound, .disabled),
                    (.requiresApproval, .requiresApproval)
                ]
                for (input, output) in expected {
                    let mapped = SMAppServiceBackend.status(
                        from: input,
                        isRunningInAppBundle: true
                    )
                    try expect(
                        mapped == output,
                        "\(input) mapped to \(mapped), expected \(output)"
                    )
                }

                // Outside an app bundle nothing is possible, whatever macOS says.
                for (input, _) in expected {
                    let mapped = SMAppServiceBackend.status(
                        from: input,
                        isRunningInAppBundle: false
                    )
                    try expect(
                        !mapped.isActionable,
                        "a loose executable cannot register, but \(input) mapped to \(mapped)"
                    )
                }
            },

            Check(name: "launch/an unavailable backend leaves the preference alone") {
                let defaults = try makeScratchDefaults(suffix: "launchunavailable")
                let settings = SettingsManager(defaults: defaults)

                settings.launchAtLogin = true

                let backend = StubLaunchAtLoginBackend(
                    status: .unavailable(reason: "not running from an app bundle")
                )
                let manager = LaunchAtLoginManager(settings: settings, backend: backend)
                manager.synchronize()

                try expect(
                    settings.launchAtLogin,
                    "an unavailable backend says nothing about intent, so the preference stands"
                )
                try expect(!manager.status.isActionable, "the toggle should be disabled")

                manager.setEnabled(false)
                try expect(
                    backend.registerCount == 0 && backend.unregisterCount == 0,
                    "an unavailable backend must not be called"
                )
            }
        ]
    }

    // MARK: - Helpers

    /// Records calls instead of touching the real login item database.
    final class StubLaunchAtLoginBackend: LaunchAtLoginBackend {
        var systemStatus: LaunchAtLoginStatus
        var errorToThrow: Error?
        var registerCount = 0
        var unregisterCount = 0

        init(status: LaunchAtLoginStatus) {
            self.systemStatus = status
        }

        func register() throws {
            registerCount += 1
            if let errorToThrow { throw errorToThrow }
            systemStatus = .enabled
        }

        func unregister() throws {
            unregisterCount += 1
            if let errorToThrow { throw errorToThrow }
            systemStatus = .disabled
        }
    }

    /// A ritual under test, with its collaborators captured so their effects
    /// can be asserted on.
    struct RitualHarness {
        let manager: RitualManager
        let context: RitualContext
        let physics: RecordingRitualPhysics
        let audio: RecordingSoundPlayer
    }

    /// Records impulses instead of simulating them, so a ritual's physical
    /// intent can be asserted without running the solver.
    final class RecordingRitualPhysics: RitualPhysicsControlling {
        var impulses: [CGVector] = []
        var charmVelocity: CGVector = .zero

        func applyImpulse(_ impulse: CGVector) {
            impulses.append(impulse)
        }
    }

    final class RecordingSoundPlayer: SoundPlaying {
        var isEnabled = true
        var played: [String] = []

        func play(_ name: String) {
            guard isEnabled else { return }
            played.append(name)
        }
    }

    static func makeRitualHarness(
        charmID: String,
        manager: RitualManager = RitualManager()
    ) throws -> RitualHarness {
        guard let charm = BuiltInCharmCatalog().charm(withID: charmID) else {
            throw Failure(message: "charm \(charmID) is not in the catalog")
        }
        let physics = RecordingRitualPhysics()
        let audio = RecordingSoundPlayer()
        return RitualHarness(
            manager: manager,
            context: RitualContext(charm: charm, physics: physics, audio: audio),
            physics: physics,
            audio: audio
        )
    }

    static func advanceRitual(
        _ harness: RitualHarness,
        seconds: CFTimeInterval,
        frameRate: Double = 60
    ) {
        let step = 1.0 / frameRate
        var elapsed: CFTimeInterval = 0
        while elapsed < seconds {
            harness.manager.update(harness.context, deltaTime: step)
            elapsed += step
        }
    }

    /// A rope on a notional 1440x900 screen, anchored to the top edge exactly
    /// as `CharmOverlayController` anchors it.
    static func makeEngine(
        bounds: CGRect = CGRect(x: 0, y: 0, width: 1440, height: 900)
    ) -> RopePhysicsEngine {
        let engine = RopePhysicsEngine()
        engine.bounds = bounds
        engine.charmHalfExtent = CGSize(width: 45, height: 110)
        engine.anchor = CGPoint(x: bounds.midX, y: bounds.maxY)
        engine.reset()
        return engine
    }

    static func advance(_ engine: RopePhysicsEngine, seconds: CFTimeInterval, frameRate: Double = 60) {
        let step = 1.0 / frameRate
        var elapsed: CFTimeInterval = 0
        while elapsed < seconds {
            engine.step(deltaTime: step)
            elapsed += step
        }
    }

    static func settle(_ engine: RopePhysicsEngine) {
        advance(engine, seconds: 12)
    }

    static func makeScratchDefaults(suffix: String) throws -> UserDefaults {
        let name = "\(Constants.App.bundleIdentifier).selfcheck.\(suffix)"
        guard let defaults = UserDefaults(suiteName: name) else {
            throw Failure(message: "could not create scratch defaults domain \(name)")
        }
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    static func requiredScreen() throws -> NSScreen {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            throw Failure(message: "no display available to size the overlay panel against")
        }
        return screen
    }

    // MARK: - Command-line runner

    /// Runs every check, printing a TAP-like report. Returns true when all pass.
    static func runAllAndReport() -> Bool {
        let checks = allChecks
        var failures: [(String, String)] = []

        print("\(Constants.App.displayName) self-check: \(checks.count) checks\n")

        for check in checks {
            do {
                try check.run()
                print("  pass  \(check.name)")
            } catch {
                let message = (error as? Failure)?.message ?? error.localizedDescription
                failures.append((check.name, message))
                print("  FAIL  \(check.name)")
                print("        \(message)")
            }
        }

        print("")
        if failures.isEmpty {
            print("All \(checks.count) checks passed.")
            return true
        }

        print("\(failures.count) of \(checks.count) checks failed:")
        for (name, message) in failures {
            print("  - \(name): \(message)")
        }
        return false
    }
}
