-- 0493 THE RATE SAYS WHY, BEFORE. A PROD CHECK: read-only, ONE statement (begin read only ... rollback), the gate's three figures.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/rate-why/before-0493.sql
-- Expect: head 20260818000492; new_fns 0; hq_board_for = baa3f56dc8f20f103031f2aeb324a5ca (the chain's world at 0492, so 0493's one
--   hunk occurs there exactly once, as its self-assert proved on that world); old_rate_text 1. A different digest or count: 0493
--   refuses at the push (its hunk count), nothing changes.
-- Reads: arrivals_beats (5 minutes), pg_class, pg_stat_activity, world_config by key, the catalog. No ledger row is read and no
--   function that writes is called. ROLLBACK: nothing to roll back (read only; ends with rollback).
begin transaction read only;
select json_build_object(
  'at', now(),
  'gate', json_build_object(
    'beat_mean_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'database_mb', (select (sum(c.relpages)::numeric * 8192 / 1048576)::int from pg_class c where c.relkind in ('r', 'i', 't', 'm', 'S', 'p')),
    'io_waiting', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.wait_event_type = 'IO' and a.state = 'active')),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'hq_board_enabled', (select c.value from public.world_config c where c.key = 'hq_board_enabled'),
  'new_fns', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
               where (n.nspname, p.proname) in (('public', 'company_rate_line'), ('public', 'company_rate_for'), ('world', 'company_rate'))),
  'hq_board_for', (select md5(replace(pg_get_functiondef('public.hq_board_for(uuid)'::regprocedure), E'\r', ''))),
  'old_rate_text', (select (length(d.def) - length(replace(d.def, d.old, ''))) / length(d.old)
                      from (select replace(pg_get_functiondef('public.hq_board_for(uuid)'::regprocedure), E'\r', '') as def,
                                   '''rate'', (select jsonb_build_object(''per_hour'', round(coalesce(sum(l.ducats_delta), 0) / 24.0)'::text as old) d)
);
rollback;
