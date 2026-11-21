---
name: verify
description: Drive Nazar like a user to prove a change works. Builds and runs an isolated copy of the macOS menu bar app (clicks the menu bar icon, the dashboard panel, Settings, the catalog) and serves the static website in a real browser, capturing screenshots, accessibility trees, and app logs as evidence. Use after any change to Views/, Services/, Models/, StatusMonitorApp.swift, Resources/catalog.json, or website/, and before calling such a change done.
---

# Verify Nazar

Two surfaces, two harnesses:

| Surface | Harness | Runs on |
|---|---|---|
| Mac menu bar app (`Nazar.app`) | `scripts/nazar-app.sh` + the `ax` driver (Accessibility API + real mouse/keyboard events) | macOS 14+ with Xcode only |
| Website (`website/`, usenazar.com) | `scripts/web.sh` + `scripts/web-drive.cjs` (Playwright, Chromium) | macOS or Linux; needs network for the Tailwind CDN |

All paths below are relative to the repo root. `S=.claude/skills/verify/scripts`.

Unit tests (`xcodebuild ... test`) and `npm run test:visual` are not this skill. They prove code paths. This skill proves what a user sees. Run both when a change touches behavior. CI minutes are often exhausted on this repo, so do not count on CI to catch what you skip here.

Read [features/README.md](features/README.md), then the feature file for what you changed. Each one lists the user entry points and the observable end state.

## Mac app

### Isolation (why this is safe on the maintainer's own Mac)

The verify build uses bundle ID `com.moollapps.StatusMonitor.verify`. Its sandbox container, saved services, and log subsystem are all separate from the user's real Nazar (`com.moollapps.StatusMonitor`). Every command targets the PID the script started. Never `pkill Nazar`, never `defaults delete com.moollapps.StatusMonitor`, and never pass `-UITestMode` to the user's installed copy: it wipes that app's saved services.

One verify instance at a time. `launch` refuses if one is running.

### Launch

```bash
$S/nazar-app.sh build            # ~1-3 min cold; Debug, ad-hoc signed, hardened runtime off
$S/nazar-app.sh launch --fresh   # empty state: first-run onboarding, no services
$S/nazar-app.sh launch           # keep the services saved by the previous verify run
```

Ready means the app logged `App launch complete`. `launch` waits for that line (30 s max) and prints `ready: pid N, run ID`. A second menu bar icon appears next to the user's own Nazar icon. It looks the same.

`launch -- <args>` passes launch arguments. `-UITestOpenSettingsAt <Services|Catalog|Preferences|Feedback|Help>` opens Settings on a tab. It is a shortcut for setup only. A proof of how a user reaches Settings must click the gear or the context menu.

Debug build, on purpose: it has the `Simulate Degraded` / `Simulate Major Outage` row actions, the only way to produce an outage on demand. Side effect: Sparkle never starts in Debug, so `Check for Updates…` is disabled. Update behavior needs a Release build; see [features/app-updates.md](features/app-updates.md).

### Doctor

```bash
$S/nazar-app.sh doctor
```

Read-only. Checks that the running PID is our build, the bundle ID is the verify one, the build is newer than every source file (else rebuild), the log stream is alive, and the terminal has Accessibility and Screen Recording permission. It also names any other running Nazar so you leave it alone. Run it first whenever a step fails in a way you do not expect.

First run on a Mac: the app that runs your shell needs **Accessibility** (called **Device Control and Data Access** on newer macOS) and **Screen & System Audio Recording** in System Settings > Privacy & Security. Without them `ax` cannot see or click anything and `shot` saves only the `.ax.txt`. A person must switch them on; an agent cannot. `doctor` asks macOS to add the right entry to both lists and prints its name. Stop and ask the person to switch it on.

Which app that is: the nearest `.app` above the shell. In Terminal, iTerm, or Ghostty it is that app. In the Claude desktop app it is **not** the orange "Claude" entry: Claude disclaims its child process, so the entry is the lowercase **claude** (grey icon, bundle "Claude Code", under `~/Library/Application Support/Claude/claude-code/<version>/…/claude.app`). Tell the person to choose "Later" if macOS offers "Quit & Reopen"; restarting kills the session. Accessibility applies at once; Screen Recording can lag by a minute. A Claude Code update can change that path and need a new grant.

