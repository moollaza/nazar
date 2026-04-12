---
title: "ZPR-26 — Add XCTest Target with Unit Tests for Core Logic"
type: feat
status: draft
date: 2026-04-11
linear: ZPR-26
---

# ZPR-26 — Add XCTest Target with Unit Tests for Core Logic

## Overview

Add a `StatusMonitorTests` XCTest target to the Xcode project and write unit tests covering all critical non-UI logic: status parsing, Codable decoding, catalog operations, provider validation, worst-status calculation, and RSS parsing. No UI tests for v1.

## Problem Statement

The app has 10 Swift files and zero tests. Core parsing and status logic is the most critical code to verify — a decoding regression means silent failures for users. The OpenAI/incident.io compatibility fix (ZPR-3) already proved that schema variations cause real bugs. Tests prevent regressions and enable confident refactoring.

## Scope

**In scope:** Unit tests for all non-UI logic in `Models/Models.swift`, `Services/StatusManager.swift`, `Services/RSSParser.swift`, and `Services/NotificationService.swift`.

**Out of scope:** UI tests, snapshot tests, integration tests hitting live APIs. Manual testing in Xcode covers the popover UI adequately for v1.

---

## Test Target Setup

### Adding StatusMonitorTests to the Xcode Project

1. **Create directory:** `StatusMonitorTests/` at the repo root (sibling to `Models/`, `Services/`, `Views/`)
2. **Add test target in Xcode:** File > New > Target > macOS > Unit Testing Bundle
   - Product Name: `StatusMonitorTests`
   - Target to be Tested: `StatusMonitor`
   - Language: Swift
3. **pbxproj changes** (Xcode handles these automatically when adding via UI):
   - New `PBXNativeTarget` for `StatusMonitorTests`
   - New `PBXGroup` for `StatusMonitorTests/`
   - `TEST_HOST = "$(BUILT_PRODUCTS_DIR)/StatusMonitor.app/Contents/MacOS/StatusMonitor"`
   - `BUNDLE_LOADER = $(TEST_HOST)`
   - `@testable import StatusMonitor` enabled via `ENABLE_TESTING_SEARCH_PATHS = YES`
4. **Test bundle resources:** Add a `TestData/` subdirectory within `StatusMonitorTests/` for JSON fixtures. Add these files to the test target's Copy Bundle Resources build phase.

### File Structure

```
StatusMonitorTests/
  ComponentStatusTests.swift
  CodableTests.swift
  CatalogTests.swift
  ProviderTests.swift
  StatusManagerTests.swift
  RSSParserTests.swift
  TestData/
    atlassian-summary.json
    incidentio-summary.json
    sample-rss.xml
    sample-atom.xml
```

---

## Test Files

### 1. ComponentStatusTests.swift

Tests the `ComponentStatus` enum — parsing, severity ordering, and `Comparable` conformance.

**Test cases:**

| Test | What it verifies |
|------|-----------------|
| `testFromStatuspageOperational` | `ComponentStatus(fromStatuspage: "operational")` == `.operational` |
| `testFromStatuspageDegradedPerformance` | `"degraded_performance"` maps to `.degradedPerformance` |
| `testFromStatuspagePartialOutage` | `"partial_outage"` maps to `.partialOutage` |
| `testFromStatuspageMajorOutage` | `"major_outage"` maps to `.majorOutage` |
| `testFromStatuspageUnderMaintenance` | `"under_maintenance"` maps to `.underMaintenance` |
| `testFromStatuspageUnknownString` | `"garbage"` maps to `.unknown` |
| `testFromStatuspageEmptyString` | `""` maps to `.unknown` |
| `testFromIndicatorNone` | `ComponentStatus(fromIndicator: "none")` == `.operational` |
| `testFromIndicatorMinor` | `"minor"` maps to `.degradedPerformance` |
| `testFromIndicatorMajor` | `"major"` maps to `.partialOutage` |
| `testFromIndicatorCritical` | `"critical"` maps to `.majorOutage` |
| `testFromIndicatorUnknownString` | `"foo"` maps to `.unknown` |
| `testSeverityOrdering` | `.operational < .degradedPerformance < .partialOutage < .majorOutage` |
| `testUnknownSeverityIsNegative` | `.unknown.severity == -1` (excluded from worst-status via `max()`) |
| `testMaintenanceSeverityEqualsDegraded` | `.underMaintenance.severity == .degradedPerformance.severity` |
| `testComparableMax` | `[.operational, .majorOutage, .partialOutage].max() == .majorOutage` |
| `testComparableSorted` | Sorted array is in ascending severity order |
| `testLabelsNotEmpty` | Every case has a non-empty `label` string |
| `testRawValueRoundTrip` | `ComponentStatus(rawValue: status.rawValue) == status` for all cases except `.unknown` which has rawValue `"unknown"` |

