import SwiftUI
import LocalAuthentication
import CryptoKit

/// Single source of truth for Anka's app lock.
///
/// Owned by `AnkaApp` and injected via `@Environment(AppLockManager.self)`.
/// Lives across the app's lifetime so scene-phase changes can flip
/// `isLocked` between foreground/background transitions.
@MainActor
@Observable
final class AppLockManager {
    // `static` so `init` can reference them without re-typing the literal
    // strings (it can't read instance properties before all stored props are
    // initialized — that's why these used to be duplicated as literals) (A4).
    private static let pinKey = "ankaPINCode"
    private static let enabledKey = "anka.appLockEnabled"
    private static let graceKey = "anka.appLock.gracePeriod"
    private static let failedAttemptsKey = "anka.appLock.failedAttempts"
    private static let lockoutUntilKey = "anka.appLock.lockoutUntil"
    private static let biometricKey = "anka.appLock.biometricEnabled"

    /// Persisted: does the user want the lock screen at all?
    var appLockEnabled: Bool {
        didSet { UserDefaults.standard.set(appLockEnabled, forKey: Self.enabledKey) }
    }

    /// Persisted user *preference* for using Face ID / Touch ID on the lock
    /// screen. Distinct from `canUseBiometrics` (the hardware capability) — the
    /// user can keep the lock PIN-only even on a Face ID device. Defaults to on
    /// so existing installs keep using biometrics.
    var biometricEnabled: Bool {
        didSet { UserDefaults.standard.set(biometricEnabled, forKey: Self.biometricKey) }
    }

    /// Effective gate the lock screen uses: biometrics are offered only when the
    /// hardware supports them AND the user hasn't opted into PIN-only.
    var useBiometrics: Bool { canUseBiometrics && biometricEnabled }

    /// Transient: is the lock screen currently covering the UI?
    var isLocked: Bool

    /// Cached "is a PIN set?" flag. Read in SwiftUI view bodies (SettingsView),
    /// i.e. on every render — so it's kept in sync by `savePIN`/`removePIN`
    /// rather than hitting the Keychain on each access.
    private(set) var hasPIN: Bool

    // MARK: - Auto-lock grace period (S4)

    /// How long the app may sit in the background before it re-locks. A short
    /// grace period stops Control Center / notification-shade pulldowns (which
    /// fire `.inactive`/`.background`) from forcing a fresh unlock every time.
    enum GracePeriod: Int, CaseIterable, Identifiable {
        case immediately = 0
        case after30Seconds = 30
        case after1Minute = 60
        case after5Minutes = 300

        var id: Int { rawValue }

        var displayName: String {
            switch self {
            case .immediately:   return "Immediately"
            case .after30Seconds: return "After 30 seconds"
            case .after1Minute:   return "After 1 minute"
            case .after5Minutes:  return "After 5 minutes"
            }
        }
    }

    /// Persisted auto-lock grace period.
    var gracePeriod: GracePeriod {
        didSet { UserDefaults.standard.set(gracePeriod.rawValue, forKey: Self.graceKey) }
    }

    /// When the app last went to the background. Used to decide whether the
    /// grace period has elapsed on the next foreground.
    private var backgroundedAt: Date?

    // MARK: - Brute-force lockout (S2)

    /// Count of consecutive wrong PIN entries. Persisted so relaunching the app
    /// can't reset the lockout (the attack the audit calls out).
    private(set) var failedAttempts: Int

    /// While in the future, PIN entry is blocked.
    private(set) var lockoutUntil: Date?

