import Foundation
import UserNotifications
import AppKit
import OSLog

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "StatusMonitor", category: "notifications")

class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    /// Called when user taps a notification; set by AppDelegate to open the popover.
    var onNotificationTapped: (@MainActor @Sendable () -> Void)?

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                logger.error("Notification permission error: \(error.localizedDescription)")
            }
        }
    }

    func notify(provider: String, from: ComponentStatus, to: ComponentStatus, incident: String?) {
        guard UserDefaults.standard.bool(forKey: "notificationsEnabled") else {
            logger.debug("Notification suppressed (disabled in preferences)")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "\(provider): \(to.label)"

        if let incident = incident {
            content.body = String(incident.prefix(200))
        } else if to.severity > from.severity {
            content.body = "Status degraded from \(from.label) to \(to.label)"
        } else {
            content.body = "Status improved to \(to.label)"
        }

        // Sound: critical for outages, default for others
        if to == .majorOutage {
            content.sound = .defaultCritical
        } else if to.severity > ComponentStatus.operational.severity {
            content.sound = .default
        }

        // Distinct identifier per provider so notifications stack properly
        let request = UNNotificationRequest(
            identifier: "\(provider)-\(UUID().uuidString)",
            content: content,
            trigger: nil // deliver immediately
        )

        UNUserNotificationCenter.current().add(request)
    }

    // Show notification even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // Open popover when user taps a notification
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in onNotificationTapped?() }
        completionHandler()
    }
}
