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
        XCTAssertLessThan(ComponentStatus.operational.severity, ComponentStatus.degradedPerformance.severity)
        XCTAssertLessThan(ComponentStatus.degradedPerformance.severity, ComponentStatus.partialOutage.severity)
        XCTAssertLessThan(ComponentStatus.partialOutage.severity, ComponentStatus.majorOutage.severity)
    }

    func testUnknownSeverityIsNegative() {
        XCTAssertEqual(ComponentStatus.unknown.severity, -1)
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
        let statuses: [ComponentStatus] = [.majorOutage, .operational, .partialOutage, .degradedPerformance]
        let sorted = statuses.sorted()
        XCTAssertEqual(sorted, [.operational, .degradedPerformance, .partialOutage, .majorOutage])
    }

    func testMaxWithUnknown() {
        // .unknown has severity -1, so .operational (severity 0) should win
        let statuses: [ComponentStatus] = [.unknown, .operational]
        XCTAssertEqual(statuses.max(), .operational)
    }

    func testMaxAllUnknown() {
        let statuses: [ComponentStatus] = [.unknown, .unknown]
        XCTAssertEqual(statuses.max(), .unknown)
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
