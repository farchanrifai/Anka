import Testing
@testable import Anka

/// Verifies the natural-language parsing for the Add-Transaction description
/// field. Mirrors the Phase 9+ spec test table.
struct TransactionParserTests {

    private let parser = TransactionParser.shared

    @Test func explicitDollarWithJoiner() {
        let r = parser.parse("5 dollar for grabfood")
        #expect(r.amount == 5)
        #expect(r.currencyCode == "USD")
        #expect(r.note == "grabfood")
        #expect(r.confidence == 0.9)
    }

    @Test func decimalNoCurrency() {
        let r = parser.parse("5.50 coffee")
        #expect(r.amount == 5.5)
        #expect(r.currencyCode == nil)
        #expect(r.note == "coffee")
        #expect(r.confidence == 0.6)
    }

    @Test func numberAfterNote() {
        let r = parser.parse("coffee 5")
        #expect(r.amount == 5)
        #expect(r.currencyCode == nil)
        #expect(r.note == "coffee")
        #expect(r.confidence == 0.6)
    }

    @Test func thousandsShorthand() {
        let r = parser.parse("5k transport")
        #expect(r.amount == 5000)
        #expect(r.currencyCode == "IDR")
        #expect(r.note == "transport")
        #expect(r.confidence == 0.7)
    }

    @Test func explicitEuroMultiWordNote() {
        let r = parser.parse("100 eur hotel in paris")
        #expect(r.amount == 100)
        #expect(r.currencyCode == "EUR")
        #expect(r.note == "hotel in paris")
        #expect(r.confidence == 0.9)
    }

    @Test func noAmountIsPlainNote() {
        let r = parser.parse("just coffee")
        #expect(r.amount == nil)
        #expect(r.currencyCode == nil)
        #expect(r.note == "just coffee")
        #expect(r.confidence == 0)
    }

    @Test func emptyInput() {
        let r = parser.parse("   ")
        #expect(r.amount == nil)
        #expect(r.currencyCode == nil)
        #expect(r.note == "")
        #expect(r.confidence == 0)
    }

    // MARK: - Extra coverage beyond the spec table

    @Test func uppercaseCurrencyCode() {
        let r = parser.parse("20 USD lunch")
        #expect(r.amount == 20)
        #expect(r.currencyCode == "USD")
        #expect(r.note == "lunch")
    }

    @Test func kSuffixWithExplicitCurrencyKeepsCurrency() {
        // "k" multiplies, but a named currency still wins over the IDR default.
        let r = parser.parse("5k usd savings")
        #expect(r.amount == 5000)
        #expect(r.currencyCode == "USD")
        #expect(r.note == "savings")
        #expect(r.confidence == 0.9)
    }

    @Test func currencySubstringInsideWordIsNotMatched() {
        // "card" must not match the CAD code; "paris" must not match anything.
        let r = parser.parse("100 new card")
        #expect(r.amount == 100)
        #expect(r.currencyCode == nil)
        #expect(r.note == "new card")
    }

    // MARK: - Magnitude suffixes (k / m / b)

    @Test func millionShorthand() {
        let r = parser.parse("5m rent")
        #expect(r.amount == 5_000_000)
        #expect(r.currencyCode == "IDR")
        #expect(r.note == "rent")
        #expect(r.confidence == 0.7)
    }

    @Test func decimalMillionShorthand() {
        let r = parser.parse("2.5m apartment deposit")
        #expect(r.amount == 2_500_000)
        #expect(r.currencyCode == "IDR")
        #expect(r.note == "apartment deposit")
        #expect(r.confidence == 0.7)
    }

    @Test func billionShorthand() {
        let r = parser.parse("1b acquisition")
        #expect(r.amount == 1_000_000_000)
        #expect(r.currencyCode == "IDR")
        #expect(r.note == "acquisition")
        #expect(r.confidence == 0.7)
    }

    @Test func uppercaseMagnitudeSuffix() {
        let r = parser.parse("3M bonus")
        #expect(r.amount == 3_000_000)
        #expect(r.note == "bonus")
    }

    @Test func magnitudeSuffixWithExplicitCurrency() {
        // Named currency still wins over the IDR shorthand default.
        let r = parser.parse("10m usd transfer")
        #expect(r.amount == 10_000_000)
        #expect(r.currencyCode == "USD")
        #expect(r.note == "transfer")
        #expect(r.confidence == 0.9)
    }

    // MARK: - Indonesian magnitude words (rb/ribu, jt/juta, miliar)

    @Test func ribuShorthand() {
        let r = parser.parse("150rb groceries")
        #expect(r.amount == 150_000)
        #expect(r.currencyCode == "IDR")
        #expect(r.note == "groceries")
        #expect(r.confidence == 0.7)
    }

    @Test func ribuFullWord() {
        let r = parser.parse("20ribu parkir")
        #expect(r.amount == 20_000)
        #expect(r.note == "parkir")
    }

    @Test func jutaShorthand() {
        let r = parser.parse("2jt kos")
        #expect(r.amount == 2_000_000)
        #expect(r.currencyCode == "IDR")
        #expect(r.note == "kos")
        #expect(r.confidence == 0.7)
    }

    @Test func jutaFullWord() {
        let r = parser.parse("1.5juta sewa")
        #expect(r.amount == 1_500_000)
        #expect(r.note == "sewa")
    }

    @Test func miliarWord() {
        let r = parser.parse("3miliar rumah")
        #expect(r.amount == 3_000_000_000)
        #expect(r.note == "rumah")
    }

    @Test func indonesianSuffixIsCaseInsensitive() {
        let r = parser.parse("75RB bensin")
        #expect(r.amount == 75_000)
        #expect(r.note == "bensin")
    }

    @Test func suffixLetterInsideWordIsNotAMultiplier() {
        // "5km" / "5min" must NOT multiply — the letter belongs to a word.
        let km = parser.parse("5km taxi")
        #expect(km.amount == 5)
        #expect(km.note == "km taxi")

        let mins = parser.parse("5min parking")
        #expect(mins.amount == 5)
        #expect(mins.note == "min parking")
    }
}
