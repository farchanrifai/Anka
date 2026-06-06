import Foundation

enum TransactionType: String, Codable, CaseIterable, Hashable {
    case expense = "expense"
    case income = "income"

    var displayName: String {
        switch self {
        case .expense: return "Expense"
        case .income: return "Income"
        }
    }
}
