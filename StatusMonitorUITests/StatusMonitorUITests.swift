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
        let window = app.windows["Nazar Settings"]
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
        let window = app.windows["Nazar Settings"]
        XCTAssertTrue(window.waitForExistence(timeout: 5))

        // Feedback tab renders a "Send Feedback" header. Tab transition can
        // take a moment — 5s timeout matches the Services tab-load wait.
        XCTAssertTrue(window.staticTexts["Send Feedback"].waitForExistence(timeout: 5),
                      "Feedback tab content should appear when launched with -UITestOpenSettingsAt Feedback")
    }

    func testCustomServiceURLValidatorRejectsHTTP() {
        let app = launchSettings(tab: "Services")
        let window = app.windows["Nazar Settings"]
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
        let window = app.windows["Nazar Settings"]
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
        let window = app.windows["Nazar Settings"]
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

    func testSettingsOffersCheckForUpdates() {
        for tab in ["Preferences", "Help"] {
            let app = launchSettings(tab: tab)
            let window = app.windows["Nazar Settings"]
            XCTAssertTrue(window.waitForExistence(timeout: 5))
            XCTAssertTrue(window.buttons["Check for Updates…"].waitForExistence(timeout: 5),
                          "\(tab) tab should offer Check for Updates")
            app.terminate()
        }
    }
}

