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

First run on a Mac: macOS asks to grant the terminal app (Terminal, iTerm, Ghostty, or the Claude app) **Accessibility** and **Screen Recording** in System Settings > Privacy & Security. Without them `ax` cannot see or click anything and screenshots show only the desktop. A person must grant these; an agent cannot. Stop and ask.

### Drive

`$S/nazar-app.sh ax <cmd> ...` fills in the PID. Labels match an element's title, description, value, identifier, tooltip, or placeholder. Exact by default; `--contains` for substring.

```bash
$S/nazar-app.sh ax statusitem              # left-click the menu bar icon: toggles the dashboard panel
$S/nazar-app.sh ax statusitem --right      # right-click: context menu (About, Check for Updates…, Preferences…, Send Feedback…, Quit)
$S/nazar-app.sh ax wait "Nazar" --timeout 5
$S/nazar-app.sh ax dump                    # whole AX tree: role, labels, center point, size, [disabled]
$S/nazar-app.sh ax press "Settings"        # AXPress, or a real click if the element has none
$S/nazar-app.sh ax click "Search services..."   # real click (focus a field)
$S/nazar-app.sh ax type "GitHub"
$S/nazar-app.sh ax rightclick "GitHub, Operational"
$S/nazar-app.sh ax key escape              # escape | return | tab | cmd-r | cmd-w
$S/nazar-app.sh ax windows                 # on-screen windows of the app
```

Stable handles in this app (from the source, not guesses):

- Dashboard panel header: `Nazar`; header buttons have tooltips `Show issues only`, `Refresh all`, `Settings`; filter field placeholder `Filter services...`; status line `All operational` / `Updated …`.
- Service row: one combined element labelled `<Name>, <Status>` (for example `GitHub, Operational`, `GitHub, Major Outage`, `GitHub, Unavailable`, `…, muted`).
- Empty dashboard: `No services monitored`, button `Get Started`.
- Settings window title `Nazar Settings`; sidebar items `Services`, `Catalog`, `Preferences`, `Feedback`, `Help`.
- Services tab: `Browse Catalog`, `Add Custom...`; custom sheet fields `Name (e.g. My Service)`, `Status Page URL (e.g. https://status.example.com)`, buttons `Cancel`, `Add`; bad URL message `URL must be a valid https:// address with a host`.
- Catalog tab: `Search services...`, one checkbox per service, `Scan Apps`.
- Detail view: back button `Services`, `View Status Page`, `Filter components...`.

Prefer `wait` over `sleep`. The panel and Settings animate in; status values arrive after a network poll.

Mouse events are real. Do not move the mouse or type while a drive runs, and tell the user that before starting on their own Mac.

### Evidence

```bash
$S/nazar-app.sh shot <name>      # full screen + each app window + AX tree
$S/nazar-app.sh log "Added provider"   # grep this run's app log
$S/nazar-app.sh evidence         # prints .verify/evidence/<run>/
```

Everything lands in `.verify/evidence/<run>/` (gitignored). `quit` and `clean` copy the run's app log there as `app.log`. Cleanup never deletes this folder.

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
