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
    }

    struct PreviewResult {
        var transactions: [ParsedTransaction]
        var parseErrors: [(row: Int, message: String)]
    }

    static func parsePreview(
        from url: URL,
        availableCategories: [Category]
    ) throws -> PreviewResult {
        let raw = try String(contentsOf: url, encoding: .utf8)
        let lines = raw.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard lines.count > 1 else { throw CSVError.emptyFile }

        let headers = lines[0].lowercased().components(separatedBy: ",")
        guard let col = ColumnMap(headers: headers) else {
            throw CSVError.missingRequiredColumns
        }

        var transactions: [ParsedTransaction] = []
        var errors: [(row: Int, message: String)] = []

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withFullDate]
        let fallbackFormatter = DateFormatter()

        for (index, line) in lines.dropFirst().enumerated() {
            let fields = parseCSVLine(line)
            do {
                let tx = try parseParsedRow(
                    fields: fields,
                    col: col,
                    isoFormatter: isoFormatter,
                    fallbackFormatter: fallbackFormatter,
                    availableCategories: availableCategories
                )
                transactions.append(tx)
            } catch {
                errors.append((row: index + 2, message: error.localizedDescription))
            }
        }

        return PreviewResult(transactions: transactions, parseErrors: errors)
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

    static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current)
        return fields
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
