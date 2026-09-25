import XCTest
import UserNotifications
@testable import StatusMonitor

/// Tests the pure `makeRequest` / `makeBody` builders. Covers the
/// notification-shape invariants and the smarter body format: arrow
/// transition + incident annotation + flap-count suffix.
final class NotificationServiceTests: XCTestCase {

    private let providerId = UUID()

    private func make(from: ComponentStatus,
                      to: ComponentStatus,
                      incident: String? = nil,
                      changeCount: Int = 1,
                      provider: String = "TestService") -> UNNotificationRequest {
        NotificationService.makeRequest(
            providerId: providerId,
            provider: provider,
            from: from,
            to: to,
            incident: incident,
            recentChangeCount: changeCount
        )
    }

    // MARK: - Identifier (stable per provider so notifications coalesce)

    func testIdentifierIsStablePerProvider() {
        let r1 = make(from: .operational, to: .majorOutage)
        let r2 = make(from: .majorOutage, to: .operational)
        XCTAssertEqual(r1.identifier, r2.identifier,
                       "Identifier must be stable per providerId so successive notifications REPLACE each other")
        XCTAssertTrue(r1.identifier.contains(providerId.uuidString))
    }

    func testIdentifiersDifferAcrossProviders() {
        let a = NotificationService.makeRequest(providerId: UUID(), provider: "A",
                                                from: .operational, to: .majorOutage,
                                                incident: nil, recentChangeCount: 1)
        let b = NotificationService.makeRequest(providerId: UUID(), provider: "B",
                                                from: .operational, to: .majorOutage,
                                                incident: nil, recentChangeCount: 1)
        XCTAssertNotEqual(a.identifier, b.identifier)
    }

    // MARK: - Title

    func testTitleContainsProviderAndStatus() {
        let req = make(from: .operational, to: .majorOutage, provider: "GitHub")
        XCTAssertEqual(req.content.title, "GitHub: Major Outage")
    }

    // MARK: - Body: arrow transition as baseline

    func testBodyShowsTransitionArrow() {
        let req = make(from: .operational, to: .degradedPerformance)
        XCTAssertEqual(req.content.body, "Operational → Degraded")
    }

    func testBodyRecoveryShowsArrow() {
        let req = make(from: .majorOutage, to: .operational)
        XCTAssertEqual(req.content.body, "Major Outage → Operational")
    }

    // MARK: - Body: incident annotation

    func testBodyAppendsIncidentAfterArrow() {
        let req = make(from: .operational, to: .majorOutage, incident: "API 5xx spike in us-east")
        XCTAssertEqual(req.content.body, "Operational → Major Outage — API 5xx spike in us-east")
    }

    func testBodyTruncatesLongIncident() {
        let longIncident = String(repeating: "x", count: 300)
        let req = make(from: .operational, to: .majorOutage, incident: longIncident)
        XCTAssertTrue(req.content.body.count <= 200,
                      "Body stays within notification-center's visible length")
        XCTAssertTrue(req.content.body.contains("Operational → Major Outage — "))
    }

    // MARK: - Body: flap-count suffix

    func testBodyOmitsChangeCountOnFirstChange() {
        let req = make(from: .operational, to: .degradedPerformance, changeCount: 1)
        XCTAssertFalse(req.content.body.contains("change in the last hour"),
                       "First-change-of-the-hour should NOT be annotated with a count")
    }

    func testBodyShowsSecondChangeSuffix() {
        let req = make(from: .operational, to: .degradedPerformance, changeCount: 2)
        XCTAssertEqual(req.content.body, "Operational → Degraded (2nd change in the last hour)")
    }

    func testBodyShowsThirdChangeSuffix() {
        let req = make(from: .degradedPerformance, to: .operational, changeCount: 3)
        XCTAssertEqual(req.content.body, "Degraded → Operational (3rd change in the last hour)")
    }

