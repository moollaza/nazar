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

    private func parseRSS(_ xml: String) -> [RSSItem] {
        let data = xml.data(using: .utf8)!
        return RSSStatusParser(data: data).parse()
    }

    // MARK: - RSS parsing

    func testParseRSSItemCount() {
        let items = parseRSS(sampleRSS)
        XCTAssertEqual(items.count, 2)
    }

    func testParseRSSItemTitle() {
        let items = parseRSS(sampleRSS)
        XCTAssertEqual(items[0].title, "Major outage in US-East")
    }

    func testParseRSSItemDescription() {
        let items = parseRSS(sampleRSS)
        XCTAssertEqual(items[0].description, "We are investigating a major outage.")
    }

    func testParseRSSItemGuid() {
        let items = parseRSS(sampleRSS)
        XCTAssertEqual(items[0].guid, "item-1")
    }

    func testParseRSSItemPubDate() {
        let items = parseRSS(sampleRSS)
        XCTAssertNotNil(items[0].pubDate, "pubDate should be parsed from RFC 822 format")
    }

    func testParseRSSDateRFC822() {
        let items = parseRSS(sampleRSS)
        let date = items[0].pubDate
        XCTAssertNotNil(date)
        // Verify the date is roughly Jan 1, 2026
        if let date = date {
            let cal = Calendar(identifier: .gregorian)
            let components = cal.dateComponents(in: TimeZone(identifier: "UTC")!, from: date)
            XCTAssertEqual(components.year, 2026)
            XCTAssertEqual(components.month, 1)
            XCTAssertEqual(components.day, 1)
        }
    }

    // MARK: - Atom parsing

    func testParseAtomEntry() {
        let items = parseRSS(sampleAtom)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "Degraded performance on EU cluster")
    }

    func testParseAtomSummary() {
        let items = parseRSS(sampleAtom)
        XCTAssertEqual(items[0].description, "Elevated error rates observed.")
    }

    func testParseAtomId() {
        let items = parseRSS(sampleAtom)
        XCTAssertEqual(items[0].guid, "entry-1")
    }

    func testParseAtomPublished() {
        let items = parseRSS(sampleAtom)
        XCTAssertNotNil(items[0].pubDate, "Atom <published> should be parsed as pubDate")
    }

    // MARK: - Edge cases

    func testParseEmptyFeed() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0"><channel><title>Empty</title></channel></rss>
        """
        let items = parseRSS(xml)
        XCTAssertTrue(items.isEmpty)
    }

    func testParseInvalidXML() {
        let data = "<<<not valid xml>>>".data(using: .utf8)!
        let items = RSSStatusParser(data: data).parse()
        XCTAssertTrue(items.isEmpty, "Invalid XML should return empty array, not crash")
    }

    func testParseEmptyData() {
        let items = RSSStatusParser(data: Data()).parse()
        XCTAssertTrue(items.isEmpty, "Empty data should return empty array")
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
