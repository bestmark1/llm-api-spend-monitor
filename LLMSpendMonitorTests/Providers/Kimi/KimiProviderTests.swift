import XCTest
@testable import LLMSpendMonitor

final class KimiProviderTests: XCTestCase {
    func testFetchReturnsOfficialBalanceBreakdown() async throws {
        let client = KimiHTTPClientQueue(responses: [.success(Self.balanceResponse)])
        let provider = KimiProvider(httpClient: client, now: { Self.now })

        let snapshot = try await provider.fetch(Self.request, credential: "kimi-test-key")

        XCTAssertEqual(snapshot.providerID, .kimi)
        XCTAssertEqual(snapshot.capabilities, [.balance])
        XCTAssertEqual(snapshot.fetchedAt, Self.now)
        XCTAssertNil(snapshot.coverage)
        XCTAssertTrue(snapshot.buckets.isEmpty)
        XCTAssertNil(snapshot.issue)
        XCTAssertEqual(snapshot.balances.first?.total.value.amount, Decimal(string: "49.58894"))
        XCTAssertEqual(snapshot.balances.first?.granted?.value.amount, Decimal(string: "46.58893"))
        XCTAssertEqual(snapshot.balances.first?.toppedUp?.value.amount, Decimal(string: "3.00001"))
        XCTAssertEqual(snapshot.balances.first?.total.value.currencyCode, "USD")
        XCTAssertEqual(snapshot.balances.first?.total.provenance, .official)

        let requests = await client.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.method, .get)
        XCTAssertEqual(request.url.absoluteString, "https://api.moonshot.ai/v1/users/me/balance")
        XCTAssertEqual(request.headers["Authorization"], "Bearer kimi-test-key")
    }

    func testMapsAuthenticationAndRateLimitErrors() async throws {
        let cases: [(Int, [String: String], ProviderClientError)] = [
            (401, [:], .invalidCredential),
            (403, [:], .unavailable),
            (429, ["retry-after": "12"], .rateLimited(retryAfterSeconds: 12))
        ]

        for (statusCode, headers, expected) in cases {
            let client = KimiHTTPClientQueue(responses: [
                .failure(HTTPClientError.httpStatus(
                    HTTPResponse(statusCode: statusCode, headers: headers, body: Data())
                ))
            ])
            let provider = KimiProvider(httpClient: client, now: { Self.now })

            do {
                _ = try await provider.fetch(Self.request, credential: "kimi-test-key")
                XCTFail("Expected HTTP \(statusCode) to fail")
            } catch {
                XCTAssertEqual(error as? ProviderClientError, expected)
            }
        }
    }

    func testRejectsUnsuccessfulPayloadAndEmptyCredential() async throws {
        let unsuccessful = HTTPResponse(
            statusCode: 200,
            headers: [:],
            body: Data(#"{"status":false,"data":{"available_balance":0,"voucher_balance":0,"cash_balance":0}}"#.utf8)
        )
        let provider = KimiProvider(
            httpClient: KimiHTTPClientQueue(responses: [.success(unsuccessful)]),
            now: { Self.now }
        )

        do {
            _ = try await provider.fetch(Self.request, credential: "kimi-test-key")
            XCTFail("Expected unsuccessful payload to fail")
        } catch {
            XCTAssertEqual(error as? ProviderClientError, .malformedResponse)
        }

        do {
            _ = try await provider.fetch(Self.request, credential: "   ")
            XCTFail("Expected empty credential to fail")
        } catch {
            XCTAssertEqual(error as? ProviderClientError, .invalidCredential)
        }
    }

    private static let now = Date(timeIntervalSince1970: 1_784_332_800)
    private static let request = ProviderFetchRequest(purpose: .full, reportingInterval: nil)
    private static let balanceResponse = HTTPResponse(
        statusCode: 200,
        headers: [:],
        body: Data("""
        {
          "code": 0,
          "data": {
            "available_balance": 49.58894,
            "voucher_balance": 46.58893,
            "cash_balance": 3.00001
          },
          "scode": "0x0",
          "status": true
        }
        """.utf8)
    )
}

private actor KimiHTTPClientQueue: HTTPClient {
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
