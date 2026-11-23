-- COURIER CONTRACTS (0483), AFTER; ALSO THE 30-MINUTE LIT CHECK. A PROD CHECK: read-only, ONE statement, with the gate's three figures.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/contracts/after-0483.sql
-- Expect, AS DEPLOYED (dark): head 20260818000483; `knobs.contracts_enabled` false and 23 knobs; `hunked` true (public.hq_board_for holds
-- the courier_moves line, public.client_rpc_entry_points the six doors); `stable` true; `client_reach` false (no core, the tick or the
-- table reachable by a client); `cron` the job byeharu-voyage:contracts every 2 minutes; `rows` 0; `flow_words` the five kinds.
-- LIT (30 minutes after the owner lights contracts_enabled): `live` the open contracts by poster (house + city at most `cap`, ceil(houses /
-- 20)), the taken; `settled_30m` delivered / failed / lapsed / cancelled in the last 30 minutes; `runs_30m` the cron's runs, their mean
-- and max milliseconds (pg_cron's own record) and their failures; `ledger_30m` the five kinds' rows and sum (the sum of the escrows held
-- and paid out: it moves money, it never makes any); the gate green.
-- ROLLBACK if `client_reach` true, `stable` false, a run's max over 5,000 ms, a run failing, or the gate red: contracts_enabled false
-- (owner): no post and no take; the taken wait, their collateral and goods held, until it is lit again.
-- Reads: arrivals_beats (5 minutes), pg_class, pg_stat_activity, world_config by key, the catalog, cron.job and cron.job_run_details (30
-- minutes), courier_contracts (small), the ledger by kind over 30 minutes (its (player_id, created_at) index does not serve a kind: on
-- the 30-minute window it is a bounded scan; drop `ledger_30m` if the beat is slow), npc_houses (a count). No function that writes is
-- called. ROLLBACK: nothing to roll back (read only; ends with rollback).
begin transaction read only;
select jsonb_build_object(
  'at', now(),
  'gate', jsonb_build_object(
    'beat_mean_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'database_mb', (select (sum(c.relpages)::numeric * 8192 / 1048576)::int from pg_class c where c.relkind in ('r', 'i', 't', 'm', 'S', 'p')),
    'io_waiting', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.wait_event_type = 'IO' and a.state = 'active')),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'knobs', (select jsonb_object_agg(c.key, c.value) from public.world_config c where c.key like 'contracts\_%'),
  'hunked', position('public.courier_moves(p_player, v_purse)' in pg_get_functiondef('public.hq_board_for(uuid)'::regprocedure)) > 0
            and (select count(*) from public.client_rpc_entry_points() e
                  where e.function_name in ('take_contract', 'deliver_contract', 'fail_contract', 'post_contract', 'cancel_contract', 'courier_contracts')
                    and e.fn is not null) = 6,
  'stable', (select count(*) from pg_proc p
              where p.oid = any (array['public.courier_on()', 'public.courier_state(uuid,timestamptz)', 'public.courier_moves(uuid,bigint)',
                                       'public.courier_rows(uuid,text)', 'world.courier_contracts()']::regprocedure[]::oid[]) and p.provolatile = 's') = 5,
  'client_reach', has_table_privilege('authenticated', 'public.courier_contracts', 'select')
                  or has_function_privilege('authenticated', 'public.tick_courier_contracts(timestamptz)', 'execute')
                  or has_function_privilege('authenticated', 'public.courier_settle(uuid,text,text,timestamptz)', 'execute')
                  or has_function_privilege('anon', 'cmd.take_contract(uuid,uuid,integer)', 'execute'),
  'cron', (select jsonb_agg(jsonb_build_object('name', j.jobname, 'schedule', j.schedule, 'active', j.active)) from cron.job j
            where j.jobname = 'byeharu-voyage:contracts'),
  'rows', (select count(*) from public.courier_contracts),
  'flow_words', (select coalesce(jsonb_agg(w.kind order by w.ord), '[]'::jsonb) from public.stats_flow_words w where w.kind like 'CONTRACT\_%'),
  'cap', (select ceil(count(*)::numeric / greatest((select (c.value #>> '{}')::numeric from public.world_config c where c.key = 'contracts_houses_per'), 1))
            from public.npc_houses),
  'live', (select coalesce(jsonb_object_agg(x.k, x.n), '{}'::jsonb)
             from (select c.status || ':' || c.poster_kind as k, count(*) as n from public.courier_contracts c
                    where c.status in ('open', 'taken') group by 1) x),
  'settled_30m', (select coalesce(jsonb_object_agg(x.status, x.n), '{}'::jsonb)
                    from (select c.status, count(*) as n from public.courier_contracts c
                           where c.settled_at > now() - interval '30 minutes' group by 1) x),
  'runs_30m', (select jsonb_build_object('runs', count(*), 'failed', count(*) filter (where d.status <> 'succeeded'),
                                         'mean_ms', round(avg(extract(epoch from d.end_time - d.start_time) * 1000)),
                                         'max_ms', round(max(extract(epoch from d.end_time - d.start_time) * 1000)))
                 from cron.job_run_details d join cron.job j on j.jobid = d.jobid
                where j.jobname = 'byeharu-voyage:contracts' and d.start_time > now() - interval '30 minutes'),
  'ledger_30m', (select jsonb_build_object('rows', count(*), 'sum', coalesce(sum(l.ducats_delta), 0))
                   from public.ledger l where l.created_at > now() - interval '30 minutes' and l.kind like 'CONTRACT\_%')
) as r;
rollback;
