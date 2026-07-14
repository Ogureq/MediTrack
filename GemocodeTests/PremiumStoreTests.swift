import XCTest
@testable import Gemocode

/// Exercises `AIReportQuota` only — it's a pure function over `UserDefaults`,
/// deliberately kept separate from StoreKit so it needs no StoreKit test
/// session. Follows the `AppLockTests` convention: reset the exact
/// `UserDefaults` key this type touches in both `setUp` and `tearDown` so
/// runs never leak state into each other or a real app install on the same
/// host.
final class PremiumStoreTests: XCTestCase {

    private let defaults = UserDefaults.standard

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaults.removeObject(forKey: AIReportQuota.usedCountKey)
    }

    override func tearDownWithError() throws {
        defaults.removeObject(forKey: AIReportQuota.usedCountKey)
        try super.tearDownWithError()
    }

    // MARK: Fresh state

    func testFreshDefaultsHaveFullRemainingAllowanceAndCanGenerate() {
        XCTAssertEqual(AIReportQuota.usedCount(defaults: defaults), 0)
        XCTAssertEqual(AIReportQuota.remaining(defaults: defaults), AIReportQuota.freeLifetimeLimit)
        XCTAssertTrue(AIReportQuota.canGenerate(isPremium: false, defaults: defaults))
        XCTAssertTrue(AIReportQuota.canGenerate(isPremium: true, defaults: defaults))
    }

    // MARK: usedCount tracking

    func testUsedCountReflectsEachRecordedUse() {
        AIReportQuota.recordUse(defaults: defaults)
        XCTAssertEqual(AIReportQuota.usedCount(defaults: defaults), 1)

        AIReportQuota.recordUse(defaults: defaults)
        XCTAssertEqual(AIReportQuota.usedCount(defaults: defaults), 2)
    }

    // MARK: Exhausting the free allowance

    func testExhaustingFreeAllowanceBlocksFreeButNotPremium() {
        for _ in 0..<AIReportQuota.freeLifetimeLimit {
            AIReportQuota.recordUse(defaults: defaults)
        }

        XCTAssertEqual(AIReportQuota.usedCount(defaults: defaults), AIReportQuota.freeLifetimeLimit)
        XCTAssertEqual(AIReportQuota.remaining(defaults: defaults), 0)
        XCTAssertFalse(AIReportQuota.canGenerate(isPremium: false, defaults: defaults))
        XCTAssertTrue(AIReportQuota.canGenerate(isPremium: true, defaults: defaults))
    }

    // MARK: Never negative

    func testRecordUseBeyondLimitKeepsRemainingAtZeroNeverNegative() {
        for _ in 0..<(AIReportQuota.freeLifetimeLimit + 5) {
            AIReportQuota.recordUse(defaults: defaults)
        }

        XCTAssertEqual(AIReportQuota.usedCount(defaults: defaults), AIReportQuota.freeLifetimeLimit + 5)
        XCTAssertEqual(AIReportQuota.remaining(defaults: defaults), 0)
        XCTAssertFalse(AIReportQuota.canGenerate(isPremium: false, defaults: defaults))
    }

    // MARK: Per-use accounting

    func testRemainingDecreasesByOnePerRecordedUse() {
        AIReportQuota.recordUse(defaults: defaults)
        XCTAssertEqual(AIReportQuota.remaining(defaults: defaults), AIReportQuota.freeLifetimeLimit - 1)
        // Whether more free generations remain depends only on the limit;
        // premium is never blocked by the counter.
        XCTAssertEqual(
            AIReportQuota.canGenerate(isPremium: false, defaults: defaults),
            AIReportQuota.freeLifetimeLimit > 1
        )
        XCTAssertTrue(AIReportQuota.canGenerate(isPremium: true, defaults: defaults))
    }
}
