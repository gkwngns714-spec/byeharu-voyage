// ═════════════════════════════════════════════════════════════════
// proof-0306.mjs — A BROKE CITY IS SHORT (migration 0306): the red-first proof. LOCAL ONLY (PGlite); not in CI.
// ═════════════════════════════════════════════════════════════════
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/reserve-floor/proof-0306.mjs
//
// Restores the cached world at head 0305 (never from zero), then applies 0306 to it several times inside savepoints:
//   MUTATION CONTROLS - deliberate breakages of the file, each required to FAIL its self-assert for the intended reason;
//   POSITIVE CONTROL  - the real file, which must pass and print its receipt.
// The harness reads the migration from supabase/migrations; it does not edit it.

import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { migrationFiles, MIGRATIONS_DIR, PREFIX_CACHE_DIR, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const NAME = '20260818000306_a_broke_city_is_short.sql'
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

const MUTATIONS = [
  ['the floor is ignored (the bug itself)', (s) => swap(s,
    `greatest(coalesce((select t.reserve from public.port_treasury t where t.port_id = p_port), 0),
                  round(public.wc_num('treasury_reserve_floor')))::bigint`,
    `coalesce((select t.reserve from public.port_treasury t where t.port_id = p_port), 0)::bigint`),
    /target is not greatest/],
  ['the floor goes into public.treasury_reserve, so a sale pays less', (s) => swap(s,
    `  -- ── 3. THE AID, MOVED OUT OF public.city_day ──`,
    `  execute $x$create or replace function public.treasury_reserve(p_port uuid) returns bigint language sql stable security definer set search_path = public, pg_temp
       as $y$ select greatest(public.wc_num('treasury_reserve_floor'), round(public.wc_num('treasury_reserve_days') * public.city_sell_outflow(p_port)))::bigint $y$ $x$;`),
    /another function moved/],
  ['a capital gives its whole purse, below its reserve', (s) => swap(s,
    `greatest(0, public.city_surplus(r.cap)));
    if v_a > 0 then
      perform public.treasury_post(r.cap, 'CROWN_AID', -v_a, null, null);
      perform public.treasury_post(r.port_id, 'CROWN_AID', v_a, null, null);
      v_aided := v_aided + 1;
      v_aid := v_aid + v_a;
    end if;
  end loop;
  return`,
    `greatest(0, public.treasury_balance(r.cap)));
    if v_a > 0 then
      perform public.treasury_post(r.cap, 'CROWN_AID', -v_a, null, null);
      perform public.treasury_post(r.port_id, 'CROWN_AID', v_a, null, null);
      v_aided := v_aided + 1;
      v_aid := v_aid + v_a;
    end if;
  end loop;
  return`),
    /did not stop exactly at its reserve/],
  ['the capital does not pay: gold is minted', (s) => swap(s,
    `      perform public.treasury_post(r.cap, 'CROWN_AID', -v_a, null, null);
      perform public.treasury_post(r.port_id, 'CROWN_AID', v_a, null, null);
      v_aided := v_aided + 1;
      v_aid := v_aid + v_a;
    end if;
  end loop;
  return`,
    `      perform public.treasury_post(r.port_id, 'CROWN_AID', v_a, null, null);
      v_aided := v_aided + 1;
      v_aid := v_aid + v_a;
    end if;
  end loop;
  return`),
    /the sum of purses moved/],
  ['a floor of 0 is not today: every city is short by 1', (s) => swap(s,
    `round(public.wc_num('treasury_reserve_floor')))::bigint`,
    `1 + round(public.wc_num('treasury_reserve_floor')))::bigint`),
    /target is not greatest/],
  ['the top-up overshoots the target', (s) => swap(s,
    `v_a := least(r.target - public.treasury_balance(r.port_id), greatest`,
    `v_a := least(r.target + 1 - public.treasury_balance(r.port_id), greatest`),
    /floor of 0 is not today/],
  ['a hunk was cut against a body that is not the live one', (s) => swap(s,
    `$h$                            'aided', v_aided, 'aid', v_aid);
$h$];`,
    `$h$                            'aided', v_aided,  'aid', v_aid);
$h$];`),
    /hunk 5 of public.city_day occurs 0/],
  ['a hunk does not reverse: the new body gained a line no hunk knows', (s) => swap(s,
    `  execute v_def;

  -- ── 5.`,
    `  execute replace(v_def, 'v_cities := v_cities + 1;', 'v_cities := v_cities + 1; -- drift');

  -- ── 5.`),
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
  say(`${good ? 'RED, as it must be' : 'FAIL'}  ${what}\n    ${r.ok ? 'it passed' : r.error.slice(0, 230)}`)
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
