-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- news: none (no coin moves differently: the sell face shows, before the press, the profit the sale already tells after it)
-- 0490 - A SALE SHOWS ITS PROFIT BEFORE THE PRESS  (no switch: a figure is told, the same sale)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-24: "when i sell, i want to see the price i bought, the price i will get, how much profit earn and such."
--   docs/design/simplify-2026-11-24.md, slice S2 `sell-shows-profit`; dev log docs/dev-log/2026-11-24-sell-shows-profit.md.
--
-- WHY: the sell face reads the sale's dry run (cmd.preview runs cmd.do_sell and rolls it back; src/domain/order/estimate.ts). That
--   result carries `basis`, `cost`, `profit` (0081), `tax` and `wages` (0122 / 0128) but NOT the dock fee or `trip_net`, so the face
--   cannot show THE ONE PROFIT (0474): the SOLD event's `trip_net` = profit - tax - wages - dock fee, the figure the arrival card and
--   Report print. A second profit worked out in the client is what 0474 ended; the server must say it.
-- WHAT (one body, cmd.do_sell, by four hunks; nothing else moves): the event's `trip_net` expression becomes one variable, v_trip, set
--   once where 0474 reads the wages and the dock fee; the SOLD event writes v_trip (the same value as before, to the unit); the returned
--   object also carries `dock_fee` (coalesce(v_call, 0), the event's) and `trip_net` (v_trip). So the dry run of a sale (the preview)
--   and the sale's own result say the figure its event then writes: one computation, told three times. `wages` was already returned
--   (pay_wages' payment = public.wages_due, 0474's rule, the event's `wages`).
-- LOCKS: CREATE OR REPLACE of one function. TIME: a few seconds (the catalog md5s). BUDGET: statement_timeout 30 s; fails above 20 s.
-- LOAD: no rows, no tables, no cron, no beat step. 0 new rows a minute.
-- ROLLBACK (forward): a migration reversing the four hunks below (OLD texts verbatim); the client reads the two keys as nullable.
-- SELF-ASSERT: each hunk once and reversing to its pre-image; no other function moved; cmd.do_sell's grants, volatility, definer, search
--   path and owner unmoved; no world_config row moved. THE PROBE (rolled back by a raised sentinel): a fresh company at Lisbon with five
--   units of a good Lisbon bids for (bought at half the bid), wages owed and a dock fee standing from her call: the preview's `trip_net`,
--   the sale's returned `trip_net` and its SOLD event's `trip_net` are one figure, = profit - tax - wages - dock fee, the dock fee the
--   call's. Proof 193 plays it on the closed economy with the profit tax lit and the purse: a scene with tax, wages and a dock fee.
-- VERSION: 0490 = prod head 0489 + 1.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_fn     constant text := 'cmd.do_sell(uuid,jsonb)';
  c_uid    constant uuid := '00000000-0490-4000-8000-000000000001';
  v_t0        timestamptz := clock_timestamp();
  x           record;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_fn_before text;
  v_meta      text;
  v_cfg_before text;
  v_lived     boolean := false;
  v_lis       uuid;
  v_pl        uuid;
  v_fl        uuid;
  v_g         record;
  v_pv        jsonb;
  v_r         jsonb;
  v_ev        jsonb;
  v_note      text := '';
begin
  perform set_config('statement_timeout', '30s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure(c_fn) is null or to_regprocedure('public.wages_due(uuid,bigint)') is null
     or not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'fleets' and column_name = 'call_fee') then
    raise exception '0490 refuses: the one profit (0474: public.wages_due, fleets.call_fee) is not in this world';
  end if;
  if position('v_trip' in pg_get_functiondef(c_fn::regprocedure)) > 0 then
    raise exception '0490 refuses: it has been applied once';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  v_pre := replace(pg_get_functiondef(c_fn::regprocedure), E'\r', '');
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> c_fn::regprocedure::oid;
  select md5(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text)
    into v_meta from pg_proc p where p.oid = c_fn::regprocedure::oid;
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
    into v_cfg_before from public.world_config c;

  -- ── 2. THE HUNKS (each OLD text once in the live body; each reverses) ──
  create temp table hunks_0490 (ord int primary key, old text, new text) on commit drop;
  insert into hunks_0490 values
  (1,
$h$  v_call    bigint;        -- 0474: the dock fee charged when she made this harbour (fleets.call_fee), taken by her first sale here
$h$,
$h$  v_call    bigint;        -- 0474: the dock fee charged when she made this harbour (fleets.call_fee), taken by her first sale here
  v_trip    bigint;        -- 0490: THE ONE PROFIT of the trip (0474's trip_net), worked out once: the event writes it, the result returns it
$h$),
  (2,
$h$  v_call := f.call_fee;
$h$,
$h$  v_call := f.call_fee;
  v_trip := v_profit - v_tax - v_due - coalesce(v_call, 0);   -- 0490: profit - tax - wages - dock fee (0474's trip_net, moved here)
$h$),
  (3,
$h$      'wages', v_due, 'dock_fee', coalesce(v_call, 0), 'trip_net', v_profit - v_tax - v_due - coalesce(v_call, 0),   -- 0474
$h$,
$h$      'wages', v_due, 'dock_fee', coalesce(v_call, 0), 'trip_net', v_trip,   -- 0474 (0490: v_trip)
$h$),
  (4,
$h$                            'tax', v_tax, 'wages', v_wages, 'net', q.total - v_tax - v_wages,
$h$,
$h$                            'tax', v_tax, 'wages', v_wages, 'net', q.total - v_tax - v_wages,
                            -- 0490: the event's dock fee and trip_net, so the dry run (cmd.preview) shows the profit before the press
                            'dock_fee', coalesce(v_call, 0), 'trip_net', v_trip,
$h$);

  v_def := v_pre;
  for x in select * from hunks_0490 order by ord loop
    v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
    if v_n <> 1 then
      raise exception '0490 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, c_fn, v_n;
    end if;
    v_def := replace(v_def, x.old, x.new);
  end loop;
  execute v_def;
  v_def := replace(pg_get_functiondef(c_fn::regprocedure), E'\r', '');
  for x in select * from hunks_0490 order by ord desc loop
    if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
      raise exception '0490 self-assert FAIL: hunk % of % is not in the new body once', x.ord, c_fn;
    end if;
    v_def := replace(v_def, x.new, x.old);
  end loop;
  if v_def <> v_pre then
    raise exception '0490 self-assert FAIL: % does not reverse to its pre-image', c_fn;
  end if;

  -- ── 3. SELF-ASSERT: the catalog, the knobs ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> c_fn::regprocedure::oid) <> v_fn_before then
    raise exception '0490 self-assert FAIL: another function moved';
  end if;
  if (select md5(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text)
        from pg_proc p where p.oid = c_fn::regprocedure::oid) <> v_meta then
    raise exception '0490 self-assert FAIL: the grants, volatility, definer, search path or owner of % moved', c_fn;
  end if;
  if has_function_privilege('anon', c_fn, 'execute') or has_function_privilege('authenticated', c_fn, 'execute') then
    raise exception '0490 self-assert FAIL: a client can call % directly', c_fn;
  end if;

  -- ── 4. THE PROBE, rolled back by a raised sentinel: the preview, the result and the event tell one trip_net ──
  begin
    select p.id into v_lis from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR';
    v_pl := public.new_house(c_uid, 'Casa do Lucro 0490', 'PRT');
    select f.id into v_fl from public.fleets f where f.player_id = v_pl limit 1;
    -- a good Lisbon bids for, five units, bought at half the bid (written straight, rolled back)
    select g.id, g.code, q.avg_price as bid into v_g
      from public.goods g cross join lateral world.quote(v_lis, g.id, 5, 'sell', null, v_fl) q
     where public.port_offers(v_lis, g.id) and q.units = 5 and q.avg_price > 50
     order by g.code limit 1;
    if v_g.id is null then
      raise exception '0490 self-assert FAIL: Lisbon bids for no good the probe can sell';
    end if;
    update public.ships set cargo = jsonb_build_object(v_g.code, 5), cargo_basis = jsonb_build_object(v_g.code, floor(v_g.bid / 2))
     where fleet_id = v_fl;
    -- her crew is owed 40, and her call left a dock fee of 25 standing (as public.port_call writes it)
    insert into public.fleet_wages (fleet_id, owed, visit_net, visit_paid) values (v_fl, 40, 0, 0)
      on conflict (fleet_id) do update set owed = 40, visit_net = 0, visit_paid = 0;
    update public.fleets set call_fee = 25 where id = v_fl;

    v_pv := cmd.preview(v_fl, 'SELL ' || v_g.code || ' 5', null::jsonb);
    if coalesce((v_pv ->> 'ok')::boolean, false) is not true or (select f.call_fee from public.fleets f where f.id = v_fl) is distinct from 25::bigint then
      raise exception '0490 self-assert FAIL: the preview % (or it moved the call fee)', v_pv;
    end if;
    v_r := cmd.do_sell(v_fl, jsonb_build_object('good', v_g.id, 'qty', 5));
    select e.payload into v_ev from public.events e where e.player_id = v_pl and e.kind = 'SOLD' order by e.created_at desc limit 1;
    if v_ev is null
       or (v_r ->> 'trip_net') is null
       or (v_pv -> 'estimate' ->> 'trip_net')::bigint is distinct from (v_r ->> 'trip_net')::bigint
       or (v_r ->> 'trip_net')::bigint is distinct from (v_ev ->> 'trip_net')::bigint
       or (v_r ->> 'trip_net')::bigint is distinct from (v_r ->> 'profit')::bigint - (v_r ->> 'tax')::bigint - (v_r ->> 'wages')::bigint - (v_r ->> 'dock_fee')::bigint
       or (v_pv -> 'estimate' ->> 'dock_fee')::bigint is distinct from 25::bigint
       or (v_r ->> 'dock_fee')::bigint is distinct from (v_ev ->> 'dock_fee')::bigint
       or (v_r ->> 'wages')::bigint is distinct from (v_ev ->> 'wages')::bigint
       or (v_r ->> 'wages')::bigint <= 0
       or (v_pv -> 'estimate' ->> 'wages')::bigint is distinct from (v_r ->> 'wages')::bigint
       or (v_pv -> 'estimate' ->> 'tax')::bigint is distinct from (v_r ->> 'tax')::bigint then
      raise exception '0490 self-assert FAIL: preview % / result % / event % do not tell one trip_net', v_pv -> 'estimate', v_r, v_ev;
    end if;
    v_note := format('%s x5: profit %s, tax %s, wages %s, dock fee %s -> trip_net %s (preview, result and event)',
      v_g.code, v_r ->> 'profit', v_r ->> 'tax', v_r ->> 'wages', v_r ->> 'dock_fee', v_r ->> 'trip_net');
    raise exception using errcode = 'ZX490', message = 'PROBE_ROLLBACK_0490';
  exception when sqlstate 'ZX490' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0490 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name = 'Casa do Lucro 0490' or p.auth_uid = c_uid) then
    raise exception '0490 self-assert FAIL: the probe left something behind';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c) <> v_cfg_before then
    raise exception '0490 self-assert FAIL: a world_config row moved';
  end if;

  if clock_timestamp() - v_t0 > interval '20 seconds' then
    raise exception '0490 self-assert FAIL: the file took % (budget 20 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0490 self-assert ok: A SALE SHOWS ITS PROFIT BEFORE THE PRESS. % hunks once each and reversing; grants and volatility unmoved; no other function or knob moved. Probe (rolled back): %. % ms.',
    (select count(*) from hunks_0490), v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
