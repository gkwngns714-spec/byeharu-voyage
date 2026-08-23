// One-off: fold the roster's free-hand goods vocabulary onto the 70 canonical ids in
// data/goods.json, in place, and report anything that does not map.
// Run: node scripts/normalise-goods.mjs
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
const FILES = ['europe', 'africa-indian-ocean', 'east-asia', 'americas'].map(n => join(HERE, 'roster', `${n}.mjs`));

// roster term -> canonical goods id. Terms already canonical are absent from this map.
const MAP = {
  'salt-cod': 'dried-fish', stockfish: 'dried-fish', salmon: 'dried-fish',
  kelp: 'dried-fish', abalone: 'dried-fish',
    grain: 'wheat', 'sweet-potato': 'rice',
  oxen: 'salted-beef', cattle: 'salted-beef',     raisins: 'dried-fruit', currants: 'dried-fruit',   cashew: 'dried-fruit', kola: 'dried-fruit',
  fruit: 'dried-fruit', 'areca-nut': 'dried-fruit',
  gin: 'wine', 'malmsey-wine': 'wine',
      dyewood: 'logwood', redwood: 'logwood',
      matchlocks: 'iron', mercury: 'silver',
  ceramics: 'porcelain',   gems: 'diamonds',   spices: 'black-pepper', pepper: 'black-pepper', 'clove-bark': 'cloves',
  textiles: 'cotton-cloth',   'hanji-paper': 'linen',
  'coconut-coir': 'hemp', cordage: 'hemp',
    'train-oil': 'whale-oil', whalebone: 'whale-oil',
      incense: 'frankincense',         deerhides: 'hides', leather: 'hides',
    pitch: 'tar',     // dropped: no defensible canonical equivalent
  water: null, guano: null,
};

const goods = JSON.parse(readFileSync(join(HERE, '..', 'data', 'goods.json'), 'utf8'));
const canonical = new Set(goods.goods.map(g => g.id));

// The invariant the header states, enforced: a term that IS a canonical good id must not appear
// as a MAP key — it would silently rewrite a real good into a different one. This bit when the
// catalogue grew 70 -> 243 and forty-odd folded terms (dates, rum, celadon, sappanwood...) became
// goods in their own right; their fold entries were deleted, and this guard keeps the class dead.
for (const k of Object.keys(MAP)) {
  if (canonical.has(k)) throw new Error(`MAP key "${k}" is a canonical good id — delete the fold entry`)
}

const unmapped = new Set();
let arrays = 0;

for (const file of FILES) {
  const src = readFileSync(file, 'utf8');
  const next = src.replace(/goods: \[([^\]]*)\]/g, (whole, body) => {
    arrays++;
    const terms = body.split(',').map(s => s.trim().replace(/^'|'$/g, '')).filter(Boolean);
    const mapped = [];
    for (const t of terms) {
      const to = Object.hasOwn(MAP, t) ? MAP[t] : t;
      if (to === null) continue;
      if (!canonical.has(to)) { unmapped.add(`${t}${to !== t ? ` -> ${to}` : ''}`); continue; }
      if (!mapped.includes(to)) mapped.push(to);
    }
    return `goods: [${mapped.map(g => `'${g}'`).join(', ')}]`;
  });
  writeFileSync(file, next);
}

console.log(`rewrote ${arrays} goods arrays across ${FILES.length} roster files`);
if (unmapped.size) {
  console.log(`\nUNMAPPED terms (${unmapped.size}) — add them to MAP or to data/goods.json:`);
  for (const t of [...unmapped].sort()) console.log('  ', t);
  process.exitCode = 1;
} else {
  console.log('every roster goods term resolves to a canonical goods id.');
}
