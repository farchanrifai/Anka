import SwiftUI

// MARK: - Animation tokens
//
// Named curves for the app's recurring interactions so motion stays
// consistent and is tunable in one place. These replace the
// `.spring(response:dampingFraction:)` / `.snappy(duration:)` /
// `.easeInOut(duration:)` literals that previously appeared verbatim across
// the Today, Stats, and shared surfaces.
//
// Bespoke, staged animations (onboarding intro choreography, per-character
// SlotCharEffect delays) intentionally keep their hand-tuned values. The
// AddTransaction category-morph spring is tokenized as `dsMorph` below.

extension Animation {

    /// The AddTransaction category-morph spring — sparkle pill grow/shrink,
    /// category select/deselect, chip row slide. Hand-tuned, now named so all
    /// the morph surfaces share one curve.
    /// (was `.spring(response: 0.45, dampingFraction: 0.75)` ×8)
    static let dsMorph = Animation.spring(response: 0.45, dampingFraction: 0.75)

    /// Standard interactive spring — pill toggles, balance-mode switches,
    /// visibility toggles, filter chips. (was `.spring(response: 0.3, dampingFraction: 0.7)`)
    static let dsSpring = Animation.spring(response: 0.3, dampingFraction: 0.7)

    /// Softer spring for reveals / larger surfaces. (was `.spring(response: 0.35, dampingFraction: 0.85)`)
    static let dsSpringSoft = Animation.spring(response: 0.35, dampingFraction: 0.85)

    /// Snappy curve for list content changes, numeric hero rolls, and month
    /// navigation. (was `.snappy(duration: 0.3)`)
    static let dsSnappy = Animation.snappy(duration: 0.3)

    /// Faster snappy for in-place swaps such as the balance-mode swipe.
    /// (was `.snappy(duration: 0.25)`)
    static let dsSnappyFast = Animation.snappy(duration: 0.25)

    /// Short ease for subtle state changes — label fades, collapse, toggles.
    /// (was `.easeInOut(duration: 0.2)`)
    static let dsEase = Animation.easeInOut(duration: 0.2)

    /// Slightly longer ease for chart/data crossfades. (was `.easeInOut(duration: 0.25)`)
    static let dsEaseSlow = Animation.easeInOut(duration: 0.25)
}