**Notes:**
- These are pure value-type tests. No mocking needed.
- Tests verify that `Comparable` conformance uses severity, not raw value alphabetical order.

---

### 2. CodableTests.swift

Tests `StatuspageSummary` and related struct decoding from real-world JSON shapes.

**Test data (embedded as string literals or test bundle resources):**

**Atlassian JSON fixture** (`atlassian-summary.json`) — based on real GitHub status page shape:
```json
{
  "page": { "name": "GitHub", "url": "https://www.githubstatus.com", "updated_at": "2026-01-01T00:00:00Z" },
  "status": { "indicator": "none", "description": "All Systems Operational" },
  "components": [
    { "id": "abc123", "name": "Git Operations", "status": "operational", "description": "Git pulls and pushes", "updated_at": "2026-01-01T00:00:00Z" },
    { "id": "def456", "name": "API Requests", "status": "degraded_performance", "description": null, "updated_at": "2026-01-01T00:00:00Z" }
  ],
  "incidents": [
    {
      "id": "inc1", "name": "Elevated error rates", "status": "investigating", "impact": "minor",
      "created_at": "2026-01-01T00:00:00Z", "updated_at": "2026-01-01T00:00:00Z",
      "incident_updates": [
        { "id": "upd1", "status": "investigating", "body": "We are investigating.", "created_at": "2026-01-01T00:00:00Z" }
      ]
    }
  ],
  "scheduled_maintenances": []
}
```

**incident.io JSON fixture** (`incidentio-summary.json`) — based on real OpenAI status page shape (missing fields):
```json
{
  "page": { "name": "OpenAI", "url": "https://status.openai.com" },
  "status": { "indicator": "none", "description": "All Systems Operational" },
  "components": [
    { "id": "xyz789", "name": "API", "status": "operational" }
  ]
}
```
Note: no `incidents`, no `scheduled_maintenances`, no `updated_at` on page, no `description`/`updated_at` on component.

**Test cases:**

| Test | What it verifies |
|------|-----------------|
| `testDecodeAtlassianFullResponse` | Full Atlassian JSON decodes without error. All fields populated correctly. |
| `testDecodeAtlassianPageFields` | `page.name`, `page.url`, `page.updatedAt` parsed correctly |
| `testDecodeAtlassianStatusFields` | `status.indicator` and `status.description` parsed correctly |
| `testDecodeAtlassianComponents` | Components array decoded with correct count, IDs, names, statuses |
| `testDecodeAtlassianComponentOptionalDescription` | `description: null` in JSON decoded as `nil` |
| `testDecodeAtlassianIncidents` | `incidents` array decoded; incident has updates |
| `testDecodeAtlassianScheduledMaintenances` | `scheduled_maintenances` key decoded (even if empty) |
| `testDecodeIncidentIOMinimalResponse` | incident.io JSON (missing `incidents`, `scheduled_maintenances`, `updated_at`) decodes without error |
| `testDecodeIncidentIOPageNoUpdatedAt` | `page.updatedAt` is `nil` when absent from JSON |
| `testDecodeIncidentIOComponentNoDescription` | `description` is `nil` when key is absent |
| `testDecodeIncidentIOComponentNoUpdatedAt` | `updatedAt` is `nil` when key is absent |
| `testDecodeIncidentIOMissingIncidents` | `incidents` is `nil` when key is absent from JSON |
| `testDecodeIncidentIOMissingScheduledMaintenances` | `scheduledMaintenances` is `nil` when key is absent |
| `testDecodeInvalidJSONThrows` | Garbage data throws `DecodingError` |
| `testDecodeEmptyComponentsArray` | Components can be an empty array |
| `testIncidentUpdateFields` | `StatuspageIncidentUpdate` decodes `id`, `status`, `body`, `created_at` |

**Notes:**
- Use `JSONDecoder()` (no `keyDecodingStrategy`) since the models use explicit `CodingKeys`.
- Fixtures should be minimal but structurally accurate — copy the shape from real API responses.
- Prefer test bundle resources over inline strings for readability; both approaches work.

---

### 3. CatalogTests.swift

Tests `Catalog` loading, search, and category filtering.

**Challenge:** `Catalog.shared` uses `Bundle.main` which in a test target resolves to the test runner, not the app. Two options:

- **Option A (recommended):** Refactor `Catalog` to accept a `Bundle` parameter with a default of `.main`. Tests pass `Bundle(for: type(of: self))` or `Bundle.module` and include `catalog.json` in the test target's bundle. This is the cleanest approach but requires a small production code change.
- **Option B:** Test against `Catalog.shared` by relying on `TEST_HOST` / `BUNDLE_LOADER` settings, which make the test run inside the app's process and thus `Bundle.main` resolves to the app bundle. This works if the test target is configured as a hosted unit test (which it should be).

**Recommended approach: Option B** (no production code change). Verify during implementation that `Bundle.main` resolves correctly in hosted tests. Fall back to Option A if it does not.

**Production code change (Option A, if needed):**
```swift
// Catalog initializer gains a bundle parameter
static func load(from bundle: Bundle = .main) -> Catalog { ... }
```

**Test cases:**

| Test | What it verifies |
|------|-----------------|
| `testCatalogLoads` | `Catalog.shared.entries` is non-empty |
| `testCatalogEntryCount` | Entry count matches expected (~65+ entries in current catalog.json) |
| `testCatalogCategoriesNotEmpty` | `categories` array is non-empty |
| `testCatalogCategoriesSorted` | `categories` array is sorted alphabetically |
| `testCatalogCategoriesAreUnique` | No duplicate category names |
| `testCatalogEntriesInCategory` | `entries(in: "Developer Tools")` returns only developer tool entries |
| `testCatalogEntriesInUnknownCategory` | `entries(in: "Nonexistent")` returns empty array |
| `testCatalogSearchFindsMatch` | `search("git")` returns entries containing "git" (case-insensitive) |
| `testCatalogSearchEmptyQuery` | `search("")` returns all entries |
| `testCatalogSearchNoMatch` | `search("zzzzzzz")` returns empty array |
| `testCatalogSearchCaseInsensitive` | `search("GITHUB")` finds GitHub entry |
| `testCatalogEntryHasValidFields` | Every entry has non-empty `id`, `name`, `baseURL`, `category` |
| `testCatalogEntryBaseURLIsHTTPS` | Every entry's `baseURL` starts with `https://` |
| `testKnownEntryExists` | `entries.first(where: { $0.id == "github" })` is non-nil with expected name |

---

### 4. ProviderTests.swift

Tests `Provider` initialization, URL validation, poll interval clamping, and catalog entry conversion.

**Test cases:**

| Test | What it verifies |
|------|-----------------|
| `testInitDefaultValues` | Default `pollIntervalSeconds` is 60, `isEnabled` is true, `catalogEntryId` is nil |
| `testInitTrimsTrailingSlash` | `Provider(name: "X", baseURL: "https://example.com/")` stores `"https://example.com"` |
| `testInitClampsLowPollInterval` | `pollIntervalSeconds: 10` is clamped to `30` |
| `testInitClampsBoundaryPollInterval` | `pollIntervalSeconds: 29` is clamped to `30`; `30` stays `30` |
| `testInitFromCatalogEntry` | `Provider(from: catalogEntry)` copies name, baseURL, type, sets catalogEntryId |
| `testInitFromCatalogEntryType` | RSS catalog entry creates provider with `.rss` type |
| `testHasValidURLAcceptsHTTPS` | `https://status.github.com` returns `true` |
| `testHasValidURLAcceptsHTTP` | `http://status.github.com` returns `true` |
| `testHasValidURLRejectsNoScheme` | `status.github.com` returns `false` |
| `testHasValidURLRejectsFTP` | `ftp://example.com` returns `false` |
| `testHasValidURLRejectsJavascript` | `javascript:alert(1)` returns `false` |
| `testHasValidURLRejectsEmpty` | `""` returns `false` |
| `testAPIURLStatuspage` | `.statuspage` provider returns URL ending in `/api/v2/summary.json` |
| `testAPIURLRSS` | `.rss` provider returns the baseURL as-is |
| `testAPIURLInvalidBase` | Invalid baseURL returns `nil` for apiURL |
| `testProviderCodableRoundTrip` | Encode then decode a Provider; all fields match |
| `testProviderEquality` | Two providers with same UUID are equal |
| `testDefaultsIsEmpty` | `Provider.defaults` is empty (onboarding handles initial selection) |

---

### 5. StatusManagerTests.swift

Tests `recalcWorstStatus` logic. This is the most important business logic to verify.

**Challenge:** `StatusManager` is `@MainActor` and `@Observable`. Tests must run on the main actor. The `recalcWorstStatus()` method is private — test it indirectly by manipulating `snapshots` and observing `worstStatus`.

