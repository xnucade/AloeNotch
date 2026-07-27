#!/usr/bin/env bash
# Build a social cut: the demo video plus a UI sound bed.
#
# The site keeps the silent demo.mp4 — it autoplays muted there, so audio would
# never be heard and would only cost bandwidth. These versions are for YouTube,
# X, and Reddit, where sound actually plays.
#
#   ./social.sh [variant]
#
#   ./social.sh              # → out/demo-social-kenney.mp4
#   ./social.sh pixabay      # → out/demo-social-pixabay.mp4
#
# Requires out/demo.mp4 from build.sh. Rebuilds the sound bed each run so the
# audio always matches the current cue list. Never touches site/assets.
set -euo pipefail

cd "$(dirname "$0")"

VARIANT="${1:-kenney}"

if [[ ! -f out/demo.mp4 ]]; then
  echo "out/demo.mp4 not found — run ./build.sh first." >&2
  exit 1
fi

echo "==> Building SFX bed"
./sfx.sh "$VARIANT"

echo "==> Muxing"
# -shortest guards against the wav and the video drifting apart in length.
# AAC-LC at 192k stereo: every platform re-encodes anyway, so the goal is to
# hand them something clean rather than something small.
ffmpeg -y -loglevel error -stats \
  -i out/demo.mp4 -i "out/sfx-$VARIANT.wav" \
  -map 0:v:0 -map 1:a:0 \
  -c:v copy \
  -c:a aac -b:a 192k -ar 48000 -ac 2 \
  -movflags +faststart -shortest \
  "out/demo-social-$VARIANT.mp4"

echo
ffprobe -v error -show_entries format=duration \
        -show_entries stream=codec_type,codec_name,channels,sample_rate \
        -of default=noprint_wrappers=1 "out/demo-social-$VARIANT.mp4"
ls -lh "out/demo-social-$VARIANT.mp4"
echo "Done — out/demo-social-$VARIANT.mp4"
