-- 0360 PROD CHECK AFTER, read-only, one statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/trip-cost/after.sql
-- The catalog, and the STABLE authorities the read composes, on the docked human fleet with the most ships, for the nearest harbour a day away.
-- world.trip_cost itself answers null here (no signed-in company on this connection): `not_yours_null` is that, and it is the only call of it.
-- Every function called is STABLE ('s'; before.sql prints them). No clock is read, nothing is written.
-- Wanted: head 20260818000360; fn_vol 's'; registry_row_times 1; anon false and authenticated true; not_yours_null true;
--         news_row 1; `leg` printed: the first leg's supplies as public.supply_need says them, the day's wage, the dock fee there, the port time.
begin transaction read only;
with f as (
  select fl.id, fl.player_id, fl.port_id
    from public.fleets fl join public.players p on p.id = fl.player_id
   where not p.is_npc and fl.port_id is not null
   order by (select count(*) from public.ships s where s.fleet_id = fl.id) desc, fl.id
   limit 1
), near as (
  select r.port_id, r.nm from f cross join lateral voyage.reach_from(f.port_id) r
   where r.nm / greatest(voyage.fleet_speed(f.id), 0.1) / 24 >= 1 order by r.nm limit 1
)
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'fn_vol', (select p.provolatile::text from pg_proc p where p.oid = to_regprocedure('world.trip_cost(uuid,jsonb)')),
  'registry_row_times', (select (length(d.def) - length(replace(d.def, $h$('world',       'trip_cost',             'uuid, jsonb'),$h$, '')))
                                / length($h$('world',       'trip_cost',             'uuid, jsonb'),$h$)
                           from (select replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), E'\r', '') as def) d),
  'anon', has_function_privilege('anon', 'world.trip_cost(uuid,jsonb)', 'execute'),
  'authenticated', has_function_privilege('authenticated', 'world.trip_cost(uuid,jsonb)', 'execute'),
  'not_yours_null', (select world.trip_cost(f.id, '[]'::jsonb) is null from f),
  'news_row', (select count(*) from public.world_news n where n.key = 'update:0360'),
  'leg', (select jsonb_build_object(
            'nm', round(near.nm, 1),
            'supplies', (select n.cost from public.supply_need(f.id, near.nm) n),
            'wage_a_day', public.fleet_wage(f.id, false),
            'dock_fee', public.port_fee(near.port_id, f.player_id, public.fleet_stock_at_cost(f.id)),
            'port_time_s', case when public.economy_closed() then public.wc_num('port_prep_seconds') else 0 end)
            from f, near)
) as checks;
commit;
