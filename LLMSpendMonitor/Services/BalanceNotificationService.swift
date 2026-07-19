import Foundation
import UserNotifications

enum BalanceAlertLevel: String, Equatable, Sendable {
    case warning
    case critical
}

struct BalanceAlert: Equatable, Sendable {
    let identifier: String
    let providerID: ProviderID
    let level: BalanceAlertLevel
    let title: String
    let body: String
}

protocol BalanceNotificationPreferenceStoring: Sendable {
    func isEnabled() async -> Bool
    func setEnabled(_ enabled: Bool) async
}

protocol BalanceNotificationDeliveryStoring: Sendable {
    func contains(_ identifier: String) async -> Bool
    func insert(_ identifier: String) async
}

protocol BalanceNotificationClient: Sendable {
    func requestAuthorization() async throws -> Bool
    func deliver(_ alert: BalanceAlert) async throws
}

protocol BalanceNotificationHandling: Sendable {
    func evaluate(_ balances: [ProviderID: PlatformBalanceStatus]) async
}

actor BalanceNotificationService {
    static let shared: BalanceNotificationService = {
        let store = UserDefaultsBalanceNotificationStore()
        return BalanceNotificationService(
            preferences: store,
            deliveries: store,
            client: SystemBalanceNotificationClient()
        )
    }()

    private let preferences: any BalanceNotificationPreferenceStoring
    private let deliveries: any BalanceNotificationDeliveryStoring
    private let client: any BalanceNotificationClient
    private var latestBalances: [ProviderID: PlatformBalanceStatus] = [:]
    private var inFlightIdentifiers: Set<String> = []

    init(
        preferences: any BalanceNotificationPreferenceStoring,
        deliveries: any BalanceNotificationDeliveryStoring,
        client: any BalanceNotificationClient
    ) {
        self.preferences = preferences
        self.deliveries = deliveries
        self.client = client
    }

    func isEnabled() async -> Bool {
        await preferences.isEnabled()
    }

    @discardableResult
    func setEnabled(_ enabled: Bool) async -> Bool {
        guard enabled else {
            await preferences.setEnabled(false)
            return false
        }

        do {
            let granted = try await client.requestAuthorization()
            await preferences.setEnabled(granted)
            if granted {
                await deliverEligibleAlerts(in: latestBalances)
            }
            return granted
        } catch {
            await preferences.setEnabled(false)
            return false
        }
    }

    func evaluate(_ balances: [ProviderID: PlatformBalanceStatus]) async {
        latestBalances = balances
        guard await preferences.isEnabled() else { return }
        await deliverEligibleAlerts(in: balances)
    }

    private func deliverEligibleAlerts(
        in balances: [ProviderID: PlatformBalanceStatus]
    ) async {
        for providerID in balances.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard
                let balance = balances[providerID],
                balance.automaticallyDeductsSpend,
                balance.calibratedBalance.amount > 0,
                balance.calibratedBalance.currencyCode == balance.remaining.currencyCode,
                let level = alertLevel(for: balance)
            else { continue }

            let alert = makeAlert(providerID: providerID, balance: balance, level: level)
            guard !inFlightIdentifiers.contains(alert.identifier) else { continue }
            let wasDelivered = await deliveries.contains(alert.identifier)
            guard
                !wasDelivered,
                !inFlightIdentifiers.contains(alert.identifier)
            else { continue }
            inFlightIdentifiers.insert(alert.identifier)

            do {
                try await client.deliver(alert)
                await deliveries.insert(alert.identifier)
            } catch {
                // A later refresh may retry a transient delivery failure.
            }
            inFlightIdentifiers.remove(alert.identifier)
        }
    }

    private func alertLevel(for balance: PlatformBalanceStatus) -> BalanceAlertLevel? {
        let ratio = balance.remaining.amount / balance.calibratedBalance.amount
        if ratio <= Decimal(string: "0.05")! {
            return .critical
        }
        if ratio <= Decimal(string: "0.20")! {
            return .warning
        }
        return nil
    }

    private func makeAlert(
        providerID: ProviderID,
        balance: PlatformBalanceStatus,
        level: BalanceAlertLevel
    ) -> BalanceAlert {
        let calibrationID = Int64(balance.synchronizedAt.timeIntervalSince1970 * 1_000)
        let providerName = ProviderRegistry.metadata(for: providerID)?.displayName ?? providerID.rawValue
        let percent = NSDecimalNumber(
            decimal: balance.remaining.amount / balance.calibratedBalance.amount * 100
        ).intValue
        let remaining = Self.format(balance.remaining)

        return BalanceAlert(
            identifier: "balance.\(providerID.rawValue).\(calibrationID).\(level.rawValue)",
            providerID: providerID,
            level: level,
            title: level == .critical
                ? "\(providerName) balance is almost exhausted"
                : "\(providerName) balance is running low",
            body: "\(remaining) remains (\(percent)% of the last calibration). Open Billing and recalibrate after topping up."
        )
    }

    private static func format(_ money: Money) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .currency
        formatter.currencyCode = money.currencyCode
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: money.amount))
            ?? "\(money.currencyCode) \(money.amount)"
    }
}

extension BalanceNotificationService: BalanceNotificationHandling {}

private actor UserDefaultsBalanceNotificationStore:
    BalanceNotificationPreferenceStoring,
    BalanceNotificationDeliveryStoring {
    private let defaults: UserDefaults
    private let enabledKey = "balance-notifications-enabled-v1"
    private let deliveriesKey = "balance-notification-deliveries-v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func isEnabled() -> Bool {
        defaults.bool(forKey: enabledKey)
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: enabledKey)
    }

    func contains(_ identifier: String) -> Bool {
        deliveredIdentifiers().contains(identifier)
    }

    func insert(_ identifier: String) {
        var identifiers = deliveredIdentifiers()
        identifiers.insert(identifier)
        defaults.set(Array(identifiers).sorted(), forKey: deliveriesKey)
    }

    private func deliveredIdentifiers() -> Set<String> {
        Set(defaults.stringArray(forKey: deliveriesKey) ?? [])
    }
}

private struct SystemBalanceNotificationClient: BalanceNotificationClient {
    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    func deliver(_ alert: BalanceAlert) async throws {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        content.userInfo = ["providerID": alert.providerID.rawValue]

        let request = UNNotificationRequest(
            identifier: alert.identifier,
            content: content,
            trigger: nil
        )
        try await UNUserNotificationCenter.current().add(request)
    }
}
