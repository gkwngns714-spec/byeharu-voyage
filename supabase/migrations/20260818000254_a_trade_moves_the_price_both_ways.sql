-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0254 — A TRADE MOVES THE PRICE BOTH WAYS   (slice E6 of docs/CLOSED_ECONOMY.md §4: prices like stocks)
--        DARK: this file changes no price. Lit later by the OWNER only:
--        `update public.world_config set value = 'true' where key = 'price_impact'`.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER (2026-10-26) ──────────────────────────────────────────────────────────────────────
--   "i want prices to be moved like stocks"
--
-- ── WHAT THIS FILE DOES (§4) ────────────────────────────────────────────────────────────────────
--   THE PRESS is today's port_goods.glut, made SIGNED: > 0 price down (sold into), < 0 price up (bought out). Same
--   column, same term of world.mid_from_terms (× (1 − glut)): no second price path.
--   CONSTRAINT port_goods_glut_check [0, 0.5] → [−0.5, 0.5] (widened only; every live row stays valid). The lit press
--            is clamped at ±glut_max (0.30 on prod).
--   KNOB     price_impact false (THE dark switch of this slice).
--   NEW, server-only:
--     public.price_impact_lit()   price_impact AND economy_closed().                         (THE one gate)
--     public.press_after(glut, units, target, side, per, max)   THE one rule of the press after `units` traded:
--                                 glut ∓ per × units / target (buy −, sell +), clamped ±max, 4 places. Immutable SQL.
--   HUNKS (re-cut against the LIVE bodies, prod head 0248):
--     world.quote_priced (3)     lit: each 10-tun shelf is priced at the press of the walk — a buy's shelf at the press
--                                AFTER it, a sale's shelf at the press BEFORE it (the press's "top of the shelf", as 0211
--                                does for the stock) — so a buy of N and the sale of those N price every shelf at the
--                                same mid and only the spread separates them: 0211's "a round trip never pays" holds.
--                                The two knobs are read once a quote, only when lit.
--     cmd.do_buy (1)             lit: the buy writes the press the walk ended on (negative: price up).
--     cmd.do_sell (1)            lit: the sale's mark through the same rule (floored at −glut_max; else as 0194).
--   Decay: unchanged (tick_market_drift's glut × (1 − glut_decay)^days, 48-min half-life) — it fades a negative press
--   toward 0 the same way. Every quoter (players, merchants' planners, the boards) reads the walk: one authority.
--
-- ── DARK (what the main session sees after deploy) ──────────────────────────────────────────────
--   price_impact false: quote_priced walks at the row's glut as before; do_buy writes glut = glut; do_sell's mark is
--   0194's expression verbatim. Quotes, trades, answers byte-identical (asserted).
--
-- ── DECIDED BY DEFAULT (stated; the owner may reverse) ──────────────────────────────────────────
--   * Own flag `price_impact`, not lit by deploy even though the economy is closed (the same reason as 0245).
--   * The press's cap is the existing glut_max (0.30) both ways; its step is the existing glut_per_depth (0.30).
--   * §4's "Noise" line (drift slot 900 → 600 s, θ 0.932, σ 0.0166) is NOT in this file. It is three live knobs, and
--     drift_slot_seconds is stored in slot units on every row (0240's dev-log: going 900 → 600 → 900 would freeze the
--     drift for months). Changing it is a separate owner decision with its own care.
--   * The column CHECK is widened to ±0.5 (not narrowed to ±0.30) so no live row can fail it; the clamp is the rule.
--
-- ── WHAT IT SELF-ASSERTS (probe rows only; every probe a rolled-back sub-transaction, asserted) ───
--   (a) hunks reverse; ACL / volatility / definer / config unmoved; new functions server-only; registry; walls 0.
--   (b) DARK, BYTE FOR BYTE: 18 quotes at Lisbon (3 goods × buy/sell × 1, 30, 119 t) and a probe company's buy 30 then
--       sell 30 at Lisbon (answers, purse, the row's stock and glut) — BEFORE and AFTER the re-cut, same state.
--   (c) LIT: a 119-t buy at depth 1,330 (stock = max) moves the mid +7–8 %; the press is negative after it and back to 0
--       after the sale of the same 119; the sale ≤ the buy (round trip never pays); a lit sale walks the price down
--       (its average < the dark sale's); the clamp ±0.30; the probe company's real buy and sale write the rule's press.
--   (d) after: knob false, the probe company gone.
-- ROLLBACK (forward): restore the OLD hunks below verbatim; drop the two functions and the knob; the CHECK back to
-- [0, 0.5] only after every negative glut has decayed (it fades by half a game-day).
-- VERSION: 0254 (renumbered from 0253 on 10-28: the reconcile follow-up #364 took 0253; hunks re-checked on the live bodies at head 0253).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '10min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('public.economy_closed()') is null then
    raise exception '0254 refuses: E1 (0228) is not in this world';
  end if;
  if to_regprocedure('public.press_after(numeric,numeric,numeric,text,numeric,numeric)') is not null then
    raise exception '0254 refuses: press_after already exists';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0254(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 0. THE PRE-IMAGES (LF-normalised) ───────────────────────────────────────────────────────────
create temp table defs_before_0254 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('world.quote_priced(uuid,uuid,numeric,text,numeric,uuid,numeric,numeric,numeric,numeric)'),
               ('cmd.do_buy(uuid,jsonb)'),
               ('cmd.do_sell(uuid,jsonb)')) f(fn);

create temp table before_0254 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR') as lis;

-- three goods Lisbon sells (light, in stock), the first the trade probe's
create temp table goods_0254 on commit drop as
select g.id, g.code, row_number() over (order by g.code) as n
  from public.goods g
  join public.port_goods pg on pg.good_id = g.id
  join public.ports p on p.id = pg.port_id
 where p.code = 'LIS' and p.kind = 'HARBOUR' and g.bulk <= 1 and pg.stock >= 200
   and public.port_offers(p.id, g.id) and not public.culture_refuses(p.culture, g.culture_mask)
 order by g.code limit 3;

do $$
begin
  if (select b.lis from before_0254 b) is null or (select count(*) from goods_0254) <> 3 then
    raise exception '0254 self-assert FAIL: no Lisbon, or not three goods it sells in stock';
  end if;
  -- Lisbon's rows are held still for this transaction, so the two dark runs price one market
  perform 1 from public.port_goods pg, before_0254 b where pg.port_id = b.lis for update;
end $$;

-- ── 1. THE DARK PROBE: 18 quotes, then a company's buy 30 and sell 30 at Lisbon; rolled back ──────
create or replace function pg_temp.trader_0254()
returns jsonb
language plpgsql
as $$
declare
  v_p uuid;
  v_f uuid;
begin
  v_p := public.new_house(null, 'Casa da Balança 0254', 'PRT', 'LIS');
  select f.id into v_f from public.fleets f where f.player_id = v_p;
  perform public.credit(v_p, 'PROBE_0254', 1000000);
  return jsonb_build_object('p', v_p, 'f', v_f);
end $$;

create or replace function pg_temp.dark_0254()
returns jsonb
language plpgsql
as $$
declare
  v_lis  uuid := (select b.lis from before_0254 b);
  v_good uuid := (select g.id from goods_0254 g where g.n = 1);
  v_q    jsonb;
  v      jsonb;
  v_f    uuid;
  v_buy  jsonb;
  v_sell jsonb;
begin
  begin
    select jsonb_agg(jsonb_build_array(g.code, s.side, n.qty, q.units, q.total, q.avg_price, q.end_stock, q.mid_total,
                                       q.tax_total, q.spread_total, q.haggle_saved) order by g.code, s.side, n.qty)
      into v_q
      from goods_0254 g
     cross join (values ('buy'), ('sell')) s(side)
     cross join (values (1), (30), (119)) n(qty)
     cross join lateral world.quote(v_lis, g.id, n.qty, s.side) q;
    v := pg_temp.trader_0254();
    v_f := (v->>'f')::uuid;
    v_buy  := cmd.do_buy(v_f, jsonb_build_object('good', v_good, 'qty', 30));
    v_sell := cmd.do_sell(v_f, jsonb_build_object('good', v_good, 'qty', 30));
    raise exception using errcode = 'ZY254', message = jsonb_build_object(
      'quotes', v_q, 'buy', v_buy, 'sell', v_sell,
      'purse', (select pl.ducats from public.players pl where pl.id = (v->>'p')::uuid),
      'row', (select jsonb_build_array(pg.stock, pg.glut) from public.port_goods pg where pg.port_id = v_lis and pg.good_id = v_good))::text;
  exception when sqlstate 'ZY254' then
    return sqlerrm::jsonb;
  end;
end $$;

create temp table dark_old_0254 on commit drop as select pg_temp.dark_0254() as seen;

-- ── 2. THE CONSTRAINT AND THE KNOB ──────────────────────────────────────────────────────────────
alter table public.port_goods drop constraint port_goods_glut_check;
alter table public.port_goods add constraint port_goods_glut_check check (glut >= -0.5 and glut <= 0.5) not valid;
alter table public.port_goods validate constraint port_goods_glut_check;

insert into public.world_config (key, value, description) values
  ('price_impact', 'false'::jsonb,
   '0254 (docs/CLOSED_ECONOMY.md §4, E6): false = trades leave today''s mark (a sale raises glut after it), byte for byte. true (with economy_closed) = every trade moves the price inside its own walk, buy up and sell down, through the signed press (port_goods.glut). Read only through public.price_impact_lit(). OWNER ONLY.');

-- ── 3. THE TWO FUNCTIONS ────────────────────────────────────────────────────────────────────────
create function public.price_impact_lit()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0254: THE ONE gate of this slice: its own knob AND the closed economy.
  select coalesce((public.wc('price_impact'))::boolean, false) and public.economy_closed()
$$;

create function public.press_after(p_glut numeric, p_units numeric, p_target numeric, p_side text,
                                   p_per numeric, p_max numeric)
returns numeric
language sql
immutable
parallel safe
as $$
  -- 0254 (§4): THE ONE rule of the press after p_units traded at a row of max stock p_target: a buy pushes it down
  -- (price up), a sale up (price down), by p_per × units / max, clamped to ±p_max, at the column's scale.
  select round(greatest(-p_max, least(p_max,
           p_glut + case when p_side = 'buy' then -1 else 1 end * p_per * p_units / greatest(p_target, 1))), 4)
$$;

comment on function public.price_impact_lit() is '0254: price_impact AND economy_closed(). Server-only.';
comment on function public.press_after(numeric, numeric, numeric, text, numeric, numeric) is
  '0254 (§4): the one rule of the signed press after a trade. Read by world.quote_priced (per shelf), cmd.do_buy, cmd.do_sell.';
revoke all on function public.price_impact_lit() from public, anon, authenticated;
revoke all on function public.press_after(numeric, numeric, numeric, text, numeric, numeric) from public, anon, authenticated;

-- ── 4. THE RE-CUTS (hunks sliced from the live bodies; each occurs once; each body reverses) ──────
create temp table hunks_0254 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0254 (fn, n, old, new) values
('world.quote_priced(uuid,uuid,numeric,text,numeric,uuid,numeric,numeric,numeric,numeric)', 1,
$h$  k        record;    -- 0169: the four terms (world.quote_terms), when none were handed over
begin
$h$,
$h$  k        record;    -- 0169: the four terms (world.quote_terms), when none were handed over
  v_imp    boolean := public.price_impact_lit();   -- 0254 (E6): the trade moves the price inside its own walk (dark: false)
  v_per    numeric;   -- 0254: glut_per_depth, read once a quote when lit
  v_gmax   numeric;   -- 0254: glut_max, read once a quote when lit
begin
$h$),
('world.quote_priced(uuid,uuid,numeric,text,numeric,uuid,numeric,numeric,numeric,numeric)', 2,
$h$  select * into t from world.mid_terms(p_port, p_good);
$h$,
$h$  select * into t from world.mid_terms(p_port, p_good);
  if v_imp then
    v_per  := public.wc_num('glut_per_depth');
    v_gmax := public.wc_num('glut_max');
  end if;
$h$),
('world.quote_priced(uuid,uuid,numeric,text,numeric,uuid,numeric,numeric,numeric,numeric)', 3,
$h$    v_mid := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_haul, t.m_glut, t.m_target, v_top, t.m_drift,$h$,
$h$    -- 0254 (E6), lit: THE PRESS OF THE WALK. A buy's shelf is priced at the press after it, a sale's at the press before
    -- it (public.press_after, the one rule), so a buy of N and the sale of those N see every shelf at one mid.
    v_mid := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_haul,
                                  case when v_imp
                                       then public.press_after(t.m_glut, case when p_side = 'buy' then v_units + v_n else v_units end,
                                                               t.m_target, p_side, v_per, v_gmax)
                                       else t.m_glut end, t.m_target, v_top, t.m_drift,$h$),
('cmd.do_buy(uuid,jsonb)', 1,
$h$  update public.port_goods set stock = q.end_stock, updated_at = now()
   where port_id = f.port_id and good_id = g.id;
$h$,
$h$  update public.port_goods set stock = q.end_stock, updated_at = now(),
         glut = case when public.price_impact_lit()   -- 0254 (E6), lit: a buy leaves its mark too (the press falls: price up)
                     then public.press_after(glut, q.units, stock_target, 'buy',
                                             public.wc_num('glut_per_depth'), public.wc_num('glut_max'))
                     else glut end
   where port_id = f.port_id and good_id = g.id;
$h$),
('cmd.do_sell(uuid,jsonb)', 1,
$h$         glut = round(least(public.wc_num('glut_max'),
                            glut + public.wc_num('glut_per_depth') * q.units / greatest(stock_target, 1)), 4)   -- 0194: a sale leaves a mark
$h$,
$h$         glut = case when public.price_impact_lit()   -- 0254 (E6), lit: the same mark through the one rule (floored at −glut_max)
                     then public.press_after(glut, q.units, stock_target, 'sell',
                                             public.wc_num('glut_per_depth'), public.wc_num('glut_max'))
                     else round(least(public.wc_num('glut_max'),
                            glut + public.wc_num('glut_per_depth') * q.units / greatest(stock_target, 1)), 4) end   -- 0194: a sale leaves a mark
$h$);

create or replace function pg_temp.recut_0254(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := (select def from defs_before_0254 where fn = p_fn);
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0254 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0254(v_def, h.old);
    if v_n <> 1 then
      raise exception '0254 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, h.fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0254(fn) from defs_before_0254 order by fn;

-- ── 5. THE SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
do $$
declare
  b      record;
  v_d record; v_h record; v_pp record; v_def text;
  v_old  jsonb;
  v_new  jsonb;
  v_good uuid := (select g.id from goods_0254 g where g.n = 1);
  v_m0   numeric;
  v_m1   numeric;
  v_g    numeric;
  qb     record;
  qs     record;
  qd     record;
  qdl    record;
  v      jsonb;
  v_f    uuid;
  v_buy  jsonb;
  v_sell jsonb;
  v_g0   numeric;
  v_tg   numeric;
begin
  select * into b from before_0254;

  -- (a) THE RE-CUTS reverse; ACL / volatility / definer / config unmoved; new functions server-only
  for v_d in select * from defs_before_0254 loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0254 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0254(v_def, v_h.new) <> 1 then
        raise exception '0254 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0254 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
      into v_pp from pg_proc p where p.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0254 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;
  if exists (select 1 from (values ('public.price_impact_lit()'), ('public.press_after(numeric,numeric,numeric,text,numeric,numeric)')) f(fn)
              where has_function_privilege('authenticated', f.fn, 'execute') or has_function_privilege('anon', f.fn, 'execute')) then
    raise exception '0254 self-assert FAIL: a client role can execute one of the two new functions';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> b.entry_points then
    raise exception '0254 self-assert FAIL: the registry moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0254 self-assert FAIL: a wall moved';
  end if;

  -- (b) DARK, BYTE FOR BYTE
  if public.price_impact_lit() then
    raise exception '0254 self-assert FAIL: price_impact is not dark';
  end if;
  v_old := (select d.seen from dark_old_0254 d);
  v_new := pg_temp.dark_0254();
  if v_old is null or v_new is distinct from v_old or jsonb_array_length(v_new->'quotes') <> 18
     or (v_new->'buy'->>'qty')::numeric <> 30 or (v_new->'sell'->>'qty')::numeric <> 30 then
    raise exception '0254 self-assert FAIL: dark, the quotes or the probe trade are not the pre-image''s: new % old %', v_new, v_old;
  end if;

  -- (c) LIT (a rolled-back sub-transaction)
  begin
    if public.press_after(0, 1000000000, 1330, 'buy', 0.30, 0.30) <> -0.30
       or public.press_after(0, 1000000000, 1330, 'sell', 0.30, 0.30) <> 0.30
       or public.press_after(0.1, 0, 1330, 'buy', 0.30, 0.30) <> 0.1 then
      raise exception '0254 self-assert FAIL: the press is not clamped at ±0.30';
    end if;
    -- §4's example: a median quay, stock = max = 1,330, nothing pressing; the dark sale's quote first
    update public.port_goods set stock = 1330, stock_target = 1330, glut = 0, drift = 0, season_mod = 0, affinity = 1, demand = 1
     where port_id = b.lis and good_id = v_good;
    select * into qdl from world.quote(b.lis, v_good, 119, 'sell');
    select * into qd from world.quote(b.lis, v_good, 119, 'buy');
    update public.world_config set value = 'true'::jsonb where key in ('economy_closed', 'price_impact');
    if not public.price_impact_lit() then
      raise exception '0254 self-assert FAIL: price_impact_lit() is false with both switches on';
    end if;
    v_m0 := world.mid_price(b.lis, v_good, 1330);
    select * into qb from world.quote(b.lis, v_good, 119, 'buy');
    if qb.units <> 119 or qb.total <= qd.total then
      raise exception '0254 self-assert FAIL: lit, the 119-t buy is not dearer than dark (% vs %)', qb.total, qd.total;
    end if;
    v_g := public.press_after(0, 119, 1330, 'buy', public.wc_num('glut_per_depth'), public.wc_num('glut_max'));
    update public.port_goods set stock = qb.end_stock, glut = v_g where port_id = b.lis and good_id = v_good;
    v_m1 := world.mid_price(b.lis, v_good, qb.end_stock);
    if v_g >= 0 or not (v_m1 / v_m0 between 1.07 and 1.08) then
      raise exception '0254 self-assert FAIL: a 119-t buy at depth 1,330 moved the mid by % (want +7-8 %%), press %', v_m1 / v_m0, v_g;
    end if;
    select * into qs from world.quote(b.lis, v_good, 119, 'sell');
    if qs.units <> 119 or qs.total > qb.total then
      raise exception '0254 self-assert FAIL: a round trip paid: bought 119 for %, sold them back for %', qb.total, qs.total;
    end if;
    if abs(public.press_after(v_g, 119, 1330, 'sell', public.wc_num('glut_per_depth'), public.wc_num('glut_max'))) > 0.0001 then
      raise exception '0254 self-assert FAIL: the sale of the same 119 does not bring the press back to 0';
    end if;
    -- a lit sale walks the price down: from the fresh row, its average is under the dark sale's
    update public.port_goods set stock = 1330, glut = 0 where port_id = b.lis and good_id = v_good;
    select * into qs from world.quote(b.lis, v_good, 119, 'sell');
    if qs.units <> 119 or not (qs.avg_price < qdl.avg_price) then
      raise exception '0254 self-assert FAIL: lit, a sale did not walk the price down (% vs dark %)', qs.avg_price, qdl.avg_price;
    end if;
    -- the probe company's real buy and sale write the rule's press
    select pg.glut, pg.stock_target into v_g0, v_tg from public.port_goods pg where pg.port_id = b.lis and pg.good_id = v_good;
    v := pg_temp.trader_0254();
    v_f := (v->>'f')::uuid;
    v_buy := cmd.do_buy(v_f, jsonb_build_object('good', v_good, 'qty', 30));
    v_g := public.press_after(v_g0, 30, v_tg, 'buy', public.wc_num('glut_per_depth'), public.wc_num('glut_max'));
    if (select pg.glut from public.port_goods pg where pg.port_id = b.lis and pg.good_id = v_good) <> v_g or v_g >= 0 then
      raise exception '0254 self-assert FAIL: the buy did not write the press % (row %)', v_g,
        (select pg.glut from public.port_goods pg where pg.port_id = b.lis and pg.good_id = v_good);
    end if;
    v_sell := cmd.do_sell(v_f, jsonb_build_object('good', v_good, 'qty', 30));
    v_g := public.press_after(v_g, 30, v_tg, 'sell', public.wc_num('glut_per_depth'), public.wc_num('glut_max'));
    if (select pg.glut from public.port_goods pg where pg.port_id = b.lis and pg.good_id = v_good) <> v_g
       or (v_sell->>'total')::bigint > (v_buy->>'total')::bigint then
      raise exception '0254 self-assert FAIL: the sale did not write the press, or the round trip paid (buy %, sell %)',
        v_buy->>'total', v_sell->>'total';
    end if;
    raise exception using errcode = 'ZY254', message = 'lit ok';
  exception when sqlstate 'ZY254' then
    null;
  end;

  -- (d) the probe rolled back
  if public.price_impact_lit() or exists (select 1 from public.players pl where pl.company_name = 'Casa da Balança 0254') then
    raise exception '0254 self-assert FAIL: the lit probe left something behind';
  end if;

  raise notice '0254 self-assert ok: A TRADE MOVES THE PRICE BOTH WAYS (dark). quote_priced (3 hunks), do_buy (1), do_sell (1) re-cut, each reversed, ACL unmoved; glut CHECK widened to ±0.5; two server-only functions; registry unchanged; walls 0. DARK: 18 Lisbon quotes and a probe buy 30 / sell 30 (answers, purse, row) equal the pre-image''s. LIT (rolled back): a 119-t buy at depth 1,330 moves the mid x%; the press goes negative and the sale of the same 119 brings it back to 0, paying no more than the buy; a lit sale walks down; the clamp is ±0.30; the probe''s real buy and sale write the rule''s press.',
    round(v_m1 / v_m0, 4);
end $$;
