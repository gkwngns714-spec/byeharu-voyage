// ═══════════════════════════════════════════════════════════════════════════════════════════════
// proof-0226-hour.mjs — FROZEN 0226: the probe's planted pair must not straddle a UTC day.
// LOCAL ONLY (PGlite); not in CI. Source of the table in the PR that added the patch.
// ═══════════════════════════════════════════════════════════════════════════════════════════════
//
//   node scripts/ops/harness/frozen-0226/proof-0226-hour.mjs                  every check (about 15 min: 12 of them build the world)
//   node scripts/ops/harness/frozen-0226/proof-0226-hour.mjs --hours=0,1,2     only these UTC hours (still red first)
//   ... --world=PATH keep a scratch copy of the pre-0226 world there (first run builds it, later runs load it: about 2 min)
//   ... --no-edges   skip the second-by-second cases around UTC hour 01
//   ... --no-zone    skip the session-time-zone cases (Asia/Seoul)
//   ... --no-mutants skip the mutants
//
// THE DEFECT. Migration 0226's self-assert plants two finished hours of "yesterday" at
//     v_h0 := date_trunc('hour', now()) - interval '26 hours'      (supabase/migrations/…0226…sql:612)
// and expects ONE day row over both (n 8). In UTC hour 01 that pair is 23:00 and 00:00: two days, so the day
// folds into two rows of n 4 and the assert fails ("0226 self-assert FAIL: the day folded day … n 4"). CI
// from-zero applies that reached 0226 at 01:00, 01:07 and 01:41 UTC died there (chain-baseline, 11-04/05/06).
// The file is frozen, so src/lib/db/frozenAsserts.ts reads that one line differently: one hour earlier in
// UTC hour 01 and nowhere else. This script proves that, for every UTC hour, on the real file.
//
// HOW IT RUNS THE FILE. The self-assert reads temp tables the file builds earlier, and the marks its own
// backfill tick leaves, so it cannot run alone: the WHOLE 0226 file runs, in one transaction that is rolled
// back, on the cached world at the head before it (never from zero: it needs the local prefix cache, as every
// harness here does, and only reads it: nothing is written to or pruned from it). The clock is SHADOWED: a function now() in a sibling schema
// listed after public and before pg_catalog in search_path, so every unqualified now() in the file and in its
// DO block reads the chosen instant (the session time zone is UTC, as on CI, unless a case says otherwise).
// The shadow lives in its own schema, granted to PUBLIC, so the lockdown authorities the self-assert calls
// (caller_evaluated_functions and the like) see nothing new in public and nothing a client cannot execute.
// Functions with their own search_path (the tick, the series) still read the real clock; the instants are
// therefore taken from the last 24 hours of real time, which keeps every row the file writes inside the
// windows those functions look at.
//
// WHAT IT CHECKS (every line below is an expectation; any miss exits 1):
//   1. RED FIRST   the file as written fails in UTC hour 01 and in no other hour, with the day-fold message;
//   2. THE PATCH   the patched text (sqlToApply, the applier's own path) differs from the file in exactly one line;
//   3. GREEN       it passes in all 24 hours and prints its receipt; the planted rows are on ONE UTC day and
//                  older than 24 h; outside hour 01 the planted hours are the file's own, to the second;
//   3b. SAME DB    outside hour 01 the patched text leaves the database the file leaves, content digest for
//                  content digest (what the prefix snapshots and world images judge a database by), each on its own fork;
//   4. EDGES       00:59:59 / 01:00:00 / 01:59:59 / 02:00:00: unpatched fails exactly in hour 01, patched passes;
//   5. ZONE        a session in Asia/Seoul (this PC): the flake is in UTC hour 01, i.e. 10:xx there;
//   6. MUTANTS     the patched assert can still fail: a pair on two days, a pair one hour short of the fold, a
//                  pair on an unfinished day, and a shift made in the wrong hour are each red, for the intended reason.
// The planted hours are read off the executed text by a one-line notice added after the plant, the same in
// every case (instrumentation, not part of the patch).

import { existsSync } from 'node:fs'
import { readFile, writeFile } from 'node:fs/promises'
import path from 'node:path'
import { gzipSync } from 'node:zlib'
import { migrationFiles, MIGRATIONS_DIR, PREFIX_CACHE_DIR, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache, contentDigest, dumpCheckpointed } from '../../../db/prefix-cache.mjs'
import { FROZEN_ASSERT_PATCHES, sqlToApply } from '../../../../src/lib/db/frozenAsserts.ts'

