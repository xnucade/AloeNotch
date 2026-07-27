#!/usr/bin/env bash
# Re-render a time range into an existing frame sequence, then re-encode.
#
#   ./patch-frames.sh 0 1.4        # just the opening
#   ./patch-frames.sh 73 74 0 1.4  # several ranges, pairs of from/to
#
# Useful when a change only affects part of the timeline — re-rendering 4,400
# frames to fix one second is wasteful. Frames are a pure function of t, so a
# patched sequence is identical to a full re-render of the same source.
#
# Ranges must be given as from/to pairs in seconds.
set -euo pipefail

cd "$(dirname "$0")"

FPS=60
[[ -d frames ]] || { echo "no frames/ to patch — run ./build.sh first" >&2; exit 1; }
(( $# >= 2 && $# % 2 == 0 )) || { echo "usage: $0 <from> <to> [<from> <to> ...]" >&2; exit 1; }

while (( $# )); do
  from=$1; to=$2; shift 2
  echo "==> Re-rendering ${from}s → ${to}s"
  node render.mjs --fps "$FPS" --from "$from" --to "$to" --out frames --resume
done

./encode.sh frames out "$FPS"

cp out/demo.mp4 ../site/assets/demo.mp4
cp out/demo.webm ../site/assets/demo.webm
cp out/poster.jpg ../site/assets/demo-poster.jpg

echo
ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1 out/demo.mp4
ls -lh out/demo.mp4 out/demo.webm
echo "Done."
