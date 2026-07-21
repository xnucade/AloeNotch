/* Render a handful of timestamps to out/probe/ for eyeballing, and report any
   page errors. Much faster than a full render when iterating on the timeline.

     node probe.mjs 0 3 8 12 16 20 26 33 41 50 58 62
*/
import puppeteer from 'puppeteer';
import { mkdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const times = process.argv.slice(2).map(Number);
if (!times.length) { console.error('usage: node probe.mjs <t> [t...]'); process.exit(1); }

const OUT = path.join(here, 'out', 'probe');
await mkdir(OUT, { recursive: true });

const browser = await puppeteer.launch({
  headless: true,
  args: ['--force-device-scale-factor=1', '--hide-scrollbars', '--disable-lcd-text',
         '--font-render-hinting=none', '--allow-file-access-from-files'],
});
const page = await browser.newPage();
await page.setViewport({ width: 1920, height: 1080, deviceScaleFactor: 1 });

const problems = [];
page.on('pageerror', e => problems.push('pageerror: ' + e.message));
page.on('console', m => { if (m.type() === 'error') problems.push('console: ' + m.text()); });
page.on('requestfailed', r => problems.push('requestfailed: ' + r.url()));

await page.goto('file://' + path.join(here, 'demo.html'), { waitUntil: 'networkidle0' });
await page.evaluateHandle('document.fonts.ready');

// Confirm the system fonts we rely on actually resolved.
const fonts = await page.evaluate(() => ({
  body: getComputedStyle(document.body).fontFamily,
  hasRounded: document.fonts.check('700 19px "SF Pro Rounded"'),
  hasSF: document.fonts.check('600 13px "SF Pro Text"'),
}));
console.log('fonts:', JSON.stringify(fonts));

for (const t of times) {
  await page.evaluate(t => window.__render(t), t);
  const name = `t${String(t).replace('.', '_')}.png`;
  await page.screenshot({ path: path.join(OUT, name) });
  console.log('wrote', name);
}

await browser.close();
if (problems.length) { console.log('\nPROBLEMS:'); problems.forEach(p => console.log(' -', p)); }
else console.log('\nno page errors');
