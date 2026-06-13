import SwiftUI
import SwiftData

/// The Today screen's sheet + alert stack (Stats, Settings, Add, Filter, Edit,
/// plus the delete-confirm and delete-failed alerts). Identical across the
/// Today view variants, so it lives in one modifier applied via `.todaySheets`.
struct TodaySheetsModifier: ViewModifier {
    @Bindable var vm: TodayViewModel
    let allTransactions: [Transaction]
    let allCategories: [Category]
    let namespace: Namespace.ID

    @Environment(\.modelContext) private var modelContext

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $vm.showStats) {
                // Stats inherits Today's month one-way: the selected month when
                // Today is in single-month mode, else the real current month.
                StatsView(
                    transactions: allTransactions,
                    categories: allCategories,
                    initialMonth: vm.selectedPeriod == .month ? vm.selectedMonth : Date().startOfMonth
                )
                .presentationDragIndicator(.visible)
                .navigationTransition(.zoom(sourceID: "stats", in: namespace))
            }
            .sheet(isPresented: $vm.showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $vm.showAddTransaction) {
                AddTransactionView(defaultType: vm.addDefaultType)
                    .navigationTransition(.zoom(sourceID: "addTransaction", in: namespace))
            }
            // The experimental inline composer (Phase 8.5 / V3) is NOT a sheet —
            // it's a Liquid Glass bar applied via `.inlineComposer(vm:)` on the
            // Today views so it rides the keyboard like the Messages composer.
            .sheet(isPresented: $vm.showCategoryFilter) {
                CategoryFilterSheet(
                    selection: $vm.selectedCategories,
                    selectedPeriod: $vm.selectedPeriod,
                    customStartDate: $vm.customStartDate,
                    customEndDate: $vm.customEndDate
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                // Detent is honored — the zoom destination is the sheet's final
                // (half-page) size. Sources from the filter toolbar button.
                .navigationTransition(.zoom(sourceID: "filter", in: namespace))
            }
            .sheet(isPresented: Binding(
                get: { vm.editingTransaction != nil },
                set: { if !$0 { vm.editingTransaction = nil } }
            )) {
                if let tx = vm.editingTransaction {
                    AddTransactionView(defaultType: tx.type, existingTransaction: tx)
                        .navigationTransition(.zoom(sourceID: tx.id, in: namespace))
                }
            }
            .alert("Delete Transaction?", isPresented: Binding(
                get: { vm.pendingDeleteTransaction != nil },
                set: { if !$0 { vm.pendingDeleteTransaction = nil } }
            )) {
                Button("Delete", role: .destructive) { vm.confirmDelete(context: modelContext) }
                Button("Cancel", role: .cancel) { vm.pendingDeleteTransaction = nil }
            } message: {
                Text("This action cannot be undone.")
            }
            .alert("Delete Failed", isPresented: Binding(
                get: { vm.deleteErrorMessage != nil },
                set: { if !$0 { vm.deleteErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { vm.deleteErrorMessage = nil }
            } message: {
                Text(vm.deleteErrorMessage ?? "An unknown error occurred. Please try again.")
            }
    }
}

extension View {
    /// Applies the Today screen's full sheet + alert stack.
    func todaySheets(
        vm: TodayViewModel,
        allTransactions: [Transaction],
        allCategories: [Category],
        namespace: Namespace.ID
    ) -> some View {
        modifier(TodaySheetsModifier(
            vm: vm,
            allTransactions: allTransactions,
            allCategories: allCategories,
            namespace: namespace
        ))
    }
}
