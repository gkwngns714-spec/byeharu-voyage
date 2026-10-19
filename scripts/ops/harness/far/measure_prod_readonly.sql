begin transaction read only;
-- BASELINE: long vs short profit per day for a competent trader (450 t, 20 crew, 4.97 kn), read-only, stable fns only.
with par as (select 450::numeric as hold_t, 20 as crew, 4.97::numeric as kn, 1.0::numeric as turn_days,
                    (select (value#>>'{}')::numeric from public.world_config where key='wage_per_crew_day')
                    + (select (value#>>'{}')::numeric from public.world_config where key='food_per_crew_day') * (select (value#>>'{}')::numeric from public.world_config where key='provision_food_price')
                    + (select (value#>>'{}')::numeric from public.world_config where key='water_per_crew_day') * (select (value#>>'{}')::numeric from public.world_config where key='provision_water_price') as cost_crew_day,
                    (select (value#>>'{}')::numeric from public.world_config where key='daily_cap_fraction') as capf),
origins as (select p.id, p.code from public.ports p where p.kind='HARBOUR' order by md5(p.code || 'far0213') limit 12),
offered as (select o.id as origin, o.code ocode, pg.good_id, g.code gcode, g.bulk, pg.stock, pg.stock_target,
                   world.mid_price(o.id, pg.good_id, pg.stock) mid_here
              from origins o cross join lateral public.port_offered_goods(o.id) og
              join public.port_goods pg on pg.port_id=o.id and pg.good_id=og.good_id
              join public.goods g on g.id=pg.good_id
              join public.ports op on op.id=o.id
             where not public.culture_refuses(op.culture, g.culture_mask)),
reach as (select o.id origin, r.port_id, r.nm,
                 case when r.nm < 1000 then 1 when r.nm < 2500 then 2 when r.nm < 5000 then 3 when r.nm < 8000 then 4 else 5 end as band
            from origins o cross join lateral voyage.reach_from(o.id) r join public.ports d on d.id=r.port_id and d.kind='HARBOUR'
           where r.nm > 0),
mids as (select f.origin, f.ocode, f.good_id, f.gcode, f.bulk, f.stock, f.stock_target, f.mid_here, rc.port_id, rc.nm, rc.band,
                world.mid_price(rc.port_id, f.good_id, pg.stock) mid_there
           from offered f join reach rc on rc.origin=f.origin
           join public.port_goods pg on pg.port_id=rc.port_id and pg.good_id=f.good_id
           join public.ports d on d.id=rc.port_id
           join public.goods g on g.id=f.good_id
          where not public.culture_refuses(d.culture, g.culture_mask)),
-- shortlist: per (origin, band) the 6 best (good, dest) by mid gap per day (mid ratio is a proxy)
short as (select * from (select m.*, row_number() over (partition by m.origin, m.band
                     order by ((m.mid_there - m.mid_here) * floor((select hold_t from par)/m.bulk)) / (m.nm / (select kn from par) / 24 + (select turn_days from par)) desc) rn
                from mids m where m.mid_there > m.mid_here) z where rn <= 6),
sized as (select s.*, floor(least((select hold_t from par)/s.bulk, s.stock, (select capf from par)*s.stock_target)) units from short s),
bought as (select z.*, qb.units bu, qb.total outlay from sized z cross join lateral world.quote(z.origin, z.good_id, z.units, 'buy', null, null) qb where z.units >= 1),
sold as (select b.*, qs.units su, qs.total proceeds from bought b cross join lateral world.quote(b.port_id, b.good_id, b.bu, 'sell', null, null) qs where b.bu > 0),
net as (select s.*, s.nm / (select kn from par) / 24 as sea_days,
               s.proceeds - s.outlay - public.profit_tax(s.port_id, s.proceeds - s.outlay, null) as after_tax
          from sold s),
perday as (select n.*, (n.after_tax - (select crew from par) * (select cost_crew_day from par) * n.sea_days) / (n.sea_days + (select turn_days from par)) as pday from net n),
best as (select distinct on (origin, band) origin, ocode, band, gcode, nm, bu, outlay, proceeds, round(after_tax) after_tax, round(sea_days,1) sea_days, round(pday,1) pday
           from perday order by origin, band, pday desc)
select jsonb_agg(to_jsonb(b) order by b.ocode, b.band) from best b;
