-- 0491 THE QUOTE IS ON HER COURSE, BEFORE. A PROD CHECK: read-only, ONE statement (begin read only ... rollback), the gate's three figures.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/quote-on-her-course/before-0491.sql
-- Expect: head 20260818000490 (S2's 0490 first); the digests of the chain's world at 0489, which 0491's guard and its rollback pin:
--   courses a9b593754530495de24d331cc3be1204, reaches_hh 3cbac251bb36faa50ba6710eadec9f7f, reaches_rest 9009e9f67a735c705e577806ec0d2a53,
--   haul 2ad60b0c9fb244c8f98a7c95cecc5499 (159,766 rows), job_course 11df277c754935805a787d035c659581.
--   A different reaches_hh or courses: 0491 refuses at the push (nothing changes). A different haul: rollback-0491.sql's c_haul pin is set
--   to prod's figure before the deploy. A different job_course: 0491's hunks refuse.
-- Reads: arrivals_beats (5 minutes), pg_class, pg_stat_activity, world_config by key, sea_courses (254 rows), sea_reaches (268 rows),
--   ports, goods, port_goods (159,766 rows, one pass), the matrix row, one pg_get_functiondef. No function that writes is called.
begin transaction read only;
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
  'matrix', (select md5(m.nm::text) from public.sea_reach_matrix m where m.id = 1)
) as r;
rollback;
