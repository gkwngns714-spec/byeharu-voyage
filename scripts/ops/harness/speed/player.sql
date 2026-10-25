-- player.sql — a PLAYER's day at the game's own speed authority (2026-10-25, the 0219 pair).
-- The stand-in for a starter is a one-hull barca fleet of this world (the first by md5(id || '0219'):
-- the same hull in both arms), read through the authorities a player's screens read: voyage.fleet_speed
-- (empty, what the fleet card prints), voyage.fleet_speed_at(fleet, 1) (laden, what she sails out at),
-- voyage.endurance_days, voyage.reach_from (the miles). From Lisbon, the founding port: the nearest harbour,
-- the one nearest 2,500 nm and the farthest — days quoted (miles ÷ (speed × 24), 0188's arithmetic) and the
-- real hours that is at game_day_seconds. Then haul/bands.sql's metric — a competent trader's best profit
-- per game day by route band (buy a full hold at a maker, sell it all at one harbour, less tax and the
-- running costs per sea-day) — at THIS hull's speed, hold and crew, from 24 origins by md5(code||'far0213'),
-- turned into ducats per REAL hour and laps per real day. READ-ONLY: every function it calls is stable.
with par0 as (
  select f.id as fleet, c.code, voyage.fleet_speed(f.id) as kn_empty, voyage.fleet_speed_at(f.id, 1) as kn,
         public.fleet_free_hold(f.id) as hold_t, (select sum(s2.crew) from public.ships s2 where s2.fleet_id = f.id)::int as crew,
         voyage.endurance_days(f.id) as endurance_days
    from public.fleets f join public.ships s on s.fleet_id = f.id join public.ship_classes c on c.id = s.class_id
   where c.code = 'barca' and (select count(*) from public.ships s3 where s3.fleet_id = f.id) = 1
   order by md5(f.id::text || '0219') limit 1),
par as (select p.*, 1.0::numeric as turn_days, public.wc_num('game_day_seconds') as gds,
               (public.wc_num('wage_per_crew_day') + public.wc_num('food_per_crew_day') * public.wc_num('provision_food_price')
                + public.wc_num('water_per_crew_day') * public.wc_num('provision_water_price')) * public.wc_num('running_cost_level') as cost_crew_day,
               public.wc_num('daily_cap_fraction') as capf
          from par0 p),
lis as (select id, code from public.ports where kind = 'HARBOUR' and name ilike 'lisbo%' order by code limit 1),
legs as (select d.code as dest, r.nm, round(r.nm / ((select kn from par) * 24), 2) as days,
                round(r.nm / ((select kn from par) * 24) * (select gds from par) / 3600, 2) as real_hours, k.which
           from lis cross join lateral voyage.reach_from(lis.id) r join public.ports d on d.id = r.port_id and d.kind = 'HARBOUR'
           cross join lateral (select case when r.nm = (select min(r2.nm) from voyage.reach_from(lis.id) r2 join public.ports d2 on d2.id = r2.port_id and d2.kind = 'HARBOUR' where r2.nm > 0) then 'nearest'
                                           when r.nm = (select max(r2.nm) from voyage.reach_from(lis.id) r2 join public.ports d2 on d2.id = r2.port_id and d2.kind = 'HARBOUR') then 'farthest' end) k(which)
          where r.nm > 0 and k.which is not null),
mid_leg as (select d.code as dest, r.nm, round(r.nm / ((select kn from par) * 24), 2) as days,
                   round(r.nm / ((select kn from par) * 24) * (select gds from par) / 3600, 2) as real_hours, 'nearest 2,500 nm' as which
              from lis cross join lateral voyage.reach_from(lis.id) r join public.ports d on d.id = r.port_id and d.kind = 'HARBOUR'
             where r.nm > 0 order by abs(r.nm - 2500) limit 1),
origins as (select p.id, p.code from public.ports p where p.kind = 'HARBOUR' order by md5(p.code || 'far0213') limit 24),
offered as (select o.id as origin, o.code ocode, pg.good_id, g.code gcode, g.bulk, pg.stock, pg.stock_target,
                   world.mid_price(o.id, pg.good_id, pg.stock) mid_here
              from origins o cross join lateral public.port_offered_goods(o.id) og
              join public.port_goods pg on pg.port_id = o.id and pg.good_id = og.good_id
              join public.goods g on g.id = pg.good_id
              join public.ports op on op.id = o.id
             where not public.culture_refuses(op.culture, g.culture_mask)),
reach as (select o.id origin, r.port_id, r.nm,
                 case when r.nm < 1000 then 1 when r.nm < 2500 then 2 when r.nm < 5000 then 3 when r.nm < 10000 then 4 else 5 end as band
            from origins o cross join lateral voyage.reach_from(o.id) r join public.ports d on d.id = r.port_id and d.kind = 'HARBOUR'
           where r.nm > 0),
mids as (select f.*, rc.port_id, rc.nm, rc.band, pg.haul, world.mid_price(rc.port_id, f.good_id, pg.stock) mid_there
           from offered f join reach rc on rc.origin = f.origin
           join public.port_goods pg on pg.port_id = rc.port_id and pg.good_id = f.good_id
           join public.ports d on d.id = rc.port_id
           join public.goods g on g.id = f.good_id
          where not public.culture_refuses(d.culture, g.culture_mask)),
short as (select * from (select m.*, row_number() over (partition by m.origin, m.band
                     order by ((m.mid_there - m.mid_here) * floor((select hold_t from par) / m.bulk)) / (m.nm / (select kn from par) / 24 + (select turn_days from par)) desc) rn
                from mids m where m.mid_there > m.mid_here) z where rn <= 12),
sized as (select s.*, floor(least((select hold_t from par) / s.bulk, s.stock, (select capf from par) * s.stock_target)) units from short s),
bought as (select z.*, qb.units bu, qb.total outlay from sized z cross join lateral world.quote(z.origin, z.good_id, z.units, 'buy', null, null) qb where z.units >= 1),
sold as (select b.*, qs.units su, qs.total proceeds from bought b cross join lateral world.quote(b.port_id, b.good_id, b.bu, 'sell', null, null) qs where b.bu > 0),
net as (select s.*, s.nm / (select kn from par) / 24 as sea_days,
               s.proceeds - s.outlay - public.profit_tax(s.port_id, s.proceeds - s.outlay, null) as after_tax
          from sold s),
perday as (select n.*, (n.after_tax - (select crew from par) * (select cost_crew_day from par) * n.sea_days) / (n.sea_days + (select turn_days from par)) as pday,
                  n.after_tax - (select crew from par) * (select cost_crew_day from par) * n.sea_days as lap_net
             from net n),
best as (select distinct on (origin, band) origin, ocode, band, gcode, nm, bu, outlay, proceeds, after_tax, sea_days, lap_net, pday
           from perday order by origin, band, pday desc),
bands as (select b.band, count(*) as origins, round(percentile_cont(0.5) within group (order by b.pday)::numeric, 1) as median_pday,
                 round(percentile_cont(0.5) within group (order by b.lap_net)::numeric) as median_lap_net,
                 round(percentile_cont(0.5) within group (order by b.sea_days)::numeric, 2) as median_sea_days,
                 round((percentile_cont(0.5) within group (order by b.pday) * 3600 / (select gds from par))::numeric, 1) as median_ducats_per_real_hour,
                 round((86400 / ((percentile_cont(0.5) within group (order by b.sea_days + (select turn_days from par))) * (select gds from par)))::numeric, 2) as laps_per_real_day
            from best b group by b.band)
select jsonb_build_object(
  'hull', (select to_jsonb(p) - 'fleet' from par p),
  'from', (select code from lis),
  'legs', (select jsonb_agg(to_jsonb(l) order by l.nm) from (select * from legs union all select * from mid_leg) l),
  'bands', (select jsonb_agg(to_jsonb(b) order by b.band) from bands b)) as x;
