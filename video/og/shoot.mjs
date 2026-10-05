// Renders og.html to ../../site/assets/og.jpg (1200x630, the og:image size).
import puppeteer from 'puppeteer';
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const here = path.dirname(fileURLToPath(import.meta.url));
const b = await puppeteer.launch({ headless: true, args: ['--force-device-scale-factor=1', '--allow-file-access-from-files'] });
const p = await b.newPage();
await p.setViewport({ width: 1200, height: 630 });
await p.goto('file://' + path.join(here, 'og.html'), { waitUntil: 'networkidle0' });
await p.screenshot({ path: path.join(here, 'og.png') });
await b.close();
execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-i', path.join(here, 'og.png'), '-q:v', '3',
  path.resolve(here, '../../site/assets/og.jpg')]);
console.log('→ site/assets/og.jpg');
