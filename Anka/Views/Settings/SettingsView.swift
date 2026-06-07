import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortOrder) private var allCategories: [Category]
    @State private var viewModel = SettingsViewModel()

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

                Section("Appearance") {
                    Toggle(isOn: $vm.darkModeEnabled) {
                        Label {
                            Text("Dark Mode")
                        } icon: {
                            Image(systemName: "moon.fill")
                                .foregroundStyle(DSColor.accent)
                        }
                    }
                    .tint(DSColor.accent)
                }

                Section("Data") {
                    Button {
                        // Phase 9+: export
                    } label: {
                        Label {
                            Text("Export")
                                .foregroundStyle(DSColor.textPrimary)
                        } icon: {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(DSColor.accent)
                        }
                    }
                }

                Section {
                    LabeledContent("Version", value: appVersion)
                } header: {
                    Text("About")
                }
            }
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
        .task {
            viewModel.update(categories: allCategories)
        }
        .onChange(of: allCategories) { _, new in
            viewModel.update(categories: new)
        }
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
}
