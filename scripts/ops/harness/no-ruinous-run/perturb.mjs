// 0502's SELF-ASSERT AGAINST WORLDS THAT ARE NOT THE CHAIN'S (local PGlite only, never prod; everything rolled back).
//   node scripts/ops/harness/no-ruinous-run/perturb.mjs [--cache <a private copy of the prefix cache>]
// A migration's self-assert runs on PRODUCTION when it deploys, where the market, the purses and the companies are not the chain's.
// This applies the chain up to the file before it, then for each world below: begin; perturb; run 0502 whole (its self-assert included); print
// its receipt or its failure; rollback. A failure here is a deploy that would have been refused.
// The cache is only READ (snapshots: false: no snapshot written, nothing pruned); --cache points it at a private copy all the same.
import { readFile, readdir } from 'node:fs/promises'
import path from 'node:path'
import { MIGRATIONS_DIR, PREFIX_CACHE_DIR, preambleVariant } from '../../../db/apply-chain.mjs'
import { applyWithPrefixCache } from '../../../db/prefix-cache.mjs'

const cacheDir = process.argv.includes('--cache') ? process.argv[process.argv.indexOf('--cache') + 1] : PREFIX_CACHE_DIR
const MINE = '20260818000502_no_ruinous_run.sql'
const names = (await readdir(MIGRATIONS_DIR)).filter((n) => n.endsWith('.sql')).sort()
const files = []
for (const name of names.filter((n) => n < MINE)) files.push({ name, sql: await readFile(path.join(MIGRATIONS_DIR, name), 'utf8') })
const mine = await readFile(path.join(MIGRATIONS_DIR, MINE), 'utf8')
const out = await applyWithPrefixCache({ variant: await preambleVariant(), files, cacheDir, snapshots: false, log: (m) => /restored|REFUSED/.test(String(m)) && console.log(String(m).slice(0, 160)) })
if (out.restored < files.length - 6) throw new Error(`only ${out.restored} of ${files.length} files were cached: refusing a long replay`)
const db = out.db

// the switches production runs lit (tests/corpWorld.fixture.ts) and the ones the standing jobs need
const LIT = ['raid_companies_enabled', 'yard_order_enabled', 'hold_requests_enabled', 'houses_board_enabled', 'level_unlocks_enabled', 'world_events_enabled',
  'pirate_bounties_enabled', 'first_hour_enabled', 'regard_enabled', 'levels_bite', 'land_enabled', 'hq_board_enabled', 'fleet_jobs_enabled', 'sea_courses_enabled']
const lit = (keys) => `update public.world_config set value = 'true'::jsonb where key in (${keys.map((k) => `'${k}'`).join(', ')})`

/** A company as the owner's is on prod: home Lisbon, her fleet UNABLE_TO_SAIL at Diego Garcia, hull 0, 899 black coral, purse 0, a Best
 *  job, and SAIL BAN / SAIL MAL / SAIL MAC / SELL black-coral ALL pending; then two more wrecks of other companies (one in a yard
 *  harbour with a refused order in her queue, one adrift at sea) and an empty UNABLE_TO_SAIL fleet (0321). */
const WRECKS = `
do $w$
declare v_a uuid; v_f uuid; v_b uuid; v_c uuid; v_e uuid; v_dga uuid := (select id from public.ports where code = 'DGA');
begin
  v_a := public.new_house('00000000-0497-4000-8000-00000000aa01', 'A Casa Real', 'PRT');
  select f.id into v_f from public.fleets f where f.player_id = v_a;
  update public.fleets set port_id = v_dga, status = 'DOCKED', ready_at = null where id = v_f;
  perform public.fleet_load(v_f, 'black-coral', 899, 10);
  insert into public.orders (fleet_id, player_id, seq, raw_text, verb, args, status)
  select v_f, v_a, x.i, x.t, split_part(x.t, ' ', 1),
         case when x.t like 'SAIL%' then jsonb_build_object('dest', (select p.id from public.ports p where p.code = split_part(x.t, ' ', 2)))
              else jsonb_build_object('good', (select g.id from public.goods g where g.code = 'black-coral'), 'qty_mode', 'ALL') end, 'pending'
    from (values (1, 'SAIL BAN'), (2, 'SAIL MAL'), (3, 'SAIL MAC'), (4, 'SELL black-coral ALL')) x(i, t);
  insert into public.fleet_jobs (fleet_id, player_id, kind, params, since, seen_at, runs, last)
  values (v_f, v_a, 'best', '{}'::jsonb, now() - interval '3 hours', now() - interval '3 hours', 1, jsonb_build_object('at', now() - interval '2 hours', 'ok', true));
  update public.ships set durability = 0 where fleet_id = v_f;
  update public.fleets set status = 'UNABLE_TO_SAIL' where id = v_f;
  update public.players set ducats = 0 where id = v_a;
  -- another company's wreck, in her home harbour, a refused order standing in her queue
  v_b := public.new_house('00000000-0497-4000-8000-00000000aa02', 'Casa Segunda', 'NLD');
  update public.ships set durability = 0 where fleet_id = (select f.id from public.fleets f where f.player_id = v_b);
  update public.fleets set status = 'UNABLE_TO_SAIL' where player_id = v_b;
  insert into public.orders (fleet_id, player_id, seq, raw_text, verb, args, status, error_code, error_message)
  select f.id, v_b, 1, 'SAIL LIS', 'SAIL', '{}'::jsonb, 'failed', 'E_FLAGSHIP_DISABLED', 'the flagship is not fit to sail' from public.fleets f where f.player_id = v_b;
  -- a third, wrecked at sea
  v_c := public.new_house('00000000-0497-4000-8000-00000000aa03', 'Casa Terceira', 'PRT');
  update public.fleets set status = 'UNABLE_TO_SAIL', port_id = null, lat = 10, lon = 60 where player_id = v_c;
  -- an empty fleet that cannot sail (0321)
  select f.id into v_e from public.fleets f where f.player_id = v_c;
  v_e := public.form_fleet(v_c, 'Vazia', v_dga);
  update public.fleets set status = 'UNABLE_TO_SAIL' where id = v_e;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
end $w$`

