-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0114 — THE MERCHANTS ARE TENDED INSIDE THE HOUR
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER'S WORDS ───────────────────────────────────────────────────────────────────────────
-- 2026-10-14: *"I saw no NPC."* Production that morning, 837 merchant routes: 521 laid up (every
-- one dated 2026-10-11 14:33:08, the switch's own transaction), 223 paused 'losing' and climbing,
-- 86 sailing. Nine merchants in ten were lying in port.
--
-- ── WHAT WAS FOUND, MEASURED ON PRODUCTION (rolled-back transactions) ──────────────────────────
-- 1. THE HOURLY UPKEEP HAD NOT COMMITTED SINCE THE SWITCH WAS THROWN. `tick_reconcile` (0097's
--    re-cut) runs npc_tend, npc_plan and npc_compact in ONE cron statement, and the server's
--    statement_timeout is 2 min (configuration file). cron.job_run_details: 13 ms a run while
--    the switch was off, the clock stopped 10-11 13:07 → 10-13 01:07, and EVERY run since
--    10-13 02:07 "canceling statement due to statement timeout" at 2:00.000. The per-step
--    `exception when others` does not catch query_canceled, so each hour the whole upkeep rolled
--    back. Measured: npc_plan's full pass 114 s (230 planned, ~0.5 s a route); a 'losing' lift
--    0.34 s; a laid-up re-plan 0.09 s; npc_compact more than 60 s (killed at 60 s).
-- 2. npc_compact WAS QUADRATIC. Every merchant event it deletes is FK-checked against
--    `ledger.ref_event_id` (and its own NOT EXISTS reads the same column), which had NO index:
--    29,803 events × a seq scan of 102,253 ledger rows. With the index below the whole two-day
--    backlog compacts in 5.2 s (5,858 voyages, 93,904 ledger rows rolled, 26,728 events).
-- 3. ONE BUYER PER (port, good) LEFT 60 % OF THE ROSTER WITH NOTHING TO CARRY. 0105's header
--    said so on the day (491 of 761 found no cargo), and production agrees: 80 laid-up routes
--    re-planned alone found cargo for ONE. With the cap at two buyers, 145 of 150; with none,
--    75 of 80. 0105 puts about 3.5 fleets on every loop, all calling at the same harbours; one
--    slot per good cannot carry them.
-- 4. WHY 'losing': the lines were planned once (10-11) and never again, because the re-plan
--    lives in the upkeep that never committed — the cut-loss never fired (877 SELLs refused
--    E_PRICE_LIMIT), purses ran dry (1,065 BUYs refused E_INSUFFICIENT_FUNDS) and no refound ran.
--    The loss guard is NOT wrong for merchants: npc_tend already lifts a 'losing' pause at once
--    onto freshly planned lines (0097 §7). It was never reached. So the guard stays.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) `ledger_ref_event_id` — the missing index under the FK and the compactor's NOT EXISTS.
-- (2) THE UPKEEP HAS A BUDGET, and ONE place sets it. `tick_reconcile` (re-cut by a slice of its
--     LIVE body, 0097's hunk shape) sets the transaction-local `byeharu.npc_upkeep_deadline` to
--     now + `npc_upkeep_budget_seconds` (60 — half the 2-min statement timeout, so tend + plan,
--     then compact and the invariants, finish inside it) and clears it after the compactor.
--     `public.npc_upkeep_spent()` is the ONE reading of it. Unset — the switch, a proof, a probe,
--     this migration — means no budget at all, so every other caller behaves exactly as before.
-- (3) It SUPERSEDES 0097's `public.npc_plan` (0097:372) and `public.npc_tend` (0097:574), restated
--     whole from 0097 with these changes and no others:
--       npc_plan — past the deadline a route is not begun (`deferred`); the pass takes the route
--         planned LONGEST AGO first (updated_at) instead of (hour mod n), because a budgeted pass
--         rotated by one index an hour would re-plan the same head of the roster for ever; and
--         the buyer rule is ONE count for both modes, at most `npc_buyers_per_good` (3) OTHER
--         merchant routes' BUY lines at that (port, good), a route laid up or in error excepted.
--         The pass's temp table and its (hour mod n) `start` receipt are deleted with it.
--       npc_tend — the same oldest-first walk (k stays the ROSTER rank, which npc_fleet_max reads),
--         and the deadline gates the dear work only: a plan + start/resume, and the halt law's
--         release. Dark and cannot-sail lay-ups stay unconditional.
-- (4) THE IDLE MERCHANTS ARE PUT BACK TO SEA BY THE ONE SWITCH. As found lit (production), this
--     file calls `public.npc_traders_switch(true)` — the switch's own plan-then-tend, unbudgeted —
--     which re-plans every running route and lifts every 'losing' and aged 'laid_up' route through
--     npc_tend's plan → start/resume. No route is updated by hand. As found dark (a fresh chain,
--     CI), the switch is not touched and nothing sails.
--
-- ── WHAT IT DOES NOT TOUCH ──────────────────────────────────────────────────────────────────────
-- The executor's loss guard (0092 `stop_after_losing_laps`) and every player's route; the five
-- cron jobs and their schedules (wind_the_clock owns them); npc_compact's body; npc_fleet_max;
-- the price, ranking and quote authorities the planner calls.
--
-- ── SELF-ASSERTS, AS FOUND ──────────────────────────────────────────────────────────────────────
-- Lit or dark, the probes run inside a rolled-back block and the switch is left as found
-- (0113's lesson, 2026-10-14). The budget, the buyer cap (positive control: a cap of 0 lays a
-- route up, deterministically, whatever the market) and the single setter are asserted
-- structurally and by behaviour; when lit, the resume is then asserted on the real roster: no
-- merchant left 'losing', none left laid up past npc_laid_up_hours, no failed plan or tend.
--
-- Depends ONLY on: public.npc_plan / npc_tend / npc_traders_switch (0097), public.tick_reconcile
-- (0010, re-cut 0097), cmd.standing_route_set_paused (0092), public.world_config (0001).