    /// Cached "is a PIN set?" / biometric state below…

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
        let defaults = UserDefaults.standard
        let enabled = defaults.bool(forKey: Self.enabledKey)
        self.appLockEnabled = enabled
        // hasPIN read inline (can't reference self.hasPIN before all stored
        // properties are initialized).
        let pinExists = KeychainHelper.shared.read(forKey: Self.pinKey) != nil
        self.hasPIN = pinExists
        self.isLocked = enabled && pinExists
        self.gracePeriod = GracePeriod(rawValue: defaults.integer(forKey: Self.graceKey)) ?? .immediately
        self.failedAttempts = defaults.integer(forKey: Self.failedAttemptsKey)
        self.lockoutUntil = defaults.object(forKey: Self.lockoutUntilKey) as? Date
        // Default to true when the key has never been written (new + existing
        // installs keep biometrics on until the user turns them off).
        self.biometricEnabled = defaults.object(forKey: Self.biometricKey) as? Bool ?? true
        // Seed the cached biometric state once (all stored properties are now
        // initialized, so calling an instance method here is valid).
        refreshBiometricState()
    }

    // MARK: - State transitions

    /// Explicit lock (e.g. a future "Lock Now" action).
    func lock() {
        guard appLockEnabled, hasPIN else { return }
        isLocked = true
    }

    func unlock() {
        isLocked = false
        // A successful unlock (PIN or biometric) clears the brute-force counter.
        resetAttempts()
    }

    /// Called when the scene leaves the foreground (`.inactive`/`.background`).
    /// Covers the UI immediately so the app-switcher snapshot and Control Center
    /// peek don't expose data, and stamps the time so the grace period can be
    /// honored on return.
    func enterBackground() {
        guard appLockEnabled, hasPIN else { return }
        if backgroundedAt == nil { backgroundedAt = Date() }
        isLocked = true
    }

    /// Called on `.active`. If the app was only away briefly (within the grace
    /// period), unlock silently without prompting; otherwise stay locked.
    func enterForeground() {
        defer { backgroundedAt = nil }
        guard appLockEnabled, hasPIN, isLocked else { return }
        guard gracePeriod != .immediately, let since = backgroundedAt else { return }
        if Date().timeIntervalSince(since) < Double(gracePeriod.rawValue) {
            isLocked = false
        }
    }

    // MARK: - PIN management

    /// Saves a salted-SHA256 hash of `pin` (never the plaintext). Returns the
    /// keychain success so the caller only flips `hasPIN` on a real write.
    @discardableResult
    func savePIN(_ pin: String) -> Bool {
        let ok = KeychainHelper.shared.save(Self.makeCredential(for: pin), forKey: Self.pinKey)
        if ok {
            hasPIN = true
            resetAttempts()
        }
        return ok
    }

    @discardableResult
    func removePIN() -> Bool {
        let ok = KeychainHelper.shared.delete(forKey: Self.pinKey)
        if ok {
            hasPIN = false
            resetAttempts()
        }
        return ok
    }

    /// Verifies `pin` against the stored credential, applying brute-force
    /// lockout. Returns `false` immediately while locked out. On a wrong PIN it
    /// records the attempt (escalating the lockout); on success it clears the
    /// counter and transparently upgrades a legacy plaintext PIN to a hash.
    func verifyPIN(_ pin: String) -> Bool {
        guard !isInLockout else { return false }
        guard let stored = KeychainHelper.shared.read(forKey: Self.pinKey) else {
            recordFailedAttempt()
            return false
        }

        let ok: Bool
        if stored.contains(Self.credentialDelimiter) {
            ok = Self.verify(pin, against: stored)
        } else {
            // Legacy plaintext PIN from before hashing — compare directly, and
            // if it matches, migrate it to a salted hash in place.
            ok = (stored == pin)
            if ok { savePIN(pin) }
        }

        if ok {
            resetAttempts()
        } else {
            recordFailedAttempt()
        }
        return ok
    }

    // MARK: - Lockout

    /// `true` while a wrong-attempt lockout window is still in the future.
    var isInLockout: Bool {
        guard let until = lockoutUntil else { return false }
        return until > Date()
    }

    /// Seconds remaining in the current lockout (0 when not locked out).
    var lockoutRemaining: TimeInterval {
        guard let until = lockoutUntil else { return 0 }
        return max(0, until.timeIntervalSinceNow)
    }

    private func recordFailedAttempt() {
        failedAttempts += 1
        UserDefaults.standard.set(failedAttempts, forKey: Self.failedAttemptsKey)
        if let delay = Self.lockoutDelay(for: failedAttempts) {
            let until = Date().addingTimeInterval(delay)
            lockoutUntil = until
            UserDefaults.standard.set(until, forKey: Self.lockoutUntilKey)
        }
    }

    private func resetAttempts() {
        guard failedAttempts != 0 || lockoutUntil != nil else { return }
        failedAttempts = 0
        lockoutUntil = nil
        UserDefaults.standard.removeObject(forKey: Self.failedAttemptsKey)
        UserDefaults.standard.removeObject(forKey: Self.lockoutUntilKey)
    }

    /// Escalating lockout schedule. No penalty for the first four misses, then
    /// increasing delays so a scripted 10k-combination sweep becomes infeasible.
    private static func lockoutDelay(for attempts: Int) -> TimeInterval? {
        switch attempts {
        case ..<5:  return nil
        case 5:     return 30
        case 6:     return 60
        case 7:     return 300
        case 8:     return 900
        default:    return 3600
        }
    }

    // MARK: - PIN hashing

    private static let credentialDelimiter: Character = ":"

    /// Builds a `"<saltHex>:<hashHex>"` credential for storage. A fresh 16-byte
    /// random salt per PIN means identical PINs hash differently and a stolen
    /// keychain item can't be reversed with a precomputed table.
    private static func makeCredential(for pin: String) -> String {
        var salt = Data(count: 16)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        let hash = hashPIN(pin, salt: salt)
        return "\(salt.hexString)\(credentialDelimiter)\(hash.hexString)"
    }

    /// Recomputes the hash with the credential's stored salt and constant-time
    /// compares it against the stored hash.
    private static func verify(_ pin: String, against credential: String) -> Bool {
        let parts = credential.split(separator: credentialDelimiter, maxSplits: 1)
        guard parts.count == 2,
              let salt = Data(hexString: String(parts[0])),
              let expected = Data(hexString: String(parts[1])) else {
            return false
        }
        let actual = Data(hashPIN(pin, salt: salt))
        // Length-stable compare; SHA256 outputs are fixed-length anyway.
        return actual.count == expected.count &&
            zip(actual, expected).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }

    private static func hashPIN(_ pin: String, salt: Data) -> Data {
        var input = salt
        input.append(Data(pin.utf8))
        return Data(SHA256.hash(data: input))
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

// MARK: - Hex helpers

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    init?(hexString: String) {
        let chars = Array(hexString)
        guard chars.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(chars.count / 2)
        var i = 0
        while i < chars.count {
            guard let b = UInt8(String(chars[i...i+1]), radix: 16) else { return nil }
            bytes.append(b)
            i += 2
        }
        self = Data(bytes)
    }
}
