import AppKit
import Combine
import SwiftUI

enum SpenderMenuBarIcon {
    static let size = NSSize(width: 18, height: 18)

    static func make() -> NSImage {
        let image = NSImage(size: size, flipped: true) { _ in
            NSColor.black.setFill()

            NSBezierPath(
                roundedRect: NSRect(x: 6.2, y: 2, width: 5.6, height: 5.2),
                xRadius: 1.2,
                yRadius: 1.2
            ).fill()

            let pocket = NSBezierPath()
            pocket.move(to: NSPoint(x: 2.5, y: 6.4))
            pocket.curve(
                to: NSPoint(x: 9, y: 8.4),
                controlPoint1: NSPoint(x: 4.1, y: 6.4),
                controlPoint2: NSPoint(x: 5.5, y: 8.4)
            )
            pocket.curve(
                to: NSPoint(x: 15.5, y: 6.4),
                controlPoint1: NSPoint(x: 12.5, y: 8.4),
                controlPoint2: NSPoint(x: 13.9, y: 6.4)
            )
            pocket.line(to: NSPoint(x: 15.5, y: 14.4))
            pocket.curve(
                to: NSPoint(x: 14.1, y: 15.8),
                controlPoint1: NSPoint(x: 15.5, y: 15.2),
                controlPoint2: NSPoint(x: 14.9, y: 15.8)
            )
            pocket.line(to: NSPoint(x: 3.9, y: 15.8))
            pocket.curve(
                to: NSPoint(x: 2.5, y: 14.4),
                controlPoint1: NSPoint(x: 3.1, y: 15.8),
                controlPoint2: NSPoint(x: 2.5, y: 15.2)
            )
            pocket.close()
            pocket.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}

@MainActor
final class RefreshScheduler {
    typealias Sleep = @Sendable (TimeInterval) async throws -> Void
    typealias Refresh = @MainActor @Sendable (RefreshTrigger) async -> Void

    private let interval: TimeInterval
    private let sleep: Sleep
    private let refresh: Refresh
    private var periodicTask: Task<Void, Never>?

    init(
        interval: TimeInterval = 60,
        sleep: @escaping Sleep = { interval in
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        },
        refresh: @escaping Refresh
    ) {
        self.interval = interval
        self.sleep = sleep
        self.refresh = refresh
    }

    deinit {
        periodicTask?.cancel()
    }

    func start() {
        guard periodicTask == nil else { return }
        let interval = interval
        let sleep = sleep
        let refresh = refresh

        periodicTask = Task {
            while !Task.isCancelled {
                do {
                    try await sleep(interval)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await refresh(.timer)
            }
        }
    }

    func stop() {
        periodicTask?.cancel()
        periodicTask = nil
    }

    func refreshNow(for trigger: RefreshTrigger) async {
        await refresh(trigger)
    }
}

@MainActor
protocol MenuPanelPresenting: AnyObject {
    var isVisible: Bool { get }
    func show()
    func hide()
    func toggle()
}

enum StatusItemClick: Equatable {
    case primary
    case contextMenu

    init(eventType: NSEvent.EventType?) {
        self = eventType == .rightMouseDown || eventType == .rightMouseUp
            ? .contextMenu
            : .primary
    }
}

@MainActor
final class SettingsRequestRouter: ObservableObject {
    @Published private(set) var requestCount = 0

    func openSettings() {
        requestCount += 1
    }
}

enum StatusBarMenuAction: Int, CaseIterable, Equatable {
    case customize
    case connections
    case settings
    case quit

    var title: String {
        switch self {
        case .customize: "Customize"
        case .connections: "Connections"
        case .settings: "Settings"
        case .quit: "Quit Spender"
        }
    }

    var keyEquivalent: String {
        self == .quit ? "q" : ""
    }
}

@MainActor
final class StatusBarInteractionController: NSObject {
    private let appState: AppState
    private let panelPresenter: any MenuPanelPresenting
    private let openSettings: () -> Void
    private let quitApplication: () -> Void

    init(
        appState: AppState,
        panelPresenter: any MenuPanelPresenting,
        openSettings: @escaping () -> Void,
        quitApplication: @escaping () -> Void
    ) {
        self.appState = appState
        self.panelPresenter = panelPresenter
        self.openSettings = openSettings
        self.quitApplication = quitApplication
    }

    func handle(_ click: StatusItemClick, showContextMenu: () -> Void) {
        switch click {
        case .primary:
            panelPresenter.toggle()
        case .contextMenu:
            showContextMenu()
        }
    }

    func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for action in StatusBarMenuAction.allCases {
            let item = NSMenuItem(
                title: action.title,
                action: #selector(performMenuItem(_:)),
                keyEquivalent: action.keyEquivalent
            )
            item.target = self
            item.tag = action.rawValue
            item.isEnabled = true
            menu.addItem(item)
        }
        return menu
    }

    @objc func performMenuItem(_ sender: NSMenuItem) {
        guard let action = StatusBarMenuAction(rawValue: sender.tag) else { return }
        perform(action)
    }

    func perform(_ action: StatusBarMenuAction) {
        switch action {
        case .customize:
            appState.showCustomize()
            panelPresenter.show()
        case .connections:
            appState.showConnections()
            panelPresenter.show()
        case .settings:
            openSettings()
        case .quit:
            quitApplication()
        }
    }
}

@MainActor
final class StatusBarController: NSObject {
    private let appState: AppState
    private let dashboardViewModel: DashboardViewModel
    private let statusItem: NSStatusItem
    private let panelPresenter: MenuPanelPresenter
    private let refreshScheduler: RefreshScheduler
    private let settingsRequestRouter: SettingsRequestRouter
    private let interactionController: StatusBarInteractionController
    private lazy var contextMenu = interactionController.makeContextMenu()
    private var cancellables: Set<AnyCancellable> = []

    init(
        appState: AppState = AppState(),
        dashboardViewModel: DashboardViewModel = .launchConfigured(),
        statusItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    ) {
#if DEBUG
        if DebugLaunchOptions.resetProviderCardExpansion {
            for providerID in ProviderID.allCases {
                UserDefaults.standard.removeObject(
                    forKey: "provider.card.\(providerID.rawValue).expanded"
                )
            }
        }
#endif
        let quitApplication = { NSApplication.shared.terminate(nil) }
        let settingsRequestRouter = SettingsRequestRouter()
        let panelPresenter = MenuPanelPresenter(
            appState: appState,
            dashboardViewModel: dashboardViewModel,
            settingsRequestRouter: settingsRequestRouter,
            quitApplication: quitApplication
        )

        self.appState = appState
        self.dashboardViewModel = dashboardViewModel
        self.statusItem = statusItem
        self.panelPresenter = panelPresenter
        self.settingsRequestRouter = settingsRequestRouter
        refreshScheduler = RefreshScheduler { [weak dashboardViewModel] trigger in
            await dashboardViewModel?.refresh(trigger: trigger)
        }
        interactionController = StatusBarInteractionController(
            appState: appState,
            panelPresenter: panelPresenter,
            openSettings: {
                NSApplication.shared.activate(ignoringOtherApps: true)
                settingsRequestRouter.openSettings()
            },
            quitApplication: quitApplication
        )
        super.init()

        configureStatusItem()
        observeDashboardMetric()
        panelPresenter.anchorProvider = { [weak statusItem] in
            statusItem?.button
        }
        panelPresenter.didShow = { [weak self] in
            self?.requestRefresh(for: .panelOpen)
        }
        observeWorkspaceLifecycle()
        refreshScheduler.start()
        Task { await dashboardViewModel.start() }
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func showOnboardingIfNeeded() {
#if DEBUG
        if DebugLaunchOptions.dashboardPreview {
            appState.skipOnboarding()
            panelPresenter.show()
            return
        }
#endif
        guard appState.destination == .onboarding else { return }
        panelPresenter.show()
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        interactionController.handle(
            StatusItemClick(eventType: NSApplication.shared.currentEvent?.type)
        ) { [weak self, weak sender] in
            guard let self, let sender else { return }
            contextMenu.popUp(
                positioning: contextMenu.items.first,
                at: NSPoint(x: sender.bounds.midX, y: sender.bounds.minY),
                in: sender
            )
        }
    }

    @objc private func workspaceDidWake(_ notification: Notification) {
        requestRefresh(for: .wake)
    }

    @objc private func workspaceSessionDidBecomeActive(_ notification: Notification) {
        requestRefresh(for: .unlock)
    }

    private func requestRefresh(for trigger: RefreshTrigger) {
        Task { [weak self] in
            await self?.refreshScheduler.refreshNow(for: trigger)
        }
    }

    private func observeWorkspaceLifecycle() {
        let notificationCenter = NSWorkspace.shared.notificationCenter
        notificationCenter.addObserver(
            self,
            selector: #selector(workspaceDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(workspaceSessionDidBecomeActive(_:)),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        button.image = SpenderMenuBarIcon.make()
        button.imagePosition = .imageLeading
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateDashboardMetric()
    }

    private func observeDashboardMetric() {
        dashboardViewModel.$snapshots
            .sink { [weak self] _ in self?.updateDashboardMetric() }
            .store(in: &cancellables)
    }

    private func updateDashboardMetric() {
        guard let button = statusItem.button else { return }
        let total = dashboardViewModel.menuBarUSDTotal
        button.title = MenuBarLabelView.metricText(for: total)
        button.setAccessibilityLabel(MenuBarLabelView.accessibilityLabel(for: total))
    }
}

@MainActor
final class MenuPanelPresenter: NSObject, MenuPanelPresenting {
    var anchorProvider: (() -> NSStatusBarButton?)?
    var didShow: (() -> Void)?

    private let panel: MenuBarPanel
    private var outsideClickMonitor: GlobalMouseMonitor?

    var isVisible: Bool { panel.isVisible }

    init(
        appState: AppState,
        dashboardViewModel: DashboardViewModel,
        settingsRequestRouter: SettingsRequestRouter,
        quitApplication: @escaping () -> Void
    ) {
        panel = MenuBarPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 640),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        super.init()

        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.contentView = NSHostingView(
            rootView: DashboardRootView(
                appState: appState,
                dashboardViewModel: dashboardViewModel,
                settingsRequestRouter: settingsRequestRouter,
                closePanel: { [weak self] in self?.hide() },
                quitApplication: quitApplication
            )
        )
        outsideClickMonitor = GlobalMouseMonitor(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard self?.isVisible == true else { return }
                self?.hide()
            }
        }
    }

    func show() {
        positionPanel()
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        didShow?()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    private func positionPanel() {
        guard
            let button = anchorProvider?(),
            let buttonWindow = button.window
        else {
            centerBelowMenuBar()
            return
        }

        let buttonRectInWindow = button.convert(button.bounds, to: nil)
        let buttonRectOnScreen = buttonWindow.convertToScreen(buttonRectInWindow)
        let panelSize = panel.frame.size
        let origin = NSPoint(
            x: buttonRectOnScreen.midX - panelSize.width / 2,
            y: buttonRectOnScreen.minY - panelSize.height - 8
        )
        panel.setFrameOrigin(constrainedOrigin(origin, size: panelSize, screen: buttonWindow.screen))
    }

    private func centerBelowMenuBar() {
        guard let screen = NSScreen.main else { return }
        let panelSize = panel.frame.size
        let origin = NSPoint(
            x: screen.visibleFrame.midX - panelSize.width / 2,
            y: screen.visibleFrame.maxY - panelSize.height - 8
        )
        panel.setFrameOrigin(origin)
    }

    private func constrainedOrigin(_ origin: NSPoint, size: NSSize, screen: NSScreen?) -> NSPoint {
        guard let visibleFrame = screen?.visibleFrame else { return origin }
        return NSPoint(
            x: min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - size.width),
            y: max(origin.y, visibleFrame.minY)
        )
    }
}

private final class GlobalMouseMonitor: @unchecked Sendable {
    private let token: Any?

    init(matching mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> Void) {
        token = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
    }

    deinit {
        if let token {
            NSEvent.removeMonitor(token)
        }
    }
}

#if DEBUG
private enum DebugLaunchOptions {
    static let dashboardPreview = ProcessInfo.processInfo.arguments.contains("--dashboard-preview")
    static let resetProviderCardExpansion = ProcessInfo.processInfo.arguments.contains(
        "--reset-provider-card-expansion"
    )
}
#endif

final class MenuBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

}
