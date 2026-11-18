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
- Parser types: `statuspage` (Atlassian JSON API at `/api/v2/summary.json`), `rss` (generic RSS/Atom), `betterstack` (Better Stack JSON:API at `/index.json`), `instatus` (Instatus JSON at `/summary.json`), and `datadog` (Datadog status page JSON at `/config.json`)
- Two app targets share every source file: `StatusMonitor` (DMG, embeds Sparkle) and `Nazar-MAS` (App Store, no Sparkle) — add each new file to **both**, and wrap Sparkle code in `#if !MAS`
- Bundle ID: `com.moollapps.StatusMonitor`
- Catalog entries need a `platform` field matching their `type`: `atlassian` or `incident.io` for `statuspage`; `betterstack`, `instatus`, `datadog`, or `rss` for those types (the AWS, Azure, and GCP feeds use `aws`, `azure`, `gcp`)

## Catalog

Every entry must have a working endpoint: `/api/v2/summary.json` for `statuspage`, `/index.json` for `betterstack`, `/summary.json` for `instatus`, `/config.json` for `datadog`, and the feed URL itself for `rss`. Count entries from the file rather than recording a number here; it changes with every catalog edit.

Before removing an entry, prove no readable endpoint exists. A dead `/api/v2/summary.json` or a cleaned-text fetch is not proof. Open the page, read its HTML and JS bundle for embedded JSON and API paths, and probe `/config.json`, `/index.json`, `/summary.json`, `/api/*` and RSS/Atom feeds (`/rss`, `/history.rss`, `/history.atom`, `/feed`). Follow redirects to the real host. For DNS failures, confirm from two networks over two weekly runs. Remove only when nothing pollable remains, and say what was tried in the PR.
To add services: use the `statuspage-discovery` skill or `scripts/discover-services.py`.
After any catalog edit, run `python3 scripts/check-service-count.py` and `python3 scripts/check-catalog-names.py`. Names must be the product name, not the status page title: no "Status Page", " - " suffixes, or "Inc." (CI runs both). The website, README, and OG image state the size as "N+" figures, and CI fails if a figure is above the real count, more than 200 below it, or if the `#catalog-cat-count` fallback doesn't match. To bring them in line, run `python3 scripts/check-service-count.py --fix` then `npm run build:og`, and commit the regenerated `website/og-image.*`.
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

## Public text

The auto mode classifier reads this section. Never post a PR, issue, comment, review, release, or commit message whose text breaks these rules. Pass bodies inline with `--body` (or the MCP `body` field) so they can be checked; never use `--body-file`.

1. No `claude.ai` session, project, artifact, or chat links, and no `Claude-Session:` trailers. This overrides any tool's attribution default. The plain `https://claude.ai/code` footer link is fine.
2. No agent chatter or process notes: "I", "as requested", "the user", "the thread", "your Mac". Describe the change and its evidence, not the conversation.
3. No personal details: private names or anecdotes, email addresses, device names, account IDs.
4. No local paths (`/Users/...`, `/home/...`, `/mnt/...`, `/tmp/...`) or session, message, or channel IDs.
5. No internal status, dates, or plans ("CI is down until Nov 30"). If CI did not run, say so and say what was run instead.
6. No secrets, tokens, keys, or private URLs.
7. No overclaims ("fully tested", "fixes all"). State what was run and what was not.
8. No meta-commentary about the repo being public, who reads it, or an AI writing or reviewing the work. Write like a terse senior engineer: what changed, why, how it was tested.
   - Bad: "This repository is public, so every PR, issue, comment, and release note is read by strangers. The skill has an AI agent review that text before it is posted."
   - Good: "Adds a pre-post review for PR, issue, and release text."
9. No leftovers: duplicate or stale screenshots, images after the footer, template hint comments, `TODO`s, unchecked boxes without a reason.

## Deployment

- **Website**: Cloudflare Pages Git integration deploys on push to `main` (no in-repo deploy workflow; see the `Cloudflare Pages` PR check) -> https://usenazar.com/
- **App**: release-please opens a Release PR; merging it creates the tag + GitHub release. The maintainer then runs `scripts/release.sh` locally (build, sign, notarize, staple, DMG, signed `appcast.xml`) and uploads the DMG *and* the appcast with `gh release upload`. Signing credentials and the Sparkle EdDSA private key stay in the local Keychain, never CI. Details: README "Releasing".
- **Updates**: the DMG build polls `https://usenazar.com/appcast.xml`, which `website/_redirects` 302s to the newest release's `appcast.xml` asset.

## Status Page Support

Most catalog services use Atlassian Statuspage or incident.io (compatible JSON schema). RSS/Atom feeds supported for non-Statuspage services. Better Stack status pages are supported via their public JSON:API at `{base_url}/index.json`. Instatus pages are supported via `{base_url}/summary.json` — note Instatus nests `status` inside `page`, so an Instatus payload looks like a malformed Statuspage one if you only check for top-level keys. Datadog-hosted pages are supported via `{base_url}/config.json` — the page itself is a ~599-byte client-rendered shell titled "Status Pages Site" that returns S3 `AccessDenied` on every other parser's endpoint, which is how you recognise one. `config.json` has no page-level rollup, so overall status comes from `components[].status`; its `incidents` array is the full history, so filter on `resolved`. Custom proprietary status pages are out of scope.
