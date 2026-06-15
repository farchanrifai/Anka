import SwiftUI

/// A pinned day-section header: the day label on the left and (when non-zero)
/// the day's signed total on the right, both in subtle Liquid Glass capsules
/// so the sticky chips now belong to the same shell vocabulary as the toolbar
/// and transaction flows.
/// Pure presentation — the total/sign are computed by
/// `TodayViewModel.dailyTotal(for:)`. Shared by the Today view variants.
struct DayHeaderView: View {
    let label: String
    let total: Double
    let sign: String

    var body: some View {
        HStack {
            Text(label)
                .font(.dsFootnoteMedium)
                .foregroundStyle(.primary)
                .frame(height: 28)
                .padding(.horizontal, DSSpacing.md)
                .glassEffect(.regular, in: .capsule)

            Spacer()

            if total > 0 {
                Text("\(sign)\(total.rupiah)")
                    .font(.dsFootnoteMedium)
                    .foregroundStyle(.primary)
                    .frame(height: 28)
                    .padding(.horizontal, DSSpacing.md)
                    .glassEffect(.regular, in: .capsule)
            }
        }
        .padding(.horizontal, DSSpacing.screenEdge)
        .padding(.vertical, DSSpacing.sm)
    }
}
