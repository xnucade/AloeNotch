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

echo "==> Encoding H.264"
# yuv420p + even dimensions for universal playback; faststart so the site can
# begin playing before the whole file arrives.
ffmpeg -y -loglevel error -stats \
  -framerate "$FPS" -i "$FRAMES/f_%06d.png" \
  -vf "scale=1920:1080:flags=lanczos,format=yuv420p" \
  -c:v libx264 -preset slow -crf 20 -pix_fmt yuv420p \
  -movflags +faststart -r "$FPS" \
  "$OUT/demo.mp4"

echo "==> Encoding VP9"
ffmpeg -y -loglevel error -stats \
  -framerate "$FPS" -i "$FRAMES/f_%06d.png" \
  -vf "scale=1920:1080:flags=lanczos,format=yuv420p" \
  -c:v libvpx-vp9 -crf 34 -b:v 0 -row-mt 1 -deadline good -cpu-used 2 \
  -r "$FPS" \
  "$OUT/demo.webm"

echo "==> Poster frame"
# A frame from the reveal, where the panel is open and lit.
ffmpeg -y -loglevel error -ss 16 -i "$OUT/demo.mp4" -frames:v 1 -q:v 2 "$OUT/poster.jpg"

if [[ "$INSTALL" == "1" ]]; then
  echo "==> Installing into site/assets"
  cp "$OUT/demo.mp4"   ../site/assets/demo.mp4
  cp "$OUT/demo.webm"  ../site/assets/demo.webm
  cp "$OUT/poster.jpg" ../site/assets/demo-poster.jpg
fi

echo
ls -lh "$OUT"
echo "Done."
