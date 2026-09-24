# Next level: the plan to be the best notch app on the market

Design note. Status: **proposed**. Written 2026-09-24 from a full audit of the
0.9.2 codebase, a measured run of the shipping build, and a survey of the
category as it stands today. Builds on `motion-and-readouts.md` — read that
first for the "motion you can dial" positioning, which this plan keeps.

## 1. What "best" has to mean

"Best" cannot be a feeling, or there is no way to know when we have got
there. So first, the bar. Each line is something we can measure or check.

| Axis | Bar | Today (0.9.2, measured) |
|---|---|---|
| **Feel** | Every state change is a spring, can be interrupted, lags content behind its container, and never drops a frame at 120 Hz | Springs ✅, choreography ✅, frame drops not yet measured |
| **Idle cost** | < 0.1% CPU, < 1 wakeup/s, < 40 MB | 0.1% CPU ✅, **~4.5 wakeups/s** ❌, 36 MB ✅ |
| **Accessibility** | Every control labelled; Reduce Motion and Transparency respected | Reduce Motion ✅, Transparency ✅, **2 labels across ~54 buttons** ❌ |
| **Craft** | One type scale, one opacity ladder, no one-off values | **22 different white opacities, 47 raw font sizes, 50 raw paddings** ❌ |
| **Trust** | Signed, notarized, private by default, crash data without a third party | Private ✅, **not notarized** ❌, no crash reporting |
| **Reach** | Runs on the Macs people actually own | macOS 26+ only, Apple silicon only |

The engineering underneath is already better than most of the category. The
reducer is tested, the motion tokens are disciplined, and the clip,
choreography and glow problems are all solved. The gaps are the **signature
moments** people screenshot and share, and a layer of **polish debt** that
nobody notices one item at a time but everybody feels.

## 2. The market today

Condensed from current comparisons ([notchy.dev][1], [macnotch.io][2]):

- **Alcove** ($15–25). Still the benchmark for motion. Differentiators:
  **several live activities on screen at once**, **swiping on the notch to
  switch between them**, and **lock-screen** media.
- **NotchNook** ($25). The most mature shelf and widgets. Users report
  **battery drain and high CPU**, which is the opening for our efficiency
  story.
- **Boring Notch** (free, OSS). **Audio visualizer** and **synced lyrics**
  (beta), plus **AirDrop from the shelf**. Reviewers call its animations
  "less polished".
- **Atoll / Notchy** (free). Lock-screen widgets, and a very long feature list.
- **Seam**. Battery per AirPod (left, right, case) and Focus detection.
- **MacNotch / DynamicLake**. Liquid Glass styling on the panel.

The pattern: **free apps are broad and rough; paid apps are polished and
narrow.** No app is free, open source, tiny, *and* in Alcove's league for
motion. That is the empty slot, and it is ours to take. We don't need to win on
feature count. Notchy has 71 features and nobody talks about how it feels.

## The plan in four tracks

```
  FEEL (signature motion)      CRAFT (every pixel)         SOLID (trust)            REACH (features that matter)
  ───────────────────────      ───────────────────         ─────────────            ────────────────────────────
  3.1 Poured shape             4.1 Opacity ladder          5.1 Hover intent         6.1 AirDrop + Quick Look
  3.2 Anticipation swell       4.2 Type scale              5.2 Zero idle wakeups    6.2 AirPods battery
  3.3 Split island  ★          4.3 Track-change motion     5.3 VoiceOver            6.3 Lock-screen media
  3.4 Gestures                 4.4 Marquee titles          5.4 Screen-share privacy 6.4 Lyrics (opt-in)
  3.5 Rubber-band HUD          4.5 Blur, surgically        5.5 Multi-display        6.5 Focus indicator
  3.6 Real equalizer                                       5.6 Crash diagnostics    6.6 Notarize (blocked)
  3.7 Magnetic drop                                        5.7 Frame-time budget
```

★ is the headline. If only one thing ships, ship that.

---

## 3. Feel: the signature motion

### 3.1 The poured shape: concave top shoulders

