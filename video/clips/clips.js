/* =========================================================================
   Feature clips for the site's card grid.

   Nine short, seamlessly looping clips, one per feature card. Rendered rather
   than screen-recorded, for the same reasons the 66-second film is (see
   ../README.md): every beat lands on cue, it re-renders in minutes, and no
   real album art or personal data ends up on the marketing site.

   Nothing here reads the clock. `window.__render(clip, t)` is a pure function
   of t, so a frame is reproducible and a render can be resumed.

   Every clip starts and ends in the same visual state, so the <video loop>
   wraps without a jump.
   ========================================================================= */

/* ---------- Metrics, from the Swift source ------------------------------ */
const NOTCH_W = 200, NOTCH_H = 32;              // NotchGeometry, 14" MacBook Pro
const MEDIA_WING = 46;                          // NotchMetrics.mediaWingWidth
const WING = { compact: 46, regular: 64, wide: 84 };   // activityWingWidth
const EXP_W = 680, EXP_H = 208;                 // panelWidth default, .columns height
const NARROW_W = 520;                           // AppSettings.panelWidthRange.lowerBound
const R_EXPANDED = 26, R_COLLAPSED = 10;        // Metrics.panelRadius / .collapsedRadius

/* Motion.swift. duration + extraBounce, unscaled (animationSpeed = 1). */
const EXPAND   = { d: 0.40, bounce: 0.10 };
const COLLAPSE = { d: 0.32, bounce: 0.0  };
const ARRIVAL  = { d: 0.34, bounce: 0.35 };
const READOUT  = { d: 0.18, bounce: 0.0  };

const K = 2.0;                                   // points → pixels, matches --k
const px = pt => pt * K;

/* ---------- Maths ------------------------------------------------------- */
const clamp01 = x => (x < 0 ? 0 : x > 1 ? 1 : x);
const lerp = (a, b, t) => a + (b - a) * t;
const easeOut = t => 1 - Math.pow(1 - t, 3);
const easeInOut = t => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);

/** SwiftUI's `.smooth`/`.snappy` spring, as a 0..1 progress curve. */
function spring(elapsed, { d, bounce }) {
  if (elapsed <= 0) return 0;
  if (elapsed >= d * 2.2) return 1;
  const zeta = 1 - (bounce || 0);
  const w = (2 * Math.PI) / d;
  if (zeta < 1) {
    const wd = w * Math.sqrt(1 - zeta * zeta);
    return 1 - Math.exp(-zeta * w * elapsed) *
      (Math.cos(wd * elapsed) + (zeta * w / wd) * Math.sin(wd * elapsed));
  }
  return 1 - Math.exp(-w * elapsed) * (1 + w * elapsed);
}
const springAt = (t, start, cfg) => spring(t - start, cfg);
const ramp = (t, start, dur) => clamp01((t - start) / dur);
const eramp = (t, start, dur, ease = easeInOut) => ease(ramp(t, start, dur));

/** 0 → 1 → 0 across a hold, with soft shoulders. For things that appear and go. */
function envelope(t, start, hold, inD = 0.28, outD = 0.28) {
  if (t < start) return 0;
  const end = start + hold;
  if (t > end + outD) return 0;
  if (t < start + inD) return easeOut(ramp(t, start, inD));
  if (t > end) return 1 - easeInOut(ramp(t, end, outD));
  return 1;
}

function mixHex(a, b, t) {
  const p = h => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16));
  const [r1, g1, b1] = p(a), [r2, g2, b2] = p(b);
  const c = (x, y) => Math.round(lerp(x, y, t)).toString(16).padStart(2, '0');
  return `#${c(r1, r2)}${c(g1, g2)}${c(b1, b2)}`;
}

/* ---------- Handles ----------------------------------------------------- */
const $ = id => document.getElementById(id);
const el = {};
['stage', 'panelWrap', 'panel', 'edge', 'glow', 'strip', 'stripLeft', 'stripRight',
 'expanded', 'artMain', 'artAura', 'scrubFill', 'tElapsed', 'hClock', 'wxPill',
 'gear', 'colMedia', 'colCal', 'colTools', 'div1', 'div2', 'toolTabs', 'toolBody',
 'calDays', 'calSub', 'keys', 'cursor', 'backdrop', 'menubar']
  .forEach(id => (el[id] = $(id)));

/* Synthetic cover art — a gradient, so nothing copyrighted ships. */
const ART = 'linear-gradient(135deg, #ff5f8f 0%, #a45cff 48%, #4bc0ff 100%)';
const ART_ACCENT = '#c86bff';

el.artMain.style.background = ART;
el.artAura.style.background = ART;

/* The week strip: seven days centred on today. */
(function buildCalendar() {
  const dows = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
  el.calDays.innerHTML = '';
  for (let i = -3; i <= 3; i++) {
    const d = document.createElement('div');
    d.className = 'day' + (i === 0 ? ' today' : '');
    d.innerHTML = `<span class="dow">${dows[(i + 10) % 7]}</span>` +
                  `<span class="num mono-digit">${10 + i}</span>`;
    el.calDays.appendChild(d);
  }
})();

/* ---------- Stage primitives -------------------------------------------- */

/** Size the panel. `p` is 0 (collapsed strip) → 1 (fully expanded). */
function panel(width, height, radius) {
  el.panel.style.width = px(width) + 'px';
  el.panel.style.height = px(height) + 'px';
  el.panel.style.borderBottomLeftRadius = px(radius) + 'px';
  el.panel.style.borderBottomRightRadius = px(radius) + 'px';
  el.edge.style.opacity = radius > R_COLLAPSED + 2 ? 1 : 0;
}

/**
 * Interpolate between the collapsed strip and the expanded panel.
 * One shape the whole way — the app never swaps one view for another, and a
 * cross-fade here would lose exactly the quality the clips exist to show.
 */
function morph(p, stripWidth = NOTCH_W, expandedWidth = EXP_W) {
  const w = lerp(stripWidth, expandedWidth, p);
  const h = lerp(NOTCH_H, EXP_H, p);
  const r = lerp(R_COLLAPSED, R_EXPANDED, p);
  panel(w, h, r);
  // Content lags the container slightly, the way NotchEntrance does.
  const content = clamp01((p - 0.35) / 0.5);
  el.expanded.style.opacity = content;
  el.expanded.style.display = p > 0.02 ? 'flex' : 'none';
  el.strip.style.opacity = clamp01(1 - p * 4);
  el.strip.style.display = p > 0.28 ? 'none' : 'flex';
  return { w, h };
}

