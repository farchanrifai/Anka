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
        #expect(MLFeaturizer.amountBucket(5_000) == "micro")
        #expect(MLFeaturizer.amountBucket(50_000) == "small")
        #expect(MLFeaturizer.amountBucket(250_000) == "medium")
        #expect(MLFeaturizer.amountBucket(1_000_000) == "large")
        #expect(MLFeaturizer.amountBucket(5_000_000) == "xlarge")
    }

    @Test func amountBucketBoundariesAreHalfOpen() {
        // Upper bounds belong to the next tier up.
        #expect(MLFeaturizer.amountBucket(20_000) == "small")
        #expect(MLFeaturizer.amountBucket(100_000) == "medium")
        #expect(MLFeaturizer.amountBucket(500_000) == "large")
        #expect(MLFeaturizer.amountBucket(2_000_000) == "xlarge")
    }

    @Test func featurizerInputLowercasesNoteAndAppendsBucket() {
        #expect(MLFeaturizer.input(note: "GoFood Lunch", amount: 50_000) == "gofood lunch small")
    }
}
