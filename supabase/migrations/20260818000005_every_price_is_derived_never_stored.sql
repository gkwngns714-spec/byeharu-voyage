-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0005 — EVERY PRICE IS DERIVED, NEVER STORED
--        port_goods, the authored affinities that are the soul of the world, and the ONE price
--        function of DESIGN §G.1 — plus the stepped quote that makes buying move the market.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE RULE ────────────────────────────────────────────────────────────────────────────────────
--   DESIGN §G.1: "Every (port, good) pair is one row. Price is DERIVED, never stored as a free
--   variable." There is no `price` column anywhere in this migration and there never will be. What
--   is stored is the four things a price is made of — affinity (authored), stock (moved by trade),
--   drift (an OU walk), season_mod (an event) — and the price is a function of them.
--
--   §G.7.7: "The client never computes a price it then submits. Every price is derived inside the
--   transaction from the row it just locked." That is why world.quote() exists: it is the same
--   arithmetic for the dry-run preview and for the committed trade, so the number the player was
--   shown and the number they are charged cannot diverge.
--
-- ── ONE AUTHORITY PER CONCEPT ───────────────────────────────────────────────────────────────────
--   world.mid_price(port, good, stock)  — THE mid of §G.1, as a function of a HYPOTHETICAL stock.
--                                         Taking stock as a parameter is what lets one function
--                                         serve both the spot price and every step of a large order.
--   world.spread(port) / world.tax_rate(port) — the two costs of doing business, each stated once.
--   world.price(port, good)             — the spot quote (mid/ask/bid/spread) shown on MARKET.
--   world.quote(port, good, qty, side, limit) — THE stepped execution of §G.2, including the
--                                         partial fill of a limit order (§F.2 BUY "AT <= p").
--   world.game_day(at)                  — THE calendar-clock day index (§D.1).
--   world.daily_cap_remaining(...)      — THE anti-cornering cap of §G.7.1.
--
-- ── WHAT IT SELF-ASSERTS ────────────────────────────────────────────────────────────────────────
--   * One port_goods row per (port, good) — none missing, none doubled — for the whole world.
--   * Every price is positive, inside the §G.7.3 hard band, and has ask > bid.
--   * PRICE IMPACT IS REAL: 200 tuns cost strictly more PER TUN than 10 tuns (§G.2). Without this,
--     the stepping loop could be silently returning a flat price and every other assert would pass.
--   * §G.7.4 HOLDS ON EVERY PAIR: buying and immediately selling back in the same port is a
--     LOSS. Round-tripping a port is structurally unprofitable, everywhere, with no exception.
--   * THE GRADIENT IS REAL: salt bought where it is made and sold where it is not turns a profit,
--     and the actual ducat figures are printed into the deploy log.
--   * A limit order PARTIALLY FILLS rather than overpaying, and a limit nothing can satisfy fills 0.
--
-- Depends ONLY on: 0001 (knobs, lockdown), 0002 (ports/goods), 0003 (the seed), 0004 (players).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

insert into public.world_config (key, value, description) values
  ('game_day_seconds', to_jsonb(2880),
   'DESIGN D.1 calendar clock: 1 real day = 1 game month = 30 game-days, so a game-day is 2880 real seconds (48 min). Governs stock regeneration and the daily volume cap.')
on conflict (key) do nothing;

-- ── The market table ───────────────────────────────────────────────────────────────────────────
create table if not exists public.port_goods (
  port_id         uuid not null references public.ports(id) on delete cascade,
  good_id         uuid not null references public.goods(id) on delete cascade,
  affinity        numeric(5,3) not null check (affinity between 0.25 and 3.000),
  stock           numeric(12,2) not null check (stock >= 0),
  stock_target    numeric(12,2) not null check (stock_target > 0),
  production_rate numeric(10,2) not null default 0 check (production_rate >= 0),
  drift           numeric(6,4) not null default 0,
  season_mod      numeric(6,4) not null default 0 check (season_mod between -0.30 and 0.30),
  updated_at      timestamptz not null default now(),
  primary key (port_id, good_id)
);
comment on column public.port_goods.affinity is
  'DESIGN G.1: "the authored soul of the world", 0.25-3.00. Below 1 the port PRODUCES the good and '
  'sells it cheap; above 1 it is a SINK and pays dear. The gradient between two ports is the game.';

