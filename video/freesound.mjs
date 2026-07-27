/* =========================================================================
   Fetch candidate UI sounds from Freesound for the "freesound" sound set.

   Searches one query per cue slot, restricted to CC0 so nothing carries an
   attribution obligation, and downloads a few candidates each into
   sfx/freesound/candidates/<slot>/. The best-scoring candidate is copied to
   sfx/freesound/<slot>.ogg so ./social.sh freesound works immediately; the
   rest are there to swap in from the audition page.

   Full-quality downloads need OAuth2, but preview-hq-ogg (~192kbps) does not,
   and is more than enough for short interface sounds in a video every platform
   re-encodes anyway.

     node freesound.mjs             # fetch candidates + pick defaults
     node freesound.mjs --slot open # just one slot

   Needs a free API key from https://freesound.org/apiv2/apply/ in either
   FREESOUND_API_KEY or video/.freesound-key (gitignored — keep it out of the
   repo).
   ========================================================================= */

import { mkdir, writeFile, readFile, copyFile, rm } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const OUT = path.join(here, 'sfx', 'freesound');
const CAND = path.join(OUT, 'candidates');
const PER_SLOT = 4;

async function apiKey() {
  if (process.env.FREESOUND_API_KEY) return process.env.FREESOUND_API_KEY.trim();
  const f = path.join(here, '.freesound-key');
  if (existsSync(f)) return (await readFile(f, 'utf8')).trim();
  console.error(
    'No API key.\n' +
    '  1. Get one (free, instant): https://freesound.org/apiv2/apply/\n' +
    '  2. Save it:  echo "YOUR_KEY" > video/.freesound-key\n' +
    '     (that path is gitignored)\n' +
    '  or: export FREESOUND_API_KEY=YOUR_KEY');
  process.exit(1);
}

/* One entry per cue slot in sfx/freesound/cues.txt.
   `dur` keeps results the right length for the cue — a tick with a tail would
   smear across the three HUD steps half a second apart.

   Freesound's text query ANDs every term, so a five-word phrase matches almost
   nothing under a CC0 filter. Keep queries to one or two words and let the
   duration filter and download-count ranking do the narrowing. */
const SLOTS = [
  { slot: 'open',        q: 'ui open',       dur: [0.15, 0.9] },
  { slot: 'track',       q: 'ui tap',        dur: [0.02, 0.3] },
  { slot: 'drop-1',      q: 'ui pop',        dur: [0.04, 0.5] },
  { slot: 'drop-2',      q: 'pop soft',      dur: [0.04, 0.5] },
  { slot: 'drop-3',      q: 'thud soft',     dur: [0.04, 0.5] },
  { slot: 'drag',        q: 'whoosh',        dur: [0.15, 1.1] },
  { slot: 'close',       q: 'whoosh down',   dur: [0.15, 0.9] },
  { slot: 'tick-vol',    q: 'ui tick',       dur: [0.01, 0.22] },
  { slot: 'tick-bright', q: 'blip',          dur: [0.01, 0.22] },
  { slot: 'vanish',      q: 'power down',    dur: [0.15, 1.3] },
  { slot: 'endcard',     q: 'chime',         dur: [0.6, 3.2] },
];

async function search(token, { q, dur }) {
  const url = new URL('https://freesound.org/apiv2/search/text/');
  url.searchParams.set('query', q);
  // CC0 only: Creative Commons Attribution would put a credit obligation on a
  // video that has no credits.
  url.searchParams.set('filter',
    `license:"Creative Commons 0" duration:[${dur[0]} TO ${dur[1]}]`);
  url.searchParams.set('fields', 'id,name,username,license,duration,previews,url,avg_rating,num_downloads');
  url.searchParams.set('page_size', String(PER_SLOT * 3));
  url.searchParams.set('token', token);

  const r = await fetch(url);
  if (!r.ok) throw new Error(`search "${q}" → HTTP ${r.status} ${await r.text()}`);
  return (await r.json()).results ?? [];
}

async function download(url, dest) {
  const r = await fetch(url);
  if (!r.ok) throw new Error(`download → HTTP ${r.status}`);
  await writeFile(dest, Buffer.from(await r.arrayBuffer()));
}

const token = await apiKey();
const only = process.argv.includes('--slot')
  ? process.argv[process.argv.indexOf('--slot') + 1] : null;

await mkdir(CAND, { recursive: true });

// Merge into any existing provenance so a single `--slot` run doesn't wipe the
// records for every other slot. Entries for the slot(s) we're re-fetching are
// dropped first, then re-added below.
let provenance = [];
const provPath = path.join(OUT, 'PROVENANCE.json');
if (existsSync(provPath)) {
  try {
    provenance = JSON.parse(await readFile(provPath, 'utf8'))
      .filter(p => !only || p.slot !== only);
  } catch { provenance = []; }
}

for (const spec of SLOTS) {
  if (only && spec.slot !== only) continue;

  let results;
  try {
    results = await search(token, spec);
  } catch (e) {
    console.error(`  ${spec.slot}: ${e.message}`);
    continue;
  }
  if (!results.length) {
    console.log(`  ${spec.slot}: no CC0 results for "${spec.q}"`);
    continue;
  }

  // Prefer things other people actually used; relevance order is the tiebreak.
  const ranked = results
    .filter(s => s.previews?.['preview-hq-ogg'])
    .sort((a, b) => (b.num_downloads ?? 0) - (a.num_downloads ?? 0))
    .slice(0, PER_SLOT);

  const dir = path.join(CAND, spec.slot);
  await rm(dir, { recursive: true, force: true });
  await mkdir(dir, { recursive: true });

  const picked = [];
  for (const [i, s] of ranked.entries()) {
    const file = `${i + 1}_${String(s.id)}.ogg`;
    try {
      await download(s.previews['preview-hq-ogg'], path.join(dir, file));
    } catch (e) {
      console.error(`    ${spec.slot}/${file}: ${e.message}`);
      continue;
    }
    picked.push({ file, ...s });
    provenance.push({
      slot: spec.slot, candidate: file, id: s.id, name: s.name,
      user: s.username, license: s.license, duration: s.duration,
      downloads: s.num_downloads, url: s.url,
    });
  }

  // Default pick = first candidate, so the set is buildable straight away.
  if (picked.length) {
    await copyFile(path.join(dir, picked[0].file), path.join(OUT, `${spec.slot}.ogg`));
    console.log(`  ${spec.slot}: ${picked.length} candidates, default "${picked[0].name}" (${picked[0].duration.toFixed(2)}s)`);
  }
}

provenance.sort((a, b) => a.slot.localeCompare(b.slot) || a.candidate.localeCompare(b.candidate));
await writeFile(provPath, JSON.stringify(provenance, null, 2));

console.log(`\n${provenance.length} files → ${path.relative(here, CAND)}`);
console.log('Provenance written to sfx/freesound/PROVENANCE.json (all CC0).');
console.log('Next: node audition.mjs   then   ./social.sh freesound');
