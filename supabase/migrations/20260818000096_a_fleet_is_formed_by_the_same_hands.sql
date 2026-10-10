-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0096 — A FLEET IS FORMED BY THE SAME HANDS
--        docs/NPC_TRADERS.md §3.1, §4.2, §4.3 (D3), §4.4, §11 "0096". The owner, 2026-10-08:
--        "this game will now turn into simulator, of trades. add npc to and show movement on map"
--        and "it should be fleet as well, i will be able to click on fleet, see ships, captains,
--        skills etc." — merchant companies must be made of the SAME rows a player's company is
--        made of, by the SAME authorities. This file builds those authorities; no merchant exists
--        after it (0097 builds the machinery, 0098 founds the companies), and nothing here is
--        reachable by a client that was not reachable before.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE METHOD (the 0092 `cmd.enqueue` precedent, NO_SPAGHETTI §1) ────────────────────────────
-- Each client door that a merchant's founding needs is SLICED: the body after the door's own
-- player-only gates moves VERBATIM into a server-only CORE that takes `p_player`; the door becomes
-- `current_player_id()` + its gates + one call. Every hunk is cut from pg_get_functiondef,
-- LF-normalised, asserted to occur exactly once; the door's parity is proven by REVERSE
-- substitution back to its pre-image, and the core is proven to CONTAIN the moved region to the
-- character (with only this file's named core-hunks applied to it). ACLs of the doors are unmoved.
-- No core is granted to `anon` or `authenticated`; none is in either registry.
--
-- ── WHAT THIS FILE SUPERSEDES ──────────────────────────────────────────────────────────────────
--   GENERALISED IN PLACE (dropped and recreated, grants re-issued):
--     public.new_house(uuid, text, text)  -> new_house(auth, name, nation 'PRT', port 'LIS',
--                       fleet 'Gaivota', class 'barca', ship 'Gaivota', ducats null, is_npc false).
--                       An unknown nation or port code now RAISES (0004:289 silently nulled the
--                       nation). cmd.found_house's 3-argument call is unchanged, and its EFFECT is
--                       asserted identical below (same rows, same FOUNDING amount, same LIS).
--   SLICED DOORS -> NEW CORES (server-only):
--     cmd.do_build                 ship insert            -> public.commission_ship (the ONE ship
--                                                            insert; new_house was the second copy)
--     cmd.hire_officer             signing + wage         -> public.sign_officer
--     cmd.post_officer             the posting update     -> public.post_officer_to
--     cmd.study_skill              level + tuition        -> public.raise_skill
--     cmd.provision_preset_save    the book write         -> cmd.provision_preset_save_for
--     cmd.provision_preset_apply   the fleet's order      -> cmd.provision_preset_apply_for
--     cmd.standing_route_save      the route write        -> cmd.standing_route_save_for
--                                  (+ p_laps_per_game_day, + crew_up, + the anchor fix)
--     cmd.standing_route_assign    the assignment         -> cmd.standing_route_assign_for
--                                  (+ the anchor fix)
--     cmd.standing_route_pause     the pause/resume       -> cmd.standing_route_pause_for
--                                  (+ p_reason: the world's own reasons are written as events)
--     cmd.clear                    the release            -> cmd.clear_for
--   SLICED IN PLACE (hunks):
--     cmd.run_standing_route       THE pacing hunk becomes an INTERVAL hold (§4.2) and the
--                                  sail-on branch renders through the one tail (§4.4).
--     cmd.standing_route_lines     step 5 renders through cmd.standing_route_tail (§4.4).
--     cmd.do_sell                  D3: `SELL <good> ALL` takes the day's allowance (§4.3).
--     cmd.cancel_at                an ownership gate (below, "A HOLE THIS FILE CLOSES").
--     world.standing_routes        serves `crew_up` per stop and `laps_per_game_day` per route.
--     public.client_rpc_entry_points  the stale `world.trade_routes` row goes (revoked since
--                                  0071:176; the ONE registry row `authenticated` cannot execute).
--   TABLES: players.is_npc (+ check: a merchant can never sign in — moved here from 0097 so that
--     new_house is generalised once, not twice); standing_routes.laps_per_game_day;
--     standing_route_stops.crew_up; standing_routes.paused_reason's CHECK gains 'dark', 'laid_up'
--     (a drop/re-add on ~30 rows).
--
-- ── A STATED CHANGE FOR LIVE PLAYERS ───────────────────────────────────────────────────────────
-- THE PACING RULE (D2, 0092:656-668) held every route on earth until the NEXT CALENDAR BOUNDARY:
-- one instant for all, a thundering herd at every game-day. It becomes an INTERVAL: a lap may
-- start `game_day_seconds / N` after the LAST lap started (N = the route's own laps_per_game_day,
-- else the knob, 1). D2's number is unchanged — one lap per game-day for a player — its anchor
-- moves from the calendar to the lap. docs/TRADE_ROUTES.md §13 and DEV_LOG say so too.
--
-- ── THE REPEATED-HARBOUR ANCHOR, FIXED FOR EVERYONE ────────────────────────────────────────────
-- The save door re-anchored an assigned route with `min(ord) where port_id = v_at` (0092:1004);
-- the assign door the same (0093:234). A loop calling at one harbour twice (A → B → C → B) was
-- reset to the FIRST B whenever the fleet was at or bound for the second, so its lap boundary was
-- never reached. Both now prefer the stop the cursor names when that stop IS the fleet's harbour.
--
-- ── A HOLE THIS FILE CLOSES ────────────────────────────────────────────────────────────────────
-- cmd.clear and cmd.cancel_at are client entry points that took a fleet id and NEVER asked whose
-- it was (security definer, so RLS was no wall). Harmless while no foreign fleet id was ever
-- served; 0099 serves merchant fleet ids on the map, so both now refuse a fleet that is not the
-- caller's (E_NOT_YOUR_FLEET, the sentence every other door says).
--
-- ── WHAT IT DOES NOT TOUCH ─────────────────────────────────────────────────────────────────────
-- The executor (cmd.advance, cmd.execute_order, do_sail/do_buy/do_provision/do_repair/do_hire,
-- voyage.settle, cmd.enqueue, cmd.parse) is CALLED, never retyped — and asserted below to read no
-- identity (auth.uid() / current_player_id()), after a positive control proves the scan can see.
--
-- Depends on: 0004, 0007, 0015, 0016, 0034, 0072, 0073, 0092, 0093, 0094.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── 0. TABLES ──────────────────────────────────────────────────────────────────────────────────
alter table public.players add column is_npc boolean not null default false;
alter table public.players add constraint players_npc_never_signs_in check (not is_npc or auth_uid is null);
comment on column public.players.is_npc is
  '0096: THE one predicate for "is this a merchant company the world keeps?" (docs/NPC_TRADERS.md §1.1). '
  'A merchant has no login, structurally (players_npc_never_signs_in).';

alter table public.standing_routes add column laps_per_game_day int
  constraint standing_routes_laps_per_game_day_sane check (laps_per_game_day is null or laps_per_game_day between 0 and 96);
comment on column public.standing_routes.laps_per_game_day is
  '0096: this route''s own pace (null = the knob standing_route_laps_per_game_day). Written ONLY by '
  'cmd.standing_route_save_for; read ONLY by cmd.run_standing_route''s pacing hunk.';

alter table public.standing_route_stops add column crew_up boolean not null default false;
comment on column public.standing_route_stops.crew_up is
  '0096: hire back to crew_required before sailing on (HIRE n, rendered by cmd.standing_route_tail).';

alter table public.standing_routes drop constraint standing_routes_paused_reason_check;
alter table public.standing_routes add constraint standing_routes_paused_reason_check
  check (paused_reason = any (array['player', 'reserve', 'losing', 'off_route', 'error', 'edited', 'dark', 'laid_up']));

-- ── 1. THE HUNKS, written ONCE, read by the cut and by the parity proof ────────────────────────
-- kind 'door' = a re-cut of a live function (reverse-substitution parity);
-- kind 'core' = a named change applied to a MOVED region inside a new core (the moved region,
--               with these reversed, must appear verbatim in the core).
create temporary table hunks_0096 (fn text not null, n int not null, old text not null, new text not null,
                                   primary key (fn, n));
-- The moved regions: door pre-image text that now lives in a core, and the core that holds it.
create temporary table moved_0096 (door text primary key, core text not null, region text not null, call text not null);

insert into hunks_0096 values
-- ── cmd.do_build: the ONE ship insert ──────────────────────────────────────────────────────────
('cmd.do_build(uuid, jsonb)', 1,
$h$  insert into public.ships (player_id, fleet_id, class_id, name, durability, crew,
                            water_t, food_t, store_ratio, is_flagship)
  values (f.player_id, p_fleet, c.id, v_name, c.durability, 0,
          0, 0, public.wc_num('store_ratio_default'), false)
  returning id into v_ship;$h$,
$h$  -- 0096: THE ONE SHIP INSERT (public.commission_ship), the hull laid down empty and uncrewed.
  v_ship := public.commission_ship(f.player_id, p_fleet, c.code, v_name, false, false);$h$),

-- ── cmd.do_sell: D3 — SELL <good> ALL takes what the day's allowance takes ─────────────────────
('cmd.do_sell(uuid, jsonb)', 1,
$h$  v_cap := world.daily_cap_remaining(f.player_id, f.port_id, g.id);
  if v_qty > v_cap then$h$,
$h$  v_cap := world.daily_cap_remaining(f.player_id, f.port_id, g.id);
  -- 0096 (D3, docs/TRADE_ROUTES.md §11): an ALL sells what the day's allowance takes instead of
  -- refusing the whole parcel — the mirror of BUY ALL. An EXPLICIT quantity still refuses whole.
  if v_qty > v_cap and floor(v_cap) > 0
     and not (p_args ? 'qty' and p_args->>'qty' is not null)
     and coalesce(p_args->>'qty_mode', 'ALL') = 'ALL' then
    v_qty := floor(v_cap);
  end if;
  if v_qty > v_cap then$h$),

-- ── cmd.cancel_at: the ownership gate it never had ─────────────────────────────────────────────
('cmd.cancel_at(uuid, integer)', 1,
$h$begin
  if p_index is null then$h$,
$h$begin
  -- 0096: a fleet id is not a public handle (0099 serves merchant fleet ids on the map).
  if not exists (select 1 from public.fleets where id = p_fleet and player_id = public.current_player_id()) then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_YOUR_FLEET',
      'error_message', 'That fleet is not yours.', 'fixes', '[]'::jsonb);
  end if;
  if p_index is null then$h$),

-- ── cmd.run_standing_route: the interval pacing, and the one tail on the sail-on branch ─────────
('cmd.run_standing_route(uuid, timestamptz)', 1,
$h$  v_day    int;
$h$,
$h$  v_day    int;
  v_hold   timestamptz;   -- 0096: the interval hold's instant
$h$),
('cmd.run_standing_route(uuid, timestamptz)', 2,
$h$        -- The last SAIL was refused and the player CLEARed it: sail on, and nothing else.
        v_parsed := jsonb_set(cmd.parse(sr.player_id, p_fleet, format('SAIL TO %s', cur.code)),
                              '{fleet_id}', to_jsonb(p_fleet::text));
        v_res := cmd.enqueue(sr.player_id, v_parsed, format('SAIL TO %s', cur.code), prv.course, sr.lap_id);
        if not coalesce((v_res->>'ok')::boolean, false) then
          raise exception 'E_ROUTE_BROKEN: The queue was too full to add the sail onward.' using errcode = 'P0001';
        end if;
        return 1;$h$,
$h$        -- The last SAIL was refused and the player CLEARed it: sail on, and nothing else —
        -- 0096: through THE ONE TAIL (cmd.standing_route_tail), so a crew-short fleet hires first.
        v_lines := cmd.standing_route_tail(sr.id, prv.ord, p_fleet);
        for i in 1 .. array_length(v_lines, 1) loop
          v_parsed := jsonb_set(cmd.parse(sr.player_id, p_fleet, v_lines[i]), '{fleet_id}', to_jsonb(p_fleet::text));
          v_res := cmd.enqueue(sr.player_id, v_parsed, v_lines[i],
                               case when v_parsed->>'verb' = 'SAIL' then prv.course end, sr.lap_id);
          if not coalesce((v_res->>'ok')::boolean, false) then
            raise exception 'E_ROUTE_BROKEN: The queue was too full to add the sail onward.' using errcode = 'P0001';
          end if;
        end loop;
        return array_length(v_lines, 1);$h$),
('cmd.run_standing_route(uuid, timestamptz)', 3,
$h$      -- PACING (D2): at most N laps START per game-day; then wait for the next one.
      v_per := public.wc_int('standing_route_laps_per_game_day');
      if v_per > 0 then
        v_day := world.game_day(p_now);
        if (select count(*) from public.standing_route_laps x
             where x.route_id = sr.id and world.game_day(x.started_at) = v_day) >= v_per then
          update public.standing_routes
             set hold_until = to_timestamp(((v_day + 1) * public.wc_num('game_day_seconds'))::double precision),
                 updated_at = now()
           where id = sr.id;
          return 0;
        end if;
      end if;$h$,
$h$      -- PACING (D2), 0096: AN INTERVAL, NOT A CALENDAR. A lap may START game_day_seconds / N after
      -- the LAST lap started — N the route's own pace, else the knob. One rule for every route; it
      -- no longer wakes every route on earth at the same boundary (docs/NPC_TRADERS.md §4.2).
      v_per := coalesce(sr.laps_per_game_day, public.wc_int('standing_route_laps_per_game_day'));
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
      end if;$h$),

-- ── cmd.standing_route_lines: step 5 is the one tail ───────────────────────────────────────────
('cmd.standing_route_lines(uuid, integer, uuid)', 1,
$h$  -- 5. SAIL to the next stop. Its course rides as args.path (the generator attaches it).
  select p.code into v_next
    from public.standing_route_stops s join public.ports p on p.id = s.port_id
   where s.route_id = p_route and s.ord = (p_stop + 1) % v_n;
  v_out := v_out || format('SAIL TO %s', v_next);
  return v_out;$h$,
$h$  -- 5. 0096: THE ONE TAIL — HIRE back to strength when the stop says so, then SAIL to the next
  --    stop. Its course rides as args.path (the generator attaches it). The sail-on branch of
  --    cmd.run_standing_route renders the same tail, so a crew-short fleet cannot loop for ever.
  v_out := v_out || cmd.standing_route_tail(p_route, p_stop, p_fleet);
  return v_out;$h$),

-- ── world.standing_routes: serve the two new route facts ───────────────────────────────────────
('world.standing_routes()', 1,
$h$        'cursor', sr.stop_cursor, 'lap_no', sr.lap_no,$h$,
$h$        'cursor', sr.stop_cursor, 'lap_no', sr.lap_no, 'laps_per_game_day', sr.laps_per_game_day,$h$),
('world.standing_routes()', 2,
$h$'ord', s.ord, 'port', p.code, 'course', s.course, 'repair', s.repair,$h$,
$h$'ord', s.ord, 'port', p.code, 'course', s.course, 'repair', s.repair, 'crew_up', s.crew_up,$h$),

-- ── public.client_rpc_entry_points: the stale ranking row goes ─────────────────────────────────
('public.client_rpc_entry_points()', 1,
$h$      ('world',       'trade_routes',        'uuid, uuid, numeric, int, uuid'),
$h$,
$h$      -- 0096: world.trade_routes is server-only since 0071:176 (the owner removed the player's
      -- comparison); its row here was the one registry row `authenticated` could not execute.
$h$),

-- ── THE CORE HUNKS: named changes to a moved region inside its core ────────────────────────────
('cmd.standing_route_save_for', 1,
$h$      insert into public.standing_routes (player_id, name, reserve, stop_after_losing_laps)
      values (v_player, v_name, coalesce(p_reserve, 0),
              coalesce(p_losing, public.wc_int('standing_route_losing_laps')))
      returning * into sr;$h$,
$h$      insert into public.standing_routes (player_id, name, reserve, stop_after_losing_laps, laps_per_game_day)
      values (v_player, v_name, coalesce(p_reserve, 0),
              coalesce(p_losing, public.wc_int('standing_route_losing_laps')), p_laps_per_game_day)
      returning * into sr;$h$),
('cmd.standing_route_save_for', 2,
$h$             stop_after_losing_laps = coalesce(p_losing, stop_after_losing_laps), updated_at = now()$h$,
$h$             stop_after_losing_laps = coalesce(p_losing, stop_after_losing_laps),
             laps_per_game_day = coalesce(p_laps_per_game_day, laps_per_game_day), updated_at = now()$h$),
('cmd.standing_route_save_for', 3,
$h$      insert into public.standing_route_stops (route_id, ord, port_id, course, repair)
      values (sr.id, k, v_port.id, s->'course', coalesce((s->>'repair')::boolean, false));$h$,
$h$      insert into public.standing_route_stops (route_id, ord, port_id, course, repair, crew_up)
      values (sr.id, k, v_port.id, s->'course', coalesce((s->>'repair')::boolean, false),
              coalesce((s->>'crew_up')::boolean, false));$h$),
('cmd.standing_route_save_for', 4,
$h$    select min(ord) into v_anchor from public.standing_route_stops where route_id = sr.id and port_id = v_at;$h$,
$h$    -- 0096: A LOOP MAY CALL AT ONE HARBOUR TWICE. Prefer the stop the cursor names when that stop
    -- IS the fleet's harbour (the one she is bound for, or — docked with route orders pending —
    -- the one she is working), and only then the first visit.
    v_anchor := case when f.status <> 'SAILING'
                           and exists (select 1 from public.orders o where o.fleet_id = f.id
                                        and o.status = 'pending' and o.route_lap_id is not null)
                     then (select s9.ord from public.standing_route_stops s9
                            where s9.route_id = sr.id and s9.port_id = v_at
                              and s9.ord = (sr.stop_cursor - 1 + v_n) % v_n)
                     else (select s9.ord from public.standing_route_stops s9
                            where s9.route_id = sr.id and s9.port_id = v_at
                              and s9.ord = sr.stop_cursor % v_n) end;
    if v_anchor is null then
      select min(ord) into v_anchor from public.standing_route_stops where route_id = sr.id and port_id = v_at;
    end if;$h$),
