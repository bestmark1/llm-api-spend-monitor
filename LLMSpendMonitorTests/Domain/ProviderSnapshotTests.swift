import XCTest
@testable import LLMSpendMonitor

final class ProviderSnapshotTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_784_102_400)
    private let end = Date(timeIntervalSince1970: 1_784_188_800)

    func testFullProviderSnapshotPreservesExactOfficialMetrics() throws {
        let cost = MoneyMetric(
            value: try Money(amount: Decimal(string: "1.23456789000000000000000000000")!, currencyCode: "USD"),
            provenance: .official
        )
        let usage = TokenUsage(
            inputTokens: 123_456,
            outputTokens: 7_890,
            cachedInputTokens: 12_345,
            provenance: .official
        )
        let bucket = PeriodBucket(
            start: start,
            end: end,
            cost: cost,
            tokenUsage: usage,
            modelBreakdown: [ModelUsage(modelID: "model-a", cost: nil, tokenUsage: usage)]
        )

        let snapshot = try ProviderSnapshot(
            providerID: .openAI,
            capabilities: [.officialCostHistory, .tokenUsage, .modelBreakdown],
            fetchedAt: end,
            coverage: ReportingCoverage(start: start, through: end, completeness: .complete),
            buckets: [bucket],
            balances: [],
            issue: nil
        )

        let encoded = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(ProviderSnapshot.self, from: encoded)

        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.buckets.first?.cost?.value.amount, cost.value.amount)
    }

    func testSnapshotRejectsMetricsMissingFromCapabilities() throws {
        let cost = MoneyMetric(
            value: try Money(amount: 1, currencyCode: "USD"),
            provenance: .official
        )

        XCTAssertThrowsError(
            try ProviderSnapshot(
                providerID: .deepSeek,
                capabilities: [.balance],
                fetchedAt: end,
                coverage: ReportingCoverage(start: start, through: end, completeness: .complete),
                buckets: [PeriodBucket(start: start, end: end, cost: cost)],
                balances: [],
                issue: nil
            )
        ) { error in
            XCTAssertEqual(error as? ProviderSnapshot.ValidationError, .unsupportedMetric(.officialCostHistory))
        }
    }

    func testSnapshotAcceptsEstimatedProviderMoneyWithMatchingCapability() throws {
        let estimated = MoneyMetric(
            value: try Money(amount: 1, currencyCode: "USD"),
            provenance: .estimated
        )

        let snapshot = try ProviderSnapshot(
            providerID: .deepSeek,
            capabilities: [.balance, .estimatedCostHistory],
            fetchedAt: end,
            coverage: ReportingCoverage(start: start, through: end, completeness: .complete),
            buckets: [PeriodBucket(start: start, end: end, cost: estimated)],
            balances: [],
            issue: nil
        )

        XCTAssertEqual(snapshot.buckets.first?.cost, estimated)
    }

    func testSnapshotRejectsEstimatedProviderMoneyWithoutMatchingCapability() throws {
        let estimated = MoneyMetric(
            value: try Money(amount: 1, currencyCode: "USD"),
            provenance: .estimated
        )

        XCTAssertThrowsError(
            try ProviderSnapshot(
                providerID: .deepSeek,
                capabilities: [.balance],
                fetchedAt: end,
                coverage: ReportingCoverage(start: start, through: end, completeness: .complete),
                buckets: [PeriodBucket(start: start, end: end, cost: estimated)],
                balances: [],
                issue: nil
            )
        ) { error in
            XCTAssertEqual(error as? ProviderSnapshot.ValidationError, .unsupportedMetric(.estimatedCostHistory))
        }
    }

    func testBalanceOnlySnapshotSupportsMultipleCurrencies() throws {
        let balances = [
            ProviderBalance(
                total: MoneyMetric(value: try Money(amount: 7, currencyCode: "USD"), provenance: .official),
                granted: MoneyMetric(value: try Money(amount: 0, currencyCode: "USD"), provenance: .official),
                toppedUp: MoneyMetric(value: try Money(amount: 7, currencyCode: "USD"), provenance: .official)
            ),
            ProviderBalance(
                total: MoneyMetric(value: try Money(amount: 10, currencyCode: "CNY"), provenance: .official),
                granted: nil,
                toppedUp: nil
            )
        ]

        let snapshot = try ProviderSnapshot(
            providerID: .deepSeek,
            capabilities: [.balance],
            fetchedAt: end,
            coverage: nil,
            buckets: [],
            balances: balances,
            issue: nil
        )

        XCTAssertEqual(snapshot.balances.map(\.total.value.currencyCode), ["USD", "CNY"])
    }
}
