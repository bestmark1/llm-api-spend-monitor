import XCTest
import Security
@testable import LLMSpendMonitor

final class GeminiProviderTests: XCTestCase {
    func testValidKeyWithoutMonitoringAccessReturnsConnectionOnlySnapshot() async throws {
        let client = GeminiHTTPClientQueue(responses: [.success(response(fixture: "models"))])
        let provider = GeminiProvider(httpClient: client, now: { Self.now })

        let snapshot = try await provider.fetch(Self.request, credential: "gemini-test-key")

        XCTAssertEqual(snapshot.providerID, .gemini)
        XCTAssertEqual(snapshot.capabilities, [.credentialValidation, .tokenUsage, .modelBreakdown])
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

    func testMonitoringAccessReturnsOfficialFreeTierTokensByModel() async throws {
        let store = GeminiCredentialStore(values: [
            GeminiMonitoringCredentialIdentities.serviceAccountJSON: Self.serviceAccountJSON
        ])
        let client = GeminiMonitoringHTTPClient()
        let provider = GeminiProvider(
            httpClient: client,
            credentialStore: store,
            now: { Self.now },
            accessTokenProvider: { credentials in
                XCTAssertEqual(credentials.projectID, "spender-test-project")
                return "monitoring-access-token"
            }
        )
        let interval = DateInterval(
            start: Date(timeIntervalSince1970: 1_783_641_600),
            end: Date(timeIntervalSince1970: 1_784_332_800)
        )

        let snapshot = try await provider.fetch(
            ProviderFetchRequest(purpose: .full, reportingInterval: interval),
            credential: "gemini-test-key"
        )

        XCTAssertEqual(snapshot.coverage?.start, interval.start)
        XCTAssertEqual(snapshot.coverage?.through, interval.end)
        XCTAssertEqual(snapshot.buckets.count, 1)
        let bucket = try XCTUnwrap(snapshot.buckets.first)
        XCTAssertEqual(bucket.tokenUsage?.inputTokens, 120)
        XCTAssertEqual(bucket.tokenUsage?.outputTokens, 40)
        XCTAssertEqual(bucket.tokenUsage?.provenance, .official)
        XCTAssertEqual(bucket.modelBreakdown.map(\.modelID), ["gemini-2.5-flash"])
        XCTAssertEqual(bucket.modelBreakdown.first?.tokenUsage?.inputTokens, 120)
        XCTAssertEqual(bucket.modelBreakdown.first?.tokenUsage?.outputTokens, 40)

        let requests = await client.requests
        XCTAssertEqual(requests.filter { $0.url.host == "monitoring.googleapis.com" }.count, 5)
        XCTAssertTrue(
            requests.filter { $0.url.host == "monitoring.googleapis.com" }
                .allSatisfy { $0.headers["Authorization"] == "Bearer monitoring-access-token" }
        )
    }

    func testServiceAccountPKCS8KeyCreatesSignedMonitoringJWT() throws {
        let privateKey = try makeServiceAccountPrivateKey()
        let jsonData = try JSONSerialization.data(withJSONObject: [
            "type": "service_account",
            "project_id": "spender-test-project",
            "private_key": privateKey,
            "client_email": "spender@spender-test-project.iam.gserviceaccount.com"
        ])
        let credentials = try GeminiMonitoringCredentials(
            json: String(decoding: jsonData, as: UTF8.self)
        )
        let issuedAt = Date(timeIntervalSince1970: 1_784_332_800)

        let jwt = try GeminiServiceAccountJWT.make(credentials: credentials, now: issuedAt)

        let parts = jwt.split(separator: ".")
        XCTAssertEqual(parts.count, 3)
        XCTAssertFalse(parts[2].isEmpty)
        let claimsData = try XCTUnwrap(decodeBase64URL(String(parts[1])))
        let claims = try XCTUnwrap(
            JSONSerialization.jsonObject(with: claimsData) as? [String: Any]
        )
        XCTAssertEqual(claims["iss"] as? String, credentials.clientEmail)
        XCTAssertEqual(
            claims["scope"] as? String,
            "https://www.googleapis.com/auth/monitoring.read"
        )
        XCTAssertEqual(claims["iat"] as? Int, Int(issuedAt.timeIntervalSince1970))
        XCTAssertEqual(claims["exp"] as? Int, Int(issuedAt.timeIntervalSince1970) + 3_600)
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
    private static let serviceAccountJSON = #"{"type":"service_account","project_id":"spender-test-project","private_key":"-----BEGIN PRIVATE KEY-----\nAA==\n-----END PRIVATE KEY-----\n","client_email":"spender@spender-test-project.iam.gserviceaccount.com"}"#

    private func query(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == name }?
            .value
    }

    private func decodeBase64URL(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }

    private func makeServiceAccountPrivateKey() throws -> String {
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits: 1_024
        ]
        var creationError: Unmanaged<CFError>?
        let key = try XCTUnwrap(
            SecKeyCreateRandomKey(attributes as CFDictionary, &creationError)
        )
        var exportError: Unmanaged<CFError>?
        let pkcs1 = try XCTUnwrap(
            SecKeyCopyExternalRepresentation(key, &exportError) as Data?
        )
        let version = Data([0x02, 0x01, 0x00])
        let rsaAlgorithmIdentifier = Data([
            0x30, 0x0d,
            0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01,
            0x05, 0x00
        ])
        let pkcs8 = der(tag: 0x30, value: version + rsaAlgorithmIdentifier + der(tag: 0x04, value: pkcs1))
        let base64 = pkcs8.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return "-----BEGIN PRIVATE KEY-----\n\(base64)-----END PRIVATE KEY-----"
    }