### Drive

`$S/nazar-app.sh ax <cmd> ...` fills in the PID. Labels match an element's title, description, value, identifier, tooltip, or placeholder. Exact by default; `--contains` for substring.

```bash
$S/nazar-app.sh ax statusitem              # left-click the menu bar icon: toggles the dashboard panel
$S/nazar-app.sh ax statusitem --right      # right-click: context menu (About, Check for Updates…, Preferences…, Send Feedback…, Quit)
$S/nazar-app.sh ax wait "Settings and more" --timeout 5   # the panel is open
$S/nazar-app.sh ax dump                    # whole AX tree: role, labels, center point, size, [disabled]
$S/nazar-app.sh ax press "Settings and more" # AXPress, or a real click if the element has none; opens the gear menu
$S/nazar-app.sh ax click "Catalog"                 # real click; refuses if another window covers the point
$S/nazar-app.sh ax focus "catalog-search"         # keyboard focus without a click
$S/nazar-app.sh ax type "GitHub"
$S/nazar-app.sh ax press "catalog-toggle-github"   # catalog checkbox
$S/nazar-app.sh ax rightclick "GitHub, Operational"
$S/nazar-app.sh ax key escape              # escape | return | tab | cmd-r | cmd-w
$S/nazar-app.sh ax windows                 # on-screen windows of the app
```

Stable handles in this app, read from the source. Identifiers (`ax` matches them like labels) are the most stable; the same ones drive the XCUITests in `StatusMonitorUITests`.

- Dashboard panel header: `Add a service` (tooltip), `Sort`, and the gear menu `Settings and more` with `Refresh Now`, `Add Custom Status Page…`, `Browse Catalog…`, `Settings…`, `Send Feedback…`, `Quit Nazar`. Filter field `dashboard-filter` (placeholder `Filter or add a service…`). Status line `All operational`, or a count such as `1 issue`. To prove the panel is open, wait for `Settings and more`, never `Nazar` (that matches the application element).
- Service row: identifier `service-row-<catalogId>` (for example `service-row-github`), label `<Name>, <Status>` (for example `GitHub, Operational`, `GitHub, Major Outage`, `GitHub, Unavailable`, `…, muted`). Right-click it for `View Details`, `Open Status Page`, `Copy Status Page URL`, `Remove <Name>…`, and in Debug `Simulate Degraded`, `Simulate Major Outage`, `Reset to Operational`.
- Empty dashboard: `No services monitored`, button `Browse Catalog`.
- Settings window title `Nazar Settings`; sidebar items `Services`, `Catalog`, `Preferences`, `Feedback`, `Help` (static text: `click`, not `press`). Opening Settings closes the panel.
- Services tab: `Browse Catalog`, `Add Custom...`; custom sheet fields `Name (e.g. My Service)`, `Status Page URL (e.g. https://status.example.com)`, buttons `Cancel`, `Add`; bad URL message `URL must be a valid https:// address with a host`.
- Catalog tab: header `Service Catalog`, `<N> monitoring`; field `catalog-search`; one `AXCheckBox` per service, identifier `catalog-toggle-<catalog id>`, value `0`/`1`; `Scan Apps`.
- Detail view: `detail-back`, `detail-view-status-page`, `Filter components...`.
- `Check for Updates…` is in Settings and in the menu bar icon's right-click menu.

Prefer `wait` over `sleep`. The panel and Settings animate in; status values arrive after a network poll.

Mouse events are real and the drive runs on the person's own desktop. Before each drive, ask the person to reply `go` once they can leave the Mac alone for about 2 minutes, and wait for it. A macOS VM was rejected for this repo (the smallest Tart image is a 20.8 GB download). Per-PR checks run as XCUITest on GitHub Actions (`StatusMonitorUITests`, in `ci.yml`), which needs no desktop. Use this skill for proof the UI tests do not cover, or to show a change working before tests exist.

