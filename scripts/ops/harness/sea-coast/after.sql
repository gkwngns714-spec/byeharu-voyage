-- 0401 PROD CHECK, AFTER the deploy, read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/sea-coast/after.sql
-- Wanted: zones 64; boxes NOR 10, PHI 3, SOU 5; kuroshio_wave 12; guinea_box true; off_liberia GUL, off_guianas CAR, off_luzon VIS,
-- mid_south_atlantic NOR-DOL, mid_atlantic NOR-DOL (the ocean is still a wall); paramaribo CAR; pair_rows = harbours squared; crossings: every figure
-- 24 or more; self_rows_wrong 0; news 1 (the row of 0401); courses_not_remembered 0; head 20260818000401.
-- Then barca-from-lisbon.sql again, beside the answer kept from before.
begin transaction read only;
select (select count(*) from public.sea_zones) as zones,
       (select jsonb_object_agg(s.code, q.n) from (select b.sea_id, count(*) as n from public.sea_zone_boxes b group by 1) q join public.seas s on s.id = q.sea_id where s.code in ('NOR', 'PHI', 'SOU')) as boxes,
       (select z.wave_min from public.sea_zones z where z.code = 'PHI-JP') as kuroshio_wave,
       exists (select 1 from public.sea_zone_boxes b join public.seas s on s.id = b.sea_id where s.code = 'NOR' and b.zone_code = 'GUL') as guinea_box,
       public.sea_zone_at(6, -12) as off_liberia, public.sea_zone_at(8, -55) as off_guianas, public.sea_zone_at(16, 124) as off_luzon,
       public.sea_zone_at(-10, -15) as mid_south_atlantic, public.sea_zone_at(5, -30) as mid_atlantic,
       (select public.harbour_zone(p.id) from public.ports p where p.code = 'PAR') as paramaribo,
       (select count(*) from public.sea_leg_asks) as pair_rows, (select count(*) from public.ports where kind = 'HARBOUR') as harbours,
       (select jsonb_object_agg(a.code || '-' || b.code, s.wave_min) from public.sea_leg_asks s join public.ports a on a.id = s.from_port join public.ports b on b.id = s.to_port
         where (a.code, b.code) in (('LIS', 'REC'), ('CID', 'REC'), ('LUA', 'REC'), ('LIS', 'HAV'), ('MNL', 'HAG'))) as crossings,
       (select count(*) from public.sea_leg_asks s where s.from_port = s.to_port and s.zones[1] is distinct from public.harbour_zone(s.from_port)) as self_rows_wrong,
       (select count(*) from public.world_news n where to_jsonb(n)::text like '%0401%') as news,
       (select count(*) from public.standing_route_stops st join public.npc_fleets nf on nf.route_id = st.route_id
         where not exists (select 1 from public.npc_course_zones_memo mm where mm.course_md5 = md5(st.course::text))) as courses_not_remembered,
       (select max(version) from supabase_migrations.schema_migrations) as head;
commit;
