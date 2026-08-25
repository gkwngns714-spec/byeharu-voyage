// ═══════════════════════════════════════════════════════════════════════════════════════════════
// build-sea-migration.mjs — writes THE NAVIGABLE SEA, AS DATA. Currently migration 0052.
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
import { buildSeaGrid, COLS, ROWS, CELL_DEG, cellLat, cellLon, inIce } from './sea-grid.mjs'
import { packCells, findPath, floodFrom, floodPathTo, gcNm, navFromServed, SEA_BIT, POLAR_BIT } from '../src/lib/sea/index.ts'
import { applyChain, MIGRATIONS_DIR } from './db/apply-chain.mjs'

// The migration this run writes. 0046 was the first; an applied one is history, so this moves and
// the emitted SQL supersedes what the previous number seeded.
const MIGRATION = '20260818000052_the_severn_is_water_and_the_pack_is_one_rule.sql'
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

// A real proposed water path, as a client would send one: Lisbon→Cádiz round Cape St Vincent.
const lisCad = findPath(nav, LIS, CAD)
if (!lisCad) throw new Error('no Lisbon→Cádiz path — the raster is broken')
// …and the course this migration exists to make possible: Bristol→Amsterdam, down the Bristol
// Channel, round Land's End and up the Channel. Before the Severn opened, Bristol's own water lay
// 64.8 nm away in Lyme Bay, so her measured approach allowance was ~90 nm and the pathfinder's
// first leg was a STRAIGHT LINE from the quay across Somerset, Dorset and Hampshire to (50.63,
// -0.13): 324.7 nm to Amsterdam over dry England (measured 2026-08-25).
const brsAms = findPath(nav, BRS, AMS)
if (!brsAms) throw new Error('no Bristol→Amsterdam path — the Severn channel is broken')
const brsAmsNm = reaches.get(BRS.code).get(AMS.code)
console.log(`  the Severn fix: ${BRS.code} snaps ${snapNm.get(BRS.code).toFixed(2)} nm to water; ` +
            `${BRS.code}→${AMS.code} ${Math.round(brsAmsNm)} nm (the overland shortcut served 324.7)`)
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

