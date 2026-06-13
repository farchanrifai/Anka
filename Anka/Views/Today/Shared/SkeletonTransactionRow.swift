import SwiftUI

/// Cold-start placeholder row shown while the first `refreshDashboard()` runs.
/// Shared by the Today view variants so the skeleton stays identical.
struct SkeletonTransactionRow: View {
    /// Static placeholders read as a frozen UI; a slow sweep signals "loading"
    /// and matches the app's polish level (AUDIT.md AN4). Suppressed under
    /// Reduce Motion (AC5) — the redaction alone communicates the pending state.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmer = false

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
        .overlay {
            if !reduceMotion {
                shimmerOverlay
            }
        }
        .onAppear { shimmer = true }
    }

    /// A soft highlight band swept horizontally across the row via a masked
    /// gradient, repeating forever.
    private var shimmerOverlay: some View {
        GeometryReader { geo in
            let width = geo.size.width
            LinearGradient(
                colors: [.clear, DSColor.textPrimary.opacity(0.06), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: width * 0.6)
            .offset(x: shimmer ? width : -width * 0.6)
            .animation(.linear(duration: 1.3).repeatForever(autoreverses: false), value: shimmer)
        }
        .allowsHitTesting(false)
    }
}
