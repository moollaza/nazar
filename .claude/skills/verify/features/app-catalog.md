# Add services from the catalog

The catalog lists every verified status page Nazar ships (`Resources/catalog.json`). The user searches it in Settings and ticks a checkbox to start monitoring a service. The choice persists across relaunches and shows in the dashboard panel.

## Sub-features

- `cat-open` Settings > `Catalog` shows `Service Catalog` with a count of available services.
- `cat-search` `Search services...` narrows the list.
- `cat-add` ticking a service's checkbox adds it; `Services` tab count and the dashboard both show it.
- `cat-persist` the added service is still there after quit and relaunch.
- `cat-remove` unticking removes it from the dashboard.
- `cat-scan` `Scan Apps` suggests services that match apps in /Applications.

## How to get to it (user POV)

- Dashboard panel > gear (`Settings`) > sidebar `Catalog`.
- Empty dashboard > `Get Started` > sidebar `Catalog`.
- Menu bar icon right-click > `Preferences…` > sidebar `Catalog`.
- Settings > `Services` > `Browse Catalog`.

## Driving it with nazar-app.sh

Preconditions:

- Baseline: `launch --fresh`, `doctor` passes. Network reaches `www.githubstatus.com`.

- **Open from the panel.** Run `ax statusitem` (if the onboarding panel is not already open), `ax press "Settings"`, `ax wait "Nazar Settings"`, `ax click "Catalog"`, `ax wait "Service Catalog"`.
- **Search.** Run `ax click "Search services..."`, `ax type "GitHub"`. `ax find "GitHub"` passes. `shot cat-search`.
- **Add.** Run `ax press "GitHub"` on the checkbox (check the `.ax.txt`: the `AXCheckBox` must carry the label; if the match lands on a static text instead, use `ax click` on the checkbox's center from `ax dump`). `log "Added from catalog"` shows a line. `shot cat-added`.
- **See it in the dashboard.** Run `ax statusitem`, `ax wait "GitHub" --contains --timeout 20`. `shot cat-dashboard`.
- **Persist.** Run `quit`, then `launch` (no `--fresh`), `ax statusitem`, `ax wait "GitHub" --contains --timeout 20`. Passing proves the provider list was saved.
- **Remove.** Back in Settings > Catalog, search `GitHub` again and press the checkbox. `log "Removed from catalog"` shows a line and the dashboard shows `No services monitored`.
- **Other entry points.** Repeat **Open** through `ax statusitem --right` > `ax press "Preferences…"` and through `ax press "Browse Catalog"` on the Services tab.

## Gotchas

- `Search services...` filters as you type; wait for the row before pressing.
- `Scan Apps` reads the real /Applications. Its result depends on the Mac; prove only that suggestions or `No suggestions found…` appear.
- Settings is a standalone NSWindow. Closing it keeps its tab; reopening may land on the last tab, not `Services`.
- A provider is keyed by base URL. Adding a URL that already exists is refused (`Refused to add duplicate provider` in the log).
