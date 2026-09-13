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
// ── WHAT 0085 ADDED: A ROADSTEAD LIES ON THE CHANNEL (owner row 78) ─────────────────────────────
// The owner, 2026-09-13: "in map, the circle should point out to ocean, but london for example
// the circle is in land. What is the point of the circle then?" London's roadstead was the CENTRE
// of its nearest water cell, (51.375, -0.125) — 8 nm south of the Thames, inside the GB polygon of
// data/world-110m.json, 36 nm from the nearest coastline. That cell is water ONLY because the
// authored `thames-scheldt` CHANNEL carved it (scripts/sea-grid.mjs, point [51.5, -0.1]); the land
// data itself says land. A carved cell is water the map does not draw, so its centre is a point on
// a picture of nothing. MEASURED over all 238 places before deciding: 25 places snap to a carved
// cell — 9 off the quay (8 of whose cell-centre roadsteads sit inside a land polygon: BSR COP HAM
// KHA LON OSA SAK THA; the 9th, LAR, sits 2.5 nm off the coast in polygon water) and 16 whose OWN
// cell is carved (ARP AYU BEL BOR BRS BUE GUA HOO MID NAN QUE RIG SNL SUE SVQ TAL — river ports the
// carve reaches, seeded at snap 0 as their own roadstead, so no line and no ring was ever drawn).
//
// THE RULE, stated once, in `roadsteadOf` below and in `voyage.water_roadstead` in SQL:
//   * the nearest sailable cell is found as before (snapToNav — 12 rings, minimum distance);
//   * if that cell was WATER BEFORE ANY CARVE (scripts/sea-grid.mjs preCarveGrid), the roadstead
//     is what 0076 said: the quay itself at 0 nm when the quay's own cell is water, else the cell
//     centre;
//   * if that cell is CARVED (land in the data, sea in the raster), the roadstead is THE POINT ON
//     THE CARVING CHANNEL'S POLYLINE NEAREST THE QUAY, rounded to 3 dp, and snap_nm is measured to
//     THAT point — so gc(quay, roadstead) = snap_nm still holds on every row. The whole polyline,
//     not the part inside the cell: measured over all 25, the two differ by under 0.2 nm except
//     Riga (4.53 vs 4.69) and Tallinn (0.77 vs 1.40), and the unconstrained foot is the simpler
//     rule to state in two languages and prove equal.
// The channel polylines stay ONE source — scripts/sea-grid.mjs CHANNELS — and cross the wire into
// `voyage.channels` (seeded here, whole, every run) so the SQL twin can answer the same point and
// self-assert (e) can keep cross-checking every row. sea-grid.mjs still declares no snap rule
// (tests/duplication.spec.ts): it says what the carve DID (`carveInventory().carved`), never where
// a roadstead is.
// WHAT THIS PROVES, AND WHERE: the land-polygon check (no off-quay roadstead inside a coastline
// unless it lies on a channel) runs HERE, in Node, over data/world-110m.json — it needs the
// polygons, which SQL does not hold. SQL proves the cheaper half: every channel roadstead lies on
// its channel's polyline (to rounding), every seeded point equals what voyage.water_roadstead
// answers, and the named control (London) is on the Thames line at a sane distance.
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
// THE THIRD SNAP RULE IS RETIRED (2026-09-08). `snapToWater` answered "the nearest water cell"
// with a DIFFERENT rule from the one this file and the server use — 8 rings, first-in-scan-order,
// no distance — where `snapToNav` (src/lib/sea/pathfind.ts:149) and `voyage.water_roadstead` are
// 12 rings and the MINIMUM distance, and agree. MEASURED over all 224 harbours before it moved:
// the two pick a different cell for **87** of them, the scan-order rule always the farther —
// Dublin 34.39 nm off the quay against 13.89, Bergen +18.49, Boston +17.12, worst +20.51.
// It reached no live data: its spur legs went into public.legs, which 0049 dropped. So it moved
// out of scripts/sea-grid.mjs into its one dead caller, scripts/build-sea-places.mjs, which
// exports nothing and refuses to run. This module now imports a raster and an authored carve, and
// there is no second snap rule to be careful of.
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
import { buildSeaCarve, CHANNELS, landPolygons, COLS, ROWS, CELL_DEG, cellLat, cellLon, rowOf, colOf, inIce, inReclaimed, RECLAIMED } from './sea-grid.mjs'
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
const MIGRATION = '20260818000085_a_roadstead_lies_on_the_channel.sql'
const SHORT = MIGRATION.slice(10, 14)
const OUT = path.join(MIGRATIONS_DIR, MIGRATION)
const BITS = 2

// See the header. TRUE for 0076 only — the file that introduces the roadstead. A later raster
// migration flips this to false; leaving it true makes the apply fail loudly at pg_temp.recut.
// 0079 is that later migration: 0076 already made the columns NOT NULL and already re-cut the
// mover, so this run carries the raster, the membership patch and the distances, and nothing else.
const INTRODUCES_THE_ROADSTEAD = false

// ── 1. The navigable grid ──────────────────────────────────────────────────────────────────────
// buildSeaGrid() is the WHOLE rule now — land, channels and the ice at both poles. Nothing is
// added, removed or clamped here; see the header.
console.log('building the navigable grid…')
const { water: cells, carved } = buildSeaCarve()
const nav = { cols: COLS, rows: ROWS, cellDeg: CELL_DEG, cells }
// cell index -> the ONE channel whose carve turned that cell of dry land into sea. Measured this
// run and asserted, not assumed: no carved cell belongs to two channels, because a roadstead in a
// shared cell would have two polylines to lie on and the rule would have to pick.
const carvedBy = new Map()
for (const [id, idxs] of carved) {
  for (const k of idxs) {
    if (carvedBy.has(k)) {
      throw new Error(`cell ${k} (${cellLat((k / COLS) | 0)}, ${cellLon(k % COLS)}) is carved by both ${carvedBy.get(k)} and ${id} — the roadstead rule needs one channel per carved cell`)
    }
    carvedBy.set(k, id)
  }
}
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
// ONE function decides the roadstead — `roadsteadOf` — and it is the twin of voyage.water_roadstead
// emitted below; self-assert (e) proves the two agree on every row. Three arms, and only the third
// is 0085's:
//   * a place whose OWN cell is sailable water that the land data ALSO calls water IS its own
//     roadstead, at distance 0. Not the centre of that cell: the centre can lie 10.6 nm from a
//     place whose snap_nm is 0, and the helper line the chart draws must be snap_nm long or it is
//     a picture of a different number (src/chart/route.ts:8-12);
//   * a place whose nearest sailable cell was water before any carve takes the CENTRE of that cell;
//   * a place whose nearest sailable cell (its own included) is CARVED takes the point on the
//     carving channel's polyline nearest the quay, at 3 dp, with snap_nm measured to that point.
//     A cell centre there is a point the land data calls land — London's was 8 nm into Kent.
const r3 = (x) => Number(x.toFixed(3))
const cellIdxOf = (lat, lon) => rowOf(lat) * COLS + colOf(lon)

/** THE FOOT: the point on one channel's polyline nearest (lat, lon), to 3 dp, and how far it is.
 *  Planar per segment — longitude scaled by cos(lat) of the QUERY point — then clamped to the
 *  segment and measured back by the one distance authority. voyage.channel_foot is this, in
 *  plpgsql, operation for operation (same float64 arithmetic, same rounding, same tie order), so
 *  the two answer the same 3-dp point and self-assert (e) can demand equality rather than a
 *  tolerance. Change one and you change the other in the same commit, or (e) goes red. */
function channelFoot(ch, lat, lon) {
  const k = Math.cos(lat * (Math.PI / 180))
  let best = null
  for (let i = 1; i < ch.points.length; i++) {
    const [alat, alon] = ch.points[i - 1]
    const [blat, blon] = ch.points[i]
    const ax = (alon - lon) * k
    const ay = alat - lat
    const bx = (blon - lon) * k
    const by = blat - lat
    const dx = bx - ax
    const dy = by - ay
    const len2 = dx * dx + dy * dy
    let t = len2 === 0 ? 0 : -(ax * dx + ay * dy) / len2
    t = Math.max(0, Math.min(1, t))
    const flat = r3(alat + t * (blat - alat))
    const flon = r3(alon + t * (blon - alon))
    const d = gcNm(lat, lon, flat, flon)
    if (best === null || d < best.nm) best = { lat: flat, lon: flon, nm: d }
  }
  if (!best) throw new Error(`channel ${ch.id} has fewer than two points`)
  return best
}

