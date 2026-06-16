import SwiftUI

/// App root. Today is the only screen; Stats is reached via the "Stats →"
/// button in the Today hero and pushed onto Today's own NavigationStack.
/// The Add action lives in Today's bottom toolbar (iOS Mail-style), so we
/// no longer need a TabView with a detached `.search`-role Add tab.
struct AppRouter: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(AppearanceManager.self) private var appearance

    @AppStorage("useMainPageV2") private var useMainPageV2 = false

    var body: some View {
        Group {
            if useMainPageV2 {
                MainPageV2View()
            } else {
                TodayView()
            }
        }
            // AppRouter sits inside the WindowGroup's
            // `.preferredColorScheme(mode.preferredColorScheme)` modifier.
            // When mode is `.system`, that resolves to nil → window follows
            // OS → AppRouter's env `colorScheme` IS the OS scheme. Mirror
            // it into `appearance.osScheme` so sheet roots can resolve
            // `.system` mode to a concrete value without nil-doesn't-reset
            // or view-structure pop bugs. (For `.light`/`.dark` modes the
            // env reflects our explicit override — written too, but unused
            // since `effectiveScheme` short-circuits before reading
            // `osScheme`.)
            .onChange(of: scheme, initial: true) { _, newScheme in
                appearance.osScheme = newScheme
            }
    }
}

