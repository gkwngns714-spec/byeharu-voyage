-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 155 - AN ESCORT IS RE-RATED IN HARBOUR  (migration 0452; docs/dev-log/2026-11-16-escort-refit.md)
--
--   Prod, 2026-11-16 (head 0451): the ladder re-rated 40 navy fleets and never the last ship of eight lines, each escorting a cargo ship: the
--   refit refused any navy ship with escort_of set, and public.navy_escort_step keeps it set while any cargo ship of hers sails with funds.
--   Here, through the real doors: Spain keeps two navy ships at her capital; one of her cargo ships sails for it with funds aboard, so her
--   own escort step makes ord 2 (the last of the line) the escort; then the minute's re-rating (public.npc_ladder_pass) and a raid on the ward
--   (public.navy_call). Rolled back with proof.mjs's transaction. ER_RATED and ER_CALL FAIL BEFORE 0452: the escort stays one galion.
--
-- @pass ER_DUTY   her own escort step makes the last ship of Spain's line the escort of the cargo ship at sea with funds; she waits in harbour
-- @pass ER_HELD   called to a fight she is not re-rated, the Frigate beside her is; inside the ladder's pace
-- @pass ER_RATED  freed, the next minute's pass re-rates the escort to her rung (Brigs: two zabras of Spain's line), in harbour; her mission and her ward unmoved
-- @pass ER_CALL   her duty after: her escort step still keeps her, and a raid on the ward puts her on its sheet at once as its ESCORT, on her new hulls
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

create function pg_temp.sig_155(p_fleet uuid) returns text language sql as $f$
  select string_agg(h.code || '*' || h.n, '+' order by h.code)
    from (select k.code, count(*) as n from public.ships s join public.ship_classes k on k.id = s.class_id where s.fleet_id = p_fleet group by k.code) h
$f$;

do $p$
declare
  t0     timestamptz := date_trunc('minute', now()) + interval '1 day';
  v_nat  uuid := (select n.id from public.nations n where n.code = 'ESP');
  v_cap  uuid;
  v_pl   uuid;
  v_n    uuid[] := '{}';
  v_c    uuid;
  v_g    uuid;
  v_bat  uuid;
  v_r    jsonb;
  v_s    text;
  v_k    int;
  i      int;
