-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0142 — A MERCHANT SELLS AT THE QUAY'S PRICE WHEN SHE MUST  (and sails only loops that pay)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY ─────────────────────────────────────────────────────────────────────────────────────────
-- A merchant route ("Carrera Guayaquil", NPC) has lain at Guayaquil with lap 14 open since
-- 2026-10-14 17:26: every SELL refused E_PRICE_LIMIT ("bid below your limit of <what she paid>"),
-- every BUY E_INSUFFICIENT_FUNDS / E_HOLD_FULL, every lap a REPAIR refused E_NO_YARD at Realejo.
-- The owner (2026-10-17): fix it, and *"redesign the routes that are like this, and also that gives
-- negative cash."*
--
-- ── WHAT WAS FOUND (prod, read-only, head 0140, 2026-10-17 ~12:00 UTC) ──────────────────────────
-- STUCK LAPS: 819 merchant laps open; 365 open longer than 6 h, 323 longer than 24 h.
--   * 284 of the 365 hold an E_ENDURANCE SAIL ("the passage is longer than her casks"): 2,238
--     such refusals over 404 merchant fleets in 24 h. THIS is what keeps a lap open. Carrera
--     Guayaquil: preset 12 days, GYE -> REA 1,065.8 nm at 3.22 kn needs 15.9. The lap-start choice
--     (0120) raises her preset only for a loop it SWITCHES to; the loop she keeps is never measured
--     against her stores again, and her speed moves under it (wear, skills). She cannot reach her
--     stop 0, so her lap never closes and she never reaches a lap start again.
--   * 240 of them also show a SELL refused E_PRICE_LIMIT, 221 with E_INSUFFICIENT_FUNDS or
--     E_HOLD_FULL beside it — the pattern above. But only 11 merchant fleets (13 parcels of 1,378)
--     hold cargo bought above EVERY bid on their loop: the floor is a symptom of lying still, not
--     the lock.
--   * The other 81 lie UNABLE_TO_SAIL with every hull at durability 0 (89 fleets in all) — and 84 of
--     those 89 have their REPAIR written at a port with no shipyard. They are the REPAIR defect's
--     dead: see "NOT DONE" below.
-- REPAIR WHERE NO YARD IS: 256 merchant routes carry `repair` on a stop with no shipyard (npc_plan
-- writes `'repair', j = 0` — at her home, yard or not). 806 E_NO_YARD refusals over 51 routes in
-- 24 h; 69 merchant loops have no shipyard anywhere on them.
-- LOSING ROUTES (closed laps, last 24 h): 19,453 laps over 514 routes; 15,587 laps net < 0, 270 = 0,
-- 3,596 > 0; median lap -17 d., mean +468. Per route: 182 net < 0, 55 = 0, 277 > 0; median +332.5,
-- mean +17,699. 11,388 laps traded nothing (11,196 of them < 0; mean -34: supplies 22, repairs 12).
-- On the 182 losing routes: sold - bought +377,216, wages 711,388, supplies 362,344, repairs
-- 183,188, loss -482,915. THE CAUSE: the loop's score (0120/0128) is Σ leg profit with each leg's
-- wages taken from THAT leg's profit only, so a ballast leg costs nothing in the score — while
-- 0128 owes wages for every sea-day, ballast days included, paid from the next profit; and the
-- stores she eats are not in the score at all. A loop of one thin trade and long empty legs ranks
-- as paying and sails at a loss.
--
-- ── THE FLOOR WAS NEVER ASKED FOR ───────────────────────────────────────────────────────────────
-- 0120 §6 made the cut-loss line "SELL <good> ALL at what she paid and not a ducat less". The owner
-- never asked for that floor (it is not in docs/OWNER_REQUESTS.md); it was my invention. A defect
-- that comes from a rule I invented is fixed by REMOVING the rule, so it is removed — not given a
-- second check on top. The cut-loss is again what it was before 0120: SELL <good> ALL at the
-- quay's bid. The ordinary at-profit SELL (paid + npc_sell_margin, 0114) stays: it does not lock a
-- merchant by itself — she sails on, and a good refused at a stop two closed laps running becomes
-- the cut-loss, which now lets it go. What locked her was the lap that could not close.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) THE CUT-LOSS HAS NO FLOOR. public.npc_leg_lines writes it `at_profit false` (no AT, the
--     quay's bid), and 0120's renderer hunk in cmd.standing_route_lines (`ln.good_id is null`: a
--     named at-profit SELL floors at cost) is cut back to its pre-0120 text: every merchant
--     at-profit SELL carries the margin, and only the general SELL is at-profit.
-- (2) EVERY LOOP SHE SAILS IS MEASURED AGAINST HER STORES. npc_plan's preset raise (0120: the
--     longest leg's days through endurance_margin, + 1, through cmd.provision_preset_save_for) runs
--     for the loop WRITTEN — her present loop too, at every plan (the lap start, the switch's pass,
--     and the third-clear re-plan that npc_tend gives a lap stuck on a failed order). A refused
--     raise for a chosen loop un-chooses it and her present loop is measured in turn. The stop's
--     render then carries PROVISION DAYS <n> (keep_level_met, 0034) and the SAIL clears.
-- (3) NO REPAIR WHERE NO YARD IS. public.port_has_shipyard(port) — the reading cmd.do_repair
--     refuses E_NO_YARD by (0067: the port_buildings row), lifted out of do_repair into one
--     function (its second caller is the planner) and do_repair re-cut to call it. npc_plan writes
--     `repair` on the FIRST stop of the loop that has a shipyard (her home when it has one, as
--     before), and nowhere when none has.
-- (4) THE SCORE IS WHAT THE LAP LEAVES HER. npc_leg_lines answers the leg's profit after tax and,
--     separately, the wages its sea-days owe; npc_plan takes the wages out of the LOOP's profit
--     once (public.wages_from_profit, 0128 — the rule the sale pays by) and the stores the loop
--     eats (crew x water/food per crew-day x nm / kn days) at public.stores_cost — the price
--     cmd.do_provision charges, lifted into one function and do_provision re-cut to call it. The
--     choice is otherwise 0120's: the best per real hour wins when it beats her present loop by
--     npc_route_switch_pct AND pays more than nothing; a present loop that loses is beaten by any
--     loop that pays. When no loop pays she sails her present one (0115, the owner: "remove laid
--     up"). The note of a switch carries both nets.
-- Repairs are NOT in the score (they ride on wear, not on the loop's length; 12 d. a lap mean).
-- No new knob.
--
-- ── NOT DONE, AND WHY ───────────────────────────────────────────────────────────────────────────
-- * 89 merchant fleets lie UNABLE_TO_SAIL at durability 0, 31 of them in a port with a yard. No
--   verb refloats a fleet for anybody (0115), and cmd.do_repair refuses a fleet that is not DOCKED.
--   They will not recover by themselves; how a wrecked hull is refloated (a REPAIR that accepts
--   UNABLE_TO_SAIL in a yard, a tow, a write-off) is a game rule for players too, and is the owner's.
--   This file stops new ones (no more yardless repairs).
-- * 69 loops have no shipyard on them; they now write no REPAIR at all. Whether the lap-start
--   choice should prefer a loop with a yard is not decided here.
--
-- ── RECOVERY OF THE STUCK ───────────────────────────────────────────────────────────────────────
-- No data is touched. A merchant whose SAIL failed is cleared by npc_tend (hourly); the third clear
-- in one lap re-plans her (0115) — every stuck lap is long past three — and that plan now raises
-- her preset for her own loop; the save door puts her cursor back on the stop she lies at, the
-- executor renders it again with PROVISION DAYS <n>, and she sails.
--
-- SUPERSEDES, by hunks sliced from the LIVE bodies (LF-normalised), each asserted to occur exactly
-- once and reversed to its pre-image: public.npc_leg_lines (0120 as cut by 0122/0128/0129),
-- public.npc_plan (0120), cmd.standing_route_lines (0114 as cut by 0120/0129), cmd.do_repair (0007
-- as cut by 0033/0067/0114), cmd.do_provision (0034 as cut by 0114). ACLs unmoved.
-- Self-asserts hold on a lived-in world: every probe runs on its own founded merchant and rolls
-- back. Timings: raise notice only. VERSION 0142; applies on prod head 0141 (0141 touches
-- none of these bodies).

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

-- ── 1. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0142 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl
  from unnest(array['public.npc_leg_lines(uuid, uuid, uuid, numeric, integer, numeric)',
                    'public.npc_plan(timestamptz, uuid)',
                    'cmd.standing_route_lines(uuid, integer, uuid)',
                    'cmd.do_repair(uuid, jsonb)',
                    'cmd.do_provision(uuid, jsonb)']) f(fn);

create temp table before_0142 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from public.world_config) as knobs;

-- ── 2. THE TWO READINGS, LIFTED ────────────────────────────────────────────────────────────────
create or replace function public.port_has_shipyard(p_port uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  -- 0142: THE reading of "this port has a shipyard" — lifted from cmd.do_repair (0067: the ROW is
  -- the authority; the authored boolean ports.has_yard equals it today and cannot express a yard a
  -- player raises). Read by cmd.do_repair (E_NO_YARD) and by public.npc_plan (where she repairs).
  return exists (select 1 from public.port_buildings b where b.port_id = p_port and b.kind = 'shipyard');
end $$;

create or replace function public.stores_cost(p_player uuid, p_water_t numeric, p_food_t numeric)
returns bigint
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  -- 0142: THE price of stores — tons of water and food at provision_water_price /
  -- provision_food_price through the house's running_cost_mult — lifted from cmd.do_provision
  -- (0114). Read by cmd.do_provision (what she pays) and by public.npc_plan (what a loop will eat).
  return round((coalesce(p_water_t, 0) * public.wc_num('provision_water_price')
                + coalesce(p_food_t, 0) * public.wc_num('provision_food_price'))
               * public.running_cost_mult(p_player))::bigint;
end $$;

revoke all on function public.port_has_shipyard(uuid) from public, anon, authenticated;
revoke all on function public.stores_cost(uuid, numeric, numeric) from public, anon, authenticated;

-- ── 3. THE HUNKS (old → new), sliced from the live bodies ──────────────────────────────────────
create temp table hunks_0142 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0142 values
-- public.npc_leg_lines: the cut-loss has no floor; the leg answers its wages apart from its profit
('public.npc_leg_lines(uuid, uuid, uuid, numeric, integer, numeric)', 1,
$h$--   4. LINES: SELL everything above cost (paid + npc_sell_margin); for a good refused E_PRICE_LIMIT
--      on a SELL here in BOTH of the last two closed laps, the cut-loss: SELL <good> ALL at what she
--      paid and not a ducat less (0120 — it had no floor); BUY <good> <q> AT <ceiling>.
-- Answers {lines, profit, nm, any}: `profit` is the sum of (sink quote - source quote) over the
-- kept goods, `nm` the sailed distance from the reach table (the figure the ranking's rows carry),
-- `any` whether anything was kept.
$h$,
$h$--   4. LINES: SELL everything above cost (paid + npc_sell_margin); for a good refused E_PRICE_LIMIT
--      on a SELL here in BOTH of the last two closed laps, the cut-loss: SELL <good> ALL at the
--      quay's bid, no floor (0142: the at-cost floor 0120 put here was never asked for — removed);
--      BUY <good> <q> AT <ceiling>.
-- Answers {lines, profit, wages, nm, any}: `profit` is the sum of (sink quote - source quote) less
-- the sink's profit tax over the kept goods; `wages` what the leg's sea-days owe (0142: npc_plan
-- takes them out of the LOOP's profit, once — a ballast leg's days are owed too); `nm` the sailed
-- distance from the reach table (the figure the ranking's rows carry); `any` whether anything was kept.
$h$),
('public.npc_leg_lines(uuid, uuid, uuid, numeric, integer, numeric)', 2,
$h$    v_lines := v_lines || jsonb_build_object('kind', 'SELL', 'good', v_cut, 'at_profit', true);   -- 0120: at cost
$h$,
$h$    v_lines := v_lines || jsonb_build_object('kind', 'SELL', 'good', v_cut, 'at_profit', false);   -- 0142: at the quay's bid
$h$),
('public.npc_leg_lines(uuid, uuid, uuid, numeric, integer, numeric)', 3,
$h$  -- 0128: what the leg LEAVES her — its profit less the wages it pays, by the rule the sale pays by.
  return jsonb_build_object('lines', v_lines, 'profit', v_profit - public.wages_from_profit(v_wages, v_profit),
                            'nm', v_nm, 'any', v_any);
$h$,
$h$  -- 0142: the leg's profit after tax, and apart from it the wages its sea-days owe — npc_plan takes
  -- the wages out of the LOOP's profit by the rule the sale pays by (public.wages_from_profit).
  return jsonb_build_object('lines', v_lines, 'profit', v_profit, 'wages', v_wages,
                            'nm', v_nm, 'any', v_any);
$h$),

-- public.npc_plan: the score is what the lap leaves her; her stores cover the loop she sails; she
-- repairs only where a yard is
('public.npc_plan(timestamptz, uuid)', 1,
$h$--     lap — sea time at her speed through time_compression, plus her rest (route_rest_voyage_days).
$h$,
$h$--     lap — sea time at her speed through time_compression, plus her rest (route_rest_voyage_days).
--     0142: the ducats are what the lap LEAVES her — the parcels' profit after tax, less the wages
--     every sea-day of the loop owes and the stores it eats — and the loop she sails, chosen or
--     kept, has her preset raised to cover its longest leg. She repairs at its first shipyard.
$h$),
('public.npc_plan(timestamptz, uuid)', 2,
$h$  v_best_maxnm numeric;
$h$,
$h$  v_best_maxnm numeric;
  v_cur_maxnm numeric;   -- 0142: her present loop's longest leg
  v_wages   numeric;     -- 0142: what every sea-day of a loop owes
  v_net     numeric;     -- 0142: what a lap of the loop leaves her
  v_cur_net numeric;     -- 0142
  v_best_net numeric;    -- 0142
  v_rep     boolean;     -- 0142: a REPAIR is written on this loop already
  v_yard    boolean;     -- 0142: this stop has a shipyard (public.port_has_shipyard)
  v_sea_d   numeric;     -- 0142: the loop's days at sea
  v_try     int;         -- 0142
$h$),
('public.npc_plan(timestamptz, uuid)', 3,
$h$        v_maxnm  := 0;
        v_any    := false;
$h$,
$h$        v_maxnm  := 0;
        v_any    := false;
        v_wages  := 0;       -- 0142
        v_rep    := false;   -- 0142
$h$),
('public.npc_plan(timestamptz, uuid)', 4,
$h$          v_stops  := v_stops || jsonb_build_object('port', v_loop->j->>'code', 'course', v_loop->j->'course',
                                                   'repair', j = 0, 'crew_up', true, 'lines', v_leg->'lines');
          v_profit := v_profit + coalesce((v_leg->>'profit')::numeric, 0);
$h$,
$h$          -- 0142: SHE REPAIRS AT THE FIRST STOP OF THE LOOP THAT HAS A SHIPYARD (public.port_has_shipyard,
          -- the reading cmd.do_repair refuses E_NO_YARD by) — never where no yard is.
          v_yard   := not v_rep and public.port_has_shipyard(v_from);
          v_rep    := v_rep or v_yard;
          v_stops  := v_stops || jsonb_build_object('port', v_loop->j->>'code', 'course', v_loop->j->'course',
                                                   'repair', v_yard, 'crew_up', true, 'lines', v_leg->'lines');
          v_profit := v_profit + coalesce((v_leg->>'profit')::numeric, 0);
          v_wages  := v_wages + coalesce((v_leg->>'wages')::numeric, 0);   -- 0142
$h$),
('public.npc_plan(timestamptz, uuid)', 5,
$h$        v_score := v_profit / greatest(v_nm / v_speed / v_comp + v_rest_h, v_day_h);
        if i = 0 then
          v_cur_stops := v_stops; v_cur_score := v_score; v_cur_any := v_any;
          v_best_stops := v_stops; v_best_score := v_score; v_best_any := v_any; v_best_maxnm := v_maxnm;
        elsif v_score > v_best_score then
          v_best_i := i; v_best_stops := v_stops; v_best_score := v_score; v_best_any := v_any; v_best_maxnm := v_maxnm;
        end if;
$h$,
$h$        -- 0142: WHAT THE LAP LEAVES HER — the parcels' profit after tax, less the wages every sea-day
        -- of the loop owes (paid from that profit and never past it: public.wages_from_profit, once
        -- for the loop, so a ballast leg's days count), less the stores the loop eats
        -- (public.stores_cost, the price cmd.do_provision charges, for her crew over nm / kn days).
        v_sea_d := v_nm / (v_speed * 24);
        v_net   := v_profit - public.wages_from_profit(v_wages, v_profit)
                   - public.stores_cost(sr.player_id, v_crew * public.wc_num('water_per_crew_day') * v_sea_d,
                                        v_crew * public.wc_num('food_per_crew_day') * v_sea_d);
        v_score := v_net / greatest(v_nm / v_speed / v_comp + v_rest_h, v_day_h);
        if i = 0 then
          v_cur_stops := v_stops; v_cur_score := v_score; v_cur_any := v_any; v_cur_maxnm := v_maxnm; v_cur_net := v_net;
          v_best_stops := v_stops; v_best_score := v_score; v_best_any := v_any; v_best_maxnm := v_maxnm; v_best_net := v_net;
        elsif v_score > v_best_score then
          v_best_i := i; v_best_stops := v_stops; v_best_score := v_score; v_best_any := v_any; v_best_maxnm := v_maxnm; v_best_net := v_net;
        end if;
$h$),
('public.npc_plan(timestamptz, uuid)', 6,
$h$      if v_best_i <> 0 then
        -- A LONGER LEG THAN HER STORES COVER raises her preset through the preset core (the
        -- candidates already stop at npc_preset_days_max and half her hold).
        v_days := ceil(v_best_maxnm / (v_speed * 24) * v_emargin)::int + 1;
        select pr.days into v_preset from public.provision_presets pr where pr.id = f.provision_preset_id;
        if v_preset is not null and v_days > v_preset then
          v_res := cmd.provision_preset_save_for(sr.player_id, f.provision_preset_id, null, v_days);
          if not coalesce((v_res->>'ok')::boolean, false) then
            v_notes := v_notes || jsonb_build_object('route', sr.name, 'preset_refused', v_res->>'error_code');
            v_best_i := 0;
          end if;
        end if;
      end if;
$h$,
$h$      -- A LONGER LEG THAN HER STORES COVER raises her preset through the preset core. 0142: FOR THE
      -- LOOP SHE WILL SAIL, chosen or kept — a kept loop was never measured again, her speed moved
      -- under it, and her SAIL was refused E_ENDURANCE for ever. A chosen loop whose raise is
      -- refused is not chosen, and her present loop is measured in turn.
      for v_try in 1 .. 2 loop
        v_days := ceil((case when v_best_i <> 0 then v_best_maxnm else v_cur_maxnm end)
                       / (v_speed * 24) * v_emargin)::int + 1;
        select pr.days into v_preset from public.provision_presets pr where pr.id = f.provision_preset_id;
        exit when v_preset is null or v_days <= v_preset;
        v_res := cmd.provision_preset_save_for(sr.player_id, f.provision_preset_id, null, v_days);
        exit when coalesce((v_res->>'ok')::boolean, false);
        v_notes := v_notes || jsonb_build_object('route', sr.name, 'preset_refused', v_res->>'error_code');
        exit when v_best_i = 0;
        v_best_i := 0;
      end loop;
$h$),
('public.npc_plan(timestamptz, uuid)', 7,
$h$                     'per_hour', round(v_best_score), 'was', round(v_cur_score));
$h$,
$h$                     'per_hour', round(v_best_score), 'was', round(v_cur_score),
                     'net', round(v_best_net), 'was_net', round(v_cur_net));   -- 0142
$h$),

-- cmd.standing_route_lines: 0120's floor-at-cost hunk, cut back to its pre-0120 rule
('cmd.standing_route_lines(uuid, integer, uuid)', 1,
$h$      -- 0120: the margin is the GENERAL at-profit SELL's (no good named). A NAMED at-profit SELL
      -- is the cut-loss: she lets that parcel go at what she paid, and never below.
      if v_npc and ln.at_profit and ln.good_id is null and v_floor is not null then
$h$,
$h$      -- 0142: the cut-loss is a named SELL with no floor (at_profit false: the quay's bid), so a
      -- merchant's at-profit SELL — the general one — always carries the margin.
      if v_npc and ln.at_profit and v_floor is not null then
$h$),

-- cmd.do_repair: the yard through the one reading
('cmd.do_repair(uuid, jsonb)', 1,
$h$  select exists (select 1 from public.port_buildings b
                  where b.port_id = f.port_id and b.kind = 'shipyard'),
         p.dev_industry
    into v_yard, v_dev
$h$,
$h$  select public.port_has_shipyard(p.id),   -- 0142: the one reading of a yard
         p.dev_industry
    into v_yard, v_dev
$h$),

-- cmd.do_provision: the price of stores through the one reading
('cmd.do_provision(uuid, jsonb)', 1,
$h$  r        record;
  v_wp     numeric := public.wc_num('provision_water_price');
  v_fp     numeric := public.wc_num('provision_food_price');
$h$,
$h$  r        record;
$h$),
('cmd.do_provision(uuid, jsonb)', 2,
$h$  v_cost := round((v_water * v_wp + v_food * v_fp) * public.running_cost_mult(f.player_id))::bigint;   -- 0114
$h$,
$h$  v_cost := public.stores_cost(f.player_id, v_water, v_food);   -- 0142: the one price of stores
$h$);

-- ── 4. THE RE-CUTS ─────────────────────────────────────────────────────────────────────────────
create or replace function pg_temp.recut_0142(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0142 where fn = p_fn order by n loop
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0142 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0142(fn) from defs_before_0142 order by fn;

-- set the probe merchant's purse, through the ledger (the purse reconciles with it).
create or replace function pg_temp.purse_0142(p_player uuid, p_ducats numeric)
returns void language sql
as $$ select public.credit(p_player, 'PROBE_0142',
                           (p_ducats - (select ducats from public.players where id = p_player))::bigint) $$;

-- ── 5. SELF-ASSERT ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_fn       text;
  v_def      text;
  v_back     text;
  h          record;
  v_n        int;
  v_list     text[];
  v_lis      uuid;
  v_fnc      uuid;
  v_leg      jsonb;
  v_back_c   jsonb;
  v_m        uuid;
  v_mfleet   uuid;
  v_route    uuid;
  v_preset   uuid;
  v_good     uuid;
  v_code     text;
  v_bulk     numeric;
  v_qty      numeric;
  v_lines    text[];
  v_res      jsonb;
  v_plan     jsonb;
  v_ducats0  bigint;
  v_left     numeric;
  v_hold     numeric;
  v_crew     int;
  v_speed    numeric;
  v_days     int;
  v_y        record;
  v_s        record;
  v_note     jsonb;
  v_found    text := '';
  v_tried    int := 0;
  v_chosen   int := 0;
  v_t0       timestamptz;
  v_ms       numeric := 0;
  v_k        int := 0;
  v_ok_lines text := '';
  v_was_on   boolean := public.npc_traders_on();
  v_routes_on boolean := public.standing_routes_on();
begin
  -- (a) PARITY BY REVERSE SUBSTITUTION; ACLs unmoved; each hunk in its new body exactly once.
  for v_fn in select fn from defs_before_0142 loop
    v_def := replace(pg_get_functiondef(v_fn::regprocedure), E'\r', '');
    v_back := v_def;
    for h in select * from hunks_0142 where fn = v_fn order by n desc loop
      v_n := (length(v_back) - length(replace(v_back, h.new, ''))) / length(h.new);
      if v_n <> 1 then
        raise exception '0142 self-assert FAIL: hunk % of % is in the new body % time(s), not once', h.n, v_fn, v_n;
      end if;
      v_back := replace(v_back, h.new, h.old);
    end loop;
    if v_back <> (select def from defs_before_0142 where fn = v_fn) or v_def = v_back then
      raise exception '0142 self-assert FAIL: % is not its pre-image plus only 0142''s hunks', v_fn;
    end if;
    if coalesce((select p.proacl::text from pg_proc p where p.oid = v_fn::regprocedure), '')
       is distinct from (select acl from defs_before_0142 where fn = v_fn) then
      raise exception '0142 self-assert FAIL: the re-cut moved the ACL of %', v_fn;
    end if;
  end loop;

  -- (b) ONE AUTHORITY EACH, scanned over every live body.
  select array_agg(n.nspname || '.' || p.proname order by n.nspname || '.' || p.proname) into v_list
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prosrc ~ 'kind\s*=\s*''shipyard''';
  if v_list is distinct from array['public.port_has_shipyard'] then
    raise exception '0142 self-assert FAIL: "this port has a shipyard" is read in %, not in port_has_shipyard alone', v_list;
  end if;
  select array_agg(n.nspname || '.' || p.proname order by n.nspname || '.' || p.proname) into v_list
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage')
     and (p.prosrc like '%provision_water_price%' or p.prosrc like '%provision_food_price%');
  if v_list is distinct from array['public.stores_cost'] then
    raise exception '0142 self-assert FAIL: the price of stores is read in %, not in stores_cost alone', v_list;
  end if;
  select array_agg(n.nspname || '.' || p.proname order by n.nspname || '.' || p.proname) into v_list
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prosrc like '%npc_leg_lines(%'
     and p.oid <> 'public.npc_leg_lines(uuid, uuid, uuid, numeric, integer, numeric)'::regprocedure;
  if v_list is distinct from array['public.npc_plan'] then
    raise exception '0142 self-assert FAIL: the leg planner''s answer (profit now apart from wages) is read by %, not by npc_plan alone', v_list;
  end if;
  if strpos(pg_get_functiondef('public.npc_plan(timestamptz, uuid)'::regprocedure), 'public.port_has_shipyard(v_from)') = 0
     or strpos(pg_get_functiondef('public.npc_plan(timestamptz, uuid)'::regprocedure), 'public.wages_from_profit(v_wages, v_profit)') = 0
     or strpos(pg_get_functiondef('public.npc_plan(timestamptz, uuid)'::regprocedure), 'public.stores_cost(sr.player_id,') = 0
     or strpos(pg_get_functiondef('public.npc_plan(timestamptz, uuid)'::regprocedure), $q$'repair', j = 0$q$) > 0
     or strpos(pg_get_functiondef('public.npc_leg_lines(uuid, uuid, uuid, numeric, integer, numeric)'::regprocedure), 'public.wages_from_profit(v_wages') > 0
     or strpos(pg_get_functiondef('public.npc_leg_lines(uuid, uuid, uuid, numeric, integer, numeric)'::regprocedure), $q$'good', v_cut, 'at_profit', true$q$) > 0
     or strpos(pg_get_functiondef('cmd.standing_route_lines(uuid, integer, uuid)'::regprocedure), 'ln.good_id is null and v_floor') > 0
     or strpos(pg_get_functiondef('cmd.do_repair(uuid, jsonb)'::regprocedure), 'public.port_has_shipyard(p.id)') = 0
     or strpos(pg_get_functiondef('cmd.do_provision(uuid, jsonb)'::regprocedure), 'public.stores_cost(f.player_id, v_water, v_food)') = 0 then
    raise exception '0142 self-assert FAIL: a re-cut did not compose the one reading, or the floor at cost survived';
  end if;

  -- (c) THE WALL: server-only, no new entry point, no client write, no new knob.
  if has_function_privilege('authenticated', 'public.port_has_shipyard(uuid)', 'execute')
     or has_function_privilege('anon', 'public.port_has_shipyard(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.stores_cost(uuid, numeric, numeric)', 'execute')
     or has_function_privilege('anon', 'public.stores_cost(uuid, numeric, numeric)', 'execute') then
    raise exception '0142 self-assert FAIL: a lifted reading is client-reachable';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from before_0142)
     or (select count(*) from public.world_config) <> (select knobs from before_0142)
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0142 self-assert FAIL: the registry, the knobs, the grant wall or the read wall moved';
  end if;

  -- (d) THE TWO READINGS answer what the bodies they came from answered.
  select count(*) into v_n from public.ports p
   where public.port_has_shipyard(p.id) is distinct from
         exists (select 1 from public.port_buildings b where b.port_id = p.id and b.kind = 'shipyard');
  if v_n <> 0 or not exists (select 1 from public.ports p where public.port_has_shipyard(p.id))
     or not exists (select 1 from public.ports p where p.kind = 'HARBOUR' and not public.port_has_shipyard(p.id)) then
    raise exception '0142 self-assert FAIL: port_has_shipyard disagrees with the rows on % port(s), or the world has no yard / no yardless harbour to tell apart', v_n;
  end if;

  -- (e) THE PROBES, on a merchant of the probe's own, rolled back.
  select id into v_lis from public.ports where code = 'LIS';
  select id into v_fnc from public.ports where code = 'FNC';
  select jsonb_build_array(jsonb_build_array(ra.roadstead_lat, ra.roadstead_lon),
                           jsonb_build_array(rb.roadstead_lat, rb.roadstead_lon))
    into v_leg from public.sea_reaches ra, public.sea_reaches rb
   where ra.port_id = v_lis and rb.port_id = v_fnc;
  v_back_c := jsonb_build_array(v_leg->1, v_leg->0);
  begin
    update public.world_config set value = 'true'::jsonb where key = 'npc_traders_enabled';
    update public.world_config set value = 'true'::jsonb where key = 'standing_routes_enabled';
    perform set_config('byeharu.npc_upkeep_deadline', '', true);
    if not public.npc_traders_on() then
      raise exception '0142 self-assert FAIL: the probe could not light the merchants';
    end if;
    v_m := public.npc_found(jsonb_build_object(
      'company', 'Casa da Venda Forcada', 'alt_company', 'Casa do Cais', 'nation', 'PRT', 'ink', 'prt',
      'master', 'Capitao Desfeito',
      'blurb', 'A probe company founded so that a merchant who must sell can be seen to sell.',
      'capital', 40000, 'patience', 0.20, 'wares', '[]'::jsonb, 'roster_ord', 9142,
      'skills', '{}'::jsonb,
      'fleets', jsonb_build_array(jsonb_build_object(
        'name', 'Desfeita', 'roster_ord', 9142, 'days', 12,
        'ships', jsonb_build_array(jsonb_build_object('class', 'nau', 'name', 'Desfeita')),
        'officers', '[]'::jsonb,
        'stops', jsonb_build_array(jsonb_build_object('port', 'LIS', 'course', v_leg),
                                   jsonb_build_object('port', 'FNC', 'course', v_back_c)),
        'alt_stops', jsonb_build_array(jsonb_build_object('port', 'LIS', 'course', v_leg),
                                       jsonb_build_object('port', 'FNC', 'course', v_back_c))))));
    select nf.fleet_id, nf.route_id into v_mfleet, v_route from public.npc_fleets nf
     where nf.player_id = v_m order by nf.roster_ord limit 1;   -- the probe founded exactly one
    select f.provision_preset_id into v_preset from public.fleets f where f.id = v_mfleet;
    if v_mfleet is null or v_route is null or v_preset is null then
      raise exception '0142 self-assert FAIL: the probe merchant was founded without a fleet, a route or a preset';
    end if;
    -- SHE LIES AT HER STOP 0, MID-LAP (the re-plan a stuck lap gets: no loop choice).
    update public.voyages set status = 'ARRIVED' where fleet_id = v_mfleet and status = 'SAILING';
    update public.fleets set status = 'DOCKED', port_id = v_lis, lat = null, lon = null where id = v_mfleet;
    update public.ships set cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb where fleet_id = v_mfleet;
    insert into public.standing_route_laps (route_id, lap_no, started_at, closed_at, skipped)
    select v_route, 900140 + k, now() - make_interval(hours => 4 - k), now() - make_interval(hours => 3 - k), '[]'::jsonb
      from generate_series(1, 2) k;
    insert into public.standing_route_laps (route_id, lap_no, started_at)
    values (v_route, 900143, now() - interval '1 hour');
    update public.standing_routes set fleet_id = v_mfleet, lap_no = 900143, stop_cursor = 0, paused_reason = null,
                                      hold_until = null,
                                      lap_id = (select id from public.standing_route_laps where route_id = v_route and lap_no = 900143)
     where id = v_route;

    -- THE SUBJECT GOOD: one LIS bids for (a sale of 1 pays something), the first by id.
    select g.id, g.code, g.bulk into v_good, v_code, v_bulk
      from public.port_goods pg join public.goods g on g.id = pg.good_id
      cross join lateral world.quote(v_lis, pg.good_id, 1, 'sell', null, null) q
     where pg.port_id = v_lis and q.units >= 1 and q.total > 0
     order by g.id limit 1;
    if v_good is null then
      raise exception '0142 self-assert FAIL: LIS bids for no good to probe the cut-loss with';
    end if;

    -- (e1) A FULL HOLD OF IT, BOUGHT FAR ABOVE ANY BID, AN EMPTY PURSE.
    v_qty := least(floor(public.fleet_free_hold(v_mfleet) / greatest(v_bulk, 0.001)), 200);
    if v_qty < 1 then
      raise exception '0142 self-assert FAIL: the probe hull has no room for one unit of %', v_code;
    end if;
    perform public.fleet_load(v_mfleet, v_code, v_qty, 1000000);
    perform pg_temp.purse_0142(v_m, 0);

    -- POSITIVE CONTROL: with no refusal on record the plan's general SELL floors at cost + margin,
    -- and that line is refused at LIS.
    v_plan := public.npc_plan(now(), v_route);
    if (v_plan->>'planned')::int is distinct from 1 or (v_plan->>'failed')::int is distinct from 0 then
      raise exception '0142 self-assert FAIL: the mid-lap plan answered %', v_plan;
    end if;
    v_lines := cmd.standing_route_lines(v_route, 0, v_mfleet);
    if not exists (select 1 from unnest(v_lines) l where l like format('SELL %s ALL AT >= %%', v_code)) then
      raise exception '0142 self-assert FAIL: POSITIVE CONTROL — the general SELL did not floor %: %', v_code, v_lines;
    end if;

    -- THE CUT-LOSS: refused at LIS in both of her last two closed laps — the plan lets it go at the
    -- quay's bid (no AT), and the sale goes through with her hold full and her purse empty.
    update public.standing_route_laps
       set skipped = jsonb_build_array(jsonb_build_object('port', 'LIS', 'verb', 'SELL', 'code', 'E_PRICE_LIMIT',
                                                          'line', format('SELL %s ALL AT >= 1050000', v_code)))
     where route_id = v_route and lap_no in (900141, 900142);
    v_res := public.npc_leg_lines(v_route, v_lis, v_fnc, 400, 0, 6);
    if not (v_res->'lines' @> jsonb_build_array(jsonb_build_object('kind', 'SELL', 'good', v_code, 'at_profit', false))) then
      raise exception '0142 self-assert FAIL: the leg planner wrote no unfloored cut-loss for %: %', v_code, v_res->'lines';
    end if;
    update public.standing_routes set updated_at = now() - interval '2 minutes' where id = v_route;
    v_plan := public.npc_plan(now(), v_route);
    v_lines := cmd.standing_route_lines(v_route, 0, v_mfleet);
    if not (v_lines @> array[format('SELL %s ALL', v_code)])
       or exists (select 1 from unnest(v_lines) l where l like format('SELL %s ALL AT%%', v_code)) then
      raise exception '0142 self-assert FAIL: the cut-loss rendered with a floor: %', v_lines;
    end if;
    select ducats into v_ducats0 from public.players where id = v_m;
    v_res := cmd.do_sell(v_mfleet, cmd.parse(v_m, v_mfleet, format('SELL %s ALL', v_code))->'args');
    select coalesce(sum((s.cargo->>v_code)::numeric), 0) into v_left from public.ships s where s.fleet_id = v_mfleet;
    if v_left >= v_qty or (select ducats from public.players where id = v_m) <= v_ducats0 then
      raise exception '0142 self-assert FAIL: the full-hold merchant did not sell (% of % left, purse % -> %): %',
        v_left, v_qty, v_ducats0, (select ducats from public.players where id = v_m), v_res;
    end if;
    v_ok_lines := format('a full hold of %s %s bought at 1,000,000 a unit, purse 0: the general SELL rendered at a floor and the cut-loss rendered "SELL %s ALL" and sold %s of them for %s d.; ',
                         v_qty, v_code, v_code, v_qty - v_left, (select ducats from public.players where id = v_m) - v_ducats0);

    -- (e2) HER STORES COVER THE LOOP SHE KEEPS. Preset cut to 1 day: the mid-lap plan raises it to
    --      the longest leg's days through endurance_margin + 1, and the stop renders PROVISION DAYS.
    update public.provision_presets set days = 1 where id = v_preset;
    update public.ships set water_t = 0, food_t = 0 where fleet_id = v_mfleet;   -- so the keep level is not met
    select coalesce(sum(c.crew_required), 0) into v_crew
      from public.ships s join public.ship_classes c on c.id = s.class_id where s.fleet_id = v_mfleet;
    v_speed := greatest(coalesce(voyage.fleet_speed(v_mfleet), 0), 0.1);
    select ceil(max(r.nm) / (v_speed * 24) * public.wc_num('endurance_margin'))::int + 1 into v_days
      from public.standing_route_stops s
      join public.standing_route_stops s2 on s2.route_id = s.route_id and s2.ord = (s.ord + 1) % 2
      cross join lateral voyage.reach_from(s.port_id) r
     where s.route_id = v_route and r.port_id = s2.port_id;
    if v_days is null or v_days <= 1 then
      raise exception '0142 self-assert FAIL: the probe loop needs % day(s) of stores — no subject', v_days;
    end if;
    update public.standing_routes set updated_at = now() - interval '2 minutes' where id = v_route;
    v_plan := public.npc_plan(now(), v_route);
    v_lines := cmd.standing_route_lines(v_route, 0, v_mfleet);
    if (select days from public.provision_presets where id = v_preset) <> v_days
       or not (v_lines @> array[format('PROVISION DAYS %s', v_days)]) then
      raise exception '0142 self-assert FAIL: her kept loop needs % days and her preset reads % (lines %)',
        v_days, (select days from public.provision_presets where id = v_preset), v_lines;
    end if;
    v_ok_lines := v_ok_lines || format('a kept loop needing %s days raised a 1-day preset to %s and rendered PROVISION DAYS %s; ',
                                       v_days, (select days from public.provision_presets where id = v_preset), v_days);

    -- (e3) NO REPAIR WHERE NO YARD IS. Her loop becomes Y -> B -> Y, Y a yardless harbour with a
    --      known course to a yard harbour B (the first such pair by code): the plan writes the
    --      repair at B, none at Y, and Y's render carries no REPAIR.
    select y.id as y_id, y.code as y_code, l.to_port as b_id, l.code as b_code, l.course as y_to_b,
           (select l2.course from public.npc_known_legs(l.to_port) l2 where l2.to_port = y.id) as b_to_y
      into v_y
      from public.ports y cross join lateral public.npc_known_legs(y.id) l
     where y.kind = 'HARBOUR' and not public.port_has_shipyard(y.id) and public.port_has_shipyard(l.to_port)
       and exists (select 1 from public.npc_known_legs(l.to_port) l2 where l2.to_port = y.id)
     order by y.code, l.code limit 1;
    if v_y.y_id is null then
      raise exception '0142 self-assert FAIL: no yardless harbour with a known way to a yard and back — no subject';
    end if;
    update public.ships set cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb where fleet_id = v_mfleet;
    update public.standing_route_stops set port_id = v_y.y_id, course = v_y.y_to_b where route_id = v_route and ord = 0;
    update public.standing_route_stops set port_id = v_y.b_id, course = v_y.b_to_y where route_id = v_route and ord = 1;
    update public.fleets set port_id = v_y.y_id where id = v_mfleet;
    update public.standing_routes set updated_at = now() - interval '2 minutes' where id = v_route;
    v_plan := public.npc_plan(now(), v_route);
    if (v_plan->>'planned')::int is distinct from 1 then
      raise exception '0142 self-assert FAIL: the yardless loop was not planned: %', v_plan;
    end if;
    v_lines := cmd.standing_route_lines(v_route, 0, v_mfleet);
    if (select repair from public.standing_route_stops where route_id = v_route and ord = 0)
       or not (select repair from public.standing_route_stops where route_id = v_route and ord = 1)
       or 'REPAIR' = any(v_lines) then
      raise exception '0142 self-assert FAIL: on % (no yard) -> % (yard) the repair is written at %',
        v_y.y_code, v_y.b_code, (select array_agg(ord order by ord) from public.standing_route_stops where route_id = v_route and repair);
    end if;
    v_ok_lines := v_ok_lines || format('loop %s (no yard) -> %s (yard) repairs at %s only; ', v_y.y_code, v_y.b_code, v_y.b_code);

    -- (e4) A LOSING LOOP IS LEFT FOR ONE THAT PAYS. Her present loop becomes the farthest known
    --      out-and-back from a merchant home, purse 5,000 d.; at her lap start the plan prices it
    --      and the candidates by what a lap leaves her. Subjects in roster order, the first where her
    --      present loop leaves nothing (net <= 0) and a candidate pays. Every switch, on any subject,
    --      must leave her more than nothing.
    update public.standing_route_laps set closed_at = now() where id = (select lap_id from public.standing_routes where id = v_route);
    for v_s in
      with homes as (
        select y.h, y.roster_ord from (
          select distinct on (s0.port_id) s0.port_id as h, nf.roster_ord
            from public.npc_fleets nf join public.standing_route_stops s0 on s0.route_id = nf.route_id and s0.ord = 0
           where nf.player_id <> v_m
           order by s0.port_id, nf.roster_ord) y
         order by y.roster_ord, y.h limit 40)
      select hm.h, hm.roster_ord, far.to_port as f, far.course as hf, back.course as fh
        from homes hm
        cross join lateral (select l.to_port, l.course from public.npc_known_legs(hm.h) l
                             order by l.nm desc, l.to_port limit 1) far
        cross join lateral (select l2.course from public.npc_known_legs(far.to_port) l2
                             where l2.to_port = hm.h) back
       order by hm.roster_ord, hm.h
    loop
      v_tried := v_tried + 1;
      begin
        update public.standing_route_stops set port_id = v_s.h, course = v_s.hf where route_id = v_route and ord = 0;
        update public.standing_route_stops set port_id = v_s.f, course = v_s.fh where route_id = v_route and ord = 1;
        update public.fleets set status = 'DOCKED', port_id = v_s.h where id = v_mfleet;
        update public.standing_routes set fleet_id = v_mfleet, lap_id = null, stop_cursor = 0, paused_reason = null,
                                          hold_until = null, updated_at = now() - interval '2 minutes'
         where id = v_route;
        perform pg_temp.purse_0142(v_m, 5000);
        v_t0 := clock_timestamp();
        v_plan := public.npc_plan(now(), v_route);
        v_ms := v_ms + extract(epoch from clock_timestamp() - v_t0) * 1000; v_k := v_k + 1;
        if (v_plan->>'planned')::int is distinct from 1 or (v_plan->>'failed')::int is distinct from 0 then
          raise exception '0142 self-assert FAIL: the lap-start plan from % answered %', v_s.h, v_plan;
        end if;
        v_note := (select x from jsonb_array_elements(v_plan->'notes') x where x ? 'chosen' limit 1);   -- one route planned
        if v_note is not null then
          v_chosen := v_chosen + 1;
          if (v_note->>'net')::numeric <= 0 or (v_note->>'per_hour')::numeric <= 0 then
            raise exception '0142 self-assert FAIL: the plan chose a loop that leaves her nothing: %', v_note;
          end if;
          if (v_note->>'was_net')::numeric <= 0 then
            if (select array_agg(port_id order by ord) from public.standing_route_stops where route_id = v_route)
               = array[v_s.h, v_s.f] then
              raise exception '0142 self-assert FAIL: a switch was noted and her stops did not change: %', v_note;
            end if;
            v_found := format('from %s her out-and-back to %s was worth %s d. a lap and she took %s, worth %s (%s d. a real hour, was %s)',
                              (select code from public.ports where id = v_s.h), (select code from public.ports where id = v_s.f),
                              v_note->>'was_net', v_note->>'chosen', v_note->>'net', v_note->>'per_hour', v_note->>'was');
            raise exception 'KEEP_0142';
          end if;
        end if;
        raise exception 'ROLLBACK_0142_ONE';
      exception when others then
        if sqlerrm = 'KEEP_0142' then exit; end if;
        if sqlerrm <> 'ROLLBACK_0142_ONE' then raise; end if;
      end;
    end loop;
    if v_found = '' then
      raise exception '0142 self-assert FAIL: none of % merchant homes tried gave a losing loop and one that pays (% switches seen)', v_tried, v_chosen;
    end if;

    raise exception 'ROLLBACK_0142';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0142' then raise; end if;
  end;
  if exists (select 1 from public.npc_houses where roster_ord = 9142)
     or exists (select 1 from public.standing_route_laps where lap_no between 900141 and 900143)
     or public.npc_traders_on() is distinct from v_was_on or public.standing_routes_on() is distinct from v_routes_on then
    raise exception '0142 self-assert FAIL: the probe world was not rolled back';
  end if;

  raise notice '0142 lap-start plans over % home(s): mean % ms', v_k, round(v_ms / greatest(v_k, 1));
  raise notice '0142 self-assert ok: A MERCHANT SELLS AT THE QUAY''S PRICE WHEN SHE MUST. npc_leg_lines, npc_plan, standing_route_lines, do_repair and do_provision reverse to their pre-images hunk by hunk, ACLs unmoved; "a shipyard" is read in port_has_shipyard alone and "the price of stores" in stores_cost alone (each agrees with the body it left); only npc_plan reads the leg planner; no floor at cost survives; server-only, no new entry point, no new knob, no client write. Probes: %the first of % home(s) tried: %; every one of % switch(es) seen leaves her more than nothing. Rolled back.',
    v_ok_lines, v_tried, v_found, v_chosen;
end $$;