- Before every real click `ax` raises the element's window and checks that the window under the point belongs to the verify app (or, for `statusitem`, the menu bar). If another app covers the point it refuses with `refusing to click … covered by <app>` instead of clicking into the user's app. Do not work around this.
- The dashboard panel closes on any mouse click in another app, including the person using their Mac. If `wait "Settings and more"` fails right after `statusitem`, the panel was closed by outside activity: chain `statusitem` and the next steps in one command, and ask the person to keep hands off.
- For a field another window covers, use `ax focus "<label>"`, then `ax type`. `type` and `key` refuse unless the verify app is frontmost.

### Evidence

```bash
$S/nazar-app.sh shot <name>      # full screen + each app window + AX tree
$S/nazar-app.sh log "Added provider"   # grep this run's app log
$S/nazar-app.sh evidence         # prints .verify/evidence/<run>/
```

Everything lands in `.verify/evidence/<run>/` (gitignored). `launch --fresh` starts a new run; a plain `launch` continues the current one, so a persistence check stays in the same folder. `quit` and `clean` append the app log there as `app.log`. Cleanup never deletes this folder.

`<name>.screen.png` is the whole screen, including whatever else the person has open. Look at and share the `<name>.winN.png` window shots; keep `.screen.png` local.

Proof standards:

- Drive the real user path: menu bar icon, panel, Settings sidebar, context menus. Launch arguments only set up state that is not the thing under test.
- Capture the action and the resulting state: a `shot` before and after, plus the `ax dump` text showing the changed label.
- Prove side effects too. A service added in the catalog must survive `quit` + `launch` (no `--fresh`) and appear in the dashboard again. A status change must show in the menu bar icon tooltip and the log (`Simulated status`), and as a notification if permission was granted.
- Log lines interpolating strings show `<private>` (os_log default). Match on the literal part of the message.
- No mocks. The app polls real status pages over the network; that is the production boundary.

### Cleanup

```bash
$S/nazar-app.sh quit     # stop the app and log stream we started; keep state for a relaunch
$S/nazar-app.sh clean    # quit + wipe the verify bundle's saved state; evidence stays
```

Run `clean` after every run, failed ones included. To reclaim disk, `rm -rf .verify/DerivedData` (keeps evidence).

## Website

```bash
$S/web.sh up        # python http.server on 127.0.0.1:4174 serving website/ as-is (4173 is the Playwright suite's)
$S/web.sh doctor    # 200 on /, catalog.json parses, our PID
node $S/web-drive.cjs <name> <path> [steps...] [--mobile]
$S/web.sh down
```

`web-drive.cjs` steps, run in order, each a pass/fail check: `see:<text>`, `gone:<text>`, `fill:<selector>=<value>`, `click:<selector>`, `attr:<selector>@<attr>=<value>`, `count:<selector>=<n>`, `shot:<label>`. Selectors are Playwright selectors (CSS plus `:has-text("…")`). `--mobile` uses a Pixel 7 viewport. Example:

```bash
node $S/web-drive.cjs catalog-search '/#services' \
  'count:#catalog-list a=30' 'fill:#catalog-search=GitHub' \
  'attr:#catalog-list a:has-text("GitHub")@href=https://www.githubstatus.com' shot:github \
  'fill:#catalog-search=zzz-no-such-service' 'see:No services match.' shot:empty
```

Evidence: `.verify/evidence/<run>/web-<name>-NN-<label>.png` plus `.aria.yml` (ARIA snapshot) and `web-<name>.log`. `down` does not touch it.

The driver aborts analytics requests (PostHog via `z.usenazar.com`, Fathom) so verification never shows up in production metrics. It fails the run on any other failed request or page error. In a sandbox that blocks `cdn.jsdelivr.net`, Tailwind does not load, the page renders unstyled with every hidden state visible, and the run fails on purpose: that screenshot is not what users see. Run on a machine with open network.

Production checks need no server: `curl -sI https://usenazar.com/appcast.xml` must 302 to `github.com/moollaza/nazar/releases/latest/download/appcast.xml`.

## Feature map

[features/README.md](features/README.md) indexes one file per user-facing feature. When you prove a feature, drive every entry point its file lists. When the app changes, keep the map honest with `/maintain-verification-skill`.
