import SwiftUI
import LocalAuthentication
import Combine

/// Full-screen lock cover. Shown whenever `AppLockManager.isLocked == true`.
/// When biometrics are enabled it auto-prompts Face ID / Touch ID every time the
/// app becomes active, falling back to PIN only if that attempt fails; otherwise
/// it shows the PIN keypad directly.
struct AppLockView: View {
    @Environment(AppLockManager.self) private var lock
    @Environment(\.scenePhase) private var scenePhase

    @State private var pinInput: String = ""
    @State private var showPINEntry: Bool = false
    @State private var errorMessage: String = ""
    @State private var isAuthenticating: Bool = false
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
                } else if showsPINEntry {
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
            // The lock cover can appear while the app is *backgrounding* (we
            // cover the UI for the app-switcher snapshot). Prompting biometric
            // then is suppressed by iOS and would dump the user to the PIN
            // fallback — so only auto-authenticate if we're already foreground
            // (cold launch / enable-from-Settings). Foreground re-entry is
            // handled by the scenePhase observer below.
            if scenePhase == .active {
                await authenticateOnAppear(resetToBiometric: false)
            }
        }
        .onChange(of: scenePhase) { old, new in
            // Re-offer the default method each time the app returns to the
            // foreground while locked, so reopening defaults to Face ID rather
            // than getting stuck on a PIN fallback from a prior (backgrounded,
            // hence auto-failed) attempt.
            guard new == .active, old != .active else { return }
            Task { await authenticateOnAppear(resetToBiometric: true) }
        }
    }

    /// The default unlock attempt for the current foreground: Face ID / Touch ID
    /// when enabled (falling back to PIN on failure), or the PIN keypad when not.
    /// - Parameter resetToBiometric: on a fresh foreground, drop a stale PIN
    ///   fallback and re-offer biometrics — but never interrupt a PIN the user
    ///   has already started typing.
    private func authenticateOnAppear(resetToBiometric: Bool) async {
        guard lock.isLocked, !isLockedOut, !isAuthenticating else { return }
        guard lock.useBiometrics else {
            // PIN-only — the PIN section is already visible, and its field
            // requests focus on appear. No hand-tuned delay needed here.
            return
        }
        if resetToBiometric, showPINEntry, pinInput.isEmpty {
            withAnimation(.dsEase) { showPINEntry = false }
        }
        // Don't yank a user out of PIN entry they've already begun.
        guard !showPINEntry else { return }
        // Let the foreground transition finish before presenting the system
        // biometric sheet — evaluating during the `.active` handoff throws a
        // not-interactive error. Retry once with a longer settle if the first
        // attempt couldn't present; a genuine success/failure stops the loop.
        for delayMs in [300, 600] {
            try? await Task.sleep(for: .milliseconds(delayMs))
            guard lock.isLocked, !isLockedOut, !showPINEntry, !isAuthenticating else { return }
            if await runBiometric() != .unavailable { return }
        }
    }

    /// Shows the PIN keypad when the user tapped "Use PIN" or when biometrics
    /// are off (hardware-absent or user opted into PIN-only).
    private var showsPINEntry: Bool {
        showPINEntry || !lock.useBiometrics
    }

    private var subtitle: String {
        if isLockedOut { return "Too many attempts" }
        if showsPINEntry { return "Enter your PIN" }
        if lock.useBiometrics { return "Authenticate to continue" }
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
            if lock.useBiometrics {
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
                    withAnimation(.dsEase) {
                        showPINEntry = true
                    }
                } label: {
                    Text(lock.useBiometrics ? "Use PIN instead" : "Enter PIN")
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
                .onAppear {
                    Task { @MainActor in
                        await Task.yield()
                        pinFocused = true
                    }
                }
                .onChange(of: pinInput) { _, new in
                    if new.count > 4 { pinInput = String(new.prefix(4)) }
                    if pinInput.count == 4 { attemptPINUnlock() }
                }

            if lock.useBiometrics {
                Button {
                    withAnimation(.dsEase) {
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

    @discardableResult
    private func runBiometric() async -> AppLockManager.BiometricOutcome {
        guard !isAuthenticating else { return .unavailable }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let outcome = await lock.authenticateWithBiometrics()
        switch outcome {
        case .success:
            withAnimation(.dsEaseSlow) {
                lock.unlock()
            }
        case .failed:
            // Genuine miss / cancel / fallback — drop to PIN.
            if lock.hasPIN {
                withAnimation(.dsEase) {
                    showPINEntry = true
                }
            }
        case .unavailable:
            // The prompt couldn't be presented (e.g. fired during the
            // foreground handoff). Keep the biometric screen up so the user can
            // tap "Unlock with Face ID" — don't dump them to PIN.
            break
        }
        return outcome
    }

    private func attemptPINUnlock() {
        if lock.verifyPIN(pinInput) {
            withAnimation(.dsEaseSlow) {
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
