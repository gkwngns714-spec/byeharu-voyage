-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0170 — A PRICE SAYS WHERE IT IS GOING  (COMMAND DESK slice D1: the estimate, one server read)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY ─────────────────────────────────────────────────────────────────────────────────────────
-- The owner, 2026-10-17: *"i will be able to see the estimated price movement so that i can plan buying
-- and selling for max profit. for example when i press coffee trade goods, it will show chart, where i can
-- buy, the price if i sell to other cities. at which time and so on."* docs/COMMAND_DESK.md §4, §7.1 and
-- §10 row D1. The estimate is the server's, built from the terms the price is made of today
-- (world.mid_terms → world.mid_from_terms); the client draws it and computes nothing.
--
-- ── WHAT THIS FILE DOES (one authority each) ────────────────────────────────────────────────────
-- (1) public.stock_after(stock, target, rate, production, days) — NEW: the regeneration rule, MOVED out of
--     public.tick_market_drift's UPDATE (one hunk; the tick composes it, inlined, and reverses to its
--     pre-image). The outlook steps the same leaf.
-- (2) public.drift_moments(d0, k) — NEW: the drift walk's mean and spread after 0..k steps, beside the tick
--     that steps it, from the three knobs the tick reads: mean_{k+1} = the tick's own step with the draw at
--     its mean (θ·mean, clamped, at the column's scale); sd_k = σ·sqrt((1 − θ^2k) / (1 − θ²)).
-- (3) world.price_terms(port) and world.price_sides(mid, spread, tax, bid factor) — NEW: what a quay adds
--     to a mid, MOVED out of world.price (three hunks; world.price composes both and answers as before —
--     asserted on every row of the sample). The outlook prices its ask and bid through the same two.
-- (4) public.price_path(port, good, slots) — NEW, server-only: k = 0 is the market row as it stands (so it
--     IS world.price); k = 1..H are the next H drift slots, each a step of the tick: the drift at its mean,
--     the stock regenerated through (1) whenever a game day passes, every other term as world.mid_terms
--     reads it; lo / hi are the price at the drift's mean ∓ outlook_band_z × sd (clamped).
-- (5) world.price_outlook(port, good, slots, side) — NEW, the client's read (registered, authenticated
--     only): the path on one side (mid / ask / bid), the best time (only when its gain beats the band's
--     half-width there — else null), the fairs that fall in the window, and the assumption, in words.
--     Knobs outlook_slots 24, outlook_slots_max 96, outlook_band_z 1.2816 (80 %).
-- (6) THE RECORD, REPAIRED: public.price_history rows numbered on an older, shorter slot clock
--     (slot > drift_slot_of(now()) — 61,824 rows on prod, all dated 2026-09-02) are deleted, and
--     public.tick_price_snapshot's prune also drops a row numbered past the present slot (one hunk), so a
--     change of slot length can never again leave rows the window rule cannot reach and the history read
--     serves as its newest points.
--
-- ── WHAT IT DELIBERATELY DOES NOT DO ────────────────────────────────────────────────────────────
-- Change any price, rule, knob the tick reads, schedule, or grant of an existing function. Forecast other
-- traders (COMMAND_DESK D5: "If nobody else trades here"). Hold anything per fleet (no p_fleet: a price is
-- the market's, and the purser's shave is the quote's — D2's good_board names a fleet). Add a client
-- catalogue entry: that lands WITH the face that reads it (D3), as every entry point here has.
--
-- ── THE PROOF (in this file; production is lived in while it runs, so only OWN state is asserted) ─
-- A SAMPLE of up to four harbours (the most rows short of their target, the most rows, the first and the last by id) is
-- captured once into a temp table; every probe re-writes every sample row from that capture before it
-- runs (and bends nine rows so every arm is taken), inside a sub-transaction that is rolled back — so a
-- player's trade between two runs cannot make them differ, and nothing a probe writes survives.
--   (a) world.price, old (the pre-image, pg_temp) vs new, on every sample row and two md5-chosen goods of
--       every harbour: equal.  k = 0 of the outlook, on the same rows × mid / ask / bid: world.price to
--       the cent.
--   (b) the tick, old (pre-image) vs new, σ = 0, the sample harbour by harbour at the next 24 slot
--       boundaries: the same rows after every step (md5 of every row's stock, drift, slot and day).
--   (c) the outlook vs the tick: on the bent rows and an md5 subset, the path's stock and drift at k equal
--       the rows the tick left at t_k, for k = 1..24, and its mid equals world.price at k = 1, 8, 24.
--       The arms: both clamps, stock 0, stock 2 × target (pulled down), production > 0, a three-day
--       catch-up, a flat row (best null), a low drift (bid best later), a short stock (ask best later).
--   (d) the band: random() seeded (setseed, then reseeded from the clock), σ as live, every sample row
--       at drift 0.12, 24 steps: at k = 1, 4, 24 the observed mean is within 4 SE of drift_moments and the
--       share inside the band within 4 SE of erf(z / √2) (80 %).
--   (e) the record: no row past the present slot remains; a planted one is pruned by the snapshot.
--   (f) refusals; the registry +1 (authenticated may, anon may not); the leaves server-only; the walls.
--   Timings: raise notice only.
--
-- ── LOCKS, AND HOW LONG THE PUSH TAKES ──────────────────────────────────────────────────────────
-- CREATE (OR REPLACE) FUNCTION (catalogue only). DELETE of the stale history rows (row locks on rows no
-- one writes). The probes lock the sample's port_goods rows only while each sub-transaction runs (a few
-- hundred ms to ~2 s each; their row locks go with the rollback): a trade at one of those harbours
-- waits that long at most. No LOCK TABLE, no set role, no set local, no begin. Measured on the cached
-- PGlite world: see the dev-log (docs/dev-log/2026-10-18-command-desk-d1.md).
--
-- ── DEPLOY ──────────────────────────────────────────────────────────────────────────────────────
-- DEPLOY_RUNBOOK: select public.unwind_the_clock(); → supabase db push --linked --include-all →
-- select public.wind_the_clock(). Nothing reads the new function until D3's client; the history repair
-- shows at once (the market chart of a pair that held stale rows draws 12 hours, not 45 days).
-- ROLLBACK: a forward migration restoring the three re-cut bodies from this file's hunks (old text) and
-- dropping the six new functions; the deleted rows were a defect and are not restored.
-- VERSION: 0170 (prod head 0169, read 2026-10-18). 0169 (the arrivals sweep's step 4, #191) re-cut world.quote and
-- world.trade_routes and added world.quote_terms / world.quote_priced; this file touches none of them. Every
-- hunk was checked to occur exactly once in production's live bodies (read-only, after 0169 landed).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

create or replace function pg_temp.occurs_0170(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 1. THE PRE-IMAGES ─────────────────────────────────────────────────────────────────────────
create temp table defs_before_0170 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg,
       (select p.proowner from pg_proc p where p.oid = f.fn::regprocedure) as owner
  from (values ('public.tick_market_drift(timestamp with time zone, uuid)'),
               ('world.price(uuid, uuid)'),
               ('public.tick_price_snapshot(timestamp with time zone)'),
               ('public.client_rpc_entry_points()')) f(fn);

create temp table before_0170 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from public.price_history where slot > public.drift_slot_of(now())) as stale,
       (select count(*) from public.price_history where slot <= public.drift_slot_of(now())) as kept,
       (select count(*) from public.world_config where key in ('outlook_slots', 'outlook_slots_max', 'outlook_band_z')) as own_knobs,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where (n.nspname, p.proname) in (('public', 'stock_after'), ('public', 'drift_moments'), ('public', 'price_path'),
                                          ('world', 'price_terms'), ('world', 'price_sides'), ('world', 'price_outlook'))) as n_found;

