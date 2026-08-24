// ═══════════════════════════════════════════════════════════════════════════════════════════════
// GROW THE WORLD — generate a migration that takes the APPLIED world to the world data/*.json
// describes. The successor to build-world-seed.mjs, for a world that has already shipped.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// WHY A DELTA, NOT A RE-SEED. Migration 0003 has been applied to PRODUCTION. It is history: it can
// never be edited (supabase/migrations/README.md §1) and never re-run. On 2026-08-24 it WAS edited
// after applying — production kept the original 70 goods while every fresh rebuild got 243, the
// exact divergence the never-edit rule exists to prevent. So world changes now travel as GROWTH
// migrations: the delta from a BASELINE to today's data, where the baseline is not remembered or
// typed but MEASURED — this script applies the real chain to a scratch PostgreSQL and reads the
// world it actually produces.
//
// USAGE
//   node scripts/build-world-growth.mjs <version14> <snake_case_name>
//   e.g. node scripts/build-world-growth.mjs 20260818000041 ten_islands_and_a_richer_catalogue
//
//   BASELINE  every migration in supabase/migrations/ whose version < <version14>, applied in
//             order to a fresh PGlite (with the same Supabase-shaped preamble the local gate
//             uses). Re-running for the same version therefore excludes the file being rewritten,
//             so the generator converges instead of diffing against its own output.
//   DESIRED   scripts/lib/world-derive.mjs (the ONE derivation) over data/*.json.
//   OUTPUT    supabase/migrations/<version14>_<name>.sql — inserts, targeted updates and deletes,
//             the port_goods re-derivation, and a self-assert that pins the END STATE to the data
//             by set equality, so the migration lands the whole delta or does not land at all.
//
// WHAT IT REFUSES TO EMIT (each is a decision a human must make, not a diff):
//   * deleting a port or a good — production fleets dock at ports and hold goods as cargo
//   * renaming a code (theft net) — a code is a shipped identity; see PORT_CODES in the lib
//   * changing or deleting a sea / region / nation — none has ever changed; the day one does,
//     decide the semantics then, with the world in front of you
//   * CRLF anywhere in the output (the chain is LF-only, a deploy precondition)
//
// WHAT IS DELIBERATELY NOT RECONCILED:
//   * ports.crew_pool — seeded on insert, owned by the RUNNING GAME afterwards (0007 hire drains
//     it); overwriting it would confiscate a live market's labour state
//   * port_goods.stock / drift / season_mod on rows whose affinity did NOT change — runtime state
//     moved by real trade; rows whose affinity DID change get stock := new stock_target, because a
//     retuned geometry with a stale stock displacement prices as a random shortage
//   * SEA_PLACE port rows and their spur legs — 0036 owns them (generated from
//     data/sea-places.json by scripts/build-sea-places.mjs); this generator checks it is not
//     colliding with them and otherwise leaves them alone
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { readFileSync, readdirSync, writeFileSync, existsSync } from 'node:fs'
import { join } from 'node:path'
import { deriveWorld, q, REPO_ROOT } from './lib/world-derive.mjs'

const MIG = join(REPO_ROOT, 'supabase', 'migrations')

const [version, name] = process.argv.slice(2)
if (!/^\d{14}$/.test(version ?? '') || !/^[a-z0-9_]+$/.test(name ?? '')) {
  console.error('usage: node scripts/build-world-growth.mjs <version14> <snake_case_name>')
  process.exit(1)
}
const OUT = join(MIG, `${version}_${name}.sql`)
const shortNo = version.slice(-4)

// ── the baseline: the world the applied chain actually produces ───────────────────────────────
const files = readdirSync(MIG)
  .filter((f) => f.endsWith('.sql') && /^\d{14}_/.test(f) && f.slice(0, 14) < version)
  .sort()
if (files.length === 0) throw new Error('no baseline migrations found below ' + version)

console.log(`baseline: applying ${files.length} migration(s) < ${version} to scratch PostgreSQL…`)
const { PGlite } = await import('@electric-sql/pglite')
const db = await new PGlite()
await db.exec(readFileSync(join(REPO_ROOT, 'scripts', 'db', 'supabase-preamble.sql'), 'utf8'))
for (const f of files) {
  try {
    await db.exec(readFileSync(join(MIG, f), 'utf8'))
  } catch (err) {
    throw new Error(`baseline apply failed in ${f}: ${err.message}`)
  }
}

const hasKind = (await db.query(
  `select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'ports' and column_name = 'kind'`,
)).rows.length > 0
const harbourWhere = hasKind ? `where p.kind = 'HARBOUR'` : ''

const base = {}
base.ports = (await db.query(`
  select p.code, p.name, p.country, n.code as nation_code, p.lat::float8 lat, p.lon::float8 lon,
         s.code as sea_code, r.code as region_code, p.culture, p.size_tier, p.max_draft,
         p.has_yard, p.yard_tier, p.has_academy, p.dev_industry, p.dev_commerce, p.dev_military,
         p.tax_rate::float8 tax_rate
    from public.ports p
    join public.seas s on s.id = p.sea_id
    join public.regions r on r.id = p.region_id
    left join public.nations n on n.id = p.nation_id
    ${harbourWhere} order by p.code`)).rows
base.placeCodes = hasKind
  ? (await db.query(`select code from public.ports where kind = 'SEA_PLACE' order by code`)).rows.map((r) => r.code)
  : []
base.goods = (await db.query(`
  select code, name, base_value::float8 base_value, bulk::float8 bulk,
         perishable_pct_day::float8 perishable_pct_day, category, culture_mask
    from public.goods order by code`)).rows
base.legs = (await db.query(`
  select a.code as f, b.code as t, l.distance_nm::float8 nm, l.hazard_mult::float8 hz, l.notes as note
    from public.legs l
    join public.ports a on a.id = l.from_port_id
    join public.ports b on b.id = l.to_port_id
   ${hasKind ? `where a.kind = 'HARBOUR' and b.kind = 'HARBOUR'` : ''}
   order by a.code, b.code`)).rows
base.spec = (await db.query(`
  select p.code as port, g.code as good from public.port_specialties s
    join public.ports p on p.id = s.port_id join public.goods g on g.id = s.good_id
   order by p.code, g.code`)).rows
base.seas = (await db.query(`select code, name from public.seas order by code`)).rows
base.regions = (await db.query(`select code, name from public.regions order by code`)).rows
base.nations = (await db.query(`select code, name from public.nations order by code`)).rows
base.knobs = Object.fromEntries((await db.query(
  `select key, value::text as v from public.world_config where key like 'affinity_%' order by key`,
)).rows.map((r) => [r.key, r.v]))
await db.close()

