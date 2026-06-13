import Foundation
import SwiftData

struct CSVService {

    // MARK: - Export

    static func export(_ transactions: [Transaction]) -> String {
        var rows = ["date,type,category,amount,note,tags,currency,paymentMethod"]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]

        for tx in transactions.sorted(by: { $0.date > $1.date }) {
            let tagStr = tx.tags.joined(separator: "|")
            rows.append([
                formatter.string(from: tx.date),
                tx.type.rawValue,
                escape(tx.category?.name ?? ""),
                String(tx.amount),
                escape(tx.note ?? ""),
                escape(tagStr),
                tx.currencyCode,
                escape(tx.paymentMethod ?? "")
            ].joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    // MARK: - Parse (no DB writes)

    struct ParsedTransaction: Identifiable {
        let id = UUID()
        let date: Date
        let type: TransactionType
        let amount: Double
        let categoryName: String?
        let matchedCategory: Category?
        let note: String?
        let tagNames: [String]
        let currencyCode: String?
        let paymentMethod: String?
        /// True when an existing transaction already matches this row
        /// (same day + amount + type + note). Set during preview (AUDIT.md D9).
        var isDuplicate: Bool = false
    }

    struct PreviewResult {
        var transactions: [ParsedTransaction]
        var parseErrors: [(row: Int, message: String)]

        /// How many parsed rows look like duplicates of existing data.
        var duplicateCount: Int { transactions.lazy.filter(\.isDuplicate).count }
    }

    static func parsePreview(
        from url: URL,
        availableCategories: [Category],
        existingTransactions: [Transaction] = []
    ) throws -> PreviewResult {
        let raw = try String(contentsOf: url, encoding: .utf8)
        let rows = parseCSV(raw)

        // Need at least a header + one data row.
        guard rows.count > 1 else { throw CSVError.emptyFile }

        let headers = rows[0].map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        guard let col = ColumnMap(headers: headers) else {
            throw CSVError.missingRequiredColumns
        }

        // Signatures of existing data, for duplicate detection.
        let existingSignatures = Set(existingTransactions.map {
            signature(date: $0.date, amount: $0.amount, type: $0.type, note: $0.note)
        })

        var transactions: [ParsedTransaction] = []
        var errors: [(row: Int, message: String)] = []

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withFullDate]
        let fallbackFormatter = DateFormatter()

        for (index, fields) in rows.dropFirst().enumerated() {
            // Skip blank rows (e.g. a trailing newline produced an empty row).
            if fields.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { continue }
            do {
                var tx = try parseParsedRow(
                    fields: fields,
                    col: col,
                    isoFormatter: isoFormatter,
                    fallbackFormatter: fallbackFormatter,
                    availableCategories: availableCategories
                )
                tx.isDuplicate = existingSignatures.contains(
                    signature(date: tx.date, amount: tx.amount, type: tx.type, note: tx.note)
                )
                transactions.append(tx)
            } catch {
                errors.append((row: index + 2, message: error.localizedDescription))
            }
        }

        return PreviewResult(transactions: transactions, parseErrors: errors)
    }

    /// Stable key for "is this the same transaction" — day-granular date so a
    /// re-export (which drops the time component) still matches the original.
    private static func signature(date: Date, amount: Double, type: TransactionType, note: String?) -> String {
        let day = Calendar.current.startOfDay(for: date).timeIntervalSince1970
        let n = note?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return "\(day)|\(amount)|\(type.rawValue)|\(n)"
    }

    // MARK: - Commit (writes to DB)

    struct ImportResult {
        var imported: Int
        var skipped: Int
        var errors: [String]
    }

    static func commit(
        _ parsed: [ParsedTransaction],
        skippedErrors: [(row: Int, message: String)] = [],
        into context: ModelContext,
        resolvingCategoriesFrom categories: [Category]? = nil
    ) throws -> ImportResult {
        for p in parsed {
            // Re-match by name against the available categories
            let resolvedCategory: Category?
            if let cats = categories {
                resolvedCategory = cats.first { $0.name.lowercased() == p.categoryName?.lowercased() }
            } else {
                resolvedCategory = p.matchedCategory
            }

            let tx = Transaction(
                amount: p.amount,
                type: p.type,
                date: p.date,
                note: p.note,
                category: resolvedCategory,
                currencyCode: p.currencyCode ?? "USD",
                tags: p.tagNames,
                paymentMethod: p.paymentMethod
            )
            context.insert(tx)
        }
        try context.save()
        return ImportResult(
            imported: parsed.count,
            skipped: skippedErrors.count,
            errors: skippedErrors.map { "Row \($0.row): \($0.message)" }
        )
    }

    // MARK: - Helpers

    private static func parseParsedRow(
        fields: [String],
        col: ColumnMap,
        isoFormatter: ISO8601DateFormatter,
        fallbackFormatter: DateFormatter,
        availableCategories: [Category]
    ) throws -> ParsedTransaction {
        guard fields.count > max(col.date, col.amount) else {
            throw CSVError.malformedRow
        }

        // Date
        let dateStr = fields[col.date].trimmingCharacters(in: .whitespaces)
        var date = isoFormatter.date(from: dateStr)
        if date == nil {
            fallbackFormatter.dateFormat = "yyyy-MM-dd"
            date = fallbackFormatter.date(from: dateStr)
        }
        if date == nil {
            fallbackFormatter.dateFormat = nil
            fallbackFormatter.dateStyle = .short
            date = fallbackFormatter.date(from: dateStr)
        }
        guard let parsedDate = date else { throw CSVError.invalidDate(dateStr) }

        // Amount
        let rawAmount = fields[col.amount].trimmingCharacters(in: .whitespaces)
        let amountStr = rawAmount.filter { $0.isNumber || $0 == "." }
        guard let amount = Double(amountStr), amount > 0 else {
            throw CSVError.invalidAmount(rawAmount)
        }

        // Type
        let typeStr: String
        if let idx = col.type, idx < fields.count {
            typeStr = fields[idx].trimmingCharacters(in: .whitespaces).lowercased()
        } else {
            typeStr = "expense"
        }
        guard let txType = TransactionType(rawValue: typeStr) else {
            throw CSVError.invalidType(typeStr)
        }

        // Category
        let categoryName: String?
        if let idx = col.category, idx < fields.count {
            let name = fields[idx].trimmingCharacters(in: .whitespaces)
            categoryName = name.isEmpty ? nil : name
        } else {
            categoryName = nil
        }
        let matchedCategory = availableCategories.first {
            $0.name.lowercased() == categoryName?.lowercased()
        }

        // Note
        let note: String?
        if let idx = col.note, idx < fields.count {
            let n = fields[idx].trimmingCharacters(in: .whitespaces)
            note = n.isEmpty ? nil : n
        } else {
            note = nil
        }

        // Tags (pipe-separated, optional column)
        let tagNames: [String]
        if let idx = col.tags, idx < fields.count {
            let raw = fields[idx].trimmingCharacters(in: .whitespaces)
            tagNames = raw.isEmpty ? [] : raw.components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        } else {
            tagNames = []
        }

        // Currency (optional column)
        let currencyCode: String?
        if let idx = col.currency, idx < fields.count {
            let c = fields[idx].trimmingCharacters(in: .whitespaces)
            currencyCode = c.isEmpty ? nil : c
        } else {
            currencyCode = nil
        }

        // Payment method (optional column)
        let paymentMethod: String?
        if let idx = col.paymentMethod, idx < fields.count {
            let pm = fields[idx].trimmingCharacters(in: .whitespaces)
            paymentMethod = pm.isEmpty ? nil : pm
        } else {
            paymentMethod = nil
        }

        return ParsedTransaction(
            date: parsedDate,
            type: txType,
            amount: amount,
            categoryName: categoryName,
            matchedCategory: matchedCategory,
            note: note,
            tagNames: tagNames,
            currencyCode: currencyCode,
            paymentMethod: paymentMethod
        )
    }

    private static func escape(_ s: String) -> String {
        guard s.contains(",") || s.contains("\"") || s.contains("\n") else { return s }
        return "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    /// Full-file RFC-4180-ish CSV tokenizer. Handles quoted fields containing
    /// commas and newlines, and unescapes doubled quotes (`""` → `"`). The old
    /// implementation split the file on newlines first and didn't unescape, so
    /// a note like `He said "hi"` or one containing a comma + newline was
    /// corrupted on round-trip (AUDIT.md D7).
    static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false

        let chars = Array(text)
        var i = 0

        func endField() { row.append(field); field = "" }
        func endRow()   { endField(); rows.append(row); row = [] }

        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" {
                        field.append("\"")   // escaped quote
                        i += 2
                    } else {
                        inQuotes = false     // closing quote
                        i += 1
                    }
                } else {
                    field.append(c)
                    i += 1
                }
            } else {
                // Note: Swift fuses "\r\n" into ONE Character grapheme, so a
                // CRLF terminator is matched by `isNewline` in a single step —
                // no lookahead needed (and `case "\r"` would never fire).
                if c == "\"" {
                    inQuotes = true
                    i += 1
                } else if c == "," {
                    endField()
                    i += 1
                } else if c.isNewline {
                    endRow()
                    i += 1
                } else {
                    field.append(c)
                    i += 1
                }
            }
        }
        // Flush the last field/row when the file doesn't end in a newline.
        if !field.isEmpty || !row.isEmpty {
            endRow()
        }
        return rows
    }
}

