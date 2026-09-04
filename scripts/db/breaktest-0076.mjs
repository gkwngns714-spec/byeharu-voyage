// ═══════════════════════════════════════════════════════════════════════════════════════════════
// breaktest-0076.mjs — watch every guard in migration 0076 BITE, on a real PostgreSQL
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
// A guard nobody has seen fail is decoration (docs/NO_SPAGHETTI.md §7, checklist item 7). This
// applies the chain up to but NOT including 0076 exactly once, then runs MUTATED copies of 0076
// inside begin/rollback and records the REAL red message each of its asserts produces. A mutation
// that applies cleanly is reported as GREEN!! and fails the run — that is a guard that would never
// have caught anything.
//
//   node scripts/db/breaktest-0076.mjs               # every mutation
//   node scripts/db/breaktest-0076.mjs --clean       # apply 0076 unmutated, print its receipt
//   node scripts/db/breaktest-0076.mjs --only=<sub>  # one mutation, by a substring of its name
//
// THE ASSERTS RUN IN ORDER, AND THE ORDER IS LOAD-BEARING, so two of them cannot be reached by any
// single-hunk mutation of this file and that is written down rather than hidden:
//
//   * (c)'s FIRST half — "a place that snaps 0 nm holds a roadstead off the quay" — is unreachable
//     because (b) runs first and any roadstead more than 0.01 nm from a snap-0 quay fails (b). The
//     smallest move the column can even express (0.001°) is 0.06 nm, four times (b)'s tolerance.
//     (c)'s SECOND half IS reachable and is exercised below.
//   * (e)'s DISTANCE half is unreachable for the same reason: a snap_nm that disagrees with
//     water_roadstead's measurement by more than 0.01 nm also disagrees with the quay-to-roadstead
//     great circle, so (b) reaches it first. (e)'s POINT half IS reachable and is exercised.
//
// Shape copied from scripts/db/breaktest-0062.mjs. It lives in scripts/, never in the migration.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
import { MIGRATIONS_DIR, PREAMBLE_PATH, migrationFiles } from './apply-chain.mjs'
import { readFile } from 'node:fs/promises'
import path from 'node:path'

const LAST = '20260818000076_a_harbour_is_reached_from_its_roads.sql'
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
console.log('chain applied up to (not including) 0076\n')

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
    console.log(`UNMUTATED 0076 IS RED — fix the migration before break-testing it:\n${red}`)
    process.exit(1)
  }
  console.log('UNMUTATED 0076: green\n')
  for (const n of notices) console.log(`  ${n}\n`)
  if (cleanOnly) process.exit(0)
}

// The anchor every "poke the seeded table" mutation hangs on: the line that opens the self-assert.
const ASSERT = '-- ── SELF-ASSERT ─'
const poke = (name, statement) => [name, ASSERT, `${statement}\n${ASSERT}`]

