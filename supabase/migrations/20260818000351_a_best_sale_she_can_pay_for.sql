-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0351 — A BEST SALE SHE CAN PAY FOR: world.best_sales names, for every good, the sale that pays best PER DAY among the sales her purse can buy. No table, no knob, no switch, no row, no job.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- WHY (docs/SUCCESS_PLAN.md, slice T5). world.best_sales (0348, re-cut by 0350) picked, for every good, the sale with the biggest TOTAL profit at the units her hold takes. Played by a new
-- company at Lisbon with 40,000 coins it names Matsumae, Hagatna and Salvador (weeks at sea, hours of real time), most cards cost more than her purse (the tray they open says "No money"),
-- the card shows no time and no cost, and the hop to Setubal that pays is never named.
-- WHAT. world.best_sales RE-CUT (3 hunks), and nothing else:
--   * THE UNITS ARE THE TRAY'S MAX. For a good bought where she lies, public.fleet_buy_capacity (the one authority behind the docked tray's Max: her hold, the city's stock, the day's cap and
--     her purse at the price she would really pay) is asked. Where her hold binds it the sale is priced as before (the units that fit beside each leg's stores). Where anything else binds it
--     (her purse, the stock, the day's cap) every sale is priced for THAT count: world.board_sell asked exactly as world.good_board asks it for an amount, so the card is still the board's row.
--     No second cap rule is written here.
--   * WITHIN HER PURSE. A sale is a candidate when she can pay to go: the buy, and her stores for the leg unless they may be owed (public.credit_on) — the trip tray's own "No money" test.
--   * THE ANSWER IS THE BEST PROFIT PER DAY among the candidates that gain (the row's own arrive_at is the time); with none that gains, the least loss (pays false: "No gain", as before).
--   * SERVED WITH IT: cost (what the buy costs), seconds (the real time to that sale, from the row's own arrive_at), short (sales are priced and none is within her purse), and far —
--     the candidate with the biggest total profit (what the card named before this file) when it is another city: {port, units, profit, days, cost, seconds}.
-- ONE AUTHORITY, STILL. world.good_board, world.board_sell, world.board_legs, world.good_mids, world.quote and public.fleet_buy_capacity are not edited (asserted: every other function is
-- byte for byte what it was), so the board and the tray's figures cannot move; a card's profit, units and cost are world.good_board(good, fleet, here, units)'s row for that city (asserted).
-- THE COST. One public.fleet_buy_capacity a good bought where she lies: one quote when her hold binds, and its walk down (a quote a step) when her purse does. Measured in
-- docs/dev-log/2026-11-11-near-sale.md. The 2.5 s budget is unmoved.
-- NOT TOUCHED: every table, knob, switch, job; every function but world.best_sales.
-- ROLLBACK (forward): a new migration reversing the 3 hunks (each OLD text is here verbatim). The client reads the new keys as optional.
-- SELF-ASSERT: the catalog, then a probe house of its own rolled-back rows. BUDGET: ONE DO block, statement_timeout 90 s, lock_timeout 5 s; it fails above 45 s.
-- news: none
-- VERSION: 0351 - prod head 0350 (2026-11-12).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0          timestamptz := clock_timestamp();
  v_def         text;
  v_n           int;
  v_fn_before   text;
  v_cfg_before  text;
  v_rel_before  text;
  v_job_before  text;
  h             record;
  rf            record;
  v_lived       boolean := false;
  v_pl          uuid;
  v_fl          uuid;
  v_home        uuid;
  v_hcode       text;
  v_near        uuid;
  v_g1          uuid;
  v_g1code      text;
  v_purse       numeric;
  v_credit      boolean;
  v_bad         text;
  v_cnt         int;
  v_rows        int;
  v_asked       int;
  v_hold        int;
  v_old         jsonb;
  v_new         jsonb;
  v_caps        jsonb;
  v_ms_old      numeric;
  v_ms_new      numeric;
  v_sum_old     numeric := 0;
  v_sum_new     numeric := 0;
  v_pairs       int := 0;
  v_k           int;
  r_b text; r_r text; r_c text; r_d text; r_e text;
  c_uid  constant uuid := '00000000-0351-4000-8000-000000000001';
  c_recut constant text[] := array['world.best_sales(uuid,uuid)'];
  c_keys constant text[] := array['good', 'basis', 'port', 'units', 'profit', 'days', 'pays', 'cost', 'seconds', 'short', 'far'];
begin
  perform set_config('statement_timeout', '90s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from unnest(c_recut || array['world.good_board(uuid,uuid,uuid,numeric)', 'world.board_sell(uuid,uuid,jsonb)', 'world.board_legs(uuid,jsonb)', 'world.good_mids(uuid)',
                                                   'public.fleet_buy_capacity(uuid,uuid)', 'public.credit_on(uuid)', 'cmd.assume_identity(uuid)']) f
              where to_regprocedure(f) is null) then
    raise exception '0351 refuses: 0350 (the read and its pieces), the tray''s Max (public.fleet_buy_capacity) or public.credit_on is not in this world';
  end if;
  if (select p.prosrc from pg_proc p where p.oid = 'world.best_sales(uuid,uuid)'::regprocedure) like '%fleet_buy_capacity%' then
    raise exception '0351 refuses: something of it is already in this world';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0351 (fn text primary key, def text, meta text) on commit drop;
  insert into pre_0351
  select f, replace(pg_get_functiondef(f::regprocedure), E'\r', ''),
         (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
            from pg_proc p where p.oid = f::regprocedure)
    from unnest(c_recut) f;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select f::regprocedure::oid from unnest(c_recut) f));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before from public.world_config c;
  select md5(string_agg(n.nspname || '.' || c.relname || ':' || c.relkind::text, ',' order by n.nspname, c.relname)) into v_rel_before
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and c.relkind in ('r', 'v', 'm', 'S', 'i', 'f', 'p');
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.command || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_job_before;
  end if;

  -- ── 2. THE HUNKS: world.best_sales asks the tray's Max, keeps the sales within her purse, and answers the best per day (each hunk once, and reversing) ──
  create temp table hunks_0351 (fn text, n int, old text, new text) on commit drop;
  insert into hunks_0351 values
