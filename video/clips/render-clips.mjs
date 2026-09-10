/* =========================================================================
   Renders every feature clip to mp4 + webm + poster.

     node render-clips.mjs                 # all clips, 60fps
     node render-clips.mjs --only timer    # one clip
     node render-clips.mjs --fps 30        # quicker draft

   Frames go to a scratch directory and are deleted after encoding; only the
   encoded clips survive, in ../../site/assets/clips/.
   ========================================================================= */
import puppeteer from 'puppeteer';
import { mkdir, rm } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const run = promisify(execFile);
const here = path.dirname(fileURLToPath(import.meta.url));
const OUT = path.resolve(here, '../../site/assets/clips');
const SCRATCH = path.resolve(here, '.frames');

const args = Object.fromEntries(
  process.argv.slice(2).join(' ').split('--').filter(Boolean)
    .map(s => s.trim().split(/\s+/)).map(([k, v]) => [k, v ?? 'true'])
);
const FPS = Number(args.fps ?? 60);
const ONLY = args.only;

/* 1600x680 rendered, delivered at 800x340 — the panel's own 3.3:1 proportions
   rather than a 16:10 box that would be half empty. The cards show these around 280px
   wide, so 720 keeps them crisp on a retina display without the file size of
   a full-resolution clip nobody will ever see at full resolution. */
const W = 1600, H = 640;
const OUT_W = 800, OUT_H = 320;

const browser = await puppeteer.launch({
  headless: true,
  args: ['--force-device-scale-factor=1', '--hide-scrollbars', '--disable-lcd-text',
         '--font-render-hinting=none', '--allow-file-access-from-files', '--disable-gpu-vsync'],
});
const page = await browser.newPage();
await page.setViewport({ width: W, height: H, deviceScaleFactor: 1 });
await page.goto('file://' + path.join(here, 'clips.html'), { waitUntil: 'networkidle0' });
await page.evaluateHandle('document.fonts.ready');

const clips = await page.evaluate(() => window.__CLIPS);
const todo = ONLY ? clips.filter(c => c.name === ONLY) : clips;
if (!todo.length) { console.error(`no clip named "${ONLY}"`); process.exit(1); }

await mkdir(OUT, { recursive: true });

for (const { name, duration, poster } of todo) {
  const dir = path.join(SCRATCH, name);
  await rm(dir, { recursive: true, force: true });
  await mkdir(dir, { recursive: true });

  const frames = Math.round(duration * FPS);
  process.stdout.write(`  ${name.padEnd(14)} ${frames} frames `);
  for (let f = 0; f < frames; f++) {
    await page.evaluate((n, t) => window.__render(n, t), name, f / FPS);
    await page.screenshot({ path: path.join(dir, `f_${String(f).padStart(5, '0')}.png`), optimizeForSpeed: true });
  }

  const scale = `scale=${OUT_W}:${OUT_H}:flags=lanczos,format=yuv420p`;
  // Same encode reasoning as ../encode.sh: the clips are almost entirely dark
  // blues and near-blacks, where the default CRF leaves visible contouring.
  await run('ffmpeg', ['-y', '-loglevel', 'error', '-framerate', String(FPS),
    '-i', path.join(dir, 'f_%05d.png'), '-vf', scale,
    '-c:v', 'libx264', '-preset', 'slow', '-crf', '20', '-x264-params', 'aq-mode=3',
    '-pix_fmt', 'yuv420p', '-movflags', '+faststart', '-r', String(FPS),
    path.join(OUT, `${name}.mp4`)]);
  await run('ffmpeg', ['-y', '-loglevel', 'error', '-framerate', String(FPS),
    '-i', path.join(dir, 'f_%05d.png'), '-vf', scale,
    '-c:v', 'libvpx-vp9', '-crf', '34', '-b:v', '0', '-row-mt', '1',
    '-deadline', 'good', '-cpu-used', '3', '-r', String(FPS),
    path.join(OUT, `${name}.webm`)]);
  // Each clip names the moment that represents it. Left to a fixed fraction
  // this lands mid-transition — the battery card's poster showed no battery.
  const posterFrame = Math.min(frames - 1, Math.round((poster ?? duration * 0.55) * FPS));
  await run('ffmpeg', ['-y', '-loglevel', 'error',
    '-i', path.join(dir, `f_${String(posterFrame).padStart(5, '0')}.png`),
    '-vf', `scale=${OUT_W}:${OUT_H}:flags=lanczos`, '-q:v', '4',
    path.join(OUT, `${name}.jpg`)]);

  await rm(dir, { recursive: true, force: true });
  console.log('✓');
}

await rm(SCRATCH, { recursive: true, force: true });
await browser.close();
console.log(`\nDone → ${OUT}`);
