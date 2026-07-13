import SwiftUI

struct DashboardRootView: View {
    @ObservedObject var appState: AppState
    let closePanel: () -> Void
    let quitApplication: () -> Void

    var body: some View {
        Group {
            switch appState.destination {
            case .onboarding:
                OnboardingView(
                    skip: appState.skipOnboarding,
                    connect: appState.showConnections,
                    close: closePanel
                )
            case .dashboard:
                DashboardView(
                    showConnections: appState.showConnections,
                    closePanel: closePanel,
                    quitApplication: quitApplication
                )
            case .connections:
                ConnectionsView(showDashboard: appState.showDashboard)
            }
        }
        .frame(width: 380, height: 560)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityIdentifier("menu.panel")
    }
}

private struct OnboardingView: View {
    let skip: () -> Void
    let connect: () -> Void
    let close: () -> Void

    @AccessibilityFocusState private var headingFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Spacer()
                Button("Close", systemImage: "xmark", action: close)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("onboarding.close")
            }

            Spacer()

            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 44))
                .foregroundStyle(.tint)

            Text("Monitor your LLM API spend")
                .font(.title.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($headingFocused)
                .accessibilityIdentifier("onboarding.heading")

            Text("Connect providers to see official costs, tokens, and balances in one private menu bar utility.")
                .foregroundStyle(.secondary)

            Button("Connect Provider", action: connect)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("onboarding.connect")

            Button("Skip for now", action: skip)
                .buttonStyle(.link)
                .accessibilityIdentifier("onboarding.skip")

            Spacer()
        }
        .padding(24)
        .onAppear { headingFocused = true }
    }
}

private struct DashboardView: View {
    let showConnections: () -> Void
    let closePanel: () -> Void
    let quitApplication: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("LLM Spend")
                    .font(.title2.bold())
                Spacer()
                Button("Close", systemImage: "xmark", action: closePanel)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
            }

            Picker("Period", selection: .constant(0)) {
                Text("Today").tag(0)
                Text("Yesterday").tag(1)
                Text("30 Days").tag(2)
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 6) {
                Text("Official spend")
                    .foregroundStyle(.secondary)
                Text("$0.00")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                Text("Connect a provider to load official data.")
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))

            Spacer()

            Menu("Options", systemImage: "ellipsis.circle") {
                Button("Connections", action: showConnections)
                    .accessibilityIdentifier("options.connections")
                SettingsLink {
                    Text("Settings")
                }
                Divider()
                Button("Quit LLM Spend Monitor", action: quitApplication)
                    .keyboardShortcut("q")
                    .accessibilityIdentifier("options.quit")
            }
            .menuStyle(.borderlessButton)
            .accessibilityIdentifier("options.menu")
        }
        .padding(20)
        .accessibilityIdentifier("dashboard.root")
    }
}

private struct ConnectionsView: View {
    let showDashboard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Button("Back", systemImage: "chevron.left", action: showDashboard)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("connections.back")
                Text("Connections")
                    .font(.title2.bold())
            }

            Text("Provider credentials are added in the next milestone.")
                .foregroundStyle(.secondary)

            ForEach(["OpenAI", "Anthropic", "Gemini", "DeepSeek"], id: \.self) { provider in
                HStack {
                    Text(provider)
                    Spacer()
                    Text("Not connected")
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            }

            Spacer()
        }
        .padding(20)
        .accessibilityIdentifier("connections.root")
    }
}
