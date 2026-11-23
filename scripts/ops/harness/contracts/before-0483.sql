-- COURIER CONTRACTS (0483), BEFORE. A PROD CHECK: read-only, ONE statement. It carries the gate's own three figures (the arrivals beat's
-- mean over 5 minutes, the database by the catalog, the sessions waiting on the disk), so it is the builder's one prod read.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/contracts/before-0483.sql
-- Expect: head 20260818000482; `knobs` {} (no contracts_*); `absent` true (no public.courier_contracts, no public.courier_*, no
-- cmd.take_contract); `anchors` {hq_board_for: 1, client_rpc_entry_points: 1} and `new_absent` true (each hunk's anchor once in prod's
-- live body, its new text nowhere); `bodies` the md5 of the two hunked bodies (equal to the chain's: the local chain prints them);
-- `flow_words` [] (none of the five kinds yet) and `flow_ord_max` 62.
-- THE PROBE'S SELECTIONS, as the self-assert makes them: `probe.good` the lightest good Lisbon offers, `probe.to` the nearest harbour 150
-- miles or more from Lisbon with a stored course and a warehouse that trades it, `probe.house` the richest house's purse, `probe.lis_shed`
-- Lisbon's warehouse (tons) — none may be null.
-- THE WORLD THE DRAWS SEE: `houses` (and those whose home is a harbour), `cap` ceil(houses / 20), the switches the draws read.
-- THE COST: `reach_ms` 20 voyage.reach_from (a board read asks one a fleet; a draw one); `draw_ms` the reads of 5 draws (the houses'
-- home harbours: offered goods, the harbours in reach that trade the good, two prices), no write.
-- Reads: arrivals_beats (5 minutes), pg_class, pg_stat_activity, world_config by key, the catalog (pg_proc), stats_flow_words, ports,
-- goods, port_goods, port_specialties, sea_reaches, sea_courses, port_buildings, npc_houses, players (the houses' purses), and the STABLE
-- reads above. No function that writes is called. ROLLBACK: nothing to roll back (read only; ends with rollback).
begin transaction read only;
with lis as materialized (
  select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR'
), good as materialized (
  select g.id, g.code from lis cross join public.port_offered_goods(lis.id) o join public.goods g on g.id = o.good_id
    join public.port_goods pg on pg.port_id = lis.id and pg.good_id = g.id
   where g.bulk > 0 order by g.bulk, g.code limit 1
), dest as materialized (
  select r.code, r.nm from lis cross join voyage.reach_from(lis.id) r join public.ports p on p.id = r.port_id and p.kind = 'HARBOUR'
    join public.port_goods pg on pg.port_id = r.port_id and pg.good_id = (select good.id from good)
   where r.nm >= 150 and public.sea_course(lis.id, r.port_id) is not null and public.storage_cap(r.port_id) > 0
   order by r.nm, r.code limit 1
), t0 as materialized (
  select clock_timestamp() as t
), reach as materialized (
  select (select count(*) from (select p.id from public.ports p where p.kind = 'HARBOUR' order by p.code limit 20) h
            cross join lateral voyage.reach_from(h.id) r) as rows, clock_timestamp() as t from t0
), draws as materialized (
  select (select count(*)
            from (select h.home_port_id as a from public.npc_houses h order by h.roster_ord limit 5) d
            cross join lateral (select g.id as gid from public.port_offered_goods(d.a) o join public.goods g on g.id = o.good_id
                                  join public.port_goods pg on pg.port_id = d.a and pg.good_id = g.id where g.bulk > 0 order by g.code limit 1) gg
            cross join lateral (select r.port_id from voyage.reach_from(d.a) r join public.ports p on p.id = r.port_id and p.kind = 'HARBOUR'
                                  join public.port_goods pg on pg.port_id = r.port_id and pg.good_id = gg.gid
                                 where r.nm between 150 and 1500
                                   and not exists (select 1 from public.port_specialties s where s.port_id = r.port_id and s.good_id = gg.gid)
                                 order by r.code limit 1) bb
            cross join lateral (select (select q.mid from world.price(d.a, gg.gid) q) + (select q.mid from world.price(bb.port_id, gg.gid) q) as m) pr
           where pr.m > 0) as n, clock_timestamp() as t from reach
), hb as (
  select replace(pg_get_functiondef('public.hq_board_for(uuid)'::regprocedure), E'\r', '') as d
), ce as (
  select replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), E'\r', '') as d
)
select jsonb_build_object(
  'at', now(),
  'gate', jsonb_build_object(
    'beat_mean_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'beats', (select count(*) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'database_mb', (select (sum(c.relpages)::numeric * 8192 / 1048576)::int from pg_class c where c.relkind in ('r', 'i', 't', 'm', 'S', 'p')),
    'io_waiting', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.wait_event_type = 'IO' and a.state = 'active')),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'knobs', (select coalesce(jsonb_object_agg(c.key, c.value), '{}'::jsonb) from public.world_config c where c.key like 'contracts\_%'),
  'absent', to_regclass('public.courier_contracts') is null and to_regprocedure('cmd.take_contract(uuid,uuid,integer)') is null
            and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname like 'courier\_%'),
  'anchors', jsonb_build_object(
    'hq_board_for', (select (length(hb.d) - length(replace(hb.d, '  -- THE YARD: the second ship (fewer than hq_board_build_below ships, none on order), the cheapest hull at a yard where she lies' || E'\n', '')))
                             / length('  -- THE YARD: the second ship (fewer than hq_board_build_below ships, none on order), the cheapest hull at a yard where she lies' || E'\n') from hb),
    'client_rpc_entry_points', (select (length(ce.d) - length(replace(ce.d, '      (''world'',       ''away_report'',           ''''),', '')))
                                        / length('      (''world'',       ''away_report'',           ''''),') from ce)),
  'new_absent', (select position('contract_moves' in hb.d) = 0 from hb) and (select position('take_contract' in ce.d) = 0 from ce),
  'bodies', jsonb_build_object('hq_board_for', (select md5(hb.d) from hb), 'client_rpc_entry_points', (select md5(ce.d) from ce)),
  'flow_words', (select coalesce(jsonb_agg(w.kind), '[]'::jsonb) from public.stats_flow_words w where w.kind like 'CONTRACT\_%'),
  'flow_ord_max', (select max(w.ord) from public.stats_flow_words w),
  'probe', jsonb_build_object('good', (select good.code from good), 'to', (select dest.code from dest), 'to_nm', (select dest.nm from dest),
                              'house', (select max(p.ducats) from public.npc_houses h join public.players p on p.id = h.player_id),
                              'lis_shed', (select public.storage_cap(lis.id) from lis)),
  'houses', (select count(*) from public.npc_houses),
  'houses_harbour_home', (select count(*) from public.npc_houses h join public.ports p on p.id = h.home_port_id and p.kind = 'HARBOUR'),
  'cap', (select ceil(count(*)::numeric / 20) from public.npc_houses),
  'switches', (select jsonb_object_agg(c.key, c.value) from public.world_config c
                where c.key in ('city_treasury_enabled', 'economy_closed', 'sea_courses_enabled', 'hq_board_enabled', 'fleet_jobs_enabled',
                                'time_compression', 'standing_routes_enabled', 'hq_board_request_floor_s')),
  'reach_ms', (select round(extract(epoch from reach.t - t0.t) * 1000, 1) from reach, t0),
  'reach_rows', (select reach.rows from reach),
  'draw_ms', (select round(extract(epoch from draws.t - reach.t) * 1000, 1) from draws, reach),
  'draws_priced', (select draws.n from draws)
) as r;
rollback;
