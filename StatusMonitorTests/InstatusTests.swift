import XCTest
@testable import StatusMonitor

final class InstatusTests: XCTestCase {

    // MARK: - Status mapping

    func testFromInstatusUp() {
        XCTAssertEqual(ComponentStatus(fromInstatus: "UP"), .operational)
    }

    func testFromInstatusOperationalComponent() {
        XCTAssertEqual(ComponentStatus(fromInstatus: "OPERATIONAL"), .operational)
    }

    func testFromInstatusDegraded() {
        XCTAssertEqual(ComponentStatus(fromInstatus: "DEGRADEDPERFORMANCE"), .degradedPerformance)
    }

    func testFromInstatusHasIssues() {
        XCTAssertEqual(ComponentStatus(fromInstatus: "HASISSUES"), .partialOutage)
    }

    func testFromInstatusPartialOutage() {
        XCTAssertEqual(ComponentStatus(fromInstatus: "PARTIALOUTAGE"), .partialOutage)
    }

    func testFromInstatusMajorOutage() {
        XCTAssertEqual(ComponentStatus(fromInstatus: "MAJOROUTAGE"), .majorOutage)
    }

    /// A minor outage must not be reported as a major one.
    func testFromInstatusMinorOutageIsPartial() {
        XCTAssertEqual(ComponentStatus(fromInstatus: "MINOROUTAGE"), .partialOutage)
    }

    func testFromInstatusUnderMaintenance() {
        XCTAssertEqual(ComponentStatus(fromInstatus: "UNDERMAINTENANCE"), .underMaintenance)
    }

    func testFromInstatusUnknownString() {
        XCTAssertEqual(ComponentStatus(fromInstatus: "garbage"), .unknown)
    }

    // MARK: - Decoding

    /// Captured from https://recraft.instatus.com/summary.json — the common
    /// case, where a healthy page omits the incident arrays entirely.
    private let healthyJSON = """
    {"page":{"name":"Recraft","url":"https://recraft.instatus.com","status":"UP"}}
    """

    /// Captured from https://manychat.instatus.com/summary.json — a page
    /// reporting UP while carrying an open degraded-performance incident.
    private let incidentJSON = """
    {
      "page": { "name": "Manychat", "url": "https://status.manychat.com", "status": "UP" },
      "activeIncidents": [
        {
          "id": "cmmxljn3s01ntuud42lsa7zud",
          "name": "Delays in Instagram automation",
          "started": "2026-03-17T03:00:00.000Z",
          "status": "IDENTIFIED",
          "impact": "DEGRADEDPERFORMANCE",
          "url": "https://status.manychat.com/cmmxljn3s01ntuud42lsa7zud",
          "updatedAt": "2026-05-06T15:19:52.073Z"
        }
      ]
    }
    """

    func testDecodesHealthyPageWithoutIncidentArrays() throws {
        let summary = try JSONDecoder().decode(InstatusSummary.self, from: Data(healthyJSON.utf8))
        XCTAssertEqual(summary.page.name, "Recraft")
        XCTAssertEqual(summary.page.status, "UP")
        XCTAssertNil(summary.activeIncidents)
        XCTAssertNil(summary.activeMaintenances)
    }

    func testDecodesActiveIncident() throws {
        let summary = try JSONDecoder().decode(InstatusSummary.self, from: Data(incidentJSON.utf8))
        let incident = try XCTUnwrap(summary.activeIncidents?.first)
        XCTAssertEqual(incident.impact, "DEGRADEDPERFORMANCE")
        XCTAssertEqual(incident.status, "IDENTIFIED")
    }

    /// The page-level status trails its own incidents on some Instatus pages,
    /// so the worst signal has to win or an active outage renders as healthy.
    func testIncidentImpactOverridesHealthyPageStatus() throws {
        let summary = try JSONDecoder().decode(InstatusSummary.self, from: Data(incidentJSON.utf8))
        let pageStatus = ComponentStatus(fromInstatus: summary.page.status)
        let incidentMax = (summary.activeIncidents ?? [])
            .map { ComponentStatus(fromInstatus: $0.impact ?? "") }
            .max() ?? .operational

        XCTAssertEqual(pageStatus, .operational)
        XCTAssertEqual(max(pageStatus, incidentMax), .degradedPerformance)
    }

    /// Atlassian pages put `status` at the top level. Instatus nests it inside
    /// `page`, so an Atlassian payload must not decode as Instatus.
    func testAtlassianPayloadDoesNotDecodeAsInstatus() {
        let atlassian = """
        {"page":{"name":"GitHub","url":"https://www.githubstatus.com"},
         "status":{"indicator":"none","description":"All Systems Operational"}}
        """
        XCTAssertThrowsError(
            try JSONDecoder().decode(InstatusSummary.self, from: Data(atlassian.utf8))
        )
    }

    /// An incident with no impact field must not turn a healthy page Unknown.
    func testIncidentWithoutImpactDoesNotElevateHealthyPage() throws {
        let json = """
        {"page":{"name":"X","status":"UP"},
         "activeIncidents":[{"id":"i1","name":"Something","status":"INVESTIGATING"}]}
        """
        let summary = try JSONDecoder().decode(InstatusSummary.self, from: Data(json.utf8))
        let pageStatus = ComponentStatus(fromInstatus: summary.page.status)
        let impact = summary.activeIncidents?.first?.impact
            .map(ComponentStatus.init(fromInstatus:)) ?? pageStatus
        XCTAssertEqual(max(pageStatus, impact), .operational)
    }

    // MARK: - Provider wiring

    func testInstatusProviderUsesSummaryEndpoint() {
        let provider = Provider(name: "Recraft", baseURL: "https://recraft.instatus.com", type: .instatus)
        XCTAssertEqual(provider.apiURL?.absoluteString, "https://recraft.instatus.com/summary.json")
    }
}
