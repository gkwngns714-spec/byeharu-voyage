// players.mjs <world.tar.gz> <out.json> <migration.sql> — the PLAYER half of the 0220 pair (2026-10-25).
// Opens the world prep.mjs dumped (prod's state, 0205–0216 applied), measures player.sql as it stands
// (BEFORE), then in ONE transaction applies the migration under test and measures player.sql again
// (AFTER) and rolls back — the same world, the same hull, the same markets, the only difference the
// migration. Prints both and the after ÷ before ratios. Run from the repo root.
import { readFileSync, writeFileSync } from 'node:fs'
import { open, log } from '../arrfast/setup.mjs'
const [image, outf, mig] = process.argv.slice(2)
const db = await open(image, [])
const q = async (sql, p) => (await db.query(sql, p)).rows
const sql = readFileSync(new URL('./player.sql', import.meta.url), 'utf8')
const measure = async () => { const t0 = Date.now(); const x = (await q(sql))[0].x; log('player.sql in', Date.now() - t0, 'ms'); return x }
const before = await measure()
await db.exec('begin')
let after, notice = null
try {
  const notices = []; const t0 = Date.now()
  await db.exec(readFileSync(mig, 'utf8').replace(/\r\n/g, '\n'), { onNotice: (n) => notices.push(n.message) })
  log('applied', mig.split(/[\\/]/).pop(), Date.now() - t0, 'ms')
  notice = notices.find((n) => /self-assert/.test(n)) ?? null; if (notice) log('NOTICE', notice.slice(0, 1200))
  after = await measure()
} finally {
  await db.exec('rollback')
}
const ratio = (a, b) => (a == null || b == null || Number(b) === 0 ? null : Math.round((Number(a) / Number(b)) * 1000) / 1000)
const bands = before.bands.map((b) => {
  const a = after.bands.find((x) => x.band === b.band) ?? {}
  return { band: b.band, origins: b.origins, median_sea_days: [b.median_sea_days, a.median_sea_days], median_lap_net: [b.median_lap_net, a.median_lap_net],
    median_pday: [b.median_pday, a.median_pday], ducats_per_real_hour: [b.median_ducats_per_real_hour, a.median_ducats_per_real_hour, ratio(a.median_ducats_per_real_hour, b.median_ducats_per_real_hour)],
    laps_per_real_day: [b.laps_per_real_day, a.laps_per_real_day, ratio(a.laps_per_real_day, b.laps_per_real_day)] }
})
const legs = before.legs.map((l) => { const a = after.legs.find((x) => x.which === l.which) ?? {}; return { ...l, days_after: a.days, real_hours_after: a.real_hours, ratio: ratio(l.days, a.days) } })
const out = { mig, hull: { before: before.hull, after: after.hull, kn_ratio: ratio(after.hull.kn, before.hull.kn), kn_empty_ratio: ratio(after.hull.kn_empty, before.hull.kn_empty) }, from: before.from, legs, bands, notice, raw: { before, after } }
writeFileSync(outf, JSON.stringify(out, null, 1))
log(JSON.stringify({ ...out, raw: undefined, notice: undefined }))
process.exit(0)