/** The artwork-coloured glow hugging the panel edge. */
function glow(strength, colour = ART_ACCENT, w = EXP_W, h = EXP_H) {
  const g = el.glow;
  if (strength <= 0.001) { g.style.opacity = 0; return; }
  g.style.opacity = strength;
  g.style.width = px(w + 26) + 'px';
  g.style.height = px(h + 26) + 'px';
  g.style.boxShadow = `0 0 ${px(46)}px ${px(6)}px ${colour}`;
  g.style.background = 'transparent';
  g.style.border = `${Math.max(1, px(1.2))}px solid ${colour}`;
  g.style.opacity = strength * 0.85;
}

/**
 * Push the camera in. A clip that never opens the panel is filming a 330pt
 * strip in a 800pt frame, which at card size reads as an empty rectangle.
 */
const FRAME_W = 1600, FRAME_H = 640;

/**
 * Zoom so a panel of `widthPt` fills the frame, bounded by height.
 *
 * Without this a clip showing one module sat at whatever size 680pt happened
 * to be, with the content occupying a third of the frame — which is why the
 * cards were hard to read.
 */
function fill(widthPt, headroom = 0.95) {
  const byWidth = (FRAME_W * headroom) / (widthPt * K);
  const byHeight = (FRAME_H * 0.90) / (EXP_H * K);
  zoom(Math.min(byWidth, byHeight));
}

function zoom(scale) {
  el.stage.style.transform = `translateX(-50%) scale(${scale})`;
  el.stage.style.transformOrigin = '50% 0';
}

/** Fill the collapsed strip's two sides. */
function strip(left, right) {
  el.stripLeft.innerHTML = left ?? '';
  el.stripRight.innerHTML = right ?? '';
}

/** Show or hide the three expanded columns. */
function columns({ media = true, cal = true, tools = true } = {}) {
  const shown = [media, cal, tools].filter(Boolean).length;
  document.querySelector('.body-row').classList.toggle('solo', shown === 1);
  el.colMedia.style.display = media ? 'flex' : 'none';
  el.colCal.style.display = cal ? 'flex' : 'none';
  el.colTools.style.display = tools ? 'flex' : 'none';
  el.div1.style.display = media && (cal || tools) ? 'block' : 'none';
  el.div2.style.display = cal && tools ? 'block' : 'none';
}

const ICONS = {
  music: `<svg width="22" height="22" viewBox="0 0 20 20" fill="currentColor"><path d="M16 2.4 7.4 4.2v8.5a3 3 0 1 0 1.6 2.6V7.2l5.4-1.1v5a3 3 0 1 0 1.6 2.6V2.4z"/></svg>`,
  bolt: `<svg width="22" height="22" viewBox="0 0 20 20" fill="#5ee07a"><path d="M11.4 1.6 4.2 11h4.3l-.9 7.4L15.8 9h-4.3z"/></svg>`,
  timer: `<svg width="22" height="22" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.7"><circle cx="10" cy="11.4" r="6.6"/><path d="M10 8.2v3.4l2.2 1.5M7.6 1.8h4.8"/></svg>`,
  speaker: `<svg width="22" height="22" viewBox="0 0 20 20" fill="currentColor"><path d="M9.4 3.2 5.6 6.4H2.8v7.2h2.8l3.8 3.2z"/><path d="M12.4 7a4 4 0 0 1 0 6" stroke="currentColor" stroke-width="1.5" fill="none" stroke-linecap="round"/><path d="M14.8 4.6a7.2 7.2 0 0 1 0 10.8" stroke="currentColor" stroke-width="1.5" fill="none" stroke-linecap="round"/></svg>`,
  clip: `<svg width="18" height="18" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6"><rect x="7" y="2.6" width="10.4" height="13.6" rx="2.2"/><path d="M13.6 16.2v1.2H2.6V5.6h1.4"/></svg>`,
  tray: `<svg width="18" height="18" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6"><path d="M2.4 12h4l1.2 2.2h4.8L13.6 12h4M2.4 12l2.2-7.4h10.8L17.6 12v4.2a1.4 1.4 0 0 1-1.4 1.4H3.8a1.4 1.4 0 0 1-1.4-1.4z"/></svg>`,
  clock: `<svg width="18" height="18" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6"><circle cx="10" cy="10" r="7.4"/><path d="M10 5.6V10l3 2"/></svg>`,
  check: `<svg width="18" height="18" viewBox="0 0 20 20" fill="none" stroke="#5ee07a" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M4.4 10.6 8 14.2l7.6-8"/></svg>`,
  link: `<svg width="18" height="18" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6"><path d="M8.4 11.6a3.4 3.4 0 0 0 5 .4l2.4-2.4a3.4 3.4 0 0 0-4.8-4.8l-1.4 1.4M11.6 8.4a3.4 3.4 0 0 0-5-.4L4.2 10.4a3.4 3.4 0 0 0 4.8 4.8l1.4-1.4"/></svg>`,
  text: `<svg width="18" height="18" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><path d="M3.4 5h13.2M3.4 10h13.2M3.4 15h8"/></svg>`,
};

/** Four equaliser bars that breathe while something is playing. */
function waveform(t, playing = true) {
  const base = [5, 11, 7, 9];
  return '<div style="display:flex;align-items:flex-end;gap:' + px(2) + 'px;height:' + px(13) + 'px">' +
    base.map((h, i) => {
      const v = playing
        ? h * (0.45 + 0.55 * (0.5 + 0.5 * Math.sin(t * 7.5 + i * 1.7)))
        : 3;
      return `<i style="display:block;width:${px(2.2)}px;height:${px(v)}px;` +
             `border-radius:${px(1.1)}px;background:#fff"></i>`;
    }).join('') + '</div>';
}

const WX_PILL_HTML = document.getElementById('wxPill').innerHTML;

