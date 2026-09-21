/* =========================================================================
   AloeNotch launch film — the director.

   One object on screen for twenty-three seconds. Everything about it — size,
   corner radius, what it contains, where the camera is — is a pure function of
   composition time, sampled once per frame. Nothing cuts to a different
   element, because the thing this app is actually good at is being one shape
   that reshapes, and cross-fading between separate clips throws that away.

   Geometry is from NotchGeometry.swift, spring curves from Theme.swift, at
   1pt = 2px. Deterministic: no clocks, no randomness, no network.
   ========================================================================= */

/* ---- The app's own numbers -------------------------------------------- */
var PT = 2;
var NOTCH_W = 200 * PT, NOTCH_H = 32 * PT;       // the hardware cutout
var MEDIA_WING = 46 * PT, WING_REG = 64 * PT;    // NotchMetrics wings
var EXP_W = 680 * PT, EXP_H = 208 * PT;          // panelWidth default, .columns height
var R_OPEN = 26 * PT, R_SHUT = 10 * PT;          // Metrics.panelRadius / .collapsedRadius

var EXPAND = { d: 0.40, bounce: 0.10 };          // Motion.expand
var COLLAPSE = { d: 0.32, bounce: 0.0 };         // Motion.collapse

var ART = "linear-gradient(135deg, #ff5f8f 0%, #a45cff 48%, #4bc0ff 100%)";
var ART_ACCENT = "#b072ff";

/* ---- Maths ------------------------------------------------------------- */
function clamp01(x) { return x < 0 ? 0 : x > 1 ? 1 : x; }
function lerp(a, b, t) { return a + (b - a) * t; }
function easeInOut(t) { return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2; }
function easeOut(t) { return 1 - Math.pow(1 - t, 3); }

/** SwiftUI's `.smooth` spring as a 0..1 progress curve. */
function spring(elapsed, cfg) {
  if (elapsed <= 0) return 0;
  if (elapsed >= cfg.d * 2.2) return 1;
  var zeta = 1 - (cfg.bounce || 0), w = (2 * Math.PI) / cfg.d;
  if (zeta < 1) {
    var wd = w * Math.sqrt(1 - zeta * zeta);
    return 1 - Math.exp(-zeta * w * elapsed) *
      (Math.cos(wd * elapsed) + (zeta * w / wd) * Math.sin(wd * elapsed));
  }
  return 1 - Math.exp(-w * elapsed) * (1 + w * elapsed);
}
function springAt(t, start, cfg) { return spring(t - start, cfg); }
function ramp(t, start, dur) { return clamp01((t - start) / dur); }

/** Interpolate a keyframed value: track(t, [[time, value], ...]). */
function track(t, keys, ease) {
  ease = ease || easeInOut;
  if (t <= keys[0][0]) return keys[0][1];
  for (var i = 1; i < keys.length; i++) {
    if (t <= keys[i][0]) {
      var a = keys[i - 1], b = keys[i];
      return lerp(a[1], b[1], ease(clamp01((t - a[0]) / (b[0] - a[0]))));
    }
  }
  return keys[keys.length - 1][1];
}

function clock(seconds) {
  var s = Math.max(0, Math.round(seconds));
  return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
}

/* ---- Handles ----------------------------------------------------------- */
var $ = function (id) { return document.getElementById(id); };
var elStage = $("stage"), elWrap = $("panelWrap"), elPanel = $("panel"), elEdge = $("edge"),
    elGlow = $("glow"), elStrip = $("strip"), elL = $("stripL"), elR = $("stripR"),
    elExp = $("expanded"), elTabs = $("tabs"), elKeys = $("keys"), elCursor = $("cursor"),
    elBar = $("barfill"), elElapsed = $("elapsed"), elArc = $("ringarc"), elRingNum = $("ringnum"),
    elAura = $("aura"), elArt = $("artimg"), elR1g = $("r1g"), elR1t = $("r1t"), elR1 = $("r1");
