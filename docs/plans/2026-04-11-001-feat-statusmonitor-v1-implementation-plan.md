---
title: "StatusMonitor v1 — Full Implementation"
type: feat
status: active
date: 2026-04-11
origin: docs/brainstorms/2026-04-09-statusmonitor-v1-requirements.md
deepened: 2026-04-11
---

# StatusMonitor v1 — Full Implementation Plan

## Overview

Execute all 14 v1 milestone issues to bring StatusMonitor from working prototype to shippable product. The app already has core polling, dashboard, notifications, and menu bar icon. This plan adds: bug fixes, a curated ~100-service catalog with onboarding picker, dashboard improvements (sort, icons, error states, status page links), notification tap handling, configurable polling, signed/notarized distribution, and a marketing website.

## Problem Statement / Motivation

The current prototype monitors 5 hardcoded services with no onboarding, no catalog, and several bugs (OpenAI parse error, placeholder bundle ID). A new user has to manually add services via URL — the success criterion of "monitoring 5 services in under 60 seconds" is impossible without a catalog picker. (see origin: `docs/brainstorms/2026-04-09-statusmonitor-v1-requirements.md`)

## Design Decisions (resolved)

These were resolved during research and SpecFlow analysis:

1. **All services errored → gray icon.** When every service is in error state, `recalcWorstStatus` returns `.unknown` (gray). The app genuinely can't determine status.
2. **First launch vs. user-emptied providers.** Use a `hasCompletedOnboarding` boolean in UserDefaults. First launch (flag absent) auto-shows catalog picker. Post-onboarding empty state shows R9 "Browse Catalog" CTA. **Migration guard**: if existing providers exist but flag is absent, set flag to true and skip onboarding.
3. **Catalog shows already-monitored services** as pre-checked and disabled (non-interactive). Matched via `catalogEntryId` field on Provider. Catalog is additive; removal is in Settings.
4. **Error-to-healthy transition: no notification.** The user doesn't know the fetch failed, so "recovery" would be confusing. Handle explicitly to prevent spurious notifications.
5. **Onboarding has a "Skip" button.** Empty-state dashboard (R9) provides a path back.
6. **Sleep/wake burst is acceptable** for 5-20 services. Cap concurrent polls at 6 for safety.
7. **Parse errors show user-friendly message** ("Unable to read status page") not raw Swift decoder errors.
8. **Poll interval minimum (30s) enforced in both model and UI.**
9. **Bundle ID: `com.moollapps.StatusMonitor`** (user confirmed).
10. **Monorepo restructure (ZPR-1) deferred** — not blocking v1 work.
11. **HTTP conditional GET deferred to v1.x** — R14 text is contradictory with roadmap; the v1 scope is "expose interval in UI" only.
12. **Secondary sort within severity tiers: alphabetical.** Prevents unpredictable reordering between polls.
13. **Separate `CatalogEntry` struct** (in Models.swift, not its own file) from `Provider`. Catalog entries are read-only reference data; selecting them creates `Provider` instances via `init(from catalogEntry:)`.
14. **Two status page platforms supported:** Atlassian Statuspage (full schema) and incident.io (reduced, Statuspage-compatible schema). All Codable fields that differ must be optional.
15. **2-tier icons only for v1:** Bundled assets for top ~20 services + initials avatars. No favicon fetching (deferred to v1.x per requirements scope boundary).
16. **Auto-open popover on first launch** for onboarding. Essential for "5 services in 60 seconds" success criterion.
17. **`@AppStorage` only in Views, not in `@Observable` classes** — use `didSet` + UserDefaults in `@Observable` (Apple Developer Forums thread 731187).

## Implementation Phases

### Phase 1: Bug Fixes & Foundation
**Branch: `fix/v1-bugs-and-foundation`**
**Issues: ZPR-2, ZPR-3, ZPR-4, ZPR-10**
**Estimated scope: Medium** (7 subtasks including security hardening and polling refactor)

#### 1a. Fix bundle ID (ZPR-2)

