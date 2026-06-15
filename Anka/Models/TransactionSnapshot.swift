import Foundation

/// Immutable, `Sendable` value copy of a `Transaction`'s aggregation-relevant
/// fields. Built on the main actor, then handed to `Task.detached` so the heavy
/// dashboard/stats math runs off-main without touching the non-Sendable
/// `@Model` objects. Previously duplicated as `TxSnap` (Today) and `StatsTxSnap`
/// (Stats) — identical byte-for-byte (AUDIT.md A3).
struct TransactionSnapshot: Sendable {
    let id: UUID
    let date: Date
    let type: TransactionType
    let amount: Double
    let currencyCode: String
    let categoryID: UUID?

    init(_ tx: Transaction) {
        self.id           = tx.id
        self.date         = tx.date
        self.type         = tx.type
        self.amount       = tx.amount
        self.currencyCode = tx.currencyCode
        self.categoryID   = tx.category?.id
    }

    /// Amount converted to `targetCurrency` (1:1 stub via `CurrencyConverter`).
    nonisolated func convertedAmount(to targetCurrency: String) -> Double {
        CurrencyConverter.convert(amount, from: currencyCode, to: targetCurrency)
    }
}