create table if not exists public.trade_daily (
  player_id uuid not null references public.players(id) on delete cascade,
  port_id   uuid not null references public.ports(id) on delete cascade,
  good_id   uuid not null references public.goods(id) on delete cascade,
  game_day  int  not null,
  qty       numeric(12,2) not null default 0 check (qty >= 0),
  primary key (player_id, port_id, good_id, game_day)
);
comment on table public.trade_daily is
  'DESIGN G.7.1: the per (player, port, good) per game-day volume cap that prevents cornering.';

alter table public.port_goods  enable row level security;
alter table public.trade_daily enable row level security;

create policy port_goods_read  on public.port_goods  for select to authenticated using (true);
create policy trade_daily_read on public.trade_daily for select to authenticated
  using (player_id = public.current_player_id());

grant select on public.port_goods, public.trade_daily to authenticated;

-- ── The seed: every (port, good) pair in the world, priced by DISTANCE FROM THE SOURCE ─────────
--
-- DESIGN §G.1 calls affinity "the authored soul of the world". With twelve ports it was authored
-- as a matrix, by hand. With 214 ports and 70 goods that matrix is 14,980 cells, and a hand-typed
-- 14,980-cell matrix is not authorship — it is noise nobody can check or defend.
--
-- So ONE editorial fact is authored — WHICH PORTS PRODUCE WHICH GOOD, in public.port_specialties,
-- sourced in docs/WORLD_DATA.md — and the affinity is derived from it by the rule below:
--
--     a port that produces the good          affinity 0.60   (it sells its own cheap)
--     anywhere else                          0.85 + 1.50 × min(1, nearest source / 6000 nm)
--     a good nobody in the world produces    affinity 1.20   (an even, unremarkable price)
--
-- That is the age of sail in one line: pepper is cheap in Malabar and dear in Lisbon because
-- Lisbon is nine thousand miles from the nearest pepper vine, and the whole voyage exists to
-- close that gap. The gradient is not decorated onto the world; it IS the world's geometry.
--
-- The distance used is the great circle, not the sailed route: it is a measure of REMOTENESS,
-- which is what price responds to, and it is one immutable function call rather than a graph walk
-- over 782 legs for each of 14,980 pairs.
--
-- stock_target and production_rate stay derived from size_tier and affinity, as before: a
-- producer's depth and a sink's thinness are consequences of the affinity, not independent facts.
insert into public.port_goods (port_id, good_id, affinity, stock, stock_target, production_rate)
select p.id,
       g.id,
       aff.affinity,
       greatest(60, round(200 * p.size_tier * (1.60 - aff.affinity))),   -- stock = target at seed
       greatest(60, round(200 * p.size_tier * (1.60 - aff.affinity))),
       case when aff.affinity < 0.80
            then round(greatest(60, 200 * p.size_tier * (1.60 - aff.affinity)) * 0.05, 2)
            else 0 end
  from public.ports p
  cross join public.goods g
  cross join lateral (
    select case
             -- Does this very port produce it?
             when exists (
               select 1 from public.port_specialties s
                where s.port_id = p.id and s.good_id = g.id
             ) then 0.600::numeric
             else least(3.000, greatest(0.250,
               round((0.850 + 1.500 * least(1.0, coalesce((
                 select min(voyage.gc_distance_nm(p.lat, p.lon, src.lat, src.lon))
                   from public.port_specialties s
                   join public.ports src on src.id = s.port_id
                  where s.good_id = g.id
               ), 6000) / 6000.0))::numeric, 3))
             )
           end as affinity
  ) aff
on conflict (port_id, good_id) do nothing;

-- ── The calendar-clock day index (DESIGN §D.1) ─────────────────────────────────────────────────
create or replace function world.game_day(p_at timestamptz default now())
returns int
language sql
stable
security definer
set search_path = public, pg_temp
as $$ select floor(extract(epoch from p_at) / public.wc_num('game_day_seconds'))::int $$;

-- ── THE price of DESIGN §G.1 ───────────────────────────────────────────────────────────────────
create or replace function world.spread(p_port uuid)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- spread = spread_base - spread_per_dev × dev_commerce, floored (DESIGN G.1).
  select greatest(
           public.wc_num('spread_floor'),
           public.wc_num('spread_base') - public.wc_num('spread_per_dev') * p.dev_commerce
         )
    from public.ports p where p.id = p_port
$$;

create or replace function world.tax_rate(p_port uuid)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$ select coalesce((select tax_rate from public.ports where id = p_port), public.wc_num('tax_rate_default')) $$;

create or replace function world.mid_price(p_port uuid, p_good uuid, p_stock numeric)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_base   numeric;
  v_aff    numeric;
  v_target numeric;
  v_drift  numeric;
  v_season numeric;
  v_dev    int;
  v_mid    numeric;
