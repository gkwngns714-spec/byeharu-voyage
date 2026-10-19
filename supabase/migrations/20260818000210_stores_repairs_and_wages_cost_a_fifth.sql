-- NOT FOR DEPLOY (2026-10-19 hand-off): proof 07_standing_provision is red with this file (5/6 markers, not yet
-- read), and the paired merchant sim was stopped before it finished. See docs/dev-log/2026-10-19-running-costs-d5.md.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0210 — STORES, REPAIRS AND WAGES COST A FIFTH
--        (one knob, running_cost_level 0.2, applied once in each cost's one authority)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- The owner, 2026-10-19, after 0208 (goods ÷ 5, holds × 3, the haul premium halved) left running costs
-- alone and merchants' lap nets fell about 75 %: "supplies and repairs yes" (cut them ÷ 5 like goods).
-- And about wages: "wages are in % so it will be same right?" They are NOT a percentage: public.crew_wages
-- is crew × wage_per_crew_day (1 ducat) × the short-rations multiplier, × running_cost_mult, owed each
-- sea-day and paid out of profit. DECIDED BY DEFAULT (the owner may reverse it): wages ÷ 5 as well, because
-- the owner's intent is that running costs keep pace with the ÷ 5 prices.
-- Built on 0208 (live). Supersedes and re-cuts, every body sliced from the live one (each hunk occurs once
-- and reverses to its pre-image, asserted; the live md5s were checked on prod read-only):
--   public.crew_wages (0086: drop + recreate, RETURNS numeric), public.fleet_wage (0154: drop + recreate,
--   RETURNS numeric), public.owe_wages (0128: drop + recreate, p_wage numeric), public.pay_wages (0128),
--   voyage.settle (0128 … 0189: one hunk, the wage variable's type), public.stores_cost (0142),
--   cmd.do_repair (0181), public.unit_repair_cost (0158).
--
-- ── THE ONE KNOB: running_cost_level (0.2) ─────────────────────────────────────────────────────
--   What the house pays to keep a ship at sea, as a multiple of the design figures (the knobs keep their
--   design values: provision_*_price 2 / 5, repair_rate_per_point 2, gear_repair_pct 0.3, wage_per_crew_day 1).
--   Read at the moment a cost is reckoned — unlike 0208's knobs, which were applied when rows were written —
--   in exactly one place per cost, the place that already DECIDES that cost:
--     1. STORES — public.stores_cost (0142: "THE price of stores"). Every price of stores is it:
--        cmd.do_provision (what she pays), public.npc_provision_for (what a top-up costs a merchant),
--        public.npc_plan (what a loop's stores will cost) — no hunk in any of them.
--     2. HULL REPAIR — cmd.do_repair's one charge line (points × repair_rate_per_point × (1 − dev %) ×
--        running_cost_mult). Nothing else prices a hull: cmd.preview runs cmd.do_repair, npc_plan writes a
--        REPAIR on a loop without pricing it, cmd.standing_route_lines asks public.fleet_repair_due (points only).
--     3. GEAR REPAIR — public.unit_repair_cost (0158: "THE ONE PRICE OF REPAIRING ONE UNIT"). gear_repair_pct is
--        a share of public.item_recipe_value, which 0208 pinned to the DESIGN value (base_value ÷
--        goods_price_level), so without this term gear repair would not move at all. public.gear_repair_quote
--        (cmd.do_repair's gear) and public.unmount_fitting (a worn piece's way off) read it — no hunk.
--     4. WAGES — public.crew_wages (0086: "THE ONE SUM"). public.fleet_wage (THE one reading of a fleet's day:
--        voyage.settle owes it, world.crew_cost quotes it, cmd.do_dismiss and world.good_board read it) and the
--        planner's leg estimate (public.npc_leg_lines: crew_wages × running_cost_mult × sea-days) follow.
--   running_cost_mult (npc_cost_mult for a merchant, 0114) is a DIFFERENT thing — who pays what share — and
--   is left exactly as it is.
--
-- ── THE WAGE'S ROUNDING, and how the money stays right over a voyage ───────────────────────────
--   crew_wages and fleet_wage rounded to a whole ducat per call, and voyage.settle calls them once a sea-day.
--   At 1 ducat a man that was exact. At 0.2 it is not: a crew of 2 owes 0.4 a day, which rounds to 0 — she
--   would owe nothing for ever — and a crew of 3 owes 0.6, which rounds to 1, two thirds too much, every day,
--   the same way. So the fraction is KEPT until money moves:
--     * crew_wages returns the exact numeric (no rounding); fleet_wage rounds to 4 places (its Pursership
--       discount divides by 100); voyage.settle's day wage is numeric;
--     * public.fleet_wages.owed is numeric (was bigint), and public.owe_wages takes a numeric day — what she
--       owes is the exact sum of her sea-days;
--     * public.pay_wages, THE ONE MOVER, pays FLOOR(wages_from_profit(owed, …)) whole ducats — never more than
--       she owes — and the fraction stays owed for the next sale. (For whole-ducat inputs floor = round, so a
--       pre-0210 world pays exactly as before.)
--   Over any voyage the crew is paid the exact sum, less under one ducat still owed.
--
-- ── DECIDED BY DEFAULT (the owner may reverse each) ────────────────────────────────────────────
--   * Wages ÷ 5 (above).
--   * WHAT IS OWED NOW × 0.2 (public.fleet_wages.owed: on prod 838 rows, 433,898 owed). It is wages reckoned
--     in the old money and not yet paid; left whole, the first ÷ 5 profits would go to old debts (up to 5,400
--     a fleet), and the 30-day cap (wages_owed_cap_days × the NEW day) would clip most of it at a fleet's
--     next sea-day anyway, by chance of timing. Scaled, every fleet's debt is in the new money at once.
--   * KEPT: the tow (tow_fee_per_nm — a fee for being wrecked, not keeping a ship at sea), the hire fee
--     (crew_hire_cost — a one-off price), officers' wages, ship prices, cash, purses, the profit-tax rates,
--     the 0208 knobs, wages_owed_cap_days (30 days of the new, smaller day), npc_cost_mult.
--   * The figures the client is served keep their design values (snapshot.config.wage_per_crew_day 1); every
--     screen reads a cost the server computed (world.crew_cost, the receipts), never knob × count.
--   * Rounding of stores and repairs stays per purchase (round to the ducat): a purchase IS the payment.
--
-- ── WHAT IT SELF-ASSERTS ─────────────────────────────────────────────────────────────────────────
--   (a) the knob; the pre-image copies of the old arithmetic equal the live bodies on a grid (before);
--   (b) stores_cost, unit_repair_cost and crew_wages are 0.2 × the old arithmetic (exactly before rounding,
--       within the rounding after) on a grid of every item × three wears, stores 7 × 7, crews 0–400;
--   (c) the doors, on the probe's own house (rolled back whole): PROVISION charges stores_cost; a crew of 3
--       and a crew of 313 owe the exact sum of their sea-days (0.6 and 62.6 a day, 1.5 × on short rations),
--       which the old per-day rounding could not; the sale pays floor(owed) and leaves the fraction owed;
--       REPAIR charges 0.2 × the old hull price;
--   (d) owed × 0.2 on every row; the 0208 knobs, ship prices and every purse unmoved;
--   (e) every re-cut body reverses to its pre-image, ACL / volatility / definer / config kept (the dropped
--       three get their pre-image ACL back); no client reaches them; the walls;
--   (f) timings, 8 calls each in one session: crew_wages, fleet_wage, stores_cost, unit_repair_cost,
--       npc_provision_for, voyage.settle (the probe's passage in 8 steps).
-- ROLLBACK (a forward migration): running_cost_level 1 restores every cost (the owed × 5 by hand); the
--   hunks reverse (owe_wages / fleet_wage / crew_wages back to bigint by drop + recreate).
-- VERSION: 0210 at writing (prod head 0208; an arrivals slice may take 0209). It RENUMBERS to the prod
--   head + 1 at push, with every '0210' in this file.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '10min', true);
  perform set_config('lock_timeout', '5s', true);
  if exists (select 1 from public.world_config where key = 'running_cost_level') then
    raise exception '0210 refuses: running_cost_level already exists — this has been applied once';
  end if;
  if public.wc_num('goods_price_level') is distinct from 0.2 then
    raise exception '0210 refuses: 0208 (goods_price_level 0.2) is not in this world';
  end if;
  if to_regprocedure('public.crew_wages(integer, boolean)') is null
     or to_regprocedure('public.fleet_wage(uuid, boolean, integer)') is null
     or to_regprocedure('public.owe_wages(uuid, bigint)') is null
     or (select data_type from information_schema.columns
          where table_schema = 'public' and table_name = 'fleet_wages' and column_name = 'owed') <> 'bigint' then
    raise exception '0210 refuses: the wage functions or fleet_wages.owed are not 0128 / 0154''s';
  end if;
end $guard$;

-- ── 0. HELPERS (pg_temp, gone at commit) ───────────────────────────────────────────────────────
create or replace function pg_temp.occurs_0210(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- THE OLD ARITHMETIC, kept under pg_temp names so the new can be compared to it (proved equal to the live
-- bodies on a grid before the re-cut, below).
create function pg_temp.crew_wages_b0210(p_crew int, p_short boolean) returns bigint language sql stable as $$
  select round(p_crew * public.wc_num('wage_per_crew_day')
               * (case when p_short then public.wc_num('short_rations_wage_mult') else 1 end))::bigint
$$;
create function pg_temp.stores_cost_b0210(p_player uuid, p_water numeric, p_food numeric) returns bigint language sql stable as $$
  select round((coalesce(p_water, 0) * public.wc_num('provision_water_price')
                + coalesce(p_food, 0) * public.wc_num('provision_food_price'))
               * public.running_cost_mult(p_player))::bigint
$$;
create function pg_temp.unit_repair_cost_b0210(p_item text, p_wear numeric) returns bigint language sql stable as $$
  select round(public.item_recipe_value(p_item) * least(greatest(coalesce(p_wear, 0), 0), 100) / 100
               * public.wc_num('gear_repair_pct'))::bigint
$$;

-- A PASSAGE'S WAGES, read back: the sea-days, what their payloads owed, what crew × 0.2 × the ration owes
-- (the crew at the START of each day: the day's wage is reckoned before its hazard, and a raid's dead are
-- not paid the next day), and what the old per-day rounding would have owed for the same days.
create function pg_temp.wage_days_0210(p_voy uuid, p_crew0 int)
returns table (days int, paid_days numeric, exact numeric, rounded numeric)
language sql stable as $$
  select count(*)::int, coalesce(sum(z.w), 0), coalesce(sum(z.c * 0.2 * z.m), 0), coalesce(sum(round(z.c * 0.2 * z.m)), 0)
    from (select (ve.payload->>'wages')::numeric as w,
                 case when (ve.payload->>'short_rations')::boolean then public.wc_num('short_rations_wage_mult') else 1 end as m,
                 p_crew0 - coalesce(sum(coalesce((ve.payload->>'crew_lost')::numeric, 0))
                                      over (order by ve.day_index rows between unbounded preceding and 1 preceding), 0) as c
            from public.voyage_events ve
           where ve.voyage_id = p_voy and ve.payload ? 'wages') z
$$;

-- ── 1. THE KNOB ─────────────────────────────────────────────────────────────────────────────────
insert into public.world_config (key, value, description) values
  ('running_cost_level', to_jsonb(0.2),
   '0210 (owner, 2026-10-19: "supplies and repairs yes"; wages by default): what keeping a ship at sea costs, as a '
   'multiple of the design figures (provision_*_price, repair_rate_per_point, gear_repair_pct, wage_per_crew_day '
   'keep their design values). Read once per cost, in that cost''s one authority: public.stores_cost (stores), '
   'cmd.do_repair (hull), public.unit_repair_cost (gear), public.crew_wages (wages; the fraction of a ducat is '
   'owed, not rounded away). Not the tow, the hire fee or ship prices.');

-- ── 2. LOCK, THEN THE PRE-IMAGES ────────────────────────────────────────────────────────────────
do $lock$
begin
  perform 1 from public.fleet_wages for update;
end $lock$;

create temp table defs_before_0210 on commit drop as
select f.fn, f.fn_new, f.redo,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg,
       (select pg_get_userbyid(p.proowner) from pg_proc p where p.oid = f.fn::regprocedure) as owner,
       obj_description(f.fn::regprocedure, 'pg_proc') as descr
  from (values
    -- (old identity, new identity, dropped and recreated: a return or argument type moves)
    ('public.crew_wages(integer, boolean)',            'public.crew_wages(integer, boolean)',            true),
    ('public.fleet_wage(uuid, boolean, integer)',      'public.fleet_wage(uuid, boolean, integer)',      true),
    ('public.owe_wages(uuid, bigint)',                 'public.owe_wages(uuid, numeric)',                true),
    ('public.pay_wages(uuid, uuid, bigint, uuid)',     'public.pay_wages(uuid, uuid, bigint, uuid)',     false),
    ('voyage.settle(uuid, timestamptz)',               'voyage.settle(uuid, timestamptz)',               false),
    ('public.stores_cost(uuid, numeric, numeric)',     'public.stores_cost(uuid, numeric, numeric)',     false),
    ('cmd.do_repair(uuid, jsonb)',                     'cmd.do_repair(uuid, jsonb)',                     false),
    ('public.unit_repair_cost(text, numeric)',         'public.unit_repair_cost(text, numeric)',         false)
  ) f(fn, fn_new, redo);

create temp table owed_0210 on commit drop as select fleet_id, owed from public.fleet_wages;
create temp table purse_0210 on commit drop as select id, ducats from public.players;
create temp table knobs_0210 on commit drop as
select key, value from public.world_config
 where key in ('goods_price_level', 'hold_scale', 'haul_premium_share', 'npc_cost_mult', 'wages_owed_cap_days',
               'wage_per_crew_day', 'provision_food_price', 'provision_water_price', 'repair_rate_per_point',
               'gear_repair_pct', 'tow_fee_per_nm', 'short_rations_wage_mult');
create temp table yard_0210 on commit drop as select coalesce(sum(ducats), 0) as d, count(*) as n from public.hull_recipes;

-- THE GRIDS: every item × three wears; stores 7 × 7 for a player (null: running_cost_mult 1) and for the
-- first merchant house by id, if there is one; crews 0–400 on both rations.
create temp table grid_items_0210 on commit drop as
select k.code, w.wear, public.unit_repair_cost(k.code, w.wear) as live, pg_temp.unit_repair_cost_b0210(k.code, w.wear) as copy,
       public.item_recipe_value(k.code) * w.wear / 100 * public.wc_num('gear_repair_pct') as exact
  from public.item_kinds k cross join (values (0::numeric), (37), (100)) w(wear);
create temp table grid_stores_0210 on commit drop as
select pl.player_id, a.w, b.f, public.stores_cost(pl.player_id, a.w, b.f) as live,
       pg_temp.stores_cost_b0210(pl.player_id, a.w, b.f) as copy,
       (a.w * public.wc_num('provision_water_price') + b.f * public.wc_num('provision_food_price'))
         * public.running_cost_mult(pl.player_id) as exact
  from (select null::uuid as player_id
        union all (select p.id from public.players p where p.is_npc order by p.id limit 1)) pl
  cross join (values (0::numeric), (0.37), (1), (2.25), (12.5), (81), (240.6)) a(w)
  cross join (values (0::numeric), (0.37), (1), (2.25), (12.5), (81), (240.6)) b(f);
create temp table grid_crew_0210 on commit drop as
select n, s, public.crew_wages(n, s) as live, pg_temp.crew_wages_b0210(n, s) as copy
  from generate_series(0, 400) n cross join (values (false), (true)) x(s);

do $copies$
begin
  -- THE COPIES ARE FAITHFUL: the old arithmetic under pg_temp names equals the live bodies on every grid row
  if exists (select 1 from grid_items_0210 where live is distinct from copy)
     or exists (select 1 from grid_stores_0210 where live is distinct from copy)
     or exists (select 1 from grid_crew_0210 where live is distinct from copy)
     or (select count(*) from grid_items_0210) < 300 or (select count(*) from grid_crew_0210) <> 802 then
    raise exception '0210 self-assert FAIL: a pre-image copy of the old arithmetic does not equal the live body (items %, stores %, crews %)',
      (select count(*) from grid_items_0210 where live is distinct from copy),
      (select count(*) from grid_stores_0210 where live is distinct from copy),
      (select count(*) from grid_crew_0210 where live is distinct from copy);
  end if;
end $copies$;

-- ── 3. THE HUNKS (old → new), sliced from the live bodies ──────────────────────────────────────
create temp table hunks_0210 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0210 values
-- (4) WAGES: THE ONE SUM, × the level, kept exact
('public.crew_wages(integer, boolean)', 1,
$h$ RETURNS bigint
$h$,
$h$ RETURNS numeric
$h$),
('public.crew_wages(integer, boolean)', 2,
$h$  return round(p_crew * public.wc_num('wage_per_crew_day')
               * (case when p_short then public.wc_num('short_rations_wage_mult') else 1 end))::bigint;
$h$,
$h$  -- 0210: × running_cost_level (running costs keep pace with 0208's goods ÷ 5), and NOT rounded: a crew of 2
  -- at 0.2 a man owes 0.4 a day, which rounded per day would be nothing for ever. public.fleet_wages.owed keeps
  -- the fraction; public.pay_wages pays whole ducats.
  return p_crew * public.wc_num('wage_per_crew_day') * public.wc_num('running_cost_level')
         * (case when p_short then public.wc_num('short_rations_wage_mult') else 1 end);
$h$),
('public.fleet_wage(uuid, boolean, integer)', 1,
$h$ RETURNS bigint
$h$,
$h$ RETURNS numeric
$h$),
('public.fleet_wage(uuid, boolean, integer)', 2,
$h$    return round(public.crew_wages(v_crew, p_short) * public.running_cost_mult(v_player))::bigint;
$h$,
$h$    -- 0210: to 4 places, not to the ducat — the day's fraction is owed (public.owe_wages), not rounded away
    return round(public.crew_wages(v_crew, p_short) * public.running_cost_mult(v_player), 4);
$h$),
('public.fleet_wage(uuid, boolean, integer)', 3,
$h$               * (1 - least(v_pct, 100) / 100.0))::bigint;
$h$,
$h$               * (1 - least(v_pct, 100) / 100.0), 4);   -- 0210: 4 places
$h$),
('public.owe_wages(uuid, bigint)', 1,
$h$CREATE OR REPLACE FUNCTION public.owe_wages(p_fleet uuid, p_wage bigint)
 RETURNS bigint
$h$,
$h$CREATE OR REPLACE FUNCTION public.owe_wages(p_fleet uuid, p_wage numeric)
 RETURNS numeric
$h$),
('public.owe_wages(uuid, bigint)', 2,
$h$  v_owed bigint;
$h$,
$h$  v_owed numeric;   -- 0210: what she owes keeps its fraction of a ducat (fleet_wages.owed is numeric)
$h$),
('public.pay_wages(uuid, uuid, bigint, uuid)', 1,
$h$                else round(public.wages_from_profit(w.owed, least(p_profit, w.visit_net - w.visit_paid)))::bigint end;
$h$,
$h$                -- 0210: WHOLE DUCATS, never past what is owed: the fraction of a ducat stays owed for the next sale
                else floor(public.wages_from_profit(w.owed, least(p_profit, w.visit_net - w.visit_paid)))::bigint end;
$h$),
('voyage.settle(uuid, timestamptz)', 1,
$h$  v_wages   bigint;
$h$,
$h$  v_wages   numeric;   -- 0210: the day's wage keeps its fraction (public.fleet_wage, public.owe_wages)
$h$),
-- (1) STORES: THE price of stores, × the level
('public.stores_cost(uuid, numeric, numeric)', 1,
$h$               * public.running_cost_mult(p_player))::bigint;
$h$,
$h$               * public.running_cost_mult(p_player)
               * public.wc_num('running_cost_level'))::bigint;   -- 0210: running costs keep pace with the goods
$h$),
-- (2) HULL REPAIR: the one charge line, × the level
('cmd.do_repair(uuid, jsonb)', 1,
$h$                  * public.running_cost_mult(f.player_id))::bigint;   -- 0114
$h$,
$h$                  * public.running_cost_mult(f.player_id)
                  * public.wc_num('running_cost_level'))::bigint;   -- 0114; 0210: × running_cost_level
