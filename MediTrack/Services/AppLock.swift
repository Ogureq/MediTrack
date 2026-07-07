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
    @discardableResult
    func unlock(passcode: String, remember: Bool) -> Bool {
        guard verify(passcode) else {
            lastError = "Incorrect passcode."
            return false
        }
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
