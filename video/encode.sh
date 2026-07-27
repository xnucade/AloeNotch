#!/usr/bin/env bash
# The encode — single source of truth.
#
#   ./encode.sh [frames_dir] [out_dir] [fps]
#
# Called by both build.sh (full render) and patch-frames.sh (partial re-render).
# These settings used to be copy-pasted into both, which silently produced two
# different-looking films: a partial re-render came back at CRF 20 with no
# adaptive quantisation and quietly undid the dark-scene banding work, dropping
# the file from 8.9 MB to 5.7 MB. Change the encode here and nowhere else.
#
# Why these values:
#   crf 18            the film is almost entirely dark blues and near-blacks,
#                     where the default CRF leaves visible contouring
#   x264 aq-mode=3    biases bits toward dark regions specifically
#   vp9 crf 30        matched perceptual target for the WebM
#   yuv420p           universal playback
#   +faststart        the site can begin playing before the file finishes
set -euo pipefail

cd "$(dirname "$0")"

FRAMES="${1:-frames}"
OUT="${2:-out}"
FPS="${3:-60}"
SCALE="scale=1920:1080:flags=lanczos,format=yuv420p"

mkdir -p "$OUT"

echo "==> Encoding H.264"
ffmpeg -y -loglevel error -stats \
  -framerate "$FPS" -i "$FRAMES/f_%06d.png" \
  -vf "$SCALE" \
  -c:v libx264 -preset slow -crf 18 -x264-params aq-mode=3 -pix_fmt yuv420p \
  -movflags +faststart -r "$FPS" \
  "$OUT/demo.mp4"

echo "==> Encoding VP9"
ffmpeg -y -loglevel error -stats \
  -framerate "$FPS" -i "$FRAMES/f_%06d.png" \
  -vf "$SCALE" \
  -c:v libvpx-vp9 -crf 30 -b:v 0 -row-mt 1 -deadline good -cpu-used 2 \
  -r "$FPS" \
  "$OUT/demo.webm"

echo "==> Poster frame"
# From the reveal, where the panel is open and lit.
ffmpeg -y -loglevel error -ss 16 -i "$OUT/demo.mp4" -frames:v 1 -q:v 2 "$OUT/poster.jpg"
