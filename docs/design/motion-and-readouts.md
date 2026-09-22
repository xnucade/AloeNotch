# Motion personality and tunable readouts

Design note. Status: **built**. Presets retuned against measured overshoot — see §5.1.

## 1. What this is answering

> "Make AloeNotch have a bounce animation like Alcove, and an option to change
> the colour of the increasing toggle — brightness and sound. Really I just want
> this to replicate a lot of what Alcove has. We really need to separate
> ourselves."

Those are two concrete features and one strategic instruction, and the
strategic one contradicts the others. Section 2 deals with that before the
design, because it changes what we should build.

## 2. The strategic problem: "replicate Alcove" and "separate ourselves"
   pull in opposite directions

Alcove's whole position is **fewer features, executed beautifully**. It has no
file shelf, no clipboard, no timer. It charges around $14 one-time and asks for
macOS 15+. Reviewers are consistent about what you are paying for: animation
timing, the way the island expands, typography.

AloeNotch already ships the shelf, the clipboard, the timer, the keyboard
shortcut, sound-output switching and keep-awake — and it is free, MIT, and
1.6 MB.

So the map looks like this:

```
                      more features →
                │
  free          │   Boring Notch ····· AloeNotch ····· Notchy
                │        (basics)      (broad + tiny)   (broad + 71 features)
  ──────────────┼──────────────────────────────────────────────
                │
  paid          │   Alcove ··········· NotchNook ····· Droppy
                │   (minimal + best    (widgets)       (extensions,
                │    motion, $14)                       iPhone sync)
                │
                      ↑ motion quality is Alcove's entire moat
```

Copying Alcove's *feature set* moves us left into Boring Notch's slot. Copying
its *motion standard* moves us up without giving anything away. **The second is
free to take; the first is a downgrade.**

And there is a third option neither of them occupies: Alcove's motion is
excellent and **fixed**. Nobody in this category lets you tune it. That is
where your two asks and "separate ourselves" stop fighting each other:

> **AloeNotch is the notch app whose motion you can dial.**
> Alcove decides how it feels. We let you decide, and we ship with good taste
> as the default.

Everything below serves that line.

## 3. Requirements

### Functional
| # | Requirement |
|---|---|
| F1 | The panel's opening overshoot is user-adjustable, from none to Alcove-lively. |
| F2 | Volume and brightness readouts can be tinted independently of the app accent. |
| F3 | Defaults are unchanged for existing installs — nobody's notch changes under them on update. |
| F4 | Every new control lives in Settings → Appearance, in the existing section/row primitives. |

### Non-functional
| # | Requirement | Why |
|---|---|---|
| N1 | 60 fps, no dropped frames during a bounce. | Existing bar. A bounce that stutters is worse than no bounce. |
| N2 | The collapsed strip must land on the hardware notch **exactly**, always. | It is what makes the app invisible at rest. See §5.1 — this constrains where bounce is allowed. |
| N3 | Reduce Motion forces bounce to zero regardless of the setting. | `AccessibilityPreferences` already exists; the setting must not be able to override the system. |
| N4 | Reduce Transparency and the existing `animationSpeed` keep working unchanged. | No regressions in the accessibility surface. |
| N5 | No new permissions, no new network calls, no measurable idle cost. | The "1.6 MB, <1% of a core" claim on the site is load-bearing. |

### Constraints
- One developer, SwiftUI, no new dependencies.
- Motion values must stay named constants in one place (`Theme.swift` → `Motion`),
  per the standing rule for this codebase.
- macOS 26+, Apple Silicon.

## 4. High-level design

Both features are the same shape: **a stored preference, read live by an
existing token layer, consumed by existing views.** No new subsystems.

```
AppSettings                    Theme.swift                 Views
───────────                    ───────────                 ─────
motionBounce  ──────────────►  Motion.expand      ───────►  NotchRootView
   (0…0.40)                    Motion.arrival               (panel geometry)
                               Motion.collapse  = 0 always
animationSpeed (exists) ─────► Motion.scaled()

hudTintMode   ──────────────►  NotchHUD.activity  ───────►  ActivityContent
hudVolumeHex                     → LiveActivity              (.level bar +
hudBrightnessHex                   .tint                      symbol)
   ▲
   └── AccentPicker (exists, reused)
```

`Motion` already reads `AppSettings.shared.animationSpeed` on every access via
computed properties, precisely so the Appearance sliders preview live. Bounce
threads through the identical path. There is no new plumbing to invent.

## 5. Deep dive

### 5.1 Bounce — and the one place it must not go

Today:

```swift
static var expand:   Animation { .smooth(duration: scaled(0.40), extraBounce: 0.10) }
static var collapse: Animation { .smooth(duration: scaled(0.32)) }            // 0 bounce
static var arrival:  Animation { .snappy(duration: scaled(0.34), extraBounce: 0.35) }
```

Proposed:

