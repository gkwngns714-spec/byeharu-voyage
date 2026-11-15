-- before.sql: READ ONLY on prod, one statement, BEFORE 0442 (owner row 352). The way proof 98 (ROW_HOLDS_COURSE) and proof 97 measure it:
--   lanes_off_row  remembered courses (public.npc_courses) that cross a sea their pair's row (public.sea_leg_asks) does not hold
--   own_rows_off   harbours whose own row does not name the sea their roadstead lies in (public.harbour_zone)
--   memo_missing   remembered courses with no row in the merchants' memo (each is sampled live here; want 0, so this read stays cheap)
-- Calls only STABLE functions: public.npc_course_zones (the memo's reader), public.harbour_zone. Want before 0442: head 20260818000441; lanes_off_row
-- and own_rows_off above 0 (the fault; 18 and 1 on the chain's own world). After 0442: both 0.
begin transaction read only;
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'lanes', (select count(*) from public.npc_courses),
  'memo_missing', (select count(*) from public.npc_courses n where not exists (select 1 from public.npc_course_zones_memo m where m.course_md5 = md5(n.course::text))),
  'lanes_off_row', (select count(*) from public.npc_courses n join public.sea_leg_asks s on s.from_port = n.from_port and s.to_port = n.to_port
                     where not s.zones @> public.npc_course_zones(n.course)),
  'lanes_off_row_list', (select string_agg(a.code || '-' || b.code, ' ' order by a.code, b.code)
                           from public.npc_courses n join public.sea_leg_asks s on s.from_port = n.from_port and s.to_port = n.to_port
                           join public.ports a on a.id = n.from_port join public.ports b on b.id = n.to_port
                          where not s.zones @> public.npc_course_zones(n.course)),
  'own_rows_off', (select string_agg(p.code || ':' || public.harbour_zone(p.id) || '/' || array_to_string(s.zones, '+'), ' ' order by p.code)
                     from public.ports p join public.sea_leg_asks s on s.from_port = p.id and s.to_port = p.id
                    where p.kind = 'HARBOUR' and s.zones <> array[public.harbour_zone(p.id)]),
  'pairs', (select count(*) from public.sea_leg_asks));
rollback;