**Problem.** `NotchShape` has square top corners (`topLeadingRadius: 0`). The
real MacBook cutout flares into the bezel through small **concave** fillets.
So when the wings grow for media or a HUD, their top outer corners meet the
screen edge at a hard 90° and read as *attached*. Every top-tier notch app
curves those corners so the panel reads as *poured* from the bezel.

```
  today                         proposed
  ┌──────────────┐             ╮──────────────╭      ← concave shoulders flare
  │              │             │              │        into the screen edge
  ╰──────────────╯             ╰──────────────╯
```

**Design.** Add `shoulderRadius` to `NotchShape`, built from two quad curves
that sit *outside* the rect's top corners. Animate it alongside
`cornerRadius`:

| State | Shoulder | Bottom |
|---|---|---|
| collapsed (hug) | match the hardware (~6 pt) | hardware |
| peek (wings) | 6 pt | 10 pt |
| expanded | 10–14 pt | 26 pt |

The shape's width grows by 2 × shoulder, so `NotchMetrics.size(for:)` and the
hit-test region must include the shoulders, and the ambient glow's
`NotchEdgeShape` must trace them. **Constraint:** this must not break the
"invisible when idle" rule. In the collapsed state the shoulders must match the
hardware fillet exactly. Measure the fillet on a real display with a screenshot
at 2× before choosing the number.

**Cost:** small, since it is one shape. **Risk:** a pixel of misalignment shows
at the cutout, so verify against the hardware on the built-in display.

### 3.2 Anticipation swell (and the hover-intent fix it pays for)

**Problem 1, solidity.** `hoverChanged(true)` opens *instantly*. Every trip to
the menu bar or a browser tab strip that crosses the notch pops the panel
open. This is the top complaint in the category about notch apps.

**Problem 2, feel.** The collapsed notch is dead until the moment it is
fully opening.

**Design: one mechanism solves both.** Add a ~120 ms hover-intent delay, and
fill that delay with a **2–3 pt swell**: the strip grows slightly wider and
taller on a critically damped spring as the pointer arrives. If the pointer
leaves within the intent window, the swell relaxes and nothing opens. If it
stays, the open spring starts *from the swollen size* and inherits its
velocity. The delay then feels like responsiveness rather than lag, because
something visibly happened in the first frame.

- Add a state, `.peek(.anticipate)`, to the reducer, with a test for "leave
  inside the intent window never reaches `.expanded`".
- Settings → General: **Open on: Hover / Hover (instant) / Click**. Some people
  want click-to-open, and competitors offer it.
- Dragging a file bypasses the intent delay: a drag is never an accident.

### 3.3 ★ Split island: two activities at once

**Why it's the headline.** It is the most recognisable Dynamic Island moment
there is: a second activity *pinches off* the island as its own bubble. Alcove
charges for "multiple live activities", and nobody free does it. The most
common real case is **timer running + music playing**. Today the reducer
shows one or the other (the resident timer wins and the media peek
disappears), so the user loses one of them.

```
  one activity                 two activities
  ╭──[art]  ▮▮▮  ≋≋≋──╮          ╭──[art]  ▮▮▮  ≋≋≋──╮   ●  4:32
                                                    ↑
                                   detached bubble, pure black, notch height
```

**Model.** Extend `PanelState.Peek` with
`.split(primary: ActivitySize, secondary: LiveActivity.Kind)`. The reducer
picks the primary exactly as today, and the secondary is the next resident
(timer, media, charging). A transient HUD (volume) still takes the whole strip
and hides the bubble, because it is time-critical and brief.

**The animation: metaball detach.** SwiftUI can render a gooey merge natively:
draw both shapes in a `Canvas`, then apply
`context.addFilter(.alphaThreshold(min: 0.5, color: .black))` after
`.blur(radius: ~8)`. The blur merges nearby silhouettes and the threshold
re-sharpens the result. The bubble's centre animates outward on a spring, so
the bridge between them stretches, thins and snaps, and does the reverse to
merge.

