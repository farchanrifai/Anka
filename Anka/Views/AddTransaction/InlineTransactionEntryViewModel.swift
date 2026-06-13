import Observation
import SwiftData
import SwiftUI

/// Which Add-Transaction entry UI to use. `v1`/`v2` both present the classic
/// numpad sheet (`AddTransactionView`); `v3` is the experimental inline
/// natural-language composer (Phase 8.5). Persisted under `storageKey`.
enum TransactionEntryLayout: String, CaseIterable, Identifiable {
    case v1, v2, v3

    var id: String { rawValue }
    static let storageKey = "transactionEntryLayout"

    var isInline: Bool { self == .v3 }

    var displayName: String {
        switch self {
        case .v1: return "V1 · Classic Sheet"
        case .v2: return "V2 · Sheet"
        case .v3: return "V3 · Inline (Experimental)"
        }
    }
}

/// Drives the experimental inline composer (Phase 8.5 / V3): holds the input
/// text, the debounced parse result, an optional manual category override, and
/// the save path. UI-agnostic so the view stays declarative.
@Observable
@MainActor
final class InlineTransactionEntryViewModel {
    /// Bound to the composer's text field.
    var inputText: String = ""
    /// Latest debounced parse (nil until an amount is detected).
    private(set) var parseResult: ParsedInlineTransaction?
    /// User's explicit pick from the category bubble — overrides the parsed one.
    var selectedCategory: Category?
    /// True while a save is in flight, to debounce rapid send taps.
    private(set) var isSaving = false

    private let parser = InlineTransactionParser()
    private var parseTask: Task<Void, Never>?

    /// The category that will actually be used on send: manual override first,
    /// otherwise the parser's prediction.
    var effectiveCategory: Category? { selectedCategory ?? parseResult?.category }

    /// Send is allowed only with a detected amount **and** a category (parsed or
    /// chosen) — mirrors "enabled only when amount + category both present".
    var canSend: Bool {
        guard !isSaving, let result = parseResult, result.amount > 0 else { return false }
        return effectiveCategory != nil
    }

    /// The date the entry will land on (today unless the text named another day).
    var resolvedDate: Date { parseResult?.date ?? Date() }

    // MARK: - Parsing (debounced)

    /// Re-parses `inputText` after a 300 ms quiet period. Cancels any in-flight
    /// parse so each keystroke doesn't spin up redundant work.
    func scheduleParse(categories: [Category], predictor: CategoryPredictor) {
        parseTask?.cancel()

        let text = inputText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            parseResult = nil
            return
        }

        parseTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            self.parseResult = self.parser.parse(text, availableCategories: categories, predictor: predictor)
        }
    }

    // MARK: - Save

    /// Creates and persists the transaction, then resets for the next entry.
    /// Returns the created transaction (caller may animate to it). The
    /// `.ankaDataDidChange` post refreshes the dashboard + widgets centrally (X2).
    @discardableResult
    func save(context: ModelContext) -> Transaction? {
        guard canSend, let result = parseResult else { return nil }
        isSaving = true
        defer { isSaving = false }

        let tx = Transaction(
            amount: result.amount,
            type: .expense,
            date: result.date,
            note: result.note,
            category: effectiveCategory,
            currencyCode: AppCurrency.code
        )
        context.insert(tx)
        do {
            try context.save()
        } catch {
            context.delete(tx)
            return nil
        }
        NotificationCenter.default.post(name: .ankaDataDidChange, object: nil)

        reset()
        return tx
    }

    /// Clears state so the composer is ready for the next entry.
    func reset() {
        parseTask?.cancel()
        inputText = ""
        parseResult = nil
        selectedCategory = nil
    }
}
