# Outage alerts

When a monitored service changes status, Nazar updates the service row, tints the menu bar icon, changes the icon tooltip to `Nazar — N service(s) degraded`, and posts a macOS notification (unless the service is muted or notifications are off). Clicking the notification opens the panel on that service.

## Sub-features

- `alert-row` the row label changes to `<Name>, Degraded` / `<Name>, Major Outage`.
- `alert-icon` the menu bar icon tooltip changes from `Nazar — All operational` to `Nazar — 1 service degraded`.
- `alert-notify` a notification is posted for the change.
- `alert-mute` a muted service changes status without a notification.
- `alert-recover` `Reset to Operational` returns the row, icon, and tooltip to normal and notifies the recovery.

## How to get to it (user POV)

- Happens on its own when a real status page reports an incident.
- Debug builds only: right-click a row > `Simulate Degraded`, `Simulate Major Outage`, `Reset to Operational`.

## Driving it with nazar-app.sh

Preconditions:

- GitHub monitored (see [app-catalog.md](app-catalog.md)), panel open, row label `GitHub, Operational`.
- For `alert-notify`: the verify bundle has notification permission (a person clicks Allow on the first-run prompt, or in System Settings > Notifications > Nazar).

- **Degrade.** Run `ax rightclick "GitHub, Operational"`, `ax press "Simulate Major Outage"`. `ax wait "GitHub, Major Outage"` passes. `log "Simulated status"` shows a line. `shot alert-outage`.
- **Icon tooltip.** In `ax dump`, the extras menu bar item's help reads `Nazar — 1 service degraded`.
- **Notification.** With permission, the full-screen shot shows the banner. Without it, the log shows `Not posting notification … authorization denied`: report `alert-notify` as not verified, not as passed.
- **Recover.** Right-click the row again, `ax press "Reset to Operational"`. Label and tooltip return to `Operational` and `Nazar — All operational`.
- **Mute.** Right-click > `Mute Service`. The label gains `, muted`. Simulate again: no notification and no new delivery line in the log.

## Gotchas

- Simulation only edits the in-memory snapshot. The next real poll (default interval) overwrites it, so check right after simulating.
- Simulated changes do not go through backoff or the real parser. They prove the alert path, not that a real incident is detected. Parser coverage lives in `StatusMonitorTests`.
- Release builds do not have the simulate items.
