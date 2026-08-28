import AppKit
import SwiftUI

struct DashboardRootView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var dashboardViewModel: DashboardViewModel
    @StateObject private var customizeViewModel = CustomizeViewModel()
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
                    providers: customizeViewModel.items
                        .filter(\.isVisible)
                        .map(\.metadata),
                    moveProvider: { providerID, destinationID in
                        customizeViewModel.move(providerID, to: destinationID)
                    },
                    showConnections: appState.showConnections,
                    showCustomize: appState.showCustomize,
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
            case .customize:
                CustomizeProvidersView(
                    viewModel: customizeViewModel,
                    showDashboard: appState.showDashboard
                )
            }
        }
        .frame(width: 420, height: 640)
        .background {
            GlassSurface(cornerRadius: 18, prominence: .panel)
        }
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

            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 76, height: 76)
                .accessibilityHidden(true)

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
    let providers: [ProviderMetadata]
    let moveProvider: (ProviderID, ProviderID) -> Bool
    let showConnections: () -> Void
    let showCustomize: () -> Void
    let closePanel: () -> Void
    let quitApplication: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Spender")
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

            PeriodPicker(selection: $viewModel.selectedPeriod)

            SummaryCard(
                total: viewModel.trackedUSDTotal,
                breakdown: viewModel.trackedUSDBreakdown,
                dailySpend: viewModel.trackedUSDDailySpend,
                excludedProviderCount: viewModel.excludedOfficialCostProviderCount,
                showsDetails: viewModel.selectedPeriod == .thirtyDays
            )

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(providers) { provider in
                        ProviderCard(
                            metadata: provider,
                            snapshot: viewModel.snapshot(for: provider.id),
                            freshness: viewModel.providerFreshness(for: provider.id),
                            platformBalance: viewModel.platformBalance(for: provider.id),
                            synchronizeBalance: viewModel.canSynchronizePlatformBalance(for: provider.id) ? { balance in
                                await viewModel.synchronizePlatformBalance(
                                    providerID: provider.id,
                                    balance: balance
                                )
                            } : nil
                        )
                        .draggable(provider.id.rawValue)
                        .dropDestination(for: String.self) { values, _ in
                            guard
                                let rawValue = values.first,
                                let draggedProviderID = ProviderID(rawValue: rawValue)
                            else { return false }
                            return moveProvider(draggedProviderID, provider.id)
                        }
                        .help("Drag to reorder providers")
                    }

                    if providers.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "eye.slash")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text("No providers shown")
                                .font(.headline)
                            Button("Choose Providers", action: showCustomize)
                                .buttonStyle(.link)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        .accessibilityIdentifier("dashboard.noProviders")
                    }
                }
            }

            Menu("Options", systemImage: "ellipsis.circle") {
                Button("Customize", action: showCustomize)
                    .accessibilityIdentifier("options.customize")
                Button("Connections", action: showConnections)
                    .accessibilityIdentifier("options.connections")
                SettingsLink {
                    Text("Settings")
                }
                Divider()
                Button("Quit Spender", action: quitApplication)
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
