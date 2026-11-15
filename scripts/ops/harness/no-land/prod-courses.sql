-- READ ONLY, one statement: every distinct stored course prod holds (lanes, coast courses, route stops), as Postgres's own text,
-- with the raster's md5 and the roadsteads, for scripts/db/audit-land-crossings.mjs (owner row 352). No function but md5/encode.
begin transaction read only;
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'at', now(),
  'raster_md5', (select md5(replace(encode(r.cells, 'base64'), E'\n', '')) from public.sea_raster r where r.id = 1),
  'roads', (select jsonb_agg(jsonb_build_array(p.code, sr.roadstead_lat::text, sr.roadstead_lon::text, sr.snap_nm::text) order by p.code)
              from public.sea_reaches sr join public.ports p on p.id = sr.port_id),
  'npc', (select jsonb_agg(jsonb_build_array(a.code, b.code, c.course::text) order by a.code, b.code)
            from public.npc_courses c join public.ports a on a.id = c.from_port join public.ports b on b.id = c.to_port),
  'coast', (select jsonb_agg(jsonb_build_array(a.code, b.code, c.course::text) order by a.code, b.code)
              from public.npc_coast_courses c join public.ports a on a.id = c.from_port join public.ports b on b.id = c.to_port),
  'stops', (select jsonb_agg(jsonb_build_array(x.code, x.n, x.t) order by x.code, x.t)
              from (select p.code, s.course::text as t, count(*) as n
                      from public.standing_route_stops s join public.ports p on p.id = s.port_id
                     where s.course is not null group by p.code, s.course::text) x));
rollback;