function reset() {
  resetNew();
  el.wxPill.innerHTML = WX_PILL_HTML;
  el.wxPill.style.opacity = 1;
  el.gear.style.opacity = 1;
  el.hClock.style.opacity = 1;
  const outRow = document.getElementById('outRow');
  if (outRow) outRow.style.opacity = 0;
  el.keys.innerHTML = '';
  el.keys.style.transform = 'translateX(-50%)';
  el.cursor.style.opacity = 0;
  el.glow.style.opacity = 0;
  el.toolBody.innerHTML = '';
  el.toolTabs.innerHTML = '';
  el.stage.style.transform = 'translateX(-50%)';
  columns();
}

/** The tools column's tab row: the active one names itself, the rest are glyphs. */
function tabs(active) {
  const list = [['shelf', ICONS.tray, 'Shelf'], ['clip', ICONS.clip, 'Clipboard'], ['timer', ICONS.clock, 'Timer']];
  el.toolTabs.innerHTML = list.map(([id, svg, name]) =>
    `<span class="tab${id === active ? ' on' : ''}">${svg}` +
    (id === active ? `<span class="name">${name}</span>` : '') + '</span>'
  ).join('') + '<span class="sp"></span>';
}

/* =========================================================================
   The clips
   ========================================================================= */
const CLIPS = {};

/* 1. Now Playing — the peek grows into the panel and the track plays on. */
CLIPS['now-playing'] = { duration: 6.0, poster: 3.4, render(t) {
  reset();
  columns({ media: true, cal: false, tools: false });
  const open = springAt(t, 1.0, EXPAND);
  const shut = springAt(t, 4.6, COLLAPSE);
  const p = clamp01(open - shut);
  fill(lerp(NOTCH_W + MEDIA_WING * 2, NARROW_W, easeInOut(p)));
  morph(p, NOTCH_W + MEDIA_WING * 2, NARROW_W);
  strip(`<div id="miniArt" style="background:${ART}"></div>`, waveform(t));
  glow(p * 0.5, ART_ACCENT);
  const played = 0.38 + 0.055 * t;
  el.scrubFill.style.width = (played * 100) + '%';
  const secs = Math.floor(played * 204);
  el.tElapsed.textContent = `${Math.floor(secs / 60)}:${String(secs % 60).padStart(2, '0')}`;
}};

/* 2. Ambient glow — the panel takes the artwork's colour and drifts with it. */
CLIPS['ambient-glow'] = { duration: 6.0, poster: 3.0, render(t) {
  reset();
  columns({ media: true, cal: false, tools: false });
  fill(NARROW_W);
  morph(1, NOTCH_W, NARROW_W);
  // A slow loop through three album accents, returning to the first.
  const stops = ['#c86bff', '#ff5f8f', '#4bc0ff', '#c86bff'];
  const u = (t / 6) * 3;
  const i = Math.min(2, Math.floor(u));
  const colour = mixHex(stops[i], stops[i + 1], easeInOut(u - i));
  glow(0.55 + 0.2 * Math.sin(t * 1.6), colour);
  el.artMain.style.background =
    `linear-gradient(135deg, ${colour} 0%, #a45cff 48%, #4bc0ff 100%)`;
  el.artAura.style.background = el.artMain.style.background;
  el.scrubFill.style.width = '46%';
}};

/* 3. The Shelf — three files land, one after another. */
CLIPS['shelf'] = { duration: 6.0, poster: 4.4, render(t) {
  reset();
  columns({ media: false, cal: false, tools: true });
  fill(NARROW_W);
  morph(1, NOTCH_W, NARROW_W);
  tabs('shelf');
  const files = [['#ff8a5c', 'PDF'], ['#5cc8ff', 'PNG'], ['#b78bff', 'ZIP']];
  const landed = files.map((f, i) => springAt(t, 1.2 + i * 0.85, ARRIVAL));
  const any = landed.some(v => v > 0.01);
  el.toolBody.innerHTML =
    `<div class="drop" style="border-color:rgba(255,255,255,${any ? 0.14 : 0.3})">` +
    (any
      ? '<div class="grid">' + files.map(([c, label], i) => {
          const s = landed[i];
          if (s < 0.01) return '';
          return `<span class="chip" style="background:${c};transform:scale(${0.6 + 0.4 * s});opacity:${clamp01(s * 1.4)}">${label}</span>`;
        }).join('') + '</div>'
      : `<div class="empty">${ICONS.tray}<span>Drop files here</span></div>`) +
    '</div>';
}};

/* 4. Your day, at a glance — the week and the next event. */
CLIPS['at-a-glance'] = { duration: 6.0, poster: 3.0, render(t) {
  reset();
  columns({ media: false, cal: true, tools: false });
  fill(EXP_W);
  const open = springAt(t, 0.8, EXPAND);
  const shut = springAt(t, 4.8, COLLAPSE);
  morph(clamp01(open - shut));
  // The header pills arrive a beat after the panel, as NotchEntrance staggers.
  el.wxPill.style.opacity = eramp(t, 1.25, 0.4, easeOut);
  el.gear.style.opacity = eramp(t, 1.35, 0.4, easeOut);
}};

/* 5. Battery — plugging in gets one brief acknowledgement, then the panel
      shows where the charge lives the rest of the time. */
CLIPS['battery'] = { duration: 7.0, poster: 4.8, render(t) {
  reset();
  columns({ media: true, cal: true, tools: false });

  const open = springAt(t, 3.6, EXPAND);
  const shut = springAt(t, 6.0, COLLAPSE);
  const p = clamp01(open - shut);
  // In close on the peek, pulling back as the panel opens so it is never
  // cropped. A 328pt strip filmed in an 800pt frame is an empty rectangle.
  zoom(lerp(2.1, Math.min((FRAME_W * 0.95) / (EXP_W * K), (FRAME_H * 0.90) / (EXP_H * K)), easeInOut(p)));

  const peek = envelope(t, 1.0, 1.6, 0.3, 0.3) * (1 - p);
  const wing = springAt(t, 1.0, READOUT) - springAt(t, 2.9, READOUT);
  morph(p, lerp(NOTCH_W, NOTCH_W + WING.regular * 2, clamp01(wing)));

  const pop = 0.4 + 0.6 * springAt(t, 1.0, ARRIVAL);
  strip(
    `<span class="act" style="opacity:${peek};transform:scale(${pop})"><span class="glyph">${ICONS.bolt}</span></span>`,
    `<span class="act" style="opacity:${peek}"><span class="value mono-digit">82%</span></span>`
  );

  // The header's battery pill, which is where the charge lives once open.
  el.wxPill.innerHTML =
    `<span style="display:inline-flex;align-items:center;gap:${px(4)}px">` +
    `<span style="position:relative;width:${px(26)}px;height:${px(12)}px;` +
      `border:1px solid rgba(255,255,255,0.5);border-radius:${px(3)}px;display:inline-block">` +
      `<b style="position:absolute;left:${px(1.5)}px;top:${px(1.5)}px;bottom:${px(1.5)}px;` +
      `width:${px(19)}px;background:#5ee07a;border-radius:${px(1.5)}px"></b></span>` +
    `<span class="temp mono-digit">82%</span></span>`;
  el.wxPill.style.opacity = eramp(t, 3.75, 0.4, easeOut) * (1 - springAt(t, 6.0, COLLAPSE));
}};

