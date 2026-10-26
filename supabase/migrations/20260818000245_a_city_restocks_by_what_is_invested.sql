-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0245 — A CITY RESTOCKS BY WHAT IS INVESTED
--        (slice E5 of docs/CLOSED_ECONOMY.md §3, §8. DARK: this file changes no price and no stock. Lit later by one
--         `update public.world_config set value = 'true' where key = 'restock_by_investment'`, with the deploy note.)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER (2026-10-26) ──────────────────────────────────────────────────────────────────────
--   "i want city to restock trade goods based on their invested amount."   And: "the settings set by should be once
--   per day."
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
--   COLUMNS  port_treasury.restock_rate numeric(6,4) null, port_treasury.restock_day int null — THE DAY'S RATE, set
--            once a game-day by public.restock_day(), read by public.restock_rate(). (port_treasury.invested is 0228's.)
--   KNOBS    restock_by_investment false (THE dark switch of this slice), restock_r0 0.03, restock_r1 0.30,
--            restock_i_half 500000, invested_half_life_hours 72.
--   NEW, server-only:
--     public.restock_formula(I)   r0 + (r1 − r0) × I / (I + I½), rounded to 4 places.         (§3's one formula)
--     public.restock_lit()        restock_by_investment AND economy_closed().                 (THE one gate)
--     public.restock_rate(port)   THE one reader. Not lit: stock_regen_fraction (byte parity). Lit: the port's stored
--                                 day rate; until the day's job has set it (a new harbour, the first minutes after
--                                 lighting) stock_regen_fraction — two acceptable outcomes, never a silent zero.
--     public.invested_decay()     I ← round(I × 0.5^(1/invested_half_life_hours)) on every row where I is not null.
--     public.restock_day(day)     lit only: once per game-day per harbour, restock_rate := restock_formula(I or 0).
--   HUNKS (re-cut against the LIVE bodies, prod head 0244):
--     public.tick_city           (1) the roll calls invested_decay() first; (2) the roll's purse update adds this hour's
--                                SHARE + DONATION to `invested` (where it is tracked — null stays null);
--                                (3) a step 3b calls restock_day(today), errors in the receipt's error map.
--     public.tick_market_drift   the regen reads public.restock_rate(port) in place of the knob.
--     public.price_path          the outlook reads public.restock_rate(port) in place of the knob.
--
-- ── DARK (what the main session sees after deploy) ──────────────────────────────────────────────
--   restock_rate = stock_regen_fraction for every harbour; the regen of a probe harbour is byte-identical to the
--   pre-image's; price_path likewise. `invested` KEEPS ROLLING where E7's switch seeded it (prod: all 246 rows) —
--   nothing reads it while dark, and it must be current the day the knob is turned. This is the one visible change.
--
-- ── DEVIATION FROM THE DESIGN (docs/CLOSED_ECONOMY.md §3), stated ────────────────────────────────
--   * The doc says E5 "goes live when it deploys because the economy is already closed". The economy IS closed on prod
--     now (06:52 UTC 10-26), so a gate on economy_closed() alone would have lit this on deploy. The knob
--     restock_by_investment is the dark switch; restock_lit() = knob AND economy_closed() (reopen the economy and the
--     rate falls back to stock_regen_fraction).
--   * The owner's "max stock moves with investment too" (depth_mult, §3) is NOT in this file: stock_target is read by
--     mid_terms, price_path, the glut and the quote path, and re-cutting them is its own slice (E5b). The slice table's
--     E5 row does not list it.
--
-- ── WHAT IT SELF-ASSERTS (probe rows only; every probe a rolled-back sub-transaction, asserted) ───
--   (a) hunks reverse to the pre-images; ACL / volatility / definer / config unmoved; new functions server-only;
--       registry unchanged; walls 0.
--   (b) DARK, BYTE FOR BYTE: Funchal's rows regenerated 30 days on (tick_market_drift) and its price_path for three
--       goods — run BEFORE the re-cut and AFTER, from the same state (Funchal's rows locked): stock, glut, day, outlook
--       equal. restock_rate = the knob on every harbour.
--   (c) LIT, THE MATHS: I = 0 → 0.03, 500,000 → 0.165, 10^15 → 0.30 (the cap); the decay step is round(I × 0.5^(1/72))
--       exactly on a probe port (1,000,000 → 990,419); restock_day sets the day's rate once (a second call changes
--       nothing); the regen then follows the stored rate row for row; reopening the economy returns the knob's rate.
--   (d) after: knob false, no row carries a stored rate, the count of tracked `invested` rows is what it was.
--   No growing table is counted; tick_city is NOT run (it rolls the real flows and builds with real purses): its three
--   hunks are asserted to occur once and to reverse, and the roll was run end to end on the local chain — see the
--   dev-log. Nothing is DELETEd. No `set role`.
-- ROLLBACK (forward): restore the OLD hunks below verbatim; drop the five functions, the two columns, the five knobs.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '5min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('public.economy_closed()') is null
     or not exists (select 1 from information_schema.columns
                     where table_schema = 'public' and table_name = 'port_treasury' and column_name = 'invested') then
    raise exception '0245 refuses: E1 (0228) is not in this world';
  end if;
  if to_regprocedure('public.restock_rate(uuid)') is not null then
    raise exception '0245 refuses: restock_rate already exists';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0245(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 0. THE PRE-IMAGES (LF-normalised) ───────────────────────────────────────────────────────────
create temp table defs_before_0245 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('public.tick_city(timestamp with time zone)'),
               ('public.tick_market_drift(timestamp with time zone,uuid)'),
               ('public.price_path(uuid,uuid,integer)')) f(fn);

create temp table before_0245 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from public.port_treasury t where t.invested is not null) as invested_rows,
       (select p.id from public.ports p where p.code = 'FNC' and p.kind = 'HARBOUR') as fnc,
       (select p.id from public.ports p where p.code = 'AMS' and p.kind = 'HARBOUR') as ams,
       (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR') as lis,
       (select p.id from public.ports p where p.code = 'OPO' and p.kind = 'HARBOUR') as opo;

-- Funchal's market rows are held still for this transaction, so the two dark runs start from one state.
do $$
begin
  if exists (select 1 from before_0245 b where b.fnc is null or b.ams is null or b.lis is null or b.opo is null) then
    raise exception '0245 self-assert FAIL: no Funchal, Amsterdam, Lisbon or Porto';
  end if;
  perform 1 from public.port_goods pg, before_0245 b where pg.port_id = b.fnc for update;
end $$;

-- ── 1. THE PROBE: Funchal's outlook, then regenerated 30 days on; rolled back; answers what it saw ──
create or replace function pg_temp.dark_0245()
returns jsonb
language plpgsql
as $$
declare
  b       record;
  v_paths jsonb;
  v_res   jsonb;
begin
  select * into b from before_0245;
  begin
    select jsonb_agg(jsonb_build_array(x.good, x.k, x.stock, x.mid, x.lo, x.hi) order by x.good, x.k)
      into v_paths
      from (select g.code as good, pp.k, pp.stock, pp.mid, pp.lo, pp.hi
              from (select pg.good_id from public.port_goods pg where pg.port_id = b.fnc order by pg.good_id limit 3) q
              join public.goods g on g.id = q.good_id
             cross join lateral public.price_path(b.fnc, q.good_id, 6) pp) x;
    perform public.tick_market_drift(now() + interval '30 days', b.fnc);
    select jsonb_build_object('paths', v_paths,
             'regen', (select jsonb_agg(jsonb_build_array(g.code, pg.stock, pg.glut, pg.last_regen_day) order by g.code)
                         from public.port_goods pg join public.goods g on g.id = pg.good_id where pg.port_id = b.fnc))
      into v_res;
    raise exception using errcode = 'ZY245', message = v_res::text;
  exception when sqlstate 'ZY245' then
    return sqlerrm::jsonb;
  end;
end $$;

create temp table dark_old_0245 on commit drop as select pg_temp.dark_0245() as seen;

-- ── 2. THE COLUMNS AND THE KNOBS ────────────────────────────────────────────────────────────────
alter table public.port_treasury
  add column restock_rate numeric(6,4) check (restock_rate between 0 and 1),
  add column restock_day  int;
comment on column public.port_treasury.restock_rate is
  '0245 (docs/CLOSED_ECONOMY.md §3): the harbour''s restock rate for ONE game-day (restock_day), set once a day by '
  'public.restock_day() from `invested`; read only through public.restock_rate(). Null until lit.';
comment on column public.port_treasury.restock_day is
  '0245: the game-day restock_rate was last set for. One writer: public.restock_day().';

insert into public.world_config (key, value, description) values
  ('restock_by_investment', 'false'::jsonb,
   '0245 (docs/CLOSED_ECONOMY.md §3): false = every harbour restocks at stock_regen_fraction, byte for byte. true (with economy_closed) = at the rate its investment earns, set once a game-day. Read only through public.restock_lit().'),
  ('restock_r0', '0.03'::jsonb, '0245 (§3): the restock rate of a city nobody has invested in (per game-day). Never zero.'),
  ('restock_r1', '0.30'::jsonb, '0245 (§3): the cap of the restock rate (per game-day).'),
  ('restock_i_half', '500000'::jsonb, '0245 (§3): the investment at which the rate is half way between r0 and r1.'),
  ('invested_half_life_hours', '72'::jsonb, '0245 (§3): the half-life of `invested`, in hourly tick_city rolls (72 = 3 real days).');

-- ── 3. THE FIVE FUNCTIONS ───────────────────────────────────────────────────────────────────────
create function public.restock_formula(p_invested bigint)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0245 (§3): rate = r0 + (r1 − r0) × I / (I + I½), at the column's scale. I = 0 → r0; I → ∞ → r1.
  select round(public.wc_num('restock_r0')
               + (public.wc_num('restock_r1') - public.wc_num('restock_r0'))
                 * greatest(0, coalesce(p_invested, 0))::numeric
                 / (greatest(0, coalesce(p_invested, 0))::numeric + public.wc_num('restock_i_half')), 4)
$$;

create function public.restock_lit()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0245: THE ONE gate of this slice: its own knob AND the closed economy.
  select coalesce((public.wc('restock_by_investment'))::boolean, false) and public.economy_closed()
$$;

create function public.restock_rate(p_port uuid)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0245: THE ONE reader of a harbour's restock rate (tick_market_drift and price_path). Not lit: stock_regen_fraction,
  -- byte for byte. Lit: the day's stored rate; a harbour the day's job has not reached yet (new, or just lit) restocks at
  -- stock_regen_fraction until it does — one of two acceptable rates, never zero.
  select case when public.restock_lit()
              then coalesce((select t.restock_rate from public.port_treasury t where t.port_id = p_port),
                            public.wc_num('stock_regen_fraction'))
              else public.wc_num('stock_regen_fraction') end
$$;

create function public.invested_decay()
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_n int;
begin
  -- 0245: the decay half of I ← round(I × 0.5^(1/72)) + this hour's SHARE + DONATION (the second half is tick_city's
  -- roll). Only tracked rows (null = not seeded yet). Called by tick_city, before its roll.
  update public.port_treasury t
     set invested = round(t.invested * power(0.5, 1.0 / public.wc_num('invested_half_life_hours')))::bigint
   where t.invested is not null;
  get diagnostics v_n = row_count;
  return v_n;
