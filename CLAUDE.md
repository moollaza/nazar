# Nazar

macOS menu bar app that watches the services users depend on and alerts on outages. Open source under Apache-2.0.

## Tech Stack

- **App**: Swift 5.9+, SwiftUI, macOS 14+, `@Observable` (not `ObservableObject`)
- **Architecture**: Menu bar accessory (`LSUIElement=true`), no Dock icon, floating NSPanel (not NSPopover)
- **Persistence**: `UserDefaults` for provider list and preferences
- **Network**: `URLSession` for polling; sandboxed (`com.apple.security.network.client`)
- **Website**: Static HTML + Tailwind CSS CDN (no build step), Cloudflare Pages at https://usenazar.com/
- **License**: Apache-2.0

## Repo Layout

```
StatusMonitor.xcodeproj   Xcode project
Models/                   Data models (Provider, CatalogEntry, Statuspage API types)
Views/                    SwiftUI views (Dashboard, Settings, Detail, Feedback, Icons)
Services/                 StatusManager, NotificationService, RSSParser
Resources/                catalog.json (1,683 verified services)
scripts/                  Discovery, verification, and categorization tooling
website/                  Marketing site (deployed to Cloudflare Pages)
docs/
  brainstorms/            Requirements docs
  plans/                  Implementation plans
```

## Build & Run

Open `StatusMonitor.xcodeproj` in Xcode and run the `StatusMonitor` scheme.

```bash
# Build from CLI (CI)
xcodebuild -project StatusMonitor.xcodeproj -scheme StatusMonitor -configuration Release build
```

## Key Conventions

- Use `@Observable` / `@Environment` (Swift 5.9 macro), not `ObservableObject`/`@StateObject`
- `StatusManager` is `@MainActor` — all snapshot mutations happen on main thread
- Dashboard uses a floating `NSPanel` (FloatingPanel class), NOT NSPopover (NSPopover has an arrow that can't be removed)
- Settings is a standalone `NSWindow` with `NSHostingController` — NOT the SwiftUI `Settings` scene (broken with `.accessory` policy)
- `@AppStorage` only in Views, never in `@Observable` classes (Apple bug causes infinite loops)
- Two parser types: `statuspage` (Atlassian JSON API at `/api/v2/summary.json`) and `rss`
- Bundle ID: `com.moollapps.StatusMonitor`
- Catalog entries need `platform` field: `"atlassian"` or `"incident.io"`

## Catalog

1,683 verified services across 22 categories. All entries have working `/api/v2/summary.json` endpoints.

To add services: use the `statuspage-discovery` skill or `scripts/discover-services.py`.
To verify catalog: `python3 scripts/audit-catalog.py`

## Workflow

This project uses the compound engineering skill suite:

```
/ce:brainstorm  →  /document-review  →  /ce:plan  →  /ce:work
```

- Requirements docs live in `docs/brainstorms/`
- Plans live in `docs/plans/`
- Keep commits short and factual

## Issue Tracking (Linear — required)

All work is tracked in Linear. **The Linear MCP must be connected before planning or implementation work begins.**

- **Project**: Nazar — https://linear.app/moollaza/project/statusmonitor-ac69e82c3ceb
- **Team**: Side Projects (`ZPR` prefix)
- **MCP**: `plugin:linear:linear` — connect via OAuth when starting a session

## Deployment

- **Website**: Deploys automatically to Cloudflare Pages on push to `main` via `.github/workflows/deploy-website.yml` -> https://usenazar.com/
- **App**: Distribution via signed DMG (not yet set up)

## Status Page Support

Most catalog services use Atlassian Statuspage or incident.io (compatible JSON schema). RSS/Atom feeds supported for non-Statuspage services. Custom proprietary status pages are out of scope.