const NAME = '20260818000226_a_price_is_kept_for_years_both_ways.sql'
const say = (...a) => console.log(...a)
const opt = (k) => process.argv.find((a) => a.startsWith(`--${k}=`))?.slice(k.length + 3)
const flag = (k) => process.argv.includes(`--${k}`)
const failures = []
const expect = (ok, what) => {
  if (!ok) failures.push(what)
  return ok
}
const swap = (sql, from, to) => {
  if (sql.split(from).length !== 2) throw new Error(`text occurs ${sql.split(from).length - 1} times, not once: ${from.trim()}`)
  return sql.replace(from, to)
}

// ── the world: the cached head before 0226 ───────────────────────────────────────────────────────
const names = await migrationFiles()
const at = names.indexOf(NAME)
if (at < 1) throw new Error(`${NAME} is not in supabase/migrations/`)
const before = []
for (const n of names.slice(0, at)) before.push({ name: n, sql: await readFile(path.join(MIGRATIONS_DIR, n), 'utf8') })
// --world=PATH keeps a scratch copy of that world (outside the repo and the shared cache): the first run builds
// and saves it, later runs load it in seconds, digest checked. Without it the world is rebuilt every run.
const worldFile = opt('world')
const sideFile = worldFile && `${worldFile}.json`
const names226 = before.map((f) => f.name)
let db
if (worldFile && existsSync(worldFile) && existsSync(sideFile)) {
  const meta = JSON.parse(await readFile(sideFile, 'utf8'))
  if (JSON.stringify(meta.names) !== JSON.stringify(names226)) throw new Error(`${worldFile} is a world for another chain: delete it`)
  const { PGlite } = await import('@electric-sql/pglite')
  const bytes = new Uint8Array(await readFile(worldFile))
  db = await PGlite.create({ loadDataDir: new File([bytes], 'world.tar.gz', { type: 'application/gzip' }) })
  if ((await contentDigest(db)) !== meta.digest) throw new Error(`${worldFile} restored to another content digest: delete it`)
  say(`world: ${before.length} files before 0226, loaded from ${worldFile} (content digest verified)\n`)
} else {
  const world = await applyWithPrefixCache({
    variant: await preambleVariant(), files: before, cacheDir: PREFIX_CACHE_DIR, log: say, required: true, snapshots: false,
  })
  db = world.db
  say(`world: ${before.length} files before 0226, ${world.restored} restored from the prefix cache, ${world.applied.filter((r) => !r.restored).length} applied here\n`)
  if (worldFile) {
    const { tar } = await dumpCheckpointed(db)
    await writeFile(worldFile, gzipSync(tar, { level: 1 }))
    await writeFile(sideFile, JSON.stringify({ names: names226, digest: await contentDigest(db), made: new Date().toISOString() }))
    say(`world: saved to ${worldFile}\n`)
  }
}

// ── the texts ────────────────────────────────────────────────────────────────────────────────────
const raw = (await readFile(path.join(MIGRATIONS_DIR, NAME), 'utf8')).replaceAll('\r', '')
const entry = FROZEN_ASSERT_PATCHES.find((p) => p.file === NAME)
if (!entry) throw new Error(`no entry for ${NAME} in FROZEN_ASSERT_PATCHES`)
const patchedText = sqlToApply({ name: NAME, sql: raw }) // the applier's own path, unique-find check included

// the planted hours, read off the executed text (the same line in every case; instrumentation, not the patch)
const AFTER_PLANT = "    update public.price_rollup set hour_done = v_h0, day_done = (v_h0 at time zone 'UTC')::date;\n"
const SPY =
  "    raise notice 'PLANT first=% last=% days=% youngest_age_h=%', v_h0, v_h0 + interval '105 minutes', " +
  "(select count(distinct ((v_h0 + make_interval(mins => 15 * i)) at time zone 'UTC')::date) from generate_series(0, 7) i), " +
  "round(extract(epoch from now() - (v_h0 + interval '105 minutes')) / 3600, 2);\n"
const spied = (s) => swap(s, AFTER_PLANT, AFTER_PLANT + SPY)

const UNPATCHED = spied(raw)
const PATCHED = spied(patchedText)

// 2. THE PATCH: exactly one line differs
{
  const a = raw.split('\n')
  const b = patchedText.split('\n')
  const changed = a.map((l, i) => (l === b[i] ? -1 : i)).filter((i) => i >= 0)
  say('THE PATCH (sqlToApply on the real file):')
  for (const i of changed) say(`  line ${i + 1}\n    - ${a[i].trim()}\n    + ${b[i].trim()}`)
  expect(a.length === b.length && changed.length === 1, 'the patched text differs from the file in exactly one line')
  say(`  ${changed.length === 1 ? 'one line differs' : changed.length + ' lines differ'}; every assertion of the final self-assert is the file's own\n`)
}

