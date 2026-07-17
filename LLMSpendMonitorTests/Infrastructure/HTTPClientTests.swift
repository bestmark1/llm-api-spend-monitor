import XCTest
@testable import LLMSpendMonitor

final class HTTPClientTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }

    func testReturnsSuccessfulHTTPSResponse() async throws {
        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(#"{"ok":true}"#.utf8))
        }
        let client = makeClient()

        let response = try await client.send(
            makeRequest(headers: ["Authorization": "Bearer test-token"])
        )

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.body, Data(#"{"ok":true}"#.utf8))
    }

    func testRejectsNonHTTPSRequestBeforeStartingTransport() throws {
        XCTAssertThrowsError(
            try HTTPRequest(
                method: .get,
                url: URL(string: "http://api.example.com/usage")!,
                allowedOrigin: HTTPOrigin(httpsURL: URL(string: "https://api.example.com")!)
            )
        ) { error in
            XCTAssertEqual(error as? HTTPClientError, .insecureURL)
        }
    }

    func testRejectsResponseThatExceedsByteLimit() async throws {
        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(repeating: 0x41, count: 9))
        }
        let client = makeClient()

        do {
            _ = try await client.send(makeRequest(maxResponseBytes: 8))
            XCTFail("Expected response size rejection")
        } catch {
            XCTAssertEqual(error as? HTTPClientError, .responseTooLarge(limit: 8))
        }
    }

    func testThrowsTypedHTTPStatusWithResponseMetadata() async throws {
        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 429,
                httpVersion: nil,
                headerFields: ["Retry-After": "7"]
            )!
            return (response, Data(#"{"error":"rate_limit"}"#.utf8))
        }
        let client = makeClient()

        do {
            _ = try await client.send(makeRequest())
            XCTFail("Expected typed HTTP status error")
        } catch let HTTPClientError.httpStatus(response) {
            XCTAssertEqual(response.statusCode, 429)
            XCTAssertEqual(response.header(named: "Retry-After"), "7")
            XCTAssertEqual(response.body, Data(#"{"error":"rate_limit"}"#.utf8))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCrossOriginRedirectPolicyRefusesRedirectWithoutCopyingCredential() throws {
        let origin = try HTTPOrigin(httpsURL: URL(string: "https://api.example.com")!)
        let policy = HTTPRedirectPolicy(
            allowedOrigin: origin,
            originalHeaders: ["Authorization": "Bearer secret"]
        )
        let redirect = URLRequest(url: URL(string: "https://attacker.example/collect")!)

        let approved = policy.approvedRequest(for: redirect)

        XCTAssertNil(approved)
        XCTAssertNil(redirect.value(forHTTPHeaderField: "Authorization"))
    }

    func testSameOriginRedirectPreservesExplicitHeaders() throws {
        let origin = try HTTPOrigin(httpsURL: URL(string: "https://api.example.com")!)
        let policy = HTTPRedirectPolicy(
            allowedOrigin: origin,
            originalHeaders: ["Authorization": "Bearer secret"]
        )
        let redirect = URLRequest(url: URL(string: "https://api.example.com/v2/usage")!)

        let approved = try XCTUnwrap(policy.approvedRequest(for: redirect))

        XCTAssertEqual(approved.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
    }

    private func makeClient() -> URLSessionHTTPClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSessionHTTPClient(configuration: configuration)
    }

    private func makeRequest(
        headers: [String: String] = [:],
        maxResponseBytes: Int = 1_024
    ) throws -> HTTPRequest {
        let origin = try HTTPOrigin(httpsURL: URL(string: "https://api.example.com")!)
        return try HTTPRequest(
            method: .get,
            url: URL(string: "https://api.example.com/usage")!,
            allowedOrigin: origin,
            headers: headers,
            maxResponseBytes: maxResponseBytes
        )
    }
}

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let storage = HandlerStorage()

    static var handler: Handler? {
        get { storage.handler }
        set { storage.handler = newValue }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class HandlerStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var storedHandler: URLProtocolStub.Handler?

    var handler: URLProtocolStub.Handler? {
        get { lock.withLock { storedHandler } }
        set { lock.withLock { storedHandler = newValue } }
    }
}
