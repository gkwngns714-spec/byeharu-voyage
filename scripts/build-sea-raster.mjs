// ═══════════════════════════════════════════════════════════════════════════════════════════════
// THE SEA RASTER — every water cell of the 0.25° grid answers WHICH SEA IT IS IN.
// Writes migration 0040. Run:  node scripts/build-sea-raster.mjs [--png <dir>]
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// ── THE FOUR DECISIONS (NO_SPAGHETTI §7B), ANSWERED BEFORE THE CODE ────────────────────────────
//
// 1. WHAT CONCEPT? — "which named sea a point of water belongs to." One noun phrase, one output:
//    a sea ordinal per 0.25° cell, total over every water cell the game can reach.
//
// 2. WHERE DOES IT LIVE, AND WHY THERE? — public.sea_cells + public.seas.raster_ordinal, seeded
//    by the generated migration this script writes. `public`, because it is world reference data
//    exactly like `seas`, `ports` and `goods` (PLATFORM §5 q2: public = the world's reference
//    tables; voyage = time and motion; cmd = writes). The lookup, voyage.sea_at(lat, lon), lives
//    in `voyage` beside voyage.gc_distance_nm: it is a geometry read the SEA-side rules compose.
//    The client re-derives NOTHING: in local mode it runs this same chain; a cloud-facing read
//    (map labels) is a 3-line world.* + registry + catalog slice the day a screen wants one.
//
// 3. WHO IS THE SECOND CALLER? — three are already on the schedule, which is why this exists
//    BEFORE free sailing ships rather than after: the free-water mover's hazard sampling (a path
//    with no ports in the middle still needs seas.hazard_base / piracy_index), NPC placement by
//    sea with levels (OWNER_REQUESTS row 43 — danger keyed to WHERE, never to WHEN), and the
//    hazard/disaster system's "a storm has somewhere to be".
//
// 4. WHAT WOULD MAKE IT THE WRONG SHAPE, AND HOW DOES ANYONE FIND OUT? — if a rule ever needs
//    sub-cell boundaries (a strait narrower than 15 nm deciding jurisdiction), a 0.25° byte grid
//    is too coarse — the tell is somebody special-casing coordinates around a boundary instead of
//    reading the raster. And if a second sea raster ever appears (the mover ships a WATER raster;
//    water and sea-membership must stay byte-consistent: ordinal > 0 on exactly the navigable
//    cells), fold them into one table in that slice — two rasters that can disagree about where
//    the sea is would be the exact byeharu disease.
//
// ── WHERE THE BOUNDARIES COME FROM — sourced, not invented ─────────────────────────────────────
// Natural Earth's marine polygons (ne_10m_geography_marine_polys, public domain — the same
// project, author and licence as the coastline in data/world-110m.json). data/seas.json's own
// note says its centroids are hand-placed label anchors, "NOT surveyed" — so a Voronoi over them
// would put the Channel boundary in visibly wrong places. Instead, each of the 51 seas takes its
// REAL surveyed extent from the NE polygon(s) bearing its name (49 exact name matches; NE spells
// "INDIAN OCEAN" in caps and calls the Seto Inland Sea "Inner Sea" — both aliased below, nothing
// else authored). Water NE names that we do not model (Celtic Sea, Hudson Bay, Gulf of Bothnia,
// SOUTHERN OCEAN, …) is NOT guessed at: it joins the nearest named sea BY WATER — a multi-source
// BFS through water cells, so the Gulf of Bothnia grows out of the Baltic and can never leak
// across an isthmus. The slimmed polygon set is cached at scripts/marine-polys.cache.json with
// full provenance, so regeneration is offline after the first run.
//
// The WATER itself — cells, forced-open channels, ice — is scripts/sea-grid.mjs, unchanged: ONE
// authority for what is sailable, this file only says what the sailable water is called.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { readFileSync, writeFileSync, existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'
import { deflateSync } from 'node:zlib'
import {
  buildSeaGrid, CELL_DEG, COLS, ROWS, rowOf, colOf, cellLat, cellLon, gcNm,
} from './sea-grid.mjs'

const HERE = dirname(fileURLToPath(import.meta.url))
const ROOT = join(HERE, '..')
const DATA = join(ROOT, 'data')
const CACHE = join(HERE, 'marine-polys.cache.json')
const MIGRATION = join(ROOT, 'supabase', 'migrations', '20260818000040_every_water_answers_its_sea.sql')
const NE_URL = 'https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_geography_marine_polys.geojson'

// The only authored naming: NE's two spellings that differ from ours.
const NE_ALIASES = { 'indian ocean': 'indian-ocean', 'inner sea': 'seto-inland-sea' }

