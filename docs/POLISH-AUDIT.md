# AloeNotch polish audit (Phase 0)

Audited at 0.13.2 (`35b7bf6`), 2026-10-06. Read-only: nothing in the app changed for this document.

This audit comes from reading the code, plus one measurement of the running 0.13.2 build. Anything that only a real notch can settle is marked **needs eyes**.

---

## 0. Headline findings

1. **The motion system is mostly in place.**
   - `Motion` (`Design/Theme.swift`) already holds named, speed-scaled springs.
   - `PanelStateReducer` (`Notch/PanelState.swift`) already decides the panel state as a pure, tested function.
   - Phase 1 is therefore tightening and finishing, not a rewrite. Rebuilding either would cost more than it gains.
2. **Reduce Motion has gaps.**
   - 38 call sites go through `Motion.resolve`, and 48 use a `Motion.*` curve directly.
   - Bounce is zeroed globally under Reduce Motion. However, scale, offset and blur transitions still travel at those 48 sites.
   - Two endless loops ignore Reduce Motion entirely: the battery bolt pulse and the charging shimmer.
3. **Announcements are dropped, not queued.**
   - `LiveActivityCenter.present` throws away a lower-priority activity that arrives during a higher one. For example, "AirPods connected" during a volume change is lost for good.
   - An announcement that arrives while the panel is open expires unseen.
4. **Hit-region timing ignores the speed setting.**
   - `expandSettle`, `collapseSettle` and `hudSettle` are fixed constants (0.42/0.34/0.30s). The curves they shadow, however, are divided by `animationSpeed`.
   - At 0.5× speed the clickable region shrinks while the panel is still visibly closing. A slow-motion debug mode would make this much worse, so it must be fixed first.
5. **The panel can't be used from the keyboard.**
   - ⌃⌥N opens it, but there's no focus, arrow or Tab navigation, and Esc doesn't close it.
   - There are no `@FocusState`, `focusable` or `onKeyPress` handlers anywhere in the panel.
6. **Memory is over budget.**
   - The running 0.13.2 shows a **47 MB** footprint after 24 hours (`footprint -p`), against the ~37 MB target. The perl now-playing adapter adds another 8 MB on top.
   - Idle CPU is fine: 0.0–0.1% over 12s of sampling, with about 0.18 idle wakeups/s averaged over 24 hours.
7. **One requested feature conflicts with an earlier decision of yours.**
   - The *camera mirror* in Phase 3 tier A goes against the recorded call "no mirror/camera feature".
   - I won't build it unless you reverse that call. See §3.4.

---

## 1. Motion inventory

### 1.1 Named curves (`Design/Theme.swift`, `enum Motion`)

"Speed-scaled" means the duration is divided by `animationSpeed` (clamped 0.25–3.0). "Bounce" is the Calm/Standard/Lively value, which is 0 under Reduce Motion.

| Token | Curve | Scaled | Used for | Interruptible |
|---|---|---|---|---|
| `expand` | `.smooth(0.40, extraBounce: bounce)` | yes | any → expanded | yes (spring on one `Animatable` frame) |
| `collapse` | `.smooth(0.32)`, no bounce | yes | expanded → anything; content removal | yes. Never overshoots, as the invariant requires |
| `detach` | `.smooth(0.52, bounce+0.14 ≤ 0.4)` | yes | split-island bubble leaving the strip | yes |
| `hud` | `.smooth(0.28)` | yes | peek ↔ peek width changes, drag reach, swipe spring-back | yes |
| `anticipate` | `.smooth(0.18)` | yes | hover swell (`isAnticipating`) | yes |
| `micro` | `.snappy(0.20)` | yes | hover/press states, tab pills | yes |
| `accentShift` | `.smooth(0.80)` | yes | ambient glow colour following artwork | yes |
| `contentFade` | `.smooth(0.30)` | yes | most content swaps | **no**: insert/remove transitions crossfade, they don't retarget |
| `arrival` | `.snappy(0.34, bounce+0.25 ≤ 0.5)` | yes | activity glyph arrival, shelf chip landing, gulp release | partly |
| `readout` | `.smooth(0.18)` | yes | numeric HUD values, countdown digits | yes |
| `ambientPulse` | `easeInOut(0.9)` repeat | **no** | charging bolt pulse | loop. **Ignores Reduce Motion** |
| `equalizerBar` | `easeInOut(0.5)` | **no** | idle (fake) equalizer | loop, gated |
| `equalizerLive` | `linear(0.05)` | **no** | live equalizer bars | per sample |
| `rimDrift` | `linear(18)` repeat | **no** | glass rim rotation while playing | loop, gated by Reduce Motion |
| `chargeShimmer` | `linear(1.2)` repeat | **no** | battery pill shimmer | loop. **Ignores Reduce Motion** |
| `contentLag` / `stagger` | 0.06s / 0.03s | yes | content follows shape by one beat | n/a |
| `reduced` | `easeInOut(0.20)` | no | Reduce Motion replacement | yes |

