# Pixabay sound set — shopping list

This folder is scaffolded but **empty of audio**. Pixabay's search pages sit
behind a Cloudflare bot challenge and their public API covers images and video
only, so the files have to be downloaded by hand.

That turns out to be the better division of labour anyway: picking sounds is a
listening job, and you can hear them.

## How

1. Go to <https://pixabay.com/sound-effects/> and search the terms below.
2. Download the ones you like.
3. Rename to the filename in the first column and drop it in this folder.
4. Run `./social.sh pixabay` from `video/`.

You don't need all eleven to try it — but every file named in `cues.txt` must
exist or the build stops with which one is missing. To test early, point
several cues at the same file.

## What each cue needs

| Filename | Used for | Character to look for | Search terms |
|---|---|---|---|
| `open.mp3` | Panel springs open (8.4s) | Soft rising swell, ~0.3–0.6s. The hero sound — worth the most time. Not a click; something with lift. | `ui open`, `whoosh soft`, `interface open`, `pop up` |
| `track.mp3` | Track change (23.6, 26.4s) | Very short, very quiet blip. Should almost pass unnoticed. | `ui tap`, `soft click`, `subtle click` |
| `drop-1/2/3.mp3` | Files land on shelf (31.1, 32.9, 34.5s) | Soft landing with a little body — a "tock", not a beep. Three slightly different ones is ideal. | `ui drop`, `soft thud`, `pop`, `bubble pop` |
| `drag.mp3` | Stack drags out (36.65s) | Short airy whoosh, ~0.4–1.0s. | `whoosh short`, `swipe`, `swoosh ui` |
| `close.mp3` | Panel collapses (48.0s) | The counterpart to `open` — falling rather than rising. Ideally from the same pack so they match. | `ui close`, `whoosh down`, `interface close` |
| `tick-vol.mp3` | Volume steps ×3 (49.9–50.9s) | Tight, dry, quiet tick. Plays three times half a second apart, so anything with a tail will smear. | `ui tick`, `click short`, `toggle` |
| `tick-bright.mp3` | Brightness steps ×3 (52.8–53.8s) | Same idea, noticeably brighter or higher, so the two groups read as different actions. | `ui tick high`, `blip`, `select` |
| `vanish.mp3` | Strip goes invisible (56.4s) | Quiet, soft, conclusive. Understated — the picture is showing *nothing happening*. | `ui close soft`, `power down soft`, `fade out ui` |
| `endcard.mp3` | End card (60.35s) | The one sound allowed some length and warmth. A resolved chime or soft bell, 1–3s. | `notification soft`, `chime`, `success`, `logo` |

## Tuning after the first build

- **Overall too loud/quiet:** `./sfx.sh pixabay -12` — it's a peak target in dBFS.
- **One cue out of balance:** change its `gain` in `cues.txt` and rebuild.
- **A cue has a long tail you don't want:** add `atrim=0:0.4` as the extra
  filter column.
- **Already has a natural tail:** delete the `aecho=...` from the endcard line.

## Licence

Pixabay's Content License allows commercial use with no attribution, but it is
**not** CC0 and it does carry restrictions. Check the terms for anything you
download: <https://pixabay.com/service/license-summary/>

Keep a note here of what you used and from where, so provenance is traceable
later:

```
open.mp3      — <url>
drop-1.mp3    — <url>
...
```