var MODS = { media: $("mod-media"), timer: $("mod-timer"), clip: $("mod-clip") };

elArt.style.background = ART;
elAura.style.background = ART;

var ICON = {
  timer: '<svg width="26" height="26" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.7"><circle cx="10" cy="11.4" r="6.6"/><path d="M10 8.2v3.4l2.2 1.5M7.6 1.8h4.8"/></svg>',
  tray: '<svg width="22" height="22" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6"><path d="M2.4 12h4l1.2 2.2h4.8L13.6 12h4M2.4 12l2.2-7.4h10.8L17.6 12v4.2a1.4 1.4 0 0 1-1.4 1.4H3.8a1.4 1.4 0 0 1-1.4-1.4z"/></svg>',
  clip: '<svg width="22" height="22" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6"><rect x="7" y="2.6" width="10.4" height="13.6" rx="2.2"/><path d="M13.6 16.2v1.2H2.6V5.6h1.4"/></svg>',
  clock: '<svg width="22" height="22" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6"><circle cx="10" cy="10" r="7.4"/><path d="M10 5.6V10l3 2"/></svg>',
  check: '<svg width="24" height="24" viewBox="0 0 20 20" fill="none" stroke="#5ee07a" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M4.4 10.6 8 14.2l7.6-8"/></svg>',
  note: '<svg width="24" height="24" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><path d="M3.4 5h13.2M3.4 10h13.2M3.4 15h8"/></svg>'
};

function tabs(active) {
  var list = [["shelf", ICON.tray, "Shelf"], ["clip", ICON.clip, "Clipboard"], ["timer", ICON.clock, "Timer"]];
  elTabs.innerHTML = list.map(function (x) {
    return '<span class="tab' + (x[0] === active ? " on" : "") + '">' + x[1] +
      (x[0] === active ? '<span class="nm">' + x[2] + "</span>" : "") + "</span>";
  }).join("");
}
var tabsFor = { media: null, timer: "timer", clip: "clip" };
var tabsDrawn = null;

/* Four bars that breathe while something is playing. */
function waveform(t) {
  var base = [10, 22, 14, 18], out = "";
  for (var i = 0; i < 4; i++) {
    var h = base[i] * (0.45 + 0.55 * (0.5 + 0.5 * Math.sin(t * 7.5 + i * 1.7)));
    out += '<i style="height:' + h.toFixed(1) + 'px"></i>';
  }
  return '<div id="wave">' + out + "</div>";
}

/* =========================================================================
   The cut
   ========================================================================= */
var T = {
  morph: 3.62,        // the strip opens                     // beat-locked: 3.63s
  toTimer: 8.20,      // collapses to a running countdown
  timerOpen: 8.74,    // and opens on the ring               // beat-locked: 8.74s strong cue
  toClip: 10.70,      // reshapes to the clipboard
  click: 11.62,       // the cursor lands
  toShut: 12.58,      // collapses, with no pointer on screen
  keyOpen: 13.11,     // ⌃⌥N opens it                        // beat-locked: 13.11s strong cue
  pullBack: 15.30,    // the camera retreats
  panelOut: 18.10     // the panel leaves; type only
};

/** Which module the panel is showing, and how far faded in. */
function moduleAt(t) {
  if (t < T.toTimer) return { key: "media", a: clamp01((t - T.morph - 0.18) / 0.35) };
  if (t < T.toClip - 0.2) return { key: "timer", a: clamp01((t - T.timerOpen + 0.05) / 0.3) };
  // A tab switch inside an open panel: the app cross-fades, so this does too.
  if (t < T.toShut - 0.2) return { key: "clip", a: clamp01((t - T.toClip) / 0.28) };
  if (t < T.keyOpen) return { key: "clip", a: clamp01(1 - (t - (T.toShut - 0.2)) / 0.2) };
  // Reopened from the keyboard, and it has to open onto *something* — the panel
  // spent the whole numbers scene showing an empty header before this existed.
  return { key: "media", a: clamp01((t - T.keyOpen - 0.15) / 0.35) };
}

