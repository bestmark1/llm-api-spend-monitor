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
                endpointStore: QwenEndpointStoreStub(endpoint: QwenAPIEndpoint.defaultValue)
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
            endpointStore: QwenEndpointStoreStub(endpoint: "https://example.com/compatible-mode/v1")
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

private actor QwenHTTPClientQueue: HTTPClient {
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
