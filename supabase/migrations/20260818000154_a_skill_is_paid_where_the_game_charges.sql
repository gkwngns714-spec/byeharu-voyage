-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0154 — A SKILL IS PAID WHERE THE GAME CHARGES  (K2: one reading per cost, then the skill terms — DARK)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHY NOW ─────────────────────────────────────────────────────────────────────────────────────
-- docs/SKILLS_AND_CAPTAINS.md §3.3 ("Lifted means one authority first") and §8 row K2. K1 (0151) put
-- ten HOUSE-scope effect rows in the catalogue that nothing reads; K2 gives six of them their one
-- reader, and gives Shipwright the yard-labour effect §3.3 assigns it. Brokerage (profit tax),
-- Patronage (influence) are K2b; Leadership and Hospitality are K6 — untouched here.
--
-- ── 1. THE LIFTS (each proven equal to today's figure, for every company) ─────────────────────────
-- Four costs were computed inline in a door and printed by a screen from elsewhere. A skill term put
-- in the door would make the screen print a number the game does not charge, so each is lifted into
-- ONE function that both the door and the screen read:
--   public.fleet_wage(fleet, short, crew)  the day's crew wage: crew_wages × running_cost_mult (0114).
--        voyage.settle charges it (was inline), world.crew_cost quotes it, cmd.do_dismiss reports it.
--   public.crew_hire_cost(fleet, n)        the hire: the pool split (0097) and the price (DESIGN F.2).
--        cmd.do_hire charges it (was inline); the Inn's price is cmd.preview of that same door.
--   public.captain_wage(player, officer)   a captain's signing wage (officers.wage_ducats).
--        public.sign_officer charges it (cmd.hire_officer, npc_found); world.inn and world.officers print it.
--   public.yard_labour(player, class)      a hull's yard labour: public.hull_labour (0135), the base.
--        cmd.do_build charges it; world.building_yard prints it.
-- And the two reads the voyage needs, also one each:
--   public.standing_route_max_for(player)  the route cap: the trigger standing_routes_cap() and
--        world.standing_routes' `max` read it (both read the knob inline).
--   voyage.day_delay_for(voyage, kind, magnitude, prior)  what a day's roll costs THIS voyage:
--        voyage.day_delay_hours (0125's table) and, for a calm, Light-air. voyage.settle's three arms and
--        voyage.arrival_at's fixed point read it (they read the table inline), so the arrival the
--        game predicts and the arrival it settles stay one rule.
--   voyage.storm_hull_lost(voyage, maxd, magnitude)  the STORM arm's hull loss (was inline).
--
-- ── 2. THE SKILL TERMS (all DARK: nothing while skills_bite is off) ──────────────────────────────
--   Factorage        +1 route per level            standing_route_max_for
--   Pursership       −3 % per level, crew wages     fleet_wage
--   Etiquette        −4 % per level, crew hiring    crew_hire_cost
--   Recruiting       −5 % per level, captain wage   captain_wage
--   Shipwright       −3 % per level, yard labour    yard_labour (new effect row + the CHECK re-made)
--   Weather Lore     −4 % per level, storm hull     storm_hull_lost   } the level AT THE VOYAGE'S
--   Light-air        −5 % per level, calm delay     day_delay_for     } DEPARTURE (skill_level_at)
-- Every term is read through THE one reading of a company's skills: world.skill_bonuses → world.skill_pct
-- (scope house). For a level at a moment that reading gains a time: world.skill_bonuses_at(player, ship,
-- at) is the live world.skill_bonuses body with `now()` → `p_at` (its two time reads: the finished queue
-- entries and public.skill_level → public.skill_level_at), made FROM the live body here; world.skill_bonuses
-- and world.skill_pct become that reading at now(), row for row (proven). voyage.skill_pct_at_departure
-- reads it at the voyage's departed_at, so a settlement never depends on when it runs.
-- The words (public.skill_effect_words): "+2 routes", "−15% crew wages", "−8% crew hiring", "−15% captain
-- wages", "−6% yard labour", "−12% storm damage", "−10% time lost in a calm" (WORDS: a "route", never a
-- "standing route"). The client prints only server numbers: every screen these touch already reads the
-- lifted function (Inn crew wage, Inn hire dry run, Inn / Captains wage, Yard price, Routes max).
--
-- ── WHAT IT DELIBERATELY DOES NOT DO ────────────────────────────────────────────────────────────
-- Light skills_bite. Change any figure any company sees or pays today (proven: every fleet, house,
-- officer, hull, voyage, and every screen read, old body vs new, dark AND lit). Read profit_tax,
-- influence (K2b), captain_xp, homesick (K6). Touch the merchant planner's estimates (npc_leg_lines'
-- crew_wages, npc_found's wage budget): a merchant holds only the four live company skills, so its
-- estimate and its charge stay equal by construction (asserted: no merchant holds a house skill).
-- Add a gate, a refusal, an entry point or a client grant.
--
-- ── THE PROOF ───────────────────────────────────────────────────────────────────────────────────
-- (a) OLD vs NEW, dark and lit (rolled back), for every company: every fleet's wage (both rations),
--     every crewed quote, every docked fleet's hire quote (1 / 12 / 400), every house × officer wage,
--     every house × hull labour, every house's route cap, every house's and hull's skill bonuses and
--     per cents, every sailing voyage's predicted arrival, storm loss and day delays; and every screen
--     read (world.crew_cost, world.officers, world.inn, world.building_yard, world.standing_routes) as
--     each human house and as nobody, through the old bodies kept under pg_temp names.
-- (b) THE PROBE (own throw-away houses that BUILD their own state, rolled back): dark, the old and new
--     doors give the same hire, signing and settlement, to the byte; lit, Factorage II → 2 more routes (the
--     trigger accepts them and refuses the next, E_ROUTE_CAP), Pursership V → wages × 0.85 (settle's day
--     and the Inn's quote agree), Etiquette II → hire × 0.92 (the door's cost), Recruiting III → wage ×
--     0.85 (paid = printed), Shipwright II → labour × 0.94 (charged = printed), Weather Lore III → every
--     storm's hull × 0.88, Light-air II → every calm's delay × 0.90, the predicted arrival = the settled
--     one, and two settles at different clocks agree.
-- (c) the bodies reverse to their pre-images; ACLs, volatility, definer, config unmoved; new functions
--     carry their siblings' ACL; entry points unmoved. Timings (notice only): K0's merchant reads lit,
--     before vs after this file, and the merchant wage / arrival reads, old vs new.
--
-- ── LOCKS ───────────────────────────────────────────────────────────────────────────────────────
-- Everything heavy runs first. Last, §8 re-makes skill_effects' house CHECK (ACCESS EXCLUSIVE on
-- public.skill_effects, retried on lock_timeout / deadlock, held to commit) for Shipwright's row; after it
-- only that row, a one-house probe and the self-assert (well under a second). Deploy with the clock
-- unwound (DEPLOY_RUNBOOK): unwind_the_clock() → db push → wind_the_clock().
--
-- ROLLBACK: a forward slice restoring the 15 bodies (their hunks' OLD text), dropping the ten new
-- functions and Shipwright's effect row (after asserting no screen or door names them), the CHECK as 0151 made it.
-- SUPERSEDES, by hunks sliced from the LIVE bodies (prod head 0151, LF-normalised), each asserted to
-- occur exactly once, ACLs unchanged: public.standing_routes_cap (0092), world.standing_routes (0093),
-- voyage.settle (0128), voyage.arrival_at (0125), world.crew_cost (0086), cmd.do_dismiss (0086),
-- cmd.do_hire (0097), public.sign_officer (0122), world.inn (0119), world.officers (0127),
-- cmd.do_build (0135), world.building_yard (0135), world.skill_bonuses (0149), world.skill_pct (0149),
-- public.skill_effect_words (0151).
-- VERSION: 0154 (provisional; renumbered to head + 1 at merge). Applies on K1 (0151).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $guard$
begin
  perform set_config('statement_timeout', '30min', true);
  perform set_config('lock_timeout', '5s', true);
  perform set_config('random_page_cost', '1.1', true);   -- prod's planner page cost (0149's header)
end $guard$;

-- ── 0. HELPERS (pg_temp, gone at commit) ───────────────────────────────────────────────────────
create or replace function pg_temp.occurs_0154(p_hay text, p_needle text)
returns int
language sql
immutable
as $$ select (length(p_hay) - length(replace(p_hay, p_needle, ''))) / length(p_needle) $$;

-- run one statement, keep its answer, roll back everything it wrote
create or replace function pg_temp.rb_0154(p_sql text)
returns jsonb
language plpgsql
as $$
declare
  r jsonb;
begin
  begin
    execute p_sql into r;
    raise exception 'RB_0154';
  exception when others then
    if sqlerrm <> 'RB_0154' then raise; end if;
  end;
  return r;
end $$;

-- the same, but a refusal is an answer too: {"error": sqlerrm}
create or replace function pg_temp.try_0154(p_sql text)
returns jsonb
language plpgsql
as $$
declare
  r jsonb;
begin
  begin
    execute p_sql into r;
    raise exception 'RB_0154';
  exception when others then
    if sqlerrm <> 'RB_0154' then r := jsonb_build_object('error', sqlerrm); end if;
  end;
  return r;
end $$;

create or replace function pg_temp.as_0154(p_uid uuid)
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  perform set_config('request.jwt.claims', case when p_uid is null then '' else json_build_object('sub', p_uid)::text end, true);
end $$;