/** Panel openness, 0 = the bare cutout, 1 = the full panel. */
function opennessAt(t) {
  var p = springAt(t, T.morph, EXPAND);
  p -= springAt(t, T.toTimer, COLLAPSE);            // down to the timer strip
  p += springAt(t, T.timerOpen, EXPAND);            // and open on the ring
  p -= springAt(t, T.toShut, COLLAPSE);             // down to the bare cutout
  p += springAt(t, T.keyOpen, EXPAND);              // ⌃⌥N opens it
  p -= springAt(t, T.panelOut, COLLAPSE);           // and it closes for the last word
  return clamp01(p);
}

/** How wide the strip is when the panel is shut — the app grows "wings". */
function stripWidthAt(t) {
  if (t >= T.toTimer && t < T.keyOpen) return NOTCH_W + WING_REG * 2;   // a countdown needs room
  if (t < T.morph) return NOTCH_W;                                      // dead: exactly the cutout
  if (t >= T.panelOut) return NOTCH_W;    // closing for the last word: back to the bare cutout
  return NOTCH_W + MEDIA_WING * 2;
}

function frame(t) {
  /* ---- Camera -------------------------------------------------------- */
  // Pushed hard into the dead notch, pulling back as it opens, and retreating
  // again for the numbers so the panel reads as a small lit object.
  // The pull-back has to outrun the morph. The panel is 1360px at rest scale,
  // so any scale above ~1.41 crops it against a 1920 frame — if the camera is
  // still at 1.6 when the shape finishes opening, the reveal lands cropped.
  // The push on the timer beat is not decoration: when the panel collapses to
  // a strip at rest scale it is a small pill in an empty frame, and the whole
  // point of that beat — the countdown taking the notch over — goes unread.
  var scale = track(t, [[0, 2.55], [T.morph, 2.55], [T.morph + 0.95, 1.0],
                        [T.toTimer - 0.15, 1.0], [T.toTimer + 0.32, 1.7], [T.timerOpen + 0.5, 1.0],
                        [T.pullBack, 1.0], [T.pullBack + 1.3, 0.74], [23, 0.74]]);
  var camY = track(t, [[0, 455], [T.morph, 448], [T.morph + 0.95, 150],
                       [T.toTimer - 0.15, 150], [T.toTimer + 0.32, 330], [T.timerOpen + 0.5, 150],
                       [T.pullBack, 150], [T.pullBack + 1.3, 196], [23, 196]]);
  // A slow, continuous drift so even the held close-up is never a still frame.
  var drift = 1 + 0.045 * easeInOut(clamp01(t / T.morph));
  elStage.style.transform = "translateY(" + camY.toFixed(1) + "px) scale(" +
    (scale * (t < T.morph ? drift : 1)).toFixed(4) + ")";

  /* ---- The shape ------------------------------------------------------ */
  var p = opennessAt(t);
  var w = lerp(stripWidthAt(t), EXP_W, p);
  var h = lerp(NOTCH_H, EXP_H, p);
  var r = lerp(R_SHUT, R_OPEN, p);
  elWrap.style.width = EXP_W + "px";
  elPanel.style.width = w.toFixed(1) + "px";
  elPanel.style.height = h.toFixed(1) + "px";
  elPanel.style.borderBottomLeftRadius = r.toFixed(1) + "px";
  elPanel.style.borderBottomRightRadius = r.toFixed(1) + "px";
  elEdge.style.opacity = p > 0.55 ? ((p - 0.55) / 0.45).toFixed(3) : 0;

  var panelAlpha = t < T.panelOut + 0.45 ? 1 : clamp01(1 - (t - (T.panelOut + 0.45)) / 0.45);
  elPanel.style.opacity = panelAlpha;

  /* ---- Strip vs panel contents ---------------------------------------- */
  elStrip.style.opacity = clamp01(1 - p * 4);
  elStrip.style.display = p > 0.3 ? "none" : "flex";
  elExp.style.opacity = clamp01((p - 0.34) / 0.46);
  elExp.style.display = p > 0.05 ? "flex" : "none";

  if (p <= 0.3) {
    if (t < T.morph) {
      elL.innerHTML = ""; elR.innerHTML = "";              // dead. nothing on it.
    } else if (t >= T.toTimer && t < T.keyOpen) {
      var left = Math.max(0, 1500 - (t - T.toTimer) * 22);
      elL.innerHTML = '<span class="peekglyph">' + ICON.timer + "</span>";
      elR.innerHTML = '<span class="peekval rounded">' + clock(left) + "</span>";
    } else {
      elL.innerHTML = '<div id="miniArt" style="background:' + ART + '"></div>';
      elR.innerHTML = waveform(t);
    }
  }

  /* ---- Which module, and its live values ------------------------------ */
  var mod = moduleAt(t);
  for (var k in MODS) MODS[k].style.opacity = k === mod.key ? mod.a.toFixed(3) : 0;

  var wantTabs = tabsFor[mod.key];
  if (wantTabs !== tabsDrawn) { tabsDrawn = wantTabs; if (wantTabs) tabs(wantTabs); }
  elTabs.style.opacity = wantTabs ? mod.a.toFixed(3) : 0;

  var played = 0.40 + 0.030 * (t - T.morph);
  elBar.style.width = (clamp01(played) * 100).toFixed(2) + "%";
  elElapsed.textContent = clock(clamp01(played) * 204);

  var remaining = Math.max(0, 1500 - (t - T.toTimer) * 22);
  elRingNum.textContent = clock(remaining);
  var C = 2 * Math.PI * 58, done = 1 - remaining / 1500;
  elArc.setAttribute("stroke-dasharray", C.toFixed(2));
  elArc.setAttribute("stroke-dashoffset", (C * (1 - done)).toFixed(2));
  elArc.style.opacity = done > 9 / (Math.PI * 132) ? 1 : 0;   // hide the cap until it reads as an arc

  /* ---- The click ------------------------------------------------------- */
  var copied = t >= T.click && t < T.toShut - 0.25;
  elR1g.innerHTML = copied ? ICON.check : ICON.note;
  elR1t.textContent = copied ? "Copied" : "const notch = useNotch()";
  elR1.style.background = "rgba(255,255,255," + (copied ? 0.18 : 0.04) + ")";
  var reach = easeOut(clamp01((t - (T.toClip + 0.15)) / 0.75));
  var leaving = clamp01((t - (T.click + 0.9)) / 0.5);
  elCursor.style.opacity = (clamp01(reach * 1.6) * (1 - leaving)).toFixed(3);
  elCursor.style.left = lerp(340, 610, reach).toFixed(0) + "px";
  elCursor.style.top = (lerp(250, 96, reach) + leaving * 70).toFixed(0) + "px";
  elCursor.style.transform = "scale(" + (t >= T.click && t < T.click + 0.13 ? 0.86 : 1) + ")";

  /* ---- Keycaps --------------------------------------------------------- */
  var keyShow = clamp01((t - (T.toShut + 0.1)) / 0.3) * (1 - clamp01((t - (T.keyOpen + 1.5)) / 0.4));
  var down = t >= T.keyOpen - 0.14 && t < T.keyOpen + 0.06;
  elKeys.style.opacity = keyShow.toFixed(3);
  elKeys.style.top = "690px";
  elKeys.style.transform = "translateX(-50%) translateY(" + (down ? 6 : 0) + "px)";

  /* ---- Glow ------------------------------------------------------------ */
  var fr = AUDIO_DATA.frames[Math.min(AUDIO_DATA.totalFrames - 1, Math.round(t * AUDIO_DATA.fps))];
  var bass = fr ? fr.bands[0] : 0, energy = fr ? fr.bands[1] : 0;
  // Present only while the panel is, and only once it is actually open — the
  // glow belongs to the artwork, and the dead notch has no artwork.
  var gate = clamp01((p - 0.25) / 0.5) * panelAlpha;
  elGlow.style.width = (w + 26).toFixed(1) + "px";
  elGlow.style.height = (h + 26).toFixed(1) + "px";
  elGlow.style.border = "3px solid " + ART_ACCENT;
  elGlow.style.boxShadow = "0 0 " + (86 + 30 * bass).toFixed(0) + "px " + (10 + 8 * bass).toFixed(0) + "px " + ART_ACCENT;
  elGlow.style.opacity = (gate * (0.30 + 0.34 * energy)).toFixed(3);
}

