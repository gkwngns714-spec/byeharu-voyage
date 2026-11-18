-- @pass MEASURE_DONE   scratch
do $p$
declare r record; v text := '';
begin
  -- (1) L1's reproduction: Lisbon, each job at its level, no tool, 6 packs, home jobs, party-hour over 1 % of Lisbon's target
  for r in
    select a.code, a.level, pg.stock_target, round(a.seconds*(1-0.002*(a.level-1)))::int as aa,
           round(3600.0*6/(30+6*round(a.seconds*(1-0.002*(a.level-1)))) / (0.01*pg.stock_target),1) as x
      from public.land_actions a join public.port_goods pg on pg.good_id = a.good_id
      join public.ports p on p.id = pg.port_id and p.code = 'LIS'
     where public.land_passage(p.id, a.good_id) ->> 'home' = 'true'
     order by x desc
  loop v := v || format('%s %s(t%s) ', r.code, r.x, round(r.stock_target)); end loop;
  raise notice 'TIMING: LISBON home jobs, party-hour / hundredth of Lisbon target: %', v;
  v := '';
  -- (2) per good x origin region: how many harbours of the region stock it; median target
  for r in
    select a.code, rg.code as reg, count(pg.*) as n, round(percentile_disc(0.5) within group (order by pg.stock_target)) as med,
           round(3600.0/a.seconds/(0.01*nullif(percentile_disc(0.5) within group (order by pg.stock_target),0)),1) as x
      from public.land_actions a join public.goods g on g.id = a.good_id
      cross join unnest(g.origin_regions) o(rc) join public.regions rg on rg.code = o.rc
      left join public.ports p on p.region_id = rg.id and p.kind = 'HARBOUR'
      left join public.port_goods pg on pg.port_id = p.id and pg.good_id = a.good_id
     group by a.code, a.seconds, rg.code order by x desc nulls first
  loop v := v || format('%s@%s n%s med%s %sx; ', r.code, r.reg, r.n, r.med, r.x); end loop;
  raise notice 'TIMING: PER REGION: %', v;
  raise notice 'PASS: MEASURE_DONE';
end $p$;
