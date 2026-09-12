#!/usr/bin/env bash
#
# Build, sign, notarize, and DMG a Release build of Nazar.
#
# One-time setup (only you know the password, so this step is manual):
#   xcrun notarytool store-credentials AC_PASSWORD \
#       --apple-id you@example.com \
#       --team-id  W4HBM3A7DC \
#       --password <app-specific-password-from-appleid.apple.com>
#
# That stores the credentials securely in the macOS Keychain. This script
# references the profile by name — no secrets in repo, env, or shell history.
# Set KEYCHAIN_PROFILE to use a differently named notarytool profile.
#
# Usage:
#   scripts/release.sh                         # build + notarize + staple + DMG
#   KEYCHAIN_PROFILE=Notary scripts/release.sh # use a custom Keychain profile
#   scripts/release.sh --skip-notarize         # local test build, no Apple round-trip
#
# Sparkle appcast signing needs the EdDSA private key in the Keychain under
# `sparkle-ed-private-key`, reachable through the `secret` wrapper. The key is
# only ever piped into generate_appcast — never assigned, printed, or written
# to disk. See README "Releasing" for the one-time setup.
#
# Output: build/release/Nazar-<version>.dmg (notarized + stapled)
#         build/release/appcast.xml         (signed, upload alongside the DMG)
#

set -euo pipefail

SCHEME="StatusMonitor"
PROJECT="StatusMonitor.xcodeproj"
SIGNING_IDENTITY="Developer ID Application"
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-AC_PASSWORD}"
OUTPUT_DIR="build/release"
ARCHIVE_PATH="$OUTPUT_DIR/StatusMonitor.xcarchive"
EXPORT_DIR="$OUTPUT_DIR/export"
EXPORT_OPTIONS="scripts/ExportOptions.plist"
PUBLIC_APP_NAME="Nazar.app"
LEGACY_APP_NAME="StatusMonitor.app"
VERSION_XCCONFIG="Config/Version.xcconfig"
SPARKLE_KEY_NAME="sparkle-ed-private-key"
PACKAGES_DIR="$OUTPUT_DIR/SourcePackages"
SPARKLE_BIN="$PACKAGES_DIR/artifacts/sparkle/Sparkle/bin"
APPCAST_PATH="$OUTPUT_DIR/appcast.xml"
APPCAST_STAGING="$OUTPUT_DIR/appcast-staging"
REPO="moollaza/nazar"

# Print a setting's value from the version xcconfig, minus trailing comments.
xcconfig_value() {
    sed -nE "s|^[[:space:]]*$1[[:space:]]*=[[:space:]]*([^/[:space:]]+).*|\1|p" "$VERSION_XCCONFIG" | head -1
}

SKIP_NOTARIZE=0
if [[ "${1:-}" == "--skip-notarize" ]]; then
    SKIP_NOTARIZE=1
fi

# Ensure we're at the repo root.
cd "$(dirname "$0")/.."

# Config/Version.xcconfig is the single source for the app version;
# release-please bumps its MARKETING_VERSION in the same Release PR that
# produces the tag. The tag and the xcconfig must agree, or the DMG name,
# GitHub release, and CFBundleShortVersionString would diverge.
TAG_VERSION=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)
XCCONFIG_VERSION=$(xcconfig_value MARKETING_VERSION)
XCCONFIG_BUILD=$(xcconfig_value CURRENT_PROJECT_VERSION)

if [[ -z "$XCCONFIG_VERSION" || ! "$XCCONFIG_BUILD" =~ ^[0-9]+$ ]]; then
    echo "✗ Could not read MARKETING_VERSION / CURRENT_PROJECT_VERSION from $VERSION_XCCONFIG"
    exit 1
fi
if [[ -n "$TAG_VERSION" && "$TAG_VERSION" != "$XCCONFIG_VERSION" ]]; then
    echo "✗ Version drift: git tag=v$TAG_VERSION, $VERSION_XCCONFIG=$XCCONFIG_VERSION"
    echo "  Run this from the release tag commit (\`git checkout v$TAG_VERSION\`)."
    exit 1
fi
VERSION="$XCCONFIG_VERSION"

# CFBundleVersion must strictly increase across releases (Sparkle compares
# it; App Store Connect rejects non-increasing uploads). Derive it from the
# commit count so it can't be forgotten, floored at the xcconfig value.
if [[ "$(git rev-parse --is-shallow-repository)" == "true" ]]; then
    echo "✗ Shallow clone: commit count is wrong. Run \`git fetch --unshallow\`."
    exit 1
fi
BUILD=$(git rev-list --count HEAD)
if (( BUILD < XCCONFIG_BUILD )); then
    BUILD="$XCCONFIG_BUILD"
fi

