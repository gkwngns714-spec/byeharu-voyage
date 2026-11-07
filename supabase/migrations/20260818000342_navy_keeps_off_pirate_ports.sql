-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0342 — THE NAVY KEEPS OFF PIRATE PORTS: a navy ship never sails for a harbour the pirates hold, and her upkeep never reaches their purse. DARK
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- Owner rows 284, 285 (the pirates and the navy); the W19 review of 2026-11-07 (docs/dev-log/2026-11-07-the-navy-hunts.md, "Decided by default"): a navy ship lying at a harbour the pirates hold has her hourly upkeep
-- (NAVY_PAY, 0331: capital to the harbour she lies at or last called at) paid INTO THE PIRATES' PURSE, which is their hoard (0339 public.pirate_hoard = the purses of every city they hold), and their quay mans her
-- (public.fleet_hands at her departure). W19 closed that for the hunt's targets alone (public.navy_hunt_targets) and left the rest for a slice of its own: this one. The navy is DARK on prod (navy_enabled false) and
-- must be safe to light while the pirates are lit (pirates_bite true since 2026-11-07 17:55 UTC).
--
-- THE ONE RULE, in one reader: public.navy_harbour_ok(port) = the pirates do not hold it (public.pirate_power of public.port_nation; a harbour nobody holds is open). Every place a navy ship's harbour is CHOSEN reads it:
--   a patrol's stops (public.navy_patrol_build, 0331)            a call's harbour (public.harbour_nearest, 0333, the call's one reader of "where")      a reinforcement's harbour, read again as she sails (public.navy_reinforce, 0333)
--   an escort's stop (public.navy_escort_step, 0333)              the station a ship is laid at or woken for (public.navy_add, 0335)                      her home, as she leaves port (public.navy_ship_step, 0340's body)
--   the next stop of a patrol already written (public.navy_ship_step)   a hunt's harbour (public.navy_hunt_targets, 0340: its own copy of the test replaced by the reader, so the rule has one copy)
-- AND THE MONEY (case d: a harbour that BECOMES pirate-held under her, which the daily influence count can do to any crown city but a home): public.navy_pay pays the slice of a ship lying at, or last called at, a harbour
--   the pirates hold AS IF SHE LAY AT THE CAPITAL: it stays in the capital's purse, she counts as paid (on duty), and her step takes her to a crown harbour. Nothing is minted; the realm's other cities receive what they
--   did; the hoard receives nothing. Her hands: public.navy_sail takes none from a quay the pirates hold (she sails as she is). Her stores are free and her dock fee 0 anywhere, as before: no other flow exists.
-- WHEN A HARBOUR FALLS TO THE PIRATES UNDER THE NAVY:
--   * her STATION: on duty her home is the plan's station for her ord (public.navy_stations_build re-plans a realm after a flag change, one a run); until then, and off duty (her last station), her home is her
--     realm's CAPITAL instead; with no crown harbour at all she stays where she lies (IDLE, no crash). A station the pirates hold is never laid at or woken for (public.navy_add waits for the plan).
--   * a PATROL STOP already written: she ends her patrol at the stop before it (the crown's mend waits for her next finished patrol), and the station's patrol is DROPPED (public.navy_patrol_drop: its legs go, legs_at
--     null) so public.navy_plan_step writes it again, without the stop, one station a run; a sister ship out on that patrol ends hers at her next port, as off her line (0331's path), and sails home. The first stop fallen:
--     she lies at her station (IDLE) until the patrol is written again.
--   * a CALL's harbour: she is freed and never gets there ('infinity' on the sheet), as 0333 treats a harbour no course reaches. A ship lying AT a harbour that falls: she waits out the battle (CALLED), paid at the capital.
--   * a HUNT's harbour while she lies there: she lies out her hours (navy_hunt_hours, 6) paid at the capital, then sails home; a hunt never picks one.
-- NOT CHANGED, said plainly: public.refit_yard (0322) names the yard a capital pays for a hull (BUILD_NAVY) and a station pays for a wreck (REFIT): a yard of the same crown first, else the nearest, WHOEVER HOLDS IT.
--   Crown gold reaches a yard the pirates hold only when a realm has no yard but its capital's and the nearest foreign yard is a city they won; it is the one rule every merchant's and cargo ship's refit follows, so it is a
--   slice of its own if the owner wants crowns to buy from no pirate yard. Pirate ships, pirate merchants, the hunt's fight, every switch and knob: untouched. No new knob: a rule with no number needs none.
--
-- DARK IS BYTE-IDENTICAL: with navy_enabled false no body below runs (public.navy_call returns before it reads a harbour; the patrol, the add and the pay run lit only; a step, a sail, an escort and a reinforcement need a
--   navy ship, and prod has none). public.navy_hunt_targets answers the same rows (the same test, through the reader). Parity is proved, not argued: scripts/ops/harness/navy-off-pirate-ports/dark-scene.sql beside the
--   navy, navy-comes and the-navy-hunts scenes, before and after this file, every line equal.
--
-- THE RE-CUTS (hunks sliced from the LIVE bodies, read on the world at head 0341; each occurs exactly once and reverses to its pre-image; ACL, volatility, definer and config unmoved; these supersede the same lines of
-- 0331, 0333, 0335 and 0340):
--   public.navy_patrol_build (1):   a stop is never a harbour the pirates hold.
--   public.harbour_nearest (1):     the nearest OPEN harbour: the pirates' are passed over, read from the nearest outward (fenced with offset 0, so the holder is asked of the nearest few, not of every harbour).
--   public.navy_reinforce (1):      a called harbour that fell since the call: freed, 'infinity', as with no course.
--   public.navy_escort_step (1):    the ward is the richest cargo ship bound for a harbour the pirates do not hold (fenced the same way: read from the richest down).
--   public.navy_ship_step (3):      the next patrol leg (drop and end), her home (the capital, or IDLE), the first leg at her station (drop and IDLE).
--   public.navy_pay (1):            the slice of a ship at a harbour they hold stays at the capital.
--   public.navy_add (1):            no ship is laid at or woken for a station they hold.
--   public.navy_sail (1):           no hands from their quay.
--   public.navy_hunt_targets (1):   the reader, in place of 0340's own copy of the test, asked AFTER the reach is read once and joined (fenced with offset 0): the same rows, and a station's read falls from about 300 ms to a few
--                                   (with the test on the join the planner looped voyage.reach_from once a harbour, re-reading navy_reach_nm for every row; measured in scripts/ops/harness/navy-off-pirate-ports/cost-0342.mjs).
-- NEW: public.navy_harbour_ok(uuid) STABLE, public.navy_patrol_drop(bigint). No table, no column, no knob, no word, no job, no entry point.
--
-- SELF-ASSERT: the catalog and stable reads only: hunks once and reversing; ACL, volatility and config unmoved; no other function, knob or job; the switch off; no row written; the reader false at the pirate homes and true
--   at every crown capital and at a harbour nobody holds; the call's reader answers no pirate harbour for the sea off Port Royal. THIS FILE RUNS NO GAME STEP, in every environment (docs/OPS_HEALTH.md section 4).
--   THE LIVE PATHS ARE PROVED IN CI: proof 49, scripts/db/proofs/49_navy_keeps_off_pirate_ports.sql. Mutation controls: scripts/ops/harness/navy-off-pirate-ports/proof-0342.mjs (local).
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 45 s, lock_timeout 5 s first. Self-assert fails above 45 s. No scan of a big table (ports, port_allegiance, great_powers, pg_proc, world_config, navy_ships).
-- ROLLBACK (forward, owner only): navy_enabled false is 0331's rollback, and it holds. To remove: a NEW migration swapping each hunk's old and new (every OLD text is in this file) and dropping the two functions.
-- VERSION: 0342 - prod head 0341 (read 2026-11-08).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0   timestamptz := clock_timestamp();
  v_h    record;
  v_def  text;
  v_pre  text;
  v_n    int;
  v_por  public.ports%rowtype;
  v_free uuid;
  v_near uuid;
  v_fn_before    text;
  v_cfg_before   text;
  v_meta_before  text;
  v_cron_before  text;
  v_cron_after   text;
  c_new_fns constant text[] := array['public.navy_harbour_ok(uuid)', 'public.navy_patrol_drop(bigint)'];
  c_hunked constant text[] := array[
    'public.navy_patrol_build(bigint,timestamp with time zone)', 'public.harbour_nearest(double precision,double precision)', 'public.navy_reinforce(uuid,uuid,timestamp with time zone)',
    'public.navy_escort_step(uuid,uuid,boolean,timestamp with time zone)', 'public.navy_ship_step(uuid,timestamp with time zone)', 'public.navy_pay(timestamp with time zone,uuid)',
    'public.navy_add(timestamp with time zone,uuid)', 'public.navy_sail(uuid,uuid,jsonb,uuid,bigint,integer,timestamp with time zone)', 'public.navy_hunt_targets(uuid,timestamp with time zone)'];
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('public.navy_harbour_ok(uuid)') is not null or to_regprocedure('public.navy_patrol_drop(bigint)') is not null then
    raise exception '0342 refuses: something of it is already in this world';
  end if;
  if to_regprocedure('public.navy_patrol_build(bigint,timestamp with time zone)') is null or to_regprocedure('public.navy_reinforce(uuid,uuid,timestamp with time zone)') is null
     or to_regprocedure('public.navy_escort_step(uuid,uuid,boolean,timestamp with time zone)') is null or to_regprocedure('public.harbour_nearest(double precision,double precision)') is null then
    raise exception '0342 refuses: 0331 / 0333 (the navy, its patrol, its call and its escort) are not in this world';
  end if;
  if to_regprocedure('public.capital_draw(uuid,bigint,boolean)') is null then
    raise exception '0342 refuses: 0335 (the realm pays for its navy) is not in this world';
  end if;
  if to_regprocedure('public.pirate_power(uuid)') is null or to_regprocedure('public.port_nation(uuid)') is null then
    raise exception '0342 refuses: 0338 (the pirates, the 11th power) is not in this world';
  end if;
  if to_regprocedure('public.navy_hunt_targets(uuid,timestamp with time zone)') is null or to_regprocedure('public.navy_hunt_step(uuid,uuid,uuid,boolean,timestamp with time zone)') is null then
    raise exception '0342 refuses: 0340 (the navy hunts) is not in this world';
  end if;

  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked) x));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before
    from public.world_config c;
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
    into v_meta_before
    from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked) x));
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.command || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_cron_before;
  end if;

  -- ── 1. THE NEW FUNCTIONS ──
  execute $f$
