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

- Empty dashboard > `Browse Catalog`.
- Dashboard panel > `Settings and more` > `Browse Catalog…`.
- Dashboard panel > `Settings and more` > `Settings…` > sidebar `Catalog`.
- Menu bar icon right-click > `Preferences…` > sidebar `Catalog`.
- Settings > `Services` > `Browse Catalog`.

## Driving it with nazar-app.sh

Preconditions:

- Baseline: `launch --fresh`, `doctor` passes. Network reaches `www.githubstatus.com`.

- **Open from the panel.** In one command (outside clicks close the panel): `ax statusitem && ax wait "Settings and more" --timeout 3 && ax press "Settings and more" && ax press "Settings…" && ax wait "Nazar Settings"`. Then `ax click "Catalog"`, `ax wait "Service Catalog"`. `shot settings`. (From onboarding, `ax press "Browse Catalog"` lands on Catalog directly.)
- **Search.** Run `ax focus "catalog-search"`, then `ax type "GitHub"`. `ax find "catalog-toggle-github"` passes. Do not use `ax find "GitHub"`: it matches the search field, whose value is now `GitHub`. `shot cat-search`.
- **Add.** Run `ax press "catalog-toggle-github"`. It prints `AXCheckBox … "1"`; `ax find "1 monitoring"` passes; `log "Added from catalog"` shows a line (the name is `<private>`). `shot cat-added`.
- **See it in the dashboard.** Close Settings (`ax key cmd-w`), run `ax statusitem`, `ax wait "service-row-github" --timeout 20`. `shot cat-dashboard`.
- **Persist.** Run `quit`, then `launch` (no `--fresh`), `ax statusitem`, `ax wait "service-row-github" --timeout 20`. Passing proves the provider list was saved. `shot cat-persist`.
- **Remove.** Back in Settings > Catalog, search `GitHub` again and `ax press "catalog-toggle-github"` (value goes to `0`). `log "Removed from catalog"` shows a line and the dashboard shows `No services monitored`.
- **Other entry points.** Repeat **Open** through `ax statusitem --right` > `ax press "Preferences…"` and through `ax press "Browse Catalog"` on the Services tab.

## Gotchas

- `Search services...` filters as you type; wait for the checkbox before pressing.
- Each checkbox has identifier `catalog-toggle-<catalog id>` and label `<Name>, <status page host>`. The sidebar items are static text in rows: `click`, not `press`.
- Search, add, persistence, and remove were driven on 2026-11-14 against the pre-#90 UI. The identifiers and menu labels here come from the current source and the XCUITest `testCatalogAddPersistsAcrossRelaunchAndRemoveEmptiesPanel`, not from a drive.
- `Scan Apps` reads the real /Applications. Its result depends on the Mac; prove only that suggestions or `No suggestions found…` appear.
- Settings is a standalone NSWindow. Closing it keeps its tab; reopening may land on the last tab, not `Services`.
- A provider is keyed by base URL. Adding a URL that already exists is refused (`Refused to add duplicate provider` in the log).
