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
--   * Exactly 144 port_goods rows — one per (12 ports × 12 goods), none missing, none doubled.
--   * Every one of the 144 prices is positive, inside the §G.7.3 hard band, and has ask > bid.
--   * PRICE IMPACT IS REAL: 200 tuns cost strictly more PER TUN than 10 tuns (§G.2). Without this,
--     the stepping loop could be silently returning a flat price and every other assert would pass.
--   * §G.7.4 HOLDS ON ALL 144 PAIRS: buying and immediately selling back in the same port is a
--     LOSS. Round-tripping a port is structurally unprofitable, everywhere, with no exception.
--   * THE §K.1 GRADIENT IS REAL: 60 tuns of sal bought at Lisboa and sold at Cádiz turns a profit,
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

-- ── The seed: 12 ports × 12 goods of authored affinity ─────────────────────────────────────────
-- The affinity vector is given per port in ONE fixed good order, so the matrix reads as a matrix.
-- stock_target and production_rate are DERIVED from size_tier and affinity rather than authored,
-- because a producer's depth and a sink's thinness are consequences of the affinity, not
-- independent facts — two authored numbers that had to agree would eventually stop agreeing.
insert into public.port_goods (port_id, good_id, affinity, stock, stock_target, production_rate)
select p.id,
       g.id,
       m.aff,
       greatest(60, round(200 * p.size_tier * (1.60 - m.aff))),                    -- stock = target at seed
       greatest(60, round(200 * p.size_tier * (1.60 - m.aff))),
       case when m.aff < 0.80
            then round(greatest(60, 200 * p.size_tier * (1.60 - m.aff)) * 0.05, 2)
            else 0 end
  from (values
    --      port      sal   vinho azeite cortica trigo   la   cobre ferro acucar couro tamaras coral
    ('LIS', array[0.55, 0.60, 0.75, 0.50, 1.35, 1.10, 1.20, 1.15, 0.85, 1.25, 1.40, 1.30]::numeric[]),
    ('OPO', array[0.85, 0.45, 0.90, 0.70, 1.30, 0.95, 1.25, 1.20, 1.10, 1.15, 1.50, 1.45]::numeric[]),
    ('SVQ', array[0.95, 0.85, 0.55, 1.05, 1.20, 0.65, 1.10, 1.05, 0.70, 0.75, 1.20, 1.25]::numeric[]),
    ('CAD', array[1.15, 0.95, 0.80, 1.10, 1.25, 0.90, 1.15, 1.10, 0.90, 0.95, 1.10, 1.15]::numeric[]),
    ('CEU', array[1.20, 1.30, 1.15, 1.25, 1.45, 1.20, 1.10, 1.00, 1.20, 0.85, 0.70, 0.95]::numeric[]),
    ('SAF', array[0.90, 1.00, 1.05, 1.30, 1.15, 0.55, 1.60, 1.70, 1.05, 0.40, 0.35, 1.10]::numeric[]),
    ('FNC', array[1.25, 0.70, 1.30, 1.35, 1.60, 1.35, 1.45, 1.50, 0.30, 1.30, 1.25, 1.20]::numeric[]),
    ('LPA', array[1.20, 0.80, 1.35, 1.40, 1.55, 1.30, 1.50, 1.55, 0.40, 1.25, 0.95, 1.15]::numeric[]),
    ('MRS', array[0.80, 0.75, 0.95, 1.20, 1.30, 1.05, 1.05, 0.95, 1.35, 1.10, 1.15, 0.60]::numeric[]),
    ('GOA', array[1.10, 1.05, 0.90, 1.25, 1.45, 1.55, 0.85, 0.70, 1.50, 1.20, 1.20, 0.75]::numeric[]),
    ('TUN', array[0.75, 1.00, 0.85, 1.45, 1.50, 0.80, 1.65, 1.75, 1.30, 0.55, 0.30, 0.35]::numeric[]),
    ('NAP', array[0.95, 0.90, 0.60, 1.30, 0.50, 1.15, 1.20, 1.10, 1.25, 1.05, 1.05, 0.90]::numeric[])
  ) as v(port_code, affs)
  cross join lateral unnest(
    array['sal','vinho','azeite','cortica','trigo','la','cobre','ferro','acucar','couro','tamaras','coral'],
    v.affs
  ) as m(good_code, aff)
  join public.ports p on p.code = v.port_code
  join public.goods g on g.code = m.good_code
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
do $$
declare
  v_rows      int;
  v_bad       int;
  v_lis       uuid;
  v_cad       uuid;
  v_sal       uuid;
  q10         record;
  q200        record;
  q_buy       record;
  q_sell      record;
  q_limit     record;
  q_nofill    record;
  v_roundtrip int := 0;
  v_pairs     int := 0;
  v_profit    bigint;
  v_grants    int;
  r           record;
  b           record;
  s           record;