// ── the desired world ─────────────────────────────────────────────────────────────────────────
const want = deriveWorld()

// ── refusals ──────────────────────────────────────────────────────────────────────────────────
const wantPortByCode = new Map(want.ports.map((p) => [p.code, p]))
const wantGoodByCode = new Map(want.goods.map((g) => [g.code, g]))
const fail = (m) => { console.error(`REFUSED: ${m}`); process.exit(1) }

for (const b of base.ports) {
  const w = wantPortByCode.get(b.code)
  if (!w) fail(`baseline port ${b.code} (${b.name}) is absent from data/ports.json — deleting a shipped port is not a diff, it is a decision (fleets may be docked there)`)
  if (w.name !== b.name || w.country !== b.country) {
    // identity check: same code must be the same harbour (coordinates are the anchor)
    if (Math.abs(w.lat - b.lat) > 0.5 || Math.abs(w.lon - b.lon) > 0.5) {
      fail(`code ${b.code} would move from ${b.name} (${b.country}) to ${w.name} (${w.country}) — a code is a shipped identity and may never be reassigned`)
    }
  }
}
for (const b of base.goods) {
  if (!wantGoodByCode.has(b.code)) fail(`baseline good ${b.code} is absent from data/goods.json — deleting a shipped good is not a diff (cargo holds it, on delete cascade would take player property)`)
}
for (const w of want.ports) {
  if (base.placeCodes.includes(w.code)) fail(`port ${w.id} wants code ${w.code}, which a SEA_PLACE already holds`)
}
const eqNamed = (bs, ws, what) => {
  const wm = new Map(ws.map((x) => [x.code, x.name]))
  for (const b of bs) {
    if (!wm.has(b.code)) fail(`${what} ${b.code} (${b.name}) is absent from the derived world — removing a shipped ${what} is a decision, not a diff`)
    if (wm.get(b.code) !== b.name) fail(`${what} ${b.code} would be renamed ${b.name} -> ${wm.get(b.code)} — decide that by hand`)
  }
}
eqNamed(base.seas, want.seas, 'sea')
eqNamed(base.regions, want.regions, 'region')
eqNamed(base.nations, want.nations, 'nation')
if (want.seas.length !== base.seas.length || want.regions.length !== base.regions.length
    || want.nations.length !== base.nations.length) {
  fail('a new sea/region/nation appeared — teach this generator to seed it before emitting (nothing has ever added one; decide hazard/piracy and capitals deliberately)')
}

// ── the delta ─────────────────────────────────────────────────────────────────────────────────
const r1 = (n) => Math.round(n * 10) / 10
const basePortByCode = new Map(base.ports.map((p) => [p.code, p]))
const newPorts = want.ports.filter((p) => !basePortByCode.has(p.code))
const PORT_COLS = ['name', 'country', 'nation_code', 'lat', 'lon', 'sea_code', 'region_code', 'culture',
  'size_tier', 'max_draft', 'has_yard', 'yard_tier', 'has_academy', 'dev_industry', 'dev_commerce',
  'dev_military', 'tax_rate']
const changedPorts = want.ports.filter((p) => {
  const b = basePortByCode.get(p.code)
  return b && PORT_COLS.some((c) => String(p[c] ?? null) !== String(b[c] ?? null))
})

const baseGoodByCode = new Map(base.goods.map((g) => [g.code, g]))
const newGoods = want.goods.filter((g) => !baseGoodByCode.has(g.code))
const changedGoods = want.goods.filter((g) => {
  const b = baseGoodByCode.get(g.code)
  if (!b) return false
  const bMask = Array.isArray(b.culture_mask) ? b.culture_mask : String(b.culture_mask ?? '{}').replace(/[{}]/g, '').split(',').filter(Boolean)
  return b.name !== g.name || Math.abs(b.base_value - g.base_value) > 1e-9 || Math.abs(b.bulk - g.bulk) > 1e-9
    || Math.abs(b.perishable_pct_day - g.perishable_pct_day) > 1e-9 || b.category !== g.category
    || JSON.stringify(bMask) !== JSON.stringify(g.culture_mask)
})

const legKey = (l) => `${l.f ?? l.from}|${l.t ?? l.to}`
const baseLegs = new Map(base.legs.map((l) => [legKey(l), l]))
const wantLegs = new Map(want.legs.map((l) => [legKey(l), { ...l, nm: r1(l.nm) }]))
const newLegs = [...wantLegs.values()].filter((l) => !baseLegs.has(legKey(l)))
const removedLegs = [...baseLegs.values()].filter((l) => !wantLegs.has(legKey(l)))
const changedLegs = [...wantLegs.values()].filter((l) => {
  const b = baseLegs.get(legKey(l))
  return b && (Math.abs(b.nm - l.nm) > 0.05 || Math.abs(b.hz - l.hazard) > 1e-9
    || String(b.note ?? '') !== String(l.note ?? ''))
})

const baseSpec = new Set(base.spec.map((s) => `${s.port}|${s.good}`))
const wantSpec = new Set(want.specialtyPairs.map(([p, g]) => `${p}|${g}`))
const specAdd = [...wantSpec].filter((k) => !baseSpec.has(k)).map((k) => k.split('|'))
const specDel = [...baseSpec].filter((k) => !wantSpec.has(k)).map((k) => k.split('|'))

const anything = newPorts.length + changedPorts.length + newGoods.length + changedGoods.length
  + newLegs.length + removedLegs.length + changedLegs.length + specAdd.length + specDel.length
if (anything === 0) {
  console.log('the applied world already equals data/*.json — nothing to emit, no file written')
  process.exit(0)
}

console.log(`delta: +${newPorts.length} ports (~${changedPorts.length} updated) · +${newGoods.length} goods (~${changedGoods.length} updated) · legs +${newLegs.length}/-${removedLegs.length}/~${changedLegs.length} · offers +${specAdd.length}/-${specDel.length}`)

// ── emit ──────────────────────────────────────────────────────────────────────────────────────
const lines = []
const w = (s = '') => lines.push(s)
const knobLits = base.knobs // e.g. { affinity_producer: '0.92', ... } — the chain's CURRENT values

