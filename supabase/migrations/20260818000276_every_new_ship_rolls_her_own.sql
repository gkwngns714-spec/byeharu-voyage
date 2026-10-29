-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0276 — EVERY NEW SHIP ROLLS HER OWN STATS   (owner row 222; docs/SHIP_STORES_AND_VARIETY.md §2, §5 V1+V3)
--
-- THE OWNER'S WORDS (row 222, 2026-10-26): *"all ships when made or bought will not have same stats
-- even though its name is same, it should have variety (randomness) too."* — a hull built or bought
-- rolls her own speed, hold, stores, hull, crew max and handling around her class's figures, fixed
-- for life. This file is the VARIETY half (V1 + V3 of the design): the stores-space half (row 221,
-- V2 of the design) is a SEPARATE slice and is NOT built here — the six factors include `stores`
-- (rolled and stored now, lit when V2 adds `ship_classes.stores`), but nothing here reads it yet.
--
-- THE RULES, AS DATA (the hard constraint): every band is a ROW in the NEW `public.ship_variety`
-- (class_code '' = the default band; a class with its own row overrides, stat by stat). NO band
-- number is written in a function body: the tier cut, the Poor and Fine spans, the normal ± and the
-- grade cut all come from the table, so adding a class never needs code (no row, no code — the
-- default band answers).
--
-- DETERMINISM: the seed of a hull's roll is HER OWN ID (drawn before the insert) plus a FIXED
-- server-side salt inside `public.ship_roll_u` — the draw is md5, never random(): the same id always
-- answers the same six factors, on any machine, for ever, and a probe reproduces a ship's stored
-- roll from her id alone. The factors are STORED on the ship row (fixed for life); nothing else
-- writes them.
--
-- ONE AUTHORITY: `public.ship_base(ship)` = class × her roll, the only place a class column meets a
-- ship. Every live reader of the five rolled class columns (hold, speed_kn, durability, crew_max,
-- handling) is re-cut onto it below, and the self-assert scans every body in the four schemas to
-- prove no other reader remains. The roll happens at ONE place — `public.commission_ship` (0096's
-- one ship insert; every creator goes through it) — and no client code rolls: the client prints
-- what `world.ship_view` serves (`roll`, `grade`, `class_*`).
--
-- EXISTING SHIPS KEEP THEIR CLASS STATS — said plainly: this file backfills NOTHING. Every hull
-- afloat keeps roll 1.000 (the columns' default), so her base is her class's figures to the digit,
-- and the self-assert proves world.ship_stats and world.ship_view answer the pre-image, byte for
-- byte, for every hull and every fleet in the world. Only hulls commissioned AFTER this file rolls.
--
-- THE SIX FACTORS: hold, speed, stores, durability (hull), crew_max, handling. Not rolled (the
-- design §2.1): crew needed, draft, guns and the combat stats — draft/armour/attack/accuracy/
-- reach/sighting/wave stay class columns, read where they always were. Clamps (design §2.1): crew
-- max is never below what the class needs (stored on the factor, so ship_base reads one number);
-- hold, hull and handling are floored to whole numbers and speed to 0.01 kn — their class scales,
-- which is also what keeps the byte-identity for roll 1.000. A famous hull (class_profile.tech
-- 'F', 0165) is the ship of the legend: 1.000 always. A founding hull (crewed AND flagship —
-- public.new_house and an NPC's first hull) never starts Poor: every factor is raised to 1.000 at
-- least. The grade word is DERIVED, never stored: public.ship_grade = the mean of her six factors
-- against the band's grade_cut ('fine' at +cut, 'poor' at −cut, else null).
--
-- SUPERSEDE (supabase/migrations/README.md:43-48). This file re-cuts TWELVE live functions, by
-- hunks sliced from the LIVE bodies (each hunk asserted to occur exactly once and to reverse to
-- its pre-image; ACL, volatility, definer and search_path unmoved; the md5 of every OTHER function
-- in the four schemas asserted unmoved). It re-cuts, and what changes in each:
--   * public.commission_ship(uuid, uuid, text, text, boolean, boolean) — the ONE ship insert
--     (0096, never re-cut since): gains the roll. Two hunks: the signature gains `p_ship uuid
--     default null` (only a test names it, so a probe's hull has a FIXED id and a reproducible
--     roll — live play passes nothing), and the body rolls before the insert and writes the six
--     `roll_*` columns. The starting durability is her rolled max (design §2.2).
--   * world.ship_stats(uuid) — 0124's computation, as re-cut by 0133, 0149, 0158, 0163, 0168,
--     0215 (both branches, skills on and off): the base of hold, speed, handling and durability
--     reads public.ship_base (draft, armour, attack, accuracy, reach, sighting, wave stay class).
--   * world.ship_view(uuid) — 0124's builder, as re-cut by 0132, 0133, 0149, 0157, 0163, 0215:
--     max_durability, crew_max, hold_rated and speed_rated read her base; NEW keys `roll` (her six
--     factors), `grade` (her word), and `class_hold`/`class_speed`/`class_durability`/
--     `class_crew_max`/`class_handling` (the class averages, for the tile's "Barca avg").
--   * cmd.do_hire(uuid, jsonb) — 0007's door, as re-cut by 0154: berths and the fill loop read her
--     rolled crew max.
--   * cmd.do_repair(uuid, jsonb) — 0007's door, as re-cut by 0142, 0158, 0181, 0210: the repair
--     ceiling is her rolled max.
--   * public.fleet_repair_due(uuid, numeric) — 0181: the points to mend read her rolled max.
--   * public.ship_set_bonus(uuid) — 0163: the set's per-cent base (hold, speed, handling,
--     durability) is her base; the other five stats stay class.
--   * voyage.ship_speed_at(uuid, numeric) — 0203's body (as re-cut by 0250): the hull-speed
--     factor divides by her rolled max.
--   * voyage.settle(uuid, timestamptz) — 0027's settle, as re-cut by 0059, 0067, 0122, 0128,
--     0142, 0154, 0155, 0168, 0189, 0210, 0213, 0237: the STORM and SHOAL_WATER hull loops take
--     her rolled max.
--   * voyage.fight(uuid, int, uuid, numeric) — 0189: the hull handed to fight_resolve carries her
--     rolled max. (voyage.fight_resolve itself reads only the RAIDERS' class — untouched.)
--   * world.building_yard(uuid) — 0072's yard, as re-cut by 0130, 0133, 0135, 0159, 0165, 0184:
--     each hull gains `variety_pct` — how far (per cent, ±) a new hull of this class may stray
--     from the figures shown, from the same rows the roll draws. The yard itself stays on the
--     class: it is the catalogue, not a ship.
--   * world.ship_budget(uuid) — 0132's reading, as re-cut by 0133, 0149, 0151, 0163: her Hands
--     max reads her rolled crew max (the Deck half stays the class's).
-- IT IS A NO-OP WHEN THE NEW INPUT IS ABSENT: every hull afloat has every roll = 1.000 (asserted:
-- no backfill), and then each re-cut body answers exactly its pre-image — world.ship_stats and
-- world.ship_view byte-identical for every hull and every fleet (asserted), the repair ceiling,
-- berths, budgets, storm and fight losses all the class figures they always were. The roll only
-- speaks for a hull commissioned after this file.
--
-- WHAT THIS FILE DOES NOT DO (said plainly): it does not build the stores SPACE (row 221): no
-- `ship_classes.stores`, no stores capacity, no `'stores'` in ship_base — the row-221 slice adds
-- them, and ship_base's stores line joins beside these five. It does not roll existing ships, and
-- it does not change the build price: a better roll is luck, not goods (design §4).
--
-- PROD CHECKS (before the push; read-only; in the PR body): the twelve live bodies are the ones the
-- hunks were cut against (md5 of pg_get_functiondef, listed in the dev-log); every hull afloat
-- reads a class-built ship with no roll column yet (they are added by this very file). AFTER THE
-- DEPLOY: no live figure moves (every roll is 1.000) — the first reading that anything moved is a
-- NEW hull's own roll; the after-check watches new human builds (dev-log §After-check).
--
-- VERSION: 0276 (prod head 0272 at authoring; 0273/0274/0275 apply before this one, in number
-- order). Depends on: 0002, 0004, 0007, 0017, 0027, 0067, 0072, 0096, 0124, 0130, 0132, 0133,
-- 0142, 0149, 0151, 0154, 0155, 0157, 0158, 0159, 0163, 0165, 0168, 0181, 0184, 0189, 0203,
-- 0210, 0213, 0215, 0237, 0250.

-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
  if to_regprocedure('public.commission_ship(uuid,uuid,text,text,boolean,boolean)') is null
     or to_regprocedure('world.ship_stats(uuid)') is null
     or to_regprocedure('world.ship_view(uuid)') is null
     or to_regclass('public.class_profile') is null then
    raise exception '0276 refuses: 0096/0124/0130 are not in this world';
  end if;
  if to_regprocedure('public.ship_base(uuid)') is not null
     or to_regprocedure('public.ship_roll(uuid,text)') is not null
     or to_regclass('public.ship_variety') is not null then
    raise exception '0276 refuses: ship_base, ship_roll or ship_variety already exists — this has been applied once';
  end if;
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'ships' and column_name = 'roll_hold') then
    raise exception '0276 refuses: ships.roll_hold already exists — this has been applied once';
  end if;
end $guard$;

create or replace function pg_temp.occurs_0276(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- ── 0. AS FOUND — the twelve bodies, and the whole world, before anything moves ─────────────────
create temp table defs_before_0276 (fn text, fn_after text, canon text, def text, acl text, vol text, secdef boolean, cfg text);

insert into defs_before_0276 (fn, fn_after, canon, def, acl, vol, secdef, cfg)
select f.fn, f.fn_after,
       (select n.nspname || '.' || p.proname || '(' || oidvectortypes(p.proargtypes) || ')'
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace where p.oid = f.fn::regprocedure),
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', ''),
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), ''),
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure),
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure),
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure)
  from (values
    ('public.commission_ship(uuid,uuid,text,text,boolean,boolean)',
     'public.commission_ship(uuid,uuid,text,text,boolean,boolean,uuid)'),
    ('world.ship_stats(uuid)', null),
    ('world.ship_view(uuid)', null),
    ('cmd.do_hire(uuid,jsonb)', null),
    ('cmd.do_repair(uuid,jsonb)', null),
    ('public.fleet_repair_due(uuid,numeric)', null),
    ('public.ship_set_bonus(uuid)', null),
    ('voyage.ship_speed_at(uuid,numeric)', null),
    ('voyage.settle(uuid,timestamptz)', null),
    ('voyage.fight(uuid,int,uuid,numeric)', null),
    ('world.building_yard(uuid)', null),
    ('world.ship_budget(uuid)', null)) f(fn, fn_after);

