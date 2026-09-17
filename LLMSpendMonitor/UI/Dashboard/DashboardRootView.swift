import AppKit
import SwiftUI

struct DashboardRootView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var dashboardViewModel: DashboardViewModel
    @ObservedObject var settingsRequestRouter: SettingsRequestRouter
    @StateObject private var customizeViewModel = CustomizeViewModel()
    @Environment(\.openSettings) private var openSettings
    let closePanel: () -> Void
    let quitApplication: () -> Void
    var panelRequestDidChange: (MenuPanelRequest) -> Void = { _ in }

    @State private var dashboardHeight: CGFloat?
    @State private var onboardingHeight: CGFloat?

    var body: some View {
        Group {
            switch appState.destination {
            case .onboarding:
                OnboardingView(
                    heightDidChange: { onboardingHeight = $0 },
                    skip: appState.skipOnboarding,
                    connect: appState.showConnections,
                    close: closePanel
                )
            case .dashboard:
                DashboardView(
                    heightDidChange: { dashboardHeight = $0 },
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
        .frame(width: MenuPanelMetrics.width)
        .demoAppStorageIfNeeded()
        .background {
            GlassSurface(cornerRadius: 18, prominence: .panel)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityIdentifier("menu.panel")
        .onChange(of: settingsRequestRouter.requestCount) {
            openSettings()
        }
        .onAppear { panelRequestDidChange(panelRequest) }
        .onChange(of: panelRequest) { _, request in
            panelRequestDidChange(request)
        }
    }

    /// The dashboard and the onboarding screen size themselves; Connections and
    /// Customize are scrolling lists that keep the standing height.
    private var panelRequest: MenuPanelRequest {
        switch appState.destination {
        case .dashboard:
            MenuPanelRequest(
                screen: "dashboard",
                height: dashboardHeight ?? MenuPanelMetrics.defaultHeight,
                isMeasured: dashboardHeight != nil
            )
        case .onboarding:
            MenuPanelRequest(
                screen: "onboarding",
                height: onboardingHeight ?? MenuPanelMetrics.defaultHeight,
                isMeasured: onboardingHeight != nil
            )
        case .connections:
            MenuPanelRequest(
                screen: "connections",
                height: MenuPanelMetrics.defaultHeight,
                isMeasured: true
            )
        case .customize:
            MenuPanelRequest(
                screen: "customize",
                height: MenuPanelMetrics.defaultHeight,
                isMeasured: true
            )
        }
    }
}

private struct OnboardingView: View {
    let heightDidChange: (CGFloat) -> Void
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
        }
        .padding(24)
        // Sized to its own content: the screen is a short pitch and two buttons,
        // and stretching it to the dashboard's height only added empty room.
        .measuringPanelPart("onboarding")
        .onPreferenceChange(PanelPartHeights.self) { heights in
            if let height = heights["onboarding"] { heightDidChange(height) }
        }
        .onAppear { headingFocused = true }
    }
}

private struct DashboardView: View {
    let heightDidChange: (CGFloat) -> Void
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
                DashboardHeaderButton(
                    title: "Refresh",
                    systemImage: "arrow.clockwise",
                    isDisabled: viewModel.isRefreshing,
                    accessibilityIdentifier: "dashboard.refresh"
                ) {
                    Task { await viewModel.refresh(trigger: .manual) }
                }
                DashboardHeaderButton(
                    title: "Close",
                    systemImage: "xmark",
                    accessibilityIdentifier: "dashboard.close",
                    action: closePanel
                )
            }
            .measuringPanelPart("header")

            PeriodPicker(selection: $viewModel.selectedPeriod)
                .measuringPanelPart("picker")

            SummaryCard(
                total: viewModel.trackedUSDTotal,
                breakdown: viewModel.trackedUSDBreakdown,
                dailySpend: viewModel.trackedUSDDailySpend,
                excludedProviderCount: viewModel.excludedOfficialCostProviderCount,
                showsDetails: viewModel.selectedPeriod == .thirtyDays
            )
            .measuringPanelPart("summary")

            ScrollView {
                LazyVStack(spacing: MenuPanelMetrics.providerCardSpacing) {
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
                        .measuringPanelPart("card")
                        .draggable(provider.id.rawValue)
                        .dropDestination(for: String.self) { values, _ in
                            guard
                                let rawValue = values.first,
                                let draggedProviderID = ProviderID(rawValue: rawValue)
                            else { return false }
                            return moveProvider(draggedProviderID, provider.id)
                        }
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
                .measuringPanelPart("list")
            }
            // The list is the one row that gives way. It never grows past the
            // cap, and it yields height back when the summary grows on the
            // 30 Days tab, so a frozen panel still fits everything it must.
            .frame(maxHeight: listCap)

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
            .measuringPanelPart("options")
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityIdentifier("dashboard.root")
        .task { await viewModel.start() }
        .onPreferenceChange(PanelPartHeights.self) { heights in
            partHeights = heights
        }
        .onChange(of: desiredHeight) { _, height in
            heightDidChange(height)
        }
    }

    @State private var partHeights: [String: CGFloat] = [:]

    /// Three collapsed cards and the gaps between them — or fewer, when fewer
    /// providers are shown.
    private var listCap: CGFloat {
        let count = CGFloat(min(providers.count, MenuPanelMetrics.visibleProviderCap))
        guard count > 0, let card = partHeights["card"], card > 0 else {
            return .infinity
        }
        return card * count + MenuPanelMetrics.providerCardSpacing * (count - 1)
    }

    /// What the panel would have to be for this dashboard to fit exactly.
    ///
    /// Reported rather than measured off the panel itself: measuring the laid-out
    /// root would only ever return the height the panel already has.
    private var desiredHeight: CGFloat {
        let rows = ["header", "picker", "summary", "options"].compactMap { partHeights[$0] }
        guard rows.count == 4, let list = partHeights["list"] else {
            return MenuPanelMetrics.defaultHeight
        }
        return MenuPanelMetrics.chromeHeight + rows.reduce(0, +) + min(list, listCap)
    }
}

