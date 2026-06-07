import Observation
import SwiftData
import Foundation

/// Business state + logic for AddTransactionView (adapted from Spendy's
/// AddTransactionV2 / AddTransactionViewModel). Anka-only: no ML, no
/// recurring, no accounts, no Tag @Model — tags are plain Strings.
@Observable
final class AddTransactionViewModel {
    // MARK: - User-edited state
    var selectedType: TransactionType
    var selectedCategory: Category?
    var selectedDate: Date
    var descriptionText: String
    var amountText: String
    var selectedTags: [String]
    var tagInput: String

    // MARK: - ML placeholders (not used at MVP — kept so view code mirrors V2)
    var isMLAssigned: Bool = false
    var latestMLCategory: Category? = nil
    var sparkleActive: Bool = false

    // MARK: - Snapshot from Queries
    private(set) var allCategories: [Category] = []
    private(set) var allTransactions: [Transaction] = []

    let existingTransaction: Transaction?

    init(defaultType: TransactionType, existingTransaction: Transaction? = nil) {
        self.selectedType = defaultType
        self.existingTransaction = existingTransaction
        self.selectedCategory = nil
        self.selectedDate = Date()
        self.descriptionText = ""
        self.amountText = ""
        self.selectedTags = []
        self.tagInput = ""
    }

    // MARK: - Data feed
    func update(categories: [Category], allTransactions: [Transaction]) {
        self.allCategories = categories
        self.allTransactions = allTransactions
    }

    // MARK: - Derived

    var filteredCategories: [Category] {
        allCategories
            .filter { $0.type == selectedType }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var parsedAmount: Double {
        let cleaned = amountText
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
        return Double(cleaned) ?? 0
    }

    var formattedAmountDisplay: String {
        let value = parsedAmount
        guard value > 0 else { return amountText }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        f.maximumFractionDigits = amountText.contains(".") ? 2 : 0
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? amountText
    }

    var dateChipLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(selectedDate) { return "Today" }
        if cal.isDateInYesterday(selectedDate) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f.string(from: selectedDate)
    }

    var isValid: Bool {
        parsedAmount > 0 && selectedCategory != nil
    }

    // MARK: - Type change

    func changeType(_ type: TransactionType) {
        selectedType = type
        if let cat = selectedCategory, cat.type != type {
            selectedCategory = nil
            isMLAssigned = false
            latestMLCategory = nil
        }
    }

    // MARK: - Tag autocomplete

    /// Suggested completion of `tagInput`, drawn from tags on recent transactions.
    var shadowSuggestion: String {
        let prefix = tagInput.lowercased()
        guard !prefix.isEmpty else { return "" }
        let known = Set(allTransactions.flatMap { $0.tags }.map { $0.lowercased() })
        let alreadyPicked = Set(selectedTags.map { $0.lowercased() })
        if let match = known.first(where: {
            $0.hasPrefix(prefix) && $0 != prefix && !alreadyPicked.contains($0)
        }) {
            return String(match.dropFirst(prefix.count))
        }
        return ""
    }

    func commitTag(context: ModelContext) {
        // If there's a shadow suggestion, prefer the full suggested token.
        let raw: String
        if !shadowSuggestion.isEmpty {
            raw = tagInput + shadowSuggestion
        } else {
            raw = tagInput
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { tagInput = ""; return }
        if !selectedTags.contains(where: { $0.lowercased() == trimmed.lowercased() }) {
            selectedTags.append(trimmed)
        }
        tagInput = ""
    }

    func removeTag(_ tag: String) {
        selectedTags.removeAll { $0 == tag }
    }

    // MARK: - Load / save / delete

    func loadExisting(_ tx: Transaction) {
        selectedType = tx.type
        selectedCategory = tx.category
        selectedDate = tx.date
        descriptionText = tx.note ?? ""
        amountText = tx.amount.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(tx.amount))
            : String(tx.amount)
        selectedTags = tx.tags
    }

    /// Returns true on successful save, false if validation fails (so view can shake).
    func save(context: ModelContext) throws -> Bool {
        guard isValid else { return false }
        let trimmedNote = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let tx = existingTransaction {
            tx.amount = parsedAmount
            tx.type = selectedType
            tx.date = selectedDate
            tx.note = trimmedNote.isEmpty ? nil : trimmedNote
            tx.category = selectedCategory
            tx.tags = selectedTags
        } else {
            let tx = Transaction(
                amount: parsedAmount,
                type: selectedType,
                date: selectedDate,
                note: trimmedNote.isEmpty ? nil : trimmedNote,
                category: selectedCategory,
                currencyCode: "IDR",
                tags: selectedTags
            )
            context.insert(tx)
        }
        try context.save()
        return true
    }

    func deleteTransaction(context: ModelContext) throws {
        guard let tx = existingTransaction else { return }
        context.delete(tx)
        try context.save()
    }

    // MARK: - ML stubs (kept so view code mirrors V2 — never fire)

    func triggerMLPrediction(note: String) {}
    func cancelMLPrediction() {}
}