('cmd.standing_route_assign_for', 1,
$h$    select min(ord) into v_anchor from public.standing_route_stops where route_id = sr.id and port_id = f.port_id;$h$,
$h$    -- 0096: prefer the stop the cursor names when it IS this harbour (a loop may call twice).
    v_anchor := coalesce(
      (select s9.ord from public.standing_route_stops s9
        where s9.route_id = sr.id and s9.port_id = f.port_id
          and s9.ord = sr.stop_cursor % greatest(1, (select count(*) from public.standing_route_stops s8
                                                      where s8.route_id = sr.id))),
      (select min(ord) from public.standing_route_stops where route_id = sr.id and port_id = f.port_id));$h$),
('cmd.standing_route_pause_for', 1,
$h$    update public.standing_routes set paused_reason = 'player', updated_at = now() where id = sr.id;$h$,
$h$    if coalesce(p_reason, 'player') = 'player' then
      update public.standing_routes set paused_reason = 'player', updated_at = now() where id = sr.id;
    else
      -- 0096: the world's own reasons (dark, laid_up, …) are WRITTEN, like every pause a route
      -- makes of itself (cmd.standing_route_set_paused, 0092).
      perform cmd.standing_route_set_paused(sr.id, p_reason, null, p_sentence);
    end if;$h$);

-- ── 1b. THE PRE-IMAGES, captured before anything is cut ────────────────────────────────────────
create temporary table defs_before_0096 as
  select f.fn, replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
         coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl
    from (select distinct fn from hunks_0096 where fn like '%(%'
          union select x from unnest(array[
            'cmd.hire_officer(text, uuid)', 'cmd.post_officer(text, uuid)', 'cmd.study_skill(text, uuid)',
            'cmd.provision_preset_save(uuid, text, integer)', 'cmd.provision_preset_apply(uuid, uuid)',
            'cmd.standing_route_save(uuid, text, jsonb, bigint, integer)', 'cmd.standing_route_assign(uuid, uuid)',
            'cmd.standing_route_pause(uuid, boolean)', 'cmd.clear(uuid, boolean)']) x) as f(fn);

-- THE MOVED REGIONS, read off the pre-images: from the first line that moves to the body's last
-- statement. Each becomes the door's hunk (old = the region, new = one call to the core), so the
-- door's parity proof and the core's containment proof read the SAME text — nothing retyped.
create or replace function pg_temp.region_0096(p_door text, p_start text) returns text
language plpgsql as $$
declare
  v_def text := (select def from defs_before_0096 where fn = p_door);
  v_at  int  := strpos(v_def, p_start);
  v_end int;
begin
  if v_at = 0 or strpos(substr(v_def, v_at + 1), p_start) > 0 then
    raise exception '0096 slice: the moved region of % does not start exactly once where expected', p_door;
  end if;
  -- the body's last statement ends just before its final newline-end-$function$
  v_end := length(v_def) - strpos(reverse(v_def), reverse(E'\nend $function$')) - length(E'\nend $function$') + 2;
  return substr(v_def, v_at, v_end - v_at);
end $$;

insert into moved_0096 (door, core, region, call) values
('cmd.hire_officer(text, uuid)', 'public.sign_officer',
   pg_temp.region_0096('cmd.hire_officer(text, uuid)', '  if exists (select 1 from public.player_officers where player_id = v_player and officer_id = v_off.id) then'),
   E'  -- 0096: the signing, the wage and the record are public.sign_officer''s (the core a merchant''s
'
   '  -- founding calls too). The encounter gate above — she must be in the room — stays the door''s.
'
   '  return public.sign_officer(v_player, v_code, p_fleet);'),
