import XCTest
@testable import LLMSpendMonitor

final class MoneyTests: XCTestCase {
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