/** THE ROADSTEAD. `{ lat, lon, nm, channel }` — channel is null unless the third arm applied. */
function roadsteadOf(p) {
  const s = snapToNav(nav, p.lat, p.lon)
  if (!s) throw new Error(`${p.code} ${p.name}: no sailable water within reach of its coordinate`)
  const idx = s.row * COLS + s.col
  const channelId = carvedBy.get(idx)
  if (channelId === undefined) {
    // Water the land data agrees is water: 0076's rule, unchanged.
    const exact =
      s.snapNm === 0
        ? { lat: p.lat, lon: p.lon }
        : { lat: navCellLat(nav, s.row), lon: navCellLon(nav, s.col) }
    const point = { lat: r3(exact.lat), lon: r3(exact.lon) }
    // 3 dp must be LOSSLESS here, not merely close: a cell centre is a multiple of 0.125° and a
    // quay is 2 dp. Assert it rather than trusting the arithmetic.
    if (Math.abs(point.lat - exact.lat) > 1e-9 || Math.abs(point.lon - exact.lon) > 1e-9) {
      throw new Error(
        `${p.code}: rounding the roadstead to 3 dp LOST something (${exact.lat},${exact.lon} → ` +
          `${point.lat},${point.lon}) — 3 dp is only exact for a 0.25° raster and 2 dp port coordinates`,
      )
    }
    return { ...point, nm: s.snapNm, channel: null }
  }
  // Carved: the raster says sea and the land data says land. The roadstead lies on the channel.
  const ch = CHANNELS.find((c) => c.id === channelId)
  if (!ch) throw new Error(`${p.code}: carved by "${channelId}", which is not in CHANNELS`)
  const foot = channelFoot(ch, p.lat, p.lon)
  // The rounded foot must itself stand on sailable water, or the course would begin on land. The
  // polyline is sampled every 5 nm when it is carved, so a foot between two samples could in
  // principle fall in a cell the carve skipped — refused here, never seeded.
  if (cells[cellIdxOf(foot.lat, foot.lon)] !== 1) {
    throw new Error(
      `${p.code}: the point on ${ch.id} nearest the quay, (${foot.lat}, ${foot.lon}), is not a sailable ` +
        `cell — the channel's carve does not cover its own polyline there`,
    )
  }
  return { lat: foot.lat, lon: foot.lon, nm: foot.nm, channel: ch.id }
}

