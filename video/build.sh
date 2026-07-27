#!/usr/bin/env bash
# Build the AloeNotch demo video: render frames, then encode.
#
#   ./build.sh              # full 60fps render + encode + install into the site
#   ./build.sh --fps 30     # faster draft
#   ./build.sh --no-install # build into video/out/ but leave the site alone
#
# Outputs:
#   out/demo.mp4     H.264, faststart, ~1080p — the site's <video> source
#   out/demo.webm    VP9, smaller, served first where supported
#   out/poster.jpg   first meaningful frame, used as the <video> poster
set -euo pipefail

cd "$(dirname "$0")"

FPS=60
INSTALL=1
for ((i = 1; i <= $#; i++)); do
  case "${!i}" in
    --fps) j=$((i + 1)); FPS="${!j}" ;;
    --no-install) INSTALL=0 ;;
  esac
done

FRAMES="frames"
OUT="out"
mkdir -p "$OUT"

echo "==> Rendering frames at ${FPS}fps"
node render.mjs --fps "$FPS" --out "$FRAMES"

# Encoding lives in encode.sh so build.sh and patch-frames.sh can never
# drift apart on codec settings.
./encode.sh "$FRAMES" "$OUT" "$FPS"

if [[ "$INSTALL" == "1" ]]; then
  echo "==> Installing into site/assets"
  cp "$OUT/demo.mp4"   ../site/assets/demo.mp4
  cp "$OUT/demo.webm"  ../site/assets/demo.webm
  cp "$OUT/poster.jpg" ../site/assets/demo-poster.jpg
fi

echo
ls -lh "$OUT"
echo "Done."