begin
  select g.base_value, pg.affinity, pg.stock_target, pg.drift, pg.season_mod, p.dev_commerce
    into v_base, v_aff, v_target, v_drift, v_season, v_dev
    from public.port_goods pg
    join public.goods g on g.id = pg.good_id
    join public.ports p on p.id = pg.port_id
   where pg.port_id = p_port and pg.good_id = p_good;

  if v_base is null then
    raise exception 'E_NO_SUCH_GOOD: no market row for port % good %', p_port, p_good using errcode = 'P0001';
  end if;

  -- DESIGN G.1, term by term. Officer purchasing/sales bonuses are NOT applied here: officers are
  -- explicitly out of V0 scope (§K.1), so there is no coefficient to fold and none is invented.
  v_mid := v_base
         * v_aff
         * power(v_target / greatest(p_stock, 1), public.wc_num('price_elasticity'))
         * (1 + v_drift)
         * (1 + v_season)
         * (1 - public.wc_num('mid_dev_discount') * v_dev);

  -- §G.7.3: a hard band. No infinite spike is reachable, in either direction.
  return round(least(greatest(v_mid, public.wc_num('price_band_lo') * v_base),
                     public.wc_num('price_band_hi') * v_base), 4);
end $$;

create or replace function world.price(p_port uuid, p_good uuid)
returns table (mid numeric, ask numeric, bid numeric, spread numeric)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_stock  numeric;
  v_mid    numeric;
  v_spread numeric;
  v_tax    numeric;
begin
  select pg.stock into v_stock from public.port_goods pg
   where pg.port_id = p_port and pg.good_id = p_good;
  if v_stock is null then
    raise exception 'E_NO_SUCH_GOOD: no market row for port % good %', p_port, p_good using errcode = 'P0001';
  end if;

  v_mid    := world.mid_price(p_port, p_good, v_stock);
  v_spread := world.spread(p_port);
  v_tax    := world.tax_rate(p_port);

  mid    := v_mid;
  spread := v_spread;
  ask    := round(v_mid * (1 + v_tax + v_spread / 2), 2);   -- what you pay   (DESIGN G.1)
  bid    := round(v_mid * (1 - v_spread / 2) * (1 - v_tax), 2);  -- what you receive
  return next;
end $$;

-- ── THE stepped execution of DESIGN §G.2 ───────────────────────────────────────────────────────
create or replace function world.quote(
  p_port uuid, p_good uuid, p_qty numeric, p_side text, p_limit numeric default null
)
returns table (units numeric, total bigint, avg_price numeric, end_stock numeric)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_step   numeric := public.wc_num('trade_step_tuns');
  v_stock  numeric;
  v_spread numeric;
  v_tax    numeric;
  v_left   numeric := p_qty;
  v_n      numeric;
  v_mid    numeric;
  v_unit   numeric;
  v_units  numeric := 0;
  v_total  numeric := 0;
begin
  if p_side not in ('buy', 'sell') then
    raise exception 'world.quote: side must be buy or sell, got %', p_side using errcode = '22023';
  end if;

  select pg.stock into v_stock from public.port_goods pg
   where pg.port_id = p_port and pg.good_id = p_good;
  if v_stock is null then
    raise exception 'E_NO_SUCH_GOOD: no market row for port % good %', p_port, p_good using errcode = 'P0001';
  end if;

  v_spread := world.spread(p_port);
  v_tax    := world.tax_rate(p_port);

  -- §G.2: "Orders execute in 10-tun steps, each repricing, so a large order pays a genuinely worse
  -- average." The loop IS the price impact; there is no separate impact formula to drift from it.
  while v_left > 0 loop
    v_n := least(v_step, v_left);
    if p_side = 'buy' then
      if v_stock < v_n then v_n := v_stock; end if;
      exit when v_n <= 0;
      v_mid  := world.mid_price(p_port, p_good, v_stock);
      v_unit := round(v_mid * (1 + v_tax + v_spread / 2), 2);
      -- §F.2: a limit order PARTIALLY FILLS to the largest quantity that stays under the limit.
      exit when p_limit is not null and v_unit > p_limit;
      v_total := v_total + v_unit * v_n;
      v_stock := v_stock - v_n;
    else
      v_mid  := world.mid_price(p_port, p_good, v_stock);
      v_unit := round(v_mid * (1 - v_spread / 2) * (1 - v_tax), 2);
      exit when p_limit is not null and v_unit < p_limit;
      v_total := v_total + v_unit * v_n;
      v_stock := v_stock + v_n;
    end if;
    v_units := v_units + v_n;
    v_left  := v_left - v_n;
  end loop;

  units     := v_units;
  total     := round(v_total)::bigint;
  avg_price := case when v_units > 0 then round(v_total / v_units, 2) else null end;
  end_stock := v_stock;
  return next;
