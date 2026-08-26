// ═══════════════════════════════════════════════════════════════════════════════════════════════
// build-sea-migration.mjs — writes THE NAVIGABLE SEA, AS DATA. Currently migration 0060.
//
// IT WROTE 0046 FIRST, AND 0046 IS HISTORY NOW. An applied migration is never edited (README §1,
// D23); when the sea moves, this generator emits the NEXT number and that file SUPERSEDES the data
// the last one seeded. So the emit below is a data supersede — it updates public.sea_raster's one
// row and replaces public.sea_reaches — and it deliberately re-cuts NO function: voyage.path_nm
// and voyage.path_refusal were created by 0046 and voyage.sail_refusal was re-cut by 0050, so a
// generator that re-emitted the function bodies it happened to remember would silently roll 0050
// back. The tables and the two 0046 functions are 0046's; only the numbers in them are this file's.
// One constant, MIGRATION, says which file is being written; move it, never the emitted SQL.
//
// §7B — the four questions:
//   CONCEPT      "the one statement of what water connects to what": the navigable raster, and
//                the sailed distance between every pair of places, derived FROM that raster by
//                the one pathfinder (src/lib/sea).
//   LIVES HERE   scripts/, because it is a GENERATOR: it runs the applied chain in PGlite to read
//                the world's own ports (codes and coordinates come from the database, never from
//                a second derivation of them), computes, and emits SQL. The AUTHORITY it emits is
//                the migration; once the newest one applies, the raster row IS the sea.
//   SECOND CALLER  none — it is run by hand when the sea or the ports change, and then a NEW
//                migration is cut (never an edit of an applied one). scripts/build-proof-paths.mjs
//                consumes the same src/lib/sea search, not this file.
//   WRONG SHAPE  if the raster it packs and the raster a browser unpacks could differ. They
//                cannot: both sides are src/lib/sea/grid.ts, and the emitted self-assert round-
//                trips get_bit() against embedded control cells.
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
import { buildSeaGrid, CHANNELS, COLS, ROWS, CELL_DEG, cellLat, cellLon, inIce } from './sea-grid.mjs'
import { packCells, findPath, floodFrom, floodPathTo, gcNm, navFromServed, SEA_BIT, POLAR_BIT } from '../src/lib/sea/index.ts'
import { applyChain, MIGRATIONS_DIR } from './db/apply-chain.mjs'

// The migration this run writes. 0046 was the first; an applied one is history, so this moves and
// the emitted SQL supersedes what the previous number seeded.
const MIGRATION = '20260818000060_forty_harbours_stop_sailing_overland.sql'
const SHORT = MIGRATION.slice(10, 14)
const OUT = path.join(MIGRATIONS_DIR, MIGRATION)
const BITS = 2

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
const TOK = byName('Tokyo')
const PAT = byName('Patras')
const CAG = byName('Cagliari')
// The unmoved controls. NONE of these is one of the harbours this file opens water for, which is
// what makes 'identical to 0.1 nm' worth asserting — a control inside the fixed set would only be
// proving that the fix did nothing.
const BUE = byName('Buenos Aires')
const CLL = byName('Callao')
const RIO = byName('Rio de Janeiro')
const CEB = byName('Cebu')
const CPT = byName('Cape Town')
const JKT = byName('Jakarta')
const VLP = byName('Valparaiso')
const PAN = byName('Panama City')
const POR = byName('Port Royal')

// ── THE SEA THE CHAIN IS ALREADY SERVING ───────────────────────────────────────────────────────
// Read ONCE, here, because every claim this file makes is a DIFFERENCE against it: which cells
// opened, whose snap moved, which pair readings changed and — the one that matters — which did
// NOT. A figure remembered from an earlier probe is not evidence (README §2).
const applied = navFromServed(
  (
    await db.query(`select cols, rows, cell_deg::float8 as cell_deg, bits_per_cell,
                           replace(encode(cells, 'base64'), e'\\n', '') as cells_base64
                      from public.sea_raster where id = 1`)
  ).rows[0],
)
const appliedRows = (
  await db.query('select code, snap_nm::float8 as snap_nm, reaches from public.sea_reaches')
).rows
const appliedSnap = new Map(appliedRows.map((r) => [r.code, r.snap_nm]))
const appliedReach = new Map(appliedRows.map((r) => [r.code, r.reaches]))
if (appliedSnap.size !== ports.length) {
  throw new Error(`the applied chain serves ${appliedSnap.size} reach row(s) for ${ports.length} port(s)`)
}

let opened = 0
let closed = 0
for (let i = 0; i < COLS * ROWS; i++) {
  if (cells[i] && !applied.cells[i]) opened++
  else if (!cells[i] && applied.cells[i]) closed++
}
const appliedWater = applied.cells.reduce((n, c) => n + c, 0)
const newWater = cells.reduce((n, c) => n + c, 0)
console.log(`  raster diff vs the applied one: ${appliedWater} → ${newWater} water cells (+${opened} opened, -${closed} closed)`)

// THIS FILE MAY ONLY OPEN WATER. A migration that CLOSED a cell could strand a fleet already at
// sea on a course that is now land — the served course was computed over the old raster and is
// frozen in public.voyages.path. Opening is safe by construction (a legal course over a raster is
// still legal over a superset of it); closing is not, and needs a migration that deals with the
// fleets on those courses first. See the header's note on the six spilling CHANNELS entries.
if (closed !== 0) {
  throw new Error(`${closed} cell(s) would be CLOSED by this raster — refuse to emit; see the header`)
}

// WHICH CHANNELS ENTRIES ARE THIS FILE'S DOING — derived, not counted by hand. An entry is this
// migration's if at least one cell it forces open was LAND on the raster the chain is serving.
const rowFor = (lat) => Math.min(ROWS - 1, Math.max(0, Math.floor((90 - lat) / CELL_DEG)))
const colFor = (lon) => ((Math.floor((lon + 180) / CELL_DEG) % COLS) + COLS) % COLS
const channelsThisFile = []
for (const ch of CHANNELS) {
  const touched = new Set()
  const mark = (lat, lon) => touched.add(rowFor(lat) * COLS + colFor(lon))
  for (let i = 0; i < ch.points.length; i++) {
    mark(ch.points[i][0], ch.points[i][1])
    if (i + 1 < ch.points.length) {
      const [la, lo] = ch.points[i]
      const [lb, lb2] = ch.points[i + 1]
      const steps = Math.ceil(gcNm(la, lo, lb, lb2) / 5)
      for (let st = 1; st < steps; st++) mark(la + ((lb - la) * st) / steps, lo + ((lb2 - lo) * st) / steps)
    }
  }
  let fresh = 0
  for (const i of touched) if (!applied.cells[i]) fresh++
  if (fresh > 0) channelsThisFile.push({ id: ch.id, name: ch.name, fresh })
}
const CHANNEL_COUNT = CHANNELS.length
const NEW_CHANNELS = channelsThisFile.length
console.log(`  ${NEW_CHANNELS} of ${CHANNEL_COUNT} CHANNELS entries open water this raster did not have: ` +
            channelsThisFile.map((c) => `${c.id}+${c.fresh}`).join(', '))

// ── THE DEFECT: A HARBOUR WITH NO WATER BUYS A CORRIDOR ACROSS ITS OWN COUNTRY ─────────────────
// sea_reaches.snap_nm is what voyage.path_refusal grants a course as its LAND-EXEMPT head
// allowance, so a harbour whose own cell scan-filled as land is handed a straight line over the
// country it stands in. 0052 proved that at Bristol; these are the ones it left.
const OVER = 20
const offenders = ports
  .filter((p) => appliedSnap.get(p.code) > OVER)
  .sort((a, b) => appliedSnap.get(b.code) - appliedSnap.get(a.code))
const fixedSet = new Set(offenders.map((p) => p.code))
console.log(`  ${offenders.length} harbour(s) snapped over ${OVER} nm on the applied raster; worst: ` +
            offenders.slice(0, 4).map((p) => `${p.code} ${appliedSnap.get(p.code).toFixed(2)}`).join(', '))

const stillOver = ports.filter((p) => snapNm.get(p.code) > OVER)
if (stillOver.length > 0) {
  throw new Error(
    `${stillOver.length} harbour(s) STILL snap over ${OVER} nm: ` +
      stillOver.map((p) => `${p.code} ${snapNm.get(p.code).toFixed(2)}`).join(', '),
  )
}
const movedSnap = ports.filter((p) => Math.abs(snapNm.get(p.code) - appliedSnap.get(p.code)) > 0.005)
const straySnap = movedSnap.filter((p) => !fixedSet.has(p.code))
if (straySnap.length > 0) {
  throw new Error(
    `${straySnap.length} harbour(s) whose snap this pass did NOT set out to move, moved: ` +
      straySnap.map((p) => `${p.code} ${appliedSnap.get(p.code).toFixed(2)}→${snapNm.get(p.code).toFixed(2)}`).join(', '),
  )
}
if (movedSnap.length !== offenders.length) {
  throw new Error(`${movedSnap.length} snap(s) moved but ${offenders.length} were over ${OVER} nm`)
}

