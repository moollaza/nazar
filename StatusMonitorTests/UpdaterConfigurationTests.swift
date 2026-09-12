import XCTest
@testable import StatusMonitor

/// Guards the Sparkle keys that Config/Sparkle-Info.plist maps from
/// Config/Sparkle.xcconfig. A typo there fails silently at runtime — Sparkle
/// just never finds an update — so it's checked in the built bundle instead.
final class UpdaterConfigurationTests: XCTestCase {

    private func infoValue<T>(_ key: String, as type: T.Type) throws -> T {
        let value = Bundle.main.object(forInfoDictionaryKey: key)
        return try XCTUnwrap(value as? T, "\(key) missing or not a \(T.self) in the app bundle")
    }

    func testFeedURLPointsAtTheRedirect() throws {
        // The app only ever knows the usenazar.com URL; that redirects to the
        // newest release's appcast asset (website/_redirects).
        let feed: String = try infoValue("SUFeedURL", as: String.self)
        XCTAssertEqual(feed, "https://usenazar.com/appcast.xml")
    }

    func testPublicEdKeyIsA32ByteEd25519Key() throws {
        let key: String = try infoValue("SUPublicEDKey", as: String.self)
        let decoded = try XCTUnwrap(Data(base64Encoded: key), "SUPublicEDKey is not valid base64")
        XCTAssertEqual(decoded.count, 32, "An ed25519 public key is 32 bytes")
    }

    func testInstallerLauncherServiceIsEnabled() throws {
        // Required for the sandboxed installer XPC service (KTD3); without it
        // the download verifies but can't be installed.
        let enabled: Bool = try infoValue("SUEnableInstallerLauncherService", as: Bool.self)
        XCTAssertTrue(enabled)
    }

    /// Sparkle's xcconfig became the target-level base configuration, which is
    /// where the version single-source could have been lost (see #43).
    func testBundleVersionsStillComeFromVersionXcconfig() throws {
        let short: String = try infoValue("CFBundleShortVersionString", as: String.self)
        let build: String = try infoValue("CFBundleVersion", as: String.self)
        XCTAssertFalse(short.isEmpty)
        XCTAssertFalse(build.isEmpty)
        XCTAssertNotEqual(short, "$(MARKETING_VERSION)", "MARKETING_VERSION was not substituted")
        XCTAssertNotEqual(build, "$(CURRENT_PROJECT_VERSION)", "CURRENT_PROJECT_VERSION was not substituted")
    }
}
