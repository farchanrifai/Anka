import SwiftUI

/// Drives Anka's automatic backups from the Today screen — the one place that
/// already holds the full `@Query` of transactions + categories and observes
/// every change to them.
///
/// Two triggers (see AUDIT.md D2):
///   • App foreground (`scenePhase == .active`) → backup if >24h since last.
///   • Transaction set changes (save / delete / import / restore re-fires the
///     `@Query`) → throttled snapshot.
///
/// Applied to `TodayView` so the auto-backup behavior is centralized.
struct AutoBackupModifier: ViewModifier {
    let transactions: [Transaction]
    let categories: [Category]

    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                AutoBackupService.shared.backupOnForegroundIfNeeded(
                    transactions: transactions, categories: categories
                )
            }
            .onChange(of: transactions) {
                AutoBackupService.shared.backupAfterChange(
                    transactions: transactions, categories: categories
                )
            }
    }
}

extension View {
    /// Schedules automatic backups off the Today screen's transaction query.
    func autoBackup(transactions: [Transaction], categories: [Category]) -> some View {
        modifier(AutoBackupModifier(transactions: transactions, categories: categories))
    }
}
