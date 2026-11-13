-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 99 - FAR TRADERS REACH THE FAR HARBOURS  (migration 0404; docs/SEA_CONDITIONS_AND_REGIONS.md slice S4)
--
--   On the world's own far traders, rolled back with proof.mjs's transaction. Nothing here reads a price, the world's secret or what the planner
--   CHOOSES: only what the sea rule and the founding path guarantee. The gold is proved by founding one more far trader under the closed economy
--   with the purses lit, as prod founds them.
--
-- @pass FT_HOUSES  24 far-trader houses, one hull each (20 of size 4, 4 of size 5), every fleet's wave 57 or more; each of the 15 far harbours is the home of one or two; none is homed in a pirate home
-- @pass FT_OPEN    lit, where she lies: every far trader is offered at least one leg from her home and her present loop has no leg the sea closes to her
-- @pass FT_BITES   the control: with a nau's wave (39) no remembered leg out of Cape Town or Hobart is open, so the houses there sail only because of their hulls
-- @pass FT_BERTH   npc_fleet_max is not under the roster: no merchant lies paused for want of a berth
-- @pass FT_GOLD    closed, purses lit: one more far trader founded through public.npc_found is paid by a city's purse to the ducat (her ledger and the cities' flows that name her sum to nothing), her purse is her capital, and the world total is unchanged
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
do $p$
declare
  v_bad   text;
  v_n     int;
  v_tot0  numeric;
  v_tot1  numeric;
  v_p     uuid;
  v_home  uuid;
  v_leg   record;
  v_back  jsonb;
  v_led   bigint;
  v_flow  bigint;
