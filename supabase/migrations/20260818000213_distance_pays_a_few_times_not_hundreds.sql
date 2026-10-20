-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0213 — DISTANCE PAYS A FEW TIMES, NOT HUNDREDS
--        (one knob moves: haul_max 600 → 3; the hauls are refilled from the one derivation, as 0208 did)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY (the prod audit of 2026-10-20, read-only, head 0211) ────────────────────────────────────
-- A far sale's distance premium is paid by the city's PEOPLE (0174's IMPORT_DEMAND flow): money minted
-- from nothing. On prod it was ~57 % of every sale's value — about 500–600 M ducats a real day against a
-- world money stock of ~1.6 B. Routes of 10,000 nm and more were 30 % of the merchants' laps and 89 % of
-- all their profit. The cause is the SIZE of 0173's haul: at the far end a good sold for haul_max 600 ×
-- haul_premium_share 0.5 → 300.5 times its maker's price (the far-selling baseline of 2026-10-19 measured
-- a competent trader's long route at ~200× a short route's profit PER DAY; the owner's target, approved
-- 2026-10-19, is 1.3–1.5×).
--
-- ── THE ONE KNOB ────────────────────────────────────────────────────────────────────────────────
-- 0173's arithmetic is the ONE authority for the haul and is NOT re-cut here:
--     world.haul_at(nm, max, reach, curve, share) = 1 + share × (max ^ (min(1, nm / reach) ^ curve) − 1)
-- It reads haul_max through world.haul_rows() (0173, 0208). This file sets haul_max 600 → 3, so the far
-- end pays 1 + 0.5 × (3 − 1) = 2 × (was 300.5 ×), and refills port_goods.haul_nm / haul from
-- world.haul_rows() exactly as 0208 did. haul_premium_share (0.5), haul_reach_nm (14,500) and haul_curve
-- (2.0) are untouched, so the SHAPE of the curve is 0173's: next to nothing near home, rising over an ocean.
-- With max 3 (at 4 dp):   nm   1,000   2,500   5,000   7,500   10,000  12,000  14,006 (Mokpo → London)  ≥ 14,500
--                         haul 1.0026  1.0166  1.0698  1.1708  1.3431  1.5611  1.8936                   2
-- (today, max 600:        1.0154  1.1047  1.5698  3.2684  10.979  40.469  195.99                   300.5;
--  the plan's default 8:  1.005   1.0319  1.1403  1.3721  1.8443  2.5773  3.9801                   4.5).
-- WHY 3 AND NOT THE PLAN'S 8 — docs/dev-log/2026-10-20-haul-cap.md §2: on the far-selling metric (a competent
-- trader's best profit per day by route band, prod-shaped world) 8 leaves a 10,000+ nm route at 6.0 × a short
-- route's profit per day (5–10k at 2.7 ×); 3 puts it at 1.45 ×, inside the owner's approved 1.3–1.5 band. The
-- knob is the one place to move if the owner prefers 8 (4.5 ×): the self-assert follows c_max below.
--
-- ── WHAT MOVES WITH IT, AND WHAT DOES NOT ────────────────────────────────────────────────────────
-- MOVES: every market row's stored haul (port_goods.haul: 130,356 of 132,090 rows on prod are above 1; a
--   maker's row, haul_nm 0, stays at 1 to the digit); therefore every far mid / ask / bid / quote / outlook /
--   route / good board, because world.mid_terms reads pg.haul and world.mid_from_terms multiplies by it —
--   no body changes, no hunk. price_history.mid × (new haul ÷ old haul) per row, so the chart meets the
--   new level instead of falling off a cliff at this deploy (0208 did the same; 64,704 rows on prod).
-- DOES NOT MOVE (stated, decided by default): 0174's split of a sale — the purse pays round(total / haul),
--   the people pay the rest (cmd.do_sell, public.cargo_haul: their bodies are asserted unmoved) — only the
--   haul it reads is smaller, so IMPORT_DEMAND shrinks with it. Affinity (0005), demand, faith tastes, the
--   glut, the spread, the tax, the city bid. Cargo cost basis (what was PAID, at a maker: haul 1 there),
--   route-line limits (merchants' BUY ceilings, at makers), open orders, contracts (money already escrowed),
--   lap books. The merchants' loops: a loop planned for a 300 × sale now sells at ≤ 2 ×; the planner
--   reviews loops on its own schedule (npc_route_review_laps), and 0180's budget rule still sells only at a
--   profit over the basis.
--
-- ── WHAT IT SELF-ASSERTS (own probe rows; every selection was run read-only on prod first) ──────
-- (a) the knob reads 3; share / reach / curve read what they did.
-- (b) every market row = world.haul_rows() (both columns); makers at 1 / 0 nm, untouched to the digit;
--     every row with a premium moved; the haul still rises with distance (monotone); the largest haul is 2.
-- (c) ONLY THE KNOB MOVED: on every row, the new haul = world.haul_at(nm, 3, reach, curve, share) and the
--     old haul = world.haul_at(nm, 600, reach, curve, share) — the same arithmetic, the same other knobs.
--     The probe pair (the first row beyond the reach, by port and good code) reads 300.5 → 2 exactly.
-- (d) prices: on a quay probe set (every 7th row a city offers, haul 1 there) mid / ask / bid and the 1-
--     and 10-unit quotes, buy and sell, are IDENTICAL to the digit at the same stock; on a far probe set
--     (every 211th row above haul 1) the mid is old mid × (new ÷ old haul) within the 4-dp rounding.
-- (e) every price_history row = round(old mid × new haul ÷ old haul, 4).
-- (f) public.cargo_haul(port, good) (0174's one reader of the stored haul) = the stored haul on the far
--     probe set; the bodies of cmd.do_sell, cargo_haul, haul_at and haul_rows have the md5 they had; the
--     walls (client_write_grants / client_executable_writers / caller_evaluated_functions) are 0.
-- (g) timings (notice only): world.quote and world.price, 8 calls each in one session.
-- RECEIPT: kimchi's mid from Mokpo to London, before → after (a statement, not an assert).
-- ROLLBACK (a forward migration): haul_max 3 → 600, refill from world.haul_rows(), price_history ×
--   (old ÷ new) per row. IMPORT_DEMAND already paid is money: it stays.
-- LOCKS: port_goods FOR UPDATE for the length of this file (a trade waits the seconds it takes: the refill
--   of 132,090 rows and the probe quotes), then one UPDATE of price_history. No LOCK TABLE, no set role, no
--   set local, no begin. Deploy with the clock unwound, as 0208 was.
-- VERSION: 0213 at writing (prod head 0211, live; 0212 is the insurance slice's number). It RENUMBERS to
--   the prod head + 1 at push.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  if public.wc_num('haul_max') is distinct from 600 then
    raise exception '0213 refuses: haul_max reads %, not 600 — this has been applied once, or the world is not the one this file was cut for', public.wc_num('haul_max');
  end if;
  if public.wc_num('haul_premium_share') is distinct from 0.5 or public.wc_num('haul_reach_nm') is distinct from 14500
     or public.wc_num('haul_curve') is distinct from 2.0 then
    raise exception '0213 refuses: share / reach / curve read % / % / %, not 0.5 / 14500 / 2.0',
      public.wc_num('haul_premium_share'), public.wc_num('haul_reach_nm'), public.wc_num('haul_curve');
  end if;
  if to_regprocedure('world.haul_at(numeric, numeric, numeric, numeric, numeric)') is null
     or to_regprocedure('world.haul_rows()') is null
     or to_regprocedure('public.cargo_haul(uuid, uuid)') is null then
    raise exception '0213 refuses: 0208''s haul_at, 0173''s haul_rows or 0174''s cargo_haul is not in this world';
  end if;
end $guard$;

-- ── 1. LOCK, THEN THE PRE-IMAGES ────────────────────────────────────────────────────────────────
do $lock$
begin
  perform 1 from public.port_goods for update;
end $lock$;

create temp table bodies_0213 on commit drop as
select f.fn, md5(replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '')) as h
  from (values ('cmd.do_sell(uuid, jsonb)'), ('public.cargo_haul(uuid, uuid)'),
               ('world.haul_at(numeric, numeric, numeric, numeric, numeric)'), ('world.haul_rows()')) f(fn);

create temp table hauls_0213 on commit drop as select port_id, good_id, haul_nm, haul from public.port_goods;
create temp table hist_0213 on commit drop as select port_id, good_id, slot, mid from public.price_history;

-- THE PRICE PROBE SET — deterministic (0208's): every 7th row a quay offers (haul 1 there), by port then
-- good code; and the FAR set: every 211th row with a haul above 1, by port then good code.
create temp table probe_0213 on commit drop as
select x.port_id, x.good_id, x.port_code, x.good_code, 'quay'::text as kind
  from (select pg.port_id, pg.good_id, p.code as port_code, g.code as good_code,
               row_number() over (order by p.code, g.code) as rn
          from public.port_goods pg
          join public.ports p on p.id = pg.port_id
          join public.goods g on g.id = pg.good_id
         where public.port_offers(pg.port_id, pg.good_id)) x
 where x.rn % 7 = 1
union all
select x.port_id, x.good_id, x.port_code, x.good_code, 'far'
  from (select pg.port_id, pg.good_id, p.code as port_code, g.code as good_code,
               row_number() over (order by p.code, g.code) as rn
          from public.port_goods pg
          join public.ports p on p.id = pg.port_id
          join public.goods g on g.id = pg.good_id
         where pg.haul > 1) x
 where x.rn % 211 = 1;

create temp table quote_0213 (
  phase text, port_id uuid, good_id uuid, mid numeric, ask numeric, bid numeric,
  b1 numeric, b10 numeric, s1 numeric, s10 numeric, stock numeric
) on commit drop;

create function pg_temp.quote_0213(p_phase text) returns void language sql as $$
  insert into quote_0213
  select p_phase, pr.port_id, pr.good_id, wp.mid, wp.ask, wp.bid,
         qb1.avg_price, qb10.avg_price, qs1.avg_price, qs10.avg_price,
         (select pg.stock from public.port_goods pg where pg.port_id = pr.port_id and pg.good_id = pr.good_id)
    from probe_0213 pr
    cross join lateral world.price(pr.port_id, pr.good_id) wp
    cross join lateral world.quote(pr.port_id, pr.good_id, 1,  'buy',  null, null) qb1
    cross join lateral world.quote(pr.port_id, pr.good_id, 10, 'buy',  null, null) qb10
    cross join lateral world.quote(pr.port_id, pr.good_id, 1,  'sell', null, null) qs1
    cross join lateral world.quote(pr.port_id, pr.good_id, 10, 'sell', null, null) qs10;
$$;
select pg_temp.quote_0213('before');

-- ── 2. THE KNOB ─────────────────────────────────────────────────────────────────────────────────
update public.world_config
   set value = to_jsonb(3),
       description = coalesce(description, '')
         || ' 0213 (2026-10-20): 600 → 3. The far end now pays 1 + haul_premium_share × 2 = 2 × (was 300.5 ×). '
            'The premium was minted (0174''s IMPORT_DEMAND, ~57 % of every sale on prod); the owner''s target is a '
            'long route at ~1.3–1.5 × a short one''s profit per day. port_goods.haul is refilled from world.haul_rows() '
            'by the migration that moves this.'
 where key = 'haul_max';

-- ── 3. THE ROWS, refilled from the one derivation (0208's statement) ───────────────────────────
update public.port_goods pg
   set haul_nm = h.haul_nm, haul = h.haul
  from world.haul_rows() h
 where h.port_id = pg.port_id and h.good_id = pg.good_id
   and (pg.haul is distinct from h.haul or pg.haul_nm is distinct from h.haul_nm);

-- the chart follows the level (0208's statement, without the price level's factor)
update public.price_history ph
   set mid = round(ph.mid * pg.haul / h.haul, 4)
  from hauls_0213 h, public.port_goods pg
 where h.port_id = ph.port_id and h.good_id = ph.good_id
   and pg.port_id = ph.port_id and pg.good_id = ph.good_id
   and pg.haul <> h.haul;

select pg_temp.quote_0213('after');

-- ── 4. SELF-ASSERT ──────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_max     constant numeric := 3;                        -- THE value this file sets (the one literal above is asserted against it)
  c_far     constant numeric := 1 + 0.5 * (c_max - 1);    -- what the far end pays at share 0.5
  v_rows    int;
  v_n       int;
  v_m       int;
  v_moved   int;
  v_makers  int;
  v_quay    int;
  v_far     int;
  v_hist    int;
  v_maxh    numeric;
  v_pair    record;
  v_kimchi  text;
  v_t       timestamptz;
  v_ms      numeric[] := '{}';
  v_pms     numeric[] := '{}';
  v_port    uuid;
  v_good    uuid;
  i         int;
begin
  -- (a) THE KNOB, and the knobs that must not have moved
  if public.wc_num('haul_max') is distinct from c_max or public.wc_num('haul_premium_share') is distinct from 0.5
     or public.wc_num('haul_reach_nm') is distinct from 14500 or public.wc_num('haul_curve') is distinct from 2.0 then
    raise exception '0213 self-assert FAIL: the haul knobs read max %, share %, reach %, curve %',
      public.wc_num('haul_max'), public.wc_num('haul_premium_share'), public.wc_num('haul_reach_nm'), public.wc_num('haul_curve');
  end if;

  -- (b) EVERY ROW IS THE DERIVATION; makers untouched; every far row moved; monotone; the ceiling
  select count(*) into v_rows from hauls_0213;
  if v_rows = 0 or v_rows <> (select count(*) from public.port_goods) then
    raise exception '0213 self-assert FAIL: % rows before, % after', v_rows, (select count(*) from public.port_goods);
  end if;
  select count(*) filter (where h.port_id is null or pg.haul is distinct from h.haul or pg.haul_nm is distinct from h.haul_nm),
         count(*) filter (where pg.haul <> o.haul),
         count(*) filter (where o.haul > 1 and pg.haul = o.haul),
         max(pg.haul)
    into v_n, v_moved, v_m, v_maxh
    from public.port_goods pg
    join hauls_0213 o on o.port_id = pg.port_id and o.good_id = pg.good_id
    left join world.haul_rows() h on h.port_id = pg.port_id and h.good_id = pg.good_id;
  -- (a row whose premium rounded to 0 at 4 dp before — a few dozen nm from a maker — stays at 1; a row with
  --  any premium at all moves: 8's premium is under a third of 600's at every distance, so no 4-dp step holds)
  if v_n <> 0 or v_moved = 0 or v_m <> 0 then
    raise exception '0213 self-assert FAIL: % market row(s) differ from world.haul_rows(); % moved; % row(s) with a premium did not move', v_n, v_moved, v_m;
  end if;
  select count(*), count(*) filter (where pg.haul <> 1 or pg.haul_nm is distinct from 0 or o.haul <> 1) into v_makers, v_n
    from public.ports p cross join lateral public.port_offered_goods(p.id) og
    join public.port_goods pg on pg.port_id = p.id and pg.good_id = og.good_id
    join hauls_0213 o on o.port_id = pg.port_id and o.good_id = pg.good_id;
  if v_makers = 0 or v_n <> 0 then
    raise exception '0213 self-assert FAIL: % of % maker rows are not at haul 1 / 0 nm before and after', v_n, v_makers;
  end if;
  select count(*) into v_n from (
    select haul, lag(haul) over (order by haul_nm, haul) as prev from public.port_goods where haul_nm is not null) x
   where x.haul < x.prev;
  if v_n > 0 then
    raise exception '0213 self-assert FAIL: the haul falls with distance on % row(s)', v_n;
  end if;
  if v_maxh <> c_far then
    raise exception '0213 self-assert FAIL: the largest haul in the world is %, not % (= 1 + 0.5 × (% − 1))', v_maxh, c_far, c_max;
  end if;

  -- (c) ONLY THE KNOB MOVED: the same arithmetic, the same other knobs, max c_max now and 600 before
  select count(*) into v_n
    from public.port_goods pg join hauls_0213 o on o.port_id = pg.port_id and o.good_id = pg.good_id
   where pg.haul is distinct from world.haul_at(pg.haul_nm, c_max, public.wc_num('haul_reach_nm'), public.wc_num('haul_curve'), public.wc_num('haul_premium_share'))
      or o.haul is distinct from world.haul_at(o.haul_nm, 600, public.wc_num('haul_reach_nm'), public.wc_num('haul_curve'), public.wc_num('haul_premium_share'))
      or pg.haul > o.haul;
  if v_n <> 0 then
    raise exception '0213 self-assert FAIL: % row(s) whose haul is not world.haul_at at max % now and max 600 before (or rose)', v_n, c_max;
  end if;
  select p.code as port, g.code as good, o.haul as old_h, pg.haul as new_h, pg.port_id, pg.good_id into v_pair
    from public.port_goods pg
    join hauls_0213 o on o.port_id = pg.port_id and o.good_id = pg.good_id
    join public.ports p on p.id = pg.port_id join public.goods g on g.id = pg.good_id
   where o.haul_nm >= public.wc_num('haul_reach_nm')
   order by p.code, g.code limit 1;
  if v_pair.port is null or v_pair.old_h <> 300.5 or v_pair.new_h <> c_far then
    raise exception '0213 self-assert FAIL: the probe pair % / % beyond the reach reads % → %, not 300.5 → %',
      v_pair.port, v_pair.good, v_pair.old_h, v_pair.new_h, c_far;
  end if;

  -- (d) PRICES: a maker's quay is untouched to the digit; a far row's mid follows its haul
  select count(*) filter (where pr.kind = 'quay'), count(*) filter (where pr.kind = 'far') into v_quay, v_far from probe_0213 pr;
  if v_quay < 100 or v_far < 100 then
    raise exception '0213 self-assert FAIL: only % quay and % far probe rows — the price check would be thin', v_quay, v_far;
  end if;
  if exists (select 1 from probe_0213 pr join hauls_0213 h on h.port_id = pr.port_id and h.good_id = pr.good_id
              where pr.kind = 'quay' and h.haul <> 1) then
    raise exception '0213 self-assert FAIL: a quay probe row had a haul above 1';
  end if;
  select count(*) into v_n
    from probe_0213 pr
    join quote_0213 b on b.port_id = pr.port_id and b.good_id = pr.good_id and b.phase = 'before'
    join quote_0213 a on a.port_id = pr.port_id and a.good_id = pr.good_id and a.phase = 'after'
   where pr.kind = 'quay' and b.mid is not null and b.b10 is not null and b.s10 is not null
     and (a.mid, a.ask, a.bid, a.b1, a.b10, a.s1, a.s10, a.stock) is not distinct from (b.mid, b.ask, b.bid, b.b1, b.b10, b.s1, b.s10, b.stock);
  if v_n <> v_quay then
    raise exception '0213 self-assert FAIL: % of % quay probe rows quote the same to the digit (mid, ask, bid, 1 and 10 units buy and sell)', v_n, v_quay;
  end if;
  select count(*) into v_n
    from probe_0213 pr
    join quote_0213 b on b.port_id = pr.port_id and b.good_id = pr.good_id and b.phase = 'before'
    join quote_0213 a on a.port_id = pr.port_id and a.good_id = pr.good_id and a.phase = 'after'
    join hauls_0213 h on h.port_id = pr.port_id and h.good_id = pr.good_id
    join public.port_goods pg on pg.port_id = pr.port_id and pg.good_id = pr.good_id
   where pr.kind = 'far' and a.stock = b.stock and pg.haul < h.haul and a.mid <= b.mid
     and abs(a.mid - b.mid * pg.haul / h.haul) <= 0.0003;   -- two 4-dp roundings: at most 0.0001 apart
  if v_n <> v_far then
    raise exception '0213 self-assert FAIL: % of % far probe rows price at (new haul ÷ old haul) of their old mid, no higher, at the same stock', v_n, v_far;
  end if;

  -- (e) THE CHART
  select count(*) into v_hist from hist_0213;
  select count(*) into v_n
    from hist_0213 h0
    join hauls_0213 o on o.port_id = h0.port_id and o.good_id = h0.good_id
    join public.port_goods pg on pg.port_id = h0.port_id and pg.good_id = h0.good_id
    left join public.price_history ph on ph.port_id = h0.port_id and ph.good_id = h0.good_id and ph.slot = h0.slot
   where ph.port_id is null or ph.mid <> round(h0.mid * pg.haul / o.haul, 4);
  if v_n <> 0 then
    raise exception '0213 self-assert FAIL: % of % price_history row(s) are not (new haul ÷ old haul) of their mid', v_n, v_hist;
  end if;

  -- (f) 0174's READER reads the new haul; no body moved; the walls
  select count(*) into v_n
    from probe_0213 pr join public.port_goods pg on pg.port_id = pr.port_id and pg.good_id = pr.good_id
   where pr.kind = 'far' and public.cargo_haul(pr.port_id, pr.good_id) <> pg.haul;
  if v_n <> 0 then
    raise exception '0213 self-assert FAIL: public.cargo_haul differs from the stored haul on % far probe row(s)', v_n;
  end if;
  select count(*) into v_n from bodies_0213 b
   where b.h <> md5(replace(pg_get_functiondef(b.fn::regprocedure), E'\r', ''));
  if v_n <> 0 then
    raise exception '0213 self-assert FAIL: % of the 4 bodies (do_sell, cargo_haul, haul_at, haul_rows) changed — this file moves a knob, not a body', v_n;
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0213 self-assert FAIL: a wall moved';
  end if;

  -- (g) TIMINGS (notice only): no hot body changed; 8 calls each in this session
  select pr.port_id, pr.good_id into v_port, v_good from probe_0213 pr where pr.kind = 'far' order by pr.port_code, pr.good_code limit 1;
  for i in 1..8 loop
    v_t := clock_timestamp();
    perform * from world.quote(v_port, v_good, 50, 'sell', null, null);
    v_ms := v_ms || round(extract(epoch from clock_timestamp() - v_t) * 1000, 2);
    v_t := clock_timestamp();
    perform * from world.price(v_port, v_good);
    v_pms := v_pms || round(extract(epoch from clock_timestamp() - v_t) * 1000, 2);
  end loop;

  -- THE RECEIPT: kimchi from its maker to London (a statement)
  select string_agg(format('%s %s nm ×%s→×%s: %s → %s', p.code, pg.haul_nm, o.haul, pg.haul,
                           round(world.mid_price(pg.port_id, pg.good_id, pg.stock) * o.haul / pg.haul, 2),
                           round(world.mid_price(pg.port_id, pg.good_id, pg.stock), 2)), '; ' order by pg.haul_nm)
    into v_kimchi
    from public.port_goods pg join hauls_0213 o on o.port_id = pg.port_id and o.good_id = pg.good_id
    join public.goods g on g.id = pg.good_id join public.ports p on p.id = pg.port_id
   where g.code = 'kimchi' and p.code in ('MOK', 'NAG', 'MAL', 'GOA', 'ALE', 'LIS', 'LON');

  raise notice '0213 self-assert ok: DISTANCE PAYS A FEW TIMES, NOT HUNDREDS. haul_max 600 → % (share 0.5, reach 14500, curve 2.0 kept): % market rows = world.haul_rows(), % moved, % maker rows at 1 untouched, monotone, largest haul % (pair %/% % → %, exact); every row = haul_at at % now and at 600 before. PRICES: % quay probes identical to the digit; % far probes at (new ÷ old haul) of their mid. CHART: % price_history rows follow. cargo_haul = the stored haul on every far probe; 4 bodies unmoved; walls 0. KIMCHI (mid before → after): %. world.quote(50 sell) ms %, world.price ms %.',
    c_max, v_rows, v_moved, v_makers, v_maxh, v_pair.port, v_pair.good, v_pair.old_h, v_pair.new_h, c_max,
    v_quay, v_far, v_hist, v_kimchi, v_ms, v_pms;
end $$;
