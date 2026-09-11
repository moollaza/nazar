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
Resources/                catalog.json (verified service catalog)
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
- Parser types: `statuspage` (Atlassian JSON API at `/api/v2/summary.json`), `rss` (generic RSS/Atom), `betterstack` (Better Stack JSON:API at `/index.json`), and `instatus` (Instatus JSON at `/summary.json`)
- Bundle ID: `com.moollapps.StatusMonitor`
- Catalog entries need a `platform` field matching their `type`: `atlassian` or `incident.io` for `statuspage`; `betterstack`, `instatus`, or `rss` for those types (the AWS, Azure, and GCP feeds use `aws`, `azure`, `gcp`)

## Catalog

Every entry must have a working endpoint: `/api/v2/summary.json` for `statuspage`, `/index.json` for `betterstack`, `/summary.json` for `instatus`, and the feed URL itself for `rss`. Count entries from the file rather than recording a number here; it changes with every catalog edit.

To add services: use the `statuspage-discovery` skill or `scripts/discover-services.py`.
To verify catalog: `python3 scripts/audit-catalog.py` (also runs weekly via `.github/workflows/catalog-audit.yml`, which opens a `catalog-audit` issue when entries break)

## Workflow

This project uses the compound engineering skill suite:

```
/ce:brainstorm  →  /document-review  →  /ce:plan  →  /ce:work
```

- Requirements docs live in `docs/brainstorms/`
- Plans live in `docs/plans/`
- Keep commits short and factual

## Issue Tracking

All work is tracked in GitHub Issues: https://github.com/moollaza/nazar/issues

- Search open and closed issues before filing — avoid duplicates; comment on the existing issue instead
- Use the templates in `.github/ISSUE_TEMPLATE/` (bug, feature, service request)
- Reference issues in PRs (`Closes #N`)

## Deployment

- **Website**: Cloudflare Pages Git integration deploys on push to `main` (no in-repo deploy workflow; see the `Cloudflare Pages` PR check) -> https://usenazar.com/
- **App**: release-please opens a Release PR; merging it creates the tag + GitHub release. The maintainer then runs `scripts/release.sh` locally (build, sign, notarize, staple, DMG) and uploads with `gh release upload`. Signing credentials stay in the local Keychain, never CI. Details: README "Releasing".

## Status Page Support

Most catalog services use Atlassian Statuspage or incident.io (compatible JSON schema). RSS/Atom feeds supported for non-Statuspage services. Better Stack status pages are supported via their public JSON:API at `{base_url}/index.json`. Instatus pages are supported via `{base_url}/summary.json` — note Instatus nests `status` inside `page`, so an Instatus payload looks like a malformed Statuspage one if you only check for top-level keys. Custom proprietary status pages are out of scope.
