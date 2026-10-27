-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0252 — A CITY HOLDS WHAT IS INVESTED   (slice E5b of docs/CLOSED_ECONOMY.md §3: the max stock moves with investment)
--        DARK: this file changes no price, no stock and no max stock. Lit later by the OWNER only:
--        `update public.world_config set value = 'true' where key = 'depth_by_investment'`.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER (2026-10-26, §3) ──────────────────────────────────────────────────────────────────
--   "the max trade good stock, should increase and decrease depending on the investment of that city too, and the
--   settings set by should be once per day."
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
--   COLUMNS  port_treasury.depth_mult numeric(6,4) null, port_treasury.depth_day int null — THE DAY'S MULTIPLE of the
--            harbour's max stock, set once a game-day by public.depth_day(); read by public.depth_mult().
--            port_goods.base_target numeric(12,2) null — the max stock as it stood before any multiple (kept the
--            first time a multiple is applied, so a multiple never compounds).
--   KNOBS    depth_by_investment false (THE dark switch of this slice), depth_m0 0.5, depth_m1 1.5,
--            depth_step_max 0.10. The investment at the half-way point is E5's restock_i_half (500,000): one figure.
--   NEW, server-only:
--     public.depth_formula(I)     m0 + (m1 − m0) × I / (I + I½), 4 places.        (§3: I = 0 → 0.5×, 504 k ≈ 1.0×, cap 1.5×)
--     public.depth_lit()          depth_by_investment AND economy_closed().        (THE one gate of this slice)
--     public.depth_mult(port)     THE one reader of the stored multiple (null = never set: the max as it stands).
--     public.depth_target(target, base, mult)   THE one expression of the max stock: mult null → target unchanged;
--                                 else round(coalesce(base, target) × mult, 2). Immutable SQL (inlined, no call cost).
--     public.depth_day(day)       once per game-day per harbour: mult ← the formula's value (lit) or 1 (not lit, for a
--                                 harbour that was lit before), moved at most ±depth_step_max of itself in one day.
--   HUNKS (re-cut against the LIVE bodies, prod head 0248):
--     public.tick_city           (1) a step 3c calls depth_day(today), right after E5's restock_day; errors go in
--                                the receipt's error map like every other step.
--     public.tick_market_drift   (1) 0247's once-a-harbour CTE also reads depth_mult(port); (2) the regen walks the
--                                stock to depth_target(...); (3) the same update writes stock_target / base_target.
--                                No new statement, no new row write: the max moves in the row write the day's regen
--                                already makes, once per game-day per row.
--
-- ── DARK (what the main session sees after deploy) ──────────────────────────────────────────────
--   depth_mult is null on every harbour; depth_day writes nothing; the regen writes stock_target = stock_target and
--   base_target = null (the values they hold): stock, glut, day, max stock byte-identical to the pre-image's.
--
-- ── DECIDED BY DEFAULT (stated; the owner may reverse) ──────────────────────────────────────────
--   * "Once a day" = once per GAME-day, in tick_city, as E5's restock_day does (§3 says "the daily job"). One rule.
--   * "±10 % of depth" = the multiple moves at most 10 % OF ITSELF a day (1.0 → 1.1 → 1.21; 1.0 → 0.9 → 0.81).
--   * Lit first, every harbour starts from 1.0× (today's max), never a jump to the formula's value.
--   * Switched off after being lit: each harbour's multiple walks back to 1.0 by the same ±10 % a day (no jump), then
--     stays at 1.0 (= base). Never-lit harbours are never touched.
--   * The stock is NOT rescaled. It walks to the new max at the day's restock rate. A max that FALLS below the stock:
--     the regen's existing rule (public.stock_after, `least(target, …)`, unchanged since 0010) trims the stock to the
--     max at that day's regen, as it already trims goods sold in above the max. The ±10 %/day step bounds it.
--   * Own flag, not E5's: restock_by_investment and depth_by_investment are lit separately.
--   * The outlook (price_path) keeps the max as it stands now (it already does not predict trades).
--
-- ── WHAT IT SELF-ASSERTS (probe rows only; every probe a rolled-back sub-transaction, asserted) ───
--   (a) hunks reverse to the pre-images; ACL / volatility / definer / config unmoved; new functions server-only;
--       registry unchanged; walls 0.
--   (b) DARK, BYTE FOR BYTE: Funchal regenerated 30 days on (stock, max, base, glut, day) BEFORE and AFTER the re-cut,
--       from the same state (rows locked); depth_mult null everywhere; depth_day writes 0.
--   (c) LIT: the formula (0 → 0.5, 500 k → 1.0, 10^15 → 1.5); the step (1.0 → 1.1 → 1.21 and 1.0 → 0.9 → 0.81; once a
--       day); Funchal's regen at a planted 1.1 and then 1.21: max = round(base × mult, 2) (not compounded), base kept,
--       stock walked by the stored rate to the new max (not rescaled); switched off → back toward 1.0 by the step.
--   (d) after: no multiple, no base_target, knob false.
-- ROLLBACK (forward): restore the OLD hunks below verbatim; drop the five functions, the three columns, the four knobs.
-- VERSION: 0252 (prod head 0248 when cut; 0249-0251 in flight, none touches these hunks).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '10min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('public.restock_rate(uuid)') is null or to_regprocedure('public.restock_day(int)') is null then
    raise exception '0252 refuses: E5 (0245) is not in this world';
  end if;
  if to_regprocedure('public.depth_mult(uuid)') is not null then
    raise exception '0252 refuses: depth_mult already exists';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0252(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 0. THE PRE-IMAGES (LF-normalised) ───────────────────────────────────────────────────────────
create temp table defs_before_0252 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('public.tick_city(timestamp with time zone)'),
               ('public.tick_market_drift(timestamp with time zone,uuid)')) f(fn);

create temp table before_0252 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select p.id from public.ports p where p.code = 'FNC' and p.kind = 'HARBOUR') as fnc,
       (select p.id from public.ports p where p.code = 'AMS' and p.kind = 'HARBOUR') as ams,
       (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR') as lis;

do $$
begin
  if exists (select 1 from before_0252 b where b.fnc is null or b.ams is null or b.lis is null) then
    raise exception '0252 self-assert FAIL: no Funchal, Amsterdam or Lisbon';
  end if;
  perform 1 from public.port_goods pg, before_0252 b where pg.port_id = b.fnc for update;   -- one state for both dark runs
end $$;

-- ── 1. THE DARK PROBE: Funchal regenerated 30 days on; rolled back; answers what it saw ─────────
--   (base_target does not exist before the re-cut; the probe reads it through to_jsonb, absent = null)
create or replace function pg_temp.dark_0252()
returns jsonb
language plpgsql
as $$
declare
  v_fnc uuid := (select b.fnc from before_0252 b);
  v_res jsonb;
begin
  begin
    perform public.tick_market_drift(now() + interval '30 days', v_fnc);
    select jsonb_agg(jsonb_build_array(g.code, pg.stock, pg.stock_target, to_jsonb(pg)->'base_target', pg.glut,
                                       pg.last_regen_day) order by g.code)
      into v_res
      from public.port_goods pg join public.goods g on g.id = pg.good_id where pg.port_id = v_fnc;
    raise exception using errcode = 'ZY252', message = v_res::text;
  exception when sqlstate 'ZY252' then
    return sqlerrm::jsonb;
  end;
end $$;

create temp table dark_old_0252 on commit drop as select pg_temp.dark_0252() as seen;

-- ── 2. THE COLUMNS AND THE KNOBS ────────────────────────────────────────────────────────────────
alter table public.port_treasury
  add column depth_mult numeric(6,4) check (depth_mult between 0.1 and 10),
  add column depth_day  int;
alter table public.port_goods
  add column base_target numeric(12,2) check (base_target > 0);
comment on column public.port_treasury.depth_mult is
  '0252 (docs/CLOSED_ECONOMY.md §3, E5b): the multiple of the harbour''s max stock for ONE game-day (depth_day), set '
  'once a day by public.depth_day() from `invested`; read only through public.depth_mult(). Null = never set.';
comment on column public.port_treasury.depth_day is '0252: the game-day depth_mult was last set for. One writer: public.depth_day().';
comment on column public.port_goods.base_target is
  '0252 (E5b): the max stock before any investment multiple, kept the first time one is applied (so it never compounds). '
  'One writer: public.tick_market_drift''s regen, through public.depth_target(). Null = no multiple ever applied.';

insert into public.world_config (key, value, description) values
  ('depth_by_investment', 'false'::jsonb,
   '0252 (docs/CLOSED_ECONOMY.md §3, E5b): false = every harbour keeps its max stock, byte for byte. true (with economy_closed) = the max stock moves with what is invested, set once a game-day, at most depth_step_max a day. Read only through public.depth_lit(). OWNER ONLY.'),
  ('depth_m0', '0.5'::jsonb, '0252 (§3): the max-stock multiple of a city nobody has invested in.'),
  ('depth_m1', '1.5'::jsonb, '0252 (§3): the cap of the max-stock multiple.'),
  ('depth_step_max', '0.10'::jsonb, '0252 (§3): the most a harbour''s max-stock multiple moves in one game-day, as a fraction of itself.');

-- ── 3. THE FIVE FUNCTIONS ───────────────────────────────────────────────────────────────────────
create function public.depth_formula(p_invested bigint)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0252 (§3): depth_mult = m0 + (m1 − m0) × I / (I + I½), at the column's scale. I = 0 → m0; I → ∞ → m1.
  select round(public.wc_num('depth_m0')
               + (public.wc_num('depth_m1') - public.wc_num('depth_m0'))
                 * greatest(0, coalesce(p_invested, 0))::numeric
                 / (greatest(0, coalesce(p_invested, 0))::numeric + public.wc_num('restock_i_half')), 4)
$$;

create function public.depth_lit()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0252: THE ONE gate of this slice: its own knob AND the closed economy.
  select coalesce((public.wc('depth_by_investment'))::boolean, false) and public.economy_closed()
$$;

create function public.depth_mult(p_port uuid)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0252: THE ONE reader of a harbour's max-stock multiple (tick_market_drift's regen, once a harbour). Null = never
  -- set: the max stays as it stands. Not gated by the knob, so a harbour switched off walks back to 1.0 by depth_day.
  select t.depth_mult from public.port_treasury t where t.port_id = p_port