/* 6. Timer — the countdown takes over the collapsed strip, then the panel. */
CLIPS['timer'] = { duration: 7.0, poster: 5.0, render(t) {
  reset();
  columns({ media: false, cal: false, tools: true });
  const open = springAt(t, 3.2, EXPAND);
  const shut = springAt(t, 5.9, COLLAPSE);
  const p = clamp01(open - shut);
  fill(NARROW_W);
  morph(p, NOTCH_W + WING.regular * 2, NARROW_W);
  tabs('timer');

  // 25:00 counting down, fast enough to see it move.
  const remaining = Math.max(0, 1500 - t * 14);
  const mm = Math.floor(remaining / 60), ss = Math.floor(remaining % 60);
  const clock = `${mm}:${String(ss).padStart(2, '0')}`;
  const progress = 1 - remaining / 1500;

  strip(
    `<span class="act"><span class="glyph">${ICONS.timer}</span></span>`,
    `<span class="act"><span class="value mono-digit">${clock}</span></span>`
  );

  const R = 24, C = 2 * Math.PI * R;
  el.toolBody.innerHTML =
    `<div class="timer">
       <div class="ring">
         <svg viewBox="0 0 54 54">
           <circle cx="27" cy="27" r="${R}" fill="none" stroke="rgba(255,255,255,0.12)" stroke-width="4"/>
           <circle cx="27" cy="27" r="${R}" fill="none" stroke="var(--accent)" stroke-width="4"
                   stroke-linecap="round" stroke-dasharray="${C}"
                   stroke-dashoffset="${C * (1 - progress)}"/>
         </svg>
         <span class="num rounded mono-digit">${clock}</span>
       </div>
       <div class="tbtns">
         <span class="tbtn"><svg width="16" height="16" viewBox="0 0 20 20" fill="#fff"><path d="M6.6 4.2h2.2v11.6H6.6zM11.2 4.2h2.2v11.6h-2.2z"/></svg></span>
         <span class="tbtn"><svg width="15" height="15" viewBox="0 0 20 20" fill="none" stroke="#fff" stroke-width="1.7"><circle cx="10" cy="10" r="7"/><path d="M10 6v4l2.6 1.6"/></svg></span>
       </div>
     </div>`;
}};

/* 7. Clipboard — a row is clicked and confirms. */
CLIPS['clipboard'] = { duration: 6.5, poster: 3.2, render(t) {
  reset();
  columns({ media: false, cal: false, tools: true });
  fill(NARROW_W);
  morph(1, NOTCH_W, NARROW_W);
  tabs('clip');

  const rows = [
    [ICONS.link, 'https://aloenotch.com'],
    [ICONS.text, 'const notch = useNotch()'],
    [ICONS.text, 'Design review, 2:30'],
    [ICONS.text, 'xnucade'],
  ];
  // Reach the second row, click it, hold the confirmation, then leave.
  const reach = eramp(t, 1.0, 0.9, easeOut);
  const clicked = t > 2.0;
  const copied = t > 2.05 && t < 4.6;
  const leave = eramp(t, 4.9, 0.7, easeOut);

  el.toolBody.innerHTML = '<div class="cliplist">' + rows.map(([g, text], i) => {
    const hot = i === 1 && clicked && !leave;
    const bg = hot ? 0.18 : (i === 1 && reach > 0.6 && !leave ? 0.10 : 0.04);
    return `<div class="cliprow" style="background:rgba(255,255,255,${bg})">
              <span class="g">${copied && i === 1 ? ICONS.check : g}</span>
              <span class="t">${copied && i === 1 ? 'Copied' : text}</span>
            </div>`;
  }).join('') + '</div>';

  // The pointer arrives, presses, and withdraws.
  const x = lerp(px(NARROW_W) * 0.32, px(NARROW_W) * 0.62, reach) + lerp(0, px(120), leave);
  const y = lerp(px(EXP_H) * 1.05, px(EXP_H) * 0.56, reach) + lerp(0, px(70), leave);
  const press = t > 2.0 && t < 2.16 ? 0.88 : 1;
  // Panel-local coordinates now that the cursor lives inside the panel.
  el.cursor.style.opacity = clamp01(reach * 1.5) * (1 - leave);
  el.cursor.style.left = x + 'px';
  el.cursor.style.top = y + 'px';
  el.cursor.style.transform = `scale(${press})`;
}};

/* 8. The shortcut — a key press opens it, another closes it. */
CLIPS['shortcut'] = { duration: 6.0, poster: 3.0, render(t) {
  reset();
  columns({ media: true, cal: true, tools: false });
  fill(EXP_W);
  const open = springAt(t, 1.35, EXPAND);
  const shut = springAt(t, 4.3, COLLAPSE);
  morph(clamp01(open - shut));

  // Two presses: one to open, one to close.
  const down = (t > 1.2 && t < 1.42) || (t > 4.15 && t < 4.37);
  const show = envelope(t, 0.7, 4.0, 0.35, 0.5);
  // Below the panel, not over it. The expanded panel reaches 416px down a
  // 520px frame, so anything anchored more than ~100px up lands on the
  // content it is supposed to be opening.
  el.keys.style.bottom = '16px';
  el.keys.style.top = 'auto';
  el.keys.style.transform = 'translateX(-50%) scale(0.8)';
  el.keys.style.transformOrigin = '50% 100%';
  el.keys.style.opacity = show;
  el.keys.innerHTML = ['⌃', '⌥', 'N'].map(c =>
    `<span class="cap" style="transform:translateY(${down ? px(3) : 0}px);` +
    `background:${down ? 'linear-gradient(180deg,rgba(120,180,255,0.5),rgba(90,150,255,0.3))'
                       : 'linear-gradient(180deg,rgba(255,255,255,0.16),rgba(255,255,255,0.07))'}">${c}</span>`
  ).join('');
}};

