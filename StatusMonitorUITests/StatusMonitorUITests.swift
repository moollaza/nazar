import XCTest

/// Smoke-test UI coverage. Menu-bar apps can't be driven through the status
/// item in CI (the status bar lives in a separate process), so these tests
/// use the app's `-UITestMode` and `-UITestOpenSettings[At]` launch arguments
/// to land directly on inspectable windows.
final class StatusMonitorUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    private func launchSettings(tab: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "-UITestOpenSettings"]
        if let tab {
            app.launchArguments = ["-UITestMode", "-UITestOpenSettingsAt", tab]
        }
        app.launch()
        return app
    }

    // MARK: - Tests

    func testAppLaunchesWithoutCrashing() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode"]
        app.launch()
        XCTAssertEqual(app.state, .runningForeground, "App must reach foreground after launch")
    }

    func testSettingsWindowOpensWithAllTabs() {
        let app = launchSettings()
        let window = app.windows["Status Monitor Settings"]
        XCTAssertTrue(window.waitForExistence(timeout: 5), "Settings window should appear")

        // All 5 tabs present in the sidebar.
        for tab in ["Services", "Catalog", "Preferences", "Feedback", "Help"] {
            XCTAssertTrue(window.staticTexts[tab].exists, "Sidebar should contain \(tab) tab")
        }
    }

    func testSettingsOpensDirectlyOnFeedbackTab() {
        // Right-click → "Send Feedback…" uses the same tab-routing path. This
        // verifies the tab-navigation fix end-to-end.
        let app = launchSettings(tab: "Feedback")
        let window = app.windows["Status Monitor Settings"]
        XCTAssertTrue(window.waitForExistence(timeout: 5))

        // Feedback tab renders a "Send Feedback" header. Tab transition can
        // take a moment — 5s timeout matches the Services tab-load wait.
        XCTAssertTrue(window.staticTexts["Send Feedback"].waitForExistence(timeout: 5),
                      "Feedback tab content should appear when launched with -UITestOpenSettingsAt Feedback")
    }

    func testCustomServiceURLValidatorRejectsHTTP() {
        let app = launchSettings(tab: "Services")
        let window = app.windows["Status Monitor Settings"]
        XCTAssertTrue(window.waitForExistence(timeout: 5))

        // Open the Add Custom sheet.
        let addCustomButton = window.buttons["Add Custom..."]
        XCTAssertTrue(addCustomButton.waitForExistence(timeout: 2))
        addCustomButton.click()

        // The sheet becomes the frontmost window.
        let nameField = app.textFields.element(boundBy: 0)
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        nameField.click()
        nameField.typeText("Test Service")

        let urlField = app.textFields.element(boundBy: 1)
        urlField.click()
        urlField.typeText("http://status.example.com")

        // Inline validation should appear.
        let validationMessage = app.staticTexts["URL must be a valid https:// address with a host"]
        XCTAssertTrue(validationMessage.waitForExistence(timeout: 2),
                      "http:// URL must surface the validation banner")

        // Add button must be disabled.
        let addButton = app.sheets.firstMatch.buttons["Add"]
        if addButton.exists {
            XCTAssertFalse(addButton.isEnabled, "Add must be disabled while URL is invalid")
        }
    }

    func testCustomServiceURLValidatorAcceptsHTTPS() {
        let app = launchSettings(tab: "Services")
        let window = app.windows["Status Monitor Settings"]
        XCTAssertTrue(window.waitForExistence(timeout: 5))

        window.buttons["Add Custom..."].click()

        let nameField = app.textFields.element(boundBy: 0)
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        nameField.click()
        nameField.typeText("Example")

        let urlField = app.textFields.element(boundBy: 1)
        urlField.click()
        urlField.typeText("https://status.example.com")

        // Validation banner must be absent.
        let validationMessage = app.staticTexts["URL must be a valid https:// address with a host"]
        XCTAssertFalse(validationMessage.exists,
                       "A valid https URL should not trigger the validation banner")

        // Add button must be enabled.
        let addButton = app.sheets.firstMatch.buttons["Add"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 2))
        XCTAssertTrue(addButton.isEnabled)
    }

    func testHelpTabShowsVersionAndLinks() {
        let app = launchSettings(tab: "Help")
        let window = app.windows["Status Monitor Settings"]
        XCTAssertTrue(window.waitForExistence(timeout: 5))

        // Tab transition can take a moment after window appearance.
        XCTAssertTrue(window.staticTexts["How It Works"].waitForExistence(timeout: 5),
                      "Help tab content should render")

        // SwiftUI `Link` surfaces via several accessibility roles depending on
        // macOS version; scan the descendants broadly to avoid a brittle role
        // check.
        let predicate = NSPredicate(format: "label CONTAINS[c] 'github repository'")
        let descendants = window.descendants(matching: .any).matching(predicate)
        XCTAssertGreaterThan(descendants.count, 0,
                             "Help tab should surface the GitHub Repository link")
    }
}
