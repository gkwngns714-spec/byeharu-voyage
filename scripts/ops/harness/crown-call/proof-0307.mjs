// ═════════════════════════════════════════════════════════════════
// proof-0307.mjs — A CAPITAL DRAWS ON ITS NATION (migration 0307): the red-first proof. LOCAL ONLY (PGlite); not in CI.
// ═════════════════════════════════════════════════════════════════
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/crown-call/proof-0307.mjs
//
// Restores the cached world at head 0306 (never from zero), then applies 0307 to it several times inside savepoints:
//   MUTATION CONTROLS - deliberate breakages of the file, each required to FAIL its self-assert for the intended reason;
//   POSITIVE CONTROL  - the real file, which must pass and print its receipt.
// The harness reads the migration from supabase/migrations; it does not edit it.

import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { migrationFiles, MIGRATIONS_DIR, PREFIX_CACHE_DIR, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const NAME = '20260818000307_a_capital_draws_on_its_nation.sql'
const failures = []
const say = (...a) => console.log(...a)

const names = await migrationFiles()
const files = []
for (const n of names) if (n !== NAME) files.push({ name: n, sql: await readFile(path.join(MIGRATIONS_DIR, n), 'utf8') })
const file = (await readFile(path.join(MIGRATIONS_DIR, NAME), 'utf8')).replaceAll('\r', '')
const out = await applyWithPrefixCache({
  variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: say, required: true, snapshots: false,
})
const db = out.db
say(`world: head ${files.at(-1).name.slice(0, 14)}, ${out.restored} of ${files.length} restored from the prefix cache, ${out.applied.filter((r) => !r.restored).length} applied here`)

function swap(sql, from, to) {
  if (sql.split(from).length !== 2) throw new Error(`mutation text occurs ${sql.split(from).length - 1} times: ${from}`)
  return sql.replace(from, to)
}

const ROOM = `least(public.wc_num('crown_call_share') * x.above, x.above - public.wc_num('crown_call_cover') * x.reserve)`

const MUTATIONS = [
  ['no call at all (the bug itself)', (s) => swap(s,
    `  v_call := public.crown_call(v_short);\n`,
    `  v_call := jsonb_build_object('called', 0, 'donors', 0);\n`),
    /the shortfall was not called exactly/],
  ['the call overshoots the shortfall by 1 d.', (s) => swap(s,
    `    v_gap := k.need - public.city_surplus(k.cap);`,
    `    v_gap := k.need + 1 - public.city_surplus(k.cap);`),
    /a capital that could pay called|the shortfall was not called exactly/],
  ['a capital under its reserve calls only what its cities need', (s) => swap(s,
    `    v_gap := k.need - public.city_surplus(k.cap);`,
    `    v_gap := k.need - greatest(0, public.city_surplus(k.cap));`),
    /under its reserve was not made whole/],
  ['the capital does not receive: gold is burned', (s) => swap(s,
    `      perform public.treasury_post(k.cap, 'CROWN_CALL', v_c, null, null);\n`, ``),
    /the sum of purses moved/],
  ['the donor does not pay: gold is minted', (s) => swap(s,
    `      perform public.treasury_post(d.id, 'CROWN_CALL', -v_c, null, null);\n`, ``),
    /the sum of purses moved/],
  ['a donor can be called to its whole purse', (s) => swap(s, ROOM, `public.treasury_balance(p_port)`),
    /a donor went under its reserve/],
  ['a donor is judged from its reserve, not its target, with no share and no cover', (s) => swap(s, ROOM, `x.above + public.city_aid_target(p_port) - x.reserve`),
    /a donor went under its aid target/],
  ['the share cap is ignored', (s) => swap(s, ROOM, `x.above - public.wc_num('crown_call_cover') * x.reserve`),
    /gave more than its share/],
  ['the cover is ignored: a donor near its reserve gives', (s) => swap(s, ROOM, `public.wc_num('crown_call_share') * x.above`),
    /a donor near its reserve gave|gave more than its share/],
  ['the poorest pays first', (s) => swap(s, `order by c.room desc, h.code loop`, `order by c.room, h.code loop`),
    /not called exactly, from the richest/],
  ['a busy donor is called anyway', (s) => swap(s, `      continue when not public.treasury_try_lock(d.id);\n`, ``),
    /a busy donor was not passed over/],
  ['a donor outside the realm pays', (s) => swap(s, `h.id <> k.cap and public.city_capital(h.id) = k.cap and c.room > 0`, `h.id <> k.cap and c.room > 0`),
    /not called exactly|the sum of purses moved/],
  ['knob 0 still calls', (s) => swap(s, `least(public.wc_num('crown_call_share') * x.above,`, `least(greatest(public.wc_num('crown_call_share'), 0.10) * x.above,`),
    /knob 0 is not 0306/],
  ['the try-lock takes another key', (s) => swap(s, `pg_try_advisory_xact_lock(hashtextextended('byeharu.treasury:' || p_port::text, 0))`, `pg_try_advisory_xact_lock(hashtextextended('byeharu.call:' || p_port::text, 0))`),
    /does not take public.treasury_lock's key/],
  ['a hunk was cut against a body that is not the live one', (s) => swap(s,
    `$h$  return jsonb_build_object('aided', v_aided, 'aid', v_aid);\n$h$];`,
    `$h$  return jsonb_build_object('aided', v_aided,  'aid', v_aid);\n$h$];`),
    /hunk 4 of public.crown_aid occurs 0/],
  ['a hunk does not reverse: the new body gained a line no hunk knows', (s) => swap(s,
    `  execute v_def;

  -- ── 6.`,
    `  execute replace(v_def, 'v_aided := v_aided + 1;', 'v_aided := v_aided + 1; -- drift');

  -- ── 6.`),
    /does not reverse to its pre-image/],
]

async function attempt(sql) {
  const notices = []
  const t = performance.now()
  await db.exec('begin')
  try {
    await db.exec(sql, { onNotice: (n) => notices.push(n.message ?? String(n)) })
    return { ok: true, error: null, notices, ms: performance.now() - t }
  } catch (e) {
    return { ok: false, error: String(e?.message ?? e), notices, ms: performance.now() - t }
  } finally {
    await db.exec('rollback')
  }
}

for (const [what, mutate, why] of MUTATIONS) {
  const r = await attempt(mutate(file))
  const good = !r.ok && why.test(r.error)
  if (!good) failures.push(what)
  say(`${good ? 'RED, as it must be' : 'FAIL'}  ${what}\n    ${r.ok ? 'it passed' : r.error.slice(0, 260)}`)
}

const green = await attempt(file)
if (!green.ok) failures.push(`the real file: ${green.error}`)
say(`\n${green.ok ? 'GREEN' : 'FAIL'}  the real file, ${Math.round(green.ms)} ms\n    ${green.ok ? green.notices.find((n) => n.includes('self-assert ok')) : green.error}`)

await db.close()
if (failures.length) {
  say(`\n${failures.length} FAILED:\n  ${failures.join('\n  ')}`)
  process.exit(1)
}
say(`\nall ${MUTATIONS.length} mutations red, the real file green`)
