import SwiftUI

/// A single transaction row: category emoji bubble, category name + description,
/// and the signed amount capsule (`AmountLabel`). Pure display + callbacks —
/// all state and persistence live in the caller's view model.
///
/// Interaction:
///   • tapping the row → `onEdit` (opens the edit sheet)
///   • long-press context menu → Edit (`onEdit`) / Delete (`onDelete`)
///
/// `namespace` is the caller's `@Namespace`, paired with the edit sheet's
/// `.navigationTransition(.zoom(sourceID: transaction.id, in:))` so the row
/// zooms into the sheet (Mail-style).
struct TransactionRow: View {
    let transaction: Transaction
    let namespace: Namespace.ID
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onEdit) {
            HStack(spacing: DSSpacing.md) {
                let cat = transaction.category
                ZStack {
                    Circle()
                        .fill((cat.map { Color(hex: $0.colorHex) } ?? .gray).opacity(DSOpacity.subtle))
                        .frame(width: 54, height: 54)
                    Text(cat?.emoji ?? "💳")
                        .font(.dsEmoji)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(cat?.name ?? "Uncategorized")
                        .font(.dsCaption)
                        .foregroundStyle(.secondary)

                    let trimmedNote = transaction.note.flatMap { $0.isEmpty ? nil : $0 }
                    let desc = trimmedNote ?? (cat?.name ?? transaction.type.displayName)
                    Text(desc)
                        .font(.dsBodySemi)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Spacer()

                AmountLabel(amount: transaction.amount, type: transaction.type)
            }
            .padding(.horizontal, DSSpacing.screenEdge)
            .frame(minHeight: 68)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tint(.primary)
        // Mail-like zoom: tapping a row presents the edit sheet via a zoom
        // transition originating from this row. Pairs with
        // `.navigationTransition(.zoom(sourceID: transaction.id, in: namespace))`
        // applied on the edit sheet's AddTransactionView. Each row uses its
        // own transaction.id so the zoom sources from the exact row the user tapped.
        .matchedTransitionSource(id: transaction.id, in: namespace)
        // `.swipeActions` is List-only and is a no-op inside this
        // ScrollView/LazyVStack, so delete/edit live in a long-press
        // context menu instead. The tap-to-edit Button above is unchanged.
        .contextMenu {
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

#Preview {
    @Previewable @Namespace var namespace
    return TransactionRow(
        transaction: Transaction(amount: 50_000, type: .expense, note: "Coffee"),
        namespace: namespace,
        onEdit: {},
        onDelete: {}
    )
}
