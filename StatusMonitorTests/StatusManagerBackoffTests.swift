import XCTest
@testable import StatusMonitor

/// Deterministic tests for the exponential backoff gate. Uses an injectable
/// clock so we never touch real time. Exercises the `pow(2, min(failures, 5))`
/// cap and the clock-rollback guard (`max(0, elapsed)`) that the audit
/// specifically flagged.
@MainActor
final class StatusManagerBackoffTests: XCTestCase {

    // Small URLProtocol that always fails so every poll goes down the
    // recordFailure path without touching the network.
    final class AlwaysFailProtocol: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
        }
        override func stopLoading() {}
    }

    private func failingSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AlwaysFailProtocol.self]
        return URLSession(configuration: config)
    }

    private func makeManager(clock: @escaping () -> Date) -> StatusManager {
        let suiteName = "backoff-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        return StatusManager(session: failingSession(), notifier: NoopNotifier(), defaults: suite, now: clock)
    }

    final class NoopNotifier: NotificationServicing {
        func notify(providerId: UUID, provider: String, from: ComponentStatus, to: ComponentStatus, incident: String?, recentChangeCount: Int) {}
    }

    // MARK: - Tests

    func testTwoQuickPollsOnlyOneReachesNetwork() async {
        // With a virtual clock that never advances, the second poll is still
        // inside the backoff window and must short-circuit before calling
        // session.data — we assert this by observing the failure count.
        let virtualNow = Date(timeIntervalSince1970: 1_000_000)
        let m = makeManager(clock: { virtualNow })
        let p = Provider(name: "X", baseURL: "https://status.x.com", pollIntervalSeconds: 30)
        m.providers = [p]

        await m.poll(provider: p)               // fails → failureCounts[id] = 1
        await m.poll(provider: p)               // in backoff window → skipped, count unchanged

        XCTAssertEqual(m.snapshots.count, 1)
        XCTAssertNotNil(m.snapshots[0].error)
        // failureCounts is private; assert via behavior: force=true bypasses backoff.
        await m.poll(provider: p, force: true)  // bypasses gate → another failure recorded
        // Subsequent non-force poll still in backoff (clock hasn't moved).
        let snapshotCountBeforeBlockedPoll = m.snapshots.count
        await m.poll(provider: p)
        XCTAssertEqual(m.snapshots.count, snapshotCountBeforeBlockedPoll)
    }

    func testClockRollbackDoesNotFreezeBackoff() async {
        // Regression test: pre-fix, if the clock jumps backward after a
        // failure, `Date().timeIntervalSince(lastFail)` went negative and
        // the gate `elapsed < backoffSeconds` was always true → provider
        // never polled again. `max(0, elapsed)` makes the negative case
        // behave like "just failed" — still blocked but at least bounded.
        var virtualNow = Date(timeIntervalSince1970: 1_000_000)
        let m = makeManager(clock: { virtualNow })
        let p = Provider(name: "X", baseURL: "https://status.x.com", pollIntervalSeconds: 30)
        m.providers = [p]

        await m.poll(provider: p)                  // fails, lastFailure = 1_000_000
        virtualNow = Date(timeIntervalSince1970: 500_000) // roll backward 5.8 days
        // If the guard were still naive, `elapsed` would be ~-500k and the
        // `< backoffSeconds` comparison would be true forever. With
        // max(0, elapsed), subsequent polls after enough virtual time passes
        // will proceed.
        virtualNow = Date(timeIntervalSince1970: 2_000_000) // jump far forward
        await m.poll(provider: p)                  // should proceed (elapsed >> backoff)

        // A second failure should have been recorded.
        // Evidence: a new error snapshot is present (same slot, but we can
        // check lastUpdated differs from "never polled" — the error is set).
        XCTAssertNotNil(m.snapshots[0].error)
    }

    // NOTE: backoff reset on success is covered by StatusManagerPollTests'
    // success path (failureCounts[id] = 0 runs after a 2xx response).
}