end $$;

create function public.restock_day(p_day int)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_n int := 0;
begin
  -- 0245 (§3, owner: "once per day"): lit only. Every harbour whose rate is not this game-day's gets
  -- restock_formula(I) (an untracked harbour: I = 0, the slowest rate) and the day. Called by tick_city (step 3b).
  if not public.restock_lit() then
    return 0;
  end if;
  update public.port_treasury t
     set restock_rate = public.restock_formula(t.invested), restock_day = p_day
    from public.ports p
   where p.id = t.port_id and p.kind = 'HARBOUR' and t.restock_day is distinct from p_day;
  get diagnostics v_n = row_count;
  return v_n;
end $$;

comment on function public.restock_formula(bigint) is '0245 (§3): the one formula of the restock rate. Server-only.';
comment on function public.restock_lit() is '0245: restock_by_investment AND economy_closed(). Server-only.';
comment on function public.restock_rate(uuid) is '0245 (§3): THE one reader of a harbour''s restock rate. Server-only.';
comment on function public.invested_decay() is '0245 (§3): one hourly decay step of port_treasury.invested. Called by tick_city.';
comment on function public.restock_day(int) is '0245 (§3): sets each harbour''s restock rate once per game-day. Called by tick_city.';
revoke all on function public.restock_formula(bigint) from public, anon, authenticated;
revoke all on function public.restock_lit() from public, anon, authenticated;
revoke all on function public.restock_rate(uuid) from public, anon, authenticated;
revoke all on function public.invested_decay() from public, anon, authenticated;
revoke all on function public.restock_day(int) from public, anon, authenticated;

