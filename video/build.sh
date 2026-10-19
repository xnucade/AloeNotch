#!/usr/bin/env bash
# Build the AloeNotch demo video: render frames, then encode.
#
#   ./build.sh              # full 60fps render + encode
#   ./build.sh --fps 30     # faster draft
#
# Outputs (video/out/ only — the site no longer embeds this film; social.sh
# builds the social cut from out/demo.mp4):
#   out/demo.mp4     H.264, faststart, ~1080p
#   out/demo.webm    VP9, smaller
#   out/poster.jpg   first meaningful frame
set -euo pipefail

cd "$(dirname "$0")"

FPS=60
for ((i = 1; i <= $#; i++)); do
  case "${!i}" in
    --fps) j=$((i + 1)); FPS="${!j}" ;;
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

echo
ls -lh "$OUT"
echo "Done."