// ── THE FOLDS — NE-named waters we do not model, assigned WHOLESALE to one of our seas ─────────
// BFS would split each of these along an arbitrary equidistance seam; for these six the seam is
// VISIBLE and the whole feature plainly belongs to one neighbour, so the fold is authored and the
// reason recorded. Everything else NE names (Hudson Bay, Gulf of Bothnia, Sea of Okhotsk, Bering
// Sea, …) still joins by water-BFS, where the seam is either correct or out at sea where no rule
// and no player can see it.
const NE_FOLDS = {
  // The strait is the Mediterranean's doorway: Tangier, Ceuta and Gibraltar are all filed under
  // the Med in data/ports.json (WORLD_DATA §6 records that filing as deliberate), and the sea
  // place "Strait of Gibraltar" declares mediterranean-sea. The water agrees with the ports.
  'strait of gibraltar': 'mediterranean-sea',
  // The Mediterranean must BEGIN at Gibraltar: without this fold the Atlantic BFS wavefront pours
  // through the strait and claims the western Alboran, putting the Atlantic/Med seam mid-basin —
  // the exact "boundary in a visibly wrong place" this generator exists to prevent.
  'alboran sea': 'mediterranean-sea',
  // Same shape: the Bosporus is Istanbul's own water and Istanbul declares the Sea of Marmara.
  // Without this the forced-open channel cells BFS-fill from the Black Sea side.
  'bosporus': 'sea-of-marmara',
  // The Bristol Channel is the Atlantic's arm, not the English Channel's: without the fold the
  // English Channel wavefront wins the race round Land's End and Bristol reads "English Channel",
  // which a player who knows the water would rightly call wrong.
  'bristol channel': 'north-atlantic',
  // Svalbard's whaling grounds: the ports there (Longyearbyen) are filed under the Arctic, and
  // "Arctic Ocean" is the right name for that water in this game's vocabulary.
  'greenland sea': 'arctic-ocean',
  // Off Queensland, "Tasman Sea" would be visibly wrong; the open Pacific is the honest parent.
  'coral sea': 'south-pacific',
  // The ring around Antarctica: split by the IHO ocean-sector meridians (20°E Cape Agulhas,
  // 146°55'E South East Cape, 67°16'W Cape Horn) rather than by a BFS race no atlas would draw.
  'southern ocean': '@southern',
}
const SOUTHERN_SECTOR = (lon) =>
  lon < -67.2667 ? 'south-pacific'
  : lon < 20 ? 'south-atlantic'
  : lon < 146.9167 ? 'indian-ocean'
  : 'south-pacific'

// Straits NARROWER THAN A CELL: their polygon contains no cell centre, so scanline fill paints
// nothing — the same reason sea-grid.mjs needs its CHANNELS. Their fold is painted by sampling
// along the polygon's own rings instead (every ~4 nm), onto water cells only.
const NARROW_FOLDS = new Set(['Strait of Gibraltar', 'Bosporus'])

const seasFile = JSON.parse(readFileSync(join(DATA, 'seas.json'), 'utf8'))
const SEAS = seasFile.seas // ARRAY ORDER IS THE ORDINAL: 1-based position = raster byte value.
const portsFile = JSON.parse(readFileSync(join(DATA, 'ports.json'), 'utf8'))
const placesFile = JSON.parse(readFileSync(join(DATA, 'sea-places.json'), 'utf8'))

// ── 1. the marine polygons, slimmed to the features we name ────────────────────────────────────
async function loadMarine() {
  if (existsSync(CACHE)) return JSON.parse(readFileSync(CACHE, 'utf8'))
  console.log(`cache missing — fetching ${NE_URL}`)
  const res = await fetch(NE_URL)
  if (!res.ok) throw new Error(`Natural Earth fetch failed: ${res.status}`)
  const fc = await res.json()
  const wanted = new Map() // lowercased NE name -> our sea id (or @southern)
  for (const s of SEAS) wanted.set(s.name.toLowerCase(), s.id)
  for (const [ne, id] of Object.entries(NE_ALIASES)) wanted.set(ne, id)
  for (const [ne, id] of Object.entries(NE_FOLDS)) wanted.set(ne, id)
  const features = []
  for (const f of fc.features) {
    const id = wanted.get((f.properties.name ?? '').toLowerCase())
    if (id) features.push({ sea: id, neName: f.properties.name, geometry: f.geometry })
  }
  const cache = {
    $doc: '../docs/WORLD_DATA.md §9',
    provenance: {
      dataset: 'Natural Earth 1:10m Geography Marine Polygons (ne_10m_geography_marine_polys)',
      url: NE_URL,
      licence: 'Public domain — naturalearthdata.com/about/terms-of-use',
      fetchedAt: new Date().toISOString(),
      transform: 'kept only features whose name matches a data/seas.json sea (case-insensitive, '
        + 'plus the two aliases in scripts/build-sea-raster.mjs); geometry byte-for-byte',
    },
    features,
  }
  writeFileSync(CACHE, JSON.stringify(cache))
  return cache
}

// ── 2. scan-fill a polygon feature onto the grid (even-odd, same rule as sea-grid.mjs) ────────
function fillFeature(geometry, paint) {
  const polys = geometry.type === 'Polygon' ? [geometry.coordinates] : geometry.coordinates
  for (const rings of polys) {
    let minLat = 90, maxLat = -90
    for (const ring of rings) for (const [, lat] of ring) {
      if (lat < minLat) minLat = lat
      if (lat > maxLat) maxLat = lat
    }
    for (let row = rowOf(maxLat); row <= rowOf(minLat); row++) {
      const lat = cellLat(row)
      const xs = []
      for (const ring of rings) {
        for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
          const [x1, y1] = ring[j]
          const [x2, y2] = ring[i]
          if (y1 > lat !== y2 > lat) xs.push(x1 + ((lat - y1) / (y2 - y1)) * (x2 - x1))
        }
      }
      xs.sort((a, b) => a - b)
      for (let k = 0; k + 1 < xs.length; k += 2) {
        // NE rings never wrap the antimeridian (CRS84, clipped at ±180), so fill in lon space.
        const c1 = Math.max(0, Math.ceil((xs[k] + 180) / CELL_DEG - 0.5))
        const c2 = Math.min(COLS - 1, Math.floor((xs[k + 1] + 180) / CELL_DEG - 0.5))
        for (let c = c1; c <= c2; c++) paint(row, c)
      }
    }
  }
}