w(`-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- ${shortNo} — ${name.replace(/_/g, ' ').toUpperCase()}
--        The world grows to what data/*.json holds today: ${want.ports.length} harbours, ${want.goods.length} goods,
--        ${want.legs.length} sea legs, ${want.specialtyPairs.length} port offers — landed as a DELTA on whatever world this
--        database holds, and pinned to the data by set equality at the foot of this file.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- GENERATED by scripts/build-world-growth.mjs from data/*.json against the applied chain
-- (baseline: every migration below ${version}, applied to a scratch PostgreSQL and read back).
-- Do not hand-edit: edit the data or the generator and run it again.
--
-- ── WHY A GROWTH MIGRATION EXISTS AT ALL ────────────────────────────────────────────────────────
-- 0003 seeded the world and then SHIPPED. On 2026-08-24 it was edited in place after production
-- had applied it — production kept the original 70 goods and 214 harbours while fresh rebuilds
-- got 243 goods, and the ten island ports existed in no database at all. 0003 is now reverted to
-- the exact bytes production ran (git blob eee9091), and THIS file carries the growth, so every
-- world — production's, a fresh browser's, CI's — arrives at the same place through the same door.
--
-- ── WHAT LANDS HERE (measured against the applied baseline, not remembered) ────────────────────
--   +${String(newPorts.length).padEnd(4)} harbour ports${newPorts.length ? '  (' + newPorts.map((p) => p.code).join(' ') + ')' : ''}
--   ~${String(changedPorts.length).padEnd(4)} harbour rows updated (dev_* follow the roster; Corfu & Heraklion fly Venice)
--   +${String(newGoods.length).padEnd(4)} goods; ~${changedGoods.length} renamed (codes never change)
--   +${newLegs.length}/-${removedLegs.length}/~${changedLegs.length} sea legs (data/sea-routes.json was regenerated with approach legs)
--   +${specAdd.length}/-${specDel.length} port offers, then port_goods re-derived for EVERY (harbour, good) pair
--   the five affinity_* knobs reconciled to the chain's tuned values (0005 was edited in place
--   before the never-edit rule was enforced; a deployed world may still hold the old values)
--
-- ── WHAT THIS DELIBERATELY DOES NOT TOUCH ──────────────────────────────────────────────────────
--   Player rows (houses, fleets, ships, cargo, ledgers): no statement here reads or writes them.
--   ports.crew_pool on existing harbours (the running game owns it; 0007 hire drains it).
--   port_goods.stock / drift / season_mod where affinity is unchanged (real trade moved them).
--   SEA_PLACE rows and their spur legs (0036 owns them; asserted untouched below).
--
-- Depends on: 0002 (tables), 0003 (the seeded world), 0005 (port_goods, world.affinity_at, knobs),
--             0036 (ports.kind).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 0. Pre-image: the world this migration found (feeds the DELTA receipts below) ──────────────
create temporary table pre_${shortNo} as
  select (select count(*) from public.ports    where kind = 'HARBOUR') as harbours,
         (select count(*) from public.goods)                           as goods,
         (select count(*) from public.legs l
            join public.ports a on a.id = l.from_port_id
            join public.ports b on b.id = l.to_port_id
           where a.kind = 'HARBOUR' and b.kind = 'HARBOUR')            as harbour_legs,
         (select count(*) from public.legs l
            join public.ports a on a.id = l.from_port_id
            join public.ports b on b.id = l.to_port_id
           where a.kind = 'SEA_PLACE' or b.kind = 'SEA_PLACE')         as spur_legs,
         (select count(*) from public.port_specialties)                as offers,
         (select count(*) from public.port_goods)                      as market_rows,
         (select value from public.world_config where key = 'affinity_producer') as old_producer;
`)

// 1. knobs
w(`-- ── 1. The affinity knobs, reconciled to the chain's current tuned values ─────────────────────
--       0005 seeds these on a fresh world; a deployed world that applied an earlier 0005 keeps its
--       old values because a seed does not re-run. The grown catalogue was TUNED under the values
--       below (0005's measurement table: the old setting read 16.5% through proof 05 on 243 goods,
--       past the band; these bring it back). Idempotent: a world already holding them is untouched.`)
for (const [key, v] of Object.entries(knobLits)) {
  w(`update public.world_config set value = '${v}'::jsonb where key = ${q(key)} and value <> '${v}'::jsonb;`)
}
w('')

// 2. goods
if (newGoods.length) {
  w(`-- ── 2. The ${newGoods.length} new goods ───────────────────────────────────────────────────────────────────`)
  w('insert into public.goods (code, name, base_value, bulk, perishable_pct_day, category, culture_mask) values')
  w(newGoods.map((g) =>
    `  (${q(g.code)}, ${q(g.name)}, ${g.base_value.toFixed(2)}, ${g.bulk.toFixed(3)}, ${g.perishable_pct_day.toFixed(3)}, ${q(g.category)}, '{${g.culture_mask.join(',')}}')`,
  ).join(',\n') + '\non conflict (code) do nothing;\n')
}
if (changedGoods.length) {
  w(`-- ── 2b. ${changedGoods.length} goods whose prose changed (name/category/price band); codes never move ──────`)
  w(`update public.goods g
   set name = v.name, base_value = v.base_value, bulk = v.bulk,
       perishable_pct_day = v.perish, category = v.category, culture_mask = v.mask::text[]
  from (values`)
  w(changedGoods.map((g) =>
    `  (${q(g.code)}, ${q(g.name)}, ${g.base_value.toFixed(2)}::numeric, ${g.bulk.toFixed(3)}::numeric, ${g.perishable_pct_day.toFixed(3)}::numeric, ${q(g.category)}, ${q('{' + g.culture_mask.join(',') + '}')})`,
  ).join(',\n'))
  w(`  ) as v(code, name, base_value, bulk, perish, category, mask)
 where g.code = v.code
   and (g.name, g.base_value, g.bulk, g.perishable_pct_day, g.category, g.culture_mask)
       is distinct from (v.name, v.base_value, v.bulk, v.perish, v.category, v.mask::text[]);
`)
}

// 3. ports
const portRow = (p) =>
  `    (${q(p.code)}, ${q(p.name)}, ${q(p.country)}, ${q(p.nation_code)}, ${p.lat}, ${p.lon}, ${q(p.sea_code)}, ${q(p.region_code)}, ${q(p.culture)}, ${p.size_tier}, ${p.max_draft}, ${p.yard_tier}, ${p.has_academy}, ${p.dev_industry}, ${p.dev_commerce}, ${p.dev_military}, ${p.crew_pool})`
