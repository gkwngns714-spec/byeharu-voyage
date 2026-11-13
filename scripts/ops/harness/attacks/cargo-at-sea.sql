-- ATTACKS, PROD CHECK (the cargo ships of the world), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/attacks/cargo-at-sea.sql
-- THE "FREE GOLD" QUESTION, read BEFORE attack_enabled is lit (docs/COMBAT_LOG.md 3.6, R11; docs/dev-log/2026-11-13-attacks-ready.md). 0327's sim: a crewless unarmed qpinnace loses 92 % of
-- fights to one xebec and never fires. 0328 (convoy_armed_enabled, lit on prod 2026-11-07) refits an idle ship at home to an armed navire and takes up to 60 hands at each departure, but
-- "a quay with none gives none and she sails short". This reads what really sails: every cargo ship's class, whether she has guns, her hands against her class's crew_required, her hull,
-- whether she is at sea (SAILING or ANCHORED: the only ships public.attack_for takes) and the funds aboard (public.cargo_ship_aboard: what a boarding takes its share of).
--   switches   the switches the lighting file's guard reads, and the caps.
--   ships      every cargo ship, by state: `armed and crewed` (guns, hands >= crew_required), `armed but short-handed` (guns, fewer hands), `unarmed` (no guns: the old hull).
--   by_class   the same count by class, state and where she is (at sea / in port / laid up), with the least and the mean share of hands and of hull.
--   at_sea     the ships that can be attacked now, by state, and by hands: none, under 25 %, under 50 %, under 100 %, full.
--   unsafe     THE FIGURE THE LIGHTING FILE'S GUARD READS (0375): ships at sea that are UNARMED (the old hull). `share` is of the ships at sea. 0375 refuses to light while
--              share > 0.10. Why unarmed alone: the sim (scripts/ops/harness/attacks/sim.mjs, the dev-log's tables) found her hands change almost nothing (a navire with no hands
--              is beaten by the same fleets, as often, as one with all 60: the guns decide it), while the unarmed hull is taken by ANY fleet with a gun in 9 fights of 10.
--              `under_half_hands` is printed beside it for reading, not judged. Since 0374 an unarmed ship yields no loot either way (the attacker loses no hull to her).
--   aboard     the funds aboard the ships at sea: how many carry any, the median, the 90th centile, the most, and how many carry 400,000 or more (a boarding there reaches loot_per_ship).
--   worst      the 25 worst ships at sea: unarmed first, then the fewest hands, then the weakest hull; her country, name, class, hands / crew_required, hull %, status, funds aboard.
-- Wanted before lighting: unsafe.share <= 0.10 (unarmed ships at sea: only ships on their last lap in the old hull). Every function called is STABLE (public.cargo_ship_aboard, public.ship_base, the switch readers).
-- Bounded: public.cargo_ships is a few hundred rows (20 to 50 a great power); no growing table is read whole (convoy_cargo is read by its fleet index, one load a ship).
begin transaction read only;
with s as (
  select c.fleet_id, n.code as nation, f.name, f.status, c.laid_up_at is not null as laid_up, k.code as class, k.attack > 0 as guns, sh.crew, k.crew_required,
         case when k.crew_required > 0 then least(1, sh.crew::numeric / k.crew_required) else 1 end as hands,
         case when b.durability > 0 then least(1, sh.durability::numeric / b.durability) else 0 end as hull,
         f.status in ('SAILING', 'ANCHORED') and c.laid_up_at is null as at_sea,
         coalesce((select a.aboard from public.cargo_ship_aboard(c.fleet_id) a), 0) as aboard
    from public.cargo_ships c
    join public.nations n on n.id = c.nation_id
    join public.fleets f on f.id = c.fleet_id
    join public.ships sh on sh.fleet_id = c.fleet_id and sh.is_flagship
    join public.ship_classes k on k.id = sh.class_id
    cross join lateral (select max(sb.durability) as durability from public.ship_base(sh.id) sb) b),
t as (
  select s.*, case when not s.guns then 'unarmed' when s.crew >= s.crew_required then 'armed and crewed' else 'armed but short-handed' end as state,
         case when s.laid_up then 'laid up' when s.at_sea then 'at sea' else 'in port' end as place,
         (not s.guns) as unsafe
    from s)
