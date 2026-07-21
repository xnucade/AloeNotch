/* =========================================================================
   AloeNotch demo video — deterministic timeline.

   `window.__render(t)` paints the frame for time `t` (seconds). It is a PURE
   function of t: no wall-clock reads, no requestAnimationFrame, no CSS
   transitions. Rendering the same t twice must produce identical pixels, or
   the frame-by-frame renderer would tear.

   Motion curves mirror the app's own SwiftUI animations so the video moves the
   way the app actually moves:
     expand   .smooth(duration: 0.40, extraBounce: 0.10)
     collapse .smooth(duration: 0.32)
     hud      .smooth(duration: 0.28)
   ========================================================================= */

/* ---------- Timing ------------------------------------------------------ */

const DURATION = 66;          // total runtime, seconds

/* Scene boundaries — see README.md for the shot list. */
const S = {
  open:      0,
  reveal:    6.5,
  playing:   13,
  ambient:   22,
  shelf:     29,
  glance:    39,
  hud:       47,
  invisible: 55,
  endcard:   60,
};

/* App animation constants, from NotchViewModel.swift. */
const EXPAND   = { d: 0.40, bounce: 0.10 };
const COLLAPSE = { d: 0.32, bounce: 0.0  };
const HUDANIM  = { d: 0.28, bounce: 0.0  };

/* Panel geometry, from NotchGeometry.swift. */
const NOTCH_W = 200, NOTCH_H = 32;
const MEDIA_WING = 46, HUD_WING = 84;
const EXP_W = 616, EXP_H = 208;
const R_EXPANDED = 26, R_COLLAPSED = 10;

const SCREEN_W = 1512, SCREEN_H = 982;
const FRAME_W = 1920, FRAME_H = 1080;
const BASE_SCALE = FRAME_W / SCREEN_W;   // fill the frame's width

/* ---------- Math -------------------------------------------------------- */

const clamp01 = x => x < 0 ? 0 : x > 1 ? 1 : x;
const lerp = (a, b, t) => a + (b - a) * t;
const easeInOut = t => t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
const easeOut = t => 1 - Math.pow(1 - t, 3);
const easeOutQuint = t => 1 - Math.pow(1 - t, 5);

/**
 * SwiftUI `.smooth(duration:extraBounce:)` — a unit spring settling in
 * `duration` seconds. dampingRatio = 1 - extraBounce, natural frequency
 * omega = 2*PI/duration (matching SwiftUI's perceptual-duration mapping).
 */
function springCurve(elapsed, duration, bounce) {
  if (elapsed <= 0) return 0;
  if (elapsed >= duration * 2.2) return 1;    // long settled
  const zeta = 1 - (bounce || 0);
  const w = (2 * Math.PI) / duration;
  const t = elapsed;
  if (zeta < 1) {
    const wd = w * Math.sqrt(1 - zeta * zeta);
    return 1 - Math.exp(-zeta * w * t) *
      (Math.cos(wd * t) + (zeta * w / wd) * Math.sin(wd * t));
  }
  return 1 - Math.exp(-w * t) * (1 + w * t);
}

/** Spring progress for an event that began at `start`. */
const springAt = (t, start, cfg) => springCurve(t - start, cfg.d, cfg.bounce);

/** Linear 0..1 progress across [start, start+dur]. */
const ramp = (t, start, dur) => clamp01((t - start) / dur);

/** Eased 0..1 progress across [start, start+dur]. */
const eramp = (t, start, dur, ease = easeInOut) => ease(ramp(t, start, dur));

/**
 * Fade envelope: 0 before `start`, up over `inD`, 1 while held, down over
 * `outD`, 0 after. Used for captions and overlays.
 */
function envelope(t, start, hold, inD = 0.5, outD = 0.5) {
  if (t < start) return 0;
  if (t < start + inD) return easeOut((t - start) / inD);
  if (t < start + inD + hold) return 1;
  if (t < start + inD + hold + outD) return 1 - easeInOut((t - start - inD - hold) / outD);
  return 0;
}

/** Interpolate keyframes [{t, v}] with easing between them. */
function track(t, keys, ease = easeInOut) {
  if (t <= keys[0].t) return keys[0].v;
  const last = keys[keys.length - 1];
  if (t >= last.t) return last.v;
  for (let i = 0; i < keys.length - 1; i++) {
    const a = keys[i], b = keys[i + 1];
    if (t >= a.t && t <= b.t) {
      const p = (t - a.t) / (b.t - a.t);
      return lerp(a.v, b.v, ease(p));
    }
  }
  return last.v;
}

/* Mix two hex colors. */
function mixHex(a, b, t) {
  const pa = [1, 3, 5].map(i => parseInt(a.substr(i, 2), 16));
  const pb = [1, 3, 5].map(i => parseInt(b.substr(i, 2), 16));
  const c = pa.map((v, i) => Math.round(lerp(v, pb[i], clamp01(t))));
  return `rgb(${c[0]},${c[1]},${c[2]})`;
}

