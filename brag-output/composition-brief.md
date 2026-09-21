# Hyperframes Composition Brief: AloeNotch

## Objective
Create a short launch-style brag video for AloeNotch — a free, open-source
macOS app that turns the MacBook notch into a Dynamic Island.

## Output
- Composition directory: `brag-output/composition/`
- Rendered video: `brag-output/brag.mp4`
- Format: landscape — 1920x1080
- Duration: 22.3 seconds

## Source Material
- Project root: `/Users/cadeg/Desktop/Open Notch`
- Primary files read: `site/index.html`, `site/style.css`, `video/clips/clips.js`,
  `OpenNotch/Notch/NotchGeometry.swift`, `OpenNotch/Design/Theme.swift`
- Product name: AloeNotch
- Tagline / strongest claim: "Your notch just woke up." / "Free, without the asterisk."
- Key UI to show: **real product footage.** Four clips are supplied in
  `assets/video/`, re-rendered at 1600x640 from the project's own clip stage
  (`video/clips/`), which recreates the app's geometry and spring curves from
  the Swift source. Each is already trimmed to its scene length:
  - `now-playing.mp4` (4.70s) — the collapsed strip morphing into the full
    panel with artwork, scrubber, transport, and the ambient glow.
  - `timer.mp4` (3.20s) — a countdown taking over the collapsed strip, then the
    panel opening with the ring.
  - `clipboard.mp4` (3.10s) — a cursor clicking a row, which turns to a green
    check and "Copied". The click lands ~1.0s into this clip.
  - `shortcut.mp4` (3.10s) — ⌃⌥N keycaps pressing and the panel opening with no
    pointer on screen. The press lands ~0.5s into this clip.
- Copy that must appear verbatim:
  - "Your Mac has a notch."
  - "It has never done anything."
  - "Your notch just woke up."
  - "A timer that lives in the notch."
  - "Your last 24 copies."
  - "Never written to disk."
  - "Open it without the mouse."
  - "The good ones cost $15 to $25."
  - "This one doesn't."
  - "aloenotch.com"
  - "1.6 MB", "37 MB", "<1% of a core", "MIT"

## Creative Direction
- Tone preset: `polished`
- Creative direction: quiet premium product film for an app that costs nothing
- Interpretation: restraint is the argument. Mixed case, light weights, generous
  tracking. No exclamation marks. The footage plays without a label fighting it.
  The only forceful moment is the price line, and it lands by being plain.
- Angle: every MacBook owner has a notch and none of them have ever used it.
  The video is that argument: the notch is dead, the notch wakes up, here are
  three things it now does, and it is free while the good alternatives are not.
- Hook: a real inert black strip at the top of an empty screen under the words
  "Your Mac has a notch." then "It has never done anything." Nothing moves.
- Outro / punchline: "The good ones cost $15 to $25." → "This one doesn't." →
  wordmark, aloenotch.com, and four numbers.
- Avoid:
  - Generic SaaS language
  - Abstract filler visuals
  - Unrelated visual redesign
  - Naming competitors (the price range is the honest form of that argument)

## Visual Identity
- Background: `#050507`
- Surface: `rgba(255,255,255,0.05)`
- Accent: `#73bfff`; accent soft `rgba(115,191,255,0.35)`
- Text: `#f5f5f7`; muted `rgba(245,245,247,0.6)`
- Hero gradient: `linear-gradient(90deg, #73bfff, #b58cff 70%)`
- Display + body font: the system stack. The product is a macOS app; the system
  face is the honest one and needs no webfont.
- Visual references: the collapsed strip hanging from the top edge; the ambient
  glow tracing the panel; the site's radial wash at the top of the page.

## Layout note
The supplied clips already contain their own screen framing — a menu-bar edge
along the top and a desktop wash below. Place each video **full width at the
top of the canvas** (1920x768 at y=0) so its menu-bar edge is the canvas's top
edge and the notch reads as hanging from a real screen. Scene 1's hand-drawn
inert strip must match that position and scale: 480x77 at top centre, bottom
corners rounded, pure black.

## Storyboard
Use the storyboard in `brag-output/brag-plan.md` as the creative contract.

Scene summary:
1. Dead weight — 3.3s — inert strip; "Your Mac has a notch." then "It has never done anything."
2. It wakes — 4.7s — `now-playing.mp4`; "Your notch just woke up." in the site gradient.
3. The timer — 3.2s — `timer.mp4`; "A timer that lives in the notch."
4. The clipboard — 3.1s — `clipboard.mp4`; "Your last 24 copies." then "Never written to disk."
5. The shortcut — 3.1s — `shortcut.mp4`; "Open it without the mouse."
6. The price — 4.9s — type only; the two price lines, then wordmark + aloenotch.com + four numbers.

## Audio
- Audio role: warm bed, low and steady, with sparse motion-matched accents.
- Audio arc: silent-feeling hook over a low bed → lift on the wake → flat hold
  through three product moments with three small accents → duck under the price
  line → return for the logo → fade out.
- Music: `assets/music/happy-beats-business-moves-vol-12-by-ende-dot-app.mp3`
  (109.96 BPM).
- Music treatment: ~0.20 under the hook, ~0.42 from the wake, duck to ~0.22
  across the two price lines, back to ~0.40 for the logo, fade to 0 over the
  final 0.8s.
- Music cue guidance: preset at
  `assets/music/happy-beats-business-moves-vol-12-by-ende-dot-app.music-cues.json`.
  Strong cues 8.74s, 13.11s, 17.47s, 18.56s. Beat grid for the stat row:
  19.66 / 20.19 / 20.75 / 21.28.
- Audio-reactive treatment: subtle. The glow behind the panel and the hero
  title's presence may breathe with music RMS. Nothing else — no waveform bars,
  no equalizers, no particles.
- Audio-coupled moments:
  - Scene 2, the morph — one soft warm swell.
  - Scene 4, the cursor click — one short interface tick, on the click frame.
  - Scene 5, the keycap press — one key sound, on the press frame.
  - Scene 6, "This one doesn't." — one dry low hit, allowed to ring over the music.
- SFX selection guidance: four cues in the whole video, no more. Already chosen
  from the skill's safest low-high-frequency-risk picks and copied in:
  `assets/sfx/morph-swell.ogg` (impactSoft_medium_001),
  `assets/sfx/click.ogg` (ui/click2), `assets/sfx/keypress.wav`,
  `assets/sfx/payoff.ogg` (interface/bong_001).
- SFX analysis guidance:
  `/Users/cadeg/.claude/plugins/cache/brag/brag/0.3.0/skills/brag/assets/sfx/sfx-analysis.md`
  — all four picks are low high-frequency risk.
- Restraint rule: no whoosh on every transition, no riser into the logo, no SFX
  on the hook.

## Hyperframes Instructions
Follow `hyperframes-core` (composition contract + `data-*` timing),
`hyperframes-animation` (motion), `hyperframes-creative` (design spec, beats,
audio-reactive), `hyperframes-keyframes` (seek-safe keyframes), and
`hyperframes-cli` (check/render). This is the `/brag` workflow — do not route
into the generic promo / launch-video workflow.

Requirements:
- Show real product footage (supplied) — this is the centrepiece, not a recreation.
- Keep every line readable: short label ~0.8s settled, a sentence ~0.3s/word.
- 22.3 seconds total.
- Include the music bed and the four SFX.
- Lock 3 major reveals to strong cues within ±0.15s; snap the four outro stat
  tokens to consecutive beats within ±0.10s; hold the last one past its beat.
- Use local assets only.
- `npx hyperframes check` must pass before render.