if (newPorts.length) {
  w(`-- ── 3. The ${newPorts.length} new harbours ────────────────────────────────────────────────────────────────`)
  w(`insert into public.ports (
  code, name, country, nation_id, lat, lon, sea_id, region_id, culture,
  size_tier, max_draft, has_yard, yard_tier, has_academy,
  dev_industry, dev_commerce, dev_military, tax_rate, crew_pool
)
select v.code, v.name, v.country, n.id, v.lat, v.lon, s.id, r.id, v.culture,
       v.size_tier, v.max_draft, v.yard_tier > 0, v.yard_tier, v.academy,
       v.dev_i, v.dev_c, v.dev_m, 0.03, v.crew_pool
  from (values`)
  w(newPorts.map(portRow).join(',\n'))
  w(`  ) as v(code, name, country, nation_code, lat, lon, sea_code, region_code, culture,
         size_tier, max_draft, yard_tier, academy, dev_i, dev_c, dev_m, crew_pool)
  join public.seas    s on s.code = v.sea_code
  join public.regions r on r.code = v.region_code
  left join public.nations n on n.code = v.nation_code
on conflict (code) do nothing;
`)
}
if (changedPorts.length) {
  w(`-- ── 3b. ${changedPorts.length} existing harbours whose derived columns moved (dev_* follow the roster).
--        crew_pool is NOT here: the running game owns it. ───────────────────────────────────────`)
  w(`update public.ports p
   set name = v.name, country = v.country, nation_id = n.id, lat = v.lat, lon = v.lon,
       sea_id = s.id, region_id = r.id, culture = v.culture, size_tier = v.size_tier,
       max_draft = v.max_draft, has_yard = v.yard_tier > 0, yard_tier = v.yard_tier,
       has_academy = v.academy, dev_industry = v.dev_i, dev_commerce = v.dev_c,
       dev_military = v.dev_m
  from (values`)
  w(changedPorts.map(portRow).join(',\n'))
  w(`  ) as v(code, name, country, nation_code, lat, lon, sea_code, region_code, culture,
         size_tier, max_draft, yard_tier, academy, dev_i, dev_c, dev_m, crew_pool)
  join public.seas    s on s.code = v.sea_code
  join public.regions r on r.code = v.region_code
  left join public.nations n on n.code = v.nation_code
 where p.code = v.code
   and (p.name, p.country, p.nation_id, p.lat, p.lon, p.sea_id, p.region_id, p.culture,
        p.size_tier, p.max_draft, p.yard_tier, p.has_academy, p.dev_industry, p.dev_commerce,
        p.dev_military)
       is distinct from
       (v.name, v.country, n.id, v.lat, v.lon, s.id, r.id, v.culture,
        v.size_tier, v.max_draft, v.yard_tier, v.academy, v.dev_i, v.dev_c, v.dev_m);
`)
}

// 4. offers
if (specDel.length) {
  w(`-- ── 4. ${specDel.length} offers withdrawn (the roster rebalance took them off the quay) ──────────────────`)
  w(`delete from public.port_specialties ps
 using public.ports p, public.goods g
 where ps.port_id = p.id and ps.good_id = g.id
   and (p.code, g.code) in (values`)
  w(specDel.map(([p, g]) => `  (${q(p)}, ${q(g)})`).join(',\n'))
  w(');\n')
}
if (specAdd.length) {
  w(`-- ── 4b. ${specAdd.length} offers added ──────────────────────────────────────────────────────────────────`)
  w('insert into public.port_specialties (port_id, good_id)')
  w('select p.id, g.id from (values')
  w(specAdd.map(([p, g]) => `  (${q(p)}, ${q(g)})`).join(',\n'))
  w(`) as v(port_code, good_code)
  join public.ports p on p.code = v.port_code
  join public.goods g on g.code = v.good_code
on conflict do nothing;
`)
}

// 5. legs
if (changedLegs.length) {
  w(`-- ── 5. ${changedLegs.length} legs re-measured (sea-routes regenerated: approach spurs refine distances).
--        A SAILING voyage is untouched: its path/total_nm/speed froze at departure (0006). ──────`)
  w(`update public.legs l
   set distance_nm = v.nm, hazard_mult = v.hz, notes = v.note
  from (values`)
  w(changedLegs.map((l) => `  (${q(l.from)}, ${q(l.to)}, ${l.nm.toFixed(1)}::numeric, ${l.hazard.toFixed(3)}::numeric, ${q(l.note)})`).join(',\n'))
  w(`  ) as v(f, t, nm, hz, note)
  join public.ports a on a.code = v.f
  join public.ports b on b.code = v.t
 where l.from_port_id = a.id and l.to_port_id = b.id
   and (l.distance_nm, l.hazard_mult, coalesce(l.notes, '')) is distinct from (v.nm, v.hz, coalesce(v.note, ''));
`)
}
if (removedLegs.length) {
  w(`-- ── 5b. ${removedLegs.length} legs withdrawn (no schema references legs; a sailing voyage carries its own
--         frozen copy of every leg it is on, so nothing in flight can dangle). ──────────────────`)
  w(`delete from public.legs l
 using public.ports a, public.ports b
 where l.from_port_id = a.id and l.to_port_id = b.id
   and (a.code, b.code) in (values`)
  w(removedLegs.map((l) => `  (${q(l.f)}, ${q(l.t)})`).join(',\n'))
  w(');\n')
}
if (newLegs.length) {
  w(`-- ── 5c. ${newLegs.length} new legs (canonical from.code < to.code, the 0002 rule) ───────────────────────`)
  w(`insert into public.legs (from_port_id, to_port_id, distance_nm, hazard_mult, notes)
select pf.id, pt.id, v.nm, v.hz, v.note
  from (values`)
  w(newLegs.map((l) => `    (${q(l.from)}, ${q(l.to)}, ${l.nm.toFixed(1)}, ${l.hazard.toFixed(3)}, ${q(l.note)})`).join(',\n'))
  w(`  ) as v(f, t, nm, hz, note)
  join public.ports pf on pf.code = v.f
  join public.ports pt on pt.code = v.t
on conflict do nothing;
`)
}

