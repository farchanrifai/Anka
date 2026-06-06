import SwiftData
import Foundation

@Model
final class Transaction {
    @Attribute(.unique) var id: UUID
    var amount: Double
    var type: TransactionType
    var date: Date
    var createdAt: Date
    var note: String?
    var category: Category?
    var currencyCode: String          // e.g. "USD", "IDR"
    var tags: [String]                // freeform tags, optional
    var paymentMethod: String?        // e.g. "Cash", "Visa", optional

    init(
        id: UUID = UUID(),
        amount: Double,
        type: TransactionType,
        date: Date = Date(),
        createdAt: Date = Date(),
        note: String? = nil,
        category: Category? = nil,
        currencyCode: String = "USD",
        tags: [String] = [],
        paymentMethod: String? = nil
    ) {
        self.id = id
        self.amount = amount
        self.type = type
        self.date = date
        self.createdAt = createdAt
        self.note = note
        self.category = category
        self.currencyCode = currencyCode
        self.tags = tags
        self.paymentMethod = paymentMethod
    }
}
