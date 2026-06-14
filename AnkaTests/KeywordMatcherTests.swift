import Testing
@testable import Anka

/// Covers the word-boundary matching introduced for short keywords (AUDIT.md X6)
/// plus the shared amount-bucket featurizer (Batch 10).
struct KeywordMatcherTests {

    // MARK: - X6: short keywords no longer match as substrings

    @Test func shortKeywordDoesNotMatchInsideLongerWord() {
        // "repair" contains "air" (→ Home) — must NOT match now.
        #expect(KeywordMatcher.match(note: "repair")?.category != "Home")
        // "premiere" contains "mie" (→ Eating Out).
        #expect(KeywordMatcher.match(note: "premiere")?.category != "Eating Out")
        // "gigantic" contains "giant" (→ Groceries).
        #expect(KeywordMatcher.match(note: "gigantic")?.category != "Groceries")
        // "grabbing" contains "grab" (→ Taxi).
        #expect(KeywordMatcher.match(note: "grabbing")?.category != "Taxi")
    }

    // MARK: - X6: short keywords still match as whole words

    @Test func shortKeywordMatchesAsWholeWord() {
        #expect(KeywordMatcher.match(note: "air")?.category == "Home")
        #expect(KeywordMatcher.match(note: "bayar air pdam")?.category == "Home")
        #expect(KeywordMatcher.match(note: "giant")?.category == "Groceries")
        #expect(KeywordMatcher.match(note: "mie ayam")?.category == "Eating Out")
    }

    // MARK: - Brand (long) keywords still match as substrings

    @Test func longBrandKeywordStillMatchesAsSubstring() {
        #expect(KeywordMatcher.match(note: "ke indomaret beli susu")?.category == "Groceries")
        #expect(KeywordMatcher.match(note: "starbucks venti")?.category == "Coffee")
        #expect(KeywordMatcher.match(note: "netflix subscription")?.category == "Entertainment")
    }

    @Test func noKeywordReturnsNil() {
        #expect(KeywordMatcher.match(note: "qwerty zxcvb") == nil)
    }

    // MARK: - Shared amount-bucket featurizer (no predictor/trainer drift)

    @Test func amountBucketTiers() {
        // Median of recentAmounts is 100_000 — ratios drive the tier.
        let recent = [100_000.0]
        #expect(MLFeaturizer.amountBucket(5_000, relativeTo: recent) == "micro")    // 0.05x
        #expect(MLFeaturizer.amountBucket(50_000, relativeTo: recent) == "small")   // 0.5x
        #expect(MLFeaturizer.amountBucket(100_000, relativeTo: recent) == "medium") // 1.0x
        #expect(MLFeaturizer.amountBucket(250_000, relativeTo: recent) == "large")  // 2.5x
        #expect(MLFeaturizer.amountBucket(1_000_000, relativeTo: recent) == "xlarge") // 10x
    }

    @Test func amountBucketBoundariesAreHalfOpen() {
        let recent = [100_000.0]
        // Upper bounds belong to the next tier up.
        #expect(MLFeaturizer.amountBucket(25_000, relativeTo: recent) == "small")  // 0.25x
        #expect(MLFeaturizer.amountBucket(75_000, relativeTo: recent) == "medium") // 0.75x
        #expect(MLFeaturizer.amountBucket(150_000, relativeTo: recent) == "large") // 1.5x
        #expect(MLFeaturizer.amountBucket(400_000, relativeTo: recent) == "xlarge") // 4.0x
    }

    @Test func amountBucketColdStartIsMedium() {
        #expect(MLFeaturizer.amountBucket(5_000, relativeTo: []) == "medium")
        #expect(MLFeaturizer.amountBucket(5_000_000, relativeTo: []) == "medium")
    }

    @Test func featurizerInputLowercasesNoteAndAppendsBucket() {
        #expect(MLFeaturizer.input(note: "GoFood Lunch", amount: 50_000, recentAmounts: [100_000]) == "gofood lunch small")
    }
}
