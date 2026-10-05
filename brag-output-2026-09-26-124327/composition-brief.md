# Composition brief (vertical)

- **Composition.** A standalone index.html with id `main`, 1080x1920 and 23 s, using one paused GSAP timeline.
- **Reused from the landscape cut:** the panel, rim, frost and strip markup, the audio, and the 4-band audio data.
- **Screen viewport.** The device is a clipped 992x848 screen.
  - Inside it, `#wall` and `#stage` are authored in the landscape design space (1920x1080) and anchored so that design x = 960 sits at the screen centre.
  - The camera scales from `960px 0`:
    - hook 1.4;
    - panel 0.86;
    - lyrics 0.88;
    - strip 1.3 → 1.38;
    - outro 1.0.
- **Panel type.** Type inside the panel is bumped up for phone legibility: title 44, lyric/artist 36.
- **Text blocks.** Text sits in blocks below the device, as stacked label + sub clips, with a centred max width of 880.
- **Gate.** `npx hyperframes check` must pass clean.
