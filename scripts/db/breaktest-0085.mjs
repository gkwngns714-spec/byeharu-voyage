// ═══════════════════════════════════════════════════════════════════════════════════════════════
// breaktest-0085.mjs — watch every guard in migration 0085 BITE, on a real PostgreSQL
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// A guard nobody has seen fail is decoration (docs/NO_SPAGHETTI.md §7, checklist item 7). This
// applies the chain up to but NOT including 0085 exactly once, then runs MUTATED copies of 0085
// inside begin/rollback and records the REAL red message each of its asserts produces. A mutation
// that applies cleanly is reported as GREEN!! and fails the run — that is a guard that would never
// have caught anything.
//
//   node scripts/db/breaktest-0085.mjs               # every mutation
//   node scripts/db/breaktest-0085.mjs --clean       # apply 0085 unmutated, print its receipt
//   node scripts/db/breaktest-0085.mjs --only=<sub>  # one mutation, by a substring of its name
//
// WHAT 0085 CHANGES, so the mutations below are read for what they attack: a roadstead whose cell
// the authored carve opened lies ON the carving channel's polyline (nearest the quay), not at the
// cell's centre — London's centre was 8 nm into Kent. The channels cross the wire as
// voyage.channels, voyage.channel_foot is the foot-on-polyline, and voyage.water_roadstead is
// re-cut to read them. Every seeded point must EQUAL the function's answer (e), every channel
// roadstead must lie on its line (q), London is the named control (r), the river ports are pinned
// to the measurement (s), and (t) puts London back into Kent to prove (e) and (q) can see it.
//
// THE ORDER IS LOAD-BEARING and it is written down rather than hidden: (e) runs before (q), (r)
// and (s), and any mutation that moves a seeded point off what water_roadstead answers is caught
// by (e) first. So (q), (r) and (s) are exercised by mutating the RULE (the function bodies, the
// channel table) rather than the seed, which is the only way past (e) — and that is the right
// test of them, because a wrong rule is what they exist to catch.
//
// Shape copied from scripts/db/breaktest-0076.mjs. It lives in scripts/, never in the migration.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
import { MIGRATIONS_DIR, PREAMBLE_PATH, migrationFiles } from './apply-chain.mjs'
import { readFile } from 'node:fs/promises'
import path from 'node:path'

const LAST = '20260818000085_a_roadstead_lies_on_the_channel.sql'
const sql = (await readFile(path.join(MIGRATIONS_DIR, LAST), 'utf8')).replace(/\r\n/g, '\n')
const cleanOnly = process.argv.includes('--clean')
const only = (process.argv.find((a) => a.startsWith('--only=')) ?? '').slice('--only='.length)

const { PGlite } = await import('@electric-sql/pglite')
const db = await new PGlite()
await db.exec(await readFile(PREAMBLE_PATH, 'utf8'))
for (const f of await migrationFiles()) {
  if (f >= LAST) continue
  await db.exec((await readFile(path.join(MIGRATIONS_DIR, f), 'utf8')).replace(/\r\n/g, '\n'))
}
console.log('chain applied up to (not including) 0085\n')

// ── the unmutated run: it must be GREEN, and its receipt is the measurement this file reports ──
{
  const notices = []
  await db.exec('begin')
  let red = null
  try {
    await db.exec(sql, { onNotice: (n) => notices.push(n.message ?? String(n)) })
  } catch (e) {
    red = String(e.message)
  }
  await db.exec('rollback').catch(() => {})
  if (red) {
    console.log(`UNMUTATED 0085 IS RED — fix the migration before break-testing it:\n${red}`)
    process.exit(1)
  }
  console.log('UNMUTATED 0085: green\n')
  for (const n of notices) console.log(`  ${n}\n`)
  if (cleanOnly) process.exit(0)
}

// The anchor every "poke the seeded table" mutation hangs on: the line that opens the self-assert.
const ASSERT = '-- ── SELF-ASSERT ─'
const poke = (name, statement) => [name, ASSERT, `${statement}\n${ASSERT}`]