    private func der(tag: UInt8, value: Data) -> Data {
        var result = Data([tag])
        if value.count < 0x80 {
            result.append(UInt8(value.count))
        } else {
            var bytes: [UInt8] = []
            var length = value.count
            while length > 0 {
                bytes.insert(UInt8(length & 0xff), at: 0)
                length >>= 8
            }
            result.append(0x80 | UInt8(bytes.count))
            result.append(contentsOf: bytes)
        }
        result.append(value)
        return result
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

private final class GeminiCredentialStore: CredentialStoring, @unchecked Sendable {
    private let values: [CredentialIdentity: String]

    init(values: [CredentialIdentity: String]) {
        self.values = values
    }

    func save(_ secret: String, for identity: CredentialIdentity) throws {}

    func read(for identity: CredentialIdentity) throws -> String {
        guard let value = values[identity] else { throw KeychainStoreError.itemNotFound }
        return value
    }

    func delete(for identity: CredentialIdentity) throws {}
}

private actor GeminiMonitoringHTTPClient: HTTPClient {
    private(set) var requests: [HTTPRequest] = []

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        if request.url.host == "generativelanguage.googleapis.com" {
            return HTTPResponse(
                statusCode: 200,
                headers: [:],
                body: Data(#"{"models":[{"name":"models/gemini-2.5-flash"}]}"#.utf8)
            )
        }

        let filter = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "filter" }?.value ?? ""
        let body: Data
        if filter.contains("generate_content_free_tier_input_token_count") {
            body = Data(#"{"timeSeries":[{"metric":{"labels":{"model":"gemini-2.5-flash"}},"points":[{"interval":{"endTime":"2026-07-17T12:00:00Z"},"value":{"int64Value":"120"}}]}]}"#.utf8)
        } else if filter.contains("generate_content_usage_output_token_count") {
            body = Data(#"{"timeSeries":[{"metric":{"labels":{"model":"gemini-2.5-flash"}},"points":[{"interval":{"endTime":"2026-07-17T12:00:00Z"},"value":{"int64Value":"40"}}]}]}"#.utf8)
        } else {
            body = Data(#"{"timeSeries":[]}"#.utf8)
        }
        return HTTPResponse(statusCode: 200, headers: [:], body: body)
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
