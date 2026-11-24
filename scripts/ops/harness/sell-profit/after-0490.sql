-- A SALE SHOWS ITS PROFIT BEFORE THE PRESS (0490), AFTER. A PROD CHECK: read-only, ONE statement, the catalog only.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/sell-profit/after-0490.sql
-- Expect: head 20260818000490; v_trip 5 (declared, set once, written on the SOLD event (and named in its comment), returned); returns true (the result carries
--   'trip_net', v_trip and the event's dock fee); old_expr 0 (0474's inline expression is gone: one computation); client_exec false.
-- Reads: supabase_migrations.schema_migrations, pg_proc. Nothing is written. ROLLBACK: nothing (ends with rollback).
begin transaction read only;
with d as (select replace(pg_get_functiondef('cmd.do_sell(uuid,jsonb)'::regprocedure), E'\r', '') as def)
select (select max(version) from supabase_migrations.schema_migrations) as head,
       (length(d.def) - length(replace(d.def, 'v_trip', ''))) / length('v_trip') as v_trip,
       position(E'''dock_fee'', coalesce(v_call, 0), ''trip_net'', v_trip,\n' in d.def) > 0 as returns,
       (length(d.def) - length(replace(d.def, '''trip_net'', v_profit - v_tax', ''))) / length('''trip_net'', v_profit - v_tax') as old_expr,
       has_function_privilege('authenticated', 'cmd.do_sell(uuid,jsonb)', 'execute') or has_function_privilege('anon', 'cmd.do_sell(uuid,jsonb)', 'execute') as client_exec
  from d;
rollback;
