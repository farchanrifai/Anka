import Foundation

/// Result of parsing a natural-language amount+note phrase such as
/// "5 dollar for grabfood" → amount 5, currency "USD", note "grabfood".
struct ParsedTransaction: Equatable {
    let amount: Double?
    let currencyCode: String?
    let note: String
    /// 0.0–1.0 — how confident the amount/currency extraction was.
    let confidence: Double
}

/// Lightweight natural-language parser for the Add-Transaction description
/// field. Pure, stateless logic (no SwiftData, no UI, no actor) — safe to call
/// from anywhere and trivial to unit-test.
///
/// Recognises an amount (anywhere in the string) plus an optional currency
/// word/code, strips them out, and returns the descriptive remainder as the
/// note. Examples:
///   "5 dollar for grabfood" → (5,       "USD", "grabfood",       0.9)
///   "100 eur hotel in paris"→ (100,     "EUR", "hotel in paris", 0.9)
///   "5k transport"          → (5000,    "IDR", "transport",      0.7)
///   "2.5m rent"             → (2500000, "IDR", "rent",           0.7)
///   "150rb groceries"       → (150000,  "IDR", "groceries",      0.7)  // ribu
///   "2jt kos"               → (2000000, "IDR", "kos",            0.7)  // juta
///   "5.50 coffee"           → (5.5,     nil,   "coffee",         0.6)
///   "just coffee"           → (nil,     nil,   "just coffee",    0.0)
final class TransactionParser: Sendable {
    static let shared = TransactionParser()
    init() {}

    // MARK: - Confidence tiers
    private static let confExplicitCurrency = 0.9   // amount + a named currency
    private static let confShorthand        = 0.7   // "5k"/"5m"/"5b" magnitude → IDR
    private static let confAmountOnly       = 0.6   // bare number, currency assumed
    private static let confNone             = 0.0   // no amount found

    /// Currency words/codes → ISO code, matched on word boundaries and
    /// case-insensitively. Deliberately conservative: only unambiguous tokens
    /// (no bare "us"/"singapore"/"australian") so we never eat note words.
    private static let currencyMap: [(token: String, code: String)] = [
        ("usd", "USD"), ("dollar", "USD"), ("dollars", "USD"),
        ("eur", "EUR"), ("euro", "EUR"),   ("euros", "EUR"),
        ("gbp", "GBP"), ("pound", "GBP"),  ("pounds", "GBP"),
        ("jpy", "JPY"), ("yen", "JPY"),
        ("idr", "IDR"), ("rupiah", "IDR"), ("rp", "IDR"),
        ("sgd", "SGD"),
        ("aud", "AUD"),
        ("cad", "CAD"),
    ]

    /// Number (int/decimal, optional thousands commas) + an optional adjacent
    /// magnitude suffix (case-insensitive). Supports English `k`/`m`/`b` and
    /// Indonesian `rb`/`ribu` (thousand), `jt`/`juta` (million), and
    /// `miliar`/`milyar` (billion). The trailing `(?![a-z])` lookahead means
    /// the suffix only counts when it ends the token — so "5k"/"5jt" parse,
    /// but the letters in "5km"/"5min" stay as note text. Longer alternatives
    /// are listed first so a shorter prefix can't shadow them.
    /// Group 1 = the number, group 2 = the suffix (if present).
    private static let numberRegex = try! NSRegularExpression(
        pattern: #"(\d+(?:[.,]\d+)?)((?:juta|jt|ribu|rb|miliar|milyar|k|m|b)(?![a-z]))?"#,
        options: [.caseInsensitive]
    )

    // MARK: - Public

    func parse(_ input: String) -> ParsedTransaction {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ParsedTransaction(amount: nil, currencyCode: nil, note: trimmed, confidence: Self.confNone)
        }

        let (amount, currency, confidence) = extractAmount(from: trimmed)
        let note = cleanedNote(from: trimmed)
        return ParsedTransaction(amount: amount, currencyCode: currency, note: note, confidence: confidence)
    }

    // MARK: - Amount + currency

    private func extractAmount(from text: String) -> (Double?, String?, Double) {
        guard let (number, multiplier) = firstNumber(in: text) else {
            return (nil, nil, Self.confNone)
        }
        let amount = number * multiplier

        // An explicit currency word wins (and still honours the k/m/b multiplier).
        if let code = detectCurrency(in: text) {
            return (amount, code, Self.confExplicitCurrency)
        }
        // A magnitude suffix ("5k", "5m", "5b") with no named currency → IDR shorthand.
        if multiplier > 1 {
            return (amount, AppCurrency.code, Self.confShorthand)
        }
        // Bare number — currency left to the caller's default.
        return (amount, nil, Self.confAmountOnly)
    }

    /// The first number in the text + its magnitude multiplier from an adjacent
    /// `k`/`m`/`b` suffix (×1,000 / ×1,000,000 / ×1,000,000,000; 1 when absent).
    private func firstNumber(in text: String) -> (value: Double, multiplier: Double)? {
        guard let match = Self.numberRegex.firstMatch(
            in: text, range: NSRange(text.startIndex..., in: text)
        ), let numberRange = Range(match.range(at: 1), in: text) else { return nil }

        // Interpret separators by the device locale instead of assuming
        // comma=thousands / dot=decimal. On id-ID "1.500" is 1500 and "1,5"
        // is 1.5; on en-US it's the reverse (AUDIT.md D6).
        let grouping = Locale.current.groupingSeparator ?? ","
        let decimal  = Locale.current.decimalSeparator ?? "."
        var raw = String(text[numberRange]).replacingOccurrences(of: grouping, with: "")
        if decimal != "." {
            raw = raw.replacingOccurrences(of: decimal, with: ".")
        }
        guard let value = Double(raw) else { return nil }

        var multiplier = 1.0
        if let suffixRange = Range(match.range(at: 2), in: text) {
            switch String(text[suffixRange]).lowercased() {
            case "k", "rb", "ribu":       multiplier = 1_000            // thousand / ribu
            case "m", "jt", "juta":       multiplier = 1_000_000        // million / juta
            case "b", "miliar", "milyar": multiplier = 1_000_000_000    // billion / miliar
            default:                      break
            }
        }
        return (value, multiplier)
    }

    private func detectCurrency(in text: String) -> String? {
        let lower = text.lowercased()
        for (token, code) in Self.currencyMap where Self.wholeWord(token, existsIn: lower) {
            return code
        }
        return nil
    }

    // MARK: - Note cleaning

    private func cleanedNote(from text: String) -> String {
        var result = text

        // 1. Strip the first number token (with its optional k/m/b suffix).
        if let match = Self.numberRegex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
           let range = Range(match.range, in: result) {
            result.removeSubrange(range)
        }

        // 2. Strip currency words/codes (word-boundary, case-insensitive).
        for (token, _) in Self.currencyMap {
            result = result.replacingOccurrences(
                of: "\\b\(token)\\b", with: "", options: [.regularExpression, .caseInsensitive]
            )
        }

        // 3. Strip leftover joiner words "for" / "at" / "on".
        result = result.replacingOccurrences(
            of: "\\b(for|at|on)\\b", with: "", options: [.regularExpression, .caseInsensitive]
        )

        // 4. Collapse whitespace + trim.
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func wholeWord(_ word: String, existsIn lowercasedText: String) -> Bool {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        return regex.firstMatch(in: lowercasedText, range: NSRange(lowercasedText.startIndex..., in: lowercasedText)) != nil
    }
}
