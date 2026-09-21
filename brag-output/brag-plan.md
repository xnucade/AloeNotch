# Brag Plan: AloeNotch

## What is this app?
AloeNotch turns the dead black bar at the top of a MacBook into a Dynamic
Island — now playing, a drop shelf, a timer, clipboard history, a keyboard
shortcut — and it is free, open source, and 1.6 MB.

## The angle
Every MacBook owner has a notch. None of them have ever used it for anything.
AloeNotch's own site opens on exactly that observation, and the whole product
is the answer to it. The video is that argument in twenty seconds: the notch is
dead, the notch wakes up, here is what it does, and it costs nothing while the
good alternatives cost $15–25.

The video is not a recreation. The product footage is the product: ten clips
already exist in `site/assets/clips/`, rendered frame-by-frame from the app's
real geometry and spring curves. They get re-encoded at full resolution and
placed directly in the composition.

## Hook (first 2-3 seconds)
The project's own line, which it has already tested on its site:
**"Your Mac has a notch."** — held over a real, inert black strip at the top of
an empty screen — then **"It has never done anything."** Nothing moves. The
stillness is the hook: the viewer is looking at their own machine.

## Key moments (the middle)
- The strip **morphs** open into the full panel with a track playing and the
  artwork's colour bleeding out around the edge. One continuous shape, not a
  cut — this is the thing the app is actually good at.
- **The timer taking over the collapsed strip**, counting down in the notch
  itself while the ring fills in the panel.
- **A clipboard row being clicked and confirming "Copied"**, with a real cursor.
- **⌃⌥N pressed, and the panel opening from the keyboard** with no pointer
  anywhere on screen.

## Outro / punchline
"The good ones cost $15 to $25." Hold. "This one doesn't." Then the wordmark,
`aloenotch.com`, and the four numbers that make the claim land: 1.6 MB · 37 MB ·
<1% of a core · MIT.

## User flow worth showing
Entry → key action → result, three times over, each one a real clip:
1. **Hover/keyboard → the notch opens** → the panel with media controls.
2. **Start a timer → it takes over the collapsed strip** → ring counting down.
3. **Click a clipboard row → "Copied"** → it is back on the pasteboard.

## Tone
- Preset: `polished`
- Creative direction: quiet premium product film for an app that costs nothing
- Interpretation: restraint is the argument. No exclamation marks, no swooshes,
  no feature-bullet grid. Type is mixed case and light. The product footage is
  allowed to play without a label fighting it. The only moment of force is the
  price line, and it lands by being plain.

**Deviation noted:** `polished` guidance says 3–4 scenes. This has six, because
three of them are product footage rather than copy — the scene count that
matters for restraint is the number of things the viewer has to *read*, and
that is four.

## Format: landscape — 1920x1080
## Duration: 22.3 seconds

## Visual identity (from the project)
- Background: `#050507` (site `--bg`)
- Surface: `rgba(255,255,255,0.05)` (site `--surface`)
- Accent: `#73bfff` (site `--accent`)
- Accent soft: `rgba(115,191,255,0.35)`
- Text: `#f5f5f7` (site `--text`), muted `rgba(245,245,247,0.6)`
- Hero gradient: `linear-gradient(90deg, #73bfff, #b58cff 70%)` — the site's
  treatment on the words "just woke up."
- Display + body font: system stack (`-apple-system`, SF Pro Display). No
  webfont: the product is a macOS app and the system face is the honest one.
- Strongest visual element: the panel morph with the artwork-coloured ambient
  glow tracing its edge.

## Share copy (draft)
Your Mac has a notch. It has never done anything. AloeNotch fixes that — free,
open source, 1.6 MB.

## Audio direction
- Role: warm bed, low and steady, with sparse motion-matched accents
- Music: `happy-beats-business-moves-vol-12-by-ende-dot-app.mp3` (110 BPM, the
  calmest of the bundled set and long enough to cover the cut without a loop)
- Music treatment: start at 0 under the silent hook at low volume (~0.20),
  lift to ~0.42 on the wake, hold, duck to ~0.22 under the price line so the
  words carry, return for the logo and fade out over the last 0.8s.
- Music cue guidance: preset read from
  `assets/music/cues/happy-beats-business-moves-vol-12-...music-cues.md`.
  Strong cues to target: **8.74s** (timer scene in), **13.11s** (clipboard
  "Copied"), **18.56s** (the price payoff). Beat grid for the outro stat row:
  19.66 / 20.19 / 20.75 / 21.28.
- Audio-reactive treatment: subtle. The ambient glow around the panel and the
  hero title's presence may breathe with music RMS. Nothing else. No waveform
  bars, no equalizers, no particles.
