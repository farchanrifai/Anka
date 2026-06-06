import SwiftUI

struct TodayView: View {
    var body: some View {
        Text("Today")
            .font(.dsHeadline)
            .foregroundStyle(DSColor.textPrimary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DSColor.bgGrouped)
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.large)
    }
}
