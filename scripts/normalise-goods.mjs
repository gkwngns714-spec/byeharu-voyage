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
  seaweed: 'dried-fish', kelp: 'dried-fish', abalone: 'dried-fish',
  cork: 'olive-oil', soap: 'olive-oil', 'palm-oil': 'olive-oil',
  grain: 'wheat', sago: 'rice', 'sweet-potato': 'rice',
  oxen: 'salted-beef', cattle: 'salted-beef', butter: 'cheese',
  honey: 'sugar',
  raisins: 'dried-fruit', currants: 'dried-fruit', figs: 'dried-fruit', citrus: 'dried-fruit',
  dates: 'dried-fruit', almonds: 'dried-fruit', cashew: 'dried-fruit', kola: 'dried-fruit',
  fruit: 'dried-fruit', 'areca-nut': 'dried-fruit',
  gin: 'wine', brandy: 'wine', rum: 'wine', sake: 'wine', beer: 'wine', 'malmsey-wine': 'wine',
  woad: 'indigo', orchil: 'indigo', lac: 'indigo', gamboge: 'indigo',
  annatto: 'cochineal',
  dyewood: 'logwood', redwood: 'logwood',
  sappanwood: 'brazilwood',
  potash: 'alum',
  coal: 'iron', lead: 'iron', matchlocks: 'iron', mercury: 'silver',
  ceramics: 'porcelain', celadon: 'porcelain',
  carnelian: 'diamonds', gems: 'diamonds', emeralds: 'diamonds', rubies: 'diamonds',
  spices: 'black-pepper', pepper: 'black-pepper', 'clove-bark': 'cloves',
  textiles: 'cotton-cloth', 'raffia-cloth': 'cotton-cloth',
  paper: 'linen', 'hanji-paper': 'linen',
  'coconut-coir': 'hemp', cordage: 'hemp',
  'mangrove-poles': 'timber', teak: 'timber', cedar: 'timber', rattan: 'timber',
  'train-oil': 'whale-oil', whalebone: 'whale-oil',
  'walrus-ivory': 'ivory', elephants: 'ivory',
  sealskins: 'furs', 'ostrich-feathers': 'furs',
  incense: 'frankincense', civet: 'musk', 'birds-nests': 'musk',
  camphor: 'sandalwood', benzoin: 'sandalwood', aloeswood: 'sandalwood',
  senna: 'gum-arabic', sarsaparilla: 'gum-arabic', sassafras: 'gum-arabic',
  rhubarb: 'ginseng',
  deerhides: 'hides', leather: 'hides',
  sponges: 'coral', tortoiseshell: 'coral',
  pitch: 'tar', tallow: 'wax',
  hazelnuts: 'dried-fruit', rosewater: 'musk',
  // dropped: no defensible canonical equivalent
  water: null, guano: null,
};

const goods = JSON.parse(readFileSync(join(HERE, '..', 'data', 'goods.json'), 'utf8'));
const canonical = new Set(goods.goods.map(g => g.id));

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
