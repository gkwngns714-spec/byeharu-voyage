// Download Natural Earth 1:110m Admin 0 Countries, slim its properties, and vendor it
// at data/world-110m.json. Also emits scripts/country-bbox.generated.json, the bounding
// boxes that check-ports.mjs uses to sanity-check each port's lat/lon against its country.
//
// Source:  https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_110m_admin_0_countries.geojson
//          (the official Natural Earth vector repository, maintained by NE's own author)
// Licence: Natural Earth data is in the public domain. https://www.naturalearthdata.com/about/terms-of-use/
//
// Geometry is copied through byte-for-byte; only the property bag is reduced.
// Run: node scripts/build-world.mjs
import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..');
const SRC = 'https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_110m_admin_0_countries.geojson';

const res = await fetch(SRC, { headers: { 'User-Agent': 'byeharu-voyage-dataset/0.1' } });
if (!res.ok) throw new Error(`HTTP ${res.status} fetching ${SRC}`);
const raw = await res.text();
console.log(`downloaded ${raw.length} bytes from ${SRC}`);
const fc = JSON.parse(raw);
console.log(`features: ${fc.features.length}`);

const KEEP = ['NAME', 'NAME_LONG', 'ISO_A2', 'ISO_A2_EH', 'ISO_A3', 'ISO_A3_EH', 'CONTINENT', 'REGION_UN', 'SUBREGION'];

const slim = {
  type: 'FeatureCollection',
  _provenance: {
    source: SRC,
    dataset: 'Natural Earth 1:110m Cultural Vectors — Admin 0 Countries',
    licence: 'Public domain (Natural Earth terms of use)',
    licenceUrl: 'https://www.naturalearthdata.com/about/terms-of-use/',
    transform: 'Property bag reduced to ' + KEEP.join(', ') + '; geometry copied unmodified.',
    downloadedAt: new Date().toISOString(),
    sourceBytes: Buffer.byteLength(raw, 'utf8'),
  },
  features: fc.features.map(f => ({
    type: 'Feature',
    properties: Object.fromEntries(KEEP.filter(k => f.properties[k] !== undefined).map(k => [k, f.properties[k]])),
    geometry: f.geometry,
  })),
};

const outPath = join(ROOT, 'data', 'world-110m.json');
const text = JSON.stringify(slim);
writeFileSync(outPath, text + '\n');
console.log(`wrote ${outPath} — ${Buffer.byteLength(text, 'utf8')} bytes`);

// ---- bounding boxes, keyed by ISO 3166-1 alpha-2 ----
function bboxOf(geom) {
  let minLon = 180, minLat = 90, maxLon = -180, maxLat = -90;
  const walk = c => {
    if (typeof c[0] === 'number') {
      const [lon, lat] = c;
      if (lon < minLon) minLon = lon; if (lon > maxLon) maxLon = lon;
      if (lat < minLat) minLat = lat; if (lat > maxLat) maxLat = lat;
    } else for (const x of c) walk(x);
  };
  walk(geom.coordinates);
  return [minLon, minLat, maxLon, maxLat];
}

const round = n => Math.round(n * 10000) / 10000;

function collect(features, scale, into) {
  for (const f of features) {
    const p = f.properties;
    const iso = (p.ISO_A2_EH && p.ISO_A2_EH !== '-99') ? p.ISO_A2_EH
      : (p.ISO_A2 && p.ISO_A2 !== '-99') ? p.ISO_A2 : null;
    if (!iso) continue;
    const b = bboxOf(f.geometry).map(round);
    const prev = into[iso];
    into[iso] = prev
      ? { ...prev, bbox: [Math.min(prev.bbox[0], b[0]), Math.min(prev.bbox[1], b[1]), Math.max(prev.bbox[2], b[2]), Math.max(prev.bbox[3], b[3])] }
      : { name: p.NAME_LONG ?? p.NAME, bbox: b, scale };
  }
  return into;
}

// The bbox table is built from Natural Earth 1:10m, not 110m: the 110m sheet drops
// small islands and dependencies (the Azores, Madeira, the Canaries, Okinawa, Rhodes,
// Jeju, Tsushima, Ceuta, Gibraltar, Macau...), which would make the plausibility test
// reject perfectly correct island ports. 10m is downloaded here but NOT vendored.
const SRC10 = 'https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_admin_0_countries.geojson';
const res10 = await fetch(SRC10, { headers: { 'User-Agent': 'byeharu-voyage-dataset/0.1' } });
if (!res10.ok) throw new Error(`HTTP ${res10.status} fetching ${SRC10}`);
const raw10 = await res10.text();
console.log(`downloaded ${raw10.length} bytes from ${SRC10} (bbox table only, not vendored)`);
const fc10 = JSON.parse(raw10);
const boxes = collect(fc10.features, '10m', {});

// Natural Earth's default point of view excludes the Crimean peninsula from Ukraine, so
// UA's bbox stops north of Feodosia. Natural Earth also publishes point-of-view variants;
// union in the Ukrainian one so UA covers the territory the UN recognises as Ukrainian.
// The number comes from that file, not from a hand-typed coordinate.
const SRC10_UKR = 'https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_admin_0_countries_ukr.geojson';
const resUkr = await fetch(SRC10_UKR, { headers: { 'User-Agent': 'byeharu-voyage-dataset/0.1' } });
if (!resUkr.ok) throw new Error(`HTTP ${resUkr.status} fetching ${SRC10_UKR}`);
const ukrBoxes = collect((await resUkr.json()).features, '10m-ukr', {});
if (boxes.UA && ukrBoxes.UA) {
  const a = boxes.UA.bbox, b = ukrBoxes.UA.bbox;
  boxes.UA.bbox = [Math.min(a[0], b[0]), Math.min(a[1], b[1]), Math.max(a[2], b[2]), Math.max(a[3], b[3])];
  boxes.UA.note = `unioned with Natural Earth's Ukrainian point-of-view file so the bbox covers Crimea (${SRC10_UKR})`;
  console.log(`UA bbox unioned with the Ukrainian point-of-view file: ${JSON.stringify(boxes.UA.bbox)}`);
}

writeFileSync(join(HERE, 'country-bbox.generated.json'), JSON.stringify({
  _provenance: {
    vendoredGeometry: SRC,
    bboxSource: SRC10,
    dataset: 'Natural Earth 1:10m Admin 0 Countries; bbox = min/max of every coordinate in the country geometry',
    licence: 'Public domain (Natural Earth terms of use)',
    note: 'bbox is [minLon, minLat, maxLon, maxLat], rounded to 4 decimal places. Names are Natural Earth NAME_LONG.',
    generatedAt: new Date().toISOString(),
  },
  countries: boxes,
}, null, 1) + '\n');
console.log(`wrote scripts/country-bbox.generated.json — ${Object.keys(boxes).length} ISO alpha-2 codes`);