Transitions:
- `notchEntrance`, `activityEntrance`, `artworkSkip` and `textSkip` are named and Reduce-Motion aware.
- `activityEntrance` is the only one with the blur + scale + opacity treatment the brief asks for. The others use opacity + scale only.

### 1.2 Animations that bypass `Motion`

| Where | Value | Note |
|---|---|---|
| `NotchViewModel.swift:416` | `easeOut(0.07)` | drop "gulp". Should be a named token |
| `MediaView.swift:275`, `FocusedContent.swift:355` | `linear(0.5)` | scrubber progress (duplicated) |
| `TimerView.swift:218` | `linear(0.25)` | timer ring progress |
| `TimerView.swift:229` | `easeInOut(0.5)` | timer digits pulse |
| `MarqueeText.swift:86–87` | `easeOut(0.25)`, `linear(d)` + `Task.sleep` | marquee is a sleep loop. Fine, but untokenised |
| `NotchRootView.swift:718–719` | `SpringKeyframe .snappy` / `.bouncy(0.1)` | rubber band at volume limit. **Bounce isn't zeroed by Reduce Motion here** |
| `NotchRootView.swift:762` | per-bar `animation(index)` | idle equalizer |
| `NotchGestureDemo.swift:139–148` | four inline curves on a `Timer` + `asyncAfter` chain | onboarding demo only |
| `AppearanceTab.swift`, `WelcomeView.swift:166` | `.animation(motion)` bindings | local `motion` var. Check it resolves |

Duplicated values:
- 0.30 appears as `contentFade` and also as `hudSettle`.
- 0.5 linear appears three times.
- The settle constants re-state the curve durations by hand (finding 4).

### 1.3 Timer- and `asyncAfter`-driven behaviour

| Where | What | Verdict |
|---|---|---|
| `NotchViewModel.swift:357/375` | hover intent delay (0.12s) / close grace (0.25s) | fine as work items. Grace isn't speed-scaled, which is correct |
| `NotchViewModel.swift:583` | hit-region shrink after settle | **must derive from the curve** (finding 4) |
| `LiveActivity.swift:152` | activity expiry | wall clock. Keeps counting while the panel is open |
| `NotchWindowController.swift:98` | hover re-check 0.6s after a drop | OK |
| `AppDelegate.swift:51/56` | onboarding / What's New after 0.5s | OK |
| `ActivityDetectors.swift:74` | detector debounce | OK |
| `Weather` 30 min, `Calendar` 5 min, `Battery` 30s timers | refresh | the battery timer duplicates IOPS notifications. **Check whether it can go** |
| `NotchViewModel.swift:630` | Accessibility trust poll every 2s | no notification exists for this. Confirm it only runs while untrusted *and* HUD replacement is on |
| `ModulesTab`, `WelcomeView`, `PermissionsTab` | 2s permission polls | only while those windows are open. OK |
| `NotchRootView.swift:775` | `Task.sleep(3600)` loop | keep-alive for an animation. Worth a look |

