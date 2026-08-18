// Audit: how far is each port from a coastline? Confirms no landlocked city slipped in,
// and names the river and estuary ports that are legitimately some way inland.
//
// Source:  https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_coastline.geojson
// Licence: public domain (Natural Earth).
// This script needs the network; scripts/check-ports.mjs does not. Run: node scripts/check-coastal.mjs
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const DATA = join(dirname(fileURLToPath(import.meta.url)), '..', 'data');
const ports = JSON.parse(readFileSync(join(DATA, 'ports.json'), 'utf8')).ports;

const SRC = 'https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_coastline.geojson';
const res = await fetch(SRC, { headers: { 'User-Agent': 'byeharu-voyage-dataset/0.1' } });
if (!res.ok) throw new Error(`HTTP ${res.status} fetching ${SRC}`);
const fc = await res.json();

const verts = [];
const walk = c => { if (typeof c[0] === 'number') verts.push(c); else for (const x of c) walk(x); };
for (const f of fc.features) walk(f.geometry.coordinates);
console.log(`Natural Earth 1:10m coastline — ${fc.features.length} lines, ${verts.length} vertices`);

const R = 6371.0088;
const rad = d => d * Math.PI / 180;
function haversine(lat1, lon1, lat2, lon2) {
  const dLat = rad(lat2 - lat1), dLon = rad(lon2 - lon1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

const rows = ports.map(p => {
  let best = Infinity;
  for (const [lon, lat] of verts) {
    // cheap rejection before the expensive trig
    if (Math.abs(lat - p.lat) > 8) continue;
    const dLon = Math.abs(lon - p.lon);
    if (dLon > 8 && dLon < 352) continue;
    const d = haversine(p.lat, p.lon, lat, lon);
    if (d < best) best = d;
  }
  return { id: p.id, name: p.name, country: p.country, km: best };
}).sort((a, b) => b.km - a.km);

console.log('\nfarthest from a coastline vertex (kilometres):');
for (const r of rows.slice(0, 20)) console.log(`  ${r.km.toFixed(1).padStart(7)} km  ${r.id} (${r.country}) — ${r.name}`);

const median = rows[Math.floor(rows.length / 2)].km;
console.log(`\nmedian distance ${median.toFixed(1)} km; ${rows.filter(r => r.km <= 25).length} of ${rows.length} ports within 25 km of a coastline vertex.`);
console.log('Note: this measures distance to the nearest coastline VERTEX, not to the nearest point on the');
console.log('coastline segment, so every figure is an over-estimate. Anything above ~40 km should be a');
console.log('known river or estuary port and is listed above for human review.');
