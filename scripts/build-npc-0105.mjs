// ═══════════════════════════════════════════════════════════════════════════════════════════════
// build-npc-0105.mjs — ~760 merchant fleets over ~220 routes, GENERATED, and the migration that
// founds them dark. docs/NPC_FLEET_SCALE.md slice C. Owner rows 116, 118, 119, 122a.
// EMITS supabase/migrations/20260818000105_the_merchants_are_counted_by_their_coasts.sql
//        data/npc-roster.generated.json
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// WHAT THIS IS NOT. It is not scripts/build-npc-0098.mjs with bigger numbers. 0098 MEASURES every
// candidate loop of every fleet with the whole roster sailing, and that took hours at 107 fleets;
// 760 one by one does not fit in a day, let alone a CI gate. So three things move, and each is
// said out loud in the receipt, in the migration header and in the commit:
//
//   1. THE SHARE IS DERIVED. fleets(nation) = round(760 × Σ(dev_commerce + dev_industry) over that
//      nation's HARBOURS ÷ Σ over all nations). Linear in one authored sum, monotone in wealth, no
//      floor and no ceiling needed. Owner row 119 — "powerful and rich countries will have more
//      ships" — answered from what the world already says, never from an opinion. The formula is
//      re-derived and ASSERTED inside the migration, so nobody can quietly hand their favourite
//      nation a navy. (The rejected alternative, (commerce+industry) × Σsize_tier, multiplies two
//      quantities that both grow with harbour count: quadratic in size, Castile 54 %, Persia 1.)
//
//   2. THE MEASUREMENT MOVES OFF THE FLEET. A route is MEASURED once (several fleets share it) and
//      every fleet that sails it inherits the figure; and only a SAMPLE of routes is sailed at all.
//      Capital is DERIVED for every route from the SERVER'S OWN PLANNER — public.npc_plan, run per
//      route on the untouched market, whose lines are then priced through world.quote — and that
//      derivation is VALIDATED against the sailed sample. What this gives up is the whole-roster
//      market interaction over many laps: that was always the deploy's soak (NPC_TRADERS §5.1),
//      and it is admitted here rather than quietly dropped. A derivation is never reported as a
//      measurement: the generated JSON tags every figure `measured` or `derived`.
//
//   3. THE NAMES ARE COMPOSED, not authored. scripts/roster/npc-names.mjs holds each nation's own
//      naming HABIT over family and given-name pools; the PLACE element is read off public.ports.
//      Every draw is seeded from a hash of (nation, index) — never Math.random().
//
// WHAT IT STILL REFUSES, exactly as 0098 does (printed, never silently dropped): a stop that is
// not a HARBOUR · a harbour twice in one loop · a draft a stop cannot take · a quay that cannot
// crew its share (and 0097's npc_crew_pool_floor, 25, which a merchant may not draw a quay below)
// · a leg THE pathfinder cannot plot from the served roadsteads · a course the SERVER's own
// voyage.path_refusal refuses as cmd.do_sail calls it · a name production has taken.
//
// USAGE
//   node scripts/build-npc-0105.mjs [--fleets 760] [--routes 220] [--sample 40] [--laps 6]
//                                   [--taken names.txt] [--no-emit] [--no-sail]
//   --taken: one company name per line — production's `select company_name from public.players`.
// ═══════════════════════════════════════════════════════════════════════════════════════════════

import { readFile, writeFile, stat } from 'node:fs/promises'
import { createHash } from 'node:crypto'
import path from 'node:path'
import os from 'node:os'
import { applyChain, migrationFiles, MIGRATIONS_DIR, PREAMBLE_PATH, REPO_ROOT } from './db/apply-chain.mjs'
import { navFromServed, findPath } from '../src/lib/sea/index.ts'
import { NATIONS, INK, RUN_WORDS, NAME_MAX, hash32, rng, deburr, altSpellings } from './roster/npc-names.mjs'

const { PGlite } = await import('@electric-sql/pglite')

// ── arguments ─────────────────────────────────────────────────────────────────────────────────
const argv = process.argv.slice(2)
const opt = (n, d) => { const i = argv.indexOf(n); return i >= 0 ? argv[i + 1] : d }
const TARGET_FLEETS = Number(opt('--fleets', '760'))
const TARGET_ROUTES = Number(opt('--routes', '220'))
const SAMPLE = Number(opt('--sample', '40'))
// MEASURED: a cap of OLD_FLEETS + 40 started only TWELVE of 0105's routes, because 0098's 76 hold
// the first slots of roster_ord and only about a third of any prefix starts at all (the rest are
// laid up for want of a cargo). So the cap goes SAMPLE_SCOPE deep and the sample is whoever SAILS.
const SAMPLE_SCOPE = Number(opt('--sample-scope', String(3 * Number(opt('--sample', '40')))))
const LAPS = Number(opt('--laps', '6'))
const MAX_SIM_HOURS = Number(opt('--max-sim-hours', '240'))
const SAMPLE_MINUTES = Number(opt('--sample-minutes', '25'))
const EMIT = !argv.includes('--no-emit')
const SAIL = !argv.includes('--no-sail')
// the middle ceiling costs four minutes (the 781 MB image is re-loaded and the roster re-founded)
// and the decision only needs the pair: what the knob is today, and what it would be at the roster
const CEILINGS_ALL = argv.includes('--all-ceilings')
const TAKEN_FILE = opt('--taken', null)
const STOP = '20260818000105'
const SLUG = 'the_merchants_are_counted_by_their_coasts'
const OUT_SQL = opt('--out-sql', path.join(MIGRATIONS_DIR, `${STOP}_${SLUG}.sql`))
const OUT_JSON = opt('--out-json', path.join(REPO_ROOT, 'data', 'npc-roster.generated.json'))
const MEASURE_CAPITAL = 50_000_000
const ROSTER_BASE = 1000          // 0098 used 1..76; 0097's probe 9001/9002. No collision.
const say = (...a) => console.log(...a)
const t00 = Date.now()
const el = () => `${((Date.now() - t00) / 1000).toFixed(0)}s`

// ── the chain, cached by a fingerprint of everything it applies ───────────────────────────────
const chainFiles = (await migrationFiles()).filter((f) => f < STOP)
const fpr = createHash('md5')
fpr.update(await readFile(PREAMBLE_PATH, 'utf8'))
for (const f of chainFiles) fpr.update(f).update(await readFile(path.join(MIGRATIONS_DIR, f), 'utf8'))
const CACHE = path.join(os.tmpdir(), `byeharu-npc-chain-${fpr.digest('hex').slice(0, 16)}.tar`)
let cacheBytes = null
async function freshDb() {
  if (!cacheBytes && (await stat(CACHE).then(() => true, () => false))) cacheBytes = await readFile(CACHE)
  if (cacheBytes) return PGlite.create({ loadDataDir: new Blob([cacheBytes], { type: 'application/x-tar' }) })
  say(`applying ${chainFiles.length} migrations (0001-${chainFiles.at(-1).slice(10, 14)}) …`)
  const { db } = await applyChain({ quiet: true, log: () => {}, stopBefore: STOP })
  cacheBytes = Buffer.from(new Uint8Array(await (await db.dumpDataDir('none')).arrayBuffer()))
  await writeFile(CACHE, cacheBytes)
  say(`cached the applied chain at ${CACHE} (${(cacheBytes.length / 1e6).toFixed(0)} MB) — ${el()}`)
  return db
}
const rows = async (db, sql, p = []) => (await db.query(sql, p)).rows
const one = async (db, sql, p = []) => (await db.query(sql, p)).rows[0]
const lit = (s) => `'${String(s).replace(/'/g, "''")}'`

// ══ 1. THE STATIC WORLD ═══════════════════════════════════════════════════════════════════════
const db0 = await freshDb()
const K = Object.fromEntries((await rows(db0, `select key, value from public.world_config`)).map((r) => [r.key, r.value]))
const GAME_DAY = Number(K.game_day_seconds)
const PACE = Number(K.npc_laps_per_game_day)
const CREW_FLOOR = Number(K.npc_crew_pool_floor)
const STOP_MAX = Number(K.standing_route_stop_max)
const MIN_NET_TO_WAGES = Number(K.npc_min_net_to_wages)

const allPorts = await rows(db0, `
  select p.code, p.name, p.kind, p.culture, p.size_tier,
         p.lat::float8 lat, p.lon::float8 lon,
         p.max_draft::float8 max_draft, p.crew_pool::float8 crew_pool,
         p.dev_commerce::float8 dev_commerce, p.dev_industry::float8 dev_industry,
         n.code nation, r.code region, r.name region_name,
         sr.roadstead_lat::float8 rlat, sr.roadstead_lon::float8 rlon
    from public.ports p
    left join public.nations n on n.id = p.nation_id
    left join public.regions r on r.id = p.region_id
    left join public.sea_reaches sr on sr.port_id = p.id
   order by p.code`)
const ports = new Map(allPorts.map((p) => [p.code, p]))
const HARBOURS = allPorts.filter((p) => p.kind === 'HARBOUR' && Number.isFinite(p.rlat))
const nations = new Map((await rows(db0, `select code, name, capital_port_code from public.nations`)).map((n) => [n.code, n]))
const classes = new Map((await rows(db0, `
  select code, name, hold::float8 hold, crew_required, draft::float8 draft, speed_kn::float8 kn, tier
    from public.ship_classes order by tier`)).map((c) => [c.code, c]))
const goods = new Map((await rows(db0, `select code, name, bulk::float8 bulk, culture_mask from public.goods`)).map((g) => [g.code, g]))
const officerPool = await rows(db0, `
  select o.code, o.specialty, o.wage_ducats::float8 wage, n.code nation, p.code home
    from public.officers o left join public.nations n on n.id = o.nation_id left join public.ports p on p.id = o.home_port_id
   order by o.code`)
const raster = await one(db0, `
  select cols, rows, cell_deg::float8 as cell_deg, bits_per_cell,
         replace(encode(cells, 'base64'), e'\\n', '') as cells_base64 from public.sea_raster where id = 1`)
const nav = navFromServed(raster)
const OLD_FLEETS = Number((await one(db0, `select count(*)::int n from public.npc_fleets`)).n)
const taken = new Set(TAKEN_FILE ? (await readFile(TAKEN_FILE, 'utf8')).split(/\r?\n/).map((s) => s.trim()).filter(Boolean) : [])
// ── THE NAMES ALREADY TAKEN ON THIS CHAIN ────────────────────────────────────────────────────
// MEASURED: six composed names collided with 0098's own ("Companhia de Setubal", "Compania de
// Manila", "Kamer van Amsterdam", "Compagnie de Saint-Malo" and two more). npc_found falls back to
// the SECOND spelling silently-but-for-a-notice (0097:284), so the migration would have founded
// six houses under their alternates and only the self-assert would have said so, on apply. The
// authoritative taken-set is the chain itself -- every company_name already in public.players --
// plus BOTH spellings data/npc-houses.json authored, because 0098's alternate is a real name too.
// --taken is still how production's own roll is handed in.
for (const r of await rows(db0, `select company_name from public.players`)) taken.add(r.company_name)
for (const h of JSON.parse(await readFile(path.join(REPO_ROOT, 'data', 'npc-houses.json'), 'utf8')).houses) {
  taken.add(h.company); taken.add(h.alt_company)
}
say(`names already taken on this chain: ${taken.size} (public.players plus both spellings data/npc-houses.json authored)`)

// THE GRADIENT, as a table read. port_goods is the authored soul of the world (0005): below 1 the
// port PRODUCES the good and sells it cheap, above 1 it is a SINK and pays dear, and "the gradient
// between two ports is the game". 132,090 rows is one read, not ~320k price computations.
const AFF = new Map()        // port code -> Map(good code -> affinity)
for (const r of await rows(db0, `
  select p.code port, g.code good, pg.affinity::float8 affinity
    from public.port_goods pg join public.ports p on p.id = pg.port_id join public.goods g on g.id = pg.good_id`)) {
  let m = AFF.get(r.port); if (!m) AFF.set(r.port, (m = new Map()))
  m.set(r.good, r.affinity)
}
/** What a harbour SELLS CHEAP and its own culture will handle: the 40 lowest affinities under 1. */
const OFFERS = new Map()
for (const p of HARBOURS) {
  const m = AFF.get(p.code) ?? new Map()
  const list = []
  for (const [g, a] of m) {
    if (a >= 0.99) continue
    const gd = goods.get(g)
    if (!gd || (gd.culture_mask ?? []).includes(p.culture)) continue
    list.push([g, a])
  }
  list.sort((x, y) => x[1] - y[1])
  OFFERS.set(p.code, list.slice(0, 40))
}
say(`world: ${HARBOURS.length} harbours (${HARBOURS.filter((p) => !p.nation).length} unaligned), ${nations.size} nations, ${classes.size} classes, stop_max ${STOP_MAX}, crew floor ${CREW_FLOOR} — ${el()}`)

// public.ships and public.players both band a name at 3..24 characters (0004:90, 0004:52). A pool
// entry that cannot fit is a build-time refusal, never a silent truncation inside the migration.
for (const [n, N] of Object.entries(NATIONS)) {
  // A HULL NAME is written straight into public.ships, which bands it 3..24. Family and given
  // names are only ever used INSIDE a pattern, so a two-letter Ming surname is not a defect.
  const bad = N.hulls.filter((x) => x.length < 3 || x.length > NAME_MAX)
  if (bad.length) { say(`REFUSED: ${n}'s hull names do not fit 3..${NAME_MAX} characters: ${bad.join(', ')}`); process.exit(1) }
  const long = [...N.family, ...N.given, ...N.titles].filter((x) => x.length > NAME_MAX)
  if (long.length) { say(`REFUSED: ${n}'s name material is longer than ${NAME_MAX}: ${long.join(', ')}`); process.exit(1) }
  if (N.hulls.length < 3) { say(`REFUSED: ${n} has fewer than three hull names`); process.exit(1) }
}

const R_EARTH_NM = 3440.065
const gc = (la1, lo1, la2, lo2) => {
  const r = Math.PI / 180
  const s = Math.sin((la2 - la1) * r / 2) ** 2 + Math.cos(la1 * r) * Math.cos(la2 * r) * Math.sin((lo2 - lo1) * r / 2) ** 2
  return 2 * R_EARTH_NM * Math.asin(Math.min(1, Math.sqrt(s)))
}
/** Roadstead to roadstead: how far she actually sails between two berths. */
const hav = (a, b) => gc(a.rlat, a.rlon, b.rlat, b.rlon)
/** Harbour to harbour, which is what the migration's own self-assert measures through
 *  voyage.gc_distance_nm on public.ports — the same formula and the same Earth radius, so the
 *  "a long way from home" test is the SAME number on both sides of the build. */
