import Foundation

@MainActor
final class AppState: ObservableObject {
    enum Destination: Equatable, Sendable {
        case onboarding
        case dashboard
        case connections
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
}
