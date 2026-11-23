-- THE COUNTRY RACE (0484), AFTER; ALSO THE 30-MINUTE LIT CHECK. A PROD CHECK: read-only, ONE statement, with the gate's three figures.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/nation-race/after-0484.sql
-- Expect, AS DEPLOYED (dark): head 20260818000484; `knobs.nation_race_enabled` false and 8 knobs; `hunked` 6 (each hunked body holds its
-- new line once); `stable` true; `client_reach` false (no core, the tick or a table reachable by a client; world.nation_race for
-- authenticated alone); `cron` the job byeharu-voyage:nation-race hourly at :21; `rows` {book: 0, weeks: 0}; `kind` true.
-- LIT (30 minutes after the owner lights nation_race_enabled): `book_week` this week's rows, points and companies; `leaders` the race
-- cities led and by whom; `runs_30m` the cron's runs (pg_cron's own record: their mean and max milliseconds and failures; a run outside
-- Monday's first hours settles nothing); `weeks` the settled weeks (the first lit run settles last week, empty: winner null); the gate
-- green.
-- ROLLBACK if `client_reach` true, `stable` false, a run's max over 5,000 ms, a run failing, or the gate red: nation_race_enabled false
-- (owner): nothing is written, the dock fee and the board are as before; the rows stay, inert.
-- Reads: arrivals_beats (5 minutes), pg_class, pg_stat_activity, world_config by key, the catalog, cron.job and cron.job_run_details (30
-- minutes), nation_race_book (this week's: a few hundred rows at most), nation_race_weeks (a row a week), reputation_kinds. No function
-- that writes is called. ROLLBACK: nothing to roll back (read only; ends with rollback).
begin transaction read only;
select jsonb_build_object(
  'at', now(),
  'gate', jsonb_build_object(
    'beat_mean_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'database_mb', (select (sum(c.relpages)::numeric * 8192 / 1048576)::int from pg_class c where c.relkind in ('r', 'i', 't', 'm', 'S', 'p')),
    'io_waiting', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.wait_event_type = 'IO' and a.state = 'active')),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'knobs', (select jsonb_object_agg(c.key, c.value) from public.world_config c where c.key like 'nation\_race\_%'),
  'hunked', (select count(*) from (values
               ('cmd.do_sell(uuid,jsonb)', 'public.nation_race_sale(f.player_id, f.port_id, q.total)'),
               ('cmd.run_fulfil(uuid,uuid)', 'public.nation_race_job(f.player_id, c.port_id, v_pay)'),
               ('public.pay_city(uuid,uuid,text,bigint,uuid)', 'public.nation_race_gift(p_player, p_port, p_amount)'),
               ('public.port_fee(uuid,uuid,numeric)', 'public.nation_fee_factor(p_player, p_port)'),
               ('public.hq_board_for(uuid)', 'public.nation_race_marks(p_player, v_moves)'),
               ('public.client_rpc_entry_points()', '''nation_race''')) h(fn, line)
              where position(h.line in pg_get_functiondef(h.fn::regprocedure)) > 0),
  'stable', (select count(*) from pg_proc p
              where p.oid = any (array['public.nation_race_on()', 'public.nation_race_week(timestamptz)', 'public.nation_race_city(uuid)',
                                       'public.nation_fee_factor(uuid,uuid)', 'public.nation_race_leaders(bigint)', 'public.nation_race_standings(bigint)',
                                       'public.nation_race_marks(uuid,jsonb)', 'world.nation_race()']::regprocedure[]::oid[]) and p.provolatile = 's') = 8,
  'client_reach', has_table_privilege('authenticated', 'public.nation_race_book', 'select')
                  or has_table_privilege('authenticated', 'public.nation_race_weeks', 'select')
                  or has_function_privilege('authenticated', 'public.tick_nation_race(timestamptz)', 'execute')
                  or has_function_privilege('authenticated', 'public.nation_race_post(uuid,uuid,bigint)', 'execute')
                  or has_function_privilege('authenticated', 'public.nation_race_settle(bigint,timestamptz)', 'execute')
                  or has_function_privilege('anon', 'world.nation_race()', 'execute')
                  or not has_function_privilege('authenticated', 'world.nation_race()', 'execute'),
  'kind', exists (select 1 from public.reputation_kinds k where k.code = 'nation_race'),
  'cron', (select jsonb_agg(jsonb_build_object('name', j.jobname, 'schedule', j.schedule, 'active', j.active)) from cron.job j
            where j.jobname = 'byeharu-voyage:nation-race'),
  'rows', jsonb_build_object('book', (select count(*) from public.nation_race_book), 'weeks', (select count(*) from public.nation_race_weeks)),
  'book_week', (select jsonb_build_object('rows', count(*), 'points', coalesce(sum(b.points), 0), 'companies', count(distinct b.player_id))
                  from public.nation_race_book b where b.week = floor((extract(epoch from now()) - 345600) / 604800)),
  'leaders', (select coalesce(jsonb_object_agg(x.code, x.n), '{}'::jsonb)
                from (select n.code, count(*) as n
                        from (select distinct on (b.port_id) b.port_id, b.nation_id
                                from (select b.port_id, b.nation_id, sum(b.points) as pts from public.nation_race_book b
                                       where b.week = floor((extract(epoch from now()) - 345600) / 604800) group by 1, 2) b
                               order by b.port_id, b.pts desc) l
                        join public.nations n on n.id = l.nation_id group by n.code) x),
  'weeks', (select coalesce(jsonb_agg(jsonb_build_object('week', w.week, 'winner', w.winner, 'champions', jsonb_array_length(w.champions), 'at', w.settled_at)
                                      order by w.week desc), '[]'::jsonb)
              from (select * from public.nation_race_weeks order by week desc limit 3) w),
  'runs_30m', (select jsonb_build_object('runs', count(*), 'failed', count(*) filter (where d.status <> 'succeeded'),
                                         'mean_ms', round(avg(extract(epoch from d.end_time - d.start_time) * 1000)),
                                         'max_ms', round(max(extract(epoch from d.end_time - d.start_time) * 1000)))
                 from cron.job_run_details d join cron.job j on j.jobid = d.jobid
                where j.jobname = 'byeharu-voyage:nation-race' and d.start_time > now() - interval '30 minutes')
) as r;
rollback;
