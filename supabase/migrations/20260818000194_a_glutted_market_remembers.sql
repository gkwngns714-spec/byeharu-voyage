-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0194 — A GLUTTED MARKET REMEMBERS  (PRICE_FACTORS slice P5: a heavy sale leaves a mark that fades)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY ─────────────────────────────────────────────────────────────────────────────────────────
-- The owner, 2026-10-18: *"is there a way for the prices move on many different factors? like … merchants"*.
-- docs/PRICE_FACTORS.md §3.4 / F7: today a sale lowers the price through the stock term alone, and the stock
-- refills toward its target within game days, so 800-odd merchant companies dumping the same pepper leave no
-- lasting trace. Borrowed: Uncharted Waters Online's 폭락 (selling too much at one port crashes it, so players
-- split their sales — Inven 2597/146) and Patrician's asymmetry (a flooded town's sell price falls and stays
-- down while its people eat through the glut — gog.com Patrician forum). 0190 made the crowding SEEN; this
-- makes it FELT.
--
-- ── THE TERM ────────────────────────────────────────────────────────────────────────────────────
--     mid = round(band(base × affinity × demand × stock × drift × season × development) × haul × (1 − glut), 4)
--     on a SELL of q units:  glut := least(glut_max, glut + glut_per_depth × q / stock_target)
--     each game day:         glut := glut × (1 − glut_decay) ^ days            (with the stock's regeneration)
--     knobs: glut_max 0.30 · glut_per_depth 0.30 · glut_decay 0.50 (half-life one game day = one real hour)
-- Applied after the band, like the haul: the band bounds the market's own swing, the glut is a crash on top.
-- A BUY does not lower it (a buyer clears a glut only by moving the stock term, as now). A sale of a whole
-- market's depth costs 30 %, half of it 15 %; nothing a city can be sold lowers its price by more than 30 %.
-- It is a MARKET term: everyone at that quay sees the same glutted price, players and merchants alike.
--
-- ── WHERE IT LIVES (one authority each) ─────────────────────────────────────────────────────────
-- (1) port_goods.glut — NEW column (0 – 0.5 by CHECK; 0 on every row when this lands, so no price moves).
-- (2) world.mid_from_terms gains p_glut (after p_haul): the 14-argument form; the 13-argument form is DROPPED
--     once its four callers are re-cut (0066's and 0173's pattern).
-- (3) world.mid_terms gains OUT m_glut (read with the row): every reader of the one price — world.mid_price,
--     world.price, world.quote / quote_priced, world.trade_routes, the merchants' planner, public.price_path,
--     world.price_outlook, world.price_why — prices the glut without a second path.
-- (4) Re-cut to pass it: world.mid_price (1 hunk), world.quote_priced (2), public.price_path (3 + the glut
--     faded at each game day the path crosses, as the tick fades it: 3 more), world.market (2: range_lo / hi).
-- (5) cmd.do_sell (the ONE sale) raises it in the UPDATE of the row it already makes (1 hunk).
-- (6) public.tick_market_drift fades it in the regeneration UPDATE it already makes, in closed form over the
--     game days passed, exactly as the stock (1 hunk).
-- (7) world.price_why serves it as its own term, `glut` (1 hunk); the terms still multiply back to the mid.
--
-- ── WHAT IT DELIBERATELY DOES NOT DO ────────────────────────────────────────────────────────────
-- Touch the stock term, the haul, the band, the spread, the tax, a purse, any knob of the existing terms or any
-- grant. Raise the glut on a BUY, or inside a sale's own 10-unit walk (the walk prices the stock as before; the
-- mark is left by the sale as a whole).
--
-- ── THE PROOF (only this file's own rows; probes in sub-blocks rolled back whole) ──────────────
-- (a) every market row carries glut 0, so THE ONE EXPRESSION over a sample: new = the 13-argument pre-image
--     (pg_temp) exactly, through world.mid_price, world.quote (buy and sell × 10 / 200), public.price_path
--     (every step) and world.market's range — old tree and new in ONE statement each;
-- (b) a planted glut 0.2 on a probe row: world.mid_price = the pre-image × 0.8 (to the rounding), the
--     quote's units likewise, price_path's steps × 0.8 until a game day passes and × 0.9 after (the fade),
--     world.market's range × 0.8, world.price_why's glut term 0.8 with its terms multiplying to the mid;
-- (c) a probe company sells 10 units at Lisbon through cmd.do_sell: the row's glut becomes 0.30 × 10 /
--     stock_target (rounded), the next unit's bid is lower by that share; a BUY leaves it alone;
-- (d) public.tick_market_drift on the probe harbour with the row's last regeneration a day back halves it;
-- (e) every caller of the expression is one of the four re-cut; the 13-argument form is gone; every body
--     reverses to its pre-image; ACL / owner / volatility / definer / config unmoved; mid_terms' ACL put back.
-- Timings: raise notice only.
--
-- ── LOCKS AND TIME ──────────────────────────────────────────────────────────────────────────────
-- ALTER TABLE port_goods ADD COLUMN with a constant default (catalogue only; ACCESS EXCLUSIVE for that
-- instant), then catalogue-only CREATE / DROP FUNCTION. No UPDATE of the market (every glut starts at 0).
-- No LOCK TABLE, no set role, no set local, no begin. Deploy with the clock unwound.
-- ROLLBACK: set glut_max to 0 (no sale can raise a glut) and `update public.port_goods set glut = 0 where
-- glut <> 0`; every price is the pre-image's again. Or a forward slice restoring the bodies from these hunks.
-- VERSION: 0194 PROVISIONAL — prod head 0189 when re-checked (2026-10-19; all 19 hunks occur once on prod at 0189; the coordinator's order: 0190 P2, 0191 P3, …, then this);
-- renumbered to head + 1 at push.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

create or replace function pg_temp.occurs_0194(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 1. THE PRE-IMAGES ─────────────────────────────────────────────────────────────────────────
create temp table defs_before_0194 on commit drop as
select f.fn, f.ord,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg,
       (select p.proowner from pg_proc p where p.oid = f.fn::regprocedure) as owner
  from (values (1, 'world.mid_from_terms(numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, integer, numeric, numeric, numeric, numeric)'),
               (2, 'world.mid_terms(uuid, uuid)'),
               (3, 'world.mid_price(uuid, uuid, numeric)'),
               (4, 'world.quote_priced(uuid, uuid, numeric, text, numeric, uuid, numeric, numeric, numeric, numeric)'),
               (5, 'public.price_path(uuid, uuid, integer)'),
               (6, 'world.market(uuid)'),
               (7, 'cmd.do_sell(uuid, jsonb)'),
               (8, 'public.tick_market_drift(timestamp with time zone, uuid)'),
               (9, 'world.price_why(uuid, uuid)')) f(ord, fn);

do $$
begin
  if (select count(*) from defs_before_0194 where def is not null) <> 9 then
    raise exception '0194 self-assert FAIL: % of the 9 bodies found', (select count(*) from defs_before_0194 where def is not null);
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'port_goods' and column_name = 'glut')
     or exists (select 1 from public.world_config where key in ('glut_max', 'glut_per_depth', 'glut_decay')) then
    raise exception '0194 self-assert FAIL: something this file creates already exists';
  end if;
  if (select string_agg(n.nspname || '.' || p.proname, ',' order by n.nspname || '.' || p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('world', 'public', 'cmd', 'voyage') and p.prosrc like '%mid_from_terms(%')
     is distinct from 'public.price_path,world.market,world.mid_price,world.quote_priced' then
    raise exception '0194 self-assert FAIL: the callers of world.mid_from_terms are %, not the four this file re-cuts',
      (select string_agg(n.nspname || '.' || p.proname, ',' order by n.nspname || '.' || p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname in ('world', 'public', 'cmd', 'voyage') and p.prosrc like '%mid_from_terms(%');
  end if;
end $$;

-- THE OLD TREE the proofs compare against: the 13-argument expression and its three row-level callers,
-- as pg_temp copies calling it (world.mid_terms' new OUT column is a field they never read).
do $$
declare
  v_def text;
  r     record;
begin
  select def into v_def from defs_before_0194 where ord = 1;
  v_def := replace(v_def, 'CREATE OR REPLACE FUNCTION world.mid_from_terms(', 'CREATE OR REPLACE FUNCTION pg_temp.mft_old_0194(');
  if strpos(v_def, 'FUNCTION pg_temp.mft_old_0194(') = 0 then
    raise exception '0194 self-assert FAIL: the old copy of mid_from_terms was not made from the pre-image';
  end if;
  execute v_def;
  for r in select * from (values (3, 'world.mid_price(', 'pg_temp.mid_price_old_0194('),
                                 (4, 'world.quote_priced(', 'pg_temp.quote_priced_old_0194('),
                                 (5, 'public.price_path(', 'pg_temp.price_path_old_0194(')) x(ord, f, t) loop
    select def into v_def from defs_before_0194 where ord = r.ord;
    v_def := replace(v_def, 'CREATE OR REPLACE FUNCTION ' || r.f, 'CREATE OR REPLACE FUNCTION ' || r.t);
    v_def := replace(v_def, 'world.mid_from_terms(', 'pg_temp.mft_old_0194(');
    if strpos(v_def, 'FUNCTION ' || r.t) = 0 or strpos(v_def, 'world.mid_from_terms(') > 0 then
      raise exception '0194 self-assert FAIL: the old copy of % was not made from the pre-image', r.f;
    end if;
    execute v_def;
  end loop;
end $$;

-- ── 2. THE KNOBS AND THE COLUMN ───────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('glut_max', to_jsonb(0.30),
   '0194: the most a glut takes off a market price (1 - glut). docs/PRICE_FACTORS.md §3.4, F7.'),
  ('glut_per_depth', to_jsonb(0.30),
   '0194: how much a sale raises its market''s glut per market depth sold: + glut_per_depth x units / stock_target.'),
  ('glut_decay', to_jsonb(0.50),
   '0194: the share of a glut that fades each game day (with the stock''s regeneration, public.tick_market_drift; '
   'public.price_path fades it the same way). 0.5 = a half-life of one game day.');

alter table public.port_goods
  add column glut numeric(5,4) not null default 0 check (glut >= 0 and glut <= 0.5);
comment on column public.port_goods.glut is
  '0194: how glutted this market is by recent sales: its price is multiplied by (1 - glut). Raised by cmd.do_sell '
  '(glut_per_depth x units / stock_target, up to glut_max), faded each game day by public.tick_market_drift '
  '(x (1 - glut_decay) per day). A term of world.mid_from_terms, read by world.mid_terms. Runtime state.';

-- ── 3. THE RE-CUTS (hunks sliced from the live bodies; each occurs once; each body reverses) ──
create temp table hunks_0194 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0194 (fn, n, old, new) values
-- world.mid_from_terms: × (1 − glut), after the band and the haul (a new 14-argument form)
('world.mid_from_terms(numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, integer, numeric, numeric, numeric, numeric)', 1,
$h$p_haul numeric, p_stock_target numeric$h$,
$h$p_haul numeric, p_glut numeric, p_stock_target numeric$h$),
('world.mid_from_terms(numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, integer, numeric, numeric, numeric, numeric)', 2,
$h$  -- the BANDED product: the band bounds the market's own swing around the distance, never the distance.
$h$,
$h$  -- the BANDED product: the band bounds the market's own swing around the distance, never the distance.
  -- 0194: × (1 − THE GLUT) (port_goods.glut, recent sales here), likewise after the band: a crash on top.
$h$),
('world.mid_from_terms(numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, integer, numeric, numeric, numeric, numeric)', 3,
$h$           p_band_lo * p_base), p_band_hi * p_base) * p_haul, 4)$h$,
$h$           p_band_lo * p_base), p_band_hi * p_base) * p_haul * (1 - p_glut), 4)$h$),
-- world.mid_terms: the row's glut, read with the row
('world.mid_terms(uuid, uuid)', 1,
$h$OUT m_haul numeric, OUT m_target numeric$h$,
$h$OUT m_haul numeric, OUT m_glut numeric, OUT m_target numeric$h$),
('world.mid_terms(uuid, uuid)', 2,
$h$  select g.base_value, pg.affinity, pg.demand, pg.haul, pg.stock_target, pg.drift, pg.season_mod, p.dev_commerce   -- 0173: + haul
    into m_base, m_affinity, m_demand, m_haul, m_target, m_drift, m_season, m_dev$h$,
$h$  select g.base_value, pg.affinity, pg.demand, pg.haul, pg.glut, pg.stock_target, pg.drift, pg.season_mod, p.dev_commerce   -- 0173: + haul; 0194: + glut
    into m_base, m_affinity, m_demand, m_haul, m_glut, m_target, m_drift, m_season, m_dev$h$),
