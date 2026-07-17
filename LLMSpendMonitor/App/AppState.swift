import Foundation

@MainActor
final class AppState: ObservableObject {
    enum Destination: Equatable, Sendable {
        case onboarding
        case dashboard
        case connections
        case customize
    }

    @Published private(set) var destination: Destination = .onboarding

    func skipOnboarding() {
        destination = .dashboard
    }

    func showConnections() {
        destination = .connections
    }

    func showDashboard() {
        destination = .dashboard
    }

    func showCustomize() {
        destination = .customize
    }
}
