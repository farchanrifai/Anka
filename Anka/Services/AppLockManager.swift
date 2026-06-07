import SwiftUI
import LocalAuthentication

/// Single source of truth for Anka's app lock.
///
/// Owned by `AnkaApp` and injected via `@Environment(AppLockManager.self)`.
/// Lives across the app's lifetime so scene-phase changes can flip
/// `isLocked` between foreground/background transitions.
@MainActor
@Observable
final class AppLockManager {
    private let pinKey = "ankaPINCode"
    private let enabledKey = "anka.appLockEnabled"

    /// Persisted: does the user want the lock screen at all?
    var appLockEnabled: Bool {
        didSet { UserDefaults.standard.set(appLockEnabled, forKey: enabledKey) }
    }

    /// Transient: is the lock screen currently covering the UI?
    var isLocked: Bool

    var hasPIN: Bool {
        KeychainHelper.shared.read(forKey: pinKey) != nil
    }

    var biometricType: LABiometryType {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return ctx.biometryType
    }

    var canUseBiometrics: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    init() {
        let enabled = UserDefaults.standard.bool(forKey: "anka.appLockEnabled")
        self.appLockEnabled = enabled
        // hasPIN read inline (can't reference self.hasPIN before all stored
        // properties are initialized).
        let pinExists = KeychainHelper.shared.read(forKey: "ankaPINCode") != nil
        self.isLocked = enabled && pinExists
    }

    // MARK: - State transitions

    func lock() {
        guard appLockEnabled, hasPIN else { return }
        isLocked = true
    }

    func unlock() { isLocked = false }

    // MARK: - PIN management

    func savePIN(_ pin: String) {
        KeychainHelper.shared.save(pin, forKey: pinKey)
    }

    func removePIN() {
        KeychainHelper.shared.delete(forKey: pinKey)
    }

    func verifyPIN(_ pin: String) -> Bool {
        KeychainHelper.shared.read(forKey: pinKey) == pin
    }

    // MARK: - Biometrics

    func authenticateWithBiometrics() async -> Bool {
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return false
        }
        do {
            return try await ctx.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Unlock Anka"
            )
        } catch {
            return false
        }
    }
}