// ── 3. assign: polygons first (small overrides large), then BFS through water ─────────────────
function assign(water, marine) {
  // Merge features by sea id; measure each sea's painted footprint first so that where NE
  // polygons brush against each other, the SMALLER named water wins the cell (a gulf beats an
  // ocean at their shared boundary).
  const bySea = new Map()
  const southern = []
  for (const f of marine.features) {
    if (f.sea === '@southern') { southern.push(f.geometry); continue }
    if (!bySea.has(f.sea)) bySea.set(f.sea, [])
    bySea.get(f.sea).push(f.geometry)
  }
  const ordinalOf = new Map(SEAS.map((s, i) => [s.id, i + 1]))
  const footprint = []
  for (const [sea, geoms] of bySea) {
    let n = 0
    for (const g of geoms) fillFeature(g, () => { n++ })
    footprint.push([sea, n])
  }
  footprint.sort((a, b) => b[1] - a[1]) // big first; later (smaller) paints override
  const grid = new Uint8Array(COLS * ROWS)
  // The Southern Ocean first — by IHO sector meridian — so every named sea paints over it.
  for (const g of southern) {
    fillFeature(g, (row, col) => { grid[row * COLS + col] = ordinalOf.get(SOUTHERN_SECTOR(cellLon(col))) })
  }
  for (const [sea] of footprint) {
    const ord = ordinalOf.get(sea)
    for (const g of bySea.get(sea)) fillFeature(g, (row, col) => { grid[row * COLS + col] = ord })
  }
  // The narrow strait folds — painted by ring sampling, since scanline finds no cell centre.
  for (const f of marine.features) {
    if (!NARROW_FOLDS.has(f.neName)) continue
    const ord = ordinalOf.get(f.sea)
    const polys = f.geometry.type === 'Polygon' ? [f.geometry.coordinates] : f.geometry.coordinates
    for (const rings of polys) for (const ring of rings) {
      for (let i = 0; i + 1 < ring.length; i++) {
        const [x1, y1] = ring[i]
        const [x2, y2] = ring[i + 1]
        const steps = Math.max(1, Math.ceil(gcNm(y1, x1, y2, x2) / 4))
        for (let s = 0; s <= steps; s++) {
          const lat = y1 + ((y2 - y1) * s) / steps
          const lon = x1 + ((x2 - x1) * s) / steps
          const ni = rowOf(lat) * COLS + colOf(lon)
          if (water[ni] === 1) grid[ni] = ord
        }
      }
    }
  }

  // Mask to water: land keeps 0 whatever a polygon said.
  let assigned = 0, waterCells = 0
  for (let i = 0; i < grid.length; i++) {
    if (water[i] !== 1) { grid[i] = 0; continue }
    waterCells++
    if (grid[i] > 0) assigned++
  }
  console.log(`water cells ${waterCells}; named by NE polygon ${assigned}`)

  // Multi-source BFS through water: unnamed water joins the nearest named sea BY WATER.
  // 4-neighbour first (cannot leak diagonally across an isthmus), then an 8-neighbour sweep for
  // cells only diagonally attached (the A* mover moves diagonally, so they are reachable water).
  const ORTHO = [[-1, 0], [1, 0], [0, -1], [0, 1]]
  const ALL8 = [...ORTHO, [-1, -1], [-1, 1], [1, -1], [1, 1]]
  for (const neigh of [ORTHO, ALL8]) {
    const queue = new Int32Array(waterCells + 8)
    let head = 0, tail = 0
    for (let i = 0; i < grid.length; i++) if (grid[i] > 0) queue[tail++] = i
    while (head < tail) {
      const cur = queue[head++]
      const row = Math.floor(cur / COLS), col = cur % COLS
      for (const [dr, dc] of neigh) {
        const nrow = row + dr
        if (nrow < 0 || nrow >= ROWS) continue
        const ncol = ((col + dc) % COLS + COLS) % COLS
        const ni = nrow * COLS + ncol
        if (water[ni] !== 1 || grid[ni] > 0) continue
        grid[ni] = grid[cur]
        queue[tail++] = ni
      }
    }
  }
  let unassigned = 0
  for (let i = 0; i < grid.length; i++) if (water[i] === 1 && grid[i] === 0) unassigned++
  console.log(`after BFS: unassigned water cells ${unassigned} (disconnected from every named sea)`)
  return { grid, waterCells, unassigned }
}

// ── 4. what stayed unassigned — name the components so the report can say why ─────────────────
function unassignedComponents(water, grid) {
  const seen = new Uint8Array(COLS * ROWS)
  const out = []
  for (let i = 0; i < grid.length; i++) {
    if (water[i] !== 1 || grid[i] !== 0 || seen[i]) continue
    let size = 0
    let latSum = 0, lonSum = 0
    const stack = [i]
    seen[i] = 1
    while (stack.length) {
      const cur = stack.pop()
      size++
      const row = Math.floor(cur / COLS), col = cur % COLS
      latSum += cellLat(row); lonSum += cellLon(col)
      for (const [dr, dc] of [[-1, 0], [1, 0], [0, -1], [0, 1], [-1, -1], [-1, 1], [1, -1], [1, 1]]) {
        const nrow = row + dr
        if (nrow < 0 || nrow >= ROWS) continue
        const ncol = ((col + dc) % COLS + COLS) % COLS
        const ni = nrow * COLS + ncol
        if (water[ni] === 1 && grid[ni] === 0 && !seen[ni]) { seen[ni] = 1; stack.push(ni) }
      }
    }
    out.push({ size, lat: +(latSum / size).toFixed(1), lon: +(lonSum / size).toFixed(1) })
  }
  return out.sort((a, b) => b.size - a.size)
}

// ── 5. reconcile: every port's declared sea vs the cell it sits in ────────────────────────────
// Mirrors the SQL self-assert EXACTLY: coordinates rounded to 2 dp (the ports table's numeric
// precision), then the first cell with an ordinal > 0 in ring order 0..8.
function resolveAt(grid, lat, lon) {
  const r0 = rowOf(lat), c0 = colOf(lon)
  for (let ring = 0; ring <= 8; ring++) {
    for (let dr = -ring; dr <= ring; dr++) {
      for (let dc = -ring; dc <= ring; dc++) {
        if (Math.max(Math.abs(dr), Math.abs(dc)) !== ring) continue
        const row = r0 + dr
        if (row < 0 || row >= ROWS) continue
        const col = ((c0 + dc) % COLS + COLS) % COLS
        const ord = grid[row * COLS + col]
        if (ord > 0) return { ord, ring }
      }
    }
  }
  return null
}