('world.best_sales(uuid,uuid)', 1,
$h$-- port null: no city she can sail to is priced. pays: the profit is above nought. cut: the 2.5 s budget ran out; the goods after it are not answered.
$h$,
$h$-- port null: no city she can sail to is priced. pays: the profit is above nought. cut: the 2.5 s budget ran out; the goods after it are not answered.
-- 0351: A SALE SHE CAN PAY FOR, AND THE BEST PER DAY. {good, basis, port, units, profit, days, pays, cost, seconds, short, far}. The answer (port .. seconds) is now the sale with the best
-- profit per day among the sales WITHIN HER PURSE that gain (none gains: the least loss, pays false). units: for a good bought where she lies, the tray's own Max
-- (public.fleet_buy_capacity) when anything but her hold binds it — every sale then priced for that count, as world.good_board prices an asked amount; else as before. Within her purse:
-- the buy, and her stores for the leg unless they may be owed (public.credit_on), are no more than her coins. cost: what the buy costs. seconds: the real time to that sale (the row's own
-- arrive_at). short: sales are priced and none is within her purse. far: the sale within her purse with the biggest total profit (what was answered before 0351), when it is another city.
$h$),
('world.best_sales(uuid,uuid)', 2,
$h$  v_legs_own jsonb;                 -- 0350: world.board_legs for her cargo, asked once
$h$,
$h$  v_legs_own jsonb;                 -- 0350: world.board_legs for her cargo, asked once
  v_purse   numeric := (select p.ducats from public.players p where p.id = v_player);   -- 0351: her coins
  v_credit  boolean;                -- 0351: her stores for this sail may be owed (public.credit_on): they are not asked of her purse
  v_cap     jsonb;                  -- 0351: public.fleet_buy_capacity's answer — the docked tray's Max
  v_u       numeric;                -- 0351: that Max, when anything but her hold binds it
  v_buy     record;                 -- 0351: the buy of v_u here, as world.good_board quotes it
  v_far     jsonb;                  -- 0351: the sale within her purse with the biggest total profit
  v_short   boolean;                -- 0351: sales are priced, none within her purse
$h$),
('world.best_sales(uuid,uuid)', 3,
$h$    v_rows := world.board_sell(gd.id, p_fleet, v_ctx);
    v_best := (select e from jsonb_array_elements(v_rows) e
                where (e->>'sailable')::boolean and jsonb_typeof(e->'profit') = 'number' and e->>'port' is distinct from v_port.code
                order by (e->>'profit')::numeric desc, (e->>'days')::numeric nulls last, e->>'port'
                limit 1);
    v_out := v_out || jsonb_build_array(jsonb_build_object(
               'good', gd.code, 'basis', a.basis,
               'port', v_best->>'port', 'units', (v_best->>'units')::numeric, 'profit', (v_best->>'profit')::numeric,
               'days', (v_best->>'days')::numeric, 'pays', coalesce((v_best->>'profit')::numeric > 0, false)));
$h$,
$h$    -- 0351: THE UNITS ARE THE TRAY'S MAX. Bought where she lies: public.fleet_buy_capacity (her hold, the stock, the day's cap, her purse — the one cap authority) is asked.
    -- Her hold binds it: priced as before (FIT: the units that fit beside each leg's stores). Anything else binds it: every sale is priced for that count.
    v_u := null; v_cap := null;
    if a.basis <> 'on_board' and f.port_id is not distinct from p_port then
      v_cap := public.fleet_buy_capacity(p_fleet, gd.id);
      if v_cap->>'bound_by' is distinct from 'hold' then
        v_u := coalesce((v_cap->>'max_qty')::numeric, 0);
      end if;
    end if;
    v_short := v_u is not null and v_u <= 0 and v_cap->>'bound_by' = 'purse';   -- her purse buys not one
    if v_u is null then
      v_rows := world.board_sell(gd.id, p_fleet, v_ctx);
    elsif v_u <= 0 then
      v_rows := '[]'::jsonb;
    else
      -- the buy of that count here, and the sell rows for it, exactly as world.good_board(good, fleet, p_port, v_u) asks them (basis asked, no FIT)
      select q.units, q.total::numeric as total into v_buy from world.quote(p_port, gd.id, v_u, 'buy', null, p_fleet) q;
      v_rows := world.board_sell(gd.id, p_fleet, v_ctx || jsonb_build_object(
                  'units', v_u, 'basis', 'asked', 'fit', false,
                  'src', jsonb_build_object('code', v_port.code, 'units', v_buy.units, 'cost', v_buy.total)));
      -- a leg whose stores leave room for fewer than that count is priced for what fits beside them (FIT, as before): fewer units, so within her purse too
      if exists (select 1 from jsonb_array_elements(v_rows) e
                  where (e->>'sailable')::boolean and (e->'supplies'->>'units_fit')::numeric < v_u) then
        v_rows := (select coalesce(jsonb_agg(x.e), '[]'::jsonb)
                     from (select e from jsonb_array_elements(v_rows) e
                            where (e->'supplies'->>'units_fit')::numeric >= v_u
                           union all
                           select e from jsonb_array_elements(world.board_sell(gd.id, p_fleet, v_ctx)) e
                            where (e->'supplies'->>'units_fit')::numeric < v_u) x);
      end if;
    end if;
    -- 0351: WITHIN HER PURSE, THE BEST PER DAY. The candidates: the rows she can sail to, priced, not p_port, loaded with no more than fits, and paid for with the coins she has —
    -- the buy, and her stores unless they may be owed where she takes them on (public.credit_on). The answer: the best profit per day of those that gain (the row's own arrive_at is
    -- the time), else the least loss. far: the biggest total profit (the pick before 0351), served when it is another city.
    v_credit := public.credit_on(case when a.basis = 'on_board' then v_origin else p_port end);
    with pool as materialized (
      select e, (e->>'profit')::numeric as profit,
             greatest(extract(epoch from ((e->>'arrive_at')::timestamptz - now())), 1) as secs,
             (case when a.basis <> 'on_board' then coalesce((e->>'cost')::numeric, 0) else 0 end
              + case when v_credit then 0 else coalesce((e->'supplies'->>'cost')::numeric, 0) end) <= v_purse as afford
        from jsonb_array_elements(v_rows) e
       where (e->>'sailable')::boolean and jsonb_typeof(e->'profit') = 'number' and e->>'port' is distinct from v_port.code
         and (a.basis = 'on_board' or (e->>'units')::numeric <= (e->'supplies'->>'units_fit')::numeric)
    ), c as (
      select * from pool where afford
    )
    select (select c.e from c
             order by (c.profit > 0) desc, case when c.profit > 0 then c.profit / c.secs end desc nulls last,
                      c.profit desc, (c.e->>'days')::numeric nulls last, c.e->>'port'
             limit 1),
           (select c.e from c order by c.profit desc, (c.e->>'days')::numeric nulls last, c.e->>'port' limit 1),
           v_short or (exists (select 1 from pool) and not exists (select 1 from c))
      into v_best, v_far, v_short;
    v_out := v_out || jsonb_build_array(jsonb_build_object(
               'good', gd.code, 'basis', a.basis,
               'port', v_best->>'port', 'units', (v_best->>'units')::numeric, 'profit', (v_best->>'profit')::numeric,
               'days', (v_best->>'days')::numeric, 'pays', coalesce((v_best->>'profit')::numeric > 0, false),
               'cost', (v_best->>'cost')::numeric,
               'seconds', round(extract(epoch from ((v_best->>'arrive_at')::timestamptz - now()))),
               'short', v_short and v_best is null,
               'far', case when v_far->>'port' is distinct from v_best->>'port' then jsonb_build_object(
                        'port', v_far->>'port', 'units', (v_far->>'units')::numeric, 'profit', (v_far->>'profit')::numeric,
                        'days', (v_far->>'days')::numeric, 'cost', (v_far->>'cost')::numeric,
                        'seconds', round(extract(epoch from ((v_far->>'arrive_at')::timestamptz - now())))) end));
$h$);

  for rf in select * from pre_0351 order by 1 loop
    v_def := rf.def;
    for h in select * from hunks_0351 x where x.fn = rf.fn order by n loop
      v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
      if v_n <> 1 then
        raise exception '0351 self-assert FAIL: % hunk % occurs % time(s), not once: the deployed body is not what this file was written against', rf.fn, h.n, v_n;
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(rf.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0351 x where x.fn = rf.fn order by n desc loop
      if (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new) <> 1 then
        raise exception '0351 self-assert FAIL: % new hunk % is not in the live body once', rf.fn, h.n;
      end if;
      v_def := replace(v_def, h.new, h.old);
    end loop;
    if v_def <> rf.def then
      raise exception '0351 self-assert FAIL: % does not reverse to its pre-image', rf.fn;
    end if;
    if (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
          from pg_proc p where p.oid = rf.fn::regprocedure) <> rf.meta then
      raise exception '0351 self-assert FAIL: % changed its ACL, volatility, definer, config or owner', rf.fn;
    end if;
  end loop;
  if (select count(*) from hunks_0351) <> 3 or (select count(distinct x.fn) from hunks_0351 x join pre_0351 p on p.fn = x.fn) <> 1 then
    raise exception '0351 self-assert FAIL: the hunks are not the 3 of the one re-cut body';
  end if;

  -- ── 3. THE SELF-ASSERT: the catalog ──
  -- every other function is byte for byte what it was: world.good_board (the tray's figures), world.board_sell, world.quote and public.fleet_buy_capacity (the tray's Max) among them
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select f::regprocedure::oid from unnest(c_recut) f))) <> v_fn_before then
    raise exception '0351 self-assert FAIL: another function moved (world.good_board, world.board_sell, world.quote and public.fleet_buy_capacity among them must not)';
  end if;
  v_def := (select p.prosrc from pg_proc p where p.oid = 'world.best_sales(uuid,uuid)'::regprocedure);
  -- ONE cap authority, asked once a good; no walk, no step and no knob of its own here; the budget and 0350's legs unmoved
  if (length(v_def) - length(replace(v_def, 'public.fleet_buy_capacity(', ''))) / length('public.fleet_buy_capacity(') <> 1
     or v_def like '%trade_step_tuns%' or v_def like '%wc_num(%' or v_def like '%while %'
     or v_def not like '%interval ''2.5 seconds''%'
     or (length(v_def) - length(replace(v_def, 'world.board_legs(p_fleet, v_ctx)', ''))) / length('world.board_legs(p_fleet, v_ctx)') <> 2 then
    raise exception '0351 self-assert FAIL: world.best_sales does not ask the tray''s Max exactly once, or carries a cap rule of its own, or its budget or its legs moved';
  end if;
  if not has_function_privilege('authenticated', 'world.best_sales(uuid,uuid)', 'execute') or has_function_privilege('anon', 'world.best_sales(uuid,uuid)', 'execute')
     or (select p.provolatile from pg_proc p where p.oid = 'world.best_sales(uuid,uuid)'::regprocedure) <> 's' then
    raise exception '0351 self-assert FAIL: the read lost its grant or is no longer STABLE';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) from public.world_config c) <> v_cfg_before then
    raise exception '0351 self-assert FAIL: a world_config row moved: this file sets no knob';
  end if;
  if (select md5(string_agg(n.nspname || '.' || c.relname || ':' || c.relkind::text, ',' order by n.nspname, c.relname))
        from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and c.relkind in ('r', 'v', 'm', 'S', 'i', 'f', 'p')) <> v_rel_before then
    raise exception '0351 self-assert FAIL: a table, view, sequence or index appeared or went: this file makes none';
  end if;
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.command || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_def;
    if v_def is distinct from v_job_before then
      raise exception '0351 self-assert FAIL: a cron job moved: this file schedules nothing';
    end if;
  end if;

  -- ── 4. THE SELF-ASSERT: a probe house of its own rows (a new company, docked, with a new company's purse), every one rolled back. Only the probe's own answers are asserted. ──
  begin
    -- the answer BEFORE this file, kept as a pg_temp copy of the pre-image (rolled back with the probe)
    execute replace((select def from pre_0351 where fn = 'world.best_sales(uuid,uuid)'), 'FUNCTION world.best_sales(', 'FUNCTION pg_temp.best_sales_old_0351(');

    v_pl := public.new_house(c_uid, 'Probe 0351', 'PRT');
    select id, port_id into v_fl, v_home from public.fleets where player_id = v_pl;
    v_hcode := (select code from public.ports where id = v_home);
    if v_home is null then
      raise exception '0351 self-assert FAIL: the probe company lies at no harbour';
    end if;
    perform cmd.assume_identity(c_uid);
    v_purse := (select p.ducats from public.players p where p.id = v_pl);
    v_credit := public.credit_on(v_home);
    select g.id, g.code into v_g1, v_g1code
      from public.port_goods pg join public.goods g on g.id = pg.good_id
     where pg.port_id = v_home and pg.stock >= 50 and public.port_offers(v_home, g.id)
     order by g.code limit 1;
    select p.id into v_near
      from public.ports p, public.ports hb
     where hb.id = v_home and p.kind = 'HARBOUR' and p.id <> v_home
       and exists (select 1 from public.port_goods pg where pg.port_id = p.id and public.port_offers(p.id, pg.good_id))
     order by voyage.gc_distance_nm(hb.lat, hb.lon, p.lat, p.lon), p.code limit 1;
    if v_g1 is null or v_near is null or v_purse is null then
      raise exception '0351 self-assert FAIL: the probe found no good at %, no harbour near it, or has no purse', v_hcode;
    end if;

    -- (b) WHERE SHE LIES: old then new in ONE statement (one snapshot), each timed, with the tray's Max for every good. A cut answer (the 2.5 s budget, on a busy world) is judged
    -- over the goods it answered.
    with t0 as materialized (select clock_timestamp() as c),
         o  as materialized (select pg_temp.best_sales_old_0351(v_fl, v_home) as b from t0),
         t1 as materialized (select clock_timestamp() as c, o.b from o),
         n  as materialized (select world.best_sales(v_fl, v_home) as b, t1.c, t1.b as ob from t1),
         t2 as materialized (select clock_timestamp() as c2, n.c as c1, n.b, n.ob from n)
    select t2.ob, t2.b, extract(epoch from t2.c1 - t0.c) * 1000, extract(epoch from t2.c2 - t2.c1) * 1000,
           (select jsonb_object_agg(g.code, public.fleet_buy_capacity(v_fl, g.id))
              from public.port_goods pg join public.goods g on g.id = pg.good_id
             where pg.port_id = v_home and public.port_offers(v_home, g.id))
      into v_old, v_new, v_ms_old, v_ms_new, v_caps from t2 cross join t0;
    v_k := least(jsonb_array_length(v_old->'goods'), jsonb_array_length(v_new->'goods'));
    if v_k = 0 or v_old->'port' is distinct from v_new->'port' or v_old->'clock' is distinct from v_new->'clock' then
      raise exception '0351 self-assert FAIL: best_sales at % answered no good, or another port or clock: old % new %', v_hcode, v_old, v_new;
    end if;
    if not (v_new->>'cut')::boolean and jsonb_array_length(v_new->'goods') <> (select count(*) from public.port_goods pg where pg.port_id = v_home and public.port_offers(v_home, pg.good_id)) then
      raise exception '0351 self-assert FAIL: positive control — best_sales at % answered % good(s)', v_hcode, jsonb_array_length(v_new->'goods');
    end if;
    -- the shape, and what every card must be: within her purse, its far choice dearer and no nearer, short only with no sale
    select string_agg(format('%s: %s', e->>'good', e), '; ')
      into v_bad
      from jsonb_array_elements(v_new->'goods') e
     where not (e ?& c_keys)
        or (e->>'port' is not null and ((e->>'cost')::numeric > v_purse or (e->>'cost') is null or (e->>'seconds')::numeric < 1 or (e->>'units')::numeric < 1
                                        or (e->>'pays')::boolean is distinct from ((e->>'profit')::numeric > 0) or (e->>'short')::boolean))
        or (e->>'port' is null and (jsonb_typeof(e->'far') <> 'null' or (e->>'pays')::boolean))
        or e->>'port' = v_hcode
        or (jsonb_typeof(e->'far') = 'object' and (e->'far'->>'port' = e->>'port' or e->'far'->>'port' = v_hcode or (e->'far'->>'cost')::numeric > v_purse
                                                  or (e->'far'->>'profit')::numeric < (e->>'profit')::numeric
                                                  or ((e->>'pays')::boolean and (e->'far'->>'seconds')::numeric < (e->>'seconds')::numeric)))
        -- the tray's Max is the most a card asks her to buy
        or (e->>'port' is not null and (e->>'units')::numeric > (v_caps->(e->>'good')->>'max_qty')::numeric)
        or (jsonb_typeof(e->'far') = 'object' and (e->'far'->>'units')::numeric > (v_caps->(e->>'good')->>'max_qty')::numeric);
    if v_bad is not null then
      raise exception '0351 self-assert FAIL: a card at % is not a sale she can pay for (purse %): %', v_hcode, v_purse, v_bad;
    end if;
    -- HER HOLD BINDS THE MAX: nothing of the pricing changed, so the dearest sale within her purse is the answer before this file, to the coin — unless that one is past her purse
    select count(*), string_agg(format('%s: before %s x %s at %s, now %s', o.e->>'good', o.e->>'profit', o.e->>'units', o.e->>'port', n.e), '; ')
             filter (where (o.e->>'port' is distinct from coalesce(n.e->'far'->>'port', n.e->>'port')
                            or (o.e->>'profit')::numeric is distinct from coalesce((n.e->'far'->>'profit')::numeric, (n.e->>'profit')::numeric)
                            or (o.e->>'units')::numeric is distinct from coalesce((n.e->'far'->>'units')::numeric, (n.e->>'units')::numeric))
                       -- past her purse (her stores are not on credit here and tip it over): then it must not be a candidate, and the board says so
                       and not exists (select 1 from jsonb_array_elements(world.good_board((select g.id from public.goods g where g.code = o.e->>'good'), v_fl, v_home,
                                                                                           (o.e->>'units')::numeric)->'sell') s
                                        where s->>'port' = o.e->>'port'
                                          and (s->>'cost')::numeric + case when v_credit then 0 else coalesce((s->'supplies'->>'cost')::numeric, 0) end > v_purse))
      into v_hold, v_bad
      from generate_series(0, v_k - 1) i
     cross join lateral (select v_old->'goods'->i as e) o
     cross join lateral (select v_new->'goods'->i as e) n
     where v_caps->(o.e->>'good')->>'bound_by' = 'hold' and o.e->>'basis' <> 'on_board' and o.e->>'port' is not null;
    if v_bad is not null then
      raise exception '0351 self-assert FAIL: where her hold binds the Max, the dearest sale is not the answer before this file: %', v_bad;
    end if;
    -- positive control: a new company's purse binds at least one good where she lies, and that card is the tray's Max of it
    select count(*) into v_asked
      from jsonb_array_elements(v_new->'goods') e
     where v_caps->(e->>'good')->>'bound_by' = 'purse' and e->>'port' is not null
       and (e->>'units')::numeric = (v_caps->(e->>'good')->>'max_qty')::numeric;
    if v_asked = 0 and not (v_new->>'cut')::boolean then
      raise exception '0351 self-assert FAIL: positive control — the probe''s purse (%) binds no good at % to a sale (caps %, answer %)', v_purse, v_hcode, v_caps, v_new->'goods';
    end if;
    if not (v_old->>'cut')::boolean and not (v_new->>'cut')::boolean then
      v_sum_old := v_sum_old + v_ms_old; v_sum_new := v_sum_new + v_ms_new; v_pairs := v_pairs + 1;
    end if;
    r_b := format('best_sales at %s, purse %s: %s goods answered (%s before); %s where her hold binds = the dearest before; %s priced at the Max her purse binds; %s short; old %s ms, new %s ms',
                  v_hcode, v_purse, jsonb_array_length(v_new->'goods'), jsonb_array_length(v_old->'goods'), v_hold, v_asked,
                  (select count(*) from jsonb_array_elements(v_new->'goods') e where (e->>'short')::boolean), round(v_ms_old), round(v_ms_new));

    -- (r) THE LAW 0348 ASSERTED, KEPT, AND THE RULE: a card's profit, units and cost are world.good_board(good, fleet, here, units)'s row for that city, to the coin; and on that same board
    -- (the cards priced at a Max her hold does not bind: every row there is at the card's units) no sale within her purse has a better profit per day than the card's, and none a
    -- bigger profit than its far choice. 3 cards, the ones her purse binds first; ONE statement.
    with bs as materialized (select world.best_sales(v_fl, v_home) as b),
         cards as materialized (
           select x.e, x.i, g.id as gid, public.fleet_buy_capacity(v_fl, g.id) as cap
             from bs cross join lateral jsonb_array_elements(bs.b->'goods') with ordinality x(e, i)
             join public.goods g on g.code = x.e->>'good'
            where x.e->>'port' is not null and x.e->>'basis' <> 'on_board'),
         pick as materialized (select * from cards c order by (c.cap->>'bound_by' = 'purse') desc, (c.cap->>'bound_by' <> 'hold') desc, c.i limit 3),
         gb as materialized (select p.*, world.good_board(p.gid, v_fl, v_home, (p.e->>'units')::numeric) as gb from pick p),
         chk as materialized (
           select g.e, g.cap,
                  g.cap->>'bound_by' <> 'hold' and (g.e->>'units')::numeric = (g.cap->>'max_qty')::numeric as asked,
                  (select s from jsonb_array_elements(g.gb->'sell') s where s->>'port' = g.e->>'port') as nr,
                  (select s from jsonb_array_elements(g.gb->'sell') s where s->>'port' = g.e->'far'->>'port') as fr,
                  (select coalesce(jsonb_agg(jsonb_build_object('port', s->>'port', 'profit', (s->>'profit')::numeric,
                                               'secs', greatest(extract(epoch from ((s->>'arrive_at')::timestamptz - now())), 1))), '[]'::jsonb)
                     from jsonb_array_elements(g.gb->'sell') s
                    where (s->>'quoted')::boolean and (s->>'sailable')::boolean and jsonb_typeof(s->'profit') = 'number' and s->>'port' <> v_hcode
                      and (s->>'units')::numeric <= (s->'supplies'->>'units_fit')::numeric
                      and (s->>'cost')::numeric + case when v_credit then 0 else coalesce((s->'supplies'->>'cost')::numeric, 0) end <= v_purse) as pool
             from gb g)
    select count(*), count(*) filter (where c.asked),
           string_agg(format('%s at %s: card %s x %s cost %s far %s; board %s x %s cost %s; pool %s', c.e->>'good', c.e->>'port', c.e->>'profit', c.e->>'units', c.e->>'cost',
                             c.e->'far', c.nr->>'profit', c.nr->>'units', c.nr->>'cost', c.pool), '; ')
             filter (where c.nr is null or (c.nr->>'profit')::numeric is distinct from (c.e->>'profit')::numeric or (c.nr->>'units')::numeric is distinct from (c.e->>'units')::numeric
                        or (c.nr->>'cost')::numeric is distinct from (c.e->>'cost')::numeric or (c.nr->>'sailable')::boolean is not true
                        or round(extract(epoch from ((c.nr->>'arrive_at')::timestamptz - now()))) is distinct from (c.e->>'seconds')::numeric
                        -- its far choice, when it is priced at the same units, is the board's row too
                        or (jsonb_typeof(c.e->'far') = 'object' and (c.e->'far'->>'units')::numeric = (c.e->>'units')::numeric
                            and (c.fr is null or (c.fr->>'profit')::numeric is distinct from (c.e->'far'->>'profit')::numeric
                                 or (c.fr->>'cost')::numeric is distinct from (c.e->'far'->>'cost')::numeric))
                        -- THE RULE, on the board at the card's units
                        or (c.asked and exists (select 1 from jsonb_array_elements(c.pool) s
                                                 where (s->>'profit')::numeric > coalesce((c.e->'far'->>'profit')::numeric, (c.e->>'profit')::numeric)
                                                    or ((c.e->>'pays')::boolean and (s->>'profit')::numeric > 0
                                                        and (s->>'profit')::numeric / (s->>'secs')::numeric
                                                            > (c.e->>'profit')::numeric / greatest(extract(epoch from ((c.nr->>'arrive_at')::timestamptz - now())), 1))
                                                    or (not (c.e->>'pays')::boolean and (s->>'profit')::numeric > 0)))
                        or (c.asked and jsonb_array_length(c.pool) = 0))
      into v_rows, v_asked, v_bad
      from chk c;
    if v_bad is not null or v_rows = 0 then
      raise exception '0351 self-assert FAIL: a card is not the board''s figure, or not the best per day within her purse (% cards): %', v_rows, v_bad;
    end if;
    r_r := format('%s cards at %s: each is good_board''s row to the coin (profit, units, cost, seconds); %s of them at a Max her hold does not bind: none within her purse beats its profit per day, none its far choice''s profit',
                  v_rows, v_hcode, v_asked);

    -- (c) ANOTHER CITY IN HAND (bought there, not where she lies: no tray Max there, the units stay what her hold takes): NEW FIRST, then old, in one statement. The candidates are the
    -- old ones within her purse, so the dearest now is never above the answer before, and is that answer to the coin where it names the same city.
    with t0 as materialized (select clock_timestamp() as c),
         n  as materialized (select world.best_sales(v_fl, v_near) as b from t0),
         t1 as materialized (select clock_timestamp() as c, n.b from n),
         o  as materialized (select pg_temp.best_sales_old_0351(v_fl, v_near) as b, t1.c, t1.b as nb from t1),
         t2 as materialized (select clock_timestamp() as c2, o.c as c1, o.b, o.nb from o)
    select t2.b, t2.nb, extract(epoch from t2.c2 - t2.c1) * 1000, extract(epoch from t2.c1 - t0.c) * 1000
      into v_old, v_new, v_ms_old, v_ms_new from t2 cross join t0;
    v_k := least(jsonb_array_length(v_old->'goods'), jsonb_array_length(v_new->'goods'));
    select string_agg(format('%s: before %s, now %s', o.e->>'good', o.e, n.e), '; ')
      into v_bad
      from generate_series(0, v_k - 1) i
     cross join lateral (select v_old->'goods'->i as e) o
     cross join lateral (select v_new->'goods'->i as e) n
     where o.e->>'good' is distinct from n.e->>'good' or o.e->>'basis' is distinct from n.e->>'basis' or not (n.e ?& c_keys)
        or (n.e->>'port' is not null and (o.e->>'port' is null or (n.e->>'cost')::numeric > v_purse
                                          or coalesce((n.e->'far'->>'profit')::numeric, (n.e->>'profit')::numeric) > (o.e->>'profit')::numeric))
        or (o.e->>'port' is not null and o.e->>'port' = coalesce(n.e->'far'->>'port', n.e->>'port')
            and ((o.e->>'profit')::numeric is distinct from coalesce((n.e->'far'->>'profit')::numeric, (n.e->>'profit')::numeric)
                 or (o.e->>'units')::numeric is distinct from coalesce((n.e->'far'->>'units')::numeric, (n.e->>'units')::numeric)))
        or (o.e->>'port' is not null and n.e->>'port' is null and not (n.e->>'short')::boolean);
    if v_k = 0 or v_old->'port' is distinct from v_new->'port' or v_bad is not null then
      raise exception '0351 self-assert FAIL: from another city, a card is not one of the sales before this file within her purse: %', coalesce(v_bad, format('old %s new %s', v_old, v_new));
    end if;
    if not (v_old->>'cut')::boolean and not (v_new->>'cut')::boolean then
      v_sum_old := v_sum_old + v_ms_old; v_sum_new := v_sum_new + v_ms_new; v_pairs := v_pairs + 1;
    end if;
    r_c := format('best_sales at %s (not where she lies): %s goods, each one of the sales before within her purse (%s with a sale, %s short); old %s ms, new %s ms', v_new->>'port', v_k,
                  (select count(*) from jsonb_array_elements(v_new->'goods') e where e->>'port' is not null),
                  (select count(*) from jsonb_array_elements(v_new->'goods') e where (e->>'short')::boolean), round(v_ms_old), round(v_ms_new));

    -- (d) HER CARGO: 10 of a good bought. Its card reads her cargo, and is world.good_board(good, fleet)'s row to the coin (ONE statement)
    perform cmd.do_buy(v_fl, jsonb_build_object('good', v_g1, 'qty', 10));
    if coalesce(public.fleet_cargo_qty(v_fl, v_g1code), 0) <> 10 then
      raise exception '0351 self-assert FAIL: the probe did not load 10 %', v_g1code;
    end if;
    with bs as materialized (select world.best_sales(v_fl, v_home) as b),
         mine as (select e from bs, jsonb_array_elements(bs.b->'goods') e where e->>'good' = v_g1code)
    select (select b from bs),
           (select case when m.e->>'basis' <> 'on_board' then 'the card does not read her cargo: ' || m.e::text
                        when m.e->>'port' is not null
                             and not exists (select 1 from jsonb_array_elements(world.good_board(v_g1, v_fl, null, null)->'sell') s
                                              where s->>'port' = m.e->>'port' and (s->>'profit')::numeric = (m.e->>'profit')::numeric and (s->>'sailable')::boolean)
                        then 'her cargo''s card is not the board''s row: ' || m.e::text end
              from mine m)
      into v_new, v_bad;
    if v_bad is not null or (not (v_new->>'cut')::boolean and not exists (select 1 from jsonb_array_elements(v_new->'goods') e where e->>'good' = v_g1code)) then
      raise exception '0351 self-assert FAIL: her cargo: %', coalesce(v_bad, 'no card for ' || v_g1code);
    end if;
    r_d := format('%s aboard: its card reads her cargo and is good_board''s row', v_g1code);

    -- (e) THE TIME: a bound that is safe on a busy world. Over the pairs neither of which was cut, the new read may not take more than three times the old (it measures about 1.3 for a
    -- purse-bound company where she lies: the tray's Max walks her purse down a quote a step; the same from another city)
    if v_pairs > 0 and v_sum_new > v_sum_old * 3 then
      raise exception '0351 self-assert FAIL: best_sales is far slower than before: new % ms against old % ms over % pair(s)', round(v_sum_new), round(v_sum_old), v_pairs;
    end if;
    r_e := format('%s pair(s) uncut: old %s ms, new %s ms (%s %%)', v_pairs, round(v_sum_old), round(v_sum_new),
                  case when v_sum_old > 0 then round(100 * v_sum_new / v_sum_old) end);

    raise exception using errcode = 'ZX351', message = 'PROBE_ROLLBACK_0351';
  exception when sqlstate 'ZX351' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0351 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.auth_uid = c_uid) then
    raise exception '0351 self-assert FAIL: the probe left rows behind';
  end if;
  if public.current_player_id() is not null then
    raise exception '0351 self-assert FAIL: the probe''s identity outlived its rollback';
  end if;
  if to_regprocedure('pg_temp.best_sales_old_0351(uuid,uuid)') is not null then
    raise exception '0351 self-assert FAIL: a copy of the pre-image outlived the probe';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0351 self-assert FAIL: the file ran % s, over its 45 s budget', round(extract(epoch from clock_timestamp() - v_t0));
  end if;
  raise notice '0351 probe (b): %', r_b;
  raise notice '0351 probe (r): %', r_r;
  raise notice '0351 probe (c): %', r_c;
  raise notice '0351 probe (d): %', r_d;
  raise notice '0351 probe (e): %', r_e;
  raise notice '0351 self-assert ok: A BEST SALE SHE CAN PAY FOR. world.best_sales asks the tray''s Max (public.fleet_buy_capacity) for a good bought where she lies, keeps the sales within her purse, and answers the best profit per day with its cost and real seconds, and the dearest as far. Each card is still world.good_board''s row; no other function, knob, table, row or job moved. % ms.',
    round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
