import XCTest
@testable import StatusMonitor

@MainActor
final class StatusManagerTests: XCTestCase {

    private var manager: StatusManager!

    override func setUp() {
        super.setUp()
        manager = StatusManager()
        // Clear any loaded state; we test recalcWorstStatus in isolation
        manager.snapshots = []
        manager.providers = []
    }

    // MARK: - Helpers

    private func makeSnapshot(
        id: UUID = UUID(),
        name: String = "Test",
        status: ComponentStatus,
        error: String? = nil
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            id: id,
            name: name,
            overallStatus: status,
            components: [],
            activeIncidents: [],
            lastUpdated: Date(),
            error: error
        )
    }

    // MARK: - recalcWorstStatus

    func testWorstStatusEmpty() {
        manager.snapshots = []
        manager.recalcWorstStatus()
        XCTAssertEqual(manager.worstStatus, .operational)
    }

    func testWorstStatusAllOperational() {
        manager.snapshots = [
            makeSnapshot(status: .operational),
            makeSnapshot(status: .operational),
        ]
        manager.recalcWorstStatus()
        XCTAssertEqual(manager.worstStatus, .operational)
    }

    func testWorstStatusOneDegraded() {
        manager.snapshots = [
            makeSnapshot(status: .operational),
            makeSnapshot(status: .degradedPerformance),
        ]
        manager.recalcWorstStatus()
        XCTAssertEqual(manager.worstStatus, .degradedPerformance)
    }

    func testWorstStatusMajorOutage() {
        manager.snapshots = [
            makeSnapshot(status: .operational),
            makeSnapshot(status: .degradedPerformance),
            makeSnapshot(status: .majorOutage),
        ]
        manager.recalcWorstStatus()
        XCTAssertEqual(manager.worstStatus, .majorOutage)
    }

    func testWorstStatusPreservesLastGoodAcrossError() {
        // When a poll fails mid-incident, the snapshot retains its last-good
        // overallStatus with error != nil. worstStatus must still include it
        // so the menu bar doesn't revert to green during a transient failure.
        manager.snapshots = [
            makeSnapshot(status: .operational),
            makeSnapshot(status: .majorOutage, error: "Network error"),
        ]
        manager.recalcWorstStatus()
        XCTAssertEqual(manager.worstStatus, .majorOutage,
                       "Error snapshots carry their last-good status and must contribute to worstStatus")
    }

    func testWorstStatusAllErrors() {
        manager.snapshots = [
            makeSnapshot(status: .majorOutage, error: "Error 1"),
            makeSnapshot(status: .partialOutage, error: "Error 2"),
        ]
        manager.recalcWorstStatus()
        XCTAssertEqual(manager.worstStatus, .majorOutage,
                       "Error snapshots retain their last-good status; max wins")
    }

    func testWorstStatusMixedWithErrors() {
        manager.snapshots = [
            makeSnapshot(status: .operational),
            makeSnapshot(status: .degradedPerformance),
            makeSnapshot(status: .majorOutage, error: "Network error"),
        ]
        manager.recalcWorstStatus()
        XCTAssertEqual(manager.worstStatus, .majorOutage,
                       "Error snapshots contribute to worst status; outage beats degraded")
    }

    func testWorstStatusUnknownSurfaces() {
        // .unknown now elevates above .operational so monitoring-degraded
        // state is visible instead of masquerading as healthy.
        manager.snapshots = [
            makeSnapshot(status: .unknown),
            makeSnapshot(status: .operational),
        ]
        manager.recalcWorstStatus()
        XCTAssertEqual(manager.worstStatus, .unknown,
                       "Unknown must surface above operational")
    }

    func testWorstStatusUnknownBeatenByRealProblem() {
        manager.snapshots = [
            makeSnapshot(status: .unknown),
            makeSnapshot(status: .degradedPerformance),
        ]
        manager.recalcWorstStatus()
        XCTAssertEqual(manager.worstStatus, .degradedPerformance,
                       "A real degraded signal must override an unknown one")
    }

    func testUnreachableCountCountsErrorSnapshots() {
        manager.snapshots = [
            makeSnapshot(status: .operational),
            makeSnapshot(status: .majorOutage, error: "Network error"),
            makeSnapshot(status: .operational, error: "Timeout"),
        ]
        XCTAssertEqual(manager.unreachableCount, 2)
    }

    // MARK: - Refresh coalescing

    func testPollAllCoalescesWhenAlreadyRefreshing() {
        // Simulate an in-flight refresh. A second call must no-op rather than
        // spawn an overlapping task group.
        manager.isRefreshing = true
        manager.pollAll()
        XCTAssertTrue(manager.isRefreshing,
                      "Second pollAll must not reset the flag nor start a new cycle")
    }

    // MARK: - Muted providers

    func testWorstStatusExcludesMutedProviders() {
        let mutedId = UUID()
        let normalId = UUID()

        manager.providers = [
            Provider(name: "Muted", baseURL: "https://a.com", isMuted: true),
        ]
        // Override the provider id to match snapshot — we need to create with known id
        // Since Provider generates its own UUID, we set up providers with isMuted
        // and use matching ids in snapshots
        let mutedProvider = manager.providers[0]

        manager.snapshots = [
            makeSnapshot(id: mutedProvider.id, status: .majorOutage),
            makeSnapshot(id: normalId, status: .operational),
        ]
        manager.recalcWorstStatus()
        XCTAssertEqual(manager.worstStatus, .operational,
                       "Muted provider's major outage should be excluded")
    }

    // MARK: - onWorstStatusChanged callback

    func testOnWorstStatusChangedCallback() {
        var callbackStatuses: [ComponentStatus] = []
        manager.onWorstStatusChanged = { status in
            callbackStatuses.append(status)
        }

        // Set initial state to operational
        manager.worstStatus = .operational
        manager.snapshots = [makeSnapshot(status: .majorOutage)]
        manager.recalcWorstStatus()

        XCTAssertEqual(callbackStatuses, [.majorOutage],
                       "Callback should fire when status changes")
    }

    func testOnWorstStatusChangedDoesNotFireWhenUnchanged() {
        var callCount = 0
        manager.onWorstStatusChanged = { _ in
            callCount += 1
        }

        manager.worstStatus = .operational
        manager.snapshots = [makeSnapshot(status: .operational)]
        manager.recalcWorstStatus()

        XCTAssertEqual(callCount, 0,
                       "Callback should not fire when status stays the same")
    }
}
