import XCTest
@testable import LLMSpendMonitor

final class XAIProviderTests: XCTestCase {
    func testFetchReturnsOfficialBalanceAndDailyModelSpend() async throws {
        let client = XAIHTTPClientQueue(responses: [
            .success(Self.validationResponse),
            .success(Self.balanceResponse),
            .success(Self.usageResponse)
        ])
        let provider = XAIProvider(httpClient: client, now: { Self.now })

        let snapshot = try await provider.fetch(Self.request, credential: "management-key")

        XCTAssertEqual(snapshot.providerID, .xAI)
        XCTAssertEqual(snapshot.capabilities, [.balance, .officialCostHistory, .modelBreakdown])
        XCTAssertEqual(snapshot.fetchedAt, Self.now)
        XCTAssertEqual(snapshot.coverage?.start, Self.interval.start)
        XCTAssertEqual(snapshot.coverage?.through, Self.interval.end)
        XCTAssertEqual(snapshot.coverage?.completeness, .complete)
        XCTAssertNil(snapshot.issue)
        XCTAssertEqual(snapshot.balances.first?.total.value.amount, Decimal(string: "12.34"))
        XCTAssertEqual(snapshot.balances.first?.total.value.currencyCode, "USD")
        XCTAssertEqual(snapshot.balances.first?.total.provenance, .official)

        XCTAssertEqual(snapshot.buckets.count, 2)
        XCTAssertEqual(snapshot.buckets[0].cost?.value.amount, Decimal(string: "1.25"))
        XCTAssertEqual(snapshot.buckets[1].cost?.value.amount, Decimal(string: "0.75"))
        XCTAssertEqual(snapshot.buckets[0].modelBreakdown.map(\.modelID), [
            "Chat grok-4-0709",
            "Chat grok-4-mini"
        ])
        XCTAssertEqual(
            snapshot.buckets[0].modelBreakdown.compactMap(\.cost?.value.amount),
            [Decimal(string: "0.75"), Decimal(string: "0.50")]
        )

        let requests = await client.requests
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests[0].method, .get)
        XCTAssertEqual(
            requests[0].url.absoluteString,
            "https://management-api.x.ai/auth/management-keys/validation"
        )
        XCTAssertEqual(
            requests[1].url.absoluteString,
            "https://management-api.x.ai/v1/billing/teams/team-123/prepaid/balance"
        )
        XCTAssertEqual(requests[2].method, .post)
        XCTAssertEqual(
            requests[2].url.absoluteString,
            "https://management-api.x.ai/v1/billing/teams/team-123/usage"
        )
        XCTAssertTrue(requests.allSatisfy {
            $0.headers["Authorization"] == "Bearer management-key"
        })

