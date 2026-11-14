# App updates (Sparkle)

The DMG build of Nazar updates itself with Sparkle. It reads `https://usenazar.com/appcast.xml`, which redirects to the newest GitHub release's `appcast.xml`. The App Store build (`Nazar-MAS`) has no updater at all.

## Sub-features

- `upd-menu` right-click menu has `Check for Updates…` (or `Update Available…` after a background find) as its second item.
- `upd-disabled-debug` in Debug builds the item is present and disabled (Sparkle never starts).
- `upd-redirect` `https://usenazar.com/appcast.xml` 302s to the latest release's `appcast.xml`, which is a signed appcast for a version at least the shipped one.
- `upd-install` a Release build with an older build number finds, installs, and relaunches into the new build.
- `upd-gentle` a background find when the app is not focused posts a notification and changes the menu title instead of opening a window.
- `upd-mas` the `Nazar-MAS` product contains no Sparkle framework or feed keys.

## How to get to it (user POV)

- Menu bar icon right-click > `Check for Updates…`.
- Automatic: Sparkle's scheduled background check (daily).
- Clicking the `Update available` notification.

## Driving it with nazar-app.sh

Preconditions:

- `upd-menu`, `upd-disabled-debug`: the normal Debug verify build.
- `upd-install`, `upd-gentle`: a Developer ID signing identity and the Sparkle EdDSA private key in the Keychain. Only the maintainer's Mac has these.

- **Menu item.** Run `ax statusitem --right`, then `ax find "Check for Updates…"`. It exists and, in Debug, shows `[disabled]`. `shot upd-menu`. Close with `ax key escape`.
- **Redirect.** Run `curl -sI https://usenazar.com/appcast.xml`. Status 302, `location:` is `https://github.com/moollaza/nazar/releases/latest/download/appcast.xml`. Then `curl -sL https://usenazar.com/appcast.xml | grep -E 'sparkle:(version|shortVersionString)|edSignature'` shows a version and an `edSignature`. A 404 after the redirect means no release has uploaded an appcast yet: report `upd-redirect` as failing.
- **Install (rehearsal).** Follow U7 in `docs/plans/2026-09-12-0857-feat-sparkle-auto-updates-plan.md`: build an old Release app with a low `CURRENT_PROJECT_VERSION` and `SPARKLE_FEED_URL` pointed at a local feed, build the new DMG and appcast with `scripts/release.sh --skip-notarize`, serve both, run the old app from /Applications, press `Check for Updates…`, install. Proof: the relaunched app's `CFBundleVersion` (`/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' /Applications/Nazar.app/Contents/Info.plist`) is the new one, and `log show --last 10m --predicate 'process == "Nazar" OR process CONTAINS "Sparkle"'` has no sandbox or XPC denials.
- **MAS has no Sparkle.** Build `Nazar-MAS` (`xcodebuild -project StatusMonitor.xcodeproj -scheme Nazar-MAS -configuration Release -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO build`), then `find <product>.app -name 'Sparkle*'` is empty and `PlistBuddy -c 'Print :SUFeedURL'` fails.

## Gotchas

- The rehearsal installs into /Applications and replaces whatever Nazar is there, the user's real copy included. Ask before running it, and quit the user's Nazar first.
- The rehearsal uses the real bundle ID (Sparkle's installer XPC service names derive from it), so it is not isolated like the Debug verify build.
- Plain-http local feeds may be blocked by App Transport Security. Serve over https or from a GitHub draft pre-release.
- `-UITestMode` wipes the defaults domain where Sparkle keeps `SULastCheckTime`. Do not pass it to a Release build under test.