-- ── 4. THE RE-CUTS (hunks sliced from the live bodies; each occurs once; each body reverses) ──────
create temp table hunks_0245 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0245 (fn, n, old, new) values
('public.tick_city(timestamp with time zone)', 1,
$h$  perform set_config('byeharu.treasury_roll', 'on', true);
  with f as (
$h$,
$h$  perform set_config('byeharu.treasury_roll', 'on', true);
  perform public.invested_decay();   -- 0245 (E5): the decay half of `invested`; the roll below adds the hour's SHARE + DONATION
  with f as (
$h$),
('public.tick_city(timestamp with time zone)', 2,
$h$       set ducats = t.ducats + s.net, rolled_at = p_now, updated_at = now()
      from (select f.port_id, sum(f.ducats) as net from f group by 1) s
$h$,
$h$       set ducats = t.ducats + s.net, rolled_at = p_now, updated_at = now(),
           invested = case when t.invested is null then null else greatest(0, t.invested + s.inflow) end   -- 0245 (E5)
      from (select f.port_id, sum(f.ducats) as net,
                   coalesce(sum(f.ducats) filter (where f.kind in ('SHARE', 'DONATION')), 0) as inflow
              from f group by 1) s
$h$),
('public.tick_city(timestamp with time zone)', 3,
$h$  -- 4. BUILD (0123, lit): each harbour subscribes its lowest work from its surplus; the money goes
$h$,
$h$  -- 3b. RESTOCK (0245, E5; lit by restock_by_investment): once per game-day each harbour's restock rate is set from
  --     what is invested (public.restock_day). Dark it writes nothing.
  begin
    perform public.restock_day(v_today);
  exception when others then
    v_err := v_err || jsonb_build_object('restock', sqlerrm);
  end;

  -- 4. BUILD (0123, lit): each harbour subscribes its lowest work from its surplus; the money goes
$h$),
('public.tick_market_drift(timestamp with time zone,uuid)', 1,
$h$  v_rate   numeric := public.wc_num('stock_regen_fraction');
$h$,
$h$  -- 0245 (E5): the regen rate is read per harbour, public.restock_rate(port) (dark: stock_regen_fraction)
$h$),
('public.tick_market_drift(timestamp with time zone,uuid)', 2,
$h$     set stock = public.stock_after(pg.stock, pg.stock_target, v_rate,   -- 0170: the rule, one leaf (the outlook steps it)
$h$,
$h$     set stock = public.stock_after(pg.stock, pg.stock_target, public.restock_rate(pg.port_id),   -- 0170: the rule, one leaf (the outlook steps it); 0245: at the harbour's own rate
$h$),
('public.price_path(uuid,uuid,integer)', 1,
$h$  v_rate  numeric := public.wc_num('stock_regen_fraction');
$h$,
$h$  v_rate  numeric := public.restock_rate(p_port);   -- 0245 (E5): the harbour's own rate (dark: the knob)
$h$);

create or replace function pg_temp.recut_0245(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := (select def from defs_before_0245 where fn = p_fn);
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0245 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0245(v_def, h.old);
    if v_n <> 1 then
      raise exception '0245 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, h.fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0245(fn) from defs_before_0245 order by fn;

-- ── 5. THE SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
do $$
declare
  b       record;
  v_d record; v_h record; v_pp record; v_def text;
  v_old   jsonb;
  v_new   jsonb;
  v_exp   bigint;
  v_day   int := 7777777;       -- a game-day no clock has reached: nothing real carries it
  v_rate  numeric;
  v_bad   int;
  v_far   timestamptz := now() + interval '30 days';
begin
  select * into b from before_0245;

  -- (a) THE RE-CUTS reverse; ACL / volatility / definer / config unmoved; the five new functions server-only
  for v_d in select * from defs_before_0245 loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0245 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0245(v_def, v_h.new) <> 1 then
        raise exception '0245 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0245 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
      into v_pp from pg_proc p where p.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0245 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;
  if exists (select 1 from (values ('public.restock_formula(bigint)'), ('public.restock_lit()'), ('public.restock_rate(uuid)'),
                                   ('public.invested_decay()'), ('public.restock_day(int)')) f(fn)
              where has_function_privilege('authenticated', f.fn, 'execute') or has_function_privilege('anon', f.fn, 'execute')) then
    raise exception '0245 self-assert FAIL: a client role can execute one of the five new functions';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> b.entry_points then
    raise exception '0245 self-assert FAIL: the registry moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0245 self-assert FAIL: a wall moved';
  end if;

  -- (b) DARK, BYTE FOR BYTE
  if public.restock_lit() then
    raise exception '0245 self-assert FAIL: restock_by_investment is not dark';
  end if;
  select count(*) into v_bad from public.ports p
   where p.kind = 'HARBOUR' and public.restock_rate(p.id) is distinct from public.wc_num('stock_regen_fraction');
  if v_bad <> 0 then
    raise exception '0245 self-assert FAIL: % harbour(s) restock at another rate than stock_regen_fraction while dark', v_bad;
  end if;
  v_old := (select d.seen from dark_old_0245 d);
  v_new := pg_temp.dark_0245();
  if v_old is null or v_new is distinct from v_old or jsonb_array_length(v_new->'regen') < 1 or jsonb_array_length(v_new->'paths') < 1 then
    raise exception '0245 self-assert FAIL: dark, Funchal''s regen or outlook is not the pre-image''s: new % old %', v_new, v_old;
  end if;

  -- (c) LIT, THE MATHS (a rolled-back sub-transaction)
  begin
    update public.world_config set value = 'true'::jsonb where key in ('economy_closed', 'restock_by_investment');
    if not public.restock_lit() then
      raise exception '0245 self-assert FAIL: restock_lit() is false with both switches on';
    end if;
    if public.restock_formula(0) <> 0.03 or public.restock_formula(500000) <> 0.165
       or public.restock_formula(1000000000000000) <> 0.30 or public.restock_formula(null) <> 0.03
       or not (public.restock_formula(100000) < public.restock_formula(504000)
               and public.restock_formula(504000) < public.restock_formula(1250000)
               and public.restock_formula(1250000) < 0.30) then
      raise exception '0245 self-assert FAIL: the formula is not I=0 → 0.03, 500 k → 0.165, cap 0.30, rising';
    end if;
    -- the decay step, exact on a probe port (and an untracked port stays untracked)
    update public.port_treasury set invested = 1000000 where port_id = b.fnc;
    update public.port_treasury set invested = null where port_id = b.opo;
    perform public.invested_decay();
    v_exp := round(1000000 * exp(-ln(2.0) / 72));
    if v_exp <> 990419
       or (select t.invested from public.port_treasury t where t.port_id = b.fnc) <> v_exp
       or (select t.invested from public.port_treasury t where t.port_id = b.opo) is not null then
      raise exception '0245 self-assert FAIL: the decay step on Funchal is % (want 990419 = round(1000000 × 0.5^(1/72))); an untracked port must stay null',
        (select t.invested from public.port_treasury t where t.port_id = b.fnc);
    end if;
    -- the day's rates: planted investments, then restock_day once
    update public.port_treasury set invested = 0 where port_id = b.lis;
    update public.port_treasury set invested = 500000 where port_id = b.ams;
    perform public.restock_day(v_day);
    if (select t.restock_rate from public.port_treasury t where t.port_id = b.lis) <> 0.03
       or (select t.restock_rate from public.port_treasury t where t.port_id = b.ams) <> 0.165
       or (select t.restock_rate from public.port_treasury t where t.port_id = b.opo) <> 0.03   -- untracked: the slowest rate
       or (select t.restock_rate from public.port_treasury t where t.port_id = b.fnc) <> public.restock_formula(v_exp)
       or public.restock_rate(b.ams) <> 0.165 or public.restock_rate(b.lis) <> 0.03
       or exists (select 1 from public.port_treasury t join public.ports p on p.id = t.port_id and p.kind = 'HARBOUR'
                   where t.restock_day is distinct from v_day or t.restock_rate not between 0.03 and 0.30) then
      raise exception '0245 self-assert FAIL: restock_day did not set the planted harbours'' rates (or left a harbour off the day)';
    end if;
    -- once per day: a new investment changes nothing until the next day
    update public.port_treasury set invested = 100000000 where port_id = b.ams;
    if public.restock_day(v_day) <> 0 or public.restock_rate(b.ams) <> 0.165 then
      raise exception '0245 self-assert FAIL: the rate moved twice in one game-day';
    end if;
    perform public.restock_day(v_day + 1);
    if public.restock_rate(b.ams) <> public.restock_formula(100000000) or public.restock_rate(b.ams) <= 0.165 then
      raise exception '0245 self-assert FAIL: the next day did not take the new investment';
    end if;
    -- the regen follows the stored rate, row for row
    v_rate := public.restock_rate(b.fnc);
    if v_rate = public.wc_num('stock_regen_fraction') then
      raise exception '0245 self-assert FAIL: the probe rate equals the dark rate — the test proves nothing';
    end if;
    create temp table pre_0245 on commit drop as
      select pg.good_id, pg.stock, pg.stock_target, pg.last_regen_day,
             pg.production_rate * public.works_factor(pg.port_id, 'production', 'production_per_level') as prod
        from public.port_goods pg where pg.port_id = b.fnc;
    perform public.tick_market_drift(v_far, b.fnc);
    select count(*) into v_bad
      from pre_0245 q join public.port_goods pg on pg.port_id = b.fnc and pg.good_id = q.good_id
     where q.last_regen_day < world.game_day(v_far)
       and pg.stock is distinct from round(public.stock_after(q.stock, q.stock_target, v_rate, q.prod,
                                                               world.game_day(v_far) - q.last_regen_day), 2);
    if v_bad <> 0 or not exists (select 1 from pre_0245 q where q.last_regen_day < world.game_day(v_far)) then
      raise exception '0245 self-assert FAIL: % Funchal row(s) did not regenerate at the stored rate % (or none was due)', v_bad, v_rate;
    end if;
    -- reopening the economy gives the knob's rate back
    update public.world_config set value = 'false'::jsonb where key = 'economy_closed';
    if public.restock_rate(b.ams) <> public.wc_num('stock_regen_fraction') or public.restock_day(v_day + 2) <> 0 then
      raise exception '0245 self-assert FAIL: with the economy open the rate is not the knob''s, or the day''s job wrote';
    end if;
    raise exception using errcode = 'ZY245', message = 'lit ok';
  exception when sqlstate 'ZY245' then
    null;
  end;

  -- (d) the probe rolled back: dark again, no stored rate, the tracked rows as they were
  if public.restock_lit()
     or exists (select 1 from public.port_treasury t where t.restock_rate is not null or t.restock_day is not null)
     or (select count(*) from public.port_treasury t where t.invested is not null) <> b.invested_rows then
    raise exception '0245 self-assert FAIL: the lit probe left something behind';
  end if;

  raise notice '0245 self-assert ok: A CITY RESTOCKS BY WHAT IS INVESTED (dark). tick_city (3 hunks), tick_market_drift (2), price_path (1) re-cut, each reversed, ACL unmoved; five server-only functions; registry unchanged; walls 0. DARK: restock_rate = stock_regen_fraction on every harbour; Funchal 30 days on and its outlook for 3 goods equal the pre-image''s. LIT (rolled back): I=0 -> 0.03, 500 k -> 0.165, 10^15 -> 0.30; decay 1,000,000 -> 990,419 exactly, untracked stays null; the day''s rate set once (a second call writes 0), the next day takes new investment; Funchal''s regen follows the stored rate row for row; open economy -> the knob''s rate. Nothing left behind.';
end $$;
