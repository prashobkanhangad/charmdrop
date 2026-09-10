import XCTest
@testable import CharmDrop

/// Surfaces every invariant declared in `SelfCheck` as an XCTest assertion.
///
/// The expectations themselves live in `SelfCheck` so that the same list can be
/// executed by `CharmDrop --self-check` on machines without an Xcode test
/// runner. These tests are the grouped, IDE-friendly view of that list.
final class InvariantTests: XCTestCase {

    private func assertAll(_ checks: [SelfCheck.Check]) {
        XCTAssertFalse(checks.isEmpty, "expected at least one check in this group")
        for check in checks {
            XCTContext.runActivity(named: check.name) { _ in
                do {
                    try check.run()
                } catch {
                    let message = (error as? SelfCheck.Failure)?.message
                        ?? error.localizedDescription
                    XCTFail("\(check.name): \(message)")
                }
            }
        }
    }

    func testRopePhysicsInvariants() {
        assertAll(SelfCheck.physicsChecks)
    }

    func testInteractionInvariants() {
        assertAll(SelfCheck.interactionChecks)
    }

    func testSettingsPersistenceInvariants() {
        assertAll(SelfCheck.settingsChecks)
    }

    func testCharmCatalogInvariants() {
        assertAll(SelfCheck.catalogChecks)
    }

    func testRenderingInvariants() {
        assertAll(SelfCheck.renderChecks)
    }
}