// ── one attempt: the whole file, shadowed clock, rolled back ─────────────────────────────────────
const PLANT_RE = /PLANT first=(\S+ \S+) last=(\S+ \S+) days=(\d+) youngest_age_h=([\d.]+)/
async function attempt(sql, instant, zone = 'UTC', digest = false, target = db) {
  const notices = []
  const t = performance.now()
  await target.exec(`set time zone '${zone}'`)
  await target.exec('begin')
  try {
    await target.exec(`
      create schema zz_clock;
      create function zz_clock.now() returns timestamptz language sql stable as $f$ select '${instant}'::timestamptz $f$;
      grant usage on schema zz_clock to public;
      grant execute on function zz_clock.now() to public;
      set local search_path = public, zz_clock, pg_catalog;`)
    await target.exec(sql, { onNotice: (n) => notices.push(n.message ?? String(n)) })
    // the database the file leaves behind (inside the transaction, before the rollback), as the snapshots judge it:
    // the stable digest (uuid and clock columns dropped: the real clock still stamps some rows), sequences included
    return { ok: true, notices, ms: performance.now() - t, digest: digest ? await contentDigest(target, { stableOnly: true }) : undefined }
  } catch (e) {
    return { ok: false, error: String(e?.message ?? e), notices, ms: performance.now() - t }
  } finally {
    await target.exec('rollback')
  }
}
const plant = (r) => {
  const m = r.notices.map((n) => PLANT_RE.exec(n)).find(Boolean)
  return m ? { first: m[1], last: m[2], days: Number(m[3]), age: Number(m[4]) } : null
}
const receipt = (r) => r.ok && r.notices.some((n) => /0226 self-assert ok:/.test(n))
const verdict = (r) => (r.ok ? (receipt(r) ? 'PASS' : 'PASS?no-receipt') : 'FAIL')
const msg = (r) => (r.ok ? '' : r.error.replace(/^error: /i, '').split('\n')[0].slice(0, 110))

// ── the instants: 24 consecutive hours ending 25 minutes ago, one per UTC hour of the day ───────
const realNow = new Date()
const last = new Date(Math.floor((realNow.getTime() - 25 * 60_000) / 60_000) * 60_000)
const instants = new Map()
for (let i = 0; i < 24; i += 1) {
  const d = new Date(last.getTime() - i * 3_600_000)
  instants.set(d.getUTCHours(), d)
}
const iso = (d) => d.toISOString()
const hours = (opt('hours') ? opt('hours').split(',').map(Number) : [...Array(24).keys()]).sort((a, b) => a - b)

// the shadow works, and the real clock is still there
{
  const d = instants.get(hours[0])
  await db.exec("set time zone 'UTC'")
  await db.exec('begin')
  await db.exec(`create schema zz_clock; create function zz_clock.now() returns timestamptz language sql stable as $f$ select '${iso(d)}'::timestamptz $f$; set local search_path = public, zz_clock, pg_catalog;`)
  const r = (await db.query(`select now()::text as shadow, pg_catalog.now()::text as real`)).rows[0]
  await db.exec('rollback')
  say(`SHADOW CHECK: now() = ${r.shadow}, pg_catalog.now() = ${r.real}`)
  expect(new Date(r.shadow).getTime() === d.getTime(), 'the shadowed now() is the chosen instant')
}

// ── 1. RED FIRST: the file as written ────────────────────────────────────────────────────────────
say('\n1. RED FIRST — the file as written, UTC session, now() = hh:mm of the last 24 hours')
const un = new Map()
for (const h of hours) {
  const r = await attempt(UNPATCHED, iso(instants.get(h)))
  un.set(h, r)
  const p = plant(r)
  say(`  hour ${String(h).padStart(2, '0')}  ${iso(instants.get(h)).slice(0, 16)}Z  ${verdict(r).padEnd(5)}  planted ${p ? `${p.first.slice(5, 16)} .. ${p.last.slice(11, 16)} (${p.days} day${p.days === 1 ? '' : 's'}, youngest ${p.age} h)` : '(not reached)'}  ${Math.round(r.ms / 1000)} s${msg(r) ? `\n           ${msg(r)}` : ''}`)
}
const failedUn = hours.filter((h) => !un.get(h).ok)
expect(hours.every((h) => (h === 1 ? !un.get(h).ok : un.get(h).ok && receipt(un.get(h)))), 'the file as written fails in UTC hour 01 and in no other hour')
if (hours.includes(1)) expect(/the day folded day .* n 4/.test(un.get(1).error ?? ''), 'its failure is the day fold: n 4, not n 8')
say(`  as written: fails in hour(s) [${failedUn.map((h) => String(h).padStart(2, '0')).join(', ')}]${hours.length === 24 ? ' of 24' : ''}`)

