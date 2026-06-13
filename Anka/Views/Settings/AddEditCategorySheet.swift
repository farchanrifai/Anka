import SwiftUI
import SwiftData

struct AddEditCategorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var viewModel: SettingsViewModel

    @State private var showDeleteConfirm = false

    private var isEditing: Bool { viewModel.editingCategory != nil }
    private var title: String { isEditing ? "Edit Category" : "Add Category" }

    var body: some View {
        NavigationStack {
            ZStack {
                DSColor.bgPrimary.ignoresSafeArea()

                VStack(spacing: DSSpacing.lg) {
                    emojiField
                    nameField
                    typePicker
                    Spacer()
                    actionButtons
                }
                .padding(DSSpacing.lg)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        viewModel.cancelEdit()
                        dismiss()
                    }
                    .foregroundStyle(DSColor.textSecondary)
                }
            }
            .confirmationDialog(
                deleteDialogTitle,
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete Category", role: .destructive) { deleteEditing() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(deleteDialogMessage)
            }
        }
    }

    // MARK: - Delete confirmation copy

    private var deleteDialogTitle: String {
        guard let cat = viewModel.editingCategory else { return "Delete Category?" }
        return "Delete \"\(cat.name)\"?"
    }

    private var deleteDialogMessage: String {
        let count = viewModel.editingCategory?.transactions.count ?? 0
        guard count > 0 else {
            return "This category has no transactions and will be removed."
        }
        let noun = count == 1 ? "transaction" : "transactions"
        return "\(count) \(noun) will be kept and moved to Uncategorized. The category itself is removed."
    }

    // MARK: - Fields

    private var emojiField: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text("Emoji")
                .font(.dsCaption)
                .foregroundStyle(DSColor.textMuted)

            TextField("", text: $viewModel.newCategoryEmoji)
                .font(.system(size: 32))
                .foregroundStyle(DSColor.textPrimary)
                .frame(height: 56)
                .padding(DSSpacing.md)
                .background(DSColor.bgCard)
                .cornerRadius(DSRadius.medium)
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text("Name")
                .font(.dsCaption)
                .foregroundStyle(DSColor.textMuted)

            TextField("Category name", text: $viewModel.newCategoryName)
                .font(.dsBody)
                .foregroundStyle(DSColor.textPrimary)
                .padding(DSSpacing.md)
                .background(DSColor.bgCard)
                .cornerRadius(DSRadius.medium)
        }
    }

    private var typePicker: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text("Type")
                .font(.dsCaption)
                .foregroundStyle(DSColor.textMuted)

            Picker("Type", selection: $viewModel.newCategoryType) {
                Text("Expense").tag(TransactionType.expense)
                Text("Income").tag(TransactionType.income)
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Actions

    private var actionButtons: some View {
        HStack(spacing: DSSpacing.md) {
            if isEditing {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.dsBody)
                        .foregroundStyle(DSColor.textOnAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(DSColor.negative)
                        .cornerRadius(DSRadius.medium)
                }
            }

            Button {
                save()
            } label: {
                Text("Save")
                    .font(.dsBody)
                    .foregroundStyle(DSColor.textOnAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(viewModel.isFormValid ? DSColor.accent : DSColor.bgCard)
                    .cornerRadius(DSRadius.medium)
            }
            .disabled(!viewModel.isFormValid)
        }
    }

    // MARK: - Persistence

    private func save() {
        let name = viewModel.newCategoryName.trimmingCharacters(in: .whitespaces)
        let emoji = viewModel.newCategoryEmoji.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !emoji.isEmpty else { return }

        if let existing = viewModel.editingCategory {
            existing.name = name
            existing.emoji = emoji
            existing.colorHex = viewModel.newCategoryColor
            existing.type = viewModel.newCategoryType
        } else {
            let nextSortOrder = (viewModel.categories.map(\.sortOrder).max() ?? 0) + 1
            let newCategory = Category(
                name: name,
                emoji: emoji,
                colorHex: viewModel.newCategoryColor,
                type: viewModel.newCategoryType,
                sortOrder: nextSortOrder
            )
            modelContext.insert(newCategory)
        }

        try? modelContext.save()
        viewModel.cancelEdit()
        dismiss()
    }

    private func deleteEditing() {
        guard let category = viewModel.editingCategory else { return }
        modelContext.delete(category)
        try? modelContext.save()
        viewModel.cancelEdit()
        dismiss()
    }
}
