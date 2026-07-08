import SwiftUI

/// Two-step PIN entry: pick a 4-digit PIN, then confirm. On match, save to
/// Keychain via `AppLockManager.savePIN(_:)` and enable app lock.
///
/// Presented from SettingsView when the user enables Biometric Lock without a
/// PIN already on file. PIN is mandatory because biometric can fail (sensor
/// dirty, mask, sunglasses), and we don't want to lock the user out forever.
struct PINSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppLockManager.self) private var lock

    /// Called on successful PIN save. Caller is responsible for flipping
    /// `appLockEnabled` if needed (Settings does this).
    var onComplete: () -> Void = {}

    enum Step { case create, confirm }
    @State private var step: Step = .create
    @State private var firstPIN: String = ""
    @State private var confirmPIN: String = ""
    @State private var errorMessage: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                DSColor.bgPrimary.ignoresSafeArea()

                VStack(spacing: DSSpacing.xl) {
                    Spacer()

                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 44, relativeTo: .largeTitle))
                        .foregroundStyle(DSColor.accent)

                    VStack(spacing: DSSpacing.sm) {
                        Text(title)
                            .font(.dsHeadline)
                            .foregroundStyle(DSColor.textPrimary)
                        Text(subtitle)
                            .font(.dsCaption)
                            .foregroundStyle(DSColor.textMuted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, DSSpacing.lg)

                    SecureField("PIN", text: currentBinding)
                        .keyboardType(.numberPad)
                        .textContentType(.newPassword)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 32, weight: .bold, design: .monospaced, relativeTo: .title))
                        .frame(height: 56)
                        .padding(.horizontal, DSSpacing.lg)
                        .background(DSColor.bgCard)
                        .cornerRadius(DSRadius.medium)
                        .focused($focused)
                        .padding(.horizontal, DSSpacing.lg)
                        .onChange(of: currentValue) { _, new in
                            if new.count > 4 { trim() }
                            if currentValue.count == 4 { advance() }
                        }

                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.dsBadge)
                            .foregroundStyle(DSColor.negative)
                    }

                    Spacer()
                    Spacer()
                }
                .padding(.vertical, DSSpacing.lg)
            }
            .navigationTitle("Set PIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .tint(DSColor.textSecondary)
                }
            }
            .task {
                try? await Task.sleep(for: .milliseconds(300))
                focused = true
            }
        }
        .interactiveDismissDisabled()
    }

    // MARK: - Step routing

    private var title: String {
        switch step {
        case .create:  "Create PIN"
        case .confirm: "Confirm PIN"
        }
    }

    private var subtitle: String {
        switch step {
        case .create:  "Pick a 4-digit PIN. You'll use it if biometric fails."
        case .confirm: "Re-enter the same PIN to confirm."
        }
    }

    private var currentBinding: Binding<String> {
        switch step {
        case .create:  $firstPIN
        case .confirm: $confirmPIN
        }
    }

    private var currentValue: String {
        switch step {
        case .create:  firstPIN
        case .confirm: confirmPIN
        }
    }

    private func trim() {
        switch step {
        case .create:  firstPIN  = String(firstPIN.prefix(4))
        case .confirm: confirmPIN = String(confirmPIN.prefix(4))
        }
    }

    private func advance() {
        switch step {
        case .create:
            errorMessage = ""
            withAnimation(.dsEase) {
                step = .confirm
            }
        case .confirm:
            if confirmPIN == firstPIN {
                guard lock.savePIN(firstPIN) else {
                    // Keychain write failed — do NOT call onComplete (which would
                    // enable App Lock with no stored PIN and lock the user out).
                    errorMessage = "Couldn't save your PIN. Please try again."
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    firstPIN = ""
                    confirmPIN = ""
                    withAnimation(.dsEase) {
                        step = .create
                    }
                    return
                }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onComplete()
                dismiss()
            } else {
                errorMessage = "PINs don't match. Start over."
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                firstPIN = ""
                confirmPIN = ""
                withAnimation(.dsEase) {
                    step = .create
                }
            }
        }
    }
}

#Preview {
    PINSetupSheet()
        .environment(AppLockManager())
}