-- ── 1. THE PRE-IMAGES (every heavy read happens here, before anything is changed) ───────────────
create temp table defs_before_0154 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
       (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
       (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
       (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
  from (values ('public.standing_routes_cap()'), ('world.standing_routes()'),
               ('voyage.settle(uuid, timestamp with time zone)'), ('voyage.arrival_at(uuid, timestamp with time zone)'),
               ('world.crew_cost(uuid, integer)'), ('cmd.do_dismiss(uuid, jsonb)'), ('cmd.do_hire(uuid, jsonb)'),
               ('public.sign_officer(uuid, text, uuid)'), ('world.inn(uuid)'), ('world.officers()'),
               ('cmd.do_build(uuid, jsonb)'), ('world.building_yard(uuid)'),
               ('world.skill_bonuses(uuid, uuid)'), ('world.skill_pct(uuid, uuid, text)'),
               ('public.skill_effect_words(text, numeric)')) f(fn);

create temp table untouched_before_0154 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl
  from (values ('public.crew_wages(integer, boolean)'), ('public.hull_labour(text)'),
               ('voyage.day_delay_hours(text, numeric, numeric)'), ('public.skill_level_at(uuid, text, timestamp with time zone)'),
               ('public.house_skill_scopes(uuid, uuid)'), ('voyage.hazard_roll(uuid, integer)'),
               ('public.running_cost_mult(uuid)'), ('public.player_skill_bonus(uuid, text)'),
               ('public.fleet_officer_bonus(uuid, text)'), ('public.npc_leg_lines(uuid, uuid, uuid, numeric, integer, numeric)'),
               ('public.npc_found(jsonb)'), ('cmd.hire_officer(text, uuid)'), ('cmd.preview(uuid, text, jsonb)'),
               ('voyage.delay_before_day(uuid, integer)'), ('voyage.day_ends_at(uuid, integer)')) f(fn);

create temp table before_0154 on commit drop as
select (select count(*) from public.client_rpc_entry_points()) as entry_points,
       (select count(*) from public.skill_effects) as effects,
       (select max(id) from public.skill_effects) as effects_max_id,
       (select md5(string_agg(to_jsonb(e)::text, '|' order by e.id)) from public.skill_effects e) as effects_hash,
       (select count(*) from public.skills) as skills;

-- the old bodies, kept under pg_temp names for §5's comparisons and the probe's doors
do $$
declare
  d     record;
  v_def text;
  v_new text;
begin
  for d in select * from defs_before_0154 loop
    v_new := 'CREATE OR REPLACE FUNCTION pg_temp.' || replace(split_part(d.fn, '(', 1), '.', '_') || '_b0154(';
    v_def := replace(d.def, 'CREATE OR REPLACE FUNCTION ' || split_part(d.fn, '(', 1) || '(', v_new);
    if pg_temp.occurs_0154(v_def, v_new) <> 1 then
      raise exception '0154 self-assert FAIL: could not rename the pre-image of %', d.fn;
    end if;
    execute v_def;
  end loop;
end $$;

-- the old door's hire arithmetic, its lines verbatim (they are hunk 2's and 3's OLD text below)
create or replace function pg_temp.hire_quote_b0154(p_fleet uuid, p_count int)
returns jsonb
language plpgsql
as $$
declare
  f       public.fleets%rowtype;
  v_count int := p_count;
  v_pool  int;
  v_rate  numeric := public.wc_num('hire_crew_rate');
  v_norm  int;
  v_urg   int;
  v_cost  bigint;
begin
  select * into f from public.fleets where id = p_fleet;
  select crew_pool into v_pool from public.ports where id = f.port_id;
  v_norm := least(v_count, case when exists (select 1 from public.players p where p.id = f.player_id and p.is_npc)
                                then greatest(0, v_pool - public.wc_int('npc_crew_pool_floor'))
                                else v_pool end);
  v_urg  := v_count - v_norm;
  v_cost := round(v_norm * v_rate + v_urg * v_rate * public.wc_num('crew_urgent_multiplier'))::bigint;
  return jsonb_build_object('normal', v_norm, 'urgent', v_urg, 'cost', v_cost);
end $$;

-- K0's merchant reads, LIT (rolled back), BEFORE this file — the bound is reported against these
create temp table timing_0154 (what text, ms numeric) on commit drop;
create or replace function pg_temp.time_merchants_0154(p_tag text)
returns void
language plpgsql
as $$
declare
  v_t0 timestamptz;
  v_a  numeric;
  v_b  numeric;
  v_n  numeric;
begin
  begin
    update public.world_config set value = 'true'::jsonb where key = 'skills_bite';
    for i in 1 .. 2 loop
      v_t0 := clock_timestamp();
      select sum(voyage.fleet_speed(f.id)) into v_n from public.fleets f join public.players p on p.id = f.player_id where p.is_npc;
      select sum(public.ship_hold_capacity(s.id)) into v_n from public.ships s join public.players p on p.id = s.player_id where p.is_npc;
      v_a := least(coalesce(v_a, 1e12), round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
      v_t0 := clock_timestamp();
      select count(world.ship_view(s.id)) into v_n from public.ships s join public.players p on p.id = s.player_id where p.is_npc;
      v_b := least(coalesce(v_b, 1e12), round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
    end loop;
    raise exception 'TIME_ROLLBACK_0154';
  exception when others then
    if sqlerrm <> 'TIME_ROLLBACK_0154' then raise; end if;
  end;
  insert into timing_0154 values (p_tag || ' speed+cargo', v_a), (p_tag || ' ship_view', v_b);
end $$;
select pg_temp.time_merchants_0154('before');

-- ── 2. THE READING AT A MOMENT — made FROM the live world.skill_bonuses (its two time reads) ─────
do $$
declare
  v_def text := (select def from defs_before_0154 where fn = 'world.skill_bonuses(uuid, uuid)');
  r     record;
begin
  for r in select * from (values
      (1, 'CREATE OR REPLACE FUNCTION world.skill_bonuses(p_player uuid, p_ship uuid)',
          'CREATE OR REPLACE FUNCTION world.skill_bonuses_at(p_player uuid, p_ship uuid, p_at timestamp with time zone)'),
      (2, E'begin\n',
          E'begin\n  -- 0154 (K2): THE ONE READING, AT A MOMENT. Made from world.skill_bonuses'' body as it stood after 0151\n'
          '  -- with its two time reads at p_at — the finished queue entries and the level (public.skill_level →\n'
          '  -- public.skill_level_at, the one core) — and nothing else. world.skill_bonuses is this at now();\n'
          '  -- voyage.skill_pct_at_departure reads it at a voyage''s departure. house_skill_scopes still asks at\n'
          '  -- now(): a house holds at least what it held before (levels only rise), so the early exit stays sound.\n'),
      (3, 'q.finishes_at <= now()', 'q.finishes_at <= p_at'),
      (4, 'public.skill_level(p_player, sk.code)', 'public.skill_level_at(p_player, sk.code, p_at)')) x(n, a, b) order by n loop
    if pg_temp.occurs_0154(v_def, r.a) <> 1 then
      raise exception '0154 self-assert FAIL: world.skill_bonuses has % copies of piece % — not the body this file was cut against',
        pg_temp.occurs_0154(v_def, r.a), r.n;
    end if;
    v_def := replace(v_def, r.a, r.b);
  end loop;
  execute v_def;
end $$;
revoke all on function world.skill_bonuses_at(uuid, uuid, timestamptz) from public, anon, authenticated;

create or replace function world.skill_pct_at(p_player uuid, p_ship uuid, p_stat text, p_at timestamptz)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  -- 0154 (K2): THE per cent a company's skills add to one stat (of one hull, or with none of the company)
  -- AT A MOMENT: the sum of world.skill_bonuses_at for that stat. world.skill_pct is this at now().
  -- 0 while skills_bite is off.
  return (select coalesce(sum(sb.pct), 0) from world.skill_bonuses_at(p_player, p_ship, p_at) sb where sb.stat = p_stat);
end $$;
revoke all on function world.skill_pct_at(uuid, uuid, text, timestamptz) from public, anon, authenticated;

-- ── 3. THE LIFTED COSTS (each = today's figure while skills_bite is off; proven in §5) ───────────
create or replace function public.fleet_wage(p_fleet uuid, p_short boolean, p_crew integer default null)
returns bigint
language plpgsql
stable
set search_path = public, pg_temp
as $$
declare
  v_player uuid;
  v_crew   int := p_crew;
  v_pct    numeric := 0;
begin
  -- 0154 (K2): THE ONE READING OF A FLEET'S DAILY CREW WAGE — public.crew_wages for its crew (or the crew
  -- named: what a quote asks), × public.running_cost_mult (0114), less Pursership while skills_bite is on.
  -- voyage.settle charges it (owed, 0128), world.crew_cost quotes it, cmd.do_dismiss reports it.
  select f.player_id into v_player from public.fleets f where f.id = p_fleet;
  if v_crew is null then
    select coalesce(sum(sh.crew), 0)::int into v_crew from public.ships sh where sh.fleet_id = p_fleet;
  end if;
  -- (0149's early exit: a house holding no HOUSE-scope skill — every merchant — reads nothing more)
  if public.skills_bite_on() and 'house' = any(public.house_skill_scopes(v_player)) then
    v_pct := world.skill_pct(v_player, null, 'crew_wage');
  end if;
  if v_pct = 0 then
    return round(public.crew_wages(v_crew, p_short) * public.running_cost_mult(v_player))::bigint;
  end if;
  return round(public.crew_wages(v_crew, p_short) * public.running_cost_mult(v_player)
               * (1 - least(v_pct, 100) / 100.0))::bigint;
end $$;
revoke all on function public.fleet_wage(uuid, boolean, integer) from public, anon, authenticated;

create or replace function public.crew_hire_cost(p_fleet uuid, p_count integer)
returns jsonb
language plpgsql
stable
set search_path = public, pg_temp
as $$
declare
  f       public.fleets%rowtype;
  v_count int := p_count;
  v_pool  int;
  v_rate  numeric := public.wc_num('hire_crew_rate');
  v_norm  int;
  v_urg   int;
  v_cost  bigint;
  v_pct   numeric := 0;
begin
  -- 0154 (K2): THE ONE READING OF WHAT HIRING n HANDS COSTS A FLEET WHERE SHE LIES — cmd.do_hire's own
  -- lines, lifted: 0097's split (a merchant draws only the hands above npc_crew_pool_floor; the rest, and
  -- anyone's ask beyond the pool, are URGENT, at crew_urgent_multiplier, taking nothing off the quay) and
  -- DESIGN F.2's price; less Etiquette while skills_bite is on. {normal, urgent, cost}. cmd.do_hire charges
  -- it and draws the pool by its split; the Inn's price is cmd.preview of that door.
  select * into f from public.fleets where id = p_fleet;
  select crew_pool into v_pool from public.ports where id = f.port_id;
  v_norm := least(v_count, case when exists (select 1 from public.players p where p.id = f.player_id and p.is_npc)
                                then greatest(0, v_pool - public.wc_int('npc_crew_pool_floor'))
                                else v_pool end);
  v_urg  := v_count - v_norm;
  if public.skills_bite_on() then
    v_pct := world.skill_pct(f.player_id, null, 'crew_hire');
  end if;
  if v_pct = 0 then
    v_cost := round(v_norm * v_rate + v_urg * v_rate * public.wc_num('crew_urgent_multiplier'))::bigint;
  else
    v_cost := round((v_norm * v_rate + v_urg * v_rate * public.wc_num('crew_urgent_multiplier'))
                    * (1 - least(v_pct, 100) / 100.0))::bigint;
  end if;
  return jsonb_build_object('normal', v_norm, 'urgent', v_urg, 'cost', v_cost);
end $$;
revoke all on function public.crew_hire_cost(uuid, integer) from public, anon, authenticated;

create or replace function public.captain_wage(p_player uuid, p_officer uuid)
returns bigint
language plpgsql
stable
set search_path = public, pg_temp
as $$
declare
  v_wage bigint;
  v_pct  numeric := 0;
begin
  -- 0154 (K2): THE ONE READING OF WHAT SIGNING A CAPTAIN COSTS A HOUSE — officers.wage_ducats (paid once,
  -- at signing), less Recruiting while skills_bite is on. public.sign_officer charges it; world.inn and
  -- world.officers print it. With no house (nobody signed in) it is the wage itself.
  select o.wage_ducats into v_wage from public.officers o where o.id = p_officer;
  if v_wage is null or p_player is null or not public.skills_bite_on() then
    return v_wage;
  end if;
  v_pct := world.skill_pct(p_player, null, 'captain_wage');
  if v_pct = 0 then
    return v_wage;
  end if;
  return round(v_wage * (1 - least(v_pct, 100) / 100.0))::bigint;
end $$;
revoke all on function public.captain_wage(uuid, uuid) from public, anon, authenticated;

create or replace function public.yard_labour(p_player uuid, p_class text)
returns bigint
language plpgsql
stable
set search_path = public, pg_temp
as $$
declare
  v_base bigint := public.hull_labour(p_class);
  v_pct  numeric := 0;
begin
  -- 0154 (K2): THE ONE READING OF WHAT A YARD CHARGES A HOUSE FOR A HULL'S WORK — public.hull_labour (0135:
  -- the recipe × hull_labour_mult, the base), less Shipwright while skills_bite is on. cmd.do_build charges
  -- it; world.building_yard prints it. Null for a class no yard builds; the base with no house.
  if v_base is null or p_player is null or not public.skills_bite_on() then
    return v_base;
  end if;
  v_pct := world.skill_pct(p_player, null, 'yard_labour');
  if v_pct = 0 then
    return v_base;
  end if;
  return round(v_base * (1 - least(v_pct, 100) / 100.0))::bigint;
end $$;
revoke all on function public.yard_labour(uuid, text) from public, anon, authenticated;

create or replace function public.standing_route_max_for(p_player uuid)
returns integer
language plpgsql
stable
set search_path = public, pg_temp
as $$
declare
  v_max int := public.wc_int('standing_route_max');
begin
  -- 0154 (K2): THE ONE READING OF HOW MANY ROUTES A HOUSE MAY KEEP — the knob standing_route_max, plus one
  -- per level of Factorage while skills_bite is on. The trigger standing_routes_cap() refuses beyond it;
  -- world.standing_routes serves it as `max`. The knob itself with no house.
  if p_player is null or not public.skills_bite_on() then
    return v_max;
  end if;
  return v_max + floor(world.skill_pct(p_player, null, 'standing_routes'))::int;
end $$;
revoke all on function public.standing_route_max_for(uuid) from public, anon, authenticated;

create or replace function voyage.skill_pct_at_departure(p_voyage uuid, p_stat text)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_player uuid;
  v_at     timestamptz;
begin
  -- 0154 (K2): what the sailing house's skills add to one house stat AS IT DEPARTED (world.skill_pct_at at
  -- the voyage's departed_at), so a day's settlement is the same whenever it runs. 0 while skills_bite is off.
  if not public.skills_bite_on() then
    return 0;
  end if;
  select v.player_id, v.departed_at into v_player, v_at from public.voyages v where v.id = p_voyage;
  -- (0149's early exit: a house holding no HOUSE-scope skill — every merchant — reads nothing more)
  if v_player is null or not ('house' = any(public.house_skill_scopes(v_player))) then
    return 0;
  end if;
  return world.skill_pct_at(v_player, null, p_stat, v_at);
end $$;
revoke all on function voyage.skill_pct_at_departure(uuid, text) from public, anon, authenticated;

create or replace function voyage.storm_hull_lost(p_voyage uuid, p_maxd numeric, p_magnitude numeric)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_pct numeric := voyage.skill_pct_at_departure(p_voyage, 'storm_damage');
begin
  -- 0154 (K2): THE STORM's hull loss for one hull of this voyage — DESIGN B.6's maxd × (0.08 + 0.17 ×
  -- magnitude), moved verbatim out of voyage.settle's STORM arm, less Weather Lore (at departure) while
  -- skills_bite is on. Rounded to the hundredth as the arm always rounded it.
  if v_pct = 0 then
    return round(p_maxd * (0.08 + 0.17 * p_magnitude), 2);
  end if;
  return round(p_maxd * (0.08 + 0.17 * p_magnitude) * (1 - least(v_pct, 100) / 100.0), 2);
end $$;
revoke all on function voyage.storm_hull_lost(uuid, numeric, numeric) from public, anon, authenticated;

create or replace function voyage.day_delay_for(p_voyage uuid, p_kind text, p_magnitude numeric, p_prior numeric)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_hours numeric := voyage.day_delay_hours(p_kind, p_magnitude, p_prior);
  v_pct   numeric;
begin
  -- 0154 (K2): what a day's roll costs THIS voyage, in sim-hours — 0125's one table (voyage.day_delay_hours),
  -- and for a CALM less Light-air Sailing (at departure) while skills_bite is on. voyage.settle's STORM,
  -- CALM and FAIR_WIND arms and voyage.arrival_at's fixed point read it, so the arrival the game predicts
  -- is the arrival it settles.
  if p_kind is distinct from 'CALM' or v_hours = 0 then
    return v_hours;
  end if;
  v_pct := voyage.skill_pct_at_departure(p_voyage, 'calm_delay');
  if v_pct = 0 then
    return v_hours;
  end if;
  return round(v_hours * (1 - least(v_pct, 100) / 100.0), 2);
end $$;
revoke all on function voyage.day_delay_for(uuid, text, numeric, numeric) from public, anon, authenticated;

-- ── 4. THE RE-CUTS (hunks: old = verbatim from the live bodies; new = what replaces it) ─────────
create temp table hunks_0154 (fn text, n int, old text, new text) on commit drop;
insert into hunks_0154 values
('public.standing_routes_cap()', 1,
$h$declare v_max int := public.wc_int('standing_route_max');
$h$,
$h$declare v_max int := public.standing_route_max_for(new.player_id);   -- 0154 (K2): the knob + Factorage, the one reading
$h$),
('world.standing_routes()', 1,
$h$    'max',               public.wc_int('standing_route_max'),
$h$,
$h$    'max',               public.standing_route_max_for(v_player),   -- 0154 (K2): what the cap trigger refuses beyond
$h$),
('voyage.settle(uuid, timestamp with time zone)', 1,
$h$    select round(public.crew_wages(coalesce(sum(sh.crew), 0)::int, v_short)
                 * public.running_cost_mult(f.player_id))::bigint
      into v_wages from public.ships sh where sh.fleet_id = p_fleet;
$h$,
$h$    -- 0154 (K2): the day's wage is public.fleet_wage — THE one reading (crew_wages × running_cost_mult, less
    -- Pursership while skills_bite), the figure world.crew_cost quotes for this fleet.
    v_wages := public.fleet_wage(p_fleet, v_short);
$h$),
('voyage.settle(uuid, timestamp with time zone)', 2,
$h$        v_lost := round(s.maxd * (0.08 + 0.17 * h.magnitude), 2);
$h$,
$h$        v_lost := voyage.storm_hull_lost(v.id, s.maxd, h.magnitude);   -- 0154 (K2): the one storm rule (Weather Lore at departure)
$h$),
('voyage.settle(uuid, timestamp with time zone)', 3,
$h$      v_delay   := voyage.day_delay_hours(h.kind, h.magnitude, voyage.delay_before_day(v.id, d));   -- 0125: DESIGN B.6 +1.5 days, the one table
$h$,
$h$      v_delay   := voyage.day_delay_for(v.id, h.kind, h.magnitude, voyage.delay_before_day(v.id, d));   -- 0125: DESIGN B.6 +1.5 days, the one table (0154: for this voyage)
$h$),
('voyage.settle(uuid, timestamp with time zone)', 4,
$h$      v_delay   := voyage.day_delay_hours(h.kind, h.magnitude, voyage.delay_before_day(v.id, d));   -- 0125: DESIGN B.6 1-4 days, the one table
$h$,
$h$      v_delay   := voyage.day_delay_for(v.id, h.kind, h.magnitude, voyage.delay_before_day(v.id, d));   -- 0125: DESIGN B.6 1-4 days, the one table (0154: less Light-air)
$h$),
('voyage.settle(uuid, timestamp with time zone)', 5,
$h$      v_gain    := -voyage.day_delay_hours(h.kind, h.magnitude, voyage.delay_before_day(v.id, d));   -- 0125: the one table
$h$,
$h$      v_gain    := -voyage.day_delay_for(v.id, h.kind, h.magnitude, voyage.delay_before_day(v.id, d));   -- 0125: the one table (0154: for this voyage)
$h$),
('voyage.arrival_at(uuid, timestamp with time zone)', 1,
$h$      v_delay := v_delay + voyage.day_delay_hours(h.kind, h.magnitude, v_delay);
$h$,
$h$      v_delay := v_delay + voyage.day_delay_for(v.id, h.kind, h.magnitude, v_delay);   -- 0154 (K2): what settle charges
$h$),
('world.crew_cost(uuid, integer)', 1,
$h$    'per_day', public.crew_wages(v_crew, false),
    'per_day_short_rations', public.crew_wages(v_crew, true));
$h$,
$h$    -- 0154 (K2): public.fleet_wage, the figure voyage.settle charges this fleet for that crew
    'per_day', public.fleet_wage(p_fleet, false, v_crew),
    'per_day_short_rations', public.fleet_wage(p_fleet, true, v_crew));
$h$),
('cmd.do_dismiss(uuid, jsonb)', 1,
$h$                            'wages_per_day', public.crew_wages(v_after, false));
$h$,
$h$                            'wages_per_day', public.fleet_wage(p_fleet, false, v_after));   -- 0154 (K2)
$h$),
('cmd.do_hire(uuid, jsonb)', 1,
$h$  v_rate  numeric := public.wc_num('hire_crew_rate');
$h$,
$h$  -- 0154 (K2): the rate, the split and the price are public.crew_hire_cost's
$h$),
('cmd.do_hire(uuid, jsonb)', 2,
$h$  v_norm := least(v_count, case when exists (select 1 from public.players p where p.id = f.player_id and p.is_npc)
                                then greatest(0, v_pool - public.wc_int('npc_crew_pool_floor'))
                                else v_pool end);
  v_urg  := v_count - v_norm;
$h$,
$h$  -- 0154 (K2): THE SPLIT AND THE PRICE are public.crew_hire_cost's — these lines, lifted (and less Etiquette
  -- while skills_bite) — read once: the refusals below, the pool draw and the payment use them.
  select (q->>'normal')::int, (q->>'urgent')::int, (q->>'cost')::bigint into v_norm, v_urg, v_cost
    from public.crew_hire_cost(p_fleet, v_count) q;
$h$),
('cmd.do_hire(uuid, jsonb)', 3,
$h$  v_cost := round(v_norm * v_rate + v_urg * v_rate * public.wc_num('crew_urgent_multiplier'))::bigint;
$h$,
$h$  -- 0154: v_cost is public.crew_hire_cost's (above)
$h$),
('public.sign_officer(uuid, text, uuid)', 1,
$h$      'error_message', format('No officer answers to "%s".', v_code), 'fixes', '[]'::jsonb);
  end if;