Update `Info.plist` `CFBundleIdentifier` from `com.yourname.StatusMonitor` to `com.moollapps.StatusMonitor`. Update `PRODUCT_BUNDLE_IDENTIFIER` in `project.pbxproj` from `MoollApps.StatusMonitor` to `com.moollapps.StatusMonitor` (proper reverse-DNS format).

**Files:**
- `Info.plist` — change `CFBundleIdentifier`
- `StatusMonitor.xcodeproj/project.pbxproj` — change `PRODUCT_BUNDLE_IDENTIFIER` in both Debug and Release configs

#### 1b. Fix OpenAI parse error (ZPR-3)

**Root cause (confirmed by research):** OpenAI uses **incident.io**, not Atlassian Statuspage. incident.io provides a Statuspage-compatible API but with a reduced schema:
- `incidents` and `scheduled_maintenances` are **MISSING** from `/api/v2/summary.json`
- Component fields `description`, `showcase`, `start_date`, `group_id`, `group`, `only_show_if_degraded` are missing
- Page field `time_zone` is missing

**Fix:** Make all non-universal fields optional in the Codable structs.

```swift
// StatuspageSummary
let incidents: [StatuspageIncident]?           // was non-optional
let scheduledMaintenances: [StatuspageIncident]? // new, optional

// StatuspagePage
let timeZone: String?  // was likely non-optional

// StatuspageComponent — already has custom init(from:), extend it
// Make description, showcase, startDate, groupId, group, onlyShowIfDegraded all optional
```

Also add `"under_maintenance"` as a valid component status (used during scheduled maintenances on Atlassian).

**Files:**
- `Models/Models.swift` — make fragile fields optional, add `underMaintenance` case to ComponentStatus
- `Services/StatusManager.swift` — handle nil values in `parseStatuspage()`, use `?? []` for optional arrays

#### 1c. Close ZPR-4 (Slack 404)

Slack was already removed from defaults in commit `137d75a`. Close the Linear issue.

#### 1d. Fix error state handling (ZPR-10)

**Current bug:** `recalcWorstStatus()` includes error snapshots. Spec says to explicitly exclude them.

**Changes:**
- `Services/StatusManager.swift`:
  - Filter `snapshots` to exclude those with non-nil `error` before computing `.max()` in `recalcWorstStatus()`
  - In `updateSnapshot(error:)`, set user-friendly error message ("Unable to read status page") instead of raw error strings
  - **Fix static DateFormatter:** Replace per-call `ISO8601DateFormatter()` allocation with a `private static let` (performance finding)
- `Views/DashboardView.swift`:
  - Show gray circle + "Unavailable" for error snapshots
  - Add empty state: when `manager.providers.isEmpty`, show "No services monitored" + "Browse Catalog" CTA
  - Distinguish "loading" (providers exist, snapshots empty) from "empty" (no providers)

#### 1e. Add .gitignore and URL validation

- Create standard macOS/Xcode `.gitignore`
- Add URL scheme validation to `Provider.init`: reject non-http(s) schemes
- Add basic URL format validation to the add-provider UI

#### 1f. Security hardening

- `Services/RSSParser.swift` — add `parser.shouldResolveExternalEntities = false` for defense in depth
- Truncate notification body content to 200 characters to prevent spoofing via malicious status pages

#### 1g. Cap concurrent polls (performance)

Replace unbounded `Task` spawning in `pollAll()` and `startPolling()` with a `TaskGroup` limited to 6 concurrent requests. Prevents resource exhaustion with 50+ providers.

---

### Phase 2: Catalog Data & Model (ZPR-5)
**Branch: `feat/service-catalog`**
**Issue: ZPR-5**
**Estimated scope: Medium**

#### 2a. Add CatalogEntry and update Provider model

Add to `Models/Models.swift`:

```swift
struct CatalogEntry: Identifiable, Codable, Equatable {
    let id: String          // kebab-case slug, e.g. "github"
    let name: String        // Display name, e.g. "GitHub"
    let baseURL: String     // Status page base URL
    let type: ProviderType  // .statuspage or .rss
    let category: String    // e.g. "Developer Tools"
}
```

