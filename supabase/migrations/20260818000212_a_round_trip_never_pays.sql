-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0212 — A ROUND TRIP NEVER PAYS  (a shelf has one price, whichever way it is walked, and the house
--        keeps the fraction)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- THE BUG (pre-existing; found 2026-10-19 while building the live-price tick, docs/WORK_QUEUE.md HAND-OFF #2):
-- buy 10 and sell those 10 in the SAME port, with no time passing, and the sale is priced one stock step
-- BETTER than the purchase. world.quote_priced walked the book in trade_step_tuns steps and priced every
-- step at the mid of the stock it STARTED from: a buy from stock S priced its first ten at mid(S) and left
-- the stock at S − 10; the sale of those ten then started from S − 10 and priced them at mid(S − 10), which
-- is the dearer mid (the price falls as the stock grows: × (target ÷ stock) ^ elasticity). The round trip
-- therefore gained one step of the curve, ≈ elasticity × step ÷ stock (0.5 × 10 ÷ 600 = 0.83 % at the
-- thinnest market), against a spread that a purser, a bargain and a city's standing can shave to 0.4 %
-- (spread_floor 0.02 × haggle_spread_floor_frac 0.2). So a same-port flip could pay today, with no tick.
-- A second leak sat in the same body: `total := round(v_total)` rounded half up on BOTH sides, so a cheap
-- good whose bid landed on x.50 sold one tun at a time for a ducat more each than ten of them cost at once.
--
-- THE RULE (decided by default; the owner may reverse it). THE SHELF: stock is shelved in trade_step_tuns,
-- the shelves (k·step, (k+1)·step]; a shelf has ONE mid, the mid at its top (its full level), whichever
-- way it is walked. A BUY takes tuns off the shelf the stock stands in (ceil) and works down; a SELL puts
-- them onto the shelf above (floor + 1) and works up; on a shelf boundary the buy empties the shelf below
-- and the sale fills the one above. A buy of N and the sale of those N therefore walk the SAME shelves at
-- the SAME mids, in opposite order, to the digit (asserted: mid_total equal), and only the spread separates
-- the two totals. THE FRACTION: a buy's total is CEILED to the ducat and a sale's FLOORED, so splitting a
-- sale into lots can never win the half-ducat each. Both together make the theorem: for any stock, any
-- spread (0 included), any N and any splitting, cash out ≤ cash in. The per-unit price keeps its 2-dp
-- rounding (round(): the display's world.price_sides and the quote agree to the cent, as before).
--
-- WHAT MOVES ON THE LIVE WORLD. A buy from a stock on a shelf boundary (every market row sits on one until
-- the first fractional regen; prod's rows are 600–6,700, targets on tens) pays exactly what it paid: the
-- first shelf's top IS the stock. A sale pays one shelf lower than today on its first ten (≤ 0.83 % at the
-- thinnest prod market, 0.07 % at the deepest) and the same as today on every later ten. A total moves by
-- less than a ducat. world.price is NOT re-cut: mid, ask and bid stay the market's price AT the current
-- stock (the chart, the outlook and "why this price" read it); the trade tray prices through world.quote,
-- so what is quoted is what is charged. The owner may ask for a shelf-aware bid (the sell shelf's mid)
-- later: it is one more hunk here, and then price_outlook's "now" must follow it.
--
-- ONE AUTHORITY. The rule lives in world.quote_priced's walk alone; world.quote composes it unchanged, as
-- do both trade doors (cmd.do_buy, cmd.do_sell), the baskets, the routes, the good board and the merchants'
-- planner. Nothing is restated in a caller. Re-cut from the LIVE body (3 hunks, each asserted to occur
-- exactly once; the body reverses to its pre-image).
--
-- ── WHAT IT SELF-ASSERTS (its own probe rows; the planted sales are rolled back) ─────────────────
--   (a) the hunks occur once; the re-cut body reverses; ACL / volatility / definer / config unmoved; walls.
--   (b) THE THEOREM on a deterministic probe set (every 1,999th market row by port then good, plus the
--       thinnest and the deepest stock), for N in 1, 3, 7, 10, 15, 20, 37, 100: buy N at the row's stock,
--       plant the stock the buy leaves, sell N back: sell.mid_total = buy.mid_total EXACTLY, the stock
--       returns to where it was, and sell.total ≤ buy.total; and the sale in 1-tun lots (N = 7) sums to ≤
--       the buy. The pre-image (kept under pg_temp) is the positive control: on the same rows its sale's
--       mid_total is > its buy's on at least one pair — the leak this file closes.
--   (c) THE LIVE WORLD'S FIGURES: on every probe row whose stock is on a shelf boundary every BUY (units,
--       mid_total) equals the pre-image's, its total within the ceiling (≥ it, ≤ 1 ducat above); every SELL
--       total is ≤ the pre-image's (the largest fall of a 10-tun sale is reported).
--   (d) a limit order still fills partially (one probe); timings for world.quote(50) and world.price (notice).
-- ROLLBACK (a forward migration): reverse the three hunks (they reverse to the digit).
-- VERSION: 0212 at writing (prod head 0208, live; 0209–0211 are open branches). It RENUMBERS to the prod
--          head + 1 at push.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '10min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('world.quote_priced(uuid, uuid, numeric, text, numeric, uuid, numeric, numeric, numeric, numeric)') is null
     or to_regprocedure('world.quote(uuid, uuid, numeric, text, numeric, uuid)') is null
     or to_regprocedure('world.mid_from_terms(numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, integer, numeric, numeric, numeric, numeric)') is null then
    raise exception '0212 refuses: 0169''s world.quote_priced or 0194''s world.mid_from_terms is not in this world';
  end if;
  if not exists (select 1 from public.world_config where key = 'trade_step_tuns') then
    raise exception '0212 refuses: trade_step_tuns is not in this world';
  end if;
  if (select replace(pg_get_functiondef('world.quote_priced(uuid, uuid, numeric, text, numeric, uuid, numeric, numeric, numeric, numeric)'::regprocedure), E'\r', ''))
     like '%0212: THE SHELF%' then
    raise exception '0212 refuses: world.quote_priced already carries the shelf rule — this has been applied once';
  end if;
end $guard$;

-- ── 0. HELPERS (pg_temp, gone at commit) ───────────────────────────────────────────────────────
create or replace function pg_temp.occurs_0212(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 1. THE PRE-IMAGE (LF-normalised), and the old body kept under pg_temp as the positive control ──
create temp table defs_before_0212 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('world.quote_priced(uuid, uuid, numeric, text, numeric, uuid, numeric, numeric, numeric, numeric)')) f(fn);

do $old$
declare
  v_def text := (select def from defs_before_0212 where fn like 'world.quote_priced(%');
begin
  if pg_temp.occurs_0212(v_def, 'FUNCTION world.quote_priced(') <> 1 then
    raise exception '0212 self-assert FAIL: the live world.quote_priced header is not what this file was cut against';
  end if;
  execute replace(v_def, 'FUNCTION world.quote_priced(', 'FUNCTION pg_temp.quote_priced_old_0212(');
end $old$;

-- ── 2. THE HUNKS (old → new), sliced from the live body ────────────────────────────────────────
create temp table hunks_0212 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0212 values
('world.quote_priced(uuid, uuid, numeric, text, numeric, uuid, numeric, numeric, numeric, numeric)', 1,
$h$  v_unit   numeric;
$h$,
$h$  v_unit   numeric;
  v_top    numeric;   -- 0212: the top of the shelf this step prices at
$h$),
('world.quote_priced(uuid, uuid, numeric, text, numeric, uuid, numeric, numeric, numeric, numeric)', 2,
$h$  while v_left > 0 loop
    v_n := least(v_step, v_left);
    if p_side = 'buy' then
      if v_stock < v_n then v_n := v_stock; end if;
      exit when v_n <= 0;
      v_mid  := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_haul, t.m_glut, t.m_target, v_stock, t.m_drift,   -- 0134, 0173, 0194
                                     t.m_season, t.m_dev, t.m_elasticity, t.m_dev_discount, t.m_band_lo, t.m_band_hi);
      v_unit := round(v_mid * (1 + v_tax + v_spread / 2), 2);
      -- §F.2: a limit order PARTIALLY FILLS to the largest quantity that stays under the limit.
      exit when p_limit is not null and v_unit > p_limit;
      v_total := v_total + v_unit * v_n;
      -- 0083: the same unit price in its parts, from the same v_mid / v_tax / v_spread; the parts
      -- differ from v_unit only by v_unit's rounding to the hundredth.
      v_mid_t := v_mid_t + v_mid * v_n;
      v_tax_t := v_tax_t + v_mid * v_tax * v_n;
      v_spr_t := v_spr_t + v_mid * (v_spread / 2) * v_n;
      v_hag_t := v_hag_t + (round(v_mid * (1 + v_tax + v_nohag / 2), 2) - v_unit) * v_n;
      v_stock := v_stock - v_n;
    else
      v_mid  := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_haul, t.m_glut, t.m_target, v_stock, t.m_drift,   -- 0134, 0173, 0194
                                     t.m_season, t.m_dev, t.m_elasticity, t.m_dev_discount, t.m_band_lo, t.m_band_hi);
      v_unit := round(v_mid * (1 - v_spread / 2) * (1 - v_tax) * v_bidf, 2);
$h$,
$h$  while v_left > 0 loop
    -- 0212: THE SHELF. Stock is shelved in v_step tuns, the shelves (k·step, (k+1)·step]; a shelf has ONE
    -- mid, the mid at its TOP (its full level), whichever way it is walked. A buy takes tuns off the shelf
    -- the stock stands in (ceil) and works down; a sale puts them onto the shelf above (floor + 1) and
    -- works up. So a buy of N and the sale of those N walk the same shelves at the same mids, in opposite
    -- order, and only the spread separates the two totals: a round trip never pays. (Before 0212 each
    -- step was priced at the stock it STARTED from, and a sale came out one shelf dearer than the buy.)
    if p_side = 'buy' then
      exit when v_stock <= 0;
      v_top := ceil(v_stock / v_step) * v_step;
      v_n   := least(v_left, v_stock - (v_top - v_step));
    else
      v_top := (floor(greatest(v_stock, 0) / v_step) + 1) * v_step;
      v_n   := least(v_left, v_top - greatest(v_stock, 0));
    end if;
    v_mid := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_haul, t.m_glut, t.m_target, v_top, t.m_drift,   -- 0134, 0173, 0194; 0212: the shelf's top
                                  t.m_season, t.m_dev, t.m_elasticity, t.m_dev_discount, t.m_band_lo, t.m_band_hi);
    if p_side = 'buy' then
      v_unit := round(v_mid * (1 + v_tax + v_spread / 2), 2);
      -- §F.2: a limit order PARTIALLY FILLS to the largest quantity that stays under the limit.
      exit when p_limit is not null and v_unit > p_limit;
      v_total := v_total + v_unit * v_n;
      -- 0083: the same unit price in its parts, from the same v_mid / v_tax / v_spread; the parts
      -- differ from v_unit only by v_unit's rounding to the hundredth.
      v_mid_t := v_mid_t + v_mid * v_n;
      v_tax_t := v_tax_t + v_mid * v_tax * v_n;
      v_spr_t := v_spr_t + v_mid * (v_spread / 2) * v_n;
      v_hag_t := v_hag_t + (round(v_mid * (1 + v_tax + v_nohag / 2), 2) - v_unit) * v_n;
      v_stock := v_stock - v_n;
    else
      v_unit := round(v_mid * (1 - v_spread / 2) * (1 - v_tax) * v_bidf, 2);
