-- measure-scene.sql — WHAT GEAR WEAR COSTS A COMPANY, LIT: a LOCAL SCENE (it writes; run.mjs rolls it back).
--   BYEHARU_PREFIX_CACHE=required node scripts/ops/harness/gear-wear/run.mjs --fixtures scripts/ops/harness/gear-wear/measure-scene.sql
-- Probe companies sail real round trips out of Lisbon through the game's own doors (cmd.issue BUY / SELL / REPAIR, a SAIL with the proofs' course,
-- voyage.settle at each arrival's own instant) with the switches prod has lit and gear_wear_bite true. Printed per company: voyages, miles, sea days,
-- PIRATES and STORM days met, what the yard charged for fittings and for the hull, the trading result (sales less buys), per sea day.
-- Kinds: BARCA a founding barca, nothing fitted; BARCA+ the same hull with every place a new company may fill; TRADER an armed trader (carlat), every
-- place filled with what a new company may fit, repaired each lap; TRADER-NEVER the same, never repaired (how far wear runs, what it does to her
-- figures); BIG two hulls (nau, galion: a fleet sails two today) with the DEAREST piece in every place (the dearest that mount: the ceiling of a rich company's bill; BIG-NEVER the same, never repaired; skills_bite is put out
-- while she is fitted and lit again before she sails).
-- THE SEA IS NOT ASKED TO BEHAVE: each world rolls its own days, so the figures move from world to world; nothing here asserts an outcome.
-- Two clocks are skipped, and said so: her port time (fleets.ready_at) and the yard's hours (REPAIRING back to DOCKED). The money is the game's own.
-- LOCAL PGlite WORLD ONLY (scripts/ops/harness/README.md): it writes. The first statement refuses a real server.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;

-- every place of p_ship filled through public.mount_fitting (the core of FIT): cheapest first, or dearest first
create or replace function pg_temp.gw_fit(p_ship uuid, p_dear boolean) returns int language plpgsql as $$
declare r record; v_n int := 0; v_try int;
begin
  -- the three kinds of wear in turn (MILES, PIRATES, STORM), so a loadout is not all of one kind
  for r in select z.code from (
             select k.code, public.item_recipe_value(k.code) as val,
                    row_number() over (partition by iu.trigger order by case when p_dear then -public.item_recipe_value(k.code) else public.item_recipe_value(k.code) end, k.code) as rn
               from public.item_kinds k join public.item_profile ip on ip.item_code = k.code join public.item_use iu on iu.item_code = k.code
              where ip.rack <> 'refit' and iu.trigger is not null) z
            order by z.rn, z.code loop
    for v_try in 1 .. 3 loop
      begin
        perform public.mount_fitting(p_ship, r.code);
        v_n := v_n + 1;
      exception when others then exit;
      end;
    end loop;
  end loop;
  return v_n;
end $$;

-- one leg: buy the good that pays best at p_dest, sail there, sell. Returns false when she did not make it.
create or replace function pg_temp.gw_leg(p_fleet uuid, p_dest text) returns boolean language plpgsql as $$
declare
  v_here uuid; v_to uuid; v_pl uuid; v_purse bigint; v_room numeric; v_pick record; v_r jsonb; v_voy record; v_n int; g record;
