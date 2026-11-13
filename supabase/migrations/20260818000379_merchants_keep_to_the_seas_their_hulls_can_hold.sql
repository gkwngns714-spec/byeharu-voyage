-- ═══════════════════════════════════════════════════════════════════════════════════════════════════
-- 0379 - MERCHANTS KEEP TO THE SEAS THEIR HULLS CAN HOLD: the one guarded step that lights sea_conditions_bite_npc  (owner rows 166 and 324)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER (docs/OWNER_REQUESTS.md row 166, 2026-10-20): "NPCs under the same rule". Row 324 (2026-11-13): "open them if everything is built and is workable."
-- 0377 built the merchants' half of the sea conditions, dark behind sea_conditions_bite_npc. This file is the step that lights it, as 0378 is the players'.
--
-- THIS FILE LIGHTS NOTHING. It installs the step, with its guards, and the read of those guards (why a step and not a switch thrown here: 0378's header and
-- docs/dev-log/2026-11-13-lighting-the-seas.md):
--   public.sea_conditions_npc_ready() -> jsonb   STABLE, server-only:
--        lit                         the merchants' switch as it stands
--        planner_in                  0377 is in (public.npc_sea_shut, public.npc_loop_sea_shut, public.npc_feasible_legs with the fleet)
--        players_lit                 sea_conditions_bite is on. THE ORDER IS THE DESIGN'S (section 6: "lit after S2's window"): players first, in their own
--                                    measured window, then merchants in theirs, so each after-check reads one change.
--        merchant_loops, loops_closed, closed_at_sea   the loops with a leg her hull cannot hold (the planner moves each at her next lap start), and those at sea now (they finish)
--        merchants_with_no_open_leg  merchants on such a loop who have a known leg out of the harbour her loop starts at today and would have NONE her hull can
--                                    hold: the "no open loop" figure. The step refuses unless it is 0.
--        courses_not_remembered      merchant courses the memo does not hold (told, not a guard: such a course is sampled live)
--        ready                       not lit, and planner_in, players_lit and merchants_with_no_open_leg = 0
--   public.sea_conditions_npc_light() -> jsonb   VOLATILE, server-only, THE STEP: refuses (raises, nothing changed) when already lit or when a guard fails, naming
--        each; otherwise sets sea_conditions_bite_npc true and posts the news row public.news_update('0379', ...) (players will see fewer merchants on the far
--        seas and in fourteen far harbours: that is told), and returns the figures.
-- The verdicts are 0377's own readers (public.npc_loop_sea_shut, public.npc_sea_shut: the one rule, on wave only). Nothing is compared here.
--
-- TO LIGHT (the lead, on the owner's word, never an agent), after the players' window is closed and clean:
--   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/sea-light/before-npc.sql        (read-only: wanted guards.ready true)
--   npx --yes supabase@2.120.0 db query --linked -f scripts/ops/harness/sea-merchants/after-lit.sql     (read-only: the baseline of the window)
--   npx --yes supabase@2.120.0 db query --linked "select public.sea_conditions_npc_light()"
--   then sea-merchants/after-lit.sql at +5, +15 and +30 minutes.
-- ROLLBACK, at once (owner): update public.world_config set value = 'false'::jsonb where key = 'sea_conditions_bite_npc' returning key, value;
--   every plan after it is the old planner's (0377's assert, proof 70 SM_OFF). Forward removal: scripts/ops/harness/sea-light/rollback-0379.sql (a draft).
--
-- NOT TOUCHED: any function of 0377, any switch, any knob, any row. Two new functions and nothing else.
-- ALL OR NOTHING: ONE `do` block; statement_timeout 60 s and lock_timeout 5 s first; BUDGET 30 s (the read walks every merchant loop once: locally about 1 s).
-- SELF-ASSERT (this block): the two functions server-only, pinned, of the declared volatility; no other function, knob or news row moved; the read answers
-- its figures and agrees with both switches; the step, called INSIDE A PROBE THAT ROLLS BACK, refuses naming its guards and changes nothing, or (a ready
-- world) lights and posts one news row. THE LIVE PATHS are proved in CI by scripts/db/proofs/72_merchants_are_lit_by_one_guarded_step.sql.
-- VERSION: 0379 = 0377 (the merchants' rule, dark) + 0378 (the players' step) + 1.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0         timestamptz := clock_timestamp();
  v_fn_before  text;
  v_cfg_before text;
  v_news       bigint;
  v_entry      int;
  v_r          jsonb;
  v_g          jsonb;
  v_lit        boolean;
  v_refused    boolean;
  v_n          int := 0;
  r_x          record;
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('public.sea_conditions_npc_ready()') is not null or to_regprocedure('public.sea_conditions_npc_light()') is not null then
    raise exception '0379 refuses: the merchants'' lighting step is already in this world';
  end if;
  if to_regprocedure('public.sea_conditions_npc_on()') is null or to_regprocedure('public.npc_sea_shut(numeric, uuid, jsonb)') is null
     or to_regprocedure('public.npc_loop_sea_shut(uuid, jsonb)') is null or to_regprocedure('public.npc_feasible_legs(uuid, uuid, numeric, integer)') is null
     or to_regprocedure('public.sea_conditions_on()') is null or to_regprocedure('public.fleet_wave(uuid)') is null
     or to_regprocedure('public.news_update(text, text, text)') is null or to_regclass('public.npc_course_zones_memo') is null
     or not exists (select 1 from public.world_config where key = 'sea_conditions_bite_npc') then
    raise exception '0379 refuses: a function, table or knob this file reads is not in this world (0377 the merchants'' rule, 0215 the seas, 0347 the news)';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  v_entry := (select count(*) from public.client_rpc_entry_points());
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p');
  select md5(string_agg(c.key || ':' || c.value::text || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before from public.world_config c;
  select count(*) into v_news from public.world_news;
  v_lit := public.sea_conditions_npc_on();

  -- ── 2. THE READ ──
  execute $f$
create function public.sea_conditions_npc_ready()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0379: WHAT STANDS BETWEEN THIS WORLD AND LIGHTING THE SEA CONDITIONS FOR MERCHANTS, as figures (the header of 0379 names each). A read, through 0377's own
  -- readers. `merchants_with_no_open_leg` is read while the switch is off: public.npc_feasible_legs then answers every known leg her stores allow, and the sea
  -- is asked of each here; lit, that function has already taken the closed ones away, and the world is not `ready` anyway.
  with m as materialized (
    select nf.fleet_id, f.status, public.fleet_wave(nf.fleet_id) as wave,
           greatest(coalesce(voyage.fleet_speed_at(nf.fleet_id, 1), 0), 0.1) as speed,
           (select st.port_id from public.standing_route_stops st where st.route_id = nf.route_id order by st.ord limit 1) as home,
           public.npc_loop_sea_shut(nf.fleet_id, (select jsonb_agg(jsonb_build_object('port_id', st.port_id, 'course', st.course) order by st.ord)
                                                    from public.standing_route_stops st where st.route_id = nf.route_id)) as shut
      from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id
     where nf.route_id is not null),
  legs as materialized (
    select m.fleet_id,
           (select count(*) from jsonb_array_elements(l.legs) x) as known,
           (select count(*) from jsonb_array_elements(l.legs) x where public.npc_sea_shut(m.wave, (x ->> 'port_id')::uuid, x -> 'course') is null) as open
      from m cross join lateral (select public.npc_feasible_legs(m.home, m.fleet_id, m.speed, 400) as legs) l
     where m.shut and m.home is not null),
  g as (
    select public.sea_conditions_npc_on() as lit,
           true as planner_in,
           public.sea_conditions_on() as players_lit,
           (select count(*) from m) as merchant_loops,
           (select count(*) from m where m.shut) as loops_closed,
           (select count(*) from m where m.shut and m.status <> 'DOCKED') as closed_at_sea,
           (select count(*) from legs l where l.known > 0 and l.open = 0) as merchants_with_no_open_leg,
           (select count(*) from public.standing_route_stops st join public.npc_fleets nf on nf.route_id = st.route_id
             where not exists (select 1 from public.npc_course_zones_memo mm where mm.course_md5 = md5(st.course::text))) as courses_not_remembered)
  select jsonb_build_object(
           'lit', g.lit, 'planner_in', g.planner_in, 'players_lit', g.players_lit,
           'merchant_loops', g.merchant_loops, 'loops_closed', g.loops_closed, 'closed_at_sea', g.closed_at_sea,
           'merchants_with_no_open_leg', g.merchants_with_no_open_leg, 'courses_not_remembered', g.courses_not_remembered,
           'ready', not g.lit and g.planner_in and g.players_lit and g.merchants_with_no_open_leg = 0)
    from g
$body$
  $f$;
  revoke all on function public.sea_conditions_npc_ready() from public, anon, authenticated;
  comment on function public.sea_conditions_npc_ready() is '0379: the figures that stand between this world and lighting sea_conditions_bite_npc. A read; server-only.';

  -- ── 3. THE STEP ──
  execute $f$
create function public.sea_conditions_npc_light()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0379: THE ONE STEP THAT LIGHTS THE SEA CONDITIONS FOR MERCHANTS. It refuses, changing nothing, when the switch is already lit or when a guard of
-- public.sea_conditions_npc_ready fails, and says every guard that fails. Otherwise: sea_conditions_bite_npc true, and the news row of this step.
-- Server-only: the lead runs it on the owner's word. Its rollback is the switch.
declare
  v     jsonb := public.sea_conditions_npc_ready();
  v_why text[] := '{}';
begin
  if (v ->> 'lit')::boolean then
    raise exception 'sea_conditions_npc_light refuses: the sea conditions are already lit for merchants' using errcode = 'P0001';
  end if;
  if not (v ->> 'players_lit')::boolean then
    v_why := v_why || 'sea_conditions_bite is off: the players'' seas are lit first, in their own window (public.sea_conditions_light)'::text;
  end if;
  if (v ->> 'merchants_with_no_open_leg')::int > 0 then
    v_why := v_why || format('%s merchant(s) would be left with no known leg their hull can hold', v ->> 'merchants_with_no_open_leg');
  end if;
  if cardinality(v_why) > 0 then
    raise exception 'sea_conditions_npc_light refuses: %. Read scripts/ops/harness/sea-light/before-npc.sql and scripts/ops/harness/sea-conditions/impact.sql', array_to_string(v_why, '; ')
      using errcode = 'P0001';
  end if;
  update public.world_config set value = 'true'::jsonb, updated_at = now() where key = 'sea_conditions_bite_npc';
  perform public.news_update('0379', 'Merchants keep to seas their ships hold', '상선도 내파에 맞는 바다만 항해');
  return v || jsonb_build_object('lit', public.sea_conditions_npc_on(), 'ready', false, 'lit_at', now());
end
$body$
  $f$;
  revoke all on function public.sea_conditions_npc_light() from public, anon, authenticated;
  comment on function public.sea_conditions_npc_light() is '0379: THE guarded step that lights sea_conditions_bite_npc and posts its news. Refuses, changing nothing, while a guard of public.sea_conditions_npc_ready fails. Server-only; the lead runs it on the owner''s word.';

  -- ── 4. THE SELF-ASSERT ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and not (n.nspname = 'public' and p.proname in ('sea_conditions_npc_ready', 'sea_conditions_npc_light'))) is distinct from v_fn_before then
    raise exception '0379 self-assert FAIL: a function this file does not write moved';
  end if;
  for r_x in select p.proname, p.provolatile, p.prosecdef, coalesce(p.proconfig::text, '') as cfg, p.oid
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname in ('sea_conditions_npc_ready', 'sea_conditions_npc_light') loop
    v_n := v_n + 1;
    if r_x.provolatile <> (case when r_x.proname = 'sea_conditions_npc_light' then 'v' else 's' end)
       or not r_x.prosecdef or r_x.cfg <> '{"search_path=public, pg_temp"}'
       or has_function_privilege('anon', r_x.oid, 'execute') or has_function_privilege('authenticated', r_x.oid, 'execute') then
      raise exception '0379 self-assert FAIL: public.% is not of its declared volatility, definer, pinned and server-only', r_x.proname;
    end if;
  end loop;
  if v_n <> 2 or (select count(*) from public.client_rpc_entry_points()) <> v_entry
     or (select count(*) from public.client_write_grants()) <> 0 or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0379 self-assert FAIL: the two functions are not exactly two, or the registry or a wall moved';
  end if;

  v_r := public.sea_conditions_npc_ready();
  if not (v_r ?& array['lit', 'planner_in', 'players_lit', 'merchant_loops', 'loops_closed', 'closed_at_sea', 'merchants_with_no_open_leg', 'courses_not_remembered', 'ready'])
     or (v_r ->> 'lit')::boolean is distinct from v_lit or (v_r ->> 'players_lit')::boolean is distinct from public.sea_conditions_on()
     or (v_r ->> 'loops_closed')::int > (v_r ->> 'merchant_loops')::int
     or ((v_r ->> 'ready')::boolean and ((v_r ->> 'lit')::boolean or not (v_r ->> 'players_lit')::boolean or (v_r ->> 'merchants_with_no_open_leg')::int > 0)) then
    raise exception '0379 self-assert FAIL: the read does not answer its figures, or calls a world ready that is not: %', v_r;
  end if;

  begin
    begin
      v_g := public.sea_conditions_npc_light();
      v_refused := false;
    exception when sqlstate 'P0001' then
      if sqlerrm not like 'sea_conditions_npc_light refuses: %' then raise; end if;
      v_refused := true;
    end;
    if v_refused then
      if (v_r ->> 'ready')::boolean or public.sea_conditions_npc_on() is distinct from v_lit or (select count(*) from public.world_news) <> v_news then
        raise exception '0379 self-assert FAIL: the step refused a world its own read calls ready, or refused and still changed something';
      end if;
    else
      if not (v_r ->> 'ready')::boolean or not public.sea_conditions_npc_on() or (select count(*) from public.world_news where key = 'update:0379') <> 1 then
        raise exception '0379 self-assert FAIL: the step lit a world its own read does not call ready, or lit without the switch and one news row';
      end if;
    end if;
    raise exception 'PROBE_ROLLBACK_0379';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_0379' then raise; end if;
  end;

  if public.sea_conditions_npc_on() is distinct from v_lit
     or (select md5(string_agg(c.key || ':' || c.value::text || ':' || c.updated_at::text, ',' order by c.key)) from public.world_config c) is distinct from v_cfg_before
     or (select count(*) from public.world_news) <> v_news then
    raise exception '0379 self-assert FAIL: the switch, a knob or the news moved (this file lights nothing)';
  end if;
  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0379 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;

  raise notice '0379 NOTE: this file lights nothing. The lead lights with: select public.sea_conditions_npc_light()  (docs/dev-log/2026-11-13-lighting-the-seas.md). The guards as this world stands: %', v_r;
  raise notice '0379 self-assert ok: MERCHANTS KEEP TO THE SEAS THEIR HULLS CAN HOLD - the read and the step installed, server-only; no other function, knob or news row moved; the step, probed and rolled back, %; % ms',
    case when v_refused then 'refused naming its guards and changed nothing' else 'lit a ready world with one news row' end,
    round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
