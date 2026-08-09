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

@MainActor
final class StatusBarController: NSObject {
    private let appState: AppState
    private let dashboardViewModel: DashboardViewModel
    private let statusItem: NSStatusItem
    private let panelPresenter: MenuPanelPresenter
    private let refreshScheduler: RefreshScheduler
    private var cancellables: Set<AnyCancellable> = []

    init(
        appState: AppState = AppState(),
        dashboardViewModel: DashboardViewModel = DashboardViewModel(),
        statusItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    ) {
        self.appState = appState
        self.dashboardViewModel = dashboardViewModel
        self.statusItem = statusItem
        panelPresenter = MenuPanelPresenter(appState: appState, dashboardViewModel: dashboardViewModel)
        refreshScheduler = RefreshScheduler { [weak dashboardViewModel] trigger in
            await dashboardViewModel?.refresh(trigger: trigger)
        }
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

    @objc private func togglePanel() {
        panelPresenter.toggle()
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
        button.action = #selector(togglePanel)
        button.sendAction(on: [.leftMouseUp])
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

    var isVisible: Bool { panel.isVisible }

    init(appState: AppState, dashboardViewModel: DashboardViewModel) {
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
                closePanel: { [weak self] in self?.hide() },
                quitApplication: { NSApplication.shared.terminate(nil) }
            )
        )
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

#if DEBUG
private enum DebugLaunchOptions {
    static let dashboardPreview = ProcessInfo.processInfo.arguments.contains("--dashboard-preview")
}
#endif

final class MenuBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