Update `Provider`:
- Add `catalogEntryId: String?` — set when created from a catalog entry, enables matching in catalog picker
- Add `init(from catalogEntry: CatalogEntry)` convenience initializer
- Note: `category` lives on `CatalogEntry`, not on `Provider`. The dashboard doesn't group by category — it sorts by status. No need to duplicate the field.

#### 2b. Create static Catalog loader

Add to `Models/Models.swift` (or a new `Models/Catalog.swift` if it gets large):

```swift
struct Catalog {
    let entries: [CatalogEntry]
    let categories: [String]  // sorted unique category names

    static let shared: Catalog = {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return Catalog(entries: [], categories: [])
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let entries = (try? decoder.decode([CatalogEntry].self, from: data)) ?? []
        let categories = Array(Set(entries.map(\.category))).sorted()
        return Catalog(entries: entries, categories: categories)
    }()

    func entries(in category: String) -> [CatalogEntry] {
        entries.filter { $0.category == category }
    }

    func search(_ query: String) -> [CatalogEntry] {
        guard !query.isEmpty else { return entries }
        return entries.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
}
```

No `@Observable`, no environment injection needed. It's static data.

#### 2c. Create catalog.json

Bundle a `catalog.json` resource with ~100 verified entries. Research confirmed 70+ working URLs across these categories:

- **AI & ML:** Anthropic/Claude (`status.claude.com`), OpenAI, Pinecone, Replicate
- **Developer Tools & CI/CD:** GitHub, Bitbucket, CircleCI, Codecov, Linear, Sentry, npm, Docker, Deno, LaunchDarkly, HashiCorp
- **Cloud & Hosting:** Vercel, Cloudflare, DigitalOcean, Linode, Fly.io, Netlify, Render, Bunny.net
- **Databases:** Supabase, MongoDB, Snowflake, Confluent, Elastic, Upstash, Turso, Algolia
- **Productivity:** Asana, Notion, Figma, Miro, Monday.com, Airtable, Zapier, Calendly, Loom, Box, HubSpot
- **Communication:** Twilio, SendGrid, Intercom, PubNub
- **Security:** 1Password, WorkOS, Stytch, Clerk
- **Monitoring:** Datadog, New Relic, Grafana, Amplitude, Mixpanel
- **Payments:** Plaid, Segment
- **Social/Streaming:** Reddit, Twitch
- **Atlassian:** Jira, Confluence, Trello, Bitbucket

Must-haves per user: **Asana, Anthropic, OpenAI, Sportradar** (Sportradar status page URL needs verification during implementation — check `status.sportradar.com` or similar).

**Note:** `status.anthropic.com` redirects to `status.claude.com`. Use the canonical URL.

**Files:**
- `Resources/catalog.json` (new)
- `Models/Models.swift` — add CatalogEntry, update Provider, add Catalog struct
- `StatusMonitor.xcodeproj/project.pbxproj` — add catalog.json to Copy Bundle Resources

#### 2d. Update Provider.defaults and loadProviders()

- Remove or minimize `Provider.defaults` (onboarding handles initial selection now)
- Update `loadProviders()`: if saved providers exist but `hasCompletedOnboarding` is false, set flag to true (migration guard for existing prototype users)
- If no providers and no onboarding flag, return empty list (triggers onboarding in view)

---

### Phase 3: Catalog Picker & Onboarding (ZPR-6)
**Branch: `feat/catalog-picker`**
**Issue: ZPR-6**
**Estimated scope: Large (biggest feature)**

#### 3a. Build CatalogPickerView

**Files:** `Views/CatalogPickerView.swift` (new)

Use SwiftUI `List` + `Section(isExpanded:)` + `.searchable()` + `.toggleStyle(.checkbox)`:

```
Layout:
┌─────────────────────────────────────┐
│  Browse Services          [Skip/Done] │
│  ┌─────────────────────────────────┐ │
│  │ 🔍 Search services...          │ │
│  └─────────────────────────────────┘ │
│                                       │
│  ▸ AI/ML (4)                          │
│    ☑ Anthropic                        │
│    ☐ Hugging Face                     │
│    ☑ OpenAI           (already added) │
│    ☐ Replicate                        │
│  ▸ Cloud Providers (6)                │
│    ...                                │
│                                       │
│  ┌─────────────────────────────────┐ │
│  │   Add 3 Selected                │ │
│  └─────────────────────────────────┘ │
└─────────────────────────────────────┘
```

**Key patterns (from research):**
- `.toggleStyle(.checkbox)` for native macOS checkboxes
- `.searchable(text:placement:.sidebar)` for native search field
- `Section(category, isExpanded: binding)` for collapsible categories
- Already-monitored services matched via `provider.catalogEntryId` — pre-checked and disabled
- "Add N Selected" button disabled when N=0
- "Skip" button (onboarding) or "Done" button (Settings)

#### 3b. Wire onboarding flow (view-level, not AppDelegate)

In `DashboardView`, check `@AppStorage("hasCompletedOnboarding")`:
- If false and providers empty → show catalog picker inline, replacing dashboard content (not a sheet — the picker IS the first-run experience)
- After selection or skip → set flag to true

In `AppDelegate.applicationDidFinishLaunching` → auto-open popover on first launch:
```swift
if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
    DispatchQueue.main.async { self.togglePopover() }
}
```

**Files:**
- `Views/CatalogPickerView.swift` (new)
- `Views/DashboardView.swift` — onboarding state check, inline catalog picker presentation
- `StatusMonitorApp.swift` — auto-open popover on first launch

#### 3c. Wire Settings access (R4)

Add "Browse Catalog" button in `SettingsView`.

**Files:**
- `Views/SettingsView.swift` — add button + sheet

---

### Phase 4: Dashboard Improvements (ZPR-8, ZPR-9)
**Branch: `feat/dashboard-improvements`**
**Issues: ZPR-8, ZPR-9**
**Estimated scope: Small**

#### 4a. Sort toggle (ZPR-8)

Add `enum DashboardSort: String { case severity, alphabetical }` with `@AppStorage("dashboardSort")` in the **view** (not in an @Observable class). Segmented picker in header. Secondary alphabetical sort within severity tiers for stability.

**Files:**
- `Views/DashboardView.swift` — sort enum, @AppStorage, segmented control, sort logic

#### 4b. "View status page" link (ZPR-9)

Look up `Provider.baseURL` from `manager.providers` using the snapshot's id. Add "View Status Page" button in expanded row that calls `NSWorkspace.shared.open(url)`.

**No model change needed** — Provider already has baseURL.

**Files:**
- `Views/DashboardView.swift` — add link button in expanded section

---

### Phase 5: Service Icons (ZPR-7)
**Branch: `feat/service-icons`**
**Issue: ZPR-7**
**Estimated scope: Small (simplified from original Medium)**

#### 5a. Create Assets.xcassets

Create asset catalog with AppIcon set (required for distribution). Ship v1 with initials avatars universally — do not block on sourcing service logos. If time permits, add icons for the top ~10 services (GitHub, Cloudflare, etc.) from press kits, but this is stretch, not required.

#### 5b. Build ServiceIconView (2-tier: bundled → initials)

```swift
// Views/ServiceIconView.swift (new)
struct ServiceIconView: View {
    let name: String
    let catalogId: String?  // matches asset name if bundled

    var body: some View {
        if let catalogId, let nsImage = NSImage(named: catalogId) {
            Image(nsImage: nsImage)
                .resizable()
                .frame(width: 20, height: 20)
        } else {
            InitialsAvatarView(name: name)
        }
    }
}

struct InitialsAvatarView: View {
    let name: String
    // Deterministic color from name hash
    // First letter centered in colored circle
}
```

Both tiers are **synchronous** — no async loading, no flicker on scroll.

