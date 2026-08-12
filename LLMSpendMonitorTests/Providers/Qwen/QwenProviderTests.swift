import XCTest
@testable import LLMSpendMonitor

final class QwenProviderTests: XCTestCase {
    func testValidKeyUsesConfiguredOfficialEndpointWithoutFinancialMetrics() async throws {
        let endpointStore = QwenEndpointStoreStub(
            endpoint: "https://workspace.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1/"
        )
        let client = QwenHTTPClientQueue(responses: [.success(Self.modelsResponse)])
        let provider = QwenProvider(
            httpClient: client,
            endpointStore: endpointStore,
            credentialStore: QwenCredentialStoreStub(),
            now: { Self.now }
        )

        let snapshot = try await provider.fetch(Self.request, credential: "qwen-test-key")

        XCTAssertEqual(snapshot.providerID, .qwen)
        XCTAssertEqual(snapshot.capabilities, [.credentialValidation])
        XCTAssertEqual(snapshot.fetchedAt, Self.now)
        XCTAssertNil(snapshot.coverage)
        XCTAssertTrue(snapshot.buckets.isEmpty)
        XCTAssertTrue(snapshot.balances.isEmpty)

        let requests = await client.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.method, .get)
        XCTAssertEqual(request.url.absoluteString, "https://workspace.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1/models")
        XCTAssertEqual(request.headers["Authorization"], "Bearer qwen-test-key")
        XCTAssertEqual(request.headers["Accept"], "application/json")
    }

    func testBillingCredentialsReturnOfficialDailySpend() async throws {
        let credentialStore = QwenCredentialStoreStub(values: [
            QwenBillingCredentialIdentities.accessKeyID: "billing-id",
            QwenBillingCredentialIdentities.accessKeySecret: "billing-secret",
            QwenBillingCredentialIdentities.productCode: "model-studio-code"
        ])
        let client = QwenHTTPClientQueue(responsesByAction: [
            "QueryAccountBalance": [
                .success(Self.balanceResponse(availableAmount: "47.75", currency: "USD"))
            ],
            "QueryAccountBill": [
                .success(Self.mixedBillResponse(date: "2026-07-15")),
                .success(Self.billResponse(date: "2026-07-16", amount: "2.50"))
            ]
        ])
        let provider = QwenProvider(
            httpClient: client,
            endpointStore: QwenEndpointStoreStub(endpoint: QwenAPIEndpoint.defaultValue),
            credentialStore: credentialStore,
            now: { Self.now },
            nonce: { "fixed-nonce" }
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let interval = DateInterval(
            start: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 15))),
            end: try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 17)))
        )

        let snapshot = try await provider.fetch(
            ProviderFetchRequest(purpose: .full, reportingInterval: interval),
            credential: "qwen-test-key"
        )

        XCTAssertEqual(snapshot.capabilities, [.balance, .credentialValidation, .officialCostHistory])
        XCTAssertEqual(snapshot.balances.first?.total.value.amount, Decimal(string: "47.75"))
        XCTAssertEqual(snapshot.balances.first?.total.value.currencyCode, "USD")
        XCTAssertEqual(snapshot.balances.first?.total.provenance, .official)
        XCTAssertEqual(snapshot.coverage?.start, interval.start)
        XCTAssertEqual(snapshot.coverage?.through, interval.end)
        XCTAssertEqual(snapshot.coverage?.completeness, .complete)
        XCTAssertEqual(snapshot.buckets.map { $0.cost?.value.amount }, [Decimal(string: "1.25"), Decimal(string: "2.50")])
        XCTAssertTrue(snapshot.buckets.allSatisfy { $0.cost?.provenance == .official })

        let requests = await client.requests
        XCTAssertEqual(requests.count, 3)
        let balanceRequests = requests.filter {
            Self.queryValue("Action", in: $0) == "QueryAccountBalance"
        }
        XCTAssertEqual(balanceRequests.count, 1)
        XCTAssertFalse(try XCTUnwrap(balanceRequests.first).url.absoluteString.contains("BillingDate="))
        let billRequests = requests.filter {
            Self.queryValue("Action", in: $0) == "QueryAccountBill"
        }
        XCTAssertEqual(billRequests.count, 2)
        for request in billRequests {
            XCTAssertEqual(request.url.host, "business.ap-southeast-1.aliyuncs.com")
            XCTAssertTrue(request.url.absoluteString.contains("ProductCode=model-studio-code"))
            XCTAssertNil(request.headers["Authorization"])
            XCTAssertEqual(Self.queryValue("AccessKeyId", in: request), "billing-id")
            XCTAssertEqual(Self.queryValue("SignatureMethod", in: request), "HMAC-SHA1")
            XCTAssertEqual(Self.queryValue("Version", in: request), "2017-12-14")
            XCTAssertNotNil(Self.queryValue("Signature", in: request))
            XCTAssertFalse(request.headers.values.contains { $0.contains("billing-secret") })
        }
    }

    func testOfficialBalanceSurvivesUnavailableCostHistory() async throws {
        let credentialStore = QwenCredentialStoreStub(values: [
            QwenBillingCredentialIdentities.accessKeyID: "billing-id",
            QwenBillingCredentialIdentities.accessKeySecret: "billing-secret",
            QwenBillingCredentialIdentities.productCode: "model-studio-code"
        ])
        let client = QwenHTTPClientQueue(responsesByAction: [
            "QueryAccountBalance": [
                .success(Self.balanceResponse(availableAmount: "12.34", currency: "USD"))
            ],
            "QueryAccountBill": [
                .failure(HTTPClientError.httpStatus(
                    HTTPResponse(statusCode: 401, headers: [:], body: Data())
                ))
            ]
        ])
        let provider = QwenProvider(
            httpClient: client,
            endpointStore: QwenEndpointStoreStub(endpoint: QwenAPIEndpoint.defaultValue),
            credentialStore: credentialStore,
            now: { Self.now },
            nonce: { "fixed-nonce" }
        )
        let interval = DateInterval(
            start: Self.now.addingTimeInterval(-86_400),
            end: Self.now
        )

        let snapshot = try await provider.fetch(
            ProviderFetchRequest(purpose: .full, reportingInterval: interval),
            credential: "qwen-test-key"
        )

        XCTAssertEqual(snapshot.balances.first?.total.value.amount, Decimal(string: "12.34"))
        XCTAssertTrue(snapshot.buckets.isEmpty)
        XCTAssertEqual(snapshot.issue, .partialData)
        XCTAssertEqual(snapshot.coverage?.completeness, .partial)
    }

    func testOfficialCostHistoryRemainsCompleteWhenBalanceIsUnavailable() async throws {
        let credentialStore = QwenCredentialStoreStub(values: [
            QwenBillingCredentialIdentities.accessKeyID: "billing-id",
            QwenBillingCredentialIdentities.accessKeySecret: "billing-secret",
            QwenBillingCredentialIdentities.productCode: "model-studio-code"
        ])
        let client = QwenHTTPClientQueue(responsesByAction: [
            "QueryAccountBalance": [
                .failure(HTTPClientError.httpStatus(
                    HTTPResponse(statusCode: 503, headers: [:], body: Data())
                ))
            ],
            "QueryAccountBill": [
                .success(Self.billResponse(date: "2026-07-16", amount: "2.50"))
            ]
        ])
        let provider = QwenProvider(
            httpClient: client,
            endpointStore: QwenEndpointStoreStub(endpoint: QwenAPIEndpoint.defaultValue),
            credentialStore: credentialStore,
            now: { Self.now },
            nonce: { "fixed-nonce" }
        )
        let interval = DateInterval(
            start: Self.now.addingTimeInterval(-86_400),
            end: Self.now
        )

        let snapshot = try await provider.fetch(
            ProviderFetchRequest(purpose: .full, reportingInterval: interval),
            credential: "qwen-test-key"
        )

        XCTAssertTrue(snapshot.balances.isEmpty)
        XCTAssertEqual(snapshot.buckets.map { $0.cost?.value.amount }, [Decimal(string: "2.50")])
        XCTAssertEqual(snapshot.coverage?.completeness, .complete)
        XCTAssertEqual(snapshot.issue, .balanceUnavailable)
    }

    func testPartialCostHistoryTakesPrecedenceOverUnavailableBalance() async throws {
        let credentialStore = QwenCredentialStoreStub(values: [
            QwenBillingCredentialIdentities.accessKeyID: "billing-id",
            QwenBillingCredentialIdentities.accessKeySecret: "billing-secret",
            QwenBillingCredentialIdentities.productCode: "model-studio-code"
        ])
        let client = QwenHTTPClientQueue(responsesByAction: [
            "QueryAccountBalance": [
                .failure(HTTPClientError.httpStatus(
                    HTTPResponse(statusCode: 503, headers: [:], body: Data())
                ))
            ],
            "QueryAccountBill": [
                .success(Self.billResponse(date: "2026-07-15", amount: "1.25")),
                .failure(HTTPClientError.httpStatus(
                    HTTPResponse(statusCode: 503, headers: [:], body: Data())
                ))
            ]
        ])
        let provider = QwenProvider(
            httpClient: client,
            endpointStore: QwenEndpointStoreStub(endpoint: QwenAPIEndpoint.defaultValue),
            credentialStore: credentialStore,
            now: { Self.now },
            nonce: { "fixed-nonce" }
        )
        let interval = DateInterval(
            start: Self.now.addingTimeInterval(-172_800),
            end: Self.now
        )

        let snapshot = try await provider.fetch(
            ProviderFetchRequest(purpose: .full, reportingInterval: interval),
            credential: "qwen-test-key"
        )

        XCTAssertTrue(snapshot.balances.isEmpty)
        XCTAssertEqual(snapshot.buckets.map { $0.cost?.value.amount }, [Decimal(string: "1.25")])
        XCTAssertEqual(snapshot.coverage?.completeness, .partial)
        XCTAssertEqual(snapshot.issue, .partialData)
    }

    func testBillingNoPermissionResponseIsNotReportedAsInvalidCredential() async throws {
        let credentialStore = QwenCredentialStoreStub(values: [
            QwenBillingCredentialIdentities.accessKeyID: "billing-id",
            QwenBillingCredentialIdentities.accessKeySecret: "billing-secret",
            QwenBillingCredentialIdentities.productCode: "model-studio-code"
        ])
        let noPermission = HTTPResponse(
            statusCode: 400,
            headers: [:],
            body: Data(#"{"Code":"NoPermission","Message":"not authorized"}"#.utf8)
        )
        let client = QwenHTTPClientQueue(responsesByAction: [
            "QueryAccountBalance": [.failure(HTTPClientError.httpStatus(noPermission))],
            "QueryAccountBill": [.failure(HTTPClientError.httpStatus(noPermission))]
        ])
        let provider = QwenProvider(
            httpClient: client,
            endpointStore: QwenEndpointStoreStub(endpoint: QwenAPIEndpoint.defaultValue),
            credentialStore: credentialStore,
            now: { Self.now },
            nonce: { "fixed-nonce" }
        )

        do {
            _ = try await provider.fetch(
                ProviderFetchRequest(
                    purpose: .full,
                    reportingInterval: DateInterval(
                        start: Self.now.addingTimeInterval(-86_400),
                        end: Self.now
                    )
                ),
                credential: "qwen-test-key"
            )
            XCTFail("Expected insufficient permissions")
        } catch let error as ProviderClientError {
            XCTAssertEqual(error, .insufficientPermissions)
        }
    }

    func testAlibabaRPCSignerMatchesBSSFixedVector() throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let date = try XCTUnwrap(formatter.date(from: "2026-08-11T12:00:00Z"))
        let request = try AlibabaCloudRPCSigner().makeRequest(
            method: .get,
            endpoint: try XCTUnwrap(URL(string: "https://business.aliyuncs.com/")),
            action: "QueryAccountBalance",
            version: "2017-12-14",
            queryItems: [],
            accessKeyID: "test-access-key-id",
            accessKeySecret: "test-access-key-secret",
            date: date,
            nonce: "fixed-nonce"
        )

        XCTAssertEqual(
            URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.percentEncodedQuery,
            "AccessKeyId=test-access-key-id&Action=QueryAccountBalance&Format=JSON&SignatureMethod=HMAC-SHA1&SignatureNonce=fixed-nonce&SignatureVersion=1.0&Timestamp=2026-08-11T12%3A00%3A00Z&Version=2017-12-14&Signature=V3WgfVAEvyItz%2FaGM0IsPNVYFoQ%3D"
        )
        XCTAssertEqual(request.headers["Accept"], "application/json")
        XCTAssertNil(request.headers["Authorization"])
    }

    func testBillingEndpointFollowsConfiguredQwenRegion() throws {
        XCTAssertEqual(
            QwenProvider.billingEndpoint(for: try QwenAPIEndpoint(QwenAPIEndpoint.defaultValue)).host,
            "business.ap-southeast-1.aliyuncs.com"
        )
        XCTAssertEqual(
            QwenProvider.billingEndpoint(
                for: try QwenAPIEndpoint(
                    "https://dashscope.aliyuncs.com/compatible-mode/v1"
                )
            ).host,
            "business.aliyuncs.com"
        )
    }

    func testEndpointRejectsCredentialExfiltrationAndNonCompatiblePaths() throws {
        XCTAssertThrowsError(try QwenAPIEndpoint("https://example.com/compatible-mode/v1")) {
            XCTAssertEqual($0 as? QwenAPIEndpointError, .unsupportedHost)
        }
        XCTAssertThrowsError(try QwenAPIEndpoint("https://dashscope-intl.aliyuncs.com/evil")) {
            XCTAssertEqual($0 as? QwenAPIEndpointError, .unsupportedPath)
        }
        XCTAssertThrowsError(
            try QwenAPIEndpoint("https://user@dashscope-intl.aliyuncs.com/compatible-mode/v1")
        ) {
            XCTAssertEqual($0 as? QwenAPIEndpointError, .invalidURL)
        }
        XCTAssertThrowsError(
            try QwenAPIEndpoint("https://dashscope-intl.aliyuncs.com:8443/compatible-mode/v1")
        ) {
            XCTAssertEqual($0 as? QwenAPIEndpointError, .invalidURL)
        }
        XCTAssertThrowsError(
            try QwenAPIEndpoint("https://token-plan.cn-beijing.maas.aliyuncs.com/compatible-mode/v1")
        ) {
            XCTAssertEqual($0 as? QwenAPIEndpointError, .unsupportedHost)
        }
    }

    func testTokenPlanKeyIsRejectedBeforeNetworkRequest() async throws {
        let client = QwenHTTPClientQueue(responses: [.success(Self.modelsResponse)])
        let provider = QwenProvider(
            httpClient: client,
            endpointStore: QwenEndpointStoreStub(endpoint: QwenAPIEndpoint.defaultValue),
            credentialStore: QwenCredentialStoreStub()
        )

        do {
            _ = try await provider.fetch(Self.request, credential: "sk-sp-token-plan-key")
            XCTFail("Expected Token Plan key to fail")
        } catch {
            XCTAssertEqual(error as? ProviderClientError, .invalidCredential)
        }

        let requests = await client.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testMapsAuthenticationRateLimitOfflineAndMalformedResponse() async throws {
        let cases: [(Result<HTTPResponse, Error>, ProviderClientError)] = [
            (
                .failure(HTTPClientError.httpStatus(
                    HTTPResponse(statusCode: 401, headers: [:], body: Data())
                )),
                .invalidCredential
            ),
            (
                .failure(HTTPClientError.httpStatus(
                    HTTPResponse(statusCode: 429, headers: ["retry-after": "7"], body: Data())
                )),
                .rateLimited(retryAfterSeconds: 7)
            ),
            (.failure(HTTPClientError.transport(.notConnectedToInternet)), .offline),
            (
                .success(HTTPResponse(statusCode: 200, headers: [:], body: Data(#"{"models":[]}"#.utf8))),
                .malformedResponse
            )
        ]

        for (result, expected) in cases {
            let provider = QwenProvider(
                httpClient: QwenHTTPClientQueue(responses: [result]),
                endpointStore: QwenEndpointStoreStub(endpoint: QwenAPIEndpoint.defaultValue),
                credentialStore: QwenCredentialStoreStub()
            )

            do {
                _ = try await provider.fetch(Self.request, credential: "qwen-test-key")
                XCTFail("Expected request to fail")
            } catch {
                XCTAssertEqual(error as? ProviderClientError, expected)
            }
        }
    }

    func testBlankKeyAndUnsafeStoredEndpointAreRejectedBeforeNetworkRequest() async throws {
        let client = QwenHTTPClientQueue(responses: [.success(Self.modelsResponse)])
        let provider = QwenProvider(
            httpClient: client,
            endpointStore: QwenEndpointStoreStub(endpoint: "https://example.com/compatible-mode/v1"),
            credentialStore: QwenCredentialStoreStub()
        )

        do {
            _ = try await provider.fetch(Self.request, credential: "qwen-test-key")
            XCTFail("Expected unsafe endpoint to fail")
        } catch {
            XCTAssertEqual(error as? ProviderClientError, .malformedResponse)
        }
        let requests = await client.requests
        XCTAssertTrue(requests.isEmpty)

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
    private static let modelsResponse = HTTPResponse(
        statusCode: 200,
        headers: [:],
        body: Data(#"{"object":"list","data":[{"id":"qwen3.7-plus","object":"model"}]}"#.utf8)
    )

    private static func balanceResponse(availableAmount: String, currency: String) -> HTTPResponse {
        HTTPResponse(
            statusCode: 200,
            headers: [:],
            body: Data(
                """
                {
                  "Code": "200",
                  "Success": true,
                  "Data": {
                    "AvailableAmount": "\(availableAmount)",
                    "AvailableCashAmount": "40.00",
                    "CreditAmount": "7.75",
                    "Currency": "\(currency)"
                  }
                }
                """.utf8
            )
        )
    }

    private static func queryValue(_ name: String, in request: HTTPRequest) -> String? {
        URLComponents(url: request.url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == name }?
            .value
    }

    private static func billResponse(date: String, amount: String) -> HTTPResponse {
        HTTPResponse(
            statusCode: 200,
            headers: [:],
            body: Data(
                """
                {
                  "Code": "Success",
                  "Success": true,
                  "Data": {
                    "TotalCount": 1,
                    "Items": {
                      "Item": [{
                        "BillingDate": "\(date)",
                        "Currency": "USD",
                        "PretaxAmount": \(amount),
                        "ProductCode": "model-studio-code",
                        "SubscriptionType": "PayAsYouGo"
                      }]
                    }
                  }
                }
                """.utf8
            )
        )
    }

    private static func mixedBillResponse(date: String) -> HTTPResponse {
        HTTPResponse(
            statusCode: 200,
            headers: [:],
            body: Data(
                """
                {
                  "Code": "Success",
                  "Success": true,
                  "Data": {
                    "TotalCount": 2,
                    "Items": {
                      "Item": [
                        {
                          "BillingDate": "\(date)",
                          "Currency": "USD",
                          "PretaxAmount": 1.25,
                          "ProductCode": "model-studio-code",
                          "SubscriptionType": "PayAsYouGo"
                        },
                        {
                          "BillingDate": "\(date)",
                          "Currency": "USD",
                          "PretaxAmount": 99.00,
                          "ProductCode": "model-studio-code",
                          "SubscriptionType": "Subscription"
                        }
                      ]
                    }
                  }
                }
                """.utf8
            )
        )
    }
}

private final class QwenEndpointStoreStub: ProviderEndpointStoring, @unchecked Sendable {
    let endpoint: String?

    init(endpoint: String?) {
        self.endpoint = endpoint
    }

    func loadEndpoint(for providerID: ProviderID) -> String? {
        endpoint
    }

    func saveEndpoint(_ endpoint: String, for providerID: ProviderID) {}
}

private final class QwenCredentialStoreStub: CredentialStoring, @unchecked Sendable {
    private var values: [CredentialIdentity: String]

    init(values: [CredentialIdentity: String] = [:]) {
        self.values = values
    }

    func save(_ secret: String, for identity: CredentialIdentity) throws {
        values[identity] = secret
    }

    func read(for identity: CredentialIdentity) throws -> String {
        guard let value = values[identity] else { throw KeychainStoreError.itemNotFound }
        return value
    }

    func delete(for identity: CredentialIdentity) throws {
        values.removeValue(forKey: identity)
    }
}

private actor QwenHTTPClientQueue: HTTPClient {
    private(set) var requests: [HTTPRequest] = []
    private var responses: [Result<HTTPResponse, Error>]
    private var responsesByAction: [String: [Result<HTTPResponse, Error>]]

    init(responses: [Result<HTTPResponse, Error>]) {
        self.responses = responses
        responsesByAction = [:]
    }

    init(responsesByAction: [String: [Result<HTTPResponse, Error>]]) {
        responses = []
        self.responsesByAction = responsesByAction
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        if let action = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "Action" })?
            .value,
           var actionResponses = responsesByAction[action],
           !actionResponses.isEmpty {
            let response = actionResponses.removeFirst()
            responsesByAction[action] = actionResponses
            return try response.get()
        }
        return try responses.removeFirst().get()
    }
}