/**
 * The ports the CHAIN holds at position 0040: 0003's harbours plus 0036's sea places. ports.json
 * may run AHEAD of the chain (it does today: 10 island ports await their own seeding slice), and
 * 0040's self-assert replays at its own chain position for ever — so the assert's expected list is
 * filtered to what the table actually holds there, while the report still covers everything.
 */
function chainPortKeys() {
  const sql = readFileSync(join(ROOT, 'supabase', 'migrations',
    '20260818000003_the_real_world_and_the_water_between_it.sql'), 'utf8')
  const keys = new Set()
  for (const m of sql.matchAll(/^\s*\('[A-Z]{3}', '((?:[^']|'')*)', '((?:[^']|'')*)', /gm)) {
    keys.add(`${m[1].replaceAll("''", "'")}/${m[2].replaceAll("''", "'")}`)
  }
  for (const p of placesFile.places) keys.add(`${p.name}/High seas`)
  return keys
}

function reconcile(grid) {
  const round2 = (x) => Math.round(x * 100) / 100
  const entries = [
    ...portsFile.ports.map((p) => ({
      key: `${p.name}/${p.countryName}`, lat: round2(p.lat), lon: round2(p.lon), declared: p.sea,
    })),
    ...placesFile.places.map((p) => ({
      key: `${p.name}/High seas`, lat: round2(p.lat), lon: round2(p.lon), declared: p.sea,
    })),
  ]
  const inChain = chainPortKeys()
  const aheadOfChain = entries.filter((e) => !inChain.has(e.key)).map((e) => e.key)
  const disagreements = []
  const unresolved = []
  for (const e of entries) {
    const r = resolveAt(grid, e.lat, e.lon)
    if (!r) { unresolved.push(e.key); continue }
    const resolvedSea = SEAS[r.ord - 1].id
    if (resolvedSea !== e.declared) {
      disagreements.push({
        key: e.key, declared: e.declared, resolved: resolvedSea, ring: r.ring,
        inChain: inChain.has(e.key),
      })
    }
  }
  return { total: entries.length, inChainTotal: entries.length - aheadOfChain.length, aheadOfChain, disagreements, unresolved }
}

// ── 6. the migration ──────────────────────────────────────────────────────────────────────────
function sqlQ(s) { return `'${String(s).replace(/'/g, "''")}'` }

function writeMigration(grid, recon, waterCells, unassigned, componentsNote) {
  const L = []
  const w = (s = '') => L.push(s)
  const seaByName = new Map(SEAS.map((s, i) => [s.name, { ...s, ord: i + 1 }]))

  w('-- ═══════════════════════════════════════════════════════════════════════════════════════════════')
  w('-- 0040 — EVERY WATER ANSWERS ITS SEA')
  w('--        A sea-membership raster on the same 0.25° grid as the water itself: every navigable')
  w('--        cell carries the ordinal of the sea it is in, so a fleet at ANY water point still has')
  w('--        a region — the thing piracy, hazards and the by-sea NPC design (OWNER_REQUESTS row 43)')
  w('--        are keyed on, and the thing free sailing would otherwise silently switch off.')
  w('--        GENERATED by scripts/build-sea-raster.mjs — do not hand-edit; edit the data or the')
  w('--        generator and run it again. Boundaries are Natural Earth ne_10m_geography_marine_polys')
  w('--        (public domain, same source family as the coastline), NOT the hand-placed label')
  w('--        centroids of data/seas.json, which its own note marks unsurveyed. Water bearing an NE')
  w('--        name we do not model joins the nearest named sea BY WATER (BFS through water cells),')
  w('--        so nothing leaks across land. §7B decisions are in the generator header.')
  w('-- ═══════════════════════════════════════════════════════════════════════════════════════════════')
  w('--')
  w(`-- THE NUMBERS, from this generation: ${waterCells} water cells; ${waterCells - unassigned} carry a sea;`)
  w(`-- ${unassigned} do not — ${componentsNote}`)
  const chainDis = recon.disagreements.filter((d) => d.inChain)
  w(`-- Ports checked against their cell: ${recon.total} in the data, ${recon.inChainTotal} in the chain at`)
  w(`-- this position (${recon.aheadOfChain.length} island ports in data/ports.json await their own seeding slice);`)
  w(`-- disagreements with the declared sea among the chain's ports: ${chainDis.length}`)
  w('-- (each one asserted below BY NAME — a silent drift of this list is a red apply).')
  w('--')
  w('-- Depends on: 0002 (public.seas, public.ports), 0003 (the seed), 0036 (SEA_PLACE rows).')
  w('')
  w('-- ── 1. the seas learn their ordinal, their danger tier and their character ────────────────────')
  w('-- raster_ordinal: the byte value of this sea in public.sea_cells. 1-based position in')
  w('-- data/seas.json array order, which is append-only (the seas.json note says so).')
  w('-- danger_level: the authored WHERE-keyed threat tier (1 home waters … 5 deadly) the owner')
  w("-- specified for NPC encounters — \"different npcs in different areas of the sea - different")
  w('-- levels\". READ BY NO RULE TODAY (2026-08-24): named readers are the NPC/encounter system')
  w('-- (OWNER_REQUESTS row 43) and any level-gated hazard content. Stated plainly, the takes_effect')
  w('-- discipline of 0015/0016: an authored field nothing reads yet is marked, never implied live.')
  w('-- note: the sea\'s character in plain words — a NAME, not a sentence (UI_DIRECTION). Same')
  w('-- posture: no rule reads it yet; the map label / compendium is its named reader.')
  w('alter table public.seas')
  w('  add column raster_ordinal smallint,')
  w('  add column danger_level   int,')
  w('  add column note           text;')
  w('')
  for (const s of SEAS) {
    const e = seaByName.get(s.name)
    w(`update public.seas set raster_ordinal = ${e.ord}, danger_level = ${s.danger}, note = ${sqlQ(s.note)} where name = ${sqlQ(s.name)};`)
  }
  w('')
  w('alter table public.seas')
  w('  alter column raster_ordinal set not null,')
  w('  alter column danger_level   set not null,')
  w('  alter column note           set not null,')
  w('  add constraint seas_raster_ordinal_unique unique (raster_ordinal),')
  w('  add constraint seas_raster_ordinal_band   check (raster_ordinal between 1 and 255),')
  w('  add constraint seas_danger_level_band     check (danger_level between 1 and 5),')
  w('  add constraint seas_note_is_a_name        check (length(note) between 3 and 60);')
  w('')
  w("comment on column public.seas.raster_ordinal is 'This sea''s byte value in public.sea_cells. Append-only: data/seas.json array order.';")
  w("comment on column public.seas.danger_level is 'Authored WHERE-keyed threat tier, 1 (home waters) to 5 (deadly). READ BY NO RULE TODAY (2026-08-24) — named reader: the by-sea NPC/encounter system, OWNER_REQUESTS row 43. The takes_effect discipline: marked until something reads it.';")
  w("comment on column public.seas.note is 'The sea''s character in plain words. READ BY NO RULE TODAY (2026-08-24) — named reader: map labels / the compendium.';")
  w('')
  w('-- ── 2. the raster: 720 rows of 1,440 bytes, one byte per cell ─────────────────────────────────')
  w('-- Row r covers latitude (90 - 0.25*(r+1), 90 - 0.25*r]; byte c covers longitude')
  w('-- [-180 + 0.25*c, -180 + 0.25*(c+1)). Byte value 0 = not navigable sea here (land, ice, or a')
  w('-- landlocked pool no route can reach); 1-255 = public.seas.raster_ordinal.')
  w('-- STORAGE SHAPE IS THE POINT (docs/DESIGN_RESEARCH_NAVIGATION.md P.5): one TOASTed bytea costs')
  w('-- ~843 ms per detoasting read; 720 inline rows cost 4-8 ms. 1,440 bytes sits under the TOAST')
  w("-- threshold and `storage main` states the intent structurally.")
  w('create table if not exists public.sea_cells (')
  w('  row_idx int   primary key check (row_idx between 0 and 719),')
  w('  seas    bytea not null   check (octet_length(seas) = 1440)')
  w(');')
  w('alter table public.sea_cells alter column seas set storage main;')
  w("comment on table public.sea_cells is 'WHICH SEA each 0.25° cell of water belongs to — the spatial key piracy, hazards and NPC levels hang on. Generated by scripts/build-sea-raster.mjs from Natural Earth marine polygons; the water mask itself (channels, ice) is scripts/sea-grid.mjs. One byte per cell = seas.raster_ordinal, 0 = no navigable sea.';")
  w('')
  w('-- Server-private, the 0035 voyage_event_kinds posture: RLS on, NO policy, NO grant. Nothing')
  w('-- the client renders comes from here directly; voyage.sea_at is the one door, and a cloud map')
  w('-- read would be a world.* + registry + catalog slice of its own.')
  w('alter table public.sea_cells enable row level security;')
  w('')
  // The rows, base64. 720 inserts in batches of 45.
  const rows = []
  for (let r = 0; r < ROWS; r++) {
    rows.push(Buffer.from(grid.subarray(r * COLS, (r + 1) * COLS)).toString('base64'))
  }
  for (let b = 0; b < ROWS; b += 45) {
    w('insert into public.sea_cells (row_idx, seas) values')
    const vals = []
    for (let r = b; r < Math.min(b + 45, ROWS); r++) {
      vals.push(`  (${r}, decode('${rows[r]}', 'base64'))`)
    }
    w(vals.join(',\n'))
    w('on conflict (row_idx) do nothing;')
    w('')
  }
  w('-- ── 3. the lookup — ONE authority for "which sea is this point in" ────────────────────────────')
  w('-- voyage, beside voyage.gc_distance_nm: a geometry read the sea-side rules compose. STRICT on')
  w("-- land: null means \"not at sea here\", it is NEVER a navigability answer (the mover's water")
  w('-- raster owns that). Not granted to any client role — no client caller exists; the day a map')
  w('-- label wants it, that slice adds a world.* read, a client_rpc_entry_points row and a')
  w('-- src/lib/rpc/catalog.ts row TOGETHER (never-ship-half-a-slice).')
  w('create or replace function voyage.sea_at(p_lat double precision, p_lon double precision)')
  w('returns uuid')
  w('language plpgsql')
  w('stable')
  w('security definer')
  w('set search_path = public, pg_temp')
  w('as $$')
  w('declare')
  w('  v_col int;')
  w('  v_ord int;')
  w('begin')
  w('  if p_lat is null or p_lon is null or p_lat < -90 or p_lat > 90 then')
  w('    return null;')
  w('  end if;')
  w(`  v_col := ((floor((p_lon + 180) / ${CELL_DEG})::int % ${COLS}) + ${COLS}) % ${COLS};`)
  w(`  select get_byte(c.seas, v_col) into v_ord`)
  w('    from public.sea_cells c')
  w(`   where c.row_idx = least(${ROWS - 1}, greatest(0, floor((90 - p_lat) / ${CELL_DEG})::int));`)
  w('  if v_ord is null or v_ord = 0 then return null; end if;')
  w('  return (select s.id from public.seas s where s.raster_ordinal = v_ord);')
  w('end $$;')
  w('')
  w("comment on function voyage.sea_at(double precision, double precision) is 'WHICH SEA is this point in — total over navigable water, null on land/ice/landlocked pools. The one spatial-membership authority: hazard sampling on a free path, NPC placement by sea, storm placement all compose THIS, never a centroid distance.';")
  w('')
  w('revoke all on function voyage.sea_at(double precision, double precision) from public, anon, authenticated;')
  w('')
  w('-- ── 4. SELF-ASSERT ────────────────────────────────────────────────────────────────────────────')
  w('do $$')
  w('declare')
  w('  v_rows int;')
  w('  v_bad  int;')
  w('  v_missing text;')
  w('  v_expected_disagreements text[] := array[')
  if (chainDis.length === 0) {
    w('  ]::text[];')
  } else {
    w(chainDis.map((d) => `    ${sqlQ(d.key)}`).join(',\n'))
    w('  ];')
  }
  w('  v_found_disagreements text[];')
  w('  v_port record;')
  w('  v_ord int;')
  w('  v_r0 int; v_c0 int; v_row int; v_col int; v_ring int; v_dr int; v_dc int;')
  w('  v_resolved uuid;')
  w('  v_probe uuid;')
  w('  v_unresolved text;')
  w('begin')
  w('  -----------------------------------------------------------------------------------------------')
  w('  -- (a) SHAPE: 720 rows, every byte value resolves to a sea, every sea has extent somewhere.')
  w('  --     Not a bare count: the two set-differences are what make an orphan byte or an extent-less')
  w('  --     sea IMPOSSIBLE to ship, whichever direction the drift runs.')
  w('  -----------------------------------------------------------------------------------------------')
  w('  select count(*) into v_rows from public.sea_cells;')
  w(`  if v_rows <> ${ROWS} then`)
  w(`    raise exception '0040 self-assert FAIL: % raster rows, expected ${ROWS}', v_rows;`)
  w('  end if;')
  w('  select count(*) into v_bad')
  w('    from (select distinct get_byte(c.seas, i.i) as b')
  w('            from public.sea_cells c')
  w(`           cross join generate_series(0, ${COLS - 1}) as i(i)) bytes`)
  w('   where bytes.b > 0')
  w('     and not exists (select 1 from public.seas s where s.raster_ordinal = bytes.b);')
  w('  if v_bad > 0 then')
  w("    raise exception '0040 self-assert FAIL: % raster byte value(s) name no sea', v_bad;")
  w('  end if;')
  w("  select string_agg(s.name, ', ' order by s.name) into v_missing")
  w('    from public.seas s')
  w('   where not exists (')
  w('     select 1 from public.sea_cells c')
  w(`      cross join generate_series(0, ${COLS - 1}) as i(i)`)
  w('      where get_byte(c.seas, i.i) = s.raster_ordinal);')
  w('  if v_missing is not null then')
  w("    raise exception '0040 self-assert FAIL: sea(s) with NO extent in the raster: %', v_missing;")
  w('  end if;')
  w('')
  w('  -----------------------------------------------------------------------------------------------')
  w('  -- (b) EVERY PORT RESOLVES, and the disagreements with the declared sea are EXACTLY the ones')
  w('  --     this generation found, by name — a delta against the world as found, not a count. The')
  w('  --     ring search mirrors scripts/build-sea-raster.mjs resolveAt() byte for byte.')
  w('  -----------------------------------------------------------------------------------------------')
  w('  v_found_disagreements := array[]::text[];')
  w('  for v_port in')
  w("    select p.name || '/' || p.country as key, p.lat, p.lon, p.sea_id")
  w('      from public.ports p')
  w('     order by p.code')
  w('  loop')
  w(`    v_r0 := least(${ROWS - 1}, greatest(0, floor((90 - v_port.lat) / ${CELL_DEG})::int));`)
  w(`    v_c0 := ((floor((v_port.lon + 180) / ${CELL_DEG})::int % ${COLS}) + ${COLS}) % ${COLS};`)
  w('    v_resolved := null;')
  w('    <<rings>>')
  w('    for v_ring in 0 .. 8 loop')
  w('      for v_dr in -v_ring .. v_ring loop')
  w('        for v_dc in -v_ring .. v_ring loop')
  w('          continue when greatest(abs(v_dr), abs(v_dc)) <> v_ring;')
  w('          v_row := v_r0 + v_dr;')
  w(`          continue when v_row < 0 or v_row > ${ROWS - 1};`)
  w(`          v_col := ((v_c0 + v_dc) % ${COLS} + ${COLS}) % ${COLS};`)
  w('          select get_byte(c.seas, v_col) into v_ord from public.sea_cells c where c.row_idx = v_row;')
  w('          if v_ord > 0 then')
  w('            select s.id into v_resolved from public.seas s where s.raster_ordinal = v_ord;')
  w('            exit rings;')
  w('          end if;')
  w('        end loop;')
  w('      end loop;')
  w('    end loop;')
  w('    if v_resolved is null then')
  w("      v_unresolved := coalesce(v_unresolved || ', ', '') || v_port.key;")
  w('    elsif v_resolved <> v_port.sea_id then')
  w('      v_found_disagreements := v_found_disagreements || v_port.key;')
  w('    end if;')
  w('  end loop;')
  w('  if v_unresolved is not null then')
  w("    raise exception '0040 self-assert FAIL: port(s) resolve to NO sea within 8 rings (~120 nm): %', v_unresolved;")
  w('  end if;')
  w('  if exists (select 1 from unnest(v_found_disagreements) f(k)')
  w('              where not (f.k = any(v_expected_disagreements)))')
  w('     or exists (select 1 from unnest(v_expected_disagreements) e(k)')
  w('              where not (e.k = any(v_found_disagreements))) then')
  w("    raise exception '0040 self-assert FAIL: port-vs-cell disagreements drifted. found: [%] expected: [%]',")
  w("      array_to_string(v_found_disagreements, ', '), array_to_string(v_expected_disagreements, ', ');")
  w('  end if;')
  w('')
  w('  -----------------------------------------------------------------------------------------------')
  w('  -- (c) GEOGRAPHY CONTROLS: five real places answer by NAME, and dry land answers nothing.')
  w('  --     These assert the Earth, not the seed: mid-North-Atlantic, the Channel off Portsmouth,')
  w('  --     mid-Adriatic, the Malacca narrows (water only because a CHANNEL forced it open — so this')
  w('  --     also proves channel cells carry a sea), the central Gulf of Mexico, the Sea of Japan —')
  w('  --     and the middle of the Sahara, which must be NULL (strict: null is "not at sea", never')
  w('  --     a navigability answer).')
  w('  -----------------------------------------------------------------------------------------------')
  const controls = [
    [35, -40, 'North Atlantic Ocean'],
    [50.5, -1.0, 'English Channel'],
    [42.8, 15.0, 'Adriatic Sea'],
    [3.0, 100.4, 'Strait of Malacca'],
    [25, -90, 'Gulf of Mexico'],
    [40, 135, 'Sea of Japan'],
  ]
  for (const [lat, lon, name] of controls) {
    w(`  v_probe := voyage.sea_at(${lat}, ${lon});`)
    w(`  if v_probe is null or v_probe <> (select id from public.seas where name = ${sqlQ(name)}) then`)
    w(`    raise exception '0040 self-assert FAIL: (${lat}, ${lon}) should be ${name}, got %',`)
    w("      coalesce((select name from public.seas where id = v_probe), 'NULL');")
    w('  end if;')
  }
  w('  if voyage.sea_at(23, 10) is not null then')
  w("    raise exception '0040 self-assert FAIL: the middle of the Sahara answered a sea: %',")
  w('      (select name from public.seas where id = voyage.sea_at(23, 10));')
  w('  end if;')
  w('')
  w('  -----------------------------------------------------------------------------------------------')
  w('  -- (d) POSTURE: the read wall did not move.')
  w('  -----------------------------------------------------------------------------------------------')
  w('  if (select count(*) from public.client_write_grants()) <> 0')
  w('     or (select count(*) from public.client_executable_writers()) <> 0')
  w('     or (select count(*) from public.client_rpc_entry_points() e where e.fn is null) <> 0')
  w('     or (select count(*) from public.caller_evaluated_functions()) <> 0')
  w("     or has_function_privilege('anon', 'voyage.sea_at(double precision, double precision)', 'execute')")
  w("     or has_function_privilege('authenticated', 'voyage.sea_at(double precision, double precision)', 'execute') then")
  w("    raise exception '0040 self-assert FAIL: the read wall moved — a client grant appeared, or sea_at is client-executable';")
  w('  end if;')
  w('')
  w(`  raise notice '0040 self-assert ok: EVERY WATER ANSWERS ITS SEA — ${ROWS} raster rows, every byte names a sea and all ${SEAS.length} seas have extent; all % ports resolve within 8 rings and the % known port-vs-cell disagreements matched by name; six real waters from the Channel to the Sea of Japan answer correctly and the Sahara answers null; danger 1-5 and a plain-words note on every sea (marked: read by no rule yet); sea_cells is server-private and sea_at is not client-executable; 0 client write grants',`)
  w(`    ${recon.inChainTotal}, ${chainDis.length};`)
  w('end $$;')
  w('')
  // NEVER OVERWRITE AN APPLIED MIGRATION. 0040 has run; editing it in place is the D23 defect
  // (docs/DEV_LOG.md: production keeps the ORIGINAL bytes while every fresh rebuild gets the new
  // ones, and nothing goes red). This guard became load-bearing on 2026-08-25, when migration 0052
  // opened the Bristol Channel in the shared scripts/sea-grid.mjs: re-running this generator would
  // now emit a 0040 whose bytes DIFFER from the applied one. A membership change goes in a new
  // migration that supersedes 0040's data, exactly as 0052 did for 0046's.
  if (existsSync(MIGRATION)) {
    throw new Error(
      `${MIGRATION} already exists and has been applied — refusing to rewrite it (README §1: never ` +
        `edit an applied migration). Point MIGRATION at a NEW version and have the emitted SQL ` +
        `UPDATE public.sea_cells / public.seas instead of seeding them, the way ` +
        `scripts/build-sea-migration.mjs supersedes its own predecessor.`,
    )
  }
  writeFileSync(MIGRATION, L.join('\n'))
  console.log(`wrote ${MIGRATION} (${(L.join('\n').length / 1024).toFixed(0)} KiB)`)
}

// ── 7. the picture — the proof a query cannot give ────────────────────────────────────────────
function crc32(buf) {
  let c, table = crc32.table
  if (!table) {
    table = crc32.table = new Int32Array(256)
    for (let n = 0; n < 256; n++) {
      c = n
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1
      table[n] = c
    }
  }
  c = 0 ^ -1
  for (let i = 0; i < buf.length; i++) c = (c >>> 8) ^ table[(c ^ buf[i]) & 0xff]
  return (c ^ -1) >>> 0
}

function pngEncode(width, height, rgb) {
  const chunk = (type, data) => {
    const out = Buffer.alloc(8 + data.length + 4)
    out.writeUInt32BE(data.length, 0)
    out.write(type, 4)
    data.copy(out, 8)
    out.writeUInt32BE(crc32(out.subarray(4, 8 + data.length)), 8 + data.length)
    return out
  }
  const ihdr = Buffer.alloc(13)
  ihdr.writeUInt32BE(width, 0); ihdr.writeUInt32BE(height, 4)
  ihdr[8] = 8; ihdr[9] = 2 // 8-bit, truecolor
  const raw = Buffer.alloc(height * (1 + width * 3))
  for (let y = 0; y < height; y++) {
    rgb.copy(raw, y * (1 + width * 3) + 1, y * width * 3, (y + 1) * width * 3)
  }
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ])
}

