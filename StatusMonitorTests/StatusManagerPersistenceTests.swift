import XCTest
@testable import StatusMonitor

/// Persistence round-trip, onboarding migration, and corruption-recovery
/// coverage. Previously zero-coverage paths — the audit flagged that a schema
/// change could silently wipe every user's provider list on upgrade.
@MainActor
final class StatusManagerPersistenceTests: XCTestCase {

    private var suite: UserDefaults!
    private var suiteName: String!
    private static let noopNotifier = NoopNotifier()

    override func setUp() {
        super.setUp()
        // Per-test isolated suite so tests don't clobber each other or the
        // real app defaults.
        suiteName = "StatusMonitorTests-\(UUID().uuidString)"
        suite = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        suite.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeManager() -> StatusManager {
        StatusManager(session: .shared, notifier: Self.noopNotifier, defaults: suite)
    }

    // MARK: - Round-trip

    func testSaveThenLoadPreservesProviders() {
        let m1 = makeManager()
        let github = Provider(name: "GitHub", baseURL: "https://www.githubstatus.com",
                              type: .statuspage, pollIntervalSeconds: 120)
        m1.providers = [github]
        m1.saveProviders()

        let m2 = makeManager()
        XCTAssertEqual(m2.providers.count, 1)
        XCTAssertEqual(m2.providers[0].name, "GitHub")
        XCTAssertEqual(m2.providers[0].baseURL, "https://www.githubstatus.com")
        XCTAssertEqual(m2.providers[0].pollIntervalSeconds, 120)
    }

    func testFirstLaunchWithNoDataIsEmpty() {
        let m = makeManager()
        XCTAssertTrue(m.providers.isEmpty)
    }

    // MARK: - Onboarding migration

    func testLoadingNonEmptyProvidersMarksOnboardingComplete() {
        // Simulate an existing user who has providers saved from a prior
        // version but never saw onboarding.
        let existing = [Provider(name: "Old", baseURL: "https://status.old.com")]
        let blob = try! JSONEncoder().encode(existing)
        suite.set(blob, forKey: "providers")
        XCTAssertFalse(suite.bool(forKey: "hasCompletedOnboarding"))

        _ = makeManager()
        XCTAssertTrue(suite.bool(forKey: "hasCompletedOnboarding"),
                      "Legacy users with saved providers should skip onboarding")
    }

    // MARK: - Corruption recovery

    func testCorruptedBlobIsBackedUpNotOverwritten() {
        // Write garbage under the providers key — simulating schema migration
        // failure or external mutation.
        let garbage = Data("not-valid-json".utf8)
        suite.set(garbage, forKey: "providers")

        let m = makeManager()
        XCTAssertTrue(m.providers.isEmpty)

        // Corrupt blob must be backed up under a different key so it can be
        // inspected / recovered, not silently overwritten.
        let backups = suite.dictionaryRepresentation().keys.filter { $0.hasPrefix("providers_corrupt_") }
        XCTAssertFalse(backups.isEmpty, "Corrupted blob must be preserved for recovery")
    }

    func testSaveAfterCorruptionReplacesProvidersKey() {
        // After recovery (empty providers), subsequent saveProviders writes
        // should overwrite the "providers" key but leave the corrupt backup.
        let garbage = Data("not-valid-json".utf8)
        suite.set(garbage, forKey: "providers")
        let m = makeManager()

        m.providers = [Provider(name: "Fresh", baseURL: "https://status.fresh.com")]
        m.saveProviders()

        // "providers" is now valid JSON
        let data = suite.data(forKey: "providers")!
        let decoded = try! JSONDecoder().decode([Provider].self, from: data)
        XCTAssertEqual(decoded[0].name, "Fresh")
    }

    // MARK: - addProvider validation and dedup

    func testAddProviderRejectsInvalidURL() {
        let m = makeManager()
        let bad = Provider(name: "Bad", baseURL: "not a url")
        XCTAssertFalse(m.addProvider(bad))
        XCTAssertTrue(m.providers.isEmpty)
    }

    func testAddProviderRejectsDuplicateBaseURL() {
        let m = makeManager()
        let first = Provider(name: "GitHub", baseURL: "https://www.githubstatus.com")
        XCTAssertTrue(m.addProvider(first))

        let dup = Provider(name: "GitHub Again", baseURL: "https://www.githubstatus.com")
        XCTAssertFalse(m.addProvider(dup))
        XCTAssertEqual(m.providers.count, 1)
    }

    func testAddProviderSetsOnboardingComplete() {
        let m = makeManager()
        XCTAssertFalse(suite.bool(forKey: "hasCompletedOnboarding"))
        _ = m.addProvider(Provider(name: "X", baseURL: "https://status.x.com"))
        XCTAssertTrue(suite.bool(forKey: "hasCompletedOnboarding"))
    }

    // MARK: - No-op notifier (avoid real UNUserNotificationCenter in tests)

    final class NoopNotifier: NotificationServicing {
        func notify(providerId: UUID, provider: String, from: ComponentStatus, to: ComponentStatus, incident: String?, recentChangeCount: Int) {}
    }
}
