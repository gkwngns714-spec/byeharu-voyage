-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0152 — A WRECK IS TOWED TO A SHIPYARD  (and a merchant's loop prefers one)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY ─────────────────────────────────────────────────────────────────────────────────────────
-- 0142 recorded, and left to the owner: "89 merchant fleets lie UNABLE_TO_SAIL at durability 0 …
-- No verb refloats a fleet for anybody, and cmd.do_repair refuses a fleet that is not DOCKED."
-- The same is true for a player. Measured on prod (read-only, head 0146, 2026-10-17): 90 fleets
-- UNABLE_TO_SAIL, every one a merchant's, every one lying in a port (none at sea), 31 of them in a
-- port that HAS a shipyard (REPAIR still refuses them: they are not DOCKED). And 69 merchant loops
-- have no shipyard on them anywhere, so a merchant sailing one can never repair at all.
--
-- ── THE OWNER'S DEFAULTS (decided by default 2026-10-17 — the owner may reverse) ────────────────
-- (1) A fleet that cannot sail because its hulls are at 0 can be TOWED to the nearest harbour
--     with a shipyard, paying a towing fee per mile, and arrives DOCKED there; the existing REPAIR
--     then works. ONE verb for players and merchants alike; merchants call it from the hourly
--     upkeep when wrecked. A purse that cannot pay is refused clearly — a new code, E_TOW_FUNDS.
-- (2) A merchant's loop prefers a shipyard: in THE one loop-choice authority (public.npc_plan),
--     a loop with no shipyard is chosen only when no loop with one pays.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) public.tow_for(player, fleet) — THE tow. Refuses E_NO_SUCH_FLEET (not hers), E_NOT_WRECKED
--     (she is not UNABLE_TO_SAIL — the status voyage.settle writes when her flagship makes port at
--     durability 0; the one reading of "a wreck", never a second test of the hull), E_NOT_AT_PORT
--     (a wreck at sea: none exists today — see NOT DONE), E_NO_YARD (no shipyard harbour in reach)
--     and E_TOW_FUNDS (have / need, in ducats). Otherwise: the nearest open HARBOUR with a shipyard
--     (public.port_has_shipyard, 0142) by the SAILED distance (voyage.reach_from, the reach table —
--     the figure every quote reads), her own port at 0 miles when it has one; the fee
--     round(miles x tow_fee_per_nm x running_cost_mult) — the house's running-cost multiplier,
--     as a repair's; the TOWED event; the fee through public.pay_city to the city she is towed to
--     (TOW — the existing money path, ledger and treasury alike); her queue released
--     (cmd.clear_for — orders written for where she lay must not run where she is towed); and she
--     lies DOCKED there. No voyage is sailed: a tow is a service bought in port, and a towed hull
--     is not a fleet at sea (no hazard rolls, no wages, no miles learned).
-- (2) cmd.preview_tow(fleet) — the real tow, rolled back: {ok, estimate} or the refusal it would
--     give. cmd.tow(fleet, expected_version) — the caller's own fleet, E_STALE on a moved version.
--     Both registered (public.client_rpc_entry_points) and executable by `authenticated` only.
-- (3) THE MERCHANT, through the same verb (public.npc_tend_route, the hourly upkeep's per-merchant
--     step): a wreck in port is towed by public.tow_for, and her REPAIR is queued there the way a
--     player queues it (cmd.parse, cmd.enqueue, cmd.advance). A refused tow leaves her counted as
--     before (`tow_refused` in the notes). Repaired at a shipyard her loop does not call at, her
--     route pauses `off_route` (cmd.run_standing_route, unchanged); the off_route branch now has
--     her loop chosen afresh FROM WHERE SHE LIES (public.npc_plan, below) and assigns her there.
-- (4) THE LOOP CHOICE (public.npc_plan): a loop is TIER 1 when it has a shipyard AND pays (net > 0),
--     else tier 0; the best loop is the highest tier, then the best per real hour. A higher tier
--     switches outright; within a tier npc_route_switch_pct rules as before. And a merchant DOCKED
--     OFF HER LOOP (p_route named) is given the lap-start choice from where she lies, her present
--     loop priced at tier -1 (it cannot be sailed from there) so any loop from here is taken.
--     The switch note carries `yard` (the chosen loop has one) and `off_loop`. The rule is three
--     functions that read no market — public.npc_loop_tier, npc_loop_beats, npc_loop_switches —
--     proven case by case (a first draft proved it on whatever loops the live market made pay, and
--     failed on prod 2026-10-17 for want of a subject: a proof never waits for the world to fit).
-- One new knob: tow_fee_per_nm = 3 (see THE FEE).
--
-- ── THE FEE (measured on prod, read-only, 2026-10-17, head 0146) ───────────────────────────────────────────
-- The 90 wrecks: nearest shipyard median 48.8 miles, p90 672.8, max 993.8 (31 at 0: a yard where
-- they lie). Median wreck: 1 hull worth 26,000 (build_cost), full repair 1,100; the cheapest hull
-- in the game is 8,000. Sailing under her own power costs a median 0.15 a mile (wages 1 + stores
-- 0.115 a crew-day). At 3 a mile — about twenty times the cost of sailing it — the median tow is
-- 146, the longest 2,981 (37% of the cheapest hull): a real cost, and always cheaper than losing
-- the fleet. Affordability on prod at 3: 89 of 90 merchant purses pay the tow, 87 the tow and the
-- full repair (at 2: 89 / 87; at 5: 87 / 84). Players: none wrecked today; a starting purse is
-- 8,000.
--
-- ── NOT DONE, AND WHY ───────────────────────────────────────────────────────────────────────────
-- * A wreck AT SEA (UNABLE_TO_SAIL at an anchor point — a voyage to open water ending with her
--   flagship at 0) is refused E_NOT_AT_PORT: the reach table measures from harbours only, and a
--   distance from a bare point would be a guess. Prod holds none (0 of 90). ADRIFT is not a wreck
--   (her hull is sound) and is not towed.
-- * A merchant who is towed and cannot pay the repair lies DOCKED at the shipyard with her
--   flagship at 0 (prod: 2 of the 90 at this fee); her REPAIR waits for her fortune (the company's
--   refounding, public.npc_tend_houses).
--
-- ── LOCKS ───────────────────────────────────────────────────────────────────────────────────────
-- CREATE OR REPLACE FUNCTION; one knob INSERT. The probes' writes are rolled back.
--
-- SUPERSEDES, by hunks sliced from the LIVE bodies (LF-normalised), each asserted to occur exactly
-- once and reversed to its pre-image: public.npc_plan (0120 as cut by 0142), public.npc_tend_route
-- (0137), public.client_rpc_entry_points (anchored mid-list, so a row appended at its tail by
-- another file cannot move this hunk). ACLs unmoved. Self-asserts hold on a lived-in world: every
-- probe runs on its own founded house or merchant and rolls back, dark and with the city purses
-- lit. Timings: raise notice only. VERSION 0152; applies on prod 0151 (0149 skills K0, 0150 the
-- stuck-laps fix, 0151 skills K1) — their bodies were checked against these hunks on prod.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

