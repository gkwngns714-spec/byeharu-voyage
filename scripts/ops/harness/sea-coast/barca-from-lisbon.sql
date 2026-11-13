-- 0401 PROD CHECK, read-only, ONE statement, run BEFORE and AFTER the deploy: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/sea-coast/barca-from-lisbon.sql
-- THE HARBOURS A BARCA (wave 12) REACHES FROM LISBON, at title 1, 3 and 11, two ways:
--   board     hop by hop over the pair table (public.sea_leg_asks, what Trade reads), legs within nav_leg_nm_base
--   courses   hop by hop over the courses the world remembers (public.npc_courses, real sailed lines, sampled as the sail door samples a course)
-- Local world: courses title 1: 82 before and after; title 3: 95 before, 104 after; title 11: 95 before, 104 after. `courses_rank_3_and_up` names what
-- she reaches beyond Macaronesia: after 0401 it holds Guinea and Angola and no harbour of the Americas. The board's figures are too high where a
-- straight line crosses land (a known gap, not this file's subject).
begin transaction read only;
with recursive hz as materialized (
  select p.id, p.code, public.harbour_zone(p.id) as zone, r.roadstead_lat as lat, r.roadstead_lon as lon
    from public.ports p join public.sea_reaches r on r.port_id = p.id where p.kind = 'HARBOUR'),
edge as materialized (
  select a.from_port as a, a.to_port as b, a.title_min as t, a.wave_min as w
    from public.sea_leg_asks a join hz f on f.id = a.from_port join hz g on g.id = a.to_port
   where a.from_port <> a.to_port and voyage.gc_distance_nm(f.lat, f.lon, g.lat, g.lon) <= public.wc_num('nav_leg_nm_base')),
ce as materialized (
  select c.from_port as a, c.to_port as b,
         (select max(z.title_min) from public.sea_zones z where z.code = any (public.course_zones(c.course) || array[public.harbour_zone(c.to_port), public.harbour_zone(c.from_port)])) as t,
         (select max(z.wave_min) from public.sea_zones z where z.code = any (public.course_zones(c.course) || array[public.harbour_zone(c.to_port), public.harbour_zone(c.from_port)])) as w
    from public.npc_courses c),
cee as (select a, b, t, w from ce union all select b, a, t, w from ce),
tt(title) as (values (1), (3), (11)),
board(title, port) as (
  select tt.title, (select id from hz where code = 'LIS') from tt
  union select w.title, e.b from board w join edge e on e.a = w.port and e.t <= w.title and e.w <= 12),
sailed(title, port) as (
  select tt.title, (select id from hz where code = 'LIS') from tt
  union select w.title, e.b from sailed w join cee e on e.a = w.port and e.t <= w.title and e.w <= 12)
select tt.title,
       (select count(*) - 1 from board b where b.title = tt.title) as board,
       (select count(*) - 1 from sailed s where s.title = tt.title) as courses,
       (select string_agg(h.code, ' ' order by h.code) from sailed s join hz h on h.id = s.port join public.sea_zones z on z.code = h.zone where s.title = tt.title and z.title_min >= 3) as courses_rank_3_and_up
  from tt order by 1;
commit;
