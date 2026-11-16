import XCTest
@testable import StatusMonitor

@MainActor
final class AppleSystemStatusPollTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let outage = #"{"services":[{"serviceName":"App Store","events":[{"messageId":"outage","statusType":"Outage","eventStatus":"ongoing","message":"Purchases are unavailable.","epochStartDate":1799999000000,"epochEndDate":1}]}]}"#
    private let healthy = #"{"services":[{"serviceName":"App Store","events":[]}]}"#

    override func tearDown() {
        StubURLProtocol.clearStubs()
        super.tearDown()
    }

    private func makeManager(spy: StatusManagerPollTests.NotificationSpy) -> StatusManager {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return StatusManager(
            session: URLSession(configuration: config),
            notifier: spy,
            defaults: UserDefaults(suiteName: "AppleSystemStatusPollTests.\(UUID())")!,
            now: { self.now }
        )
    }

    func testBothAppleEndpointsPollThroughSharedSnapshotPipeline() async throws {
        for page in ["https://developer.apple.com/system-status/", "https://www.apple.com/support/systemstatus/"] {
            let spy = StatusManagerPollTests.NotificationSpy()
            let manager = makeManager(spy: spy)
            let provider = Provider(name: "Apple", baseURL: page, type: .apple)
            manager.providers = [provider]
            let payload = page.contains("developer") ? "jsonCallback(\(outage));" : outage
            StubURLProtocol.register(url: try XCTUnwrap(provider.apiURL), response: (Data(payload.utf8), 200))

            await manager.poll(provider: provider)

            let snapshot = try XCTUnwrap(manager.snapshots.first)
            XCTAssertNil(snapshot.error)
            XCTAssertEqual(snapshot.overallStatus, .majorOutage)
            XCTAssertEqual(manager.worstStatus, .majorOutage)
            XCTAssertEqual(snapshot.lastUpdated, now)
            XCTAssertEqual(snapshot.activeIncidents.first?.latestUpdate, "Purchases are unavailable.")
            XCTAssertTrue(spy.calls.isEmpty)
        }
    }

    func testAppleParseErrorsPreserveLastGoodSnapshot() async throws {
        let invalidFeeds = [
            "jsonCallback({", #"{"services":[{"serviceName":"App Store"}]}"#,
            #"{"services":[]}"#, #"{"drpost":true,"services":[{"serviceName":"App Store","events":[]}]}"#
        ]
        for invalidFeed in invalidFeeds {
            let spy = StatusManagerPollTests.NotificationSpy()
            let manager = makeManager(spy: spy)
            let provider = Provider(name: "Apple", baseURL: "https://www.apple.com/support/systemstatus", type: .apple)
            manager.providers = [provider]
            let url = try XCTUnwrap(provider.apiURL)
            StubURLProtocol.register(url: url, response: (Data(outage.utf8), 200))
            await manager.poll(provider: provider)
            let good = try XCTUnwrap(manager.snapshots.first)

            StubURLProtocol.register(url: url, response: (Data(invalidFeed.utf8), 200))
            await manager.poll(provider: provider)

            let failed = try XCTUnwrap(manager.snapshots.first)
            XCTAssertEqual(failed.error, "Status format not recognized")
            XCTAssertEqual(failed.overallStatus, .majorOutage)
            XCTAssertEqual(failed.components.map(\.id), good.components.map(\.id))
            XCTAssertEqual(failed.components.map(\.status), good.components.map(\.status))
            XCTAssertEqual(failed.activeIncidents.map(\.id), good.activeIncidents.map(\.id))
            XCTAssertEqual(failed.lastUpdated, good.lastUpdated)
            XCTAssertTrue(spy.calls.isEmpty)
        }
    }

    func testUnavailableAppleFeedWithoutHistoryIsUnknown() async throws {
        for payload in [#"{"services":[]}"#, #"{"drpost":true,"services":[{"serviceName":"App Store","events":[]}]}"#] {
            let manager = makeManager(spy: StatusManagerPollTests.NotificationSpy())
            let provider = Provider(name: "Apple", baseURL: "https://www.apple.com/support/systemstatus", type: .apple)
            manager.providers = [provider]
            StubURLProtocol.register(url: try XCTUnwrap(provider.apiURL), response: (Data(payload.utf8), 200))
            await manager.poll(provider: provider)
            XCTAssertEqual(manager.snapshots.first?.overallStatus, .unknown)
            XCTAssertEqual(manager.snapshots.first?.error, "Status format not recognized")
        }
    }

    func testAppleRecoveryUsesExistingNotificationAndMuteRules() async throws {
        for muted in [false, true] {
            let spy = StatusManagerPollTests.NotificationSpy()
            let manager = makeManager(spy: spy)
            let provider = Provider(name: "Apple", baseURL: "https://www.apple.com/support/systemstatus", type: .apple, isMuted: muted)
            manager.providers = [provider]
            let url = try XCTUnwrap(provider.apiURL)
            StubURLProtocol.register(url: url, response: (Data(outage.utf8), 200))
            await manager.poll(provider: provider)
            StubURLProtocol.register(url: url, response: (Data(healthy.utf8), 200))
            await manager.poll(provider: provider)
            XCTAssertEqual(manager.snapshots.first?.overallStatus, .operational)
            XCTAssertEqual(spy.calls.count, muted ? 0 : 1)
            if !muted {
                XCTAssertEqual(spy.calls.first?.from, .majorOutage)
                XCTAssertEqual(spy.calls.first?.to, .operational)
            }
        }
    }

    func testAppleMaintenancePollUsesInjectedClock() async throws {
        let manager = makeManager(spy: StatusManagerPollTests.NotificationSpy())
        let provider = Provider(name: "Apple", baseURL: "https://www.apple.com/support/systemstatus", type: .apple)
        manager.providers = [provider]
        let payload = #"{"services":[{"serviceName":"App Store","events":[{"messageId":"maintenance","statusType":"Maintenance","eventStatus":"upcoming","epochStartDate":1800000000000,"epochEndDate":1800000060000}]}]}"#
        StubURLProtocol.register(url: try XCTUnwrap(provider.apiURL), response: (Data(payload.utf8), 200))
        await manager.poll(provider: provider)
        XCTAssertEqual(manager.snapshots.first?.overallStatus, .underMaintenance)
        XCTAssertEqual(manager.snapshots.first?.lastUpdated, now)
    }
}