// ── WHAT MOVED IN THE TABLE, AND WHAT DID NOT ─────────────────────────────────────────────────
// Opening a harbour's own water moves that harbour's distances — she stops starting her voyage in
// somebody else's sea — and it must move NOTHING ELSE. Every directed reading is compared at the
// precision the table stores (0.1 nm).
let pairSame = 0
const pairMovedAtFixed = []
const pairMovedElsewhere = []
for (const a of ports) {
  for (const b of ports) {
    if (a.code === b.code) continue
    const before = Number(appliedReach.get(a.code)[b.code])
    const after = Number(reaches.get(a.code).get(b.code).toFixed(1))
    if (Math.abs(before - after) < 0.05) pairSame++
    else if (fixedSet.has(a.code) || fixedSet.has(b.code)) pairMovedAtFixed.push([a.code, b.code, before, after])
    else pairMovedElsewhere.push([a.code, b.code, before, after])
  }
}
// WHAT MOVED, CLASSIFIED. This file changes TWO things and they move distances in opposite
// directions, so the counts are kept apart rather than summed into one comforting number:
//   * the RASTER gives forty harbours water of their own, which moves their own readings;
//   * the PROPOSER (src/lib/sea segmentIsWater) now walks the cells a leg crosses instead of
//     sampling points along it, so a leg can no longer be straightened THROUGH land that its
//     samples stepped over or that fell inside an approach allowance. Every reading in the world
//     is re-straightened, and the ones that GREW are phantom shortcuts being paid for.
const statsOf = (rows) =>
  rows.map(([a, b, before, after]) => ({ a, b, before, after, nm: Math.abs(after - before), pct: Math.abs(after - before) / before }))
const elsewhereStats = statsOf(pairMovedElsewhere)
const atFixedStats = statsOf(pairMovedAtFixed)
const grew = elsewhereStats.filter((x) => x.after > x.before).sort((a, b) => b.nm - a.nm)
const shrank = elsewhereStats.filter((x) => x.after < x.before).sort((a, b) => b.nm - a.nm)
const worstGrowth = grew[0] ?? { nm: 0, a: null, b: null, before: 0, after: 0 }
const worstShrink = shrank[0] ?? { nm: 0, a: null, b: null, before: 0, after: 0 }
const worstElsewhere = elsewhereStats.reduce((m, x) => (x.nm > m.nm ? x : m), { nm: 0, pct: 0, a: null, b: null, before: 0, after: 0 })
const worstElsewherePct = elsewhereStats.reduce((m, x) => (x.pct > m.pct ? x : m), { nm: 0, pct: 0, a: null, b: null, before: 0, after: 0 })
const pairMoved = pairMovedAtFixed.length + pairMovedElsewhere.length
// A SHORTCUT IS ALWAYS A SHORTENING, so the cap that matters is on what got SHORTER between two
// harbours this file gave no new water to. Nothing there may fall by more than the greedy
// straightener's own wobble; a new canal would show up here first and blow through it.
const SHRINK_CAP_NM = 300
if (worstShrink.nm > SHRINK_CAP_NM) {
  throw new Error(
    `a reading between two untouched harbours SHORTENED by ${worstShrink.nm.toFixed(1)} nm ` +
      `(${worstShrink.a}->${worstShrink.b} ${worstShrink.before}->${worstShrink.after}) — that is a new shortcut, read it before raising the cap`,
  )
}
console.log(
  `  pair readings: ${pairSame} identical, ${pairMovedAtFixed.length} at a fixed harbour, ${pairMovedElsewhere.length} elsewhere ` +
    `(${grew.length} grew, worst ${worstGrowth.nm.toFixed(1)} nm ${worstGrowth.a}->${worstGrowth.b} ${worstGrowth.before}->${worstGrowth.after}; ` +
    `${shrank.length} shrank, worst ${worstShrink.nm.toFixed(1)} nm ${worstShrink.a}->${worstShrink.b} ${worstShrink.before}->${worstShrink.after})`,
)
console.log(`    at a fixed harbour: ${atFixedStats.filter((x) => x.after > x.before).length} grew, ${atFixedStats.filter((x) => x.after < x.before).length} shrank`)

// ── THE COURSES, POSITIVE AND NEGATIVE ────────────────────────────────────────────────────────
// A real proposed water path, as a client would send one: Lisbon→Cádiz round Cape St Vincent.
const lisCad = findPath(nav, LIS, CAD)
if (!lisCad) throw new Error('no Lisbon→Cádiz path — the raster is broken')
// 0052's course, still legal: Bristol→Amsterdam down the Bristol Channel and round Land's End.
const brsAms = findPath(nav, BRS, AMS)
if (!brsAms) throw new Error('no Bristol→Amsterdam path — the Severn channel is broken')
// …and the two this file exists for, over the NEW water.
const tokNag = findPath(nav, TOK, NAG)
if (!tokNag) throw new Error('no Tokyo→Nagasaki path — the Edo Bay channel is broken')
const patCag = findPath(nav, PAT, CAG)
if (!patCag) throw new Error('no Patras→Cagliari path — the Gulf of Patras channel is broken')

// THE NEGATIVE CONTROLS ARE THE COURSES THE GAME IS SERVING RIGHT NOW. Not a hand-drawn line:
// the exact polyline findPath produces over the APPLIED raster, whose first leg runs from the quay
// straight to water on the far side of a peninsula.
//
// Both halves are asked of the REAL authority, voyage.path_refusal, and never of a second copy of
// the law written here:
//   1. on the raster the chain is serving, with the allowance that raster's snap buys → must be
//      NULL. If it is not, the course was never legal and the control proves nothing.
//   2. on THIS file's raster, with the allowance this file's snap buys → must be E_LAND.
// (2) is only askable because the live PGlite session can be given the new raster inside a
// transaction and rolled straight back out of it. That matters: the first draft picked Patras,
// whose served course crosses the Gulf of Patras — water this very file opens — so it would have
// been ACCEPTED after applying and the migration would have gone red on the deploy. The subject is
// not chosen by hand either: the offenders are walked worst-snap-first and the first two that
// satisfy BOTH halves are taken, so the probe satisfies its own preconditions.
const overland = []
{
  const ask = async (port, dest, path, headNm, tailNm) =>
    (
      await db.query('select voyage.path_refusal($1::jsonb, $2, $3, $4, $5, 15, $6, $7) as r', [
        JSON.stringify(path.map(([la, lo]) => [Number(la.toFixed(4)), Number(lo.toFixed(4))])),
        port.lat, port.lon, dest.lat, dest.lon, headNm, tailNm,
      ])
    ).rows[0].r
  // A destination that is NOT itself one of the offenders, so its tail allowance is the same
  // number before and after and the control is testing the head.
  const destFor = (port) => {
    const m = appliedReach.get(port.code)
    const best = ports
      .filter((d) => d.code !== port.code && !fixedSet.has(d.code) && Number(m[d.code]) > 300)
      .sort((a, b) => Number(m[a.code]) - Number(m[b.code]) || a.code.localeCompare(b.code))[0]
    if (!best) throw new Error(`no untouched destination for ${port.code}`)
    return best
  }
  const rejected = []
  for (const port of offenders) {
    if (overland.length === 2) break
    const dest = destFor(port)
    const old = findPath(applied, port, dest)
    if (!old) { rejected.push(`${port.code}: no served path`); continue }
    const wasLegal = await ask(port, dest, old.path, appliedSnap.get(port.code) + 25, appliedSnap.get(dest.code) + 25)
    if (wasLegal !== null) { rejected.push(`${port.code}: served course already refused (${wasLegal.slice(0, 30)})`); continue }
    await db.query('begin')
    await db.query("update public.sea_raster set cells = decode($1, 'base64') where id = 1", [b64])
    const nowRefused = await ask(port, dest, old.path, snapNm.get(port.code) + 25, appliedSnap.get(dest.code) + 25)
    await db.query('rollback')
    if (nowRefused === null || !nowRefused.startsWith('E_LAND:')) {
      rejected.push(`${port.code}: still legal on the new raster (${nowRefused ?? 'null'})`)
      continue
    }
    console.log(`  overland control ${port.code}→${dest.code}: legal on ${appliedSnap.get(port.code).toFixed(2)} nm of exemption, ` +
                `refused on ${snapNm.get(port.code).toFixed(2)} — ${nowRefused.slice(0, 70)}`)
    overland.push({ port, dest, path: old.path, refusal: nowRefused })
  }
  if (overland.length < 2) {
    throw new Error(`only ${overland.length} usable overland control(s); rejected: ${rejected.join(' | ')}`)
  }
  if (rejected.length > 0) console.log(`  (passed over ${rejected.length}: ${rejected.slice(0, 6).join(' | ')})`)
}

