/* =========================================================================
   The hero stage and the motion toy.

   The stage is the panel rebuilt in HTML — the same metrics the feature clips
   use (NotchGeometry.swift / Theme.swift) — running itself through five
   moments: now playing, the shelf, clipboard history, the volume readout and
   a timer. Hover takes over from the loop; the chips pick a moment.

   The springs are the app's, not a lookalike. Motion.swift opens with
   `.smooth(duration: 0.40, extraBounce: b)`, closes with a critically damped
   `.smooth(duration: 0.32)`, and MotionPersonality.swift names three values
   of b. SwiftUI's smooth spring is a damped oscillator with damping ratio
   1 − b and period `duration`, so the curve is computed here and handed to
   CSS as a `linear()` easing sampled at 60 Hz. Choosing "Lively" on the page
   is therefore the same 12.6% overshoot you get in the app.
   ========================================================================= */
(() => {
  "use strict";

  const $ = (id) => document.getElementById(id);
  const root = document.documentElement;
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const hasLinear = window.CSS && CSS.supports("transition-timing-function", "linear(0, 1)");

  /* ---------- Springs ---------------------------------------------------- */
  const PRESETS = { calm: 0.0, standard: 0.10, lively: 0.45 };

  function springFn(bounce, d) {
    const zeta = 1 - bounce;
    const w = (2 * Math.PI) / d;
    if (zeta < 1) {
      const wd = w * Math.sqrt(1 - zeta * zeta);
      return (t) => 1 - Math.exp(-zeta * w * t) *
        (Math.cos(wd * t) + ((zeta * w) / wd) * Math.sin(wd * t));
    }
    return (t) => 1 - Math.exp(-w * t) * (1 + w * t);
  }

  /** When the motion is within 0.2% of rest for good. */
  function settleTime(x, d) {
    const step = 1 / 120;
    let last = 0;
    for (let t = step; t < 3; t += step) if (Math.abs(x(t) - 1) > 0.002) last = t;
    return Math.max(d * 0.9, last + step);
  }

  function curve(bounce, d) {
    const x = springFn(bounce, d);
    const T = settleTime(x, d);
    const n = Math.min(90, Math.max(24, Math.round(T * 60)));
    const pts = [];
    for (let i = 0; i <= n; i++) pts.push(i === n ? 1 : +x((T * i) / n).toFixed(4));
    // Browsers without linear() get the nearest cubic-bezier.
    const fallback = bounce > 0.3 ? "cubic-bezier(0.34, 1.5, 0.5, 1)"
                   : bounce > 0.05 ? "cubic-bezier(0.3, 1.06, 0.45, 1)"
                   : "cubic-bezier(0.22, 1, 0.36, 1)";
    return { ease: hasLinear ? `linear(${pts.join(", ")})` : fallback, ms: Math.round(T * 1000) };
  }

  /** Peak overshoot of an underdamped spring, as a fraction of the travel. */
  function overshoot(bounce) {
    const z = 1 - bounce;
    return z >= 1 ? 0 : Math.exp((-z * Math.PI) / Math.sqrt(1 - z * z));
  }

  const COLLAPSE = curve(0, 0.32);
  let preset = "standard";
  try {
    const saved = localStorage.getItem("aloenotch-bounce");
    if (saved && saved in PRESETS) preset = saved;
  } catch { /* storage blocked: the default is fine */ }

  let OPEN = curve(PRESETS[preset], 0.40);
  const onPreset = [];

  function setPreset(p) {
    preset = p;
    // Reduce Motion wins, in the app and here.
    const b = reduce ? 0 : PRESETS[p];
    OPEN = curve(b, 0.40);
    const arrive = curve(Math.min(0.5, b + 0.25), 0.34);   // Motion.arrival
    root.style.setProperty("--arrive-ease", arrive.ease);
    root.style.setProperty("--arrive-ms", arrive.ms + "ms");
    for (const btn of document.querySelectorAll(".seg [data-bounce]")) {
      btn.setAttribute("aria-checked", String(btn.dataset.bounce === p));
    }
    try { localStorage.setItem("aloenotch-bounce", p); } catch { /* ignore */ }
    onPreset.forEach((f) => f(p));
  }
  for (const btn of document.querySelectorAll(".seg [data-bounce]")) {
    btn.addEventListener("click", () => setPreset(btn.dataset.bounce));
  }

  /* ---------- Shared bits ------------------------------------------------ */
  const ICON = {
    speaker: '<svg viewBox="0 0 20 20" fill="currentColor"><path d="M9.4 3.2 5.6 6.4H2.8v7.2h2.8l3.8 3.2z"/><path d="M12.4 7a4 4 0 0 1 0 6" stroke="currentColor" stroke-width="1.5" fill="none" stroke-linecap="round"/><path d="M14.8 4.6a7.2 7.2 0 0 1 0 10.8" stroke="currentColor" stroke-width="1.5" fill="none" stroke-linecap="round"/></svg>',
    timer: '<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.7"><circle cx="10" cy="11.4" r="6.6"/><path d="M10 8.2v3.4l2.2 1.5M7.6 1.8h4.8"/></svg>',
    tray: '<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6"><path d="M2.4 12h4l1.2 2.2h4.8L13.6 12h4M2.4 12l2.2-7.4h10.8L17.6 12v4.2a1.4 1.4 0 0 1-1.4 1.4H3.8a1.4 1.4 0 0 1-1.4-1.4z"/></svg>',
    clip: '<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6"><rect x="7" y="2.6" width="10.4" height="13.6" rx="2.2"/><path d="M13.6 16.2v1.2H2.6V5.6h1.4"/></svg>',
    clock: '<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6"><circle cx="10" cy="10" r="7.4"/><path d="M10 5.6V10l3 2"/></svg>',
    link: '<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6"><path d="M8.4 11.6a3.4 3.4 0 0 0 5 .4l2.4-2.4a3.4 3.4 0 0 0-4.8-4.8l-1.4 1.4M11.6 8.4a3.4 3.4 0 0 0-5-.4L4.2 10.4a3.4 3.4 0 0 0 4.8 4.8l1.4-1.4"/></svg>',
    text: '<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><path d="M3.4 5h13.2M3.4 10h13.2M3.4 15h8"/></svg>',
    check: '<svg class="ok" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M4.4 10.6 8 14.2l7.6-8"/></svg>',
  };

  setPreset(preset);

  const stage = $("stage");
  const hn = $("hn");
  if (stage && hn) initStage();
  initToy();

  /* =======================================================================
     The stage
     ======================================================================= */
  function initStage() {
    /* Synthetic tracks — gradient artwork and invented names, so nothing
       copyrighted ends up on the page. */
    const TRACKS = [
      { title: "Neon Arcade", artist: "Kade & the Lantern", len: 204, glow: "#c86bff",
        lyrics: ["Coins in the slot", "and the lights come on", "Press start, hold on"],
        art: "linear-gradient(135deg, #ff5f8f 0%, #a45cff 48%, #4bc0ff 100%)" },
      { title: "Tidal Rooms", artist: "Marlow Vane", len: 247, glow: "#3fd6c6",
        lyrics: ["Salt on the windows", "the tide keeps the time", "Stay till the morning"],
        art: "linear-gradient(135deg, #3ee6c1 0%, #2a8cff 55%, #1b2a6b 100%)" },
      { title: "Amber Static", artist: "The Paper Suns", len: 188, glow: "#ff8a5c",
        lyrics: ["Radio hum at midnight", "amber on the dial", "Tune me back to you"],
        art: "linear-gradient(135deg, #ffc15e 0%, #ff5f6d 55%, #6a3093 100%)" },
    ];

    const NOTCH_W = 200, NOTCH_H = 32, MEDIA_WING = 46, ACT_WING = 64;
    const R_COL = 10, R_EXP = 26;
    const S_COL = 6, S_EXP = 10;   // Metrics.shoulder: peek / expanded
    const ORDER = ["music", "shelf", "clipboard", "volume", "timer"];
    const HOLD = { music: 6400, shelf: 3800, clipboard: 3600, volume: 3000, timer: 3400 };

    const chips = [...document.querySelectorAll(".chip-btn")];
    const hint = $("stageHint");
    const hoverable = matchMedia("(hover: hover)").matches;
    if (!hoverable && hint) hint.lastChild.textContent = " It’s live — tap the notch";

    let track = 0, elapsed = 0;
    let state = "music";
    let cur = { w: 680, h: 208 };
    let subTimers = [];          // timers that belong to the current moment
    let nextTimer = null;        // the autoplay advance
    let resumeTimer = null;
    let autoplay = !reduce;
    let visible = true, hovering = false, openedByHover = false;

    const narrow = () => stage.clientWidth <= 640;
    const panelSize = () => (narrow() ? { w: 400, h: 196 } : { w: 680, h: 208 });

    const later = (ms, f) => subTimers.push(setTimeout(f, ms));
    const clearSub = () => { subTimers.forEach(clearTimeout); subTimers = []; };

    /* ---- The shape. One element, resized; never swapped. ---- */
    function shape(w, h, r, mode) {
      const grow = w * h > cur.w * cur.h + 1;
      const c = reduce ? null : grow ? OPEN : COLLAPSE;
      hn.style.transitionTimingFunction = c ? c.ease : "linear";
      hn.style.transitionDuration = c ? c.ms + "ms" : "0ms";
      hn.style.setProperty("--w", w);
      hn.style.setProperty("--h", h);
      hn.style.setProperty("--r", r);
      hn.style.setProperty("--s", mode === "panel" ? S_EXP : S_COL);
      stage.dataset.mode = mode;
      cur = { w, h };
    }
    function openPanel() {
      const s = panelSize();
      hn.style.setProperty("--cw", s.w);
      hn.style.setProperty("--ch", s.h);
      shape(s.w, s.h, R_EXP, "panel");
      light(0.62, 0.9);
    }
    function light(glow, thrown) {
      hn.style.setProperty("--glow-a", glow);
      stage.style.setProperty("--throw", thrown);
    }
    function strip(left, right) {
      $("hnLeft").innerHTML = left;
      $("hnRight").innerHTML = right;
    }
    function tabs(active) {
      const list = [["shelf", ICON.tray, "Shelf"], ["clip", ICON.clip, "Clipboard"], ["timer", ICON.clock, "Timer"]];
      $("hnTabs").innerHTML = list.map(([id, svg, name]) =>
        `<span class="tab${id === active ? " on" : ""}">${svg}${id === active ? `<span class="name">${name}</span>` : ""}</span>`
      ).join("");
    }
    const tool = (html) => { $("hnTool").innerHTML = html; };

    /* ---- Glass or solid (GlassNotch.swift) ----
       A visitor's own pick is remembered. Without one, the panel opens solid
       the first time and turns to glass a beat later, so the switch itself
       is the first thing shown. */
    let look = null, lookPicked = false;
    try {
      const saved = localStorage.getItem("aloenotch-look");
      if (saved === "solid" || saved === "glass") { look = saved; lookPicked = true; }
    } catch { /* storage blocked */ }
    function setLook(l, remember) {
      look = l;
      stage.dataset.look = l;
      for (const b of document.querySelectorAll(".seg [data-look]")) {
        b.setAttribute("aria-checked", String(b.dataset.look === l));
      }
      if (remember) {
        lookPicked = true;
        try { localStorage.setItem("aloenotch-look", l); } catch { /* ignore */ }
      }
    }
    setLook(lookPicked ? look : (reduce ? "glass" : "solid"), false);
    for (const b of document.querySelectorAll(".seg [data-look]")) {
      b.addEventListener("click", () => {
        setLook(b.dataset.look, true);
        dismissHint();
        if (stage.dataset.mode !== "panel") {
          clearTimeout(resumeTimer);
          go("music", { manual: true });
          resumeTimer = setTimeout(schedule, 9000);
        }
      });
    }
    let showedGlass = false;
    function maybeShowGlass() {
      if (lookPicked || showedGlass) return;
      showedGlass = true;
      setTimeout(() => { if (!lookPicked) setLook("glass", false); }, 1500);
    }

    /* The rim catches the pointer: a highlight that follows it round the edge. */
    const rim = stage.querySelector(".hn-rim");
    if (rim && hoverable) {
      stage.addEventListener("pointermove", (e) => {
        const r = hn.getBoundingClientRect();
        rim.style.setProperty("--mx", (e.clientX - r.left).toFixed(0) + "px");
        rim.style.setProperty("--my", (e.clientY - r.top).toFixed(0) + "px");
        rim.style.setProperty("--spot", "1");
      });
      stage.addEventListener("pointerleave", () => rim.style.setProperty("--spot", "0"));
    }

    /* ---- Lyrics: the line being sung, in the artist's place ---- */
    let lyricAt = 0;
    function stopLyrics() {
      const a = $("hnArtist");
      if (!a.classList.contains("lyrics")) return;
      a.classList.remove("lyrics");
      a.textContent = TRACKS[track].artist;
    }
    function showLyric(i) {
      const a = $("hnArtist");
      const lines = TRACKS[track].lyrics;
      if (!a.classList.contains("lyrics")) { a.classList.add("lyrics"); a.textContent = ""; }
      for (const old of a.querySelectorAll(".lyric:not(.out)")) {
        old.classList.add("out");
        setTimeout(() => old.remove(), 450);
      }
      const span = document.createElement("span");
      span.className = "lyric";
      span.textContent = lines[i % lines.length];
      a.appendChild(span);
    }
    function startLyrics(delay) {
      lyricAt = 0;
      if (reduce) { showLyric(0); return; }
      const step = () => { showLyric(lyricAt++); later(2100, step); };
      later(delay, step);
    }

    /* ---- The equalizer, driven by a real track ----
       Four bands at SpectrumBands.swift's edges with the meter's attack and
       decay, measured off the launch video's music and looped. */
    const EQ = "223817212332141819272222215455491760464115513834544352808552449172663776607231645161265443512245364318383036153225572845218723381894203218791727199217221677191913651616115513181246324025393733313231283527322337333220393927174040231444552820467937343993312933972624388222203269181735581514414816123541242429344777323549922729417828333565284640552456344627472839234024322733203630351730252914252525152721372238225119322555163721564448187937401591313412772628108122240968192007571617064813140540171206341410052812080424100703201106044451470348433904403633044130280447252304392120033318160328151404321312043611100430090803302721063923180841191509341613093718180731212508381821073215246745517656484364474836713952397640564064345633543847284532543252277079853482937140697860425866504349555543524647364439393037334478494882664140895545347446472862396178883375937428639762315382522655696737465856423948473542414037453433315537283760312431504064796773756677916355867753477264453961543733514531285638262947324432403847363332393928273340232839336678813683936830707857485965837649557064524672545339614544335138372743323923363342193028354978338084664093715541975946449850393799423338833528387030237559435863493648535530414459253437502729315931243470262034592717297369743288906234749652286281443352683728445731334548262745402276515576644347645436395445403345386262753271886334789553298080453267676237575652384847444040403733343331353428263635242230302844785360836664866955758858466374493953624139625235335244293763374331533152384426443237223737312531316277793479926629677855335665867847789566589380556178674652655639435547334446403337393335414165357082893784697540715863335948533969574433704837375940315749507180414259673536505739304248433335403638303438322536412721305659763786877943909566447580564563674738705739405947334059402880605074675142805743366748363057404655663476867328868661347272513461616438515154434343454536363845303632383531273929262233332619795452756670856355748553477672443964603733655131345443263546363429553950394640424439333537322830395469783968906640577555344863667963538967674575567038634759325340492744334122373435193134293158297877813693646842975457";
    const eqGet = (j, b) => Number(EQ.substr((Math.min(269, Math.max(0, j)) * 4 + b) * 2, 2)) / 99;
    function eqAt(sec) {
      const f = sec * 30, i = Math.floor(f), a = f - i;
      return [0, 1, 2, 3].map((b) => eqGet(i, b) + (eqGet(i + 1, b) - eqGet(i, b)) * a);
    }
    let eqRunning = false;
    function eqFrame(now) {
      const bars = stage.querySelectorAll(".wave.live i");
      if (!bars.length || !visible) { eqRunning = false; return; }
      const S = 0.6, D = 8.4, X = 0.6, t = (now / 1000) % D;
      let lv = eqAt(S + t);
      if (t > D - X) {
        const a = (t - (D - X)) / X, early = eqAt(S + t - D);
        lv = lv.map((v, i) => v + (early[i] - v) * a);
      }
      bars.forEach((b, i) => b.style.setProperty("--lv", (3 + 9 * lv[i]).toFixed(2)));
      requestAnimationFrame(eqFrame);
    }
    function startEq() {
      if (reduce || eqRunning) return;
      eqRunning = true;
      requestAnimationFrame(eqFrame);
    }

    /* ---- Track, clock, calendar ---- */
    function setTrack(i) {
      track = i;
      const t = TRACKS[i];
      stage.style.setProperty("--art", t.art);
      root.style.setProperty("--glow", t.glow);
      $("hnTitle").textContent = t.title;
      $("hnArtist").textContent = t.artist;
      $("hnLength").textContent = fmt(t.len);
      elapsed = Math.round(t.len * 0.38);
      tickScrub();
    }
    const fmt = (s) => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, "0")}`;
    function tickScrub() {
      const t = TRACKS[track];
      $("hnElapsed").textContent = fmt(elapsed);
      $("hnScrub").style.width = ((elapsed / t.len) * 100).toFixed(2) + "%";
    }
    setInterval(() => {
      if (!visible) return;
      elapsed = (elapsed + 1) % TRACKS[track].len;
      tickScrub();
    }, 1000);

    function tickClock() {
      const now = new Date();
      $("hnClock").textContent = now.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" }).replace(/\s?[AP]M$/i, "");
      $("mbClock").textContent =
        now.toLocaleDateString(undefined, { weekday: "short", day: "numeric", month: "short" }).replace(",", "") +
        "  " + now.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" });
    }
    tickClock();
    setInterval(tickClock, 15000);

    (function buildWeek() {
      const today = new Date();
      $("hnMonth").textContent = today.toLocaleDateString(undefined, { month: "short" });
      let html = "";
      for (let i = -3; i <= 3; i++) {
        const d = new Date(today);
        d.setDate(today.getDate() + i);
        const dow = d.toLocaleDateString(undefined, { weekday: "narrow" });
        html += `<div class="day${i === 0 ? " today" : ""}"><span class="dow">${dow}</span><span class="num">${d.getDate()}</span></div>`;
      }
      $("hnDays").innerHTML = html;
    })();

    /* ---- The five moments ---- */
    const MOMENTS = {
      music(advance) {
        if (advance) setTrack((track + 1) % TRACKS.length);
        stage.dataset.col = "media";
        tabs("shelf");
        tool('<div class="drop"><span>Drop files here</span></div>');
        strip('<div class="mini-art"></div>', '<div class="wave live"><i></i><i></i><i></i><i></i></div>');
        startEq();
        if (reduce) { openPanel(); startLyrics(0); return; }
        // Peek first, then open: the open is where the bounce shows.
        shape(NOTCH_W + MEDIA_WING * 2, NOTCH_H, R_COL, "strip");
        light(0.4, 0.45);
        later(1300, () => { openPanel(); maybeShowGlass(); });
        startLyrics(1900);
      },
      shelf() {
        stage.dataset.col = "tools";
        tabs("shelf");
        const files = [["PDF", "#ff8a5c"], ["PNG", "#5cc8ff"], ["ZIP", "#b78bff"]];
        tool('<div class="drop">' + files.map(([label, c], i) =>
          `<span class="file" style="--c:${c};--d:${250 + i * 520}ms">${label}</span>`).join("") + "</div>");
        if (stage.dataset.mode !== "panel") openPanel();
      },
      clipboard() {
        stage.dataset.col = "tools";
        tabs("clip");
        const rows = [[ICON.link, "https://aloenotch.com"], [ICON.text, "const notch = useNotch()"], [ICON.text, "Design review moved to 2:30"]];
        tool('<div class="cliplist">' + rows.map(([g, t]) =>
          `<div class="cliprow">${g}<span>${t}</span>${ICON.check}</div>`).join("") + "</div>");
        if (stage.dataset.mode !== "panel") openPanel();
        later(1500, () => {
          const row = stage.querySelectorAll(".cliprow")[1];
          if (row) row.classList.add("hit");
        });
      },
      volume() {
        hn.style.setProperty("--tint", "color-mix(in oklab, var(--glow) 70%, white)");
        strip(`<span class="act">${ICON.speaker}</span>`, '<span class="lvl"><b></b></span>');
        shape(NOTCH_W + ACT_WING * 2, NOTCH_H, R_COL, "strip");
        light(0.18, 0.25);
        const steps = [38, 50, 62, 75, 69];
        const setLevel = (v) => { const b = stage.querySelector(".lvl"); if (b) b.style.setProperty("--lv", v + "%"); };
        setLevel(steps[0]);
        steps.slice(1).forEach((v, i) => later(500 + i * 440, () => setLevel(v)));
      },
      timer() {
        let left = 300;
        strip(`<span class="act" style="color:#ffb454">${ICON.timer}</span>`,
              `<span class="act"><span class="v" id="hnCount">${fmt(left)}</span></span>`);
        shape(NOTCH_W + ACT_WING * 2, NOTCH_H, R_COL, "strip");
        light(0.18, 0.25);
        const tick = () => {
          left -= 1;
          const el = $("hnCount");
          if (el) el.textContent = fmt(left);
          later(1000, tick);
        };
        later(1000, tick);
      },
    };

    function timerTool() {
      tabs("timer");
      const R = 22, C = 2 * Math.PI * R;
      tool(`<div class="drop" style="border-style:solid;border-color:rgba(255,255,255,.06)">
        <svg viewBox="0 0 54 54" style="width:calc(54 * var(--pt));height:calc(54 * var(--pt));transform:rotate(-90deg)">
          <circle cx="27" cy="27" r="${R}" fill="none" stroke="rgba(255,255,255,.12)" stroke-width="4"/>
          <circle cx="27" cy="27" r="${R}" fill="none" stroke="#ffb454" stroke-width="4" stroke-linecap="round"
                  stroke-dasharray="${C}" stroke-dashoffset="${C * 0.22}"/></svg>
        <span style="font-size:calc(15 * var(--pt));font-weight:600;font-variant-numeric:tabular-nums">${($("hnCount") || {}).textContent || "4:59"}</span>
      </div>`);
    }

    /* ---- Driving it ---- */
    function go(name, { advance = false, manual = false } = {}) {
      clearSub();
      clearTimeout(nextTimer);
      state = name;
      openedByHover = false;
      for (const c of chips) {
        c.classList.toggle("on", c.dataset.go === name);
        c.classList.remove("timed");
        c.setAttribute("aria-pressed", String(c.dataset.go === name));
      }
      stopLyrics();
      MOMENTS[name](advance);
      if (!manual) schedule();
    }

    function schedule() {
      clearTimeout(nextTimer);
      if (!autoplay || !visible || hovering) return;
      const chip = chips.find((c) => c.dataset.go === state);
      if (chip) {
        chip.style.setProperty("--hold", HOLD[state] + "ms");
        chip.classList.remove("timed");
        void chip.offsetWidth;          // restart the progress animation
        chip.classList.add("timed");
      }
      nextTimer = setTimeout(() => {
        const next = ORDER[(ORDER.indexOf(state) + 1) % ORDER.length];
        go(next, { advance: next === "music" });
      }, HOLD[state]);
    }

    function pause() {
      clearTimeout(nextTimer);
      chips.forEach((c) => c.classList.remove("timed"));
    }

    const dismissHint = () => hint && hint.classList.add("gone");

    for (const chip of chips) {
      chip.addEventListener("click", () => {
        dismissHint();
        const name = chip.dataset.go;
        go(name, { manual: true, advance: name === "music" && state === "music" });
        clearTimeout(resumeTimer);
        resumeTimer = setTimeout(schedule, 9000);
      });
    }

    function expandHere() {
      if (stage.dataset.mode === "panel") return;
      openedByHover = true;
      if (state === "timer") { stage.dataset.col = "tools"; timerTool(); }
      else { clearSub(); stage.dataset.col = "media"; startLyrics(500); }
      openPanel();
      maybeShowGlass();
    }

    if (hoverable) {
      hn.addEventListener("pointerenter", () => {
        hovering = true;
        dismissHint();
        clearTimeout(resumeTimer);
        pause();
        expandHere();
      });
      hn.addEventListener("pointerleave", () => {
        hovering = false;
        clearTimeout(resumeTimer);
        resumeTimer = setTimeout(() => {
          if (openedByHover) go(state);   // fold back to what it was showing
          else schedule();
        }, 380);
      });
    } else {
      hn.addEventListener("click", () => {
        dismissHint();
        if (stage.dataset.mode === "panel") go(state === "music" ? "volume" : state, { manual: true });
        else expandHere();
        clearTimeout(resumeTimer);
        resumeTimer = setTimeout(schedule, 9000);
      });
    }

    // Nothing runs while nobody can see it.
    new IntersectionObserver((entries) => {
      visible = entries[0].isIntersecting;
      if (visible) { schedule(); startEq(); } else pause();
    }, { threshold: 0.2 }).observe(stage);
    document.addEventListener("visibilitychange", () => {
      visible = !document.hidden;
      if (visible) { schedule(); startEq(); } else pause();
    });

    // A resize across the phone breakpoint changes the panel's size.
    let wasNarrow = narrow();
    addEventListener("resize", () => {
      if (narrow() !== wasNarrow) {
        wasNarrow = narrow();
        if (stage.dataset.mode === "panel") openPanel();
      }
    });

    // The preset applies to the next open; show it off right away.
    onPreset.push(() => {
      if (!stage.isConnected) return;
      dismissHint();
      clearTimeout(resumeTimer);
      go("music", { manual: true });
      resumeTimer = setTimeout(schedule, 9000);
    });

    // The markup ships expanded so the page has a picture without JS. Start
    // from the peek instead, without animating there, so the first thing a
    // visitor sees the panel do is open.
    if (!reduce) {
      hn.style.transitionDuration = "0ms";
      hn.style.setProperty("--w", NOTCH_W + MEDIA_WING * 2);
      hn.style.setProperty("--h", NOTCH_H);
      hn.style.setProperty("--r", R_COL);
      stage.dataset.mode = "strip";
      cur = { w: NOTCH_W + MEDIA_WING * 2, h: NOTCH_H };
      void hn.offsetWidth;
    }
    setTrack(0);
    go("music");
  }

  /* =======================================================================
     The motion toy, in the "Motion you can dial" card. A small notch opens
     and closes on the chosen spring while the curve it is following draws
     itself behind it.
     ======================================================================= */
  function initToy() {
    const toy = $("toy");
    const notch = $("toyNotch");
    const path = $("toyPath");
    const read = $("toyOver");
    if (!toy || !notch || !path) return;

    // A second copy of the curve that draws in time with the open.
    const svg = $("toyCurve");
    const live = svg.cloneNode(true);
    live.removeAttribute("id");
    live.classList.add("live");
    live.querySelector(".target").remove();
    const livePath = live.querySelector(".line");
    livePath.removeAttribute("id");
    svg.after(live);
    path.style.opacity = "0.22";

    const SPAN = 1.0;   // seconds plotted across the card
    function draw() {
      const b = PRESETS[preset];
      const x = springFn(b, 0.40);
      let d = "";
      for (let i = 0; i <= 120; i++) {
        const px = (400 * i) / 120;
        const py = 150 - 90 * x((SPAN * i) / 120);
        d += (i ? "L" : "M") + px.toFixed(1) + " " + py.toFixed(1);
      }
      path.setAttribute("d", d);
      livePath.setAttribute("d", d);
      const v = overshoot(b) * 100;
      read.textContent = v === 0 ? "0%" : v < 1 ? v.toFixed(2) + "%" : v.toFixed(1) + "%";
    }

    let timer = null, visible = false, isOpen = false;

    function setOpen(open) {
      isOpen = open;
      const c = reduce ? null : open ? OPEN : COLLAPSE;
      notch.style.transitionTimingFunction = c ? c.ease : "linear";
      notch.style.transitionDuration = c ? c.ms + "ms" : "0ms";
      notch.classList.toggle("open", open);
      if (reduce) { live.style.clipPath = "none"; return; }
      if (open) {
        live.style.transition = "none";
        live.style.clipPath = "inset(0 100% 0 0)";
        live.style.opacity = "1";
        void live.getBoundingClientRect();
        live.style.transition = `clip-path ${SPAN * 1000}ms linear`;
        live.style.clipPath = "inset(0 0 0 0)";
      } else {
        live.style.transition = "opacity 0.4s ease";
        live.style.opacity = "0";
      }
    }

    function cycle() {
      clearTimeout(timer);
      if (!visible || reduce) return;
      setOpen(!isOpen);
      timer = setTimeout(cycle, isOpen ? 1900 : 1000);
    }

    toy.addEventListener("click", () => {
      clearTimeout(timer);
      setOpen(!isOpen);
      timer = setTimeout(cycle, isOpen ? 1900 : 1000);
    });

    onPreset.push(() => {
      draw();
      clearTimeout(timer);
      if (isOpen) { setOpen(false); timer = setTimeout(cycle, 600); }
      else cycle();
    });

    new IntersectionObserver((entries) => {
      visible = entries[0].isIntersecting;
      if (visible) cycle(); else clearTimeout(timer);
    }, { threshold: 0.4 }).observe(toy);

    draw();
    if (reduce) setOpen(true);
  }
})();
