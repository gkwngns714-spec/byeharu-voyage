-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none (no coin moves and nothing a player sees changes: two reads for the HQ worker list, which the client hooks up after)
-- 0496 - THE WORKERS AND THEIR ACTIONS  (read only: no switch, no coin, no table, no cron; the read half of the design's `rate-ledger`)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-24: "it is like madevor's rs3 jagex game idle game, but instead of doing with only 1 player, i do it with multiple".
--   docs/design/hq-corp-2026-11-24.md A2.1 (the action: one shape), A2.2 (the server owns time), A2.5 (offline), B3 (assignment) and the
--   slice `0495 rate-ledger`, MINUS world.company_rate, which 0493 built. Dev log docs/dev-log/2026-11-24-workers-read.md.
--
-- WHAT (all STABLE or IMMUTABLE; nothing is written):
--   world.workers()            CLIENT READ. One row for each of her fleets and her land party: her action in the one shape, her state,
--                              the served stamps of her progress, and coin / experience / items an hour (public.workers_for).
--   world.actions(worker)      CLIENT READ. The options of one worker (`id` of a workers() row: fleet:<uuid> | party:<n>) in the same
--                              shape, ONLY what the server would take (public.sea_actions_for, public.land_actions_for).
--   public.action_shape        THE ONE SHAPE (A2.1) and the one place per_hour, xp_per_hour and items_per_hour of ONE completion are worked out. IMMUTABLE.
--   public.run_day             A REPEATING RUN OVER ONE GAME DAY, by the server's own rules: the day's allowance at both ends
--                              (world.daily_cap_remaining), the stock on the buying quay, the game day's length, and every run after the
--                              first priced into the press of the runs before it (world.quote over the day's units: the quay's own walk).
--   public.action_over_day     the one place a repeating run's per_hour, xp_per_hour and items_per_hour are worked out: its day's coin,
--                              experience and units over its day's seconds. IMMUTABLE.
--   public.fleet_job_tick_s    the fleet-jobs job's period (0481: every 2 minutes), in seconds. IMMUTABLE.
--   public.job_trip            a job's legs (public.fleet_job_sails, 0494: THE authority) priced by world.trip_cost (0360).
--   public.away_parties_for    the away report's land rows; public.away_report_for serves them as `parties` (ONE hunk; every key kept).
--   public.client_rpc_entry_points gains the two reads (ONE hunk).
-- THE SHAPE: {id, kind, skill, level, interval_s, inputs {coin, items}, outputs {coin, items}, xp [{skill, xp}], cost, net, per_hour,
--   xp_per_hour, items_per_hour, basis} and beside it what its door takes: a sea action's `job` {kind, params} for cmd.set_fleet_job,
--   a land action's `action` for cmd.land_send.
-- NO SECOND ESTIMATOR. Every figure is an existing quote's:
--   sea     world.best_sales (the cards: good, harbour, units, cost, profit, seconds), world.quote (the sale, whole), world.trip_cost
--           (the sail back; the trip home and back of a bring-home), public.fleet_buy_capacity and public.fleet_job_ends (0492: the
--           units a bring-home BUY takes, the home shed's room). A SEA RUN'S INTERVAL IS THE WHOLE CYCLE: the card's seconds out, the
--           dock turn there (world.trip_stop_seconds), the sail back and the turn at home. The Best run alone is one way (it does not
--           come back: its next run starts where it sold), and says so (`returns` false).
--           THE WAIT FOR THE JOB TICK IS IN THE INTERVAL. A job's fleet lying idle in port is started by public.tick_fleet_jobs, which
--           runs every public.fleet_job_tick_s() seconds: half of that on average each time she waits. A run there and back waits
--           twice (at the sale's harbour, then at home), the Best run once.
-- A REPEATING RUN'S PER HOUR IS ITS DAY'S, NOT ITS FIRST RUN'S (measured 2026-11-25, scripts/ops/harness/hq-figures/measure-repeat.mjs:
--   the first run's net over its interval read +537,909 an hour for quicksilver Lisbon - Setubal; played through the real tick the
--   second run already lost coin, and the day's allowance at Setubal stopped her in the fourth). A fixed run there and back, and a
--   bring-home, carry `day` {runs, coin, seconds, stop} (public.run_day) and their per_hour, xp_per_hour and items_per_hour are that
--   day's (public.action_over_day). `net`, `interval_s`, `inputs` and `outputs` stay ONE run's (the first: what Once would do).
--   NOT COUNTED, SAID: the days after (stock returns toward its mark at the harbour's restock rate a game day, so a quay she empties
--   every day pays less the next); the part run after the last whole one; what other traders do to the same quays.
--   land    public.land_terms, the terms Send freezes.
--   WHAT THE QUOTES DO NOT SERVE, SAID: a card carries no split of its tax, wages, stores and dock fee on the way out (only
--   world.good_board's full row does, a second's work a good), so `cost.total` is the sale less the buy less the net, and the sail
--   back's parts are served as `cost.back`. A new harbour's 25 Exploration is not counted. No coin moves ashore yet (wages: 0498).
-- ONLY WHAT THE SERVER WOULD TAKE. A run whose way out or back public.fleet_job_sails shuts (range, stores, no course: 0494) is not
--   offered. A door shut for every option (dark, a standing route, the party out, a haul waiting) answers `closed {code, sentence}` and
--   no option. A land job whose terms name a refusal (level, materials, no land in reach) is not offered. A bring-home the door's own
--   judge refuses (public.fleet_job_end: dark, no home, no warehouse, bought at home) or the shed stops is not offered. The probe sets
--   every option it is served through the real doors.
-- A RUNNING WORKER'S FIGURES, AND THEIR BASIS (the field `basis` on every action):
--   runs    her own completed runs: her fleet's ledger rows since the job was set (24 hours at most), from her first BUY to her
--           last, when at least 3 BUYs lie there (two whole runs or more)
--   quote   an option (world.actions); in world.workers, a Best run under way (the card its plan took, kept on the job). THE BEST RUN
--           CARRIES NO per_hour (null), as an option and under way: each run is another sale from another harbour, so its rate is her
--           own runs' (basis runs) or nothing
--   terms   a land job: the terms frozen at Send
--   none    not priced yet (a fixed job before two whole runs): null figures. world.workers asks no quote; world.actions serves the
--           same id with its quote while she lies at the job's buy harbour.
-- NOT CHANGED: any command, any coin, any knob or switch, any table, the ledger, world.hq_board, any existing key of world.away_report.
-- ROWS: none. No table, no index, no cron, no beat step. 0 new rows a minute.
-- budget: no table, no cron job, no autovacuum or fillfactor change; reads only. world.workers: her fleets, her jobs and ONE range of
--   her last 24 hours of ledger (the (player_id, created_at) index company_rate_for reads); world.actions: one world.best_sales and at
--   most 8 trips back for a fleet, public.land_terms a job for a party. NOTHING IS CUT BY THE CLOCK (2026-11-25: on CI the 1.2 s cut
--   left Bring home out at Porto, so a player's choices would come and go with the server's speed): the Best run, every Bring home
--   and every land job are always served; the single runs are the first 8 paying cards by count; past 5 s the read answers closed
--   E_SLOW and nothing else.
-- COST (local PGlite, this file's probe; the notice prints them): world.workers a few ms (budget 100); world.actions about 1 s for a
--   fleet (budget 1.5 s; world.best_sales is about half of it), under 0.1 s for a party.
-- HOW OFTEN A CLIENT MAY ASK (served as ask_s): world.workers no more than once in 60 s a client, and once after a command of hers or
--   when a served stamp passes; world.actions only when the Assign sheet opens, no more than once in 300 s a worker, NEVER on a timer.
--   Prod is the smallest size: neither read belongs on a beat or a poll.
-- LOCKS: CREATE FUNCTION x11; CREATE OR REPLACE x2 by hunks. TIME: a few seconds. BUDGET: statement_timeout 60 s, lock_timeout 5 s;
--   fails above 45 s.
-- ROLLBACK (forward): a migration reversing the two hunks (OLD texts below verbatim) and dropping the eleven functions; the client
--   reads `parties` as optional and the worker list falls back to world.away_report.
-- SELF-ASSERT: each hunk once and reversing; no other function moved; the hunked bodies' grants, volatility, definer, search path and
--   owner unmoved; no world_config row moved; the nine cores server only (public, anon, authenticated, service_role), the two reads for
--   authenticated alone and in the registry; the shape IMMUTABLE, the rest STABLE. THE PROBE (rolled back by a raised sentinel; it reads
--   and counts only its own company's rows, starts no voyage and buys nothing): dark, the lists and the closed doors; lit, a fleet's
--   options at home and in a second harbour, each figure against the quote it came from, EVERY option set through cmd.set_fleet_job
--   (none refused); bring home offered only away from home and only lit; a party's jobs against public.land_terms, one sent through
--   cmd.land_send, then the door closed (E_LAND_OUT); her own runs (planted ledger rows) read as basis `runs`; the away report's old
--   keys kept and its `parties` row. Proof 199 plays a run through the tick and the reach.
-- VERSION: 0496 (0493 `rate-why` and 0494 `job-by-harbours` land first; 0495 is `dividend-hourly`'s and touches none of these bodies).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array['public.away_report_for(uuid)', 'public.client_rpc_entry_points()'];
  c_cores  constant text[] := array['public.action_shape(text,text,text,integer,numeric,jsonb,jsonb,jsonb,jsonb,numeric,text,jsonb)',
                                    'public.job_trip(uuid,uuid,text[],boolean)', 'public.sea_actions_for(uuid,uuid)',
                                    'public.land_actions_for(uuid,integer)', 'public.workers_for(uuid)', 'public.away_parties_for(uuid)',
                                    'public.run_day(uuid,uuid,uuid,uuid,uuid,numeric,numeric,numeric,numeric,numeric)',
                                    'public.action_over_day(jsonb,jsonb,numeric,numeric)', 'public.fleet_job_tick_s()'];
  c_doors  constant text[] := array['world.workers()', 'world.actions(text)'];
  c_uid    constant uuid := '00000000-0496-4000-8000-000000000001';
  v_t0        timestamptz := clock_timestamp();
  v_t         timestamptz;
  v_h         record;
  x           record;
  v_q         text;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_fn_before text;
  v_meta      text;
  v_cfg_before text;
  v_lived     boolean := false;
  v_me        uuid;
  v_fl        uuid;
  v_lis       uuid;
  v_home      text;
  v_x         uuid;
  v_xc        text;
  v_w         jsonb;
  v_a         jsonb;
  v_r         jsonb;
  v_bs        jsonb;
  v_e         jsonb;
  v_c         jsonb;
  v_tb        jsonb;
  v_turn      numeric;
  v_ms_w      numeric;
  v_ms_a      numeric;
  v_ms_b      numeric;
  v_ms_p      numeric;
  v_set       int := 0;
  v_fixed     int := 0;
  v_store     int := 0;
  v_land      int := 0;
  v_note      text := '';
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('world.workers()') is not null or to_regprocedure('world.actions(text)') is not null
     or to_regprocedure('public.workers_for(uuid)') is not null or to_regprocedure('public.away_parties_for(uuid)') is not null then
    raise exception '0496 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.fleet_job_legs(uuid,uuid,uuid)') is null or to_regprocedure('public.fleet_job_ends(uuid,uuid,jsonb,text)') is null
     or to_regprocedure('public.company_rate_for(uuid)') is null or to_regprocedure('world.trip_cost(uuid,jsonb)') is null
     or to_regprocedure('world.best_sales(uuid,uuid)') is null or to_regprocedure('public.land_terms(uuid,text)') is null
     or to_regprocedure('public.away_report_for(uuid)') is null or to_regprocedure('cmd.assume_identity(uuid)') is null then
    raise exception '0496 refuses: 0494 (job by harbours), 0493 (the rate), 0492 (bring home), 0481 (fleet jobs) or 0455 (the land) is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
    into v_cfg_before from public.world_config c;

  -- ── 2. THE READS ──
  execute $f$
create function public.action_shape(p_id text, p_kind text, p_skill text, p_level integer, p_interval numeric, p_inputs jsonb, p_outputs jsonb,
                                    p_xp jsonb, p_cost jsonb, p_net numeric, p_basis text, p_more jsonb)
returns jsonb
language plpgsql
immutable
set search_path = public, pg_temp
as $body$
-- 0496: THE ONE SHAPE OF AN ACTION (docs/design/hq-corp-2026-11-24.md A2.1): every option world.actions serves and every running action
-- world.workers serves is built here, and the three derived figures are worked out here alone: per_hour = net x 3600 / interval_s,
-- xp_per_hour = the xp of a completion x 3600 / interval_s, items_per_hour = the units a completion puts out x 3600 / interval_s.
-- No interval (an action nothing has priced): the three are null. p_more's keys ride beside the shape (what the door takes, the good,
-- the harbours). Reads nothing.
begin
  return jsonb_build_object(
    'id', p_id, 'kind', p_kind, 'skill', p_skill, 'level', p_level,
    'interval_s', round(p_interval),
    'inputs', jsonb_build_object('coin', round(coalesce((p_inputs->>'coin')::numeric, 0)), 'items', coalesce(p_inputs->'items', '[]'::jsonb)),
    'outputs', jsonb_build_object('coin', round(coalesce((p_outputs->>'coin')::numeric, 0)), 'items', coalesce(p_outputs->'items', '[]'::jsonb)),
    'xp', coalesce(p_xp, '[]'::jsonb),
    'cost', coalesce(p_cost, '{}'::jsonb),
    'net', round(p_net),
    'per_hour', case when p_interval > 0 then round(p_net * 3600 / p_interval) end,
    'xp_per_hour', case when p_interval > 0 and p_xp is not null
                        then round((select coalesce(sum((e->>'xp')::numeric), 0) from jsonb_array_elements(p_xp) e) * 3600 / p_interval) end,
    'items_per_hour', case when p_interval > 0
                           then round((select coalesce(sum((e->>'units')::numeric), 0)
                                         from jsonb_array_elements(coalesce(p_outputs->'items', '[]'::jsonb)) e) * 3600 / p_interval, 2) end,
    'basis', p_basis) || coalesce(p_more, '{}'::jsonb);
end
$body$
  $f$;

  execute $f$
create function public.fleet_job_tick_s()
returns numeric
language sql
immutable
set search_path = public, pg_temp
as $body$
  -- 0496: THE FLEET-JOBS JOB'S PERIOD, in seconds (0481: pg_cron byeharu-voyage:fleet-jobs, '*/2 * * * *'). A job's fleet lying idle in
  -- port waits for its next run: half of this on average. A change of that schedule changes this line.
  select 120::numeric
$body$
  $f$;

  execute $f$
create function public.action_over_day(p_action jsonb, p_day jsonb, p_xp numeric, p_items numeric)
returns jsonb
language plpgsql
immutable
set search_path = public, pg_temp
as $body$
-- 0496: A REPEATING RUN'S FIGURES ARE ITS DAY'S. p_action is the run in the one shape (public.action_shape: its net, interval, inputs
-- and outputs are ONE run's); p_day is public.run_day's answer {runs, coin, seconds, stop}; p_xp and p_items the experience and the
-- units those runs bring. The three derived figures are worked out here alone for a repeating run: per_hour = the day's coin x 3600 /
-- the day's seconds, and the same for experience and units. The day rides beside them as `day`. Reads nothing.
declare
  v_s numeric := (p_day->>'seconds')::numeric;
begin
  if p_day is null or coalesce(v_s, 0) <= 0 then
    return p_action;
  end if;
  return p_action || jsonb_build_object(
    'per_hour', round((p_day->>'coin')::numeric * 3600 / v_s),
    'xp_per_hour', round(coalesce(p_xp, 0) * 3600 / v_s),
    'items_per_hour', round(coalesce(p_items, 0) * 3600 / v_s, 2),
    'day', jsonb_build_object('runs', (p_day->>'runs')::numeric, 'coin', round((p_day->>'coin')::numeric), 'seconds', round(v_s), 'stop', p_day->>'stop'));
end
$body$
  $f$;

  execute $f$
create function public.run_day(p_player uuid, p_fleet uuid, p_buy uuid, p_sell uuid, p_good uuid, p_units numeric, p_interval numeric,
                               p_cost numeric, p_gross numeric, p_net numeric)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0496: ONE RUN, REPEATED OVER ONE GAME DAY, BY THE SERVER'S OWN RULES. p_units of p_good bought at p_buy and sold at p_sell (null: a
-- bring-home, stored), a run lasting p_interval seconds; the first run buys for p_cost, sells for p_gross and leaves p_net after
-- every cost. {runs, coin, seconds, stop, traded}:
--   runs     the whole runs of p_units she makes in a game day: what the day's allowance takes at BOTH ends
--            (world.daily_cap_remaining, the authority the BUY and the SELL read), what the buying quay holds, and what the day's
--            length (game_day_seconds) has time for; never under one
--   stop     allowance (the day's allowance or the quay's stock stops her before the day is out) | time
--   seconds  the runs' time; stopped by the allowance, the whole day (it returns at the day's turn)
--   coin     what those runs leave. EVERY RUN AFTER THE FIRST IS PRICED INTO THE PRESS OF THE RUNS BEFORE IT: the quay walks its shelves
--            (world.quote), so the buys of n runs cost what ONE buy of n x p_units costs, and the sales bring what one sale of them
--            brings. THE MARK A SALE LEAVES (cmd.do_sell: port_goods.glut, by public.press_after's rule) is on every sale after the
--            first: while the quote does not walk the press itself (public.price_impact_lit dark), the day's sales are scaled by the
--            mean of (1 - the mark before each sale) over (1 - the mark now). Each run pays the first run's costs but the profit tax
--            (the dock fees, wages, stores and the sail back); the profit tax (public.profit_tax) is charged on the runs that still
--            gain, their margins falling evenly from the first.
--   traded   the coin bought and sold (what Trading counts)
-- A RUN SET TO REPEAT IS NOT STOPPED BY A LOSS (public.fleet_job_plan buys and sells ALL each time), so the losing runs are counted.
-- No estimate of its own: the allowance, the stock, the quote and the tax are the server's. Writes nothing.
declare
  v_day    numeric := greatest(coalesce(public.wc_num('game_day_seconds'), 0), 1);
  v_allow  numeric;
  v_ntime  numeric;
  v_nall   numeric;
  v_n      numeric;
  v_stop   text;
  v_buy    numeric;
  v_sale   numeric;
  v_got    numeric;
  v_m1     numeric := p_gross - p_cost;                 -- the first run's margin
  v_tax1   numeric;
  v_fixed  numeric;
  v_d      numeric;
  v_k      numeric;
  v_gain   numeric;
  v_coin   numeric;
  v_g0     numeric;
  v_tgt    numeric;
  v_w      numeric;
begin
  if coalesce(p_units, 0) <= 0 or coalesce(p_interval, 0) <= 0 then
    return null;
  end if;
  v_allow := least(world.daily_cap_remaining(p_player, p_buy, p_good),
                   (select pg.stock from public.port_goods pg where pg.port_id = p_buy and pg.good_id = p_good),
                   case when p_sell is not null then world.daily_cap_remaining(p_player, p_sell, p_good) end);
  v_ntime := greatest(1, floor(v_day / p_interval));
  v_nall := floor(coalesce(v_allow, 0) / p_units);
  v_n := greatest(1, least(v_ntime, v_nall));
  v_stop := case when v_nall < v_ntime then 'allowance' else 'time' end;
  if v_n > 1 then
    select q.units, q.total into v_got, v_buy from world.quote(p_buy, p_good, v_n * p_units, 'buy', null, p_fleet) q;
    if coalesce(v_got, 0) < v_n * p_units then   -- the quay ran out inside the walk: the whole runs it holds
      v_n := greatest(1, floor(coalesce(v_got, 0) / p_units));
      v_stop := 'allowance';
      if v_n > 1 then
        select q.total into v_buy from world.quote(p_buy, p_good, v_n * p_units, 'buy', null, p_fleet) q;
      end if;
    end if;
  end if;
  if v_n > 1 and p_sell is not null then
    select q.units, q.total into v_got, v_sale from world.quote(p_sell, p_good, v_n * p_units, 'sell', null, p_fleet) q;
    if v_sale is null or coalesce(v_got, 0) < v_n * p_units then
      v_n := 1;
    elsif not public.price_impact_lit() then
      -- the mark of the sales before each sale (the quote above read the mark as it stands for all of them)
      select pg.glut, pg.stock_target into v_g0, v_tgt from public.port_goods pg where pg.port_id = p_sell and pg.good_id = p_good;
      if v_g0 is not null and v_g0 < 1 then
        select avg(1 - public.press_after(v_g0, (i - 1) * p_units, v_tgt, 'sell', public.wc_num('glut_per_depth'), public.wc_num('glut_max')))
               / (1 - v_g0)
          into v_w from generate_series(1, v_n::int) i;
        v_sale := floor(v_sale * coalesce(v_w, 1));
      end if;
    end if;
  end if;
  if v_n <= 1 then
    v_coin := p_net;
    v_buy := p_cost;
    v_sale := p_gross;
  elsif p_sell is null then
    -- a bring-home: the buys, and the trip of each run (p_net is -(buy + trip))
    v_coin := -v_buy + v_n * (p_net + p_cost);
    v_sale := 0;
  else
    v_tax1 := coalesce(public.profit_tax(p_sell, v_m1, p_player), 0);
    v_fixed := greatest(v_m1 - p_net - v_tax1, 0);     -- a run's costs but the profit tax: dock fees, wages, stores, the sail back
    -- the runs that still gain: the margins fall evenly from the first to the day's whole (v_sale - v_buy)
    v_d := 2 * (v_n * v_m1 - (v_sale - v_buy)) / (v_n * (v_n - 1));
    v_k := case when v_m1 <= 0 then 0 when v_d <= 0 then v_n else least(v_n, floor(v_m1 / v_d) + 1) end;
    v_gain := case when v_d <= 0 then v_sale - v_buy else v_k * v_m1 - v_d * v_k * (v_k - 1) / 2 end;
    v_coin := (v_sale - v_buy) - v_n * v_fixed - coalesce(public.profit_tax(p_sell, greatest(v_gain, 0), p_player), 0);
  end if;
  return jsonb_build_object(
    'runs', v_n, 'coin', round(v_coin), 'stop', v_stop,
    'seconds', round(case when v_stop = 'allowance' then greatest(v_day, v_n * p_interval) else v_n * p_interval end),
    'traded', round(coalesce(v_buy, 0) + coalesce(v_sale, 0)));
end
$body$
  $f$;

  execute $f$
create function public.job_trip(p_fleet uuid, p_from uuid, p_codes text[], p_cost boolean)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0496: A JOB'S SAIL FROM ONE HARBOUR THROUGH OTHERS, AS THE JOB WOULD SAIL IT AND AS THE MAP PRICES IT. The legs are
-- public.fleet_job_sails' (0494: THE authority on a job's legs, harbour by harbour, each judged by the leg judge): no way through ->
-- {shut: {code, sentence}}, the door's own refusal. p_cost: the legs are handed, with their courses, to world.trip_cost (0360: THE quote
-- of a trip of sails, which reads the CALLER) -> {legs, nm, seconds, wages, stores, dock_fee, total}; seconds are its `days` (the
-- sailing and the calls between) in real time. Not p_cost: {legs, nm} alone, the miles of those courses as cmd.issue_lines measures
-- them. No estimate of its own. Writes nothing.
declare
  v_s    jsonb;
  v_legs jsonb := '[]'::jsonb;
  v_at   text := (select p.code from public.ports p where p.id = p_from);
  l      jsonb;
  v_to   text;
  v_c    jsonb;
  v_nm   numeric;
begin
  v_s := public.fleet_job_sails(p_fleet, p_from, p_codes);
  if v_s ? 'missing' then
    return jsonb_build_object('shut', jsonb_build_object('code', coalesce(v_s->>'pause', 'E_NO_COURSE'),
             'sentence', coalesce(v_s->>'sentence', format('no course the world remembers reaches %s', v_s->>'missing'))));
  end if;
  for l in select e from jsonb_array_elements(v_s->'lines') e loop
    v_to := substr(l->>'text', 6);   -- 'SAIL <code>'
    v_legs := v_legs || jsonb_build_array(jsonb_build_object('from', v_at, 'to', v_to, 'course', l->'path'));
    v_at := v_to;
  end loop;
  if jsonb_array_length(v_legs) = 0 then
    return jsonb_build_object('shut', jsonb_build_object('code', 'E_SAME_DEST', 'sentence', 'she lies there already'));
  end if;
  if not p_cost then
    select sum((s->>'nm')::numeric) into v_nm
      from jsonb_array_elements(v_legs) e cross join lateral jsonb_array_elements(voyage.segments_from_course(e->'course')) s;
    return jsonb_build_object('legs', jsonb_array_length(v_legs), 'nm', round(coalesce(v_nm, 0), 1));
  end if;
  v_c := world.trip_cost(p_fleet, v_legs);
  if v_c is null or jsonb_typeof(v_c->'days') is distinct from 'number' then
    return jsonb_build_object('shut', jsonb_build_object('code', 'E_UNPRICED', 'sentence', 'that trip cannot be priced now'));
  end if;
  return jsonb_build_object(
    'legs', jsonb_array_length(v_legs),
    'nm', (select round(coalesce(sum((e->>'nm')::numeric), 0), 1) from jsonb_array_elements(v_c->'legs') e),
    'seconds', round((v_c->>'days')::numeric * 86400 / public.wc_num('time_compression')),
    'wages', v_c->'wages', 'stores', v_c->'supplies', 'dock_fee', v_c->'dock_fee', 'total', v_c->'total');
end
$body$
  $f$;

  execute $f$
create function public.sea_actions_for(p_player uuid, p_fleet uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0496: WHAT ONE FLEET MAY BE SET TO NOW, each option in the one shape (public.action_shape), and ONLY what cmd.set_fleet_job would take.
-- {options, closed, cut}. closed {code, sentence}: the door is shut for every option (dark, not her fleet, on a standing route); then none.
-- WHAT IS ALWAYS THERE, AND WHAT MAY BE LEFT OUT. The Best run and every Bring home the door would take are built first and are never
-- left out. Only the list of single runs (a good to a harbour) is bounded, BY COUNT: the first c_top paying cards in the plan's own
-- order (profit a second, then the good), and `cut` true says cards past them were left out. NOTHING IS CUT BY THE CLOCK: a slow
-- machine serves the same options as a fast one. Past c_guard of its own time the read answers closed E_SLOW and no option (an honest
-- "ask again"), never a shorter list.
-- THE QUOTES ARE THE SERVER'S OWN, no second estimator:
--   world.best_sales(fleet, harbour)   the cards of the harbour she lies at (or is bound for): good, harbour, units, cost, profit, seconds
--   world.quote                        a card's sale, whole (the coin a completion brings in; Trading counts what is bought and sold)
--   public.job_trip                    the legs (public.fleet_job_sails, 0494) and the sail back or home (world.trip_cost)
--   public.fleet_job_end / _ends       bring home (0492): the home harbour, the shed's room; public.fleet_buy_capacity: the units and cost
-- THE OPTIONS:
--   sea:best                 the Best run (job best): priced as the card the job's plan would take first now (the plan's own order);
--                            one way, a sale ends it (returns false): interval = the card's seconds + the dock turn + one wait for the
--                            job tick (half of public.fleet_job_tick_s). net and interval_s are that one sale's; NO per_hour is served
--                            (null): the next run is another sale from another harbour
--   sea:fixed:G:A:B:sell     buy G where she lies, sell at B, sail back: the c_top best cards. interval = the WHOLE cycle: the card's
--                            seconds out + the turn at B + the sail back (world.trip_cost) + the turn at A + two waits for the job tick
--                            (public.fleet_job_tick_s). net = the card's profit less the sail back's wages, stores and dock fees.
--                            ITS PER HOUR IS ITS DAY'S (`day`: public.run_day, public.action_over_day), not the first run's
--   sea:fixed:G:A:H:store    buy G where she lies, STORE it at home, sail back (lit assign_home_enabled, docked, not at home): the units
--                            and cost the BUY line would take (the home shed's room binds, public.fleet_job_ends); net = -(buy + trip);
--                            the two waits and the day as above
-- NOT OFFERED: a run whose way out or back the leg judge shuts (range, stores, no course); a bring-home the door refuses (no home, no
-- warehouse, bought at home) or the shed stops (E_SHED_FULL). A read; world.best_sales reads the CALLER, so asked for anyone else: closed.
declare
  c_top    constant int := 8;
  -- THE LAST RESORT, never a shorter list: past this the read answers `closed` E_SLOW (ask again) and no option at all
  c_guard  constant interval := interval '5 seconds';
  c_slow   constant jsonb := jsonb_build_object('options', '[]'::jsonb, 'cut', false,
                               'closed', jsonb_build_object('code', 'E_SLOW', 'sentence', 'the quotes are slow just now: ask again in a moment'));
  v_t0     timestamptz := clock_timestamp();
  f        public.fleets%rowtype;
  v_at     uuid;
  v_code   text;
  v_lead   numeric := 0;
  v_docked boolean := false;
  v_turn   numeric := world.trip_stop_seconds();
  v_tick   numeric := public.fleet_job_tick_s();
  v_int    numeric;
  v_nm     numeric;
  v_day    jsonb;
  v_tr     record;
  v_ex     record;
  v_bs     jsonb;
  v_best   jsonb;
  v_fixed  jsonb := '[]'::jsonb;
  v_store  jsonb := '[]'::jsonb;
  v_trips  jsonb := '{}'::jsonb;
  v_t      jsonb;
  v_cut    boolean := false;
  c        record;
  v_dest   uuid;
  v_gid    uuid;
  v_gross  numeric;
  v_n      int := 0;
  v_end    jsonb;
  v_home   text;
  v_ends   jsonb;
  v_cap    jsonb;
  v_units  numeric;
  v_cost   numeric;
  v_back   numeric;
begin
  select * into f from public.fleets x where x.id = p_fleet;
  if f.id is null or f.player_id is distinct from p_player then
    return jsonb_build_object('options', '[]'::jsonb, 'cut', false,
                              'closed', jsonb_build_object('code', 'E_NO_SUCH_FLEET', 'sentence', 'that fleet is not yours'));
  end if;
  if not public.fleet_jobs_on() then
    return jsonb_build_object('options', '[]'::jsonb, 'cut', false,
                              'closed', jsonb_build_object('code', 'E_NOT_IN_USE', 'sentence', 'standing jobs are not open yet'));
  end if;
  if exists (select 1 from public.standing_routes r where r.fleet_id = p_fleet) then
    return jsonb_build_object('options', '[]'::jsonb, 'cut', false,
                              'closed', jsonb_build_object('code', 'E_ROUTE_TAKEN', 'sentence', format('%s runs a route; take her off it first', f.name)));
  end if;
  select t.xp, t.per into v_tr from public.level_activity_terms() t where t.code = 'trade';
  select t.xp, t.per into v_ex from public.level_activity_terms() t where t.code = 'miles';

  -- WHERE HER QUOTES RUN FROM: the harbour she lies at, or the one her voyage is bound for (the way in is taken off a card's seconds)
  if f.port_id is not null then
    select p.id, p.code into v_at, v_code from public.ports p where p.id = f.port_id and p.kind = 'HARBOUR';
    v_docked := v_at is not null and f.status = 'DOCKED';
  else
    select p.id, p.code, greatest(extract(epoch from v.eta - now()), 0) into v_at, v_code, v_lead
      from public.voyages v join public.ports p on p.id = v.dest_port_id and p.kind = 'HARBOUR'
     where v.fleet_id = p_fleet and v.status = 'SAILING' order by v.departed_at desc limit 1;
  end if;
  if v_at is not null and public.current_player_id() is not distinct from p_player then
    begin
      v_bs := world.best_sales(p_fleet, v_at);
    exception when others then
      v_bs := null;
    end;
  end if;

  -- BRING HOME (0492), BUILT FIRST AND NEVER CUT: what the door's own judge takes (public.fleet_job_end), the trip there and back,
  -- the BUY line's units. Every good the harbour sells, in the order of its code: a fixed list, whatever the machine's speed
  if v_docked and public.assign_home_on() then
    begin
      v_end := public.fleet_job_end(p_player, jsonb_build_object('buy', v_code, 'end', 'store'));
    exception when others then
      if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
      v_end := null;
    end;
    v_home := v_end->>'sell';
    if v_home is not null then
      v_t := public.job_trip(p_fleet, v_at, array[v_home, v_code], true);
      if not (v_t ? 'shut') then
        for c in
          select g.id, g.code
            from public.port_goods pg join public.goods g on g.id = pg.good_id
           where pg.port_id = v_at and public.port_offers(v_at, g.id)
           order by g.code
        loop
          if clock_timestamp() - v_t0 > c_guard then
            return c_slow;
          end if;
          v_ends := public.fleet_job_ends(p_player, p_fleet, jsonb_build_object('good', c.code, 'buy', v_code, 'sell', v_home, 'end', 'store'), v_code);
          continue when v_ends ? 'pause' or v_ends ? 'wait';
          if v_ends ? 'buy' then
            select q.units, q.total into v_units, v_cost
              from world.quote(v_at, c.id, split_part(v_ends->>'buy', ' ', 3)::numeric, 'buy', null, p_fleet) q;
          else
            v_cap := public.fleet_buy_capacity(p_fleet, c.id);
            v_units := (v_cap->>'max_qty')::numeric;
            v_cost := (v_cap->>'est_total')::numeric;
          end if;
          continue when coalesce(v_units, 0) < 1 or v_cost is null;
          v_int := (v_t->>'seconds')::numeric + v_turn + v_tick;
          v_day := public.run_day(p_player, p_fleet, v_at, null, c.id, v_units, v_int, v_cost, 0, -(v_cost + (v_t->>'total')::numeric));
          v_store := v_store || jsonb_build_array(public.action_over_day(public.action_shape(
            format('sea:fixed:%s:%s:%s:store', c.code, v_code, v_home), 'sea', 'trading', 1, v_int,
            jsonb_build_object('coin', v_cost),
            jsonb_build_object('coin', 0, 'items', jsonb_build_array(jsonb_build_object('good', c.code, 'units', v_units, 'basis', round(v_cost / v_units, 2)))),
            jsonb_build_array(jsonb_build_object('skill', 'trading', 'xp', floor(v_cost / v_tr.per * v_tr.xp)),
                              jsonb_build_object('skill', 'exploration', 'xp', floor((v_t->>'nm')::numeric / v_ex.per * v_ex.xp))),
            jsonb_build_object('total', round((v_t->>'total')::numeric), 'wages', v_t->'wages', 'stores', v_t->'stores', 'dock_fee', v_t->'dock_fee'),
            -(v_cost + (v_t->>'total')::numeric), 'quote',
            jsonb_build_object('job', jsonb_build_object('kind', 'fixed', 'params', jsonb_build_object('good', c.code, 'buy', v_code, 'end', 'store')),
                               'good', c.code, 'buy', v_code, 'sell', v_home, 'end', 'store', 'units', v_units, 'returns', true, 'varies', false)),
            v_day,
            floor((v_day->>'traded')::numeric / v_tr.per * v_tr.xp) + floor((v_day->>'runs')::numeric * (v_t->>'nm')::numeric / v_ex.per * v_ex.xp),
            (v_day->>'runs')::numeric * v_units));
        end loop;
      end if;
    end if;
  end if;

  -- THE CARDS, in the order the Best run's plan takes them (public.fleet_job_plan: profit a second, then the good). The Best run is
  -- the first of them she can sail: made before any row, so it is never left out
  for c in
    select g.e->>'good' as good, g.e->>'port' as port, g.e->>'basis' as basis, (g.e->>'units')::numeric as units,
           (g.e->>'profit')::numeric as profit, coalesce((g.e->>'cost')::numeric, 0) as cost,
           greatest(coalesce((g.e->>'seconds')::numeric, (g.e->>'days')::numeric * 86400) - v_lead, 1) as secs
      from jsonb_array_elements(coalesce(v_bs->'goods', '[]'::jsonb)) g(e)
     where (g.e->>'pays')::boolean and g.e->>'port' is not null and jsonb_typeof(g.e->'profit') = 'number' and (g.e->>'profit')::numeric > 0
       and g.e->'near' is distinct from 'false'::jsonb
       and (jsonb_typeof(g.e->'seconds') = 'number' or jsonb_typeof(g.e->'days') = 'number')
     order by (g.e->>'profit')::numeric / greatest(coalesce((g.e->>'seconds')::numeric, (g.e->>'days')::numeric * 86400), 1) desc, g.e->>'good'
     limit greatest(c_top, coalesce(public.wc_int('fleet_jobs_runs'), 12))
  loop
    v_dest := (select p.id from public.ports p where p.code = c.port and p.kind = 'HARBOUR');
    v_gid := (select g.id from public.goods g where g.code = c.good);
    continue when v_dest is null or v_gid is null or coalesce(c.units, 0) <= 0;
    if not v_trips ? c.port then
      v_trips := v_trips || jsonb_build_object(c.port, jsonb_build_object('out', public.job_trip(p_fleet, v_at, array[c.port], false)));
    end if;
    v_t := v_trips->c.port;
    continue when v_t->'out' ? 'shut';
    v_gross := (select q.total from world.quote(v_dest, v_gid, c.units, 'sell', null, p_fleet) q);
    continue when v_gross is null;
    if v_best is null then
      v_best := public.action_shape('sea:best', 'sea', 'trading', 1, c.secs + v_turn + v_tick / 2,
        jsonb_build_object('coin', c.cost), jsonb_build_object('coin', v_gross),
        jsonb_build_array(jsonb_build_object('skill', 'trading', 'xp', floor((c.cost + v_gross) / v_tr.per * v_tr.xp)),
                          jsonb_build_object('skill', 'exploration', 'xp', floor((v_t->'out'->>'nm')::numeric / v_ex.per * v_ex.xp))),
        jsonb_build_object('total', round(v_gross - c.cost - c.profit)), c.profit, 'quote',
        jsonb_build_object('job', jsonb_build_object('kind', 'best', 'params', '{}'::jsonb), 'good', c.good, 'buy', v_code, 'sell', c.port,
                           'end', 'sell', 'units', c.units, 'returns', false, 'varies', true,
                           -- NO RATE FOR THE BEST RUN: each run takes its own sale from a new harbour, so one card over its seconds is
                           -- not what an hour brings (measured: ten Best runs made 1.5 % of it). Her own runs give it (basis runs).
                           'per_hour', null, 'xp_per_hour', null, 'items_per_hour', null));
    end if;
    continue when c.basis = 'on_board';
    -- THE ROWS ARE BOUNDED BY COUNT, NEVER BY THE CLOCK: the first c_top cards in the plan's own order; a card past them is left out
    -- and `cut` says so. The same harbour and market give the same rows on any machine.
    if v_n >= c_top then
      v_cut := true;
      exit;
    end if;
    if clock_timestamp() - v_t0 > c_guard then
      return c_slow;
    end if;
    if not (v_t ? 'back') then
      v_t := v_t || jsonb_build_object('back', public.job_trip(p_fleet, v_dest, array[v_code], true));
      v_trips := v_trips || jsonb_build_object(c.port, v_t);
    end if;
    continue when v_t->'back' ? 'shut';
    v_n := v_n + 1;
    v_back := (v_t->'back'->>'total')::numeric;
    v_int := c.secs + v_turn + (v_t->'back'->>'seconds')::numeric + v_turn + v_tick;
    v_nm := (v_t->'out'->>'nm')::numeric + (v_t->'back'->>'nm')::numeric;
    v_day := public.run_day(p_player, p_fleet, v_at, v_dest, v_gid, c.units, v_int, c.cost, v_gross, c.profit - v_back);
    v_fixed := v_fixed || jsonb_build_array(public.action_over_day(public.action_shape(
      format('sea:fixed:%s:%s:%s:sell', c.good, v_code, c.port), 'sea', 'trading', 1, v_int,
      jsonb_build_object('coin', c.cost), jsonb_build_object('coin', v_gross),
      jsonb_build_array(jsonb_build_object('skill', 'trading', 'xp', floor((c.cost + v_gross) / v_tr.per * v_tr.xp)),
                        jsonb_build_object('skill', 'exploration', 'xp', floor(v_nm / v_ex.per * v_ex.xp))),
      jsonb_build_object('total', round(v_gross - c.cost - c.profit + v_back),
                         'back', jsonb_build_object('wages', v_t->'back'->'wages', 'stores', v_t->'back'->'stores', 'dock_fee', v_t->'back'->'dock_fee')),
      c.profit - v_back, 'quote',
      jsonb_build_object('job', jsonb_build_object('kind', 'fixed', 'params', jsonb_build_object('good', c.good, 'buy', v_code, 'sell', c.port)),
                         'good', c.good, 'buy', v_code, 'sell', c.port, 'end', 'sell', 'units', c.units, 'returns', true, 'varies', false)),
      v_day,
      floor((v_day->>'traded')::numeric / v_tr.per * v_tr.xp) + floor((v_day->>'runs')::numeric * v_nm / v_ex.per * v_ex.xp), 0));
  end loop;

  -- more paying cards than the plan's own count looks at: rows were left out
  if not v_cut and (select count(*) from jsonb_array_elements(case when jsonb_typeof(v_bs->'goods') = 'array' then v_bs->'goods' else '[]'::jsonb end) x(e)
                     where (x.e->>'pays')::boolean and x.e->>'port' is not null and jsonb_typeof(x.e->'profit') = 'number' and (x.e->>'profit')::numeric > 0
                       and x.e->'near' is distinct from 'false'::jsonb and x.e->>'basis' is distinct from 'on_board')
                   > greatest(c_top, coalesce(public.wc_int('fleet_jobs_runs'), 12)) then
    v_cut := true;
  end if;

  return jsonb_build_object(
    'options',
      -- the Best run first (unpriced when no card can be sailed: the door still takes it), then the runs by coin an hour, then bring home
      jsonb_build_array(coalesce(v_best, public.action_shape('sea:best', 'sea', 'trading', 1, null, null, null, null, null, null, 'none',
        jsonb_build_object('job', jsonb_build_object('kind', 'best', 'params', '{}'::jsonb), 'returns', false, 'varies', true))))
      || coalesce((select jsonb_agg(e order by (e->>'per_hour')::numeric desc, e->>'id') from jsonb_array_elements(v_fixed) e), '[]'::jsonb)
      || coalesce((select jsonb_agg(e order by (e->>'items_per_hour')::numeric desc, e->>'id') from jsonb_array_elements(v_store) e), '[]'::jsonb),
    'closed', null, 'cut', v_cut or coalesce((v_bs->>'cut')::boolean, false),
    'at', v_code);
end
$body$
  $f$;

  execute $f$
create function public.land_actions_for(p_player uuid, p_ord integer)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0496: WHAT A LAND PARTY MAY BE SENT ON NOW, each job in the one shape (public.action_shape), and ONLY what cmd.land_send would take
-- (public.land_send_for's refusals, read here in its order). {options, closed, cut}. closed: the door is shut whatever the job (dark,
-- no such party, the party out: E_LAND_OUT, a haul waiting for room: E_SHED_FULL); then none. An option is a job of a skill that is
-- open (public.land_skill_on) whose terms name no refusal (public.land_terms' `short`: the level, the materials, no land in reach).
-- THE QUOTE is public.land_terms, the terms Send would freeze: interval = its trip (march, turns, march, the passage both ways); a
-- completion is one trip: p units of the good and xp x p; a make job is one unit a trip from its inputs. No coin moves ashore yet.
declare
  c_guard constant interval := interval '5 seconds';   -- the last resort: closed E_SLOW, never a shorter list
  v_t0   timestamptz := clock_timestamp();
  lp     public.land_parties%rowtype;
  la     record;
  t      jsonb;
  v_out  jsonb := '[]'::jsonb;
  v_cut  boolean := false;
  v_p    numeric;
begin
  if not public.land_on() then
    return jsonb_build_object('options', '[]'::jsonb, 'cut', false,
                              'closed', jsonb_build_object('code', 'E_NOT_IN_USE', 'sentence', 'the land is not open yet'));
  end if;
  if p_ord is distinct from 1 then
    return jsonb_build_object('options', '[]'::jsonb, 'cut', false,
                              'closed', jsonb_build_object('code', 'E_NO_SUCH_PARTY', 'sentence', 'there is no such party'));
  end if;
  select * into lp from public.land_parties x where x.player_id = p_player and x.ord = 1;
  if lp.id is null and public.home_port_of(p_player) is null then
    return jsonb_build_object('options', '[]'::jsonb, 'cut', false,
                              'closed', jsonb_build_object('code', 'E_NO_HOUSE', 'sentence', 'a company with no home city has no party'));
  end if;
  if lp.action is not null then
    return jsonb_build_object('options', '[]'::jsonb, 'cut', false,
                              'closed', jsonb_build_object('code', 'E_LAND_OUT', 'sentence', 'the party is out; call it home first'));
  end if;
  if lp.waiting > 0 or lp.found_waiting <> '{}'::jsonb then
    return jsonb_build_object('options', '[]'::jsonb, 'cut', false,
                              'closed', jsonb_build_object('code', 'E_SHED_FULL', 'sentence', 'a haul waits for room in Storage: sell, ship or use some first'));
  end if;
  for la in
    select a.code, a.skill, a.kind, a.level, a.xp, g.code as good
      from public.land_actions a
      join public.goods g on g.id = a.good_id
      join public.level_skills s on s.code = a.skill
     where public.land_skill_on(a.skill)
     order by s.ord, a.ord
  loop
    if clock_timestamp() - v_t0 > c_guard then
      return jsonb_build_object('options', '[]'::jsonb, 'cut', false,
                                'closed', jsonb_build_object('code', 'E_SLOW', 'sentence', 'the terms are slow just now: ask again in a moment'));
    end if;
    t := public.land_terms(p_player, la.code);
    continue when t is null or jsonb_typeof(t->'short') = 'object';
    v_p := (t->>'p')::numeric;
    v_out := v_out || jsonb_build_array(public.action_shape(
      'land:' || la.code, la.kind, la.skill, la.level, (t->>'trip')::numeric,
      jsonb_build_object('coin', 0, 'items', coalesce((select jsonb_agg(jsonb_build_object('good', i->>'code', 'units', (i->>'qty')::numeric * v_p) order by i->>'code')
                                                         from jsonb_array_elements(t->'make'->'inputs') i), '[]'::jsonb)),
      jsonb_build_object('coin', 0, 'items', jsonb_build_array(jsonb_build_object('good', la.good, 'units', v_p))),
      jsonb_build_array(jsonb_build_object('skill', la.skill, 'xp', la.xp * v_p)),
      '{}'::jsonb, 0, 'quote',
      jsonb_strip_nulls(jsonb_build_object('action', la.code, 'good', la.good, 'have', (t->>'have')::int, 'region', t->>'region',
                                           'home', (t->>'home')::boolean, 'via', t->>'via', 'over_cap', (t->>'over_cap')::boolean,
                                           'crowd', (t->>'crowd')::numeric, 'can', (t->'make'->>'can')::int))));
  end loop;
  return jsonb_build_object('options', v_out, 'closed', null, 'cut', v_cut);
end
$body$
  $f$;

  execute $f$
create function public.workers_for(p_player uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0496: EVERY WORKER OF ONE COMPANY, ONE ROW EACH (docs/design/hq-corp-2026-11-24.md B3): her fleets by their founding, then her land
-- party. A row: {id, kind, name, at, state, worker_state, action, progress, stop, runs, measured}.
--   id            fleet:<uuid> | party:<n>: what world.actions takes
--   state         idle (no action) | working | waiting | stopped: a fleet's as public.away_report_for words it, on public.fleet_state
--   worker_state  a fleet's public.fleet_state (THE one rule: port, sea, battle, laid_up, wrecked); a party's public.land_progress phase
--   action        her action in the one shape (public.action_shape), null when idle. `basis` says where its figures come from:
--                   runs   her own completed runs: her fleet's ledger rows since the job was set (the last 24 hours at most, the
--                          (player_id, created_at) index, read ONCE for all her fleets), from her first BUY to her last: whole runs
--                          only, when at least c_enough BUYs lie there (so two whole runs or more). interval_s, per_hour: those rows;
--                          xp: Trading on what was bought and sold and Exploration on the miles sailed in them; items: what a
--                          bring-home job STORED in them (her events)
--                   quote  a Best run under way: the card its plan took (fleet_jobs.last: profit, seconds), one way, with its one
--                          wait for the job tick (half of public.fleet_job_tick_s): that sale's net and seconds, and NO per_hour (null)
--                   terms  a land job: the terms frozen at Send (public.land_terms' answer, kept on the party)
--                   none   nothing has priced it yet (a fixed job before two whole runs): the figures are null; world.actions quotes it
--   progress      the served stamps a bar is drawn between: {from, to, leg, ...}. Sea: the voyage's departed_at and due_at (eta when
--                 none), leg out | back | way, from_port, to_port. In port: {from: null, to: the job's next_at or her ready_at, leg: port}.
--                 Land: this trip's start and public.land_progress' next_home_at, leg = its phase, with turns_home and in_packs.
--   stop          why she stopped: {code, sentence} (a job's paused_reason and its last word; a party at the away cap: cap; a haul
--                 waiting for room: E_SHED_FULL)
-- NO QUOTE IS ASKED HERE (world.best_sales is a second's work a fleet): a company's list is its rows and one ledger range. Writes nothing.
declare
  c_enough constant int := 3;
  v_turn   numeric := world.trip_stop_seconds();
  v_tr     record;
  v_ex     record;
  v_out    jsonb := '[]'::jsonb;
  r        record;
  lp       public.land_parties%rowtype;
  la       record;
  v_act    jsonb;
  v_prog   jsonb;
  v_stop   jsonb;
  v_state  text;
  v_secs   numeric;
  v_cyc    numeric;
  v_nm     numeric;
  v_put    numeric;
  v_id     text;
  v_more   jsonb;
  v_pr     jsonb;
  v_home   uuid;
  v_p      numeric;
begin
  select t.xp, t.per into v_tr from public.level_activity_terms() t where t.code = 'trade';
  select t.xp, t.per into v_ex from public.level_activity_terms() t where t.code = 'miles';
  for r in
    with jl as materialized (
      select l.fleet_id, l.kind, l.ducats_delta as d, l.created_at as at
        from public.ledger l
        join public.fleet_jobs j on j.fleet_id = l.fleet_id and j.player_id = p_player
       where l.player_id = p_player and l.created_at > now() - interval '24 hours' and l.created_at >= j.since
         and l.kind <> 'FOUNDING' and left(l.kind, 6) <> 'PROBE_'
    ), bd as (
      select jl.fleet_id, min(jl.at) as t0, max(jl.at) as t1, count(distinct jl.at) as n from jl where jl.kind = 'BUY' group by jl.fleet_id
    ), ag as (
      select jl.fleet_id, bd.n, bd.t0, bd.t1, sum(jl.d) as coin, coalesce(sum(abs(jl.d)) filter (where jl.kind in ('BUY', 'SELL')), 0) as traded
        from jl join bd on bd.fleet_id = jl.fleet_id
       where jl.at >= bd.t0 and jl.at < bd.t1
       group by jl.fleet_id, bd.n, bd.t0, bd.t1
    )
    select f.id, f.name, f.status, f.ready_at, pt.code as at, st.s as fstate,
           j.fleet_id is not null as has_job, j.kind as jkind, j.params, j.runs, j.last, j.paused_reason, j.next_at,
           v.departed_at, coalesce(v.due_at, v.eta) as due, vo.code as v_from, vd.code as v_to,
           exists (select 1 from public.orders o where o.fleet_id = f.id and o.status in ('pending', 'active')) as queued,
           a.n, a.t0, a.t1, a.coin, a.traded
      from public.fleets f
      left join public.ports pt on pt.id = f.port_id
      left join public.fleet_jobs j on j.fleet_id = f.id
      left join lateral (select x.departed_at, x.due_at, x.eta, x.origin_port_id, x.dest_port_id from public.voyages x
                          where x.fleet_id = f.id and x.status = 'SAILING' order by x.departed_at desc limit 1) v on true
      left join public.ports vo on vo.id = v.origin_port_id
      left join public.ports vd on vd.id = v.dest_port_id
      left join ag a on a.fleet_id = f.id
     cross join lateral (select public.fleet_state(f.id) as s) st
     where f.player_id = p_player
     order by f.created_at, f.id
  loop
    v_act := null; v_stop := null;
    if r.has_job then
      v_state := case when r.paused_reason is not null then 'stopped' when r.fstate = 'sea' or r.queued then 'working' else 'waiting' end;
      if r.paused_reason is not null then
        v_stop := jsonb_build_object('code', r.paused_reason, 'sentence', r.last->>'sentence');
      end if;
      v_id := case r.jkind when 'best' then 'sea:best'
                           when 'fixed' then format('sea:fixed:%s:%s:%s:%s', r.params->>'good', r.params->>'buy', r.params->>'sell', coalesce(r.params->>'end', 'sell'))
                           else format('sea:haul:%s', r.params->>'to') end;
      v_more := jsonb_strip_nulls(jsonb_build_object(
        'job', jsonb_build_object('kind', r.jkind, 'params', r.params),
        'good', coalesce(r.params->>'good', r.last->>'good'),
        'buy', case r.jkind when 'fixed' then r.params->>'buy' when 'best' then r.last->>'from' end,
        'sell', case r.jkind when 'fixed' then r.params->>'sell' when 'best' then r.last->>'to' else r.params->>'to' end,
        'end', case when r.jkind = 'land' then 'store' else coalesce(r.params->>'end', 'sell') end,
        'returns', r.jkind <> 'best', 'varies', r.jkind = 'best', 'left', r.params->'left'));
      if r.n >= c_enough and r.t1 > r.t0 then
        -- HER OWN RUNS: whole runs, from her first BUY to her last
        v_secs := extract(epoch from r.t1 - r.t0);
        v_cyc := r.n - 1;
        select coalesce(sum(x.total_nm), 0) into v_nm from public.voyages x
         where x.fleet_id = r.id and x.departed_at >= r.t0 and x.departed_at < r.t1;
        v_put := 0;
        if r.params->>'end' = 'store' then
          select coalesce(sum((e.payload->>'qty')::numeric), 0) into v_put from public.events e
           where e.player_id = p_player and e.created_at >= r.t0 and e.created_at < r.t1 and e.kind = 'STORED'
             and e.payload->>'fleet' = r.name and e.payload->>'good' = (select g.name from public.goods g where g.code = r.params->>'good');
        end if;
        v_act := public.action_shape(v_id, 'sea', 'trading', 1, v_secs / v_cyc, null,
          jsonb_build_object('coin', 0, 'items', case when v_put > 0 then jsonb_build_array(jsonb_build_object('good', r.params->>'good', 'units', round(v_put / v_cyc, 2)))
                                                     else '[]'::jsonb end),
          jsonb_build_array(jsonb_build_object('skill', 'trading', 'xp', round(r.traded / v_tr.per * v_tr.xp / v_cyc, 1)),
                            jsonb_build_object('skill', 'exploration', 'xp', round(v_nm / v_ex.per * v_ex.xp / v_cyc, 1))),
          null, r.coin / v_cyc, 'runs', v_more);
      elsif r.jkind = 'best' and (r.last->>'ok')::boolean and jsonb_typeof(r.last->'profit') = 'number' and jsonb_typeof(r.last->'seconds') = 'number' then
        v_act := public.action_shape(v_id, 'sea', 'trading', 1, (r.last->>'seconds')::numeric + v_turn + public.fleet_job_tick_s() / 2, null, null, null, null,
                                     (r.last->>'profit')::numeric, 'quote',
                                     -- one sale's net and seconds, and no rate: the next run is another sale (public.sea_actions_for)
                                     v_more || jsonb_build_object('per_hour', null, 'xp_per_hour', null, 'items_per_hour', null));
      else
        v_act := public.action_shape(v_id, 'sea', 'trading', 1, null, null, null, null, null, null, 'none', v_more);
      end if;
    else
      v_state := 'idle';
    end if;
    v_prog := case
      when r.departed_at is not null then jsonb_build_object(
        'from', r.departed_at, 'to', r.due, 'from_port', r.v_from, 'to_port', r.v_to,
        'leg', case when r.jkind = 'fixed' and r.v_to = r.params->>'sell' then 'out'
                    when r.jkind = 'fixed' and r.v_to = r.params->>'buy' then 'back'
                    when r.jkind = 'best' and r.v_to = r.last->>'to' then 'out' else 'way' end)
      when r.has_job and r.paused_reason is null and coalesce(r.next_at, r.ready_at) > now() then
        jsonb_build_object('from', null, 'to', coalesce(r.next_at, r.ready_at), 'leg', 'port')
      else null end;
    v_out := v_out || jsonb_build_array(jsonb_build_object(
      'id', 'fleet:' || r.id, 'kind', 'fleet', 'fleet', r.id, 'name', r.name, 'at', r.at, 'state', v_state, 'worker_state', r.fstate,
      'action', v_act, 'progress', v_prog, 'stop', v_stop, 'runs', coalesce(r.runs, 0),
      'measured', case when r.n >= c_enough and r.t1 > r.t0 then r.n - 1 else 0 end));
  end loop;

  -- THE LAND PARTY (lit): the row a company keeps, or the one her first Send will make
  if public.land_on() and not coalesce((select pl.is_npc from public.players pl where pl.id = p_player), true) then
    select * into lp from public.land_parties x where x.player_id = p_player and x.ord = 1;
    v_home := coalesce(lp.port_id, public.home_port_of(p_player));
    if v_home is not null then
      v_act := null; v_stop := null; v_prog := null; v_state := 'idle'; v_pr := null;
      if lp.id is not null then
        v_pr := public.land_progress(lp.id, now());
      end if;
      if lp.action is not null then
        select a.code, a.skill, a.kind, a.level, g.code as good into la
          from public.land_actions a join public.goods g on g.id = a.good_id where a.code = lp.action;
        v_p := (lp.terms->>'p')::numeric;
        v_act := public.action_shape('land:' || lp.action, la.kind, la.skill, la.level, (lp.terms->>'trip')::numeric,
          jsonb_build_object('coin', 0, 'items', coalesce((select jsonb_agg(jsonb_build_object('good', e.key, 'units', (e.value->>'qty')::numeric * v_p) order by e.key)
                                                             from jsonb_each(lp.terms->'take') e), '[]'::jsonb)),
          jsonb_build_object('coin', 0, 'items', jsonb_build_array(jsonb_build_object('good', la.good, 'units', v_p))),
          jsonb_build_array(jsonb_build_object('skill', la.skill, 'xp', (lp.terms->>'xp')::numeric * v_p)),
          '{}'::jsonb, 0, 'terms',
          jsonb_strip_nulls(jsonb_build_object('action', lp.action, 'good', la.good,
                                               'region', (select rg.code from public.regions rg where rg.id = lp.region_id),
                                               'home', (lp.terms->>'home')::boolean, 'last', (lp.terms->>'last')::int)));
        v_state := case when (v_pr->>'stopped')::boolean then 'stopped'
                        when coalesce((v_pr->>'done')::boolean, false) or v_pr->>'phase' = 'home' then 'waiting' else 'working' end;
        if (v_pr->>'stopped')::boolean then
          v_stop := jsonb_build_object('code', 'cap', 'sentence', format('away longer than %s hours: collect to go on', public.wc_num('land_away_hours')));
        end if;
        v_prog := case
          when v_pr->>'state' = 'returning' then jsonb_build_object('from', null, 'to', (v_pr->>'home_at')::timestamptz, 'leg', v_pr->>'phase')
          else jsonb_build_object(
            'from', lp.started_at + make_interval(secs => (coalesce((v_pr->>'trips')::numeric, 0) * (lp.terms->>'trip')::numeric)::double precision),
            'to', (v_pr->>'next_home_at')::timestamptz, 'leg', v_pr->>'phase') end
          || jsonb_build_object('turns_home', coalesce((v_pr->>'new')::int, 0), 'in_packs', coalesce((v_pr->>'in_packs')::int, 0));
      elsif lp.waiting > 0 or lp.found_waiting <> '{}'::jsonb then
        v_state := 'stopped';
        v_stop := jsonb_build_object('code', 'E_SHED_FULL', 'sentence', 'a haul waits for room in Storage: sell, ship or use some first');
      end if;
      v_out := v_out || jsonb_build_array(jsonb_build_object(
        'id', 'party:1', 'kind', 'party', 'name', null, 'at', (select p.code from public.ports p where p.id = v_home),
        'state', v_state, 'worker_state', coalesce(v_pr->>'phase', 'home'),
        'action', v_act, 'progress', v_prog, 'stop', v_stop, 'runs', coalesce((v_pr->>'trips')::int, 0), 'measured', 0));
    end if;
  end if;
  return v_out;
end
$body$
  $f$;

  execute $f$
create function public.away_parties_for(p_player uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0496: THE AWAY REPORT'S LAND ROWS (docs/design/hq-corp-2026-11-24.md A2.5; public.away_report_for serves them as `parties`): one row a
-- land party with a job, or with a haul waiting. What came home while she was away is what public.land_progress counts and no press
-- has booked yet (turns_home: Collect books them), beside what this job has booked (turns_booked) and the experience due; `stop` is why
-- it stands: cap (the away cap, land_away_hours), shed_full (a haul waits for room), done (Repeat off: its last trip is home). Dark, a
-- merchant or no party: []. Writes nothing: a read is the sum, never a settle.
declare
  lp   public.land_parties%rowtype;
  v_pr jsonb;
  v_out jsonb := '[]'::jsonb;
begin
  if not public.land_on() then
    return v_out;
  end if;
  for lp in select * from public.land_parties x where x.player_id = p_player order by x.ord loop
    continue when lp.action is null and lp.waiting = 0 and lp.found_waiting = '{}'::jsonb;
    v_pr := public.land_progress(lp.id, now());
    v_out := v_out || jsonb_build_array(jsonb_build_object(
      'party', 'party:' || lp.ord, 'action', lp.action,
      'good', (select g.code from public.goods g where g.id = coalesce((lp.terms->>'good')::uuid, lp.waiting_good)),
      'state', case when lp.action is null or (v_pr->>'stopped')::boolean then 'stopped'
                    when coalesce((v_pr->>'done')::boolean, false) or v_pr->>'phase' = 'home' then 'waiting' else 'working' end,
      'phase', v_pr->>'phase', 'since', lp.started_at, 'seen_at', lp.touched_at,
      'turns_home', coalesce((v_pr->>'new')::int, 0), 'turns_booked', lp.booked, 'in_packs', coalesce((v_pr->>'in_packs')::int, 0),
      'waiting', lp.waiting, 'xp_due', lp.xp_due,
      'stop', case when lp.waiting > 0 or lp.found_waiting <> '{}'::jsonb then 'shed_full'
                   when (v_pr->>'stopped')::boolean then 'cap'
                   when coalesce((v_pr->>'done')::boolean, false) then 'done' end,
      'next_home_at', (v_pr->>'next_home_at')::timestamptz));
  end loop;
  return v_out;
end
$body$
  $f$;

  execute $f$
create function world.workers()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0496: THE WORKER LIST, HQ's one read of who does what (docs/design/hq-corp-2026-11-24.md B3): the caller's fleets and land party,
-- each with her action in the one shape, her state, the served stamps of her progress and her coin, experience and items an hour
-- (public.workers_for). Signed out or a merchant: {company: false, workers: []}. No switch of its own: a dark feature has no rows (no
-- job is set while fleet_jobs_enabled is off; no party while land_enabled is off). ask_s: the least seconds between two asks by one
-- client (and at once after a command of hers, or when a served stamp passes). A read: writes nothing, asks no quote.
declare
  v_me uuid := public.current_player_id();
begin
  if v_me is null or coalesce((select pl.is_npc from public.players pl where pl.id = v_me), true) then
    return jsonb_build_object('company', false, 'workers', '[]'::jsonb);
  end if;
  return jsonb_build_object('company', true, 'now', now(), 'ask_s', 60, 'away_cap_hours', public.wc_num('land_away_hours'),
                            'workers', public.workers_for(v_me));
end
$body$
  $f$;

  execute $f$
create function world.actions(p_worker text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0496: WHAT ONE WORKER MAY BE SET TO, the Assign sheet's one read (docs/design/hq-corp-2026-11-24.md A2.1, C3). p_worker is a row's
-- `id` from world.workers(): fleet:<uuid> (public.sea_actions_for) or party:<n> (public.land_actions_for). {company, worker, kind,
-- options, closed, cut, now, ask_s, ms}: each option in the one shape, only what the server would take; closed {code, sentence} when her
-- door is shut for all of them (E_SLOW: the read took too long, ask again); cut when single runs past the first eight were left out
-- (by count, never by the clock). Signed out or a merchant:
-- {company: false, options: []}. THIS READ PRICES (a fleet's is world.best_sales and the trips back): ask it when the sheet opens and
-- no sooner than ask_s after, never on a timer. Writes nothing.
declare
  v_me uuid := public.current_player_id();
  v_t0 timestamptz := clock_timestamp();
  v_r  jsonb;
  v_k  text;
begin
  if v_me is null or coalesce((select pl.is_npc from public.players pl where pl.id = v_me), true) then
    return jsonb_build_object('company', false, 'options', '[]'::jsonb);
  end if;
  if p_worker ~ '^fleet:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    v_k := 'fleet';
    v_r := public.sea_actions_for(v_me, substr(p_worker, 7)::uuid);
  elsif p_worker ~ '^party:[0-9]{1,4}$' then
    v_k := 'party';
    v_r := public.land_actions_for(v_me, substr(p_worker, 7)::int);
  else
    v_r := jsonb_build_object('options', '[]'::jsonb, 'cut', false,
                              'closed', jsonb_build_object('code', 'E_NO_SUCH_WORKER', 'sentence', 'there is no such worker'));
  end if;
  return jsonb_build_object('company', true, 'worker', p_worker, 'kind', v_k, 'now', now(), 'ask_s', 300) || v_r
         || jsonb_build_object('ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
end
$body$
  $f$;

  -- grants: the two reads to authenticated alone; every core server only (service_role too: the platform grants execute on a new
  -- function by default, 0459's first push)
  foreach v_q in array c_cores || c_doors loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_q::regprocedure);
  end loop;
  foreach v_q in array c_doors loop
    execute format('grant execute on function %s to authenticated', v_q::regprocedure);
  end loop;
  comment on function world.workers() is
    '0496: the worker list: each of her fleets and her land party with her action in the one shape (A2.1), her state, the served stamps of her progress and coin, experience and items an hour (basis: runs, quote, terms or none). A read; asks no quote. Client read: no more than once in 60 s.';
  comment on function world.actions(text) is
    '0496: one worker''s options (fleet:<uuid> | party:<n>) in the one shape, only what cmd.set_fleet_job or cmd.land_send would take, priced by the server''s own quotes. A read that prices: when the Assign sheet opens, never on a timer. Client read.';

  -- ── 3. THE HUNKS (each OLD text once in the live body; each reverses) ──
  create temp table hunks_0496 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0496 values
  ('public.away_report_for(uuid)', 1,
$h$           'since', min(x.seen), 'runs', coalesce(sum(x.runs), 0), 'earned', coalesce(sum(x.earned), 0))
$h$,
$h$           'since', min(x.seen), 'runs', coalesce(sum(x.runs), 0), 'earned', coalesce(sum(x.earned), 0),
           -- 0496: her land parties' rows (docs/design/hq-corp-2026-11-24.md A2.5; public.away_parties_for); every key above is as 0481 wrote it
           'parties', public.away_parties_for(p_player))
$h$),
  ('public.client_rpc_entry_points()', 1,
$h$      ('world',       'away_report',           ''),$h$,
$h$      ('world',       'away_report',           ''),
      -- 0496: the worker list and one worker's options (reads; no switch of their own)
      ('world',       'workers',               ''),
      ('world',       'actions',               'text'),$h$);

  for v_h in select h.fn from hunks_0496 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0496 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0496 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0496 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0496 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0496 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 4. SELF-ASSERT: the catalog, the grants, the registry ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_cores || c_doors) u(q)))) <> v_fn_before then
    raise exception '0496 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0496 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if exists (select 1 from unnest(c_cores) u(q)
              where has_function_privilege('authenticated', u.q::regprocedure, 'execute') or has_function_privilege('anon', u.q::regprocedure, 'execute')
                 or has_function_privilege('service_role', u.q::regprocedure, 'execute'))
     or exists (select 1 from unnest(c_doors) u(q)
                 where not has_function_privilege('authenticated', u.q::regprocedure, 'execute') or has_function_privilege('anon', u.q::regprocedure, 'execute')
                    or has_function_privilege('service_role', u.q::regprocedure, 'execute'))
     or (select count(*) from pg_proc p where p.oid = any (array[c_cores[1]::regprocedure::oid, c_cores[8]::regprocedure::oid, c_cores[9]::regprocedure::oid])
                                          and p.provolatile = 'i') <> 3
     or (select count(*) from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_cores[2:7] || c_doors) u(q))) and p.provolatile = 's') <> 8
     or (select count(*) from public.client_rpc_entry_points() e
          where (e.schema_name, e.function_name, e.arg_types) in (('world', 'workers', ''), ('world', 'actions', 'text'))
            and e.fn is not null and has_function_privilege('authenticated', e.fn, 'execute')) <> 2
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0496 self-assert FAIL: a core is reachable by a client or service_role, a read is not for authenticated alone or not in the registry, or a function is not a read';
  end if;

  -- ── 5. THE PROBE, rolled back by a raised sentinel (its own company's rows alone; no voyage starts, nothing is bought) ──
  begin
    v_me := public.new_house(c_uid, 'Casa dos Obreiros 0496', 'PRT');
    select f.id, f.port_id into v_fl, v_lis from public.fleets f where f.player_id = v_me;
    v_home := (select p.code from public.ports p where p.id = v_lis);
    update public.players p set ducats = 5000000 where p.id = v_me;
    perform cmd.assume_identity(c_uid);
    v_turn := world.trip_stop_seconds();

    -- (a) DARK: her fleet is a row with no action; every door says closed; the away report is as 0481 left it
    update public.world_config set value = 'false'::jsonb where key in ('fleet_jobs_enabled', 'land_enabled', 'assign_home_enabled');
    v_w := world.workers();
    if (v_w->>'company')::boolean is not true or jsonb_array_length(v_w->'workers') <> 1 or v_w #>> '{workers,0,id}' <> 'fleet:' || v_fl
       or v_w #>> '{workers,0,state}' <> 'idle' or v_w #>> '{workers,0,worker_state}' <> 'port' or v_w #>> '{workers,0,at}' <> v_home
       or jsonb_typeof(v_w #> '{workers,0,action}') <> 'null' or (v_w->>'ask_s')::int <> 60 then
      raise exception '0496 self-assert FAIL: dark, the worker list is not her one idle fleet: %', v_w;
    end if;
    if world.actions('fleet:' || v_fl) #>> '{closed,code}' <> 'E_NOT_IN_USE' or jsonb_array_length(world.actions('fleet:' || v_fl)->'options') <> 0
       or world.actions('party:1') #>> '{closed,code}' <> 'E_NOT_IN_USE' or world.actions('nobody') #>> '{closed,code}' <> 'E_NO_SUCH_WORKER'
       or world.actions('fleet:00000000-0496-4000-8000-0000000000ff') #>> '{closed,code}' <> 'E_NO_SUCH_FLEET'
       or world.away_report() is distinct from '{"on": false}'::jsonb then
      raise exception '0496 self-assert FAIL: dark, a door is not closed or the away report moved: % / %', world.actions('fleet:' || v_fl), world.away_report();
    end if;

    -- (b) LIT, AT HOME: the Best run first; every run's figures are its quotes'; no bring-home at home; every option is taken by the door
    update public.world_config set value = 'true'::jsonb where key in ('fleet_jobs_enabled', 'sea_courses_enabled', 'land_enabled', 'assign_home_enabled');
    v_t := clock_timestamp();
    v_w := world.workers();
    v_ms_w := round(extract(epoch from clock_timestamp() - v_t)::numeric * 1000, 1);
    if jsonb_array_length(v_w->'workers') <> 2 or v_w #>> '{workers,1,id}' <> 'party:1' or v_w #>> '{workers,1,state}' <> 'idle'
       or v_w #>> '{workers,1,at}' <> v_home then
      raise exception '0496 self-assert FAIL: lit, the worker list is not her fleet and her party: %', v_w;
    end if;
    v_t := clock_timestamp();
    v_a := world.actions('fleet:' || v_fl);
    v_ms_a := round(extract(epoch from clock_timestamp() - v_t)::numeric * 1000, 1);
    v_bs := world.best_sales(v_fl, v_lis);
    if jsonb_typeof(v_a->'closed') <> 'null' or v_a #>> '{options,0,id}' <> 'sea:best' or v_a #>> '{options,0,job,kind}' <> 'best'
       or exists (select 1 from jsonb_array_elements(v_a->'options') e where e->>'end' = 'store')
       or exists (select 1 from jsonb_array_elements(v_a->'options') e
                   where jsonb_typeof(e->'interval_s') = 'number'
                     and case when e ? 'day'
                              -- a repeating run: its day's coin over its day's seconds; the day is whole runs, and one run a day is that run
                              then (e->>'per_hour')::numeric <> round((e #>> '{day,coin}')::numeric * 3600 / (e #>> '{day,seconds}')::numeric)
                                   or (e #>> '{day,runs}')::numeric < 1 or (e #>> '{day,runs}')::numeric <> floor((e #>> '{day,runs}')::numeric)
                                   or e #>> '{day,stop}' not in ('allowance', 'time')
                                   or (e #>> '{day,seconds}')::numeric < (e #>> '{day,runs}')::numeric * (e->>'interval_s')::numeric - 1
                                   or ((e #>> '{day,runs}')::numeric = 1 and (e #>> '{day,coin}')::numeric <> (e->>'net')::numeric)
                                   -- no run after the first is priced above it: a day never reads better than its first run repeated
                                   or (e #>> '{day,coin}')::numeric > (e #>> '{day,runs}')::numeric * (e->>'net')::numeric + 1
                              else abs((e->>'per_hour')::numeric - (e->>'net')::numeric * 3600 / (e->>'interval_s')::numeric)
                                   > 2 + abs((e->>'per_hour')::numeric) * 0.02 end)
       or exists (select 1 from jsonb_array_elements(v_a->'options') e where (e->>'id' like 'sea:fixed:%') is distinct from (e ? 'day')) then
      raise exception '0496 self-assert FAIL: at home the options are not the Best run first and runs, a per hour is not net over interval, or a run''s per hour is not its day''s: %', left(v_a::text, 1500);
    end if;
    for v_e in select e from jsonb_array_elements(v_a->'options') e loop
      if v_e->>'id' like 'sea:fixed:%' then
        -- the card it came from, and the sail back, read again in this transaction
        select g.e into v_c from jsonb_array_elements(v_bs->'goods') g(e) where g.e->>'good' = v_e->>'good' and g.e->>'port' = v_e->>'sell';
        v_tb := public.job_trip(v_fl, (select p.id from public.ports p where p.code = v_e->>'sell' and p.kind = 'HARBOUR'), array[v_home], true);
        if v_c is null or v_tb ? 'shut'
           or public.fleet_job_sails(v_fl, v_lis, array[v_e->>'sell']) ? 'missing'
           or (v_e #>> '{inputs,coin}')::numeric <> round((v_c->>'cost')::numeric) or (v_e->>'units')::numeric <> (v_c->>'units')::numeric
           or (v_e->>'interval_s')::numeric <> round((v_c->>'seconds')::numeric + v_turn + (v_tb->>'seconds')::numeric + v_turn + public.fleet_job_tick_s())
           or (v_e->>'net')::numeric <> round((v_c->>'profit')::numeric - (v_tb->>'total')::numeric)
           or (v_e #>> '{cost,back,wages}')::numeric <> (v_tb->>'wages')::numeric
           or (v_e->>'returns')::boolean is not true or v_e->>'basis' <> 'quote' then
          raise exception '0496 self-assert FAIL: a run is not its card and its sail back: % / card % / back %', v_e, v_c, v_tb;
        end if;
        v_fixed := v_fixed + 1;
      end if;
      v_r := cmd.set_fleet_job(v_fl, v_e #>> '{job,kind}', v_e #> '{job,params}');
      if (v_r->>'ok')::boolean is not true or world.workers() #>> '{workers,0,action,id}' is distinct from v_e->>'id'
         or world.workers() #>> '{workers,0,action,basis}' <> 'none' or world.workers() #>> '{workers,0,state}' <> 'waiting' then
        raise exception '0496 self-assert FAIL: the door refused an option it was served, or her row is not that action: % / % / %', v_e, v_r, world.workers() #> '{workers,0}';
      end if;
      v_set := v_set + 1;
    end loop;
    v_note := format('workers %s ms; a fleet at %s: %s options in %s ms (%s runs there and back)', v_ms_w, v_home, jsonb_array_length(v_a->'options'), v_ms_a, v_fixed);

    -- (c) IN A SECOND HARBOUR: bring home is offered (lit) and each is the BUY line's units, the trip home and back, and taken by the door
    select k2.to_port, k2.code into v_x, v_xc from public.npc_known_legs(v_lis) k2 join public.ports p on p.id = k2.to_port
     where p.kind = 'HARBOUR' and public.fleet_job_course(v_fl, k2.to_port, v_lis) is not null order by k2.nm, k2.code limit 1;
    if v_x is not null then
      delete from public.fleet_jobs where fleet_id = v_fl;
      update public.fleets set port_id = v_x where id = v_fl;
      v_t := clock_timestamp();
      v_a := world.actions('fleet:' || v_fl);
      v_ms_b := round(extract(epoch from clock_timestamp() - v_t)::numeric * 1000, 1);
      v_tb := public.job_trip(v_fl, v_x, array[v_home, v_xc], true);
      for v_e in select e from jsonb_array_elements(v_a->'options') e loop
        if v_e->>'end' = 'store' then
          if v_e->>'sell' <> v_home or v_e->>'buy' <> v_xc or v_e #> '{job,params}' <> jsonb_build_object('good', v_e->>'good', 'buy', v_xc, 'end', 'store')
             or (v_e #>> '{outputs,items,0,units}')::numeric < 1 or v_e #>> '{outputs,items,0,good}' <> v_e->>'good'
             or (v_e->>'net')::numeric <> -round((v_e #>> '{inputs,coin}')::numeric + (v_tb->>'total')::numeric)
             or (v_e->>'interval_s')::numeric <> round((v_tb->>'seconds')::numeric + v_turn + public.fleet_job_tick_s())
             or (v_e->>'items_per_hour')::numeric <= 0 or not (v_e ? 'day')
             or (v_e->>'items_per_hour')::numeric
                  <> round((v_e #>> '{day,runs}')::numeric * (v_e #>> '{outputs,items,0,units}')::numeric * 3600 / (v_e #>> '{day,seconds}')::numeric, 2) then
            raise exception '0496 self-assert FAIL: a bring-home is not its buy and its trip home and back: % / trip %', v_e, v_tb;
          end if;
          v_store := v_store + 1;
        end if;
        v_r := cmd.set_fleet_job(v_fl, v_e #>> '{job,kind}', v_e #> '{job,params}');
        if (v_r->>'ok')::boolean is not true or world.workers() #>> '{workers,0,action,id}' is distinct from v_e->>'id' then
          raise exception '0496 self-assert FAIL: away from home the door refused an option it was served: % / %', v_e, v_r;
        end if;
        v_set := v_set + 1;
      end loop;
      -- bring home dark: none is offered
      update public.world_config set value = 'false'::jsonb where key = 'assign_home_enabled';
      if exists (select 1 from jsonb_array_elements(world.actions('fleet:' || v_fl)->'options') e where e->>'end' = 'store') then
        raise exception '0496 self-assert FAIL: bring home is offered while assign_home_enabled is off';
      end if;
      update public.world_config set value = 'true'::jsonb where key = 'assign_home_enabled';
      v_note := v_note || format('; at %s: %s options in %s ms (%s bring home)', v_xc, jsonb_array_length(v_a->'options'), v_ms_b, v_store);
    end if;

    -- (d) HER OWN RUNS: three BUYs since the job was set are two whole runs, read from her first BUY to her last
    if not exists (select 1 from public.fleet_jobs j where j.fleet_id = v_fl) then
      v_r := cmd.set_fleet_job(v_fl, 'best', '{}'::jsonb);
    end if;
    update public.fleet_jobs set since = now() - interval '4 hours' where fleet_id = v_fl;
    insert into public.ledger (player_id, fleet_id, kind, ducats_delta, balance_after, created_at) values
      (v_me, v_fl, 'BUY',   -777, 1, now() - interval '5 hours'),      -- before the job was set: left out
      (v_me, v_fl, 'BUY',  -1000, 1, now() - interval '3 hours'),
      (v_me, v_fl, 'SELL',  1500, 1, now() - interval '150 minutes'),
      (v_me, v_fl, 'WAGES', -100, 1, now() - interval '140 minutes'),
      (v_me, v_fl, 'BUY',  -1000, 1, now() - interval '2 hours'),
      (v_me, v_fl, 'SELL',  1500, 1, now() - interval '90 minutes'),
      (v_me, v_fl, 'BUY',  -1000, 1, now() - interval '1 hour'),       -- her last BUY: the run it opens is not whole, left out
      (v_me, v_fl, 'SELL',  1500, 1, now() - interval '30 minutes'),
      (v_me, null, 'SELL',  9999, 1, now() - interval '100 minutes');  -- no fleet's row: left out
    v_w := world.workers();
    if v_w #>> '{workers,0,action,basis}' <> 'runs' or (v_w #>> '{workers,0,measured}')::int <> 2
       or (v_w #>> '{workers,0,action,interval_s}')::numeric <> 3600 or (v_w #>> '{workers,0,action,per_hour}')::numeric <> 450
       or (v_w #>> '{workers,0,action,net}')::numeric <> 450
       or (v_w #>> '{workers,0,action,xp_per_hour}')::numeric
            <> round((select 5000 / t.per * t.xp from public.level_activity_terms() t where t.code = 'trade') / 2) then
      raise exception '0496 self-assert FAIL: her own runs are not read as written: %', v_w #> '{workers,0}';
    end if;
    v_note := v_note || '; her own runs: 2 whole runs, 450 an hour, basis runs';

    -- (e) HER PARTY: each job is public.land_terms' answer; one is sent through the door; then the door is closed and the report has her row
    v_t := clock_timestamp();
    v_a := world.actions('party:1');
    v_ms_p := round(extract(epoch from clock_timestamp() - v_t)::numeric * 1000, 1);
    v_land := jsonb_array_length(v_a->'options');
    if jsonb_typeof(v_a->'closed') <> 'null'
       or v_land <> (select count(*) from public.land_actions a
                      where public.land_skill_on(a.skill) and jsonb_typeof(public.land_terms(v_me, a.code)->'short') is distinct from 'object')
       or exists (select 1 from jsonb_array_elements(v_a->'options') e
                   cross join lateral (select public.land_terms(v_me, e->>'action') as t) z
                   join public.land_actions a on a.code = e->>'action'
                  where (e->>'interval_s')::numeric <> round((z.t->>'trip')::numeric) or (e #>> '{outputs,items,0,units}')::numeric <> (z.t->>'p')::numeric
                     or (e #>> '{xp,0,xp}')::numeric <> a.xp * (z.t->>'p')::numeric or (e->>'level')::int > (e->>'have')::int
                     or e->>'kind' <> a.kind or e->>'skill' <> a.skill or e->>'id' <> 'land:' || a.code) then
      raise exception '0496 self-assert FAIL: a party''s jobs are not public.land_terms'' answers: %', left(v_a::text, 1500);
    end if;
    if v_land > 0 then
      v_e := v_a #> '{options,0}';
      v_r := cmd.land_send(v_e->>'action');
      v_w := world.workers();
      v_a := world.away_report();
      if (v_r->>'ok')::boolean is not true or world.actions('party:1') #>> '{closed,code}' <> 'E_LAND_OUT'
         or jsonb_array_length(world.actions('party:1')->'options') <> 0
         or v_w #>> '{workers,1,action,id}' <> v_e->>'id' or v_w #>> '{workers,1,action,basis}' <> 'terms' or v_w #>> '{workers,1,state}' <> 'working'
         or (v_w #>> '{workers,1,action,interval_s}')::numeric <> (v_e->>'interval_s')::numeric
         or (v_w #>> '{workers,1,action,items_per_hour}')::numeric <> (v_e->>'items_per_hour')::numeric
         or (v_w #>> '{workers,1,progress,to}')::timestamptz <> now() + make_interval(secs => (v_e->>'interval_s')::double precision)
         or (v_w #>> '{workers,1,progress,from}')::timestamptz <> now()
         or not (v_a ? 'on' and v_a ? 'company' and v_a ? 'jobs' and v_a ? 'since' and v_a ? 'runs' and v_a ? 'earned')
         or jsonb_array_length(v_a->'jobs') <> 1 or v_a #>> '{jobs,0,fleet}' <> v_fl::text
         or jsonb_array_length(v_a->'parties') <> 1 or v_a #>> '{parties,0,party}' <> 'party:1' or v_a #>> '{parties,0,action}' <> v_e->>'action'
         or v_a #>> '{parties,0,state}' <> 'working' or (v_a #>> '{parties,0,turns_home}')::int <> 0 or v_a #> '{parties,0,stop}' <> 'null'::jsonb then
        raise exception '0496 self-assert FAIL: a sent party is not her row, the door is not closed, or the away report lost a key: % / % / % / %', v_r, v_w #> '{workers,1}', world.actions('party:1'), v_a;
      end if;
    end if;
    v_note := v_note || format('; her party: %s jobs in %s ms, one sent, then closed E_LAND_OUT; the away report keeps its keys and gains her row', v_land, v_ms_p);
    -- nobody's list is empty
    if public.workers_for('00000000-0496-4000-8000-0000000000ff'::uuid) <> '[]'::jsonb
       or public.away_parties_for('00000000-0496-4000-8000-0000000000ff'::uuid) <> '[]'::jsonb then
      raise exception '0496 self-assert FAIL: nobody''s list is not empty';
    end if;
    raise exception using errcode = 'ZX496', message = 'PROBE_ROLLBACK_0496';
  exception when sqlstate 'ZX496' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0496 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name = 'Casa dos Obreiros 0496' or p.auth_uid = c_uid) then
    raise exception '0496 self-assert FAIL: the probe left something behind';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c) <> v_cfg_before then
    raise exception '0496 self-assert FAIL: a world_config row moved';
  end if;

  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0496 self-assert FAIL: the file took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0496 self-assert ok: THE WORKERS AND THEIR ACTIONS. Two hunks once and reversing; eleven new functions (two client reads, nine cores server only); grants and volatility unmoved; no other function or knob moved. Probe (rolled back; % options set through the doors, none refused): %. % ms.',
    v_set, v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
