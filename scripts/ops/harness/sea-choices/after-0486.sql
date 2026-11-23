-- CHOICES AT SEA (0486), AFTER; ALSO THE 30-MINUTE LIT CHECK. A PROD CHECK: read-only, ONE statement, with the gate's three figures.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/sea-choices/after-0486.sql
-- Expect, AS DEPLOYED (dark): head 20260818000486; `knobs.sea_choices_enabled` false and 8 knobs; `hunked` 3 (each hunked body holds its new
-- line once); `stable` true (the four reads); `client_reach` false (no core reachable by a client or service_role; the door for
-- authenticated alone; the table no client's); `rows` {} (no choice set).
-- LIT (30 minutes after the owner lights sea_choices_enabled): `rows` the choices by kind and state (an `_error` suffix: a settle that
-- failed and lapsed); `picked` those she chose and those left to the default; `money` the SEA_FIND / SEA_LOSS rows of the last 30 minutes
-- and their sum; `row_ms` the read's row (public.sea_choice_row, STABLE) on the five newest choices, 20 times; the gate green.
-- ROLLBACK if `client_reach` true, `stable` false, the beat's mean over 2,000 ms, or any `_error` row: sea_choices_enabled false (owner):
-- nothing new is set, no arrival settles, the door refuses; the open rows lapse at their company's next departure.
-- Reads: arrivals_beats (5 minutes), pg_class, pg_stat_activity, world_config by key, the catalog, sea_choices (all of it: a few hundred
-- rows at most), the ledger by (created_at) for 30 minutes. Functions called: public.sea_choice_row (STABLE). No function that writes is
-- called. ROLLBACK: nothing to roll back (read only; ends with rollback).
begin transaction read only;
with t0 as materialized (
  select clock_timestamp() as t
), rd as materialized (
  select count(x.r) as n, clock_timestamp() as t
    from t0 cross join generate_series(1, 20) g
   cross join lateral (select public.sea_choice_row(c.voyage_id) as r from public.sea_choices c order by c.created_at desc limit 5) x
)
select jsonb_build_object(
  'at', now(),
  'gate', jsonb_build_object(
    'beat_mean_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'database_mb', (select (sum(c.relpages)::numeric * 8192 / 1048576)::int from pg_class c where c.relkind in ('r', 'i', 't', 'm', 'S', 'p')),
    'io_waiting', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.wait_event_type = 'IO' and a.state = 'active')),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'knobs', (select jsonb_object_agg(c.key, c.value) from public.world_config c where c.key like 'sea\_choices\_%'),
  'hunked', (select count(*) from (values
               ('voyage.depart(uuid,jsonb,uuid,uuid,timestamp with time zone)', 'perform public.sea_choice_plan(v_voyage, p_at);'),
               ('voyage.settle(uuid,timestamp with time zone)', 'perform public.sea_choice_settle(v.id);'),
               ('public.client_rpc_entry_points()', '''sea_choose''')) h(fn, line)
              where (length(pg_get_functiondef(h.fn::regprocedure)) - length(replace(pg_get_functiondef(h.fn::regprocedure), h.line, ''))) / length(h.line) = 1),
  'stable', (select count(*) from pg_proc p
              where p.oid = any (array['public.sea_choices_on()', 'public.sea_choice_result(uuid,jsonb)', 'public.sea_choice_row(uuid)', 'world.sea_choices()']::regprocedure[]::oid[])
                and p.provolatile = 's') = 4,
  'client_reach', exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                           where n.nspname = 'public' and p.proname like 'sea\_choice%'
                             and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute')
                                  or has_function_privilege('service_role', p.oid, 'execute')))
                  or not has_function_privilege('authenticated', 'cmd.sea_choose(uuid,text)', 'execute')
                  or has_function_privilege('anon', 'cmd.sea_choose(uuid,text)', 'execute')
                  or has_function_privilege('service_role', 'cmd.sea_choose(uuid,text)', 'execute')
                  or has_table_privilege('authenticated', 'public.sea_choices', 'select'),
  'rows', (select coalesce(jsonb_object_agg(k.kk, k.n), '{}'::jsonb) from (
             select c.kind || '.' || c.state || case when c.outcome ? 'error' then '_error' else '' end as kk, count(*) as n
               from public.sea_choices c group by 1) k),
  'picked', (select jsonb_build_object('you', count(*) filter (where c.decided_by = 'you'), 'default', count(*) filter (where c.decided_by = 'default'),
                                       'open_chosen', count(*) filter (where c.state = 'open' and c.chosen is not null)) from public.sea_choices c),
  'money', (select jsonb_build_object('rows', count(*), 'sum', coalesce(sum(l.ducats_delta), 0))
              from public.ledger l where l.created_at > now() - interval '30 minutes' and l.kind in ('SEA_FIND', 'SEA_LOSS')),
  'row_ms', (select round(extract(epoch from rd.t - t0.t) * 1000 / 20, 2) from rd, t0)
);
rollback;