/* ---- Timeline ---------------------------------------------------------- */
var tl = gsap.timeline({ paused: true });

// The whole film is sampled, not tweened: every visual is a pure function of t,
// so a seek to any frame produces exactly the frame the render produces.
for (var f = 0; f < AUDIO_DATA.totalFrames; f++) {
  tl.call((function (time) { return function () { frame(time); }; })(f / AUDIO_DATA.fps), [], f / AUDIO_DATA.fps);
}

/* Type. Fast in, then hold — the pace comes from the camera, never from
   pulling a line off screen before it can be read. */
function line(sel, at, hold, rise) {
  rise = rise === undefined ? 26 : rise;
  tl.fromTo(sel, { opacity: 0, y: rise }, { opacity: 1, y: 0, duration: 0.45, ease: "power2.out" }, at);
  tl.to(sel, { opacity: 0, duration: 0.35, ease: "power1.in" }, at + hold);
}
line("#h1", 0.45, 1.5);
line("#h2", 2.05, 1.3);
line("#hero", 4.9, 2.7, 30);
line("#lb1", 8.6, 1.35);              // beat-locked: 8.74s strong cue
line("#lb2", 10.75, 1.55);
line("#lb2b", 11.75, 0.65);
line("#lb3", 13.1, 1.45);             // beat-locked: 13.11s strong cue