/* ---------- Content ----------------------------------------------------- */

/* Synthetic cover art and fictional tracks: the video ships publicly, so it
   must not depend on real album artwork or artist names. */
const TRACKS = [
  {
    title: 'Neon Arcade', artist: 'Lanterns', dur: 204, accent: '#ff5f7e',
    art: `radial-gradient(70% 60% at 22% 18%, #ff9a3d, transparent 62%),
          radial-gradient(75% 70% at 82% 84%, #7b2ff7, transparent 66%),
          linear-gradient(148deg, #ff2f6d 0%, #d81e5b 48%, #3b1053 100%)`,
    badge: '#fa233b', badgeGlyph: 'note',
  },
  {
    title: 'Deep Field', artist: 'Aurora Bay', dur: 257, accent: '#3fd2e0',
    art: `radial-gradient(65% 60% at 26% 24%, #67e8f9, transparent 60%),
          radial-gradient(80% 75% at 84% 80%, #4338ca, transparent 68%),
          linear-gradient(145deg, #0ea5b7 0%, #1d4ed8 52%, #111a4a 100%)`,
    badge: '#1db954', badgeGlyph: 'wave',
  },
  {
    title: 'Golden Hour', artist: 'Marisol Vane', dur: 189, accent: '#ffb44d',
    art: `radial-gradient(68% 62% at 24% 20%, #fde68a, transparent 62%),
          radial-gradient(78% 72% at 80% 82%, #9a3412, transparent 66%),
          linear-gradient(150deg, #f59e0b 0%, #ea580c 50%, #5b1a06 100%)`,
    badge: '#fa233b', badgeGlyph: 'note',
  },
];

/* Files that get dropped on the shelf. */
const FILES = [
  { fill: 'linear-gradient(150deg,#fdfdfd,#e3e6ee)', kind: 'doc' },
  { fill: 'linear-gradient(150deg,#7dd3fc,#2563eb)', kind: 'img' },
  { fill: 'linear-gradient(150deg,#fca5a5,#dc2626)', kind: 'pdf' },
];

const CAPTIONS = [
  { at: 1.1,  hold: 2.3, text: 'Your Mac has a notch.' },
  { at: 4.0,  hold: 1.6, text: 'It has never done anything.' },
  { at: 9.4,  hold: 2.6, text: 'AloeNotch', sub: 'A Dynamic Island for your MacBook.', big: true },
  { at: 14.0, hold: 2.6, text: 'Now playing, from any app', sub: 'Music, Spotify — even a browser tab.' },
  { at: 18.2, hold: 2.2, text: 'Scrub, seek, skip', sub: 'Real controls, not just a readout.' },
  { at: 23.2, hold: 3.4, text: 'Ambient glow', sub: "The panel takes on the artwork's color." },
  { at: 30.0, hold: 3.0, text: 'Drop shelf', sub: 'Park files in the notch while you move between apps.' },
  { at: 35.0, hold: 2.4, text: 'Then drag them all out at once.' },
  { at: 40.0, hold: 2.8, text: 'Your week at a glance', sub: 'The next event, right under the date.' },
  { at: 44.0, hold: 2.0, text: 'Weather and battery, always in the header.' },
  { at: 48.4, hold: 2.6, text: 'It replaces the macOS HUD', sub: 'Volume and brightness land in the notch.' },
  { at: 52.4, hold: 1.8, text: 'No more grey square over your work.' },
  { at: 56.0, hold: 2.6, text: 'And when you don’t need it, it vanishes.', sub: 'The collapsed strip hugs the hardware notch exactly.' },
];

/* ---------- Element handles -------------------------------------------- */

const $ = id => document.getElementById(id);
const el = {};
['camera','screen','panelWrap','panel','glow','edge','collapsed','hud','expanded',
 'miniArt','wave','hudIcon','hudBar','cursor','dragGhost','caption','card',
 'artAura','artMain','artBadge','mTitle','mArtist','scrubFill','scrubKnob',
 'tElapsed','tTotal','btnPlay','btnPrev','btnNext','calDays','calSub','hClock',
 'battFill','battPct','shelfDrop','shelfEmpty','shelfGrid','dragAll','shelfTrash',
 'div1','div2','wxPill'].forEach(id => el[id] = $(id));

const glowBloom = el.glow.querySelector('.bloom');
const glowLine  = el.glow.querySelector('.line');
const edgePathEl = el.edge.querySelector('path');
const hudBarFill = el.hudBar.querySelector('b');
const waveBars = [...el.wave.querySelectorAll('i')];

