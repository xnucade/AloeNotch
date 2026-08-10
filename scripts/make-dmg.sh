#!/bin/bash
# Builds AloeNotch (Release) and packages it into a distributable DMG.
#
# Usage:
#   ./scripts/make-dmg.sh                        # ad-hoc signed (free, see notes)
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
#     ./scripts/make-dmg.sh                      # properly signed
#   SIGN_IDENTITY="..." NOTARY_PROFILE="myprofile" \
#     ./scripts/make-dmg.sh                      # signed + notarized + stapled
#
# NOTARY_PROFILE is a keychain profile created once with:
#   xcrun notarytool store-credentials myprofile \
#     --apple-id you@example.com --team-id TEAMID --password <app-specific-pw>
#
# Ad-hoc builds work, but downloaders must approve the app in
# System Settings > Privacy & Security ("Open Anyway") on first launch.
# A Developer ID + notarization ($99/yr Apple Developer Program) removes that.
set -euo pipefail

# The Xcode project, scheme, and source folder are still named "OpenNotch"
# internally; only the product/brand was renamed to "AloeNotch" (via
# PRODUCT_NAME). PROJECT_NAME drives the build; APP_NAME drives the output.
PROJECT_NAME="OpenNotch"
APP_NAME="AloeNotch"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$PROJECT_DIR/build"          # final DMG lands here
# Build and sign in a temp dir OUTSIDE the project. If the project lives under
# an iCloud-synced folder (Desktop/Documents), the file provider re-stamps
# com.apple.FinderInfo onto build output, which makes codesign fail with
# "resource fork, Finder information, or similar detritus not allowed".
WORK_DIR="${TMPDIR:-/tmp}/AloeNotch-build"
DERIVED="$WORK_DIR/DerivedData"
STAGING="$WORK_DIR/dmg-staging"
# Default to the local self-signed identity, falling back to ad-hoc if it is
# not in the keychain (a fresh clone, or another machine).
#
# This matters more than it looks. Ad-hoc signing makes the designated
# requirement a hash of the binary itself, so *every build is a different app*
# as far as macOS privacy is concerned — which means Calendar, Location and
# Accessibility grants are silently discarded on every rebuild, and on every
# update a user installs. Signing with a stable certificate makes the
# requirement `identifier … and certificate root = …`, which does not change
# between builds, so permissions persist.
#
# Keep the certificate backed up: signing future releases with a *different*
# identity resets everyone's permissions again. Export it from Keychain Access
# ("AloeNotch Signing", including the private key) and store it somewhere safe.
DEFAULT_IDENTITY="AloeNotch Signing"
if [ -z "${SIGN_IDENTITY:-}" ]; then
    if security find-identity -p codesigning 2>/dev/null | grep -q "$DEFAULT_IDENTITY"; then
        SIGN_IDENTITY="$DEFAULT_IDENTITY"
    else
        echo "warning: '$DEFAULT_IDENTITY' not found in the keychain — falling back to" >&2
        echo "         ad-hoc signing. Permissions will reset for users on this build." >&2
        SIGN_IDENTITY="-"
    fi
fi
mkdir -p "$OUT_DIR"

# Find a usable xcodebuild when xcode-select points at bare CommandLineTools.
#
# Exporting DEVELOPER_DIR and letting the /usr/bin shim find it is NOT enough:
# Xcode-beta ships no usr/bin/xcrun of its own, and its libxcrun.dylib is
# arm64-only, so the universal (arm64e) system shim fails to dlopen it with
# "incompatible architecture". Invoking Xcode's own xcodebuild binary by
# absolute path avoids the shim entirely.
XCODEBUILD=""
if xcodebuild -version >/dev/null 2>&1; then
    XCODEBUILD="$(command -v xcodebuild)"
else
    for XC in /Applications/Xcode.app /Applications/Xcode-beta.app; do
        CANDIDATE="$XC/Contents/Developer/usr/bin/xcodebuild"
        [ -x "$CANDIDATE" ] && XCODEBUILD="$CANDIDATE" && break
    done
fi
[ -n "$XCODEBUILD" ] || {
    echo "error: no usable xcodebuild found." >&2
    echo "       Install Xcode, or point xcode-select at it:" >&2
    echo "       sudo xcode-select -s /Applications/Xcode.app" >&2
    exit 1
}

VERSION=$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' \
    "$PROJECT_DIR/$PROJECT_NAME.xcodeproj/project.pbxproj" | head -1)
DMG="$OUT_DIR/$APP_NAME-$VERSION.dmg"

echo "==> Building $APP_NAME $VERSION (Release)"
# Captured rather than streamed so the known `-quiet` artifact can be filtered
# without hiding a real failure.
#
# With `-quiet`, xcodebuild prints
#   "error: the following command failed with exit code 0 but produced no
#    further output"
# on a perfectly successful build — a summariser quirk, not a build problem
# (note the exit code in its own message). It appeared on two consecutive
# releases and cost time both times, so: on failure the whole log is dumped and
# we abort; on success only that one line is suppressed.
BUILD_LOG="$(mktemp)"
trap 'rm -f "$BUILD_LOG"' EXIT
if ! "$XCODEBUILD" -project "$PROJECT_DIR/$PROJECT_NAME.xcodeproj" \
    -scheme "$PROJECT_NAME" -configuration Release build \
    -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO -quiet >"$BUILD_LOG" 2>&1
then
    cat "$BUILD_LOG" >&2
    echo "error: build failed." >&2
    exit 1
fi
grep -vF 'failed with exit code 0 but produced no further output' "$BUILD_LOG" >&2 || true

APP="$DERIVED/Build/Products/Release/$APP_NAME.app"
[ -d "$APP" ] || { echo "Build product not found: $APP"; exit 1; }

echo "==> Signing (identity: $SIGN_IDENTITY)"
ENTITLEMENTS="$PROJECT_DIR/$PROJECT_NAME/$PROJECT_NAME.entitlements"

# Validate before signing. codesign treats an unparseable entitlements file as
# a warning, not an error — it prints "Failed to parse entitlements" and then
# signs the app with NO entitlements at all, exit status 0. The result looks
# perfectly healthy and silently loses every capability the file granted, which
# is exactly how a stray "--" inside an XML comment cost an afternoon.
plutil -lint "$ENTITLEMENTS" >/dev/null || {
    echo "error: $ENTITLEMENTS is not valid XML." >&2
    echo "       (XML comments may not contain two consecutive hyphens.)" >&2
    exit 1
}

# Strip extended attributes (resource forks, Finder info) that break codesign.
xattr -cr "$APP"
codesign --force --deep --options runtime \
    --entitlements "$ENTITLEMENTS" \
    -s "$SIGN_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"

# And confirm they actually landed, for the same reason.
EXPECTED=$(plutil -convert json -o - "$ENTITLEMENTS" | tr ',' '\n' | grep -c 'com\.apple\.security')
ACTUAL=$(codesign -d --entitlements - --xml "$APP" 2>/dev/null \
    | plutil -convert json -o - - 2>/dev/null | tr ',' '\n' | grep -c 'com\.apple\.security' || echo 0)
if [ "$ACTUAL" -lt "$EXPECTED" ]; then
    echo "error: signed app carries $ACTUAL entitlements, expected $EXPECTED." >&2
    exit 1
fi
echo "    entitlements verified ($ACTUAL)"

echo "==> Creating DMG"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" \
    -ov -format UDZO "$DMG" -quiet
rm -rf "$STAGING"

if [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "==> Notarizing (profile: $NOTARY_PROFILE)"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
fi

echo "==> Done: $DMG"
du -h "$DMG" | cut -f1 | xargs echo "    size:"
