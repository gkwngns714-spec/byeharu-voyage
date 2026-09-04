// ═══════════════════════════════════════════════════════════════════════════════════════════════
// build-sea-migration.mjs — writes THE NAVIGABLE SEA, AS DATA. Currently migration 0076.
//
// IT WROTE 0046 FIRST, AND 0046 IS HISTORY NOW. An applied migration is never edited (README §1,
// D23); when the sea moves, this generator emits the NEXT number and that file SUPERSEDES the data
// the last one seeded. So the emit below is a data supersede — it updates public.sea_raster's one
// row (only when the water actually moved) and replaces public.sea_reaches — and it deliberately
// re-cuts NO function that belongs to another slice: voyage.path_nm and voyage.path_refusal were
// created by 0046 and voyage.sail_refusal was re-cut by 0050, so a generator that re-emitted the
// function bodies it happened to remember would silently roll 0050 back. The tables and the two
// 0046 functions are 0046's; only the numbers in them are this file's.
// One constant, MIGRATION, says which file is being written; move it, never the emitted SQL.
//
// ── WHAT 0076 ADDED TO THIS GENERATOR, AND THE ONE SWITCH IT LEFT BEHIND ───────────────────────
// public.sea_reaches now carries THE ROADSTEAD — the one point of open water a place is reached
// from (docs/DESIGN_ROADSTEAD.md). It is the same measurement snap_nm has always been, with the
// coordinate KEPT instead of thrown away, so the two can never disagree: `snapToNav` answers both
// in one call. Two consequences for this file:
//
//   * the insert carries `roadstead_lat` / `roadstead_lon` beside `snap_nm`, at 3 decimal places,
//     which is EXACT and lossless — a cell centre is `90 - (row+0.5)*0.25`, always a multiple of
//     0.125° (measured over all 238 places: every fractional part is .000 .125 .375 .625 .875).
//     A fourth decimal would be a fiction about a 0.25° raster;
//   * `reaches` is measured ROADSTEAD → ROADSTEAD, because after 0076 that is the passage the
//     mover actually sells. A table still measuring quay→quay would advertise Port Royal at
//     560.9 nm from Panama City while `cmd.do_sail` refused the order (0047:445-448's standing
//     law: "world.trade_routes refuses to recommend what this refuses").
//
// THE SWITCH: `INTRODUCES_THE_ROADSTEAD`. The COLUMNS and the DATA above are permanent and are
// emitted on every run. The one-time INTRODUCTION — adding the columns, folding
// voyage.water_snap_nm down onto voyage.water_roadstead, and slicing the four cmd.do_sail hunks,
// the one voyage.assert_paths_water hunk and the one world.snapshot hunk — belongs to 0076 alone.
// A LATER raster migration sets it false, because by then those hunks are already in the deployed
// bodies and `pg_temp.recut` would (correctly) refuse them for occurring zero times. Leaving it
// true on a later run is therefore a LOUD failure at apply, never a silent one.
//
// §7B — the four questions:
//   CONCEPT      "the one statement of what water connects to what": the navigable raster, the
//                roadstead every place is reached from, and the sailed distance between every
//                pair of those roadsteads, all derived FROM that raster by the one pathfinder
//                (src/lib/sea).
//   LIVES HERE   scripts/, because it is a GENERATOR: it runs the applied chain in PGlite to read
//                the world's own ports (codes and coordinates come from the database, never from
//                a second derivation of them), computes, and emits SQL. The AUTHORITY it emits is
//                the migration; once the newest one applies, the raster row IS the sea.
//   SECOND CALLER  none — it is run by hand when the sea or the ports change, and then a NEW
//                migration is cut (never an edit of an applied one). scripts/build-proof-paths.mjs
//                consumes the same src/lib/sea search, not this file.
//   WRONG SHAPE  if the raster it packs and the raster a browser unpacks could differ. They
//                cannot: both sides are src/lib/sea/grid.ts, and the emitted self-assert round-
//                trips get_bit() against embedded control cells. And, since 0076: if the
//                roadstead this file computes and the one `voyage.water_roadstead` computes could
//                differ. They cannot either — the emitted self-assert cross-checks all 238 rows
//                against the SQL rule, which is the whole reason water_snap_nm's body was folded
//                down into a function that returns the point.
//
// THE NAV RULE, stated once, and NOT here:
//   navigable = buildSeaGrid()            (Natural Earth land, scan-filled; the CHANNELS forced
//                                          open; the ICE closures shut — BOTH poles)
// Until 2026-08-25 this file kept a second half of that rule of its own — `if (cellLat(row) < -60)
// cells.fill(0, …)`, the Antarctic pack, written here because ICE only knew how to close a
// NORTHERN latitude. One concept, two files, and the cross-check below then had to hard-code the
// same −60 a third time to know which closed water was allowed to carry a sea name. ICE now takes
// `latBelow` as well as `latAbove`, the Antarctic pack is a row in it like the Northeast Passage,
// and this file reads that list instead of remembering the number. The water is unchanged: the
// closure is the same parallel, measured cell-for-cell (0 cells differ).
//
// THE THIRD SNAP RULE, NAMED RATHER THAN FIXED: `snapToWater` (scripts/sea-grid.mjs:246) answers
// "the nearest water cell" with a DIFFERENT rule from the one this file and the server use — 8
// rings, first-in-scan-order, no distance — and can therefore return a different cell.
// `snapToNav` (src/lib/sea/pathfind.ts:149) and `voyage.water_roadstead` are 12 rings and the
// MINIMUM distance, and they agree. That is spaghetti and it is said plainly. Its whole reachable
// graph is snapToWater ← findSeaRoute (sea-grid.mjs:274) ← scripts/build-sea-places.mjs:157, and
// nothing else; folding it means regenerating data/sea-places.json, which is a different slice.
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

import { writeFileSync, existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import path from 'node:path'
import { buildSeaGrid, COLS, ROWS, CELL_DEG, cellLat, cellLon, inIce } from './sea-grid.mjs'
// NOTE THE TWO cellLat/cellLon PAIRS, and the aliases. scripts/sea-grid.mjs's take (row) and read
// its own module-level CELL_DEG; src/lib/sea's take (nav, row). They are the same arithmetic with
// different signatures, and calling one with the other's arguments returns NaN silently — which is
// exactly what happened on this file's first run: every off-quay roadstead came out {NaN, NaN},
// and BOTH of the guards below waved it through because `Math.abs(NaN - NaN) > 1e-9` is false.
// The guards now reject a non-finite number FIRST, which is the only reason that bug was cheap.
import {
  packCells,
  findPath,
  floodFrom,
  floodPathTo,
  snapToNav,
  gcNm,
  navFromServed,
  cellLat as navCellLat,
  cellLon as navCellLon,
  SEA_BIT,
  POLAR_BIT,
} from '../src/lib/sea/index.ts'
import { applyChain, MIGRATIONS_DIR } from './db/apply-chain.mjs'

// The migration this run writes. 0046 was the first; an applied one is history, so this moves and
// the emitted SQL supersedes what the previous number seeded.
const MIGRATION = '20260818000076_a_harbour_is_reached_from_its_roads.sql'
const SHORT = MIGRATION.slice(10, 14)
const OUT = path.join(MIGRATIONS_DIR, MIGRATION)
const BITS = 2

// See the header. TRUE for 0076 only — the file that introduces the roadstead. A later raster
// migration flips this to false; leaving it true makes the apply fail loudly at pg_temp.recut.
const INTRODUCES_THE_ROADSTEAD = true

// ── 1. The navigable grid ──────────────────────────────────────────────────────────────────────
// buildSeaGrid() is the WHOLE rule now — land, channels and the ice at both poles. Nothing is
// added, removed or clamped here; see the header.
console.log('building the navigable grid…')
const cells = buildSeaGrid()
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

// ── 3. THE ROADSTEAD of every place, and all-pairs sailed distances between them ───────────────
// ONE call to snapToNav answers both halves of the same measurement — how far the water is, and
// WHERE it is — so `snap_nm` and the roadstead cannot disagree by construction. Two rules, and
// only the second one is new:
//   * a place whose OWN cell is sailable water IS its own roadstead, at distance 0. Not the
//     centre of that cell: the centre can lie 10.6 nm from a place whose snap_nm is 0, and the
//     helper line the chart draws must be snap_nm long or it is a picture of a different number
//     (src/chart/route.ts:8-12).
//   * every other place takes the centre of the nearest sailable cell.
console.log('measuring every place’s roadstead…')
const reaches = new Map() // code -> Map(code -> nm)
const snapNm = new Map() // code -> nm from the true coordinate to sailable water
const roads = new Map() // code -> { lat, lon } — the roadstead, 3 dp, exact
for (const p of ports) reaches.set(p.code, new Map())
const r3 = (x) => Number(x.toFixed(3))
for (const p of ports) {
  const s = snapToNav(nav, p.lat, p.lon)
  if (!s) throw new Error(`${p.code} ${p.name}: no sailable water within reach of its coordinate`)
  snapNm.set(p.code, s.snapNm)
  const exact =
    s.snapNm === 0
      ? { lat: p.lat, lon: p.lon }
      : { lat: navCellLat(nav, s.row), lon: navCellLon(nav, s.col) }
  const point = { lat: r3(exact.lat), lon: r3(exact.lon) }
  // A NON-FINITE COORDINATE MUST BE CAUGHT HERE, not by the comparisons below: every `>` test
  // against a NaN is false, so a broken measurement would pass all of them and be seeded.
  if (![point.lat, point.lon, s.snapNm].every(Number.isFinite)) {
    throw new Error(`${p.code}: the roadstead measured (${point.lat}, ${point.lon}) at ${s.snapNm} nm`)
  }
  // 3 dp must be LOSSLESS, not merely close: assert it rather than trusting the arithmetic.
  if (Math.abs(point.lat - exact.lat) > 1e-9 || Math.abs(point.lon - exact.lon) > 1e-9) {
    throw new Error(
      `${p.code}: rounding the roadstead to 3 dp LOST something (${exact.lat},${exact.lon} → ` +
        `${point.lat},${point.lon}) — 3 dp is only exact for a 0.25° raster and 2 dp port coordinates`,
    )
  }
  // The invariant the chart's helper line stands on: the line drawn IS the distance measured.
  const drawn = gcNm(p.lat, p.lon, point.lat, point.lon)
  if (Math.abs(drawn - s.snapNm) > 1e-6) {
    throw new Error(
      `${p.code}: the roadstead lies ${drawn.toFixed(4)} nm off the quay but snap_nm is ` +
        `${s.snapNm.toFixed(4)} — the helper line would not be the measured distance`,
    )
  }
  roads.set(p.code, point)
}
const ownWater = ports.filter((p) => snapNm.get(p.code) === 0).length
const offQuay = ports.length - ownWater
const overNm = (n) => ports.filter((p) => snapNm.get(p.code) > n).length
const worst = [...snapNm.entries()].sort((a, b) => b[1] - a[1])
const distinctCells = new Set([...roads.values()].map((r) => `${r.lat},${r.lon}`)).size
console.log(
  `  ${ownWater} place(s) already stand on sailable water (snap 0, their own roadstead); ` +
    `${offQuay} carry a roadstead off the quay; >10 nm ${overNm(10)}, >20 nm ${overNm(20)}, ` +
    `>30 nm ${overNm(30)}, >50 nm ${overNm(50)}`,
)
console.log(`  worst: ${worst.slice(0, 8).map(([c, n]) => `${c} ${n.toFixed(2)}`).join(' · ')}`)
console.log(`  ${distinctCells} distinct roadstead cell(s) for ${ports.length} places — they are NOT unique`)

// ── CROSS-CHECK against 0040's sea-membership raster (public.sea_cells) ────────────────────────
// The chain applied above includes 0040, so the membership bytes are readable right here. Rules:
//   * every navigable cell REACHABLE from the port network must carry a sea (a reachable cell
//     with byte 0 means the two rasters genuinely disagree — refuse to emit);
//   * unreachable navigable water with no sea is the KNOWN landlocked-pool set (Caspian and
//     friends) — counted and printed, never silently;
//   * membership on water this mask CLOSES must be inside an authored ICE closure — 0040 names
//     those waters, this file forbids sailing them, which is a division of labour and not a
//     disagreement. The allowance is read from scripts/sea-grid.mjs's ICE list (inIce), never
//     from a latitude repeated here.
//
// AND WHEN A CHANNEL OPENS WATER 0040 NEVER SAW. A new CHANNELS entry turns land into sea, and
// land carries no sea name, so those cells arrive as reachable-water-with-no-sea — the wound above.
// They are not a drift: they are this migration's own doing, and the honest repair is the SAME
// rule build-sea-raster.mjs used for every unnamed water it met (its header: "it joins the nearest
// named sea BY WATER — a multi-source BFS through water cells, so nothing leaks across an
// isthmus"). So each wound is healed by a BFS through the NEW water to the nearest cell that
// already carries a name, the healed rows are emitted as a sea_cells patch beside the raster, and
// every one is printed and asserted BY NAME in the migration. A wound the rule cannot answer
// (no named water reachable at all) still refuses to emit.
const seaPatch = new Map() // row_idx -> Uint8Array(COLS), only for rows a heal touched
const healed = [] // { lat, lon, ordinal } — printed, and asserted by name in the migration
{
  const seaRows = (
    await db.query('select row_idx, seas from public.sea_cells order by row_idx')
  ).rows
  if (seaRows.length !== ROWS) throw new Error(`sea_cells has ${seaRows.length} rows, expected ${ROWS} — is 0040 applied?`)
  const membership = new Uint8Array(COLS * ROWS)
  const seaByRow = new Map()
  for (const r of seaRows) {
    membership.set(r.seas, r.row_idx * COLS)
    seaByRow.set(r.row_idx, r.seas)
  }
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
    if (reachable[i] === 2) wounds.push(i)
    else pools++
  }

  // Heal each wound with the nearest named sea BY WATER (four-neighbour BFS over the new grid).
  for (const wound of wounds) {
    const seen = new Set([wound])
    const queue = [wound]
    let found = 0
    for (let head = 0; head < queue.length && found === 0; head++) {
      const at = queue[head]
      const row = (at / COLS) | 0
      const col = at - row * COLS
      for (const [dr, dc] of [[-1, 0], [1, 0], [0, -1], [0, 1]]) {
        const nrow = row + dr
        if (nrow < 0 || nrow >= ROWS) continue
        const ncol = ((col + dc) % COLS + COLS) % COLS
        const next = nrow * COLS + ncol
        if (seen.has(next) || !cells[next]) continue
        if (membership[next] > 0) { found = membership[next]; break }
        seen.add(next)
        queue.push(next)
      }
    }
    const row = (wound / COLS) | 0
    const col = wound - row * COLS
    if (found === 0) {
      throw new Error(
        `REACHABLE water with NO sea at (${cellLat(row).toFixed(2)}, ${cellLon(col).toFixed(2)}) and ` +
          `no named water reachable from it — public.sea_cells (0040) and this raster disagree ` +
          `about the ocean itself, and the nearest-sea-by-water rule cannot answer it`,
      )
    }
    if (!seaPatch.has(row)) seaPatch.set(row, Uint8Array.from(seaByRow.get(row)))
    seaPatch.get(row)[col] = found
    membership[wound] = found
    healed.push({ row, col, lat: cellLat(row), lon: cellLon(col), ordinal: found })
  }

  let iced = 0
  const northWounds = []
  for (let i = 0; i < COLS * ROWS; i++) {
    if (cells[i] || membership[i] === 0) continue
    const row = (i / COLS) | 0
    const col = i - row * COLS
    if (inIce(cellLat(row), cellLon(col))) iced++
    else northWounds.push(`(${cellLat(row).toFixed(2)}, ${cellLon(col).toFixed(2)})`)
  }
  if (northWounds.length > 0) {
    throw new Error(
      `sea-membership on water this mask closes OUTSIDE every ICE closure (${northWounds.length} ` +
        `cell(s)) — the two rasters disagree where no authored ice explains it: ${northWounds.slice(0, 12).join(', ')}`,
    )
  }
  console.log(
    `  cross-check vs public.sea_cells (0040): every reachable navigable cell carries a sea ` +
      `(${healed.length} newly opened cell(s) healed to the nearest sea by water); ` +
      `${pools} unreachable pool cell(s) carry none (Caspian and friends); ` +
      `${iced} named-but-closed cell(s), every one inside an authored ICE closure`,
  )
  for (const h of healed) {
    console.log(`    healed (${h.lat.toFixed(3)}, ${h.lon.toFixed(3)}) → sea ordinal ${h.ordinal}`)
  }
}

