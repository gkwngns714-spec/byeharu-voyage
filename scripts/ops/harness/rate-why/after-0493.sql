-- 0493 THE RATE SAYS WHY, AFTER. A PROD CHECK: read-only, ONE statement. The gate first.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/rate-why/after-0493.sql
-- Expect: head 20260818000493; new_fns 3; client_reach false (none callable by anon, authenticated or service_role); reads 3 (the map
--   immutable, the two reads stable); hq_board_for = 93c12cd82eaf2ac6db2693fce4cd9dcb (the chain's world at 0493); the board's own
--   grants as before (hq_board_client true: world.hq_board for authenticated; hq_board_for_client false).
--   rate: the one authority for THE COMPANY NAMED BELOW (put the owner's company name in place of the text between the quotes):
--   per_hour is her running lines only; all_24h is the old figure; old_sum is 0480's expression read in the same statement, and
--   sums_hold says running lines = net_24h, one-time lines = one_time_24h, all lines = all_24h = old_sum.
--   With the owner's day (SHARE -461,384 in 2 rows, TOW -6,932, OFFICER_WAGE -3,250, while those rows are inside 24 hours):
--   per_hour -289, one_time_24h -464,634, all_24h -471,566.
-- ROLLBACK (forward, owner only) if client_reach is true, sums_hold is false, or HQ's board fails to open: a migration reversing the
--   one hunk (0493's OLD text) and dropping the three functions.
-- Reads: arrivals_beats (5 minutes), pg_class, pg_stat_activity, the catalog, one players row by name, that company's ledger rows of
--   the last 24 hours (the (player_id, created_at) index, twice). public.company_rate_for is STABLE and writes nothing.
--   ROLLBACK: nothing to roll back (read only; ends with rollback).
begin transaction read only;
with me as (
  select p.id from public.players p where p.company_name = 'PUT THE COMPANY NAME HERE' and not p.is_npc limit 1
), r as (
  select public.company_rate_for(me.id) as rate,
         (select coalesce(sum(l.ducats_delta), 0) from public.ledger l
           where l.player_id = me.id and l.created_at > now() - interval '24 hours' and l.kind <> 'FOUNDING' and left(l.kind, 6) <> 'PROBE_') as old_sum
    from me
)
select json_build_object(
  'at', now(),
  'gate', json_build_object(
    'beat_mean_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'database_mb', (select (sum(c.relpages)::numeric * 8192 / 1048576)::int from pg_class c where c.relkind in ('r', 'i', 't', 'm', 'S', 'p')),
    'io_waiting', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.wait_event_type = 'IO' and a.state = 'active')),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'new_fns', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
               where (n.nspname, p.proname) in (('public', 'company_rate_line'), ('public', 'company_rate_for'), ('world', 'company_rate'))),
  'client_reach', (select coalesce(bool_or(has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute')
                                           or has_function_privilege('service_role', p.oid, 'execute')), false)
                     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                    where (n.nspname, p.proname) in (('public', 'company_rate_line'), ('public', 'company_rate_for'), ('world', 'company_rate'))),
  'reads', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where ((n.nspname, p.proname) = ('public', 'company_rate_line') and p.provolatile = 'i')
                or ((n.nspname, p.proname) in (('public', 'company_rate_for'), ('world', 'company_rate')) and p.provolatile = 's')),
  'hq_board_for', (select md5(replace(pg_get_functiondef('public.hq_board_for(uuid)'::regprocedure), E'\r', ''))),
  'hq_board_client', has_function_privilege('authenticated', 'world.hq_board()', 'execute'),
  'hq_board_for_client', has_function_privilege('authenticated', 'public.hq_board_for(uuid)', 'execute'),
  'rate', (select r.rate from r),
  'old_sum', (select r.old_sum from r),
  'sums_hold', (select (select coalesce(sum((e->>'total_24h')::numeric), 0) from jsonb_array_elements(r.rate->'lines') e where not (e->>'one_time')::boolean) = (r.rate->>'net_24h')::numeric
                   and (select coalesce(sum((e->>'total_24h')::numeric), 0) from jsonb_array_elements(r.rate->'lines') e where (e->>'one_time')::boolean) = (r.rate->>'one_time_24h')::numeric
                   and (select coalesce(sum((e->>'total_24h')::numeric), 0) from jsonb_array_elements(r.rate->'lines') e) = (r.rate->>'all_24h')::numeric
                   and (r.rate->>'all_24h')::numeric = r.old_sum
                  from r)
);
rollback;
