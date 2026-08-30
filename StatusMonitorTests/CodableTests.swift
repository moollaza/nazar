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

    // MARK: - Better Stack index.json decoding
    //
    // Shape documented at https://betterstack.com/docs/uptime/status-pages/subscribing-to-status-updates/subscribing-to-api/

    private let betterStackJSON = """
    {
      "data": { "attributes": { "aggregate_state": "degraded" } },
      "included": [
        { "id": "s1", "type": "status_page_section", "attributes": { "name": "Core" } },
        { "id": "r1", "type": "status_page_resource",
          "attributes": { "public_name": "API", "status": "operational", "status_page_section_id": "s1" } },
        { "id": "r2", "type": "status_page_resource",
          "attributes": { "public_name": "Dashboard", "status": "downtime", "status_page_section_id": "s1" } },
        { "id": "r3", "type": "status_page_resource",
          "attributes": { "public_name": "Docs", "status": "not_monitored" } },
        { "id": "u1", "type": "status_update",
          "attributes": { "message": "We are investigating.", "published_at": "2026-01-01T00:00:00Z" } },
        { "id": "rep1", "type": "status_report",
          "attributes": { "title": "Elevated error rates", "report_type": "incident", "aggregate_state": "investigating" },
          "relationships": { "status_updates": { "data": [ { "id": "u1" } ] } } },
        { "id": "rep2", "type": "status_report",
          "attributes": { "title": "Old incident", "report_type": "incident", "aggregate_state": "resolved" } }
      ]
    }
    """

    private func decodeBetterStack(_ json: String) throws -> BetterStackIndex {
        let data = json.data(using: .utf8)!
        return try JSONDecoder().decode(BetterStackIndex.self, from: data)
    }

    func testDecodeBetterStackAggregateState() throws {
        let index = try decodeBetterStack(betterStackJSON)
        XCTAssertEqual(index.data.attributes.aggregateState, "degraded")
    }

    func testDecodeBetterStackIncludedIsPolymorphic() throws {
        let index = try decodeBetterStack(betterStackJSON)
        let included = try XCTUnwrap(index.included)
        XCTAssertEqual(included.count, 7)

        let section = try XCTUnwrap(included.first { $0.id == "s1" })
        XCTAssertEqual(section.type, "status_page_section")
        XCTAssertEqual(section.attributes?.name, "Core")

        let resource = try XCTUnwrap(included.first { $0.id == "r2" })
        XCTAssertEqual(resource.type, "status_page_resource")
        XCTAssertEqual(resource.attributes?.publicName, "Dashboard")
        XCTAssertEqual(resource.attributes?.status, "downtime")
        XCTAssertEqual(resource.attributes?.statusPageSectionId, "s1")

        let report = try XCTUnwrap(included.first { $0.id == "rep1" })
        XCTAssertEqual(report.type, "status_report")
        XCTAssertEqual(report.attributes?.title, "Elevated error rates")
        XCTAssertEqual(report.attributes?.reportType, "incident")
        XCTAssertEqual(report.attributes?.reportAggregateState, "investigating")
        XCTAssertEqual(report.relationships?.statusUpdates?.data?.first?.id, "u1")

        let update = try XCTUnwrap(included.first { $0.id == "u1" })
        XCTAssertEqual(update.type, "status_update")
        XCTAssertEqual(update.attributes?.message, "We are investigating.")
        XCTAssertEqual(update.attributes?.publishedAt, "2026-01-01T00:00:00Z")
    }

    func testDecodeBetterStackWithoutIncluded() throws {
        let json = """
        { "data": { "attributes": { "aggregate_state": "operational" } } }
        """
        let index = try decodeBetterStack(json)
        XCTAssertNil(index.included)
        XCTAssertEqual(index.data.attributes.aggregateState, "operational")
    }

    func testDecodeBetterStackInvalidJSONThrows() {
        let garbage = "not json at all".data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(BetterStackIndex.self, from: garbage))
    }
}
