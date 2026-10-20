-- bands.sql — a competent trader's best profit PER GAME DAY from each origin, by route-length band.
-- The metric of docs/dev-log/2026-10-19-far-selling.md (osn-far-selling), with the bands the 2026-10-20
-- plan asks for: <1k, 1–2.5k, 2.5–5k, 5–10k, 10k+ nm. She has 450 t of hold, 20 crew, 4.97 knots, capital
-- not binding; buys a full hold at a maker (capped by the stock and the daily cap) and sells it all at one
-- destination. Profit = proceeds − outlay − profit tax − running costs (wages + food + water a crew a sea-day,
-- at running_cost_level) × sea-days; per day = profit / (sea-days + 1 turnaround day). Per origin and band,
-- the best (good, destination) of a 12-long shortlist by mid gap; origins = 24 harbours by md5(code||'far0213')
-- (the far-selling baseline's own set, so the figures compare). READ-ONLY: world.mid_price / world.quote /
-- public.profit_tax are stable.
with par as (select 450::numeric as hold_t, 20 as crew, 4.97::numeric as kn, 1.0::numeric as turn_days,
                    (public.wc_num('wage_per_crew_day') + public.wc_num('food_per_crew_day') * public.wc_num('provision_food_price')
                     + public.wc_num('water_per_crew_day') * public.wc_num('provision_water_price')) * public.wc_num('running_cost_level') as cost_crew_day,
                    public.wc_num('daily_cap_fraction') as capf),
origins as (select p.id, p.code from public.ports p where p.kind='HARBOUR' order by md5(p.code || 'far0213') limit 24),
offered as (select o.id as origin, o.code ocode, pg.good_id, g.code gcode, g.bulk, pg.stock, pg.stock_target,
                   world.mid_price(o.id, pg.good_id, pg.stock) mid_here
              from origins o cross join lateral public.port_offered_goods(o.id) og
              join public.port_goods pg on pg.port_id=o.id and pg.good_id=og.good_id
              join public.goods g on g.id=pg.good_id
              join public.ports op on op.id=o.id
             where not public.culture_refuses(op.culture, g.culture_mask)),
reach as (select o.id origin, r.port_id, r.nm,
                 case when r.nm < 1000 then 1 when r.nm < 2500 then 2 when r.nm < 5000 then 3 when r.nm < 10000 then 4 else 5 end as band
            from origins o cross join lateral voyage.reach_from(o.id) r join public.ports d on d.id=r.port_id and d.kind='HARBOUR'
           where r.nm > 0),
mids as (select f.*, rc.port_id, rc.nm, rc.band, pg.haul, world.mid_price(rc.port_id, f.good_id, pg.stock) mid_there
           from offered f join reach rc on rc.origin=f.origin
           join public.port_goods pg on pg.port_id=rc.port_id and pg.good_id=f.good_id
           join public.ports d on d.id=rc.port_id
           join public.goods g on g.id=f.good_id
          where not public.culture_refuses(d.culture, g.culture_mask)),
short as (select * from (select m.*, row_number() over (partition by m.origin, m.band
                     order by ((m.mid_there - m.mid_here) * floor((select hold_t from par)/m.bulk)) / (m.nm / (select kn from par) / 24 + (select turn_days from par)) desc) rn
                from mids m where m.mid_there > m.mid_here) z where rn <= 12),
sized as (select s.*, floor(least((select hold_t from par)/s.bulk, s.stock, (select capf from par)*s.stock_target)) units from short s),
bought as (select z.*, qb.units bu, qb.total outlay from sized z cross join lateral world.quote(z.origin, z.good_id, z.units, 'buy', null, null) qb where z.units >= 1),
sold as (select b.*, qs.units su, qs.total proceeds from bought b cross join lateral world.quote(b.port_id, b.good_id, b.bu, 'sell', null, null) qs where b.bu > 0),
net as (select s.*, s.nm / (select kn from par) / 24 as sea_days,
               s.proceeds - s.outlay - public.profit_tax(s.port_id, s.proceeds - s.outlay, null) as after_tax
          from sold s),
perday as (select n.*, (n.after_tax - (select crew from par) * (select cost_crew_day from par) * n.sea_days) / (n.sea_days + (select turn_days from par)) as pday from net n),
best as (select distinct on (origin, band) origin, ocode, band, gcode, nm, haul, bu, su, outlay, proceeds, round(after_tax) after_tax, round(sea_days,1) sea_days, round(pday,1) pday
           from perday order by origin, band, pday desc)
select jsonb_agg(to_jsonb(b) order by b.ocode, b.band) as x from best b;