begin
  select f.port_id, f.player_id into v_here, v_pl from public.fleets f where f.id = p_fleet;
  select id into v_to from public.ports where code = p_dest;
  select ducats into v_purse from public.players where id = v_pl;
  select coalesce(sum(public.ship_hold_capacity(s.id) * (1 - s.store_ratio) - public.ship_cargo_tuns(s.id)), 0) into v_room from public.ships s where s.fleet_id = p_fleet;
  select z.code, z.u, z.gain into v_pick from (
    select g2.code, x.u, (select qs.total from world.quote(v_to, g2.id, x.u, 'sell', null, null) qs) - (select qb.total from world.quote(v_here, g2.id, x.u, 'buy', null, null) qb) as gain
      from public.port_offered_goods(v_here) og
      join public.port_goods pg on pg.port_id = v_here and pg.good_id = og.good_id
      join public.goods g2 on g2.id = pg.good_id
      join public.port_goods dg on dg.port_id = v_to and dg.good_id = g2.id
      cross join lateral (select floor(least(v_room * 0.85 / g2.bulk, pg.stock, public.wc_num('daily_cap_fraction') * pg.stock_target,
                                             v_purse * 0.6 / greatest(world.mid_price(v_here, g2.id, pg.stock), 1))) as u) x
     where x.u >= 1) z
   where z.gain > 0 order by z.gain desc limit 1;
  if v_pick.code is not null then
    v_r := cmd.issue(p_fleet, format('BUY %s %s', v_pick.code, v_pick.u::int));
    if v_r -> 'order' ->> 'status' = 'failed' then raise notice '  (BUY % refused: %)', v_pick.code, v_r -> 'order' ->> 'error_message'; end if;
  end if;
  v_r := proof.sail(p_fleet, p_dest);
  if (select f.status from public.fleets f where f.id = p_fleet) <> 'SAILING' and v_r -> 'fixes' ->> 0 is not null then
    perform cmd.issue(p_fleet, v_r -> 'fixes' ->> 0);   -- the game's own fix for the refusal (her casks), then once more
    v_r := proof.sail(p_fleet, p_dest);
  end if;
  if (select f.status from public.fleets f where f.id = p_fleet) <> 'SAILING' then
    raise notice '  (no departure for %: %)', p_dest, left(v_r::text, 300);
    return false;
  end if;
  for v_n in 1 .. 60 loop
    exit when (select f.status from public.fleets f where f.id = p_fleet) <> 'SAILING';
    select v.id, v.eta into v_voy from public.voyages v where v.fleet_id = p_fleet and v.status = 'SAILING' limit 1;
    perform voyage.settle(p_fleet, v_voy.eta);
  end loop;
  update public.fleets set ready_at = null where id = p_fleet;   -- the port time is skipped (a clock, not money)
  if (select f.status from public.fleets f where f.id = p_fleet) <> 'DOCKED' or (select f.port_id from public.fleets f where f.id = p_fleet) is distinct from v_to then
    raise notice '  (she did not make %: she is % at %)', p_dest, (select f.status from public.fleets f where f.id = p_fleet),
      (select p.code from public.fleets f left join public.ports p on p.id = f.port_id where f.id = p_fleet);
    return false;
  end if;
  for g in select distinct k as code from public.ships s, jsonb_object_keys(s.cargo) k where s.fleet_id = p_fleet loop
    v_r := cmd.issue(p_fleet, format('SELL %s ALL', g.code));
    if v_r -> 'order' ->> 'status' = 'failed' then raise notice '  (SELL % at % refused: %)', g.code, p_dest, v_r -> 'order' ->> 'error_message'; end if;
  end loop;
  return true;
end $$;

create or replace function pg_temp.gw_company(p_kind text, p_classes text[], p_fit text, p_repair boolean, p_purse bigint, p_laps int) returns void language plpgsql as $$
declare
  v_auth uuid := gen_random_uuid(); v_pl uuid; v_fl uuid; v_lis uuid; v_sh uuid; c text; v_units int := 0; v_dest text[]; v_i int; v_ok boolean := true;
  v_p0 bigint; v_p1 bigint; v_t0 timestamptz := clock_timestamp(); v_r jsonb; v_due record; v_laps int := 0;
  v_stats0 jsonb; v_stats1 jsonb; m record; v_gear bigint := 0; v_hull bigint := 0; v_free int := 0; v_rep int := 0; v_trade numeric;
