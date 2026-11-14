// gen-0414.mjs: WRITES supabase/migrations/20260818000414_pirates_have_homes_and_grounds.sql from its parts. LOCAL ONLY; re-run, never hand-edit a literal.
//   node scripts/ops/harness/pacific-pirates/gen-0414.mjs <sea.json from gen-sea> <legs.json from gen-legs>
// Parts: head.sql and tail.sql beside this file (typed), the harbours' literals (data/*.json through scripts/lib/world-derive.mjs, gen-sea, gen-legs,
// scripts/build-population.mjs, data/captains.generated.json), the roster (roster.mjs), and 0338's own market arithmetic (its lines for a new
// harbour's rows, lifted verbatim from the applied file so the two cannot drift).
import { readFileSync, writeFileSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { deriveWorld, REPO_ROOT } from '../../../lib/world-derive.mjs'
import { HUBS, roster } from './roster.mjs'
const here = path.dirname(fileURLToPath(import.meta.url))
const [, , SEA, LEGS] = process.argv
const sea = JSON.parse(readFileSync(SEA, 'utf8')); const legs = JSON.parse(readFileSync(LEGS, 'utf8'))
const q = (s) => `'${String(s).replace(/'/g, "''")}'`
const W = deriveWorld()
const codes = HUBS.map((h) => h.code)
const ports = codes.map((c) => W.ports.find((p) => p.code === c))
const pop = JSON.parse(readFileSync(path.join(REPO_ROOT, 'data/port-population.json'), 'utf8')).ports
const lang = JSON.parse(readFileSync(path.join(REPO_ROOT, 'data/captains.generated.json'), 'utf8')).harbours
const PROD = { MWY: ['sea-cucumber', 'shark'], PTC: ['kumara', 'harakeke'], TDC: ['yams', 'millet'], FLO: ['archil-lichen'], DGA: ['zebu-cattle', 'sea-cucumber'] }
const m338 = readFileSync(path.join(REPO_ROOT, 'supabase/migrations/20260818000338_the_brethren.sql'), 'utf8').replaceAll('\r', '').split('\n')
const a = m338.findIndex((l) => l.startsWith('  create temp table sc_h on commit drop as')); const b = m338.findIndex((l) => l.startsWith("  select n.id, k.kind from new_h n cross join (values ('docks')"))
if (a < 0 || b < a) throw new Error('0338 market lines not found')
// 0414 does NOT re-derive the affinity, the max stock, the production or the stock of an EXISTING market row (0338's lines from "the EXISTING rows a new
// maker moves" to that update's row count are left out): a live economy's markets are not reset because five islands were added. The HAUL of a row whose
// nearest maker is now a hub IS re-derived: the world guard holds every row's haul to world.haul_rows(), and it moves no stock.
const mk = m338.slice(a, b + 1)
const cutA = mk.findIndex((l) => l.startsWith('  -- the EXISTING rows a new maker moves'))
const cutB = mk.findIndex((l) => l.trim() === 'get diagnostics v_moved_h = row_count;')
if (cutA < 0 || cutB < cutA) throw new Error('0338 existing-rows lines not found')
const market = [...mk.slice(0, cutA), "  v_moved_h := 0;   -- 0414: no existing row's affinity, max stock, production or stock is touched", ...mk.slice(cutB + 1)].join('\n')
const R = roster()
const lines = {
  PORTS: ports.map((p) => `      (${q(p.code)}, ${q(p.name)}, ${q(p.country)}, ${p.nation_code ? q(p.nation_code) : 'null'}, ${p.lat}, ${p.lon}, ${q(p.sea_code)}, ${q(p.region_code)}, ${q(p.culture)}, ${p.size_tier}, ${p.max_draft}, ${p.yard_tier}, ${p.has_academy}, ${p.dev_industry}, ${p.dev_commerce}, ${p.dev_military}, ${p.crew_pool})`).join(',\n'),
  OFFERS: ports.flatMap((p) => p.specialties.map((g) => `      (${q(p.code)}, ${q(g)})`)).join(',\n'),
  PRODUCTION: codes.flatMap((c) => PROD[c].map((g, i) => `      (${q(c)}, ${q(g)}, ${i + 1})`)).join(',\n'),
  REACHES: sea.hubs.map((h) => `      (${q(h.code)}, ${h.snap.toFixed(2)}, ${h.rlat.toFixed(3)}, ${h.rlon.toFixed(3)}, ${q(JSON.stringify(Object.fromEntries(Object.entries(h.reaches).sort(([x], [y]) => (x < y ? -1 : 1)))))})`).join(',\n'),
  COURSES: sea.hubs.flatMap((h) => h.courses.map((c) => `      (${q(c.from)}, ${q(c.to)}, ${q(c.course)})`)).join(',\n'),
  LANGS: codes.map((c) => `      (${q(c)}, ${q(lang.find((x) => x.port === c).language)})`).join(',\n'),
  POP: codes.map((c) => { const x = pop.find((y) => y.code === c); return `      (${q(c)}, ${x.population}, ${x.year}, ${q(x.confidence)}, ${q(x.note)})` }).join(',\n'),
  LEGROWS: legs.rows.map((r) => `${r[0]} ${r[1]} ${r[2]}`).join('|'),
  HUBROWS: HUBS.map((h) => `    (${q(h.code)}, ${q(h.ground)}, ${q(h.ground_name)}, ${q(h.ground_ko)}, ${h.ships}, ${h.reach})`).join(',\n'),
  ROSTER: R.map((r) => `    (${r.ord}, ${q(r.hub)}, ${r.house}, ${q(r.house_name)}, ${q(r.house_ko)}, ${q(r.fleet_name)}, ${q(r.fleet_ko)})`).join(',\n'),
  HULLS: R.flatMap((r) => r.hulls.map(([c, n]) => `    (${r.ord}, ${q(c)}, ${n})`)).join(',\n'),
  MARKET: market,
  NCOURSES: String(sea.hubs.reduce((s, h) => s + h.courses.length, 0)),
  NFLEETS: String(R.length), NSHIPS: String(R.reduce((s, r) => s + r.hulls.reduce((t, x) => t + x[1], 0), 0)),
}
// head.sql and tail.sql each carry the harness guard under a LOCAL ONLY note (they write, so tests/harness.guard.spec.ts wants them marked local): a migration never carries it.
const GUARD = "do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;"
const part = (f) => { const t = readFileSync(path.join(here, f), 'utf8').replaceAll('\r', '').split('\n'); const i = t.indexOf(GUARD); if (i < 1 || !t[i - 1].startsWith('-- LOCAL ONLY')) throw new Error(`${f}: no guard line under its LOCAL ONLY note`); t.splice(i - 1, 2); return t.join('\n') }
let sql = part('head.sql') + part('tail.sql')
for (const [k, v] of Object.entries(lines)) { if (!sql.includes(`/*${k}*/`)) throw new Error(`no slot ${k}`); sql = sql.replaceAll(`/*${k}*/`, v) }
if (/\/\*[A-Z]+\*\//.test(sql)) throw new Error('a slot is unfilled')
const out = path.join(REPO_ROOT, 'supabase/migrations/20260818000414_pirates_have_homes_and_grounds.sql')
writeFileSync(out, sql)
console.log(`wrote ${out}: ${(sql.length / 1024).toFixed(0)} KiB, ${R.length} fleets, ${lines.NSHIPS} ships, ${lines.NCOURSES} courses, ${legs.rows.length} leg rows`)