do $guard$ begin perform set_config('statement_timeout', '20min', true); end $guard$;

-- ── 1. THE INDEX THE COMPACTOR WAS MISSING ─────────────────────────────────────────────────────
create index if not exists ledger_ref_event_id on public.ledger (ref_event_id) where ref_event_id is not null;

-- ── 2. TWO KNOBS ───────────────────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('npc_upkeep_budget_seconds', to_jsonb(60),
   '0114: wall-clock seconds the hourly merchant upkeep (npc_tend, then npc_plan) may spend inside '
   'tick_reconcile before it defers the rest to the next hour. Half the server''s 2-min '
   'statement_timeout, so the compactor and the invariants still finish inside one statement.'),
  ('npc_buyers_per_good', to_jsonb(3),
   '0114: how many merchant routes may plan a BUY of one good at one harbour (laid-up and failed '
   'routes hold no place). 0097 allowed one, which left 60 % of 0105''s roster with no cargo.')
on conflict (key) do nothing;

-- ── 3. THE ONE READING OF THE BUDGET ───────────────────────────────────────────────────────────
create or replace function public.npc_upkeep_spent()
returns boolean
language sql
volatile
set search_path = public, pg_temp
as $$
  -- 0114: true once the hourly upkeep's deadline has passed. The deadline is transaction-local
  -- and set by tick_reconcile ALONE; unset or empty means no budget, so a switch, a proof or a
  -- one-route tend is never cut short.
  select coalesce(nullif(current_setting('byeharu.npc_upkeep_deadline', true), '')::timestamptz
                  < clock_timestamp(), false)
$$;
revoke all on function public.npc_upkeep_spent() from public, anon, authenticated;

