#!/usr/bin/env bash
# Build a UI sound bed for the demo video.
#
#   ./sfx.sh [variant] [peak_dbfs]
#
#   ./sfx.sh                 # kenney set, -7 dBFS  → out/sfx-kenney.wav
#   ./sfx.sh pixabay         # a different sound set
#   ./sfx.sh kenney -12      # quieter pass
#
# A "variant" is just a directory under sfx/ containing audio files and a
# cues.txt. To try a new set of sounds, make sfx/<name>/, drop the files in,
# copy a cues.txt across and point it at the new filenames. Nothing else
# changes.
#
# The score is deliberately sparse. This is a product demo, not a trailer:
# each sound marks something the UI actually did, and the silence between cues
# is intentional rather than a gap to fill.
#
# CUE TIMES MIRROR timeline.js. If a scene moves there, move it in cues.txt, or
# the audio drifts off the picture. Verify after any change with:
#   ffmpeg -i out/sfx-<variant>.wav -af silencedetect=n=-50dB:d=0.08 -f null -
# Each `silence_start + silence_duration` should equal a cue time.
set -euo pipefail

cd "$(dirname "$0")"

VARIANT="${1:-kenney}"
PEAK_DB="${2:--7}"
# Match the rendered video exactly. Read it from the encode rather than
# repeating the number here — a stale duration silently truncates the bed or
# pads it with silence.
if [[ -f out/demo.mp4 ]]; then
  DURATION=$(ffprobe -v error -show_entries format=duration -of csv=p=0 out/demo.mp4)
else
  DURATION=74     # timeline.js DURATION, for building audio before the video
fi
DIR="sfx/$VARIANT"
CUEFILE="$DIR/cues.txt"

[[ -d "$DIR" ]]     || { echo "no such sound set: $DIR" >&2; exit 1; }
[[ -f "$CUEFILE" ]] || { echo "missing $CUEFILE" >&2; exit 1; }
mkdir -p out

# --- Assemble ---------------------------------------------------------------
# Each cue becomes its own ffmpeg input, so reusing one sample at several times
# needs no stream splitting.
inputs=(); filters=(); labels=""
i=0
while read -r t file gain pan extra; do
  [[ -z "${t:-}" || "$t" == \#* ]] && continue
  [[ -f "$DIR/$file" ]] || { echo "missing $DIR/$file (cue at ${t}s)" >&2; exit 1; }

  ms=$(printf '%.0f' "$(bc -l <<< "$t * 1000")")
  inputs+=(-i "$DIR/$file")

  # Equal-power pan into stereo.
  gl=$(bc -l <<< "sqrt((1 - $pan) / 2)")
  gr=$(bc -l <<< "sqrt((1 + $pan) / 2)")

  # Strip any leading silence in the source first, so the cue lands on its
  # visual frame regardless of how much lead-in the file happens to carry.
  # Downloaded samples vary from 0 to ~150ms of silence before the transient;
  # without this, a cue that reads correctly in the file plays late on screen.
  chain="[$i:a]aformat=sample_fmts=fltp:sample_rates=48000:channel_layouts=stereo"
  chain="$chain,silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0"
  [[ -n "${extra:-}" ]] && chain="$chain,$extra"
  chain="$chain,volume=$gain,pan=stereo|c0=${gl}*c0|c1=${gr}*c1,adelay=${ms}:all=1[a$i]"
  filters+=("$chain")
  labels="${labels}[a$i]"
  i=$((i + 1))
done < "$CUEFILE"

(( i > 0 )) || { echo "no cues found in $CUEFILE" >&2; exit 1; }

graph="$(IFS=';'; echo "${filters[*]}");${labels}amix=inputs=$i:normalize=0:duration=longest[mix];[mix]apad=whole_dur=$DURATION,atrim=0:$DURATION,afade=t=in:st=0:d=0.05,afade=t=out:st=$(bc -l <<< "$DURATION - 0.05"):d=0.05[out]"

echo "==> $VARIANT: mixing $i cues"
ffmpeg -y -loglevel error "${inputs[@]}" \
  -filter_complex "$graph" -map "[out]" \
  -c:a pcm_s16le -ar 48000 -ac 2 "out/sfx-$VARIANT-raw.wav"

# --- Normalise to the target peak -------------------------------------------
# Two-pass: measure, then apply one clean gain. No limiter — that would squash
# the transients that make these read as interface sounds.
measured=$(ffmpeg -v info -i "out/sfx-$VARIANT-raw.wav" -af volumedetect -f null - 2>&1 \
           | grep -o 'max_volume: -\?[0-9.]*' | awk '{print $2}')
adjust=$(bc -l <<< "$PEAK_DB - ($measured)")
echo "==> peak ${measured} dBFS → applying ${adjust} dB (target ${PEAK_DB})"

ffmpeg -y -loglevel error -i "out/sfx-$VARIANT-raw.wav" -af "volume=${adjust}dB" \
  -c:a pcm_s16le -ar 48000 -ac 2 "out/sfx-$VARIANT.wav"
rm -f "out/sfx-$VARIANT-raw.wav"

echo "out/sfx-$VARIANT.wav  ${DURATION}s  48kHz stereo  peak ${PEAK_DB} dBFS"
