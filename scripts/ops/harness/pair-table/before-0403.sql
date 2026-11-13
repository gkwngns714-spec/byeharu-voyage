-- 0403 PROD CHECK, BEFORE the deploy, read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/pair-table/before-0403.sql
-- Wanted: head 20260818000402; applied false; pair_rows = harbours squared (62001 = 249 x 249); same_world TRUE (the harbours, their roadsteads, the sea
-- raster and the sea boxes are the ones the courses were plotted on: if false, DO NOT deploy, re-run scripts/build-sea-legs.mjs against prod's data);
-- rows_off_the_straight_line 0 (the table is still the straight-line derivation); remembered_courses about 1061 or more, of which
-- remembered_crossing_a_sea_the_row_lacks is some hundreds (329 on the cached world: the gap this file closes); five: Suez-Alexandria and
-- Arkhangelsk-Bergen ask wave 10, Ayutthaya-Malacca 10, Cebu-Ternate and Cebu-Tidore 12; news_rows 0.
-- Functions called: public.sea_leg_asks_derive and public.course_zones (both stable). Then counts-0403.sql, and keep its answer.
begin transaction read only;
select (select max(version) from supabase_migrations.schema_migrations) as head,
       coalesce(obj_description('public.sea_leg_asks'::regclass, 'pg_class'), '') like '%0403%' as applied,
       (select count(*) from public.sea_leg_asks) as pair_rows, (select count(*) from public.ports where kind = 'HARBOUR') as harbours,
       (    md5((select string_agg(p.code, ' ' order by p.code collate "C") from public.ports p where p.kind = 'HARBOUR')) = '1694d2cfb9686e59984a9acd06eb5a15'
        and md5((select string_agg(p.code || ':' || sr.roadstead_lat || ',' || sr.roadstead_lon, ' ' order by p.code collate "C")
                   from public.ports p join public.sea_reaches sr on sr.port_id = p.id where p.kind = 'HARBOUR')) = '01f7e8a89f47ac12fd574402d61440ce'
        and md5((select encode(r.cells, 'hex') from public.sea_raster r where r.id = 1)) = 'fc79275a85438fe50876ce38376b91c9'
        and md5((select string_agg(encode(c.zones, 'hex'), '' order by c.row_idx) from public.sea_zone_cells c)) = 'b51294cf4e7d78432e5bd0538da55fba') as same_world,
       (select count(*) from public.sea_leg_asks s join public.sea_leg_asks_derive() d on d.from_port = s.from_port and d.to_port = s.to_port
         where not (s.zones @> d.zones and s.zones <@ d.zones) or s.wave_min <> d.wave_min or s.title_min <> d.title_min) as rows_off_the_straight_line,
       (select count(*) from public.npc_courses) as remembered_courses,
       (select count(*) from public.npc_courses n join public.sea_leg_asks s on s.from_port = n.from_port and s.to_port = n.to_port
         where not s.zones @> public.course_zones(n.course)) as remembered_crossing_a_sea_the_row_lacks,
       (select jsonb_object_agg(a.code || '-' || b.code, jsonb_build_array(s.wave_min, s.title_min, array_to_string(s.zones, ' ')))
          from public.sea_leg_asks s join public.ports a on a.id = s.from_port join public.ports b on b.id = s.to_port
         where (a.code, b.code) in (('SUE', 'ALE'), ('ARK', 'BER'), ('CEB', 'TER'), ('CEB', 'TID'), ('AYU', 'MAL'))) as five,
       (select count(*) from public.world_news n where n.key = 'update:0403') as news_rows;
commit;
