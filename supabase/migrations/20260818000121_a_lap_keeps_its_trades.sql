-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0121 — A LAP KEEPS ITS TRADES
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER'S WORDS ───────────────────────────────────────────────────────────────────────────
-- 2026-10-15: *"by clicking fleet, i want to be able to click on laps, so far, a lap and so on
-- which tells me what the ship has bought and sold, where it sold, and so on. info about trading."*
--
-- ── WHAT WAS FOUND ──────────────────────────────────────────────────────────────────────────────
-- A lap's trades live in ONE place: its route-born `orders` rows (`route_lap_id`, 0092), each a
-- done BUY or SELL whose `result` carries good, qty and total (cmd.do_buy / cmd.do_sell), cut into
-- stops by the SAILs between them (`args.dest`). Those rows are NOT KEPT:
--   * cmd.standing_route_close_lap deletes the route-born orders of every lap but the newest
--     closed one, at every close (0092's "BOUNDED");
--   * public.npc_compact deletes a merchant's done orders older than npc_retention_hours (6) unless
--     they belong to the OPEN lap (0097).
-- So of the seven laps the sheet's "Last laps" pills name, at most one still has its trades, and a
-- merchant's not even that for long. The lap row itself (`standing_route_laps`) keeps only sums.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) `standing_route_laps.trades jsonb` — the lap's trades, stop by stop, written by THE ONE
--     closer at the moment it already sums the same orders (sliced from its LIVE body, the way
--     0114–0117 do). COMPACT, because ~830 merchants close laps around the clock on a shared
--     database: one array per stop, `[port, sold, bought]`, each side a list of `[good, qty, total]`
--     — no keys repeated per line. Unit price is NOT stored; the read divides (total / qty), which
--     is what do_buy/do_sell's avg_price is up to rounding.
--     HARD CAPS in the builder: at most `lap_trades_stops_max` (16) stops a lap and
--     `lap_trades_lines_max` (12) lines a side a stop, the largest totals kept. A merchant route has
--     2–8 harbours and a harbour sells a handful of goods; the caps are a ceiling, not a cut.
-- (2) KEPT ON THE NEWEST `standing_route_lap_trades_keep` (7) LAPS ONLY — the same seven the
--     sheet's "Last laps" pills print (public.route_earnings' `laps_recent`). The closer nulls the
--     trades of laps older than that in the same call, so a route holds at most seven lap
--     summaries however long it runs; the lap rows themselves keep their sums as before (200).
-- (3) public.lap_trades(lap) — THE ONE BUILDER, from the orders. The closer stores its answer; the
--     read asks it live for the OPEN lap (whose orders the compactor never deletes), so "this lap,
--     so far" and "a closed lap" are one shape from one function.
--     public.lap_trades_view(trades) — THE ONE EXPANDER, compact → the served shape with words.
-- (4) world.fleet_trades(fleet) — A READ, at a tap, never on a beat. For a merchant fleet (switch
--     on — the card's own predicate) or the CALLER'S OWN fleet; anything else refuses E_NOT_FOUND
--     in the card's words. Serves the route's newest seven closed laps (newest first — pill i is
--     laps[i]) with every figure of the 0116 net (sold − bought − supplies − repairs − wages +
--     stock_out − stock_in, stock_in the previous closed lap's stock_out, the closer's own reading),
--     the open lap's trades so far, and the DAY — the laps closed in the last 24 real hours, the
--     window public.route_earnings' `day` sums, totalled and its goods summed by port, saying how
--     many of its laps still carry their trades.
--     Privacy as 0099: no cargo basis, no per-line profit, no queue, no ledger. A merchant's buying
--     and selling prices were always public on the quay; what she paid for a parcel is not served.
--     Registered in public.client_rpc_entry_points and granted to `authenticated` only.
--
-- ── COST ────────────────────────────────────────────────────────────────────────────────────────
-- Per lap close: one more indexed read of the lap's own orders (orders_route_lap — the closer
-- already reads the same rows for its sums), the jsonb written in the UPDATE the closer already
-- makes, and one UPDATE nulling the lap that falls out of the seven (an index range on
-- standing_route_laps_one_per_number). Measured bytes per lap and closer time: DEV_LOG 2026-10-15.
--
-- SUPERSEDES: cmd.standing_route_close_lap (0116) and public.client_rpc_entry_points (0118) — one
-- hunk each, sliced from the LIVE body and asserted to occur exactly once.
-- Self-asserts hold AS FOUND (0113); every probe rolls back.
-- VERSION: 0121 = the chain's highest (0118) + 3; 0119 and 0120 are being written alongside.

