import SwiftUI
import SwiftData

/// Compact, capsule-shaped slot shown in the category + date + Save row.
/// Displays the selected category (emoji + name) or a placeholder, and calls
/// `onTap` so the parent can present the picker sheet.
struct CategorySlotView: View {
    let category: Category?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DSSpacing.sm) {
                if let category {
                    Text(category.emoji)
                        .font(.dsBody)
                    Text(category.name)
                        .font(.dsBody)
                        .foregroundStyle(DSColor.textPrimary)
                        .lineLimit(1)
                } else {
                    Image(systemName: "square.grid.2x2")
                        .font(.dsCaption)
                        .foregroundStyle(DSColor.textMuted)
                    Text("Category")
                        .font(.dsBody)
                        .foregroundStyle(DSColor.textMuted)
                }
            }
            .padding(.horizontal, DSSpacing.md)
            .frame(height: 48)
            .background(DSColor.bgCard, in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(DSColor.textPrimary)
    }
}

struct CategoryPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var allCategories: [Category]

    let selectedCategory: Category?
    let onSelect: (Category) -> Void

    @State private var tab: TransactionType = .expense

    private var categories: [Category] {
        allCategories.filter { $0.type == tab }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Type", selection: $tab) {
                    Text("Expenses").tag(TransactionType.expense)
                    Text("Income").tag(TransactionType.income)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, DSSpacing.lg)
                .padding(.bottom, DSSpacing.sm)

                List(categories) { category in
                    Button {
                        onSelect(category)
                        dismiss()
                    } label: {
                        HStack(spacing: DSSpacing.md) {
                            Text(category.emoji)
                                .font(.dsBody)
                            Text(category.name)
                                .font(.dsBody)
                                .foregroundStyle(DSColor.textPrimary)
                            Spacer()
                            if selectedCategory?.id == category.id {
                                Image(systemName: "checkmark")
                                    .font(.dsBody)
                                    .foregroundStyle(DSColor.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .listRowBackground(DSColor.bgPrimary)
                    .listRowSeparatorTint(DSColor.textMuted.opacity(0.2))
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(DSColor.bgPrimary)
            }
            .background(DSColor.bgPrimary)
            .navigationTitle("Category")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(DSColor.bgPrimary)
        .onAppear { tab = selectedCategory?.type ?? .expense }
    }
}
