import AppKit
import SwiftUI

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
        statusBarController = StatusBarController()
        statusBarController?.showOnboardingIfNeeded()
    }
}

private struct SettingsRootView: View {
    var body: some View {
        Form {
            LabeledContent("Menu bar metric") {
                Text("Today’s spend")
            }
            Text("Provider connections and refresh settings arrive in the next milestones.")
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 220)
        .navigationTitle("Settings")
        .accessibilityIdentifier("settings.root")
    }
}
