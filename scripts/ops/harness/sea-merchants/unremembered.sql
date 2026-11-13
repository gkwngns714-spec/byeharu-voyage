-- PROD CHECK, read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/sea-merchants/unremembered.sql
-- THE MERCHANTS' MEMO (public.npc_course_zones_memo, 0397) is a CACHE of the door's sampler. A merchant course with no row is not judged open and not
-- refused: public.npc_course_zones samples it live with public.course_zones (the same answer, slower). 0401's refill forgot 0400's coast courses, so
-- merchants that took a coast leg since then sail courses with no row. 0403 writes the missing rows. What to read:
--   unremembered_stops, unremembered_courses   merchant route legs, and distinct courses, with no memo row. Before 0403: some tens. After 0403: 0, and it
--                                              stays 0 while merchants only take remembered and coast legs (a later memo refill must keep the coast courses).
--   coast_courses, coast_unremembered          0400's coast courses, and those with no memo row. After 0403: coast_unremembered 0.
--   legs                                       the unremembered legs (from>to, how many merchants hold each), 40 at most.
--   memo_differs_from_sampler                  memo rows of merchant route courses whose seas are not the sampler's answer today. WANTED 0, always: a wrong
--                                              row WOULD misjudge a merchant.
--   loops_closed, closed_at_sea                merchant loops with a leg her hull cannot hold by the lit rule, judged with the sampler's live answer where
--                                              the memo has no row (public.npc_loop_sea_shut, as after-lit.sql reads it); and those now at sea. Lit, loops_closed
--                                              falls as each merchant reaches her lap start (after-lit.sql); it must not rise.
--   unremembered_loops_closed                  of the loops that hold an unremembered course, those with a leg her hull cannot hold: the same judgement, on
--                                              the legs in question. WANTED: no more than loops_closed, falling with it.
-- Functions called: public.course_zones, public.npc_loop_sea_shut (stable; after-lit.sql calls the second on prod already).
begin transaction read only;
with stops as (
  select st.route_id, st.ord, st.port_id, st.course, nf.fleet_id,
         exists (select 1 from public.npc_course_zones_memo m where m.course_md5 = md5(st.course::text)) as remembered
    from public.standing_route_stops st join public.npc_fleets nf on nf.route_id = st.route_id
   where jsonb_typeof(st.course) = 'array' and jsonb_array_length(st.course) > 0
), nxt as (
  select s.*, coalesce(lead(s.port_id) over w, first_value(s.port_id) over w) as to_port from stops s window w as (partition by s.route_id order by s.ord)
), loops as (
  select nf.fleet_id, nf.route_id, f.status,
         public.npc_loop_sea_shut(nf.fleet_id, (select jsonb_agg(jsonb_build_object('port_id', st.port_id, 'course', st.course) order by st.ord)
                                                  from public.standing_route_stops st where st.route_id = nf.route_id)) as shut
    from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id where nf.route_id is not null
)
select now() as read_at,
       (select value from public.world_config where key = 'sea_conditions_bite_npc') as switch_merchants,
       (select count(*) from stops where not remembered) as unremembered_stops,
       (select count(distinct md5(course::text)) from stops where not remembered) as unremembered_courses,
       (select count(*) from public.npc_coast_courses) as coast_courses,
       (select count(*) from public.npc_coast_courses cc where not exists (select 1 from public.npc_course_zones_memo m where m.course_md5 = md5(cc.course::text))) as coast_unremembered,
       (select jsonb_agg(x.leg order by x.leg) from (select a.code || '>' || b.code || ' x' || count(*) as leg
                                                        from nxt n join public.ports a on a.id = n.port_id join public.ports b on b.id = n.to_port
                                                       where not n.remembered group by a.code, b.code order by 1 limit 40) x) as legs,
       (select count(*) from (select distinct md5(s.course::text) as h, s.course from stops s where s.remembered) d
          join public.npc_course_zones_memo m on m.course_md5 = d.h
         where not (m.zones @> public.course_zones(d.course) and m.zones <@ public.course_zones(d.course))) as memo_differs_from_sampler,
       (select count(*) from loops where shut) as loops_closed,
       (select count(*) from loops where shut and status <> 'DOCKED') as closed_at_sea,
       (select count(*) from loops l where l.shut and exists (select 1 from stops s where s.route_id = l.route_id and not s.remembered)) as unremembered_loops_closed;
commit;