const inland = [...snapNm.entries()].filter(([, nm]) => nm > 20).sort((a, b) => b[1] - a[1])
console.log(`  ${inland.length} places snap >20 nm to open water; worst: ` +
            inland.slice(0, 5).map(([c, n]) => `${c} ${Math.round(n)}`).join(', '))

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
const applied = navFromServed(
  (
    await db.query(`select cols, rows, cell_deg::float8 as cell_deg, bits_per_cell,
                           replace(encode(cells, 'base64'), e'\\n', '') as cells_base64
                      from public.sea_raster where id = 1`)
  ).rows[0],
)
let opened = 0
let closed = 0
for (let i = 0; i < COLS * ROWS; i++) {
  if (cells[i] && !applied.cells[i]) opened++
  else if (!cells[i] && applied.cells[i]) closed++
}
const appliedWater = applied.cells.reduce((n, c) => n + c, 0)
const newWater = cells.reduce((n, c) => n + c, 0)
console.log(`  raster diff vs the applied one: ${appliedWater} → ${newWater} water cells (+${opened} opened, -${closed} closed)`)

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
w(`-- ${SHORT} — THE SEVERN IS WATER, AND THE PACK IS ONE RULE`)
w(`--        Bristol stops sailing overland, and the Antarctic closure stops being a second`)
w(`--        authority written in a generator.`)
w(`-- ═══════════════════════════════════════════════════════════════════════════════════════════════`)
w(`--`)
w(`-- GENERATED by scripts/build-sea-migration.mjs — do not hand-edit. Change the sea (scripts/`)
w(`-- sea-grid.mjs) or the ports and cut a NEW migration; an applied one is history.`)
w(`--`)
w(`-- ── WHAT THIS SUPERSEDES ───────────────────────────────────────────────────────────────────────`)
w(`--   It SUPERSEDES THE DATA of 0046 (the water knows the way): public.sea_raster's one row is`)
w(`--   rewritten and public.sea_reaches is replaced wholesale. 0046 stays exactly as it applied —`)
w(`--   it is history, and editing it is the D23 defect.`)
w(`--   It supersedes NO FUNCTION and re-cuts none. voyage.path_nm and voyage.path_refusal are`)
w(`--   0046's and are untouched; voyage.sail_refusal belongs to 0050 now. A generator that`)
w(`--   re-emitted the bodies it remembered would silently roll 0050 back, so this file emits data.`)
w(`--   It also PATCHES ${seaPatch.size} row(s) of 0040's membership raster (public.sea_cells): the cells the`)
w(`--   Severn opens were land when 0040 was cut, and land carries no sea name. Each one joins the`)
w(`--   nearest named sea BY WATER — build-sea-raster.mjs's own rule for unnamed water, reused, not`)
w(`--   re-invented — and each is asserted by name below. Two rasters that could disagree about`)
w(`--   where the sea is would be the exact disease build-sea-raster's header names.`)
w(`--`)
w(`-- ── DEFECT 1: BRISTOL SAILED OVERLAND ──────────────────────────────────────────────────────────`)
w(`--   docs/DEV_LOG.md D22 flagged it and left it for the mover's worktree: "Bristol still reads`)
w(`--   english-channel at ring 4 … the honest fix is a Severn entry in sea-grid.mjs CHANNELS".`)
w(`--   It was worse than a wrong label. The Severn estuary is narrower than a 0.25° cell above`)
w(`--   Barry, so the whole Bristol Channel east of 4°W scan-filled as LAND, and Bristol's nearest`)
w(`--   sailable water was Lyme Bay — 64.8 nm away, over Devon, on the other coast of England.`)
w(`--   sea_reaches.snap_nm is what voyage.path_refusal grants a course as its head allowance, so`)
w(`--   Bristol carried a ~90 nm land-exempt corridor and the pathfinder used it: measured`)
w(`--   2026-08-25 on the old raster, BRS→AMS was 324.7 nm whose first leg ran STRAIGHT from the`)
w(`--   quay to (50.63, -0.13) across Somerset, Dorset and Hampshire; BRS→DUB 179.5 nm ran straight`)
w(`--   over the Welsh mountains. The owner's law (OWNER_REQUESTS row 41) is "i don't want the`)
w(`--   fleet to ever touch land."`)
w(`--   The Bristol Channel and the Avon are now a CHANNELS entry like the Thames and the Gironde —`)
w(`--   real navigable water Bristol's ships worked to King Road and seven miles up to the quay.`)
w(`--   MEASURED, this raster against the last one:`)
w(`--     Bristol's snap        64.55 nm (Lyme Bay, English Channel)  →  ${snapNm.get(BRS.code).toFixed(2)} nm (her own cell)`)
w(`--     the sea she answers   english-channel at ring 4             →  her own declared sea, at ring 0`)
w(`--     BRS→AMS               324.7 nm over England                 →  ${Math.round(brsAmsNm).toLocaleString('en')} nm round Land's End`)
w(`--     water cells           ${appliedWater.toLocaleString('en')}  →  ${newWater.toLocaleString('en')}  (+${opened} opened, -${closed} closed)`)
w(`--`)
w(`-- ── DEFECT 2: THE ANTARCTIC CLOSURE WAS A SECOND AUTHORITY ─────────────────────────────────────`)
w(`--   scripts/sea-grid.mjs holds ICE, "the inverse authority of CHANNELS: named waters CLOSED by`)
w(`--   hand", with a historical justification per closure. It could only express a NORTHERN`)
w(`--   parallel, so the Antarctic pack lived in the generator instead as`)
w(`--   \`if (cellLat(row) < -60) cells.fill(0, …)\`, and the generator's cross-check then repeated`)
w(`--   the same −60 a third time to know which closed water was allowed to carry a sea name. One`)
w(`--   concept, three statements (docs/NO_SPAGHETTI.md: one authority per concept).`)
w(`--   ICE now takes \`latBelow\` beside \`latAbove\` and the Antarctic pack is a row in it. THE WATER`)
w(`--   DID NOT MOVE: the closure is the same parallel and 0 cells differ from the old rule.`)
w(`--   Why 60°S, from the dates and not from taste: the southernmost land seen by the end of this`)
w(`--   game's century was South Georgia (54°S, 1675); the South Shetlands at 62°S were not sighted`)
w(`--   until 1819, the Antarctic Circle not crossed until Cook in 1773, the continent not seen`)
w(`--   until 1820. Everything the age of sail worked stays open and MEASURED UNCHANGED here:`)
w(`--     Cape Horn and the Drake Passage   VER→ACA ${Math.round(verAcaNm).toLocaleString('en')} nm, rounding through 55.63°S`)
w(`--     the Horn again, from the east     Buenos Aires→Callao 4,251.9 nm, also through 55.63°S`)
w(`--     the Roaring Forties               Rio de Janeiro→Manila 9,919.0 nm, riding 43.9°S`)
w(`--     the Cape of Good Hope             Cape Town→Jakarta 5,244.8 nm, Valparaiso→Cape Town 5,228.7 nm`)
w(`--   Every one of those four is identical to 0.1 nm before and after. The closure is asserted`)
w(`--   from BOTH sides below: 59°S open water, 61°S ice.`)
w(`--`)
w(`-- ── THE CONSEQUENCE, STATED FOR THE BALANCE SLICE ──────────────────────────────────────────────`)
w(`--   Sailed distances price trade. ${opened} water cell(s) opened and ${closed} closed, so only routes THROUGH the Bristol`)
w(`--   Channel move, and they move UP — Bristol was cheating. Bristol's reaches rise by 41 to 293 nm`)
w(`--   on the short British and North Sea runs; nothing else in the table changes. The canal and`)
w(`--   Arctic controls are unmoved: ${LIS.code}→${NAG.code} ${Math.round(lisNagNm).toLocaleString('en')} nm, ${ALX.code}→${ADE.code} ${Math.round(alxAdeNm).toLocaleString('en')} nm, ${VER.code}→${ACA.code} ${Math.round(verAcaNm).toLocaleString('en')} nm.`)
w(`--`)
w(`-- Depends on: 0002 (ports, seas, gc_distance_nm), 0040 (sea_cells, voyage.sea_at), 0046 (the two`)
w(`-- tables and voyage.path_nm / voyage.path_refusal), and the port rows of 0003/0036/0041.`)
w(`-- ═══════════════════════════════════════════════════════════════════════════════════════════════`)
w()
w(`-- ── The raster, superseding 0046's ─────────────────────────────────────────────────────────────`)
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
w(`-- ── The sailed distances, superseding 0046's ───────────────────────────────────────────────────`)
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
w(`  v_snap     numeric;`)
w(`  v_lis_cad  constant jsonb := ${j(pathJson(lisCad.path))}::jsonb;`)
w(`  v_brs_ams  constant jsonb := ${j(pathJson(brsAms.path))}::jsonb;`)
w(`  -- the course the OLD raster served: Bristol straight across southern England to the Channel,`)
w(`  -- then on to Amsterdam. It must now be refused as land.`)
w(`  v_overland constant jsonb := ${j([[BRS.lat, BRS.lon], [50.63, -0.13], [50.63, 0.63], [AMS.lat, AMS.lon]])}::jsonb;`)
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
w(`  -- (a3) BRISTOL ANSWERS HER OWN DECLARED SEA, AT HER OWN COORDINATE. Before this file her cell`)
w(`  --      was land and the ring search walked four rings across Devon to the English Channel.`)
w(`  if voyage.sea_at(${BRS.lat}, ${BRS.lon}) is distinct from (select sea_id from public.ports where code = ${q(BRS.code)}) then`)
w(`    raise exception '${SHORT} self-assert FAIL: Bristol (${BRS.lat}, ${BRS.lon}) answers [%] and not her declared sea [%]',`)
w(`      coalesce((select name from public.seas where id = voyage.sea_at(${BRS.lat}, ${BRS.lon})), 'null'),`)
w(`      (select s.name from public.ports p join public.seas s on s.id = p.sea_id where p.code = ${q(BRS.code)});`)
w(`  end if;`)
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
w(`  -- (f) THE SEVERN, AS A RULE ABOUT THE SERVED NUMBERS. Bristol's approach is a river approach`)
w(`  --     now, not a walk across a peninsula, and the North Sea run is the long way round because`)
w(`  --     there is no short way.`)
w(`  select snap_nm into v_snap from public.sea_reaches where code = ${q(BRS.code)};`)
w(`  if v_snap is null or v_snap > 20 then`)
w(`    raise exception '${SHORT} self-assert FAIL: Bristol snaps % nm to sailable water — over 20 means the Severn is land again and her courses get that much of a land-exempt head allowance (it was 64.55 nm to Lyme Bay)', v_snap;`)
w(`  end if;`)
w(`  v_nm := (select (reaches->>${q(AMS.code)})::numeric from public.sea_reaches where code = ${q(BRS.code)});`)
w(`  if v_nm is null or v_nm < 500 then`)
w(`    raise exception '${SHORT} self-assert FAIL: ${BRS.code}→${AMS.code} is % nm — under 500 means the overland shortcut across southern England is back (it served 324.7)', v_nm;`)
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
w(`  raise notice '${SHORT} self-assert ok: the sea is one raster (${COLS}x${ROWS}, % bytes, ${CONTROLS.length} named control cells read back through get_bit, the Antarctic closure pinned open at 59S and shut at 61S); the Severn is water, so Bristol snaps % nm instead of 64.55 to Lyme Bay, answers her own declared sea at ring 0, and sails % nm to ${AMS.name} round Land''s End where the overland course served 324.7 — that course is now refused as E_LAND with her own allowance; every one of % places reaches every other with a symmetric sailed distance never under the great circle; the Arctic stays closed (${LIS.code}→${NAG.code} % nm) and there is still no Suez and no Panama (${ALX.code}→${ADE.code} ${Math.round(alxAdeNm)} nm, ${VER.code}→${ACA.code} ${Math.round(verAcaNm)} nm); ${healed.length} newly opened cell(s) answer their sea by name; 0 client write grants',`)
w(`    octet_length(r.cells),`)
w(`    (select round(snap_nm, 2) from public.sea_reaches where code = ${q(BRS.code)}),`)
w(`    (select (reaches->>${q(AMS.code)})::numeric from public.sea_reaches where code = ${q(BRS.code)}),`)
w(`    v_ports,`)
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