// 6. port_goods re-derivation
w(`-- ── 6. THE MARKET FOLLOWS THE WORLD: port_goods re-derived for every (harbour, good) pair ─────
--
-- The same arithmetic as 0005's seed — the one formula world.affinity_at(), the same knobs-once +
-- distance-matrix shape — extended to the grown world. Three kinds of row come out of it:
--   * a MISSING pair (new good anywhere, any good at a new harbour): INSERTED, stock = target
--   * an EXISTING pair whose affinity moved (a source appeared/vanished nearby, or the knobs
--     changed): affinity/stock_target/production_rate re-derived, stock := the new target — a
--     retuned geometry with a stale stock displacement would price as a random shortage
--   * an EXISTING pair whose affinity is unchanged: NOT TOUCHED (stock/drift belong to the game)
with knob as (
  select public.wc_num('affinity_producer') as producer,
         public.wc_num('affinity_home')     as home,
         public.wc_num('affinity_span')     as span,
         public.wc_num('affinity_reach_nm') as reach_nm,
         public.wc_num('affinity_curve')    as curve
),
source_distance as (
  select p.id as port_id, src.id as src_id,
         voyage.gc_distance_nm(p.lat, p.lon, src.lat, src.lon) as nm
    from public.ports p
    cross join (select distinct port_id from public.port_specialties) s
    join public.ports src on src.id = s.port_id
   where p.kind = 'HARBOUR'
),
nearest as (
  select d.port_id, ps.good_id, min(d.nm) as nm
    from source_distance d
    join public.port_specialties ps on ps.port_id = d.src_id
   group by d.port_id, ps.good_id
)
insert into public.port_goods (port_id, good_id, affinity, stock, stock_target, production_rate)
select p.id,
       g.id,
       aff.affinity,
       greatest(60, round(200 * p.size_tier * (1.60 - aff.affinity))),
       greatest(60, round(200 * p.size_tier * (1.60 - aff.affinity))),
       case when aff.affinity < 0.80
            then round(greatest(60, 200 * p.size_tier * (1.60 - aff.affinity)) * 0.05, 2)
            else 0 end
  from public.ports p
  cross join public.goods g
  cross join knob k
  left join nearest n on n.port_id = p.id and n.good_id = g.id
  cross join lateral (
    select world.affinity_at(
             exists (select 1 from public.port_specialties s
                      where s.port_id = p.id and s.good_id = g.id),
             n.nm, k.producer, k.home, k.span, k.reach_nm, k.curve) as affinity
  ) aff
 where p.kind = 'HARBOUR'
on conflict (port_id, good_id) do update
   set affinity        = excluded.affinity,
       stock_target    = excluded.stock_target,
       production_rate = excluded.production_rate,
       stock           = excluded.stock,
       updated_at      = now()
 where port_goods.affinity is distinct from excluded.affinity;
`)

// 7. self-assert
const wantPortCodes = want.ports.map((p) => p.code)
const wantGoodCodes = want.goods.map((g) => g.code)
// a probe offer that does NOT exist: Lisboa plus the first good Lisboa does not offer
const lisSpecs = new Set(want.ports.find((p) => p.code === 'LIS').specialties)
const probeGood = wantGoodCodes.find((g) => !lisSpecs.has(g))

w(`-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
-- The migration's whole claim: after it, THE DATABASE'S WORLD EQUALS data/*.json — by set
-- equality over identities AND values, never by counts alone. The literals below are generated
-- from the data; the deltas are measured against the pre-image; the derivation rules (dev_*, the
-- offer band, affinity) are asserted as RULES over the live tables, so they hold for every row
-- including ones this migration never touched. The roster check carries its own positive control.
create temporary table want_ports_${shortNo} (
  code text, name text, country text, nation_code text, lat numeric, lon numeric,
  sea_code text, region_code text, culture text, size_tier int, max_draft int,
  yard_tier int, academy boolean, dev_i int, dev_c int, dev_m int
);
insert into want_ports_${shortNo} values`)
w(want.ports.map((p) =>
  `  (${q(p.code)}, ${q(p.name)}, ${q(p.country)}, ${q(p.nation_code)}, ${p.lat}, ${p.lon}, ${q(p.sea_code)}, ${q(p.region_code)}, ${q(p.culture)}, ${p.size_tier}, ${p.max_draft}, ${p.yard_tier}, ${p.has_academy}, ${p.dev_industry}, ${p.dev_commerce}, ${p.dev_military})`,
).join(',\n') + ';')
w(`
create temporary table want_goods_${shortNo} (
  code text, name text, base_value numeric, bulk numeric, perish numeric, category text, mask text[]
);
insert into want_goods_${shortNo} values`)
w(want.goods.map((g) =>
  `  (${q(g.code)}, ${q(g.name)}, ${g.base_value.toFixed(2)}, ${g.bulk.toFixed(3)}, ${g.perishable_pct_day.toFixed(3)}, ${q(g.category)}, ${q('{' + g.culture_mask.join(',') + '}')})`,
).join(',\n') + ';')
w(`
create temporary table want_offers_${shortNo} (port_code text, good_code text);
insert into want_offers_${shortNo} values`)
w(want.specialtyPairs.map(([p, g]) => `  (${q(p)}, ${q(g)})`).join(',\n') + ';')
w(`
create temporary table want_legs_${shortNo} (f text, t text, nm numeric, hz numeric, note text);
insert into want_legs_${shortNo} values`)
w([...wantLegs.values()].map((l) => `  (${q(l.from)}, ${q(l.to)}, ${l.nm.toFixed(1)}, ${l.hazard.toFixed(3)}, ${q(l.note)})`).join(',\n') + ';')