// beat-grid: 15.84 / 16.38 / 16.93 / 17.47 — four short tokens, comfortably
// spaced at 110 BPM, with the last held a full second past its beat.
var NUM_BEATS = [15.84, 16.38, 16.93, 17.47];
["#n0", "#n1", "#n2", "#n3"].forEach(function (sel, i) {
  tl.fromTo(sel, { opacity: 0, y: 12 }, { opacity: 1, y: 0, duration: 0.36, ease: "power2.out" }, NUM_BEATS[i]);
});
tl.to("#nums", { opacity: 0, duration: 0.45, ease: "power1.in" }, 18.15);

line("#price", 18.5, 1.05, 20);       // beat-locked: 18.56s strong cue
tl.fromTo("#payoff", { opacity: 0, y: 18 }, { opacity: 1, y: 0, duration: 0.42, ease: "power3.out" }, 19.9);
tl.to("#payoff", { opacity: 0, duration: 0.5, ease: "power1.in" }, 22.4);
tl.fromTo("#mark", { opacity: 0, y: 22 }, { opacity: 1, y: 0, duration: 0.5, ease: "power2.out" }, 20.6);
tl.fromTo("#url", { opacity: 0 }, { opacity: 1, duration: 0.5, ease: "power2.out" }, 20.85);
tl.to(["#mark", "#url"], { opacity: 0, duration: 0.55, ease: "power1.in" }, 22.3);

// Handed back to index.html to register. The static lint only reads
// index.html, so the `window.__timelines[...]` assignment has to live there or
// it reports the composition as having no timeline at all.
window.__buildTimeline = function () { return tl; };
