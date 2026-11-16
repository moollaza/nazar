import XCTest
@testable import StatusMonitor

final class AppleSystemStatusTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let provider = Provider(name: "Apple Developer", baseURL: "https://developer.apple.com/system-status/", type: .apple)

    private let developerFeed = #"""
    jsonCallback({"drMessage":null,"services":[
      {"serviceName":"Account","redirectUrl":"https://developer.apple.com/account/","events":[]},
      {"serviceName":"App Store Connect","events":[
        {"messageId":"2000005739","statusType":"Issue","eventStatus":"resolved","message":"Users may have experienced issues.","epochStartDate":1793142000000,"epochEndDate":1793147400000}
      ]}],"drpost":false});
    """#
    private let consumerFeed = #"""
    {"drMessage":null,"services":[
      {"serviceName":"App Store","redirectUrl":null,"events":[]},
      {"serviceName":"Apple Business","events":[
        {"messageId":"2000005739","statusType":"Issue","eventStatus":"resolved","message":"Users may have experienced issues with purchases and subscriptions.","epochStartDate":1793142000000,"epochEndDate":1793147400000}
      ]}],"drpost":false}
    """#

    private func parse(_ text: String, at date: Date? = nil) throws -> ProviderSnapshot {
        try AppleSystemStatus.snapshot(from: Data(text.utf8), provider: provider, now: date ?? now)
    }

    private func feed(_ services: [[String: Any]]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: ["services": services])
        return String(decoding: data, as: UTF8.self)
    }

    private func service(_ name: String = "API", events: [[String: Any]]) -> [String: Any] {
        ["serviceName": name, "events": events]
    }

    private func event(_ type: String = "Issue", lifecycle: String = "ongoing", id: String = "event", start: Double? = nil, end: Double? = nil) -> [String: Any] {
        var event: [String: Any] = ["messageId": id, "statusType": type, "eventStatus": lifecycle, "message": "Apple's update"]
        event["epochStartDate"] = start
        event["epochEndDate"] = end
        return event
    }

    func testBothObservedEnvelopesIgnoreResolvedHistory() throws {
        for text in [developerFeed, consumerFeed] {
            let snapshot = try parse(text)
            XCTAssertEqual(snapshot.overallStatus, .operational)
            XCTAssertEqual(snapshot.components.count, 2)
            XCTAssertTrue(snapshot.activeIncidents.isEmpty)
            XCTAssertEqual(snapshot.lastUpdated, now)
            XCTAssertEqual(snapshot.id, provider.id)
        }
    }

    func testBOMAndWhitespaceAreAcceptedForBothEnvelopes() throws {
        for text in [developerFeed, consumerFeed] {
            XCTAssertEqual(try parse("\u{FEFF}\n  " + text + "\n ").overallStatus, .operational)
        }
        XCTAssertEqual(try parse(developerFeed.dropLast().description).overallStatus, .operational)
    }

    func testStrictEnvelopeRejectsOtherJavaScript() {
        for text in ["otherCallback(\(consumerFeed));", "var status = \(consumerFeed);", "jsonCallback(\(consumerFeed)", "jsonCallback(\(consumerFeed));alert(1);", "jsonCallback (\(consumerFeed));", "\(consumerFeed);", "<html>status</html>"] {
            XCTAssertThrowsError(try parse(text), text)
        }
    }

    func testOngoingKindsAndCaseNormalization() throws {
        let cases: [(String, ComponentStatus)] = [
            ("oUtAgE", .majorOutage), ("ISSUE", .partialOutage),
            ("Performance", .degradedPerformance), ("Maintenance", .underMaintenance),
            ("Available", .operational), ("new-kind", .unknown)
        ]
        for (kind, expected) in cases {
            let snapshot = try parse(feed([service(events: [event(kind, lifecycle: "ONGOING")])]))
            XCTAssertEqual(snapshot.overallStatus, expected, kind)
            XCTAssertEqual(snapshot.components.first?.status, expected, kind)
            XCTAssertEqual(snapshot.activeIncidents.count, expected == .operational ? 0 : 1, kind)
        }
    }

    func testOngoingOutageIgnoresPlaceholderEndEpoch() throws {
        let snapshot = try parse(feed([service(events: [event("Outage", start: 1_700_000_000_000, end: 1_700_000_001_000)])]))
        XCTAssertEqual(snapshot.overallStatus, .majorOutage)
        XCTAssertEqual(snapshot.activeIncidents.first?.updatedAt, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(snapshot.activeIncidents.first?.latestUpdate, "Apple's update")
        XCTAssertEqual(snapshot.activeIncidents.first?.name, "API: Outage")
        XCTAssertTrue(try XCTUnwrap(snapshot.activeIncidents.first).updates.isEmpty)
    }

    func testTerminalLifecycleWinsOverMaintenanceWindow() throws {
        for lifecycle in ["RESOLVED", "Completed"] {
            let snapshot = try parse(feed([service(events: [event("Maintenance", lifecycle: lifecycle, start: 1_799_999_000_000, end: 1_800_001_000_000)])]))
            XCTAssertEqual(snapshot.overallStatus, .operational)
            XCTAssertTrue(snapshot.activeIncidents.isEmpty)
        }
    }

    func testMaintenanceUsesHalfOpenWindowForBothDeclaredPhases() throws {
        let start = now.timeIntervalSince1970 * 1_000
        let end = start + 60_000
        for lifecycle in ["upcoming", "ongoing"] {
            let text = try feed([service(events: [event("Maintenance", lifecycle: lifecycle, start: start, end: end)])])
            for (offset, expected) in [(-1.0, ComponentStatus.operational), (0, .underMaintenance), (59, .underMaintenance), (60, .operational), (61, .operational)] {
                let snapshot = try parse(text, at: now.addingTimeInterval(offset))
                XCTAssertEqual(snapshot.overallStatus, expected, "\(lifecycle), \(offset)")
                XCTAssertEqual(snapshot.activeIncidents.count, expected == .operational ? 0 : 1)
                if expected == .underMaintenance {
                    XCTAssertEqual(snapshot.activeIncidents.first?.status, "ongoing")
                }
            }
        }
    }

    func testMaintenanceFallsBackToDeclaredPhaseForUnusableBounds() throws {
        let bounds: [(Double?, Double?)] = [(nil, nil), (0, 100), (-1, 100), (100, 100), (200, 100), (1e100, 2e100)]
        for (start, end) in bounds {
            for (lifecycle, expected) in [("ongoing", ComponentStatus.underMaintenance), ("upcoming", .operational)] {
                XCTAssertEqual(try parse(feed([service(events: [event("Maintenance", lifecycle: lifecycle, start: start, end: end)])])).overallStatus, expected)
            }
        }
    }

    func testInvalidStartEpochDoesNotBecomeIncidentDate() throws {
        for epoch in [0.0, -1, 1e100] {
            XCTAssertNil(try parse(feed([service(events: [event(start: epoch)])])).activeIncidents.first?.updatedAt)
        }
    }

    func testUnknownLifecycleStaysUnknownEvenDuringMaintenanceWindow() throws {
        for kind in ["Issue", "Available", "Maintenance", "new-kind"] {
            let snapshot = try parse(feed([service("Healthy", events: []), service(events: [event(kind, lifecycle: "new-phase", start: 1_799_999_000_000, end: 1_800_001_000_000)])]))
            XCTAssertEqual(snapshot.overallStatus, .unknown)
            XCTAssertEqual(snapshot.components.last?.status, .unknown)
            XCTAssertEqual(snapshot.activeIncidents.first?.impact, .unknown)
        }
    }

    func testUpcomingNonMaintenanceIsInactive() throws {
        let snapshot = try parse(feed([service(events: [event("Outage", lifecycle: "upcoming")])]))
        XCTAssertEqual(snapshot.overallStatus, .operational)
        XCTAssertTrue(snapshot.activeIncidents.isEmpty)
    }

    func testWorstActiveEventDeterminesComponentAndProvider() throws {
        let snapshot = try parse(feed([service("Healthy", events: []), service(events: [event("Performance", id: "a"), event("Outage", id: "b"), event("Available", id: "c")])]))
        XCTAssertEqual(snapshot.components.map(\.name), ["Healthy", "API"])
        XCTAssertEqual(snapshot.components.map(\.status), [.operational, .majorOutage])
        XCTAssertEqual(snapshot.overallStatus, .majorOutage)
        XCTAssertEqual(snapshot.activeIncidents.map(\.impact), [.majorOutage, .degradedPerformance])
    }

    func testIncidentIdentityIsStableAcrossServiceOrderAndCoalescesRepeatedKeys() throws {
        let services = [service("First", events: [event(), event()]), service("Second", events: [event()])]
        let first = try parse(feed(services))
        let second = try parse(feed(Array(services.reversed())))
        XCTAssertEqual(first.activeIncidents.count, 2)
        XCTAssertEqual(Set(first.activeIncidents.map(\.id)).count, 2)
        XCTAssertEqual(first.activeIncidents.map(\.id), second.activeIncidents.map(\.id))
        XCTAssertEqual(first.components.map(\.id), ["First", "Second"])
    }

    func testSeverityIsComputedBeforeIncidentLimitAndSortingIsDeterministic() throws {
        var events = (0..<5).map { event("Issue", id: "\($0)", start: 1_700_000_000_000 + Double($0) * 1_000) }
        events.append(event("Outage", id: "sixth"))
        let snapshot = try parse(feed([service(events: events)]))
        XCTAssertEqual(snapshot.overallStatus, .majorOutage)
        XCTAssertEqual(snapshot.activeIncidents.count, 5)
        XCTAssertEqual(snapshot.activeIncidents.first?.impact, .majorOutage)
        XCTAssertEqual(snapshot.activeIncidents.dropFirst().map(\.updatedAt), (1...4).reversed().map { Date(timeIntervalSince1970: 1_700_000_000 + Double($0)) })
    }

    func testUnavailableAndMalformedFeedsThrow() {
        for text in [#"{"services":[],"drpost":false}"#, #"{"services":[{"serviceName":"API","events":[]}],"drpost":true}"#, #"{}"#, #"{"services":[{"serviceName":"API"}]}"#, #"{"services":[{"events":[]}]}"#, #"{"services":[{"serviceName":"  ","events":[]}]}"#, #"{"services":[{"serviceName":"API","events":[{"messageId":"","statusType":"Issue","eventStatus":"ongoing"}]}]}"#, #"{"services":[{"serviceName":"API","events":[{"messageId":"a","eventStatus":"ongoing"}]}]}"#, #"{"services":[{"serviceName":"API","events":[{"messageId":"a","statusType":"Issue"}]}]}"#] {
            XCTAssertThrowsError(try parse(text), text)
        }
    }

    func testSupportedPageURLsResolveToExactEndpoints() {
        for (page, endpoint) in [
            ("https://developer.apple.com/system-status", "https://developer.apple.com/system-status/data/system_status_en_US.js"),
            ("https://www.apple.com/support/systemstatus", "https://www.apple.com/support/systemstatus/data/system_status_en_US.js")
        ] {
            for url in [page, page + "/"] {
                let provider = Provider(name: "Apple", baseURL: url, type: .apple)
                XCTAssertTrue(provider.hasValidURL)
                XCTAssertEqual(provider.apiURL?.absoluteString, endpoint)
                XCTAssertEqual(provider.externalURL?.absoluteString, page)
            }
        }
    }

    func testUnsupportedAppleURLsAreRejected() {
        for url in ["http://developer.apple.com/system-status", "https://apple.com/support/systemstatus", "https://www.apple.com/system-status", "https://developer.apple.com/support/systemstatus", "https://developer.apple.com.evil.example/system-status", "https://user@developer.apple.com/system-status", "https://developer.apple.com:444/system-status", "https://developer.apple.com/system-status?lang=en", "https://developer.apple.com/system-status#status", "https://developer.apple.com/system-status/data/system_status_en_US.js", "https://developer.apple.com/system-status/extra", "https://developer.apple.com/%73ystem-status"] {
            let provider = Provider(name: "Apple", baseURL: url, type: .apple)
            XCTAssertFalse(provider.hasValidURL, url)
            XCTAssertNil(provider.apiURL, url)
            XCTAssertNil(provider.externalURL, url)
        }
    }

    func testAppleProviderSurvivesCodableRoundTrip() throws {
        let decoded = try JSONDecoder().decode(Provider.self, from: JSONEncoder().encode(provider))
        XCTAssertEqual(decoded, provider)
        XCTAssertEqual(decoded.type.rawValue, "apple")
        XCTAssertEqual(decoded.apiURL, provider.apiURL)
    }
}
