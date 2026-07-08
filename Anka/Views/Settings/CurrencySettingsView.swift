import SwiftUI

/// Default currency picker, pushed from Settings → Default Currency.
///
/// Selection is backed by `AppCurrency.code` (shared App Group defaults), so
/// the widget extension and new-transaction defaults pick it up immediately.
/// Existing transactions keep their stored `currencyCode` — only formatting
/// and new transactions follow the new default (Phase 3b).
struct CurrencySettingsView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(AppearanceManager.self) private var appearance

    @State private var selected = AppCurrency.code

    var body: some View {
        List {
            Section {
                ForEach(CurrencyInfo.all) { currency in
                    currencyRow(currency)
                }
            } footer: {
                Text("Changes how amounts are displayed and the currency new transactions use. Existing transactions keep their original currency.")
            }
            .listRowBackground(appearance.bgCard(scheme))
        }
        .scrollContentBackground(.hidden)
        .background(appearance.bgGrouped(scheme))
        .navigationTitle("Default Currency")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func currencyRow(_ currency: CurrencyInfo) -> some View {
        Button {
            withAnimation(.dsEase) {
                selected = currency.code
                AppCurrency.code = currency.code
            }
        } label: {
            HStack(spacing: DSSpacing.md) {
                Text(currency.symbol)
                    .frame(width: 28)
                    .foregroundStyle(DSColor.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(currency.name)
                        .foregroundStyle(DSColor.textPrimary)
                    Text(currency.code)
                        .font(.dsCaption)
                        .foregroundStyle(DSColor.textMuted)
                }

                Spacer()

                if selected == currency.code {
                    Image(systemName: "checkmark")
                        .font(.dsBodySemi)
                        .foregroundStyle(DSColor.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        CurrencySettingsView()
    }
    .environment(AppearanceManager())
}
