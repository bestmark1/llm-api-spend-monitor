import XCTest
@testable import LLMSpendMonitor

final class SnapshotCacheTests: XCTestCase {
    func testSaveAndLoadRoundTripPreservesNormalizedSnapshots() async throws {
        let fileURL = try makeCacheURL()
        let cache = SnapshotCache(fileURL: fileURL)
        let snapshot = try makeSnapshot(providerID: .openAI, amount: "1.234567890123456789")

        try await cache.save([snapshot.providerID: snapshot])
        let loaded = try await cache.load()

        XCTAssertEqual(loaded, [snapshot.providerID: snapshot])
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        XCTAssertEqual(attributes[.posixPermissions] as? NSNumber, NSNumber(value: 0o600))
    }

    func testRemovePurgesOnlySelectedProvider() async throws {
        let fileURL = try makeCacheURL()
        let cache = SnapshotCache(fileURL: fileURL)
        let openAI = try makeSnapshot(providerID: .openAI, amount: "1.00")
        let anthropic = try makeSnapshot(providerID: .anthropic, amount: "2.00")
        try await cache.save([.openAI: openAI, .anthropic: anthropic])

        try await cache.remove(.openAI)

        let loaded = try await cache.load()
        XCTAssertEqual(loaded, [.anthropic: anthropic])
    }

    func testFailedAtomicWritePreservesPreviousCache() async throws {
        let fileURL = try makeCacheURL()
        let workingCache = SnapshotCache(fileURL: fileURL)
        let initial = try makeSnapshot(providerID: .openAI, amount: "1.00")
        try await workingCache.save([.openAI: initial])

        let failingCache = SnapshotCache(fileURL: fileURL, writer: FailingSnapshotWriter())
        let replacement = try makeSnapshot(providerID: .openAI, amount: "9.00")

        await XCTAssertThrowsErrorAsync {
            try await failingCache.save([.openAI: replacement])
        }
        let loaded = try await workingCache.load()
        XCTAssertEqual(loaded, [.openAI: initial])
    }

    private func makeCacheURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LLMSpendMonitorTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("snapshots.json")
    }

    private func makeSnapshot(providerID: ProviderID, amount: String) throws -> ProviderSnapshot {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(86_400)
        let metric = MoneyMetric(
            value: try Money(amount: Decimal(string: amount)!, currencyCode: "USD"),
            provenance: .official
        )
        return try ProviderSnapshot(
            providerID: providerID,
            capabilities: [.officialCostHistory],
            fetchedAt: end,
            coverage: ReportingCoverage(start: start, through: end, completeness: .complete),
            buckets: [PeriodBucket(start: start, end: end, cost: metric)],
            balances: [],
            issue: nil
        )
    }
}

private struct FailingSnapshotWriter: SnapshotFileWriting {
    struct Failure: Error {}

    func write(_ data: Data, to fileURL: URL) throws {
        throw Failure()
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {}
}