**Files:**
- `Assets.xcassets/` (new) — AppIcon + optional service icons
- `Views/ServiceIconView.swift` (new)
- `Views/DashboardView.swift` — replace colored dot with ServiceIconView
- `StatusMonitor.xcodeproj/project.pbxproj` — add asset catalog

---

### Phase 6: Notifications & Polling (ZPR-11, ZPR-12)
**Branch: `feat/notifications-and-polling`**
**Issues: ZPR-11, ZPR-12**
**Estimated scope: Small**

#### 6a. Notification tap opens popover (ZPR-11)

Use the callback pattern (matches existing `onWorstStatusChanged`):

```swift
// In NotificationService
var onNotificationTapped: (@MainActor @Sendable () -> Void)?

func userNotificationCenter(_ center: UNUserNotificationCenter,
                            didReceive response: UNNotificationResponse,
                            withCompletionHandler completionHandler: @escaping () -> Void) {
    Task { @MainActor in onNotificationTapped?() }
    completionHandler()
}
```

**Important (from research):**
- Set `UNUserNotificationCenter.current().delegate` in `applicationDidFinishLaunching` **before** anything else
- `.defaultCritical` sound requires Apple entitlement approval — falls back to `.default` without it
- macOS may not call `didReceive` when user dismisses via "X" button

**Files:**
- `Services/NotificationService.swift` — add `didReceive`, `onNotificationTapped` callback
- `StatusMonitorApp.swift` — set callback, ensure delegate is set first

#### 6b. Poll interval UI (ZPR-12)

Add per-provider poll interval control in Settings. Picker options: 30s, 60s, 2m, 5m, 15m. Clamp in `Provider.init`: `pollIntervalSeconds = max(30, pollIntervalSeconds)`.

**Files:**
- `Models/Models.swift` — clamp pollIntervalSeconds in init
- `Views/SettingsView.swift` — add interval picker per provider
- `Services/StatusManager.swift` — reschedule timer when interval changes

---

### Phase 7: Distribution (ZPR-13)
**Branch: `feat/distribution`**
**Issue: ZPR-13**
**Estimated scope: Medium**

#### 7a. Prepare for distribution

- Verify Developer ID Application certificate
- Create app icon in Assets.xcassets
- Verify sandbox entitlements
- Store notarization credentials via `xcrun notarytool store-credentials` (keychain, not in scripts)

#### 7b. Build script

```bash
# scripts/build-dmg.sh
# 1. xcodebuild archive with Developer ID
# 2. xcodebuild -exportArchive with ExportOptions.plist
# 3. ditto -c -k for notarization zip
# 4. xcrun notarytool submit --keychain-profile "notary-profile" --wait
# 5. xcrun stapler staple
# 6. Create DMG with create-dmg or hdiutil
```

**ExportOptions.plist:**
```xml
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>W4HBM3A7DC</string>
    <key>signingStyle</key><string>automatic</string>
</dict>
```

**Files:**
- `ExportOptions.plist` (new)
- `scripts/build-dmg.sh` (new) — never hardcode passwords, use keychain profile

---

### Phase 8: Marketing Website (ZPR-14)
**Branch: `feat/marketing-website`**
**Issue: ZPR-14**
**Estimated scope: Medium**

Build per website requirements doc. Static HTML + Tailwind CSS CDN (SRI hash pinned). No JavaScript.

**Files:**
- `website/index.html` (new)
- `website/assets/logos/` (new) — ~20 service logos
- `website/assets/screenshot.png` (new) — after UI complete

---

## Acceptance Criteria

### Functional
- [ ] Bundle ID is `com.moollapps.StatusMonitor` everywhere
- [ ] OpenAI status page parses successfully (incident.io compatibility)
- [ ] ZPR-4 closed in Linear
- [ ] Error services show gray "Unavailable", excluded from worst-status
- [ ] Dashboard distinguishes "loading" from "no services"
- [ ] ~100 services in bundled catalog with categories
- [ ] Catalog picker: search, browse categories, multi-select, add
- [ ] First launch auto-opens popover with catalog picker
- [ ] Catalog accessible from Settings post-onboarding
- [ ] Dashboard sort toggle (severity/A-Z) persists across sessions
- [ ] Expanded row has "View Status Page" link
- [ ] Service rows show icon (bundled asset or initials avatar)
- [ ] Notification tap opens app popover
- [ ] Poll interval configurable per-service in Settings (min 30s)
- [ ] Concurrent polls capped at 6
- [ ] URL scheme validation on custom providers
- [ ] App builds with no warnings
- [ ] .gitignore stops tracking xcuserdata

