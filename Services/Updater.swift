// Sparkle lives in the DMG (Developer ID) flavor only. The App Store build
// defines MAS and compiles none of this — see Config/MAS.xcconfig.
#if !MAS

import AppKit
import Sparkle
import OSLog

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "StatusMonitor", category: "updater")

/// Owns Sparkle's updater controller and the "gentle reminder" state the
/// status-bar menu reads.
///
/// Nazar runs as `.accessory`, so Sparkle's scheduled update alert would open
/// behind whatever the user is looking at. Instead we let Sparkle show its
/// window only when it already has focus, and otherwise reach the user through
/// a notification plus a changed menu title.
@MainActor
final class Updater: NSObject, SPUStandardUserDriverDelegate {

    /// Created with `startingUpdater: false` so the start decision stays ours
    /// (KTD4) — Debug builds and UI-test runs never schedule a check.
    private(set) lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: nil,
        userDriverDelegate: self
    )

    /// Set when a *background* check finds an update, cleared when the user
    /// engages with it. The menu title follows this.
    private(set) var updateAvailableVersion: String?

    /// Posts the "update available" notification. Injected so tests can spy.
    private let notifier: UpdateNotifying

    private var didStart = false

    init(notifier: UpdateNotifying = NotificationService.shared) {
        self.notifier = notifier
        super.init()
    }

    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }

    /// Menu title: reflects a pending background find, otherwise the plain
    /// manual-check label.
    var menuItemTitle: String {
        updateAvailableVersion == nil ? "Check for Updates…" : "Update Available…"
    }

    /// Starts scheduled update checks if this build should run them. The
    /// manual "Check for Updates…" item works either way, so a Debug build can
    /// still exercise the whole flow on demand.
    func startIfNeeded(arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard !didStart else { return }
        guard Self.shouldStartUpdater(isDebugBuild: Self.isDebugBuild, arguments: arguments) else {
            logger.info("Updater not started (debug or UI-test run)")
            return
        }
        controller.startUpdater()
        didStart = true
        logger.info("Updater started")
    }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }

    // MARK: - Start policy (pure, so tests don't need Sparkle state)

    static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    /// Debug builds would nag the developer on every second launch, and a
    /// Sparkle window during XCUITest blocks the harness — `-UITestMode` also
    /// wipes the defaults domain Sparkle stores its schedule in.
    nonisolated static func shouldStartUpdater(isDebugBuild: Bool, arguments: [String]) -> Bool {
        if isDebugBuild { return false }
        if arguments.contains("-UITestMode") { return false }
        return true
    }

    /// Sparkle only lets a scheduled alert take focus when it can do so
    /// without stealing it. When it can't, we handle the reminder ourselves.
    nonisolated static func shouldHandleShowingScheduledUpdate(immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    // MARK: - SPUStandardUserDriverDelegate (gentle reminders)

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        Self.shouldHandleShowingScheduledUpdate(immediateFocus: immediateFocus)
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        // Sparkle is showing its own window for user-initiated checks and for
        // scheduled ones it could bring to the front; nothing to announce.
        guard !state.userInitiated, !handleShowingUpdate else { return }
        let version = update.displayVersionString
        updateAvailableVersion = version
        notifier.notifyUpdateAvailable(version: version)
        logger.info("Background check found \(version, privacy: .public)")
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        updateAvailableVersion = nil
        notifier.withdrawUpdateNotification(version: update.displayVersionString)
    }

    func standardUserDriverWillFinishUpdateSession() {
        updateAvailableVersion = nil
    }
}

#endif
