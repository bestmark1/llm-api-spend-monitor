import XCTest
@testable import LLMSpendMonitor

final class AnthropicProviderTests: XCTestCase {
    func testFetchPaginatesAndConvertsFractionalCentsExactly() async throws {
        let client = AnthropicHTTPClientQueue(responses: [
            .success(response(fixture: "cost-page")),
            .success(response(fixture: "cost-page-2")),
            .success(response(fixture: "usage-page")),
            .success(response(fixture: "usage-page-2"))
        ])
        let provider = AnthropicProvider(httpClient: client, now: { Self.interval.end })

        let snapshot = try await provider.fetch(Self.fullRequest, credential: "admin-test-token")

        XCTAssertEqual(snapshot.providerID, .anthropic)
        XCTAssertEqual(snapshot.coverage?.completeness, .complete)
        XCTAssertNil(snapshot.issue)
        XCTAssertEqual(snapshot.buckets.count, 2)
        XCTAssertEqual(snapshot.buckets[0].cost?.value.amount, Decimal(string: "1.7345"))
        XCTAssertEqual(snapshot.buckets[1].cost?.value.amount, Decimal(string: "0.25"))
        XCTAssertEqual(snapshot.buckets[0].tokenUsage?.inputTokens, 2_200)
        XCTAssertEqual(snapshot.buckets[0].tokenUsage?.outputTokens, 75)
        XCTAssertEqual(snapshot.buckets[0].tokenUsage?.cachedInputTokens, 400)
        XCTAssertEqual(snapshot.buckets[0].modelBreakdown.map(\.modelID), [
            "claude-haiku-4-5-20251001",
            "claude-sonnet-4-20250514"
        ])
        XCTAssertTrue(snapshot.buckets.flatMap(\.modelBreakdown).allSatisfy { $0.cost == nil })

        let requests = await client.requests
        XCTAssertEqual(requests.count, 4)
        XCTAssertEqual(requests[0].url.path, "/v1/organizations/cost_report")
        XCTAssertEqual(query("starting_at", in: requests[0].url), "2026-07-10T00:00:00Z")
        XCTAssertEqual(query("ending_at", in: requests[0].url), "2026-07-12T00:00:00Z")
        XCTAssertEqual(query("page", in: requests[1].url), "cost-next")
        XCTAssertEqual(requests[2].url.path, "/v1/organizations/usage_report/messages")
        XCTAssertEqual(queries("group_by[]", in: requests[2].url), ["model", "service_tier"])
        XCTAssertEqual(query("page", in: requests[3].url), "usage-next")
        XCTAssertTrue(requests.allSatisfy { $0.headers["x-api-key"] == "admin-test-token" })
        XCTAssertTrue(requests.allSatisfy { $0.headers["anthropic-version"] == "2023-06-01" })
    }

    func testEmptyOrganizationReturnsCompleteEmptyCoverage() async throws {
        let client = AnthropicHTTPClientQueue(responses: [
            .success(response(fixture: "empty-page")),
            .success(response(fixture: "empty-page"))
        ])
        let provider = AnthropicProvider(httpClient: client, now: { Self.interval.end })

        let snapshot = try await provider.fetch(Self.fullRequest, credential: "admin-test-token")

        XCTAssertEqual(snapshot.coverage?.completeness, .complete)
        XCTAssertTrue(snapshot.buckets.isEmpty)
    }

    func testPriorityUsageMarksOfficialCostCoveragePartial() async throws {
        let client = AnthropicHTTPClientQueue(responses: [
            .success(response(fixture: "cost-page-2")),
            .success(response(fixture: "usage-priority-page"))
        ])
        let provider = AnthropicProvider(httpClient: client, now: { Self.interval.end })

        let snapshot = try await provider.fetch(Self.fullRequest, credential: "admin-test-token")

        XCTAssertEqual(snapshot.coverage?.completeness, .partial)
        XCTAssertEqual(snapshot.issue, .partialData)
        let costs = snapshot.buckets.compactMap(\.cost)
        XCTAssertFalse(costs.isEmpty)
        XCTAssertTrue(costs.allSatisfy { $0.provenance == .official })
    }

    func testNonAdminOrIndividualAccountMapsToInsufficientPermissions() async throws {
        let failure = HTTPResponse(statusCode: 403, headers: [:], body: fixture("error"))
        let client = AnthropicHTTPClientQueue(
            responses: [.failure(HTTPClientError.httpStatus(failure))]
        )
        let provider = AnthropicProvider(httpClient: client, now: { Self.interval.end })

        do {
            _ = try await provider.fetch(Self.fullRequest, credential: "standard-test-token")
            XCTFail("Expected permission failure")
        } catch {
            XCTAssertEqual(error as? ProviderClientError, .insufficientPermissions)
        }
    }

    func testCostFailureDoesNotPublishUsageOnlySnapshot() async throws {
        let failure = HTTPResponse(statusCode: 500, headers: [:], body: fixture("error"))
        let client = AnthropicHTTPClientQueue(
            responses: [.failure(HTTPClientError.httpStatus(failure))]
        )
        let provider = AnthropicProvider(httpClient: client, now: { Self.interval.end })

        do {
            _ = try await provider.fetch(Self.fullRequest, credential: "admin-test-token")
            XCTFail("Expected provider failure")
        } catch {
            XCTAssertEqual(error as? ProviderClientError, .unavailable)
        }
        let requestCount = await client.requestCount
        XCTAssertEqual(requestCount, 1)
    }

    func testIncrementalPageCapMarksSnapshotPartial() async throws {
        let client = AnthropicHTTPClientQueue(responses: [
            .success(response(fixture: "cost-page")),
            .success(response(fixture: "cost-page")),
            .success(response(fixture: "usage-page")),
            .success(response(fixture: "usage-page"))
        ])
        let provider = AnthropicProvider(httpClient: client, now: { Self.interval.end })
        let request = ProviderFetchRequest(purpose: .incremental, reportingInterval: Self.interval)

        let snapshot = try await provider.fetch(request, credential: "admin-test-token")

        XCTAssertEqual(snapshot.coverage?.completeness, .partial)
        XCTAssertEqual(snapshot.issue, .partialData)
        let requestCount = await client.requestCount
        XCTAssertEqual(requestCount, 4)
    }

    private static let interval = DateInterval(
        start: Date(timeIntervalSince1970: 1_783_641_600),
        end: Date(timeIntervalSince1970: 1_783_814_400)
    )
    private static let fullRequest = ProviderFetchRequest(
        purpose: .full,
        reportingInterval: interval
    )

    private func query(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == name }?
            .value
    }

    private func queries(_ name: String, in url: URL) -> [String] {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .filter { $0.name == name }
            .compactMap(\.value) ?? []
    }

    private func response(fixture name: String) -> HTTPResponse {
        HTTPResponse(statusCode: 200, headers: [:], body: fixture(name))
    }

    private func fixture(_ name: String) -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Fixtures/Anthropic/\(name).json")
        return try! Data(contentsOf: url)
    }
}

private actor AnthropicHTTPClientQueue: HTTPClient {
    private(set) var requests: [HTTPRequest] = []
    private var responses: [Result<HTTPResponse, Error>]

    init(responses: [Result<HTTPResponse, Error>]) {
        self.responses = responses
    }

    var requestCount: Int { requests.count }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        return try responses.removeFirst().get()
    }
}