$h$),
-- (3) GEAR REPAIR: the one price of one unit, × the level (item_recipe_value is the DESIGN value since 0208)
('public.unit_repair_cost(text, numeric)', 1,
$h$               * public.wc_num('gear_repair_pct'))::bigint;
$h$,
$h$               * public.wc_num('gear_repair_pct')
               * public.wc_num('running_cost_level'))::bigint;   -- 0210: the recipe is at its design value (0208)
$h$);

create or replace function pg_temp.recut_0210(p_fn text)
returns void
language plpgsql
as $$
declare
  d     record;
  v_def text;
  h     record;
  v_n   int;
  g     record;
begin
  select * into d from defs_before_0210 where fn = p_fn;
  v_def := d.def;
  for h in select * from hunks_0210 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0210(v_def, h.old);
    if v_n <> 1 then
      raise exception '0210 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  if d.redo then
    -- a return or argument type moves: drop and recreate, then the pre-image's ACL exactly (a dropped
    -- function takes its ACL with it, and a new one gets the default privileges)
    execute format('drop function %s', d.fn);
    execute v_def;
    execute format('revoke all on function %s from public, anon, authenticated, service_role', d.fn_new);
    for g in select distinct pg_get_userbyid(a.grantee) as role
               from aclexplode(nullif(d.acl, '')::aclitem[]) a
              where a.privilege_type = 'EXECUTE' and a.grantee <> 0 and pg_get_userbyid(a.grantee) <> d.owner
              order by 1 loop
      execute format('grant execute on function %s to %I', d.fn_new, g.role);
    end loop;
    if d.descr is not null then
      execute format('comment on function %s is %L', d.fn_new, d.descr);
    end if;
  else
    execute v_def;
  end if;