### 1.4 Haptics

- `Haptics.tick()` fires on each volume/brightness step and each module step.
- `Haptics.caught()` fires on a shelf drop and when the timer finishes.
- Both already follow "one tap per landing". Note that Mac haptics only fire while a finger is on a Force Touch trackpad, so key-driven ticks are usually silent. That's harmless.

---

## 2. State map

### 2.1 States

The surface is in exactly one `PanelState`:
- `collapsed`
- `peek(.media)`
- `peek(.activity(compact|regular|wide))`
- `peek(.split(compact|regular|wide))`: media strip plus a detached bubble for a *resident* activity (the timer)
- `expanded`

Orthogonal modifiers sit on top. They don't change the state, but they do animate the same surface:
- `isAnticipating`: hover swell before open
- `dragReach`: surface leans toward a dragged file
- `gulping`: drop swallow
- `pull`: two-finger swipe stretch, with a spring-back
- `limitPush`: rubber band at volume/brightness limits
- `moduleStep`: swipe between modules
- `isPinnedOpen`: keyboard-opened

### 2.2 How the state is chosen

`PanelStateReducer.state(for:)` applies a fixed precedence:
1. Hover or pin → `expanded`.
2. Otherwise, an activity → `split` if the activity is resident and media plays, else `activity`.
3. Otherwise, media playing → `peek(.media)`.
4. Otherwise `collapsed`.

`NotchViewModel.apply` picks the curve by edge: into expanded → `expand`; out of expanded → `collapse`; everything else → `hud`.

```
            hover/click/⌃⌥N/drag
  collapsed ───────────────────────────▶ expanded
     ▲  │ media plays                       │ leave (+0.25s grace) / swipe up / ⌃⌥N / Esc✗
     │  ▼                                   ▼
  peek(media) ◀──── activity ends ──── (back to whatever inputs imply)
     │  ▲
     │  └─ activity ends
     ▼
  peek(activity) ── resident activity while media plays ──▶ peek(split)
```

### 2.3 Problems

| # | Problem | Effect |
|---|---|---|
| S1 | **No queue.** A lower-priority activity of a different kind is discarded (`LiveActivity.swift`, `present`) | device and drive announcements lost during HUD use |
| S2 | **Activities expire while hidden.** Expanded wins the reducer, but the expiry timer keeps running | a charge or connect event during an open panel is never seen |
| S3 | **Equal priority = last write wins**, with no minimum dwell | two quick ambient events can flash the first for one frame |
| S4 | **Settle timers not speed-scaled** (finding 4) | the hit region shrinks under a still-visible surface at speed < 1× |
| S5 | **Content branch swap isn't interruptible.** Reversing mid-flight runs removal and insertion transitions over each other | hover in/out fast and you see both contents ghosting. **Needs eyes** to judge severity |
| S6 | **Charging flash** (`flashChargingPeek`) and the battery timer can both announce the same plug-in | possible double announcement. **Needs eyes** |
| S7 | **Keyboard pin + hover**: mousing away from a keyboard-opened panel closes it | deliberate (documented in code). Keep |
| S8 | **Esc** does nothing | keyboard users can only close with ⌃⌥N |

Already well handled:
- The hit region grows immediately and shrinks only after settle.
- The hover grace cancels cleanly.
- A drag skips the intent delay.
- A swipe spring-back is 1:1 while the fingers move.

### 2.4 Proposed scheduler (Phase 1, PR 3)

Keep `PanelStateReducer` as the single decision function. Put an `ActivityScheduler` in front of `LiveActivityCenter`:
- **Priority classes:**
  - `direct` (HUD, 100) preempts;
  - `action` (60) and `ambient` (30) queue, maximum 3 queued, deduplicated by `kind`, newest payload wins.
- **Minimum dwell** of about 0.6s before a same-priority replacement, so nothing flashes.
- **Pause expiry while expanded.** Anything still in the queue plays after collapse, or is dropped if older than about 5s.
- Resident activities (timer, and later stopwatch and focus session) stay separate, as now.
- Every rule is unit-tested like the reducer, with simultaneous events resolved by (priority, arrival order).

