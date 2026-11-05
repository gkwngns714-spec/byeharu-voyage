// ═════════════════════════════════════════════════════════════════
// proof-0316.mjs — GRAPHS BY DAY, WEEK AND MONTH (migration 0316): the red-first proof. LOCAL ONLY (PGlite); not in CI.
// ═════════════════════════════════════════════════════════════════
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/history/proof-0316.mjs
//
// Restores the cached world at the head before 0316 (never from zero), then applies 0316 to it several times inside a transaction that is rolled back:
//   MUTATION CONTROLS - deliberate breakages of the file, each required to FAIL its self-assert, or proof 25 run right after it, for the intended reason;
//   POSITIVE CONTROL  - the real file followed by proof 25, which must pass and print their receipts.
// The harness reads the migration from supabase/migrations; it does not edit it.

import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { migrationFiles, MIGRATIONS_DIR, PREFIX_CACHE_DIR, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const NAME = '20260818000316_graphs_by_day_week_and_month.sql'
const PROOF = 'scripts/db/proofs/25_history.sql'
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

const MUTATIONS = [
  ['a week starts on Sunday', (s) => swap(s, `return date_trunc('week', p_day::timestamp)::date;`, `return (date_trunc('week', p_day::timestamp + interval '1 day') - interval '1 day')::date;`),
    /a period is not Monday to Sunday/],
  ['a bad period reads as a day', (s) => swap(s, `  raise exception 'E_BAD_PERIOD: a graph is by day, week or month, not %', coalesce(p_period, 'null') using errcode = 'P0001';\n`, `  return p_day;\n`),
    /a year was accepted/],
  ['a state takes the day\'s first row', (s) => swap(s, `select p_day,\n         (array_agg(w.players order by w.at desc))[1]`, `select p_day,\n         (array_agg(w.players order by w.at))[1]`),
    /a state is not the day's last|a state is not the day''s last/],
  ['midnight belongs to the day before', (s) => swap(s, `where w.at >= v_lo and w.at < v_hi`, `where w.at > v_lo and w.at <= v_hi`),
    /a state is not the day|midnight does not start/],
  ['a city\'s purse is the highest of the day', (s) => swap(s, `select c.port_id, p_day, (array_agg(c.purse order by c.at desc))[1],`, `select c.port_id, p_day, max(c.purse) + 1,`),
    /a city's day is wrong|a city''s day is wrong/],
  ['profit counts crown aid', (s) => swap(s, `from jsonb_each_text(c.flows) e where public.flow_is_profit(e.key)`, `from jsonb_each_text(c.flows) e`),
    /not by public.flow_is_profit/],
  ['profit is income less spending', (s) => swap(s, `coalesce(sum((select sum(e.value::numeric) from jsonb_each_text(c.flows) e where public.flow_is_profit(e.key))), 0)::bigint`, `(sum(c.income) - sum(c.spending))::bigint`),
    /not by public.flow_is_profit/],
  ['a null price closes the day', (s) => swap(s, `(array_agg(g.mid order by g.at desc) filter (where g.mid is not null))[1],`, `(array_agg(g.mid order by g.at desc))[1],`),
    /not open, high, low, close/],
  ['the high is the last price', (s) => swap(s, `filter (where g.mid is not null))[1], max(g.mid), min(g.mid),`, `filter (where g.mid is not null))[1], min(g.mid), min(g.mid),`),
    /not open, high, low, close/],
  ['a recount rewrites every row', (s) => swap(s, `   where (t.purse, t.income, t.spending, t.profit) is distinct from (excluded.purse, excluded.income, excluded.spending, excluded.profit);\n`, `   ;\n`),
    /a recount rewrote/],
  ['the thinned days draw a flow', (s) => swap(s, `c_flows_from constant date := date '2026-10-23';`, `c_flows_from constant date := date '2000-01-01';`),
    /a thinned day drew a flow/],
  ['a week adds purses', (s) => swap(s, `select public.history_bucket(h.day, p_period) as b, (array_agg(h.purse order by h.day desc))[1] as purse,`, `select public.history_bucket(h.day, p_period) as b, sum(h.purse)::bigint as purse,`),
    /a city's week is not its days|a city''s week is not its days/],
  ['a week closes on its first day', (s) => swap(s, `(array_agg(h.close order by h.day desc) filter (where h.close is not null))[1] as close,`, `(array_agg(h.close order by h.day) filter (where h.close is not null))[1] as close,`),
    /a good's week|a good''s week/],
  ['a week\'s high is its last day\'s', (s) => swap(s, `as open, max(h.high) as high, min(h.low) as low,`, `as open, min(h.high) as high, min(h.low) as low,`),
    /a good's week|a good''s week/],
  ['the carried row counts', (s) => swap(s, `select p_kind not in ('FOUNDING', 'NPC_REFOUND', 'NPC_CARRIED') and`, `select p_kind not in ('FOUNDING', 'NPC_REFOUND') and`),
    /money in and out/],
  ['capital counts as earned', (s) => swap(s, `select p_kind not in ('FOUNDING', 'NPC_REFOUND', 'NPC_CARRIED') and`, `select p_kind not in ('NPC_REFOUND', 'NPC_CARRIED') and`),
    /money in and out/],
  ['a loss is added as a gain', (s) => swap(s, `coalesce(-sum(l.ducats_delta) filter (where l.ducats_delta < 0), 0)::bigint`, `coalesce(sum(l.ducats_delta) filter (where l.ducats_delta < 0), 0)::bigint`),
    /money in and out/],
  ['the window takes its open end', (s) => swap(s, `where l.created_at > p_from and l.created_at <= p_to`, `where l.created_at >= p_from and l.created_at <= p_to`),
    /a window took a row at its open end/],
  ['the window replaces instead of adding', (s) => swap(s, `set earned = t.earned + excluded.earned, lost = t.lost + excluded.lost;`, `set earned = excluded.earned, lost = excluded.lost;`),
    /a window replaced the day/],
  ['the mark does not move: every run adds the ledger again', (s) => swap(s, `    m.ledger_through := v_hi;\n`, ``),
    /PROOF 25 FAIL: a ledger row did not count exactly once/],
  ['no lag', (s) => swap(s, `v_hi    timestamptz := p_now - make_interval(secs => public.wc_num('history_ledger_lag_seconds')::double precision);`, `v_hi    timestamptz := p_now;`),
    /PROOF 25 FAIL: a run read a ledger row inside the lag/],
  ['the backfill never moves', (s) => swap(s, `    v_open := v_open + 1;\n`, ``),
    /PROOF 25 FAIL: the backfill does not end/],
  ['a run starts at today, no backfill', (s) => swap(s, `v_open := least(coalesce(m.open_day, (select (w.at at time zone 'UTC')::date from public.stats_world w order by w.at limit 1), v_today), v_today);`, `v_open := least(coalesce(m.open_day, v_today), v_today);`),
    /PROOF 25 FAIL: a first run did not start at the oldest count/],
  ['the job writes the ledger', (s) => swap(s, `  update public.history_mark set ledger_through = m.ledger_through, open_day = v_open;\n`, `  update public.history_mark set ledger_through = m.ledger_through, open_day = v_open;\n  perform public.credit((select p.id from public.players p where p.company_name = 'Proof 25 house'), 'SELL', 1);\n`),
    /PROOF 25 FAIL/],
  ['the trim ships on', (s) => swap(s, `('stats_city_good_keep_days', to_jsonb(0),`, `('stats_city_good_keep_days', to_jsonb(3),`),
    /the trim does not ship off|the trim ran at 0/],
  ['the trim ignores the 3-day floor', (s) => swap(s, `make_interval(days => greatest(v_keep, 3))`, `make_interval(days => v_keep)`),
    /the trim went under 3 days/],
  ['a player reads another player\'s books', (s) => swap(s, `where p.company_name = p_subject and p.is_npc;`, `where p.company_name = p_subject;`),
    /a player's books were served|a player''s books were served/],
  ['anyone may run the job', (s) => swap(s, `  grant execute on function world.history(text, text, text) to authenticated;\n`, `  grant execute on function world.history(text, text, text) to authenticated;\n  grant execute on function public.tick_history(timestamptz) to authenticated;\n`),
    /a client can run the job/],
  ['the read is open to the signed-out', (s) => swap(s, `  grant execute on function world.history(text, text, text) to authenticated;\n`, `  grant execute on function world.history(text, text, text) to anon, authenticated;\n`),
    /not for signed-in players alone/],
  ['a table is open to clients', (s) => swap(s, `  alter table public.history_company_day enable row level security;\n`, ``),
    /a client can reach a history table/],
  ['a knob outside the list moved', (s) => swap(s, `  -- ── 3. THE RULE OF A PERIOD ──\n`, `  update public.world_config set updated_at = now() - interval '1 day' where key = 'stats_fine_hours';\n  -- ── 3. THE RULE OF A PERIOD ──\n`),
    /a world_config row moved/],
  ['tick_stats was touched', (s) => swap(s, `  -- ── 3. THE RULE OF A PERIOD ──\n`, `  execute replace(pg_get_functiondef('public.tick_stats(timestamptz)'::regprocedure), 'declare\n  v_t0 ', 'declare\n  v_new int;\n  v_t0 ');\n  -- ── 3. THE RULE OF A PERIOD ──\n`),
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

const green = await attempt(`${file}\n${proof}`)
if (!green.ok) failures.push(`the real file: ${green.error}`)
say(`\n${green.ok ? 'GREEN' : 'FAIL'}  the real file and proof 25, ${Math.round(green.ms)} ms\n    ${green.ok ? green.notices.filter((n) => /self-assert ok|PASS:/.test(n)).join('\n    ') : green.error.slice(0, 600)}`)

if (green.ok) {
  for (const [what, mutate, why] of MUTATIONS) {
    const r = await attempt(`${mutate(file)}\n${proof}`)
    const good = !r.ok && why.test(r.error)
    if (!good) failures.push(what)
    say(`${good ? 'RED, as it must be' : 'FAIL'}  ${what}\n    ${r.ok ? 'it passed' : r.error.slice(0, 260)}`)
  }
}

await db.close()
if (failures.length) {
  say(`\n${failures.length} FAILED:\n  ${failures.join('\n  ')}`)
  process.exit(1)
}
say(`\nall ${MUTATIONS.length} mutations red, the real file green`)
