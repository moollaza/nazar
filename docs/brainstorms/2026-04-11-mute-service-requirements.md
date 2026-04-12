---
date: 2026-04-11
topic: mute-service
linear: ZPR-28
---

# Mute/Ignore Per Service

## Problem Frame

Users monitor services like Cloudflare that frequently report regional issues irrelevant to them. These regional incidents turn the menu bar icon orange/red and trigger notifications, causing alert fatigue. The user wants to keep seeing the service's status in the dashboard but exclude it from the aggregate worst-status indicator and from notification triggers. There is currently no way to do this short of removing the service entirely.

## Requirements

### R1. `isMuted` property on Provider

Add `var isMuted: Bool` to the `Provider` struct, defaulting to `false`. The field must be optional in Codable so existing UserDefaults data decodes without migration — a missing key decodes as `false`.

### R2. Muted services are still polled and displayed

Muting does not disable polling. The service still appears in the dashboard list with its real-time status. This distinguishes mute from disable/remove.

### R3. Muted services excluded from worst-status calculation

`recalcWorstStatus()` in `StatusManager` must filter out snapshots whose corresponding provider has `isMuted == true`. The menu bar icon reflects only unmuted services.

### R4. Muted services excluded from notifications

`applySnapshot(_:for:)` in `StatusManager` must skip the `NotificationService.shared.notify(...)` call when the provider is muted. The `previousStatuses` dict is still updated so that unmuting later does not trigger a spurious notification for the current state.

### R5. Visual indicator in dashboard

Muted service rows are dimmed (opacity 0.5) and show a `speaker.slash.fill` icon next to the service name. This makes muted status immediately visible without adding clutter to unmuted rows.

### R6. Toggle via context menu on service row

Right-clicking (or control-clicking) a `ProviderRowView` shows a context menu with "Mute Service" or "Unmute Service" (label toggles based on current state). This is the primary interaction point — fast, discoverable, standard macOS pattern.

### R7. Toggle in Settings

In `SettingsView`, each provider row shows a mute/unmute button (speaker icon) alongside the existing poll interval menu and remove button. This provides an alternative path and makes muted state visible when managing services.

### R8. Persistence

`isMuted` is persisted as part of the `Provider` Codable struct in UserDefaults. No separate storage needed. `saveProviders()` already handles this.

## Scope Boundaries

- No per-component muting (e.g., mute only "Cloudflare — Asia Pacific"). That is a v2 feature requiring a new data model.
- No scheduled mute (e.g., "mute during maintenance windows"). Out of scope.
- No bulk mute/unmute. Single-service toggle only.
- No mute expiry or auto-unmute.

## Key Decisions

- **Mute, not hide.** Users still want visibility into the service — they just don't want it to affect the aggregate indicator or fire notifications. Hiding would lose information.
- **Optional Codable field for backwards compat.** Adding `isMuted` as an optional field means existing UserDefaults data (without the key) decodes cleanly as `nil`, interpreted as `false`. No migration code needed.
- **Context menu as primary UX.** Right-click is the standard macOS pattern for per-item actions. It keeps the main row clean while being immediately discoverable.
- **Dimmed + icon, not a separate section.** Muted services stay in the same list, sorted normally. Separating them into a "Muted" section would add visual complexity and break sort expectations.
- **Still update previousStatuses when muted.** This prevents a flood of notifications when unmuting a service that had status changes while muted.

## Dependencies / Assumptions

- The `Provider` struct is already `Codable` with `saveProviders()`/`loadProviders()` in `StatusManager`. Adding an optional field requires no infrastructure changes.
- `ProviderRowView` currently has no context menu — one must be added via `.contextMenu {}`.
- `recalcWorstStatus()` currently filters by `error == nil` only. Adding an `isMuted` filter is additive.

## Outstanding Questions

### Resolve Before Planning
- None — all decisions are resolved.

### Deferred
- [v2] Per-component muting for services with many regional components (Cloudflare, AWS).
- [v2] Mute schedule tied to maintenance windows.

## Next Steps

-> `docs/plans/2026-04-11-004-feat-mute-service-plan.md` for implementation plan
