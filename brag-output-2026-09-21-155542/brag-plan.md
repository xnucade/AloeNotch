# Brag Plan: AloeNotch

## What is this app?
AloeNotch turns the dead black bar at the top of a MacBook into a Dynamic
Island — now playing, a drop shelf, a timer, clipboard history, a keyboard
shortcut — free, open source, and 1.6 MB to download.

## The angle
**A hardware keynote for a 1.6 MB app.**

Treat a free menu-bar utility with the gravity Apple reserves for silicon: an
extreme close-up on a dead piece of hardware, a slow push in, big type, one
object that never cuts away. The joke is never stated — it is the distance
between the treatment and the fact that the whole thing is four megabytes and
costs nothing. The last line is the only wink, and it is delivered flat.

**Everything is drawn natively in the composition.** No footage. The panel is
rebuilt in HTML/CSS from the app's own constants — NotchGeometry.swift for the
geometry, Theme.swift for the spring curves — and driven by a per-frame
director, so the camera can push, pull and reframe against vector-crisp type at
1920 instead of scaling a clip that was framed for a 280px website card.

## Hook (first 2-3 seconds)
An extreme close-up of the collapsed notch. It fills the frame, pure black,
doing nothing, while the camera pushes in almost imperceptibly. Then: **"Your
Mac has a notch."** — hold — **"It has never done anything."** The viewer is
looking at their own machine.

## Key moments (the middle)
- **The morph.** On the strongest cue in the window, the strip opens into the
  full panel on the app's real spring — 0.40s, 0.10 extra bounce — while the
  camera pulls back to reveal it. One shape the whole way.
- **One object, three states.** The panel never cuts away. It reshapes from
  now-playing to a countdown taking over the strip, to the clipboard, to the
  keyboard shortcut opening it with no pointer on screen. This continuity *is*
  the product's signature; cutting between clips is what throws it away.
- **The pull-back.** The camera retreats until the panel is a small bright
  object in a large dark frame, and the four numbers arrive underneath it.

## Outro / punchline
"The good ones cost $15 to $25." Hold. "This one doesn't." Then the wordmark,
aloenotch.com, and nothing else.

## User flow worth showing
Entry → key action → result, as one continuous object:
1. **The notch opens** → the panel, playing something.
2. **A timer starts** → it takes over the collapsed strip → the ring counts down.
3. **⌃⌥N is pressed** → the panel opens with no pointer anywhere.

## Tone
- Preset: `cinematic`
- Creative direction: a hardware keynote for a 1.6 MB app
- Interpretation: wide shots, big type, long holds, real camera moves. The
  claims stay literally true — the treatment is what is oversized, not the
  copy. No riser, no whoosh, no triumphal swell. Restraint in the sound is what
  keeps the grandeur from tipping into parody.

## Format: landscape — 1920x1080
## Duration: 23.0 seconds

## Visual identity (from the project)
- Background: `#050507` (site `--bg`)
- Accent: `#73bfff` (site `--accent`); soft `rgba(115,191,255,0.35)`
- Text: `#f5f5f7`; muted `rgba(245,245,247,0.6)`; faint `rgba(245,245,247,0.38)`
- Hero gradient: `linear-gradient(90deg, #73bfff, #b58cff 70%)`
- Panel: pure `#000`, radius 26pt open / 10pt collapsed, continuous corners
- Geometry (NotchGeometry.swift): notch 200x32pt, media wing 46pt, activity
  wings 46/64/84pt, expanded 680x208pt
- Springs (Theme.swift): expand 0.40s / bounce 0.10; collapse 0.32s / bounce 0
- Font: the system stack. It is a macOS app; the system face is the honest one.
- Strongest visual element: the morph, with the artwork's colour bleeding out
  past the panel edge.

## Share copy (draft)
Your Mac has a notch. It has never done anything. AloeNotch fixes that, in
1.6 MB, for free.

## Audio direction
- Role: cinematic support — a low bed that lifts once and never celebrates.
- Music: `happy-beats-business-moves-vol-12-by-ende-dot-app.mp3` (109.96 BPM).
- Music treatment: near-silent under the close-up (~0.14), lift to ~0.44 on the
  morph, hold flat across the three states, duck to ~0.20 under the price line,
  return to ~0.38 for the wordmark, fade out over the last second.
- Music cue guidance: preset read from the bundled cue file. Strong cues to
  target: **8.74s** (the timer state), **13.11s** (the shortcut state),
  **18.56s** (the price payoff). Beat grid for the four numbers: 15.84 / 16.38 /
  16.93 / 17.47.