do $$
begin
  if (select count(*) from defs_before_0170 where def is not null) <> 4 then
    raise exception '0170 self-assert FAIL: % of the 4 bodies found', (select count(*) from defs_before_0170 where def is not null);
  end if;
  if (select n_found from before_0170) <> 0 then
    raise exception '0170 self-assert FAIL: a function this file creates already exists';
  end if;
  -- THE COLUMNS' SCALES the outlook steps at (the tick's assignment rounds to them): drift numeric(6,4),
  -- stock numeric(12,2). Stated here so a change of either is a red, not a silent drift of the estimate.
  if (select format_type(a.atttypid, a.atttypmod) from pg_attribute a
       where a.attrelid = 'public.port_goods'::regclass and a.attname = 'drift') <> 'numeric(6,4)'
     or (select format_type(a.atttypid, a.atttypmod) from pg_attribute a
          where a.attrelid = 'public.port_goods'::regclass and a.attname = 'stock') <> 'numeric(12,2)' then
    raise exception '0170 self-assert FAIL: port_goods.drift is not numeric(6,4) or port_goods.stock is not numeric(12,2) — the outlook''s steps round to them';
  end if;
end $$;

-- the old copies the proofs run against the new bodies
do $$
declare
  v_def text;
begin
  select def into v_def from defs_before_0170 where fn = 'public.tick_market_drift(timestamp with time zone, uuid)';
  v_def := replace(v_def, 'CREATE OR REPLACE FUNCTION public.tick_market_drift(', 'CREATE OR REPLACE FUNCTION pg_temp.tick_market_drift_old_0170(');
  if strpos(v_def, 'FUNCTION pg_temp.tick_market_drift_old_0170(') = 0 or strpos(v_def, 'stock_after') > 0 then
    raise exception '0170 self-assert FAIL: the old copy of tick_market_drift was not made from the pre-image';
  end if;
  execute v_def;
  select def into v_def from defs_before_0170 where fn = 'world.price(uuid, uuid)';
  v_def := replace(v_def, 'CREATE OR REPLACE FUNCTION world.price(', 'CREATE OR REPLACE FUNCTION pg_temp.price_old_0170(');
  if strpos(v_def, 'FUNCTION pg_temp.price_old_0170(') = 0 or strpos(v_def, 'price_terms') > 0 then
    raise exception '0170 self-assert FAIL: the old copy of world.price was not made from the pre-image';
  end if;
  execute v_def;
end $$;

-- ── 2. THE KNOBS (only where absent) ──────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('outlook_slots', '24'::jsonb,
   '0170 (docs/COMMAND_DESK.md D3): how many drift slots ahead world.price_outlook looks when it is not told '
   '(24 × 900 s = 6 hours: four stock refills, and the drift''s spread at ~99 % of its limit).'),
  ('outlook_slots_max', '96'::jsonb,
   '0170: the most drift slots world.price_outlook will look ahead (96 × 900 s = 24 hours).'),
  ('outlook_band_z', '1.2816'::jsonb,
   '0170 (COMMAND_DESK D3): the estimate''s band is the drift''s mean ± this × its spread — 1.2816 = 80 % '
   '(8 times in 10 the price lands inside it, if nobody else trades there).')
on conflict (key) do nothing;

-- ── 3. THE LEAVES ─────────────────────────────────────────────────────────────────────────────
create or replace function public.stock_after(p_stock numeric, p_target numeric, p_rate numeric, p_production numeric, p_days numeric)
returns numeric
language sql
immutable
parallel safe
as $$
  -- 0170: DESIGN §G.2's regeneration in closed form over p_days game days — MOVED verbatim out of
  -- public.tick_market_drift's UPDATE (0010, 0123: production × the city's works), which now composes
  -- this; world.price_outlook steps it too. The caller rounds to the column (numeric(12,2)).
  select least(p_target,
               p_target - (p_target - p_stock) * power(1 - p_rate, p_days)
               + p_production * p_days)
$$;

create or replace function public.drift_moments(p_d0 numeric, p_k int)
returns table (k int, mean numeric, sd numeric)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0170: THE DRIFT WALK'S MOMENTS, beside the tick that steps it (public.tick_market_drift, 0010):
--   d ← clamp(θ·d + σ·N(0,1), ±clamp) once a slot, stored at numeric(6,4).
-- mean after k steps: the tick's step with the draw at its mean, k times — exactly what the tick does
-- with σ = 0 (asserted by 0170 against the tick itself); sd after k steps: σ·sqrt((1 − θ^2k) / (1 − θ²)),
-- the AR(1) spread (σ·sqrt(k) at θ = 1). The same three knobs the tick reads. Server-only.
declare
  v_theta numeric := public.wc_num('drift_theta');
  v_sigma numeric := public.wc_num('drift_sigma');
  v_clamp numeric := public.wc_num('drift_clamp');
  v_m     numeric := p_d0;
begin
  for i in 0 .. greatest(coalesce(p_k, 0), 0) loop
    k    := i;
    mean := v_m;
    sd   := case when i = 0 or v_sigma = 0 then 0
                 when v_theta * v_theta = 1 then v_sigma * sqrt(i::numeric)
                 else v_sigma * sqrt((1 - power(v_theta, 2 * i)) / (1 - v_theta * v_theta)) end;
    return next;
    v_m := round(greatest(-v_clamp, least(v_clamp, v_theta * v_m)), 4);   -- the column's scale, numeric(6,4)
  end loop;
end $$;

create or replace function world.price_terms(p_port uuid, out spread numeric, out tax numeric, out bid_factor numeric)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0170: WHAT A QUAY ADDS TO A MID — the port fee (spread), the tax inside the price and the city purse's
-- bid factor, MOVED verbatim out of world.price (0122), which composes this; world.price_outlook reads it
-- once for a whole path. Server-only.
begin
  spread     := world.spread(p_port);
  tax        := case when public.city_treasury_on() then 0 else world.tax_rate(p_port) end;   -- 0122
  bid_factor := public.city_bid_factor(p_port);
end $$;

create or replace function world.price_sides(p_mid numeric, p_spread numeric, p_tax numeric, p_bid_factor numeric,
                                             out ask numeric, out bid numeric)
