-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 140 - A PLAYER ACTS IN A FIGHT  (migration 0439; docs/design/tick-combat.md 7, 9.2; docs/dev-log/2026-11-15-battle-act.md; the owner,
--   2026-11-15: "i want the combat system resemble something like rs3"; no PvP, ever)
--
--   A RAID on a player's ship, written with a fixed sheet (hulls so large and guns so light that the fight runs to the boarding at tick 120 in
--   every world, whatever its dice; the AI's rotation does not read the dice), driven through the door cmd.battle_act as the player. The
--   server's clock is set by moving the battle's start (pg_temp.at_tick_140). Rolled back with proof.mjs's transaction.
--
-- @pass BA_REFUSE   every refusal: E_BAD_CODE, E_NO_BATTLE, E_NOT_YOUR_BATTLE (not hers; hers not in it), E_PAST_TICK, E_BATTLE_OVER (past the end; closed), E_BAD_CODE (Run by a ship that joined); nothing re-run
-- @pass BA_TAIL     a valid act asked one tick after her commander's last ability lands at the global cooldown; the timeline is re-run (k + 1): every event before its tick the same, the tail from it changed
-- @pass BA_RATE     a second act of the same fleet at once is E_TOO_SOON; three ticks on the cap is lifted
-- @pass BA_COOLDOWN an ability inside its cooldown in the current timeline is E_COOLDOWN ("Ready n / cd")
-- @pass BA_FURY     Rake with Fury under 50 is E_NO_FURY ("Fury n / 50"); Patch at the tick her bar first holds 50 is taken and spends it
-- @pass BA_RUN      Run: her guns fall silent and she rolls at its end with the raid's chance (within raid_flee_floor..raid_flee_max: 3-45 % since 0450)
-- @pass BA_PAY      Pay by the ship set upon: the fight ends at its tick in a RANSOM (paid), the past the same, the end moved to it
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

-- the server's tick now is p_tick (for 300 ms): the battle began p_tick ticks ago; its end follows its timeline
create function pg_temp.at_tick_140(p_battle uuid, p_tick int) returns void language sql as $f$
  update public.battles b set started_at = clock_timestamp() - make_interval(secs => (p_tick * 600 + 300) / 1000.0),
                              resolves_at = clock_timestamp() - make_interval(secs => (p_tick * 600 + 300) / 1000.0) + make_interval(secs => ((b.ticks ->> 'n')::int + 2) * 0.6)
   where b.id = p_battle;
$f$;

-- the events of a timeline before a tick, as one text
create function pg_temp.before_140(p_tl jsonb, p_t int) returns text language sql as $f$
  select coalesce(jsonb_agg(e order by o), '[]'::jsonb)::text from jsonb_array_elements(p_tl -> 'e') with ordinality q(e, o) where (e ->> 0)::int < p_t;
$f$;
create function pg_temp.from_140(p_tl jsonb, p_t int) returns text language sql as $f$
  select coalesce(jsonb_agg(e order by o), '[]'::jsonb)::text from jsonb_array_elements(p_tl -> 'e') with ordinality q(e, o) where (e ->> 0)::int >= p_t;
$f$;

do $p$
declare
  v_uid   uuid := '00000000-0439-4000-8000-0000000001a1';
  v_uid2  uuid := '00000000-0439-4000-8000-0000000001a2';
  v_np    uuid;
  v_h     uuid;
  v_g     uuid;
  v_m     uuid;
  v_bat   uuid;
  v_fake  uuid;
  v_ha    jsonb;
  v_hb    jsonb;
  v_r     jsonb;
  v_old   jsonb;
  v_new   jsonb;
  v_k     int;
  v_ns    int;
  v_t     int;
  v_tu    int;
  v_trk   int;
  v_fury  numeric;
  v_x     jsonb;
  v_codes text;
  v_end   timestamptz;