/* 9. Invisible by design — it hugs the cutout, then proves it can open. */
CLIPS['invisible'] = { duration: 6.0, poster: 1.0, render(t) {
  reset();
  columns({ media: true, cal: true, tools: false });
  // Mostly closed. The one brief opening is what shows the strip really is the
  // notch and not a bar drawn near it.
  const open = springAt(t, 2.4, EXPAND);
  const shut = springAt(t, 3.9, COLLAPSE);
  const p = clamp01(open - shut);
  // Pushed in on the closed strip, pulling back as it opens so the panel is
  // never cropped. The move itself is what shows the strip *is* the cutout.
  zoom(lerp(1.9, Math.min((FRAME_W * 0.95) / (EXP_W * K), (FRAME_H * 0.90) / (EXP_H * K)), easeInOut(p)));
  morph(p);
  strip('', '');
  // A soft sweep of light across the bezel, so a static black strip still
  // reads as a rendered frame rather than a dropped one.
  const sweep = (t % 6) / 6;
  el.menubar.style.background =
    `linear-gradient(90deg, rgba(255,255,255,0.04) 0%, rgba(255,255,255,0.04) ${sweep * 100 - 18}%,` +
    ` rgba(255,255,255,0.13) ${sweep * 100}%, rgba(255,255,255,0.04) ${sweep * 100 + 18}%, rgba(255,255,255,0.04) 100%)`;
}};

/* 10. Sound output — the header swaps for the device picker. */
CLIPS['sound-output'] = { duration: 6.0, poster: 3.8, render(t) {
  reset();
  columns({ media: true, cal: false, tools: false });
  fill(NARROW_W);
  morph(1, NOTCH_W, NARROW_W);
  const swap = envelope(t, 1.6, 2.6, 0.32, 0.32);
  el.wxPill.style.opacity = 1 - swap;
  el.gear.style.opacity = 1 - swap;
  // The device chips ride in from the right, where the speaker button is.
  const chips = ['MacBook Pro Speakers', 'AirPods Pro'];
  const picked = t > 3.4 ? 1 : 0;
  el.hClock.style.opacity = 1 - swap;
  let row = document.getElementById('outRow');
  if (!row) {
    row = document.createElement('div');
    row.id = 'outRow';
    row.style.cssText = `position:absolute;left:${px(16)}px;right:${px(16)}px;top:${px(38)}px;display:flex;gap:${px(6)}px;align-items:center`;
    el.expanded.appendChild(row);
  }
  row.style.opacity = swap;
  row.style.transform = `translateX(${lerp(px(26), 0, swap)}px)`;
  row.innerHTML = `<span class="icon-btn">${ICONS.speaker}</span>` + chips.map((name, i) => {
    const on = i === picked;
    return `<span class="pill" style="background:${on ? 'rgba(71,153,255,0.20)' : 'rgba(255,255,255,0.07)'};` +
           `color:${on ? 'var(--accent)' : 'rgba(255,255,255,0.75)'}">` +
           `<span class="temp">${name}</span></span>`;
  }).join('');
}};

/* =========================================================================
   New in 0.13 — glass, lyrics, the live equalizer, the split island,
   gestures, Join, and the display picker.
   ========================================================================= */
const N = {};
['wall', 'frost', 'patch', 'rim', 'seg', 'segKnob', 'bubble', 'bubbleIn', 'bridge',
 'fingers', 'displays', 'artist', 'title'].forEach(id => (N[id] = $(id)));
const ARTIST_HTML = N.artist.innerHTML;
const TITLE_TEXT = N.title.textContent;
const CALSUB_HTML = el.calSub.innerHTML;
const META = document.querySelector('.media .meta');

const TRACK_B = { title: 'Tidal Rooms', artist: 'Marlow Vane', glow: '#3fd6c6',
  art: 'linear-gradient(135deg, #3ee6c1 0%, #2a8cff 55%, #1b2a6b 100%)' };

/* GlassRim.colors for the cover's accent (#c86bff, hue 279°): the accent,
   its neighbours ±0.14 round the wheel, and a pale highlight. */
N.rim.style.setProperty('--c1', 'hsl(279 100% 72%)');
N.rim.style.setProperty('--c2', 'hsl(329 100% 70%)');
N.rim.style.setProperty('--c3', 'hsl(279 60% 94%)');
N.rim.style.setProperty('--c4', 'hsl(229 100% 70%)');

function resetNew() {
  N.wall.style.opacity = 0;
  el.panel.style.background = '';
  N.frost.style.opacity = 0;
  N.patch.style.opacity = 0;
  N.rim.style.opacity = 0;
  N.seg.style.display = 'none';
  N.bubble.style.display = 'none';
  N.bridge.style.display = 'none';
  N.fingers.style.opacity = 0;
  N.displays.style.display = 'none';
  el.stage.style.display = '';
  el.menubar.style.display = '';
  el.menubar.style.background = '';
  N.artist.innerHTML = ARTIST_HTML;
  N.artist.style.cssText = '';
  N.title.textContent = TITLE_TEXT;
  META.style.cssText = '';
  el.artMain.style.cssText = '';
  el.artMain.style.background = ART;
  el.artAura.style.background = ART;
  el.calSub.innerHTML = CALSUB_HTML;
  el.calSub.parentElement.style.color = '';
  N.seg.querySelector('.lbl').textContent = 'Notch style';
  const opts = N.seg.querySelectorAll('.track span');
  opts[0].textContent = 'Solid'; opts[1].textContent = 'Glass';
  opts.forEach(o => (o.style.width = ''));
  N.segKnob.style.width = '';
}