language sql
immutable
parallel safe
as $$
  -- 0170: a mid's two sides, MOVED verbatim out of world.price (DESIGN G.1; 0122), which composes this.
  select round(p_mid * (1 + p_tax + p_spread / 2), 2),                          -- what you pay   (DESIGN G.1)
         round(p_mid * (1 - p_spread / 2) * (1 - p_tax) * p_bid_factor, 2)      -- what you receive (0122: × the purse's factor)
$$;

revoke all on function public.stock_after(numeric, numeric, numeric, numeric, numeric) from public, anon, authenticated;
revoke all on function public.drift_moments(numeric, int) from public, anon, authenticated;
revoke all on function world.price_terms(uuid) from public, anon, authenticated;
revoke all on function world.price_sides(numeric, numeric, numeric, numeric) from public, anon, authenticated;

-- ── 4. THE RE-CUTS (hunks sliced from the live bodies; each occurs once; each body reverses) ──
create temp table hunks_0170 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0170 (fn, n, old, new) values
('public.tick_market_drift(timestamp with time zone, uuid)', 1,
$h$     set stock = least(pg.stock_target,
                   pg.stock_target - (pg.stock_target - pg.stock) * power(1 - v_rate, v_day - pg.last_regen_day)
                   + pg.production_rate * public.works_factor(pg.port_id, 'production', 'production_per_level')   -- 0123
                     * (v_day - pg.last_regen_day)),$h$,
$h$     set stock = public.stock_after(pg.stock, pg.stock_target, v_rate,   -- 0170: the rule, one leaf (the outlook steps it)
                   pg.production_rate * public.works_factor(pg.port_id, 'production', 'production_per_level'),   -- 0123
                   v_day - pg.last_regen_day),$h$),
('world.price(uuid, uuid)', 1,
$h$  v_tax    numeric;
begin$h$,
$h$  v_tax    numeric;
  v_bidf   numeric;   -- 0170: the purse's factor, from world.price_terms
begin$h$),
('world.price(uuid, uuid)', 2,
$h$  v_spread := world.spread(p_port);
  v_tax    := case when public.city_treasury_on() then 0 else world.tax_rate(p_port) end;   -- 0122
$h$,
$h$  select t.spread, t.tax, t.bid_factor into v_spread, v_tax, v_bidf from world.price_terms(p_port) t;   -- 0170: what the quay adds, one leaf
$h$),
('world.price(uuid, uuid)', 3,
$h$  ask    := round(v_mid * (1 + v_tax + v_spread / 2), 2);   -- what you pay   (DESIGN G.1)
  bid    := round(v_mid * (1 - v_spread / 2) * (1 - v_tax) * public.city_bid_factor(p_port), 2);  -- what you receive (0122: × the purse's factor)
$h$,
$h$  select s.ask, s.bid into ask, bid from world.price_sides(v_mid, v_spread, v_tax, v_bidf) s;   -- 0170: what you pay, what you receive (one leaf)
$h$),
('public.tick_price_snapshot(timestamp with time zone)', 1,
$h$  delete from public.price_history where slot <= v_slot - v_keep;$h$,
$h$  delete from public.price_history where slot <= v_slot - v_keep or slot > v_slot;   -- 0170: or numbered on another slot clock$h$),
('public.client_rpc_entry_points()', 1,
$h$      ('cmd',         'promote_captain',       'text')
$h$,
$h$      ('cmd',         'promote_captain',       'text'),
      -- 0170: a good's estimated price, the next hours, at one city (docs/COMMAND_DESK.md §4, D1).
      ('world',       'price_outlook',         'uuid, uuid, int, text')
$h$);

do $$
declare
  d     record;
  h     record;
  p     record;
  v_def text;
  v_rev text;
  v_n   int := 0;
begin
  for d in select * from defs_before_0170 order by fn loop
    v_def := d.def;
    for h in select * from hunks_0170 where fn = d.fn order by n loop
      if pg_temp.occurs_0170(v_def, h.old) <> 1 then
        raise exception '0170 self-assert FAIL: % hunk % occurs % time(s), not once — the deployed body is not what this file was written against',
          d.fn, h.n, pg_temp.occurs_0170(v_def, h.old);
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    if v_def = d.def then
      raise exception '0170 self-assert FAIL: % has no hunk', d.fn;
    end if;
    execute v_def;
    -- REVERSE TO ORIGINAL: the live body, its hunks undone, is the pre-image byte for byte
    v_rev := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0170 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0170(v_rev, h.new) <> 1 then
        raise exception '0170 self-assert FAIL: % new hunk % is not in the live body once', d.fn, h.n;
      end if;
      v_rev := replace(v_rev, h.new, h.old);
    end loop;
    if v_rev <> d.def then
      raise exception '0170 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef,
           coalesce(pr.proconfig::text, '') as cfg, pr.proowner as owner
      into p from pg_proc pr where pr.oid = d.fn::regprocedure;
    if p.acl <> d.acl or p.vol <> d.vol or p.secdef <> d.secdef or p.cfg <> d.cfg or p.owner <> d.owner then
      raise exception '0170 self-assert FAIL: % changed its ACL, owner, volatility, definer or config', d.fn;
    end if;
    v_n := v_n + 1;
  end loop;
  if v_n <> 4 then
    raise exception '0170 self-assert FAIL: % bodies re-cut, not 4', v_n;
  end if;
  -- THE MOVED TEXT IS THE OLD TEXT: each expression the hunks took out stands once in its leaf, and
  -- nowhere in the body it left
  if pg_temp.occurs_0170(replace(pg_get_functiondef('world.price_terms(uuid)'::regprocedure), E'\r', ''), ':= world.spread(p_port);') <> 1
     or pg_temp.occurs_0170(replace(pg_get_functiondef('world.price_terms(uuid)'::regprocedure), E'\r', ''),
                            ':= case when public.city_treasury_on() then 0 else world.tax_rate(p_port) end;   -- 0122') <> 1
     or pg_temp.occurs_0170(replace(pg_get_functiondef('world.price_terms(uuid)'::regprocedure), E'\r', ''), ':= public.city_bid_factor(p_port);') <> 1
     or pg_temp.occurs_0170(replace(pg_get_functiondef('world.price_sides(numeric, numeric, numeric, numeric)'::regprocedure), E'\r', ''),
                            'round(p_mid * (1 + p_tax + p_spread / 2), 2)') <> 1
     or pg_temp.occurs_0170(replace(pg_get_functiondef('world.price_sides(numeric, numeric, numeric, numeric)'::regprocedure), E'\r', ''),
                            'round(p_mid * (1 - p_spread / 2) * (1 - p_tax) * p_bid_factor, 2)') <> 1
     or strpos(pg_get_functiondef('world.price(uuid, uuid)'::regprocedure), 'world.spread(') > 0
     or strpos(pg_get_functiondef('world.price(uuid, uuid)'::regprocedure), 'city_bid_factor(') > 0
     or strpos(pg_get_functiondef('world.price(uuid, uuid)'::regprocedure), 'round(') > 0 then
    raise exception '0170 self-assert FAIL: world.price''s terms and sides did not move whole into world.price_terms / world.price_sides';
  end if;
  if pg_temp.occurs_0170(replace(pg_get_functiondef('public.stock_after(numeric, numeric, numeric, numeric, numeric)'::regprocedure), E'\r', ''),
                         'p_target - (p_target - p_stock) * power(1 - p_rate, p_days)') <> 1
     or strpos(pg_get_functiondef('public.tick_market_drift(timestamp with time zone, uuid)'::regprocedure), 'power(') > 0 then
    raise exception '0170 self-assert FAIL: the regeneration rule did not move whole into public.stock_after';
  end if;
end $$;

-- ── 5. THE PATH AND THE READ ──────────────────────────────────────────────────────────────────
create or replace function public.price_path(p_port uuid, p_good uuid, p_slots int)
returns table (k int, at timestamptz, stock numeric, drift numeric, sd numeric, mid numeric, lo numeric, hi numeric)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0170: ONE MARKET ROW'S ESTIMATED PATH (docs/COMMAND_DESK.md §4). k = 0 is the row as it stands — the
-- price world.price serves now. k = 1..p_slots are the next drift-slot boundaries (the first from
-- public.next_drift_change_at, the clock's one authority; each after it one drift_slot_seconds later —
-- read once: on prod a call of the authority costs 0.25 ms, 24 of them were most of this read), each a
-- step of public.tick_market_drift:
-- the drift stepped once at its mean (public.drift_moments), the stock regenerated through
-- public.stock_after whenever a game day (world.game_day) passes — no trade assumed — and every other
-- term as world.mid_terms reads it now. mid through world.mid_from_terms, the one price expression;
-- lo / hi the same at the drift's mean ∓ outlook_band_z × sd, clamped as the tick clamps. Server-only.
declare
  t       record;
  r       record;
  v_rate  numeric := public.wc_num('stock_regen_fraction');
  v_z     numeric := public.wc_num('outlook_band_z');
  v_clamp numeric := public.wc_num('drift_clamp');
  v_slot  numeric := public.wc_num('drift_slot_seconds');
  v_prod  numeric;
  v_s     numeric;
  v_day   int;
  v_d     int;
  v_at    timestamptz := now();
begin
  select * into t from world.mid_terms(p_port, p_good);   -- refuses a missing row E_NO_SUCH_GOOD
  select pg.stock, pg.last_regen_day,
         pg.production_rate * public.works_factor(pg.port_id, 'production', 'production_per_level')   -- the tick's production
    into v_s, v_day, v_prod
    from public.port_goods pg where pg.port_id = p_port and pg.good_id = p_good;

  for r in select * from public.drift_moments(t.m_drift, p_slots) order by 1 loop
    if r.k > 0 then
      v_at := case when r.k = 1 then public.next_drift_change_at(v_at) else v_at + make_interval(secs => v_slot) end;
      v_d  := world.game_day(v_at);
      if v_d > v_day then
        v_s   := round(public.stock_after(v_s, t.m_target, v_rate, v_prod, v_d - v_day), 2);   -- the column's scale
        v_day := v_d;
      end if;
    end if;
    k     := r.k;
    at    := v_at;
    stock := v_s;
    drift := r.mean;
    sd    := r.sd;
    mid   := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_target, v_s, r.mean,
                                  t.m_season, t.m_dev, t.m_elasticity, t.m_dev_discount, t.m_band_lo, t.m_band_hi);
    lo    := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_target, v_s,
                                  greatest(-v_clamp, r.mean - v_z * r.sd),
                                  t.m_season, t.m_dev, t.m_elasticity, t.m_dev_discount, t.m_band_lo, t.m_band_hi);
    hi    := world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_target, v_s,
                                  least(v_clamp, r.mean + v_z * r.sd),
                                  t.m_season, t.m_dev, t.m_elasticity, t.m_dev_discount, t.m_band_lo, t.m_band_hi);
    return next;
  end loop;
