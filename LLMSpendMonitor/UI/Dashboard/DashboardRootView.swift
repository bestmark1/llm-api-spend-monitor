import SwiftUI

struct DashboardRootView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var dashboardViewModel: DashboardViewModel
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
                    viewModel: dashboardViewModel,
                    showConnections: appState.showConnections,
                    closePanel: closePanel,
                    quitApplication: quitApplication
                )
            case .connections:
                ConnectionsView(
                    showDashboard: appState.showDashboard,
                    credentialDidChange: { providerID in
                        Task { await dashboardViewModel.credentialDidChange(providerID) }
                    }
                )
            }
        }
        .frame(width: 420, height: 640)
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
    @ObservedObject var viewModel: DashboardViewModel
    let showConnections: () -> Void
    let closePanel: () -> Void
    let quitApplication: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("LLM Spend")
                    .font(.title2.bold())
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await viewModel.refresh(trigger: .manual) }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .disabled(viewModel.isRefreshing)
                .accessibilityIdentifier("dashboard.refresh")
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
                Text(MetricFormatting.money(viewModel.officialUSDTotal))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                Text("Complete official USD reports only")
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(ProviderRegistry.all) { provider in
                        ProviderCard(metadata: provider, snapshot: viewModel.snapshots[provider.id])
                    }
                }
            }

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
        .task { await viewModel.start() }
    }
}
