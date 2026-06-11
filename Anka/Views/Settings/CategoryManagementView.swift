import SwiftUI
import SwiftData

struct CategoryManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var scheme
    @Environment(AppearanceManager.self) private var appearance
    @Bindable var viewModel: SettingsViewModel

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
                    delete(from: expenses, at: offsets)
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
                    delete(from: incomes, at: offsets)
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
                        .font(.system(size: 18))
                }

                Text(category.name)
                    .foregroundStyle(DSColor.textPrimary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DSColor.textMuted)
            }
        }
    }

    // MARK: - Mutations

    private func delete(from list: [Category], at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(list[index])
        }
        try? modelContext.save()
    }

    private func move(in list: [Category], from source: IndexSet, to destination: Int) {
        var ordered = list
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, category) in ordered.enumerated() {
            category.sortOrder = index
        }
        try? modelContext.save()
    }
}

#Preview {
    NavigationStack {
        CategoryManagementView(viewModel: SettingsViewModel())
    }
    .modelContainer(SampleData.container())
    .environment(AppearanceManager())
}