- SFX posture: sparse. At most four cues in the whole video.
- Audio-coupled moments: the morph open (one soft swell), the clipboard click
  (one interface tick), the ⌃⌥N keypress (one key sound), the price payoff
  (one dry, low announcement hit that is allowed to ring over the music).
- Restraint rule: no whoosh on every transition, no riser into the logo, no
  sound on the hook. The first three seconds are silent except the music bed.

## Music cue guidance
- Track: vol-12, 109.96 BPM, preset available.
- Strong cues: 8.74s, 13.11s, 18.56s — lock the three major reveals here.
- Beat grid for the sequential stat row: 19.66, 20.19, 20.75, 21.28.
- Restraint note: `polished`. Three locks, not ten. If a lock hurts a read,
  use natural timing.

## Storyboard

### Scene 1 — Dead weight — 3.3s
Empty near-black screen with the site's radial wash at the top. A real
collapsed notch strip hangs from the top edge, pure black, doing nothing.
Centred below it, in light mixed case: **"Your Mac has a notch."** holds ~1.3s,
then **"It has never done anything."** holds ~1.4s. No motion but a very slow
drift in the background wash.
Sequential/interaction: two lines, one after the other, each held past the
reading floor.
Audio intent: music only, low. The silence is the point.
Audio-coupled idea: none.
Music: bed at ~0.20.
Transition mood: soft → Scene 2

### Scene 2 — It wakes — 4.7s
The strip **morphs** — one continuous shape — into the full panel: artwork,
track title, scrubber, transport, and the artwork's colour glowing out past
the edge. Real product footage (`now-playing`). The hero line fades up beneath
it in the site's own gradient: **"Your notch just woke up."** held ~1.8s.
Sequential/interaction: the morph itself is the interaction.
Audio intent: the bed lifts. One soft swell under the morph.
Audio-coupled idea: single low swell on the morph; glow breathes with RMS.
Music: lift to ~0.42.
Transition mood: soft crossfade → Scene 3

### Scene 3 — The timer — 3.2s  // beat-locked 8.74s
Real footage (`timer`): the countdown takes over the collapsed strip, then the
panel opens with the ring filling. Label, lower third, one line:
**"A timer that lives in the notch."** held ~1.9s.
Sequential/interaction: strip readout → panel ring.
Audio intent: steady. No accent — the visual is already the event.
Audio-coupled idea: none.
Music: hold.
Transition mood: clean cut → Scene 4

### Scene 4 — The clipboard — 3.1s  // beat-locked 13.11s
Real footage (`clipboard`): a cursor reaches a row, clicks, and the row turns
to a green check and **Copied**. Label: **"Your last 24 copies."** held ~1.2s,
then a second, smaller line: **"Never written to disk."** held ~1.2s.
Sequential/interaction: simulated click, already in the footage.
Audio intent: one small interface tick on the click, matched to the frame.
Audio-coupled idea: interface tick at the click.
Music: hold.
Transition mood: clean cut → Scene 5

### Scene 5 — The shortcut — 3.1s
Real footage (`shortcut`): ⌃⌥N keycaps press, the panel opens, no pointer on
screen. Label: **"Open it without the mouse."** held ~1.5s.
Sequential/interaction: keypress → open.
Audio intent: one key sound on the press.
Audio-coupled idea: key tick at the keycap press.
Music: hold.
Transition mood: soft crossfade → Scene 6

### Scene 6 — The price — 4.9s  // beat-locked 18.56s
Type only, centred, the panel gone. **"The good ones cost $15 to $25."** holds
~1.5s. Then, on the strong cue, it is replaced by **"This one doesn't."** held
~1.4s. Then the AloeNotch wordmark with `aloenotch.com` beneath, and a single
quiet row of four numbers arriving on the beat grid:
**1.6 MB · 37 MB · <1% of a core · MIT**, on beats 19.66 / 20.19 /
20.75 / 21.28 — the last one holds past its beat so it can be read.
Sequential/interaction: the four numbers arrive one by one on beats 19.66 /
20.19 / 20.75 / 21.28 — non-text-heavy, short tokens, so beat spacing is fine.
Audio intent: duck the music under the two price lines so they carry, return
for the logo, one dry low hit on "This one doesn't," fade out over 0.8s.
Audio-coupled idea: single announcement hit on the payoff.
Music: duck to ~0.22, return to ~0.40, fade to 0.
Transition mood: end.

**Music mood for this video:** warm, steady, confident — never triumphant.
**Audio summary:** a low bed under a silent hook, lifting once when the notch
wakes, holding flat through three product moments with three small
motion-matched accents, ducking so the price line can be heard plainly, and
fading out under the wordmark.