-- world.mid_price
('world.mid_price(uuid, uuid, numeric)', 1,
$h$  return world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_haul, t.m_target, p_stock, t.m_drift,$h$,
$h$  return world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_haul, t.m_glut, t.m_target, p_stock, t.m_drift,   -- 0194: + glut$h$),
-- world.quote_priced: both sides' steps
('world.quote_priced(uuid, uuid, numeric, text, numeric, uuid, numeric, numeric, numeric, numeric)', 1,
$h$      exit when v_n <= 0;
      v_mid  := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_haul, t.m_target, v_stock, t.m_drift,   -- 0134, 0173$h$,
$h$      exit when v_n <= 0;
      v_mid  := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_haul, t.m_glut, t.m_target, v_stock, t.m_drift,   -- 0134, 0173, 0194$h$),
('world.quote_priced(uuid, uuid, numeric, text, numeric, uuid, numeric, numeric, numeric, numeric)', 2,
$h$    else
      v_mid  := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_haul, t.m_target, v_stock, t.m_drift,   -- 0134, 0173$h$,
$h$    else
      v_mid  := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_haul, t.m_glut, t.m_target, v_stock, t.m_drift,   -- 0134, 0173, 0194$h$),
-- public.price_path: the glut, faded at each game day the path crosses (as the tick fades it), on every step
('public.price_path(uuid, uuid, integer)', 1,
$h$  v_at    timestamptz := now();
begin$h$,
$h$  v_at    timestamptz := now();
  v_g     numeric;                                     -- 0194: the glut, faded as the tick fades it
  v_fade  numeric := 1 - public.wc_num('glut_decay');
begin$h$),
('public.price_path(uuid, uuid, integer)', 2,
$h$  select * into t from world.mid_terms(p_port, p_good);   -- refuses a missing row E_NO_SUCH_GOOD
$h$,
$h$  select * into t from world.mid_terms(p_port, p_good);   -- refuses a missing row E_NO_SUCH_GOOD
  v_g := t.m_glut;
$h$),
('public.price_path(uuid, uuid, integer)', 3,
$h$        v_s   := round(public.stock_after(v_s, t.m_target, v_rate, v_prod, v_d - v_day), 2);   -- the column's scale
$h$,
$h$        v_s   := round(public.stock_after(v_s, t.m_target, v_rate, v_prod, v_d - v_day), 2);   -- the column's scale
        v_g   := round(v_g * power(v_fade, v_d - v_day), 4);   -- 0194: the column's scale, the tick's rule
$h$),
('public.price_path(uuid, uuid, integer)', 4,
$h$    mid   := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_haul, t.m_target, v_s, r.mean,   -- 0173: + haul$h$,
$h$    mid   := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_haul, v_g, t.m_target, v_s, r.mean,   -- 0173: + haul; 0194: + glut$h$),
('public.price_path(uuid, uuid, integer)', 5,
$h$    lo    := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_haul, t.m_target, v_s,$h$,
$h$    lo    := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_haul, v_g, t.m_target, v_s,$h$),
('public.price_path(uuid, uuid, integer)', 6,
$h$    hi    := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_haul, t.m_target, v_s,$h$,
$h$    hi    := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_haul, v_g, t.m_target, v_s,$h$),
-- world.market: the range
('world.market(uuid)', 1,
$h$        'range_lo', world.mid_from_terms(g.base_value, pg.affinity, pg.demand, pg.haul, pg.stock_target,   -- 0173: + haul$h$,
$h$        'range_lo', world.mid_from_terms(g.base_value, pg.affinity, pg.demand, pg.haul, pg.glut, pg.stock_target,   -- 0173: + haul; 0194: + glut$h$),
('world.market(uuid)', 2,
$h$        'range_hi', world.mid_from_terms(g.base_value, pg.affinity, pg.demand, pg.haul, pg.stock_target,$h$,
$h$        'range_hi', world.mid_from_terms(g.base_value, pg.affinity, pg.demand, pg.haul, pg.glut, pg.stock_target,$h$),
-- cmd.do_sell: the sale leaves its mark on the row it already writes
('cmd.do_sell(uuid, jsonb)', 1,
$h$  update public.port_goods set stock = q.end_stock, updated_at = now()
   where port_id = f.port_id and good_id = g.id;$h$,
$h$  update public.port_goods set stock = q.end_stock, updated_at = now(),
         glut = round(least(public.wc_num('glut_max'),
                            glut + public.wc_num('glut_per_depth') * q.units / greatest(stock_target, 1)), 4)   -- 0194: a sale leaves a mark
   where port_id = f.port_id and good_id = g.id;$h$),
-- public.tick_market_drift: the glut fades with the stock's regeneration, in closed form over the days passed
('public.tick_market_drift(timestamp with time zone, uuid)', 1,
$h$         last_regen_day = v_day,
$h$,
$h$         glut = round(pg.glut * power(1 - public.wc_num('glut_decay'), v_day - pg.last_regen_day), 4),   -- 0194: the glut fades
         last_regen_day = v_day,
$h$),
-- world.price_why: the glut, its own term (the terms still multiply back to the mid)
('world.price_why(uuid, uuid)', 1,
$h$      jsonb_build_object('key', 'band',        'mult', case when v_raw > 0 then round(v_clamp / v_raw, 4) else 1 end)),$h$,
$h$      jsonb_build_object('key', 'band',        'mult', case when v_raw > 0 then round(v_clamp / v_raw, 4) else 1 end),
      jsonb_build_object('key', 'glut',        'mult', 1 - t.m_glut)),   -- 0194: recent sales here$h$);

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
  for d in select * from defs_before_0194 order by ord loop
    v_def := d.def;
    for h in select * from hunks_0194 where fn = d.fn order by n loop
      if pg_temp.occurs_0194(v_def, h.old) <> 1 then
        raise exception '0194 self-assert FAIL: % hunk % occurs % time(s), not once — the deployed body is not what this file was written against',
          d.fn, h.n, pg_temp.occurs_0194(v_def, h.old);
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    if v_def = d.def then
      raise exception '0194 self-assert FAIL: % has no hunk', d.fn;
    end if;
    -- mid_terms' OUT row changes, so it is dropped and created; mid_from_terms' new form is a new signature
    if d.ord = 2 then
      execute 'drop function world.mid_terms(uuid, uuid)';
    end if;
    execute v_def;
    v_new := case d.ord
               when 1 then 'world.mid_from_terms(numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, integer, numeric, numeric, numeric, numeric)'::regprocedure
               else d.fn::regprocedure end;
    if d.ord in (1, 2) then
      -- a function CREATEd here starts from the default ACL; put the pre-image's back (server-only)
      execute format('revoke all on function %s from public, anon, authenticated, service_role', v_new::text);
    end if;
    v_rev := replace(pg_get_functiondef(v_new), E'\r', '');
    for h in select * from hunks_0194 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0194(v_rev, h.new) <> 1 then
        raise exception '0194 self-assert FAIL: % new hunk % is not in the live body once', d.fn, h.n;
      end if;
      v_rev := replace(v_rev, h.new, h.old);
    end loop;
    if v_rev <> d.def then
      raise exception '0194 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef,
           coalesce(pr.proconfig::text, '') as cfg, pr.proowner as owner
      into p from pg_proc pr where pr.oid = v_new;
    if p.acl <> d.acl or p.vol <> d.vol or p.secdef <> d.secdef or p.cfg <> d.cfg or p.owner <> d.owner then
      raise exception '0194 self-assert FAIL: % changed its ACL (% → %), owner, volatility, definer or config', d.fn, d.acl, p.acl;
    end if;
    v_n := v_n + 1;
  end loop;
  if v_n <> 9 then
    raise exception '0194 self-assert FAIL: % bodies re-cut, not 9', v_n;
  end if;
end $$;

-- the 13-argument expression is retired: every caller now passes the glut (asserted below)
drop function world.mid_from_terms(numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, integer, numeric, numeric, numeric, numeric);

-- ── 4. THE PROOF ──────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_uid  constant uuid := '00000000-0194-4000-8000-000000000001';
  v_bad  int;
  v_n    int;
  v_port uuid;
  v_good uuid;
  v_tgt  numeric;
  v_p    uuid;
  v_f    uuid;
  v_code text;
  v_g0   numeric;
  v_g1   numeric;
  v_b0   numeric;
  v_b1   numeric;
  v_r    jsonb;
  j      jsonb;
  v_prod numeric;
  v_m    jsonb;
  v_ok   text := '';
  v_t0   timestamptz;
  v_ms   numeric;
  r      record;
begin
  -- (e) the expression's callers are the four; the old form is gone
  if (select string_agg(n.nspname || '.' || p.proname, ',' order by n.nspname || '.' || p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('world', 'public', 'cmd', 'voyage') and p.prosrc like '%mid_from_terms(%')
     is distinct from 'public.price_path,world.market,world.mid_price,world.quote_priced'
     or to_regprocedure('world.mid_from_terms(numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, integer, numeric, numeric, numeric, numeric)') is not null then
    raise exception '0194 self-assert FAIL: a caller of the old expression remains, or the old form stands';
  end if;

  -- (a) every glut is 0, so new = old exactly on a sample (old tree and new in one statement each)
  if exists (select 1 from public.port_goods where glut <> 0) then
    raise exception '0194 self-assert FAIL: a market row starts with a glut';
  end if;
  create temp table sample_0194 on commit drop as
    select pg.port_id, pg.good_id from public.port_goods pg
     order by md5(pg.port_id::text || pg.good_id::text || '0194') limit 120;
  select count(*) into v_bad from sample_0194 s join public.port_goods pg using (port_id, good_id)
   where world.mid_price(s.port_id, s.good_id, pg.stock) is distinct from pg_temp.mid_price_old_0194(s.port_id, s.good_id, pg.stock);
  if v_bad <> 0 then
    raise exception '0194 self-assert FAIL: % sampled mid prices moved with every glut at 0', v_bad;
  end if;
  select count(*) into v_bad from sample_0194 s
   cross join (values ('buy', 10::numeric), ('buy', 200), ('sell', 10), ('sell', 200)) q(side, qty)
   cross join lateral (select world.quote_priced(s.port_id, s.good_id, q.qty, q.side, null, null, null, null, null, null) as n,
                              pg_temp.quote_priced_old_0194(s.port_id, s.good_id, q.qty, q.side, null, null, null, null, null, null) as o) x
   where x.n::text is distinct from x.o::text;
  if v_bad <> 0 then
    raise exception '0194 self-assert FAIL: % sampled quotes moved with every glut at 0', v_bad;
  end if;
  select count(*) into v_bad from (select * from sample_0194 limit 12) s
   cross join lateral (select array_agg(row(p.k, p.mid, p.lo, p.hi)::text order by p.k) a from public.price_path(s.port_id, s.good_id, 24) p) n
   cross join lateral (select array_agg(row(p.k, p.mid, p.lo, p.hi)::text order by p.k) a from pg_temp.price_path_old_0194(s.port_id, s.good_id, 24) p) o
   where n.a is distinct from o.a;
  if v_bad <> 0 then
    raise exception '0194 self-assert FAIL: % sampled price paths moved with every glut at 0', v_bad;
  end if;

  -- (b) a planted glut 0.2 on one probe row (rolled back)
  select pg.port_id, pg.good_id, pg.stock_target into v_port, v_good, v_tgt
    from public.port_goods pg join public.ports p on p.id = pg.port_id join public.goods g on g.id = pg.good_id
   where p.code = 'LIS' and pg.stock > 50 and not public.culture_refuses(p.culture, g.culture_mask)
     and exists (select 1 from public.port_offered_goods(pg.port_id) o where o.good_id = pg.good_id)   -- LIS sells it: the probe can buy
     and pg_temp.mid_price_old_0194(pg.port_id, pg.good_id, pg.stock) between 1 and 300
   order by g.code limit 1;
  if v_good is null then
    raise exception '0194 self-assert FAIL: no Lisbon row to probe';
  end if;
  begin
    update public.port_goods set glut = 0.2, last_regen_day = world.game_day() where port_id = v_port and good_id = v_good;
    select count(*) into v_bad from public.port_goods pg
     where pg.port_id = v_port and pg.good_id = v_good
       and abs(world.mid_price(pg.port_id, pg.good_id, pg.stock) - pg_temp.mid_price_old_0194(pg.port_id, pg.good_id, pg.stock) * 0.8) > 0.0002;
    if v_bad <> 0 then
      raise exception '0194 self-assert FAIL: a 0.2 glut is not × 0.8 on the mid';
    end if;
    -- the quote's mid parts (before the units' rounding) are × 0.8
    if abs((select q.mid_total from world.quote_priced(v_port, v_good, 10, 'sell', null, null, null, null, null, null) q)
           - (select q.mid_total from pg_temp.quote_priced_old_0194(v_port, v_good, 10, 'sell', null, null, null, null, null, null) q) * 0.8) > 0.05 then
      raise exception '0194 self-assert FAIL: a 0.2 glut is not × 0.8 in the quote: % vs %',
        (select q.mid_total from world.quote_priced(v_port, v_good, 10, 'sell', null, null, null, null, null, null) q),
        (select q.mid_total from pg_temp.quote_priced_old_0194(v_port, v_good, 10, 'sell', null, null, null, null, null, null) q);
    end if;
    -- the path: × 0.8 until a game day passes, × 0.9 after (the glut halved, as the tick halves it)
    select count(*) into v_bad
      from public.price_path(v_port, v_good, 96) n
      join pg_temp.price_path_old_0194(v_port, v_good, 96) o using (k)
     where abs(n.mid - o.mid * case when world.game_day(n.at) = world.game_day() then 0.8
                                    else 1 - round(0.2 * power(0.5, world.game_day(n.at) - world.game_day()), 4) end)
           > 0.0002 + o.mid * 0.0002;   -- the path rounds the glut at each day it crosses, as the tick does: within 0.0002 of the closed form
    select count(*) into v_n from public.price_path(v_port, v_good, 96) n where world.game_day(n.at) > world.game_day();
    if v_bad <> 0 or v_n = 0 then
      raise exception '0194 self-assert FAIL: the path does not carry and fade the glut (% bad steps, % steps past the day)', v_bad, v_n;
    end if;
    -- the market's range, and the read
    select x into v_m from jsonb_array_elements(world.market(v_port)->'goods') x where x->>'good_id' = v_good::text limit 1;
    select count(*) into v_bad
      from public.port_goods pg join public.goods g on g.id = pg.good_id join public.ports pr on pr.id = pg.port_id
     where pg.port_id = v_port and pg.good_id = v_good
       and (abs((v_m->>'range_lo')::numeric - 0.8 * pg_temp.mft_old_0194(g.base_value, pg.affinity, pg.demand, pg.haul, pg.stock_target, pg.stock,
                  -public.wc_num('drift_clamp'), pg.season_mod, pr.dev_commerce, public.wc_num('price_elasticity'), public.wc_num('mid_dev_discount'),
                  public.wc_num('price_band_lo'), public.wc_num('price_band_hi'))) > 0.0002
         or abs((v_m->>'range_hi')::numeric - 0.8 * pg_temp.mft_old_0194(g.base_value, pg.affinity, pg.demand, pg.haul, pg.stock_target, pg.stock,
                  public.wc_num('drift_clamp'), pg.season_mod, pr.dev_commerce, public.wc_num('price_elasticity'), public.wc_num('mid_dev_discount'),
                  public.wc_num('price_band_lo'), public.wc_num('price_band_hi'))) > 0.0002);
    if v_m is null or v_bad <> 0 then
      raise exception '0194 self-assert FAIL: world.market''s range does not carry the glut: %', v_m;
    end if;
    j := world.price_why(v_port, v_good);
    select (j->>'base')::numeric * exp(sum(ln((x->>'mult')::numeric))) into v_prod from jsonb_array_elements(j->'terms') x;
    if (select (x->>'mult')::numeric from jsonb_array_elements(j->'terms') x where x->>'key' = 'glut') is distinct from 0.8
       or abs(v_prod - (j->>'mid')::numeric) > greatest(0.0005 * (j->>'mid')::numeric, 0.0002) then
      raise exception '0194 self-assert FAIL: price_why does not carry the glut, or its terms do not multiply to the mid: %', j;
    end if;
    raise exception using errcode = 'ZX190';
  exception when sqlstate 'ZX190' then
    null;
  end;
  if exists (select 1 from public.port_goods where port_id = v_port and good_id = v_good and glut <> 0) then
    raise exception '0194 self-assert FAIL: the planted glut survived its rollback';
  end if;

  -- (c) + (d) a probe company sells 10 at Lisbon; then the tick fades the mark (rolled back)
  begin
    v_p := public.new_house(c_uid, 'Casa da Fartura 0194', 'PRT', 'LIS');
    select id into v_f from public.fleets where player_id = v_p order by id limit 1;
    select g.code into v_code from public.goods g where g.id = v_good;
    perform public.fleet_load(v_f, v_code, 40, 1);
    select glut into v_g0 from public.port_goods where port_id = v_port and good_id = v_good;
    v_r := cmd.do_sell(v_f, jsonb_build_object('good', v_good, 'qty', 10));
    select glut into v_g1 from public.port_goods where port_id = v_port and good_id = v_good;
    if v_g1 <> round(least(0.30, v_g0 + 0.30 * (v_r->>'qty')::numeric / greatest(v_tgt, 1)), 4) or v_g1 <= v_g0 then
      raise exception '0194 self-assert FAIL: a sale of % left glut % (was %, target %)', v_r->>'qty', v_g1, v_g0, v_tgt;
    end if;
    -- a BUY leaves it alone
    v_r := cmd.do_buy(v_f, jsonb_build_object('good', v_good, 'qty', 5));
    if (select glut from public.port_goods where port_id = v_port and good_id = v_good) <> v_g1 then
      raise exception '0194 self-assert FAIL: a buy moved the glut';
    end if;
    -- the tick fades it: a day back, then one tick of the harbour
    update public.port_goods set glut = 0.2, last_regen_day = world.game_day() - 1 where port_id = v_port and good_id = v_good;
    perform public.tick_market_drift(now(), v_port);
    if (select glut from public.port_goods where port_id = v_port and good_id = v_good) <> 0.1 then
      raise exception '0194 self-assert FAIL: a day''s tick left glut %, not 0.1', (select glut from public.port_goods where port_id = v_port and good_id = v_good);
    end if;
    v_ok := format('sold 10 at LIS (target %s): glut %s → %s', v_tgt, v_g0, v_g1);
    raise exception using errcode = 'ZX195', message = v_ok;
  exception when sqlstate 'ZX195' then
    v_ok := sqlerrm;
  end;
  if exists (select 1 from public.players where id = v_p) then
    raise exception '0194 self-assert FAIL: the probe company survived its rollback';
  end if;

  -- timing (notice only): world.quote_priced on the sample
  v_t0 := clock_timestamp();
  perform world.quote_priced(s.port_id, s.good_id, 50, 'sell', null, null, null, null, null, null) from sample_0194 s;
  v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000 / 120, 3);

  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0
     or exists (select 1 from unnest(array['world.mid_terms(uuid, uuid)',
                 'world.mid_from_terms(numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, integer, numeric, numeric, numeric, numeric)']) f(fn),
                 unnest(array['anon', 'authenticated']) rl(role) where has_function_privilege(rl.role, f.fn, 'execute')) then
    raise exception '0194 self-assert FAIL: a wall moved, or a client can reach the expression';
  end if;
  raise notice '0194 self-assert ok: A GLUTTED MARKET REMEMBERS. port_goods.glut (0 on every row); world.mid_from_terms × (1 − glut) after the band and the haul (14 arguments; the 13-argument form dropped); world.mid_terms + m_glut; re-cut: mid_price, quote_priced, price_path (+ the fade), market, do_sell (the mark), tick_market_drift (the fade), price_why (its term) — 9 bodies reverse to their pre-images, ACL unmoved. With every glut 0: 120 sampled mids, 480 quotes and 12 paths equal the pre-image exactly. A planted 0.2: mid × 0.8, quote × 0.8, path × 0.8 then × 0.9 past the day, price_why carries it. Probe: %; a buy left it; a day''s tick halved 0.2 to 0.1. world.quote_priced % ms a call (sample).',
    v_ok, v_ms;
end $$;
