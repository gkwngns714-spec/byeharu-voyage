// build-sea-legs-migration.mjs: THE MIGRATION THAT SHIPS data/sea-legs.json (0442 is the first written this way). LOCAL; not in CI.
//
//   BYEHARU_PREFIX_CACHE=required node scripts/build-sea-legs-migration.mjs --before=0442 --name=<file name> [--courses=<file.json> --proof98]
//                                                                           [--reaches=<measure-reaches out.json>]
//   (--reaches: also re-ships the distances the quay quotes, public.sea_reaches.reaches, as the SAILED figures of
//   scripts/ops/harness/seas-memo/measure-reaches.mjs, and refills public.port_goods' haul from world.haul_rows(): a change to prices, measured
//   here before and after and written into the migration's header)
//
// Run it right after scripts/build-sea-legs.mjs --before=<same> [--courses=<file.json>] has written data/sea-legs.json. It:
//   1. restores the cached world at the head before the named migration (never from zero; the cache is only read);
//   2. writes supabase/migrations/<name> from scripts/sea-legs.sql.mjs: the whole file as its seed, guarded by the md5 of the harbours, roadsteads,
//      raster and sea boxes it was plotted on;
//   3. applies it to that world inside a transaction that is rolled back, so its self-assert runs and its header says what moved and how long it took;
//   4. writes scripts/ops/harness/seas-memo/after.sql and rollback-<tag>.sql (the rows as they were);
//   5. with --proof98 and --courses: rewrites the courses proof 98 holds (from Acapulco and from Sakai to every other harbour) from the same plot.
import { readFile, writeFile, mkdir } from 'node:fs/promises'
import path from 'node:path'
import { createHash } from 'node:crypto'
import { migrationSql, LAWS_SQL } from './sea-legs.sql.mjs'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, REPO_ROOT, migrationFiles, preambleVariant } from './db/apply-chain.mjs'
import { applyWithPrefixCache } from './db/prefix-cache.mjs'

const arg = (k) => process.argv.find((a) => a.startsWith(`--${k}=`))?.slice(k.length + 3)
const before = arg('before')
const name = arg('name')
if (!before || !name || name.slice(10, 14) !== before) throw new Error('usage: --before=0442 --name=20260818000442_<words>.sql [--courses=<file.json> --proof98]')
const md5 = (s) => createHash('md5').update(s).digest('hex')
const files = []
for (const f of await migrationFiles()) {
  if (f.slice(10, 14) >= before) continue
  files.push({ name: f, sql: await readFile(path.join(MIGRATIONS_DIR, f), 'utf8') })
}
const { db } = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: () => {}, required: true, snapshots: false })
const head = files.at(-1).name.slice(0, 14)
const one = async (sql) => (await db.query(sql)).rows[0]

const seedText = (await readFile(path.join(REPO_ROOT, 'data', 'sea-legs.json'), 'utf8')).trimEnd()
const seed = JSON.parse(seedText)
const world = await one(`select
  (select string_agg(p.code, ' ' order by p.code collate "C") from public.ports p where p.kind = 'HARBOUR') as harbours,
  md5((select string_agg(p.code || ':' || sr.roadstead_lat || ',' || sr.roadstead_lon, ' ' order by p.code collate "C")
         from public.ports p join public.sea_reaches sr on sr.port_id = p.id where p.kind = 'HARBOUR')) as roads,
  md5((select encode(r.cells, 'hex') from public.sea_raster r where r.id = 1)) as raster,
  md5((select string_agg(encode(c.zones, 'hex'), '' order by c.row_idx) from public.sea_zone_cells c)) as zones`)