const ICON = {
  play:  '<svg width="15" height="15" viewBox="0 0 20 20" fill="currentColor"><path d="M6.4 4.3a.9.9 0 0 0-1.4.8v9.8a.9.9 0 0 0 1.4.8l8.2-4.9a.9.9 0 0 0 0-1.6z"/></svg>',
  pause: '<svg width="15" height="15" viewBox="0 0 20 20" fill="currentColor"><rect x="5.4" y="4.2" width="3.5" height="11.6" rx="1.2"/><rect x="11.1" y="4.2" width="3.5" height="11.6" rx="1.2"/></svg>',
  vol1:  '<svg width="14" height="14" viewBox="0 0 20 20" fill="currentColor"><path d="M9.6 3.3 5.9 6.4H3.3a1 1 0 0 0-1 1v5.2a1 1 0 0 0 1 1h2.6l3.7 3.1a.7.7 0 0 0 1.2-.6V3.9a.7.7 0 0 0-1.2-.6z"/><path d="M13.2 7.6a.8.8 0 0 0-.2 1.2 1.8 1.8 0 0 1 0 2.4.8.8 0 0 0 1.1 1.1 3.4 3.4 0 0 0 0-4.6.8.8 0 0 0-.9-.1z"/></svg>',
  vol2:  '<svg width="14" height="14" viewBox="0 0 20 20" fill="currentColor"><path d="M9.6 3.3 5.9 6.4H3.3a1 1 0 0 0-1 1v5.2a1 1 0 0 0 1 1h2.6l3.7 3.1a.7.7 0 0 0 1.2-.6V3.9a.7.7 0 0 0-1.2-.6z"/><path d="M13.2 7.6a.8.8 0 0 0-.2 1.2 1.8 1.8 0 0 1 0 2.4.8.8 0 0 0 1.1 1.1 3.4 3.4 0 0 0 0-4.6.8.8 0 0 0-.9-.1z"/></svg>',
  vol3:  '<svg width="14" height="14" viewBox="0 0 20 20" fill="currentColor"><path d="M9.6 3.3 5.9 6.4H3.3a1 1 0 0 0-1 1v5.2a1 1 0 0 0 1 1h2.6l3.7 3.1a.7.7 0 0 0 1.2-.6V3.9a.7.7 0 0 0-1.2-.6z"/><path d="M13.2 7.6a.8.8 0 0 0-.2 1.2 1.8 1.8 0 0 1 0 2.4.8.8 0 0 0 1.1 1.1 3.4 3.4 0 0 0 0-4.6.8.8 0 0 0-.9-.1z"/><path d="M15.5 5.2a.8.8 0 0 0-.3 1.2 5.2 5.2 0 0 1 0 7.2.8.8 0 0 0 1.1 1.1 6.8 6.8 0 0 0 0-9.4.8.8 0 0 0-.8-.1z"/></svg>',
  sun:   '<svg width="14" height="14" viewBox="0 0 20 20" fill="currentColor"><circle cx="10" cy="10" r="4"/><g stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><path d="M10 1.6v2.2M10 16.2v2.2M18.4 10h-2.2M3.8 10H1.6M15.9 4.1l-1.6 1.6M5.7 14.3l-1.6 1.6M15.9 15.9l-1.6-1.6M5.7 5.7 4.1 4.1"/></g></svg>',
  note:  '<svg width="11" height="11" viewBox="0 0 20 20" fill="#fff"><path d="M15.4 2.6 8.2 4.3v8.5a2.9 2.9 0 1 0 1.6 2.6V7.6l5.6-1.3z"/></svg>',
  wave:  '<svg width="11" height="11" viewBox="0 0 20 20" fill="none" stroke="#fff" stroke-width="1.7" stroke-linecap="round"><path d="M4.6 12.2c3.4-1.9 7.4-1.9 10.8 0M5.6 8.6c2.8-1.6 6-1.6 8.8 0M6.8 5.2c2-1.1 4.4-1.1 6.4 0"/></svg>',
  doc:   '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="#5b6478" stroke-width="1.6"><path d="M7 5.5h6.5L17 9v9.5H7z"/><path d="M9.4 12h5.2M9.4 15h5.2"/></svg>',
  img:   '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="1.6"><rect x="5.5" y="6.5" width="13" height="11" rx="2"/><circle cx="9.3" cy="10.2" r="1.3" fill="#fff"/><path d="M6.4 15.6 10 12.4l3 2.6 2.4-1.9 2.2 1.9"/></svg>',
  pdf:   '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="1.6"><path d="M7 5.5h6.5L17 9v9.5H7z"/><path d="M9.6 14.6c2.6-.6 4.2-3.2 3.6-4.4-.5-1-1.7-.3-1.5 1.2.3 2.2 1.7 4 3.6 4.2"/></svg>',
};

/* Build the calendar week strip once (7 days centred on "today"). */
(function buildCalendar() {
  const dows = ['T','F','S','S','M','T','W'];
  const nums = [16, 17, 18, 19, 20, 21, 22];
  el.calDays.innerHTML = nums.map((n, i) =>
    `<div class="day${i === 3 ? ' today' : ''}"><span class="dow">${dows[i]}</span><span class="num rounded mono-digit">${n}</span></div>`
  ).join('');
})();

