-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0178 — A COMPANY USES WHAT IT HAS LEARNED  (skills_bite false → true: the company's Skills bite)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE ASK ─────────────────────────────────────────────────────────────────────────────────────
-- The owner, 2026-10-17: *"do a thorough research … of 대항해시대 오리진 (Uncharted Waters Origin), their
-- skills and EVE-style skill sets, and make them properly … apply it to the game as well."* Every skill
-- slice (0131 S9, 0133 S11, 0149 K0, 0151 K1, 0154 K2, 0155 K3) shipped DARK behind ONE switch,
-- world_config `skills_bite`. docs/SKILLS_AND_CAPTAINS.md §8 "Lighting order": K0 → skills_bite (after
-- §7.6's check) → … → crew_bite. This file is that one step, and nothing else.
--
-- ── WHAT THE SWITCH TURNS ON (every reader is LIVE already; none is touched here) ────────────────
--   * ship / fitting per-level bonuses on a company's own hulls (world.skill_bonuses → world.ship_stats,
--     world.ship_budget, world.ship_view): line and size hull skills, role skills, Cargo Stowage, Deck
--     Management, Gun Drill, Crew Drill (0133, 0149, 0151);
--   * the requirements of public.skill_requirements on BUILD and FIT start to COUNT the levels held
--     (public.requirements_unmet). Dark, no level counts, so a gated hull or item cannot be built or
--     fitted by anyone; lit, whoever holds the levels may. It only ever LOOSENS: lit refuses nothing
--     dark allowed (asserted below for every player house and every subject);
--   * the house effects (0154 K2): Factorage (routes), Pursership (wage), Etiquette (hiring), Recruiting
--     (captain's wage), Shipwright (yard labour), Weather Lore and Light-air Sailing (storm and calm, read
--     at the voyage's departure), Command (hull cap, captains' bonus), Leadership (captains' experience);
--   * the company effects of the K1 skills (Wholesale, Negotiation, Provisioning, Celestial Navigation) —
--     the four LIVE company skills (ACCOUNTING, HAGGLING, NAVIGATION, SEAMANSHIP) were never gated and
--     answer exactly as before.
--   NOT this file: crew_bite (captains' traits, cabins, homesickness, languages), levels_bite, combat_bite,
--   armour_turns_pct, gear_wear_bite, skill_sp_per_arrival (K3's bonus training stays 0 = off).
--
-- ── WHO IT REACHES ON PRODUCTION (read-only, 2026-10-18 03:15 UTC, head 0177) ────────────────────
--   * PLAYERS (17 houses, 20 hulls): one skill level between them (NAVIGATION I, a live company skill),
--     no queue entry, no banked SP. So every player answer is what it was — speed, hold, stores, wages,
--     routes, hull cap, hiring. What changes for them is what a skill they LEARN from now on does: it
--     now bites. The refusal sentence loses its "— ship skills are not in use yet" tail.
--   * MERCHANTS (821 houses, 837 fleets, 892 hulls): the four live company skills (unchanged), plus the
--     hull-line skills S18 (0167) fixed once for the 57 English and French houses whose hulls changed
--     class (ENG_SMALL/LIGHT/MEDIUM, FRA_SMALL/LIGHT/MEDIUM, levels I–III). Of those, only the English
--     lines carry a SPEED row (+2 % a level, on their own size): 10 hulls in 9 fleets read +2 % speed;
--     the rest are handling / reach / accuracy, which no roll reads until combat_bite (S4). No merchant
--     holds a hold, house or fitting skill, so cargo space, stores, wages, spread, hull cap, routes and
--     hiring are unmoved — asserted below for every live merchant fleet.
--
-- ── THE BOUNDS (from the plans, asserted for EVERY live merchant fleet, dark → lit) ──────────────
--   SHIPS_AND_SKILLS §8 S18: "merchant fleet hold within ±10 % and speed within ±5 % of pre-image per
--   fleet", crew and wages exact; SKILLS_AND_CAPTAINS §0.11 / §6.2: what merchants get from their
--   captains does not move. So, per merchant fleet: speed in [dark, dark × 1.05]; cargo space, stores,
--   daily wage, a 10-hand hiring quote, the captains' four live per cents, hull cap, route cap and every
--   ship budget EXACTLY the pre-image; 300 sampled quay spreads exactly the pre-image. Per player house:
--   no answer gets worse (speed, cargo space, stores, caps ≥; wage, hiring ≤), and no (house, hull or
--   item) pair gains an unmet requirement. Every hull of every house: no stat falls.
--
-- ── THE COST (SKILLS_AND_CAPTAINS §7.6) ─────────────────────────────────────────────────────────
--   §7.6: throw the switch only if the arrivals p95 is under 5 s and the max under 8 s. Prod, the 30 min
--   to 03:14 UTC: 116 runs, avg 2.71 s, p95 3.87 s, max 9.00 s (one run); since 01:00 UTC: p95 ≤ 4.2 s.
--   The 24 h window still holds the 17:00–23:00 UTC stretch of 0172–0174's pushes (p95 up to 10.2 s).
--   The read cost is printed below (merchant speed + cargo space and ship_view, dark vs lit; a notice,
--   never a raise — prod's CPU is burstable). Measured on the cached world image, PGlite, before this
--   file: speed + cargo space 575 → 797 ms over 837 fleets, ship_view 1,385 → 1,908 ms over 892 hulls;
--   the extra is the 57 S18 houses' hulls (the lit branch runs for a house that holds a SHIP skill);
--   every other merchant leaves at 0149's probe. docs/dev-log/2026-10-18-lighting-skills.md has the
--   sweep measurement.
--
-- ── ROLLBACK ────────────────────────────────────────────────────────────────────────────────────
-- A forward migration with `update public.world_config set value = 'false'::jsonb where key =
-- 'skills_bite';`. Stated consequence (0133's note): a house that built or fitted a gated subject while
-- lit keeps it; a house grown past ship_max under Command is refused E_SHIP_MAX on its next transfer.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $$
begin
  perform set_config('statement_timeout', '10min', true);
  perform set_config('lock_timeout', '5s', true);
  perform set_config('random_page_cost', '1.1', true);   -- prod's planner page cost (0149's header)
  if public.skills_bite_on() then
    raise exception '0178 self-assert FAIL: skills_bite is already on — this file throws it, and its pre-image must be the dark world';
  end if;
  if not exists (select 1 from public.world_config where key = 'skills_bite') then
    raise exception '0178 self-assert FAIL: there is no skills_bite row to throw (0133 seeded it)';
  end if;
end $$;

-- ── 1. THE ANSWERS, one statement per reading (taken dark, then lit) ─────────────────────────────
create or replace function pg_temp.fleet_answers_0178()
returns table (fleet_id uuid, player_id uuid, is_npc boolean, speed numeric, endurance numeric, wage bigint,
               hold numeric, hire10 bigint, c_speed numeric, c_spread numeric, c_saved numeric, c_hold numeric,
               ship_max int, routes_max int, budgets jsonb)
language sql
as $$
  select f.id, f.player_id, p.is_npc,
         voyage.fleet_speed(f.id),
         voyage.endurance_days(f.id),
         public.fleet_wage(f.id, false),
         (select sum(public.ship_hold_capacity(s.id)) from public.ships s where s.fleet_id = f.id),
         (public.crew_hire_cost(f.id, 10)->>'cost')::bigint,
         public.crew_pct(f.id, null, 'speed'),
         public.crew_pct(f.id, null, 'spread'),
         public.crew_pct(f.id, null, 'crew_saved'),
         public.crew_pct(f.id, null, 'hold'),
         public.house_ship_max(f.player_id),
         public.standing_route_max_for(f.player_id),
         (select jsonb_agg(world.ship_budget(s.id) order by s.id) from public.ships s where s.fleet_id = f.id)
    from public.fleets f
    join public.players p on p.id = f.player_id
   where exists (select 1 from public.ships s where s.fleet_id = f.id)
$$;

create or replace function pg_temp.ship_answers_0178()
returns table (ship_id uuid, player_id uuid, is_npc boolean, stats jsonb)
language sql
as $$
  select s.id, s.player_id, p.is_npc, world.ship_stats(s.id)
    from public.ships s join public.players p on p.id = s.player_id
$$;

-- 300 quay spreads of merchant fleets lying in port (a fixed sample: md5 order, no random())
create temp table spread_keys_0178 on commit drop as
select f.port_id, g.id as good_id, f.id as fleet_id
  from public.fleets f
  join public.players p on p.id = f.player_id and p.is_npc
 cross join lateral (select id from public.goods order by md5(id::text || f.id::text) limit 3) g
 where f.port_id is not null
 order by md5(f.id::text || g.id::text)
 limit 300;

-- every requirement subject x every player house (players only: 17 houses; merchants fit G1 / build
-- through npc_found, and lit only counts levels they hold)
create temp table req_keys_0178 on commit drop as
select p.id as player_id, r.subject_kind, r.subject_code
  from public.players p
 cross join (select distinct subject_kind, subject_code from public.skill_requirements) r
 where not p.is_npc;

create or replace function pg_temp.timing_0178()
returns jsonb
language plpgsql
as $$
declare
  v_t0   timestamptz;
  v_best numeric;
  v_ms   numeric;
  v_out  jsonb := '{}'::jsonb;
  v_x    numeric;
  i      int;
begin
  v_best := null;
  for i in 1 .. 2 loop
    v_t0 := clock_timestamp();
    select sum(voyage.fleet_speed(f.id)) + sum((select sum(public.ship_hold_capacity(s.id)) from public.ships s where s.fleet_id = f.id))
      into v_x
      from public.fleets f join public.players p on p.id = f.player_id and p.is_npc
     where exists (select 1 from public.ships s where s.fleet_id = f.id);
    v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
    v_best := least(coalesce(v_best, v_ms), v_ms);
  end loop;
  v_out := v_out || jsonb_build_object('speed_hold_ms', v_best);
  v_best := null;
  for i in 1 .. 2 loop
    v_t0 := clock_timestamp();
    select count(world.ship_view(s.id)) into v_x from public.ships s join public.players p on p.id = s.player_id and p.is_npc;
    v_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
    v_best := least(coalesce(v_best, v_ms), v_ms);
  end loop;
  return v_out || jsonb_build_object('ship_view_ms', v_best);
end $$;

create temp table dark_fleets_0178 on commit drop as select * from pg_temp.fleet_answers_0178();
create temp table dark_ships_0178  on commit drop as select * from pg_temp.ship_answers_0178();
create temp table dark_spread_0178 on commit drop as
select k.*, world.spread_effective(k.port_id, k.good_id, k.fleet_id) as v from spread_keys_0178 k;
create temp table dark_req_0178 on commit drop as
select k.*, (select count(*) from public.requirements_unmet(k.player_id, k.subject_kind, k.subject_code))::int as unmet
  from req_keys_0178 k;
create temp table timing_0178 (k text primary key, v jsonb) on commit drop;
insert into timing_0178 values ('dark', pg_temp.timing_0178());

-- ── 2. THE SWITCH ───────────────────────────────────────────────────────────────────────────────
update public.world_config
   set value = 'true'::jsonb,
       description = '0133: true = skills DO something — the per-level bonuses of public.skill_effects on ship '
                     'stats, budgets and officers, the house effects (0154), the house hull cap from Command, and '
                     'the requirements of public.skill_requirements on BUILD and FIT. false = every one of them '
                     'off. Shipped false (dark); THROWN TRUE by 0178 (2026-10-18), the owner''s order to apply '
                     'the skills to the game. The company effects of the four live skills were never gated.'
 where key = 'skills_bite';

create temp table lit_fleets_0178 on commit drop as select * from pg_temp.fleet_answers_0178();
create temp table lit_ships_0178  on commit drop as select * from pg_temp.ship_answers_0178();
create temp table lit_spread_0178 on commit drop as
select k.*, world.spread_effective(k.port_id, k.good_id, k.fleet_id) as v from spread_keys_0178 k;
create temp table lit_req_0178 on commit drop as
select k.*, (select count(*) from public.requirements_unmet(k.player_id, k.subject_kind, k.subject_code))::int as unmet
  from req_keys_0178 k;
insert into timing_0178 values ('lit', pg_temp.timing_0178());

-- ── 3. THE PROBE: a throw-away house, its own state, the lit answers the plans state ─────────────
create temp table probe_0178 (j jsonb) on commit drop;
do $$
declare
  c_uid   constant uuid := '00000000-0178-4000-8000-000000000001';
  v_p     uuid;
  v_pf    uuid;
  v_ps    uuid;
  v_cls   text;
  v_hull  text;
  v_out   jsonb := '{}'::jsonb;
  v_pct   jsonb;
  v_n     uuid;
begin
  begin
    if not public.skills_bite_on() then
      raise exception '0178 self-assert FAIL: skills_bite did not read true after the UPDATE';
    end if;
    v_p := public.new_house(c_uid, 'Casa da Prova 0178', 'PRT', 'LIS');
    select id into v_pf from public.fleets where player_id = v_p;
    select s.id, c.code into v_ps, v_cls from public.ships s join public.ship_classes c on c.id = s.class_id where s.fleet_id = v_pf;
    update public.ships set crew = 10 where id = v_ps;
    -- a control house holding nothing but what new_house gives
    v_n := public.new_house('00000000-0178-4000-8000-000000000002', 'Casa Sem Escola 0178', 'PRT', 'LIS');
    -- the hull her line's skills gate: the cheapest-coded PRT size-4 class (needs PRT Medium/Heavy … levels)
    select cp.class_code into v_hull from public.class_profile cp
     where cp.line_code = 'PRT' and cp.size = 4
       and exists (select 1 from public.skill_requirements r where r.subject_kind = 'hull' and r.subject_code = cp.class_code)
     order by cp.class_code limit 1;

    -- DARK reading of the probe (the switch put back inside this rolled-back block)
    update public.world_config set value = 'false'::jsonb where key = 'skills_bite';
    insert into public.player_skills (player_id, skill_id, level)
    select v_p, s.id, x.lvl
      from (values ('PRT_SMALL', 3), ('PRT_LIGHT', 3), ('CARGO_STOWAGE', 2), ('MERCHANT_SHIPS', 2), ('COMMAND', 2),
                   ('FACTORAGE', 2), ('PURSERSHIP', 5)) x(code, lvl)
      join public.skills s on s.code = x.code;
    v_out := v_out || jsonb_build_object('class', v_cls, 'gated_hull', v_hull, 'dark', jsonb_build_object(
      'stats', world.ship_stats(v_ps), 'hold', public.ship_hold_capacity(v_ps), 'speed', voyage.fleet_speed(v_pf),
      'ship_max', public.house_ship_max(v_p), 'routes', public.standing_route_max_for(v_p),
      'wage', public.fleet_wage(v_pf, false), 'unmet', (select count(*) from public.requirements_unmet(v_p, 'hull', v_hull)),
      'refusal', public.requirements_refusal(v_p, 'hull', v_hull),
      'control', jsonb_build_object('stats', world.ship_stats((select s.id from public.ships s where s.player_id = v_n limit 1)),
                                    'ship_max', public.house_ship_max(v_n), 'routes', public.standing_route_max_for(v_n))));
    -- every level the gated hull asks, granted (so lit nothing is unmet; dark everything still is)
    insert into public.player_skills (player_id, skill_id, level)
    select v_p, s.id, r.level from public.skill_requirements r join public.skills s on s.code = r.skill_code
     where r.subject_kind = 'hull' and r.subject_code = v_hull
    on conflict (player_id, skill_id) do update set level = greatest(public.player_skills.level, excluded.level);
    v_out := v_out || jsonb_build_object('dark_unmet_granted', (select count(*) from public.requirements_unmet(v_p, 'hull', v_hull)));
    delete from public.player_skills ps using public.skills s
     where ps.player_id = v_p and s.id = ps.skill_id
       and s.code not in ('PRT_SMALL', 'PRT_LIGHT', 'CARGO_STOWAGE', 'MERCHANT_SHIPS', 'COMMAND', 'FACTORAGE', 'PURSERSHIP');
    update public.player_skills ps set level = x.lvl
      from public.skills s, (values ('PRT_SMALL', 3), ('PRT_LIGHT', 3), ('CARGO_STOWAGE', 2), ('MERCHANT_SHIPS', 2), ('COMMAND', 2),
                                    ('FACTORAGE', 2), ('PURSERSHIP', 5)) x(code, lvl)
     where ps.player_id = v_p and s.id = ps.skill_id and s.code = x.code;

    -- LIT (the switch as this file leaves it)
    update public.world_config set value = 'true'::jsonb where key = 'skills_bite';
    -- the per cents the plan's rows state, summed from public.skill_effects by the probe's OWN profile
    select jsonb_object_agg(z.stat, z.pct) into v_pct
      from (select e.stat, sum(e.pct_per_level * ps.level) as pct
              from public.player_skills ps
              join public.skills s on s.id = ps.skill_id
              join public.skill_effects e on e.skill_code = s.code and e.scope in ('ship', 'fitting', 'house')
              left join public.class_profile cp on cp.class_code = v_cls
             where ps.player_id = v_p
               and (e.scope = 'house' or ((e.line_code is null or e.line_code = cp.line_code) and (e.size is null or e.size = cp.size)
                                           and (e.role is null or e.role = cp.role) and (e.tech is null or e.tech = cp.tech)))
             group by e.stat) z;
    v_out := v_out || jsonb_build_object('pct', v_pct, 'lit', jsonb_build_object(
      'stats', world.ship_stats(v_ps), 'hold', public.ship_hold_capacity(v_ps), 'speed', voyage.fleet_speed(v_pf),
      'ship_max', public.house_ship_max(v_p), 'routes', public.standing_route_max_for(v_p),
      'wage', public.fleet_wage(v_pf, false), 'unmet', (select count(*) from public.requirements_unmet(v_p, 'hull', v_hull)),
      'refusal', public.requirements_refusal(v_p, 'hull', v_hull),
      'bonuses', (select count(*) from jsonb_array_elements(coalesce(world.ship_view(v_ps)->'bonuses', '[]'::jsonb))),
      'control', jsonb_build_object('stats', world.ship_stats((select s.id from public.ships s where s.player_id = v_n limit 1)),
                                    'ship_max', public.house_ship_max(v_n), 'routes', public.standing_route_max_for(v_n))));
    insert into public.player_skills (player_id, skill_id, level)
    select v_p, s.id, r.level from public.skill_requirements r join public.skills s on s.code = r.skill_code
     where r.subject_kind = 'hull' and r.subject_code = v_hull
    on conflict (player_id, skill_id) do update set level = greatest(public.player_skills.level, excluded.level);
    v_out := v_out || jsonb_build_object('lit_unmet_granted', (select count(*) from public.requirements_unmet(v_p, 'hull', v_hull)),
                                         'crew_wages', public.crew_wages(10, false), 'rcm', public.running_cost_mult(v_p),
                                         'ship_max_knob', public.wc_int('ship_max'), 'per_command', public.wc_int('command_hulls_per_level'),
                                         'route_knob', public.wc_int('standing_route_max'));
    raise exception 'PROBE_ROLLBACK_0178:%', v_out::text;
  exception when others then
    if sqlerrm not like 'PROBE_ROLLBACK_0178:%' then raise; end if;
    insert into probe_0178 values (substr(sqlerrm, length('PROBE_ROLLBACK_0178:') + 1)::jsonb);
  end;
end $$;

-- ── 4. THE SELF-ASSERT ──────────────────────────────────────────────────────────────────────────
do $$
declare
  j       jsonb := (select j from probe_0178);
  d       jsonb;
  l       jsonb;
  v_m     record;
  v_pl    record;
  v_sh    record;
  v_sp    record;
  v_rq    record;
  v_td    jsonb := (select v from timing_0178 where k = 'dark');
  v_tl    jsonb := (select v from timing_0178 where k = 'lit');
begin
  if not public.skills_bite_on() then
    raise exception '0178 self-assert FAIL: skills_bite is not on after the probe (the probe''s rollback must have restored true)';
  end if;
  if exists (select 1 from public.players where auth_uid in ('00000000-0178-4000-8000-000000000001', '00000000-0178-4000-8000-000000000002')) then
    raise exception '0178 self-assert FAIL: a probe house survived its rolled-back block';
  end if;

  -- (a) EVERY LIVE MERCHANT FLEET, dark → lit, inside the plans' bounds
  select count(*) as n,
         count(*) filter (where l.speed is distinct from d.speed) as speed_moved,
         count(*) filter (where l.speed < d.speed or l.speed > d.speed * 1.05) as speed_out,
         max(round(100 * (l.speed / nullif(d.speed, 0) - 1), 3)) as speed_max_pct,
         count(*) filter (where l.hold is distinct from d.hold or l.endurance is distinct from d.endurance
                            or l.wage is distinct from d.wage or l.hire10 is distinct from d.hire10
                            or l.c_speed is distinct from d.c_speed or l.c_spread is distinct from d.c_spread
                            or l.c_saved is distinct from d.c_saved or l.c_hold is distinct from d.c_hold
                            or l.ship_max is distinct from d.ship_max or l.routes_max is distinct from d.routes_max
                            or l.budgets::text is distinct from d.budgets::text) as other_moved
    into v_m
    from dark_fleets_0178 d join lit_fleets_0178 l using (fleet_id)
   where d.is_npc;
  if v_m.speed_out > 0 then
    raise exception '0178 self-assert FAIL: % merchant fleet(s) read a speed outside [dark, dark × 1.05] lit (S18''s ±5 %% bound; max +% %%)',
      v_m.speed_out, v_m.speed_max_pct;
  end if;
  if v_m.other_moved > 0 then
    raise exception '0178 self-assert FAIL: % merchant fleet(s) moved cargo space, stores, wage, hiring, captains'' per cents, a cap or a budget lit — the plans hold every one to its pre-image',
      v_m.other_moved;
  end if;
  select count(*) as n, count(*) filter (where d.v is distinct from l.v) as moved into v_sp
    from dark_spread_0178 d join lit_spread_0178 l using (port_id, good_id, fleet_id);
  if v_sp.moved > 0 then
    raise exception '0178 self-assert FAIL: % of % sampled merchant quay spreads moved lit', v_sp.moved, v_sp.n;
  end if;

  -- (b) EVERY PLAYER HOUSE: no answer gets worse; report what moved
  select count(*) as n,
         count(*) filter (where l.speed < d.speed or l.hold < d.hold or l.endurance < d.endurance
                            or l.wage > d.wage or l.hire10 > d.hire10 or l.ship_max < d.ship_max
                            or l.routes_max < d.routes_max) as worse,
         count(*) filter (where (l.speed, l.hold, l.endurance, l.wage, l.hire10, l.ship_max, l.routes_max)
                                is distinct from (d.speed, d.hold, d.endurance, d.wage, d.hire10, d.ship_max, d.routes_max)) as moved
    into v_pl
    from dark_fleets_0178 d join lit_fleets_0178 l using (fleet_id)
   where not d.is_npc;
  if v_pl.worse > 0 then
    raise exception '0178 self-assert FAIL: % player fleet(s) read a worse answer lit — a learned skill may only help', v_pl.worse;
  end if;
  select count(*) as n, count(*) filter (where l.unmet > d.unmet) as tighter, count(*) filter (where l.unmet < d.unmet) as looser
    into v_rq from dark_req_0178 d join lit_req_0178 l using (player_id, subject_kind, subject_code);
  if v_rq.tighter > 0 then
    raise exception '0178 self-assert FAIL: % (player, subject) pair(s) gained an unmet requirement lit — lit must refuse nothing dark allowed', v_rq.tighter;
  end if;

  -- (c) EVERY HULL: no stat falls
  select count(*) as n,
         count(*) filter (where d.stats::text is distinct from l.stats::text) as moved,
         count(*) filter (where d.stats::text is distinct from l.stats::text and d.is_npc) as npc_moved,
         count(*) filter (where exists (select 1 from jsonb_each(d.stats) x
                                         where jsonb_typeof(x.value) = 'number'
                                           and (l.stats->>x.key)::numeric < (x.value #>> '{}')::numeric)) as fell,
         count(*) filter (where d.is_npc and (l.stats->>'hold') is distinct from (d.stats->>'hold')) as npc_hold_moved
    into v_sh
    from dark_ships_0178 d join lit_ships_0178 l using (ship_id);
  if v_sh.fell > 0 then
    raise exception '0178 self-assert FAIL: % hull(s) lost a stat lit — a skill only adds', v_sh.fell;
  end if;
  if v_sh.npc_hold_moved > 0 then
    raise exception '0178 self-assert FAIL: % merchant hull(s) moved their rated hold lit (no merchant holds a hold skill)', v_sh.npc_hold_moved;
  end if;

  -- (d) THE PROBE, against the plan's rows (S11, K2), from its own state
  d := j->'dark'; l := j->'lit';
  -- dark: nothing a skill gives, the gated hull refused even with every level it asks
  if (d->>'ship_max')::int <> (j->>'ship_max_knob')::int or (d->>'routes')::int <> (j->>'route_knob')::int then
    raise exception '0178 self-assert FAIL: dark, the probe''s caps read % / %, not the knobs % / %', d->>'ship_max', d->>'routes', j->>'ship_max_knob', j->>'route_knob';
  end if;
  if (j->>'dark_unmet_granted')::int = 0 or (d->>'refusal') not like '% — ship skills are not in use yet' then
    raise exception '0178 self-assert FAIL: dark, the gated hull % was not refused with every level granted (% unmet; %)', j->>'gated_hull', j->>'dark_unmet_granted', d->>'refusal';
  end if;
  -- lit: speed and sighting by PRT Small III (+6 %, +12 %: S11's per-level rows), cargo space by Cargo Stowage II
  -- + Merchant Ships II (+12 %), Command II → ship_max + 2 × per-level, Factorage II → 2 more routes (K2),
  -- Pursership V → the daily wage × (1 − 15 %) (K2)
  if (j->'pct'->>'speed')::numeric is distinct from 6 or (j->'pct'->>'sighting')::numeric is distinct from 12
     or (j->'pct'->>'hold')::numeric is distinct from 12 then
    raise exception '0178 self-assert FAIL: the probe''s %-class hull sums % from public.skill_effects — the plan''s rows say speed 6, sighting 12, hold 12',
      j->>'class', j->'pct';
  end if;
  if (l->'stats'->>'speed')::numeric is distinct from round(public.skill_scale((d->'stats'->>'speed')::numeric, 6), scale((d->'stats'->>'speed')::numeric))
     or (l->'stats'->>'sighting')::numeric is distinct from round(public.skill_scale((d->'stats'->>'sighting')::numeric, 12), scale((d->'stats'->>'sighting')::numeric))
     or (l->'stats'->>'hold')::numeric is distinct from round(public.skill_scale((d->'stats'->>'hold')::numeric, 12), scale((d->'stats'->>'hold')::numeric)) then
    raise exception '0178 self-assert FAIL: lit, the probe''s hull reads speed % / sighting % / hold % from dark % / % / % — not × 1.06 / × 1.12 / × 1.12',
      l->'stats'->>'speed', l->'stats'->>'sighting', l->'stats'->>'hold', d->'stats'->>'speed', d->'stats'->>'sighting', d->'stats'->>'hold';
  end if;
  if (l->>'hold')::numeric is distinct from floor((l->'stats'->>'hold')::numeric) then
    raise exception '0178 self-assert FAIL: lit, the probe''s cargo space % is not her lit hold % (no captain aboard)', l->>'hold', l->'stats'->>'hold';
  end if;
  if (l->>'speed')::numeric <= (d->>'speed')::numeric then
    raise exception '0178 self-assert FAIL: lit, the probe''s fleet speed % did not rise from %', l->>'speed', d->>'speed';
  end if;
  if (l->>'ship_max')::int <> (j->>'ship_max_knob')::int + 2 * (j->>'per_command')::int then
    raise exception '0178 self-assert FAIL: lit, Command II gives a hull cap of %, not % + 2 × %', l->>'ship_max', j->>'ship_max_knob', j->>'per_command';
  end if;
  if (l->>'routes')::int <> (j->>'route_knob')::int + 2 then
    raise exception '0178 self-assert FAIL: lit, Factorage II gives % routes, not % + 2', l->>'routes', j->>'route_knob';
  end if;
  if (l->>'wage')::bigint <> round((j->>'crew_wages')::numeric * (j->>'rcm')::numeric * (1 - 15 / 100.0))::bigint
     or (d->>'wage')::bigint <> round((j->>'crew_wages')::numeric * (j->>'rcm')::numeric)::bigint then
    raise exception '0178 self-assert FAIL: the probe''s daily wage reads % dark / % lit — Pursership V should take 15 %% off %', d->>'wage', l->>'wage', j->>'crew_wages';
  end if;
  if (j->>'lit_unmet_granted')::int <> 0 or (l->>'unmet')::int = 0 or (l->>'refusal') like '%not in use yet' then
    raise exception '0178 self-assert FAIL: lit, the gated hull % — % unmet with every level granted (want 0), % without (want > 0), refusal "%"',
      j->>'gated_hull', j->>'lit_unmet_granted', l->>'unmet', l->>'refusal';
  end if;
  if (l->>'bonuses')::int = 0 then
    raise exception '0178 self-assert FAIL: lit, the probe''s ship_view lists no skill bonus';
  end if;
  if (l->'control')::text is distinct from (d->'control')::text then
    raise exception '0178 self-assert FAIL: a house that learned nothing reads differently lit: % vs %', l->'control', d->'control';
  end if;

  raise notice '0178 self-assert ok: A COMPANY USES WHAT IT HAS LEARNED — skills_bite thrown true. MERCHANTS (% fleets): % read a faster speed (max +% %%, bound +5 %%), 0 moved cargo space, stores, wage, hiring, captains'' per cents, caps or budgets; % of % sampled quay spreads moved. PLAYERS (% fleets): % moved, 0 worse; requirements over % (player, subject) pairs: 0 tighter, % looser. HULLS (%): % stats moved (% merchant: combat stats + the English lines'' speed), 0 fell, no merchant hold moved. PROBE (%-class, own house, rolled back): lit speed % → %, sighting % → %, hold % → % (the plan''s +6 / +12 / +12 %%), fleet % → % kn; Command II hull cap % → %; Factorage II routes % → %; Pursership V wage % → %; gated hull % refused dark with every level held ("%"), buildable lit; a house that learned nothing reads the same. READ COST over the live merchants (fastest of 2, notice only): speed + cargo space % → % ms, ship_view % → % ms.',
    v_m.n, v_m.speed_moved, coalesce(v_m.speed_max_pct, 0), v_sp.moved, v_sp.n,
    v_pl.n, v_pl.moved, v_rq.n, v_rq.looser,
    v_sh.n, v_sh.moved, v_sh.npc_moved,
    j->>'class', d->'stats'->>'speed', l->'stats'->>'speed', d->'stats'->>'sighting', l->'stats'->>'sighting',
    d->'stats'->>'hold', l->'stats'->>'hold', d->>'speed', l->>'speed', d->>'ship_max', l->>'ship_max',
    d->>'routes', l->>'routes', d->>'wage', l->>'wage', j->>'gated_hull', d->>'refusal',
    v_td->>'speed_hold_ms', v_tl->>'speed_hold_ms', v_td->>'ship_view_ms', v_tl->>'ship_view_ms';
end $$;
