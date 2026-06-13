import Testing
import Foundation
@testable import Anka

/// Locale-aware amount parsing (AUDIT.md D6). The decimal-pad keyboard shows
/// the *locale's* decimal separator, so the same keystrokes mean different
/// numbers on en-US vs id-ID. The bug was treating every "," as a thousands
/// separator, which turned an Indonesian user's "1,5" into 15.
struct AmountParsingTests {

    private let enUS = Locale(identifier: "en_US")
    private let idID = Locale(identifier: "id_ID")

    // MARK: - Indonesian locale (decimal ",", grouping ".")

    @Test func indonesianDecimalComma() {
        // "1,5" is one-and-a-half, NOT fifteen.
        #expect(AddTransactionViewModel.parseAmount("1,5", locale: idID) == 1.5)
    }

    @Test func indonesianGroupingDot() {
        // "1.500" is 1500 (dot = thousands separator on id-ID).
        #expect(AddTransactionViewModel.parseAmount("1.500", locale: idID) == 1500)
    }

    @Test func indonesianGroupingAndDecimal() {
        #expect(AddTransactionViewModel.parseAmount("1.500,50", locale: idID) == 1500.5)
        #expect(AddTransactionViewModel.parseAmount("2.000.000", locale: idID) == 2_000_000)
    }

    // MARK: - US locale (decimal ".", grouping ",")

    @Test func usDecimalDot() {
        #expect(AddTransactionViewModel.parseAmount("1.5", locale: enUS) == 1.5)
    }

    @Test func usGroupingComma() {
        #expect(AddTransactionViewModel.parseAmount("1,500", locale: enUS) == 1500)
        #expect(AddTransactionViewModel.parseAmount("1,234,567", locale: enUS) == 1_234_567)
    }

    // MARK: - Shared edge cases

    @Test func plainInteger() {
        #expect(AddTransactionViewModel.parseAmount("50000", locale: idID) == 50000)
        #expect(AddTransactionViewModel.parseAmount("50000", locale: enUS) == 50000)
    }

    @Test func emptyOrJunk() {
        #expect(AddTransactionViewModel.parseAmount("", locale: idID) == 0)
        #expect(AddTransactionViewModel.parseAmount("   ", locale: enUS) == 0)
        #expect(AddTransactionViewModel.parseAmount("abc", locale: idID) == 0)
    }
}