$h$,
$h$      'error_message', format('No officer answers to "%s".', v_code), 'fixes', '[]'::jsonb);
  end if;
  -- 0154 (K2): what she signs for is public.captain_wage — the one reading (less Recruiting while
  -- skills_bite), the figure world.inn and world.officers print; every use below reads it.
  v_off.wage_ducats := public.captain_wage(v_player, v_off.id);
$h$),
('world.inn(uuid)', 1,
$h$'wage', o.wage_ducats, 'blurb'$h$,
$h$'wage', public.captain_wage(v_player, o.id), 'blurb'$h$),
('world.officers()', 1,
$h$'wage', o.wage_ducats, 'blurb'$h$,
$h$'wage', public.captain_wage(v_player, o.id), 'blurb'$h$),
('cmd.do_build(uuid, jsonb)', 1,
$h$  h.ducats := public.hull_labour(c.code);
$h$,
$h$  h.ducats := public.yard_labour(f.player_id, c.code);   -- 0154 (K2): hull_labour less Shipwright, the one reading
$h$),
('world.building_yard(uuid)', 1,
$h$'ducats', public.hull_labour(h.class_code),$h$,
$h$'ducats', public.yard_labour(v_player, h.class_code),$h$),
('world.skill_pct(uuid, uuid, text)', 1,
$h$  select coalesce(sum(sb.pct), 0) from world.skill_bonuses(p_player, p_ship) sb where sb.stat = p_stat
$h$,
$h$  -- 0154 (K2): the one sum, at now() — world.skill_pct_at (a voyage asks it at her departure)
  select world.skill_pct_at(p_player, p_ship, p_stat, now())
$h$),
('world.skill_bonuses(uuid, uuid)', 1,
$h$  -- 0133: THE ONE READING OF WHAT A COMPANY'S SKILLS GIVE — for one of its hulls (scopes ship and
  -- fitting, through the hull's line / size / role / tech), or with no hull for the company itself
  -- (scope house: Command). One row per bonus, BY SOURCE: the skill, its level (public.skill_level —
  -- the one reading, a finished queue entry included), the per cent (per level × level), "Portuguese
  -- Medium Hulls III" and "+12% sighting". NOTHING while skills_bite is off. Company effects (the
  -- live four) are not here: public.player_skill_bonus reads them, as it always has.
  -- Cheap for a merchant: her fixed skills are the live four, which carry only company effects, so
  -- the join below finds no row and no level is read — no merchant flag is read, no exemption.
  if p_player is null or not public.skills_bite_on() then
    return;
  end if;
  -- 0149: … nor for a company that holds no skill with an effect of the scope this read can return
  -- (public.house_skill_scopes, one indexed read): no row below could match it. Every merchant leaves here.
  if not (public.house_skill_scopes(p_player)
          && case when p_ship is null then array['house'] else array['ship', 'fitting'] end) then
    return;
  end if;
  return query
  with held as (
    select ps.skill_id from public.player_skills ps where ps.player_id = p_player
    union
    select q.skill_id from public.skill_queue q where q.player_id = p_player and q.finishes_at <= now()
  ),
  prof as (
    select cp.line_code, cp.size, cp.role, cp.tech
      from public.ships s
      join public.ship_classes c on c.id = s.class_id
      left join public.class_profile cp on cp.class_code = c.code
     where s.id = p_ship
  )
  select e.stat, e.scope, sk.code, l.lvl, e.pct_per_level * l.lvl,
         sk.name || ' ' || public.skill_level_word(l.lvl),
         public.skill_effect_words(e.stat, e.pct_per_level * l.lvl)
    from held h
    join public.skills sk on sk.id = h.skill_id
    join public.skill_effects e on e.skill_code = sk.code and e.scope <> 'company'
    left join prof p on true
   cross join lateral (select public.skill_level(p_player, sk.code) as lvl) l
   where l.lvl > 0
     and case when p_ship is null then e.scope = 'house'
              else e.scope in ('ship', 'fitting') and exists (select 1 from prof) end
     and (e.line_code is null or e.line_code = p.line_code)
     and (e.size is null or e.size = p.size)
     and (e.role is null or e.role = p.role)
     and (e.tech is null or e.tech = p.tech)
   order by sk.code, e.stat;
