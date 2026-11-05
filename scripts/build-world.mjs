// Download Natural Earth 1:110m Admin 0 Countries, slim its properties, and vendor it
// at data/world-110m.json. Also emits scripts/country-bbox.generated.json, the bounding
// boxes that check-ports.mjs uses to sanity-check each port's lat/lon against its country.
//
// Source:  https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_110m_admin_0_countries.geojson
//          (the official Natural Earth vector repository, maintained by NE's own author)
// Licence: Natural Earth data is in the public domain. https://www.naturalearthdata.com/about/terms-of-use/
//
// Geometry is copied through byte-for-byte; only the property bag is reduced. The one addition is
// the 28 harbour islands the 110m sheet lacks, taken from the 10m sheet below.
// Run: node scripts/build-world.mjs
import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { deriveWorld } from './lib/world-derive.mjs';
import { simplifyPath } from '../src/lib/geo/simplify.ts';

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

// ---- the harbours' islands (owner row 92, again) ----
// The 110m sheet has no polygon for 28 islands that carry a harbour, so those harbours stood in
// drawn water under a speck. Only THOSE islands are taken from the 10m sheet: the one polygon that
// holds the harbour (or, for Ponta Delgada and Banda Neira, whose coordinate falls just off the
// 10m shore, the nearest within ISLAND_REACH_NM). The rest of the world stays 110m, and so does the
// payload. Each island is decimated HERE, once, at ISLAND_TOLERANCE_DEG, and written with its own
// marker HARBOUR_ISLAND = the harbour's code. The marker is what binds the two readers together:
// src/chart/coastlineBuild.ts draws these points as they stand, and scripts/sea-grid.mjs closes
// every raster cell they touch, so the coast on the chart and the water the fleets sail are the
// same ring and no island can be drawn that a keel sails through.
const HARBOUR_ISLANDS = [
  'AMB', 'ANG', 'BND', 'BRI', 'CHS', 'CID', 'FNC', 'HAD', 'HAG', 'JEJ', 'LPA', 'MAN', 'MLE', 'NAH',
  'PLM', 'PLO', 'PON', 'RHO', 'SAO', 'STG', 'TEN', 'TOR', 'TSU', 'VIS', 'VLL', 'WIL', 'ZAK', 'ZAN',
];
const ISLAND_TOLERANCE_DEG = 0.015; // about a mile: an island is far smaller than the 0.2 deg coast
const ISLAND_REACH_NM = 3;

const inRing = (ring, lon, lat) => {
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [x1, y1] = ring[j];
    const [x2, y2] = ring[i];
    if (y1 > lat !== y2 > lat && lon < x1 + ((lat - y1) / (y2 - y1)) * (x2 - x1)) inside = !inside;
  }
  return inside;
};
const shoreNm = (ring, lon, lat) => {
  const k = Math.cos(lat * Math.PI / 180);
  return Math.min(...ring.map(([x, y]) => Math.hypot((x - lon) * k, y - lat) * 60));
};
function harbourIslands(features) {
  const polys = [];
  for (const f of features) {
    const g = f.geometry;
    for (const p of g.type === 'Polygon' ? [g.coordinates] : g.coordinates) polys.push({ ring: p[0], iso: f.properties.ISO_A2_EH });
  }
  const ports = deriveWorld().ports;
  return HARBOUR_ISLANDS.map((code) => {
    const port = ports.find((p) => p.code === code);
    if (!port) throw new Error(`${code}: no such harbour`);
    const hit = polys.find((p) => inRing(p.ring, port.lon, port.lat))
      ?? polys.map((p) => ({ ...p, nm: shoreNm(p.ring, port.lon, port.lat) })).sort((a, b) => a.nm - b.nm).find((p) => p.nm <= ISLAND_REACH_NM);
    if (!hit) throw new Error(`${code}: no 10m polygon within ${ISLAND_REACH_NM} nm of ${port.name}`);
    const coords = simplifyPath(hit.ring.map(([x, y]) => ({ x, y })), ISLAND_TOLERANCE_DEG)
      .map((p) => [Number(p.x.toFixed(3)), Number(p.y.toFixed(3))])
      .filter((p, i, all) => i === 0 || p[0] !== all[i - 1][0] || p[1] !== all[i - 1][1]);
    if (coords.length < 4) throw new Error(`${code}: the island collapsed to ${coords.length} points`);
    return {
      type: 'Feature',
      properties: { NAME: port.name, ISO_A2_EH: hit.iso, HARBOUR_ISLAND: code },
      geometry: { type: 'Polygon', coordinates: [coords] },
    };
  });
}
const islands = harbourIslands(fc10.features);
slim.features.push(...islands);
slim._provenance.islands = `${islands.length} harbour islands from ${SRC10}, marked HARBOUR_ISLAND, decimated at ${ISLAND_TOLERANCE_DEG} deg; the other features are unmodified.`;

const outPath = join(ROOT, 'data', 'world-110m.json');
const text = JSON.stringify(slim);
writeFileSync(outPath, text + '\n');
console.log(`wrote ${outPath} — ${Buffer.byteLength(text, 'utf8')} bytes, ${islands.length} harbour islands, ${islands.reduce((n, f) => n + f.geometry.coordinates[0].length, 0)} island points`);

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