```swift
/// 0 = lands flat, 0.40 ≈ Alcove. Reduce Motion clamps this to 0.
private static var bounce: Double {
    AccessibilityPreferences.shared.reduceMotion
        ? 0
        : max(0, min(0.40, AppSettings.shared.motionBounce))
}

static var expand: Animation { .smooth(duration: scaled(0.40), extraBounce: bounce) }

/// Transients are allowed to be bouncier than the container — they are on
/// screen for a second and should read as having *landed*.
static var arrival: Animation {
    .snappy(duration: scaled(0.34), extraBounce: min(0.5, bounce + 0.25))
}

/// Still zero, and not configurable. See below.
static var collapse: Animation { .smooth(duration: scaled(0.32)) }
```

**Why `collapse` stays flat, and why this is a feature rather than a
limitation.**

The collapsed strip is drawn to the hardware notch's exact bounds. A spring
with overshoot on the *closing* transition undershoots its target before
settling — the strip becomes momentarily narrower and shorter than the physical
cutout, and for two or three frames you see the cutout's edges as a hairline of
wallpaper around a black shape that should be invisible.

Expanding overshoots *outward*, away from the cutout, into space that is
already the app's. That is safe at any bounce value.

This asymmetry is worth saying out loud in the UI, because a naive competitor
implementation bounces both ways and it looks broken on a real notched display.
It is the kind of detail that justifies the positioning in §2.

**Presets, not a raw number.** A slider labelled "extraBounce 0.0–0.4" is a
developer control. Ship three named personalities backed by the same scalar:

`extraBounce` maps to a damping ratio of `1 - bounce`, and the overshoot it
produces is sharply non-linear. Measured before picking the presets:

| `extraBounce` | overshoot |   | `extraBounce` | overshoot |
|---|---|---|---|---|
| 0.10 | 0.15% |  | 0.40 | 9.5% |
| 0.20 | 1.5%  |  | 0.45 | 12.6% |
| 0.30 | 4.6%  |  | 0.55 | 20.5% |

Which explains something worth knowing: **today's 0.10 is invisible.** At 0.15%
the panel does not overshoot in any way a person can see. The comment in
`Theme.swift` describing it as arriving "with momentum" has never been true.

| Preset | `motionBounce` | Overshoot | Reads as |
|---|---|---|---|
| Calm | 0.00 | 0% | Lands flat. Closest to macOS's own chrome. |
| Standard | 0.10 | 0.15% | Today's behaviour. **Default — F3.** |
| Lively | 0.45 | 12.6% | Alcove territory. Visible bounce, settles fast. |

Ceiling 0.55 (20.5%). Past that the panel wobbles rather than bounces, and on
a shape anchored to the top edge that reads as a bug.

With a disclosure-triangle "Custom" slider underneath for anyone who wants
0.22. The preset row is what 95% of people touch.

**Live preview.** The Appearance tab should animate a miniature notch when the
preset changes, the way the welcome screen's hover demo does — otherwise the
user has to close Settings and hover the notch to evaluate each option, which
makes the control feel broken.

### 5.2 Readout tint

Today the level bar is hardcoded:

```swift
case .level(let value):
    ZStack(alignment: .leading) {
        Capsule().fill(.white.opacity(0.18))      // track
        Capsule().fill(.white.opacity(0.92))      // fill
            .frame(width: max(3, 62 * value))
    }
```

`LiveActivity` already carries `var tint: Color = .white`, and `ActivityContent`
already applies it to the *symbol* (`.foregroundStyle(activity.tint)`). The bar
simply never reads it. So the change is small:

```swift
case .level(let value):
    ZStack(alignment: .leading) {
        Capsule().fill(activity.tint.opacity(0.18))
        Capsule().fill(activity.tint.opacity(0.92))
            .frame(width: max(3, 62 * value))
    }
```

…and then `NotchHUD.activity` supplies the tint instead of defaulting to white:

```swift
var activity: LiveActivity {
    LiveActivity(kind: "system.hud", symbol: icon,
                 tint: AppSettings.shared.hudTint(for: self),
                 trailing: .level(Double(level)),
                 size: .wide, duration: 1.5,
                 priority: LiveActivity.Priority.direct)
}
```

**Three modes, not a colour well per readout.** A plain "pick a colour for
volume, pick a colour for brightness" is fine but misses the interesting one:

| Mode | Behaviour | Notes |
|---|---|---|
| `monochrome` | White, as today. | **Default — F3.** |
| `accent` | Both follow the app accent. | One setting, no new decisions for the user. |
| `perKind` | Volume and brightness get their own colour. | Reuses `AccentPicker` twice. This is the literal ask. |
| `artwork` | Both take the now-playing artwork's extracted accent. | **This is the differentiator.** |

`artwork` is nearly free: `NowPlayingManager` already extracts an accent colour
from the album art for the ambient glow (measured at 12.24 ms median). Routing
that same value into the HUD means your volume bar is the colour of whatever is
playing, and goes back to white when nothing is. No competitor does this, and it
is a direct extension of the app's existing signature rather than a bolted-on
option.

**Contrast floor.** A user-chosen colour on pure black can fall below legibility.
The picker should clamp to a minimum luminance (or warn), the same way the
site's contrast audit does. A HUD you cannot read is worse than a white one.

