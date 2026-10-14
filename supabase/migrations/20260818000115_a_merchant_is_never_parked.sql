-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0115 — A MERCHANT IS NEVER PARKED
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER'S WORDS ───────────────────────────────────────────────────────────────────────────
-- 2026-10-14, after 0114 went live (585 laid up, 247 sailing, 5 resting): *"make the resting
-- shorter like in real life 10 min. remove laid up."*
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) A MERCHANT RESTS TEN REAL MINUTES AT HOME. The one knob and its one reader stay as they are:
--     cmd.run_standing_route (0101) reads `route_rest_voyage_days` × 86400 / time_compression.
--     The knob is set from the LIVE compression so that the rest is 600 real seconds:
--     600 × 960 / 86400 = 6.6667 voyage-days today, against 14 (21 real minutes) before.
-- (2) NOTHING PARKS A MERCHANT ANY MORE. Every path that wrote 'laid_up' is cut, by slices of the
--     LIVE bodies of public.npc_plan and public.npc_tend (0114):
--       * planner, nothing pays at the 15 % bar: she sails her loop anyway. Her lines are saved as
--         they stand: SELL at a profit (what she paid plus the margin) at every stop and no BUY.
--         She carries nothing she cannot sell at a profit, and her next lap start re-plans her
--         on that day's prices. Counted `ballast`.
--       * the third failed-order clear in one lap: her lines are re-planned, then she is cleared
--         and released like every other clear. She is never parked.
--       * the weekly refound cap: deleted with its lay-up and loop swap. A purse under the floor is
--         refounded; the cooldown still spaces refounds.
--       * ADRIFT / UNABLE_TO_SAIL: no verb refloats a fleet, for anybody. She is counted in the
--         receipt (`laid_up` there now counts these) and her route is left unpaused, so the
--         executor waits for her.
--       * npc_tend lifts a legacy 'laid_up' pause AT ONCE, like dark/losing/reserve/edited.
--     The CHECK constraint keeps 'laid_up' as a value: a merchant route lying paused in a harbour
--     is still read as `doing = 'laid_up'` by world.port_merchants (0104) for ANY pause (dark,
--     error, off_route), so the client's word stays.
-- (3) ONE-TIME, AS FOUND LIT: public.npc_traders_switch(true). The switch plans and tends, and the
--     tend lifts every laid-up merchant through the planner and resumes or starts her.
--
-- SUPERSEDES (by slices of the live bodies, each hunk asserted to occur exactly once):
-- public.npc_plan and public.npc_tend (0114). The rest knob is a value, not a rule.
-- Self-asserts hold AS FOUND (0113): lit or dark, the probes roll back and the switch is left as
-- found.

do $guard$ begin perform set_config('statement_timeout', '20min', true); end $guard$;

-- ── 1. TEN REAL MINUTES AT HOME ────────────────────────────────────────────────────────────────
update public.world_config
   set value = to_jsonb(round(600 * public.wc_num('time_compression') / 86400, 6)),
       description = '0115: a merchant''s rest at her home stop between laps, in VOYAGE-days (cmd.run_standing_route '
                     'converts through time_compression). Set so the rest is 600 real seconds — ten minutes — at the '
                     'compression of the day it was written (960: 6.666667).'
 where key = 'route_rest_voyage_days';

