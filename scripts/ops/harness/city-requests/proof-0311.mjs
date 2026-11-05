// ═════════════════════════════════════════════════════════════════
// proof-0311.mjs — A REQUEST STANDS A DAY (migration 0311): the red-first proof. LOCAL ONLY (PGlite); not in CI.
// ═════════════════════════════════════════════════════════════════
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/city-requests/proof-0311.mjs
//
// Restores the cached world (never from zero), then applies 0311 to it several times inside rolled-back transactions:
//   MUTATION CONTROLS - deliberate breakages of the file, each required to FAIL its self-assert for the intended reason;
//   POSITIVE CONTROL  - the real file, which must pass and print its receipt.
// The harness reads the migration from supabase/migrations; it does not edit it.

import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { migrationFiles, MIGRATIONS_DIR, PREFIX_CACHE_DIR, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const NAME = '20260818000311_a_request_stands_a_day.sql'
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
  return sql.replace(from, () => to)
}

const BEFORE_ASSERT = `  -- ── 4. THE SELF-ASSERT: hunks, grants, nothing else moved ──\n`
const addBeforeAssert = (s, sql) => swap(s, BEFORE_ASSERT, `${sql}\n${BEFORE_ASSERT}`)

const MUTATIONS = [
  ['the cap is ignored', (s) => swap(s, `status = 'open') >= v_max then\n    return 0;\n  end if;\n  select min(s) into v_s`, `status = 'open') >= v_max + 9 then\n    return 0;\n  end if;\n  select min(s) into v_s`),
    /did not hold/],
  ['the budget ignores the knob', (s) => swap(s, `least(public.wc_int('contract_budget')::bigint, v_share) else v_lot end`, `v_share else v_lot end`),
    /not the knob's budget/],
  ['the budget ignores the surplus', (s) => swap(s, `least(public.wc_int('contract_budget')::bigint, v_share) else v_lot end`, `public.wc_int('contract_budget')::bigint else v_lot end`),
    /under the lot posted|not surplus|E_CITY_BROKE/],
  ['no minimum', (s) => swap(s, `  if v_budget < v_lot then\n    return 0;   -- a budget that cannot pay for the drawn lot does not post\n  end if;\n`, ``),
    /under the lot posted/],
  ['the budget is not escrowed', (s) => swap(s, `      perform public.treasury_post(p_port, 'BOUNTY', -v_budget, null, null);\n`, `      null;\n`),
    /did not leave the purse/],
  ['the old deadline stands', (s) => swap(s, `     set value = to_jsonb(1440),`, `     set value = to_jsonb(4),`), /knobs are not this file's/],
  ['the read serves no price', (s) => swap(s, `        'price_each', round(q.bid + c.premium_per_unit, 2),\n`, ``), /does not serve the row/],
  ['the read serves the mid for the sale', (s) => swap(s, `        'sale_price', q.bid,\n`, `        'sale_price', q.mid,\n`), /does not serve the row/],
  ['the read serves the lot, not what is left', (s) => swap(s, `        'qty', floor(c.premium_ducats / c.premium_per_unit),\n`, `        'qty', c.qty,\n`), /does not show what is left/],
  ['the whole lot is still demanded', (s) => swap(s, `  if floor(v_have) < 1 then\n`, `  if v_have < c.qty then\n`), /a part did not land|dry run of a part/],
  ['an empty hold passes', (s) => swap(s, `  if floor(v_have) < 1 then\n`, `  if false then\n`), /empty hold|manifest|E_MANIFEST/],
  ['the budget does not fall', (s) => swap(s, `       set premium_ducats = v_rest, escrow = greatest(escrow - v_pay, 0)\n`, `       set escrow = greatest(escrow - v_pay, 0)\n`),
    /did not fall by the bonus/],
  ['the escrow does not fall', (s) => swap(s, `       set premium_ducats = v_rest, escrow = greatest(escrow - v_pay, 0)\n`, `       set premium_ducats = v_rest\n`),
    /did not fall by the bonus/],
  ['the bonus is doubled', (s) => swap(s, `  perform public.credit(f.player_id, 'PREMIUM', v_pay, v_event);\n`, `  perform public.credit(f.player_id, 'PREMIUM', 2 * v_pay, v_event);\n`),
    /made or lost money/],
  ['a delivery is not cut to the budget', (s) => swap(s, `  v_qty := least(floor(v_have), v_left);\n`, `  v_qty := floor(v_have);\n`), /not cut|violates|check constraint/],
  ['a delivery is not cut to the allowance', (s) => swap(s, `    v_qty := least(v_qty, floor(v_cap));\n`, `    null;\n`), /allowance did not cut/],
  ['a spent request stays open', (s) => swap(s, `    update public.trade_contracts set status = 'spent', premium_ducats = 0, escrow = 0 where id = c.id;\n`, `    update public.trade_contracts set premium_ducats = 0, escrow = 0 where id = c.id;\n`),
    /did not close/],
  ['the odd coin is kept', (s) => swap(s, `      perform public.treasury_post(c.port_id, 'BOUNTY_LAPSED', c.escrow - v_pay, null, null, true);\n`, `      null;\n`),
    /odd coin did not go home/],
  ['a spent request takes a delivery', (s) => swap(s, `  if c.status in ('fulfilled', 'spent') or (c.status = 'open' and v_left < 1) then\n`, `  if c.status = 'fulfilled' then\n`), /spent request took a delivery|E_MANIFEST|empty hold/],
  ['the report files the bonus nowhere', (s) => swap(s, `case when k.kind in ('SELL', 'PREMIUM', 'BUY', 'TAX', 'PORT_FEE') then 'trade'`, `case when k.kind in ('SELL', 'BUY', 'TAX', 'PORT_FEE') then 'trade'`),
    /does not show the bonus/],
  ['the report has no word', (s) => swap(s, `('SELL', 'Sold', 1), ('PREMIUM', 'Bonus', 1), ('BUY'`, `('SELL', 'Sold', 1), ('BUY'`), /does not show the bonus/],
  ['the words are not renamed', (s) => swap(s, `  update public.stats_flow_words set word = 'Bonus returned' where kind = 'BOUNTY_LAPSED';\n`, ``), /words of the books/],
  ['paid counts the wrong kind', (s) => swap(s, `where l.kind = 'PREMIUM' and l.created_at > p_since`, `where l.kind = 'SELL' and l.created_at > p_since`), /do not reconcile/],
  ['held counts closed rows too', (s) => swap(s, `from public.trade_contracts c where c.status = 'open' and (p_port is null`, `from public.trade_contracts c where (p_port is null`), /do not reconcile/],
  ['a helper is open to clients', (s) => swap(s, `  revoke all on function public.bonus_figures(uuid, timestamptz) from public, anon, authenticated;\n`, `  grant execute on function public.bonus_figures(uuid, timestamptz) to authenticated;\n`),
    /a client can reach the helper/],
  ['a hunk against another body', (s) => swap(s, `$h$        'qty', c.qty,\n$h$,`, `$h$        'qty', c.qty ,\n$h$,`), /occurs 0 time/],
  ['a live function was touched', (s) => addBeforeAssert(s,
    `  execute replace(replace(pg_get_functiondef('public.crown_call_room(uuid)'::regprocedure), E'\\r', ''), 'select greatest(0,', 'select greatest(0 ,');`),
    /another function moved/],
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

const green0 = await attempt(file)
if (!green0.ok) {
  say(`FAIL  the real file, before any mutation: ${green0.error}`)
  await db.close()
  process.exit(1)
}
say(`the real file is green first, ${Math.round(green0.ms)} ms`)

for (const [what, mutate, why] of MUTATIONS) {
  const r = await attempt(mutate(file))
  const good = !r.ok && why.test(r.error)
  if (!good) failures.push(what)
  say(`${good ? 'RED, as it must be' : 'FAIL'}  ${what}\n    ${r.ok ? 'it passed' : r.error.slice(0, 260)}`)
}

const green = await attempt(file)
if (!green.ok) failures.push(`the real file: ${green.error}`)
say(`\n${green.ok ? 'GREEN' : 'FAIL'}  the real file, ${Math.round(green.ms)} ms\n    ${green.ok ? green.notices.find((n) => n.includes('self-assert ok')) : green.error}`)

// THE SECOND POSITIVE CONTROL: a local world is dark, prod is lit and closed. The real file on a world set as prod is.
const lit = await attempt(`
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed');
  update public.world_config set value = to_jsonb(50000) where key = 'treasury_reserve_floor';
  update public.world_config set value = to_jsonb(60) where key = 'game_day_seconds';
  ${file}`)
if (!lit.ok) failures.push(`the real file, lit: ${lit.error}`)
say(`${lit.ok ? 'GREEN' : 'FAIL'}  the real file on a lit, closed world, ${Math.round(lit.ms)} ms\n    ${lit.ok ? lit.notices.find((n) => n.includes('self-assert ok')) : lit.error}`)

await db.close()
if (failures.length) {
  say(`\n${failures.length} FAILED:\n  ${failures.join('\n  ')}`)
  process.exit(1)
}
say(`\nall ${MUTATIONS.length} mutations red, the real file green`)
