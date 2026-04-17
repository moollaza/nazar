import XCTest
@testable import StatusMonitor

/// Fixture-based tests for the real RSS shapes that AWS and Azure publish.
/// These guard against regressions in the RSS parser if Apple ever changes
/// XMLParser CDATA behavior, or if a refactor of the status heuristic
/// changes precedence rules.
final class CloudProviderRSSTests: XCTestCase {

    // MARK: - AWS

    /// AWS global feed: CDATA-wrapped titles + descriptions, RFC-822 dates
    /// with regional timezone suffixes (PST/PDT), nested paragraph breaks
    /// inside descriptions. The fields that matter for us: title, description,
    /// pubDate, and guid.
    private let awsFixture = #"""
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0">
      <channel>
        <title><![CDATA[Amazon Web Services Service Status]]></title>
        <link>https://status.aws.amazon.com/</link>
        <language>en-us</language>
        <lastBuildDate>Thu, 16 Apr 2026 13:49:14 PDT</lastBuildDate>
        <generator>AWS Service Health Dashboard RSS Generator</generator>
        <description><![CDATA[Recent AWS events]]></description>
        <ttl>5</ttl>
        <item>
          <title><![CDATA[Service impact: Increased Connectivity Issues and API Error Rates]]></title>
          <link>https://status.aws.amazon.com/</link>
          <pubDate>Tue, 03 Mar 2026 08:40:00 PST</pubDate>
          <guid isPermaLink="false">https://status.aws.amazon.com/#multipleservices-me-south-1_1772556000</guid>
          <description><![CDATA[We are providing an update on the ongoing service disruptions affecting the AWS Middle East (Bahrain) Region (ME-SOUTH-1).]]></description>
        </item>
        <item>
          <title><![CDATA[Resolved: Informational message: Recovery underway]]></title>
          <link>https://status.aws.amazon.com/</link>
          <pubDate>Mon, 02 Mar 2026 17:00:00 PST</pubDate>
          <guid isPermaLink="false">https://status.aws.amazon.com/#s3-us-east-1_1772456400</guid>
          <description><![CDATA[The issue has been resolved and the service is operating normally.]]></description>
        </item>
      </channel>
    </rss>
    """#.data(using: .utf8)!

    func testAWSFeedParsesCDATAFields() throws {
        let items = try RSSStatusParser(data: awsFixture).parse()
        XCTAssertEqual(items.count, 2)

        // CDATA title preserved
        XCTAssertEqual(items[0].title, "Service impact: Increased Connectivity Issues and API Error Rates")
        // CDATA description preserved
        XCTAssertTrue(items[0].description.contains("AWS Middle East (Bahrain)"))
        // GUID present
        XCTAssertTrue(items[0].guid?.contains("me-south-1") ?? false)
        // RFC-822 date with PST suffix parsed
        XCTAssertNotNil(items[0].pubDate)
    }

    func testAWSFirstItemIsActiveOutage() {
        // Most-recent item in fixture describes an active impact → heuristic
        // must not be tricked into resolved by the word "issue" or "ongoing"
        // appearing in an active description.
        let status = StatusManager.rssStatusHeuristic(
            title: "Service impact: Increased Connectivity Issues and API Error Rates",
            description: "We are providing an update on the ongoing service disruptions affecting AWS ME-SOUTH-1."
        )
        // "issue" triggers nothing directly; "impact" not in the keyword set;
        // the description has neither "major" nor "outage" — this is why a
        // real catalog user notices AWS coverage is heuristic-limited.
        // Document the current behavior explicitly so a refactor doesn't drift.
        XCTAssertEqual(status, .unknown,
                       "AWS's non-Atlassian phrasing is not matched by current heuristic keywords — " +
                       "documenting this so any future heuristic change is deliberate")
    }

    func testAWSResolvedItemClassifiesOperational() {
        let status = StatusManager.rssStatusHeuristic(
            title: "Resolved: Informational message: Recovery underway",
            description: "The issue has been resolved and the service is operating normally."
        )
        XCTAssertEqual(status, .operational,
                       "'Resolved' in title must beat every other keyword")
    }

    // MARK: - Azure

    /// Azure feed between incidents: valid RSS envelope with no <item>
    /// elements. Our parser must treat this as "no current incidents" rather
    /// than throwing or returning unknown.
    private let azureEmptyFixture = #"""
    <?xml version="1.0" encoding="utf-8"?>
    <rss version="2.0">
      <channel>
        <title>Azure Status</title>
        <link>https://azure.status.microsoft/en-us/status/</link>
        <description>Azure Status</description>
        <language>en-us</language>
        <lastBuildDate>Thu, 16 Apr 2026 20:49:00 Z</lastBuildDate>
      </channel>
    </rss>
    """#.data(using: .utf8)!

    func testAzureEmptyFeedIsParsedWithoutError() throws {
        let items = try RSSStatusParser(data: azureEmptyFixture).parse()
        XCTAssertTrue(items.isEmpty)
    }

    /// Hypothetical Azure feed during an incident — testing that our parser
    /// handles the namespaced RSS+Atom combination Azure uses.
    private let azureIncidentFixture = #"""
    <?xml version="1.0" encoding="utf-8"?>
    <rss xmlns:a10="http://www.w3.org/2005/Atom" version="2.0">
      <channel>
        <title>Azure Status</title>
        <link>https://azure.status.microsoft/en-us/status/</link>
        <description>Azure Status</description>
        <item>
          <title>Degraded connectivity - East US</title>
          <pubDate>Thu, 16 Apr 2026 18:00:00 Z</pubDate>
          <guid>azure-eastus-2026-04-16-001</guid>
          <description>We are investigating degraded network connectivity in East US.</description>
        </item>
      </channel>
    </rss>
    """#.data(using: .utf8)!

    func testAzureIncidentFeedParses() throws {
        let items = try RSSStatusParser(data: azureIncidentFixture).parse()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "Degraded connectivity - East US")
        XCTAssertNotNil(items[0].pubDate)
    }

    func testAzureDegradedItemClassifiesDegraded() {
        let status = StatusManager.rssStatusHeuristic(
            title: "Degraded connectivity - East US",
            description: "We are investigating degraded network connectivity."
        )
        XCTAssertEqual(status, .degradedPerformance)
    }

    // MARK: - Catalog entries wired correctly

    func testCatalogHasAWSEntry() {
        let aws = Catalog.shared.entries.first(where: { $0.id == "aws" })
        XCTAssertNotNil(aws)
        XCTAssertEqual(aws?.type, .rss)
        XCTAssertTrue(aws?.baseURL.contains("status.aws.amazon.com") ?? false)
        XCTAssertEqual(aws?.category, "Cloud & Hosting")
    }

    func testCatalogHasAzureEntry() {
        let azure = Catalog.shared.entries.first(where: { $0.id == "azure" })
        XCTAssertNotNil(azure)
        XCTAssertEqual(azure?.type, .rss)
        XCTAssertTrue(azure?.baseURL.contains("azure.status.microsoft") ?? false)
        XCTAssertEqual(azure?.category, "Cloud & Hosting")
    }
}
