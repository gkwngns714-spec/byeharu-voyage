// ═════════════════════════════════════════════════════════════════
// proof-0313.mjs — MERCHANTS INVEST THEIR SURPLUS (migration 0313): the red-first proof. LOCAL ONLY (PGlite); not in CI.
// ═════════════════════════════════════════════════════════════════
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/merchants-invest/proof-0313.mjs
//
// Restores the cached world (never from zero), then applies 0313 to it several times inside rolled-back transactions:
//   MUTATION CONTROLS - deliberate breakages of the file, each required to FAIL its self-assert for the intended reason;
//   POSITIVE CONTROL  - the real file, which must pass and print its receipt; then proof 21 over the real pass, on top of it.
// The harness reads the migration from supabase/migrations; it does not edit it.

import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { migrationFiles, MIGRATIONS_DIR, PREFIX_CACHE_DIR, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const NAME = '20260818000313_merchants_invest_their_surplus.sql'
const PROOF = new URL('../../../db/proofs/21_merchants_invest.sql', import.meta.url)
const failures = []
const say = (...a) => console.log(...a)

const names = await migrationFiles()
const files = []
for (const n of names) if (n !== NAME) files.push({ name: n, sql: await readFile(path.join(MIGRATIONS_DIR, n), 'utf8') })
const file = (await readFile(path.join(MIGRATIONS_DIR, NAME), 'utf8')).replaceAll('\r', '')
const proof = (await readFile(PROOF, 'utf8')).replaceAll('\r', '')
const out = await applyWithPrefixCache({
  variant: await preambleVariant(), files, cacheDir: PREFIX_CACHE_DIR, log: say, required: true, snapshots: false,
})
const db = out.db
say(`world: head ${files.at(-1).name.slice(0, 14)}, ${out.restored} of ${files.length} restored from the prefix cache, ${out.applied.filter((r) => !r.restored).length} applied here`)

function swap(sql, from, to) {
  if (sql.split(from).length !== 2) throw new Error(`mutation text occurs ${sql.split(from).length - 1} times: ${from}`)
  return sql.replace(from, () => to)
}

const BEFORE_ASSERT = `  -- ── 4. THE SELF-ASSERT: the catalog ──\n`
const addBeforeAssert = (s, sql) => swap(s, BEFORE_ASSERT, `${sql}\n${BEFORE_ASSERT}`)

const MUTATIONS = [
  ['a finished work offers nothing', (s) => swap(s, `then greatest(0, public.wc_int('works_open_shares') - w.subscribed)\n`, `then 0\n`), /does not offer its lot|E_NOT_OFFERED/],
  ['knob 0 does not close it', (s) => swap(s, `then greatest(0, public.wc_int('works_open_shares') - w.subscribed)\n`, `then greatest(0, 100 - w.subscribed)\n`), /knob 0 is not the pre-image/],
  ['a finished work\'s level rises', (s) => swap(s, `update public.city_works set level = least(level + 1, v_max), subscribed = 0`, `update public.city_works set level = level + 1, subscribed = 0`), /a lot of a finished work/],
  ['the receipt says a level was built', (s) => swap(s, `v_done := w.level < v_max;`, `v_done := true;`), /a lot of a finished work/],
  ['the event says level six', (s) => swap(s, `'level', least(w.level + 1, v_max)));`, `'level', w.level + 1));`), /a lot of a finished work/],
  ['a lot never closes', (s) => swap(s, `  if p_shares >= v_offer then\n`, `  if false then\n`), /a lot of a finished work|an unfinished work did not complete|E_NOT_OFFERED/],
  ['the hall serves no price', (s) => swap(s, ` or public.city_offered(p_port, k.kind) > 0   -- 0313: a finished work still selling`, `   -- 0313: a finished work still selling`), /the hall does not serve a finished work/],
  ['every hour is her hour', (s) => swap(s, `h.roster_ord % 24 <> extract(hour from p_now at time zone 'UTC')::int`, `false`), /a budget outside her hour/],
  ['the cap is not divided', (s) => swap(s, `least(v_cap / greatest(v_n, 1),`, `least(v_cap,`), /the budget is not her equal part/],
  ['her laps are not kept', (s) => swap(s, `public.wc_num('npc_invest_keep_laps') * v_lap`, `0 * v_lap`), /working cash/],
  ['her capital is not kept', (s) => swap(s, `greatest(public.wc_num('npc_invest_keep') * h.capital,\n`, `greatest(0,\n`), /npc_invest_keep x capital/],
  ['an old lap counts', (s) => swap(s, `x.closed_at > p_now - interval '3 days'`, `x.closed_at > p_now - interval '30 days'`), /the budget is not her equal part|working cash/],
  ['the race ignores her budget', (s) => swap(s, `floor(v_budget / v_stake.price)`, `floor(v_left / v_stake.price)`), /outside her hour the race is not what it was/],
  ['the route ignores her budget', (s) => swap(s, `floor(v_budget / v_pick.price)`, `floor((hi.ducats - public.wc_num('npc_invest_keep') * hi.capital) / v_pick.price)`), /the stake is not what her budget bought/],
  ['a client can read her budget', (s) => swap(s, `  revoke all on function public.npc_share_budget(timestamptz, uuid, bigint) from public, anon, authenticated;\n`, `  grant execute on function public.npc_share_budget(timestamptz, uuid, bigint) to authenticated;\n`), /a client can reach/],
  ['the default cap is wrong', (s) => swap(s, `('npc_invest_day_cap', to_jsonb(100000000),`, `('npc_invest_day_cap', to_jsonb(1000000000),`), /a knob is not at its default/],
  ['a hunk against another body', (s) => swap(s, `$h$  v_gave     boolean;\n$h$,\n$h$      -- 0145`, `$h$  v_gave    boolean;\n$h$,\n$h$      -- 0145`), /occurs 0 time/],
  ['a live function was touched', (s) => addBeforeAssert(s,
    `  execute replace(replace(pg_get_functiondef('public.crown_call_room(uuid)'::regprocedure), E'\\r', ''), 'select greatest(0,', 'select greatest(0 ,');`),
    /a function outside this file moved/],
  ['a live knob was touched', (s) => addBeforeAssert(s, `  update public.world_config set value = to_jsonb(6) where key = 'works_level_max';`), /a knob outside this file moved/],
]

async function attempt(sql, after) {
  const notices = []
  const t = performance.now()
  await db.exec('begin')
  try {
    await db.exec(sql, { onNotice: (n) => notices.push(n.message ?? String(n)) })
    const ms = performance.now() - t
    if (after) await db.exec(after, { onNotice: (n) => notices.push(n.message ?? String(n)) })
    return { ok: true, error: null, notices, ms, all: performance.now() - t }
  } catch (e) {
    return { ok: false, error: String(e?.message ?? e), notices, ms: performance.now() - t }
  } finally {
    await db.exec('rollback')
  }
}

const only = process.argv[2]
if (only !== 'green') {
  for (const [what, mutate, why] of MUTATIONS) {
    const r = await attempt(mutate(file))
    const good = !r.ok && why.test(r.error)
    if (!good) failures.push(what)
    say(`${good ? 'RED, as it must be' : 'FAIL'}  ${what}\n    ${r.ok ? 'it passed' : r.error.slice(0, 260)}`)
  }
}

const green = await attempt(file, proof)
if (!green.ok) failures.push(`the real file: ${green.error}`)
say(`\n${green.ok ? 'GREEN' : 'FAIL'}  the real file, ${Math.round(green.ms)} ms, with proof 21 ${Math.round(green.all ?? 0)} ms\n    ${green.ok ? green.notices.filter((n) => /self-assert ok|PASS:/.test(n)).join('\n    ') : green.error}`)

await db.close()
if (failures.length) {
  say(`\n${failures.length} FAILED:\n  ${failures.join('\n  ')}`)
  process.exit(1)
}
say(only === 'green' ? '\nthe real file green' : `\nall ${MUTATIONS.length} mutations red, the real file green`)