**Approach:** Since `snapshots` is a public `var`, tests can set it directly and then call a method that triggers `recalcWorstStatus()`. However, `recalcWorstStatus()` is only called from `applySnapshot()`, `updateSnapshot()`, and `removeProvider()` — all private.

**Recommended refactoring (minimal):** Either:
- **(A)** Make `recalcWorstStatus()` `internal` (not private) so tests can call it directly. This is the simplest approach.
- **(B)** Add a small test helper that sets snapshots and calls recalc.

**Go with (A):** Change `private func recalcWorstStatus()` to `func recalcWorstStatus()` (internal access). This is a one-word change and the method has no side effects beyond updating `worstStatus` and calling `onWorstStatusChanged`.

**Test cases:**

| Test | What it verifies |
|------|-----------------|
| `testWorstStatusAllOperational` | Snapshots all `.operational` -> `worstStatus == .operational` |
| `testWorstStatusOneDegraded` | One `.degradedPerformance` among `.operational` -> `worstStatus == .degradedPerformance` |
| `testWorstStatusMajorOutage` | One `.majorOutage` -> `worstStatus == .majorOutage` |
| `testWorstStatusExcludesErrors` | Snapshots with `error != nil` are excluded from worst calculation |
| `testWorstStatusAllErrors` | All snapshots have errors -> `worstStatus == .operational` (default) |
| `testWorstStatusEmpty` | No snapshots -> `worstStatus == .operational` |
| `testWorstStatusMixedWithErrors` | Mix of healthy, degraded, and error snapshots; error ones ignored |
| `testWorstStatusUnknownExcludedFromMax` | `.unknown` severity is -1, so `.operational` beats it via `max()` |
| `testOnWorstStatusChangedCallback` | `onWorstStatusChanged` fires when status changes, does not fire when unchanged |

**Test helper:**
```swift
// Create a ProviderSnapshot for testing
func makeSnapshot(
    status: ComponentStatus,
    error: String? = nil
) -> ProviderSnapshot {
    ProviderSnapshot(
        id: UUID(),
        name: "Test",
        overallStatus: status,
        components: [],
        activeIncidents: [],
        lastUpdated: Date(),
        error: error
    )
}
```

**Notes:**
- All tests must be `@MainActor` since `StatusManager` is `@MainActor`.
- Do NOT test `poll()`, `startPolling()`, or network calls — those require mocking URLSession which is out of scope for v1.
- `loadProviders()` reads from UserDefaults — test it by seeding UserDefaults in `setUp()` and cleaning up in `tearDown()`. Or skip it if too coupled; the critical logic is `recalcWorstStatus`.

---

### 6. RSSParserTests.swift

Tests `RSSStatusParser` XML parsing and the RSS status heuristic in `StatusManager.parseRSS`.

**Test data (test bundle resources):**

**RSS fixture** (`sample-rss.xml`):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>Service Status</title>
    <item>
      <title>Major outage in US-East</title>
      <description>We are investigating a major outage.</description>
      <guid>item-1</guid>
      <pubDate>Mon, 01 Jan 2026 00:00:00 +0000</pubDate>
    </item>
    <item>
      <title>Resolved: API latency</title>
      <description>This incident has been resolved.</description>
      <guid>item-2</guid>
      <pubDate>Sun, 31 Dec 2025 12:00:00 +0000</pubDate>
    </item>
  </channel>
</rss>
```

**Atom fixture** (`sample-atom.xml`):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Service Status</title>
  <entry>
    <title>Degraded performance on EU cluster</title>
    <summary>Elevated error rates observed.</summary>
    <id>entry-1</id>
    <published>2026-01-01T00:00:00Z</published>
  </entry>
</feed>
```

**Test cases:**

| Test | What it verifies |
|------|-----------------|
| `testParseRSSItemCount` | RSS feed with 2 items returns 2 `RSSItem`s |
| `testParseRSSItemTitle` | First item title matches |
| `testParseRSSItemDescription` | First item description matches |
| `testParseRSSItemGuid` | `guid` is parsed correctly |
| `testParseRSSItemPubDate` | `pubDate` is parsed into a `Date` (not nil) |
| `testParseRSSDateRFC822` | `"Mon, 01 Jan 2026 00:00:00 +0000"` parses successfully |
| `testParseAtomEntry` | Atom `<entry>` elements are parsed as items |
| `testParseAtomSummary` | Atom `<summary>` maps to `description` |
| `testParseAtomId` | Atom `<id>` maps to `guid` |
| `testParseAtomPublished` | Atom `<published>` maps to `pubDate` |
| `testParseEmptyFeed` | Empty `<channel>` returns empty array |
| `testParseInvalidXML` | Malformed XML returns empty array (no crash) |
| `testParseEmptyData` | Empty `Data()` returns empty array |
| `testHeuristicMajorOutage` | Title containing "major outage" -> `.majorOutage` |
| `testHeuristicPartialOutage` | Title containing "partial" -> `.partialOutage` |
| `testHeuristicDegraded` | Title containing "degraded" -> `.degradedPerformance` |
| `testHeuristicElevated` | Description containing "elevated" -> `.degradedPerformance` |
| `testHeuristicResolved` | Title containing "resolved" -> `.operational` |
| `testHeuristicUnknown` | Title with no keywords -> `.unknown` |

