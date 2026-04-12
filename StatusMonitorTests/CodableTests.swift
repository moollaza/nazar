import XCTest
@testable import StatusMonitor

final class CodableTests: XCTestCase {

    // MARK: - Atlassian full response

    private let atlassianJSON = """
    {
      "page": { "name": "GitHub", "url": "https://www.githubstatus.com", "updated_at": "2026-01-01T00:00:00Z" },
      "status": { "indicator": "none", "description": "All Systems Operational" },
      "components": [
        { "id": "abc123", "name": "Git Operations", "status": "operational", "description": "Git pulls and pushes", "updated_at": "2026-01-01T00:00:00Z" },
        { "id": "def456", "name": "API Requests", "status": "degraded_performance", "description": null, "updated_at": "2026-01-01T00:00:00Z" }
      ],
      "incidents": [
        {
          "id": "inc1", "name": "Elevated error rates", "status": "investigating", "impact": "minor",
          "created_at": "2026-01-01T00:00:00Z", "updated_at": "2026-01-01T00:00:00Z",
          "incident_updates": [
            { "id": "upd1", "status": "investigating", "body": "We are investigating.", "created_at": "2026-01-01T00:00:00Z" }
          ]
        }
      ],
      "scheduled_maintenances": []
    }
    """

    private let incidentIOJSON = """
    {
      "page": { "name": "OpenAI", "url": "https://status.openai.com" },
      "status": { "indicator": "none", "description": "All Systems Operational" },
      "components": [
        { "id": "xyz789", "name": "API", "status": "operational" }
      ]
    }
    """

    private func decode(_ json: String) throws -> StatuspageSummary {
        let data = json.data(using: .utf8)!
        return try JSONDecoder().decode(StatuspageSummary.self, from: data)
    }

    // MARK: - Atlassian decoding

    func testDecodeAtlassianFullResponse() throws {
        let summary = try decode(atlassianJSON)
        XCTAssertEqual(summary.page.name, "GitHub")
        XCTAssertEqual(summary.components.count, 2)
        XCTAssertNotNil(summary.incidents)
        XCTAssertNotNil(summary.scheduledMaintenances)
    }

    func testDecodeAtlassianPageFields() throws {
        let summary = try decode(atlassianJSON)
        XCTAssertEqual(summary.page.name, "GitHub")
        XCTAssertEqual(summary.page.url, "https://www.githubstatus.com")
        XCTAssertEqual(summary.page.updatedAt, "2026-01-01T00:00:00Z")
    }

    func testDecodeAtlassianStatusFields() throws {
        let summary = try decode(atlassianJSON)
        XCTAssertEqual(summary.status.indicator, "none")
        XCTAssertEqual(summary.status.description, "All Systems Operational")
    }

    func testDecodeAtlassianComponents() throws {
        let summary = try decode(atlassianJSON)
        XCTAssertEqual(summary.components.count, 2)
        XCTAssertEqual(summary.components[0].id, "abc123")
        XCTAssertEqual(summary.components[0].name, "Git Operations")
        XCTAssertEqual(summary.components[0].status, "operational")
        XCTAssertEqual(summary.components[1].id, "def456")
        XCTAssertEqual(summary.components[1].status, "degraded_performance")
    }

    func testDecodeAtlassianComponentOptionalDescription() throws {
        let summary = try decode(atlassianJSON)
        XCTAssertEqual(summary.components[0].description, "Git pulls and pushes")
        XCTAssertNil(summary.components[1].description)
    }

    func testDecodeAtlassianIncidents() throws {
        let summary = try decode(atlassianJSON)
        XCTAssertEqual(summary.incidents?.count, 1)
        let incident = try XCTUnwrap(summary.incidents?.first)
        XCTAssertEqual(incident.id, "inc1")
        XCTAssertEqual(incident.name, "Elevated error rates")
        XCTAssertEqual(incident.status, "investigating")
        XCTAssertEqual(incident.impact, "minor")
        XCTAssertEqual(incident.incidentUpdates?.count, 1)
    }

    func testDecodeAtlassianScheduledMaintenances() throws {
        let summary = try decode(atlassianJSON)
        XCTAssertNotNil(summary.scheduledMaintenances)
        XCTAssertEqual(summary.scheduledMaintenances?.count, 0)
    }

    func testIncidentUpdateFields() throws {
        let summary = try decode(atlassianJSON)
        let update = try XCTUnwrap(summary.incidents?.first?.incidentUpdates?.first)
        XCTAssertEqual(update.id, "upd1")
        XCTAssertEqual(update.status, "investigating")
        XCTAssertEqual(update.body, "We are investigating.")
        XCTAssertEqual(update.createdAt, "2026-01-01T00:00:00Z")
    }

    // MARK: - incident.io minimal response

    func testDecodeIncidentIOMinimalResponse() throws {
        let summary = try decode(incidentIOJSON)
        XCTAssertEqual(summary.page.name, "OpenAI")
        XCTAssertEqual(summary.components.count, 1)
    }

    func testDecodeIncidentIOPageNoUpdatedAt() throws {
        let summary = try decode(incidentIOJSON)
        XCTAssertNil(summary.page.updatedAt)
    }

    func testDecodeIncidentIOComponentNoDescription() throws {
        let summary = try decode(incidentIOJSON)
        XCTAssertNil(summary.components[0].description)
    }

    func testDecodeIncidentIOComponentNoUpdatedAt() throws {
        let summary = try decode(incidentIOJSON)
        XCTAssertNil(summary.components[0].updatedAt)
    }

    func testDecodeIncidentIOMissingIncidents() throws {
        let summary = try decode(incidentIOJSON)
        XCTAssertNil(summary.incidents)
    }

    func testDecodeIncidentIOMissingScheduledMaintenances() throws {
        let summary = try decode(incidentIOJSON)
        XCTAssertNil(summary.scheduledMaintenances)
    }

    // MARK: - Edge cases

    func testDecodeInvalidJSONThrows() {
        let garbage = "not json at all".data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(StatuspageSummary.self, from: garbage))
    }

    func testDecodeEmptyComponentsArray() throws {
        let json = """
        {
          "page": { "name": "Test", "url": "https://test.com" },
          "status": { "indicator": "none", "description": "OK" },
          "components": []
        }
        """
        let summary = try decode(json)
        XCTAssertEqual(summary.components.count, 0)
    }
}
