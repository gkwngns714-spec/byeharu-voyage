-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 147 - PIRATES CRUISE THE SEA  (migration 0445; docs/dev-log/2026-11-16-pirates-at-sea.md; the owner, 2026-11-15: "pirates still in
--   port. too much. fix this please"; standing: "pirates' main goal is to attack other npcs, loot them")
--
--   Lit as prod is (the purses, the closed economy, the pirates, the refit rule, attacks; prod's clock, a day in 300 s), through the pirates' own
--   minute job (public.tick_pirates), the battles' (public.tick_battles) and the arrivals beat (public.tick_arrivals), rolled back with
--   proof.mjs's transaction. Roster fleets of Tortuga, built by the Brethren's own hand. EVERY MARKER BUT PC_KNOBS FAILS BEFORE 0445: a pirate
--   sailed one course to her haunt and lay there twelve hours, raiding from the quay.
--
-- @pass PC_KNOBS   the knobs are 0445's: a cruise of 5,000 nm in at most 24 lanes, 2 minutes in a harbour, home under half her hulls, 8 sailings a run, no raid from a harbour, 16 pirates asked a run
-- @pass PC_OUT     from her home the job sails her on ONE voyage of several stored lanes laid end to end (its miles the sum of public.npc_courses' own), pirate_cruise_nm long, ending at a haunt, in a sea; two pirates leave in the same run
-- @pass PC_STRIKE  under sail, beside a merchant, the job opens a RAID; it is fought where they met (she is held under sail, not in a harbour); it over, she sails on, the same voyage, later by the fight
-- @pass PC_QUAY    lying in a harbour beside a merchant she opens no raid (NOT_HUNTING); knob pirate_strike_from_port is the way back
-- @pass PC_PORT    at the harbour her cruise ends at she lies pirate_port_minutes, not hours; then the job sails her on the cruise back, as long, ending at her home
-- @pass PC_REFIT   hurt (her hulls under pirate_refit_below of their best) she sails the one course straight home in no sea; home, she is mended whole and cruises again
-- @pass PC_SHARE   an hour of the job and the beat at prod's clock, six pirates: at least 70 % of them are under sail, minute by minute on average
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

create function pg_temp.lie_147(p_fleet uuid, p_lat numeric, p_lon numeric) returns void language sql as $f$
  update public.voyages v set status = 'ABORTED' where v.fleet_id = p_fleet and v.status = 'SAILING';
  update public.fleets f set status = 'ANCHORED', port_id = null, lat = p_lat, lon = p_lon, busy_until = null, ready_at = null, version = f.version + 1 where f.id = p_fleet;
$f$;
create function pg_temp.dock_147(p_fleet uuid, p_port uuid) returns void language sql as $f$
  update public.voyages v set status = 'ABORTED' where v.fleet_id = p_fleet and v.status = 'SAILING';
  update public.fleets f set status = 'DOCKED', port_id = p_port, lat = null, lon = null, busy_until = null, ready_at = null, version = f.version + 1 where f.id = p_fleet;
$f$;

do $p$
declare
  t0      timestamptz := date_trunc('minute', now()) + interval '1 day';
  t       timestamptz;
  v_hub   uuid := (select p.id from public.ports p where p.code = 'TDC');
  v_fl    uuid[] := '{}';
  v_pf    uuid;
  v_p2    uuid;
  v_m     uuid;
  v_min   numeric := public.wc_num('pirate_cruise_nm');
  v_cap   int := public.wc_int('pirate_cruise_courses');
  v_port  numeric := public.wc_num('pirate_port_minutes');
  v_plan  record;
  v_back  record;
  v_v     public.voyages%rowtype;
  v_v2    public.voyages%rowtype;
  v_b     public.battles%rowtype;
  v_r     jsonb;
  v_s     text;
  v_lat   numeric;
  v_lon   numeric;
  v_lanes numeric;
  v_sum   numeric := 0;
  v_k     int := 0;
  v_low   numeric := 1;
  r       record;
  i       int;
begin
  -- ── THE SCENE ──
  perform public.clock_set(288, t0);   -- prod's clock: a day in 300 s
  update public.world_config set value = 'true'::jsonb
   where key in ('city_treasury_enabled', 'economy_closed', 'pirates_bite', 'npc_refits_enabled', 'attack_enabled') and value is distinct from 'true'::jsonb;
  update public.world_config set value = 'false'::jsonb where key in ('navy_enabled', 'pirates_trade', 'convoys_enabled') and value is distinct from 'false'::jsonb;
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 5000000, reserve = 0;
  update public.port_treasury t set ducats = 1900000000 where t.port_id = public.pirate_capital();
  update public.world_config set value = to_jsonb(0.5) where key = 'pirate_spend_day_pct';
  update public.world_config set value = to_jsonb(0) where key = 'pirate_wakes_per_run';
  if not public.pirates_on() or not public.attack_on() then
    raise exception 'PROOF 147 FAIL: the pirates or attacks could not be lit in this world';
  end if;

  -- ── PC_KNOBS ──
  if v_min <> 5000 or v_cap <> 24 or v_port <> 2 or public.wc_num('pirate_refit_below') <> 0.5 or public.wc_int('pirate_sails_per_run') <> 8
     or public.wc('pirate_strike_from_port') <> 'false'::jsonb or public.wc_int('pirate_strike_tries_per_run') <> 16 then
    raise exception 'PROOF 147 FAIL: the knobs are not 0445''s';
  end if;
  raise notice 'PASS: PC_KNOBS — a cruise of % nm in at most % lanes, % min in a harbour, home under % of her hulls, % sailings a run, % pirates asked a run',
    v_min, v_cap, v_port, public.wc_num('pirate_refit_below'), public.wc_int('pirate_sails_per_run'), public.wc_int('pirate_strike_tries_per_run');

  -- six roster fleets of Tortuga, manned, at their home; nobody else is at work, at sea or at anchor; the add and the pay have just run
  update public.pirate_ships set laid_up_at = t0 where laid_up_at is null;
  update public.pirate_clock set added_at = t0 + interval '1 day', paid_at = t0 + interval '1 day';
  for r in select q.ord from public.pirate_roster q where q.hub_port = v_hub order by q.ord limit 6 loop
    v_pf := public.pirate_commission_fleet(r.ord, public.refit_yard(v_hub), t0);
    if v_pf is null then
      raise exception 'PROOF 147 FAIL: roster fleet % was not built', r.ord;
    end if;
    v_fl := v_fl || v_pf;
  end loop;
  update public.ships s set crew = (select b.crew_max from public.ship_base(s.id) b) where s.fleet_id = any (v_fl);
  update public.voyages v set status = 'ABORTED' where v.status = 'SAILING';
  update public.fleets f set status = 'DOCKED', port_id = coalesce(f.port_id, v_hub), lat = null, lon = null, busy_until = null where f.status in ('SAILING', 'ANCHORED');
  v_pf := v_fl[1];
  v_p2 := v_fl[2];
  update public.pirate_ships x set laid_up_at = t0 where x.fleet_id = any (v_fl[3:6]);   -- the first two alone, until PC_SHARE

  -- ── PC_OUT ── the job sails both, each on one voyage of stored lanes laid end to end
  select * into v_plan from public.pirate_cruise_plan(v_pf, v_hub);
  v_r := public.tick_pirates(t0);
  select * into v_v from public.voyages o where o.fleet_id = v_pf and o.status = 'SAILING';
  -- the lanes of her voyage, by the harbours its plan passes: the miles are public.npc_courses' own, nothing drawn anew
  v_lanes := (select sum((e ->> 'nm')::numeric) from jsonb_array_elements(v_plan.segments) e);
  if (v_r #>> '{steps,SAILED}')::int is distinct from 2 or v_v.id is null or v_v.origin_port_id <> v_hub or v_v.dest_port_id is distinct from v_plan.port_id
     or v_plan.port_id = v_hub or v_plan.courses < 2 or v_plan.courses > v_cap or v_v.total_nm < v_min or abs(v_v.total_nm - v_plan.nm) > 1 or abs(v_lanes - v_plan.nm) > 0.01 * v_plan.nm
     or not exists (select 1 from public.npc_courses c where c.from_port = v_hub and c.nm < v_v.total_nm)
     or not exists (select 1 from public.pirate_ships x where x.fleet_id = v_pf and x.mission = 'CRUISE' and x.sea_id = v_plan.sea_id and x.sea_id is not null and x.haunt_port = v_plan.port_id)
     or (select count(*) from public.pirate_ships_cruising c where c.fleet_id in (v_pf, v_p2)) <> 2
     or (select f.status from public.fleets f where f.id = v_p2) <> 'SAILING'
     or v_v.eta - v_v.departed_at < interval '10 minutes' then
    raise exception 'PROOF 147 FAIL: the job did not sail both pirates on a long cruise of stored lanes: % / % nm in % lanes, to sail % nm in %', v_r, v_plan.nm, v_plan.courses,
      v_v.total_nm, v_v.eta - v_v.departed_at;
  end if;
  raise notice 'PASS: PC_OUT — one voyage of % stored lanes, % nm, % under sail, ending at a haunt (%); both pirates left in the same run: %', v_plan.courses, round(v_v.total_nm),
    v_v.eta - v_v.departed_at, (select p.code from public.ports p where p.id = v_plan.port_id), v_r -> 'steps';

  -- ── PC_STRIKE ── five minutes out, a company's merchant lies beside her: the job raids from the sea
  update public.pirate_ships x set laid_up_at = t0 where x.fleet_id = v_p2;   -- the first pirate alone
  perform pg_temp.dock_147(v_p2, v_hub);
  t := t0 + interval '5 minutes';
  select p.lat, p.lon into v_lat, v_lon from voyage.fleet_point(v_pf, t) p;
  select nf.fleet_id into v_m
    from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id join public.players pl on pl.id = f.player_id
   where pl.nation_id is distinct from public.pirate_nation() and exists (select 1 from public.ships s where s.fleet_id = nf.fleet_id and s.durability > 0)
   order by nf.fleet_id limit 1;
  update public.ships s set crew = 1 where s.fleet_id = v_m;   -- a weak prize: the pirate is not wrecked by it
  perform pg_temp.lie_147(v_m, v_lat, v_lon);
  v_r := public.tick_pirates(t);
  select b.* into v_b from public.battles b join public.battle_sides s on s.battle_id = b.id and s.fleet_id = v_pf and s.side = 'ATTACKER' and s.how = 'OPENED';
  if (v_r #>> '{struck,STRUCK}')::int is distinct from 1 or v_b.kind is distinct from 'RAID'
     or not exists (select 1 from public.battle_sides s where s.battle_id = v_b.id and s.fleet_id = v_m and s.side = 'DEFENDER')
     or not exists (select 1 from public.fleets f where f.id = v_pf and f.status = 'SAILING' and f.port_id is null and f.busy_until = v_b.resolves_at) then
    raise exception 'PROOF 147 FAIL: under sail beside a merchant she did not raid from the sea: % / %', v_r, to_jsonb(v_b) - 'sheet' - 'ticks';
  end if;
  perform public.tick_battles(v_b.resolves_at);
  select * into v_b from public.battles b where b.id = v_b.id;
  select * into v_v2 from public.voyages o where o.fleet_id = v_pf and o.status = 'SAILING';
  if v_b.status = 'FIGHTING' or v_v2.id is distinct from v_v.id or v_v2.eta <= v_v.eta
     or not exists (select 1 from public.fleets f where f.id = v_pf and f.status = 'SAILING' and f.busy_until is null) then
    raise exception 'PROOF 147 FAIL: the raid over (%), she did not sail on with her cruise: voyage % (was %), eta % (was %)', v_b.status, v_v2.id, v_v.id, v_v2.eta, v_v.eta;
  end if;
  raise notice 'PASS: PC_STRIKE — a RAID opened under sail (% s), % %; she sails on, the same voyage, % later', extract(epoch from v_b.resolves_at - v_b.started_at), v_b.status,
    v_b.result ->> 'outcome', v_v2.eta - v_v.eta;

  -- ── PC_QUAY ── lying in the harbour her cruise ends at, a merchant beside her, long past her rest and the merchant's peace: no raid
  t := t0 + interval '2 hours';
  perform pg_temp.dock_147(v_pf, v_plan.port_id);
  update public.ships s set durability = (select b.durability from public.ship_base(s.id) b), crew = (select b.crew_max from public.ship_base(s.id) b) where s.fleet_id = v_pf;
  select p.lat, p.lon into v_lat, v_lon from voyage.fleet_point(v_pf, t) p;
  select nf.fleet_id into v_m
    from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id join public.players pl on pl.id = f.player_id
   where pl.nation_id is distinct from public.pirate_nation() and nf.fleet_id <> v_m and exists (select 1 from public.ships s where s.fleet_id = nf.fleet_id and s.durability > 0)
   order by nf.fleet_id limit 1;
  perform pg_temp.lie_147(v_m, v_lat, v_lon);
  if public.raid_target(v_pf, t) is distinct from v_m or not exists (select 1 from public.pirate_ships_cruising c where c.fleet_id = v_pf) then
    raise exception 'PROOF 147 FAIL: the scene: the merchant beside the harbour is not in her reach';
  end if;
  v_s := public.pirate_strike(v_pf, t);
  update public.world_config set value = 'true'::jsonb where key = 'pirate_strike_from_port';
  if v_s <> 'NOT_HUNTING' or public.pirate_strike(v_pf, t) <> 'STRUCK' then
    raise exception 'PROOF 147 FAIL: in a harbour she answered % (not NOT_HUNTING), or the knob did not let her raid from it', v_s;
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'pirate_strike_from_port';
  select b.* into v_b from public.battles b join public.battle_sides s on s.battle_id = b.id and s.fleet_id = v_m and s.side = 'DEFENDER';
  perform public.tick_battles(v_b.resolves_at);
  raise notice 'PASS: PC_QUAY — in a harbour, a merchant in reach: NOT_HUNTING; with pirate_strike_from_port: STRUCK';

  -- ── PC_PORT ── she lies pirate_port_minutes, then the job sails her on the cruise back
  t := t0 + interval '3 hours';
  perform pg_temp.dock_147(v_pf, v_plan.port_id);
  perform pg_temp.dock_147(v_m, v_hub);
  update public.ships s set durability = (select b.durability from public.ship_base(s.id) b), crew = (select b.crew_max from public.ship_base(s.id) b) where s.fleet_id = v_pf;
  update public.pirate_ships x set haunt_since = null, wrecked_at = null where x.fleet_id = v_pf;
  if (select f.status from public.fleets f where f.id = v_pf) <> 'DOCKED' or public.npc_wrecked(v_pf) then
    raise exception 'PROOF 147 FAIL: the scene: she does not lie whole at her haunt';
  end if;
  v_r := public.tick_pirates(t);
  if (v_r #>> '{steps,HAUNT}')::int is distinct from 1 or (select x.haunt_since from public.pirate_ships x where x.fleet_id = v_pf) is distinct from t then
    raise exception 'PROOF 147 FAIL: come in from her cruise she did not lie: %', v_r;
  end if;
  v_r := public.tick_pirates(t + interval '1 minute');
  if (v_r #>> '{steps,HAUNT}')::int is distinct from 1 then
    raise exception 'PROOF 147 FAIL: a minute in, inside pirate_port_minutes, she did not lie: %', v_r;
  end if;
  select * into v_back from public.pirate_cruise_plan(v_pf, v_plan.port_id);
  v_r := public.tick_pirates(t + make_interval(secs => (v_port * 60)::double precision));
  select * into v_v from public.voyages o where o.fleet_id = v_pf and o.status = 'SAILING';
  if (v_r #>> '{steps,SAILED}')::int is distinct from 1 or v_v.origin_port_id is distinct from v_plan.port_id or v_v.dest_port_id is distinct from v_hub
     or v_v.total_nm < v_min or abs(v_v.total_nm - v_back.nm) > 1
     or not exists (select 1 from public.pirate_ships x where x.fleet_id = v_pf and x.mission = 'CRUISE' and x.sea_id is not null and x.haunt_port = v_hub) then
    raise exception 'PROOF 147 FAIL: after % minutes she did not sail the cruise back to her home: % (% nm planned, % to sail)', v_port, v_r, v_back.nm, v_v.total_nm;
  end if;
  raise notice 'PASS: PC_PORT — HAUNT, HAUNT, and after % minutes SAILED: the cruise back, % nm in % lanes, ending at her home, hunting (in a sea)', v_port, round(v_v.total_nm), v_back.courses;

  -- ── PC_REFIT ── hurt at her haunt: straight home, in no sea; home: mended, and out again
  t := t0 + interval '4 hours';
  perform pg_temp.dock_147(v_pf, v_plan.port_id);
  update public.pirate_ships x set sea_id = v_plan.sea_id, haunt_port = v_plan.port_id, haunt_since = t - interval '1 hour', mission = 'CRUISE' where x.fleet_id = v_pf;
  update public.ships s set durability = greatest(1, floor(0.3 * (select b.durability from public.ship_base(s.id) b))) where s.fleet_id = v_pf;
  if not public.pirate_hurt(v_pf) then
    raise exception 'PROOF 147 FAIL: at three tenths of her hulls she is not hurt';
  end if;
  v_r := public.tick_pirates(t);
  select * into v_v from public.voyages o where o.fleet_id = v_pf and o.status = 'SAILING';
  if (v_r #>> '{steps,SAILED}')::int is distinct from 1 or v_v.dest_port_id is distinct from v_hub
     or abs(v_v.total_nm - (select c.nm from public.npc_courses c where c.from_port = v_plan.port_id and c.to_port = v_hub)) > 1
     or not exists (select 1 from public.pirate_ships x where x.fleet_id = v_pf and x.mission = 'HOME' and x.sea_id is null)
     or exists (select 1 from public.pirate_ships_cruising c where c.fleet_id = v_pf) then
    raise exception 'PROOF 147 FAIL: hurt, she did not sail the one course straight home in no sea: % (% nm)', v_r, v_v.total_nm;
  end if;
  v_lanes := v_v.total_nm;
  perform pg_temp.dock_147(v_pf, v_hub);
  v_r := public.tick_pirates(t + interval '1 hour');
  select * into v_v from public.voyages o where o.fleet_id = v_pf and o.status = 'SAILING';
  if (v_r #>> '{steps,SAILED}')::int is distinct from 1 or public.pirate_hurt(v_pf) or v_v.total_nm < v_min
     or exists (select 1 from public.ships s where s.fleet_id = v_pf and s.durability <> (select b.durability from public.ship_base(s.id) b)) then
    raise exception 'PROOF 147 FAIL: home, she was not mended whole and sent out again: %', v_r;
  end if;
  raise notice 'PASS: PC_REFIT — hurt: one course straight home (% nm), in no sea; home: mended whole, and out again on a cruise of % nm', round(v_lanes), round(v_v.total_nm);

  -- ── PC_SHARE ── six pirates, an hour of the job and the beat (after twenty minutes to spread), prod's clock
  t := t0 + interval '6 hours';
  update public.pirate_ships x set laid_up_at = null where x.fleet_id = any (v_fl);
  for i in 1..6 loop
    perform pg_temp.dock_147(v_fl[i], v_hub);
  end loop;
  update public.pirate_ships x set mission = 'HOME', sea_id = null, haunt_port = null, haunt_since = null, last_port = v_hub, wrecked_at = null where x.fleet_id = any (v_fl);
  update public.ships s set durability = (select b.durability from public.ship_base(s.id) b), crew = (select b.crew_max from public.ship_base(s.id) b) where s.fleet_id = any (v_fl);
  update public.pirate_clock set added_at = t + interval '1 day', paid_at = t + interval '1 day';
  for i in 0..79 loop
    perform public.tick_arrivals(t + make_interval(mins => i));
    perform public.tick_pirates(t + make_interval(mins => i));
    if i >= 20 then
      v_k := v_k + 1;
      v_sum := v_sum + (select count(*) filter (where f.status = 'SAILING')::numeric / 6 from public.fleets f where f.id = any (v_fl));
      v_low := least(v_low, (select count(*) filter (where f.status = 'SAILING')::numeric / 6 from public.fleets f where f.id = any (v_fl)));
    end if;
  end loop;
  if v_sum / v_k < 0.70 or (select count(*) from public.voyages o where o.fleet_id = any (v_fl) and o.departed_at >= t) < 6 then
    raise exception 'PROOF 147 FAIL: over the hour % of the six pirates were under sail (at least 0.70 wanted); the lowest minute %', round(v_sum / v_k, 3), round(v_low, 3);
  end if;
  raise notice 'PASS: PC_SHARE — over an hour % of the six pirates were under sail (the lowest minute %); % voyages begun in 80 minutes', round(v_sum / v_k, 3), round(v_low, 3),
    (select count(*) from public.voyages o where o.fleet_id = any (v_fl) and o.departed_at >= t);
end
$p$;
