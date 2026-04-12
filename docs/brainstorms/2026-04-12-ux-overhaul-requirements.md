---
date: 2026-04-12
topic: ux-overhaul
---

# StatusMonitor UX Overhaul

## Problem Frame

StatusMonitor was built feature-by-feature, resulting in an inconsistent interaction model. Settings appear as sheets inside the popover. Custom service adding opens floating windows. The catalog picker is sometimes inline and sometimes a sheet. Hover states don't work reliably. The app gets stuck after dismissing windows. These aren't individual bugs — they stem from not having a clear separation between the **dashboard** (glanceable status) and **management** (configuration) surfaces.

Research into how polished macOS menu bar apps (iStat Menus, Raycast, Dato, Bartender) handle this reveals a consistent pattern: the popover is **read-only status + quick drill-down only**. All configuration, management, and setup lives in a separate Settings window.

## Design Principles

1. **Popover = dashboard.** Status at a glance. Tap to drill into detail. Nothing else.
2. **Settings window = management.** Catalog browsing, service management, preferences, feedback, help. A proper macOS window with sidebar navigation.
3. **No sheets, no floating windows.** Everything is either in the popover (dashboard) or the Settings window (management). Never both, never neither.
4. **Every interaction has visible feedback.** Hover highlights, press states, loading indicators.
5. **Consistent navigation.** All services drill down the same way. No threshold-based behavior switching.

## Requirements

### Popover (Dashboard)

