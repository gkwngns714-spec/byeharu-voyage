-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0212 — A PRICE TICKS WHILE YOU WATCH  (the market's mood: a small live tick on top of the one price)
-- NOT FOR DEPLOY (WIP 2026-10-19): the self-assert passed once locally (PGlite, on the 0208 prefix); the client half,
-- the server/client parity spec, the prod hunk check and the performance/arrivals measurements are NOT done.
--        LANDS DARK: price_tick_on = false, and every price is bit-identical to 0208's (asserted)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER, VERBATIM (2026-10-19) ────────────────────────────────────────────────────────────
--   "would it be possible, for the prices to be like of stock market? like it moves like real-time stock."
--
-- ── WHAT SAYS THE OPPOSITE TODAY ────────────────────────────────────────────────────────────────
-- A price moves only at a drift slot (public.tick_market_drift, every drift_slot_seconds = 15 min) and when a
-- trade walks the stock. Between two slots every figure on the desk stands still. The chart is a record of
-- 15-minute points (public.tick_price_snapshot), the watchlist a record too (world.watchlist, 0171).
--
-- ── THE TERM: the TICK (players read it as "market mood") ──────────────────────────────────────
-- Every market (port × good) gets a multiplicative factor that is a PURE function of (the market, the time
-- bucket): no row is written per tick. The server computes it inside the ONE price authority; the client runs
-- the SAME integer arithmetic (src/domain/market/tick.ts) and tests/priceTick.spec.ts holds the two equal on
-- 1,000 (market, instant) pairs, to the ppm and to the cent.
--     mid = round( round(banded × haul × (1 − glut), 4) × tick, 4 )                 world.mid_from_terms
--     tick = round(ppm / 1e6, 6),  ppm = public.price_tick_ppm(seed, bucket, the good's tier terms)
--     bucket = floor(epoch / price_tick_seconds)        seed = from the first 24 bits of each uuid
--     ppm = 1e6 + slow + fast + jitter, all integer (no sine: libm and V8 may differ in the last bit):
--       slow    the rarity's amplitude × two value-noise octaves (lattice steps p1, p2 buckets, 65/35)
--       fast    a small octave a minute long        jitter  a fresh draw every bucket
-- The inner round lets a client tick a served `calm` (the 4-dp price with the tick at 1, world.mid_calm)
-- exactly as the server would; with tick = 1 it is the old expression to the digit (round(x,4) × 1 = itself).
--
-- ── NO FREE MONEY — the law the rule is DERIVED from (public.price_tick_rule_derive) ─────────────
-- A buy at one tick and a sale at another in the same port must never pay. The thinnest round trip any
-- trader can reach is the port fee at its floor, with every fair on (buff_bonus_cap_pct) and every shave
-- stacked to the haggle floor:  s_min = spread_floor × (1 − buff_cap) × haggle_spread_floor_frac = 0.2 % today.
-- The rule spends 80 % of it as the BUDGET (1,600 ppm): the tick may never move more than that between any two
-- instants within price_tick_window_seconds (300 s). Jitter and the fast octave take a quarter each (±200
-- ppm); the slow octaves' lattice steps are then made long enough that their move over the window fits the
-- other half: p1 = ceil(2 × amp × window_buckets × 158 / (100 × slow budget)). A bigger amplitude is a SLOWER
-- wave; the one volatility knob scales the amplitude, so it scales the wave's length too and never the
-- short-horizon swing. Proven below over every pair of instants within the window on a sample of markets of
-- every rarity, at the thinnest spread, through world.price_sides (the sides' one leaf) — and the positive
-- control proves the check CAN fail (a spread a quarter as thin does pay).
--
-- ── WHERE IT LIVES (one authority each) ─────────────────────────────────────────────────────────
-- (1) knobs: price_tick_on (false — the kill switch), price_tick_seconds 15, price_tick_window_seconds 300,
--     price_tick_volatility 1 (the ONE overall knob), price_tick_amplitude by rarity (common 1.5 %, uncommon
--     2.5 %, rare 3.5 %, exotic 5 %), and price_tick_rule — DERIVED, written only by public.price_tick_refresh()
--     (call it after changing any of the four above or the spread knobs; this file calls it once).
-- (2) public.price_tick_goods (good → its rarity tier): a stored copy of public.good_rarity, which scans every
--     port specialty (0.5 ms) and so cannot be on the quote's path. Written here; the world guard holds it equal.
-- (3) public.price_tick_ppm (the integer leaf), public.price_tick_seed, public.price_tick_rule_derive,
--     public.price_tick_refresh, public.price_tick_rule_now (the stored rule + the switch, what payloads serve),
--     public.price_tick(port, good, at, rule) (1 dark), world.mid_calm (the price with the tick at 1).
-- (4) world.mid_from_terms gains p_tick after p_glut (the 15-argument form; the 14-argument form is DROPPED once
--     its callers are re-cut — 0194's pattern). world.mid_terms gains OUT m_tick (one knob read dark).
-- (5) Re-cut by hunks sliced from the live bodies (each occurs once; each reverses to its pre-image; ACL,
--     owner, volatility, definer and config kept): world.mid_from_terms, world.mid_terms, world.mid_price (1),
--     world.quote_priced (2), public.price_path (4: the tick at each step's instant — k = 0 is world.price's
--     own), world.market (3: the range carries the tick), world.price_why (1: the term `mood`),
--     world.price_outlook (1: serves `tick` and `calm`), world.watchlist (3: serves `tick`, and lit, `calm`).
-- So everything that prices — every quote, cmd.do_buy / do_sell, the merchants' planner, world.good_board's
-- Best trade, the outlook, the record (tick_price_snapshot writes world.mid_price) — reads the tick through
-- world.mid_terms, and no second price path exists.
--
-- ── WHAT IT DELIBERATELY DOES NOT DO ────────────────────────────────────────────────────────────
-- Write anything per tick. Touch the drift, the stock, the glut, the band, the haul, the spread, the tax, a
-- purse, any grant, or any client-callable surface (no new RPC: the rule rides on world.watchlist and
-- world.price_outlook). Light itself: price_tick_on stays false until a measured window.
-- DECIDED BY DEFAULT (the owner may reverse each): the tick is predictable — a client can compute it ahead,
-- as it can read the outlook ahead; inside the window that is worth nothing (the law), over hours the slow
-- wave is a mood a patient trader can plan for, as the drift's mean reversion already is. A game day's
-- mean is NOT 1 for the slow wave (its lattice steps are hours long, by the law); it is 1 on average across
-- markets and over days. The outlook carries the tick at each step's instant (it is known), and world.market's
-- range carries the tick of this instant. The watchlist's `mid` stays the record's; `calm` (lit) is now's.
--
-- ── THE PROOF (only this file's own rows; probes in sub-blocks rolled back whole) ──────────────
-- (a) knobs, the stored rule = the derived rule, the law analytically per tier, every good's tier stored;
-- (b) DARK: 120 sampled mids, 480 quotes, 12 paths and 6 market ranges = the pre-image tree exactly; why's
--     mood term 1; the payloads carry the rule with on = false and no calm;
-- (c) LIT (the switch set inside a rolled-back block): mid = round(old mid × tick, 4) on every sampled row;
--     the path's k = 0 and the outlook's first point = world.price to the cent (mid / ask / bid); why carries
--     the mood and its terms multiply back to the mid; the range carries it; mid_calm = the old mid;
--     NO FREE MONEY over every pair within the window on 40 markets of every tier for an hour, at the thinnest
--     spread, and the positive control; |tick − 1| bounded; one bucket's step ≤ the budget;
--     a limit set at the calm price refuses E_PRICE_LIMIT when the tick has moved past it, and fills at the
--     ticked price (a probe company at Lisbon);
-- (d) every body reverses to its pre-image; the callers of the expression are the five; the old form is gone;
--     ACL / owner / volatility / definer / config unmoved; the new functions are server-only; walls.
-- (e) timings (notice only): world.quote, world.mid_price, world.watchlist, world.price_outlook, 8 calls
--     each in one session, dark and lit.
-- ── LOCKS AND TIME ──────────────────────────────────────────────────────────────────────────────
-- Catalogue-only CREATE / DROP FUNCTION, one small new table, five knobs. No UPDATE of the market.
-- ROLLBACK: price_tick_on false (every price the pre-image's again, bit for bit); or a forward slice restoring
-- the bodies from these hunks.
-- VERSION: 0212 at writing (prod head 0208; 0209–0211 in flight). It RENUMBERS to the prod head + 1 at push.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  if exists (select 1 from public.world_config where key like 'price_tick%') then
    raise exception '0212 refuses: a price_tick knob already exists — this has been applied once';
  end if;
  if to_regprocedure('world.mid_from_terms(numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, integer, numeric, numeric, numeric, numeric)') is null
     or not exists (select 1 from public.world_config where key = 'goods_price_level') then
    raise exception '0212 refuses: 0194''s 14-argument expression or 0208 is not in this world';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0212(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 1. THE PRE-IMAGES ─────────────────────────────────────────────────────────────────────────
create temp table defs_before_0212 on commit drop as
select f.fn, f.ord,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg,
       (select p.proowner from pg_proc p where p.oid = f.fn::regprocedure) as owner
  from (values (1, 'world.mid_from_terms(numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, integer, numeric, numeric, numeric, numeric)'),
               (2, 'world.mid_terms(uuid, uuid)'),
               (3, 'world.mid_price(uuid, uuid, numeric)'),
               (4, 'world.quote_priced(uuid, uuid, numeric, text, numeric, uuid, numeric, numeric, numeric, numeric)'),
               (5, 'public.price_path(uuid, uuid, integer)'),
               (6, 'world.market(uuid)'),
               (7, 'world.price_why(uuid, uuid)'),
               (8, 'world.price_outlook(uuid, uuid, integer, text)'),
               (9, 'world.watchlist(uuid)')) f(ord, fn);

do $$
begin
  if (select count(*) from defs_before_0212 where def is not null) <> 9 then
    raise exception '0212 self-assert FAIL: % of the 9 bodies found', (select count(*) from defs_before_0212 where def is not null);
  end if;
  if (select string_agg(n.nspname || '.' || p.proname, ',' order by n.nspname || '.' || p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('world', 'public', 'cmd', 'voyage') and p.prosrc like '%mid_from_terms(%')
     is distinct from 'public.price_path,world.market,world.mid_price,world.quote_priced' then
    raise exception '0212 self-assert FAIL: the callers of world.mid_from_terms are %, not the four this file re-cuts',
      (select string_agg(n.nspname || '.' || p.proname, ',' order by n.nspname || '.' || p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname in ('world', 'public', 'cmd', 'voyage') and p.prosrc like '%mid_from_terms(%');
  end if;
end $$;

-- THE OLD TREE the proofs compare against: the 14-argument expression and its row-level callers, as pg_temp
-- copies calling it (world.mid_terms' new OUT column is a field they never read).
do $$
declare
  v_def text;
  r     record;
begin
  select def into v_def from defs_before_0212 where ord = 1;
  v_def := replace(v_def, 'CREATE OR REPLACE FUNCTION world.mid_from_terms(', 'CREATE OR REPLACE FUNCTION pg_temp.mft_old_0212(');
  if strpos(v_def, 'FUNCTION pg_temp.mft_old_0212(') = 0 then
    raise exception '0212 self-assert FAIL: the old copy of mid_from_terms was not made from the pre-image';
  end if;
  execute v_def;
  for r in select * from (values (3, 'world.mid_price(', 'pg_temp.mid_price_old_0212('),
                                 (4, 'world.quote_priced(', 'pg_temp.quote_priced_old_0212('),
                                 (5, 'public.price_path(', 'pg_temp.price_path_old_0212(')) x(ord, f, t) loop
    select def into v_def from defs_before_0212 where ord = r.ord;
    v_def := replace(v_def, 'CREATE OR REPLACE FUNCTION ' || r.f, 'CREATE OR REPLACE FUNCTION ' || r.t);
    v_def := replace(v_def, 'world.mid_from_terms(', 'pg_temp.mft_old_0212(');
    if strpos(v_def, 'FUNCTION ' || r.t) = 0 or strpos(v_def, 'world.mid_from_terms(') > 0 then
      raise exception '0212 self-assert FAIL: the old copy of % was not made from the pre-image', r.f;
    end if;
    execute v_def;
  end loop;
end $$;

-- ── 2. THE KNOBS, THE TIER TABLE AND THE TICK'S OWN FUNCTIONS ─────────────────────────────────
insert into public.world_config (key, value, description) values
  ('price_tick_on', to_jsonb(false),
   '0212: THE KILL SWITCH of the live price tick (the market''s mood). false: every price is exactly 0208''s; true: '
   'world.mid_terms multiplies in public.price_tick at the instant of the read. docs/PRICE_FACTORS.md §3.5.'),
  ('price_tick_seconds', to_jsonb(15),
   '0212: the tick''s bucket, in real seconds: the mood changes once a bucket. Then select public.price_tick_refresh().'),
  ('price_tick_window_seconds', to_jsonb(300),
   '0212: the no-free-money window: the tick may never move more than the budget (80 % of the thinnest spread any '
   'trader can reach) between two instants this close. Then select public.price_tick_refresh().'),
  ('price_tick_volatility', to_jsonb(1),
   '0212: THE ONE OVERALL KNOB of the mood: scales every rarity''s amplitude, and with it the slow wave''s length, so '
   'the short-horizon swing stays inside the budget. Then select public.price_tick_refresh().'),
  ('price_tick_amplitude', '{"common": 0.015, "uncommon": 0.025, "rare": 0.035, "exotic": 0.05}'::jsonb,
   '0212: the slow mood''s reach by the good''s rarity (public.good_rarity), at volatility 1: common gentle, exotic '
   'stronger. Then select public.price_tick_refresh().'),
  ('price_tick_rule', '{}'::jsonb,
   '0212: DERIVED — the tick''s integer terms (bucket, budget, jitter, fast octave, per-tier amplitude and lattice '
   'steps), written ONLY by public.price_tick_refresh() from the price_tick_* and spread knobs. Never edit by hand.');

create table public.price_tick_goods (
  good_id uuid primary key references public.goods(id),
  rarity  text not null
);
comment on table public.price_tick_goods is
  '0212: each good''s rarity tier as the live tick reads it — a stored copy of public.good_rarity(good_id), which '
  'scans every port specialty and cannot sit on the quote''s path. Written by 0212; the world guard holds it equal.';
alter table public.price_tick_goods enable row level security;
revoke all on table public.price_tick_goods from public, anon, authenticated;
insert into public.price_tick_goods (good_id, rarity) select g.id, public.good_rarity(g.id) from public.goods g;

-- THE LEAF — the one arithmetic the client ports (src/domain/market/tick.ts). Integers only, every product
-- below 2^53 (x < 2^26, so x·x < 2^52; a hash × 2,000,001 < 2^47), and every division truncates toward zero
-- — PostgreSQL's bigint `/` and JavaScript's Math.trunc agree on that. Returns the tick in ppm.
create function public.price_tick_ppm(p_seed bigint, p_bucket bigint, p_amp int, p_p1 int, p_p2 int,
                                      p_fast int, p_fp int, p_jit int)
returns int
language plpgsql
immutable parallel safe
set search_path = public, pg_temp
as $fn$
-- 0212: one hash, three steps (x·48271 + 11, x² + 7, x·69621 + 13, all mod 67,108,859), mapped onto
-- [−1,000,000, 1,000,000]; the octaves interpolate it linearly between lattice points; the jitter draws it
-- once a bucket. The weights: slow = (65 × octave 1 + 35 × octave 2) / 100.
declare
  m  constant bigint := 67108859;
  n  bigint; r bigint; x bigint; v0 bigint; v1 bigint; s1 bigint; s2 bigint; f bigint; j bigint;
begin
  n := p_bucket / p_p1; r := p_bucket - n * p_p1;
  x := (p_seed + n * 7919) % m;           x := (x * 48271 + 11) % m; x := (x * x + 7) % m; x := (x * 69621 + 13) % m; v0 := x * 2000001 / m - 1000000;
  x := (p_seed + (n + 1) * 7919) % m;     x := (x * 48271 + 11) % m; x := (x * x + 7) % m; x := (x * 69621 + 13) % m; v1 := x * 2000001 / m - 1000000;
  s1 := (v0 * (p_p1 - r) + v1 * r) / p_p1;
  n := p_bucket / p_p2; r := p_bucket - n * p_p2;
  x := (p_seed + 1000003 + n * 7919) % m; x := (x * 48271 + 11) % m; x := (x * x + 7) % m; x := (x * 69621 + 13) % m; v0 := x * 2000001 / m - 1000000;
  x := (p_seed + 1000003 + (n + 1) * 7919) % m; x := (x * 48271 + 11) % m; x := (x * x + 7) % m; x := (x * 69621 + 13) % m; v1 := x * 2000001 / m - 1000000;
  s2 := (v0 * (p_p2 - r) + v1 * r) / p_p2;
  n := p_bucket / p_fp; r := p_bucket - n * p_fp;
  x := (p_seed + 2000006 + n * 7919) % m; x := (x * 48271 + 11) % m; x := (x * x + 7) % m; x := (x * 69621 + 13) % m; v0 := x * 2000001 / m - 1000000;
  x := (p_seed + 2000006 + (n + 1) * 7919) % m; x := (x * 48271 + 11) % m; x := (x * x + 7) % m; x := (x * 69621 + 13) % m; v1 := x * 2000001 / m - 1000000;
  f := (v0 * (p_fp - r) + v1 * r) / p_fp;
  x := (p_seed + 3000009 + p_bucket * 7919) % m; x := (x * 48271 + 11) % m; x := (x * x + 7) % m; x := (x * 69621 + 13) % m; j := x * 2000001 / m - 1000000;
  return (1000000 + p_amp * ((65 * s1 + 35 * s2) / 100) / 1000000 + p_fast * f / 1000000 + p_jit * j / 1000000)::int;
end $fn$;

-- THE MARKET'S SEED: the first 24 bits of the port's uuid and of the good's, folded below the hash's modulus.
create function public.price_tick_seed(p_port uuid, p_good uuid)
returns bigint
language sql
immutable parallel safe
as $fn$
  select ((('x' || substr(p_port::text, 1, 6))::bit(24)::int)::bigint * 4096
          + ('x' || substr(p_good::text, 1, 6))::bit(24)::int) % 67108859
$fn$;

-- THE RULE, DERIVED from the knobs (the law in the header). Raises when the law cannot be kept.
create function public.price_tick_rule_derive()
returns jsonb
language plpgsql
stable security definer
set search_path = public, pg_temp
as $fn$
declare
  v_s      int := public.wc_int('price_tick_seconds');
  v_w      int := public.wc_int('price_tick_window_seconds');
  v_vol    numeric := public.wc_num('price_tick_volatility');
  v_min    numeric := public.wc_num('spread_floor') * (1 - public.wc_num('buff_bonus_cap_pct') / 100)
                      * public.wc_num('haggle_spread_floor_frac');
  v_wb     int;
  v_budget int;
  v_jit    int;
  v_fast   int;
  v_slow   int;
  v_fp     int;
  v_tiers  jsonb := '{}'::jsonb;
  v_amp    int;
  v_p1     int;
  r        record;
begin
  if v_s < 1 or v_w < v_s or v_vol < 0 then
    raise exception 'price_tick: seconds %, window % and volatility % do not make a tick', v_s, v_w, v_vol using errcode = '22023';
  end if;
  v_wb     := ceil(v_w::numeric / v_s)::int;
  v_budget := floor(v_min * 0.8 * 1000000)::int;
  v_jit    := v_budget / 8;
  v_fast   := v_budget / 8;
  v_slow   := v_budget - 2 * v_jit - 2 * v_fast;
  v_fp     := greatest(2, ceil(60.0 / v_s))::int;
  if v_slow < 100 then
    raise exception 'price_tick: the thinnest spread (%) leaves no budget for a tick', v_min using errcode = '22023';
  end if;
  for r in select k, v from jsonb_each(public.wc('price_tick_amplitude')) e(k, v) order by k loop
    v_amp := round((r.v)::text::numeric * v_vol * 1000000)::int;
    if v_amp < 0 or v_amp > 200000 then
      raise exception 'price_tick: tier % amplitude % ppm is outside 0 – 200,000', r.k, v_amp using errcode = '22023';
    end if;
    v_p1 := greatest(2, ceil(2.0 * v_amp * v_wb * 158 / (100.0 * v_slow)))::int;
    v_tiers := v_tiers || jsonb_build_object(r.k, jsonb_build_object(
                 'amp_ppm', v_amp, 'p1', v_p1, 'p2', greatest(2, ceil(v_p1 * 38 / 100.0))::int));
  end loop;
  return jsonb_build_object('seconds', v_s, 'window_buckets', v_wb, 'budget_ppm', v_budget,
                            'jitter_ppm', v_jit, 'fast_ppm', v_fast, 'fast_period', v_fp,
                            'volatility', v_vol, 'tiers', v_tiers);
end $fn$;

-- WRITE the derived rule (after any change of a price_tick_* or spread knob).
create function public.price_tick_refresh()
returns jsonb
language plpgsql
volatile security definer
set search_path = public, pg_temp
as $fn$
declare
  v jsonb := public.price_tick_rule_derive();
begin
  update public.world_config set value = v where key = 'price_tick_rule';
  return v;
end $fn$;

-- WHAT A PAYLOAD SERVES and a path reads once: the stored rule and the switch.
create function public.price_tick_rule_now()
returns jsonb
language sql
stable security definer
set search_path = public, pg_temp
as $fn$
  select public.wc('price_tick_rule') || jsonb_build_object('on', public.wc('price_tick_on') = 'true'::jsonb)
$fn$;

-- THE TICK of one market at one instant: exactly 1 when the rule is off (or names no tier for this good).
create function public.price_tick(p_port uuid, p_good uuid, p_at timestamptz, p_rule jsonb)
returns numeric
language plpgsql
stable security definer
set search_path = public, pg_temp
as $fn$
declare
  v_t jsonb;
begin
  if p_rule is null or p_rule->'on' is distinct from 'true'::jsonb then
    return 1;
  end if;
  select p_rule->'tiers'->tg.rarity into v_t from public.price_tick_goods tg where tg.good_id = p_good;
  if v_t is null then
    return 1;   -- a good with no tier row (a later migration's) trades calm — the world guard names it
  end if;
  return round(public.price_tick_ppm(public.price_tick_seed(p_port, p_good),
                                     floor(extract(epoch from p_at) / (p_rule->>'seconds')::numeric)::bigint,
                                     (v_t->>'amp_ppm')::int, (v_t->>'p1')::int, (v_t->>'p2')::int,
                                     (p_rule->>'fast_ppm')::int, (p_rule->>'fast_period')::int,
                                     (p_rule->>'jitter_ppm')::int)::numeric / 1000000, 6);
end $fn$;

select public.price_tick_refresh();

-- ── 3. THE RE-CUTS (hunks sliced from the live bodies; each occurs once; each body reverses) ──
create temp table hunks_0212 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0212 (fn, n, old, new) values
-- world.mid_from_terms: × the tick, on the 4-dp price (a new 15-argument form)
('world.mid_from_terms(numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, integer, numeric, numeric, numeric, numeric)', 1,
$h$p_glut numeric, p_stock_target numeric$h$,
$h$p_glut numeric, p_tick numeric, p_stock_target numeric$h$),
('world.mid_from_terms(numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, integer, numeric, numeric, numeric, numeric)', 2,
$h$  -- 0194: × (1 − THE GLUT) (port_goods.glut, recent sales here), likewise after the band: a crash on top.
$h$,
$h$  -- 0194: × (1 − THE GLUT) (port_goods.glut, recent sales here), likewise after the band: a crash on top.
  -- 0212: × THE TICK (world.mid_terms' m_tick: the market's mood this instant, public.price_tick; 1 dark), on the
  -- 0212: price already rounded to 4 dp — so a client ticks a served calm price exactly as this does.
$h$),
('world.mid_from_terms(numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, integer, numeric, numeric, numeric, numeric)', 3,
$h$  select round(least(greatest($h$,
$h$  select round(round(least(greatest($h$),
('world.mid_from_terms(numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, integer, numeric, numeric, numeric, numeric)', 4,
$h$           p_band_lo * p_base), p_band_hi * p_base) * p_haul * (1 - p_glut), 4)$h$,
$h$           p_band_lo * p_base), p_band_hi * p_base) * p_haul * (1 - p_glut), 4) * p_tick, 4)$h$),
-- world.mid_terms: the tick, read at the instant of the read (one knob read while dark)
('world.mid_terms(uuid, uuid)', 1,
$h$OUT m_glut numeric, OUT m_target numeric$h$,
$h$OUT m_glut numeric, OUT m_tick numeric, OUT m_target numeric$h$),
('world.mid_terms(uuid, uuid)', 2,
$h$  m_band_hi      := public.wc_num('price_band_hi');
$h$,
$h$  m_band_hi      := public.wc_num('price_band_hi');
  -- 0212: THE TICK — the market's mood at this instant (public.price_tick); exactly 1 while price_tick_on is off
  m_tick := case when public.wc('price_tick_on') = 'true'::jsonb
                 then public.price_tick(p_port, p_good, now(), public.price_tick_rule_now()) else 1 end;
$h$),
-- world.mid_price
('world.mid_price(uuid, uuid, numeric)', 1,
$h$  return world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_haul, t.m_glut, t.m_target, p_stock, t.m_drift,   -- 0194: + glut   -- 0173: + haul$h$,
$h$  return world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_haul, t.m_glut, t.m_tick, t.m_target, p_stock, t.m_drift,   -- 0194: + glut   -- 0173: + haul   -- 0212: + tick$h$),
-- world.quote_priced: both sides' steps, at the tick of the trade's instant
('world.quote_priced(uuid, uuid, numeric, text, numeric, uuid, numeric, numeric, numeric, numeric)', 1,
$h$      exit when v_n <= 0;
      v_mid  := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_haul, t.m_glut, t.m_target, v_stock, t.m_drift,   -- 0134, 0173, 0194$h$,
$h$      exit when v_n <= 0;
      v_mid  := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_haul, t.m_glut, t.m_tick, t.m_target, v_stock, t.m_drift,   -- 0134, 0173, 0194, 0212$h$),
('world.quote_priced(uuid, uuid, numeric, text, numeric, uuid, numeric, numeric, numeric, numeric)', 2,
$h$    else
      v_mid  := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_haul, t.m_glut, t.m_target, v_stock, t.m_drift,   -- 0134, 0173, 0194$h$,
$h$    else
      v_mid  := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_haul, t.m_glut, t.m_tick, t.m_target, v_stock, t.m_drift,   -- 0134, 0173, 0194, 0212$h$),
-- public.price_path: the tick at each step's instant (k = 0: the read's own, so k = 0 is world.price's)
('public.price_path(uuid, uuid, integer)', 1,
$h$  v_fade  numeric := 1 - public.wc_num('glut_decay');
begin$h$,
$h$  v_fade  numeric := 1 - public.wc_num('glut_decay');
  v_tr    jsonb := public.price_tick_rule_now();       -- 0212: the tick's rule, read once a path
  v_k     numeric;                                     -- 0212: the tick at this step's instant
begin$h$),
('public.price_path(uuid, uuid, integer)', 2,
$h$    mid   := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_haul, v_g, t.m_target, v_s, r.mean,   -- 0173: + haul; 0194: + glut$h$,
$h$    v_k   := case when r.k = 0 then t.m_tick else public.price_tick(p_port, p_good, v_at, v_tr) end;   -- 0212
    mid   := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_haul, v_g, v_k, t.m_target, v_s, r.mean,   -- 0173: + haul; 0194: + glut; 0212: + tick$h$),
('public.price_path(uuid, uuid, integer)', 3,
$h$    lo    := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_haul, v_g, t.m_target, v_s,$h$,
$h$    lo    := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_haul, v_g, v_k, t.m_target, v_s,$h$),
('public.price_path(uuid, uuid, integer)', 4,
$h$    hi    := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_haul, v_g, t.m_target, v_s,$h$,
$h$    hi    := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_haul, v_g, v_k, t.m_target, v_s,$h$),
-- world.market: the range carries the tick of this instant (so the mid stays inside it)
('world.market(uuid)', 1,
$h$           public.wc_num('drift_clamp')      as clamp
  )$h$,
$h$           public.wc_num('drift_clamp')      as clamp,
           public.price_tick_rule_now()      as tr   -- 0212: the tick's rule, read once a quay
  )$h$),
('world.market(uuid)', 2,
$h$        'range_lo', world.mid_from_terms(g.base_value, pg.affinity, pg.demand, pg.haul, pg.glut, pg.stock_target,   -- 0173: + haul; 0194: + glut$h$,
$h$        'range_lo', world.mid_from_terms(g.base_value, pg.affinity, pg.demand, pg.haul, pg.glut,
                      public.price_tick(pg.port_id, pg.good_id, v_now, k.tr), pg.stock_target,   -- 0173: + haul; 0194: + glut; 0212: + tick$h$),
('world.market(uuid)', 3,
$h$        'range_hi', world.mid_from_terms(g.base_value, pg.affinity, pg.demand, pg.haul, pg.glut, pg.stock_target,$h$,
$h$        'range_hi', world.mid_from_terms(g.base_value, pg.affinity, pg.demand, pg.haul, pg.glut,
                      public.price_tick(pg.port_id, pg.good_id, v_now, k.tr), pg.stock_target,$h$),
-- world.price_why: the mood, its own term (the terms still multiply back to the mid)
('world.price_why(uuid, uuid)', 1,
$h$      jsonb_build_object('key', 'glut',        'mult', 1 - t.m_glut)),   -- 0194: recent sales here$h$,
$h$      jsonb_build_object('key', 'glut',        'mult', 1 - t.m_glut),   -- 0194: recent sales here
      jsonb_build_object('key', 'mood',        'mult', t.m_tick)),   -- 0212: the market's mood this instant (1 dark)$h$),
-- world.price_outlook: the tick's rule and this city's calm price, so the client ticks the hero figure
('world.price_outlook(uuid, uuid, integer, text)', 1,
$h$    'events', v_events,
$h$,
$h$    'events', v_events,
    -- 0212: the TICK's rule (public.price_tick_rule_now) and the city's middle price with the tick at 1
    -- 0212: (world.mid_calm): a client ticks the figure as the server would (src/domain/market/tick.ts)
    'tick', public.price_tick_rule_now(),
    'calm', world.mid_calm(p_port, p_good, (select pg.stock from public.port_goods pg where pg.port_id = p_port and pg.good_id = p_good)),
$h$),
-- world.watchlist: the tick's rule, and lit, each cheapest seller's calm price NOW
('world.watchlist(uuid)', 1,
$h$  v_out    jsonb;
begin$h$,
$h$  v_out    jsonb;
  v_tick   jsonb := public.price_tick_rule_now();       -- 0212: the tick's rule, served
  v_lit    boolean := (v_tick->>'on')::boolean;          -- 0212: lit, each best row carries its calm price now
begin$h$),
('world.watchlist(uuid)', 2,
$h$                        else jsonb_build_object('port', b.port, 'mid', round(b.mid, 2), 'as_of', b.as_of, 'recorded', b.recorded,$h$,
$h$                        else jsonb_build_object('port', b.port, 'mid', round(b.mid, 2), 'as_of', b.as_of, 'recorded', b.recorded,
                                                'calm', case when v_lit then world.mid_calm(b.port_id, b.good_id, b.stock) end,   -- 0212$h$),
('world.watchlist(uuid)', 3,
$h$    'window_slots', v_win,$h$,
$h$    'window_slots', v_win,
    'tick', v_tick,   -- 0212$h$);

-- THE CALM PRICE: the one expression with the tick at 1 (what a client ticks). Created before the bodies that
-- call it; it calls the 15-argument form, created first in the loop below.
do $$
declare
  d     record;
  h     record;
  p     record;
  v_def text;
  v_rev text;
  v_new regprocedure;
  v_n   int := 0;
begin
  for d in select * from defs_before_0212 order by ord loop
    v_def := d.def;
    for h in select * from hunks_0212 where fn = d.fn order by n loop
      if pg_temp.occurs_0212(v_def, h.old) <> 1 then
        raise exception '0212 self-assert FAIL: % hunk % occurs % time(s), not once — the deployed body is not what this file was written against',
          d.fn, h.n, pg_temp.occurs_0212(v_def, h.old);
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    if v_def = d.def then
      raise exception '0212 self-assert FAIL: % has no hunk', d.fn;
    end if;
    -- mid_terms' OUT row changes, so it is dropped and created; mid_from_terms' new form is a new signature
    if d.ord = 2 then
      execute 'drop function world.mid_terms(uuid, uuid)';
    end if;
    execute v_def;
    v_new := case d.ord
               when 1 then 'world.mid_from_terms(numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, integer, numeric, numeric, numeric, numeric)'::regprocedure
               else d.fn::regprocedure end;
    if d.ord in (1, 2) then
      -- a function CREATEd here starts from the default ACL; put the pre-image's back (server-only)
      execute format('revoke all on function %s from public, anon, authenticated, service_role', v_new::text);
    end if;
    if d.ord = 2 then
      -- world.mid_calm is the outlook's and the watchlist's, re-cut next: it must exist before they are created
      create or replace function world.mid_calm(p_port uuid, p_good uuid, p_stock numeric)
      returns numeric
      language plpgsql
      stable security definer
      set search_path = public, pg_temp
      as $fn$
      -- 0212: THE CALM PRICE — world.mid_price with the tick held at 1 (its mean): the one expression, the row's
      -- terms from world.mid_terms. What a client multiplies the live tick into (src/domain/market/tick.ts).
      declare
        t record;
      begin
        select * into t from world.mid_terms(p_port, p_good);
        return world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_haul, t.m_glut, 1, t.m_target, p_stock, t.m_drift,
                                    t.m_season, t.m_dev, t.m_elasticity, t.m_dev_discount, t.m_band_lo, t.m_band_hi);
      end $fn$;
      revoke all on function world.mid_calm(uuid, uuid, numeric) from public, anon, authenticated, service_role;
    end if;
    v_rev := replace(pg_get_functiondef(v_new), E'\r', '');
    for h in select * from hunks_0212 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0212(v_rev, h.new) <> 1 then
        raise exception '0212 self-assert FAIL: % new hunk % is not in the live body once', d.fn, h.n;
      end if;
      v_rev := replace(v_rev, h.new, h.old);
    end loop;
    if v_rev <> d.def then
      raise exception '0212 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef,
           coalesce(pr.proconfig::text, '') as cfg, pr.proowner as owner
      into p from pg_proc pr where pr.oid = v_new;
    if p.acl <> d.acl or p.vol <> d.vol or p.secdef <> d.secdef or p.cfg <> d.cfg or p.owner <> d.owner then
      raise exception '0212 self-assert FAIL: % changed its ACL (% → %), owner, volatility, definer or config', d.fn, d.acl, p.acl;
    end if;
    v_n := v_n + 1;
  end loop;
  if v_n <> 9 then
    raise exception '0212 self-assert FAIL: % bodies re-cut, not 9', v_n;
  end if;
end $$;

-- the 14-argument expression is retired: every caller now passes the tick (asserted below)
drop function world.mid_from_terms(numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, integer, numeric, numeric, numeric, numeric);

revoke all on function public.price_tick_ppm(bigint, bigint, int, int, int, int, int, int) from public, anon, authenticated, service_role;
revoke all on function public.price_tick_seed(uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function public.price_tick_rule_derive() from public, anon, authenticated, service_role;
revoke all on function public.price_tick_refresh() from public, anon, authenticated, service_role;
revoke all on function public.price_tick_rule_now() from public, anon, authenticated, service_role;
revoke all on function public.price_tick(uuid, uuid, timestamptz, jsonb) from public, anon, authenticated, service_role;

-- ── 4. THE PROOF ──────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_uid    constant uuid := '00000000-0212-4000-8000-000000000001';
  v_rule   jsonb;
  v_bad    int;
  v_n      int;
  v_wb     int;
  v_budget int;
  v_smin   numeric;
  v_b0     bigint;
  v_pairs  bigint;
  v_worst  numeric;
  v_ctl    int;
  v_mean   numeric;
  v_ticked int;
  v_dev    numeric;
  v_step   int;
  v_port   uuid;
  v_good   uuid;
  v_p      uuid;
  v_f      uuid;
  v_tick   numeric;
  v_calm1  numeric;
  v_lit1   numeric;
  v_r      jsonb;
  v_err    text;
  v_ok     text := '';
  v_law    text := '';
  j        jsonb;
  v_prod   numeric;
  v_t0     timestamptz;
  v_tq_d   numeric; v_tm_d numeric; v_tw_d numeric; v_to_d numeric;
  v_tq_l   numeric; v_tm_l numeric; v_tw_l numeric; v_to_l numeric;
  v_qp     uuid; v_qg uuid; v_qs numeric;
  r        record;
begin
  -- (d) the expression's callers are the five; the old form is gone
  if (select string_agg(n.nspname || '.' || p.proname, ',' order by n.nspname || '.' || p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('world', 'public', 'cmd', 'voyage') and p.prosrc like '%mid_from_terms(%')
     is distinct from 'public.price_path,world.market,world.mid_calm,world.mid_price,world.quote_priced'
     or to_regprocedure('world.mid_from_terms(numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, integer, numeric, numeric, numeric, numeric)') is not null then
    raise exception '0212 self-assert FAIL: a caller of the old expression remains, or the old form stands';
  end if;

  -- (a) the knobs, the rule, the law, the tiers
  v_rule := public.wc('price_tick_rule');
  if v_rule is distinct from public.price_tick_rule_derive() or public.wc('price_tick_on') <> 'false'::jsonb then
    raise exception '0212 self-assert FAIL: the stored rule is not the derived one, or the switch is not dark: %', v_rule;
  end if;
  v_wb     := (v_rule->>'window_buckets')::int;
  v_budget := (v_rule->>'budget_ppm')::int;
  v_smin   := public.wc_num('spread_floor') * (1 - public.wc_num('buff_bonus_cap_pct') / 100) * public.wc_num('haggle_spread_floor_frac');
  if v_budget <> floor(v_smin * 0.8 * 1000000) or v_budget < 400 then
    raise exception '0212 self-assert FAIL: the budget % ppm is not 80 %% of the thinnest spread %', v_budget, v_smin;
  end if;
  for r in select e.key as tier, e.value as t from jsonb_each(v_rule->'tiers') e order by 1 loop
    -- the slow octaves' largest move over the window + both fast parts' largest move must fit the budget
    if 2.0 * (r.t->>'amp_ppm')::int * v_wb * (65.0 / (r.t->>'p1')::int + 35.0 / (r.t->>'p2')::int) / 100
       + 2 * (v_rule->>'jitter_ppm')::int + 2 * (v_rule->>'fast_ppm')::int > v_budget then
      raise exception '0212 self-assert FAIL: tier % breaks the law: %', r.tier, r.t;
    end if;
    v_law := v_law || format('%s ±%s %% (steps %s/%s buckets) ', r.tier, round((r.t->>'amp_ppm')::numeric / 10000, 1), r.t->>'p1', r.t->>'p2');
  end loop;
  if (select count(*) from public.goods g left join public.price_tick_goods tg on tg.good_id = g.id
       where tg.rarity is distinct from public.good_rarity(g.id) or not (v_rule->'tiers' ? tg.rarity)) <> 0 then
    raise exception '0212 self-assert FAIL: a good''s stored tier is not its rarity, or the rule has no terms for it';
  end if;
  -- the leaf is the same on equal inputs and can reach both sides of 1 (not a constant)
  select count(*) filter (where p > 1000000), count(*) filter (where p < 1000000) into v_n, v_bad
    from (select public.price_tick_ppm(public.price_tick_seed(pg.port_id, pg.good_id), 117000000 + k, 50000, 3000, 1140, 200, 4, 200) p
            from (select port_id, good_id from public.port_goods order by port_id, good_id limit 5) pg, generate_series(0, 999, 37) k) z;
  if v_n = 0 or v_bad = 0 then
    raise exception '0212 self-assert FAIL: the leaf does not move both ways (% up, % down)', v_n, v_bad;
  end if;

  -- (b) DARK: new = old exactly on a sample (old tree and new in one statement each)
  create temp table sample_0212 on commit drop as
    select pg.port_id, pg.good_id from public.port_goods pg
     order by md5(pg.port_id::text || pg.good_id::text || '0212') limit 120;
  select count(*) into v_bad from sample_0212 s join public.port_goods pg using (port_id, good_id)
   where world.mid_price(s.port_id, s.good_id, pg.stock) is distinct from pg_temp.mid_price_old_0212(s.port_id, s.good_id, pg.stock)
      or world.mid_price(s.port_id, s.good_id, pg.stock)::text is distinct from pg_temp.mid_price_old_0212(s.port_id, s.good_id, pg.stock)::text
      or world.mid_calm(s.port_id, s.good_id, pg.stock)::text is distinct from pg_temp.mid_price_old_0212(s.port_id, s.good_id, pg.stock)::text;
  if v_bad <> 0 then
    raise exception '0212 self-assert FAIL: % sampled mid prices moved while the tick is dark', v_bad;
  end if;
  select count(*) into v_bad from sample_0212 s
   cross join (values ('buy', 10::numeric), ('buy', 200), ('sell', 10), ('sell', 200)) q(side, qty)
   cross join lateral (select world.quote_priced(s.port_id, s.good_id, q.qty, q.side, null, null, null, null, null, null) as n,
                              pg_temp.quote_priced_old_0212(s.port_id, s.good_id, q.qty, q.side, null, null, null, null, null, null) as o) x
   where x.n::text is distinct from x.o::text;
  if v_bad <> 0 then
    raise exception '0212 self-assert FAIL: % sampled quotes moved while the tick is dark', v_bad;
  end if;
  select count(*) into v_bad from (select * from sample_0212 order by port_id, good_id limit 12) s
   cross join lateral (select array_agg(row(p.k, p.at, p.stock, p.mid, p.lo, p.hi)::text order by p.k) a from public.price_path(s.port_id, s.good_id, 24) p) n
   cross join lateral (select array_agg(row(p.k, p.at, p.stock, p.mid, p.lo, p.hi)::text order by p.k) a from pg_temp.price_path_old_0212(s.port_id, s.good_id, 24) p) o
   where n.a is distinct from o.a;
  if v_bad <> 0 then
    raise exception '0212 self-assert FAIL: % sampled price paths moved while the tick is dark', v_bad;
  end if;
  -- the market's range at Lisbon, and the why. world.market winds its quay's drift and stock first (0029), so
  -- it is read once to wind them, and compared on the second read (idempotent within the slot and the day).
  perform world.market((select id from public.ports where code = 'LIS'));
  select count(*) into v_bad
    from jsonb_array_elements(world.market((select id from public.ports where code = 'LIS'))->'goods') x
    join public.port_goods pg on pg.port_id = (select id from public.ports where code = 'LIS') and pg.good_id = (x->>'good_id')::uuid
    join public.goods g on g.id = pg.good_id join public.ports pr on pr.id = pg.port_id
   where (x->>'range_lo')::numeric is distinct from pg_temp.mft_old_0212(g.base_value, pg.affinity, pg.demand, pg.haul, pg.glut, pg.stock_target, pg.stock,
                  -public.wc_num('drift_clamp'), pg.season_mod, pr.dev_commerce, public.wc_num('price_elasticity'), public.wc_num('mid_dev_discount'),
                  public.wc_num('price_band_lo'), public.wc_num('price_band_hi'))
      or (x->>'range_hi')::numeric is distinct from pg_temp.mft_old_0212(g.base_value, pg.affinity, pg.demand, pg.haul, pg.glut, pg.stock_target, pg.stock,
                  public.wc_num('drift_clamp'), pg.season_mod, pr.dev_commerce, public.wc_num('price_elasticity'), public.wc_num('mid_dev_discount'),
                  public.wc_num('price_band_lo'), public.wc_num('price_band_hi'));
  if v_bad <> 0 then
    raise exception '0212 self-assert FAIL: % of Lisbon''s market ranges moved while the tick is dark', v_bad;
  end if;
  select s.port_id, s.good_id into v_qp, v_qg from sample_0212 s order by s.port_id, s.good_id limit 1;
  j := world.price_why(v_qp, v_qg);
  if (select (x->>'mult')::numeric from jsonb_array_elements(j->'terms') x where x->>'key' = 'mood') is distinct from 1
     or (j->>'mid')::numeric is distinct from pg_temp.mid_price_old_0212(v_qp, v_qg, (select stock from public.port_goods where port_id = v_qp and good_id = v_qg)) then
    raise exception '0212 self-assert FAIL: price_why dark is not the old mid with a mood of 1: %', j;
  end if;
  j := world.price_outlook(v_qp, v_qg, 4, 'mid');
  if j->'tick'->'on' is distinct from 'false'::jsonb or (j->>'calm')::numeric is distinct from (j->'points'->0->>'value')::numeric then
    raise exception '0212 self-assert FAIL: the dark outlook does not serve the rule off and its calm = its first point: % / %', j->'tick', j->>'calm';
  end if;
  j := world.watchlist(null);
  if j->'tick'->'on' is distinct from 'false'::jsonb
     or exists (select 1 from jsonb_array_elements(j->'goods') x where x->'best' ? 'calm' and x->'best'->'calm' <> 'null'::jsonb) then
    raise exception '0212 self-assert FAIL: the dark watchlist does not serve the rule off with no calm';
  end if;

  -- timings, dark (notice only): 8 calls each, one session, the same market
  select s.port_id, s.good_id, pg.stock into v_qp, v_qg, v_qs from sample_0212 s join public.port_goods pg using (port_id, good_id)
   join public.ports p on p.id = s.port_id where p.kind = 'HARBOUR' and public.port_offers(s.port_id, s.good_id)
   order by s.port_id, s.good_id limit 1;
  if v_qp is null then
    select pg.port_id, pg.good_id, pg.stock into v_qp, v_qg, v_qs from public.port_goods pg
     where public.port_offers(pg.port_id, pg.good_id) order by pg.port_id, pg.good_id limit 1;
  end if;
  v_t0 := clock_timestamp(); perform world.quote(v_qp, v_qg, 50, 'buy', null, null) from generate_series(1, 8);
  v_tq_d := round(extract(epoch from clock_timestamp() - v_t0) * 1000 / 8, 3);
  v_t0 := clock_timestamp(); perform world.mid_price(v_qp, v_qg, v_qs) from generate_series(1, 8);
  v_tm_d := round(extract(epoch from clock_timestamp() - v_t0) * 1000 / 8, 3);
  v_t0 := clock_timestamp(); perform world.price_outlook(v_qp, v_qg, 24, 'mid') from generate_series(1, 8);
  v_to_d := round(extract(epoch from clock_timestamp() - v_t0) * 1000 / 8, 3);
  v_t0 := clock_timestamp(); perform world.watchlist(null) from generate_series(1, 2);
  v_tw_d := round(extract(epoch from clock_timestamp() - v_t0) * 1000 / 2, 1);

  -- (c) LIT, inside a block that is rolled back whole
  begin
    update public.world_config set value = 'true'::jsonb where key = 'price_tick_on';
    v_rule := public.price_tick_rule_now();
    -- mid = round(old mid × tick, 4) on every sampled row; calm = the old mid
    select count(*), count(*) filter (where public.price_tick(s.port_id, s.good_id, now(), v_rule) <> 1)
      into v_bad, v_n
      from sample_0212 s join public.port_goods pg using (port_id, good_id)
     where world.mid_price(s.port_id, s.good_id, pg.stock)
             is distinct from round(pg_temp.mid_price_old_0212(s.port_id, s.good_id, pg.stock) * public.price_tick(s.port_id, s.good_id, now(), v_rule), 4)
        or world.mid_calm(s.port_id, s.good_id, pg.stock) is distinct from pg_temp.mid_price_old_0212(s.port_id, s.good_id, pg.stock);
    if v_bad <> 0 then
      raise exception '0212 self-assert FAIL: % sampled lit mids are not the old mid × the tick', v_bad;
    end if;
    select count(*) into v_ticked from sample_0212 s where public.price_tick(s.port_id, s.good_id, now(), v_rule) <> 1;
    if v_ticked < 100 then
      raise exception '0212 self-assert FAIL: only % of 120 sampled markets carry a tick other than 1 when lit', v_ticked;
    end if;
    -- the path's k = 0 and the outlook's first point are world.price, to the cent, on every side
    select count(*) into v_bad from (select * from sample_0212 order by port_id, good_id limit 12) s
     cross join lateral (select p.mid from public.price_path(s.port_id, s.good_id, 4) p where p.k = 0) k0
     cross join lateral world.price(s.port_id, s.good_id) w
     cross join lateral (select (world.price_outlook(s.port_id, s.good_id, 4, 'ask')->'points'->0->>'value')::numeric as a,
                                (world.price_outlook(s.port_id, s.good_id, 4, 'bid')->'points'->0->>'value')::numeric as b,
                                (world.price_outlook(s.port_id, s.good_id, 4, 'mid')->'points'->0->>'value')::numeric as m) o
     where k0.mid is distinct from w.mid or o.a is distinct from w.ask or o.b is distinct from w.bid or o.m is distinct from w.mid;
    if v_bad <> 0 then
      raise exception '0212 self-assert FAIL: % lit paths / outlooks do not start at world.price', v_bad;
    end if;
    -- a later step carries ITS instant's tick
    select count(*) into v_bad from (select * from sample_0212 order by port_id, good_id limit 6) s
     cross join lateral public.price_path(s.port_id, s.good_id, 8) p
     cross join lateral (select * from pg_temp.price_path_old_0212(s.port_id, s.good_id, 8) o where o.k = p.k) o
     where p.k > 0 and p.mid is distinct from round(round(o.mid, 4) * public.price_tick(s.port_id, s.good_id, p.at, v_rule), 4);
    if v_bad <> 0 then
      raise exception '0212 self-assert FAIL: % lit path steps do not carry the tick at their instant', v_bad;
    end if;
    -- the why: the mood term is the tick; the terms multiply back to the mid
    j := world.price_why(v_qp, v_qg);
    select (j->>'base')::numeric * exp(sum(ln((x->>'mult')::numeric))) into v_prod from jsonb_array_elements(j->'terms') x;
    if (select (x->>'mult')::numeric from jsonb_array_elements(j->'terms') x where x->>'key' = 'mood') is distinct from public.price_tick(v_qp, v_qg, now(), v_rule)
       or abs(v_prod - (j->>'mid')::numeric) > greatest(0.0005 * (j->>'mid')::numeric, 0.0002) then
      raise exception '0212 self-assert FAIL: lit price_why does not carry the mood, or its terms do not multiply to the mid: %', j;
    end if;
    -- the lit payloads: the outlook's calm × the tick = its first point; the watchlist's best rows carry a calm
    j := world.price_outlook(v_qp, v_qg, 4, 'mid');
    if round((j->>'calm')::numeric * public.price_tick(v_qp, v_qg, now(), v_rule), 4) is distinct from (j->'points'->0->>'value')::numeric
       or j->'tick'->'on' is distinct from 'true'::jsonb then
      raise exception '0212 self-assert FAIL: the lit outlook''s calm × tick is not its first point: %', j;
    end if;
    j := world.watchlist(null);
    if (select count(*) from jsonb_array_elements(j->'goods') x where x->'best' is not null and x->'best' <> 'null'::jsonb
          and (x->'best'->>'calm') is null) <> 0
       or (select count(*) from jsonb_array_elements(j->'goods') x where (x->'best'->>'calm') is not null) = 0 then
      raise exception '0212 self-assert FAIL: the lit watchlist''s best rows do not all carry a calm price';
    end if;
    -- the range carries the tick, and the mid is inside it
    select count(*) into v_bad
      from jsonb_array_elements(world.market((select id from public.ports where code = 'LIS'))->'goods') x
     where (x->>'mid')::numeric < (x->>'range_lo')::numeric or (x->>'mid')::numeric > (x->>'range_hi')::numeric;
    if v_bad <> 0 then
      raise exception '0212 self-assert FAIL: % of Lisbon''s lit mids sit outside their range', v_bad;
    end if;

    -- NO FREE MONEY: 10 markets of every tier, every bucket of an hour, every pair within the window, at the
    -- thinnest spread any trader can reach, through world.price_sides (the sides' one leaf) and the expression.
    v_b0 := floor(extract(epoch from now()) / (v_rule->>'seconds')::numeric)::bigint;
    create temp table nfm_0212 on commit drop as
      with pick as (
        select x.port_id, x.good_id, x.rarity from (
          select pg.port_id, pg.good_id, tg.rarity,
                 row_number() over (partition by tg.rarity order by md5(pg.port_id::text || pg.good_id::text || 'nfm0212')) rk
            from public.port_goods pg join public.price_tick_goods tg on tg.good_id = pg.good_id) x
         where x.rk <= 10
      ), terms as materialized (
        select p.port_id, p.good_id, p.rarity, t.*, pg.stock
          from pick p join public.port_goods pg using (port_id, good_id)
         cross join lateral world.mid_terms(p.port_id, p.good_id) t
      )
      select tm.port_id, tm.good_id, tm.rarity, b.b,
             world.mid_from_terms(tm.m_base, tm.m_affinity, tm.m_demand, tm.m_haul, tm.m_glut,
                                  public.price_tick(tm.port_id, tm.good_id, to_timestamp(b.b * (v_rule->>'seconds')::numeric), v_rule),
                                  tm.m_target, tm.stock, tm.m_drift, tm.m_season, tm.m_dev, tm.m_elasticity, tm.m_dev_discount,
                                  tm.m_band_lo, tm.m_band_hi) as mid
        from terms tm cross join generate_series(v_b0, v_b0 + 239) b(b);
    select count(distinct rarity), count(*) into v_n, v_ctl from nfm_0212;
    if v_n <> (select count(distinct rarity) from public.price_tick_goods) or v_ctl < 240 * 10 * v_n then
      raise exception '0212 self-assert FAIL: the no-free-money sample is not every tier × 10 markets × 240 buckets (% tiers, % rows)', v_n, v_ctl;
    end if;
    select count(*),
           count(*) filter (where s2.bid > s1.ask or s1.bid > s2.ask),
           max(greatest(a.mid / b.mid, b.mid / a.mid))
      into v_pairs, v_bad, v_worst
      from nfm_0212 a
      join nfm_0212 b on b.port_id = a.port_id and b.good_id = a.good_id and b.b > a.b and b.b <= a.b + v_wb
     cross join lateral world.price_sides(a.mid, v_smin, 0, 1) s1
     cross join lateral world.price_sides(b.mid, v_smin, 0, 1) s2;
    if v_bad <> 0 or v_pairs < 100000 then
      raise exception '0212 self-assert FAIL: % of % pairs within the window pay a round trip at the thinnest spread %', v_bad, v_pairs, v_smin;
    end if;
    -- the positive control: a spread a quarter as thin DOES pay somewhere (the check can fail)
    select count(*) filter (where s2.bid > s1.ask or s1.bid > s2.ask) into v_ctl
      from nfm_0212 a
      join nfm_0212 b on b.port_id = a.port_id and b.good_id = a.good_id and b.b > a.b and b.b <= a.b + v_wb
     cross join lateral world.price_sides(a.mid, v_smin / 4, 0, 1) s1
     cross join lateral world.price_sides(b.mid, v_smin / 4, 0, 1) s2;
    if v_ctl = 0 then
      raise exception '0212 self-assert FAIL: the no-free-money check could not fail even at a quarter of the spread';
    end if;
    -- the tick's reach, one bucket's step (what a quote and a trade a second later can differ by), a game day's mean
    select max(abs(t.k - 1)), max(t.step) into v_dev, v_step
      from (select x.k, abs(x.k - lag(x.k) over (partition by x.port_id, x.good_id order by x.b)) * 1000000 as step
              from (select n.port_id, n.good_id, n.b, public.price_tick(n.port_id, n.good_id, to_timestamp(n.b * (v_rule->>'seconds')::numeric), v_rule) k
                      from nfm_0212 n) x) t;
    if v_step > v_budget or v_dev > 0.2 + 2 * v_budget / 1000000.0 then
      raise exception '0212 self-assert FAIL: one bucket moved the tick % ppm (budget %), or it reached % from 1', v_step, v_budget, v_dev;
    end if;
    select max(abs(m - 1)) into v_mean from (
      select avg(public.price_tick(n.port_id, n.good_id, to_timestamp((v_b0 + k) * (v_rule->>'seconds')::numeric), v_rule)) m
        from (select distinct port_id, good_id from nfm_0212) n
       cross join generate_series(0, ceil(public.wc_num('game_day_seconds') / (v_rule->>'seconds')::numeric)::int - 1) k
       group by n.port_id, n.good_id) z;

    -- A LIMIT AT THE CALM PRICE REFUSES WHEN THE TICK HAS MOVED PAST IT, plainly; at the ticked price it fills.
    -- Probe: a company founded at Lisbon, its fleet laid (rolled back) at the market every harbour offers whose
    -- tick NOW is furthest above 1 — chosen over every offered market, not one city's handful, so the probe's
    -- precondition (a tick above 1 by more than a cent's rounding) is the world's, never a draw's.
    v_p := public.new_house(c_uid, 'Casa do Pregão 0212', 'PRT', 'LIS');
    select id into v_f from public.fleets where player_id = v_p order by id limit 1;
    select pg.port_id, pg.good_id, public.price_tick(pg.port_id, pg.good_id, now(), v_rule)
      into v_port, v_good, v_tick
      from public.port_goods pg join public.ports p on p.id = pg.port_id
     where p.kind = 'HARBOUR' and pg.stock > 50 and public.port_offers(pg.port_id, pg.good_id)
       and pg_temp.mid_price_old_0212(pg.port_id, pg.good_id, pg.stock) between 2 and 200
     order by public.price_tick(pg.port_id, pg.good_id, now(), v_rule) desc, pg.port_id, pg.good_id limit 1;
    if v_good is null or v_tick <= 1.01 then
      raise exception '0212 self-assert FAIL: no offered market with a tick above 1.01 to probe the limit (%)', v_tick;
    end if;
    update public.fleets set port_id = v_port, status = 'DOCKED' where id = v_f;
    select round(world.mid_calm(v_port, v_good, pg.stock) * (1 + q.q_tax + q.q_spread / 2), 2),
           round(world.mid_price(v_port, v_good, pg.stock) * (1 + q.q_tax + q.q_spread / 2), 2)
      into v_calm1, v_lit1
      from public.port_goods pg cross join lateral world.quote_terms(v_port, v_good, v_f) q
     where pg.port_id = v_port and pg.good_id = v_good;
    if v_lit1 <= v_calm1 then
      raise exception '0212 self-assert FAIL: the probe''s ticked unit % is not above its calm unit %', v_lit1, v_calm1;
    end if;
    begin
      v_r := cmd.do_buy(v_f, jsonb_build_object('good', v_good, 'qty', 10, 'limit', v_calm1));
      raise exception '0212 self-assert FAIL: a limit of % (the calm price) bought at a tick of % : %', v_calm1, v_tick, v_r;
    exception when others then
      v_err := sqlerrm;
      if v_err not like 'E_PRICE_LIMIT%' then
        raise exception '0212 self-assert FAIL: a limit past the tick was refused with "%", not E_PRICE_LIMIT', v_err;
      end if;
    end;
    v_r := cmd.do_buy(v_f, jsonb_build_object('good', v_good, 'qty', 10, 'limit', v_lit1));
    if coalesce((v_r->>'qty')::numeric, 0) <> 10 or (v_r->>'avg_price')::numeric is distinct from v_lit1 then
      raise exception '0212 self-assert FAIL: a limit at the ticked price % did not fill 10 at it: %', v_lit1, v_r;
    end if;
    v_ok := format('limit %s (calm) refused "%s" at tick %s; limit %s (ticked) bought %s',
                   v_calm1, left(v_err, 60), v_tick, v_lit1, v_r->>'qty');

    -- timings, lit
    v_t0 := clock_timestamp(); perform world.quote(v_qp, v_qg, 50, 'buy', null, null) from generate_series(1, 8);
    v_tq_l := round(extract(epoch from clock_timestamp() - v_t0) * 1000 / 8, 3);
    v_t0 := clock_timestamp(); perform world.mid_price(v_qp, v_qg, v_qs) from generate_series(1, 8);
    v_tm_l := round(extract(epoch from clock_timestamp() - v_t0) * 1000 / 8, 3);
    v_t0 := clock_timestamp(); perform world.price_outlook(v_qp, v_qg, 24, 'mid') from generate_series(1, 8);
    v_to_l := round(extract(epoch from clock_timestamp() - v_t0) * 1000 / 8, 3);
    v_t0 := clock_timestamp(); perform world.watchlist(null) from generate_series(1, 2);
    v_tw_l := round(extract(epoch from clock_timestamp() - v_t0) * 1000 / 2, 1);

    raise exception using errcode = 'ZX212', message = format(
      'LIT: 120 mids = old × tick (%s carry a tick ≠ 1); path k = 0 and the outlook = world.price on every side; '
      'why carries the mood; NO FREE MONEY on %s pairs within %s buckets at the thinnest spread %s (worst mid ratio %s); '
      'the control at a quarter of it pays on %s pairs; |tick − 1| ≤ %s; one bucket''s step ≤ %s ppm; a game day''s mean '
      'within %s of 1; %s. Timings lit: quote %s ms, mid_price %s ms, outlook %s ms, watchlist %s ms',
      v_ticked, v_pairs, v_wb, round(v_smin, 4), round(v_worst, 5), v_ctl, round(v_dev, 5), v_step, round(v_mean, 4), v_ok,
      v_tq_l, v_tm_l, v_to_l, v_tw_l);
  exception when sqlstate 'ZX212' then
    v_ok := sqlerrm;
  end;
  if public.wc('price_tick_on') <> 'false'::jsonb or exists (select 1 from public.players where id = v_p) then
    raise exception '0212 self-assert FAIL: the lit block or its probe company survived its rollback';
  end if;
  if v_ok not like 'LIT:%' then
    raise exception '0212 self-assert FAIL: the lit block did not report: %', v_ok;
  end if;

  -- (d) walls: nothing new a client can reach
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0
     or exists (select 1 from unnest(array['world.mid_terms(uuid, uuid)', 'world.mid_calm(uuid, uuid, numeric)',
                 'world.mid_from_terms(numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, integer, numeric, numeric, numeric, numeric)',
                 'public.price_tick_ppm(bigint, bigint, integer, integer, integer, integer, integer, integer)', 'public.price_tick_seed(uuid, uuid)',
                 'public.price_tick_rule_derive()', 'public.price_tick_refresh()', 'public.price_tick_rule_now()',
                 'public.price_tick(uuid, uuid, timestamp with time zone, jsonb)']) f(fn),
                 unnest(array['anon', 'authenticated']) rl(role) where has_function_privilege(rl.role, f.fn, 'execute'))
     or has_table_privilege('authenticated', 'public.price_tick_goods', 'select')
     or has_table_privilege('anon', 'public.price_tick_goods', 'select') then
    raise exception '0212 self-assert FAIL: a wall moved, or a client can reach the tick''s machinery';
  end if;
  raise notice '0212 self-assert ok: A PRICE TICKS WHILE YOU WATCH (dark). world.mid_from_terms × the tick on the 4-dp price (15 arguments; the 14-argument form dropped); world.mid_terms + m_tick; world.mid_calm; re-cut: mid_price, quote_priced, price_path, market, price_why, price_outlook, watchlist — 9 bodies reverse to their pre-images, ACL unmoved. Rule: bucket % s, window % buckets, budget % ppm (80 %% of the thinnest spread %), jitter ±%, fast ±% ppm; tiers: %. DARK: 120 mids, 480 quotes, 12 paths, Lisbon''s ranges = the pre-image exactly; why''s mood 1; payloads serve the rule off. %. Timings dark: quote % ms, mid_price % ms, outlook % ms, watchlist % ms.',
    v_rule->>'seconds', v_wb, v_budget, round(v_smin, 4), v_rule->>'jitter_ppm', v_rule->>'fast_ppm', v_law, v_ok,
    v_tq_d, v_tm_d, v_to_d, v_tw_d;
end $$;
