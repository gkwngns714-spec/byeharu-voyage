// ═══════════════════════════════════════════════════════════════════════════════════════════════
// world-guard.mjs — ON EVERY APPLY: the applied world must EQUAL data/*.json, or the run fails.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// WHY THIS EXISTS. On 2026-08-24 migration 0003 was found to have been edited AFTER production
// applied it: production held 70 goods while every fresh rebuild got 243, and ten island ports in
// data/ports.json existed in no database at all. Nothing red happened anywhere — the chain was
// green, the proofs were green, and the world was simply not the data. This guard makes that class
// of drift impossible to commit silently: apply-chain.mjs calls it after the chain lands, so
// `npm run db:apply`, `npm run db:proof` and CI's apply-proof job all fail loudly the moment the
// chain's world and data/*.json disagree — whichever of the two moved.
//
// WHAT "EQUAL" MEANS HERE
//   * harbours    every port in data/ports.json exists (by pinned code), every column the chain
//                 derives from the data is equal, both directions — EXCEPT crew_pool, which is
//                 seeded once and then owned by the running game (0007 hire drains it)
//   * goods       every good, every column, both directions
//   * offers      every port's port_specialties rows equal its `goods` array, as a set
//   * legs        every harbour-harbour leg equals data/sea-routes.json: pair, distance, hazard,
//                 note. SEA_PLACE spur legs belong to 0036 (generated from data/sea-places.json);
//                 here each place is checked to exist, sit where the data says, and keep its spurs
//   * seas/regions/nations   the code+name sets are equal
//   * market      exactly one port_goods row per (harbour, good) — the market covers the world
//
// WHAT IT DOES NOT CHECK (and why): runtime state (stock, drift, season_mod, crew_pool — the
// game's, not the data's); affinity values (0041's self-assert pins them to the one formula, and
// re-runs on every chain apply); the browser's own apply (src/lib/db) — the chain FINGERPRINT
// guarantees the browser applies the same bytes this guard just certified.
//
// POSITIVE CONTROL, EVERY RUN: before certifying, the comparator is aimed at a deliberately
// mutated copy of the derived world (one harbour dropped, one distance bent) and MUST report both
// wounds. A guard that cannot see a planted drift certifies nothing (proofs-never-assert rule).
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { deriveWorld, REPO_ROOT, round2 } from '../lib/world-derive.mjs'