const MUTATIONS = [
  // ── (a) NON-VACUITY ─────────────────────────────────────────────────────────────────────────
  poke('(a) the table is emptied after it is filled — every check below would pass over nothing',
    'delete from public.sea_reaches;'),

  // ── (b) THE LINE DRAWN IS THE DISTANCE MEASURED ─────────────────────────────────────────────
  poke("(b) one roadstead is collapsed back onto its own quay — the drawn line stops being snap_nm",
    `update public.sea_reaches sr set roadstead_lat = p.lat, roadstead_lon = p.lon
       from public.ports p where p.id = sr.port_id and sr.code = 'AMS';`),
  poke('(b) one snap_nm is bent while its roadstead stays put',
    `update public.sea_reaches set snap_nm = snap_nm + 1 where code = 'AMS';`),

  // ── (c) SECOND HALF: the table is not allowed to be all quay-coordinates ────────────────────
  poke('(c) every place is made its own roadstead at 0 nm — CONSISTENT, so (b) passes and only (c) can see it',
    `update public.sea_reaches sr set snap_nm = 0, roadstead_lat = p.lat, roadstead_lon = p.lon
       from public.ports p where p.id = sr.port_id;`),

  // ── (d) EVERY ROADSTEAD STANDS ON SAILABLE WATER ────────────────────────────────────────────
  poke('(d) one roadstead is moved to central France, with snap_nm re-measured so (b) still passes',
    `update public.sea_reaches sr
        set roadstead_lat = 46.5, roadstead_lon = 2.5,
            snap_nm = voyage.gc_distance_nm(p.lat::float8, p.lon::float8, 46.5, 2.5)::numeric
       from public.ports p where p.id = sr.port_id and sr.code = 'AMS';`),

  // ── (e) THE GENERATOR AND THE SQL ARE ONE RULE ──────────────────────────────────────────────
  poke('(e) one roadstead is moved to a DIFFERENT patch of open water, consistently — only the cross-check can see it',
    `update public.sea_reaches sr
        set roadstead_lat = 30, roadstead_lon = -40,
            snap_nm = voyage.gc_distance_nm(p.lat::float8, p.lon::float8, 30, -40)::numeric
       from public.ports p where p.id = sr.port_id and sr.code = 'AMS';`),

  // ── (f) THE POSITIVE CONTROL ON (b), broken so it cannot find its own planted fault ──────────
  ['(f) (b) is weakened to a tolerance that swallows a 67 nm error — the control must notice it cannot bite',
    `     where abs(voyage.gc_distance_nm(p.lat::float8, p.lon::float8,
                sr.roadstead_lat::float8, sr.roadstead_lon::float8)::numeric - sr.snap_nm) > 0.01;
    if v_bad <> 1 then`,
    `     where abs(voyage.gc_distance_nm(p.lat::float8, p.lon::float8,
                sr.roadstead_lat::float8, sr.roadstead_lon::float8)::numeric - sr.snap_nm) > 999;
    if v_bad <> 1 then`],

  // ── (g) THE HEADLINE AND ITS CONTROL ────────────────────────────────────────────────────────
  ['(g) the quay-to-quay control is asked under the NEW allowance — it stops being ACCEPTED, so the file must refuse to claim a repair',
    `                         v_pan_snap + 25, v_por_snap + 25) is not null then`,
    `                         25, 25) is not null then`],
  // THE REGRESSION THIS HALF OF (g) GUARDS, put back whole: the roadstead reverts to the quay AND
  // the allowance reverts to snap + 25 — i.e. exactly what 0047 did. MEASURED ON THE WAY, and it
  // is the more interesting half: reverting ONLY the allowance leaves the roads-to-roads line
  // REFUSED, because the isthmus is wider than 35.82 + 44.02 nm of exemption. So the thing that
  // closes Panama is the ROADSTEAD, not the flat 25 — and a mutation of the allowance alone would
  // have reported this guard as decoration when it is nothing of the kind.
  ['(g) the whole file regresses to 0047 — the isthmus line runs quay to quay again, under snap + 25',
    `  v_road_line := jsonb_build_array(jsonb_build_array(v_pan_rlat, v_pan_rlon),
                                   jsonb_build_array(v_por_rlat, v_por_rlon));
  v_isthmus := voyage.path_refusal(v_road_line, v_pan_rlat, v_pan_rlon, v_por_rlat, v_por_rlon,
                                   public.wc_num('course_join_nm'), 25, 25);`,
    `  v_road_line := jsonb_build_array(jsonb_build_array(v_pan_lat, v_pan_lon),
                                   jsonb_build_array(v_por_lat, v_por_lon));
  v_isthmus := voyage.path_refusal(v_road_line, v_pan_lat, v_pan_lon, v_por_lat, v_por_lon,
                                   public.wc_num('course_join_nm'), v_pan_snap + 25, v_por_snap + 25);`],

  // ── (h) THE WIRE ────────────────────────────────────────────────────────────────────────────
  ['(h) the served roadstead loses its latitude — a client would have to compute one',
    `                        'lat', sr.roadstead_lat, 'lon', sr.roadstead_lon, 'nm', sr.snap_nm)`,
    `                        'lat', null, 'lon', sr.roadstead_lon, 'nm', sr.snap_nm)`],
  ['(h) the wire serves a table of zeroes — every key present, every distance 0, nothing drawn',
    `                        'lat', sr.roadstead_lat, 'lon', sr.roadstead_lon, 'nm', sr.snap_nm)`,
    `                        'lat', sr.roadstead_lat, 'lon', sr.roadstead_lon, 'nm', 0)`],

  // ── (i) THE MOVER, AND THE OWNER'S SENTENCE ─────────────────────────────────────────────────
  ['(i) the ORIGIN hunk is reverted — she puts to sea from the quay again',
    `    select sr.roadstead_lat, sr.roadstead_lon into v_olat, v_olon
      from public.sea_reaches sr where sr.port_id = f.port_id;$o1$,`,
    `    select p.lat, p.lon into v_olat, v_olon from public.ports p where p.id = f.port_id;$o1$,`],
  // A FIFTH hunk, appended AFTER the four so it runs last: the destination read is put back to
  // the quay once 0076's own hunk has already replaced it. Order matters — an extra pair placed
  // before $d0$ would look for text the body does not hold yet, and recut would refuse it.
  ['(i) the DESTINATION hunk is reverted — her course ends at the quay again',
    `    v_tail := 25;$t1$);`,
    `    v_tail := 25;$t1$,
  $z0$    select sr.roadstead_lat, sr.roadstead_lon into v_dlat, v_dlon
      from public.sea_reaches sr where sr.port_id = v_dest;$z0$,
  $z1$    select p.lat, p.lon into v_dlat, v_dlon from public.ports p where p.id = v_dest;$z1$);`],
  ['(i) the arrival is pointed at the wrong port — docking somewhere else must be caught',
    `    if v_status <> 'DOCKED' or v_docked is distinct from (select id from public.ports where code = 'SET') then`,
    `    if v_status <> 'DOCKED' or v_docked is distinct from (select id from public.ports where code = 'AMS') then`],
  ['(i) GRANDFATHER: the cutoff never fires, so the guard keeps the hole this file closed',
    `    if v.origin_port_id is not null and v.departed_at >= %L::timestamptz then`,
    `    if v.origin_port_id is not null and false and v.departed_at >= %L::timestamptz then`],
  ['(i) GRANDFATHER: the cutoff fires for EVERYONE, so a pre-0076 voyage a player bought is failed (the guard raises, which is the point)',
    `    if v.origin_port_id is not null and v.departed_at >= %L::timestamptz then`,
    `    if v.origin_port_id is not null and (true or v.departed_at >= %L::timestamptz) then`],

  // ── (j) POSTURE, both halves ────────────────────────────────────────────────────────────────
  poke('(j) a client role is granted a write on sea_reaches',
    'grant update on public.sea_reaches to authenticated;'),
  poke('(j) the roadstead rule is handed to the browser',
    'grant execute on function voyage.water_roadstead(numeric, numeric) to authenticated;'),

  // ── (l) THE TABLE'S OWN SHAPE ───────────────────────────────────────────────────────────────
  poke('(l) one reading is bent in one direction only — the table stops being symmetric',
    `update public.sea_reaches set reaches = jsonb_set(reaches, '{NAG}', '8000') where code = 'LIS';`),

  // ── (m) NOTHING SAILS SHORTER THAN THE GREAT CIRCLE BETWEEN THE ROADSTEADS ──────────────────
  poke('(m) one pair is made to sail 100 nm across the world, symmetrically',
    `update public.sea_reaches set reaches = jsonb_set(reaches, '{NAG}', '100') where code = 'LIS';
     update public.sea_reaches set reaches = jsonb_set(reaches, '{LIS}', '100') where code = 'NAG';`),

  // ── (n) THE WORLD'S THREE STANDING FACTS ────────────────────────────────────────────────────
  poke('(n) the Arctic reopens — LIS->NAG at 8,000 nm, still longer than the great circle so only (n) can see it',
    `update public.sea_reaches set reaches = jsonb_set(reaches, '{NAG}', '8000') where code = 'LIS';
     update public.sea_reaches set reaches = jsonb_set(reaches, '{LIS}', '8000') where code = 'NAG';`),

  // ── (o) THE LAW STILL REFUSES LAND ──────────────────────────────────────────────────────────
  ['(o) the Iberia negative control is given a 4,000 nm allowance — a straight line across Spain becomes legal',
    '38.71, -9.14, 41.38, 2.18, 15, 40, 40);',
    '38.71, -9.14, 41.38, 2.18, 15, 4000, 4000);'],
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
