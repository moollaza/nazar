# Nazar verification map

The maintained source for verifying what a Nazar user sees. Read this index, then use the matching feature file as the recipe. Harness commands are in [../SKILL.md](../SKILL.md); `S=.claude/skills/verify/scripts`.

## Baseline preconditions

- Mac app: `$S/nazar-app.sh build`, then `$S/nazar-app.sh launch --fresh`, then `$S/nazar-app.sh doctor` passes. The verify build (bundle ID `com.moollapps.StatusMonitor.verify`) starts with no services and onboarding not done.
- Website: `$S/web.sh up` and `$S/web.sh doctor` pass, on a machine that can reach `cdn.jsdelivr.net`.
- Never drive an instance this run did not start. The user's own Nazar may be running; `doctor` names it.

## Driving conventions

- Start each recipe from the baseline unless its preconditions say otherwise. Recipes that need a monitored service get one through the catalog journey in [app-catalog.md](app-catalog.md), not by writing defaults.
- Prefer labels from the source (button titles, tooltips, placeholders, the `<Name>, <Status>` row label) over coordinates.
- `wait` for an element instead of sleeping. Status values arrive after a real network poll.
- Do not touch the mouse or keyboard during a Mac drive.

## Proof and skip reporting

- Capture the action and the resulting state: `shot` before and after, and quote the changed AX label from the `.ax.txt`.
- Prove persistence by `quit` + `launch` (no `--fresh`) and seeing the state again.
- Name the feature ID and entry point with each artifact.
- An entry point you could not drive is reported as not verified, with the command and the unmet precondition. Do not count it as verified through another path.

## Feature entry contract

Each feature file has an H1, one paragraph on the user-visible behavior, then exactly these H2s in order: `Sub-features`, `How to get to it (user POV)`, `Driving it with <harness>` (starting with `Preconditions:`), `Gotchas`.

## Features

- [First run and the dashboard panel](app-dashboard.md): onboarding auto-open, menu bar icon toggle, empty state, filter, detail view.
- [Add services from the catalog](app-catalog.md): Settings > Catalog search, checkbox add/remove, persistence, dashboard row.
- [Add a custom service](app-custom-service.md): Settings > Services > Add Custom..., https validation, add.
- [Outage alerts](app-outage-alert.md): a status change reaches the row, the menu bar icon, its tooltip, and a notification.
- [App updates (Sparkle)](app-updates.md): the update menu item, the local update rehearsal, and the appcast redirect.
- [Website catalog](website-catalog.md): homepage, catalog paging, search, empty state, service links.
