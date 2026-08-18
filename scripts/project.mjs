// Reference implementation of the three map projections evaluated in docs/WORLD_DATA.md,
// plus a round-trip test of the recommended one. Run: node scripts/project.mjs
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const DATA = join(dirname(fileURLToPath(import.meta.url)), '..', 'data');
const ports = JSON.parse(readFileSync(join(DATA, 'ports.json'), 'utf8')).ports;

// --- the recommended projection: cropped equirectangular (plate carree) ---
export const VIEW = { lonMin: -180, lonMax: 180, latMin: -58, latMax: 82, width: 3600, height: 1400 };

export function project({ lat, lon }, v = VIEW) {
  return {
    x: (lon - v.lonMin) / (v.lonMax - v.lonMin) * v.width,
    y: (v.latMax - lat) / (v.latMax - v.latMin) * v.height,
  };
}
export function unproject({ x, y }, v = VIEW) {
  return {
    lon: x / v.width * (v.lonMax - v.lonMin) + v.lonMin,
    lat: v.latMax - y / v.height * (v.latMax - v.latMin),
  };
}

// --- the alternatives, for comparison ---
const rad = d => d * Math.PI / 180;
export const millerY = lat => 1.25 * Math.log(Math.tan(Math.PI / 4 + 0.4 * rad(lat)));
export const millerYInverse = y => (2.5 * (Math.atan(Math.exp(0.8 * y)) - Math.PI / 4)) * 180 / Math.PI;
export const mercatorY = lat => Math.log(Math.tan(Math.PI / 4 + rad(Math.max(-85.0511, Math.min(85.0511, lat))) / 2));

console.log(`recommended view: equirectangular, lon [${VIEW.lonMin}, ${VIEW.lonMax}], lat [${VIEW.latMin}, ${VIEW.latMax}], ${VIEW.width} x ${VIEW.height}`);
console.log(`aspect ratio ${(VIEW.lonMax - VIEW.lonMin)} : ${(VIEW.latMax - VIEW.latMin)} = ${((VIEW.lonMax - VIEW.lonMin) / (VIEW.latMax - VIEW.latMin)).toFixed(3)} : 1\n`);

for (const id of ['lisbon', 'busan', 'longyearbyen', 'buenos-aires', 'honolulu', 'malacca']) {
  const p = ports.find(q => q.id === id);
  const { x, y } = project(p);
  const back = unproject({ x, y });
  const err = Math.max(Math.abs(back.lat - p.lat), Math.abs(back.lon - p.lon));
  console.log(`${id.padEnd(14)} (${p.lat.toFixed(4)}, ${p.lon.toFixed(4)}) -> x ${x.toFixed(1).padStart(7)}  y ${y.toFixed(1).padStart(7)}   round-trip error ${err.toExponential(2)}`);
}

let worst = 0;
for (const p of ports) {
  const b = unproject(project(p));
  worst = Math.max(worst, Math.abs(b.lat - p.lat), Math.abs(b.lon - p.lon));
}
console.log(`\nround-trip over all ${ports.length} ports: worst error ${worst.toExponential(2)} degrees`);

const outside = ports.filter(p => p.lat < VIEW.latMin || p.lat > VIEW.latMax);
console.log(`ports outside the recommended latitude crop: ${outside.length ? outside.map(p => p.id).join(', ') : 'none'}`);

// How much does each projection stretch the far north relative to the equator?
console.log('\nvertical stretch at latitude, relative to the equator (1.00 = no stretch):');
console.log('  lat   equirect   miller   mercator');
for (const lat of [0, 30, 45, 60, 70, 78]) {
  const d = 0.001;
  const m = (millerY(lat + d) - millerY(lat - d)) / (millerY(d) - millerY(-d));
  const w = (mercatorY(lat + d) - mercatorY(lat - d)) / (mercatorY(d) - mercatorY(-d));
  console.log(`  ${String(lat).padStart(3)}     1.00     ${m.toFixed(2).padStart(4)}     ${w.toFixed(2).padStart(5)}`);
}
