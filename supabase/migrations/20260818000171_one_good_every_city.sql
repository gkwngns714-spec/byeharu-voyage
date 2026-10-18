-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0171 — ONE GOOD, EVERY CITY  (COMMAND DESK slice D2: the good page's board, and the watchlist)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY ─────────────────────────────────────────────────────────────────────────────────────────
-- The owner, 2026-10-17: *"when i press coffee trade goods, it will show chart, where i can buy, the price if i
-- sell to other cities. at which time and so on."* docs/COMMAND_DESK.md §3.2, §3.3, §7.2, §7.3, §10 row D2. Row 55
-- and row 64 are REVERSED by that order (COMMAND_DESK, the table at its head).
--
-- ── WHAT THIS FILE DOES (one authority each; nothing re-spelt) ─────────────────────────────────
-- (1) public.outlook_best(points, from, side) — NEW: THE best-time rule, MOVED out of world.price_outlook (0170,
--     one hunk; the read now composes it at its own now and answers as before — asserted on every sample row ×
--     side): from the first point at or after `from`, the cheapest ask (side ask) or the dearest mid / bid
--     after it, served only when its gain beats the band's half-width there.
-- (2) world.good_board(good, fleet, from, qty) — NEW, the client's read. For the caller's fleet:
--       buy  — every city that sells the good: what the amount costs there (world.quote, her purser and any
--              bargain included), the stock, the miles and voyage days from where she is (or is bound), when
--              she would arrive, the estimate there at that time and its best time (world.price_outlook, ask).
--       sell — every harbour whose culture buys it, with the market price there (world.mid_price) and the
--              miles; the good_board_quoted dearest of them priced in full: what she gets (world.quote,
--              sell), what it cost (the cargo's bought-at price when it is on board, public.fleet_cargo_basis;
--              else the buy row it would be bought at), the profit tax (public.profit_tax), the crew's wages for
--              the voyage days (public.fleet_wage × days, the figure voyage.settle charges), net and net per
--              ton, the day's cap left (world.daily_cap_remaining), an open request, and the estimate at
--              arrival with its best time (world.price_outlook, bid; public.outlook_best).
--     The port fee (the quote's spread_total) is served beside the money and is NOT subtracted again: it is
--     already inside what she gets.
-- (3) world.watchlist(fleet) — NEW, the client's read: every good once — how many cities sell it, the
--     cheapest of them and its market price as THE RECORD last wrote it (public.price_history at its newest
--     slot: world.mid_price at the snapshot; a pair with no point there — a world with no snapshot job, the local
--     game — is priced live through world.mid_price and says so), its hourly record over the window, the change
--     across it, what the fleet has on board, and the cities with an open request for it. Key lookups only.
-- (4) the knob good_board_quoted 10; client_rpc_entry_points +2 (one hunk).
--
-- ── WHAT IT DELIBERATELY DOES NOT DO ────────────────────────────────────────────────────────────
-- Copy any price, quote, tax, wage or terms arithmetic: every figure is a call of its one authority, so a term
-- added INSIDE world.mid_terms / world.mid_from_terms / world.quote_priced reaches the board by itself. Change
-- world.quote, world.trade_routes or any rule. Settle a fleet or wind a clock (asserted). Count supplies,
-- repairs or losses at sea (COMMAND_DESK D7). Distances are not offered from a bare sea point (an anchored
-- fleet has no row in the sailed-distance table): such a board has no miles, days or arrival.
--
-- ── THE PROOF (own probe company, rolled back; production is lived in) ────────────────────────────
-- (a) world.price_outlook old (pre-image) vs new, on a sample of market rows × mid / ask / bid: equal; the body
--     reverses to its pre-image; ACL unmoved. outlook_best on built points: flat → none; a rise → the top; an
--     ask's fall → the bottom; a later `from` → measured from there; a gain inside the band → none.
-- (b) THE PROBE: a company at Lisbon (public.new_house), signed in as it. good_board for a good Lisbon sells:
--     Lisbon is a buy row at 0 miles; every quoted sell row recomputed by hand — world.quote, profit_tax,
--     fleet_wage × days — equals the board to the coin; the rows are the harbours that do not refuse it.
--     Bought 10 through cmd.do_buy: the board's basis is on_board and its cost is fleet_cargo_basis × units.
--     Another company's fleet → E_NOT_YOURS. watchlist: every good once; the bought good on board; the
--     cheapest seller of 20 goods recomputed; the read's sparkline is the record's hourly points.
-- (c) the registry +2 (authenticated, not anon); the leaf server-only; the walls; no clock stepped.
-- Timings: raise notice only.
--
-- ── LOCKS ───────────────────────────────────────────────────────────────────────────────────────
-- CREATE (OR REPLACE) FUNCTION (catalogue only). The probe writes its own company's rows, a 10-unit purchase at
-- Lisbon (that market row is locked until the sub-transaction rolls back, ~1 s) — all rolled back.
-- No LOCK TABLE, no set role, no set local, no begin.
--
-- ── DEPLOY ──────────────────────────────────────────────────────────────────────────────────────
-- DEPLOY_RUNBOOK (unwind → push → wind). Nothing reads the two reads until D3's client.
-- ROLLBACK: drop the three functions, reverse world.price_outlook's and client_rpc_entry_points' hunks.
-- VERSION: 0171 PROVISIONAL — prod head 0170 when written (2026-10-18); renumbered to head + 1 at deploy. Every
-- pre-image is read live from the target; the hunks were checked to occur once there (read-only).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

create or replace function pg_temp.occurs_0171(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 1. THE PRE-IMAGES ─────────────────────────────────────────────────────────────────────────
create temp table defs_before_0171 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg,
       (select p.proowner from pg_proc p where p.oid = f.fn::regprocedure) as owner
  from (values ('world.price_outlook(uuid, uuid, integer, text)'),
               ('public.client_rpc_entry_points()')) f(fn);

create temp table before_0171 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from public.world_config where key = 'good_board_quoted') as own_knobs,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where (n.nspname, p.proname) in (('public', 'outlook_best'), ('world', 'good_board'), ('world', 'watchlist'))) as n_found;

do $$
declare
  v_def text;
begin
  if (select count(*) from defs_before_0171 where def is not null) <> 2 then
    raise exception '0171 self-assert FAIL: % of the 2 bodies found', (select count(*) from defs_before_0171 where def is not null);
  end if;
  if (select n_found from before_0171) <> 0 then
    raise exception '0171 self-assert FAIL: a function this file creates already exists';
  end if;
  select def into v_def from defs_before_0171 where fn = 'world.price_outlook(uuid, uuid, integer, text)';
  v_def := replace(v_def, 'CREATE OR REPLACE FUNCTION world.price_outlook(', 'CREATE OR REPLACE FUNCTION pg_temp.price_outlook_old_0171(');
  if strpos(v_def, 'FUNCTION pg_temp.price_outlook_old_0171(') = 0 or strpos(v_def, 'outlook_best') > 0 then
    raise exception '0171 self-assert FAIL: the old copy of world.price_outlook was not made from the pre-image';
  end if;
  execute v_def;
end $$;

-- ── 2. THE KNOB ───────────────────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('good_board_quoted', '10'::jsonb,
   '0171 (docs/COMMAND_DESK.md §3.3): how many of the dearest cities world.good_board prices in full (a quote, '
   'the profit tax, the wages, the estimate at arrival); the rest carry the market price and the miles.')
on conflict (key) do nothing;

-- ── 3. THE RULE, ONE LEAF ─────────────────────────────────────────────────────────────────────
create or replace function public.outlook_best(p_points jsonb, p_from timestamptz, p_side text)
returns jsonb
language sql
stable
as $$
  -- 0171: THE BEST TIME, moved out of world.price_outlook (0170), which composes it at its own now;
  -- world.good_board composes it at an arrival. From the first point at or after p_from, the cheapest ask
  -- (p_side 'ask') or the dearest mid / bid after it — served only when its gain beats the band's
  -- half-width at that time; otherwise null: it is as likely to fall as to rise. Server-only.
  with pts as (
    select (x.e->>'at')::timestamptz as at, (x.e->>'value')::numeric as value,
           (x.e->>'lo')::numeric as lo, (x.e->>'hi')::numeric as hi, x.i
      from jsonb_array_elements(coalesce(p_points, '[]'::jsonb)) with ordinality x(e, i)
  ), z as (
    select pts.value, pts.i from pts where pts.at >= p_from order by pts.i limit 1
  ), b as (
    select pts.at, pts.value, pts.lo, pts.hi,
           case when p_side = 'ask' then z.value - pts.value else pts.value - z.value end as gain
      from pts cross join z
     where pts.i > z.i
     order by case when p_side = 'ask' then pts.value else -pts.value end, pts.i
     limit 1
  )
  select case when b.gain > (b.hi - b.lo) / 2 and b.gain > 0 and z.value > 0
              then jsonb_build_object('at', b.at, 'value', b.value, 'gain_pct', round(b.gain / z.value * 100, 2)) end
    from b cross join z
$$;
revoke all on function public.outlook_best(jsonb, timestamptz, text) from public, anon, authenticated;

-- ── 4. THE RE-CUTS (hunks sliced from the live bodies; each occurs once; each body reverses) ──
create temp table hunks_0171 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0171 (fn, n, old, new) values
('world.price_outlook(uuid, uuid, integer, text)', 1,
$h$  ), z as (
    select pp.value from pp where pp.k = 0
  ), b as (
    select pp.at, pp.value, pp.lo, pp.hi,
           case when v_side = 'ask' then z.value - pp.value else pp.value - z.value end as gain
      from pp cross join z
     where pp.k > 0
     order by case when v_side = 'ask' then pp.value else -pp.value end, pp.k
     limit 1
  )
  select (select jsonb_agg(jsonb_build_object('at', pp.at, 'value', pp.value, 'lo', pp.lo, 'hi', pp.hi) order by pp.k) from pp),
         (select max(pp.at) from pp),
         (select case when b.gain > (b.hi - b.lo) / 2 and b.gain > 0 and z.value > 0
                      then jsonb_build_object('at', b.at, 'value', b.value, 'gain_pct', round(b.gain / z.value * 100, 2)) end
            from b cross join z)
    into v_pts, v_end, v_best;
$h$,
$h$  )
  select (select jsonb_agg(jsonb_build_object('at', pp.at, 'value', pp.value, 'lo', pp.lo, 'hi', pp.hi) order by pp.k) from pp),
         (select max(pp.at) from pp)
    into v_pts, v_end;
  v_best := public.outlook_best(v_pts, v_now, v_side);   -- 0171: the rule, one leaf (world.good_board reads it from an arrival)
