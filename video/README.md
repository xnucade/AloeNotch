# AloeNotch demo video

The 66-second product video on the site is **rendered, not screen-recorded**.
The notch UI is rebuilt in HTML/CSS from the real SwiftUI source, animated on a
deterministic timeline, rasterised frame-by-frame in headless Chromium, and
encoded with ffmpeg.

Why rendered rather than captured:

- Every beat is directable — the panel expands, a HUD fires, three files land
  on the shelf, all exactly on cue. Some of these are near-impossible to catch
  cleanly in a live recording.
- It re-renders in minutes when the app changes, with no re-shoot.
- It depends on no copyrighted material: the cover art, wallpaper, track names,
  and artist names are all synthetic. A screen recording of real Music playback
  would put someone's album art on the marketing site.

The trade-off: it is a **recreation**, so it can drift from the shipping app.
Metrics are copied from the Swift source and annotated with their origin —
if the panel's geometry or animation curves change, update `timeline.js` and
`demo.html` to match.

## Building

```sh
npm install
npx puppeteer browsers install chrome     # one-time
./build.sh                                # render + encode + install into site/assets
```

Options:

```sh
./build.sh --fps 30       # quicker draft
./build.sh --no-install   # leave site/assets alone
```

Outputs land in `out/` and, unless `--no-install`, are copied to
`site/assets/demo.mp4`, `demo.webm`, and `demo-poster.jpg`.

> **The encoded video is gitignored.** Like the DMG, it is several MB of
> reproducible binary that reaches users only through the deployed site. A
> fresh clone therefore has no `demo.mp4` / `demo.webm` — run `./build.sh`
> here **before** `wrangler deploy`, or the site ships without its demo.
> (`demo-poster.jpg` is tracked, so the frame at least shows a still.)

## The social cut (with sound)

The site's video is **silent on purpose** — it autoplays, browsers only permit
that when muted, so audio there would never be heard and would only cost
bandwidth. For YouTube, X, and Reddit, where sound actually plays, there is a
separate cut:

```sh
./social.sh              # → out/demo-social-kenney.mp4  (H.264 + AAC)
./social.sh pixabay      # a different sound set
```

It reuses `out/demo.mp4`, so it does not re-render frames. `site/assets/` is
never touched.

### Sound sets

A sound set is just a directory under `sfx/` holding audio files and a
`cues.txt`. To try different sounds, make `sfx/<name>/`, drop files in, copy a
`cues.txt` across and point it at the new filenames — no script changes.

