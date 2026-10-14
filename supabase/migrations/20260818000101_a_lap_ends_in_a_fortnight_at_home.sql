-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0101 — A LAP ENDS IN A FORTNIGHT AT HOME, AND A LOOP MAY CALL AT EIGHT
--        Owner rows 122 and 116 (docs/OWNER_REQUESTS.md, 2026-10-11).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE ASK ─────────────────────────────────────────────────────────────────────────────────────
-- The owner, 2026-10-11: *"The trading routes should be from cities to cities, visiting 2 cities,
-- 3 cities, to max 8 cities then returning from the original starting city, earning gold. Then
-- waiting at least 2 weeks in that city."*
--
-- Two rules in one sentence, and the engine already keeps half of each: a standing route IS a loop
-- that returns to its first stop, and it already paces its laps. What is missing is the SIZE of the
-- loop (the cap has been 6 since 0092) and the REST at the end of one.
--
-- ── WHICH "TWO WEEKS" ───────────────────────────────────────────────────────────────────────────
-- This world runs two clocks and 0045/0100 moved one of them twice, so the unit has to be named.
-- `game_day_seconds` (2880 real s) is the CALENDAR day the market and the daily caps run on. The
-- VOYAGE-day is the one the player reads everywhere — "9.4 days" on a passage, `formatVoyageDays`,
-- the two-clock line — and at 0100's compression it is 90 real seconds.
--
-- A fortnight is therefore FOURTEEN VOYAGE-DAYS: the days the player counts. In real time that is
-- 14 x 86400 / time_compression = 21 minutes at the current clock, and it FOLLOWS the clock,
-- because the interval is derived from the knob and never typed. Fourteen CALENDAR days would have
-- been 11 real hours and 448 voyage-days — four times the longest passage in the game, a rest
-- nobody would ever see end. The knob is spelled in voyage-days so the unit cannot be misread:
-- `route_rest_voyage_days`.
--
-- ── WHOSE ROUTES REST ───────────────────────────────────────────────────────────────────────────
-- MERCHANTS' (players.is_npc), not players'. The instruction arrived inside a paragraph about the
-- world's own traders ("Make npc ships like this"), and forcing a 21-minute idle onto a captain's
-- own standing route is a nerf nobody asked for. The rule reads `players.is_npc`, the one
-- predicate, exactly as the crew-pool floor does (0097). If a player's routes should rest too,
-- that is one `and` away and it is the owner's call, not a thing to slip in.
--
-- ── WHERE IT LIVES ──────────────────────────────────────────────────────────────────────────────
-- In the pacing block of `cmd.run_standing_route` — the ONE place a route decides it may not start
-- its next lap yet (0092, re-cut to an interval by 0096). The rest is a FLOOR on that same hold,
-- not a second hold beside it: one authority for "when may this route sail again", which is the
-- whole reason 0096 collapsed the calendar boundary into the interval in the first place.
--
-- A merchant resting is a merchant LYING AT HER QUAY, visible on the chart at her berth, and that
-- is the point of the ask: the sea should show ships that have arrived somewhere, not only ships
-- in transit. `world.sea_traffic` already serves her `next_lap_at` from `hold_until`, so the rest
-- needs no new field to be read back (owner row 121 builds the harbour's view on top of it).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

insert into public.world_config (key, value, description) values
  ('route_rest_voyage_days', to_jsonb(14),
   '0101 (owner row 122): VOYAGE-days a merchant route lies at its home stop after a lap closes, '
   'before the next may start. The days the player counts — 90 real seconds each at 0100''s '
   'compression, so a fortnight is 21 real minutes and it follows the clock. A FLOOR on the pacing '
   'hold in cmd.run_standing_route, never a second hold. Merchant routes only (players.is_npc).');

update public.world_config
   set value = to_jsonb(8),
       description = 'DESIGN: a standing route calls at 2 to 8 harbours and returns to the first. '
                     'Raised from 6 on 2026-10-11 (owner row 122: "visiting 2 cities, 3 cities, to '
                     'max 8 cities then returning from the original starting city"). The engine '
                     'already looped; this is the stated maximum.',
       updated_at = now()
 where key = 'standing_route_stop_max';

-- ── THE SLICE TOOL (its own copy, by necessity — tests/duplication.spec.ts) ────────────────────
create temporary table hunks_0101 (fn text not null, n int not null, old text not null, new text not null,
                                   primary key (fn, n));
insert into hunks_0101 values
('cmd.run_standing_route(uuid, timestamptz)', 1,
$h$  v_hold   timestamptz;   -- 0096: the interval hold's instant$h$,
$h$  v_hold   timestamptz;   -- 0096: the interval hold's instant
  v_rest   timestamptz;   -- 0101: the fortnight at home, as an instant$h$),
('cmd.run_standing_route(uuid, timestamptz)', 2,
$h$      v_per := coalesce(sr.laps_per_game_day, public.wc_int('standing_route_laps_per_game_day'));
      if v_per > 0 then
        v_hold := (select max(x.started_at) from public.standing_route_laps x where x.route_id = sr.id)
                  + make_interval(secs => (public.wc_num('game_day_seconds') / v_per)::double precision);
        if v_hold > p_now then
          update public.standing_routes
             set hold_until = v_hold,
                 updated_at = now()
           where id = sr.id;
          return 0;
        end if;
      end if;$h$,
$h$      v_per := coalesce(sr.laps_per_game_day, public.wc_int('standing_route_laps_per_game_day'));
      v_hold := case when v_per > 0
                     then (select max(x.started_at) from public.standing_route_laps x where x.route_id = sr.id)
                          + make_interval(secs => (public.wc_num('game_day_seconds') / v_per)::double precision)
                end;
      -- 0101 (owner row 122): AND A MERCHANT RESTS A FORTNIGHT AT HOME. A floor on the same hold,
      -- measured from the moment the last lap CLOSED — she has arrived, and now she lies there —
      -- in VOYAGE-days, the days the player counts, converted through the served compression so the
      -- rest follows the clock instead of being typed in real seconds. Merchant routes only: the
      -- one predicate, players.is_npc, as the crew-pool floor reads it.
      if exists (select 1 from public.players p where p.id = sr.player_id and p.is_npc) then
        v_rest := (select max(x.closed_at) from public.standing_route_laps x
                    where x.route_id = sr.id and x.closed_at is not null)
                  + make_interval(secs => (public.wc_num('route_rest_voyage_days') * 86400
                                           / public.wc_num('time_compression'))::double precision);
        v_hold := greatest(coalesce(v_hold, v_rest), coalesce(v_rest, v_hold));
      end if;
      if v_hold is not null and v_hold > p_now then
        update public.standing_routes
           set hold_until = v_hold,
               updated_at = now()
         where id = sr.id;
        return 0;
      end if;$h$);

create temporary table defs_before_0101 as
  select f.fn, replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
         coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl
    from (select distinct fn from hunks_0101) as f(fn);

create or replace function pg_temp.recut_0101(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0101 where fn = p_fn order by n loop
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0101 slice: hunk % of % occurs % time(s), expected exactly 1 — the deployed body is not what this migration was generated against.',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0101('cmd.run_standing_route(uuid, timestamptz)');

do $$
declare
  v_fn      text;
  v_def     text;
  v_back    text;
  h         record;
  v_n       int;
  v_secs    numeric;
  v_lis     uuid;
  v_fnc     uuid;
  v_m       uuid;
  v_fleet   uuid;
  v_route   uuid;
  v_leg     jsonb;
  v_back_c  jsonb;
  v_spec    jsonb;
  v_hold0   timestamptz;
  v_hold1   timestamptz;
  v_closed  timestamptz;
  v_player  uuid;
  v_proute  uuid;
  v_pfleet  uuid;
  v_base    int;
  v_per     int;
  v_rest0   timestamptz;
  v_hold2   timestamptz;
begin
  -- (a) PARITY BY REVERSE SUBSTITUTION, and the ACL did not move.
  for v_fn in select distinct fn from hunks_0101 loop
    v_def := replace(pg_get_functiondef(v_fn::regprocedure), E'\r', '');
    v_back := v_def;
    for h in select * from hunks_0101 where fn = v_fn order by n desc loop
      v_n := (length(v_back) - length(replace(v_back, h.new, ''))) / length(h.new);
      if v_n <> 1 then
        raise exception '0101 self-assert FAIL: hunk % of % is in the new body % time(s), not once', h.n, v_fn, v_n;
      end if;
      v_back := replace(v_back, h.new, h.old);
    end loop;
    if v_back <> (select def from defs_before_0101 where fn = v_fn) or v_def = v_back then
      raise exception '0101 self-assert FAIL: % is not its pre-image plus only 0101''s hunks', v_fn;
    end if;
    if coalesce((select p.proacl::text from pg_proc p where p.oid = v_fn::regprocedure), '')
       is distinct from (select acl from defs_before_0101 where fn = v_fn) then
      raise exception '0101 self-assert FAIL: the re-cut moved the ACL of %', v_fn;
    end if;
  end loop;

  -- (b) THE TWO KNOBS, and the arithmetic read off them rather than retyped.
  if public.wc_int('standing_route_stop_max') <> 8 then
    raise exception '0101 self-assert FAIL: a route may call at % harbours, expected 8', public.wc_int('standing_route_stop_max');
  end if;
  v_secs := public.wc_num('route_rest_voyage_days') * 86400 / public.wc_num('time_compression');
  if public.wc_num('route_rest_voyage_days') <> 14 or round(v_secs) <> 1260 then
    raise exception '0101 self-assert FAIL: a fortnight is % voyage-day(s) = % real second(s), expected 14 and 1260',
      public.wc_num('route_rest_voyage_days'), round(v_secs);
  end if;

  -- (c) A ROUTE OF EIGHT SAVES, and nine is refused — the law, through the door that keeps it.
  select count(*) into v_base from public.players;
  begin
    select id into v_lis from public.ports where code = 'LIS';
    v_player := public.new_house('00000000-0000-4000-8000-000000000101'::uuid, 'Casa Quinzena', 'PRT');
    select id into v_pfleet from public.fleets where player_id = v_player;
    v_leg := (select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon),
                                       jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
                from public.sea_reaches a, public.sea_reaches b
               where a.port_id = v_lis and b.port_id = (select id from public.ports where code = 'SET'));
    -- eight stops, every one a different harbour, each leg carrying a course the save accepts
    v_spec := (select jsonb_agg(jsonb_build_object('port', c, 'course', v_leg))
                 from unnest(array['LIS', 'SET', 'SNL', 'CAD', 'MLG', 'OPO', 'BIL', 'FNC']) c);
    if coalesce((cmd.standing_route_save_for(v_player, null, 'Oito', v_spec, null, null, null)->>'ok')::boolean, false) is not true then
      raise exception '0101 self-assert FAIL: a route of eight harbours was refused: %',
        cmd.standing_route_save_for(v_player, null, 'Oito2', v_spec, null, null, null);
    end if;
    v_spec := v_spec || jsonb_build_array(jsonb_build_object('port', 'SVQ', 'course', v_leg));
    if (cmd.standing_route_save_for(v_player, null, 'Nove', v_spec, null, null, null)->>'error_code') <> 'E_PARSE' then
      raise exception '0101 self-assert FAIL: a route of NINE harbours was accepted: %',
        cmd.standing_route_save_for(v_player, null, 'Nove2', v_spec, null, null, null);
    end if;
    raise exception 'ROLLBACK_0101_STOPS';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0101_STOPS' then raise; end if;
  end;

  -- (d) THE REST ITSELF, on a real merchant, with the player as the control. A lap is planted as
  --     CLOSED a minute ago and the route is asked to run: a merchant must be held for the
  --     fortnight less that minute, and a player's identical route must not be held at all.
  begin
    select id into v_lis from public.ports where code = 'LIS';
    select id into v_fnc from public.ports where code = 'FNC';
    v_leg := (select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon),
                                       jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
                from public.sea_reaches a, public.sea_reaches b where a.port_id = v_lis and b.port_id = v_fnc);
    v_back_c := jsonb_build_array(v_leg->1, v_leg->0);
    v_m := public.npc_found(jsonb_build_object(
      'company', 'Casa do Descanso', 'alt_company', 'Casa da Folga', 'nation', 'PRT', 'ink', 'prt',
      'master', 'Capitão Quieto', 'blurb', 'A probe company that exists to lie still for a fortnight.',
      'capital', 40000, 'patience', 0.20, 'wares', '[]'::jsonb, 'roster_ord', 9101,
      'skills', jsonb_build_object('SEAMANSHIP', 1),
      'fleets', jsonb_build_array(jsonb_build_object(
        'name', 'Quinzena', 'roster_ord', 9101, 'days', 12,
        'ships', jsonb_build_array(jsonb_build_object('class', 'carlat', 'name', 'Quinzena')),
        'officers', '[]'::jsonb,
        'stops', jsonb_build_array(jsonb_build_object('port', 'LIS', 'course', v_leg),
                                   jsonb_build_object('port', 'FNC', 'course', v_back_c)),
        'alt_stops', jsonb_build_array(jsonb_build_object('port', 'LIS', 'course', v_leg),
                                       jsonb_build_object('port', 'FNC', 'course', v_back_c))))));
    select fleet_id, route_id into v_fleet, v_route from public.npc_fleets where player_id = v_m;
    -- The route runner's first three guards are the switch, the route's own pause and the fleet's
    -- berth: it returns 0 before it ever reaches the pacing unless routes are ON and she is DOCKED
    -- at the stop the cursor names. A fresh chain ships standing_routes_enabled false (0092), so
    -- the probe sets its own preconditions rather than discovering them — the first cut of this
    -- file did not, and the assert read "was not held at all" when nothing had run.
    update public.world_config set value = 'true'::jsonb where key = 'standing_routes_enabled';
    update public.fleets set port_id = v_lis, status = 'DOCKED' where id = v_fleet;
    update public.standing_routes set fleet_id = v_fleet, paused_reason = null, hold_until = null,
                                      stop_cursor = 0, lap_id = null
     where id = v_route;
    v_closed := now() - interval '1 minute';
    insert into public.standing_route_laps (route_id, lap_no, started_at, closed_at, net)
    values (v_route, 1, v_closed - interval '5 minutes', v_closed, 0);

    perform cmd.run_standing_route(v_fleet, now());
    select hold_until into v_hold0 from public.standing_routes where id = v_route;
    if v_hold0 is null then
      raise exception '0101 self-assert FAIL: a merchant whose lap closed a minute ago was not held at all';
    end if;
    if abs(extract(epoch from v_hold0 - (v_closed + make_interval(secs => v_secs::double precision)))) > 1 then
      raise exception '0101 self-assert FAIL: the hold is % and the fortnight from the lap''s close is %',
        v_hold0, v_closed + make_interval(secs => v_secs::double precision);
    end if;

    -- THE POSITIVE CONTROL ON THE CLOCK: at ten times the compression the SAME rest is a tenth as
    -- long in real time, because it is derived from the knob and never typed. The merchant PACE is
    -- taken out of the way for this pair of readings (laps_per_game_day 0, which the hunk's own
    -- `case when v_per > 0` leaves null), because at 9600 the fortnight is 126 s — SHORTER than
    -- this route's pace — and the floor would then be correctly overruled by it. That overruling
    -- is the NEXT assertion, not this one; the first cut of this file conflated the two and read
    -- the pace's 18 minutes as a broken clock.
    select laps_per_game_day into v_per from public.standing_routes where id = v_route;
    update public.standing_routes set laps_per_game_day = 0, hold_until = null where id = v_route;
    perform cmd.run_standing_route(v_fleet, now());
    select hold_until into v_rest0 from public.standing_routes where id = v_route;
    if v_rest0 is distinct from v_hold0 then
      raise exception '0101 self-assert FAIL: with the pace off the hold moved (% vs %) — the fortnight was not what held her',
        v_rest0, v_hold0;
    end if;
    update public.world_config set value = to_jsonb(9600) where key = 'time_compression';
    update public.standing_routes set hold_until = null where id = v_route;
    perform cmd.run_standing_route(v_fleet, now());
    select hold_until into v_hold1 from public.standing_routes where id = v_route;
    if round(extract(epoch from v_rest0 - v_closed) / nullif(extract(epoch from v_hold1 - v_closed), 0)) <> 10 then
      raise exception '0101 self-assert FAIL: the rest did not follow the clock (% vs %)', v_rest0, v_hold1;
    end if;

    -- AND IT IS A FLOOR, NOT A REPLACEMENT. The pace is put back with the clock still fast, so the
    -- fortnight (126 s) is now the SHORTER of the two: the merchant pace must win, because the rule
    -- is greatest(pace, rest) and not rest. Without this the hunk could be a plain assignment and
    -- every other assertion in this file would still pass.
    if coalesce(v_per, 0) <= 0 then
      raise exception '0101 self-assert FAIL: the probe route has no pace (% laps/game-day), so the floor cannot be shown to be a floor', v_per;
    end if;
    update public.standing_routes set laps_per_game_day = v_per, hold_until = null where id = v_route;
    perform cmd.run_standing_route(v_fleet, now());
    select hold_until into v_hold2 from public.standing_routes where id = v_route;
    if v_hold2 is null or v_hold2 <= v_hold1 then
      raise exception '0101 self-assert FAIL: the longer merchant pace did not survive the fortnight floor (pace-and-rest % vs rest-alone %)',
        v_hold2, v_hold1;
    end if;
    update public.world_config set value = to_jsonb(960) where key = 'time_compression';

    -- THE CONTROL: a PLAYER's route, the same lap closed a minute ago, is not held by this rule.
    v_player := public.new_house('00000000-0000-4000-8000-000000000102'::uuid, 'Casa Sem Folga', 'PRT');
    select id into v_pfleet from public.fleets where player_id = v_player;
    update public.fleets set port_id = v_lis, status = 'DOCKED' where id = v_pfleet;
    v_spec := jsonb_build_array(jsonb_build_object('port', 'LIS', 'course', v_leg),
                                jsonb_build_object('port', 'FNC', 'course', v_back_c));
    v_proute := (cmd.standing_route_save_for(v_player, null, 'Sem Folga', v_spec, null, null, 0)->>'route_id')::uuid;
    if v_proute is null then
      select id into v_proute from public.standing_routes where player_id = v_player order by created_at desc limit 1;
    end if;
    update public.standing_routes set fleet_id = v_pfleet, paused_reason = null, hold_until = null,
                                      stop_cursor = 0, lap_id = null, laps_per_game_day = 0
     where id = v_proute;
    insert into public.standing_route_laps (route_id, lap_no, started_at, closed_at, net)
    values (v_proute, 1, v_closed - interval '5 minutes', v_closed, 0);
    perform cmd.run_standing_route(v_pfleet, now());
    if (select hold_until from public.standing_routes where id = v_proute) is not null then
      raise exception '0101 self-assert FAIL: the fortnight reached a player''s route (held until %)',
        (select hold_until from public.standing_routes where id = v_proute);
    end if;
    raise exception 'ROLLBACK_0101_REST';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0101_REST' then raise; end if;
  end;

  if (select count(*) from public.players) <> v_base then
    raise exception '0101 self-assert FAIL: a probe company survived the subtransaction';
  end if;

  raise notice '0101 self-assert ok: A LAP ENDS IN A FORTNIGHT AT HOME. cmd.run_standing_route is its '
    'pre-image plus only this file''s two hunks, ACL unmoved; a route may call at 8 harbours and a '
    'ninth is refused E_PARSE through the save door; the rest is % voyage-day(s) = % real second(s) '
    'derived from time_compression and never typed. On probe companies, rolled back: a merchant '
    'whose lap closed a minute ago is held to the second until the fortnight is out, and the same '
    'hold stands with her pace switched off, so it was the fortnight that held her; at ten times '
    'the compression the same rest is a tenth as long in real time, so it follows the clock; with '
    'the clock still fast the LONGER merchant pace wins, so the fortnight is a floor and not a '
    'replacement; and a PLAYER''s identical route, same lap, same minute, is not held at all.',
    public.wc_num('route_rest_voyage_days'), round(v_secs);
end $$;