DMG_NAME="Nazar-${VERSION}.dmg"
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"

echo "═══════════════════════════════════════════════════════════"
echo "  Nazar release: v$VERSION (build $BUILD)"
echo "═══════════════════════════════════════════════════════════"

# ── 0. Preflight ─────────────────────────────────────────────
# Everything the tail of this script needs, checked before the ~20 minutes of
# archiving and notarization. A missing Keychain entry should cost seconds.
echo
echo "▶ 0/7  Preflight…"

if ! command -v secret >/dev/null 2>&1; then
    echo "✗ \`secret\` wrapper not found — it reads the Sparkle signing key from the Keychain."
    exit 1
fi
if ! secret has "$SPARKLE_KEY_NAME" >/dev/null 2>&1; then
    echo "✗ Keychain has no \`$SPARKLE_KEY_NAME\` — the appcast can't be signed."
    echo "  See README \"Releasing\" for the one-time key setup."
    exit 1
fi
echo "  ✓ Sparkle signing key present"

# The appcast's release notes come from the GitHub release body, and both
# files upload to that release.
HAVE_RELEASE=0
if gh release view "v$VERSION" --repo "$REPO" >/dev/null 2>&1; then
    HAVE_RELEASE=1
    echo "  ✓ GitHub release v$VERSION exists"
elif [[ "$SKIP_NOTARIZE" -eq 1 ]]; then
    echo "  ⚠ No GitHub release v$VERSION — using placeholder release notes (--skip-notarize)"
else
    echo "✗ No GitHub release v$VERSION — merge the release-please PR first."
    exit 1
fi

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# ── 1. Archive ───────────────────────────────────────────────
echo
echo "▶ 1/7  Archiving Release build…"
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=macOS" \
    -clonedSourcePackagesDirPath "$PACKAGES_DIR" \
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
    CODE_SIGN_STYLE=Manual \
    CURRENT_PROJECT_VERSION="$BUILD" \
    | xcbeautify --quiet 2>/dev/null \
    || xcodebuild archive \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration Release \
        -archivePath "$ARCHIVE_PATH" \
        -destination "generic/platform=macOS" \
        -clonedSourcePackagesDirPath "$PACKAGES_DIR" \
        CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
        CODE_SIGN_STYLE=Manual \
        CURRENT_PROJECT_VERSION="$BUILD"

# ── 2. Export signed .app ────────────────────────────────────
echo
echo "▶ 2/7  Exporting signed .app…"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTIONS"

APP_PATH="$EXPORT_DIR/$PUBLIC_APP_NAME"
LEGACY_APP_PATH="$EXPORT_DIR/$LEGACY_APP_NAME"
if [[ ! -d "$APP_PATH" && -d "$LEGACY_APP_PATH" ]]; then
    rm -rf "$APP_PATH"
    mv "$LEGACY_APP_PATH" "$APP_PATH"
fi
if [[ ! -d "$APP_PATH" ]]; then
    echo "✗ Expected app at $APP_PATH — export failed?"
    exit 1
fi

# Backstop: the shipped bundle must report the version we're naming it.
PLIST="$APP_PATH/Contents/Info.plist"
APP_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$PLIST")
APP_BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$PLIST")
if [[ "$APP_VERSION" != "$VERSION" || "$APP_BUILD" != "$BUILD" ]]; then
    echo "✗ Bundle reports $APP_VERSION ($APP_BUILD), expected $VERSION ($BUILD)"
    exit 1
fi

# Verify signature before we package it.
echo "  Verifying signature…"
codesign -vvv --deep --strict "$APP_PATH"
spctl --assess --type execute --verbose "$APP_PATH" || \
    echo "  ⚠ spctl assessment warning (expected until notarized)"

# ── 3. Notarize + staple the .app ────────────────────────────
# Staple the .app BEFORE packaging it in the DMG. Stapling only the DMG
# isn't enough: when the user drags Nazar.app to /Applications,
# the ticket goes with the DMG they discard, not with the .app that
# lives on. An unstapled .app works (Gatekeeper phones home), but fails
# on a user who is offline on first launch — common for remote workers.
if [[ "$SKIP_NOTARIZE" -eq 1 ]]; then
    echo
    echo "▶ 3/7  Skipping .app notarization (--skip-notarize)"
else
    echo
    echo "▶ 3/7  Notarizing the .app (first of two notary submissions)…"
    APP_ZIP="$OUTPUT_DIR/Nazar.app.zip"
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
echo "▶ 4/7  Building DMG ($DMG_NAME)…"

