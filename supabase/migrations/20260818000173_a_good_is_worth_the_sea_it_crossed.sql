-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0173 — A GOOD IS WORTH THE SEA IT CROSSED  (the distance term: one more factor in the one price)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY ─────────────────────────────────────────────────────────────────────────────────────────
-- The owner, 2026-10-17 ~23:50 UTC: *"the distance ratio should make kimchi higher for cash. for example
-- korea - london is one of the longest trip. you bought for 100, it should sell for like 50k each. Or
-- something like that. Do a thorough research on 대항해시대 오리진 again, and check for trading prices and
-- apply."*  On prod at head 0170, kimchi cost ~100.70 a jar at its maker (Mokpo) and London's MIDDLE price
-- was ~130: 1.3 times, for a 14,006 nm passage. The only distance in the price was port_goods.affinity
-- (0005): a GREAT-CIRCLE gradient that saturates at affinity_reach_nm and can never pass
-- affinity_home + affinity_span (1.76). Distance from where a good is made did not move its price.
--
-- ── THE RESEARCH (docs/research/UWO_TRADE_PRICES.md, every number sourced) ──────────────────────
-- Uncharted Waters Origin prices a sale by a distance multiplier on the sailing distance (official notice
-- 2024-12-24: "이전보다 정확한 항해 거리를 기준으로"), strong enough that "멀리 나가서 팔수록 그만큼의 값을
-- 하게 되며" (namu). The ratios players quote, by haul: adjacent sea 1.2–1.5×; one ocean 3–5× (10× for a
-- cheap specialty); the farthest hauls (East/SE Asia ↔ Europe / the Caribbean) 16–40× and more. The shape
-- is convex: almost nothing near home, then steeply rising over an ocean. No source publishes the formula.
--
-- ── THE TERM ────────────────────────────────────────────────────────────────────────────────────
--     haul(nm) = haul_max ^ (min(1, nm / haul_reach_nm) ^ haul_curve)        (1 at nm = 0)
--     knobs:  haul_max 600   haul_reach_nm 14500   haul_curve 2.0
-- nm = the SAILING distance (public.sea_reaches — the water raster's own nm, the same lanes a fleet
-- sails) from the nearest city whose roster offers the good (public.port_offered_goods, the authority
-- world.affinity_for already reads); a city that offers it is at 0. The owner's number sets the scale
-- (Mokpo → London 14,006 nm: × 391, kimchi's London middle ~130 → ~50,800); the research sets the shape:
--     nm      1,000  2,000  3,000  5,000  7,000  10,000  12,000  14,006  ≥14,500
--     haul     1.03   1.13   1.32   2.14   4.45    20.9    79.8     391      600
-- A maker sells at exactly the price it did (haul 1): nothing anyone can BUY moves (a quay sells only
-- what its roster offers), so this is a pure rise in what a far city PAYS.
--
-- ── WHERE IT LIVES (one authority each) ─────────────────────────────────────────────────────────
-- (1) world.haul_at(nm, max, reach, curve) — NEW, the arithmetic, immutable.
-- (2) world.haul_rows() — NEW, the derivation for every market row, set-based: the distance from the
--     nearest maker by sea and its haul. 0173 fills port_goods from it; scripts/db/world-guard.mjs
--     compares the table with it on every chain apply (a knob or roster change that is not re-derived
--     is a red, not a silent mis-price).
-- (3) port_goods.haul_nm, port_goods.haul — NEW columns: stored per row like affinity, so a quote reads
--     one more column and does no arithmetic it did not do before.
-- (4) world.mid_from_terms gains p_haul (after p_demand) and multiplies the BANDED product by it: the
--     price_band_lo / hi clamp (0.35 – 3.5 × base) now bounds the market's own swing — stock, drift,
--     season — around the haul, so the band scales with the distance instead of clipping it. Created as
--     the 13-argument form; the 12-argument form is DROPPED once every caller is re-cut (0066's pattern).
-- (5) world.mid_terms gains OUT m_haul (it reads pg.haul with the row), so every reader of the one price
--     — world.mid_price, world.price, world.quote / quote_priced, world.trade_routes, the NPC planner,
--     public.price_path and 0170's world.price_outlook — prices the haul without a second path.
-- (6) Re-cut to pass it: world.mid_price (1 hunk), world.quote_priced (2), public.price_path (3),
--     world.market (2: its range_lo / range_hi), world.mid_terms (2; dropped and recreated — its OUT row
--     changes — with its ACL put back and compared).
-- Selling volume still depresses the price: the stock term is untouched (√(target / stock)), and a sale
-- of 100 jars into London's 175 still walks its price down 10 tuns at a time.
--
-- ── WHAT IT DELIBERATELY DOES NOT DO ────────────────────────────────────────────────────────────
-- Touch affinity (it still sets each market's depth — stock_target — and its small slope stays), the
-- city purse (city_bid_factor, the treasury: a parallel slice, 0172), the drift, demand, the spread,
-- the tax, or any grant of an existing function. Serve haul_nm to a client payload (the table was
-- already readable to authenticated, as affinity and demand are; no RPC adds it).
--
-- ── THE PROOF (in this file; production is lived in while it runs, so only OWN state is asserted) ─
-- (a) every port_goods row equals world.haul_rows(), both columns; makers at 1; haul monotone in nm.
-- (b) THE ONE EXPRESSION over every market row: new (with pg.haul) = old (the 12-argument pre-image,
--     pg_temp) × haul to the rounding; = old exactly where haul = 1.
-- (c) a sample (every kimchi row; a quarter of the rows at kimchi's maker and at the harbour with most
--     rows past 12,000 nm; an md5 sample): world.mid_price, world.quote (buy / sell × 10 / 50 / 200 t, and
--     a limit), public.price_path (every step's mid / lo / hi, stock, drift) — old tree (pg_temp) and new
--     in ONE statement each: equal where haul = 1, × haul where not; the outlook's k = 0 = world.price (mid / ask / bid) on the same rows — it does not fork.
-- (d) world.market at the sample's two harbours (in a rolled-back sub-block): range_lo / range_hi
--     = the old expression × haul; buy / sell / mid = world.price.
-- (e) every function that calls world.mid_from_terms is one of the four re-cut; the 12-argument form is
--     gone; 5 bodies reverse to their pre-images; ACL / owner / volatility / definer / config unmoved.
-- Timings: raise notice only (rankings through world.trade_routes before and after, same harbours).
--
-- ── LOCKS, AND HOW LONG THE PUSH TAKES ──────────────────────────────────────────────────────────
-- ALTER TABLE port_goods ADD COLUMN (two, with constant defaults — a catalogue change, no rewrite) takes
-- ACCESS EXCLUSIVE on port_goods for that instant, then one UPDATE of every market row (132,090 on the
-- chain) under row locks, then catalogue-only CREATE / DROP FUNCTION. A trade waits for the UPDATE
-- (measured on PGlite: see the dev-log). No LOCK TABLE, no set role, no set local, no begin.
--
-- ── DEPLOY ──────────────────────────────────────────────────────────────────────────────────────
-- DEPLOY_RUNBOOK: select public.unwind_the_clock(); → supabase db push --linked --include-all →
-- select public.wind_the_clock(). Prices at far cities rise at once; the client needs no change.
-- ROLLBACK: set haul_max to 1 and re-derive (update port_goods from world.haul_rows()) — every haul is 1
-- and every price is the pre-image's again; or a forward migration restoring the five bodies from this
-- file's hunks (old text), recreating the 12-argument form and dropping the columns.
-- VERSION: 0173 (prod head 0172, the city purses, read 2026-10-18: the six bodies cut here have the same md5 on
-- prod as on the fresh chain, and the callers of world.mid_from_terms on prod are the same four).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

create or replace function pg_temp.occurs_0173(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 1. THE PRE-IMAGES ─────────────────────────────────────────────────────────────────────────
create temp table defs_before_0173 on commit drop as
select f.fn, f.ord,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg,
       (select p.proowner from pg_proc p where p.oid = f.fn::regprocedure) as owner
  from (values (1, 'world.mid_from_terms(numeric, numeric, numeric, numeric, numeric, numeric, numeric, integer, numeric, numeric, numeric, numeric)'),
               (2, 'world.mid_terms(uuid, uuid)'),
               (3, 'world.mid_price(uuid, uuid, numeric)'),
               (4, 'world.quote_priced(uuid, uuid, numeric, text, numeric, uuid, numeric, numeric, numeric, numeric)'),
               (5, 'public.price_path(uuid, uuid, integer)'),
               (6, 'world.market(uuid)')) f(ord, fn);

do $$
begin
  if (select count(*) from defs_before_0173 where def is not null) <> 6 then
    raise exception '0173 self-assert FAIL: % of the 6 bodies found', (select count(*) from defs_before_0173 where def is not null);
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'port_goods'
                and column_name in ('haul', 'haul_nm'))
     or exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'world' and p.proname in ('haul_at', 'haul_rows'))
     or exists (select 1 from public.world_config where key in ('haul_max', 'haul_reach_nm', 'haul_curve')) then
    raise exception '0173 self-assert FAIL: something this file creates already exists';
  end if;
  -- THE CALLERS, as found: every body that names the one expression. A fifth one here is a caller this
  -- file would leave on a dropped signature.
  if (select string_agg(n.nspname || '.' || p.proname, ',' order by n.nspname || '.' || p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('world', 'public', 'cmd', 'voyage') and p.prosrc like '%mid_from_terms(%')
     is distinct from 'public.price_path,world.market,world.mid_price,world.quote_priced' then
    raise exception '0173 self-assert FAIL: the callers of world.mid_from_terms are %, not the four this file re-cuts',
      (select string_agg(n.nspname || '.' || p.proname, ',' order by n.nspname || '.' || p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname in ('world', 'public', 'cmd', 'voyage') and p.prosrc like '%mid_from_terms(%');
  end if;
end $$;

-- THE OLD TREE the proofs run against the new bodies: the 12-argument expression and its three
-- row-level callers, as pg_temp copies calling it (world.mid_terms' new OUT column is a field they
-- never read).
do $$
declare
  v_def text;
  r     record;
begin
  select def into v_def from defs_before_0173 where ord = 1;
  v_def := replace(v_def, 'CREATE OR REPLACE FUNCTION world.mid_from_terms(', 'CREATE OR REPLACE FUNCTION pg_temp.mft_old_0173(');
  if strpos(v_def, 'FUNCTION pg_temp.mft_old_0173(') = 0 then
    raise exception '0173 self-assert FAIL: the old copy of mid_from_terms was not made from the pre-image';
  end if;
  execute v_def;
  for r in select * from (values (3, 'world.mid_price(', 'pg_temp.mid_price_old_0173('),
                                 (4, 'world.quote_priced(', 'pg_temp.quote_priced_old_0173('),
                                 (5, 'public.price_path(', 'pg_temp.price_path_old_0173(')) x(ord, f, t) loop
    select def into v_def from defs_before_0173 where ord = r.ord;
    v_def := replace(v_def, 'CREATE OR REPLACE FUNCTION ' || r.f, 'CREATE OR REPLACE FUNCTION ' || r.t);
    v_def := replace(v_def, 'world.mid_from_terms(', 'pg_temp.mft_old_0173(');
    if strpos(v_def, 'FUNCTION ' || r.t) = 0 or strpos(v_def, 'world.mid_from_terms(') > 0 then
      raise exception '0173 self-assert FAIL: the old copy of % was not made from the pre-image', r.f;
    end if;
    execute v_def;
  end loop;
end $$;

-- THE SAMPLE, captured before anything moves: every kimchi row (the owner's example), every row at the
-- harbour with the most market rows past 12,000 nm of a maker and at kimchi's maker, and an md5 sample
-- of 400 rows. Distances are read here from the same authority world.haul_rows() will read.
create temp table sample_0173 on commit drop as
with offered as (
  select p.id as port_id, o.good_id from public.ports p cross join lateral public.port_offered_goods(p.id) o
), near as (
  select s.good_id, e.key as code, min(e.value::numeric) as nm
    from offered s join public.sea_reaches sr on sr.port_id = s.port_id
   cross join lateral jsonb_each_text(sr.reaches) e
   group by 1, 2
), far as (
  select pg.port_id, count(*) as n
    from public.port_goods pg join public.ports p on p.id = pg.port_id
    join near n on n.good_id = pg.good_id and n.code = p.code
   where n.nm > 12000 and not exists (select 1 from offered o where o.port_id = pg.port_id and o.good_id = pg.good_id)
   group by 1 order by 2 desc, 1 limit 1
), maker as (
  select o.port_id from offered o join public.goods g on g.id = o.good_id where g.code = 'kimchi' order by 1 limit 1
)
select distinct pg.port_id, pg.good_id
  from public.port_goods pg join public.goods g on g.id = pg.good_id
 where g.code = 'kimchi'
    or pg.port_id in (select port_id from far) and md5(pg.good_id::text || '0173a') < '4'
    or pg.port_id in (select port_id from maker) and md5(pg.good_id::text || '0173b') < '4'
    or md5(pg.port_id::text || pg.good_id::text || '0173') < '0031';

create temp table sample_ports_0173 on commit drop as
with offered as (
  select p.id as port_id, o.good_id from public.ports p cross join lateral public.port_offered_goods(p.id) o
)
select p.id as port_id, p.code, ord
  from (select (select o.port_id from offered o join public.goods g on g.id = o.good_id where g.code = 'kimchi' order by 1 limit 1) as id, 1 as ord
        union all
        select (select p2.id from public.ports p2 where p2.code = 'LON'), 2) x
  join public.ports p on p.id = x.id;

-- THE RANKINGS BEFORE: world.trade_routes from the two sample harbours, no fleet, timed (notice only).
create temp table timing_0173 (phase text, ms numeric, n int) on commit drop;
do $$
declare
  t0 timestamptz;
  v_n int := 0;
  r record;
begin
  t0 := clock_timestamp();
  for r in select port_id from sample_ports_0173 loop
    v_n := v_n + (select count(*) from world.trade_routes(r.port_id, null, null, 20, null));
  end loop;
  insert into timing_0173 values ('before', extract(epoch from clock_timestamp() - t0) * 1000, v_n);
end $$;

-- ── 2. THE KNOBS ──────────────────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('haul_max', to_jsonb(600),
   '0173: the most a good''s price is multiplied by for the sea it crossed — at haul_reach_nm and beyond from its '
   'nearest maker. Set by the owner''s order (2026-10-17: Korea → London, bought for ~100, sells for ~50k): '
   'Mokpo → London 14,006 nm gives × 391. docs/research/UWO_TRADE_PRICES.md.'),
  ('haul_reach_nm', to_jsonb(14500),
   '0173: the sailing distance (public.sea_reaches nm) from a good''s nearest maker at which its haul reaches haul_max.'),
  ('haul_curve', to_jsonb(2.0),
   '0173: the shape of the haul: haul = haul_max ^ ((nm / haul_reach_nm) ^ haul_curve). 2.0 = convex, as the '
   'Uncharted Waters Origin ratios players quote (adjacent sea ~1.1–1.5×, one ocean 2–5×, the far side of the world '
   'tens to hundreds): 1.03 at 1,000 nm, 2.1 at 5,000, 21 at 10,000.');

-- ── 3. THE ARITHMETIC AND THE DERIVATION ──────────────────────────────────────────────────────
create function world.haul_at(p_nm numeric, p_max numeric, p_reach_nm numeric, p_curve numeric)
returns numeric
language sql
immutable
parallel safe
as $$
  -- 0173: THE HAUL — what a good's price is multiplied by for the sea between this city and its nearest
  -- maker: max ^ (min(1, nm / reach) ^ curve), at 4 dp. 1 at a maker (nm 0) and where no sea lane reaches
  -- (nm null: what the sea cannot fetch earns no premium).
  select case when p_nm is null or p_nm <= 0 then 1::numeric
              else round(exp(ln(p_max) * power(least(1::numeric, p_nm / p_reach_nm), p_curve)), 4) end
$$;

create function world.haul_rows()
returns table (port_id uuid, good_id uuid, haul_nm numeric, haul numeric)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0173: THE DERIVATION, every market row at once: the sailing distance (public.sea_reaches, the water
  -- raster's nm) from the nearest city whose roster offers the good (public.port_offered_goods — the
  -- authority world.affinity_for reads), 0 at a city that offers it, and world.haul_at over the three
  -- knobs. port_goods.haul_nm / haul are filled from this and the world guard compares them with it.
  with k as materialized (
    select public.wc_num('haul_max') as mx, public.wc_num('haul_reach_nm') as reach, public.wc_num('haul_curve') as c
  ), offered as materialized (
    select p.id as port_id, o.good_id from public.ports p cross join lateral public.port_offered_goods(p.id) o
  ), near as materialized (
    select s.good_id, e.key as code, min(e.value::numeric) as nm
      from offered s join public.sea_reaches sr on sr.port_id = s.port_id
     cross join lateral jsonb_each_text(sr.reaches) e
     group by 1, 2
  )
  select pg.port_id, pg.good_id, d.nm, world.haul_at(d.nm, k.mx, k.reach, k.c)
    from public.port_goods pg
    join public.ports p on p.id = pg.port_id
   cross join k
    left join offered o on o.port_id = pg.port_id and o.good_id = pg.good_id
    left join near n on n.good_id = pg.good_id and n.code = p.code
   cross join lateral (select case when o.port_id is not null then 0::numeric else round(n.nm, 1) end as nm) d
$$;

revoke all on function world.haul_at(numeric, numeric, numeric, numeric) from public, anon, authenticated;
revoke all on function world.haul_rows() from public, anon, authenticated;

alter table public.port_goods
  add column haul_nm numeric(8,1),
  add column haul numeric(10,4) not null default 1 check (haul >= 1);
comment on column public.port_goods.haul_nm is
  '0173: the sailing distance in nm from the nearest city that offers this good (0 here if this city does; '
  'null where no sea lane reaches). Derived by world.haul_rows(); the world guard compares it.';
comment on column public.port_goods.haul is
  '0173: the haul — what this row''s price is multiplied by for the sea it crossed (world.haul_at over haul_nm '
  'and the haul_* knobs; 1 at a maker). A term of world.mid_from_terms, read by world.mid_terms.';

do $$
declare
  t0 timestamptz := clock_timestamp();
  v_n int;
begin
  update public.port_goods pg set haul_nm = h.haul_nm, haul = h.haul
    from world.haul_rows() h
   where h.port_id = pg.port_id and h.good_id = pg.good_id;
  get diagnostics v_n = row_count;
  insert into timing_0173 values ('fill', extract(epoch from clock_timestamp() - t0) * 1000, v_n);
end $$;

-- ── 4. THE RE-CUTS (hunks sliced from the live bodies; each occurs once; each body reverses) ──
create temp table hunks_0173 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0173 (fn, n, old, new) values
-- world.mid_from_terms: the haul, after the band (a new 13-argument form; the old one is dropped below)
('world.mid_from_terms(numeric, numeric, numeric, numeric, numeric, numeric, numeric, integer, numeric, numeric, numeric, numeric)', 1,
$h$p_affinity numeric, p_demand numeric, p_stock_target numeric$h$,
$h$p_affinity numeric, p_demand numeric, p_haul numeric, p_stock_target numeric$h$),
('world.mid_from_terms(numeric, numeric, numeric, numeric, numeric, numeric, numeric, integer, numeric, numeric, numeric, numeric)', 2,
$h$  -- floor and ceiling, or a wanted good in a thin market runs away.
$h$,
$h$  -- floor and ceiling, or a wanted good in a thin market runs away.
  -- 0173: × THE HAUL (port_goods.haul, the sea between this city and the good's nearest maker), applied to
  -- the BANDED product: the band bounds the market's own swing around the distance, never the distance.
$h$),
('world.mid_from_terms(numeric, numeric, numeric, numeric, numeric, numeric, numeric, integer, numeric, numeric, numeric, numeric)', 3,
$h$           p_band_lo * p_base), p_band_hi * p_base), 4)$h$,
$h$           p_band_lo * p_base), p_band_hi * p_base) * p_haul, 4)$h$),
-- world.mid_terms: the row's haul, read with the row
('world.mid_terms(uuid, uuid)', 1,
$h$OUT m_demand numeric, OUT m_target numeric$h$,
$h$OUT m_demand numeric, OUT m_haul numeric, OUT m_target numeric$h$),
('world.mid_terms(uuid, uuid)', 2,
$h$  select g.base_value, pg.affinity, pg.demand, pg.stock_target, pg.drift, pg.season_mod, p.dev_commerce
    into m_base, m_affinity, m_demand, m_target, m_drift, m_season, m_dev$h$,
$h$  select g.base_value, pg.affinity, pg.demand, pg.haul, pg.stock_target, pg.drift, pg.season_mod, p.dev_commerce   -- 0173: + haul
    into m_base, m_affinity, m_demand, m_haul, m_target, m_drift, m_season, m_dev$h$),
-- world.mid_price
('world.mid_price(uuid, uuid, numeric)', 1,
$h$  return world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_target, p_stock, t.m_drift,$h$,
$h$  return world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_haul, t.m_target, p_stock, t.m_drift,   -- 0173: + haul$h$),
-- world.quote_priced: both sides' steps
('world.quote_priced(uuid, uuid, numeric, text, numeric, uuid, numeric, numeric, numeric, numeric)', 1,
$h$      exit when v_n <= 0;
      v_mid  := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_target, v_stock, t.m_drift,   -- 0134$h$,
$h$      exit when v_n <= 0;
      v_mid  := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_haul, t.m_target, v_stock, t.m_drift,   -- 0134, 0173$h$),
('world.quote_priced(uuid, uuid, numeric, text, numeric, uuid, numeric, numeric, numeric, numeric)', 2,
$h$    else
      v_mid  := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_target, v_stock, t.m_drift,   -- 0134$h$,
$h$    else
      v_mid  := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_haul, t.m_target, v_stock, t.m_drift,   -- 0134, 0173$h$),
-- public.price_path: the path, its low and its high
('public.price_path(uuid, uuid, integer)', 1,
$h$    mid   := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_target, v_s, r.mean,$h$,
$h$    mid   := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_haul, t.m_target, v_s, r.mean,   -- 0173: + haul$h$),
('public.price_path(uuid, uuid, integer)', 2,
$h$    lo    := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_target, v_s,$h$,
$h$    lo    := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_haul, t.m_target, v_s,$h$),
('public.price_path(uuid, uuid, integer)', 3,
$h$    hi    := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_target, v_s,$h$,
$h$    hi    := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_haul, t.m_target, v_s,$h$),
-- world.market: the range
('world.market(uuid)', 1,
$h$        'range_lo', world.mid_from_terms(g.base_value, pg.affinity, pg.demand, pg.stock_target,$h$,
$h$        'range_lo', world.mid_from_terms(g.base_value, pg.affinity, pg.demand, pg.haul, pg.stock_target,   -- 0173: + haul$h$),
('world.market(uuid)', 2,
$h$        'range_hi', world.mid_from_terms(g.base_value, pg.affinity, pg.demand, pg.stock_target,$h$,
$h$        'range_hi', world.mid_from_terms(g.base_value, pg.affinity, pg.demand, pg.haul, pg.stock_target,$h$);

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
  for d in select * from defs_before_0173 order by ord loop
    v_def := d.def;
    for h in select * from hunks_0173 where fn = d.fn order by n loop
      if pg_temp.occurs_0173(v_def, h.old) <> 1 then
        raise exception '0173 self-assert FAIL: % hunk % occurs % time(s), not once — the deployed body is not what this file was written against',
          d.fn, h.n, pg_temp.occurs_0173(v_def, h.old);
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    if v_def = d.def then
      raise exception '0173 self-assert FAIL: % has no hunk', d.fn;
    end if;
    -- the OUT row of world.mid_terms changes, so it is dropped and created (nothing in the catalogue
    -- depends on a PL/pgSQL function); mid_from_terms' new form is a new signature beside the old one
    if d.ord = 2 then
      execute 'drop function world.mid_terms(uuid, uuid)';
    end if;
    execute v_def;
    v_new := case d.ord
               when 1 then 'world.mid_from_terms(numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, integer, numeric, numeric, numeric, numeric)'::regprocedure
               else d.fn::regprocedure end;
    if d.ord in (1, 2) then
      -- a function CREATEd here starts from the default ACL (on Supabase that grants service_role too);
      -- put the pre-image's back (server-only: the owner alone), and the compare below proves it
      execute format('revoke all on function %s from public, anon, authenticated, service_role', v_new::text);
    end if;
    -- REVERSE TO ORIGINAL: the live body, its hunks undone, is the pre-image byte for byte
    v_rev := replace(pg_get_functiondef(v_new), E'\r', '');
    for h in select * from hunks_0173 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0173(v_rev, h.new) <> 1 then
        raise exception '0173 self-assert FAIL: % new hunk % is not in the live body once', d.fn, h.n;
      end if;
      v_rev := replace(v_rev, h.new, h.old);
    end loop;
    if v_rev <> d.def then
      raise exception '0173 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef,
           coalesce(pr.proconfig::text, '') as cfg, pr.proowner as owner
      into p from pg_proc pr where pr.oid = v_new;
    if p.acl <> d.acl or p.vol <> d.vol or p.secdef <> d.secdef or p.cfg <> d.cfg or p.owner <> d.owner then
      raise exception '0173 self-assert FAIL: % changed its ACL (% → %), owner, volatility, definer or config', d.fn, d.acl, p.acl;
    end if;
    v_n := v_n + 1;
  end loop;
  if v_n <> 6 then
    raise exception '0173 self-assert FAIL: % bodies re-cut, not 6', v_n;
  end if;
end $$;

-- the 12-argument expression is retired: every caller now passes the haul (asserted below)
drop function world.mid_from_terms(numeric, numeric, numeric, numeric, numeric, numeric, numeric, integer, numeric, numeric, numeric, numeric);

-- ── 5. THE RANKINGS AFTER (timed, notice only) ────────────────────────────────────────────────
do $$
declare
  t0 timestamptz;
  v_n int := 0;
  r record;
begin
  t0 := clock_timestamp();
  for r in select port_id from sample_ports_0173 loop
    v_n := v_n + (select count(*) from world.trade_routes(r.port_id, null, null, 20, null));
  end loop;
  insert into timing_0173 values ('after', extract(epoch from clock_timestamp() - t0) * 1000, v_n);
end $$;

-- ── 6. SELF-ASSERT ────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_rows     int;
  v_bad      int;
  v_ex       text;
  v_far      int;
  v_makers   int;
  v_mono     int;
  v_x        record;
  v_q        int;
  v_p        int;
  v_o        int;
  v_m        int;
  v_kimchi   text;
  v_goods    text;
  v_tb       numeric;
  v_ta       numeric;
  v_fill     numeric;
  v_mkt      jsonb;
  r          record;
begin
  -- (a) THE ROWS ARE THE DERIVATION, both columns, every row; makers at 1; the haul rises with the sea
  select count(*) into v_rows from public.port_goods;
  select count(*), min(pg.port_id::text || '/' || pg.good_id::text) into v_bad, v_ex
    from public.port_goods pg
    left join world.haul_rows() h on h.port_id = pg.port_id and h.good_id = pg.good_id
   where h.port_id is null or pg.haul_nm is distinct from h.haul_nm or pg.haul is distinct from h.haul;
  if v_bad > 0 then
    raise exception '0173 self-assert FAIL: % of % market rows differ from world.haul_rows() (e.g. %)', v_bad, v_rows, v_ex;
  end if;
  select count(*), count(*) filter (where pg.haul <> 1 or pg.haul_nm is distinct from 0) into v_makers, v_bad
    from public.ports p cross join lateral public.port_offered_goods(p.id) o
    join public.port_goods pg on pg.port_id = p.id and pg.good_id = o.good_id;
  if v_makers = 0 or v_bad > 0 then
    raise exception '0173 self-assert FAIL: a city that offers a good does not price it at haul 1 / 0 nm (% offered rows)', v_makers;
  end if;
  select count(*) into v_far from public.port_goods where haul > 100;
  if v_far = 0 or (select count(*) from public.port_goods where haul = 1) = 0 then
    raise exception '0173 self-assert FAIL: the haul is vacuous (% rows above 100, % at 1)', v_far, (select count(*) from public.port_goods where haul = 1);
  end if;
  -- monotone: no row has a smaller haul than a row with a shorter haul_nm (the one curve)
  select count(*) into v_mono from (
    select haul, lag(haul) over (order by haul_nm, haul) as prev from public.port_goods where haul_nm is not null) x
   where x.haul < x.prev;
  if v_mono > 0 then
    raise exception '0173 self-assert FAIL: the haul falls with distance on % row(s)', v_mono;
  end if;

  -- (b) THE ONE EXPRESSION, every market row: new = old × haul (to the 4-dp rounding of each), and = old
  --     to the digit where the haul is 1
  select count(*), min(x.port_id::text || '/' || x.good_id::text || ' ' || x.nw || ' vs ' || x.od || ' x ' || x.haul) into v_bad, v_ex
    from (select pg.port_id, pg.good_id, pg.haul,
                 world.mid_from_terms(g.base_value, pg.affinity, pg.demand, pg.haul, pg.stock_target, pg.stock, pg.drift,
                                      pg.season_mod, p.dev_commerce, k.e, k.dd, k.blo, k.bhi) as nw,
                 pg_temp.mft_old_0173(g.base_value, pg.affinity, pg.demand, pg.stock_target, pg.stock, pg.drift,
                                      pg.season_mod, p.dev_commerce, k.e, k.dd, k.blo, k.bhi) as od
            from public.port_goods pg
            join public.goods g on g.id = pg.good_id
            join public.ports p on p.id = pg.port_id
           cross join (select public.wc_num('price_elasticity') as e, public.wc_num('mid_dev_discount') as dd,
                              public.wc_num('price_band_lo') as blo, public.wc_num('price_band_hi') as bhi) k) x
   where (x.haul = 1 and x.nw <> x.od)
      or abs(x.nw - x.od * x.haul) > 0.00005 * x.haul + 0.00005;
  if v_bad > 0 then
    raise exception '0173 self-assert FAIL: the one expression is not the old one × the haul on % of % rows (e.g. %)', v_bad, v_rows, v_ex;
  end if;

  -- (c) THE READERS, old tree vs new, on the sample
  --   mid_price
  select count(*), min(s.port_id::text || '/' || s.good_id::text) into v_bad, v_ex
    from sample_0173 s join public.port_goods pg on pg.port_id = s.port_id and pg.good_id = s.good_id
   cross join lateral (select world.mid_price(s.port_id, s.good_id, pg.stock) as nw,
                              pg_temp.mid_price_old_0173(s.port_id, s.good_id, pg.stock) as od) m
   where (pg.haul = 1 and m.nw <> m.od) or abs(m.nw - m.od * pg.haul) > 0.00005 * pg.haul + 0.00005;
  if v_bad > 0 then
    raise exception '0173 self-assert FAIL: world.mid_price is not the old one × the haul on % sample row(s) (e.g. %)', v_bad, v_ex;
  end if;
  --   quotes: both sides, three sizes, old tree and new in ONE statement (one snapshot: a trade elsewhere
  --   cannot come between them): units and the end stock unmoved, the average × the haul (each 10-tun step
  --   rounds to the cent once), the same to the cent where the haul is 1
  select count(*) as n,
         count(*) filter (where (pg.haul = 1 and (n.total, n.avg_price) is distinct from (o.total, o.avg_price))
                             or n.units <> o.units or n.end_stock <> o.end_stock
                             or (o.units > 0 and abs(n.avg_price - o.avg_price * pg.haul) > 0.01 * pg.haul + 0.01)) as bad,
         min(case when n.units <> o.units or (o.units > 0 and abs(n.avg_price - o.avg_price * pg.haul) > 0.01 * pg.haul + 0.01)
                  then x.side || ' ' || x.qty || ' ' || s.port_id || '/' || s.good_id || ': ' || n.avg_price || ' vs ' || o.avg_price || ' x ' || pg.haul end) as ex
    into v_x
    from sample_0173 s
    join public.port_goods pg on pg.port_id = s.port_id and pg.good_id = s.good_id
   cross join (values ('buy', 10::numeric), ('buy', 50), ('buy', 200), ('sell', 10), ('sell', 50), ('sell', 200)) x(side, qty)
   cross join lateral world.quote(s.port_id, s.good_id, x.qty, x.side, null, null) n
   cross join lateral pg_temp.quote_priced_old_0173(s.port_id, s.good_id, x.qty, x.side, null, null, null, null, null, null) o;
  v_q := v_x.n;
  if v_x.bad > 0 or v_x.n = 0 then
    raise exception '0173 self-assert FAIL: % of % quotes are not the pre-image''s × the haul (e.g. %)', v_x.bad, v_x.n, v_x.ex;
  end if;
  --   a limit at the haul-1 rows: the same fill as the old tree at the same limit
  select count(*) as n, count(*) filter (where (n.units, n.total) is distinct from (o.units, o.total)) as bad into v_x
    from sample_0173 s join public.port_goods pg on pg.port_id = s.port_id and pg.good_id = s.good_id and pg.haul = 1
   cross join lateral (select world.mid_price(s.port_id, s.good_id, pg.stock) * 1.04 as lim) l
   cross join lateral world.quote(s.port_id, s.good_id, 200, 'buy', l.lim, null) n
   cross join lateral pg_temp.quote_priced_old_0173(s.port_id, s.good_id, 200, 'buy', l.lim, null, null, null, null, null) o;
  if v_x.n = 0 or v_x.bad > 0 then
    raise exception '0173 self-assert FAIL: a limited buy at a maker filled differently from the pre-image on % of % rows', v_x.bad, v_x.n;
  end if;
  --   the path, old tree and new in one statement: stock and drift unmoved, every price × the haul
  select count(*), count(*) filter (where n.stock <> o.stock or n.drift <> o.drift
                                       or abs(n.mid - o.mid * pg.haul) > 0.00005 * pg.haul + 0.00005
                                       or abs(n.lo - o.lo * pg.haul) > 0.00005 * pg.haul + 0.00005
                                       or abs(n.hi - o.hi * pg.haul) > 0.00005 * pg.haul + 0.00005)
    into v_p, v_bad
    from (select * from sample_0173 where md5(good_id::text || port_id::text) < '6') s
    join public.port_goods pg on pg.port_id = s.port_id and pg.good_id = s.good_id
   cross join lateral pg_temp.price_path_old_0173(s.port_id, s.good_id, 6) o
    join lateral public.price_path(s.port_id, s.good_id, 6) n on n.k = o.k;
  if v_bad > 0 or v_p = 0 then
    raise exception '0173 self-assert FAIL: % of % path steps are not the pre-image''s × the haul', v_bad, v_p;
  end if;
  --   the outlook (0170) does not fork from world.price: its now is world.price's, all three sides, and it
  --   is the distance-scaled price (asserted on the rows with a haul above 100)
  select count(*), count(*) filter (where (ol.m->'points'->0->>'value')::numeric <> pr.mid
                                       or (ol.a->'points'->0->>'value')::numeric <> pr.ask
                                       or (ol.b->'points'->0->>'value')::numeric <> pr.bid),
         count(*) filter (where pg.haul > 100)
    into v_o, v_bad, v_far
    from sample_0173 s join public.port_goods pg on pg.port_id = s.port_id and pg.good_id = s.good_id
   cross join lateral world.price(s.port_id, s.good_id) pr
   cross join lateral (select world.price_outlook(s.port_id, s.good_id, 2, 'mid') as m,
                              world.price_outlook(s.port_id, s.good_id, 2, 'ask') as a,
                              world.price_outlook(s.port_id, s.good_id, 2, 'bid') as b) ol
   where md5(s.good_id::text || 'o') < '8';
  if v_bad > 0 or v_o = 0 or v_far = 0 then
    raise exception '0173 self-assert FAIL: the outlook''s now differs from world.price on % of % rows (% of them far)', v_bad, v_o, v_far;
  end if;

  -- (d) world.market at the two sample harbours (it winds the drift tick, so it runs in a sub-block that is
  --     rolled back): range = the old expression × the haul; buy / sell / mid = world.price
  v_m := 0;
  for r in select port_id, code from sample_ports_0173 loop
    begin
      v_mkt := world.market(r.port_id);
      select count(*) as n, count(*) filter (where
                 abs((e->>'range_lo')::numeric - pg_temp.mft_old_0173(g.base_value, pg.affinity, pg.demand, pg.stock_target, pg.stock,
                        -public.wc_num('drift_clamp'), pg.season_mod, p.dev_commerce, public.wc_num('price_elasticity'),
                        public.wc_num('mid_dev_discount'), public.wc_num('price_band_lo'), public.wc_num('price_band_hi')) * pg.haul)
                   > 0.00005 * pg.haul + 0.00005
              or abs((e->>'range_hi')::numeric - pg_temp.mft_old_0173(g.base_value, pg.affinity, pg.demand, pg.stock_target, pg.stock,
                        public.wc_num('drift_clamp'), pg.season_mod, p.dev_commerce, public.wc_num('price_elasticity'),
                        public.wc_num('mid_dev_discount'), public.wc_num('price_band_lo'), public.wc_num('price_band_hi')) * pg.haul)
                   > 0.00005 * pg.haul + 0.00005
              or (e->>'mid')::numeric <> pr.mid or (e->>'buy')::numeric <> pr.ask or (e->>'sell')::numeric <> pr.bid) as bad
        into v_x
        from jsonb_array_elements(v_mkt->'goods') e
        join public.port_goods pg on pg.port_id = r.port_id and pg.good_id = (e->>'good_id')::uuid
        join public.goods g on g.id = pg.good_id
        join public.ports p on p.id = pg.port_id
       cross join lateral world.price(pg.port_id, pg.good_id) pr;
      if v_x.n = 0 or v_x.bad > 0 then
        raise exception '0173 self-assert FAIL: world.market at % — % of % goods'' range or sides are not the one price × the haul', r.code, v_x.bad, v_x.n;
      end if;
      v_m := v_m + v_x.n;
      raise exception using errcode = 'ZX173', message = 'roll back the market read';
    exception when sqlstate 'ZX173' then null;
    end;
  end loop;

  -- (e) THE CALLERS: every body naming the one expression is one of the four re-cut, and passes the haul;
  --     the 12-argument form is gone; the leaves are server-only
  if (select string_agg(n.nspname || '.' || p.proname, ',' order by n.nspname || '.' || p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('world', 'public', 'cmd', 'voyage') and p.prosrc like '%mid_from_terms(%')
     is distinct from 'public.price_path,world.market,world.mid_price,world.quote_priced'
     or exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname in ('world', 'public', 'cmd', 'voyage') and p.prosrc like '%mid_from_terms(%'
                   and pg_temp.occurs_0173(p.prosrc, 'mid_from_terms(') <> pg_temp.occurs_0173(p.prosrc, 'haul, ')) then
    raise exception '0173 self-assert FAIL: a caller of world.mid_from_terms does not pass the haul';
  end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'world' and p.proname = 'mid_from_terms') <> 1
     or (select pronargs from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'world' and p.proname = 'mid_from_terms') <> 13 then
    raise exception '0173 self-assert FAIL: world.mid_from_terms is not one 13-argument function';
  end if;
  if has_function_privilege('authenticated', 'world.haul_rows()', 'execute')
     or has_function_privilege('anon', 'world.haul_at(numeric, numeric, numeric, numeric)', 'execute')
     or has_function_privilege('authenticated', 'world.mid_terms(uuid, uuid)', 'execute')
     or has_function_privilege('authenticated', 'world.mid_from_terms(numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, integer, numeric, numeric, numeric, numeric)', 'execute') then
    raise exception '0173 self-assert FAIL: a price leaf is callable by a client';
  end if;
  if exists (select 1 from public.client_write_grants()) then
    raise exception '0173 self-assert FAIL: a client role holds a write';
  end if;

  -- THE RECEIPT: kimchi from its maker to the far side, and five goods across the world (mid now vs the
  -- pre-image's — a statement, not an assert)
  select string_agg(format('%s %s nm ×%s: %s → %s', p.code, pg.haul_nm, pg.haul,
                           round(pg_temp.mid_price_old_0173(pg.port_id, pg.good_id, pg.stock), 2),
                           round(world.mid_price(pg.port_id, pg.good_id, pg.stock), 2)), '; ' order by pg.haul_nm)
    into v_kimchi
    from public.port_goods pg join public.goods g on g.id = pg.good_id join public.ports p on p.id = pg.port_id
   where g.code = 'kimchi' and p.code in ('MOK', 'BUS', 'NAG', 'MAN', 'MAL', 'CAL', 'GOA', 'ADE', 'ALE', 'VEN', 'LIS', 'AMS', 'LON');
  select ms into v_tb from timing_0173 where phase = 'before';
  select ms into v_ta from timing_0173 where phase = 'after';
  select ms into v_fill from timing_0173 where phase = 'fill';

  raise notice '0173 self-assert ok: A GOOD IS WORTH THE SEA IT CROSSED. TERM: haul = % ^ ((nm / %) ^ %), nm by sea from the nearest maker; % market rows = world.haul_rows() (% at a maker, % above × 100); the one expression = the pre-image × haul on all % rows; mid_price on % sample rows, % quotes, % path steps, the outlook''s now = world.price on % rows, world.market on % goods at 2 harbours; 6 bodies reverse to their pre-images, ACL / owner / volatility / definer / config unmoved; the 12-argument form dropped. KIMCHI (mid, pre-image → now): %. TIMING: fill % ms; rankings from the two sample harbours % ms → % ms.',
    public.wc_num('haul_max'), public.wc_num('haul_reach_nm'), public.wc_num('haul_curve'),
    v_rows, v_makers, (select count(*) from public.port_goods where haul > 100), v_rows,
    (select count(*) from sample_0173), v_q, v_p, v_o, v_m, v_kimchi, round(v_fill), round(v_tb), round(v_ta);
end $$;