/** 0 = the solid black panel, 1 = glass. The rim drifts on a sine so the
    loop wraps without a jump (the app turns it once every 18s). */
function glass(g, t, period) {
  el.panel.style.background = `rgba(0,0,0,${1 - g})`;
  N.frost.style.opacity = g;
  N.patch.style.opacity = g;
  N.rim.style.opacity = g;
  N.rim.style.setProperty('--ang', `${200 + 70 * Math.sin((2 * Math.PI * t) / period)}deg`);
}

const miniArt = (art = ART) => `<div id="miniArt" style="background:${art}"></div>`;

/* 11. A glass notch — the panel frosts the wallpaper, then goes back. */
CLIPS['glass'] = { duration: 7.0, poster: 3.6, render(t) {
  reset();
  columns({ media: true, cal: true, tools: false });
  N.wall.style.opacity = 1;
  fill(EXP_W);
  morph(1);
  const knob = clamp01(springAt(t, 1.0, READOUT) - springAt(t, 4.8, READOUT));
  const g = eramp(t, 1.15, 0.8) - eramp(t, 4.95, 0.8);
  glass(g, t, 7.0);
  N.seg.style.display = 'flex';
  N.segKnob.style.transform = `translateX(${116 * knob}px)`;
  el.scrubFill.style.width = '42%';
}};

/* 12. Lyrics — the line being sung takes the artist's place. */
const LYRICS = ['Coins in the slot and the lights come on',
                'We were high scores on a Friday night',
                'Pixel hearts in a neon glow',
                'Press start, we’re never letting go'];
CLIPS['lyrics'] = { duration: 7.5, poster: 2.4, render(t) {
  reset();
  columns({ media: true, cal: false, tools: false });
  fill(NARROW_W);
  morph(1, NOTCH_W, NARROW_W);
  glow(0.5, ART_ACCENT, NARROW_W);
  el.scrubFill.style.width = '42%';
  el.tElapsed.textContent = '1:26';
  const changes = [1.7, 3.4, 5.1, 6.8];
  const n = changes.filter(c => t >= c).length;
  const u = n ? eramp(t, changes[n - 1], 0.42, easeOut) : 1;
  const cur = LYRICS[n % 4], prev = LYRICS[(n + 3) % 4];
  const line = (text, y, o) =>
    `<span style="position:absolute;left:0;top:0;white-space:nowrap;color:rgba(255,255,255,0.95);` +
    `transform:translateY(${y}%);opacity:${o}">${text}</span>`;
  N.artist.style.cssText = 'position:relative;height:1.35em;overflow:hidden;text-overflow:clip';
  N.artist.innerHTML = (u < 1 ? line(prev, -110 * u, 1 - u) : '') + line(cur, 110 * (1 - u), u);
}};

/* 13. The live equalizer — four bands of a real track, at the edges
       SpectrumBands.swift uses, with the meter's attack and decay. */
const EQ = '223817212332141819272222215455491760464115513834544352808552449172663776607231645161265443512245364318383036153225572845218723381894203218791727199217221677191913651616115513181246324025393733313231283527322337333220393927174040231444552820467937343993312933972624388222203269181735581514414816123541242429344777323549922729417828333565284640552456344627472839234024322733203630351730252914252525152721372238225119322555163721564448187937401591313412772628108122240968192007571617064813140540171206341410052812080424100703201106044451470348433904403633044130280447252304392120033318160328151404321312043611100430090803302721063923180841191509341613093718180731212508381821073215246745517656484364474836713952397640564064345633543847284532543252277079853482937140697860425866504349555543524647364439393037334478494882664140895545347446472862396178883375937428639762315382522655696737465856423948473542414037453433315537283760312431504064796773756677916355867753477264453961543733514531285638262947324432403847363332393928273340232839336678813683936830707857485965837649557064524672545339614544335138372743323923363342193028354978338084664093715541975946449850393799423338833528387030237559435863493648535530414459253437502729315931243470262034592717297369743288906234749652286281443352683728445731334548262745402276515576644347645436395445403345386262753271886334789553298080453267676237575652384847444040403733343331353428263635242230302844785360836664866955758858466374493953624139625235335244293763374331533152384426443237223737312531316277793479926629677855335665867847789566589380556178674652655639435547334446403337393335414165357082893784697540715863335948533969574433704837375940315749507180414259673536505739304248433335403638303438322536412721305659763786877943909566447580564563674738705739405947334059402880605074675142805743366748363057404655663476867328868661347272513461616438515154434343454536363845303632383531273929262233332619795452756670856355748553477672443964603733655131345443263546363429553950394640424439333537322830395469783968906640577555344863667963538967674575567038634759325340492744334122373435193134293158297877813693646842975457';
function eqAt(sec) {
  const f = sec * 30, i = Math.floor(f), a = f - i;
  const get = (j, b) => Number(EQ.substr((Math.min(269, Math.max(0, j)) * 4 + b) * 2, 2)) / 99;
  return [0, 1, 2, 3].map(b => lerp(get(i, b), get(i + 1, b), a));
}
CLIPS['live-eq'] = { duration: 6.0, poster: 2.5, render(t) {
  reset();
  const S = 1.0, D = 6.0, X = 0.6;
  let lv = eqAt(S + t);
  // Cross-fade the tail into the frames just before the start, so it loops.
  if (t > D - X) {
    const a = easeInOut((t - (D - X)) / X), early = eqAt(S + t - D);
    lv = lv.map((v, i) => lerp(v, early[i], a));
  }
  // The desktop behind it, so a strip hanging from the top of the screen
  // isn't a black bar in an empty frame.
  N.wall.style.opacity = 0.6;
  morph(0, NOTCH_W + MEDIA_WING * 2);
  zoom(2.5);
  const tint = mixHex(ART_ACCENT, '#ffffff', 0.35);
  // WaveformGlyph: 2.5pt capsules, 3pt at rest, 12pt full, 2pt apart.
  const bars = lv.map(v =>
    `<i style="display:block;width:${px(2.5)}px;height:${px(3 + 9 * v)}px;border-radius:${px(1.25)}px;` +
    `background:${tint};box-shadow:0 0 ${px(4)}px ${ART_ACCENT}"></i>`).join('');
  strip(miniArt(), `<div style="display:flex;align-items:center;gap:${px(2)}px;height:${px(12)}px">${bars}</div>`);
}};

