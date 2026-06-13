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
    // `.nullify` (not `.cascade`): deleting a category must NOT delete its
    // transactions — they survive as "Uncategorized" (tx.category == nil).
    // This matches the one-time migration in AnkaApp, which deliberately
    // unlinks transactions before deleting old default categories so a cascade
    // wouldn't wipe a user's history. See AUDIT.md D1.
    @Relationship(deleteRule: .nullify, inverse: \Transaction.category) var transactions: [Transaction] = []

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
