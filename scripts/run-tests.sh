#!/usr/bin/env bash
# Run the unit tests.
#
#   ./scripts/run-tests.sh
#
# Compiles the SwiftUI-free logic files together with Tests/ and runs them.
# There is no Xcode test target on purpose: everything covered here is pure,
# so a direct compile runs in about a second and needs no scheme, no pbxproj
# entry and nothing to keep in sync. Add files to SOURCES below as more logic
# becomes independently testable.
set -euo pipefail

cd "$(dirname "$0")/.."

# Design-token guards. The panel has one opacity ladder (`Ink` in Theme.swift)
# and one type scale (`Typography`); these fail on anything that bypasses
# them, so the ladder can't quietly grow back to 22 shades.
LINT_FAIL=0
if RAW=$(grep -rn --include='*.swift' -E '\.white\.opacity\(' OpenNotch | grep -v 'Design/Theme.swift'); then
    echo "error: raw .white.opacity( — use an Ink token:" >&2; echo "$RAW" >&2; LINT_FAIL=1
fi
# Panel views only: the Settings/onboarding windows use the system text
# styles, and a size scaled from a parameter (`size * 0.26`) is deliberate.
if RAW=$(grep -rn --include='*.swift' -E '\.system\(size: [0-9.]+[,)]' OpenNotch/Views \
        | grep -v -e 'Views/Settings/' -e 'WelcomeView' -e 'WhatsNewView' -e 'SettingsMenuView'); then
    echo "error: raw .system(size:) in the panel — use Typography:" >&2; echo "$RAW" >&2; LINT_FAIL=1
fi
[ "$LINT_FAIL" -eq 0 ] || exit 1
echo "✓ design tokens clean"

SOURCES=(
    OpenNotch/Notch/PanelState.swift
    OpenNotch/Design/SemanticVersion.swift
    OpenNotch/System/ClipboardHistory.swift
    OpenNotch/Timer/CountdownState.swift
    OpenNotch/Design/MotionPersonality.swift
    OpenNotch/Notch/SwipeTracker.swift
)

TESTS=(Tests/*.swift)

# Xcode's own toolchain by absolute path — the /usr/bin shim fails when
# xcode-select points at bare CommandLineTools, and Xcode-beta ships an
# arm64-only libxcrun the universal shim cannot load.
SWIFTC=""
if swiftc -version >/dev/null 2>&1; then
    SWIFTC="$(command -v swiftc)"
else
    for XC in /Applications/Xcode.app /Applications/Xcode-beta.app; do
        CANDIDATE="$XC/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
        [ -x "$CANDIDATE" ] && SWIFTC="$CANDIDATE" && break
    done
fi
[ -n "$SWIFTC" ] || { echo "error: no usable swiftc found." >&2; exit 1; }

# The host may run a newer macOS than any installed SDK targets, in which case
# the default target triple has no standard library to load. Pin to the SDK.
SDK=""
for XC in /Applications/Xcode.app /Applications/Xcode-beta.app; do
    CANDIDATE="$XC/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
    [ -d "$CANDIDATE" ] && SDK="$CANDIDATE" && break
done

BIN="$(mktemp -d)/aloenotch-tests"
ARGS=(-O -o "$BIN")
[ -n "$SDK" ] && ARGS+=(-sdk "$SDK" -target arm64-apple-macosx26.0)

"$SWIFTC" "${ARGS[@]}" "${SOURCES[@]}" "${TESTS[@]}"
"$BIN"
