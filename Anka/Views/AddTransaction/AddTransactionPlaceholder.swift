import SwiftUI

struct AddTransactionPlaceholder: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            Text("Add Transaction")
                .font(.dsHeadline)
                .foregroundStyle(DSColor.textPrimary)
            Text("Coming in Phase 2")
                .font(.dsCaption)
                .foregroundStyle(DSColor.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DSColor.bgPrimary)
    }
}
