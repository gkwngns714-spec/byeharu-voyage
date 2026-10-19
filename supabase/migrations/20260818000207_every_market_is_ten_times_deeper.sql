-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0207 — EVERY MARKET IS TEN TIMES DEEPER  (every city's goods stock, its normal stock and its
--        production × 10, from ONE knob, market_depth, read by ONE derivation, world.market_depth_at)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- The owner, 2026-10-19, verbatim: "make the trade good quantity 10 times larger for all".
--
-- DECIDED BY DEFAULT (recorded here and in docs/dev-log/2026-10-19-trade-qty-x10.md; the owner may
-- reverse it): every city market's goods STOCK and its NORMAL (target) stock become 10× larger, for
-- every good in every city, and so does the flow that refills them (production_rate). Prices stay
-- where they are today. Ship holds do not change.
--
-- ── WHY ONE UPDATE IS THE WHOLE CHANGE (every reader of a quantity was read, on prod, 2026-10-19) ──
--   A market row stores three quantities: stock, stock_target, production_rate. EVERYTHING that
--   refills, drains, caps or prices a market already reads them, so scaling the three scales all of it:
--   * THE PRICE   world.mid_from_terms: power(stock_target / greatest(stock, 1), price_elasticity).
--                 Stock and target × 10 leaves the ratio, and therefore every mid, ask, bid and the
--                 first step of every quote, unchanged (asserted below on a probe set, and on prod
--                 over all 132,090 rows read-only before this PR). The `greatest(stock, 1)` floor binds
--                 only below one tun — on prod today no market holds fewer than 10 (100 after this).
--   * RECOVERY    public.stock_after (via public.tick_market_drift and public.price_path):
--                 target − (target − stock) × (1 − stock_regen_fraction)^days + production × days.
--                 Homogeneous of degree one in (stock, target, production): × 10 in, × 10 out, so a
--                 market refills at the same pace relative to its size. stock_regen_fraction is a
--                 fraction and stays. (Production is 0 on every prod row today — no affinity is
--                 below 0.80 — so the scaled term is 0 × 10; it is scaled anyway, by the same rule.)
--   * THE DAY CAP world.daily_cap_remaining = daily_cap_fraction × stock_target × skill × works —
--                 × 10 with the target. It is the per-(company, port, good) per-day trade allowance:
--                 the only per-day cap on a trade, and the one NPC merchants' parcels are sized under
--                 (public.npc_leg_lines, cmd.standing_route_lines) as well as the contracts' upper
--                 bound (public.contract_draw).
--   * THE GLUT    cmd.do_sell: glut += glut_per_depth × units / stock_target — relative to depth, so a
--                 sale of the same size leaves a tenth of the mark. That is what a deeper market IS.
--   * PRICE IMPACT world.quote_priced walks the book in trade_step_tuns (10) steps, each repriced at
--                 the moved stock. A 10-unit step is a tenth as large a share of a 10× market, so a
--                 large order slips a tenth as much. Asserted below: no 200-unit buy dearer, most cheaper.
--   NOTHING ELSE SETS OR LIMITS A MARKET QUANTITY. Read and left alone, each for its reason:
--   * trade_step_tuns (10)   the RESOLUTION of the price walk, not a quantity a trade may move (any
--                            count above nought is accepted). Kept: a coarser walk would only price a
--                            large order less finely.
--   * route_probe_tuns (50)  the cargo world.trade_routes assumes when no fleet is named — a HOLD
--                            stand-in (a fleet's load), not a market size. Kept.
--   * contract_qty_steps_min/max (1–3 steps = 10–30)  a city's delivery request, sized to a hold and
--                            already bounded by the day cap (which grows). Kept.
--   * warehouse_tuns_per_tier (150), every hull's capacity — storage and holds. Not a trade cap: no
--                            code found treats a trade cap as a hold cap. Kept, as ordered.
--   * NPC merchants          no constant of their own: a parcel is the sink's quote answer, under the
--                            day caps at both ends, her working capital (npc_affordable) and her hold.
--   * fleet_buy_capacity     min(hold, stock, day cap), then the purse — composed; nothing to scale.
--   * price_history.stock    the chart's stock line: SCALED here too (× 10), so the line drawn from the
--                            last 47 slots meets the new level instead of jumping 10× at this deploy.
--                            Its mid is a price and is untouched.
--   * trade_daily.qty        what was really traded today — a record, not a size. Untouched.
--
-- ── ONE AUTHORITY ────────────────────────────────────────────────────────────────────────────────
--   market_depth (world_config, 10)  how deep every market is, as a multiple of 0005's seed depth.
--   world.market_depth_at(size_tier, affinity, depth)  THE derivation of a market row's normal stock
--       and production: 0005's arithmetic (written out seven times in the chain — 0005, 0041, 0048,
--       0058, 0062, 0065, 0090 — and again in scripts/build-world-growth.mjs and
--       scripts/db/tune-balance.mjs), × depth. Immutable and argument-only, like world.affinity_at, so a
--       seed can inline it. Its callers: this file, the generator and the tuner (both now compose it).
--   Like the affinity knobs, market_depth is applied when rows are WRITTEN: changing the knob alone
--   moves no existing row; a migration re-derives them through world.market_depth_at, as this one does.
--
-- ── WHAT IT SELF-ASSERTS ─────────────────────────────────────────────────────────────────────────
--   (pre) every row's target and production equal world.market_depth_at(tier, affinity, 1) — 0005's
--         seed exactly — or the file refuses: the × 10 below is only "the same market, deeper" if so.
--   (a) every row: stock, stock_target, production_rate = 10 × its pre-image; target and production =
--       world.market_depth_at(tier, affinity, market_depth); the row count unchanged and non-zero.
--   (b) THE PRICE IS UNCHANGED: on a deterministic probe set (every 7th quay row by port, good code),
--       world.price's mid / ask / bid and world.quote for 1 and for 10 units (one step), buy and sell,
--       equal the pre-image exactly — while the stock is 10×.
--   (c) THE DAY CAP IS 10× on the same set (world.daily_cap_remaining, no company), and a 200-unit buy
--       is never dearer a unit, and on most rows cheaper (price impact a tenth).
--   (d) RECOVERY SCALES: public.stock_after is × 10 out for × 10 in on the probe set (a planted
--       production), and one live tick of a planted half-empty probe market lands it at 10× the old step.
--   (e) price_history.stock = 10 × its pre-image on every row; its mid untouched.
--   (f) the lockdown stands and no client can execute world.market_depth_at.
-- No body is re-cut, no column altered, no grant moved. No top-level LOCK / SET LOCAL / BEGIN / SET ROLE.
-- ROLLBACK (a forward migration): the same update with depth 1 / 10 — stock, stock_target,
--   production_rate and price_history.stock ÷ 10 (stock rounded to the column), market_depth := 1.
-- VERSION: 0207 at writing (prod head 0206; applies on 0206, the good-board fix-forward, #264). It RENUMBERS
--   to the prod head + 1 at push, as every migration does.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  if exists (select 1 from public.world_config where key = 'market_depth') then
    raise exception '0207 refuses: market_depth already exists — the markets have been rescaled once';
  end if;
  if not exists (select 1 from public.port_goods) then
    raise exception '0207 refuses: no market rows';
  end if;
end $guard$;

-- ── 1. THE KNOB AND THE DERIVATION ──────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('market_depth', to_jsonb(10),
   '0207 (owner, 2026-10-19: "make the trade good quantity 10 times larger for all"): how deep every city market is, '
   'as a multiple of 0005''s seed depth. world.market_depth_at multiplies a row''s normal stock (stock_target) and its '
   'production_rate by this; the price reads stock / target, so the depth moves no price. Applied when rows are '
   'WRITTEN (0207 wrote every row at 10): changing it alone moves nothing until a migration re-derives the rows.');

create or replace function world.market_depth_at(
  p_size_tier int,
  p_affinity  numeric,
  p_depth     numeric,
  out stock_target    numeric,
  out production_rate numeric
)
language sql
immutable
parallel safe
as $$
  -- 0005's seed arithmetic (moved here, unchanged) × the depth: a city's size and how far it is from the
  -- good's source set how much it keeps; a producer (affinity below 0.80) also makes 5 % of it a day.
  select greatest(60, round(200 * p_size_tier * (1.60 - p_affinity))) * p_depth,
         case when p_affinity < 0.80
              then round(greatest(60, 200 * p_size_tier * (1.60 - p_affinity)) * 0.05, 2) * p_depth
              else 0 end
$$;

comment on function world.market_depth_at(int, numeric, numeric) is
  '0207: THE derivation of a market row''s normal stock and production — 0005''s seed arithmetic × the depth '
  '(world_config market_depth). Argument-only and immutable, like world.affinity_at, so a seed inlines it. '
  'Callers: 0207, scripts/build-world-growth.mjs, scripts/db/tune-balance.mjs. Server-only.';

revoke all on function world.market_depth_at(int, numeric, numeric) from public;

-- ── 2. THE PRE-IMAGE (refused unless every row is 0005's seed depth) ─────────────────────────────
-- Every market row is locked FIRST, so no trade or tick can move a stock between this pre-image and
-- the update below (a trade waits the few seconds this file takes; lock_timeout bounds the wait).
do $lock$
begin
  perform 1 from public.port_goods for update;
end $lock$;

create temp table pre_0207 on commit drop as
select pg.port_id, pg.good_id, p.size_tier, pg.affinity, pg.stock, pg.stock_target, pg.production_rate
  from public.port_goods pg join public.ports p on p.id = pg.port_id;

do $pre$
declare
  v_n int;
begin
  select count(*) into v_n
    from pre_0207 r cross join lateral world.market_depth_at(r.size_tier, r.affinity, 1) d
   where r.stock_target is distinct from d.stock_target or r.production_rate is distinct from d.production_rate;
  if v_n <> 0 then
    raise exception '0207 self-assert FAIL: % market row(s) are not at 0005''s seed depth — × 10 would not be the same market, deeper', v_n;
  end if;
end $pre$;

-- THE PROBE SET — deterministic: every 7th row a quay offers, by port code then good code.
create temp table probe_0207 on commit drop as
select x.port_id, x.good_id, x.port_code, x.good_code
  from (select pg.port_id, pg.good_id, p.code as port_code, g.code as good_code,
               row_number() over (order by p.code, g.code) as rn
          from public.port_goods pg
          join public.ports p on p.id = pg.port_id
          join public.goods g on g.id = pg.good_id
         where public.port_offers(pg.port_id, pg.good_id)) x
 where x.rn % 7 = 1;

create temp table quote_0207 (
  phase text, port_id uuid, good_id uuid,
  mid numeric, ask numeric, bid numeric,
  b1 numeric, b10 numeric, b10_total bigint, s1 numeric, s10 numeric, s10_total bigint,
  b200_units numeric, b200 numeric, cap numeric
) on commit drop;

create function pg_temp.quote_0207(p_phase text)
returns void
language sql
as $$
  insert into quote_0207
  select p_phase, pr.port_id, pr.good_id, wp.mid, wp.ask, wp.bid,
         qb1.avg_price, qb10.avg_price, qb10.total, qs1.avg_price, qs10.avg_price, qs10.total,
         qb200.units, qb200.avg_price,
         world.daily_cap_remaining(null::uuid, pr.port_id, pr.good_id)
    from probe_0207 pr
    cross join lateral world.price(pr.port_id, pr.good_id) wp
    cross join lateral world.quote(pr.port_id, pr.good_id, 1,   'buy',  null, null) qb1
    cross join lateral world.quote(pr.port_id, pr.good_id, 10,  'buy',  null, null) qb10
    cross join lateral world.quote(pr.port_id, pr.good_id, 1,   'sell', null, null) qs1
    cross join lateral world.quote(pr.port_id, pr.good_id, 10,  'sell', null, null) qs10
    cross join lateral world.quote(pr.port_id, pr.good_id, 200, 'buy',  null, null) qb200;
$$;

select pg_temp.quote_0207('before');

create temp table hist_0207 on commit drop as
select port_id, good_id, slot, mid, stock from public.price_history;

-- ── 3. THE MARKETS, TEN TIMES DEEPER ────────────────────────────────────────────────────────────
update public.port_goods pg
   set stock_target    = n.stock_target,
       production_rate = n.production_rate,
       stock           = round(pg.stock * public.wc_num('market_depth'), 2)
  from (select r.port_id, r.good_id, d.stock_target, d.production_rate
          from pre_0207 r
         cross join lateral world.market_depth_at(r.size_tier, r.affinity, public.wc_num('market_depth')) d) n
 where n.port_id = pg.port_id and n.good_id = pg.good_id;

update public.price_history set stock = round(stock * public.wc_num('market_depth'), 2);

select pg_temp.quote_0207('after');

-- ── 4. SELF-ASSERT ──────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_depth  numeric := public.wc_num('market_depth');
  v_n      int;
  v_rows   int;
  v_probes int;
  v_price  int;
  v_dearer int;
  v_cheaper int;
  v_filled int;
  v_hist   int;
  v_port   uuid;
  v_good   uuid;
  v_t      numeric;
  v_rate   numeric := public.wc_num('stock_regen_fraction');
  v_prod   numeric;
  v_got    numeric;
  v_want   numeric;
  v_ok     text;
begin
  if v_depth is distinct from 10 then
    raise exception '0207 self-assert FAIL: market_depth reads %, not 10', v_depth;
  end if;

  -- (a) every row × 10, and every row the derivation's answer
  select count(*) into v_rows from pre_0207;
  if v_rows = 0 or v_rows <> (select count(*) from public.port_goods) then
    raise exception '0207 self-assert FAIL: % pre-image rows against % market rows', v_rows, (select count(*) from public.port_goods);
  end if;
  select count(*) into v_n
    from pre_0207 r
    join public.port_goods pg on pg.port_id = r.port_id and pg.good_id = r.good_id
    cross join lateral world.market_depth_at(r.size_tier, pg.affinity, v_depth) d
   where pg.stock           <> r.stock * 10
      or pg.stock_target    <> r.stock_target * 10
      or pg.production_rate <> r.production_rate * 10
      or pg.stock_target    <> d.stock_target
      or pg.production_rate <> d.production_rate
      or pg.affinity        <> r.affinity;
  if v_n <> 0 then
    raise exception '0207 self-assert FAIL: % of % market row(s) are not exactly 10 × their pre-image at the derivation''s depth', v_n, v_rows;
  end if;

  -- (b) THE PRICE IS UNCHANGED for a fixed small amount (1 unit, and one 10-unit step), both sides
  select count(*) into v_probes from probe_0207;
  if v_probes < 100 then
    raise exception '0207 self-assert FAIL: only % probe rows — the price check would be thin', v_probes;
  end if;
  select count(*) into v_price
    from quote_0207 b join quote_0207 a on a.port_id = b.port_id and a.good_id = b.good_id
   where b.phase = 'before' and a.phase = 'after'
     and b.mid is not null and b.b10 is not null and b.s10 is not null
     and a.mid = b.mid and a.ask = b.ask and a.bid = b.bid
     and a.b1 = b.b1 and a.b10 = b.b10 and a.b10_total = b.b10_total
     and a.s1 = b.s1 and a.s10 = b.s10 and a.s10_total = b.s10_total;
  if v_price <> v_probes then
    raise exception '0207 self-assert FAIL: % of % probe rows quote the same price after × 10 (mid, ask, bid, 1 and 10 units buy and sell)', v_price, v_probes;
  end if;
  -- … while the stock really is 10× (the positive control: a price read off the wrong row would also "match")
  if exists (select 1 from probe_0207 pr
               join pre_0207 r on r.port_id = pr.port_id and r.good_id = pr.good_id
               join public.port_goods pg on pg.port_id = pr.port_id and pg.good_id = pr.good_id
              where pg.stock <> r.stock * 10 or r.stock <= 0) then
    raise exception '0207 self-assert FAIL: a probe row''s stock is not 10 × a non-empty pre-image';
  end if;

  -- (c) the day cap × 10; a 200-unit buy never dearer, mostly cheaper
  select count(*) into v_n
    from quote_0207 b join quote_0207 a on a.port_id = b.port_id and a.good_id = b.good_id
   where b.phase = 'before' and a.phase = 'after' and (b.cap <= 0 or a.cap <> b.cap * 10);
  if v_n <> 0 then
    raise exception '0207 self-assert FAIL: % probe row(s) whose day cap is not 10 × a positive pre-image', v_n;
  end if;
  select count(*) filter (where a.b200 > b.b200), count(*) filter (where a.b200 < b.b200), count(*)
    into v_dearer, v_cheaper, v_filled
    from quote_0207 b join quote_0207 a on a.port_id = b.port_id and a.good_id = b.good_id
   where b.phase = 'before' and a.phase = 'after' and b.b200_units = 200 and a.b200_units = 200;
  if v_filled = 0 or v_dearer <> 0 or v_cheaper * 2 < v_filled then
    raise exception '0207 self-assert FAIL: of % probe rows filling 200 units, % buy dearer and only % cheaper after × 10', v_filled, v_dearer, v_cheaper;
  end if;

  -- (d) RECOVERY SCALES — the rule, on the probe set with a planted production (prod has none) …
  select count(*) into v_n
    from probe_0207 pr
    join pre_0207 r on r.port_id = pr.port_id and r.good_id = pr.good_id
   where abs(public.stock_after(r.stock * 10 / 2, r.stock_target * 10, v_rate, r.stock_target * 10 * 0.05, 3)
             - 10 * public.stock_after(r.stock / 2, r.stock_target, v_rate, r.stock_target * 0.05, 3)) > 0.000001;
  if v_n <> 0 then
    raise exception '0207 self-assert FAIL: % probe row(s) where public.stock_after is not × 10 out for × 10 in', v_n;
  end if;
  -- … and the live tick, on the first probe market planted half empty a day back (rolled back)
  select pr.port_id, pr.good_id into v_port, v_good from probe_0207 pr order by pr.port_code, pr.good_code limit 1;
  begin
    select pg.stock_target, pg.production_rate * public.works_factor(pg.port_id, 'production', 'production_per_level')
      into v_t, v_prod
      from public.port_goods pg where pg.port_id = v_port and pg.good_id = v_good;
    update public.port_goods set stock = v_t / 2, last_regen_day = world.game_day() - 1
     where port_id = v_port and good_id = v_good;
    perform public.tick_market_drift(now(), v_port);
    select stock into v_got from public.port_goods where port_id = v_port and good_id = v_good;
    v_want := round(10 * public.stock_after(v_t / 20, v_t / 10, v_rate, v_prod / 10, 1), 2);   -- the old market's step, × 10
    if v_got is distinct from v_want or v_got <= v_t / 2 then
      raise exception '0207 self-assert FAIL: one tick took a half-empty market (target %) to %, not % (10 × the old step)', v_t, v_got, v_want;
    end if;
    v_ok := format('target %s: %s → %s in one game day', v_t, v_t / 2, v_got);
    raise exception using errcode = 'ZX207', message = v_ok;
  exception when sqlstate 'ZX207' then
    v_ok := sqlerrm;
  end;
  if exists (select 1 from public.port_goods pg join pre_0207 r on r.port_id = pg.port_id and r.good_id = pg.good_id
              where pg.port_id = v_port and pg.good_id = v_good and pg.stock <> r.stock * 10) then
    raise exception '0207 self-assert FAIL: the planted probe market survived its rollback';
  end if;

  -- (e) the chart's stock line × 10, its price untouched
  select count(*) into v_hist from hist_0207;
  select count(*) into v_n
    from hist_0207 h
    left join public.price_history ph on ph.port_id = h.port_id and ph.good_id = h.good_id and ph.slot = h.slot
   where ph.port_id is null or ph.stock <> round(h.stock * 10, 2) or ph.mid <> h.mid;
  if v_n <> 0 then
    raise exception '0207 self-assert FAIL: % of % price_history row(s) are not 10 × their stock with their mid unmoved', v_n, v_hist;
  end if;

  -- (f) the walls
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0
     or exists (select 1 from unnest(array['anon', 'authenticated']) rl(role)
                 where has_function_privilege(rl.role, 'world.market_depth_at(int, numeric, numeric)', 'execute')) then
    raise exception '0207 self-assert FAIL: a wall moved, or a client can reach world.market_depth_at';
  end if;

  raise notice '0207 self-assert ok: EVERY MARKET IS TEN TIMES DEEPER. market_depth 10; world.market_depth_at = 0005''s seed × depth. % market rows: stock, stock_target, production_rate exactly 10 × (target %–% → %–%). PRICE UNCHANGED on % probe quays: mid / ask / bid and 1- and 10-unit quotes, buy and sell, equal to the cent while the stock is 10×. Day cap 10× on every probe. 200 units bought: % probe rows filled, % cheaper a unit, % dearer. Recovery: stock_after × 10 out for × 10 in; one tick %. price_history: % rows, stock × 10, mid unmoved.',
    v_rows,
    (select min(stock_target) from pre_0207), (select max(stock_target) from pre_0207),
    (select min(stock_target) from public.port_goods), (select max(stock_target) from public.port_goods),
    v_probes, v_filled, v_cheaper, v_dearer, v_ok, v_hist;
end $$;