/* 14. The split island — a running timer pinches off into its own bubble
       beside the music, then merges back. */
CLIPS['split-island'] = { duration: 7.0, poster: 3.4, render(t) {
  reset();
  const SW = NOTCH_W + MEDIA_WING * 2, BW = 74, GAP = 9, STRETCH = GAP - 1.5, H = NOTCH_H;
  N.wall.style.opacity = 0.6;
  morph(0, SW);
  strip(miniArt(), waveform(t));
  const out = springAt(t, 1.2, ARRIVAL) - springAt(t, 5.2, COLLAPSE);
  const gap = lerp(-BW, GAP, out);
  // Pan with the bubble so the pair ends up centred.
  const s = 1.9, shift = px((SW / 2 + GAP + BW - SW / 2) / 2) * s * clamp01(out);
  el.stage.style.transform = `translateX(calc(-50% - ${shift}px)) scale(${s})`;
  N.bubble.style.display = 'flex';
  N.bubble.style.zIndex = -1;
  N.bubble.style.width = px(BW) + 'px';
  N.bubble.style.left = `calc(100% + ${px(gap)}px)`;
  const left = Math.max(0, 300 - Math.floor(t));
  N.bubbleIn.style.opacity = clamp01((gap + 20) / 20);
  N.bubbleIn.innerHTML =
    `<span class="glyph" style="display:flex;color:#ffb454">${ICONS.timer.replace(/22/g, '18')}</span>` +
    `<span class="value mono-digit" style="font-size:${px(12)}px;font-weight:600">${Math.floor(left / 60)}:${String(left % 60).padStart(2, '0')}</span>`;
  // The bridge: full while they overlap, its waist thinning as the gap opens.
  const waist = gap <= 0 ? H : H * (1 - gap / STRETCH);
  if (waist >= 2.5) {
    const f = 12, W = Math.max(0, gap) + 2 * f, xR = W - 3, xL = 3, xm = W / 2;
    N.bridge.style.display = 'block';
    N.bridge.style.zIndex = -1;
    N.bridge.style.left = `calc(100% - ${px(f)}px)`;
    N.bridge.style.width = px(W) + 'px';
    N.bridge.style.height = px(H) + 'px';
    N.bridge.setAttribute('viewBox', `0 0 ${W} ${H}`);
    N.bridge.firstElementChild.setAttribute('d',
      `M0 0H${W}V${H}H${xR}C${xR} ${waist} ${xm + (xR - xm) * 0.35} ${waist} ${xm} ${waist}` +
      `C${xm - (xm - xL) * 0.35} ${waist} ${xL} ${waist} ${xL} ${H}H0Z`);
  }
}};

/* 15. Swipe — two fingers down to open, sideways to skip, up to close. */
CLIPS['swipe'] = { duration: 8.0, poster: 3.0, render(t) {
  reset();
  columns({ media: true, cal: false, tools: false });
  const SW = NOTCH_W + MEDIA_WING * 2;
  const p = clamp01(springAt(t, 1.3, EXPAND) - springAt(t, 6.0, COLLAPSE));
  fill(lerp(SW, NARROW_W, easeInOut(p)));
  morph(p, SW, NARROW_W);
  strip(miniArt(), waveform(t));
  el.scrubFill.style.width = '42%';

  // Next on a swipe left, back on a swipe right: the loop ends where it began.
  const fwd = eramp(t, 2.85, 0.4), back = eramp(t, 4.45, 0.4);
  const u = fwd - back;                                  // 0 = A, 1 = B
  const moving = (fwd > 0 && fwd < 1) ? -1 : (back > 0 && back < 1) ? 1 : 0;
  const phase = moving === -1 ? fwd : back;
  const showB = u >= 0.5;
  const tr = showB ? TRACK_B : { title: TITLE_TEXT, art: ART, glow: ART_ACCENT };
  N.title.textContent = tr.title;
  N.artist.textContent = showB ? TRACK_B.artist : 'Kade & the Lantern';
  el.artMain.style.background = tr.art;
  el.artAura.style.background = tr.art;
  if (moving) {
    const half = phase < 0.5;
    const o = half ? 1 - phase * 2 : phase * 2 - 1;
    const x = (half ? phase * 2 : (phase * 2 - 1) - 1) * px(26) * moving;
    META.style.cssText = `transform:translateX(${x}px);opacity:${o}`;
    el.artMain.style.opacity = 0.35 + 0.65 * o;
  }
  glow(p * 0.5, mixHex(ART_ACCENT, TRACK_B.glow, u), NARROW_W);

  // The fingertips: [appear, start, end, gone, from, to] in points.
  const strokes = [
    [0.5, 0.95, 1.45, 1.75, [0, 4], [0, 52]],
    [2.35, 2.7, 3.15, 3.45, [40, 110], [-50, 110]],
    [3.95, 4.3, 4.75, 5.05, [-50, 110], [40, 110]],
    [5.3, 5.65, 6.1, 6.4, [0, 160], [0, 92]],
  ];
  for (const [a, b, c, d, from, to] of strokes) {
    if (t < a || t > d + 0.01) continue;
    const m = eramp(t, b, c - b);
    const o = t < b ? eramp(t, a, b - a, easeOut) : t > c ? 1 - eramp(t, c, d - c) : 1;
    N.fingers.style.opacity = o;
    N.fingers.style.zIndex = 3;
    N.fingers.style.transform =
      `translateX(calc(-50% + ${px(lerp(from[0], to[0], m))}px)) translateY(${px(lerp(from[1], to[1], m))}px)`;
  }
}};