-- ── 4. THE PLANNER AND THE UPKEEP, SUPERSEDED (0097:372, 0097:574) ─────────────────────────────
create or replace function public.npc_plan(p_now timestamptz default now(), p_route uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- Writes each merchant route's LINES from the market, through cmd.standing_route_save_for with the
-- SAME stops and courses. For every stop i bound for stop j:
--   1. RANK with THE ranking (world.trade_routes, port_i to port_j, twelve rows) — priced end to end
--      through world.quote. Server-only since 0071:176; this is its only live caller.
--   2. FILTER its rows: the house's authored wares first (all rows only when no listed good
--      passes), and AT MOST npc_buyers_per_good MERCHANT BUYERS PER (port, good) — counted over
--      every OTHER merchant route's BUY lines at that port, a route laid up or in error excepted
--      (its lines are dead). One rule for the hourly pass and for a route re-planned alone (0114;
--      0097 kept ONE buyer, by a temp table in the pass and by this count alone).
--   3. SIZE each kept good with the quote authority's own answer: how many units the SINK takes
--      above the probe's cost × (1 + npc_sell_margin) — a sell-side world.quote at port_j for cap units WITH a limit,
--      the p_limit walk (0005:442-448) — cap = the cap authority at both ends and the hold left.
--      KEEP it only if the two quotes at that size pay more than the leg's wages (crew_wages × the
--      leg's sea-days) and return ≥ npc_min_return_pct on the outlay. The first npc_lines_per_stop.
--   4. WRITE: SELL everything above cost; SELL <good> ALL for a good refused E_PRICE_LIMIT on a
--      SELL here in BOTH of the last two closed laps (the cut-loss); BUY <good> <q> AT <ceiling>.
-- A route with no paying good on ANY leg is laid up (the upkeep tries again after
-- npc_laid_up_hours). The pass takes the route planned LONGEST AGO first (updated_at, which the
-- save door and every pause re-date — 0114), so no house is structurally last and a pass the
-- upkeep budget cuts short (public.npc_upkeep_spent) resumes next hour where it stopped; a route
-- not reached is counted `deferred`, never half-planned. Routes paused 'error' or 'laid_up' are SKIPPED by the hourly pass (the save
-- door bumps updated_at, which dates the pause); npc_tend re-plans one alone before it resumes it.
-- Locks fleet then route, NOWAIT: a busy route is skipped this hour, never waited for.
declare
  v_k       int     := public.wc_int('npc_lines_per_stop');
  v_margin  numeric := public.wc_num('npc_sell_margin');
  v_minret  numeric := public.wc_num('npc_min_return_pct');
  v_pace    int     := public.wc_int('npc_laps_per_game_day');
  v_kmax    int     := public.wc_int('npc_buyers_per_good');   -- 0114
  r         record;
  st        record;
  e         jsonb;
  sr        public.standing_routes%rowtype;
  h         public.npc_houses%rowtype;
  v_n       int;
  v_stops   jsonb;
  v_lines   jsonb;
  v_rows    jsonb;
  v_hold    numeric;
  v_left    numeric;
  v_crew    int;
  v_speed   numeric;
  v_wages   numeric;
  v_good    uuid;
  v_bulk    numeric;
  v_cap     numeric;
  v_q       numeric;
  v_ceiling numeric;
  q_size    record;
  q_sell    record;
  q_buy     record;
  v_kept    int;
  v_any     boolean;
  v_pass    int;
  v_cut     text;
  v_res     jsonb;
  v_planned int := 0;
  v_laid    int := 0;
  v_busy    int := 0;
  v_failed  int := 0;
  v_deferred int := 0;                                          -- 0114
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
    -- 0114: THE BUDGET. Past the upkeep's deadline a route is not begun: it is counted and waits
    -- for the next pass, where its older updated_at puts it first.
    if public.npc_upkeep_spent() then
      v_deferred := v_deferred + 1;
      continue;
    end if;
    begin
      -- FLEET BEFORE ROUTE, and never wait (§4.5).
      perform 1 from public.fleets where id = r.fleet_id for update nowait;
      select * into sr from public.standing_routes where id = r.route_id for update nowait;
      select * into h from public.npc_houses where player_id = sr.player_id;
      select count(*) into v_n from public.standing_route_stops where route_id = sr.id;
      select coalesce(sum(c.crew_required), 0), coalesce(sum(public.ship_cargo_tuns(s.id)), 0)
        into v_crew, v_hold
        from public.ships s join public.ship_classes c on c.id = s.class_id
       where s.fleet_id = r.fleet_id;
      v_hold  := v_hold + public.fleet_free_hold(r.fleet_id);
      v_speed := greatest(coalesce(voyage.fleet_speed(r.fleet_id), 0), 0.1);
      v_stops := '[]'::jsonb;
      v_any   := false;

      for st in select s.ord, s.port_id, p.code, s.course,
                       (select s2.port_id from public.standing_route_stops s2
                         where s2.route_id = s.route_id and s2.ord = (s.ord + 1) % v_n) as next_port
                  from public.standing_route_stops s join public.ports p on p.id = s.port_id
                 where s.route_id = sr.id order by s.ord loop
        v_lines := jsonb_build_array(jsonb_build_object('kind', 'SELL', 'at_profit', true));

        -- THE CUT-LOSS: refused E_PRICE_LIMIT on a SELL here in BOTH of the last two closed laps.
        for v_cut in
          select z.g from (
            select split_part(x.e->>'line', ' ', 2) as g, count(distinct x.lap_no) as laps
              from (select l.lap_no, jsonb_array_elements(l.skipped) as e
                      from (select lp.lap_no, lp.skipped from public.standing_route_laps lp
                             where lp.route_id = sr.id and lp.closed_at is not null
                             order by lp.lap_no desc limit 2) l) x
             where x.e->>'port' = st.code and x.e->>'verb' = 'SELL' and x.e->>'code' = 'E_PRICE_LIMIT'
             group by 1) z
           where z.laps = 2 and exists (select 1 from public.goods g where g.code = z.g)
           order by z.g limit 2 loop
          v_lines := v_lines || jsonb_build_object('kind', 'SELL', 'good', v_cut);
        end loop;

        -- RANK, FILTER, SIZE, KEEP.
        v_rows  := coalesce(world.trade_routes(st.port_id, null, null, 12, st.next_port)->'routes', '[]'::jsonb);
        v_left  := v_hold;
        v_kept  := 0;
        v_wages := public.crew_wages(v_crew, false)
                   * coalesce((v_rows->0->>'nm')::numeric, 0) / (v_speed * 24);
        for v_pass in 1 .. 2 loop
          exit when v_pass = 2 and v_kept > 0;
          for e in select x from jsonb_array_elements(v_rows) x loop
            exit when v_kept >= v_k;
            v_good := (e->>'good_id')::uuid;
            continue when v_pass = 1 and not ((e->>'code') = any(h.wares));
            continue when v_lines @> jsonb_build_array(jsonb_build_object('kind', 'BUY', 'good', e->>'code'));
            -- 0114: AT MOST npc_buyers_per_good MERCHANT BUYERS here for this good, one count for
            -- both modes. A laid-up or failed route's lines are dead and hold no place.
            continue when (
              select count(distinct l.route_id) from public.standing_route_lines l
                join public.standing_route_stops s3 on s3.route_id = l.route_id and s3.ord = l.stop_ord
                join public.standing_routes sr3 on sr3.id = l.route_id
                                               and coalesce(sr3.paused_reason, '') not in ('laid_up', 'error')
                join public.players p3 on p3.id = sr3.player_id and p3.is_npc
               where l.route_id <> sr.id and l.kind = 'BUY' and l.good_id = v_good and s3.port_id = st.port_id
            ) >= v_kmax;
            select g.bulk into v_bulk from public.goods g where g.id = v_good;
            v_cap := floor(least(world.daily_cap_remaining(sr.player_id, st.port_id, v_good),
                                 world.daily_cap_remaining(sr.player_id, st.next_port, v_good),
                                 v_left / greatest(v_bulk, 0.001)));
            continue when v_cap is null or v_cap < 1;
            -- THE SIZE is the sink's own answer: units it takes above the probe's cost plus the margin.
            select * into q_size from world.quote(st.next_port, v_good, v_cap, 'sell',
                                                  round((e->>'buy_price')::numeric * (1 + v_margin), 2), null);
            v_q := floor(coalesce(q_size.units, 0));
            continue when v_q < 1;
            select * into q_buy from world.quote(st.port_id, v_good, v_q, 'buy', null, null);
            continue when q_buy.units is null or q_buy.units < v_q or q_buy.total <= 0;
            select * into q_sell from world.quote(st.next_port, v_good, v_q, 'sell', null, null);
            continue when q_sell.total - q_buy.total - v_wages <= 0
                       or (q_sell.total - q_buy.total) * 100 < v_minret * q_buy.total;
            v_ceiling := public.npc_buy_ceiling(st.port_id, v_good, h.patience);
            continue when v_ceiling is null;
            v_lines := v_lines || jsonb_build_object('kind', 'BUY', 'good', e->>'code', 'qty', v_q,
                                                     'price_limit', v_ceiling);
            v_left := v_left - v_q * v_bulk;
            v_kept := v_kept + 1;
            v_any  := true;
          end loop;
        end loop;

        v_stops := v_stops || jsonb_build_object('port', st.code, 'course', st.course,
                                                 'repair', st.ord = 0, 'crew_up', true, 'lines', v_lines);
      end loop;

      if not v_any then
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
    exception
      when lock_not_available then
        v_busy := v_busy + 1;
      when others then
        v_failed := v_failed + 1;
        v_notes := v_notes || jsonb_build_object('route', r.route_id, 'error', sqlerrm);
    end;
  end loop;

  return jsonb_build_object('enabled', true, 'planned', v_planned, 'laid_up', v_laid,
                            'busy', v_busy, 'failed', v_failed, 'deferred', v_deferred, 'notes', v_notes);