/// User journeys from the verify skill, run headless on CI instead of driving
/// the maintainer's desktop. A real status page is polled, so a row may read
/// "Unavailable" when the network is down; tests match the service name, not
/// its status.
final class JourneyUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode"] + arguments
        app.launch()
        return app
    }

    private func githubRow(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["service-row-github"]
    }

    private func openPanelFromMenuBar(_ app: XCUIApplication) {
        let icon = app.statusItems.firstMatch
        XCTAssertTrue(icon.waitForExistence(timeout: 5), "Nazar should have a menu bar icon")
        icon.click()
    }

    /// Clicks a screen point through `host`, which is already frontmost.
    /// `XCUIElement.click()` activates the element's app first, and that hides
    /// bugs that only show while another app is in front.
    private func click(at point: CGPoint, through host: XCUIApplication) {
        let origin = host.frame.origin
        host.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: point.x - origin.x, dy: point.y - origin.y))
            .click()
    }

    private func setGitHubMonitored(_ monitored: Bool, in app: XCUIApplication) {
        let settings = app.windows["Nazar Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5), "Settings window should be open")
        settings.staticTexts["Catalog"].click()
        XCTAssertTrue(settings.staticTexts["Service Catalog"].waitForExistence(timeout: 5))

        let search = settings.textFields["catalog-search"]
        search.click()
        search.typeKey("a", modifierFlags: .command)
        search.typeText("GitHub")

        let checkbox = settings.checkBoxes["catalog-toggle-github"]
        XCTAssertTrue(checkbox.waitForExistence(timeout: 5), "GitHub should be in the search results")
        if (checkbox.value as? Int == 1) != monitored {
            checkbox.click()
        }
        XCTAssertEqual(checkbox.value as? Int, monitored ? 1 : 0)
    }

    /// Adds GitHub from the catalog, closes Settings, and opens the panel the
    /// way a user does.
    private func launchWithGitHubInPanel() -> XCUIApplication {
        let app = launch(["-UITestOpenSettingsAt", "Catalog"])
        setGitHubMonitored(true, in: app)
        app.windows["Nazar Settings"].typeKey("w", modifierFlags: .command)
        openPanelFromMenuBar(app)
        XCTAssertTrue(githubRow(in: app).waitForExistence(timeout: 30),
                      "A service added from the catalog should appear in the panel")
        return app
    }

    func testFirstRunOpensOnboardingPanelAndBrowseCatalogOpensSettings() {
        let app = launch(["-UITestFirstRun"])

        XCTAssertTrue(app.staticTexts["No services monitored"].waitForExistence(timeout: 5),
                      "First launch should open the panel on its own with the empty state")
        app.buttons["Browse Catalog"].click()
        XCTAssertTrue(app.windows["Nazar Settings"].waitForExistence(timeout: 5),
                      "Browse Catalog should open Settings")
    }

    func testMenuBarIconTogglesPanel() {
        let app = launch(["-UITestAccessory"])

        openPanelFromMenuBar(app)
        let empty = app.staticTexts["No services monitored"]
        XCTAssertTrue(empty.waitForExistence(timeout: 5), "Clicking the icon should open the panel")

        // A menu bar app is usually not frontmost while its panel shows.
        // XCUIElement.click() activates the app first, so click the icon with
        // raw mouse events to keep another app in front.
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        XCTAssertTrue(finder.wait(for: .runningForeground, timeout: 5), "Finder should be frontmost")
        XCTAssertTrue(empty.exists, "The panel should stay open when another app becomes active")

        let icon = app.statusItems.firstMatch.frame
        click(at: CGPoint(x: icon.midX, y: icon.midY), through: finder)
        XCTAssertTrue(empty.waitForNonExistence(timeout: 5), "Clicking the icon again should close the panel")
        _ = XCTWaiter.wait(for: [XCTestExpectation()], timeout: 1)
        XCTAssertFalse(empty.exists, "The panel should stay closed after the second click")

        openPanelFromMenuBar(app)
        XCTAssertTrue(empty.waitForExistence(timeout: 5), "A third click should open the panel again")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(empty.waitForNonExistence(timeout: 5), "Escape should close the panel")
    }

    func testCatalogAddPersistsAcrossRelaunchAndRemoveEmptiesPanel() {
        var app = launchWithGitHubInPanel()

        app.terminate()
        app = launch(["-UITestKeepState"])
        openPanelFromMenuBar(app)
        let row = githubRow(in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 30), "The added service should survive a relaunch")
        let label = row.value as? String ?? ""
        XCTAssertTrue(label.hasPrefix("GitHub, "), "Row should read 'GitHub, <status>', got '\(label)'")

        // Opening Settings closes the panel, so it can't cover the catalog.
        // Reopen the panel afterwards to see the result.
        app.menuButtons["Settings and more"].click()
        // The app's hidden main menu also has a "Settings…" item; click the visible one.
        let settingsItem = app.menuItems.matching(identifier: "Settings…").allElementsBoundByIndex
            .first { $0.isHittable } ?? app.menuItems["Settings…"].firstMatch
        settingsItem.click()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5), "Opening Settings should close the panel")
        setGitHubMonitored(false, in: app)
        openPanelFromMenuBar(app)
        XCTAssertTrue(app.staticTexts["No services monitored"].waitForExistence(timeout: 5),
                      "Unticking the catalog entry should empty the panel")
    }

    func testPanelFilterDetailAndRefresh() {
        let app = launchWithGitHubInPanel()
        let row = githubRow(in: app)

        let filter = app.textFields["dashboard-filter"]
        filter.click()
        filter.typeText("zzz")
        XCTAssertTrue(row.waitForNonExistence(timeout: 5), "A filter with no match should hide the row")
        filter.typeKey("a", modifierFlags: .command)
        filter.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Clearing the filter should bring the row back")

        app.menuButtons["Settings and more"].click()
        app.menuItems["Refresh Now"].click()

        row.click()
        XCTAssertTrue(app.buttons["detail-view-status-page"].waitForExistence(timeout: 5),
                      "Clicking a row should open its detail view")
        app.buttons["detail-back"].click()
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Back should return to the list")
    }

    func testSimulatedOutageUpdatesRowAndResets() {
        let app = launchWithGitHubInPanel()

        let row = githubRow(in: app)
        row.rightClick()
        app.menuItems["Simulate Major Outage"].click()
        XCTAssertTrue(app.staticTexts["1 issue"].waitForExistence(timeout: 5),
                      "Footer should count the simulated outage")
        XCTAssertEqual(row.value as? String, "GitHub, Major Outage")

        row.rightClick()
        app.menuItems["Reset to Operational"].click()
        XCTAssertTrue(app.staticTexts["All operational"].waitForExistence(timeout: 5),
                      "Reset should clear the outage")
        // Coming back from an outage shows the Recovered badge until it is seen.
        let label = row.value as? String ?? ""
        XCTAssertTrue(label.hasPrefix("GitHub, Recovered"), "Row should read 'GitHub, Recovered…', got '\(label)'")
    }
}
