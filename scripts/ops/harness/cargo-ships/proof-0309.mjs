// ═════════════════════════════════════════════════════════════════
// proof-0309.mjs — A CARGO SHIP CARRIES FUNDS (migration 0309): the red-first proof. LOCAL ONLY (PGlite); not in CI.
// ═════════════════════════════════════════════════════════════════
//
//   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/cargo-ships/proof-0309.mjs
//
// Restores the cached world at head 0308 (never from zero), then applies 0309 to it several times inside rolled-back transactions:
//   MUTATION CONTROLS - deliberate breakages of the file, each required to FAIL its self-assert for the intended reason;
//   POSITIVE CONTROL  - the real file, which must pass and print its receipt.
// The harness reads the migration from supabase/migrations; it does not edit it.

import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { migrationFiles, MIGRATIONS_DIR, PREFIX_CACHE_DIR, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const NAME = '20260818000309_a_cargo_ship_carries_funds.sql'
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

const BEFORE_ASSERT = `  -- ── 11. THE SELF-ASSERT: hunks, grants, nothing else moved ──\n`
const addBeforeAssert = (s, sql) => swap(s, BEFORE_ASSERT, `${sql}\n${BEFORE_ASSERT}`)
const LOADS = `    return jsonb_build_object('aided', 0, 'aid', 0) || v_call || public.cargo_ships_load(v_short);\n`
const MEND_HOME = `      update public.ships s set durability = (select b.durability from public.ship_base(s.id) b) where s.fleet_id = p_fleet;\n      update public.cargo_ships x set out_load = null`

const MUTATIONS = [
  ['both paths pay: the load does not replace the aid', (s) => swap(s, LOADS, `    perform public.cargo_ships_load(v_short);\n`),
    /two paths paid|did not load the roster/],
  ['the branch ignores the switch: dark loads', (s) => swap(s, `  if public.convoys_on() then\n${LOADS}`, `  if true then\n${LOADS}`),
    /dark, public\.crown_aid is not its pre-image/],
  ['the file ships lit', (s) => addBeforeAssert(s, `  update public.world_config set value = 'true'::jsonb where key = 'convoys_enabled';`),
    /a world_config row moved|not dark and empty/],
  ['the job works dark', (s) => swap(s, `  if public.convoys_on() then\n    select g.nation_id into v_nat`, `  if true then\n    select g.nation_id into v_nat`),
    /dark, the job did something/],
  ['the capital no longer draws on its nation when lit', (s) => swap(s, `  v_call := public.crown_call(v_short);\n  if public.convoys_on() then\n${LOADS}  end if;\n`,
    `  if public.convoys_on() then\n    return jsonb_build_object('aided', 0, 'aid', 0, 'called', 0, 'donors', 0) || public.cargo_ships_load(v_short);\n  end if;\n  v_call := public.crown_call(v_short);\n`),
    /did not draw on its nation/],
  ['a run loads what is already aboard', (s) => swap(s, `least(k.need - (select coalesce(sum(a.aboard), 0)::bigint from public.cargo_ships c cross join lateral public.cargo_ship_aboard(c.fleet_id) a where c.home_port_id = k.cap),`, `least(k.need,`),
    /two paths paid|a second run loaded/],
  ['a capital loads more than it holds', (s) => swap(s, `                 greatest(0, public.city_surplus(k.cap)));\n    continue when v_a <= 0;`, `                 k.need);\n    continue when v_a <= 0;`),
    /cannot pay|loaded what it does not hold/],
  ['loading does not take from the capital', (s) => swap(s, `    case when p_stage = 'LOADED' then -p_ducats else p_ducats end, null, null, p_stage <> 'LOADED');`, `    p_ducats, null, null, p_stage <> 'LOADED');`),
    /two paths paid|counted to the ducat/],
  ['the live figure does not move with the funds', (s) => swap(s, `  perform public.stats_live_add(jsonb_build_object('set_aside', case when p_stage = 'LOADED' then p_ducats else -p_ducats end));\n`, ``),
    /the live figures did not move/],
  ['tick_stats leaves out the funds aboard', (s) => swap(s, ` + public.funds_aboard(),   -- 0224`, `,   -- 0224`),
    /leaves out the funds aboard/],
  ['the fold leaves out the funds aboard', (s) => swap(s, `from public.city_shares sh) + public.funds_aboard())::bigint as set_aside,`, `from public.city_shares sh))::bigint as set_aside,`),
    /leaves out the funds aboard/],
  ['a delivery overshoots by 1 d.', (s) => swap(s, `v_give := least(public.city_aid_target(f.port_id) - public.treasury_balance(f.port_id), v_left);`, `v_give := least(public.city_aid_target(f.port_id) + 1 - public.treasury_balance(f.port_id), v_left);`),
    /not topped up exactly once/],
  ['she pays with the switch off', (s) => swap(s, `    if v_lit and v_left > 0 and public.city_capital(f.port_id) = c.home_port_id then`, `    if v_left > 0 and public.city_capital(f.port_id) = c.home_port_id then`),
    /off, a ship paid a city/],
  ['she pays a city of another flag', (s) => swap(s, `    if v_lit and v_left > 0 and public.city_capital(f.port_id) = c.home_port_id then`, `    if v_lit and v_left > 0 then`),
    /a city of another flag was paid/],
  ['she ignores her port time', (s) => swap(s, `  if f.ready_at is not null and f.ready_at > p_now then\n    return 'IN_PORT';\n  end if;\n`, ``),
    /not topped up exactly once/],
  ['the rest does not come home', (s) => swap(s, `      if v_left > 0 then\n        perform public.convoy_book('RETURNED', p_fleet, c.player_id, f.port_id, v_left, v_load);\n      end if;\n`, ``),
    /did not come home/],
  ['a load not yet gone sails with the switch off', (s) => swap(s, `    if c.out_load is not null or (v_load is not null and not v_lit) then`, `    if c.out_load is not null then`),
    /did not come back ashore/],
  ['she is not mended at home', (s) => swap(s, MEND_HOME, `      update public.cargo_ships x set out_load = null`),
    /she was not mended/],
  ['a wreck stays wrecked', (s) => swap(s, `    update public.fleets set status = 'DOCKED', ready_at = f.ready_at, version = version + 1 where id = p_fleet;\n`, `    update public.fleets set ready_at = f.ready_at, version = version + 1 where id = p_fleet;\n`),
    /a wreck was lost/],
  ['a wreck waits for nothing', (s) => swap(s, `    f.ready_at := p_now + make_interval(secs => public.wc_num('convoy_wreck_seconds')::double precision);\n`, `    f.ready_at := p_now;\n`),
    /a wreck was lost, or not delayed/],
  ['she still pays the dock fee', (s) => swap(s, `     or exists (select 1 from public.cargo_ships c where c.player_id = p_player)   -- 0309: a crown's cargo ship docks free in her own crown's cities; she has no purse\n`, ``),
    /paid a dock fee|left her owing/],
  ['every NPC house docks free', (s) => swap(s, `     or exists (select 1 from public.cargo_ships c where c.player_id = p_player)   -- 0309`, `     or exists (select 1 from public.players c where c.id = p_player and c.is_npc)   -- 0309`),
    /public\.port_fee is not its pre-image|another house stopped paying/],
  ['a ship can hold two loads', (s) => swap(s, `    if exists (select 1 from public.cargo_ship_aboard(new.fleet_id)) then\n      raise exception 'E_CARGO_OPEN: fleet % still carries a load', new.fleet_id using errcode = '23514';   -- 0309: one open load a ship, so public.cargo_ship_aboard stays one load's walk\n    end if;\n`, ``),
    /took a second load/],
  ['the circuit does not come home', (s) => swap(s, `    for i in 1 .. k loop\n      s := v_tour[i];`, `    for i in 1 .. k - 1 loop\n      s := v_tour[i];`),
    /E_CARGO_NO_LEG|not capital, every city, capital/],
  ['a city no course reaches is dropped in silence', (s) => swap(s, `      v_left := v_left || to_jsonb((select p.code from public.ports p where p.id = v_ids[v_s[t]]));\n`, `      null;\n`),
    /not capital, every city, capital/],
  ['a flag change does not rebuild the circuit', (s) => swap(s, `       and (k.built_at is null or k.built_at < (select max(a.since) from public.port_allegiance a)\n            or (select count(*)`, `       and (k.built_at is null\n            or (select count(*)`),
    /did not rebuild the circuit/],
  ['a rebuild drops the circuit a ship is out on', (s) => swap(s, `     and not exists (select 1 from public.cargo_ships s where s.circuit_id = c.id);\n`, `     and true;\n`),
    /foreign key|dropped the one a ship is on/],
  ['a client can run the job', (s) => swap(s, `  revoke all on function public.tick_cargo_ships(timestamptz, uuid) from public, anon, authenticated;\n`,
    `  revoke all on function public.tick_cargo_ships(timestamptz, uuid) from public, anon;\n  grant execute on function public.tick_cargo_ships(timestamptz, uuid) to authenticated;\n`),
    /a client can reach a new function/],
  ['a client can read a circuit', (s) => swap(s, `  revoke all on sequence public.cargo_circuits_id_seq from public, anon, authenticated;\n`,
    `  grant select on table public.cargo_circuits to authenticated;\n`),
    /a client can reach a circuit/],
  ['no row security on a circuit', (s) => swap(s, `  alter table public.cargo_circuits enable row level security;\n`, ``),
    /has no row security/],
  ['the plan is not stable', (s) => swap(s, `create function public.cargo_circuit_plan(p_nation uuid)\nreturns jsonb\nlanguage plpgsql\nstable\n`, `create function public.cargo_circuit_plan(p_nation uuid)\nreturns jsonb\nlanguage plpgsql\n`),
    /a read is not stable/],
  ['a hunk cut against another body', (s) => swap(s, `$h$  if p_player is null or not public.economy_closed() or not public.city_treasury_on()\n$h$,\n$h$+ coalesce`, `$h$  if p_player is null or not public.economy_closed() or not public.city_treasury_on() \n$h$,\n$h$+ coalesce`),
    /occurs 0 time/],
  ['a hunk that does not reverse', (s) => addBeforeAssert(s, `  execute replace(pg_get_functiondef('public.port_fee(uuid,uuid,numeric)'::regprocedure), 'THE one dock fee', 'THE one fee at the dock');`),
    /is not the body this file wrote/],
  ['a live function was touched', (s) => addBeforeAssert(s,
    `  execute replace(replace(pg_get_functiondef('public.crown_call_room(uuid)'::regprocedure), E'\\r', ''), 'select greatest(0,', 'select greatest(0 ,');`),
    /another function moved/],
  ['a live knob was touched', (s) => addBeforeAssert(s, `  update public.world_config set value = to_jsonb(21) where key = 'crown_call_cover';`),
    /a world_config row moved/],
  ['a live trigger was added', (s) => addBeforeAssert(s, `  create trigger cargo_watch after update on public.fleets for each row execute function public.tg_house_caps();`),
    /a trigger moved/],
  ['a live word was touched', (s) => addBeforeAssert(s, `  update public.stats_flow_words set word = 'Crown money' where kind = 'CROWN_AID';`),
    /a word moved/],
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
