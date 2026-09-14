// Writes data/region-tint.json — the regions' tint, derived (scripts/lib/region-tint.mjs says
// from what and by which rules). Run:  node scripts/build-region-tint.mjs
// Prints the ambiguity tables the build decided by, so the decision is read, not assumed.

import { writeFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'
import { buildRegionTint, regionTintText } from './lib/region-tint.mjs'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const OUT = join(ROOT, 'data', 'region-tint.json')

const { file, report } = buildRegionTint(ROOT)
const text = regionTintText(file)
writeFileSync(OUT, text)

const fmt = (counts) => counts.map(([r, n]) => `${r} ${n}`).join(', ')
console.log(`sea_cells replayed from: ${report.writes.map((w) => `${w.file.slice(0, 18)} (${w.rows} rows)`).join(', ')}`)
console.log(`water cells ${report.waterCells}, tinted ${report.tintedCells} (${((100 * report.tintedCells) / report.waterCells).toFixed(1)}%), rectangles ${report.rectCount}`)
console.log(`countries with a harbour: ${report.countryCount}`)
console.log(`countries split across regions (tinted by the majority):`)
for (const c of report.splitCountries) console.log(`  ${c.iso} → ${c.region}   [${fmt(c.counts)}]`)
console.log(`sea → region by MAJORITY (measured, NOT used — the water is nearest-harbour-by-water):`)
for (const s of report.seaMajority) console.log(`  ${s.sea} → ${s.region}   [${fmt(s.counts)}]`)
console.log(`harbours with no water cell within 8 rings (seed nothing): ${report.unseeded.join(', ') || 'none'}`)
console.log(`regions touching on the water (${report.touching.length} pairs): ${report.touching.join(' ')}`)
console.log(`wrote ${OUT} (${text.length} bytes)`)