end $$;

select pg_temp.recut_0210(fn) from defs_before_0210 order by redo desc, fn;

comment on function public.crew_wages(integer, boolean) is
  '0086 / 0210: THE ONE SUM — crew × wage_per_crew_day × running_cost_level × (short rations: short_rations_wage_mult), '
  'exact (numeric, not rounded: the fraction is owed). Read by public.fleet_wage and public.npc_leg_lines. Server-only.';
comment on function public.owe_wages(uuid, numeric) is
  '0128 / 0210: a sea-day''s wage is OWED — added to fleet_wages.owed (numeric: the fraction of a ducat is carried), '
  'capped at wages_owed_cap_days × the day. Called by voyage.settle alone. Server-only.';

-- ── 4. THE ROWS: what is owed is in the old money ──────────────────────────────────────────────
alter table public.fleet_wages alter column owed type numeric;
update public.fleet_wages set owed = owed * public.wc_num('running_cost_level');

-- ── 5. SELF-ASSERT ──────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_uid      constant uuid := '00000000-0210-4000-8000-000000000001';
  v_n        int;
  v_m        int;
  v_d        record;
  v_h        record;
  v_pp       record;
  v_def      text;
  v_player   uuid;
  v_fleet    uuid;
  v_lis      uuid;
  v_fnc      uuid;
  v_port     uuid;
  v_voy      uuid;
  v_r        jsonb;
  v_cost     bigint;
  v_old      bigint;
  v_exact    numeric;
  v_purse0   bigint;
  v_days     int;
  v_sum      numeric;
  v_old_sum  numeric;
  v_owed     numeric;
  v_owed0    numeric;
  v_paid     bigint;
  v_points   numeric;
  v_dev      int;
  v_notes    text := '';
  v_t        timestamptz;
  v_dep      timestamptz;
  v_eta      timestamptz;
  v_ms_cw    numeric[] := '{}';
  v_ms_fw    numeric[] := '{}';
  v_ms_sc    numeric[] := '{}';
  v_ms_ur    numeric[] := '{}';
  v_ms_pf    numeric[] := '{}';
  v_ms_st    numeric[] := '{}';
  v_item     text;
  i          int;
