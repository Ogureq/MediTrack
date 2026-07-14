import Foundation
import LocalAuthentication
import CryptoKit

/// Coordinates the app-lock login: a local numeric passcode (salted SHA-256
/// hash stored in the Keychain), optional Face ID / Touch ID, and a
/// "Remember me" option that keeps the session unlocked across launches.
///
/// No account, no server — authentication is entirely on-device.
@MainActor
final class AppLock: ObservableObject {
    @Published var isLocked = true
    @Published var lastError: String?

    // Persisted preference keys (also used by @AppStorage in the UI).
    nonisolated static let rememberMeKey = "app.rememberMe"
    nonisolated static let biometricsEnabledKey = "app.biometricsEnabled"

    // Login backoff keys, exposed (not private) so tests can seed/reset them.
    nonisolated static let failedAttemptsKey = "app.lock.failedAttempts"
    nonisolated static let lockoutUntilKey = "app.lock.lockoutUntil"

    /// Consecutive failures before a lockout begins.
    private static let attemptsThreshold = 5
    /// Lockout duration at the threshold; doubles with every failure after that.
    private static let baseLockoutSeconds: TimeInterval = 30
    private static let maxLockoutSeconds: TimeInterval = 8 * 60

    private let hashAccount = "passcode.hash"
    private let saltAccount = "passcode.salt"

    // MARK: Stored preferences

    var rememberMe: Bool {
        get { UserDefaults.standard.bool(forKey: Self.rememberMeKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.rememberMeKey) }
    }

    /// Defaults to true so biometrics is offered as soon as the lock is on.
    var biometricsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.biometricsEnabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.biometricsEnabledKey) }
    }

    // MARK: Login backoff

    private var failedAttempts: Int {
        get { UserDefaults.standard.integer(forKey: Self.failedAttemptsKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.failedAttemptsKey) }
    }

    private var lockoutUntil: Date? {
        get {
            let stored = UserDefaults.standard.double(forKey: Self.lockoutUntilKey)
            return stored > 0 ? Date(timeIntervalSince1970: stored) : nil
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: Self.lockoutUntilKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.lockoutUntilKey)
            }
        }
    }

    /// Seconds left in an active lockout, or 0 if there isn't one (or it has
    /// expired). Recomputed from wall-clock time on every access so a UI
    /// timer can poll it.
    var lockoutRemainingSeconds: Int {
        guard let lockoutUntil else { return 0 }
        let remaining = lockoutUntil.timeIntervalSinceNow
        return remaining > 0 ? Int(remaining.rounded(.up)) : 0
    }

    var isLockedOut: Bool { lockoutRemainingSeconds > 0 }

    private func registerFailedAttempt() {
        failedAttempts += 1
        guard failedAttempts >= Self.attemptsThreshold else {
            lastError = "Incorrect passcode."
            return
        }
        let extraFailures = failedAttempts - Self.attemptsThreshold
        let seconds = min(Self.baseLockoutSeconds * pow(2, Double(extraFailures)), Self.maxLockoutSeconds)
        lockoutUntil = Date().addingTimeInterval(seconds)
        lastError = "Try again in \(Int(seconds))s."
    }

    private func resetFailedAttempts() {
        failedAttempts = 0
        lockoutUntil = nil
    }

    // MARK: Capabilities

    var hasPasscode: Bool { KeychainStore.get(hashAccount) != nil }

    nonisolated static var biometricsAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// "Face ID", "Touch ID", or a generic fallback for the current device.
    nonisolated static var biometryLabel: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "Biometrics"
        }
    }

    /// Whether a lock can actually be enforced (a passcode or biometrics exists).
    var canLock: Bool { hasPasscode || Self.biometricsAvailable }

    // MARK: Passcode management

    func setPasscode(_ passcode: String) {
        let salt = Self.randomSalt()
        KeychainStore.set(salt, for: saltAccount)
        KeychainStore.set(Self.hash(passcode, salt: salt), for: hashAccount)
        // A freshly (re)set passcode shouldn't inherit a prior lockout.
        resetFailedAttempts()
    }

    func removePasscode() {
        KeychainStore.delete(hashAccount)
        KeychainStore.delete(saltAccount)
    }

    func verify(_ passcode: String) -> Bool {
        guard let salt = KeychainStore.get(saltAccount),
              let stored = KeychainStore.get(hashAccount) else { return false }
        // Constant-time comparison to avoid leaking the hash via timing.
        let candidate = Self.hash(passcode, salt: salt)
        return constantTimeEquals(candidate, stored)
    }

    // MARK: Session

    /// Unlock with the passcode. Only commits "Remember me" on success, so
    /// toggling it on the login screen can never bypass the lock.
    ///
    /// Deliberately fails open on repeated failures rather than wiping data
    /// or permanently locking the app out — see `registerFailedAttempt`.
    @discardableResult
    func unlock(passcode: String, remember: Bool) -> Bool {
        if isLockedOut {
            lastError = "Try again in \(lockoutRemainingSeconds)s."
            return false
        }
        guard verify(passcode) else {
            registerFailedAttempt()
            return false
        }
        resetFailedAttempts()
        rememberMe = remember
        isLocked = false
        lastError = nil
        return true
    }

    func authenticateWithBiometrics(remember: Bool) async {
        let context = LAContext()
        context.localizedFallbackTitle = "Enter Passcode"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            lastError = "Biometrics is not available."
            return
        }
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Unlock your medical data"
            )
            if success {
                resetFailedAttempts()
                rememberMe = remember
                isLocked = false
                lastError = nil
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Decide whether to show the login screen on launch / foreground.
    func evaluate(lockEnabled: Bool) {
        guard lockEnabled, canLock else {
            isLocked = false
            return
        }
        // "Remember me" keeps the previous session signed in.
        isLocked = !rememberMe
    }

    /// Lock when the app backgrounds, unless the user chose to stay signed in.
    func lockOnBackground(lockEnabled: Bool) {
        guard lockEnabled, canLock, !rememberMe else { return }
        isLocked = true
    }

    /// Explicit sign-out: clears "Remember me" and re-locks immediately.
    func signOut() {
        rememberMe = false
        lastError = nil
        isLocked = true
    }

    // MARK: Hashing

    private static func randomSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    private static func hash(_ passcode: String, salt: Data) -> Data {
        var input = salt
        input.append(Data(passcode.utf8))
        return Data(SHA256.hash(data: input))
    }

    private func constantTimeEquals(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for (a, b) in zip(lhs, rhs) {
            difference |= a ^ b
        }
        return difference == 0
    }
}