$$;

create function public.depth_target(p_target numeric, p_base numeric, p_mult numeric)
returns numeric
language sql
immutable
parallel safe
as $$
  -- 0252: THE ONE expression of a row's max stock under a multiple. Null multiple → the max as it stands (dark).
  -- Otherwise the base (kept the first time) × the multiple, at the column's scale, never below one hundredth.
  select case when p_mult is null then p_target
              else greatest(0.01, round(coalesce(p_base, p_target) * p_mult, 2)) end
$$;

create function public.depth_day(p_day int)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_lit  boolean := public.depth_lit();
  v_step numeric := public.wc_num('depth_step_max');
  v_n    int;
begin
  -- 0252 (§3, owner: "once per day"): once per game-day per harbour. Lit: the multiple moves toward
  -- depth_formula(I) (untracked I = 0); not lit: a harbour that was lit before moves back toward 1.0. Either way at
  -- most v_step of itself. A never-lit harbour (null) is never touched while dark. Called by tick_city (step 3c).
  update public.port_treasury t
     set depth_mult = round(least(greatest(x.goal, x.old * (1 - v_step)), x.old * (1 + v_step)), 4),
         depth_day  = p_day
    from (select t2.port_id, coalesce(t2.depth_mult, 1.0) as old,
                 case when v_lit then public.depth_formula(t2.invested) else 1.0 end as goal
            from public.port_treasury t2
            join public.ports p on p.id = t2.port_id and p.kind = 'HARBOUR'
           where t2.depth_day is distinct from p_day
             and (v_lit or (t2.depth_mult is not null and t2.depth_mult <> 1))) x
   where x.port_id = t.port_id;
  get diagnostics v_n = row_count;
  return v_n;