end $$;

create or replace function world.price_outlook(p_port uuid, p_good uuid, p_slots int default null, p_side text default 'mid')
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0170: A GOOD'S ESTIMATED PRICE AT ONE CITY, THE NEXT HOURS (docs/COMMAND_DESK.md §4, §7.1). The path is
-- public.price_path's; the sides are world.price_sides over world.price_terms (read once — the port fee,
-- the tax and the purse held as they are now, said in `held`). best: the cheapest ask (side ask) or the
-- dearest mid / bid ahead, served only when its gain over now beats the band's half-width at that time —
-- otherwise null: it is as likely to fall as to rise. events: the fairs that fall in the window (a fair
-- moves the port fee; the line does not fold it in). Reads; writes nothing; settles nothing.
declare
  v_side   text := lower(coalesce(p_side, 'mid'));
  v_h      int;
  q        record;
  v_pts    jsonb;
  v_best   jsonb;
  v_events jsonb;
  v_end    timestamptz;
  v_now    timestamptz := now();
begin
  if p_port is null then
    raise exception 'E_NO_SUCH_PORT: an estimate needs a port' using errcode = 'P0001';
  end if;
  if p_good is null then
    raise exception 'E_NO_SUCH_GOOD: an estimate needs a good' using errcode = 'P0001';
  end if;
  if v_side not in ('mid', 'ask', 'bid') then
    raise exception 'world.price_outlook: side must be mid, ask or bid, got %', p_side using errcode = '22023';
  end if;
  v_h := least(greatest(coalesce(p_slots, public.wc_int('outlook_slots')), 1), public.wc_int('outlook_slots_max'));
  select * into q from world.price_terms(p_port);

  with pp as materialized (
    select p.k, p.at,
           case v_side when 'ask' then sm.ask when 'bid' then sm.bid else p.mid end as value,
           case v_side when 'ask' then sl.ask when 'bid' then sl.bid else p.lo end as lo,
           case v_side when 'ask' then sh.ask when 'bid' then sh.bid else p.hi end as hi
      from public.price_path(p_port, p_good, v_h) p
     cross join lateral world.price_sides(p.mid, q.spread, q.tax, q.bid_factor) sm
     cross join lateral world.price_sides(p.lo,  q.spread, q.tax, q.bid_factor) sl
     cross join lateral world.price_sides(p.hi,  q.spread, q.tax, q.bid_factor) sh
  ), z as (
    select pp.value from pp where pp.k = 0
  ), b as (
    select pp.at, pp.value, pp.lo, pp.hi,
           case when v_side = 'ask' then z.value - pp.value else pp.value - z.value end as gain
      from pp cross join z
     where pp.k > 0
     order by case when v_side = 'ask' then pp.value else -pp.value end, pp.k
     limit 1
  )
  select (select jsonb_agg(jsonb_build_object('at', pp.at, 'value', pp.value, 'lo', pp.lo, 'hi', pp.hi) order by pp.k) from pp),
         (select max(pp.at) from pp),
         (select case when b.gain > (b.hi - b.lo) / 2 and b.gain > 0 and z.value > 0
                      then jsonb_build_object('at', b.at, 'value', b.value, 'gain_pct', round(b.gain / z.value * 100, 2)) end
            from b cross join z)
    into v_pts, v_end, v_best;

  select coalesce(jsonb_agg(jsonb_build_object('code', k.code, 'name', k.name, 'effect', k.effect,
                                               'from', ab.starts_at, 'to', ab.ends_at) order by ab.starts_at), '[]'::jsonb)
    into v_events
    from public.active_buffs ab
    join public.buff_kinds k on k.code = ab.kind_code
   where ab.subject_id = p_port and k.subject_kind = 'PORT'
     and ab.ends_at > v_now and ab.starts_at < v_end;

  return jsonb_build_object(
    'port', p_port,
    'good', (select g.code from public.goods g where g.id = p_good),
    'side', v_side,
    'slot_seconds', public.wc_int('drift_slot_seconds'),
    'now', v_now,
    'horizon_slots', v_h,
    'band_z', public.wc_num('outlook_band_z'),
    'assumes', 'If nobody else trades here',
    'held', 'The port fee, the tax and the city''s purse are taken as they are now.',
    'points', v_pts,
    'best', v_best,
    'events', v_events,
    'clock', jsonb_build_object('now', v_now, 'next_change_at', public.next_drift_change_at(v_now)));