do $guard$ begin perform set_config('statement_timeout', '20min', true); end $guard$;

-- ── 1. THE KNOBS ───────────────────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('standing_route_lap_trades_keep', to_jsonb(7),
   '0121: how many of a route''s newest closed laps keep their trades (standing_route_laps.trades). Older '
   'laps keep their sums and lose the detail at the next close. 7: the laps the merchant sheet''s "Last '
   'laps" pills print (public.route_earnings laps_recent).'),
  ('lap_trades_stops_max', to_jsonb(16),
   '0121: the most stops one lap''s trades record (public.lap_trades). A route has at most 8 harbours.'),
  ('lap_trades_lines_max', to_jsonb(12),
   '0121: the most lines one side (sold or bought) of one stop records in a lap''s trades, the largest '
   'totals kept (public.lap_trades).')
on conflict (key) do nothing;

-- ── 2. THE COLUMN ──────────────────────────────────────────────────────────────────────────────
alter table public.standing_route_laps add column if not exists trades jsonb;
comment on column public.standing_route_laps.trades is
  '0121: the lap''s trades stop by stop, compact: [[port_code, [[good_code, qty, total], …sold], '
  '[[good_code, qty, total], …bought]], …] in sailing order. Written by cmd.standing_route_close_lap '
  '(public.lap_trades); kept on the newest standing_route_lap_trades_keep laps, null on older ones '
  'and on laps closed before 0121.';

