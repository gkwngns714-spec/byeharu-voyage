-- 0491 THE QUOTE IS ON HER COURSE, AFTER; ALSO THE 30-MINUTE AFTER-CHECK. A PROD CHECK: read-only, ONE statement, the gate's figures.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/quote-on-her-course/after-0491.sql
-- Expect, right after: head 20260818000491; digests courses a9b593754530495de24d331cc3be1204 (unmoved), reaches_hh
--   8e418cd663c8c3790b94f9c4fe57e2b9, reaches_rest 9009e9f67a735c705e577806ec0d2a53 (unmoved), job_course 40599d42a7fb56879c6d636fc0f97af7;
--   `guard` 0 (every market row's haul is world.haul_rows()'s); `matrix_kept` true.
-- THE 30-MINUTE CHECK (the same file, 30 minutes on): the gate green; `best_sales_ms` one world.best_sales for the newest company's idle
--   fleet at Lisbon (null if none); `sailing` fleets at sea now; `ledger` and `treasury` [rows, sum] by kind in the last 30 minutes, then
--   the 30 before (merchants still sail and sell; no kind gone or swollen); `cron_60m` per job [runs, failed, max ms] in the last 30
--   minutes, then [runs, failed] the 30 before.
-- ROLLBACK (scripts/ops/harness/quote-on-her-course/rollback-0491.sql) if: the gate red, a failed fleet-jobs or contracts run the 30
--   minutes before did not have, sales collapsing against the 30 minutes before, `guard` > 0, or best_sales far over its before.
-- Reads: arrivals_beats (5 minutes), the catalog, world_config by key, sea_courses, sea_reaches, ports, goods, port_goods (two passes:
--   the digest and the guard; world.haul_rows() is STABLE), the matrix (sea_reach_matrix_build STABLE, once), fleets (a count), ledger
--   and treasury_flows over 60 minutes by their created_at indexes, cron.job_run_details (60 minutes), ONE world.best_sales (STABLE).
--   No function that writes is called. Read only; ends with rollback.
begin transaction read only;
with who as materialized (
  select f.player_id, f.id as fleet, f.port_id,
         set_config('request.jwt.claim.sub', p.auth_uid::text, true) as a,
         set_config('request.jwt.claims', json_build_object('sub', p.auth_uid)::text, true) as b
    from public.fleets f join public.players p on p.id = f.player_id join public.ports pt on pt.id = f.port_id
   where pt.code = 'LIS' and f.status = 'DOCKED' and not p.is_npc
     and not exists (select 1 from public.orders o where o.fleet_id = f.id and o.status in ('pending', 'active'))
   order by p.created_at desc, f.created_at, f.id limit 1
), t0 as materialized (select clock_timestamp() as t0 from who
), bs as materialized (select t0.t0, world.best_sales(who.fleet, who.port_id) as r, clock_timestamp() as t1 from t0, who
)
select json_build_object(
  'at', now(),
  'gate', json_build_object(
    'beat_mean_ms', (select round(avg(b.ms)) from public.arrivals_beats b where b.at > now() - interval '5 minutes'),
    'database_mb', (select (sum(c.relpages)::numeric * 8192 / 1048576)::int from pg_class c where c.relkind in ('r', 'i', 't', 'm', 'S', 'p')),
    'io_waiting', (select count(*) from pg_stat_activity a where a.pid <> pg_backend_pid() and a.wait_event_type = 'IO' and a.state = 'active')),
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'sea_courses_enabled', (select c.value from public.world_config c where c.key = 'sea_courses_enabled'),

  'courses', (select md5(string_agg(p.code || ':' || array_to_string(c.tos, ',') || ':' || array_to_string(c.offs, ',') || ':' || md5(c.pts), '|' order by p.code collate "C"))
                from public.sea_courses c join public.ports p on p.id = c.port_id),
  'reaches_hh', (select md5(string_agg(a.code || '>' || e.key || '=' || e.value, ',' order by a.code collate "C", e.key collate "C"))
                   from public.sea_reaches a join public.ports pa on pa.id = a.port_id and pa.kind = 'HARBOUR'
                  cross join lateral jsonb_each_text(a.reaches) e
                  where exists (select 1 from public.ports pb where pb.code = e.key and pb.kind = 'HARBOUR')),
  'reaches_rest', (select md5(string_agg(a.code || '>' || e.key || '=' || e.value, ',' order by a.code collate "C", e.key collate "C"))
                     from public.sea_reaches a cross join lateral jsonb_each_text(a.reaches) e
                    where not (exists (select 1 from public.ports pa where pa.id = a.port_id and pa.kind = 'HARBOUR')
                               and exists (select 1 from public.ports pb where pb.code = e.key and pb.kind = 'HARBOUR'))),
  'haul', (select md5(string_agg(p.code || '/' || g.code || '=' || coalesce(pg.haul_nm::text, '-') || ':' || coalesce(pg.haul::text, '-'), ',' order by p.code collate "C", g.code collate "C"))
             from public.port_goods pg join public.ports p on p.id = pg.port_id join public.goods g on g.id = pg.good_id),
  'haul_rows', (select count(*) from public.port_goods),
  'job_course', (select md5(replace(pg_get_functiondef('public.fleet_job_course(uuid,uuid,uuid)'::regprocedure), E'\r', ''))),
  'matrix', (select md5(m.nm::text) from public.sea_reach_matrix m where m.id = 1),
  'guard', (select count(*) from public.port_goods pg join world.haul_rows() h on h.port_id = pg.port_id and h.good_id = pg.good_id
             where (pg.haul_nm, pg.haul) is distinct from (h.haul_nm, h.haul)),
  'matrix_kept', (select count(*) = 1 from public.sea_reach_matrix m, public.sea_reach_matrix_build() b
                   where m.id = 1 and m.ids = b.ids and m.codes = b.codes and m.nm = b.nm),
  'best_sales_ms', (select round(extract(epoch from bs.t1 - bs.t0) * 1000) from bs),
  'best_sales_cut', (select bs.r -> 'cut' from bs),
  'sailing', (select count(*) from public.fleets f where f.status = 'SAILING'),
  'ledger', (select json_object_agg(x.kind, json_build_array(x.n_now, x.sum_now, x.n_before, x.sum_before))
               from (select l.kind, count(*) filter (where l.created_at > now() - interval '30 minutes') n_now,
                            coalesce(sum(l.ducats_delta) filter (where l.created_at > now() - interval '30 minutes'), 0) sum_now,
                            count(*) filter (where l.created_at <= now() - interval '30 minutes') n_before,
                            coalesce(sum(l.ducats_delta) filter (where l.created_at <= now() - interval '30 minutes'), 0) sum_before
                       from public.ledger l where l.created_at > now() - interval '60 minutes' group by l.kind) x),
  'treasury', (select json_object_agg(x.kind, json_build_array(x.n_now, x.sum_now, x.n_before, x.sum_before))
                 from (select f.kind, count(*) filter (where f.created_at > now() - interval '30 minutes') n_now,
                              coalesce(sum(f.ducats) filter (where f.created_at > now() - interval '30 minutes'), 0) sum_now,
                              count(*) filter (where f.created_at <= now() - interval '30 minutes') n_before,
                              coalesce(sum(f.ducats) filter (where f.created_at <= now() - interval '30 minutes'), 0) sum_before
                         from public.treasury_flows f where f.created_at > now() - interval '60 minutes' group by f.kind) x),
  'cron_60m', (select json_object_agg(x.jobname, json_build_array(x.runs_now, x.failed_now, x.max_ms_now, x.runs_before, x.failed_before))
                 from (select j.jobname, count(*) filter (where d.start_time > now() - interval '30 minutes') runs_now,
                              count(*) filter (where d.start_time > now() - interval '30 minutes' and d.status <> 'succeeded') failed_now,
                              round(max(extract(epoch from d.end_time - d.start_time) * 1000) filter (where d.start_time > now() - interval '30 minutes')) max_ms_now,
                              count(*) filter (where d.start_time <= now() - interval '30 minutes') runs_before,
                              count(*) filter (where d.start_time <= now() - interval '30 minutes' and d.status <> 'succeeded') failed_before
                         from cron.job_run_details d join cron.job j on j.jobid = d.jobid
                        where d.start_time > now() - interval '60 minutes' group by j.jobname) x)
) as r;
rollback;
