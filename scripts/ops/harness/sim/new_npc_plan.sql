CREATE OR REPLACE FUNCTION public.npc_plan(p_now timestamp with time zone DEFAULT now(), p_route uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- Writes each merchant route's STOPS and LINES from the market through cmd.standing_route_save_for.
-- Every leg's lines come from THE leg planner (public.npc_leg_lines: 0114's rank, filter, size,
-- keep); this function decides WHICH LOOP and writes it.
--   * A PASS (p_route null — the switch) or a route not at a lap start: her present loop, re-lined.
--   * A LAP START (p_route named, her fleet docked at her stop 0 with no open lap): her present
--     loop and up to npc_route_candidates others (public.npc_loop_candidates; 0186: only when hers leaves
--     her nothing, she lies off it, or on a review lap, every npc_route_review_laps-th), each priced through
--     the leg planner with every distinct leg priced once, scored in ducats per REAL hour of the
--     lap — sea time at her speed through time_compression, plus her rest (route_rest_voyage_days).
--     0142: the ducats are what the lap LEAVES her — the parcels' profit after tax, less the wages
--     every sea-day of the loop owes and the stores it eats — and the loop she sails, chosen or
--     kept, has her preset raised to cover its longest leg. She repairs at its first shipyard.
--     0152: a loop with a shipyard that pays (TIER 1) outranks every loop without one — a yardless
--     loop is chosen only when no loop with a yard pays — and a higher tier switches outright.
--   * DOCKED OFF HER LOOP (0152: towed to a shipyard her loop does not call at; p_route named): the
--     same choice from where she lies, her present loop never kept (it cannot be sailed from there).
--     The best wins when it beats her present loop by npc_route_switch_pct; a longer leg than her
--     stores cover raises her preset through cmd.provision_preset_save_for first (the candidates
--     already stop at npc_preset_days_max and half her hold), and a refused raise keeps her loop.
--     Counted `chosen`; the loops priced, `candidates`.
--   * 0186: THE LOOP WRITTEN DOES NOT PAY — what a lap of it leaves her (the net above: the parcels'
--     profit after tax, less the loop's wages and stores) is nothing or less, whether or not some leg
--     carries a parcel: it is written as it stands with NO BUY — SELL at a profit at every stop (and
--     0142's cut-loss) — so she never buys into a loss. Counted `ballast`. Mid-lap, off her loop, on the switch's pass or with
--     cargo aboard she sails it in ballast (0115). 0181: AT HER LAP START, WITH NOTHING ABOARD, SHE
--     WAITS IN PORT — laid up ('laid_up', written once) and counted `waiting`; public.npc_tend_route
--     re-plans her at every tend and resumes her on the first loop that pays.
-- The pass takes the route planned LONGEST AGO first (updated_at) and defers past the upkeep
-- budget (public.npc_upkeep_spent); a route not reached is counted `deferred`, never half-planned.
-- Routes paused 'error' or 'laid_up' are skipped by the pass; npc_tend re-plans one alone.
-- Locks fleet then route, NOWAIT: a busy route is skipped, never waited for.
declare
  v_pace    int     := public.wc_int('npc_laps_per_game_day');
  v_cand    int     := public.wc_int('npc_route_candidates');
  v_switch  numeric := public.wc_num('npc_route_switch_pct');
  v_review  int     := public.wc_int('npc_route_review_laps');   -- 0186
  v_emargin numeric := public.wc_num('endurance_margin');
  v_comp    numeric := public.wc_num('time_compression');
  v_rest_h  numeric := public.wc_num('route_rest_voyage_days') * 86400 / public.wc_num('time_compression') / 3600;
  v_day_h   numeric := public.wc_num('game_day_seconds') / 3600;   -- the daily cap's period, in real hours
  r         record;
  lp        record;
  sr        public.standing_routes%rowtype;
  f         public.fleets%rowtype;
  v_n       int;
  v_hold    numeric;
  v_crew    int;
  v_speed   numeric;
  v_choose  boolean;
  v_loops   jsonb;
  v_loop    jsonb;
  v_len     int;
  v_memo    jsonb;
  v_key     text;
  v_leg     jsonb;
  v_from    uuid;
  v_to      uuid;
  v_stops   jsonb;
  v_profit  numeric;
  v_nm      numeric;
  v_maxnm   numeric;
  v_any     boolean;
  v_score   numeric;
  v_cur_stops jsonb;
  v_cur_score numeric;
  v_cur_any boolean;
  v_best_i  int;
  v_best_stops jsonb;
  v_best_score numeric;
  v_best_any boolean;
  v_best_maxnm numeric;
  v_cur_maxnm numeric;   -- 0142: her present loop's longest leg
  v_wages   numeric;     -- 0142: what every sea-day of a loop owes
  v_net     numeric;     -- 0142: what a lap of the loop leaves her
  v_cur_net numeric;     -- 0142
  v_best_net numeric;    -- 0142
  v_rep     boolean;     -- 0142: a REPAIR is written on this loop already
  v_yard    boolean;     -- 0142: this stop has a shipyard (public.port_has_shipyard)
  v_sea_d   numeric;     -- 0142: the loop's days at sea
  v_try     int;         -- 0142
  v_off     boolean;     -- 0152: she lies docked at a port her loop does not call at
  v_tier    int;         -- 0152: 1 = a shipyard on the loop and it pays; 0 otherwise; -1 = unsailable
  v_cur_tier int;        -- 0152
  v_best_tier int;       -- 0152
  v_days    int;
  v_preset  int;
  v_res     jsonb;
  i         int;
  j         int;
  v_planned int := 0;
  v_laid    int := 0;
  v_busy    int := 0;
  v_failed  int := 0;
  v_deferred int := 0;
  v_chosen  int := 0;
  v_cands   int := 0;
  v_waiting int := 0;      -- 0181: laid up at her lap start, nothing paying on any loop
  v_aboard  numeric;       -- 0181: the tuns she carries now (public.ship_cargo_tuns)
  v_pays    boolean;       -- 0186: the loop she will sail leaves her more than nothing a lap
  v_notes   jsonb := '[]'::jsonb;
begin
  if not public.npc_traders_on() then
    return jsonb_build_object('enabled', false);
  end if;
  for r in
    select nf.fleet_id, nf.route_id
      from public.npc_fleets nf
      join public.players p on p.id = nf.player_id and p.is_npc
      join public.standing_routes sr0 on sr0.id = nf.route_id
     where (p_route is null and coalesce(sr0.paused_reason, '') not in ('error', 'laid_up'))
        or nf.route_id = p_route
     order by sr0.updated_at, nf.roster_ord
  loop
    -- THE BUDGET (0114). Past the upkeep's deadline a route is not begun.
    if public.npc_upkeep_spent() then
      v_deferred := v_deferred + 1;
      continue;
    end if;
    begin
      -- FLEET BEFORE ROUTE, and never wait (§4.5).
      perform 1 from public.fleets where id = r.fleet_id for update nowait;
      select * into sr from public.standing_routes where id = r.route_id for update nowait;
      select * into f from public.fleets where id = r.fleet_id;
      select count(*) into v_n from public.standing_route_stops where route_id = sr.id;
      select coalesce(sum(c.crew_required), 0), coalesce(sum(public.ship_cargo_tuns(s.id)), 0)
        into v_crew, v_hold
        from public.ships s join public.ship_classes c on c.id = s.class_id
       where s.fleet_id = r.fleet_id;
      v_aboard := v_hold;   -- 0181: what she carries, before her free hold is added
      v_hold  := v_hold + public.fleet_free_hold(r.fleet_id);
      v_speed := greatest(coalesce(voyage.fleet_speed(r.fleet_id), 0), 0.1);

      -- LOOP 0 IS HER PRESENT LOOP.
      select jsonb_agg(jsonb_build_object('port_id', s.port_id, 'code', p.code, 'course', s.course) order by s.ord)
        into v_loop
        from public.standing_route_stops s join public.ports p on p.id = s.port_id
       where s.route_id = sr.id;
      v_loops := jsonb_build_array(v_loop);

      -- THE CHOICE, at her lap start only: planned alone, her fleet lying at her stop 0 between
      -- laps. The switch's pass (p_route null) and a route mid-lap keep their loop.
      -- 0152: OR SHE LIES DOCKED OFF HER LOOP — the candidates start where she lies.
      v_off := p_route is not null and sr.fleet_id = r.fleet_id and f.status = 'DOCKED'
               and not exists (select 1 from public.standing_route_stops s0
                                where s0.route_id = sr.id and s0.port_id = f.port_id);
      v_choose := (p_route is not null and v_cand > 0 and sr.fleet_id = r.fleet_id and sr.lap_id is null
                  and f.status = 'DOCKED' and f.port_id = (v_loop->0->>'port_id')::uuid)
                  or (v_off and v_cand > 0);
      -- 0186: the loops on offer are fetched once her present loop is priced (below).

      -- PRICE EVERY LOOP through the leg planner, each distinct leg once.
      v_memo := '{}'::jsonb;
      v_best_i := 0;
      i := 0;
      while i < jsonb_array_length(v_loops) loop   -- 0186: the candidates join after loop 0
        v_loop   := v_loops->i;
        v_len    := jsonb_array_length(v_loop);
        v_stops  := '[]'::jsonb;
        v_profit := 0;
        v_nm     := 0;
        v_maxnm  := 0;
        v_any    := false;
        v_wages  := 0;       -- 0142
        v_rep    := false;   -- 0142
        for j in 0 .. v_len - 1 loop
          v_from := (v_loop->j->>'port_id')::uuid;
          v_to   := (v_loop->((j + 1) % v_len)->>'port_id')::uuid;
          v_key  := v_from::text || '>' || v_to::text;
          if v_memo ? v_key then
            v_leg := v_memo->v_key;
          else
            v_leg  := public.npc_leg_lines(sr.id, v_from, v_to, v_hold, v_crew, v_speed);
            v_memo := v_memo || jsonb_build_object(v_key, v_leg);
          end if;
          -- 0142: SHE REPAIRS AT THE FIRST STOP OF THE LOOP THAT HAS A SHIPYARD (public.port_has_shipyard,
          -- the reading cmd.do_repair refuses E_NO_YARD by) — never where no yard is.
          v_yard   := not v_rep and public.port_has_shipyard(v_from);
          v_rep    := v_rep or v_yard;
          v_stops  := v_stops || jsonb_build_object('port', v_loop->j->>'code', 'course', v_loop->j->'course',
                                                   'repair', v_yard, 'crew_up', true, 'lines', v_leg->'lines');
          v_profit := v_profit + coalesce((v_leg->>'profit')::numeric, 0);
          v_wages  := v_wages + coalesce((v_leg->>'wages')::numeric, 0);   -- 0142
          v_nm     := v_nm + coalesce((v_leg->>'nm')::numeric, 0);
          v_maxnm  := greatest(v_maxnm, coalesce((v_leg->>'nm')::numeric, 0));
          v_any    := v_any or coalesce((v_leg->>'any')::boolean, false);
        end loop;
        -- DUCATS PER REAL HOUR of the lap: nm / kn is voyage-hours; through the compression, real;
        -- plus her rest; and never less than a game-day, because the daily cap lets her buy a
        -- parcel once a game-day — a five-minute hop does not sell its parcel eleven times an hour.
        -- 0142: WHAT THE LAP LEAVES HER — the parcels' profit after tax, less the wages every sea-day
        -- of the loop owes (paid from that profit and never past it: public.wages_from_profit, once
        -- for the loop, so a ballast leg's days count), less the stores the loop eats
        -- (public.stores_cost, the price cmd.do_provision charges, for her crew over nm / kn days).
        v_sea_d := v_nm / (v_speed * 24);
        v_net   := v_profit - public.wages_from_profit(v_wages, v_profit)
                   - public.stores_cost(sr.player_id, v_crew * public.wc_num('water_per_crew_day') * v_sea_d,
                                        v_crew * public.wc_num('food_per_crew_day') * v_sea_d);
        v_score := v_net / greatest(v_nm / v_speed / v_comp + v_rest_h, v_day_h);
        -- 0152: THE TIER (owner default, 2026-10-17): a shipyard on the loop (v_rep — the REPAIR
        -- written above) AND it pays is tier 1, else 0; her present loop, when she lies off it, -1.
        -- The best is the highest tier, then the best per real hour.
        v_tier := public.npc_loop_tier(v_rep, v_net, i = 0 and v_off);
        if i = 0 then
          v_cur_stops := v_stops; v_cur_score := v_score; v_cur_any := v_any; v_cur_maxnm := v_maxnm; v_cur_net := v_net;
          v_best_stops := v_stops; v_best_score := v_score; v_best_any := v_any; v_best_maxnm := v_maxnm; v_best_net := v_net;
          v_cur_tier := v_tier; v_best_tier := v_tier;   -- 0152
        elsif public.npc_loop_beats(v_tier, v_score, v_best_tier, v_best_score) then
          v_best_i := i; v_best_stops := v_stops; v_best_score := v_score; v_best_any := v_any; v_best_maxnm := v_maxnm; v_best_net := v_net;
          v_best_tier := v_tier;   -- 0152
        end if;
        -- 0186: HER PRESENT LOOP IS PRICED FIRST, and the loops on offer (public.npc_loop_candidates) are
        -- fetched and priced only when it leaves her nothing, when she lies off it, or on a review lap
        -- (every npc_route_review_laps-th): a loop that pays is kept between reviews without pricing
        -- fifteen others at every lap start — the trade loops' long legs cost the arrivals sweep.
        if i = 0 and v_choose and (v_net <= 0 or v_off or sr.lap_no % greatest(v_review, 1) = 0) then
          for lp in select * from public.npc_loop_candidates(sr.id, r.fleet_id, f.port_id, v_hold, v_speed) loop
            exit when jsonb_array_length(v_loops) >= v_cand;
            v_loops := v_loops || jsonb_build_array(lp.stops);
          end loop;
        end if;
        i := i + 1;
      end loop;
      v_cands := v_cands + jsonb_array_length(v_loops);

      -- SHE CHANGES LOOP only when the best pays npc_route_switch_pct more per hour than her own.
      -- 0152: a HIGHER TIER switches outright (a paying loop with a shipyard over one without; any
      -- loop over the one she lies off); within a tier, npc_route_switch_pct as before.
      if v_best_i <> 0 and not public.npc_loop_switches(v_best_tier, v_best_score, v_cur_tier, v_cur_score, v_switch) then
        v_best_i := 0;
      end if;
      -- A LONGER LEG THAN HER STORES COVER raises her preset through the preset core. 0142: FOR THE
      -- LOOP SHE WILL SAIL, chosen or kept — a kept loop was never measured again, her speed moved
      -- under it, and her SAIL was refused E_ENDURANCE for ever. A chosen loop whose raise is
      -- refused is not chosen, and her present loop is measured in turn.
      for v_try in 1 .. 2 loop
        v_days := ceil((case when v_best_i <> 0 then v_best_maxnm else v_cur_maxnm end)
                       / (v_speed * 24) * v_emargin)::int + 1;
        -- 0150: AND, FOR THE LOOP SHE KEEPS, NEVER LESS THAN THE PASSAGE HER SAIL WAS REFUSED FOR
        -- (public.sail_refused_days — the SAIL's own measure of the course, 2-7 % past the reach
        -- table's nm on a long leg).
        if v_best_i = 0 then
          v_days := greatest(v_days, public.sail_refused_days(f.id));
        end if;
        select pr.days into v_preset from public.provision_presets pr where pr.id = f.provision_preset_id;
        exit when v_preset is null or v_days <= v_preset;
        v_res := cmd.provision_preset_save_for(sr.player_id, f.provision_preset_id, null, v_days);
        exit when coalesce((v_res->>'ok')::boolean, false);
        v_notes := v_notes || jsonb_build_object('route', sr.name, 'preset_refused', v_res->>'error_code');
        exit when v_best_i = 0;
        v_best_i := 0;
      end loop;
      if v_best_i <> 0 then
        v_stops := v_best_stops; v_any := v_best_any;
        v_chosen := v_chosen + 1;
        v_notes := v_notes || jsonb_build_object('route', sr.name, 'chosen',
                     (select string_agg(x->>'port', '-' order by k) from jsonb_array_elements(v_best_stops) with ordinality t(x, k)),
                     'per_hour', round(v_best_score), 'was', round(v_cur_score),
                     'net', round(v_best_net), 'was_net', round(v_cur_net),   -- 0142
                     'yard', v_best_tier = 1, 'off_loop', v_off);               -- 0152
      else
        v_stops := v_cur_stops; v_any := v_cur_any;
      end if;

      -- 0186: A LOOP PAYS WHEN A LAP OF IT LEAVES HER MORE THAN NOTHING — the net the score is made of
      -- (parcels' profit after tax, less the wages its sea-days owe and the stores it eats), not when some
      -- leg carries a parcel (0115/0181's v_any): a loop whose parcels do not cover her wages and stores
      -- lost the same few ducats every lap (the owner, 2026-10-18: "why is there a route that has no
      -- profit? this is design defect"). One that does not pay is written with no BUY — SELL at a profit
      -- at every stop, and the cut-loss — so she buys nothing into a loss. Counted `ballast`.
      v_pays := coalesce(case when v_best_i <> 0 then v_best_net else v_cur_net end, 0) > 0;
      if not v_pays then
        v_laid := v_laid + 1;
        select jsonb_agg(x || jsonb_build_object('lines',
                 coalesce((select jsonb_agg(l order by o) from jsonb_array_elements(x->'lines') with ordinality u(l, o)
                            where l->>'kind' <> 'BUY'), '[]'::jsonb)) order by k)
          into v_stops from jsonb_array_elements(v_stops) with ordinality t(x, k);
      end if;
      v_res := cmd.standing_route_save_for(sr.player_id, sr.id, null, v_stops, null, null, v_pace);
      if not coalesce((v_res->>'ok')::boolean, false) then
        raise exception 'npc_plan: the save door refused % — %', sr.name, v_res->>'error_message';
      end if;
      v_planned := v_planned + 1;
      -- 0181: AT HER LAP START, WITH NOTHING ABOARD, SHE WAITS IN PORT instead of sailing a lap that
      -- pays only its stores (the owner, 2026-10-18: "redesign the routes ... that gives negative
      -- cash"). Every loop on offer was priced above and none carries a paying parcel: she is laid
      -- up where she lies, once (a lay-up already standing is not written again), and counted
      -- `waiting`. cmd.run_standing_route does not open a lap its plan paused (0114), and
      -- public.npc_tend_route re-plans her at every tend. With cargo aboard she sails (her SELLs and
      -- 0142's cut-loss clear it); mid-lap, off her loop or on the switch's pass, as before.
      -- 0186: and "none pays" is v_pays — every loop on offer was priced and the best leaves her nothing.
      if not v_pays and v_choose and not v_off and coalesce(v_aboard, 0) <= 0 then
        v_waiting := v_waiting + 1;
        if sr.paused_reason is distinct from 'laid_up' then
          v_res := cmd.standing_route_pause_for(sr.player_id, sr.id, true, 'laid_up',
                     'No loop of hers pays its wages and stores at present; she waits in port.');
          if not coalesce((v_res->>'ok')::boolean, false) then
            raise exception 'npc_plan: the pause door refused % — %', sr.name, v_res->>'error_message';
          end if;
        end if;
      end if;
    exception
      when lock_not_available then
        v_busy := v_busy + 1;
      when others then
        v_failed := v_failed + 1;
        v_notes := v_notes || jsonb_build_object('route', r.route_id, 'error', sqlerrm);
    end;
  end loop;

  return jsonb_build_object('enabled', true, 'planned', v_planned, 'ballast', v_laid,
                            'chosen', v_chosen, 'candidates', v_cands, 'waiting', v_waiting,   -- 0181
                            'busy', v_busy, 'failed', v_failed, 'deferred', v_deferred, 'notes', v_notes);
end $function$

