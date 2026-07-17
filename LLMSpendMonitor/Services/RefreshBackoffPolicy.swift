import Foundation

struct RefreshBackoffPolicy: Sendable {
    let baseDelay: TimeInterval
    let maximumDelay: TimeInterval
    let jitter: @Sendable () -> Double

    init(
        baseDelay: TimeInterval = 30,
        maximumDelay: TimeInterval = 15 * 60,
        jitter: @escaping @Sendable () -> Double = { Double.random(in: 0...1) }
    ) {
        precondition(baseDelay > 0 && maximumDelay >= baseDelay)
        self.baseDelay = baseDelay
        self.maximumDelay = maximumDelay
        self.jitter = jitter
    }

    func delay(consecutiveFailureCount: Int, retryAfter: TimeInterval?) -> TimeInterval {
        if let retryAfter {
            return max(0, retryAfter)
        }

        let exponent = min(max(0, consecutiveFailureCount - 1), 20)
        let exponential = min(maximumDelay, baseDelay * pow(2, Double(exponent)))
        let normalizedJitter = min(max(jitter(), 0), 1)
        return exponential * (0.8 + normalizedJitter * 0.4)
    }
}