const brsAmsNm = reaches.get(BRS.code).get(AMS.code)
const lisNagNm = reaches.get(LIS.code).get(NAG.code)
const alxAdeNm = reaches.get(ALX.code).get(ADE.code)
const verAcaNm = reaches.get(VER.code).get(ACA.code)
console.log(`  canal controls: ${ALX.code}→${ADE.code} ${Math.round(alxAdeNm)} nm round the Cape (no Suez); ` +
            `${VER.code}→${ACA.code} ${Math.round(verAcaNm)} nm round the Horn (no Panama)`)
console.log(`  the Arctic control: ${LIS.code}→${NAG.code} ${Math.round(lisNagNm)} nm`)

// Control cells for the bit-order round trip: (name, lat, lon, expected 1/0). Every harbour this
// file opens water for gets a PAIR — the water she now answers, and land she must NOT spill into —
// so a channel that ran away inland fails at apply instead of at play.
const CONTROLS = [
  ['the mid-Atlantic', 30, -40, 1],
  ['the middle of Iberia', 39.5, -4.5, 0],
  ['the Bosphorus channel', 41.0, 29.0, 1],
  ['the Siberian arctic (ice)', 75, 120, 0],
  ['the Barents Sea (open — the Muscovy road)', 70, 40, 1],
  ['the Antarctic pack', -65, 0, 0],
  ['the South China Sea', 12, 112, 1],
  ['the Sahara', 23, 10, 0],
  // 0052's, kept: the Severn Bristol sails, and the hills it must NOT spill into.
  ['the Bristol Channel off Barry', 51.4, -3.1, 1],
  ['the Severn approach at Bristol', 51.45, -2.6, 1],
  ['the Welsh hills above the channel', 52.0, -3.5, 0],
  ['the Southern Ocean at 59°S (open)', -59, 0, 1],
  ['the pack at 61°S (closed)', -61, 0, 0],
  // 0060's water, and 0060's land. The land halves are what stop a channel becoming a canal.
  ['Isfjorden at Longyearbyen', 78.22, 15.63, 1],
  ['the Spitsbergen ice fields south of it', 77.6, 15.6, 0],
  ['the Red River at Ke Cho', 21.02, 105.84, 1],
  ['the hills of Tonkin west of it', 21.0, 105.0, 0],
  ['the head of the Gulf of Khambhat', 22.31, 72.62, 1],
  ['the Kathiawar plain west of it', 22.3, 71.6, 0],
  ['Edo Bay', 35.6, 139.85, 1],
  ['the Kanto plain north of it', 36.1, 139.7, 0],
  ['the Gulf of Patras', 38.25, 21.4, 1],
  ['the mountains of Achaea south of it', 37.9, 21.9, 0],
  ['the Trondheimsfjord', 63.5, 10.25, 1],
  ['the Dovrefjell south of it', 62.5, 10.0, 0],
  ['the Gulf of Smyrna', 38.5, 26.9, 1],
  ['Anatolia east of Smyrna', 38.4, 28.2, 0],
  ['the Zuiderzee off Hoorn', 52.65, 5.07, 1],
  ['the Veluwe east of the Zuiderzee', 52.2, 5.9, 0],
  ['the Cross River at Old Calabar', 4.95, 8.32, 1],
  ['the forest north of Old Calabar', 5.6, 8.3, 0],
  ['the Min at Fuzhou', 26.08, 119.29, 1],
  ['the Fujian hills west of it', 26.0, 118.4, 0],
  ['the James River at Jamestown', 37.21, -76.78, 1],
  ['the Virginia piedmont west of it', 37.4, -77.9, 0],
  ['the Thermaic Gulf at Thessaloniki', 40.64, 22.94, 1],
  ['Macedonia north of it', 41.2, 22.9, 0],
  ['the Tagus at Lisbon', 38.7, -9.14, 1],
  ['the Alentejo east of the Tagus', 38.7, -8.3, 0],
  ['Manila Bay', 14.58, 120.9, 1],
  ['Luzon east of Manila', 14.6, 121.6, 0],
  ['the roads of Valencia', 39.42, -0.15, 1],
  ['the huerta behind Valencia', 39.45, -0.7, 0],
  ['the Firth of Forth at Leith', 56.05, -3.2, 1],
  ['the Lothians south of it', 55.7, -3.2, 0],
]
for (const [name, lat, lon, want] of CONTROLS) {
  const r = Math.min(ROWS - 1, Math.max(0, Math.floor((90 - lat) / CELL_DEG)))
  const c = ((Math.floor((lon + 180) / CELL_DEG) % COLS) + COLS) % COLS
  const got = cells[r * COLS + c]
  if (got !== want) throw new Error(`control cell "${name}" is ${got}, expected ${want}`)
}

const inland = [...snapNm.entries()].filter(([, nm]) => nm > OVER).sort((a, b) => b[1] - a[1])
console.log(`  ${inland.length} places snap >${OVER} nm to open water after this pass`)

// ── 5. Emit ────────────────────────────────────────────────────────────────────────────────────
const lines = []
const w = (s = '') => lines.push(s)
const q = (s) => `'${String(s).replace(/'/g, "''")}'`
const j = (x) => `'${JSON.stringify(x).replace(/'/g, "''")}'`

const pathJson = (p) => p.map(([lat, lon]) => [Number(lat.toFixed(4)), Number(lon.toFixed(4))])

// The seas by raster ordinal, so a healed cell can be asserted BY NAME rather than by byte.
const seaNames = new Map(
  (await db.query('select raster_ordinal, name from public.seas where raster_ordinal is not null')).rows
    .map((r) => [Number(r.raster_ordinal), r.name]),
)
for (const h of healed) {
  h.sea = seaNames.get(h.ordinal)
  if (!h.sea) throw new Error(`healed cell (${h.lat}, ${h.lon}) took ordinal ${h.ordinal}, which names no sea`)
}
const b64Row = (bytes) => Buffer.from(bytes).toString('base64')

