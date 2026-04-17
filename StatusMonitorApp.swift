import SwiftUI
import UserNotifications
import OSLog

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "StatusMonitor", category: "ui")

@main
struct StatusMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Empty scene — we manage all windows ourselves
        Settings {
            EmptyView()
        }
    }
}

// MARK: - Floating Panel (replaces NSPopover for clean rectangle, no arrow)

class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false

        // Visual effect for native macOS panel look
        let visualEffect = NSVisualEffectView(frame: contentRect)
        visualEffect.material = .popover
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 10
        visualEffect.layer?.masksToBounds = true
        contentView = visualEffect
    }

    // Close on Escape key
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            close()
        } else {
            super.keyDown(with: event)
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var panel: FloatingPanel!
    let statusManager = StatusManager()
    private var eventMonitor: Any?
    private var localEventMonitor: Any?
    private var settingsWindow: NSWindow?

    var isPanelShown: Bool { panel?.isVisible ?? false }

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("App launching")

        // Launch arguments for UI tests. A menu-bar app is hard to drive via
        // XCUITest because the status item lives in a separate process; these
        // hooks let tests land directly on an inspectable window.
        let args = ProcessInfo.processInfo.arguments
        let uiTestMode = args.contains("-UITestMode")
        if uiTestMode {
            // Start clean each run so onboarding / provider state doesn't leak
            // across tests.
            UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "com.moollapps.StatusMonitor")
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        }

        UserDefaults.standard.register(defaults: ["notificationsEnabled": true])
        // Menu-bar apps use .accessory in production (no Dock icon, no foreground
        // state). That isolation prevents XCUITest from enumerating windows, so
        // we promote to .regular during UI tests — the status item still shows,
        // but the app becomes a regular foreground process the test harness
        // can drive.
        NSApp.setActivationPolicy(uiTestMode ? .regular : .accessory)

        NotificationService.shared.setup()
        NotificationService.shared.requestPermission()

        // Menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateMenuBarIcon(for: .operational)

        if let button = statusItem.button {
            button.action = #selector(handleStatusBarClick)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Status Monitor — All operational"
        }

        // Floating panel (clean rectangle, no popover arrow)
        let panelSize = NSSize(width: 420, height: 520)
        panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: panelSize))

        let hostingView = NSHostingView(
            rootView: DashboardView(onOpenSettings: { [weak self] in
                self?.openSettings()
            })
            .environment(statusManager)
        )
        hostingView.frame = NSRect(origin: .zero, size: panelSize)

        // Add hosting view as subview of the visual effect view
        if let visualEffect = panel.contentView as? NSVisualEffectView {
            hostingView.autoresizingMask = [.width, .height]
            visualEffect.addSubview(hostingView)
        }

        // Close panel on outside click
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if self?.isPanelShown == true {
                self?.panel.close()
            }
        }

        // Keyboard shortcut: Cmd+R to refresh (only when panel is shown)
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isPanelShown else { return event }
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "r" {
                self.statusManager.pollAll()
                return nil
            }
            return event
        }

        // Start polling
        statusManager.startPolling()

        // Notification tap → open panel and deep-link to service
        NotificationService.shared.onNotificationTapped = { [weak self] providerId in
            if self?.isPanelShown != true {
                self?.togglePanel()
            }
            if let providerId {
                NotificationCenter.default.post(
                    name: .deepLinkToProvider,
                    object: nil,
                    userInfo: ["providerId": providerId]
                )
            }
        }

        // Status changes → update menu bar icon
        statusManager.onWorstStatusChanged = { [weak self] status in
            self?.updateMenuBarIcon(for: status)
            self?.updateTooltip()
        }

        // Update tooltip after every poll cycle (not just worst-status changes)
        statusManager.onPollCycleComplete = { [weak self] in
            self?.updateTooltip()
        }

        // First launch → auto-open panel (slight delay so menu bar button window is ready)
        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            logger.info("First launch — opening panel")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.togglePanel()
            }
        }

        #if DEBUG
        NotificationCenter.default.addObserver(forName: .simulateStatus, object: nil, queue: .main) { [weak self] notification in
            guard let id = notification.userInfo?["id"] as? UUID,
                  let status = notification.userInfo?["status"] as? ComponentStatus,
                  let self = self else { return }
            Task { @MainActor in
                if let idx = self.statusManager.snapshots.firstIndex(where: { $0.id == id }) {
                    let oldStatus = self.statusManager.snapshots[idx].overallStatus
                    let name = self.statusManager.snapshots[idx].name
                    self.statusManager.snapshots[idx] = ProviderSnapshot(
                        id: id,
                        name: name,
                        overallStatus: status,
                        components: self.statusManager.snapshots[idx].components,
                        activeIncidents: self.statusManager.snapshots[idx].activeIncidents,
                        lastUpdated: Date(),
                        error: nil
                    )
                    self.statusManager.recalcWorstStatus()
                    // Fire notification on simulated status change
                    if oldStatus != status {
                        NotificationService.shared.notify(
                            providerId: id,
                            provider: name,
                            from: oldStatus,
                            to: status,
                            incident: nil
                        )
                    }
                    logger.debug("Simulated status: \(status.label)")
                }
            }
        }
        #endif

        logger.info("App launch complete — \(self.statusManager.providers.count) providers")

        // UI tests: auto-open the window they need so we don't have to drive
        // the status bar item via Accessibility APIs (which don't work in CI).
        if args.contains("-UITestOpenSettings") {
            DispatchQueue.main.async { [weak self] in self?.openSettings() }
        }
        if args.contains("-UITestOpenSettingsAt") {
            if let idx = args.firstIndex(of: "-UITestOpenSettingsAt"),
               idx + 1 < args.count,
               let tab = SettingsTab(rawValue: args[idx + 1]) {
                DispatchQueue.main.async { [weak self] in self?.openSettings(tab: tab) }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
    }

    // MARK: - Settings Window

    func openSettings(tab: SettingsTab = .services) {
        // Reuse the existing window regardless of visibility so tab selection
        // and other state persist across close/reopen. With
        // `isReleasedWhenClosed = false` the window lives as long as
        // settingsWindow retains it.
        if let window = settingsWindow {
            SettingsInitialTab.value = tab
            NotificationCenter.default.post(name: .settingsTabRequested, object: nil, userInfo: ["tab": tab])
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        SettingsInitialTab.value = tab
        let settingsView = SettingsView()
            .environment(statusManager)

        let controller = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: controller)
        window.title = "Status Monitor Settings"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 680, height: 480))
        window.minSize = NSSize(width: 580, height: 400)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window

        logger.info("Settings window opened")
    }

    // MARK: - Menu Bar Icon

    func updateMenuBarIcon(for status: ComponentStatus) {
        guard let button = statusItem?.button else { return }
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let (name, color) = status.iconInfo
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Status")?
            .withSymbolConfiguration(config)
        // Use template rendering for operational state so macOS matches menu bar appearance
        image?.isTemplate = (status == .operational)
        button.image = image
        button.contentTintColor = (status == .operational) ? nil : color
    }

    private func updateTooltip() {
        let degradedCount = statusManager.snapshots
            .filter { $0.error == nil && $0.overallStatus != .operational }
            .count
        if degradedCount == 0 {
            statusItem.button?.toolTip = "Status Monitor — All operational"
        } else {
            let s = degradedCount == 1 ? "service" : "services"
            statusItem.button?.toolTip = "Status Monitor — \(degradedCount) \(s) degraded"
        }
    }

    // MARK: - Panel Positioning & Toggle

    @objc func handleStatusBarClick() {
        guard let event = NSApp.currentEvent else {
            togglePanel()
            return
        }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePanel()
        }
    }

    @objc func togglePanel() {
        if isPanelShown {
            panel.close()
        } else {
            positionPanel()
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func positionPanel() {
        guard let button = statusItem.button,
              let buttonWindow = button.window else { return }

        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let panelSize = panel.frame.size
        let screenFrame = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        // Center panel horizontally below the menu bar icon
        var x = buttonFrame.midX - panelSize.width / 2
        let y = buttonFrame.minY - panelSize.height - 4 // 4pt gap below menu bar

        // Clamp to screen edges with 8pt margin
        x = max(screenFrame.minX + 8, min(x, screenFrame.maxX - panelSize.width - 8))

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Right-Click Menu

    private func showContextMenu() {
        let menu = NSMenu()

        menu.addItem(withTitle: "About StatusMonitor", action: #selector(showAbout), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Preferences…", action: #selector(openPreferencesAction), keyEquivalent: ",")
        menu.addItem(withTitle: "Send Feedback…", action: #selector(openFeedbackAction), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit StatusMonitor", action: #selector(quitApp), keyEquivalent: "q")

        for item in menu.items {
            item.target = self
        }

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        DispatchQueue.main.async { [weak self] in
            self?.statusItem.menu = nil
        }
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Status Monitor",
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
            .version: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1",
            .credits: NSAttributedString(
                string: "Made by MoollApps\nhttps://github.com/moollaza/status-monitor",
                attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
            ),
        ])
    }

    @objc private func openPreferencesAction() {
        openSettings()
    }

    @objc private func openFeedbackAction() {
        openSettings(tab: .feedback)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
