import XCTest
@testable import CharmDrop

/// Behavioural tests that are more natural to express with XCTest's
/// measurement and parameterised style than as flat invariants.
final class RopePhysicsTests: XCTestCase {

    func testRopeIsDeterministicForIdenticalInput() {
        let first = SelfCheck.makeEngine()
        let second = SelfCheck.makeEngine()

        first.applyImpulse(CGVector(dx: 900, dy: 40))
        second.applyImpulse(CGVector(dx: 900, dy: 40))

        SelfCheck.advance(first, seconds: 1.5)
        SelfCheck.advance(second, seconds: 1.5)

        for (lhs, rhs) in zip(first.points, second.points) {
            XCTAssertEqual(lhs.position.x, rhs.position.x, accuracy: 0.0001)
            XCTAssertEqual(lhs.position.y, rhs.position.y, accuracy: 0.0001)
        }
    }

    /// The simulation must land in the same place whether the host renders at
    /// 60Hz or 120Hz, which is the whole point of the fixed-substep loop.
    func testSimulationIsRefreshRateIndependent() {
        let sixty = SelfCheck.makeEngine()
        let oneTwenty = SelfCheck.makeEngine()

        sixty.applyImpulse(CGVector(dx: 700, dy: 0))
        oneTwenty.applyImpulse(CGVector(dx: 700, dy: 0))

        SelfCheck.advance(sixty, seconds: 2, frameRate: 60)
        SelfCheck.advance(oneTwenty, seconds: 2, frameRate: 120)

        XCTAssertEqual(
            sixty.charmPosition.x,
            oneTwenty.charmPosition.x,
            accuracy: 12,
            "60Hz and 120Hz should agree to within a few points"
        )
    }

    func testHideAndShowCyclesLeaveTheRopeStable() {
        let engine = SelfCheck.makeEngine()

        for _ in 0..<25 {
            engine.applyImpulse(CGVector(dx: 1_500, dy: 0))
            SelfCheck.advance(engine, seconds: 0.2)
            // Standing in for the overlay being hidden and shown again: the
            // clock restarts but the rope state is retained.
            engine.resetTiming()
        }

        SelfCheck.advance(engine, seconds: 5)
        for point in engine.points {
            XCTAssertTrue(point.position.isFinite)
        }
    }

    func testScreenResizeKeepsTheCharmVisible() {
        let engine = SelfCheck.makeEngine(
            bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080)
        )
        engine.applyImpulse(CGVector(dx: 6_000, dy: 0))
        SelfCheck.advance(engine, seconds: 0.5)

        // Simulates switching to a much smaller display.
        engine.bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        engine.anchor = CGPoint(x: 400, y: 596)
        SelfCheck.advance(engine, seconds: 2)

        XCTAssertTrue(engine.bounds.insetBy(dx: -1, dy: -1).contains(engine.charmPosition))
    }

    func testPhysicsStepCostIsReasonable() {
        let engine = SelfCheck.makeEngine()
        engine.applyImpulse(CGVector(dx: 1_200, dy: 0))

        measure {
            for _ in 0..<600 {
                engine.step(deltaTime: 1.0 / 60.0)
            }
        }
    }
}
