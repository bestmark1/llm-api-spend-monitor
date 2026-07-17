import AppKit
import SwiftUI

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

    init(
        appState: AppState = AppState(),
        dashboardViewModel: DashboardViewModel = DashboardViewModel(),
        statusItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    ) {
        self.appState = appState
        self.dashboardViewModel = dashboardViewModel
        self.statusItem = statusItem
        panelPresenter = MenuPanelPresenter(appState: appState, dashboardViewModel: dashboardViewModel)
        super.init()

        configureStatusItem()
        panelPresenter.anchorProvider = { [weak statusItem] in
            statusItem?.button
        }
    }

    func showOnboardingIfNeeded() {
        guard appState.destination == .onboarding else { return }
        panelPresenter.show()
    }

    @objc private func togglePanel() {
        panelPresenter.toggle()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        button.image = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.title = MenuBarLabelView.metricText
        button.target = self
        button.action = #selector(togglePanel)
        button.sendAction(on: [.leftMouseUp])
        button.setAccessibilityLabel(MenuBarLabelView.accessibilityLabel)
    }
}

@MainActor
final class MenuPanelPresenter: NSObject, MenuPanelPresenting, NSWindowDelegate {
    var anchorProvider: (() -> NSStatusBarButton?)?

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

        panel.delegate = self
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
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
    }

    func hide() {
        panel.orderOut(nil)
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
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

final class MenuBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
