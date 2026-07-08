import Testing
import Foundation
@testable import Anka

/// Covers the security math behind App Lock: salted-SHA256 PIN credentials
/// (S2), constant-time verification, the escalating lockout schedule (S4),
/// and one Keychain round-trip through KeychainHelper (S3).
@MainActor
struct AppLockManagerTests {

    // MARK: - Credential round-trip

    @Test func correctPINVerifies() {
        let credential = AppLockManager.makeCredential(for: "1234")
        #expect(AppLockManager.verify("1234", against: credential))
    }

    @Test func wrongPINFails() {
        let credential = AppLockManager.makeCredential(for: "1234")
        #expect(!AppLockManager.verify("1235", against: credential))
        #expect(!AppLockManager.verify("", against: credential))
    }

    @Test func pinContainingDelimiterRoundTrips() {
        let credential = AppLockManager.makeCredential(for: "12:34")
        #expect(AppLockManager.verify("12:34", against: credential))
        #expect(!AppLockManager.verify("1234", against: credential))
    }

    // MARK: - Salt

    @Test func samePINProducesDifferentCredentials() {
        let a = AppLockManager.makeCredential(for: "0000")
        let b = AppLockManager.makeCredential(for: "0000")
        #expect(a != b)
        // Both still verify — only the salt differs.
        #expect(AppLockManager.verify("0000", against: a))
        #expect(AppLockManager.verify("0000", against: b))
    }

    @Test func credentialHasSaltAndHashParts() {
        let credential = AppLockManager.makeCredential(for: "9999")
        let parts = credential.split(separator: ":")
        #expect(parts.count == 2)
        #expect(parts[0].count == 32)  // 16-byte salt as hex
        #expect(parts[1].count == 64)  // SHA256 as hex
    }

    // MARK: - Malformed credentials

    @Test func malformedCredentialsFailClosed() {
        #expect(!AppLockManager.verify("1234", against: ""))
        #expect(!AppLockManager.verify("1234", against: "no-delimiter"))
        #expect(!AppLockManager.verify("1234", against: "nothex:alsonothex"))
        #expect(!AppLockManager.verify("1234", against: ":"))
    }

    // MARK: - Lockout schedule

    @Test func lockoutEscalates() {
        #expect(AppLockManager.lockoutDelay(for: 0) == nil)
        #expect(AppLockManager.lockoutDelay(for: 4) == nil)
        #expect(AppLockManager.lockoutDelay(for: 5) == 30)
        #expect(AppLockManager.lockoutDelay(for: 6) == 60)
        #expect(AppLockManager.lockoutDelay(for: 7) == 300)
        #expect(AppLockManager.lockoutDelay(for: 8) == 900)
        #expect(AppLockManager.lockoutDelay(for: 9) == 3600)
        #expect(AppLockManager.lockoutDelay(for: 100) == 3600)
    }

    // MARK: - Keychain round-trip

    @Test func keychainSaveReadDelete() {
        let key = "test.applock.\(UUID().uuidString)"
        defer { KeychainHelper.shared.delete(forKey: key) }

        #expect(KeychainHelper.shared.save("secret", forKey: key))
        #expect(KeychainHelper.shared.read(forKey: key) == "secret")

        // Overwrite replaces, not duplicates.
        #expect(KeychainHelper.shared.save("secret2", forKey: key))
        #expect(KeychainHelper.shared.read(forKey: key) == "secret2")

        #expect(KeychainHelper.shared.delete(forKey: key))
        #expect(KeychainHelper.shared.read(forKey: key) == nil)
        // Deleting an absent key is a successful end state.
        #expect(KeychainHelper.shared.delete(forKey: key))
    }
}
