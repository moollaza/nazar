---
date: 2026-04-11
topic: statusmonitor-ux-polish
---

# StatusMonitor v1.x UX Polish

## Problem Frame

StatusMonitor's core features work (polling, dashboard, catalog, notifications) but the app lacks standard macOS menu bar app conventions that users expect. Most critically: there is no way to quit the app, no right-click menu, no about window, and no launch-at-login. The onboarding has no welcome text, there's no feedback path, and no analytics to understand usage. These gaps make the app feel unfinished despite working functionality.

## Requirements

### Critical (ship-blocking)

- R1. **Right-click context menu on menu bar icon.** Left-click opens the popover (current behavior). Right-click shows a menu with: About StatusMonitor, Preferences..., Send Feedback, Check for Updates (placeholder), Quit. This is the universal macOS menu bar app pattern.
- R2. **Quit option.** The right-click menu's "Quit" item terminates the app via `NSApp.terminate(nil)`. Currently there is NO way to quit without Force Quit.
- R3. **About window.** Standard macOS about panel showing: app icon, app name, version number, "Made by MoollApps", link to website, link to GitHub repo.

### High Priority (first-run experience)

- R4. **Welcome header on first-launch catalog picker.** When the catalog picker is shown inline during onboarding, display a brief welcome above it: app name, one-line tagline ("Monitor your services. Know before your users do."), and a short instruction ("Pick the services you use — we'll watch them for you."). Keep it to 3 lines max.
- R5. **Launch at login toggle.** In Settings (or right-click menu > Preferences), a toggle to launch the app at login. Use `SMAppService.mainApp` (macOS 13+, no helper app needed). Default: off.

### Medium Priority (usability)

- R6. **Feedback via pre-filled GitHub Issue URL.** "Send Feedback" in the right-click menu opens a pre-filled GitHub Issue URL in the browser with app version and OS version in the body. No backend needed. Can upgrade to CF Worker + GitHub API later for seamless in-app form.
- R7. **Dashboard search/filter.** A small search field in the dashboard header (or below it) to filter services by name. Useful when monitoring 10+ services. Simple `localizedCaseInsensitiveContains` filter.
- R8. **Mute/ignore per service.** A toggle (context menu or Settings) to mute a service: still monitored and visible, but excluded from worst-status calculation and does not trigger notifications. Visual indicator (muted icon or dimmed row). Persisted in Provider model.
- R9. **Menu bar icon tooltip.** Hover over the menu bar icon shows a tooltip with a quick summary: "All operational" or "2 services degraded" (count of non-operational services).
- R10. **Confirmation before removing services.** Show a confirmation alert before removing a service in Settings. Prevents accidental deletion.

### Low Priority (polish)

- R11. **Keyboard shortcuts.** Cmd+R to refresh all. Cmd+, to open Preferences/Settings. Cmd+Q to quit. These should work when the popover is focused.
- R12. **TelemetryDeck integration.** Privacy-first analytics SDK. Track: app launches (daily active), services monitored count, catalog vs custom provider ratio. No user IDs, no PII. Free tier: 100k signals/month.
- R13. **Fathom Analytics on marketing website.** Add Fathom script to website/index.html when the website is built (Phase 8). Privacy-friendly, no cookies, GDPR-compliant.
- R14. **Menu bar icon color customization.** Option to use monochrome icon (for users who find colored icons distracting) or custom accent color. Setting in Preferences.
- R15. **Auto-update checking.** Integrate Sparkle framework for checking and installing updates from GitHub Releases. "Check for Updates" in right-click menu triggers manual check. Background checks on configurable interval.

### Deferred (v2)

- Per-service component/region filtering (Cloudflare 200+ PoPs problem) — requires new UI and per-provider persistence model
- On-device LLM summaries via Apple Foundation Models — requires macOS 26+, heavy dependency
- Pull-to-refresh — not natively supported in macOS ScrollView, workarounds are fragile

## Success Criteria

- A new user can quit the app without Force Quit.
- Right-click on the menu bar icon shows a functional context menu.
- First-launch experience explains what the app does before showing the catalog.
- App can launch at login via a simple toggle.
- User can send feedback without leaving the app flow (opens browser with pre-filled issue).

## Scope Boundaries

- No in-app feedback form for v1.x (pre-filled GitHub URL is sufficient).
- No custom icon themes or icon packs.
- No window/panel mode (app stays popover-only for v1.x).
- Sparkle integration is research + implement — may be deferred if complex.
- Component/region filtering is v2 (requires data model changes).

## Key Decisions

- **Right-click = menu, left-click = popover:** Standard macOS pattern. Don't combine them.
- **Feedback via pre-filled URL, not CF Worker:** Zero infra for v1.x. Upgrade path exists.
- **TelemetryDeck over homebrew ping:** Established SDK, differential privacy, free tier sufficient. Adds one dependency but it's the "boring" choice for indie Mac apps.
- **Launch at login via SMAppService:** Modern API (macOS 13+), no login item helper app, one-line integration.
- **Sparkle for auto-updates:** Industry standard for non-App-Store Mac apps. Proven, maintained, handles the full update lifecycle.

## Dependencies / Assumptions

- GitHub repo is public (for feedback URL to work).
- TelemetryDeck requires a free account and app ID.
- Sparkle requires an appcast XML file hosted somewhere (GitHub Pages or R2).
- SMAppService requires the app to be code-signed.

## Outstanding Questions

### Resolve Before Planning
- None — all product decisions are resolved.

### Deferred to Planning
- [Affects R5][Technical] Does SMAppService.mainApp work correctly with Developer ID signing (non-App-Store)?
- [Affects R12][Needs research] TelemetryDeck Swift package — confirm macOS support and minimum deployment target.
- [Affects R15][Needs research] Sparkle framework integration — what's the minimum setup for GitHub Releases as the appcast source?
- [Affects R8][Technical] Mute flag on Provider — does adding a new Codable field require migration for existing UserDefaults data? (Likely no — optional field decodes as nil.)

## Next Steps

→ `/ce:plan` for structured implementation planning
→ Mockups via `/design-mockup` for the right-click menu, welcome header, and mute UI