$h$,
$h$  -- 0133: THE ONE READING OF WHAT A COMPANY'S SKILLS GIVE — one row per bonus, BY SOURCE (scopes ship and
  -- fitting for a hull, house for the company). 0154 (K2): it lives in world.skill_bonuses_at (the same
  -- body, a level AT A MOMENT through public.skill_level_at); this is that reading at now(), row for row
  -- as before (0154 proved it over every house and hull). NOTHING while skills_bite is off.
  return query select * from world.skill_bonuses_at(p_player, p_ship, now());
$h$),
('public.skill_effect_words(text, numeric)', 1,
$h$  select case when p_stat = 'high_hands' then '−' else '+' end || trim_scale(p_pct)::text || '% ' ||
$h$,
$h$  -- 0154 (K2): the house effects that take OFF (wages, hiring, labour, storm harm, calm time) read "−",
  -- and a route is a count, not a per cent ("+2 routes"; WORDS: the player reads "route").
  select case when p_stat in ('high_hands', 'crew_wage', 'captain_wage', 'crew_hire', 'yard_labour',
                              'storm_damage', 'calm_delay') then '−' else '+' end || trim_scale(p_pct)::text ||
         case when p_stat = 'standing_routes' then ' ' else '% ' end ||
$h$),
('public.skill_effect_words(text, numeric)', 2,
$h$                     when 'officer_bonus' then 'officer bonuses'
$h$,
$h$                     when 'officer_bonus' then 'officer bonuses'
                     when 'standing_routes' then case when p_pct = 1 then 'route' else 'routes' end   -- 0154: Factorage
                     when 'crew_wage'     then 'crew wages'            -- 0154: Pursership
                     when 'captain_wage'  then 'captain wages'         -- 0154: Recruiting
                     when 'crew_hire'     then 'crew hiring'           -- 0154: Etiquette
                     when 'yard_labour'   then 'yard labour'           -- 0154: Shipwright
                     when 'storm_damage'  then 'storm damage'          -- 0154: Weather Lore
                     when 'calm_delay'    then 'time lost in a calm'   -- 0154: Light-air Sailing
$h$);

create or replace function pg_temp.recut_0154(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0154 where fn = p_fn order by n loop
    v_n := pg_temp.occurs_0154(v_def, h.old);
    if v_n <> 1 then
      raise exception '0154 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0154(fn) from defs_before_0154 order by fn;

-- the ACL each new function must carry: its sibling's (Supabase's default grants included)
create temp table acl_0154 (fn text, sibling text) on commit drop;
insert into acl_0154 values
  ('world.skill_bonuses_at(uuid, uuid, timestamp with time zone)', 'world.skill_bonuses(uuid, uuid)'),
  ('world.skill_pct_at(uuid, uuid, text, timestamp with time zone)', 'world.skill_pct(uuid, uuid, text)'),
  ('public.fleet_wage(uuid, boolean, integer)', 'public.crew_wages(integer, boolean)'),
  ('public.crew_hire_cost(uuid, integer)', 'public.crew_wages(integer, boolean)'),
  ('public.captain_wage(uuid, uuid)', 'public.sign_officer(uuid, text, uuid)'),
  ('public.yard_labour(uuid, text)', 'public.hull_labour(text)'),
  ('public.standing_route_max_for(uuid)', 'public.standing_routes_cap()'),
  ('voyage.skill_pct_at_departure(uuid, text)', 'voyage.arrival_at(uuid, timestamp with time zone)'),
  ('voyage.storm_hull_lost(uuid, numeric, numeric)', 'voyage.arrival_at(uuid, timestamp with time zone)'),
  ('voyage.day_delay_for(uuid, text, numeric, numeric)', 'voyage.arrival_at(uuid, timestamp with time zone)');

-- ── 5. THE COMPARISONS (old body vs new, for every company), dark and lit ───────────────────────
create or replace function pg_temp.compare_0154()
returns jsonb
language plpgsql
as $$
declare
  v_out jsonb := '{}'::jsonb;
  v_bad int;
  v_n   int;
  h     record;
  p     record;
  v_a   jsonb;
  v_b   jsonb;
  v_sn  int := 0;
  v_sb  int := 0;
  v_ex  text;
begin
  -- the day's wage: settle's old inline sum, every fleet, both rations
  select count(*), count(*) filter (where a is distinct from b) into v_n, v_bad
    from (select public.fleet_wage(f.id, s.short) as a,
                 (select round(public.crew_wages(coalesce(sum(sh.crew), 0)::int, s.short)
                               * public.running_cost_mult(f.player_id))::bigint
                    from public.ships sh where sh.fleet_id = f.id) as b
            from public.fleets f cross join (values (false), (true)) s(short)) z;
  v_out := v_out || jsonb_build_object('wage', jsonb_build_object('n', v_n, 'bad', v_bad));
  -- a quote for a named crew (world.crew_cost's old figure; a player's mult is 1), every human fleet
  select count(*), count(*) filter (where a is distinct from b) into v_n, v_bad
    from (select public.fleet_wage(f.id, s.short, c.n) as a, public.crew_wages(c.n, s.short) as b
            from public.fleets f join public.players pl on pl.id = f.player_id and not pl.is_npc
           cross join (values (false), (true)) s(short) cross join (values (0), (7), (113)) c(n)) z;
  v_out := v_out || jsonb_build_object('wage_quote', jsonb_build_object('n', v_n, 'bad', v_bad));
  -- the hire: the old door's lines, every fleet lying in a port
  select count(*), count(*) filter (where a is distinct from b) into v_n, v_bad
    from (select public.crew_hire_cost(f.id, c.n) as a, pg_temp.hire_quote_b0154(f.id, c.n) as b
            from public.fleets f cross join (values (1), (12), (400)) c(n)
           where f.port_id is not null) z;
  v_out := v_out || jsonb_build_object('hire', jsonb_build_object('n', v_n, 'bad', v_bad));
  -- a captain's wage, every house × every officer
  select count(*), count(*) filter (where public.captain_wage(pl.id, o.id) is distinct from o.wage_ducats) into v_n, v_bad
    from public.players pl cross join public.officers o;
  v_out := v_out || jsonb_build_object('captain', jsonb_build_object('n', v_n, 'bad', v_bad));
  -- a hull's labour, every house × every hull a yard builds
  select count(*), count(*) filter (where public.yard_labour(pl.id, h2.class_code) is distinct from public.hull_labour(h2.class_code)) into v_n, v_bad
    from public.players pl cross join public.hull_recipes h2;
  v_out := v_out || jsonb_build_object('yard', jsonb_build_object('n', v_n, 'bad', v_bad));
  -- the route cap, every house
  select count(*), count(*) filter (where public.standing_route_max_for(pl.id) is distinct from public.wc_int('standing_route_max')) into v_n, v_bad
    from public.players pl;
  v_out := v_out || jsonb_build_object('routes', jsonb_build_object('n', v_n, 'bad', v_bad));
  -- THE READING: every house (no hull) and every hull (its house), rows and per cents
  select count(*), count(*) filter (where a is distinct from b or pa is distinct from pb) into v_n, v_bad
    from (select (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from world.skill_bonuses(k.player, k.ship) x) as a,
                 (select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) from pg_temp.world_skill_bonuses_b0154(k.player, k.ship) x) as b,
                 jsonb_build_array(world.skill_pct(k.player, k.ship, 'hold'), world.skill_pct(k.player, k.ship, 'speed'),
                                   world.skill_pct(k.player, k.ship, 'deck'), world.skill_pct(k.player, null, 'officer_bonus')) as pa,
                 jsonb_build_array(pg_temp.world_skill_pct_b0154(k.player, k.ship, 'hold'), pg_temp.world_skill_pct_b0154(k.player, k.ship, 'speed'),
                                   pg_temp.world_skill_pct_b0154(k.player, k.ship, 'deck'), pg_temp.world_skill_pct_b0154(k.player, null, 'officer_bonus')) as pb
            from (select pl.id as player, null::uuid as ship from public.players pl
                  union all
                  select s.player_id, s.id from public.ships s) k) z;
  v_out := v_out || jsonb_build_object('reading', jsonb_build_object('n', v_n, 'bad', v_bad));
  -- every voyage at sea: the arrival the game predicts (forced past the eta, so the fixed point runs),
  -- a storm's loss on each of her hulls, and what each kind of day costs her
  select count(*), count(*) filter (where a is distinct from b) into v_n, v_bad
    from (select voyage.arrival_at(v.id, greatest(now(), v.eta) + interval '1 hour') as a,
                 pg_temp.voyage_arrival_at_b0154(v.id, greatest(now(), v.eta) + interval '1 hour') as b
            from public.voyages v where v.status = 'SAILING') z;
  v_out := v_out || jsonb_build_object('arrival', jsonb_build_object('n', v_n, 'bad', v_bad));
  select count(*), count(*) filter (where voyage.storm_hull_lost(v.id, c.durability, m.m) is distinct from round(c.durability * (0.08 + 0.17 * m.m), 2))
    into v_n, v_bad
    from public.voyages v join public.ships s on s.fleet_id = v.fleet_id join public.ship_classes c on c.id = s.class_id
   cross join (values (0::numeric), (0.371), (1)) m(m)
   where v.status = 'SAILING';
  v_out := v_out || jsonb_build_object('storm', jsonb_build_object('n', v_n, 'bad', v_bad));
  select count(*), count(*) filter (where voyage.day_delay_for(v.id, k.k, m.m, pr.p) is distinct from voyage.day_delay_hours(k.k, m.m, pr.p))
    into v_n, v_bad
    from public.voyages v cross join (values ('STORM'), ('CALM'), ('FAIR_WIND'), ('PIRATES')) k(k)
   cross join (values (0::numeric), (0.371), (1)) m(m) cross join (values (0::numeric), (30)) pr(p)
   where v.status = 'SAILING';
  v_out := v_out || jsonb_build_object('delay', jsonb_build_object('n', v_n, 'bad', v_bad));
  -- the words, every stat × per cent the catalogue can print
  select count(*), count(*) filter (where public.skill_effect_words(e.stat, e.pct_per_level * l.l)
                                          is distinct from pg_temp.public_skill_effect_words_b0154(e.stat, e.pct_per_level * l.l)) into v_n, v_bad
    from public.skill_effects e cross join generate_series(1, 5) l(l)
   where e.stat not in ('standing_routes', 'crew_wage', 'captain_wage', 'crew_hire', 'yard_labour', 'storm_damage', 'calm_delay');
  v_out := v_out || jsonb_build_object('words', jsonb_build_object('n', v_n, 'bad', v_bad));

  -- THE SCREENS, as nobody and as each human house (old body vs new; a read that settles is rolled back)
  for p in select null::uuid as uid, null::uuid as id
           union all
           select pl.auth_uid, pl.id from public.players pl where not pl.is_npc and pl.auth_uid is not null loop
    perform pg_temp.as_0154(p.uid);
    v_a := jsonb_build_array(world.officers());
    v_b := jsonb_build_array(pg_temp.world_officers_b0154());
    v_sn := v_sn + 1; if v_a is distinct from v_b then v_sb := v_sb + 1; v_ex := coalesce(v_ex, 'officers'); end if;
    for h in select distinct b.port_id
               from public.port_buildings b
              where b.kind in ('inn', 'building_yard')
                and (p.id is null or b.port_id in (select f.port_id from public.fleets f where f.player_id = p.id)
                     or b.port_id = (select pt.id from public.ports pt where pt.code = 'LIS')) loop
      if exists (select 1 from public.port_buildings b where b.port_id = h.port_id and b.kind = 'inn') then
        v_sn := v_sn + 1;
        if world.inn(h.port_id) is distinct from pg_temp.world_inn_b0154(h.port_id) then v_sb := v_sb + 1; v_ex := coalesce(v_ex, 'inn'); end if;
      end if;
      if exists (select 1 from public.port_buildings b where b.port_id = h.port_id and b.kind = 'building_yard') then
        v_sn := v_sn + 1;
        if world.building_yard(h.port_id) is distinct from pg_temp.world_building_yard_b0154(h.port_id) then v_sb := v_sb + 1; v_ex := coalesce(v_ex, 'yard'); end if;
      end if;
    end loop;
    if p.id is not null then
      for h in select f.id from public.fleets f where f.player_id = p.id loop
        v_sn := v_sn + 2;
        if world.crew_cost(h.id) is distinct from pg_temp.world_crew_cost_b0154(h.id) then v_sb := v_sb + 1; v_ex := coalesce(v_ex, 'crew_cost'); end if;
        if world.crew_cost(h.id, 37) is distinct from pg_temp.world_crew_cost_b0154(h.id, 37) then v_sb := v_sb + 1; v_ex := coalesce(v_ex, 'crew_cost 37'); end if;
      end loop;
      v_sn := v_sn + 1;
      if pg_temp.rb_0154('select world.standing_routes()') is distinct from pg_temp.rb_0154('select pg_temp.world_standing_routes_b0154()') then
        v_sb := v_sb + 1; v_ex := coalesce(v_ex, 'standing_routes');
      end if;
    end if;
  end loop;
  perform pg_temp.as_0154(null);
  v_out := v_out || jsonb_build_object('screens', jsonb_build_object('n', v_sn, 'bad', v_sb, 'first', v_ex));
  return v_out;
