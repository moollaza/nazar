#!/usr/bin/env bash
#
# Build, sign, notarize, and DMG a Release build of StatusMonitor.
#
# One-time setup (only you know the password, so this step is manual):
#   xcrun notarytool store-credentials AC_PASSWORD \
#       --apple-id you@example.com \
#       --team-id  W4HBM3A7DC \
#       --password <app-specific-password-from-appleid.apple.com>
#
# That stores the credentials securely in the macOS Keychain. This script
# references the profile by name — no secrets in repo, env, or shell history.
#
# Usage:
#   scripts/release.sh               # build + notarize + staple + DMG
#   scripts/release.sh --skip-notarize   # local test build, no Apple round-trip
#
# Output: build/release/StatusMonitor-<version>.dmg (notarized + stapled)
#

set -euo pipefail

SCHEME="StatusMonitor"
PROJECT="StatusMonitor.xcodeproj"
KEYCHAIN_PROFILE="AC_PASSWORD"
OUTPUT_DIR="build/release"
ARCHIVE_PATH="$OUTPUT_DIR/StatusMonitor.xcarchive"
EXPORT_DIR="$OUTPUT_DIR/export"
EXPORT_OPTIONS="scripts/ExportOptions.plist"

SKIP_NOTARIZE=0
if [[ "${1:-}" == "--skip-notarize" ]]; then
    SKIP_NOTARIZE=1
fi

# Ensure we're at the repo root.
cd "$(dirname "$0")/.."

# Pull version from project.pbxproj so the DMG is named correctly.
VERSION=$(grep 'MARKETING_VERSION' "$PROJECT/project.pbxproj" | head -1 | awk -F'= ' '{print $2}' | tr -d '";')
BUILD=$(grep 'CURRENT_PROJECT_VERSION' "$PROJECT/project.pbxproj" | head -1 | awk -F'= ' '{print $2}' | tr -d '";')
DMG_NAME="StatusMonitor-${VERSION}.dmg"
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"

echo "═══════════════════════════════════════════════════════════"
echo "  StatusMonitor release: v$VERSION (build $BUILD)"
echo "═══════════════════════════════════════════════════════════"

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# ── 1. Archive ───────────────────────────────────────────────
echo
echo "▶ 1/6  Archiving Release build…"
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=macOS" \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    CODE_SIGN_STYLE=Manual \
    | xcbeautify --quiet 2>/dev/null \
    || xcodebuild archive \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration Release \
        -archivePath "$ARCHIVE_PATH" \
        -destination "generic/platform=macOS" \
        CODE_SIGN_IDENTITY="Developer ID Application" \
        CODE_SIGN_STYLE=Manual

# ── 2. Export signed .app ────────────────────────────────────
echo
echo "▶ 2/6  Exporting signed .app…"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTIONS"

APP_PATH="$EXPORT_DIR/StatusMonitor.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo "✗ Expected app at $APP_PATH — export failed?"
    exit 1
fi

# Verify signature before we package it.
echo "  Verifying signature…"
codesign -vvv --deep --strict "$APP_PATH"
spctl --assess --type execute --verbose "$APP_PATH" || \
    echo "  ⚠ spctl assessment warning (expected until notarized)"

# ── 3. Notarize + staple the .app ────────────────────────────
# Staple the .app BEFORE packaging it in the DMG. Stapling only the DMG
# isn't enough: when the user drags StatusMonitor.app to /Applications,
# the ticket goes with the DMG they discard, not with the .app that
# lives on. An unstapled .app works (Gatekeeper phones home), but fails
# on a user who is offline on first launch — common for remote workers.
if [[ "$SKIP_NOTARIZE" -eq 1 ]]; then
    echo
    echo "▶ 3/6  Skipping .app notarization (--skip-notarize)"
else
    echo
    echo "▶ 3/6  Notarizing the .app (first of two notary submissions)…"
    APP_ZIP="$OUTPUT_DIR/StatusMonitor.app.zip"
    ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP"
    xcrun notarytool submit "$APP_ZIP" \
        --keychain-profile "$KEYCHAIN_PROFILE" \
        --wait
    rm -f "$APP_ZIP"

    echo "  Stapling ticket to .app…"
    xcrun stapler staple "$APP_PATH"
    xcrun stapler validate "$APP_PATH"
fi

# ── 4. Build DMG (containing the now-stapled .app) ───────────
echo
echo "▶ 4/6  Building DMG ($DMG_NAME)…"

if command -v create-dmg >/dev/null 2>&1; then
    # Preferred path: create-dmg lays out icons, adds a background, and
    # positions the drop-to-Applications arrow so the DMG looks polished
    # on open. Requires `brew install create-dmg`.
    create-dmg \
        --volname "StatusMonitor" \
        --volicon "$APP_PATH/Contents/Resources/AppIcon.icns" \
        --window-pos 200 120 \
        --window-size 560 380 \
        --icon-size 96 \
        --icon "StatusMonitor.app" 140 180 \
        --app-drop-link 420 180 \
        --no-internet-enable \
        "$DMG_PATH" \
        "$APP_PATH" \
        || { echo "✗ create-dmg failed"; exit 1; }
else
    # Fallback: plain hdiutil DMG with a /Applications symlink. Functional
    # drag-to-install, but no background image / arrow.
    echo "  create-dmg not installed — falling back to plain hdiutil."
    echo "  (brew install create-dmg for the polished layout)"
    DMG_STAGING="$OUTPUT_DIR/dmg-staging"
    rm -rf "$DMG_STAGING"
    mkdir -p "$DMG_STAGING"
    cp -R "$APP_PATH" "$DMG_STAGING/"
    ln -s /Applications "$DMG_STAGING/Applications"

    hdiutil create \
        -volname "StatusMonitor" \
        -srcfolder "$DMG_STAGING" \
        -ov -format UDZO \
        "$DMG_PATH"

    rm -rf "$DMG_STAGING"
fi

# ── 5. Notarize + staple the DMG ─────────────────────────────
# Separately notarize the DMG itself so Gatekeeper is happy when the
# user double-clicks the downloaded .dmg (before they've even copied
# the .app anywhere).
if [[ "$SKIP_NOTARIZE" -eq 1 ]]; then
    echo
    echo "▶ 5/6  Skipping DMG notarization (--skip-notarize)"
    echo "▶ 6/6  Skipping DMG stapling (--skip-notarize)"
else
    echo
    echo "▶ 5/6  Notarizing the DMG (second notary submission)…"
    xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$KEYCHAIN_PROFILE" \
        --wait

    echo
    echo "▶ 6/6  Stapling ticket to DMG…"
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
fi

echo
echo "═══════════════════════════════════════════════════════════"
echo "  ✓ Release built: $DMG_PATH"
if [[ "$SKIP_NOTARIZE" -eq 0 ]]; then
    echo "    Notarized and stapled — ready to distribute."
fi
echo "═══════════════════════════════════════════════════════════"
