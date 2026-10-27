-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0255 — A CITY WANTS WHAT IT LACKS   (slice E6b of docs/CLOSED_ECONOMY.md §4b: every city wants 1–3 goods, pays ×2)
--        DARK: this file draws no want and changes no price. Lit later by the OWNER only:
--        `update public.world_config set value = 'true' where key = 'city_wants'`.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER (2026-10-26, row 214) ─────────────────────────────────────────────────────────────
--   "for each city, the trade good that city needs, and the city will pay much more money. this should be for every
--   city, 1~3 trade goods. First make it random? or any other method needed so that the economy circulates even further
--   on a closed gold."
--
-- ── WHAT THIS FILE DOES (§4b) ───────────────────────────────────────────────────────────────────
--   TABLES   public.city_wants (APPEND-ONLY, the draw's log: port, good, period, mult, cap, nearest_nm, weight) and
--            public.city_want_fills (port, good, period → units sold at the want price; the cap's tally). Server-only.
--   KNOBS    city_wants false (THE dark switch), want_mult 2.0, want_cap_pct 0.10, want_min_nm 1500,
--            want_regional_weight 1.5, want_period_seconds 1440 (= half a game-day: wants refresh twice a game-day).
--   NEW, server-only:
--     public.wants_lit()          city_wants AND economy_closed().                          (THE one gate)
--     public.want_period(ts)      floor(epoch / want_period_seconds).                       (the one clock of wants)
--     public.wants_draw(now)      lit, once a period: every harbour draws 1–3 wants (1, +1 if its `invested` ≥ the
--                                 median harbour's, +1 if ≥ the top quartile's). Candidates: goods it does NOT sell
--                                 (port_specialties), its culture trades, whose nearest maker is ≥ want_min_nm away
--                                 (port_goods.haul_nm), not wanted by it the period before. WEIGHTED random without
--                                 replacement (key = −ln(u) / weight, u from md5(port, period, good): every reader and a
--                                 re-run agree); weight = haul_nm × want_regional_weight when the region wants the good
--                                 (port_goods.demand > 1, 0066's regional appetite). cap = want_cap_pct × max stock.
--     world.want_left(port, good) THE one reader: the current period's (mult, units left at it), or no row.
--     world.city_wants_now(port)  {wants: [...]} for the city view, or null.
--   HUNKS (re-cut against the LIVE bodies; the quote's on top of 0254's):
--     world.quote_priced (4)      a SALE reads want_left once; the first `left` units are priced at mid × mult (a shelf
--                                 is split where the want runs out), the rest as before. Paid from the city purse by the
--                                 sale itself (city_pays): never minted; the empty-purse rule judges the whole total.
--     cmd.do_sell (1)             the units sold at the want price are added to the period's tally.
--     world.market (2)            a wanted good's row carries `wanted` (mult) and `wanted_left`; the payload carries
--                                 `wants` (the city's list). Both ABSENT when there is no want: dark, byte-identical.
--     public.tick_market_drift_each_port (1)   the drift job (every 10 min) calls wants_draw(now) once, first. Dark:
--                                 one gate read a run.
--   CLIENT: City view lists the city's wants ("Wanted ×2" / "수요 ×2"); a wanted good's quay row says it.
--
-- ── DECIDED BY DEFAULT (stated; the owner may reverse) ──────────────────────────────────────────
--   * Refresh: twice a game-day (want_period_seconds 1440), as briefed (§4b's table says "once a day"; the knob holds
--     either: 2880 = once a game-day, 86400 = once a real day).
--   * "Sold somewhere ≥ 1,500 nm away" = its NEAREST maker is ≥ 1,500 nm away (haul_nm), so a want is never next door.
--   * "Regional wants" = port_goods.demand > 1 (0066 seeded it from docs/REGIONAL_GOODS.md).
--   * The cap is per period (10 % of that good's max stock); past it the normal price. Two sales in the same instant may
--     each see the same units left (the tally is added after the sale): a small overshoot, never a refusal.
--   * The empty-purse rule shrinks the LOT, as for every sale; the want units are walked first, so a short purse buys
--     fewer units, premium first (not a separate "premium first" shrink).
--   * Stats → Cities' wants list is not in this slice: the city view and the quay rows show them (the log is the table).
--
-- ── WHAT IT SELF-ASSERTS (probe rows only; every probe a rolled-back sub-transaction, asserted) ───
--   (a) hunks reverse; ACL / volatility / definer / config unmoved; new functions server-only; tables server-only and
--       city_wants append-only; registry; walls 0.
--   (b) DARK, BYTE FOR BYTE: 18 Lisbon quotes, world.market(Lisbon), and a probe company's buy 30 / sell 30 — BEFORE and
--       AFTER the re-cut, same state; wants_draw writes 0; want_left empty.
--   (c) LIT: one draw a period (a second call writes 0); every harbour 1–3 wants, none it sells, none nearer than
--       1,500 nm, none its culture refuses; Lisbon's count follows its investment rank; the next period draws none of
--       Lisbon's previous wants; world.market shows them; a probe sale of a wanted good pays ≈ ×2 the dark quote, from
--       the purse (SELL flow = the total, no minted flow), and the tally takes the units; past the cap, the normal price.
--   (d) after: knob false, both tables empty.
-- ROLLBACK (forward): restore the OLD hunks below verbatim; drop the functions, tables and knobs.
-- VERSION: 0255 (renumbered from 0254 on 10-28: the reconcile follow-up #364 took 0253, E6 moved to 0254; the quote hunks sit on 0254's body).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '10min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('public.press_after(numeric,numeric,numeric,text,numeric,numeric)') is null then
    raise exception '0255 refuses: E6 (0254) is not in this world';
  end if;
  if to_regclass('public.city_wants') is not null then
    raise exception '0255 refuses: city_wants already exists';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0255(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 0. THE PRE-IMAGES (LF-normalised) ───────────────────────────────────────────────────────────
create temp table defs_before_0255 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('world.quote_priced(uuid,uuid,numeric,text,numeric,uuid,numeric,numeric,numeric,numeric)'),
               ('cmd.do_sell(uuid,jsonb)'),
               ('world.market(uuid)'),
               ('public.tick_market_drift_each_port()')) f(fn);

create temp table before_0255 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR') as lis,
       (select coalesce(max(f.id), 0) from public.treasury_flows f) as mark;

create temp table goods_0255 on commit drop as
select g.id, g.code, row_number() over (order by g.code) as n
  from public.goods g
  join public.port_goods pg on pg.good_id = g.id
  join public.ports p on p.id = pg.port_id
 where p.code = 'LIS' and p.kind = 'HARBOUR' and g.bulk <= 1 and pg.stock >= 200
   and public.port_offers(p.id, g.id) and not public.culture_refuses(p.culture, g.culture_mask)
 order by g.code limit 3;

do $$
begin
  if (select b.lis from before_0255 b) is null or (select count(*) from goods_0255) <> 3 then
    raise exception '0255 self-assert FAIL: no Lisbon, or not three goods it sells in stock';
  end if;
  perform 1 from public.port_goods pg, before_0255 b where pg.port_id = b.lis for update;   -- one market for both dark runs
end $$;

-- ── 1. THE DARK PROBE ───────────────────────────────────────────────────────────────────────────
create or replace function pg_temp.trader_0255()
returns jsonb
language plpgsql
as $$
declare
  v_p uuid;
  v_f uuid;
begin
  v_p := public.new_house(null, 'Casa da Procura 0255', 'PRT', 'LIS');
  select f.id into v_f from public.fleets f where f.player_id = v_p;
  perform public.credit(v_p, 'PROBE_0255', 1000000);
  return jsonb_build_object('p', v_p, 'f', v_f);
end $$;

create or replace function pg_temp.dark_0255()
returns jsonb
language plpgsql
as $$
declare
  v_lis  uuid := (select b.lis from before_0255 b);
  v_good uuid := (select g.id from goods_0255 g where g.n = 1);
  v_q    jsonb;
  v_m    jsonb;
  v      jsonb;
  v_f    uuid;
  v_buy  jsonb;
  v_sell jsonb;
begin
  begin
    select jsonb_agg(jsonb_build_array(g.code, s.side, n.qty, q.units, q.total, q.avg_price, q.end_stock, q.mid_total,
                                       q.tax_total, q.spread_total, q.haggle_saved) order by g.code, s.side, n.qty)
      into v_q
      from goods_0255 g
     cross join (values ('buy'), ('sell')) s(side)
     cross join (values (1), (30), (119)) n(qty)
     cross join lateral world.quote(v_lis, g.id, n.qty, s.side) q;
    v_m := world.market(v_lis);
    v := pg_temp.trader_0255();
    v_f := (v->>'f')::uuid;
    v_buy  := cmd.do_buy(v_f, jsonb_build_object('good', v_good, 'qty', 30));
    v_sell := cmd.do_sell(v_f, jsonb_build_object('good', v_good, 'qty', 30));
    raise exception using errcode = 'ZY255', message = jsonb_build_object(
      'quotes', v_q, 'market', v_m, 'buy', v_buy, 'sell', v_sell,
      'purse', (select pl.ducats from public.players pl where pl.id = (v->>'p')::uuid),
      'row', (select jsonb_build_array(pg.stock, pg.glut) from public.port_goods pg where pg.port_id = v_lis and pg.good_id = v_good))::text;
  exception when sqlstate 'ZY255' then
    return sqlerrm::jsonb;
  end;
end $$;

create temp table dark_old_0255 on commit drop as select pg_temp.dark_0255() as seen;

-- ── 2. THE TABLES AND THE KNOBS ─────────────────────────────────────────────────────────────────
create table public.city_wants (
  id         bigint generated always as identity primary key,
  port_id    uuid    not null references public.ports(id),
  good_id    uuid    not null references public.goods(id),
  period     bigint  not null,
  mult       numeric(6,3)  not null check (mult >= 1),
  cap        numeric(12,2) not null check (cap >= 0),
  nearest_nm numeric(8,1),
  weight     numeric not null check (weight > 0),
  created_at timestamptz not null default now(),
  unique (period, port_id, good_id)
);
create index city_wants_port_good on public.city_wants (port_id, good_id, period);

-- the walk's marker: the last want-period this market row was drawn in (written by wants_draw alone, beside the log).
-- world.quote_priced reads it in the row read it already makes, so a sale of a row never wanted costs nothing more.
alter table public.port_goods add column want_period bigint;
comment on column public.port_goods.want_period is
  '0255 (E6b): the last want-period this row was drawn as a city want (null = never). A MARKER for the quote walk only; '
  'the truth is public.city_wants, read through world.want_left. One writer: public.wants_draw.';
comment on table public.city_wants is
  '0255 (docs/CLOSED_ECONOMY.md §4b, E6b): the city wants, one row per (want-period, harbour, good) drawn by '
  'public.wants_draw — what the city pays `mult` × the sell price for, up to `cap` units a period. APPEND-ONLY (the '
  'draw''s log, public.forbid_mutation). Read through world.want_left / world.city_wants_now. Server-only.';
create trigger city_wants_append_only
  before update or delete on public.city_wants
  for each row execute function public.forbid_mutation();
alter table public.city_wants enable row level security;
revoke all on table public.city_wants from public, anon, authenticated;
revoke all on sequence public.city_wants_id_seq from public, anon, authenticated;

create table public.city_want_fills (
  port_id uuid    not null references public.ports(id),
  good_id uuid    not null references public.goods(id),
  period  bigint  not null,
  units   numeric(12,2) not null check (units >= 0),
  primary key (port_id, good_id, period)
);
comment on table public.city_want_fills is
  '0255 (E6b): the units a city has bought at its want price this period (the cap''s tally). One writer: cmd.do_sell. Server-only.';
alter table public.city_want_fills enable row level security;
revoke all on table public.city_want_fills from public, anon, authenticated;

insert into public.world_config (key, value, description) values
  ('city_wants', 'false'::jsonb,
   '0255 (docs/CLOSED_ECONOMY.md §4b, E6b): false = no city wants anything, prices byte for byte. true (with economy_closed) = every harbour draws 1-3 wanted goods each want-period and pays want_mult for them from its purse. Read only through public.wants_lit(). OWNER ONLY.'),
  ('want_mult', '2.0'::jsonb, '0255 (§4b): what a city pays for a wanted good, × the normal sell price (from its purse). Taken at the draw.'),
  ('want_cap_pct', '0.10'::jsonb, '0255 (§4b): the units a city buys at the want price per period, as a fraction of its max stock of that good.'),
  ('want_min_nm', '1500'::jsonb, '0255 (§4b): a good is wanted only where its nearest maker is at least this far (nm).'),
  ('want_regional_weight', '1.5'::jsonb, '0255 (§4b): the draw''s weight × this when the region wants the good (port_goods.demand > 1).'),
  ('want_period_seconds', '1440'::jsonb, '0255 (§4b): how often the wants are re-drawn, in seconds (1440 = twice a game-day).');

-- ── 3. THE FUNCTIONS ────────────────────────────────────────────────────────────────────────────
create function public.wants_lit()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0255: THE ONE gate of this slice: its own knob AND the closed economy.
  select coalesce((public.wc('city_wants'))::boolean, false) and public.economy_closed()
$$;

create function public.want_period(p_at timestamptz)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0255: THE ONE clock of the wants: which want-period an instant falls in.
  select floor(extract(epoch from p_at) / public.wc_num('want_period_seconds'))::bigint
$$;

create function world.want_left(p_port uuid, p_good uuid)
returns table (mult numeric, left_units numeric)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0255: THE ONE reader of a city's want for a good, now: its multiple and the units still bought at it this period.
  -- No row when not lit, not wanted, or not this period's.
  select w.mult, greatest(0, w.cap - coalesce(f.units, 0))
    from public.city_wants w
    left join public.city_want_fills f on f.port_id = w.port_id and f.good_id = w.good_id and f.period = w.period
   where public.wants_lit()
     and w.period = public.want_period(now()) and w.port_id = p_port and w.good_id = p_good
$$;

create function world.city_wants_now(p_port uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0255: the city's wants now, for world.market: {wants: [{good_id, code, name, mult, left}]}, or null when none.
  select case when count(*) > 0 then jsonb_build_object('wants', jsonb_agg(jsonb_build_object(
           'good_id', g.id, 'code', g.code, 'name', g.name, 'mult', w.mult,
           'left', greatest(0, w.cap - coalesce(f.units, 0))) order by g.code)) end
    from public.city_wants w
    join public.goods g on g.id = w.good_id
    left join public.city_want_fills f on f.port_id = w.port_id and f.good_id = w.good_id and f.period = w.period
   where public.wants_lit() and w.period = public.want_period(now()) and w.port_id = p_port
$$;

create function public.wants_draw(p_now timestamptz)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_period bigint;
  v_min    numeric;
  v_rw     numeric;
  v_mult   numeric;
  v_cap    numeric;
  v_med    numeric;
  v_q3     numeric;
  v_n      int;
begin
  -- 0255 (§4b): lit only, once a want-period. Every harbour draws 1–3 wanted goods (see the file header).
  if not public.wants_lit() then
    return 0;
  end if;
  v_period := public.want_period(p_now);
  if exists (select 1 from public.city_wants w where w.period = v_period) then
    return 0;
  end if;
  v_min  := public.wc_num('want_min_nm');
  v_rw   := public.wc_num('want_regional_weight');
  v_mult := public.wc_num('want_mult');
  v_cap  := public.wc_num('want_cap_pct');
  select percentile_cont(0.5) within group (order by coalesce(t.invested, 0)),
         percentile_cont(0.75) within group (order by coalesce(t.invested, 0))
    into v_med, v_q3
    from public.port_treasury t join public.ports p on p.id = t.port_id and p.kind = 'HARBOUR';

  insert into public.city_wants (port_id, good_id, period, mult, cap, nearest_nm, weight)
  select x.port_id, x.good_id, v_period, v_mult, x.cap, x.haul_nm, x.weight
    from (select c.*, row_number() over (partition by c.port_id order by c.key, c.good_id) as rn
            from (select pg.port_id, pg.good_id, pg.haul_nm,
                         round(v_cap * pg.stock_target, 2) as cap,
                         pg.haul_nm * case when pg.demand > 1 then v_rw else 1 end as weight,
                         -ln(r.u) / (pg.haul_nm * case when pg.demand > 1 then v_rw else 1 end) as key
                    from public.port_goods pg
                    join public.ports p on p.id = pg.port_id and p.kind = 'HARBOUR'
                    join public.goods g on g.id = pg.good_id
                   cross join lateral (select ((('x' || substr(md5(pg.port_id::text || ':' || v_period || ':' || pg.good_id::text), 1, 12))::bit(48)::bigint + 1)::numeric
                                               / 281474976710657) as u) r
                   where pg.haul_nm >= v_min
                     and coalesce(public.culture_refuses(p.culture, g.culture_mask), false) = false
                     and not exists (select 1 from public.port_specialties s where s.port_id = pg.port_id and s.good_id = pg.good_id)
                     and not exists (select 1 from public.city_wants w
                                      where w.period = v_period - 1 and w.port_id = pg.port_id and w.good_id = pg.good_id)) c) x
    join (select t.port_id, 1 + (coalesce(t.invested, 0) >= v_med)::int + (coalesce(t.invested, 0) >= v_q3)::int as k
            from public.port_treasury t) kk on kk.port_id = x.port_id
   where x.rn <= kk.k;
  get diagnostics v_n = row_count;
  update public.port_goods pg set want_period = v_period   -- the walk's marker (see the column)
    from public.city_wants w
   where w.period = v_period and pg.port_id = w.port_id and pg.good_id = w.good_id;
  return v_n;
end $$;

comment on function public.wants_lit() is '0255: city_wants AND economy_closed(). Server-only.';
comment on function public.want_period(timestamptz) is '0255: the want-period of an instant. Server-only.';
comment on function world.want_left(uuid, uuid) is '0255 (§4b): THE one reader of a city''s want for a good now. Server-only.';
comment on function world.city_wants_now(uuid) is '0255 (§4b): a city''s wants now, for world.market. Server-only.';
comment on function public.wants_draw(timestamptz) is '0255 (§4b): draws every harbour''s wants once a want-period. Called by the drift job.';
revoke all on function public.wants_lit() from public, anon, authenticated;
revoke all on function public.want_period(timestamptz) from public, anon, authenticated;
revoke all on function world.want_left(uuid, uuid) from public, anon, authenticated;
revoke all on function world.city_wants_now(uuid) from public, anon, authenticated;
revoke all on function public.wants_draw(timestamptz) from public, anon, authenticated;

-- ── 4. THE RE-CUTS (hunks sliced from the live bodies; each occurs once; each body reverses) ──────
create temp table hunks_0255 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0255 (fn, n, old, new) values
('world.quote_priced(uuid,uuid,numeric,text,numeric,uuid,numeric,numeric,numeric,numeric)', 0,
$h$  select pg.stock into v_stock from public.port_goods pg
$h$,
$h$  select pg.stock, pg.want_period into v_stock, v_wper from public.port_goods pg   -- 0255: + the want marker
$h$),
('world.quote_priced(uuid,uuid,numeric,text,numeric,uuid,numeric,numeric,numeric,numeric)', 1,
$h$  v_bidf   numeric;   -- 0122: the city's bid factor (1 dark)
$h$,
$h$  v_bidf   numeric;   -- 0122: the city's bid factor (1 dark)
  v_wmult  numeric;   -- 0255 (E6b): the city's want multiple for this good (a sale; none dark)
  v_wleft  numeric := 0;   -- 0255: the units still bought at it this period
  v_want   boolean := false;   -- 0255: units are still left at the want price (the walk tests this one flag)
  v_wper   bigint;    -- 0255: the row's want marker (port_goods.want_period), read with its stock
$h$),
('world.quote_priced(uuid,uuid,numeric,text,numeric,uuid,numeric,numeric,numeric,numeric)', 2,
$h$  -- §G.2: "Orders execute in 10-tun steps, each repricing, so a large order pays a genuinely worse
$h$,
$h$  -- 0255 (E6b): A CITY THAT WANTS THIS GOOD pays its want multiple for the first units it still buys at it this period
  -- (world.want_left, the one reader; read once a sale). Dark: no row, v_wleft 0, the walk below is as it was. Only a
  -- row ever drawn (its marker, read with the stock above) asks, so a sale of a good never wanted (every sale, dark) costs nothing.
  if p_side = 'sell' and v_wper is not null then
    select w.mult, w.left_units into v_wmult, v_wleft from world.want_left(p_port, p_good) w;
    v_wleft := coalesce(v_wleft, 0);
    v_want  := v_wleft > 0;
  end if;

  -- §G.2: "Orders execute in 10-tun steps, each repricing, so a large order pays a genuinely worse
$h$),
('world.quote_priced(uuid,uuid,numeric,text,numeric,uuid,numeric,numeric,numeric,numeric)', 3,
$h$    if p_side = 'buy' then
      v_unit := round(v_mid * (1 + v_tax + v_spread / 2), 2);
$h$,
$h$    if v_want then   -- 0255 (E6b): a sale's units at the want price; the shelf splits where the want runs out (a sale's mid
      -- does not read v_n, so the split may follow it). One flag test a shelf; dark it is false.
      v_n     := least(v_n, v_wleft);
      v_mid   := v_mid * v_wmult;
      v_wleft := v_wleft - v_n;
      v_want  := v_wleft > 0;
    end if;
    if p_side = 'buy' then
      v_unit := round(v_mid * (1 + v_tax + v_spread / 2), 2);
$h$),
('cmd.do_sell(uuid,jsonb)', 1,
$h$  on conflict (player_id, port_id, good_id, game_day) do update set qty = public.trade_daily.qty + excluded.qty;
$h$,
$h$  on conflict (player_id, port_id, good_id, game_day) do update set qty = public.trade_daily.qty + excluded.qty;
  -- 0255 (E6b): the units this sale took at the city's want price count against the period's cap
  insert into public.city_want_fills (port_id, good_id, period, units)
  select f.port_id, g.id, public.want_period(now()), least(q.units, w.left_units)
    from world.want_left(f.port_id, g.id) w
   where w.left_units > 0
  on conflict (port_id, good_id, period) do update set units = public.city_want_fills.units + excluded.units;
$h$),
('world.market(uuid)', 1,
$h$        'offered', public.port_offers(pg.port_id, pg.good_id))
$h$,
$h$        'offered', public.port_offers(pg.port_id, pg.good_id))
        -- 0255 (E6b): a good the city wants now carries its multiple and the units left at it (absent otherwise)
        || coalesce((select jsonb_build_object('wanted', w.mult, 'wanted_left', w.left_units)
                       from world.want_left(pg.port_id, pg.good_id) w), '{}'::jsonb)
$h$),
('world.market(uuid)', 2,
$h$        'next_change_at', public.next_drift_change_at(v_now))));
$h$,
$h$        'next_change_at', public.next_drift_change_at(v_now)))
    -- 0255 (E6b): the city's wants now, {wants: [...]} (absent when it wants nothing)
    || coalesce(world.city_wants_now(p_port), '{}'::jsonb));
