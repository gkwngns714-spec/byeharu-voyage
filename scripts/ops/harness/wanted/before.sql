-- 0334 PROD CHECK, read-only, one statement: npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/wanted/before.sql
-- Every function read here is STABLE (pg_get_functiondef, to_regclass, replace) or a count. No game function is called.
-- Wanted: every `times` 1; keys 0; kind_navy 0; wanted_table null; side_table null; fine_side 'moved'; capitals_short 0; head the number before 0334. Re-run at the head before 0334: 0332 and 0333 land first, and W13 may cut these lines.
begin transaction read only;
with h(fn, ord, old) as (values
  ('voyage.depart(uuid,jsonb,uuid,uuid,timestamp with time zone)'::regprocedure, 1, $h$  e         jsonb;
begin
  select player_id into v_player from public.fleets where id = p_fleet;
$h$),
  ('voyage.depart(uuid,jsonb,uuid,uuid,timestamp with time zone)'::regprocedure, 2, $h$  returning id into v_voyage;
$h$),
  ('voyage.hazard_roll(uuid,integer)'::regprocedure, 1, $h$  if not occurred then
    kind := null;
$h$),
  ('voyage.settle(uuid,timestamp with time zone)'::regprocedure, 1, $h$    elsif h.occurred and h.kind = 'FAIR_WIND' then
$h$),
  ('public.attack_close(uuid,jsonb,timestamp with time zone)'::regprocedure, 1, $h$  return jsonb_build_object('loot', v_gold, 'crew_lost', v_lost);
$h$),
  ('public.fine_for(uuid,uuid,bigint)'::regprocedure, 1, $h$  v_score := public.regard_add(p_player, v_nat, v_pay::numeric / v_per, 'FINE');
$h$),
  ('public.regard_line(uuid,uuid)'::regprocedure, 1, $h$    'fine', case when public.city_capital(p_port) = p_port then public.fine_owed(p_player, v_nation) else 0 end));
$h$)
)
select jsonb_build_object(
  'hunks', (select jsonb_agg(jsonb_build_object('fn', h.fn::text, 'ord', h.ord,
                     'times', (length(d.def) - length(replace(d.def, h.old, ''))) / length(h.old)) order by h.fn::text, h.ord)
              from h cross join lateral (select replace(pg_get_functiondef(h.fn), E'\r', '') as def) d),
  'keys', (select count(*) from public.world_config c where c.key in ('wanted_hours', 'navy_hunt_per_day', 'navy_hunt_wanted_mult', 'navy_fine_share', 'navy_fine_cap', 'navy_hull_floor', 'navy_crew_lost')),
  'kind_navy', (select count(*) from public.voyage_event_kinds k where k.code = 'NAVY'),
  'wanted_table', to_regclass('public.wanted'),
  'side_table', to_regclass('public.voyage_hostile'),
  'fine_side', (select w.side from public.stats_flow_words w where w.kind = 'FINE'),
  'capitals_short', (select count(*) from public.great_powers g
                       join public.nations n on n.id = g.nation_id join public.ports p on p.code = n.capital_port_code and p.kind = 'HARBOUR'
                      cross join public.goods x
                      where not exists (select 1 from public.port_goods pg where pg.port_id = p.id and pg.good_id = x.id)),
  'head', (select max(version) from supabase_migrations.schema_migrations)
) as checks;
commit;