    func testBodyShowsNthChangeSuffix() {
        let req = make(from: .operational, to: .majorOutage, changeCount: 7)
        XCTAssertEqual(req.content.body, "Operational → Major Outage (7th change in the last hour)")
    }

    func testBodyCombinesIncidentAndFlapSuffix() {
        let req = make(from: .operational, to: .majorOutage,
                       incident: "Investigating elevated errors",
                       changeCount: 4)
        XCTAssertEqual(req.content.body,
                       "Operational → Major Outage — Investigating elevated errors (4th change in the last hour)")
    }

    // MARK: - Sound

    func testMajorOutageUsesCriticalSound() {
        let req = make(from: .operational, to: .majorOutage)
        XCTAssertEqual(req.content.sound, .defaultCritical)
    }

    func testNonCriticalNonGreenUsesDefaultSound() {
        let req = make(from: .operational, to: .degradedPerformance)
        XCTAssertEqual(req.content.sound, .default)
    }

    func testRecoveryToOperationalIsSilent() {
        let req = make(from: .majorOutage, to: .operational)
        XCTAssertNil(req.content.sound,
                     "Recovery notifications shouldn't play a sound — user just got a red one a moment ago")
    }

    // MARK: - userInfo (deep-link payload)

    func testUserInfoCarriesProviderIdAsString() {
        let req = make(from: .operational, to: .majorOutage)
        XCTAssertEqual(req.content.userInfo["providerId"] as? String, providerId.uuidString)
    }

    // MARK: - Unicode / edge cases

    func testProviderNameWithEmojiIsPreservedInTitle() {
        let req = make(from: .operational, to: .majorOutage, provider: "🚀 Rocket API")
        XCTAssertTrue(req.content.title.contains("🚀 Rocket API"))
    }

    func testIncidentWithEmojiDoesNotCrashOnMultibyteBoundary() {
        let flag = "🇺🇳"
        let longIncident = String(repeating: flag, count: 50)
        _ = make(from: .operational, to: .majorOutage, incident: longIncident)
        // If the line above didn't crash, we're good.
    }
}

/// The update notification is a second category on the same delegate as the
/// outage alerts, so both the request shape and the tap routing are covered
/// here — outage routing must stay unchanged.
final class UpdateNotificationTests: XCTestCase {

    func testTitleNamesTheVersion() {
        let req = NotificationService.makeUpdateRequest(version: "1.4.0")
        XCTAssertEqual(req.content.title, "Nazar 1.4.0 is available")
    }

    func testUsesTheUpdateCategory() {
        let req = NotificationService.makeUpdateRequest(version: "1.4.0")
        XCTAssertEqual(req.content.categoryIdentifier, NotificationService.updateCategoryIdentifier)
    }

    func testIdentifierIsStablePerVersionSoRemindersReplace() {
        let first = NotificationService.makeUpdateRequest(version: "1.4.0")
        let second = NotificationService.makeUpdateRequest(version: "1.4.0")
        XCTAssertEqual(first.identifier, second.identifier)
    }

    func testIdentifiersDifferAcrossVersions() {
        let a = NotificationService.makeUpdateRequest(version: "1.4.0")
        let b = NotificationService.makeUpdateRequest(version: "1.5.0")
        XCTAssertNotEqual(a.identifier, b.identifier)
    }

    // MARK: - Tap routing

    func testUpdateCategoryRoutesToTheUpdater() {
        let route = NotificationService.route(
            categoryIdentifier: NotificationService.updateCategoryIdentifier,
            userInfo: [:]
        )
        XCTAssertEqual(route, .update)
    }

    func testOutageNotificationStillRoutesToItsProvider() {
        let id = UUID()
        let route = NotificationService.route(
            categoryIdentifier: "",
            userInfo: ["providerId": id.uuidString]
        )
        XCTAssertEqual(route, .provider(id))
    }

    func testOutageNotificationWithoutAProviderRoutesToThePanel() {
        XCTAssertEqual(NotificationService.route(categoryIdentifier: "", userInfo: [:]), .provider(nil))
    }
}
