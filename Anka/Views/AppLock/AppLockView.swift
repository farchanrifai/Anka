import SwiftUI
import LocalAuthentication
import Combine

/// Full-screen lock cover. Shown whenever `AppLockManager.isLocked == true`.
/// Auto-prompts biometric on first appearance; PIN is always available as fallback.
struct AppLockView: View {
    @Environment(AppLockManager.self) private var lock

    @State private var pinInput: String = ""
    @State private var showPINEntry: Bool = false
    @State private var errorMessage: String = ""
    @State private var isAuthenticating: Bool = false
    @State private var biometricAttempted: Bool = false
    /// Drives the live lockout countdown — refreshed once a second while the
    /// lockout window is open.
    @State private var now: Date = .now
    @FocusState private var pinFocused: Bool

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            DSColor.bgPrimary
                .ignoresSafeArea()

            VStack(spacing: DSSpacing.xl) {
                Spacer()

                Image(systemName: "lock.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(DSColor.accent)
                    .padding(.bottom, DSSpacing.lg)

                VStack(spacing: DSSpacing.sm) {
                    Text("Anka is Locked")
                        .font(.dsHeadline)
                        .foregroundStyle(DSColor.textPrimary)

                    Text(subtitle)
                        .font(.dsCaption)
                        .foregroundStyle(DSColor.textMuted)
                }

                Spacer()

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.dsBadge)
                        .foregroundStyle(DSColor.negative)
                        .transition(.opacity)
                }

                if isLockedOut {
                    lockoutSection
                } else if showPINEntry {
                    pinEntrySection
                } else {
                    biometricSection
                }

                Spacer()
            }
            .padding(.horizontal, DSSpacing.lg)
        }
        .onReceive(ticker) { now = $0 }
        .task {
            // Auto-prompt biometric once when the lock screen first appears.
            // After that the user must tap to retry.
            if !biometricAttempted, lock.canUseBiometrics, !showPINEntry {
                biometricAttempted = true
                await runBiometric()
            }
        }
    }

    private var subtitle: String {
        if isLockedOut { return "Too many attempts" }
        if showPINEntry { return "Enter your PIN" }
        if lock.canUseBiometrics { return "Authenticate to continue" }
        return "Enter your PIN to continue"
    }

    /// Recomputed every tick (reads `now`) so the countdown updates and the
    /// section automatically clears the instant the lockout expires.
    private var isLockedOut: Bool {
        guard let until = lock.lockoutUntil else { return false }
        return until > now
    }

    private var lockoutRemaining: Int {
        guard let until = lock.lockoutUntil else { return 0 }
        return max(0, Int(until.timeIntervalSince(now).rounded(.up)))
    }

    // MARK: - Lockout section

    private var lockoutSection: some View {
        VStack(spacing: DSSpacing.sm) {
            Image(systemName: "hourglass")
                .font(.system(size: 24))
                .foregroundStyle(DSColor.textMuted)
            Text("Try again in \(lockoutCountdown)")
                .font(.dsBody)
                .fontWeight(.semibold)
                .foregroundStyle(DSColor.textPrimary)
                .monospacedDigit()
            Text("Locked after too many incorrect PINs.")
                .font(.dsCaption)
                .foregroundStyle(DSColor.textMuted)
                .multilineTextAlignment(.center)
        }
    }

    private var lockoutCountdown: String {
        let total = lockoutRemaining
        let minutes = total / 60
        let seconds = total % 60
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, seconds)
        }
        return "\(seconds)s"
    }

    // MARK: - Biometric section

    private var biometricSection: some View {
        VStack(spacing: DSSpacing.md) {
            if lock.canUseBiometrics {
                Button {
                    Task { await runBiometric() }
                } label: {
                    HStack(spacing: DSSpacing.md) {
                        Image(systemName: biometricSymbol)
                            .font(.system(size: 20))
                        Text(biometricLabel)
                            .font(.dsBody)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .foregroundStyle(DSColor.textOnAccent)
                    .background(DSColor.accent)
                    .cornerRadius(DSRadius.large)
                }
                .disabled(isAuthenticating)
            }

            if lock.hasPIN {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showPINEntry = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        pinFocused = true
                    }
                } label: {
                    Text(lock.canUseBiometrics ? "Use PIN instead" : "Enter PIN")
                        .font(.dsCaption)
                        .foregroundStyle(DSColor.accentText)
                }
            }
        }
    }

    private var biometricSymbol: String {
        switch lock.biometricType {
        case .faceID:
            return "faceid"
        case .touchID:
            return "touchid"
        case .opticID:
            return "opticid"
        case .none:
            return "lock.shield"
        @unknown default:
            return "lock.shield"
        }
    }

    private var biometricLabel: String {
        switch lock.biometricType {
        case .faceID:
            return "Unlock with Face ID"
        case .touchID:
            return "Unlock with Touch ID"
        case .opticID:
            return "Unlock with Optic ID"
        case .none:
            return "Unlock"
        @unknown default:
            return "Unlock"
        }
    }

    // MARK: - PIN section

    private var pinEntrySection: some View {
        VStack(spacing: DSSpacing.md) {
            SecureField("PIN", text: $pinInput)
                .keyboardType(.numberPad)
                .textContentType(.password)
                .multilineTextAlignment(.center)
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .frame(height: 56)
                .frame(maxWidth: .infinity)
                .background(DSColor.bgCard)
                .cornerRadius(DSRadius.medium)
                .focused($pinFocused)
                .onChange(of: pinInput) { _, new in
                    if new.count > 4 { pinInput = String(new.prefix(4)) }
                    if pinInput.count == 4 { attemptPINUnlock() }
                }

            if lock.canUseBiometrics {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showPINEntry = false
                        pinInput = ""
                        errorMessage = ""
                    }
                } label: {
                    Text("Back to \(biometricLabel.replacingOccurrences(of: "Unlock with ", with: ""))")
                        .font(.dsCaption)
                        .foregroundStyle(DSColor.accentText)
                }
            }
        }
    }

    // MARK: - Actions

    private func runBiometric() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let ok = await lock.authenticateWithBiometrics()
        if ok {
            withAnimation(.easeInOut(duration: 0.25)) {
                lock.unlock()
            }
        } else if lock.hasPIN {
            // Biometric failed or was dismissed — fall through to PIN.
            withAnimation(.easeInOut(duration: 0.2)) {
                showPINEntry = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                pinFocused = true
            }
        }
    }

    private func attemptPINUnlock() {
        if lock.verifyPIN(pinInput) {
            withAnimation(.easeInOut(duration: 0.25)) {
                lock.unlock()
            }
        } else {
            pinInput = ""
            // Light haptic to feel the rejection
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            if isLockedOut {
                // Just tripped (or still in) the lockout — the lockout section
                // takes over; clear the inline error so it doesn't double up.
                errorMessage = ""
            } else {
                errorMessage = "Incorrect PIN"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if errorMessage == "Incorrect PIN" { errorMessage = "" }
                }
            }
        }
    }
}

#Preview {
    AppLockView()
        .environment(AppLockManager())
}
