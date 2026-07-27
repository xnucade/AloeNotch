/* Build out/audition.html — every downloaded candidate as a play button,
   grouped by cue slot, with the cue's timecode and what it needs to sound
   like. Open it, click through, and note which candidate wins each slot.

     node audition.mjs [variant]      # default: freesound
     open out/audition.html

   To promote a candidate, copy it over the slot file and rebuild:
     cp sfx/freesound/candidates/open/3_12345.ogg sfx/freesound/open.ogg
     ./social.sh freesound
   The page prints the exact command under each candidate.
*/

import { readdir, writeFile, readFile, mkdir } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const variant = process.argv[2] ?? 'freesound';
const root = path.join(here, 'sfx', variant);
const cand = path.join(root, 'candidates');

if (!existsSync(cand)) {
  console.error(`No candidates at sfx/${variant}/candidates — run: node freesound.mjs`);
  process.exit(1);
}

/* What each slot is for. Mirrors sfx/<variant>/cues.txt. */
const NOTES = {
  'open':        ['8.4s',            'Panel springs open. The hero sound — soft rising swell, not a click.'],
  'track':       ['23.6s, 26.4s',    'Track change. Very short, very quiet — should almost pass unnoticed.'],
  'drop-1':      ['31.1s',           'First file lands on the shelf. Soft landing with body, not a beep.'],
  'drop-2':      ['32.9s',           'Second file. Should differ audibly from drop-1.'],
  'drop-3':      ['34.5s',           'Third file. Different again.'],
  'drag':        ['36.65s',          'Stack drags out to the desktop. Short airy whoosh.'],
  'close':       ['48.0s',           'Panel collapses. The counterpart to open — falling, not rising.'],
  'tick-vol':    ['49.9/50.4/50.9s', 'Volume steps. Plays 3x half a second apart — any tail will smear.'],
  'tick-bright': ['52.8/53.3/53.8s', 'Brightness steps. Brighter than tick-vol so they read as different.'],
  'vanish':      ['56.4s',           'Strip goes invisible. Quiet, soft, conclusive.'],
  'endcard':     ['60.35s',          'End card. The one sound allowed length and warmth.'],
};

let provenance = [];
const pf = path.join(root, 'PROVENANCE.json');
if (existsSync(pf)) provenance = JSON.parse(await readFile(pf, 'utf8'));
const meta = new Map(provenance.map(p => [`${p.slot}/${p.candidate}`, p]));

const slots = (await readdir(cand, { withFileTypes: true }))
  .filter(d => d.isDirectory()).map(d => d.name)
  .sort((a, b) => (Object.keys(NOTES).indexOf(a)) - (Object.keys(NOTES).indexOf(b)));

let body = '';
for (const slot of slots) {
  const files = (await readdir(path.join(cand, slot))).filter(f => /\.(ogg|mp3|wav)$/.test(f)).sort();
  const [time, note] = NOTES[slot] ?? ['', ''];
  body += `<section>
    <h2>${slot} <span class="t">${time}</span></h2>
    <p class="note">${note}</p>
    <div class="rows">`;
  for (const [i, f] of files.entries()) {
    const m = meta.get(`${slot}/${f}`);
    const rel = path.posix.join('..', 'sfx', variant, 'candidates', slot, f);
    const title = m ? m.name : f;
    const sub = m
      ? `${m.duration.toFixed(2)}s · ${m.downloads.toLocaleString()} downloads · ${m.user} · <a href="${m.url}" target="_blank">Freesound</a>`
      : '';
    body += `<div class="row${i === 0 ? ' current' : ''}">
        <button onclick="play(this,'${rel}')">▶</button>
        <div class="meta"><strong>${title}</strong>${i === 0 ? ' <em>(current default)</em>' : ''}<br><small>${sub}</small>
          <code>cp sfx/${variant}/candidates/${slot}/${f} sfx/${variant}/${slot}.ogg</code>
        </div>
      </div>`;
  }
  body += `</div></section>`;
}

const html = `<!doctype html><meta charset="utf-8"><title>Audition — ${variant}</title>
<style>
 :root{color-scheme:dark}
 body{background:#0b0b0e;color:#f2f2f5;font:15px/1.5 -apple-system,BlinkMacSystemFont,sans-serif;
      max-width:860px;margin:0 auto;padding:48px 24px 96px}
 h1{font-size:30px;letter-spacing:-.5px;margin-bottom:6px}
 .lead{color:#9a9aa5;margin-bottom:36px}
 section{margin:30px 0;padding:20px;background:#141419;border:1px solid #26262e;border-radius:14px}
 h2{font-size:18px;display:flex;align-items:baseline;gap:10px}
 .t{font-size:12px;color:#73bfff;font-weight:500}
 .note{color:#9a9aa5;font-size:13px;margin:4px 0 16px}
 .row{display:flex;gap:14px;align-items:flex-start;padding:10px;border-radius:10px}
 .row.current{background:#1c2430;box-shadow:inset 0 0 0 1px #2f4560}
 button{flex:0 0 auto;width:42px;height:42px;border-radius:50%;border:0;background:#73bfff;
        color:#04101d;font-size:15px;cursor:pointer}
 button.playing{background:#f2f2f5}
 .meta{min-width:0}
 small{color:#8a8a95}
 code{display:block;margin-top:6px;font-size:11px;color:#7c8a9c;
      background:#0b0b0e;padding:5px 8px;border-radius:6px;overflow-x:auto;white-space:nowrap}
 a{color:#73bfff}
</style>
<h1>Audition — ${variant}</h1>
<p class="lead">Click through each slot and note which candidate wins. The first
in each group is the current default. Copy the command under a candidate to
promote it, then run <code style="display:inline">./social.sh ${variant}</code>.</p>
${body}
<script>
let cur=null;
function play(btn,src){
  if(cur){cur.pause();document.querySelectorAll('button').forEach(b=>b.classList.remove('playing'));}
  if(cur&&cur.dataset.src===src){cur=null;return;}
  const a=new Audio(src);a.dataset.src=src;a.play();cur=a;btn.classList.add('playing');
  a.onended=()=>btn.classList.remove('playing');
}
</script>`;

await mkdir(path.join(here, 'out'), { recursive: true });
await writeFile(path.join(here, 'out', 'audition.html'), html);
console.log(`out/audition.html — ${slots.length} slots`);
console.log('open out/audition.html');
