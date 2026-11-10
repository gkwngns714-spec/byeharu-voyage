-- 0345 PROD READ (what lighting ship_stores_separate WOULD do), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/ship-stores/impact.sql
-- Runs BEFORE 0345 exists, so the stores space is spelt here as 0345 spells it: floor(ceil(class crew_max x (water_per_crew_day + food_per_crew_day) x 36) x roll_stores).
-- Per side (human / merchant-or-crown house): ships, fleets, stores aboard (the cargo room lit gives back), stores space made, ships carrying more than their space,
-- the least lit stores-days of any crewed fleet (her shortest hull, x voyage.endurance_mult), and the fleets whose longest leg asked (a voyage under way or a standing-route stop),
-- at today's speed (voyage.stores_need_days), today's carry (public.supply_reach) and lit would not fit.
-- Every function called is STABLE (voyage.fleet_speed, voyage.endurance_mult, voyage.stores_need_days, public.supply_reach, public.wc_num): read on prod by volatility.sql.
begin transaction read only;
with k as (
  select public.wc_num('water_per_crew_day') + public.wc_num('food_per_crew_day') as per_day
), sh as (
  select s.id, s.fleet_id, p.is_npc, s.crew, s.water_t + s.food_t as aboard,
         floor(ceil(c.crew_max * k.per_day * 36) * s.roll_stores) as space, k.per_day
    from public.ships s join public.ship_classes c on c.id = s.class_id join public.players p on p.id = s.player_id cross join k
), fl as (
  select sh.fleet_id, bool_or(sh.is_npc) as is_npc,
         min(case when sh.crew > 0 then sh.space / (sh.crew * sh.per_day) end) * voyage.endurance_mult(sh.fleet_id) as lit_days
    from sh group by sh.fleet_id
), legs as (
  select x.fleet_id, max(x.nm) as nm
    from (select v.fleet_id, v.total_nm as nm from public.voyages v where v.status = 'SAILING'
          union all
          select r.fleet_id, st.course_nm from public.standing_routes r join public.standing_route_stops st on st.route_id = r.id) x
   where x.fleet_id is not null group by x.fleet_id
), judged as (
  select fl.*, l.nm, voyage.stores_need_days(l.nm, greatest(voyage.fleet_speed(fl.fleet_id), 0.1)) as need,
         (select r.carry_days from public.supply_reach(fl.fleet_id) r) as dark_days
    from fl left join legs l on l.fleet_id = fl.fleet_id
)
select case when s.is_npc then 'npc' else 'human' end as side,
       count(*) as ships, count(distinct s.fleet_id) as fleets,
       round(sum(s.aboard), 1) as stores_aboard_t, sum(s.space) as space_made_t,
       count(*) filter (where s.aboard > s.space) as ships_over_space,
       (select round(min(j.lit_days), 1) from judged j where j.is_npc = s.is_npc) as least_lit_days,
       (select round(percentile_cont(0.5) within group (order by j.lit_days)::numeric, 1) from judged j where j.is_npc = s.is_npc) as p50_lit_days,
       (select round(max(j.need), 1) from judged j where j.is_npc = s.is_npc) as longest_leg_need_days,
       (select count(*) from judged j where j.is_npc = s.is_npc and j.nm is not null) as fleets_with_a_leg,
       (select count(*) from judged j where j.is_npc = s.is_npc and j.nm is not null and j.dark_days < j.need - 0.01) as short_today,
       (select count(*) from judged j where j.is_npc = s.is_npc and j.nm is not null and j.lit_days < j.need - 0.01) as short_lit
  from sh s group by s.is_npc order by 1;
commit;
