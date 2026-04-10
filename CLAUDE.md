# StatusMonitor

macOS menu bar app that monitors SaaS service status pages and alerts on outages. FOSS, free at launch.

## Tech Stack

- **App**: Swift 5.9+, SwiftUI, macOS 13+, `@Observable` (not `ObservableObject`)
- **Architecture**: Menu bar accessory (`LSUIElement=true`), no Dock icon, popover UI
- **Persistence**: `UserDefaults` for provider list and preferences
- **Network**: `URLSession` for polling; sandboxed (`com.apple.security.network.client`)
- **Website**: Static HTML + Tailwind CSS CDN (no build step), GitHub Pages

## Repo Layout

```
app/           Xcode project (StatusMonitor.xcodeproj) — planned move from root
website/       Marketing site — planned addition
ai-docs/       AI context docs — planned addition
docs/
  brainstorms/ Requirements docs
```

> Note: Xcode project currently lives at the repo root (pre-monorepo). R12 tracks the reorganization.

## Build & Run

Open `StatusMonitor.xcodeproj` in Xcode and run the `StatusMonitor` scheme. No CLI build needed for development.

```bash
# Build from CLI (CI)
xcodebuild -project StatusMonitor.xcodeproj -scheme StatusMonitor -configuration Release build
```

## Key Conventions

- Use `@Observable` / `@Environment` (Swift 5.9 macro), not `ObservableObject`/`@StateObject`
- `StatusManager` is `@MainActor` — all snapshot mutations happen on main thread
- New status page providers: add to `Provider.defaults` in `Models/Models.swift`
- Two parser types: `statuspage` (Atlassian JSON API at `/api/v2/summary.json`) and `rss`
- Bundle ID placeholder `com.yourname.StatusMonitor` — must be replaced before distribution

## Workflow

This project uses the compound engineering skill suite:

```
/ce:brainstorm  →  /document-review  →  /ce:plan  →  /ce:work
```

- Requirements docs live in `docs/brainstorms/`
- Plans will live in `docs/plans/`
- Run `/cleanup` before committing; lint and test before every commit
- Keep commits short and factual

## Status Page Support

Most catalog services use the Atlassian Statuspage JSON API. A few use RSS/Atom feeds. Services with custom proprietary status pages are out of scope for v1.

## Known Issues (pre-v1)

- `com.yourname.StatusMonitor` bundle ID is a placeholder
- OpenAI status page returns a parse error (JSON schema mismatch)
- Slack status page returns HTTP 404 (non-standard URL)
- Poll interval per-provider is configurable but default (60s) is not exposed in UI
