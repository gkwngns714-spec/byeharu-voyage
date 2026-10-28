-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0263 — NO GOOD IS LOST, AND A SHORT CITY PAYS THE PLAIN PRICE   (two fixes to E5b 0252 and E6b 0255, before the
--        owner's switch-on; docs/CLOSED_ECONOMY.md §3 and §4b)
--        DARK: this file changes no flag, no price, no stock. `depth_by_investment` and `city_wants` stay false.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER (2026-10-28) ──────────────────────────────────────────────────────────────────────
--   E5b, E6 and E6b are to be switched on once the bugs are fixed. Two places where the build breaks the design:
--
-- ── FIX 1, E5b (§3: "goods are never created or destroyed by the re-set") ───────────────────────
--   Was (0252): when a harbour's max stock falls below its stock, the day's regen (public.stock_after's
--   `least(target, …)`) trims the stock DOWN to the max: goods destroyed.
--   Now: under a max-stock multiple, a stock at or above the day's max STAYS; only the refill stops, until sales bring
--   it under the max. Below the max the regen is stock_after's, unchanged.
--   NEW public.depth_stock(stock, max, mult, rate, production, days)   THE one rule of a row's stock at the regen:
--     mult null (dark, every harbour today) → stock_after(...) verbatim; mult set and stock ≥ max → stock; else
--     stock_after(...). Immutable SQL (inlined).
--   HUNK public.tick_market_drift (1): the regen's `stock_after(` becomes `depth_stock(`, with f.depth passed.
--
-- ── FIX 2, E6b (§4b: "a city that can't pay shrinks the premium first, then refuses") ───────────
--   Was (0255): a city short of money shrank the whole lot, still priced at its ×2 want.
--   Now: a short city first drops the ×2 premium — the sale is re-priced at the normal price, the whole lot — and only
--   if it still cannot pay that does the lot shrink (at the normal price), then refuse. A sale it CAN pay at ×2 is
--   unchanged. Units sold at the normal price do not count against the want's cap.
--   HOW: one transaction-local switch, `byeharu.want_off`, read by THE one reader of wants (world.want_left): while it
--   is 'on' there is no want, so the quote walk prices at the normal price and the tally takes nothing. cmd.do_sell
--   sets it only on the short path when the good is wanted, and clears it after the tally (a refusal raises, which
--   rolls the setting back with the sale).
--   HUNKS world.want_left (1): `and current_setting('byeharu.want_off', true) is distinct from 'on'`.
--         cmd.do_sell (2): (1) inside the short-purse test, drop the premium and re-quote first; (2) after the tally,
--         clear the switch.
--
-- ── DECIDED BY DEFAULT (stated; the owner may reverse) ──────────────────────────────────────────
--   * Fix 1 holds for EVERY stock above a harbour's max once it has a multiple (a lowered max, or goods sold in above
--     it): under the multiple nothing is ever trimmed. Harbours with no multiple (all of them, dark) keep 0010's rule.
--   * Fix 2 drops the WHOLE premium (the normal price for every unit), as the owner's brief says, not part of it.
--   * A limit order whose limit sits between the normal and the want price: dropped to the normal price, nothing is
--     above the limit, so the sale is refused E_CITY_BROKE (the city cannot pay the price that was asked).
--   * The outlook (price_path) still steps stock_after (it already keeps today's max; it does not predict trades).
--
-- ── WHAT IT SELF-ASSERTS (probe rows only; every probe a rolled-back sub-transaction, asserted) ───
--   (a) hunks reverse; ACL / volatility / definer / config unmoved; depth_stock server-only; registry; walls 0.
--   (b) FLAGS OFF, BYTE FOR BYTE, BEFORE and AFTER the re-cut from the same state (rows locked): Funchal regenerated 30
--       days on (stock, max, base, glut, day); 18 Lisbon quotes; world.market(Lisbon); a probe company's buy 30, sell 30
--       and a sale of 30 into a Lisbon purse planted short (shrunk or refused); want_left empty; the switch unset.
--   (c) FLAGS ON (rolled back): FIX 1 — Funchal at a planted 0.9: max = round(base × 0.9, 2), every row above it keeps
--       its stock to the hundredth, a row below it is walked by stock_after; a sale brings one under, the next day it
--       refills (stock_after again). FIX 2 — Lisbon draws its wants; a purse between the normal and the ×2 total buys
--       the WHOLE lot at the normal total, no tally; a purse under the normal total shrinks the lot exactly as the
--       normal-price loop would, no tally; then a rich purse pays ×2 again and the tally takes it (the switch is clear).
--   (d) after: nothing left behind; the three flags false.
-- ROLLBACK (forward): restore the OLD hunks below verbatim; drop public.depth_stock.
-- VERSION: 0263 (prod head 0259 when cut; 0260 (compactor) and 0261-0262 (arrivals) queued by other agents; none touches these bodies, re-checked on prod before deploy).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '10min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('public.depth_target(numeric,numeric,numeric)') is null or to_regprocedure('world.want_left(uuid,uuid)') is null then
    raise exception '0263 refuses: E5b (0252) or E6b (0255) is not in this world';
  end if;
  if to_regprocedure('public.depth_stock(numeric,numeric,numeric,numeric,numeric,numeric)') is not null then
    raise exception '0263 refuses: depth_stock already exists';
  end if;
  if coalesce((public.wc('depth_by_investment'))::boolean, false) or coalesce((public.wc('city_wants'))::boolean, false)
     or coalesce((public.wc('price_impact'))::boolean, false) then
    raise exception '0263 refuses: a flag is already on; this file was cut and proven against all three off';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0263(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 0. THE PRE-IMAGES (LF-normalised) ───────────────────────────────────────────────────────────
create temp table defs_before_0263 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('public.tick_market_drift(timestamp with time zone,uuid)'),
               ('world.want_left(uuid,uuid)'),
               ('cmd.do_sell(uuid,jsonb)')) f(fn);

create temp table before_0263 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select p.id from public.ports p where p.code = 'FNC' and p.kind = 'HARBOUR') as fnc,
       (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR') as lis;

create temp table goods_0263 on commit drop as
select g.id, g.code, row_number() over (order by g.code) as n
  from public.goods g
  join public.port_goods pg on pg.good_id = g.id
  join public.ports p on p.id = pg.port_id
 where p.code = 'LIS' and p.kind = 'HARBOUR' and g.bulk <= 1 and pg.stock >= 200
   and public.port_offers(p.id, g.id) and not public.culture_refuses(p.culture, g.culture_mask)
 order by g.code limit 3;

do $$
begin
  if exists (select 1 from before_0263 b where b.fnc is null or b.lis is null) or (select count(*) from goods_0263) <> 3 then
    raise exception '0263 self-assert FAIL: no Funchal or Lisbon, or not three goods Lisbon sells in stock';
  end if;
  perform 1 from public.port_goods pg, before_0263 b where pg.port_id in (b.fnc, b.lis) for update;   -- one state for both dark runs
  perform 1 from public.port_treasury t, before_0263 b where t.port_id in (b.fnc, b.lis) for update;
end $$;

-- ── 1. THE PROBES ───────────────────────────────────────────────────────────────────────────────
create or replace function pg_temp.trader_0263()
returns jsonb
language plpgsql
as $$
declare
  v_p uuid;
  v_f uuid;
begin
  -- founded with the economy open (its capital may be empty in a fresh world); the caller sets the economy after
  update public.world_config set value = 'false'::jsonb where key = 'economy_closed';
  v_p := public.new_house(null, 'Casa do Preco 0263', 'PRT', 'LIS');
  select f.id into v_f from public.fleets f where f.player_id = v_p;
  perform public.credit(v_p, 'PROBE_0263', 1000000);
  return jsonb_build_object('p', v_p, 'f', v_f);
end $$;

-- the city's purse, planted to exactly p_bal ducats over a zero reserve (a probe flow; rolled back with the probe)
create or replace function pg_temp.purse_0263(p_port uuid, p_bal bigint)
returns void
language plpgsql
as $$
begin
  update public.port_treasury set reserve = 0 where port_id = p_port;
  perform public.treasury_post(p_port, 'PROBE_0263', p_bal - public.treasury_balance(p_port), null, null, true);
  if public.treasury_balance(p_port) <> p_bal then
    raise exception '0263 self-assert FAIL: could not plant the purse at % (it is %)', p_bal, public.treasury_balance(p_port);
  end if;
end $$;

-- a sale's answer, or its refusal's text (a refusal is an answer too)
create or replace function pg_temp.sell_0263(p_fleet uuid, p_good uuid, p_qty numeric)
returns jsonb
language plpgsql
as $$
begin
  return cmd.do_sell(p_fleet, jsonb_build_object('good', p_good, 'qty', p_qty));
exception when others then
  return jsonb_build_object('refused', sqlerrm);
end $$;

create or replace function pg_temp.dark_0263()
returns jsonb
language plpgsql
as $$
declare
  v_fnc  uuid := (select b.fnc from before_0263 b);
  v_lis  uuid := (select b.lis from before_0263 b);
  v_good uuid := (select g.id from goods_0263 g where g.n = 1);
  v_reg  jsonb;
  v_q    jsonb;
  v_m    jsonb;
  v      jsonb;
  v_f    uuid;
  v_buy  jsonb;
  v_sell jsonb;
  v_q30  record;
  v_shrt jsonb;
begin
  begin
    -- the purses and the closed economy as prod runs them (the subject flags stay off)
    v := pg_temp.trader_0263();
    v_f := (v->>'f')::uuid;
    update public.world_config set value = 'true'::jsonb where key in ('economy_closed', 'city_treasury_enabled');
    perform public.tick_market_drift(now() + interval '30 days', v_fnc);
    select jsonb_agg(jsonb_build_array(g.code, pg.stock, pg.stock_target, pg.base_target, pg.glut, pg.last_regen_day) order by g.code)
      into v_reg
      from public.port_goods pg join public.goods g on g.id = pg.good_id where pg.port_id = v_fnc;
    select jsonb_agg(jsonb_build_array(g.code, s.side, n.qty, q.units, q.total, q.avg_price, q.end_stock, q.mid_total,
                                       q.tax_total, q.spread_total, q.haggle_saved) order by g.code, s.side, n.qty)
      into v_q
      from goods_0263 g
     cross join (values ('buy'), ('sell')) s(side)
     cross join (values (1), (30), (119)) n(qty)
     cross join lateral world.quote(v_lis, g.id, n.qty, s.side) q;
    v_m := world.market(v_lis);
    v_buy  := cmd.do_buy(v_f, jsonb_build_object('good', v_good, 'qty', 60));
    v_sell := cmd.do_sell(v_f, jsonb_build_object('good', v_good, 'qty', 30));
    -- the short path: a purse half of what 30 more would cost (the lot shrinks)
    select * into v_q30 from world.quote(v_lis, v_good, 30, 'sell', null, v_f);
    perform pg_temp.purse_0263(v_lis, greatest(1, v_q30.total / 2));
    v_shrt := pg_temp.sell_0263(v_f, v_good, 30);
    raise exception using errcode = 'ZY263', message = jsonb_build_object(
      'regen', v_reg, 'quotes', v_q, 'market', v_m, 'buy', v_buy, 'sell', v_sell, 'short', v_shrt,
      'purse', (select pl.ducats from public.players pl where pl.id = (v->>'p')::uuid),
      'city', public.treasury_balance(v_lis),
      'row', (select jsonb_build_array(pg.stock, pg.glut) from public.port_goods pg where pg.port_id = v_lis and pg.good_id = v_good),
      'want', (select count(*) from world.want_left(v_lis, v_good)),
      'switch', coalesce(current_setting('byeharu.want_off', true), ''))::text;
  exception when sqlstate 'ZY263' then
    return sqlerrm::jsonb;
  end;
end $$;

create temp table dark_old_0263 on commit drop as select pg_temp.dark_0263() as seen;

-- ── 2. THE ONE NEW FUNCTION ─────────────────────────────────────────────────────────────────────
create function public.depth_stock(p_stock numeric, p_target numeric, p_mult numeric, p_rate numeric,
                                   p_production numeric, p_days numeric)
returns numeric
language sql
immutable
parallel safe
as $$
  -- 0263 (E5b fix, §3: goods are never created or destroyed by the re-set): THE one rule of a row's stock at the day's
  -- regen. No multiple (dark) → public.stock_after, verbatim. Under a multiple a stock at or above the day's max STAYS
  -- (only the refill stops, until sales bring it under); below it, stock_after.
  select case when p_mult is not null and p_stock >= p_target then p_stock
              else public.stock_after(p_stock, p_target, p_rate, p_production, p_days) end
$$;
comment on function public.depth_stock(numeric, numeric, numeric, numeric, numeric, numeric) is
  '0263 (§3): a row''s stock at the regen; under a max-stock multiple a stock above the max is kept, never trimmed. Server-only.';
revoke all on function public.depth_stock(numeric, numeric, numeric, numeric, numeric, numeric) from public, anon, authenticated;

-- ── 3. THE RE-CUTS (hunks sliced from the live bodies, prod head 0259; each occurs once; each body reverses) ──
create temp table hunks_0263 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0263 (fn, n, old, new) values
('public.tick_market_drift(timestamp with time zone,uuid)', 1,
$h$     set stock = public.stock_after(pg.stock, public.depth_target(pg.stock_target, pg.base_target, f.depth), f.rate,$h$,
$h$     set stock = public.depth_stock(pg.stock, public.depth_target(pg.stock_target, pg.base_target, f.depth), f.depth, f.rate,$h$),
('world.want_left(uuid,uuid)', 1,
$h$   where public.wants_lit()
$h$,
$h$   where public.wants_lit() and current_setting('byeharu.want_off', true) is distinct from 'on'   -- 0263: off for a short city's sale
$h$),
('cmd.do_sell(uuid,jsonb)', 1,
$h$    if round(q.total / v_haul) > v_bal then
      v_need := round(q.total / v_haul);
$h$,
$h$    -- 0263 (E6b fix, §4b): a short city drops its want premium FIRST — the whole lot re-priced at the normal price
    -- (world.want_left reads no want while byeharu.want_off is on; cleared after the tally below) — and only then shrinks.
    if round(q.total / v_haul) > v_bal
       and exists (select 1 from world.want_left(f.port_id, g.id) w where w.left_units > 0) then
      perform set_config('byeharu.want_off', 'on', true);
      select * into q from world.quote(f.port_id, g.id, v_qty, 'sell',
                                       nullif((p_args->>'limit'), '')::numeric, p_fleet);
      if q.units <= 0 then
        perform cmd.refuse('E_CITY_BROKE',
          format('%s cannot pay for cargo today', (select p.name from public.ports p where p.id = f.port_id)),
          cmd.figures(greatest(v_bal, 0), v_need, 'ducats'));
      end if;
    end if;
    if round(q.total / v_haul) > v_bal then
      v_need := round(q.total / v_haul);
$h$),
('cmd.do_sell(uuid,jsonb)', 2,
$h$  on conflict (port_id, good_id, period) do update set units = public.city_want_fills.units + excluded.units;
$h$,
$h$  on conflict (port_id, good_id, period) do update set units = public.city_want_fills.units + excluded.units;
  if current_setting('byeharu.want_off', true) = 'on' then   -- 0263: the premium was dropped for this sale only
    perform set_config('byeharu.want_off', '', true);
  end if;
$h$);

create or replace function pg_temp.recut_0263(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := (select def from defs_before_0263 where fn = p_fn);
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0263 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0263(v_def, h.old);
    if v_n <> 1 then
      raise exception '0263 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, h.fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0263(fn) from defs_before_0263 order by fn;

-- ── 4. THE SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
do $$
declare
  b      record;
  v_d record; v_h record; v_pp record; v_def text;
  v_old  jsonb;
  v_new  jsonb;
  v_bad  int;
  v_rate numeric;
  v_far  timestamptz := now() + interval '30 days';
  v_far2 timestamptz := now() + interval '31 days';
  v_low  uuid;
  v_sold uuid;
  v_pl   record;
  v_per  bigint;
  v_w    record;
  v      jsonb;
  v_f    uuid;
  v_qty  numeric;
  v_dark record;
  v_lit  record;
  v_sale jsonb;
  v_x    bigint;
  v_step numeric := public.wc_num('trade_step_tuns');
  v_fit  numeric;
  v_exp  record;
begin
  select * into b from before_0263;

  -- (a) THE RE-CUTS reverse; ACL / volatility / definer / config unmoved; the new function server-only
  for v_d in select * from defs_before_0263 loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0263 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0263(v_def, v_h.new) <> 1 then
        raise exception '0263 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0263 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
      into v_pp from pg_proc p where p.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0263 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;
  if has_function_privilege('authenticated', 'public.depth_stock(numeric,numeric,numeric,numeric,numeric,numeric)', 'execute')
     or has_function_privilege('anon', 'public.depth_stock(numeric,numeric,numeric,numeric,numeric,numeric)', 'execute') then
    raise exception '0263 self-assert FAIL: a client role can execute depth_stock';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> b.entry_points then
    raise exception '0263 self-assert FAIL: the registry moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0263 self-assert FAIL: a wall moved';
  end if;

  -- (b) FLAGS OFF, BYTE FOR BYTE
  if public.depth_lit() or public.wants_lit() or public.price_impact_lit() then
    raise exception '0263 self-assert FAIL: a flag is on';
  end if;
  v_old := (select d.seen from dark_old_0263 d);
  v_new := pg_temp.dark_0263();
  if v_old is null or v_new is distinct from v_old or jsonb_array_length(v_new->'quotes') <> 18
     or jsonb_array_length(v_new->'regen') < 1 or (v_new->'sell'->>'qty')::numeric <> 30
     or (v_new->>'want')::int <> 0 or v_new->>'switch' <> '' then
    raise exception '0263 self-assert FAIL: flags off, the regen, quotes, market or probe trades are not the pre-image''s: new % old %', v_new, v_old;
  end if;

  -- (c) FLAGS ON (a rolled-back sub-transaction)
  begin
    v := pg_temp.trader_0263();
    v_f := (v->>'f')::uuid;
    update public.world_config set value = 'true'::jsonb
     where key in ('economy_closed', 'city_treasury_enabled', 'depth_by_investment', 'city_wants');
    if not (public.depth_lit() and public.wants_lit()) then
      raise exception '0263 self-assert FAIL: the gates are false with the switches on';
    end if;

    -- FIX 1: Funchal's max falls to 0.9 of its base; every row filled to its old max (now above the new one) keeps its
    -- stock; one row planted at a fifth is walked up by stock_after; nothing is trimmed.
    update public.port_treasury set depth_mult = 0.9 where port_id = b.fnc;
    v_rate := public.restock_rate(b.fnc);
    select pg.good_id into v_low from public.port_goods pg join public.goods g on g.id = pg.good_id
     where pg.port_id = b.fnc order by g.code limit 1;
    update public.port_goods pg
       set stock = case when pg.good_id = v_low then round(pg.stock_target * 0.2, 2) else pg.stock_target end
     where pg.port_id = b.fnc;
    create temp table pre_0263 on commit drop as
      select pg.good_id, pg.stock, pg.stock_target, pg.last_regen_day,
             pg.production_rate * public.works_factor(pg.port_id, 'production', 'production_per_level') as prod
        from public.port_goods pg where pg.port_id = b.fnc;
    if (select count(*) from pre_0263 q where round(q.stock_target * 0.9, 2) < q.stock) < 1 then
      raise exception '0263 self-assert FAIL: no Funchal row stands above its lowered max';
    end if;
    perform public.tick_market_drift(v_far, b.fnc);
    select count(*) into v_bad
      from pre_0263 q join public.port_goods pg on pg.port_id = b.fnc and pg.good_id = q.good_id
     where pg.stock_target is distinct from round(q.stock_target * 0.9, 2)
        or pg.base_target is distinct from q.stock_target
        or pg.last_regen_day <> world.game_day(v_far)
        or (q.stock >= round(q.stock_target * 0.9, 2) and pg.stock is distinct from q.stock)
        or (q.stock < round(q.stock_target * 0.9, 2)
            and pg.stock is distinct from round(public.stock_after(q.stock, round(q.stock_target * 0.9, 2), v_rate, q.prod,
                                                                   world.game_day(v_far) - q.last_regen_day), 2));
    if v_bad <> 0 then
      raise exception '0263 self-assert FAIL: % Funchal row(s) were trimmed, or not walked, under a lowered max', v_bad;
    end if;
    if exists (select 1 from pre_0263 q join public.port_goods pg on pg.port_id = b.fnc and pg.good_id = q.good_id
                where q.good_id = v_low and pg.stock <= q.stock) and v_rate > 0 then
      raise exception '0263 self-assert FAIL: the row under the max was not refilled';
    end if;
    -- a sale brings one row under the max; the next day it refills by stock_after (the refill resumes)
    select q.good_id into v_sold from pre_0263 q where q.good_id <> v_low order by q.good_id limit 1;
    update public.port_goods pg set stock = pg.stock_target - 20 where pg.port_id = b.fnc and pg.good_id = v_sold
    returning pg.stock, pg.stock_target, pg.last_regen_day into v_pl;
    perform public.tick_market_drift(v_far2, b.fnc);
    if (select pg.stock from public.port_goods pg where pg.port_id = b.fnc and pg.good_id = v_sold)
       is distinct from round(public.stock_after(v_pl.stock, v_pl.stock_target, v_rate,
                                                 (select q.prod from pre_0263 q where q.good_id = v_sold),
                                                 world.game_day(v_far2) - v_pl.last_regen_day), 2) then
      raise exception '0263 self-assert FAIL: a row sold under the max did not refill by stock_after';
    end if;

    -- FIX 2: Lisbon's wants; the want with the most room
    v_per := public.want_period(now());
    if public.wants_draw(now()) < 1 then
      raise exception '0263 self-assert FAIL: no want was drawn';
    end if;
    select w.good_id, g.code, w.cap into v_w
      from public.city_wants w join public.goods g on g.id = w.good_id
     where w.period = v_per and w.port_id = b.lis order by w.cap desc, g.code limit 1;
    v_qty := least(10, floor(v_w.cap));
    if v_w.good_id is null or v_qty < 1 then
      raise exception '0263 self-assert FAIL: Lisbon has no want with room (cap %)', v_w.cap;
    end if;
    perform public.fleet_load(v_f, v_w.code, 200, 25);

    -- (i) a purse between the normal and the ×2 total: the WHOLE lot at the normal total, no tally
    perform pg_temp.purse_0263(b.lis, 100000000);
    select * into v_lit from world.quote(b.lis, v_w.good_id, v_qty, 'sell', null, v_f);
    perform set_config('byeharu.want_off', 'on', true);
    select * into v_dark from world.quote(b.lis, v_w.good_id, v_qty, 'sell', null, v_f);
    perform set_config('byeharu.want_off', '', true);
    v_x := (v_lit.total + v_dark.total) / 2;
    perform pg_temp.purse_0263(b.lis, v_x);
    select * into v_lit from world.quote(b.lis, v_w.good_id, v_qty, 'sell', null, v_f);
    perform set_config('byeharu.want_off', 'on', true);
    select * into v_dark from world.quote(b.lis, v_w.good_id, v_qty, 'sell', null, v_f);
    perform set_config('byeharu.want_off', '', true);
    if not (v_dark.total <= v_x and v_x < v_lit.total and v_dark.units = v_qty) then
      raise exception '0263 self-assert FAIL: the planted purse % is not between the normal % and the want % total', v_x, v_dark.total, v_lit.total;
    end if;
    v_sale := pg_temp.sell_0263(v_f, v_w.good_id, v_qty);
    if v_sale ? 'refused' or (v_sale->>'qty')::numeric <> v_qty or (v_sale->>'total')::bigint <> v_dark.total
       or exists (select 1 from public.city_want_fills f where f.port_id = b.lis and f.good_id = v_w.good_id and f.units > 0)
       or current_setting('byeharu.want_off', true) = 'on' then
      raise exception '0263 self-assert FAIL: a short city did not pay the normal price for the whole lot (sale %, normal %, want %)',
        v_sale, v_dark.total, v_lit.total;
    end if;

    -- (ii) a purse under the normal total: the lot shrinks exactly as the normal-price loop would, no tally
    perform set_config('byeharu.want_off', 'on', true);
    select * into v_dark from world.quote(b.lis, v_w.good_id, 30, 'sell', null, v_f);
    v_x := greatest(1, v_dark.total / 2);
    perform set_config('byeharu.want_off', '', true);
    perform pg_temp.purse_0263(b.lis, v_x);
    perform set_config('byeharu.want_off', 'on', true);
    select * into v_dark from world.quote(b.lis, v_w.good_id, 30, 'sell', null, v_f);
    v_fit := floor(greatest(v_x, 0) / nullif(v_dark.avg_price, 0) / v_step) * v_step;
    loop
      exit when coalesce(v_fit, 0) < v_step;
      select * into v_exp from world.quote(b.lis, v_w.good_id, v_fit, 'sell', null, v_f);
      exit when v_exp.total <= v_x;
      v_fit := v_fit - v_step;
    end loop;
    perform set_config('byeharu.want_off', '', true);
    if coalesce(v_fit, 0) < v_step or v_exp.total > v_x then
      raise exception '0263 self-assert FAIL: the probe purse % covers no step at the normal price', v_x;
    end if;
    v_sale := pg_temp.sell_0263(v_f, v_w.good_id, 30);
    if v_sale ? 'refused' or (v_sale->>'qty')::numeric <> v_exp.units or (v_sale->>'total')::bigint <> v_exp.total
       or (v_sale->>'qty')::numeric >= 30
       or exists (select 1 from public.city_want_fills f where f.port_id = b.lis and f.good_id = v_w.good_id and f.units > 0)
       or current_setting('byeharu.want_off', true) = 'on' then
      raise exception '0263 self-assert FAIL: a short city did not shrink at the normal price (sale %, expected % for %)',
        v_sale, v_exp.total, v_exp.units;
    end if;

    -- (iii) a rich purse: ×2 again, and the tally takes it (the switch was cleared inside the transaction)
    perform pg_temp.purse_0263(b.lis, 100000000);
    select * into v_lit from world.quote(b.lis, v_w.good_id, v_qty, 'sell', null, v_f);
    perform set_config('byeharu.want_off', 'on', true);
    select * into v_dark from world.quote(b.lis, v_w.good_id, v_qty, 'sell', null, v_f);
    perform set_config('byeharu.want_off', '', true);
    v_sale := pg_temp.sell_0263(v_f, v_w.good_id, v_qty);
    if v_sale ? 'refused' or (v_sale->>'total')::bigint <> v_lit.total or not (v_lit.total > v_dark.total)
       or (select f.units from public.city_want_fills f where f.port_id = b.lis and f.good_id = v_w.good_id and f.period = v_per) <> v_qty then
      raise exception '0263 self-assert FAIL: a rich city did not pay its want price, or the tally missed it (sale %, want %, normal %)',
        v_sale, v_lit.total, v_dark.total;
    end if;
    raise exception using errcode = 'ZY263', message = 'lit ok';
  exception when sqlstate 'ZY263' then
    null;
  end;

  -- (d) the probe rolled back
  if public.depth_lit() or public.wants_lit() or public.price_impact_lit()
     or exists (select 1 from public.port_treasury t where t.depth_mult is not null)
     or exists (select 1 from public.port_goods pg where pg.base_target is not null)
     or exists (select 1 from public.city_wants) or exists (select 1 from public.city_want_fills)
     or exists (select 1 from public.players pl where pl.company_name = 'Casa do Preco 0263')
     or current_setting('byeharu.want_off', true) = 'on' then
    raise exception '0263 self-assert FAIL: the probe left something behind';
  end if;

  raise notice '0263 self-assert ok: NO GOOD IS LOST, AND A SHORT CITY PAYS THE PLAIN PRICE (flags off). tick_market_drift (1 hunk), want_left (1), do_sell (2) re-cut, each reversed, ACL unmoved; depth_stock server-only; registry unchanged; walls 0. FLAGS OFF: Funchal 30 days on, 18 Lisbon quotes, world.market, a probe buy 60 / sell 30 and a short-purse sale equal the pre-image''s. FLAGS ON (rolled back): under a 0.9 max every stock above it kept, the one below walked, a row sold under refilled; a short city paid the normal price for the whole lot, then shrank at the normal price, no tally; a rich city paid x2 and the tally took it.';
end $$;
