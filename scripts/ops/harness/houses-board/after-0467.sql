-- HOUSES' BOARD (0467), AFTER. A PROD CHECK: read-only, ONE statement, small. The gate first (db-health/gate.sql).
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/houses-board/after-0467.sql
-- Expect, DARK (as deployed): head 0467; houses_board_enabled false; houses_week 0 rows; world.houses_week stable and executable by
-- authenticated, not anon; the settle not executable by authenticated; the history job's newest run (after its next :12/:27/:42/:57) has
-- phases.houses = null and its ms in its usual range. LIT (only after the owner lights it, and one history run later): houses_week about
-- 2 x 874 rows, this week's count = the merchant houses + the companies with a login (5 on 2026-11-21), phases.houses.ms small.
-- Reads: catalog, world_config by key, houses_week (at most ~1,750 rows), npc_houses count, players not is_npc (~19) with auth.users by key,
-- history_runs' newest row by its key. No game function is called.
begin transaction read only;
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'switch', (select value from public.world_config where key = 'houses_board_enabled'),
  'week_rows', (select count(*) from public.houses_week),
  'this_week', (select count(*) from public.houses_week w where w.week = date_trunc('week', (now() at time zone 'UTC'))::date),
  'should_be', (select count(*) from public.npc_houses)
               + (select count(*) from public.players p where not p.is_npc and exists (select 1 from auth.users u where u.id = p.auth_uid)),
  'read_ok', (select p.provolatile = 's' and has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute')
                from pg_proc p where p.oid = to_regprocedure('world.houses_week()')),
  'settle_private', (select not has_function_privilege('authenticated', p.oid, 'execute') from pg_proc p where p.oid = to_regprocedure('public.houses_week_settle(timestamp with time zone)')),
  'last_run', (select jsonb_build_object('at', r.at, 'ms', r.ms, 'houses', r.receipt -> 'phases' -> 'houses', 'has_key', (r.receipt -> 'phases') ? 'houses')
                 from public.history_runs r order by r.at desc limit 1));
rollback;