/* Build the shelf chips once; visibility is driven per frame. */
el.shelfGrid.innerHTML = FILES.map(f =>
  `<div class="chip" style="background:${f.fill}">${ICON[f.kind]}</div>`
).join('');
const chips = [...el.shelfGrid.querySelectorAll('.chip')];

/* End card. Uses the real app icon shipped with the site. */
el.card.innerHTML = `
  <div class="glowbed"></div>
  <div class="icon"><img src="../site/assets/icon.png" width="148" height="148" alt=""></div>
  <div class="wordmark">AloeNotch</div>
  <div class="rule"></div>
  <div class="tag">Free and open source.</div>
  <div class="url">aloenotch.kadeslab.com</div>
  <div class="meta">macOS 15+ &middot; Apple Silicon &middot; MIT licensed</div>
`;
const cardItems = [...el.card.children].slice(1);

/* ---------- Per-frame state -------------------------------------------- */

/** Which track is playing at time t, and when it started. */
function trackAt(t) {
  if (t < S.ambient + 1.6) return { i: 0, since: S.reveal + 1.9 };
  if (t < S.ambient + 4.4) return { i: 1, since: S.ambient + 1.6 };
  return { i: 2, since: S.ambient + 4.4 };
}

/** Media is playing between the reveal and the final collapse. */
const MEDIA_START = S.reveal + 1.9;
const MEDIA_END = S.invisible + 1.4;
const isPlaying = t => t >= MEDIA_START && t < MEDIA_END;

/** Panel is expanded from the reveal until the HUD scene collapses it. */
const EXPAND_AT = S.reveal + 1.9;
const COLLAPSE_AT = S.hud + 1.0;
const isExpanded = t => t >= EXPAND_AT && t < COLLAPSE_AT;

/** Volume / brightness key presses: [time, kind, level]. */
const HUD_EVENTS = [
  [S.hud + 2.9, 'vol', 0.42],
  [S.hud + 3.4, 'vol', 0.58],
  [S.hud + 3.9, 'vol', 0.74],
  [S.hud + 5.8, 'bright', 0.38],
  [S.hud + 6.3, 'bright', 0.62],
  [S.hud + 6.8, 'bright', 0.86],
];
const HUD_LINGER = 1.5;   // matches the 1.5s auto-dismiss in NotchViewModel

/** The active HUD at time t, or null. */
function hudAt(t) {
  let active = null;
  for (const [at, kind, level] of HUD_EVENTS) {
    if (t >= at) active = { at, kind, level };
  }
  if (!active) return null;
  // A press restarts the dismiss timer; only the last one counts.
  const laterPress = HUD_EVENTS.find(([at]) => at > active.at);
  const dismissAt = active.at + HUD_LINGER;
  if (!laterPress && t > dismissAt) return null;
  return active;
}

/** Shelf drops: [dragStart, dropTime]. */
const DROPS = [
  [S.shelf + 0.6, S.shelf + 2.1],
  [S.shelf + 2.6, S.shelf + 3.9],
  [S.shelf + 4.3, S.shelf + 5.5],
];
const DRAG_ALL_AT = S.shelf + 7.4;   // cursor grabs the "Drag all" pill

/* ---------- Camera ------------------------------------------------------ */

/**
 * Camera keyframes. The screen's top edge is always pinned to the frame's top
 * edge — the notch lives at y=0, and letterboxing above the menu bar would
 * read as a rendering bug rather than as framing. So a shot is just "which
 * screen column is centred" (x) and "how far in" (s).
 *
 * s is a multiplier on BASE_SCALE. It must stay >= 1.0 or the virtual screen
 * stops covering the frame and black bars appear at the sides.
 */
const CAM = [
  // s = 1.00 maps the 1512pt screen exactly onto the 1920px frame, so nothing
  // is cropped — the menu-bar clock stays visible in the wide shots.
  { t: 0,               x: 756, s: 1.00 },
  { t: S.reveal,        x: 756, s: 1.14 },
  { t: S.reveal + 2.3,  x: 756, s: 1.34 },
  { t: S.playing,       x: 756, s: 1.34 },
  { t: S.playing + 1.5, x: 700, s: 1.95 },   // push in on the media column
  { t: S.ambient - 1.2, x: 700, s: 1.95 },
  { t: S.ambient + 0.6, x: 756, s: 1.55 },   // pull back for the glow
  { t: S.shelf - 0.6,   x: 756, s: 1.55 },
  { t: S.shelf + 0.4,   x: 820, s: 1.85 },   // over to the shelf
  { t: S.glance - 1.0,  x: 820, s: 1.85 },
  { t: S.glance + 0.8,  x: 770, s: 2.05 },   // calendar week strip
  { t: S.glance + 4.0,  x: 770, s: 2.05 },
  { t: S.glance + 5.4,  x: 810, s: 2.05 },   // header pills
  { t: S.hud - 0.6,     x: 810, s: 2.05 },
  { t: S.hud + 0.8,     x: 756, s: 1.55 },   // pull back so the panel can collapse
  { t: S.hud + 1.7,     x: 756, s: 1.55 },
  // The collapsed strip is only 32pt tall, so the HUD beats need a hard push
  // in — at this zoom the frame shows just the top ~250pt of the screen.
  { t: S.hud + 2.3,     x: 756, s: 3.30 },
  { t: S.invisible-0.6, x: 756, s: 3.30 },
  { t: S.invisible+1.4, x: 756, s: 1.00 },   // wide: the notch disappears
  { t: DURATION,        x: 756, s: 1.00 },
];