if (world.harbours !== seed.harbours.join(' ')) throw new Error('data/sea-legs.json is not this world\'s harbours: run scripts/build-sea-legs.mjs first')
await db.exec(`create temp table seed_md5 as select $s$${seedText}$s$::jsonb as j`)
const seedMd5 = (await one(`select md5((s.j -> 'harbours')::text || (s.j -> 'sets')::text || (s.j -> 'legs')::text) as m from seed_md5 s`)).m
await db.exec('drop table seed_md5')
const laws = await one(LAWS_SQL)
const pre = (await db.query(`select a.code as a, b.code as b, s.wave_min, s.title_min, array_to_string(s.zones, ' ') as zones
                               from public.sea_leg_asks s join public.ports a on a.id = s.from_port join public.ports b on b.id = s.to_port`)).rows
const preOf = new Map(pre.map((r) => [`${r.a} ${r.b}`, r]))

// the quoted distances (--reaches), and what they do to the prices on this world
let reachIn = null
let reachPre = null
if (arg('reaches')) {
  const m = JSON.parse(await readFile(arg('reaches'), 'utf8')).sailed
  reachPre = (await db.query(`select sr.code, sr.reaches from public.sea_reaches sr order by sr.code collate "C"`)).rows
  if (reachPre.map((r) => r.code).join(' ') !== Object.keys(m).sort().join(' ')) throw new Error('the measured distances are not for this world\'s places')
  const rel = []
  let worst = { d: 0 }
  let pairs = 0
  for (const a of reachPre) for (const b of reachPre) {
    if (a.code >= b.code) continue
    pairs++
    const was = Number(a.reaches[b.code])
    const now = m[a.code][b.code]
    if (m[b.code][a.code] !== now) throw new Error(`${a.code}-${b.code}: two figures`)
    if (was === now) continue
    const d = (now - was) / was
    rel.push(Math.abs(d))
    if (Math.abs(d) > Math.abs(worst.d)) worst = { d, k: `${a.code}-${b.code}`, was, now }
  }
  rel.sort((x, y) => x - y)
  const q = (xs, p) => (xs.length ? xs[Math.min(xs.length - 1, Math.floor(p * xs.length))] : 0)
  const json = `{${Object.keys(m).sort().map((c) => `"${c}":${JSON.stringify(Object.fromEntries(Object.keys(m[c]).sort().map((k) => [k, m[c][k]])))}`).join(',\n')}}`
  reachIn = { json, pairs, moved: rel.length, median: (q(rel, 0.5) * 100).toFixed(2), p95: (q(rel, 0.95) * 100).toFixed(2), over5: rel.filter((x) => x > 0.05).length, worst,
    haulRows: 0, marketRows: 0, priceMedian: '0', priceP95: '0', priceP99: '0', priceOver2: 0, priceMax: '0' }
}
const haulSql = `select pg.port_id::text || ':' || pg.good_id::text as k, pg.haul::float8 as haul from public.port_goods pg`
const haulPre = reachIn ? new Map((await db.query(haulSql)).rows.map((r) => [r.k, r.haul])) : null

const worst = (r) => `${r.worst.k} ${r.worst.was} -> ${r.worst.now}`
const fill = (changed, ms) =>
  migrationSql({
    tag: before, head, prodNote: arg('prod-note') ?? 'see the PR',
    before: { lanes: laws.lanes ? laws.lanes.split(' ').length : 0, lanesList: laws.lanes ?? 'none' },
    harbours: seed.harbours.length, sets: seed.sets.length, harbourList: world.harbours, roadsMd5: world.roads, rasterMd5: world.raster, zonesMd5: world.zones,
    seed: seedText, seedMd5, changed, ms, reach: reachIn,
  })
// pass 1: apply, rolled back, to read what moves and how long it takes; pass 2: the same file with those figures in its header
const notices = []
let sql = fill({ zones: 0, asks: 0, more: 0, less: 0 }, 0)
const t0 = Date.now()
await db.exec('begin')
await db.exec(sql, { onNotice: (n) => notices.push(n.message) })
const ms = Date.now() - t0
const post = (await db.query(`select a.code as a, b.code as b, s.wave_min, s.title_min, array_to_string(s.zones, ' ') as zones
                                from public.sea_leg_asks s join public.ports a on a.id = s.from_port join public.ports b on b.id = s.to_port`)).rows
