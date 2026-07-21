/* =========================================================================
   Frame renderer for the AloeNotch demo video.

   Loads demo.html in headless Chromium, steps `window.__render(t)` one frame
   at a time and screenshots each one. Nothing here depends on wall-clock
   time, so a render is reproducible and can be interrupted and resumed.

     node render.mjs [--fps 60] [--scale 1] [--from 0] [--to 66] [--out frames]
   ========================================================================= */

import puppeteer from 'puppeteer';
import { mkdir, rm } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));

const args = Object.fromEntries(
  process.argv.slice(2).join(' ').split('--').filter(Boolean)
    .map(s => s.trim().split(/\s+/)).map(([k, v]) => [k, v ?? 'true'])
);

const FPS = Number(args.fps ?? 60);
const SCALE = Number(args.scale ?? 1);
const OUT = path.resolve(here, args.out ?? 'frames');
const WIDTH = 1920, HEIGHT = 1080;

const browser = await puppeteer.launch({
  headless: true,
  args: [
    '--force-device-scale-factor=1',
    '--hide-scrollbars',
    '--disable-lcd-text',            // greyscale AA: no colour fringing in H.264
    '--font-render-hinting=none',
    '--allow-file-access-from-files',
    '--disable-gpu-vsync',
  ],
});

const page = await browser.newPage();
await page.setViewport({ width: WIDTH, height: HEIGHT, deviceScaleFactor: SCALE });

const url = 'file://' + path.join(here, 'demo.html');
await page.goto(url, { waitUntil: 'networkidle0' });
await page.evaluateHandle('document.fonts.ready');

const duration = Number(args.to ?? await page.evaluate('window.__DURATION'));
const from = Number(args.from ?? 0);
const first = Math.round(from * FPS);
const last = Math.round(duration * FPS);
const total = last - first;

if (existsSync(OUT) && !args.resume) await rm(OUT, { recursive: true, force: true });
await mkdir(OUT, { recursive: true });

console.log(`Rendering ${total} frames @ ${FPS}fps (${from}s → ${duration}s), ${WIDTH * SCALE}x${HEIGHT * SCALE}`);
const started = Date.now();

for (let f = first; f < last; f++) {
  const t = f / FPS;
  await page.evaluate(t => window.__render(t), t);
  await page.screenshot({
    path: path.join(OUT, `f_${String(f).padStart(6, '0')}.png`),
    optimizeForSpeed: true,
  });

  if ((f - first) % 60 === 0 || f === last - 1) {
    const done = f - first + 1;
    const rate = done / ((Date.now() - started) / 1000);
    const eta = Math.round((total - done) / Math.max(rate, 0.01));
    process.stdout.write(
      `\r  ${done}/${total} frames  ${rate.toFixed(1)} fps  eta ${eta}s   `
    );
  }
}

process.stdout.write('\n');
await browser.close();
console.log(`Done in ${Math.round((Date.now() - started) / 1000)}s → ${OUT}`);
