---
date: 2026-04-09
topic: statusmonitor-v1
---

# StatusMonitor v1

## Problem Frame

Developers rely on dozens of SaaS services daily. When those services have outages, they find out through frustrated users, failed builds, or Twitter — not proactively. StatusMonitor is a macOS menu bar app that **polls** status pages on a regular interval and surfaces problems immediately via system notifications and a visual indicator. The goal for v1 is a polished, easy-to-set-up tool with a built-in catalog of popular services so users can get value in under a minute.

## How It Works

The app polls status pages on a configurable interval (default: 60 seconds). This is the correct approach — public status pages are pull-only (Atlassian Statuspage JSON API, RSS/Atom feeds). Push-based delivery (webhooks, SSE) requires server infrastructure and is out of scope for v1. HTTP conditional GET (`ETag`/`If-None-Match`) should be used where supported so no-change polls transfer minimal data.

Users typically monitor 5–20 active services. The built-in catalog (~100 entries) exists for easy discovery and setup, not as an expectation of simultaneous monitoring.

## Requirements

**Catalog & Onboarding**
- R1. Bundle a curated catalog of ~100 popular services with known-working status page URLs, organized by category (e.g., Developer Tools, Cloud Providers, AI/ML, Communication, Payments).
- R2. On first launch (no providers configured), show the catalog picker automatically as an onboarding flow.
- R3. Catalog picker: searchable by name, browsable by category, checkbox selection, "Add N Selected" CTA. Empty search state and zero-selection CTA state (disabled) must be handled.
- R4. Catalog is also accessible from Settings for adding more services post-onboarding.
- R5. Catalog data is bundled with the app for v1 (no remote fetch). Enables offline use and avoids hosting complexity.

**Dashboard**
- R6. Each service row shows a service icon, service name, status label, and colored status indicator. Icons for bundled catalog services are cached assets included in the app. Icons for user-added services are fetched at runtime and cached locally. Fallback: initials avatar. A favicon micro-service or third-party icon API is a v2 consideration.
- R7. Dashboard sort toggles between "by status severity" (worst first, default) and "A–Z". Control: segmented picker in the popover header. Selected sort persists across sessions.
- R8. Expanding a row shows component-level status and active incidents (already implemented). A "View status page" link opens the service's status URL in the browser.
- R9. Dashboard empty state (no services added): display a prompt with a "Browse Catalog" CTA to re-open the onboarding picker.
- R10. Service fetch error state: row shows a gray indicator and an inline error label (e.g. "Unavailable"). Does not trigger a notification. Does not affect the menu bar worst-status calculation.

**Menu Bar**
- R11. Menu bar icon reflects the worst monitored status across all *healthy-fetch* services: green (all operational), yellow (degraded), orange (partial outage), red (major outage). Already implemented. Error/unavailable services are excluded from worst-status.

**Notifications**
- R12. System notification fires on any status change — both degradation and recovery. Default poll interval is 60 seconds; notifications arrive within 2 poll cycles (~2 minutes) of a real incident. Already partially implemented.
- R13. Tapping a notification opens the app popover. Deferred: scroll-to/focus the relevant service row (v2).

**Polling**
- R14. Default poll interval: 60 seconds per service. User-configurable per service in Settings (minimum: 30s). HTTP conditional GET used where the status page supports `ETag` or `Last-Modified`.

**Repo & Project Structure**
- R15. Reorganize as a monorepo: `app/` (Xcode project), `website/` (static site), `ai-docs/` (AI context docs), `CLAUDE.md`. Note: Xcode project path migration requires care (all `project.pbxproj` file references will need updating).

**Marketing Website**
- R16. A companion marketing website is required for v1. Full requirements in `docs/brainstorms/2026-04-09-statusmonitor-website-requirements.md`. Can ship in parallel with or after the app.
- R17. Free and open-source. Source on GitHub. No pricing tiers at launch.

**Distribution**
- R18. Signed and notarized `.dmg` for direct download via GitHub Releases. Download link on website.
- R19. Mac App Store is a post-v1 goal. Code should be sandbox-compliant from the start (entitlements already set), but submission and App Store review are deferred.

## Success Criteria

- A new user can go from first launch to monitoring their first 5 services in under 60 seconds.
- Status changes are reflected in the menu bar icon and delivered as notifications within 2 poll cycles (120 seconds at default interval).
- The website clearly communicates what the app does and provides a working download link.

## Scope Boundaries

- No Windows or iOS app.
- No account, sync, or cloud backend in v1.
- No webhook/Slack integration in v1 (services expose these natively; StatusMonitor is the consumer).
- No per-service notification preferences in v1 (global all-or-nothing; 20 active services makes noise manageable).
- No changelog page on the website in v1.
- No App Store submission in v1.
- No third-party favicon/icon service in v1 (research spike deferred to v1.x).

## Key Decisions

- **Polling, not push**: Public status pages are pull-only APIs. No server infrastructure needed. HTTP conditional GET minimizes bandwidth on no-change polls.
- **Active monitoring scale**: Users typically monitor 5–20 services. The catalog of ~100 is for discovery, not simultaneous monitoring.
- **Catalog bundled**: Simpler, no hosting, works offline. Downside: catalog updates require app release. Accepted for v1.
- **Icons — two-tier**: Bundled cached assets for catalog services; runtime fetch + local cache for user-added services. Third-party icon service deferred to research.
- **App Store — sandbox-compliant but deferred**: Write sandbox-safe code from the start; submission is post-v1.
- **Monetization**: FOSS, free at launch. Paid features are a future consideration.
- **Website tech**: Plain HTML + Tailwind CDN with SRI hash pinned. No build step.

## Dependencies / Assumptions

- Services in the catalog either use the Atlassian Statuspage JSON API (`/api/v2/summary.json`) or a known RSS/Atom feed. Pre-curation research needed to confirm ~100 viable entries.
- GitHub Releases will host `.dmg` artifacts. The website links there directly.
- Bundle ID `com.yourname.StatusMonitor` is a placeholder and must be replaced before distribution.

## Outstanding Questions

### Resolve Before Planning
- None — all product decisions are resolved.

### Deferred to Planning
- [Affects R6][Needs research] Icon sourcing for bundled catalog: where to obtain ~100 service icons (press kits, brand asset pages). SVG preferred, PNG acceptable.
- [Affects R1][Needs research] Catalog curation: which ~100 services? Prioritize Atlassian Statuspage providers. Need names, URLs, types, categories.
- [Affects R15][Technical] Monorepo path migration: Xcode project is currently at repo root; moving to `app/` requires updating all `fileRef` paths in `project.pbxproj`. Use Xcode's built-in folder rename to do this atomically.
- [Affects R12][Technical] HTTP conditional GET: which Atlassian Statuspage endpoints support `ETag`? Verify before implementing.

## Roadmap Notes

- **v1**: Core polling, catalog, dashboard, notifications, website, direct download
- **v1.x**: Third-party icon service research (Clearbit, Brandfetch, etc.), HTTP conditional GET optimization
- **v2**: Per-service notification preferences, notification focus/deep-link, App Store submission

## Next Steps

→ `/ce:plan` for structured implementation planning
→ Track work in Linear (MCP integration planned)