begin
  create temp table ft99 on commit drop as
  select nf.fleet_id, nf.route_id, nf.player_id, nh.home_port_id, hp.code as home, c.code as class, c.speed_kn, cp.size, public.fleet_wave(nf.fleet_id) as wave
    from public.npc_fleets nf
    join public.npc_houses nh on nh.player_id = nf.player_id
    join public.ports hp on hp.id = nh.home_port_id
    join public.ships s on s.fleet_id = nf.fleet_id
    join public.ship_classes c on c.id = s.class_id
    join public.class_profile cp on cp.class_code = c.code
   where c.code in ('taforeia', 'retour', 'nao', 'hourque', 'indiaman', 'naucarr');

  -- ── FT_HOUSES ──
  if (select count(*) from ft99) <> 24 or (select count(distinct player_id) from ft99) <> 24
     or (select count(*) from ft99 where size = 4) <> 20 or (select count(*) from ft99 where size = 5) <> 4
     or exists (select 1 from ft99 where wave < 57)
     or (select string_agg(distinct home, ' ' order by home) from ft99) <> 'AMB BND CPT DIL GAL HAG HOB KOL MAK OLD PLO STG SYD TER TID'
     or exists (select 1 from ft99 group by home having count(*) > 2)
     or exists (select 1 from ft99 where public.pirate_home(home_port_id)) then
    raise exception 'PROOF 99 FAIL: the far traders are not 24 houses of one hull (20 of size 4, 4 of size 5, wave 57 or more) at the 15 far harbours: %',
      (select jsonb_agg(jsonb_build_object('home', home, 'class', class, 'wave', wave)) from ft99);
  end if;
  raise notice 'PASS: FT_HOUSES — 24 houses at 15 harbours, waves % to %', (select min(wave) from ft99), (select max(wave) from ft99);

  -- ── FT_OPEN ──
  update public.world_config set value = 'true'::jsonb where key = 'sea_conditions_bite_npc';
  select string_agg(f.home || ' ' || f.class, ', ') into v_bad
    from ft99 f
   where jsonb_array_length(coalesce(public.npc_feasible_legs(f.home_port_id, f.fleet_id, f.speed_kn, 90), '[]'::jsonb)) = 0
      or public.npc_loop_sea_shut(f.fleet_id,
           (select jsonb_agg(jsonb_build_object('port_id', st.port_id, 'course', st.course) order by st.ord) from public.standing_route_stops st where st.route_id = f.route_id))
      or (select st.port_id from public.standing_route_stops st where st.route_id = f.route_id and st.ord = 0) is distinct from f.home_port_id;
  if v_bad is not null then
    raise exception 'PROOF 99 FAIL: lit, a far trader has no open leg from home or a closed loop: %', v_bad;
  end if;
  raise notice 'PASS: FT_OPEN — lit, all 24 are offered a leg from home and sail a loop the sea leaves open';
  update public.world_config set value = 'false'::jsonb where key = 'sea_conditions_bite_npc';

  -- ── FT_BITES ──
  select count(*) into v_n
    from public.ports h cross join lateral public.npc_known_legs(h.id) l
   where h.code in ('CPT', 'HOB') and public.npc_sea_shut(39, l.to_port, l.course) is null;
  if v_n <> 0 or not exists (select 1 from public.ports h cross join lateral public.npc_known_legs(h.id) l where h.code = 'CPT' and public.npc_sea_shut(57, l.to_port, l.course) is null)
     or not exists (select 1 from public.ports h cross join lateral public.npc_known_legs(h.id) l where h.code = 'HOB' and public.npc_sea_shut(57, l.to_port, l.course) is null) then
    raise exception 'PROOF 99 FAIL: a nau (wave 39) holds % remembered legs out of Cape Town and Hobart, or wave 57 holds none', v_n;
  end if;
  raise notice 'PASS: FT_BITES — a nau holds no remembered leg out of Cape Town or Hobart; wave 57 does';

  -- ── FT_BERTH ──
  if public.wc_int('npc_fleet_max') < (select count(*) from public.npc_fleets) then
    raise exception 'PROOF 99 FAIL: npc_fleet_max % is under the % fleets on the roster', public.wc_int('npc_fleet_max'), (select count(*) from public.npc_fleets);
  end if;
  raise notice 'PASS: FT_BERTH — npc_fleet_max % holds the % fleets', public.wc_int('npc_fleet_max'), (select count(*) from public.npc_fleets);

  -- ── FT_GOLD: one more, founded as prod founds them (closed, purses lit, Lisbon rich) ──
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed');
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury t set ducats = 500000000, reserve = 1000 from public.ports p where p.id = t.port_id and p.code = 'LIS';
  select p.id into v_home from public.ports p where p.code = 'CPT';
  select l.to_port, l.code, l.course, l.nm, (select jsonb_agg(t.x order by t.i desc) from jsonb_array_elements(l.course) with ordinality t(x, i)) as back into v_leg
    from public.npc_known_legs(v_home) l join public.ports p on p.id = l.to_port
   where p.kind = 'HARBOUR' and not p.is_ice_closed and not public.pirate_home(p.id) and public.npc_sea_shut(57, l.to_port, l.course) is null
   order by l.nm, l.to_port limit 1;
  v_back := v_leg.back;
  v_tot0 := (world.stats_now() ->> 'total')::numeric;
  v_p := public.npc_found(jsonb_build_object(
    'company', 'Proof 99 Far Trader', 'alt_company', 'Proof 99 Far Trader II', 'nation', 'PRT', 'ink', 'prt', 'master', 'Capitão Prova',
    'blurb', 'A far trader of the proof: one great hull that holds the ocean legs — under Capitão Prova.',
    'capital', 40000, 'patience', 0.30, 'wares', '[]'::jsonb, 'skills', jsonb_build_object('NAVIGATION', 2, 'HAGGLING', 1),
    'roster_ord', (select max(h.roster_ord) + 1 from public.npc_houses h),
    'fleets', jsonb_build_array(jsonb_build_object(
      'name', 'Proof 99 Far Trader', 'roster_ord', (select max(f.roster_ord) + 1 from public.npc_fleets f), 'home', 'CPT', 'days', 30,
      'ships', jsonb_build_array(jsonb_build_object('class', 'taforeia', 'name', 'Santa Prova')), 'officers', '[]'::jsonb,
      'stops', jsonb_build_array(jsonb_build_object('port', 'CPT', 'course', v_leg.course), jsonb_build_object('port', v_leg.code, 'course', v_back))))));
  v_tot1 := (world.stats_now() ->> 'total')::numeric;
  select coalesce(sum(l.ducats_delta), 0) into v_led from public.ledger l where l.player_id = v_p;
  select coalesce(sum(f.ducats), 0) into v_flow from public.treasury_flows f where f.player_id = v_p;
  if v_led <> 40000 or v_led + v_flow <> 0 or (select pl.ducats from public.players pl where pl.id = v_p) <> 40000 or v_tot1 <> v_tot0
     or not exists (select 1 from public.treasury_flows f where f.player_id = v_p and f.kind = 'FOUNDING' and f.ducats < 0)
     or (select public.fleet_wave(f.id) from public.fleets f where f.player_id = v_p) <> 57 then
    raise exception 'PROOF 99 FAIL: closed, the founding does not reconcile: ledger %, flows %, purse %, world total % then %',
      v_led, v_flow, (select pl.ducats from public.players pl where pl.id = v_p), v_tot0, v_tot1;
  end if;
  raise notice 'PASS: FT_GOLD — closed: her 40,000 and her tuition came from a city''s purse (flows %), the world total stayed %', v_flow, v_tot1;
end
$p$;