- Audio-reactive treatment: subtle. The ambient glow around the panel breathes
  with bass; the panel's own presence responds to overall energy. Nothing else.
  No bars, no particles, no strobing.
- SFX posture: four cues in twenty-three seconds.
- Audio-coupled moments: one warm swell on the morph; one interface tick on the
  clipboard copy; one key sound on ⌃⌥N; one dry low hit on the payoff.
- Restraint rule: nothing on the hook, nothing on the camera pull-back, and no
  sound layered over the wordmark.

## Music cue guidance
- Track: vol-12, 109.96 BPM, preset available.
- Strong cues: 8.74s, 13.11s, 18.56s — three locks, no more.
- Beat grid for the number row: 15.84, 16.38, 16.93, 17.47.
- Restraint note: `cinematic` earns big motion, not dense rhythm. If a lock
  fights a read, use natural timing.

## Storyboard

### Scene 1 — The dead notch — 3.6s
Extreme close-up: the collapsed strip fills most of the frame, pure black
against the site's blue-grey wash. Camera pushes in ~4% across the whole scene.
**"Your Mac has a notch."** holds ~1.3s, then **"It has never done anything."**
holds ~1.3s.
Sequential/interaction: two lines, one after the other, each past the reading floor.
Audio intent: bed at its lowest. The stillness is the hook.
Audio-coupled idea: none.
Music: ~0.14.
Transition mood: none — the camera carries straight into Scene 2.

### Scene 2 — The morph — 4.6s
On the beat the strip opens into the full panel on the app's real spring, and
the camera pulls back over 1.2s to frame it whole: artwork, title, scrubber,
transport, and the artwork's colour bleeding past the edge. Hero line fades up
beneath in the site's gradient: **"Your notch just woke up."** holds ~2.0s.
Sequential/interaction: the morph is the interaction.
Audio intent: the bed lifts on the same frame. One warm swell.
Audio-coupled idea: swell on the morph; glow breathes with bass from here on.
Music: lift to ~0.44.
Transition mood: none — the panel stays on screen.

### Scene 3 — One object, three states — 7.0s
The panel never cuts away; it reshapes.
- **8.2s** it collapses to a strip with a countdown running in it, then opens on
  the timer ring. Label: **"A timer that lives in the notch."** // beat-locked 8.74
- **10.6s** it reshapes to the clipboard: four rows, a cursor reaches the second,
  clicks, and it turns to a green check and **Copied**. Label: **"Your last 24
  copies."** then **"Never written to disk."**
- **13.0s** it collapses again; ⌃⌥N keycaps press below it and it opens with no
  pointer on screen. Label: **"Open it without the mouse."** // beat-locked 13.11
Sequential/interaction: a simulated click and a simulated keypress, both authored.
Audio intent: flat. One tick at the click, one key sound at the press.
Audio-coupled idea: interface tick on the click frame; key sound on the press frame.
Music: hold ~0.44.
Transition mood: none — continuous.

### Scene 4 — The numbers — 3.4s
Camera pulls back further until the panel is a small lit object high in a large
dark frame. Four numbers arrive beneath it on consecutive beats:
**1.6 MB · 37 MB · <1% of a core · MIT**.
Sequential/interaction: four short tokens on the beat grid 15.84 / 16.38 /
16.93 / 17.47 — short enough that beat spacing does not outrun reading.
Audio intent: unchanged. No accent; the arrival is visual.
Audio-coupled idea: none.
Music: hold.
Transition mood: slow crossfade → Scene 5

### Scene 5 — The price — 4.4s
The panel and numbers fade. Type only, centred.
**"The good ones cost $15 to $25."** holds ~1.4s. On the strong cue it is
replaced by **"This one doesn't."** holds ~1.6s. Then the wordmark and
`aloenotch.com`, and the frame goes quiet.
Sequential/interaction: none — the plainness is the point.
Audio intent: duck so the words carry, one dry low hit on the payoff, return for
the wordmark, fade out.
Audio-coupled idea: single announcement hit at 18.56.
Music: duck ~0.20, return ~0.38, fade to 0.
Transition mood: end.

**Music mood for this video:** low, wide, confident — never triumphant.
**Audio summary:** a near-silent bed under an extreme close-up, one lift on the
morph, flat through three reshapes with two small motion-matched ticks, a duck
so the price line lands plainly, and a fade out under the wordmark.