$h$),
('public.client_rpc_entry_points()', 1,
$h$      ('world',       'price_outlook',         'uuid, uuid, int, text')
$h$,
$h$      ('world',       'price_outlook',         'uuid, uuid, int, text'),
      -- 0171: one good at every city for your fleet, and every good once (docs/COMMAND_DESK.md §7.2–7.3, D2).
      ('world',       'good_board',            'uuid, uuid, uuid, numeric'),
      ('world',       'watchlist',             'uuid')
$h$);

do $$
declare
  d     record;
  h     record;
  p     record;
  v_def text;
  v_rev text;
  v_n   int := 0;
begin
  for d in select * from defs_before_0171 order by fn loop
    v_def := d.def;
    for h in select * from hunks_0171 where fn = d.fn order by n loop
      if pg_temp.occurs_0171(v_def, h.old) <> 1 then
        raise exception '0171 self-assert FAIL: % hunk % occurs % time(s), not once — the deployed body is not what this file was written against',
          d.fn, h.n, pg_temp.occurs_0171(v_def, h.old);
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    execute v_def;
    v_rev := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0171 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0171(v_rev, h.new) <> 1 then
        raise exception '0171 self-assert FAIL: % new hunk % is not in the live body once', d.fn, h.n;
      end if;
      v_rev := replace(v_rev, h.new, h.old);
    end loop;
    if v_rev <> d.def then
      raise exception '0171 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef,
           coalesce(pr.proconfig::text, '') as cfg, pr.proowner as owner
      into p from pg_proc pr where pr.oid = d.fn::regprocedure;
    if p.acl <> d.acl or p.vol <> d.vol or p.secdef <> d.secdef or p.cfg <> d.cfg or p.owner <> d.owner then
      raise exception '0171 self-assert FAIL: % changed its ACL, owner, volatility, definer or config', d.fn;
    end if;
    v_n := v_n + 1;
  end loop;
  if v_n <> 2 then
    raise exception '0171 self-assert FAIL: % bodies re-cut, not 2', v_n;
  end if;
