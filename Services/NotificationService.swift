import Foundation
import UserNotifications
import AppKit

class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }

    func notify(provider: String, from: ComponentStatus, to: ComponentStatus, incident: String?) {
        let content = UNMutableNotificationContent()
        content.title = "\(provider): \(to.label)"

        if let incident = incident {
            content.body = incident
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
}
