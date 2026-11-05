// ═════════════════════════════════════════════════════════════════
// proof-0312.mjs — DIVIDENDS ARE PAID FROM PROFIT (migration 0312): the red-first proof. LOCAL ONLY (PGlite); not in CI.
// ═════════════════════════════════════════════════════════════════
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/dividends/proof-0312.mjs
//
// Restores the cached world at the head before 0312 (never from zero), then applies 0312 to it several times inside a transaction that is rolled back:
//   MUTATION CONTROLS - deliberate breakages of the file, each required to FAIL its self-assert, or proof 22 run right after it, for the intended reason;
//   POSITIVE CONTROL  - the real file followed by proof 22, which must pass and print their receipts.
// The harness reads the migration from supabase/migrations; it does not edit it.

import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { migrationFiles, MIGRATIONS_DIR, PREFIX_CACHE_DIR, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const NAME = '20260818000312_dividends_are_paid_from_profit.sql'
const PROOF = 'scripts/db/proofs/22_dividends.sql'
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
  return sql.replace(from, to)
}

const DUE = `round(s.paid * v_rate * least(v_rday - v_last, greatest(0, (v_today - s.accrued_day) * v_gds / 86400))`
const PAYABLE = `least(coalesce(sum(d.due), 0), greatest(0, public.city_surplus(p_port)), greatest(0, v_profit))::bigint as payable`

