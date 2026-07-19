import XCTest
@testable import LLMSpendMonitor

final class OpenAIProviderTests: XCTestCase {
    func testFetchFollowsBothCursorsAndBuildsExactOfficialSnapshot() async throws {
        let client = HTTPClientQueue(responses: [
            .success(response(fixture: "costs-page")),
            .success(response(fixture: "costs-page-2")),
            .success(response(fixture: "usage-page")),
            .success(response(fixture: "usage-page-2"))
        ])
        let provider = OpenAIProvider(httpClient: client, now: { Self.interval.end })

        let snapshot = try await provider.fetch(Self.fullRequest, credential: "admin-test-token")

        XCTAssertEqual(snapshot.providerID, .openAI)
        XCTAssertEqual(snapshot.coverage?.start, Self.interval.start)
        XCTAssertEqual(snapshot.coverage?.through, Self.interval.end)
        XCTAssertEqual(snapshot.coverage?.completeness, .complete)
        XCTAssertEqual(snapshot.buckets.count, 2)
        XCTAssertEqual(snapshot.buckets[0].cost?.value.amount, Decimal(string: "0.512345"))
        XCTAssertEqual(snapshot.buckets[1].cost?.value.amount, Decimal(string: "0.25"))
        XCTAssertEqual(snapshot.buckets[0].tokenUsage?.inputTokens, 150)
        XCTAssertEqual(snapshot.buckets[0].tokenUsage?.outputTokens, 30)
        XCTAssertEqual(snapshot.buckets[0].tokenUsage?.cachedInputTokens, 40)
        XCTAssertEqual(snapshot.buckets[0].modelBreakdown.map(\.modelID), [
            "gpt-4o-2024-08-06",
            "gpt-4o-mini-2024-07-18"
        ])
        XCTAssertTrue(snapshot.buckets.flatMap(\.modelBreakdown).allSatisfy { $0.cost == nil })

        let requests = await client.requests
        XCTAssertEqual(requests.count, 4)
        XCTAssertEqual(requests[0].url.path, "/v1/organization/costs")
        XCTAssertEqual(query("start_time", in: requests[0].url), "1783641600")
        XCTAssertEqual(query("end_time", in: requests[0].url), "1783814400")
        XCTAssertEqual(query("page", in: requests[1].url), "costs-next")
        XCTAssertEqual(requests[2].url.path, "/v1/organization/usage/completions")
        XCTAssertEqual(query("group_by", in: requests[2].url), "model")
        XCTAssertEqual(query("page", in: requests[3].url), "usage-next")
        XCTAssertTrue(requests.allSatisfy { $0.headers["Authorization"] == "Bearer admin-test-token" })
    }

    func testEmptyOrganizationReturnsCompleteEmptyCoverage() async throws {
        let client = HTTPClientQueue(responses: [
            .success(response(fixture: "empty-page")),
            .success(response(fixture: "empty-page"))
        ])
        let provider = OpenAIProvider(httpClient: client, now: { Self.interval.end })

        let snapshot = try await provider.fetch(Self.fullRequest, credential: "admin-test-token")

        XCTAssertEqual(snapshot.coverage?.completeness, .complete)
        XCTAssertTrue(snapshot.buckets.isEmpty)
    }

    func testScientificNotationZeroCostIsDecodedExactly() async throws {
        let client = HTTPClientQueue(responses: [
            .success(response(fixture: "costs-scientific-zero")),
            .success(response(fixture: "empty-page"))
        ])
        let provider = OpenAIProvider(httpClient: client, now: { Self.interval.end })

        let snapshot = try await provider.fetch(Self.fullRequest, credential: "admin-test-token")

        XCTAssertEqual(snapshot.issue, nil)
        XCTAssertEqual(snapshot.buckets.first?.cost?.value.amount, .zero)
    }

    func testCostFailureNeverPublishesUsageOnlySnapshot() async throws {
        let failure = HTTPResponse(
            statusCode: 500,
            headers: [:],
            body: fixture("error")
        )
        let client = HTTPClientQueue(responses: [.failure(HTTPClientError.httpStatus(failure))])
        let provider = OpenAIProvider(httpClient: client, now: { Self.interval.end })

        do {
            _ = try await provider.fetch(Self.fullRequest, credential: "admin-test-token")
            XCTFail("Expected provider failure")
        } catch {
            XCTAssertEqual(error as? ProviderClientError, .unavailable)
        }
        let requestCount = await client.requestCount
        XCTAssertEqual(requestCount, 1)
    }

    func testProjectKeyForbiddenMapsToInsufficientPermissions() async throws {
        let failure = HTTPResponse(statusCode: 403, headers: [:], body: fixture("error"))
        let client = HTTPClientQueue(responses: [.failure(HTTPClientError.httpStatus(failure))])
        let provider = OpenAIProvider(httpClient: client, now: { Self.interval.end })

        do {
            _ = try await provider.fetch(Self.fullRequest, credential: "project-test-token")
            XCTFail("Expected permission failure")
        } catch {
            XCTAssertEqual(error as? ProviderClientError, .insufficientPermissions)
        }
    }

    func testUnauthorizedKeyMapsToInvalidCredential() async throws {
        let failure = HTTPResponse(statusCode: 401, headers: [:], body: fixture("error"))
        let client = HTTPClientQueue(responses: [.failure(HTTPClientError.httpStatus(failure))])
        let provider = OpenAIProvider(httpClient: client, now: { Self.interval.end })

        do {
            _ = try await provider.fetch(Self.fullRequest, credential: "invalid-token")
            XCTFail("Expected authentication failure")
        } catch {
            XCTAssertEqual(error as? ProviderClientError, .invalidCredential)
        }
    }

    func testRateLimitPreservesRetryAfter() async throws {
        let failure = HTTPResponse(
            statusCode: 429,
            headers: ["retry-after": "17"],
            body: fixture("error")
        )
        let client = HTTPClientQueue(responses: [.failure(HTTPClientError.httpStatus(failure))])
        let provider = OpenAIProvider(httpClient: client, now: { Self.interval.end })

        do {
            _ = try await provider.fetch(Self.fullRequest, credential: "admin-test-token")
            XCTFail("Expected rate limit")
        } catch {
            XCTAssertEqual(error as? ProviderClientError, .rateLimited(retryAfterSeconds: 17))
        }
    }

    func testIncrementalPageCapMarksSnapshotPartial() async throws {
        let client = HTTPClientQueue(responses: [
            .success(response(fixture: "costs-page")),
            .success(response(fixture: "costs-page")),
            .success(response(fixture: "usage-page")),
            .success(response(fixture: "usage-page"))
        ])
        let provider = OpenAIProvider(httpClient: client, now: { Self.interval.end })
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

    private func response(fixture name: String) -> HTTPResponse {
        HTTPResponse(statusCode: 200, headers: [:], body: fixture(name))
    }

    private func fixture(_ name: String) -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Fixtures/OpenAI/\(name).json")
        return try! Data(contentsOf: url)
    }
}

private actor HTTPClientQueue: HTTPClient {
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
