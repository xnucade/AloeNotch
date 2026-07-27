/* =========================================================================
   Rewrite each sound set's cue times from the timeline.

   timeline.js is the single source of truth: it exports `window.__CUES` as an
   ordered list of {slot, t}. This reads that list and rewrites the leading
   timestamp of every cue line in sfx/<set>/cues.txt, leaving the file, gain,
   pan, extra filter, and all comments untouched.

   Run it after ANY change to scene timings, then rebuild the beds:

     node sync-cues.mjs
     ./social.sh kenney && ./social.sh freesound

   Without this the audio silently drifts off the picture — the cue times used
   to live in three files at once, which is exactly how that happens.
   ========================================================================= */

import puppeteer from 'puppeteer';
import { readFile, writeFile, readdir } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));

/* --- Read the cue list straight out of the timeline --------------------- */
const browser = await puppeteer.launch({
  headless: true,
  args: ['--allow-file-access-from-files', '--hide-scrollbars'],
});
const page = await browser.newPage();
const problems = [];
page.on('pageerror', e => problems.push(e.message));
await page.goto('file://' + path.join(here, 'demo.html'), { waitUntil: 'networkidle0' });
const cues = await page.evaluate(() => window.__CUES);
const duration = await page.evaluate(() => window.__DURATION);
await browser.close();

if (problems.length) {
  console.error('timeline.js raised errors, refusing to sync:');
  problems.forEach(p => console.error(' -', p));
  process.exit(1);
}
if (!Array.isArray(cues) || !cues.length) {
  console.error('window.__CUES is missing or empty — is it still exported?');
  process.exit(1);
}

console.log(`timeline: ${duration}s, ${cues.length} cues`);

/* --- Rewrite each set --------------------------------------------------- */
const sfxRoot = path.join(here, 'sfx');
const sets = (await readdir(sfxRoot, { withFileTypes: true }))
  .filter(d => d.isDirectory())
  .map(d => d.name)
  .filter(name => existsSync(path.join(sfxRoot, name, 'cues.txt')));

let failed = false;

for (const set of sets) {
  const file = path.join(sfxRoot, set, 'cues.txt');
  const lines = (await readFile(file, 'utf8')).split('\n');

  // Cue lines are the ones that start with a number; everything else is
  // comment or blank and must survive untouched.
  const cueIdx = lines
    .map((l, i) => ({ l, i }))
    .filter(({ l }) => /^\s*[\d.]+\s+\S/.test(l))
    .map(({ i }) => i);

  if (cueIdx.length !== cues.length) {
    console.error(
      `  ${set}: has ${cueIdx.length} cue lines but the timeline exports ` +
      `${cues.length}. Reconcile them by hand — refusing to guess which is which.`);
    failed = true;
    continue;
  }

  cueIdx.forEach((lineNo, n) => {
    // Replace only the leading timestamp; keep the original column alignment.
    lines[lineNo] = lines[lineNo].replace(
      /^(\s*)([\d.]+)(\s+)/,
      (_, pre, oldT, gap) => {
        const newT = cues[n].t.toFixed(2);
        // Preserve the column by padding to the old field width where we can.
        const width = Math.max(oldT.length + gap.length, newT.length + 1);
        return pre + newT.padEnd(width);
      });
  });

  await writeFile(file, lines.join('\n'));
  console.log(`  ${set}: ${cueIdx.length} cue times updated`);
}

if (failed) process.exit(1);
console.log('\nNow rebuild the beds:  ./social.sh kenney && ./social.sh freesound');
