import AppIntents
import SwiftData

/// "V2/inline-style" Siri/Shortcuts intent — a single free-form phrase like
/// "100k grabfood yesterday", parsed exactly like the V3 inline composer via
/// `InlineTransactionParser` + `CategoryPredictor`. Expense-only, mirroring
/// the inline composer (the parser only matches expense categories today).
struct QuickAddTransactionIntent: AppIntent {
    static let title: LocalizedStringResource = "Quick Add Transaction"
    static let description = IntentDescription("Add an expense to Anka using natural language, e.g. \"100k grabfood yesterday\".")

    @Parameter(title: "Description")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Quick add \(\.$text)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try AnkaModelContainer.makeContext()
        let categories = try context.allCategories()

        guard let parsed = InlineTransactionParser().parse(
            text, availableCategories: categories, predictor: AnkaModelContainer.predictor
        ), parsed.amount > 0 else {
            throw $text.needsValueError("I couldn't understand that. Try something like \"100k grabfood yesterday\".")
        }

        let tx = Transaction(
            amount: parsed.amount,
            type: .expense,
            date: parsed.date,
            note: parsed.note,
            category: parsed.category,
            currencyCode: AppCurrency.code
        )
        context.insert(tx)
        try context.save()
        postSaveSideEffects(context: context)

        let dialog = "Added expense of \(parsed.amount.rupiah) for \(parsed.category?.name ?? "Uncategorized")"
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}
