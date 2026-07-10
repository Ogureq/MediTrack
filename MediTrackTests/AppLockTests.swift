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
}