end $$;

-- ── 5. THE TWO READS ──────────────────────────────────────────────────────────────────────────
create or replace function world.good_board(p_good uuid, p_fleet uuid, p_from uuid default null, p_qty numeric default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0171: ONE GOOD AT EVERY CITY, FOR YOUR FLEET (docs/COMMAND_DESK.md §3.3, §7.2). Every figure is a call of its
-- one authority: world.quote (the money), world.mid_price (the market price), public.profit_tax,
-- public.fleet_wage (what a day at sea costs this crew — voyage.settle's figure), voyage.reach_from (the sailed
-- miles), voyage.fleet_speed, world.daily_cap_remaining, world.price_outlook + public.outlook_best (the estimate).
-- Distances run from where the fleet is: docked there, or bound there (the miles still to sail added, the eta
-- the voyage holds). A voyage day is 86,400 / time_compression real seconds (DESIGN D.2, as voyage.progress_nm
-- reads it). Reads; settles nothing; steps no clock.
declare
  v_player  uuid := public.current_player_id();
  f         public.fleets%rowtype;
  g         public.goods%rowtype;
  v         public.voyages%rowtype;
  v_now     timestamptz := now();
  v_tc      numeric := public.wc_num('time_compression');
  v_slot_s  numeric := public.wc_num('drift_slot_seconds');
  v_slots   int := public.wc_int('outlook_slots');
  v_max     int := public.wc_int('outlook_slots_max');
  v_quoted  int := public.wc_int('good_board_quoted');
  v_origin  uuid;
  v_lead_nm numeric := 0;
  v_lead_at timestamptz := now();
  v_speed   numeric;
  v_wage    numeric;
  v_aboard  numeric;
  v_units   numeric;
  v_basis   text;
  v_cost_each numeric;
  v_src     record;
  v_buy     jsonb;
  v_sell    jsonb;
  v_where   jsonb;
begin
  if v_player is null then
    raise exception 'E_NO_PLAYER: there is no company signed in' using errcode = 'P0001';
  end if;
  select * into f from public.fleets where id = p_fleet;
  if f.id is null or f.player_id is distinct from v_player then
    raise exception 'E_NOT_YOURS: that is not your fleet' using errcode = 'P0001';
  end if;
  select * into g from public.goods where id = p_good;
  if g.id is null then
    raise exception 'E_NO_SUCH_GOOD: there is no such good' using errcode = 'P0001';
  end if;

  v_speed := voyage.fleet_speed(p_fleet);
  v_wage  := public.fleet_wage(p_fleet, false);
  if f.port_id is not null then
    v_origin := f.port_id;
    v_where  := jsonb_build_object('kind', 'docked', 'port', (select code from public.ports where id = f.port_id));
  else
    select * into v from public.voyages where fleet_id = p_fleet and status = 'SAILING' order by departed_at desc limit 1;
    if v.id is not null then
      v_origin  := v.dest_port_id;
      v_lead_nm := greatest(0, v.total_nm - voyage.progress_nm(v.id, v_now));
      v_lead_at := greatest(v.eta, v_now);
      v_where   := jsonb_build_object('kind', 'sailing', 'port', (select code from public.ports where id = v.dest_port_id),
                                      'miles_left', round(v_lead_nm), 'eta', v.eta);
    else
      v_where := jsonb_build_object('kind', 'at_sea', 'port', null);
    end if;
  end if;

  -- THE AMOUNT: what is on board, else what was asked, else what her free cargo space takes (at least a step)
  v_aboard := coalesce(public.fleet_cargo_qty(p_fleet, g.code), 0);
  if v_aboard > 0 then
    v_units := v_aboard; v_basis := 'on_board';
    v_cost_each := public.fleet_cargo_basis(p_fleet, g.code);
  elsif p_qty is not null and p_qty > 0 then
    v_units := floor(p_qty); v_basis := 'asked';
  else
    v_units := floor(public.fleet_free_hold(p_fleet) / g.bulk); v_basis := 'capacity';
    if v_units < 1 then
      v_units := public.wc_num('trade_step_tuns'); v_basis := 'step';
    end if;
  end if;

  -- BUY AT: every city that sells it
  with reach as materialized (
    select r.port_id, r.nm from voyage.reach_from(v_origin) r
    union all select v_origin, 0 where v_origin is not null
  ), sellers as materialized (
    select p.id, p.code, p.name, rc.nm, pg.stock,
           qb.units, qb.total, qb.avg_price
      from public.ports p
      join public.port_goods pg on pg.port_id = p.id and pg.good_id = p_good
      left join reach rc on rc.port_id = p.id
     cross join lateral world.quote(p.id, p_good, v_units, 'buy', null, p_fleet) qb
     where p.kind = 'HARBOUR' and public.port_offers(p.id, p_good)
  ), timed as materialized (
    select s.*,
           case when s.nm is not null and v_speed > 0
                then v_lead_at + make_interval(secs => (s.nm / v_speed * 3600 / v_tc)::double precision) end as arrive_at
      from sellers s
  ), shaped as (
    select t.*, o.j
      from timed t
     cross join lateral (select world.price_outlook(t.id, p_good,
                          least(v_max, greatest(v_slots, ceil(extract(epoch from (coalesce(t.arrive_at, v_now) - v_now)) / v_slot_s)::int + 1)),
                          'ask') as j) o
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'port', s.code, 'name', s.name, 'here', s.id = f.port_id,
           'units', s.units, 'cost', s.total, 'price_each', s.avg_price, 'stock', s.stock,
           'miles', case when s.nm is not null then round(v_lead_nm + s.nm) end,
           'days', case when s.nm is not null and v_speed > 0 then round((v_lead_nm + s.nm) / v_speed / 24, 2) end,
           'arrive_at', s.arrive_at,
           'at_arrival', (select jsonb_build_object('value', (e->>'value')::numeric, 'lo', (e->>'lo')::numeric, 'hi', (e->>'hi')::numeric)
                            from jsonb_array_elements(s.j->'points') with ordinality x(e, i)
                           where (e->>'at')::timestamptz >= coalesce(s.arrive_at, v_now) order by i limit 1),
           'best', public.outlook_best(s.j->'points', coalesce(s.arrive_at, v_now), 'ask'))
           order by s.avg_price nulls last, s.code), '[]'::jsonb)
    into v_buy
    from shaped s;

  -- WHERE IT WOULD BE BOUGHT (not on board): the asked city, else the cheapest that can fill any of it
  select e->>'port' as code, (e->>'units')::numeric as units, (e->>'cost')::numeric as cost into v_src
    from jsonb_array_elements(v_buy) e
   where v_basis <> 'on_board'
     and (e->>'units')::numeric > 0
     and (p_from is null or e->>'port' = (select code from public.ports where id = p_from))
   order by (e->>'price_each')::numeric, e->>'port' limit 1;

  -- SELL AT: every harbour whose culture buys it; the dearest good_board_quoted priced in full
  with src as (
    select p.id from public.ports p where v_basis <> 'on_board' and p.code = v_src.code
  ), reach as materialized (
    select r.port_id, r.nm from voyage.reach_from(v_origin) r
    union all select v_origin, 0 where v_origin is not null
  ), reach2 as materialized (   -- from the buy city, when it must be bought first
    select r.port_id, r.nm from src cross join lateral voyage.reach_from(src.id) r
    union all select id, 0 from src
  ), cand as materialized (
    select p.id, p.code, p.name,
           world.mid_price(p.id, p_good, pg.stock) as mid,
           case when v_basis = 'on_board' then rc.nm
                else (select rc1.nm from reach rc1 where rc1.port_id = (select id from src)) + r2.nm end as nm
      from public.ports p
      join public.port_goods pg on pg.port_id = p.id and pg.good_id = p_good
      left join reach rc on rc.port_id = p.id
      left join reach2 r2 on r2.port_id = p.id
     where p.kind = 'HARBOUR' and not public.culture_refuses(p.culture, g.culture_mask)
  ), ranked as materialized (
    select c.*, row_number() over (order by c.mid desc, c.nm nulls last, c.code) as rk from cand c
  ), units as (
    select case when v_basis = 'on_board' then v_units else coalesce(v_src.units, 0) end as n,
           case when v_basis = 'on_board' then case when v_cost_each is null then null else round(v_cost_each * v_units) end
                else v_src.cost end as cost
  ), quoted as materialized (
    select r.id, qs.total as proceeds, qs.avg_price, qs.spread_total,
           case when r.nm is not null and v_speed > 0 then (v_lead_nm + r.nm) / v_speed / 24 end as days,
           case when r.nm is not null and v_speed > 0
                then v_lead_at + make_interval(secs => (r.nm / v_speed * 3600 / v_tc)::double precision) end as arrive_at
      from ranked r cross join units u
     cross join lateral world.quote(r.id, p_good, u.n, 'sell', null, p_fleet) qs
     where r.rk <= v_quoted and u.n > 0
  ), priced as materialized (
    select q.*, u.cost,
           public.profit_tax(q.id, case when u.cost is null then null else q.proceeds - u.cost end, v_player) as tax,
           case when q.days is null then null else round(v_wage * q.days) end as wages,
           world.daily_cap_remaining(v_player, q.id, p_good) as cap_left,
           world.price_outlook(q.id, p_good,
             least(v_max, greatest(v_slots, ceil(extract(epoch from (coalesce(q.arrive_at, v_now) - v_now)) / v_slot_s)::int + 1)),
             'bid') as j
      from quoted q cross join units u
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'port', r.code, 'name', r.name, 'mid', r.mid, 'quoted', p.id is not null,
           'miles', case when r.nm is not null then round(v_lead_nm + r.nm) end,
           'days', case when r.nm is not null and v_speed > 0 then round((v_lead_nm + r.nm) / v_speed / 24, 2) end,
           'arrive_at', p.arrive_at,
           'units', case when p.id is not null then (select n from units) end,
           'price_each', p.avg_price, 'proceeds', p.proceeds, 'cost', p.cost, 'profit_tax', p.tax,
           'port_fee', p.spread_total, 'wages', p.wages,
           'net', case when p.id is not null and p.cost is not null and p.wages is not null
                       then p.proceeds - p.cost - p.tax - p.wages end,
           'net_per_ton', case when p.id is not null and p.cost is not null and p.wages is not null and (select n from units) > 0
                               then round((p.proceeds - p.cost - p.tax - p.wages) / ((select n from units) * g.bulk), 2) end,
           'cap_left', p.cap_left,
           'at_arrival', case when p.id is not null then
              (select jsonb_build_object('value', (e->>'value')::numeric, 'lo', (e->>'lo')::numeric, 'hi', (e->>'hi')::numeric)
                 from jsonb_array_elements(p.j->'points') with ordinality x(e, i)
                where (e->>'at')::timestamptz >= coalesce(p.arrive_at, v_now) order by i limit 1) end,
           'best', case when p.id is not null then public.outlook_best(p.j->'points', coalesce(p.arrive_at, v_now), 'bid') end,
           'request', (select jsonb_build_object('premium_pct', c.premium_pct, 'days_left', c.expires_day - world.game_day())
                         from public.trade_contracts c
                        where c.port_id = r.id and c.good_id = p_good and c.status = 'open' and c.expires_day >= world.game_day()
                        order by c.premium_pct desc limit 1))
           order by (p.id is null),
                    case when p.id is not null and p.cost is not null and p.wages is not null
                         then p.proceeds - p.cost - p.tax - p.wages end desc nulls last,
                    r.mid desc, r.code), '[]'::jsonb)
    into v_sell
    from ranked r left join priced p on p.id = r.id;

  return jsonb_build_object(
    'good', g.code,
    'fleet', jsonb_build_object('id', f.id, 'name', f.name, 'where', v_where, 'speed_kn', v_speed, 'wage_per_day', v_wage),
    'qty', jsonb_build_object('units', v_units, 'basis', v_basis, 'tons', round(v_units * g.bulk, 2),
                              'bought_at', case when v_basis <> 'on_board' then v_src.code end,
                              'cost_each', v_cost_each),
    'buy', v_buy,
    'sell', v_sell,
    'quoted', v_quoted,
    'assumes', 'If nobody else trades here',
    'clock', jsonb_build_object('now', v_now, 'next_change_at', public.next_drift_change_at(v_now)));
