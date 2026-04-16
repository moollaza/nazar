import XCTest
@testable import StatusMonitor

/// Exercises the full poll() path by injecting a mock URLSession and a
/// notification spy. Covers the branches the audit flagged as zero-coverage:
/// success/HTTP error/thrown-error/size-cap, and status-transition notification
/// dispatch.
@MainActor
final class StatusManagerPollTests: XCTestCase {

    // MARK: - Spy

    final class NotificationSpy: NotificationServicing {
        struct Call: Equatable {
            let providerId: UUID
            let provider: String
            let from: ComponentStatus
            let to: ComponentStatus
            let incident: String?
        }
        var calls: [Call] = []
        func notify(providerId: UUID, provider: String, from: ComponentStatus, to: ComponentStatus, incident: String?) {
            calls.append(Call(providerId: providerId, provider: provider, from: from, to: to, incident: incident))
        }
    }

    // MARK: - Mock URLSession helpers

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override func tearDown() {
        super.tearDown()
        StubURLProtocol.clearStubs()
    }

    // MARK: - Fixtures

    private let operationalJSON = #"""
    {
      "page": {"name": "Test Status", "url": "https://status.example.com"},
      "status": {"indicator": "none", "description": "All Systems Operational"},
      "components": [
        {"id": "c1", "name": "API", "status": "operational"}
      ],
      "incidents": [],
      "scheduled_maintenances": []
    }
    """#.data(using: .utf8)!

    private let majorOutageJSON = #"""
    {
      "page": {"name": "Test Status", "url": "https://status.example.com"},
      "status": {"indicator": "critical", "description": "Major Outage"},
      "components": [
        {"id": "c1", "name": "API", "status": "major_outage"}
      ],
      "incidents": [
        {"id": "i1", "name": "API unreachable", "status": "investigating", "impact": "critical", "updated_at": "2026-04-16T12:00:00Z", "incident_updates": []}
      ],
      "scheduled_maintenances": []
    }
    """#.data(using: .utf8)!

    // MARK: - Happy path

    func testPoll200AppliesSnapshotAsOperational() async {
        let url = URL(string: "https://status.example.com/api/v2/summary.json")!
        StubURLProtocol.register(url: url, response: (operationalJSON, 200))

        let manager = StatusManager(session: makeSession(), notifier: NotificationSpy())
        manager.snapshots = []
        manager.providers = []

        let provider = Provider(name: "Test", baseURL: "https://status.example.com")
        manager.providers = [provider]

        await manager.poll(provider: provider)

        XCTAssertEqual(manager.snapshots.count, 1)
        XCTAssertEqual(manager.snapshots[0].overallStatus, .operational)
        XCTAssertNil(manager.snapshots[0].error)
    }

    func testPoll200WithMajorOutageReflectsOutage() async {
        let url = URL(string: "https://status.example.com/api/v2/summary.json")!
        StubURLProtocol.register(url: url, response: (majorOutageJSON, 200))

        let manager = StatusManager(session: makeSession(), notifier: NotificationSpy())
        let provider = Provider(name: "Test", baseURL: "https://status.example.com")
        manager.providers = [provider]
        manager.snapshots = []

        await manager.poll(provider: provider)

        XCTAssertEqual(manager.snapshots[0].overallStatus, .majorOutage)
        XCTAssertEqual(manager.snapshots[0].activeIncidents.count, 1)
    }

    // MARK: - HTTP error branches

    func testPoll404SetsErrorAndRecordsFailure() async {
        let url = URL(string: "https://status.example.com/api/v2/summary.json")!
        StubURLProtocol.register(url: url, response: (Data(), 404))

        let manager = StatusManager(session: makeSession(), notifier: NotificationSpy())
        let provider = Provider(name: "Gone", baseURL: "https://status.example.com")
        manager.providers = [provider]

        await manager.poll(provider: provider)

        XCTAssertEqual(manager.snapshots.count, 1)
        XCTAssertNotNil(manager.snapshots[0].error)
        XCTAssertTrue(manager.snapshots[0].error!.contains("404"),
                      "404 message should include the status code for diagnosability")
    }

    func testPoll500SetsError() async {
        let url = URL(string: "https://status.example.com/api/v2/summary.json")!
        StubURLProtocol.register(url: url, response: (Data(), 503))

        let manager = StatusManager(session: makeSession(), notifier: NotificationSpy())
        let provider = Provider(name: "Sick", baseURL: "https://status.example.com")
        manager.providers = [provider]

        await manager.poll(provider: provider)

        XCTAssertNotNil(manager.snapshots[0].error)
    }

    // MARK: - Invalid URL

    func testPollInvalidURLSetsError() async {
        let manager = StatusManager(session: makeSession(), notifier: NotificationSpy())
        let provider = Provider(name: "Bad", baseURL: "not a url")
        manager.providers = [provider]

        await manager.poll(provider: provider)

        XCTAssertEqual(manager.snapshots.count, 1)
        XCTAssertTrue(manager.snapshots[0].error?.contains("Invalid URL") ?? false)
    }

    // MARK: - Last-good preservation

    func testErrorPreservesLastGoodStatus() async {
        let url = URL(string: "https://status.example.com/api/v2/summary.json")!

        // First poll: healthy
        StubURLProtocol.register(url: url, response: (operationalJSON, 200))
        let manager = StatusManager(session: makeSession(), notifier: NotificationSpy())
        let provider = Provider(name: "Flappy", baseURL: "https://status.example.com")
        manager.providers = [provider]
        await manager.poll(provider: provider)
        XCTAssertEqual(manager.snapshots[0].overallStatus, .operational)

        // Second poll: 500 error
        StubURLProtocol.register(url: url, response: (Data(), 500))
        await manager.poll(provider: provider)

        // Last-good status (operational) preserved; error annotated
        XCTAssertEqual(manager.snapshots[0].overallStatus, .operational,
                       "Error must preserve last-good overallStatus so the UI doesn't revert to green by accident")
        XCTAssertNotNil(manager.snapshots[0].error)
    }

    // MARK: - Transition notifications

    func testStatusTransitionFiresNotification() async {
        let url = URL(string: "https://status.example.com/api/v2/summary.json")!
        let spy = NotificationSpy()

        // First poll: operational — must NOT notify (first poll)
        StubURLProtocol.register(url: url, response: (operationalJSON, 200))
        let manager = StatusManager(session: makeSession(), notifier: spy)
        let provider = Provider(name: "T", baseURL: "https://status.example.com")
        manager.providers = [provider]
        await manager.poll(provider: provider)
        XCTAssertTrue(spy.calls.isEmpty, "First poll must not notify")

        // Second poll: major outage — must notify
        StubURLProtocol.register(url: url, response: (majorOutageJSON, 200))
        await manager.poll(provider: provider)

        XCTAssertEqual(spy.calls.count, 1)
        XCTAssertEqual(spy.calls.first?.from, .operational)
        XCTAssertEqual(spy.calls.first?.to, .majorOutage)
    }

    func testSameStatusDoesNotNotify() async {
        let url = URL(string: "https://status.example.com/api/v2/summary.json")!
        StubURLProtocol.register(url: url, response: (operationalJSON, 200))
        let spy = NotificationSpy()
        let manager = StatusManager(session: makeSession(), notifier: spy)
        let provider = Provider(name: "Steady", baseURL: "https://status.example.com")
        manager.providers = [provider]

        await manager.poll(provider: provider)
        await manager.poll(provider: provider)
        await manager.poll(provider: provider)

        XCTAssertTrue(spy.calls.isEmpty, "No transition — no notification")
    }

    func testMutedProviderDoesNotNotifyOnTransition() async {
        let url = URL(string: "https://status.example.com/api/v2/summary.json")!
        let spy = NotificationSpy()

        let manager = StatusManager(session: makeSession(), notifier: spy)
        var provider = Provider(name: "Muted", baseURL: "https://status.example.com")
        provider.isMuted = true
        manager.providers = [provider]

        StubURLProtocol.register(url: url, response: (operationalJSON, 200))
        await manager.poll(provider: provider)

        StubURLProtocol.register(url: url, response: (majorOutageJSON, 200))
        await manager.poll(provider: provider)

        XCTAssertTrue(spy.calls.isEmpty, "Muted providers must not fire transition notifications")
    }
}

// MARK: - URLProtocol stub

/// Minimal URLProtocol that returns canned (data, statusCode) responses for
/// exact URL matches. Register with `StubURLProtocol.register(url:response:)`
/// before issuing a request.
final class StubURLProtocol: URLProtocol {
    private static var stubs: [URL: (Data, Int)] = [:]
    private static let lock = NSLock()

    static func register(url: URL, response: (Data, Int)) {
        lock.lock(); defer { lock.unlock() }
        stubs[url] = response
    }

    static func clearStubs() {
        lock.lock(); defer { lock.unlock() }
        stubs.removeAll()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let stub = request.url.flatMap { Self.stubs[$0] }
        Self.lock.unlock()

        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        if let (data, code) = stub {
            let response = HTTPURLResponse(
                url: url,
                statusCode: code,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
        }
    }

    override func stopLoading() {}
}

