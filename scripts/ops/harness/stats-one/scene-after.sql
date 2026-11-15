-- scene-after.sql: what every face reads AFTER 0448 on the scene's world (the newest count re-stated by the file). A read, LOCAL PGlite WORLD ONLY
-- (its runner, probe.mjs, holds the transaction; on production run after.sql).
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
select 'AFTER' as at, jsonb_build_object(
  'ships_tab', (select jsonb_build_object('merchants', v -> 'merchants', 'navy', (v -> 'navy') - 'nations', 'pirates', (v -> 'pirates') - 'homes', 'cargo', v -> 'cargo') from (select world.stats_fleets() as v) x),
  'merchants_tab', (select v - 'list' - 'series' - 'top' - 'bottom' - 'purse' from (select world.stats_merchants(null) as v) x),
  'tabs', (select jsonb_object_agg(k.kind, world.stats_fleet_list(k.kind) - 'list' - 'day' - 'week') from (values ('NAVY'), ('PIRATE'), ('CARGO')) k(kind)),
  'tally_now', public.fleet_tally()) as r;