('cmd.post_officer(text, uuid)', 'public.post_officer_to',
   pg_temp.region_0096('cmd.post_officer(text, uuid)', '  select o.id into v_off from public.officers o where o.code = v_code;'),
   E'  -- 0096: the posting is public.post_officer_to''s.
  return public.post_officer_to(v_player, v_code, p_fleet);'),
('cmd.study_skill(text, uuid)', 'public.raise_skill',
   pg_temp.region_0096('cmd.study_skill(text, uuid)', '  select ps.level into v_level from public.player_skills ps'),
   E'  -- 0096: the level, the tuition and the record are public.raise_skill''s. The academy gate
'
   '  -- above — taught ashore, where a school stands — stays the door''s.
'
   '  return public.raise_skill(v_player, v_code, v_port.code);'),
('cmd.provision_preset_save(uuid, text, integer)', 'cmd.provision_preset_save_for',
   pg_temp.region_0096('cmd.provision_preset_save(uuid, text, integer)', E'  begin
    if p_preset is null then'),
   E'  -- 0096: the book write is cmd.provision_preset_save_for''s.
'
   '  return cmd.provision_preset_save_for(v_player, p_preset, p_name, p_days);'),
('cmd.provision_preset_apply(uuid, uuid)', 'cmd.provision_preset_apply_for',
   pg_temp.region_0096('cmd.provision_preset_apply(uuid, uuid)', '  select id, player_id, name into f from public.fleets where id = p_fleet;'),
   E'  -- 0096: the fleet''s standing order is cmd.provision_preset_apply_for''s.
'
   '  return cmd.provision_preset_apply_for(v_player, p_fleet, p_preset);'),
('cmd.standing_route_save(uuid, text, jsonb, bigint, integer)', 'cmd.standing_route_save_for',
   pg_temp.region_0096('cmd.standing_route_save(uuid, text, jsonb, bigint, integer)', '  v_n := case when jsonb_typeof(p_stops) = ''array'''),
   E'  -- 0096: the route write is cmd.standing_route_save_for''s (a null pace leaves it unchanged).
'
   '  return cmd.standing_route_save_for(v_player, p_route, p_name, p_stops, p_reserve, p_losing, null);'),
('cmd.standing_route_assign(uuid, uuid)', 'cmd.standing_route_assign_for',
   pg_temp.region_0096('cmd.standing_route_assign(uuid, uuid)', '  -- FLEET BEFORE ROUTE: the fleet it is on now and the fleet it is given, in id order.'),
   E'  -- 0096: the assignment is cmd.standing_route_assign_for''s.
'
   '  return cmd.standing_route_assign_for(v_player, p_route, p_fleet);'),
('cmd.standing_route_pause(uuid, boolean)', 'cmd.standing_route_pause_for',
   pg_temp.region_0096('cmd.standing_route_pause(uuid, boolean)', '  -- FLEET BEFORE ROUTE (0093).'),
   E'  -- 0096: the pause and the resume are cmd.standing_route_pause_for''s; the player''s reason is ''player''.
'
   '  return cmd.standing_route_pause_for(v_player, p_route, p_paused, ''player'', null);'),
('cmd.clear(uuid, boolean)', 'cmd.clear_for',
   pg_temp.region_0096('cmd.clear(uuid, boolean)', '  -- §F.3: "CLEAR drops every pending order and LEAVES THE ACTIVE ONE RUNNING." Recalling an active'),
   E'  -- 0096: the release is cmd.clear_for''s, and it now asks whose fleet this is.
'
   '  return cmd.clear_for(public.current_player_id(), p_fleet, p_include_active);');

-- Each door's hunk IS its moved region.
insert into hunks_0096 (fn, n, old, new) select door, 1, region, call from moved_0096;

-- ── 1c. THE FOUNDING'S EFFECT, read through the OLD new_house before it is replaced ────────────
create or replace function pg_temp.house_effect_0096(p_player uuid) returns jsonb
language sql as $$
  select jsonb_build_object(
    'player', (select jsonb_build_object('name', p.company_name, 'nation', n.code, 'ducats', p.ducats,
                                         'level', p.company_level, 'title', p.title_level)
                 from public.players p left join public.nations n on n.id = p.nation_id where p.id = p_player),
    'fleets', (select jsonb_agg(jsonb_build_object('name', f.name, 'status', f.status, 'port', po.code,
                                                   'version', f.version, 'preset', f.provision_preset_id) order by f.name)
                 from public.fleets f left join public.ports po on po.id = f.port_id where f.player_id = p_player),
    'ships', (select jsonb_agg(jsonb_build_object('name', s.name, 'class', c.code, 'dur', s.durability,
                                                  'crew', s.crew, 'water', s.water_t, 'food', s.food_t,
                                                  'ratio', s.store_ratio, 'flag', s.is_flagship,
                                                  'cargo', s.cargo, 'basis', s.cargo_basis) order by s.name)
                from public.ships s join public.ship_classes c on c.id = s.class_id where s.player_id = p_player),
    'ledger', (select jsonb_agg(jsonb_build_object('kind', l.kind, 'delta', l.ducats_delta, 'bal', l.balance_after)
                                order by l.created_at, l.kind)
                 from public.ledger l where l.player_id = p_player),
    'events', (select jsonb_agg(jsonb_build_object('kind', e.kind, 'payload', e.payload) order by e.created_at, e.kind)
                 from public.events e where e.player_id = p_player))
$$;
create temporary table effect_0096 (k text primary key, v jsonb);
do $$
declare
  v jsonb;
begin
  begin
    perform cmd.assume_identity('00000000-0096-4000-8000-0000000000a1');
    v := cmd.found_house('Casa da Prova', 'PRT');
    v := pg_temp.house_effect_0096((v->>'player_id')::uuid);
    raise exception using errcode = 'P0961', message = '0096 effect probe rollback';
  exception when sqlstate 'P0961' then
    null;
  end;
  insert into effect_0096 values ('before', v);
end $$;

-- ── 2. THE ONE SHIP INSERT, AND THE ONE FLEET INSERT ───────────────────────────────────────────
create or replace function public.commission_ship(p_player uuid, p_fleet uuid, p_class_code text, p_name text,
                                                  p_flagship boolean, p_crewed boolean)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- THE ONE PLACE A HULL IS PUT INTO THE `ships` TABLE (0096). Two copies of this insert lived in
-- new_house (0004:308, the founding Gaivota, crewed and stored) and cmd.do_build (0072, a hull laid
-- down empty). A merchant's convoy is commissioned by the same insert. Every constraint and trigger
-- (the house caps, one flagship, the composite fleet/player FK, the per-company name) bites here.
declare
  c      public.ship_classes%rowtype;
  v_ship uuid;
begin
  select * into c from public.ship_classes where code = p_class_code;
  if c.id is null then
    raise exception 'E_NO_SUCH_CLASS: no ship is called "%"', coalesce(p_class_code, '') using errcode = 'P0001';
  end if;
  insert into public.ships (player_id, fleet_id, class_id, name, durability, crew,
                            water_t, food_t, store_ratio, is_flagship)
  values (p_player, p_fleet, c.id, p_name, c.durability,
          case when p_crewed then c.crew_required else 0 end,
          case when p_crewed then 2.400 else 0 end,
          case when p_crewed then 1.800 else 0 end,
          public.wc_num('store_ratio_default'), coalesce(p_flagship, false))
  returning id into v_ship;
  return v_ship;
end $$;
comment on function public.commission_ship(uuid, uuid, text, text, boolean, boolean) is
  '0096: THE one ship insert. Callers: public.new_house (crewed, the founding stores), cmd.do_build '
  '(empty), public.npc_found (0098). Server-only.';

create or replace function public.form_fleet(p_player uuid, p_name text, p_port uuid)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- THE ONE PLACE A FLEET IS FORMED (0096): docked at a harbour, with no ships yet. new_house forms
-- the founding fleet through it; 0098 forms a merchant's second fleet; a player verb to form a
-- second fleet (fleet_max = 2, 0021) is its named third caller.
declare
  v_fleet uuid;
begin
  insert into public.fleets (player_id, name, status, port_id)
  values (p_player, p_name, 'DOCKED', p_port)
  returning id into v_fleet;
  return v_fleet;
end $$;

-- ── 3. new_house, GENERALISED IN PLACE ─────────────────────────────────────────────────────────
drop function public.new_house(uuid, text, text);
create function public.new_house(p_auth_uid uuid, p_company_name text, p_nation_code text default 'PRT',
                                 p_port_code text default 'LIS', p_fleet_name text default 'Gaivota',
                                 p_class_code text default 'barca', p_ship_name text default 'Gaivota',
                                 p_ducats bigint default null, p_is_npc boolean default false)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- DESIGN K.1, 0:00 — "One Barca, 'Gaivota', docked at Lisboa. 8,000 ducats." — by default, and
-- exactly so (0096's self-assert compares the effect with 0004's body). The parameters are what a
-- merchant company's founding needs (docs/NPC_TRADERS.md §3.1): its own harbour, flagship and
-- purse. An unknown nation or port code RAISES; 0004 silently nulled the nation.
declare
  v_player uuid;
  v_fleet  uuid;
  v_nation uuid;
  v_port   uuid;
  v_start  bigint := coalesce(p_ducats, public.wc_int('starting_ducats'));
begin
  select id into v_nation from public.nations where code = p_nation_code;
  if v_nation is null then
    raise exception 'E_NO_SUCH_NATION: no nation answers to "%"', coalesce(p_nation_code, '') using errcode = 'P0001';
  end if;
  select id into v_port from public.ports where code = p_port_code and kind = 'HARBOUR';
  if v_port is null then
    raise exception 'E_NO_SUCH_PORT: there is no harbour "%"', coalesce(p_port_code, '') using errcode = 'P0001';
  end if;

  insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
  values (p_auth_uid, p_company_name, v_nation, 0, coalesce(p_is_npc, false))
  returning id into v_player;

  perform public.credit(v_player, 'FOUNDING', v_start,
                        public.emit_event(v_player, 'FOUNDED',
                          jsonb_build_object('company', p_company_name, 'port', p_port_code)));

  v_fleet := public.form_fleet(v_player, p_fleet_name, v_port);
  perform public.commission_ship(v_player, v_fleet, p_class_code, p_ship_name, true, true);
  return v_player;
end $$;

-- ── 4. THE CORES ───────────────────────────────────────────────────────────────────────────────
create or replace function public.sign_officer(p_player uuid, p_officer_code text, p_fleet uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0096: CORE of cmd.hire_officer — the signing, the wage through the one mover, the record. The
-- door keeps the encounter gate (E_NOT_IN_THE_ROOM). Server-only.
declare
  v_player uuid := p_player;
  v_code   text := upper(btrim(coalesce(p_officer_code, '')));
  v_off    public.officers%rowtype;
  v_purse  bigint;
  v_owner  uuid;
  v_id     uuid;
begin
  select * into v_off from public.officers where code = v_code;
  if v_off.id is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_SUCH_OFFICER',
      'error_message', format('No officer answers to "%s".', v_code), 'fixes', '[]'::jsonb);
  end if;
  if exists (select 1 from public.player_officers where player_id = v_player and officer_id = v_off.id) then
    return jsonb_build_object('ok', false, 'error_code', 'E_ALREADY_SIGNED',
      'error_message', format('%s already serves this house.', v_off.name),
      'fixes', jsonb_build_array('(post them to a fleet instead)'));
  end if;

  -- A fleet named must be YOURS. Reading it here rather than trusting the caller is the same rule
  -- every cmd verb follows: the client asks, the server decides.
  if p_fleet is not null then
    select player_id into v_owner from public.fleets where id = p_fleet;
    if v_owner is distinct from v_player then
      return jsonb_build_object('ok', false, 'error_code', 'E_NOT_YOUR_FLEET',
        'error_message', 'That fleet is not yours to post an officer to.',
        'fixes', jsonb_build_array('(name one of your own fleets, or leave them ashore)'));
    end if;
  end if;

  select ducats into v_purse from public.players where id = v_player;
  if v_purse < v_off.wage_ducats then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_ENOUGH_DUCATS',
      'error_message', format('%s signs for %s d. and the house holds %s.', v_off.name, v_off.wage_ducats, v_purse),
      'fixes', jsonb_build_array('(sell a parcel first)'));
  end if;

  insert into public.player_officers (player_id, officer_id, fleet_id)
  values (v_player, v_off.id, p_fleet)
  returning id into v_id;

  -- The money moves through the ONE mover (0004), so the purse and the ledger cannot disagree.
  perform public.credit(
    v_player,
    'OFFICER_WAGE',
    -v_off.wage_ducats,
    public.emit_event(v_player, 'SIGNED_OFFICER', jsonb_build_object(
      'officer', v_off.name, 'code', v_off.code, 'specialty', v_off.specialty,
      'bonus_pct', v_off.bonus_pct, 'cost', v_off.wage_ducats)));

  return jsonb_build_object('ok', true, 'officer', v_off.code, 'name', v_off.name,
    'specialty', v_off.specialty, 'bonus_pct', v_off.bonus_pct, 'fleet', p_fleet, 'paid', v_off.wage_ducats);
end $$;

create or replace function public.post_officer_to(p_player uuid, p_officer_code text, p_fleet uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0096: CORE of cmd.post_officer — the posting. Server-only.
declare
  v_player uuid := p_player;
  v_code   text := upper(btrim(coalesce(p_officer_code, '')));
  v_off    uuid;
  v_owner  uuid;
  v_n      int;
begin
  select o.id into v_off from public.officers o where o.code = v_code;
  if v_off is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_SUCH_OFFICER',
      'error_message', format('No officer answers to "%s".', v_code),
      'fixes', jsonb_build_array('(check the roster)'));
  end if;

  if p_fleet is not null then
    select player_id into v_owner from public.fleets where id = p_fleet;
    if v_owner is distinct from v_player then
      return jsonb_build_object('ok', false, 'error_code', 'E_NOT_YOUR_FLEET',
        'error_message', 'That fleet is not yours.', 'fixes', jsonb_build_array('(name one of your own)'));
    end if;
  end if;

  update public.player_officers set fleet_id = p_fleet
   where player_id = v_player and officer_id = v_off;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_SIGNED',
      'error_message', 'That officer does not serve this house.',
      'fixes', jsonb_build_array('(hire them first)'));
  end if;

  return jsonb_build_object('ok', true, 'officer', v_code, 'fleet', p_fleet);
