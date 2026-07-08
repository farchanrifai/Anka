import SwiftUI

// MARK: - Shared surface styles (DESIGN.md §4)
//
// The two recurring content surfaces, centralized so screens stop re-rolling
// background + radius + stroke combos (the root cause of hardcoded-radius and
// opacity drift):
//
//   .dsCard()          — static content card: bgCard fill, DSRadius.large,
//                        no border, no shadow. (Highlights cards, breakdowns.)
//   .dsChip()          — capsule chip: bgCard fill + hairline separator stroke.
//                        (AddTransaction metadata/category chips.)

extension View {
    /// Standard content card surface.
    func dsCard() -> some View {
        self
            .background(DSColor.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.large))
    }

    /// Capsule chip surface with a hairline stroke. Apply after sizing/padding.
    func dsChip() -> some View {
        self
            .background(DSColor.bgCard, in: RoundedRectangle(cornerRadius: DSRadius.full))
            .overlay(RoundedRectangle(cornerRadius: DSRadius.full).stroke(Color(.separator), lineWidth: 0.5))
    }
}