end $$;

create temp table proven_0154 (k text primary key, v jsonb) on commit drop;
do $$
declare
  r       jsonb;
  v_lit   boolean;
  v_try   int;
  v_state text;
  v_msg   text;
begin
  foreach v_lit in array array[false, true] loop
    v_try := 0;
    loop
      v_try := v_try + 1;
      begin
        begin
          if v_lit then
            update public.world_config set value = 'true'::jsonb where key = 'skills_bite';
          end if;
          r := pg_temp.compare_0154();
          raise exception 'LIT_ROLLBACK_0154';
        exception when others then
          if sqlerrm <> 'LIT_ROLLBACK_0154' then raise; end if;
        end;
        exit;
      exception when lock_not_available or deadlock_detected then
        -- a screen read that settles (world.standing_routes) waited on a player's write: ask again
        get stacked diagnostics v_msg = message_text, v_state = returned_sqlstate;
        if v_try >= 5 then
          raise exception '0154 self-assert FAIL: LOCK CONTENTION, not a result — the comparison could not get its locks in 5 tries (%: %). Re-run the push.',
            v_state, v_msg;
        end if;
        perform pg_sleep(0.2);
      end;
    end loop;
    insert into proven_0154 values (case when v_lit then 'lit' else 'dark' end, r);
  end loop;
end $$;

-- K0's merchant reads, lit, AFTER the re-cuts; and the two merchant hot reads this file moves, old vs new
select pg_temp.time_merchants_0154('after');
do $$
declare
  v_t0  timestamptz;
  v_old numeric;
  v_new numeric;
  v_lit numeric;
  v_n   numeric;