end $$;

create or replace function world.watchlist(p_fleet uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0171: EVERY GOOD ONCE (docs/COMMAND_DESK.md §3.2, §7.3). The market price of a good's cheapest seller is THE
-- RECORD's (public.price_history — world.mid_price as the snapshot wrote it at its newest slot in the window,
-- at most a drift slot ago; `as_of` says when): one pass for the newest slot, then a key lookup a pair. A sold
-- pair with no point at that slot (no snapshot job runs — the local game — or a city that began selling it
-- since) is priced live through world.mid_price, and `recorded` says which. The sparkline is that pair's
-- record hour by hour back from the newest slot, oldest first; change_pct is across it. on_board: the fleet's
-- cargo (public.fleet_cargo_qty), when one of yours is named. wanted_at: the cities with an open request.
-- Reads; writes nothing.
declare
  v_player uuid := public.current_player_id();
  v_slot   bigint := public.drift_slot_of(now());
  v_win    int := public.price_history_window();
  v_step   int := greatest(1, round(3600 / public.wc_num('drift_slot_seconds'))::int);   -- slots an hour
  v_day    int := world.game_day();
  v_last   bigint;
  v_hours  bigint[];
  v_out    jsonb;
begin
  if p_fleet is not null and not exists (select 1 from public.fleets where id = p_fleet and player_id = v_player) then
    raise exception 'E_NOT_YOURS: that is not your fleet' using errcode = 'P0001';
  end if;
  select max(h.slot) into v_last from public.price_history h where h.slot > v_slot - v_win and h.slot <= v_slot;
  v_hours := array(select v_last - v_step * j from generate_series(0, v_win / v_step - 1) j
                    where v_last is not null and v_last - v_step * j > v_slot - v_win);

  with sold as materialized (
    select p.id as port_id, p.code as port, o.good_id
      from public.ports p cross join lateral public.port_offered_goods(p.id) o
     where p.kind = 'HARBOUR'
  ), priced as materialized (
    select s.port_id, s.port, s.good_id,
           coalesce(h.mid, world.mid_price(s.port_id, s.good_id, pg.stock)) as mid,
           h.at as as_of, h.mid is not null as recorded
      from sold s
      join public.port_goods pg on pg.port_id = s.port_id and pg.good_id = s.good_id
      left join public.price_history h on h.port_id = s.port_id and h.good_id = s.good_id and h.slot = v_last
  ), best as materialized (
    select distinct on (p.good_id) p.* from priced p order by p.good_id, p.mid, p.port
  ), spark as materialized (
    select b.good_id, jsonb_agg(round(h.mid, 2) order by h.slot) as pts, (array_agg(h.mid order by h.slot))[1] as first
      from best b
      join public.price_history h on h.port_id = b.port_id and h.good_id = b.good_id and h.slot = any(v_hours)
     group by b.good_id
  ), sellers as (
    select good_id, count(*) as n from sold group by good_id
  ), aboard as (
    select k.code, public.fleet_cargo_qty(p_fleet, k.code) as qty
      from (select distinct e.key as code from public.ships sh cross join lateral jsonb_each(sh.cargo) e
             where p_fleet is not null and sh.fleet_id = p_fleet) k
  ), wanted as (
    select c.good_id, jsonb_agg(distinct p.code) as ports
      from public.trade_contracts c join public.ports p on p.id = c.port_id
     where c.status = 'open' and c.expires_day >= v_day
     group by c.good_id
  )
  select jsonb_agg(jsonb_build_object(
           'code', g.code,
           'sellers', coalesce(se.n, 0),
           'best', case when b.good_id is null then null
                        else jsonb_build_object('port', b.port, 'mid', round(b.mid, 2), 'as_of', b.as_of, 'recorded', b.recorded) end,
           'change_pct', case when sp.first > 0 and b.good_id is not null then round((b.mid - sp.first) / sp.first * 100, 1) end,
           'spark', coalesce(sp.pts, '[]'::jsonb),
           'on_board', coalesce(a.qty, 0),
           'wanted_at', coalesce(w.ports, '[]'::jsonb))
           order by g.code)
    into v_out
    from public.goods g
    left join best b on b.good_id = g.id
    left join spark sp on sp.good_id = g.id
    left join sellers se on se.good_id = g.id
    left join aboard a on a.code = g.code
    left join wanted w on w.good_id = g.id;

  return jsonb_build_object(
    'window_slots', v_win,
    'goods', coalesce(v_out, '[]'::jsonb),
    'clock', jsonb_build_object('now', now(), 'next_change_at', public.next_drift_change_at(now())));
