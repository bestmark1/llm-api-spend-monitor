import XCTest
@testable import LLMSpendMonitor

final class GeminiProviderTests: XCTestCase {
    func testValidKeyReturnsConnectionOnlySnapshotWithoutFinancialMetrics() async throws {
        let client = GeminiHTTPClientQueue(responses: [.success(response(fixture: "models"))])
        let provider = GeminiProvider(httpClient: client, now: { Self.now })

        let snapshot = try await provider.fetch(Self.request, credential: "gemini-test-key")

        XCTAssertEqual(snapshot.providerID, .gemini)
        XCTAssertEqual(snapshot.capabilities, [.credentialValidation])
        XCTAssertEqual(snapshot.fetchedAt, Self.now)
        XCTAssertNil(snapshot.coverage)
        XCTAssertTrue(snapshot.buckets.isEmpty)
        XCTAssertTrue(snapshot.balances.isEmpty)
        XCTAssertNil(snapshot.issue)

        let requests = await client.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.method, .get)
        XCTAssertEqual(request.url.host, "generativelanguage.googleapis.com")
        XCTAssertEqual(request.url.path, "/v1beta/models")
        XCTAssertEqual(query("pageSize", in: request.url), "1")
        XCTAssertNil(query("key", in: request.url))
        XCTAssertEqual(request.headers["x-goog-api-key"], "gemini-test-key")
        XCTAssertEqual(request.headers["Accept"], "application/json")
    }

    func testEmptyModelListStillValidatesTheKey() async throws {
        let body = Data(#"{"models":[]}"#.utf8)
        let client = GeminiHTTPClientQueue(
            responses: [.success(HTTPResponse(statusCode: 200, headers: [:], body: body))]
        )
        let provider = GeminiProvider(httpClient: client, now: { Self.now })

        let snapshot = try await provider.fetch(Self.request, credential: "gemini-test-key")

        XCTAssertEqual(snapshot.providerID, .gemini)
        XCTAssertTrue(snapshot.buckets.isEmpty)
        XCTAssertTrue(snapshot.balances.isEmpty)
    }

    func testMapsInvalidRestrictedAndRateLimitedKeys() async throws {
        let cases: [(Int, [String: String], ProviderClientError)] = [
            (400, [:], .invalidCredential),
            (401, [:], .invalidCredential),
            (403, [:], .insufficientPermissions),
            (429, ["retry-after": "13"], .rateLimited(retryAfterSeconds: 13))
        ]

        for (statusCode, headers, expected) in cases {
            let failure = HTTPResponse(
                statusCode: statusCode,
                headers: headers,
                body: fixture("error")
            )
            let client = GeminiHTTPClientQueue(
                responses: [.failure(HTTPClientError.httpStatus(failure))]
            )
            let provider = GeminiProvider(httpClient: client, now: { Self.now })

            do {
                _ = try await provider.fetch(Self.request, credential: "gemini-test-key")
                XCTFail("Expected HTTP \(statusCode) to fail")
            } catch {
                XCTAssertEqual(error as? ProviderClientError, expected)
            }
        }
    }

    func testServiceFailureAndOfflineNetworkAreTyped() async throws {
        let serviceFailure = HTTPResponse(statusCode: 503, headers: [:], body: Data())
        let cases: [(Error, ProviderClientError)] = [
            (HTTPClientError.httpStatus(serviceFailure), .unavailable),
            (HTTPClientError.transport(.notConnectedToInternet), .offline)
        ]

        for (failure, expected) in cases {
            let client = GeminiHTTPClientQueue(responses: [.failure(failure)])
            let provider = GeminiProvider(httpClient: client, now: { Self.now })

            do {
                _ = try await provider.fetch(Self.request, credential: "gemini-test-key")
                XCTFail("Expected request to fail")
            } catch {
                XCTAssertEqual(error as? ProviderClientError, expected)
            }
        }
    }

    func testMalformedResponseAndBlankKeyAreRejected() async throws {
        let body = Data(#"{"models":[{"displayName":"Missing required name"}]}"#.utf8)
        let client = GeminiHTTPClientQueue(
            responses: [.success(HTTPResponse(statusCode: 200, headers: [:], body: body))]
        )
        let provider = GeminiProvider(httpClient: client, now: { Self.now })

        do {
            _ = try await provider.fetch(Self.request, credential: "gemini-test-key")
            XCTFail("Expected malformed response to fail")
        } catch {
            XCTAssertEqual(error as? ProviderClientError, .malformedResponse)
        }

        do {
            _ = try await provider.fetch(Self.request, credential: "  ")
            XCTFail("Expected blank key to fail")
        } catch {
            XCTAssertEqual(error as? ProviderClientError, .invalidCredential)
        }
    }

    private static let now = Date(timeIntervalSince1970: 1_784_332_800)
    private static let request = ProviderFetchRequest(
        purpose: .credentialValidation,
        reportingInterval: nil
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
            .appending(path: "Fixtures/Gemini/\(name).json")
        return try! Data(contentsOf: url)
    }
}

private actor GeminiHTTPClientQueue: HTTPClient {
    private(set) var requests: [HTTPRequest] = []
    private var responses: [Result<HTTPResponse, Error>]

    init(responses: [Result<HTTPResponse, Error>]) {
        self.responses = responses
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        return try responses.removeFirst().get()
    }
}