end $$;

revoke all on function public.price_path(uuid, uuid, int) from public, anon, authenticated;
revoke all on function world.price_outlook(uuid, uuid, int, text) from public, anon, authenticated;
grant execute on function world.price_outlook(uuid, uuid, int, text) to authenticated;

comment on function world.price_outlook(uuid, uuid, int, text) is
  '0170 (docs/COMMAND_DESK.md §4, D1): a good''s estimated price at one city over the next drift slots — '
  'public.price_path on one side, its 80 % band, the best time when it beats the band, the fairs in the window.';

-- ── 6. THE RECORD, REPAIRED ───────────────────────────────────────────────────────────────────
delete from public.price_history where slot > public.drift_slot_of(now());

-- ── 7. THE PROOFS ─────────────────────────────────────────────────────────────────────────────
-- THE SAMPLE: up to four harbours, captured once; every probe writes every sample row back from here
create temp table sample_ports_0170 on commit drop as
with per_port as (
  select pg.port_id, count(*) filter (where pg.stock < pg.stock_target) as short, count(*) as n
    from public.port_goods pg group by pg.port_id
)
select distinct s.port_id from (
  (select port_id from per_port order by short desc, port_id limit 1)
  union all (select port_id from per_port order by n desc, port_id limit 1)
  union all (select port_id from per_port order by port_id limit 1)
  union all (select port_id from per_port order by port_id desc limit 1)) s;

-- ord 1..9 are bent (prepare_0170): taken from the first harbour's rows whose price stays strictly inside
-- the world's band under every bend (half the target at the upper clamp, twice it at the lower), so a
-- bent row's estimate can move at all
create temp table sample_rows_0170 on commit drop as
with rws as (
  select pg.port_id, pg.good_id, pg.stock, pg.stock_target, pg.drift, pg.production_rate,
         md5(pg.port_id::text || pg.good_id::text) as h,
         pg.port_id = (select min(port_id::text)::uuid from sample_ports_0170) as first_port
    from public.port_goods pg
   where pg.port_id in (select port_id from sample_ports_0170)
)
select r.port_id, r.good_id, r.stock, r.stock_target, r.drift, r.production_rate, r.h,
       row_number() over (order by (r.first_port and coalesce(i.inside, false)) desc, r.port_id, r.good_id) as ord
  from rws r
  left join lateral (
    select world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_target, r.stock_target / 2, 0.2,
                                t.m_season, t.m_dev, t.m_elasticity, t.m_dev_discount, t.m_band_lo, t.m_band_hi) < t.m_band_hi * t.m_base * 0.999
       and world.mid_from_terms(t.m_base, t.m_affinity, t.m_demand, t.m_target, r.stock_target * 2, -0.2,
                                t.m_season, t.m_dev, t.m_elasticity, t.m_dev_discount, t.m_band_lo, t.m_band_hi) > t.m_band_lo * t.m_base * 1.001
       and r.stock_target > 0 as inside
      from world.mid_terms(r.port_id, r.good_id) t
  ) i on r.first_port;

do $$
begin
  if (select count(*) from sample_rows_0170 where ord <= 9) <> 9 then
    raise exception '0170 self-assert FAIL: the sample has fewer than nine rows to bend';
  end if;
end $$;

-- the rows the outlook is compared on: the nine bent rows and an md5 subset of the rest
create temp table outlook_rows_0170 on commit drop as
select port_id, good_id, ord from sample_rows_0170
 where ord <= 9 or h < '0a';

-- the in-run preparation, the same for every run: the sample due at the next slot, read back from the
-- capture, nine rows bent so every arm is taken whatever the world holds. p_sigma0: σ = 0 for the run.
create or replace function pg_temp.prepare_0170(p_sigma0 boolean, p_drift numeric)
returns void
language plpgsql
as $$
declare
  v_slot  bigint := public.drift_slot_of(now());
  v_day   int    := world.game_day(now());
  v_bend  numeric := round(2 * public.wc_num('drift_clamp') / public.wc_num('drift_theta'), 4);
begin
  perform 1 from public.port_goods pg where pg.port_id in (select port_id from sample_ports_0170) order by pg.ctid for update;
  if p_sigma0 then
    update public.world_config set value = to_jsonb(0) where key = 'drift_sigma';
  end if;
  update public.port_goods pg
     set drift_slot      = v_slot,
         last_regen_day  = case when s.ord = 6 then v_day - 3 else v_day end,
         drift           = case when p_drift is not null then p_drift
                                else case s.ord when 1 then least(v_bend, 0.9999) when 2 then greatest(-v_bend, -0.9999)
                                                when 7 then 0 when 8 then -0.15 when 9 then 0 else s.drift end end,
         stock           = case when p_drift is not null then s.stock
                                else case s.ord when 3 then 0 when 4 then s.stock_target * 2
                                                when 5 then round(s.stock_target / 2, 2) when 6 then round(s.stock_target / 2, 2)
                                                when 7 then s.stock_target when 8 then s.stock_target
                                                when 9 then round(s.stock_target / 2, 2) else s.stock end end,
         production_rate = case when p_drift is null and s.ord = 5 then 5 else s.production_rate end
    from pg_temp.sample_rows_0170 s
   where s.port_id = pg.port_id and s.good_id = pg.good_id;
end $$;

-- the sample's rows as the tick left them, one md5
create or replace function pg_temp.sample_digest_0170()
returns text
language sql
as $$
  select md5(string_agg(format('%s/%s/%s/%s/%s/%s', pg.port_id, pg.good_id, pg.stock, pg.drift, pg.drift_slot, pg.last_regen_day), ','
                        order by pg.port_id, pg.good_id))
    from public.port_goods pg where pg.port_id in (select port_id from sample_ports_0170)
$$;

