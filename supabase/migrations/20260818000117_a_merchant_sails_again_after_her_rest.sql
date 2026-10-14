-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0117 — A MERCHANT SAILS AGAIN THE MOMENT HER REST IS OVER
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER'S WORDS ───────────────────────────────────────────────────────────────────────────
-- 2026-10-14: remove the merchant lap pacing, so that the two-minute rest (0116) is the ONLY wait
-- at home. Server load is fine.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) `npc_laps_per_game_day` goes from 6 to 0. docs/NPC_TRADERS.md §4.2: 0 means she starts her
--     next lap the moment she can. cmd.run_standing_route (0096) reads the route's own
--     laps_per_game_day, falling back to the knob, and applies no interval when it is 0. Only the
--     0101 rest floor then holds her.
-- (2) Every merchant route's own laps_per_game_day is re-saved to 0 THROUGH THE ONE DOOR,
--     cmd.standing_route_save_for. The route's stops, courses and lines are passed back exactly as
--     they stand, the same call npc_plan makes, so the door re-anchors her cursor as it always does.
--     Nobody updates the column by hand.
-- Players are untouched: `standing_route_laps_per_game_day` and every player route keep their pace.
--
-- Self-asserts hold AS FOUND (0113).

do $guard$ begin perform set_config('statement_timeout', '20min', true); end $guard$;

update public.world_config set value = to_jsonb(0),
       description = '0117: laps a merchant route may START per game-day (cmd.run_standing_route''s pacing). 0: '
                     'no pacing — the 0101 rest at home (route_rest_voyage_days) is her only wait between laps.'
 where key = 'npc_laps_per_game_day';

do $$
declare
  v_was_on  boolean := public.npc_traders_on();
  r         record;
  v_stops   jsonb;
  v_res     jsonb;
  v_n       int := 0;
  v_edited0 int;
  v_left    int;
  v_players int;
  v_players0 bigint;
begin
  select count(*) into v_edited0 from public.npc_fleets nf join public.standing_routes sr on sr.id = nf.route_id
   where sr.paused_reason = 'edited';
  select coalesce(sum(coalesce(sr.laps_per_game_day, -1)), 0) into v_players0
    from public.standing_routes sr join public.players p on p.id = sr.player_id and not p.is_npc;

  -- (1) THE KNOB.
  if public.wc_int('npc_laps_per_game_day') <> 0 then
    raise exception '0117 self-assert FAIL: npc_laps_per_game_day reads %', public.wc_int('npc_laps_per_game_day');
  end if;

  -- (2) EVERY MERCHANT ROUTE, THROUGH THE DOOR, with what it already holds.
  for r in select sr.id, sr.player_id, sr.name
             from public.npc_fleets nf join public.standing_routes sr on sr.id = nf.route_id
            where sr.laps_per_game_day is distinct from 0
            order by nf.roster_ord, sr.id loop
    select jsonb_agg(jsonb_build_object(
             'port', p.code, 'course', s.course, 'repair', s.repair, 'crew_up', s.crew_up,
             'lines', coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                                  'kind', l.kind, 'good', g.code, 'qty', l.qty,
                                  'price_limit', l.price_limit, 'at_profit', l.at_profit)) order by l.ord)
                                  from public.standing_route_lines l left join public.goods g on g.id = l.good_id
                                 where l.route_id = s.route_id and l.stop_ord = s.ord), '[]'::jsonb))
             order by s.ord)
      into v_stops
      from public.standing_route_stops s join public.ports p on p.id = s.port_id
     where s.route_id = r.id;
    v_res := cmd.standing_route_save_for(r.player_id, r.id, null, v_stops, null, null, 0);
    if not coalesce((v_res->>'ok')::boolean, false) then
      raise exception '0117 self-assert FAIL: the door refused % — %', r.name, v_res;
    end if;
    v_n := v_n + 1;
  end loop;

  select count(*) into v_left from public.npc_fleets nf join public.standing_routes sr on sr.id = nf.route_id
   where sr.laps_per_game_day is distinct from 0;
  if v_left <> 0 then
    raise exception '0117 self-assert FAIL: % merchant route(s) still paced', v_left;
  end if;
  -- the door re-anchored every one of them: none was paused 'edited' by the re-save.
  if (select count(*) from public.npc_fleets nf join public.standing_routes sr on sr.id = nf.route_id
       where sr.paused_reason = 'edited') > v_edited0 then
    raise exception '0117 self-assert FAIL: the re-save left merchant routes paused edited';
  end if;
  -- players untouched.
  if (select coalesce(sum(coalesce(sr.laps_per_game_day, -1)), 0)
        from public.standing_routes sr join public.players p on p.id = sr.player_id and not p.is_npc) <> v_players0 then
    raise exception '0117 self-assert FAIL: a player route''s pace moved';
  end if;
  if public.npc_traders_on() is distinct from v_was_on then
    raise exception '0117 self-assert FAIL: the switch was not left as found';
  end if;

  raise notice '0117 self-assert ok: A MERCHANT SAILS AGAIN THE MOMENT HER REST IS OVER. npc_laps_per_game_day 0; '
    '% merchant route(s) re-saved through cmd.standing_route_save_for with laps_per_game_day 0, none paused edited; '
    'player routes untouched. Switch as found (%).', v_n, case when v_was_on then 'lit' else 'dark' end;
end $$;