function cameraAt(t) {
  const k = f => track(t, CAM.map(c => ({ t: c.t, v: c[f] })), easeInOut);
  return { x: k('x'), s: Math.max(1, k('s')) * BASE_SCALE };
}

/* ---------- Cursor ------------------------------------------------------ */

const CURSOR = [
  { t: 0,             x: 1180, y: 640 },
  { t: S.reveal,      x: 1180, y: 640 },
  { t: S.reveal+1.7,  x: 762,  y: 22  },   // arrives at the notch → expands
  { t: S.playing+4.6, x: 762,  y: 22  },
  { t: S.playing+5.4, x: 556,  y: 150 },   // onto the scrubber
  { t: S.playing+7.4, x: 610,  y: 150 },   // drags it forward (seek)
  { t: S.ambient-1.4, x: 610,  y: 150 },
  { t: S.ambient-0.5, x: 585,  y: 168 },   // onto "next"
  { t: S.ambient+5.4, x: 585,  y: 168 },
  { t: S.shelf-0.4,   x: 300,  y: 520 },
  { t: S.shelf+0.6,   x: 300,  y: 520 },
  { t: DROPS[0][1],   x: 1000, y: 132 },
  { t: DROPS[1][0],   x: 340,  y: 470 },
  { t: DROPS[1][1],   x: 1000, y: 132 },
  { t: DROPS[2][0],   x: 320,  y: 500 },
  { t: DROPS[2][1],   x: 1000, y: 132 },
  { t: DRAG_ALL_AT,   x: 1012, y: 96  },   // the "Drag all" pill
  { t: DRAG_ALL_AT+1.6, x: 1290, y: 470 },
  { t: S.glance,      x: 1290, y: 470 },
  { t: S.glance+1.0,  x: 900,  y: 640 },
  { t: DURATION,      x: 900,  y: 700 },
];

const cursorAt = t => ({
  x: track(t, CURSOR.map(c => ({ t: c.t, v: c.x })), easeInOut),
  y: track(t, CURSOR.map(c => ({ t: c.t, v: c.y })), easeInOut),
});

/* ---------- Render ------------------------------------------------------ */

