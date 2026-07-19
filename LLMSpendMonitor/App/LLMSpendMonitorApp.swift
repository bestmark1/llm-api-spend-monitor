import AppKit
import SwiftUI
import UserNotifications

@main
struct LLMSpendMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsRootView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        statusBarController = StatusBarController()
        statusBarController?.showOnboardingIfNeeded()
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

@MainActor
final class NotificationSettingsViewModel: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var isWorking = false
    @Published private(set) var permissionDenied = false

    private let service: any BalanceNotificationSettingsHandling

    init(
        service: any BalanceNotificationSettingsHandling = BalanceNotificationService.shared
    ) {
        self.service = service
    }

    func load() async {
        isEnabled = await service.isEnabled()
    }

    func setEnabled(_ requested: Bool) async {
        isWorking = true
        let resultingState = await service.setEnabled(requested)
        isEnabled = resultingState
        permissionDenied = requested && !resultingState
        isWorking = false
    }
}

private struct SettingsRootView: View {
    @StateObject private var notifications = NotificationSettingsViewModel()

    var body: some View {
        Form {
            Section("General") {
                LabeledContent("Menu bar metric") {
                    Text("Today’s spend")
                }
            }

            Section("Notifications") {
                Toggle(
                    "Low balance alerts",
                    isOn: Binding(
                        get: { notifications.isEnabled },
                        set: { requested in
                            Task { await notifications.setEnabled(requested) }
                        }
                    )
                )
                .disabled(notifications.isWorking)
                .accessibilityIdentifier("settings.balanceNotifications")

                Text("Warn once at 20% remaining and again at 5% for each balance calibration.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if notifications.permissionDenied {
                    Text("Notifications are disabled in macOS System Settings.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("settings.notificationPermissionDenied")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 300)
        .navigationTitle("Settings")
        .accessibilityIdentifier("settings.root")
        .task { await notifications.load() }
    }
}
