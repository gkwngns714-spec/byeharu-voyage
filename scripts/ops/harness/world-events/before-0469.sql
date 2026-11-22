-- WORLD EVENTS (0469), BEFORE. A PROD CHECK: read-only, ONE statement, small. The gate first (db-health/gate.sql).
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/world-events/before-0469.sql
-- Reads: buff_kinds (1 row), active_buffs by kind (about 50 rows), the buff-calendar job's row, world_config by key, news_kinds (8 rows),
-- the four hunked bodies' fingerprints (catalog), and the count of Lisbon's market rows without a want marker (one port's rows, by key).
-- Expect: head 0468 (0468 is the other builder's, deployed first); world_events_enabled absent; buff_kinds FAIR only, no `categories`
-- column; active_buffs FAIR rows only; byeharu-voyage:buff-calendar active on */10; no EVENT_ news kind; each hunk's old line present once
-- (the `hunks` booleans all true; a false means 0468 or another file cut that line: rebase 0469 before pushing).
begin transaction read only;
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'switch', (select c.value from public.world_config c where c.key = 'world_events_enabled'),
  'knobs', (select jsonb_object_agg(c.key, c.value) from public.world_config c
             where c.key in ('buff_bonus_cap_pct', 'city_wants', 'economy_closed', 'want_period_seconds', 'want_cap_pct')),
  'kinds', (select jsonb_agg(jsonb_build_object('code', k.code, 'effect', k.effect, 'mag', k.magnitude_pct) order by k.code) from public.buff_kinds k),
  'categories_column', exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'buff_kinds' and column_name = 'categories'),
  'active_buffs', (select jsonb_object_agg(x.kind_code, x.n) from (select ab.kind_code, count(*) as n from public.active_buffs ab group by 1) x),
  'job', (select jsonb_build_object('schedule', j.schedule, 'active', j.active, 'command', j.command) from cron.job j where j.jobname = 'byeharu-voyage:buff-calendar'),
  'event_news_kinds', (select count(*) from public.news_kinds n where n.kind like 'EVENT_%'),
  'hunks', jsonb_build_object(
    'tick_buff_calendar', position('  return v_total;' in pg_get_functiondef('public.tick_buff_calendar(timestamp with time zone)'::regprocedure)) > 0,
    'want_left', position('   where public.wants_lit() and current_setting(''byeharu.want_off'', true) is distinct from ''on''' in pg_get_functiondef('world.want_left(uuid,uuid)'::regprocedure)) > 0,
    'spread', position('* (1 - public.buff_multiplier(''PORT'', p.id, ''SPREAD'', now()))' in pg_get_functiondef('world.spread(uuid)'::regprocedure)) > 0,
    'buffs', position('v_read constant text[] := array[''SPREAD''];' in pg_get_functiondef('world.buffs(uuid)'::regprocedure)) > 0,
    'entry_points', position('''houses_week'',' in pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure)) > 0),
  'lisbon_rows_unmarked', (select count(*) from public.port_goods pg join public.ports p on p.id = pg.port_id where p.code = 'LIS' and pg.want_period is null));
rollback;
