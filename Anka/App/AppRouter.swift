import SwiftUI

@Observable
class AppState {
    var selectedTab: String = "today"
}

struct AppRouter: View {
    @State private var appState = AppState()
    @State private var previousTab: String = "today"
    @State private var showAddTransaction = false

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            
            Tab("Today", systemImage: "house", value: "today") {
                NavigationStack {
                    TodayView()
                }
            }

            // Add — detached to the right via .search role; intercepted, never navigates
            Tab("Add", systemImage: "plus", value: "add", role: .search) {
                Color.clear
            }
        }
        .tint(DSColor.accent)
        .tabBarMinimizeBehavior(.onScrollDown)
        .onChange(of: appState.selectedTab) { _, newValue in
            if newValue == "add" {
                showAddTransaction = true
                appState.selectedTab = previousTab
            } else {
                previousTab = newValue
            }
        }
        .sheet(isPresented: $showAddTransaction) {
            AddTransactionView()
        }
        .onAppear {
            previousTab = appState.selectedTab
        }
    }
}