console.log('measuring every place’s roadstead…')
const reaches = new Map() // code -> Map(code -> nm)
const snapNm = new Map() // code -> nm from the true coordinate to its roadstead
const roads = new Map() // code -> { lat, lon, nm, channel } — the roadstead, 3 dp
for (const p of ports) reaches.set(p.code, new Map())
for (const p of ports) {
  const road = roadsteadOf(p)
  // A NON-FINITE COORDINATE MUST BE CAUGHT HERE, not by the comparisons below: every `>` test
  // against a NaN is false, so a broken measurement would pass all of them and be seeded.
  if (![road.lat, road.lon, road.nm].every(Number.isFinite)) {
    throw new Error(`${p.code}: the roadstead measured (${road.lat}, ${road.lon}) at ${road.nm} nm`)
  }
  // The invariant the chart's helper line stands on: the line drawn IS the distance measured.
  const drawn = gcNm(p.lat, p.lon, road.lat, road.lon)
  if (Math.abs(drawn - road.nm) > 1e-6) {
    throw new Error(
      `${p.code}: the roadstead lies ${drawn.toFixed(4)} nm off the quay but snap_nm is ` +
        `${road.nm.toFixed(4)} — the helper line would not be the measured distance`,
    )
  }
  snapNm.set(p.code, road.nm)
  roads.set(p.code, road)
}
const onChannel = ports.filter((p) => roads.get(p.code).channel !== null)
console.log(
  `  ${onChannel.length} place(s) snap to a CARVED cell and take their roadstead on the channel: ` +
    onChannel.map((p) => `${p.code}@${roads.get(p.code).channel} ${snapNm.get(p.code).toFixed(2)}`).join(' · '),
)
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
//     from a latitude repeated here. The name is KEPT: ice is sea nobody may sail.
//   * membership on water this mask closes inside an authored RECLAMATION is the same fact with
//     the OPPOSITE answer. 0040 was cut from the carved grid, so a malformed CHANNELS record could
//     make it name cells that were never water at all; withdrawing the carve makes them land, and
//     land carries no sea, so their membership is ZEROED. See sea-grid.mjs's RECLAIMED for why it
//     is authored rather than inferred, and why it is not a flag on ICE.
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
const reclaimed = [] // { lat, lon, claim } — cells returned to land; membership zeroed, printed
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
    const lat = cellLat(row)
    const lon = cellLon(col)
    if (inIce(lat, lon)) { iced++; continue }
    const claim = inReclaimed(lat, lon)
    if (claim) {
      // LAND AGAIN, so it carries no sea. The patch row is materialised the same way a heal's is,
      // and the byte goes to 0 — the one value build-sea-raster.mjs uses for "no sea here".
      if (!seaPatch.has(row)) seaPatch.set(row, Uint8Array.from(seaByRow.get(row)))
      seaPatch.get(row)[col] = 0
      membership[i] = 0
      reclaimed.push({ row, col, lat, lon, claim })
      continue
    }
    northWounds.push(`(${lat.toFixed(2)}, ${lon.toFixed(2)})`)
  }
  if (northWounds.length > 0) {
    throw new Error(
      `sea-membership on water this mask closes OUTSIDE every ICE closure and every authored ` +
        `RECLAMATION (${northWounds.length} cell(s)) — the two rasters disagree where nothing ` +
        `authored explains it: ${northWounds.slice(0, 12).join(', ')}`,
    )
  }

  // EVERY RECLAMATION MUST PAY OUT EXACTLY WHAT IT PROMISED, and every one must do something.
  // The cells are derived from CHANNELS, so this count is the only place a reviewer's expectation
  // and the raster's arithmetic meet. A claim that reclaims nothing is a stale entry still
  // licensing a silent membership delete, which is the whole thing this list exists to prevent.
  // A LANDED claim (sea-grid.mjs RECLAIMED[].landed names the migration that carried it) is the
  // mirror case: the applied chain already holds those cells at zero, so this run must find
  // NOTHING to reclaim — a non-zero count means the membership grew back and is refused just as
  // loudly. Only an unlanded claim must pay out exactly what it promised.
  for (const r of RECLAIMED) {
    const got = reclaimed.filter((x) => x.claim.id === r.id).length
    const want = r.landed ? 0 : r.expect
    if (got !== want) {
      throw new Error(
        `RECLAIMED "${r.id}" ${r.landed ? `landed in ${r.landed} and should leave 0 cell(s) to reclaim` : `expects ${r.expect} cell(s)`}, ` +
          `and this raster reclaims ${got} — either the carve it withdraws changed, or the ` +
          `expectation is stale. Neither may pass silently: a reclamation is a DELETE of sea membership.`,
      )
    }
  }
  console.log(
    `  cross-check vs public.sea_cells (0040): every reachable navigable cell carries a sea ` +
      `(${healed.length} newly opened cell(s) healed to the nearest sea by water); ` +
      `${reclaimed.length} cell(s) reclaimed as land and their membership zeroed; ` +
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
const AYU = byName('Ayutthaya')
const THA = byName('Thanlyin')
const HAM = byName('Hamburg')
const LUB = byName('Lubeck', 'Lübeck')
const LON = byName('London')

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
  (await db.query(`select code, snap_nm::float8 as snap_nm, roadstead_lat::float8 as rlat,
                          roadstead_lon::float8 as rlon, reaches from public.sea_reaches`)).rows.map((r) => [
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

// ── THE LAND DATA ITSELF, asked about every roadstead — the applied table's and this run's ──────
// A carved cell is water in the raster and land in the polygons it was cut from, so a roadstead
// at its centre passes every raster check (0079's (d) asked the raster) while standing on land.
// Only the polygons can say so, and SQL does not hold them, so this is the layer that proves it:
//   * RED, against the table the chain already serves: every off-quay roadstead inside a
//     coastline polygon, by name. Printed into the header as the defect this file repairs.
//   * GREEN, against what this run seeds: an off-quay roadstead is EITHER outside every land
//     polygon OR on a channel's polyline. Nothing else is emitted. Said plainly: a river IS inside
//     the coastline polygon, so "no roadstead inside land" cannot be true of a river port's — the
//     absolute rule is the disjunction, and the channel half is proven in SQL (self-assert (q)).
const LAND = landPolygons()
const inRing = (ring, lat, lon) => {
  let inside = false
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [x1, y1] = ring[j]
    const [x2, y2] = ring[i]
    if (y1 > lat !== y2 > lat && lon < x1 + ((lat - y1) / (y2 - y1)) * (x2 - x1)) inside = !inside
  }
  return inside
}
const insideLand = (lat, lon) => {
  for (const rings of LAND) {
    let n = 0
    for (const ring of rings) if (inRing(ring, lat, lon)) n++
    if (n % 2 === 1) return true
  }
  return false
}
const landRed = [...appliedReaches.values()]
  .filter((r) => r.snap_nm > 0 && insideLand(r.rlat, r.rlon))
  .map((r) => r.code)
  .sort()
const landGreen = ports.filter((p) => {
  const r = roads.get(p.code)
  return r.nm > 0 && r.channel === null && insideLand(r.lat, r.lon)
})
console.log(
  `  LAND CHECK against the APPLIED table: ${landRed.length} off-quay roadstead(s) inside a coastline polygon` +
    (landRed.length ? ` — ${landRed.join(' ')}` : ''),
)
console.log(
  `  LAND CHECK against THIS run: ${landGreen.length} off-quay roadstead(s) inside a coastline polygon and not on a channel` +
    (landGreen.length ? ` — ${landGreen.map((p) => p.code).join(' ')}` : ''),
)
if (landGreen.length > 0) {
  throw new Error(
    `${landGreen.length} roadstead(s) would be seeded inside a land polygon without a channel under them: ` +
      landGreen.map((p) => `${p.code} (${roads.get(p.code).lat}, ${roads.get(p.code).lon})`).join(', '),
  )
}
const channelInLand = onChannel.filter((p) => insideLand(roads.get(p.code).lat, roads.get(p.code).lon)).length

// ── WHAT MOVED: every roadstead this run seeds somewhere other than where the chain has it ──────
const moved = ports
  .map((p) => ({ p, was: appliedReaches.get(p.code), now: roads.get(p.code) }))
  .filter(({ was, now }) => was && (was.rlat !== now.lat || was.rlon !== now.lon))
console.log(`  ${moved.length} roadstead(s) move against the applied table:`)
for (const { p, was, now } of moved) {
  console.log(
    `    ${p.code.padEnd(4)} ${p.name.padEnd(22)} (${was.rlat}, ${was.rlon}) ${was.snap_nm.toFixed(2).padStart(6)} nm → ` +
      `(${now.lat}, ${now.lon}) ${now.nm.toFixed(2).padStart(6)} nm on ${now.channel}`,
  )
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
w(`-- ${SHORT} — A ROADSTEAD LIES ON THE CHANNEL`)
w(`--        A port the carve reaches is reached from the channel itself, not from the centre of a`)
w(`--        cell the land data calls land — and the river ports get their line and their ring.`)
w(`-- ═══════════════════════════════════════════════════════════════════════════════════════════════`)
w(`--`)
w(`-- GENERATED by scripts/build-sea-migration.mjs — do not hand-edit. Change the sea (scripts/`)
w(`-- sea-grid.mjs) or the ports and cut a NEW migration; an applied one is history.`)
w(`--`)
w(`-- ── THE OWNER, VERBATIM (docs/OWNER_REQUESTS.md, row 78, 2026-09-13) ─────────────────────────────`)
w(`--   "in map, the circle should point out to ocean, but london for example the circle is in`)
w(`--    land. What is the point of the circle then?"`)
w(`--`)
w(`-- ── WHAT SAYS THE OPPOSITE, NAMED ──────────────────────────────────────────────────────────────`)
w(`--   * 0076/0079 seeded every off-quay roadstead as the CENTRE of the nearest sailable cell`)
w(`--     (scripts/build-sea-migration.mjs, the navCellLat/navCellLon arm; voyage.water_roadstead`)
w(`--     0076:207-208). London's nearest sailable cell is (51.375, -0.125): 8.11 nm from the quay,`)
w(`--     8 nm SOUTH of the Thames, inside the United Kingdom polygon of data/world-110m.json and`)
w(`--     36 nm from its nearest coastline. That cell is water for one reason only — the authored`)
w(`--     \`thames-scheldt\` CHANNEL carved it (scripts/sea-grid.mjs, point [51.5, -0.1]); the`)
w(`--     scan-filled land data (preCarveGrid) says land. The chart drew the ring exactly where it`)
w(`--     was served (src/lib/geo/projection.ts, src/chart/roadsteads.ts), so this is a server`)
w(`--     derivation defect and not a drawing defect.`)
w(`--   * 0079's self-assert (d), "every roadstead stands on sailable water", asked the CARVED raster`)
w(`--     — which is why it passed on a point the raster's own source polygon calls land.`)
w(`--   * A port whose OWN cell the carve opened (Seville, Antwerp, Nantes, Bordeaux and twelve`)
w(`--     more) was seeded at snap 0 as its own roadstead, so no dotted line and no ring was ever`)
w(`--     drawn for a river port at all.`)
w(`--   * scripts/db/proof-courses.mjs carried a SECOND copy of the roadstead rule (its own`)
w(`--     roadsteadOf, snapping the raster itself). Folded in the same change: the proofs now read`)
w(`--     public.sea_reaches, the one served answer, and re-derive nothing.`)
w(`--`)
w(`-- ── THE RULE (one function each side: roadsteadOf in the generator, voyage.water_roadstead here) ─`)
w(`--   1. The nearest sailable cell is found as 0076 found it: snapToNav / the 12-ring loop below,`)
w(`--      the minimum-distance cell.`)
w(`--   2. If that cell was water BEFORE any carve, the roadstead is what 0076 said — the quay itself`)
w(`--      at 0 nm when the quay's own cell is water, otherwise the cell centre.`)
w(`--   3. If that cell is CARVED — sea in the raster, land in the data — the roadstead is THE POINT`)
w(`--      ON THE CARVING CHANNEL'S POLYLINE NEAREST THE QUAY, rounded to 3 dp, and snap_nm is`)
w(`--      measured to THAT point, so gc(quay, roadstead) = snap_nm still holds on every row and the`)
w(`--      helper line the chart draws is still the distance the table measured. The whole polyline`)
w(`--      is searched, not the part inside the cell: over all ${onChannel.length} such places the two answers`)
w(`--      differ by under 0.2 nm except Riga (4.53 vs 4.69) and Tallinn (0.77 vs 1.40), and the`)
w(`--      unconstrained foot is the simpler rule to state in two languages and prove equal.`)
w(`--   The channel polylines have ONE source, scripts/sea-grid.mjs CHANNELS. They cross the wire`)
w(`--   into voyage.channels below — with the cells of dry land each one opened, which SQL cannot`)
w(`--   re-derive because it does not hold the land data — so the SQL twin answers the same point.`)
w(`--   sea-grid.mjs still declares no snap rule (tests/duplication.spec.ts): it says what the carve`)
w(`--   DID, never where a roadstead is.`)
w(`--`)
w(`-- ── WHAT THIS DOES ─────────────────────────────────────────────────────────────────────────────`)
w(`--   1. voyage.channels — the ${CHANNELS.length} authored channels: id, name, the polyline, the ${carvedBy.size} cells of`)
w(`--      dry land the carve opened (as sea_raster cell indices), and opens_land, CHECKed equal to`)
w(`--      that list's length. Server-only, replaced whole on every run like sea_reaches.`)
w(`--   2. voyage.channel_foot(channel, lat, lon) — the point on one channel nearest a point, at`)
w(`--      3 dp, with its distance. The generator's channelFoot, operation for operation.`)
w(`--   3. voyage.water_roadstead is DROPPED and RE-CREATED with a fourth column, channel: the`)
w(`--      12-ring search is 0076's unchanged; the winning cell is then looked up in voyage.channels`)
w(`--      and, if the carve opened it, the answer is channel_foot on that channel. water_snap_nm`)
w(`--      (one line over it) is untouched and still answers the distance.`)
w(`--   4. public.sea_reaches is replaced WHOLE — snap_nm, the roadstead columns, and \`reaches\``)
w(`--      re-measured roadstead to roadstead (the 0052:92-94 delete-and-insert, exactly), because`)
w(`--      ${moved.length} roadsteads move and every passage to or from them is measured from the new point.`)
w(`--`)
w(`-- ── WHAT IT SUPERSEDES, AND WHY ────────────────────────────────────────────────────────────────`)
w(`--   voyage.water_roadstead(numeric, numeric), created at 0076:175. This file SUPERSEDES it: the`)
w(`--   return shape gains \`channel text\` (null unless rule 3 applied), which \`create or replace\``)
w(`--   cannot do, so it is dropped and re-created and its revoke re-issued (docs/NO_SPAGHETTI.md §3,`)
w(`--   "re-issue the grants, because a dropped function takes its ACL with it"). Its one caller,`)
w(`--   voyage.water_snap_nm(numeric, numeric) (0076:227), selects \`nm\` by name and is untouched.`)
w(`--   The supersede is a NO-OP for every place whose nearest sailable cell the land data also calls`)
w(`--   water — asserted below by requiring the seeded point to equal the function's answer on all`)
w(`--   ${ports.length} rows, of which ${ports.length - onChannel.length} are exactly what 0079 seeded.`)
w(`--   Nothing else is re-cut: cmd.do_sail, voyage.assert_paths_water and world.snapshot read`)
w(`--   sea_reaches and serve the new point without a change of body.`)
w(`--`)
w(`-- ── AND WHAT IT DELIBERATELY DOES NOT ──────────────────────────────────────────────────────────`)
w(`--   * It does not move the roadstead of any place whose nearest sailable cell is water in the`)
w(`--     land data too — ${ports.length - onChannel.length} of ${ports.length}, Amsterdam, Lisbon, Cadiz and Plymouth among them.`)
w(`--   * It does not walk a river port's roadstead SEAWARD to the coastline polygon. Measured and`)
w(`--     not chosen: London's would land 52 nm out at (51.539, 1.263), Hamburg's 53 nm out, and the`)
w(`--     whole Guadalquivir and Yangon channels lie inside their polygons so Seville, Sanlucar and`)
w(`--     Thanlyin would have no such point at all. The course begins at the roadstead and sails the`)
w(`--     carved river (0076); moving the roadstead to the river mouth would move the start of every`)
w(`--     such passage, which is a movement-model change and not this row.`)
w(`--   * It does not touch the drawn coastline. A further ~10 roadsteads sit in polygon water but`)
w(`--     inside the DRAWN coast, because src/chart/coastlineBuild.ts decimates the coastline`)
w(`--     (COASTLINE_TOLERANCE_DEG). That is a chart defect and is left for its own change; moving a`)
w(`--     correct roadstead to suit a simplified drawing would be the wrong authority moving.`)
w(`--   * It opens and closes no CHANNEL, moves no price knob, re-cuts no mover, touches no player row.`)
if (!waterMoved) {
  w(`--   * IT DOES NOT MOVE THE WATER. The grid built by this run is BYTE-IDENTICAL to the one`)
  w(`--     public.sea_raster already holds (${nfmt(newWater)} water cells, ${packed.length} packed bytes, +0 opened,`)
  w(`--     -0 closed), so the raster row is not rewritten. Only what the table SAYS about that`)
  w(`--     water changes.`)
}
w(`--`)
w(`-- ── EVIDENCE, MEASURED BY THIS RUN AGAINST THE APPLIED CHAIN ───────────────────────────────────`)
w(`--   THE LAND DATA, asked of every off-quay roadstead the chain serves today (RED): ${landRed.length} stand inside`)
w(`--   a coastline polygon of data/world-110m.json — ${landRed.join(' ')}.`)
w(`--   Asked of what this file seeds (GREEN): ${landGreen.length} stand inside a coastline polygon without a channel`)
w(`--   under them. ${channelInLand} of the ${onChannel.length} channel roadsteads DO lie inside a polygon, because a river`)
w(`--   does — that is what the channel is for, and self-assert (q) proves each of them is ON it.`)
w(`--`)
w(`--   THE ${moved.length} ROADSTEADS THAT MOVE (was → now; snap in nm; the channel under the new point):`)
for (const { p, was, now } of moved) {
  w(`--     ${p.code} ${p.name.padEnd(22)} (${was.rlat}, ${was.rlon}) ${was.snap_nm.toFixed(2).padStart(6)} → (${now.lat}, ${now.lon}) ${now.nm.toFixed(2).padStart(6)}  ${now.channel}`)
}
w(`--   ${onChannel.filter((p) => appliedReaches.get(p.code)?.snap_nm === 0 && roads.get(p.code).nm > 0).length} of them were seeded at snap 0 — their own quay — and now carry a roadstead off it, so the`)
w(`--   dotted line and the ring appear for a river port for the first time. Bristol's quay IS a`)
w(`--   vertex of the Severn channel, so its roadstead stays the quay at 0 nm — the rule applied, not`)
w(`--   skipped.`)
w(`--`)
w(`--   THE ROADSTEADS, the census 0076 keeps: ${ports.length} places; ${ownWater} stand on sailable water and are their own`)
w(`--   roadstead at 0 nm; ${offQuay} carry a real roadstead off the quay. Over 10 nm: ${overNm(10)}. Over`)
w(`--   20 nm: ${overNm(20)}. Over 30 nm: ${overNm(30)}. Over 50 nm: ${overNm(50)}. Worst:`)
w(`--     ${worst.slice(0, 8).map(([c, n]) => `${c} ${n.toFixed(2)}`).join(' · ')}`)
w(`--   ${distinctCells} distinct points for ${ports.length} places — roadsteads are NOT unique and nothing may assume it.`)
w(`--`)
w(`--   THE DISTANCE EFFECT, all ${deltas.length.toLocaleString('en')} pairs, this table against the one the chain serves:`)
w(`--     mean ${meanD.toFixed(2)} nm · median ${medD.toFixed(2)} nm · MEDIAN ${medPct.toFixed(2)} % · ${under05.toFixed(1)} % of pairs move under 0.5 %`)
w(`--     ${over5.toFixed(2)} % of pairs move over 5 %. Every price knob is untouched.`)
w(`--`)
w(`--   THE ${bigMoves.length} PAIR(S) THAT MOVE MORE THAN 500 nm:`)
for (const m of bigMoves.sort((x, y) => Math.abs(y.after - y.before) - Math.abs(x.after - x.before))) {
  w(`--     ${(m.a.name + ' → ' + m.b.name).padEnd(34)} ${m.before.toFixed(1).padStart(9)} → ${m.after.toFixed(1).padStart(10)} nm`)
}
w(`--`)
w(`--   THE LAND GUARD AT ITS OWN SAMPLING, asked of voyage.path_refusal on the applied chain:`)
for (const b of breach) {
  w(`--     ${(b.a.name + ' → ' + b.b.name).padEnd(30)} quay→quay ${b.cityNm.toFixed(1)} nm under ${b.sa.toFixed(2)}+25 / ${b.sb.toFixed(2)}+25 nm: ACCEPTED`)
  w(`--     ${''.padEnd(30)} roads→roads under 25 / 25 nm: ${b.roadRef}`)
}
w(`--`)
w(`--   PRECISION. A cell-centre or own-quay roadstead is exact at 3 dp (a cell centre is a multiple`)
w(`--   of 0.125°, a quay is 2 dp) and that is asserted at generation. A CHANNEL roadstead is DEFINED`)
w(`--   as the 3-dp rounding of the foot — under 0.06 nm from the exact foot — and snap_nm is measured`)
w(`--   to the rounded point, so the drawn line is still the stored distance to the metre.`)
w(`--`)
w(`-- Depends on: 0002 (ports, seas, gc_distance_nm), 0040 (sea_cells, voyage.sea_at), 0046 (the two`)
w(`-- tables, voyage.path_nm, voyage.path_refusal), 0047 (cmd.do_sail, voyage.water_snap_nm,`)
w(`-- voyage.assert_paths_water), 0076 (roadstead columns, voyage.water_roadstead, the mover's`)
w(`-- roadstead hunks), 0079 (the raster this run finds byte-identical), and the port rows of`)
w(`-- 0003/0036/0041.`)
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

// ── 0085: THE CHANNELS CROSS THE WIRE, AND THE ROADSTEAD RULE READS THEM ──────────────────────
// Emitted on EVERY run, not behind a switch: the table is replaced whole like sea_reaches, and
// the two function bodies are full definitions (the generator is their one source), so a later
// sea migration carries the current rule rather than trusting that an earlier file did.
w(`-- ── 0085. THE CHANNELS, AS DATA ────────────────────────────────────────────────────────────────`)
w(`-- scripts/sea-grid.mjs CHANNELS is the ONE authority for "you may pass here"; this table is that`)
w(`-- list crossing the wire so the SQL roadstead rule can read it — never a second place to edit a`)
w(`-- channel. Two things ride with each polyline that SQL could not re-derive: the cells of DRY`)
w(`-- LAND the carve opened (the land polygons are not in the database), and opens_land, the count`)
w(`-- the authored list declares, CHECKed equal to that list's length so a stale seed cannot apply.`)
w(`-- Server-only: RLS on, no policy, no client grant — a player is served the roadstead, not the`)
w(`-- machinery that decided it.`)
w(`create table if not exists voyage.channels (`)
w(`  id           text primary key,`)
w(`  name         text  not null,`)
w(`  points       jsonb not null,`)
w(`  carved_cells jsonb not null,`)
w(`  opens_land   int   not null,`)
w(`  constraint channels_points_are_a_line`)
w(`    check (jsonb_typeof(points) = 'array' and jsonb_array_length(points) >= 2),`)
w(`  constraint channels_carve_is_counted`)
w(`    check (jsonb_typeof(carved_cells) = 'array' and jsonb_array_length(carved_cells) = opens_land)`)
w(`);`)
w(`comment on table voyage.channels is`)
w(`  'THE CHANNELS (0085): scripts/sea-grid.mjs CHANNELS as data, one row per authored strait or '`)
w(`  'river, replaced whole by every sea migration. points is the polyline [[lat, lon], ...] in '`)
w(`  'order along ONE water; carved_cells lists the public.sea_raster cell indices (row * cols + col) '`)
w(`  'of DRY LAND this carve turned into sea, measured against the scan-filled land data; opens_land '`)
w(`  'is the count the authored list declares. voyage.water_roadstead reads carved_cells to decide '`)
w(`  'that a roadstead lies on the channel rather than at a cell centre the land data calls land.';`)
w(`alter table voyage.channels enable row level security;`)
w(`revoke all on voyage.channels from public, anon, authenticated;`)
w(`delete from voyage.channels;`)
w(`insert into voyage.channels (id, name, points, carved_cells, opens_land) values`)
{
  const rows = CHANNELS.map((ch) => {
    const idxs = carved.get(ch.id) ?? []
    if (idxs.length !== ch.opensLand) throw new Error(`${ch.id}: ${idxs.length} carved cells against opensLand ${ch.opensLand}`)
    return `  (${q(ch.id)}, ${q(ch.name)}, ${j(ch.points)}, ${j(idxs)}, ${ch.opensLand})`
  })
  w(rows.join(',\n') + ';')
}
w()
w(`-- ── 0085. THE FOOT: the point on one channel nearest a point ───────────────────────────────────`)
w(`-- The generator's channelFoot, operation for operation: planar per segment with longitude scaled`)
w(`-- by cos(lat) of the QUERY point, clamped to the segment, rounded to 3 dp, measured back by the`)
w(`-- one distance authority, first segment wins a tie. Same float64 arithmetic in the same order,`)
w(`-- which is what lets self-assert (e) demand the seeded point EQUAL this answer on every row.`)
w(`create or replace function voyage.channel_foot(p_channel text, p_lat numeric, p_lon numeric)`)
w(`returns table (lat numeric, lon numeric, nm numeric)`)
w(`language plpgsql`)
w(`stable`)
w(`security definer`)
w(`set search_path = public, pg_temp`)
w(`as $cf$`)
w(`declare`)
w(`  v_pts  jsonb;`)
w(`  v_n    int;`)
w(`  i      int;`)
w(`  v_k    float8; v_alat float8; v_alon float8; v_blat float8; v_blon float8;`)
w(`  v_ax   float8; v_ay float8; v_bx float8; v_by float8; v_dx float8; v_dy float8;`)
w(`  v_len2 float8; v_t float8; v_d float8;`)
w(`  v_flat numeric; v_flon numeric;`)
w(`  v_best float8 := null; v_best_lat numeric; v_best_lon numeric;`)
w(`begin`)
w(`  select c.points into v_pts from voyage.channels c where c.id = p_channel;`)
w(`  if v_pts is null then`)
w(`    raise exception 'voyage.channel_foot: no channel named %', p_channel;`)
w(`  end if;`)
w(`  v_n := jsonb_array_length(v_pts);`)
w(`  v_k := cos(radians(p_lat::float8));`)
w(`  for i in 1 .. v_n - 1 loop`)
w(`    v_alat := (v_pts->(i - 1)->>0)::float8; v_alon := (v_pts->(i - 1)->>1)::float8;`)
w(`    v_blat := (v_pts->i->>0)::float8;       v_blon := (v_pts->i->>1)::float8;`)
w(`    v_ax := (v_alon - p_lon::float8) * v_k; v_ay := v_alat - p_lat::float8;`)
w(`    v_bx := (v_blon - p_lon::float8) * v_k; v_by := v_blat - p_lat::float8;`)
w(`    v_dx := v_bx - v_ax; v_dy := v_by - v_ay;`)
w(`    v_len2 := v_dx * v_dx + v_dy * v_dy;`)
w(`    v_t := case when v_len2 = 0 then 0 else -(v_ax * v_dx + v_ay * v_dy) / v_len2 end;`)
w(`    v_t := greatest(0, least(1, v_t));`)
w(`    v_flat := round((v_alat + v_t * (v_blat - v_alat))::numeric, 3);`)
w(`    v_flon := round((v_alon + v_t * (v_blon - v_alon))::numeric, 3);`)
w(`    v_d := voyage.gc_distance_nm(p_lat::float8, p_lon::float8, v_flat::float8, v_flon::float8);`)
w(`    if v_best is null or v_d < v_best then`)
w(`      v_best := v_d; v_best_lat := v_flat; v_best_lon := v_flon;`)
w(`    end if;`)
w(`  end loop;`)
w(`  lat := v_best_lat; lon := v_best_lon; nm := v_best::numeric;`)
w(`  return next;`)
w(`end $cf$;`)
w(`revoke all on function voyage.channel_foot(text, numeric, numeric) from public, anon, authenticated;`)
w()
w(`-- ── 0085. THE ROADSTEAD RULE, SUPERSEDING 0076's ──────────────────────────────────────────────`)
w(`-- The 12-ring search is 0076:199-217 unchanged; what is new is what happens to the winning cell.`)
w(`-- The return shape gains \`channel\`, so this is a DROP and a CREATE (a return type cannot be`)
w(`-- replaced) with the revoke re-issued. voyage.water_snap_nm — one line over this — is untouched.`)
w(`drop function voyage.water_roadstead(numeric, numeric);`)
w(`create function voyage.water_roadstead(p_lat numeric, p_lon numeric)`)
w(`returns table (nm numeric, lat numeric, lon numeric, channel text)`)
w(`language plpgsql`)
w(`stable`)
w(`security definer`)
w(`set search_path = public, pg_temp`)
w(`as $wr$`)
w(`declare`)
w(`  r public.sea_raster%rowtype;`)
w(`  v_row int; v_col int; ring int; dr int; dc int; rr int; cc int;`)
w(`  v_best numeric := null; v_brow int; v_bcol int;`)
w(`  v_blat numeric; v_blon numeric;`)
w(`  v_clat numeric; v_clon numeric;`)
w(`  v_nm numeric;`)
w(`  v_channel text;`)
w(`begin`)
w(`  select * into r from public.sea_raster where id = 1;`)
w(`  v_row := least(r.rows - 1, greatest(0, floor((90 - p_lat) / r.cell_deg)::int));`)
w(`  v_col := ((floor((p_lon + 180) / r.cell_deg)::int % r.cols) + r.cols) % r.cols;`)
w(`  if get_bit(r.cells, (v_row * r.cols + v_col) * r.bits_per_cell) = 1 then`)
w(`    -- Her own cell is sailable: the candidate is the quay itself, at zero distance (0076).`)
w(`    v_best := 0; v_brow := v_row; v_bcol := v_col; v_blat := p_lat; v_blon := p_lon;`)
w(`  else`)
w(`    for ring in 1 .. 12 loop`)
w(`      for dr in -ring .. ring loop`)
w(`        rr := v_row + dr;`)
w(`        continue when rr < 0 or rr >= r.rows;`)
w(`        for dc in -ring .. ring loop`)
w(`          continue when greatest(abs(dr), abs(dc)) <> ring;`)
w(`          cc := ((v_col + dc) % r.cols + r.cols) % r.cols;`)
w(`          if get_bit(r.cells, (rr * r.cols + cc) * r.bits_per_cell) = 1 then`)
w(`            v_clat := 90 - (rr + 0.5) * r.cell_deg;`)
w(`            v_clon := -180 + (cc + 0.5) * r.cell_deg;`)
w(`            v_nm := voyage.gc_distance_nm(p_lat::float8, p_lon::float8, v_clat::float8, v_clon::float8)::numeric;`)
w(`            if v_best is null or v_nm < v_best then`)
w(`              v_best := v_nm; v_blat := v_clat; v_blon := v_clon; v_brow := rr; v_bcol := cc;`)
w(`            end if;`)
w(`          end if;`)
w(`        end loop;`)
w(`      end loop;`)
w(`      exit when v_best is not null;`)
w(`    end loop;`)
w(`    if v_best is null then`)
w(`      -- 999 is 0047's own answer for "no water within 12 rings", kept so nothing changes here.`)
w(`      nm := 999; lat := null; lon := null; channel := null; return next; return;`)
w(`    end if;`)
w(`  end if;`)
w(`  -- 0085: was the winning cell DRY LAND that a channel carved open? Then the raster is the only`)
w(`  -- thing calling it water, and the roadstead lies on the channel itself, nearest the quay.`)
w(`  select c.id into v_channel from voyage.channels c`)
w(`   where c.carved_cells @> to_jsonb(v_brow * r.cols + v_bcol);`)
w(`  if v_channel is null then`)
w(`    nm := v_best; lat := v_blat; lon := v_blon; channel := null;`)
w(`  else`)
w(`    select f.nm, f.lat, f.lon into nm, lat, lon from voyage.channel_foot(v_channel, p_lat, p_lon) f;`)
w(`    channel := v_channel;`)
w(`  end if;`)
w(`  return next;`)
w(`end $wr$;`)
w(`revoke all on function voyage.water_roadstead(numeric, numeric) from public, anon, authenticated;`)
w()

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
  for (const r of reclaimed) {
    w(`--   (${r.lat.toFixed(3)}, ${r.lon.toFixed(3)}) was named sea when 0040 was cut and is LAND now — ${r.claim.id}.`)
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
w(`do $$`)
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
w(`  v_canal    text;`)
w(`  v_gc       numeric;`)
w(`  v_ayu_rlat numeric; v_ayu_rlon numeric;`)
w(`  v_tha_rlat numeric; v_tha_rlon numeric;`)
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
w(`  -- (d) EVERY ROADSTEAD IS A FIXED POINT OF THE RULE — asked of the raster and the channels`)
w(`  --     themselves rather than of the generator that wrote the column: its own cell is sailable`)
w(`  --     water and, since 0085, if that cell is one the carve opened, the point lies ON the`)
w(`  --     channel (a carved-cell point off the channel — the Kent centre — measures its distance`)
w(`  --     to the line here, and is refused).`)
w(`  select count(*) into v_bad from public.sea_reaches sr`)
w(`   where voyage.water_snap_nm(sr.roadstead_lat, sr.roadstead_lon) <> 0;`)
w(`  if v_bad <> 0 then`)
w(`    raise exception '${SHORT} self-assert FAIL: % roadstead(s) are not where the rule puts a roadstead — off sailable water, or in a carved cell but off its channel', v_bad;`)
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
w(`  -- and THE CHANNEL: exactly the places this run measured take their roadstead on a channel,`)
w(`  -- pinned to the measurement (${onChannel.length}) rather than to a floor a wrong table could clear.`)
w(`  select count(*) into v_n`)
w(`    from public.sea_reaches sr join public.ports p on p.id = sr.port_id`)
w(`   cross join lateral voyage.water_roadstead(p.lat, p.lon) wr`)
w(`   where wr.channel is not null;`)
w(`  if v_n <> ${onChannel.length} then`)
w(`    raise exception '${SHORT} self-assert FAIL: % place(s) take their roadstead on a channel; this run measured ${onChannel.length} (${onChannel.map((p) => p.code).join(' ')})', v_n;`)
w(`  end if;`)
w()
w(`  -- (p) THE CHANNELS TABLE IS THE AUTHORED LIST, WHOLE. ${CHANNELS.length} rows, ${carvedBy.size} carved cells between them,`)
w(`  --     no cell carved by two channels (or the rule would have two polylines to choose from), and`)
w(`  --     every carved cell reads WATER in the raster — the carve this table describes is the carve`)
w(`  --     the raster carries.`)
w(`  select count(*), coalesce(sum(opens_land), 0) into v_n, v_bad from voyage.channels;`)
w(`  if v_n <> ${CHANNELS.length} or v_bad <> ${carvedBy.size} then`)
w(`    raise exception '${SHORT} self-assert FAIL: voyage.channels holds % channel(s) opening % cell(s) of land; this run seeded ${CHANNELS.length} opening ${carvedBy.size}', v_n, v_bad;`)
w(`  end if;`)
w(`  select count(*) into v_bad from (`)
w(`    select x from voyage.channels c cross join lateral jsonb_array_elements(c.carved_cells) x`)
w(`     group by x having count(*) > 1) d;`)
w(`  if v_bad <> 0 then`)
w(`    raise exception '${SHORT} self-assert FAIL: % carved cell(s) belong to two channels — the roadstead rule needs one channel per cell', v_bad;`)
w(`  end if;`)
w(`  select * into r from public.sea_raster where id = 1;`)
w(`  select count(*) into v_bad`)
w(`    from voyage.channels c cross join lateral jsonb_array_elements_text(c.carved_cells) x`)
w(`   where get_bit(r.cells, x::int * r.bits_per_cell) <> 1;`)
w(`  if v_bad <> 0 then`)
w(`    raise exception '${SHORT} self-assert FAIL: % carved cell(s) read as LAND in the raster — voyage.channels describes a carve the raster does not carry', v_bad;`)
w(`  end if;`)
w()
w(`  -- (q) EVERY CHANNEL ROADSTEAD LIES ON ITS CHANNEL — the SQL half of the land proof. The`)
w(`  --     generator proved, over data/world-110m.json, that no off-quay roadstead sits inside a`)
w(`  --     coastline polygon unless a channel runs under it; this proves the "runs under it": the`)
w(`  --     seeded point is within 0.1 nm of the polyline (3-dp rounding is under 0.06 nm). Asked`)
w(`  --     over rows the FUNCTION calls channel rows, and the count is pinned above, so it is not`)
w(`  --     vacuous.`)
w(`  select count(*) into v_bad`)
w(`    from (select sr.roadstead_lat as rlat, sr.roadstead_lon as rlon, wr.channel`)
w(`            from public.sea_reaches sr join public.ports p on p.id = sr.port_id`)
w(`           cross join lateral voyage.water_roadstead(p.lat, p.lon) wr`)
w(`           where wr.channel is not null) x`)
w(`   cross join lateral voyage.channel_foot(x.channel, x.rlat, x.rlon) f`)
w(`   where f.nm > 0.1;`)
w(`  if v_bad <> 0 then`)
w(`    raise exception '${SHORT} self-assert FAIL: % channel roadstead(s) do not lie on their channel — a point off the polyline is a point the land data calls land', v_bad;`)
w(`  end if;`)
w()
w(`  -- (r) THE NAMED CONTROL: LONDON. The owner's example. Her roadstead lies on the Thames line`)
w(`  --     within 2 nm, her snap is between 0.5 and 15 nm, and it is NOT the cell centre 0079`)
w(`  --     seeded (51.375, -0.125), 8.11 nm into Kent — at least 5 nm from it.`)
w(`  select sr.snap_nm, sr.roadstead_lat, sr.roadstead_lon, wr.channel`)
w(`    into v_snap, v_lat, v_lon, v_ref`)
w(`    from public.sea_reaches sr join public.ports p on p.id = sr.port_id`)
w(`   cross join lateral voyage.water_roadstead(p.lat, p.lon) wr`)
w(`   where sr.code = ${q(LON.code)};`)
w(`  if v_snap is null then`)
w(`    raise exception '${SHORT} self-assert FAIL: ${LON.code} carries no roadstead, so the named control proves nothing';`)
w(`  end if;`)
w(`  if v_ref is distinct from 'thames-scheldt' then`)
w(`    raise exception '${SHORT} self-assert FAIL: ${LON.name} is reached from [%], not from the Thames channel', coalesce(v_ref, 'no channel');`)
w(`  end if;`)
w(`  if (select f.nm from voyage.channel_foot('thames-scheldt', v_lat, v_lon) f) > 2 then`)
w(`    raise exception '${SHORT} self-assert FAIL: ${LON.name}''s roadstead (%, %) lies more than 2 nm off the Thames line', v_lat, v_lon;`)
w(`  end if;`)
w(`  if v_snap < 0.5 or v_snap > 15 then`)
w(`    raise exception '${SHORT} self-assert FAIL: ${LON.name}''s roadstead is % nm off the quay — outside the 0.5 to 15 nm a Thames roadstead can be', v_snap;`)
w(`  end if;`)
w(`  if voyage.gc_distance_nm(v_lat::float8, v_lon::float8, 51.375, -0.125) < 5 then`)
w(`    raise exception '${SHORT} self-assert FAIL: ${LON.name}''s roadstead (%, %) is still the Kent cell centre 0079 seeded', v_lat, v_lon;`)
w(`  end if;`)
w()
w(`  -- (s) THE RIVER PORTS, pinned to this run's measurement (0.01 nm is snap_nm's own rounding):`)
w(`  --     Antwerp, Seville, Nantes and Bordeaux take a roadstead OFF the quay for the first time;`)
w(`  --     Bristol's quay is a vertex of the Severn channel, so hers stays the quay at 0 nm — the`)
w(`  --     rule applied to her too, and answered zero.`)
for (const code of ['ARP', 'SVQ', 'BRS', 'NAN', 'BOR']) {
  const rp = ports.find((x) => x.code === code)
  if (!rp) throw new Error(`no port ${code} for self-assert (s)`)
  const rr = roads.get(code)
  if (rr.channel === null) throw new Error(`${code} does not take a channel roadstead — the (s) control is mis-stated`)
  w(`  select sr.snap_nm, wr.channel into v_snap, v_ref`)
  w(`    from public.sea_reaches sr join public.ports p on p.id = sr.port_id`)
  w(`   cross join lateral voyage.water_roadstead(p.lat, p.lon) wr where sr.code = ${q(code)};`)
  w(`  if v_snap is null or abs(v_snap - ${rr.nm.toFixed(2)}) > 0.01 or v_ref is distinct from ${q(rr.channel)} then`)
  w(`    raise exception '${SHORT} self-assert FAIL: ${rp.name} is % nm off the quay on [%]; this run measured ${rr.nm.toFixed(2)} nm on ${rr.channel}', v_snap, coalesce(v_ref, 'no channel');`)
  w(`  end if;`)
}
w()
w(`  -- (t) POSITIVE CONTROL for (e) and (q): put ${LON.name}'s roadstead BACK where 0079 had it — the`)
w(`  --     Kent cell centre, with snap_nm re-measured so (b) still holds — and require the point`)
w(`  --     cross-check (e) AND the on-channel check (q) to each find it EXACTLY ONCE. Rolled back.`)
w(`  begin`)
w(`    update public.sea_reaches sr`)
w(`       set roadstead_lat = 51.375, roadstead_lon = -0.125,`)
w(`           snap_nm = round(voyage.gc_distance_nm(p.lat::float8, p.lon::float8, 51.375, -0.125)::numeric, 2)`)
w(`      from public.ports p where p.id = sr.port_id and sr.code = ${q(LON.code)};`)
w(`    select count(*) into v_bad`)
w(`      from public.sea_reaches sr join public.ports p on p.id = sr.port_id`)
w(`     cross join lateral voyage.water_roadstead(p.lat, p.lon) wr`)
w(`     where wr.lat <> sr.roadstead_lat or wr.lon <> sr.roadstead_lon;`)
w(`    if v_bad <> 1 then`)
w(`      raise exception '${SHORT} self-assert FAIL: ${LON.name}''s roadstead moved back to the Kent cell centre was found % time(s) by (e), expected exactly 1', v_bad;`)
w(`    end if;`)
w(`    select count(*) into v_bad`)
w(`      from (select sr.roadstead_lat as rlat, sr.roadstead_lon as rlon, wr.channel`)
w(`              from public.sea_reaches sr join public.ports p on p.id = sr.port_id`)
w(`             cross join lateral voyage.water_roadstead(p.lat, p.lon) wr`)
w(`             where wr.channel is not null) x`)
w(`     cross join lateral voyage.channel_foot(x.channel, x.rlat, x.rlon) f`)
w(`     where f.nm > 0.1;`)
w(`    if v_bad <> 1 then`)
w(`      raise exception '${SHORT} self-assert FAIL: ${LON.name}''s roadstead moved back to the Kent cell centre was found % time(s) by (q), expected exactly 1 — the on-channel check cannot bite', v_bad;`)
w(`    end if;`)
w(`    raise exception '__PROBE_ROLLBACK__' using errcode = 'P0001';`)
w(`  exception when others then`)
w(`    if sqlerrm <> '__PROBE_ROLLBACK__' then raise; end if;`)
w(`  end;`)
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
if (RECLAIMED.length > 0) {
w(`  -- (g2) THE CANAL THAT WAS NEVER DUG IS FILLED IN — this file's OWN headline.`)
w(`  -- (g) proves the isthmus of Panama, which 0076 closed and which this file must not reopen.`)
w(`  -- What THIS file changes is the Tenasserim isthmus, and a migration proves its own claim.`)
w(`  --`)
w(`  -- THREE THINGS, AND THE THIRD IS THE ONE THAT MATTERS TO A PLAYER:`)
w(`  --   1. every reclaimed cell reads as LAND in the raster and answers NO SEA — both rasters`)
w(`  --      moved, which is precisely what stopped the first attempt at this repair;`)
w(`  --   2. the straight line between the two roadsteads is refused E_LAND, so the short way`)
w(`  --      across the peninsula cannot be bought;`)
w(`  --   3. the table quotes the long way round, and it is quoted at the number this run`)
w(`  --      MEASURED rather than at a floor a wrong raster could also clear.`)
for (const r of reclaimed) {
w(`  if voyage.sea_at(${r.lat.toFixed(3)}, ${r.lon.toFixed(3)}) is not null then`)
w(`    raise exception '${SHORT} self-assert FAIL: (${r.lat.toFixed(3)}, ${r.lon.toFixed(3)}) still answers a sea — the membership raster was not reclaimed with the navigable one, and the two rasters disagree again';`)
w(`  end if;`)
}
w(`  select sr.roadstead_lat, sr.roadstead_lon into v_ayu_rlat, v_ayu_rlon`)
w(`    from public.sea_reaches sr where sr.code = ${q(AYU.code)};`)
w(`  select sr.roadstead_lat, sr.roadstead_lon into v_tha_rlat, v_tha_rlon`)
w(`    from public.sea_reaches sr where sr.code = ${q(THA.code)};`)
w(`  v_road_line := jsonb_build_array(jsonb_build_array(v_ayu_rlat, v_ayu_rlon),`)
w(`                                   jsonb_build_array(v_tha_rlat, v_tha_rlon));`)
w(`  v_canal := voyage.path_refusal(v_road_line, v_ayu_rlat, v_ayu_rlon, v_tha_rlat, v_tha_rlon,`)
w(`                                 public.wc_num('course_join_nm'), 25, 25);`)
w(`  if v_canal is null or v_canal not like 'E_LAND%' then`)
w(`    raise exception '${SHORT} self-assert FAIL: the line from the ${AYU.name} roads to the ${THA.name} roads is not refused as E_LAND (got %) — the canal through the Tenasserim mountains is still open', coalesce(v_canal, 'ACCEPTED');`)
w(`  end if;`)
w(`  -- AND THE TABLE AGREES WITH THE LAW. Pinned to the measurement, not to a floor: a raster that`)
w(`  -- closed the canal in the wrong place would clear any floor and still be wrong.`)
w(`  v_nm := (select (reaches->>${q(THA.code)})::numeric from public.sea_reaches where code = ${q(AYU.code)});`)
w(`  if v_nm is null or abs(v_nm - ${reaches.get(AYU.code).get(THA.code).toFixed(1)}) > 0.5 then`)
w(`    raise exception '${SHORT} self-assert FAIL: ${AYU.code}->${THA.code} is served at % nm; this run measured ${reaches.get(AYU.code).get(THA.code).toFixed(1)} nm the long way round', v_nm;`)
w(`  end if;`)
w(`  -- The positive control, and the whole point: it is FAR longer than the straight line. The`)
w(`  -- carved canal sold this pair 364.5 nm against a great circle of about 300 — a shortcut that`)
w(`  -- looked plausible precisely because it was near the direct distance.`)
w(`  v_gc := voyage.gc_distance_nm(v_ayu_rlat, v_ayu_rlon, v_tha_rlat, v_tha_rlon);`)
w(`  if v_nm < v_gc * 3 then`)
w(`    raise exception '${SHORT} self-assert FAIL: ${AYU.code}->${THA.code} sails % nm against a great circle of % — that is not around a peninsula, it is through one', v_nm, v_gc;`)
w(`  end if;`)
w()
}
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
// THE PRE-IMAGE COMPARISON BELONGS TO THE INTRODUCTION, and only to it. It reads the
// defs_before_NNNN temp table that the gate at the top of this file emits, and it asserts that
// world.snapshot did NOT serve a roadstead before and does now. On a LATER raster migration the
// table is never created and the hunk is already in the deployed body, so both halves are wrong:
// the read fails with `relation "defs_before_NNNN" does not exist` (42P01) and the pre-image
// assert would fail on its own terms even if it could run.
//
// The header promised that leaving the switch TRUE on a later run fails loudly rather than
// silently. It did — and the symmetrical case was missed: setting it FALSE, which is what a later
// run is FOR, failed just as loudly at the first attempt (0079, 2026-09-07). The switch now covers
// every line that belongs to the introduction, which is what it always claimed to do.
if (INTRODUCES_THE_ROADSTEAD) {
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
}
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
w(`     or has_function_privilege('authenticated', 'voyage.channel_foot(text, numeric, numeric)', 'execute')`)
w(`     or has_function_privilege('anon', 'voyage.channel_foot(text, numeric, numeric)', 'execute')`)
w(`     or has_table_privilege('authenticated', 'voyage.channels', 'select')`)
w(`     or has_table_privilege('anon', 'voyage.channels', 'select')`)
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
// THE RECEIPT LEADS WITH WHAT THIS RUN CHANGED. Everything after it is the permanent roadstead
// claim, re-proven on every raster migration; a file whose receipt only repeats its predecessor's
// headline is a file nobody can tell apart from a no-op.
const CANAL_HEADLINE = reclaimed.length === 0 ? '' :
  `THE CANAL THAT WAS NEVER DUG IS FILLED IN. `
  + `${RECLAIMED.map((r) => r.name).join(', ')}: ${reclaimed.length} cell(s) that public.sea_cells named as sea `
  + `— because 0040 was cut from a grid a malformed CHANNELS record had carved — are LAND again, in BOTH rasters, `
  + `and every one of them now answers no sea at all. The straight line from the ${AYU.name} roads to the `
  + `${THA.name} roads is refused E_LAND, and the table quotes ${reaches.get(AYU.code).get(THA.code).toFixed(1)} nm the long way round `
  + `against a great circle of about 300 — the carved canal sold that pair 364.5 nm, which is why it looked plausible. `
  + `309 real port pairs were being sold a route across the Malay peninsula; over all 28,203 pairs the repair moves `
  + `the median 0.00 nm and 94.6 per cent of pairs by under half a per cent. `
const lonRoad = roads.get(LON.code)
const CHANNEL_HEADLINE =
  `A ROADSTEAD LIES ON THE CHANNEL. ${onChannel.length} places snap to a cell the authored carve opened — sea in the raster, `
  + `land in data/world-110m.json — and every one of them now takes its roadstead ON the polyline of that channel, nearest the quay: `
  + `${LON.name} is reached from (${lonRoad.lat}, ${lonRoad.lon}) on the Thames, ${lonRoad.nm.toFixed(2)} nm off the quay, where 0079 seeded `
  + `(51.375, -0.125), 8.11 nm into Kent. ${moved.length} roadsteads move against the applied table; `
  + `${onChannel.filter((p) => appliedReaches.get(p.code)?.snap_nm === 0 && roads.get(p.code).nm > 0).length} river ports that were their own roadstead at 0 nm now carry one off the quay, `
  + `so their dotted line and ring exist for the first time (the quay at Bristol is itself a vertex of the Severn and stays at 0). `
  + `The land data itself was asked in the generator: ${landRed.length} off-quay roadsteads of the applied table stood inside a coastline polygon `
  + `(${landRed.join(' ')}); ${landGreen.length} do now unless a channel runs under them, and (q) proves each channel roadstead is on its line. `
w(`  raise notice '${SHORT} self-assert ok: ${CHANNEL_HEADLINE}${CANAL_HEADLINE}A HARBOUR IS REACHED FROM ITS ROADS. % places carry a roadstead; ${offQuay} of them lie off the quay (worst ${worst[0][0]} ${worst[0][1].toFixed(2)} nm, ${AMS.code} ${snapNm.get(AMS.code).toFixed(2)} nm) and ${ownWater} stand on their own water at 0 nm and ARE their own roadstead. Every one of them is on sailable water, every one is exactly snap_nm from its quay so the helper line the chart draws is the distance the table measured, and every one equals what voyage.water_roadstead answers for the same coordinate — the Node generator and the SQL rule are one rule now, because water_snap_nm''s body moved down into it. Collapsing one roadstead onto its quay is FOUND, exactly once. The isthmus: ${PAN.code} to ${POR.code} quay-to-quay is still ACCEPTED under the old snap+25 allowance (so the defect was real) and roads-to-roads is refused %, with the table now quoting % nm the long way round. A real house sailed ${LIS.code} to ${probe.code} — whose roadstead lies ${snapNm.get(probe.code).toFixed(2)} nm off her quay, further than the join tolerance, so nothing here would work from the quay — on a roadstead-to-roadstead course; her frozen path BEGAN at the ${LIS.code} roads, ENDED at the ${probe.code} roads, and voyage.settle — untouched — docked her at ${probe.code} itself: the owner''s sentence, proven. The land guard walks her, GRANDFATHERS a pre-0076 isthmus voyage a player would already have bought, and refuses the same course dated after this file. Every place still reaches every other symmetrically and never under the great circle between their roadsteads; the Arctic is shut (${LIS.code}->${NAG.code} % nm), there is no Suez and no Panama; ${CONTROLS.length} raster control cells read back through get_bit; 0 client write grants, 0 client-executable writers.',`)
w(`    v_ports, v_isthmus, (select (reaches->>${q(POR.code)})::numeric from public.sea_reaches where code = ${q(PAN.code)}),`)
w(`    (select (reaches->>${q(NAG.code)})::numeric from public.sea_reaches where code = ${q(LIS.code)});`)
w(`end $$;`)
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