const havPort = (a, b) => gc(a.lat, a.lon, b.lat, b.lon)

// ══ 2. THE SHARE, DERIVED ═════════════════════════════════════════════════════════════════════
// share(nation) = Σ(dev_commerce + dev_industry) over that nation's HARBOURS ÷ Σ over all nations.
// Home ports come only from a nation's OWN harbours; the unaligned harbours are DESTINATIONS,
// which is also what they historically were.
const devOf = (p) => p.dev_commerce + p.dev_industry
const nationHarbours = new Map()
for (const p of HARBOURS) if (p.nation) {
  if (!nationHarbours.has(p.nation)) nationHarbours.set(p.nation, [])
  nationHarbours.get(p.nation).push(p)
}
const nationDev = new Map([...nationHarbours].map(([n, hs]) => [n, hs.reduce((a, p) => a + devOf(p), 0)]))
const DEV_TOTAL = [...nationDev.values()].reduce((a, b) => a + b, 0)
const shareOrder = [...nationDev.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
// round-half-up in EXACT INTEGER arithmetic, so the JS figure and the migration's own
// `round(760 * dev / total)` on numeric cannot disagree on a value that lands on .5
const roundShare = (dev) => Math.floor((2 * TARGET_FLEETS * dev + DEV_TOTAL) / (2 * DEV_TOTAL))
const fleetsOf = new Map(shareOrder.map(([n, v]) => [n, roundShare(v)]))
const routesOf = new Map(shareOrder.map(([n]) => [n, fleetsOf.get(n) === 0 ? 0 : Math.max(1, Math.min(fleetsOf.get(n), Math.round(fleetsOf.get(n) * TARGET_ROUTES / TARGET_FLEETS)))]))
say(`\n== the derived share (Σ dev_commerce + dev_industry over a nation's harbours ÷ ${DEV_TOTAL})`)
for (const [n, v] of shareOrder) {
  say(`   ${n} ${nations.get(n).name.padEnd(18)} dev ${String(v).padStart(4)}  ${((v / DEV_TOTAL) * 100).toFixed(2).padStart(5)} %  ` +
      `fleets ${String(fleetsOf.get(n)).padStart(3)}  routes ${String(routesOf.get(n)).padStart(2)}  harbours ${String(nationHarbours.get(n).length).padStart(2)}`)
}
say(`   TOTAL ${[...fleetsOf.values()].reduce((a, b) => a + b, 0)} fleets over ${[...routesOf.values()].reduce((a, b) => a + b, 0)} routes, ` +
    `${shareOrder.length} nations, no floor and no ceiling applied`)
// the rejected formula, printed so the receipt carries the comparison rather than the claim
{
  const q = new Map([...nationHarbours].map(([n, hs]) => [n, hs.reduce((a, p) => a + devOf(p), 0) * hs.reduce((a, p) => a + p.size_tier, 0)]))
  const qt = [...q.values()].reduce((a, b) => a + b, 0)
  const top = [...q].sort((a, b) => b[1] - a[1])
  say(`   rejected ((commerce+industry) × Σsize_tier): ${top[0][0]} ${((top[0][1] / qt) * 100).toFixed(0)} % = ${Math.round(top[0][1] / qt * TARGET_FLEETS)} fleets ` +
      `against ${top.at(-1)[0]}'s ${Math.round(top.at(-1)[1] / qt * TARGET_FLEETS)} — quadratic in harbour count, which is why it is not used`)
}

// ══ 3. LEGS: REAL WATER, AND THE SERVER'S OWN REFUSAL ════════════════════════════════════════
const refusals = []
const plotCache = new Map()     // the course THE pathfinder lays, and its own length
const verifyCache = new Map()   // and what the SERVER says about that course
let pathCalls = 0
let pathFails = 0
let pathMs = 0
let verifyCalls = 0

/**
 * SCREENING is done without the server, and this is why. Scoring a next stop means plotting a
 * candidate leg and measuring it; measuring it through voyage.segments_from_course costs a round
 * trip of about 150 ms, and the build plots thousands of candidate legs it will never use. At
 * eight candidates a stop that was sixty seconds a route and climbing.
 *
 * The sum of the great-circle distances between a course's consecutive points is EXACTLY what the
 * server's own measure sums (voyage.segments_from_course splits a long piece but splits it along
 * the same great circle, and voyage.gc_distance_nm is the formula and the Earth radius used here).
 * So screening measures the course in JS, and the SERVER still has the last word on every leg the
 * roster actually keeps: `verifyLeg` below runs voyage.path_refusal on the chosen loop exactly as
 * cmd.do_sail calls it from a quay, and a course it refuses is not a route.
 */
function plotLeg(a, b) {
  const key = `${a}>${b}`
  if (plotCache.has(key)) return plotCache.get(key)
  const A = ports.get(a), B = ports.get(b)
  pathCalls += 1
  const tP = Date.now()
  const r = findPath(nav, { lat: A.rlat, lon: A.rlon }, { lat: B.rlat, lon: B.rlon })
  pathMs += Date.now() - tP
  let out
  if (!r) { pathFails += 1; out = { err: 'THE pathfinder cannot plot it' } }
  else {
    const course = r.path.map(([lat, lon]) => [Number(lat.toFixed(4)), Number(lon.toFixed(4))])
    let nm = 0
    for (let i = 1; i < course.length; i++) nm += gc(course[i - 1][0], course[i - 1][1], course[i][0], course[i][1])
    // A COURSE OF NO LENGTH IS NOT A LEG. voyage.path_refusal calls it E_BAD_PATH, and it happens
    // where two berths share a roadstead (Basra and Bushehr on the Shatt al-Arab). Caught here, in
    // the screening, so it costs a candidate instead of a whole route.
    out = course.length < 2 || nm < 1 ? { err: 'the course has no length' } : { course, nm }
  }
  plotCache.set(key, out)
  return out
}

/** The SERVER's own verdict on the plotted course, as cmd.do_sail asks for it from a quay. */
async function verifyLeg(a, b) {
  const key = `${a}>${b}`
  if (verifyCache.has(key)) return verifyCache.get(key)
  const p0 = plotLeg(a, b)
  let out
  if (p0.err) out = p0
  else {
    const A = ports.get(a), B = ports.get(b)
    verifyCalls += 1
    const chk = await one(db0, `
      select voyage.path_refusal($1::jsonb, $2::numeric, $3::numeric, $4::numeric, $5::numeric,
                                 public.wc_num('course_join_nm'), 25, 25) as refusal,
             (select sum((s->>'nm')::numeric) from jsonb_array_elements(voyage.segments_from_course($1::jsonb)) s)::float8 as nm`,
      [JSON.stringify(p0.course), A.rlat, A.rlon, B.rlat, B.rlon])
    out = chk.refusal ? { err: `the server refuses the course: ${chk.refusal}` } : { course: p0.course, nm: chk.nm }
  }
  verifyCache.set(key, out)
  return out
}

/** 0098's checkLoop, with 0097's crew floor added to the quay test. */
async function checkLoop(stops, className, hulls) {
  const c = classes.get(className)
  const crew = hulls * c.crew_required
  const why = []
  if (stops.length < 2 || stops.length > STOP_MAX) why.push(`a loop of ${stops.length} stops is outside 2..${STOP_MAX}`)
  if (new Set(stops).size !== stops.length) why.push('a harbour is repeated in the loop')
  for (const s of stops) {
    const p = ports.get(s)
    if (!p) { why.push(`no place ${s}`); continue }
    if (p.kind !== 'HARBOUR') why.push(`${s} is not a HARBOUR`)
    if (c.draft > p.max_draft) why.push(`${s} takes draft ${p.max_draft}, a ${className} draws ${c.draft}`)
    if (p.crew_pool < CREW_FLOOR + 0.2 * crew) why.push(`${s}'s quay holds ${p.crew_pool}, under the floor ${CREW_FLOOR} plus a fifth of ${crew}`)
    if (!Number.isFinite(p.rlat)) why.push(`${s} is served no roadstead`)
  }
  const legs = []
  if (!why.length) {
    for (let i = 0; i < stops.length; i++) {
      const a = stops[i], b = stops[(i + 1) % stops.length]
      const L = await verifyLeg(a, b)
      if (L.err) why.push(`${a}→${b}: ${L.err}`)
      else legs.push({ from: a, to: b, nm: L.nm, course: L.course })
    }
  }
  return { stops, legs, why }
}

// ══ 4. THE ROUTES ═════════════════════════════════════════════════════════════════════════════
//
// LENGTH. 0101 made standing_route_stop_max 8 (owner row 122a) and the whole range is authored
// with a real spread: today 69 of 76 routes are 3 stops, which is exactly why the world looks the
// same everywhere. Short coastal runs are common, 7-8 stop carreiras rare.
const LEN_MIX = [[2, 0.20], [3, 0.24], [4, 0.20], [5, 0.14], [6, 0.10], [7, 0.07], [8, 0.05]]
// THE NEXT STOP, scored. The gradient is the game; the hop target is what makes a coastal run a
// coastal run and a carreira a carreira; the region bonus answers the owner's own complaint,
// "there are no trades seen between different continents".
const HOP_NM = { 2: 420, 3: 520, 4: 760, 5: 1500, 6: 2100, 7: 2900, 8: 3400 }
const FAR_NM = 2500            // "a long way from home", for a loop of five stops or more
const W_GRAD = 1.00, W_HOP = 0.85, W_REGION = 0.55, W_SPREAD = 0.40, W_JITTER = 0.18
const DETOUR_MAX = 1.8          // sailed nm ÷ great-circle nm, above which the two ends are in different basins
const DETOUR_FLOOR_NM = 600     // under which the ratio is meaningless (a river mouth, a strait)

function gradient(fromCode, toCode) {
  const offers = OFFERS.get(fromCode)
  const dest = AFF.get(toCode)
  if (!offers || !dest) return 0
  const toCult = ports.get(toCode).culture
  let best = 0
  for (const [g, a] of offers) {
    const gd = goods.get(g)
    if ((gd.culture_mask ?? []).includes(toCult)) continue   // they will not trade it at the far end
    const d = (dest.get(g) ?? a) - a
    if (d > best) best = d
  }
  return best
}

/** Every good this loop can actually trade, by its own ports' affinities and cultures. */
function tradeGoods(stops) {
  const out = []
  const seen = new Set()
  for (const s of stops) for (const [g] of OFFERS.get(s) ?? []) seen.add(g)
  for (const g of seen) {
    const gd = goods.get(g)
    let lo = null, hi = null
    for (const s of stops) {
      if ((gd.culture_mask ?? []).includes(ports.get(s).culture)) continue
      const a = AFF.get(s)?.get(g)
      if (a == null) continue
      if (!lo || a < lo.a) lo = { s, a }
      if (!hi || a > hi.a) hi = { s, a }
    }
    if (!lo || !hi || lo.s === hi.s) continue
    if (lo.a >= 0.99) continue
    const grad = hi.a - lo.a
    if (grad < 0.25) continue
    out.push({ good: g, name: gd.name, from: lo.s, to: hi.s, from_aff: lo.a, to_aff: hi.a, gradient: Number(grad.toFixed(3)) })
  }
  out.sort((a, b) => b.gradient - a.gradient || a.good.localeCompare(b.good))
  return out
}

/** The hull a route wants: a long leg wants a nau, a coastal run a barca. Hulls 1-3 (owner row 120). */
function classFor(len, longestNm) {
  if (longestNm >= 2200 || len >= 6) return 'nau'
  if (longestNm >= 600 || len >= 4) return 'carlat'
  return 'barca'
}

// HOME PORTS. The same linear rule, one level down: a nation's routes are allotted to its harbours
// in proportion to each harbour's own (dev_commerce + dev_industry). Seville hosts more than
// Sanlucar, and 56 Castilian routes do not all sail from one quay — which is also what keeps a
// quay's crew_pool (it never regenerates) from being drawn flat by its own nation's merchants.
function homePortsFor(nationCode, nRoutes) {
  const hs = [...nationHarbours.get(nationCode)].sort((a, b) => devOf(b) - devOf(a) || a.code.localeCompare(b.code))
  const tot = hs.reduce((a, p) => a + devOf(p), 0)
  const want = hs.map((p) => ({ p, exact: (devOf(p) / tot) * nRoutes }))
  const outs = want.map((w) => ({ p: w.p, n: Math.floor(w.exact), frac: w.exact - Math.floor(w.exact) }))
  let short = nRoutes - outs.reduce((a, o) => a + o.n, 0)
  for (const o of [...outs].sort((a, b) => b.frac - a.frac || a.p.code.localeCompare(b.p.code))) {
    if (short <= 0) break
    o.n += 1; short -= 1
  }
  // round-robin, so a nation's routes alternate between its quays rather than filling one first
  const list = []
  for (let pass = 0; list.length < nRoutes; pass++) {
    let moved = false
    for (const o of outs) if (o.n > pass) { list.push(o.p.code); moved = true; if (list.length === nRoutes) break }
    if (!moved) break
  }
  while (list.length < nRoutes) list.push(hs[0].code)
  return list
}

// Lengths, dealt so each nation gets a spread and the world-wide mix is the authored one.
function lengthsFor(nationCode, nRoutes) {
  const r = rng(`len|${nationCode}`)
  const bag = []
  for (const [len, w] of LEN_MIX) {
    const k = nRoutes * w
    for (let i = 0; i < Math.floor(k); i++) bag.push(len)
    if (r() < k - Math.floor(k)) bag.push(len)
  }
  while (bag.length < nRoutes) bag.push(LEN_MIX[Math.floor(r() * 3)][0])   // top up from the short end
  bag.length = nRoutes
  // deterministic shuffle, so a nation's long route is not always its last
  for (let i = bag.length - 1; i > 0; i--) { const j = Math.floor(r() * (i + 1)); [bag[i], bag[j]] = [bag[j], bag[i]] }
  return bag.sort((a, b) => a - b).map((_, i, arr) => arr[(i * 7 + 3) % arr.length])
}

const stopUse = new Map()     // how many loops already call at a harbour — spread the roster
const bump = (c) => stopUse.set(c, (stopUse.get(c) ?? 0) + 1)

async function growRoute(nationCode, idx, len, home, className, attempt = 0) {
  const c = classes.get(className)
  const crew = c.crew_required            // one hull for the legality test; hulls are added later
  const r = rng(attempt ? `${nationCode}|${idx}|try${attempt}` : `${nationCode}|${idx}`)
  const H = ports.get(home)
  const target = HOP_NM[len]
  const long = len >= 5
  const stops = [home]
  const regions = new Set([H.region])
  let farthest = 0
  const legal = (p) => p.kind === 'HARBOUR' && Number.isFinite(p.rlat) && c.draft <= p.max_draft &&
                       p.crew_pool >= CREW_FLOOR + 0.2 * crew
  for (let k = 1; k < len; k++) {
    const last = ports.get(stops.at(-1))
    // THE ONE FORCED STEP on a long loop: somewhere on a five-stop-or-more loop she must call at a
    // harbour FAR from home and in another region. Forced by construction at k = 2 rather than
    // hoped for, so the owner's "no trades between different continents" cannot come back.
    const forceFar = long && k === 2 && farthest < FAR_NM * 1.01
    const cands = []
    for (const p of HARBOURS) {
      if (stops.includes(p.code) || !legal(p)) continue
      const dHome = havPort(H, p)
      if (forceFar && (dHome < FAR_NM * 1.01 || dHome > 6000 || regions.has(p.region))) continue
      const d = hav(last, p)
      if (d < 40) continue
      // A CANDIDATE FAR OUTSIDE THE LOOP'S OWN HOP TARGET IS NOT A CANDIDATE. Without this a
      // two-stop coastal run wandered 2,514 nm and was then refused by the whole-loop cap, which
      // threw away the route instead of the stop.
      if (!forceFar && d > 2.4 * target) continue
      const grad = gradient(last.code, p.code) / 2.75
      const hopFit = 1 / (1 + Math.abs(Math.log(Math.max(d, 1) / target)))
      const newRegion = long && !regions.has(p.region) ? 1 : 0
      const spread = Math.min(1, (stopUse.get(p.code) ?? 0) / 10)
      cands.push({ p, d, dHome, score: W_GRAD * grad + W_HOP * hopFit + W_REGION * newRegion - W_SPREAD * spread + W_JITTER * r() })
    }
    if (!cands.length) return { why: [`${nationCode}|${idx}: no legal ${className} candidate for stop ${k}${forceFar ? ' (the forced far call)' : ''}`] }
    cands.sort((a, b) => b.score - a.score)
    let picked = null
    for (const cd of cands.slice(0, 8)) {
      const L = plotLeg(stops.at(-1), cd.p.code)
      if (L.err) continue
      // a leg that sails far further than the straight line is a leg across a landmass
      if (L.nm > Math.max(DETOUR_FLOOR_NM, DETOUR_MAX * hav(last, cd.p))) continue
      // and the LAST stop owes a sane way home, or the loop closes with a leg nobody laid
      if (k === len - 1) {
        const back = plotLeg(cd.p.code, home)
        if (back.err || back.nm > Math.max(DETOUR_FLOOR_NM, DETOUR_MAX * hav(cd.p, H))) continue
      }
      picked = cd; break
    }
    if (!picked) return { why: [`${nationCode}|${idx}: no leg from ${stops.at(-1)} to any of the eight best stop-${k} candidates is water a merchant would sail`] }
    stops.push(picked.p.code)
    regions.add(picked.p.region)
    farthest = Math.max(farthest, picked.dHome)
  }
  const chk = await checkLoop(stops, className, 1)
  if (chk.why.length) return { why: chk.why.map((w) => `${nationCode}|${idx} [${stops.join(' ')}]: ${w}`) }
  const totalNm = chk.legs.reduce((a, l) => a + l.nm, 0)
  const nmCap = 3.0 * len * HOP_NM[len]
  if (totalNm > nmCap) {
    return { why: [`${nationCode}|${idx} [${stops.join(' ')}]: ${Math.round(totalNm)} nm for a ${len}-stop loop, over the ${Math.round(nmCap)} nm a loop of that length may run`] }
  }
  if (long && (regions.size < 2 || farthest < FAR_NM * 1.01)) {
    return { why: [`${nationCode}|${idx} [${stops.join(' ')}]: a loop of ${len} takes in ${regions.size} region(s), farthest ${Math.round(farthest)} nm — a long loop owes two regions and ${FAR_NM} nm`] }
  }
  for (const s of stops) bump(s)
  return { stops, legs: chk.legs, regions: [...regions], farthest, len }
}

say(`\n== building ${[...routesOf.values()].reduce((a, b) => a + b, 0)} routes …`)
const routes = []
for (const [n] of shareOrder) {
  const nR = routesOf.get(n)
  const homes = homePortsFor(n, nR)
  const lens = lengthsFor(n, nR)
  for (let i = 0; i < nR; i++) {
    const want = Math.max(2, Math.min(STOP_MAX, lens[i]))
    let built = null
    const why = []
    // THE AUTHORED LENGTH IS TRIED FIRST, then shorter ones: a loop nobody can lay out of this
    // harbour is still a fleet the derivation has promised that nation, and the migration asserts
    // the count against public.ports. Each (length, class) gets three different draws — the jitter
    // is seeded from (nation, index, attempt), so the retry is a different route and not the same
    // one again, and it is still reproducible.
    outer:
    for (const len of [want, ...(want > 3 ? [want - 2, 3, 2] : want > 2 ? [2] : [])]) {
      const order = len >= 6 ? ['nau', 'carlat', 'barca'] : len >= 4 ? ['carlat', 'nau', 'barca'] : ['barca', 'carlat']
      for (let attempt = 0; attempt < 3; attempt++) for (const cn of order) {
        const g = await growRoute(n, i, len, homes[i], cn, attempt)
        if (!g.why) { built = { ...g, className: cn }; break outer }
        if (attempt === 0 && len === want) why.push(...g.why)
      }
    }
    if (!built) { refusals.push(`${n}|${i} (home ${homes[i]}, ${want} stops): ${why.join('; ')} — no shorter loop and no other class could be laid from this harbour either`); continue }
    // the class is re-read off the loop she actually got, then held to what every stop can take
    const longest = Math.max(...built.legs.map((l) => l.nm))
    let cn = classFor(built.len, longest)
    const fits = (x) => built.stops.every((s) => classes.get(x).draft <= ports.get(s).max_draft)
    if (!fits(cn)) cn = fits('carlat') ? 'carlat' : 'barca'
    if (routes.length % 10 === 0) {
      say(`   … ${routes.length} routes, ${plotCache.size} legs plotted (${pathFails} with no water), ${verifyCache.size} verified by the server, ` +
          `${(pathMs / 1000).toFixed(0)} s in THE pathfinder, ${refusals.length} refusal(s) — ${el()}`)
    }
    routes.push({
      ord: routes.length + 1, nation: n, idx: i, home: homes[i], stops: built.stops, legs: built.legs,
      className: cn, len: built.stops.length, regions: built.regions, farthest: Math.round(built.farthest),
      nm: Math.round(built.legs.reduce((a, l) => a + l.nm, 0)), longest_nm: Math.round(longest),
      trade: tradeGoods(built.stops),
    })
    const rt = routes.at(-1)
    // HULLS 1-3 (owner row 120). A nau is 400 tuns and 60 hands, so she sails alone or in a pair;
    // the small classes group up where the gradient pays for it. A fact about the ROUTE, so the
    // home quay's crew budget can be settled below while the fleets are still only counts.
    const g0 = rt.trade[0]?.gradient ?? 0
    rt.hulls = rt.className === 'nau' ? (g0 > 1.1 ? 2 : 1) : g0 > 1.0 ? 3 : g0 > 0.6 ? 2 : 1
    rt.crew = rt.hulls * classes.get(rt.className).crew_required
  }
}
say(`   ${routes.length} routes built, ${refusals.length} refusal(s), ${pathCalls} pathfinder calls over ${plotCache.size} distinct legs (${(pathMs / 1000).toFixed(0)} s), ${verifyCalls} verified through voyage.path_refusal — ${el()}`)
for (const r of refusals.slice(0, 40)) say(`   REFUSED ${r}`)
if (refusals.length > 40) say(`   … and ${refusals.length - 40} more refusal(s) (all of them are in the generated JSON)`)
{
  const d = {}; for (const r of routes) d[r.len] = (d[r.len] ?? 0) + 1
  say(`   length distribution ${Object.entries(d).map(([k, v]) => `${k}:${v}`).join(' ')}`)
  const long = routes.filter((r) => r.len >= 5)
  say(`   of ${long.length} loops of five stops or more, ${long.filter((r) => r.regions.length >= 2).length} take in two regions or more; ` +
      `median farthest call ${long.length ? Math.round(long.map((r) => r.farthest).sort((a, b) => a - b)[Math.floor(long.length / 2)]) : 0} nm`)
  say(`   distinct harbours called at: ${new Set(routes.flatMap((r) => r.stops)).size} of ${HARBOURS.length}; ` +
      `unaligned harbours called at: ${new Set(routes.flatMap((r) => r.stops)).size ? [...new Set(routes.flatMap((r) => r.stops))].filter((c) => !ports.get(c).nation).length : 0}`)
}
if (!routes.length) { say('REFUSED: no route survived. Nothing to found.'); process.exit(1) }

// ══ 5. THE FLEETS AND THE COMPANIES ═══════════════════════════════════════════════════════════
// Several fleets share a route (760 / 220 ≈ 3.5) — what a trading nation does, and what makes the
// measurement affordable. Each fleet is ONE company, which is what a one-fleet merchant house is.
const usedNames = new Set(taken)
// THE NAME POOL, per nation. Every (pattern × family) and (pattern × place) rendering that FITS
// public.players' own 24-character check (0004:52) — built once, drawn from deterministically.
// Nothing is hand-authored per company; what is authored is the habit (scripts/roster/npc-names.mjs).
const namePool = new Map()
function poolFor(nationCode) {
  if (namePool.has(nationCode)) return namePool.get(nationCode)
  const N = NATIONS[nationCode]
  const places = [...new Set((nationHarbours.get(nationCode) ?? []).map((p) => p.name.split(/[ ,(]/)[0]))]
  const out = []
  for (const pat of N.patterns) {
    if (pat.includes('{family}')) for (const fam of N.family) {
      const nm = pat.replace('{family}', fam)
      if (nm.length <= NAME_MAX && nm.length >= 3) out.push({ nm, fam })
    }
    if (pat.includes('{place}')) for (const pl of places) {
      const nm = pat.replace('{place}', pl)
      if (nm.length <= NAME_MAX && nm.length >= 3) out.push({ nm, pl })
    }
  }
  namePool.set(nationCode, out)
  return out
}
/**
 * Draw a free name and a free SECOND SPELLING for it. When a nation's pool runs dry the name is
 * qualified by the house's own home coast ("Casa de Melo de Porto") and only then numbered — and
 * either way it is REFUSED rather than silently truncated if it cannot be made to fit 24.
 */
function composeName(nationCode, placeName, r) {
  const pool = poolFor(nationCode)
  if (!pool.length) throw new Error(`${nationCode}: no company name under ${NAME_MAX} characters is composable`)
  const tries = []
  const k0 = Math.floor(r() * pool.length)
  for (let i = 0; i < pool.length; i++) tries.push(pool[(k0 + i) % pool.length].nm)
  for (const base of [...tries]) {
    const q = `${base} de ${placeName}`
    if (q.length <= NAME_MAX) tries.push(q)
  }
  for (let n = 2; n <= 9; n++) for (const base of tries.slice(0, pool.length)) {
    const q = `${base} ${n}`
    if (q.length <= NAME_MAX) tries.push(q)
  }
  for (const name of tries) {
    if (usedNames.has(name)) continue
    const alt = altSpellings(name).find((a) => !usedNames.has(a))
    if (!alt) continue
    usedNames.add(name); usedNames.add(alt)
    return { name, alt }
  }
  throw new Error(`${nationCode}: every one of ${tries.length} composable names is taken`)
}

/** Fleets per route: the base share, with the routes whose gradient is widest carrying more. */
function fleetsPerRoute(nationCode) {
  const rs = routes.filter((r) => r.nation === nationCode)
  const want = fleetsOf.get(nationCode)
  if (!rs.length) return new Map()
  const weight = rs.map((r) => 1 + Math.min(1.2, (r.trade[0]?.gradient ?? 0)))
  const wTot = weight.reduce((a, b) => a + b, 0)
  const out = rs.map((r, i) => ({ r, exact: (weight[i] / wTot) * want }))
  const got = out.map((o) => ({ ...o, n: Math.max(1, Math.floor(o.exact)) }))
  let diff = want - got.reduce((a, o) => a + o.n, 0)
  const byFrac = [...got].sort((a, b) => (b.exact - b.n) - (a.exact - a.n) || a.r.ord - b.r.ord)
  for (const o of byFrac) { if (diff <= 0) break; o.n += 1; diff -= 1 }
  for (const o of [...byFrac].reverse()) { if (diff >= 0) break; if (o.n > 1) { o.n -= 1; diff += 1 } }
  return new Map(got.map((o) => [o.r.ord, o.n]))
}

const fleets = []
for (const [n] of shareOrder) {
  const per = fleetsPerRoute(n)
  const N = NATIONS[n]
  if (!N) { refusals.push(`${n}: no naming habit in scripts/roster/npc-names.mjs — the nation is skipped`); continue }
  const runs = RUN_WORDS[n]
  let seq = 0
  for (const route of routes.filter((r) => r.nation === n)) {
    const count = per.get(route.ord) ?? 1
    for (let j = 0; j < count; j++) {
      const r = rng(`house|${n}|${route.ord}|${j}`)
      const home = ports.get(route.home)
      const far = ports.get(route.stops.reduce((a, s) => (havPort(home, ports.get(s)) > havPort(home, ports.get(a)) ? s : a), route.stops[0]))
      const placeName = (r() < 0.5 ? home.name : far.name).split(/[ ,(]/)[0]
      const { name, alt } = composeName(n, placeName, r)
      const hulls = route.hulls
      const hullNames = []
      const pool = [...N.hulls]
      for (let h = 0; h < hulls; h++) hullNames.push(pool.splice(Math.floor(r() * pool.length), 1)[0])
      // HER OWN SHELF of the route's gradient list — her place in the queue decides where it
      // starts, so the houses on one loop do not all claim the same cargo (see the note above).
      const tg = route.trade
      const share = 8
      const mine = tg.length <= share ? tg
        : Array.from({ length: Math.min(share, tg.length) }, (_, i) => tg[(j * share + i) % tg.length])
      const named = mine.slice(0, Math.min(3, mine.length))
      const master = `${N.titles[Math.floor(r() * N.titles.length)]} ${N.given[Math.floor(r() * N.given.length)]} ${N.family[Math.floor(r() * N.family.length)]}`
      // THE BLURB names only what this loop can really trade, and npc_houses bands it 8..240
      // (0097:114), so the tail is budgeted FIRST and the lines then fill what is left.
      const tail = ` — under ${master}.`
      const room = 240 - tail.length
      const blurb = (() => {
        if (!named.length) return `Works the ${route.len}-port coast out of ${home.name}`.slice(0, room) + tail
        const byLeg = new Map()
        for (const t of named) {
          const k2 = `${t.from}>${t.to}`
          if (!byLeg.has(k2)) byLeg.set(k2, { from: t.from, to: t.to, names: [] })
          byLeg.get(k2).names.push(t.name.toLowerCase())
        }
        const parts = [...byLeg.values()].map((g) => {
          const list = g.names.length === 1 ? g.names[0]
            : `${g.names.slice(0, -1).join(', ')} and ${g.names.at(-1)}`
          return `${list} from ${ports.get(g.from).name} to ${ports.get(g.to).name}`
        })
        let body = parts[0].slice(0, room)
        for (let i = 1; i < parts.length; i++) { if ((body + '; ' + parts[i]).length > room) break; body += '; ' + parts[i] }
        return body[0].toUpperCase() + body.slice(1) + tail
      })()
      // ONE officer at most, and only where the run is worth a specialist: 760 fleets cannot each
      // sign three out of a 63-officer catalogue without every company paying for a crowd.
      const spec = route.className === 'nau' ? 'NAVIGATOR' : route.len >= 4 ? 'PURSER' : null
      const off = spec
        ? (officerPool.filter((o) => o.specialty === spec)
            .sort((a, b) => Number(route.stops.includes(b.home)) - Number(route.stops.includes(a.home)) ||
                            Number(b.nation === n) - Number(a.nation === n) || a.code.localeCompare(b.code))[0]?.code)
        : null
      seq += 1
      fleets.push({
        nation: n, route, company: name, alt_company: alt, master,
        blurb,
        blurb_goods: named.filter((t) => blurb.toLowerCase().includes(t.name.toLowerCase())).map((t) => t.good),
        wares: mine.map((t) => t.good),
        ink: INK[n], className: route.className, hulls, hullNames,
        fleetName: `${runs[Math.floor(r() * runs.length)]} ${far.name}`.slice(0, 24),
        officers: off ? [off] : [],
        patience: Number((0.08 + 0.20 * r()).toFixed(2)),   // npc_houses bands it 0.05..0.30 (0097:120)
        skills: route.className === 'nau' ? { NAVIGATION: 2, ACCOUNTING: 1 } : route.len >= 4 ? { ACCOUNTING: 1, HAGGLING: 1 } : { HAGGLING: 1 },
        days: Math.min(999, Math.max(3, Math.ceil(1.5 * Math.max(...route.legs.map((l) => l.nm / (classes.get(route.className).kn * 24)))))),
        crew: route.crew,
        nSeq: seq,
      })
    }
  }
}

// ROSTER ORDER IS STRATIFIED, and it has to be: npc_tend starts the first `npc_fleet_max` fleets
// BY ROSTER ORDER (0097:625) and pauses the rest 'dark'. A roster written nation by nation would
// make any cap an all-Castile world. So the order interleaves nations in proportion — any PREFIX
// of this roster is a proportional spread across nations and across loop lengths — which is also
// what makes the first N of it a fair measurement sample.
const perNation = new Map()
for (const f of fleets) perNation.set(f.nation, (perNation.get(f.nation) ?? 0) + 1)
const seenN = new Map()
for (const f of fleets) {
  const k = (seenN.get(f.nation) ?? 0)
  seenN.set(f.nation, k + 1)
  f.strat = (k + 0.5) / perNation.get(f.nation)
}
fleets.sort((a, b) => a.strat - b.strat || (fleetsOf.get(b.nation) - fleetsOf.get(a.nation)) || a.company.localeCompare(b.company))
fleets.forEach((f, i) => { f.ord = ROSTER_BASE + i + 1 })
{
  // A NATION THE DERIVATION OWES FLEETS MUST HAVE A ROUTE FOR THEM. The migration asserts every
  // nation's count against public.ports, so a quiet shortfall here is a migration that fails on
  // apply — Safavid Persia holds one harbour and her only loop was refused on the first build.
  const short = shareOrder.filter(([n]) => fleetsOf.get(n) > 0 && !routes.some((r) => r.nation === n)).map(([n]) => n)
  if (short.length) {
    say(`REFUSED: ${short.join(', ')} are owed fleets by the derivation and no route could be laid for them.`)
    say('         Nothing is emitted.')
    process.exit(1)
  }
}
say(`\n== ${fleets.length} fleets / ${fleets.length} companies over ${routes.length} routes ` +
    `(${(fleets.length / routes.length).toFixed(2)} fleets a route), ${fleets.reduce((a, f) => a + f.hulls, 0)} hulls — ${el()}`)
{
  const cd = {}; for (const f of fleets) cd[f.className] = (cd[f.className] ?? 0) + 1
  say(`   classes ${JSON.stringify(cd)}`)
  const got = new Map(); for (const f of fleets) got.set(f.nation, (got.get(f.nation) ?? 0) + 1)
  say(`   per nation, built vs derived: ${shareOrder.map(([n]) => `${n} ${got.get(n) ?? 0}/${fleetsOf.get(n)}`).join('  ')}`)
}

// WHAT A QUAY COSTS A MERCHANT, which is NOT what it was first written as. 0097's cmd.do_hire
// draws only the hands ABOVE npc_crew_pool_floor off a quay for a merchant and recruits the rest at
// crew_urgent_multiplier (2.5×) WITHOUT touching the pool, and it leaves `v_pool` alone either way:
// "the quays players hire from cannot be drained by 32 merchant fleets re-crewing ... and a
// merchant at a drained quay still sails, poorer." So a quay is a PRICE, not a budget a roster can
// overdraw — and the figure worth printing is how many fleets would ever have to pay the urgent
// rate, which is a fleet whose whole crew exceeds crew_pool - the floor at some stop.
const urgentAt = []
for (const f of fleets) for (const s2 of f.route.stops) {
  if (f.crew > ports.get(s2).crew_pool - CREW_FLOOR) urgentAt.push(`${f.company} at ${s2} (${f.crew} hands against ${ports.get(s2).crew_pool - CREW_FLOOR} at the normal rate)`)
}
const homeLoad = new Map()
for (const f of fleets) homeLoad.set(f.route.home, (homeLoad.get(f.route.home) ?? 0) + f.crew)
const worstHome = [...homeLoad].sort((a, b) => b[1] - a[1])[0]
say(`   quays: ${homeLoad.size} home quays, the busiest ${worstHome[0]} with ${worstHome[1]} hands homed on it ` +
    `(a figure, not a gate — crew_pool is not depleted by a merchant); ${urgentAt.length} fleet-stop pair(s) would ever pay the urgent rate` +
    (urgentAt.length ? `: ${urgentAt.slice(0, 5).join('; ')}` : ''))

const specOf = (f, extra = {}) => ({
  company: taken.has(f.company) ? f.alt_company : f.company,
  alt_company: f.alt_company,
  nation: f.nation,
  ink: f.ink,
  master: f.master,
  blurb: extra.blurb ?? f.blurb,
  capital: extra.capital ?? MEASURE_CAPITAL,
  patience: f.patience,
  wares: f.wares,
  skills: f.skills,
  roster_ord: f.ord,
  blurb_goods: f.blurb_goods,
  route_ord: f.route.ord,
  fleets: [{
    name: f.fleetName,
    roster_ord: f.ord,
    days: f.days,
    ships: f.hullNames.map((n) => ({ class: f.className, name: n })),
    officers: f.officers,
    route_ord: f.route.ord,
    stops: f.route.legs.map((l) => ({ port: l.from, course: l.course })),
  }],
})

// ══ 6. ON THE ONE EXECUTOR: FOUND, PLAN, DERIVE, TIME, SAIL ═══════════════════════════════════
const DARK_SQL = `
  update public.world_config set value = to_jsonb(0.0) where key = 'hazard_p_max';
  update public.world_config set value = 'true'::jsonb where key = 'standing_routes_enabled';`

/** Found the whole roster on a fresh image. Returns the db, kept open. */
async function foundAll(label, capitalOf = null) {
  const db = await freshDb()
  await db.exec(DARK_SQL)
  const t0 = Date.now()
  const failed = []
  for (const f of fleets) {
    const spec = specOf(f, capitalOf ? { capital: capitalOf(f) } : {})
    // the stops carry the course, exactly as the emitted migration will hand them over
    try { await db.query(`select public.npc_found($1::jsonb)`, [JSON.stringify(spec)]) }
    catch (e) { failed.push(`${spec.company}: ${e.message}`) }
  }
  const ms = Date.now() - t0
  say(`   ${label}: founded ${fleets.length - failed.length}/${fleets.length} companies in ${(ms / 1000).toFixed(0)} s ` +
      `(${(ms / fleets.length).toFixed(1)} ms a company), ${failed.length} failure(s)`)
  for (const x of failed.slice(0, 20)) say(`      FOUNDING FAILED ${x}`)
  return { db, failed, foundMs: ms }
}

say(`\n== founding the whole roster through public.npc_found (the one founding) …`)
const { db: dbA, failed: foundFailed, foundMs } = await foundAll('probe purse')
if (foundFailed.length) { say('REFUSED: the founding failed. Nothing is emitted.'); process.exit(1) }

// ── 6a. CAPITAL, DERIVED FROM THE SERVER'S OWN PLANNER ────────────────────────────────────────
// Not a guess and not a measurement: public.npc_plan is run ONCE PER ROUTE on the untouched market
// and the lines IT wrote are priced through world.quote, the one price authority. That is the
// outlay the world itself would ask of her on her first lap. The contention is real and kept: the
// planner refuses a (port, good) another merchant route already buys there, and the routes are
// planned in ROSTER ORDER, so a quay's best cargo goes to whoever the roster names first and the
// rest find something else or are laid up. Both arms are counted.
say(`\n== deriving capital: public.npc_plan once per route, in roster order, on the untouched market …`)
// npc_plan answers {enabled:false} and nothing else while the switch is off (0097:437), so the
// HARNESS turns the planner on through world_config — NOT through npc_traders_switch, which also
// runs npc_tend, and npc_tend ASSIGNS, and assigning sails. Nothing is emitted from this db.
await dbA.exec(`update public.world_config set value = 'true'::jsonb where key = 'npc_traders_enabled';`)
if (!(await one(dbA, `select public.npc_traders_on() as on`)).on) { say('REFUSED: the harness could not enable the planner'); process.exit(1) }
const planT0 = Date.now()
const routeIdOf = new Map(
  (await rows(dbA, `select nf.roster_ord, nf.route_id, nf.fleet_id, nf.player_id from public.npc_fleets nf`))
    .map((r) => [r.roster_ord, r]))
let planned = 0, laidUp = 0
for (const f of fleets) {
  const m = routeIdOf.get(f.ord)
  const res = await one(dbA, `select public.npc_plan(now(), $1::uuid) as j`, [m.route_id])
  if (res.j?.enabled !== true) { say(`REFUSED: npc_plan answered ${JSON.stringify(res.j)} — the planner is not running`); process.exit(1) }
  if ((res.j.planned ?? 0) > 0) planned += 1; else laidUp += 1
}
const planMs = Date.now() - planT0
say(`   ${planned} routes planned, ${laidUp} laid up for want of a cargo that pays — ` +
    `${(planMs / 1000).toFixed(0)} s for ${fleets.length} single-route plans (${(planMs / fleets.length).toFixed(0)} ms a route)`)

// the outlay of each route's dearest leg, priced by world.quote at the qty the planner wrote
const outlay = new Map(
  (await rows(dbA, `
    with per_leg as (
      select nf.roster_ord, l.stop_ord, sum(q.total)::numeric as leg_total
        from public.npc_fleets nf
        join public.standing_route_lines l on l.route_id = nf.route_id and l.kind = 'BUY' and l.qty > 0
        join public.standing_route_stops s on s.route_id = nf.route_id and s.ord = l.stop_ord
        cross join lateral world.quote(s.port_id, l.good_id, l.qty, 'buy', null, null) q
       group by nf.roster_ord, l.stop_ord
    )
    select roster_ord, max(leg_total)::float8 as biggest, sum(leg_total)::float8 as whole
      from per_leg group by roster_ord`)).map((r) => [r.roster_ord, r]))
const wageOf = new Map(
  (await rows(dbA, `select c.code, public.crew_wages(c.crew_required, false)::float8 as w from public.ship_classes c`))
    .map((r) => [r.code, r.w]))
function lapWages(f) {
  const c = classes.get(f.className)
  const nm = f.route.nm
  return wageOf.get(f.className) * f.hulls * (nm / (c.kn * 24))
}
function derivedCapital(f) {
  const o = outlay.get(f.ord)
  const biggest = o?.biggest ?? 0
  const cap = Math.max(1.5 * biggest, 1.5 * lapWages(f), 5000)
  return Math.ceil(cap / 1000) * 1000
}
for (const f of fleets) { f.capital = derivedCapital(f); f.derived_outlay = Math.round(outlay.get(f.ord)?.biggest ?? 0); f.lap_wages = Math.round(lapWages(f)) }
say(`   capital derived for ${fleets.length} companies: median ${(() => { const v = fleets.map((f) => f.capital).sort((a, b) => a - b); return v[Math.floor(v.length / 2)].toLocaleString() })()} ducats, ` +
    `range ${Math.min(...fleets.map((f) => f.capital)).toLocaleString()}–${Math.max(...fleets.map((f) => f.capital)).toLocaleString()}; ` +
    `${fleets.filter((f) => !f.derived_outlay).length} of them sized by the wage floor alone (their planner found no cargo)`)

// ── 6b. WHAT THE TICK COSTS AT THE NEW ROSTER ─────────────────────────────────────────────────
// npc_fleet_max is 120 today — the ceiling on how many merchant fleets may sail, and therefore the
// gate on this whole roster. Raising it is only honest with a number beside it: tick_arrivals runs
// EVERY MINUTE on pg_cron and npc_plan + npc_tend hourly, and the 0097 machinery was measured at
// ~21 fleets.
say(`\n== what the clock costs, measured at each ceiling (hazards off, the switch on) …`)
const tickCost = []
for (const cap of [Number(K.npc_fleet_max), OLD_FLEETS + Math.round(fleets.length / 2), OLD_FLEETS + fleets.length].filter((c, i, a) => a.indexOf(c) === i && (CEILINGS_ALL || i !== 1))) {
  const db = await freshDb()
  await db.exec(DARK_SQL)
  for (const f of fleets) await db.query(`select public.npc_found($1::jsonb)`, [JSON.stringify(specOf(f, { capital: f.capital }))])
  await db.query(`update public.world_config set value = to_jsonb($1::int) where key = 'npc_fleet_max'`, [cap])
  await db.query(`select setseed(0.4242)`)
  const sw = await one(db, `select public.npc_traders_switch(true) as j`)
  const sailing = Number((await one(db, `select count(*)::int n from public.standing_routes sr join public.players p on p.id = sr.player_id and p.is_npc where sr.fleet_id is not null and sr.paused_reason is null`)).n)
  // THE EMPTY MINUTE: what the job costs on a tick with no arrival due — which is 59 of every 60.
  const t1 = Date.now(); await db.query(`select public.tick_arrivals(now())`); const arrMs = Date.now() - t1
  // THE WORST MINUTE: every fleet at sea arrives inside one tick, settled in the job's ONE
  // transaction (0010:54). Nothing in the world makes them all due together, so this is an upper
  // bound and it is labelled one.
  const t1b = Date.now()
  const minute = await one(db, `select public.tick_arrivals(now() + interval '2 minutes') as j`)
  const arrMinuteMs = Date.now() - t1b
  const t1c = Date.now()
  const burst = await one(db, `select public.tick_arrivals(now() + interval '8 hours') as j`)
  const arrBurstMs = Date.now() - t1c
  const t2 = Date.now(); const pl = await one(db, `select public.npc_plan(now()) as j`); const planHourMs = Date.now() - t2
  const t3 = Date.now(); const te = await one(db, `select public.npc_tend(now()) as j`); const tendMs = Date.now() - t3
  const t4 = Date.now(); await db.query(`select world.sea_traffic()`); const trafMs = Date.now() - t4
  const t5 = Date.now()
  await db.query(`select world.sea_traffic(jsonb_build_object('south', 30, 'north', 46, 'west', -18, 'east', 2))`)
  const trafWinMs = Date.now() - t5
  const tr = await one(db, `select world.sea_traffic() as j`)
  tickCost.push({ npc_fleet_max: cap, started: Number(sw.j?.tend?.started ?? 0), sailing,
    tick_arrivals_idle_ms: arrMs,
    tick_arrivals_a_minute_on_ms: arrMinuteMs, tick_arrivals_a_minute_on_fleets: minute.j?.fleets_touched ?? null,
    tick_arrivals_burst_ms: arrBurstMs, tick_arrivals_burst_fleets: burst.j?.fleets_touched ?? null,
    npc_plan_hourly_ms: planHourMs, npc_tend_ms: tendMs,
    sea_traffic_whole_ms: trafMs, sea_traffic_window_ms: trafWinMs,
    sea_traffic_served: jsonLen(tr.j), sea_traffic_total: Number(tr.j?.total ?? 0), sea_traffic_omitted: Number(tr.j?.omitted ?? 0),
    planned: pl.j?.planned ?? null, laid_up: pl.j?.laid_up ?? null })
  say(`   npc_fleet_max ${String(cap).padStart(4)}: ${String(sailing).padStart(3)} routes running · tick_arrivals ` +
      `idle ${String(arrMs).padStart(5)} ms / a minute on ${String(arrMinuteMs).padStart(6)} ms (${minute.j?.fleets_touched ?? '?'} fleets) / ` +
      `8 h on ${String(arrBurstMs).padStart(6)} ms (${burst.j?.fleets_touched ?? '?'}) · ` +
      `npc_plan (hourly, all) ${String(planHourMs).padStart(6)} ms · npc_tend ${String(tendMs).padStart(5)} ms · ` +
      `sea_traffic whole ${String(trafMs).padStart(4)} ms serving ${tickCost.at(-1).sea_traffic_served}/${tickCost.at(-1).sea_traffic_total} ` +
      `(omitted ${tickCost.at(-1).sea_traffic_omitted}) · window 16°×20° ${trafWinMs} ms`)
  await db.close()
}
function jsonLen(j) { return Array.isArray(j?.fleets) ? j.fleets.length : 0 }
await dbA.close()

// ── 6c. THE SAMPLE THAT IS ACTUALLY SAILED ────────────────────────────────────────────────────
// The roster order is stratified, so capping npc_fleet_max at SAMPLE makes the server itself pick
// a proportional spread across nations and loop lengths — and the reading is then also the reading
// for "what does the world do at npc_fleet_max = SAMPLE". Every arrival is settled by voyage.settle
// (what tick_arrivals runs for a due fleet), the market drifts on its own 15-minute slots, the
// daily cap rolls at every game-day boundary and npc_plan + npc_tend run on the hour.
let sample = { skipped: true }
if (SAIL) {
  say(`\n== sailing 0105's routes for ${LAPS} laps through the one executor (npc_fleet_max set to ${OLD_FLEETS} + ${SAMPLE_SCOPE}) …`)
  const t0 = Date.now()
  const db = await freshDb()
  await db.exec(DARK_SQL)
  await db.exec(`update public.world_config set value = to_jsonb(0) where key = 'npc_laps_per_game_day';`)
  for (const f of fleets) await db.query(`select public.npc_found($1::jsonb)`, [JSON.stringify(specOf(f, { capital: f.capital }))])
  await db.query(`update public.world_config set value = to_jsonb($1::int) where key = 'npc_fleet_max'`, [OLD_FLEETS + SAMPLE_SCOPE])
  await db.query(`select setseed(0.4242)`)
  await one(db, `select public.npc_traders_switch(true) as j`)
  // 0098's ${OLD_FLEETS} fleets hold the first ${OLD_FLEETS} slots of npc_fleets.roster_ord, so the cap is set at
  // ${OLD_FLEETS} + SAMPLE and 0098's roster sails BESIDE the sample — which is what makes the market the
  // sample trades in a real one rather than an empty sea. Only 0105's own routes are reported.
  const live = await rows(db, `
    select nf.roster_ord, nf.fleet_id, nf.route_id from public.npc_fleets nf
      join public.standing_routes sr on sr.id = nf.route_id
     where sr.fleet_id is not null and sr.paused_reason is null
     order by nf.roster_ord`)
  const mine = live.filter((m) => m.roster_ord > ROSTER_BASE)
  say(`   ${mine.length} of 0105's routes started under the cap, beside ${live.length - mine.length} of 0098's — ` +
      `and ALL ${live.length} are driven, because a market nobody trades in is not the market the sample is measured against`)
  const realStart = Number((await one(db, `select extract(epoch from now())::float8 t`)).t)
  const st = new Map()
  const fleetState = (fid) => one(db, `
    select f.status, extract(epoch from f.busy_until)::float8 busy,
           (select extract(epoch from v.eta)::float8 from public.voyages v where v.fleet_id = f.id and v.status = 'SAILING') eta,
           (select extract(epoch from v.eta - v.departed_at)::float8 from public.voyages v where v.fleet_id = f.id and v.status = 'SAILING') dur,
           extract(epoch from now())::float8 now from public.fleets f where f.id = $1`, [fid])
  const schedule = async (s, depart) => {
    const x = await fleetState(s.fleet_id)
    if (x.status === 'SAILING') { s.next = depart + x.dur; s.kind = 'arrive'; s.eta = x.eta }
    else if (x.status === 'REPAIRING' && x.busy) { s.next = depart + Math.max(1, x.busy - x.now); s.kind = 'release'; s.busy = x.busy }
    else { s.next = null; s.kind = 'idle' }
  }
  for (const m of live) { const s = { ...m, closed: 0, lastStart: 0, lap1: null, sample: m.roster_ord > ROSTER_BASE }; st.set(m.roster_ord, s); await schedule(s, 0) }
  const samples = () => [...st.values()].filter((s) => s.sample)
  const merchantIds = `(select id from public.players where is_npc)`
  let S = 0, hour = 0, events = 0
  let day = Math.floor(realStart / GAME_DAY), slot = Math.floor(realStart / Number(K.drift_slot_seconds))
  const LIMIT = MAX_SIM_HOURS * 3600
  let budgetSpent = false
  for (;;) {
    if (Date.now() - t0 > SAMPLE_MINUTES * 60_000) { budgetSpent = true; break }
    let next = null
    for (const s of st.values()) if (s.next != null && (!next || s.next < next.next)) next = s
    // the clock stops when the SAMPLE is done; 0098's fleets are driven for the market's sake, not
    // for a reading, so they do not hold the loop open
    if (samples().every((s) => s.closed >= LAPS)) break
    const nextHour = (hour + 1) * 3600
    if (!next || next.next > nextHour) {
      if (nextHour > LIMIT) break
      S = nextHour; hour += 1
      await db.query(`select public.npc_plan(to_timestamp($1)), public.npc_tend(to_timestamp($1))`, [realStart + S])
      for (const s of st.values()) if (s.kind === 'idle') await schedule(s, S)
      continue
    }
    S = next.next
    const T = realStart + S
    if (Math.floor(T / GAME_DAY) !== day) { day = Math.floor(T / GAME_DAY); await db.query(`delete from public.trade_daily where player_id in ${merchantIds}`) }
    if (Math.floor(T / Number(K.drift_slot_seconds)) !== slot) { slot = Math.floor(T / Number(K.drift_slot_seconds)); await db.query(`select public.tick_market_drift(to_timestamp($1))`, [T]) }
    const before = next.closed
    if (next.kind === 'arrive') await db.query(`select voyage.settle($1::uuid, to_timestamp($2))`, [next.fleet_id, next.eta + 0.001])
    else await db.query(`select cmd.advance($1::uuid, to_timestamp($2))`, [next.fleet_id, next.busy + 0.001])
    events += 1
    next.closed = Number((await one(db, `select count(*)::int n from public.standing_route_laps where route_id = $1 and closed_at is not null`, [next.route_id])).n)
    let depart = S
    if (next.closed > before) {
      depart = Math.max(S, next.lastStart + GAME_DAY / Math.max(PACE, 1))
      next.lastStart = depart
      if (before === 0) next.lap1 = await lapOne(db, next)
    }
    // EVERY ROUTE STOPS AT LAPS, not only the sample. 0098's fleets are driven so the sample
    // trades in a real market, but a coastal loop closes a lap in about half an hour of simulated
    // time where a long carreira needs nineteen hours for four — so an unparked short loop lapped
    // on and on while the sample's longest route finished, and the harness spent its whole budget
    // settling arrivals nobody was measuring. Only the SAMPLE holds the clock open.
    if (next.closed >= LAPS) { next.next = null; next.kind = 'done'; continue }
    await schedule(next, depart)
  }
  const res = []
  for (const s of samples()) {
    const laps = await rows(db, `
      select lap_no, net::float8 net, wages::float8 wages, bought::float8 bought, sold::float8 sold
        from public.standing_route_laps where route_id = $1 and closed_at is not null order by lap_no`, [s.route_id])
    const judged = laps.filter((l) => l.lap_no >= 3 && l.lap_no <= LAPS)
    const mean = (xs) => (xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : null)
    const rr = await one(db, `select paused_reason from public.standing_routes where id = $1`, [s.route_id])
    const f = fleets.find((x) => x.ord === s.roster_ord)
    res.push({ roster_ord: s.roster_ord, company: f.company, nation: f.nation, loop: f.route.stops.join(' '),
      len: f.route.len, class: f.className, hulls: f.hulls, laps: laps.length,
      nets: laps.map((l) => Math.round(l.net)),
      measured_mean_net: judged.length ? Math.round(mean(judged.map((l) => l.net))) : null,
      measured_mean_wages: judged.length ? Math.round(mean(judged.map((l) => l.wages))) : null,
      measured_lap1_bought: laps[0] ? Math.round(laps[0].bought) : null,
      measured_lap1_biggest_leg: s.lap1 ? Math.round(Math.max(0, ...s.lap1.map((l) => l.buys.reduce((a, b) => a + b.total, 0)))) : null,
      derived_biggest_leg_outlay: f.derived_outlay, derived_capital: f.capital, derived_lap_wages: f.lap_wages,
      paused_reason: rr?.paused_reason ?? null })
  }
  const held = await one(db, `
    select (select count(*) from public.ledger where player_id in ${merchantIds})::int ledger,
           (select count(*) from public.events where player_id in ${merchantIds})::int events,
           (select count(*) from public.voyages v join public.fleets f on f.id = v.fleet_id where f.player_id in ${merchantIds})::int voyages`)
  await db.close()
  const unfinished = samples().filter((x) => x.closed < LAPS).length
  sample = { routes: res.length, laps_asked: LAPS, also_driven_from_0098: live.length - mine.length,
    stopped_on: budgetSpent ? `the ${SAMPLE_MINUTES}-minute wall-clock budget` : S / 3600 >= MAX_SIM_HOURS ? 'the simulated-hours budget' : 'every sample route closing its laps',
    sample_routes_short_of_their_laps: unfinished, sim_hours: Number((S / 3600).toFixed(2)), arrivals: events,
    wall_seconds: Math.round((Date.now() - t0) / 1000), merchant_rows: held, results: res }
  const withLaps = res.filter((r) => r.laps >= 1)
  const judged = res.filter((r) => r.measured_mean_net != null)
  say(`   ${events} arrivals over ${(S / 3600).toFixed(1)} simulated hours in ${sample.wall_seconds} s wall clock` +
      ` — stopped on ${sample.stopped_on}` + (unfinished ? `, ${unfinished} sample route(s) short of ${LAPS} laps` : '') + `; ` +
      `${withLaps.length} of ${res.length} closed at least one lap, ${judged.length} closed three`)
  if (judged.length) {
    const pass = judged.filter((r) => r.measured_mean_net > 0 && r.measured_mean_net >= MIN_NET_TO_WAGES * (r.measured_mean_wages ?? 0))
    say(`   ${pass.length} of ${judged.length} judged routes clear npc_min_net_to_wages (${MIN_NET_TO_WAGES} × wages)`)
  }
  // THE VALIDATION: does the DERIVED capital cover what a SAILED lap actually spent?
  const comp = withLaps.filter((r) => r.measured_lap1_biggest_leg > 0)
  if (comp.length) {
    const ratio = comp.map((r) => r.derived_capital / (1.5 * r.measured_lap1_biggest_leg)).sort((a, b) => a - b)
    const pc = (q) => ratio[Math.max(0, Math.min(ratio.length - 1, Math.floor(q * ratio.length)))]
    sample.validation = { compared: comp.length, under_1: ratio.filter((x) => x < 1).length,
      p10: Number(pc(0.1).toFixed(2)), median: Number(pc(0.5).toFixed(2)), p90: Number(pc(0.9).toFixed(2)) }
    say(`   VALIDATION derived capital ÷ 1.5 × the dearest single leg the sailed first lap actually bought ` +
        `(the same rule the derivation sizes on, so this is like for like): ` +
        `p10 ${sample.validation.p10}× · median ${sample.validation.median}× · p90 ${sample.validation.p90}× ` +
        `(${sample.validation.under_1} of ${comp.length} under 1×, i.e. the derivation under-funded her)`)
  }
}

/** 0098's own reading: the first lap's lines leg by leg, off the route-born orders before the lap
 *  closer prunes them. Copied in shape from scripts/build-npc-0098.mjs so the MEASURED per-leg
 *  outlay and the DERIVED one are the same quantity. */
async function lapOne(db, s) {
  const lap = await one(db, `select id from public.standing_route_laps where route_id = $1 and lap_no = 1`, [s.route_id])
  if (!lap) return null
  const ords = await rows(db, `select verb, raw_text, result from public.orders where route_lap_id = $1 and status = 'done' order by seq`, [lap.id])
  const stop0 = (await one(db, `select p.code from public.standing_route_stops st join public.ports p on p.id = st.port_id where st.route_id = $1 and st.ord = 0`, [s.route_id]))?.code
  const legs = []
  let at = stop0, buys = []
  for (const o of ords) {
    if (o.verb === 'BUY' && o.result?.good) buys.push({ good: o.result.good, qty: Number(o.result.qty), total: Number(o.result.total) })
    if (o.verb === 'SAIL') { const to = o.raw_text.trim().split(/\s+/).pop(); legs.push({ from: at, to, buys }); buys = []; at = to }
  }
  return legs
}

// ══ 7. THE OPENING FRAME ══════════════════════════════════════════════════════════════════════
// A player's company is founded at Lisbon (new_house) and the opening chart is at least 12° across
// (src/chart/chartView.ts), so that frame is where liveliness is judged.
const frameOf = (code) => { const p = ports.get(code); const hl = 6 * (844 / 390); return { lat0: p.lat - hl, lat1: p.lat + hl, lon0: p.lon - 6, lon1: p.lon + 6 } }
const crossing = (code) => { const fr = frameOf(code); return routes.filter((r) => r.legs.some((l) => l.course.some(([la, lo]) => la >= fr.lat0 && la <= fr.lat1 && lo >= fr.lon0 && lo <= fr.lon1))).length }
const lisbon = crossing('LIS')
say(`\n== the Lisbon opening frame: ${lisbon} of ${routes.length} new loops cross it`)
for (const n of [...nations.values()].filter((n) => n.capital_port_code && ports.has(n.capital_port_code))) {
  say(`   ${n.code} capital ${n.capital_port_code}: ${crossing(n.capital_port_code)} loop(s)`)
}
if (lisbon < 2) { say('REFUSED: the founding frame (Lisbon) is crossed by fewer than two merchant loops.'); process.exit(1) }

if (!EMIT) { say(`\n(--no-emit) ${el()}`); process.exit(0) }

// ══ 8. THE REVIEWABLE JSON ════════════════════════════════════════════════════════════════════
const generated = {
  about:
    `GENERATED by scripts/build-npc-0105.mjs on the applied 0001-${chainFiles.at(-1).slice(10, 14)} chain. Do not edit: re-run the build. ` +
    `docs/NPC_FLEET_SCALE.md slice C; owner rows 116, 118, 119, 122a. ` +
    `MEASURED means sailed through the one executor (npc_found → npc_traders_switch → voyage.settle at every ` +
    `arrival, npc_plan + npc_tend on the hour, tick_market_drift per slot, hazards off): that is the ${SAMPLE}-route ` +
    `SAMPLE in \`sample\` only. DERIVED means the server's own planner answered on the untouched market ` +
    `(public.npc_plan once per route, its lines priced through world.quote): that is every route's capital. ` +
    `What this build does NOT have, and 0098 did: a per-fleet measurement with the whole roster sailing for ` +
    `many laps. That interaction was always the deploy's soak (docs/NPC_TRADERS.md §5.1) and it is said here ` +
    `rather than quietly dropped.`,
  generated_on: new Date().toISOString().slice(0, 10),
  chain_through: chainFiles.at(-1),
  targets: { fleets: TARGET_FLEETS, routes: TARGET_ROUTES, sample: SAMPLE, laps: LAPS },
  share_formula: 'fleets(nation) = round(760 × Σ(ports.dev_commerce + ports.dev_industry) over that nation\'s HARBOURS ÷ Σ over all nations)',
  share: shareOrder.map(([n, v]) => ({ nation: n, name: nations.get(n).name, harbours: nationHarbours.get(n).length,
    dev_sum: v, share_pct: Number(((v / DEV_TOTAL) * 100).toFixed(3)), fleets_derived: fleetsOf.get(n),
    fleets_built: fleets.filter((f) => f.nation === n).length, routes_built: routes.filter((r) => r.nation === n).length })),
  dev_total: DEV_TOTAL,
  length_distribution: Object.fromEntries(Object.entries(routes.reduce((a, r) => ((a[r.len] = (a[r.len] ?? 0) + 1), a), {}))),
  refusals,
  founding_ms_per_company: Number((foundMs / fleets.length).toFixed(1)),
  plan_ms_per_route: Number((planMs / fleets.length).toFixed(1)),
  planner: { planned, laid_up: laidUp },
  tick_cost: tickCost,
  crew: {
    note: '0097 cmd.do_hire draws only the hands ABOVE npc_crew_pool_floor off a quay for a '
        + 'merchant and recruits the rest at crew_urgent_multiplier without touching the pool, and '
        + 'leaves crew_pool itself alone either way. So a quay is a PRICE to a merchant, not a '
        + 'budget a roster can overdraw. The per-STOP capacity rule (crew_pool >= floor + a fifth '
        + 'of the fleet) is what the migration asserts.',
    home_quays: homeLoad.size,
    busiest_home_quay: { port: worstHome[0], hands_homed: worstHome[1], crew_pool: ports.get(worstHome[0]).crew_pool },
    fleet_stop_pairs_paying_the_urgent_rate: urgentAt,
  },
  lisbon_frame_loops: lisbon,
  sample,
  routes: routes.map((r) => ({ ord: r.ord, nation: r.nation, home: r.home, loop: r.stops.join(' '), stops: r.len,
    class: r.className, nm: r.nm, longest_leg_nm: r.longest_nm, regions: r.regions, farthest_call_nm: r.farthest,
    fleets: fleets.filter((f) => f.route.ord === r.ord).length,
    trade: r.trade.slice(0, 6) })),
  roster: fleets.map((f) => ({ roster_ord: f.ord, company: f.company, alt_company: f.alt_company, nation: f.nation,
    master: f.master, fleet: f.fleetName, class: f.className, hulls: f.hulls, ships: f.hullNames,
    route_ord: f.route.ord, loop: f.route.stops.join(' '), stops: f.route.len, officers: f.officers,
    wares: f.wares, blurb: f.blurb, blurb_goods: f.blurb_goods, skills: f.skills, patience: f.patience,
    capital_derived: f.capital, derived_biggest_leg_outlay: f.derived_outlay, derived_lap_wages: f.lap_wages })),
}
await writeFile(OUT_JSON, JSON.stringify(generated, null, 1) + '\n', 'utf8')

// ══ 9. THE MIGRATION ══════════════════════════════════════════════════════════════════════════
// Courses are emitted ONCE PER ROUTE, not once per fleet. 3.5 fleets share a loop, so baking the
// polyline into every company's spec would be the same ~900 courses written three and a half times
// over; the founding reads the route's stops out of a second temp table by route_ord instead.
const routeRows = routes.map((r) => `  (${r.ord}, $c$${JSON.stringify(r.legs.map((l) => ({ port: l.from, course: l.course })))}$c$::jsonb)`).join(',\n')
const rosterRows = fleets.map((f, i) => {
  const s = specOf(f, { capital: f.capital })
  delete s.fleets[0].stops                    // supplied by the route table, below
  return `  (${i + 1}, ${f.route.ord}, $r$${JSON.stringify(s)}$r$::jsonb)`
}).join(',\n')
const lenDist = Object.entries(routes.reduce((a, r) => ((a[r.len] = (a[r.len] ?? 0) + 1), a), {})).sort((a, b) => a[0] - b[0])
const shareTable = shareOrder.map(([n, v]) =>
  `--   ${n}  ${nations.get(n).name.padEnd(18)} ${String(nationHarbours.get(n).length).padStart(2)} harbours  dev ${String(v).padStart(4)}  ` +
  `${((v / DEV_TOTAL) * 100).toFixed(2).padStart(5)} %  ${String(fleetsOf.get(n)).padStart(3)} derived  ` +
  `${String(fleets.filter((f) => f.nation === n).length).padStart(3)} built  ${String(routes.filter((r) => r.nation === n).length).padStart(2)} routes`).join('\n')
const tickTable = tickCost.map((t) =>
  `--   npc_fleet_max ${String(t.npc_fleet_max).padStart(4)}  ${String(t.sailing).padStart(3)} routes running  ` +
  `tick_arrivals ${String(t.tick_arrivals_a_minute_on_ms).padStart(5)} ms a minute on (${t.tick_arrivals_a_minute_on_fleets} fleets), ` +
  `${String(t.tick_arrivals_burst_ms).padStart(6)} ms if every one of them arrived at once  npc_plan (hourly) ${String(t.npc_plan_hourly_ms).padStart(6)} ms  ` +
  `npc_tend ${String(t.npc_tend_ms).padStart(5)} ms  sea_traffic ${String(t.sea_traffic_whole_ms).padStart(4)} ms serving ` +
  `${t.sea_traffic_served}/${t.sea_traffic_total}`).join('\n')
const CEILING = Number(opt('--ceiling', String(fleets.length + 100)))

const sql = `-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0105 — THE MERCHANTS ARE COUNTED BY THEIR COASTS        (GENERATED — do not edit by hand)
--        docs/NPC_FLEET_SCALE.md slice C. Owner rows 116 (three times the routes), 118 (ten times
--        the ships), 119 (rich nations carry more), 122a (2 to 8 stops, home again).
--        Generated by scripts/build-npc-0105.mjs on the applied 0001-${chainFiles.at(-1).slice(10, 14)} chain; the figures it
--        rests on are data/npc-roster.generated.json. Re-run the build to change anything here.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- WHAT IT DOES. Founds ${fleets.length} more merchant companies — ${fleets.length} fleets, ${fleets.reduce((a, f) => a + f.hulls, 0)} hulls, over ${routes.length} distinct
-- loops — each through public.npc_found (0097), the same door 0098's ${60} companies came through,
-- and raises npc_fleet_max from ${Number(K.npc_fleet_max)} to ${CEILING} so they may sail. Nothing sails between this
-- deploy and the owner's switch: npc_traders_enabled stays false and every route is saved, unassigned,
-- with its fleet docked at its home harbour.
--
-- ── 1. A NATION'S SHARE IS DERIVED, NEVER OPINIONATED (owner row 119) ───────────────────────────
--
--     fleets(nation) = round(${TARGET_FLEETS} × Σ(ports.dev_commerce + ports.dev_industry) over that nation's
--                            HARBOURS ÷ Σ of the same sum over all nations)
--
-- Linear in ONE authored quantity, monotone in wealth, and it needs no floor and no ceiling. The
-- formula is re-derived from the live tables in the self-assert below and every nation's fleet
-- count checked against it, so nobody can quietly hand their favourite nation a navy.
--
-- THE ALTERNATIVE WAS MEASURED AND REJECTED: (commerce+industry) × Σsize_tier multiplies two
-- quantities that BOTH grow with harbour count. It is quadratic in size, and it gave Castile 54 %
-- of the world's merchant marine against Safavid Persia's one hull. The sum above gives:
--
${shareTable}
--
-- ${HARBOURS.filter((p) => !p.nation).length} of the world's ${HARBOURS.length} harbours belong to no nation. A HOME port comes only from a nation's
-- own harbours; the unaligned ones are DESTINATIONS, which is also what they historically were.
--
-- ── 2. A ROUTE IS 2 TO 8 STOPS AND COMES HOME (owner row 122a, the law since 0101) ──────────────
--
-- Loop lengths built: ${lenDist.map(([k, v]) => `${k} stops ×${v}`).join(', ')}.
-- Before this file 69 of 76 loops in the world were THREE stops, which is why every coast looked
-- the same. Short coastal runs are common here and ${lenDist.at(-1)[0]}-stop carreiras rare, which is the shape a
-- trading world has. ${routes.filter((r) => r.len >= 5).length} loops call at five harbours or more, and EVERY ONE of them takes in
-- at least two REGIONS and calls at least ${FAR_NM} nm from home — forced at the third stop by
-- construction, not hoped for, because the owner's complaint was "there are no trades seen between
-- different continents". A stop may be any nation's harbour: trade is international and only the
-- HOME port is the company's own.
--
-- Every leg is real water, twice over: THE pathfinder (src/lib/sea) plots it from served roadstead
-- to served roadstead, and then the SERVER's own voyage.path_refusal refuses or passes it exactly
-- as cmd.do_sail calls it from a quay. The course is baked into standing_route_stops.course.
--
-- ── 3. WHAT WAS MEASURED AND WHAT WAS DERIVED — THE DIFFERENCE IS NOT GLOSSED ──────────────────
--
-- DERIVED, for every one of the ${routes.length} routes: capital. public.npc_plan — the server's OWN planner —
-- was run ONCE PER ROUTE on the untouched market, in roster order, and the BUY lines it wrote were
-- priced through world.quote, the one price authority. Capital is 1.5 × the dearest single leg's
-- outlay, floored at 1.5 × the loop's wages. ${planned} routes found a cargo that pays; ${laidUp} did not and are
-- sized by the wage floor alone — the planner refuses a (port, good) another merchant route already
-- buys there, so at ${(fleets.length / routes.length).toFixed(1)} fleets a loop the quay's best cargo goes to whoever the roster
-- names first and the rest must find something else. That contention is real and it is kept.
--
-- MEASURED, for ${sample.skipped ? 0 : sample.routes} routes: actually sailed, ${LAPS} laps, through the one executor — npc_found,
-- npc_traders_switch(true), voyage.settle at every arrival, tick_market_drift on its own 15-minute
-- slots, the daily cap rolled at every game-day boundary, npc_plan + npc_tend on the hour, hazards
-- off.${sample.skipped ? '' : ` ${sample.arrivals} arrivals over ${sample.sim_hours} simulated hours.`}
--
-- WHAT IS THEREFORE NOT KNOWN, said here rather than discovered later: there is no per-fleet
-- measurement of the whole roster over many laps. 0098 did that for 107 fleets and it took hours;
-- ${fleets.length} one by one does not fit in a day, let alone in a CI gate (docs/NPC_FLEET_SCALE.md §0 item 2).
-- What it gives up is the whole-roster market INTERACTION over a long soak — which was always the
-- deploy's job (docs/NPC_TRADERS.md §5.1), and the switch is still off when this file lands.
${sample.skipped || !sample.validation ? '--' : `--
-- THE DERIVATION WAS VALIDATED AGAINST THE SAMPLE. Derived capital ÷ what the sailed first lap
-- actually bought, over ${sample.validation.compared} sampled routes: p10 ${sample.validation.p10}×, median ${sample.validation.median}×, p90 ${sample.validation.p90}×, with
-- ${sample.validation.under_1} under 1× (under-funded). The floor of 1.5 is why the median sits where it does.`}
--
-- ── 4. WHAT THE CLOCK COSTS, MEASURED AT EACH CEILING ──────────────────────────────────────────
--
-- npc_fleet_max was ${Number(K.npc_fleet_max)}: the ceiling on how many merchant fleets may sail, and therefore the
-- gate on this whole roster. Raising a gate without a number beside it is how a world that cannot
-- be ticked gets shipped, so it was measured on the built image (PGlite, this machine, one
-- transaction a call, hazards off, the switch on):
--
${tickTable}
--
-- tick_arrivals runs EVERY MINUTE on pg_cron (0010) and npc_plan + npc_tend hourly inside
-- tick_reconcile. The figure that decides the ceiling is tick_arrivals, because it is the one with
-- a minute to finish in; the hourly pair has an hour.
--
-- sea_traffic is 0102's windowed read and it holds: the whole-world call is capped at
-- sea_traffic_max (${Number(K.sea_traffic_max)}) and owns up to what it left out, and a window costs what a window
-- should. ${Number(K.sea_traffic_max)} is kept: it is a CAP on one read, not a budget for the world, and at this roster
-- it is doing exactly the job 0102 built it for.
--
-- ── 5. THE NAMES ARE COMPOSED, NOT AUTHORED ────────────────────────────────────────────────────
--
-- ${fleets.length} hand-authored companies would be 20,000 lines of invented names nobody could check
-- (docs/NPC_FLEET_SCALE.md §2). scripts/roster/npc-names.mjs authors each nation's own naming
-- HABIT — "Casa de …", "Handelshaus …", "Kontor …", "… -ya", "Hong …" — over family and
-- given-name pools; the PLACE element is read off public.ports, so a house is named for a coast
-- the world actually has. Every draw is seeded from a hash of (nation, index), never
-- Math.random(), so the same chain builds the same roster twice. Each company's blurb names ONLY
-- goods its own loop can really trade — a stop that PRODUCES the good (affinity under 1) and
-- another, culture-willing stop that pays dearer for it — and that is re-derived from port_goods
-- in the self-assert rather than taken on trust.
--
-- ── 6. STRUCTURAL SELF-ASSERTS ONLY ────────────────────────────────────────────────────────────
-- Nothing below may fail on market luck in production (NO_SPAGHETTI §7C): the counts, the share
-- formula re-derived from the live tables, the books, every course against voyage.path_refusal as
-- cmd.do_sail calls it, harbours only, no harbour twice, the 2-8 law, two regions and a far call on
-- every long loop, draft (with a positive control), the quay floor, the blurbs against the real
-- affinity gradient (with a positive control), distinct names and hulls, and nothing assigned,
-- everyone docked at home, the switch OFF.
--
-- PRODUCTION NAMES. npc_found takes the second spelling when the first is taken and raises when
-- both are. Before deploying, re-run the build with --taken (production's company names) so this
-- file can never raise half-way through \`supabase db push\`.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 1. THE CEILING MOVES, WITH THE MEASUREMENT IN THE SENTENCE ───────────────────────────────
update public.world_config
   set value = to_jsonb(${CEILING}),
       description = '0105: the most merchant fleets that may sail at once, counted in npc_fleets.roster_ord '
                     'order (npc_tend pauses the rest "dark"). Raised from ${Number(K.npc_fleet_max)} for the ${fleets.length}-fleet roster 0105 '
                     'founds. MEASURED on the built image at this count: tick_arrivals ${tickCost.at(-1).tick_arrivals_a_minute_on_ms} ms a minute on with '
                     '${tickCost.at(-1).tick_arrivals_a_minute_on_fleets} fleets at sea (it runs every '
                     'minute), npc_plan ${tickCost.at(-1).npc_plan_hourly_ms} ms and npc_tend ${tickCost.at(-1).npc_tend_ms} ms (hourly). The roster order is '
                     'STRATIFIED across nations, so lowering this knob thins the world evenly instead of '
                     'leaving one nation''s flag on every hull.'
 where key = 'npc_fleet_max';

-- ── 2. THE ROUTES: ONE COPY OF EACH BAKED COURSE ─────────────────────────────────────────────
-- ${(fleets.length / routes.length).toFixed(2)} fleets share a loop, so the polyline is written once per ROUTE and the founding reads it
-- back by route_ord. Baking it into every company's spec would write the same ${verifyCache.size} courses over.
create temporary table npc_routes_0105 (route_ord int primary key, stops jsonb not null);
insert into npc_routes_0105 (route_ord, stops) values
${routeRows};

-- ── 3. THE ROSTER ────────────────────────────────────────────────────────────────────────────
create temporary table npc_roster_0105 (ord int primary key, route_ord int not null, spec jsonb not null);
insert into npc_roster_0105 (ord, route_ord, spec) values
${rosterRows};

-- ── 4. THE FOUNDING ──────────────────────────────────────────────────────────────────────────
do $$
declare
  r record;
begin
  for r in select * from npc_roster_0105 order by ord loop
    perform public.npc_found(jsonb_set(r.spec, '{fleets,0,stops}',
                                       (select stops from npc_routes_0105 where route_ord = r.route_ord)));
  end loop;
end $$;

-- ── SELF-ASSERT ──────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_n        int;
  v_fleets   int;
  v_hulls    int;
  v_bad      text[];
  v_pc       text[];
  v_dev      numeric;
  v_target   int := ${TARGET_FLEETS};
  v_base     int := ${ROSTER_BASE};
begin
  -- (a) THE COUNTS. Everything 0105 names is founded, and 0098's roster is untouched beside it.
  select count(*) into v_n from public.npc_houses where roster_ord > v_base;
  select count(*) into v_fleets from public.npc_fleets where roster_ord > v_base;
  select count(*) into v_hulls
    from public.ships s join public.npc_fleets nf on nf.fleet_id = s.fleet_id where nf.roster_ord > v_base;
  if v_n <> (select count(*) from npc_roster_0105)
     or v_fleets <> (select count(*) from npc_roster_0105)
     or v_hulls <> (select sum(jsonb_array_length(spec->'fleets'->0->'ships')) from npc_roster_0105) then
    raise exception '0105 self-assert FAIL: % companies, % fleets and % hulls founded for a roster of %',
      v_n, v_fleets, v_hulls, (select count(*) from npc_roster_0105);
  end if;
  if (select count(*) from public.npc_fleets where roster_ord <= v_base) <> ${OLD_FLEETS} then
    raise exception '0105 self-assert FAIL: the roster 0105 was built on top of is % fleets, not the ${OLD_FLEETS} it was generated against',
      (select count(*) from public.npc_fleets where roster_ord <= v_base);
  end if;

  -- (b) THE SHARE IS THE FORMULA'S, re-derived HERE from public.ports and public.nations rather
  --     than taken from the generator's word for it. Every nation, to the hull.
  select sum(p.dev_commerce + p.dev_industry) into v_dev
    from public.ports p where p.kind = 'HARBOUR' and p.nation_id is not null;
  select array_agg(format('%s: %s built, formula says %s', x.code, x.built, x.want)) into v_bad from (
    select n.code,
           (select count(*) from public.npc_houses h
              join public.players pl on pl.id = h.player_id
             where h.roster_ord > v_base and pl.nation_id = n.id) as built,
           round(v_target * (select sum(p.dev_commerce + p.dev_industry) from public.ports p
                              where p.kind = 'HARBOUR' and p.nation_id = n.id) / v_dev) as want
      from public.nations n
     where exists (select 1 from public.ports p where p.kind = 'HARBOUR' and p.nation_id = n.id)
  ) x where x.built <> x.want;
  if v_bad is not null then
    raise exception '0105 self-assert FAIL: a nation''s fleet count is not what the derivation says: %', v_bad;
  end if;
  -- POSITIVE CONTROL: the same test must SEE a nation whose count is wrong. Nudge the figure and
  -- read it back; the probe is arithmetic on a literal, so nothing in the world is touched.
  select array_agg(x.code) into v_pc from (
    select n.code,
           (select count(*) from public.npc_houses h join public.players pl on pl.id = h.player_id
             where h.roster_ord > v_base and pl.nation_id = n.id) + 1 as built,
           round(v_target * (select sum(p.dev_commerce + p.dev_industry) from public.ports p
                              where p.kind = 'HARBOUR' and p.nation_id = n.id) / v_dev) as want
      from public.nations n
     where exists (select 1 from public.ports p where p.kind = 'HARBOUR' and p.nation_id = n.id)
  ) x where x.built <> x.want;
  if coalesce(array_length(v_pc, 1), 0) <> (select count(*) from public.nations n
                                             where exists (select 1 from public.ports p where p.kind = 'HARBOUR' and p.nation_id = n.id)) then
    raise exception '0105 self-assert FAIL: the share test cannot see its positive control (% of % nations)',
      coalesce(array_length(v_pc, 1), 0), (select count(*) from public.nations);
  end if;
  -- AND A HOME PORT IS THE COMPANY'S OWN NATION'S HARBOUR.
  select array_agg(format('%s homes at %s', pl.company_name, po.code)) into v_bad
    from public.npc_houses h
    join public.players pl on pl.id = h.player_id
    join public.ports po on po.id = h.home_port_id
   where h.roster_ord > v_base and po.nation_id is distinct from pl.nation_id;
  if v_bad is not null then
    raise exception '0105 self-assert FAIL: a company homes outside its own nation: %', v_bad;
  end if;

  -- (c) THE BOOKS: each purse is its capital, and the ledger says so.
  select array_agg(pl.company_name) into v_bad
    from public.players pl join public.npc_houses h on h.player_id = pl.id
   where h.roster_ord > v_base and (pl.ducats <> h.capital or public.ledger_sum(pl.id) <> pl.ducats);
  if v_bad is not null then
    raise exception '0105 self-assert FAIL: purse <> capital or ledger <> purse for %', v_bad;
  end if;

  -- (d) EVERY COURSE PASSES THE SERVER'S OWN VERIFICATION, as cmd.do_sail calls it from a quay.
  select array_agg(format('%s %s→%s: %s', sr.name, a.code, b.code, x.refusal)) into v_bad
    from public.npc_fleets nf
    join public.standing_routes sr on sr.id = nf.route_id
    join public.standing_route_stops s on s.route_id = sr.id
    join public.standing_route_stops s2 on s2.route_id = sr.id
         and s2.ord = (s.ord + 1) % (select count(*) from public.standing_route_stops c where c.route_id = sr.id)
    join public.ports a on a.id = s.port_id
    join public.ports b on b.id = s2.port_id
    join public.sea_reaches ra on ra.port_id = a.id
    join public.sea_reaches rb on rb.port_id = b.id
    cross join lateral (select voyage.path_refusal(s.course, ra.roadstead_lat, ra.roadstead_lon,
                                                   rb.roadstead_lat, rb.roadstead_lon,
                                                   public.wc_num('course_join_nm'), 25, 25) as refusal) x
   where nf.roster_ord > v_base and x.refusal is not null;
  if v_bad is not null then
    raise exception '0105 self-assert FAIL: the server refuses merchant course(s): %', v_bad;
  end if;

  -- (e) THE SHAPE OF A LOOP: harbours only, none twice, 2 to standing_route_stop_max, home again.
  if exists (select 1 from public.npc_fleets nf
               join public.standing_route_stops s on s.route_id = nf.route_id
               join public.ports po on po.id = s.port_id
              where nf.roster_ord > v_base and po.kind <> 'HARBOUR') then
    raise exception '0105 self-assert FAIL: a merchant stop is not a harbour';
  end if;
  if exists (select 1 from public.npc_fleets nf
               join public.standing_route_stops s on s.route_id = nf.route_id
              where nf.roster_ord > v_base
              group by nf.route_id, s.port_id having count(*) > 1) then
    raise exception '0105 self-assert FAIL: a loop calls at one harbour twice';
  end if;
  select array_agg(format('%s has %s stops', sr.name, x.n)) into v_bad
    from public.npc_fleets nf
    join public.standing_routes sr on sr.id = nf.route_id
    cross join lateral (select count(*) as n from public.standing_route_stops s where s.route_id = sr.id) x
   where nf.roster_ord > v_base and (x.n < 2 or x.n > public.wc_int('standing_route_stop_max'));
  if v_bad is not null then
    raise exception '0105 self-assert FAIL: a loop is outside 2..%: %', public.wc_int('standing_route_stop_max'), v_bad;
  end if;
  if (select count(distinct x.n) from public.npc_fleets nf
        cross join lateral (select count(*) as n from public.standing_route_stops s where s.route_id = nf.route_id) x
       where nf.roster_ord > v_base) < 6 then
    raise exception '0105 self-assert FAIL: the roster authors fewer than six of the seven legal loop lengths — the world would look the same everywhere again';
  end if;

  -- (f) A LONG LOOP CROSSES A BORDER AND GOES A LONG WAY. Five stops or more owes two REGIONS and
  --     a call at least ${FAR_NM} nm from home: the owner's "there are no trades seen between different
  --     continents", made structural. The distance is the great-circle one, derived here.
  select array_agg(format('%s: %s region(s), farthest %s nm', sr.name, x.regions, round(x.far))) into v_bad
    from public.npc_fleets nf
    join public.standing_routes sr on sr.id = nf.route_id
    cross join lateral (
      select count(*) as n,
             count(distinct po.region_id) as regions,
             max(voyage.gc_distance_nm(h.lat::float8, h.lon::float8, po.lat::float8, po.lon::float8)) as far
        from public.standing_route_stops s
        join public.ports po on po.id = s.port_id
        join public.standing_route_stops s0 on s0.route_id = sr.id and s0.ord = 0
        join public.ports h on h.id = s0.port_id
       where s.route_id = sr.id) x
   where nf.roster_ord > v_base and x.n >= 5 and (x.regions < 2 or x.far < ${FAR_NM});
  if v_bad is not null then
    raise exception '0105 self-assert FAIL: a long loop stays at home: %', v_bad;
  end if;
  -- POSITIVE CONTROL: the very same predicate, asked of the SHORT loops, must name some of them.
  -- A test that passes every loop in the roster is a test that is not testing the rule — it would
  -- also pass a roster of 220 two-stop coastal hops, which is the world this file exists to end.
  select array_agg(sr.name) into v_pc
    from public.npc_fleets nf
    join public.standing_routes sr on sr.id = nf.route_id
    cross join lateral (
      select count(*) as n,
             count(distinct po.region_id) as regions,
             max(voyage.gc_distance_nm(h.lat::float8, h.lon::float8, po.lat::float8, po.lon::float8)) as far
        from public.standing_route_stops s
        join public.ports po on po.id = s.port_id
        join public.standing_route_stops s0 on s0.route_id = sr.id and s0.ord = 0
        join public.ports h on h.id = s0.port_id
       where s.route_id = sr.id) x
   where nf.roster_ord > v_base and x.n < 5 and (x.regions < 2 or x.far < ${FAR_NM});
  if coalesce(array_length(v_pc, 1), 0) < 1 then
    raise exception '0105 self-assert FAIL: the long-loop test cannot see its positive control — not one short loop in the roster fails it, so the test discriminates nothing';
  end if;

  -- (g) DRAFT, with its positive control: the same test must refuse a nau (draft 3) at Seville (2).
  create temporary table draft_probe_0105 (fleet text, draft numeric, max_draft numeric);
  insert into draft_probe_0105
  select 'probe: a nau at Seville', c.draft, po.max_draft
    from public.ship_classes c, public.ports po where c.code = 'nau' and po.code = 'SVQ';
  insert into draft_probe_0105
  select f.name,
         (select max(c.draft) from public.ships s join public.ship_classes c on c.id = s.class_id where s.fleet_id = f.id),
         (select min(po.max_draft) from public.standing_route_stops st join public.ports po on po.id = st.port_id
           where st.route_id = nf.route_id)
    from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id where nf.roster_ord > v_base;
  select array_agg(fleet) into v_pc from draft_probe_0105 where draft > max_draft and fleet like 'probe:%';
  select array_agg(fleet) into v_bad from draft_probe_0105 where draft > max_draft and fleet not like 'probe:%';
  if coalesce(array_length(v_pc, 1), 0) <> 1 then
    raise exception '0105 self-assert FAIL: the draft test cannot see its positive control';
  end if;
  if v_bad is not null then
    raise exception '0105 self-assert FAIL: a merchant fleet draws more than a stop takes: %', v_bad;
  end if;
  drop table draft_probe_0105;

  -- (h) THE QUAY: every stop can crew a fifth of the fleet back WITHOUT going under 0097's floor,
  --     which is stricter than 0098's rule because crew_pool never regenerates and this roster is
  --     ten times the size. And no home quay has more hands homed on it than it may ever hand out.
  select array_agg(format('%s at %s', f.name, po.code)) into v_bad
    from public.npc_fleets nf
    join public.fleets f on f.id = nf.fleet_id
    join public.standing_route_stops st on st.route_id = nf.route_id
    join public.ports po on po.id = st.port_id
   where nf.roster_ord > v_base
     and po.crew_pool < public.wc_int('npc_crew_pool_floor')
                        + 0.2 * (select sum(c.crew_required) from public.ships s
                                   join public.ship_classes c on c.id = s.class_id where s.fleet_id = f.id);
  if v_bad is not null then
    raise exception '0105 self-assert FAIL: a quay cannot crew its merchant back above the floor: %', v_bad;
  end if;
  -- AND NOT A BUDGET. There was very nearly a second test here, that Sigma crew of the fleets HOMED
  -- at a quay stays inside crew_pool minus the floor. It is withdrawn, because the premise is
  -- false and 0097 says so in the body that draws the hands: for a merchant only the hands ABOVE
  -- npc_crew_pool_floor come off the quay, the rest are recruited at crew_urgent_multiplier and
  -- take NOTHING off it, and v_pool itself is left alone -- "the quays players hire from cannot
  -- be drained by ... merchant fleets re-crewing, and a merchant at a drained quay still sails,
  -- poorer." A quay is a PRICE to a merchant, never a budget a roster can overdraw. The rule would
  -- also have refused a legal roster: Safavid Persia holds ONE harbour and every one of her fleets
  -- homes on it, so no spreading could ever have satisfied it.

  -- (i) NAMES, HULLS, NATIONS, INK.
  if exists (select 1 from public.npc_houses h join public.players pl on pl.id = h.player_id
              where h.roster_ord > v_base and pl.nation_id is null) then
    raise exception '0105 self-assert FAIL: a merchant company has no nation';
  end if;
  if exists (select 1 from public.ships s
               join public.npc_fleets nf on nf.fleet_id = s.fleet_id
              where nf.roster_ord > v_base
              group by s.player_id, lower(btrim(s.name)) having count(*) > 1) then
    raise exception '0105 self-assert FAIL: two hulls of one company share a name';
  end if;
  -- public.players already holds company_name UNIQUE, so counting distinct names would prove
  -- nothing. What is worth proving is that no company needed its SECOND spelling: npc_found falls
  -- back silently-but-for-a-notice (0097:284), and a file that quietly founded forty houses under
  -- their alternate names is a file whose --taken list was stale.
  select array_agg(r.spec->>'company') into v_bad
    from npc_roster_0105 r
   where not exists (select 1 from public.players pl where pl.company_name = r.spec->>'company');
  if v_bad is not null then
    raise exception '0105 self-assert FAIL: % company/companies were founded under their second spelling — re-run the build with --taken: %',
      array_length(v_bad, 1), v_bad[1:10];
  end if;

  -- (j) THE BLURBS NAME ONLY WHAT THE LOOP CAN REALLY TRADE. For every good a blurb names, some
  --     stop on that company's own loop must PRODUCE it (port_goods.affinity under 1, and its
  --     culture must handle it) and some OTHER culture-willing stop must pay dearer for it. The
  --     good's NAME must also actually appear in the blurb that was stored — case-folded, because
  --     the blurb is a SENTENCE: "pepper from Kochi to Lisbon", not "Pepper". 0098 could compare
  --     case-sensitively because it pasted goods.name in verbatim.
  select array_agg(format('%s: %s', r.spec->>'company', g.code)) into v_bad
    from npc_roster_0105 r
    cross join lateral jsonb_array_elements_text(r.spec->'blurb_goods') g(code)
    join public.goods gd on gd.code = g.code
    join public.npc_houses h on h.roster_ord = (r.spec->>'roster_ord')::int
    join public.npc_fleets nf on nf.roster_ord = (r.spec->>'roster_ord')::int
   where strpos(lower(h.blurb), lower(gd.name)) = 0   -- prose: "pepper from Kochi", not "Pepper"
      or not exists (
        select 1 from public.standing_route_stops s
          join public.ports po on po.id = s.port_id
          join public.port_goods pg on pg.port_id = po.id and pg.good_id = gd.id
         where s.route_id = nf.route_id and pg.affinity < 0.99
           and not (po.culture = any(gd.culture_mask)))
      or not exists (
        select 1 from public.standing_route_stops s
          join public.ports po on po.id = s.port_id
          join public.port_goods pg on pg.port_id = po.id and pg.good_id = gd.id
         where s.route_id = nf.route_id and not (po.culture = any(gd.culture_mask))
           and pg.affinity > (select min(pg2.affinity) from public.standing_route_stops s2
                                join public.port_goods pg2 on pg2.port_id = s2.port_id and pg2.good_id = gd.id
                                join public.ports po2 on po2.id = s2.port_id
                               where s2.route_id = nf.route_id and not (po2.culture = any(gd.culture_mask))));
  if v_bad is not null then
    raise exception '0105 self-assert FAIL: a blurb names a good its own loop cannot trade: %', v_bad;
  end if;
  -- POSITIVE CONTROL: the same test must refuse a good nobody on the loop produces. 'silver' is
  -- produced in the Americas and in Japan; ask it of a company whose loop touches neither, with a
  -- name the blurb cannot contain, and the test has to name it.
  select array_agg(pl.company_name) into v_pc
    from public.npc_fleets nf
    join public.players pl on pl.id = nf.player_id
    join public.goods gd on gd.code = 'silver'
   where nf.roster_ord > v_base
     and not exists (select 1 from public.standing_route_stops s
                       join public.port_goods pg on pg.port_id = s.port_id and pg.good_id = gd.id
                      where s.route_id = nf.route_id and pg.affinity < 0.99)
   limit 5;
  if coalesce(array_length(v_pc, 1), 0) < 1 then
    raise exception '0105 self-assert FAIL: the blurb test cannot see its positive control — every loop in the roster produces silver, which cannot be';
  end if;

  -- (k) NOTHING SAILS. No route assigned, every fleet docked at its own stop 0, no lines, switch off.
  if exists (select 1 from public.npc_fleets nf join public.standing_routes sr on sr.id = nf.route_id
              where nf.roster_ord > v_base and sr.fleet_id is not null)
     or exists (select 1 from public.npc_fleets nf
                  join public.fleets f on f.id = nf.fleet_id
                  join public.standing_route_stops st on st.route_id = nf.route_id and st.ord = 0
                 where nf.roster_ord > v_base and (f.status <> 'DOCKED' or f.port_id is distinct from st.port_id))
     or exists (select 1 from public.standing_route_lines l
                  join public.npc_fleets nf on nf.route_id = l.route_id where nf.roster_ord > v_base)
     or public.npc_traders_on() then
    raise exception '0105 self-assert FAIL: a merchant was left assigned, at sea, away from home, with lines, or the switch is on';
  end if;

  -- (l) THE CEILING MOVED, and it is big enough to let this roster sail.
  if public.wc_int('npc_fleet_max') <> ${CEILING} then
    raise exception '0105 self-assert FAIL: npc_fleet_max is %, expected ${CEILING}', public.wc_int('npc_fleet_max');
  end if;
  if public.wc_int('npc_fleet_max') < (select count(*) from public.npc_fleets) then
    raise exception '0105 self-assert FAIL: npc_fleet_max (%) is under the % fleets on the roster — some would never sail',
      public.wc_int('npc_fleet_max'), (select count(*) from public.npc_fleets);
  end if;

  raise notice '0105 self-assert ok: THE MERCHANTS ARE COUNTED BY THEIR COASTS. % more companies, % fleets, % hulls over ${routes.length} distinct loops, beside the 76 fleets 0098 founded. Every nation''s fleet count equals round(${TARGET_FLEETS} x its harbours'' dev_commerce + dev_industry / the world''s), re-derived here from public.ports (the test saw its positive control on all % nations), and every company homes at a harbour of its own nation. Every purse is its capital and its ledger; every course from a served roadstead passes voyage.path_refusal as cmd.do_sail calls it; harbours only, none twice in a loop, every loop 2 to % stops with at least six of the seven lengths used; every loop of five stops or more takes in two regions and calls at least ${FAR_NM} nm from home; no fleet draws more than a stop takes (the test refused its nau-at-Seville control); every quay can crew a fifth of its merchant back above npc_crew_pool_floor (and a quay is a PRICE to a merchant, not a budget — 0097 leaves crew_pool itself alone — so there is deliberately no test here that a home quay is not over-homed); every company has a nation, a name no other holds and no two hulls alike; every blurb names only goods its own loop produces at one stop and sells dearer at another (the test saw its positive control); nothing assigned, everyone docked at home with no lines, the switch OFF; npc_fleet_max raised to % with tick_arrivals measured at ${tickCost.at(-1).tick_arrivals_a_minute_on_ms} ms a minute on, ${tickCost.at(-1).tick_arrivals_a_minute_on_fleets} fleets at sea, at this count.',
    v_n, v_fleets, v_hulls,
    (select count(*) from public.nations n where exists (select 1 from public.ports p where p.kind = 'HARBOUR' and p.nation_id = n.id)),
    public.wc_int('standing_route_stop_max'), public.wc_int('npc_fleet_max');
end $$;
`
await writeFile(OUT_SQL, sql.replace(/\r\n/g, '\n'), 'utf8')
say(`\nwrote ${path.relative(REPO_ROOT, OUT_SQL)} (${(sql.length / 1024).toFixed(0)} KB) and ${path.relative(REPO_ROOT, OUT_JSON)} — ${el()}`)
process.exit(0)