function render(t) {
  /* --- Camera --- */
  const cam = cameraAt(t);
  // Screen point (cam.x, 0) lands at frame (centre, top).
  el.camera.style.transform =
    `translate(${FRAME_W / 2}px, 0px) scale(${cam.s}) translate(${-cam.x}px, 0px)`;

  /* --- Panel size --- */
  const expanded = isExpanded(t);
  const playing = isPlaying(t);
  const hud = hudAt(t);
  const { i: trackIdx, since: trackSince } = trackAt(t);
  const tr = TRACKS[trackIdx];

  // Collapsed width grows into wings for the media glyph or a HUD.
  let collapsedW = NOTCH_W;
  if (hud) collapsedW = NOTCH_W + HUD_WING * 2;
  else if (playing) collapsedW = NOTCH_W + MEDIA_WING * 2;

  // Wing width eases with the HUD curve from whatever it was before the last
  // change (media glyph appearing, a HUD taking over, or either going away).
  const lastChange = lastCollapsedChange(t);
  const wingP = springAt(t, lastChange.at, HUDANIM);
  const animCollapsedW = lerp(lastChange.from, collapsedW, wingP);

  let w, h, radius, expandP;
  if (expanded) {
    expandP = springAt(t, EXPAND_AT, EXPAND);
    w = lerp(NOTCH_W + MEDIA_WING * 2, EXP_W, expandP);
    h = lerp(NOTCH_H, EXP_H, expandP);
    radius = lerp(R_COLLAPSED, R_EXPANDED, clamp01(expandP));
  } else if (t >= COLLAPSE_AT) {
    const p = springAt(t, COLLAPSE_AT, COLLAPSE);
    expandP = 1 - p;
    w = lerp(EXP_W, animCollapsedW, p);
    h = lerp(EXP_H, NOTCH_H, p);
    radius = lerp(R_EXPANDED, R_COLLAPSED, clamp01(p));
  } else {
    expandP = 0;
    w = animCollapsedW;
    h = NOTCH_H;
    radius = R_COLLAPSED;
  }

  el.panel.style.width = w + 'px';
  el.panel.style.height = h + 'px';
  el.panel.style.borderRadius = `0 0 ${radius}px ${radius}px`;

  /* --- Edge hairline + ambient glow (both outside the panel's clip) --- */
  const d = edgePath(w, h, radius);
  for (const svg of [el.glow, el.edge]) {
    svg.setAttribute('width', w);
    svg.setAttribute('height', h + 40);
    svg.style.width = w + 'px';
    svg.style.height = (h + 40) + 'px';
  }
  edgePathEl.setAttribute('d', d);
  edgePathEl.style.opacity = expandP > 0.05 ? 1 : 0;

  glowBloom.setAttribute('d', d);
  glowLine.setAttribute('d', d);
  // Accent crossfades over 0.8s when the artwork changes (AmbientGlow).
  const prev = TRACKS[Math.max(0, trackIdx - 1)];
  const accent = mixHex(prev.accent, tr.accent, ramp(t, trackSince, 0.8));
  const glowVisible = playing ? 1 : 0;
  const glowFade = playing
    ? clamp01((t - MEDIA_START) / 0.6)
    : clamp01(1 - (t - MEDIA_END) / 0.5);
  glowBloom.style.stroke = accent;
  glowLine.style.stroke = accent;
  glowBloom.style.opacity = (expanded ? 0.5 : 0.35) * glowFade * glowVisible || (glowFade * 0.35);
  glowLine.style.opacity = (expanded ? 0.95 : 0.7) * glowFade;
  el.glow.style.opacity = glowFade;

  /* --- Collapsed / HUD / expanded content --- */
  const deadzone = NOTCH_W;
  el.collapsed.querySelector('.deadzone').style.width = deadzone + 'px';
  el.hud.querySelector('.deadzone').style.width = deadzone + 'px';

  el.collapsed.style.opacity = (!expanded && !hud) ? 1 : 0;
  el.collapsed.style.display = expandP > 0.98 ? 'none' : 'flex';
  el.miniArt.style.background = tr.art;
  el.miniArt.style.opacity = playing ? 1 : 0;

  // Equalizer: 4 bars breathing on a 0.5s ease-in-out, staggered by 0.11s.
  const barH = [5, 11, 7, 9];
  waveBars.forEach((b, i) => {
    const phase = (t - MEDIA_START - i * 0.11) / 0.5;
    const osc = playing ? (1 - Math.cos(phase * Math.PI)) / 2 : 0;
    b.style.height = lerp(3, barH[i], osc) + 'px';
    b.style.background = accent;
    b.style.opacity = playing ? 0.9 : 0;
  });

  el.hud.style.opacity = hud ? 1 : 0;
  el.hud.style.display = hud ? 'flex' : 'none';
  if (hud) {
    // Icon thresholds match NotchHUD.icon in NotchViewModel.swift.
    el.hudIcon.innerHTML = hud.kind === 'bright' ? ICON.sun
      : hud.level < 0.34 ? ICON.vol1
      : hud.level < 0.67 ? ICON.vol2
      : ICON.vol3;
    el.hudIcon.style.color = 'rgba(255,255,255,0.9)';
    // The level bar itself eases with .smooth(0.18).
    const prevEvent = [...HUD_EVENTS].reverse().find(([at]) => at < hud.at);
    const from = prevEvent && prevEvent[1] === hud.kind ? prevEvent[2] : (hud.kind === 'bright' ? 0.2 : 0.28);
    const lvl = lerp(from, hud.level, springCurve(t - hud.at, 0.18, 0));
    hudBarFill.style.width = Math.max(3, 62 * clamp01(lvl)) + 'px';
  }

  // Expanded content: opacity + scale(0.97, anchor top), tracking the spring.
  el.expanded.style.opacity = clamp01((expandP - 0.12) / 0.5);
  el.expanded.style.transform = `scale(${lerp(0.97, 1, expandP)})`;
  el.expanded.style.display = expandP < 0.02 ? 'none' : 'flex';

  /* --- Media column --- */
  el.artMain.style.background = tr.art;
  el.artAura.style.background = tr.art;
  el.mTitle.textContent = tr.title;
  el.mArtist.textContent = tr.artist;
  el.artBadge.style.background = tr.badge;
  el.artBadge.innerHTML = ICON[tr.badgeGlyph];
  el.btnPlay.innerHTML = playing ? ICON.pause : ICON.play;

  // Elapsed advances in real time from the moment the track started. The first
  // track also gets dragged forward once, during the scrub beat.
  const SEEK_AT = S.playing + 5.4, SEEK_END = S.playing + 7.4, SEEK_TO = 141;
  let elapsed, seeking = false;
  if (trackIdx === 0) {
    if (t < SEEK_AT) {
      elapsed = 82 + (t - trackSince);
    } else if (t <= SEEK_END) {
      seeking = true;
      elapsed = lerp(82 + (SEEK_AT - trackSince), SEEK_TO,
                     clamp01((t - SEEK_AT) / (SEEK_END - SEEK_AT)));
    } else {
      elapsed = SEEK_TO + (t - SEEK_END);
    }
  } else {
    elapsed = 14 + (t - trackSince);
  }
  const frac = clamp01(elapsed / tr.dur);
  el.scrubFill.style.width = Math.max(2, frac * 100) + '%';
  el.scrubKnob.style.left = (frac * 100) + '%';
  el.scrubKnob.style.width = el.scrubKnob.style.height = (seeking ? 9 : 0) + 'px';
  el.tElapsed.textContent = timeString(elapsed);
  el.tTotal.textContent = timeString(tr.dur);

  // Transport button hover / press states.
  applyButton(el.btnNext, t, S.ambient - 0.3, [S.ambient + 1.6, S.ambient + 4.4]);
  applyButton(el.btnPrev, t, -99, []);
  applyButton(el.btnPlay, t, -99, []);

  /* --- Header --- */
  el.hClock.textContent = '10:54 PM';
  el.battFill.style.width = (24 * 0.99) + 'px';
  el.battFill.style.background = 'rgba(255,255,255,0.85)';
  el.battPct.textContent = '99%';

  /* --- Calendar --- */
  el.calSub.textContent = t > S.glance + 0.4 ? '11:30 AM · Design review' : 'Nothing for today';

  /* --- Shelf --- */
  const dropped = DROPS.filter(([, at]) => t >= at).length;
  chips.forEach((c, i) => {
    if (i >= dropped) { c.style.display = 'none'; return; }
    c.style.display = 'flex';
    // .transition(.scale(scale: 0.6).combined(with: .opacity)) at snappy(0.3)
    const p = springCurve(t - DROPS[i][1], 0.3, 0);
    c.style.transform = `scale(${lerp(0.6, 1, p)})`;
    c.style.opacity = clamp01(p * 1.6);
  });
  el.shelfEmpty.style.display = dropped ? 'none' : 'flex';
  el.shelfGrid.style.display = dropped ? 'flex' : 'none';
  el.dragAll.style.opacity = dropped >= 2 ? clamp01((t - DROPS[1][1]) / 0.3) : 0;
  el.shelfTrash.style.opacity = dropped >= 1 ? clamp01((t - DROPS[0][1]) / 0.3) : 0;

  // The dashed border brightens while a file hovers over it.
  const targeting = DROPS.some(([start, at]) => t >= at - 0.45 && t < at);
  el.shelfDrop.style.borderColor = `rgba(255,255,255,${targeting ? 0.55 : 0.14})`;

  /* --- Drag ghost --- */
  renderDragGhost(t);

  /* --- Cursor --- */
  const cur = cursorAt(t);
  el.cursor.style.left = cur.x + 'px';
  el.cursor.style.top = cur.y + 'px';
  const cursorVisible = t > S.reveal - 0.4 && t < S.invisible + 0.6 ? 1 : 0;
  el.cursor.style.opacity = cursorVisible;

  /* --- Captions --- */
  renderCaption(t);

  /* --- Cards: opening fade-from-black and the end card --- */
  renderCard(t);
}

