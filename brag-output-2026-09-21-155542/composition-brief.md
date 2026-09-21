# Hyperframes Composition Brief: AloeNotch

## Objective
A launch film for AloeNotch — a free, open-source macOS app that turns the
MacBook notch into a Dynamic Island.

## Output
- Composition directory: `composition/`
- Rendered video: `brag.mp4`
- Format: landscape — 1920x1080
- Duration: 23.0 seconds

## Source Material
- Project root: `/Users/cadeg/Desktop/Open Notch`
- Primary files read: `site/index.html`, `site/style.css`,
  `OpenNotch/Notch/NotchGeometry.swift`, `OpenNotch/Design/Theme.swift`,
  `video/clips/clips.js`
- Product name: AloeNotch
- Strongest claims: "Your notch just woke up." / "Free, without the asterisk."

**No footage.** Everything on screen is drawn in the composition and driven by
a per-frame director, because the previous cut was limited by clips framed for
a 280px website card and could not survive a camera move. The panel is rebuilt
from the app's own constants:

| Value | Source | Used as |
|---|---|---|
| notch 200x32pt | `NotchGeometry.swift` | the collapsed strip |
| media wing 46pt, activity wing 64pt | `NotchMetrics` | peek widths |
| expanded 680x208pt | `expandedWidth` / `PanelLayout.height` | the open panel |
| radius 26pt / 10pt | `Metrics.panelRadius` / `.collapsedRadius` | the morph |
| expand 0.40s, bounce 0.10 | `Motion.expand` | every opening |
| collapse 0.32s, bounce 0 | `Motion.collapse` | every closing |

Authored at 1pt = 2px so the camera can push to 2.55x and still be vector-crisp.

- Copy that must appear verbatim:
  - "Your Mac has a notch." / "It has never done anything."
  - "Your notch just woke up."
  - "A timer that lives in the notch."
  - "Your last 24 copies." / "Never written to disk."
  - "Open it without the mouse."
  - "The good ones cost $15 to $25." / "This one doesn't."
  - "aloenotch.com"; "1.6 MB", "37 MB", "<1% of a core", "MIT"

## Creative Direction
- Tone preset: `cinematic`
- Creative direction: a hardware keynote for a 1.6 MB app
- Interpretation: wide shots, big type, long holds, real camera moves. The
  claims stay literally true — the treatment is what is oversized. The joke is
  never stated; it is the distance between the gravity and the four megabytes.
- Hook: an extreme close-up on a dead notch, pushing in, under two lines.
- Outro: "This one doesn't." then the wordmark, and nothing else.
- Avoid: generic SaaS language, abstract filler, naming competitors, any riser
  or swell that tips the gravity into parody.

## Visual Identity
- Background `#050507`; accent `#73bfff`; text `#f5f5f7`
- Hero gradient `linear-gradient(90deg, #73bfff, #b58cff 70%)`
- Panel pure `#000`; artwork accent `#b072ff` for the ambient glow
- Font: the system stack — it is a macOS app

## Storyboard
`brag-plan.md` is the creative contract.

1. The dead notch — 3.6s — extreme close-up, two hook lines.
2. The morph — 4.6s — the strip opens on the real spring; camera pulls back.
3. One object, three states — 7.0s — timer takeover, clipboard copy, ⌃⌥N.
4. The numbers — 3.4s — camera retreats; four figures on the beat grid.
5. The price — 4.4s — type only, then the wordmark.

## Audio
- Role: cinematic support — one lift, no celebration.
- Music: `assets/music/happy-beats-business-moves-vol-12-...mp3` (109.96 BPM).
- Treatment: 0.14 under the close-up, 0.44 from the morph, duck to 0.20 under
  the price line, 0.38 for the wordmark, fade to 0. Implemented as a
  `data-automation` volume lane.
- Cue guidance: strong cues 8.74s, 13.11s, 18.56s; beat grid 15.84 / 16.38 /
  16.93 / 17.47 for the four numbers.
- Audio-reactive: the ambient glow's spread and opacity follow per-frame bass
  and overall energy. Extraction is `tools/extract-audio.py` — ffmpeg plus the
  standard library, because the bundled extractor needs numpy and numpy is not
  installed here.
- SFX: four cues only — `morph-swell.ogg` on the morph, `click.ogg` on the
  copy, `keypress.wav` on ⌃⌥N, `payoff.ogg` on the last line. All four are
  low-high-frequency-risk picks from the skill's own analysis.
- Restraint rule: nothing on the hook, nothing on a camera move, nothing over
  the wordmark.

## Hyperframes Instructions
`/brag` workflow, not the generic promo route. Gate on `npx hyperframes check`
with zero errors before render.