private struct DashboardHeaderButton: View {
    let title: String
    let systemImage: String
    var isDisabled = false
    let accessibilityIdentifier: String
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .frame(width: 28, height: 28)
            .contentShape(Circle())
            .background(
                Color.primary.opacity(isHovered && !isDisabled ? 0.08 : 0),
                in: Circle()
            )
            .disabled(isDisabled)
            .onHover { hovering in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                    isHovered = hovering
                }
            }
            .help(title)
            .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private extension View {
    /// Keeps the screenshot demo build from writing card-expansion state into
    /// the installed app's preferences.
    @ViewBuilder
    func demoAppStorageIfNeeded() -> some View {
#if DEBUG
        if let defaults = DemoLaunch.defaults {
            defaultAppStorage(defaults)
        } else {
            self
        }
#else
        self
#endif
    }
}

/// Size of the menu bar panel.
///
/// The width is fixed. The height follows what the dashboard actually has to
/// show — a person tracking two providers should not get a panel sized for
/// four — and stops at `visibleProviderCap` cards so the panel never grows into
/// a window. Past that the provider list scrolls.
enum MenuPanelMetrics {
    static let width: CGFloat = 420

    /// Used before the dashboard has measured itself, and by every other screen.
    static let defaultHeight: CGFloat = 640

    /// The tallest the provider list is allowed to get, in whole cards. A fourth
    /// card is not shown half-cut at the panel edge: it is scrolled to.
    static let visibleProviderCap = 3

    /// Everything the dashboard spends on itself rather than on content:
    /// `.padding(20)` top and bottom, plus the 16pt gaps between its five rows.
    /// Keep this in step with `DashboardView.body`.
    static let chromeHeight: CGFloat = 20 * 2 + 16 * 4

    /// Spacing between provider cards — `LazyVStack(spacing: 12)`.
    static let providerCardSpacing: CGFloat = 12

    private static let minHeight: CGFloat = 320
    private static let maxHeight: CGFloat = 900

    static func clamped(_ height: CGFloat) -> CGFloat {
        min(max(height, minHeight), maxHeight)
    }

    /// A height the demo build is told to use regardless of content, so a
    /// screenshot can be framed deliberately. Never set in a shipping build.
    static var forcedHeight: CGFloat? {
#if DEBUG
        if
            DemoLaunch.isEnabled,
            let raw = ProcessInfo.processInfo.environment["SPENDER_DEMO_PANEL_HEIGHT"],
            let requested = Double(raw),
            requested >= 320,
            requested <= 1200
        {
            return CGFloat(requested)
        }
#endif
        return nil
    }
}

/// The panel size one screen is asking for.
///
/// `screen` is the identity of what is on display, not a label: the controller
/// resizes when the screen changes and holds still otherwise, so the panel never
/// jumps under the pointer while someone is reading it.
struct MenuPanelRequest: Equatable {
    var screen: String
    var height: CGFloat
    /// False while the screen is still a placeholder — the panel opens before
    /// SwiftUI has laid anything out, and the first height it offers is a guess.
    var isMeasured: Bool
}

/// Heights of the dashboard's individual rows, keyed by name.
///
/// Every part measured here is intrinsically sized, so a reading never depends on
/// how tall the panel currently is — which is what keeps resizing from feeding
/// back into itself. Duplicate keys reduce to the smallest, so the per-card key
/// yields a collapsed card even when one card is expanded.
private struct PanelPartHeights: PreferenceKey {
    static var defaultValue: [String: CGFloat] { [:] }

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { min($0, $1) }
    }
}

private extension View {
    func measuringPanelPart(_ name: String) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: PanelPartHeights.self,
                    value: [name: proxy.size.height]
                )
            }
        }
    }
}