console.log('flooding the ocean from every roadstead…')
const t0 = performance.now()
for (let i = 0; i < ports.length; i++) {
  const a = ports[i]
  const ra = roads.get(a.code)
  const flood = floodFrom(nav, ra)
  if (!flood) throw new Error(`${a.code} ${a.name}: its own roadstead reaches no water`)
  if (flood.source.snapNm !== 0) {
    throw new Error(
      `${a.code}: the roadstead at (${ra.lat}, ${ra.lon}) does not stand on sailable water — it ` +
        `snapped a further ${flood.source.snapNm.toFixed(2)} nm`,
    )
  }
  for (let j = i + 1; j < ports.length; j++) {
    const b = ports[j]
    const r = floodPathTo(flood, ra, roads.get(b.code))
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

// ── 4. The fixtures the migration embeds for its own asserts ───────────────────────────────────
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
const BRS = byName('Bristol')
const AMS = byName('Amsterdam')
const PAN = byName('Panama City')
const POR = byName('Port Royal')
const HAM = byName('Hamburg')
const LUB = byName('Lubeck', 'Lübeck')

// A real proposed water path, as a client would send one — and, since 0076, ROADSTEAD to
// ROADSTEAD, which is the only shape the re-cut cmd.do_sail will accept for a port pair.
const lisCad = findPath(nav, roads.get(LIS.code), roads.get(CAD.code))
if (!lisCad) throw new Error('no Lisbon→Cádiz path between the roadsteads — the raster is broken')

// THE PROBE'S DESTINATION, chosen by measurement rather than named here: of the harbours within a
// starter hull's comfortable range of Lisbon, the one whose roadstead lies FURTHEST off its own
// quay. That is what makes the destination hunk load-bearing in the self-assert — reverting it
// aims the mover at the quay, which is more than `course_join_nm` (15 nm) from the course's last
// point, so the order is refused E_OFF_COURSE instead of quietly behaving the same.
// MEASURED THE HARD WAY: the first draft sailed to Cádiz, whose roadstead is 9.99 nm out — INSIDE
// the join tolerance — so reverting that hunk changed nothing at all and the break-test reported
// the guard as decoration. It was.
const PROBE_RANGE_NM = 600
const probe = ports
  .filter((p) => p.kind === 'HARBOUR' && p.code !== LIS.code)
  .filter((p) => (reaches.get(LIS.code).get(p.code) ?? Infinity) < PROBE_RANGE_NM)
  .sort((a, b) => snapNm.get(b.code) - snapNm.get(a.code) || (a.code < b.code ? -1 : 1))[0]
if (!probe || snapNm.get(probe.code) <= 15) {
  throw new Error(
    `no harbour within ${PROBE_RANGE_NM} nm of ${LIS.code} snaps further than course_join_nm, so the ` +
      `self-assert cannot prove the destination hunk does anything`,
  )
}
const lisProbe = findPath(nav, roads.get(LIS.code), roads.get(probe.code))
if (!lisProbe) throw new Error(`no ${LIS.code}→${probe.code} path between the roadsteads`)
console.log(
  `  the probe destination: ${probe.code} ${probe.name}, roadstead ${snapNm.get(probe.code).toFixed(2)} nm off her quay, ` +
    `${reaches.get(LIS.code).get(probe.code).toFixed(1)} nm from ${LIS.code}`,
)
const brsAms = findPath(nav, roads.get(BRS.code), roads.get(AMS.code))
if (!brsAms) throw new Error('no Bristol→Amsterdam path — the Severn channel is broken')
const brsAmsNm = reaches.get(BRS.code).get(AMS.code)
const lisNagNm = reaches.get(LIS.code).get(NAG.code)
const alxAdeNm = reaches.get(ALX.code).get(ADE.code)
const verAcaNm = reaches.get(VER.code).get(ACA.code)
console.log(`  canal controls: ${ALX.code}→${ADE.code} ${Math.round(alxAdeNm)} nm round the Cape (no Suez); ` +
            `${VER.code}→${ACA.code} ${Math.round(verAcaNm)} nm round the Horn (no Panama)`)
console.log(`  the Arctic control: ${LIS.code}→${NAG.code} ${Math.round(lisNagNm)} nm`)

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
  // The Severn: the channel Bristol sails, and the hills it must NOT spill into.
  ['the Bristol Channel off Barry', 51.4, -3.1, 1],
  ['the Severn approach at Bristol', 51.45, -2.6, 1],
  ['the Welsh hills above the channel', 52.0, -3.5, 0],
  // The Antarctic closure, pinned to the parallel from BOTH sides: the Southern Ocean at 59°S is
  // open water the period's whalers and Horn traffic could be in; 61°S is pack ice.
  ['the Southern Ocean at 59°S (open)', -59, 0, 1],
  ['the pack at 61°S (closed)', -61, 0, 0],
]
for (const [name, lat, lon, want] of CONTROLS) {
  const r = Math.min(ROWS - 1, Math.max(0, Math.floor((90 - lat) / CELL_DEG)))
  const c = ((Math.floor((lon + 180) / CELL_DEG) % COLS) + COLS) % COLS
  const got = cells[r * COLS + c]
  if (got !== want) throw new Error(`control cell "${name}" is ${got}, expected ${want}`)
}

// ── 5. Emit ────────────────────────────────────────────────────────────────────────────────────
const lines = []
const w = (s = '') => lines.push(s)
const q = (s) => `'${String(s).replace(/'/g, "''")}'`
const j = (x) => `'${JSON.stringify(x).replace(/'/g, "''")}'`

const pathJson = (p) => p.map(([lat, lon]) => [Number(lat.toFixed(4)), Number(lon.toFixed(4))])

// ── WHAT THIS RASTER CHANGES, measured against the one the chain is already serving ────────────
// The applied chain includes the previous raster migration, so the bytes it seeded are readable
// right here. Diffing them against what was just built is the only honest way to say "N cells
// changed" — a number remembered from a probe would drift the first time anyone edited the sea.
const appliedRow = (
  await db.query(`select cols, rows, cell_deg::float8 as cell_deg, bits_per_cell, octet_length(cells) as bytes,
                         replace(encode(cells, 'base64'), e'\\n', '') as cells_base64
                    from public.sea_raster where id = 1`)
).rows[0]
const applied = navFromServed(appliedRow)
let opened = 0
let closed = 0
for (let i = 0; i < COLS * ROWS; i++) {
  if (cells[i] && !applied.cells[i]) opened++
  else if (!cells[i] && applied.cells[i]) closed++
}
const appliedWater = applied.cells.reduce((n, c) => n + c, 0)
const newWater = cells.reduce((n, c) => n + c, 0)
// The water moved, or it did not. Both are real states and each gets its own honest emit: a
// migration that rewrote 260 KB of identical raster bytes would be claiming a change it did not
// make, and one that skipped a real change would ship a table measured over water nobody has.
const waterMoved = opened > 0 || closed > 0 || appliedRow.cells_base64 !== b64
console.log(
  `  raster diff vs the applied one: ${appliedWater} → ${newWater} water cells ` +
    `(+${opened} opened, -${closed} closed) — ${waterMoved ? 'THE WATER MOVED, the raster is rewritten' : 'byte-identical, the raster is NOT rewritten'}`,
)
if (!waterMoved && seaPatch.size > 0) {
  throw new Error('the raster is byte-identical yet the membership heal wants to patch rows — refuse to emit')
}

// ── WHAT THE TABLE CHANGES, measured against the reaches the chain is already serving ──────────
// The applied `sea_reaches` is quay→quay; this one is roadstead→roadstead. That is the whole
// gameplay effect of the slice, so it is MEASURED over every pair rather than argued.
const appliedReaches = new Map(
  (await db.query('select code, snap_nm::float8 as snap_nm, reaches from public.sea_reaches')).rows.map((r) => [
    r.code,
    r,
  ]),
)
const deltas = []
const bigMoves = []
for (let i = 0; i < ports.length; i++) {
  const a = ports[i]
  const was = appliedReaches.get(a.code)
  if (!was) continue
  for (let k = i + 1; k < ports.length; k++) {
    const b = ports[k]
    const before = Number(was.reaches[b.code])
    const after = reaches.get(a.code).get(b.code)
    if (!Number.isFinite(before) || !Number.isFinite(after)) continue
    deltas.push({ a: a.code, b: b.code, before, after, d: after - before, pct: ((after - before) / before) * 100 })
    if (Math.abs(after - before) > 500) bigMoves.push({ a, b, before, after })
  }
}
const median = (xs) => {
  const s = [...xs].sort((x, y) => x - y)
  return s.length === 0 ? NaN : s.length % 2 ? s[(s.length - 1) / 2] : (s[s.length / 2 - 1] + s[s.length / 2]) / 2
}
const mean = (xs) => xs.reduce((t, x) => t + x, 0) / xs.length
const medD = median(deltas.map((x) => x.d))
const meanD = mean(deltas.map((x) => x.d))
const medPct = median(deltas.map((x) => x.pct))
const under05 = (deltas.filter((x) => Math.abs(x.pct) < 0.5).length / deltas.length) * 100
const over5 = (deltas.filter((x) => Math.abs(x.pct) > 5).length / deltas.length) * 100
console.log(
  `  reach diff over ${deltas.length.toLocaleString('en')} pairs: mean ${meanD.toFixed(2)} nm, median ${medD.toFixed(2)} nm, ` +
    `median ${medPct.toFixed(2)} %, ${under05.toFixed(1)} % of pairs under 0.5 %, ${over5.toFixed(2)} % over 5 %`,
)
for (const m of bigMoves.sort((x, y) => Math.abs(y.after - y.before) - Math.abs(x.after - x.before))) {
  console.log(`    ${m.a.name} → ${m.b.name}: ${m.before.toFixed(1)} → ${m.after.toFixed(1)} nm`)
}

// ── THE LAND GUARD AT ITS OWN SAMPLING, measured through the SERVER's function, not restated ───
// The chain applied above still holds the OLD allowances, so voyage.path_refusal can be asked
// both questions right here: is the quay-to-quay line accepted today, and is the roads-to-roads
// line refused under the flat one? Both answers go in the header as facts with a date on them.
const askRefusal = async (fromLat, fromLon, toLat, toLon, head, tail) =>
  (
    await db.query(
      `select voyage.path_refusal(jsonb_build_array(jsonb_build_array($1::numeric, $2::numeric),
                                                    jsonb_build_array($3::numeric, $4::numeric)),
                                  $1::numeric, $2::numeric, $3::numeric, $4::numeric,
                                  public.wc_num('course_join_nm'), $5::numeric, $6::numeric) as ref`,
      [fromLat, fromLon, toLat, toLon, head, tail],
    )
  ).rows[0].ref
const breach = []
for (const [a, b] of [[PAN, POR], [HAM, LUB]]) {
  const ra = roads.get(a.code)
  const rb = roads.get(b.code)
  const sa = snapNm.get(a.code)
  const sb = snapNm.get(b.code)
  const cityRef = await askRefusal(a.lat, a.lon, b.lat, b.lon, sa + 25, sb + 25)
  const roadRef = await askRefusal(ra.lat, ra.lon, rb.lat, rb.lon, 25, 25)
  const cityNm = gcNm(a.lat, a.lon, b.lat, b.lon)
  breach.push({ a, b, sa, sb, cityRef, roadRef, cityNm, allowance: sa + sb + 50 })
  console.log(
    `  ${a.name} → ${b.name}: quay-to-quay ${cityNm.toFixed(1)} nm under ${(sa + 25).toFixed(2)}/${(sb + 25).toFixed(2)} nm ` +
      `→ ${cityRef ?? 'ACCEPTED'}; roads-to-roads under 25/25 → ${roadRef ?? 'ACCEPTED'}`,
  )
  if (cityRef !== null) {
    throw new Error(
      `${a.code}→${b.code}: the quay-to-quay line is ALREADY refused under the old allowance — the ` +
        `defect this migration claims to close is not there, and its headline control would be a boast`,
    )
  }
  if (roadRef === null || !roadRef.startsWith('E_LAND')) {
    throw new Error(
      `${a.code}→${b.code}: the roads-to-roads line is not refused as E_LAND (got ${roadRef ?? 'ACCEPTED'}) — ` +
        `the isthmus is still open and this migration repairs nothing`,
    )
  }
}
const seaNames = new Map(
  (await db.query('select raster_ordinal, name from public.seas where raster_ordinal is not null')).rows
    .map((r) => [Number(r.raster_ordinal), r.name]),
)
for (const h of healed) {
  h.sea = seaNames.get(h.ordinal)
  if (!h.sea) throw new Error(`healed cell (${h.lat}, ${h.lon}) took ordinal ${h.ordinal}, which names no sea`)
}
const b64Row = (bytes) => Buffer.from(bytes).toString('base64')
const nfmt = (x) => Math.round(x).toLocaleString('en')

w(`-- ═══════════════════════════════════════════════════════════════════════════════════════════════`)
w(`-- ${SHORT} — A HARBOUR IS REACHED FROM ITS ROADS`)
w(`--        The roadstead becomes a place: measured, seeded, served — and the course ends there.`)
w(`-- ═══════════════════════════════════════════════════════════════════════════════════════════════`)
w(`--`)
w(`-- GENERATED by scripts/build-sea-migration.mjs — do not hand-edit. Change the sea (scripts/`)
w(`-- sea-grid.mjs) or the ports and cut a NEW migration; an applied one is history.`)
w(`--`)
w(`-- ── THE OWNER, VERBATIM (docs/OWNER_REQUESTS.md:131, row 72) ───────────────────────────────────`)
w(`--   "create a perpendicular helper line (dotted) that is the shortest point between the land`)
w(`--    city and nearby shore - sea. Then create a point there, and when the ship arrive at that`)
w(`--    point, consider it as the ship have landed on land"`)
w(`--`)
w(`-- ── WHAT SAYS THE OPPOSITE, NAMED ──────────────────────────────────────────────────────────────`)
w(`--   * cmd.do_sail takes the port's RAW COORDINATE as the course endpoint (0047:589-590, 0047:602)`)
w(`--     and grants \`snap_nm + 25\` nm of land-crossing allowance at each end (0047:588, 0047:606).`)
w(`--   * voyage.path_refusal skips every sample inside that allowance; the client's mirror of the`)
w(`--     same rule is src/lib/sea/pathfind.ts:317.`)
w(`--   * public.sea_reaches records the snap DISTANCE and throws the point away (0046:79), and`)
w(`--     voyage.water_snap_nm computes the winning cell (0047:225-228) and returns only the number.`)
w(`--     No function in the chain could answer "WHERE is the water nearest this place".`)
w(`--   * scripts/sea-grid.mjs:246 \`snapToWater\` is a THIRD, DIFFERENT snap rule — 8 rings, the`)
w(`--     first water cell in scan order rather than the nearest — with exactly one build-time`)
w(`--     caller (scripts/build-sea-places.mjs:157, through findSeaRoute). It is NAMED here rather`)
w(`--     than fixed: folding it regenerates data/sea-places.json, which is its own slice.`)
w(`--`)
w(`-- ── WHAT THIS DOES ─────────────────────────────────────────────────────────────────────────────`)
w(`--   1. public.sea_reaches gains roadstead_lat/roadstead_lon (numeric(6,3)/(7,3), NOT NULL).`)
w(`--   2. voyage.water_snap_nm's BODY MOVES DOWN into voyage.water_roadstead(lat, lon), which`)
w(`--      returns (nm, lat, lon); water_snap_nm keeps its signature and becomes one line over it.`)
w(`--      One body now answers "where is the water nearest this point, and how far" — which is`)
w(`--      what makes the JS-generated column checkable against the SQL rule for all ${ports.length} rows.`)
w(`--   3. public.sea_reaches is replaced WHOLE: snap_nm, the two roadstead columns, and \`reaches\``)
w(`--      re-measured ROADSTEAD → ROADSTEAD (the 0052:92-94 delete-and-insert, exactly).`)
w(`--   4. cmd.do_sail: four hunks. A port end is the ROADSTEAD and its allowance is a flat 25 nm.`)
w(`--   5. voyage.assert_paths_water: one hunk, the same allowance — with pre-0076 voyages`)
w(`--      GRANDFATHERED on voyages.departed_at, so a passage a player already bought is judged by`)
w(`--      the rule it was admitted under.`)
w(`--   6. world.snapshot().ports[] gains one key, \`roadstead\` — { lat, lon, nm } — so the chart`)
w(`--      draws the helper line off a SERVED number and never computes a snap of its own.`)
w(`--`)
w(`-- ── AND WHAT IT DELIBERATELY DOES NOT ──────────────────────────────────────────────────────────`)
w(`--   * It does not touch voyage.settle. Arrival is ALREADY right: 0027:409-416 docks her at`)
w(`--     v.dest_port_id at the ETA, so the moment the course ENDS at the roadstead the owner's`)
w(`--     sentence is true by the mechanism shipping since 0007. A geometric arrival test would be`)
w(`--     a second authority for "has she arrived" beside the ETA, and none is written.`)
w(`--   * It does not shrink the ~21 nm (client) / 25 nm (server) sampling slack every course end`)
w(`--     still enjoys. src/lib/sea/pathfind.ts:330 gives every path end \`cellDiagNm\` =`)
w(`--     0.25 * 60 * sqrt(2) = 21.21 nm unconditionally; a server allowance under that would`)
w(`--     refuse courses the client's own straightener legitimately produced. Said plainly rather`)
w(`--     than implied: shrinking THAT is the never-touch-land slice, not this one.`)
w(`--   * It opens and closes no CHANNEL, moves no price knob, and touches no player row.`)
if (!waterMoved) {
  w(`--   * IT DOES NOT MOVE THE WATER. The grid built by this run is BYTE-IDENTICAL to the one`)
  w(`--     public.sea_raster already holds (${nfmt(newWater)} water cells, ${packed.length} packed bytes, +0 opened,`)
  w(`--     -0 closed), so the raster row is not rewritten. Only what the table SAYS about that`)
  w(`--     water changes.`)
}
w(`--`)
w(`-- ── EVIDENCE, MEASURED BY THIS RUN AGAINST THE APPLIED CHAIN ───────────────────────────────────`)
w(`--   THE ROADSTEADS. ${ports.length} places; ${ownWater} already stand on sailable water and are their own`)
w(`--   roadstead at 0 nm; ${offQuay} carry a real roadstead off the quay. Over 10 nm: ${overNm(10)}. Over`)
w(`--   20 nm: ${overNm(20)}. Over 30 nm: ${overNm(30)}. Over 50 nm: ${overNm(50)}. Worst:`)
w(`--     ${worst.slice(0, 8).map(([c, n]) => `${c} ${n.toFixed(2)}`).join(' · ')}`)
w(`--   ${distinctCells} distinct cells for ${ports.length} places — roadsteads are NOT unique and nothing may assume it.`)
w(`--`)
w(`--   THE DISTANCE EFFECT, all ${deltas.length.toLocaleString('en')} pairs, this table against the one the chain serves:`)
w(`--     mean ${meanD.toFixed(2)} nm · median ${medD.toFixed(2)} nm · MEDIAN ${medPct.toFixed(2)} % · ${under05.toFixed(1)} % of pairs move under 0.5 %`)
w(`--     ${over5.toFixed(2)} % of pairs move over 5 %. This is NOT a repricing: 0048 moved PRICES; this moves`)
w(`--     DISTANCES by a fifth of a percent at the median. Every price knob is untouched.`)
w(`--`)
w(`--   THE ONLY ${bigMoves.length} PAIRS THAT MOVE MORE THAN 500 nm — and every one of them is the documented`)
w(`--   live breach of the never-touch-land law, repaired:`)
for (const m of bigMoves.sort((x, y) => Math.abs(y.after - y.before) - Math.abs(x.after - x.before))) {
  w(`--     ${(m.a.name + ' → ' + m.b.name).padEnd(34)} ${m.before.toFixed(1).padStart(9)} → ${m.after.toFixed(1).padStart(10)} nm`)
}
w(`--   Those passages become the long way round. That is the repair, and it is a VISIBLE gameplay`)
w(`--   change: a house running a Panama-to-Caribbean loop loses a route that was a Panama Canal`)
w(`--   three and a half centuries early.`)
w(`--`)
w(`--   THE LAND GUARD AT ITS OWN SAMPLING, asked of voyage.path_refusal on the applied chain:`)
for (const b of breach) {
  w(`--     ${(b.a.name + ' → ' + b.b.name).padEnd(30)} quay→quay ${b.cityNm.toFixed(1)} nm under ${b.sa.toFixed(2)}+25 / ${b.sb.toFixed(2)}+25 nm: ACCEPTED`)
  w(`--     ${''.padEnd(30)} roads→roads under 25 / 25 nm: ${b.roadRef}`)
}
{
  const ham = breach.find((b) => b.a.code === HAM.code)
  if (ham && ham.cityNm < ham.allowance) {
    w(`--     The Hamburg row is the worst of the two: the WHOLE ${ham.cityNm.toFixed(1)} nm line lies inside`)
    w(`--     head + tail = ${ham.allowance.toFixed(1)} nm, so voyage.path_refusal walks it and checks ZERO samples. The`)
    w(`--     guard is not lenient there — it is switched off.`)
  }
}
w(`--`)
w(`--   PRECISION. Every roadstead is a cell centre (\`90 - (row+0.5)*0.25\`) or a 2-dp port`)
w(`--   coordinate, so 3 decimal places is EXACT and lossless — asserted at generation, not hoped.`)
w(`--   A fourth decimal would be a fiction about a 0.25° raster.`)
w(`--`)
w(`-- Depends on: 0002 (ports, seas, gc_distance_nm), 0040 (sea_cells, voyage.sea_at), 0046 (the two`)
w(`-- tables, voyage.path_nm, voyage.path_refusal), 0047 (cmd.do_sail, voyage.water_snap_nm,`)
w(`-- voyage.assert_paths_water), 0050 (cmd.do_sail's live body), 0032/0036/0067/0071 (world.snapshot's`)
w(`-- live body), and the port rows of 0003/0036/0041.`)
w(`-- ═══════════════════════════════════════════════════════════════════════════════════════════════`)
w()

if (INTRODUCES_THE_ROADSTEAD) {
  w(`-- ── THE SLICER. 0075's helper (0075:66-88) verbatim, with this file's slice id. Its law: a `)
  w(`-- hunk that does not occur EXACTLY ONCE in the deployed body is a failed apply, so a drifted`)
  w(`-- production body refuses the migration instead of silently taking half of it.`)
  w(`create or replace function pg_temp.recut(p_fn regprocedure, p_drop boolean, variadic p_edits text[])`)
  w(`returns void`)
  w(`language plpgsql`)
  w(`as $recut$`)
  w(`declare`)
  w(`  v_def text := pg_get_functiondef(p_fn);`)
  w(`  v_i   int := 1;`)
  w(`  v_n   int;`)
  w(`begin`)
  w(`  while v_i < array_length(p_edits, 1) loop`)
  w(`    v_n := (length(v_def) - length(replace(v_def, p_edits[v_i], ''))) / length(p_edits[v_i]);`)
  w(`    if v_n <> 1 then`)
  w(`      raise exception '${SHORT} slice: hunk % of % occurs % time(s) in %, expected exactly 1 — the deployed body is not what this migration was generated against.',`)
  w(`        (v_i + 1) / 2, (array_length(p_edits, 1)) / 2, v_n, p_fn;`)
  w(`    end if;`)
  w(`    v_def := replace(v_def, p_edits[v_i], p_edits[v_i + 1]);`)
  w(`    v_i := v_i + 2;`)
  w(`  end loop;`)
  w(`  if p_drop then`)
  w(`    execute format('drop function %s', p_fn::text);`)
  w(`  end if;`)
  w(`  execute v_def;`)
  w(`end $recut$;`)
  w()
  w(`-- PRE-IMAGES. "Nothing else moved" is a comparison, never a sentence (NO_SPAGHETTI §3.3).`)
  w(`create temporary table defs_before_${SHORT} as`)
  w(`  select f.fn, pg_get_functiondef(f.fn::regprocedure) as def,`)
  w(`         (select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure) as acl`)
  w(`    from (values ('cmd.do_sail(uuid, jsonb)'), ('world.snapshot()'),`)
  w(`                 ('voyage.assert_paths_water()')) as f(fn);`)
  w()
  w(`-- ── 1. THE COLUMNS ─────────────────────────────────────────────────────────────────────────────`)
  w(`-- On sea_reaches and NOT on public.ports, deliberately: \`ports\` is the AUTHORED world`)
  w(`-- (data/ports.json -> 0003/0041/0058) and scripts/db/world-guard.mjs fails any apply whose`)
  w(`-- applied world is not that file. A raster-derived column there would either break that guard`)
  w(`-- or push the roadstead into a JSON file where a hand edit could put it on land. A port's`)
  w(`-- coordinate is a fact about a CITY; the roadstead is a fact about the RASTER — and it is the`)
  w(`-- same measurement snap_nm already is, taken in the same pass by the same function, so it`)
  w(`-- belongs in the same row. Nullable for exactly as long as it takes to fill them, below.`)
  w(`alter table public.sea_reaches`)
  w(`  add column if not exists roadstead_lat numeric(6,3),`)
  w(`  add column if not exists roadstead_lon numeric(7,3);`)
  w()
  w(`comment on column public.sea_reaches.roadstead_lat is`)
  w(`  'THE ROADSTEAD (0076): the one point of open water this place is reached from. A course to '`)
  w(`  'this place BEGINS and ENDS here, and voyage.settle then docks her at the port itself. It is '`)
  w(`  'the cell voyage.water_roadstead answers for the quay coordinate, EXCEPT where the quay''s '`)
  w(`  'own cell is sailable water, in which case it IS the quay coordinate and snap_nm is 0 — so '`)
  w(`  'that gc(quay, roadstead) = snap_nm holds on every row and the helper line the chart draws '`)
  w(`  'is the distance the table measured. 3 dp is exact for a 0.25 degree raster.';`)
  w()
  w(`-- ── 2. THE FOLD: ONE BODY ANSWERS "WHERE IS THE WATER, AND HOW FAR" ────────────────────────────`)
  w(`-- voyage.water_snap_nm (0047:199) computed the winning cell at 0047:225-228 and threw the`)
  w(`-- coordinates away, so nothing in SQL could say WHERE a place is reached from. Its body moves`)
  w(`-- down here unchanged but for keeping the point, and water_snap_nm becomes one line over it.`)
  w(`-- NO SIGNATURE MOVES and no function is dropped: the three existing callers (0047:594, 0047:612,`)
  w(`-- and voyage.assert_paths_water) are untouched. This is what makes the headline cross-check`)
  w(`-- possible — the Node generator's column against the SQL rule, all ${ports.length} rows, below.`)
  w(`create or replace function voyage.water_roadstead(p_lat numeric, p_lon numeric)`)
  w(`returns table (nm numeric, lat numeric, lon numeric)`)
  w(`language plpgsql`)
  w(`stable`)
  w(`security definer`)
  w(`set search_path = public, pg_temp`)
  w(`as $wr$`)
  w(`declare`)
  w(`  r public.sea_raster%rowtype;`)
  w(`  v_row int; v_col int; ring int; dr int; dc int; rr int; cc int;`)
  w(`  v_best numeric := null;`)
  w(`  v_blat numeric; v_blon numeric;`)
  w(`  v_clat numeric; v_clon numeric;`)
  w(`  v_nm numeric;`)
  w(`begin`)
  w(`  select * into r from public.sea_raster where id = 1;`)
  w(`  v_row := least(r.rows - 1, greatest(0, floor((90 - p_lat) / r.cell_deg)::int));`)
  w(`  v_col := ((floor((p_lon + 180) / r.cell_deg)::int % r.cols) + r.cols) % r.cols;`)
  w(`  -- A POINT WHOSE OWN CELL IS SAILABLE WATER IS ITS OWN ROADSTEAD, at zero distance. Not the`)
  w(`  -- centre of that cell: the centre can lie up to 10.6 nm away, and a helper line whose length`)
  w(`  -- is not the measured snap is a picture of a number nothing computed (src/chart/route.ts:8-12).`)
  w(`  if get_bit(r.cells, (v_row * r.cols + v_col) * r.bits_per_cell) = 1 then`)
  w(`    nm := 0; lat := p_lat; lon := p_lon; return next; return;`)
  w(`  end if;`)
  w(`  for ring in 1 .. 12 loop`)
  w(`    for dr in -ring .. ring loop`)
  w(`      rr := v_row + dr;`)
  w(`      continue when rr < 0 or rr >= r.rows;`)
  w(`      for dc in -ring .. ring loop`)
  w(`        continue when greatest(abs(dr), abs(dc)) <> ring;`)
  w(`        cc := ((v_col + dc) % r.cols + r.cols) % r.cols;`)
  w(`        if get_bit(r.cells, (rr * r.cols + cc) * r.bits_per_cell) = 1 then`)
  w(`          v_clat := 90 - (rr + 0.5) * r.cell_deg;`)
  w(`          v_clon := -180 + (cc + 0.5) * r.cell_deg;`)
  w(`          v_nm := voyage.gc_distance_nm(p_lat::float8, p_lon::float8, v_clat::float8, v_clon::float8)::numeric;`)
  w(`          if v_best is null or v_nm < v_best then`)
  w(`            v_best := v_nm; v_blat := v_clat; v_blon := v_clon;`)
  w(`          end if;`)
  w(`        end if;`)
  w(`      end loop;`)
  w(`    end loop;`)
  w(`    exit when v_best is not null;`)
  w(`  end loop;`)
  w(`  -- 999 is 0047's own answer for "no water within 12 rings", kept so the fold changes no`)
  w(`  -- behaviour; there is no point to report with it, and the caller gets a null coordinate.`)
  w(`  nm := coalesce(v_best, 999); lat := v_blat; lon := v_blon; return next;`)
  w(`end $wr$;`)
  w()
  w(`revoke all on function voyage.water_roadstead(numeric, numeric) from public, anon, authenticated;`)
  w()
  w(`-- The same signature, the same answer, one line. Every existing caller is untouched, and there`)
  w(`-- is now exactly ONE body deciding where the nearest water is.`)
  w(`create or replace function voyage.water_snap_nm(p_lat numeric, p_lon numeric)`)
  w(`returns numeric`)
  w(`language sql`)
  w(`stable`)
  w(`security definer`)
  w(`set search_path = public, pg_temp`)
  w(`as $ws$`)
  w(`  select nm from voyage.water_roadstead(p_lat, p_lon)`)
  w(`$ws$;`)
  w()
  w(`revoke all on function voyage.water_snap_nm(numeric, numeric) from public, anon, authenticated;`)
  w()
}

if (waterMoved) {
  w(`-- ── The raster, superseding the applied one ────────────────────────────────────────────────────`)
  w(`-- Same shape, same LSB-first packing, same two bits per cell (bit 0 SEA, bit 1 POLAR). An`)
  w(`-- UPDATE, not an insert: 0046's row is the one row, and this file rewrites what is in it.`)
  w(`update public.sea_raster`)
  w(`   set cols = ${COLS}, rows = ${ROWS}, cell_deg = ${CELL_DEG}, bits_per_cell = ${BITS},`)
  w(`       cells = decode('${b64}', 'base64')`)
  w(` where id = 1;`)
  w()
} else {
  w(`-- ── The raster is NOT rewritten ────────────────────────────────────────────────────────────────`)
  w(`-- The grid this run built is byte-identical to the row public.sea_raster already holds`)
  w(`-- (${nfmt(newWater)} water cells, ${packed.length} packed bytes). Re-emitting 260 KB of the same base64 would`)
  w(`-- claim a change this file did not make. The self-assert still reads ${CONTROLS.length} named control cells`)
  w(`-- back through get_bit, because "unchanged" is a measurement too.`)
  w()
}
if (seaPatch.size > 0) {
  w(`-- ── The membership patch (0040's public.sea_cells) ─────────────────────────────────────────────`)
  for (const h of healed) {
    w(`--   (${h.lat.toFixed(3)}, ${h.lon.toFixed(3)}) was land when 0040 was cut; it is water now and joins ${h.sea}.`)
  }
  for (const [row, bytes] of [...seaPatch.entries()].sort((a, b) => a[0] - b[0])) {
    w(`update public.sea_cells set seas = decode('${b64Row(bytes)}', 'base64') where row_idx = ${row};`)
  }
  w()
}
w(`-- ── 3. THE ROADSTEADS AND THE SAILED DISTANCES BETWEEN THEM ────────────────────────────────────`)
w(`-- Replaced whole rather than merged — the 0052:92-94 precedent, exactly. Every figure in the`)
w(`-- table comes from ONE pass over ONE raster, and a half-updated table would be two authorities`)
w(`-- for one distance. \`reaches\` is now measured ROADSTEAD to ROADSTEAD, because that is the`)
w(`-- passage cmd.do_sail sells after this file: a table still quoting quay to quay would advertise`)
w(`-- a passage the mover refuses, which is the very thing 0047:445-448 forbids.`)
w(`delete from public.sea_reaches;`)
w()
w(`insert into public.sea_reaches (port_id, code, snap_nm, roadstead_lat, roadstead_lon, reaches)`)
w(`select p.id, v.code, v.snap_nm::numeric, v.rlat::numeric, v.rlon::numeric, v.reaches::jsonb`)
w(`  from (values`)
{
  const rows = ports.map((p) => {
    const m = reaches.get(p.code)
    const obj = {}
    for (const [c, nm] of [...m.entries()].sort()) obj[c] = Number(nm.toFixed(1))
    const r = roads.get(p.code)
    return `    (${q(p.code)}, ${snapNm.get(p.code).toFixed(2)}, ${r.lat.toFixed(3)}, ${r.lon.toFixed(3)}, ${j(obj)})`
  })
  w(rows.join(',\n'))
}
w(`  ) as v(code, snap_nm, rlat, rlon, reaches)`)
w(`  join public.ports p on p.code = v.code;`)
w()
if (INTRODUCES_THE_ROADSTEAD) {
  w(`-- Every row is filled, so the columns stop being optional. A NULL roadstead would mean a port`)
  w(`-- world.snapshot serves without one, and a client with no answer but to compute its own.`)
  w(`alter table public.sea_reaches`)
  w(`  alter column roadstead_lat set not null,`)
  w(`  alter column roadstead_lon set not null;`)
  w()
  w(`-- ── 4. THE MOVER ENDS THE COURSE AT THE ROADS ──────────────────────────────────────────────────`)
  w(`-- Four hunks, all inside THE ONE MOVER. cmd.divert needs none: it composes the onward passage`)
  w(`-- through cmd.issue -> cmd.do_sail, which is the whole point of there being one mover.`)
  w(`select pg_temp.recut('cmd.do_sail(uuid, jsonb)'::regprocedure, false,`)
  w(`  $o0$    select p.lat, p.lon into v_olat, v_olon from public.ports p where p.id = f.port_id;$o0$,`)
  w(`  $o1$    -- 0076 THE ROADSTEAD: she does not put to sea from the quay. Her course begins at the`)
  w(`    -- one point of open water this port is reached from — the same point the chart draws the`)
  w(`    -- dotted helper line to, served on world.snapshot().ports[].roadstead, so the line drawn,`)
  w(`    -- the course proposed and the endpoint verified are one answer and cannot drift.`)
  w(`    select sr.roadstead_lat, sr.roadstead_lon into v_olat, v_olon`)
  w(`      from public.sea_reaches sr where sr.port_id = f.port_id;$o1$,`)
  w(`  $h0$    v_head := coalesce((select snap_nm from public.sea_reaches where port_id = f.port_id), 0) + 25;$h0$,`)
  w(`  $h1$    -- 0076: a FLAT 25 nm, not the snap plus 25. The snap WAS the land-crossing exemption`)
  w(`    -- that let the straightener cut the coast; ending the course at the roads makes it`)
  w(`    -- unnecessary rather than merely smaller. 25 is not a new knob: it is the number already`)
  w(`    -- in this line, and the smallest one here that clears the 21.21 nm of sampling slack the`)
  w(`    -- client's own straightener spends at every path end (one cell diagonal,`)
  w(`    -- src/lib/sea/pathfind.ts:330), so a course the client passed cannot be refused for its`)
  w(`    -- own approach — the failure 0047:195-198 records finding the expensive way.`)
  w(`    v_head := 25;$h1$,`)
  w(`  $d0$    select p.lat, p.lon into v_dlat, v_dlon from public.ports p where p.id = v_dest;$d0$,`)
  w(`  $d1$    -- 0076 THE ROADSTEAD: she is bound for the roads, not the quay. Every port has a`)
  w(`    -- sea_reaches row (asserted in this file before anything relies on it), so a null here`)
  w(`    -- still means "no such port" and the refusal below is unchanged. voyage.settle then docks`)
  w(`    -- her at dest_port_id on the ETA exactly as it has since 0007 — which is the whole of the`)
  w(`    -- owner's "when the ship arrive at that point, consider it as the ship have landed".`)
  w(`    select sr.roadstead_lat, sr.roadstead_lon into v_dlat, v_dlon`)
  w(`      from public.sea_reaches sr where sr.port_id = v_dest;$d1$,`)
  w(`  $t0$    v_tail := coalesce((select snap_nm from public.sea_reaches where port_id = v_dest), 0) + 25;$t0$,`)
  w(`  $t1$    -- 0076: the flat 25 nm again, for the reason written on the head allowance above.`)
  w(`    v_tail := 25;$t1$);`)
  w()
  w(`-- ── 5. THE LAND GUARD TAKES THE SAME ALLOWANCE — AND GRANDFATHERS WHAT IT MUST ─────────────────`)
  w(`-- Without this hunk the guard would keep the hole this file just closed. With it and nothing`)
  w(`-- else, it would FAIL A PASSAGE A PLAYER LEGITIMATELY BOUGHT: voyages.path, total_nm and`)
  w(`-- speed_profile are frozen at departure (0047:453-500), so a fleet already at sea finishes the`)
  w(`-- voyage she paid for — over a course that began at her QUAY under the old allowance. The`)
  w(`-- column that says which rule she was admitted under already exists and is voyages.departed_at`)
  w(`-- (0006:63); the cutoff is the instant THIS FILE APPLIED, written in below. Legacy-converted`)
  w(`-- paths are still skipped and still counted, exactly as before.`)
  w(`-- An OPEN-WATER end keeps its MEASURED snap on either side of the cutoff, because cmd.do_sail`)
  w(`-- still grants it: a divert can lawfully cut a course inside a port's approach, and the guard`)
  w(`-- must judge by the rule the voyage was admitted under.`)
  w(`select pg_temp.recut('voyage.assert_paths_water()'::regprocedure, false,`)
  w(`  $g0$    v_head := coalesce((select sr.snap_nm from public.sea_reaches sr where sr.port_id = v.origin_port_id),`)
  w(`                       voyage.water_snap_nm((v_course->0->>0)::numeric, (v_course->0->>1)::numeric)) + 25;`)
  w(`    v_tail := coalesce((select sr.snap_nm from public.sea_reaches sr where sr.port_id = v.dest_port_id),`)
  w(`                       voyage.water_snap_nm((v_course->(jsonb_array_length(v_course)-1)->>0)::numeric,`)
  w(`                                            (v_course->(jsonb_array_length(v_course)-1)->>1)::numeric)) + 25;$g0$,`)
  w(`  format($g1$    -- 0076 THE ROADSTEAD. A course ORDERED FROM THIS INSTANT ON begins and ends at a`)
  w(`    -- roadstead, which is open water, so a port end gets the flat 25 nm of sampling slack and`)
  w(`    -- not the snap on top of it. A voyage ordered BEFORE it began at the quay and was admitted`)
  w(`    -- under snap + 25; judging her by a rule she was never sold would fail a passage a player`)
  w(`    -- legitimately bought (docs/DESIGN_ROADSTEAD.md 7). voyages.departed_at is the column that`)
  w(`    -- already answers which of the two she is.`)
  w(`    if v.origin_port_id is not null and v.departed_at >= %L::timestamptz then`)
  w(`      v_head := 25;`)
  w(`    else`)
  w(`      v_head := coalesce((select sr.snap_nm from public.sea_reaches sr where sr.port_id = v.origin_port_id),`)
  w(`                         voyage.water_snap_nm((v_course->0->>0)::numeric, (v_course->0->>1)::numeric)) + 25;`)
  w(`    end if;`)
  w(`    if v.dest_port_id is not null and v.departed_at >= %L::timestamptz then`)
  w(`      v_tail := 25;`)
  w(`    else`)
  w(`      v_tail := coalesce((select sr.snap_nm from public.sea_reaches sr where sr.port_id = v.dest_port_id),`)
  w(`                         voyage.water_snap_nm((v_course->(jsonb_array_length(v_course)-1)->>0)::numeric,`)
  w(`                                              (v_course->(jsonb_array_length(v_course)-1)->>1)::numeric)) + 25;`)
  w(`    end if;$g1$, v_cutoff, v_cutoff))`)
  w(`  from (select now()::text as v_cutoff) c;`)
  w()
  w(`-- ── 6. THE WIRE CARRIES IT ─────────────────────────────────────────────────────────────────────`)
  w(`-- world.snapshot() is the static world: ONE call, cached hard by the client (0009:19), already`)
  w(`-- the chart's only source of ports. world.reach(p_from) was measured and rejected as the home —`)
  w(`-- it is per-port, and the chart would need ${ports.length} calls to draw one layer. The correlated`)
  w(`-- subselect is the shape 0067 used for \`buildings\`, so the FROM clause does not move and the`)
  w(`-- slice is one hunk. Never null: every port has a sea_reaches row and this file asserts it`)
  w(`-- below, so there is no null arm for a client to reason about.`)
  w(`-- Deliberately NOT served: the raster row/col. The client already has the raster`)
  w(`-- (world.sea_raster); cell indices beside coordinates would be a second spelling of one fact.`)
  w(`select pg_temp.recut('world.snapshot()'::regprocedure, false,`)
  w(`  $w0$        'kind', p.kind, 'approach', p.approach,$w0$,`)
  w(`  $w1$        'kind', p.kind, 'approach', p.approach,`)
  w(`        'roadstead', (select jsonb_build_object(`)
  w(`                        'lat', sr.roadstead_lat, 'lon', sr.roadstead_lon, 'nm', sr.snap_nm)`)
  w(`                       from public.sea_reaches sr where sr.port_id = p.id),$w1$);`)
  w()
  w(`-- An assumed grant is how a read wall came down in 0018 and had to be rebuilt in 0023.`)
  w(`-- Re-issued explicitly for the one function a client calls, and asserted unmoved below.`)
  w(`revoke all on function world.snapshot() from public, anon;`)
  w(`grant execute on function world.snapshot() to authenticated;`)
  w(`revoke all on function cmd.do_sail(uuid, jsonb) from public, anon, authenticated;`)
  w(`revoke all on function voyage.assert_paths_water() from public, anon, authenticated;`)
  w()
}

// ── THE SELF-ASSERT ────────────────────────────────────────────────────────────────────────────
w(`-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────`)
w(`do $selfassert$`)
w(`declare`)
w(`  r          public.sea_raster%rowtype;`)
w(`  c_probe    constant uuid := '00000000-${SHORT}-4000-8000-000000000001';`)
w(`  -- The Lisbon -> Cadiz course this run's own pathfinder produced, ROADSTEAD to ROADSTEAD.`)
w(`  c_course   constant jsonb := ${j(pathJson(lisCad.path))}::jsonb;`)
w(`  -- and the course the PROBE sails: ${LIS.code} to ${probe.code}, whose roadstead lies ${snapNm.get(probe.code).toFixed(2)} nm off her`)
w(`  -- quay — further than course_join_nm, which is what makes the destination hunk provable.`)
w(`  c_probe_course constant jsonb := ${j(pathJson(lisProbe.path))}::jsonb;`)
w(`  c_brs_ams  constant jsonb := ${j(pathJson(brsAms.path))}::jsonb;`)
w(`  v_n        int;`)
w(`  v_bad      int;`)
w(`  v_far      int;`)
w(`  v_ports    int;`)
w(`  v_missing  int;`)
w(`  v_grants   int;`)
w(`  v_nm       numeric;`)
w(`  v_ref      text;`)
w(`  v_isthmus  text;`)
w(`  v_snap     numeric;`)
w(`  v_road     jsonb;`)
w(`  v_def      text;`)
w(`  v_before   text;`)
w(`  v_acl_b    text;`)
w(`  v_acl_a    text;`)
w(`  v_pan_lat  numeric; v_pan_lon numeric; v_pan_snap numeric; v_pan_rlat numeric; v_pan_rlon numeric;`)
w(`  v_por_lat  numeric; v_por_lon numeric; v_por_snap numeric; v_por_rlat numeric; v_por_rlon numeric;`)
w(`  v_city_line jsonb; v_road_line jsonb;`)
w(`  v_player   uuid;`)
w(`  v_fleet    uuid;`)
w(`  v_res      jsonb;`)
w(`  v_lat      numeric; v_lon numeric;`)
w(`  v_eta      timestamptz;`)
w(`  v_docked   uuid;`)
w(`  v_status   text;`)
w(`  v_walked   int;`)
w(`begin`)
w(`  -- (a) NOT VACUOUS: the table is populated, and EVERY port has a row. Every check below runs`)
w(`  --     over these rows, and 0049:85 / 0065:4329 already assert this equality — it is asserted`)
w(`  --     again HERE, before anything relies on it, because world.snapshot is about to serve a`)
w(`  --     key that has no null arm.`)
w(`  select count(*) into v_ports from public.ports;`)
w(`  select count(*) into v_n from public.sea_reaches;`)
w(`  if v_ports < 200 or v_n <> v_ports then`)
w(`    raise exception '${SHORT} self-assert FAIL: % reach row(s) for % port(s) — every check below would pass over nothing', v_n, v_ports;`)
w(`  end if;`)
w(`  select count(*) into v_missing from public.ports p`)
w(`   where not exists (select 1 from public.sea_reaches sr where sr.port_id = p.id);`)
w(`  if v_missing <> 0 then`)
w(`    raise exception '${SHORT} self-assert FAIL: % port(s) carry no sea_reaches row, so world.snapshot would serve them a null roadstead', v_missing;`)
w(`  end if;`)
w()
w(`  -- (b) THE LINE DRAWN IS THE DISTANCE MEASURED. The chart draws the helper line from the quay`)
w(`  --     to the roadstead and prints snap_nm beside it; if those are two numbers, the picture is`)
w(`  --     about a quantity nothing computed (src/chart/route.ts:8-12). 0.01 nm is the rounding of`)
w(`  --     snap_nm's own two decimal places, not a tolerance for error.`)
w(`  select count(*) into v_bad`)
w(`    from public.sea_reaches sr join public.ports p on p.id = sr.port_id`)
w(`   where abs(voyage.gc_distance_nm(p.lat::float8, p.lon::float8,`)
w(`              sr.roadstead_lat::float8, sr.roadstead_lon::float8)::numeric - sr.snap_nm) > 0.01;`)
w(`  if v_bad <> 0 then`)
w(`    raise exception '${SHORT} self-assert FAIL: % place(s) whose helper line is not snap_nm long — the line drawn would not be the distance measured', v_bad;`)
w(`  end if;`)
w()
w(`  -- (c) A PORT ON ITS OWN WATER IS ITS OWN ROADSTEAD — and that is not the whole table.`)
w(`  select count(*) into v_bad`)
w(`    from public.sea_reaches sr join public.ports p on p.id = sr.port_id`)
w(`   where sr.snap_nm = 0 and (sr.roadstead_lat <> p.lat or sr.roadstead_lon <> p.lon);`)
w(`  if v_bad <> 0 then`)
w(`    raise exception '${SHORT} self-assert FAIL: % place(s) snap 0 nm and yet hold a roadstead off the quay', v_bad;`)
w(`  end if;`)
w(`  select count(*) into v_far from public.sea_reaches where snap_nm > 0;`)
w(`  if v_far < 100 then`)
w(`    raise exception '${SHORT} self-assert FAIL: only % place(s) hold a roadstead off the quay — ${offQuay} were measured, and a table of quay coordinates would pass (b) and (c) vacuously', v_far;`)
w(`  end if;`)
w()
w(`  -- (d) EVERY ROADSTEAD STANDS ON SAILABLE WATER, asked of the raster itself rather than of the`)
w(`  --     generator that wrote the column.`)
w(`  select count(*) into v_bad from public.sea_reaches sr`)
w(`   where voyage.water_snap_nm(sr.roadstead_lat, sr.roadstead_lon) <> 0;`)
w(`  if v_bad <> 0 then`)
w(`    raise exception '${SHORT} self-assert FAIL: % roadstead(s) do not stand on sailable water', v_bad;`)
w(`  end if;`)
w()
w(`  -- (e) THE GENERATOR AND THE SQL ARE ONE RULE. This is why water_snap_nm's body was folded`)
w(`  --     down: a cross-implementation check over every row, not a re-read of what was written.`)
w(`  select count(*) into v_bad`)
w(`    from public.sea_reaches sr join public.ports p on p.id = sr.port_id`)
w(`   cross join lateral voyage.water_roadstead(p.lat, p.lon) wr`)
w(`   where wr.lat <> sr.roadstead_lat or wr.lon <> sr.roadstead_lon;`)
w(`  if v_bad <> 0 then`)
w(`    raise exception '${SHORT} self-assert FAIL: % row(s) where the seeded roadstead POINT is not what voyage.water_roadstead answers — the Node generator and the SQL rule have drifted', v_bad;`)
w(`  end if;`)
w(`  -- and the DISTANCE, to the two decimal places snap_nm is stored at. The first draft of this`)
w(`  -- check compared the two exactly and went red on all ${offQuay} off-quay rows on its own first`)
w(`  -- apply: water_roadstead answers in full float precision and the column keeps two decimals.`)
w(`  -- The tolerance is that rounding, not room for a disagreement.`)
w(`  select count(*) into v_bad`)
w(`    from public.sea_reaches sr join public.ports p on p.id = sr.port_id`)
w(`   cross join lateral voyage.water_roadstead(p.lat, p.lon) wr`)
w(`   where abs(wr.nm - sr.snap_nm) > 0.01;`)
w(`  if v_bad <> 0 then`)
w(`    raise exception '${SHORT} self-assert FAIL: % row(s) where the seeded snap_nm is not what voyage.water_roadstead measures', v_bad;`)
w(`  end if;`)
w()
w(`  -- (f) POSITIVE CONTROL #1 for (b): collapse ONE roadstead back onto its own quay — the exact`)
w(`  --     regression this design fears — and require (b) to find it, EXACTLY ONCE. Rolled back.`)
w(`  begin`)
w(`    update public.sea_reaches sr`)
w(`       set roadstead_lat = p.lat, roadstead_lon = p.lon`)
w(`      from public.ports p`)
w(`     where p.id = sr.port_id`)
w(`       and sr.code = (select code from public.sea_reaches order by snap_nm desc, code limit 1);`)
w(`    select count(*) into v_bad`)
w(`      from public.sea_reaches sr join public.ports p on p.id = sr.port_id`)
w(`     where abs(voyage.gc_distance_nm(p.lat::float8, p.lon::float8,`)
w(`                sr.roadstead_lat::float8, sr.roadstead_lon::float8)::numeric - sr.snap_nm) > 0.01;`)
w(`    if v_bad <> 1 then`)
w(`      raise exception '${SHORT} self-assert FAIL: a roadstead collapsed onto its own quay was found % time(s), expected exactly 1 — check (b) cannot bite and every green above it is vacuous', v_bad;`)
w(`    end if;`)
w(`    raise exception '__PROBE_ROLLBACK__' using errcode = 'P0001';`)
w(`  exception when others then`)
w(`    if sqlerrm <> '__PROBE_ROLLBACK__' then raise; end if;`)
w(`  end;`)
w()
w(`  -- (g) THE HEADLINE, AND ITS OWN POSITIVE CONTROL — the isthmus of Panama.`)
w(`  select p.lat, p.lon, sr.snap_nm, sr.roadstead_lat, sr.roadstead_lon`)
w(`    into v_pan_lat, v_pan_lon, v_pan_snap, v_pan_rlat, v_pan_rlon`)
w(`    from public.ports p join public.sea_reaches sr on sr.port_id = p.id where p.code = ${q(PAN.code)};`)
w(`  select p.lat, p.lon, sr.snap_nm, sr.roadstead_lat, sr.roadstead_lon`)
w(`    into v_por_lat, v_por_lon, v_por_snap, v_por_rlat, v_por_rlon`)
w(`    from public.ports p join public.sea_reaches sr on sr.port_id = p.id where p.code = ${q(POR.code)};`)
w(`  if v_pan_rlat is null or v_por_rlat is null then`)
w(`    raise exception '${SHORT} self-assert FAIL: ${PAN.code} or ${POR.code} carries no roadstead, so the headline proves nothing';`)
w(`  end if;`)
w(`  -- CONTROL, MUST STAY GREEN: the OLD quay-to-quay line is still ACCEPTED under the OLD`)
w(`  -- allowance. If it ever stops being accepted, the defect this file claims to close was not`)
w(`  -- there and the repair below proves nothing — so the file says so instead of shipping a boast.`)
w(`  v_city_line := jsonb_build_array(jsonb_build_array(v_pan_lat, v_pan_lon),`)
w(`                                   jsonb_build_array(v_por_lat, v_por_lon));`)
w(`  if voyage.path_refusal(v_city_line, v_pan_lat, v_pan_lon, v_por_lat, v_por_lon,`)
w(`                         public.wc_num('course_join_nm'),`)
w(`                         v_pan_snap + 25, v_por_snap + 25) is not null then`)
w(`    raise exception '${SHORT} self-assert FAIL: the quay-to-quay isthmus line is ALREADY refused under the old allowance — the defect this file claims to close is not there';`)
w(`  end if;`)
w(`  -- THE REPAIR: the same passage between the two ROADSTEADS, under the flat allowance.`)
w(`  v_road_line := jsonb_build_array(jsonb_build_array(v_pan_rlat, v_pan_rlon),`)
w(`                                   jsonb_build_array(v_por_rlat, v_por_rlon));`)
w(`  v_isthmus := voyage.path_refusal(v_road_line, v_pan_rlat, v_pan_rlon, v_por_rlat, v_por_rlon,`)
w(`                                   public.wc_num('course_join_nm'), 25, 25);`)
w(`  if v_isthmus is null or v_isthmus not like 'E_LAND%' then`)
w(`    raise exception '${SHORT} self-assert FAIL: the line from the ${PAN.name} roads to the ${POR.name} roads is not refused as E_LAND (got %) — the isthmus is open and the short way across it is still purchasable', coalesce(v_isthmus, 'ACCEPTED');`)
w(`  end if;`)
w(`  -- and the table agrees with the law: the reach is the long way round now.`)
w(`  v_nm := (select (reaches->>${q(POR.code)})::numeric from public.sea_reaches where code = ${q(PAN.code)});`)
w(`  if v_nm is null or v_nm < 5000 then`)
w(`    raise exception '${SHORT} self-assert FAIL: ${PAN.code}->${POR.code} is served at % nm — the quay would advertise a passage the mover refuses', v_nm;`)
w(`  end if;`)
w()
w(`  -- (h) THE WIRE CARRIES IT, FOR EVERY PORT.`)
w(`  select count(*) into v_bad`)
w(`    from jsonb_array_elements(world.snapshot()->'ports') p`)
w(`   where p->'roadstead' is null or p->'roadstead'->>'lat' is null`)
w(`      or p->'roadstead'->>'lon' is null or p->'roadstead'->>'nm'  is null;`)
w(`  if v_bad <> 0 then`)
w(`    raise exception '${SHORT} self-assert FAIL: % served port(s) carry no roadstead — a client would have to compute one', v_bad;`)
w(`  end if;`)
w(`  select p->'roadstead' into v_road from jsonb_array_elements(world.snapshot()->'ports') p`)
w(`   where p->>'code' = ${q(AMS.code)};`)
w(`  if (v_road->>'nm')::numeric <= 20 then`)
w(`    raise exception '${SHORT} self-assert FAIL: ${AMS.name} is served a roadstead % nm off the quay — ${snapNm.get(AMS.code).toFixed(2)} was measured, and a table of zeroes serves fine and draws nothing', v_road->>'nm';`)
w(`  end if;`)
w(`  if (v_road->>'lat')::numeric <> (select roadstead_lat from public.sea_reaches where code = ${q(AMS.code)}) then`)
w(`    raise exception '${SHORT} self-assert FAIL: the served roadstead is not the stored one';`)
w(`  end if;`)
w(`  -- NOTHING ELSE MOVED on the wire: the re-cut body is its own pre-image with exactly this hunk`)
w(`  -- swapped in, and the grants are the ones it had.`)
w(`  select def, acl into v_before, v_acl_b from defs_before_${SHORT} where fn = 'world.snapshot()';`)
w(`  v_def := pg_get_functiondef('world.snapshot()'::regprocedure);`)
w(`  select p.proacl::text into v_acl_a from pg_proc p where p.oid = 'world.snapshot()'::regprocedure;`)
w(`  if position('roadstead' in v_before) <> 0 then`)
w(`    raise exception '${SHORT} self-assert FAIL: the pre-image already served a roadstead — this slice is a no-op';`)
w(`  end if;`)
w(`  if replace(v_def,`)
w(`       $x$        'kind', p.kind, 'approach', p.approach,`)
w(`        'roadstead', (select jsonb_build_object(`)
w(`                        'lat', sr.roadstead_lat, 'lon', sr.roadstead_lon, 'nm', sr.snap_nm)`)
w(`                       from public.sea_reaches sr where sr.port_id = p.id),$x$,`)
w(`       $y$        'kind', p.kind, 'approach', p.approach,$y$) <> v_before then`)
w(`    raise exception '${SHORT} self-assert FAIL: world.snapshot is not its own pre-image with exactly the declared hunk swapped in';`)
w(`  end if;`)
w(`  if v_acl_a is distinct from v_acl_b then`)
w(`    raise exception '${SHORT} self-assert FAIL: world.snapshot grants moved (% -> %)', v_acl_b, v_acl_a;`)
w(`  end if;`)
w()
w(`  -- (i) A REAL HOUSE SAILS, AND HER COURSE STARTS AT THE ROADS — then she docks AT THE PORT.`)
w(`  --     The 0075/0063 probe shape, rolled back. This is the owner's sentence PROVEN rather than`)
w(`  --     argued, with voyage.settle untouched.`)
w(`  begin`)
w(`    v_player := public.new_house(c_probe, 'Casa das Roadas', 'PRT');`)
w(`    perform cmd.assume_identity(c_probe);`)
w(`    select id into v_fleet from public.fleets where player_id = v_player;`)
w(`    -- Pinned for the reason 0037, 0063 and 0075 pin it: a hazard drawn on this passage would`)
w(`    -- delay her and this probe would be measuring the dice rather than the geometry.`)
w(`    update public.world_config set value = to_jsonb(0.0) where key = 'hazard_p_max';`)
w(`    perform cmd.do_provision(v_fleet, jsonb_build_object('mode', 'FULL'));`)
w(`    -- A REFUSAL IS AN ENVELOPE, NOT AN EXCEPTION (0008).`)
w(`    v_res := cmd.issue(v_fleet, 'SAIL TO ${probe.code}', null, c_probe_course);`)
w(`    if coalesce(v_res->>'ok', 'false') <> 'true' then`)
w(`      raise exception '${SHORT} self-assert FAIL: the probe could not put to sea on a roadstead-to-roadstead course: [%: %]',`)
w(`        v_res->>'error_code', v_res->>'error_message';`)
w(`    end if;`)
w(`    perform cmd.advance(v_fleet);`)
w(`    select (path->0->'a'->>0)::numeric, (path->0->'a'->>1)::numeric, eta`)
w(`      into v_lat, v_lon, v_eta`)
w(`      from public.voyages where fleet_id = v_fleet and status = 'SAILING';`)
w(`    if v_lat is null then`)
w(`      raise exception '${SHORT} self-assert FAIL: the probe never put a voyage to sea, so this proves nothing';`)
w(`    end if;`)
w(`    if v_lat is distinct from (select roadstead_lat from public.sea_reaches where code = ${q(LIS.code)})`)
w(`       or v_lon is distinct from (select roadstead_lon from public.sea_reaches where code = ${q(LIS.code)}) then`)
w(`      raise exception '${SHORT} self-assert FAIL: her course begins at (%, %) and not at ${LIS.name}''s roadstead (%, %) — the mover still departs from the quay',`)
w(`        v_lat, v_lon,`)
w(`        (select roadstead_lat from public.sea_reaches where code = ${q(LIS.code)}),`)
w(`        (select roadstead_lon from public.sea_reaches where code = ${q(LIS.code)});`)
w(`    end if;`)
w(`    select (path->(jsonb_array_length(path)-1)->'b'->>0)::numeric into v_lat`)
w(`      from public.voyages where fleet_id = v_fleet and status = 'SAILING';`)
w(`    if v_lat is distinct from (select roadstead_lat from public.sea_reaches where code = ${q(probe.code)}) then`)
w(`      raise exception '${SHORT} self-assert FAIL: her course ends at % and not at ${probe.name}''s roadstead', v_lat;`)
w(`    end if;`)
w(`    select total_nm into v_nm from public.voyages where fleet_id = v_fleet and status = 'SAILING';`)
w(`    if v_nm is null or v_nm <= 0 then`)
w(`      raise exception '${SHORT} self-assert FAIL: a course of % nm', v_nm;`)
w(`    end if;`)
w(`    -- THE OWNER'S SENTENCE. She reaches the point, and voyage.settle — untouched by this file —`)
w(`    -- docks her AT THE PORT.`)
w(`    perform voyage.settle(v_fleet, v_eta + interval '1 second');`)
w(`    select port_id, status into v_docked, v_status from public.fleets where id = v_fleet;`)
w(`    if v_status <> 'DOCKED' or v_docked is distinct from (select id from public.ports where code = ${q(probe.code)}) then`)
w(`      raise exception '${SHORT} self-assert FAIL: she reached the ${probe.name} roads and is [%] at [%] — arriving at the roadstead must dock her at the port itself',`)
w(`        v_status, coalesce((select code from public.ports where id = v_docked), 'nowhere');`)
w(`    end if;`)
w(`    -- AND THE GUARD WALKS HER. Non-vacuity is the caller's duty (the guard's own header).`)
w(`    select voyages_walked into v_walked from voyage.assert_paths_water();`)
w(`    if v_walked < 1 then`)
w(`      raise exception '${SHORT} self-assert FAIL: the land guard walked % course(s) — it is asserting over nothing', v_walked;`)
w(`    end if;`)
w(`    -- POSITIVE CONTROL #2 FOR THE GRANDFATHER CLAUSE, both directions on ONE planted voyage:`)
w(`    -- the quay-to-quay isthmus passage, which is legal under the OLD allowance and land under`)
w(`    -- the NEW one. Dated BEFORE this migration it must be walked and accepted; dated after, the`)
w(`    -- same row must be refused as land.`)
w(`    insert into public.voyages (fleet_id, player_id, path, total_nm, speed_profile,`)
w(`                                departed_at, eta, status, last_settled_day, origin_port_id, dest_port_id)`)
w(`    select v_fleet, v_player, s.segs,`)
w(`           (select sum((x->>'nm')::numeric) from jsonb_array_elements(s.segs) x),`)
w(`           '[4.5]'::jsonb, timestamptz '2000-01-01', timestamptz '2000-01-02',`)
w(`           'ARRIVED', 1,`)
w(`           (select id from public.ports where code = ${q(PAN.code)}),`)
w(`           (select id from public.ports where code = ${q(POR.code)})`)
w(`      from (select voyage.segments_from_course(v_city_line) as segs) s;`)
w(`    select voyages_walked into v_walked from voyage.assert_paths_water();`)
w(`    if v_walked < 2 then`)
w(`      raise exception '${SHORT} self-assert FAIL: the grandfathered isthmus voyage was not walked (% course(s)) — the guard skipped it rather than accepting it', v_walked;`)
w(`    end if;`)
w(`    update public.voyages set departed_at = now(), eta = now() + interval '1 hour'`)
w(`     where fleet_id = v_fleet and status = 'ARRIVED' and dest_port_id = (select id from public.ports where code = ${q(POR.code)});`)
w(`    begin`)
w(`      perform * from voyage.assert_paths_water();`)
w(`      raise exception '${SHORT} self-assert FAIL: the SAME isthmus course dated after this migration was still accepted — the guard kept the hole this file closed';`)
w(`    exception when others then`)
w(`      if sqlerrm like '${SHORT} self-assert FAIL%' then raise; end if;`)
w(`      if position('E_LAND' in sqlerrm) = 0 then`)
w(`        raise exception '${SHORT} self-assert FAIL: the guard refused the post-cutoff isthmus voyage for the wrong reason: %', sqlerrm;`)
w(`      end if;`)
w(`    end;`)
w(`    raise exception '__PROBE_ROLLBACK__' using errcode = 'P0001';`)
w(`  exception when others then`)
w(`    if sqlerrm <> '__PROBE_ROLLBACK__' then raise; end if;`)
w(`  end;`)
w()
w(`  -- (j) POSTURE. Both halves, per README §3: a TABLE write grant and an EXECUTE on a`)
w(`  --     SECURITY DEFINER writer are two different doors, and 0018 exists because the first read`)
w(`  --     an honest zero for seventeen migrations while the second was open.`)
w(`  select count(*) into v_grants from public.client_write_grants();`)
w(`  if v_grants <> 0 then raise exception '${SHORT} self-assert FAIL: % client write grant(s)', v_grants; end if;`)
w(`  select count(*) into v_grants from public.client_executable_writers();`)
w(`  if v_grants <> 0 then raise exception '${SHORT} self-assert FAIL: % client-executable writer(s)', v_grants; end if;`)
w(`  if not has_table_privilege('authenticated', 'public.sea_reaches', 'select')`)
w(`     or has_function_privilege('anon', 'voyage.water_roadstead(numeric, numeric)', 'execute')`)
w(`     or has_function_privilege('authenticated', 'voyage.water_roadstead(numeric, numeric)', 'execute')`)
w(`     or has_function_privilege('authenticated', 'voyage.water_snap_nm(numeric, numeric)', 'execute')`)
w(`     or has_function_privilege('anon', 'world.snapshot()', 'execute')`)
w(`     or not has_function_privilege('authenticated', 'world.snapshot()', 'execute') then`)
w(`    raise exception '${SHORT} self-assert FAIL: the grant posture is wrong — the roadstead rule is server-only and the snapshot is the client''s';`)
w(`  end if;`)
w()
w(`  -- ── AND THE TABLE'S OWN PROPERTIES, because this file rewrote every row of it ────────────────`)
w(`  -- (k) THE RASTER IS THERE AND THE BIT ORDER IS THE ONE THE CLIENT PACKS. ${CONTROLS.length} control cells,`)
w(`  --     each a named piece of the world, read through get_bit — the same read the sampler uses.`)
w(`  select * into r from public.sea_raster where id = 1;`)
w(`  if r.cols <> ${COLS} or r.rows <> ${ROWS} or r.bits_per_cell <> ${BITS} or octet_length(r.cells) <> ${packed.length} then`)
w(`    raise exception '${SHORT} self-assert FAIL: the raster is % x % at % bit(s) with % bytes — expected ${COLS} x ${ROWS} at ${BITS} with ${packed.length}', r.cols, r.rows, r.bits_per_cell, octet_length(r.cells);`)
w(`  end if;`)
for (const [name, lat, lon, want] of CONTROLS) {
  const row = Math.min(ROWS - 1, Math.max(0, Math.floor((90 - lat) / CELL_DEG)))
  const col = ((Math.floor((lon + 180) / CELL_DEG) % COLS) + COLS) % COLS
  const bit = (row * COLS + col) * BITS
  w(`  if get_bit(r.cells, ${bit}) <> ${want} then`)
  w(`    raise exception '${SHORT} self-assert FAIL: ${name} (${lat}, ${lon}) reads %, expected ${want}', get_bit(r.cells, ${bit});`)
  w(`  end if;`)
}
w()
w(`  -- (l) EVERY PLACE REACHES EVERY OTHER PLACE, symmetrically. Non-vacuous by the counts`)
w(`  --     themselves: the world cannot hold an island nobody can sail to.`)
w(`  select count(*) into v_bad from public.sea_reaches sr`)
w(`   where (select count(*) from jsonb_object_keys(sr.reaches)) <> v_ports - 1;`)
w(`  if v_bad <> 0 then`)
w(`    raise exception '${SHORT} self-assert FAIL: % place(s) do not reach every other place', v_bad;`)
w(`  end if;`)
w(`  select count(*) into v_bad`)
w(`    from public.sea_reaches a`)
w(`   cross join lateral jsonb_each_text(a.reaches) e(code, nm)`)
w(`    join public.sea_reaches b on b.code = e.code`)
w(`   where (b.reaches->>a.code)::numeric is distinct from e.nm::numeric;`)
w(`  if v_bad <> 0 then`)
w(`    raise exception '${SHORT} self-assert FAIL: % asymmetric pair reading(s)', v_bad;`)
w(`  end if;`)
w()
w(`  -- (m) NO SAILED DISTANCE IS SHORTER THAN THE GREAT CIRCLE — and after this file the great`)
w(`  --     circle it must clear is the one BETWEEN THE ROADSTEADS, because that is what was sailed.`)
w(`  --     Comparing against the quay-to-quay line would be comparing two different passages.`)
w(`  select count(*) into v_bad`)
w(`    from public.sea_reaches a`)
w(`   cross join lateral jsonb_each_text(a.reaches) e(code, nm)`)
w(`    join public.sea_reaches b on b.code = e.code`)
w(`   where a.code < e.code`)
w(`     and e.nm::numeric < voyage.gc_distance_nm(a.roadstead_lat::float8, a.roadstead_lon::float8,`)
w(`                                               b.roadstead_lat::float8, b.roadstead_lon::float8) * 0.995;`)
w(`  if v_bad <> 0 then`)
w(`    raise exception '${SHORT} self-assert FAIL: % pair(s) sail shorter than the great circle between their roadsteads', v_bad;`)
w(`  end if;`)
w()
w(`  -- (n) THE WORLD'S THREE STANDING FACTS, unmoved by the reshape: no Arctic road, no Suez, no`)
w(`  --     Panama. If ending courses at the roads had quietly opened one of them, this bites.`)
w(`  v_nm := (select (reaches->>${q(NAG.code)})::numeric from public.sea_reaches where code = ${q(LIS.code)});`)
w(`  if v_nm is null or v_nm < 12000 then`)
w(`    raise exception '${SHORT} self-assert FAIL: ${LIS.code}->${NAG.code} is % nm — under 12,000 means the Arctic is open again (the leg graph served 7,565 over the pole)', v_nm;`)
w(`  end if;`)
w(`  if (select (reaches->>${q(ADE.code)})::numeric from public.sea_reaches where code = ${q(ALX.code)}) < 9000 then`)
w(`    raise exception '${SHORT} self-assert FAIL: ${ALX.code}->${ADE.code} under 9,000 nm — a Suez Canal three centuries early';`)
w(`  end if;`)
w(`  if (select (reaches->>${q(ACA.code)})::numeric from public.sea_reaches where code = ${q(VER.code)}) < 9000 then`)
w(`    raise exception '${SHORT} self-assert FAIL: ${VER.code}->${ACA.code} under 9,000 nm — a Panama Canal three centuries early';`)
w(`  end if;`)
w(`  select snap_nm into v_snap from public.sea_reaches where code = ${q(BRS.code)};`)
w(`  if v_snap is null or v_snap > 20 then`)
w(`    raise exception '${SHORT} self-assert FAIL: Bristol snaps % nm to sailable water — over 20 means the Severn is land again (it was 64.55 nm to Lyme Bay)', v_snap;`)
w(`  end if;`)
w()
w(`  -- (o) THE MEASURE AND THE LAW, on two real courses this run's own pathfinder produced between`)
w(`  --     the very roadsteads the table now holds — accepted under the FLAT allowance, which is`)
w(`  --     the allowance the re-cut mover grants. A course that needed more would mean the`)
w(`  --     roadstead did not remove the need for the snap exemption.`)
w(`  v_ref := voyage.path_refusal(c_course,`)
w(`             (select roadstead_lat from public.sea_reaches where code = ${q(LIS.code)}),`)
w(`             (select roadstead_lon from public.sea_reaches where code = ${q(LIS.code)}),`)
w(`             (select roadstead_lat from public.sea_reaches where code = ${q(CAD.code)}),`)
w(`             (select roadstead_lon from public.sea_reaches where code = ${q(CAD.code)}),`)
w(`             public.wc_num('course_join_nm'), 25, 25);`)
w(`  if v_ref is not null then`)
w(`    raise exception '${SHORT} self-assert FAIL: the real ${LIS.name}->${CAD.name} roads-to-roads course was refused under the flat 25 nm allowance: %', v_ref;`)
w(`  end if;`)
w(`  v_ref := voyage.path_refusal(c_brs_ams,`)
w(`             (select roadstead_lat from public.sea_reaches where code = ${q(BRS.code)}),`)
w(`             (select roadstead_lon from public.sea_reaches where code = ${q(BRS.code)}),`)
w(`             (select roadstead_lat from public.sea_reaches where code = ${q(AMS.code)}),`)
w(`             (select roadstead_lon from public.sea_reaches where code = ${q(AMS.code)}),`)
w(`             public.wc_num('course_join_nm'), 25, 25);`)
w(`  if v_ref is not null then`)
w(`    raise exception '${SHORT} self-assert FAIL: the real ${BRS.name}->${AMS.name} roads-to-roads course was refused under the flat 25 nm allowance: %', v_ref;`)
w(`  end if;`)
w(`  -- the negative control the sampler has carried since 0046: a straight line across Iberia.`)
w(`  v_ref := voyage.path_refusal(`)
w(`             jsonb_build_array(jsonb_build_array(${LIS.lat}, ${LIS.lon}), jsonb_build_array(${BCN.lat}, ${BCN.lon})),`)
w(`             ${LIS.lat}, ${LIS.lon}, ${BCN.lat}, ${BCN.lon}, 15, 40, 40);`)
w(`  if v_ref is null or v_ref not like 'E_LAND:%' then`)
w(`    raise exception '${SHORT} self-assert FAIL: a straight ${LIS.name}->${BCN.name} line across Iberia was NOT refused as land (got [%])', coalesce(v_ref, 'null');`)
w(`  end if;`)
w()
w(`  raise notice '${SHORT} self-assert ok: A HARBOUR IS REACHED FROM ITS ROADS. % places carry a roadstead; ${offQuay} of them lie off the quay (worst ${worst[0][0]} ${worst[0][1].toFixed(2)} nm, ${AMS.code} ${snapNm.get(AMS.code).toFixed(2)} nm) and ${ownWater} stand on their own water at 0 nm and ARE their own roadstead. Every one of them is on sailable water, every one is exactly snap_nm from its quay so the helper line the chart draws is the distance the table measured, and every one equals what voyage.water_roadstead answers for the same coordinate — the Node generator and the SQL rule are one rule now, because water_snap_nm''s body moved down into it. Collapsing one roadstead onto its quay is FOUND, exactly once. The isthmus: ${PAN.code} to ${POR.code} quay-to-quay is still ACCEPTED under the old snap+25 allowance (so the defect was real) and roads-to-roads is refused %, with the table now quoting % nm the long way round. A real house sailed ${LIS.code} to ${probe.code} — whose roadstead lies ${snapNm.get(probe.code).toFixed(2)} nm off her quay, further than the join tolerance, so nothing here would work from the quay — on a roadstead-to-roadstead course; her frozen path BEGAN at the ${LIS.code} roads, ENDED at the ${probe.code} roads, and voyage.settle — untouched — docked her at ${probe.code} itself: the owner''s sentence, proven. The land guard walks her, GRANDFATHERS a pre-0076 isthmus voyage a player would already have bought, and refuses the same course dated after this file. Every place still reaches every other symmetrically and never under the great circle between their roadsteads; the Arctic is shut (${LIS.code}->${NAG.code} % nm), there is no Suez and no Panama; ${CONTROLS.length} raster control cells read back through get_bit; 0 client write grants, 0 client-executable writers.',`)
w(`    v_ports, v_isthmus, (select (reaches->>${q(POR.code)})::numeric from public.sea_reaches where code = ${q(PAN.code)}),`)
w(`    (select (reaches->>${q(NAG.code)})::numeric from public.sea_reaches where code = ${q(LIS.code)});`)
w(`end $selfassert$;`)
w()

const sql = lines.join('\n')
if (sql.includes('\r')) throw new Error('CR found in generated SQL — refuse to emit')
// NEVER OVERWRITE A MIGRATION THAT IS ALREADY ON DISK. Once a file is in the chain it has applied
// somewhere, and rewriting it in place is the D23 defect. The next sea change moves MIGRATION to a
// new version; the emitted SQL is already a supersede (it UPDATEs the raster and replaces the
// reach table), so nothing else has to change.
if (existsSync(OUT)) {
  throw new Error(
    `${OUT} already exists — refusing to rewrite a migration in the chain (supabase/migrations/` +
      `README.md §1: never edit an applied migration). Move the MIGRATION constant at the top of ` +
      `this file to the next version and run again.`,
  )
}
writeFileSync(OUT, sql, 'utf8')
console.log(`\nwrote ${OUT} — ${(sql.length / 1024).toFixed(0)} KiB`)
await db.close()
