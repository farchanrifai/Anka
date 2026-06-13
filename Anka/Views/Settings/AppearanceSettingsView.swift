import SwiftUI

/// Theme selection sub-page pushed from Settings → Appearance.
///
/// Mode picker:  System · Light · Dark
/// Dark variant: Pure Black (#000000) · Soft Dark (#1A1A1A)
///
/// The Dark Variant section is disabled (greyed) when the user picks Light mode,
/// since the variant only affects the dark palette. Keeping the section visible
/// rather than hiding it avoids a layout shift when the user toggles modes.
struct AppearanceSettingsView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(AppearanceManager.self) private var appearance

    var body: some View {
        @Bindable var appearance = appearance

        List {
            Section {
                ForEach(AppearanceManager.Mode.allCases, id: \.self) { mode in
                    modeRow(mode, binding: $appearance.mode)
                }
            } header: {
                Text("Theme")
            } footer: {
                Text("Choose how Anka adapts to your device's light/dark setting.")
            }
            .listRowBackground(appearance.bgCard(scheme))

            Section {
                ForEach(AppearanceManager.DarkVariant.allCases, id: \.self) { variant in
                    variantRow(variant, binding: $appearance.darkVariant)
                }
            } header: {
                Text("Dark Variant")
            } footer: {
                Text("Pure Black uses #000000 — best on OLED displays. Soft Dark (#1A1A1A) is gentler in low light.")
            }
            .disabled(!appearance.isDarkVariantApplicable)
            .listRowBackground(appearance.bgCard(scheme))
        }
        .scrollContentBackground(.hidden)
        .background(appearance.bgGrouped(scheme))
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Rows

    private func modeRow(_ mode: AppearanceManager.Mode, binding: Binding<AppearanceManager.Mode>) -> some View {
        Button {
            withAnimation(.dsEase) {
                binding.wrappedValue = mode
            }
        } label: {
            HStack(spacing: DSSpacing.md) {
                Image(systemName: mode.symbolName)
                    .frame(width: 28)
                    .foregroundStyle(DSColor.accent)

                Text(mode.displayName)
                    .foregroundStyle(DSColor.textPrimary)

                Spacer()

                if binding.wrappedValue == mode {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DSColor.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func variantRow(_ variant: AppearanceManager.DarkVariant, binding: Binding<AppearanceManager.DarkVariant>) -> some View {
        Button {
            withAnimation(.dsEase) {
                binding.wrappedValue = variant
            }
        } label: {
            HStack(spacing: DSSpacing.md) {
                swatch(for: variant)

                VStack(alignment: .leading, spacing: 2) {
                    Text(variant.displayName)
                        .foregroundStyle(DSColor.textPrimary)
                    Text(variant.hexDescription)
                        .font(.dsCaption)
                        .foregroundStyle(DSColor.textMuted)
                }

                Spacer()

                if binding.wrappedValue == variant {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DSColor.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func swatch(for variant: AppearanceManager.DarkVariant) -> some View {
        let color: Color = {
            switch variant {
            case .black: return Color(hex: "000000")
            case .gray:  return Color(hex: "1A1A1A")
            }
        }()
        return RoundedRectangle(cornerRadius: DSRadius.small)
            .fill(color)
            .frame(width: 28, height: 28)
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.small)
                    .stroke(DSColor.separator, lineWidth: 1)
            )
    }
}

#Preview {
    NavigationStack {
        AppearanceSettingsView()
    }
    .environment(AppearanceManager())
}
