# Adding the StatusMonitorTests Target in Xcode

The test files are in `StatusMonitorTests/`. To run them, add a unit test target to the Xcode project:

## Steps

1. Open `StatusMonitor.xcodeproj` in Xcode
2. File > New > Target...
3. Select **macOS** > **Unit Testing Bundle**
4. Configure:
   - Product Name: `StatusMonitorTests`
   - Target to be Tested: `StatusMonitor`
   - Language: Swift
5. Click **Finish**

## After Creating the Target

1. **Delete the auto-generated test file** that Xcode creates (e.g. `StatusMonitorTests.swift`)
2. **Add existing test files**: Right-click `StatusMonitorTests` group > Add Files to "StatusMonitor"
   - Select all `.swift` files from the `StatusMonitorTests/` directory
   - Ensure "StatusMonitorTests" target is checked
3. **Verify build settings** (Xcode sets these automatically for hosted tests):
   - `TEST_HOST = $(BUILT_PRODUCTS_DIR)/StatusMonitor.app/Contents/MacOS/StatusMonitor`
   - `BUNDLE_LOADER = $(TEST_HOST)`
   - `MACOSX_DEPLOYMENT_TARGET = 13.0`

## Running Tests

- **Xcode**: Cmd+U to run all tests
- **CLI**: `xcodebuild test -project StatusMonitor.xcodeproj -scheme StatusMonitor -destination 'platform=macOS'`

## Notes

- The test target is a "hosted" unit test bundle, meaning tests run inside the app process. This allows `Bundle.main` to resolve to the app bundle (needed for `Catalog.shared` to load `catalog.json`).
- `@testable import StatusMonitor` gives tests access to `internal` symbols.
