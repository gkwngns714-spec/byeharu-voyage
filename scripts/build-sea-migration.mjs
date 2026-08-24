// ═══════════════════════════════════════════════════════════════════════════════════════════════
// build-sea-migration.mjs — writes migration 0046: THE NAVIGABLE SEA, AS DATA.
//
// §7B — the four questions:
//   CONCEPT      "the one statement of what water connects to what": the navigable raster, and
//                the sailed distance between every pair of places, derived FROM that raster by
//                the one pathfinder (src/lib/sea).
//   LIVES HERE   scripts/, because it is a GENERATOR: it runs the applied chain in PGlite to read
//                the world's own ports (codes and coordinates come from the database, never from
//                a second derivation of them), computes, and emits SQL. The AUTHORITY it emits is
//                the migration; after 0046 applies, the raster row IS the sea.
//   SECOND CALLER  none — it is run by hand when the sea or the ports change, and then a NEW
//                migration is cut (never an edit of an applied one). scripts/build-proof-paths.mjs
//                consumes the same src/lib/sea search, not this file.
//   WRONG SHAPE  if the raster it packs and the raster a browser unpacks could differ. They
//                cannot: both sides are src/lib/sea/grid.ts, and 0046's own self-assert round-
//                trips get_bit() against embedded control cells.
//
// THE NAV RULE, stated once, here, where the raster is made:
//   navigable = buildSeaGrid()            (Natural Earth land, scan-filled; CHANNELS forced open;
//                                          the Arctic ICE closures of scripts/sea-grid.mjs)
//               minus everything south of 60°S   (the Antarctic pack — the age of sail rounded
//                                          Cape Horn at ~56°S; nothing sailed the pack ice)
//
// THE MASK (2 bits per cell — passability is a property of (water, ship), coordinator 2026-08-24):
//   bit 0  SEA    sailable water. The LAW gates on this alone today.
//   bit 1  POLAR  the polar margin: OPEN water poleward of 66.5°N or 55°S — the Barents/White Sea
//                 road, Svalbard's grounds, the sub-Antarctic fringe. Data for the later region /
//                 ice-capability systems; it does not gate passage (no hull carries a capability
//                 yet, and an ungatable gate would close Arkhangelsk to everyone — §7C).
//
// Run:  node scripts/build-sea-migration.mjs        (applies the chain first; takes minutes)
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { writeFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import path from 'node:path'
import { buildSeaGrid, COLS, ROWS, CELL_DEG, cellLat } from './sea-grid.mjs'
import { packCells, findPath, floodFrom, floodPathTo, gcNm, SEA_BIT, POLAR_BIT } from '../src/lib/sea/index.ts'
import { applyChain, MIGRATIONS_DIR } from './db/apply-chain.mjs'

const OUT = path.join(MIGRATIONS_DIR, '20260818000046_the_water_knows_the_way.sql')
const BITS = 2

// ── 1. The navigable grid ──────────────────────────────────────────────────────────────────────
console.log('building the navigable grid…')
const cells = buildSeaGrid()
for (let row = 0; row < ROWS; row++) {
  if (cellLat(row) < -60) cells.fill(0, row * COLS, row * COLS + COLS)
}
const nav = { cols: COLS, rows: ROWS, cellDeg: CELL_DEG, cells }
const masks = new Uint8Array(COLS * ROWS)
for (let row = 0; row < ROWS; row++) {
  const lat = cellLat(row)
  const polar = lat > 66.5 || lat < -55
  for (let col = 0; col < COLS; col++) {
    const i = row * COLS + col
    if (cells[i]) masks[i] = SEA_BIT | (polar ? POLAR_BIT : 0)
  }
}
const packed = packCells(masks, BITS)
const b64 = Buffer.from(packed).toString('base64')
const polarCells = masks.reduce((n, m) => n + ((m & POLAR_BIT) ? 1 : 0), 0)
console.log(`  ${COLS}×${ROWS} cells × ${BITS} bits, ${packed.length} bytes packed, ${b64.length} chars base64, ${polarCells} polar-margin cells`)

// ── 2. The world's own places, from the applied chain ──────────────────────────────────────────
console.log('applying the chain to read the ports…')
const { db } = await applyChain({ quiet: true })
const ports = (
  await db.query(`select code, name, kind, lat::float8 as lat, lon::float8 as lon
                    from public.ports order by code`)
).rows
console.log(`  ${ports.length} places (${ports.filter((p) => p.kind === 'HARBOUR').length} harbours)`)

// ── 3. All-pairs sailed distances: one flood per place ─────────────────────────────────────────
console.log('flooding the ocean from every place…')
const t0 = performance.now()
const reaches = new Map() // code -> Map(code -> nm)
const snapNm = new Map() // code -> nm from the true coordinate to sailable water
for (const p of ports) reaches.set(p.code, new Map())

// ── CROSS-CHECK against 0040's sea-membership raster (public.sea_cells) ────────────────────────
// The chain applied above includes 0040, so the membership bytes are readable right here. Rules:
//   * every navigable cell REACHABLE from the port network must carry a sea (a reachable cell
//     with byte 0 means the two rasters genuinely disagree — refuse to emit);
//   * unreachable navigable water with no sea is the KNOWN landlocked-pool set (Caspian and
//     friends) — counted and printed, never silently;
//   * membership on water this mask CLOSES must lie south of 60°S (the Antarctic pack rule is
//     this file's own; 0040 names those waters, this file forbids sailing them — that is a
//     division of labour, not a disagreement) or on the ice closures sea-grid already shares.
{
  const seaRows = (
    await db.query('select row_idx, seas from public.sea_cells order by row_idx')
  ).rows
  if (seaRows.length !== ROWS) throw new Error(`sea_cells has ${seaRows.length} rows, expected ${ROWS} — is 0040 applied?`)
  const membership = new Uint8Array(COLS * ROWS)
  for (const r of seaRows) membership.set(r.seas, r.row_idx * COLS)
  // reachable set: BFS over the navigable mask from the first port's water cell
  const seed = ports[0]
  const seedFlood = floodFrom(nav, seed)
  if (!seedFlood) throw new Error(`${seed.code}: no sailable water for the cross-check seed`)
  const reachable = seedFlood.seen // 2 = closed (reached)
  let pools = 0
  const wounds = []
  for (let i = 0; i < COLS * ROWS; i++) {
    if (!cells[i]) continue
    if (membership[i] > 0) continue
    if (reachable[i] === 2) {
      const row = (i / COLS) | 0
      const col = i - row * COLS
      wounds.push(`(${(90 - (row + 0.5) * CELL_DEG).toFixed(2)}, ${(-180 + (col + 0.5) * CELL_DEG).toFixed(2)})`)
    } else pools++
  }
  if (wounds.length > 0) {
    throw new Error(
      `REACHABLE water with NO sea (${wounds.length} cell(s)) — public.sea_cells (0040) and this ` +
        `raster disagree about the ocean itself: ${wounds.slice(0, 12).join(', ')}`,
    )
  }
  let southless = 0
  const northWounds = []
  for (let i = 0; i < COLS * ROWS; i++) {
    if (cells[i] || membership[i] === 0) continue
    const row = (i / COLS) | 0
    const lat = 90 - (row + 0.5) * CELL_DEG
    if (lat < -60) southless++
    else northWounds.push(`(${lat.toFixed(2)}, ${(-180 + ((i - row * COLS) + 0.5) * CELL_DEG).toFixed(2)})`)
  }
  if (northWounds.length > 0) {
    throw new Error(
      `sea-membership on water this mask closes NORTH of 60°S (${northWounds.length} cell(s)) — ` +
        `the two rasters disagree outside the Antarctic rule: ${northWounds.slice(0, 12).join(', ')}`,
    )
  }
  console.log(
    `  cross-check vs public.sea_cells (0040): every reachable navigable cell carries a sea; ` +
      `${pools} unreachable pool cell(s) carry none (Caspian and friends); ` +
      `${southless} named-but-closed cell(s), all south of 60°S (the Antarctic pack rule)`,
  )
}

for (let i = 0; i < ports.length; i++) {
  const a = ports[i]
  const flood = floodFrom(nav, a)
  if (!flood) throw new Error(`${a.code} ${a.name}: no sailable water within reach of its coordinate`)
  snapNm.set(a.code, flood.source.snapNm)
  for (let j = i + 1; j < ports.length; j++) {
    const b = ports[j]
    const r = floodPathTo(flood, a, b)
    if (!r) continue // recorded and refused below if it leaves anything unreachable
    reaches.get(a.code).set(b.code, r.nm)
    reaches.get(b.code).set(a.code, r.nm)
  }
  if ((i + 1) % 25 === 0) console.log(`  ${i + 1}/${ports.length} floods…`)
}
console.log(`  floods done in ${((performance.now() - t0) / 1000).toFixed(0)} s`)

// Every place must reach every other place, or the world has an island nobody can sail to. That
// is a GENERATION failure — fix the raster or the port — never something to ship quietly.
const unreachable = []
for (const a of ports) {
  for (const b of ports) {
    if (a.code !== b.code && !reaches.get(a.code).has(b.code)) unreachable.push(`${a.code}→${b.code}`)
  }
}
if (unreachable.length > 0) {
  throw new Error(`unreachable pairs (${unreachable.length}): ${unreachable.slice(0, 20).join(', ')}`)
}

// ── 4. The fixtures 0046 embeds for its own asserts ────────────────────────────────────────────
const byName = (...names) => {
  const p = ports.find((x) => names.includes(x.name))
  if (!p) throw new Error(`no port named ${names.join(' / ')}`)
  return p
}
const LIS = byName('Lisbon', 'Lisboa')
const CAD = byName('Cadiz', 'Cádiz')
const NAG = byName('Nagasaki')
const ALX = byName('Alexandria')
const ADE = byName('Aden')
const VER = byName('Veracruz')
const ACA = byName('Acapulco')
const BCN = byName('Barcelona')

// A real proposed water path, as a client would send one: Lisbon→Cádiz round Cape St Vincent.
const lisCad = findPath(nav, LIS, CAD)
if (!lisCad) throw new Error('no Lisbon→Cádiz path — the raster is broken')
const lisNagNm = reaches.get(LIS.code).get(NAG.code)
const alxAdeNm = reaches.get(ALX.code).get(ADE.code)
const verAcaNm = reaches.get(VER.code).get(ACA.code)
console.log(`  canal controls: ${ALX.code}→${ADE.code} ${Math.round(alxAdeNm)} nm round the Cape (no Suez); ` +
            `${VER.code}→${ACA.code} ${Math.round(verAcaNm)} nm round the Horn (no Panama)`)
console.log(`  the Arctic fix: ${LIS.code}→${NAG.code} ${Math.round(lisNagNm)} nm (the leg graph served 7,565)`)

// Control cells for the bit-order round trip: (name, lat, lon, expected 1/0).
const CONTROLS = [
  ['the mid-Atlantic', 30, -40, 1],
  ['the middle of Iberia', 39.5, -4.5, 0],
  ['the Bosphorus channel', 41.0, 29.0, 1],
  ['the Siberian arctic (ice)', 75, 120, 0],
  ['the Barents Sea (open — the Muscovy road)', 70, 40, 1],
  ['the Antarctic pack', -65, 0, 0],
  ['the South China Sea', 12, 112, 1],
  ['the Sahara', 23, 10, 0],
]
for (const [name, lat, lon, want] of CONTROLS) {
  const r = Math.min(ROWS - 1, Math.max(0, Math.floor((90 - lat) / CELL_DEG)))
  const c = ((Math.floor((lon + 180) / CELL_DEG) % COLS) + COLS) % COLS
  const got = cells[r * COLS + c]
  if (got !== want) throw new Error(`control cell "${name}" is ${got}, expected ${want}`)
}

const inland = [...snapNm.entries()].filter(([, nm]) => nm > 20).sort((a, b) => b[1] - a[1])
console.log(`  ${inland.length} places snap >20 nm to open water; worst: ` +
            inland.slice(0, 5).map(([c, n]) => `${c} ${Math.round(n)}`).join(', '))

// ── 5. Emit ────────────────────────────────────────────────────────────────────────────────────
const lines = []
const w = (s = '') => lines.push(s)
const q = (s) => `'${String(s).replace(/'/g, "''")}'`
const j = (x) => `'${JSON.stringify(x).replace(/'/g, "''")}'`

const pathJson = (p) => p.map(([lat, lon]) => [Number(lat.toFixed(4)), Number(lon.toFixed(4))])

w(`-- ═══════════════════════════════════════════════════════════════════════════════════════════════`)
w(`-- 0046 — THE WATER KNOWS THE WAY`)
w(`--        The navigable sea as ONE raster, the sailed distance between every pair of places`)
w(`--        derived from it, and the two primitives every free passage stands on: MEASURE a`)
w(`--        polyline, and REFUSE a polyline that touches land.`)
w(`-- ═══════════════════════════════════════════════════════════════════════════════════════════════`)
w(`--`)
w(`-- GENERATED by scripts/build-sea-migration.mjs — do not hand-edit. Change the sea (scripts/`)
w(`-- sea-grid.mjs) or the ports and cut a NEW migration; an applied one is history.`)
w(`--`)
w(`-- ── WHY (docs/NAVIGATION_PLAN.md, approved by the owner) ───────────────────────────────────────`)
w(`-- The game sailed a fixed graph of 782 precomputed legs, and the graph was measurably wrong:`)
w(`-- it routed Lisboa→Nagasaki over the North Pole at 88.6°N for 7,565 nm where the honest path`)
w(`-- is ${Math.round(lisNagNm).toLocaleString('en')} nm round the Cape of Good Hope. Every one of those numbers gated an endurance`)
w(`-- check and priced a trade route. The owner, three times: "it should go by sea without the`)
w(`-- fixed route — but fastest way possible." So the raster becomes the ONE source of what water`)
w(`-- connects to what, and 0047 replaces the graph-bound mover with a free one.`)
w(`--`)
w(`-- ── WHAT THIS FILE PUTS IN THE WORLD ───────────────────────────────────────────────────────────`)
w(`--   public.sea_raster    ${COLS}×${ROWS} cells at ${CELL_DEG}°, a ${BITS}-bit PASSABILITY MASK per cell,`)
w(`--                        packed LSB-first (get_bit numbering; cell i starts at bit i×${BITS}).`)
w(`--                        Bit 0 SEA = sailable (land from Natural Earth; CHANNELS forced open;`)
w(`--                        Arctic ICE closures; Antarctic pack south of 60°S). Bit 1 POLAR = the`)
w(`--                        open polar margin (>66.5°N / <55°S) — DATA for the region and ice-`)
w(`--                        capability systems to come; it gates nothing yet, and the migration`)
w(`--                        that gives it a reader must say so. Passability is a property of`)
w(`--                        (water, ship); ports keep max_draft, which answers BERTHING.`)
w(`--   public.sea_reaches   one row per place: the SAILED nm to every other place, computed by`)
w(`--                        the one pathfinder (src/lib/sea) over this very raster — Dijkstra`)
w(`--                        flood per source, path straightened by line-of-sight, measured as`)
w(`--                        the polyline's great-circle length. Plus snap_nm: how far the true`)
w(`--                        harbour coordinate sits from sailable water (a river port's approach).`)
w(`--   voyage.path_nm       THE measure of a polyline. The server never takes a client's distance.`)
w(`--   voyage.path_refusal  THE water-legality of a polyline: every segment sampled at half-cell`)
w(`--                        intervals against this raster, ends exempt only by a MEASURED approach`)
w(`--                        allowance. Returns the refusal sentence, or null for legal water.`)
w(`--`)
w(`-- ── THE CANAL CONTROLS, printed on every run ───────────────────────────────────────────────────`)
w(`--   There is no Suez and no Panama in 1550. Nothing encodes that: it falls out of the land.`)
w(`--   ${ALX.name}→${ADE.name} ${Math.round(alxAdeNm).toLocaleString('en')} nm round the Cape; ${VER.name}→${ACA.name} ${Math.round(verAcaNm).toLocaleString('en')} nm round the Horn.`)
w(`--`)
w(`-- ── WHAT IT DELIBERATELY DOES NOT DO ───────────────────────────────────────────────────────────`)
w(`--   * It does not touch public.legs or any mover — 0047 is the supersede; this file is data`)
w(`--     and two pure functions, so the chain stays green between the two.`)
w(`--   * It does not serve anything to a client — world.sea_raster() and the reach read arrive`)
w(`--     with the mover that needs them (0047).`)
w(`--`)
w(`-- Depends on: 0001 (schemas), 0002 (ports, gc_distance_nm), 0003/0036/0041 (the port rows —`)
w(`-- ten islands included), and 0040 (voyage.sea_at over public.sea_cells: the membership raster`)
w(`-- this passability raster is cross-checked against, at generation over every reachable cell`)
w(`-- and at apply on the named controls).`)
w(`-- ═══════════════════════════════════════════════════════════════════════════════════════════════`)
w()
w(`-- ── The raster ─────────────────────────────────────────────────────────────────────────────────`)
w(`create table if not exists public.sea_raster (`)
w(`  id            int primary key default 1 check (id = 1),`)
w(`  cols          int not null,`)
w(`  rows          int not null,`)
w(`  cell_deg      numeric not null,`)
w(`  bits_per_cell int not null,`)
w(`  -- a bits_per_cell-bit passability mask per cell, LSB-first: cell (row, col)'s mask starts at`)
w(`  -- bit (row*cols+col)*bits_per_cell, exactly get_bit()'s numbering. Bit 0 = SEA (sailable);`)
w(`  -- bit 1 = POLAR margin (no reader yet — see the header). Row 0 is the north edge (+90);`)
w(`  -- col 0 is the antimeridian (−180).`)
w(`  cells         bytea not null`)
w(`);`)
w()
// ONE literal, one line. The first cut chunked this into 2,880 concatenated 120-char literals
// for readability, and PGlite's exec silently stopped mid-file on the expression — a several-
// thousand-term || tree is a parser stress nobody needs. A single long token is boring and works.
w(`insert into public.sea_raster (id, cols, rows, cell_deg, bits_per_cell, cells)`)
w(`values (1, ${COLS}, ${ROWS}, ${CELL_DEG}, ${BITS}, decode('${b64}', 'base64'))`)
w(`on conflict (id) do nothing;`)
w()
w(`-- ── The sailed distances ───────────────────────────────────────────────────────────────────────`)
w(`create table if not exists public.sea_reaches (`)
w(`  port_id uuid primary key references public.ports(id) on delete cascade,`)
w(`  code    text not null unique,`)
w(`  -- great-circle nm from the port's true coordinate to the nearest sailable cell: the river or`)
w(`  -- estuary approach (Suez ${Math.round(snapNm.get(byName('Suez').code))} nm, Bristol ${Math.round(snapNm.get(byName('Bristol').code))} nm). INSIDE every reach figure below,`)
w(`  -- because each path starts and ends at the true coordinate — never silently skipped again.`)
w(`  snap_nm numeric not null,`)
w(`  -- { other_code: sailed_nm } for every other place in the world. Symmetric by construction`)
w(`  -- (one flood per pair, mirrored) and asserted below over the whole table.`)
w(`  reaches jsonb not null`)
w(`);`)
w()
w(`alter table public.sea_raster  enable row level security;`)
w(`alter table public.sea_reaches enable row level security;`)
w(`create policy sea_raster_read  on public.sea_raster  for select to authenticated using (true);`)
w(`create policy sea_reaches_read on public.sea_reaches for select to authenticated using (true);`)
w(`grant select on public.sea_raster, public.sea_reaches to authenticated;`)
w()
w(`insert into public.sea_reaches (port_id, code, snap_nm, reaches)`)
w(`select p.id, v.code, v.snap_nm::numeric, v.reaches::jsonb`)
w(`  from (values`)
{
  const rows = ports.map((p) => {
    const m = reaches.get(p.code)
    const obj = {}
    for (const [c, nm] of [...m.entries()].sort()) obj[c] = Number(nm.toFixed(1))
    return `    (${q(p.code)}, ${snapNm.get(p.code).toFixed(2)}, ${j(obj)})`
  })
  w(rows.join(',\n'))
}
w(`  ) as v(code, snap_nm, reaches)`)
w(`  join public.ports p on p.code = v.code`)
w(`on conflict (port_id) do nothing;`)
w()
w(`-- ── THE MEASURE. The server never takes a client's word for a distance. ────────────────────────`)
w(`create or replace function voyage.path_nm(p_path jsonb)`)
w(`returns numeric`)
w(`language sql`)
w(`stable`)
w(`security definer`)
w(`set search_path = public, pg_temp`)
w(`as $$`)
w(`  -- The polyline's own great-circle length, segment by segment, via THE distance authority`)
w(`  -- (voyage.gc_distance_nm, 0002). A path is [[lat, lon], …]; anything shorter than two points`)
w(`  -- measures 0 and the refusal function is what rejects it as a shape.`)
w(`  select coalesce(sum(voyage.gc_distance_nm(`)
w(`           (a.value->>0)::float8, (a.value->>1)::float8,`)
w(`           (b.value->>0)::float8, (b.value->>1)::float8)), 0)`)
w(`    from jsonb_array_elements(p_path) with ordinality a(value, i)`)
w(`    join jsonb_array_elements(p_path) with ordinality b(value, i) on b.i = a.i + 1`)
w(`$$;`)
w()
w(`revoke all on function voyage.path_nm(jsonb) from public, anon, authenticated;`)
w()
w(`-- ── THE LAW. A polyline is legal exactly when every sample of it is sailable water. ────────────`)
w(`create or replace function voyage.path_refusal(`)
w(`  p_path jsonb,`)
w(`  p_from_lat numeric, p_from_lon numeric,`)
w(`  p_to_lat   numeric, p_to_lon   numeric,`)
w(`  p_join_nm  numeric,      -- how far path[first]/path[last] may sit from the stated ends`)
w(`  p_head_nm  numeric,      -- measured approach allowance at the origin (its snap + one cell)`)
w(`  p_tail_nm  numeric       -- measured approach allowance at the destination`)
w(`)`)
w(`returns text`)
w(`language plpgsql`)
w(`stable`)
w(`security definer`)
w(`set search_path = public, pg_temp`)
w(`as $$`)
w(`-- Returns NULL for legal water, else the exact 'E_CODE: sentence' the mover raises. ONE reading`)
w(`-- of "may a ship be here", shared by cmd.do_sail, cmd.divert and the land-guard proof — a second`)
w(`-- sampler with a different step or allowance could disagree, which is the spaghetti this file`)
w(`-- exists to prevent.`)
w(`--`)
w(`-- THE SAMPLING RULE: each segment is walked at half-cell steps (≤ ${(CELL_DEG * 60 * 0.5).toFixed(1)} nm), linearly in`)
w(`-- lat/lon — the SAME interpolation voyage.position uses to place the ship, so the line judged`)
w(`-- is the line sailed. Samples inside the head/tail allowance of the path's FIRST/LAST point are`)
w(`-- exempt: a harbour sits ON the coast and its cell is usually land at this resolution; the`)
w(`-- allowance is the MEASURED snap of that harbour (sea_reaches.snap_nm), never a fixed guess.`)
w(`-- A segment jumping the antimeridian the long way (|Δlon| > 180) is refused: the pathfinder`)
w(`-- never emits one, and linear interpolation across it would sample water it does not cross.`)
w(`declare`)
w(`  r        public.sea_raster%rowtype;`)
w(`  v_n      int;`)
w(`  v_prev   jsonb := null;`)
w(`  v_seg    jsonb;`)
w(`  v_i      int := 0;`)
w(`  v_lat1   float8; v_lon1 float8; v_lat2 float8; v_lon2 float8;`)
w(`  v_nm     float8;`)
w(`  v_step   int;`)
w(`  v_s      int;`)
w(`  v_f      float8;`)
w(`  v_lat    float8; v_lon float8;`)
w(`  v_row    int; v_col int;`)
w(`  v_done   float8 := 0;`)
w(`  v_total  float8;`)
w(`begin`)
w(`  if p_path is null or jsonb_typeof(p_path) <> 'array' or jsonb_array_length(p_path) < 2 then`)
w(`    return 'E_BAD_PATH: a course is a list of at least two [lat, lon] points';`)
w(`  end if;`)
w(`  select * into r from public.sea_raster where id = 1;`)
w(`  v_n := jsonb_array_length(p_path);`)
w()
w(`  -- Every point is a finite coordinate on the sphere.`)
w(`  for v_i in 0 .. v_n - 1 loop`)
w(`    v_seg := p_path->v_i;`)
w(`    if jsonb_typeof(v_seg) <> 'array' or jsonb_array_length(v_seg) <> 2`)
w(`       or jsonb_typeof(v_seg->0) <> 'number' or jsonb_typeof(v_seg->1) <> 'number' then`)
w(`      return 'E_BAD_PATH: point ' || v_i || ' is not a [lat, lon] pair';`)
w(`    end if;`)
w(`    if abs((v_seg->>0)::float8) > 90 or abs((v_seg->>1)::float8) > 180 then`)
w(`      return 'E_BAD_PATH: point ' || v_i || ' is off the sphere';`)
w(`    end if;`)
w(`  end loop;`)
w()
w(`  -- The course must JOIN what it claims to join: its first point at the stated origin, its last`)
w(`  -- at the stated destination, within p_join_nm. Without this a legal-water path from anywhere`)
w(`  -- to anywhere could be attached to any order.`)
w(`  if voyage.gc_distance_nm(p_from_lat::float8, p_from_lon::float8,`)
w(`                           (p_path->0->>0)::float8, (p_path->0->>1)::float8) > p_join_nm then`)
w(`    return format('E_OFF_COURSE: the course begins %s nm from where she lies',`)
w(`      round(voyage.gc_distance_nm(p_from_lat::float8, p_from_lon::float8,`)
w(`                                  (p_path->0->>0)::float8, (p_path->0->>1)::float8)::numeric, 1));`)
w(`  end if;`)
w(`  if voyage.gc_distance_nm(p_to_lat::float8, p_to_lon::float8,`)
w(`                           (p_path->(v_n-1)->>0)::float8, (p_path->(v_n-1)->>1)::float8) > p_join_nm then`)
w(`    return format('E_OFF_COURSE: the course ends %s nm short of the destination',`)
w(`      round(voyage.gc_distance_nm(p_to_lat::float8, p_to_lon::float8,`)
w(`                                  (p_path->(v_n-1)->>0)::float8, (p_path->(v_n-1)->>1)::float8)::numeric, 1));`)
w(`  end if;`)
w()
w(`  v_total := voyage.path_nm(p_path)::float8;`)
w(`  if v_total <= 0 then`)
w(`    return 'E_BAD_PATH: the course has no length';`)
w(`  end if;`)
w()
w(`  -- Sample every segment. v_done tracks nm already walked, so the head/tail allowances are`)
w(`  -- against the whole path's ends, exactly as the client's own straightener applies them.`)
w(`  for v_i in 0 .. v_n - 2 loop`)
w(`    v_lat1 := (p_path->v_i->>0)::float8;     v_lon1 := (p_path->v_i->>1)::float8;`)
w(`    v_lat2 := (p_path->(v_i+1)->>0)::float8; v_lon2 := (p_path->(v_i+1)->>1)::float8;`)
w(`    if abs(v_lon2 - v_lon1) > 180 then`)
w(`      return format('E_BAD_PATH: segment %s jumps the antimeridian the long way round', v_i);`)
w(`    end if;`)
w(`    v_nm := voyage.gc_distance_nm(v_lat1, v_lon1, v_lat2, v_lon2)::float8;`)
w(`    v_step := greatest(2, ceil(v_nm / ${(CELL_DEG * 60 * 0.5).toFixed(2)})::int);`)
w(`    for v_s in 1 .. v_step - 1 loop`)
w(`      v_f := v_s::float8 / v_step;`)
w(`      -- exempt only the measured approaches at the path's own two ends`)
w(`      continue when v_done + v_f * v_nm < p_head_nm;`)
w(`      continue when v_total - (v_done + v_f * v_nm) < p_tail_nm;`)
w(`      v_lat := v_lat1 + (v_lat2 - v_lat1) * v_f;`)
w(`      v_lon := v_lon1 + (v_lon2 - v_lon1) * v_f;`)
w(`      v_row := least(${ROWS - 1}, greatest(0, floor((90 - v_lat) / ${CELL_DEG})::int));`)
w(`      v_col := ((floor((v_lon + 180) / ${CELL_DEG})::int % ${COLS}) + ${COLS}) % ${COLS};`)
w(`      if get_bit(r.cells, (v_row * ${COLS} + v_col) * r.bits_per_cell) = 0 then`)
w(`        return format('E_LAND: the course touches land near %s°, %s° (segment %s)',`)
w(`                      round(v_lat::numeric, 2), round(v_lon::numeric, 2), v_i);`)
w(`      end if;`)
w(`    end loop;`)
w(`    v_done := v_done + v_nm;`)
w(`  end loop;`)
w(`  return null;`)
w(`end $$;`)
w()
w(`revoke all on function voyage.path_refusal(jsonb, numeric, numeric, numeric, numeric, numeric, numeric, numeric) from public, anon, authenticated;`)
w()
w(`comment on function voyage.path_refusal(jsonb, numeric, numeric, numeric, numeric, numeric, numeric, numeric) is`)
w(`  'THE water-legality of a proposed course (0046): shape, endpoint joins, and every segment '`)
w(`  'sampled at half-cell intervals against public.sea_raster. NULL means legal water; anything '`)
w(`  'else is the E_ sentence the mover raises. One sampler for do_sail, divert and the land guard.';`)
w()
w(`comment on function voyage.path_nm(jsonb) is`)
w(`  'THE measure of a course (0046): the polyline''s own great-circle length. The server never '`)
w(`  'takes a client''s word for a distance — it measures.';`)
w()
w(`-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────`)
w(`do $$`)
w(`declare`)
w(`  r          public.sea_raster%rowtype;`)
w(`  v_n        int;`)
w(`  v_bad      int;`)
w(`  v_ports    int;`)
w(`  v_nm       numeric;`)
w(`  v_ref      text;`)
w(`  v_lis_cad  constant jsonb := ${j(pathJson(lisCad.path))}::jsonb;`)
w(`begin`)
w(`  -- (a) THE RASTER IS THERE AND THE BIT ORDER IS THE ONE THE CLIENT PACKS. Eight control cells,`)
w(`  --     each a named piece of the world, asserted through get_bit — the same read the sampler`)
w(`  --     uses. A packing that shifted one bit would fail all eight.`)
w(`  select * into r from public.sea_raster where id = 1;`)
w(`  if r.cols <> ${COLS} or r.rows <> ${ROWS} or r.bits_per_cell <> ${BITS} or octet_length(r.cells) <> ${packed.length} then`)
w(`    raise exception '0046 self-assert FAIL: the raster is % x % at % bit(s) with % bytes — expected ${COLS} x ${ROWS} at ${BITS} with ${packed.length}', r.cols, r.rows, r.bits_per_cell, octet_length(r.cells);`)
w(`  end if;`)
for (const [name, lat, lon, want] of CONTROLS) {
  const row = Math.min(ROWS - 1, Math.max(0, Math.floor((90 - lat) / CELL_DEG)))
  const col = ((Math.floor((lon + 180) / CELL_DEG) % COLS) + COLS) % COLS
  const bit = (row * COLS + col) * BITS
  w(`  if get_bit(r.cells, ${bit}) <> ${want} then`)
  w(`    raise exception '0046 self-assert FAIL: ${name} (${lat}, ${lon}) reads %, expected ${want}', get_bit(r.cells, ${bit});`)
  w(`  end if;`)
}
// …and the POLAR bit, both ways: set on the Barents road, clear on the mid-Atlantic. A packing
// that interleaved the planes wrongly would fail one of these while the SEA bits still read true.
{
  const cellBit = (lat, lon) => {
    const row = Math.min(ROWS - 1, Math.max(0, Math.floor((90 - lat) / CELL_DEG)))
    const col = ((Math.floor((lon + 180) / CELL_DEG) % COLS) + COLS) % COLS
    return (row * COLS + col) * BITS
  }
  w(`  if get_bit(r.cells, ${cellBit(70, 40) + 1}) <> 1 then`)
  w(`    raise exception '0046 self-assert FAIL: the Barents Sea does not carry the POLAR mark';`)
  w(`  end if;`)
  w(`  if get_bit(r.cells, ${cellBit(30, -40) + 1}) <> 0 then`)
  w(`    raise exception '0046 self-assert FAIL: the mid-Atlantic carries a POLAR mark it must not';`)
  w(`  end if;`)
  w(`  if get_bit(r.cells, ${cellBit(-57.5, -65) + 1}) <> 1 or get_bit(r.cells, ${cellBit(-57.5, -65)}) <> 1 then`)
  w(`    raise exception '0046 self-assert FAIL: the Drake Passage fringe should be open POLAR water';`)
  w(`  end if;`)
}
w()
w(`  -- (a2) THE TWO RASTERS AGREE AT THE CONTROLS: every sailable control cell answers a sea`)
w(`  --      through voyage.sea_at (0040) — one authority composed, so a database where the`)
w(`  --      membership and passability rasters drifted apart cannot apply this file.`)
w(`  if voyage.sea_at(30, -40) is null then`)
w(`    raise exception '0046 self-assert FAIL: the mid-Atlantic (30, -40) is sailable here but answers NO sea through voyage.sea_at (0040) — the two rasters have drifted apart';`)
w(`  end if;`)
w(`  if voyage.sea_at(41, 29) is null then`)
w(`    raise exception '0046 self-assert FAIL: the Bosphorus channel (41, 29) is sailable here but answers NO sea through voyage.sea_at (0040) — the two rasters have drifted apart';`)
w(`  end if;`)
w(`  if voyage.sea_at(70, 40) is null then`)
w(`    raise exception '0046 self-assert FAIL: the Barents Sea (70, 40) is sailable here but answers NO sea through voyage.sea_at (0040) — the two rasters have drifted apart';`)
w(`  end if;`)
w(`  if voyage.sea_at(12, 112) is null then`)
w(`    raise exception '0046 self-assert FAIL: the South China Sea (12, 112) is sailable here but answers NO sea through voyage.sea_at (0040) — the two rasters have drifted apart';`)
w(`  end if;`)
w()
w(`  -- (b) EVERY PLACE HAS A REACH ROW, AND EVERY ROW REACHES EVERY OTHER PLACE. Non-vacuous by`)
w(`  --     the counts themselves: the world cannot hold an island nobody can sail to.`)
w(`  select count(*) into v_ports from public.ports;`)
w(`  select count(*) into v_n from public.sea_reaches;`)
w(`  if v_n <> v_ports or v_n < 2 then`)
w(`    raise exception '0046 self-assert FAIL: % reach row(s) for % port(s)', v_n, v_ports;`)
w(`  end if;`)
w(`  select count(*) into v_bad from public.sea_reaches sr`)
w(`   where (select count(*) from jsonb_object_keys(sr.reaches)) <> v_ports - 1;`)
w(`  if v_bad <> 0 then`)
w(`    raise exception '0046 self-assert FAIL: % place(s) do not reach every other place', v_bad;`)
w(`  end if;`)
w()
w(`  -- (c) THE TABLE IS SYMMETRIC — the whole crosswalk, not a sample. a→b and b→a are one flood,`)
w(`  --     mirrored at generation; a divergence would mean two authorities for one distance.`)
w(`  select count(*) into v_bad`)
w(`    from public.sea_reaches a`)
w(`   cross join lateral jsonb_each_text(a.reaches) e(code, nm)`)
w(`    join public.sea_reaches b on b.code = e.code`)
w(`   where (b.reaches->>a.code)::numeric is distinct from e.nm::numeric;`)
w(`  if v_bad <> 0 then`)
w(`    raise exception '0046 self-assert FAIL: % asymmetric pair reading(s)', v_bad;`)
w(`  end if;`)
w()
w(`  -- (d) NO SAILED DISTANCE IS SHORTER THAN THE GREAT CIRCLE. The whole table against the one`)
w(`  --     distance authority (0002), with a half-percent tolerance for the endpoint snap.`)
w(`  select count(*) into v_bad`)
w(`    from public.sea_reaches a`)
w(`   cross join lateral jsonb_each_text(a.reaches) e(code, nm)`)
w(`    join public.ports pa on pa.id = a.port_id`)
w(`    join public.ports pb on pb.code = e.code`)
w(`   where a.code < e.code`)
w(`     and e.nm::numeric < voyage.gc_distance_nm(pa.lat::float8, pa.lon::float8, pb.lat::float8, pb.lon::float8) * 0.995;`)
w(`  if v_bad <> 0 then`)
w(`    raise exception '0046 self-assert FAIL: % pair(s) sail shorter than the great circle', v_bad;`)
w(`  end if;`)
w()
w(`  -- (e) THE ARCTIC FIX AND THE CANAL CONTROLS — the three worldly facts this migration exists`)
w(`  --     to make true, asserted as RULES about the served numbers, not as seeds.`)
w(`  v_nm := (select (reaches->>${q(NAG.code)})::numeric from public.sea_reaches where code = ${q(LIS.code)});`)
w(`  if v_nm is null or v_nm < 12000 then`)
w(`    raise exception '0046 self-assert FAIL: ${LIS.code}→${NAG.code} is % nm — under 12,000 means the Arctic is open again (the leg graph served 7,565 over the pole)', v_nm;`)
w(`  end if;`)
w(`  if (select (reaches->>${q(ADE.code)})::numeric from public.sea_reaches where code = ${q(ALX.code)}) < 9000 then`)
w(`    raise exception '0046 self-assert FAIL: ${ALX.code}→${ADE.code} under 9,000 nm — a Suez Canal three centuries early';`)
w(`  end if;`)
w(`  if (select (reaches->>${q(ACA.code)})::numeric from public.sea_reaches where code = ${q(VER.code)}) < 9000 then`)
w(`    raise exception '0046 self-assert FAIL: ${VER.code}→${ACA.code} under 9,000 nm — a Panama Canal three centuries early';`)
w(`  end if;`)
w()
w(`  -- (f) THE MEASURE: a real proposed course (Lisbon→Cádiz round Cape St Vincent, produced by`)
w(`  --     the one pathfinder at generation time) measures what the table says it measures, and`)
w(`  --     LONGER than the straight line — the cape is the whole point.`)
w(`  v_nm := voyage.path_nm(v_lis_cad);`)
w(`  if abs(v_nm - ${lisCad.nm.toFixed(1)}) > ${(lisCad.nm * 0.005).toFixed(1)} then`)
w(`    raise exception '0046 self-assert FAIL: the embedded Lisbon→Cádiz course measures % nm, generation measured ${lisCad.nm.toFixed(1)}', v_nm;`)
w(`  end if;`)
w(`  if v_nm <= voyage.gc_distance_nm(${LIS.lat}, ${LIS.lon}, ${CAD.lat}, ${CAD.lon}) then`)
w(`    raise exception '0046 self-assert FAIL: the sailed Lisbon→Cádiz course is not longer than the straight line — Cape St Vincent has gone missing';`)
w(`  end if;`)
w()
w(`  -- (g) THE LAW, both ways — the positive control FIRST: the real water course is accepted…`)
w(`  v_ref := voyage.path_refusal(v_lis_cad, ${LIS.lat}, ${LIS.lon}, ${CAD.lat}, ${CAD.lon}, 15,`)
w(`             (select snap_nm from public.sea_reaches where code = ${q(LIS.code)}) + 25,`)
w(`             (select snap_nm from public.sea_reaches where code = ${q(CAD.code)}) + 25);`)
w(`  if v_ref is not null then`)
w(`    raise exception '0046 self-assert FAIL: the real Lisbon→Cádiz water course was refused: %', v_ref;`)
w(`  end if;`)
w(`  -- …and the straight line Lisbon→Barcelona, which crosses the whole of Iberia, is REFUSED as`)
w(`  -- land. This is the non-vacuity proof the never-touch-land law demands (OWNER_REQUESTS 41):`)
w(`  -- a sampler that cannot catch a line across a continent is decoration.`)
w(`  v_ref := voyage.path_refusal(`)
w(`             jsonb_build_array(jsonb_build_array(${LIS.lat}, ${LIS.lon}), jsonb_build_array(${BCN.lat}, ${BCN.lon})),`)
w(`             ${LIS.lat}, ${LIS.lon}, ${BCN.lat}, ${BCN.lon}, 15, 40, 40);`)
w(`  if v_ref is null or v_ref not like 'E_LAND:%' then`)
w(`    raise exception '0046 self-assert FAIL: a straight Lisbon→Barcelona line across Iberia was NOT refused as land (got [%])', coalesce(v_ref, 'null');`)
w(`  end if;`)
w(`  -- a course that joins the wrong ends is refused as itself, not as land`)
w(`  v_ref := voyage.path_refusal(v_lis_cad, ${CAD.lat}, ${CAD.lon}, ${LIS.lat}, ${LIS.lon}, 15, 40, 40);`)
w(`  if v_ref is null or v_ref not like 'E_OFF_COURSE:%' then`)
w(`    raise exception '0046 self-assert FAIL: a course starting 250 nm from the stated origin was not refused E_OFF_COURSE (got [%])', coalesce(v_ref, 'null');`)
w(`  end if;`)
w(`  -- and a non-course is refused as a shape`)
w(`  if voyage.path_refusal('[[1,2]]'::jsonb, 0, 0, 0, 0, 15, 0, 0) not like 'E_BAD_PATH:%' then`)
w(`    raise exception '0046 self-assert FAIL: a one-point course was not refused E_BAD_PATH';`)
w(`  end if;`)
w()
w(`  -- (h) the posture: world data readable, the two functions server-only`)
w(`  if not has_table_privilege('authenticated', 'public.sea_reaches', 'select')`)
w(`     or has_function_privilege('anon', 'voyage.path_refusal(jsonb, numeric, numeric, numeric, numeric, numeric, numeric, numeric)', 'execute')`)
w(`     or has_function_privilege('authenticated', 'voyage.path_nm(jsonb)', 'execute')`)
w(`     or (select count(*) from public.client_write_grants()) <> 0 then`)
w(`    raise exception '0046 self-assert FAIL: the grant posture is wrong';`)
w(`  end if;`)
w()
w(`  raise notice '0046 self-assert ok: the sea is one raster (${COLS}x${ROWS}, % bytes, 8 named control cells read back through get_bit), every one of % places reaches every other with a symmetric sailed distance never under the great circle; the Arctic is closed (${LIS.code}→${NAG.code} % nm where the leg graph served 7,565 over the pole) and there is no Suez and no Panama (${ALX.code}→${ADE.code} ${Math.round(alxAdeNm)} nm, ${VER.code}→${ACA.code} ${Math.round(verAcaNm)} nm); the measure prices the embedded Lisbon→Cádiz course at % nm (the straight line is %), the law accepted that course and REFUSED a straight Lisbon→Barcelona line across Iberia as E_LAND, a mis-joined course as E_OFF_COURSE and a one-point course as E_BAD_PATH; 0 client write grants',`)
w(`    octet_length(r.cells), v_ports,`)
w(`    (select (reaches->>${q(NAG.code)})::numeric from public.sea_reaches where code = ${q(LIS.code)}),`)
w(`    round(voyage.path_nm(v_lis_cad), 1),`)
w(`    round(voyage.gc_distance_nm(${LIS.lat}, ${LIS.lon}, ${CAD.lat}, ${CAD.lon})::numeric, 1);`)
w(`end $$;`)
w()

const sql = lines.join('\n')
if (sql.includes('\r')) throw new Error('CR found in generated SQL — refuse to emit')
writeFileSync(OUT, sql, 'utf8')
console.log(`\nwrote ${OUT} — ${(sql.length / 1024).toFixed(0)} KiB`)
await db.close()