-- (b) + (c): the tick at the next 24 slot boundaries, harbour by harbour, σ = 0. p_old: the pre-image.
-- With the new tick, the outlook is computed first (from the prepared rows) and compared at every step.
create or replace function pg_temp.tick_run_0170(p_old boolean)
returns jsonb
language plpgsql
as $$
declare
  v_at     timestamptz := now();
  v_digest text[] := '{}';
  v_k      int;
  v_port   uuid;
  v_bad    int;
  v_cmp    int := 0;
  v_prices int := 0;
  v_t0     timestamptz;
  v_ms     numeric := 0;
  v_arms   jsonb;
begin
  perform pg_temp.prepare_0170(true, null);
  if not p_old then
    create temp table path_0170 on commit drop as
    select o.port_id, o.good_id, o.ord, p.*
      from outlook_rows_0170 o cross join lateral public.price_path(o.port_id, o.good_id, 24) p;
  end if;
  for v_k in 1 .. 24 loop
    v_at := public.next_drift_change_at(v_at);
    v_t0 := clock_timestamp();
    for v_port in select port_id from sample_ports_0170 order by port_id loop
      if p_old then
        perform pg_temp.tick_market_drift_old_0170(v_at, v_port);
      else
        perform public.tick_market_drift(v_at, v_port);
      end if;
    end loop;
    v_ms := v_ms + extract(epoch from clock_timestamp() - v_t0) * 1000;
    v_digest := v_digest || pg_temp.sample_digest_0170();
    if not p_old then
      select count(*) into v_bad
        from path_0170 p join public.port_goods pg using (port_id, good_id)
       where p.k = v_k and (p.stock <> pg.stock or p.drift <> pg.drift);
      if v_bad > 0 then
        raise exception '0170 self-assert FAIL: the outlook''s step % differs from the tick on % row(s), e.g. %', v_k, v_bad,
          (select format('%s/%s path stock %s drift %s, tick stock %s drift %s', p.port_id, p.good_id, p.stock, p.drift, pg.stock, pg.drift)
             from path_0170 p join public.port_goods pg using (port_id, good_id)
            where p.k = v_k and (p.stock <> pg.stock or p.drift <> pg.drift) limit 1);
      end if;
      v_cmp := v_cmp + (select count(*) from path_0170 where k = v_k);
      if v_k in (1, 8, 24) then
        select count(*) into v_bad
          from path_0170 p cross join lateral world.price(p.port_id, p.good_id) w
         where p.k = v_k and p.mid <> w.mid;
        if v_bad > 0 then
          raise exception '0170 self-assert FAIL: the outlook''s mid at step % differs from world.price on % row(s)', v_k, v_bad;
        end if;
        v_prices := v_prices + (select count(*) from path_0170 where k = v_k);
      end if;
    end if;
  end loop;
  if not p_old then
    -- the arms were taken (read back from the rows the tick left, and from the path)
    v_arms := jsonb_build_object(
      'upper_clamp', exists (select 1 from path_0170 where ord = 1 and k = 1 and drift = public.wc_num('drift_clamp')),
      'lower_clamp', exists (select 1 from path_0170 where ord = 2 and k = 1 and drift = -public.wc_num('drift_clamp')),
      'from_zero',   exists (select 1 from path_0170 where ord = 3 and k = 24 and stock > 0),
      'pulled_down', exists (select 1 from path_0170 p join sample_rows_0170 s using (port_id, good_id)
                              where p.ord = 4 and p.k = 24 and p.stock = s.stock_target),
      'production',  exists (select 1 from path_0170 a join path_0170 b using (port_id, good_id)
                              where a.ord = 5 and b.ord = 5 and a.k = 0 and b.k = 24 and b.stock > a.stock),
      'regen_days',  (select count(distinct stock) from path_0170 where ord = 9),
      'flat',        (select count(distinct mid) from path_0170 where ord = 7));
    if not (v_arms->>'upper_clamp')::boolean or not (v_arms->>'lower_clamp')::boolean or not (v_arms->>'from_zero')::boolean
       or not (v_arms->>'pulled_down')::boolean or not (v_arms->>'production')::boolean or (v_arms->>'regen_days')::int < 3 or (v_arms->>'flat')::int <> 1 then
      raise exception '0170 self-assert FAIL: the bent rows did not take their arms: %', v_arms;
    end if;
  end if;
  return jsonb_build_object('digest', to_jsonb(v_digest), 'compared', v_cmp, 'priced', v_prices,
                            'ms', round(v_ms), 'arms', coalesce(v_arms, '{}'::jsonb));
end $$;

-- (d): the band. Seeded; σ as live; every sample row at drift p_d0; the drift collected at k = 1, 4, 24
create or replace function pg_temp.band_run_0170(p_d0 numeric)
returns jsonb
language plpgsql
as $$
declare
  v_at  timestamptz := now();
  v_k   int;
  v_p   uuid;
  v_out jsonb := '{}'::jsonb;
  m     record;
  v_z   numeric := public.wc_num('outlook_band_z');
begin
  perform pg_temp.prepare_0170(false, p_d0);
  perform setseed(0.170);
  for v_k in 1 .. 24 loop
    v_at := public.next_drift_change_at(v_at);
    for v_p in select port_id from sample_ports_0170 order by port_id loop
      perform public.tick_market_drift(v_at, v_p);
    end loop;
    if v_k in (1, 4, 24) then
      select * into m from public.drift_moments(p_d0, v_k) where k = v_k;
      v_out := v_out || jsonb_build_object(v_k::text, (
        select jsonb_build_object('n', count(*), 'obs_mean', avg(pg.drift), 'mean', m.mean, 'sd', m.sd,
                                  'inside', count(*) filter (where pg.drift between m.mean - v_z * m.sd and m.mean + v_z * m.sd))
          from public.port_goods pg where pg.port_id in (select port_id from sample_ports_0170)));
    end if;
  end loop;
  return v_out;
end $$;

do $$
declare
  v_old   jsonb;
  v_new   jsonb;
  v_band  jsonb;
  v_k     text;
  v_n     numeric;
  v_p     numeric := erf(public.wc_num('outlook_band_z')::double precision / sqrt(2::double precision))::numeric;
  v_bad   int;
  v_rows  int := (select count(*) from sample_rows_0170);
  v_ports int := (select count(*) from sample_ports_0170);
  v_t0    timestamptz;
  v_ms_o  numeric;
  v_ms_n  numeric;
  v_parity int;
  v_out   jsonb;
  v_flat  jsonb;
  v_low   jsonb;
  v_short jsonb;
  v_state text;
  v_msg   text;
  v_notes text := '';
  v_fn    record;