- R1. **Popover is the dashboard and nothing else.** It shows the service list, status footer, and search/sort controls. No settings, no catalog, no add-service UI.
- R2. **Remove the popover arrow.** Use `popover.hasFullSizeContent = true` or the zero-frame positioning trick to suppress the arrow. The popover should feel like a floating panel.
- R3. **All services drill down the same way.** Tapping any service row replaces the dashboard content with the detail view. No inline expand. The threshold-based dual behavior (expand for <10, push for 10+) is confusing — make it uniform.
- R4. **Hover highlight on every interactive element.** Service rows get a subtle rounded-rect background on hover. Buttons get a slightly darker/highlighted state. Use `Color(nsColor: .unemphasizedSelectedContentBackgroundColor)` for system-native hover.
- R5. **Press/tap feedback.** When a row is tapped, briefly show a darker highlight (100ms) before the action fires. Refresh button should spin briefly on click.
- R6. **Status description visible on the detail view.** When drilling into a service, show the overall status description text and any active incident descriptions (not truncated). Users need to know *what* is happening, not just the label.
- R7. **Component names must be distinguishable.** If a service has duplicate component names (like Asana's "App", "App", "App"), append the component group name or a qualifier. If the Statuspage API provides `group_id` or group components, use those as section headers.
- R8. **Zoom and other "Unknown" statuses must be investigated.** If a catalog service consistently returns Unknown, it should be flagged or removed from defaults. Investigate Zoom's status page URL.
- R9. **Dev mode: fake status trigger.** In debug builds, add a right-click context menu item on service rows: "Simulate Outage" / "Simulate Degraded" / "Reset to Operational". This mutates the snapshot in memory (not the real poll) for visual testing.
- R10. **Logging.** Add `Logger` (OSLog) throughout the app with categories: `network`, `polling`, `notifications`, `ui`. Replace all `print()` statements. Log HTTP response codes, parse results, notification deliveries, and UI navigation events.

### Settings Window

- R11. **Settings is a proper macOS window, not a popover sheet.** Opened from the gear button in the popover header AND from the right-click menu "Preferences..." AND from Cmd+,. Uses SwiftUI `Settings` scene or a standalone `NSWindow` with `Form` + `.formStyle(.grouped)`.
- R12. **Settings has sidebar navigation** with sections: Services (default), Catalog, Preferences, Feedback, Help/About.
- R13. **Services section** shows a table/list of monitored services. Columns: icon, name, status, poll interval, mute toggle, remove button. Sorted alphabetically. Matches the quality of a native macOS table view.
- R14. **Catalog section** replaces the current catalog picker sheet. Full browsable catalog with search, category filtering, add/remove toggles. Users can both add AND remove services from here (uncheck = remove, with confirmation for monitored services).
- R15. **Preferences section** contains: Launch at Login toggle, notification preferences (future), menu bar icon style (future).
- R16. **Feedback section** contains the in-app feedback form (type picker, title, description, system info, submit).
- R17. **Help section** contains: brief "how it works" text, link to website, link to GitHub, app version.
- R18. **Add Custom Service** is a form inside the Settings Services section (not a floating window). An "Add Custom" button at the top of the Services list reveals inline fields or a sheet within the Settings window.

### Onboarding

- R19. **First launch: auto-open the popover with the dashboard.** The dashboard shows an empty state with a "Get Started" CTA that opens the Settings window to the Catalog tab. No inline catalog picker in the popover.
- R20. **Settings Catalog tab has a "Recommended" section** at the top showing ~10 popular services pre-checked as suggestions. User can modify and click "Add Selected."

### General

- R21. **No dock icon by default.** Menu bar only (current behavior, `LSUIElement = true`). No toggle for now — this is standard for menu bar utilities.
- R22. **Settings window does not show a dock icon.** Use `NSApp.setActivationPolicy(.accessory)` and ensure the Settings window appears without a dock icon. If needed, temporarily switch to `.regular` while the Settings window is open.
- R23. **Popover dismisses cleanly.** Fix the bug where the app gets stuck after dismissing a Settings sheet. The root cause is likely the sheet/popover interaction — moving Settings to a separate window eliminates this entirely.
- R24. **Settings service list sort matches dashboard default** or is always alphabetical (user's choice). Settings should show alphabetical since it's a management view.

## Success Criteria

- Every navigation action in the popover is "tap row → detail view → back." No exceptions.
- Settings is a standalone window that can be open simultaneously with the popover.
- Zero floating windows or sheets spawned from the popover.
- Every interactive element has visible hover and press states.
- A first-time user can understand the app within 30 seconds.
- The app never gets "stuck" — no orphaned windows, no unresponsive states.

## Scope Boundaries

- No custom NSPanel (keep NSPopover for now). Consider for future.
- No NavigationStack (known issues in popovers). Keep manual content replacement.
- No per-component filtering/muting (v2).
- No themes or appearance customization beyond menu bar icon.
- No dock icon toggle.

## Key Decisions

- **Uniform drill-down for all services:** Eliminates the confusing threshold-based split UX. Every row tap = detail view. Simpler code too.
- **Settings as separate window:** Industry standard for menu bar apps. Fixes the sheet/floating window mess. Allows sidebar navigation for organized management.
- **No popover arrow:** Modern menu bar apps don't use it. Feels more polished.
- **Logging with Logger/OSLog:** Standard Apple framework. Categories for filtering in Console.app. Essential for debugging user-reported issues.
- **Dev mode status simulation:** Solves the "how do I test status changes" problem without requiring real outages.

## Dependencies / Assumptions

- The existing `Settings` SwiftUI scene in StatusMonitorApp already creates a basic window. It needs to be expanded with sidebar navigation and new sections.
- Moving catalog/feedback into the Settings window means those views need to work both standalone (in the window) and potentially receive focus from the popover (via the "Get Started" CTA).
- The `hasFullSizeContent` property on NSPopover requires macOS 14+ (our minimum target is 14.6, so this is fine).

## Outstanding Questions

### Resolve Before Planning
- None — all product decisions are resolved.

### Deferred to Planning
- [Affects R2][Technical] Confirm `NSPopover.hasFullSizeContent = true` actually hides the arrow on macOS 14.6, or if the zero-frame positioning trick is needed.
- [Affects R7][Needs research] Inspect the Asana Statuspage API response to understand why components have duplicate names. Check if `group_id` or group components provide disambiguation.
- [Affects R8][Needs research] Verify Zoom's status page URL and why it returns Unknown. Try `https://status.zoom.us/api/v2/summary.json`.
- [Affects R11][Technical] Determine if the existing SwiftUI `Settings` scene can support sidebar navigation via `TabView` with `.sidebarAdaptable` style, or if a custom `NSWindow` is needed.
- [Affects R9][Technical] Best approach for debug-only context menu items (use `#if DEBUG` preprocessor flag).

## Next Steps

→ `/ce:plan` for structured implementation planning
→ Create mockups for the new Settings window layout and popover-only dashboard
