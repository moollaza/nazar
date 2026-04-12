import XCTest
@testable import StatusMonitor

final class CatalogTests: XCTestCase {

    // Note: These tests rely on the hosted test target (TEST_HOST / BUNDLE_LOADER)
    // so that Bundle.main resolves to the app bundle containing catalog.json.
    // If Catalog.shared.entries is empty, the test target may not be configured
    // as a hosted unit test — see scripts/add-test-target.md.

    // MARK: - Loading

    func testCatalogLoads() {
        XCTAssertFalse(Catalog.shared.entries.isEmpty, "Catalog should load entries from catalog.json")
    }

    func testCatalogEntryCount() {
        // catalog.json currently has 72 entries; allow some flexibility
        XCTAssertGreaterThanOrEqual(Catalog.shared.entries.count, 60,
                                     "Expected at least 60 catalog entries")
    }

    // MARK: - Categories

    func testCatalogCategoriesNotEmpty() {
        XCTAssertFalse(Catalog.shared.categories.isEmpty)
    }

    func testCatalogCategoriesSorted() {
        let categories = Catalog.shared.categories
        XCTAssertEqual(categories, categories.sorted())
    }

    func testCatalogCategoriesAreUnique() {
        let categories = Catalog.shared.categories
        XCTAssertEqual(categories.count, Set(categories).count, "Categories should be unique")
    }

    // MARK: - Filtering

    func testCatalogEntriesInCategory() {
        let devTools = Catalog.shared.entries(in: "Developer Tools")
        XCTAssertFalse(devTools.isEmpty)
        for entry in devTools {
            XCTAssertEqual(entry.category, "Developer Tools")
        }
    }

    func testCatalogEntriesInUnknownCategory() {
        let results = Catalog.shared.entries(in: "Nonexistent Category 12345")
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Search

    func testCatalogSearchFindsMatch() {
        let results = Catalog.shared.search("git")
        XCTAssertFalse(results.isEmpty, "Search for 'git' should find at least GitHub")
    }

    func testCatalogSearchEmptyQuery() {
        let results = Catalog.shared.search("")
        XCTAssertEqual(results.count, Catalog.shared.entries.count,
                       "Empty search should return all entries")
    }

    func testCatalogSearchNoMatch() {
        let results = Catalog.shared.search("zzzzzzzzzzz")
        XCTAssertTrue(results.isEmpty)
    }

    func testCatalogSearchCaseInsensitive() {
        let upper = Catalog.shared.search("GITHUB")
        let lower = Catalog.shared.search("github")
        XCTAssertFalse(upper.isEmpty)
        XCTAssertEqual(upper.count, lower.count)
    }

    // MARK: - Entry validation

    func testCatalogEntryHasValidFields() {
        for entry in Catalog.shared.entries {
            XCTAssertFalse(entry.id.isEmpty, "Entry \(entry.name) has empty id")
            XCTAssertFalse(entry.name.isEmpty, "Entry \(entry.id) has empty name")
            XCTAssertFalse(entry.baseURL.isEmpty, "Entry \(entry.id) has empty baseURL")
            XCTAssertFalse(entry.category.isEmpty, "Entry \(entry.id) has empty category")
        }
    }

    func testCatalogEntryBaseURLIsHTTPS() {
        for entry in Catalog.shared.entries {
            XCTAssertTrue(entry.baseURL.hasPrefix("https://"),
                          "Entry \(entry.id) baseURL should start with https:// but is \(entry.baseURL)")
        }
    }

    func testKnownEntryExists() {
        let github = Catalog.shared.entries.first(where: { $0.id == "github" })
        XCTAssertNotNil(github)
        XCTAssertEqual(github?.name, "GitHub")
    }
}