const after = await one(LAWS_SQL)
let reachesMd5 = null
if (reachIn) {
  const dp = []
  let mx = 0
  const rows = (await db.query(haulSql)).rows
  for (const r of rows) {
    const o = haulPre.get(r.k)
    if (o === r.haul) continue
    const d = r.haul / o - 1
    dp.push(Math.abs(d))
    if (Math.abs(d) > Math.abs(mx)) mx = d
  }
  dp.sort((x, y) => x - y)
  const q = (xs, p) => (xs.length ? xs[Math.min(xs.length - 1, Math.floor(p * xs.length))] : 0)
  Object.assign(reachIn, { haulRows: dp.length, marketRows: rows.length, priceMedian: (q(dp, 0.5) * 100).toFixed(3), priceP95: (q(dp, 0.95) * 100).toFixed(2),
    priceP99: (q(dp, 0.99) * 100).toFixed(2), priceOver2: dp.filter((x) => x > 0.02).length, priceMax: (mx * 100).toFixed(2) })
  reachesMd5 = (await one(`select md5(string_agg(sr.code || sr.reaches::text, ',' order by sr.code collate "C")) as m from public.sea_reaches sr`)).m
  console.log(`  the quoted distances: ${reachIn.moved} of ${reachIn.pairs} pairs move (median ${reachIn.median} %, p95 ${reachIn.p95} %, ${reachIn.over5} over 5 %, largest ${worst(reachIn)}); prices: ${reachIn.haulRows} of ${reachIn.marketRows} market rows, median ${reachIn.priceMedian} %, p95 ${reachIn.priceP95} %, p99 ${reachIn.priceP99} %, ${reachIn.priceOver2} over 2 %, largest ${reachIn.priceMax} %`)
}
await db.exec('rollback')
for (const n of notices) console.log('  ' + n)
if (after.own || after.lanes || after.asks) throw new Error(`after the migration the laws are not whole: ${JSON.stringify(after)}`)
const changed = { zones: 0, asks: 0, more: 0, less: 0 }
const moved = []
for (const r of post) {
  const o = preOf.get(`${r.a} ${r.b}`)
  if (r.zones !== o.zones) changed.zones++
  if (r.wave_min !== o.wave_min || r.title_min !== o.title_min) changed.asks++
  if (r.wave_min > o.wave_min || r.title_min > o.title_min) changed.more++
  if (r.wave_min < o.wave_min || r.title_min < o.title_min) changed.less++
  if (r.zones !== o.zones || r.wave_min !== o.wave_min || r.title_min !== o.title_min) moved.push(o)
}
sql = fill(changed, ms)
await writeFile(path.join(MIGRATIONS_DIR, name), sql)
console.log(`wrote supabase/migrations/${name} (${Math.round(sql.length / 1024)} KB): ${JSON.stringify(changed)} of ${post.length} rows, ${ms} ms here; before: own ${laws.own}, lanes ${laws.lanes}`)