begin
  -- ── THE SCENE ──
  update public.world_config set value = 'true'::jsonb
   where key in ('navy_enabled', 'city_treasury_enabled', 'convoys_enabled', 'convoy_armed_enabled', 'npc_ladder_enabled') and value is distinct from 'true'::jsonb;
  update public.world_config set value = 'false'::jsonb where key = 'pirates_trade' and value is distinct from 'false'::jsonb;
  v_cap := public.realm_capital(v_nat);
  if v_cap is null or not public.navy_on() or exists (select 1 from public.navy_ships n where n.nation_id = v_nat)
     or exists (select 1 from public.cargo_ships c where c.nation_id = v_nat) or public.wc_int('navy_escorts') <> 1 then
    raise exception 'PROOF 155 FAIL: no Spanish capital, the navy is not lit, Spain already keeps navy or cargo ships, or navy_escorts is not 1 in this world';
  end if;
  insert into public.navy_realms (nation_id, ships) values (v_nat, 2) on conflict (nation_id) do update set ships = 2;
  for i in 1 .. 2 loop
    insert into public.players (company_name, nation_id, ducats, is_npc) values ('Proof 155 navy ' || i, v_nat, 0, true) returning id into v_pl;
    v_g := public.form_fleet(v_pl, 'Proof 155 navy ' || i, v_cap);
    perform public.commission_ship(v_pl, v_g, 'galion', 'Proof 155 navy ' || i, true, false);
    update public.ships s set crew = c.crew_required from public.ship_classes c where c.id = s.class_id and s.fleet_id = v_g;
    insert into public.navy_ships (fleet_id, player_id, nation_id, ord, station_port, last_port, created_at) values (v_g, v_pl, v_nat, i, v_cap, v_cap, t0);
    v_n := v_n || v_g;
  end loop;
  -- the ward: a cargo ship of Spain at sea for the capital, funds aboard
  insert into public.players (company_name, nation_id, ducats, is_npc) values ('Proof 155 cargo', v_nat, 0, true) returning id into v_pl;
  v_c := public.form_fleet(v_pl, 'Proof 155 cargo', v_cap);
  perform public.commission_ship(v_pl, v_c, public.cargo_class(), 'Proof 155 cargo', true, false);
  insert into public.cargo_ships (fleet_id, player_id, nation_id, home_port_id, ord) values (v_c, v_pl, v_nat, v_cap, 1);
  insert into public.convoy_cargo (stage, fleet_id, player_id, port_id, ducats) values ('LOADED', v_c, v_pl, v_cap, 50000);
  update public.fleets set status = 'SAILING', port_id = null where id = v_c;
  insert into public.voyages (fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta, status, origin_port_id, dest_port_id)
  values (v_c, v_pl, '[]'::jsonb, 100, '{}'::jsonb, t0 - interval '1 hour', t0 + interval '5 hours', 'SAILING', v_cap, v_cap);

  -- ── ER_DUTY ──
  v_s := public.navy_escort_step(v_n[2], v_cap, public.navy_on_duty(v_nat, 2, null), t0);
  if v_s is distinct from 'ESCORT' or public.navy_escort_step(v_n[1], v_cap, public.navy_on_duty(v_nat, 1, null), t0) is not null
     or (select count(*) from public.navy_ships n where n.fleet_id = v_n[2] and n.mission = 'ESCORT' and n.escort_of = v_c) <> 1
     or (select f.status from public.fleets f where f.id = v_n[2]) <> 'DOCKED' then
    raise exception 'PROOF 155 FAIL: ord 2 is not the escort of the ward, waiting in harbour: step %', v_s;
  end if;
  raise notice 'PASS: ER_DUTY — Spain''s ord 2 of 2: %, escort_of the ward, DOCKED; ord 1 no escort', v_s;

  -- ── ER_HELD ──
  update public.navy_ships n set called_to = v_cap where n.fleet_id = v_n[2];
  v_r := public.npc_ladder_pass(t0 + interval '1 minute');
  if (v_r ->> 'rated')::int is distinct from 1 or pg_temp.sig_155(v_n[1]) <> 'galeon*1' or pg_temp.sig_155(v_n[2]) <> 'galion*1' then
    raise exception 'PROOF 155 FAIL: called out, the escort was re-rated, or the Frigate was not: %, %, %', v_r, pg_temp.sig_155(v_n[1]), pg_temp.sig_155(v_n[2]);
  end if;
  raise notice 'PASS: ER_HELD — called to a fight: the pass %, ord 1 %, the escort stays %', v_r, pg_temp.sig_155(v_n[1]), pg_temp.sig_155(v_n[2]);
  update public.navy_ships n set called_to = null where n.fleet_id = v_n[2];

  -- ── ER_RATED ──
  v_r := public.npc_ladder_pass(t0 + interval '2 minutes');
  if (v_r ->> 'rated')::int is distinct from 1 or pg_temp.sig_155(v_n[2]) <> 'zabra*2' or public.npc_rung_of(v_n[2]) <> 2
     or (select count(*) from public.ships s where s.fleet_id = v_n[2] and s.is_flagship and s.name = 'Proof 155 navy 2') <> 1
     or (select count(*) from public.navy_ships n where n.fleet_id = v_n[2] and n.mission = 'ESCORT' and n.escort_of = v_c and n.battle_id is null) <> 1
     or not exists (select 1 from public.npc_fleet_rungs g where g.fleet_id = v_n[2] and g.kind = 'NAVY' and g.rung = 2 and g.hulls = 'zabra*2')
     or (select f.status from public.fleets f where f.id = v_n[2]) <> 'DOCKED' then
    raise exception 'PROOF 155 FAIL: the escort in harbour was not re-rated to Spain''s Brigs with her duty intact: %, %, row %', v_r, pg_temp.sig_155(v_n[2]),
      (select to_jsonb(n) from public.navy_ships n where n.fleet_id = v_n[2]);
  end if;
  if (public.npc_ladder_pass(t0 + interval '3 minutes')) ? 'rated' then
    raise exception 'PROOF 155 FAIL: the pass re-rated a fleet that is her rung';
  end if;
  raise notice 'PASS: ER_RATED — the next minute: %, the escort galion -> %, still ESCORT of her ward, in harbour', v_r, pg_temp.sig_155(v_n[2]);

  -- ── ER_CALL ──
  v_s := public.navy_escort_step(v_n[2], v_cap, true, t0 + interval '4 minutes');
  insert into public.battles (kind, site, started_at, resolves_at, status)
  select 'RAID', jsonb_build_object('lat', p.lat, 'lon', p.lon), t0 + interval '4 minutes', t0 + interval '1 hour', 'FIGHTING' from public.ports p where p.id = v_cap
  returning id into v_bat;
  update public.fleets set status = 'DOCKED', port_id = v_cap where id = v_c;
  v_k := public.navy_call(v_bat, v_c, t0 + interval '4 minutes', t0 + interval '1 hour');
  if v_s is distinct from 'ESCORT' or v_k < 1
     or (select count(*) from public.battle_sides bs where bs.battle_id = v_bat and bs.fleet_id = v_n[2] and bs.how = 'ESCORT' and bs.arrives_at = bs.joined_at) <> 1
     or (select n.battle_id from public.navy_ships n where n.fleet_id = v_n[2]) is distinct from v_bat
     or pg_temp.sig_155(v_n[2]) <> 'zabra*2' then
    raise exception 'PROOF 155 FAIL: after her re-rating the escort did not answer the raid on her ward: step %, called %', v_s, v_k;
  end if;
  raise notice 'PASS: ER_CALL — her step %, the raid called %, the escort on its sheet as ESCORT at once, on %', v_s, v_k, pg_temp.sig_155(v_n[2]);
end $p$;
