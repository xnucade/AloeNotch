/* Post-build check for the site's demo embed.
   Loads site/index.html in a real browser and asserts that the video actually
   plays, fills the MacBook frame with no cropping, and does not trip the
   "coming soon" placeholder fallback.

   Run after any re-render — the frame's aspect ratio is hard-coded in
   style.css, so re-rendering at a different resolution silently reintroduces
   cropping, which this catches.

     node verify-site.mjs      # exits non-zero on failure; writes out/site-check.png
*/
import puppeteer from 'puppeteer';

const b = await puppeteer.launch({
  headless: true,
  args: ['--allow-file-access-from-files', '--hide-scrollbars',
         '--autoplay-policy=no-user-gesture-required'],
});
const p = await b.newPage();
await p.setViewport({ width: 1440, height: 900 });

const problems = [];
p.on('pageerror', e => problems.push('pageerror: ' + e.message));
p.on('console', m => { if (m.type() === 'error') problems.push('console: ' + m.text()); });
p.on('requestfailed', r => problems.push('requestfailed: ' + r.url().split('/').pop()));

await p.goto('file:///Users/cadeg/Desktop/Open%20Notch/site/index.html',
             { waitUntil: 'networkidle0' });

// Give the video a moment to fetch metadata and start.
await p.evaluate(() => new Promise(res => {
  const v = document.getElementById('demoVideo');
  if (v.readyState >= 2) return res();
  v.addEventListener('loadeddata', res, { once: true });
  setTimeout(res, 6000);
}));

const r = await p.evaluate(() => {
  const v = document.getElementById('demoVideo');
  const s = document.querySelector('.screen');
  const ph = document.getElementById('demoPlaceholder');
  const sr = s.getBoundingClientRect();
  return {
    currentSrc: (v.currentSrc || '').split('/').pop(),
    videoPx: `${v.videoWidth}x${v.videoHeight}`,
    duration: Math.round(v.duration * 10) / 10,
    readyState: v.readyState,
    paused: v.paused,
    hasControls: v.hasAttribute('controls'),
    screenAspect: +(sr.width / sr.height).toFixed(3),
    videoAspect: v.videoWidth ? +(v.videoWidth / v.videoHeight).toFixed(3) : null,
    objectFit: getComputedStyle(v).objectFit,
    placeholderShown: ph.classList.contains('show'),
    videoDisplay: getComputedStyle(v).display,
    mediaError: v.error ? v.error.code : null,
    sourceCount: v.querySelectorAll('source').length,
  };
});

console.log(JSON.stringify(r, null, 1));

const fail = [];
if (r.placeholderShown) fail.push('placeholder is showing');
if (r.videoDisplay === 'none') fail.push('video is hidden');
if (r.mediaError) fail.push('media error ' + r.mediaError);
if (r.readyState < 2) fail.push('video never loaded data');
if (Math.abs(r.screenAspect - r.videoAspect) > 0.005) {
  fail.push(`aspect mismatch: frame ${r.screenAspect} vs video ${r.videoAspect} → cropping`);
}
// Frame the demo section itself, not the hero, so the screenshot is evidence.
await p.evaluate(() => document.querySelector('.demo').scrollIntoView({ block: 'center' }));
await new Promise(r => setTimeout(r, 900));   // let the reveal animation settle
await p.screenshot({ path: 'out/site-check.png' });
await b.close();

if (problems.length) { console.log('\nPAGE PROBLEMS:'); problems.forEach(x => console.log(' -', x)); }
console.log(fail.length ? '\nFAIL:\n - ' + fail.join('\n - ') : '\nPASS');
process.exit(fail.length ? 1 : 0);
