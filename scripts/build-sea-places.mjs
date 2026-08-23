// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE SEA HAS PLACES IN IT — generates migration 0036 from data/sea-places.json.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// The owner chose, over free steering (option A, the OSN shape byeharu built and deleted):
//   "B — the sea has places in it." Destinations stop being only ports: fishing grounds, straits,
//   belts of wind. Same continuous movement, same live coordinates — but each one is SOMEWHERE,
//   so a pirate can one day wait there and a thing can one day be discovered there.
//
// WHAT A SEA PLACE IS (the decision, defended in the migration header this script writes):
//   a row in public.ports with kind = 'SEA_PLACE' — a node of the one leg graph, reached by the
//   one router, arrived at by the one settle, drawn by the one chart. NOT a new table.
//
// WHAT THIS SCRIPT DERIVES, AND FROM WHAT:
//   spur legs   the K=3 nearest harbours BY SEA for each place, distances from the same 0.25°
//               water raster the 782 authored legs came from (scripts/sea-grid.mjs, the ONE
//               routing rule). A sea place therefore joins the graph exactly the way a harbour
//               does, and the stored distance obeys the same invariant: >= the great circle.
//   escape leg  (reported, not stored): the nearest harbour, which voyage.sail_refusal's
//               round-trip stores rule will quote when it refuses a one-way trap.
//
// WHAT IS NOT DERIVED: the places themselves. Names, coordinates, seas, hazard and the approach
// line the lookout speaks on arrival are AUTHORED in data/sea-places.json — these are waters a
// sailor of 1550 knew by name, and a place in the wrong sea is visible on the chart at a glance.
//
// STRICTLY WATER: a place whose own 0.25° cell is land is REFUSED (no snapping) — a sea place on
// land could still reach the chain through snapToWater, and the chart would draw it in a field.
//
// ⚠ scripts/build-sea-routes.mjs (the 782-leg generator) is deliberately NOT touched and NOT
//   imported beyond sea-grid.mjs. The fold of sea places into that generator — so straits become
//   through-nodes of the world graph rather than spurs — is specified in the 0036 migration
//   header and waits for the candidate-limit fix that is being made to it in a parallel worktree.
//
// Run:    node scripts/build-sea-places.mjs
// Writes: supabase/migrations/20260818000036_the_sea_has_places_in_it.sql
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { existsSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'
import { buildSeaGrid, findSeaRoute, gcNm, isWater, rowOf, colOf } from './sea-grid.mjs'
import { applyChain } from './db/apply-chain.mjs'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const DATA = join(ROOT, 'data')
const OUT = join(ROOT, 'supabase', 'migrations', '20260818000036_the_sea_has_places_in_it.sql')

const K_NEAREST = 3 // spur legs per place: enough that a place is a junction, not a cul-de-sac
const CANDIDATE_NM = 2500 // straight-line radius for candidate harbours; widened when too few
const CANDIDATE_NM_WIDE = 4500
const SEARCH_LIMIT_NM = 8000

const q = (s) => (s === null || s === undefined ? 'null' : `'${String(s).replace(/'/g, "''")}'`)
const round2 = (n) => Math.round(n * 100) / 100

// ── the authored places ───────────────────────────────────────────────────────────────────────
const placesFile = JSON.parse(readFileSync(join(DATA, 'sea-places.json'), 'utf8'))
const seas = JSON.parse(readFileSync(join(DATA, 'seas.json'), 'utf8')).seas
const regions = JSON.parse(readFileSync(join(DATA, 'regions.json'), 'utf8')).regions
const seaById = new Map(seas.map((s) => [s.id, s]))
const regionById = new Map(regions.map((r) => [r.id, r]))

const places = placesFile.places
const seenIds = new Set()
const seenCodes = new Set()
for (const p of places) {
  const fail = (msg) => {
    throw new Error(`sea place ${p.id ?? '(no id)'}: ${msg}`)
  }
  if (!p.id || seenIds.has(p.id)) fail('missing or duplicate id')
  seenIds.add(p.id)
  if (!/^[A-Z]{3}$/.test(p.code ?? '') || seenCodes.has(p.code)) fail('code must be a unique ^[A-Z]{3}$')
  seenCodes.add(p.code)
  if (!Number.isFinite(p.lat) || !Number.isFinite(p.lon)) fail('lat/lon must be numbers')
  if (!seaById.has(p.sea)) fail(`sea "${p.sea}" is not in data/seas.json`)
  if (!regionById.has(p.region)) fail(`region "${p.region}" is not in data/regions.json`)
  if (![2, 3].includes(p.tier)) fail('tier must be 2 or 3 (a sea place is never a great entrepôt)')
  if (!(p.leg_hazard > 0 && p.leg_hazard <= 2)) fail('leg_hazard must be in (0, 2] — the band the world uses')
  if (!p.approach || !p.approach.trim()) fail('approach (the lookout line spoken on arrival) is required')
}

// ── the harbours, from the applied chain — the real codes, never re-derived ───────────────────
// The chain is applied WITHOUT this script's own previous output: 0036 is about to be rewritten,
// and a broken previous cut must not be able to stop its own regeneration.
if (existsSync(OUT)) {
  rmSync(OUT)
  console.log('removed the previous 0036 (about to be regenerated)')
}
console.log('applying the chain to read the real harbour table…')
const { db } = await applyChain({ quiet: true, log: () => {} })
const hasKind = (
  await db.query(
    "select 1 from information_schema.columns where table_schema = 'public' and table_name = 'ports' and column_name = 'kind'",
  )
).rows.length > 0
const harbours = (
  await db.query(
    hasKind
      ? "select code, name, lat::float8 as lat, lon::float8 as lon from public.ports where kind = 'HARBOUR' order by code"
      : 'select code, name, lat::float8 as lat, lon::float8 as lon from public.ports order by code',
  )
).rows
const seaNamesDb = new Set((await db.query('select name from public.seas')).rows.map((r) => r.name))
const regionNamesDb = new Set((await db.query('select name from public.regions')).rows.map((r) => r.name))
await db.close()
console.log(`harbours           ${harbours.length}`)

for (const p of places) {
  if (harbours.some((h) => h.code === p.code)) throw new Error(`sea place ${p.id}: code ${p.code} collides with a harbour`)
  if (!seaNamesDb.has(seaById.get(p.sea).name)) throw new Error(`sea place ${p.id}: sea name "${seaById.get(p.sea).name}" not in the chain`)
  if (!regionNamesDb.has(regionById.get(p.region).name)) throw new Error(`sea place ${p.id}: region name "${regionById.get(p.region).name}" not in the chain`)
  for (const h of harbours) {
    if (Math.abs(h.lat - p.lat) < 0.05 && Math.abs(h.lon - p.lon) < 0.05) {
      throw new Error(`sea place ${p.id} sits on top of harbour ${h.code} (${h.name})`)
    }
  }
}

// ── the water, and the spur legs ──────────────────────────────────────────────────────────────
const t0 = Date.now()
const water = buildSeaGrid()
console.log(`sea grid           built (${Date.now() - t0} ms)`)

for (const p of places) {
  if (!isWater(water, rowOf(p.lat), colOf(p.lon))) {
    throw new Error(
      `sea place ${p.id} (${p.lat}, ${p.lon}) is NOT water on the 0.25° raster — a sea place on land ` +
        'is refused outright, never snapped to the nearest wet cell. Move the point.',
    )
  }
}

const legs = [] // { placeCode, harbourCode, nm, note }
const escapes = new Map() // placeCode -> { code, name, nm }
for (const p of places) {
  const candidates = harbours
    .map((h) => ({ h, gc: gcNm(p.lat, p.lon, h.lat, h.lon) }))
    .sort((a, b) => a.gc - b.gc)
  const routed = []
  for (const radius of [CANDIDATE_NM, CANDIDATE_NM_WIDE]) {
    for (const c of candidates) {
      if (c.gc > radius) break
      if (routed.some((r) => r.h.code === c.h.code)) continue
      const r = findSeaRoute(water, p, c.h, { limitNm: SEARCH_LIMIT_NM })
      if (r) routed.push({ h: c.h, nm: r.nm, gc: c.gc })
      if (routed.length >= K_NEAREST * 3) break // enough sailed candidates to pick the K nearest BY SEA
    }
    if (routed.length >= 2) break
  }
  if (routed.length < 2) {
    throw new Error(`sea place ${p.id}: only ${routed.length} harbour(s) reachable by sea — a place with one road is a trap`)
  }
  routed.sort((a, b) => a.nm - b.nm)
  const keep = routed.slice(0, K_NEAREST)
  escapes.set(p.code, { code: keep[0].h.code, name: keep[0].h.name, nm: Math.round(keep[0].nm) })
  for (const k of keep) {
    // Same storage rule as build-world-seed.mjs: the chain re-derives the great circle from the
    // STORED (0.01°-rounded) coordinates, so the stored distance is never allowed under it.
    const gcRounded = gcNm(round2(p.lat), round2(p.lon), round2(k.h.lat), round2(k.h.lon))
    const nm = Math.max(Math.ceil(k.nm * 10) / 10, Math.ceil(gcRounded * 10) / 10)
    legs.push({
      placeCode: p.code,
      harbourCode: k.h.code,
      nm,
      note: `${Math.round(nm)} nm of open water to ${p.name} (sea place, 0036)`,
    })
  }
  console.log(
    `${p.name.padEnd(22)} ${keep.map((k) => `${k.h.code} ${Math.round(k.nm)}nm`).join('  ')}`,
  )
}

// Canonical leg order: lower code first, the 0002 rule the whole chain asserts.
const legRows = legs
  .map((l) => {
    const [a, b] = l.placeCode < l.harbourCode ? [l.placeCode, l.harbourCode] : [l.harbourCode, l.placeCode]
    return { from: a, to: b, nm: l.nm, hazard: places.find((p) => p.code === l.placeCode).leg_hazard, note: l.note }
  })
  .sort((x, y) => (x.from === y.from ? x.to.localeCompare(y.to) : x.from.localeCompare(y.from)))

// ── the migration ─────────────────────────────────────────────────────────────────────────────
const placeValues = places
  .map((p) => {
    const sea = seaById.get(p.sea).name
    const region = regionById.get(p.region).name
    return `    (${q(p.code)}, ${q(p.name)}, ${round2(p.lat)}, ${round2(p.lon)}, ${q(sea)}, ${q(region)}, ${p.tier}, ${q(p.approach)})`
  })
  .join(',\n')

const legValues = legRows
  .map((l) => `    (${q(l.from)}, ${q(l.to)}, ${l.nm.toFixed(1)}, ${l.hazard.toFixed(3)}, ${q(l.note)})`)
  .join(',\n')

const sql = `-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0036 — THE SEA HAS PLACES IN IT
--        ${places.length} named locations in open water a fleet can sail to and arrive at, as nodes of the
--        ONE leg graph. GENERATED by scripts/build-sea-places.mjs from data/sea-places.json —
--        do not hand-edit; edit the data or the generator and run it again.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE ASK ─────────────────────────────────────────────────────────────────────────────────────
-- The owner, 2026-08-23: "but we need coordinate. we will move around the world, seas." Offered
-- free steering (the OSN shape the predecessor built, never lit, and deleted — docs/PLATFORM.md §1)
-- against "the sea has places in it", the owner chose the places. This file is their foundation:
-- the fishing ground, the strait, the belt of wind — each one SOMEWHERE, so that what happens at
-- sea can one day happen AT a place, which is exactly what the predecessor's free coordinates
-- made structurally impossible ("open space has no location" — the audit finding).
--
-- ── THE FOUR DECISIONS (NO_SPAGHETTI §7B), ANSWERED BEFORE THE SQL ─────────────────────────────
--
-- 1. WHAT IS A SEA PLACE? A ROW IN public.ports WITH kind = 'SEA_PLACE' — not a new table.
--    The concept, in one noun phrase: A NAMED LOCATION A FLEET CAN BE AT. That concept already
--    has one authority — public.ports — and every rule about being somewhere already stands on
--    it: the leg graph's foreign keys, voyage.route/reach_from, voyage.depart, settle's arrival,
--    sail_refusal, the chart, the SAIL picker, the order parser. A second node table would need
--    polymorphic leg endpoints or a parallel graph: two authorities for "where can she be", the
--    exact dead end that got OSN deleted (a fleet at a free coordinate could not be fought
--    BECAUSE it had a weaker kind of existence than a port). The cost of this choice, stated:
--    every rule that assumes a port has a SHORE now needs the distinction — and this file pays
--    that cost in full rather than leaving it to be found: the chandler (do_provision), the fair
--    calendar (tick_buff_calendar + a table trigger), the stores gate (sail_refusal), and the
--    served payload (world.snapshot carries kind). What needs NO guard is measured, not assumed:
--    BUY/SELL die on the absent market rows (E_NO_SUCH_GOOD), HIRE on crew_pool 0 (E_CREW_POOL),
--    REPAIR on has_yard false (E_NO_YARD), fame/rarity/prices/fairs key on port_goods and
--    port_specialties rows a sea place simply does not have.
--
-- 2. HOW IS IT REACHED? By ${legRows.length} spur LEGS to each place's ${K_NEAREST} nearest harbours BY SEA — real
--    sailed A* distances over the same 0.25° water raster as the 782 authored legs, generated by
--    the same rule (scripts/sea-grid.mjs), obeying the same invariant (>= the great circle, and
--    asserted below over the WHOLE table). The router, the picker and the chart take them with
--    zero new code, because a sea place is a port row (decision 1).
--    ⚠ WHAT WAITS: folding sea places into scripts/build-sea-routes.mjs as first-class nodes —
--    so the Strait of Gibraltar sits ON the Lisbon–Genoa road instead of one spur off it — is
--    DELIBERATELY not done here: that generator is being fixed in a parallel worktree (the
--    1,300 nm candidate limit that routes Lisbon–Brazil via Iceland) and two hands in one file
--    is how generators fork. The precise spec for that fold is at the foot of this header. Every
--    insert below is idempotent (on conflict do nothing), so the later fold cannot double-seed.
--
-- 3. WHAT IS IT FOR, TODAY? Sailing there, ARRIVING, and the arrival being an EVENT the report
--    tells you about — composing 0035's catalogue: one new kind, LANDFALL, is_rolled = false (a
--    CONDITION, never drawn by the dice), whose sentence carries the place's authored approach
--    line. voyage.settle's arrival arm writes it for SEA_PLACE destinations only — a harbour
--    arrival already has the whole Port tab; a sea-place arrival has the report, so the report
--    says something worth reading. NO combat, NO exploration, NO NPCs, NO goods: PLATFORM.md §6
--    forbids exactly that, and a half-built encounter system takes the foundation with it. A
--    fishing ground yielding a good was considered and refused for this slice: a yield needs a
--    verb or an arrival mutation, both of which are the ACTIVITY seam's next brick, not this one.
--
-- 4. WHAT MUST NOT BE ASSUMED? A future encounter system needs: a place to be AT (this file: an
--    arrived fleet holds port_id = the place — a real presence row, the thing OSN never had); a
--    deterministic rng (0006, untouched); what-can-happen as data (0035, composed); an actor
--    (PLATFORM §6 seam 2, deliberately open); more than one event per voyage-day (§6 seam 3,
--    deliberately open — LANDFALL sits at day total+1 precisely so it needs no PK change). NOT
--    foreclosed: sea places may later carry markets (kind is a column, not a schema fork), fairs
--    of their own kind (the trigger names the rule it enforces), per-place event weights
--    (PLATFORM §6 row 4 composes on sea_id, which every spur leg carries).
--
-- ── ONE-WAY TRAPS ARE REFUSED AT THE QUAY ──────────────────────────────────────────────────────
-- A sea place has no chandler, so a fleet that arrives with empty casks could neither provision
-- nor leave — bricked for ever, the predecessor's recorded empty-fleet deadlock shape. The stores
-- gate (voyage.sail_refusal, superseded below) therefore requires stores for the passage PLUS the
-- shortest sailed way back to a harbour, x the endurance margin, whenever the DESTINATION is a
-- sea place. The refusal names both figures and PROVISION remains the fix.
--
-- ── SUPERSEDES ─────────────────────────────────────────────────────────────────────────────────
--   voyage.sail_refusal      0019:396  — re-cut whole: + the round-trip stores clause above.
--                                        Byte-identical for harbour destinations (asserted).
--   public.tick_buff_calendar 0026:317 — re-cut whole: the calendar draws fairs at HARBOURS only.
--                                        A fair is a market event; open water has no market. The
--                                        rule is also on the TABLE (trigger below), so any future
--                                        writer inherits it — 0034's provision-cap pattern.
--   voyage.settle            0027:238 (sliced by 0034) — SLICED again, one hunk: the arrival arm
--                                        writes the LANDFALL event for sea-place destinations,
--                                        before the report emit so the report's last line is the
--                                        landfall. Wage/ration/day arithmetic untouched BY
--                                        CONSTRUCTION (reverse-substitution parity asserted).
--   cmd.do_provision         0017:250 (sliced by 0034) — SLICED, one hunk: E_NO_CHANDLER at a sea
--                                        place. Without it the flat provision knobs would sell
--                                        fresh water in the middle of the Sargasso.
--   world.snapshot           0032:—   — SLICED, one hunk: ports[] gains 'kind' and 'approach',
--                                        so no screen has to invent which places have a quay.
--
-- ── THE GENERATOR SPEC THAT WAITS (for scripts/build-sea-routes.mjs, after its fix lands) ──────
--   1. Read data/sea-places.json beside ports.json; a place enters the node set with its
--      authored coordinate, STRICTLY-water asserted (no snapToWater for places).
--   2. Places join pass 1's candidate pairs (place–port and place–place), with K_NEAREST_PLACE=3,
--      so straits and capes become through-nodes where the water makes them one.
--   3. hazardOf() takes max(derived, place.leg_hazard) for a leg touching a place — the authored
--      character of the water outranks the derived floor, never undercuts it.
--   4. The emitted legs carry the same canonical order and the same >= great-circle invariant;
--      sea-place rows/legs land as a NEW idempotent migration (never an edit of applied 0003),
--      and this file's spur legs are then superseded BY DELETION in that same migration if the
--      through-graph replaces them — never left as a second, disagreeing road.
--
-- ── WHAT IT SELF-ASSERTS (every assert able to fail; break-tested red before trusted) ──────────
--   (a) deltas: exactly ${places.length} SEA_PLACE rows and ${legRows.length} spur legs landed, measured against the
--       counts captured BEFORE the inserts — never asserted as absolute totals against a world
--       another migration may have grown.
--   (b) every sea place has >= 2 legs, EVERY leg in the world still >= its great circle, the
--       whole graph is still ONE component from Lisboa, and every sea place is settled by
--       voyage.reach_from(Lisboa) at a finite sailed distance.
--   (c) sail_refusal is a NO-OP for harbour destinations (same answer, same text, before/after —
--       the pre-image function is kept under a probe name and both are asked); for a sea-place
--       destination the round-trip clause REFUSES a fleet with one-way stores (real red) and
--       passes the same fleet once provisioned.
--   (d) the WIRING, end to end: a house is founded, provisions, hires, SAILS to the nearest sea
--       place from Lisboa (found deterministically, never named), the voyage settles at its ETA,
--       and the fleet is DOCKED AT THE PLACE with exactly one LANDFALL event whose report line
--       carries the authored approach — then PROVISION there is refused E_NO_CHANDLER (real
--       red), HIRE is refused, and she sails HOME on the reserve the gate forced her to carry.
--       settle re-run x3 moves nothing (idempotence, the 0007 rule).
--   (e) the fair calendar: a (kind, season) is FOUND (deterministically, by scanning the rng)
--       in which the unfiltered draw would have put a fair at a sea place; the calendar is wound
--       at that instant; zero sea-place fairs exist and the harbour draws for that season all
--       landed. The table trigger is shown biting on a direct insert (real red).
--   (f) slices: each hunk occurred EXACTLY once; reverse-substituting the new text yields the
--       pre-image byte-for-byte (nothing else moved); ACLs unchanged; snapshot's ports[] is the
--       old payload plus the two new fields and the new rows, its other sections byte-identical.
--   (g) posture: catalogue weights still close, LANDFALL is never rolled, 0 client write grants,
--       all four read-wall authorities still read zero.
--
-- Depends ONLY on: 0002 (ports/legs), 0003 (the world), 0006 (route/depart/settle machinery),
--                  0007/0027/0034 (settle, do_provision — sliced), 0019 (sail_refusal, reach_from),
--                  0026 (tick_buff_calendar, active_buffs), 0032 (world.snapshot), 0035 (the
--                  voyage_event_kinds catalogue and its FK).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 0. PRE-IMAGES — captured before anything moves, because "this changes nothing" is not
--       evidence (NO_SPAGHETTI §3.3). The counts feed the DELTA asserts; the defs feed the
--       exactly-once slice asserts and the reverse-substitution parity; the snapshot feeds the
--       payload no-op; the old sail_refusal is KEPT under a probe name so (c) can ask both.
create temporary table pre_0036 as
  select (select count(*) from public.ports) as ports,
         (select count(*) from public.legs)  as legs,
         (select count(*) from public.voyage_event_kinds) as kinds,
         world.snapshot() as snapshot;

create temporary table defs_before_0036 as
  select 'voyage.settle'::text as fn,
         pg_get_functiondef('voyage.settle(uuid, timestamptz)'::regprocedure) as def,
         (select p.proacl::text from pg_proc p where p.oid = 'voyage.settle(uuid, timestamptz)'::regprocedure) as acl
  union all
  select 'cmd.do_provision',
         pg_get_functiondef('cmd.do_provision(uuid, jsonb)'::regprocedure),
         (select p.proacl::text from pg_proc p where p.oid = 'cmd.do_provision(uuid, jsonb)'::regprocedure)
  union all
  select 'world.snapshot',
         pg_get_functiondef('world.snapshot()'::regprocedure),
         (select p.proacl::text from pg_proc p where p.oid = 'world.snapshot()'::regprocedure)
  union all
  select 'voyage.sail_refusal',
         pg_get_functiondef('voyage.sail_refusal(uuid, uuid, numeric)'::regprocedure),
         (select p.proacl::text from pg_proc p where p.oid = 'voyage.sail_refusal(uuid, uuid, numeric)'::regprocedure)
  union all
  select 'public.tick_buff_calendar',
         pg_get_functiondef('public.tick_buff_calendar(timestamptz)'::regprocedure),
         (select p.proacl::text from pg_proc p where p.oid = 'public.tick_buff_calendar(timestamptz)'::regprocedure);

-- The 0019 sail_refusal, verbatim, under a probe-only name — so assert (c) can put the same
-- question to both definitions instead of trusting prose. Dropped at the foot of this file.
do $$
declare v_def text;
begin
  select def into v_def from defs_before_0036 where fn = 'voyage.sail_refusal';
  execute replace(v_def, 'voyage.sail_refusal(', 'voyage.sail_refusal_0019_probe(');
end $$;

-- ── 1. THE DISTINCTION, AS A COLUMN — one authority for "is there a shore here?" ───────────────
-- WHERE IT LIVES AND WHY (§7B q2): on public.ports, because decision 1 above makes a sea place a
-- port row; a side table keyed by port_id would be a second place to look for a fact about one
-- row. WHO THE SECOND CALLER IS (q3): five on day one — sail_refusal, do_provision, settle's
-- arrival arm, tick_buff_calendar, world.snapshot. WHAT WOULD MAKE IT THE WRONG SHAPE (q4): a
-- third kind with different rules (a river mouth? a roadstead?) — the tell is a second boolean
-- growing beside it; the CHECK names the closed set so adding one is a deliberate migration.
alter table public.ports add column if not exists kind text not null default 'HARBOUR';
alter table public.ports add column if not exists approach text;
alter table public.ports
  add constraint ports_kind_named check (kind in ('HARBOUR', 'SEA_PLACE')),
  add constraint ports_approach_iff_sea_place check ((kind = 'SEA_PLACE') = (approach is not null));

comment on column public.ports.kind is
  '0036: HARBOUR is a settlement with a shore — market, chandler, crew, possibly a yard. '
  'SEA_PLACE is a named location in open water: a node of the same leg graph, reached by the '
  'same router, arrived at by the same settle — and NOTHING ashore, which every shore-side rule '
  'checks here rather than assuming. THE one authority for "is there a quay?".';
comment on column public.ports.approach is
  '0036: the lookout''s line, spoken by the LANDFALL report when a fleet raises this sea place. '
  'Authored in data/sea-places.json. Exactly the SEA_PLACE rows carry one (CHECK above).';

-- ── 2. LANDFALL joins the catalogue — 0035's seam doing its job: one INSERT, no new authority ──
-- A CONDITION kind, never drawn (is_rolled = false, so the rolled weights stay closed and the
-- dice are untouched). The sentence interpolates the place and its authored approach out of the
-- payload settle writes. The crew clause cannot fire on it: the payload carries no crew_lost.
insert into public.voyage_event_kinds
  (code, ordinal, is_rolled, roll_weight, cedes_to, cede_fraction, prose, prose_keys, prose_fallbacks, note)
values
  ('LANDFALL', 6, false, null, null, null,
   'We raised %s and hove to. %s',
   array['place', 'remark'], array['the mark', 'The sea ran empty to every horizon.'],
   '0036: written by voyage.settle''s arrival arm when the destination is a SEA_PLACE — the one '
   'day a place with no quay gets its say. Never rolled: arrival is a fact of the schedule, not '
   'of the dice.')
on conflict (code) do nothing;

-- ── 3. THE PLACES — ${places.length} named waters, authored in data/sea-places.json ─────────────────────────
-- lat/lon are hand-placed where the named water actually is and STRICTLY-water asserted against
-- the same 0.25° raster the leg graph is derived from (the generator refuses to snap a land
-- point wet). country is 'High seas' — no crown holds them. No nation, no market, no crew, no
-- yard, no development: what is not there is stored as not there, never faked small.
insert into public.ports (
  code, name, country, nation_id, lat, lon, sea_id, region_id, culture,
  size_tier, max_draft, has_yard, yard_tier, has_academy,
  dev_industry, dev_commerce, dev_military, tax_rate, crew_pool, kind, approach
)
select v.code, v.name, 'High seas', null, v.lat, v.lon, s.id, r.id, 'open-sea',
       v.tier, 6, false, 0, false, 0, 0, 0, 0, 0, 'SEA_PLACE', v.approach
  from (values
${placeValues}
  ) as v(code, name, lat, lon, sea_name, region_name, tier, approach)
  join public.seas    s on s.name = v.sea_name
  join public.regions r on r.name = v.region_name
on conflict (code) do nothing;

-- ── 4. THE SPUR LEGS — each place joined to its ${K_NEAREST} nearest harbours BY SEA ─────────────────────
-- Sailed A* distances through the water raster (scripts/sea-grid.mjs — the ONE routing rule),
-- canonical lower-code-first like every leg since 0002, and >= the great circle by construction
-- AND by the assert below. hazard_mult is the place's authored character: the Roaring Forties
-- ARE the hazard; the strait is the calm road everyone watches.
insert into public.legs (from_port_id, to_port_id, distance_nm, hazard_mult, notes)
select pf.id, pt.id, v.nm, v.hz, v.note
  from (values
${legValues}
  ) as v(f, t, nm, hz, note)
  join public.ports pf on pf.code = v.f
  join public.ports pt on pt.code = v.t
on conflict do nothing;

-- ── 5. A FAIR NEEDS A QUAY — the rule on the TABLE, then the one writer composing it ───────────
-- 0034's pattern: put the refusal on the table so any future writer inherits it, and make the
-- one existing writer obey it so the trigger never fires in anger.
create or replace function public.tg_buff_needs_a_quay()
returns trigger
language plpgsql
as $$
begin
  if exists (select 1 from public.ports p where p.id = new.subject_id and p.kind = 'SEA_PLACE') then
    raise exception 'E_NO_QUAY: a fair needs a quay, and % is open water',
      (select name from public.ports p where p.id = new.subject_id)
      using errcode = '23514';
  end if;
  return new;
end $$;

comment on function public.tg_buff_needs_a_quay() is
  '0036: THE structural statement that a market event cannot be held where there is no market. '
  'public.tick_buff_calendar composes it by drawing at HARBOUR rows only; this refuses any '
  'future writer that has not read that file.';

drop trigger if exists buff_needs_a_quay on public.active_buffs;
create trigger buff_needs_a_quay
  before insert or update on public.active_buffs
  for each row execute function public.tg_buff_needs_a_quay();

-- ── 6. SUPERSEDES 0026:317 — the calendar draws fairs at harbours only ─────────────────────────
-- The body is 0026's, unchanged but for the one WHERE line marked 0036. The draw for every
-- harbour is the same pure function of (port, season, stream, secret) it always was — assert (e)
-- proves the harbour draws land identically and the sea-place draws never happen.
create or replace function public.tick_buff_calendar(p_at timestamptz default now())
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  k        public.buff_kinds%rowtype;
  v_season int;
  v_gds    numeric := public.wc_num('game_day_seconds');
  v_n      int;
  v_total  int := 0;
begin
  for k in select * from public.buff_kinds
            where season_game_days is not null and subject_kind = 'PORT'
            order by code
  loop
    v_season := public.buff_season_of(p_at, k.season_game_days);

    -- The draw is deterministic, so a repeat call writes nothing whether or not this short-circuit
    -- fires; it is here so the common case costs one index probe rather than 214 rng calls. If a
    -- season happens to draw no fair anywhere, the loop below simply re-derives the same nothing.
    if not exists (select 1 from public.active_buffs ab
                    where ab.kind_code = k.code and ab.season = v_season) then

      insert into public.active_buffs (kind_code, subject_id, season, starts_at, ends_at, source)
      select k.code, p.id, v_season,
             to_timestamp((d.open_day * v_gds)::double precision),
             to_timestamp(((d.open_day + k.duration_game_days) * v_gds)::double precision),
             'calendar'
        from public.ports p
        -- The fair opens somewhere INSIDE its season, on a game-day this port draws for itself, so
        -- 214 quays do not all open on the same morning. The draw is taken ONCE, here, and both
        -- ends of the window are derived from it: two spellings of the same arithmetic could give
        -- a fair that ends before it starts.
       cross join lateral (
         select v_season * k.season_game_days
                + floor(voyage.rng(p.id, v_season, 'buff-day:' || k.code)
                        * (k.season_game_days - k.duration_game_days)) as open_day
       ) d
       where p.kind = 'HARBOUR'  -- 0036: a fair is a market event; open water has no market
         and voyage.rng(p.id, v_season, 'buff:' || k.code) < k.chance_per_season
      on conflict do nothing;
      get diagnostics v_n = row_count;
      v_total := v_total + v_n;
    end if;

    -- A working set, not an archive.
    delete from public.active_buffs ab
     where ab.kind_code = k.code
       and ab.season is not null
       and ab.season <= v_season - public.wc_int('buff_history_seasons');
  end loop;

  return v_total;
end $$;

comment on function public.tick_buff_calendar(timestamptz) is
  'THE ONE writer of the calendar. Every fair it draws is a pure function of (port, season, the '
  'kind''s stream, the world secret), so it is idempotent by construction and identical on any '
  'replay. Wound by pg_cron where the platform has one and by world.buffs() where it does not — '
  'two callers, one definition of when a fair happens. Supersedes 0026:317 (0036): fairs are '
  'drawn at HARBOUR rows only — a fair is a market event, and open water has no market.';

revoke all on function public.tick_buff_calendar(timestamptz) from public, anon, authenticated;
grant execute on function public.tick_buff_calendar(timestamptz) to service_role;

-- ── 7. SUPERSEDES 0019:396 — the stores gate learns that open water has no chandler ────────────
-- Byte-identical for a HARBOUR destination (assert (c) puts the same questions to the kept 0019
-- body and to this one). For a SEA_PLACE destination the stores must cover the passage plus the
-- shortest sailed way BACK to a harbour: a destination where she cannot provision must never be
-- reachable on one-way stores, or the fleet is bricked at anchor for ever — the predecessor's
-- recorded empty-fleet deadlock, refused here at the quay where the fix (PROVISION) is one tap.
create or replace function voyage.sail_refusal(p_fleet uuid, p_dest uuid, p_nm numeric)
returns text
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  f        public.fleets%rowtype;
  v_short  int;
  v_flag   numeric;
  v_draft  int;
  v_maxd   int;
  v_speed  numeric;
  v_days   numeric;
  v_end    numeric;
  v_dkind  text;
  v_dname  text;
  v_esc_nm numeric;
begin
  select * into f from public.fleets where id = p_fleet;
  if f.id is null then
    return 'E_NO_SUCH_FLEET: there is no such fleet';
  end if;
  if f.status <> 'DOCKED' then
    return format('E_NOT_DOCKED: %s is %s and must be docked to sail', f.name, f.status);
  end if;

  -- Every ship must be able to leave and to arrive (DESIGN F.2 SAIL preconditions).
  select count(*) into v_short
    from public.ships s join public.ship_classes c on c.id = s.class_id
   where s.fleet_id = p_fleet and s.crew < c.crew_required;
  if v_short > 0 then
    return format('E_CREW_SHORT: %s ship(s) are below their required complement', v_short);
  end if;

  select coalesce(durability, 0) into v_flag from public.ships where fleet_id = p_fleet and is_flagship;
  if coalesce(v_flag, 0) <= 0 then
    return 'E_FLAGSHIP_DISABLED: the flagship cannot sail until it is repaired';
  end if;

  select max(c.draft) into v_draft from public.ships s join public.ship_classes c on c.id = s.class_id
   where s.fleet_id = p_fleet;
  select max_draft, kind, name into v_maxd, v_dkind, v_dname from public.ports where id = p_dest;
  if v_draft > v_maxd then
    return format('E_DRAFT: the deepest hull draws %s and that port takes %s', v_draft, v_maxd);
  end if;
  if (select is_ice_closed from public.ports where id = p_dest) then
    return 'E_PORT_CLOSED: that port is closed';
  end if;

  v_speed := voyage.fleet_speed(p_fleet);
  v_end   := voyage.endurance_days(p_fleet);

  -- 0036 SEA PLACE: no chandler out there, so the casks must cover the passage AND the shortest
  -- sailed way back to a harbour. Asked of voyage.reach_from — the one distance authority — and
  -- only for sea-place destinations, so a harbour run costs exactly what it cost under 0019.
  if v_dkind = 'SEA_PLACE' then
    select min(r.nm) into v_esc_nm
      from voyage.reach_from(p_dest) r
      join public.ports hp on hp.id = r.port_id
     where hp.kind = 'HARBOUR';
    if v_esc_nm is null then
      -- Unreachable while 0036's connectivity assert holds; spelt because the alternative is a
      -- division by a null a frame later, which is a message about nothing (NO_SPAGHETTI §7C).
      return format('E_NO_ROUTE: no harbour is reachable from %s', v_dname);
    end if;
    v_days := ((p_nm + v_esc_nm) / v_speed) / 24;
    if v_end < v_days * public.wc_num('endurance_margin') then
      return format('E_ENDURANCE: %s carries %s days of stores, and %s is open water with no chandler — the casks must cover the passage and the way back to harbour, %s voyage-days; you need %s — PROVISION first',
        f.name, round(v_end, 1), v_dname, round(v_days, 1), round(v_days * public.wc_num('endurance_margin'), 1));
    end if;
    return null;
  end if;

  v_days := (p_nm / v_speed) / 24;
  -- DESIGN C.5: "SAIL refuses to queue if endurance_days < leg_days x 1.15, and says so."
  if v_end < v_days * public.wc_num('endurance_margin') then
    return format('E_ENDURANCE: %s carries %s days of stores and that route is %s voyage-days; you need %s — PROVISION first',
      f.name, round(v_end, 1), round(v_days, 1), round(v_days * public.wc_num('endurance_margin'), 1));
  end if;
  return null;
end $$;

comment on function voyage.sail_refusal(uuid, uuid, numeric) is
  'THE one answer to "may this fleet sail there, right now?" — crew, flagship, draft, ice and '
  'endurance. cmd.do_sail RAISES what this returns and world.trade_routes REFUSES TO RECOMMEND '
  'what this refuses. Supersedes 0019:396 (0036): a SEA_PLACE destination requires stores for '
  'the passage PLUS the shortest sailed way back to a harbour, because open water has no '
  'chandler and a one-way trap is the recorded deadlock shape. Harbour destinations are '
  'byte-identical to 0019.';

revoke all on function voyage.sail_refusal(uuid, uuid, numeric) from public, anon, authenticated;

-- ── 8. THE SLICES — settle's arrival arm, the chandler guard, and the served kind ──────────────
-- 0034's slice-and-replace method: each hunk must occur EXACTLY ONCE in the deployed body (or
-- this file was generated against a different deployment and must not guess), and the reverse
-- substitution must reproduce the pre-image byte-for-byte (so nothing else moved).
do $$
declare
  r     record;
  v_new text;
  v_back text;
  v_n   int;
  h     jsonb;
  hunks constant jsonb := jsonb_build_array(
    -- S1 — voyage.settle, the arrival arm. Anchored on the fleets-docking update plus the report
    -- emit, which occur adjacent exactly once. The LANDFALL is written BEFORE the emit so the
    -- report's last line is the landfall; its day sits past every settled checkpoint so the PK
    -- cannot collide with a hazard; resolved_at is the deterministic ETA, never now(); and the
    -- same ON CONFLICT keeps settle idempotent, re-entry and all.
    jsonb_build_object('fn', 'voyage.settle',
      'old', $s1$     where id = p_fleet;
    perform public.emit_event(f.player_id, 'VOYAGE_REPORT', jsonb_build_object($s1$,
      'new', $s2$     where id = p_fleet;
    -- 0036 SEA PLACE: landfall in open water is an EVENT — the only thing that is out there.
    insert into public.voyage_events (voyage_id, day_index, kind, payload, resolved_at)
    select v.id, voyage.total_days(v.id) + 1, 'LANDFALL',
           jsonb_build_object('place', sp.name, 'remark', sp.approach), v.eta
      from public.ports sp
     where sp.id = v.dest_port_id and sp.kind = 'SEA_PLACE'
    on conflict (voyage_id, day_index) do nothing;
    perform public.emit_event(f.player_id, 'VOYAGE_REPORT', jsonb_build_object($s2$),
    -- P1 — cmd.do_provision. Without this the flat provision knobs would happily sell fresh
    -- water in the middle of the Sargasso: a lie with a price on it. The standing order (0034)
    -- composes do_provision, so at a sea place it writes its PROVISION_REFUSED ledger line with
    -- this code — visible, true, and once per arrival.
    jsonb_build_object('fn', 'cmd.do_provision',
      'old', $p1$    raise exception 'E_NOT_DOCKED: % is % and must be docked to take on stores', f.name, f.status using errcode = 'P0001';
  end if;$p1$,
      'new', $p2$    raise exception 'E_NOT_DOCKED: % is % and must be docked to take on stores', f.name, f.status using errcode = 'P0001';
  end if;
  -- 0036 SEA PLACE: there is no chandler in open water.
  if exists (select 1 from public.ports sp where sp.id = f.port_id and sp.kind = 'SEA_PLACE') then
    raise exception 'E_NO_CHANDLER: % lies at %, open water — there is no chandler; stores are bought in harbour',
      f.name, (select sp.name from public.ports sp where sp.id = f.port_id) using errcode = 'P0001';
  end if;$p2$),
    -- W1 — world.snapshot's ports[]: the client is told which places have a quay instead of
    -- having to invent it, and the approach line rides along for the anchorage view.
    jsonb_build_object('fn', 'world.snapshot',
      'old', $w1$        'has_yard', p.has_yard, 'yard_tier', p.yard_tier, 'has_academy', p.has_academy,$w1$,
      'new', $w2$        'has_yard', p.has_yard, 'yard_tier', p.yard_tier, 'has_academy', p.has_academy,
        'kind', p.kind, 'approach', p.approach,$w2$));
begin
  for r in select fn, def from defs_before_0036 where fn in ('voyage.settle', 'cmd.do_provision', 'world.snapshot') loop
    v_new := r.def;
    for h in select * from jsonb_array_elements(hunks) loop
      continue when h->>'fn' <> r.fn;
      v_n := (length(v_new) - length(replace(v_new, h->>'old', ''))) / length(h->>'old');
      if v_n <> 1 then
        raise exception '0036: hunk for % occurs % time(s) in the deployed body — expected exactly 1; the deployed body is not what this migration was generated against', r.fn, v_n;
      end if;
      v_new := replace(v_new, h->>'old', h->>'new');
    end loop;
    execute v_new;

    -- Reverse-substitution parity: undoing the hunks must give back the pre-image exactly.
    v_back := v_new;
    for h in select * from jsonb_array_elements(hunks) loop
      continue when h->>'fn' <> r.fn;
      v_back := replace(v_back, h->>'new', h->>'old');
    end loop;
    if v_back is distinct from r.def then
      raise exception '0036: reverse-substituting the % hunks does not reproduce the pre-image — something beyond the hunks moved', r.fn;
    end if;
  end loop;
end $$;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_probe    constant uuid := '00000000-0036-4000-8000-000000000001';
  v_pre      record;
  v_places   int;
  v_legs_new int;
  v_n        int;
  v_bad      int;
  v_lis      uuid;
  v_place    uuid;
  v_pcode    text;
  v_pname    text;
  v_remark   text;
  v_home     uuid;
  v_player   uuid;
  v_fleet    uuid;
  v_nodes    uuid[];
  v_nm       numeric;
  v_esc      numeric;
  v_refuse   text;
  v_refuse2  text;
  v_voyage   uuid;
  v_eta      timestamptz;
  v_days     int;
  v_events0  int;
  v_events1  int;
  v_line     text;
  v_report   jsonb;
  v_acl0     text;
  v_acl1     text;
  v_snap     jsonb;
  v_old_snap jsonb;
  v_kseason  int;
  v_kcode    text;
  v_kts      timestamptz;
  v_expect   int;
  s          int;
  kk         record;
  f_deltas   boolean := false;  f_graph    boolean := false;
  f_noop     boolean := false;  f_reserve  boolean := false;
  f_sail     boolean := false;  f_landfall boolean := false;
  f_chandler boolean := false;  f_hire     boolean := false;
  f_home     boolean := false;  f_idem     boolean := false;
  f_fair     boolean := false;  f_trigger  boolean := false;
  f_snapshot boolean := false;  f_posture  boolean := false;
begin
  select * into v_pre from pre_0036;

  ---------------------------------------------------------------------------------------------
  -- (a) DELTAS, against the counts captured before the inserts — never absolute totals.
  ---------------------------------------------------------------------------------------------
  select count(*) into v_places from public.ports where kind = 'SEA_PLACE';
  select (select count(*) from public.ports) - v_pre.ports,
         (select count(*) from public.legs)  - v_pre.legs
    into v_n, v_legs_new;
  if v_places = ${places.length} and v_n = ${places.length} and v_legs_new = ${legRows.length}
     and (select count(*) from public.voyage_event_kinds) = v_pre.kinds + 1 then
    f_deltas := true;
  end if;
  if not f_deltas then
    raise exception '0036 self-assert FAIL: expected +${places.length} sea places, +${legRows.length} legs and +1 event kind over the pre-image; got % places (+% ports), +% legs, % kinds against %',
      v_places, v_n, v_legs_new, (select count(*) from public.voyage_event_kinds), v_pre.kinds;
  end if;

  ---------------------------------------------------------------------------------------------
  -- (b) THE GRAPH: >=2 legs per place; EVERY leg in the world >= its great circle; still ONE
  --     component from Lisboa; every sea place settled by reach_from(Lisboa) at a finite nm.
  ---------------------------------------------------------------------------------------------
  select count(*) into v_bad
    from public.ports p
   where p.kind = 'SEA_PLACE'
     and (select count(*) from public.legs l where l.from_port_id = p.id or l.to_port_id = p.id) < 2;
  if v_bad <> 0 then
    raise exception '0036 self-assert FAIL: % sea place(s) have fewer than 2 legs — a place with one road is a trap', v_bad;
  end if;
  select count(*) into v_bad
    from public.legs l
    join public.ports a on a.id = l.from_port_id
    join public.ports b on b.id = l.to_port_id
   where l.distance_nm < voyage.gc_distance_nm(a.lat, a.lon, b.lat, b.lon) - 0.0001;
  if v_bad <> 0 then
    raise exception '0036 self-assert FAIL: % leg(s) are SHORTER than the great circle between their ends — a leg may detour round land, never cut through it', v_bad;
  end if;
  select id into v_lis from public.ports where code = 'LIS';
  with recursive reached(id) as (
      select v_lis
    union
      select case when l.from_port_id = r.id then l.to_port_id else l.from_port_id end
        from reached r join public.legs l on l.from_port_id = r.id or l.to_port_id = r.id
  )
  select count(*) into v_n from reached;
  if v_n <> (select count(*) from public.ports) then
    raise exception '0036 self-assert FAIL: only % of % ports (harbours + sea places) are reachable from Lisboa', v_n, (select count(*) from public.ports);
  end if;
  select count(*) into v_n
    from public.ports p
    join voyage.reach_from(v_lis) r on r.port_id = p.id and r.nm > 0
   where p.kind = 'SEA_PLACE';
  if v_n <> ${places.length} then
    raise exception '0036 self-assert FAIL: reach_from(Lisboa) settles % of ${places.length} sea places', v_n;
  end if;
  f_graph := true;

  ---------------------------------------------------------------------------------------------
  -- (c) + (d) THE WIRING, on a real house — rolled back at the foot.
  ---------------------------------------------------------------------------------------------
  begin
    -- The subject is FOUND, deterministically: the sea place nearest Lisboa by sailed distance.
    select p.id, p.code, p.name, p.approach into v_place, v_pcode, v_pname, v_remark
      from public.ports p
      join voyage.reach_from(v_lis) r on r.port_id = p.id
     where p.kind = 'SEA_PLACE'
     order by r.nm, p.code
     limit 1;

    v_player := public.new_house(c_probe, 'Casa do Mar Alto', 'PRT');
    select id into v_fleet from public.fleets where player_id = v_player;

    v_nodes := voyage.route(v_lis, v_place);
    select sum((e->>'nm')::numeric) into v_nm from jsonb_array_elements(voyage.path_from_nodes(v_nodes)) e;

    -- (c) THE NO-OP for a harbour destination: the kept 0019 body and the new one must answer
    -- identically — same nulls, same sentences — for the fresh fleet against a real harbour run.
    select r.port_id into v_home from voyage.reach_from(v_lis) r
      join public.ports hp on hp.id = r.port_id and hp.kind = 'HARBOUR'
     order by r.nm, r.port_id limit 1;
    select r.nm into v_esc from voyage.reach_from(v_lis) r where r.port_id = v_home;
    if voyage.sail_refusal(v_fleet, v_home, v_esc) is distinct from voyage.sail_refusal_0019_probe(v_fleet, v_home, v_esc)
       or voyage.sail_refusal(v_fleet, v_home, 99999) is distinct from voyage.sail_refusal_0019_probe(v_fleet, v_home, 99999) then
      raise exception '0036 self-assert FAIL: sail_refusal answers a HARBOUR destination differently from its 0019 pre-image — the supersede is not a no-op where it promised to be';
    end if;
    f_noop := true;

    -- (c) THE RESERVE BITES. THE PROBE SETS ITS OWN PRECONDITION: a fresh Barca happens to
    -- carry roughly a round trip's stores for the NEAREST place (measured — the first cut of
    -- this assert passed vacuously on exactly that), so the casks are set to hold the one-way
    -- passage with margin and NOT the way back. The 0019 body must then still say YES — which
    -- is the recorded deadlock: she sails, arrives, and can neither provision nor leave — and
    -- the superseding body must say NO, naming the missing chandler.
    update public.ships s
       set water_t = round(s.crew * public.wc_num('water_per_crew_day')
                     * ((v_nm / voyage.fleet_speed(v_fleet)) / 24 * public.wc_num('endurance_margin') + 0.3), 3),
           food_t  = round(s.crew * public.wc_num('food_per_crew_day')
                     * ((v_nm / voyage.fleet_speed(v_fleet)) / 24 * public.wc_num('endurance_margin') + 0.3), 3)
     where s.fleet_id = v_fleet;
    if voyage.sail_refusal_0019_probe(v_fleet, v_place, v_nm) is not null then
      raise exception '0036 self-assert FAIL: the 0019 gate refused the one-way stores fixture [%] — the reserve assert below would not be testing the NEW clause at all',
        voyage.sail_refusal_0019_probe(v_fleet, v_place, v_nm);
    end if;
    v_refuse := voyage.sail_refusal(v_fleet, v_place, v_nm);
    if v_refuse like 'E_ENDURANCE%' and v_refuse like '%no chandler%' then
      -- and the SAME fleet, provisioned and crewed, passes the same gate.
      perform cmd.do_provision(v_fleet, jsonb_build_object('mode', 'FULL'));
      perform cmd.do_hire(v_fleet, jsonb_build_object('count',
        (select c.crew_max - sh.crew from public.ships sh
           join public.ship_classes c on c.id = sh.class_id where sh.fleet_id = v_fleet)));
      v_refuse2 := voyage.sail_refusal(v_fleet, v_place, v_nm);
      if v_refuse2 is null then f_reserve := true; end if;
    end if;
    if not f_reserve then
      raise exception '0036 self-assert FAIL: the round-trip stores gate did not behave — dry fleet said [%], provisioned fleet said [%]', v_refuse, coalesce(v_refuse2, '(null)');
    end if;

    -- (d) SAIL THERE, ARRIVE, AND READ THE REPORT.
    perform cmd.do_sail(v_fleet, jsonb_build_object('dest', v_place));
    select id, eta into v_voyage, v_eta from public.voyages where fleet_id = v_fleet and status = 'SAILING';
    perform voyage.settle(v_fleet, v_eta + interval '1 second');

    if (select status from public.fleets where id = v_fleet) = 'DOCKED'
       and (select port_id from public.fleets where id = v_fleet) = v_place then
      f_sail := true;
    end if;
    if not f_sail then
      raise exception '0036 self-assert FAIL: after settling past the ETA the fleet is % at % — she should be lying at %',
        (select status from public.fleets where id = v_fleet),
        (select coalesce(p.code, '(nowhere)') from public.fleets fl left join public.ports p on p.id = fl.port_id where fl.id = v_fleet),
        v_pcode;
    end if;

    v_days := voyage.total_days(v_voyage);
    select count(*) into v_n from public.voyage_events where voyage_id = v_voyage and kind = 'LANDFALL';
    select voyage.report_line(ve.day_index, ve.kind, ve.payload) into v_line
      from public.voyage_events ve where ve.voyage_id = v_voyage and ve.kind = 'LANDFALL';
    if v_n = 1
       and v_line = format('Day %s. We raised %s and hove to. %s', v_days + 1, v_pname, v_remark)
       and exists (select 1 from public.events e
                    where e.player_id = v_player and e.kind = 'VOYAGE_REPORT'
                      and e.payload->'lines'->>(jsonb_array_length(e.payload->'lines') - 1) = v_line) then
      f_landfall := true;
    end if;
    if not f_landfall then
      raise exception '0036 self-assert FAIL: expected exactly one LANDFALL whose line is the report''s last — got % row(s), line [%]', v_n, coalesce(v_line, '(none)');
    end if;

    -- Idempotence, the 0007 rule: three more settles move nothing.
    select count(*) into v_events0 from public.voyage_events where voyage_id = v_voyage;
    perform voyage.settle(v_fleet, v_eta + interval '1 hour');
    perform voyage.settle(v_fleet, v_eta + interval '2 hours');
    perform voyage.settle(v_fleet, v_eta + interval '3 hours');
    select count(*) into v_events1 from public.voyage_events where voyage_id = v_voyage;
    if v_events0 = v_events1 then f_idem := true; end if;
    if not f_idem then
      raise exception '0036 self-assert FAIL: re-settling an arrived voyage grew its events % -> %', v_events0, v_events1;
    end if;

    -- (d) THE SHORE VERBS REFUSE, in their own words — real reds, not prose.
    begin
      perform cmd.do_provision(v_fleet, jsonb_build_object('mode', 'FULL'));
    exception when others then
      if sqlerrm like 'E_NO_CHANDLER%' and sqlerrm like '%' || v_pname || '%' then f_chandler := true; end if;
    end;
    if not f_chandler then
      raise exception '0036 self-assert FAIL: PROVISION at % was not refused E_NO_CHANDLER — the game just sold fresh water on the open sea', v_pname;
    end if;
    -- One berth is opened first: the probe hired to FULL at Lisboa, so E_CREW_MAX would fire
    -- before the pool was ever consulted and this assert would test the wrong refusal.
    update public.ships set crew = crew - 1 where fleet_id = v_fleet;
    begin
      perform cmd.do_hire(v_fleet, jsonb_build_object('count', 1));
    exception when others then
      if sqlerrm like 'E_CREW_POOL%' then f_hire := true; end if;
    end;
    if not f_hire then
      raise exception '0036 self-assert FAIL: HIRE at a sea place was not refused E_CREW_POOL';
    end if;

    -- (d) AND SHE SAILS HOME on the reserve the gate forced her to carry.
    perform cmd.do_sail(v_fleet, jsonb_build_object('dest', v_home));
    if (select status from public.fleets where id = v_fleet) = 'SAILING' then f_home := true; end if;
    if not f_home then
      raise exception '0036 self-assert FAIL: the fleet could not leave % — the reserve rule did not actually keep her free', v_pname;
    end if;

    ---------------------------------------------------------------------------------------------
    -- (e) THE FAIR CALENDAR — find, deterministically, a (kind, season) whose UNFILTERED draw
    -- would put a fair at a sea place; wind the calendar there; assert the harbour draws landed
    -- and the sea-place draw did not. Then show the table trigger biting on a direct insert.
    ---------------------------------------------------------------------------------------------
    v_kseason := null;
    <<hunt>>
    for s in 0 .. 400 loop
      for kk in select * from public.buff_kinds where season_game_days is not null and subject_kind = 'PORT' order by code loop
        if exists (select 1 from public.ports p where p.kind = 'SEA_PLACE'
                    and voyage.rng(p.id, s, 'buff:' || kk.code) < kk.chance_per_season) then
          v_kseason := s; v_kcode := kk.code;
          v_kts := to_timestamp((s * kk.season_game_days * public.wc_num('game_day_seconds'))::double precision);
          exit hunt;
        end if;
      end loop;
    end loop;
    if v_kseason is null then
      raise exception '0036 self-assert FAIL: no (kind, season) in 400 seasons would draw a fair at any sea place — the filter assert below would be VACUOUS, which is worse than red';
    end if;
    delete from public.active_buffs where season = v_kseason and kind_code = v_kcode;
    perform public.tick_buff_calendar(v_kts);
    select count(*) into v_expect
      from public.ports p, public.buff_kinds k
     where k.code = v_kcode and p.kind = 'HARBOUR'
       and voyage.rng(p.id, v_kseason, 'buff:' || k.code) < k.chance_per_season;
    select count(*) into v_n from public.active_buffs ab
      join public.ports p on p.id = ab.subject_id
     where ab.season = v_kseason and ab.kind_code = v_kcode and p.kind = 'HARBOUR';
    select count(*) into v_bad from public.active_buffs ab
      join public.ports p on p.id = ab.subject_id
     where p.kind = 'SEA_PLACE';
    if v_bad = 0 and v_n = v_expect and v_expect > 0 then f_fair := true; end if;
    if not f_fair then
      raise exception '0036 self-assert FAIL: season % of % drew % harbour fair(s) (expected %) and % at sea places (expected 0) — the calendar filter is not doing what it claims',
        v_kseason, v_kcode, v_n, v_expect, v_bad;
    end if;
    begin
      insert into public.active_buffs (kind_code, subject_id, season, starts_at, ends_at, source)
      values (v_kcode, v_place, 999999, now(), now() + interval '1 day', 'calendar');
    exception when others then
      if sqlerrm like 'E_NO_QUAY%' then f_trigger := true; end if;
    end;
    if not f_trigger then
      raise exception '0036 self-assert FAIL: a fair was WRITTEN at % — the buff_needs_a_quay trigger is not standing', v_pname;
    end if;

    raise exception 'ROLLBACK_0036_PROBE';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0036_PROBE' then raise; end if;
  end;

  -- The probe rolled all the way back.
  select count(*) into v_n from public.players pl where pl.auth_uid = c_probe;
  if v_n <> 0 then
    raise exception '0036 self-assert FAIL: % probe house(s) survived the subtransaction', v_n;
  end if;

  ---------------------------------------------------------------------------------------------
  -- (f) THE SNAPSHOT: old payload + the two new fields + the new rows; nothing else moved.
  ---------------------------------------------------------------------------------------------
  v_snap := world.snapshot();
  v_old_snap := v_pre.snapshot;
  if (v_snap - 'ports' - 'legs') = (v_old_snap - 'ports' - 'legs')
     and (select jsonb_agg(p - 'kind' - 'approach' order by p->>'code')
            from jsonb_array_elements(v_snap->'ports') p
           where p->>'kind' = 'HARBOUR')
         = (select jsonb_agg(p order by p->>'code') from jsonb_array_elements(v_old_snap->'ports') p)
     and (select count(*) from jsonb_array_elements(v_snap->'ports') p
           where p->>'kind' = 'SEA_PLACE' and (p->>'approach') is not null) = ${places.length}
     and jsonb_array_length(v_snap->'legs') = jsonb_array_length(v_old_snap->'legs') + ${legRows.length} then
    f_snapshot := true;
  end if;
  if not f_snapshot then
    raise exception '0036 self-assert FAIL: world.snapshot() is not the old payload plus kind/approach plus the new rows — something else about the wire moved';
  end if;

  ---------------------------------------------------------------------------------------------
  -- (g) POSTURE: ACLs unchanged, weights still close, LANDFALL never rolled, read wall zero.
  ---------------------------------------------------------------------------------------------
  select count(*) into v_bad from defs_before_0036 d
   where d.acl is distinct from (
     select p.proacl::text from pg_proc p
      where p.oid = (case d.fn
        when 'voyage.settle' then 'voyage.settle(uuid, timestamptz)'
        when 'cmd.do_provision' then 'cmd.do_provision(uuid, jsonb)'
        when 'world.snapshot' then 'world.snapshot()'
        when 'voyage.sail_refusal' then 'voyage.sail_refusal(uuid, uuid, numeric)'
        when 'public.tick_buff_calendar' then 'public.tick_buff_calendar(timestamptz)'
      end)::regprocedure);
  if v_bad = 0
     and (select coalesce(sum(roll_weight), 0) from public.voyage_event_kinds where is_rolled) = 1
     and not (select is_rolled from public.voyage_event_kinds where code = 'LANDFALL')
     and (select count(*) from public.client_write_grants()) = 0
     and (select count(*) from public.client_executable_writers()) = 0
     and (select count(*) from public.client_rpc_entry_points() e where e.fn is null) = 0
     and (select count(*) from public.caller_evaluated_functions()) = 0 then
    f_posture := true;
  end if;
  if not f_posture then
    raise exception '0036 self-assert FAIL: the posture moved — an ACL changed (% of 5), the rolled weights no longer close, LANDFALL is rolled, or a read-wall authority no longer reads zero', v_bad;
  end if;

  raise notice '0036 self-assert ok: THE SEA HAS PLACES IN IT — % named waters landed as ports rows (kind SEA_PLACE) with % sailed spur legs, every leg in the world still >= its great circle, the graph is still one piece from Lisboa and reach_from settles every place; sail_refusal answers harbour runs byte-identically to its kept 0019 body and refused a one-way trip to a sea place until the same fleet provisioned for the round trip; a real house then sailed Lisboa -> % (% nm), settled at her ETA, lay DOCKED at the place with exactly ONE LANDFALL whose line is the report''s last — and three re-settles moved nothing; PROVISION there was refused E_NO_CHANDLER and HIRE E_CREW_POOL, and she sailed home on the reserve the gate forced aboard; the fair calendar wound over a season that WOULD have drawn a sea-place fair drew all % harbour fairs and none at sea, and the buff_needs_a_quay trigger rejected a direct write; the snapshot is the old payload plus kind/approach plus the new rows; ACLs unchanged, weights closed, 0 client write grants, 0 read-wall gaps',
    ${places.length}, ${legRows.length}, v_pcode, round(v_nm), v_expect;
end $$;

drop function voyage.sail_refusal_0019_probe(uuid, uuid, numeric);
drop table pre_0036;
drop table defs_before_0036;
`

if (sql.includes('\r')) throw new Error('CRLF leaked into the generated migration — refuse to emit')
writeFileSync(OUT, sql, 'utf8')
console.log(`\nwrote ${OUT.replace(ROOT, '.')}`)
console.log(`  ${places.length} sea places · ${legRows.length} spur legs`)
for (const p of places) {
  const esc = escapes.get(p.code)
  console.log(`  ${p.code} ${p.name.padEnd(22)} escape: ${esc.code} ${esc.nm} nm`)
}
