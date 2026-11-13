-- 0369 PROD CHECK (after the light, and again at +30 minutes), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/ship-stores/after-light.sql
-- Run it once BEFORE the deploy too: wanted then `lit` false, `news_rows` 0.
-- Wanted after: `lit` true; `news_rows` 1; `company_fleets_short` 0 and `merchant_fleets_short` 0 (no fleet with a leg under way or a stop on a standing route that its supply room
-- cannot carry: the read 0369 itself refuses on); `ships_over_room` may be above 0 on the first day (a hull keeps what she carried; it only falls) and must not rise between two reads;
-- `docked_route_fleets` is for the eye: merchants lying in port with a route, which should move as before at the +30 read (read scripts/ops/health.sh beside it).
-- Every function called is STABLE (public.ship_stores_separate, public.ship_stores_space, public.wc_num, voyage.endurance_mult, voyage.stores_need_days, voyage.fleet_speed): volatility.sql reads them on prod.
begin transaction read only;
with k as (
  select public.wc_num('water_per_crew_day') + public.wc_num('food_per_crew_day') as per_day
), legs as (
  select x.fleet_id, max(x.nm) as nm
    from (select v.fleet_id, v.total_nm as nm from public.voyages v where v.status = 'SAILING'
          union all
          select r.fleet_id, st.course_nm from public.standing_routes r join public.standing_route_stops st on st.route_id = r.id) x
   where x.fleet_id is not null group by x.fleet_id
), fl as (
  select l.fleet_id, l.nm, bool_or(p.is_npc) as is_npc,
         min(case when s.crew > 0 then public.ship_stores_space(s.id) / (s.crew * k.per_day) end) * voyage.endurance_mult(l.fleet_id) as lit_days
    from legs l join public.ships s on s.fleet_id = l.fleet_id join public.players p on p.id = s.player_id cross join k
   group by l.fleet_id, l.nm
), judged as (
  select fl.*, voyage.stores_need_days(fl.nm, greatest(voyage.fleet_speed(fl.fleet_id), 0.1)) as need from fl
)
select public.ship_stores_separate() as lit,
       (select c.updated_at from public.world_config c where c.key = 'ship_stores_separate') as switch_written_at,
       (select count(*) from public.world_news w where w.key = 'update:0369') as news_rows,
       (select count(*) from judged j) as fleets_with_a_leg,
       (select count(*) from judged j where not j.is_npc and j.lit_days < j.need - 0.01) as company_fleets_short,
       (select count(*) from judged j where j.is_npc and j.lit_days < j.need - 0.01) as merchant_fleets_short,
       (select count(*) from public.ships s where s.water_t + s.food_t > public.ship_stores_space(s.id) + 0.01) as ships_over_room,
       (select count(*) from public.fleets f join public.standing_routes r on r.fleet_id = f.id where f.status = 'DOCKED') as docked_route_fleets;
commit;