private struct ColumnMap {
    let date: Int
    let amount: Int
    let type: Int?
    let category: Int?
    let note: Int?
    let tags: Int?
    let currency: Int?
    let paymentMethod: Int?

    init?(headers: [String]) {
        guard let d = headers.firstIndex(where: { $0.contains("date") }),
              let a = headers.firstIndex(where: { $0.contains("amount") || $0.contains("total") })
        else { return nil }
        date          = d
        amount        = a
        type          = headers.firstIndex(where: { $0.contains("type") })
        category      = headers.firstIndex(where: { $0.contains("category") || $0.contains("cat") })
        note          = headers.firstIndex(where: { $0.contains("note") || $0.contains("desc") || $0.contains("memo") })
        tags          = headers.firstIndex(where: { $0.contains("tag") })
        currency      = headers.firstIndex(where: { $0.contains("currency") || $0.contains("curr") })
        paymentMethod = headers.firstIndex(where: { $0.contains("payment") || $0.contains("method") })
    }
}

enum CSVError: LocalizedError {
    case emptyFile
    case missingRequiredColumns
    case malformedRow
    case invalidDate(String)
    case invalidAmount(String)
    case invalidType(String)

    var errorDescription: String? {
        switch self {
        case .emptyFile:              return "The file is empty."
        case .missingRequiredColumns: return "CSV must have the required columns."
        case .malformedRow:           return "Row has too few columns."
        case .invalidDate(let s):     return "Can't parse date: \"\(s)\""
        case .invalidAmount(let s):   return "Can't parse amount: \"\(s)\""
        case .invalidType(let s):     return "Unknown type: \"\(s)\" — expected 'expense' or 'income'"
        }
    }
}