select jsonb_build_object(
         'attack_enabled', public.attack_on(), 'convoy_armed_enabled', public.cargo_armed_on(), 'regard_enabled', public.regard_on(), 'navy_enabled', public.navy_on(),
         'npc_ship_level_enabled', public.wc('npc_ship_level_enabled'), 'npc_refits_enabled', public.wc('npc_refits_enabled'), 'navy_hunt_per_day', public.wc('navy_hunt_per_day'),
         'cargo_class', public.cargo_class(), 'npc_crew_pool_floor', public.wc('npc_crew_pool_floor'),
         'loot_share', public.wc('loot_share'), 'loot_per_ship', public.wc('loot_per_ship'), 'loot_per_company_day', public.wc('loot_per_company_day'),
         'loot_risk_full', public.wc('loot_risk_full'), 'loot_risk_floor', public.wc('loot_risk_floor')) as switches,
       (select jsonb_object_agg(x.state, x.n) from (select t.state, count(*) as n from t group by t.state) x) as ships,
       (select jsonb_agg(jsonb_build_object('class', x.class, 'state', x.state, 'place', x.place, 'ships', x.n, 'hands_least', x.hands_least, 'hands_mean', x.hands_mean,
                                            'hull_least', x.hull_least, 'hull_mean', x.hull_mean) order by x.class, x.state, x.place)
          from (select t.class, t.state, t.place, count(*) as n, round(min(t.hands), 2) as hands_least, round(avg(t.hands), 2) as hands_mean,
                       round(min(t.hull), 2) as hull_least, round(avg(t.hull), 2) as hull_mean
                  from t group by t.class, t.state, t.place) x) as by_class,
       (select jsonb_build_object('ships', count(*),
                 'armed_and_crewed', count(*) filter (where t.state = 'armed and crewed'), 'armed_short_handed', count(*) filter (where t.state = 'armed but short-handed'),
                 'unarmed', count(*) filter (where t.state = 'unarmed'),
                 'hands_none', count(*) filter (where t.crew = 0), 'hands_under_25', count(*) filter (where t.crew > 0 and t.hands < 0.25),
                 'hands_under_50', count(*) filter (where t.hands >= 0.25 and t.hands < 0.5), 'hands_under_100', count(*) filter (where t.hands >= 0.5 and t.hands < 1),
                 'hands_full', count(*) filter (where t.hands >= 1 and t.crew > 0),
                 'hull_under_50', count(*) filter (where t.hull < 0.5))
          from t where t.at_sea) as at_sea,
       (select jsonb_build_object('ships', count(*) filter (where t.unsafe),
                                  'under_half_hands', count(*) filter (where t.guns and t.hands < 0.5), 'of', count(*),
                                  'share', case when count(*) > 0 then round(count(*) filter (where t.unsafe)::numeric / count(*), 3) else 0 end)
          from t where t.at_sea) as unsafe,
       (select jsonb_build_object('with_funds', count(*) filter (where t.aboard > 0), 'median', percentile_disc(0.5) within group (order by t.aboard),
                                  'p90', percentile_disc(0.9) within group (order by t.aboard), 'most', max(t.aboard), 'at_400k_or_more', count(*) filter (where t.aboard >= 400000),
                                  'unsafe_with_funds', count(*) filter (where t.unsafe and t.aboard > 0), 'unsafe_funds', coalesce(sum(t.aboard) filter (where t.unsafe), 0))
          from t where t.at_sea) as aboard,
       (select coalesce(jsonb_agg(jsonb_build_object('nation', w.nation, 'name', w.name, 'class', w.class, 'state', w.state, 'hands', w.crew || '/' || w.crew_required,
                                                     'hull_pct', round(w.hull * 100), 'status', w.status, 'aboard', w.aboard)
                                  order by w.guns, w.hands, w.hull, w.nation, w.name), '[]'::jsonb)
          from (select * from t where t.at_sea order by t.guns, t.hands, t.hull, t.nation, t.name limit 25) w) as worst,
       (select max(version) from supabase_migrations.schema_migrations) as head;
commit;
