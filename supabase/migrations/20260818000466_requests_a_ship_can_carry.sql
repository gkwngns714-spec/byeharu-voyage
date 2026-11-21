-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0466 - REQUESTS A SHIP CAN CARRY  (dark: the owner's switch hold_requests_enabled, false; lit, each harbour also posts up to two
--        hold-sized jobs, a load a starter hull carries, with a deadline of hours and one total, beside its city-sized requests)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-22: "make this game a proper game". THE DESIGN: docs/design/content-plan-2026-11.md 5.2/5.3 item 4 (5.6 default: beside
--   the city-sized requests, not instead), docs/design/playable-2026-11-22.md P1. The measurements and the pay rule: docs/dev-log/2026-11-22-ship-requests.md.
--
-- WHY NO COMPANY HAS DELIVERED A REQUEST (prod, the content plan 2.4): 751 open requests at 252 harbours, 31,367 units on average, sized by the
--   city's budget (0311); a new ship carries 180 to 300 t. None was ever delivered by a company.
--
-- WHAT THIS FILE DOES (one column, twelve knobs, one new function, nine hunks in five bodies, each once and reversing):
--   S1. public.trade_contracts.size: 'city' (every row today, and every row the city's draw posts) or 'hold' (this file's). A constant default:
--       no rewrite. The unique key (port, posted day, seq) is shared: a hold job takes seq 101 and up, the city's own 1 to contract_open_max.
--   S2. THE ONE WRITER of a hold-sized job: public.hold_request_post(port, now). Dark (hold_requests_enabled false): returns 0, reads nothing else.
--       Lit, under hold_request_open_max open hold jobs at a harbour, it posts ONE, drawn pure in (port, game day, seq) like the city's draw:
--         THE GOOD: one the harbour does not sell (0087's rule), its culture takes, some other harbour sells (so the job can be filled), and not
--           already asked for there; its daily allowance at the harbour covers the lot, so a delivery is never cut by E_DAILY_CAP.
--         THE LOT: a weight drawn in hold_request_tons_min..max (40-150 t: room to spare in a 180 t hull), in units of the good's bulk, at most
--           hold_request_units_max (250) and at most hold_request_value_max (24,000 d., the lot at its mid: under a new company's 40,000);
--           under hold_request_units_min (10) it posts nothing.
--         THE PAY (the rule, dev-log): the bonus is hold_request_premium_pct_min..max (20-30 %) of the mid at posting, a unit, fixed, on top of
--           the live sale price, as the city's bonus (0311) is 8-20 %. The budget is the bonus on the whole lot and nothing more.
--         THE DEADLINE: hold_request_hours_min..max (2-6) real hours, in whole game days (at least one).
--         THE PURSE: lit purses, the budget leaves the city at posting (BOUNTY, 0122's escrow) and must be under its share,
--           city_surplus / (bounty_reserve_mult x hold_request_open_max); dark purses, nothing is escrowed (0311's dark rule).
--       A delivery, its bonus, its Reputation and its Requests experience, expiry and the money going home are the existing request's,
--       untouched: cmd.preview_fulfil / cmd.fulfil / cmd.run_fulfil, public.contracts_expire.
--   S3. THE HUNKS:
--       H1 public.tick_contracts: the city's cap counts the city's rows only (size 'city').
--       H2-H5 public.tick_contract_wind: the city's top-up counts the city's rows only; a step (C), lit only, tops the harbours' hold boards up,
--         at most hold_request_wind_posts a minute, the fewest first, in an order that turns each minute, inside the job's own contract_wind_ms;
--         its receipt says how many it posted ('hold').
--       H6-H7 world.contracts: the read winds the hold board too (dark: nothing), and serves `size` and, for a hold job, `total`: the units
--         left x (today's bid + the bonus), the one figure the client prints.
--       H8 public.contract_asks: merchants never answer a hold job: it is the companies' (a deadline of hours is under contract_npc_after_hours anyway).
--       H9 public.contracts_expire: a hold job is pruned one real day after its deadline (the city's rows keep contract_deadline_days).
-- NOT CHANGED: the city-sized requests (their draw, budget, cap, deadline, merchants), the delivery, the sale, the Reputation and the levels.
-- ROWS: none while dark. Lit: about 254 harbours x 2 jobs over a 4 h mean life: about 2 posts a minute, each a trade_contracts row and a
--   treasury_flows row (BOUNTY), and as many expiries or deliveries (an UPDATE, a BOUNTY_LAPSED flow, a delete a day later); the first fill
--   runs at hold_request_wind_posts (3) a minute for about 3 hours. About +6 new rows a minute in all (2 jobs, 2 BOUNTY, 2 BOUNTY_LAPSED).
--   -- budget: none (no table, no job, no index, no cron; one column with a constant default on a table of about 1,600 rows).
--   -- retention: a hold job's row is deleted one real day after its deadline by public.contracts_expire (H9): about 4,000 rows standing lit.
-- LOCKS: ALTER TABLE trade_contracts (ADD COLUMN with a constant default and a CHECK: a scan of about 1,600 rows); CREATE OR REPLACE x5 by hunks.
-- TIME: a few seconds. BUDGET: statement_timeout 45 s, lock_timeout 5 s; fails above 30 s.
-- ROLLBACK (forward, owner only): QUICK, hold_requests_enabled false (no new job is posted; open ones drain inside 6 h and their escrow goes home).
--   Full: a new migration reversing the nine hunks (their OLD texts are below verbatim), dropping public.hold_request_post, the knobs and the column.
-- SELF-ASSERT: each hunk once and reversing; no other function moved; the hunked bodies' grants, volatility, definer, search path, owner unmoved;
--   the knobs; DARK IS TODAY: the read of one real harbour serves the same board before and after (ids, size and total aside), the writer and the
--   wind job post no hold job; THE PROBE (rolled back, purses dark): lit, the harbour posts hold_request_open_max jobs and then none, each in its
--   bounds; the city's cap does not count them; merchants are not offered them; the read serves size and total. Proof 169 proves the rest.
-- VERSION: 0466 = prod head 0464 + 2 (0465 is #778, the yard order, open; this file touches none of its bodies and does not read it).
-- news: none (dark: nothing changes for a player until the owner lights hold_requests_enabled)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array['public.tick_contracts(uuid,timestamp with time zone)', 'public.tick_contract_wind(boolean,uuid)',
                                    'world.contracts(uuid)', 'public.contract_asks(uuid)', 'public.contracts_expire(uuid,timestamp with time zone)'];
  v_t0        timestamptz := clock_timestamp();
  v_h         record;
  x           record;
  c           public.trade_contracts%rowtype;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_fn_before text;
  v_meta      text;
  v_port      uuid;
  v_board0    jsonb;
  v_board1    jsonb;
  v_a         jsonb;
  v_city      int;
  v_note      text;
  v_day       int := world.game_day();
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config where key = 'hold_requests_enabled')
     or exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'trade_contracts' and column_name = 'size') then
    raise exception '0466 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.contract_asks(uuid)') is null or to_regprocedure('public.contracts_expire(uuid,timestamp with time zone)') is null
     or to_regprocedure('public.city_floor(uuid)') is null or to_regprocedure('public.clock_start(text,bigint)') is null
     or not exists (select 1 from public.world_config where key = 'contract_open_max') then
    raise exception '0466 refuses: 0311, 0315, 0343 or 0413 is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGE, and the board one real harbour serves today (read in a rolled-back block: the read winds) ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select p.id into v_port from public.ports p where p.kind = 'HARBOUR' and p.code = 'LIS';
  if v_port is null then
    select p.id into v_port from public.ports p where p.kind = 'HARBOUR' order by p.code limit 1;
  end if;
  begin
    select coalesce(jsonb_agg(e - 'id' order by e ->> 'good'), '[]'::jsonb) into v_board0 from jsonb_array_elements(world.contracts(v_port) -> 'contracts') e;
    raise exception sqlstate 'BV466';
  exception when sqlstate 'BV466' then null;
  end;

  -- ── 2. THE COLUMN ──
  alter table public.trade_contracts add column size text not null default 'city';
  alter table public.trade_contracts add constraint trade_contracts_size_check check (size in ('city', 'hold'));
  comment on column public.trade_contracts.size is
    '0466: city = the harbour''s own request, sized by its budget (0311); hold = a load a small ship can carry, with a deadline of hours (public.hold_request_post). A hold job takes seq 101 and up.';

  -- ── 3. THE KNOBS ──
  insert into public.world_config (key, value, description) values
    ('hold_requests_enabled', 'false'::jsonb, '0466: THE SWITCH (the owner''s). false: no hold-sized job is posted. true: each harbour also keeps up to hold_request_open_max jobs a small ship can carry (public.hold_request_post), beside its city-sized requests.'),
    ('hold_request_open_max', to_jsonb(2), '0466: how many hold-sized jobs a harbour keeps open at once (its city-sized requests are counted apart, contract_open_max).'),
    ('hold_request_tons_min', to_jsonb(40), '0466: a hold-sized job weighs at least this many tons (drawn between min and max; a new ship carries 180-300 t).'),
    ('hold_request_tons_max', to_jsonb(150), '0466: a hold-sized job weighs at most this many tons.'),
    ('hold_request_units_min', to_jsonb(10), '0466: a lot of fewer units than this is not posted (the value cap leaves few units of a dear good).'),
    ('hold_request_units_max', to_jsonb(250), '0466: a hold-sized job asks for at most this many units.'),
    ('hold_request_value_max', to_jsonb(24000), '0466: a hold-sized lot is worth at most this at its mid (a new company starts with 40,000).'),
    ('hold_request_premium_pct_min', to_jsonb(0.2), '0466: the bonus a unit is at least this share of the mid at posting (the city''s request: 0.08-0.20).'),
    ('hold_request_premium_pct_max', to_jsonb(0.3), '0466: the bonus a unit is at most this share of the mid at posting.'),
    ('hold_request_hours_min', to_jsonb(2), '0466: a hold-sized job stands at least this many real hours (in whole game days, at least one).'),
    ('hold_request_hours_max', to_jsonb(6), '0466: a hold-sized job stands at most this many real hours.'),
    ('hold_request_wind_posts', to_jsonb(3), '0466: lit, how many hold-sized jobs the byeharu-voyage:contract-wind job may post a minute (inside contract_wind_ms).');

  -- ── 4. THE ONE WRITER ──
  execute $f$
create function public.hold_request_post(p_port uuid, p_now timestamptz default now())
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $b$
-- 0466: THE ONE WRITER of a hold-sized job (trade_contracts.size 'hold'). Dark: 0, nothing read but the switch. Lit: under hold_request_open_max
-- open hold jobs at a harbour, posts ONE, drawn pure in (port, game day, seq): the good (not sold here, sold elsewhere, its culture takes it, not
-- already asked for here, its allowance here covers the lot), the lot (tons in hold_request_tons_min..max, in units of its bulk, under
-- hold_request_units_max and hold_request_value_max at its mid), the bonus (hold_request_premium_pct_min..max of the mid, a unit), the deadline
-- (hold_request_hours_min..max real hours, whole game days). Lit purses: the budget is escrowed (BOUNTY) and must be under the harbour's share.
-- Answers how many it posted (0 or 1). Never raises: a refused post is 0.
declare
  v_day   int;
  v_max   int;
  v_s     int;
  v_seq   int;
  v_u     numeric;
  v_good  uuid;
  v_bulk  numeric;
  v_cap   numeric;
  v_mid   numeric;
  v_tons  numeric;
  v_qty   numeric;
  v_pct   numeric;
  v_per   numeric;
  v_bud   bigint;
  v_days  int;
  v_lit   boolean := public.city_treasury_on();
  v_base  numeric;
begin
  if public.wc('hold_requests_enabled') is distinct from 'true'::jsonb then
    return 0;
  end if;
  if (select p.kind from public.ports p where p.id = p_port) is distinct from 'HARBOUR' then
    return 0;
  end if;
  v_day := world.game_day(p_now);
  v_max := public.wc_int('hold_request_open_max');
  if (select count(*) from public.trade_contracts c where c.port_id = p_port and c.status = 'open' and c.size = 'hold') >= v_max then
    return 0;
  end if;
  select min(s) into v_s
    from generate_series(1, v_max) s
   where not exists (select 1 from public.trade_contracts c where c.port_id = p_port and c.posted_day = v_day and c.seq = 100 + s);
  if v_s is null then
    return 0;   -- every hold seq of this game day is taken: the next game day has more
  end if;
  v_seq := 100 + v_s;
  v_base := public.daily_cap_base(null::uuid, p_port);   -- 0318's rule: read once, not once a good

  -- THE GOOD: an index into the ordered candidates, as public.contract_draw
  v_u := voyage.rng(p_port, v_day, 'hold:' || v_seq::text || ':good');
  with sold_elsewhere as (
    select distinct s.good_id from public.port_specialties s join public.ports p2 on p2.id = s.port_id and p2.kind = 'HARBOUR' where s.port_id <> p_port
  ), cand as (
    select row_number() over (order by g.code) - 1 as i, count(*) over () as n, g.id as gid, g.bulk, cp.cap
      from public.goods g
      join public.ports p on p.id = p_port
      join public.port_goods pg on pg.port_id = p_port and pg.good_id = g.id
      left join public.port_offered_goods(p_port) o on o.good_id = g.id
     cross join lateral (select greatest(0, v_base * pg.stock_target) as cap) cp
     where o.good_id is null
       and g.id in (select se.good_id from sold_elsewhere se)
       and not public.culture_refuses(p.culture, g.culture_mask)
       and g.bulk > 0
       and cp.cap >= public.wc_int('hold_request_units_min')
       and not exists (select 1 from public.trade_contracts c where c.port_id = p_port and c.good_id = g.id and c.status = 'open'))
  select cand.gid, cand.bulk, cand.cap into v_good, v_bulk, v_cap
    from cand
   where cand.i = least(cand.n - 1, floor(v_u * cand.n)::int);
  if v_good is null then
    return 0;
  end if;

  -- THE LOT, THE BONUS, THE DEADLINE
  select round(q.mid, 2) into v_mid from world.price(p_port, v_good) q;
  if coalesce(v_mid, 0) <= 0 then
    return 0;
  end if;
  v_u    := voyage.rng(p_port, v_day, 'hold:' || v_seq::text || ':tons');
  v_tons := public.wc_num('hold_request_tons_min') + v_u * (public.wc_num('hold_request_tons_max') - public.wc_num('hold_request_tons_min'));
  v_qty  := least(floor(v_tons / v_bulk), public.wc_num('hold_request_units_max'), floor(public.wc_num('hold_request_value_max') / v_mid), floor(v_cap));
  if v_qty >= 20 then
    v_qty := floor(v_qty / 5) * 5;   -- a round lot reads as a job
  end if;
  if v_qty < public.wc_int('hold_request_units_min') then
    return 0;
  end if;
  v_u   := voyage.rng(p_port, v_day, 'hold:' || v_seq::text || ':premium');
  v_pct := round(public.wc_num('hold_request_premium_pct_min') + v_u * (public.wc_num('hold_request_premium_pct_max') - public.wc_num('hold_request_premium_pct_min')), 2);
  v_per := round(v_mid * v_pct, 2);
  if v_per < 1 then
    return 0;   -- under a ducat a unit the budget would pay for more units than the lot
  end if;
  v_bud := ceil(v_per * v_qty)::bigint;
  v_u    := voyage.rng(p_port, v_day, 'hold:' || v_seq::text || ':hours');
  v_days := greatest(1, round((public.wc_num('hold_request_hours_min') + v_u * (public.wc_num('hold_request_hours_max') - public.wc_num('hold_request_hours_min')))
                              * 3600 / public.wc_num('game_day_seconds'))::int);
  if v_lit and public.city_surplus(p_port) / (public.wc_int('bounty_reserve_mult') * v_max) < v_bud then
    return 0;   -- the harbour's share of its surplus does not cover the bonus
  end if;

  begin
    insert into public.trade_contracts
      (port_id, good_id, posted_day, seq, qty, premium_pct, mid_at_post, premium_per_unit, premium_ducats, expires_day, status, escrow, size)
    values
      (p_port, v_good, v_day, v_seq, floor(v_bud / v_per), v_pct, v_mid, v_per, v_bud, v_day + v_days, 'open', case when v_lit then v_bud else 0 end, 'hold')
    on conflict (port_id, posted_day, seq) do nothing;
    if not found then
      return 0;
    end if;
    if v_lit then
      perform public.treasury_post(p_port, 'BOUNTY', -v_bud, null, null);   -- 0122: the escrow leaves the city at posting
    end if;
  exception when others then
    return 0;
  end;
  return 1;
end $b$
  $f$;
  revoke all on function public.hold_request_post(uuid, timestamptz) from public, anon, authenticated;
  comment on function public.hold_request_post(uuid, timestamptz) is
    '0466: THE ONE WRITER of a hold-sized job (trade_contracts.size hold): dark 0; lit, one job a call under hold_request_open_max, drawn pure in (port, game day, seq). Called by world.contracts and the wind job. Server-only.';

  -- ── 5. THE HUNKS (each occurs exactly once in the live body, and reverses) ──
  create temp table hunks_0466 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0466 values
  ('public.tick_contracts(uuid,timestamp with time zone)', 1,
$h$  if (select count(*) from public.trade_contracts where port_id = p_port and status = 'open') >= v_max then$h$,
$h$  if (select count(*) from public.trade_contracts where port_id = p_port and status = 'open' and size = 'city') >= v_max then   -- 0466: the city's own rows; a hold-sized job is counted apart$h$),
  ('public.tick_contract_wind(boolean,uuid)', 1,
$h$  v_note   text;$h$,
$h$  v_note   text;
  v_hold   int := 0;               -- 0466: hold-sized jobs posted this minute
  v_asked  uuid[] := '{}'::uuid[];   -- 0466: the harbours asked for one this minute$h$),
  ('public.tick_contract_wind(boolean,uuid)', 2,
$h$     cross join lateral (select count(*) as n from public.trade_contracts c where c.port_id = p.id and c.status = 'open') o$h$,
$h$     cross join lateral (select count(*) as n from public.trade_contracts c where c.port_id = p.id and c.status = 'open' and c.size = 'city') o   -- 0466: the city's own rows$h$),
  ('public.tick_contract_wind(boolean,uuid)', 3,
$h$  delete from public.contract_deliveries d where d.at < now() - interval '2 days';$h$,
$h$  -- (C) 0466: THE HOLD-SIZED JOBS, lit only (hold_requests_enabled): the harbours under hold_request_open_max, the fewest first, in an order that turns each
  -- minute, at most hold_request_wind_posts, each its own transaction, inside the same contract_wind_ms. One writer: public.hold_request_post.
  if public.wc('hold_requests_enabled') = 'true'::jsonb then
    loop
      exit when clock_timestamp() >= v_by;
      exit when cardinality(v_asked) >= public.wc_int('hold_request_wind_posts');
      v_p := null;
      select p.id into v_p
        from public.ports p
       cross join lateral (select count(*) as n from public.trade_contracts c where c.port_id = p.id and c.status = 'open' and c.size = 'hold') o
       where p.kind = 'HARBOUR' and o.n < public.wc_int('hold_request_open_max') and p.id <> all (v_asked)
         and public.treasury_balance(p.id) >= public.city_floor(p.id)
         and (p_only is null or p.id = p_only)
       order by o.n, md5(p.id::text || floor(extract(epoch from v_now0) / 60)::text)
       limit 1;
      exit when v_p is null;
      v_asked := v_asked || v_p;
      begin
        v_hold := v_hold + public.hold_request_post(v_p, now());
      exception when others then
        v_failed := v_failed + 1;
        v_note := coalesce(v_note, 'hold ' || v_p || ': ' || sqlerrm);
      end;
      if p_commit then commit; end if;
    end loop;
  end if;
  delete from public.contract_deliveries d where d.at < now() - interval '2 days';$h$),
  ('public.tick_contract_wind(boolean,uuid)', 4,
$h$'posted', v_posted, 'failed', v_failed, 'note', v_note))$h$,
$h$'posted', v_posted, 'failed', v_failed, 'note', v_note, 'hold', v_hold))$h$),
  ('world.contracts(uuid)', 1,
$h$  perform public.tick_contracts(p_port, now());$h$,
$h$  perform public.tick_contracts(p_port, now());
  perform public.hold_request_post(p_port, now());   -- 0466: and the hold-sized jobs (dark: nothing)$h$),
  ('world.contracts(uuid)', 2,
$h$        'premium_ducats', c.premium_ducats,$h$,
$h$        'premium_ducats', c.premium_ducats,
        -- 0466: city (the harbour's own) or hold (a load a small ship can carry); a hold job's whole pay at today's bid plus the bonus, one figure
        'size', c.size,
        'total', case when c.size = 'hold' then round(floor(c.premium_ducats / c.premium_per_unit) * (q.bid + c.premium_per_unit))::bigint end,$h$),
  ('public.contract_asks(uuid)', 1,
$h$     and c.premium_per_unit > 0 and c.premium_ducats >= c.premium_per_unit$h$,
$h$     and c.premium_per_unit > 0 and c.premium_ducats >= c.premium_per_unit
     and c.size = 'city'   -- 0466: a hold-sized job is the companies'$h$),
  ('public.contracts_expire(uuid,timestamp with time zone)', 1,
$h$   where port_id = p_port and status <> 'open' and expires_day < v_day - v_deadline;$h$,
$h$   where port_id = p_port and status <> 'open'
     and expires_day < v_day - case when size = 'hold' then ceil(86400 / public.wc_num('game_day_seconds'))::int else v_deadline end;   -- 0466: a hold job, a real day after$h$);

  for v_h in select h.fn from hunks_0466 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0466 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0466 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0466 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0466 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0466 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 6. SELF-ASSERT: the catalog, the knobs ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))
         and p.oid <> 'public.hold_request_post(uuid,timestamp with time zone)'::regprocedure) <> v_fn_before then
    raise exception '0466 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0466 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if has_function_privilege('authenticated', 'public.hold_request_post(uuid,timestamp with time zone)', 'execute')
     or has_function_privilege('anon', 'public.hold_request_post(uuid,timestamp with time zone)', 'execute') then
    raise exception '0466 self-assert FAIL: a player can call the writer';
  end if;
  if public.wc('hold_requests_enabled') <> 'false'::jsonb or public.wc_int('hold_request_open_max') <> 2 or public.wc_int('hold_request_wind_posts') <> 3
     or exists (select 1 from public.trade_contracts t where t.size <> 'city') then
    raise exception '0466 self-assert FAIL: the knobs are not this file''s, or a row is not a city''s';
  end if;

  -- ── 7. DARK IS TODAY (rolled back): the same board, no hold job from the writer, the read or the wind ──
  begin
    select coalesce(jsonb_agg(e - 'id' - 'size' - 'total' order by e ->> 'good'), '[]'::jsonb) into v_board1 from jsonb_array_elements(world.contracts(v_port) -> 'contracts') e;
    if v_board1 is distinct from v_board0 then
      raise exception '0466 self-assert FAIL: dark, the board of the probe harbour moved: % / %', v_board0, v_board1;
    end if;
    if public.hold_request_post(v_port, now()) <> 0 then
      raise exception '0466 self-assert FAIL: dark, the writer posted';
    end if;
    call public.tick_contract_wind(false, v_port);
    if exists (select 1 from public.trade_contracts t where t.size = 'hold') then
      raise exception '0466 self-assert FAIL: dark, a hold job was posted';
    end if;
    v_note := format('dark: the board of %s the same (%s requests), no hold job', (select p.code from public.ports p where p.id = v_port), jsonb_array_length(v_board0));
    raise exception sqlstate 'BV466';
  exception when sqlstate 'BV466' then null;
  end;

  -- ── 8. THE PROBE, rolled back by a raised sentinel: lit, purses dark, at the same harbour ──
  begin
    update public.world_config set value = 'false'::jsonb where key = 'city_treasury_enabled';
    update public.world_config set value = 'true'::jsonb where key = 'hold_requests_enabled';
    v_city := (select count(*) from public.trade_contracts t where t.port_id = v_port and t.status = 'open');
    if public.hold_request_post(v_port, now()) <> 1 or public.hold_request_post(v_port, now()) <> 1 then
      raise exception '0466 self-assert FAIL: lit, the probe harbour did not post two hold jobs';
    end if;
    if public.hold_request_post(v_port, now()) <> 0 then
      raise exception '0466 self-assert FAIL: lit, a third hold job past hold_request_open_max';
    end if;
    for c in select * from public.trade_contracts t where t.port_id = v_port and t.size = 'hold' loop
      if c.seq <= 100 or c.qty < public.wc_int('hold_request_units_min') or c.qty > public.wc_int('hold_request_units_max')
         or c.qty * (select g.bulk from public.goods g where g.id = c.good_id) > public.wc_num('hold_request_tons_max')
         or c.qty * c.mid_at_post > public.wc_num('hold_request_value_max')
         or c.premium_pct < public.wc_num('hold_request_premium_pct_min') or c.premium_pct > public.wc_num('hold_request_premium_pct_max')
         or c.premium_ducats <> ceil(c.premium_per_unit * c.qty) or c.escrow <> 0
         or c.expires_day <= v_day
         or (c.expires_day - v_day - 1) * public.wc_num('game_day_seconds') > public.wc_num('hold_request_hours_max') * 3600
         or exists (select 1 from public.port_offered_goods(v_port) o where o.good_id = c.good_id) then
        raise exception '0466 self-assert FAIL: a hold job out of its bounds: %', to_jsonb(c);
      end if;
    end loop;
    if (select count(*) from public.trade_contracts t where t.port_id = v_port and t.status = 'open' and t.size = 'city') <> v_city then
      raise exception '0466 self-assert FAIL: the city''s own rows moved under the hold posts';
    end if;
    update public.world_config set value = to_jsonb(0) where key = 'contract_npc_after_hours';
    if exists (select 1 from public.contract_asks(v_port) a join public.trade_contracts t on t.id = a.id where t.size = 'hold') then
      raise exception '0466 self-assert FAIL: a merchant is offered a hold job';
    end if;
    select e into v_a from jsonb_array_elements(world.contracts(v_port) -> 'contracts') e where e ->> 'size' = 'hold' limit 1;
    select * into c from public.trade_contracts t where t.id = (v_a ->> 'id')::uuid;
    if v_a is null or (v_a ->> 'total')::bigint is distinct from round((v_a ->> 'qty')::numeric * (v_a ->> 'price_each')::numeric)::bigint
       or (v_a ->> 'qty')::numeric <> c.qty then
      raise exception '0466 self-assert FAIL: the read does not serve a hold job''s size and total: %', v_a;
    end if;
    v_note := v_note || format('; lit: 2 hold jobs then none (%s x %s, pays %s; %s)', v_a ->> 'qty', v_a ->> 'good', v_a ->> 'total',
                               (select string_agg(t.qty || ' ' || g.code || ' ' || round(t.qty * g.bulk) || ' t', ', ') from public.trade_contracts t join public.goods g on g.id = t.good_id
                                 where t.port_id = v_port and t.size = 'hold'));
    raise exception sqlstate 'BV466';
  exception when sqlstate 'BV466' then null;
  end;

  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0466 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0466 self-assert ok: REQUESTS A SHIP CAN CARRY (dark). % hunks once each and reversing; grants and volatility unmoved; no other function moved; the column, the writer and 12 knobs (hold_requests_enabled false). %; % ms.',
    (select count(*) from hunks_0466), v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0466;
end $m$;