begin
  v_lis := (select h.id from public.ports h where h.code = 'LIS' and h.kind = 'HARBOUR');
  insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
  values (v_auth, 'Desgaste ' || p_kind, (select n.id from public.nations n where n.code = 'PRT'), p_purse, false) returning id into v_pl;
  v_fl := public.form_fleet(v_pl, 'Desgaste', v_lis);
  if p_fit = 'dear' then update public.world_config set value = 'false'::jsonb where key in ('skills_bite', 'levels_bite'); end if;
  foreach c in array p_classes loop
    if exists (select 1 from public.ships s where s.fleet_id = v_fl) then
      perform public.commission_ship(v_pl, v_fl, c, 'Desgaste ' || c || ' ' || (select count(*) from public.ships s where s.fleet_id = v_fl), false, false);
    else
      perform public.commission_ship(v_pl, v_fl, c, 'Desgaste ' || c, true, true);
    end if;
  end loop;
  update public.ships s set crew = greatest(s.crew, (select k.crew_required from public.ship_classes k where k.id = s.class_id)) where s.fleet_id = v_fl;
  for v_sh in select s.id from public.ships s where s.fleet_id = v_fl loop
    if p_fit <> 'none' then v_units := v_units + pg_temp.gw_fit(v_sh, p_fit = 'dear'); end if;
  end loop;
  if p_fit = 'dear' then update public.world_config set value = 'true'::jsonb where key in ('skills_bite', 'levels_bite'); end if;
  perform cmd.assume_identity(v_auth);
  -- three harbours out of Lisbon the proofs hold a course to: the nearest a day or more away, one about 800 nm, one about 1,600 nm
  select array_agg(x.code order by x.nm) into v_dest from (
    (select r.code, r.nm from voyage.reach_from(v_lis) r join public.ports p on p.id = r.port_id and p.kind = 'HARBOUR' where r.nm between 150 and 500 and proof.course('LIS', r.code) is not null order by r.nm limit 1)
    union all (select r.code, r.nm from voyage.reach_from(v_lis) r join public.ports p on p.id = r.port_id and p.kind = 'HARBOUR' where r.nm between 700 and 1000 and proof.course('LIS', r.code) is not null order by r.nm limit 1)
    union all (select r.code, r.nm from voyage.reach_from(v_lis) r join public.ports p on p.id = r.port_id and p.kind = 'HARBOUR' where r.nm between 1200 and 1650 and proof.course('LIS', r.code) is not null order by r.nm desc limit 1)) x;
  select jsonb_agg(world.ship_stats(s.id) order by s.created_at, s.id) into v_stats0 from public.ships s where s.fleet_id = v_fl;
  select ducats into v_p0 from public.players where id = v_pl;
  for v_i in 1 .. p_laps loop
    v_ok := pg_temp.gw_leg(v_fl, v_dest[1 + (v_i - 1) % 3]) and pg_temp.gw_leg(v_fl, 'LIS');
    exit when not v_ok;
    v_laps := v_laps + 1;
    if p_repair then
      select d.points, d.gear into v_due from public.fleet_repair_due(v_fl, 100) d;
      if v_due.points > 0 or v_due.gear is not null then
        v_r := cmd.issue(v_fl, 'REPAIR');
        update public.fleets set status = 'DOCKED', busy_until = null where id = v_fl and status = 'REPAIRING';   -- the yard's hours are skipped
      end if;
    end if;
  end loop;
  select ducats into v_p1 from public.players where id = v_pl;
  select jsonb_agg(world.ship_stats(s.id) order by s.created_at, s.id) into v_stats1 from public.ships s where s.fleet_id = v_fl;
  select count(*) as voyages, coalesce(sum(v.total_nm), 0) as nm,
         coalesce(sum(extract(epoch from v.eta - v.departed_at) * public.wc_num('time_compression') / 86400), 0) as days,
         (select count(*) from public.voyage_events ve join public.voyages v2 on v2.id = ve.voyage_id where v2.fleet_id = v_fl and ve.kind = 'PIRATES') as pirates,
         (select count(*) from public.voyage_events ve join public.voyages v2 on v2.id = ve.voyage_id where v2.fleet_id = v_fl and ve.kind = 'STORM') as storms
    into m from public.voyages v where v.fleet_id = v_fl;
  select coalesce(sum((e.payload -> 'gear' ->> 'cost')::bigint), 0), coalesce(sum((e.payload ->> 'cost')::bigint - coalesce((e.payload -> 'gear' ->> 'cost')::bigint, 0)), 0),
         count(*) filter (where e.payload ? 'gear' and (e.payload -> 'gear' ->> 'cost')::bigint = 0), count(*)
    into v_gear, v_hull, v_free, v_rep
    from public.events e where e.player_id = v_pl and e.kind = 'REPAIRING';
  select coalesce(sum(case e.kind when 'SOLD' then (e.payload ->> 'total')::numeric else -(e.payload ->> 'total')::numeric end), 0) into v_trade
    from public.events e where e.player_id = v_pl and e.kind in ('SOLD', 'BOUGHT');
  raise notice 'MEASURE % | hulls % | fitted % (% wearing) | laps % of % %| voyages % | nm % | sea days % | PIRATES days % | STORM days % | repairs % (% with fittings at 0 d.) | fittings repair % d. = % d. a sea day | hull repair % d. = % d. a sea day | trade (sold less bought) % d. = % d. a sea day | purse % -> % (% d. a sea day, all in) | fittings repair is % %% of trade | % ms',
    p_kind, array_to_string(p_classes, '+'), v_units,
    (select count(*) from public.ships s join public.fitted_units u on u.ship_id = s.id join public.item_use iu on iu.item_code = u.item_code and iu.trigger is not null where s.fleet_id = v_fl),
    v_laps, p_laps, case when v_ok then ' ' else ' (she did not finish: lost, held or refused) ' end,
    m.voyages, round(m.nm), round(m.days, 1), m.pirates, m.storms, v_rep, v_free,
    v_gear, round(v_gear / nullif(m.days, 0), 2), v_hull, round(v_hull / nullif(m.days, 0), 2),
    round(v_trade), round(v_trade / nullif(m.days, 0)),
    v_p0, v_p1, round((v_p1 - v_p0) / nullif(m.days, 0)),
    round(100.0 * v_gear / nullif(v_trade, 0), 3),
    round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  raise notice 'WEAR    % | units worn now % | wear min / mean / max % / % / % | weakest works at % %% | left unrepaired the bill is % d.',
    p_kind, (select count(*) from public.ships s join public.fitted_units u on u.ship_id = s.id where s.fleet_id = v_fl and u.wear > 0),
    (select coalesce(min(u.wear), 0) from public.ships s join public.fitted_units u on u.ship_id = s.id where s.fleet_id = v_fl and u.wear > 0),
    (select coalesce(round(avg(u.wear), 2), 0) from public.ships s join public.fitted_units u on u.ship_id = s.id where s.fleet_id = v_fl and u.wear > 0),
    (select coalesce(max(u.wear), 0) from public.ships s join public.fitted_units u on u.ship_id = s.id where s.fleet_id = v_fl),
    (select round(public.wear_factor(coalesce(max(u.wear), 0)) * 100, 1) from public.ships s join public.fitted_units u on u.ship_id = s.id where s.fleet_id = v_fl),
    coalesce((public.gear_repair_quote(v_fl) ->> 'cost')::bigint, 0);
  raise notice 'LOADOUT % | % | days met %', p_kind,
    (select string_agg(q.item_code || ' x' || q.n || ' (' || q.trig || ')', ', ' order by q.item_code) from (select u.item_code, coalesce(iu.trigger, 'never wears') as trig, count(*) as n
       from public.ships s join public.fitted_units u on u.ship_id = s.id left join public.item_use iu on iu.item_code = u.item_code where s.fleet_id = v_fl group by 1, 2) q),
    (select jsonb_object_agg(q.k, q.n) from (select ve.kind as k, count(*) as n from public.voyage_events ve join public.voyages v2 on v2.id = ve.voyage_id where v2.fleet_id = v_fl group by 1) q);
  if not p_repair then
    raise notice 'FIGURES % | first hull before: % | after: %', p_kind, v_stats0 -> 0, v_stats1 -> 0;
  end if;
