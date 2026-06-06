import SwiftUI

struct ReportsView: View {
    var body: some View {
        Text("Reports")
            .font(.dsHeadline)
            .foregroundStyle(DSColor.textPrimary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DSColor.bgGrouped)
            .navigationTitle("Reports")
            .navigationBarTitleDisplayMode(.large)
    }
}
