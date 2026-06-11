import Observation
import SwiftData
import SwiftUI
import Foundation

/// Business state + logic for AddTransactionView (adapted from Spendy's
/// AddTransactionV2 / AddTransactionViewModel). Anka-only: no ML, no
/// recurring, no accounts, no Tag @Model — tags are plain Strings.
@MainActor
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

    // MARK: - ML state
    var isMLAssigned: Bool = false
    var latestMLCategory: Category? = nil

    // MARK: - NLP parse state
    /// Currency code extracted by the natural-language parser (e.g. "USD").
    /// Persisted on save; falls back to `AppCurrency.code` when nil.
    var parsedCurrencyCode: String? = nil
    /// Confidence (0–1) of the last description parse. Exposed for potential
    /// UI feedback — the parse itself is silent.
    var parseConfidence: Double = 0

    /// Pulses the sparkle icon while the user is actively describing.
    var sparkleActive: Bool { !descriptionText.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Pending debounced prediction task — cancelled on text change / dismiss.
    @ObservationIgnored private var predictionTask: Task<Void, Never>?

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
                currencyCode: parsedCurrencyCode ?? AppCurrency.code,
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

    // MARK: - NLP parsing

    /// Parse the description into amount + currency + cleaned note, applying the
    /// results to the editable fields, then re-run ML on the cleaned note.
    ///
    /// Called on **commit** (the description field's return key) rather than on
    /// every keystroke: mutating the bound text mid-typing fights the user's
    /// cursor, and `AddTransactionView`'s focus state has documented transient
    /// blips that make per-keystroke / focus-change parsing unsafe.
    ///
    /// Non-destructive: only runs for new entries, only fills the amount when
    /// the user hasn't typed one, and leaves the live ML pass alone when there's
    /// nothing to extract.
    func applyParsedDescription(predictor: CategoryPredictor) {
        // Never rewrite a loaded transaction's fields.
        guard existingTransaction == nil else { return }
        let raw = descriptionText
        guard !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let parsed = TransactionParser.shared.parse(raw)
        parseConfidence = parsed.confidence

        // Nothing extractable and the note is unchanged → leave the live ML alone.
        if parsed.amount == nil && parsed.note == raw { return }

        // Auto-fill the amount only when the user hasn't entered one yet.
        if let amount = parsed.amount, amountText.isEmpty {
            amountText = Self.amountText(from: amount)
            parsedCurrencyCode = parsed.currencyCode
        }

        // Replace the note with the cleaned text (programmatic set — does not
        // re-fire the field's onChange, so no recursion).
        if parsed.note != raw {
            descriptionText = parsed.note
        }

        // Re-categorize on the cleaned note.
        if parsed.note.isEmpty {
            cancelMLPrediction()
        } else {
            triggerMLPrediction(note: parsed.note, predictor: predictor)
        }
    }

    /// Formats a parsed amount into the `amountText` representation (whole
    /// numbers without a trailing ".0", matching `loadExisting`).
    private static func amountText(from amount: Double) -> String {
        amount.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(amount))
            : String(amount)
    }

    // MARK: - ML Prediction
    // `predictor` is passed in from the view's @Environment so the model stays
    // loaded at app-root and isn't recreated on every sheet open.

    func triggerMLPrediction(note: String, predictor: CategoryPredictor) {
        predictionTask?.cancel()
        guard !note.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        predictionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, let self else { return }
            let amount = self.parsedAmount
            guard let pred = predictor.predict(note: note, amount: amount) else { return }
            await MainActor.run { [weak self] in
                self?.applyMLPrediction(pred)
            }
        }
    }

    func cancelMLPrediction() {
        predictionTask?.cancel()
        predictionTask = nil
    }

    private func applyMLPrediction(_ pred: Prediction) {
        guard pred.shouldAutoAssign || pred.shouldShowChip else { return }

        // Prefer a match in the currently-selected type. If none exists,
        // fall back to the opposite type and auto-switch — handles cases
        // like typing "gaji" / "salary" while still on Expense mode.
        let match: Category? = {
            if let m = allCategories.first(where: { $0.name == pred.category && $0.type == selectedType }) {
                return m
            }
            return allCategories.first { $0.name == pred.category }
        }()

        guard let match, match.id != selectedCategory?.id else { return }

        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
            if match.type != selectedType {
                selectedType = match.type
            }
            selectedCategory = match
            isMLAssigned = true
            latestMLCategory = match
        }
    }

    /// Build snapshots for the on-device trainer. Called after a successful save.
    func trainableSnapshots() -> [TrainableTransaction] {
        allTransactions.compactMap { tx in
            guard let categoryName = tx.category?.name,
                  let note = tx.note,
                  !note.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return TrainableTransaction(note: note, amount: tx.amount, categoryName: categoryName)
        }
    }
}
