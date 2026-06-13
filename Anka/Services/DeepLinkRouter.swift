import Foundation
import Observation

/// Routes `anka://` deep links from widgets into the app's navigation state.
/// Injected via `.environment(deepLinkRouter)` at the `AnkaApp` level and read
/// by `TodayView` to open the Add Transaction sheet.
///
/// Supported URLs (see `AnkaDeepLink` in `WidgetSharedTypes`):
///   - `anka://open`  — just opens the app (default behavior).
///   - `anka://add`   — opens the Add Transaction sheet.
@MainActor @Observable
final class DeepLinkRouter {
    /// Set to true when an `anka://add` link arrives — Today views observe
    /// this and open the Add sheet, then reset it.
    var pendingAddTransaction = false

    func handle(_ url: URL) {
        guard url.scheme == AnkaDeepLink.scheme else { return }
        switch url.host {
        case "add":
            pendingAddTransaction = true
        default:
            // "open" or unknown → just open the app (already happened).
            break
        }
    }
}