/* 16. Join — calls get a Join button ten minutes before they start. */
CLIPS['join-call'] = { duration: 7.0, poster: 3.0, render(t) {
  reset();
  columns({ media: false, cal: true, tools: false });
  fill(NARROW_W);
  const p = clamp01(springAt(t, 0.7, EXPAND) - springAt(t, 5.7, COLLAPSE));
  morph(p, NOTCH_W, NARROW_W);
  el.wxPill.style.opacity = eramp(t, 1.1, 0.4, easeOut);
  el.gear.style.opacity = eramp(t, 1.2, 0.4, easeOut);
  const pop = springAt(t, 1.45, ARRIVAL);
  const press = t > 3.05 && t < 3.22 ? 0.9 : 1;
  const pulse = 0.5 + 0.5 * Math.sin(t * 4.2);
  el.calSub.parentElement.style.color = 'rgba(255,255,255,0.75)';
  el.calSub.innerHTML = `Design review · in 8 min` +
    `<span id="joinPill" style="display:inline-flex;align-items:center;gap:${px(3)}px;margin-left:${px(6)}px;` +
    `padding:${px(3)}px ${px(8)}px;border-radius:999px;background:var(--accent);color:rgba(0,0,0,0.85);` +
    `font-size:${px(10)}px;font-weight:600;opacity:${clamp01(pop * 1.5)};transform:scale(${(0.5 + 0.5 * pop) * press});` +
    `box-shadow:0 0 ${px(6 + 8 * pulse)}px rgba(71,153,255,${0.25 + 0.35 * pulse})">` +
    `<svg width="${px(10)}" height="${px(10)}" viewBox="0 0 20 20" fill="currentColor"><path d="M2 6.2A2.2 2.2 0 0 1 4.2 4h7.6A2.2 2.2 0 0 1 14 6.2v7.6a2.2 2.2 0 0 1-2.2 2.2H4.2A2.2 2.2 0 0 1 2 13.8zM15 8.4l3-2.1v7.4l-3-2.1z"/></svg>Join</span>`;
  // The pointer, in panel-local coordinates measured off the live layout.
  const pill = document.getElementById('joinPill');
  const reach = eramp(t, 2.0, 0.9, easeOut), leave = eramp(t, 4.0, 0.8, easeOut);
  if (pill && p > 0.9) {
    const pr = el.panel.getBoundingClientRect(), r = pill.getBoundingClientRect();
    const sc = pr.width / el.panel.offsetWidth;
    const tx = (r.left + r.width * 0.55 - pr.left) / sc, ty = (r.top + r.height * 0.5 - pr.top) / sc;
    el.cursor.style.opacity = clamp01(reach * 1.5) * (1 - leave);
    el.cursor.style.left = lerp(tx + px(90), tx, reach) + lerp(0, px(110), leave) + 'px';
    el.cursor.style.top = lerp(ty + px(70), ty, reach) + lerp(0, px(40), leave) + 'px';
    el.cursor.style.transform = `scale(${t > 3.05 && t < 3.22 ? 0.88 : 1})`;
  }
}};

/* 17. Choose your screen — the notch moves to the other display. */
function buildDisplays() {
  if (N.displays.dataset.built) return;
  N.displays.dataset.built = '1';
  N.displays.innerHTML = `
    <div class="scr" id="dLap" style="left:170px;top:84px;width:560px;height:340px">
      <div class="wp" style="background:radial-gradient(70% 90% at 30% 10%,#ff8a3d,transparent 70%),radial-gradient(60% 80% at 80% 30%,#e8409a,transparent 70%),linear-gradient(160deg,#3a1d5c,#120b22)"></div>
      <div class="bar"></div><div class="island" id="iLap"></div></div>
    <div class="stand" style="left:130px;top:430px;width:640px;height:14px;border-radius:0 0 14px 14px"></div>
    <div class="scr" id="dExt" style="left:830px;top:40px;width:620px;height:384px">
      <div class="wp" style="background:radial-gradient(70% 90% at 70% 10%,#3a7bff,transparent 70%),radial-gradient(60% 80% at 20% 40%,#20c9b0,transparent 70%),linear-gradient(200deg,#0f2246,#07101f)"></div>
      <div class="bar"></div><div class="island" id="iExt"></div></div>
    <div class="stand" style="left:1100px;top:434px;width:80px;height:26px"></div>
    <div class="stand" style="left:1050px;top:458px;width:180px;height:8px;border-radius:4px"></div>
    <div class="name" style="left:170px;top:470px;width:580px">Built-in Display</div>
    <div class="name" style="left:830px;top:480px;width:640px">Studio Display</div>`;
}
CLIPS['displays'] = { duration: 7.0, poster: 3.6, render(t) {
  reset();
  el.stage.style.display = 'none';
  el.menubar.style.display = 'none';
  N.displays.style.display = 'block';
  buildDisplays();
  const a = clamp01(springAt(t, 2.1, EXPAND) - springAt(t, 5.1, EXPAND));   // 1 = external
  const knob = clamp01(springAt(t, 1.8, READOUT) - springAt(t, 4.8, READOUT));
  // Drawn at 0.75 px per point: the hardware notch, and the strip around it.
  const notchW = 150, stripW = 219, h = 24;
  const content = (o) =>
    `<span class="ma" style="background:${ART};opacity:${o}"></span>` +
    `<span style="opacity:${o};transform:scale(0.75);transform-origin:100% 50%">${waveform(t)}</span>`;
  const lap = $('iLap'), ext = $('iExt');
  lap.style.width = lerp(stripW, notchW, a) + 'px';
  lap.style.height = h + 'px';
  lap.innerHTML = content(clamp01(1 - a * 3));
  ext.style.width = lerp(notchW * 0.6, stripW, a) + 'px';
  ext.style.height = lerp(0, h, a) + 'px';
  ext.style.opacity = clamp01(a * 4);
  ext.innerHTML = content(clamp01((a - 0.5) * 2));
  N.seg.style.display = 'flex';
  N.seg.querySelector('.lbl').textContent = 'Show on';
  const opts = N.seg.querySelectorAll('.track span');
  opts[0].textContent = 'Built-in'; opts[1].textContent = 'Studio Display';
  opts.forEach(o => (o.style.width = '200px'));
  N.segKnob.style.width = '200px';
  N.segKnob.style.transform = `translateX(${200 * knob}px)`;
}};

/* ---------- Renderer entry points --------------------------------------- */
window.__CLIPS = Object.entries(CLIPS).map(([name, c]) => ({ name, duration: c.duration, poster: c.poster }));
window.__render = (name, t) => {
  const clip = CLIPS[name];
  if (!clip) throw new Error(`unknown clip: ${name}`);
  clip.render(t);
};
window.__render(window.__CLIPS[0].name, 0);
