-- gear_wear_bite PROD CHECK (READ BEFORE LIGHTING), read-only, ONE statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/gear-wear/before-light.sql
-- Run volatility.sql first. What lighting gear wear would do on prod the minute it is lit. Wear has ACCRUED on companies' fittings since 0158 landed (dark):
-- lighting makes every worn piece work at 1 - wear / 200 at once and puts a fittings line on the yard's bill.
-- WANTED before lighting:
--   switch            false (true: it is lit already, the lighting file refuses)
--   knobs             gear_wear_per_1000nm 1, gear_wear_per_fight 4, gear_wear_per_storm 3, gear_repair_pct 0.3, running_cost_level 0.2: the values the measurement was taken at
--                     (docs/dev-log/2026-11-13-gear-wear-lit.md). Any other value: measure again before lighting; the lighting file refuses.
--   writer            calls 1 and players_only true: public.wear_units_for is called once from voyage.settle, after the one merchant test (a merchant's fitting never wears)
--   merchants         worn 0 (anything else: a path wears a merchant's fitting; DO NOT LIGHT, read it first)
--   companies         nothing asserted; READ IT: `worn` and `most_worn` say how much lighting moves at once (`weakest_works_pct` is the largest fall of a piece's buys),
--                     `bill_all` is what every company together would pay to mend everything today, `largest_bill` the dearest single company, and
--                     `bills_over_purse` companies that could not pay theirs (wanted 0; a company that cannot pay keeps sailing, her pieces at their factor)
--   week              the last 7 days of companies' arrived voyages: miles, STORM days, PIRATES days. With the knobs this is the wear a week brings, in points summed
--                     over fleets: `week_points_miles` for each piece that answers to miles, `week_points_storm` and `week_points_pirates` likewise
begin transaction read only;
select jsonb_build_object(
  'head', (select max(version) from supabase_migrations.schema_migrations),
  'switch', (select c.value from public.world_config c where c.key = 'gear_wear_bite'),
  'switch_reads', public.gear_wear_on(),
  'knobs', (select jsonb_object_agg(c.key, c.value) from public.world_config c
             where c.key in ('gear_wear_per_1000nm', 'gear_wear_per_fight', 'gear_wear_per_storm', 'gear_repair_pct', 'running_cost_level', 'goods_price_level')),
  'writer', (select jsonb_build_object(
               'calls', (length(d.def) - length(replace(d.def, 'public.wear_units_for(', ''))) / length('public.wear_units_for('),
               'players_only', strpos(d.def, 'if not (select p.is_npc from public.players p where p.id = f.player_id) then') > 0
                               and strpos(d.def, 'if not (select p.is_npc from public.players p where p.id = f.player_id) then') < strpos(d.def, 'perform public.wear_units_for(p_fleet, v.id);'))
               from (select replace(pg_get_functiondef(to_regprocedure('voyage.settle(uuid,timestamp with time zone)')), E'\r', '') as def) d),
  'merchants', (select jsonb_build_object('fittings', count(*), 'worn', count(*) filter (where u.wear > 0))
                  from public.fitted_units u join public.ships s on s.id = u.ship_id join public.players p on p.id = s.player_id and p.is_npc),
  'companies', (select jsonb_build_object(
                  'fittings', count(*),
                  'that_wear', count(*) filter (where iu.trigger is not null),
                  'worn', count(*) filter (where u.wear > 0),
                  'most_worn', coalesce(max(u.wear), 0),
                  'mean_wear_of_worn', coalesce(round(avg(u.wear) filter (where u.wear > 0), 2), 0),
                  'weakest_works_pct', round(public.wear_factor(coalesce(max(u.wear), 0)) * 100, 1),
                  'worn_by_kind', (select coalesce(jsonb_object_agg(q.trig, q.n), '{}'::jsonb)
                                     from (select coalesce(iu2.trigger, 'never') as trig, count(*) as n
                                             from public.fitted_units u2 join public.ships s2 on s2.id = u2.ship_id join public.players p2 on p2.id = s2.player_id and not p2.is_npc
                                             left join public.item_use iu2 on iu2.item_code = u2.item_code
                                            where u2.wear > 0 group by 1) q),
                  'bill_all', coalesce(sum(public.unit_repair_cost(u.item_code, u.wear)) filter (where u.wear > 0), 0))
                  from public.fitted_units u join public.ships s on s.id = u.ship_id join public.players p on p.id = s.player_id and not p.is_npc
                  left join public.item_use iu on iu.item_code = u.item_code),
  'bills', (select jsonb_build_object('companies_with_a_bill', count(*), 'largest_bill', coalesce(max(b.bill), 0), 'bills_over_purse', count(*) filter (where b.bill > b.ducats))
              from (select p.id, p.ducats, sum(public.unit_repair_cost(u.item_code, u.wear)) as bill
                      from public.fitted_units u join public.ships s on s.id = u.ship_id join public.players p on p.id = s.player_id and not p.is_npc
                     where u.wear > 0 group by p.id, p.ducats) b),
  'week', (select jsonb_build_object(
             'voyages', count(*), 'fleets', count(distinct v.fleet_id), 'nm', coalesce(round(sum(v.total_nm)), 0),
             'storm_days', coalesce(sum((select count(*) from public.voyage_events ve where ve.voyage_id = v.id and ve.kind = 'STORM')), 0),
             'pirates_days', coalesce(sum((select count(*) from public.voyage_events ve where ve.voyage_id = v.id and ve.kind = 'PIRATES')), 0),
             'week_points_miles', coalesce(round(sum(v.total_nm) / 1000 * public.wc_num('gear_wear_per_1000nm'), 2), 0),
             'week_points_storm', coalesce(sum((select count(*) from public.voyage_events ve where ve.voyage_id = v.id and ve.kind = 'STORM')), 0) * public.wc_num('gear_wear_per_storm'),
             'week_points_pirates', coalesce(sum((select count(*) from public.voyage_events ve where ve.voyage_id = v.id and ve.kind = 'PIRATES')), 0) * public.wc_num('gear_wear_per_fight'))
             from public.voyages v join public.players p on p.id = v.player_id and not p.is_npc
            where v.status = 'ARRIVED' and v.eta > now() - interval '7 days')
) as before_light;
commit;
