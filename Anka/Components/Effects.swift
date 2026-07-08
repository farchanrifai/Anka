import SwiftUI

// MARK: - Shake effect
//
// Declarative horizontal shake for invalid-save feedback. Incrementing the
// trigger inside a single `withAnimation` drives `animatableData` from its
// old value to the new one; the `sin` curve turns that into a damped left-
// right wobble. Replaces a hand-timed sequence of four
// `DispatchQueue.main.asyncAfter` callbacks, which was prone to timing drift.
struct ShakeEffect: GeometryEffect {
    /// Peak horizontal travel in points.
    var travel: CGFloat = 10
    /// Number of left-right oscillations per trigger.
    var shakes: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let dx = travel * sin(animatableData * .pi * shakes)
        return ProjectionTransform(CGAffineTransform(translationX: dx, y: 0))
    }
}

// MARK: - Per-character slot animation (mirrors Spendy CategorySlotView's SlotChar)
//
// Staged per-character choreography — the delays ARE the effect, so the
// spring stays hand-tuned rather than tokenized.
struct SlotCharEffect: ViewModifier {
    let revealed: Bool
    let delay: Double
    var slideAmount: CGFloat = 28

    func body(content: Content) -> some View {
        content
            .offset(y: revealed ? 0 : slideAmount)
            .opacity(revealed ? 1 : 0)
            .animation(
                .spring(response: 0.35, dampingFraction: 0.72).delay(delay),
                value: revealed
            )
    }
}

// MARK: - Per-character fade-in label inside the sparkle pill
struct SparkleCategoryLabel: View {
    let category: Category

    @State private var revealed = false

    private var charPairs: [(Int, String)] {
        Array(category.name).enumerated().map { ($0.offset + 1, String($0.element)) }
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(category.emoji)
                .font(.dsSubhead)
                .modifier(SlotCharEffect(revealed: revealed, delay: 0.02, slideAmount: 10))
            Text(" ")
                .font(.dsSubhead)
            ForEach(charPairs, id: \.0) { idx, char in
                Text(char)
                    .font(.dsSubhead)
                    .modifier(SlotCharEffect(
                        revealed: revealed,
                        delay: Double(idx) * 0.016 + 0.04,
                        slideAmount: 10
                    ))
            }
        }
        .foregroundStyle(.white)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { revealed = true }
        }
    }
}
