import XCTest
@testable import LLMSpendMonitor

final class DeepSeekProviderTests: XCTestCase {
    func testFetchReturnsOfficialUSDBalanceWithoutSpendHistory() async throws {
        let client = DeepSeekHTTPClientQueue(responses: [.success(response(fixture: "balance"))])
        let provider = DeepSeekProvider(httpClient: client, now: { Self.now })

        let snapshot = try await provider.fetch(Self.request, credential: "deepseek-test-token")

        XCTAssertEqual(snapshot.providerID, .deepSeek)
        XCTAssertEqual(snapshot.capabilities, [.balance])
        XCTAssertEqual(snapshot.fetchedAt, Self.now)
        XCTAssertNil(snapshot.coverage)
        XCTAssertTrue(snapshot.buckets.isEmpty)
        XCTAssertNil(snapshot.issue)
        XCTAssertEqual(snapshot.balances, [
            try ProviderBalance(
                total: money("12.3400", currency: "USD"),
                granted: money("2.3400", currency: "USD"),
                toppedUp: money("10.0000", currency: "USD")
            )
        ])

        let requests = await client.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.method, .get)
        XCTAssertEqual(request.url.absoluteString, "https://api.deepseek.com/user/balance")
        XCTAssertEqual(request.headers["Authorization"], "Bearer deepseek-test-token")
        XCTAssertEqual(request.headers["Accept"], "application/json")
    }

    func testFetchKeepsUSDAndCNYBalancesSeparate() async throws {
        let client = DeepSeekHTTPClientQueue(
            responses: [.success(response(fixture: "multi-currency-balance"))]
        )
        let provider = DeepSeekProvider(httpClient: client, now: { Self.now })

        let snapshot = try await provider.fetch(Self.request, credential: "deepseek-test-token")

        XCTAssertEqual(snapshot.balances.map(\.total.value.currencyCode), ["CNY", "USD"])
        XCTAssertEqual(snapshot.balances.map(\.total.value.amount), [Decimal(110), Decimal(string: "1.25")])
        XCTAssertEqual(snapshot.balances.map(\.granted?.value.amount), [Decimal(10), Decimal(string: "0.25")])
        XCTAssertEqual(snapshot.balances.map(\.toppedUp?.value.amount), [Decimal(100), Decimal(1)])
    }

    func testInsufficientBalanceResponseStillPublishesOfficialZeroBalance() async throws {
        let body = Data("""
        {
          "is_available": false,
          "balance_infos": [{
            "currency": "CNY",
            "total_balance": "0",
            "granted_balance": "0",
            "topped_up_balance": "0"
          }]
        }
        """.utf8)
        let client = DeepSeekHTTPClientQueue(
            responses: [.success(HTTPResponse(statusCode: 200, headers: [:], body: body))]
        )
        let provider = DeepSeekProvider(httpClient: client, now: { Self.now })

        let snapshot = try await provider.fetch(Self.request, credential: "deepseek-test-token")

        XCTAssertEqual(snapshot.balances.first?.total.value.amount, 0)
        XCTAssertTrue(snapshot.buckets.isEmpty)
        XCTAssertNil(snapshot.coverage)
    }

    func testTopUpChangesBalanceButNeverCreatesSpendHistory() async throws {
        let before = balanceResponse(total: "1.00", granted: "0.25", toppedUp: "0.75")
        let after = balanceResponse(total: "6.00", granted: "0.25", toppedUp: "5.75")
        let client = DeepSeekHTTPClientQueue(responses: [.success(before), .success(after)])
        let provider = DeepSeekProvider(httpClient: client, now: { Self.now })

        let first = try await provider.fetch(Self.request, credential: "deepseek-test-token")
        let second = try await provider.fetch(Self.request, credential: "deepseek-test-token")

        XCTAssertEqual(first.balances.first?.total.value.amount, 1)
        XCTAssertEqual(second.balances.first?.total.value.amount, 6)
        XCTAssertTrue(first.buckets.isEmpty)
        XCTAssertTrue(second.buckets.isEmpty)
        XCTAssertNil(first.coverage)
        XCTAssertNil(second.coverage)
    }

    func testMapsDocumentedAuthenticationBalanceAndRateLimitErrors() async throws {
        let cases: [(Int, [String: String], ProviderClientError)] = [
            (401, [:], .invalidCredential),
            (402, [:], .unavailable),
            (429, ["retry-after": "9"], .rateLimited(retryAfterSeconds: 9))
        ]

        for (statusCode, headers, expected) in cases {
            let response = HTTPResponse(statusCode: statusCode, headers: headers, body: Data())
            let client = DeepSeekHTTPClientQueue(
                responses: [.failure(HTTPClientError.httpStatus(response))]
            )
            let provider = DeepSeekProvider(httpClient: client, now: { Self.now })

            do {
                _ = try await provider.fetch(Self.request, credential: "deepseek-test-token")
                XCTFail("Expected HTTP \(statusCode) to fail")
            } catch {
                XCTAssertEqual(error as? ProviderClientError, expected)
            }
        }
    }

    func testRejectsMalformedDecimalAndEmptyCredential() async throws {
        let body = Data("""
        {
          "is_available": true,
          "balance_infos": [{
            "currency": "USD",
            "total_balance": "not-a-decimal",
            "granted_balance": "0",
            "topped_up_balance": "0"
          }]
        }
        """.utf8)
        let client = DeepSeekHTTPClientQueue(
            responses: [.success(HTTPResponse(statusCode: 200, headers: [:], body: body))]
        )
        let provider = DeepSeekProvider(httpClient: client, now: { Self.now })

        do {
            _ = try await provider.fetch(Self.request, credential: "deepseek-test-token")
            XCTFail("Expected malformed decimal to fail")
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

    private func money(_ amount: String, currency: String) throws -> MoneyMetric {
        MoneyMetric(
            value: try Money(amount: XCTUnwrap(Decimal(string: amount)), currencyCode: currency),
            provenance: .official
        )
    }

    private func response(fixture name: String) -> HTTPResponse {
        HTTPResponse(statusCode: 200, headers: [:], body: fixture(name))
    }

    private func balanceResponse(
        total: String,
        granted: String,
        toppedUp: String
    ) -> HTTPResponse {
        let body = Data("""
        {
          "is_available": true,
          "balance_infos": [{
            "currency": "USD",
            "total_balance": "\(total)",
            "granted_balance": "\(granted)",
            "topped_up_balance": "\(toppedUp)"
          }]
        }
        """.utf8)
        return HTTPResponse(statusCode: 200, headers: [:], body: body)
    }

    private func fixture(_ name: String) -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Fixtures/DeepSeek/\(name).json")
        return try! Data(contentsOf: url)
    }
}

private actor DeepSeekHTTPClientQueue: HTTPClient {
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