end $$;

create or replace function public.raise_skill(p_player uuid, p_skill_code text, p_port_code text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0096: CORE of cmd.study_skill — the level row and the tuition (500 × the next level) through the
-- one mover. The door keeps the academy gate; `p_port_code` is only what the record says. Server-only.
declare
  v_player uuid := p_player;
  v_code   text := upper(btrim(coalesce(p_skill_code, '')));
  v_skill  public.skills%rowtype;
  v_port   record;
  v_level  int;
  v_next   int;
  v_max    int := public.wc_int('skill_max_level');
  v_cost   bigint;
  v_purse  bigint;
begin
  select * into v_skill from public.skills where code = v_code;
  if v_skill.id is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_SUCH_SKILL',
      'error_message', format('Nothing is taught under the name "%s".', v_code), 'fixes', '[]'::jsonb);
  end if;
  select p_port_code as code into v_port;
  select ps.level into v_level from public.player_skills ps
   where ps.player_id = v_player and ps.skill_id = v_skill.id;
  v_level := coalesce(v_level, 0);
  v_next  := v_level + 1;

  if v_next > v_max then
    return jsonb_build_object('ok', false, 'error_code', 'E_SKILL_MAXED',
      'error_message', format('%s is already at %s, which is as far as it is taught.', v_skill.name, v_max),
      'fixes', jsonb_build_array('(study something else)'));
  end if;

  v_cost := public.wc_int('skill_study_base_cost') * v_next;
  select ducats into v_purse from public.players where id = v_player;
  if v_purse < v_cost then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_ENOUGH_DUCATS',
      'error_message', format('%s to level %s costs %s d. and the house holds %s.', v_skill.name, v_next, v_cost, v_purse),
      'fixes', jsonb_build_array('(sell a parcel first)'));
  end if;

  insert into public.player_skills (player_id, skill_id, level)
  values (v_player, v_skill.id, 1)
  on conflict (player_id, skill_id) do update set level = public.player_skills.level + 1,
                                                  studied_at = now();

  perform public.credit(
    v_player,
    'TUITION',
    -v_cost,
    public.emit_event(v_player, 'STUDIED', jsonb_build_object(
      'skill', v_skill.name, 'code', v_skill.code, 'level', v_next,
      'port', v_port.code, 'cost', v_cost)));

  return jsonb_build_object('ok', true, 'skill', v_skill.code, 'name', v_skill.name,
    'level', v_next, 'max_level', v_max, 'paid', v_cost, 'port', v_port.code,
    'effect', v_skill.effect);
end $$;

create or replace function cmd.provision_preset_save_for(p_player uuid, p_preset uuid, p_name text, p_days integer)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0096: CORE of cmd.provision_preset_save. Server-only.
declare
  v_player uuid := p_player;
  pr       public.provision_presets%rowtype;
  v_name   text := nullif(btrim(coalesce(p_name, '')), '');
  v_ref    jsonb;
begin
  begin
    if p_preset is null then
      if v_name is null or p_days is null then
        return jsonb_build_object('ok', false, 'error_code', 'E_PARSE',
          'error_message', 'A standing order needs a name and a number of days.',
          'fixes', jsonb_build_array('(name it, then set the days)'));
      end if;
      insert into public.provision_presets (player_id, name, days)
      values (v_player, v_name, p_days)
      returning * into pr;
    else
      select * into pr from public.provision_presets
       where id = p_preset and player_id = v_player;
      if pr.id is null then
        return jsonb_build_object('ok', false, 'error_code', 'E_NO_SUCH_PRESET',
          'error_message', 'The book holds no such standing order.',
          'fixes', jsonb_build_array('(read the book again)'));
      end if;
      update public.provision_presets
         set name = coalesce(v_name, name), days = coalesce(p_days, days)
       where id = pr.id
      returning * into pr;
    end if;
  exception
    when unique_violation then
      return jsonb_build_object('ok', false, 'error_code', 'E_NAME_TAKEN',
        'error_message', format('The book already holds an order named "%s".', v_name),
        'fixes', jsonb_build_array('(pick another name)'));
    when check_violation then
      if sqlerrm like '%days_sane%' then
        return jsonb_build_object('ok', false, 'error_code', 'E_PARSE',
          'error_message', 'Days must be a whole number from 1 to 999.',
          'fixes', jsonb_build_array('(set the days between 1 and 999)'));
      end if;
      return jsonb_build_object('ok', false, 'error_code', 'E_PARSE',
        'error_message', 'A name is 2 to 24 characters.',
        'fixes', jsonb_build_array('(shorten or lengthen the name)'));
    when others then
      -- The cap trigger raises 'E_PRESET_CAP: …'; anything else in that shape passes through in
      -- the server's own words (execute_order's split, 0007).
      if sqlerrm ~ '^E_[A-Z0-9_]+:' then
        v_ref := cmd.refusal_caught(sqlerrm);
        return jsonb_build_object('ok', false, 'error_code', v_ref->>'code',
          'error_message', v_ref->>'sentence',
          'fixes', jsonb_build_array('(strike an order from the book first)'));
      end if;
      raise;
  end;

  return jsonb_build_object('ok', true, 'id', pr.id, 'name', pr.name, 'days', pr.days);
end $$;

create or replace function cmd.provision_preset_apply_for(p_player uuid, p_fleet uuid, p_preset uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0096: CORE of cmd.provision_preset_apply. Server-only.
declare
  v_player uuid := p_player;
  f        record;
  pr       public.provision_presets%rowtype;
begin
  select id, player_id, name into f from public.fleets where id = p_fleet;
  if f.id is null or f.player_id is distinct from v_player then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_YOUR_FLEET',
      'error_message', 'That fleet is not yours.',
      'fixes', jsonb_build_array('(name one of your own fleets)'));
  end if;
  if p_preset is not null then
    select * into pr from public.provision_presets
     where id = p_preset and player_id = v_player;
    if pr.id is null then
      return jsonb_build_object('ok', false, 'error_code', 'E_NO_SUCH_PRESET',
        'error_message', 'The book holds no such standing order.',
        'fixes', jsonb_build_array('(read the book again)'));
    end if;
  end if;
  update public.fleets set provision_preset_id = p_preset where id = f.id;
  return jsonb_build_object('ok', true, 'fleet', f.name,
                            'preset', pr.name, 'days', pr.days);
end $$;

