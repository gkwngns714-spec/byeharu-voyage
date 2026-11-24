-- A SALE SHOWS ITS PROFIT BEFORE THE PRESS (0490), BEFORE. A PROD CHECK: read-only, ONE statement, the catalog only.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/sell-profit/before-0490.sql
-- Expect: head 20260818000489; h1..h4 each 1 (each hunk's OLD text occurs once in the live cmd.do_sell: 0490's self-assert refuses
--   otherwise); applied false (no v_trip yet); client_exec false (no client may call cmd.do_sell directly).
-- Reads: supabase_migrations.schema_migrations, pg_proc (pg_get_functiondef is STABLE). Nothing is written. ROLLBACK: nothing.
begin transaction read only;
with d as (select replace(pg_get_functiondef('cmd.do_sell(uuid,jsonb)'::regprocedure), E'\r', '') as def),
o(n, old) as (values
  (1, E'  v_call    bigint;        -- 0474: the dock fee charged when she made this harbour (fleets.call_fee), taken by her first sale here\n'),
  (2, E'  v_call := f.call_fee;\n'),
  (3, E'      ''wages'', v_due, ''dock_fee'', coalesce(v_call, 0), ''trip_net'', v_profit - v_tax - v_due - coalesce(v_call, 0),   -- 0474\n'),
  (4, E'                            ''tax'', v_tax, ''wages'', v_wages, ''net'', q.total - v_tax - v_wages,\n'))
select (select max(version) from supabase_migrations.schema_migrations) as head,
       jsonb_object_agg('h' || o.n, (length(d.def) - length(replace(d.def, o.old, ''))) / length(o.old)) as hunks,
       bool_or(position('v_trip' in d.def) > 0) as applied,
       has_function_privilege('authenticated', 'cmd.do_sell(uuid,jsonb)', 'execute') or has_function_privilege('anon', 'cmd.do_sell(uuid,jsonb)', 'execute') as client_exec
  from d cross join o;
