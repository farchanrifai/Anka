import Foundation

/// Result of parsing a freeform inline-entry phrase such as
/// "100k grabfood yesterday" → amount 100000, category Transport, note
/// "grabfood", date = yesterday. Distinct from `ParsedTransaction` (the
/// amount-only result of `TransactionParser`) which this builds on.
struct ParsedInlineTransaction: Equatable {
    let amount: Double
    let category: Category?
    let note: String?
    let date: Date
    /// 0.5 when only an amount was found, 1.0 when a category was detected too.
    /// Drives the send button (gate at ≥ 0.7 unless the user overrides category).
    let confidence: Double
}

/// Natural-language parser for the experimental inline composer (Phase 8.5 / V3).
///
/// Composes three pieces of existing logic rather than reinventing them:
///   1. **Date** — a small relative-date scanner (today/yesterday/tomorrow/
///      "N days ago"/"N days from now"), stripped from the text first.
///   2. **Amount + note** — delegated to `TransactionParser` (locale-aware
///      decimals, IDR `k`/`m`/`rb`/`jt` shorthand, currency-word stripping).
///   3. **Category** — `CategoryPredictor.predict`, matched by name against the
///      caller's categories (expense-only). Optional — the user can override.
///
/// `parse` is `@MainActor` because `CategoryPredictor` is main-actor isolated.
struct InlineTransactionParser {
    private let amountParser = TransactionParser.shared

    /// `(\d+) days ago|from now|later` — captures the count and direction.
    private static let relativeDaysRegex = try! NSRegularExpression(
        pattern: #"(\d+)\s+days?\s+(ago|from\s+now|later)"#,
        options: [.caseInsensitive]
    )

    /// Phrase → day offset, checked longest-first so "day before yesterday"
    /// wins over "yesterday".
    private static let dateKeywords: [(phrase: String, offset: Int)] = [
        ("day before yesterday", -2),
        ("the day after tomorrow", 2),
        ("yesterday", -1),
        ("tomorrow", 1),
        ("tonight", 0),
        ("today", 0),
    ]

    @MainActor
    func parse(_ input: String,
               availableCategories: [Category],
               predictor: CategoryPredictor) -> ParsedInlineTransaction? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 1. Pull out (and strip) a relative date so it can't pollute the note.
        let (date, dateStripped) = extractDate(from: trimmed)

        // 2. Amount + cleaned note via the shared amount parser.
        let amountResult = amountParser.parse(dateStripped)
        guard let amount = amountResult.amount, amount > 0 else { return nil }
        let note = amountResult.note.isEmpty ? nil : amountResult.note

        // 3. Category prediction from the note (expense categories only).
        var category: Category?
        if let note, let prediction = predictor.predict(note: note, amount: amount) {
            category = availableCategories.first { $0.name == prediction.category && $0.type == .expense }
                ?? availableCategories.first { $0.name == prediction.category }
        }

        return ParsedInlineTransaction(
            amount: amount,
            category: category,
            note: note,
            date: date,
            confidence: category != nil ? 1.0 : 0.5
        )
    }

    // MARK: - Relative date

    /// Returns the resolved date and the input with the matched date phrase
    /// removed. Defaults to today (and the input unchanged) when nothing matches.
    func extractDate(from text: String) -> (date: Date, remainder: String) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // "N days ago / from now / later"
        let range = NSRange(text.startIndex..., in: text)
        if let match = Self.relativeDaysRegex.firstMatch(in: text, range: range),
           let full = Range(match.range, in: text),
           let numRange = Range(match.range(at: 1), in: text),
           let dirRange = Range(match.range(at: 2), in: text),
           let n = Int(text[numRange]) {
            let offset = text[dirRange].lowercased().hasPrefix("ago") ? -n : n
            var remainder = text
            remainder.removeSubrange(full)
            return (cal.date(byAdding: .day, value: offset, to: today) ?? today, cleaned(remainder))
        }

        // Keyword phrases.
        let lower = text.lowercased()
        for (phrase, offset) in Self.dateKeywords where lower.contains(phrase) {
            let remainder = text.replacingOccurrences(of: phrase, with: "", options: .caseInsensitive)
            return (cal.date(byAdding: .day, value: offset, to: today) ?? today, cleaned(remainder))
        }

        return (today, text)
    }

    private func cleaned(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