### Distribution
- [ ] App can be archived with Developer ID signing
- [ ] DMG created and notarized
- [ ] Marketing website deployed to GitHub Pages

### Quality
- [ ] No raw Swift error strings shown to users
- [ ] Sort is stable (alphabetical secondary within severity)
- [ ] Onboarding handles skip and migration gracefully
- [ ] Previously-monitored services shown as disabled in catalog
- [ ] RSS parser explicitly disables external entity resolution

## Dependencies & Prerequisites

- Apple Developer Program membership (active — team ID W4HBM3A7DC)
- App icon design (needed before distribution)
- App screenshot (needed before website)
- ~20 service logos for website catalog preview

## Risk Analysis

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| incident.io schema changes | Low | Medium | All Codable fields optional; defensive decoding |
| Icon sourcing takes too long | High | Low | Ship with initials avatars universally (simplified from original plan) |
| Catalog curation misses services | Low | Low | Catalog is bundled, expandable in app updates |
| Notarization issues | Medium | Medium | Test early with minimal signed build; use `notarytool log` for debugging |
| Popover lifecycle (onAppear fires once) | Medium | Low | Use NSPopover.willShowNotification for refresh-on-open logic |

## Execution Order

```
Phase 1 (bugs/foundation) ──► Phase 2 (catalog data) ──► Phase 3 (catalog picker)
                                   │
Phase 4 (dashboard) ◄── after Phase 1 only
Phase 5 (icons) ◄── after Phase 2 (catalog determines which icons to bundle)
Phase 6 (notifications/polling) ◄── after Phase 1 only
Phase 7 (distribution) ◄── after Phase 5 (needs app icon)
Phase 8 (website) ◄── after Phase 7 (needs screenshot + download link)
```

Phases 4, 5, and 6 can run in parallel after their dependencies are met.

## New Files Summary

| File | Purpose |
|------|---------|
| `Resources/catalog.json` | Bundled catalog of ~100 services |
| `Views/CatalogPickerView.swift` | Searchable, categorized catalog picker |
| `Views/ServiceIconView.swift` | 2-tier icon view (bundled + initials) |
| `Assets.xcassets/` | App icon + optional service icons |
| `ExportOptions.plist` | Developer ID export options |
| `scripts/build-dmg.sh` | Build + sign + notarize automation |
| `website/index.html` | Marketing website |
| `.gitignore` | Standard macOS/Xcode ignores |

**Total new Swift files: 2** (down from 4-5 in original plan)

## Sources & References

- **Origin document:** [docs/brainstorms/2026-04-09-statusmonitor-v1-requirements.md](docs/brainstorms/2026-04-09-statusmonitor-v1-requirements.md)
- **Website requirements:** [docs/brainstorms/2026-04-09-statusmonitor-website-requirements.md](docs/brainstorms/2026-04-09-statusmonitor-website-requirements.md)
- **Linear project:** https://linear.app/moollaza/project/statusmonitor-ac69e82c3ceb
- **incident.io Statuspage compatibility:** Confirmed via curl — OpenAI, Linear, HashiCorp use incident.io with reduced schema
- **@Observable + @AppStorage gotcha:** Apple Developer Forums thread 731187 — cannot combine them; use didSet + UserDefaults
- **macOS popover lifecycle:** NSHostingController persists — onAppear fires once, not on every popover open
- **UNUserNotificationCenter macOS:** Delegate must be set before applicationDidFinishLaunching returns
- **Notarization:** Use `xcrun notarytool store-credentials` for keychain-based auth, never hardcode passwords
