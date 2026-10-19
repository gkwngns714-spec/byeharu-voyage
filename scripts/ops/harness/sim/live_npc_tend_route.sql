CREATE OR REPLACE FUNCTION public.npc_tend_route(p_now timestamp with time zone, p_fleet uuid, p_route uuid, p_k bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- 0137: ONE merchant's upkeep — public.npc_tend's per-route body, moved verbatim (fleet then route
-- locked NOWAIT in its own subtransaction; a busy route is skipped and counted). Returns this
-- merchant's counts; public.npc_tend_sum adds them up. Called by npc_tend (one transaction) and by
-- the hourly public.tick_reconcile (one transaction PER MERCHANT, so the locks she takes are held
-- for her step and no longer).
declare
  v_on      boolean := public.npc_traders_on();
  v_max     int     := public.wc_int('npc_fleet_max');
  r         record;
  sr        public.standing_routes%rowtype;
  f         public.fleets%rowtype;
  fo        public.orders%rowtype;
  v_res     jsonb;
  v_clears  int;
  v_dark    int := 0;
  v_started int := 0;
  v_resumed int := 0;
  v_cleared int := 0;
  v_laid_n  int := 0;
  v_busy    int := 0;
  v_failed  int := 0;
  v_deferred int := 0;
  v_notes   jsonb := '[]'::jsonb;
  v_built   int := 0;   -- 0180 (d): hulls she laid down this hour
  v_waiting int := 0;   -- 0181: laid up in port, nothing on her loops paying
begin
  for r in select p_fleet as fleet_id, p_route as route_id, p_k as k loop   -- 0137: one row
    begin
      perform 1 from public.fleets where id = r.fleet_id for update nowait;
      select * into sr from public.standing_routes where id = r.route_id for update nowait;
      select * into f from public.fleets where id = r.fleet_id;

      if not v_on or r.k > v_max then
        if sr.fleet_id is not null and sr.paused_reason is distinct from 'dark' then
          perform cmd.standing_route_pause_for(sr.player_id, sr.id, true, 'dark', 'The merchants keep to port.');
          v_dark := v_dark + 1;
        end if;
        continue;
      end if;

      -- 0152: A WRECK IN PORT IS TOWED (owner default, 2026-10-17) through public.tow_for — THE tow,
      -- the one a player presses — to the nearest harbour with a shipyard, and her REPAIR is queued
      -- there the way a player queues it (cmd.parse, cmd.enqueue, cmd.advance). Repaired off her
      -- loop, the off_route branch below chooses her loop afresh. A tow her fortune will not pay
      -- (E_TOW_FUNDS) is noted and she is counted below, as before.
      if f.status = 'UNABLE_TO_SAIL' and f.port_id is not null then
        begin
          v_res := public.tow_for(sr.player_id, r.fleet_id);
          v_res := v_res || jsonb_build_object('repair_queued', cmd.enqueue(sr.player_id,
                     jsonb_set(cmd.parse(sr.player_id, r.fleet_id, 'REPAIR'), '{fleet_id}', to_jsonb(r.fleet_id::text)),
                     'REPAIR', null, null)->'ok');
          perform cmd.advance(r.fleet_id, p_now);
          v_notes := v_notes || jsonb_build_object('route', sr.name, 'towed', v_res->>'to',
                                                   'nm', v_res->'nm', 'fee', v_res->'fee',
                                                   'repair_queued', v_res->'repair_queued');
          continue;
        exception when others then
          if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
          v_notes := v_notes || jsonb_build_object('route', sr.name, 'tow_refused', split_part(sqlerrm, ':', 1));
        end;
      end if;
      if f.status in ('ADRIFT', 'UNABLE_TO_SAIL') then
        -- 0115: NOT PARKED. No verb refloats a fleet that cannot sail — for anybody — so she is
        -- counted in the receipt and her route is left as it is; the executor waits for her.
        -- 0152: a wreck in port is towed above; what reaches here is ADRIFT, a wreck at sea, or a
        -- tow refused.
        v_laid_n := v_laid_n + 1;
        v_notes := v_notes || jsonb_build_object('route', sr.name, 'cannot_sail', f.status);
        continue;
      end if;

      -- A PAUSE THE WORLD MAY LIFT, and only when it may: dark/losing/reserve/edited at once;
      -- laid_up after npc_laid_up_hours; error after 6 h (updated_at dates the pause — the hourly
      -- plan skips error routes, so it cannot keep the date fresh). off_route re-assigns where she
      -- lies, if that is a stop. 'player' is never a merchant's.
      --
      -- updated_at DATES A PAUSE ONLY WHILE NOTHING HAS WRITTEN THE ROUTE SINCE. That holds for
      -- 'error' (the plan skips those) and it is what the ageing test below reads; it does NOT hold
      -- after the plan has saved — see the receipt test further down.
      if sr.paused_reason = 'off_route' then
        -- 0152: DOCKED OFF HER LOOP (towed to a shipyard her loop does not call at): her loop is
        -- chosen afresh from where she lies (public.npc_plan), and she is assigned there below.
        if f.status = 'DOCKED'
           and not exists (select 1 from public.standing_route_stops s where s.route_id = sr.id and s.port_id = f.port_id) then
          perform public.npc_plan(p_now, sr.id);
        end if;
        if f.status = 'DOCKED'
           and exists (select 1 from public.standing_route_stops s where s.route_id = sr.id and s.port_id = f.port_id) then
          v_res := cmd.standing_route_assign_for(sr.player_id, sr.id, r.fleet_id);
          v_resumed := v_resumed + 1;
        else
          v_notes := v_notes || jsonb_build_object('route', sr.name, 'off_route', f.status);
        end if;
        continue;
      end if;
      if sr.paused_reason is not null
         and not (sr.paused_reason in ('dark', 'losing', 'reserve', 'edited', 'laid_up')   -- 0115: laid_up at once
                  or (sr.paused_reason = 'error' and sr.updated_at < p_now - interval '6 hours')) then
        continue;
      end if;

      -- 0114: THE BUDGET gates the dear work only — a plan and a start or a resume, and the halt
      -- law's release below. The dark and cannot-sail lay-ups above stay unconditional.
      if (sr.fleet_id is null or sr.paused_reason is not null) and public.npc_upkeep_spent() then
        v_deferred := v_deferred + 1;
        continue;
      end if;

      -- NOT STARTED, OR A PAUSE TO LIFT: plan first (the lines are the market's NOW), then start
      -- her where she lies, or resume her. The plan may lay her up (nothing pays): then she waits.
      if sr.fleet_id is null or sr.paused_reason is not null then
        if sr.paused_reason = 'error' then
          v_notes := v_notes || jsonb_build_object('route', sr.name, 'resumed_after_error', true);
        end if;
        v_res := public.npc_plan(p_now, sr.id);
        select * into sr from public.standing_routes where id = r.route_id;
        -- DID THIS PLAN LAY HER UP? THE PLAN'S OWN RECEIPT SAYS SO — NEVER updated_at. The save
        -- door (cmd.standing_route_save_for) sets updated_at = now(), so after a SUCCESSFUL plan an
        -- `updated_at >= p_now - v_laid` test is always true at p_now = now(): it skipped every
        -- laid-up route it had just re-planned, the resume and start branches below were
        -- unreachable for that reason, and every merchant laid up for want of cargo stayed laid up
        -- for ever (found by the 2026-10-08 review; the ageing test above still gates WHEN she is
        -- re-planned at all). `planned` is this call's own count, and p_route pins the call to this
        -- one route, so planned = 0 means she was NOT re-planned — laid up again (nothing pays),
        -- busy, or failed — and she waits. Both arms are acceptable outcomes (NO_SPAGHETTI §7C):
        -- resume on fresh lines, or wait; she is never resumed on stale ones.
        --
        -- AND THAT HOLDS FOR EVERY PAUSE, not only 'laid_up' (the 2026-10-10 review): a dark or
        -- losing route whose plan RAISED would otherwise have been resumed on week-old lines, which
        -- is the very thing the sentence above claims never happens. Counted in the notes, so a
        -- route that is never planned is visible in the receipt rather than silently stuck.
        if coalesce((v_res->>'planned')::int, 0) = 0 then
          v_notes := v_notes || jsonb_build_object('route', sr.name, 'not_planned', coalesce(sr.paused_reason, 'unstarted'));
          continue;
        end if;
        -- 0181: SHE WAITS IN PORT. The plan priced every loop on offer from where she lies and none
        -- pays, so it laid her up (or kept her laid up): she is not resumed; the next tend asks again.
        if coalesce((v_res->>'waiting')::int, 0) > 0 then
          v_waiting := v_waiting + 1;
          continue;
        end if;
        if sr.fleet_id is null then
          if f.status = 'DOCKED' then
            v_res := cmd.standing_route_assign_for(sr.player_id, sr.id, r.fleet_id);
            if coalesce((v_res->>'ok')::boolean, false) then
              v_started := v_started + 1;
            else
              v_notes := v_notes || jsonb_build_object('route', sr.name, 'start', v_res->>'error_code');
            end if;
          end if;
        elsif sr.paused_reason is not null then
          v_res := cmd.standing_route_pause_for(sr.player_id, sr.id, false);
          v_resumed := v_resumed + 1;
        end if;
        continue;
      end if;

      -- 0180 (d): SHE SPENDS HER SURPLUS ON HER FLEET — lying docked at a build yard while her house
      -- stands above her purse ceiling, one hull (public.npc_build_for: the players' doors, paid into
      -- this city). Budgeted like the dear work above.
      if f.status = 'DOCKED' and not public.npc_upkeep_spent() then
        v_res := public.npc_build_for(r.fleet_id, p_now);
        if v_res is not null then
          v_built := v_built + coalesce((v_res->>'built')::int, 0);
          v_notes := v_notes || (jsonb_build_object('route', sr.name) || v_res);
        end if;
      end if;

      -- THE HALT LAW'S RELEASE, counted: clears with no lap closed between share her lap number.
      select * into fo from public.orders where fleet_id = r.fleet_id and status = 'failed' order by seq limit 1;
      if fo.id is not null and public.npc_upkeep_spent() then
        v_deferred := v_deferred + 1;                               -- 0114
      elsif fo.id is not null then
        select count(*) + 1 into v_clears from public.events ev
         where ev.player_id = sr.player_id and ev.kind = 'NPC_CLEARED'
           and ev.payload->>'route_id' = sr.id::text and (ev.payload->>'lap_no')::int = sr.lap_no;
        perform public.emit_event(sr.player_id, 'NPC_CLEARED', jsonb_build_object(
          'route', sr.name, 'route_id', sr.id, 'lap_no', sr.lap_no, 'fleet', f.name,
          'code', fo.error_code, 'line', fo.raw_text, 'n', v_clears));
        -- 0115: NOT PARKED. The third clear in one lap re-plans her lines on today's market first;
        -- every clear then releases her queue and the executor goes on.
        -- 0150: A SAIL REFUSED E_ENDURANCE IS RE-PLANNED ON THIS CLEAR. Only a plan answers it (her
        -- preset, room for her casks, her cursor back on her stop so the stop renders whole); a
        -- clear alone re-sends the SAIL and nothing else. The count of three was read off events
        -- the compactor deletes after npc_retention_hours, and the hour's pass reached a stuck
        -- merchant every two or three hours: for 251 of 270 it never came.
        if v_clears >= 3 or (fo.verb = 'SAIL' and fo.error_code = 'E_ENDURANCE') then
          perform public.npc_plan(p_now, sr.id);
        end if;
        perform cmd.clear_for(sr.player_id, r.fleet_id, false);
        perform cmd.advance(r.fleet_id, p_now);
        v_cleared := v_cleared + 1;
      end if;
    exception
      when lock_not_available then
        v_busy := v_busy + 1;
      when others then
        v_failed := v_failed + 1;
        v_notes := v_notes || jsonb_build_object('route', r.route_id, 'error', sqlerrm);
    end;
  end loop;
  return jsonb_build_object('dark', v_dark, 'started', v_started, 'resumed', v_resumed, 'cleared', v_cleared,
                            'laid_up', v_laid_n, 'busy', v_busy, 'failed', v_failed, 'deferred', v_deferred,
                            'built', v_built,   -- 0180 (d)
                            'waiting', v_waiting,   -- 0181
                            'notes', v_notes);
end $function$