end $$;

comment on function public.depth_formula(bigint) is '0252 (§3): the one formula of the max-stock multiple. Server-only.';
comment on function public.depth_lit() is '0252: depth_by_investment AND economy_closed(). Server-only.';
comment on function public.depth_mult(uuid) is '0252 (§3): THE one reader of a harbour''s max-stock multiple. Server-only.';
comment on function public.depth_target(numeric, numeric, numeric) is '0252 (§3): the one expression of a max stock under a multiple.';
comment on function public.depth_day(int) is '0252 (§3): sets each harbour''s max-stock multiple once per game-day. Called by tick_city.';
revoke all on function public.depth_formula(bigint) from public, anon, authenticated;
revoke all on function public.depth_lit() from public, anon, authenticated;
revoke all on function public.depth_mult(uuid) from public, anon, authenticated;
revoke all on function public.depth_target(numeric, numeric, numeric) from public, anon, authenticated;
revoke all on function public.depth_day(int) from public, anon, authenticated;

-- ── 4. THE RE-CUTS (hunks sliced from the live bodies; each occurs once; each body reverses) ──────
create temp table hunks_0252 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0252 (fn, n, old, new) values
('public.tick_city(timestamp with time zone)', 1,
$h$    perform public.restock_day(v_today);
  exception when others then
    v_err := v_err || jsonb_build_object('restock', sqlerrm);
  end;
$h$,
$h$    perform public.restock_day(v_today);
  exception when others then
    v_err := v_err || jsonb_build_object('restock', sqlerrm);
  end;

  -- 3c. DEPTH (0252, E5b; lit by depth_by_investment): once per game-day each harbour's max-stock multiple is set from
  --     what is invested (public.depth_day); the drift job's regen applies it. Dark it writes nothing.
  begin
    perform public.depth_day(v_today);
  exception when others then
    v_err := v_err || jsonb_build_object('depth', sqlerrm);
  end;
$h$),
('public.tick_market_drift(timestamp with time zone,uuid)', 1,
$h$           public.wc_num('glut_decay') as glut_decay   -- 0194
      from public.ports po
$h$,
$h$           public.wc_num('glut_decay') as glut_decay,   -- 0194
           public.depth_mult(po.id) as depth   -- 0252 (E5b): the day's max-stock multiple (null: the max as it stands)
      from public.ports po
$h$),
('public.tick_market_drift(timestamp with time zone,uuid)', 2,
$h$     set stock = public.stock_after(pg.stock, pg.stock_target, f.rate,$h$,
$h$     set stock = public.stock_after(pg.stock, public.depth_target(pg.stock_target, pg.base_target, f.depth), f.rate,   -- 0252: to the day's max$h$),
('public.tick_market_drift(timestamp with time zone,uuid)', 3,
$h$         last_regen_day = v_day,
         updated_at = p_now
    from f
$h$,
$h$         last_regen_day = v_day,
         stock_target = public.depth_target(pg.stock_target, pg.base_target, f.depth),   -- 0252 (E5b): the day's max stock
         base_target = case when f.depth is null then pg.base_target else coalesce(pg.base_target, pg.stock_target) end,
         updated_at = p_now
    from f
$h$);

create or replace function pg_temp.recut_0252(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := (select def from defs_before_0252 where fn = p_fn);
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0252 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0252(v_def, h.old);
    if v_n <> 1 then
      raise exception '0252 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, h.fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0252(fn) from defs_before_0252 order by fn;

-- ── 5. THE SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
do $$
declare
  b      record;
  v_d record; v_h record; v_pp record; v_def text;
  v_old  jsonb;
  v_new  jsonb;
  v_day  int := 7777777;       -- a game-day no clock has reached: nothing real carries it
  v_bad  int;
  v_rate numeric;
  v_far  timestamptz := now() + interval '30 days';
  v_far2 timestamptz := now() + interval '31 days';
begin
  select * into b from before_0252;

  -- (a) THE RE-CUTS reverse; ACL / volatility / definer / config unmoved; new functions server-only
  for v_d in select * from defs_before_0252 loop
    v_def := replace(pg_get_functiondef(v_d.fn::regprocedure), E'\r', '');
    for v_h in select * from hunks_0252 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0252(v_def, v_h.new) <> 1 then
        raise exception '0252 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0252 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef, coalesce(p.proconfig::text, '') as cfg
      into v_pp from pg_proc p where p.oid = v_d.fn::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg then
      raise exception '0252 self-assert FAIL: % changed its ACL, volatility, definer or config', v_d.fn;
    end if;
  end loop;
  if exists (select 1 from (values ('public.depth_formula(bigint)'), ('public.depth_lit()'), ('public.depth_mult(uuid)'),
                                   ('public.depth_target(numeric,numeric,numeric)'), ('public.depth_day(int)')) f(fn)
              where has_function_privilege('authenticated', f.fn, 'execute') or has_function_privilege('anon', f.fn, 'execute')) then
    raise exception '0252 self-assert FAIL: a client role can execute one of the five new functions';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> b.entry_points then
    raise exception '0252 self-assert FAIL: the registry moved';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0252 self-assert FAIL: a wall moved';
  end if;

  -- (b) DARK, BYTE FOR BYTE
  if public.depth_lit() then
    raise exception '0252 self-assert FAIL: depth_by_investment is not dark';
  end if;
  if exists (select 1 from public.port_treasury t where t.depth_mult is not null or t.depth_day is not null) then
    raise exception '0252 self-assert FAIL: a harbour carries a max-stock multiple while dark';
  end if;
  v_old := (select d.seen from dark_old_0252 d);
  v_new := pg_temp.dark_0252();
  if v_old is null or v_new is distinct from v_old or jsonb_array_length(v_new) < 1 then
    raise exception '0252 self-assert FAIL: dark, Funchal''s regen is not the pre-image''s: new % old %', v_new, v_old;
  end if;
  begin
    if public.depth_day(v_day) <> 0 then
      raise exception '0252 self-assert FAIL: depth_day wrote while dark';
    end if;
    raise exception using errcode = 'ZY252', message = 'dark day ok';
  exception when sqlstate 'ZY252' then
    null;
  end;

  -- (c) LIT (a rolled-back sub-transaction)
  begin
    update public.world_config set value = 'true'::jsonb where key in ('economy_closed', 'depth_by_investment');
    if not public.depth_lit() then
      raise exception '0252 self-assert FAIL: depth_lit() is false with both switches on';
    end if;
    if public.depth_formula(0) <> 0.5 or public.depth_formula(500000) <> 1.0 or public.depth_formula(null) <> 0.5
       or public.depth_formula(1000000000000000) <> 1.5
       or not (public.depth_formula(100000) < public.depth_formula(504000) and public.depth_formula(504000) < 1.5) then
      raise exception '0252 self-assert FAIL: the formula is not I=0 → 0.5, 500 k → 1.0, cap 1.5, rising';
    end if;
    -- the step: from 1.0, at most 10 % of itself a day, once a day
    update public.port_treasury set invested = 1000000000000000 where port_id = b.ams;
    update public.port_treasury set invested = 0 where port_id = b.lis;
    perform public.depth_day(v_day);
    if public.depth_mult(b.ams) <> 1.1 or public.depth_mult(b.lis) <> 0.9
       or exists (select 1 from public.port_treasury t join public.ports p on p.id = t.port_id and p.kind = 'HARBOUR'
                   where t.depth_day is distinct from v_day or t.depth_mult not between 0.9 and 1.1) then
      raise exception '0252 self-assert FAIL: the first day is not 1.0 ± 10 %% (AMS %, LIS %)', public.depth_mult(b.ams), public.depth_mult(b.lis);
    end if;
    if public.depth_day(v_day) <> 0 then
      raise exception '0252 self-assert FAIL: the multiple moved twice in one game-day';
    end if;
    perform public.depth_day(v_day + 1);
    if public.depth_mult(b.ams) <> 1.21 or public.depth_mult(b.lis) <> 0.81 then
      raise exception '0252 self-assert FAIL: the second day is not 1.21 / 0.81 (AMS %, LIS %)', public.depth_mult(b.ams), public.depth_mult(b.lis);
    end if;
    -- Funchal's regen at a planted 1.1: the max = round(base × 1.1, 2), base kept, stock walked to the new max
    update public.port_treasury set depth_mult = 1.1 where port_id = b.fnc;
    v_rate := public.restock_rate(b.fnc);
    create temp table pre_0252 on commit drop as
      select pg.good_id, pg.stock, pg.stock_target, pg.last_regen_day,
             pg.production_rate * public.works_factor(pg.port_id, 'production', 'production_per_level') as prod
        from public.port_goods pg where pg.port_id = b.fnc;
    perform public.tick_market_drift(v_far, b.fnc);
    select count(*) into v_bad
      from pre_0252 q join public.port_goods pg on pg.port_id = b.fnc and pg.good_id = q.good_id
     where q.last_regen_day < world.game_day(v_far)
       and (pg.base_target is distinct from q.stock_target
            or pg.stock_target is distinct from round(q.stock_target * 1.1, 2)
            or pg.stock is distinct from round(public.stock_after(q.stock, round(q.stock_target * 1.1, 2), v_rate, q.prod,
                                                                    world.game_day(v_far) - q.last_regen_day), 2));
    if v_bad <> 0 or not exists (select 1 from pre_0252 q where q.last_regen_day < world.game_day(v_far)) then
      raise exception '0252 self-assert FAIL: % Funchal row(s) did not take max = base × 1.1 with the stock walked (or none was due)', v_bad;
    end if;
    -- the next day at 1.21: base × 1.21, not compounded on the 1.1 max
    update public.port_treasury set depth_mult = 1.21 where port_id = b.fnc;
    perform public.tick_market_drift(v_far2, b.fnc);
    select count(*) into v_bad
      from pre_0252 q join public.port_goods pg on pg.port_id = b.fnc and pg.good_id = q.good_id
     where pg.base_target is distinct from q.stock_target or pg.stock_target is distinct from round(q.stock_target * 1.21, 2);
    if v_bad <> 0 then
      raise exception '0252 self-assert FAIL: % Funchal row(s) compounded the multiple or lost the base', v_bad;
    end if;
    -- switched off: a lit harbour walks back toward 1.0 by the step (1.21 → 1.089; 0.81 → 0.891), once a day
    update public.world_config set value = 'false'::jsonb where key = 'depth_by_investment';
    perform public.depth_day(v_day + 2);
    if public.depth_mult(b.ams) <> 1.089 or public.depth_mult(b.lis) <> 0.891 then
      raise exception '0252 self-assert FAIL: switched off, the multiple did not walk back by the step (AMS %, LIS %)',
        public.depth_mult(b.ams), public.depth_mult(b.lis);
    end if;
    raise exception using errcode = 'ZY252', message = 'lit ok';
  exception when sqlstate 'ZY252' then
    null;
  end;

  -- (d) the probe rolled back
  if public.depth_lit()
     or exists (select 1 from public.port_treasury t where t.depth_mult is not null or t.depth_day is not null)
     or exists (select 1 from public.port_goods pg where pg.base_target is not null) then
    raise exception '0252 self-assert FAIL: the lit probe left something behind';
  end if;

  raise notice '0252 self-assert ok: A CITY HOLDS WHAT IS INVESTED (dark). tick_city (1 hunk), tick_market_drift (3) re-cut, each reversed, ACL unmoved; five server-only functions; registry unchanged; walls 0. DARK: no multiple anywhere, depth_day writes 0; Funchal 30 days on (stock, max, base, glut, day) equals the pre-image''s. LIT (rolled back): 0 -> 0.5, 500 k -> 1.0, 10^15 -> 1.5; the step 1.0 -> 1.1 -> 1.21 and 1.0 -> 0.9 -> 0.81, once a day; Funchal''s max = round(base x 1.1, 2) then x 1.21 (not compounded), base kept, stock walked at the stored rate; switched off -> 1.089 / 0.891. Nothing left behind.';
end $$;