-- ── 1. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0152 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl
  from unnest(array['public.npc_plan(timestamptz, uuid)',
                    'public.npc_tend_route(timestamptz, uuid, uuid, bigint)',
                    'public.client_rpc_entry_points()']) f(fn);

create temp table before_0152 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from public.world_config) as knobs;

-- ── 2. THE KNOB ────────────────────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('tow_fee_per_nm', to_jsonb(3),
   '0152: what a tow to the nearest shipyard costs a mile (sailed miles, the reach table), times the '
   'house''s running_cost_mult. Sized on prod 2026-10-17: ~20x the cost of sailing a mile, and the '
   'longest tow of a wreck then (994 miles) under 40% of the cheapest hull. Read by public.tow_for alone.')
on conflict (key) do nothing;

-- ── 3. THE TOW ─────────────────────────────────────────────────────────────────────────────────
create or replace function public.tow_for(p_player uuid, p_fleet uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0152: THE one tow — players (cmd.tow) and merchants (public.npc_tend_route) alike. A fleet lying
-- UNABLE_TO_SAIL in a port is towed to the nearest open harbour with a shipyard (her own port at 0
-- miles when it has one), pays round(miles x tow_fee_per_nm x running_cost_mult) to that city, has
-- her queue released, and lies DOCKED there — where cmd.do_repair takes her. Refuses before
-- anything moves. Server-only.
declare
  f        public.fleets%rowtype;
  v_from   public.ports%rowtype;
  v_have   bigint;
  v_to     uuid;
  v_code   text;
  v_name   text;
  v_nm     numeric;
  v_fee    bigint;
  v_event  uuid;
  v_after  bigint;
begin
  -- THE LOCK ORDER every verb takes: the fleet (voyage.settle locks it first), then the house.
  select x.* into f from public.fleets x where x.id = p_fleet for update;
  if f.id is null or f.player_id is distinct from p_player then
    perform cmd.refuse('E_NO_SUCH_FLEET', 'there is no such fleet of yours');
  end if;
  select pl.ducats into v_have from public.players pl where pl.id = p_player for update;
  if f.status <> 'UNABLE_TO_SAIL' then
    perform cmd.refuse('E_NOT_WRECKED',
      format('%s is %s — only a fleet that cannot sail is towed', f.name, lower(replace(f.status, '_', ' '))));
  end if;
  if f.port_id is null then
    perform cmd.refuse('E_NOT_AT_PORT', format('%s lies at sea, and a tow sets out only from a port', f.name));
  end if;
  select x.* into v_from from public.ports x where x.id = f.port_id;

  -- THE NEAREST SHIPYARD, by the sailed distance (voyage.reach_from — the figure every quote reads).
  select y.id, y.code, y.name, case when y.id = f.port_id then 0 else r.nm end
    into v_to, v_code, v_name, v_nm
    from public.ports y
    left join voyage.reach_from(f.port_id) r on r.port_id = y.id
   where y.kind = 'HARBOUR' and not y.is_ice_closed and public.port_has_shipyard(y.id)
     and (y.id = f.port_id or r.nm is not null)
   order by case when y.id = f.port_id then 0 else r.nm end, y.code
   limit 1;
  if v_to is null then
    perform cmd.refuse('E_NO_YARD', format('no port that repairs ships can be reached from %s', v_from.name));
  end if;

  v_fee := round(v_nm * public.wc_num('tow_fee_per_nm') * public.running_cost_mult(p_player))::bigint;
  if coalesce(v_have, 0) < v_fee then
    perform cmd.refuse('E_TOW_FUNDS',
      format('Towing %s to %s costs %s 🪙 and you have %s 🪙.', f.name, v_name, v_fee, coalesce(v_have, 0)),
      cmd.figures(coalesce(v_have, 0), v_fee, 'ducats'));
  end if;

  v_event := public.emit_event(p_player, 'TOWED', jsonb_build_object(
               'fleet', f.name, 'from', v_from.code, 'to', v_code, 'nm', round(v_nm, 1), 'fee', v_fee));
  v_after := v_have;
  if v_fee > 0 then
    v_after := public.pay_city(p_player, v_to, 'TOW', v_fee, v_event);
  end if;
  -- the orders written for where she lay do not run where she is towed
  perform cmd.clear_for(p_player, p_fleet, false);
  update public.fleets
     set status = 'DOCKED', port_id = v_to, lat = null, lon = null, version = version + 1
   where id = p_fleet;

  return jsonb_build_object('ok', true, 'fleet', f.name, 'from', v_from.code, 'to', v_code, 'to_name', v_name,
    'nm', round(v_nm, 1), 'fee', v_fee, 'purse', v_after,
    -- the one sentence a screen prints (the quote and the receipt alike): why, and what a tow does
    'sentence', format('%s cannot sail: its ships are wrecked. ', f.name)
                || case when v_to = f.port_id
                        then format('A tow brings it in for repair here at %s.', v_name)
                        else format('A tow takes it %s miles to %s, the nearest port that repairs ships.',
                                    round(v_nm), v_name) end);
end $$;

create or replace function cmd.preview_tow(p_fleet uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0152: cmd.tow's dry run — the real tow, rolled back: {ok, estimate} or the refusal it would give.
declare
  v_player uuid := public.current_player_id();
  v_out    jsonb;
  v_det    text;
begin
  if v_player is null or not exists (select 1 from public.fleets f where f.id = p_fleet and f.player_id = v_player) then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_SUCH_FLEET',
                              'error_message', 'That fleet is not yours.', 'fixes', '[]'::jsonb);
  end if;
  begin
    v_out := jsonb_build_object('ok', true, 'estimate', public.tow_for(v_player, p_fleet));
    raise exception '__PREVIEW_ROLLBACK__' using errcode = 'P0001';
  exception when others then
    if sqlerrm = '__PREVIEW_ROLLBACK__' then
      return v_out;
    end if;
    if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
    get stacked diagnostics v_det = pg_exception_detail;
    return cmd.refused_envelope(sqlerrm, v_det);
  end;
end $$;

create or replace function cmd.tow(p_fleet uuid, p_expected_version int default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0152: the caller's own wrecked fleet is towed to the nearest shipyard (public.tow_for). Settles
-- first (DESIGN D.2), and fails E_STALE on a moved version (DESIGN F.3).
declare
  v_player uuid := public.current_player_id();
  v_now    int;
  v_out    jsonb;
  v_det    text;
begin
  if v_player is null or not exists (select 1 from public.fleets f where f.id = p_fleet and f.player_id = v_player) then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_SUCH_FLEET',
                              'error_message', 'That fleet is not yours.', 'fixes', '[]'::jsonb);
  end if;
  perform voyage.settle(p_fleet);
  select version into v_now from public.fleets where id = p_fleet;
  if p_expected_version is not null and p_expected_version <> v_now then
    return jsonb_build_object('ok', false, 'error_code', 'E_STALE',
      'error_message', format('This fleet has moved on since you looked (you have version %s, it is at %s).',
                              p_expected_version, v_now),
      'fixes', cmd.fixes('E_STALE', p_fleet), 'version', v_now);
  end if;
  begin
    v_out := public.tow_for(v_player, p_fleet);
  exception when others then
    if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
    get stacked diagnostics v_det = pg_exception_detail;
    return cmd.refused_envelope(sqlerrm, v_det) || jsonb_build_object('version', v_now);
  end;
  return v_out || jsonb_build_object('version', (select version from public.fleets where id = p_fleet));
end $$;

revoke all on function public.tow_for(uuid, uuid) from public, anon, authenticated;
revoke all on function cmd.preview_tow(uuid) from public, anon;
revoke all on function cmd.tow(uuid, int) from public, anon;
grant execute on function cmd.preview_tow(uuid) to authenticated;
grant execute on function cmd.tow(uuid, int) to authenticated;

-- ── 3b. THE LOOP CHOICE'S RULE, lifted into three functions npc_plan composes ──────────────────
-- One place, reading no market, proven case by case below (the market a merchant prices loops
-- against moves by the hour, and a probe that waited for it to fit was not a proof).
create or replace function public.npc_loop_tier(p_yard boolean, p_net numeric, p_unsailable boolean)
returns int
language plpgsql
immutable
as $$
begin
  -- 0152: 1 = the loop has a shipyard AND pays (what a lap leaves her > 0); 0 otherwise; -1 = her
  -- present loop while she lies off it (it cannot be sailed from there). Read by npc_plan alone.
  if coalesce(p_unsailable, false) then return -1; end if;
  if coalesce(p_yard, false) and coalesce(p_net, 0) > 0 then return 1; end if;
  return 0;
end $$;

create or replace function public.npc_loop_beats(p_tier int, p_score numeric, p_best_tier int, p_best_score numeric)
returns boolean
language plpgsql
immutable
as $$
begin
  -- 0152: a loop beats the best so far by its tier first, then by its score (ducats per real hour).
  return p_tier > p_best_tier or (p_tier = p_best_tier and p_score > p_best_score);
end $$;

create or replace function public.npc_loop_switches(p_best_tier int, p_best_score numeric,
                                                    p_cur_tier int, p_cur_score numeric, p_switch_pct numeric)
returns boolean
language plpgsql
immutable
as $$
begin
  -- 0152: she leaves her present loop for the best when it is of a HIGHER tier (outright), or, in
  -- the same tier, when it pays something and npc_route_switch_pct more per hour (0120's rule).
  return p_best_tier > p_cur_tier
      or (p_best_tier = p_cur_tier and p_best_score > 0 and p_best_score >= p_cur_score * (1 + p_switch_pct / 100));
end $$;

revoke all on function public.npc_loop_tier(boolean, numeric, boolean) from public, anon, authenticated;
revoke all on function public.npc_loop_beats(int, numeric, int, numeric) from public, anon, authenticated;
revoke all on function public.npc_loop_switches(int, numeric, int, numeric, numeric) from public, anon, authenticated;

-- ── 4. THE HUNKS (old → new), sliced from the live bodies ──────────────────────────────────────
create temp table hunks_0152 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0152 values
-- public.npc_plan: a loop with a shipyard that pays outranks every loop without one; a merchant
-- docked off her loop chooses afresh from where she lies
('public.npc_plan(timestamptz, uuid)', 1,
$h$--     kept, has her preset raised to cover its longest leg. She repairs at its first shipyard.
$h$,
$h$--     kept, has her preset raised to cover its longest leg. She repairs at its first shipyard.
--     0152: a loop with a shipyard that pays (TIER 1) outranks every loop without one — a yardless
--     loop is chosen only when no loop with a yard pays — and a higher tier switches outright.
--   * DOCKED OFF HER LOOP (0152: towed to a shipyard her loop does not call at; p_route named): the
--     same choice from where she lies, her present loop never kept (it cannot be sailed from there).
$h$),
('public.npc_plan(timestamptz, uuid)', 2,
$h$  v_try     int;         -- 0142
$h$,
$h$  v_try     int;         -- 0142
  v_off     boolean;     -- 0152: she lies docked at a port her loop does not call at
  v_tier    int;         -- 0152: 1 = a shipyard on the loop and it pays; 0 otherwise; -1 = unsailable
  v_cur_tier int;        -- 0152
  v_best_tier int;       -- 0152
$h$),
('public.npc_plan(timestamptz, uuid)', 3,
$h$      v_choose := p_route is not null and v_cand > 0 and sr.fleet_id = r.fleet_id and sr.lap_id is null
                  and f.status = 'DOCKED' and f.port_id = (v_loop->0->>'port_id')::uuid;
$h$,
$h$      -- 0152: OR SHE LIES DOCKED OFF HER LOOP — the candidates start where she lies.
      v_off := p_route is not null and sr.fleet_id = r.fleet_id and f.status = 'DOCKED'
               and not exists (select 1 from public.standing_route_stops s0
                                where s0.route_id = sr.id and s0.port_id = f.port_id);
      v_choose := (p_route is not null and v_cand > 0 and sr.fleet_id = r.fleet_id and sr.lap_id is null
                  and f.status = 'DOCKED' and f.port_id = (v_loop->0->>'port_id')::uuid)
                  or (v_off and v_cand > 0);
$h$),
('public.npc_plan(timestamptz, uuid)', 4,
$h$        v_score := v_net / greatest(v_nm / v_speed / v_comp + v_rest_h, v_day_h);
        if i = 0 then
          v_cur_stops := v_stops; v_cur_score := v_score; v_cur_any := v_any; v_cur_maxnm := v_maxnm; v_cur_net := v_net;
          v_best_stops := v_stops; v_best_score := v_score; v_best_any := v_any; v_best_maxnm := v_maxnm; v_best_net := v_net;
        elsif v_score > v_best_score then
          v_best_i := i; v_best_stops := v_stops; v_best_score := v_score; v_best_any := v_any; v_best_maxnm := v_maxnm; v_best_net := v_net;
        end if;
$h$,
$h$        v_score := v_net / greatest(v_nm / v_speed / v_comp + v_rest_h, v_day_h);
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
$h$),
('public.npc_plan(timestamptz, uuid)', 5,
$h$      if v_best_i <> 0 and not (v_best_score > 0 and v_best_score >= v_cur_score * (1 + v_switch / 100)) then
$h$,
$h$      -- 0152: a HIGHER TIER switches outright (a paying loop with a shipyard over one without; any
      -- loop over the one she lies off); within a tier, npc_route_switch_pct as before.
      if v_best_i <> 0 and not public.npc_loop_switches(v_best_tier, v_best_score, v_cur_tier, v_cur_score, v_switch) then
$h$),
('public.npc_plan(timestamptz, uuid)', 6,
$h$                     'net', round(v_best_net), 'was_net', round(v_cur_net));   -- 0142
$h$,
$h$                     'net', round(v_best_net), 'was_net', round(v_cur_net),   -- 0142
                     'yard', v_best_tier = 1, 'off_loop', v_off);               -- 0152
$h$),