/** Compare the applied world (queried once, below) against a derived world. Pure. */
function drift(db_, want) {
  const out = []
  const say = (s) => out.push(s)

  // harbours
  const wPorts = new Map(want.ports.map((p) => [p.code, p]))
  for (const p of db_.ports) if (!wPorts.has(p.code)) say(`harbour ${p.code} (${p.name}) is in the database but not in data/ports.json`)
  for (const p of want.ports) {
    const d = db_.ports.find((x) => x.code === p.code)
    if (!d) { say(`harbour ${p.code} (${p.name}) is in data/ports.json but not in the database`); continue }
    const pairs = [
      ['name', d.name, p.name], ['country', d.country, p.country],
      ['nation', d.nation_code ?? null, p.nation_code ?? null],
      ['lat', Number(d.lat), p.lat], ['lon', Number(d.lon), p.lon],
      ['sea', d.sea_code, p.sea_code], ['region', d.region_code, p.region_code],
      ['culture', d.culture, p.culture], ['size_tier', Number(d.size_tier), p.size_tier],
      ['max_draft', Number(d.max_draft), p.max_draft], ['yard_tier', Number(d.yard_tier), p.yard_tier],
      ['has_yard', Boolean(d.has_yard), p.has_yard], ['has_academy', Boolean(d.has_academy), p.has_academy],
      ['dev_industry', Number(d.dev_industry), p.dev_industry],
      ['dev_commerce', Number(d.dev_commerce), p.dev_commerce],
      ['dev_military', Number(d.dev_military), p.dev_military],
    ]
    for (const [col, got, wanted] of pairs) {
      if (String(got) !== String(wanted)) say(`harbour ${p.code}.${col}: database has ${got}, data says ${wanted}`)
    }
  }

  // goods
  const wGoods = new Map(want.goods.map((g) => [g.code, g]))
  for (const g of db_.goods) if (!wGoods.has(g.code)) say(`good ${g.code} is in the database but not in data/goods.json`)
  for (const g of want.goods) {
    const d = db_.goods.find((x) => x.code === g.code)
    if (!d) { say(`good ${g.code} (${g.name}) is in data/goods.json but not in the database`); continue }
    const dMask = Array.isArray(d.culture_mask) ? d.culture_mask : String(d.culture_mask ?? '{}').replace(/[{}"]/g, '').split(',').filter(Boolean)
    if (d.name !== g.name) say(`good ${g.code}.name: database has ${d.name}, data says ${g.name}`)
    if (Math.abs(Number(d.base_value) - g.base_value) > 1e-9) say(`good ${g.code}.base_value: ${d.base_value} vs ${g.base_value}`)
    if (Math.abs(Number(d.bulk) - g.bulk) > 1e-9) say(`good ${g.code}.bulk: ${d.bulk} vs ${g.bulk}`)
    if (Math.abs(Number(d.perishable_pct_day) - g.perishable_pct_day) > 1e-9) say(`good ${g.code}.perishable: ${d.perishable_pct_day} vs ${g.perishable_pct_day}`)
    if (d.category !== g.category) say(`good ${g.code}.category: ${d.category} vs ${g.category}`)
    if (JSON.stringify(dMask) !== JSON.stringify(g.culture_mask)) say(`good ${g.code}.culture_mask: {${dMask}} vs {${g.culture_mask}}`)
  }

  // offers
  const dSpec = new Set(db_.spec.map((s) => `${s.port}|${s.good}`))
  const wSpec = new Set(want.specialtyPairs.map(([p, g]) => `${p}|${g}`))
  for (const k of wSpec) if (!dSpec.has(k)) say(`offer ${k.replace('|', '·')} is in a data roster but not in port_specialties`)
  for (const k of dSpec) if (!wSpec.has(k)) say(`offer ${k.replace('|', '·')} is in port_specialties but in no data roster`)

  // harbour legs
  const key = (f, t) => `${f}|${t}`
  const wLegs = new Map(want.legs.map((l) => [key(l.from, l.to), l]))
  const dLegs = new Map(db_.legs.map((l) => [key(l.f, l.t), l]))
  for (const [k, l] of wLegs) {
    const d = dLegs.get(k)
    if (!d) { say(`leg ${k.replace('|', '-')} (${Math.round(l.nm)} nm) is in data/sea-routes.json but not in the database`); continue }
    if (Math.abs(Number(d.nm) - Math.round(l.nm * 10) / 10) > 0.05) say(`leg ${k.replace('|', '-')}.distance: ${d.nm} vs ${Math.round(l.nm * 10) / 10}`)
    if (Math.abs(Number(d.hz) - l.hazard) > 1e-9) say(`leg ${k.replace('|', '-')}.hazard: ${d.hz} vs ${l.hazard}`)
    if (String(d.note ?? '') !== String(l.note ?? '')) say(`leg ${k.replace('|', '-')}.note differs`)
  }
  for (const k of dLegs.keys()) if (!wLegs.has(k)) say(`leg ${k.replace('|', '-')} is in the database but not in data/sea-routes.json`)

  // sea places
  const wPlaces = new Map(want.places.map((p) => [p.code, p]))
  for (const p of db_.places) if (!wPlaces.has(p.code)) say(`sea place ${p.code} (${p.name}) is in the database but not in data/sea-places.json`)
  for (const p of want.places) {
    const d = db_.places.find((x) => x.code === p.code)
    if (!d) { say(`sea place ${p.code} (${p.name}) is in data/sea-places.json but not in the database`); continue }
    if (d.name !== p.name) say(`sea place ${p.code}.name: ${d.name} vs ${p.name}`)
    if (Math.abs(Number(d.lat) - round2(p.lat)) > 1e-9 || Math.abs(Number(d.lon) - round2(p.lon)) > 1e-9) {
      say(`sea place ${p.code} sits at (${d.lat}, ${d.lon}); data says (${round2(p.lat)}, ${round2(p.lon)})`)
    }
    if (Number(d.spurs) < 1) say(`sea place ${p.code} has no spur leg at all — it cannot be reached`)
  }

  // seas / regions / nations
  const setCheck = (dbRows, wantRows, what) => {
    const ds = new Set(dbRows.map((x) => `${x.code}|${x.name}`))
    const ws = new Set(wantRows.map((x) => `${x.code}|${x.name}`))
    for (const k of ws) if (!ds.has(k)) say(`${what} ${k.replace('|', ' ')} is derived from the data but absent from the database`)
    for (const k of ds) if (!ws.has(k)) say(`${what} ${k.replace('|', ' ')} is in the database but the data does not derive it`)
  }
  setCheck(db_.seas, want.seas, 'sea')
  setCheck(db_.regions, want.regions, 'region')
  setCheck(db_.nations, want.nations, 'nation')

  // market coverage
  const expected = want.ports.length * want.goods.length
  if (Number(db_.marketRows) !== expected) {
    say(`port_goods holds ${db_.marketRows} rows; ${want.ports.length} harbours × ${want.goods.length} goods = ${expected} — the market does not cover the world`)
  }

  return out
}

/**
 * The standing check. Reads the applied world from `db` (a live PGlite/PG connection), derives
 * the wanted world from data/*.json, and THROWS with every difference if they are not equal.
 * apply-chain.mjs calls this after the last migration, so every local and CI apply is gated.
 */
export async function assertWorldMatchesData(db, { log = console.log } = {}) {
  const hasKind = (await db.query(
    `select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'ports' and column_name = 'kind'`,
  )).rows.length > 0
  if (!hasKind) throw new Error('world-guard: ports.kind is missing — the chain no longer reaches 0036, so this guard cannot tell harbours from sea places')

  const db_ = {}
  db_.ports = (await db.query(`
    select p.code, p.name, p.country, n.code as nation_code, p.lat::float8 lat, p.lon::float8 lon,
           s.code as sea_code, r.code as region_code, p.culture, p.size_tier, p.max_draft,
           p.has_yard, p.yard_tier, p.has_academy, p.dev_industry, p.dev_commerce, p.dev_military
      from public.ports p
      join public.seas s on s.id = p.sea_id
      join public.regions r on r.id = p.region_id
      left join public.nations n on n.id = p.nation_id
     where p.kind = 'HARBOUR' order by p.code`)).rows
  db_.places = (await db.query(`
    select p.code, p.name, p.lat::float8 lat, p.lon::float8 lon,
           (select count(*) from public.legs l where l.from_port_id = p.id or l.to_port_id = p.id) as spurs
      from public.ports p where p.kind = 'SEA_PLACE' order by p.code`)).rows
  db_.goods = (await db.query(`
    select code, name, base_value::float8 base_value, bulk::float8 bulk,
           perishable_pct_day::float8 perishable_pct_day, category, culture_mask
      from public.goods order by code`)).rows
  db_.legs = (await db.query(`
    select a.code as f, b.code as t, l.distance_nm::float8 nm, l.hazard_mult::float8 hz, l.notes as note
      from public.legs l
      join public.ports a on a.id = l.from_port_id
      join public.ports b on b.id = l.to_port_id
     where a.kind = 'HARBOUR' and b.kind = 'HARBOUR'`)).rows
  db_.spec = (await db.query(`
    select p.code as port, g.code as good from public.port_specialties s
      join public.ports p on p.id = s.port_id join public.goods g on g.id = s.good_id`)).rows
  db_.seas = (await db.query(`select code, name from public.seas`)).rows
  db_.regions = (await db.query(`select code, name from public.regions`)).rows
  db_.nations = (await db.query(`select code, name from public.nations`)).rows
  db_.marketRows = (await db.query(`select count(*)::int as n from public.port_goods`)).rows[0].n

  const want = deriveWorld()
  want.places = JSON.parse(readFileSync(join(REPO_ROOT, 'data', 'sea-places.json'), 'utf8')).places

  // ── POSITIVE CONTROL: the comparator must SEE a planted drift before it may certify zero ─────
  const wounded = {
    ...want,
    ports: want.ports.slice(1),                                      // one harbour dropped
    legs: want.legs.map((l, i) => (i === 0 ? { ...l, nm: l.nm + 500 } : l)), // one distance bent
  }
  const seen = drift(db_, wounded)
  const sawDrop = seen.some((s) => s.includes(`${want.ports[0].code}`))
  const sawBend = seen.some((s) => s.includes('.distance:'))
  if (!sawDrop || !sawBend) {
    throw new Error(
      'WORLD GUARD IS BLIND: a deliberately dropped harbour ' +
        `(${want.ports[0].code}) or bent leg distance was NOT reported by the comparator ` +
        `(saw ${seen.length} finding(s)). A guard that cannot see a planted drift certifies nothing.`,
    )
  }

  const findings = drift(db_, want)
  if (findings.length > 0) {
    const head = findings.slice(0, 40)
    throw new Error(
      [
        'WORLD DRIFT: the applied chain and data/*.json disagree ' +
          `(${findings.length} difference(s)). The world the players get is not the world the data ` +
          'describes. If the data moved, generate a growth migration ' +
          '(scripts/build-world-growth.mjs); a shipped migration is never edited.',
        ...head.map((s) => `  * ${s}`),
        findings.length > head.length ? `  … and ${findings.length - head.length} more` : null,
      ].filter(Boolean).join('\n'),
    )
  }

  log(
    `world-guard ok: the applied world EQUALS data/*.json — ${want.ports.length} harbours, ` +
      `${want.goods.length} goods, ${want.specialtyPairs.length} offers, ${want.legs.length} legs, ` +
      `${want.places.length} sea places, ${db_.marketRows} market rows ` +
      `(positive control: a planted dropped-harbour and bent-distance were both seen)`,
  )
}