end $$;

revoke all on function world.good_board(uuid, uuid, uuid, numeric) from public, anon, authenticated;
revoke all on function world.watchlist(uuid) from public, anon, authenticated;
grant execute on function world.good_board(uuid, uuid, uuid, numeric) to authenticated;
grant execute on function world.watchlist(uuid) to authenticated;

-- ── 6. THE PROOFS ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_uid   constant uuid := '00000000-0171-4000-8000-000000000001';
  c_nil   constant uuid := '00000000-0000-0000-0000-000000000000';
  v_lis   uuid := (select id from public.ports where code = 'LIS');
  v_p     uuid;
  v_pf    uuid;
  v_good  uuid;
  v_code  text;
  v_b     jsonb;
  v_b2    jsonb;
  v_w     jsonb;
  v_out   jsonb;
  v_bad   int;
  v_t0    timestamptz;
  v_notes text := '';
  v_state text;
  v_pts   jsonb;
  v_t     timestamptz := now();
  e       jsonb;
  v_n     int;
begin
  -- (a) world.price_outlook old vs new, on a sample of market rows × side
  select count(*) into v_bad
    from (select pg.port_id, pg.good_id from public.port_goods pg order by md5(pg.port_id::text || pg.good_id::text) limit 60) r
   cross join (values ('mid'), ('ask'), ('bid')) s(side)
   where pg_temp.price_outlook_old_0171(r.port_id, r.good_id, 24, s.side) - 'now' - 'clock'
         is distinct from world.price_outlook(r.port_id, r.good_id, 24, s.side) - 'now' - 'clock';
  if v_bad > 0 then
    raise exception '0171 self-assert FAIL: world.price_outlook answers differently on % (row, side) pair(s) now that it composes public.outlook_best', v_bad;
  end if;
  -- outlook_best on built points (the rule's arms)
  v_pts := jsonb_build_array(
    jsonb_build_object('at', v_t, 'value', 100, 'lo', 100, 'hi', 100),
    jsonb_build_object('at', v_t + interval '15 min', 'value', 101, 'lo', 99, 'hi', 103),
    jsonb_build_object('at', v_t + interval '30 min', 'value', 110, 'lo', 106, 'hi', 114),
    jsonb_build_object('at', v_t + interval '45 min', 'value', 104, 'lo', 99, 'hi', 109));
  if public.outlook_best(v_pts, v_t, 'bid')->>'value' <> '110'
     or public.outlook_best(v_pts, v_t + interval '30 min', 'bid') is not null       -- from the top, nothing rises
     or public.outlook_best(v_pts, v_t, 'ask') is not null                            -- nothing falls below 100
     or public.outlook_best(v_pts, v_t + interval '29 min', 'ask')->>'value' <> '104' -- from 110: 104 is 6 lower, the band ±5
     or public.outlook_best(jsonb_build_array(jsonb_build_object('at', v_t, 'value', 100, 'lo', 100, 'hi', 100),
                                              jsonb_build_object('at', v_t + interval '15 min', 'value', 102, 'lo', 97, 'hi', 107)), v_t, 'bid') is not null
     or public.outlook_best('[]'::jsonb, v_t, 'bid') is not null then
    raise exception '0171 self-assert FAIL: public.outlook_best does not take its arms';
  end if;

  -- (b) THE PROBE: an own company at Lisbon, signed in as it, rolled back whole
  begin
    v_p := public.new_house(c_uid, 'Casa do Balcão 0171', 'PRT', 'LIS');
    select id into v_pf from public.fleets where player_id = v_p;
    perform public.credit(v_p, 'PROBE_0171', 1000000);
    perform cmd.assume_identity(c_uid);
    -- a good Lisbon sells, with stock to sell
    select g.id, g.code into v_good, v_code
      from public.goods g join public.port_goods pg on pg.good_id = g.id and pg.port_id = v_lis
     where public.port_offers(v_lis, g.id) and pg.stock >= 50
     order by g.code limit 1;
    if v_good is null then
      raise exception '0171 self-assert FAIL: Lisbon sells no good with 50 in stock';
    end if;

    v_t0 := clock_timestamp();
    v_b := world.good_board(v_good, v_pf);
    v_notes := v_notes || format('good_board %s ms (%s buy, %s sell rows); ', round(extract(epoch from clock_timestamp() - v_t0) * 1000),
                                 jsonb_array_length(v_b->'buy'), jsonb_array_length(v_b->'sell'));
    if v_b->'qty'->>'basis' not in ('capacity', 'step') or (v_b->'qty'->>'units')::numeric < 1 then
      raise exception '0171 self-assert FAIL: an empty hold''s board is not sized by capacity: %', v_b->'qty';
    end if;
    if not exists (select 1 from jsonb_array_elements(v_b->'buy') b
                    where b->>'port' = 'LIS' and (b->>'here')::boolean and (b->>'miles')::numeric = 0) then
      raise exception '0171 self-assert FAIL: Lisbon is not a buy row at 0 miles, here';
    end if;
    if jsonb_array_length(v_b->'sell') <> (select count(*) from public.ports p join public.goods g on g.id = v_good
                                             where p.kind = 'HARBOUR' and not public.culture_refuses(p.culture, g.culture_mask)) then
      raise exception '0171 self-assert FAIL: the sell rows are not the harbours that buy it';
    end if;
    -- every quoted row, by hand
    v_n := 0;
    for e in select x from jsonb_array_elements(v_b->'sell') x where (x->>'quoted')::boolean loop
      v_n := v_n + 1;
      if (e->>'proceeds')::numeric <> (select q.total from world.quote((select id from public.ports where code = e->>'port'), v_good,
                                                                       (e->>'units')::numeric, 'sell', null, v_pf) q)
         or (e->>'profit_tax')::numeric <> public.profit_tax((select id from public.ports where code = e->>'port'),
                                                             (e->>'proceeds')::numeric - (e->>'cost')::numeric, v_p)
         -- the wages: the day's wage × the voyage days (the board's miles are rounded to the mile, so a mile's wage either way)
         or abs((e->>'wages')::numeric - public.fleet_wage(v_pf, false) * (e->>'miles')::numeric / voyage.fleet_speed(v_pf) / 24)
            > public.fleet_wage(v_pf, false) / voyage.fleet_speed(v_pf) / 24 + 1
         or (e->>'net')::numeric <> (e->>'proceeds')::numeric - (e->>'cost')::numeric - (e->>'profit_tax')::numeric - (e->>'wages')::numeric then
        raise exception '0171 self-assert FAIL: the sell row % is not the quote, the tax and the wages: %', e->>'port', e;
      end if;
    end loop;
    if v_n <> least(public.wc_int('good_board_quoted'), jsonb_array_length(v_b->'sell')) then
      raise exception '0171 self-assert FAIL: % sell row(s) quoted, not %', v_n, public.wc_int('good_board_quoted');
    end if;
    if (v_b->'sell'->0->>'cost')::numeric <> (select (b->>'cost')::numeric from jsonb_array_elements(v_b->'buy') b where b->>'port' = v_b->'qty'->>'bought_at') then
      raise exception '0171 self-assert FAIL: the sell rows'' cost is not the buy row it would be bought at';
    end if;

    -- bought 10: the board is the cargo's
    perform cmd.do_buy(v_pf, jsonb_build_object('good', v_good::text, 'qty', 10));
    v_b2 := world.good_board(v_good, v_pf);
    if v_b2->'qty'->>'basis' <> 'on_board' or (v_b2->'qty'->>'units')::numeric <> public.fleet_cargo_qty(v_pf, v_code)
       or exists (select 1 from jsonb_array_elements(v_b2->'sell') x where (x->>'quoted')::boolean
                    and (x->>'cost')::numeric <> round(public.fleet_cargo_basis(v_pf, v_code) * (v_b2->'qty'->>'units')::numeric)) then
      raise exception '0171 self-assert FAIL: a good on board is not priced from what it cost: %', v_b2->'qty';
    end if;

    -- the watchlist
    v_t0 := clock_timestamp();
    v_w := world.watchlist(v_pf);
    v_notes := v_notes || format('watchlist %s ms (%s goods, %s recorded); ', round(extract(epoch from clock_timestamp() - v_t0) * 1000),
                                 jsonb_array_length(v_w->'goods'),
                                 (select count(*) from jsonb_array_elements(v_w->'goods') x where (x->'best'->>'recorded')::boolean));
    if jsonb_array_length(v_w->'goods') <> (select count(*) from public.goods)
       or (select (x->>'on_board')::numeric from jsonb_array_elements(v_w->'goods') x where x->>'code' = v_code) <> public.fleet_cargo_qty(v_pf, v_code) then
      raise exception '0171 self-assert FAIL: the watchlist is not every good once with the cargo on board';
    end if;
    -- the cheapest seller of 20 goods, recomputed from the record (or live where the record has nothing)
    select count(*) into v_bad
      from (select x from jsonb_array_elements(v_w->'goods') x where x->'best' <> 'null'::jsonb order by md5(x->>'code') limit 20) w
     where (w.x->'best'->>'mid')::numeric <> (
       select round(min(coalesce(
                (select h.mid from public.price_history h where h.port_id = p.id and h.good_id = g.id
                    and h.slot = (select max(h2.slot) from public.price_history h2
                                   where h2.slot > public.drift_slot_of(now()) - public.price_history_window()
                                     and h2.slot <= public.drift_slot_of(now()))),
                world.mid_price(p.id, g.id, pg.stock))), 2)
         from public.goods g
         join public.ports p on p.kind = 'HARBOUR'
         join public.port_goods pg on pg.port_id = p.id and pg.good_id = g.id
        where g.code = w.x->>'code' and public.port_offers(p.id, g.id));
    if v_bad > 0 then
      raise exception '0171 self-assert FAIL: % watchlist row(s) do not name the cheapest seller''s price', v_bad;
    end if;
    if exists (select 1 from jsonb_array_elements(v_w->'goods') x where jsonb_array_length(x->'spark') > 12) then
      raise exception '0171 self-assert FAIL: a sparkline holds more than the window''s hourly points';
    end if;

    -- another company's fleet
    begin
      perform world.good_board(v_good, (select f.id from public.fleets f where f.player_id <> v_p limit 1));
      v_state := 'none';
    exception when others then
      v_state := sqlerrm;
    end;
    if v_state not like 'E_NOT_YOURS:%' then
      raise exception '0171 self-assert FAIL: another company''s fleet was not refused E_NOT_YOURS (%)', v_state;
    end if;
    begin
      perform world.watchlist((select f.id from public.fleets f where f.player_id <> v_p limit 1));
      v_state := 'none';
    exception when others then
      v_state := sqlerrm;
    end;
    if v_state not like 'E_NOT_YOURS:%' then
      raise exception '0171 self-assert FAIL: the watchlist named another company''s fleet (%)', v_state;
    end if;

    raise exception using errcode = 'ZX171', message = jsonb_build_object('notes', v_notes,
      'buy', jsonb_array_length(v_b->'buy'), 'sell', jsonb_array_length(v_b->'sell'), 'quoted', v_n,
      'top', v_b->'sell'->0->>'port', 'net', v_b->'sell'->0->>'net', 'good', v_code)::text;
  exception when sqlstate 'ZX171' then
    v_out := sqlerrm::jsonb;
  end;
  perform cmd.assume_identity(c_nil);
  if exists (select 1 from public.players where id = v_p) then
    raise exception '0171 self-assert FAIL: the probe company survived its rollback';
  end if;

  -- (c) the receipt
  if (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from before_0171) + 2
     or not has_function_privilege('authenticated', 'world.good_board(uuid, uuid, uuid, numeric)', 'execute')
     or not has_function_privilege('authenticated', 'world.watchlist(uuid)', 'execute')
     or has_function_privilege('anon', 'world.good_board(uuid, uuid, uuid, numeric)', 'execute')
     or has_function_privilege('anon', 'world.watchlist(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.outlook_best(jsonb, timestamptz, text)', 'execute')
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0171 self-assert FAIL: the registry, the grant wall or the read wall moved, or a client can reach the leaf';
  end if;
  if pg_get_functiondef('world.good_board(uuid, uuid, uuid, numeric)'::regprocedure) ~ '(tick_[a-z_]+|settle)\s*\('
     or pg_get_functiondef('world.watchlist(uuid)'::regprocedure) ~ '(tick_[a-z_]+|settle)\s*\(' then
    raise exception '0171 self-assert FAIL: a read steps a clock or settles a fleet';
  end if;

  raise notice '0171 self-assert ok: ONE GOOD, EVERY CITY. LEAF: public.outlook_best (world.price_outlook composes it — old = new on 60 rows × 3 sides, reverses to its pre-image). READS: world.good_board, world.watchlist (registered; authenticated only). PROBE (own company at Lisbon, rolled back): % — % buy row(s) (Lisbon here, 0 miles), % sell row(s) = the harbours that buy it, % quoted rows = world.quote + profit_tax + fleet_wage × days to the coin (best: % net %); bought 10 → priced from what it cost; another company''s fleet refused E_NOT_YOURS on both reads; the watchlist every good once, the cargo on board, the cheapest seller of 20 goods recomputed. NOTES: %',
    v_out->>'good', v_out->>'buy', v_out->>'sell', v_out->>'quoted', v_out->>'top', v_out->>'net', v_out->>'notes';
end $$;