create or replace function cmd.standing_route_save_for(p_player uuid, p_route uuid, p_name text, p_stops jsonb,
                                                       p_reserve bigint, p_losing integer,
                                                       p_laps_per_game_day integer default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0096: CORE of cmd.standing_route_save — THE one writer of every route column. `p_laps_per_game_day`
-- null = unchanged (the player's editor never passes one; the merchant planner does). Each stop
-- may carry `crew_up`. The re-anchor prefers the cursor's own stop (a loop may call twice). Server-only.
declare
  v_player uuid := p_player;
  sr       public.standing_routes%rowtype;
  v_name   text := nullif(btrim(coalesce(p_name, '')), '');
  v_n      int;
  s        jsonb;
  ln       jsonb;
  pt       jsonb;
  k        int;
  j        int;
  v_port   record;
  v_prev   uuid;
  v_first  uuid;
  v_good   uuid;
  v_kind   text;
  f        public.fleets%rowtype;
  v_at     uuid;
  v_anchor int;
begin
  v_n := case when jsonb_typeof(p_stops) = 'array' then jsonb_array_length(p_stops) else 0 end;
  if v_n < 2 or v_n > public.wc_int('standing_route_stop_max') then
    return cmd.standing_route_refusal('E_PARSE',
      format('A route needs 2 to %s stops.', public.wc_int('standing_route_stop_max')), '(add or remove a stop)');
  end if;

  begin
    if p_route is null then
      if v_name is null then
        return cmd.standing_route_refusal('E_PARSE', 'A route needs a name.', '(name it)');
      end if;
      insert into public.standing_routes (player_id, name, reserve, stop_after_losing_laps, laps_per_game_day)
      values (v_player, v_name, coalesce(p_reserve, 0),
              coalesce(p_losing, public.wc_int('standing_route_losing_laps')), p_laps_per_game_day)
      returning * into sr;
    else
      select * into sr from public.standing_routes where id = p_route and player_id = v_player for update;
      if sr.id is null then
        return cmd.standing_route_refusal('E_NO_SUCH_ROUTE', 'You keep no such route.', '(read your routes again)');
      end if;
      update public.standing_routes
         set name = coalesce(v_name, name), reserve = coalesce(p_reserve, reserve),
             stop_after_losing_laps = coalesce(p_losing, stop_after_losing_laps),
             laps_per_game_day = coalesce(p_laps_per_game_day, laps_per_game_day), updated_at = now()
       where id = sr.id returning * into sr;
      delete from public.standing_route_stops where route_id = sr.id;
    end if;

    for k in 0 .. v_n - 1 loop
      s := p_stops->k;
      select p.id, p.kind, p.code into v_port from public.ports p
       where p.code = upper(btrim(coalesce(s->>'port', '')));
      if v_port.id is null then
        raise exception 'E_NO_SUCH_PORT: there is no port "%"', coalesce(s->>'port', '') using errcode = 'P0001';
      end if;
      if v_port.kind <> 'HARBOUR' then
        raise exception 'E_UNAVAILABLE: % is open water; a route stops only where there is a market', v_port.code using errcode = 'P0001';
      end if;
      if v_port.id = v_prev or (k = v_n - 1 and v_port.id = v_first) then
        raise exception 'E_SAME_DEST: two stops in a row are both %', v_port.code using errcode = 'P0001';
      end if;
      if jsonb_typeof(s->'course') <> 'array' or jsonb_array_length(s->'course') < 2 then
        raise exception 'E_BAD_PATH: the leg from % has no course', v_port.code using errcode = 'P0001';
      end if;
      for pt in select * from jsonb_array_elements(s->'course') loop
        if jsonb_typeof(pt) <> 'array' or jsonb_array_length(pt) <> 2
           or jsonb_typeof(pt->0) <> 'number' or jsonb_typeof(pt->1) <> 'number'
           or abs((pt->>0)::numeric) > 90 or abs((pt->>1)::numeric) > 180 then
          raise exception 'E_BAD_PATH: the leg from % is not a list of points on the sphere', v_port.code using errcode = 'P0001';
        end if;
      end loop;
      insert into public.standing_route_stops (route_id, ord, port_id, course, repair, crew_up)
      values (sr.id, k, v_port.id, s->'course', coalesce((s->>'repair')::boolean, false),
              coalesce((s->>'crew_up')::boolean, false));
      if k = 0 then v_first := v_port.id; end if;
      v_prev := v_port.id;

      j := 0;
      for ln in select * from jsonb_array_elements(coalesce(s->'lines', '[]'::jsonb)) loop
        v_kind := upper(btrim(coalesce(ln->>'kind', '')));
        if v_kind not in ('SELL', 'BUY') then
          raise exception 'E_PARSE: a stop''s line is SELL or BUY, not "%"', coalesce(ln->>'kind', '') using errcode = 'P0001';
        end if;
        v_good := null;
        if nullif(btrim(coalesce(ln->>'good', '')), '') is not null then
          select id into v_good from public.goods where code = btrim(ln->>'good');
          if v_good is null then
            raise exception 'E_NO_SUCH_GOOD: there is no good "%"', ln->>'good' using errcode = 'P0001';
          end if;
        elsif v_kind = 'BUY' then
          raise exception 'E_PARSE: a BUY line names a good' using errcode = 'P0001';
        end if;
        insert into public.standing_route_lines (route_id, stop_ord, ord, kind, good_id, qty, price_limit, at_profit)
        values (sr.id, k, j, v_kind, v_good,
                nullif(ln->>'qty', '')::numeric, nullif(ln->>'price_limit', '')::numeric,
                coalesce((ln->>'at_profit')::boolean, false));
        j := j + 1;
      end loop;
    end loop;
  exception
    -- 0093: no unique_violation arm — a name is a label, not a key (the name index is dropped).
    when check_violation then
      if sqlerrm like '%name_length%' then
        return cmd.standing_route_refusal('E_PARSE', 'A name is 2 to 24 characters.', '(shorten or lengthen the name)');
      end if;
      return cmd.standing_route_refusal('E_PARSE', 'A quantity, a price and a keep-back figure are positive numbers.', '(check the numbers)');
    when invalid_text_representation then
      return cmd.standing_route_refusal('E_PARSE', 'A quantity or a price is not a number.', '(check the numbers)');
    when others then
      if sqlerrm ~ '^E_[A-Z_]+:' then
        return cmd.standing_route_refusal(split_part(sqlerrm, ':', 1),
          btrim(substr(sqlerrm, length(split_part(sqlerrm, ':', 1)) + 2)), '(change the route and save again)');
      end if;
      raise;
  end;

  -- An EDIT of an assigned route re-anchors on where its fleet is now; if the fleet is at no stop
  -- of the edited route, the route pauses rather than guess (docs/TRADE_ROUTES.md §5).
  if sr.fleet_id is not null then
    select * into f from public.fleets where id = sr.fleet_id;
    v_at := case when f.status = 'SAILING'
                 then (select dest_port_id from public.voyages where fleet_id = f.id and status = 'SAILING')
                 else f.port_id end;
    -- 0096: A LOOP MAY CALL AT ONE HARBOUR TWICE. Prefer the stop the cursor names when that stop
    -- IS the fleet's harbour (the one she is bound for, or — docked with route orders pending —
    -- the one she is working), and only then the first visit.
    v_anchor := case when f.status <> 'SAILING'
                           and exists (select 1 from public.orders o where o.fleet_id = f.id
                                        and o.status = 'pending' and o.route_lap_id is not null)
                     then (select s9.ord from public.standing_route_stops s9
                            where s9.route_id = sr.id and s9.port_id = v_at
                              and s9.ord = (sr.stop_cursor - 1 + v_n) % v_n)
                     else (select s9.ord from public.standing_route_stops s9
                            where s9.route_id = sr.id and s9.port_id = v_at
                              and s9.ord = sr.stop_cursor % v_n) end;
    if v_anchor is null then
      select min(ord) into v_anchor from public.standing_route_stops where route_id = sr.id and port_id = v_at;
    end if;
    if v_anchor is null then
      perform cmd.standing_route_set_paused(sr.id, 'edited', null,
        format('%s is not at or bound for a stop of the edited route.', f.name));
    else
      update public.standing_routes
         set stop_cursor = case when f.status <> 'SAILING'
                                 and exists (select 1 from public.orders o where o.fleet_id = f.id
                                              and o.status = 'pending' and o.route_lap_id is not null)
                                then (v_anchor + 1) % v_n else v_anchor end,
             paused_reason = case when paused_reason = 'edited' then null else paused_reason end
       where id = sr.id;
    end if;
  end if;

  return jsonb_build_object('ok', true, 'id', sr.id, 'name', sr.name, 'stops', v_n);
end $$;

create or replace function cmd.standing_route_assign_for(p_player uuid, p_route uuid, p_fleet uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0096: CORE of cmd.standing_route_assign (0093's order: fleet locks first, every check before any
-- change, the open lap closed by the one closer, the route started by cmd.advance). Server-only.
declare
  v_player uuid := p_player;
  sr       public.standing_routes%rowtype;
  f        public.fleets%rowtype;
  v_held   uuid;
  v_other  text;
  v_anchor int;
begin
  -- FLEET BEFORE ROUTE: the fleet it is on now and the fleet it is given, in id order.
  select r.fleet_id into v_held from public.standing_routes r where r.id = p_route and r.player_id = v_player;
  perform 1 from public.fleets where id in (p_fleet, v_held) order by id for update;
  select * into sr from public.standing_routes where id = p_route and player_id = v_player for update;
  if sr.id is null then
    return cmd.standing_route_refusal('E_NO_SUCH_ROUTE', 'You keep no such route.', '(read your routes again)');
  end if;
  if sr.fleet_id is distinct from v_held then
    return cmd.standing_route_refusal('E_BUSY', 'The route changed while you pressed. Try again.', '(try again)');
  end if;

  -- EVERY CHECK FIRST. A refused assign changes nothing: not the route, not the lap, not the old
  -- fleet's queue (0092 released that queue before these checks ran).
  if p_fleet is not null then
    select * into f from public.fleets where id = p_fleet;
    if f.id is null or f.player_id <> v_player then
      return cmd.standing_route_refusal('E_NO_SUCH_FLEET', 'That fleet is not yours.', '(pick one of your own fleets)');
    end if;
    select name into v_other from public.standing_routes where fleet_id = p_fleet and id <> sr.id;
    if v_other is not null then
      return cmd.standing_route_refusal('E_ROUTE_TAKEN', format('%s already runs the route "%s".', f.name, v_other),
        '(stop that route first)');
    end if;
    if f.status <> 'DOCKED' then
      return cmd.standing_route_refusal('E_NOT_DOCKED', format('%s must be in port at one of the route''s stops to start it.', f.name),
        '(start it when the fleet is in port)');
    end if;
    -- 0096: prefer the stop the cursor names when it IS this harbour (a loop may call twice).
    v_anchor := coalesce(
      (select s9.ord from public.standing_route_stops s9
        where s9.route_id = sr.id and s9.port_id = f.port_id
          and s9.ord = sr.stop_cursor % greatest(1, (select count(*) from public.standing_route_stops s8
                                                      where s8.route_id = sr.id))),
      (select min(ord) from public.standing_route_stops where route_id = sr.id and port_id = f.port_id));
    if v_anchor is null then
      return cmd.standing_route_refusal('E_NOT_ON_ROUTE',
        format('%s is in %s, which is not a stop on this route.', f.name, (select name from public.ports where id = f.port_id)),
        '(sail to one of the stops first)');
    end if;
    if f.provision_preset_id is null then
      return cmd.standing_route_refusal('E_NO_KEEP', 'Set how many days of supplies to keep first.',
        '(set the supplies to keep for this fleet)');
    end if;
  end if;

  -- Whatever fleet held it is released: its pending route orders become ordinary orders.
  if sr.fleet_id is not null and sr.fleet_id is distinct from p_fleet then
    update public.orders set route_lap_id = null
     where fleet_id = sr.fleet_id and status = 'pending' and route_lap_id is not null;
  end if;
  -- The open lap is CLOSED by the one closer — what it traded so far is a lap in History — never
  -- left open for good (0092 only forgot its id).
  if sr.lap_id is not null then
    perform cmd.standing_route_close_lap(sr.id, now());
  end if;

  if p_fleet is null then
    update public.standing_routes
       set fleet_id = null, lap_id = null, hold_until = null, paused_reason = null, updated_at = now()
     where id = sr.id;
    return jsonb_build_object('ok', true, 'route', sr.name, 'fleet', null);
  end if;

  update public.standing_routes
     set fleet_id = p_fleet, stop_cursor = v_anchor, paused_reason = null, hold_until = null,
         lap_id = null, updated_at = now()
   where id = sr.id;
  -- The route starts NOW: the one queue runner, which refills when the queue is dry.
  perform cmd.advance(p_fleet, now());
  return jsonb_build_object('ok', true, 'route', sr.name, 'fleet', f.name,
    'queue', cmd.queue(p_fleet), 'version', (select version from public.fleets where id = p_fleet));
end $$;

create or replace function cmd.standing_route_pause_for(p_player uuid, p_route uuid, p_paused boolean,
                                                        p_reason text default 'player', p_sentence text default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0096: CORE of cmd.standing_route_pause. A player pauses with 'player' (unchanged); the world's
-- upkeep pauses with its own reason ('dark', 'laid_up', 0097) and that pause is WRITTEN. Server-only.
declare
  v_player uuid := p_player;
  sr       public.standing_routes%rowtype;
  v_held   uuid;
begin
  -- FLEET BEFORE ROUTE (0093).
  select r.fleet_id into v_held from public.standing_routes r where r.id = p_route and r.player_id = v_player;
  perform 1 from public.fleets where id = v_held for update;
  select * into sr from public.standing_routes where id = p_route and player_id = v_player for update;
  if sr.id is null then
    return cmd.standing_route_refusal('E_NO_SUCH_ROUTE', 'You keep no such route.', '(read your routes again)');
  end if;
  if sr.fleet_id is distinct from v_held then
    return cmd.standing_route_refusal('E_BUSY', 'The route changed while you pressed. Try again.', '(try again)');
  end if;
  if coalesce(p_paused, true) then
    if coalesce(p_reason, 'player') = 'player' then
      update public.standing_routes set paused_reason = 'player', updated_at = now() where id = sr.id;
    else
      -- 0096: the world's own reasons (dark, laid_up, …) are WRITTEN, like every pause a route
      -- makes of itself (cmd.standing_route_set_paused, 0092).
      perform cmd.standing_route_set_paused(sr.id, p_reason, null, p_sentence);
    end if;
    return jsonb_build_object('ok', true, 'route', sr.name, 'paused', true);
  end if;
  update public.standing_routes set paused_reason = null, hold_until = null, updated_at = now() where id = sr.id;
  if sr.fleet_id is not null then
    perform cmd.advance(sr.fleet_id, now());
  end if;
  return jsonb_build_object('ok', true, 'route', sr.name, 'paused', false);
end $$;

create or replace function cmd.clear_for(p_player uuid, p_fleet uuid, p_include_active boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0096: CORE of cmd.clear — the release, for the company that owns the fleet. Server-only.
declare v_n int;
begin
  if p_player is null or not exists (select 1 from public.fleets where id = p_fleet and player_id = p_player) then
    return jsonb_build_object('ok', false, 'error_code', 'E_NOT_YOUR_FLEET',
      'error_message', 'That fleet is not yours.', 'fixes', '[]'::jsonb);
  end if;
  -- §F.3: "CLEAR drops every pending order and LEAVES THE ACTIVE ONE RUNNING." Recalling an active
  -- voyage is RECALL, which is not a V0 verb (K.1), so CLEAR ALL reports honestly rather than
  -- half-doing it.
  -- Pending orders AND a failed one. 0007's halt rule stops the fleet while a failed order sits
  -- in its queue, so if CLEAR left it there the fleet would be stopped for good — the deadlock
  -- shape that cost the previous game a live incident. CLEAR is the release.
  update public.orders set status = 'cancelled'
   where fleet_id = p_fleet and status in ('pending', 'failed');
  get diagnostics v_n = row_count;
  update public.fleets set version = version + 1 where id = p_fleet;
  return jsonb_build_object('ok', true, 'cancelled', v_n,
    'active_left_running', not p_include_active
      or (select status from public.fleets where id = p_fleet) = 'SAILING',
    'note', case when p_include_active then 'A voyage already at sea keeps sailing: RECALL arrives in V1.' end,
    'queue', cmd.queue(p_fleet));
end $$;

-- ── 5. THE ONE TAIL, AND THE ONE CREW READING ──────────────────────────────────────────────────
create or replace function public.fleet_crew_shortfall(p_fleet uuid)
returns integer
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0096: how many hands short of `crew_required` her hulls are, summed. One reading; the Inn's
  -- served HIRE ceiling (OWNER_REQUESTS row 16) is its named second caller.
  select coalesce(sum(greatest(0, c.crew_required - s.crew)), 0)::int
    from public.ships s join public.ship_classes c on c.id = s.class_id
   where s.fleet_id = p_fleet
$$;

create or replace function cmd.standing_route_tail(p_route uuid, p_stop integer, p_fleet uuid)
returns text[]
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0096: THE ONE TAIL of a stop — `HIRE n` when the stop says crew_up and she is short, then
-- `SAIL TO <next stop>`. Rendered by BOTH refill branches of cmd.run_standing_route (the full
-- render through cmd.standing_route_lines, and the sail-on branch), so neither hand-writes a SAIL.
declare
  v_n     int;
  v_crew  boolean;
  v_short int;
  v_next  text;
  v_out   text[] := '{}';
begin
  select count(*) into v_n from public.standing_route_stops where route_id = p_route;
  select s.crew_up into v_crew from public.standing_route_stops s where s.route_id = p_route and s.ord = p_stop;
  if coalesce(v_crew, false) then
    v_short := public.fleet_crew_shortfall(p_fleet);
    if v_short > 0 then
      v_out := v_out || format('HIRE %s', v_short);
    end if;
  end if;
  select p.code into v_next
    from public.standing_route_stops s join public.ports p on p.id = s.port_id
   where s.route_id = p_route and s.ord = (p_stop + 1) % v_n;
  v_out := v_out || format('SAIL TO %s', v_next);
  return v_out;
end $$;

-- ── 6. THE SLICE TOOL (its own copy, by necessity — tests/duplication.spec.ts:365-380) ────────
create or replace function pg_temp.recut_0096(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0096 where fn = p_fn order by n loop
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0096 slice: hunk % of % occurs % time(s), expected exactly 1 — the deployed body is not what this migration was generated against.',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0096(fn) from (select distinct fn from hunks_0096 where fn like '%(%') x order by fn;

-- ── 7. GRANTS. Every core is server-only; the doors' ACLs are unmoved (asserted). ──────────────
revoke all on function public.new_house(uuid, text, text, text, text, text, text, bigint, boolean) from public, anon, authenticated;
revoke all on function public.commission_ship(uuid, uuid, text, text, boolean, boolean)      from public, anon, authenticated;
revoke all on function public.form_fleet(uuid, text, uuid)                                     from public, anon, authenticated;
revoke all on function public.sign_officer(uuid, text, uuid)                                   from public, anon, authenticated;
revoke all on function public.post_officer_to(uuid, text, uuid)                                from public, anon, authenticated;
revoke all on function public.raise_skill(uuid, text, text)                                    from public, anon, authenticated;
revoke all on function cmd.provision_preset_save_for(uuid, uuid, text, integer)                from public, anon, authenticated;
revoke all on function cmd.provision_preset_apply_for(uuid, uuid, uuid)                        from public, anon, authenticated;
revoke all on function cmd.standing_route_save_for(uuid, uuid, text, jsonb, bigint, integer, integer) from public, anon, authenticated;
revoke all on function cmd.standing_route_assign_for(uuid, uuid, uuid)                         from public, anon, authenticated;
revoke all on function cmd.standing_route_pause_for(uuid, uuid, boolean, text, text)           from public, anon, authenticated;
revoke all on function cmd.clear_for(uuid, uuid, boolean)                                      from public, anon, authenticated;
revoke all on function public.fleet_crew_shortfall(uuid)                                       from public, anon, authenticated;
revoke all on function cmd.standing_route_tail(uuid, integer, uuid)                            from public, anon, authenticated;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_auth    constant uuid := '00000000-0096-4000-8000-000000000001';
  c_auth2   constant uuid := '00000000-0096-4000-8000-000000000002';
  c_auth3   constant uuid := '00000000-0096-4000-8000-0000000000a1';
  c_cores   constant text[] := array[
    'public.new_house(uuid, text, text, text, text, text, text, bigint, boolean)',
    'public.commission_ship(uuid, uuid, text, text, boolean, boolean)',
    'public.form_fleet(uuid, text, uuid)',
    'public.sign_officer(uuid, text, uuid)',
    'public.post_officer_to(uuid, text, uuid)',
    'public.raise_skill(uuid, text, text)',
    'cmd.provision_preset_save_for(uuid, uuid, text, integer)',
    'cmd.provision_preset_apply_for(uuid, uuid, uuid)',
    'cmd.standing_route_save_for(uuid, uuid, text, jsonb, bigint, integer, integer)',
    'cmd.standing_route_assign_for(uuid, uuid, uuid)',
    'cmd.standing_route_pause_for(uuid, uuid, boolean, text, text)',
    'cmd.clear_for(uuid, uuid, boolean)',
    'public.fleet_crew_shortfall(uuid)',
    'cmd.standing_route_tail(uuid, integer, uuid)'];
  v_fn      text;
  v_def     text;
  v_back    text;
  v_core    text;
  h         record;
  m         record;
  v_n       int;
  v_hits    text[];
  v_pc      text[];
  v_base    int;
  v_player  uuid;
  v_player2 uuid;
  v_fleet   uuid;
  v_fleet2  uuid;
  v_lis     uuid;
  v_fnc     uuid;
  v_cad     uuid;
  v_good    text;
  v_good_id uuid;
  v_leg_lf  jsonb;
  v_leg_fl  jsonb;
  v_leg_fc  jsonb;
  v_leg_cf  jsonb;
  v_stops   jsonb;
  v_res     jsonb;
  v_route   uuid;
  v_preset  uuid;
  v_after   jsonb;
  v_lines   text[];
  v_cursor  int;
  v_hold    timestamptz;
  v_start   timestamptz;
  v_sold    numeric;
  v_cap     numeric;
  v_refused text;
  v_fail    text;
begin
  -- (a) PARITY BY REVERSE SUBSTITUTION: every re-cut door, each 0096 hunk put back the other way
  --     (each new hunk occurring exactly once), is its pre-image to the character; ACLs unmoved.
  for v_fn in select distinct fn from hunks_0096 where fn like '%(%' loop
    v_def := replace(pg_get_functiondef(v_fn::regprocedure), E'\r', '');
    v_back := v_def;
    for h in select * from hunks_0096 where fn = v_fn order by n desc loop
      v_n := (length(v_back) - length(replace(v_back, h.new, ''))) / length(h.new);
      if v_n <> 1 then
        raise exception '0096 self-assert FAIL: hunk % of % is in the new body % time(s), not once', h.n, v_fn, v_n;
      end if;
      v_back := replace(v_back, h.new, h.old);
    end loop;
    if v_back <> (select def from defs_before_0096 where fn = v_fn) or v_def = v_back then
      raise exception '0096 self-assert FAIL: % is not its pre-image plus only 0096''s hunks', v_fn;
    end if;
    if coalesce((select p.proacl::text from pg_proc p where p.oid = v_fn::regprocedure), '')
       is distinct from (select acl from defs_before_0096 where fn = v_fn) then
      raise exception '0096 self-assert FAIL: the re-cut moved the ACL of %', v_fn;
    end if;
  end loop;

  -- (b) EVERY MOVED REGION IS IN ITS CORE TO THE CHARACTER (with only the core's named hunks).
  for m in select * from moved_0096 loop
    select replace(pg_get_functiondef(p.oid), E'\r', '') into v_core
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname || '.' || p.proname = m.core;
    if v_core is null then
      raise exception '0096 self-assert FAIL: core % does not exist', m.core;
    end if;
    for h in select * from hunks_0096 where fn = m.core order by n desc loop
      v_n := (length(v_core) - length(replace(v_core, h.new, ''))) / length(h.new);
      if v_n <> 1 then
        raise exception '0096 self-assert FAIL: core hunk % of % is in the core % time(s), not once', h.n, m.core, v_n;
      end if;
      v_core := replace(v_core, h.new, h.old);
    end loop;
    if length(m.region) < 80 or strpos(v_core, m.region) = 0 then
      raise exception '0096 self-assert FAIL: the region moved out of % (% chars) is not verbatim in %', m.door, length(m.region), m.core;
    end if;
    -- ...and the door now hands that region to the core in one call.
    if strpos(pg_get_functiondef(m.door::regprocedure), m.core || '(') = 0 then
      raise exception '0096 self-assert FAIL: % does not call %', m.door, m.core;
    end if;
  end loop;

  -- (c) THE CORES ARE SERVER-ONLY, and absent from both registries.
  foreach v_fn in array c_cores loop
    if has_function_privilege('anon', v_fn, 'execute') or has_function_privilege('authenticated', v_fn, 'execute') then
      raise exception '0096 self-assert FAIL: a client role may execute the core %', v_fn;
    end if;
    if exists (select 1 from public.client_rpc_entry_points() e where e.fn = v_fn::regprocedure) then
      raise exception '0096 self-assert FAIL: the core % is a registered client entry point', v_fn;
    end if;
  end loop;
  -- REGISTRY ⊆ GRANTED (the stale trade_routes row is gone), and GRANTED WRITERS ⊆ REGISTRY.
  select array_agg(e.fn::text) into v_hits from public.client_rpc_entry_points() e
   where e.fn is null or not has_function_privilege('authenticated', e.fn, 'execute');
  if v_hits is not null then
    raise exception '0096 self-assert FAIL: registry row(s) authenticated cannot execute: %', v_hits;
  end if;
  if exists (select 1 from public.client_rpc_entry_points() e where e.function_name = 'trade_routes')
     or has_function_privilege('authenticated', 'world.trade_routes(uuid, uuid, numeric, integer, uuid)', 'execute') then
    raise exception '0096 self-assert FAIL: world.trade_routes is listed or reachable by a client';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0096 self-assert FAIL: a client write grant, a client-executable writer or a read-wall gap';
  end if;

  -- (d) THE EXECUTOR READS NO IDENTITY. The scan first proves it can see (a pg_temp function that
  --     carries the token must be reported), then must report nothing over the executor chain.
  create or replace function pg_temp.carrier_0096() returns uuid language sql as
    'select public.current_player_id()';
  select array_agg(x.fn) into v_pc
    from (select p.oid::regprocedure::text as fn, pg_get_functiondef(p.oid) as def
            from pg_proc p where p.oid = 'pg_temp.carrier_0096()'::regprocedure) x
   where x.def ~ '(auth\.uid\(\)|current_player_id\(\))';
  if coalesce(array_length(v_pc, 1), 0) <> 1 then
    raise exception '0096 self-assert FAIL: the identity scan cannot see its own positive control';
  end if;
  drop function pg_temp.carrier_0096();
  select array_agg(x.fn) into v_hits
    from (select p.oid::regprocedure::text as fn, pg_get_functiondef(p.oid) as def
            from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where (n.nspname = 'cmd' and (p.proname like 'do\_%' or p.proname in
                   ('advance', 'execute_order', 'run_standing_route', 'enqueue', 'parse', 'standing_route_lines',
                    'standing_route_tail', 'run_standing_provision', 'standing_route_close_lap')))
              or (n.nspname = 'voyage' and p.proname = 'settle')) x
   where x.def ~ '(auth\.uid\(\)|current_player_id\(\))';
  if v_hits is not null then
    raise exception '0096 self-assert FAIL: the executor reads an identity: % (positive control saw %)', v_hits, v_pc;
  end if;

  -- (e) THE FOUNDING'S EFFECT is 0004's, through the door, byte for byte (uuids and times aside).
  begin
    perform cmd.assume_identity(c_auth3);
    v_res := cmd.found_house('Casa da Prova', 'PRT');
    v_after := pg_temp.house_effect_0096((v_res->>'player_id')::uuid);
    raise exception using errcode = 'P0962', message = '0096 effect probe rollback';
  exception when sqlstate 'P0962' then
    null;
  end;
  if v_after is null or v_after is distinct from (select v from effect_0096 where k = 'before') then
    raise exception '0096 self-assert FAIL: the founding changed: before % after %', (select v from effect_0096 where k = 'before'), v_after;
  end if;
  begin
    perform public.new_house(null, 'Casa Sem Bandeira', 'XXX');
    raise exception '0096 self-assert FAIL: an unknown nation code founded a house';
  exception when sqlstate 'P0001' then
    if sqlerrm not like 'E_NO_SUCH_NATION%' then raise; end if;
  end;

  -- (f) THE PROBES — real houses, the real verbs, the tick; then rolled back.
  select count(*) into v_base from public.players;
  begin
    update public.world_config set value = to_jsonb(0.0) where key = 'hazard_p_max';
    update public.world_config set value = 'true'::jsonb where key = 'standing_routes_enabled';
    select id into v_lis from public.ports where code = 'LIS';
    select id into v_fnc from public.ports where code = 'FNC';
    select id into v_cad from public.ports where code = 'CAD';
    v_player  := public.new_house(c_auth,  'Casa do Ensaio', 'PRT');
    v_player2 := public.new_house(c_auth2, 'Casa Alheia', 'PRT', 'CAD', 'Alheia', 'carlat', 'Alheia', 50000);
    select id into v_fleet from public.fleets where player_id = v_player;
    select id into v_fleet2 from public.fleets where player_id = v_player2;
    if (select port_id from public.fleets where id = v_fleet2) <> v_cad
       or (select c.code from public.ships s join public.ship_classes c on c.id = s.class_id where s.fleet_id = v_fleet2) <> 'carlat'
       or (select ducats from public.players where id = v_player2) <> 50000 then
      raise exception '0096 self-assert FAIL: the generalised founding ignored its port, class or purse';
    end if;
    -- a merchant can never sign in
    begin
      update public.players set is_npc = true where id = v_player;
      raise exception '0096 self-assert FAIL: a company with a login was made a merchant';
    exception when check_violation then
      null;
    end;

    -- ── DOORS REFUSE ANOTHER COMPANY'S IDS (probe identity = the first house) ───────────────────
    perform cmd.assume_identity(c_auth2);
    v_preset := ((cmd.provision_preset_save(null, 'Alheia keep', 5))->>'id')::uuid;
    perform cmd.assume_identity(c_auth);
    v_refused := '';
    foreach v_fn in array array[
        cmd.hire_officer((select code from public.officers order by code limit 1), v_fleet2)->>'error_code',
        cmd.post_officer((select code from public.officers order by code limit 1), v_fleet2)->>'error_code',
        cmd.study_skill('NAVIGATION', v_fleet2)->>'error_code',
        cmd.provision_preset_apply(v_fleet2, null)->>'error_code',
        cmd.provision_preset_apply(v_fleet, v_preset)->>'error_code',
        cmd.provision_preset_save(v_preset, 'Mine now', 7)->>'error_code',
        cmd.clear(v_fleet2, false)->>'error_code',
        cmd.cancel_at(v_fleet2, null)->>'error_code',
        cmd.issue(v_fleet2, 'SAIL TO LIS')->>'error_code',
        cmd.divert(v_fleet2, v_lis, null, null)->>'error_code',
        cmd.trade_basket(v_fleet2, '[]'::jsonb, null)->>'error_code'] loop
      v_refused := v_refused || coalesce(v_fn, 'NULL') || ' ';
      if v_fn is null or v_fn not in ('E_NOT_YOUR_FLEET', 'E_NO_SUCH_FLEET', 'E_NO_SUCH_PRESET', 'E_NOT_IN_THE_ROOM') then
        raise exception '0096 self-assert FAIL: a door accepted another company''s id (%)', v_refused;
      end if;
    end loop;
    if (select provision_preset_id from public.fleets where id = v_fleet2) is not null
       or (select name from public.provision_presets where id = v_preset) <> 'Alheia keep' then
      raise exception '0096 self-assert FAIL: a door changed another company''s rows';
    end if;

    -- ── A ROUTE: two legs, served courses ──────────────────────────────────────────────────────
    select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
      into v_leg_lf from public.sea_reaches a, public.sea_reaches b where a.code = 'LIS' and b.code = 'FNC';
    v_leg_fl := jsonb_build_array(v_leg_lf->1, v_leg_lf->0);
    select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
      into v_leg_fc from public.sea_reaches a, public.sea_reaches b where a.code = 'FNC' and b.code = 'CAD';
    v_leg_cf := jsonb_build_array(v_leg_fc->1, v_leg_fc->0);
    select gl->>'code' into v_good
      from jsonb_array_elements(world.market(v_lis)->'goods') gl
     where (gl->>'offered')::boolean and (gl->>'available')::boolean and (gl->>'stock')::numeric >= 60
       and (gl->>'buy')::numeric between 5 and 60
     order by gl->>'code' limit 1;
    select id into v_good_id from public.goods where code = v_good;
    if v_good is null then
      raise exception '0096 self-assert FAIL: no good is bought at Lisbon for the probe';
    end if;
    v_preset := ((cmd.provision_preset_save(null, 'Route keep', 12))->>'id')::uuid;
    perform cmd.provision_preset_apply(v_fleet, v_preset);

    -- ── THE REPEATED HARBOUR: LIS → FNC → CAD → FNC; the cursor at the SECOND Funchal survives ──
    v_stops := jsonb_build_array(
      jsonb_build_object('port', 'LIS', 'course', v_leg_lf),
      jsonb_build_object('port', 'FNC', 'course', v_leg_fc),
      jsonb_build_object('port', 'CAD', 'course', v_leg_cf),
      jsonb_build_object('port', 'FNC', 'course', v_leg_fl, 'crew_up', true));
    v_route := ((cmd.standing_route_save(null, 'Twice Funchal', v_stops, 0, 20))->>'id')::uuid;
    if (select crew_up from public.standing_route_stops where route_id = v_route and ord = 3) is not true then
      raise exception '0096 self-assert FAIL: the stop option crew_up was not saved';
    end if;
    -- (1) BOUND FOR THE SECOND FUNCHAL: started at Cádiz (stop 2), she sails for stop 3 with the
    --     cursor at 3; an edit-save re-anchors on the harbour she is bound for — the old min(ord)
    --     anchor put the cursor at 1, the FIRST Funchal, and the lap boundary was never reached.
    update public.fleets set port_id = v_cad where id = v_fleet;
    update public.standing_routes set stop_cursor = 2 where id = v_route;
    v_res := cmd.standing_route_assign(v_route, v_fleet);
    select stop_cursor into v_cursor from public.standing_routes where id = v_route;
    if not coalesce((v_res->>'ok')::boolean, false) or v_cursor <> 3
       or (select status from public.fleets where id = v_fleet) <> 'SAILING' then
      raise exception '0096 self-assert FAIL: the repeated-harbour route would not start from Cádiz (cursor %, %): %',
        v_cursor, (select status from public.fleets where id = v_fleet), v_res;
    end if;
    perform cmd.standing_route_save(v_route, null, v_stops, null, null);
    if (select stop_cursor from public.standing_routes where id = v_route) <> 3 then
      raise exception '0096 self-assert FAIL: a save re-anchored a fleet bound for the second Funchal to cursor %',
        (select stop_cursor from public.standing_routes where id = v_route);
    end if;
    -- (2) DOCKED AT THE SECOND FUNCHAL, an assign starts from stop 3 (renders SAIL TO LIS, cursor 0);
    --     the old anchor started from stop 1 (SAIL TO CAD, cursor 2).
    perform cmd.standing_route_assign(v_route, null);
    perform cmd.clear(v_fleet, false);
    update public.voyages set status = 'ARRIVED' where fleet_id = v_fleet and status = 'SAILING';
    update public.fleets set status = 'DOCKED', port_id = v_fnc, lat = null, lon = null where id = v_fleet;
    update public.standing_routes set stop_cursor = 3 where id = v_route;
    v_res := cmd.standing_route_assign(v_route, v_fleet);
    if (select stop_cursor from public.standing_routes where id = v_route) <> 0
       or (select dest_port_id from public.voyages where fleet_id = v_fleet and status = 'SAILING') is distinct from v_lis then
      raise exception '0096 self-assert FAIL: assign at the second Funchal started from the first (cursor %): %',
        (select stop_cursor from public.standing_routes where id = v_route), v_res;
    end if;
    perform cmd.standing_route_assign(v_route, null);
    perform cmd.clear(v_fleet, false);
    update public.voyages set status = 'ARRIVED' where fleet_id = v_fleet and status = 'SAILING';
    update public.fleets set status = 'DOCKED', port_id = v_fnc, lat = null, lon = null where id = v_fleet;

    -- ── CREW_UP: the full render ends HIRE n, SAIL when short; only SAIL when not ──────────────
    update public.ships set crew = greatest(0, crew - 3) where fleet_id = v_fleet;
    v_lines := cmd.standing_route_lines(v_route, 3, v_fleet);
    if v_lines[array_length(v_lines, 1) - 1] <> format('HIRE %s', public.fleet_crew_shortfall(v_fleet))
       or v_lines[array_length(v_lines, 1)] <> 'SAIL TO LIS' or public.fleet_crew_shortfall(v_fleet) <> 3 then
      raise exception '0096 self-assert FAIL: a crew-short stop rendered %', v_lines;
    end if;
    v_lines := cmd.standing_route_lines(v_route, 2, v_fleet);
    if exists (select 1 from unnest(v_lines) x where x like 'HIRE %') then
      raise exception '0096 self-assert FAIL: a stop without crew_up rendered a HIRE';
    end if;
    update public.ships s set crew = c.crew_required from public.ship_classes c where c.id = s.class_id and s.fleet_id = v_fleet;
    v_lines := cmd.standing_route_lines(v_route, 3, v_fleet);
    if v_lines[array_length(v_lines, 1)] <> 'SAIL TO LIS' or exists (select 1 from unnest(v_lines) x where x like 'HIRE %') then
      raise exception '0096 self-assert FAIL: a fully crewed stop rendered %', v_lines;
    end if;
    -- ...and the SAIL-ON branch (her SAIL was refused and cleared; she is still at stop 3's harbour
    -- with the cursor on stop 0) renders the same tail: HIRE first, then the sail.
    update public.standing_routes set fleet_id = v_fleet, stop_cursor = 0, lap_id = null,
                                      paused_reason = null, hold_until = null where id = v_route;
    update public.ships set crew = greatest(0, crew - 2) where fleet_id = v_fleet;
    v_n := cmd.run_standing_route(v_fleet, now());
    select array_agg(o.raw_text order by o.seq) into v_lines from public.orders o
     where o.fleet_id = v_fleet and o.status = 'pending';
    if v_n <> 2 or v_lines is null or v_lines[1] <> 'HIRE 2' or v_lines[2] <> 'SAIL TO LIS' then
      raise exception '0096 self-assert FAIL: the sail-on branch rendered % line(s): %', v_n, v_lines;
    end if;
    perform cmd.clear(v_fleet, false);
    update public.ships s set crew = c.crew_required from public.ship_classes c where c.id = s.class_id and s.fleet_id = v_fleet;
    update public.standing_routes set fleet_id = null, lap_id = null where id = v_route;
    update public.fleets set port_id = v_lis where id = v_fleet;
    perform cmd.standing_route_delete(v_route);

    -- ── PACING: at v_per 1 a lap holds until one game-day after its LAST START; at 0, none ──────
    v_stops := jsonb_build_array(
      jsonb_build_object('port', 'LIS', 'course', v_leg_lf),
      jsonb_build_object('port', 'FNC', 'course', v_leg_fl));
    v_res := cmd.standing_route_save_for(v_player, null, 'Paced', v_stops, 0, 20, 1);
    v_route := (v_res->>'id')::uuid;
    if (select laps_per_game_day from public.standing_routes where id = v_route) <> 1 then
      raise exception '0096 self-assert FAIL: the route''s own pace was not written: %', v_res;
    end if;
    v_res := cmd.standing_route_assign(v_route, v_fleet);
    select started_at into v_start from public.standing_route_laps where route_id = v_route and lap_no = 1;
    -- the probe sails out and home: rewind each passage and tick, as the cron would.
    for v_n in 1 .. 2 loop
      update public.voyages set departed_at = departed_at - (eta - now()) - interval '1 minute', eta = now() - interval '1 minute'
       where fleet_id = v_fleet and status = 'SAILING';
      perform public.tick_arrivals(now());
    end loop;
    select hold_until into v_hold from public.standing_routes where id = v_route;
    if v_start is null or v_hold is null
       or abs(extract(epoch from (v_hold - (v_start + make_interval(secs => public.wc_num('game_day_seconds')::double precision))))) > 0.001
       or (select status from public.fleets where id = v_fleet) <> 'DOCKED'
       or (select count(*) from public.standing_route_laps where route_id = v_route and closed_at is not null) <> 1 then
      raise exception '0096 self-assert FAIL: interval pacing at 1/day held until % (lap 1 started %; status %)',
        v_hold, v_start, (select status from public.fleets where id = v_fleet);
    end if;
    -- the knob at 0 for this route: no hold — the next lap starts on the next wake.
    update public.standing_routes set laps_per_game_day = 0, hold_until = now() - interval '1 second' where id = v_route;
    perform public.tick_arrivals(now());
    if (select status from public.fleets where id = v_fleet) <> 'SAILING'
       or (select lap_no from public.standing_routes where id = v_route) <> 2 then
      raise exception '0096 self-assert FAIL: at pace 0 the route did not start its second lap (status %, lap %)',
        (select status from public.fleets where id = v_fleet), (select lap_no from public.standing_routes where id = v_route);
    end if;
    -- 0092's six-tick scenario, re-stated for the interval: with no pace at all, six ticks run three laps.
    for v_n in 1 .. 5 loop
      update public.voyages set departed_at = departed_at - (eta - now()) - interval '1 minute', eta = now() - interval '1 minute'
       where fleet_id = v_fleet and status = 'SAILING';
      perform public.tick_arrivals(now());
    end loop;
    if (select count(*) from public.standing_route_laps where route_id = v_route and closed_at is not null) <> 3 then
      raise exception '0096 self-assert FAIL: six ticks unpaced closed % lap(s), not 3',
        (select count(*) from public.standing_route_laps where route_id = v_route and closed_at is not null);
    end if;
    perform cmd.standing_route_assign(v_route, null);
    perform cmd.clear(v_fleet, false);

    -- ── D3: SELL x ALL over the allowance sells the allowance; an explicit quantity refuses whole ─
    update public.voyages set status = 'ARRIVED' where fleet_id = v_fleet and status = 'SAILING';
    update public.fleets set status = 'DOCKED', port_id = v_lis, lat = null, lon = null where id = v_fleet;
    perform public.fleet_load(v_fleet, v_good, 20, 1);
    insert into public.trade_daily (player_id, port_id, good_id, game_day, qty)
    select v_player, v_lis, v_good_id, world.game_day(),
           greatest(0, public.wc_num('daily_cap_fraction') * pg.stock_target - 10)
      from public.port_goods pg where pg.port_id = v_lis and pg.good_id = v_good_id
    on conflict (player_id, port_id, good_id, game_day) do update set qty = excluded.qty;
    v_cap := floor(world.daily_cap_remaining(v_player, v_lis, v_good_id));
    v_res := cmd.issue(v_fleet, format('SELL %s 15', v_good));
    select o.error_code into v_fail from public.orders o
     where o.fleet_id = v_fleet and o.verb = 'SELL' order by o.seq desc limit 1;
    perform cmd.clear(v_fleet, false);   -- the halt law: a failed order stops the queue until cleared
    v_res := cmd.issue(v_fleet, format('SELL %s ALL', v_good));
    select coalesce((o.result->>'qty')::numeric, 0) into v_sold from public.orders o
     where o.fleet_id = v_fleet and o.verb = 'SELL' and o.status = 'done' order by o.seq desc limit 1;
    perform cmd.clear(v_fleet, false);
    if v_cap <> 10 or v_fail is distinct from 'E_DAILY_CAP' or v_sold <> v_cap
       or public.fleet_cargo_qty(v_fleet, v_good) <> 20 - v_cap then
      raise exception '0096 self-assert FAIL: D3 — allowance %, explicit 15 answered %, ALL sold % (left %)',
        v_cap, v_fail, v_sold, public.fleet_cargo_qty(v_fleet, v_good);
    end if;

    -- ── RECONCILE still raises on a falsified purse (0010:280's test) ─────────────────────────
    begin
      update public.players set ducats = ducats + 1 where id = v_player;
      perform public.tick_reconcile();
      raise exception '0096 self-assert FAIL: reconcile passed a falsified purse';
    exception when others then
      if sqlerrm like '0096 self-assert FAIL%' then raise; end if;
    end;

    raise exception using errcode = 'P0960', message = '0096 probe rollback';
  exception when sqlstate 'P0960' then
    null;
  end;

  if (select count(*) from public.players) <> v_base
     or exists (select 1 from public.players where auth_uid in (c_auth, c_auth2, c_auth3) or is_npc) then
    raise exception '0096 self-assert FAIL: the probe leaked a house, or a merchant exists';
  end if;
  if public.standing_routes_on() is distinct from (select (value)::text = 'true' from public.world_config where key = 'standing_routes_enabled') then
    raise exception '0096 self-assert FAIL: the switch reading moved';
  end if;

  raise notice '0096 self-assert ok: A FLEET IS FORMED BY THE SAME HANDS. % re-cut door(s) reverse to their pre-images hunk by hunk with ACLs unmoved; % moved region(s) live verbatim in their server-only cores (sign_officer, post_officer_to, raise_skill, the preset, route and clear cores); commission_ship is the one ship insert (new_house, do_build) and form_fleet the one fleet insert; % core(s) refused to anon/authenticated and absent from both registries; every registry row is executable by authenticated (the stale trade_routes row is gone) and no client-executable writer is unregistered; the identity scan saw its positive control (%) and found none in the executor; the founding''s effect through cmd.found_house is 0004''s; an unknown nation raises. On thrown-away houses: every door refused another company''s ids (%); a loop calling twice at Funchal kept its cursor through a start, a save and an assign; crew_up rendered HIRE n then SAIL in the full render and in the sail-on branch; interval pacing held one game-day after the last start, none at pace 0, and six unpaced ticks ran three laps; D3 sold the allowance on ALL and refused an explicit 15 whole; reconcile still raised on a falsified purse. Rolled back.',
    (select count(distinct fn) from hunks_0096 where fn like '%(%'), (select count(*) from moved_0096),
    array_length(c_cores, 1), v_pc, btrim(v_refused);
end $$;
