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

    /// Shared context reused for biometric availability checks so we don't
    /// allocate a fresh `LAContext` on every property read — these are read in
    /// SwiftUI view bodies (SettingsView), i.e. on every render pass. Re-created
    /// by `refreshBiometricState()` after a real biometric interaction.
    private var biometricContext = LAContext()

    /// Cached biometric availability. Evaluated once at init via the shared
    /// context and refreshed after each authentication attempt — not on every
    /// access.
    private(set) var biometricType: LABiometryType = .none
    private(set) var canUseBiometrics: Bool = false

    init() {
        let enabled = UserDefaults.standard.bool(forKey: "anka.appLockEnabled")
        self.appLockEnabled = enabled
        // hasPIN read inline (can't reference self.hasPIN before all stored
        // properties are initialized).
        let pinExists = KeychainHelper.shared.read(forKey: "ankaPINCode") != nil
        self.isLocked = enabled && pinExists
        // Seed the cached biometric state once (all stored properties are now
        // initialized, so calling an instance method here is valid).
        refreshBiometricState()
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
        // Once the auth attempt completes (success or failure), refresh the
        // cached biometric state so it reflects anything that changed during
        // the interaction.
        defer { refreshBiometricState() }
        do {
            return try await ctx.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Unlock Anka"
            )
        } catch {
            return false
        }
    }

    /// Re-creates the shared `LAContext` and re-evaluates the cached biometric
    /// availability. A fresh context is required because `LAContext` caches its
    /// policy evaluation, so reusing the old instance wouldn't pick up changes
    /// (e.g. the user enrolling Face/Touch ID or toggling it in iOS Settings).
    private func refreshBiometricState() {
        biometricContext = LAContext()
        canUseBiometrics = biometricContext.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics, error: nil
        )
        biometricType = biometricContext.biometryType
    }
}
