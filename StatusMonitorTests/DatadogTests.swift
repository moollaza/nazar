import XCTest
@testable import StatusMonitor

final class DatadogTests: XCTestCase {

    // MARK: - Status mapping

    func testFromDatadogOperational() {
        XCTAssertEqual(ComponentStatus(fromDatadog: "operational"), .operational)
    }

    func testFromDatadogDegraded() {
        XCTAssertEqual(ComponentStatus(fromDatadog: "degraded"), .degradedPerformance)
    }

    func testFromDatadogPartialOutage() {
        XCTAssertEqual(ComponentStatus(fromDatadog: "partial_outage"), .partialOutage)
    }

    func testFromDatadogDown() {
        XCTAssertEqual(ComponentStatus(fromDatadog: "down"), .majorOutage)
    }

    func testFromDatadogMaintenance() {
        XCTAssertEqual(ComponentStatus(fromDatadog: "maintenance"), .underMaintenance)
    }

    /// Datadog's own vocabulary is not fully documented, so an unrecognised
    /// value must surface as Unknown rather than masquerading as healthy.
    func testFromDatadogUnknownString() {
        XCTAssertEqual(ComponentStatus(fromDatadog: "garbage"), .unknown)
    }

    func testFromDatadogIsCaseAndSeparatorInsensitive() {
        XCTAssertEqual(ComponentStatus(fromDatadog: "DegradedPerformance"), .degradedPerformance)
        XCTAssertEqual(ComponentStatus(fromDatadog: "MAJOR_OUTAGE"), .majorOutage)
    }

    // MARK: - Decoding

    /// Trimmed from https://status.jasper.ai/config.json — the healthy case,
    /// where `incidents` is present but holds only resolved history.
    private let healthyJSON = """
    {
      "name": "Jasper Status",
      "domainPrefix": "jasper",
      "customDomain": "status.jasper.ai",
      "components": [
        {"id": "c1", "name": "Application", "position": 0, "status": "operational", "type": "Component"},
        {"id": "c2", "name": "AI Engine", "position": 1, "status": "operational", "type": "Component"}
      ],
      "incidents": [
        {
          "id": "i1",
          "title": "Elevated errors caused by a Google Cloud incident",
          "description": "The issue is now resolved.",
          "currentStatus": "resolved",
          "resolved": true,
          "publishedDate": "2026-09-01T16:41:48.123867Z",
          "resolvedDate": "2026-09-01T16:50:19.244657Z",
          "componentsAffected": [
            {"id": "c1", "name": "Application", "position": 0, "status": "operational", "type": "Component"}
          ],
          "timeline": [
            {"id": "t1", "status": "resolved", "description": "The issue is now resolved.",
             "createdAt": "2026-09-01T16:50:19.244657Z", "startedAt": "2026-09-01T16:50:19.244657Z"}
          ]
        }
      ],
      "maintenances": null
    }
    """

    /// The same page shape with one open incident.
    private let incidentJSON = """
    {
      "name": "Jasper Status",
      "components": [
        {"id": "c1", "name": "Application", "position": 0, "status": "degraded", "type": "Component"},
        {"id": "c2", "name": "AI Engine", "position": 1, "status": "operational", "type": "Component"}
      ],
      "incidents": [
        {
          "id": "i2",
          "title": "Generation requests failing",
          "currentStatus": "investigating",
          "resolved": false,
          "publishedDate": "2026-09-24T10:00:00.5Z",
          "componentsAffected": [
            {"id": "c1", "name": "Application", "position": 0, "status": "degraded", "type": "Component"}
          ],
          "timeline": [
            {"id": "t2", "status": "investigating", "description": "We are looking into it.",
             "createdAt": "2026-09-24T10:00:00.5Z"}
          ]
        }
      ]
    }
    """