function hslToRgb(h, s, l) {
  s /= 100; l /= 100
  const k = (n) => (n + h / 30) % 12
  const a = s * Math.min(l, 1 - l)
  const f = (n) => l - a * Math.max(-1, Math.min(k(n) - 3, Math.min(9 - k(n), 1)))
  return [Math.round(f(0) * 255), Math.round(f(8) * 255), Math.round(f(4) * 255)]
}

function palette() {
  const colors = [[26, 26, 30]] // 0 = land / no sea
  for (let i = 1; i <= SEAS.length; i++) {
    colors.push(hslToRgb((i * 137.508) % 360, 62, i % 2 ? 58 : 38))
  }
  return colors
}

function renderPng(grid, water, path, view) {
  const colors = palette()
  const { latMax = 90, latMin = -90, lonMin = -180, lonMax = 180, scale = 1 } = view ?? {}
  const r1 = rowOf(latMax), r2 = rowOf(latMin), c1 = colOf(lonMin), c2 = colOf(lonMax - 1e-9)
  const w = (c2 - c1 + 1) * scale, h = (r2 - r1 + 1) * scale
  const rgb = Buffer.alloc(w * h * 3)
  for (let row = r1; row <= r2; row++) {
    for (let col = c1; col <= c2; col++) {
      const i = row * COLS + col
      let color = colors[grid[i]]
      if (water[i] === 1 && grid[i] === 0) color = [255, 0, 255] // unassigned water: loud magenta
      for (let sy = 0; sy < scale; sy++) {
        for (let sx = 0; sx < scale; sx++) {
          const o = (((row - r1) * scale + sy) * w + (col - c1) * scale + sx) * 3
          rgb[o] = color[0]; rgb[o + 1] = color[1]; rgb[o + 2] = color[2]
        }
      }
    }
  }
  // Port dots: white with a black rim, so boundaries can be judged against real harbours.
  const marks = [
    ...portsFile.ports.map((p) => [p.lat, p.lon]),
    ...placesFile.places.map((p) => [p.lat, p.lon]),
  ]
  for (const [lat, lon] of marks) {
    if (lat > latMax || lat < latMin || lon < lonMin || lon > lonMax) continue
    const px = Math.round(((colOf(lon) - c1) + 0.5) * scale)
    const py = Math.round(((rowOf(lat) - r1) + 0.5) * scale)
    const dot = scale >= 4 ? 2 : 1
    for (let dy = -dot; dy <= dot; dy++) {
      for (let dx = -dot; dx <= dot; dx++) {
        const x = px + dx, y = py + dy
        if (x < 0 || x >= w || y < 0 || y >= h) continue
        const o = (y * w + x) * 3
        const rim = Math.max(Math.abs(dx), Math.abs(dy)) === dot
        const v = rim ? 0 : 255
        rgb[o] = v; rgb[o + 1] = v; rgb[o + 2] = v
      }
    }
  }
  writeFileSync(path, pngEncode(w, h, rgb))
  console.log(`wrote ${path} (${w}x${h})`)
}

