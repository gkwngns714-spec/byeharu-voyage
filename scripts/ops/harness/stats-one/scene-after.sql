-- scene-after.sql: what every face reads AFTER 0448 on the scene's world (the newest count re-stated by the file). Read-only.
select 'AFTER' as at, jsonb_build_object(
  'ships_tab', (select jsonb_build_object('merchants', v -> 'merchants', 'navy', (v -> 'navy') - 'nations', 'pirates', (v -> 'pirates') - 'homes', 'cargo', v -> 'cargo') from (select world.stats_fleets() as v) x),
  'merchants_tab', (select v - 'list' - 'series' - 'top' - 'bottom' - 'purse' from (select world.stats_merchants(null) as v) x),
  'tabs', (select jsonb_object_agg(k.kind, world.stats_fleet_list(k.kind) - 'list' - 'day' - 'week') from (values ('NAVY'), ('PIRATE'), ('CARGO')) k(kind)),
  'tally_now', public.fleet_tally()) as r;
