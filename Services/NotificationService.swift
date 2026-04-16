import Foundation
import UserNotifications
import AppKit
import OSLog

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "StatusMonitor", category: "notifications")

/// Thin seam for tests to substitute a spy implementation. Production code
/// wires `NotificationService.shared` into StatusManager; tests inject a spy.
@MainActor
protocol NotificationServicing: AnyObject {
    func notify(providerId: UUID, provider: String, from: ComponentStatus, to: ComponentStatus, incident: String?)
}

class NotificationService: NSObject, UNUserNotificationCenterDelegate, NotificationServicing {
    static let shared = NotificationService()

    /// Called when user taps a notification with the provider ID for deep-linking.
    var onNotificationTapped: (@MainActor @Sendable (_ providerId: UUID?) -> Void)?

    /// Cached authorization state. Refreshed after `requestPermission` and each
    /// app foreground event. Consulted before each `notify` so we don't enqueue
    /// requests that the system will silently drop.
    private var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        refreshAuthorizationStatus()
    }

    func refreshAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            self?.authorizationStatus = settings.authorizationStatus
        }
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            if let error = error {
                logger.error("Notification permission error: \(error.localizedDescription)")
            }
            if !granted {
                logger.warning("User denied notification permission — outage alerts will not be delivered")
            }
            self?.refreshAuthorizationStatus()
        }
    }

    func notify(providerId: UUID, provider: String, from: ComponentStatus, to: ComponentStatus, incident: String?) {
        guard UserDefaults.standard.bool(forKey: "notificationsEnabled") else {
            logger.debug("Notification suppressed (disabled in preferences)")
            return
        }

        // If we know the user denied permission, there's no point queuing the
        // request — log loudly so the dropped transition is still traceable.
        switch authorizationStatus {
        case .denied:
            logger.warning("Not posting notification for \(provider): authorization denied")
            return
        case .notDetermined:
            // Permission prompt hasn't resolved yet; the add() call will itself
            // no-op. Fall through so the completion handler can log.
            break
        case .authorized, .provisional, .ephemeral:
            break
        @unknown default:
            break
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

        // Include provider ID for deep-linking on tap
        content.userInfo = ["providerId": providerId.uuidString]

        // Stable identifier per provider so a newer notification REPLACES the
        // prior one for the same service (prevents flap-spam in Notification
        // Center when a service oscillates operational↔︎degraded).
        let request = UNNotificationRequest(
            identifier: "status-\(providerId.uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                logger.error("Failed to deliver notification for \(provider): \(error.localizedDescription)")
            }
        }
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
        let providerId = (response.notification.request.content.userInfo["providerId"] as? String).flatMap(UUID.init)
        Task { @MainActor in onNotificationTapped?(providerId) }
        completionHandler()
    }
}
