#!/bin/bash
# One-command release: propagate a version bump everywhere, build the DMG, and
# (optionally) ship it to GitHub + the site.
#
# Usage:
#   ./scripts/release.sh 0.3.0            # prep: bump, build DMG, update site,
#                                         #   scaffold a changelog entry — then stop
#   ./scripts/release.sh 0.3.0 --ship     # same, then commit + push + deploy
#
# Typical flow: run without --ship, fill in the new changelog entry in
# site/changelog.html (replace the "TODO" line), then re-run with --ship.
#
# Signing/notarization pass through to make-dmg.sh via SIGN_IDENTITY /
# NOTARY_PROFILE env vars (see that script).
set -euo pipefail

NEW="${1:-}"
SHIP="${2:-}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PBXPROJ="$PROJECT_DIR/OpenNotch.xcodeproj/project.pbxproj"
INDEX="$PROJECT_DIR/site/index.html"
CHANGELOG="$PROJECT_DIR/site/changelog.html"
ASSETS="$PROJECT_DIR/site/assets"

fail() { echo "error: $*" >&2; exit 1; }

[ -n "$NEW" ] || fail "usage: release.sh <version> [--ship]  (e.g. release.sh 0.3.0)"
[[ "$NEW" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version must be semver like 0.3.0 (got '$NEW')"
[ -z "$SHIP" ] || [ "$SHIP" = "--ship" ] || fail "second arg must be --ship or omitted"

OLD=$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' "$PBXPROJ" | head -1)
[ -n "$OLD" ] || fail "could not read current MARKETING_VERSION"
echo "==> Releasing $OLD → $NEW"

# 1. Version in the Xcode project (both Debug + Release configs).
sed -i '' "s/MARKETING_VERSION = $OLD;/MARKETING_VERSION = $NEW;/g" "$PBXPROJ"

# 2. Site download link + version text.
sed -i '' "s/AloeNotch-$OLD\.dmg/AloeNotch-$NEW.dmg/g; s/Version $OLD/Version $NEW/g" "$INDEX"

# 3. Scaffold a changelog entry (skipped if this version is already present).
if grep -q "<h2>$NEW " "$CHANGELOG"; then
    echo "    changelog already has a $NEW entry — leaving it"
else
    DATE=$(date "+%B %e, %Y" | tr -s ' ')
    ENTRY=$(mktemp)
    cat > "$ENTRY" <<EOF

    <h2>$NEW — $DATE</h2>
    <ul>
      <li>TODO: describe this release.</li>
    </ul>
EOF
    awk -v ef="$ENTRY" '/<!-- new-entry -->/{print; while((getline line < ef)>0) print line; close(ef); next} {print}' "$CHANGELOG" > "$CHANGELOG.tmp"
    mv "$CHANGELOG.tmp" "$CHANGELOG"
    rm -f "$ENTRY"
    echo "    added changelog stub for $NEW — edit the TODO line in site/changelog.html"
fi

# 4. Build the DMG (make-dmg.sh derives the version from the project).
"$PROJECT_DIR/scripts/make-dmg.sh"

# 5. Swap the DMG into the site (drop any older ones).
rm -f "$ASSETS"/AloeNotch-*.dmg
cp "$PROJECT_DIR/build/AloeNotch-$NEW.dmg" "$ASSETS/AloeNotch-$NEW.dmg"
echo "==> Site download set to AloeNotch-$NEW.dmg"

if [ "$SHIP" != "--ship" ]; then
    cat <<EOF

Prep done for $NEW. Next:
  1. Edit the new entry in site/changelog.html (replace the TODO line).
  2. Ship it:   ./scripts/release.sh $NEW --ship
EOF
    exit 0
fi

# --- Ship ---
grep -q "TODO: describe this release." "$CHANGELOG" && \
    fail "changelog still has a TODO placeholder — fill in the $NEW entry before shipping"

echo "==> Committing, pushing, and deploying"
cd "$PROJECT_DIR"
git add -A
git commit -q -m "Release $NEW" || { echo "    nothing to commit"; }
git fetch -q origin
if [ "$(git rev-list --count HEAD..origin/main 2>/dev/null || echo 0)" -gt 0 ]; then
    echo "    remote has new commits — rebasing"
    git pull --rebase origin main
fi
git push origin main

( cd "$PROJECT_DIR/site" && npx wrangler deploy )

echo "==> Shipped $NEW 🎉  (https://aloenotch-site.xnucade.workers.dev)"
