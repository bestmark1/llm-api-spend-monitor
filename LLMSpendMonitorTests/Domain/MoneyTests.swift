import XCTest
@testable import LLMSpendMonitor

final class MoneyTests: XCTestCase {
    func testDashboardFormattingUsesStableEnglishCurrencyStyle() throws {
        let money = try Money(amount: Decimal(string: "1234.5")!, currencyCode: "USD")

        XCTAssertEqual(MetricFormatting.money(money), "$1,234.50")
    }

    func testDashboardFormattingRoundsEveryMoneyValueToCents() throws {
        let microSpend = try Money(amount: Decimal(string: "0.0008")!, currencyCode: "USD")
        let roundedSpend = try Money(amount: Decimal(string: "4.0868")!, currencyCode: "USD")

        XCTAssertEqual(MetricFormatting.money(microSpend), "$0.00")
        XCTAssertEqual(MetricFormatting.money(roundedSpend), "$4.09")
    }

    func testCodableRoundTripPreservesDecimalAsAString() throws {
        let money = try Money(amount: Decimal(string: "1234567890.123456789")!, currencyCode: "usd")

        let data = try JSONEncoder().encode(money)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["amount"] as? String, "1234567890.123456789")
        XCTAssertEqual(object["currencyCode"] as? String, "USD")
        XCTAssertNil(object["amount"] as? Double)
        XCTAssertEqual(try JSONDecoder().decode(Money.self, from: data), money)
    }

    func testDecoderRejectsFloatingPointAmounts() {
        let data = Data(#"{"amount":12.34,"currencyCode":"USD"}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(Money.self, from: data))
    }

    func testInitializerRejectsNonISOCurrencyCode() {
        XCTAssertThrowsError(try Money(amount: 1, currencyCode: "dollars"))
    }
}
