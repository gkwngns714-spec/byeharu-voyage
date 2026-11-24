// gen-0491-sea-lengths.mjs <out.json> — the seed of migration 0491: the length of every stored harbour course (public.sea_courses), BOTH
// ways, by the SAIL's own measure: the sum of voyage.segments_from_course(public.sea_course(a, b)) 'nm' (each piece rounded to 2 decimals),
// exactly what cmd.do_sail / voyage.depart settle a voyage on. Run on the cached chain (the world the migration lands on); it calls the
// live functions, so it is the measure, not a copy of it. About 215 s on PGlite (each call also reads the raster for shelter).
// Writes {courses_md5, pairs: [[a, b, nm], ...]} sorted by a, b ("C" order, a < b as public.sea_courses stores them). Each course is
// measured both ways (sailed a -> b and b -> a); the script refuses if the two differ (0442's law: one figure both ways). 2026-11-24: equal
// for all 32,128, 213 s.
// The courses' digest is the one migration 0491 and proof 194 pin: if public.sea_courses is ever written again, re-run this and cut a
// NEW migration that writes the lengths in the same file, or proof 194 fails.
import { writeFileSync } from 'node:fs'
import { applyChainCached } from './apply-chain.mjs'

const out = process.argv[2]
if (!out) throw new Error('usage: node scripts/db/gen-0491-sea-lengths.mjs <out.json>')
const { db } = await applyChainCached({ log: () => {} })
export const COURSES_MD5_SQL = `select md5(string_agg(p.code || ':' || array_to_string(c.tos, ',') || ':' || array_to_string(c.offs, ',') || ':' || md5(c.pts), '|' order by p.code collate "C")) h
  from public.sea_courses c join public.ports p on p.id = c.port_id`
const md5 = (await db.query(COURSES_MD5_SQL)).rows[0].h
const origins = (await db.query(`select p.id, p.code from public.sea_courses c join public.ports p on p.id = c.port_id order by p.code collate "C"`)).rows
const pairs = []
const t0 = Date.now()
for (const [i, o] of origins.entries()) {
  const r = await db.query(`
    select t.code b,
           (select sum((s ->> 'nm')::numeric) from jsonb_array_elements(voyage.segments_from_course(public.sea_course($1, q.id))) s)::text ab,
           (select sum((s ->> 'nm')::numeric) from jsonb_array_elements(voyage.segments_from_course(public.sea_course(q.id, $1))) s)::text ba
      from public.sea_courses c cross join lateral unnest(c.tos) with ordinality t(code, k)
      join public.ports q on q.code = t.code and q.kind = 'HARBOUR'
     where c.port_id = $1
     order by t.code collate "C"`, [o.id])
  for (const x of r.rows) {
    if (x.ab == null || x.ab !== x.ba) throw new Error(`${o.code}-${x.b}: sailed ${x.ab} one way and ${x.ba} the other`)
    pairs.push([o.code, x.b, x.ab])
  }
  if (i % 20 === 0) console.error(`${i + 1}/${origins.length} ${o.code} ${Math.round((Date.now() - t0) / 1000)} s`)
}
writeFileSync(out, JSON.stringify({ courses_md5: md5, pairs }))
console.error(`pairs ${pairs.length} md5 ${md5} ${Math.round((Date.now() - t0) / 1000)} s`)
process.exit(0)