        let body = try XCTUnwrap(requests[2].body)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        let analytics = try XCTUnwrap(json["analyticsRequest"] as? [String: Any])
        let timeRange = try XCTUnwrap(analytics["timeRange"] as? [String: Any])
        XCTAssertEqual(timeRange["startTime"] as? String, "2026-08-01 00:00:00")
        XCTAssertEqual(timeRange["endTime"] as? String, "2026-08-02 23:59:59")
        XCTAssertEqual(timeRange["timezone"] as? String, "Etc/GMT")
        XCTAssertEqual(analytics["timeUnit"] as? String, "TIME_UNIT_DAY")
        XCTAssertEqual(analytics["groupBy"] as? [String], ["description"])
    }

    func testLimitReachedMarksCoveragePartial() async throws {
        let usage = HTTPResponse(
            statusCode: 200,
            headers: [:],
            body: Data(#"{"timeSeries":[],"limitReached":true}"#.utf8)
        )
        let provider = XAIProvider(
            httpClient: XAIHTTPClientQueue(responses: [
                .success(Self.validationResponse),
                .success(Self.balanceResponse),
                .success(usage)
            ]),
            now: { Self.now }
        )

        let snapshot = try await provider.fetch(Self.request, credential: "management-key")

        XCTAssertEqual(snapshot.coverage?.completeness, .partial)
        XCTAssertEqual(snapshot.issue, .partialData)
    }

    func testKeepsUsageWhenBalanceIsUnavailable() async throws {
        let provider = XAIProvider(
            httpClient: XAIHTTPClientQueue(responses: [
                .success(Self.validationResponse),
                Self.status(503),
                .success(Self.usageResponse)
            ]),
            now: { Self.now }
        )

        let snapshot = try await provider.fetch(Self.request, credential: "management-key")

        XCTAssertTrue(snapshot.balances.isEmpty)
        XCTAssertEqual(snapshot.buckets.count, 2)
        XCTAssertEqual(snapshot.coverage?.completeness, .complete)
        XCTAssertEqual(snapshot.issue, .balanceUnavailable)
    }

    func testKeepsBalanceWhenUsageIsUnavailable() async throws {
        let provider = XAIProvider(
            httpClient: XAIHTTPClientQueue(responses: [
                .success(Self.validationResponse),
                .success(Self.balanceResponse),
                Self.status(503)
            ]),
            now: { Self.now }
        )

        let snapshot = try await provider.fetch(Self.request, credential: "management-key")

        XCTAssertEqual(snapshot.balances.first?.total.value.amount, Decimal(string: "12.34"))
        XCTAssertTrue(snapshot.buckets.isEmpty)
        XCTAssertNil(snapshot.coverage)
        XCTAssertEqual(snapshot.issue, .partialData)
    }

    func testMapsManagementKeyAndBillingPermissionErrors() async throws {
        let cases: [([Result<HTTPResponse, Error>], ProviderClientError)] = [
            ([Self.status(401)], .invalidCredential),
            ([
                .success(Self.validationResponse),
                Self.status(403),
                Self.status(403)
            ], .insufficientPermissions),
            ([Self.status(429, headers: ["retry-after": "9"])], .rateLimited(retryAfterSeconds: 9))
        ]

        for (responses, expected) in cases {
            let provider = XAIProvider(
                httpClient: XAIHTTPClientQueue(responses: responses),
                now: { Self.now }
            )

            do {
                _ = try await provider.fetch(Self.request, credential: "management-key")
                XCTFail("Expected request to fail")
            } catch {
                XCTAssertEqual(error as? ProviderClientError, expected)
            }
        }
    }

    func testRequiresTeamScopedKeyReportingIntervalAndNonemptyCredential() async throws {
        let organizationKey = HTTPResponse(
            statusCode: 200,
            headers: [:],
            body: Data(#"{"teamId":"legacy-team","scope":"SCOPE_ORGANIZATION","scopeId":"org-123"}"#.utf8)
        )
        let provider = XAIProvider(
            httpClient: XAIHTTPClientQueue(responses: [.success(organizationKey)]),
            now: { Self.now }
        )

        do {
            _ = try await provider.fetch(Self.request, credential: "management-key")
            XCTFail("Expected an organization-scoped key to fail even with a legacy team ID")
        } catch {
            XCTAssertEqual(error as? ProviderClientError, .insufficientPermissions)
        }

        do {
            _ = try await provider.fetch(
                ProviderFetchRequest(purpose: .full, reportingInterval: nil),
                credential: "management-key"
            )
            XCTFail("Expected a reporting interval to be required")
        } catch {
            XCTAssertEqual(error as? ProviderClientError, .malformedResponse)
        }

        do {
            _ = try await provider.fetch(Self.request, credential: "  ")
            XCTFail("Expected an empty key to fail")
        } catch {
            XCTAssertEqual(error as? ProviderClientError, .invalidCredential)
        }
    }

    func testUsesTeamScopeIDWhenLegacyTeamIDIsMissing() async throws {
        let scopedKey = HTTPResponse(
            statusCode: 200,
            headers: [:],
            body: Data(#"{"scope":"SCOPE_TEAM","scopeId":"scope-team"}"#.utf8)
        )
        let client = XAIHTTPClientQueue(responses: [
            .success(scopedKey),
            .success(Self.balanceResponse),
            .success(Self.usageResponse)
        ])
        let provider = XAIProvider(httpClient: client, now: { Self.now })

        _ = try await provider.fetch(Self.request, credential: "management-key")

        let requests = await client.requests
        XCTAssertEqual(
            requests[1].url.absoluteString,
            "https://management-api.x.ai/v1/billing/teams/scope-team/prepaid/balance"
        )
    }

    private static func status(
        _ statusCode: Int,
        headers: [String: String] = [:]
    ) -> Result<HTTPResponse, Error> {
        .failure(HTTPClientError.httpStatus(
            HTTPResponse(statusCode: statusCode, headers: headers, body: Data())
        ))
    }

    private static let interval = DateInterval(
        start: Date(timeIntervalSince1970: 1_785_542_400),
        end: Date(timeIntervalSince1970: 1_785_715_200)
    )
    private static let now = Date(timeIntervalSince1970: 1_785_715_200)
    private static let request = ProviderFetchRequest(
        purpose: .full,
        reportingInterval: interval
    )
    private static let validationResponse = HTTPResponse(
        statusCode: 200,
        headers: [:],
        body: Data(#"{"teamId":"team-123","scope":"SCOPE_TEAM","scopeId":"team-123"}"#.utf8)
    )
    private static let balanceResponse = HTTPResponse(
        statusCode: 200,
        headers: [:],
        body: Data(#"{"changes":[],"total":{"val":"-1234"}}"#.utf8)
    )
    private static let usageResponse = HTTPResponse(
        statusCode: 200,
        headers: [:],
        body: Data("""
        {
          "timeSeries": [
            {
              "group": ["Chat grok-4-0709"],
              "groupLabels": ["Chat grok-4-0709"],
              "dataPoints": [
                {"timestamp":"2026-08-01T00:00:00Z","values":[0.75]},
                {"timestamp":"2026-08-02T00:00:00Z","values":[0.25]}
              ]
            },
            {
              "group": ["Chat grok-4-mini"],
              "groupLabels": ["Chat grok-4-mini"],
              "dataPoints": [
                {"timestamp":"2026-08-01T00:00:00Z","values":[0.50]},
                {"timestamp":"2026-08-02T00:00:00Z","values":[0.50]}
              ]
            }
          ],
          "limitReached": false
        }
        """.utf8)
    )
}

private actor XAIHTTPClientQueue: HTTPClient {
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