// ── 3. GREEN: the patched text ───────────────────────────────────────────────────────────────────
say('\n3. GREEN — the patched text (sqlToApply), same instants')
const pa = new Map()
for (const h of hours) {
  const r = await attempt(PATCHED, iso(instants.get(h)))
  pa.set(h, r)
  const p = plant(r)
  const same = p && plant(un.get(h)) && plant(un.get(h)).first === p.first
  say(`  hour ${String(h).padStart(2, '0')}  ${iso(instants.get(h)).slice(0, 16)}Z  ${verdict(r).padEnd(5)}  planted ${p ? `${p.first.slice(5, 16)} .. ${p.last.slice(11, 16)} (${p.days} day${p.days === 1 ? '' : 's'}, youngest ${p.age} h)` : '(not reached)'}${h === 1 ? '  <- one hour earlier' : same ? '  = the file\'s own' : ''}  ${Math.round(r.ms / 1000)} s${msg(r) ? `\n           ${msg(r)}` : ''}`)
  expect(r.ok && receipt(r), `patched: UTC hour ${h} passes and prints its receipt`)
  expect(p && p.days === 1, `patched: UTC hour ${h} plants its pair on one UTC day`)
  expect(p && p.age > 24, `patched: UTC hour ${h} plants rows older than 24 h`)
  if (h !== 1) expect(same, `patched: UTC hour ${h} plants exactly the hours the file plants`)
}
say(`  patched: passes in ${hours.filter((h) => pa.get(h).ok).length} of ${hours.length} hour(s)`)

// ── 3b. THE DATABASE IT LEAVES: the same, digest for digest, as the file as written leaves ────────
// (outside UTC hour 01, where both pass). The prefix snapshots and world images judge a database by this digest
// (scripts/db/prefix-cache.mjs contentDigest: every row, sequence, function body, ACL, policy); their KEYS hash
// the file, which the patch never touches. Each variant runs ONCE on its own fork of the world: a sequence is not
// transactional, so a second run on one instance would start from the first run's positions.
{
  const h = hours.find((x) => x !== 1)
  if (h !== undefined) {
    const { PGlite } = await import('@electric-sql/pglite')
    const gz = new Uint8Array(gzipSync((await dumpCheckpointed(db)).tar, { level: 1 }))
    const fork = () => PGlite.create({ loadDataDir: new File([gz], 'world.tar.gz', { type: 'application/gzip' }) })
    const [forkA, forkB] = [await fork(), await fork()]
    const u = await attempt(UNPATCHED, iso(instants.get(h)), 'UTC', true, forkA)
    const p = await attempt(PATCHED, iso(instants.get(h)), 'UTC', true, forkB)
    await forkA.close()
    await forkB.close()
    say(`\n3b. THE DATABASE IT LEAVES — UTC hour ${String(h).padStart(2, '0')}, stable content digest after the whole file, each on its own fork`)
    say(`  as written ${u.digest ? u.digest.slice(0, 16) : verdict(u)}   patched ${p.digest ? p.digest.slice(0, 16) : verdict(p)}   ${u.digest && u.digest === p.digest ? 'EQUAL' : 'DIFFERENT'}`)
    expect(Boolean(u.digest) && u.digest === p.digest, `the patched text leaves the database the file as written leaves (UTC hour ${h})`)
  }
}

// ── 4. EDGES around UTC hour 01 ──────────────────────────────────────────────────────────────────
if (!flag('no-edges') && (!opt('hours') || hours.includes(1))) {
  say('\n4. EDGES — the seconds around UTC hour 01 (the latest such instant within the last 23 h; skipped if none fits today)')
  const place = (hh, mm, ss) => {
    const d = new Date(last.getTime())
    d.setUTCHours(hh, mm, ss, 0)
    while (d.getTime() > last.getTime()) d.setUTCDate(d.getUTCDate() - 1)
    return last.getTime() - d.getTime() <= 23 * 3_600_000 ? d : null
  }
  for (const [hh, mm, ss, wantFail] of [[0, 59, 59, false], [1, 0, 0, true], [1, 59, 59, true], [2, 0, 0, false]]) {
    const d = place(hh, mm, ss)
    const label = `${String(hh).padStart(2, '0')}:${String(mm).padStart(2, '0')}:${String(ss).padStart(2, '0')}`
    if (!d) {
      say(`  ${label}  skipped: no such instant in the last 23 h of today's clock`)
      continue
    }
    const u = await attempt(UNPATCHED, iso(d))
    const p = await attempt(PATCHED, iso(d))
    say(`  ${label}  ${iso(d).slice(0, 19)}Z  as written ${verdict(u).padEnd(5)}  patched ${verdict(p)}`)
    expect(wantFail ? !u.ok : u.ok, `edge ${label}: as written ${wantFail ? 'fails' : 'passes'}`)
    expect(p.ok && receipt(p), `edge ${label}: patched passes`)
  }
}