-- ── 2. THE SLICES ──────────────────────────────────────────────────────────────────────────────
create or replace function pg_temp.slice_0115(p_fn text, p_old text, p_new text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  v_n   int  := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
begin
  if v_n <> 1 then
    raise exception '0115 self-assert FAIL: a hunk of % occurs % time(s), not once — the live body is not what this file was cut against: %',
      p_fn, v_n, left(p_old, 120);
  end if;
  execute replace(v_def, p_old, p_new);
end $$;

select pg_temp.slice_0115('public.npc_plan(timestamptz, uuid)',
$h$      if not v_any then
        -- (re)laid up, which also re-dates the pause: the upkeep tries again npc_laid_up_hours on.
        perform cmd.standing_route_pause_for(sr.player_id, sr.id, true, 'laid_up',
          'No cargo pays on any leg of this route at present.');
        v_laid := v_laid + 1;
      else
        v_res := cmd.standing_route_save_for(sr.player_id, sr.id, null, v_stops, null, null, v_pace);
        if not coalesce((v_res->>'ok')::boolean, false) then
          raise exception 'npc_plan: the save door refused % — %', sr.name, v_res->>'error_message';
        end if;
        v_planned := v_planned + 1;
      end if;
$h$,
$h$      -- 0115: A MERCHANT IS NEVER PARKED. With nothing that pays at the 15 % bar on any leg, she
      -- still sails her loop: her lines are saved as they stand — SELL at a profit (what she paid
      -- plus the margin) at every stop and no BUY — so she carries nothing she cannot sell at a
      -- profit, and her next lap start re-plans her on that day's prices. Counted `ballast`.
      if not v_any then
        v_laid := v_laid + 1;
      end if;
      v_res := cmd.standing_route_save_for(sr.player_id, sr.id, null, v_stops, null, null, v_pace);
      if not coalesce((v_res->>'ok')::boolean, false) then
        raise exception 'npc_plan: the save door refused % — %', sr.name, v_res->>'error_message';
      end if;
      v_planned := v_planned + 1;
$h$);

select pg_temp.slice_0115('public.npc_plan(timestamptz, uuid)',
$h$  return jsonb_build_object('enabled', true, 'planned', v_planned, 'laid_up', v_laid,$h$,
$h$  return jsonb_build_object('enabled', true, 'planned', v_planned, 'ballast', v_laid,   -- 0115: never laid up$h$);

select pg_temp.slice_0115('public.npc_tend(timestamptz, uuid)',
$h$--   ADRIFT / UNABLE_TO_SAIL -> laid up (there is no RECALL or salvage verb for anybody).
--   not started -> planned, then assigned where she lies (assigning starts the loop).
--   paused dark/losing/reserve/edited -> planned, then resumed. laid_up -> the same after
--     npc_laid_up_hours, and whether THIS call re-planned her is read off the plan's receipt, not
--     off updated_at (the save bumps it). error -> the same after 6 h (the pause is dated by updated_at, which the
--     hourly plan does not touch: it skips error routes). off_route -> re-assigned if she lies at
--     a stop; otherwise reported.
--   a FAILED order at the head of her queue (the halt law) -> cmd.clear_for, then cmd.advance —
--     COUNTED: the third clear with no lap closed between lays the route up, the code in the
--     sentence, so a merchant that cannot crew or sail stops burning the tick.
-- Then per company: purse below capital × npc_purse_floor_pct -> refounded (NPC_REFOUND through
-- the one mover; at most once per cooldown and npc_refound_max_per_week a week). At the weekly cap
-- the company is laid up and each fleet's route is re-cut to its alternate loop instead.
$h$,
$h$--   ADRIFT / UNABLE_TO_SAIL -> counted and left (0115: never parked; there is no RECALL or salvage
--     verb for anybody, so the executor waits for her).
--   not started -> planned, then assigned where she lies (assigning starts the loop).
--   paused dark/losing/reserve/edited/laid_up -> planned, then resumed, at once (0115: a lay-up is
--     legacy — nothing writes one any more); whether THIS call re-planned her is read off the
--     plan's receipt, not off updated_at (the save bumps it). error -> the same after 6 h (the
--     pause is dated by updated_at). off_route -> re-assigned if she lies at a stop; otherwise
--     reported.
--   a FAILED order at the head of her queue (the halt law) -> cmd.clear_for, then cmd.advance —
--     COUNTED: the third clear with no lap closed between re-plans her lines first (0115).
-- Then per company: purse below capital × npc_purse_floor_pct -> refounded (NPC_REFOUND through
-- the one mover; at most once per cooldown — 0115 deleted the weekly cap and its lay-up).
$h$);

select pg_temp.slice_0115('public.npc_tend(timestamptz, uuid)',
$h$      if f.status in ('ADRIFT', 'UNABLE_TO_SAIL') then
        if sr.paused_reason is distinct from 'laid_up' then
          perform cmd.standing_route_pause_for(sr.player_id, sr.id, true, 'laid_up',
            format('%s cannot sail on.', f.name));
          v_laid_n := v_laid_n + 1;
        end if;
        continue;
      end if;
$h$,
$h$      if f.status in ('ADRIFT', 'UNABLE_TO_SAIL') then
        -- 0115: NOT PARKED. No verb refloats a fleet that cannot sail — for anybody — so she is
        -- counted in the receipt and her route is left as it is; the executor waits for her.
        v_laid_n := v_laid_n + 1;
        v_notes := v_notes || jsonb_build_object('route', sr.name, 'cannot_sail', f.status);
        continue;
      end if;
$h$);

select pg_temp.slice_0115('public.npc_tend(timestamptz, uuid)',
$h$         and not (sr.paused_reason in ('dark', 'losing', 'reserve', 'edited')
                  or (sr.paused_reason = 'laid_up' and sr.updated_at < p_now - v_laid)
$h$,
$h$         and not (sr.paused_reason in ('dark', 'losing', 'reserve', 'edited', 'laid_up')   -- 0115: laid_up at once
$h$);

select pg_temp.slice_0115('public.npc_tend(timestamptz, uuid)',
$h$        if v_clears >= 3 then
          perform cmd.standing_route_pause_for(sr.player_id, sr.id, true, 'laid_up',
            format('%s stopped three times running (%s).', f.name, fo.error_code));
          v_laid_n := v_laid_n + 1;
        else
          perform cmd.clear_for(sr.player_id, r.fleet_id, false);
          perform cmd.advance(r.fleet_id, p_now);
          v_cleared := v_cleared + 1;
        end if;
$h$,
$h$        -- 0115: NOT PARKED. The third clear in one lap re-plans her lines on today's market first;
        -- every clear then releases her queue and the executor goes on.
        if v_clears >= 3 then
          perform public.npc_plan(p_now, sr.id);
        end if;
        perform cmd.clear_for(sr.player_id, r.fleet_id, false);
        perform cmd.advance(r.fleet_id, p_now);
        v_cleared := v_cleared + 1;
$h$);

select pg_temp.slice_0115('public.npc_tend(timestamptz, uuid)',
$h$        if coalesce(v_week, 0) >= public.wc_int('npc_refound_max_per_week') then
          -- AT THE CAP: the market has stopped paying this loop. Laid up, and re-cut to the
          -- alternate loop (the same door, the same courses authority); the old loop becomes the
          -- alternate, so the next cap swaps back.
          for r in select nf.fleet_id, nf.route_id, nf.alt_loop from public.npc_fleets nf
                    where nf.player_id = hh.player_id and nf.route_id is not null loop
            select * into sr from public.standing_routes where id = r.route_id;
            if r.alt_loop is not null and jsonb_array_length(r.alt_loop) >= 2 then
              select jsonb_agg(jsonb_build_object('port', p.code, 'course', s.course) order by s.ord)
                into v_alt from public.standing_route_stops s join public.ports p on p.id = s.port_id
               where s.route_id = sr.id;
              select jsonb_agg(jsonb_build_object('port', a->>'port', 'course', a->'course',
                                                  'repair', i = 1, 'crew_up', true, 'lines', '[]'::jsonb) order by i)
                into v_stops from jsonb_array_elements(r.alt_loop) with ordinality t(a, i);
              v_res := cmd.standing_route_save_for(hh.player_id, sr.id, null, v_stops, null, null, null);
              if coalesce((v_res->>'ok')::boolean, false) then
                update public.npc_fleets set alt_loop = v_alt where fleet_id = r.fleet_id;
              end if;
            end if;
            perform cmd.standing_route_pause_for(hh.player_id, sr.id, true, 'laid_up',
              'Refounded too often this week; the company changes its loop.');
            v_laid_n := v_laid_n + 1;
          end loop;
        else
          perform public.credit(hh.player_id, 'NPC_REFOUND', hh.capital - hh.ducats,
            public.emit_event(hh.player_id, 'NPC_REFOUNDED', jsonb_build_object(
              'company', hh.company_name, 'amount', hh.capital - hh.ducats, 'week', coalesce(v_week, 0) + 1)));
          v_refound := v_refound + 1;
        end if;
$h$,
$h$        -- 0115: NO WEEKLY CAP THAT PARKS A COMPANY. A purse under the floor is refounded (the
        -- cooldown still spaces refounds); the cap's lay-up and loop swap are deleted.
        perform public.credit(hh.player_id, 'NPC_REFOUND', hh.capital - hh.ducats,
          public.emit_event(hh.player_id, 'NPC_REFOUNDED', jsonb_build_object(
            'company', hh.company_name, 'amount', hh.capital - hh.ducats, 'week', coalesce(v_week, 0) + 1)));
        v_refound := v_refound + 1;
$h$);

-- ── 3. SELF-ASSERT, AND THE PARKED MERCHANTS PUT BACK TO SEA ───────────────────────────────────
do $$
declare
  v_was_on  boolean := public.npc_traders_on();
  v_routes_on boolean := public.standing_routes_on();
  v_route   uuid;
  v_res     jsonb;
  v_resume  jsonb;
  v_n       int;
  v_rest_s  numeric;
  v_groups  jsonb;
  v_adrift  int;
begin
  -- (a) TEN REAL MINUTES, read back through the reader's own conversion.
  v_rest_s := public.wc_num('route_rest_voyage_days') * 86400 / public.wc_num('time_compression');
  if abs(v_rest_s - 600) > 1 then
    raise exception '0115 self-assert FAIL: a merchant rests % real seconds, not 600', v_rest_s;
  end if;

  -- (b) NO PATH WRITES 'laid_up' ANY MORE: neither function pauses a route with it.
  if position($q$true, 'laid_up'$q$ in pg_get_functiondef('public.npc_plan(timestamptz, uuid)'::regprocedure)) > 0
     or position($q$true, 'laid_up'$q$ in pg_get_functiondef('public.npc_tend(timestamptz, uuid)'::regprocedure)) > 0
     or position('npc_refound_max_per_week' in pg_get_functiondef('public.npc_tend(timestamptz, uuid)'::regprocedure)) > 0 then
    raise exception '0115 self-assert FAIL: a merchant path still lays a route up, or the weekly cap still parks a company';
  end if;

  -- (c) BEHAVIOUR, rolled back: with the buyer cap at 0 nothing can be bought anywhere, and the
  --     route is still PLANNED (ballast), never laid up. The subject: the first merchant route by
  --     roster whose fleet can sail.
  select nf.route_id into v_route
    from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id
   where nf.route_id is not null and f.status not in ('ADRIFT', 'UNABLE_TO_SAIL')
   order by nf.roster_ord, nf.fleet_id limit 1;
  if v_route is null then
    raise exception '0115 self-assert FAIL: no merchant route to probe';
  end if;
  begin
    update public.world_config set value = 'true'::jsonb where key = 'npc_traders_enabled';
    update public.world_config set value = 'true'::jsonb where key = 'standing_routes_enabled';
    update public.world_config set value = to_jsonb(0) where key = 'npc_buyers_per_good';
    perform set_config('byeharu.npc_upkeep_deadline', '', true);
    v_res := public.npc_plan(now(), v_route);
    if (v_res->>'enabled')::boolean is distinct from true
       or (v_res->>'planned')::int is distinct from 1 or (v_res->>'ballast')::int is distinct from 1
       or (select paused_reason from public.standing_routes where id = v_route) is not distinct from 'laid_up'
       or exists (select 1 from public.standing_route_lines where route_id = v_route and kind = 'BUY') then
      raise exception '0115 self-assert FAIL: with nothing to buy the plan answered % (route %)',
        v_res, (select paused_reason from public.standing_routes where id = v_route);
    end if;
    -- and a legacy lay-up is lifted at once by the upkeep (planned, then resumed or started).
    perform cmd.standing_route_set_paused(v_route, 'laid_up', null, 'A probe lay-up (0115).');
    v_res := public.npc_tend(now(), v_route);
    if (select paused_reason from public.standing_routes where id = v_route) is not distinct from 'laid_up' then
      raise exception '0115 self-assert FAIL: the upkeep left a fresh lay-up parked: %', v_res - 'notes';
    end if;
    raise exception 'ROLLBACK_0115';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0115' then raise; end if;
  end;
  if public.npc_traders_on() is distinct from v_was_on or public.standing_routes_on() is distinct from v_routes_on
     or public.wc_int('npc_buyers_per_good') <> 3 then
    raise exception '0115 self-assert FAIL: the probe world was not rolled back';
  end if;

  -- (d) LIT AS FOUND: THE ONE SWITCH PUTS EVERY PARKED MERCHANT BACK TO SEA.
  if v_was_on then
    v_resume := public.npc_traders_switch(true);
    if coalesce((v_resume->'plan'->>'failed')::int, 0) <> 0 or coalesce((v_resume->'tend'->>'failed')::int, 0) <> 0 then
      raise exception '0115 self-assert FAIL: the switch''s pass failed: plan % tend %',
        (v_resume->'plan') - 'notes', v_resume->'tend';
    end if;
    select count(*) into v_n
      from public.npc_fleets nf join public.standing_routes sr on sr.id = nf.route_id
      join public.fleets f on f.id = nf.fleet_id
     where sr.paused_reason in ('laid_up', 'losing') and f.status not in ('ADRIFT', 'UNABLE_TO_SAIL');
    if v_n <> 0 then
      raise exception '0115 self-assert FAIL: % merchant route(s) still parked after the switch: %', v_n, v_resume->'tend'->'notes';
    end if;
  end if;

  select count(*) into v_adrift from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id
   where f.status in ('ADRIFT', 'UNABLE_TO_SAIL');
  select jsonb_object_agg(k, c) into v_groups from (
    select coalesce(sr.paused_reason, case when sr.fleet_id is null then 'unstarted' else 'running' end) as k, count(*) as c
      from public.npc_fleets nf join public.standing_routes sr on sr.id = nf.route_id group by 1) g;
  if public.npc_traders_on() is distinct from v_was_on then
    raise exception '0115 self-assert FAIL: the switch was not left as found';
  end if;

  raise notice '0115 self-assert ok: A MERCHANT IS NEVER PARKED. Rest % real s; no merchant path writes '
    'laid_up; with nothing to buy a route is planned in ballast; a legacy lay-up is lifted at once. '
    'Rolled back. Switch as found (%); the switch''s pass: %; merchants now: %; fleets that cannot sail: %.',
    round(v_rest_s), case when v_was_on then 'lit' else 'dark' end,
    jsonb_build_object('plan', (v_resume->'plan') - 'notes', 'tend', (v_resume->'tend') - 'notes'),
    v_groups, v_adrift;
end $$;
