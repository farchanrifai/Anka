import SwiftUI
import SwiftData
import LocalAuthentication

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(AppLockManager.self) private var lock
    @Environment(AppearanceManager.self) private var appearance
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]
    @State private var viewModel = SettingsViewModel()
    @State private var showPINSetup = false
    @State private var showRemovePINConfirm = false

    /// Mirrors the first-run gate in `AnkaApp`. Setting this back to `false`
    /// re-presents the onboarding overlay. It is the *only* thing replaying
    /// onboarding changes — no transactions or categories are touched — so
    /// existing data is preserved whichever option the user picks at the end.
    /// Default matches `AnkaApp` (`false`) so the two `@AppStorage` declarations
    /// can't disagree on a fresh install (AUDIT.md U17).
    @AppStorage("anka.hasCompletedOnboarding") private var hasCompletedOnboarding = false

    /// Experimental Add-Transaction entry layout (Phase 8.5). Drives whether the
    /// `+` opens the classic sheet (V1/V2) or the inline composer (V3).
    @AppStorage(TransactionEntryLayout.storageKey) private var entryLayoutRaw = TransactionEntryLayout.v1.rawValue

    var body: some View {
        @Bindable var vm = viewModel

        NavigationStack {
            List {
                Section("General") {
                    NavigationLink {
                        CategoryManagementView(viewModel: viewModel)
                    } label: {
                        Label {
                            Text("Categories")
                        } icon: {
                            Image(systemName: "square.grid.2x2.fill")
                                .foregroundStyle(DSColor.accent)
                        }
                        .badge(viewModel.categories.count)
                    }

                    LabeledContent {
                        Text(viewModel.defaultCurrency)
                            .foregroundStyle(DSColor.textSecondary)
                    } label: {
                        Label {
                            Text("Default Currency")
                        } icon: {
                            Image(systemName: "dollarsign.circle.fill")
                                .foregroundStyle(DSColor.accent)
                        }
                    }
                }
                .listRowBackground(appearance.bgCard(scheme))

                Section("Appearance") {
                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        Label {
                            Text("Theme")
                        } icon: {
                            Image(systemName: appearance.mode.symbolName)
                                .foregroundStyle(DSColor.accent)
                        }
                        .badge(appearanceBadge)
                    }
                }
                .listRowBackground(appearance.bgCard(scheme))

                inputMethodSection
                    .listRowBackground(appearance.bgCard(scheme))

                securitySection
                    .listRowBackground(appearance.bgCard(scheme))

                Section("Data") {
                    NavigationLink {
                        BackupSettingsView()
                    } label: {
                        Label {
                            Text("Backup & Restore")
                        } icon: {
                            Image(systemName: "externaldrive.fill")
                                .foregroundStyle(DSColor.accent)
                        }
                    }

                    NavigationLink {
                        DataManagementView()
                    } label: {
                        Label {
                            Text("Import & Export")
                        } icon: {
                            Image(systemName: "square.and.arrow.up.on.square")
                                .foregroundStyle(DSColor.accent)
                        }
                    }
                }
                .listRowBackground(appearance.bgCard(scheme))

                Section {
                    LabeledContent("Version", value: appVersion)
                } header: {
                    Text("About")
                }
                .listRowBackground(appearance.bgCard(scheme))

                // Dev-only utility — never ships in Release builds (U17).
                #if DEBUG
                developerSection
                    .listRowBackground(appearance.bgCard(scheme))
                #endif
            }
            // Hide the List's default UIKit-managed background so our
            // variant-aware grouped color shows through. Without these two
            // modifiers the List paints its own systemGroupedBackground and
            // ignores the variant entirely (which was the "Settings page
            // doesn't follow the variant" bug). Each Section also overrides
            // .listRowBackground so row surfaces match the variant.
            .scrollContentBackground(.hidden)
            .background(appearance.bgGrouped(scheme))
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .tint(DSColor.textSecondary)
                }
            }
        }
        // Apply preferredColorScheme unconditionally with a CONCRETE scheme
        // (`effectiveScheme` resolves `.system` to the live OS scheme tracked
        // via UIScreen). Concrete-only + always-applied is critical:
        //
        // 1. Passing nil for `.system` doesn't release the sheet host's
        //    previously-applied override (sheet gets stuck on the last
        //    concrete value, needs the sheet closed and reopened to fix).
        // 2. Conditionally omitting the modifier with @ViewBuilder changes
        //    the view's structural type, which causes SwiftUI to tear down
        //    the NavigationStack inside — popping AppearanceSettingsView
        //    back to the main Settings page on every Light↔Dark↔System
        //    toggle.
        //
        // Tracking the OS scheme separately via UIScreen lets us always
        // pass a real value while still following OS in `.system` mode.
        .preferredColorScheme(appearance.effectiveScheme)
        .task {
            viewModel.update(categories: allCategories)
        }
        .onChange(of: allCategories) { _, new in
            viewModel.update(categories: new)
        }
    }

    // MARK: - Developer section

    /// Dev-only utilities while the app is in active development. Re-launches
    /// the onboarding flow for design review. Replaying onboarding never
    /// mutates SwiftData — it only flips the `hasCompletedOnboarding` flag —
    /// so transactions and categories are left untouched.
    @ViewBuilder
    private var developerSection: some View {
        Section {
            Button {
                // Dismiss Settings first so the onboarding overlay (presented
                // at the app root, beneath any sheet) isn't hidden behind this
                // sheet. The brief delay lets the dismissal animation finish
                // before the overlay fades in.
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    hasCompletedOnboarding = false
                }
            } label: {
                Label {
                    Text("Replay Onboarding")
                        .foregroundStyle(DSColor.textPrimary)
                } icon: {
                    Image(systemName: "sparkles")
                        .foregroundStyle(DSColor.accent)
                }
            }
        } header: {
            Text("Developer")
        } footer: {
            Text("Re-launches the welcome flow. Your transactions and categories are not affected.")
        }
    }

    // MARK: - Input method section (Phase 8.5)

    @ViewBuilder
    private var inputMethodSection: some View {
        Section {
            Picker(selection: $entryLayoutRaw) {
                ForEach(TransactionEntryLayout.allCases) { layout in
                    Text(layout.displayName).tag(layout.rawValue)
                }
            } label: {
                Label {
                    Text("Entry Layout")
                } icon: {
                    Image(systemName: "keyboard")
                        .foregroundStyle(DSColor.accent)
                }
            }
            .pickerStyle(.menu)
            .tint(DSColor.textSecondary)
        } header: {
            Text("Input Method")
        } footer: {
            if entryLayoutRaw == TransactionEntryLayout.v3.rawValue {
                Text("Fast natural-language entry. Type things like \"5k coffee\" or \"100k grabfood yesterday\" — the amount, category and date are detected for you.")
            }
        }
    }

    // MARK: - Security section

    @ViewBuilder
    private var securitySection: some View {
        @Bindable var lockBindable = lock

        Section {
            Toggle(isOn: Binding(
                get: { lock.appLockEnabled },
                set: { newValue in
                    if newValue {
                        // Enabling — require PIN first so biometric failure
                        // can't lock the user out forever.
                        if lock.hasPIN {
                            engageLock()
                        } else {
                            showPINSetup = true
                        }
                    } else {
                        lock.appLockEnabled = false
                    }
                }
            )) {
                Label {
                    Text("App Lock")
                } icon: {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(DSColor.accent)
                }
            }
            .tint(DSColor.accent)

            if lock.appLockEnabled, lock.hasPIN {
                // Let the user choose PIN-only vs. PIN + biometrics (only on
                // hardware that has Face ID / Touch ID / Optic ID).
                if lock.canUseBiometrics {
                    Toggle(isOn: Binding(
                        get: { lock.biometricEnabled },
                        set: { lock.biometricEnabled = $0 }
                    )) {
                        Label {
                            Text(biometricRowLabel)
                        } icon: {
                            Image(systemName: biometricRowIcon)
                                .foregroundStyle(DSColor.accent)
                        }
                    }
                    .tint(DSColor.accent)
                }

                Picker(selection: Binding(
                    get: { lock.gracePeriod },
                    set: { lock.gracePeriod = $0 }
                )) {
                    ForEach(AppLockManager.GracePeriod.allCases) { period in
                        Text(period.displayName).tag(period)
                    }
                } label: {
                    Label {
                        Text("Require Unlock")
                    } icon: {
                        Image(systemName: "clock.fill")
                            .foregroundStyle(DSColor.accent)
                    }
                }
                .tint(DSColor.textSecondary)

                Button {
                    showPINSetup = true
                } label: {
                    Label {
                        Text("Change PIN")
                            .foregroundStyle(DSColor.textPrimary)
                    } icon: {
                        Image(systemName: "key.fill")
                            .foregroundStyle(DSColor.accent)
                    }
                }

                Button(role: .destructive) {
                    showRemovePINConfirm = true
                } label: {
                    Label {
                        Text("Remove PIN")
                    } icon: {
                        Image(systemName: "lock.slash.fill")
                    }
                }
            }
        } header: {
            Text("Security")
        } footer: {
            if lock.appLockEnabled && !lock.canUseBiometrics {
                Text("Biometric authentication not available on this device. PIN is the only unlock method.")
            }
        }
        .sheet(isPresented: $showPINSetup) {
            PINSetupSheet {
                engageLock()
            }
            .environment(lock)
        }
        .confirmationDialog(
            "Remove PIN and disable App Lock?",
            isPresented: $showRemovePINConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove PIN", role: .destructive) {
                lock.removePIN()
                lock.appLockEnabled = false
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Enables the lock and engages it *now*. The lock overlay lives at the app
    /// root, beneath this Settings sheet — so we dismiss Settings too, otherwise
    /// the lock screen (and its biometric prompt) stays hidden until the next
    /// launch (the exact "didn't ask immediately after activating" bug).
    private func engageLock() {
        lock.appLockEnabled = true
        lock.lock()
        dismiss()
    }

    /// "Use Face ID" / "Use Touch ID" / "Use Optic ID" — label for the
    /// biometric opt-in toggle (only shown on biometric-capable hardware).
    private var biometricRowLabel: String {
        switch lock.biometricType {
        case .faceID:  return "Use Face ID"
        case .touchID: return "Use Touch ID"
        case .opticID: return "Use Optic ID"
        default:       return "Use Biometrics"
        }
    }

    private var biometricRowIcon: String {
        switch lock.biometricType {
        case .faceID:  return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        default:       return "lock.fill"
        }
    }

    /// "System · Pure Black" / "Light" / "Dark · Soft Dark".
    /// Hides the dark-variant suffix when it doesn't apply (Light mode).
    private var appearanceBadge: String {
        if appearance.isDarkVariantApplicable {
            return "\(appearance.mode.displayName) · \(appearance.darkVariant.displayName)"
        }
        return appearance.mode.displayName
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}

#Preview {
    SettingsView()
        .modelContainer(SampleData.container())
        .environment(AppLockManager())
        .environment(AppearanceManager())
}
