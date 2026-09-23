#!/bin/bash
# One-command release: propagate a version bump everywhere, build the DMG, and
# (optionally) ship it to GitHub + the site.
#
# Usage:
#   ./scripts/release.sh 0.3.0            # prep: bump, build DMG, update site,
#                                         #   scaffold a changelog entry — then stop
#   ./scripts/release.sh 0.3.0 --ship     # same, then commit + push + deploy,
#                                         #   and publish the GitHub Release
#
# Typical flow: run without --ship, fill in the new changelog entry in
# site/changelog.html (replace the "TODO" line), then re-run with --ship.
#
# Signing/notarization pass through to make-dmg.sh via SIGN_IDENTITY /
# NOTARY_PROFILE env vars (see that script).
#
# The GitHub Release is not optional bookkeeping: the app's update checker
# reads releases/latest, so a version that only reaches the site is invisible
# to everyone already running AloeNotch. 0.9.0–0.9.2 shipped that way and
# nobody on 0.8.5 was told. Its notes come from the changelog entry (see
# release-notes.py) and its title from that entry's first bold line, unless
# RELEASE_TITLE is set.
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
#
# Everything matching AloeNotch-*.dmg except the frozen Intel build. That one
# is the last universal, macOS 15 release and is deliberately never rebuilt —
# a blanket `rm AloeNotch-*.dmg` would delete it on the next release and
# silently 404 the download the changelog points Intel users at.
find "$ASSETS" -maxdepth 1 -name 'AloeNotch-*.dmg' ! -name '*-intel-eol.dmg' -delete
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

# Everything the GitHub Release needs is checked before anything is pushed, so
# a missing `gh` can't leave the site on a version the app never hears about.
command -v gh >/dev/null || fail "gh (GitHub CLI) is needed to publish the release — brew install gh"
gh auth status >/dev/null 2>&1 || fail "gh is not signed in — run: gh auth login"
NOTES=$(mktemp)
"$PROJECT_DIR/scripts/release-notes.py" "$NEW" > "$NOTES" || fail "could not build release notes for $NEW"
TITLE="$NEW — ${RELEASE_TITLE:-$("$PROJECT_DIR/scripts/release-notes.py" "$NEW" --headline)}"
DMG="$PROJECT_DIR/build/AloeNotch-$NEW.dmg"
[ -f "$DMG" ] || fail "missing $DMG"

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

echo "==> Publishing the GitHub Release (what the in-app update check reads)"
if gh release view "v$NEW" >/dev/null 2>&1; then
    echo "    v$NEW already exists — replacing its DMG"
    gh release upload "v$NEW" "$DMG" --clobber
else
    gh release create "v$NEW" "$DMG" \
        --title "$TITLE" \
        --notes-file "$NOTES" \
        --target "$(git rev-parse HEAD)" \
        --latest \
    || fail "site is live but the GitHub Release failed — re-run:
    gh release create v$NEW \"$DMG\" --title \"$TITLE\" --notes-file <(./scripts/release-notes.py $NEW) --target $(git rev-parse HEAD) --latest"
fi
rm -f "$NOTES"

echo "==> Shipped $NEW 🎉  (https://aloenotch-site.xnucade.workers.dev)"