**Notes on heuristic tests:** The RSS status heuristic lives in `StatusManager.parseRSS()` which is private. Two options:
- **(A)** Extract the heuristic into a standalone function (e.g., `static func rssStatusHeuristic(title: String, description: String) -> ComponentStatus`) that can be tested directly. This is the cleanest approach and a small refactor.
- **(B)** Test it indirectly by calling the full parse flow, but that requires mocking URLSession.

**Recommended: Option A.** Extract the heuristic to a testable static function on `StatusManager` or as a free function. One-line change in `parseRSS()` to call it.

---

## Production Code Changes Required

These are minimal refactors to make the code testable. No behavior changes.

| File | Change | Reason |
|------|--------|--------|
| `Services/StatusManager.swift` | Change `private func recalcWorstStatus()` to `func recalcWorstStatus()` | Allow direct testing of worst-status logic |
| `Services/StatusManager.swift` | Extract RSS status heuristic to `static func rssStatusHeuristic(title: String, description: String) -> ComponentStatus` | Allow direct testing without URLSession mocking |

Total: 2 small refactors, no behavior changes.

---

## Test Data Strategy

1. **JSON fixtures:** Store as `.json` files in `StatusMonitorTests/TestData/`, added to the test target's Copy Bundle Resources. Load in tests via `Bundle(for: type(of: self)).url(forResource:withExtension:)`.
2. **XML fixtures:** Same approach for RSS/Atom XML files.
3. **Inline data:** For very small test cases (e.g., invalid JSON, empty objects), use string literals with `.data(using: .utf8)!`.
4. **No live API calls.** All test data is static.

---

## Adding the Test Target to the Xcode Project

The recommended approach is to add the target via Xcode's UI (File > New > Target > Unit Testing Bundle). This automatically generates the correct `pbxproj` entries. Manual `pbxproj` editing is fragile and error-prone.

**If adding programmatically** (e.g., via `xcodegen` or script), the key `pbxproj` entries needed are:

1. `PBXNativeTarget` — product type `com.apple.product-type.bundle.unit-test`
2. `PBXTargetDependency` — depends on `StatusMonitor` app target
3. `PBXBuildFile` entries for each `.swift` test file and each test resource
4. Build settings:
   - `TEST_HOST = "$(BUILT_PRODUCTS_DIR)/StatusMonitor.app/Contents/MacOS/StatusMonitor"`
   - `BUNDLE_LOADER = $(TEST_HOST)`
   - `PRODUCT_BUNDLE_IDENTIFIER = com.moollapps.StatusMonitorTests`
   - `SWIFT_VERSION = 5.0`
   - `MACOSX_DEPLOYMENT_TARGET = 13.0`
5. Test target added to the existing scheme's Test action

---

## Acceptance Criteria

- [ ] `StatusMonitorTests` target exists in the Xcode project
- [ ] `xcodebuild test` passes all tests from CLI
- [ ] Tests run via Cmd+U in Xcode
- [ ] All 6 test files present with all listed test cases
- [ ] Tests cover: ComponentStatus parsing, Codable decoding (Atlassian + incident.io), Catalog loading/search/filter, Provider validation/clamping, worst-status calculation, RSS/Atom parsing
- [ ] No tests hit the network
- [ ] Test data is embedded as bundle resources (not live API calls)
- [ ] 2 minimal production code refactors applied (recalcWorstStatus visibility, RSS heuristic extraction)
- [ ] All existing functionality unchanged (refactors are access-level only)

## Estimated Scope

**Medium.** 6 test files, ~70 test cases, 2 small production refactors, test target setup. No architectural changes.

## Dependencies

- Requires Phase 1 (ZPR-2, ZPR-3, ZPR-10) to be complete so tests verify the fixed code, not the buggy code.
- No external dependencies. XCTest is built into Xcode.