begin
  if v_ports < 2 or v_rows < 20 then
    raise exception '0170 self-assert FAIL: the sample is % harbour(s) / % row(s)', v_ports, v_rows;
  end if;

  -- (a) world.price old vs new: every sample row and two md5-chosen goods of every harbour
  create temp table price_rows_0170 on commit drop as
  select port_id, good_id from sample_rows_0170
  union
  select port_id, good_id from (
    select pg.port_id, pg.good_id, row_number() over (partition by pg.port_id order by md5(pg.port_id::text || pg.good_id::text)) as rn
      from public.port_goods pg) x where rn <= 2;
  v_t0 := clock_timestamp();
  perform count(o.*) from price_rows_0170 r cross join lateral pg_temp.price_old_0170(r.port_id, r.good_id) o;
  v_ms_o := extract(epoch from clock_timestamp() - v_t0) * 1000;
  v_t0 := clock_timestamp();
  perform count(w.*) from price_rows_0170 r cross join lateral world.price(r.port_id, r.good_id) w;
  v_ms_n := extract(epoch from clock_timestamp() - v_t0) * 1000;
  select count(*) into v_bad
    from price_rows_0170 r
   cross join lateral pg_temp.price_old_0170(r.port_id, r.good_id) o
   cross join lateral world.price(r.port_id, r.good_id) w
   where (o.mid, o.ask, o.bid, o.spread) is distinct from (w.mid, w.ask, w.bid, w.spread);
  if v_bad > 0 then
    raise exception '0170 self-assert FAIL: world.price answers differently on % of % row(s) now that it composes its leaves',
      v_bad, (select count(*) from price_rows_0170);
  end if;
  v_notes := v_notes || format('world.price old %s ms / new %s ms over %s rows; ', round(v_ms_o), round(v_ms_n), (select count(*) from price_rows_0170));

  -- (a) k = 0 of the outlook is world.price, on every side, to the cent (the outlook rows × 3 sides)
  select count(*) into v_parity
    from outlook_rows_0170 r
   cross join lateral world.price(r.port_id, r.good_id) w
   cross join lateral (values ('mid'), ('ask'), ('bid')) s(side)
   cross join lateral (select world.price_outlook(r.port_id, r.good_id, 4, s.side) as j) o
   where ((o.j->'points'->0->>'value')::numeric, (o.j->'points'->0->>'lo')::numeric, (o.j->'points'->0->>'hi')::numeric)
         is distinct from (case s.side when 'ask' then w.ask when 'bid' then w.bid else w.mid end,
                           case s.side when 'ask' then w.ask when 'bid' then w.bid else w.mid end,
                           case s.side when 'ask' then w.ask when 'bid' then w.bid else w.mid end)
      or jsonb_array_length(o.j->'points') <> 5;
  if v_parity > 0 then
    raise exception '0170 self-assert FAIL: the outlook''s now differs from world.price on % (row, side) pair(s)', v_parity;
  end if;

  -- (b) + (c): old vs new tick, and the outlook vs the new tick — each run rolled back
  begin
    v_old := pg_temp.tick_run_0170(true);
    raise exception using errcode = 'ZX170', message = v_old::text;
  exception when sqlstate 'ZX170' then
    v_old := sqlerrm::jsonb;
  end;
  begin
    v_new := pg_temp.tick_run_0170(false);
    raise exception using errcode = 'ZX170', message = v_new::text;
  exception when sqlstate 'ZX170' then
    v_new := sqlerrm::jsonb;
  end;
  if v_old->'digest' is distinct from v_new->'digest' or jsonb_array_length(v_new->'digest') <> 24 then
    raise exception '0170 self-assert FAIL: the tick moved the sample differently now that it composes public.stock_after';
  end if;
  if (v_new->>'compared')::int < 24 * 9 or (v_new->>'priced')::int < 3 * 9 then
    raise exception '0170 self-assert FAIL: the outlook was compared on % (row, step) pair(s) and priced on %, too few',
      v_new->>'compared', v_new->>'priced';
  end if;
  v_notes := v_notes || format('tick old %s ms / new %s ms for 24 steps × %s harbours; ', v_old->>'ms', v_new->>'ms', v_ports);

  -- (c) best: null on the flat row, later on the low-drift row (bid) and on the short row (ask) — rolled back
  begin
    perform pg_temp.prepare_0170(false, null);
    select world.price_outlook(port_id, good_id, 24, 'mid') into v_flat from sample_rows_0170 where ord = 7;
    select world.price_outlook(port_id, good_id, 24, 'bid') into v_low from sample_rows_0170 where ord = 8;
    select world.price_outlook(port_id, good_id, 24, 'ask') into v_short from sample_rows_0170 where ord = 9;
    raise exception using errcode = 'ZX170', message = jsonb_build_object('flat', v_flat, 'low', v_low, 'short', v_short)::text;
  exception when sqlstate 'ZX170' then
    v_out := sqlerrm::jsonb;
  end;
  if v_out->'flat'->'best' <> 'null'::jsonb
     or v_out->'low'->'best' = 'null'::jsonb or (v_out->'low'->'best'->>'gain_pct')::numeric <= 0
     or (v_out->'low'->'best'->>'value')::numeric <= (v_out->'low'->'points'->0->>'value')::numeric
     or v_out->'short'->'best' = 'null'::jsonb
     or (v_out->'short'->'best'->>'value')::numeric >= (v_out->'short'->'points'->0->>'value')::numeric
     or jsonb_array_length(v_out->'low'->'points') <> 25 then
    raise exception '0170 self-assert FAIL: the best time is wrong: flat %, low drift %, short stock %',
      v_out->'flat'->'best', v_out->'low'->'best', v_out->'short'->'best';
  end if;
  -- and the band widens step by step on the low-drift row: its stock stays at the target, so the width in
  -- coins follows the drift's spread alone (to the cent the sides are rounded to; no clamp binds at −0.15)
  if exists (select 1 from jsonb_array_elements(v_out->'low'->'points') with ordinality a(e, i)
               join jsonb_array_elements(v_out->'low'->'points') with ordinality b(e, j) on j = i + 1
              where (b.e->>'hi')::numeric - (b.e->>'lo')::numeric < (a.e->>'hi')::numeric - (a.e->>'lo')::numeric - 0.02)
     or (select ((e->>'hi')::numeric - (e->>'lo')::numeric) from jsonb_array_elements(v_out->'low'->'points') with ordinality a(e, i) where i = 25)
        <= 0 then
    raise exception '0170 self-assert FAIL: the band does not widen ahead on the low-drift row';
  end if;

  -- (d) the band: seeded draws, σ as live
  begin
    v_band := pg_temp.band_run_0170(0.12);
    raise exception using errcode = 'ZX170', message = v_band::text;
  exception when sqlstate 'ZX170' then
    v_band := sqlerrm::jsonb;
  end;
  perform setseed(((extract(microseconds from clock_timestamp())::bigint % 1999999) - 999999) / 1000000.0);
  for v_k in select k from jsonb_object_keys(v_band) k order by k::int loop
    v_n := (v_band->v_k->>'n')::numeric;
    if v_n < 1000
       or abs((v_band->v_k->>'obs_mean')::numeric - (v_band->v_k->>'mean')::numeric)
          > 4 * (v_band->v_k->>'sd')::numeric / sqrt(v_n) + 0.0001
       or abs((v_band->v_k->>'inside')::numeric / v_n - v_p) > 4 * sqrt(v_p * (1 - v_p) / v_n) + 1 / v_n then
      raise exception '0170 self-assert FAIL: the band at step % is not the walk''s: %, expected share inside %', v_k, v_band->v_k, round(v_p, 4);
    end if;
    v_notes := v_notes || format('band k=%s: mean %s vs %s, inside %s %% of %s (expected %s %%); ', v_k,
      round((v_band->v_k->>'obs_mean')::numeric, 4), v_band->v_k->>'mean',
      round(100 * (v_band->v_k->>'inside')::numeric / v_n, 1), v_n, round(100 * v_p, 1));
  end loop;
  if (select count(*) from jsonb_object_keys(v_band)) <> 3 then
    raise exception '0170 self-assert FAIL: the band was read at % step(s), not 3', (select count(*) from jsonb_object_keys(v_band));
  end if;

  -- (e) the record: nothing past the present slot; and the snapshot prunes a planted one (rolled back)
  if exists (select 1 from public.price_history where slot > public.drift_slot_of(now())) then
    raise exception '0170 self-assert FAIL: price_history still holds rows past the present slot';
  end if;
  begin
    insert into public.price_history (port_id, good_id, slot, at, mid, stock)
    select port_id, good_id, public.drift_slot_of(now()) + 1000, now(), 1, 1 from sample_rows_0170 where ord = 1;
    perform public.tick_price_snapshot(now());
    raise exception using errcode = 'ZX170',
      message = (select count(*) from public.price_history where slot > public.drift_slot_of(now()))::text;
  exception when sqlstate 'ZX170' then
    v_msg := sqlerrm;
  end;
  if v_msg <> '0' then
    raise exception '0170 self-assert FAIL: the snapshot left % planted row(s) past the present slot', v_msg;
  end if;

  -- (f) refusals
  begin
    perform world.price_outlook(null, (select good_id from sample_rows_0170 where ord = 1));
    v_state := 'none';
  exception when others then
    v_state := sqlerrm;
  end;
  if v_state not like 'E_NO_SUCH_PORT:%' then
    raise exception '0170 self-assert FAIL: a null port was not refused E_NO_SUCH_PORT (%)', v_state;
  end if;
  begin
    perform world.price_outlook((select port_id from sample_rows_0170 where ord = 1), gen_random_uuid());
    v_state := 'none';
  exception when others then
    v_state := sqlerrm;
  end;
  if v_state not like 'E_NO_SUCH_GOOD:%' then
    raise exception '0170 self-assert FAIL: a good with no market row was not refused E_NO_SUCH_GOOD (%)', v_state;
  end if;
  begin
    perform world.price_outlook((select port_id from sample_rows_0170 where ord = 1), (select good_id from sample_rows_0170 where ord = 1), 4, 'sell');
    v_state := 'none';
  exception when sqlstate '22023' then
    v_state := 'refused';
  end;
  if v_state <> 'refused' then
    raise exception '0170 self-assert FAIL: an unknown side was not refused 22023';
  end if;
  if (world.price_outlook((select port_id from sample_rows_0170 where ord = 1), (select good_id from sample_rows_0170 where ord = 1), 100000)->>'horizon_slots')::int
       <> public.wc_int('outlook_slots_max')
     or (world.price_outlook((select port_id from sample_rows_0170 where ord = 1), (select good_id from sample_rows_0170 where ord = 1))->>'horizon_slots')::int
       <> public.wc_int('outlook_slots') then
    raise exception '0170 self-assert FAIL: the window is not the knobs'' (default outlook_slots, capped at outlook_slots_max)';
  end if;

  -- TIMING (reported, not gated): the read, 3 sides × the outlook rows, at the default window
  v_t0 := clock_timestamp();
  perform sum(length(o.j::text)) from outlook_rows_0170 r cross join (values ('mid'), ('ask'), ('bid')) s(side)
    cross join lateral (select world.price_outlook(r.port_id, r.good_id, null, s.side) as j) o;
  v_notes := v_notes || format('world.price_outlook %s ms a call (mean of %s); ',
    round(extract(epoch from clock_timestamp() - v_t0) * 1000 / (3 * (select count(*) from outlook_rows_0170)), 2),
    3 * (select count(*) from outlook_rows_0170));

  -- THE RECEIPT: the registry +1 (authenticated may, anon may not), the leaves server-only, the walls
  if (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from before_0170) + 1
     or not exists (select 1 from public.client_rpc_entry_points() where fn = 'world.price_outlook(uuid, uuid, int, text)'::regprocedure)
     or not has_function_privilege('authenticated', 'world.price_outlook(uuid, uuid, int, text)', 'execute')
     or has_function_privilege('anon', 'world.price_outlook(uuid, uuid, int, text)', 'execute')
     or exists (select 1 from unnest(array['public.stock_after(numeric, numeric, numeric, numeric, numeric)', 'public.drift_moments(numeric, integer)',
                                           'world.price_terms(uuid)', 'world.price_sides(numeric, numeric, numeric, numeric)',
                                           'public.price_path(uuid, uuid, integer)']) f(fn),
                       unnest(array['anon', 'authenticated']) rl(role)
                 where has_function_privilege(rl.role, f.fn, 'execute'))
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0170 self-assert FAIL: the registry, the grant wall or the read wall moved, or a client can reach a leaf';
  end if;
  -- the read is cheap by construction: it settles nothing and steps no clock
  for v_fn in select fn from unnest(array['world.price_outlook(uuid, uuid, int, text)', 'public.price_path(uuid, uuid, integer)']) fn loop
    if pg_get_functiondef(v_fn.fn::regprocedure) ~ '(tick_[a-z_]+|settle)\s*\(' then   -- a call, not a word in a comment
      raise exception '0170 self-assert FAIL: % steps a clock or settles a fleet', v_fn.fn;
    end if;
  end loop;
  if (select count(*) from public.world_config where key in ('outlook_slots', 'outlook_slots_max', 'outlook_band_z')) <> 3 then
    raise exception '0170 self-assert FAIL: the three outlook knobs are not all present';
  end if;
  if (select count(*) from public.price_history where slot <= public.drift_slot_of(now())) < (select kept from before_0170) then
    raise exception '0170 self-assert FAIL: the repair deleted a row of the present clock';
  end if;

  raise notice '0170 self-assert ok: A PRICE SAYS WHERE IT IS GOING. LEAVES: public.stock_after (the tick composes it), public.drift_moments, world.price_terms + world.price_sides (world.price composes them), public.price_path; READ: world.price_outlook (registered; authenticated only). PROOF: world.price old = new on % rows; the outlook''s now = world.price on % rows × mid / ask / bid; the tick old = new over 24 steps × % harbours (% rows, σ = 0); the outlook = the tick on % (row, step) pairs and = world.price on %; arms %; best: none on a flat row, later on a low drift (bid +% %%) and a short stock (ask); the band (seeded, σ live): see below; the record: % stale row(s) deleted, none past the present slot, a planted one pruned by the snapshot; 4 bodies reverse to their pre-images, ACL / owner / volatility / definer / config unmoved. NOTES: %',
    (select count(*) from price_rows_0170), (select count(*) from outlook_rows_0170), v_ports, v_rows,
    v_new->>'compared', v_new->>'priced', v_new->'arms', v_out->'low'->'best'->>'gain_pct',
    (select stale from before_0170), v_notes;
end $$;