w(`
do $$
declare
  pre         record;
  v_n         int;
  v_m         int;
  v_extra     int;
  v_list      text;
  v_harbours  int;
  v_goods     int;
  v_reachable int;
  v_ports_all int;
  v_probe_extra int;
begin
  select * into pre from pre_${shortNo};

  ---------------------------------------------------------------------------------------------
  -- (a) DELTAS against the world this migration found. Both legal baselines (production after
  --     the original 0003, and a fresh rebuild of the reverted chain) present the same world
  --     here, so the deltas are exact.
  ---------------------------------------------------------------------------------------------
  select count(*) into v_harbours from public.ports where kind = 'HARBOUR';
  select count(*) into v_goods    from public.goods;
  if v_harbours - pre.harbours <> ${newPorts.length} or v_goods - pre.goods <> ${newGoods.length} then
    raise exception '${shortNo} self-assert FAIL: expected +${newPorts.length} harbours and +${newGoods.length} goods over the pre-image; got +% harbours (% now) and +% goods (% now)',
      v_harbours - pre.harbours, v_harbours, v_goods - pre.goods, v_goods;
  end if;
  select count(*) into v_n from public.legs l
    join public.ports a on a.id = l.from_port_id
    join public.ports b on b.id = l.to_port_id
   where a.kind = 'HARBOUR' and b.kind = 'HARBOUR';
  if v_n - pre.harbour_legs <> ${newLegs.length - removedLegs.length} then
    raise exception '${shortNo} self-assert FAIL: harbour legs moved by % (expected +${newLegs.length}-${removedLegs.length} = ${newLegs.length - removedLegs.length}): % now against % before',
      v_n - pre.harbour_legs, v_n, pre.harbour_legs;
  end if;
  select count(*) into v_n from public.port_specialties;
  if v_n - pre.offers <> ${specAdd.length - specDel.length} then
    raise exception '${shortNo} self-assert FAIL: offers moved by % (expected +${specAdd.length}-${specDel.length} = ${specAdd.length - specDel.length})', v_n - pre.offers;
  end if;

  ---------------------------------------------------------------------------------------------
  -- (b) EVERY HARBOUR EQUALS ITS DATA ROW — identity AND every derived column, both directions.
  ---------------------------------------------------------------------------------------------
  select count(*) into v_n from want_ports_${shortNo} wp
   where not exists (select 1 from public.ports p where p.code = wp.code and p.kind = 'HARBOUR');
  select count(*) into v_extra from public.ports p
   where p.kind = 'HARBOUR' and not exists (select 1 from want_ports_${shortNo} wp where wp.code = p.code);
  if v_n <> 0 or v_extra <> 0 then
    select string_agg(x.code, ', ') into v_list from (
      select wp.code from want_ports_${shortNo} wp
       where not exists (select 1 from public.ports p where p.code = wp.code and p.kind = 'HARBOUR')
      union all
      select p.code from public.ports p
       where p.kind = 'HARBOUR' and not exists (select 1 from want_ports_${shortNo} wp where wp.code = p.code)
    ) x;
    raise exception '${shortNo} self-assert FAIL: the harbour set does not equal the data (% missing, % extra): %', v_n, v_extra, v_list;
  end if;
  select count(*) into v_n
    from want_ports_${shortNo} wp
    join public.ports p on p.code = wp.code
    join public.seas s on s.id = p.sea_id
    join public.regions r on r.id = p.region_id
    left join public.nations n on n.id = p.nation_id
   where (p.name, p.country, coalesce(n.code, ''), p.lat, p.lon, s.code, r.code, p.culture,
          p.size_tier, p.max_draft, p.yard_tier, p.has_academy, p.dev_industry, p.dev_commerce,
          p.dev_military)
         is distinct from
         (wp.name, wp.country, coalesce(wp.nation_code, ''), wp.lat, wp.lon, wp.sea_code,
          wp.region_code, wp.culture, wp.size_tier, wp.max_draft, wp.yard_tier, wp.academy,
          wp.dev_i, wp.dev_c, wp.dev_m);
  if v_n <> 0 then
    select string_agg(wp.code, ', ') into v_list
      from want_ports_${shortNo} wp
      join public.ports p on p.code = wp.code
      join public.seas s on s.id = p.sea_id
      join public.regions r on r.id = p.region_id
      left join public.nations n on n.id = p.nation_id
     where (p.name, p.country, coalesce(n.code, ''), p.lat, p.lon, s.code, r.code, p.culture,
            p.size_tier, p.max_draft, p.yard_tier, p.has_academy, p.dev_industry, p.dev_commerce,
            p.dev_military)
           is distinct from
           (wp.name, wp.country, coalesce(wp.nation_code, ''), wp.lat, wp.lon, wp.sea_code,
            wp.region_code, wp.culture, wp.size_tier, wp.max_draft, wp.yard_tier, wp.academy,
            wp.dev_i, wp.dev_c, wp.dev_m);
    raise exception '${shortNo} self-assert FAIL: % harbour row(s) disagree with the data column-for-column: %', v_n, v_list;
  end if;

  ---------------------------------------------------------------------------------------------
  -- (c) EVERY GOOD EQUALS ITS DATA ROW, both directions, every column.
  ---------------------------------------------------------------------------------------------
  select count(*) into v_n from want_goods_${shortNo} wg
   where not exists (select 1 from public.goods g where g.code = wg.code);
  select count(*) into v_extra from public.goods g
   where not exists (select 1 from want_goods_${shortNo} wg where wg.code = g.code);
  if v_n <> 0 or v_extra <> 0 then
    raise exception '${shortNo} self-assert FAIL: the goods set does not equal the data (% missing, % extra)', v_n, v_extra;
  end if;
  select count(*) into v_n
    from want_goods_${shortNo} wg
    join public.goods g on g.code = wg.code
   where (g.name, g.base_value, g.bulk, g.perishable_pct_day, g.category, g.culture_mask)
         is distinct from (wg.name, wg.base_value, wg.bulk, wg.perish, wg.category, wg.mask);
  if v_n <> 0 then
    select string_agg(wg.code, ', ') into v_list from want_goods_${shortNo} wg
      join public.goods g on g.code = wg.code
     where (g.name, g.base_value, g.bulk, g.perishable_pct_day, g.category, g.culture_mask)
           is distinct from (wg.name, wg.base_value, wg.bulk, wg.perish, wg.category, wg.mask);
    raise exception '${shortNo} self-assert FAIL: % good row(s) disagree with the data column-for-column: %', v_n, v_list;
  end if;

  ---------------------------------------------------------------------------------------------
  -- (d) EVERY PORT'S OFFERS EQUAL ITS goods ARRAY, AS A SET — with a POSITIVE CONTROL first:
  --     a deliberately planted bogus offer must be SEEN by the very query that certifies zero,
  --     then is removed. A certifying query that cannot see a planted wrong row certifies nothing.
  ---------------------------------------------------------------------------------------------
  insert into public.port_specialties (port_id, good_id)
  select p.id, g.id from public.ports p, public.goods g
   where p.code = 'LIS' and g.code = ${q(probeGood)};
  select count(*) into v_probe_extra from public.port_specialties ps
    join public.ports p on p.id = ps.port_id
    join public.goods g on g.id = ps.good_id
   where not exists (select 1 from want_offers_${shortNo} wo
                      where wo.port_code = p.code and wo.good_code = g.code);
  if v_probe_extra <> 1 then
    raise exception '${shortNo} self-assert FAIL (positive control): planted 1 bogus offer (LIS, ${probeGood}) and the extra-offers query found % — the certifying query is blind', v_probe_extra;
  end if;
  delete from public.port_specialties ps
   using public.ports p, public.goods g
   where ps.port_id = p.id and ps.good_id = g.id and p.code = 'LIS' and g.code = ${q(probeGood)};

  select count(*) into v_n from want_offers_${shortNo} wo
   where not exists (select 1 from public.port_specialties ps
                       join public.ports p on p.id = ps.port_id
                       join public.goods g on g.id = ps.good_id
                      where p.code = wo.port_code and g.code = wo.good_code);
  select count(*) into v_extra from public.port_specialties ps
    join public.ports p on p.id = ps.port_id
    join public.goods g on g.id = ps.good_id
   where not exists (select 1 from want_offers_${shortNo} wo
                      where wo.port_code = p.code and wo.good_code = g.code);
  if v_n <> 0 or v_extra <> 0 then
    select string_agg(x.pair, ', ') into v_list from (
      select wo.port_code || '·' || wo.good_code as pair from want_offers_${shortNo} wo
       where not exists (select 1 from public.port_specialties ps
                           join public.ports p on p.id = ps.port_id
                           join public.goods g on g.id = ps.good_id
                          where p.code = wo.port_code and g.code = wo.good_code)
      union all
      select p.code || '·' || g.code from public.port_specialties ps
        join public.ports p on p.id = ps.port_id
        join public.goods g on g.id = ps.good_id
       where not exists (select 1 from want_offers_${shortNo} wo
                          where wo.port_code = p.code and wo.good_code = g.code)
      limit 20
    ) x;
    raise exception '${shortNo} self-assert FAIL: the offer set does not equal the rosters (% missing, % extra): %', v_n, v_extra, v_list;
  end if;

  ---------------------------------------------------------------------------------------------
  -- (e) EVERY HARBOUR LEG EQUALS ITS DATA ROW (pair, distance, hazard, note), both directions —
  --     and the SEA_PLACE spur legs are exactly as this migration found them (0036 owns them).
  ---------------------------------------------------------------------------------------------
  select count(*) into v_n from want_legs_${shortNo} wl
   where not exists (select 1 from public.legs l
                       join public.ports a on a.id = l.from_port_id
                       join public.ports b on b.id = l.to_port_id
                      where a.code = wl.f and b.code = wl.t
                        and l.distance_nm = wl.nm and l.hazard_mult = wl.hz
                        and coalesce(l.notes, '') = coalesce(wl.note, ''));
  select count(*) into v_extra from public.legs l
    join public.ports a on a.id = l.from_port_id
    join public.ports b on b.id = l.to_port_id
   where a.kind = 'HARBOUR' and b.kind = 'HARBOUR'
     and not exists (select 1 from want_legs_${shortNo} wl
                      where wl.f = a.code and wl.t = b.code
                        and l.distance_nm = wl.nm and l.hazard_mult = wl.hz
                        and coalesce(l.notes, '') = coalesce(wl.note, ''));
  if v_n <> 0 or v_extra <> 0 then
    select string_agg(x.pair, ', ') into v_list from (
      select wl.f || '-' || wl.t as pair from want_legs_${shortNo} wl
       where not exists (select 1 from public.legs l
                           join public.ports a on a.id = l.from_port_id
                           join public.ports b on b.id = l.to_port_id
                          where a.code = wl.f and b.code = wl.t
                            and l.distance_nm = wl.nm and l.hazard_mult = wl.hz
                            and coalesce(l.notes, '') = coalesce(wl.note, ''))
      limit 12
    ) x;
    raise exception '${shortNo} self-assert FAIL: the harbour leg set does not equal the data (% missing/wrong, % extra), e.g. %', v_n, v_extra, v_list;
  end if;
  select count(*) into v_n from public.legs l
    join public.ports a on a.id = l.from_port_id
    join public.ports b on b.id = l.to_port_id
   where a.kind = 'SEA_PLACE' or b.kind = 'SEA_PLACE';
  if v_n <> pre.spur_legs then
    raise exception '${shortNo} self-assert FAIL: this migration changed the SEA_PLACE spur legs (% now, % before) — those belong to 0036', v_n, pre.spur_legs;
  end if;

  ---------------------------------------------------------------------------------------------
  -- (f) THE DERIVATION RULES HOLD ON EVERY ROW — the rule, not the seed, so rows this migration
  --     never touched are held to the same law. dev_* restate the roster; the offer band is the
  --     owner's 4-9 rule keyed to size (tier-1 up to 9, tier-2 up to 7, tier-3 exactly 4-5).
  ---------------------------------------------------------------------------------------------
  select count(*) into v_n
    from public.ports p
    join lateral (select count(*) as c from public.port_specialties s where s.port_id = p.id) sc on true
    join lateral (select count(*) as c from public.port_specialties s
                    join public.goods g on g.id = s.good_id
                   where s.port_id = p.id and g.category in ('metal', 'textile', 'naval-stores')) ic on true
   where p.kind = 'HARBOUR'
     and (p.dev_commerce <> greatest(0, least(20, round(p.size_tier * 2.4 + sc.c)))
       or p.dev_industry <> greatest(0, least(20, round(p.size_tier * 2.0 + ic.c * 1.5)))
       or p.dev_military <> greatest(0, least(20, round(p.size_tier * 1.8 + case when p.yard_tier > 0 then 2 else 0 end))));
  if v_n <> 0 then
    raise exception '${shortNo} self-assert FAIL: % harbour(s) have dev_* columns that do not restate their roster and size', v_n;
  end if;
  select count(*) into v_n
    from public.ports p
    join lateral (select count(*) as c from public.port_specialties s where s.port_id = p.id) sc on true
   where p.kind = 'HARBOUR'
     and (sc.c < 4 or sc.c > 9
       or (p.size_tier = 5 and sc.c > 9)
       or (p.size_tier = 3 and sc.c > 7)
       or (p.size_tier = 2 and sc.c not between 4 and 5));
  if v_n <> 0 then
    select string_agg(p.code, ', ') into v_list from public.ports p
      join lateral (select count(*) as c from public.port_specialties s where s.port_id = p.id) sc on true
     where p.kind = 'HARBOUR'
       and (sc.c < 4 or sc.c > 9 or (p.size_tier = 5 and sc.c > 9)
         or (p.size_tier = 3 and sc.c > 7) or (p.size_tier = 2 and sc.c not between 4 and 5));
    raise exception '${shortNo} self-assert FAIL: % harbour(s) break the 4-9 offers-by-size rule: %', v_n, v_list;
  end if;

  ---------------------------------------------------------------------------------------------
  -- (g) THE WORLD IS STILL ONE PIECE — every port (harbours, islands, sea places) reachable
  --     from Lisboa — and no leg anywhere is shorter than its great circle.
  ---------------------------------------------------------------------------------------------
  select count(*) into v_ports_all from public.ports;
  with recursive reached(id) as (
      select id from public.ports where code = 'LIS'
    union
      select case when l.from_port_id = r.id then l.to_port_id else l.from_port_id end
        from reached r
        join public.legs l on l.from_port_id = r.id or l.to_port_id = r.id
  )
  select count(*) into v_reachable from reached;
  if v_reachable <> v_ports_all then
    raise exception '${shortNo} self-assert FAIL: only % of % ports are reachable from Lisboa after the growth', v_reachable, v_ports_all;
  end if;
  select count(*) into v_n from public.legs l
    join public.ports a on a.id = l.from_port_id
    join public.ports b on b.id = l.to_port_id
   where l.distance_nm < voyage.gc_distance_nm(a.lat, a.lon, b.lat, b.lon);
  if v_n <> 0 then
    raise exception '${shortNo} self-assert FAIL: % leg(s) are shorter than the great circle between their ports', v_n;
  end if;

  ---------------------------------------------------------------------------------------------
  -- (h) THE MARKET COVERS THE WORLD AND RESTATES THE FORMULA. One row per (harbour, good);
  --     every affinity equals the one formula recomputed from today's specialties and knobs;
  --     stock_target and production_rate restate 0005's seed arithmetic on every row.
  ---------------------------------------------------------------------------------------------
  select count(*) into v_n from public.port_goods;
  if v_n <> v_harbours * v_goods then
    raise exception '${shortNo} self-assert FAIL: % port_goods rows for % harbours × % goods (expected %)',
      v_n, v_harbours, v_goods, v_harbours * v_goods;
  end if;
  with knob as (
    select public.wc_num('affinity_producer') as producer,
           public.wc_num('affinity_home')     as home,
           public.wc_num('affinity_span')     as span,
           public.wc_num('affinity_reach_nm') as reach_nm,
           public.wc_num('affinity_curve')    as curve
  ),
  source_distance as (
    select p.id as port_id, src.id as src_id,
           voyage.gc_distance_nm(p.lat, p.lon, src.lat, src.lon) as nm
      from public.ports p
      cross join (select distinct port_id from public.port_specialties) s
      join public.ports src on src.id = s.port_id
     where p.kind = 'HARBOUR'
  ),
  nearest as (
    select d.port_id, ps.good_id, min(d.nm) as nm
      from source_distance d
      join public.port_specialties ps on ps.port_id = d.src_id
     group by d.port_id, ps.good_id
  )
  select count(*) into v_n
    from public.port_goods pg
    join public.ports p on p.id = pg.port_id
    left join nearest n on n.port_id = pg.port_id and n.good_id = pg.good_id
    cross join knob k
   where pg.affinity is distinct from world.affinity_at(
           exists (select 1 from public.port_specialties s
                    where s.port_id = pg.port_id and s.good_id = pg.good_id),
           n.nm, k.producer, k.home, k.span, k.reach_nm, k.curve);
  if v_n <> 0 then
    raise exception '${shortNo} self-assert FAIL: % port_goods row(s) hold an affinity the formula does not derive from today''s world', v_n;
  end if;
  select count(*) into v_n
    from public.port_goods pg
    join public.ports p on p.id = pg.port_id
   where pg.stock_target is distinct from greatest(60, round(200 * p.size_tier * (1.60 - pg.affinity)))
      or pg.production_rate is distinct from
         case when pg.affinity < 0.80
              then round(greatest(60, 200 * p.size_tier * (1.60 - pg.affinity)) * 0.05, 2)
              else 0 end;
  if v_n <> 0 then
    raise exception '${shortNo} self-assert FAIL: % port_goods row(s) break 0005''s stock_target/production_rate arithmetic', v_n;
  end if;

  ---------------------------------------------------------------------------------------------
  -- (i) The knobs hold the tuned values, and the lockdown of 0001/0018/0023 still stands.
  ---------------------------------------------------------------------------------------------
  if ${Object.entries(knobLits).map(([k, v]) => `(select value from public.world_config where key = ${q(k)}) <> '${v}'::jsonb`).join('\n     or ')} then
    raise exception '${shortNo} self-assert FAIL: the affinity knobs do not hold the tuned values (${Object.entries(knobLits).map(([k, v]) => `${k.replace('affinity_', '')}=${v}`).join(' ')})';
  end if;
  select count(*) into v_n from public.client_write_grants();
  select count(*) into v_m from public.client_executable_writers();
  select count(*) into v_extra from public.caller_evaluated_functions();
  if v_n <> 0 or v_m <> 0 or v_extra <> 0 then
    raise exception '${shortNo} self-assert FAIL: the growth minted % client write grant(s), % client-executable writer(s), % read-wall gap(s)', v_n, v_m, v_extra;
  end if;

  raise notice '${shortNo} self-assert ok: THE WORLD EQUALS THE DATA — % harbours (+% over the world this file found) and % goods (+%) with every column equal to data/*.json; the offer set equals every roster as a set (positive control: a planted bogus offer WAS seen, then removed); % harbour legs equal the data pair-for-pair with distances and hazards, the % sea-place spur legs untouched; dev_* restate every roster, all % harbours sit in the owner''s 4-9 offers-by-size band; all % ports reachable from Lisboa and no leg beats its great circle; % market rows = harbours × goods (% more than the % this file found), every affinity re-derivable from the one formula, 0005''s stock arithmetic holding on every row; knobs at ${Object.entries(knobLits).map(([k, v]) => `${k.replace('affinity_', '')} ${v}`).join(', ')}; 0 client write grants, 0 client-executable writers, 0 read-wall gaps',
    v_harbours, v_harbours - pre.harbours, v_goods, v_goods - pre.goods,
    (select count(*) from want_legs_${shortNo}), pre.spur_legs,
    v_harbours, v_ports_all,
    (select count(*) from public.port_goods),
    (select count(*) from public.port_goods) - pre.market_rows, pre.market_rows;
end $$;

drop table pre_${shortNo};
drop table want_ports_${shortNo};
drop table want_goods_${shortNo};
drop table want_offers_${shortNo};
drop table want_legs_${shortNo};
`)

const sql = lines.join('\n')
if (sql.includes('\r')) throw new Error('CR in generated SQL — refuse to emit (the chain is LF-only)')
writeFileSync(OUT, sql, 'utf8')
console.log(`wrote ${OUT.replace(REPO_ROOT, '.')}`)
console.log(`  ${(sql.length / 1024).toFixed(0)} KB of SQL`)
if (existsSync(OUT)) {
  console.log('  re-running this exact command regenerates it against the same baseline (the file itself is excluded).')
}