end $$;


create or replace function public.npc_tend(p_now timestamptz default now(), p_route uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- What the world does for a merchant that a player would do by hand — through the route cores,
-- cmd.clear_for + cmd.advance, and public.credit; nothing else. Per route, fleet then route locked
-- NOWAIT inside its own subtransaction (a busy route is skipped, counted, never waited for):
--   switch OFF, or beyond npc_fleet_max in roster order -> paused 'dark' (fleets at sea finish
--     their leg and lie in port).
--   ADRIFT / UNABLE_TO_SAIL -> laid up (there is no RECALL or salvage verb for anybody).
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
declare
  v_on      boolean := public.npc_traders_on();
  v_max     int     := public.wc_int('npc_fleet_max');
  v_laid    interval := make_interval(hours => public.wc_int('npc_laid_up_hours'));
  r         record;
  hh        record;
  sr        public.standing_routes%rowtype;
  f         public.fleets%rowtype;
  fo        public.orders%rowtype;
  v_res     jsonb;
  v_clears  int;
  v_last    timestamptz;
  v_week    int;
  v_alt     jsonb;
  v_stops   jsonb;
  v_n       int;
  v_dark    int := 0;
  v_started int := 0;
  v_resumed int := 0;
  v_cleared int := 0;
  v_laid_n  int := 0;
  v_refound int := 0;
  v_busy    int := 0;
  v_failed  int := 0;
  v_deferred int := 0;                                          -- 0114
  v_notes   jsonb := '[]'::jsonb;
begin
  -- 0114: k is still the ROSTER rank (npc_fleet_max is a roster ceiling), but the walk takes the
  -- route written longest ago first, so a pass the budget cuts short starts next hour where it
  -- stopped instead of tending the same head of the roster every hour.
  for r in select nf.fleet_id, nf.route_id, nf.player_id, nf.alt_loop,
                  row_number() over (order by nf.roster_ord) as k
             from public.npc_fleets nf
             join public.players p on p.id = nf.player_id and p.is_npc
             join public.standing_routes sr0 on sr0.id = nf.route_id
            where nf.route_id is not null
            order by sr0.updated_at, nf.roster_ord loop
    continue when p_route is not null and r.route_id <> p_route;
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

      if f.status in ('ADRIFT', 'UNABLE_TO_SAIL') then
        if sr.paused_reason is distinct from 'laid_up' then
          perform cmd.standing_route_pause_for(sr.player_id, sr.id, true, 'laid_up',
            format('%s cannot sail on.', f.name));
          v_laid_n := v_laid_n + 1;
        end if;
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
         and not (sr.paused_reason in ('dark', 'losing', 'reserve', 'edited')
                  or (sr.paused_reason = 'laid_up' and sr.updated_at < p_now - v_laid)
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
        if v_clears >= 3 then
          perform cmd.standing_route_pause_for(sr.player_id, sr.id, true, 'laid_up',
            format('%s stopped three times running (%s).', f.name, fo.error_code));
          v_laid_n := v_laid_n + 1;
        else
          perform cmd.clear_for(sr.player_id, r.fleet_id, false);
          perform cmd.advance(r.fleet_id, p_now);
          v_cleared := v_cleared + 1;
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

  -- REFOUNDS, per company, only while the switch is on.
  if v_on and p_route is null then
    for hh in select h.player_id, h.capital, pl.ducats, pl.company_name
                from public.npc_houses h join public.players pl on pl.id = h.player_id and pl.is_npc
               where pl.ducats < h.capital * public.wc_num('npc_purse_floor_pct')
               order by h.roster_ord loop
      begin
        select max(ev.created_at), count(*) filter (where ev.created_at > p_now - interval '7 days')
          into v_last, v_week
          from public.events ev where ev.player_id = hh.player_id and ev.kind = 'NPC_REFOUNDED';
        continue when v_last is not null
          and v_last > p_now - make_interval(secs => (public.wc_num('npc_refound_cooldown_game_days')
                                                       * public.wc_num('game_day_seconds'))::double precision);
        if coalesce(v_week, 0) >= public.wc_int('npc_refound_max_per_week') then
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
      exception when others then
        v_failed := v_failed + 1;
        v_notes := v_notes || jsonb_build_object('company', hh.company_name, 'error', sqlerrm);
      end;
    end loop;
  end if;

  return jsonb_build_object('enabled', v_on, 'dark', v_dark, 'started', v_started, 'resumed', v_resumed,
                            'cleared', v_cleared, 'laid_up', v_laid_n, 'refounded', v_refound,
                            'busy', v_busy, 'failed', v_failed, 'deferred', v_deferred, 'notes', v_notes);
end $$;


-- ── 5. tick_reconcile SETS THE BUDGET — a slice of its LIVE body, LF-normalised ────────────────
do $$
declare
  v_def  text;
  v_set  text := $h$  perform set_config('lock_timeout', '2s', true);
$h$;
  v_clr  text := $h$    v_upkeep := v_upkeep || jsonb_build_object('compact_error', sqlerrm);
  end;
$h$;
begin
  v_def := replace(pg_get_functiondef('public.tick_reconcile()'::regprocedure), E'\r', '');
  if (length(v_def) - length(replace(v_def, v_set, ''))) / length(v_set) <> 1
     or (length(v_def) - length(replace(v_def, v_clr, ''))) / length(v_clr) <> 1 then
    raise exception '0114 self-assert FAIL: tick_reconcile''s live body does not carry 0097''s upkeep hunk exactly once';
  end if;
  v_def := replace(v_def, v_set, v_set || $h$  -- 0114: THE UPKEEP'S BUDGET, set here and nowhere else. npc_tend and npc_plan read it through
  -- public.npc_upkeep_spent() and defer what is left; it is cleared after the compactor, so the
  -- invariants below are never judged against a deadline.
  perform set_config('byeharu.npc_upkeep_deadline',
    (clock_timestamp() + make_interval(secs => public.wc_num('npc_upkeep_budget_seconds')))::text, true);
$h$);
  v_def := replace(v_def, v_clr, v_clr || $h$  perform set_config('byeharu.npc_upkeep_deadline', '', true);   -- 0114
$h$);
  execute v_def;
end $$;

-- ── 6. SELF-ASSERT, AND THE IDLE MERCHANTS PUT BACK TO SEA ─────────────────────────────────────
do $$
declare
  -- AS FOUND, NOT AS SHIPPED (0113, 2026-10-14): production runs lit, a fresh chain runs dark.
  v_was_on  boolean := public.npc_traders_on();
  v_route   uuid;
  v_fleet   uuid;
  v_res     jsonb;
  v_n       int;
  v_def     text;
  v_before  timestamptz;
  v_laid    interval := make_interval(hours => public.wc_int('npc_laid_up_hours'));
  v_resume  jsonb;
  v_groups  jsonb;
begin
  -- (a) THE INDEX, on the column the FK and the compactor read.
  if not exists (select 1 from pg_index i
                  where i.indexrelid = to_regclass('public.ledger_ref_event_id')
                    and i.indrelid = 'public.ledger'::regclass
                    and i.indkey[0] = (select attnum from pg_attribute
                                        where attrelid = 'public.ledger'::regclass and attname = 'ref_event_id')) then
    raise exception '0114 self-assert FAIL: ledger.ref_event_id is not indexed';
  end if;

  -- (b) THE KNOBS hold the values this file argues for (a pre-existing key would be kept as found
  --     by `on conflict do nothing`, so a different value is a FAIL, not a silent drift).
  if public.wc_int('npc_upkeep_budget_seconds') <> 60 or public.wc_int('npc_buyers_per_good') <> 3 then
    raise exception '0114 self-assert FAIL: the knobs read % s and % buyers',
      public.wc_int('npc_upkeep_budget_seconds'), public.wc_int('npc_buyers_per_good');
  end if;

  -- (c) THE ONE SETTER. tick_reconcile sets the deadline and clears it; no other function sets it.
  v_def := pg_get_functiondef('public.tick_reconcile()'::regprocedure);
  if position($q$set_config('byeharu.npc_upkeep_deadline',
    (clock_timestamp() + make_interval(secs => public.wc_num('npc_upkeep_budget_seconds')))::text, true)$q$ in v_def) = 0
     or position($q$set_config('byeharu.npc_upkeep_deadline', '', true)$q$ in v_def) = 0
     or position('npc_tend(now())' in v_def) < position('npc_upkeep_deadline' in v_def) then
    raise exception '0114 self-assert FAIL: tick_reconcile does not set the budget before the upkeep and clear it after';
  end if;
  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname not like 'pg_temp%' and p.prosrc like '%set_config(''byeharu.npc_upkeep_deadline''%';
  if v_n <> 1 then
    raise exception '0114 self-assert FAIL: % functions set the upkeep deadline, not one', v_n;
  end if;
  -- and the planner keeps no second buyer rule.
  v_def := pg_get_functiondef('public.npc_plan(timestamptz, uuid)'::regprocedure);
  if position('npc_plan_buyers' in v_def) > 0 or position($q$wc_int('npc_buyers_per_good')$q$ in v_def) = 0
     or position('npc_upkeep_spent()' in v_def) = 0
     or position('npc_upkeep_spent()' in pg_get_functiondef('public.npc_tend(timestamptz, uuid)'::regprocedure)) = 0 then
    raise exception '0114 self-assert FAIL: the planner or the upkeep does not read the budget and the one buyer cap';
  end if;

  -- (d) BEHAVIOUR, inside a rolled-back block. A subject the upkeep WILL reach: the first merchant
  --     route by roster whose fleet can sail (an ADRIFT fleet is laid up before the gate).
  select nf.route_id, nf.fleet_id into v_route, v_fleet
    from public.npc_fleets nf
    join public.players p on p.id = nf.player_id and p.is_npc
    join public.fleets f on f.id = nf.fleet_id
   where nf.route_id is not null and f.status not in ('ADRIFT', 'UNABLE_TO_SAIL')
   order by nf.roster_ord, nf.fleet_id
   limit 1;
  if v_route is null then
    raise exception '0114 self-assert FAIL: no merchant route to probe — nothing below would mean anything';
  end if;

  begin
    update public.world_config set value = 'true'::jsonb where key = 'npc_traders_enabled';

    -- the reading: unset → false; past → true; future → false.
    perform set_config('byeharu.npc_upkeep_deadline', '', true);
    if public.npc_upkeep_spent() then
      raise exception '0114 self-assert FAIL: no deadline set, yet the budget reads spent';
    end if;
    perform set_config('byeharu.npc_upkeep_deadline', (clock_timestamp() + interval '1 hour')::text, true);
    if public.npc_upkeep_spent() then
      raise exception '0114 self-assert FAIL: a deadline an hour off reads spent';
    end if;
    perform set_config('byeharu.npc_upkeep_deadline', (clock_timestamp() - interval '1 second')::text, true);
    if not public.npc_upkeep_spent() then
      raise exception '0114 self-assert FAIL: a deadline a second past reads unspent';
    end if;

    -- SPENT, THE PASS BEGINS NOTHING: every eligible route deferred, none planned or laid up.
    select count(*) into v_n from public.npc_fleets nf
      join public.players p on p.id = nf.player_id and p.is_npc
      join public.standing_routes sr on sr.id = nf.route_id
     where coalesce(sr.paused_reason, '') not in ('error', 'laid_up');
    v_res := public.npc_plan(now());
    if v_n = 0 or (v_res->>'deferred')::int <> v_n or (v_res->>'planned')::int <> 0
       or (v_res->>'laid_up')::int <> 0 then
      raise exception '0114 self-assert FAIL: spent, the pass over % routes answered %', v_n, v_res - 'notes';
    end if;

    -- SPENT, THE UPKEEP LIFTS NOTHING: a paused route is deferred and left exactly as it lay.
    perform cmd.standing_route_set_paused(v_route, 'losing', null, 'A probe loss (0114).');
    select updated_at into v_before from public.standing_routes where id = v_route;
    v_res := public.npc_tend(now(), v_route);
    if (v_res->>'deferred')::int <> 1 or (v_res->>'resumed')::int <> 0 or (v_res->>'started')::int <> 0
       or (select paused_reason from public.standing_routes where id = v_route) is distinct from 'losing'
       or (select updated_at from public.standing_routes where id = v_route) is distinct from v_before then
      raise exception '0114 self-assert FAIL: spent, the upkeep touched the paused probe: %', v_res - 'notes';
    end if;

    -- UNSET, THE SAME CALL IS NOT DEFERRED (the positive control for the gate above).
    perform set_config('byeharu.npc_upkeep_deadline', '', true);
    update public.world_config set value = to_jsonb(0) where key = 'npc_buyers_per_good';
    v_res := public.npc_plan(now(), v_route);
    -- THE BUYER CAP, deterministically: at a cap of 0 every candidate good is refused, whatever
    -- the market, so the route is laid up for want of cargo — planned 0, laid up 1, nothing deferred.
    if (v_res->>'deferred')::int <> 0 or (v_res->>'planned')::int <> 0 or (v_res->>'laid_up')::int <> 1
       or (select paused_reason from public.standing_routes where id = v_route) is distinct from 'laid_up' then
      raise exception '0114 self-assert FAIL: at a buyer cap of 0 the plan answered %', v_res;
    end if;

    raise exception 'ROLLBACK_0114';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0114' then raise; end if;
  end;

  -- EVERYTHING ABOVE WAS UNDONE.
  if public.npc_traders_on() is distinct from v_was_on or public.wc_int('npc_buyers_per_good') <> 3
     or public.npc_upkeep_spent() then
    raise exception '0114 self-assert FAIL: the probe world was not rolled back';
  end if;

  -- (e) LIT AS FOUND: THE ONE SWITCH PUTS THE IDLE MERCHANTS BACK TO SEA — its own plan-then-tend,
  --     unbudgeted (the deadline is unset here). Dark as found: nothing is touched.
  if v_was_on then
    v_resume := public.npc_traders_switch(true);
    if not public.npc_traders_on()
       or coalesce((v_resume->'plan'->>'failed')::int, 0) <> 0
       or coalesce((v_resume->'tend'->>'failed')::int, 0) <> 0 then
      raise exception '0114 self-assert FAIL: the switch''s pass failed: plan % tend %',
        v_resume->'plan', v_resume->'tend';
    end if;
    -- No merchant is left on a pause the upkeep lifts at once, or on a lay-up older than its
    -- rest — a fleet that cannot sail excepted (it is laid up before the gate, by design).
    select count(*) into v_n
      from public.npc_fleets nf
      join public.players p on p.id = nf.player_id and p.is_npc
      join public.standing_routes sr on sr.id = nf.route_id
      join public.fleets f on f.id = nf.fleet_id
     where f.status not in ('ADRIFT', 'UNABLE_TO_SAIL')
       and (sr.paused_reason in ('losing', 'dark', 'reserve', 'edited')
            or (sr.paused_reason = 'laid_up' and sr.updated_at < now() - v_laid));
    if v_n <> 0 then
      raise exception '0114 self-assert FAIL: % merchant route(s) still idle after the switch''s pass: %',
        v_n, v_resume->'tend'->'notes';
    end if;
  end if;

  select jsonb_object_agg(k, c) into v_groups from (
    select coalesce(sr.paused_reason, case when sr.fleet_id is null then 'unstarted' else 'sailing' end) as k,
           count(*) as c
      from public.npc_fleets nf
      join public.players p on p.id = nf.player_id and p.is_npc
      join public.standing_routes sr on sr.id = nf.route_id
     group by 1) g;

  if public.npc_traders_on() is distinct from v_was_on then
    raise exception '0114 self-assert FAIL: the switch was not left as found';
  end if;

  raise notice '0114 self-assert ok: THE MERCHANTS ARE TENDED INSIDE THE HOUR. ledger.ref_event_id '
    'indexed; budget 60 s, buyer cap 3; tick_reconcile is the one setter of the deadline, set before '
    'the upkeep and cleared after the compactor; spent, the pass deferred every route and planned '
    'none, and the upkeep left a paused probe untouched; unset, the cap at 0 laid the probe up. '
    'Rolled back. Switch as found (%); the switch''s pass: %; merchants now: %.',
    case when v_was_on then 'lit' else 'dark' end,
    jsonb_build_object('plan', (v_resume->'plan') - 'notes', 'tend', (v_resume->'tend') - 'notes'),
    v_groups;
end $$;
