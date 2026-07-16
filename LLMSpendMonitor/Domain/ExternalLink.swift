import Foundation

struct ExternalLink: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Hashable, Sendable {
        case usage
        case billing
        case dashboard
        case status
    }

    let kind: Kind
    let url: URL
}
