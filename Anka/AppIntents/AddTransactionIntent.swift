import AppIntents
import SwiftData

/// Lets `TransactionType` be used as an `@Parameter` (Siri/Shortcuts picker
/// for Expense vs Income).
extension TransactionType: AppEnum {
    nonisolated static let typeDisplayRepresentation: TypeDisplayRepresentation = "Transaction Type"
    nonisolated static let caseDisplayRepresentations: [TransactionType: DisplayRepresentation] = [
        .expense: "Expense",
        .income: "Income",
    ]
}

/// "V1-style" structured Siri/Shortcuts intent — mirrors the classic Add
/// Transaction sheet: explicit amount, type, category, optional note/date.
struct AddTransactionIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Transaction"
    static let description = IntentDescription("Add an expense or income to Anka with an amount and category.")

    @Parameter(title: "Amount")
    var amount: Double

    @Parameter(title: "Type", default: .expense)
    var type: TransactionType

    @Parameter(title: "Category")
    var category: CategoryEntity

    @Parameter(title: "Note")
    var note: String?

    @Parameter(title: "Date")
    var date: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$type) of \(\.$amount) in \(\.$category)") {
            \.$note
            \.$date
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try AnkaModelContainer.makeContext()
        let categoryID = category.id
        let resolvedCategory = try context.fetch(
            FetchDescriptor<Category>(predicate: #Predicate { $0.id == categoryID })
        ).first

        let tx = Transaction(
            amount: amount,
            type: type,
            date: date ?? Date(),
            note: note,
            category: resolvedCategory,
            currencyCode: AppCurrency.code
        )
        context.insert(tx)
        try context.save()
        postSaveSideEffects(context: context)

        let dialog = "Added \(type.displayName.lowercased()) of \(amount.rupiah) in \(resolvedCategory?.name ?? "Uncategorized")"
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}
