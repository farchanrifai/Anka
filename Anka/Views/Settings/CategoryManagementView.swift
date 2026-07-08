import SwiftUI
import SwiftData

struct CategoryManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @Environment(AppearanceManager.self) private var appearance
    @Bindable var viewModel: SettingsViewModel

    /// Category pending swipe-deletion — drives the confirmation dialog.
    @State private var pendingDelete: Category?

    private var expenses: [Category] {
        viewModel.categories
            .filter { $0.type == .expense }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var incomes: [Category] {
        viewModel.categories
            .filter { $0.type == .income }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        List {
            Section("Expense") {
                ForEach(expenses) { category in
                    categoryRow(category)
                }
                .onDelete { offsets in
                    requestDelete(from: expenses, at: offsets)
                }
                .onMove { from, to in
                    move(in: expenses, from: from, to: to)
                }
            }
            .listRowBackground(appearance.bgCard(scheme))

            Section("Income") {
                ForEach(incomes) { category in
                    categoryRow(category)
                }
                .onDelete { offsets in
                    requestDelete(from: incomes, at: offsets)
                }
                .onMove { from, to in
                    move(in: incomes, from: from, to: to)
                }
            }
            .listRowBackground(appearance.bgCard(scheme))
        }
        .scrollContentBackground(.hidden)
        .background(appearance.bgGrouped(scheme))
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
                    .tint(DSColor.accent)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.startAddCategory()
                } label: {
                    Image(systemName: "plus")
                }
                .tint(DSColor.accent)
            }
        }
        .sheet(isPresented: $viewModel.showAddCategory) {
            AddEditCategorySheet(viewModel: viewModel)
        }
        .confirmationDialog(
            deleteDialogTitle,
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Category", role: .destructive) {
                if let cat = pendingDelete { delete(cat) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text(deleteDialogMessage)
        }
        .alert("Something Went Wrong", isPresented: Binding(
            get: { viewModel.categoryErrorMessage != nil },
            set: { if !$0 { viewModel.categoryErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.categoryErrorMessage = nil }
        } message: {
            Text(viewModel.categoryErrorMessage ?? "An unknown error occurred. Please try again.")
        }
    }

    // MARK: - Delete confirmation copy

    private var deleteDialogTitle: String {
        guard let cat = pendingDelete else { return "Delete Category?" }
        return "Delete \"\(cat.name)\"?"
    }

    private var deleteDialogMessage: String {
        let count = pendingDelete?.transactions.count ?? 0
        guard count > 0 else {
            return "This category has no transactions and will be removed."
        }
        let noun = count == 1 ? "transaction" : "transactions"
        return "\(count) \(noun) will be kept and moved to Uncategorized. The category itself is removed."
    }

    // MARK: - Row

    private func categoryRow(_ category: Category) -> some View {
        Button {
            viewModel.startEditCategory(category)
        } label: {
            HStack(spacing: DSSpacing.md) {
                ZStack {
                    Circle()
                        .fill(Color(hex: category.colorHex).opacity(DSOpacity.subtle))
                        .frame(width: 32, height: 32)
                    Text(category.emoji)
                        .font(.system(size: 18, relativeTo: .headline))
                }

                Text(category.name)
                    .foregroundStyle(DSColor.textPrimary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.dsCaptionSemi)
                    .foregroundStyle(DSColor.textMuted)
            }
        }
    }

    // MARK: - Mutations

    /// Swipe-to-delete: don't delete immediately — confirm first, since the
    /// category may have transactions that will be moved to Uncategorized.
    private func requestDelete(from list: [Category], at offsets: IndexSet) {
        guard let index = offsets.first, list.indices.contains(index) else { return }
        pendingDelete = list[index]
    }

    private func delete(_ category: Category) {
        modelContext.delete(category)
        do {
            try modelContext.save()
        } catch {
            viewModel.categoryErrorMessage = "Couldn't delete the category. Please try again."
        }
    }

    private func move(in list: [Category], from source: IndexSet, to destination: Int) {
        var ordered = list
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, category) in ordered.enumerated() {
            category.sortOrder = index
        }
        do {
            try modelContext.save()
        } catch {
            viewModel.categoryErrorMessage = "Couldn't reorder categories. Please try again."
        }
    }
}

#Preview {
    NavigationStack {
        CategoryManagementView(viewModel: SettingsViewModel())
    }
    .modelContainer(SampleData.container())
    .environment(AppearanceManager())
}
