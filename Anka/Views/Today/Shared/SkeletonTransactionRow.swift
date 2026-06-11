import SwiftUI

/// Cold-start placeholder row shown while the first `refreshDashboard()` runs.
/// Shared by the Today view variants so the skeleton stays identical.
struct SkeletonTransactionRow: View {
    var body: some View {
        HStack(spacing: DSSpacing.md) {
            Circle()
                .fill(DSColor.bgSecondary)
                .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: DSRadius.small)
                    .fill(DSColor.bgSecondary)
                    .frame(width: 80, height: 10)
                RoundedRectangle(cornerRadius: DSRadius.small)
                    .fill(DSColor.bgSecondary)
                    .frame(width: 120, height: 12)
            }

            Spacer()

            RoundedRectangle(cornerRadius: DSRadius.medium)
                .fill(DSColor.bgSecondary)
                .frame(width: 64, height: 28)
        }
        .padding(.horizontal, DSSpacing.screenEdge)
        .frame(height: 68)
        .redacted(reason: .placeholder)
    }
}
