import SwiftUI

/// App root. Today is the only screen; Stats is reached via the "Stats →"
/// button in the Today hero and pushed onto Today's own NavigationStack.
/// The Add action lives in Today's bottom toolbar (iOS Mail-style), so we
/// no longer need a TabView with a detached `.search`-role Add tab.
struct AppRouter: View {
    var body: some View {
        TodayView()
    }
}
