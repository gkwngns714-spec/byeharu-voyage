-- 0517: WHAT THE LEAD READS ON PROD BEFORE LIGHTING (after the deploy, dark). One read-only statement over 67 cities; the owner sees it.
--   npx --yes supabase@2.120.0 db query --linked --output-format json -f scripts/ops/harness/premium-goods/purses.sql
-- cities: each premium city's spare coin (purse less the greater of its reserve and its floor), the units its share lets it pay now, and the
--   most a day of 30 units costs it. Ask the owner before lighting if: `none` (cities that could pay nothing) is over 17, `over_third`
--   (a full day is over a third of the spare coin) is over 7, or `full_day` is over 2 % of `all_purses`.
begin transaction read only;
with c as (
  select g.code as good, h.code as city, public.treasury_balance(h.id) as purse,
         public.treasury_balance(h.id) - greatest(coalesce(t.reserve, 0), public.city_floor(h.id)) as spare,
         world.mid_price(h.id, g.id, pg.stock) * public.wc_num('premium_price_lift') * public.premium_mult(pg.haul_nm) as unit
    from public.goods g join public.ports h on h.id = g.premium_port_id
    join public.port_goods pg on pg.port_id = h.id and pg.good_id = g.id
    left join public.port_treasury t on t.port_id = h.id)
select json_build_object(
  'all_purses', (select sum(t.ducats) from public.port_treasury t),
  'full_day', (select round(sum(c.unit * public.wc_num('premium_day_units'))) from c),
  'none', (select count(*) from c where c.spare * public.wc_num('premium_purse_share') < c.unit),
  'over_third', (select count(*) from c where c.unit * public.wc_num('premium_day_units') * 3 > greatest(c.spare, 0)),
  'cities', (select json_agg(json_build_array(c.city, c.good, c.purse, c.spare, round(c.unit), least(30, floor(greatest(0, c.spare) * public.wc_num('premium_purse_share') / c.unit)),
                                              round(c.unit * public.wc_num('premium_day_units'))) order by c.spare) from c));
rollback;