// ── main ──────────────────────────────────────────────────────────────────────────────────────
const marine = await loadMarine()
console.log(`marine cache: ${marine.features.length} features for ${new Set(marine.features.map((f) => f.sea)).size} seas`)
const water = buildSeaGrid()
const { grid, waterCells, unassigned } = assign(water, marine)
const components = unassignedComponents(water, grid)
const componentsNote = components.length === 0
  ? 'none.'
  : components.slice(0, 6).map((c) => `${c.size} cells near (${c.lat}, ${c.lon})`).join('; ')
    + ` — ${components.length} landlocked pool(s) no sea route reaches (the largest is the Caspian).`
console.log('unassigned components:', components.slice(0, 10))

const recon = reconcile(grid)
console.log(`ports checked ${recon.total}; unresolved ${recon.unresolved.length}; disagreements ${recon.disagreements.length}`)
for (const d of recon.disagreements) console.log(`  ${d.key}: declared ${d.declared} -> cell says ${d.resolved} (ring ${d.ring})`)
if (recon.unresolved.length) console.log('UNRESOLVED:', recon.unresolved)

// per-sea cell counts (extent sanity)
const counts = new Array(SEAS.length + 1).fill(0)
for (let i = 0; i < grid.length; i++) counts[grid[i]]++
const empty = SEAS.filter((s, i) => counts[i + 1] === 0)
if (empty.length) console.log('SEAS WITH NO EXTENT:', empty.map((s) => s.id))
console.log('smallest extents:', SEAS.map((s, i) => [s.id, counts[i + 1]]).sort((a, b) => a[1] - b[1]).slice(0, 8))

writeMigration(grid, recon, waterCells, unassigned, componentsNote)

const pngDirIx = process.argv.indexOf('--png')
if (pngDirIx > -1) {
  const dir = process.argv[pngDirIx + 1]
  renderPng(grid, water, join(dir, 'sea-raster-world.png'), { scale: 1 })
  renderPng(grid, water, join(dir, 'sea-raster-channel.png'), { latMax: 54, latMin: 47, lonMin: -8, lonMax: 5, scale: 10 })
  renderPng(grid, water, join(dir, 'sea-raster-adriatic.png'), { latMax: 46, latMin: 34, lonMin: 12, lonMax: 29, scale: 8 })
  renderPng(grid, water, join(dir, 'sea-raster-malacca.png'), { latMax: 9, latMin: -8, lonMin: 93, lonMax: 110, scale: 8 })
  renderPng(grid, water, join(dir, 'sea-raster-gulf-of-mexico.png'), { latMax: 32, latMin: 7, lonMin: -100, lonMax: -58, scale: 5 })
  renderPng(grid, water, join(dir, 'sea-raster-sea-of-japan.png'), { latMax: 52, latMin: 30, lonMin: 122, lonMax: 145, scale: 6 })
}
