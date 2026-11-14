-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0406 - A MERCHANT COUNTS THE PORT'S FEE BEFORE SHE SAILS  (the planner's net of a loop is less the dock fees the loop will pay)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none
--
-- WHY (prod, read-only, 2026-11-14, head 0404; docs/dev-log/2026-11-14-plan-fees.md):
--   About 25 merchant houses lie laid up with an empty purse. Eleven are ordinary houses; ten of them were gifted their capital three times in a
--   week (the gift pass's limit) and emptied again, each day earning about what it lost. The one ledger still kept (Hwang Dohoe, 11-13): sold
--   31,127 in 17 sales, bought 25,759 in 16, so the trade made 5,368; PORT_FEE 8,570 in 44 calls, tax 754, wages about 85. The dock fees ate more
--   than the trade made.
--   THE CAUSE IS IN THE PLANNER. What a lap of a loop leaves her is priced in ONE place, public.npc_plan (0142): the parcels' profit after tax,
--   less the loop's wages, less its stores. 0237 (every port charges, live since the economy closed) made every harbour she makes charge her
--   public.port_fee = round((port_fee_base + port_fee_pct x her cargo at cost) x her country's factor there x regard): 250 d. a call on prod at
--   peace, 62 at home, 500 at a rival's; a call, not a hull, and nothing waived at home. That charge never entered the planner's net. So a loop
--   whose margin is under the fees it pays still "pays" (0197), is chosen, sailed and written in her lap's book as a profit, and her purse falls.
--
-- WHAT THIS FILE DOES (two bodies re-cut by hunk, nothing else):
--   1. public.npc_leg_lines also answers `cost`: what the kept parcels of the leg cost her at the source (the sum of the same buy quotes its
--      profit is made of). No figure it answered before moves.
--   2. public.npc_plan takes from every loop's net the dock fee of each of its calls, asked of THE one fee, public.port_fee(the harbour she
--      makes, her company, her cargo at cost on arriving = the leg's `cost`): the function public.port_call charges her by, with the same
--      arguments (there the cargo is public.fleet_stock_at_cost of her fleet). No second formula; the knobs, her stance, a pirate home's free
--      quay and the open economy's 0 are all the function's own. The fee of a leg is asked once and kept with the leg (the plan's memo).
--   The net is what the planner already steers by, so everything that reads it follows with no other change: the score (net an hour), the choice
--   between her loop and the loops on offer, "a loop pays" (0197: net above nothing), the review of a loop that leaves her nothing, and the
--   lay-up (0181): a merchant whose best loop does not cover its fees waits in port instead of sailing it.
--   While the economy is open, or the purses are dark, public.port_fee answers 0 and every plan is what it was (asserted below: with the fee
--   knobs at 0 a merchant's plan is the pre-image's, row for row).
--
-- NOT DONE HERE (said, for the owner): a lap's book (standing_route_laps.net) still does not count the dock fees she paid, so the Stats' merchant
--   profit and the "losing" count read better than her purse; the leg's own keep test (a parcel must pay 5 % on its outlay) is before fees.
-- COLLISION: none with 0405 (#661: new objects only, no body of these two touched). 0406 applies on 0404 or on 0405.
-- LOCKS: CREATE OR REPLACE FUNCTION x2 by hunks. TIME: the cut is milliseconds; the probe plans ONE merchant three times in sub-transactions
--   rolled back (0.3 to 1.2 s a plan on prod): expected under 10 s there. BUDGET: statement_timeout 45 s, lock_timeout 5 s; fails above 20 s.
-- ROLLBACK (forward, owner only): scripts/ops/harness/plan-fees/rollback-0406.sql, a draft: the eight hunks reversed.
-- SELF-ASSERT: each hunk once and reversing; grants, volatility, definer, search path, owner unmoved; no other function moved; then the probe.
-- VERSION: 0406 (0405 lands first).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_cut constant text[] := array['public.npc_leg_lines(uuid,uuid,uuid,numeric,integer,numeric)', 'public.npc_plan(timestamp with time zone,uuid)'];
  v_t0        timestamptz := clock_timestamp();
  h           record;
  v_z         record;
  v_def       text;
  v_n         int;
  v_fn_before text;
  v_fleet     uuid;
  v_route     uuid;
  v_old       jsonb;
  v_new       jsonb;
  v_big       jsonb;
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if position('0406' in pg_get_functiondef('public.npc_plan(timestamp with time zone,uuid)'::regprocedure)) > 0 then
    raise exception '0406 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.port_fee(uuid,uuid,numeric)') is null or to_regprocedure('public.port_call(uuid,uuid,uuid,timestamp with time zone,timestamp with time zone,uuid)') is null then
    raise exception '0406 refuses: the dock fee (0237) is not in this world';
  end if;
  if (select p.provolatile from pg_proc p where p.oid = 'public.port_fee(uuid,uuid,numeric)'::regprocedure) <> 's' then
    raise exception '0406 refuses: public.port_fee is not STABLE';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0406 (fn text primary key, def text, meta text) on commit drop;
  insert into pre_0406
  select f, replace(pg_get_functiondef(f::regprocedure), E'\r', ''),
         (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
            from pg_proc p where p.oid = f::regprocedure)
    from unnest(c_cut) f;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and not exists (select 1 from unnest(c_cut) f where f::regprocedure = p.oid);

  -- ── 2. THE PROBE'S HAND (pg_temp, gone at commit): ONE merchant planned alone at her lap start by the live planner, with the dock fee's
  --      base set as told and its share of the cargo 0, the economy closed and the purses lit so that the fee is asked. It WRITES; every caller
  --      rolls it back. Answers her plan's receipt, what the plan wrote, and whether any stop of the loop written charges her.
  execute $f$
create function pg_temp.plan_0406(p_fleet uuid, p_route uuid, p_base numeric) returns jsonb language plpgsql as $b$
declare
  v_r      jsonb;
  v_player uuid;
begin
  update public.world_config set value = 'true'::jsonb
   where key in ('npc_traders_enabled', 'standing_routes_enabled', 'economy_closed', 'city_treasury_enabled') and value is distinct from 'true'::jsonb;
  update public.world_config set value = to_jsonb(p_base) where key = 'port_fee_base';
  update public.world_config set value = to_jsonb(0) where key = 'port_fee_pct';
  update public.standing_routes set fleet_id = p_fleet, lap_id = null, paused_reason = null, hold_until = null where id = p_route;
  select sr.player_id into v_player from public.standing_routes sr where sr.id = p_route;
  v_r := public.npc_plan(now(), p_route);
  return jsonb_build_object(
    'receipt', jsonb_build_object('planned', v_r->'planned', 'waiting', v_r->'waiting', 'ballast', v_r->'ballast', 'failed', v_r->'failed'),
    'paused', (select sr.paused_reason from public.standing_routes sr where sr.id = p_route),
    'wrote', (select md5(coalesce(string_agg(s.ord || ':' || s.port_id || ':' || s.repair || ':' ||
                       coalesce((select string_agg(l.ord || l.kind || coalesce(l.good_id::text, '') || coalesce(l.qty::text, '') || coalesce(l.price_limit::text, '') || l.at_profit, ','
                                                   order by l.ord)
                                   from public.standing_route_lines l where l.route_id = s.route_id and l.stop_ord = s.ord), ''), '|' order by s.ord), ''))
                from public.standing_route_stops s where s.route_id = p_route),
    'buys', (select count(*) from public.standing_route_lines l where l.route_id = p_route and l.kind = 'BUY'),
    'charging_stops', (select count(*) from public.standing_route_stops s where s.route_id = p_route and public.port_fee(s.port_id, v_player, 0) > 0));
end $b$
  $f$;
  -- the probe merchant: in port at her loop's first stop, nothing aboard, nothing queued, no lap open, not of the pirates (a pirate home's quay is free)
  select nf.fleet_id, nf.route_id into v_fleet, v_route
    from public.npc_fleets nf
    join public.players pl on pl.id = nf.player_id and not public.pirate_power(pl.nation_id)
    join public.fleets f on f.id = nf.fleet_id and f.status = 'DOCKED'
    join public.standing_routes sr on sr.id = nf.route_id and sr.lap_id is null and (sr.fleet_id is null or sr.fleet_id = nf.fleet_id)
    join public.standing_route_stops s on s.route_id = sr.id and s.ord = 0 and s.port_id = f.port_id
   where nf.roster_ord <= public.wc_int('npc_fleet_max')
     and not exists (select 1 from public.orders o where o.fleet_id = nf.fleet_id and o.status in ('pending', 'failed'))
     and not exists (select 1 from public.ships sh where sh.fleet_id = nf.fleet_id and public.ship_cargo_tuns(sh.id) > 0)
   order by (sr.paused_reason = 'laid_up') desc nulls last, nf.roster_ord
   limit 1;
  -- BEFORE THE CUT: her plan by the pre-image, the fee knobs at 0
  if v_fleet is not null then
    begin
      v_old := pg_temp.plan_0406(v_fleet, v_route, 0);
      raise exception sqlstate 'BV406';
    exception when sqlstate 'BV406' then null;
    end;
  end if;

  -- ── 3. THE HUNKS ──
  create temp table hunk_0406 (ord int primary key, fn text, old text, new text) on commit drop;
  insert into hunk_0406 values
  (1, c_cut[1],
$h$  v_wages   numeric;
  v_kept    int := 0;
$h$,
$h$  v_wages   numeric;
  v_cost    numeric := 0;   -- 0406: what the kept parcels cost her here (the buy quotes' totals)
  v_kept    int := 0;
$h$),
  (2, c_cut[1],
$h$      v_budget := v_budget - q_buy.total;   -- 0129
$h$,
$h$      v_budget := v_budget - q_buy.total;   -- 0129
      v_cost   := v_cost + q_buy.total;     -- 0406
$h$),
  (3, c_cut[1],
$h$  return jsonb_build_object('lines', v_lines, 'profit', v_profit, 'wages', v_wages,
                            'nm', v_nm, 'any', v_any);
$h$,
$h$  -- 0406: `cost` is what the kept parcels cost her at p_from: her cargo at cost when she makes p_to, the value public.npc_plan asks the dock fee for
  return jsonb_build_object('lines', v_lines, 'profit', v_profit, 'wages', v_wages,
                            'nm', v_nm, 'any', v_any, 'cost', v_cost);
$h$),
  (4, c_cut[2],
$h$  v_sea_d   numeric;     -- 0142: the loop's days at sea
$h$,
$h$  v_sea_d   numeric;     -- 0142: the loop's days at sea
  v_fees    numeric;     -- 0406: the dock fees a lap of the loop pays (public.port_fee at every harbour she makes)
$h$),
  (5, c_cut[2],
$h$        v_wages  := 0;       -- 0142
        v_rep    := false;   -- 0142
$h$,
$h$        v_wages  := 0;       -- 0142
        v_fees   := 0;       -- 0406
        v_rep    := false;   -- 0142
$h$),
  (6, c_cut[2],
$h$            v_leg  := public.npc_leg_lines(sr.id, v_from, v_to, v_hold, v_crew, v_speed);
            v_memo := v_memo || jsonb_build_object(v_key, v_leg);
$h$,
$h$            v_leg  := public.npc_leg_lines(sr.id, v_from, v_to, v_hold, v_crew, v_speed);
            -- 0406: THE DOCK FEE OF THIS LEG'S CALL, asked of THE one fee (public.port_fee, the function public.port_call charges her by):
            -- the harbour she makes, her company, her cargo at cost on arriving (the leg's `cost`). Asked once a leg and kept with it.
            v_leg  := v_leg || jsonb_build_object('fee', public.port_fee(v_to, sr.player_id, coalesce((v_leg->>'cost')::numeric, 0)));
            v_memo := v_memo || jsonb_build_object(v_key, v_leg);
$h$),
  (7, c_cut[2],
$h$          v_wages  := v_wages + coalesce((v_leg->>'wages')::numeric, 0);   -- 0142
$h$,
$h$          v_wages  := v_wages + coalesce((v_leg->>'wages')::numeric, 0);   -- 0142
          v_fees   := v_fees + coalesce((v_leg->>'fee')::numeric, 0);      -- 0406
$h$),
  (8, c_cut[2],
$h$        v_net   := v_profit - public.wages_from_profit(v_wages, v_profit)
                   - public.stores_cost(sr.player_id, v_crew * public.wc_num('water_per_crew_day') * v_sea_d,
                                        v_crew * public.wc_num('food_per_crew_day') * v_sea_d);
$h$,
$h$        -- 0406: LESS THE DOCK FEES THE LOOP PAYS (0237: every harbour she makes charges her, at home too). They never entered this net, so a
        -- loop whose margin was under its fees "paid", was sailed and emptied her purse. The score, the choice, "pays" and the lay-up read v_net.
        v_net   := v_profit - public.wages_from_profit(v_wages, v_profit)
                   - public.stores_cost(sr.player_id, v_crew * public.wc_num('water_per_crew_day') * v_sea_d,
                                        v_crew * public.wc_num('food_per_crew_day') * v_sea_d)
                   - v_fees;
$h$);
  for h in select * from hunk_0406 order by ord loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0406 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', h.ord, h.fn, v_n;
    end if;
    execute replace(v_def, h.old, h.new);
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    if (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new) <> 1 then
      raise exception '0406 self-assert FAIL: hunk % of % is not in the new body once', h.ord, h.fn;
    end if;
    if (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
          from pg_proc p where p.oid = h.fn::regprocedure) <> (select p.meta from pre_0406 p where p.fn = h.fn) then
      raise exception '0406 self-assert FAIL: the grants, volatility, definer, search path or owner of % moved', h.fn;
    end if;
  end loop;
  for h in select p.fn, p.def from pre_0406 p loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    for v_z in select x.old, x.new from hunk_0406 x where x.fn = h.fn order by x.ord desc loop
      v_def := replace(v_def, v_z.new, v_z.old);
    end loop;
    if v_def <> h.def then
      raise exception '0406 self-assert FAIL: % does not reverse to its pre-image', h.fn;
    end if;
  end loop;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and not exists (select 1 from unnest(c_cut) f where f::regprocedure = p.oid)) <> v_fn_before then
    raise exception '0406 self-assert FAIL: another function moved';
  end if;

  -- ── 4. THE PROBE, AFTER THE CUT ──
  if v_fleet is null then
    raise notice '0406 self-assert: no merchant lies in port at her first stop with an empty hold in this world; the probe is proof 101''s';
  else
    -- (a) the fee at nothing: her plan is the pre-image's, row for row
    begin
      v_new := pg_temp.plan_0406(v_fleet, v_route, 0);
      raise exception sqlstate 'BV406';
    exception when sqlstate 'BV406' then null;
    end;
    if v_new is distinct from v_old then
      raise exception '0406 self-assert FAIL: with the dock fee at 0 her plan is not the pre-image''s: before %, after %', v_old, v_new;
    end if;
    -- (b) a fee no trade can carry: she waits in port (0181), unless no stop of the loop written charges her at all
    begin
      v_big := pg_temp.plan_0406(v_fleet, v_route, 1000000000);
      raise exception sqlstate 'BV406';
    exception when sqlstate 'BV406' then null;
    end;
    if (v_big->'receipt'->>'planned')::int <> 1 or (v_big->'receipt'->>'failed')::int <> 0 then
      raise exception '0406 self-assert FAIL: under a fee of 1,000,000,000 a call her plan failed: %', v_big;
    end if;
    if (v_big->>'charging_stops')::int > 0
       and ((v_big->'receipt'->>'waiting')::int <> 1 or v_big->>'paused' is distinct from 'laid_up' or (v_big->>'buys')::int <> 0) then
      raise exception '0406 self-assert FAIL: under a fee of 1,000,000,000 a call she does not wait in port: %', v_big;
    end if;
  end if;
  if (select count(*) from pg_proc p where p.oid in (select f::regprocedure from unnest(c_cut) f)
         and position('0406' in pg_get_functiondef(p.oid)) > 0) <> 2 then
    raise exception '0406 self-assert FAIL: the two bodies are not this file''s';
  end if;
  if clock_timestamp() - v_t0 > interval '20 seconds' then
    raise exception '0406 self-assert FAIL: the file took % (budget 20 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0406 self-assert ok: A MERCHANT COUNTS THE PORT''S FEE BEFORE SHE SAILS. Eight hunks over two bodies, each once and reversing; grants and volatility unmoved; no other function moved. %; % ms.',
    case when v_fleet is null then 'No probe merchant in this world'
         else 'One merchant planned by the live planner: the fee at 0, her plan is the pre-image''s (' || (v_new->'receipt')::text || ', ' || (v_new->>'buys') || ' BUY lines); the fee at 1,000,000,000 a call, '
              || case when (v_big->>'charging_stops')::int > 0 then 'she waits in port' else 'no stop of her loop charges her (' || (v_big->'receipt')::text || ')' end end,
    round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