- **Run the metaball pass only during the ~0.45 s transition**, then swap to
  plain shapes. Blur plus threshold on every frame is exactly the per-frame
  cost that caused the old `.blurReplace` stutter (gotcha #6).
- It must render pure `#000` so the bubble reads as part of the hardware.
- The window and hit-test region must include the bubble. Hovering the bubble
  opens its module in the focused layout.
- Reduce Motion: plain fade in and out, with no stretch.

**Cost:** the largest item in this plan (about 3–4 days). **Risk:** medium.
Keep the metaball pass isolated behind a single view, so it can fall back to a
cross-fade if it measures badly.

### 3.4 Gestures on the notch

The panel already receives scroll events when hovered, so none of these need a
permission. Override `scrollWheel` in `PassthroughHostingView`:

- **Two-finger swipe down** on the collapsed strip opens it, even under the
  hover-intent delay. **Swipe up** inside the panel closes it.
- **Horizontal swipe on the media peek**: next or previous track, with the
  directional motion from §4.3.
- **Horizontal swipe in the focused layout**: switch module (Alcove's
  "swipe between tasks").
- Follow the gesture *1:1 while the fingers move* (rubber-banded), then hand
  the release velocity to the spring. That is what makes it feel physical
  rather than triggered (WWDC23 "Animate with springs" [3]).

### 3.5 Rubber-band HUD at the limits

Pressing volume-up at 100% currently does nothing visible. The event tap
*receives the key even at the limit*, so we know it happened. Stretch the
level bar about 6 pt past full on a stiff spring and let it snap back, plus
`Haptics` on a Force Touch trackpad. It is iOS's own behaviour, and it's the
kind of detail that makes people say "oh, nice". It is about half a day of
work.

### 3.6 A real equalizer (opt-in)

The collapsed equalizer is a `repeatForever` loop, so it dances identically to
silence and to drum and bass. A real one: a **Core Audio process tap** (macOS
14.2+), with an RMS level in 4–5 bands and bars tinted with the artwork
accent.

- It needs the "System Audio Recording" permission, so it stays **opt-in**
  with a clear explanation. The fake bars remain the default.
- Compute levels on the tap's audio thread, publish at 30 Hz only while the
  peek is visible, and stop the tap when the peek hides. Budget: < 0.5% CPU
  while visible.

### 3.7 Magnetic drop

While a file is dragged toward the notch, the strip **reaches** toward the
cursor: a few points of stretch biased to the cursor's x position. On drop,
the file's icon shrinks into the shelf slot on the `arrival` spring, and the
panel does one small "gulp" (a scale of 0.98 → 1). The shelf is a place
things go into, so the motion should say that.

---

## 4. Craft: every little design element

### 4.1 One opacity ladder

There are 22 different `.white.opacity(…)` values in the code. The eye can't
tell 0.45 from 0.5 on black, but it *can* tell that nothing lines up. Collapse
them into five semantic tokens in `Theme.swift`:

| Token | Value | For |
|---|---|---|
| `Ink.primary` | 0.92 | titles, active values |
| `Ink.secondary` | 0.62 | artist, event titles |
| `Ink.tertiary` | 0.42 | labels, inactive glyphs |
| `Ink.quaternary` | 0.24 | dividers, placeholders |
| `Fill.hover` / `Fill.selected` | 0.07 / 0.14 | capsules |

Mechanical, low-risk and big in aggregate. Do it in one commit, then add a
grep to `run-tests.sh` that fails on any new raw `.white.opacity(`.

### 4.2 One type scale, one rule for rounded

47 raw `.system(size:)` calls bypass `Typography`, and rounded and default
faces mix within the same rows (the week strip's digits are rounded, the event
title beside them isn't). The rule: **SF Pro for words, SF Pro Rounded for
numerals that are the point** (clock, timer, HUD percent, temperature). Always
use `.monospacedDigit()` on anything that ticks. Then route every raw size
through `Typography`.

### 4.3 Track changes that move with intent

Today the artwork cross-fades and the title swaps instantly.

- **Artwork:** slide 12 pt in the direction of travel (next = left, previous
  = right) while cross-fading. The direction comes from our own buttons and
  swipes; changes from elsewhere default to "next".
- **Title and artist:** a short blur-and-rise on the text only
  (`.contentTransition(.interpolate)`, or opacity with an 8 pt offset and a
  3 pt blur). It is cheap because it's a tiny layer.
- **Glow:** already drifts over 0.8 s ✅. Keep it.

### 4.4 Titles that fit

Long titles hard-truncate. On hover, scroll truncated titles once
(marquee), with a 1 s pause at each end and faded edge masks. Only while
hovered, only if truncated, and only once per hover.

### 4.5 Blur, surgically

Gotcha #6 was right: blurring the *whole panel* every frame stutters. But
Apple's island blurs **content** in and out, and small layers are cheap. Use
a 2–4 pt blur on the entrance and exit of `ActivityContent` and the HUD
glyphs (layers of a few hundred points), never on the container. Measure with
the frame-time budget in §5.7 before keeping it.

---

## 5. Solid: things that must never go wrong

### 5.1 Hover intent

See §3.2. Listed again here because it is the #1 solidity item, not just a
motion one.

### 5.2 Zero idle wakeups

The measured 0.1% CPU is excellent, but there are ~4.5 wakeups/s at idle,
which almost certainly come from `BrightnessMonitor`'s 0.2 s poll. Wakeups are
what "energy impact" in Activity Monitor actually measures.

- The CGEvent tap *already sees* the brightness keys. Poll fast (0.1 s) for
  1.5 s after a brightness key, and slowly (5 s) otherwise, to catch Control
  Center and auto-brightness changes.
- Suspend the calendar and weather timers while the display sleeps
  (`NSWorkspace.screensDidSleepNotification`).
- Target **< 1 wakeup/s at idle**, then publish it on the site. NotchNook's
  battery complaints make this a competitive claim, not just hygiene.

### 5.3 VoiceOver

Two accessibility labels across ~54 buttons means the panel is mostly silent
to VoiceOver.

- Give every icon-only button an `.accessibilityLabel`.
- Group rows with `.accessibilityElement(children: .combine)`.
- Give the HUD bar `.accessibilityValue` for its level.
- Post an announcement when a live activity appears
  (`NSAccessibility.post(… .announcementRequested)`).

This is also the cheapest possible "we are serious" signal on the site.

### 5.4 Screen-share privacy

With the join button, the panel now shows up during calls, and the clipboard
pane can show a password someone copied *while they're sharing their screen*.

- Setting: **Hide from screen recordings and screen sharing**, which sets
  `window.sharingType = .none`. **Verify on 26 and 27 first:** there are
  reports that ScreenCaptureKit stopped honouring it in macOS 15. If it no
  longer works, fall back to the next option alone.
- Mark clipboard entries from password managers as concealed and never render
  them. Check the `org.nspasteboard.ConcealedType` pasteboard type, the
  convention 1Password and others use. That's worth doing regardless.

### 5.5 Multiple displays

`preferredScreen()` picks one screen. For someone docked to an external
monitor with the lid closed, there's no notch and the app sits on "the first
screen". Use this policy:

- the built-in display when it is active;
- otherwise, the display with the menu bar (the main screen), with a
  simulated notch;
- setting: *Show on: Built-in / Main display / All displays*.

### 5.6 Crash diagnostics without a third party

`MXMetricManager` (MetricKit) delivers crash and hang diagnostics locally on
macOS 12+, with no SDK and no server. Store the last few, and add
**Settings → Support → Copy diagnostic report** so a GitHub issue can include
a real stack trace. It keeps the privacy story intact.

### 5.7 A frame-time budget, enforced

"Never drops a frame" needs a number and a check:

- A debug-only overlay: a `CADisplayLink` on the panel's screen that logs any
  frame over 8.3 ms (120 Hz) during an open, a close or a split. Print the
  worst frame per transition.
- Run it on every animation change in this plan. Anything over budget either
  gets fixed or doesn't ship.

---

## 6. Reach: the features worth adding (and the ones to refuse)

Ranked by value divided by effort:

| # | Feature | Effort | Notes |
|---|---|---|---|
| 6.1 | **AirDrop from the shelf**, plus **Quick Look** (space bar) | ½ day | `NSSharingService(named: .sendViaAirDrop)`; `QLPreviewPanel`. Boring Notch has AirDrop; we should too. |
| 6.2 | **AirPods battery** in the connect activity (left, right, case) | 1–2 days | Private IOBluetooth properties; degrade to "Connected" like everything else (gotcha #3). Seam's signature feature. |
| 6.3 | **Lock-screen now playing** | 3–4 days | Needs a private SkyLight space above the lock screen (the approach open-source apps take). Alcove, Atoll and Notchy all have it. **Must degrade silently.** |
| 6.4 | **Synced lyrics**, opt-in | 2 days | LRCLIB (free, keyless). Sends the track name to a third party, so it's opt-in and disclosed in the Privacy Policy. Lyrics scroll in the focused media module. |
| 6.5 | **Focus mode indicator** | ½ day | A small glyph in the wings when Focus is on. |
| 6.6 | **Notarization + Developer ID** | blocked on the $99 enrollment | Still the biggest adoption unlock. It also unblocks Sparkle (see the memory note on Accessibility resets). |

**Refuse**, to keep the Alcove-grade focus from `motion-and-readouts.md`:
notification mirroring (fragile private APIs), AI-usage trackers, a built-in
terminal, a camera mirror (already declined), and window snapping. Every one
of them is somebody else's product.

**Revisit: the macOS 26 floor.** Liquid Glass is confined to a few places
(`GlassBackdrop`, `SettingsView`, `SettingsMenuView`), which already sit behind
`useGlass` wrappers. With `#available` gates, macOS 15 is reachable, and every
competitor supports 14+. The cost is real: a second OS to test on, with no
machine to test it. **Recommendation: keep 26+ for now**, and revisit only if
support requests show demand. It was a deliberate 0.7.0 decision.

---

## 7. Order of work

```
  0.10  "Feel"      3.1 poured shape · 3.2 swell + hover intent · 3.5 rubber band
                    4.3 track-change motion · 5.2 zero wakeups · 5.7 frame budget
  0.11  "Craft"     4.1 opacity ladder · 4.2 type scale · 4.4 marquee · 4.5 blur
                    5.3 VoiceOver · 5.4 concealed clipboard · 6.1 AirDrop + Quick Look
  0.12  "Island"    3.3 split island ★ · 3.4 gestures · 3.7 magnetic drop
  0.13  "Reach"     6.2 AirPods battery · 6.5 Focus · 5.5 multi-display · 5.6 diagnostics
  later             3.6 real equalizer · 6.3 lock screen · 6.4 lyrics · 6.6 notarize → 1.0
```

The reasoning behind the order:

- **0.10 is the cheapest high-visibility work.** The shape and the swell
  change the first half-second of every interaction.
- **The frame budget lands before anything expensive.** Nothing gets built on
  an unmeasured baseline.
- **The design-token commit (0.11) comes before the island.** Otherwise the
  biggest new view gets built on 22 opacities.
- **1.0 = notarized.** Unsigned software shouldn't be called 1.0.

Each release follows the usual flow: a feature commit, then `release.sh`,
with the site's `hero.js` updated whenever geometry or springs change (the
shoulders will change it).

## 8. What to revisit as it grows

- **The reducer** is now carrying hover, pin, intent, activity, split and
  media. If it grows past about eight inputs, split it into two layers:
  *what's shown* and *how big it is*.
- **Private APIs** (MediaRemote via perl, DisplayServices, IOBluetooth,
  SkyLight). Each new one is another thing a macOS beta can break. Keep one
  degradation test per API in the release checklist, and try each macOS beta
  in the first week it ships.
- **The metaball pass**: if the frame budget can't hold at 120 Hz on the
  lowest supported Mac, the split falls back to a clean fade. The feature
  matters more than the effect.

[1]: https://notchy.dev/best-mac-notch-apps/
[2]: https://macnotch.io/compare/best-mac-notch-apps
[3]: https://developer.apple.com/videos/play/wwdc2023/10158/