---

## 3. Gap matrix

### 3.1 Sources (fetched 2026-10-06)

- **Alcove:** the changelog API behind [tryalcove.com/changelog](https://tryalcove.com/changelog) (`api.tryalcove.com/changelog`, updated June 2026, v1.7.9). $14.99, macOS 15+.
- **The Boring Notch:** [README](https://github.com/TheBoredTeam/boring.notch). Free, GPL-3.0. It separates shipped features from its roadmap.
- **DynamicLake:** [dynamiclake.com](https://www.dynamiclake.com/). Paid; price not listed on the page.
- **MediaMate:** [wouter01.github.io/MediaMate](https://wouter01.github.io/MediaMate/). Free tier plus paid.
- **NotchNook:**
  - **Couldn't be verified.** notchnook.com shows "under construction", and lo.cafe/notchnook returns 404.
  - [lo.cafe](https://lo.cafe/) says access is suspended over an ownership dispute and that a successor, "NOOTCH", is coming.
  - Its column is left as `?` rather than filled from memory.

Key: ✓ = shipped (verified) · R = on roadmap · — = not listed · ? = unverifiable.

### 3.2 Matrix

API key: Pub = public API · Priv = private API. Effort: S/M/L.

| Feature | Aloe | Alcove | NN | Boring | DynLake | MediaMate | API | Permission | Effort | Rec. |
|---|---|---|---|---|---|---|---|---|---|---|
| Now Playing + scrubber | ✓ | ✓ | ? | ✓ | ✓ | ✓ | Priv (MediaRemote via adapter) | none | — | refine |
| Shuffle / repeat | — | ✓ | ? | — | — | — | Priv, **already in vendored adapter** (`shuffle`, `repeat`) | none | S | **build** |
| Favorite / like | — | ✓ (Spotify) | ? | — | — | — | per-app AppleScript; Apple Music/Spotify only | Automation per app | M | needs research (prompt cost) |
| Source picker (several players) | — | ✓ ("system player", exclude sources) | ? | — | — | — | MediaRemote exposes one now-playing app; listing others is deeper private API | none | M–L | needs research |
| Track-change peek | partial (peek while playing) | ✓ (QuickPeek) | ? | R | — | ✓ | — | none | S | **build** |
| Multi-line lyrics | — (one line) | — | ? | — | — | — | LRCLIB, already used | none | M | **build** (no new network) |
| Live equalizer | ✓ | ✓ | ? | ✓ | — | — | ScreenCaptureKit audio | Screen & System Audio | — | refine |
| Calendar | ✓ | ✓ | ? | ✓ | ✓ | — | EventKit | Calendar | — | refine |
| Next-event countdown | — | ✓ | ? | — | ✓ (meetings) | — | EventKit | Calendar | S | **build** |
| Join call | ✓ | — | ? | — | ✓ | — | — | — | — | refine |
| Reminders | — | — | ? | R | — | — | EventKit | Reminders | M | tier B design |
| Weather | ✓ | ✓ | ? | R | ✓ | — | Open-Meteo + CoreLocation | Location | — | refine (no offline state, §4) |
| Volume/brightness HUD | ✓ | ✓ | ? | ✓ | ✓ | ✓ | event tap | Accessibility | — | refine |
| Keyboard backlight HUD | — | — | ? | ✓ | — | ✓ | Priv (CoreBrightness) + existing tap | Accessibility (already) | M | build, behind HUD switch |
| Caps Lock | — | — | ? | — | — | — | existing event tap `flagsChanged` | Accessibility (already) | S | **build**, only when tap exists |
| Mic mute | — | — | ? | — | — | — | Pub (CoreAudio property listener) | none | S | **build** |
| Low battery / Low Power Mode | partial (low-battery icon) | ✓ | ? | R | ✓ | — | Pub (IOPS, `NSProcessInfoPowerStateDidChange`) | none | S | **build** |
| Focus mode changes | — | ✓ | ? | — | — | — | `INFocusStatus` gives only on/off; *which* Focus needs Full Disk Access | Full Disk Access | M | **skip** unless on/off alone is wanted |
| Battery + charging | ✓ | ✓ | ? | R | ✓ | — | Pub | none | — | refine |
| AirPods battery | ✓ (hardware-untested) | ✓ | ? | — | — | — | Bluetooth | Bluetooth | — | **needs eyes** |
| Device / drive events | ✓ | ✓ | ? | R | — | — | Pub | none | — | refine |
| Timer + split bubble | ✓ | — | ? | — | ✓ | — | — | — | — | refine |
| Stopwatch / Pomodoro | — | — | ? | — | ✓ (timer) | — | — | none | S | **build** on scheduler |
| Shelf + AirDrop | ✓ | — | ? | ✓ | ✓ | — | Pub | none | — | refine |
| Shelf drop actions (compress, convert) | — | — | ? | — | ✓ | — | Pub (ImageIO, AppleArchive) | none | M | **build** (local only) |
| "Last screenshot" | — | — | ? | — | — | — | screenshots live in TCC-protected Desktop | Desktop folder | S | tier B (permission cost) |
| Clipboard history | ✓ (in memory) | — | ? | — | ✓ | — | Pub | none | — | refine |
| Clipboard pin / search / plain text / images | — | — | ? | — | ✓ | — | Pub | none | S–M | **build**; images in memory only, capped (§3.3) |
| Camera mirror | — | — | ? | R | — | — | AVFoundation | Camera | M | **blocked by earlier decision** (§3.4) |
| Notification mirroring | — | ✓ | ? | R (considering) | ✓ | — | no public API (§3.5) | Full Disk Access or Accessibility scraping | L | research only |
| Lock Screen widgets | — | ✓ | ? | R | — | — | Priv (SkyLight spaces) | none | L | research only |
| Hide in full screen / games | — | ✓ | ? | — | — | — | Pub (frontmost app + `CGWindowList` bounds; no names → no Screen Recording) | none | S | **build** |
| Per-app exclusions | — | partial | ? | — | — | — | same as above | none | S | **build** together |
| Show on all displays | — (one display, picker) | ✓ | ? | — | — | ✓ (below menu bar) | Pub | none | M | build, measure memory (one panel per screen) |
| Simulated notch / pill | ✓ | ✓ | ? | ✓ | ✓ | ✓ | — | — | — | refine |
| Swipe gestures | ✓ | ✓ | ? | R | — | — | — | — | — | refine |
| Shortcuts / App Intents / URL scheme | — | — | ? | R (extensions) | — | — | Pub | none | M | tier B design |
| Download progress | — | — | ? | — | — | — | Downloads is TCC-protected | Downloads folder | M | tier B (permission cost) |
| System stats | — | — | ? | — | — | — | Pub (host_statistics) | none | M | tier B, only if idle budget holds |
| Localization | — | started | ? | — | — | — | String Catalog | — | M | Phase 2 |
| Auto-update | check only | ✓ | ? | — | — | — | Sparkle | none | M | Phase 4 |
| Homebrew | — | — | ? | ✓ | — | — | — | — | S | Phase 4 (after notarization) |

### 3.3 What I'd skip or narrow

- **Favorite/like:**
  - MediaRemote has no reliable cross-app "love" command.
  - Doing it per app means an Automation prompt per player, which breaks "permissions in context, only when needed".
  - My recommendation: skip it, or limit it to Apple Music behind its own toggle.
- **Focus mode *name*:** needs Full Disk Access. Showing only "Focus on/off" is possible but thin. Skip.
- **Clipboard images:**
  - Fine in memory, but 24 full-resolution images could add tens of MB, against a memory budget that's already over (finding 6).
  - Plan: keep downscaled thumbnails plus a size cap, and drop the oldest images first.

### 3.4 Camera mirror

Your recorded decision is "no mirror/camera feature". The brief lists it in tier A. My plan:
- I won't build it unless you reverse that decision.
- If you do, it ships off by default, asks for Camera only on first use, and runs `AVCaptureSession` only while the tile is on screen.

### 3.5 Tier C research questions (to be answered in a later write-up, not built)

- **Notification mirroring.** macOS has no public API to read other apps' notifications. The known routes are:
  1. reading the Notification Center database under `~/Library/Group Containers/group.com.apple.usernoted/`, which needs **Full Disk Access**;
  2. scraping Notification Center's UI through Accessibility, which is fragile across OS updates.
  
  Both go against the privacy story: the app would be reading every message preview. Default answer: no.
- **Lock Screen presence.** Alcove ships this, most likely through private SkyLight window-level and space APIs that can draw above the lock screen. It needs no permission, but it's private-API surface that can break with any macOS update. I'll confirm the exact mechanism before recommending anything.

---

## 4. Polish defects

### 4.1 Geometry and type

1. **Concentric radii aren't used.** `Metrics.concentricRadius` exists but has zero call sites.
   - Inner radii are 16, 13, 12, 8, 7 and 5, each chosen by hand.
   - The panel is 26 with 20 padding, which implies about 6 for flush insets. Most nested surfaces are not flush, so this needs a per-surface rule rather than one number.
2. **21 raw font sizes** outside `Typography`, mostly in Welcome, What's New, the timer and the gesture demo. Settings uses system styles, which is correct there.
3. **Off-scale spacing.** The scale is 2/4/8/12/16/20, but literals 5, 7, 9, 11, 13 and 18 appear repeatedly. The strip insets are 9 and 12, the weather pill padding 9×5, and so on.
4. **Tabular digits.** `monospacedDigit` is present on weather, the timer and HUD values. Still to confirm: battery %, the clock in the header, and scrubber times.

### 4.2 States and controls

5. **The weather pill has no loading, offline or denied state.** It renders nothing when `weather.current == nil`, so the header just shifts.
   - Media, calendar, shelf and clipboard all have designed empty states, and calendar has a denied state.
6. **Four `.buttonStyle(.plain)` buttons** have no pressed feedback. Everything else uses `PressableButtonStyle` (22 sites).
7. **No focus rings or keyboard path** in the panel (finding 5).
8. **No Increase Contrast or Differentiate Without Color handling.**
   - The hairline is `Ink.fill` (8% white), which disappears over a white wallpaper under glass.
   - Alcove added a "contrast outline" in 1.7.5.
9. **Two looping animations ignore Reduce Motion** (the charging bolt and the battery shimmer). The volume-limit rubber band uses `.bouncy` directly.

### 4.3 System edge cases with no handling

| Case | Today |
|---|---|
| Full-screen apps / games | the panel stays (`fullScreenAuxiliary`). No hide option |
| Menu bar auto-hide | not considered |
| Low Power Mode | equalizer and rim drift run unchanged |
| Sleep/wake, display hot-plug | **fixed in 0.13.2** (frame self-heal, wake reposition) |
| Mission Control / Stage Manager / Spaces | joins all Spaces. Mission Control behaviour **needs eyes** |
| Screen sharing | handled (`sharingType` follows "hide from capture") |
| Clamshell with external non-notch display | simulated notch; **needs eyes** |

### 4.4 Settings

10. **Two "glass" settings** with confusing names:
    - `notchStyle` (solid/glass) is the notch;
    - `useGlass` is the windows and menus.
    
    Rename it "Glass windows" or fold it into one appearance choice.
11. **Two motion settings:** `animationSpeed` (0.25–3×) and `motionBounce` (Calm/Standard/Lively). macOS has no speed slider; I'd keep personality and move speed into the debug menu.
12. **`positionOffset`** fixes a problem the notch geometry already solves. I'd hide it unless you know of users who need it.
13. Copy is mostly in macOS tone already; a full pass happens with the String Catalog.

### 4.5 Localization

14. **No String Catalog.** Every string is hardcoded, and right-to-left layout has never been checked. The strip's left = artwork / right = equalizer layout must **not** flip, because it follows the hardware.

### 4.6 Budgets

15. **Memory:** 47 MB measured, target ~37 MB. Needs an allocations pass before any feature work adds more. Likely suspects (unverified):
    - artwork kept at full resolution;
    - glass layers kept alive while closed;
    - the clipboard holding rich types.

---

## 5. Proposed order of work

Each PR is one concern and can ship on its own. ⚑ = needs your eyes on a real notch.

**Phase 1: motion**
1. **Motion tokens, finished.**
   - Derive the settle times from the curve durations (fixes S4).
   - Turn every bypass in §1.2 into a named token.
   - Add `Motion.animation(_:)`, which resolves Reduce Motion so call sites can't forget, and migrate the 48 unresolved sites.
   - Gate the two loops on Reduce Motion.
2. **Debug menu** (⌥-click the menu bar icon):
   - slow-motion multiplier 0.1–1×;
   - a state cycler through every `PanelState` and modifier;
   - a frame-time overlay built on the existing `FrameBudget`.
   - Compiled into Release but hidden behind ⌥.
3. **Activity scheduler** (§2.4), with tests. Fixes S1–S3 and S6.
4. **Interruptibility:**
   - retargetable content swaps (S5);
   - title and timer ring travel between strip and panel the way the artwork already does;
   - blur + scale + opacity entrance used consistently;
   - a numericText / symbol-effect sweep. ⚑
5. **Hover intent and hit region:** a menu-bar graze guard, plus re-checking the 0.12s / 0.25s values with the slow-motion tool. ⚑
6. **Profiling pass:**
   - Instruments numbers for open and close in solid and glass (the glass-vs-solid cost was never measured);
   - Low Power Mode slows the equalizer and stops the rim drift;
   - memory allocations pass.

**Phase 2: polish**

7. Geometry and type tokens: concentric radii, spacing scale, type scale, tabular digits.
8. Keyboard: focus, arrows, Tab, Space/Return, Esc closes.
9. Module states: weather loading/offline/denied, and a sweep of the rest.
10. Contrast: Increase Contrast outline and Differentiate Without Color. ⚑ over bright, dark and busy wallpapers.
11. Edge behaviour: hide in full screen, menu bar auto-hide, Mission Control. ⚑
12. Settings consolidation and copy (§4.4).
13. String Catalog and right-to-left check.

**Phase 3: tier A** (in this order, all built on the PR 3 scheduler)

14. Shuffle/repeat, track-change peek.
15. Mic mute, Caps Lock, Low battery/Low Power Mode activities.
16. Stopwatch, focus session, next-event countdown.
17. Clipboard: pin, search, plain-text paste, image thumbnails.
18. Hide in full screen plus per-app exclusions (shares code with 11).
19. Shelf drop actions (compress, convert image), optional auto-clear.
20. Multi-line lyrics.
21. Show on all displays (after the memory pass).
22. Keyboard backlight HUD (private API, behind the HUD switch).

Tier B gets design notes; tier C gets the write-up in §3.5.

**Phase 4: ship quality**

23. Notarization script. **Blocked** until you enrol in the Apple Developer Program ($99/year).
24. Sparkle with an EdDSA appcast on the site. ⚠ Expect the DMG to grow past ~2 MB; I'll measure before asking you to accept it.
25. Homebrew cask, after notarization. I'll check Homebrew's current signing policy first.
26. README, changelog, privacy policy, and Settings → Access.

---

## 6. Decisions (answered 2026-10-06)

1. **Camera mirror:** keep the "no camera" decision. Not built.
2. **Speed slider:** move `animationSpeed` out of Settings into the debug menu. Keep Calm/Standard/Lively.
3. **Favorite/like and Focus name:** skipped.
4. **Sparkle:** a DMG above 2 MB is acceptable.
5. **Keyboard backlight HUD:** build it (private API, behind the HUD switch).
6. **Plan:** approved. Work starts with PR 1.