const MUTATIONS = [
  // ── (e) THE GENERATOR AND THE SQL ARE ONE RULE — the seed is moved off the rule ─────────────
  poke("(e) London's roadstead is put BACK at the Kent cell centre 0079 seeded, snap re-measured so (b) holds",
    `update public.sea_reaches set roadstead_lat = 51.375, roadstead_lon = -0.125, snap_nm = 8.11 where code = 'LON';`),
  poke("(e) Antwerp is seeded as her own roadstead at 0 nm again — a river port with no line and no ring",
    `update public.sea_reaches sr set snap_nm = 0, roadstead_lat = p.lat, roadstead_lon = p.lon
       from public.ports p where p.id = sr.port_id and sr.code = 'ARP';`),
  poke("(e) London's roadstead is moved 12 nm DOWN the Thames to another vertex of the same channel, consistently",
    `update public.sea_reaches sr
        set roadstead_lat = 51.5, roadstead_lon = 0.2,
            snap_nm = round(voyage.gc_distance_nm(p.lat::float8, p.lon::float8, 51.5, 0.2)::numeric, 2)
       from public.ports p where p.id = sr.port_id and sr.code = 'LON';`),

  // ── THE RULE ITSELF, mutated — the only way past (e), and what (q)/(r)/(s) exist to catch ────
  ['(e) water_roadstead stops reading the carve — every channel roadstead reverts to a cell centre',
    `   where c.carved_cells @> to_jsonb(v_brow * r.cols + v_bcol);`,
    `   where c.carved_cells @> to_jsonb(v_brow * r.cols + v_bcol) and false;`],
  ['(e) channel_foot rounds to 2 dp instead of 3 — the SQL twin and the generator stop agreeing to the digit',
    `    v_flat := round((v_alat + v_t * (v_blat - v_alat))::numeric, 3);`,
    `    v_flat := round((v_alat + v_t * (v_blat - v_alat))::numeric, 2);`],
  ['(e) channel_foot takes the FARTHEST foot instead of the nearest',
    `    if v_best is null or v_d < v_best then`,
    `    if v_best is null or v_d > v_best then`],

  // ── (p) THE CHANNELS TABLE ──────────────────────────────────────────────────────────────────
  poke('(p) the channels table is emptied after it is filled — the rule reads nothing',
    'delete from voyage.channels;'),
  poke('(p) one channel loses its carved cells (count kept honest) — a carve the table no longer describes',
    `update voyage.channels set carved_cells = '[]', opens_land = 0 where id = 'thames-scheldt';`),
  poke("(p) one channel's carved cells are pointed at LAND cells — the table describes a carve the raster does not carry",
    `update voyage.channels set carved_cells = '[0, 1, 2]', opens_land = 3 where id = 'kerch';`),
  poke('(p/CHECK) a channel is blanked to no points at all — the table refuses the row',
    `update voyage.channels set points = '[]' where id = 'thames-scheldt';`),
  poke('(p/CHECK) a channel declares more land than it lists — the table refuses the row',
    `update voyage.channels set opens_land = opens_land + 1 where id = 'severn';`),

  // ── (t) THE POSITIVE CONTROL on (q), broken so it cannot find its own planted fault ─────────
  ['(t) (q) is weakened to a tolerance that swallows Kent — the control must notice it cannot bite',
    `     where f.nm > 0.1;
    if v_bad <> 1 then`,
    `     where f.nm > 999;
    if v_bad <> 1 then`],

  // ── (j) POSTURE, both halves ────────────────────────────────────────────────────────────────
  poke('(j) a client role is granted a read on voyage.channels — the machinery crosses to the browser',
    'grant select on voyage.channels to authenticated;'),
  poke('(j) the foot rule is handed to the browser',
    'grant execute on function voyage.channel_foot(text, numeric, numeric) to authenticated;'),
  poke('(j) the roadstead rule is handed to the browser',
    'grant execute on function voyage.water_roadstead(numeric, numeric) to authenticated;'),
  poke('(j) a client role is granted a write on sea_reaches',
    'grant update on public.sea_reaches to authenticated;'),

  // ── the 0076/0079 guards this file carries forward, spot-checked ────────────────────────────
  poke('(a) the table is emptied after it is filled — every check below would pass over nothing',
    'delete from public.sea_reaches;'),
  poke("(b) one roadstead is collapsed back onto its own quay — the drawn line stops being snap_nm",
    `update public.sea_reaches sr set roadstead_lat = p.lat, roadstead_lon = p.lon
       from public.ports p where p.id = sr.port_id and sr.code = 'AMS';`),
  poke('(d) one roadstead is moved to central France, with snap_nm re-measured so (b) still passes',
    `update public.sea_reaches sr
        set roadstead_lat = 46.5, roadstead_lon = 2.5,
            snap_nm = voyage.gc_distance_nm(p.lat::float8, p.lon::float8, 46.5, 2.5)::numeric
       from public.ports p where p.id = sr.port_id and sr.code = 'AMS';`),
  poke('(n) the Arctic reopens — LIS->NAG at 8,000 nm, still longer than the great circle so only (n) can see it',
    `update public.sea_reaches set reaches = jsonb_set(reaches, '{NAG}', '8000') where code = 'LIS';
     update public.sea_reaches set reaches = jsonb_set(reaches, '{LIS}', '8000') where code = 'NAG';`),
]

let bad = 0
for (const [name, ...hunks] of MUTATIONS) {
  if (only && !name.includes(only)) continue
  let mutated = sql
  let missing = false
  for (let i = 0; i < hunks.length; i += 2) {
    if (!mutated.includes(hunks[i])) { missing = true; break }
    mutated = mutated.replace(hunks[i], hunks[i + 1])
  }
  if (missing) {
    console.log(`SKIPPED  ${name} — mutation anchor not found, FIX THE SCRIPT`)
    bad += 1
    continue
  }
  await db.exec('begin')
  let red = null
  try {
    await db.exec(mutated)
  } catch (e) {
    red = String(e.message).split('\n')[0]
  }
  await db.exec('rollback').catch(() => {})
  if (!red) {
    console.log(`GREEN!!  ${name} — the mutation applied cleanly. THE GUARD IS DECORATION.`)
    bad += 1
  } else {
    console.log(`RED      ${name}\n         ${red.slice(0, 420)}`)
  }
}
console.log(bad === 0 ? '\nALL GUARDS BITE' : `\n${bad} GUARD(S) DID NOT BITE`)
process.exit(bad === 0 ? 0 : 1)