end $$;

do $m$
declare k record;
begin
  -- what prod has lit (docs/WORK_QUEUE.md, the audit of 2026-11-13), and the switch under test
  update public.world_config set value = 'true'::jsonb
   where key in ('pirates_bite', 'combat_bite', 'crew_bite', 'skills_bite', 'levels_bite', 'reputation_on', 'price_impact', 'navy_enabled', 'gear_wear_bite');
  raise notice 'KNOBS wear a 1,000 nm %, a PIRATES day %, a STORM day %; repair % of the recipe at 100 worn, times running_cost_level %',
    public.wc_num('gear_wear_per_1000nm'), public.wc_num('gear_wear_per_fight'), public.wc_num('gear_wear_per_storm'), public.wc_num('gear_repair_pct'), public.wc_num('running_cost_level');
  -- each company on the same untouched market: her run is rolled back before the next begins (the notices stay)
  for k in select * from (values ('BARCA', array['barca'], 'none', true, 30000::bigint), ('BARCA+', array['barca'], 'cheap', true, 30000),
                                 ('TRADER', array['carlat'], 'cheap', true, 300000), ('TRADER-NEVER', array['carlat'], 'cheap', false, 300000),
                                 ('BIG', array['nau', 'galion'], 'dear', true, 3000000), ('BIG-NEVER', array['nau', 'galion'], 'dear', false, 3000000)) t(kind, classes, fit, repair, purse) loop
    begin
      perform pg_temp.gw_company(k.kind, k.classes, k.fit, k.repair, k.purse, 40);
      raise exception 'GW_ROLLBACK';
    exception when others then
      if sqlerrm <> 'GW_ROLLBACK' then raise; end if;
    end;
  end loop;
end $m$;
