# First run and the dashboard panel

Nazar lives in the menu bar. Clicking its icon opens a floating panel listing the monitored services and their status. On first launch the panel opens by itself and shows an empty state that points to Settings.

## Sub-features

- `dash-onboarding` the panel opens by itself on first launch with `No services monitored` and `Get Started`.
- `dash-get-started` `Get Started` opens the `Nazar Settings` window.
- `dash-toggle` a left click on the menu bar icon opens the panel; a second click or Escape closes it.
- `dash-list` each monitored service is one row labelled `<Name>, <Status>`, and the header shows `All operational` or a count of issues.
- `dash-filter` typing in `Filter services...` narrows the rows.
- `dash-detail` clicking a row opens its detail view (`View Status Page`, `Filter components...`); `Services` goes back.
- `dash-refresh` `Refresh all` (or Cmd-R while the panel is open) polls again and updates `Updated …`.

## How to get to it (user POV)

- First launch of the app (no saved services).
- Left-click the Nazar menu bar icon.
- Click a macOS notification for an outage (opens the panel on that service; see [app-outage-alert.md](app-outage-alert.md)).

## Driving it with nazar-app.sh

Preconditions:

- Baseline: `launch --fresh`, `doctor` passes.
- For `dash-list`, `dash-filter`, `dash-detail`, `dash-refresh`: GitHub added through [app-catalog.md](app-catalog.md).

- **Onboarding.** Launch fresh. Run `$S/nazar-app.sh ax wait "No services monitored" --timeout 5` right away: any click elsewhere on the Mac closes the panel. It is found; `shot onboarding` shows the panel under the verify icon.
- **Get Started.** Run `$S/nazar-app.sh ax press "Get Started"`, then `ax wait "Nazar Settings"`. The Settings window exists.
- **Toggle.** Close Settings (`ax key cmd-w`). Run `ax statusitem`; `ax wait "Refresh all"` finds the panel header (not `"Nazar"`, which matches the app itself). Run `ax key escape`; `ax windows` no longer lists the panel.
- **List.** With GitHub monitored, open the panel and run `ax wait "GitHub, Operational" --timeout 20` (any status label is a pass for this step; `GitHub, Unavailable` means the poll failed, check `log "Poll"`). `shot dash-list`.
- **Filter.** Run `ax click "Filter services..."`, `ax type "zzz"`. `ax find "GitHub" --contains` fails. Clear with `ax key escape` or delete the text; the row comes back.
- **Detail.** The row's tooltip says `Double-click to view details`; `ax` has no double-click yet, so try `ax click "GitHub, " --contains` and report this entry point as not verified if `View Status Page` does not appear. `ax wait "View Status Page"` passes. `shot dash-detail`. `ax press "Services"` returns to the list.
- **Refresh.** Run `ax press "Refresh all"`. `log "Manual refresh triggered"` shows a new line.

## Gotchas

- Known bug (seen 2026-11-14, macOS 27): clicking the menu bar icon while the panel is open does not close it. The outside-click monitor closes the panel on mouse-down, then the icon's mouse-up opens it again. Escape does not close it while Settings has focus. `dash-toggle`'s second-click close is therefore not verified. The panel also stays open over Settings after `Settings` or `Get Started`, covering part of it.

- The panel closes on any click outside it, including a click on the user's own Nazar icon. Do not touch the mouse.
- The verify icon and the user's icon look the same. `ax statusitem` always picks the verify app's by PID; a person looking at the screen cannot tell them apart.
- On a fresh launch, `requestPermission` shows a macOS notification permission prompt for the verify bundle. Leave it; it does not block the panel.
- The row is a combined accessibility element. Its label changes with status and mute state, so match with `--contains` when status does not matter.
