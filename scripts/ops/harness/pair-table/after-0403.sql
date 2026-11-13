-- 0403 PROD CHECK, AFTER the deploy, read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/pair-table/after-0403.sql
-- Wanted: head 20260818000403; applied true; pair_rows = harbours squared; same_world true; rows_off_the_straight_line about 51,000 (50,976 on the cached
-- world: THE COUNT OF PAIR ROWS THIS FILE CHANGED; 34,697 of them ask another title or wave); remembered_crossing_a_sea_the_row_lacks 0;
-- five: Suez-Alexandria asks wave 44 by the Cape (SOU-CAPE among its seas), Arkhangelsk-Bergen 12 by the Barents and Norwegian seas (no BAL),
-- Ayutthaya-Malacca 12 with the South China Sea (SOA), Cebu-Ternate and Cebu-Tidore 12 with no PHI; news_rows 1.
-- Functions called: public.sea_leg_asks_derive and public.course_zones (both stable). Then counts-0403.sql again, beside the answer kept from before.
-- merchant_stops_with_no_memo_row 0 (healed); rows_not_asking_the_most_of_their_seas 0 (ALL 62,001 rows, the check the migration samples 50 of).
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
       (select count(*) from public.standing_route_stops st join public.npc_fleets nf on nf.route_id = st.route_id
         where not exists (select 1 from public.npc_course_zones_memo m where m.course_md5 = md5(st.course::text))) as merchant_stops_with_no_memo_row,
       (select count(*) from public.sea_leg_asks s join public.sea_leg_asks own on own.from_port = s.to_port and own.to_port = s.to_port
         where s.wave_min <> (select max(z.wave_min) from public.sea_zones z where z.code = any (s.zones || own.zones))
            or s.title_min <> (select max(z.title_min) from public.sea_zones z where z.code = any (s.zones || own.zones))) as rows_not_asking_the_most_of_their_seas,
       (select count(*) from public.world_news n where n.key = 'update:0403') as news_rows;
commit;
