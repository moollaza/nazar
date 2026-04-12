import SwiftUI
import UserNotifications

@main
struct StatusMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environment(appDelegate.statusManager)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    let statusManager = StatusManager()
    private var eventMonitor: Any?
    private var feedbackWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon — menu bar only
        NSApp.setActivationPolicy(.accessory)

        // Ensure notification delegate is set before anything else
        UNUserNotificationCenter.current().delegate = NotificationService.shared

        // Request notification permissions
        NotificationService.shared.requestPermission()

        // Set up menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateMenuBarIcon(for: .operational)

        if let button = statusItem.button {
            button.action = #selector(handleStatusBarClick)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Status Monitor — All operational"
        }

        // Set up popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 420, height: 520)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: DashboardView()
                .environment(statusManager)
        )

        // Close popover on outside click
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.popover.performClose(nil)
        }

        // Start polling
        statusManager.startPolling()

        // Open popover when user taps a notification
        NotificationService.shared.onNotificationTapped = { [weak self] in
            if !(self?.popover.isShown ?? false) {
                self?.togglePopover()
            }
        }

        // Observe overall status changes for menu bar icon + tooltip
        statusManager.onWorstStatusChanged = { [weak self] status in
            self?.updateMenuBarIcon(for: status)
            self?.updateTooltip()
        }

        // Auto-open popover on first launch for onboarding
        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            DispatchQueue.main.async { [weak self] in
                self?.togglePopover()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
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

    // MARK: - Right-Click Context Menu

    private func showContextMenu() {
        let menu = NSMenu()

        menu.addItem(withTitle: "About StatusMonitor", action: #selector(showAbout), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        menu.addItem(withTitle: "Send Feedback…", action: #selector(sendFeedback), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit StatusMonitor", action: #selector(quitApp), keyEquivalent: "q")

        for item in menu.items {
            item.target = self
        }

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // Remove menu after showing so left-click goes back to popover
        DispatchQueue.main.async { [weak self] in
            self?.statusItem.menu = nil
        }
    }

    @objc private func showAbout() {
        NSApp.setActivationPolicy(.regular)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Status Monitor",
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
            .version: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1",
            .credits: NSAttributedString(
                string: "Made by MoollApps\nhttps://github.com/moollaza/status-monitor",
                attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
            ),
        ])
        // Return to accessory mode after about panel closes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    @objc private func openPreferences() {
        // Open the Settings window via the SwiftUI scene
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc private func sendFeedback() {
        // Close existing feedback window if open
        feedbackWindow?.close()
        feedbackWindow = nil

        let feedbackView = FeedbackView()
        let controller = NSHostingController(rootView: feedbackView)
        let window = NSWindow(contentViewController: controller)
        window.title = "Send Feedback"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(controller.sizeThatFits(in: NSSize(width: 420, height: 600)))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        feedbackWindow = window
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
