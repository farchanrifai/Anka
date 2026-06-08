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
                            lock.appLockEnabled = true
                        } else {
                            showPINSetup = true
                        }
                    } else {
                        lock.appLockEnabled = false
                    }
                }
            )) {
                Label {
                    Text(lockToggleLabel)
                } icon: {
                    Image(systemName: lockToggleIcon)
                        .foregroundStyle(DSColor.accent)
                }
            }
            .tint(DSColor.accent)

            if lock.appLockEnabled, lock.hasPIN {
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
                lock.appLockEnabled = true
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

    private var lockToggleLabel: String {
        switch lock.biometricType {
        case .faceID:  return "Face ID & PIN"
        case .touchID: return "Touch ID & PIN"
        case .opticID: return "Optic ID & PIN"
        case .none:    return "App Lock (PIN)"
        @unknown default: return "App Lock (PIN)"
        }
    }

    private var lockToggleIcon: String {
        switch lock.biometricType {
        case .faceID:  return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        case .none:    return "lock.fill"
        @unknown default: return "lock.fill"
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