-- public.npc_tend_route: a wreck in port is towed (the one tow) and repaired; docked off her loop,
-- her loop is chosen afresh from where she lies
('public.npc_tend_route(timestamptz, uuid, uuid, bigint)', 1,
$h$      if f.status in ('ADRIFT', 'UNABLE_TO_SAIL') then
        -- 0115: NOT PARKED. No verb refloats a fleet that cannot sail — for anybody — so she is
        -- counted in the receipt and her route is left as it is; the executor waits for her.
$h$,
$h$      -- 0152: A WRECK IN PORT IS TOWED (owner default, 2026-10-17) through public.tow_for — THE tow,
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
$h$),
('public.npc_tend_route(timestamptz, uuid, uuid, bigint)', 2,
$h$      if sr.paused_reason = 'off_route' then
        if f.status = 'DOCKED'
$h$,
$h$      if sr.paused_reason = 'off_route' then
        -- 0152: DOCKED OFF HER LOOP (towed to a shipyard her loop does not call at): her loop is
        -- chosen afresh from where she lies (public.npc_plan), and she is assigned there below.
        if f.status = 'DOCKED'
           and not exists (select 1 from public.standing_route_stops s where s.route_id = sr.id and s.port_id = f.port_id) then
          perform public.npc_plan(p_now, sr.id);
        end if;
        if f.status = 'DOCKED'
$h$),