begin
  update public.world_config set value = '["RAID", "ATTACK"]'::jsonb where key = 'tick_fight_kinds';
  -- ── THE SCENE: her ship set upon (side a) by a company's ship (side b); a second player's fleet, outside it ──
  v_np := public.new_house(v_uid, 'Casa Acto 140', 'PRT', 'LIS', 'Acto 140', 'galion', 'Acto 140', null, false);
  select f.id into v_h from public.fleets f where f.player_id = v_np;
  v_np := public.new_house(v_uid2, 'Casa Otra 140', 'PRT', 'LIS', 'Otra 140', 'galion', 'Otra 140', null, false);
  select f.id into v_g from public.fleets f where f.player_id = v_np;
  select nf.fleet_id into v_m from public.npc_fleets nf order by nf.fleet_id limit 1;
  v_ha := jsonb_build_array(jsonb_build_object('id', '00000000-0439-4000-8000-0000000001b1', 'name', 'Acto 140', 'fleet', v_h, 'tier', 2, 'hull', 100000, 'maxd', 100000,
            'crew', 40, 'attack', 6, 'accuracy', 50, 'reach', 20, 'armour', 0, 'sighting', 0, 'boarder_pct', 0));
  v_hb := jsonb_build_array(jsonb_build_object('id', '00000000-0439-4000-8000-0000000001b2', 'name', 'Raider 140', 'fleet', v_m, 'tier', 2, 'hull', 100000, 'maxd', 100000,
            'crew', 60, 'attack', 6, 'accuracy', 50, 'reach', 20, 'armour', 0, 'sighting', 10, 'boarder_pct', 0));
  insert into public.battles (kind, site, started_at, resolves_at, status, sheet, round_seconds, rounds_done, next_round_at)
  values ('RAID', '{"lat": 38.5, "lon": -9.8}'::jsonb, clock_timestamp(), clock_timestamp() + interval '80 seconds', 'FIGHTING',
          jsonb_build_object('a', v_ha, 'b', v_hb, 'a_flee', 0.05), 12, 0, clock_timestamp() + interval '80 seconds')
  returning id into v_bat;
  insert into public.battle_sides (battle_id, fleet_id, side, joined_at, arrives_at, how)
  values (v_bat, v_h, 'DEFENDER', clock_timestamp(), clock_timestamp(), 'OPENED'), (v_bat, v_m, 'ATTACKER', clock_timestamp(), clock_timestamp(), 'OPENED');
  v_old := public.tick_battle_run(v_bat);
  if (v_old ->> 'n')::int <> 120 then
    raise exception 'PROOF 140 FAIL: the fixed sheet did not run to the boarding: n %, %', v_old ->> 'n', v_old ->> 'out';
  end if;
  v_k := (v_old ->> 'k')::int;
  v_ns := (select count(*) from public.battle_sides s where s.battle_id = v_bat);
  perform pg_temp.at_tick_140(v_bat, 10);

  -- ── BA_REFUSE ──
  perform cmd.assume_identity(v_uid);
  v_r := cmd.battle_act(v_bat, v_h, 'XX', 12);
  if v_r ->> 'error_code' is distinct from 'E_BAD_CODE' then raise exception 'PROOF 140 FAIL: a bad code: %', v_r; end if;
  v_r := cmd.battle_act(gen_random_uuid(), v_h, 'BR', 12);
  if v_r ->> 'error_code' is distinct from 'E_NO_BATTLE' then raise exception 'PROOF 140 FAIL: no battle: %', v_r; end if;
  v_r := cmd.battle_act(v_bat, v_m, 'BR', 12);
  if v_r ->> 'error_code' is distinct from 'E_NOT_YOUR_BATTLE' then raise exception 'PROOF 140 FAIL: the raider''s fleet obeyed her: %', v_r; end if;
  v_r := cmd.battle_act(v_bat, v_h, 'BR', 5);
  if v_r ->> 'error_code' is distinct from 'E_PAST_TICK' then raise exception 'PROOF 140 FAIL: an act in the past: %', v_r; end if;
  v_codes := 'E_PAST_TICK "' || (v_r ->> 'error_message') || '"';
  v_r := cmd.battle_act(v_bat, v_h, 'BR', 9999);
  if v_r ->> 'error_code' is distinct from 'E_BATTLE_OVER' then raise exception 'PROOF 140 FAIL: an act past the end: %', v_r; end if;
  perform cmd.assume_identity(v_uid2);
  v_r := cmd.battle_act(v_bat, v_g, 'BR', 12);
  if v_r ->> 'error_code' is distinct from 'E_NOT_YOUR_BATTLE' then raise exception 'PROOF 140 FAIL: a fleet not in the battle acted: %', v_r; end if;
  -- a ship that joined may not order her side to run (and a closed battle takes no act)
  insert into public.battle_sides (battle_id, fleet_id, side, joined_at, arrives_at, how) values (v_bat, v_g, 'DEFENDER', clock_timestamp(), clock_timestamp(), 'JOINED');
  v_r := cmd.battle_act(v_bat, v_g, 'RN', 12);
  if v_r ->> 'error_code' is distinct from 'E_BAD_CODE' then raise exception 'PROOF 140 FAIL: a joiner ordered the run: %', v_r; end if;
  delete from public.battle_sides s where s.battle_id = v_bat and s.fleet_id = v_g;
  perform cmd.assume_identity(v_uid);
  insert into public.battles (kind, site, started_at, resolves_at, status, sheet, ticks)
  values ('RAID', '{"lat": 38.5, "lon": -9.8}'::jsonb, clock_timestamp() - interval '2 minutes', clock_timestamp() - interval '1 minute', 'RESOLVED', jsonb_build_object('a', v_ha, 'b', v_hb), v_old)
  returning id into v_fake;
  insert into public.battle_sides (battle_id, fleet_id, side, joined_at, arrives_at, how) values (v_fake, v_h, 'DEFENDER', clock_timestamp(), clock_timestamp(), 'OPENED');
  v_r := cmd.battle_act(v_fake, v_h, 'BR', 12);
  if v_r ->> 'error_code' is distinct from 'E_BATTLE_OVER' then raise exception 'PROOF 140 FAIL: an act in a closed battle: %', v_r; end if;
  delete from public.battle_sides s where s.battle_id = v_fake;
  delete from public.battles b where b.id = v_fake;
  if (select (b.ticks ->> 'k')::int from public.battles b where b.id = v_bat) <> v_k or (select b.sheet ? 'acts' from public.battles b where b.id = v_bat) then
    raise exception 'PROOF 140 FAIL: a refused act was written or re-ran the timeline';
  end if;
  raise notice 'PASS: BA_REFUSE — E_BAD_CODE, E_NO_BATTLE, E_NOT_YOUR_BATTLE x2, %, E_BATTLE_OVER x2, E_BAD_CODE (a joiner''s Run); k still %', v_codes, v_k;

  -- ── BA_FURY (the refusal): Rake at tick 12, her bar empty (her guns are unready in the first window: she was seen first) ──
  v_r := cmd.battle_act(v_bat, v_h, 'RK', 12);
  if v_r ->> 'error_code' is distinct from 'E_NO_FURY' or v_r ->> 'error_message' not like 'Fury % / 50' then
    raise exception 'PROOF 140 FAIL: Rake without the Fury: %', v_r;
  end if;
  v_codes := v_r ->> 'error_message';

  -- ── BA_TAIL: her commander's first ability at v_tu; Brace asked at v_tu + 1 lands at v_tu + gcd ──
  select min((e ->> 0)::int) into v_tu from jsonb_array_elements(v_old -> 'e') e where e ->> 2 = 'U' and e ->> 1 = '0';
  if v_tu is null then raise exception 'PROOF 140 FAIL: her commander never acted in the AI''s timeline'; end if;
  perform pg_temp.at_tick_140(v_bat, v_tu);
  v_r := cmd.battle_act(v_bat, v_h, 'BR', v_tu + 1);
  if not coalesce((v_r ->> 'ok')::boolean, false) then raise exception 'PROOF 140 FAIL: a valid Brace was refused: %', v_r; end if;
  v_t := (v_r ->> 'tick')::int;
  select b.ticks into v_new from public.battles b where b.id = v_bat;
  if v_t <> v_tu + (v_old ->> 'gcd')::int or (v_r ->> 'k')::int <> v_k + 1 or (v_new ->> 'k')::int <> v_k + 1
     or (v_r -> 'ticks')::text <> v_new::text then
    raise exception 'PROOF 140 FAIL: the act did not land at the global cooldown (% <> % + gcd) or the timeline is not k + 1: %', v_t, v_tu, v_r - 'ticks';
  end if;
  if pg_temp.before_140(v_old, v_t) <> pg_temp.before_140(v_new, v_t) then
    raise exception 'PROOF 140 FAIL: the act at tick % changed the fight before it', v_t;
  end if;
  if pg_temp.from_140(v_old, v_t) = pg_temp.from_140(v_new, v_t)
     or not exists (select 1 from jsonb_array_elements(v_new -> 'e') e where (e ->> 0)::int = v_t and e ->> 1 = '0' and e ->> 2 = 'U' and e ->> 3 = 'BR') then
    raise exception 'PROOF 140 FAIL: the tail from tick % did not change, or her Brace is not in it', v_t;
  end if;
  if not exists (select 1 from public.battles b, jsonb_array_elements(b.sheet -> 'acts') a
                  where b.id = v_bat and (a ->> 't')::int = v_t and a ->> 's' = '0' and a ->> 'code' = 'BR' and a ->> 'fleet' = v_h::text) then
    raise exception 'PROOF 140 FAIL: the act is not on sheet.acts';
  end if;
  raise notice 'PASS: BA_TAIL — asked % (her last ability at %), landed %, k % -> %; % events before it the same, the tail changed (% -> % events)',
    v_tu + 1, v_tu, v_t, v_k, v_new ->> 'k', (select count(*) from jsonb_array_elements(v_new -> 'e') e where (e ->> 0)::int < v_t),
    jsonb_array_length(v_old -> 'e'), jsonb_array_length(v_new -> 'e');

  -- ── BA_RATE, then BA_COOLDOWN ──
  v_r := cmd.battle_act(v_bat, v_h, 'BS', v_t + 30);
  if v_r ->> 'error_code' is distinct from 'E_TOO_SOON' then raise exception 'PROOF 140 FAIL: a second act at once: %', v_r - 'ticks'; end if;
  perform pg_temp.at_tick_140(v_bat, v_tu + 3);
  v_r := cmd.battle_act(v_bat, v_h, 'BR', v_t + 5);
  if v_r ->> 'error_code' = 'E_TOO_SOON' then raise exception 'PROOF 140 FAIL: three ticks on, the cap still holds: %', v_r - 'ticks'; end if;
  raise notice 'PASS: BA_RATE — at once: E_TOO_SOON; three ticks on: %', v_r ->> 'error_code';
  if v_r ->> 'error_code' is distinct from 'E_COOLDOWN' or v_r ->> 'error_message' not like 'Ready % / 40' then
    raise exception 'PROOF 140 FAIL: Brace again inside its cooldown: %', v_r - 'ticks';
  end if;
  raise notice 'PASS: BA_COOLDOWN — Brace at % again: E_COOLDOWN "%"', v_t + 5, v_r ->> 'error_message';

  -- ── BA_FURY (taken): her bar first holds 50 at her AI's Rake; Patch there instead ──
  v_old := v_new;
  select (e ->> 0)::int into v_trk from jsonb_array_elements(v_old -> 'e') with ordinality q(e, o) where e ->> 2 = 'U' and e ->> 1 = '0' and e ->> 3 = 'RK' order by o limit 1;
  if v_trk is null then raise exception 'PROOF 140 FAIL: her bar never reached 50 in the AI''s timeline'; end if;
  select (e ->> 4)::numeric into v_fury from jsonb_array_elements(v_old -> 'e') with ordinality q(e, o)
   where e ->> 2 = 'U' and e ->> 1 = '0' and (e ->> 0)::int < v_trk order by o desc limit 1;
  perform pg_temp.at_tick_140(v_bat, v_trk - 2);
  v_r := cmd.battle_act(v_bat, v_h, 'PT', v_trk);
  if not coalesce((v_r ->> 'ok')::boolean, false) or (v_r ->> 'tick')::int <> v_trk then
    raise exception 'PROOF 140 FAIL: Patch with % Fury at tick % was not taken there: %', v_fury, v_trk, v_r - 'ticks';
  end if;
  select b.ticks into v_new from public.battles b where b.id = v_bat;
  if not exists (select 1 from jsonb_array_elements(v_new -> 'e') e
                  where (e ->> 0)::int = v_trk and e ->> 1 = '0' and e ->> 2 = 'U' and e ->> 3 = 'PT' and (e ->> 4)::numeric = v_fury - 50)
     or pg_temp.before_140(v_old, v_trk) <> pg_temp.before_140(v_new, v_trk) then
    raise exception 'PROOF 140 FAIL: Patch did not spend 50 of % at tick %, or the past moved', v_fury, v_trk;
  end if;
  raise notice 'PASS: BA_FURY — Rake at 12: "%"; Patch at % with Fury %: taken, Fury % after', v_codes, v_trk, v_fury, v_fury - 50;

  -- ── BA_RUN (rolled back): Run from the next free tick ──
  begin
    perform pg_temp.at_tick_140(v_bat, v_trk + 2);
    v_r := cmd.battle_act(v_bat, v_h, 'RN', v_trk + 3);
    if not coalesce((v_r ->> 'ok')::boolean, false) then raise exception 'PROOF 140 FAIL: Run was refused: %', v_r - 'ticks'; end if;
    v_t := (v_r ->> 'tick')::int;
    v_new := v_r -> 'ticks';
    select e into v_x from jsonb_array_elements(v_new -> 'e') e where e ->> 2 = 'X' and e ->> 1 = '0' and (e ->> 0)::int > v_t order by (e ->> 0)::int limit 1;
    if not exists (select 1 from jsonb_array_elements(v_new -> 'e') e where (e ->> 0)::int = v_t and e ->> 1 = '0' and e ->> 2 = 'U' and e ->> 3 = 'RN')
       or v_x is null or (v_x ->> 0)::int <> v_t + 20 or (v_x ->> 3)::numeric not between round(public.wc_num('raid_flee_floor') * 100) and round(public.wc_num('raid_flee_max') * 100)   -- 0450: 3..45 (was 10..80)
      
       or exists (select 1 from jsonb_array_elements(v_new -> 'e') e where e ->> 1 = '0' and e ->> 2 = 'A' and (e ->> 0)::int > v_t and (e ->> 0)::int <= v_t + 20) then
      raise exception 'PROOF 140 FAIL: the run is not silent guns and a roll at its end: U at %, roll %', v_t, v_x;
    end if;
    raise notice 'PASS: BA_RUN — Run at %, guns silent, rolled at % with % %% (%)', v_t, v_x ->> 0, v_x ->> 3, case when (v_x ->> 4) = '1' then 'away' else 'caught' end;
    raise exception sqlstate 'BV140';
  exception when sqlstate 'BV140' then null;
  end;

  -- ── BA_PAY: the ship set upon pays ──
  v_old := v_new;
  select b.ticks into v_old from public.battles b where b.id = v_bat;
  perform pg_temp.at_tick_140(v_bat, v_trk + 2);
  v_r := cmd.battle_act(v_bat, v_h, 'PY', v_trk + 3);
  if not coalesce((v_r ->> 'ok')::boolean, false) then raise exception 'PROOF 140 FAIL: Pay was refused: %', v_r - 'ticks'; end if;
  v_t := (v_r ->> 'tick')::int;
  select b.ticks, b.resolves_at into v_new, v_end from public.battles b where b.id = v_bat;
  if v_new ->> 'out' <> 'RANSOM' or (v_new -> 'r' ->> 'paid')::boolean is not true or (v_new ->> 'n')::int <> v_t
     or (v_new -> 'e' -> -1)::text <> jsonb_build_array(v_t, -1, 'E', 'RANSOM')::text
     or pg_temp.before_140(v_old, v_t) <> pg_temp.before_140(v_new, v_t)
     or v_end <> (select b.started_at + make_interval(secs => (v_t + 2) * 0.6) from public.battles b where b.id = v_bat) then
    raise exception 'PROOF 140 FAIL: Pay at % did not end it in a ransom there: out %, n %, last %, ends %', v_t, v_new ->> 'out', v_new ->> 'n', v_new -> 'e' -> -1, v_end;
  end if;
  if (select count(*) from public.battle_sides s where s.battle_id = v_bat) <> v_ns then
    raise exception 'PROOF 140 FAIL: an act changed the sides';
  end if;
  raise notice 'PASS: BA_PAY — Pay at %: RANSOM (paid), the past the same, the end at tick % (k %); the sides unchanged (no PvP)', v_t, v_new ->> 'n', v_new ->> 'k';
end
$p$;
