# First run and the dashboard panel

Nazar lives in the menu bar. Clicking its icon opens a floating panel listing the monitored services and their status. On first launch the panel opens by itself with an empty state that offers the catalog.

## Sub-features

- `dash-onboarding` the panel opens by itself on first launch with `No services monitored` and a `Browse Catalog` button.
- `dash-browse` `Browse Catalog` opens `Nazar Settings` on the Catalog tab and closes the panel.
- `dash-toggle` a left click on the menu bar icon opens the panel; Escape closes it.
- `dash-list` each monitored service is one row (`service-row-<catalogId>`) labelled `<Name>, <Status>`, and the header shows `All operational` or a count such as `1 issue`.
- `dash-filter` typing in `Filter or add a service…` (`dashboard-filter`) narrows the rows.
- `dash-detail` clicking a row opens its detail view (`detail-view-status-page`, `Filter components...`); `detail-back` returns.
- `dash-refresh` `Settings and more` > `Refresh Now` (or Cmd-R while the panel is open) polls again.

## How to get to it (user POV)

- First launch of the app (no saved services).
- Left-click the Nazar menu bar icon.
- Click a macOS notification for an outage (opens the panel on that service; see [app-outage-alert.md](app-outage-alert.md)).

## Driving it with nazar-app.sh

Preconditions:

- Baseline: `launch --fresh`, `doctor` passes.
- For `dash-list`, `dash-filter`, `dash-detail`, `dash-refresh`: GitHub added through [app-catalog.md](app-catalog.md).

- **Onboarding.** Launch fresh. Run `$S/nazar-app.sh ax wait "No services monitored" --timeout 5` at once: any click elsewhere closes the panel. `shot onboarding`.
- **Browse Catalog.** Run `ax press "Browse Catalog"`, then `ax wait "Service Catalog"`. Settings is open on Catalog and the panel is gone.
- **Toggle.** Close Settings (`ax key cmd-w`). Run `ax statusitem && ax wait "Settings and more" --timeout 3` (not `"Nazar"`, which matches the app itself). Run `ax key escape`; `ax windows` no longer lists the panel.
- **List.** With GitHub monitored, open the panel and run `ax wait "service-row-github" --timeout 20`, then `ax find "GitHub, " --contains` and quote the status. `GitHub, Unavailable` means the poll failed; check `log "Poll"`. `shot dash-list`.
- **Filter.** Run `ax focus "dashboard-filter"`, `ax type "zzz"`. `ax find "service-row-github"` fails. Clear the text; the row comes back.
- **Detail.** Run `ax click "service-row-github"`. `ax wait "detail-view-status-page"` passes. `shot dash-detail`. `ax press "detail-back"` returns to the list.
- **Refresh.** Run `ax press "Settings and more"`, then `ax press "Refresh Now"`. `log "Manual refresh triggered"` shows a new line.

## Gotchas

- These steps were rewritten from the source after the panel redesign (#90, #92) and have not been driven yet. The same journeys run as XCUITest in `StatusMonitorUITests` (`testFirstRunOpensOnboardingPanelAndBrowseCatalogOpensSettings`, `testMenuBarIconTogglesPanel`, `testPanelFilterDetailAndRefresh`); when a label here fails, that file has the one that works.
- The panel closes on any click outside it, including a click on the user's own Nazar icon. Do not touch the mouse.
- The verify icon and the user's icon look the same. `ax statusitem` always picks the verify app's by PID.
- On a fresh launch, `requestPermission` shows a macOS notification permission prompt for the verify bundle. Leave it; it does not block the panel.
- The row label changes with status and mute state. Match the identifier when status does not matter.