w(`-- ═══════════════════════════════════════════════════════════════════════════════════════════════`)
w(`-- ${SHORT} — FORTY HARBOURS STOP SAILING OVERLAND`)
w(`--        Every port that had no water of its own gets the water it actually worked, and stops`)
w(`--        being handed a land-exempt corridor across the country it stands in.`)
w(`-- ═══════════════════════════════════════════════════════════════════════════════════════════════`)
w(`--`)
w(`-- GENERATED by scripts/build-sea-migration.mjs — do not hand-edit. Change the sea (scripts/`)
w(`-- sea-grid.mjs) or the ports and cut a NEW migration; an applied one is history.`)
w(`--`)
w(`-- ── THE OWNER, VERBATIM (docs/OWNER_REQUESTS.md row 41) ────────────────────────────────────────`)
w(`--   "i don't want the fleet to ever touch land."`)
w(`--`)
w(`-- ── WHAT THIS SUPERSEDES ───────────────────────────────────────────────────────────────────────`)
w(`--   It SUPERSEDES THE DATA of 0052 (the Severn is water), which itself superseded 0046's:`)
w(`--   public.sea_raster's one row is rewritten and public.sea_reaches is replaced wholesale. 0046`)
w(`--   and 0052 stay exactly as they applied — they are history, and editing one is the D23 defect.`)
w(`--   It supersedes NO FUNCTION and re-cuts none. voyage.path_nm and voyage.path_refusal are`)
w(`--   0046's and are untouched; voyage.sail_refusal belongs to 0050. A generator that re-emitted`)
w(`--   the bodies it remembered would silently roll 0050 back, so this file emits DATA only.`)
w(`--   It also PATCHES ${seaPatch.size} row(s) of 0040's membership raster (public.sea_cells): the cells these`)
w(`--   channels open were land when 0040 was cut, and land carries no sea name. Each one joins the`)
w(`--   nearest named sea BY WATER — build-sea-raster.mjs's own rule for unnamed water, reused, not`)
w(`--   re-invented — and each is asserted by name below.`)
w(`--`)
w(`-- ── THE DEFECT, WHICH IS 0052'S DEFECT AT THIRTY-NINE MORE HARBOURS ────────────────────────────`)
w(`--   public.sea_reaches.snap_nm is not a label. voyage.path_refusal takes it as the LAND-EXEMPT`)
w(`--   HEAD ALLOWANCE of a course, so a harbour whose own 0.25° cell scan-filled as land is handed`)
w(`--   a straight line over the country it stands in — and the pathfinder uses it. 0052 proved`)
w(`--   that at Bristol (64.55 nm across Devon) and fixed her; MEASURED on the raster this file`)
w(`--   supersedes, ${offenders.length} places still snapped more than ${OVER} nm, ${offenders.filter((p) => appliedSnap.get(p.code) > 30).length} of them more than 30 nm:`)
for (const p of offenders.slice(0, 13)) {
  w(`--     ${p.code}  ${p.name.padEnd(14)} ${appliedSnap.get(p.code).toFixed(2).padStart(6)} nm  →  ${snapNm.get(p.code).toFixed(2).padStart(5)} nm`)
}
w(`--     … and ${offenders.length - 13} more between ${OVER} and 30 nm, every one listed in the guard below.`)
w(`--   Longyearbyen's 67.68 nm ran clean across Spitsbergen; Hanoi's 58.68 nm across the Tonkin`)
w(`--   delta; Tokyo's 47.69 nm across the Boso peninsula; Lisbon — the capital of the Portuguese`)
w(`--   seaborne empire — snapped 23.30 nm over Estremadura because the Tagus is narrower than a`)
w(`--   cell. Fuzhou snapped to the WRONG SEA as well as the wrong side: the East China Sea, while`)
w(`--   the port declares the Taiwan Strait.`)
w(`--`)
w(`-- ── THE FIX: ${CHANNEL_COUNT} CHANNELS ENTRIES, EACH A WATER A SHIP OF THE PERIOD WORKED ──────────────────`)
w(`--   scripts/sea-grid.mjs holds the one list of "water the map is too coarse to draw". ${NEW_CHANNELS} of its`)
w(`--   ${CHANNEL_COUNT} entries open water this raster did not have — new ones, plus two extended in place (the`)
w(`--   Gulf of Khambhat to its head at Cambay; the White Sea road up the Northern Dvina to`)
w(`--   Arkhangelsk). Every entry is justified from the`)
w(`--   period, in the file, beside its points — the Marsdiep and Texel Roads where the VOC fleets`)
w(`--   made up; the Uraga Channel and Edo Bay, which carried the whole coastal trade of Japan; the`)
w(`--   Gulf of Patras, where Lepanto was fought by four hundred galleys; the Cross River, which`)
w(`--   Bristol and Liverpool ships worked fifty miles to Duke Town; Isfjorden, whaled from the`)
w(`--   1610s. Three are ROADSTEADS rather than straits — Valencia, Safi, the Douro bar — where the`)
w(`--   110 m coastline simply bulges seaward of the real shore and swallowed the open sea a`)
w(`--   harbour lay in. Two are named in the file as the WEAKEST justifications here and open the`)
w(`--   estuary only, not the river: the Taedong (Nampo) and Gyeonggi Bay (Incheon), whose towns`)
w(`--   are 19th-century treaty ports even though their approaches are older.`)
w(`--`)
w(`-- ── WHAT MOVED, MEASURED, AND WHAT DID NOT ───────────────────────────────────────────────────`)
w(`--   water cells        ${appliedWater.toLocaleString('en')}  →  ${newWater.toLocaleString('en')}   (+${opened} opened, -${closed} closed)`)
w(`--   snap readings      ${movedSnap.length} moved, and all ${movedSnap.length} are harbours that were over ${OVER} nm. No harbour`)
w(`--                      already inside the threshold moved at all.`)
w(`--   pair readings      of ${(ports.length * (ports.length - 1)).toLocaleString('en')} directed readings, ${pairSame.toLocaleString('en')} are IDENTICAL and ${pairMoved.toLocaleString('en')} moved.`)
w(`--                      ${pairMovedAtFixed.length.toLocaleString('en')} have an end in the ${offenders.length} fixed harbours — that is the fix, and it`)
w(`--                      moves distances UP: these harbours were starting their voyages in`)
w(`--                      somebody else's sea. Amsterdam now leaves by the Marsdiep instead of`)
w(`--                      stepping onto the North Sea across North Holland.`)
w(`--                      ${pairMovedElsewhere.length.toLocaleString('en')} are between two harbours this file gave no new water to, and none`)
w(`--                      by more than ${worstElsewhere.nm.toFixed(1)} nm (${worstElsewhere.a}→${worstElsewhere.b} ${worstElsewhere.before}→${worstElsewhere.after}) or ${(worstElsewherePct.pct * 100).toFixed(2)}%. Two`)
w(`--                      causes, both geometry rather than error: a cell opened for one harbour`)
w(`--                      can be a cell a PASSING route now clips, and the figure is the length of`)
w(`--                      the greedy-straightened polyline, so a different cell path can straighten`)
w(`--                      a little longer. ${grew.length} grew, ${shrank.length} shrank; the cap on the SHRINKING side is`)
w(`--                      the one that matters, because a shortcut is always a shortening.`)
w(`--   THIS IS WHERE A CHANNEL BECOMES A CANAL, and the cap caught one during the build: carried`)
w(`--   the last twelve miles up the Trave to Lübeck's own quay, the fix put sailable water 22 nm`)
w(`--   from Hamburg's, inside the 27.5 nm approach the straightener exempts — and Hamburg→Tallinn`)
w(`--   fell from 991.5 nm round Denmark to 611.0 nm STRAIGHT OVER SCHLESWIG. A Kiel Canal, 1895.`)
w(`--   The channel now stops at Travemünde, where the seagoing water stopped.`)
w(`--   THE RASTER ONLY OPENS WATER (${closed} cells closed, asserted at generation). That is a production`)
w(`--   rule, not a tidiness one: a voyage already at sea carries a frozen path computed over the`)
w(`--   OLD raster, and a course legal over a raster stays legal over a superset of it. Closing a`)
w(`--   cell could strand a fleet mid-passage on water that had become land.`)
w(`--   UNMOVED, asserted below to 0.1 nm — none of these ports is one of the ${offenders.length}:`)
w(`--     the Cape, no Suez                 ${ALX.code}→${ADE.code} ${reaches.get(ALX.code).get(ADE.code).toFixed(1)} nm`)
w(`--     the Horn, no Panama               ${VER.code}→${ACA.code} ${reaches.get(VER.code).get(ACA.code).toFixed(1)} nm`)
w(`--     the Horn from the east            ${BUE.code}→${CLL.code} ${reaches.get(BUE.code).get(CLL.code).toFixed(1)} nm`)
w(`--     the Roaring Forties               ${RIO.code}→${CEB.code} ${reaches.get(RIO.code).get(CEB.code).toFixed(1)} nm`)
w(`--     the Cape of Good Hope             ${CPT.code}→${JKT.code} ${reaches.get(CPT.code).get(JKT.code).toFixed(1)} nm`)
w(`--     Valparaiso to the Cape            ${VLP.code}→${CPT.code} ${reaches.get(VLP.code).get(CPT.code).toFixed(1)} nm`)
w(`--   MOVED ON PURPOSE, because Lisbon is one of the ${offenders.length}: ${LIS.code}→${NAG.code} ${reaches.get(LIS.code).get(NAG.code).toFixed(1)} nm (was`)
w(`--   ${appliedReach.get(LIS.code)[NAG.code]}), still far above the 12,000 nm floor that says the Arctic has not reopened.`)
w(`--`)
w(`-- ── WHAT THIS FILE DELIBERATELY DOES NOT DO, AND WHAT IT FOUND WHILE NOT DOING IT ────────────`)
w(`--   1. IT DOES NOT CLOSE THE SIX CHANNELS ENTRIES WHOSE OWN INTERPOLATION DRAWS A CANAL.`)
w(`--      Measured 2026-08-26: an entry's points are joined cell by cell, so an entry holding TWO`)
w(`--      unconnected waters opens the land between them. \`irrawaddy-sittaung\` joins Yangon to the`)
w(`--      Chao Phraya across 330 nm and opens 30 land cells, one 85.6 nm up in the Tenasserim`)
w(`--      mountains — the Gulf of Thailand reaches the Andaman Sea in 382 nm instead of the`)
w(`--      ~2,300 nm round Singapore. \`elbe-weser\`, \`thames-scheldt\`, \`gironde\`, \`baltic-gulfs\` and`)
w(`--      \`gambia-senegal\` spill the same way, 31-63 nm inland. CLOSING water can strand a voyage`)
w(`--      already sailing it; that needs a migration which deals with those fleets first.`)
w(`--   2. IT DOES NOT REPAIR THE COURSE PROPOSER, AND THE PROPOSER IS WORSE THAN ANY SNAP.`)
w(`--      The client proposes a course and the server verifies it. The proposer asks "is this leg`)
w(`--      water?" by SAMPLING every half cell (src/lib/sea/pathfind.ts:segmentIsWater), which is`)
w(`--      phase-dependent and skips land that falls inside an approach allowance. Measured on the`)
w(`--      raster this file supersedes:`)
w(`--        * PANAMA CITY→PORT ROYAL IS SERVED AT ${appliedReach.get(PAN.code)[POR.code]} nm. The Isthmus of Panama is about`)
w(`--          30 nm wide at 0.25° and Panama's approach allowance is 32.0 nm (snap 10.82 + one cell`)
w(`--          diagonal), so every land sample on the straight line falls inside it and the whole`)
w(`--          10,479.8 nm road round the Horn collapses into one leg ACROSS THE ISTHMUS. A Panama`)
w(`--          Canal, 1914, in the served table today. Panama→Santiago de Cuba likewise: 1,944.6 nm`)
w(`--          for a road of 11,023.4. Neither canal control in this chain could see it, because`)
w(`--          Veracruz and Acapulco do not lie either side of the same 30 nm neck. THIS FILE DOES`)
w(`--          NOT CHANGE IT: ${PAN.code}→${POR.code} reads ${reaches.get(PAN.code).get(POR.code).toFixed(1)} nm after this file, exactly as before.`)
w(`--        * The same weakness makes the proposer disagree with the server's own land guard: a`)
w(`--          stored course is re-split at every sea boundary (voyage.segments_from_course, 0047)`)
w(`--          and re-sampled in a different phase, so a leg accepted as water can be refused as`)
w(`--          land. On this raster Lisbon→Nagasaki is one: legal as proposed, E_LAND at`)
w(`--          (23.23°, -16.48°) once stored. scripts/db/proofs/09_the_fleet_never_touches_land.sql`)
w(`--          IS RED FOR THAT REASON with this file applied, and it is right to be — the course`)
w(`--          does touch land. The repair is a sound proposer (walk the cells a leg crosses, and`)
w(`--          forbid A* the corner cuts a fixed-step sampler cannot judge), which re-prices every`)
w(`--          road in the world and needs its own migration and its own balance pass. It was built`)
w(`--          and measured in this worktree and deliberately NOT shipped here: it moved 50,868 of`)
w(`--          56,406 readings and disconnected 10 ports whose channels are only diagonally linked.`)
w(`--   3. It does not touch the mover, the ports, the goods or any price, and re-cuts no function.`)
w(`--      It does not change the ${OVER} nm threshold or the +25 nm cell the mover adds to a snap.`)
w(`--`)
w(`-- Depends on: 0002 (ports, seas, gc_distance_nm), 0040 (sea_cells, voyage.sea_at), 0046 (the two`)
w(`-- tables and voyage.path_nm / voyage.path_refusal), 0052 (the data this supersedes), and the`)
w(`-- port rows of 0003/0036/0041.`)
w(`-- ═══════════════════════════════════════════════════════════════════════════════════════════════`)
w()
w(`-- ── The raster, superseding 0052's ─────────────────────────────────────────────────────────────`)
w(`-- Same shape, same LSB-first packing, same two bits per cell (bit 0 SEA, bit 1 POLAR). An`)
w(`-- UPDATE, not an insert: 0046's row is the one row, and this file rewrites what is in it.`)
w(`update public.sea_raster`)
w(`   set cols = ${COLS}, rows = ${ROWS}, cell_deg = ${CELL_DEG}, bits_per_cell = ${BITS},`)
w(`       cells = decode('${b64}', 'base64')`)
w(` where id = 1;`)
w()
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
w(`-- ── The snaps the chain is serving, captured before they are gone ─────────────────────────────`)
w(`-- The guard below is non-vacuous BY CONSTRUCTION: it demands that each of these ${offenders.length} harbours was`)
w(`-- OVER ${OVER} nm a moment ago and is at or under it now, so it can only pass by the defect having`)
w(`-- actually existed and having actually been fixed IN THIS TRANSACTION. A guard that only read`)
w(`-- the new number would pass just as happily on a raster that had never been broken.`)
w(`-- Plain TEMPORARY, dropped by name at the end rather than \`on commit drop\`: a runner that does`)
w(`-- not wrap the file in one transaction would drop an \`on commit drop\` table before the DO block`)
w(`-- could read it, and the guard would fail for a reason that has nothing to do with the sea.`)
w(`create temporary table _${SHORT}_before as`)
w(`  select code, snap_nm, reaches from public.sea_reaches;`)
w()
w(`-- ── The sailed distances, superseding 0052's ───────────────────────────────────────────────────`)
w(`-- Replaced whole rather than merged: every figure in the table comes from ONE flood over ONE`)
w(`-- raster, and a half-updated table would be two authorities for one distance.`)
w(`delete from public.sea_reaches;`)
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
w(`  join public.ports p on p.code = v.code;`)
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
w(`  v_same     int;`)
w(`  v_at_fixed int;`)
w(`  v_elsewhere int;`)
w(`  v_worst_nm  numeric;`)
w(`  v_worst_pct numeric;`)
w(`  v_lis_cad  constant jsonb := ${j(pathJson(lisCad.path))}::jsonb;`)
w(`  v_brs_ams  constant jsonb := ${j(pathJson(brsAms.path))}::jsonb;`)
w(`  -- the course the OLD raster served: Bristol straight across southern England to the Channel,`)
w(`  -- then on to Amsterdam. It must now be refused as land.`)
w(`  v_overland constant jsonb := ${j([[BRS.lat, BRS.lon], [50.63, -0.13], [50.63, 0.63], [AMS.lat, AMS.lon]])}::jsonb;`)
w(`  -- the two courses this file exists for, over the water it opens…`)
w(`  v_tok_nag  constant jsonb := ${j(pathJson(tokNag.path))}::jsonb;`)
w(`  v_pat_cag  constant jsonb := ${j(pathJson(patCag.path))}::jsonb;`)
w(`  -- …and the two the game is serving RIGHT NOW, straight off findPath over the raster this file`)
w(`  -- supersedes. Not drawn by hand: these are the exact polylines a client is given today, whose`)
w(`  -- first leg walks out of the harbour across a peninsula on the strength of its snap.`)
w(`  v_was_0    constant jsonb := ${j(pathJson(overland[0].path))}::jsonb;`)
w(`  v_was_1    constant jsonb := ${j(pathJson(overland[1].path))}::jsonb;`)
w(`begin`)
w(`  -- (a) THE RASTER IS THERE AND THE BIT ORDER IS THE ONE THE CLIENT PACKS. ${CONTROLS.length} control cells,`)
w(`  --     each a named piece of the world, asserted through get_bit — the same read the sampler`)
w(`  --     uses. A packing that shifted one bit would fail all of them.`)
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
// …and the POLAR bit, both ways: set on the Barents road, clear on the mid-Atlantic. A packing
// that interleaved the planes wrongly would fail one of these while the SEA bits still read true.
{
  const cellBit = (lat, lon) => {
    const row = Math.min(ROWS - 1, Math.max(0, Math.floor((90 - lat) / CELL_DEG)))
    const col = ((Math.floor((lon + 180) / CELL_DEG) % COLS) + COLS) % COLS
    return (row * COLS + col) * BITS
  }
  w(`  if get_bit(r.cells, ${cellBit(70, 40) + 1}) <> 1 then`)
  w(`    raise exception '${SHORT} self-assert FAIL: the Barents Sea does not carry the POLAR mark';`)
  w(`  end if;`)
  w(`  if get_bit(r.cells, ${cellBit(30, -40) + 1}) <> 0 then`)
  w(`    raise exception '${SHORT} self-assert FAIL: the mid-Atlantic carries a POLAR mark it must not';`)
  w(`  end if;`)
  w(`  if get_bit(r.cells, ${cellBit(-57.5, -65) + 1}) <> 1 or get_bit(r.cells, ${cellBit(-57.5, -65)}) <> 1 then`)
  w(`    raise exception '${SHORT} self-assert FAIL: the Drake Passage fringe should be open POLAR water';`)
  w(`  end if;`)
}
w()
w(`  -- (a2) THE TWO RASTERS AGREE: every sailable control cell answers a sea through voyage.sea_at`)
w(`  --      (0040), and so does every cell the Severn newly opened — by NAME, so a heal that took`)
w(`  --      the wrong neighbour is a red apply and not a quiet relabelling of somebody's water.`)
w(`  if voyage.sea_at(30, -40) is null then`)
w(`    raise exception '${SHORT} self-assert FAIL: the mid-Atlantic (30, -40) is sailable here but answers NO sea through voyage.sea_at (0040) — the two rasters have drifted apart';`)
w(`  end if;`)
w(`  if voyage.sea_at(41, 29) is null then`)
w(`    raise exception '${SHORT} self-assert FAIL: the Bosphorus channel (41, 29) is sailable here but answers NO sea through voyage.sea_at (0040) — the two rasters have drifted apart';`)
w(`  end if;`)
w(`  if voyage.sea_at(70, 40) is null then`)
w(`    raise exception '${SHORT} self-assert FAIL: the Barents Sea (70, 40) is sailable here but answers NO sea through voyage.sea_at (0040) — the two rasters have drifted apart';`)
w(`  end if;`)
w(`  if voyage.sea_at(12, 112) is null then`)
w(`    raise exception '${SHORT} self-assert FAIL: the South China Sea (12, 112) is sailable here but answers NO sea through voyage.sea_at (0040) — the two rasters have drifted apart';`)
w(`  end if;`)
for (const h of healed) {
  w(`  if voyage.sea_at(${h.lat}, ${h.lon}) is distinct from (select id from public.seas where name = ${q(h.sea)}) then`)
  w(`    raise exception '${SHORT} self-assert FAIL: the newly opened cell (${h.lat}, ${h.lon}) should answer ${h.sea.replace(/'/g, "''")}, got [%]', coalesce((select name from public.seas where id = voyage.sea_at(${h.lat}, ${h.lon})), 'null');`)
  w(`  end if;`)
}
w()
w(`  -- (a3) THE THIRTY-NINE. Every harbour that snapped over ${OVER} nm on the raster this file`)
w(`  --      supersedes now snaps at or under it — AND the check reads BOTH numbers, so it cannot`)
w(`  --      pass vacuously: a world where the defect never existed fails the first half.`)
w(`  select count(*) into v_n from _${SHORT}_before where snap_nm > ${OVER};`)
w(`  if v_n <> ${offenders.length} then`)
w(`    raise exception '${SHORT} self-assert FAIL: the raster being superseded had % harbour(s) snapping over ${OVER} nm, expected ${offenders.length} — this file was cut against a different sea', v_n;`)
w(`  end if;`)
w(`  select count(*) into v_bad`)
w(`    from _${SHORT}_before b join public.sea_reaches a on a.code = b.code`)
w(`   where b.snap_nm > ${OVER} and a.snap_nm > ${OVER};`)
w(`  if v_bad <> 0 then`)
w(`    raise exception '${SHORT} self-assert FAIL: % harbour(s) still snap over ${OVER} nm to sailable water — they keep a land-exempt corridor across their own country (%)', v_bad,`)
w(`      (select string_agg(a.code || ' ' || round(a.snap_nm, 2), ', ' order by a.snap_nm desc)`)
w(`         from _${SHORT}_before b join public.sea_reaches a on a.code = b.code`)
w(`        where b.snap_nm > ${OVER} and a.snap_nm > ${OVER});`)
w(`  end if;`)
w(`  select count(*) into v_bad from public.sea_reaches where snap_nm > ${OVER};`)
w(`  if v_bad <> 0 then`)
w(`    raise exception '${SHORT} self-assert FAIL: % harbour(s) snap over ${OVER} nm', v_bad;`)
w(`  end if;`)
w(`  -- …and NOTHING ELSE moved. A snap that changed at a harbour that was already inside the`)
w(`  --   threshold would mean a channel ran somewhere nobody asked it to.`)
w(`  select count(*) into v_bad`)
w(`    from _${SHORT}_before b join public.sea_reaches a on a.code = b.code`)
w(`   where b.snap_nm <= ${OVER} and abs(a.snap_nm - b.snap_nm) > 0.005;`)
w(`  if v_bad <> 0 then`)
w(`    raise exception '${SHORT} self-assert FAIL: % harbour(s) this file never set out to touch had their snap moved', v_bad;`)
w(`  end if;`)
w()
w(`  -- (a4) EVERY ONE OF THE ${offenders.length}, BY NAME AND BY NUMBER. The list above proves the property; this`)
w(`  --      proves the file was cut against the sea it says it was, harbour by harbour.`)
for (const port of offenders) {
  w(`  if (select snap_nm from _${SHORT}_before where code = ${q(port.code)}) is distinct from ${appliedSnap.get(port.code).toFixed(2)}`)
  w(`     or (select snap_nm from public.sea_reaches where code = ${q(port.code)}) is distinct from ${snapNm.get(port.code).toFixed(2)} then`)
  w(`    raise exception '${SHORT} self-assert FAIL: ${port.code} (${port.name.replace(/'/g, "''")}) should have gone ${appliedSnap.get(port.code).toFixed(2)} -> ${snapNm.get(port.code).toFixed(2)} nm, went [%] -> [%]',`)
  w(`      coalesce((select snap_nm::text from _${SHORT}_before where code = ${q(port.code)}), 'null'),`)
  w(`      coalesce((select snap_nm::text from public.sea_reaches where code = ${q(port.code)}), 'null');`)
  w(`  end if;`)
}
w()
w(`  -- (b) EVERY PLACE HAS A REACH ROW, AND EVERY ROW REACHES EVERY OTHER PLACE. Non-vacuous by`)
w(`  --     the counts themselves: the world cannot hold an island nobody can sail to.`)
w(`  select count(*) into v_ports from public.ports;`)
w(`  select count(*) into v_n from public.sea_reaches;`)
w(`  if v_n <> v_ports or v_n < 2 then`)
w(`    raise exception '${SHORT} self-assert FAIL: % reach row(s) for % port(s)', v_n, v_ports;`)
w(`  end if;`)
w(`  select count(*) into v_bad from public.sea_reaches sr`)
w(`   where (select count(*) from jsonb_object_keys(sr.reaches)) <> v_ports - 1;`)
w(`  if v_bad <> 0 then`)
w(`    raise exception '${SHORT} self-assert FAIL: % place(s) do not reach every other place', v_bad;`)
w(`  end if;`)
w()
w(`  -- (c) THE TABLE IS SYMMETRIC — the whole crosswalk, not a sample.`)
w(`  select count(*) into v_bad`)
w(`    from public.sea_reaches a`)
w(`   cross join lateral jsonb_each_text(a.reaches) e(code, nm)`)
w(`    join public.sea_reaches b on b.code = e.code`)
w(`   where (b.reaches->>a.code)::numeric is distinct from e.nm::numeric;`)
w(`  if v_bad <> 0 then`)
w(`    raise exception '${SHORT} self-assert FAIL: % asymmetric pair reading(s)', v_bad;`)
w(`  end if;`)
w()
w(`  -- (c2) WHAT MOVED IN THE WHOLE TABLE, counted against the readings this file replaced. "Fixed"`)
w(`  --      is DERIVED — a harbour whose old snap was over ${OVER} nm — never a list retyped here, so`)
w(`  --      the two halves cannot drift apart. Non-vacuous by its own counts: a world where`)
w(`  --      neither defect existed fails the first comparison.`)
w(`  select count(*) filter (where x.d < 0.05),`)
w(`         count(*) filter (where x.d >= 0.05 and x.at_fixed),`)
w(`         count(*) filter (where x.d >= 0.05 and not x.at_fixed),`)
w(`         coalesce(max(x.before_nm - x.after_nm) filter (where not x.at_fixed), 0),`)
w(`         coalesce(max(x.after_nm - x.before_nm) filter (where not x.at_fixed), 0)`)
w(`    into v_same, v_at_fixed, v_elsewhere, v_worst_nm, v_worst_pct`)
w(`    from (select e.nm::numeric as before_nm,`)
w(`                 (a.reaches->>e.code)::numeric as after_nm,`)
w(`                 abs((a.reaches->>e.code)::numeric - e.nm::numeric) as d,`)
w(`                 (b1.snap_nm > ${OVER} or b2.snap_nm > ${OVER}) as at_fixed`)
w(`            from _${SHORT}_before b1`)
w(`            cross join lateral jsonb_each_text(b1.reaches) e(code, nm)`)
w(`            join _${SHORT}_before b2 on b2.code = e.code`)
w(`            join public.sea_reaches a on a.code = b1.code) x;`)
w(`  if v_same <> ${pairSame} or v_at_fixed <> ${pairMovedAtFixed.length} or v_elsewhere <> ${pairMovedElsewhere.length} then`)
w(`    raise exception '${SHORT} self-assert FAIL: % identical / % moved at a fixed harbour / % moved elsewhere — generation measured ${pairSame} / ${pairMovedAtFixed.length} / ${pairMovedElsewhere.length}', v_same, v_at_fixed, v_elsewhere;`)
w(`  end if;`)
w(`  if v_at_fixed = 0 or v_elsewhere = 0 then`)
w(`    raise exception '${SHORT} self-assert FAIL: one of the two defects moved nothing at all (% at a fixed harbour, % elsewhere)', v_at_fixed, v_elsewhere;`)
w(`  end if;`)
w(`  -- A SHORTCUT IS A SHORTENING. Between two harbours this file gave no new water to, nothing may`)
w(`  -- fall by more than the greedy straightener's own wobble — a new canal shows up here first.`)
w(`  if v_worst_nm > ${worstShrink.nm.toFixed(1)} then`)
w(`    raise exception '${SHORT} self-assert FAIL: a road between two harbours this file gave no new water to SHORTENED by % nm — generation measured at most ${worstShrink.nm.toFixed(1)} (${worstShrink.a} to ${worstShrink.b}, ${worstShrink.before} -> ${worstShrink.after}). That is a new shortcut', round(v_worst_nm, 1);`)
w(`  end if;`)
w(`  if v_worst_pct > ${worstGrowth.nm.toFixed(1)} then`)
w(`    raise exception '${SHORT} self-assert FAIL: a road between two harbours this file gave no new water to LENGTHENED by % nm — generation measured at most ${worstGrowth.nm.toFixed(1)} (${worstGrowth.a} to ${worstGrowth.b}, ${worstGrowth.before} -> ${worstGrowth.after})', round(v_worst_pct, 1);`)
w(`  end if;`)
w()
w(`  -- (d) NO SAILED DISTANCE IS SHORTER THAN THE GREAT CIRCLE.`)
w(`  select count(*) into v_bad`)
w(`    from public.sea_reaches a`)
w(`   cross join lateral jsonb_each_text(a.reaches) e(code, nm)`)
w(`    join public.ports pa on pa.id = a.port_id`)
w(`    join public.ports pb on pb.code = e.code`)
w(`   where a.code < e.code`)
w(`     and e.nm::numeric < voyage.gc_distance_nm(pa.lat::float8, pa.lon::float8, pb.lat::float8, pb.lon::float8) * 0.995;`)
w(`  if v_bad <> 0 then`)
w(`    raise exception '${SHORT} self-assert FAIL: % pair(s) sail shorter than the great circle', v_bad;`)
w(`  end if;`)
w()
w(`  -- (e) THE ARCTIC FIX AND THE CANAL CONTROLS — 0046's three worldly facts, still true.`)
w(`  v_nm := (select (reaches->>${q(NAG.code)})::numeric from public.sea_reaches where code = ${q(LIS.code)});`)
w(`  if v_nm is null or v_nm < 12000 then`)
w(`    raise exception '${SHORT} self-assert FAIL: ${LIS.code}→${NAG.code} is % nm — under 12,000 means the Arctic is open again (the leg graph served 7,565 over the pole)', v_nm;`)
w(`  end if;`)
w(`  if (select (reaches->>${q(ADE.code)})::numeric from public.sea_reaches where code = ${q(ALX.code)}) < 9000 then`)
w(`    raise exception '${SHORT} self-assert FAIL: ${ALX.code}→${ADE.code} under 9,000 nm — a Suez Canal three centuries early';`)
w(`  end if;`)
w(`  if (select (reaches->>${q(ACA.code)})::numeric from public.sea_reaches where code = ${q(VER.code)}) < 9000 then`)
w(`    raise exception '${SHORT} self-assert FAIL: ${VER.code}→${ACA.code} under 9,000 nm — a Panama Canal three centuries early';`)
w(`  end if;`)
w()
w(`  -- (f) WHAT DID NOT MOVE. Six long ocean roads whose ports are NOT among the ${offenders.length} — if any of`)
w(`  --     them shifted, a channel opened a shortcut instead of a harbour approach, and that is the`)
w(`  --     one failure a change this size can hide. Each is asserted at the exact figure it read`)
w(`  --     before this file ran, and the generator refuses to emit if any of them moved at all.`)
for (const [a, b, label] of [
  [ALX, ADE, 'the Cape, no Suez'],
  [VER, ACA, 'the Horn, no Panama'],
  [BUE, CLL, 'the Horn from the east'],
  [RIO, CEB, 'the Roaring Forties'],
  [CPT, JKT, 'the Cape of Good Hope'],
  [VLP, CPT, 'Valparaiso to the Cape'],
]) {
  if (fixedSet.has(a.code) || fixedSet.has(b.code)) {
    throw new Error(`control ${a.code}->${b.code} uses a harbour this file moves — it would prove nothing`)
  }
  const nm = reaches.get(a.code).get(b.code).toFixed(1)
  const was = Number(appliedReach.get(a.code)[b.code])
  if (Math.abs(was - Number(nm)) > 0.05) {
    throw new Error(`control ${a.code}->${b.code} MOVED ${was} -> ${nm} nm — this file changed a road it must not`)
  }
  w(`  v_nm := (select (reaches->>${q(b.code)})::numeric from public.sea_reaches where code = ${q(a.code)});`)
  w(`  if v_nm is distinct from ${nm} then`)
  w(`    raise exception '${SHORT} self-assert FAIL: ${label} (${a.code}->${b.code}) reads % nm, and it must be ${nm} — unchanged by this file', coalesce(v_nm::text, 'null');`)
  w(`  end if;`)
}
w()
w(`  -- (f2) AND WHAT DID: Lisbon IS one of the ${offenders.length}, so ${LIS.code}->${NAG.code} moves. It must still be far`)
w(`  --      above the floor that says the Arctic has not reopened.`)
w(`  v_nm := (select (reaches->>${q(NAG.code)})::numeric from public.sea_reaches where code = ${q(LIS.code)});`)
w(`  if v_nm is distinct from ${lisNagNm.toFixed(1)} then`)
w(`    raise exception '${SHORT} self-assert FAIL: ${LIS.code}->${NAG.code} reads % nm, generation measured ${lisNagNm.toFixed(1)}', coalesce(v_nm::text, 'null');`)
w(`  end if;`)
w()
w(`  -- (f3) THE ISTHMUS THIS FILE DOES NOT CROSS AND DOES NOT FIX. ${PAN.code}->${POR.code} is served at`)
w(`  --      ${appliedReach.get(PAN.code)[POR.code]} nm for a road of 10,479.8 round the Horn, because the proposer straightens`)
w(`  --      the whole route into one leg over a 30 nm neck that fits inside Panama's approach`)
w(`  --      allowance (see the header, "what it found while not doing it"). Pinned here UNCHANGED`)
w(`  --      so the defect cannot drift quietly while it waits for the migration that repairs the`)
w(`  --      proposer — and so that migration has a figure to move.`)
w(`  v_nm := (select (reaches->>${q(POR.code)})::numeric from public.sea_reaches where code = ${q(PAN.code)});`)
w(`  if v_nm is distinct from ${reaches.get(PAN.code).get(POR.code).toFixed(1)} then`)
w(`    raise exception '${SHORT} self-assert FAIL: ${PAN.code}->${POR.code} reads % nm and this file leaves it at ${reaches.get(PAN.code).get(POR.code).toFixed(1)}', coalesce(v_nm::text, 'null');`)
w(`  end if;`)
w()
w(`  -- (g) THE MEASURE AND THE LAW. The positive controls first: two real water courses produced by`)
w(`  --     the one pathfinder at generation time measure what the table says and are ACCEPTED…`)
w(`  v_nm := voyage.path_nm(v_lis_cad);`)
w(`  if abs(v_nm - ${lisCad.nm.toFixed(1)}) > ${(lisCad.nm * 0.005).toFixed(1)} then`)
w(`    raise exception '${SHORT} self-assert FAIL: the embedded Lisbon→Cádiz course measures % nm, generation measured ${lisCad.nm.toFixed(1)}', v_nm;`)
w(`  end if;`)
w(`  if v_nm <= voyage.gc_distance_nm(${LIS.lat}, ${LIS.lon}, ${CAD.lat}, ${CAD.lon}) then`)
w(`    raise exception '${SHORT} self-assert FAIL: the sailed Lisbon→Cádiz course is not longer than the straight line — Cape St Vincent has gone missing';`)
w(`  end if;`)
w(`  v_ref := voyage.path_refusal(v_lis_cad, ${LIS.lat}, ${LIS.lon}, ${CAD.lat}, ${CAD.lon}, 15,`)
w(`             (select snap_nm from public.sea_reaches where code = ${q(LIS.code)}) + 25,`)
w(`             (select snap_nm from public.sea_reaches where code = ${q(CAD.code)}) + 25);`)
w(`  if v_ref is not null then`)
w(`    raise exception '${SHORT} self-assert FAIL: the real Lisbon→Cádiz water course was refused: %', v_ref;`)
w(`  end if;`)
w(`  v_ref := voyage.path_refusal(v_brs_ams, ${BRS.lat}, ${BRS.lon}, ${AMS.lat}, ${AMS.lon}, 15,`)
w(`             (select snap_nm from public.sea_reaches where code = ${q(BRS.code)}) + 25,`)
w(`             (select snap_nm from public.sea_reaches where code = ${q(AMS.code)}) + 25);`)
w(`  if v_ref is not null then`)
w(`    raise exception '${SHORT} self-assert FAIL: the real Bristol→Amsterdam course down the Bristol Channel was refused: %', v_ref;`)
w(`  end if;`)
w(`  -- …and now the two negative controls. The course the OLD raster served — Bristol straight`)
w(`  -- across Somerset, Dorset and Hampshire — must be REFUSED as land WITH BRISTOL'S OWN allowance.`)
w(`  -- That is the whole defect, asserted: it was legal only because her snap bought 90 nm of`)
w(`  -- exemption, and a raster that closed the Severn again would let it through.`)
w(`  v_ref := voyage.path_refusal(v_overland, ${BRS.lat}, ${BRS.lon}, ${AMS.lat}, ${AMS.lon}, 15,`)
w(`             (select snap_nm from public.sea_reaches where code = ${q(BRS.code)}) + 25,`)
w(`             (select snap_nm from public.sea_reaches where code = ${q(AMS.code)}) + 25);`)
w(`  if v_ref is null or v_ref not like 'E_LAND:%' then`)
w(`    raise exception '${SHORT} self-assert FAIL: the old overland Bristol→Amsterdam course was NOT refused as land (got [%])', coalesce(v_ref, 'null');`)
w(`  end if;`)
w(`  -- THE TWO 0060 CONTROLS, and they are the whole point of the file. Each is the course the`)
w(`  -- superseded raster served, and each was LEGAL there only because the harbour's snap bought`)
w(`  -- it that many nautical miles of land exemption. Asked again with the allowance this file's`)
w(`  -- snap buys, both must come back as land. Proven able to fail before being written: at`)
w(`  -- generation each was put to the LIVE server twice — null on the old allowance, E_LAND on the`)
w(`  -- new — and the generator refuses to emit if either half comes back the other way.`)
{
  const o = overland[0]
  w(`  v_ref := voyage.path_refusal(v_was_0, ${o.port.lat}, ${o.port.lon}, ${o.dest.lat}, ${o.dest.lon}, 15,`)
  w(`             (select snap_nm from public.sea_reaches where code = ${q(o.port.code)}) + 25,`)
  w(`             (select snap_nm from public.sea_reaches where code = ${q(o.dest.code)}) + 25);`)
  w(`  if v_ref is null or v_ref not like 'E_LAND:%' then`)
  w(`    raise exception '${SHORT} self-assert FAIL: the course the superseded raster served ${o.port.code} (${o.port.name.replace(/'/g, "''")}) -> ${o.dest.code} was NOT refused as land under ${o.port.code}''s new ${snapNm.get(o.port.code).toFixed(2)} nm allowance (got [%]) — that harbour is still sailing overland', coalesce(v_ref, 'null');`)
  w(`  end if;`)
}
{
  const o = overland[1]
  w(`  v_ref := voyage.path_refusal(v_was_1, ${o.port.lat}, ${o.port.lon}, ${o.dest.lat}, ${o.dest.lon}, 15,`)
  w(`             (select snap_nm from public.sea_reaches where code = ${q(o.port.code)}) + 25,`)
  w(`             (select snap_nm from public.sea_reaches where code = ${q(o.dest.code)}) + 25);`)
  w(`  if v_ref is null or v_ref not like 'E_LAND:%' then`)
  w(`    raise exception '${SHORT} self-assert FAIL: the course the superseded raster served ${o.port.code} (${o.port.name.replace(/'/g, "''")}) -> ${o.dest.code} was NOT refused as land under ${o.port.code}''s new ${snapNm.get(o.port.code).toFixed(2)} nm allowance (got [%]) — that harbour is still sailing overland', coalesce(v_ref, 'null');`)
  w(`  end if;`)
}
w(`  -- …and the real water courses over the NEW raster are ACCEPTED — a raster that refused`)
w(`  --    everything would pass the two checks above and be useless.`)
w(`  v_ref := voyage.path_refusal(v_tok_nag, ${TOK.lat}, ${TOK.lon}, ${NAG.lat}, ${NAG.lon}, 15,`)
w(`             (select snap_nm from public.sea_reaches where code = ${q(TOK.code)}) + 25,`)
w(`             (select snap_nm from public.sea_reaches where code = ${q(NAG.code)}) + 25);`)
w(`  if v_ref is not null then`)
w(`    raise exception '${SHORT} self-assert FAIL: the real ${TOK.code}→${NAG.code} course out of Edo Bay was refused: %', v_ref;`)
w(`  end if;`)
w(`  v_ref := voyage.path_refusal(v_pat_cag, ${PAT.lat}, ${PAT.lon}, ${CAG.lat}, ${CAG.lon}, 15,`)
w(`             (select snap_nm from public.sea_reaches where code = ${q(PAT.code)}) + 25,`)
w(`             (select snap_nm from public.sea_reaches where code = ${q(CAG.code)}) + 25);`)
w(`  if v_ref is not null then`)
w(`    raise exception '${SHORT} self-assert FAIL: the real ${PAT.code}→${CAG.code} course out of the Gulf of Patras was refused: %', v_ref;`)
w(`  end if;`)
w(`  -- the straight line Lisbon→Barcelona across the whole of Iberia, 0046's own non-vacuity control`)
w(`  v_ref := voyage.path_refusal(`)
w(`             jsonb_build_array(jsonb_build_array(${LIS.lat}, ${LIS.lon}), jsonb_build_array(${BCN.lat}, ${BCN.lon})),`)
w(`             ${LIS.lat}, ${LIS.lon}, ${BCN.lat}, ${BCN.lon}, 15, 40, 40);`)
w(`  if v_ref is null or v_ref not like 'E_LAND:%' then`)
w(`    raise exception '${SHORT} self-assert FAIL: a straight Lisbon→Barcelona line across Iberia was NOT refused as land (got [%])', coalesce(v_ref, 'null');`)
w(`  end if;`)
w(`  -- a course that joins the wrong ends is refused as itself, not as land`)
w(`  v_ref := voyage.path_refusal(v_lis_cad, ${CAD.lat}, ${CAD.lon}, ${LIS.lat}, ${LIS.lon}, 15, 40, 40);`)
w(`  if v_ref is null or v_ref not like 'E_OFF_COURSE:%' then`)
w(`    raise exception '${SHORT} self-assert FAIL: a course starting 250 nm from the stated origin was not refused E_OFF_COURSE (got [%])', coalesce(v_ref, 'null');`)
w(`  end if;`)
w(`  -- and a non-course is refused as a shape`)
w(`  if voyage.path_refusal('[[1,2]]'::jsonb, 0, 0, 0, 0, 15, 0, 0) not like 'E_BAD_PATH:%' then`)
w(`    raise exception '${SHORT} self-assert FAIL: a one-point course was not refused E_BAD_PATH';`)
w(`  end if;`)
w()
w(`  -- (h) the posture is 0046's, unchanged: world data readable, the two functions server-only`)
w(`  if not has_table_privilege('authenticated', 'public.sea_reaches', 'select')`)
w(`     or has_function_privilege('anon', 'voyage.path_refusal(jsonb, numeric, numeric, numeric, numeric, numeric, numeric, numeric)', 'execute')`)
w(`     or has_function_privilege('authenticated', 'voyage.path_nm(jsonb)', 'execute')`)
w(`     or (select count(*) from public.client_write_grants()) <> 0 then`)
w(`    raise exception '${SHORT} self-assert FAIL: the grant posture is wrong';`)
w(`  end if;`)
w()
w(`  raise notice '${SHORT} self-assert ok: FORTY HARBOURS STOP SAILING OVERLAND. The sea is one raster (${COLS}x${ROWS}, % bytes, ${CONTROLS.length} named control cells read back through get_bit, each harbour opened paired with land beside it that stayed land, the Antarctic closure pinned open at 59S and shut at 61S). The ${offenders.length} harbours that snapped over ${OVER} nm now snap % nm at worst, every one of them measured ACROSS the threshold in this transaction (worst before ${offenders[0].code} ${appliedSnap.get(offenders[0].code).toFixed(2)} nm), and no harbour already inside it moved. The courses the superseded raster served out of ${overland[0].port.name} and ${overland[1].port.name} are refused as E_LAND on their own new allowances, while real water courses over the same ground are accepted. Every one of % places reaches every other with a symmetric sailed distance never under the great circle. ${pairSame.toLocaleString('en')} pair readings are identical, ${pairMovedAtFixed.length.toLocaleString('en')} moved at a fixed harbour and ${pairMovedElsewhere.length.toLocaleString('en')} elsewhere, none of those by more than ${worstElsewhere.nm.toFixed(1)} nm / ${(worstElsewherePct.pct * 100).toFixed(2)}%%. The six long roads are unchanged to 0.1 nm (${ALX.code}->${ADE.code} ${Math.round(alxAdeNm)} nm round the Cape, ${VER.code}->${ACA.code} ${Math.round(verAcaNm)} nm round the Horn), the Arctic stays closed (${LIS.code}->${NAG.code} % nm), and ${PAN.code}->${POR.code} is pinned unchanged at ${reaches.get(PAN.code).get(POR.code).toFixed(1)} nm — a defect this file names and does not fix. ${healed.length} newly opened cell(s) answer their sea by name; 0 client write grants',`)
w(`    octet_length(r.cells),`)
w(`    (select round(max(snap_nm), 2) from public.sea_reaches),`)
w(`    v_ports,`)
w(`    (select (reaches->>${q(NAG.code)})::numeric from public.sea_reaches where code = ${q(LIS.code)});`)
w(`end $$;`)
w()
w(`drop table _${SHORT}_before;`)
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
