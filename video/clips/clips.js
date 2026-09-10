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

/* ---------- Renderer entry points --------------------------------------- */
window.__CLIPS = Object.entries(CLIPS).map(([name, c]) => ({ name, duration: c.duration, poster: c.poster }));
window.__render = (name, t) => {
  const clip = CLIPS[name];
  if (!clip) throw new Error(`unknown clip: ${name}`);
  clip.render(t);
};
window.__render(window.__CLIPS[0].name, 0);
