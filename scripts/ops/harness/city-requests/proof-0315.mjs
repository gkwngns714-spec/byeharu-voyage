// ═════════════════════════════════════════════════════════════════
// proof-0315.mjs — MERCHANTS ANSWER REQUESTS (migration 0315): the red-first proof. LOCAL ONLY (PGlite); not in CI.
// ═════════════════════════════════════════════════════════════════
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/city-requests/proof-0315.mjs
//
// Restores the cached world (never from zero), then applies 0315 to it several times inside rolled-back transactions:
//   MUTATION CONTROLS - deliberate breakages of the file, each required to FAIL its self-assert for the intended reason;
//   POSITIVE CONTROL  - the real file, dark and on a world set as prod is (lit, closed), then the job as cron runs it, with real commits.
// The harness reads the migration from supabase/migrations; it does not edit it.

import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { migrationFiles, MIGRATIONS_DIR, PREFIX_CACHE_DIR, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const NAME = '20260818000315_merchants_answer_requests.sql'
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

const BEFORE_ASSERT = `  -- ── 5. THE SELF-ASSERT: hunks, grants, nothing else moved ──\n`
const addBeforeAssert = (s, sql) => swap(s, BEFORE_ASSERT, `${sql}\n${BEFORE_ASSERT}`)

const MUTATIONS = [
  // the door
  ['the SELL does not go through the new door', (s) => swap(s, `then cmd.do_sell_answering(o.fleet_id, o.args, o.route_lap_id)   -- 0315: a merchant's route SELL answers requests first\n`, `then cmd.do_sell(o.fleet_id, o.args)   -- 0315 x\n`),
    /did not deliver/],
  ['merchants do not wait the knob', (s) => swap(s, `     and c.created_at <= now() - make_interval(secs => (public.wc_num('contract_npc_after_hours') * 3600)::double precision)\n`, ``),
    /younger than the knob/],
  ['players answer too', (s) => swap(s, `  if f.status <> 'DOCKED' or not exists (select 1 from public.players p where p.id = f.player_id and p.is_npc) then\n`, `  if f.status <> 'DOCKED' then\n`),
    /a player's route answered/],
  ['an ordered sale answers', (s) => swap(s, `  if p_lap is null or p_args->>'qty' is not null then\n`, `  if p_args->>'qty' is not null then\n`), /an ordered sale answered/],
  ['a set quantity answers', (s) => swap(s, `  if p_lap is null or p_args->>'qty' is not null then\n`, `  if p_lap is null then\n`), /a set quantity answered/],
  ['the floor is ignored', (s) => swap(s, `    continue when v_limit is not null and coalesce(q.avg_price, 0) + a.per_unit < v_limit;\n`, ``), /under her floor/],
  ['the floor ignores the bonus', (s) => swap(s, `coalesce(q.avg_price, 0) + a.per_unit < v_limit;`, `coalesce(q.avg_price, 0) < v_limit;`), /did not lift the sale/],
  ['the rest is not sold', (s) => swap(s, `      v_rest := cmd.do_sell(p_fleet, p_args);\n    exception when others then\n      if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;\n    end;\n  end if;\n  return jsonb_build_object`, `      v_rest := null;\n    exception when others then\n      if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;\n    end;\n  end if;\n  return jsonb_build_object`),
    /sell the rest/],
  ['a refused rest fails the order', (s) => swap(s, `      v_rest := cmd.do_sell(p_fleet, p_args);\n    exception when others then\n      if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;\n    end;\n  end if;\n  return jsonb_build_object`, `      v_rest := cmd.do_sell(p_fleet, p_args);\n    exception when others then\n      raise;\n    end;\n  end if;\n  return jsonb_build_object`),
    /did not lift the sale|short purse/],
  ['the total leaves the bonus out', (s) => swap(s, `    'total', v_total + v_bonus + coalesce((v_rest->>'total')::numeric, 0),\n`, `    'total', v_total + coalesce((v_rest->>'total')::numeric, 0),\n`), /lap's books/],
  ['the tax is left out', (s) => swap(s, `    v_tax   := v_tax + coalesce((v_r->'lines'->0->>'tax')::numeric, 0);\n`, ``), /lap's tax|lap's books/],
  ['the manifest drops the tax', (s) => swap(s, `$h$        'basis', v_r->'basis', 'cost', v_r->'cost', 'profit', v_r->'profit',\n        'tax', v_r->'tax', 'wages', v_r->'wages');   -- 0315: a merchant's lap books them\n$h$,`, `$h$        'basis', v_r->'basis', 'cost', v_r->'cost', 'profit', v_r->'profit', 'x', 1);\n$h$,`),
    /lap's tax|lap's books/],
  // run_fulfil
  ['the bonus is on what she offered', (s) => swap(s, `$h$  v_qty := (v_rcpt->'lines'->0->>'qty')::numeric;   -- 0315: what landed: a short purse shrinks a sale (0122)\n  v_pay  := ceil(c.premium_per_unit * v_qty)::bigint;\n$h$,`, `$h$  v_pay  := ceil(c.premium_per_unit * v_qty)::bigint; -- 0315\n$h$,`),
    /short purse/],
  ['an overdue row takes a delivery', (s) => swap(s, `$h$  if c.status = 'expired' or (c.status = 'open' and c.expires_day <= world.game_day()) then   -- 0315\n$h$,`, `$h$  if c.status = 'expired' then   -- 0315\n$h$,`), /overdue row took a delivery/],
  ['a delivery still winds', (s) => swap(s, `$h$  -- 0315: NO WIND HERE. A wind may draw, about 1 s, and a merchant's delivery runs under the quay. The read and the wind job keep the board; the row's own deadline is judged below.\n$h$,`, `$h$  -- 0315: x\n  perform public.tick_contracts(f.port_id, now());\n$h$,`),
    /a delivery wound the board|overdue row took a delivery/],
  ['the delivery is not in the book', (s) => swap(s, `\n  insert into public.contract_deliveries (port_id, player_id, contract_id, bonus) values (c.port_id, f.player_id, c.id, v_pay);   -- 0315\n$h$,`, `\n  -- 0315 x\n$h$,`),
    /ledger, the book or the event|Stats does not see/],
  ['paid still reads the ledger', (s) => swap(s, `'paid', (select coalesce(sum(d.bonus), 0) from public.contract_deliveries d where d.at > p_since and (p_port is null or d.port_id = p_port)))`, `'paid', (select coalesce(sum(l.ducats_delta), 0) from public.ledger l where l.kind = 'PREMIUM' and l.created_at > p_since and (p_port is null or l.port_id = p_port))) --x`),
    /paid does not read the book/],
  // the wind
  ['the wind expires nothing', (s) => swap(s, `      v_back := v_back + public.contracts_expire(v_p, now());\n`, `      null;\n`), /overdue budget home|top the harbour/],
  ['expiry keeps the money', (s) => swap(s, `  if v_lapsed > 0 then\n    -- (whether or not the purses are still lit: an escrow is the city's money either way)\n    perform public.treasury_post(p_port, 'BOUNTY_LAPSED', v_lapsed, null, null, true);\n  end if;\n  delete from public.trade_contracts\n   where port_id = p_port and status <> 'open' and expires_day < v_day - v_deadline;\n  return v_lapsed;`, `  delete from public.trade_contracts\n   where port_id = p_port and status <> 'open' and expires_day < v_day - v_deadline;\n  return v_lapsed;`),
    /overdue budget home/],
  ['the wind ignores the cap', (s) => swap(s, `     where p.kind = 'HARBOUR' and o.n < v_max and (w.next_try`, `     where p.kind = 'HARBOUR' and (w.next_try`), /full board|did not top|does not rest/],
  ['the wind drains a short city', (s) => swap(s, `       and public.treasury_balance(p.id) >= v_floor
`, ``), /under the floor was asked/],
  ['the wind ignores its budget', (s) => swap(s, `  -- (B) THE HARBOURS ARE TOPPED UP\n  loop\n    exit when clock_timestamp() >= v_by;\n`, `  -- (B) THE HARBOURS ARE TOPPED UP\n  loop\n`), /past its budget/],
  ['a failed harbour does not rest', (s) => swap(s, `    if v_n = 0 then\n      insert into public.contract_wind (port_id, next_try) values (v_p, now() + v_retry)\n      on conflict (port_id) do update set next_try = excluded.next_try;\n    end if;\n`, `    exit when v_n = 0;\n`),
    /does not rest/],
  ['the rest is not read', (s) => swap(s, `and (w.next_try is null or w.next_try <= now())\n`, `\n`), /resting harbour|does not rest/],
  // the plan
  ['the plan counts no bonus', (s) => swap(s, `      if v_asks ? v_good::text then   -- 0315: the bonus on what the budget pays for\n        v_profit := v_profit + least(v_q, (v_asks->v_good::text->>'u')::numeric) * (v_asks->v_good::text->>'p')::numeric;\n      end if;\n`, `      -- 0315 x\n`),
    /not in the leg's profit/],
  ['the plan ignores the budget size', (s) => swap(s, `v_profit + least(v_q, (v_asks->v_good::text->>'u')::numeric) * (v_asks->v_good::text->>'p')::numeric;`, `v_profit + (v_asks->v_good::text->>'u')::numeric * (v_asks->v_good::text->>'p')::numeric;`),
    /not in the leg's profit/],
  ['the wares filter stands', (s) => swap(s, ` and not v_asks ? (e->>'good_id');   -- 0315: a good asked for is looked at too\n`, `;   -- 0315 x\n`), /was not looked at/],
  // the file
  ['a helper is open to clients', (s) => swap(s, `  revoke all on function public.contract_asks(uuid) from public, anon, authenticated;\n`, `  grant execute on function public.contract_asks(uuid) to authenticated;\n`),
    /a client can reach/],
  ['a book is open to clients', (s) => swap(s, `  revoke all on table public.contract_deliveries from public, anon, authenticated;\n`, `  grant select on table public.contract_deliveries to authenticated;\n`), /a client can reach/],
  ['the knob is not six', (s) => swap(s, `('contract_npc_after_hours', to_jsonb(6),`, `('contract_npc_after_hours', to_jsonb(5),`), /knobs are not this file's/],
  ['a hunk against another body', (s) => swap(s, `$h$  if c.status = 'expired' then\n$h$,`, `$h$  if c.status  = 'expired' then\n$h$,`), /occurs 0 time/],
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

// THE THIRD POSITIVE CONTROL: the job as cron runs it. The self-assert passes p_commit = false; here the file is applied for good (to this in-memory copy; no snapshot is taken) and the CALL commits.
try {
  // dark: a local world's purses are under prod's floor, and what is under test here is the commits
  await db.exec(file)
  await db.exec(`update public.world_config set value = to_jsonb(3000) where key = 'contract_wind_ms'; update public.world_config set value = to_jsonb(0) where key = 'treasury_reserve_floor';`)
  await db.exec('call public.tick_contract_wind()')
  const r = (await db.query(`select (select count(*)::int from public.trade_contracts where status = 'open') as open, (select receipt from public.contract_wind_runs order by at desc limit 1) as receipt`)).rows[0]
  const good = r.receipt && r.receipt.posted > 0 && r.receipt.failed === 0
  if (!good) failures.push(`the job with commits: ${JSON.stringify(r)}`)
  say(`${good ? 'GREEN' : 'FAIL'}  the job as cron runs it, with real commits: ${JSON.stringify(r)}`)
} catch (e) {
  failures.push(`the job with commits: ${e?.message ?? e}`)
  say(`FAIL  the job with commits: ${e?.message ?? e}`)
}

await db.close()
if (failures.length) {
  say(`\n${failures.length} FAILED:\n  ${failures.join('\n  ')}`)
  process.exit(1)
}
say(`\nall ${MUTATIONS.length} mutations red, the real file green`)
