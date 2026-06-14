import Testing
@testable import Anka

/// Phase 3b: multi-currency architecture seam.
struct CurrencyInfoTests {

    @Test func converterIsIdentity() {
        #expect(CurrencyConverter.convert(100, from: "USD", to: "USD") == 100)
        #expect(CurrencyConverter.convert(100, from: "USD", to: "IDR") == 100)
    }

    @Test func infoLookupReturnsCuratedEntries() {
        let usd = CurrencyInfo.info(for: "USD")
        #expect(usd.symbol == "$")
        #expect(usd.decimalDigits == 2)
        #expect(usd.symbolLeading)

        let idr = CurrencyInfo.info(for: "IDR")
        #expect(idr.symbol == "Rp")
        #expect(idr.decimalDigits == 0)
    }

    @Test func infoLookupFallsBackForUnknownCode() {
        let unknown = CurrencyInfo.info(for: "ZZZ")
        #expect(unknown.symbol == "ZZZ")
        #expect(unknown.decimalDigits == 2)
    }
}