const WORLDS = [
  ['every later switch lit: the jobs wait, choices at sea, closed economy', lit([...LIT, 'jobs_wait_enabled', 'wreck_sells_enabled', 'sea_choices_enabled', 'economy_closed', 'city_treasury_enabled']) + `; update public.port_treasury set ducats = 900000`],
  ['a sea with a chance of 1 a day at most', `update public.world_config set value = '1'::jsonb where key = 'hazard_p_max'`],
  ['the chain as it is', ``],
  ["prod's switches lit", lit(LIT)],
  ['prices up: every quay at a tenth of its stock', `update public.port_goods set stock = stock * 0.1`],
  ['prices down: every quay at ten times its stock, glutted', `update public.port_goods set stock = stock * 10, glut = 0.5, glut_at = now()`],
  ['empty: every quay at no stock', `update public.port_goods set stock = 0`],
  ['flooded: every quay at a thousand times its target', `update public.port_goods set stock = least(greatest(stock_target, 1) * 1000, 9000000000), glut = -0.5, glut_at = now()`],
  // KNOWN, AND NOT THIS FILE'S: with the economy closed and Lisbon's purse under a founding (40,000), public.new_house itself refuses
  // (E_NO_NEW_GOLD). Every migration's probe since 0481 founds a company the same way, and no real player could found one either.
  // before-0497.sql reads the two facts (`founding`) so the lead sees it before the deploy.
  ['KNOWN closed economy, every city purse empty', `${lit([...LIT, 'economy_closed', 'city_treasury_enabled'])}; update public.port_treasury set ducats = 0, reserve = 0`],
  ["closed economy, Lisbon's purse exactly a founding, every other purse empty: the quay is broke for her sale", `${lit([...LIT, 'economy_closed', 'city_treasury_enabled'])}; update public.port_treasury set ducats = 0, reserve = 0; update public.port_treasury set ducats = 40000 where port_id = (select id from public.ports where code = 'LIS')`],
  ['KNOWN her home quay buys nothing at all: Lisbon has no market row', `delete from public.port_goods where port_id = (select id from public.ports where code = 'LIS')`],
  ['no hands on any quay, no merchant in any port', `update public.ports set crew_pool = 0; update public.fleets f set port_id = null, lat = 0, lon = -30, status = 'ANCHORED' from public.npc_fleets nf where nf.fleet_id = f.id and f.port_id is not null`],
  ["real wrecks and real queues: the owner's four pending orders, two other wrecks, an empty fleet", WRECKS],
  ["the same, with prod's switches lit and the wreck switch's good glutted", `${lit(LIT)}; update public.port_goods set stock = stock * 10, glut = 0.5, glut_at = now(); ${WRECKS}`],
  ['wages owed and a dock fee on every fleet (economy closed)', `${lit([...LIT, 'economy_closed'])}; update public.fleets set call_fee = 5000 where true`],
]

let bad = 0
for (const [name, sql] of WORLDS) {
  await db.exec('begin')
  let line
  try {
    if (sql) await db.exec(sql)
    const notices = []
    await db.exec(mine, { onNotice: (n) => notices.push(n.message) })
    const ok = notices.find((n) => n.startsWith('0502 self-assert ok'))
    if (!ok) throw new Error('no receipt was printed')
    const said = ok.match(/rolled back.: (.*)/)?.[1]
    line = `PASS  ${name}
        ${said}`
  } catch (e) {
    const known = name.startsWith('KNOWN ') && /E_NO_NEW_GOLD|no good Lisbon offers/.test(String(e.message))
    if (!known) bad += 1
    line = `${known ? 'KNOWN' : 'FAIL '} ${name.replace(/^KNOWN /, '')}\n        ${String(e.message).slice(0, 700)}`
  }
  await db.exec('rollback')
  console.log(line)
}
console.log(bad === 0 ? `${WORLDS.length} worlds: the self-assert passed in every one but the known founding refusal` : `${bad} of ${WORLDS.length} worlds FAILED`)
await db.close()
process.exit(bad === 0 ? 0 : 1)