end $$;

-- ── The anti-cornering cap of DESIGN §G.7.1 ────────────────────────────────────────────────────
create or replace function world.daily_cap_remaining(p_player uuid, p_port uuid, p_good uuid)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select greatest(0,
           public.wc_num('daily_cap_fraction') * pg.stock_target
           - coalesce((select td.qty from public.trade_daily td
                        where td.player_id = p_player and td.port_id = p_port
                          and td.good_id = p_good and td.game_day = world.game_day()), 0))
    from public.port_goods pg
   where pg.port_id = p_port and pg.good_id = p_good
$$;

grant execute on function world.price(uuid, uuid)                     to authenticated;
grant execute on function world.quote(uuid, uuid, numeric, text, numeric) to authenticated;
grant execute on function world.game_day(timestamptz)                 to authenticated;
grant execute on function world.daily_cap_remaining(uuid, uuid, uuid) to authenticated;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
--
-- NOTHING HERE ASSERTS A SEEDED NUMBER. The world is 214 ports and 70 goods now, and a test that
-- hard-codes "salt is 7.02 d. at Lisboa" is asserting a WORLD rather than a rule: it goes red the
-- day somebody adds a port, and it proves nothing about the ones nobody typed. So every check
-- below FINDS its own subject by query and then asserts the RULE.
do $$
declare
  v_rows      int;
  v_expected  int;
  v_bad       int;
  v_sample    int;
  v_ports     int;
  v_goods     int;
  v_low       uuid;
  v_high      uuid;
  v_good      uuid;
  v_names     text;
  v_gap       numeric;
  q10         record;
  q200        record;
  q_buy       record;
  q_sell      record;
  q_limit     record;
  q_nofill    record;
  v_roundtrip int := 0;
  v_pairs     int := 0;
  v_profit    numeric;
  v_grants    int;
  r           record;
  b           record;
  s           record;
