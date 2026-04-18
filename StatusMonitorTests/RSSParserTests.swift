import XCTest
@testable import StatusMonitor

final class RSSParserTests: XCTestCase {

    // MARK: - Sample data

    private let sampleRSS = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0">
      <channel>
        <title>Service Status</title>
        <item>
          <title>Major outage in US-East</title>
          <description>We are investigating a major outage.</description>
          <guid>item-1</guid>
          <pubDate>Mon, 01 Jan 2026 00:00:00 +0000</pubDate>
        </item>
        <item>
          <title>Resolved: API latency</title>
          <description>This incident has been resolved.</description>
          <guid>item-2</guid>
          <pubDate>Sun, 31 Dec 2025 12:00:00 +0000</pubDate>
        </item>
      </channel>
    </rss>
    """

    private let sampleAtom = """
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>Service Status</title>
      <entry>
        <title>Degraded performance on EU cluster</title>
        <summary>Elevated error rates observed.</summary>
        <id>entry-1</id>
        <published>2026-01-01T00:00:00Z</published>
      </entry>
    </feed>
    """

    private func parseRSS(_ xml: String) throws -> [RSSItem] {
        let data = xml.data(using: .utf8)!
        return try RSSStatusParser(data: data).parse()
    }

    // MARK: - RSS parsing

    func testParseRSSItemCount() throws {
        let items = try parseRSS(sampleRSS)
        XCTAssertEqual(items.count, 2)
    }

    func testParseRSSItemTitle() throws {
        let items = try parseRSS(sampleRSS)
        XCTAssertEqual(items[0].title, "Major outage in US-East")
    }

    func testParseRSSItemDescription() throws {
        let items = try parseRSS(sampleRSS)
        XCTAssertEqual(items[0].description, "We are investigating a major outage.")
    }

    func testParseRSSItemGuid() throws {
        let items = try parseRSS(sampleRSS)
        XCTAssertEqual(items[0].guid, "item-1")
    }

    func testParseRSSItemPubDate() throws {
        let items = try parseRSS(sampleRSS)
        XCTAssertNotNil(items[0].pubDate, "pubDate should be parsed from RFC 822 format")
    }

    func testParseRSSDateRFC822() throws {
        let items = try parseRSS(sampleRSS)
        let date = items[0].pubDate
        XCTAssertNotNil(date)
        if let date = date {
            let cal = Calendar(identifier: .gregorian)
            let components = cal.dateComponents(in: TimeZone(identifier: "UTC")!, from: date)
            XCTAssertEqual(components.year, 2026)
            XCTAssertEqual(components.month, 1)
            XCTAssertEqual(components.day, 1)
        }
    }

    // MARK: - CDATA

    func testParseCDATADescription() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0"><channel>
          <item>
            <title>Incident</title>
            <description><![CDATA[<p>We are <b>investigating</b> the issue.</p>]]></description>
          </item>
        </channel></rss>
        """
        let items = try parseRSS(xml)
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items[0].description.contains("investigating"),
                      "Description must capture CDATA payload (the common case for status-page RSS)")
    }

    // MARK: - Atom parsing

    func testParseAtomEntry() throws {
        let items = try parseRSS(sampleAtom)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "Degraded performance on EU cluster")
    }

    func testParseAtomSummary() throws {
        let items = try parseRSS(sampleAtom)
        XCTAssertEqual(items[0].description, "Elevated error rates observed.")
    }

    func testParseAtomId() throws {
        let items = try parseRSS(sampleAtom)
        XCTAssertEqual(items[0].guid, "entry-1")
    }

    func testParseAtomPublished() throws {
        let items = try parseRSS(sampleAtom)
        XCTAssertNotNil(items[0].pubDate, "Atom <published> should be parsed as pubDate")
    }

    // MARK: - Edge cases

    func testParseEmptyFeed() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0"><channel><title>Empty</title></channel></rss>
        """
        let items = try parseRSS(xml)
        XCTAssertTrue(items.isEmpty)
    }

    func testParseInvalidXMLThrows() {
        let data = "<<<not valid xml>>>".data(using: .utf8)!
        XCTAssertThrowsError(try RSSStatusParser(data: data).parse(),
                             "Malformed XML must surface as an error, not an empty list")
    }

    func testParseEmptyDataThrows() {
        XCTAssertThrowsError(try RSSStatusParser(data: Data()).parse(),
                             "Empty data must surface as an error")
    }

    // MARK: - RSS status heuristic (via StatusManager.rssStatusHeuristic)

    func testHeuristicMajorOutage() {
        let status = StatusManager.rssStatusHeuristic(title: "Major outage in US-East", description: "")
        XCTAssertEqual(status, .majorOutage)
    }

    func testHeuristicOutageKeyword() {
        let status = StatusManager.rssStatusHeuristic(title: "Service outage detected", description: "")
        XCTAssertEqual(status, .majorOutage)
    }

    func testHeuristicPartialOutage() {
        let status = StatusManager.rssStatusHeuristic(title: "Partial service disruption", description: "")
        XCTAssertEqual(status, .partialOutage)
    }

    func testHeuristicDegraded() {
        let status = StatusManager.rssStatusHeuristic(title: "Degraded API performance", description: "")
        XCTAssertEqual(status, .degradedPerformance)
    }

    func testHeuristicElevated() {
        let status = StatusManager.rssStatusHeuristic(title: "Normal title", description: "Elevated error rates observed")
        XCTAssertEqual(status, .degradedPerformance)
    }

    func testHeuristicResolved() {
        let status = StatusManager.rssStatusHeuristic(title: "Resolved: API latency", description: "")
        XCTAssertEqual(status, .operational)
    }

    func testHeuristicResolvedPrecedesMajor() {
        // Regression: "Resolved: Major outage ..." is the most common
        // post-incident message on status feeds. The old heuristic matched
        // "major" first, flagging an active outage for a healed incident.
        let status = StatusManager.rssStatusHeuristic(title: "Resolved: Major outage in us-east", description: "")
        XCTAssertEqual(status, .operational,
                       "'Resolved' must beat 'major' — resolution messages are not active outages")
    }

    func testHeuristicCompletedPrecedesOutage() {
        let status = StatusManager.rssStatusHeuristic(title: "Completed: Partial outage maintenance", description: "")
        XCTAssertEqual(status, .operational)
    }

    // MARK: - Atlassian incident lifecycle verbs → degraded

    func testHeuristicInvestigating() {
        let status = StatusManager.rssStatusHeuristic(
            title: "Investigating connectivity issues",
            description: "We are looking into reports of intermittent failures."
        )
        XCTAssertEqual(status, .degradedPerformance,
                       "'Investigating' signals an open incident — should elevate icon")
    }

    func testHeuristicIdentified() {
        let status = StatusManager.rssStatusHeuristic(
            title: "Identified: Database connection pool exhaustion",
            description: "We've found the root cause and are applying a fix."
        )
        XCTAssertEqual(status, .degradedPerformance)
    }

    // MARK: - GCP-style phrasing

    func testHeuristicIncreasedErrorRates() {
        let status = StatusManager.rssStatusHeuristic(
            title: "Vertex AI Gemini API experiencing increased error rates",
            description: ""
        )
        XCTAssertEqual(status, .degradedPerformance,
                       "GCP-style 'increased error rates' should classify as degraded")
    }

    // MARK: - Critical keyword

    func testHeuristicCritical() {
        let status = StatusManager.rssStatusHeuristic(
            title: "Critical: Database replication lag",
            description: ""
        )
        XCTAssertEqual(status, .majorOutage)
    }

    func testHeuristicOperational() {
        let status = StatusManager.rssStatusHeuristic(title: "All systems operational", description: "")
        XCTAssertEqual(status, .operational)
    }

    func testHeuristicUnknown() {
        let status = StatusManager.rssStatusHeuristic(title: "Scheduled update notice", description: "Routine update")
        XCTAssertEqual(status, .unknown)
    }

    func testHeuristicCaseInsensitive() {
        let status = StatusManager.rssStatusHeuristic(title: "MAJOR OUTAGE", description: "")
        XCTAssertEqual(status, .majorOutage)
    }
}
