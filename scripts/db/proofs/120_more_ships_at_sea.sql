-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 120 - MORE SHIPS AT SEA  (migration 0423; docs/dev-log/2026-11-15-at-sea.md; the owner, 2026-11-15: "why are there still ships that are
--   laid up, or in port this much? make it so that it fixes and have as much as ships available at sea possible.")
--
--   On the world's own merchants, cargo ships and navy, every scene rolled back with proof.mjs's transaction (and each plan alone in its own
--   rolled-back block). The economy is closed and the purses lit, as on prod. EVERY MARKER FAILS ON THE RULES BEFORE 0423: the rest was 600 s, the
--   planner never priced a loop past her 5 nearest and 6 trade harbours, the waits went 10 20 40 50, a capital loaded one ship a run, and a
--   hunter lay six hours, and a home gave its room to one ship a run (at her own station when her own sea was the worst).
--
-- @pass AS_REST      a merchant whose lap has just closed rests at home at most 150 real seconds before her next lap (cmd.run_standing_route's hold)
-- @pass AS_WIDER     a merchant whose only paying loop runs to a harbour 0407's candidate set (5 near, 6 trade, 16 loops) never offers her is laid up under that set and SAILS it, with a BUY, under the live one
-- @pass AS_GUARD     the same merchant with that harbour's purse at nothing too: no loop pays and she waits in port with no BUY (0181, 0410 stand)
-- @pass AS_ASK       a laid-up merchant refused 1 to 5 times is due 10 20 30 30 30 minutes after her last ask; broke, 50
-- @pass AS_CARGO     a capital whose city is short by five ships' loads loads five idle ships in ONE run, none above convoy_load_max, and the world's money does not move; a home gives its room once a run
-- @pass AS_NAVY_OWN  a navy ship at her station whose own sea is the most dangerous sails her patrol (mission PATROL, a voyage) instead of lying there
-- @pass AS_NAVY_LIE  a hunter bound for another sea lies there at most half a voyage-day after she arrives
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $$
begin
  update public.world_config set value = 'true'::jsonb
   where key in ('npc_traders_enabled', 'standing_routes_enabled', 'economy_closed', 'city_treasury_enabled', 'convoys_enabled');
  update public.world_config set value = 'false'::jsonb where key in ('convoy_rich_enabled', 'npc_refits_enabled', 'attack_enabled', 'regard_enabled');
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 50000000, reserve = 0;
  if not public.npc_traders_on() or not public.economy_closed() or not public.city_treasury_on() or not public.convoys_on() then
    raise exception 'PROOF 120 FAIL: the merchants, the closed economy, the purses or the cargo ships cannot be lit in this world';
  end if;
end
$$;

-- the destinations of every loop public.npc_loop_candidates offers her now, with the knobs as they stand
create function pg_temp.dests_120(p_route uuid, p_fleet uuid, p_home uuid) returns setof uuid language sql as $f$
  select distinct (x->>'port_id')::uuid
    from public.npc_loop_candidates(p_route, p_fleet, p_home,
           (select coalesce(sum(public.ship_cargo_tuns(s.id)), 0) from public.ships s where s.fleet_id = p_fleet) + public.fleet_free_hold(p_fleet),
           greatest(coalesce(voyage.fleet_speed_at(p_fleet, 1), 0), 0.1)) c
   cross join lateral jsonb_array_elements(c.stops) x
   where (x->>'port_id')::uuid <> p_home
$f$;

-- 0407's candidate set (the knobs before 0423), or the live one (p_old false: the knobs as they stand)
create function pg_temp.old_set_120(p_old boolean) returns void language sql as $f$
  update public.world_config set value = to_jsonb(5)  where p_old and key = 'npc_route_neighbours';
  update public.world_config set value = to_jsonb(6)  where p_old and key = 'npc_route_trade_candidates';
  update public.world_config set value = to_jsonb(16) where p_old and key = 'npc_route_candidates';
$f$;

-- she is planned alone at her lap start with every purse at nothing but p_rich's; answers what she wrote. WRITES: every caller rolls it back.
create function pg_temp.plan_120(p_route uuid, p_rich uuid) returns jsonb language plpgsql as $f$
declare
  v jsonb;
begin
  update public.port_treasury set ducats = case when port_id = p_rich then 100000000 else 0 end;
  v := public.npc_plan(now(), p_route) - 'notes';
  return v || jsonb_build_object(
    'paused', (select sr.paused_reason from public.standing_routes sr where sr.id = p_route),
    'buys', (select count(*) from public.standing_route_lines l where l.route_id = p_route and l.kind = 'BUY'),
    'to_rich', exists (select 1 from public.standing_route_stops s where s.route_id = p_route and s.port_id = p_rich),
    'loop', (select string_agg(p.code, '-' order by s.ord) from public.standing_route_stops s join public.ports p on p.id = s.port_id where s.route_id = p_route));
end
$f$;

-- ── MERCHANTS ──
do $$
declare
  r       record;
  d       uuid;
  v_new   jsonb;
  v_old   jsonb;
  v_none  jsonb;
  v_tries int := 0;
  v_fleet uuid;
  v_route uuid;
  v_dest  uuid;
  v_hold  timestamptz;
  v_rest  numeric;
  v_steps text := '';
  v_n     int;
  v_olds  uuid[];
begin
  create temp table cand_120 on commit drop as
  select nf.fleet_id, nf.route_id, f.port_id, nf.roster_ord
    from public.npc_fleets nf
    join public.players pl on pl.id = nf.player_id and not public.pirate_power(pl.nation_id)
    join public.fleets f on f.id = nf.fleet_id and f.status = 'DOCKED'
    join public.standing_routes sr on sr.id = nf.route_id and sr.lap_id is null and (sr.fleet_id is null or sr.fleet_id = nf.fleet_id)
    join public.standing_route_stops s on s.route_id = sr.id and s.ord = 0 and s.port_id = f.port_id
   where not exists (select 1 from public.ships sh where sh.fleet_id = nf.fleet_id and public.ship_cargo_tuns(sh.id) > 0)
     and not exists (select 1 from public.orders o where o.fleet_id = nf.fleet_id and o.status in ('pending', 'failed'))
   order by nf.roster_ord
   limit 12;
  update public.standing_routes sr set fleet_id = c.fleet_id, paused_reason = null, hold_until = null from cand_120 c where sr.id = c.route_id;

  -- AS_WIDER: the first merchant and harbour where the live set offers a loop 0407's never offered, and that loop pays when its harbour alone can pay
  <<search>>
  for r in select * from cand_120 order by roster_ord loop
    v_olds := null;
    begin   -- a variable keeps what a rolled-back block read; a table would not
      perform pg_temp.old_set_120(true);
      v_olds := array(select pg_temp.dests_120(r.route_id, r.fleet_id, r.port_id));
      raise exception sqlstate 'BV120';
    exception when sqlstate 'BV120' then null;
    end;
    if v_olds is null then
      raise exception 'PROOF 120 FAIL: 0407''s candidate set was not read';
    end if;
    for d in select x from pg_temp.dests_120(r.route_id, r.fleet_id, r.port_id) x where not (x = any (v_olds)) order by x loop
      v_tries := v_tries + 1;
      exit search when v_tries > 12;
      begin
        v_new := pg_temp.plan_120(r.route_id, d);
        raise exception sqlstate 'BV120';
      exception when sqlstate 'BV120' then null;
      end;
      if (v_new->>'waiting')::int = 0 and (v_new->>'buys')::int > 0 and (v_new->>'to_rich')::boolean then
        v_fleet := r.fleet_id; v_route := r.route_id; v_dest := d;
        exit search;
      end if;
    end loop;
  end loop;
  if v_fleet is null then
    raise exception 'PROOF 120 FAIL: no merchant of the first twelve has a paying loop the live candidate set offers and 0407''s did not (% tries): the live set is no wider than 0407''s', v_tries;
  end if;
  begin
    perform pg_temp.old_set_120(true);
    v_old := pg_temp.plan_120(v_route, v_dest);
    raise exception sqlstate 'BV120';
  exception when sqlstate 'BV120' then null;
  end;
  if (v_old->>'waiting')::int <> 1 or v_old->>'paused' is distinct from 'laid_up' or (v_old->>'buys')::int <> 0 then
    raise exception 'PROOF 120 FAIL: under 0407''s set she was not laid up with no BUY: %', v_old;
  end if;
  raise notice 'PASS: AS_WIDER — under 0407''s set: laid up (% loops priced); live: % with % BUY lines, % loops priced (% tries)',
    v_old->'candidates', v_new->>'loop', v_new->'buys', v_new->'candidates', v_tries;

  -- AS_GUARD: that harbour's purse at nothing too
  begin
    v_none := pg_temp.plan_120(v_route, null);
    raise exception sqlstate 'BV120';
  exception when sqlstate 'BV120' then null;
  end;
  if (v_none->>'waiting')::int <> 1 or v_none->>'paused' is distinct from 'laid_up' or (v_none->>'buys')::int <> 0 then
    raise exception 'PROOF 120 FAIL: with every purse at nothing she did not wait in port with no BUY: %', v_none;
  end if;
  raise notice 'PASS: AS_GUARD — every purse at nothing: she waits in port, no BUY (% loops priced)', v_none->'candidates';

  -- AS_REST: her lap closed now, at her first stop with nothing aboard; the lap-start door holds her for her rest
  begin
    insert into public.standing_route_laps (route_id, lap_no, started_at, closed_at)
    select v_route, coalesce(max(x.lap_no), 0) + 1, now() - interval '1 hour', now() from public.standing_route_laps x where x.route_id = v_route;
    update public.standing_routes set lap_id = null, stop_cursor = 0, paused_reason = null, hold_until = null, updated_at = now() - interval '1 hour' where id = v_route;
    perform cmd.run_standing_route(v_fleet, now());
    v_hold := (select sr.hold_until from public.standing_routes sr where sr.id = v_route);
    raise exception sqlstate 'BV120';
  exception when sqlstate 'BV120' then null;
  end;
  v_rest := extract(epoch from v_hold - now());
  if v_hold is null or v_rest > 150 or v_rest < 60 then
    raise exception 'PROOF 120 FAIL: her rest at home is % s (wanted 60 to 150)', round(v_rest);
  end if;
  raise notice 'PASS: AS_REST — her lap closed, she rests % s at home (route_rest_voyage_days %)', round(v_rest), public.wc_num('route_rest_voyage_days');

  -- AS_ASK: the waiting line's due rule, by the line itself
  begin
    update public.world_config set value = to_jsonb(10) where key = 'npc_replan_every_minutes';
    update public.world_config set value = to_jsonb(60) where key = 'npc_replan_within_minutes';
    update public.world_config set value = to_jsonb(100) where key = 'npc_ask_broke_under';
    update public.standing_routes set paused_reason = 'laid_up', updated_at = now() - interval '3 hours' where id = v_route;
    update public.players set ducats = 5000 where id = (select sr.player_id from public.standing_routes sr where sr.id = v_route);
    foreach v_n in array array[1, 2, 3, 4, 5] loop
      update public.npc_fleets set refused = v_n, asked_at = null where fleet_id = v_fleet;
      v_steps := v_steps || (select round(extract(epoch from q.due_at - q.asked_at) / 60)::text from public.npc_waiting_queue(now()) q where q.fleet_id = v_fleet) || ' ';
    end loop;
    update public.players set ducats = 99 where id = (select sr.player_id from public.standing_routes sr where sr.id = v_route);
    v_steps := v_steps || '/ broke ' || (select round(extract(epoch from q.due_at - q.asked_at) / 60)::text from public.npc_waiting_queue(now()) q where q.fleet_id = v_fleet);
    raise exception sqlstate 'BV120';
  exception when sqlstate 'BV120' then null;
  end;
  if v_steps is distinct from '10 20 30 30 30 / broke 50' then
    raise exception 'PROOF 120 FAIL: the due rule''s steps are "%", not "10 20 30 30 30 / broke 50"', v_steps;
  end if;
  raise notice 'PASS: AS_ASK — due % minutes after her last ask', v_steps;
end
$$;

-- ── CARGO SHIPS ──
do $$
declare
  v_nat  uuid := (select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT');
  v_cap  uuid;
  v_city uuid;
  v_idle int;
  v_w0   numeric;
  v_w1   numeric;
  v_r    jsonb;
  v_big  bigint;
  v_i    int;
  v_room bigint;
  v_r2   jsonb;
begin
  v_cap := public.realm_capital(v_nat);
  for v_i in 1 .. 4 loop
    perform public.tick_cargo_ships(now(), v_nat);
  end loop;
  -- every ship of the realm lies idle at her home, nothing aboard, port time over
  update public.voyages v set status = 'ABORTED' where v.status = 'SAILING' and v.fleet_id in (select c.fleet_id from public.cargo_ships c where c.nation_id = v_nat);
  update public.fleets f set status = 'DOCKED', port_id = c.home_port_id, lat = null, lon = null, ready_at = null
    from public.cargo_ships c where c.fleet_id = f.id and c.nation_id = v_nat;
  update public.cargo_ships c set out_load = null, circuit_id = null, leg = 0 where c.nation_id = v_nat;
  select count(*) into v_idle
    from public.cargo_ships_in_service c
   where c.nation_id = v_nat and c.ord <= public.convoy_ships_of(c.nation_id) and not exists (select 1 from public.cargo_ship_aboard(c.fleet_id))
     and exists (select 1 from public.cargo_circuit_legs l where l.circuit_id = public.cargo_circuit_of(c.nation_id, c.home_port_id));
  if v_idle < 6 then
    raise exception 'PROOF 120 FAIL: the scene needs six idle ships of Portugal on a circuit; it has %', v_idle;
  end if;
  select p.id into v_city from public.ports p where p.kind = 'HARBOUR' and p.id <> v_cap and public.city_capital(p.id) = v_cap order by p.code limit 1;
  update public.port_treasury t set ducats = 1000000000 where t.port_id = v_cap;
  update public.port_treasury t set ducats = 0 where t.port_id = v_city;
  v_w0 := (select sum(public.treasury_balance(t.port_id)) from public.port_treasury t) + public.funds_aboard();
  v_r := public.cargo_ships_load(jsonb_build_array(jsonb_build_object('port_id', v_city, 'cap', v_cap, 'target', 5 * public.wc_int('convoy_load_max'))));
  v_w1 := (select sum(public.treasury_balance(t.port_id)) from public.port_treasury t) + public.funds_aboard();
  select max(b.ducats) into v_big from public.convoy_cargo b join public.cargo_ships c on c.fleet_id = b.fleet_id where c.nation_id = v_nat and b.stage = 'LOADED';
  if (v_r->>'ships')::int <> 5 or (v_r->>'loaded')::bigint <> 5 * public.wc_int('convoy_load_max') or v_big > public.wc_int('convoy_load_max') or v_w1 <> v_w0 then
    raise exception 'PROOF 120 FAIL: one run for a city short by five loads: % (largest load %, money before %, after %)', v_r, v_big, v_w0, v_w1;
  end if;
  -- the home gives its room once a run: a capital with 2.5 M of room and a need of 5 M more loads its room and no more, in 1 M shares
  update public.port_treasury t set ducats = t.ducats - (public.cargo_load_room(v_cap, v_nat) - 2500000) where t.port_id = v_cap;   -- its room (its surplus) 2.5 M
  v_room := public.cargo_load_room(v_cap, v_nat);
  v_r2 := public.cargo_ships_load(jsonb_build_array(jsonb_build_object('port_id', v_city, 'cap', v_cap, 'target', 10 * public.wc_int('convoy_load_max'))));
  if v_room <= 0 or v_room >= 5 * public.wc_int('convoy_load_max') or (v_r2->>'loaded')::bigint <> v_room
     or (v_r2->>'ships')::int <> ceil(v_room::numeric / public.wc_int('convoy_load_max'))::int then
    raise exception 'PROOF 120 FAIL: with % of room the run loaded %', v_room, v_r2;
  end if;
  raise notice 'PASS: AS_CARGO — one run loaded % ships with % d. (the largest %), % idle before; the money unmoved; a home with % of room gave it once, on % ships',
    v_r->'ships', v_r->'loaded', v_big, v_idle, v_room, v_r2->'ships';
end
$$;

-- ── NAVY ──
do $$
declare
  v_t    timestamptz := now();
  v_nat  uuid := (select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT');
  v_cap  uuid;
  v_own  uuid;
  v_ord  int;
  n      uuid;
  v_s    text;
  t2     record;
  v_vo   public.voyages%rowtype;
  v_lie  numeric;
begin
  update public.world_config set value = 'true'::jsonb where key in ('navy_enabled', 'pirates_bite');
  delete from public.pirate_roster;
  if not public.navy_hunts_on() then
    raise exception 'PROOF 120 FAIL: the hunt cannot be lit in this world';
  end if;
  v_cap := public.realm_capital(v_nat);
  v_own := (select p.sea_id from public.ports p where p.id = v_cap);
  update public.port_treasury t set ducats = 50000000 where t.port_id = v_cap;   -- the cargo scene left the capital's purse near its reserve; it builds her
  -- the scene's ship is the realm's first: the rolls are struck (as proof 48 does), no pressure anywhere
  update public.players p set company_name = 'struck ' || substr(md5(gen_random_uuid()::text), 1, 12)
   where p.id in (select x.player_id from public.navy_ships x);
  delete from public.navy_ships x where true;
  delete from public.sea_pressure;
  v_ord := 1;
  insert into public.navy_realms (nation_id, ships, read_at) values (v_nat, 25, v_t) on conflict (nation_id) do update set ships = 25, read_at = v_t;
  n := public.navy_commission(v_nat, v_ord, v_cap, public.refit_yard(v_cap), v_cap, v_t);
  update public.ships s set crew = c.crew_required from public.ship_classes c where c.id = s.class_id and s.fleet_id = n;
  perform public.navy_plan_step(v_t, v_nat);
  perform public.navy_plan_step(v_t, v_nat);
  if not exists (select 1 from public.navy_patrol_legs l join public.navy_stations s on s.id = l.station_id where s.nation_id = v_nat and s.port_id = v_cap) then
    raise exception 'PROOF 120 FAIL: the capital''s station has no patrol in this world';
  end if;

  -- AS_NAVY_OWN: her own sea pressed hardest
  insert into public.sea_pressure (sea_id, value, updated_at) values (v_own, 400, v_t);
  if (select t.sea_id from public.navy_hunt_targets(v_cap, v_t) t limit 1) is distinct from v_own then
    raise exception 'PROOF 120 FAIL: her own sea is not the first target';
  end if;
  v_s := public.navy_ship_step(n, v_t);
  select * into v_vo from public.voyages v where v.fleet_id = n and v.status = 'SAILING';
  if v_s <> 'SAILED' or v_vo.id is null
     or (select x.mission || ':' || (x.patrol is not null)::text || ':' || (x.hunt_port is null and x.hunt_until is null)::text from public.navy_ships x where x.fleet_id = n) <> 'PATROL:true:true' then
    raise exception 'PROOF 120 FAIL: her own sea pressed, she did not sail her patrol: % %', v_s, (select to_jsonb(x) - 'fleet_id' - 'player_id' from public.navy_ships x where x.fleet_id = n);
  end if;
  raise notice 'PASS: AS_NAVY_OWN — her own sea the worst: % on her patrol to %, mission PATROL', v_s, (select p.code from public.ports p where p.id = v_vo.dest_port_id);

  -- AS_NAVY_LIE: another sea pressed hardest; back at her station, off her patrol
  update public.voyages v set status = 'ABORTED' where v.fleet_id = n and v.status = 'SAILING';
  update public.fleets f set status = 'DOCKED', port_id = v_cap, lat = null, lon = null, ready_at = null, version = f.version + 1 where f.id = n;
  update public.navy_ships x set patrol = null, leg = 0, mission = 'PATROL', hunt_port = null, hunt_until = null where x.fleet_id = n;
  delete from public.sea_pressure;
  select t.port_id, t.sea_id into t2 from public.navy_hunt_targets(v_cap, v_t) t
   where t.sea_id <> v_own and public.cargo_circuit_plan(v_nat, v_cap, t.port_id) #> '{legs,0}' is not null
   order by t.nm, t.port_id limit 1;
  if t2.sea_id is null then
    raise exception 'PROOF 120 FAIL: no other sea in reach of the capital with a course';
  end if;
  insert into public.sea_pressure (sea_id, value, updated_at) values (t2.sea_id, 400, v_t);
  v_s := public.navy_ship_step(n, v_t + interval '1 second');
  select * into v_vo from public.voyages v where v.fleet_id = n and v.status = 'SAILING';
  v_lie := extract(epoch from (select x.hunt_until from public.navy_ships x where x.fleet_id = n) - v_vo.eta);
  if v_s <> 'HUNT' or v_vo.id is null or v_lie is null or v_lie > 0.5 * 86400 / public.wc_num('time_compression') + 1 then
    raise exception 'PROOF 120 FAIL: bound for another sea her lie there is % s (wanted at most half a voyage-day, % s): %', round(v_lie), round(0.5 * 86400 / public.wc_num('time_compression')), v_s;
  end if;
  raise notice 'PASS: AS_NAVY_LIE — HUNT to %, she lies % s there after she arrives (half a voyage-day: % s)',
    (select p.code from public.ports p where p.id = v_vo.dest_port_id), round(v_lie), round(0.5 * 86400 / public.wc_num('time_compression'));
end
$$;
