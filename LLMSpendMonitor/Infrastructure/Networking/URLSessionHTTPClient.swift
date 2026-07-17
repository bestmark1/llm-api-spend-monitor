import Foundation

final class URLSessionHTTPClient: HTTPClient, @unchecked Sendable {
    private let baseConfiguration: URLSessionConfiguration

    init() {
        baseConfiguration = .ephemeral
    }

    init(configuration: URLSessionConfiguration) {
        baseConfiguration = configuration
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let configuration = (baseConfiguration.copy() as? URLSessionConfiguration) ?? .ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = request.timeout

        var urlRequest = URLRequest(
            url: request.url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: request.timeout
        )
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        let delegate = HTTPRequestDelegate(
            maxResponseBytes: request.maxResponseBytes,
            redirectPolicy: HTTPRedirectPolicy(
                allowedOrigin: request.allowedOrigin,
                originalHeaders: request.headers
            )
        )
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        let session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: delegateQueue
        )
        defer { session.invalidateAndCancel() }

        let response = try await delegate.perform(session: session, request: urlRequest)
        guard (200...299).contains(response.statusCode) else {
            throw HTTPClientError.httpStatus(response)
        }
        return response
    }
}

private final class HTTPRequestDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let maxResponseBytes: Int
    private let redirectPolicy: HTTPRedirectPolicy
    private let lock = NSLock()

    private var continuation: CheckedContinuation<HTTPResponse, any Error>?
    private var task: URLSessionDataTask?
    private var response: HTTPURLResponse?
    private var body = Data()
    private var redirectRejected = false
    private var cancellationRequested = false
    private var completed = false

    init(maxResponseBytes: Int, redirectPolicy: HTTPRedirectPolicy) {
        self.maxResponseBytes = maxResponseBytes
        self.redirectPolicy = redirectPolicy
    }

    func perform(session: URLSession, request: URLRequest) async throws -> HTTPResponse {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let dataTask = session.dataTask(with: request)
                let shouldCancel = lock.withLock {
                    self.continuation = continuation
                    task = dataTask
                    return cancellationRequested
                }
                dataTask.resume()
                if shouldCancel { dataTask.cancel() }
            }
        } onCancel: {
            self.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        let approved = redirectPolicy.approvedRequest(for: request)
        if approved == nil {
            lock.withLock { redirectRejected = true }
        }
        completionHandler(approved)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let httpResponse = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            dataTask.cancel()
            finish(.failure(HTTPClientError.invalidResponse))
            return
        }

        if response.expectedContentLength > Int64(maxResponseBytes) {
            completionHandler(.cancel)
            dataTask.cancel()
            finish(.failure(HTTPClientError.responseTooLarge(limit: maxResponseBytes)))
            return
        }

        lock.withLock { self.response = httpResponse }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let exceededLimit = lock.withLock {
            guard !completed else { return false }
            guard data.count <= maxResponseBytes - body.count else { return true }
            body.append(data)
            return false
        }

        if exceededLimit {
            dataTask.cancel()
            finish(.failure(HTTPClientError.responseTooLarge(limit: maxResponseBytes)))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        let state = lock.withLock {
            (
                redirectRejected,
                cancellationRequested,
                response,
                body
            )
        }

        if state.0 {
            finish(.failure(HTTPClientError.crossOriginRedirect))
            return
        }
        if state.1 {
            finish(.failure(HTTPClientError.cancelled))
            return
        }
        if let error {
            let code = (error as? URLError)?.code ?? .unknown
            finish(.failure(HTTPClientError.transport(code)))
            return
        }
        guard let response = state.2 else {
            finish(.failure(HTTPClientError.invalidResponse))
            return
        }

        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, element in
            result[String(describing: element.key).lowercased()] = String(describing: element.value)
        }
        finish(.success(HTTPResponse(statusCode: response.statusCode, headers: headers, body: state.3)))
    }

    private func cancel() {
        let currentTask = lock.withLock {
            cancellationRequested = true
            return task
        }
        currentTask?.cancel()
    }

    private func finish(_ result: Result<HTTPResponse, any Error>) {
        let pendingContinuation = lock.withLock {
            guard !completed else { return nil as CheckedContinuation<HTTPResponse, any Error>? }
            completed = true
            task = nil
            let value = continuation
            continuation = nil
            return value
        }
        pendingContinuation?.resume(with: result)
    }
}
