import XCTest
@testable import StatusMonitor

final class ServiceHistoryTests: XCTestCase {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// Noon on the last of the 28 strip days (Nov 1...Nov 28).
    private let now = ISO8601DateFormatter().date(from: "2026-11-28T12:00:00Z")!
    private let percentWindow: TimeInterval = 28 * 86_400

    private func date(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    private func history(_ intervals: [IncidentInterval]) -> ServiceHistory {
        ServiceHistory(intervals: intervals, now: now, calendar: calendar)
    }

    private func interval(_ start: String, _ end: String?, _ severity: HistorySeverity) -> IncidentInterval {
        IncidentInterval(start: date(start), end: end.map(date), severity: severity)
    }

    func testEmptyHistoryIsAllClearAndFullyIncidentFree() {
        let h = history([])
        XCTAssertEqual(h.days.count, 28)
        XCTAssertTrue(h.days.allSatisfy { $0 == .clear })
        XCTAssertEqual(h.incidentFree, 1)
        XCTAssertEqual(h.incidentFreeText, "100%")
        XCTAssertEqual(h.issueSummary, "No issues in 28 days")
    }

    func testStripUsesCalendarDaysAndPercentUsesARollingWindow() {
        // The rolling window starts Oct 31 12:00; the strip starts Nov 1 00:00.
        let crossing = interval("2026-10-31T18:00:00Z", "2026-11-01T06:00:00Z", .major)
        let old = interval("2026-10-20T00:00:00Z", "2026-10-21T00:00:00Z", .major)
        let h = history([old, crossing])
        XCTAssertEqual(h.day(for: date("2026-11-01T12:00:00Z")), .major)
        XCTAssertNil(h.day(for: date("2026-10-31T12:00:00Z")), "the day before the strip has no entry")
        XCTAssertEqual(h.incidentFree, 1 - 12 * 3600 / percentWindow, accuracy: 1e-9, "all 12h fall in the rolling window")
        XCTAssertEqual(h.issueCount, 1, "the October incident is outside both windows")
        XCTAssertEqual(h.lastIssue, date("2026-10-31T18:00:00Z"), "the last issue keeps its real start")
    }

    func testOverlappingIncidentsCountTheirTimeOnce() {
        let a = interval("2026-11-10T00:00:00Z", "2026-11-10T04:00:00Z", .minor)
        let b = interval("2026-11-10T02:00:00Z", "2026-11-10T06:00:00Z", .major)
        let h = history([a, b])
        XCTAssertEqual(h.incidentFree, 1 - 6 * 3600 / percentWindow, accuracy: 1e-9)
        XCTAssertEqual(h.issueCount, 2)
        XCTAssertEqual(h.day(for: date("2026-11-10T12:00:00Z")), .major, "the worst incident of the day wins")
    }

    func testOngoingIncidentRunsUntilNow() {
        let h = history([interval("2026-11-28T09:00:00Z", nil, .minor)])
        XCTAssertEqual(h.day(for: now), .minor)
        XCTAssertEqual(h.incidentFree, 1 - 3 * 3600 / percentWindow, accuracy: 1e-9)
        XCTAssertEqual(h.issueSummary, "1 issue in 28 days, last today")
    }

    func testMaintenanceShowsButNeverCountsAgainstIncidentFree() {
        let h = history([interval("2026-11-20T00:00:00Z", "2026-11-20T08:00:00Z", .maintenance)])
        XCTAssertEqual(h.day(for: date("2026-11-20T12:00:00Z")), .maintenance)
        XCTAssertEqual(h.incidentFree, 1)
        XCTAssertEqual(h.issueCount, 0)
        XCTAssertEqual(h.incidentFreeText, "100%")
    }

    func testIncidentOutranksMaintenanceOnTheSameDay() {
        let maint = interval("2026-11-20T00:00:00Z", "2026-11-20T02:00:00Z", .maintenance)
        let minor = interval("2026-11-20T10:00:00Z", "2026-11-20T11:00:00Z", .minor)
        XCTAssertEqual(history([maint, minor]).day(for: date("2026-11-20T12:00:00Z")), .minor)
    }

    func testIssueSummaryCountsDaysFromTheLastIncident() {
        let a = interval("2026-11-05T00:00:00Z", "2026-11-05T01:00:00Z", .minor)
        let b = interval("2026-11-26T08:00:00Z", "2026-11-26T09:00:00Z", .major)
        XCTAssertEqual(history([a, b]).issueSummary, "2 issues in 28 days, last 2 days ago")
    }

    func testShortIncidentNeverShowsAsAHundredPercent() {
        let h = history([interval("2026-11-15T00:00:00Z", "2026-11-15T00:01:00Z", .minor)])
        XCTAssertLessThan(h.incidentFree, 1)
        XCTAssertEqual(h.incidentFreeText, "99.9%")
    }

    func testIncidentFreeRoundsDown() {
        // 0.55% incident time is 99.45% incident-free, shown as 99.4%.
        let start = date("2026-11-12T00:00:00Z")
        let h = history([IncidentInterval(start: start, end: start.addingTimeInterval(percentWindow * 0.0055), severity: .major)])
        XCTAssertEqual(h.incidentFreeText, "99.4%")
    }

    // MARK: - Statuspage mapper

    func testStatuspageFeedMapsImpactAndEndTimes() throws {
        let json = #"""
        {"incidents": [
          {"id": "a", "status": "resolved", "impact": "critical", "created_at": "2026-11-10T00:00:00.000Z",
           "started_at": "2026-11-09T23:50:00.000Z", "resolved_at": "2026-11-10T01:00:00.000Z", "updated_at": "2026-11-10T01:05:00.000Z"},
          {"id": "b", "status": "resolved", "impact": "minor", "created_at": "2026-11-11T00:00:00Z", "updated_at": "2026-11-11T02:00:00Z"},
          {"id": "c", "status": "investigating", "impact": "major", "created_at": "2026-11-28T10:00:00Z", "updated_at": "2026-11-28T10:05:00Z"},
          {"id": "d", "status": "resolved", "impact": "none", "created_at": "2026-11-12T00:00:00Z", "updated_at": "2026-11-12T01:00:00Z"},
          {"id": "e", "status": "completed", "impact": "maintenance", "created_at": "2026-11-01T00:00:00Z",
           "scheduled_for": "2026-11-13T00:00:00Z", "scheduled_until": "2026-11-13T02:00:00Z"},
          {"id": "f", "status": "scheduled", "impact": "maintenance", "created_at": "2026-11-20T00:00:00Z",
           "scheduled_for": "2026-12-01T00:00:00Z", "scheduled_until": "2026-12-01T02:00:00Z"}
        ]}
        """#
        let list = try JSONDecoder().decode(StatuspageIncidentList.self, from: Data(json.utf8))
        let intervals = list.incidents.compactMap(IncidentInterval.init(statuspage:))
        XCTAssertEqual(intervals.count, 4, "impact none and not-yet-started maintenance are dropped")
        XCTAssertEqual(intervals[0], interval("2026-11-09T23:50:00Z", "2026-11-10T01:00:00Z", .major),
                       "started_at wins over created_at, critical counts as major")
        XCTAssertEqual(intervals[1].end, date("2026-11-11T02:00:00Z"), "a resolved incident without resolved_at ends at its last update")
        XCTAssertNil(intervals[2].end, "an open incident has no end")
        XCTAssertEqual(intervals[3], interval("2026-11-13T00:00:00Z", "2026-11-13T02:00:00Z", .maintenance),
                       "maintenance uses its scheduled window")
    }

    // MARK: - Datadog mapper

    func testDatadogHistoryMapsIncidentsAndMaintenance() throws {
        let json = #"""
        {"name": "Example", "components": [],
         "incidents": [
           {"id": "r", "resolved": true, "publishedDate": "2026-11-10T00:00:00.000Z", "resolvedDate": "2026-11-10T02:00:00.000Z",
            "componentsAffected": [{"id": "c1", "name": "API", "status": "major_outage"}]},
           {"id": "u", "resolved": false, "publishedDate": "2026-11-28T08:00:00.000Z",
            "componentsAffected": [{"id": "c2", "name": "Web", "status": "partial_outage"}]},
           {"id": "n", "resolved": true, "publishedDate": "2026-11-15T00:00:00.000Z", "resolvedDate": "2026-11-15T01:00:00.000Z"}
         ],
         "maintenances": [
           {"id": "m", "scheduledStartDate": "2026-11-20T00:00:00.000Z", "scheduledEndDate": "2026-11-20T04:00:00.000Z"}
         ]}
        """#
        let config = try JSONDecoder().decode(DatadogConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.historyIntervals, [
            interval("2026-11-10T00:00:00Z", "2026-11-10T02:00:00Z", .major),
            interval("2026-11-28T08:00:00Z", nil, .minor),
            interval("2026-11-15T00:00:00Z", "2026-11-15T01:00:00Z", .minor),
            interval("2026-11-20T00:00:00Z", "2026-11-20T04:00:00Z", .maintenance),
        ], "unresolved stays open; no affected component defaults to minor")
    }
}

@MainActor
final class HistoryStoreTests: XCTestCase {
    private let url = URL(string: "https://status.example.com/api/v2/incidents.json")!
    private let provider = Provider(name: "Example", baseURL: "https://status.example.com")
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private var session: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func feed(_ id: String) -> Data {
        Data(#"{"incidents": [{"id": "\#(id)", "status": "resolved", "impact": "minor", "created_at": "2026-11-10T00:00:00Z", "resolved_at": "2026-11-10T01:00:00Z"}]}"#.utf8)
    }

    override func tearDown() {
        StubURLProtocol.clearStubs()
        super.tearDown()
    }

    func testFetchesAtMostOnceAnHour() async {
        let store = HistoryStore()
        StubURLProtocol.register(url: url, response: (feed("a"), 200))
        await store.refreshIfNeeded(provider: provider, session: session, now: start) { _ in true }?.value
        XCTAssertEqual(store.intervals[provider.id]?.count, 1)

        let soon = store.refreshIfNeeded(provider: provider, session: session, now: start.addingTimeInterval(1800)) { _ in true }
        XCTAssertNil(soon, "a second fetch within the hour is skipped")
        let later = store.refreshIfNeeded(provider: provider, session: session, now: start.addingTimeInterval(3600)) { _ in true }
        XCTAssertNotNil(later, "after an hour it fetches again")
        await later?.value
    }

    func testFailedFetchKeepsTheLastGoodHistory() async {
        let store = HistoryStore()
        StubURLProtocol.register(url: url, response: (feed("a"), 200))
        await store.refreshIfNeeded(provider: provider, session: session, now: start) { _ in true }?.value
        let good = store.intervals[provider.id]
        XCTAssertNotNil(good)

        StubURLProtocol.register(url: url, response: (Data("oops".utf8), 500))
        await store.refreshIfNeeded(provider: provider, session: session, now: start.addingTimeInterval(3600)) { _ in true }?.value
        XCTAssertEqual(store.intervals[provider.id], good)
    }

    func testDropsAResultForARemovedProvider() async {
        let store = HistoryStore()
        StubURLProtocol.register(url: url, response: (feed("a"), 200))
        await store.refreshIfNeeded(provider: provider, session: session, now: start) { _ in false }?.value
        XCTAssertNil(store.intervals[provider.id])
    }
}
