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
            button.action = #selector(togglePopover)
            button.target = self
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

        // Observe overall status changes for menu bar icon
        statusManager.onWorstStatusChanged = { [weak self] status in
            self?.updateMenuBarIcon(for: status)
        }

        // Auto-open popover on first launch for onboarding
        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            DispatchQueue.main.async { [weak self] in
                self?.togglePopover()
            }
        }
    }

    func updateMenuBarIcon(for status: ComponentStatus) {
        guard let button = statusItem?.button else { return }
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let (name, color) = status.iconInfo
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Status")?
            .withSymbolConfiguration(config)
        button.image = image
        button.contentTintColor = color
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
}
