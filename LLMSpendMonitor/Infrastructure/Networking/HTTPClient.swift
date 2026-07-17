import Foundation

enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

struct HTTPOrigin: Equatable, Sendable {
    let host: String
    let port: Int

    init(httpsURL url: URL) throws {
        guard
            url.scheme?.lowercased() == "https",
            let host = url.host?.lowercased(),
            !host.isEmpty,
            url.user == nil,
            url.password == nil
        else {
            throw HTTPClientError.insecureURL
        }

        self.host = host
        port = url.port ?? 443
    }

    func contains(_ url: URL) -> Bool {
        guard let candidate = try? HTTPOrigin(httpsURL: url) else { return false }
        return candidate == self
    }
}

struct HTTPRequest: Sendable {
    let method: HTTPMethod
    let url: URL
    let allowedOrigin: HTTPOrigin
    let headers: [String: String]
    let body: Data?
    let timeout: TimeInterval
    let maxResponseBytes: Int

    init(
        method: HTTPMethod,
        url: URL,
        allowedOrigin: HTTPOrigin,
        headers: [String: String] = [:],
        body: Data? = nil,
        timeout: TimeInterval = 30,
        maxResponseBytes: Int = 2 * 1_024 * 1_024
    ) throws {
        guard allowedOrigin.contains(url) else {
            throw url.scheme?.lowercased() == "https"
                ? HTTPClientError.disallowedOrigin
                : HTTPClientError.insecureURL
        }
        guard
            timeout > 0,
            maxResponseBytes > 0,
            headers.allSatisfy({ !$0.key.contains("\r") && !$0.key.contains("\n")
                && !$0.value.contains("\r") && !$0.value.contains("\n") })
        else {
            throw HTTPClientError.invalidRequest
        }

        self.method = method
        self.url = url
        self.allowedOrigin = allowedOrigin
        self.headers = headers
        self.body = body
        self.timeout = timeout
        self.maxResponseBytes = maxResponseBytes
    }
}

struct HTTPResponse: Equatable, Sendable {
    let statusCode: Int
    let headers: [String: String]
    let body: Data

    func header(named name: String) -> String? {
        headers[name.lowercased()]
    }
}

enum HTTPClientError: Error, Equatable, Sendable {
    case insecureURL
    case disallowedOrigin
    case invalidRequest
    case invalidResponse
    case responseTooLarge(limit: Int)
    case crossOriginRedirect
    case httpStatus(HTTPResponse)
    case transport(URLError.Code)
    case cancelled
}

protocol HTTPClient: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

struct HTTPRedirectPolicy: Sendable {
    let allowedOrigin: HTTPOrigin
    let originalHeaders: [String: String]

    func approvedRequest(for redirect: URLRequest) -> URLRequest? {
        guard let url = redirect.url, allowedOrigin.contains(url) else { return nil }

        var approved = redirect
        for (name, value) in originalHeaders {
            approved.setValue(value, forHTTPHeaderField: name)
        }
        return approved
    }
}
