import SwiftUI

/// Compact, capsule-shaped slot shown in the category + date + Save row.
/// Displays the selected category (emoji + name) or a placeholder, and calls
/// `onTap` so the parent can present the picker sheet.
struct CategorySlotView: View {
    let category: Category?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DSSpacing.sm) {
                if let category {
                    Text(category.emoji)
                        .font(.dsBody)
                    Text(category.name)
                        .font(.dsBody)
                        .foregroundStyle(DSColor.textPrimary)
                        .lineLimit(1)
                } else {
                    Image(systemName: "square.grid.2x2")
                        .font(.dsCaption)
                        .foregroundStyle(DSColor.textMuted)
                    Text("Category")
                        .font(.dsBody)
                        .foregroundStyle(DSColor.textMuted)
                }
            }
            .padding(.horizontal, DSSpacing.md)
            .frame(height: 48)
            .background(DSColor.bgCard, in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(DSColor.textPrimary)
    }
}
