import Foundation
import UserNotifications
import AppKit
import OSLog

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "StatusMonitor", category: "notifications")

/// Thin seam for tests to substitute a spy implementation. Production code
/// wires `NotificationService.shared` into StatusManager; tests inject a spy.
@MainActor
protocol NotificationServicing: AnyObject {
    /// Deliver a status-change notification.
    /// - Parameter recentChangeCount: Total status changes for this provider
    ///   in the last hour (including the current one). Values > 1 append a
    ///   "Nth change in the last hour" note to the body so the user knows
    ///   the service is flapping even though Notification Center only shows
    ///   the latest entry (notifications replace per-provider).
    func notify(providerId: UUID, provider: String, from: ComponentStatus, to: ComponentStatus, incident: String?, recentChangeCount: Int)
}

class NotificationService: NSObject, UNUserNotificationCenterDelegate, NotificationServicing {
    static let shared = NotificationService()

    /// Called when user taps a notification with the provider ID for deep-linking.
    var onNotificationTapped: (@MainActor @Sendable (_ providerId: UUID?) -> Void)?

    /// Cached authorization state. Refreshed after `requestPermission` and each
    /// app foreground event. Consulted before each `notify` so we don't enqueue
    /// requests that the system will silently drop.
    private var authorizationStatus: UNAuthorizationStatus = .notDetermined

    /// The init is nonisolated so the `shared` static can initialize without
    /// needing the main actor. Main-actor setup (delegate wiring, initial
    /// permission refresh) happens in `setup()`, which AppDelegate calls
    /// during `applicationDidFinishLaunching` — already on main.
    nonisolated private override init() {
        super.init()
    }

    func setup() {
        UNUserNotificationCenter.current().delegate = self
        refreshAuthorizationStatus()
    }

    func refreshAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            // Callback fires on a UN-internal queue — hop back to main before
            // touching mutable state.
            Task { @MainActor in
                self?.authorizationStatus = settings.authorizationStatus
            }
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
            Task { @MainActor in self?.refreshAuthorizationStatus() }
        }
    }

    func notify(providerId: UUID, provider: String, from: ComponentStatus, to: ComponentStatus, incident: String?, recentChangeCount: Int = 1) {
        guard UserDefaults.standard.bool(forKey: "notificationsEnabled") else {
            logger.debug("Notification suppressed (disabled in preferences)")
            return
        }

        // If we know the user denied permission, there's no point queuing the
        // request — log loudly so the dropped transition is still traceable.
        switch authorizationStatus {
        case .denied:
            logger.warning("Not posting notification for \(provider, privacy: .public): authorization denied")
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

        let request = Self.makeRequest(
            providerId: providerId,
            provider: provider,
            from: from,
            to: to,
            incident: incident,
            recentChangeCount: recentChangeCount
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                logger.error("Failed to deliver notification for \(provider, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Pure builder for the notification request. Extracted so tests can
    /// inspect title / body / sound / identifier / userInfo without needing
    /// to intercept UNUserNotificationCenter.
    ///
    /// Body format:
    /// - Base: "Operational → Degraded"
    /// - With incident: "Operational → Degraded — <incident>"
    /// - Flapping: "Operational → Degraded (3rd change in the last hour)"
    /// - Both: "Operational → Degraded — <incident> (3rd change in the last hour)"
    nonisolated static func makeRequest(
        providerId: UUID,
        provider: String,
        from: ComponentStatus,
        to: ComponentStatus,
        incident: String?,
        recentChangeCount: Int = 1
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "\(provider): \(to.label)"
        content.body = makeBody(from: from, to: to, incident: incident, recentChangeCount: recentChangeCount)

        // Sound: critical for outages, default for other non-green states, silent on recovery.
        if to == .majorOutage {
            content.sound = .defaultCritical
        } else if to.severity > ComponentStatus.operational.severity {
            content.sound = .default
        }

        content.userInfo = ["providerId": providerId.uuidString]

        // Stable identifier per provider so a newer notification REPLACES the
        // prior one for the same service (prevents flap-spam in Notification
        // Center when a service oscillates operational↔︎degraded). Flap
        // awareness is instead surfaced inside the body via recentChangeCount.
        return UNNotificationRequest(
            identifier: "status-\(providerId.uuidString)",
            content: content,
            trigger: nil
        )
    }

    nonisolated static func makeBody(from: ComponentStatus, to: ComponentStatus, incident: String?, recentChangeCount: Int) -> String {
        var body = "\(from.label) → \(to.label)"
        if let incident {
            // Leave ~60 chars for the arrow + labels + flap suffix.
            let trimmedIncident = String(incident.prefix(140))
            body += " — \(trimmedIncident)"
        }
        if recentChangeCount > 1 {
            body += " (\(ordinal(recentChangeCount)) change in the last hour)"
        }
        return body
    }

    nonisolated private static func ordinal(_ n: Int) -> String {
        switch n {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(n)th"
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