$h$),
('world.quote_priced(uuid, uuid, numeric, text, numeric, uuid, numeric, numeric, numeric, numeric)', 3,
$h$  total     := round(v_total)::bigint;
$h$,
$h$  -- 0212: THE HOUSE KEEPS THE FRACTION — a buy's total ceiled to the ducat, a sale's floored (it was round()
  -- on both sides, which paid a cheap good's x.50 bid a ducat up on every one-tun lot). The parts below
  -- stay exact sums, as 0083 left them.
  total     := case when p_side = 'buy' then ceil(v_total) else floor(v_total) end::bigint;
$h$);

create or replace function pg_temp.recut_0212(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := (select def from defs_before_0212 where fn = p_fn);
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0212 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0212(v_def, h.old);
    if v_n <> 1 then
      raise exception '0212 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0212(fn) from defs_before_0212 order by fn;

-- ── 3. THE SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
do $$
declare
  v_fn     constant text := 'world.quote_priced(uuid, uuid, numeric, text, numeric, uuid, numeric, numeric, numeric, numeric)';
  v_step   numeric := public.wc_num('trade_step_tuns');
  v_d      record;
  v_h      record;
  v_def    text;
  v_pp     record;
  pr       record;
  b        record;   -- the new buy
  s        record;   -- the new sale of what the buy took
  ob       record;   -- the pre-image's buy
  os       record;   -- the pre-image's sale
  q        record;
  v_n      numeric;
  v_lots   numeric;
  v_probes int := 0;
  v_pairs  int := 0;
  v_leaky  int := 0;   -- pre-image pairs whose sale's mid_total exceeded its buy's (the bug)
  v_grid   int := 0;   -- probe rows on a shelf boundary, where the buy is held to the pre-image
  v_worst  numeric := 0;   -- the worst new sell.total ÷ buy.total seen (must be ≤ 1)
  v_drop   numeric := 0;   -- the largest fall of a 10-tun sale against the pre-image (notice)
  v_lim    text;
  v_t      timestamptz;
  v_ms     numeric[] := '{}';
  v_pms    numeric[] := '{}';
  i        int;
begin
  -- (a) THE RE-CUT reverses to its pre-image; ACL / volatility / definer / config unmoved
  for v_d in select * from defs_before_0212 loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0212 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0212(v_def, v_h.new) <> 1 then
        raise exception '0212 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0212 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
      into v_pp from pg_proc p where p.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0212 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0212 self-assert FAIL: a wall moved';
  end if;

  -- THE PROBE SET — deterministic: every 1,999th market row by port code then good code, plus the thinnest
  -- and the deepest stock (ties by the same order).
  create temp table probe_0212 on commit drop as
  with rows_ as (
    select pg.port_id, pg.good_id, pg.stock, p.code as port_code, g.code as good_code,
           row_number() over (order by p.code, g.code) as rn
      from public.port_goods pg
      join public.ports p on p.id = pg.port_id
      join public.goods g on g.id = pg.good_id
     where pg.stock > 0
  )
  select port_id, good_id, stock, port_code, good_code from rows_ where rn % 1999 = 1
  union
  (select port_id, good_id, stock, port_code, good_code from rows_ order by stock asc,  port_code, good_code limit 1)
  union
  (select port_id, good_id, stock, port_code, good_code from rows_ order by stock desc, port_code, good_code limit 1);
  select count(*) into v_probes from probe_0212;
  if v_probes < 3 then
    raise exception '0212 self-assert FAIL: only % probe row(s)', v_probes;
  end if;

  -- (b) THE THEOREM, and (c) the live figures, probe by probe. Each sale is quoted on a PLANTED stock (what
  --     the buy leaves) inside a block that is rolled back by its own sentinel.
  for pr in select * from probe_0212 order by port_code, good_code loop
    if ceil(pr.stock / v_step) * v_step = pr.stock then v_grid := v_grid + 1; end if;
    foreach v_n in array array[1, 3, 7, 10, 15, 20, 37, 100] loop
      select * into b  from world.quote_priced(pr.port_id, pr.good_id, v_n, 'buy', null, null, null, null, null, null);
      select * into ob from pg_temp.quote_priced_old_0212(pr.port_id, pr.good_id, v_n, 'buy', null, null, null, null, null, null);
      if b.units <= 0 then
        raise exception '0212 self-assert FAIL: a buy of % at %/% (stock %) filled nothing', v_n, pr.port_code, pr.good_code, pr.stock;
      end if;
      -- (c) on a shelf boundary the buy is the pre-image's: same units, same mid, total within the ceiling
      if ceil(pr.stock / v_step) * v_step = pr.stock then
        if b.units <> ob.units or b.mid_total <> ob.mid_total or b.total < ob.total or b.total - ob.total > 1 then
          raise exception '0212 self-assert FAIL: a buy of % at %/% (stock %) moved: units % → %, mid_total % → %, total % → %',
            v_n, pr.port_code, pr.good_code, pr.stock, ob.units, b.units, ob.mid_total, b.mid_total, ob.total, b.total;
        end if;
      end if;
      begin
        update public.port_goods set stock = b.end_stock where port_id = pr.port_id and good_id = pr.good_id;
        select * into s  from world.quote_priced(pr.port_id, pr.good_id, b.units, 'sell', null, null, null, null, null, null);
        select * into os from pg_temp.quote_priced_old_0212(pr.port_id, pr.good_id, b.units, 'sell', null, null, null, null, null, null);
        -- the theorem: the same shelves at the same mids, and the sale never returns more than was paid
        if s.units <> b.units or s.mid_total <> b.mid_total or s.end_stock <> pr.stock then
          raise exception '0212 self-assert FAIL: the sale of % at %/% does not mirror the buy: units %/%, mid_total %/%, end stock % (was %)',
            b.units, pr.port_code, pr.good_code, s.units, b.units, s.mid_total, b.mid_total, s.end_stock, pr.stock;
        end if;
        if s.total > b.total then
          raise exception '0212 self-assert FAIL: a round trip of % at %/% (stock %) PAYS: bought for %, sold for %',
            b.units, pr.port_code, pr.good_code, pr.stock, b.total, s.total;
        end if;
        if b.total > 0 then v_worst := greatest(v_worst, s.total::numeric / b.total); end if;
        -- the positive control: the pre-image's sale came out dearer than its buy somewhere (the leak)
        if os.mid_total > ob.mid_total then v_leaky := v_leaky + 1; end if;
        -- (c) the sale against the pre-image: never dearer (the fall is reported, not bounded: it is one shelf of
        --     the curve at the stock the buy left, 0.83 % at a 600-tun market, and a drained market is steeper)
        if s.total > os.total then
          raise exception '0212 self-assert FAIL: the sale of % at %/% (stock %) is % against the pre-image''s %',
            b.units, pr.port_code, pr.good_code, pr.stock, s.total, os.total;
        end if;
        if v_n = 10 and os.total > 0 then v_drop := greatest(v_drop, 1 - s.total::numeric / os.total); end if;
        -- the sale in one-tun lots (N = 7): each lot from the stock the last one left; the lots sum to no more
        if v_n = 7 and b.units = 7 then
          v_lots := 0;
          for i in 1..7 loop
            select * into q from world.quote_priced(pr.port_id, pr.good_id, 1, 'sell', null, null, null, null, null, null);
            v_lots := v_lots + q.total;
            update public.port_goods set stock = q.end_stock where port_id = pr.port_id and good_id = pr.good_id;
          end loop;
          if v_lots > b.total then
            raise exception '0212 self-assert FAIL: seven one-tun lots at %/% (stock %) sold for %, more than the % the seven cost',
              pr.port_code, pr.good_code, pr.stock, v_lots, b.total;
          end if;
        end if;
        v_pairs := v_pairs + 1;
        raise exception using errcode = 'ZX212', message = 'planted';
      exception when sqlstate 'ZX212' then
        null;   -- the planted stock is rolled back with the block
      end;
    end loop;
    if (select stock from public.port_goods where port_id = pr.port_id and good_id = pr.good_id) <> pr.stock then
      raise exception '0212 self-assert FAIL: the planted stock at %/% survived its rollback', pr.port_code, pr.good_code;
    end if;
  end loop;
  if v_leaky = 0 then
    raise exception '0212 self-assert FAIL: the pre-image showed no leak on any of % pairs — the positive control is dead', v_pairs;
  end if;
  if v_worst > 1 then
    raise exception '0212 self-assert FAIL: worst round trip %', v_worst;
  end if;

  -- (d) a limit order still fills partially: the first probe, a buy of 100 limited to its own first-tun ask
  select x.* into pr from probe_0212 x order by x.port_code, x.good_code limit 1;
  select * into b from world.quote_priced(pr.port_id, pr.good_id, 1, 'buy', null, null, null, null, null, null);
  select * into q from world.quote_priced(pr.port_id, pr.good_id, 100, 'buy', b.avg_price, null, null, null, null, null);
  if q.units <= 0 or q.units >= 100 or q.avg_price > b.avg_price then
    raise exception '0212 self-assert FAIL: a buy of 100 limited to the first-tun ask % filled % at % (expected a partial fill under the limit)',
      b.avg_price, q.units, q.avg_price;
  end if;
  v_lim := format('%s of 100 at ≤ %s', q.units, b.avg_price);

  -- TIMINGS (notice only): 8 calls each in this session
  for i in 1..8 loop
    v_t := clock_timestamp();
    perform * from world.quote(pr.port_id, pr.good_id, 50, 'buy', null, null);
    v_ms := v_ms || round(extract(epoch from clock_timestamp() - v_t) * 1000, 2);
    v_t := clock_timestamp();
    perform * from world.price(pr.port_id, pr.good_id);
    v_pms := v_pms || round(extract(epoch from clock_timestamp() - v_t) * 1000, 2);
  end loop;

  raise notice '0212 self-assert ok: A ROUND TRIP NEVER PAYS. world.quote_priced re-cut (3 hunks, reverses; ACL kept): a shelf of % tuns has one mid (its top), a buy''s total is ceiled and a sale''s floored. % probe rows (% on a shelf boundary), % buy-then-sell pairs (N 1–100): every sale mirrors its buy to the digit and returns ≤ what was paid (worst sell ÷ buy %); seven one-tun lots never beat the seven bought. The pre-image leaked on % of % pairs (its sale dearer than its buy). On a shelf boundary the buy is the pre-image''s (units, mid; total within the ceiling); a 10-tun sale fell at most % against it. Limit: %. world.quote(50) ms %, world.price ms %.',
    v_step, v_probes, v_grid, v_pairs, round(v_worst, 6), v_leaky, v_pairs, round(v_drop * 100, 3) || ' %', v_lim, v_ms, v_pms;
end $$;