### 5.3 Settings surface

Appearance tab, after the existing **Motion** section:

```
MOTION
  ┌─────────────────────────────────────────────────┐
  │ ⚡︎  Personality                [Calm|Standard|Lively] │
  │     How much the panel overshoots when it opens. │
  │     Closing never bounces — the collapsed strip  │
  │     has to land on the notch exactly.            │
  ├─────────────────────────────────────────────────┤
  │      ▸ Custom                          0.10  ——— │
  ├─────────────────────────────────────────────────┤
  │ ⏱  Animation speed                      1.0×  ——— │   (exists)
  │ ✨  Ambient glow                            [on] │   (exists)
  └─────────────────────────────────────────────────┘

READOUTS
  ┌─────────────────────────────────────────────────┐
  │ 🎚  Colour        [White|Accent|Custom|Artwork]  │
  │     Volume and brightness bars in the notch.     │
  ├─────────────────────────────────────────────────┤
  │      Volume      ● ● ● ● ● ●  (AccentPicker)     │  } only when
  │      Brightness  ● ● ● ● ● ●  (AccentPicker)     │  } Custom
  └─────────────────────────────────────────────────┘
```

Both sections get a live miniature preview on the right, animating on change.

### 5.4 Data model

```swift
// AppSettings — same persistence pattern as accentHex / glassIntensity.
@Published var motionBounce: Double       { didSet { save(...) } }   // 0…0.40, default 0.10
@Published var hudTintMode: HUDTintMode   { didSet { save(...) } }   // default .monochrome
@Published var hudVolumeHex: String       { didSet { save(...) } }   // default AccentPalette.default
@Published var hudBrightnessHex: String   { didSet { save(...) } }   // default "#FFC857"

func hudTint(for hud: NotchHUD) -> Color   // resolves mode → concrete Color
```

Defaults preserve today's behaviour exactly (F3): bounce 0.10, tint monochrome.

### 5.5 Testing

`PanelStateReducer` and `CountdownState` are already covered by
`scripts/run-tests.sh` because they are pure. The same applies here:

- `Motion.bounce` clamping (negative, >0.40, Reduce Motion → 0) is pure and
  testable if the clamp is extracted from the `Animation` construction.
- `hudTint(for:)` resolution across all four modes is pure.
- The contrast floor is pure.

Target: the suite stays green and grows by roughly a dozen checks. Animation
*feel* is not unit-testable and should be verified with `snapshot`-style frame
capture or by eye, not asserted.

## 6. Performance and risk

| Risk | Severity | Handling |
|---|---|---|
| Bounce on collapse reveals the cutout edge | High — breaks the app's core illusion | Not configurable. §5.1. |
| Reading `AppSettings.shared` per `Motion` access | Low | Already the pattern; it is a dictionary read, and it is what makes live preview work. |
| A user picks an unreadable HUD colour | Medium | Luminance floor in the picker. |
| Bounce at 0.40 dropping frames on the width animation | Medium | Same animated properties as today, only a different spring. Verify with Instruments on a real expand/collapse — an Instruments pass is already an open item. |
| Settings tab growing unwieldy | Low now, real later | Appearance already has Theme / Layout / Accent / Glass / Motion. Adding Readouts makes six. Revisit at eight — see §8. |

Neither change adds a timer, an observer, or a network call. Idle cost is
unchanged, which matters because "<1% of a core" is published on the site.

## 7. What else Alcove has that we do not — ranked by whether it is worth taking

| Alcove feature | Have it? | Take it? |
|---|---|---|
| Fluid, bouncy transitions | Partly | **Yes** — this document. |
| Customisable HUDs | No | **Yes** — this document. |
| Notifications in the notch | No | **Probably** — biggest remaining gap, and the one users notice. Needs a decision on how (no public notification-mirroring API without Accessibility or a private framework). |
| Swipe / scroll gestures on the notch | No | **Yes, cheap** — scroll-over-notch to change volume is a few dozen lines and feels expensive. |
| Lock Screen presence | No | **Not yet** — needs a widget extension; large lift, low visibility. |
| Minimal feature set | n/a | **No.** That is their position, not ours. |

## 8. What I would revisit as this grows

- **Settings will outgrow a five-tab window.** At eight sections per tab, a
  search field or a sidebar layout beats another section card.
- **Motion tokens will outgrow a single scalar.** If "personality" later wants
  to change *durations* as well as bounce (Calm = slower, Lively = faster), the
  clean shape is a `MotionProfile` struct holding the whole set, with the three
  presets as instances — not three more scalars threaded separately.
- **`LiveActivity.tint` is doing two jobs** once the bar reads it: symbol colour
  and bar colour. If a future activity wants those different, split it then,
  not now.

## Sources

Market positioning in §2 and §7 from published comparisons:
notchy.dev/blog/notchnook-vs-boring-notch-vs-alcove, notchy.dev/alcove-vs-boring-notch,
notchbay.com/blog/notchnook-vs-alcove.
