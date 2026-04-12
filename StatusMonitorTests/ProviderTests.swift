import XCTest
@testable import StatusMonitor

final class ProviderTests: XCTestCase {

    // MARK: - Default init values

    func testInitDefaultValues() {
        let p = Provider(name: "Test", baseURL: "https://example.com")
        XCTAssertEqual(p.pollIntervalSeconds, 60)
        XCTAssertTrue(p.isEnabled)
        XCTAssertNil(p.catalogEntryId)
        XCTAssertFalse(p.isMuted)
    }

    // MARK: - URL trimming

    func testInitTrimsTrailingSlash() {
        let p = Provider(name: "X", baseURL: "https://example.com/")
        XCTAssertEqual(p.baseURL, "https://example.com")
    }

    func testInitTrimsMultipleTrailingSlashes() {
        let p = Provider(name: "X", baseURL: "https://example.com///")
        XCTAssertEqual(p.baseURL, "https://example.com")
    }

    // MARK: - Poll interval clamping

    func testInitClampsLowPollInterval() {
        let p = Provider(name: "X", baseURL: "https://example.com", pollIntervalSeconds: 10)
        XCTAssertEqual(p.pollIntervalSeconds, 30)
    }

    func testInitClampsBoundaryPollInterval() {
        let p29 = Provider(name: "X", baseURL: "https://example.com", pollIntervalSeconds: 29)
        XCTAssertEqual(p29.pollIntervalSeconds, 30)

        let p30 = Provider(name: "X", baseURL: "https://example.com", pollIntervalSeconds: 30)
        XCTAssertEqual(p30.pollIntervalSeconds, 30)
    }

    func testInitAcceptsHighPollInterval() {
        let p = Provider(name: "X", baseURL: "https://example.com", pollIntervalSeconds: 300)
        XCTAssertEqual(p.pollIntervalSeconds, 300)
    }

    // MARK: - Init from CatalogEntry

    func testInitFromCatalogEntry() {
        let entry = CatalogEntry(id: "github", name: "GitHub",
                                  baseURL: "https://www.githubstatus.com",
                                  type: .statuspage, category: "Developer Tools")
        let p = Provider(from: entry)
        XCTAssertEqual(p.name, "GitHub")
        XCTAssertEqual(p.baseURL, "https://www.githubstatus.com")
        XCTAssertEqual(p.type, .statuspage)
        XCTAssertEqual(p.catalogEntryId, "github")
    }

    func testInitFromCatalogEntryRSSType() {
        let entry = CatalogEntry(id: "rss-service", name: "RSS Service",
                                  baseURL: "https://example.com/rss",
                                  type: .rss, category: "Other")
        let p = Provider(from: entry)
        XCTAssertEqual(p.type, .rss)
    }

    // MARK: - hasValidURL

    func testHasValidURLAcceptsHTTPS() {
        let p = Provider(name: "X", baseURL: "https://status.github.com")
        XCTAssertTrue(p.hasValidURL)
    }

    func testHasValidURLAcceptsHTTP() {
        let p = Provider(name: "X", baseURL: "http://status.github.com")
        XCTAssertTrue(p.hasValidURL)
    }

    func testHasValidURLRejectsNoScheme() {
        let p = Provider(name: "X", baseURL: "status.github.com")
        XCTAssertFalse(p.hasValidURL)
    }

    func testHasValidURLRejectsFTP() {
        let p = Provider(name: "X", baseURL: "ftp://example.com")
        XCTAssertFalse(p.hasValidURL)
    }

    func testHasValidURLRejectsJavascript() {
        let p = Provider(name: "X", baseURL: "javascript:alert(1)")
        XCTAssertFalse(p.hasValidURL)
    }

    func testHasValidURLRejectsEmpty() {
        let p = Provider(name: "X", baseURL: "")
        XCTAssertFalse(p.hasValidURL)
    }

    // MARK: - apiURL

    func testAPIURLStatuspage() {
        let p = Provider(name: "X", baseURL: "https://status.github.com", type: .statuspage)
        XCTAssertEqual(p.apiURL?.absoluteString, "https://status.github.com/api/v2/summary.json")
    }

    func testAPIURLRSS() {
        let p = Provider(name: "X", baseURL: "https://example.com/rss", type: .rss)
        XCTAssertEqual(p.apiURL?.absoluteString, "https://example.com/rss")
    }

    func testAPIURLInvalidBase() {
        let p = Provider(name: "X", baseURL: "not a url")
        // URL(string:) may or may not fail here; just verify it doesn't crash
        // The important thing is hasValidURL catches this case
        _ = p.apiURL
    }

    // MARK: - Codable round-trip

    func testProviderCodableRoundTrip() throws {
        let original = Provider(name: "GitHub", baseURL: "https://status.github.com",
                                type: .statuspage, pollIntervalSeconds: 120,
                                isEnabled: true, catalogEntryId: "github", isMuted: false)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Provider.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.baseURL, original.baseURL)
        XCTAssertEqual(decoded.type, original.type)
        XCTAssertEqual(decoded.pollIntervalSeconds, original.pollIntervalSeconds)
        XCTAssertEqual(decoded.isEnabled, original.isEnabled)
        XCTAssertEqual(decoded.catalogEntryId, original.catalogEntryId)
        XCTAssertEqual(decoded.isMuted, original.isMuted)
    }

    func testProviderCodableRoundTripWithoutIsMuted() throws {
        // Simulate legacy JSON that lacks isMuted field
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "name": "Legacy",
          "baseURL": "https://example.com",
          "type": "statuspage",
          "pollIntervalSeconds": 60,
          "isEnabled": true
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Provider.self, from: data)
        XCTAssertFalse(decoded.isMuted, "isMuted should default to false when missing from JSON")
    }

    func testProviderCodableRoundTripMuted() throws {
        let original = Provider(name: "Muted", baseURL: "https://example.com", isMuted: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Provider.self, from: data)
        XCTAssertTrue(decoded.isMuted)
    }

    // MARK: - Equality

    func testProviderEquality() {
        let p1 = Provider(name: "A", baseURL: "https://a.com")
        let p2 = Provider(name: "B", baseURL: "https://b.com")
        // Different UUIDs => not equal
        XCTAssertNotEqual(p1, p2)
        // Same provider is equal to itself
        XCTAssertEqual(p1, p1)
    }

    // MARK: - Defaults

    func testDefaultsIsEmpty() {
        XCTAssertTrue(Provider.defaults.isEmpty,
                      "Provider.defaults should be empty; onboarding handles initial selection")
    }
}