$h$),
('public.tick_market_drift_each_port()', 1,
$h$begin
  for p in select po.id, po.code from public.ports po order by po.id loop
$h$,
$h$begin
  -- 0255 (E6b): the city wants, drawn once a want-period (public.wants_draw), before the harbours drift. Dark: one
  -- gate read a run. A failure is warned and the next run draws them; it never stops the drift.
  begin
    perform public.wants_draw(v_now);
  exception when others then
    raise warning 'tick_market_drift_each_port: the city wants were not drawn (SQLSTATE %: %); the next run draws them',
      sqlstate, sqlerrm;
  end;
  commit;
  for p in select po.id, po.code from public.ports po order by po.id loop
$h$);

create or replace function pg_temp.recut_0255(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := (select def from defs_before_0255 where fn = p_fn);
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0255 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0255(v_def, h.old);
    if v_n <> 1 then
      raise exception '0255 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, h.fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0255(fn) from defs_before_0255 order by fn;

-- ── 5. THE SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
do $$
declare
  b       record;
  v_d record; v_h record; v_pp record; v_def text;
  v_old   jsonb;
  v_new   jsonb;
  v_n     int;
  v_k     int;
  v_bad   int;
  v_med   numeric;
  v_q3    numeric;
  v_i     numeric;
  v_per   bigint;
  v_next  timestamptz;
  v_w     record;
  v       jsonb;
  v_f     uuid;
  v_dark  record;
  v_lit   record;
  v_sale  jsonb;
  v_m     jsonb;
  v_left  numeric;
  v_qty   numeric;
begin
  select * into b from before_0255;

  -- (a) THE RE-CUTS reverse; ACL / volatility / definer / config unmoved; new functions and tables server-only
  for v_d in select * from defs_before_0255 loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0255 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0255(v_def, v_h.new) <> 1 then
        raise exception '0255 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0255 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
      into v_pp from pg_proc p where p.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0255 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;
  if exists (select 1 from (values ('public.wants_lit()'), ('public.want_period(timestamptz)'), ('world.want_left(uuid,uuid)'),
                                   ('world.city_wants_now(uuid)'), ('public.wants_draw(timestamptz)')) f(fn)
              where has_function_privilege('authenticated', f.fn, 'execute') or has_function_privilege('anon', f.fn, 'execute')) then
    raise exception '0255 self-assert FAIL: a client role can execute one of the new functions';
  end if;
  if has_table_privilege('authenticated', 'public.city_wants', 'select') or has_table_privilege('anon', 'public.city_wants', 'select')
     or has_table_privilege('authenticated', 'public.city_want_fills', 'select') or has_table_privilege('anon', 'public.city_want_fills', 'select') then
    raise exception '0255 self-assert FAIL: a client role can read a wants table';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> b.entry_points then
    raise exception '0255 self-assert FAIL: the registry moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0255 self-assert FAIL: a wall moved';
  end if;

  -- (b) DARK, BYTE FOR BYTE
  if public.wants_lit() then
    raise exception '0255 self-assert FAIL: city_wants is not dark';
  end if;
  v_old := (select d.seen from dark_old_0255 d);
  v_new := pg_temp.dark_0255();
  if v_old is null or v_new is distinct from v_old or jsonb_array_length(v_new->'quotes') <> 18
     or (v_new->'sell'->>'qty')::numeric <> 30 or v_new->'market'->'wants' is not null then
    raise exception '0255 self-assert FAIL: dark, the quotes, the market or the probe trade are not the pre-image''s: new % old %', v_new, v_old;
  end if;
  begin
    if public.wants_draw(now()) <> 0 or exists (select 1 from public.city_wants) then
      raise exception '0255 self-assert FAIL: wants were drawn while dark';
    end if;
    raise exception using errcode = 'ZY255', message = 'dark ok';
  exception when sqlstate 'ZY255' then
    null;
  end;

  -- (c) LIT (a rolled-back sub-transaction)
  begin
    update public.world_config set value = 'true'::jsonb where key in ('economy_closed', 'city_wants', 'city_treasury_enabled');
    if not public.wants_lit() then
      raise exception '0255 self-assert FAIL: wants_lit() is false with both switches on';
    end if;
    v_per := public.want_period(now());
    v_n := public.wants_draw(now());
    if v_n < 1 or public.wants_draw(now()) <> 0 then
      raise exception '0255 self-assert FAIL: the draw wrote % row(s), or drew twice in one period', v_n;
    end if;
    -- every harbour 1-3 wants; none it sells; none nearer than want_min_nm; none its culture refuses
    select count(*) into v_bad
      from (select p.id, (select count(*) from public.city_wants w where w.period = v_per and w.port_id = p.id) as n
              from public.ports p where p.kind = 'HARBOUR') x
     where x.n > 3;
    if v_bad <> 0 or exists (select 1 from public.city_wants w join public.port_specialties s on s.port_id = w.port_id and s.good_id = w.good_id where w.period = v_per)
       or exists (select 1 from public.city_wants w where w.period = v_per and (w.nearest_nm < public.wc_num('want_min_nm') or w.mult <> 2.0))
       or exists (select 1 from public.city_wants w join public.ports p on p.id = w.port_id join public.goods g on g.id = w.good_id
                   where w.period = v_per and public.culture_refuses(p.culture, g.culture_mask)) then
      raise exception '0255 self-assert FAIL: a harbour drew more than 3 wants, or a want it sells, is near, or its culture refuses';
    end if;
    -- Lisbon's count follows its investment rank
    select percentile_cont(0.5) within group (order by coalesce(t.invested, 0)), percentile_cont(0.75) within group (order by coalesce(t.invested, 0))
      into v_med, v_q3 from public.port_treasury t join public.ports p on p.id = t.port_id and p.kind = 'HARBOUR';
    select coalesce(t.invested, 0) into v_i from public.port_treasury t where t.port_id = b.lis;
    v_k := 1 + (v_i >= v_med)::int + (v_i >= v_q3)::int;
    if (select count(*) from public.city_wants w where w.period = v_per and w.port_id = b.lis) <> v_k then
      raise exception '0255 self-assert FAIL: Lisbon drew % wants, its rank says %', (select count(*) from public.city_wants w where w.period = v_per and w.port_id = b.lis), v_k;
    end if;
    -- the market shows them
    v_m := world.market(b.lis);
    if jsonb_array_length(coalesce(v_m->'wants', '[]'::jsonb)) <> v_k
       or (v_m->'wants'->0->>'mult')::numeric <> 2.0 then
      raise exception '0255 self-assert FAIL: world.market does not list Lisbon''s % wants: %', v_k, v_m->'wants';
    end if;
    -- a probe sale of a wanted good: ≈ ×2 the dark quote, from the purse, the tally takes the units
    select w.good_id, g.code, w.cap into v_w
      from public.city_wants w join public.goods g on g.id = w.good_id
     where w.period = v_per and w.port_id = b.lis order by g.code limit 1;
    v_qty := least(10, floor(v_w.cap));
    if v_qty < 1 then
      raise exception '0255 self-assert FAIL: Lisbon''s first want has no room (cap %)', v_w.cap;
    end if;
    update public.port_treasury set reserve = 0 where port_id = b.lis;
    perform public.treasury_post(b.lis, 'PROBE_0255', 10000000, null, null, true);
    v := pg_temp.trader_0255();
    v_f := (v->>'f')::uuid;
    perform public.fleet_load(v_f, v_w.code, v_qty, 25);
    update public.world_config set value = 'false'::jsonb where key = 'city_wants';
    select * into v_dark from world.quote(b.lis, v_w.good_id, v_qty, 'sell', null, v_f);
    update public.world_config set value = 'true'::jsonb where key = 'city_wants';
    select * into v_lit from world.quote(b.lis, v_w.good_id, v_qty, 'sell', null, v_f);
    if not (v_lit.total between 1.9 * v_dark.total and 2.1 * v_dark.total + 2) then
      raise exception '0255 self-assert FAIL: the want price is not x2: lit % dark %', v_lit.total, v_dark.total;
    end if;
    v_sale := cmd.do_sell(v_f, jsonb_build_object('good', v_w.good_id, 'qty', v_qty));
    if (v_sale->>'total')::bigint <> v_lit.total
       or (select f.units from public.city_want_fills f where f.port_id = b.lis and f.good_id = v_w.good_id and f.period = v_per) <> v_qty
       or (select sum(-tf.ducats) from public.treasury_flows tf where tf.id > b.mark and tf.port_id = b.lis and tf.kind = 'SELL') <> v_lit.total
       or exists (select 1 from public.treasury_flows tf where tf.id > b.mark and tf.ducats > 0 and tf.kind in ('IMPORT_DEMAND', 'EARNINGS', 'SEED', 'GRANT')) then
      raise exception '0255 self-assert FAIL: the sale % did not pay the want price from the purse, or the tally is wrong', v_sale;
    end if;
    -- past the cap: the normal price (the tally planted full)
    update public.city_want_fills set units = v_w.cap where port_id = b.lis and good_id = v_w.good_id and period = v_per;
    select w.left_units into v_left from world.want_left(b.lis, v_w.good_id) w;
    select * into v_lit from world.quote(b.lis, v_w.good_id, v_qty, 'sell', null, v_f);
    update public.world_config set value = 'false'::jsonb where key = 'city_wants';
    select * into v_dark from world.quote(b.lis, v_w.good_id, v_qty, 'sell', null, v_f);
    update public.world_config set value = 'true'::jsonb where key = 'city_wants';
    if v_left <> 0 or v_lit.total <> v_dark.total then
      raise exception '0255 self-assert FAIL: past the cap the price is not the normal one (left %, % vs %)', v_left, v_lit.total, v_dark.total;
    end if;
    -- the next period draws none of Lisbon's wants of this one
    v_next := to_timestamp((v_per + 1) * public.wc_num('want_period_seconds'));
    if public.wants_draw(v_next) < 1
       or exists (select 1 from public.city_wants a join public.city_wants c on c.port_id = a.port_id and c.good_id = a.good_id
                   where a.period = v_per and c.period = v_per + 1) then
      raise exception '0255 self-assert FAIL: the next period drew nothing, or re-drew a good wanted the period before';
    end if;
    raise exception using errcode = 'ZY255', message = 'lit ok';
  exception when sqlstate 'ZY255' then
    null;
  end;

  -- (d) the probe rolled back
  if public.wants_lit() or exists (select 1 from public.city_wants) or exists (select 1 from public.city_want_fills)
     or exists (select 1 from public.port_goods pg where pg.want_period is not null)
     or exists (select 1 from public.players pl where pl.company_name = 'Casa da Procura 0255') then
    raise exception '0255 self-assert FAIL: the lit probe left something behind';
  end if;

  raise notice '0255 self-assert ok: A CITY WANTS WHAT IT LACKS (dark). quote_priced (4 hunks), do_sell (1), world.market (2), tick_market_drift_each_port (1) re-cut, each reversed, ACL unmoved; city_wants (append-only) and city_want_fills server-only; five server-only functions; registry unchanged; walls 0. DARK: 18 Lisbon quotes, world.market(Lisbon) and a probe buy 30 / sell 30 equal the pre-image''s; no draw. LIT (rolled back): one draw a period; every harbour <= 3 wants, none it sells, none nearer than 1,500 nm, none its culture refuses; Lisbon''s count = its investment rank (%); market lists them; a probe sale of a wanted good paid x2 from the purse (no minted flow), the tally took it; past the cap the normal price; the next period re-draws none of the last.', v_k;
end $$;
