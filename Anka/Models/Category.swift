import SwiftData
import Foundation

@Model
final class Category {
    @Attribute(.unique) var id: UUID
    var name: String
    var emoji: String
    var colorHex: String              // e.g. "F26666"
    var type: TransactionType         // .expense or .income
    var sortOrder: Int                // for ordering in picker
    @Relationship(deleteRule: .cascade, inverse: \Transaction.category) var transactions: [Transaction] = []

    init(
        id: UUID = UUID(),
        name: String,
        emoji: String,
        colorHex: String,
        type: TransactionType,
        sortOrder: Int
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.colorHex = colorHex
        self.type = type
        self.sortOrder = sortOrder
    }
}
