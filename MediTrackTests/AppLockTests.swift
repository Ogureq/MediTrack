import XCTest
@testable import MediTrack

/// Exercises `AppLock` against the *real* Keychain and UserDefaults of the
/// test host (it has no injectable storage seam). Every test resets the
/// exact entries it touches in both `setUp` and `tearDown` so runs never
/// leak state into each other or into a real app install on the same host.
@MainActor
final class AppLockTests: XCTestCase {

    // Mirrors the private account names in AppLock.swift exactly.
    private let hashAccount = "passcode.hash"
    private let saltAccount = "passcode.salt"

    override func setUpWithError() throws {
        try super.setUpWithError()
        resetPersistedState()

        // The Keychain rejects writes from unsigned test hosts (e.g. CI runs
        // with CODE_SIGNING_ALLOWED=NO), so probe it and skip rather than
        // fail. Signed local runs in Xcode exercise the full suite.
        let probeAccount = "test.keychain.probe"
        let probe = Data("probe".utf8)
        KeychainStore.set(probe, for: probeAccount)
        let readable = KeychainStore.get(probeAccount) == probe
        KeychainStore.delete(probeAccount)
        try XCTSkipUnless(readable, "Keychain is unavailable in this test environment (unsigned test host).")
    }

    override func tearDownWithError() throws {
        resetPersistedState()
        try super.tearDownWithError()
    }

    private func resetPersistedState() {
        KeychainStore.delete(hashAccount)
        KeychainStore.delete(saltAccount)
        UserDefaults.standard.removeObject(forKey: AppLock.rememberMeKey)
        UserDefaults.standard.removeObject(forKey: AppLock.biometricsEnabledKey)
        UserDefaults.standard.removeObject(forKey: AppLock.failedAttemptsKey)
        UserDefaults.standard.removeObject(forKey: AppLock.lockoutUntilKey)
    }

    // MARK: Passcode set + verify

    func testSetPasscodeThenVerifySucceedsForCorrectPasscodeAndFailsForIncorrect() {
        let appLock = AppLock()
        appLock.setPasscode("1234")

        XCTAssertTrue(appLock.hasPasscode)
        XCTAssertTrue(appLock.verify("1234"))
        XCTAssertFalse(appLock.verify("0000"))
    }

    // MARK: Unlock

    func testUnlockWithCorrectPasscodeSucceedsAndPersistsRememberMe() {
        let appLock = AppLock()
        appLock.setPasscode("1234")

        let result = appLock.unlock(passcode: "1234", remember: true)

        XCTAssertTrue(result)
        XCTAssertFalse(appLock.isLocked)
        XCTAssertTrue(appLock.rememberMe)
        XCTAssertNil(appLock.lastError)
    }

    func testUnlockWithIncorrectPasscodeFailsSetsErrorAndLeavesLockedWithoutRememberMe() {
        let appLock = AppLock()
        appLock.setPasscode("1234")

        let result = appLock.unlock(passcode: "9999", remember: true)

        XCTAssertFalse(result)
        XCTAssertNotNil(appLock.lastError)
        // Toggling "remember me" on the login screen must never take effect
        // unless the passcode itself was correct.
        XCTAssertFalse(appLock.rememberMe)
        XCTAssertTrue(appLock.isLocked)
    }

    // MARK: Sign out

    func testSignOutRelocksAndClearsRememberMe() {
        let appLock = AppLock()
        appLock.setPasscode("1234")
        XCTAssertTrue(appLock.unlock(passcode: "1234", remember: true))

        appLock.signOut()

        XCTAssertTrue(appLock.isLocked)
        XCTAssertFalse(appLock.rememberMe)
        XCTAssertNil(appLock.lastError)
    }

    // MARK: Evaluate

    func testEvaluateUnlocksImmediatelyWhenLockIsDisabled() {
        let appLock = AppLock()
        appLock.setPasscode("1234")

        appLock.evaluate(lockEnabled: false)

        XCTAssertFalse(appLock.isLocked)
    }

    func testEvaluateFailsOpenWhenNoPasscodeAndNoBiometricsAreAvailable() throws {
        // Biometric enrollment is simulator/host dependent and out of scope
        // here; only exercise the fail-open path when this host genuinely
        // has no biometric capability, so `canLock` is false.
        try XCTSkipIf(
            AppLock.biometricsAvailable,
            "Fail-open path only applies when biometrics are unavailable on this host."
        )

        let appLock = AppLock()
        XCTAssertFalse(appLock.hasPasscode)

        appLock.evaluate(lockEnabled: true)

        XCTAssertFalse(appLock.isLocked)
    }

    func testEvaluateStaysLockedWhenPasscodeExistsAndRememberMeIsFalse() {
        let appLock = AppLock()
        appLock.setPasscode("1234")
        appLock.rememberMe = false

        appLock.evaluate(lockEnabled: true)

        XCTAssertTrue(appLock.isLocked)
    }

    func testEvaluateUnlocksWhenPasscodeExistsAndRememberMeIsTrue() {
        let appLock = AppLock()
        appLock.setPasscode("1234")
        appLock.rememberMe = true

        appLock.evaluate(lockEnabled: true)

        XCTAssertFalse(appLock.isLocked)
    }

    // MARK: Lock on background

    func testLockOnBackgroundKeepsSessionUnlockedWhenRememberMeIsTrue() {
        let appLock = AppLock()
        appLock.setPasscode("1234")
        XCTAssertTrue(appLock.unlock(passcode: "1234", remember: true))

        appLock.lockOnBackground(lockEnabled: true)

        XCTAssertFalse(appLock.isLocked)
    }