begin
  -- (a) THE KNOB, and the knobs this file must not move
  if public.wc_num('running_cost_level') is distinct from 0.2 then
    raise exception '0210 self-assert FAIL: running_cost_level reads %, not 0.2', public.wc_num('running_cost_level');
  end if;
  if exists (select 1 from knobs_0210 k join public.world_config w on w.key = k.key where w.value is distinct from k.value)
     or (select count(*) from knobs_0210) <> 12 then
    raise exception '0210 self-assert FAIL: a knob this file must not move moved (or one is missing): %',
      (select string_agg(k.key, ', ') from knobs_0210 k join public.world_config w on w.key = k.key where w.value is distinct from k.value);
  end if;

  -- (b) GEAR: every item × three wears = round(0.2 × the exact old figure), within the rounding of the old
  select count(*) into v_n from grid_items_0210 g
   where public.unit_repair_cost(g.code, g.wear) <> round(g.exact * 0.2)
      or abs(public.unit_repair_cost(g.code, g.wear) - 0.2 * g.copy) > 0.6;
  select count(*) into v_m from grid_items_0210 g where g.copy >= 25 and public.unit_repair_cost(g.code, g.wear) < g.copy;
  if v_n <> 0 or v_m < 50 then
    raise exception '0210 self-assert FAIL: % gear repair price(s) of % are not 0.2 × the old (%  with an old price ≥ 25 fell)',
      v_n, (select count(*) from grid_items_0210), v_m;
  end if;
  -- (b) STORES: the grid, for a player and (where one exists) a merchant
  select count(*) into v_n from grid_stores_0210 g
   where public.stores_cost(g.player_id, g.w, g.f) <> round(g.exact * 0.2)
      or abs(public.stores_cost(g.player_id, g.w, g.f) - 0.2 * g.copy) > 0.6;
  if v_n <> 0 or not exists (select 1 from grid_stores_0210 g where g.copy >= 100 and public.stores_cost(g.player_id, g.w, g.f) < g.copy) then
    raise exception '0210 self-assert FAIL: % stores price(s) of % are not 0.2 × the old', v_n, (select count(*) from grid_stores_0210);
  end if;
  -- (b) WAGES: every crew 0–400, both rations, EXACTLY 0.2 × crew × the ration (no rounding)
  select count(*) into v_n from grid_crew_0210 g
   where public.crew_wages(g.n, g.s) <> g.n * 0.2 * (case when g.s then public.wc_num('short_rations_wage_mult') else 1 end);
  if v_n <> 0 or public.crew_wages(2, false) <> 0.4 or public.crew_wages(3, false) <> 0.6 or public.crew_wages(313, true) <> 93.9 then
    raise exception '0210 self-assert FAIL: % crew wage(s) of 802 are not exactly crew × 0.2 × the ration (2 → %, 3 → %, 313 short → %)',
      v_n, public.crew_wages(2, false), public.crew_wages(3, false), public.crew_wages(313, true);
  end if;

  -- (c) THE DOORS, on the probe's own house, rolled back whole
  select id into v_lis from public.ports where code = 'LIS';
  select id into v_fnc from public.ports where code = 'FNC';
  begin
    v_player := public.new_house(c_uid, 'Casa dos Custos 0210', 'PRT', 'LIS');
    select id into v_fleet from public.fleets where player_id = v_player;
    perform public.credit(v_player, 'PROBE_0210', 1000000);
    update public.ships set cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb, water_t = 0, food_t = 0 where fleet_id = v_fleet;
    if (select port_id from public.fleets where id = v_fleet) is distinct from v_lis then
      raise exception '0210 self-assert FAIL: the probe house''s fleet is not at LIS';
    end if;

    -- STORES: PROVISION FULL charges public.stores_cost, which is 0.2 × the old price
    select ducats into v_purse0 from public.players where id = v_player;
    v_r := cmd.do_provision(v_fleet, '{}'::jsonb);
    v_cost := (v_r->>'cost')::bigint;
    v_old := pg_temp.stores_cost_b0210(v_player, (v_r->>'water_t')::numeric, (v_r->>'food_t')::numeric);
    if v_old < 50 or v_cost <> round(((v_r->>'water_t')::numeric * public.wc_num('provision_water_price')
                                      + (v_r->>'food_t')::numeric * public.wc_num('provision_food_price')) * 0.2)
       or abs(v_cost - 0.2 * v_old) > 0.6
       or (select ducats from public.players where id = v_player) <> v_purse0 - v_cost then
      raise exception '0210 self-assert FAIL: PROVISION charged % for % t water / % t food (the old price %), and the purse moved %',
        v_cost, v_r->>'water_t', v_r->>'food_t', v_old, v_purse0 - (select ducats from public.players where id = v_player);
    end if;
    v_notes := v_notes || format('PROVISION FULL %s t / %s t cost %s (old %s); ', v_r->>'water_t', v_r->>'food_t', v_cost, v_old);
    -- timings: npc_provision_for and stores_cost, 8 calls each
    for i in 1 .. 8 loop
      v_t := clock_timestamp();
      perform * from public.npc_provision_for(v_fleet, 10 + i);
      v_ms_pf := v_ms_pf || round(extract(epoch from clock_timestamp() - v_t) * 1000, 2);
      v_t := clock_timestamp();
      perform public.stores_cost(v_player, 10 + i, 7 + i);
      v_ms_sc := v_ms_sc || round(extract(epoch from clock_timestamp() - v_t) * 1000, 2);
    end loop;

    -- WAGES, A SMALL CREW: 3 hands owe 0.6 a day — the exact sum of their sea-days (the old per-day rounding
    -- would owe round(0.6) = 1 a day, two thirds too much)
    update public.ships set crew = case when is_flagship then 3 else 0 end where fleet_id = v_fleet;
    v_voy := voyage.depart(v_fleet,
               voyage.segments_from_course((select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon),
                                                                     jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
                                              from public.sea_reaches a, public.sea_reaches b where a.port_id = v_lis and b.port_id = v_fnc)),
               v_lis, v_fnc, now() - interval '60 days');
    perform voyage.settle(v_fleet, now() - interval '40 days');
    if (select status from public.voyages where id = v_voy) <> 'ARRIVED' then
      raise exception '0210 self-assert FAIL: the small crew''s passage did not arrive';
    end if;
    select w.days, w.paid_days, w.rounded, w.exact into v_days, v_sum, v_old_sum, v_exact from pg_temp.wage_days_0210(v_voy, 3) w;
    v_owed := (select owed from public.fleet_wages where fleet_id = v_fleet);
    if v_days < 2 or v_owed is distinct from v_sum or v_sum <> v_exact or v_sum = v_old_sum then
      raise exception '0210 self-assert FAIL: a crew of 3 over % sea-day(s) owes % (the days'' payloads %, crew × 0.2 × ration %; rounded per day %)',
        v_days, v_owed, v_sum, v_exact, v_old_sum;
    end if;
    -- the sale pays floor(owed), and the fraction stays owed
    v_paid := public.pay_wages(v_fleet, v_fnc, 1000, null);
    if v_paid <> floor(v_sum) or (select owed from public.fleet_wages where fleet_id = v_fleet) <> v_sum - floor(v_sum) then
      raise exception '0210 self-assert FAIL: owed % paid % and left % (not floor and the fraction)', v_sum, v_paid,
        (select owed from public.fleet_wages where fleet_id = v_fleet);
    end if;
    v_notes := v_notes || format('crew 3: %s sea-days owed %s exactly (rounded per day: %s), paid %s, %s still owed; ',
                                 v_days, v_sum, v_old_sum, v_paid, v_sum - floor(v_sum));
    v_owed0 := v_sum - floor(v_sum);

    -- WAGES, A LARGE CREW: 313 hands owe 62.6 a day (93.9 on short rations), timed through voyage.settle in 8 steps
    update public.ships set crew = case when is_flagship then 313 else 0 end, water_t = 0, food_t = 0 where fleet_id = v_fleet;
    perform cmd.do_provision(v_fleet, '{}'::jsonb);
    v_dep := now() - interval '30 days';
    v_voy := voyage.depart(v_fleet,
               voyage.segments_from_course((select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon),
                                                                     jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
                                              from public.sea_reaches a, public.sea_reaches b where a.port_id = v_fnc and b.port_id = v_lis)),
               v_fnc, v_lis, v_dep);
    select eta into v_eta from public.voyages where id = v_voy;
    for i in 1 .. 8 loop
      v_t := clock_timestamp();
      -- seven steps through the passage, the eighth at now() (a storm's delay moves the eta past the seventh)
      perform voyage.settle(v_fleet, case when i < 8 then v_dep + (v_eta - v_dep) * i / 7.0 else now() end);
      v_ms_st := v_ms_st || round(extract(epoch from clock_timestamp() - v_t) * 1000, 2);
    end loop;
    if (select status from public.voyages where id = v_voy) <> 'ARRIVED' then
      raise exception '0210 self-assert FAIL: the large crew''s passage did not arrive';
    end if;
    select w.days, w.paid_days, w.rounded, w.exact into v_days, v_sum, v_old_sum, v_exact from pg_temp.wage_days_0210(v_voy, 313) w;
    v_owed := (select owed from public.fleet_wages where fleet_id = v_fleet);
    if v_days < 2 or v_owed is distinct from v_owed0 + v_sum or v_sum <> v_exact then
      raise exception '0210 self-assert FAIL: a crew of 313 over % sea-day(s) owes % (carried % + the days'' payloads %; crew × 0.2 × ration %)',
        v_days, v_owed, v_owed0, v_sum, v_exact;
    end if;
    v_paid := public.pay_wages(v_fleet, v_lis, 100, null);
    if v_paid <> least(100, floor(v_owed)) or (select owed from public.fleet_wages where fleet_id = v_fleet) <> v_owed - v_paid then
      raise exception '0210 self-assert FAIL: owed % and a profit of 100 paid % and left %', v_owed, v_paid,
        (select owed from public.fleet_wages where fleet_id = v_fleet);
    end if;
    v_notes := v_notes || format('crew 313: %s sea-days owed %s exactly (+ %s carried; rounded per day: %s), a profit of 100 paid %s; ',
                                 v_days, v_sum, v_owed0, v_old_sum, v_paid);
    -- AND A FRACTION ABOVE ONE HALF: owed 2.6 at a fresh visit, a profit of 1,000 pays 2 and leaves 0.6
    -- (rounding would pay 3 — more than she owes — and the owed >= 0 check would refuse the sale)
    update public.fleet_wages set owed = 2.6, visit_net = 0, visit_paid = 0 where fleet_id = v_fleet;
    begin
      v_paid := public.pay_wages(v_fleet, v_lis, 1000, null);
    exception when check_violation then
      raise exception '0210 self-assert FAIL: owed 2.6 and a profit of 1000 paid more than was owed (%)', sqlerrm;
    end;
    if v_paid <> 2 or (select owed from public.fleet_wages where fleet_id = v_fleet) <> 0.6 then
      raise exception '0210 self-assert FAIL: owed 2.6 and a profit of 1000 paid % and left %, not 2 and 0.6', v_paid,
        (select owed from public.fleet_wages where fleet_id = v_fleet);
    end if;
    v_notes := v_notes || 'owed 2.6 paid 2 and left 0.6; ';

    -- REPAIR, THE HULL: at LIS (a yard), half her hull gone, no worn gear — 0.2 × the old hull price. Docked
    -- there by hand: a storm on the passage may have left her unable to sail, and this probe prices a repair.
    update public.fleets set status = 'DOCKED', port_id = v_lis, lat = null, lon = null where id = v_fleet;
    update public.fitted_units u set wear = 0 from public.ships s where s.id = u.ship_id and s.fleet_id = v_fleet;
    update public.ships s set durability = c.durability * 0.5 from public.ship_classes c where c.id = s.class_id and s.fleet_id = v_fleet;
    select coalesce(sum(c.durability - s.durability), 0) into v_points
      from public.ships s join public.ship_classes c on c.id = s.class_id where s.fleet_id = v_fleet;
    select p.dev_industry into v_dev from public.ports p where p.id = v_lis;
    select ducats into v_purse0 from public.players where id = v_player;
    v_r := cmd.do_repair(v_fleet, '{}'::jsonb);
    v_cost := (v_r->>'cost')::bigint;
    v_old := round(v_points * public.wc_num('repair_rate_per_point') * (1 - v_dev * 0.01) * public.running_cost_mult(v_player));
    if v_old < 25 or v_r ? 'gear'
       or v_cost <> round(v_points * public.wc_num('repair_rate_per_point') * (1 - v_dev * 0.01) * public.running_cost_mult(v_player) * 0.2)
       or abs(v_cost - 0.2 * v_old) > 0.6
       or (select ducats from public.players where id = v_player) <> v_purse0 - v_cost then
      raise exception '0210 self-assert FAIL: REPAIR of % points charged % (the old price %), the purse moved %: %',
        v_points, v_cost, v_old, v_purse0 - (select ducats from public.players where id = v_player), v_r;
    end if;
    v_notes := v_notes || format('REPAIR %s points cost %s (old %s); ', round(v_points, 1), v_cost, v_old);

    -- timings: the wage sums, 8 calls each
    for i in 1 .. 8 loop
      v_t := clock_timestamp();
      perform public.crew_wages(i * 37, i % 2 = 0);
      v_ms_cw := v_ms_cw || round(extract(epoch from clock_timestamp() - v_t) * 1000, 2);
      v_t := clock_timestamp();
      perform public.fleet_wage(v_fleet, i % 2 = 0, i * 37);
      v_ms_fw := v_ms_fw || round(extract(epoch from clock_timestamp() - v_t) * 1000, 2);
    end loop;
    if public.fleet_wage(v_fleet, false, 3) <> 0.6 or public.fleet_wage(v_fleet, true, 313) <> 93.9 then
      raise exception '0210 self-assert FAIL: fleet_wage reads % / %, not 0.6 / 93.9', public.fleet_wage(v_fleet, false, 3), public.fleet_wage(v_fleet, true, 313);
    end if;

    raise exception 'ROLLBACK_0210';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0210' then raise; end if;
  end;
  if exists (select 1 from public.players where auth_uid = c_uid) then
    raise exception '0210 self-assert FAIL: the probe house was not rolled back';
  end if;
  -- timings of unit_repair_cost (outside the probe: a real item, ordered)
  select code into v_item from public.item_kinds order by code limit 1;
  for i in 1 .. 8 loop
    v_t := clock_timestamp();
    perform public.unit_repair_cost(v_item, 10 * i);
    v_ms_ur := v_ms_ur || round(extract(epoch from clock_timestamp() - v_t) * 1000, 2);
  end loop;

  -- (d) WHAT IS OWED × 0.2, every row; ship prices and every purse unmoved
  select count(*) into v_n from owed_0210 o left join public.fleet_wages w on w.fleet_id = o.fleet_id
   where w.fleet_id is null or w.owed <> o.owed * 0.2;
  if v_n <> 0 or (select count(*) from public.fleet_wages) <> (select count(*) from owed_0210) then
    raise exception '0210 self-assert FAIL: % of % owed wage row(s) are not 0.2 × what was owed', v_n, (select count(*) from owed_0210);
  end if;
  if (select data_type from information_schema.columns where table_schema = 'public' and table_name = 'fleet_wages' and column_name = 'owed') <> 'numeric' then
    raise exception '0210 self-assert FAIL: fleet_wages.owed is not numeric';
  end if;
  if exists (select 1 from purse_0210 p0 join public.players p on p.id = p0.id where p.ducats <> p0.ducats)
     or (select count(*) from public.players) <> (select count(*) from purse_0210)
     or (select coalesce(sum(ducats), 0) from public.hull_recipes) <> (select d from yard_0210) then
    raise exception '0210 self-assert FAIL: a purse or a ship''s price moved';
  end if;

  -- (e) THE RE-CUT reverses to its pre-image; ACL / volatility / definer / config as before
  for v_d in select * from defs_before_0210 loop
    if v_d.redo and v_d.fn <> v_d.fn_new and to_regprocedure(v_d.fn) is not null then
      raise exception '0210 self-assert FAIL: the old form % is still there beside %', v_d.fn, v_d.fn_new;
    end if;
    v_def := replace(pg_get_functiondef(v_d.fn_new::regprocedure), E'\r', '');
    for v_h in select * from hunks_0210 where fn = v_d.fn order by n desc loop
      if pg_temp.occurs_0210(v_def, v_h.new) <> 1 then
        raise exception '0210 self-assert FAIL: hunk % of % is not in the new body exactly once', v_h.n, v_d.fn;
      end if;
      v_def := replace(v_def, v_h.new, v_h.old);
    end loop;
    if v_def <> v_d.def then
      raise exception '0210 self-assert FAIL: % does not reverse to its pre-image', v_d.fn;
    end if;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef,
           coalesce(pr.proconfig::text, '') as cfg, pg_get_userbyid(pr.proowner) as owner
      into v_pp from pg_proc pr where pr.oid = v_d.fn_new::regprocedure;
    if v_pp.acl <> v_d.acl or v_pp.vol <> v_d.vol or v_pp.secdef <> v_d.secdef or v_pp.cfg <> v_d.cfg or v_pp.owner <> v_d.owner then
      raise exception '0210 self-assert FAIL: % changed its ACL (% → %), volatility, definer, config or owner', v_d.fn, v_d.acl, v_pp.acl;
    end if;
    if exists (select 1 from unnest(array['anon', 'authenticated']) rl(role)
                where has_function_privilege(rl.role, v_d.fn_new, 'execute')) then
      raise exception '0210 self-assert FAIL: a client can reach %', v_d.fn_new;
    end if;
  end loop;
  if (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0210 self-assert FAIL: a wall moved';
  end if;

  raise notice '0210 self-assert ok: STORES, REPAIRS AND WAGES COST A FIFTH (running_cost_level 0.2). GRIDS: % gear prices (every item × 3 wears), % stores prices, 802 crew wages = 0.2 × the old arithmetic (wages exact: crew 2 → 0.4, 3 → 0.6, 313 short → 93.9). DOORS (probe house, rolled back): %OWED: % row(s) × 0.2 (% → %), fleet_wages.owed numeric. 8 bodies reverse, ACLs kept, no client reach; 0208 knobs, ship prices and purses unmoved. ms ×8: crew_wages %, fleet_wage %, stores_cost %, unit_repair_cost %, npc_provision_for %, voyage.settle (8 steps of one passage) %.',
    (select count(*) from grid_items_0210), (select count(*) from grid_stores_0210), v_notes,
    (select count(*) from owed_0210), (select coalesce(sum(owed), 0) from owed_0210), (select coalesce(sum(owed), 0) from public.fleet_wages),
    v_ms_cw, v_ms_fw, v_ms_sc, v_ms_ur, v_ms_pf, v_ms_st;
end $$;