// ── 5. ZONE: the session time zone of this PC ────────────────────────────────────────────────────
if (!flag('no-zone') && hours.includes(1) && hours.includes(16)) {
  say('\n5. ZONE — a session in Asia/Seoul (UTC+9; 10:xx there is UTC hour 01)')
  for (const [h, wantFail] of [[1, true], [16, false]]) {
    const u = await attempt(UNPATCHED, iso(instants.get(h)), 'Asia/Seoul')
    const p = await attempt(PATCHED, iso(instants.get(h)), 'Asia/Seoul')
    say(`  UTC hour ${String(h).padStart(2, '0')} (${String((h + 9) % 24).padStart(2, '0')}:xx Seoul)  as written ${verdict(u).padEnd(5)}  patched ${verdict(p)}`)
    expect(wantFail ? !u.ok : u.ok, `zone: as written ${wantFail ? 'fails' : 'passes'} at UTC hour ${h} in an Asia/Seoul session`)
    expect(p.ok && receipt(p), `zone: patched passes at UTC hour ${h} in an Asia/Seoul session`)
  }
}

// ── 6. MUTANTS: the patched assert can still fail ────────────────────────────────────────────────
if (!flag('no-mutants')) {
  say('\n6. MUTANTS — the patched text with its plant line broken on purpose; each must be RED for the intended reason')
  const PLANT_LINE = entry.replace
  const day = "date_trunc('day', now() at time zone 'UTC') at time zone 'UTC'"
  const MUTANTS = [
    ['the pair on two days (23:00 and 00:00) at every hour', `    v_h0 := ${day} - interval '2 days' + interval '23 hours';\n`, [5, 13, 23], /the day folded day .* n 4/],
    // one hour short of the fold: the second planted hour is the hour the run itself is in (the instants end at :45
    // and a slot is 15 minutes, so the run's hour is the next one). The hour does not fold; red, but at the step
    // before, because the planted row at the run's own slot beats the tick's row (on conflict do nothing).
    ['one hour short of the fold (the second planted hour is the run\'s own)', "    v_h0 := date_trunc('hour', now());\n", [5, 13], /the unsold pair .* recorded ask <NULL> bid [\d.]+, world.price says bid/],
    // beyond the fold: nothing planted is a finished hour, so the fold writes no hour row for the pair
    ['the pair beyond the fold (24 hours ahead)', "    v_h0 := date_trunc('hour', now()) + interval '24 hours';\n", [5, 13], /0 hour row\(s\) at the planted hours for the probe pair, expected 2/],
    ['the pair on an unfinished day (today 00:00 and 01:00)', `    v_h0 := ${day};\n`, [5, 13], /the day folded day <NULL>/],
    ['the shift made in the wrong hour (02, not 01)', PLANT_LINE.replace('= 1 then', '= 2 then'), [1, 2], /the day folded day .* n 4/],
  ]
  for (const [what, line, atHours, want] of MUTANTS) {
    const text = swap(PATCHED, PLANT_LINE, line)
    for (const h of atHours.filter((x) => !opt('hours') || hours.includes(x))) {
      const r = await attempt(text, iso(instants.get(h)))
      const good = !r.ok && want.test(r.error)
      expect(good, `mutant "${what}" at UTC hour ${h} is red for the intended reason`)
      say(`  ${good ? 'RED, as it must be' : 'FAIL'}  ${what}, hour ${String(h).padStart(2, '0')}\n      ${r.ok ? 'it passed' : msg(r)}`)
    }
  }
}

await db.close()
say(`\n${'─'.repeat(100)}`)
if (failures.length) {
  say(`${failures.length} EXPECTATION(S) FAILED:\n  ${failures.join('\n  ')}`)
  process.exit(1)
}
say('every expectation held: the file as written fails in UTC hour 01 only; the patched text passes in every hour (one UTC day, over 24 h old, ' +
  'the file\'s own hours outside hour 01); the mutants are red.')