begin
  for i in 1 .. 2 loop
    v_t0 := clock_timestamp();
    select sum((select round(public.crew_wages(coalesce(sum(sh.crew), 0)::int, false) * public.running_cost_mult(f.player_id))::bigint
                  from public.ships sh where sh.fleet_id = f.id)) into v_n
      from public.fleets f join public.players p on p.id = f.player_id where p.is_npc;
    v_old := least(coalesce(v_old, 1e12), round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
    v_t0 := clock_timestamp();
    select sum(public.fleet_wage(f.id, false)) into v_n from public.fleets f join public.players p on p.id = f.player_id where p.is_npc;
    v_new := least(coalesce(v_new, 1e12), round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
  end loop;
  begin
    update public.world_config set value = 'true'::jsonb where key = 'skills_bite';
    for i in 1 .. 2 loop
      v_t0 := clock_timestamp();
      select sum(public.fleet_wage(f.id, false)) into v_n from public.fleets f join public.players p on p.id = f.player_id where p.is_npc;
      v_lit := least(coalesce(v_lit, 1e12), round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
    end loop;
    raise exception 'TIME_ROLLBACK_0154';
  exception when others then
    if sqlerrm <> 'TIME_ROLLBACK_0154' then raise; end if;
  end;
  insert into timing_0154 values ('merchant wages old', v_old), ('merchant wages new dark', v_new), ('merchant wages new lit', v_lit);
end $$;

-- ── 6. THE PROBE (own throw-away houses that build their own state; rolled back) ────────────────
create or replace function pg_temp.voyage_digest_0154(p_voyage uuid, p_fleet uuid)
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'voyage', (select jsonb_build_object('status', v.status, 'eta', v.eta, 'delay_hours', v.delay_hours,
                                         'last_settled_day', v.last_settled_day, 'wages_paid', v.wages_paid)
                 from public.voyages v where v.id = p_voyage),
    'events', (select coalesce(jsonb_agg(jsonb_build_object('day', ve.day_index, 'kind', ve.kind, 'payload', ve.payload)
                                         order by ve.day_index, ve.kind), '[]'::jsonb)
                 from public.voyage_events ve where ve.voyage_id = p_voyage),
    'ships', (select coalesce(jsonb_agg(jsonb_build_object('d', s.durability, 'crew', s.crew, 'water', s.water_t, 'food', s.food_t)
                                        order by s.id), '[]'::jsonb)
                from public.ships s where s.fleet_id = p_fleet),
    'fleet', (select jsonb_build_object('status', f.status, 'port', f.port_id) from public.fleets f where f.id = p_fleet))
$$;

create or replace function pg_temp.probe_0154()
returns jsonb
language plpgsql
as $$
declare
  c_uid   constant uuid := '00000000-0154-4000-8000-000000000001';
  v_p     uuid;
  v_pf    uuid;
  v_ps    uuid;
  v_lis   uuid := (select id from public.ports where code = 'LIS');
  v_fnc   uuid := (select id from public.ports where code = 'FNC');
  v_leg   jsonb;
  v_off   public.officers%rowtype;
  v_out   jsonb := '{}'::jsonb;
  v_voy   uuid;
  v_try   int := 0;
  v_cap   int;
  v_storm int;
  v_calm  int;
  v_r     jsonb;
  v_base  int := public.wc_int('standing_route_max');
  i       int;
begin
  begin
    if public.skills_bite_on() then
      raise exception '0154 self-assert FAIL: skills_bite is on before the probe — this file ships it dark';
    end if;
    -- P: a company docked at Lisbon, ten hands aboard, holding the six skills K2 reads
    v_p := public.new_house(c_uid, 'Casa da Prova 0154', 'PRT', 'LIS');
    select id into v_pf from public.fleets where player_id = v_p;
    select id into v_ps from public.ships where fleet_id = v_pf;
    perform public.credit(v_p, 'PROBE_0154', 10000000);
    update public.ships set crew = 10 where id = v_ps;
    insert into public.player_skills (player_id, skill_id, level)
    select v_p, s.id, x.lvl from (values ('FACTORAGE', 2), ('PURSERSHIP', 5), ('ETIQUETTE', 2), ('RECRUITING', 3),
                                         ('WEATHER_LORE', 3), ('LIGHT_AIR', 2)) x(code, lvl)
      join public.skills s on s.code = x.code;
    select * into v_off from public.officers order by wage_ducats desc, code limit 1;

    -- DARK: the figures are today's, and the old and new doors answer alike, to the byte
    v_out := v_out || jsonb_build_object('dark', jsonb_build_object(
      'route_max', public.standing_route_max_for(v_p),
      'routes', pg_temp.try_0154(format('select pg_temp.routes_0154(%L, %s)', v_p, v_base + 1)),
      'routes_ok', pg_temp.try_0154(format('select pg_temp.routes_0154(%L, %s)', v_p, v_base)),
      'wage', public.fleet_wage(v_pf, false), 'wage_short', public.fleet_wage(v_pf, true),
      'crew_wages', public.crew_wages(10, false), 'crew_wages_short', public.crew_wages(10, true),
      'hire_quote', public.crew_hire_cost(v_pf, 10), 'hire_old_quote', pg_temp.hire_quote_b0154(v_pf, 10),
      'hire_new', pg_temp.rb_0154(format('select cmd.do_hire(%L, %L)', v_pf, '{"count": 10}')),
      'hire_old', pg_temp.rb_0154(format('select pg_temp.cmd_do_hire_b0154(%L, %L)', v_pf, '{"count": 10}')),
      'sign_new', pg_temp.rb_0154(format('select public.sign_officer(%L, %L, %L)', v_p, v_off.code, v_pf)),
      'sign_old', pg_temp.rb_0154(format('select pg_temp.public_sign_officer_b0154(%L, %L, %L)', v_p, v_off.code, v_pf)),
      'wage_of', v_off.wage_ducats, 'captain', public.captain_wage(v_p, v_off.id),
      'dismiss_new', pg_temp.rb_0154(format('select cmd.do_dismiss(%L, %L)', v_pf, '{"count": 1}')),
      'dismiss_old', pg_temp.rb_0154(format('select pg_temp.cmd_do_dismiss_b0154(%L, %L)', v_pf, '{"count": 1}'))));

    -- LIT (inside this rolled-back block)
    update public.world_config set value = 'true'::jsonb where key = 'skills_bite';
    perform pg_temp.as_0154(c_uid);
    v_out := v_out || jsonb_build_object('lit', jsonb_build_object(
      'route_max', public.standing_route_max_for(v_p),
      'routes_screen', (pg_temp.rb_0154('select world.standing_routes()'))->'max',
      'routes_ok', pg_temp.try_0154(format('select pg_temp.routes_0154(%L, %s)', v_p, v_base + 2)),
      'routes_over', pg_temp.try_0154(format('select pg_temp.routes_0154(%L, %s)', v_p, v_base + 3)),
      'wage', public.fleet_wage(v_pf, false), 'wage_short', public.fleet_wage(v_pf, true),
      'quote', world.crew_cost(v_pf),
      'hire_quote', public.crew_hire_cost(v_pf, 10),
      'hire_new', pg_temp.rb_0154(format('select cmd.do_hire(%L, %L)', v_pf, '{"count": 10}')),
      'sign_new', pg_temp.rb_0154(format('select public.sign_officer(%L, %L, %L)', v_p, v_off.code, v_pf)),
      'captain', public.captain_wage(v_p, v_off.id),
      'officers_wage', (select (x->>'wage')::bigint from jsonb_array_elements(world.officers()->'officers') x where x->>'code' = v_off.code),
      'inn', (select jsonb_build_object('n', count(*), 'bad', count(*) filter (where (x->>'wage')::bigint is distinct from public.captain_wage(v_p, o.id)),
                                        'off', count(*) filter (where (x->>'wage')::bigint = o.wage_ducats))
                from jsonb_array_elements(world.inn(v_lis)->'present') x join public.officers o on o.code = x->>'code'),
      'bonuses', (select coalesce(jsonb_agg(jsonb_build_object('source', b.source, 'effect', b.effect) order by b.skill_code), '[]'::jsonb)
                    from world.skill_bonuses(v_p, null) b),
      'pcts', jsonb_build_object(
        'storm', world.skill_pct_at(v_p, null, 'storm_damage', now() - interval '60 days'),
        'calm', world.skill_pct_at(v_p, null, 'calm_delay', now() - interval '60 days'),
        'wage', world.skill_pct(v_p, null, 'crew_wage'), 'hire', world.skill_pct(v_p, null, 'crew_hire'),
        'captain', world.skill_pct(v_p, null, 'captain_wage'), 'routes', world.skill_pct(v_p, null, 'standing_routes'))));
    perform pg_temp.as_0154(null);
    update public.world_config set value = 'false'::jsonb where key = 'skills_bite';

    -- THE PASSAGE: Lisbon → Funchal and back, eleven crossings, departed 60 days ago, until her days hold a storm
    -- and a calm (the weather is a pure function of the voyage, so a new departure is a new sky)
    select jsonb_agg(case when g % 2 = 0 then jsonb_build_array(a.roadstead_lat, a.roadstead_lon)
                          else jsonb_build_array(b.roadstead_lat, b.roadstead_lon) end order by g)
      into v_leg from public.sea_reaches a, public.sea_reaches b, generate_series(0, 11) g
     where a.port_id = v_lis and b.port_id = v_fnc;
    loop
      v_try := v_try + 1;
      begin
        v_voy := voyage.depart(v_pf, voyage.segments_from_course(v_leg), v_lis, v_fnc, now() - interval '60 days');
        v_cap := voyage.total_days(v_voy);
        select count(*) filter (where h.kind = 'STORM'), count(*) filter (where h.kind = 'CALM') into v_storm, v_calm
          from generate_series(1, v_cap) d cross join lateral voyage.hazard_roll(v_voy, d) h where h.occurred;
        if v_storm = 0 or v_calm = 0 then
          raise exception 'RETRY_0154';
        end if;
        exit;
      exception when others then
        if sqlerrm <> 'RETRY_0154' then raise; end if;
      end;
      if v_try >= 2000 then
        raise exception '0154 self-assert FAIL: 2,000 probe passages of % days held no storm and calm together — the weather moved, not this file', v_cap;
      end if;
    end loop;
    v_out := v_out || jsonb_build_object('passage', jsonb_build_object('tries', v_try, 'days', v_cap, 'storms', v_storm, 'calms', v_calm));
    -- DARK: the old settlement and the new, from the same start, are the same passage; so is the predicted arrival
    v_out := v_out || jsonb_build_object('dark_voyage', jsonb_build_object(
      'arrival_new', voyage.arrival_at(v_voy, now()), 'arrival_old', pg_temp.voyage_arrival_at_b0154(v_voy, now()),
      'new', pg_temp.rb_0154(format('select pg_temp.voyage_settle_b0154_digest_new(%L, %L)', v_voy, v_pf)),
      'old', pg_temp.rb_0154(format('select pg_temp.voyage_settle_b0154_digest_old(%L, %L)', v_voy, v_pf))));

    -- LIT, AT SEA: the same passage settled lit, once and in two sittings; the arrival it predicts
    update public.world_config set value = 'true'::jsonb where key = 'skills_bite';
    v_out := v_out || jsonb_build_object('lit_voyage', jsonb_build_object(
      'arrival', voyage.arrival_at(v_voy, now()),
      'one', pg_temp.rb_0154(format('select pg_temp.voyage_settle_b0154_digest_new(%L, %L)', v_voy, v_pf)),
      'two', pg_temp.rb_0154(format('select pg_temp.voyage_settle_b0154_digest_twice(%L, %L)', v_voy, v_pf))));
    -- every storm and calm of the lit passage, against the rule worked by hand
    select jsonb_build_object(
      'storms', count(*) filter (where e->>'kind' = 'STORM'),
      'storm_bad', count(*) filter (where e->>'kind' = 'STORM' and (e->'payload'->>'hull_lost')::numeric is distinct from
                    (select sum(round(c.durability * (0.08 + 0.17 * h.magnitude) * (1 - 12 / 100.0), 2))
                       from public.ships s join public.ship_classes c on c.id = s.class_id, voyage.hazard_roll(v_voy, (e->>'day')::int) h
                      where s.fleet_id = v_pf)),
      'calms', count(*) filter (where e->>'kind' = 'CALM'),
      'calm_bad', count(*) filter (where e->>'kind' = 'CALM' and (e->'payload'->>'delay_hours')::numeric is distinct from
                    (select round(round((1 + 3 * h.magnitude) * 24, 2) * (1 - 10 / 100.0), 2) from voyage.hazard_roll(v_voy, (e->>'day')::int) h)),
      'wage_days', count(*) filter (where e->'payload' ? 'wages'),
      -- (the crew is the probe's ten until a raid takes some: a day's wage is charged before its hazard)
      'wage_bad', count(*) filter (where e->'payload' ? 'wages'
                    and not exists (select 1 from jsonb_array_elements(v_out->'lit_voyage'->'one'->'events') e2
                                     where e2->>'kind' = 'PIRATES' and (e2->>'day')::int < (e->>'day')::int)
                    and (e->'payload'->>'wages')::bigint is distinct from
                    round(public.crew_wages(10, (e->'payload'->>'short_rations')::boolean) * (1 - 15 / 100.0))::bigint))
      into v_r
      from jsonb_array_elements(v_out->'lit_voyage'->'one'->'events') e;
    v_out := v_out || jsonb_build_object('lit_check', v_r);
    select jsonb_build_object(
      'storms', count(*) filter (where e->>'kind' = 'STORM'),
      'storm_bad', count(*) filter (where e->>'kind' = 'STORM' and (e->'payload'->>'hull_lost')::numeric is distinct from
                    (select sum(round(c.durability * (0.08 + 0.17 * h.magnitude), 2))
                       from public.ships s join public.ship_classes c on c.id = s.class_id, voyage.hazard_roll(v_voy, (e->>'day')::int) h
                      where s.fleet_id = v_pf)),
      'calm_bad', count(*) filter (where e->>'kind' = 'CALM' and (e->'payload'->>'delay_hours')::numeric is distinct from
                    (select round((1 + 3 * h.magnitude) * 24, 2) from voyage.hazard_roll(v_voy, (e->>'day')::int) h)))
      into v_r
      from jsonb_array_elements(v_out->'dark_voyage'->'new'->'events') e;
    v_out := v_out || jsonb_build_object('dark_check', v_r);
    perform pg_temp.as_0154(null);
    raise exception 'PROBE_ROLLBACK_0154';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_0154' then raise; end if;
  end;
  perform pg_temp.as_0154(null);
  return v_out;
end $$;

-- a house writes n routes at once (the cap trigger fires on each); the count written
create or replace function pg_temp.routes_0154(p_player uuid, p_n int)
returns jsonb language plpgsql as $$
declare
  v_n int;
begin
  insert into public.standing_routes (player_id, name) select p_player, 'Rota 0154 ' || g from generate_series(1, p_n) g;
  get diagnostics v_n = row_count;
  return jsonb_build_object('ins', v_n);
end $$;

-- the settlement digests the probe compares (a settle, then what it left)
create or replace function pg_temp.voyage_settle_b0154_digest_new(p_voyage uuid, p_fleet uuid)
returns jsonb language plpgsql as $$
begin
  perform voyage.settle(p_fleet, now());
  return pg_temp.voyage_digest_0154(p_voyage, p_fleet);
end $$;
create or replace function pg_temp.voyage_settle_b0154_digest_old(p_voyage uuid, p_fleet uuid)
returns jsonb language plpgsql as $$
begin
  perform pg_temp.voyage_settle_b0154(p_fleet, now());
  return pg_temp.voyage_digest_0154(p_voyage, p_fleet);
end $$;
-- the same passage settled in two sittings: part of it at an earlier clock, the rest now
create or replace function pg_temp.voyage_settle_b0154_digest_twice(p_voyage uuid, p_fleet uuid)
returns jsonb language plpgsql as $$
begin
  perform voyage.settle(p_fleet, (select v.departed_at + (v.eta - v.departed_at) / 2 from public.voyages v where v.id = p_voyage));
  perform voyage.settle(p_fleet, now());
  return pg_temp.voyage_digest_0154(p_voyage, p_fleet);
end $$;

create temp table probe_0154 (j jsonb) on commit drop;
do $$
declare
  v_try   int := 0;
  v_state text;
  v_msg   text;
begin
  loop
    v_try := v_try + 1;
    begin
      insert into probe_0154 select pg_temp.probe_0154();
      exit;
    exception when lock_not_available or deadlock_detected then
      get stacked diagnostics v_msg = message_text, v_state = returned_sqlstate;
    end;
    if v_try >= 5 then
      raise exception '0154 self-assert FAIL: LOCK CONTENTION, not a result — the probe could not get its locks in 5 tries (%: %). Re-run the push.',
        v_state, v_msg;
    end if;
    perform pg_sleep(0.2);
  end loop;
end $$;

-- ── 7. NOBODY HOLDS WHAT §8 GIVES AN EFFECT (so §5's lit answers stand after it) ────────────────
create temp table shipwright_0154 on commit drop as
select (select count(*) from public.player_skills ps join public.skills s on s.id = ps.skill_id where s.code = 'SHIPWRIGHT') as held,
       (select count(*) from public.skill_queue q join public.skills s on s.id = q.skill_id where s.code = 'SHIPWRIGHT') as queued,
       -- and no merchant holds a HOUSE-scope skill (npc_leg_lines / npc_found estimate without one)
       (select count(*) from public.player_skills ps join public.players p on p.id = ps.player_id and p.is_npc
          join public.skills s on s.id = ps.skill_id
         where exists (select 1 from public.skill_effects e where e.skill_code = s.code and e.scope = 'house')) as npc_house;

-- ── 8. SHIPWRIGHT'S YARD LABOUR — the house CHECK re-made; from here to commit skill_effects is held ──
do $alter$
declare
  v_house text;
  v_try   int := 0;
  v_state text;
  v_msg   text;
begin
  select k.conname into v_house from pg_constraint k
   where k.conrelid = 'public.skill_effects'::regclass and k.contype = 'c'
     and pg_get_constraintdef(k.oid) like '%''house''%' and pg_get_constraintdef(k.oid) like '%standing_routes%';
  if v_house is null then
    raise exception '0154 self-assert FAIL: the house-stat check is not where 0151 put it';
  end if;
  loop
    v_try := v_try + 1;
    begin
      execute format(
        'alter table public.skill_effects drop constraint %I, '
        'add constraint skill_effects_house_stat check (scope <> ''house'' or stat in (''officer_bonus'', '
        '''standing_routes'', ''crew_wage'', ''profit_tax'', ''storm_damage'', ''calm_delay'', ''captain_wage'', '
        '''crew_hire'', ''influence'', ''captain_xp'', ''homesick'', ''yard_labour'')) not valid', v_house);
      alter table public.skill_effects validate constraint skill_effects_house_stat;
      exit;
    exception when lock_not_available or deadlock_detected then
      get stacked diagnostics v_msg = message_text, v_state = returned_sqlstate;
      if v_try >= 5 then
        raise exception '0154 self-assert FAIL: LOCK CONTENTION, not a result — public.skill_effects could not be altered in 5 tries (%: %). Re-run the push.',
          v_state, v_msg;
      end if;
      perform pg_sleep(0.5);
    end;
  end loop;
end $alter$;

insert into public.skill_effects (skill_code, scope, stat, pct_per_level, role, tech)
select 'SHIPWRIGHT', 'house', 'yard_labour', 3, null, null
 where not exists (select 1 from public.skill_effects e where e.skill_code = 'SHIPWRIGHT' and e.stat = 'yard_labour');
analyze public.skill_effects;

-- the yard, with a house holding Shipwright II (rolled back)
create or replace function pg_temp.probe_yard_0154()
returns jsonb
language plpgsql
as $$
declare
  c_uid  constant uuid := '00000000-0154-4000-8000-000000000002';
  v_q    uuid;
  v_qf   uuid;
  v_lis  uuid := (select id from public.ports where code = 'LIS');
  v_out  jsonb;
  v_base bigint := public.hull_labour('barca');
begin
  begin
    v_q := public.new_house(c_uid, 'Casa do Estaleiro 0154', 'PRT', 'LIS');
    select id into v_qf from public.fleets where player_id = v_q;
    perform public.credit(v_q, 'PROBE_0154', 10000000);
    insert into public.player_skills (player_id, skill_id, level) select v_q, s.id, 2 from public.skills s where s.code = 'SHIPWRIGHT';
    -- the barca's timber and fittings, in Lisbon's shed
    insert into public.player_storage (player_id, port_id, good_id, qty)
    select v_q, v_lis, hg.good_id, hg.qty from public.hull_recipe_goods hg where hg.class_code = 'barca';
    insert into public.player_items (player_id, port_id, item_code, qty)
    select v_q, v_lis, hi.item_code, hi.qty from public.hull_recipe_items hi where hi.class_code = 'barca';
    perform pg_temp.as_0154(c_uid);
    v_out := jsonb_build_object(
      'base', v_base,
      'dark', public.yard_labour(v_q, 'barca'),
      'dark_build', (pg_temp.rb_0154(format('select cmd.do_build(%L, %L)', v_qf, '{"class": "barca", "name": "Prova do Estaleiro"}')))->'ducats',
      'dark_old_build', (pg_temp.rb_0154(format('select pg_temp.cmd_do_build_b0154(%L, %L)', v_qf, '{"class": "barca", "name": "Prova do Estaleiro"}')))->'ducats');
    update public.world_config set value = 'true'::jsonb where key = 'skills_bite';
    v_out := v_out || jsonb_build_object(
      'lit', public.yard_labour(v_q, 'barca'),
      'lit_screen', (select (x->>'ducats')::bigint from jsonb_array_elements(world.building_yard(v_lis)->'hulls') x where x->>'class' = 'barca'),
      'lit_build', (pg_temp.rb_0154(format('select cmd.do_build(%L, %L)', v_qf, '{"class": "barca", "name": "Prova do Estaleiro"}')))->'ducats',
      'words', (select b.effect from world.skill_bonuses(v_q, null) b where b.stat = 'yard_labour'));
    perform pg_temp.as_0154(null);
    raise exception 'PROBE_ROLLBACK_0154';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_0154' then raise; end if;
  end;
  perform pg_temp.as_0154(null);
  return v_out;
end $$;
create temp table probe_yard_0154 (j jsonb) on commit drop;
insert into probe_yard_0154 select pg_temp.probe_yard_0154();

-- ── 9. SELF-ASSERT ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  b       record;
  d       record;
  h       record;
  p       record;
  v_k     text;
  v_def   text;
  v_pr    jsonb := (select j from probe_0154);
  v_py    jsonb := (select j from probe_yard_0154);
  v_dark  jsonb := (select v from proven_0154 where k = 'dark');
  v_lit   jsonb := (select v from proven_0154 where k = 'lit');
  v_base  int := public.wc_int('standing_route_max');
  v_tim   text;
  v_sw    record;
begin
  select * into b from before_0154;
  select * into v_sw from shipwright_0154;
  if public.skills_bite_on() then
    raise exception '0154 self-assert FAIL: skills_bite is on — this file ships it dark';
  end if;

  -- (a) OLD vs NEW, every company, dark and lit
  foreach v_k in array array['wage', 'wage_quote', 'hire', 'captain', 'yard', 'routes', 'reading', 'arrival', 'storm', 'delay', 'words', 'screens'] loop
    if (v_dark->v_k->>'bad')::int is distinct from 0 or (v_lit->v_k->>'bad')::int is distinct from 0 then
      raise exception '0154 self-assert FAIL: % moved for a company (dark %, lit %)', v_k, v_dark->v_k, v_lit->v_k;
    end if;
  end loop;
  if (v_dark->'wage'->>'n')::int <> 2 * (select count(*) from public.fleets)
     or (v_dark->'captain'->>'n')::int <> (select count(*) from public.players) * (select count(*) from public.officers)
     or (v_dark->'yard'->>'n')::int <> (select count(*) from public.players) * (select count(*) from public.hull_recipes)
     or (v_dark->'routes'->>'n')::int <> (select count(*) from public.players)
     or (v_dark->'reading'->>'n')::int <> (select count(*) from public.players) + (select count(*) from public.ships)
     or (v_dark->'hire'->>'n')::int < 3 or (v_dark->'words'->>'n')::int < 100 or (v_dark->'screens'->>'n')::int < 3 then
    raise exception '0154 self-assert FAIL: a comparison was vacuous or short of its subjects: %', v_dark;
  end if;
  if v_sw.held <> 0 or v_sw.queued <> 0 or v_sw.npc_house <> 0 then
    raise exception '0154 self-assert FAIL: % house(s) hold and % queue Shipwright, or % merchant skill row(s) carry a house effect — the lit answers above would not stand',
      v_sw.held, v_sw.queued, v_sw.npc_house;
  end if;

  -- (b) THE PROBE, dark: today's figures; old door = new door, to the byte
  if coalesce((v_pr->'dark'->>'route_max')::int <> v_base
     or v_pr->'dark'->'routes'->>'error' not like 'E_ROUTE_CAP%' or (v_pr->'dark'->'routes_ok'->>'ins')::int <> v_base
     or (v_pr->'dark'->>'wage')::bigint <> (v_pr->'dark'->>'crew_wages')::bigint
     or (v_pr->'dark'->>'wage_short')::bigint <> (v_pr->'dark'->>'crew_wages_short')::bigint
     or v_pr->'dark'->'hire_quote' <> v_pr->'dark'->'hire_old_quote'
     or v_pr->'dark'->'hire_new' <> v_pr->'dark'->'hire_old' or (v_pr->'dark'->'hire_new'->>'cost')::bigint <> (v_pr->'dark'->'hire_quote'->>'cost')::bigint
     or v_pr->'dark'->'sign_new' <> v_pr->'dark'->'sign_old' or (v_pr->'dark'->'sign_new'->>'paid')::bigint <> (v_pr->'dark'->>'wage_of')::bigint
     or (v_pr->'dark'->>'captain')::bigint <> (v_pr->'dark'->>'wage_of')::bigint
     or v_pr->'dark'->'dismiss_new' <> v_pr->'dark'->'dismiss_old'
     or (v_pr->'passage'->>'storms')::int < 1 or (v_pr->'passage'->>'calms')::int < 1
     or v_pr->'dark_voyage'->'new' <> v_pr->'dark_voyage'->'old'
     or v_pr->'dark_voyage'->'arrival_new' <> v_pr->'dark_voyage'->'arrival_old'
     or v_pr->'dark_voyage'->'new'->'voyage'->>'status' <> 'ARRIVED'
     or (v_pr->'dark_voyage'->'new'->'voyage'->>'eta')::timestamptz <> (v_pr->'dark_voyage'->>'arrival_new')::timestamptz
     or (v_pr->'dark_check'->>'storms')::int < 1 or (v_pr->'dark_check'->>'storm_bad')::int <> 0
     or (v_pr->'dark_check'->>'calm_bad')::int <> 0, true) then
    raise exception '0154 self-assert FAIL: dark, the probe''s figures or doors moved: %', v_pr - 'lit' - 'lit_check' - 'lit_voyage';
  end if;
  -- (b) lit: each term exactly its per cent, door = screen, and a passage settles the same whenever it runs
  if coalesce((v_pr->'lit'->'pcts'->>'routes')::numeric <> 2 or (v_pr->'lit'->'pcts'->>'wage')::numeric <> 15
     or (v_pr->'lit'->'pcts'->>'hire')::numeric <> 8 or (v_pr->'lit'->'pcts'->>'captain')::numeric <> 15
     or (v_pr->'lit'->'pcts'->>'storm')::numeric <> 12 or (v_pr->'lit'->'pcts'->>'calm')::numeric <> 10
     or (v_pr->'lit'->>'route_max')::int <> v_base + 2 or (v_pr->'lit'->>'routes_screen')::int <> v_base + 2
     or (v_pr->'lit'->'routes_ok'->>'ins')::int <> v_base + 2 or v_pr->'lit'->'routes_over'->>'error' not like 'E_ROUTE_CAP%'
     or (v_pr->'lit'->>'wage')::bigint <> round((v_pr->'dark'->>'crew_wages')::bigint * 0.85)
     or (v_pr->'lit'->>'wage_short')::bigint <> round((v_pr->'dark'->>'crew_wages_short')::bigint * 0.85)
     or (v_pr->'lit'->'quote'->>'per_day')::bigint <> (v_pr->'lit'->>'wage')::bigint
     or (v_pr->'lit'->'quote'->>'per_day_short_rations')::bigint <> (v_pr->'lit'->>'wage_short')::bigint
     or (v_pr->'lit'->'hire_quote'->>'cost')::bigint
        <> round(((v_pr->'lit'->'hire_quote'->>'normal')::int * public.wc_num('hire_crew_rate')
                  + (v_pr->'lit'->'hire_quote'->>'urgent')::int * public.wc_num('hire_crew_rate') * public.wc_num('crew_urgent_multiplier')) * 0.92)
     or (v_pr->'lit'->'hire_new'->>'cost')::bigint <> (v_pr->'lit'->'hire_quote'->>'cost')::bigint
     or (v_pr->'lit'->'hire_new'->>'cost')::bigint >= (v_pr->'dark'->'hire_new'->>'cost')::bigint
     or (v_pr->'lit'->>'captain')::bigint <> round((v_pr->'dark'->>'wage_of')::bigint * 0.85)
     or (v_pr->'lit'->'sign_new'->>'paid')::bigint <> (v_pr->'lit'->>'captain')::bigint
     or (v_pr->'lit'->>'officers_wage')::bigint <> (v_pr->'lit'->>'captain')::bigint
     or (v_pr->'lit'->'inn'->>'bad')::int <> 0
     or v_pr->'lit_voyage'->'one' <> v_pr->'lit_voyage'->'two'
     or v_pr->'lit_voyage'->'one'->'voyage'->>'status' <> 'ARRIVED'
     or (v_pr->'lit_voyage'->'one'->'voyage'->>'eta')::timestamptz <> (v_pr->'lit_voyage'->>'arrival')::timestamptz
     or (v_pr->'lit_check'->>'storms')::int < 1 or (v_pr->'lit_check'->>'storm_bad')::int <> 0
     or (v_pr->'lit_check'->>'calms')::int < 1 or (v_pr->'lit_check'->>'calm_bad')::int <> 0
     or (v_pr->'lit_check'->>'wage_days')::int < 1 or (v_pr->'lit_check'->>'wage_bad')::int <> 0
     or v_pr->'lit'->'bonuses' <> jsonb_build_array(
          jsonb_build_object('source', 'Etiquette II', 'effect', '−8% crew hiring'),
          jsonb_build_object('source', 'Factorage II', 'effect', '+2 routes'),
          jsonb_build_object('source', 'Light-air Sailing II', 'effect', '−10% time lost in a calm'),
          jsonb_build_object('source', 'Pursership V', 'effect', '−15% crew wages'),
          jsonb_build_object('source', 'Recruiting III', 'effect', '−15% captain wages'),
          jsonb_build_object('source', 'Weather Lore III', 'effect', '−12% storm damage')), true) then
    raise exception '0154 self-assert FAIL: lit, a term did not take exactly its per cent, a door and its screen disagree, or two settles disagree: %',
      jsonb_build_object('lit', v_pr->'lit', 'lit_check', v_pr->'lit_check', 'arrival', v_pr->'lit_voyage'->'arrival', 'eta', v_pr->'lit_voyage'->'one'->'voyage', 'one_two_equal', v_pr->'lit_voyage'->'one' = v_pr->'lit_voyage'->'two');
  end if;
  -- the yard
  if coalesce((v_py->>'dark')::bigint <> (v_py->>'base')::bigint or (v_py->>'dark_build')::bigint <> (v_py->>'base')::bigint
     or (v_py->>'dark_old_build')::bigint <> (v_py->>'base')::bigint
     or (v_py->>'lit')::bigint <> round((v_py->>'base')::bigint * 0.94) or (v_py->>'lit')::bigint >= (v_py->>'base')::bigint
     or (v_py->>'lit_screen')::bigint <> (v_py->>'lit')::bigint or (v_py->>'lit_build')::bigint <> (v_py->>'lit')::bigint
     or v_py->>'words' is distinct from '−6% yard labour', true) then
    raise exception '0154 self-assert FAIL: the yard''s labour, its screen or its door moved beyond Shipwright: %', v_py;
  end if;
  if exists (select 1 from public.players where auth_uid::text like '00000000-0154-4000-8000-00000000000%') or public.skills_bite_on()
     or current_setting('request.jwt.claim.sub', true) not in ('') then
    raise exception '0154 self-assert FAIL: the probe world was not rolled back, or an identity was left assumed';
  end if;

  -- (c) THE RE-CUTS reverse to their pre-images; ACL / volatility / definer / config unmoved
  for d in select * from defs_before_0154 order by fn loop
    v_def := replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0154 where fn = d.fn order by n desc loop
      if pg_temp.occurs_0154(v_def, h.new) <> 1 then
        raise exception '0154 self-assert FAIL: hunk % of % is not in the new body exactly once', h.n, d.fn;
      end if;
      v_def := replace(v_def, h.new, h.old);
    end loop;
    if v_def <> d.def then
      raise exception '0154 self-assert FAIL: % does not reverse to its pre-image', d.fn;
    end if;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef, coalesce(pr.proconfig::text, '') as cfg
      into p from pg_proc pr where pr.oid = d.fn::regprocedure;
    if p.acl <> d.acl or p.vol <> d.vol or p.secdef <> d.secdef or p.cfg <> d.cfg then
      raise exception '0154 self-assert FAIL: % changed its ACL, volatility, definer or config', d.fn;
    end if;
  end loop;
  for d in select * from untouched_before_0154 loop
    if replace(pg_get_functiondef(d.fn::regprocedure), E'\r', '') <> d.def
       or coalesce((select pr.proacl::text from pg_proc pr where pr.oid = d.fn::regprocedure), '') <> d.acl then
      raise exception '0154 self-assert FAIL: % moved — it was to be left untouched', d.fn;
    end if;
  end loop;
  -- no door or screen reads the lifted figures inline any more: each knob / column has its one reader
  if exists (select 1 from pg_proc pr join pg_namespace n on n.oid = pr.pronamespace
              where n.nspname in ('public', 'world', 'cmd', 'voyage')
                and pr.oid not in ('public.crew_hire_cost(uuid, integer)'::regprocedure, 'public.standing_route_max_for(uuid)'::regprocedure)
                and pr.prosrc ~ 'wc_(num|int)\(''(hire_crew_rate|crew_urgent_multiplier|standing_route_max)''\)') then
    raise exception '0154 self-assert FAIL: a body still reads the hire rate or the route cap inline: %',
      (select string_agg(pr.oid::regprocedure::text, ', ') from pg_proc pr join pg_namespace n on n.oid = pr.pronamespace
        where n.nspname in ('public', 'world', 'cmd', 'voyage')
          and pr.oid not in ('public.crew_hire_cost(uuid, integer)'::regprocedure, 'public.standing_route_max_for(uuid)'::regprocedure)
          and pr.prosrc ~ 'wc_(num|int)\(''(hire_crew_rate|crew_urgent_multiplier|standing_route_max)''\)');
  end if;
  if (select count(*) from pg_proc pr
       where pr.oid in ('public.crew_hire_cost(uuid, integer)'::regprocedure, 'public.standing_route_max_for(uuid)'::regprocedure)
         and pr.prosrc ~ 'wc_(num|int)\(''(hire_crew_rate|crew_urgent_multiplier|standing_route_max)''\)') <> 2 then
    raise exception '0154 self-assert FAIL: the inline-read scan does not find the two readers themselves — it is vacuous';
  end if;
  -- the new functions carry their siblings' ACL (server-only; Supabase's default grants included)
  for d in select * from acl_0154 loop
    if coalesce((select pr.proacl::text from pg_proc pr where pr.oid = d.fn::regprocedure), '')
       is distinct from coalesce((select pr.proacl::text from pg_proc pr where pr.oid = d.sibling::regprocedure), '') then
      raise exception '0154 self-assert FAIL: % does not carry %''s ACL (% vs %)', d.fn, d.sibling,
        (select pr.proacl::text from pg_proc pr where pr.oid = d.fn::regprocedure),
        (select pr.proacl::text from pg_proc pr where pr.oid = d.sibling::regprocedure);
    end if;
  end loop;
  if (select count(*) from public.client_rpc_entry_points()) <> b.entry_points
     or exists (select 1 from acl_0154 a, unnest(array['anon', 'authenticated']) r(role)
                 where has_function_privilege(r.role, a.fn::regprocedure, 'execute')) then
    raise exception '0154 self-assert FAIL: the client entry points moved, or a client role can run a new function';
  end if;
  -- the catalogue: exactly Shipwright's row added, nothing else moved
  if (select count(*) from public.skill_effects) <> b.effects + 1
     or (select md5(string_agg(to_jsonb(e)::text, '|' order by e.id)) from public.skill_effects e where e.id <= b.effects_max_id) is distinct from b.effects_hash
     or (select count(*) from public.skills) <> b.skills then
    raise exception '0154 self-assert FAIL: the skill catalogue moved beyond Shipwright''s yard-labour row';
  end if;

  select string_agg(format('%s %s ms', what, ms), '; ' order by what) into v_tim from timing_0154;

  raise notice '0154 self-assert ok: A SKILL IS PAID WHERE THE GAME CHARGES (dark: skills_bite false). LIFTED, one reading each, OLD vs NEW for every company, dark and lit, 0 differ: % fleet wages (both rations), % crew quotes, % hire quotes, % house × captain wages, % house × hull labours, % route caps, % house / hull skill readings, % predicted arrivals, % storm losses, % day delays at sea, % effect words, % screen reads (officers, inn, yard, crew cost, routes; as nobody and as every human house). PROBE (rolled back) — dark: old door = new door for HIRE (% d.), signing (% d.), DISMISS and a % day passage of % storm(s) and % calm(s) (found in % departure(s)), predicted arrival = settled; lit: Factorage II % → % routes (the % th refused E_ROUTE_CAP), Pursership V wage % → % d. (quote = charge), Etiquette II hire % → % d., Recruiting III % → % d. (paid = Inn = Captains), Shipwright II yard % → % d. (charged = printed), Weather Lore III every storm × 0.88, Light-air II every calm × 0.90, predicted arrival = settled, two sittings = one. BODIES: 15 reverse to their pre-images, 15 untouched; 10 new functions server-only; no new entry point; Shipwright yard_labour +1 effect row. TIMING (fastest of 2, random_page_cost %; reported, not gated): %.',
    v_dark->'wage'->>'n', v_dark->'wage_quote'->>'n', v_dark->'hire'->>'n', v_dark->'captain'->>'n', v_dark->'yard'->>'n',
    v_dark->'routes'->>'n', v_dark->'reading'->>'n', v_dark->'arrival'->>'n', v_dark->'storm'->>'n', v_dark->'delay'->>'n',
    v_dark->'words'->>'n', v_dark->'screens'->>'n',
    v_pr->'dark'->'hire_new'->>'cost', v_pr->'dark'->'sign_new'->>'paid',
    v_pr->'passage'->>'days', v_pr->'passage'->>'storms', v_pr->'passage'->>'calms', v_pr->'passage'->>'tries',
    v_base, v_pr->'lit'->>'route_max', v_base + 3,
    v_pr->'dark'->>'wage', v_pr->'lit'->>'wage', v_pr->'dark'->'hire_new'->>'cost', v_pr->'lit'->'hire_new'->>'cost',
    v_pr->'dark'->>'wage_of', v_pr->'lit'->>'captain', v_py->>'base', v_py->>'lit',
    current_setting('random_page_cost'), v_tim;
end $$;
