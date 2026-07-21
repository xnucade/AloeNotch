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

### Iterating

`build.sh` renders thousands of frames. While working on the timeline, use the
probe instead — it renders single timestamps in a couple of seconds and reports
any page errors:

```sh
node probe.mjs 2 9 16 26 33 42 50 58 62     # → out/probe/
```

## How it works

`demo.html` holds the stage: a virtual 1512x982 MacBook screen (wallpaper, menu
bar, notch panel) plus overlay captions and the end card. It contains **static
styles only** — no CSS transitions or animations.

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
| 0:00 | Cold open — the notch sits there doing nothing |
| 0:06 | Cursor arrives, panel springs open, title |
| 0:13 | Now playing: artwork, metadata, scrub and seek |
| 0:22 | Ambient glow shifts color across three tracks |
| 0:29 | Drop shelf: three files land, then drag all out |
| 0:39 | Calendar week strip, weather and battery pills |
| 0:47 | Panel collapses; volume and brightness HUDs |
| 0:55 | Collapses to nothing — invisible when idle |
| 1:00 | End card |

Copy for each beat lives in the `CAPTIONS` array in `timeline.js`; scene
boundaries are the `S` object at the top of the same file.
