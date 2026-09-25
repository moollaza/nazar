import XCTest
@testable import StatusMonitor

/// Covers the pure decisions in `Updater` — start policy and the gentle
/// reminder hand-off — plus the menu item the app delegate builds for it.
@MainActor
final class UpdaterTests: XCTestCase {

    // MARK: - Start policy (KTD4)

    func testStartsInAReleaseBuildWithNoTestArguments() {
        XCTAssertTrue(Updater.shouldStartUpdater(isDebugBuild: false, arguments: ["/path/to/Nazar"]))
    }

    func testDoesNotStartInADebugBuild() {
        XCTAssertFalse(Updater.shouldStartUpdater(isDebugBuild: true, arguments: ["/path/to/Nazar"]))
    }

    func testDoesNotStartUnderUITestModeEvenInARelease() {
        XCTAssertFalse(Updater.shouldStartUpdater(isDebugBuild: false, arguments: ["/path/to/Nazar", "-UITestMode"]))
    }

    // MARK: - Gentle reminders (KTD5)

    func testLetsSparkleShowItsOwnWindowOnlyWhenItAlreadyHasFocus() {
        XCTAssertTrue(Updater.shouldHandleShowingScheduledUpdate(immediateFocus: true))
        XCTAssertFalse(Updater.shouldHandleShowingScheduledUpdate(immediateFocus: false))
    }

    // MARK: - Menu title

    func testMenuTitleIsTheManualCheckLabelWhenNothingIsPending() {
        XCTAssertEqual(Updater().menuItemTitle, "Check for Updates…")
    }

    // MARK: - Context menu (U2)

    func testContextMenuHasTheUpdateItemRightAfterAbout() throws {
        let delegate = AppDelegate()
        let menu = delegate.makeContextMenu()

        XCTAssertEqual(menu.items.first?.title, "About Nazar")
        let updateItem = try XCTUnwrap(menu.items.dropFirst().first)
        XCTAssertEqual(updateItem.title, delegate.updater.menuItemTitle)
    }

    func testUpdateMenuItemDoesNotTargetTheAppDelegate() throws {
        let delegate = AppDelegate()
        let updateItem = try XCTUnwrap(delegate.makeContextMenu().items.dropFirst().first)

        XCTAssertFalse(updateItem.target === delegate,
                       "The item runs Sparkle's own checkForUpdates: action, not one of ours")
        XCTAssertNotNil(updateItem.target)
    }

    func testUpdateMenuItemEnabledStateFollowsSparkle() throws {
        let delegate = AppDelegate()
        let updateItem = try XCTUnwrap(delegate.makeContextMenu().items.dropFirst().first)

        XCTAssertEqual(updateItem.isEnabled, delegate.updater.canCheckForUpdates)
    }
}
