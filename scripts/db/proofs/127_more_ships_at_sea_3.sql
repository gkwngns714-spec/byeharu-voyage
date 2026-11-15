-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 127 - MORE SHIPS AT SEA, 3  (migration 0426; docs/dev-log/2026-11-15-at-sea-3.md; the owner, 2026-11-15: "why are they laid up so
--   much? and also cargoships why so many in ports?"; earlier "have as much as ships available at sea possible"; never a merchant at a loss)
--
--   On the world's own merchants and cargo ships, every scene rolled back (proof.mjs's transaction, and each staged move in its own rolled-back
--   block). The economy is closed and the purses lit, as on prod. EVERY MARKER FAILS ON THE RULES BEFORE 0426: there was no move (a merchant
--   no loop of her harbour paid for was asked about the same loops for ever), a parcel needed 5 %, and a load was 250,000.
--
-- @pass AS3_MOVE     a merchant laid up at a harbour whose loops cannot pay (every purse but one at nothing), refused four times, asked by the waiting-asks job: her plan step moves her home to the one healthy harbour near, the open step resumes her, her lap is open and she sails (or is bound) there with cargo bought here
-- @pass AS3_PAYS     the move's passage pays by the planner's measure (its parcels' profit after tax less its wages, stores and the dock fee, above nothing), and her house's home is the new harbour
-- @pass AS3_STAYS    she does not move when: no harbour near is healthy (she waits, laid up, one more refusal); the knob is 0; she was refused under four times and her last lap is fresh; she moved within the hours; the minute's cap is reached; her house flies the pirate flag; her house has two ships
-- @pass AS3_RETURN   a parcel is kept at 2 % on its outlay: of the legs priced, some keep a BUY at 2 % that 5 % drops, and none keeps fewer
-- @pass AS3_CARGO    a capital whose city is short 500,000 loads it on five idle ships of 100,000 in one run, and the world's money does not move
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $$
begin
  update public.world_config set value = 'true'::jsonb
   where key in ('npc_traders_enabled', 'standing_routes_enabled', 'economy_closed', 'city_treasury_enabled', 'convoys_enabled');
  update public.world_config set value = 'false'::jsonb where key in ('convoy_rich_enabled', 'npc_refits_enabled', 'attack_enabled', 'regard_enabled', 'pirates_bite');
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 50000000, reserve = 0;
  if not public.npc_traders_on() or not public.economy_closed() or not public.city_treasury_on() or not public.convoys_on() then
    raise exception 'PROOF 127 FAIL: the merchants, the closed economy, the purses or the cargo ships cannot be lit in this world';
  end if;
  if to_regprocedure('public.npc_rehome(uuid)') is null or public.wc_int('npc_rehome_per_run') <> 4 or public.wc_int('npc_min_return_pct') <> 2
     or public.wc_int('convoy_load_max') <> 100000 then
    raise exception 'PROOF 127 FAIL: 0426 is not in this world (npc_rehome %, npc_rehome_per_run %, npc_min_return_pct %, convoy_load_max %)',
      to_regprocedure('public.npc_rehome(uuid)'), public.wc_int('npc_rehome_per_run'), public.wc_int('npc_min_return_pct'), public.wc_int('convoy_load_max');
  end if;
end
$$;

-- her harbour p_at, laid up and due, refused p_ref times, her lap long closed or fresh (p_old_lap), every purse at nothing but p_rich's; the planner
-- prices her present loop only (npc_route_candidates 1), so nothing from p_at pays. WRITES: every caller rolls it back.
create function pg_temp.stage_127(p_fleet uuid, p_route uuid, p_rich uuid, p_ref int) returns void language plpgsql as $f$
begin
  update public.world_config set value = to_jsonb(1) where key = 'npc_route_candidates';
  update public.port_treasury set ducats = case when port_id = p_rich then 50000000 else 0 end;
  update public.standing_routes set fleet_id = p_fleet, paused_reason = 'laid_up', hold_until = null, lap_id = null,
                                    stop_cursor = 0, updated_at = now() - interval '3 hours'
   where id = p_route;
  update public.npc_fleets set refused = p_ref, asked_at = null, rehomed_at = null where fleet_id = p_fleet;
  update public.players set ducats = 5000000 where id = (select sr.player_id from public.standing_routes sr where sr.id = p_route);
end
$f$;

-- ── AS3_MOVE, AS3_PAYS ──
do $$
declare
  r       record;
  h       record;
  v_tries int := 0;
  v_a     int;
  v_b     int;
  v_stamp timestamptz;
  v_got   jsonb;
  v_home  uuid;
  v_ev    jsonb;
  v_fleet uuid;
begin
  create temp table cand_127 on commit drop as
  select nf.fleet_id, nf.route_id, nf.player_id, f.port_id, nf.roster_ord, pl.nation_id
    from public.npc_fleets nf
    join public.players pl on pl.id = nf.player_id and not public.pirate_power(pl.nation_id)
    join public.fleets f on f.id = nf.fleet_id and f.status = 'DOCKED'
    join public.standing_routes sr on sr.id = nf.route_id and sr.lap_id is null and (sr.fleet_id is null or sr.fleet_id = nf.fleet_id)
    join public.standing_route_stops s on s.route_id = sr.id and s.ord = 0 and s.port_id = f.port_id
   where not exists (select 1 from public.ships sh where sh.fleet_id = nf.fleet_id and public.ship_cargo_tuns(sh.id) > 0)
     and not exists (select 1 from public.orders o where o.fleet_id = nf.fleet_id and o.status in ('pending', 'failed'))
     and (select count(*) from public.npc_fleets n2 where n2.player_id = nf.player_id) = 1
   order by nf.roster_ord
   limit 12;
  <<search>>
  for r in select * from cand_127 order by roster_ord loop
    for h in
      select (x->>'port_id')::uuid as port_id
        from jsonb_array_elements(public.npc_feasible_legs(r.port_id, r.fleet_id, greatest(coalesce(voyage.fleet_speed_at(r.fleet_id, 1), 0), 0.1),
               (select pr.days from public.fleets f join public.provision_presets pr on pr.id = f.provision_preset_id where f.id = r.fleet_id))) x
       where not exists (select 1 from public.standing_route_stops s where s.route_id = r.route_id and s.port_id = (x->>'port_id')::uuid)
       order by coalesce(public.port_nation((x->>'port_id')::uuid) = r.nation_id, false) desc, (x->>'nm')::numeric
       limit 4
    loop
      v_tries := v_tries + 1;
      v_got := null;
      begin
        perform pg_temp.stage_127(r.fleet_id, r.route_id, h.port_id, 4);
        call public.tick_waiting_asks(false, r.fleet_id);
        v_got := jsonb_build_object(
          'paused', (select sr.paused_reason from public.standing_routes sr where sr.id = r.route_id),
          'lap', (select sr.lap_id is not null from public.standing_routes sr where sr.id = r.route_id),
          'loop', (select jsonb_agg(s.port_id order by s.ord) from public.standing_route_stops s where s.route_id = r.route_id),
          'home', (select hh.home_port_id from public.npc_houses hh where hh.player_id = r.player_id),
          'bound', coalesce((select v.dest_port_id from public.voyages v where v.fleet_id = r.fleet_id and v.status = 'SAILING'),
                            (select (o.args->>'dest_port_id')::uuid from public.orders o where o.fleet_id = r.fleet_id and o.verb = 'SAIL' and o.status = 'pending' limit 1)),
          'status', (select f.status from public.fleets f where f.id = r.fleet_id),
          'aboard', (select coalesce(sum(public.ship_cargo_tuns(s.id)), 0) from public.ships s where s.fleet_id = r.fleet_id),
          'buys', (select count(*) from public.orders o where o.fleet_id = r.fleet_id and o.verb = 'BUY'),
          'refused', (select nf.refused from public.npc_fleets nf where nf.fleet_id = r.fleet_id),
          'event', (select e.payload from public.events e where e.player_id = r.player_id and e.kind = 'NPC_REHOMED' order by e.created_at desc limit 1),
          'receipt', (select w.receipt - 'note' from public.waiting_ask_runs w order by w.at desc limit 1));
        raise exception sqlstate 'BV127';
      exception when sqlstate 'BV127' then null;
      end;
      if v_got->'event' is not null and v_got->'event' <> 'null'::jsonb then
        v_fleet := r.fleet_id;
        exit search;
      end if;
    end loop;
  end loop;
  if v_fleet is null then
    raise exception 'PROOF 127 FAIL: of % merchants and harbours staged (one healthy harbour near, every other purse at nothing), none moved: last %', v_tries, v_got;
  end if;
  if v_got->>'paused' is not null or not (v_got->>'lap')::boolean
     or v_got->'loop'->>0 <> v_got->>'home' or v_got->'loop'->>1 <> (select c.port_id::text from cand_127 c where c.fleet_id = v_fleet)
     or v_got->>'bound' is distinct from v_got->>'home'
     or ((v_got->>'aboard')::numeric <= 0 and (v_got->>'buys')::int = 0)
     or (v_got->'receipt'->>'resumed')::int <> 1 then
    raise exception 'PROOF 127 FAIL: AS3_MOVE: moved but not resumed and bound for her new home with cargo: %', v_got;
  end if;
  raise notice 'PASS: AS3_MOVE — % tries; % -> %: resumed (lap open), % bound there with % tuns aboard / % BUY orders; the job''s receipt resumed %',
    v_tries, v_got->'event'->>'from', v_got->'event'->>'to', v_got->>'status', v_got->>'aboard', v_got->>'buys', v_got->'receipt'->>'resumed';
  if (v_got->'event'->>'passage_net')::numeric <= 0 then
    raise exception 'PROOF 127 FAIL: AS3_PAYS: the passage did not pay: %', v_got->'event';
  end if;
  raise notice 'PASS: AS3_PAYS — the passage % -> % nets % (the loop %); her house''s home is now %',
    v_got->'event'->>'from', v_got->'event'->>'to', v_got->'event'->>'passage_net', v_got->'event'->>'loop_net',
    (select p.code from public.ports p where p.id = (v_got->>'home')::uuid);
  create temp table move_127 on commit drop as
  select c.fleet_id, c.route_id, c.player_id, c.port_id, (v_got->>'home')::uuid as dest from cand_127 c where c.fleet_id = v_fleet;
end
$$;

-- ── AS3_STAYS ── (the merchant and harbour that moved above, each case alone, rolled back)
do $$
declare
  m      record;
  v_out  text := '';
  v_one  text;
  v_pir  uuid := (select g.nation_id from public.great_powers g where g.pirate limit 1);
  v_oth  uuid;
begin
  select * into m from move_127;
  for v_one in select unnest(array['no_healthy', 'knob_0', 'refused_3', 'moved_lately', 'cap', 'pirate', 'two_ships']) loop
    begin
      perform pg_temp.stage_127(m.fleet_id, m.route_id, m.dest, 4);
      case v_one
        when 'no_healthy' then update public.port_treasury set ducats = 0;
        when 'knob_0' then update public.world_config set value = to_jsonb(0) where key = 'npc_rehome_per_run';
        when 'refused_3' then
          update public.npc_fleets set refused = 2 where fleet_id = m.fleet_id;   -- the plan makes it 3
          insert into public.standing_route_laps (route_id, lap_no, started_at, closed_at)
          values (m.route_id, 100000, now() - interval '1 hour', now() - interval '30 minutes');
        when 'moved_lately' then update public.npc_fleets set rehomed_at = now() - interval '1 hour' where fleet_id = m.fleet_id;
        when 'cap' then
          update public.npc_fleets set rehomed_at = now()
           where fleet_id in (select n.fleet_id from public.npc_fleets n where n.fleet_id <> m.fleet_id order by n.roster_ord limit 4);
        when 'pirate' then
          if v_pir is null then raise exception 'PROOF 127 FAIL: no pirate power in this world'; end if;
          update public.players set nation_id = v_pir where id = m.player_id;
        when 'two_ships' then
          select n.fleet_id into v_oth from public.npc_fleets n where n.player_id <> m.player_id order by n.roster_ord limit 1;
          update public.npc_fleets set player_id = m.player_id where fleet_id = v_oth;
      end case;
      call public.tick_waiting_asks(false, m.fleet_id);
      if exists (select 1 from public.events e where e.player_id = m.player_id and e.kind = 'NPC_REHOMED')
         or (select sr.paused_reason from public.standing_routes sr where sr.id = m.route_id) is distinct from 'laid_up'
         or (select h.home_port_id from public.npc_houses h where h.player_id = m.player_id) = m.dest
         or (v_one = 'no_healthy' and (select nf.refused from public.npc_fleets nf where nf.fleet_id = m.fleet_id) <> 5) then
        raise exception 'PROOF 127 FAIL: AS3_STAYS: % — she moved or was resumed (paused %, refused %)', v_one,
          (select sr.paused_reason from public.standing_routes sr where sr.id = m.route_id), (select nf.refused from public.npc_fleets nf where nf.fleet_id = m.fleet_id);
      end if;
      v_out := v_out || v_one || ' ';
      raise exception sqlstate 'BV127';
    exception when sqlstate 'BV127' then null;
    end;
  end loop;
  if v_out <> 'no_healthy knob_0 refused_3 moved_lately cap pirate two_ships ' then
    raise exception 'PROOF 127 FAIL: AS3_STAYS ran only: %', v_out;
  end if;
  raise notice 'PASS: AS3_STAYS — she stays, laid up, in each case: %', v_out;
end
$$;

-- ── AS3_RETURN ──
do $$
declare
  r      record;
  v_n2   int;
  v_n5   int;
  v_more int := 0;
  v_less int := 0;
  v_legs int := 0;
begin
  for r in
    select nf.route_id, nf.fleet_id, s0.port_id as a, s1.port_id as b
      from public.npc_fleets nf
      join public.standing_route_stops s0 on s0.route_id = nf.route_id and s0.ord = 0
      join public.standing_route_stops s1 on s1.route_id = nf.route_id and s1.ord = 1
     order by nf.roster_ord limit 40
  loop
    v_legs := v_legs + 1;
    update public.world_config set value = to_jsonb(2) where key = 'npc_min_return_pct';
    v_n2 := (select count(*) from jsonb_array_elements(public.npc_leg_lines(r.route_id, r.a, r.b, 400, 20, 5)->'lines') l where l->>'kind' = 'BUY');
    update public.world_config set value = to_jsonb(5) where key = 'npc_min_return_pct';
    v_n5 := (select count(*) from jsonb_array_elements(public.npc_leg_lines(r.route_id, r.a, r.b, 400, 20, 5)->'lines') l where l->>'kind' = 'BUY');
    if v_n2 > v_n5 then v_more := v_more + 1; end if;
    if v_n2 < v_n5 then v_less := v_less + 1; end if;
  end loop;
  update public.world_config set value = to_jsonb(2) where key = 'npc_min_return_pct';
  if v_more = 0 or v_less > 0 then
    raise exception 'PROOF 127 FAIL: AS3_RETURN: of % legs, % keep more BUY lines at 2 %% than at 5 %%, % fewer', v_legs, v_more, v_less;
  end if;
  raise notice 'PASS: AS3_RETURN — of % legs, % keep a BUY at 2 %% that 5 %% drops, none fewer', v_legs, v_more;
end
$$;

-- ── AS3_CARGO ──
do $$
declare
  v_nat  uuid := (select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT');
  v_cap  uuid;
  v_city uuid;
  v_w0   numeric;
  v_w1   numeric;
  v_r    jsonb;
  v_big  bigint;
  v_i    int;
begin
  update public.port_treasury set ducats = 50000000, reserve = 0;
  v_cap := public.realm_capital(v_nat);
  for v_i in 1 .. 4 loop
    perform public.tick_cargo_ships(now(), v_nat);
  end loop;
  update public.voyages v set status = 'ABORTED' where v.status = 'SAILING' and v.fleet_id in (select c.fleet_id from public.cargo_ships c where c.nation_id = v_nat);
  update public.fleets f set status = 'DOCKED', port_id = c.home_port_id, lat = null, lon = null, ready_at = null
    from public.cargo_ships c where c.fleet_id = f.id and c.nation_id = v_nat;
  update public.cargo_ships c set out_load = null, circuit_id = null, leg = 0 where c.nation_id = v_nat;
  select p.id into v_city from public.ports p where p.kind = 'HARBOUR' and p.id <> v_cap and public.city_capital(p.id) = v_cap order by p.code limit 1;
  update public.port_treasury t set ducats = 1000000000 where t.port_id = v_cap;
  update public.port_treasury t set ducats = 0 where t.port_id = v_city;
  v_w0 := (select sum(public.treasury_balance(t.port_id)) from public.port_treasury t) + public.funds_aboard();
  v_r := public.cargo_ships_load(jsonb_build_array(jsonb_build_object('port_id', v_city, 'cap', v_cap, 'target', 500000)));
  v_w1 := (select sum(public.treasury_balance(t.port_id)) from public.port_treasury t) + public.funds_aboard();
  select max(b.ducats) into v_big from public.convoy_cargo b join public.cargo_ships c on c.fleet_id = b.fleet_id where c.nation_id = v_nat and b.stage = 'LOADED';
  if (v_r->>'ships')::int <> 5 or (v_r->>'loaded')::bigint <> 500000 or v_big > 100000 or v_w1 <> v_w0 then
    raise exception 'PROOF 127 FAIL: AS3_CARGO: a city short 500,000: % (largest load %, money before %, after %)', v_r, v_big, v_w0, v_w1;
  end if;
  raise notice 'PASS: AS3_CARGO — a city short 500,000: one run loaded % ships with % d. (the largest %); the money unmoved', v_r->'ships', v_r->'loaded', v_big;
end
$$;
