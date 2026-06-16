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

    @AppStorage("anka.hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage(TransactionEntryLayout.storageKey) private var entryLayoutRaw = TransactionEntryLayout.v1.rawValue
    @AppStorage(InlineComposerPrefs.saveClosesKey) private var saveClosesComposer = true
    @AppStorage("anka.showDecimals") private var showDecimals = false

    var body: some View {
        @Bindable var vm = viewModel

        NavigationStack {
            List {
                // MARK: General
                Section("General") {
                    NavigationLink {
                        CategoryManagementView(viewModel: viewModel)
                    } label: {
                        Label("Categories", systemImage: "square.grid.2x2.fill")
                            .badge(viewModel.categories.count)
                    }

                    NavigationLink {
                        CurrencySettingsView()
                    } label: {
                        Label("Currency", systemImage: "dollarsign.circle.fill")
                            .badge(AppCurrency.code)
                    }

                    Toggle(isOn: $showDecimals) {
                        Label("Show Decimals", systemImage: "textformat.123")
                    }
                    .tint(DSColor.accent)
                    .onChange(of: showDecimals) { AppCurrency.showDecimals = $0 }
                }
                .labelIconTinted()
                .listRowBackground(appearance.bgCard(scheme))

                // MARK: Appearance
                Section("Appearance") {
                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        Label("Theme", systemImage: appearance.mode.symbolName)
                            .badge(appearanceBadge)
                    }
                }
                .labelIconTinted()
                .listRowBackground(appearance.bgCard(scheme))

                // MARK: Input
                inputMethodSection
                    .listRowBackground(appearance.bgCard(scheme))

                // MARK: Security
                securitySection
                    .listRowBackground(appearance.bgCard(scheme))

                // MARK: Data
                Section("Data") {
                    NavigationLink {
                        BackupSettingsView()
                    } label: {
                        Label("Backup & Restore", systemImage: "externaldrive.fill")
                    }

                    NavigationLink {
                        DataManagementView()
                    } label: {
                        Label("Import & Export", systemImage: "square.and.arrow.up.on.square")
                    }
                }
                .labelIconTinted()
                .listRowBackground(appearance.bgCard(scheme))

                // MARK: About + Developer
                Section("About") {
                    LabeledContent("Version", value: appVersion)

                    NavigationLink {
                        developerPage
                    } label: {
                        Label("Developer", systemImage: "hammer.fill")
                    }
                }
                .labelIconTinted()
                .listRowBackground(appearance.bgCard(scheme))
            }
            .scrollContentBackground(.hidden)
            .background(appearance.bgGrouped(scheme))
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .tint(DSColor.textSecondary)
                }
            }
        }
        .preferredColorScheme(appearance.effectiveScheme)
        .task { viewModel.update(categories: allCategories) }
        .onChange(of: allCategories) { _, new in viewModel.update(categories: new) }
    }

    // MARK: - Developer page

    @AppStorage("useMainPageV2") private var useMainPageV2 = false

    private var developerPage: some View {
        List {
            Section {
                Toggle(isOn: $useMainPageV2) {
                    Label("Main Page V2", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tint(DSColor.accent)
            } header: {
                Text("Experimental")
            } footer: {
                Text("Replaces the main dashboard with the V2 layout. Takes effect immediately.")
            }

            Section {
                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        hasCompletedOnboarding = false
                    }
                } label: {
                    Label("Replay Onboarding", systemImage: "sparkles")
                        .foregroundStyle(DSColor.textPrimary)
                }
            } footer: {
                Text("Re-launches the welcome flow. Transactions and categories are not affected.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(appearance.bgGrouped(scheme))
        .navigationTitle("Developer")
        .navigationBarTitleDisplayMode(.inline)
        .labelIconTinted()
    }

    // MARK: - Input method section

    @ViewBuilder
    private var inputMethodSection: some View {
        let layout = TransactionEntryLayout.current(from: entryLayoutRaw)

        Section {
            Picker(selection: Binding(
                get: { layout },
                set: { entryLayoutRaw = $0.rawValue }
            )) {
                ForEach(TransactionEntryLayout.allCases) { layout in
                    Text(layout.displayName).tag(layout)
                }
            } label: {
                Label("Entry Layout", systemImage: "keyboard")
            }
            .pickerStyle(.menu)
            .tint(DSColor.textSecondary)

            if layout == .v3 {
                Toggle(isOn: $saveClosesComposer) {
                    Label("Close After Saving", systemImage: "rectangle.bottomthird.inset.filled")
                }
                .tint(DSColor.accent)
            }
        } header: {
            Text("Input")
        } footer: {
            if layout == .v3 {
                Text("Natural-language entry — \"5k coffee\" or \"100k grabfood yesterday\". When off, the composer stays open for rapid multi-entry.")
            }
        }
        .labelIconTinted()
    }

    // MARK: - Security section

    @ViewBuilder
    private var securitySection: some View {
        @Bindable var lockBindable = lock

        Section("Security") {
            Toggle(isOn: Binding(
                get: { lock.appLockEnabled },
                set: { newValue in
                    if newValue {
                        if lock.hasPIN { engageLock() } else { showPINSetup = true }
                    } else {
                        lock.appLockEnabled = false
                    }
                }
            )) {
                Label("App Lock", systemImage: "lock.fill")
            }
            .tint(DSColor.accent)

            if lock.appLockEnabled, lock.hasPIN {
                if lock.canUseBiometrics {
                    Toggle(isOn: Binding(
                        get: { lock.biometricEnabled },
                        set: { lock.biometricEnabled = $0 }
                    )) {
                        Label(biometricRowLabel, systemImage: biometricRowIcon)
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
                    Label("Require Unlock", systemImage: "clock.fill")
                }
                .tint(DSColor.textSecondary)

                Button {
                    showPINSetup = true
                } label: {
                    Label("Change PIN", systemImage: "key.fill")
                        .foregroundStyle(DSColor.textPrimary)
                }

                Button(role: .destructive) {
                    showRemovePINConfirm = true
                } label: {
                    Label("Remove PIN", systemImage: "lock.slash.fill")
                }
            }
        }
        .labelIconTinted()
        .sheet(isPresented: $showPINSetup) {
            PINSetupSheet { engageLock() }
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

    // MARK: - Helpers

    private func engageLock() {
        lock.appLockEnabled = true
        lock.lock()
        dismiss()
    }

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

// Applies accent tint to all Label icons within a section without
// repeating `.foregroundStyle(DSColor.accent)` on every image.
private extension View {
    func labelIconTinted() -> some View {
        self.tint(DSColor.accent)
    }
}

#Preview {
    SettingsView()
        .modelContainer(SampleData.container())
        .environment(AppLockManager())
        .environment(AppearanceManager())
}