-- public.client_rpc_entry_points: the tow and its dry run
('public.client_rpc_entry_points()', 1,
$h$      -- 0123: a stake in a city's works, and its dry run (the Town Hall's Invest).
$h$,
$h$      -- 0152: a wrecked fleet towed to the nearest shipyard, and its dry run.
      ('cmd',         'tow',                   'uuid, int'),
      ('cmd',         'preview_tow',           'uuid'),
      -- 0123: a stake in a city's works, and its dry run (the Town Hall's Invest).
$h$);

-- ── 5. THE RE-CUTS ─────────────────────────────────────────────────────────────────────────────
create or replace function pg_temp.recut_0152(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0152 where fn = p_fn order by n loop
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0152 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0152(fn) from defs_before_0152 order by fn;

-- set a probe house's purse, through the ledger (the purse reconciles with it).
create or replace function pg_temp.purse_0152(p_player uuid, p_ducats numeric)
returns void language sql
as $$ select public.credit(p_player, 'PROBE_0152',
                           (p_ducats - (select ducats from public.players where id = p_player))::bigint) $$;

-- wreck a fleet where it lies: every hull at 0, UNABLE_TO_SAIL in that port (what voyage.settle
-- writes when her flagship makes port at 0).
create or replace function pg_temp.wreck_0152(p_fleet uuid, p_port uuid)
returns void language sql
as $$
  update public.voyages set status = 'ARRIVED' where fleet_id = p_fleet and status = 'SAILING';
  update public.ships set durability = 0 where fleet_id = p_fleet;
  update public.fleets set status = 'UNABLE_TO_SAIL', port_id = p_port, lat = null, lon = null, busy_until = null
   where id = p_fleet;
$$;

-- ── 6. SELF-ASSERT ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_uid      constant uuid := '00000000-0152-4000-8000-000000000001';
  v_fn       text;
  v_def      text;
  v_back     text;
  h          record;
  v_n        int;
  v_list     text[];
  v_lit      boolean;
  v_lit0     boolean := public.city_treasury_on();
  v_was_on   boolean := public.npc_traders_on();
  v_routes_on boolean := public.standing_routes_on();
  v_players0 int := (select count(*) from public.players);
  v_r        jsonb;
  v_e        jsonb;
  v_player   uuid;
  v_fleet    uuid;
  v_ver      int;
  v_y        record;
  v_near     record;
  v_yard     uuid;
  v_bal      bigint;
  v_t0       timestamptz;
  v_ms       numeric := 0;
  v_k        int := 0;
  v_ok       text := '';
  v_m        uuid;
  v_mfleet   uuid;
  v_route    uuid;
  v_s        record;
  v_plan     jsonb;
  v_note1    jsonb;
  v_note2    jsonb;
  v_stops1   uuid[];
  v_stops2   uuid[];
  v_found    text := '';
  v_tried    int := 0;
  v_leg      jsonb;
  v_back_c   jsonb;
begin
  -- (a) PARITY BY REVERSE SUBSTITUTION; ACLs unmoved; each hunk in its new body exactly once.
  for v_fn in select fn from defs_before_0152 loop
    v_def := replace(pg_get_functiondef(v_fn::regprocedure), E'\r', '');
    v_back := v_def;
    for h in select * from hunks_0152 where fn = v_fn order by n desc loop
      v_n := (length(v_back) - length(replace(v_back, h.new, ''))) / length(h.new);
      if v_n <> 1 then
        raise exception '0152 self-assert FAIL: hunk % of % is in the new body % time(s), not once', h.n, v_fn, v_n;
      end if;
      v_back := replace(v_back, h.new, h.old);
    end loop;
    if v_back <> (select def from defs_before_0152 where fn = v_fn) or v_def = v_back then
      raise exception '0152 self-assert FAIL: % is not its pre-image plus only 0152''s hunks', v_fn;
    end if;
    if coalesce((select p.proacl::text from pg_proc p where p.oid = v_fn::regprocedure), '')
       is distinct from (select acl from defs_before_0152 where fn = v_fn) then
      raise exception '0152 self-assert FAIL: the re-cut moved the ACL of %', v_fn;
    end if;
  end loop;

  -- (b) ONE AUTHORITY: the knob is read by tow_for alone; tow_for is called by the two doors and
  --     the merchant's upkeep and nothing else; the shipyard is still read in port_has_shipyard alone.
  select array_agg(n.nspname || '.' || p.proname order by n.nspname || '.' || p.proname) into v_list
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prosrc like '%tow_fee_per_nm%';
  if v_list is distinct from array['public.tow_for'] then
    raise exception '0152 self-assert FAIL: tow_fee_per_nm is read in %, not in tow_for alone', v_list;
  end if;
  select array_agg(n.nspname || '.' || p.proname order by n.nspname || '.' || p.proname) into v_list
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prosrc like '%tow_for(%'
     and p.oid <> 'public.tow_for(uuid, uuid)'::regprocedure;
  if v_list is distinct from array['cmd.preview_tow', 'cmd.tow', 'public.npc_tend_route'] then
    raise exception '0152 self-assert FAIL: the tow is called by %, not by its two doors and the merchant''s upkeep alone', v_list;
  end if;
  select array_agg(n.nspname || '.' || p.proname order by n.nspname || '.' || p.proname) into v_list
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prosrc ~ 'kind\s*=\s*''shipyard''';
  if v_list is distinct from array['public.port_has_shipyard'] then
    raise exception '0152 self-assert FAIL: "this port has a shipyard" is read in %, not in port_has_shipyard alone', v_list;
  end if;

  -- (c) THE WALL: two new entry points, one new knob, the core server-only, no client write.
  if has_function_privilege('authenticated', 'public.tow_for(uuid, uuid)', 'execute')
     or has_function_privilege('anon', 'public.tow_for(uuid, uuid)', 'execute')
     or has_function_privilege('anon', 'cmd.tow(uuid, int)', 'execute')
     or has_function_privilege('anon', 'cmd.preview_tow(uuid)', 'execute')
     or not has_function_privilege('authenticated', 'cmd.tow(uuid, int)', 'execute')
     or not has_function_privilege('authenticated', 'cmd.preview_tow(uuid)', 'execute') then
    raise exception '0152 self-assert FAIL: the tow''s grants are not: two doors for authenticated, the core for the server';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from before_0152) + 2
     or (select count(*) from public.client_rpc_entry_points() e
          where e.function_name in ('tow', 'preview_tow') and e.fn is not null) <> 2
     or (select count(*) from public.world_config) <> (select knobs from before_0152) + 1
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0152 self-assert FAIL: the registry, the knobs, the grant wall or the read wall moved unexpectedly';
  end if;
  if strpos(pg_get_functiondef('public.npc_tend_route(timestamptz, uuid, uuid, bigint)'::regprocedure), 'public.tow_for(sr.player_id, r.fleet_id)') = 0
     or strpos(pg_get_functiondef('public.npc_plan(timestamptz, uuid)'::regprocedure), 'public.npc_loop_tier(v_rep, v_net, i = 0 and v_off)') = 0
     or strpos(pg_get_functiondef('public.npc_plan(timestamptz, uuid)'::regprocedure), 'public.npc_loop_beats(v_tier, v_score, v_best_tier, v_best_score)') = 0
     or strpos(pg_get_functiondef('public.npc_plan(timestamptz, uuid)'::regprocedure), 'public.npc_loop_switches(v_best_tier, v_best_score, v_cur_tier, v_cur_score, v_switch)') = 0
     or strpos(pg_get_functiondef('public.npc_plan(timestamptz, uuid)'::regprocedure), 'v_best_score >= v_cur_score * (1 + v_switch / 100)') > 0 then
    raise exception '0152 self-assert FAIL: a re-cut did not compose the tow or the tier';
  end if;

  -- THE SUBJECT HARBOUR: the first yardless open harbour (by code) with a shipyard in reach.
  select y.id as y_id, y.code as y_code into v_y
    from public.ports y
   where y.kind = 'HARBOUR' and not y.is_ice_closed and not public.port_has_shipyard(y.id)
     and exists (select 1 from voyage.reach_from(y.id) r join public.ports b on b.id = r.port_id
                  where b.kind = 'HARBOUR' and not b.is_ice_closed and public.port_has_shipyard(b.id))
   order by y.code limit 1;
  -- its nearest shipyard, measured here by the probe (the expectation the tow must meet)
  select b.id, b.code, r.nm into v_near
    from voyage.reach_from(v_y.y_id) r join public.ports b on b.id = r.port_id
   where b.kind = 'HARBOUR' and not b.is_ice_closed and public.port_has_shipyard(b.id)
   order by r.nm, b.code limit 1;
  if v_y.y_id is null or v_near.id is null or v_near.nm <= 0 then
    raise exception '0152 self-assert FAIL: no yardless harbour with a shipyard in reach — no subject';
  end if;

  -- (d) THE PLAYER'S TOW, dark and with the city purses lit: a house of the probe's own.
  foreach v_lit in array array[false, true] loop
    begin
      -- the purses lit or dark by the switch's own flag (0122's probe idiom: the switch's one-time
      -- seeding refuses on a world with no merchants, E_WORLD_BROKE, and is not what is proved here)
      update public.world_config set value = to_jsonb(v_lit) where key = 'city_treasury_enabled';
      perform cmd.assume_identity(c_uid);
      v_r := cmd.found_house('Casa do Reboque 0152', 'prt');
      if not coalesce((v_r->>'ok')::boolean, false) then
        raise exception '0152 self-assert FAIL: the probe house was not founded: %', v_r;
      end if;
      v_player := (v_r->>'player_id')::uuid;
      select f.id into v_fleet from public.fleets f where f.player_id = v_player order by f.id limit 1;

      -- a sound fleet is not towed
      v_r := cmd.preview_tow(v_fleet);
      if v_r->>'error_code' is distinct from 'E_NOT_WRECKED' then
        raise exception '0152 self-assert FAIL: a sound fleet''s tow answered %', v_r;
      end if;
      -- nor a stranger's (any merchant's fleet)
      v_r := cmd.tow((select nf.fleet_id from public.npc_fleets nf order by nf.fleet_id limit 1), null);
      if (select count(*) from public.npc_fleets) > 0 and v_r->>'error_code' is distinct from 'E_NO_SUCH_FLEET' then
        raise exception '0152 self-assert FAIL: a stranger''s fleet was towable: %', v_r;
      end if;

      -- WRECK IT at the yardless harbour, with a failed order at the head of her queue.
      perform pg_temp.wreck_0152(v_fleet, v_y.y_id);
      insert into public.orders (fleet_id, player_id, seq, raw_text, verb, args, status, error_code)
      values (v_fleet, v_player, 900152, 'SELL x ALL', 'SELL', '{}'::jsonb, 'failed', 'E_NOT_DOCKED');
      -- POSITIVE CONTROL: without a tow her REPAIR only waits in the queue — she is not DOCKED.
      v_r := cmd.issue(v_fleet, 'REPAIR', null, null);
      if (select status from public.fleets where id = v_fleet) <> 'UNABLE_TO_SAIL'
         or exists (select 1 from public.ships s where s.fleet_id = v_fleet and s.durability > 0)
         or not exists (select 1 from public.orders o where o.fleet_id = v_fleet and o.verb = 'REPAIR' and o.status = 'pending') then
        raise exception '0152 self-assert FAIL: POSITIVE CONTROL — a wreck at a yardless harbour was repaired without a tow: %', v_r;
      end if;

      -- AN EMPTY PURSE: refused E_TOW_FUNDS with have / need, and nothing moved.
      perform pg_temp.purse_0152(v_player, 0);
      v_r := cmd.tow(v_fleet, null);
      if v_r->>'error_code' is distinct from 'E_TOW_FUNDS'
         or (v_r->'figures'->>'have')::numeric <> 0 or (v_r->'figures'->>'need')::numeric <= 0
         or (select status from public.fleets where id = v_fleet) <> 'UNABLE_TO_SAIL' then
        raise exception '0152 self-assert FAIL: an empty purse''s tow answered %', v_r;
      end if;

      -- THE DRY RUN: the nearest shipyard, the fee by the knob, and nothing moved.
      perform pg_temp.purse_0152(v_player, 20000);
      select version into v_ver from public.fleets where id = v_fleet;
      v_r := cmd.preview_tow(v_fleet);
      v_e := v_r->'estimate';
      if not coalesce((v_r->>'ok')::boolean, false) or v_e->>'to' <> v_near.code
         or (v_e->>'nm')::numeric <> round(v_near.nm, 1)
         or (v_e->>'fee')::bigint <> round(v_near.nm * public.wc_num('tow_fee_per_nm') * public.running_cost_mult(v_player))::bigint
         or (v_e->>'fee')::bigint <= 0 or coalesce(v_e->>'sentence', '') = ''
         or (select ducats from public.players where id = v_player) <> 20000
         or (select status from public.fleets where id = v_fleet) <> 'UNABLE_TO_SAIL'
         or (select version from public.fleets where id = v_fleet) <> v_ver then
        raise exception '0152 self-assert FAIL: the dry run % (expected % at % miles) moved something or priced wrong', v_r, v_near.code, v_near.nm;
      end if;
      -- a stale version is refused
      v_r := cmd.tow(v_fleet, v_ver - 1);
      if v_r->>'error_code' is distinct from 'E_STALE' then
        raise exception '0152 self-assert FAIL: a stale tow answered %', v_r;
      end if;

      -- THE TOW: docked at the shipyard, the purse down by the fee, the city up by it when lit, the
      -- event, the queue released, the ledger reconciled.
      v_bal := coalesce(public.treasury_balance(v_near.id), 0);
      v_t0 := clock_timestamp();
      v_r := cmd.tow(v_fleet, v_ver);
      v_ms := v_ms + extract(epoch from clock_timestamp() - v_t0) * 1000; v_k := v_k + 1;
      if not coalesce((v_r->>'ok')::boolean, false)
         or (select status from public.fleets where id = v_fleet) <> 'DOCKED'
         or (select port_id from public.fleets where id = v_fleet) <> v_near.id
         or (select ducats from public.players where id = v_player) <> 20000 - (v_e->>'fee')::bigint
         or coalesce(public.treasury_balance(v_near.id), 0) <> v_bal + (case when v_lit then (v_e->>'fee')::bigint else 0 end)
         or (v_lit and not exists (select 1 from public.treasury_flows tf where tf.port_id = v_near.id and tf.kind = 'TOW'
                                     and tf.player_id = v_player and tf.ducats = (v_e->>'fee')::bigint))
         or (not v_lit and exists (select 1 from public.treasury_flows tf where tf.player_id = v_player and tf.kind = 'TOW'))
         or not exists (select 1 from public.ledger l where l.player_id = v_player and l.kind = 'TOW'
                          and l.ducats_delta = -(v_e->>'fee')::bigint)
         or (select count(*) from public.events e where e.player_id = v_player and e.kind = 'TOWED'
               and e.payload->>'to' = v_near.code and (e.payload->>'fee')::bigint = (v_e->>'fee')::bigint) <> 1
         or exists (select 1 from public.orders o where o.fleet_id = v_fleet and o.status in ('pending', 'failed')) then
        raise exception '0152 self-assert FAIL: the tow (lit %) did not move fleet, purse, city, event and queue as one: %', v_lit, v_r;
      end if;
      perform public.assert_ledger_reconciles(v_player);
      -- towed once is enough
      if cmd.tow(v_fleet, null)->>'error_code' is distinct from 'E_NOT_WRECKED' then
        raise exception '0152 self-assert FAIL: a towed fleet was towed again';
      end if;

      -- THE EXISTING REPAIR NOW WORKS.
      v_r := cmd.issue(v_fleet, 'REPAIR', null, null);
      if not coalesce((v_r->>'ok')::boolean, false) or (select status from public.fleets where id = v_fleet) <> 'REPAIRING'
         or exists (select 1 from public.ships s join public.ship_classes c on c.id = s.class_id
                     where s.fleet_id = v_fleet and s.durability < c.durability) then
        raise exception '0152 self-assert FAIL: the towed wreck was not repaired: %', v_r;
      end if;
      perform public.assert_ledger_reconciles(v_player);

      -- A WRECK AT A SHIPYARD is brought in for nothing: 0 miles, no fee, docked where she lies.
      perform pg_temp.wreck_0152(v_fleet, v_near.id);
      v_r := cmd.tow(v_fleet, null);
      if not coalesce((v_r->>'ok')::boolean, false) or (v_r->>'fee')::bigint <> 0 or (v_r->>'nm')::numeric <> 0
         or v_r->>'to' <> v_near.code or (select status from public.fleets where id = v_fleet) <> 'DOCKED' then
        raise exception '0152 self-assert FAIL: a wreck lying at a shipyard answered %', v_r;
      end if;
      if not v_lit then
        v_ok := v_ok || format('a probe house wrecked at %s (no shipyard): its REPAIR only waited in the queue, an empty purse refused E_TOW_FUNDS, the dry run quoted %s at %s miles for %s and moved nothing, E_STALE refused, the tow docked it at %s (lit and dark: purse, city, ledger, TOWED, queue released), REPAIR then took it; a wreck at %s itself came in for 0; ',
                           v_y.y_code, v_near.code, round(v_near.nm, 1), v_e->>'fee', v_near.code, v_near.code);
      end if;
      raise exception 'ROLLBACK_0152_PLAYER';
    exception when others then
      if sqlerrm <> 'ROLLBACK_0152_PLAYER' then raise; end if;
    end;
  end loop;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);

  -- (e) THE MERCHANT'S TOW: wrecked at a yardless stop of a loop of two yardless harbours, the
  --     hourly upkeep tows her (the same verb) and queues her REPAIR; released from the yard she
  --     lies off her loop, pauses off_route, and the next upkeep chooses her a loop from there.
  begin
    update public.world_config set value = 'true'::jsonb where key = 'npc_traders_enabled';
    update public.world_config set value = 'true'::jsonb where key = 'standing_routes_enabled';
    perform set_config('byeharu.npc_upkeep_deadline', '', true);
    update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled';
    -- her own precondition: the upkeep tends her, not pauses her dark as beyond npc_fleet_max
    -- (the probe merchant is the roster's last; prod 2026-10-17: 837 merchants, a cap of 861).
    update public.world_config set value = to_jsonb((select count(*) + 1 from public.npc_fleets))
     where key = 'npc_fleet_max' and (value #>> '{}')::numeric < (select count(*) + 1 from public.npc_fleets);
    select y.id as y_id, y.code as y_code, l.to_port as z_id, l.code as z_code, l.course as y_to_z,
           (select l2.course from public.npc_known_legs(l.to_port) l2 where l2.to_port = y.id) as z_to_y
      into v_s
      from public.ports y cross join lateral public.npc_known_legs(y.id) l
      join public.ports z on z.id = l.to_port
     where y.kind = 'HARBOUR' and not public.port_has_shipyard(y.id)
       and z.kind = 'HARBOUR' and not public.port_has_shipyard(z.id)
       and exists (select 1 from public.npc_known_legs(l.to_port) l2 where l2.to_port = y.id)
       and exists (select 1 from voyage.reach_from(y.id) r join public.ports b on b.id = r.port_id
                    where b.kind = 'HARBOUR' and not b.is_ice_closed and public.port_has_shipyard(b.id))
     order by y.code, l.code limit 1;
    if v_s.y_id is null then
      raise exception '0152 self-assert FAIL: no two yardless harbours with known courses both ways — no subject';
    end if;
    v_m := public.npc_found(jsonb_build_object(
      'company', 'Casa do Casco Partido', 'alt_company', 'Casa do Reboque', 'nation', 'PRT', 'ink', 'prt',
      'master', 'Capitao Rebocado',
      'blurb', 'A probe company founded so that a wrecked merchant can be seen to be towed.',
      'capital', 40000, 'patience', 0.20, 'wares', '[]'::jsonb, 'roster_ord', 9149,
      'skills', '{}'::jsonb,
      'fleets', jsonb_build_array(jsonb_build_object(
        'name', 'Rebocada', 'roster_ord', 9149, 'days', 12,
        'ships', jsonb_build_array(jsonb_build_object('class', 'nau', 'name', 'Rebocada')),
        'officers', '[]'::jsonb,
        'stops', jsonb_build_array(jsonb_build_object('port', v_s.y_code, 'course', v_s.y_to_z),
                                   jsonb_build_object('port', v_s.z_code, 'course', v_s.z_to_y)),
        'alt_stops', jsonb_build_array(jsonb_build_object('port', v_s.y_code, 'course', v_s.y_to_z),
                                       jsonb_build_object('port', v_s.z_code, 'course', v_s.z_to_y))))));
    select nf.fleet_id, nf.route_id into v_mfleet, v_route from public.npc_fleets nf
     where nf.player_id = v_m order by nf.roster_ord limit 1;   -- the probe founded exactly one
    if v_mfleet is null or v_route is null then
      raise exception '0152 self-assert FAIL: the probe merchant was founded without a fleet or a route';
    end if;
    -- MID-LAP, wrecked at her stop 0 (the shape on prod: she made port with her flagship at 0).
    perform pg_temp.wreck_0152(v_mfleet, v_s.y_id);
    insert into public.standing_route_laps (route_id, lap_no, started_at)
    values (v_route, 900152, now() - interval '1 hour');
    update public.standing_routes set fleet_id = v_mfleet, lap_no = 900152, stop_cursor = 0, paused_reason = null,
                                      hold_until = null,
                                      lap_id = (select id from public.standing_route_laps where route_id = v_route and lap_no = 900152)
     where id = v_route;
    perform pg_temp.purse_0152(v_m, 40000);
    select b.id, b.code, r.nm into v_near
      from voyage.reach_from(v_s.y_id) r join public.ports b on b.id = r.port_id
     where b.kind = 'HARBOUR' and not b.is_ice_closed and public.port_has_shipyard(b.id)
     order by r.nm, b.code limit 1;

    v_r := public.npc_tend(now(), v_route);
    if not exists (select 1 from jsonb_array_elements(v_r->'notes') x where x->>'towed' = v_near.code)
       or (select port_id from public.fleets where id = v_mfleet) <> v_near.id
       or (select status from public.fleets where id = v_mfleet) <> 'REPAIRING'
       or exists (select 1 from public.ships s join public.ship_classes c on c.id = s.class_id
                   where s.fleet_id = v_mfleet and s.durability < c.durability)
       or not exists (select 1 from public.events e where e.player_id = v_m and e.kind = 'TOWED' and e.payload->>'to' = v_near.code)
       or not exists (select 1 from public.treasury_flows tf where tf.port_id = v_near.id and tf.kind = 'TOW' and tf.player_id = v_m) then
      raise exception '0152 self-assert FAIL: the upkeep did not tow the wrecked merchant from % to % and repair her: %',
        v_s.y_code, v_near.code, v_r;
    end if;
    perform public.assert_ledger_reconciles(v_m);
    -- out of the yard: she lies at a shipyard her loop does not call at, and her route says so.
    update public.fleets set busy_until = now() - interval '1 second' where id = v_mfleet;
    perform cmd.advance(v_mfleet, now());
    if (select status from public.fleets where id = v_mfleet) <> 'DOCKED'
       or (select paused_reason from public.standing_routes where id = v_route) is distinct from 'off_route' then
      raise exception '0152 self-assert FAIL: repaired off her loop she is % with her route paused %',
        (select status from public.fleets where id = v_mfleet), (select paused_reason from public.standing_routes where id = v_route);
    end if;
    -- the next upkeep chooses her a loop from where she lies, with the shipyard on it, and assigns her.
    v_t0 := clock_timestamp();
    v_r := public.npc_tend(now(), v_route);
    v_ms := v_ms + extract(epoch from clock_timestamp() - v_t0) * 1000; v_k := v_k + 1;
    if (select paused_reason from public.standing_routes where id = v_route) is not null
       or (select fleet_id from public.standing_routes where id = v_route) is distinct from v_mfleet
       or (select port_id from public.standing_route_stops where route_id = v_route and ord = 0) <> v_near.id
       or not (select repair from public.standing_route_stops where route_id = v_route and ord = 0) then
      raise exception '0152 self-assert FAIL: off her loop at % she was not given a loop from there: % (stops %, paused %)',
        v_near.code, v_r,
        (select array_agg(p.code order by s.ord) from public.standing_route_stops s join public.ports p on p.id = s.port_id where s.route_id = v_route),
        (select paused_reason from public.standing_routes where id = v_route);
    end if;
    v_ok := v_ok || format('a merchant wrecked at %s on a loop %s-%s (no shipyard on it) was towed by the upkeep to %s, repaired, paused off_route, and given the loop %s from there; ',
                           v_s.y_code, v_s.y_code, v_s.z_code, v_near.code,
                           (select string_agg(p.code, '-' order by s.ord) from public.standing_route_stops s join public.ports p on p.id = s.port_id where s.route_id = v_route));
    raise exception 'ROLLBACK_0152_MERCHANT';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0152_MERCHANT' then raise; end if;
  end;

  -- (f) A YARDLESS LOOP LOSES TO A LOOP WITH A SHIPYARD — the rule, case by case, on no market at
  --     all: the three functions npc_plan composes ((b) asserts it composes them, and that 0120's
  --     inline switch test is gone). Each row: what the rule must answer.
  for v_s in
    select * from (values
      -- npc_loop_tier(yard, net, unsailable)
      ('tier: a yard and it pays',             public.npc_loop_tier(true,  100, false) = 1),
      ('tier: a yard and it breaks even',      public.npc_loop_tier(true,    0, false) = 0),
      ('tier: a yard and it loses',            public.npc_loop_tier(true,  -50, false) = 0),
      ('tier: no yard and it pays',            public.npc_loop_tier(false, 100, false) = 0),
      ('tier: her loop while she lies off it', public.npc_loop_tier(true,  100, true) = -1),
      -- npc_loop_beats(tier, score, best tier, best score): the tier first, then the score
      ('beats: a paying yard loop over a better yardless one',  public.npc_loop_beats(1,   10, 0, 1000)),
      ('beats: a yardless loop never over a paying yard loop', not public.npc_loop_beats(0, 1000, 1,   10)),
      ('beats: in a tier, the better score',                    public.npc_loop_beats(0,   20, 0,   10)),
      ('beats: in a tier, never the equal score',          not public.npc_loop_beats(0,   10, 0,   10)),
      ('beats: any loop over the one she lies off',             public.npc_loop_beats(0,   -5, -1, 999)),
      -- npc_loop_switches(best tier, best score, present tier, present score, pct)
      ('switches: a paying yard loop over a better yardless present loop', public.npc_loop_switches(1, 10, 0, 1000, 10)),
      ('switches: off her loop, to any loop',                              public.npc_loop_switches(0, -5, -1, 999, 10)),
      ('switches: in a tier, by the switch margin',                        public.npc_loop_switches(0, 111, 0, 100, 10)),
      ('switches: in a tier, not under the margin',                    not public.npc_loop_switches(0, 105, 0, 100, 10)),
      ('switches: in a tier, never to a loop that pays nothing',       not public.npc_loop_switches(0,   0, 0, -50, 10))
    ) t(what, ok)
  loop
    v_tried := v_tried + 1;
    if not coalesce(v_s.ok, false) then
      raise exception '0152 self-assert FAIL: the loop choice''s rule — %', v_s.what;
    end if;
  end loop;
  v_found := format('%s cases of the loop choice''s rule (tier, beats, switches) answered as written', v_tried);

  if (select count(*) from public.players) <> v_players0
     or exists (select 1 from public.npc_houses where roster_ord in (9149, 9150))
     or public.npc_traders_on() is distinct from v_was_on or public.standing_routes_on() is distinct from v_routes_on
     or public.city_treasury_on() is distinct from v_lit0 then
    raise exception '0152 self-assert FAIL: the probe world was not rolled back';
  end if;

  raise notice '0152 tows and plans timed: % call(s), mean % ms', v_k, round(v_ms / greatest(v_k, 1));
  raise notice '0152 self-assert ok: A WRECK IS TOWED TO A SHIPYARD. npc_plan, npc_tend_route and the registry reverse to their pre-images hunk by hunk, ACLs unmoved; tow_fee_per_nm is read in tow_for alone and the tow is called by cmd.tow, cmd.preview_tow and the merchant upkeep alone; the shipyard is still read in port_has_shipyard alone; two doors for authenticated, the core server-only, one knob, no client write. Probes: %and %. Rolled back.',
    v_ok, v_found;
end $$;
