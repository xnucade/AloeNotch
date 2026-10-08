#!/bin/bash
# Notarize and staple a signed AloeNotch DMG, then check Gatekeeper accepts it.
#
# Usage:
#   NOTARY_PROFILE=aloenotch ./scripts/notarize.sh build/AloeNotch-0.14.0.dmg
#
# make-dmg.sh calls this when NOTARY_PROFILE is set; it can also be run on its
# own to retry a DMG that's already built. Needs the Apple Developer Program
# and a one-time `notarytool store-credentials`; see docs/NOTARIZATION.md.
#
# BLOCKED until enrolment: there is no Developer ID certificate yet, so this has
# never run against the real service.
set -euo pipefail

DMG="${1:-}"
fail() { echo "error: $*" >&2; exit 1; }
[ -n "$DMG" ] && [ -f "$DMG" ] || fail "usage: notarize.sh <signed .dmg>"
[ -n "${NOTARY_PROFILE:-}" ] || fail "set NOTARY_PROFILE to a notarytool keychain profile"

# Refuse what the service would refuse, before uploading anything.
MOUNT=$(mktemp -d)
hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MOUNT" -quiet
trap 'hdiutil detach "$MOUNT" -quiet 2>/dev/null || true; rmdir "$MOUNT" 2>/dev/null || true' EXIT
APP=$(find "$MOUNT" -maxdepth 1 -name '*.app' | head -1)
[ -n "$APP" ] || fail "no .app inside $DMG"
while IFS= read -r -d '' FILE; do
    file -b "$FILE" | grep -q '^Mach-O' || continue
    INFO=$(codesign -dvv "$FILE" 2>&1) || fail "unsigned: ${FILE#"$MOUNT/"}"
    grep -q '^Authority=Developer ID Application' <<<"$INFO" \
        || fail "not Developer ID signed: ${FILE#"$MOUNT/"}"
    grep -q '^Timestamp=' <<<"$INFO" || fail "no secure timestamp: ${FILE#"$MOUNT/"}"
done < <(find "$APP" -type f -print0)
codesign -dvv "$APP" 2>&1 | grep -q 'flags=.*runtime' || fail "hardened runtime is off"
hdiutil detach "$MOUNT" -quiet; trap - EXIT; rmdir "$MOUNT"

echo "==> Notarizing $(basename "$DMG") (profile: $NOTARY_PROFILE)"
RESULT=$(mktemp)
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" \
    --wait --output-format json | tee "$RESULT"
STATUS=$(plutil -extract status raw -o - "$RESULT" 2>/dev/null || echo unknown)
ID=$(plutil -extract id raw -o - "$RESULT" 2>/dev/null || echo "")
rm -f "$RESULT"
if [ "$STATUS" != "Accepted" ]; then
    # The log names each file and the reason, which the status never does.
    [ -n "$ID" ] && xcrun notarytool log "$ID" --keychain-profile "$NOTARY_PROFILE" >&2
    fail "notarization finished as '$STATUS'"
fi

echo "==> Stapling"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG"
echo "==> Notarized: $DMG"