    func testDecodesHealthyPage() throws {
        let config = try JSONDecoder().decode(DatadogConfig.self, from: Data(healthyJSON.utf8))
        XCTAssertEqual(config.name, "Jasper Status")
        XCTAssertEqual(config.components.count, 2)
        XCTAssertEqual(config.incidents?.count, 1)
        XCTAssertNil(config.maintenances)
    }

    /// `incidents` is the page's full history, not a list of open incidents.
    /// Without the `resolved` filter every past outage would read as active.
    func testResolvedIncidentsAreFilteredOut() throws {
        let config = try JSONDecoder().decode(DatadogConfig.self, from: Data(healthyJSON.utf8))
        let open = (config.incidents ?? []).filter { $0.resolved != true }
        XCTAssertTrue(open.isEmpty)
    }

    func testDecodesOpenIncident() throws {
        let config = try JSONDecoder().decode(DatadogConfig.self, from: Data(incidentJSON.utf8))
        let open = try XCTUnwrap((config.incidents ?? []).first { $0.resolved != true })
        XCTAssertEqual(open.title, "Generation requests failing")
        XCTAssertEqual(open.currentStatus, "investigating")
        XCTAssertEqual(open.timeline?.first?.description, "We are looking into it.")
    }

    /// There is no page-level rollup on a Datadog page, so overall status has
    /// to come from the components.
    func testOverallStatusDerivesFromComponents() throws {
        let config = try JSONDecoder().decode(DatadogConfig.self, from: Data(incidentJSON.utf8))
        let worst = config.components
            .map { ComponentStatus(fromDatadog: $0.status ?? "") }
            .max() ?? .operational
        XCTAssertEqual(worst, .degradedPerformance)
    }

    func testHealthyPageOverallIsOperational() throws {
        let config = try JSONDecoder().decode(DatadogConfig.self, from: Data(healthyJSON.utf8))
        let worst = config.components
            .map { ComponentStatus(fromDatadog: $0.status ?? "") }
            .max() ?? .operational
        XCTAssertEqual(worst, .operational)
    }

    /// A component list is the one field the parser cannot work without.
    func testPayloadWithoutComponentsDoesNotDecode() {
        let shell = """
        {"name": "Status Pages Site"}
        """
        XCTAssertThrowsError(
            try JSONDecoder().decode(DatadogConfig.self, from: Data(shell.utf8))
        )
    }

    /// An Atlassian summary nests components differently enough that it must
    /// not silently decode as a Datadog page.
    func testAtlassianPayloadDoesNotDecodeAsDatadog() {
        let atlassian = """
        {"page":{"name":"GitHub","url":"https://www.githubstatus.com"},
         "status":{"indicator":"none","description":"All Systems Operational"}}
        """
        XCTAssertThrowsError(
            try JSONDecoder().decode(DatadogConfig.self, from: Data(atlassian.utf8))
        )
    }

    /// Components carry a `position`; the parser orders by it so the app shows
    /// them in the same order the status page does.
    func testComponentsSortByPosition() throws {
        let json = """
        {"name":"X","components":[
          {"id":"b","name":"B","position":1,"status":"operational"},
          {"id":"a","name":"A","position":0,"status":"operational"}]}
        """
        let config = try JSONDecoder().decode(DatadogConfig.self, from: Data(json.utf8))
        let ordered = config.components.sorted { ($0.position ?? Int.max) < ($1.position ?? Int.max) }
        XCTAssertEqual(ordered.map(\.id), ["a", "b"])
    }

    // MARK: - Provider wiring

    func testDatadogProviderUsesConfigEndpoint() {
        let provider = Provider(name: "Jasper", baseURL: "https://status.jasper.ai", type: .datadog)
        XCTAssertEqual(provider.apiURL?.absoluteString, "https://status.jasper.ai/config.json")
    }

    func testDatadogIsACatalogProviderType() {
        XCTAssertEqual(ProviderType(rawValue: "datadog"), .datadog)
        XCTAssertTrue(ProviderType.allCases.contains(.datadog))
    }
}
