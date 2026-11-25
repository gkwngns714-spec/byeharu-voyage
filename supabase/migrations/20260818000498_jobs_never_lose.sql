-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none (dark: nothing changes for a player until the owner lights jobs_wait_enabled)
-- 0498 - JOBS NEVER LOSE  (dark: the owner's switch jobs_wait_enabled, false)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE LEAD, 2026-11-25: "a Repeat or Best sea job plans a run only if the server's own quote of that run at that moment leaves a profit
--   after tax, dock, wages, stores and the sail back; otherwise the job WAITS (not stopped), with a plain reason and a served retry
--   time, and resumes by itself as prices recover. A board card and a Best plan must price only the units the sale harbour's
--   allowance lets her sell now. hq_board's card per_hour comes from 0496's day authority (run_day)."
--   Measured first (docs/dev-log/2026-11-25-jobs-never-lose.md; scripts/ops/harness/hq-figures/): a fixed run set to repeat goes on
--   at a loss (quicksilver Lisbon - Setubal: +20,329, then -12,545, -43,096), and a Best card promised +555,908 for 328 units to a
--   harbour whose day's allowance took 153.
--
-- WHAT (lit; dark every body answers as before):
--   public.jobs_wait_on()        THE SWITCH, read once: world_config jobs_wait_enabled.
--   public.fleet_run_quote       THE QUOTE OF A FIXED RUN, NOW: the units she can buy (public.fleet_buy_capacity) cut to what the SALE
--                                harbour's allowance takes (world.daily_cap_remaining), their buy and sale (world.quote), the profit tax
--                                (public.profit_tax), and the trip there and back (public.job_trip: wages, stores, dock fees).
--   public.sale_fit              ONE CARD OF world.best_sales CUT TO WHAT ITS SALE HARBOUR TAKES NOW: its units, cost and profit priced
--                                again for the allowance left there (the card's own fees kept); nothing sellable or no profit left: none.
--   public.cards_fit             THE PAYING CARDS A CALLER MAY USE: the first p_limit by profit a second, each through public.sale_fit;
--                                for the board, each with `per_hour` from public.run_day (0496: the day's coin over the day's seconds
--                                of that run there and back). Dark: the cards as they were, untouched.
--   public.fleet_job_plan        (3 hunks) a FIXED job that sells: at its buy harbour it asks public.fleet_run_quote; no profit left ->
--                                {wait: low, sentence, net}: nothing is bought, nothing sails. Profit left and the sale's allowance
--                                under her hold: the BUY line names those units. The BEST job reads its cards through public.cards_fit.
--                                NOT TOUCHED: a run already at its sale's harbour still sells (she is there); a bring-home (end store)
--                                is exempt; the land haul.
--   public.fleet_job_note        (1 hunk) wait `low`: asked again no sooner than 600 s later (the longer of that and fleet_jobs_wait_s),
--                                its sentence and net kept on the job. The job is NOT stopped: public.fleet_jobs_due takes it again
--                                when the time has passed, and it starts by itself when the quote leaves a profit.
--   public.workers_for           (1 hunk) a fleet's row gains `wait` {code, sentence, retry_at} while her job waits (0496's row, a new key).
--   public.sea_actions_for       (1 hunk) world.actions' runs are read through public.cards_fit (the same cut).
--   public.run_day               (3 hunks; 0496's day) lit, THE DAY IS ITS GAINING RUNS: each run priced after the runs before it
--                                (world.quote's walk, the mark each sale leaves, the profit tax), and the day ends at the first that
--                                would leave no profit (stop `low`), as the job itself now waits there. Dark: as 0496 wrote it.
--   public.hq_board_for          (2 hunks) a trade card is read through public.cards_fit, and its `score` (coin an hour, the ranking's
--                                figure) is the card's `per_hour` from public.run_day; `profit` stays the ONE trip's profit.
-- NO HOT LOOP: a waiting job is not due before its next_at (public.fleet_jobs_due, unchanged), so it is quoted at most once in 600 s.
-- COST, BOUNDED: public.sale_fit is one allowance read a card, and four quotes only for a card that is cut. The board's per_hour is
--   one trip back (world.trip_cost) and at most two quotes a card, for the hq_board_runs cards a fleet it shows and no more, and none
--   once the fit has run 400 ms (the cards left carry no per_hour and rank last). world.best_sales is not touched.
-- NOT CHANGED: any knob but the new switch (the economy's are the owner's); world.best_sales; any command; any table; the ledger.
-- ROWS: one world_config row. No table, no index, no cron, no beat step. 0 new rows a minute.
-- budget: no table, no cron job, no autovacuum or fillfactor change. Lit: a waiting job is one quote in 600 s (two world.quote, one
--   world.trip_cost) instead of a run's orders; fewer rows, not more.
-- LOCKS: one INSERT (world_config); CREATE FUNCTION x4; CREATE OR REPLACE x6 by hunks. TIME: a few seconds. BUDGET: statement_timeout
--   90 s, lock_timeout 5 s; fails above 45 s.
-- ROLLBACK (forward, owner only): QUICK, jobs_wait_enabled false (every body answers as before; a job that waits is asked again at its
--   next_at and runs as before). FULL: a migration reversing the eleven hunks (OLD texts below verbatim) and dropping the four functions.
-- SELF-ASSERT: each hunk once and reversing; no other function moved; the hunked bodies' grants, volatility, definer, search path and
--   owner unmoved; the four new functions STABLE and server only; one knob added (false), no other moved. THE PROBE (rolled back by a
--   raised sentinel; its own company's rows alone): DARK, the cards pass untouched and a fixed plan is the plan it was; LIT, a card is
--   cut to the allowance left at its sale's harbour and never offered past it; a fixed run whose sale has fallen WAITS (no order, not
--   stopped, next_at 600 s on, her row says why and when), is not asked again before then, and STARTS BY ITSELF once the price is back;
--   the board's trade cards carry the day's coin an hour, never above the one trip's.
--   THE PROBE'S RUN IS BUILT, NEVER FOUND (2026-11-25: the first deploy was refused on prod, "a run whose quote loses is planned: LIS
--   quicksilver -> CAD": the probe took the live market's best card and assumed four times the sale's stock would sink it; there it
--   still paid). Now: one good Lisbon offers and her nearest remembered harbour that takes it, and the two market rows of that good the
--   quote reads (public.port_goods at Lisbon and at that harbour) written inside the probe: PAYING is Lisbon at the price band's floor
--   and the harbour at its ceiling; LOSING is both at the floor (the same mid at both ends, so the spread and the trip are the loss).
--   Each is then read back from the server's own quote (public.fleet_run_quote) before anything is asserted on it. No step asks the
--   live market for a sign, a time-budgeted read (world.best_sales, the board) is never required to carry a card, and no job but the
--   probe's is planned: her wait is written by public.fleet_job_note and her start by public.fleet_job_open, the two steps
--   public.tick_fleet_jobs makes for a due job (the tick itself would plan the real companies' due jobs first). Those two rows, the
--   quay and Lisbon's purse are held for the seconds the probe runs, as before.
-- VERSION: 0498 (it was 0497 until 2026-11-25; 0497 is `a-wreck-can-sell`, which hunks cmd.do_sell, cmd.do_store and cmd.advance, none
--   of these bodies; after 0496 `workers-read`; 0495 is `dividend-hourly`'s and touches none of them either).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array['public.fleet_job_plan(uuid)', 'public.fleet_job_note(uuid,jsonb)', 'public.workers_for(uuid)',
                                    'public.sea_actions_for(uuid,uuid)', 'public.hq_board_for(uuid)',
                                    'public.run_day(uuid,uuid,uuid,uuid,uuid,numeric,numeric,numeric,numeric,numeric)'];
  c_new    constant text[] := array['public.jobs_wait_on()', 'public.fleet_run_quote(uuid,uuid,uuid,text,text,text[])',
                                    'public.sale_fit(uuid,uuid,uuid,jsonb)', 'public.cards_fit(uuid,uuid,uuid,jsonb,integer,boolean)'];
  c_uid    constant uuid := '00000000-0498-4000-8000-000000000001';
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
  v_bs        jsonb;
  v_c         jsonb;
  v_fit       jsonb;
  v_p         jsonb;
  v_p0        jsonb;
  v_w         jsonb;
  v_b         jsonb;
  v_j         public.fleet_jobs%rowtype;
  v_dest      uuid;
  v_gid       uuid;
  v_left      numeric;
  v_stock     numeric;
  v_ms_dark   numeric;
  v_ms_lit    numeric;
  v_note      text := '';
  v_good      text;
  v_sell      text;
  v_rq        jsonb;
  v_m         jsonb;
  v_cap       jsonb;
  v_cards     jsonb;
  v_gross     numeric;
  v_o         int;
  v_slow      boolean;
  i           int;
begin
  perform set_config('statement_timeout', '90s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config where key = 'jobs_wait_enabled') or to_regprocedure('public.jobs_wait_on()') is not null then
    raise exception '0498 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.run_day(uuid,uuid,uuid,uuid,uuid,numeric,numeric,numeric,numeric,numeric)') is null
     or to_regprocedure('public.job_trip(uuid,uuid,text[],boolean)') is null or to_regprocedure('public.fleet_job_tick_s()') is null
     or to_regprocedure('public.fleet_job_plan(uuid)') is null or to_regprocedure('public.hq_board_for(uuid)') is null
     or to_regprocedure('world.daily_cap_remaining(uuid,uuid,uuid)') is null or to_regprocedure('public.profit_tax(uuid,numeric,uuid)') is null then
    raise exception '0498 refuses: 0496 (the workers and the day), 0481 (the standing jobs) or 0480 (the board) is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
    into v_cfg_before from public.world_config c;

  -- ── 2. THE KNOB ──
  insert into public.world_config (key, value, description) values
    ('jobs_wait_enabled', 'false'::jsonb,
     '0498: THE SWITCH (the owner''s). true: a fixed standing job that sells is started only when the server''s quote of that run leaves a profit after the tax, the dock fees, the wages, the stores and the sail back, and otherwise WAITS (asked again 10 minutes on, never stopped); a card of world.best_sales is cut to the units its sale harbour''s day allowance takes before the Best job, world.actions or the HQ board use it; the HQ board ranks a trade card by its day''s coin an hour (public.run_day). false: every one of them as before 0498.');

  -- ── 3. THE RULES ──
  execute $f$
create function public.jobs_wait_on()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0498: THE SWITCH, read once: world_config jobs_wait_enabled.
  select public.wc('jobs_wait_enabled') = 'true'::jsonb
$body$
  $f$;

  execute $f$
create function public.fleet_run_quote(p_player uuid, p_fleet uuid, p_from uuid, p_good text, p_sell text, p_codes text[])
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0498: THE QUOTE OF A FIXED RUN, AT THIS MOMENT, for the fleet lying at its buy harbour p_from: p_good bought there, sold at p_sell,
-- sailing p_codes (the harbours of the whole trip, there and back). Every figure is an authority's:
--   units   what she can buy (public.fleet_buy_capacity: her hold, the stock, the day's allowance here, her purse), cut to what the
--           SALE harbour's allowance takes today (world.daily_cap_remaining)
--   cost, gross   world.quote of those units, bought here and sold there
--   tax     public.profit_tax on the sale's profit
--   trip    public.job_trip (public.fleet_job_sails' legs, world.trip_cost): the wages, stores and dock fees there and back
--   net     gross - cost - tax - trip
-- {units, cost, gross, tax, trip, net, cut, why}. why: buy (nothing can be bought now) | allowance (the sale's harbour takes none
-- today) | null. {shut: true}: a leg has no way; the plan's own judge says it (public.fleet_job_sails). Writes nothing.
declare
  v_gid   uuid := (select g.id from public.goods g where g.code = p_good);
  v_dest  uuid := (select p.id from public.ports p where p.code = p_sell and p.kind = 'HARBOUR');
  v_cap   jsonb;
  v_u0    numeric;
  v_n     numeric;
  v_left  numeric;
  v_cost  numeric;
  v_gross numeric;
  v_got   numeric;
  v_tax   numeric;
  v_trip  jsonb;
begin
  if v_gid is null or v_dest is null then
    return jsonb_build_object('shut', true);
  end if;
  v_cap := public.fleet_buy_capacity(p_fleet, v_gid);
  v_u0 := coalesce((v_cap->>'max_qty')::numeric, 0);
  if v_u0 < 1 then
    return jsonb_build_object('units', 0, 'net', null, 'why', 'buy');
  end if;
  v_left := world.daily_cap_remaining(p_player, v_dest, v_gid);
  v_n := least(v_u0, floor(coalesce(v_left, v_u0)));
  if v_n < 1 then
    return jsonb_build_object('units', 0, 'net', null, 'why', 'allowance');
  end if;
  if v_n = v_u0 then
    v_cost := (v_cap->>'est_total')::numeric;
  else
    select q.total into v_cost from world.quote(p_from, v_gid, v_n, 'buy', null, p_fleet) q;
  end if;
  select q.units, q.total into v_got, v_gross from world.quote(v_dest, v_gid, v_n, 'sell', null, p_fleet) q;
  if v_cost is null or v_gross is null or coalesce(v_got, 0) < v_n then
    return jsonb_build_object('units', 0, 'net', null, 'why', 'allowance');
  end if;
  v_trip := public.job_trip(p_fleet, p_from, p_codes, true);
  if v_trip ? 'shut' then
    return jsonb_build_object('shut', true);
  end if;
  v_tax := coalesce(public.profit_tax(v_dest, v_gross - v_cost, p_player), 0);
  return jsonb_build_object('units', v_n, 'cost', round(v_cost), 'gross', round(v_gross), 'tax', v_tax, 'trip', round((v_trip->>'total')::numeric),
                            'net', round(v_gross - v_cost - v_tax - (v_trip->>'total')::numeric), 'cut', v_n < v_u0, 'why', null);
end
$body$
  $f$;

  execute $f$
create function public.sale_fit(p_player uuid, p_fleet uuid, p_from uuid, p_card jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0498: ONE CARD OF world.best_sales ({good, basis, port, units, cost, profit, ...}) CUT TO WHAT ITS SALE HARBOUR TAKES NOW. A card
-- prices the load she can BUY; the sale harbour's day allowance (world.daily_cap_remaining: its stock mark's share, less what she has
-- traded there today) may take less, and the rest would stay aboard. The allowance takes the load: the card, untouched. It takes less:
-- the card priced again for those units: `units`, `cost` and `profit` from world.quote and public.profit_tax, less the card's own fees
-- (what its profit left out of sale - buy - tax: dock fees, wages, stores), with `cut` true. It takes none, or no profit is left: null.
-- Her cargo (basis on_board) is not cut: it is aboard already. One allowance read; four quotes only when it cuts. Writes nothing.
declare
  v_units numeric := (p_card->>'units')::numeric;
  v_cost0 numeric := coalesce((p_card->>'cost')::numeric, 0);
  v_dest  uuid;
  v_gid   uuid;
  v_left  numeric;
  v_n     numeric;
  v_g0    numeric;
  v_fees  numeric;
  v_bu    numeric;
  v_b     numeric;
  v_su    numeric;
  v_s     numeric;
  v_p     numeric;
begin
  if p_card->>'basis' = 'on_board' or p_card->>'port' is null or coalesce(v_units, 0) <= 0 then
    return p_card;
  end if;
  v_dest := (select p.id from public.ports p where p.code = p_card->>'port' and p.kind = 'HARBOUR');
  v_gid := (select g.id from public.goods g where g.code = p_card->>'good');
  if v_dest is null or v_gid is null then
    return p_card;
  end if;
  v_left := world.daily_cap_remaining(p_player, v_dest, v_gid);
  if v_left is null or v_left >= v_units then
    return p_card;
  end if;
  v_n := floor(v_left);
  if v_n < 1 then
    return null;
  end if;
  select q.total into v_g0 from world.quote(v_dest, v_gid, v_units, 'sell', null, p_fleet) q;
  v_fees := greatest(coalesce(v_g0 - v_cost0 - coalesce(public.profit_tax(v_dest, v_g0 - v_cost0, p_player), 0) - (p_card->>'profit')::numeric, 0), 0);
  select q.units, q.total into v_bu, v_b from world.quote(p_from, v_gid, v_n, 'buy', null, p_fleet) q;
  select q.units, q.total into v_su, v_s from world.quote(v_dest, v_gid, v_n, 'sell', null, p_fleet) q;
  if coalesce(v_bu, 0) < v_n or coalesce(v_su, 0) < v_n then
    return null;
  end if;
  v_p := v_s - v_b - coalesce(public.profit_tax(v_dest, v_s - v_b, p_player), 0) - v_fees;
  if v_p <= 0 then
    return null;
  end if;
  return p_card || jsonb_build_object('units', v_n, 'cost', v_b, 'profit', round(v_p), 'pays', true, 'cut', true);
end
$body$
  $f$;

  execute $f$
create function public.cards_fit(p_player uuid, p_fleet uuid, p_from uuid, p_goods jsonb, p_limit integer, p_day boolean)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0498: THE CARDS A CALLER MAY USE, from world.best_sales' `goods` (the Best job, world.actions, the HQ board). DARK
-- (jobs_wait_enabled false): p_goods as it is, untouched. LIT: the paying cards (the callers' own filter: pays, a harbour, a profit,
-- `near` not false, a time), by profit a second, each through public.sale_fit (cut to its sale harbour's allowance, or left out), until
-- p_limit stand; at most p_limit + 4 are looked at. p_day (the board): each carries `per_hour`, THE DAY'S COIN AN HOUR of that run there
-- and back (public.run_day, 0496's one authority: its interval as public.sea_actions_for makes it, the sail back by public.job_trip);
-- her cargo's sale (on_board) its one sale's net over its seconds and one wait for the tick. No trip back, or the fit has run 400 ms:
-- no per_hour (the caller ranks it last). Writes nothing.
declare
  c_budget constant interval := interval '400 milliseconds';
  v_t0    timestamptz := clock_timestamp();
  v_out   jsonb := '[]'::jsonb;
  v_n     int := 0;
  v_seen  int := 0;
  v_turn  numeric;
  v_tick  numeric;
  v_code  text;
  c       record;
  v_card  jsonb;
  v_dest  uuid;
  v_gid   uuid;
  v_back  jsonb;
  v_gross numeric;
  v_int   numeric;
  v_day   jsonb;
  v_ph    numeric;
begin
  if not public.jobs_wait_on() then
    return coalesce(p_goods, '[]'::jsonb);
  end if;
  if p_day then
    v_turn := world.trip_stop_seconds();
    v_tick := public.fleet_job_tick_s();
    v_code := (select p.code from public.ports p where p.id = p_from);
  end if;
  for c in
    select g.e, greatest(coalesce((g.e->>'seconds')::numeric, (g.e->>'days')::numeric * 86400), 1) as secs
      from jsonb_array_elements(coalesce(p_goods, '[]'::jsonb)) g(e)
     where (g.e->>'pays')::boolean and g.e->>'port' is not null and jsonb_typeof(g.e->'profit') = 'number' and (g.e->>'profit')::numeric > 0
       and g.e->'near' is distinct from 'false'::jsonb
       and (jsonb_typeof(g.e->'seconds') = 'number' or jsonb_typeof(g.e->'days') = 'number')
     order by (g.e->>'profit')::numeric / greatest(coalesce((g.e->>'seconds')::numeric, (g.e->>'days')::numeric * 86400), 1) desc, g.e->>'good'
  loop
    exit when v_n >= greatest(coalesce(p_limit, 0), 0) or v_seen >= greatest(coalesce(p_limit, 0), 0) + 4;
    v_seen := v_seen + 1;
    v_card := public.sale_fit(p_player, p_fleet, p_from, c.e);
    continue when v_card is null;
    if p_day then
      v_ph := null;
      if v_card->>'basis' = 'on_board' then
        v_ph := round((v_card->>'profit')::numeric * 3600 / (c.secs + v_turn + v_tick / 2));
      elsif clock_timestamp() - v_t0 <= c_budget then
        v_dest := (select p.id from public.ports p where p.code = v_card->>'port' and p.kind = 'HARBOUR');
        v_gid := (select g.id from public.goods g where g.code = v_card->>'good');
        v_back := case when v_dest is not null and v_gid is not null then public.job_trip(p_fleet, v_dest, array[v_code], true) end;
        if v_back is not null and not (v_back ? 'shut') then
          v_gross := (select q.total from world.quote(v_dest, v_gid, (v_card->>'units')::numeric, 'sell', null, p_fleet) q);
          v_int := c.secs + v_turn + (v_back->>'seconds')::numeric + v_turn + v_tick;
          v_day := public.run_day(p_player, p_fleet, p_from, v_dest, v_gid, (v_card->>'units')::numeric, v_int,
                                  coalesce((v_card->>'cost')::numeric, 0), v_gross, (v_card->>'profit')::numeric - (v_back->>'total')::numeric);
          if v_day is not null and (v_day->>'seconds')::numeric > 0 then
            v_ph := round((v_day->>'coin')::numeric * 3600 / (v_day->>'seconds')::numeric);
          end if;
        end if;
      end if;
      v_card := v_card || jsonb_build_object('per_hour', v_ph);
    end if;
    v_out := v_out || jsonb_build_array(v_card);
    v_n := v_n + 1;
  end loop;
  return v_out;
end
$body$
  $f$;

  foreach v_q in array c_new loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_q::regprocedure);
  end loop;

  -- ── 4. THE HUNKS (each OLD text once in the live body; each reverses) ──
  create temp table hunks_0498 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0498 values
  ('public.fleet_job_plan(uuid)', 1,
$h$  v_end   jsonb;   -- 0492: what the fixed job's end and count make of this run (public.fleet_job_ends)
$h$,
$h$  v_end   jsonb;   -- 0492: what the fixed job's end and count make of this run (public.fleet_job_ends)
  v_rq    jsonb;   -- 0498: the run's quote at this moment (public.fleet_run_quote)
$h$),
  ('public.fleet_job_plan(uuid)', 2,
$h$    if v_at = v_buy then
      v_s := public.fleet_job_sails(f.id, f.port_id, v_st || v_sell);
$h$,
$h$    if v_at = v_buy then
      -- 0498 (jobs_wait_enabled): A RUN THAT SELLS IS STARTED ONLY IF ITS QUOTE NOW LEAVES A PROFIT after the tax, the dock fees, the
      -- wages, the stores and the sail back (public.fleet_run_quote). No profit, nothing to buy, or the sale's harbour takes none today:
      -- she WAITS (public.fleet_job_note: asked again 10 minutes on; not stopped). The sale's allowance under what she can buy: the
      -- BUY names those units, so nothing she cannot sell is bought. A bring-home (STORE) is exempt.
      if public.jobs_wait_on() and coalesce(v_end->>'verb', 'SELL') = 'SELL' and not (v_end ? 'buy') then
        v_rq := public.fleet_run_quote(j.player_id, f.id, f.port_id, v_g, v_sell,
                                       v_st || v_sell || array(select u.c from unnest(v_st) with ordinality u(c, i) order by u.i desc) || v_buy);
        if not (v_rq ? 'shut') then
          if coalesce((v_rq->>'units')::numeric, 0) < 1 or coalesce((v_rq->>'net')::numeric, 0) <= 0 then
            return jsonb_build_object('wait', 'low', 'net', v_rq->'net',
                                      'sentence', case v_rq->>'why' when 'buy' then 'nothing to buy now'
                                                                    when 'allowance' then 'the day''s allowance is spent' else 'prices low' end);
          end if;
          if (v_rq->>'cut')::boolean then
            v_end := v_end || jsonb_build_object('buy', format('BUY %s %s', v_g, trim_scale((v_rq->>'units')::numeric)));
          end if;
        end if;
      end if;
      v_s := public.fleet_job_sails(f.id, f.port_id, v_st || v_sell);
$h$),
  ('public.fleet_job_plan(uuid)', 3,
$h$        from jsonb_array_elements(coalesce(v_bs->'goods', '[]'::jsonb)) g(e)
$h$,
$h$        -- 0498: the cards cut to what each sale's harbour takes now (public.cards_fit; dark: the cards as they are)
        from jsonb_array_elements(public.cards_fit(j.player_id, f.id, f.port_id, v_bs->'goods', greatest(0, coalesce(public.wc_int('fleet_jobs_runs'), 12)), false)) g(e)
$h$),
  ('public.fleet_job_note(uuid,jsonb)', 1,
$h$  elsif p_plan->>'wait' in ('nothing', 'unpriced', 'identity') then
$h$,
$h$  elsif p_plan->>'wait' = 'low' then
    -- 0498: the run's quote leaves no profit now: she waits, asked again no sooner than 10 minutes on; the job is not stopped
    update public.fleet_jobs
       set next_at = now() + make_interval(secs => greatest(600, coalesce(public.wc_num('fleet_jobs_wait_s'), 900))),
           last = jsonb_build_object('at', now(), 'wait', 'low', 'sentence', coalesce(p_plan->>'sentence', 'prices low'), 'net', p_plan->'net')
     where fleet_id = p_fleet and paused_reason is null;
  elsif p_plan->>'wait' in ('nothing', 'unpriced', 'identity') then
$h$),
  ('public.workers_for(uuid)', 1,
$h$      'action', v_act, 'progress', v_prog, 'stop', v_stop, 'runs', coalesce(r.runs, 0),
$h$,
$h$      'action', v_act, 'progress', v_prog, 'stop', v_stop, 'runs', coalesce(r.runs, 0),
      -- 0498: why a job that is not stopped waits, and when it is asked again (the job's own `last` and next_at)
      'wait', case when r.has_job and r.paused_reason is null and r.last->>'wait' is not null and r.next_at > now()
                   then jsonb_build_object('code', r.last->>'wait', 'retry_at', r.next_at,
                          'sentence', coalesce(r.last->>'sentence', case r.last->>'wait' when 'nothing' then 'nothing pays now' else 'waiting' end)) end,
$h$),
  ('public.sea_actions_for(uuid,uuid)', 1,
$h$      from jsonb_array_elements(coalesce(v_bs->'goods', '[]'::jsonb)) g(e)
$h$,
$h$      -- 0498: the cards cut to what each sale's harbour takes now (public.cards_fit; dark: the cards as they are)
      from jsonb_array_elements(public.cards_fit(p_player, p_fleet, v_at, v_bs->'goods', greatest(c_top, coalesce(public.wc_int('fleet_jobs_runs'), 12)), false)) g(e)
$h$),
  ('public.run_day(uuid,uuid,uuid,uuid,uuid,numeric,numeric,numeric,numeric,numeric)', 1,
$h$  v_w      numeric;
begin
$h$,
$h$  v_w      numeric;
  v_pb     numeric := 0;   -- 0498: the buys of the runs before this one
  v_ps     numeric := 0;   -- 0498: their sales
  v_cb     numeric;
  v_cs     numeric;
  v_m      numeric;
  v_net    numeric;
begin
$h$),
  ('public.run_day(uuid,uuid,uuid,uuid,uuid,numeric,numeric,numeric,numeric,numeric)', 2,
$h$    v_sale := 0;
  else
    v_tax1 := coalesce(public.profit_tax(p_sell, v_m1, p_player), 0);
$h$,
$h$    v_sale := 0;
  elsif public.jobs_wait_on() then
    -- 0498 (jobs_wait_enabled): A RUN THAT WOULD LEAVE NO PROFIT IS NOT STARTED (public.fleet_job_plan waits), so the day is its
    -- gaining runs. Each run is priced after the runs before it: its buy and its sale are the quay's walk from where they left it
    -- (world.quote of i runs' units less that of i - 1), its sale under the mark of the sales before it, less the profit tax and a
    -- run's other costs (the first run's: dock fees, wages, stores, the sail back). The first that leaves nothing ends the day.
    v_tax1 := coalesce(public.profit_tax(p_sell, v_m1, p_player), 0);
    v_fixed := greatest(v_m1 - p_net - v_tax1, 0);
    v_k := 0;
    v_gain := 0;
    for i in 1 .. v_n::int loop
      if i = 1 then
        v_cb := p_cost;
        v_cs := p_gross;
      else
        select q.total into v_cb from world.quote(p_buy, p_good, i * p_units, 'buy', null, p_fleet) q;
        select q.total into v_cs from world.quote(p_sell, p_good, i * p_units, 'sell', null, p_fleet) q;
      end if;
      exit when v_cb is null or v_cs is null;
      v_m := (v_cs - v_ps) * case when i > 1 and v_g0 is not null and v_g0 < 1
                                  then (1 - public.press_after(v_g0, (i - 1) * p_units, v_tgt, 'sell', public.wc_num('glut_per_depth'), public.wc_num('glut_max'))) / (1 - v_g0)
                                  else 1 end - (v_cb - v_pb);
      v_net := case when i = 1 then p_net else v_m - coalesce(public.profit_tax(p_sell, v_m, p_player), 0) - v_fixed end;
      exit when v_net <= 0;
      v_k := v_k + 1;
      v_gain := v_gain + v_net;
      v_pb := v_cb;
      v_ps := v_cs;
    end loop;
    if v_k < v_n then
      v_stop := 'low';
    end if;
    v_n := v_k;
    v_coin := v_gain;
    v_buy := v_pb;
    v_sale := v_ps;
  else
    v_tax1 := coalesce(public.profit_tax(p_sell, v_m1, p_player), 0);
$h$),
  ('public.run_day(uuid,uuid,uuid,uuid,uuid,numeric,numeric,numeric,numeric,numeric)', 3,
$h$    'seconds', round(case when v_stop = 'allowance' then greatest(v_day, v_n * p_interval) else v_n * p_interval end),
$h$,
$h$    -- 0498: stopped by a run that would not pay (`low`), she waits for the day's turn as when the allowance stops her
    'seconds', round(case when v_stop in ('allowance', 'low') then greatest(v_day, v_n * p_interval) else v_n * p_interval end),
$h$),
  ('public.hq_board_for(uuid)', 1,
$h$        from jsonb_array_elements(coalesce(v_bs->'goods', '[]'::jsonb)) g(e)
$h$,
$h$        -- 0498: the cards cut to what each sale's harbour takes now, each with its day's coin an hour (public.cards_fit; dark: as they are)
        from jsonb_array_elements(public.cards_fit(p_player, f.id, f.port_id, v_bs->'goods', v_runs, true)) g(e)
$h$),
  ('public.hq_board_for(uuid)', 2,
$h$        'score', round(s.profit * 3600 / s.secs), 'profit', round(s.profit), 'seconds', round(s.secs),
$h$,
$h$        -- 0498 (lit): coin an hour is the run's DAY (public.run_day through public.cards_fit), not one trip over its seconds; `profit` stays the trip's
        'score', case when public.jobs_wait_on() then (s.e->>'per_hour')::numeric else round(s.profit * 3600 / s.secs) end, 'profit', round(s.profit), 'seconds', round(s.secs),
$h$);

  for v_h in select h.fn from hunks_0498 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0498 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0498 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0498 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0498 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0498 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 5. SELF-ASSERT: the catalog, the grants, the knob ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked || c_new) u(q)))) <> v_fn_before then
    raise exception '0498 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0498 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if exists (select 1 from unnest(c_new) u(q)
              where has_function_privilege('authenticated', u.q::regprocedure, 'execute') or has_function_privilege('anon', u.q::regprocedure, 'execute')
                 or has_function_privilege('service_role', u.q::regprocedure, 'execute'))
     or (select count(*) from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_new) u(q))) and p.provolatile = 's' and p.prosecdef) <> 4
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0498 self-assert FAIL: a new function is reachable by a client or service_role, or is not a STABLE definer read';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, ''), ',' order by c.key))
        from public.world_config c where c.key <> 'jobs_wait_enabled') <> v_cfg_before
     or public.wc('jobs_wait_enabled') is distinct from 'false'::jsonb or public.jobs_wait_on() then
    raise exception '0498 self-assert FAIL: a knob other than jobs_wait_enabled moved, or the switch is not false';
  end if;

  -- ── 6. THE PROBE, rolled back by a raised sentinel (its own company's rows alone) ──
  begin
    v_me := public.new_house(c_uid, 'Casa da Espera 0498', 'PRT');
    select f.id, f.port_id into v_fl, v_lis from public.fleets f where f.player_id = v_me;
    update public.players p set ducats = 5000000 where p.id = v_me;
    update public.world_config set value = 'true'::jsonb where key in ('fleet_jobs_enabled', 'sea_courses_enabled', 'hq_board_enabled');
    perform cmd.assume_identity(c_uid);
    -- THE RUN, BUILT (the header): the dearest good Lisbon offers that her hold takes twenty of, and her nearest remembered harbour with
    -- a market row for it. Static rows choose the pair; the market chooses nothing.
    select g.code, g.id, k.code, k.to_port into v_good, v_gid, v_sell, v_dest
      from public.npc_known_legs(v_lis) k
      join public.port_goods ps on ps.port_id = k.to_port
      join public.goods g on g.id = ps.good_id
      join public.ports pd on pd.id = k.to_port and pd.kind = 'HARBOUR'
     where public.port_offers(v_lis, g.id)
       and exists (select 1 from public.port_goods pl where pl.port_id = v_lis and pl.good_id = g.id)
       and not public.culture_refuses(pd.culture, g.culture_mask)
       and public.fleet_free_hold(v_fl) >= 20 * g.bulk
     order by k.nm, g.base_value desc, g.code limit 1;
    if v_good is null then
      raise exception '0498 self-assert FAIL: the probe found no good Lisbon offers that a remembered harbour takes (static rows, not the market)';
    end if;
    -- PAYING: Lisbon at the band's floor (a full quay, the least affinity, a glut), the harbour at its ceiling (an empty quay, the
    -- most affinity, a dearth), both with room for any load (the mark sets the day's allowance)
    update public.port_goods pg set stock_target = 1000000, stock = 1000000000, affinity = 0.25, demand = 1, drift = 0, season_mod = 0,
                                    glut = 0.5, glut_at = now(), haul = 1
     where pg.port_id = v_lis and pg.good_id = v_gid;
    update public.port_goods pg set stock_target = 1000000, stock = 0, affinity = 3, demand = 1, drift = 0, season_mod = 0,
                                    glut = -0.5, glut_at = now()
     where pg.port_id = v_dest and pg.good_id = v_gid;
    v_rq := public.fleet_run_quote(v_me, v_fl, v_lis, v_good, v_sell, array[v_sell, 'LIS']);
    if coalesce((v_rq->>'net')::numeric, 0) <= 0 or coalesce((v_rq->>'units')::numeric, 0) <= 6 then
      raise exception '0498 self-assert FAIL: the probe did not build a paying run of more than 6 units (% from LIS to %, floor against ceiling): % ; the fault is the probe''s, not the market''s',
        v_good, v_sell, v_rq;
    end if;

    v_t := clock_timestamp();
    v_bs := world.best_sales(v_fl, v_lis);
    -- a time-budgeted read that was cut, or slow, is never REQUIRED to carry a card (prod: 1.8 to 2.7 s at Lisbon, cut at 2.5 s)
    v_slow := coalesce((v_bs->>'cut')::boolean, false) or clock_timestamp() - v_t > interval '1 second';
    -- the built run's card: the server's own (world.best_sales) when it served it, else the same figures from the same authorities
    select g.e into v_c from jsonb_array_elements(v_bs->'goods') g(e)
     where g.e->>'good' = v_good and g.e->>'port' = v_sell and (g.e->>'pays')::boolean and (g.e->>'profit')::numeric > 0
       and g.e->>'basis' is distinct from 'on_board' and g.e->'near' is distinct from 'false'::jsonb and jsonb_typeof(g.e->'seconds') = 'number'
       and (g.e->>'units')::numeric > 6;
    if v_c is null then
      v_cap := public.fleet_buy_capacity(v_fl, v_gid);
      select q.total into v_gross from world.quote(v_dest, v_gid, (v_cap->>'max_qty')::numeric, 'sell', null, v_fl) q;
      v_c := jsonb_build_object('good', v_good, 'basis', 'capacity', 'port', v_sell, 'units', (v_cap->>'max_qty')::numeric,
               'cost', (v_cap->>'est_total')::numeric, 'pays', true, 'near', true,
               'profit', round(v_gross - (v_cap->>'est_total')::numeric
                               - coalesce(public.profit_tax(v_dest, v_gross - (v_cap->>'est_total')::numeric, v_me), 0)),
               'seconds', (public.job_trip(v_fl, v_lis, array[v_sell], true)->>'seconds')::numeric);
      if coalesce((v_c->>'units')::numeric, 0) <= 6 or coalesce((v_c->>'profit')::numeric, 0) <= 0 or jsonb_typeof(v_c->'seconds') <> 'number' then
        raise exception '0498 self-assert FAIL: the probe did not build a paying card of more than 6 units: % ; the fault is the probe''s, not the market''s', v_c;
      end if;
      v_cards := coalesce(v_bs->'goods', '[]'::jsonb) || jsonb_build_array(v_c);
    else
      v_cards := v_bs->'goods';
    end if;

    -- (a) DARK: the cards pass untouched; a fixed plan is the plan it was (BUY ALL, no quote asked); the board's score is the trip's
    if public.cards_fit(v_me, v_fl, v_lis, v_cards, 3, true) is distinct from v_cards then
      raise exception '0498 self-assert FAIL: dark, public.cards_fit changed the cards';
    end if;
    perform cmd.set_fleet_job(v_fl, 'fixed', jsonb_build_object('good', v_good, 'buy', 'LIS', 'sell', v_sell));
    v_p0 := public.fleet_job_plan(v_fl);
    if v_p0 #>> '{lines,0,text}' is distinct from format('BUY %s ALL', v_good) then
      raise exception '0498 self-assert FAIL: dark, the fixed plan is not BUY ALL: %', left(v_p0::text, 400);
    end if;
    v_t := clock_timestamp();
    v_b := public.hq_board_for(v_me);
    v_ms_dark := round(extract(epoch from clock_timestamp() - v_t)::numeric * 1000);

    -- (b) LIT, the built run pays: the plan is the same run (its quote leaves a profit); the cards carry the day
    update public.world_config set value = 'true'::jsonb where key = 'jobs_wait_enabled';
    v_p := public.fleet_job_plan(v_fl);
    if not (v_p ? 'lines') or v_p #>> '{lines,0,text}' !~ ('^BUY ' || v_good || ' ') then
      raise exception '0498 self-assert FAIL: lit, a run whose quote leaves a profit is not planned: % (quote %)', left(v_p::text, 300), v_rq;
    end if;
    delete from public.fleet_jobs where fleet_id = v_fl;
    -- THE DAY'S COIN AN HOUR of the built card, from the one cut every reader makes (public.cards_fit), with no budgeted read between:
    -- it is served, and a day never reads better than its one trip over its own seconds
    v_m := public.cards_fit(v_me, v_fl, v_lis, jsonb_build_array(v_c), 1, true) -> 0;
    if v_m is null or jsonb_typeof(v_m->'per_hour') <> 'number'
       or (v_m->>'per_hour')::numeric > round((v_m->>'profit')::numeric * 3600 / greatest((v_m->>'seconds')::numeric, 1)) then
      raise exception '0498 self-assert FAIL: lit, the built card has no day''s coin an hour, or it reads above its one trip: % from %', v_m, v_c;
    end if;
    v_t := clock_timestamp();
    v_b := public.hq_board_for(v_me);
    v_ms_lit := round(extract(epoch from clock_timestamp() - v_t)::numeric * 1000);
    v_slow := v_slow or v_ms_lit > 1500;
    -- the board: every trade card it carries with a figure obeys the same bound; where its read was not cut or slow, the built run's
    -- card is on it with its figure (a card past the fit's 400 ms carries none and ranks last: the rule, not a fault)
    if exists (select 1 from jsonb_array_elements(v_b->'moves') m
                where m->>'kind' = 'trade' and m #>> '{needs,basis}' is distinct from 'on_board' and jsonb_typeof(m->'score') = 'number'
                  and (m->>'score')::numeric > round((m->>'profit')::numeric * 3600 / greatest((m->>'seconds')::numeric, 1)))
       or (not v_slow and not exists (select 1 from jsonb_array_elements(v_b->'moves') m
                                       where m->>'kind' = 'trade' and m #>> '{needs,good}' = v_good and jsonb_typeof(m->'score') = 'number')) then
      raise exception '0498 self-assert FAIL: lit, a trade card reads above its one trip, or the built run''s card is not on the board with its day''s coin an hour: %', left((v_b->'moves')::text, 1200);
    end if;
    v_note := format('the run built: %s from LIS to %s, %s units, net %s; the board %s ms dark, %s ms lit (%s trade cards, %s with the day''s coin an hour%s)',
                     v_good, v_sell, v_rq->>'units', v_rq->>'net', v_ms_dark, v_ms_lit,
                     (select count(*) from jsonb_array_elements(v_b->'moves') m where m->>'kind' = 'trade'),
                     (select count(*) from jsonb_array_elements(v_b->'moves') m where m->>'kind' = 'trade' and jsonb_typeof(m->'score') = 'number'),
                     case when v_slow then '; its budgeted read was cut or slow here, so the built card was not required on it' else '' end);

    -- (c) LIT, THE SALE'S HARBOUR TAKES ONLY PART: she has traded there today, 6.5 units are left of the day's allowance
    v_left := world.daily_cap_remaining(v_me, v_dest, v_gid);
    insert into public.trade_daily (player_id, port_id, good_id, game_day, qty) values (v_me, v_dest, v_gid, world.game_day(), v_left - 6.5);
    v_fit := public.sale_fit(v_me, v_fl, v_lis, v_c);
    if v_fit is not null and ((v_fit->>'units')::numeric <> 6 or (v_fit->>'cut')::boolean is not true
                              or (v_fit->>'profit')::numeric >= (v_c->>'profit')::numeric or (v_fit->>'profit')::numeric <= 0) then
      raise exception '0498 self-assert FAIL: a card is not cut to the 6 units its sale''s harbour takes: % from %', v_fit, v_c;
    end if;
    if exists (select 1 from jsonb_array_elements(public.cards_fit(v_me, v_fl, v_lis, v_cards, 12, false)) e
                where e->>'good' = v_good and e->>'port' = v_sell and (e->>'units')::numeric > 6) then
      raise exception '0498 self-assert FAIL: the cards still offer more than the sale''s harbour takes';
    end if;
    update public.trade_daily set qty = v_left where player_id = v_me and port_id = v_dest and good_id = v_gid;
    if public.sale_fit(v_me, v_fl, v_lis, v_c) is not null then
      raise exception '0498 self-assert FAIL: a card is offered though its sale''s harbour takes nothing today';
    end if;
    delete from public.trade_daily where player_id = v_me and port_id = v_dest and good_id = v_gid;
    v_note := v_note || format('; %s %s to %s %s when 6.5 are left, and left out when none is', v_c->>'units', v_good, v_sell,
                               case when v_fit is null then 'left out (6 units leave no profit)' else 'cut to 6 units' end);

    -- (d) LIT, THE SALE HAS FALLEN: LOSING, built: the harbour at the band's floor like Lisbon (the same mid at both ends: the spread,
    -- the tax and the trip are the loss, whatever the live market says). She waits; she is not stopped; nothing is ordered
    perform cmd.set_fleet_job(v_fl, 'fixed', jsonb_build_object('good', v_good, 'buy', 'LIS', 'sell', v_sell));
    update public.port_goods pg set stock = 1000000000, affinity = 0.25, glut = 0.5, glut_at = now(), haul = 1
     where pg.port_id = v_dest and pg.good_id = v_gid;
    v_rq := public.fleet_run_quote(v_me, v_fl, v_lis, v_good, v_sell, array[v_sell, 'LIS']);
    if (v_rq->>'net') is null or (v_rq->>'net')::numeric >= 0 then
      raise exception '0498 self-assert FAIL: the probe did not build a losing run (% from LIS to %, floor against floor): % ; the fault is the probe''s, not the market''s',
        v_good, v_sell, v_rq;
    end if;
    v_p := public.fleet_job_plan(v_fl);
    if v_p->>'wait' is distinct from 'low' or v_p ? 'lines' or (v_p->>'net')::numeric > 0 then
      raise exception '0498 self-assert FAIL: a run whose quote loses is planned: % (quote %)', left(v_p::text, 400), v_rq;
    end if;
    -- the tick's step for a plan with no lines (public.tick_fleet_jobs: the wait is written by public.fleet_job_note), for HER job alone
    perform public.fleet_job_note(v_fl, v_p);
    select * into v_j from public.fleet_jobs j where j.fleet_id = v_fl;
    v_w := world.workers() #> '{workers,0}';
    if v_j.paused_reason is not null or v_j.runs <> 0 or v_j.next_at < now() + interval '600 seconds' or v_j.last->>'wait' <> 'low'
       or exists (select 1 from public.orders o where o.fleet_id = v_fl)
       or (select f.status from public.fleets f where f.id = v_fl) <> 'DOCKED'
       or v_w->>'state' <> 'waiting' or v_w #>> '{wait,code}' <> 'low' or v_w #>> '{wait,sentence}' <> 'prices low'
       or (v_w #>> '{wait,retry_at}')::timestamptz <> v_j.next_at or jsonb_typeof(v_w->'stop') <> 'null' then
      raise exception '0498 self-assert FAIL: she did not wait (not stopped, nothing ordered, asked again 600 s on, her row saying why): job % / row %', to_jsonb(v_j), v_w;
    end if;
    -- not asked again before its time
    if exists (select 1 from public.fleet_jobs_due() d where d.fleet_id = v_fl) then
      raise exception '0498 self-assert FAIL: a waiting job is due before its next_at (a hot loop)';
    end if;
    -- THE PRICE IS BACK (the harbour at its ceiling again) and her time has come: she is due, and the tick's two steps start her
    update public.port_goods pg set stock = 0, affinity = 3, glut = -0.5, glut_at = now() where pg.port_id = v_dest and pg.good_id = v_gid;
    update public.fleet_jobs set next_at = now() - interval '1 second' where fleet_id = v_fl;
    if not exists (select 1 from public.fleet_jobs_due() d where d.fleet_id = v_fl) then
      raise exception '0498 self-assert FAIL: her time come, the waiting job is not due (it would never start by itself): %',
        (select to_jsonb(j) from public.fleet_jobs j where j.fleet_id = v_fl);
    end if;
    v_p := public.fleet_job_plan(v_fl);
    if not (v_p ? 'lines') then
      raise exception '0498 self-assert FAIL: with the price back her plan has no lines: %', left(v_p::text, 400);
    end if;
    -- the open never waits for the quay (-1: busy, the live beat holds it): asked again, as the tick's next run would, for 5 s at most
    for i in 1 .. 50 loop
      v_o := public.fleet_job_open(v_fl, v_p);
      exit when v_o <> -1;
      perform pg_sleep(0.1);
    end loop;
    select * into v_j from public.fleet_jobs j where j.fleet_id = v_fl;
    if v_o <> 1 or v_j.runs <> 1 or v_j.paused_reason is not null or (select f.status from public.fleets f where f.id = v_fl) <> 'SAILING'
       or world.workers() #> '{workers,0,wait}' <> 'null'::jsonb then
      raise exception '0498 self-assert FAIL: with the price back she did not start by herself (open %): %', v_o, to_jsonb(v_j);
    end if;
    v_note := v_note || '; the same run with its sale fallen waited (asked again 600 s on, not stopped, no order), and started by itself when the price was back';
    raise exception using errcode = 'ZX498', message = 'PROBE_ROLLBACK_0498';
  exception when sqlstate 'ZX498' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0498 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name = 'Casa da Espera 0498' or p.auth_uid = c_uid) then
    raise exception '0498 self-assert FAIL: the probe left something behind';
  end if;
  if public.wc('jobs_wait_enabled') is distinct from 'false'::jsonb then
    raise exception '0498 self-assert FAIL: the switch is not false after the probe';
  end if;

  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0498 self-assert FAIL: the file took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0498 self-assert ok: JOBS NEVER LOSE (dark). Eleven hunks once and reversing; four new functions STABLE and server only; no other function moved; one knob (jobs_wait_enabled false). Probe (rolled back): %. % ms.',
    v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
