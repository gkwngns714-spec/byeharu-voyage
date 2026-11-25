-- 0500 CARGO AT COST, BEFORE. A PROD CHECK: read-only, ONE statement (begin read only ... rollback), the gate's three figures.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/cargo-at-cost/before-0500.sql
-- Expect: head 20260818000499; knobs 0; new_fns 0; the four hunked bodies equal to the chain's world at 0499 (so each of 0500's
--   thirteen hunks occurs there exactly once, as its self-assert proved on that world):
--   settle 2c355ceab0dcbeeea9c16b9f068290bf, forced_home db19e356d987657236f0047de3e9d4c1,
--   navy_meets 54ca2ed731ba0126e08b38bec418287d, company_rate_for ab4eae880c37d9eb3042980e718f96f3.
--   A different digest: 0500 refuses at the push (its hunk count), nothing changes.
--   untouched: the three loss bodies' digests, to compare with the after read (they must not move).
--   days_with_loss_24h: the days of the last 24 hours that lost cargo (how many rows a day gain the one key), and that none carries
--   the key yet.
-- Reads: arrivals_beats (5 minutes), pg_class, pg_stat_activity, world_config by key, the catalog, voyage_events of the last
--   24 hours (by resolved_at; a sequential read of the table if no index serves it: read once, not in a loop). No function that
--   writes is called. ROLLBACK: nothing to roll back (read only; ends with rollback).
begin transaction read only;
select json_build_object(
  'at', now(),
  'gate', json_build_object(
    'beat_mean_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'database_mb', (select (sum(c.relpages)::numeric * 8192 / 1048576)::int from pg_class c where c.relkind in ('r', 'i', 't', 'm', 'S', 'p')),
    'io_waiting', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.wait_event_type = 'IO' and a.state = 'active')),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'knobs', (select count(*) from public.world_config c where c.key in ('cargo_at_cost_enabled', 'cargo_at_cost_since')),
  'new_fns', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
               where n.nspname = 'public' and p.proname in ('cargo_at_cost_on', 'cargo_rate_for')),
  'bodies', json_build_object(
    'settle', md5(replace(pg_get_functiondef('voyage.settle(uuid,timestamp with time zone)'::regprocedure), E'\r', '')),
    'forced_home', md5(replace(pg_get_functiondef('voyage.forced_home(uuid,integer,uuid)'::regprocedure), E'\r', '')),
    'navy_meets', md5(replace(pg_get_functiondef('voyage.navy_meets(uuid,integer,uuid,uuid,timestamp with time zone)'::regprocedure), E'\r', '')),
    'company_rate_for', md5(replace(pg_get_functiondef('public.company_rate_for(uuid)'::regprocedure), E'\r', ''))),
  'untouched', json_build_object(
    'lose_hold', md5(replace(pg_get_functiondef('voyage.lose_hold(uuid)'::regprocedure), E'\r', '')),
    'raid_takes', md5(replace(pg_get_functiondef('voyage.raid_takes(uuid,integer,uuid,text)'::regprocedure), E'\r', '')),
    'fleet_unload', md5(replace(pg_get_functiondef('public.fleet_unload(uuid,text,numeric)'::regprocedure), E'\r', ''))),
  'days_with_loss_24h', (select json_build_object('rows', count(*), 'with_cost_key', count(*) filter (where ve.payload ? 'cargo_lost_cost'))
                           from public.voyage_events ve
                          where ve.resolved_at > now() - interval '24 hours' and ve.payload ? 'cargo_lost')
);
rollback;