// the prod check after, and the forward rollback
const H = path.join(REPO_ROOT, 'scripts', 'ops', 'harness', 'seas-memo')
await mkdir(H, { recursive: true })
await writeFile(
  path.join(H, 'after.sql'),
  `-- after.sql: READ ONLY on prod, one statement, AFTER ${before} (generated by scripts/build-sea-legs-migration.mjs: do not edit by hand).
-- Want head 20260818${before.padStart(6, '0')}, own null, lanes null, asks 0, fn 1, pairs ${post.length}${reachIn ? `, reaches_md5 ${reachesMd5}, haul_off 0 (world.haul_rows() is STABLE; about 4 s)` : ''}. STABLE functions only (public.npc_course_zones, public.harbour_zone).
begin transaction read only;
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'fn', (select count(*) from pg_proc p where p.oid = to_regprocedure('public.sea_leg_asks_keep()')),
  'pairs', (select count(*) from public.sea_leg_asks),
  'laws', (select to_jsonb(l) from (${LAWS_SQL.replace(/\n/g, '\n    ')}) l)${reachIn ? `,
  'reaches_md5', (select md5(string_agg(sr.code || sr.reaches::text, ',' order by sr.code collate "C")) from public.sea_reaches sr),
  'haul_off', (select count(*) from public.port_goods pg join world.haul_rows() h on h.port_id = pg.port_id and h.good_id = pg.good_id
                where (pg.haul_nm, pg.haul) is distinct from (h.haul_nm, h.haul))` : ''});
rollback;
`,
)
await writeFile(
  path.join(H, `rollback-${before}.sql`),
  `-- rollback-${before}.sql: the FORWARD rollback of ${before} (generated by scripts/build-sea-legs-migration.mjs: do not edit by hand). Cut it as the next migration if
-- the owner wants it undone: the ${moved.length} rows the chain's world saw move go back to what they held, and the function goes. (Rows only production
-- moved, for lanes the chain does not hold, keep the seas of their lanes: those were true.) data/sea-legs.json must go back with it.
-- A DRAFT that WRITES: it runs on a local PGlite world only while it carries the next line (the guard). To deploy it, strip that line. Owner only.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
update public.sea_leg_asks s set wave_min = v.w, title_min = v.t, zones = string_to_array(v.z, ' ')
  from (values
${moved.map((o) => `    ('${o.a}', '${o.b}', ${o.wave_min}, ${o.title_min}, '${o.zones}')`).join(',\n')}
  ) v(a, b, w, t, z), public.ports a, public.ports b
 where a.code = v.a and b.code = v.b and s.from_port = a.id and s.to_port = b.id;
drop function public.sea_leg_asks_keep();
${reachIn ? `-- the quoted distances as they were, and the prices derived from them
update public.sea_reaches sr set reaches = v.value from jsonb_each($was$${`{${reachPre.map((r) => `"${r.code}":${JSON.stringify(r.reaches)}`).join(',\n')}}`}$was$::jsonb) v where v.key = sr.code;
update public.port_goods pg set haul_nm = h.haul_nm, haul = h.haul
  from world.haul_rows() h where h.port_id = pg.port_id and h.good_id = pg.good_id and (pg.haul_nm, pg.haul) is distinct from (h.haul_nm, h.haul);
` : ''}`,
)
console.log(`wrote scripts/ops/harness/seas-memo/after.sql and rollback-${before}.sql (${moved.length} rows)`)

// proof 98's courses: from Acapulco and from Sakai to every other harbour, as this build plotted them
if (process.argv.includes('--proof98')) {
  const plot = JSON.parse(await readFile(arg('courses'), 'utf8'))
  if (plot.harbours.join(' ') !== seed.harbours.join(' ')) throw new Error('the courses file is not this build\'s')
  const rows = []
  for (const a of ['ACA', 'SAK']) {
    const i = plot.harbours.indexOf(a)
    plot.harbours.forEach((b, j) => {
      if (j !== i) rows.push(JSON.stringify([a, b, plot.courses[i][j]]))
    })
  }
  const file = path.join(REPO_ROOT, 'scripts', 'db', 'proofs', '98_trade_lists_a_passage_as_the_door_will_judge_it.sql')
  const text = await readFile(file, 'utf8')
  const a = text.indexOf('$fix$[\n')
  const b = text.indexOf('\n]$fix$')
  if (a < 0 || b < 0 || text.indexOf('$fix$[\n', a + 1) >= 0) throw new Error('proof 98: the courses block is not where it was')
  await writeFile(file, text.slice(0, a + 7) + rows.join(',\n') + text.slice(b))
  console.log(`proof 98: ${rows.length} courses rewritten`)
}
await db.close()
process.exit(0)