- **`kenney`** — built and working. Kenney's
  [Interface Sounds](https://kenney.nl/assets/interface-sounds), **CC0**: free
  commercially, attribution not required (crediting kenney.nl is appreciated).
  Only the dozen files used are vendored, with the pack's licence text.
- **`pixabay`** — scaffolded but empty. Pixabay is behind a Cloudflare bot
  challenge and their API has no audio endpoint, so those files must be
  downloaded by hand. `sfx/pixabay/README.md` lists exactly what to fetch,
  what each cue should sound like, and what to name it.

A missing file fails the build immediately, naming the cue, rather than
silently producing a bed with a hole in it.

The audio is sparse UI sound rather than a music bed: the panel opening, each
file landing on the shelf, the HUD steps, the end card. Silence between cues is
intentional.

`sfx.sh` mixes a set into `out/sfx-<variant>.wav`:

```sh
./sfx.sh                 # kenney, -7 dBFS peak
./sfx.sh kenney -12      # quieter pass
./sfx.sh pixabay
```

Each set's cue list is `sfx/<variant>/cues.txt` — one line per cue,
`time file gain pan` plus an optional extra ffmpeg filter. Swapping a sound is
a one-line edit.

**`timeline.js` is the only source of truth for cue times.** It exports
`window.__CUES`; after changing any scene timing, run:

```sh
node sync-cues.mjs        # rewrites every sfx/<set>/cues.txt
```

Never hand-edit the timestamps. They used to be duplicated across three files,
which is exactly how audio silently drifts off the picture. `sync-cues.mjs`
refuses to touch a set whose cue count no longer matches the timeline rather
than guessing which line is which.

Verify with:

```sh
ffmpeg -i out/sfx-kenney.wav -af silencedetect=n=-50dB:d=0.08 -f null -
```

Each `silence_start + silence_duration` is a cue onset; they should match the
times in the cue list.

Level targets -7 dBFS peak, which is louder than "subtle" suggests and
deliberate: the file is mostly silence, so its integrated loudness sits near
-20 LUFS, well under the ~-14 platforms normalise to — and YouTube and X only
turn loud audio *down*, never quiet audio up. A conservative peak just means
viewers on phone speakers hear nothing.

### Iterating

`build.sh` renders thousands of frames. While working on the timeline, use the
probe instead — it renders single timestamps in a couple of seconds and reports
any page errors:

```sh
node probe.mjs 2 9 16 26 33 42 50 58 62     # → out/probe/
```

## How it works

`demo.html` holds the stage: a virtual 1512x982 MacBook screen (wallpaper, menu
bar, notch panel) inside `#camera`, plus an `#overlay` carrying the opening
statement, captions, and end card. It contains **static styles only** — no CSS
transitions or animations.

The film is deliberately **screen-true**: no perspective tilt, no simulated
device body, no film grain, no vignette. The subject is the software, shown at
its real geometry, and every one of those flourishes would put a layer between
the viewer and it. Restraint is the whole design:

- **The opening statement gets the frame to itself.** Two lines of white type
  on true black, before any product is shown. The desktop is not revealed until
  the type has left.
- **One typographic voice.** A single headline size, a single supporting size,
  a single position, for the entire film. Per-shot type sizes read as
  indecision.
- **Words resolve rather than appear.** Each word clears from a 7px blur over
  18px of travel, 40ms apart — enough that a line settles into place, not so
  much that the reader notices the mechanism.
- **The camera is all but locked.** It pushes in and settles. There is a
  deliberate whisper of movement — roughly 4px over eight seconds, plus a
  breath of scale — because held perfectly still for seconds at a time the
  frame reads as a screenshot rather than a shot. Both are clamped so they can
  never letterbox: the breath only scales *up* (at `s = 1.00` the screen
  exactly covers the frame, so any shrink exposes the edges), and lateral
  drift is capped by the real horizontal headroom at the current zoom, which
  means a wide shot gets none at all.
- **The desktop is dithered, with grain sized to survive the encoder.** A
  smooth dark-blue gradient is precisely where 8-bit banding shows: the
  wallpaper measured as flat plateaus stepping one or two levels across
  hundreds of pixels, and H.264 exaggerates it. Two hard-won specifics:
  1-pixel grain at 3% is erased by the quantizer at any sane CRF — the fix
  only reaches the viewer as ~2px grain (the tile upscaled via
  `background-size`) alongside `-crf 18 -x264-params aq-mode=3`, which biases
  bits toward dark regions. And when judging it, magnify and *look*: the
  unique-colour count barely moves after encoding, but the stair-step contours
  visibly dissolve into decorrelated texture, which is the thing that matters.
  Static, never animated — moving dither crawls and costs bitrate.
- **The desktop dims as the camera closes in**, so the panel carries the frame.
  A brightness fall-off, not a lens blur — nothing here is genuinely out of
  focus, and faked bokeh on a screen recreation is a lie the eye can spot.

`timeline.js` exposes `window.__render(t)`, which paints the frame for time `t`
as a pure function. Rendering the same `t` twice must produce identical pixels;
that is what lets `render.mjs` step frames one at a time instead of recording
in real time. Anything time-varying — panel size, glow color, scrubber
position, cursor, captions, camera — is derived from `t`.

Motion curves mirror the app's own animations, including a reimplementation of
SwiftUI's `.smooth(duration:extraBounce:)` spring, so the panel opens on screen
the way it opens on a real machine.

### Two constraints worth knowing

**The camera must never letterbox.** The screen's top edge is pinned to the
frame's top edge (the notch lives at y=0), and the zoom multiplier is clamped
to `>= 1.0`, below which the virtual screen stops covering the 1920x1080 frame
and black bars appear at the sides. `s = 1.00` maps the screen exactly onto the
frame — use it for wide shots so the menu bar isn't cropped.

**Scope your CSS class names.** `demo.html` styles both the notch UI and the
end card in one sheet. An unscoped `.meta { flex: 1 }` for the media column
silently matched the end card's spec line and made it swallow 600px of layout.

## Shot list

| Time | Beat |
|------|------|
| 0:00 | Opening statement on black — "Your Mac has a notch." / "It has never done anything." |
| 0:05 | Black dissolves: the desktop, the notch sitting there doing nothing |
| 0:08 | Cursor reaches the notch — **the panel opens** |
| 0:13 | Now playing: artwork, metadata, scrub and seek |
| 0:22 | Ambient glow shifts colour across three tracks |
| 0:29 | Drop shelf: three files land, then drag all out |
| 0:39 | Calendar week strip, weather and battery pills |
| 0:47 | Panel collapses; volume and brightness HUDs |
| 0:55 | Collapses to nothing — invisible when idle |
| 1:00 | End card |
| 1:00 | End card |

Copy for each beat lives in the `CAPTIONS` array in `timeline.js`; scene
boundaries are the `S` object at the top of the same file.
