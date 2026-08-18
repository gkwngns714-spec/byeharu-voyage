// Compose data/ports.json from the roster (editorial fields) + scripts/coords.cache.json
// (coordinates fetched from Wikidata). Country names come from Natural Earth NAME_LONG.
// Run: node scripts/build-ports.mjs
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

import europe from './roster/europe.mjs';
import afrIo from './roster/africa-indian-ocean.mjs';
import easia from './roster/east-asia.mjs';
import americas from './roster/americas.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..');
const roster = [...europe, ...afrIo, ...easia, ...americas];

const cache = JSON.parse(readFileSync(join(HERE, 'coords.cache.json'), 'utf8'));
const bboxes = JSON.parse(readFileSync(join(HERE, 'country-bbox.generated.json'), 'utf8')).countries;

// Natural Earth's short forms, adjusted to the names this project uses in prose.
const NAME_OVERRIDE = {
  CV: 'Cape Verde', FO: 'Faroe Islands', MO: 'Macau', KR: 'South Korea', KP: 'North Korea',
  CD: 'DR Congo', TL: 'Timor-Leste', CI: "Côte d'Ivoire", GB: 'United Kingdom', US: 'United States',
  AE: 'United Arab Emirates', TZ: 'Tanzania', MM: 'Myanmar', VN: 'Vietnam', LA: 'Laos',
  RU: 'Russia', IR: 'Iran', SY: 'Syria', VE: 'Venezuela', BO: 'Bolivia', MD: 'Moldova',
};

const missingName = [];
const ports = roster.map(p => {
  const c = cache.entries[p.id];
  if (!c) throw new Error(`no resolved coordinate for ${p.id} — run scripts/fetch-coords.mjs`);
  const countryName = NAME_OVERRIDE[p.country] ?? bboxes[p.country]?.name;
  if (!countryName) missingName.push(p.country);
  return {
    id: p.id,
    name: p.name,
    localName: p.localName,
    country: p.country,
    countryName: countryName ?? null,
    lat: Math.round(c.lat * 1e6) / 1e6,
    lon: Math.round(c.lon * 1e6) / 1e6,
    sea: p.sea,
    region: p.region,
    tier: p.tier,
    historicalNames: p.historicalNames,
    goods: p.goods,
    notes: p.notes,
    source: { wikidata: c.qid, enwiki: c.wikiResolved },
  };
});

if (missingName.length) {
  console.error(`no country name for: ${[...new Set(missingName)].join(', ')}`);
  process.exit(1);
}

ports.sort((a, b) => a.id.localeCompare(b.id));

const doc = {
  $schema: './ports.schema.md',
  note: 'Real port cities of the ~1500-1650 Age of Sail. lat/lon are Wikidata property P625 (CC0), fetched by scripts/fetch-coords.mjs and never hand-typed; `source` records the exact item each coordinate came from. `sea`, `region`, `tier`, `goods` and `notes` are editorial. See docs/WORLD_DATA.md.',
  coordinateSource: {
    dataset: 'Wikidata',
    property: 'P625 (coordinate location)',
    licence: 'CC0 1.0 Universal',
    url: 'https://www.wikidata.org/',
    fetchedAt: cache.fetchedAt,
  },
  count: ports.length,
  ports,
};

const out = join(ROOT, 'data', 'ports.json');
writeFileSync(out, JSON.stringify(doc, null, 2) + '\n');
console.log(`wrote ${out} — ${ports.length} ports`);

const byTier = ports.reduce((m, p) => (m[p.tier] = (m[p.tier] ?? 0) + 1, m), {});
console.log('tiers:', JSON.stringify(byTier));
console.log('countries:', new Set(ports.map(p => p.country)).size);
