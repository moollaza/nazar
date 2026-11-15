import AppKit
import XCTest
@testable import StatusMonitor

/// App Store "Sufficient Contrast": text needs 4.5:1, state indicators 3:1
/// (WCAG 2 relative luminance). These colors are fixed, so Increase Contrast
/// can't rescue them; they must pass by default.
final class ContrastTests: XCTestCase {
    private let statuses: [ComponentStatus] = [.operational, .degradedPerformance, .underMaintenance, .partialOutage, .majorOutage]
    private let backgrounds: [(NSAppearance.Name, NSColor)] = [
        (.aqua, .white), (.aqua, NSColor(white: 0.925, alpha: 1)), // #ECECEC
        (.darkAqua, NSColor(white: 0.118, alpha: 1)), (.darkAqua, NSColor(white: 0.196, alpha: 1)), // #1E1E1E, #323232
    ]

    func testStatusDotsMeetNonTextContrast() {
        for status in statuses + [.unknown] {
            for (appearance, bg) in backgrounds {
                let ratio = contrast(status.color, bg, appearance)
                XCTAssertGreaterThanOrEqual(ratio, 3, "\(status) dot in \(appearance.rawValue): \(ratio)")
            }
        }
    }

    func testStatusTextMeetsTextContrast() {
        for status in statuses {
            for (appearance, bg) in backgrounds {
                let ratio = contrast(status.textColor, bg, appearance)
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(status) text in \(appearance.rawValue): \(ratio)")
            }
        }
    }

    func testLinkTextMeetsTextContrast() {
        for (appearance, bg) in backgrounds {
            let ratio = contrast(.accessibleLink, bg, appearance)
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "link in \(appearance.rawValue): \(ratio)")
        }
    }

    private func contrast(_ fg: NSColor, _ bg: NSColor, _ name: NSAppearance.Name) -> Double {
        var result = 0.0
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
            let a = luminance(fg), b = luminance(bg)
            result = (max(a, b) + 0.05) / (min(a, b) + 0.05)
        }
        return result
    }

    private func luminance(_ color: NSColor) -> Double {
        let c = color.usingColorSpace(.sRGB)!
        func channel(_ v: CGFloat) -> Double {
            let v = Double(v)
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(c.redComponent) + 0.7152 * channel(c.greenComponent) + 0.0722 * channel(c.blueComponent)
    }
}