create function public.navy_harbour_ok(p_port uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0342: THE one reader of "a navy ship may use this harbour": the pirates do not hold it (public.pirate_power of its holder, public.port_nation; a harbour nobody holds is open). Every chooser of a navy ship's harbour
  -- reads it (a patrol's stops, a call's and a reinforcement's harbour, an escort's stop, a hunt's harbour, the station she is laid at, her home), public.navy_pay pays no slice into a harbour it refuses (their purse is
  -- the hoard, 0339), and public.navy_sail takes no hands from its quay.
  select not public.pirate_power(public.port_nation(p_port))
$$
  $f$;

  execute $f$
create function public.navy_patrol_drop(p_station bigint)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  -- 0342: a station's patrol is forgotten, to be written again by public.navy_patrol_build (through public.navy_plan_step, one station a run) without the stop that fell to the pirates. A ship out on it ends her patrol at
  -- her next port, as off her line (public.navy_ship_step), and sails home. A retired station is not asked for a new one: it goes with its last ship.
  delete from public.navy_patrol_legs l where l.station_id = p_station;
  update public.navy_stations s set legs_at = null where s.id = p_station and s.retired_at is null;
$$
  $f$;

  revoke all on function public.navy_harbour_ok(uuid) from public, anon, authenticated;
  revoke all on function public.navy_patrol_drop(bigint) from public, anon, authenticated;

  -- ── 2. THE HUNKS (each occurs exactly once in the live body, and reverses) ──
  create temp table hunks_0342 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0342 values
  ('public.navy_patrol_build(bigint,timestamp with time zone)', 1,
$h$               where p.kind = 'HARBOUR' and not p.is_ice_closed and r.port_id <> s.port_id and r.nm <= public.wc_num('navy_reach_nm')
               order by coalesce(public.port_nation(r.port_id) = s.nation_id, false) desc, r.nm, r.code
$h$,
$h$               where p.kind = 'HARBOUR' and not p.is_ice_closed and r.port_id <> s.port_id and r.nm <= public.wc_num('navy_reach_nm')
                 and public.navy_harbour_ok(r.port_id)   -- 0342: never a stop the pirates hold
               order by coalesce(public.port_nation(r.port_id) = s.nation_id, false) desc, r.nm, r.code
$h$),
  ('public.harbour_nearest(double precision,double precision)', 1,
$h$  select p.id
    from public.ports p join public.sea_reaches r on r.port_id = p.id
   where p.kind = 'HARBOUR' and not p.is_ice_closed
   order by voyage.gc_distance_nm(p_lat, p_lon, p.lat, p.lon), p.code
   limit 1
$h$,
$h$  select x.id
    from (select p.id
            from public.ports p join public.sea_reaches r on r.port_id = p.id
           where p.kind = 'HARBOUR' and not p.is_ice_closed
           order by voyage.gc_distance_nm(p_lat, p_lon, p.lat, p.lon), p.code
          offset 0) x   -- 0342: fenced, so the holder is asked from the nearest outward and the first open harbour ends the read
   where public.navy_harbour_ok(x.id)   -- 0342: never a harbour the pirates hold
   limit 1
$h$),
  ('public.navy_reinforce(uuid,uuid,timestamp with time zone)', 1,
$h$  v_leg := public.cargo_circuit_plan(n.nation_id, p_port, n.called_to) #> '{legs,0}';
  if v_leg is null then
$h$,
$h$  v_leg := public.cargo_circuit_plan(n.nation_id, p_port, n.called_to) #> '{legs,0}';
  if v_leg is null or not public.navy_harbour_ok(n.called_to) then   -- 0342: the harbour fell to the pirates since the call: she never gets there, as with no course
$h$),
  ('public.navy_escort_step(uuid,uuid,boolean,timestamp with time zone)', 1,
$h$    select c.fleet_id, v.dest_port_id into v_ward, v_to
      from public.cargo_ships_in_service c
      join public.voyages v on v.fleet_id = c.fleet_id and v.status = 'SAILING' and v.dest_port_id is not null
     cross join lateral public.cargo_ship_aboard(c.fleet_id) a
     where c.nation_id = n.nation_id
     order by a.aboard desc, c.fleet_id
     limit 1;
$h$,
$h$    select x.fleet_id, x.dest_port_id into v_ward, v_to
      from (select c.fleet_id, v.dest_port_id
              from public.cargo_ships_in_service c
              join public.voyages v on v.fleet_id = c.fleet_id and v.status = 'SAILING' and v.dest_port_id is not null
             cross join lateral public.cargo_ship_aboard(c.fleet_id) a
             where c.nation_id = n.nation_id
             order by a.aboard desc, c.fleet_id
            offset 0) x   -- 0342: fenced, so the holder is asked from the richest down and the first open harbour ends the read
     where public.navy_harbour_ok(x.dest_port_id)   -- 0342: never a stop the pirates hold: a cargo ship bound for one sails unescorted
     limit 1;
$h$),
  ('public.navy_ship_step(uuid,timestamp with time zone)', 1,
$h$      if l.station_id is not null then
        return public.navy_sail(p_fleet, f.port_id, l.segments, l.to_port, n.patrol, n.leg + 1, p_now);
      end if;
      perform public.fleet_mend(p_fleet);   -- her patrol is done, at her station: the crown mends her free, as a cargo ship's lap
$h$,
$h$      if l.station_id is not null and public.navy_harbour_ok(l.to_port) then
        return public.navy_sail(p_fleet, f.port_id, l.segments, l.to_port, n.patrol, n.leg + 1, p_now);
      end if;
      if l.station_id is not null then
        perform public.navy_patrol_drop(n.patrol);   -- 0342: the next stop fell to the pirates: her patrol ends here, and the station's is written again without it (public.navy_plan_step)
      else
        perform public.fleet_mend(p_fleet);   -- her patrol is done, at her station: the crown mends her free, as a cargo ship's lap
      end if;
$h$),
  ('public.navy_ship_step(uuid,timestamp with time zone)', 2,
$h$  v_home := case when v_duty then coalesce(public.navy_station_of(n.nation_id, n.ord), n.station_port) else n.station_port end;
$h$,
$h$  v_home := case when v_duty then coalesce(public.navy_station_of(n.nation_id, n.ord), n.station_port) else n.station_port end;
  if not public.navy_harbour_ok(v_home) then   -- 0342: her home fell to the pirates (the plan moves her station one realm a run; off duty she keeps her last): her realm's capital is her home, never a harbour they hold
    v_home := public.realm_capital(n.nation_id);
    if v_home is null or not public.navy_harbour_ok(v_home) then
      return 'IDLE';   -- no crown harbour to go to: she stays where she lies
    end if;
  end if;
$h$),
  ('public.navy_ship_step(uuid,timestamp with time zone)', 3,
$h$  select * into l from public.navy_patrol_legs x where x.station_id = v_st and x.ord = 1;
  if l.station_id is null then
    return 'IDLE';   -- her patrol is not written yet, or nothing is in reach
  end if;
$h$,
$h$  select * into l from public.navy_patrol_legs x where x.station_id = v_st and x.ord = 1;
  if l.station_id is not null and not public.navy_harbour_ok(l.to_port) then
    perform public.navy_patrol_drop(v_st);   -- 0342: the first stop fell to the pirates: the patrol is written again without it (public.navy_plan_step); she lies at her station till then
    return 'IDLE';
  end if;
  if l.station_id is null then
    return 'IDLE';   -- her patrol is not written yet, or nothing is in reach
  end if;
$h$),
  ('public.navy_pay(timestamp with time zone,uuid)', 1,
$h$    select n.fleet_id, row_number() over (order by n.ord) as k, coalesce(f.port_id, n.last_port) as to_port
      from public.navy_ships_in_service n join public.fleets f on f.id = n.fleet_id
$h$,
$h$    select n.fleet_id, row_number() over (order by n.ord) as k,
           case when public.navy_harbour_ok(h.port) then h.port else v_cap end as to_port   -- 0342: lying at a harbour the pirates hold (it fell to them under her), her slice stays at the capital, as a ship at the capital's: nothing reaches the hoard, and she is paid
      from public.navy_ships_in_service n join public.fleets f on f.id = n.fleet_id
     cross join lateral (select coalesce(f.port_id, n.last_port) as port) h
$h$),
  ('public.navy_add(timestamp with time zone,uuid)', 1,
$h$    continue when v_cap is null or v_st is null or not public.capital_can_draw(v_cap, v_need);
$h$,
$h$    continue when v_cap is null or v_st is null or not public.navy_harbour_ok(v_st) or not public.capital_can_draw(v_cap, v_need);   -- 0342: no ship is laid at or woken for a station the pirates hold (the plan moves it off, one realm a run)
$h$),
  ('public.navy_sail(uuid,uuid,jsonb,uuid,bigint,integer,timestamp with time zone)', 1,
$h$  perform public.fleet_hands(p_fleet, p_port);
  perform public.fleet_stores(p_fleet, public.wc_num('navy_store_days'));
$h$,
$h$  if public.navy_harbour_ok(p_port) then   -- 0342: no hands from a quay the pirates hold (the harbour fell to them under her): she sails as she is
    perform public.fleet_hands(p_fleet, p_port);
  end if;
  perform public.fleet_stores(p_fleet, public.wc_num('navy_store_days'));
$h$),
  ('public.navy_hunt_targets(uuid,timestamp with time zone)', 1,
$h$            from (select p.sea_id, voyage.sea_danger(p.sea_id, p_now) as danger, r.port_id, r.nm, r.code
                    from voyage.reach_from(p_station) r
                    join public.ports p on p.id = r.port_id
                   where p.kind = 'HARBOUR' and not p.is_ice_closed and r.port_id <> p_station and r.nm <= public.wc_num('navy_reach_nm')
                     and not public.pirate_power(public.port_nation(p.id))
$h$,
$h$            from (select q.sea_id, voyage.sea_danger(q.sea_id, p_now) as danger, q.port_id, q.nm, q.code
                    from (select p.sea_id, r.port_id, r.nm, r.code
                            from voyage.reach_from(p_station) r
                            join public.ports p on p.id = r.port_id
                           where p.kind = 'HARBOUR' and not p.is_ice_closed and r.port_id <> p_station and r.nm <= public.wc_num('navy_reach_nm')
                          offset 0) q   -- 0342: fenced: the reach is read once and joined, then each harbour's holder is asked. With the test on the join the planner looped the reach once a harbour, re-reading navy_reach_nm for every row (0340 paid about 300 ms a read)
                   where public.navy_harbour_ok(q.port_id)   -- 0342: through the one reader
$h$);

  -- every hunk is checked against its live body BEFORE it is applied: once, and the new body reverses to the pre-image
  for v_h in select h.fn from hunks_0342 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    declare
      x record;
    begin
      for x in select * from hunks_0342 h where h.fn = v_h.fn order by h.ord loop
        v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
        if v_n <> 1 then
          raise exception '0342 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
        end if;
        v_def := replace(v_def, x.old, x.new);
      end loop;
      execute v_def;
      v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
      for x in select * from hunks_0342 h where h.fn = v_h.fn order by h.ord desc loop
        v_n := (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new);
        if v_n <> 1 then
          raise exception '0342 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
        end if;
        v_def := replace(v_def, x.new, x.old);
      end loop;
      if v_def <> v_pre then
        raise exception '0342 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
      end if;
    end;
  end loop;

  -- ── 3. THE SELF-ASSERT: the catalog and stable reads. No game step, no row. ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked || c_new_fns) x))) <> v_fn_before then
    raise exception '0342 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) from public.world_config c) <> v_cfg_before then
    raise exception '0342 self-assert FAIL: a world_config row moved (this file adds no knob)';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked) x))) <> v_meta_before then
    raise exception '0342 self-assert FAIL: the ACL, volatility, definer or config of a hunked function moved';
  end if;
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.command || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_cron_after;
    if v_cron_after is distinct from v_cron_before then
      raise exception '0342 self-assert FAIL: a cron job moved';
    end if;
  end if;
  if (select c.value from public.world_config c where c.key = 'navy_enabled') <> 'false'::jsonb then
    raise exception '0342 self-assert FAIL: the navy switch is not off';
  end if;
  if exists (select 1 from public.navy_ships) or exists (select 1 from public.navy_patrol_legs) then
    raise exception '0342 self-assert FAIL: a row was written dark';
  end if;
  if (select string_agg(p.provolatile::text, '' order by p.oid::regprocedure::text) from pg_proc p
       where p.oid = any (array['public.navy_harbour_ok(uuid)'::regprocedure, 'public.navy_patrol_drop(bigint)'::regprocedure]::oid[])) <> 'sv'
     or (select bool_and(p.prosecdef) from pg_proc p where p.oid = any (array['public.navy_harbour_ok(uuid)'::regprocedure, 'public.navy_patrol_drop(bigint)'::regprocedure]::oid[])) is not true then
    raise exception '0342 self-assert FAIL: the reader is not stable, the drop not volatile, or one is not definer';
  end if;
  if exists (select 1 from unnest(c_new_fns) f where has_function_privilege('anon', f::regprocedure, 'execute') or has_function_privilege('authenticated', f::regprocedure, 'execute')) then
    raise exception '0342 self-assert FAIL: a new function can be called from a client';
  end if;
  -- the reader: false at every harbour the pirates hold (their four homes at least), true at every crown capital, true at a harbour nobody holds (where one exists), true for no harbour at all
  if (select count(*) from public.port_allegiance a join public.great_powers g on g.nation_id = a.nation_id join public.ports p on p.id = a.port_id where g.pirate and p.kind = 'HARBOUR') < 4
     or exists (select 1 from public.port_allegiance a join public.great_powers g on g.nation_id = a.nation_id where g.pirate and public.navy_harbour_ok(a.port_id))
     or exists (select 1 from public.great_powers g where not g.pirate and not public.navy_harbour_ok(public.realm_capital(g.nation_id)))
     or not public.navy_harbour_ok(null) then
    raise exception '0342 self-assert FAIL: the reader does not refuse exactly the harbours the pirates hold';
  end if;
  select p.id into v_free from public.ports p where p.kind = 'HARBOUR' and public.port_nation(p.id) is null order by p.code limit 1;
  if v_free is not null and not public.navy_harbour_ok(v_free) then
    raise exception '0342 self-assert FAIL: a harbour nobody holds is refused';
  end if;
  if (select count(*) from public.ports p where p.kind = 'HARBOUR' and not public.navy_harbour_ok(p.id))
     <> (select count(*) from public.port_allegiance a join public.great_powers g on g.nation_id = a.nation_id join public.ports p on p.id = a.port_id where g.pirate and p.kind = 'HARBOUR') then
    raise exception '0342 self-assert FAIL: the harbours refused are not exactly the harbours the pirates hold';
  end if;
  -- the call's reader: the sea off Port Royal (a pirate home in every world since 0338) sends a ship to the nearest harbour that is not theirs; the Tagus still answers a harbour (0333)
  select p.* into v_por from public.ports p where p.code = 'POR';
  if v_por.id is null or public.navy_harbour_ok(v_por.id) then
    raise exception '0342 self-assert FAIL: Port Royal is not a harbour the pirates hold';
  end if;
  v_near := public.harbour_nearest(v_por.lat::double precision, v_por.lon::double precision);
  if v_near is null or v_near = v_por.id or not public.navy_harbour_ok(v_near) or not exists (select 1 from public.ports p where p.id = v_near and p.kind = 'HARBOUR' and not p.is_ice_closed) then
    raise exception '0342 self-assert FAIL: the call off Port Royal answers % (wanted the nearest open harbour the pirates do not hold)', (select p.code from public.ports p where p.id = v_near);
  end if;
  if not exists (select 1 from public.ports p where p.id = public.harbour_nearest(38.7, -9.1) and p.kind = 'HARBOUR') then
    raise exception '0342 self-assert FAIL: no harbour is nearest the mouth of the Tagus';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0342 self-assert FAIL: the self-assert took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0342 self-assert ok: THE NAVY KEEPS OFF PIRATE PORTS, dark behind navy_enabled. % hunks once each and reversing over % bodies; no other function, knob or job; no row written; the reader refuses % harbours (the pirates'' holdings); off Port Royal a call goes to %; no game step ran (proof 49 runs them in CI). % ms.',
    (select count(*) from hunks_0342), (select count(distinct h.fn) from hunks_0342 h),
    (select count(*) from public.ports p where p.kind = 'HARBOUR' and not public.navy_harbour_ok(p.id)), (select p.code from public.ports p where p.id = v_near),
    round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0342;
end
$m$;