-- ── 3. THE ONE BUILDER ─────────────────────────────────────────────────────────────────────────
create or replace function public.lap_trades(p_lap uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0121: one lap's trades, from its route-born orders, cut into stops by its SAILs. Segment k is
  -- the stop she lay at after k SAILs of this lap: k = 0 is the route's first stop (a lap opens
  -- there — cmd.run_standing_route's LAP BOUNDARY), k > 0 the dest of the k-th SAIL. A stop is
  -- recorded if she traded there or sailed on from it, so a call with nothing to trade still shows;
  -- the closing arrival (after the last SAIL, before that stop's SELL — which is the next lap's) is
  -- not a stop of this lap. Lines are summed per good per side; capped as the header says.
  with o as (
    select o.seq, o.verb, o.args, o.result,
           (count(*) filter (where o.verb = 'SAIL') over (order by o.seq)
              - case when o.verb = 'SAIL' then 1 else 0 end)::int as k
      from public.orders o
     where o.route_lap_id = p_lap and o.status = 'done' and o.verb in ('SAIL', 'BUY', 'SELL')
  ), lines as (
    select y.k, y.verb, y.good, y.qty, y.total, y.first
      from (select o.k, o.verb, o.result->>'good' as good,
                   sum((o.result->>'qty')::numeric) as qty,
                   round(sum((o.result->>'total')::numeric)) as total,
                   min(o.seq) as first,
                   row_number() over (partition by o.k, o.verb
                                      order by round(sum((o.result->>'total')::numeric)) desc, min(o.seq)) as rn
              from o
             where o.verb in ('BUY', 'SELL') and jsonb_typeof(o.result->'qty') = 'number'
               and (o.result->>'qty')::numeric > 0 and o.result->>'good' is not null
             group by o.k, o.verb, o.result->>'good') y
     where y.rn <= public.wc_int('lap_trades_lines_max')
  ), segs as (
    select s.k from (select o.k from o where o.verb = 'SAIL' union select l.k from lines l) s
     order by s.k limit public.wc_int('lap_trades_stops_max')
  )
  select case when exists (select 1 from segs) then
    jsonb_agg(jsonb_build_array(
      case when s.k = 0
           then (select po.code from public.standing_route_laps x
                   join public.standing_route_stops st on st.route_id = x.route_id and st.ord = 0
                   join public.ports po on po.id = st.port_id
                  where x.id = p_lap)
           else (select po.code from o join public.ports po on po.id = (o.args->>'dest')::uuid
                  where o.verb = 'SAIL' and o.k = s.k - 1 limit 1) end,
      coalesce((select jsonb_agg(jsonb_build_array(l.good, l.qty, l.total) order by l.first)
                  from lines l where l.k = s.k and l.verb = 'SELL'), '[]'::jsonb),
      coalesce((select jsonb_agg(jsonb_build_array(l.good, l.qty, l.total) order by l.first)
                  from lines l where l.k = s.k and l.verb = 'BUY'), '[]'::jsonb))
      order by s.k)
  end
    from segs s
$$;
comment on function public.lap_trades(uuid) is
  '0121: THE one builder of a lap''s trades (compact; see standing_route_laps.trades), from its done '
  'route-born orders. The closer stores it; world.fleet_trades asks it live for an open lap. Server-only.';
revoke all on function public.lap_trades(uuid) from public, anon, authenticated;

-- ── 4. THE ONE EXPANDER ────────────────────────────────────────────────────────────────────────
create or replace function public.lap_trades_view(p_trades jsonb)
returns jsonb
language sql
immutable
set search_path = public, pg_temp
as $$
  -- 0121: compact → served. Null in, null out (a lap whose trades are not kept says so).
  -- `price` is total ÷ qty, to two places — what the executors' avg_price is, up to rounding.
  select case when p_trades is null or jsonb_typeof(p_trades) <> 'array' then null else
    coalesce((select jsonb_agg(jsonb_build_object(
        'port', s.v->>0,
        'sold', coalesce((select jsonb_agg(jsonb_build_object(
                   'good', l.v->>0, 'qty', l.v->1, 'total', l.v->2,
                   'price', round((l.v->>2)::numeric / nullif((l.v->>1)::numeric, 0), 2)) order by l.n)
                   from jsonb_array_elements(s.v->1) with ordinality l(v, n)), '[]'::jsonb),
        'bought', coalesce((select jsonb_agg(jsonb_build_object(
                   'good', l.v->>0, 'qty', l.v->1, 'total', l.v->2,
                   'price', round((l.v->>2)::numeric / nullif((l.v->>1)::numeric, 0), 2)) order by l.n)
                   from jsonb_array_elements(s.v->2) with ordinality l(v, n)), '[]'::jsonb))
        order by s.n)
       from jsonb_array_elements(p_trades) with ordinality s(v, n)), '[]'::jsonb)
  end
$$;
comment on function public.lap_trades_view(jsonb) is
  '0121: THE one expander of a lap''s compact trades into the served shape (port, sold[], bought[] of '
  'good, qty, price, total). Server-only.';
revoke all on function public.lap_trades_view(jsonb) from public, anon, authenticated;

-- ── 5. THE CLOSER RECORDS THEM (two hunks of its LIVE body) ────────────────────────────────────
create or replace function pg_temp.slice_0121(p_fn text, p_old text, p_new text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  v_n   int  := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
begin
  if v_n <> 1 then
    raise exception '0121 self-assert FAIL: a hunk of % occurs % time(s), not once — the live body is not what this file was cut against: %',
      p_fn, v_n, left(p_old, 120);
  end if;
  execute replace(v_def, p_old, p_new);
end $$;

select pg_temp.slice_0121('cmd.standing_route_close_lap(uuid, timestamptz)',
$h$         wages = v_wages, stock_out = v_out,
         net = v_sold - v_bought - v_supp - v_rep - v_wages + v_out - v_in
   where id = l.id
$h$,
$h$         wages = v_wages, stock_out = v_out,
         net = v_sold - v_bought - v_supp - v_rep - v_wages + v_out - v_in,
         trades = public.lap_trades(l.id)   -- 0121: what she bought and sold, stop by stop
   where id = l.id
$h$);
select pg_temp.slice_0121('cmd.standing_route_close_lap(uuid, timestamptz)',
$h$  delete from public.standing_route_laps x
   where x.route_id = p_route and x.lap_no <= l.lap_no - public.wc_int('standing_route_lap_keep');
$h$,
$h$  delete from public.standing_route_laps x
   where x.route_id = p_route and x.lap_no <= l.lap_no - public.wc_int('standing_route_lap_keep');
  -- 0121: the trades are kept on the newest standing_route_lap_trades_keep laps only.
  update public.standing_route_laps x set trades = null
   where x.route_id = p_route and x.trades is not null
     and x.lap_no <= l.lap_no - public.wc_int('standing_route_lap_trades_keep');
$h$);

-- ── 6. THE READ ────────────────────────────────────────────────────────────────────────────────
create or replace function world.fleet_trades(p_fleet uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0121: ONE FLEET'S TRADING — a merchant's (switch on) or the caller's own; see the file header.
declare
  v_me    uuid := public.current_player_id();
  f       public.fleets%rowtype;
  v_npc   boolean;
  sr      public.standing_routes%rowtype;
  v_laps  jsonb;
  v_open  jsonb;
  v_day   jsonb;
begin
  select x.* into f from public.fleets x where x.id = p_fleet;
  select p.is_npc into v_npc from public.players p where p.id = f.player_id;
  if f.id is null
     or not ((v_npc and public.npc_traders_on()) or (v_me is not null and f.player_id = v_me)) then
    raise exception 'E_NOT_FOUND: there is no such merchant fleet' using errcode = 'P0001';
  end if;
  if v_npc then
    select r.* into sr from public.standing_routes r
      join public.npc_fleets nf on nf.route_id = r.id where nf.fleet_id = f.id;
  else
    select r.* into sr from public.standing_routes r where r.fleet_id = f.id;
  end if;
  if sr.id is null then
    return jsonb_build_object('route', null, 'laps', '[]'::jsonb, 'open', null, 'day', null);
  end if;

  -- THE NEWEST SEVEN CLOSED LAPS (route_earnings' laps_recent, newest first), each with the 0116
  -- figures; stock_in is the previous closed lap's stock_out, as the closer reads it.
  with x as (
    select y.*, coalesce(lag(y.stock_out) over (order by y.lap_no), 0) as stock_in
      from (select * from public.standing_route_laps
             where route_id = sr.id and closed_at is not null
             order by lap_no desc limit 8) y
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'lap_no', x.lap_no, 'started_at', x.started_at, 'closed_at', x.closed_at,
           'sold', x.sold, 'bought', x.bought, 'supplies', x.supplies, 'repairs', x.repairs,
           'wages', x.wages, 'stock_in', x.stock_in, 'stock_out', x.stock_out, 'net', x.net,
           'stops', public.lap_trades_view(x.trades)) order by x.lap_no desc), '[]'::jsonb)
    into v_laps
    from (select * from x order by x.lap_no desc limit 7) x;

  -- THE OPEN LAP, so far — its orders are the one set nothing deletes (the closer and the
  -- compactor both spare the open lap's).
  select jsonb_build_object('lap_no', l.lap_no, 'started_at', l.started_at,
                            'stops', coalesce(public.lap_trades_view(public.lap_trades(l.id)), '[]'::jsonb))
    into v_open
    from public.standing_route_laps l where l.id = sr.lap_id;

  -- THE DAY: route_earnings' window (laps closed in the last 24 real hours), totalled, and its
  -- goods summed by harbour over the laps that still carry their trades.
  with w as (
    select z.* from (
      select y.*, coalesce(lag(y.stock_out) over (order by y.lap_no), 0) as stock_in
        from public.standing_route_laps y
       where y.route_id = sr.id and y.closed_at is not null
         and y.lap_no >= coalesce((select min(q.lap_no) from public.standing_route_laps q
                                    where q.route_id = sr.id and q.closed_at > now() - interval '24 hours'), 2147483647) - 1
    ) z where z.closed_at > now() - interval '24 hours'
  ), g as (
    select s.v->>0 as port, l.v->>0 as good,
           sum((l.v->>1)::numeric) filter (where side.n = 2) as sold_qty,
           sum((l.v->>2)::numeric) filter (where side.n = 2) as sold_total,
           sum((l.v->>1)::numeric) filter (where side.n = 3) as bought_qty,
           sum((l.v->>2)::numeric) filter (where side.n = 3) as bought_total
      from w
      cross join lateral jsonb_array_elements(w.trades) with ordinality s(v, n)
      cross join lateral (values (2), (3)) side(n)
      cross join lateral jsonb_array_elements(s.v->(side.n - 1)) l(v)
     where w.trades is not null
     group by 1, 2
  )
  select jsonb_build_object(
           'since', (select min(w.closed_at) from w),
           'full', exists (select 1 from public.standing_route_laps y
                            where y.route_id = sr.id and y.closed_at <= now() - interval '24 hours'),
           'laps', (select count(*) from w),
           'laps_traded', (select count(*) from w where w.trades is not null),
           'sold', coalesce((select sum(w.sold) from w), 0),
           'bought', coalesce((select sum(w.bought) from w), 0),
           'supplies', coalesce((select sum(w.supplies) from w), 0),
           'repairs', coalesce((select sum(w.repairs) from w), 0),
           'wages', coalesce((select sum(w.wages) from w), 0),
           'stock_in', coalesce((select sum(w.stock_in) from w), 0),
           'stock_out', coalesce((select sum(w.stock_out) from w), 0),
           'net', coalesce((select sum(w.net) from w), 0),
           'goods', coalesce((select jsonb_agg(jsonb_build_object(
                      'port', g.port, 'good', g.good,
                      'sold_qty', coalesce(g.sold_qty, 0), 'sold_total', coalesce(g.sold_total, 0),
                      'bought_qty', coalesce(g.bought_qty, 0), 'bought_total', coalesce(g.bought_total, 0))
                      order by g.port, g.good) from g), '[]'::jsonb))
    into v_day;

  return jsonb_build_object(
    'route', jsonb_build_object('name', sr.name,
               'stops', (select coalesce(jsonb_agg(po.code order by s.ord), '[]'::jsonb)
                           from public.standing_route_stops s join public.ports po on po.id = s.port_id
                          where s.route_id = sr.id)),
    'laps', v_laps, 'open', v_open, 'day', v_day);
end $$;
comment on function world.fleet_trades(uuid) is
  '0121: one fleet''s trading — a merchant''s (switch on) or the caller''s own: the newest seven closed '
  'laps with their figures and trades stop by stop, the open lap so far, and the last real day. '
  'Read at a tap. Authenticated only.';
revoke all on function world.fleet_trades(uuid) from public, anon;
grant execute on function world.fleet_trades(uuid) to authenticated;

-- THE REGISTRY gains the read (sliced from its live body; the hunk must occur exactly once).
do $$
declare
  v_def text := replace(pg_get_functiondef('public.client_rpc_entry_points()'::regprocedure), E'\r', '');
  v_old text := $h$      ('world',       'sea_roster',            'timestamptz'),
$h$;
begin
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then
    raise exception '0121 self-assert FAIL: the registry''s sea_roster row does not occur exactly once';
  end if;
  execute replace(v_def, v_old, v_old || $h$      -- 0121: one fleet's trading, lap by lap (src/live/TradeHistoryPanel.tsx).
      ('world',       'fleet_trades',          'uuid'),
$h$);
end $$;

-- ── 7. SELF-ASSERT ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_was_on    boolean := public.npc_traders_on();
  v_routes_on boolean := public.standing_routes_on();
  v_route     uuid;
  v_fleet     uuid;
  v_player    uuid;
  v_ship      uuid;
  v_lap       public.standing_route_laps%rowtype;
  v_home      text;
  v_dest      uuid;
  v_dest_code text;
  v_g1        text;
  v_g2        text;
  v_t         jsonb;
  v_r         jsonb;
  v_old       uuid;
  v_bytes     int;
  v_earn      jsonb;
begin
  -- (a) THE WALL AND THE REGISTRY.
  if not has_function_privilege('authenticated', 'world.fleet_trades(uuid)', 'execute')
     or has_function_privilege('anon', 'world.fleet_trades(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.lap_trades(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.lap_trades_view(jsonb)', 'execute') then
    raise exception '0121 self-assert FAIL: world.fleet_trades is not exactly authenticated-only, or a helper is client-callable';
  end if;
  if not exists (select 1 from public.client_rpc_entry_points() e
                  where e.schema_name = 'world' and e.function_name = 'fleet_trades' and e.fn is not null) then
    raise exception '0121 self-assert FAIL: world.fleet_trades is not a registered entry point';
  end if;

  select nf.route_id, nf.fleet_id into v_route, v_fleet from public.npc_fleets nf
   where nf.route_id is not null order by nf.roster_ord, nf.fleet_id limit 1;
  if v_route is null then
    raise exception '0121 self-assert FAIL: no merchant route to probe';
  end if;
  select f.player_id into v_player from public.fleets f where f.id = v_fleet;
  select s.id into v_ship from public.ships s where s.fleet_id = v_fleet order by s.id limit 1;
  select po.code into v_home from public.standing_route_stops st join public.ports po on po.id = st.port_id
   where st.route_id = v_route and st.ord = 0;
  select st.port_id, po.code into v_dest, v_dest_code from public.standing_route_stops st
    join public.ports po on po.id = st.port_id where st.route_id = v_route and st.ord = 1;
  select g.code into v_g1 from public.goods g order by g.code limit 1;
  select g.code into v_g2 from public.goods g order by g.code offset 1 limit 1;

  begin
    update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled', 'standing_routes_enabled');
    update public.standing_routes set fleet_id = v_fleet where id = v_route;
    -- a lap that fell out of the seven still holding trades, and the lap before the probe's
    insert into public.standing_route_laps (route_id, lap_no, started_at, closed_at, stock_out, trades)
    values (v_route, 900000, now() - interval '3 hours', now() - interval '2 hours', 0, '[["X",[],[]]]'::jsonb)
    returning id into v_old;
    insert into public.standing_route_laps (route_id, lap_no, started_at, closed_at, stock_out)
    values (v_route, 900007, now() - interval '2 hours', now() - interval '1 hour', 700);
    insert into public.standing_route_laps (route_id, lap_no, started_at)
    values (v_route, 900008, now()) returning * into v_lap;
    update public.standing_routes set lap_id = v_lap.id, lap_no = 900008 where id = v_route;
    update public.ships set cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb where fleet_id = v_fleet;
    -- At home: SELL g1 twice (summed), BUY g2; SAIL to stop 1; there: SELL g2. One skipped line.
    insert into public.orders (fleet_id, player_id, seq, raw_text, verb, args, status, result, route_lap_id, executed_at) values
      (v_fleet, v_player, 900001, 'SELL', 'SELL', '{}', 'done', jsonb_build_object('good', v_g1, 'qty', 10, 'total', 300), v_lap.id, now()),
      (v_fleet, v_player, 900002, 'SELL', 'SELL', '{}', 'done', jsonb_build_object('good', v_g1, 'qty', 5,  'total', 150), v_lap.id, now()),
      (v_fleet, v_player, 900003, 'BUY',  'BUY',  '{}', 'done', jsonb_build_object('good', v_g2, 'qty', 20, 'total', 400), v_lap.id, now()),
      (v_fleet, v_player, 900004, 'BUY',  'BUY',  '{}', 'skipped', null, v_lap.id, now()),
      (v_fleet, v_player, 900005, 'SAIL', 'SAIL', jsonb_build_object('dest', v_dest), 'done', '{}'::jsonb, v_lap.id, now()),
      (v_fleet, v_player, 900006, 'SELL', 'SELL', '{}', 'done', jsonb_build_object('good', v_g2, 'qty', 20, 'total', 640), v_lap.id, now());

    -- (b) THE OPEN LAP IS READ LIVE, in the served shape.
    v_r := world.fleet_trades(v_fleet);
    if v_r->'open'->>'lap_no' <> '900008' or jsonb_array_length(v_r->'open'->'stops') <> 2
       or v_r->'open'->'stops'->0->>'port' <> v_home
       or v_r->'open'->'stops'->0->'sold' <> jsonb_build_array(jsonb_build_object('good', v_g1, 'qty', 15, 'total', 450, 'price', 30.00))
       or v_r->'open'->'stops'->0->'bought'->0->>'good' <> v_g2
       or v_r->'open'->'stops'->1->>'port' <> v_dest_code
       or (v_r->'open'->'stops'->1->'sold'->0->>'price')::numeric <> 32 then
      raise exception '0121 self-assert FAIL: the open lap read %', v_r->'open';
    end if;

    -- (c) THE CLOSER RECORDS THEM, COMPACT; nulls the lap past the keep; leaves its sums alone.
    perform cmd.standing_route_close_lap(v_route, now());
    select * into v_lap from public.standing_route_laps where id = v_lap.id;
    v_t := jsonb_build_array(
      jsonb_build_array(v_home, jsonb_build_array(jsonb_build_array(v_g1, 15, 450)), jsonb_build_array(jsonb_build_array(v_g2, 20, 400))),
      jsonb_build_array(v_dest_code, jsonb_build_array(jsonb_build_array(v_g2, 20, 640)), '[]'::jsonb));
    if v_lap.trades is distinct from v_t then
      raise exception '0121 self-assert FAIL: the closer recorded % not %', v_lap.trades, v_t;
    end if;
    if v_lap.sold <> 1090 or v_lap.bought <> 400
       or v_lap.net is distinct from v_lap.sold - v_lap.bought - v_lap.supplies - v_lap.repairs - v_lap.wages + v_lap.stock_out - 700 then
      raise exception '0121 self-assert FAIL: the closer''s sums moved: sold % bought % net %', v_lap.sold, v_lap.bought, v_lap.net;
    end if;
    if (select trades from public.standing_route_laps where id = v_old) is not null then
      raise exception '0121 self-assert FAIL: a lap past the keep still holds its trades';
    end if;
    v_bytes := pg_column_size(v_lap.trades);

    -- (d) THE READ: newest first, the 0116 figures with stock_in the previous lap's stock_out, the
    --     day's net is route_earnings' day, and the day's goods are summed by harbour.
    v_r := world.fleet_trades(v_fleet);
    v_earn := public.route_earnings(v_route);
    if (v_r->'laps'->0->>'lap_no')::int <> 900008 or (v_r->'laps'->0->>'stock_in')::bigint <> 700
       or (v_r->'laps'->0->>'net')::bigint <> v_lap.net
       or v_r->'laps'->0->'stops' <> public.lap_trades_view(v_t)
       or (v_r->'laps'->1->>'lap_no')::int <> 900007 or v_r->'laps'->1->'stops' <> 'null'::jsonb
       or v_r->'open' <> 'null'::jsonb
       or (v_r->'day'->>'net')::numeric <> (v_earn->>'day')::numeric
       or (v_r->'day'->>'laps')::int <> (v_earn->>'day_laps')::int
       or (v_r->'day'->>'laps_traded')::int < 1
       or not exists (select 1 from jsonb_array_elements(v_r->'day'->'goods') g
                       where g->>'port' = v_home and g->>'good' = v_g1 and (g->>'sold_qty')::numeric = 15
                         and (g->>'sold_total')::numeric = 450 and (g->>'bought_qty')::numeric = 0) then
      raise exception '0121 self-assert FAIL: world.fleet_trades read % (earnings %)', v_r, v_earn;
    end if;

    -- (e) A PLAYER'S FLEET IS NOT A MERCHANT'S TO READ: no caller here, so it refuses in the card's words.
    begin
      perform world.fleet_trades((select f.id from public.fleets f join public.players p on p.id = f.player_id
                                   where not p.is_npc order by f.id limit 1));
      if exists (select 1 from public.fleets f join public.players p on p.id = f.player_id where not p.is_npc) then
        raise exception '0121 self-assert FAIL: a stranger read a player''s fleet';
      end if;
    exception when others then
      if sqlerrm not like 'E_NOT_FOUND%' then raise; end if;
    end;
    -- and dark, a merchant's refuses too.
    update public.world_config set value = 'false'::jsonb where key = 'npc_traders_enabled';
    begin
      perform world.fleet_trades(v_fleet);
      raise exception '0121 self-assert FAIL: dark, a merchant''s trades were served';
    exception when others then
      if sqlerrm not like 'E_NOT_FOUND%' then raise; end if;
    end;
    raise exception 'ROLLBACK_0121 %', v_bytes;
  exception when others then
    if sqlerrm not like 'ROLLBACK_0121 %' then raise; end if;
    v_bytes := split_part(sqlerrm, ' ', 2)::int;
  end;
  if public.npc_traders_on() is distinct from v_was_on or public.standing_routes_on() is distinct from v_routes_on
     or exists (select 1 from public.standing_route_laps where lap_no >= 900000) then
    raise exception '0121 self-assert FAIL: the probe world was not rolled back';
  end if;

  raise notice '0121 self-assert ok: A LAP KEEPS ITS TRADES. world.fleet_trades is authenticated-only and '
    'registered, its helpers server-only; the open lap read live (two stops, a summed line, price = total / qty); '
    'the closer recorded the lap compact (% bytes for 2 stops, 3 lines), kept its sums, nulled the lap past the '
    'keep; the read served newest first with stock_in = the previous stock_out, the day''s net = route_earnings'' '
    'day, the day''s goods by harbour; a player''s fleet and a dark merchant refuse E_NOT_FOUND. Rolled back; '
    'switches as found.', v_bytes;
end $$;
