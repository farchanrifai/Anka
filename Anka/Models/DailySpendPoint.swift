import Foundation

/// One day's total for the Main Page V2 line chart. `total` follows the
/// active `BalanceMode` (Total mode nets income − expense, matching
/// `TodayViewModel.heroAmount`).
struct DailySpendPoint: Identifiable, Sendable, Equatable {
    let date: Date
    let total: Double
    var id: Date { date }
}
