import XCTest
@testable import LLMSpendMonitor

final class MistralProviderTests: XCTestCase {
    func testFetchReturnsOfficialRemainingMonthlyLimit() async throws {
        let client = MistralHTTPClientQueue(responses: [.success(Self.limitResponse)])
        let provider = MistralProvider(httpClient: client, now: { Self.now })

        let snapshot = try await provider.fetch(Self.request, credential: "admin-key")

        XCTAssertEqual(snapshot.providerID, .mistral)
        XCTAssertEqual(snapshot.capabilities, [.balance])
        XCTAssertEqual(snapshot.fetchedAt, Self.now)
        XCTAssertNil(snapshot.coverage)
        XCTAssertTrue(snapshot.buckets.isEmpty)
        XCTAssertNil(snapshot.issue)
        XCTAssertEqual(snapshot.balances.first?.total.value.amount, Decimal(string: "74.5"))
        XCTAssertEqual(snapshot.balances.first?.total.value.currencyCode, "USD")
        XCTAssertEqual(snapshot.balances.first?.total.provenance, .official)

        let requests = await client.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.method, .get)
        XCTAssertEqual(request.url.absoluteString, "https://api.mistral.ai/v1/admin/spend-limit")
        XCTAssertEqual(request.headers["x-api-key"], "admin-key")
        XCTAssertNil(request.headers["Authorization"])
    }

    func testUsageAboveLimitClampsRemainingToZero() async throws {
        let response = HTTPResponse(
            statusCode: 200,
            headers: [:],
            body: Data(#"{"limits":{"completion":{"monthly_limit_reached":true,"total_usage":125,"usage_limit":100},"last_payment_failure":false,"last_payment_failure_protection":null,"currency":"USD"}}"#.utf8)
        )
        let provider = MistralProvider(
            httpClient: MistralHTTPClientQueue(responses: [.success(response)]),
            now: { Self.now }
        )

        let snapshot = try await provider.fetch(Self.request, credential: "admin-key")

        XCTAssertEqual(snapshot.balances.first?.total.value.amount, 0)
        XCTAssertEqual(snapshot.issue, .spendingLimitReached)
    }

    func testUnlimitedOrganizationReportsNoSpendingLimitWithoutInventingAValue() async throws {
        let response = HTTPResponse(
            statusCode: 200,
            headers: [:],
            body: Data(#"{"limits":{"completion":{"no_monthly_limit":true,"monthly_limit_reached":false,"total_usage":12.5,"usage_limit":null},"last_payment_failure":false,"last_payment_failure_protection":null,"currency":"EUR"}}"#.utf8)
        )
        let provider = MistralProvider(
            httpClient: MistralHTTPClientQueue(responses: [.success(response)]),
            now: { Self.now }
        )

        let snapshot = try await provider.fetch(Self.request, credential: "admin-key")

        XCTAssertTrue(snapshot.balances.isEmpty)
        XCTAssertEqual(snapshot.issue, .noSpendingLimit)
    }

    func testMapsAdminKeyPermissionErrors() async throws {
        let cases: [(Int, ProviderClientError)] = [
            (401, .invalidCredential),
            (403, .insufficientPermissions),
            (429, .rateLimited(retryAfterSeconds: nil))
        ]

        for (statusCode, expected) in cases {
            let client = MistralHTTPClientQueue(responses: [
                .failure(HTTPClientError.httpStatus(
                    HTTPResponse(statusCode: statusCode, headers: [:], body: Data())
                ))
            ])
            let provider = MistralProvider(httpClient: client, now: { Self.now })

            do {
                _ = try await provider.fetch(Self.request, credential: "admin-key")
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
            body: Data(#"{"limits":{"completion":{"monthly_limit_reached":false,"total_usage":10,"usage_limit":100}}}"#.utf8)
        )
        let provider = MistralProvider(
            httpClient: MistralHTTPClientQueue(responses: [.success(malformed)]),
            now: { Self.now }
        )

        do {
            _ = try await provider.fetch(Self.request, credential: "admin-key")
            XCTFail("Expected missing currency to fail")
        } catch {
            XCTAssertEqual(error as? ProviderClientError, .malformedResponse)
        }

        do {
            _ = try await provider.fetch(Self.request, credential: "  ")
            XCTFail("Expected empty credential to fail")
        } catch {
            XCTAssertEqual(error as? ProviderClientError, .invalidCredential)
        }
    }

    private static let now = Date(timeIntervalSince1970: 1_787_193_600)
    private static let request = ProviderFetchRequest(purpose: .full, reportingInterval: nil)
    private static let limitResponse = HTTPResponse(
        statusCode: 200,
        headers: [:],
        body: Data(#"{"limits":{"completion":{"no_monthly_limit":false,"monthly_limit_reached":false,"usage":25.5,"vibe_usage":0,"total_usage":25.5,"usage_limit":100},"last_payment_failure":false,"last_payment_failure_protection":null,"currency":"USD"}}"#.utf8)
    )
}

private actor MistralHTTPClientQueue: HTTPClient {
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