-- Every OTHER function in the four schemas: one md5 over the lot, so a body that moves without
-- being named here is caught. commission_ship is excluded by name (its signature changes on
-- purpose), the six functions this file MINTS by name (they did not exist before), the rest by
-- their regprocedure.
create temp table before_0276 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select max(s.created_at) from public.ships s) as ships_mark,
       (select count(*) from public.ships) as ships_n,
       (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
           and (n.nspname, p.proname) not in (('public', 'commission_ship'),
                                              ('public', 'ship_base'), ('public', 'ship_roll'),
                                              ('public', 'ship_roll_u'), ('public', 'ship_grade'),
                                              ('public', 'ship_variety_row'), ('public', 'ship_variety_band'))
           and p.oid not in (select to_regprocedure(fn) from defs_before_0276 where fn_after is null)) as others_md5;

-- THE PRE-IMAGE OF EVERY HULL AND EVERY FLEET IN THE WORLD, merchants included, taken now.
create temp table stats_before_0276 on commit drop as
select s.id as ship_id, world.ship_stats(s.id)::text as v from public.ships s;

create temp table views_before_0276 on commit drop as
select s.id as ship_id, world.ship_view(s.id)::text as v from public.ships s;

create temp table fleets_before_0276 on commit drop as
select f.id as fleet_id,
       (select coalesce(jsonb_agg(world.ship_view(s.id) order by s.is_flagship desc, s.name), '[]'::jsonb)::text
          from public.ships s where s.fleet_id = f.id) as ships
  from public.fleets f;

-- THE READER SCAN BEFORE THE RE-CUT (positive control for the after-scan below): every body in the
-- four schemas that joins ship_classes with public.ships AND names one of the five rolled class
-- columns by the alias every reader here uses. The name is CANONICAL (schema + oidvectortypes, the
-- bare types), so the comparison never depends on the session's search_path or the argument names.
create temp table scan_before_0276 on commit drop as
select n.nspname || '.' || p.proname || '(' || oidvectortypes(p.proargtypes) || ')' as fn
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
   and pg_get_functiondef(p.oid) like '%ship_classes%'
   and pg_get_functiondef(p.oid) like '%public.ships%'
   and (pg_get_functiondef(p.oid) like '%c.hold%'
     or pg_get_functiondef(p.oid) like '%c.speed_kn%'
     or pg_get_functiondef(p.oid) like '%c.durability%'
     or pg_get_functiondef(p.oid) like '%c.crew_max%'
     or pg_get_functiondef(p.oid) like '%c.handling%');

-- ── 1. THE SIX FACTORS, ON THE SHIP ──────────────────────────────────────────────────────────────
alter table public.ships
  add column roll_speed    numeric(4,3) not null default 1.000 check (roll_speed    between 0.001 and 9.999),
  add column roll_hold     numeric(4,3) not null default 1.000 check (roll_hold     between 0.001 and 9.999),
  add column roll_stores   numeric(4,3) not null default 1.000 check (roll_stores   between 0.001 and 9.999),
  add column roll_hull     numeric(4,3) not null default 1.000 check (roll_hull     between 0.001 and 9.999),
  add column roll_crew     numeric(4,3) not null default 1.000 check (roll_crew     between 0.001 and 9.999),
  add column roll_handling numeric(4,3) not null default 1.000 check (roll_handling between 0.001 and 9.999);

comment on column public.ships.roll_speed is
  '0276: her speed factor, drawn once at her commission (public.commission_ship) from public.ship_variety, fixed for life. 1.000 = the class''s figure (every hull built before 0276, and every famous ship). Nothing else writes it.';
comment on column public.ships.roll_hold is
  '0276: her hold factor — rolled and stored with the rest; read by public.ship_base.';
comment on column public.ships.roll_stores is
  '0276: her stores factor — rolled and stored now, READ BY NOTHING until the stores-space slice (row 221) adds ship_classes.stores and ship_base''s stores line.';
comment on column public.ships.roll_hull is
  '0276: her hull (max durability) factor — read by public.ship_base.';
comment on column public.ships.roll_crew is
  '0276: her crew-max factor, clamped at the commission to never read below what the class needs (design §2.1) — read by public.ship_base.';
comment on column public.ships.roll_handling is
  '0276: her handling factor — read by public.ship_base.';

