import SwiftUI
import SwiftData

struct AddEditCategorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var viewModel: SettingsViewModel

    @State private var showDeleteConfirm = false
    @State private var saveErrorMessage: String?

    private var isEditing: Bool { viewModel.editingCategory != nil }
    private var title: String { isEditing ? "Edit Category" : "Add Category" }

    var body: some View {
        NavigationStack {
            ZStack {
                DSColor.bgPrimary.ignoresSafeArea()

                VStack(spacing: DSSpacing.lg) {
                    emojiField
                    nameField
                    colorField
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
            .alert("Save Failed", isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { saveErrorMessage = nil }
            } message: {
                Text(saveErrorMessage ?? "An unknown error occurred. Please try again.")
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
                // Keep only the last entered grapheme so the field holds a
                // single emoji (U11). Validity (emoji vs. letter/digit) is
                // enforced by `viewModel.isEmojiValid` gating Save.
                .onChange(of: viewModel.newCategoryEmoji) { _, new in
                    if new.count > 1 {
                        viewModel.newCategoryEmoji = String(new.suffix(1))
                    }
                }

            if !viewModel.newCategoryEmoji.isEmpty, !viewModel.isEmojiValid {
                fieldNote("Pick a single emoji.", color: DSColor.negative)
            }
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

            if viewModel.isDuplicateName {
                fieldNote("A category named \"\(viewModel.trimmedName)\" already exists.", color: DSColor.negative)
            } else if viewModel.willBreakMLMatching {
                fieldNote("Renaming a default category turns off its smart auto-categorization.", color: DSColor.accentText)
            }
        }
    }

    private var colorField: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text("Color")
                .font(.dsCaption)
                .foregroundStyle(DSColor.textMuted)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DSSpacing.md), count: 6),
                      spacing: DSSpacing.md) {
                ForEach(SettingsViewModel.categoryColorOptions, id: \.self) { hex in
                    let isSelected = viewModel.newCategoryColor.caseInsensitiveCompare(hex) == .orderedSame
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 32, height: 32)
                        .overlay {
                            Circle()
                                .strokeBorder(DSColor.textPrimary, lineWidth: isSelected ? 2.5 : 0)
                                .padding(-3)
                        }
                        .contentShape(Circle())
                        .onTapGesture {
                            withAnimation(.dsSnappy) { viewModel.newCategoryColor = hex }
                        }
                        .accessibilityLabel("Color option")
                        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
    }

    private func fieldNote(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.dsCaption2)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
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
        guard viewModel.isFormValid else { return }
        let name = viewModel.trimmedName
        let emoji = viewModel.newCategoryEmoji.trimmingCharacters(in: .whitespacesAndNewlines)

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

        // Surface save failures instead of swallowing them (A5). Keep the sheet
        // open so the user can retry rather than losing their edits silently.
        do {
            try modelContext.save()
        } catch {
            saveErrorMessage = "Couldn't save the category. Please try again."
            return
        }
        viewModel.cancelEdit()
        dismiss()
    }

    private func deleteEditing() {
        guard let category = viewModel.editingCategory else { return }
        modelContext.delete(category)
        do {
            try modelContext.save()
        } catch {
            saveErrorMessage = "Couldn't delete the category. Please try again."
            return
        }
        viewModel.cancelEdit()
        dismiss()
    }
}