begin
  -- (a) EVERY (port, good) pair carries exactly one row. Not a count somebody typed: the product
  --     of the two tables, computed here, so adding a port cannot silently leave a hole.
  select count(*) into v_ports from public.ports;
  select count(*) into v_goods from public.goods;
  v_expected := v_ports * v_goods;
  select count(*) into v_rows from public.port_goods;
  if v_rows <> v_expected then
    raise exception '0005 self-assert FAIL: % port_goods rows for % ports × % goods; expected %',
      v_rows, v_ports, v_goods, v_expected;
  end if;

  -- (b) Every price in the world is sane: positive, inside the §G.7.3 band, ask strictly above bid.
  --     This one really does walk all of them — it is a single set query, not a loop.
  select count(*) into v_bad from (
    select pg.port_id, pg.good_id, g.base_value, (world.price(pg.port_id, pg.good_id)).*
      from public.port_goods pg join public.goods g on g.id = pg.good_id
  ) x
   where x.mid <= 0 or x.ask <= 0 or x.bid <= 0
      or x.ask <= x.bid
      or x.mid < public.wc_num('price_band_lo') * x.base_value - 0.01
      or x.mid > public.wc_num('price_band_hi') * x.base_value + 0.01
      or x.spread < public.wc_num('spread_floor') - 0.0001;
  if v_bad <> 0 then
    raise exception '0005 self-assert FAIL: % of % (port,good) prices are unsound (non-positive, outside the G.7.3 band, spread below floor, or ask <= bid)',
      v_bad, v_rows;
  end if;

  -- (c) THE GRADIENT THE GAME IS PLAYED ON, found rather than assumed: the widest affinity gap
  --     between two ports that a single leg joins. Buy at the cheap end, sell at the dear end,
  --     and it must pay — otherwise there is no trade in this world and nothing else matters.
  select l.from_port_id, l.to_port_id, pg_from.good_id, pg_to.affinity - pg_from.affinity
    into v_low, v_high, v_good, v_gap
    from public.legs l
    join public.port_goods pg_from on pg_from.port_id = l.from_port_id
    join public.port_goods pg_to   on pg_to.port_id  = l.to_port_id and pg_to.good_id = pg_from.good_id
   order by pg_to.affinity - pg_from.affinity desc
   limit 1;
  if v_good is null then
    raise exception '0005 self-assert FAIL: no leg joins two ports that trade a common good';
  end if;

  select a.name || ' -> ' || b2.name || ' with ' || g.name
    into v_names
    from public.ports a, public.ports b2, public.goods g
   where a.id = v_low and b2.id = v_high and g.id = v_good;

  select * into q_buy  from world.quote(v_low,  v_good, 30, 'buy');
  select * into q_sell from world.quote(v_high, v_good, 30, 'sell');
  v_profit := q_sell.total - q_buy.total;
  if q_buy.units <> 30 or q_sell.units <> 30 then
    raise exception '0005 self-assert FAIL: the best trade in the world did not fill (bought %, sold %) — %',
      q_buy.units, q_sell.units, v_names;
  end if;
  if v_profit <= 0 then
    raise exception '0005 self-assert FAIL: the WIDEST price gradient in the world loses money: % costs % and fetches %',
      v_names, q_buy.total, q_sell.total;
  end if;

  -- (d) PRICE IMPACT IS REAL. If the stepping loop were flat, every other assert here would still
  --     pass, so this is the control that proves the loop does its job.
  select * into q10  from world.quote(v_low, v_good, 10,  'buy');
  select * into q200 from world.quote(v_low, v_good, 200, 'buy');
  if q200.avg_price <= q10.avg_price then
    raise exception '0005 self-assert FAIL: 200 tuns average % is not dearer than 10 tuns average % — buying does not move the market (DESIGN G.2)',
      q200.avg_price, q10.avg_price;
  end if;

  -- (e) DESIGN §G.7.4: "instant buy-then-sell in the same port is always a loss." Fourteen
  --     thousand pairs is 30,000 stepped quotes and this migration runs in a browser tab on first
  --     boot, so it is checked on a SAMPLE — deterministically chosen, spread across the whole
  --     world by hashing, and its size is printed. A sample, said out loud, beats a full sweep
  --     nobody waits for.
  for r in
    select pg.port_id, pg.good_id
      from public.port_goods pg
     order by md5(pg.port_id::text || pg.good_id::text)
     limit 400
  loop
    v_pairs := v_pairs + 1;
    select * into b from world.quote(r.port_id, r.good_id, 30, 'buy');
    if b.units > 0 then
      select * into s from world.quote(r.port_id, r.good_id, b.units, 'sell');
      if s.total >= b.total then
        v_roundtrip := v_roundtrip + 1;
      end if;
    end if;
  end loop;
  if v_pairs < 400 then
    raise exception '0005 self-assert FAIL: the round-trip probe examined % pairs, not 400 — it is not testing what it claims', v_pairs;
  end if;
  if v_roundtrip <> 0 then
    raise exception '0005 self-assert FAIL: % of % sampled (port,good) pairs allow a profitable same-port round trip', v_roundtrip, v_pairs;
  end if;
  v_sample := v_pairs;

  -- (f) A limit order fills partially rather than overpaying, and an impossible limit fills zero.
  select * into q_limit from world.quote(v_low, v_good, 200, 'buy', q10.avg_price);
  if q_limit.units >= 200 or q_limit.units <= 0 then
    raise exception '0005 self-assert FAIL: a limit at the 10-tun price filled % of 200 tuns; a partial fill was expected', q_limit.units;
  end if;
  select * into q_nofill from world.quote(v_low, v_good, 200, 'buy', 0.01);
  if q_nofill.units <> 0 then
    raise exception '0005 self-assert FAIL: a limit of 0.01 d. filled % tuns', q_nofill.units;
  end if;

  select count(*) into v_grants from public.client_write_grants();
  if v_grants <> 0 then
    raise exception '0005 self-assert FAIL: the market tables minted % client write grant(s)', v_grants;
  end if;

  raise notice '0005 self-assert ok: % port_goods rows (% ports × % goods), every price positive, banded and ask>bid; the widest gradient a single leg offers is % (affinity gap %) — 30 tuns cost % d. and fetch % d., +% d.; price impact real (10 t avg % d. vs 200 t avg % d.); same-port round trip loses at all % sampled pairs; a limit at % filled %/200 t and a limit of 0.01 d. filled 0; 0 client write grants',
    v_rows, v_ports, v_goods, v_names, round(v_gap, 3),
    q_buy.total, q_sell.total, v_profit,
    q10.avg_price, q200.avg_price, v_sample,
    q10.avg_price, q_limit.units;
end $$;
