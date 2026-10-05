# Composition brief

- **Composition.** A single standalone index.html with id `main`, 1920x1080 and 23 s, using one paused GSAP timeline.
- **Palette.**
  - bg #050507, fg #f5f5f7, accent #73bfff;
  - the rim uses an iridescent conic gradient (cyan/violet/pink/amber), matching `GlassRim` in the app;
  - system-ui type.
- **Camera.** `#stage` holds the wallpaper, menu bar and panel, and scales from 50% 0, so every push-in is one transform. Text sits outside the stage.
- **Panel.** A single `#panel` element morphs:
  - notch 400x64;
  - open 1100x372;
  - strip 720x64.
- **Glass.** Glass mode shows three layers:
  - a backdrop-filter frost layer;
  - a black 0.42 tint;
  - a feathered black camera patch.

  The rim is a masked conic ring whose `--ang` is tweened by GSAP.
- **Equalizer.** 4 bars are sampled per frame from `assets/music/audio-data.js`, a 4-band RMS extracted by ffmpeg bandpass filters at 40–200, 200–900, 900–3500 and 3500–14000 Hz. These match the app's `SpectrumBands` edges.
- **Audio.**
  - bed.mp3 has volume automation, with a slight lift during the EQ scene;
  - SFX: drop, switch, glass and bell.
- **Gate.** `npx hyperframes check` must pass clean.
