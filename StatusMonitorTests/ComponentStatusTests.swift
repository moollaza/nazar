import XCTest
@testable import StatusMonitor

final class ComponentStatusTests: XCTestCase {

    // MARK: - fromStatuspage

    func testFromStatuspageOperational() {
        XCTAssertEqual(ComponentStatus(fromStatuspage: "operational"), .operational)
    }

    func testFromStatuspageDegradedPerformance() {
        XCTAssertEqual(ComponentStatus(fromStatuspage: "degraded_performance"), .degradedPerformance)
    }

    func testFromStatuspagePartialOutage() {
        XCTAssertEqual(ComponentStatus(fromStatuspage: "partial_outage"), .partialOutage)
    }

    func testFromStatuspageMajorOutage() {
        XCTAssertEqual(ComponentStatus(fromStatuspage: "major_outage"), .majorOutage)
    }

    func testFromStatuspageUnderMaintenance() {
        XCTAssertEqual(ComponentStatus(fromStatuspage: "under_maintenance"), .underMaintenance)
    }

    func testFromStatuspageUnknownString() {
        XCTAssertEqual(ComponentStatus(fromStatuspage: "garbage"), .unknown)
    }

    func testFromStatuspageEmptyString() {
        XCTAssertEqual(ComponentStatus(fromStatuspage: ""), .unknown)
    }

    // MARK: - fromIndicator

    func testFromIndicatorNone() {
        XCTAssertEqual(ComponentStatus(fromIndicator: "none"), .operational)
    }

    func testFromIndicatorMinor() {
        XCTAssertEqual(ComponentStatus(fromIndicator: "minor"), .degradedPerformance)
    }

    func testFromIndicatorMajor() {
        XCTAssertEqual(ComponentStatus(fromIndicator: "major"), .partialOutage)
    }

    func testFromIndicatorCritical() {
        XCTAssertEqual(ComponentStatus(fromIndicator: "critical"), .majorOutage)
    }

    func testFromIndicatorUnknownString() {
        XCTAssertEqual(ComponentStatus(fromIndicator: "foo"), .unknown)
    }

    // MARK: - Severity ordering

    func testSeverityOrdering() {
        // operational < unknown < degraded == maintenance < partial < major
        XCTAssertLessThan(ComponentStatus.operational.severity, ComponentStatus.unknown.severity)
        XCTAssertLessThan(ComponentStatus.unknown.severity, ComponentStatus.degradedPerformance.severity)
        XCTAssertLessThan(ComponentStatus.degradedPerformance.severity, ComponentStatus.partialOutage.severity)
        XCTAssertLessThan(ComponentStatus.partialOutage.severity, ComponentStatus.majorOutage.severity)
    }

    func testUnknownSeverityElevatesAboveOperational() {
        // Unknown means "we couldn't confirm this service is healthy" — it
        // must elevate worst-status above operational so the user is warned.
        XCTAssertGreaterThan(ComponentStatus.unknown.severity, ComponentStatus.operational.severity,
                             ".unknown must surface above .operational to prevent silent green when monitoring is degraded")
    }

    func testRealDegradedBeatsUnknown() {
        // An actual degraded signal should override an unknown — we don't want
        // the "we couldn't parse" state to drown a real incident.
        XCTAssertLessThan(ComponentStatus.unknown.severity, ComponentStatus.degradedPerformance.severity)
    }

    func testMaintenanceSeverityEqualsDegraded() {
        XCTAssertEqual(ComponentStatus.underMaintenance.severity, ComponentStatus.degradedPerformance.severity)
    }

    // MARK: - Comparable

    func testComparableMax() {
        let statuses: [ComponentStatus] = [.operational, .majorOutage, .partialOutage]
        XCTAssertEqual(statuses.max(), .majorOutage)
    }

    func testComparableSorted() {
        let statuses: [ComponentStatus] = [.majorOutage, .operational, .partialOutage, .degradedPerformance, .unknown]
        let sorted = statuses.sorted()
        XCTAssertEqual(sorted, [.operational, .unknown, .degradedPerformance, .partialOutage, .majorOutage])
    }

    func testMaxWithUnknownSurfacesUnknown() {
        // .unknown surfaces above .operational so the menu bar doesn't lie.
        let statuses: [ComponentStatus] = [.unknown, .operational]
        XCTAssertEqual(statuses.max(), .unknown)
    }

    func testMaxUnknownLosesToRealDegraded() {
        let statuses: [ComponentStatus] = [.unknown, .degradedPerformance]
        XCTAssertEqual(statuses.max(), .degradedPerformance,
                       "A real degraded signal must override an unknown one")
    }

    func testMaxAllUnknown() {
        let statuses: [ComponentStatus] = [.unknown, .unknown]
        XCTAssertEqual(statuses.max(), .unknown)
    }

    // MARK: - fromIndicator coverage

    func testFromIndicatorMaintenance() {
        XCTAssertEqual(ComponentStatus(fromIndicator: "maintenance"), .underMaintenance)
    }

    // MARK: - Labels

    func testLabelsNotEmpty() {
        let allCases: [ComponentStatus] = [
            .operational, .degradedPerformance, .partialOutage,
            .majorOutage, .underMaintenance, .unknown
        ]
        for status in allCases {
            XCTAssertFalse(status.label.isEmpty, "\(status) has empty label")
        }
    }

    // MARK: - Raw value round-trip

    func testRawValueRoundTrip() {
        let cases: [ComponentStatus] = [
            .operational, .degradedPerformance, .partialOutage,
            .majorOutage, .underMaintenance, .unknown
        ]
        for status in cases {
            XCTAssertEqual(ComponentStatus(rawValue: status.rawValue), status,
                           "Round-trip failed for \(status)")
        }
    }
}

final class InitialsAvatarColorTests: XCTestCase {
    /// Pinned values: `String.hashValue` changes every launch, so a stable
    /// hash must give the same index here on every run.
    func testPaletteIndexIsStableAcrossLaunches() {
        XCTAssertEqual(InitialsAvatarView.paletteIndex(for: "Zoom"), 8)
        XCTAssertEqual(InitialsAvatarView.paletteIndex(for: "Slack"), 7)
        XCTAssertEqual(InitialsAvatarView.paletteIndex(for: "GitHub"), 4)
    }

    func testPaletteIndexIsInRange() {
        for name in ["", "A", "1Password", "TextExpander", "Zoom Video", "ü"] {
            let index = InitialsAvatarView.paletteIndex(for: name)
            XCTAssertTrue(InitialsAvatarView.palette.indices.contains(index), name)
        }
    }
}