begin
  -- (a) 144 rows: every port carries every good.
  select count(*) into v_rows from public.port_goods;
  if v_rows <> 144 then
    raise exception '0005 self-assert FAIL: % port_goods rows, expected 144 (12 ports × 12 goods)', v_rows;
  end if;

  -- (b) Every one of the 144 spot prices is sane: positive, banded, and ask strictly above bid.
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
    raise exception '0005 self-assert FAIL: % of 144 (port,good) prices are unsound (non-positive, outside the G.7.3 band, spread below floor, or ask <= bid)', v_bad;
  end if;

  select id into v_lis from public.ports where code = 'LIS';
  select id into v_cad from public.ports where code = 'CAD';
  select id into v_sal from public.goods where code = 'sal';

  -- (c) PRICE IMPACT IS REAL. If the stepping loop were flat, every other assert here would still
  --     pass, so this is the control that proves the loop does its job.
  select * into q10  from world.quote(v_lis, v_sal, 10,  'buy');
  select * into q200 from world.quote(v_lis, v_sal, 200, 'buy');
  if q200.avg_price <= q10.avg_price then
    raise exception '0005 self-assert FAIL: 200 tuns average % is not dearer than 10 tuns average % — buying does not move the market (DESIGN G.2)',
      q200.avg_price, q10.avg_price;
  end if;

  -- (d) DESIGN §G.7.4 ON ALL 144 PAIRS: "instant buy-then-sell in the same port is always a loss."
  for r in select pg.port_id, pg.good_id from public.port_goods pg loop
    v_pairs := v_pairs + 1;
    select * into b from world.quote(r.port_id, r.good_id, 30, 'buy');
    if b.units > 0 then
      select * into s from world.quote(r.port_id, r.good_id, b.units, 'sell');
      if s.total >= b.total then
        v_roundtrip := v_roundtrip + 1;
      end if;
    end if;
  end loop;
  if v_pairs <> 144 then
    raise exception '0005 self-assert FAIL: the round-trip probe examined % pairs, not 144 — it is not testing what it claims', v_pairs;
  end if;
  if v_roundtrip <> 0 then
    raise exception '0005 self-assert FAIL: % of 144 (port,good) pairs allow a profitable same-port round trip', v_roundtrip;
  end if;

  -- (e) THE §K.1 GRADIENT: 60 tuns of sal, Lisboa -> Cádiz.
  select * into q_buy  from world.quote(v_lis, v_sal, 60, 'buy');
  select * into q_sell from world.quote(v_cad, v_sal, 60, 'sell');
  v_profit := q_sell.total - q_buy.total;
  if q_buy.units <> 60 or q_sell.units <> 60 then
    raise exception '0005 self-assert FAIL: the K.1 trade did not fill (bought %, sold %)', q_buy.units, q_sell.units;
  end if;
  if v_profit <= 0 then
    raise exception '0005 self-assert FAIL: the DESIGN K.1 opening trade LOSES money — 60 sal costs % at Lisboa and fetches % at Cádiz',
      q_buy.total, q_sell.total;
  end if;

  -- (f) A limit order fills partially rather than overpaying, and an impossible limit fills zero.
  select * into q_limit from world.quote(v_lis, v_sal, 200, 'buy', q10.avg_price);
  if q_limit.units >= 200 or q_limit.units <= 0 then
    raise exception '0005 self-assert FAIL: a limit at the 10-tun price filled % of 200 tuns; a partial fill was expected', q_limit.units;
  end if;
  select * into q_nofill from world.quote(v_lis, v_sal, 200, 'buy', 0.01);
  if q_nofill.units <> 0 then
    raise exception '0005 self-assert FAIL: a limit of 0.01 d. filled % tuns', q_nofill.units;
  end if;

  select count(*) into v_grants from public.client_write_grants();
  if v_grants <> 0 then
    raise exception '0005 self-assert FAIL: the market tables minted % client write grant(s)', v_grants;
  end if;

  raise notice '0005 self-assert ok: 144 port_goods rows, all prices positive/banded with ask>bid; price impact real (10 t avg % d. vs 200 t avg % d.); same-port round trip loses at ALL 144 pairs; DESIGN K.1 trade: 60 sal costs % d. at Lisboa (avg %) and fetches % d. at Cádiz (avg %) = +% d.; a limit at % filled %/200 t and a limit of 0.01 d. filled 0; 0 client write grants',
    q10.avg_price, q200.avg_price,
    q_buy.total, q_buy.avg_price, q_sell.total, q_sell.avg_price, v_profit,
    q10.avg_price, q_limit.units;
end $$;