if command -v create-dmg >/dev/null 2>&1; then
    # Preferred path: create-dmg lays out icons, adds a background, and
    # positions the drop-to-Applications arrow so the DMG looks polished
    # on open. Requires `brew install create-dmg`.
    create-dmg \
        --volname "Nazar" \
        --volicon "$APP_PATH/Contents/Resources/AppIcon.icns" \
        --window-pos 200 120 \
        --window-size 560 380 \
        --icon-size 96 \
        --icon "$PUBLIC_APP_NAME" 140 180 \
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
        -volname "Nazar" \
        -srcfolder "$DMG_STAGING" \
        -ov -format UDZO \
        "$DMG_PATH"

    rm -rf "$DMG_STAGING"
fi

# Sign the disk image before notarization so Gatekeeper can assess the DMG
# itself, not just the app inside it.
echo "  Signing DMG…"
codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG_PATH"

# ── 5. Notarize + staple the DMG ─────────────────────────────
# Separately notarize the DMG itself so Gatekeeper is happy when the
# user double-clicks the downloaded .dmg (before they've even copied
# the .app anywhere).
if [[ "$SKIP_NOTARIZE" -eq 1 ]]; then
    echo
    echo "▶ 5/7  Skipping DMG notarization (--skip-notarize)"
    echo "▶ 6/7  Skipping DMG stapling (--skip-notarize)"
else
    echo
    echo "▶ 5/7  Notarizing the DMG (second notary submission)…"
    xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$KEYCHAIN_PROFILE" \
        --wait

    echo
    echo "▶ 6/7  Stapling ticket to DMG…"
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
fi

# ── 7. Sign the appcast ──────────────────────────────────────
# Must run AFTER stapling: stapling rewrites the DMG, so a signature made
# before it would not match the bytes users download.
echo
echo "▶ 7/7  Generating signed appcast…"

if [[ ! -x "$SPARKLE_BIN/generate_appcast" ]]; then
    echo "✗ generate_appcast not found at $SPARKLE_BIN"
    echo "  The archive step should have resolved Sparkle into $PACKAGES_DIR."
    exit 1
fi

# Stage this release alone so the appcast holds exactly one item — Sparkle
# only needs the newest. The notes file's name must match the DMG's stem for
# generate_appcast to pair them up.
rm -rf "$APPCAST_STAGING"
mkdir -p "$APPCAST_STAGING"
cp "$DMG_PATH" "$APPCAST_STAGING/"
if [[ "$HAVE_RELEASE" -eq 1 ]]; then
    gh release view "v$VERSION" --repo "$REPO" --json body --jq .body \
        > "$APPCAST_STAGING/Nazar-$VERSION.md"
else
    echo "Dry run — no release notes." > "$APPCAST_STAGING/Nazar-$VERSION.md"
fi

# The key is piped, never assigned to a variable or written to disk.
secret get "$SPARKLE_KEY_NAME" | "$SPARKLE_BIN/generate_appcast" \
    --ed-key-file - \
    --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" \
    --link "https://usenazar.com" \
    --embed-release-notes \
    "$APPCAST_STAGING"

mv "$APPCAST_STAGING/appcast.xml" "$APPCAST_PATH"
rm -rf "$APPCAST_STAGING"

# Post-check: a wrong version or a missing signature only shows up as a
# silent no-update for every user, so fail here instead.
ITEM_COUNT=$(grep -c "<item>" "$APPCAST_PATH" || true)
if [[ "$ITEM_COUNT" != "1" ]]; then
    echo "✗ Appcast has $ITEM_COUNT items, expected exactly 1"
    exit 1
fi
for expected in \
    "sparkle:version=\"$BUILD\"" \
    "sparkle:shortVersionString=\"$VERSION\"" \
    "sparkle:edSignature=\"" \
    "v$VERSION/$DMG_NAME"
do
    if ! grep -q "$expected" "$APPCAST_PATH"; then
        echo "✗ Appcast is missing: $expected"
        exit 1
    fi
done
echo "  ✓ appcast.xml: 1 item, v$VERSION (build $BUILD), signed"

echo
echo "═══════════════════════════════════════════════════════════"
echo "  ✓ Release built: $DMG_PATH"
echo "  ✓ Appcast:       $APPCAST_PATH"
if [[ "$SKIP_NOTARIZE" -eq 0 ]]; then
    echo "    Notarized and stapled — ready to distribute."
    echo
    echo "  Upload both — the appcast is useless without the DMG beside it,"
    echo "  and a release without an appcast is invisible to the updater:"
    echo
    echo "    gh release upload v$VERSION \\"
    echo "        $DMG_PATH \\"
    echo "        $APPCAST_PATH --repo $REPO"
else
    echo
    echo "  ⚠ --skip-notarize: this DMG is not notarized and this appcast"
    echo "    describes it. Do NOT upload either to a release."
fi
echo "═══════════════════════════════════════════════════════════"
