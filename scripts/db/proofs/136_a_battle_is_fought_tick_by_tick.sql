-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 136 - A BATTLE IS FOUGHT TICK BY TICK  (migration 0435; docs/design/tick-combat.md; the owner, 2026-11-15: "the round it takes for a
--   combat to happen i guess is 1 minute, i want the combat system resemble something like rs3" and "keep the total fight length modest, around
--   30-90 seconds")
--
--   Lit as prod is, through the pirates' minute job (public.tick_pirates) and the battles' (public.tick_battles), rolled back with proof.mjs's
--   transaction. Proof 133's scene: a hunting pirate at her haunt; a company's merchant 60 miles off. EVERY BUILT WORLD HAS ITS OWN DICE:
--   nothing here assumes who wins; what is proved is the shape, the clock, the rules each event keeps, and what the close does with it.
--
-- @pass TK_OPEN   the raid is run whole at its open: battles.ticks, its end (last tick + 2) within 75 s, the job due at the end, a window a round; both sides held to that end
-- @pass TK_LINE   the timeline keeps its rules: ticks in order, one ability a side per global cooldown and each on its cooldown, Fury 0..100, every hit's hull after, every run's chance within the raid's floor and cap (0450; proof 152 holds the formula), the end event its outcome
-- @pass TK_READ   world.battle_ticks serves the timeline, the clock, the circle and both sides to a signed-in player; nothing to no house or no battle
-- @pass TK_END    cmd.battle_end does nothing before the end; at the end it closes the raid (the timeline's result, raid_close's take, the fleets freed, her 5 minutes of peace); the read then serves the result
-- @pass TK_JOB    a raid nobody watches is closed by the minute job at its end, from the same result
-- @pass TK_KNOB   tick_fight_kinds [] and the next raid is fought round by round again (no timeline, 0357's clock)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

create function pg_temp.lie_136(p_fleet uuid, p_lat numeric, p_lon numeric) returns void language sql as $f$
  update public.voyages v set status = 'ABORTED' where v.fleet_id = p_fleet and v.status = 'SAILING';
  update public.fleets f set status = 'ANCHORED', port_id = null, lat = p_lat, lon = p_lon, busy_until = null, ready_at = null, version = f.version + 1 where f.id = p_fleet;
$f$;

do $p$
declare
  t0      timestamptz := date_trunc('minute', now()) + interval '1 day';
  v_uid   uuid := '00000000-0435-4000-8000-0000000000c1';
  v_hub   uuid := (select p.id from public.ports p where p.code = 'TDC');
  v_pf    uuid;
  v_m     uuid;
  v_m2    uuid;
  v_hp    uuid;
  v_lat   numeric;
  v_lon   numeric;
  v_r     jsonb;
  v_b     public.battles%rowtype;
  v_tl    jsonb;
  v_x     jsonb;
  e       jsonb;
  v_lo    numeric := public.wc_num('raid_flee_floor');
  v_hi    numeric := public.wc_num('raid_flee_max');
  v_ms    int := public.wc_int('tick_ms');
  v_last  int;
  v_gcd   int[];
  v_rdy   jsonb;
  v_hull  jsonb;
  v_pf_chance numeric;
  v_ab    jsonb := public.wc('tick_abilities');
  v_n     int := 0;
  r       record;
  v_span  interval;
begin
  -- ── THE SCENE (proof 133's) ──
  update public.world_config set value = 'true'::jsonb
   where key in ('city_treasury_enabled', 'economy_closed', 'pirates_bite', 'npc_refits_enabled', 'attack_enabled') and value is distinct from 'true'::jsonb;
  update public.world_config set value = 'false'::jsonb where key in ('navy_enabled', 'pirates_trade', 'convoys_enabled') and value is distinct from 'false'::jsonb;
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 5000000, reserve = 0;
  update public.port_treasury t set ducats = 900000000 where t.port_id = public.pirate_capital();
  update public.pirate_ships set laid_up_at = t0 where laid_up_at is null;
  update public.world_config set value = to_jsonb(0) where key = 'pirate_wakes_per_run';
  update public.pirate_clock set added_at = t0 + interval '1 hour', paid_at = t0 + interval '1 hour';
  select q.ord into r from public.pirate_roster q where q.hub_port = v_hub and q.ord % 1000 = 6;
  v_pf := public.pirate_commission_fleet(r.ord, public.refit_yard(v_hub), t0);
  update public.ships s set crew = (select b.crew_max from public.ship_base(s.id) b) where s.fleet_id = v_pf;
  select h.port_id, h.sea_id into r from public.pirate_haunt_of(v_hub, (select x.ord from public.pirate_ships x where x.fleet_id = v_pf)) h;
  update public.fleets f set port_id = r.port_id, status = 'DOCKED', ready_at = null where f.id = v_pf;
  update public.pirate_ships x set sea_id = r.sea_id, mission = 'CRUISE', haunt_port = r.port_id, haunt_since = t0 where x.fleet_id = v_pf;
  select p.lat, p.lon into v_lat, v_lon from voyage.fleet_point(v_pf, t0) p;
  update public.voyages v set status = 'ABORTED' where v.status = 'SAILING';
  update public.fleets f set status = 'DOCKED', port_id = coalesce(f.port_id, v_hub), lat = null, lon = null, busy_until = null where f.status in ('SAILING', 'ANCHORED');
  select nf.fleet_id into v_m
    from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id join public.players pl on pl.id = f.player_id
   where pl.nation_id is distinct from public.pirate_nation() and exists (select 1 from public.ships s where s.fleet_id = nf.fleet_id and s.durability > 0)
   order by nf.fleet_id limit 1;
  perform pg_temp.lie_136(v_m, v_lat + 1, v_lon);   -- sixty miles north
  v_hp := public.new_house(v_uid, 'Casa Tique 136', 'PRT', 'LIS', 'Tique 136', 'galion', 'Tique 136', null, false);   -- a reader (her ship stays in port)

  -- ── TK_OPEN ──
  v_r := public.tick_pirates(t0);
  select b.* into v_b from public.battles b join public.battle_sides s on s.battle_id = b.id and s.fleet_id = v_m and s.side = 'DEFENDER';
  if v_b.id is null or v_b.kind <> 'RAID' then
    raise exception 'PROOF 136 FAIL: the job did not raid the merchant: %', v_r;
  end if;
  v_tl := v_b.ticks;
  if v_tl is null or (v_tl ->> 'v')::int <> 1 or (v_tl ->> 'k')::int <> 0 or (v_tl ->> 'ms')::int <> v_ms then
    raise exception 'PROOF 136 FAIL: the raid has no timeline of version 1 run once: %', left(coalesce(v_tl::text, 'null'), 300);
  end if;
  v_span := v_b.resolves_at - v_b.started_at;
  if v_span <> make_interval(secs => ((v_tl ->> 'n')::int + 2) * v_ms / 1000.0) or v_span > interval '75 seconds' or v_b.next_round_at <> v_b.resolves_at
     or v_b.round_seconds <> (v_tl ->> 'w')::int * v_ms / 1000 then
    raise exception 'PROOF 136 FAIL: the clock is not the timeline''s: span %, n %, next %, round %', v_span, v_tl ->> 'n', v_b.next_round_at, v_b.round_seconds;
  end if;
  if (select f.status from public.fleets f where f.id = v_pf) <> 'IN_BATTLE' or (select f.status from public.fleets f where f.id = v_m) <> 'IN_BATTLE'
     or (select f.busy_until from public.fleets f where f.id = v_pf) <> v_b.resolves_at or (select f.busy_until from public.fleets f where f.id = v_m) <> v_b.resolves_at then
    raise exception 'PROOF 136 FAIL: a side is not held to the timeline''s end';
  end if;
  if exists (select 1 from public.battle_rounds br where br.battle_id = v_b.id) or public.battle_advance(v_b.id, t0 + interval '1 hour') <> 0 then
    raise exception 'PROOF 136 FAIL: a tick battle logged rounds';
  end if;
  raise notice 'PASS: TK_OPEN — % in % ticks, ends % after the open (was 600 s), both sides held to it', v_tl ->> 'out', v_tl ->> 'n', v_span;

  -- ── TK_LINE ──
  v_last := 0;
  v_gcd := array[-99, -99];
  v_rdy := '{}'::jsonb;
  v_hull := jsonb_build_object('0', (select jsonb_agg(s -> 'h') from jsonb_array_elements(v_tl -> 'a') s), '1', (select jsonb_agg(s -> 'h') from jsonb_array_elements(v_tl -> 'b') s));
  v_pf_chance := (v_tl #>> '{rc,a,0,1}')::numeric;   -- 0450: the chance she would run on at the open, as the timeline serves it
  for e in select x from jsonb_array_elements(v_tl -> 'e') x loop
    v_n := v_n + 1;
    if (e ->> 0)::int < v_last then
      raise exception 'PROOF 136 FAIL: event % goes back in time: %', v_n, e;
    end if;
    v_last := (e ->> 0)::int;
    if e ->> 2 = 'U' then
      if v_last < v_gcd[(e ->> 1)::int + 1] + (v_tl ->> 'gcd')::int then
        raise exception 'PROOF 136 FAIL: side % used two abilities inside the global cooldown: %', e ->> 1, e;
      end if;
      if v_last < coalesce((v_rdy ->> ((e ->> 1) || (e ->> 3)))::int, 0) then
        raise exception 'PROOF 136 FAIL: % used before its cooldown ended: %', e ->> 3, e;
      end if;
      if (e ->> 4)::numeric not between 0 and 100 then
        raise exception 'PROOF 136 FAIL: Fury out of its bar: %', e;
      end if;
      v_gcd[(e ->> 1)::int + 1] := v_last;
      v_rdy := v_rdy || jsonb_build_object((e ->> 1) || (e ->> 3), v_last + coalesce((v_ab -> (e ->> 3) ->> 'cd')::int, 0));
    elsif e ->> 2 in ('A', 'BS', 'CH', 'RK', 'GR') then
      -- her hull after = her hull before less the hit (to the tenth)
      if abs((v_hull -> (1 - (e ->> 1)::int)::text ->> (e ->> 4)::int)::numeric - least((e ->> 5)::numeric, (v_hull -> (1 - (e ->> 1)::int)::text ->> (e ->> 4)::int)::numeric) - (e ->> 7)::numeric) > 0.15 then
        raise exception 'PROOF 136 FAIL: a hit''s hull after is not the hull before less the hit: % (before %)', e, v_hull -> (1 - (e ->> 1)::int)::text ->> (e ->> 4)::int;
      end if;
      v_hull := jsonb_set(v_hull, array[(1 - (e ->> 1)::int)::text, (e ->> 4)], to_jsonb((e ->> 7)::numeric));
    elsif e ->> 2 = 'P' then
      v_hull := jsonb_set(v_hull, array[(e ->> 1), (e ->> 3)], to_jsonb((e ->> 5)::numeric));
    -- 0450: a run's chance is no longer one figure a fight (her hull, her failed attempts and the levels move it: proof 152 holds the formula);
    -- here: every roll within the raid's floor and cap
    elsif e ->> 2 = 'X' and (e ->> 1)::int = 0 and ((e ->> 3)::numeric < round(v_lo * 100) or (e ->> 3)::numeric > round(v_hi * 100)) then
      raise exception 'PROOF 136 FAIL: her run rolled on % %%, outside the raid''s floor % and cap %', e ->> 3, v_lo, v_hi;
    end if;
  end loop;
  if (v_tl -> 'e' -> -1 ->> 2) <> 'E' or (v_tl -> 'e' -> -1 ->> 3) <> (v_tl ->> 'out') or (v_tl -> 'r' ->> 'outcome') <> (v_tl ->> 'out')
     or (v_tl -> 'e' -> -1 ->> 0)::int <> (v_tl ->> 'n')::int then
    raise exception 'PROOF 136 FAIL: the timeline does not end in its outcome';
  end if;
  if (v_tl -> 'ai' ->> 'a') <> public.battle_stance_at(v_b.id, v_m, 'infinity') then
    raise exception 'PROOF 136 FAIL: the side set upon was not fought by her opening stance: % / %', v_tl -> 'ai', public.battle_stance_at(v_b.id, v_m, 'infinity');
  end if;
  raise notice 'PASS: TK_LINE — % events in tick order; abilities on their cooldowns and the global one, Fury within its bar, every hit''s hull after, her runs within the raid''s floor and cap (% %% at the open), AI %',
    v_n, v_pf_chance, v_tl -> 'ai';

  -- ── TK_READ ──
  perform cmd.assume_identity(v_uid);
  v_x := world.battle_ticks(v_b.id);
  if not coalesce((v_x ->> 'on')::boolean, false) or (v_x -> 'ticks')::text <> v_tl::text or v_x ->> 'status' <> 'FIGHTING' or v_x -> 'result' <> 'null'::jsonb
     or jsonb_array_length(v_x -> 'sides') <> 2 or (v_x ->> 'reach_nm')::numeric <> public.wc_num('battle_join_nm') or v_x -> 'mine' <> 'null'::jsonb
     or (v_x ->> 'started_at')::timestamptz <> v_b.started_at then
    raise exception 'PROOF 136 FAIL: the screen''s read is not the battle: %', left(v_x::text, 400);
  end if;
  if (world.battle_ticks(gen_random_uuid()) ->> 'on')::boolean then
    raise exception 'PROOF 136 FAIL: a battle that is not served as on';
  end if;
  if not ((world.fights() -> 'fights' -> 0) ? 'reach_nm') then
    raise exception 'PROOF 136 FAIL: the ring does not serve its circle: %', world.fights() -> 'fights' -> 0;
  end if;
  raise notice 'PASS: TK_READ — the timeline, clock, circle (% nm) and both sides served to a signed-in reader', v_x ->> 'reach_nm';

  -- ── TK_END ── (the door reads the wall clock: the battle is put on it, its span kept)
  -- the door reads clock_timestamp(), later than this transaction's now(): the battle is put on that clock, its end ahead by its own span (>= 2 ticks)
  update public.battles b set started_at = clock_timestamp(), resolves_at = clock_timestamp() + v_span, next_round_at = clock_timestamp() + v_span where b.id = v_b.id;
  update public.fleets f set busy_until = (select b.resolves_at from public.battles b where b.id = v_b.id) where f.id in (v_pf, v_m);
  v_x := cmd.battle_end(v_b.id);
  if not coalesce((v_x ->> 'ok')::boolean, false) or v_x ->> 'status' <> 'FIGHTING' then
    raise exception 'PROOF 136 FAIL: the door closed a battle before its end: %', v_x;
  end if;
  update public.battles b set started_at = clock_timestamp() - interval '5 seconds' - v_span, resolves_at = clock_timestamp() - interval '5 seconds', next_round_at = clock_timestamp() - interval '5 seconds' where b.id = v_b.id;
  update public.fleets f set busy_until = (select b.resolves_at from public.battles b where b.id = v_b.id) where f.id in (v_pf, v_m);
  v_x := cmd.battle_end(v_b.id);
  select * into v_b from public.battles b where b.id = v_b.id;
  if not coalesce((v_x ->> 'ok')::boolean, false) or v_b.status = 'FIGHTING' or v_x ->> 'status' <> v_b.status then
    raise exception 'PROOF 136 FAIL: the door did not close the battle at its end: %', v_x;
  end if;
  if v_b.result ->> 'engine' <> 'tick' or v_b.result ->> 'outcome' <> v_tl ->> 'out' or not (v_b.result ? 'raid')
     or (v_b.result -> 'rounds')::text <> (v_tl -> 'r' -> 'rounds')::text then
    raise exception 'PROOF 136 FAIL: the close did not keep the timeline''s result: %', left(v_b.result::text, 300);
  end if;
  if (select f.busy_until from public.fleets f where f.id = v_m) is not null or (select f.busy_until from public.fleets f where f.id = v_pf) is not null then
    raise exception 'PROOF 136 FAIL: a side is still held after the close';
  end if;
  if public.fleet_peace_until(v_m) <> v_b.resolves_at + make_interval(mins => public.wc_int('peace_after_flee_minutes')) then
    raise exception 'PROOF 136 FAIL: her peace runs to %, not % after the end %', public.fleet_peace_until(v_m), public.wc_int('peace_after_flee_minutes'), v_b.resolves_at;
  end if;
  v_x := world.battle_ticks(v_b.id);
  if v_x -> 'result' ->> 'outcome' <> v_tl ->> 'out' or not (v_x -> 'result' ? 'taken') or (v_x -> 'result' ->> 'taken')::bigint is distinct from (v_b.result #>> '{raid,taken}')::bigint then
    raise exception 'PROOF 136 FAIL: the read after the close is not the result: %', v_x -> 'result';
  end if;
  v_x := cmd.battle_end(v_b.id);   -- again: nothing more
  if v_x ->> 'status' <> v_b.status or (select b.result::text from public.battles b where b.id = v_b.id) <> v_b.result::text then
    raise exception 'PROOF 136 FAIL: a second close moved the battle';
  end if;
  if cmd.battle_end(gen_random_uuid()) ->> 'error_code' <> 'E_NO_BATTLE' then
    raise exception 'PROOF 136 FAIL: the door does not refuse a battle that is not';
  end if;
  raise notice 'PASS: TK_END — not before the end; at it % (taken %), the timeline''s result kept, both freed, her peace to %', v_b.result ->> 'outcome', v_b.result #>> '{raid,taken}', public.fleet_peace_until(v_m);

  -- ── TK_JOB ── (the next merchant; the pirate mended, her rest passed)
  update public.ships s set durability = (select b.durability from public.ship_base(s.id) b), crew = (select b.crew_max from public.ship_base(s.id) b) where s.fleet_id = v_pf;
  update public.fleets f set status = 'DOCKED', busy_until = null, port_id = (select x.haunt_port from public.pirate_ships x where x.fleet_id = v_pf) where f.id = v_pf;
  select nf.fleet_id into v_m2
    from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id join public.players pl on pl.id = f.player_id
   where nf.fleet_id <> v_m and pl.nation_id is distinct from public.pirate_nation() and exists (select 1 from public.ships s where s.fleet_id = nf.fleet_id and s.durability > 0)
   order by nf.fleet_id limit 1;
  perform pg_temp.lie_136(v_m2, v_lat - 1, v_lon);
  v_r := to_jsonb(public.battle_open('RAID', v_pf, v_m2, t0 + interval '10 minutes'));   -- the one door a pirate's strike opens (public.pirate_strike)
  select b.* into v_b from public.battles b join public.battle_sides s on s.battle_id = b.id and s.fleet_id = v_m2 and s.side = 'DEFENDER';
  if v_b.id is null or v_b.ticks is null then
    raise exception 'PROOF 136 FAIL: the second raid was not fought tick by tick: %', v_r;
  end if;
  perform public.tick_battles(v_b.resolves_at - interval '1 second');
  if (select b.status from public.battles b where b.id = v_b.id) <> 'FIGHTING' then
    raise exception 'PROOF 136 FAIL: the job closed a raid before its end';
  end if;
  perform public.tick_battles(v_b.resolves_at);
  if (select b.status from public.battles b where b.id = v_b.id) = 'FIGHTING' or (select b.result ->> 'outcome' from public.battles b where b.id = v_b.id) <> v_b.ticks ->> 'out' then
    raise exception 'PROOF 136 FAIL: the job did not close the raid at its end from its timeline';
  end if;
  raise notice 'PASS: TK_JOB — the minute job closed the second raid at its end: %', v_b.ticks ->> 'out';

  -- ── TK_KNOB ──
  update public.world_config set value = '[]'::jsonb where key = 'tick_fight_kinds';
  update public.ships s set durability = (select b.durability from public.ship_base(s.id) b), crew = (select b.crew_max from public.ship_base(s.id) b) where s.fleet_id = v_pf;
  update public.fleets f set status = 'DOCKED', busy_until = null, port_id = (select x.haunt_port from public.pirate_ships x where x.fleet_id = v_pf) where f.id = v_pf;
  perform pg_temp.lie_136(v_m2, v_lat - 1, v_lon);
  update public.ships s set durability = greatest(s.durability, 1) where s.fleet_id = v_m2;
  v_r := to_jsonb(public.battle_open('RAID', v_pf, v_m2, t0 + interval '20 minutes'));
  select b.* into v_b from public.battles b join public.battle_sides s on s.battle_id = b.id and s.side = 'ATTACKER' and s.fleet_id = v_pf
   where b.started_at = t0 + interval '20 minutes';
  if v_b.id is null or v_b.ticks is not null or v_b.round_seconds <> floor(public.wc_num('battle_seconds') / (jsonb_array_length(public.wc('fight_ranges')) + 1)) then
    raise exception 'PROOF 136 FAIL: with the knob [] the raid is not round by round: %, ticks %, round %', v_r, v_b.ticks is not null, v_b.round_seconds;
  end if;
  raise notice 'PASS: TK_KNOB — tick_fight_kinds [] and the next raid is round by round (% s a round)', v_b.round_seconds;
end
$p$;
