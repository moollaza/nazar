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

    // MARK: - menuBarImage

    func testOperationalMenuBarImageIsTemplate() {
        XCTAssertEqual(ComponentStatus.operational.menuBarImage?.isTemplate, true)
    }

    /// Without the color baked in, these icons draw black on a dark menu bar.
    func testNonOperationalMenuBarImagesDrawInStatusColor() throws {
        for status in ComponentStatus.allCases where status != .operational {
            let image = try XCTUnwrap(status.menuBarImage, "\(status)")
            XCTAssertFalse(image.isTemplate, "\(status)")
            for name in [NSAppearance.Name.vibrantDark, .vibrantLight] {
                let appearance = try XCTUnwrap(NSAppearance(named: name))
                var expected = NSColor.black
                appearance.performAsCurrentDrawingAppearance {
                    expected = status.color.usingColorSpace(.sRGB) ?? .black
                }
                let rep = try XCTUnwrap(render(image, in: appearance))
                let drawn = try XCTUnwrap(mostOpaquePixel(in: rep), "\(status) \(name.rawValue)")
                XCTAssertEqual(drawn.redComponent, expected.redComponent, accuracy: 0.1, "\(status) \(name.rawValue)")
                XCTAssertEqual(drawn.greenComponent, expected.greenComponent, accuracy: 0.1, "\(status) \(name.rawValue)")
                XCTAssertEqual(drawn.blueComponent, expected.blueComponent, accuracy: 0.1, "\(status) \(name.rawValue)")
            }
        }
    }

    /// The tint must keep the symbol's shape, including the glyph cut out of
    /// `xmark.circle.fill`, not draw a solid disc or triangle.
    func testNonOperationalMenuBarImagesKeepTheSymbolShape() throws {
        let appearance = try XCTUnwrap(NSAppearance(named: .vibrantDark))
        for status in ComponentStatus.allCases where status != .operational {
            let tinted = try XCTUnwrap(status.menuBarImage.flatMap { render($0, in: appearance) }, "\(status)")
            let plain = try XCTUnwrap(status.menuBarSymbol.flatMap { render($0, in: appearance) }, "\(status)")
            var mismatched = 0
            for x in 0..<plain.pixelsWide {
                for y in 0..<plain.pixelsHigh {
                    let a = tinted.colorAt(x: x, y: y)?.alphaComponent ?? 0
                    let b = plain.colorAt(x: x, y: y)?.alphaComponent ?? 0
                    if abs(a - b) > 0.1 { mismatched += 1 }
                }
            }
            XCTAssertEqual(mismatched, 0, "\(status): \(mismatched) pixels differ in shape")
        }
    }

    /// Draws `image` at 2x under `appearance`.
    private func render(_ image: NSImage, in appearance: NSAppearance) -> NSBitmapImageRep? {
        let size = image.size
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        appearance.performAsCurrentDrawingAppearance {
            image.draw(in: NSRect(origin: .zero, size: size))
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private func mostOpaquePixel(in rep: NSBitmapImageRep) -> NSColor? {
        var best: NSColor?
        for x in 0..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if c.alphaComponent > (best?.alphaComponent ?? 0.5) { best = c }
            }
        }
        return best
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