-- ── 2. THE BANDS, AS ROWS ────────────────────────────────────────────────────────────────────────
-- THE HARD CONSTRAINT: the ranges are ROWS, never numbers in a function body. class_code '' is the
-- default band (a class with no row of its own reads it); a class with a row overrides, stat by
-- stat. Adding a class needs no code AND no row.
create table public.ship_variety (
  class_code text not null,
  stat       text not null check (stat in ('hold', 'speed', 'stores', 'durability', 'crew_max', 'handling')),
  poor_cut   numeric(4,3) not null check (poor_cut between 0 and 1),
  fine_cut   numeric(4,3) not null check (fine_cut between 0 and 1),
  poor_lo    numeric(4,3) not null check (poor_lo between 0 and 1),
  poor_hi    numeric(4,3) not null check (poor_hi between 0 and 1),
  fine_lo    numeric(4,3) not null check (fine_lo between 0 and 1),
  fine_hi    numeric(4,3) not null check (fine_hi between 0 and 1),
  normal_pc  numeric(4,3) not null check (normal_pc between 0 and 1),
  grade_cut  numeric(4,3) not null check (grade_cut between 0 and 0.500),
  primary key (class_code, stat),
  constraint ship_variety_bands_sane check (poor_lo <= poor_hi and fine_lo <= fine_hi and poor_cut <= fine_cut)
);
comment on table public.ship_variety is
  '0276: THE BANDS a new hull''s roll draws from (docs/SHIP_STORES_AND_VARIETY.md §2.1). One tier draw: below '
  'poor_cut every factor is 1 − (poor_lo..poor_hi); above fine_cut every factor is 1 + (fine_lo..fine_hi); between '
  'them every factor is the bell 1 ± normal_pc. grade_cut bounds public.ship_grade''s word. class_code '''' = the '
  'default band; a class with its own row overrides stat by stat (public.ship_variety_row). No knob: these are '
  'authored rows, read at a hull''s commission and never by the clock.';
alter table public.ship_variety enable row level security;

insert into public.ship_variety (class_code, stat, poor_cut, fine_cut, poor_lo, poor_hi, fine_lo, fine_hi, normal_pc, grade_cut)
select '', s, 0.050, 0.950, 0.080, 0.200, 0.080, 0.200, 0.120, 0.070
  from unnest(array['hold', 'speed', 'stores', 'durability', 'crew_max', 'handling']) s;

-- ── 3. THE ONE DRAW ──────────────────────────────────────────────────────────────────────────────
create function public.ship_roll_u(p_tag text, p_seed uuid)
returns numeric
language sql
immutable
security definer
set search_path = public, pg_temp
as $$
  -- 0276: ONE UNIFORM from the seed — the first 32 bits of md5(the server-side salt ‖ seed ‖ tag).
  -- The salt is the FIXED server-side seed the brief names, so a given ship id always draws the
  -- same numbers on any machine for ever — no random(): a re-run cannot change the roll. The two
  -- constants are the md5's hex space (2^32) and the bell's three uniforms — not stat ranges (those
  -- are rows, §2).
  select ('x' || left(md5('byeharu-voyage.ship-variety.v1' || p_seed::text || ':' || p_tag), 8))::bit(32)::bigint::numeric
           / 4294967296::numeric
$$;
revoke all on function public.ship_roll_u(text, uuid) from public, anon, authenticated;

create function public.ship_variety_row(p_class text, p_stat text)
returns setof public.ship_variety
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0276: THE ONE READING of a (class, stat) band — the class's own row, else the default ('').
  select v.*
    from public.ship_variety v
   where v.stat = p_stat and v.class_code = p_class
   union all
  select v.*
    from public.ship_variety v
   where v.stat = p_stat and v.class_code = ''
     and not exists (select 1 from public.ship_variety v2
                      where v2.stat = p_stat and v2.class_code = p_class)
$$;
revoke all on function public.ship_variety_row(text, text) from public, anon, authenticated;

create function public.ship_roll(p_seed uuid, p_class text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0276: THE ROLL (docs/SHIP_STORES_AND_VARIETY.md §2) — six factors, one per stat, drawn from
-- public.ship_variety's bands (this body names NO band number; the ranges are rows). One tier draw
-- decides the band for all six: below poor_cut every factor is 1 − (poor_lo..poor_hi); above
-- fine_cut every factor is 1 + (fine_lo..fine_hi); between them every factor is the bell
-- 1 + normal_pc × (u1 + u2 + u3 − 1.5) / 1.5 — three uniforms, so ± normal_pc with middling draws
-- common. THE SEED IS THE SHIP'S OWN ID plus the fixed salt inside public.ship_roll_u: the same
-- seed and the same bands always answer the same factors, so a probe reproduces a ship's stored
-- roll from her id alone. Written ONCE, at her commission, by public.commission_ship.
declare
  vr     public.ship_variety%rowtype;
  v_tier numeric;
  v_u    numeric;
  v_f    numeric;
  v_stat text;
  v_out  jsonb := '{}'::jsonb;
begin
  v_tier := public.ship_roll_u('tier', p_seed);
  foreach v_stat in array array['hold', 'speed', 'stores', 'durability', 'crew_max', 'handling'] loop
    select * into vr from public.ship_variety_row(p_class, v_stat);
    if vr is null then
      raise exception 'E_NO_VARIETY: no variety band for class "%" stat "%"', p_class, v_stat using errcode = 'P0001';
    end if;
    v_u := public.ship_roll_u(v_stat || ':band', p_seed);
    if v_tier < vr.poor_cut then
      v_f := 1 - (vr.poor_lo + v_u * (vr.poor_hi - vr.poor_lo));
    elsif v_tier > vr.fine_cut then
      v_f := 1 + (vr.fine_lo + v_u * (vr.fine_hi - vr.fine_lo));
    else
      v_f := 1 + vr.normal_pc * (public.ship_roll_u(v_stat || ':1', p_seed)
                               + public.ship_roll_u(v_stat || ':2', p_seed)
                               + public.ship_roll_u(v_stat || ':3', p_seed) - 1.5) / 1.5;
    end if;
    v_out := v_out || jsonb_build_object(v_stat, round(greatest(0.001, least(9.999, v_f)), 3));
  end loop;
  return v_out;
end $$;
revoke all on function public.ship_roll(uuid, text) from public, anon, authenticated;

create function public.ship_variety_band(p_class text)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0276: THE YARD'S ONE LINE — the normal band's ± per cent for this class, the widest of its six
  -- stats, from the same rows the roll draws (the class's own, else the default).
  select coalesce(max(vr.normal_pc) * 100, 0)
    from unnest(array['hold', 'speed', 'stores', 'durability', 'crew_max', 'handling']) st(stat)
    cross join lateral public.ship_variety_row(p_class, st.stat) vr
$$;
revoke all on function public.ship_variety_band(text) from public, anon, authenticated;

create function public.ship_grade(p_ship uuid)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0276: HER GRADE WORD, derived and never stored (§2.1): the mean of her six stored factors
  -- against the class band's own grade_cut. 'fine' at +grade_cut or above, 'poor' at −grade_cut or
  -- below, null between (a standard hull shows no word). No such ship: null.
  select case when x.m is null then null
              when x.m >= 1 + vr.grade_cut then 'fine'
              when x.m <= 1 - vr.grade_cut then 'poor' end
    from (select (s.roll_hold + s.roll_speed + s.roll_stores + s.roll_hull + s.roll_crew + s.roll_handling) / 6 as m,
                 c.code as code
            from public.ships s join public.ship_classes c on c.id = s.class_id
           where s.id = p_ship) x
    cross join lateral public.ship_variety_row(x.code, 'hold') vr
$$;
revoke all on function public.ship_grade(uuid) from public, anon, authenticated;

create function public.ship_base(p_ship uuid)
returns table(hold numeric, speed numeric, durability numeric, crew_max numeric, handling numeric)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0276: A HULL'S OWN BASE — class × HER roll, THE ONE PLACE a class column meets a ship. The roll
  -- was written at her commission (public.commission_ship) and nothing else writes it, so this
  -- answer is fixed for life. Hold, hull and handling are floored to whole numbers (their class
  -- scale), speed to 0.01 kn; crew max is floored and never below what the class needs (§2.1's
  -- clamp, kept on the stored factor). No such ship: no row. THE STORES LINE JOINS WHEN THE STORES
  -- SPACE SLICE LANDS (row 221): ship_classes.stores × roll_stores, beside these five.
  select floor(c.hold       * s.roll_hold),
         round(c.speed_kn   * s.roll_speed, 2),
         floor(c.durability * s.roll_hull),
         greatest(c.crew_required, floor(c.crew_max * s.roll_crew)),
         floor(c.handling   * s.roll_handling)
    from public.ships s join public.ship_classes c on c.id = s.class_id
   where s.id = p_ship
$$;
revoke all on function public.ship_base(uuid) from public, anon, authenticated;

-- ── 4. THE HUNKS (old = verbatim from the live bodies; new = what replaces it) ──────────────────
create temp table hunks_0276 (fn text, n int, old text, new text, primary key (fn, n));

insert into hunks_0276 values
-- ── public.commission_ship: the signature gains the probe's id, the body gains the roll ─────────
('public.commission_ship(uuid,uuid,text,text,boolean,boolean)', 1,
$h$CREATE OR REPLACE FUNCTION public.commission_ship(p_player uuid, p_fleet uuid, p_class_code text, p_name text, p_flagship boolean, p_crewed boolean)
 RETURNS uuid$h$,
$h$CREATE OR REPLACE FUNCTION public.commission_ship(p_player uuid, p_fleet uuid, p_class_code text, p_name text, p_flagship boolean, p_crewed boolean, p_ship uuid DEFAULT NULL::uuid)
 RETURNS uuid$h$),

('public.commission_ship(uuid,uuid,text,text,boolean,boolean)', 2,
$h$declare
  c      public.ship_classes%rowtype;
  v_ship uuid;
begin
  select * into c from public.ship_classes where code = p_class_code;
  if c.id is null then
    raise exception 'E_NO_SUCH_CLASS: no ship is called "%"', coalesce(p_class_code, '') using errcode = 'P0001';
  end if;
  insert into public.ships (player_id, fleet_id, class_id, name, durability, crew,
                            water_t, food_t, store_ratio, is_flagship)
  values (p_player, p_fleet, c.id, p_name, c.durability,
          case when p_crewed then c.crew_required else 0 end,
          case when p_crewed then 2.400 else 0 end,
          case when p_crewed then 1.800 else 0 end,
          public.wc_num('store_ratio_default'), coalesce(p_flagship, false))
  returning id into v_ship;
  return v_ship;
end $function$$h$,
$h$declare
  c      public.ship_classes%rowtype;
  v_ship uuid;
  v_roll jsonb;   -- 0276: her six factors, rolled here at her commission and fixed for life
begin
  select * into c from public.ship_classes where code = p_class_code;
  if c.id is null then
    raise exception 'E_NO_SUCH_CLASS: no ship is called "%"', coalesce(p_class_code, '') using errcode = 'P0001';
  end if;
  -- 0276: THE ROLL (docs/SHIP_STORES_AND_VARIETY.md §2). The seed is HER OWN ID (drawn before the
  -- insert) plus the fixed server-side salt inside public.ship_roll — the same id always reads the
  -- same factors, and a probe reproduces them from the id alone. A famous hull (class_profile.tech
  -- 'F', 0165) is the ship of the legend: 1.000, always. A founding hull (crewed AND flagship —
  -- public.new_house, and an NPC house's first) never starts Poor: each factor is raised to 1.000
  -- at least. The crew factor is then clamped to never read below what the class needs (§2.1).
  -- Nothing else ever writes the roll.
  v_ship := coalesce(p_ship, gen_random_uuid());   -- p_ship: only a probe names it (a fixed id = a reproducible roll)
  v_roll := case when exists (select 1 from public.class_profile cp
                               where cp.class_code = c.code and cp.tech = 'F')
                 then null else public.ship_roll(v_ship, c.code) end;
  v_roll := coalesce(v_roll, jsonb_build_object(
    'hold', 1.000, 'speed', 1.000, 'stores', 1.000,
    'durability', 1.000, 'crew_max', 1.000, 'handling', 1.000));
  if p_crewed and coalesce(p_flagship, false) then
    select jsonb_object_agg(e.key, greatest((e.value)::numeric, 1.000)) into v_roll
      from jsonb_each(v_roll) e;
  end if;
  v_roll := jsonb_set(v_roll, '{crew_max}',
             to_jsonb(greatest((v_roll->>'crew_max')::numeric,
                               ceil(c.crew_required::numeric / c.crew_max * 1000) / 1000)));
  insert into public.ships (id, player_id, fleet_id, class_id, name, durability, crew,
                            water_t, food_t, store_ratio, is_flagship,
                            roll_speed, roll_hold, roll_stores, roll_hull, roll_crew, roll_handling)
  values (v_ship, p_player, p_fleet, c.id, p_name,
          c.durability * (v_roll->>'durability')::numeric,
          case when p_crewed then c.crew_required else 0 end,
          case when p_crewed then 2.400 else 0 end,
          case when p_crewed then 1.800 else 0 end,
          public.wc_num('store_ratio_default'), coalesce(p_flagship, false),
          (v_roll->>'speed')::numeric, (v_roll->>'hold')::numeric, (v_roll->>'stores')::numeric,
          (v_roll->>'durability')::numeric, (v_roll->>'crew_max')::numeric, (v_roll->>'handling')::numeric)
  returning id into v_ship;
  return v_ship;
end $function$$h$),

-- ── cmd.do_hire: berths and the fill loop read her rolled crew max ──────────────────────────────
('cmd.do_hire(uuid,jsonb)', 1,
$h$  select coalesce(sum(c.crew_max - s.crew), 0) into v_room
    from public.ships s join public.ship_classes c on c.id = s.class_id where s.fleet_id = p_fleet;$h$,
$h$  -- 0276: her own rolled max — as a scalar subselect, because an aggregate cannot hold a
  -- set-returning call.
  select coalesce(sum((select sb.crew_max from public.ship_base(s.id) sb) - s.crew), 0) into v_room
    from public.ships s where s.fleet_id = p_fleet;$h$),

('cmd.do_hire(uuid,jsonb)', 2,
$h$  for r in select s.id, c.crew_max - s.crew as room
             from public.ships s join public.ship_classes c on c.id = s.class_id
            where s.fleet_id = p_fleet order by room desc loop$h$,
$h$  for r in select s.id, (public.ship_base(s.id)).crew_max - s.crew as room
             from public.ships s
            where s.fleet_id = p_fleet order by room desc loop$h$),

-- ── cmd.do_repair: the repair ceiling is her rolled max ──────────────────────────────────────────
('cmd.do_repair(uuid,jsonb)', 1,
$h$  update public.ships s set durability = greatest(s.durability, c.durability * v_to / 100)
    from public.ship_classes c where c.id = s.class_id and s.fleet_id = p_fleet;$h$,
$h$  update public.ships s set durability = greatest(s.durability, (public.ship_base(s.id)).durability * v_to / 100)
   where s.fleet_id = p_fleet;   -- 0276: her own rolled max$h$),

-- ── public.fleet_repair_due: the points to mend read her rolled max ─────────────────────────────
('public.fleet_repair_due(uuid,numeric)', 1,
$h$  select coalesce(sum(greatest(c.durability * p_to / 100 - s.durability, 0)), 0),
         coalesce(max(greatest(c.durability * p_to / 100 - s.durability, 0) / nullif(c.durability, 0) * 100), 0),
         case when public.gear_wear_on() then public.gear_repair_quote(p_fleet) end
    from public.ships s join public.ship_classes c on c.id = s.class_id
   where s.fleet_id = p_fleet$h$,
$h$  -- 0276: her own rolled max — as scalar subselects, because an aggregate cannot hold a
  -- set-returning call.
  select coalesce(sum(greatest((select sb.durability from public.ship_base(s.id) sb) * p_to / 100 - s.durability, 0)), 0),
         coalesce(max(greatest((select sb.durability from public.ship_base(s.id) sb) * p_to / 100 - s.durability, 0)
                        / nullif((select sb.durability from public.ship_base(s.id) sb), 0) * 100), 0),
         case when public.gear_wear_on() then public.gear_repair_quote(p_fleet) end
    from public.ships s
   where s.fleet_id = p_fleet$h$),

-- ── public.ship_set_bonus: the set's per-cent base is her base for the four rolled stats ────────
('public.ship_set_bonus(uuid)', 1,
$h$  with base as (
    select v.stat, v.base + coalesce((select sum(e.delta) from public.fitted_units fu join public.item_effects e on e.item_code = fu.item_code
                                       where fu.ship_id = p_ship and e.stat = v.stat), 0) as total
      from public.ships s join public.ship_classes c on c.id = s.class_id
     cross join lateral (values ('hold', c.hold::numeric), ('speed', c.speed_kn::numeric), ('handling', c.handling::numeric),
                                ('durability', c.durability::numeric), ('armour', c.armour::numeric), ('attack', c.attack::numeric),
                                ('accuracy', c.accuracy::numeric), ('reach', c.reach::numeric), ('sighting', c.sighting::numeric)) v(stat, base)
     where s.id = p_ship)$h$,
$h$  with base as (
    select v.stat, v.base + coalesce((select sum(e.delta) from public.fitted_units fu join public.item_effects e on e.item_code = fu.item_code
                                       where fu.ship_id = p_ship and e.stat = v.stat), 0) as total
      from public.ships s join public.ship_classes c on c.id = s.class_id
     cross join lateral public.ship_base(p_ship) sb   -- 0276: her class × her roll, for the four rolled stats
     cross join lateral (values ('hold', sb.hold), ('speed', sb.speed), ('handling', sb.handling),
                                ('durability', sb.durability), ('armour', c.armour::numeric), ('attack', c.attack::numeric),
                                ('accuracy', c.accuracy::numeric), ('reach', c.reach::numeric), ('sighting', c.sighting::numeric)) v(stat, base)
     where s.id = p_ship)$h$),

-- ── voyage.ship_speed_at: the hull-speed factor divides by her rolled max ────────────────────────
('voyage.ship_speed_at(uuid,numeric)', 1,
$h$  v_hull := public.wc_num('hull_speed_floor')
          + (1 - public.wc_num('hull_speed_floor')) * least(1.0, s.durability / c.durability);$h$,
$h$  v_hull := public.wc_num('hull_speed_floor')
          + (1 - public.wc_num('hull_speed_floor')) * least(1.0, s.durability / (public.ship_base(p_ship)).durability);$h$),

-- ── voyage.settle: STORM and SHOAL_WATER take her rolled max ────────────────────────────────────
('voyage.settle(uuid,timestamptz)', 1,
$h$      for s in select sh.id, sh.durability, c.durability maxd
                 from public.ships sh join public.ship_classes c on c.id = sh.class_id
                where sh.fleet_id = p_fleet loop
        -- 0154 (K2): the one storm rule (Weather Lore at departure); 0168 (S4): less what her armour turns$h$,
$h$      for s in select sh.id, sh.durability, (public.ship_base(sh.id)).durability as maxd   -- 0276: her own rolled max
                 from public.ships sh
                where sh.fleet_id = p_fleet loop
        -- 0154 (K2): the one storm rule (Weather Lore at departure); 0168 (S4): less what her armour turns$h$),

('voyage.settle(uuid,timestamptz)', 2,
$h$      for s in select sh.id, sh.durability, c.durability maxd
                 from public.ships sh join public.ship_classes c on c.id = sh.class_id
                where sh.fleet_id = p_fleet loop
        -- 0189: less what her armour turns (public.armour_turns; at 0, the loss itself)$h$,
$h$      for s in select sh.id, sh.durability, (public.ship_base(sh.id)).durability as maxd   -- 0276: her own rolled max
                 from public.ships sh
                where sh.fleet_id = p_fleet loop
        -- 0189: less what her armour turns (public.armour_turns; at 0, the loss itself)$h$),

-- ── voyage.fight: the hull handed to fight_resolve carries her rolled max ───────────────────────
('voyage.fight(uuid,int,uuid,numeric)', 1,
$h$             'id', s.id, 'name', s.name, 'tier', c.tier, 'hull', s.durability, 'maxd', c.durability, 'crew', s.crew,$h$,
$h$             'id', s.id, 'name', s.name, 'tier', c.tier, 'hull', s.durability,
             -- 0276: her own rolled max — as a scalar subselect, because the jsonb_agg around this
             -- build_object is an aggregate and an aggregate cannot hold a set-returning call.
             'maxd', (select sb.durability from public.ship_base(s.id) sb), 'crew', s.crew,$h$),

-- ── world.ship_stats: the base of the four rolled stats reads her base (both branches) ──────────
('world.ship_stats(uuid)', 1,
$h$     cross join lateral (values ('hold',       c.hold::numeric),
                                ('speed',      c.speed_kn::numeric),
                                ('handling',   c.handling::numeric),
                                ('draft',      c.draft::numeric),
                                ('durability', c.durability::numeric),
                                ('armour',     c.armour::numeric),
                                ('attack',     c.attack::numeric),
                                ('accuracy',   c.accuracy::numeric),
                                ('reach',      c.reach::numeric),
                                ('sighting',   c.sighting::numeric),
                                ('wave',       c.wave::numeric)) b(stat, base)   -- 0215: + wave resistance, summed as the rest$h$,
$h$     cross join lateral public.ship_base(p_ship) sb   -- 0276: her class × her roll, for the four rolled stats
     cross join lateral (values ('hold',       sb.hold),
                                ('speed',      sb.speed),
                                ('handling',   sb.handling),
                                ('draft',      c.draft::numeric),
                                ('durability', sb.durability),
                                ('armour',     c.armour::numeric),
                                ('attack',     c.attack::numeric),
                                ('accuracy',   c.accuracy::numeric),
                                ('reach',      c.reach::numeric),
                                ('sighting',   c.sighting::numeric),
                                ('wave',       c.wave::numeric)) b(stat, base)   -- 0215: + wave resistance, summed as the rest$h$),

('world.ship_stats(uuid)', 2,
$h$   cross join lateral (values ('hold',       c.hold::numeric),
                              ('speed',      c.speed_kn::numeric),
                              ('handling',   c.handling::numeric),
                              ('draft',      c.draft::numeric),
                              ('durability', c.durability::numeric),
                              ('armour',     c.armour::numeric),
                              ('attack',     c.attack::numeric),
                              ('accuracy',   c.accuracy::numeric),
                              ('reach',      c.reach::numeric),
                              ('sighting',   c.sighting::numeric),
                              ('wave',       c.wave::numeric)) b(stat, base)   -- 0215: + wave resistance, summed as the rest$h$,
$h$   cross join lateral public.ship_base(p_ship) sb   -- 0276: her class × her roll, for the four rolled stats
   cross join lateral (values ('hold',       sb.hold),
                              ('speed',      sb.speed),
                              ('handling',   sb.handling),
                              ('draft',      c.draft::numeric),
                              ('durability', sb.durability),
                              ('armour',     c.armour::numeric),
                              ('attack',     c.attack::numeric),
                              ('accuracy',   c.accuracy::numeric),
                              ('reach',      c.reach::numeric),
                              ('sighting',   c.sighting::numeric),
                              ('wave',       c.wave::numeric)) b(stat, base)   -- 0215: + wave resistance, summed as the rest$h$),

-- ── world.ship_view: her rated figures read her base; the new keys ride beside them ─────────────
('world.ship_view(uuid)', 1,
$h$           'durability', s.durability, 'max_durability', c.durability,$h$,
$h$           'durability', s.durability, 'max_durability', sb.durability,   -- 0276: her own rolled max$h$),

('world.ship_view(uuid)', 2,
$h$           'crew', s.crew, 'crew_required', c.crew_required, 'crew_max', c.crew_max,$h$,
$h$           'crew', s.crew, 'crew_required', c.crew_required, 'crew_max', sb.crew_max,   -- 0276: her own rolled max$h$),

('world.ship_view(uuid)', 3,
$h$           'hold', public.ship_hold_capacity(s.id), 'hold_rated', c.hold,$h$,
$h$           'hold', public.ship_hold_capacity(s.id), 'hold_rated', sb.hold,   -- 0276: her own rolled hold$h$),

('world.ship_view(uuid)', 4,
$h$           'speed', voyage.ship_speed(s.id), 'speed_rated', c.speed_kn,$h$,
$h$           'speed', voyage.ship_speed(s.id), 'speed_rated', sb.speed,   -- 0276: her own rolled speed$h$),

('world.ship_view(uuid)', 5,
$h$   cross join lateral (select world.ship_stats(s.id) as st offset 0) x$h$,
$h$   cross join lateral (select world.ship_stats(s.id) as st offset 0) x
   cross join lateral public.ship_base(s.id) sb   -- 0276: her class × her roll, once$h$),

('world.ship_view(uuid)', 6,
$h$           'sighting', x.st->'sighting',
           'wave', x.st->'wave',   -- 0215: her wave resistance (world.ship_stats, the one computation)$h$,
$h$           'sighting', x.st->'sighting',
           'wave', x.st->'wave',   -- 0215: her wave resistance (world.ship_stats, the one computation)
           -- 0276: HER OWN ROLL (fixed at her commission; 1.000 for every hull built before 0276 and
           -- every famous ship), her grade word (derived, public.ship_grade), and the class's own
           -- figures beside the rolled ones — served, never derived by the client.
           'roll', jsonb_build_object('hold', s.roll_hold, 'speed', s.roll_speed, 'stores', s.roll_stores,
                                      'durability', s.roll_hull, 'crew_max', s.roll_crew, 'handling', s.roll_handling),
           'grade', public.ship_grade(s.id),
           'class_hold', c.hold, 'class_speed', c.speed_kn, 'class_durability', c.durability,
           'class_crew_max', c.crew_max, 'class_handling', c.handling,$h$),

-- ── world.building_yard: the catalogue stays on the class; each hull names its range ────────────
('world.building_yard(uuid)', 1,
$h$        'hold', c.hold, 'speed_kn', c.speed_kn, 'crew_required', c.crew_required,
        'durability', c.durability, 'draft', c.draft,$h$,
$h$        'hold', c.hold, 'speed_kn', c.speed_kn, 'crew_required', c.crew_required,
        'durability', c.durability, 'draft', c.draft,
        -- 0276: how far a new hull of this class may stray from the figures above (the normal band,
        -- ± per cent, from the same rows the roll draws; the rare Poor and Fine go beyond): the
        -- yard says it before you build, and the roll itself stays blind (design §3).
        'variety_pct', public.ship_variety_band(c.code),$h$),

-- ── world.ship_budget: her Hands max reads her rolled crew max ──────────────────────────────────
('world.ship_budget(uuid)', 1,
$h$   cross join lateral public.class_budget(c.code) b$h$,
$h$   cross join lateral (select cb.deck,
                                (public.ship_base(s.id)).crew_max - (c.crew_required + 1) / 2 as hands
                           from public.class_budget(c.code) cb) b$h$);

-- ── 5. THE SLICE TOOL (its own copy, by necessity — tests/duplication.spec.ts:365-380) ──────────
create or replace function pg_temp.recut_0276(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0276 where fn = p_fn order by n loop
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0276 slice: hunk % of % occurs % time(s), expected exactly 1 — the deployed body is not what this migration was generated against.',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0276(fn) from (select distinct fn from hunks_0276) x order by fn;

-- commission_ship's signature moved ON PURPOSE (the probe's id): the old overload is dropped, so
-- the one insert has ONE name. Its six-argument callers (new_house, cmd.do_build, npc_found)
-- resolve through the new default, exactly as before.
drop function public.commission_ship(uuid, uuid, text, text, boolean, boolean);

-- ── 6. SELF-ASSERT ──────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_uid    constant uuid := '00000000-0276-4000-8000-0000000000aa';
  c_uid2   constant uuid := '00000000-0276-4000-8000-0000000000bb';
  c_uid3   constant uuid := '00000000-0276-4000-8000-0000000000cc';
  c_uid4   constant uuid := '00000000-0276-4000-8000-0000000000dd';
  c_uid5   constant uuid := '00000000-0276-4000-8000-0000000000ee';
  -- Fixed probe ids (the roll is md5 of the id — these draws are fixed, reproduced by the
  -- simulator in docs/dev-log/2026-10-29-ship-variety.md):
  c_ship_a constant uuid := '00000000-0276-4000-8000-000000000101';   -- normal: mean 1.027, grade null
  c_ship_b constant uuid := '00000000-0276-4000-8000-000000000102';   -- Poor:   mean 0.847, grade poor
  c_ship_f constant uuid := '00000000-0276-4000-8000-000000000010';   -- Fine:   mean 1.157, grade fine
  c_ship_n constant uuid := '00000000-0276-4000-8000-000000000001';   -- founding: raw hold 0.962, crew 0.922 — the clamps bite
  c_ship_l constant uuid := '00000000-0276-4000-8000-000000000103';   -- famous: her seed's raw draw is normal, hold 0.975 — the 1.000 is the legend, not luck
  c_view_keys constant text[] := array['roll', 'grade', 'class_hold', 'class_speed', 'class_durability', 'class_crew_max', 'class_handling'];
  c_factors constant text[] := array['hold', 'speed', 'stores', 'durability', 'crew_max', 'handling'];
  v_fn      text;
  v_after   text;
  v_def     text;
  v_back    text;
  h         record;
  v_n       int;
  v_bad     bigint;
  v_hulls   bigint;
  v_fleets  bigint;
  v_err     text;
  v_player  uuid;
  v_fleet   uuid;
  v_ship    uuid;
  v_roll    jsonb;
  v_roll2   jsonb;
  v_rolled  jsonb;
  vr        public.ship_variety%rowtype;
  v_class   public.ship_classes%rowtype;
  v_base    record;
  v_famous  text;
  v_poor    int;
  v_fine    int;
  v_norm    int;
  v_plo     numeric;
  v_phi     numeric;
  v_flo     numeric;
  v_fhi     numeric;
  v_npc     numeric;
  v_t0      timestamptz;
  v_ms      numeric;
  v_pair    record;
begin
  -- (a) PARITY BY REVERSE SUBSTITUTION: every re-cut body, each 0276 hunk put back the other way
  --     (each new hunk occurring exactly once), is its pre-image to the character; ACL, volatility,
  --     definer and search_path unmoved. commission_ship's signature changed ON PURPOSE (the probe's
  --     id): its parity reads the NEW signature, and its ACL is asserted functionally below.
  for v_fn in select fn from defs_before_0276 loop
    v_after := coalesce((select fn_after from defs_before_0276 where fn = v_fn), v_fn);
    v_def := replace(pg_get_functiondef(v_after::regprocedure), E'\r', '');
    v_back := v_def;
    for h in select * from hunks_0276 where fn = v_fn order by n desc loop
      v_n := (length(v_back) - length(replace(v_back, h.new, ''))) / length(h.new);
      if v_n <> 1 then
        raise exception '0276 self-assert FAIL: hunk % of % is in the new body % time(s), not once', h.n, v_fn, v_n;
      end if;
      v_back := replace(v_back, h.new, h.old);
    end loop;
    if v_back <> (select def from defs_before_0276 where fn = v_fn) or v_def = v_back then
      raise exception '0276 self-assert FAIL: % is not its pre-image plus only 0276''s hunks', v_fn;
    end if;
    if v_fn <> 'public.commission_ship(uuid,uuid,text,text,boolean,boolean)' then
      if coalesce((select p.proacl::text from pg_proc p where p.oid = v_after::regprocedure), '')
         is distinct from (select acl from defs_before_0276 where fn = v_fn) then
        raise exception '0276 self-assert FAIL: the re-cut moved the ACL of %', v_fn;
      end if;
    end if;
    if (select p.provolatile from pg_proc p where p.oid = v_after::regprocedure)
       is distinct from (select vol from defs_before_0276 where fn = v_fn)
       or (select p.prosecdef from pg_proc p where p.oid = v_after::regprocedure)
          is distinct from (select secdef from defs_before_0276 where fn = v_fn)
       or (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = v_after::regprocedure)
          is distinct from (select cfg from defs_before_0276 where fn = v_fn) then
      raise exception '0276 self-assert FAIL: the re-cut moved the volatility, definer or search_path of %', v_fn;
    end if;
  end loop;
  if has_function_privilege('anon', 'public.commission_ship(uuid,uuid,text,text,boolean,boolean,uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.commission_ship(uuid,uuid,text,text,boolean,boolean,uuid)', 'execute') then
    raise exception '0276 self-assert FAIL: commission_ship is client-callable';
  end if;

  -- (b) NOTHING ELSE MOVED: the md5 of every OTHER function in the four schemas, the entry points,
  --     the client write grants.
  if (select md5(string_agg(md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and (n.nspname, p.proname) not in (('public', 'commission_ship'),
                                            ('public', 'ship_base'), ('public', 'ship_roll'),
                                            ('public', 'ship_roll_u'), ('public', 'ship_grade'),
                                            ('public', 'ship_variety_row'), ('public', 'ship_variety_band'))
         and p.oid not in (select to_regprocedure(fn) from defs_before_0276 where fn_after is null))
      is distinct from (select others_md5 from before_0276) then
    raise exception '0276 self-assert FAIL: a function this file did not name moved';
  end if;
  if (select count(*) from public.client_rpc_entry_points()) <> (select entry_points from before_0276)
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0 then
    raise exception '0276 self-assert FAIL: the registry or the grant wall moved';
  end if;

  -- (c) NO BACKFILL: every hull laid down before this file keeps her roll at 1.000 (the columns'
  --     default) — nothing was rolled for a ship that already sailed. Positive control: ships_n.
  if (select ships_n from before_0276) = 0 then
    raise exception '0276 self-assert FAIL: the world has no ships (positive control)';
  end if;
  if exists (select 1 from public.ships s
              where s.created_at <= (select ships_mark from before_0276)
                and (s.roll_speed <> 1.000 or s.roll_hold <> 1.000 or s.roll_stores <> 1.000
                     or s.roll_hull <> 1.000 or s.roll_crew <> 1.000 or s.roll_handling <> 1.000)) then
    raise exception '0276 self-assert FAIL: an existing ship''s roll was backfilled';
  end if;

  -- (d) EVERY HULL AND EVERY FLEET IN THE WORLD BYTE-IDENTICAL: world.ship_stats answers its
  --     pre-image to the digit for every hull; world.ship_view answers its pre-image once the new
  --     keys are stripped (and it DOES serve them, all of them).
  select count(distinct ship_id) into v_hulls from stats_before_0276;
  select count(*) into v_bad from stats_before_0276 b
   where b.v is distinct from world.ship_stats(b.ship_id)::text;
  if v_bad > 0 or v_hulls = 0 then
    raise exception '0276 self-assert FAIL: % of % hulls'' ship_stats changed', v_bad, v_hulls;
  end if;
  select count(*) into v_bad from views_before_0276 b
   where (world.ship_view(b.ship_id) - c_view_keys)::text is distinct from b.v::text;
  if v_bad > 0 then
    raise exception '0276 self-assert FAIL: % of % hulls'' ship_view changed beyond the new keys', v_bad, v_hulls;
  end if;
  if exists (select 1 from public.ships s where not (world.ship_view(s.id) ?& c_view_keys))
     or exists (select 1 from public.ships s
                 where jsonb_typeof(world.ship_view(s.id)->'roll') <> 'object'
                    or (world.ship_view(s.id)->'roll'->>'hold') is null) then
    raise exception '0276 self-assert FAIL: ship_view does not serve roll, grade and the class_* keys';
  end if;
  select count(*) into v_fleets from fleets_before_0276;
  select count(*) into v_bad from fleets_before_0276 b
   where (select coalesce(jsonb_agg(sh - c_view_keys order by o), '[]'::jsonb)::text
            from jsonb_array_elements((select coalesce(jsonb_agg(world.ship_view(s.id) order by s.is_flagship desc, s.name), '[]'::jsonb)
                                         from public.ships s where s.fleet_id = b.fleet_id)) with ordinality x(sh, o))
         is distinct from b.ships;
  if v_bad > 0 or v_fleets = 0 then
    raise exception '0276 self-assert FAIL: % of % fleets'' ships changed in world.fleets', v_bad, v_fleets;
  end if;

  -- (e) THE ROLL PROBES, rolled back whole: three probe hulls of ONE class with FIXED ids — the
  --     stored roll equals ship_roll(id) to the digit, the same seed reads the same factors twice,
  --     two hulls of one class differ within the bands, every factor and every effective stat stays
  --     inside the class's bounds (from the band rows, not from numbers here), the grade words read
  --     true, a founding hull is never Poor, a famous hull is always the legend.
  begin
    -- three probe hulls of ONE class with FIXED ids, each in her own house and fleet (a fleet
    -- sails two ships at most — the house-cap trigger enforces it — so they cannot share one).
    for v_pair in select x.ship_id, x.flag, x.uid, x.house
                    from (values (c_ship_a, true,  c_uid,  'Casa da Prova Um'),
                                 (c_ship_b, false, c_uid2, 'Casa da Prova Dois'),
                                 (c_ship_f, false, c_uid3, 'Casa da Prova Tres')) x(ship_id, flag, uid, house) loop
      insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
      values (v_pair.uid, v_pair.house, (select id from public.nations where code = 'PRT'), 0, false)
      returning id into v_player;
      v_fleet := public.form_fleet(v_player, 'Prova', (select id from public.ports where code = 'LIS'));
      perform public.commission_ship(v_player, v_fleet, 'barca', 'Prova', v_pair.flag, false, v_pair.ship_id);
    end loop;

    -- the same seed always answers the same factors (determinism; no random()).
    v_roll := public.ship_roll(c_ship_a, 'barca');
    v_roll2 := public.ship_roll(c_ship_a, 'barca');
    if v_roll::text is distinct from v_roll2::text then
      raise exception '0276 self-assert FAIL: the same seed answered two rolls';
    end if;

    -- the stored roll IS the roll of her id (the one place the roll happens).
    for v_ship in select unnest(array[c_ship_a, c_ship_b, c_ship_f]) loop
      v_roll := public.ship_roll(v_ship, 'barca');
      v_rolled := (select jsonb_build_object(
                     'hold', s.roll_hold, 'speed', s.roll_speed, 'stores', s.roll_stores,
                     'durability', s.roll_hull, 'crew_max', s.roll_crew, 'handling', s.roll_handling)
                     from public.ships s where s.id = v_ship);
      if v_rolled::text is distinct from v_roll::text then
        raise exception '0276 self-assert FAIL: the stored roll is not ship_roll of her id (stored % rolled %)',
          v_rolled::text, v_roll::text;
      end if;
    end loop;

    -- two hulls of one class differ, and every factor stays inside the stated bands (the rows).
    if public.ship_roll(c_ship_a, 'barca')::text = public.ship_roll(c_ship_b, 'barca')::text then
      raise exception '0276 self-assert FAIL: two hulls of one class rolled identical factors';
    end if;
    select * into vr from public.ship_variety_row('barca', 'hold');
    v_plo := 1 - vr.poor_hi; v_fhi := 1 + vr.fine_hi;
    for v_ship in select unnest(array[c_ship_a, c_ship_b, c_ship_f]) loop
      v_roll := public.ship_roll(v_ship, 'barca');
      foreach v_fn in array c_factors loop
        if (v_roll->>v_fn)::numeric < v_plo or (v_roll->>v_fn)::numeric > v_fhi then
          raise exception '0276 self-assert FAIL: a factor of % reads outside the bands (%)', v_fn, v_roll->>v_fn;
        end if;
      end loop;
      -- every effective stat stays inside her class's bounds (the same rows, applied to her class):
      -- whole-number stats between floor(class × (1 − poor_hi)) and floor(class × (1 + fine_hi));
      -- speed within 0.01 of them; crew max never below what the class needs.
      select c.* into v_class from public.ship_classes c join public.ships s on s.class_id = c.id where s.id = v_ship;
      select * into v_base from public.ship_base(v_ship);
      if v_base.hold < floor(v_class.hold * v_plo) or v_base.hold > floor(v_class.hold * v_fhi)
         or v_base.durability < floor(v_class.durability * v_plo) or v_base.durability > floor(v_class.durability * v_fhi)
         or v_base.handling < floor(v_class.handling * v_plo) or v_base.handling > floor(v_class.handling * v_fhi)
         or v_base.speed < v_class.speed_kn * v_plo - 0.01 or v_base.speed > v_class.speed_kn * v_fhi + 0.01
         or v_base.crew_max < v_class.crew_required or v_base.crew_max > floor(v_class.crew_max * v_fhi) then
        raise exception '0276 self-assert FAIL: an effective stat of % reads outside her class''s bounds (hold % dur % hand % speed % crew %)',
          v_ship, v_base.hold, v_base.durability, v_base.handling, v_base.speed, v_base.crew_max;
      end if;
      -- a re-read of the same ship answers the same stats, while the clock demonstrably moves
      -- between the two reads (anti-proof: no random() and no clock in the read path).
      v_roll := world.ship_view(v_ship);
      v_t0 := clock_timestamp();
      v_roll2 := world.ship_view(v_ship);
      if v_roll::text is distinct from v_roll2::text or clock_timestamp() = v_t0 then
        raise exception '0276 self-assert FAIL: a re-read of % answered differently (or the clock did not move)', v_ship;
      end if;
    end loop;

    -- the grade word, derived from the stored factors: null on a standard hull, poor and fine on
    -- the Poor and Fine hulls (fixed draws, reproduced in the dev-log).
    if public.ship_grade(c_ship_a) is not null
       or public.ship_grade(c_ship_b) <> 'poor'
       or public.ship_grade(c_ship_f) <> 'fine' then
      raise exception '0276 self-assert FAIL: a grade word read wrong (%, %, %)',
        public.ship_grade(c_ship_a), public.ship_grade(c_ship_b), public.ship_grade(c_ship_f);
    end if;

    -- a founding hull (crewed AND flagship) never starts Poor: every factor raised to 1.000 at
    -- least, and the crew factor clamped to what the class needs — against the raw roll of her id.
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values (c_uid4, 'Casa da Prova Quatro', (select id from public.nations where code = 'PRT'), 0, false)
    returning id into v_player;
    v_fleet := public.form_fleet(v_player, 'Fundadora', (select id from public.ports where code = 'LIS'));
    perform public.commission_ship(v_player, v_fleet, 'barca', 'Fundadora', true, true, c_ship_n);
    v_roll := public.ship_roll(c_ship_n, 'barca');
    select c.* into v_class from public.ship_classes c join public.ships s on s.class_id = c.id where s.id = c_ship_n;
    foreach v_fn in array array['hold', 'speed', 'stores', 'durability', 'handling'] loop
      v_n := 0;
      select count(*) into v_n from public.ships s where s.id = c_ship_n
        and (case v_fn
               when 'hold' then s.roll_hold
               when 'speed' then s.roll_speed
               when 'stores' then s.roll_stores
               when 'durability' then s.roll_hull
               else s.roll_handling end) = greatest((v_roll->>v_fn)::numeric, 1.000);
      if v_n <> 1 then
        raise exception '0276 self-assert FAIL: the founding clamp did not raise % to 1.000 (raw %)', v_fn, v_roll->>v_fn;
      end if;
    end loop;
    if (select s.roll_crew from public.ships s where s.id = c_ship_n)
       <> greatest(greatest((v_roll->>'crew_max')::numeric, 1.000),
                   ceil(v_class.crew_required::numeric / v_class.crew_max * 1000) / 1000) then
      raise exception '0276 self-assert FAIL: the crew clamp did not hold on the founding hull';
    end if;
    -- positive control: the founding seed's RAW draw had something to clamp (fixed draws).
    if (v_roll->>'hold')::numeric >= 1.000 and (v_roll->>'crew_max')::numeric >= 1.000 then
      raise exception '0276 self-assert FAIL: the founding seed''s raw draw has nothing to clamp (positive control)';
    end if;

    -- a famous hull is always the ship of the legend: 1.000 whatever the seed, even one whose raw
    -- draw is NOT 1.000 (the positive control that the roll was SKIPPED, not lucky).
    select cp.class_code into v_famous from public.class_profile cp where cp.tech = 'F' order by cp.class_code limit 1;
    if v_famous is null then
      raise exception '0276 self-assert FAIL: no famous class exists to probe';
    end if;
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values (c_uid5, 'Casa da Prova Cinco', (select id from public.nations where code = 'PRT'), 0, false)
    returning id into v_player;
    v_fleet := public.form_fleet(v_player, 'A Lenda', (select id from public.ports where code = 'LIS'));
    perform public.commission_ship(v_player, v_fleet, v_famous, 'A Lenda', true, true, c_ship_l);
    if (select s.roll_speed + s.roll_hold + s.roll_stores + s.roll_hull + s.roll_crew + s.roll_handling
          from public.ships s where s.id = c_ship_l) <> 6.000
       or public.ship_grade(c_ship_l) is not null then
      raise exception '0276 self-assert FAIL: a famous hull did not read 1.000';
    end if;
    if (public.ship_roll(c_ship_l, v_famous)->>'hold')::numeric = 1.000 then
      raise exception '0276 self-assert FAIL: the famous seed''s raw draw is 1.000 — the skip is not proven';
    end if;

    v_t0 := clock_timestamp();
    raise exception 'ROLLBACK_0276' using errcode = 'P0276';
  exception when sqlstate 'P0276' then
    v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
  end;
  if exists (select 1 from public.players where auth_uid in (c_uid, c_uid2, c_uid3, c_uid4, c_uid5))
     or exists (select 1 from public.ships where id in (c_ship_a, c_ship_b, c_ship_f, c_ship_n, c_ship_l)) then
    raise exception '0276 self-assert FAIL: the probe world was not rolled back';
  end if;

  -- (f) A THOUSAND FIXED SEEDS: the Poor and the Fine bands each answer 30–70 of 1000, every
  --     factor stays inside the stated bands, and every factor of a standard hull stays within the
  --     normal ± (the design's own test, §5 V3). Deterministic: fixed seeds, counted once.
  select * into vr from public.ship_variety_row('barca', 'hold');
  v_plo := 1 - vr.poor_hi; v_phi := 1 - vr.poor_lo;
  v_flo := 1 + vr.fine_lo; v_fhi := 1 + vr.fine_hi;
  v_npc := vr.normal_pc;
  with seeds as (
    select ('00000000-0276-4000-8000-' || lpad(to_hex(i), 12, '0'))::uuid as id
      from generate_series(1, 1000) i
  ), rolls as (
    select s.id, public.ship_roll(s.id, 'barca') r from seeds s
  )
  select count(*) filter (where (r->>'hold')::numeric between v_plo and v_phi
                              and (r->>'speed')::numeric between v_plo and v_phi
                              and (r->>'stores')::numeric between v_plo and v_phi
                              and (r->>'durability')::numeric between v_plo and v_phi
                              and (r->>'crew_max')::numeric between v_plo and v_phi
                              and (r->>'handling')::numeric between v_plo and v_phi),
         count(*) filter (where (r->>'hold')::numeric between v_flo and v_fhi
                              and (r->>'speed')::numeric between v_flo and v_fhi
                              and (r->>'stores')::numeric between v_flo and v_fhi
                              and (r->>'durability')::numeric between v_flo and v_fhi
                              and (r->>'crew_max')::numeric between v_flo and v_fhi
                              and (r->>'handling')::numeric between v_flo and v_fhi),
         count(*) filter (where not ((r->>'hold')::numeric between v_plo and v_phi
                                 and (r->>'speed')::numeric between v_plo and v_phi
                                 and (r->>'stores')::numeric between v_plo and v_phi
                                 and (r->>'durability')::numeric between v_plo and v_phi
                                 and (r->>'crew_max')::numeric between v_plo and v_phi
                                 and (r->>'handling')::numeric between v_plo and v_phi)
                             and not ((r->>'hold')::numeric between v_flo and v_fhi
                                 and (r->>'speed')::numeric between v_flo and v_fhi
                                 and (r->>'stores')::numeric between v_flo and v_fhi
                                 and (r->>'durability')::numeric between v_flo and v_fhi
                                 and (r->>'crew_max')::numeric between v_flo and v_fhi
                                 and (r->>'handling')::numeric between v_flo and v_fhi))
    into v_poor, v_fine, v_norm
    from rolls;
  if v_poor not between 30 and 70 or v_fine not between 30 and 70 or v_poor + v_fine + v_norm <> 1000 then
    raise exception '0276 self-assert FAIL: the tier draws of 1000 fixed seeds read Poor %, Fine %, standard %', v_poor, v_fine, v_norm;
  end if;
  if exists (select 1
               from (select ('00000000-0276-4000-8000-' || lpad(to_hex(i), 12, '0'))::uuid as id
                       from generate_series(1, 1000) i) s
              cross join lateral jsonb_each_text(public.ship_roll(s.id, 'barca')) e
              where (e.value)::numeric < v_plo or (e.value)::numeric > v_fhi) then
    raise exception '0276 self-assert FAIL: a factor of the 1000 seeds reads outside the stated bands';
  end if;
  if exists (select 1
               from (select ('00000000-0276-4000-8000-' || lpad(to_hex(i), 12, '0'))::uuid as id
                       from generate_series(1, 1000) i) s
              cross join lateral jsonb_each_text(public.ship_roll(s.id, 'barca')) e
              where ((e.value)::numeric < 1 - v_npc or (e.value)::numeric > 1 + v_npc)
                and not ((public.ship_roll(s.id, 'barca')->>'hold')::numeric between v_plo and v_phi
                     and (public.ship_roll(s.id, 'barca')->>'speed')::numeric between v_plo and v_phi
                     and (public.ship_roll(s.id, 'barca')->>'stores')::numeric between v_plo and v_phi
                     and (public.ship_roll(s.id, 'barca')->>'durability')::numeric between v_plo and v_phi
                     and (public.ship_roll(s.id, 'barca')->>'crew_max')::numeric between v_plo and v_phi
                     and (public.ship_roll(s.id, 'barca')->>'handling')::numeric between v_plo and v_phi)
                and not ((public.ship_roll(s.id, 'barca')->>'hold')::numeric between v_flo and v_fhi
                     and (public.ship_roll(s.id, 'barca')->>'speed')::numeric between v_flo and v_fhi
                     and (public.ship_roll(s.id, 'barca')->>'stores')::numeric between v_flo and v_fhi
                     and (public.ship_roll(s.id, 'barca')->>'durability')::numeric between v_flo and v_fhi
                     and (public.ship_roll(s.id, 'barca')->>'crew_max')::numeric between v_flo and v_fhi
                     and (public.ship_roll(s.id, 'barca')->>'handling')::numeric between v_flo and v_fhi)) then
    raise exception '0276 self-assert FAIL: a standard hull''s factor reads outside the normal ±';
  end if;

  -- (g) NO OTHER READER (the design's §2.2 wall): after the re-cuts, the ONLY bodies in the four
  --     schemas that join ship_classes with ships AND name a rolled class column are ship_base
  --     itself, ship_view (its class_* keys), and commission_ship (the roll's writer, reading the
  --     class only to lay the hull down). Positive control: the BEFORE scan saw every one of the
  --     token-visible re-cut targets — so the scan can see.
  for v_fn in select unnest(array[
        'public.commission_ship(uuid, uuid, text, text, boolean, boolean)',
        'world.ship_stats(uuid)', 'world.ship_view(uuid)',
        'cmd.do_hire(uuid, jsonb)', 'cmd.do_repair(uuid, jsonb)',
        'public.fleet_repair_due(uuid, numeric)', 'public.ship_set_bonus(uuid)',
        'voyage.ship_speed_at(uuid, numeric)', 'voyage.settle(uuid, timestamp with time zone)',
        'voyage.fight(uuid, integer, uuid, numeric)']) loop
    if not exists (select 1 from scan_before_0276 b where b.fn = v_fn) then
      raise exception '0276 self-assert FAIL: the before-scan did not see % (positive control; the scan saw: %)',
        v_fn, (select coalesce(string_agg(fn, ', ' order by fn), 'NOTHING') from scan_before_0276);
    end if;
  end loop;
  if exists (select 1 from scan_before_0276 b where b.fn not in (select canon from defs_before_0276)) then
    raise exception '0276 self-assert FAIL: the before-scan saw a reader this file never named';
  end if;
  if exists (
    select 1
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
       and pg_get_functiondef(p.oid) like '%ship_classes%'
       and pg_get_functiondef(p.oid) like '%public.ships%'
       and (pg_get_functiondef(p.oid) like '%c.hold%'
         or pg_get_functiondef(p.oid) like '%c.speed_kn%'
         or pg_get_functiondef(p.oid) like '%c.durability%'
         or pg_get_functiondef(p.oid) like '%c.crew_max%'
         or pg_get_functiondef(p.oid) like '%c.handling%')
       and n.nspname || '.' || p.proname || '(' || oidvectortypes(p.proargtypes) || ')'
             not in ('public.ship_base(uuid)',
                     'public.commission_ship(uuid, uuid, text, text, boolean, boolean, uuid)',
                     'world.ship_view(uuid)')) then
    raise exception '0276 self-assert FAIL: a body still reads a rolled class column joined to a ship (%)',
      (select string_agg(n2.nspname || '.' || q.proname || '(' || oidvectortypes(q.proargtypes) || ')', ', ' order by 1)
         from pg_proc q join pg_namespace n2 on n2.oid = q.pronamespace
        where n2.nspname in ('public', 'cmd', 'world', 'voyage') and q.prokind in ('f', 'p')
          and pg_get_functiondef(q.oid) like '%ship_classes%'
          and pg_get_functiondef(q.oid) like '%public.ships%'
          and (pg_get_functiondef(q.oid) like '%c.hold%'
            or pg_get_functiondef(q.oid) like '%c.speed_kn%'
            or pg_get_functiondef(q.oid) like '%c.durability%'
            or pg_get_functiondef(q.oid) like '%c.crew_max%'
            or pg_get_functiondef(q.oid) like '%c.handling%')
          and n2.nspname || '.' || q.proname || '(' || oidvectortypes(q.proargtypes) || ')'
                not in ('public.ship_base(uuid)',
                        'public.commission_ship(uuid, uuid, text, text, boolean, boolean, uuid)',
                        'world.ship_view(uuid)'));
  end if;

  -- (h) THE ONE INSERT: no live body other than commission_ship inserts a ship — the roll can only
  --     be taken at the one place. Positive control: commission_ship itself does insert.
  if pg_temp.occurs_0276(replace(pg_get_functiondef('public.commission_ship(uuid,uuid,text,text,boolean,boolean,uuid)'::regprocedure), E'\r', ''), 'insert into public.ships') <> 1 then
    raise exception '0276 self-assert FAIL: commission_ship no longer holds the one insert (positive control)';
  end if;
  if exists (select 1
               from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
                and p.oid <> to_regprocedure('public.commission_ship(uuid,uuid,text,text,boolean,boolean,uuid)')
                and pg_get_functiondef(p.oid) like '%insert into public.ships%') then
    raise exception '0276 self-assert FAIL: another body inserts ships — the roll has a second door';
  end if;

  -- (i) THE WALL: the six new readings are server-only; the band table is readable by no client.
  if has_function_privilege('anon', 'public.ship_base(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.ship_base(uuid)', 'execute')
     or has_function_privilege('anon', 'public.ship_roll(uuid,text)', 'execute')
     or has_function_privilege('authenticated', 'public.ship_roll(uuid,text)', 'execute')
     or has_function_privilege('anon', 'public.ship_grade(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.ship_grade(uuid)', 'execute')
     or has_function_privilege('anon', 'public.ship_roll_u(text,uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.ship_roll_u(text,uuid)', 'execute')
     or has_function_privilege('anon', 'public.ship_variety_row(text,text)', 'execute')
     or has_function_privilege('authenticated', 'public.ship_variety_row(text,text)', 'execute')
     or has_function_privilege('anon', 'public.ship_variety_band(text)', 'execute')
     or has_function_privilege('authenticated', 'public.ship_variety_band(text)', 'execute')
     or has_table_privilege('anon', 'public.ship_variety', 'select')
     or has_table_privilege('authenticated', 'public.ship_variety', 'select') then
    raise exception '0276 self-assert FAIL: a new reading or the band table is client-reachable';
  end if;
  if (select count(*) from public.ship_variety) <> 6
     or exists (select 1 from public.ship_variety v where v.poor_lo > v.poor_hi or v.fine_lo > v.fine_hi) then
    raise exception '0276 self-assert FAIL: the band rows are not as authored';
  end if;

  raise notice '0276 self-assert ok: EVERY NEW SHIP ROLLS HER OWN STATS. Twelve bodies reverse to their pre-images hunk by hunk (ACL, volatility, definer and search_path unmoved; commission_ship''s signature gains the probe''s id on purpose and stays server-only), every other function''s md5 unmoved, the registry and the grant wall as found. No backfill: all % pre-existing hulls keep roll 1.000, and their world.ship_stats and world.ship_view answer the pre-image to the digit (%, hulls; %, fleets), the new keys served on every hull. Probes rolled back: three hulls of one class with fixed ids — the stored roll equals ship_roll(id) to the digit, the same seed answers the same factors twice, two hulls differ, every factor within the band rows and every effective stat within her class''s bounds, grades read null/poor/fine; a founding hull''s factors are raised to 1.000 (raw draw had something to clamp); a famous hull reads 1.000 although her seed''s raw draw is not. A thousand fixed seeds: Poor %, Fine %, standard %, every factor within the bands, every standard factor within the normal ±. No other body reads a rolled class column joined to a ship (the before-scan saw every named reader), no other body inserts a ship. The new readings are server-only; the band table is client-dark. Probes took % ms.',
    (select ships_n from before_0276), v_hulls, v_fleets, v_poor, v_fine, v_norm, v_ms;
end $$;