    func testLockOnBackgroundLocksWhenRememberMeIsFalse() {
        let appLock = AppLock()
        appLock.setPasscode("1234")
        XCTAssertTrue(appLock.unlock(passcode: "1234", remember: false))
        XCTAssertFalse(appLock.isLocked)

        appLock.lockOnBackground(lockEnabled: true)

        XCTAssertTrue(appLock.isLocked)
    }

    // MARK: Remove passcode

    func testRemovePasscodeMakesHasPasscodeFalseAndVerifyFail() {
        let appLock = AppLock()
        appLock.setPasscode("1234")
        XCTAssertTrue(appLock.hasPasscode)

        appLock.removePasscode()

        XCTAssertFalse(appLock.hasPasscode)
        XCTAssertFalse(appLock.verify("1234"))
    }

    // MARK: Login backoff
    //
    // These run behind the same keychain-probe skip in setUpWithError as
    // every other test in this class (AppLock's failure path still needs a
    // working Keychain to call `verify`).

    func testFailedAttemptsBelowThresholdDoNotLockOut() {
        let appLock = AppLock()
        appLock.setPasscode("1234")

        for _ in 0..<4 {
            XCTAssertFalse(appLock.unlock(passcode: "0000", remember: false))
        }

        XCTAssertFalse(appLock.isLockedOut)
        XCTAssertEqual(appLock.lockoutRemainingSeconds, 0)
        XCTAssertEqual(appLock.lastError, "Incorrect passcode.")
    }

    func testFifthConsecutiveFailureLocksOutForThirtySeconds() {
        let appLock = AppLock()
        appLock.setPasscode("1234")

        for _ in 0..<5 {
            XCTAssertFalse(appLock.unlock(passcode: "0000", remember: false))
        }

        XCTAssertTrue(appLock.isLockedOut)
        XCTAssertEqual(appLock.lockoutRemainingSeconds, 30)
        XCTAssertEqual(appLock.lastError, "Try again in 30s.")
    }

    func testUnlockDuringLockoutFailsFastEvenWithTheCorrectPasscode() {
        let appLock = AppLock()
        appLock.setPasscode("1234")
        for _ in 0..<5 {
            XCTAssertFalse(appLock.unlock(passcode: "0000", remember: false))
        }
        XCTAssertTrue(appLock.isLockedOut)

        // The lockout fails fast — it doesn't even consult the correct
        // passcode — so the app never wipes data or locks out permanently.
        XCTAssertFalse(appLock.unlock(passcode: "1234", remember: false))
        XCTAssertTrue(appLock.isLocked)
        XCTAssertEqual(appLock.lastError, "Try again in 30s.")
    }

    func testSuccessfulUnlockResetsFailedAttemptCounter() {
        let appLock = AppLock()
        appLock.setPasscode("1234")
        for _ in 0..<4 {
            XCTAssertFalse(appLock.unlock(passcode: "0000", remember: false))
        }

        XCTAssertTrue(appLock.unlock(passcode: "1234", remember: false))

        // A fresh run of 4 more failures should not lock out, proving the
        // counter reset to 0 rather than continuing on toward 9.
        for _ in 0..<4 {
            XCTAssertFalse(appLock.unlock(passcode: "0000", remember: false))
        }
        XCTAssertFalse(appLock.isLockedOut)
    }

    func testConsecutiveLockoutsDoubleAfterTheInitialThirtySeconds() {
        let appLock = AppLock()
        appLock.setPasscode("1234")

        // Simulate 5 prior failures whose lockout window has already
        // expired, then let the next wrong attempt push the streak to 6.
        UserDefaults.standard.set(5, forKey: AppLock.failedAttemptsKey)
        UserDefaults.standard.set(Date().addingTimeInterval(-1).timeIntervalSince1970, forKey: AppLock.lockoutUntilKey)

        XCTAssertFalse(appLock.unlock(passcode: "0000", remember: false))
        XCTAssertEqual(appLock.lockoutRemainingSeconds, 60)

        // Expire that window too, then push the streak to 7.
        UserDefaults.standard.set(Date().addingTimeInterval(-1).timeIntervalSince1970, forKey: AppLock.lockoutUntilKey)
        XCTAssertFalse(appLock.unlock(passcode: "0000", remember: false))
        XCTAssertEqual(appLock.lockoutRemainingSeconds, 120)
    }

    func testLockoutDurationCapsAtEightMinutes() {
        let appLock = AppLock()
        appLock.setPasscode("1234")

        // Simulate a long failure streak with an already-expired window.
        UserDefaults.standard.set(20, forKey: AppLock.failedAttemptsKey)
        UserDefaults.standard.set(Date().addingTimeInterval(-1).timeIntervalSince1970, forKey: AppLock.lockoutUntilKey)

        XCTAssertFalse(appLock.unlock(passcode: "0000", remember: false))
        XCTAssertEqual(appLock.lockoutRemainingSeconds, 8 * 60)
    }

    func testSettingANewPasscodeClearsAnyExistingLockout() {
        let appLock = AppLock()
        appLock.setPasscode("1234")
        for _ in 0..<5 {
            XCTAssertFalse(appLock.unlock(passcode: "0000", remember: false))
        }
        XCTAssertTrue(appLock.isLockedOut)

        appLock.setPasscode("5678")

        XCTAssertFalse(appLock.isLockedOut)
        XCTAssertTrue(appLock.unlock(passcode: "5678", remember: false))
    }
}
