import XCTest
@testable import LLMSpendMonitor

final class OpenRouterProviderTests: XCTestCase {
    func testFetchReturnsOfficialRemainingCredits() async throws {
        let client = OpenRouterHTTPClientQueue(responses: [.success(Self.creditsResponse)])
        let provider = OpenRouterProvider(httpClient: client, now: { Self.now })

        let snapshot = try await provider.fetch(Self.request, credential: "management-key")

        XCTAssertEqual(snapshot.providerID, .openRouter)
        XCTAssertEqual(snapshot.capabilities, [.balance])
        XCTAssertEqual(snapshot.fetchedAt, Self.now)
        XCTAssertNil(snapshot.coverage)
        XCTAssertTrue(snapshot.buckets.isEmpty)
        XCTAssertNil(snapshot.issue)
        XCTAssertEqual(snapshot.balances.first?.total.value.amount, Decimal(string: "74.75"))
        XCTAssertEqual(snapshot.balances.first?.total.value.currencyCode, "USD")
        XCTAssertEqual(snapshot.balances.first?.total.provenance, .official)

        let requests = await client.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.method, .get)
        XCTAssertEqual(request.url.absoluteString, "https://openrouter.ai/api/v1/credits")
        XCTAssertEqual(request.headers["Authorization"], "Bearer management-key")
    }

    func testUsageAbovePurchasedCreditsClampsRemainingToZero() async throws {
        let response = HTTPResponse(
            statusCode: 200,
            headers: [:],
            body: Data(#"{"data":{"total_credits":10,"total_usage":12.5}}"#.utf8)
        )
        let provider = OpenRouterProvider(
            httpClient: OpenRouterHTTPClientQueue(responses: [.success(response)]),
            now: { Self.now }
        )

        let snapshot = try await provider.fetch(Self.request, credential: "management-key")

        XCTAssertEqual(snapshot.balances.first?.total.value.amount, 0)
    }

    func testMapsManagementKeyPermissionErrors() async throws {
        let cases: [(Int, ProviderClientError)] = [
            (401, .invalidCredential),
            (403, .insufficientPermissions),
            (429, .rateLimited(retryAfterSeconds: nil))
        ]

        for (statusCode, expected) in cases {
            let client = OpenRouterHTTPClientQueue(responses: [
                .failure(HTTPClientError.httpStatus(
                    HTTPResponse(statusCode: statusCode, headers: [:], body: Data())
                ))
            ])
            let provider = OpenRouterProvider(httpClient: client, now: { Self.now })

            do {
                _ = try await provider.fetch(Self.request, credential: "management-key")
                XCTFail("Expected HTTP \(statusCode) to fail")
            } catch {
                XCTAssertEqual(error as? ProviderClientError, expected)
            }
        }
    }

    func testRejectsMalformedPayloadAndEmptyCredential() async throws {
        let malformed = HTTPResponse(
            statusCode: 200,
            headers: [:],
            body: Data(#"{"data":{"total_credits":"unknown"}}"#.utf8)
        )
        let provider = OpenRouterProvider(
            httpClient: OpenRouterHTTPClientQueue(responses: [.success(malformed)]),
            now: { Self.now }
        )

        do {
            _ = try await provider.fetch(Self.request, credential: "management-key")
            XCTFail("Expected malformed payload to fail")
        } catch {
            XCTAssertEqual(error as? ProviderClientError, .malformedResponse)
        }

        do {
            _ = try await provider.fetch(Self.request, credential: "\n")
            XCTFail("Expected empty credential to fail")
        } catch {
            XCTAssertEqual(error as? ProviderClientError, .invalidCredential)
        }
    }

    private static let now = Date(timeIntervalSince1970: 1_784_332_800)
    private static let request = ProviderFetchRequest(purpose: .full, reportingInterval: nil)
    private static let creditsResponse = HTTPResponse(
        statusCode: 200,
        headers: [:],
        body: Data(#"{"data":{"total_credits":100.5,"total_usage":25.75}}"#.utf8)
    )
}

private actor OpenRouterHTTPClientQueue: HTTPClient {
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
