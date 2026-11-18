import XCTest
@testable import StatusMonitor

/// Fixtures follow the payloads that live PagerDuty status pages served in
/// November 2026, trimmed to the fields the parser reads.
@MainActor
final class PagerDutyTests: XCTestCase {

    private let base = "https://status.example.com"
    private let postsPath = "/api/posts?is_featured=true&limit=500"

    override func tearDown() {
        super.tearDown()
        StubURLProtocol.clearStubs()
    }

    private func makeManager() -> StatusManager {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let manager = StatusManager(session: URLSession(configuration: config), notifier: StatusManagerPollTests.NotificationSpy())
        manager.snapshots = []
        manager.providers = []
        return manager
    }

    private func stub(_ path: String, _ json: String, status: Int = 200) {
        StubURLProtocol.register(url: URL(string: base + path)!, response: (Data(json.utf8), status))
    }

    /// Ids are made up per page by PagerDuty. Only the keys are fixed.
    private let enumsJSON = #"""
    {"post_enums":[
      {"id":"S_INV","name":"investigating","post_type":"incident","post_enum_type":"status","rank":1,"layout_settings":{"key":"incident/status/investigating"}},
      {"id":"S_RES","name":"resolved","post_type":"incident","post_enum_type":"status","rank":3,"layout_settings":{"key":"incident/status/resolved"}},
      {"id":"S_SCH","name":"scheduled","post_type":"maintenance","post_enum_type":"status","rank":0,"layout_settings":{"key":"maintenance/status/scheduled"}},
      {"id":"S_PRG","name":"in progress","post_type":"maintenance","post_enum_type":"status","rank":1,"layout_settings":{"key":"maintenance/status/in_progress"}},
      {"id":"I_OK","name":"operational","post_type":"incident","post_enum_type":"impacts","rank":0,"layout_settings":{"key":"incident/impacts/operational"}},
      {"id":"I_PART","name":"partial outage","post_type":"incident","post_enum_type":"impacts","rank":1,"layout_settings":{"key":"incident/impacts/partial_outage"}},
      {"id":"I_OUT","name":"outage","post_type":"incident","post_enum_type":"impacts","rank":2,"layout_settings":{"key":"incident/impacts/outage"}},
      {"id":"M_MAINT","name":"maintenance","post_type":"maintenance","post_enum_type":"impacts","rank":1,"layout_settings":{"key":"maintenance/impacts/maintenance"}}
    ]}
    """#

    private let servicesJSON = #"""
    {"services":[
      {"name":"API","id":"SVC_API","is_active":true,"display_name":"Public API","status_page_id":"P1"},
      {"name":"Web","id":"SVC_WEB","is_active":true,"display_name":"Web App","status_page_id":"P1"},
      {"name":"Old","id":"SVC_OLD","is_active":false,"display_name":"Retired","status_page_id":"P1"}
    ]}
    """#

    private func stubHealthyPage() {
        stub("/api/impacted_services", #"{"status_page_id":"P1","impacted_services":[]}"#)
        stub("/api/post_enums", enumsJSON)
        stub("/api/services", servicesJSON)
        stub(postsPath, #"{"posts":[],"continuationToken":null}"#)
    }

    private func stubDegradedPage() {
        stub("/api/impacted_services", #"""
        {"status_page_id":"P1","impacted_services":[
          {"service_id":"SVC_API","impact_severity_id":"I_PART"},
          {"service_id":"SVC_WEB","impact_severity_id":"M_MAINT"}
        ]}
        """#)
        stub("/api/post_enums", enumsJSON)
        stub("/api/services", servicesJSON)
        stub(postsPath, #"""
        {"posts":[
          {"id":"POST_MAINT","title":"Database upgrade","post_type":"maintenance","last_update_at":1794457363000,
           "latest_update":{"id":"U3","status_id":"S_PRG","message":"Started.","reported_at":1794457363000,
             "impacts":[{"service_id":"SVC_WEB","severity_id":"M_MAINT"}]},
           "updates":[{"id":"U3","status_id":"S_PRG","message":"Started.","reported_at":1794457363000,
             "impacts":[{"service_id":"SVC_WEB","severity_id":"M_MAINT"}]}]},
          {"id":"POST_LATER","title":"Next month's upgrade","post_type":"maintenance","last_update_at":1794457364000,
           "latest_update":{"id":"U4","status_id":"S_SCH","message":"Planned.","reported_at":1794457364000,
             "impacts":[{"service_id":"SVC_API","severity_id":"M_MAINT"}]},
           "updates":[]},
          {"id":"POST_INC","title":"API errors","post_type":"incident","last_update_at":1794400000000,
           "latest_update":{"id":"U2","status_id":"S_INV","message":"Still looking.","reported_at":1794400000000,
             "impacts":[{"service_id":"SVC_API","severity_id":"I_PART"}]},
           "updates":[
             {"id":"U1","status_id":"S_INV","message":"Elevated errors.<br />Investigating &amp; monitoring.","reported_at":1794300000000,"impacts":[]},
             {"id":"U2","status_id":"S_INV","message":"Still looking.","reported_at":1794400000000,"impacts":[]}
           ]}
        ]}
        """#)
    }

    // MARK: - Vocabulary

    func testImpactKeysMapToComponentStatus() {
        XCTAssertEqual(ComponentStatus(fromPagerDuty: "incident/impacts/operational"), .operational)
        XCTAssertEqual(ComponentStatus(fromPagerDuty: "incident/impacts/partial_outage"), .partialOutage)
        XCTAssertEqual(ComponentStatus(fromPagerDuty: "incident/impacts/outage"), .majorOutage)
        XCTAssertEqual(ComponentStatus(fromPagerDuty: "maintenance/impacts/maintenance"), .underMaintenance)
        XCTAssertEqual(ComponentStatus(fromPagerDuty: "incident/impacts/something_new"), .unknown)
    }

    func testPagerDutyProviderPollsImpactedServices() {
        let provider = Provider(name: "BombBomb", baseURL: "https://status.bombbomb.com", type: .pagerduty)
        XCTAssertEqual(provider.apiURL?.absoluteString, "https://status.bombbomb.com/api/impacted_services")
        XCTAssertEqual(ProviderType(rawValue: "pagerduty"), .pagerduty)
    }

    func testUpdateMessagesLoseTheirHTML() {
        XCTAssertEqual(
            StatusManager.plainText(fromHTML: "Line one.<br /><br>Line <b>two</b> &amp; three."),
            "Line one.\n\nLine two & three."
        )
    }

    // MARK: - Poll

    func testHealthyPageIsOperationalAndListsActiveServices() async {
        stubHealthyPage()
        let manager = makeManager()
        let provider = Provider(name: "Example", baseURL: base, type: .pagerduty)
        manager.providers = [provider]

        await manager.poll(provider: provider)

        let snapshot = manager.snapshots[0]
        XCTAssertNil(snapshot.error)
        XCTAssertEqual(snapshot.overallStatus, .operational)
        XCTAssertEqual(snapshot.components.map(\.name), ["Public API", "Web App"])
        XCTAssertTrue(snapshot.components.allSatisfy { $0.status == .operational })
        XCTAssertTrue(snapshot.activeIncidents.isEmpty)
    }

    func testImpactedServicesDriveComponentAndOverallStatus() async {
        stubDegradedPage()
        let manager = makeManager()
        let provider = Provider(name: "Example", baseURL: base, type: .pagerduty)
        manager.providers = [provider]

        await manager.poll(provider: provider)

        let snapshot = manager.snapshots[0]
        XCTAssertNil(snapshot.error)
        let byId = Dictionary(uniqueKeysWithValues: snapshot.components.map { ($0.id, $0.status) })
        XCTAssertEqual(byId["SVC_API"], .partialOutage)
        XCTAssertEqual(byId["SVC_WEB"], .underMaintenance)
        XCTAssertEqual(snapshot.overallStatus, .partialOutage)
    }

    /// Featured posts include maintenance that has not started. Only open
    /// incidents and in-progress maintenance are active, incidents first.
    func testActiveIncidentsSkipScheduledMaintenance() async throws {
        stubDegradedPage()
        let manager = makeManager()
        let provider = Provider(name: "Example", baseURL: base, type: .pagerduty)
        manager.providers = [provider]

        await manager.poll(provider: provider)

        let incidents = manager.snapshots[0].activeIncidents
        XCTAssertEqual(incidents.map(\.id), ["POST_INC", "POST_MAINT"])

        let incident = try XCTUnwrap(incidents.first)
        XCTAssertEqual(incident.name, "API errors")
        XCTAssertEqual(incident.status, "Investigating")
        XCTAssertEqual(incident.impact, .partialOutage)
        XCTAssertEqual(incident.latestUpdate, "Still looking.")
        XCTAssertEqual(incident.updates.map(\.id), ["U2", "U1"], "updates newest first")
        XCTAssertEqual(incident.updates.last?.body, "Elevated errors.\nInvestigating & monitoring.")
        XCTAssertEqual(incident.updatedAt, Date(timeIntervalSince1970: 1_794_400_000))

        XCTAssertEqual(incidents.last?.impact, .underMaintenance)
        XCTAssertEqual(incidents.last?.status, "In Progress")
    }

    /// The status lives in four responses. A page missing any one of them is
    /// a failed poll, not a healthy page.
    func testFailedSecondaryRequestIsAFailedPoll() async {
        stubHealthyPage()
        stub(postsPath, "", status: 404)
        let manager = makeManager()
        let provider = Provider(name: "Example", baseURL: base, type: .pagerduty)
        manager.providers = [provider]

        await manager.poll(provider: provider)

        XCTAssertTrue(manager.snapshots[0].error?.contains("404") ?? false)
    }

    /// An Atlassian page answers 404 on the PagerDuty path, and a Statuspage
    /// summary must not decode as impacted services.
    func testStatuspagePayloadIsNotRecognised() async {
        stubHealthyPage()
        stub("/api/impacted_services", #"{"page":{"name":"X"},"status":{"indicator":"none"}}"#)
        let manager = makeManager()
        let provider = Provider(name: "Example", baseURL: base, type: .pagerduty)
        manager.providers = [provider]

        await manager.poll(provider: provider)

        XCTAssertEqual(manager.snapshots[0].error, "Status format not recognized")
    }
}