/* ---------- Helpers used by render ------------------------------------- */

/** Where the collapsed width last changed, for the wing animation. */
function lastCollapsedChange(t) {
  const changes = [{ at: -10, from: NOTCH_W, to: NOTCH_W }];
  changes.push({ at: MEDIA_START, from: NOTCH_W, to: NOTCH_W + MEDIA_WING * 2 });
  for (const [at] of HUD_EVENTS) {
    changes.push({ at, from: NOTCH_W + MEDIA_WING * 2, to: NOTCH_W + HUD_WING * 2 });
  }
  // HUD dismissals shrink back to the media wings.
  for (const [at] of HUD_EVENTS) {
    changes.push({ at: at + HUD_LINGER, from: NOTCH_W + HUD_WING * 2, to: NOTCH_W + MEDIA_WING * 2 });
  }
  changes.push({ at: MEDIA_END, from: NOTCH_W + MEDIA_WING * 2, to: NOTCH_W });
  const past = changes.filter(c => c.at <= t).sort((a, b) => a.at - b.at);
  return past[past.length - 1];
}

/** The classic notch silhouette minus its top edge (NotchEdgeShape.swift). */
function edgePath(w, h, r) {
  r = Math.min(r, h / 2, w / 2);
  return `M ${w} 0 L ${w} ${h - r} A ${r} ${r} 0 0 1 ${w - r} ${h} ` +
         `L ${r} ${h} A ${r} ${r} 0 0 1 0 ${h - r} L 0 0`;
}

function timeString(s) {
  s = Math.max(0, Math.round(s));
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}