const MUTATIONS = [
  ['no profit limit (the bug itself)', (s) => swap(s, PAYABLE,
    `least(coalesce(sum(d.due), 0), greatest(0, public.city_surplus(p_port)))::bigint as payable`),
    /limited by the day''s profit|limited by the day's profit|a loss paid/],
  ['the rate is per game day: the clock moves it', (s) => swap(s, DUE,
    `round(s.paid * v_rate * least(v_rday - v_last, greatest(0, (v_today - s.accrued_day) * 1 / 1440::numeric))`),
    /the clock moved the rate/],
  ['the day number is not capped: a clock change sweeps the purse', (s) => swap(s, DUE,
    `round(s.paid * v_rate * greatest(0, (v_today - s.accrued_day) * v_gds / 86400)`),
    /swept the purse/],
  ['the day number is not floored: a stamp in the future', (s) => swap(s, DUE,
    `round(s.paid * v_rate * least(v_rday - v_last, abs((v_today - s.accrued_day) * v_gds / 86400))`),
    /a stamp in the future paid/],
  ['the surplus no longer limits', (s) => swap(s, PAYABLE,
    `least(coalesce(sum(d.due), 0), greatest(0, v_profit))::bigint as payable`),
    /the surplus no longer limits|E_CITY_BROKE/],
  ['a loss is carried as a debt to tomorrow', (s) => swap(s,
    `update public.port_treasury t set profit = 0, coupon_day = v_rday where t.port_id = p_port;`,
    `update public.port_treasury t set profit = least(0, v_profit), coupon_day = v_rday where t.port_id = p_port;`),
    /the period did not close/],
  ['the profit is not reset after paying', (s) => swap(s,
    `update public.port_treasury t set profit = 0, coupon_day = v_rday where t.port_id = p_port;`,
    `update public.port_treasury t set coupon_day = v_rday where t.port_id = p_port;`),
    /the period did not close/],
  ['the shortfall accrues as a debt', (s) => swap(s,
    `update public.city_shares s set accrued = s.accrued + a.pay, accrued_day = v_today\n      from a where s.port_id = p_port`,
    `update public.city_shares s set accrued = s.accrued + a.due, accrued_day = v_today\n      from a where s.port_id = p_port`),
    /is not what the rows were credited/],
  ['old accrued is wiped', (s) => swap(s,
    `update public.city_shares s set accrued = s.accrued + a.pay, accrued_day = v_today\n      from a where s.port_id = p_port`,
    `update public.city_shares s set accrued = a.pay, accrued_day = v_today\n      from a where s.port_id = p_port`),
    /is not what the rows were credited/],
  ['a harbour pays twice a day', (s) => swap(s,
    `  if v_last is null or v_last >= v_rday then\n    return jsonb_build_object('paid', 0, 'due', 0);\n  end if;\n`,
    `  v_last := v_rday - 1;\n`),
    /a second pass paid|two missed days are not two coupons/],
  ['crown aid counts as profit', (s) => swap(s,
    `select p_kind not in ('CROWN_AID', 'CROWN_CALL',`, `select p_kind not in ('CROWN_CALL',`),
    /aid, capital or a dividend counts as profit/],
  ['aid by cargo ship counts as profit', (s) => swap(s,
    `'DIVIDEND', 'CONVOY_LOAD', 'CONVOY_DELIVER', 'CONVOY_RETURN', 'SHARE')\n$body$`, `'DIVIDEND', 'CONVOY_LOAD', 'CONVOY_RETURN', 'SHARE')\n$body$`),
    /aid, capital or a dividend counts as profit/],
  ['share money counts as profit', (s) => swap(s,
    `'CONVOY_RETURN', 'SHARE')\n$body$`, `'CONVOY_RETURN')\n$body$`),
    /aid, capital or a dividend counts as profit/],
  ['a donation does not count', (s) => swap(s,
    `'CONVOY_RETURN', 'SHARE')\n$body$`, `'CONVOY_RETURN', 'SHARE', 'DONATION')\n$body$`),
    /a city's own trade is not profit|a city''s own trade is not profit/],
  ['the wrong rate', (s) => swap(s, `to_jsonb(0.09)`, `to_jsonb(0.003)`),
    /a real day is not 9 %|the knob is not at its default/],
  ['the roll does not add profit', (s) => swap(s,
    `           profit = t.profit + s.earned,   -- 0312: what public.city_coupons may pay out; the daybook keeps too few days to say\n`, ``),
    /PROOF 22 FAIL: a city did not pay exactly what it earned/],
  ['the roll adds every flow, aid too', (s) => swap(s,
    `coalesce(sum(f.ducats) filter (where public.flow_is_profit(f.kind)), 0) as earned`, `coalesce(sum(f.ducats), 0) as earned`),
    /PROOF 22 FAIL: aid leaked out as a dividend|PROOF 22 FAIL: a city did not pay/],
  ['tick_city pays every hour', (s) => swap(s,
    `      for hp in select t.port_id from public.port_treasury t where t.coupon_day < v_rday order by t.port_id loop\n        v_c := public.city_coupons(hp.port_id, p_now);`,
    `      for hp in select t.port_id from public.port_treasury t order by t.port_id loop\n        update public.port_treasury t set coupon_day = v_rday - 1 where t.port_id = hp.port_id;\n        v_c := public.city_coupons(hp.port_id, p_now);`),
    /PROOF 22 FAIL/],
  ['a hunk was cut against a body that is not the live one', (s) => swap(s,
    `$h$  -- 6. COUPONS (0123, lit): each row's due since its coupon day; a city pays what it holds above\n`,
    `$h$  -- 6. COUPONS  (0123, lit): each row's due since its coupon day; a city pays what it holds above\n`),
    /hunk 3 of public.tick_city occurs 0/],
  ['a hunk does not reverse: the new body gained a line no hunk knows', (s) => swap(s,
    `  execute v_def;\n\n  -- ── 5.`,
    `  execute replace(v_def, 'v_inns     int := 0;', 'v_inns     int := 0; -- drift');\n\n  -- ── 5.`),
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
  const r = await attempt(`${mutate(file)}\n${proof}`)
  const good = !r.ok && why.test(r.error)
  if (!good) failures.push(what)
  say(`${good ? 'RED, as it must be' : 'FAIL'}  ${what}\n    ${r.ok ? 'it passed' : r.error.slice(0, 260)}`)
}

const green = await attempt(`${file}\n${proof}`)
if (!green.ok) failures.push(`the real file: ${green.error}`)
say(`\n${green.ok ? 'GREEN' : 'FAIL'}  the real file and proof 22, ${Math.round(green.ms)} ms\n    ${green.ok ? green.notices.filter((n) => /self-assert ok|PASS:/.test(n)).join('\n    ') : green.error}`)

await db.close()
if (failures.length) {
  say(`\n${failures.length} FAILED:\n  ${failures.join('\n  ')}`)
  process.exit(1)
}
say(`\nall ${MUTATIONS.length} mutations red, the real file green`)
