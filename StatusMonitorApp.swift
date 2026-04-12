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

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    let statusManager = StatusManager()
    private var eventMonitor: Any?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("App launching")

        NSApp.setActivationPolicy(.accessory)

        UNUserNotificationCenter.current().delegate = NotificationService.shared
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

        // Popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 420, height: 520)
        popover.behavior = .transient
        popover.hasFullSizeContent = true
        popover.contentViewController = NSHostingController(
            rootView: DashboardView(onOpenSettings: { [weak self] in
                self?.openSettings()
            })
            .environment(statusManager)
        )

        // Close popover on outside click
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.popover.performClose(nil)
        }

        // Keyboard shortcut: Cmd+R to refresh
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "r" {
                self?.statusManager.pollAll()
                return nil
            }
            return event
        }

        // Start polling
        statusManager.startPolling()

        // Notification tap → open popover
        NotificationService.shared.onNotificationTapped = { [weak self] in
            if !(self?.popover.isShown ?? false) {
                self?.togglePopover()
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

        // First launch → auto-open popover
        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            logger.info("First launch — opening popover")
            DispatchQueue.main.async { [weak self] in
                self?.togglePopover()
            }
        }

        #if DEBUG
        NotificationCenter.default.addObserver(forName: .init("SimulateStatus"), object: nil, queue: .main) { [weak self] notification in
            guard let id = notification.userInfo?["id"] as? UUID,
                  let status = notification.userInfo?["status"] as? ComponentStatus,
                  let self = self else { return }
            if let idx = self.statusManager.snapshots.firstIndex(where: { $0.id == id }) {
                self.statusManager.snapshots[idx] = ProviderSnapshot(
                    id: id,
                    name: self.statusManager.snapshots[idx].name,
                    overallStatus: status,
                    components: self.statusManager.snapshots[idx].components,
                    activeIncidents: self.statusManager.snapshots[idx].activeIncidents,
                    lastUpdated: Date(),
                    error: nil
                )
                self.statusManager.recalcWorstStatus()
                logger.debug("Simulated status: \(status.label)")
            }
        }
        #endif

        logger.info("App launch complete — \(self.statusManager.providers.count) providers")
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    // MARK: - Settings Window

    func openSettings() {
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

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
        button.image = image
        button.contentTintColor = color
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

    // MARK: - Click Handling

    @objc func handleStatusBarClick() {
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
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
        openSettings()
        // TODO: Navigate to Feedback tab
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