/** Hover highlight + press squish on a transport button. */
function applyButton(node, t, hoverFrom, presses) {
  const hovering = t >= hoverFrom && t < hoverFrom + 6;
  const hp = hovering ? clamp01((t - hoverFrom) / 0.2) : 0;
  let press = 0;
  for (const at of presses) {
    if (t >= at && t < at + 0.15) press = clamp01((t - at) / 0.15);
    else if (t >= at + 0.15 && t < at + 0.3) press = 1 - clamp01((t - at - 0.15) / 0.15);
  }
  node.style.background = `rgba(255,255,255,${0.12 * hp})`;
  node.style.color = `rgba(255,255,255,${lerp(0.85, 1, hp)})`;
  node.style.transform = `scale(${lerp(1, 1.08, hp) * lerp(1, 0.86, press)})`;
}

/** The file gliding toward the shelf, and the stack dragged back out. */
function renderDragGhost(t) {
  const g = el.dragGhost;
  // Incoming drops.
  for (let i = 0; i < DROPS.length; i++) {
    const [start, at] = DROPS[i];
    if (t >= start && t < at + 0.06) {
      const p = easeInOut(clamp01((t - start) / (at - start)));
      const from = [i === 1 ? 340 : i === 2 ? 320 : 300, i === 1 ? 470 : i === 2 ? 500 : 520];
      const x = lerp(from[0], 1000, p), y = lerp(from[1], 132, p);
      g.style.display = 'flex';
      g.style.left = (x - 26) + 'px';
      g.style.top = (y - 26) + 'px';
      g.style.background = FILES[i].fill;
      g.innerHTML = ICON[FILES[i].kind];
      g.style.opacity = clamp01((t - start) / 0.2) * (1 - clamp01((t - at) / 0.06));
      g.style.transform = `scale(${lerp(1, 0.82, p)})`;
      return;
    }
  }
  // The "Drag all" stack heading back out to the desktop.
  if (t >= DRAG_ALL_AT + 0.25 && t < DRAG_ALL_AT + 2.1) {
    const p = easeInOut(clamp01((t - DRAG_ALL_AT - 0.25) / 1.5));
    const x = lerp(1012, 1290, p), y = lerp(110, 470, p);
    g.style.display = 'flex';
    g.style.left = (x - 26) + 'px';
    g.style.top = (y - 26) + 'px';
    g.style.background = FILES[0].fill;
    g.innerHTML = ICON.doc;
    g.style.opacity = clamp01((t - DRAG_ALL_AT - 0.25) / 0.2) *
                      (1 - clamp01((t - DRAG_ALL_AT - 1.75) / 0.35));
    // Fan the stack out behind it, the way NSDraggingItem offsets do.
    g.style.boxShadow = `0 10px 26px rgba(0,0,0,0.55),
      5px -5px 0 -1px rgba(120,140,180,0.9), 10px -10px 0 -2px rgba(90,110,150,0.8)`;
    g.style.transform = 'scale(1)';
    return;
  }
  g.style.display = 'none';
  g.style.boxShadow = '0 10px 26px rgba(0,0,0,0.55)';
}

function renderCaption(t) {
  let active = null;
  for (const c of CAPTIONS) {
    const o = envelope(t, c.at, c.hold, 0.45, 0.45);
    if (o > 0) { active = { c, o }; break; }
  }
  if (!active) { el.caption.style.opacity = 0; return; }
  const { c, o } = active;
  el.caption.style.opacity = o;
  el.caption.style.fontSize = (c.big ? 88 : 46) + 'px';
  el.caption.style.letterSpacing = (c.big ? -2.2 : -0.6) + 'px';
  el.caption.style.fontWeight = c.big ? 700 : 600;
  // Rise a few pixels as it fades in — the only movement captions get.
  const rise = lerp(16, 0, easeOut(clamp01((t - c.at) / 0.6)));
  el.caption.style.transform = `translateY(${rise}px)`;
  el.caption.innerHTML = c.text + (c.sub ? `<span class="sub">${c.sub}</span>` : '');
}

function renderCard(t) {
  // Opening: hold black, then dissolve to the desktop.
  if (t < 1.2) {
    el.card.style.display = 'flex';
    el.card.style.background = '#000';
    el.card.style.opacity = 1 - easeInOut(clamp01((t - 0.35) / 0.85));
    cardItems.forEach(n => n.style.opacity = 0);
    return;
  }
  // End card.
  if (t >= S.endcard - 0.6) {
    el.card.style.display = 'flex';
    el.card.style.background = '#050507';
    el.card.style.opacity = easeInOut(clamp01((t - (S.endcard - 0.6)) / 0.9));
    cardItems.forEach((n, i) => {
      const at = S.endcard + 0.25 + i * 0.16;
      const p = easeOutQuint(clamp01((t - at) / 0.7));
      n.style.opacity = p;
      n.style.transform = `translateY(${lerp(26, 0, p)}px)`;
    });
    return;
  }
  el.card.style.display = 'none';
}

/* ---------- Entry point ------------------------------------------------- */

window.__DURATION = DURATION;
window.__render = t => { render(t); return true; };

// Paint the first frame so opening the file in a browser shows something.
render(0);
