-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0127 — A SHIP LEARNS BY THE MILE  (docs/SHIPS_AND_GEAR.md §4, step S3)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE OWNER'S WORDS ───────────────────────────────────────────────────────────────────────────
-- 2026-10-15: *"we need levels, stats too."* Decisions of the same evening: a captain's level is PER
-- SIGNING (dismissed and signed again, she starts over); merchant captains, skills and levels are
-- CONSTANT — a merchant hull carries a fixed level and nothing levels in the arrivals tick for a
-- merchant; levelling is a LONG GRIND (ship_xp_nm_per_point 1,000 on 0069's curve: a hull running a
-- route round the clock reaches level 10 in about a month and level 20 in about four and a half).
--
-- ── WHAT WAS FOUND ──────────────────────────────────────────────────────────────────────────────
-- Nothing had a level but the company (0069's three tracks, derived; combat honestly 0). A hull's
-- miles cannot be re-read from the record — a VOYAGE_REPORT names a fleet, not her hulls — so a
-- hull's experience must be a counter, written in the same transaction as the report.
--
-- ── WHAT THIS FILE DOES ─────────────────────────────────────────────────────────────────────────
-- (1) ships.xp, player_officers.xp — points, on 0069's ONE curve (public.level_from_points). The
--     ONE writer for a player's: voyage.settle's arrival arm (one hunk), after the VOYAGE_REPORT,
--     `public.voyage_xp(voyage)` to every hull in the fleet and every officer posted to it. A
--     merchant fleet is told by ONE read of players.is_npc and gets nothing (no work in the tick).
--     The ONE writer of a merchant's: public.npc_fix_level(company) — 1 + floor(skill_sum / 3),
--     written once (here, and by npc_found for a company founded later), never moved.
-- (2) public.voyage_xp(voyage) — what a voyage teaches: total_nm / ship_xp_nm_per_point plus
--     public.fight_points per PIRATES day (EVADED 5, DRIVEN_OFF 15). Fights are paid AT ARRIVAL,
--     with the miles, so the settle hunk is one hunk and a merchant's pirate days cost nothing.
-- (3) public.player_progress — the combat track is DERIVED (3 hunks): fight_points over the PIRATES
--     days of the voyages she reported; `playable` true. A merchant's stays 0 (constant).
-- (4) public.levels_bite_on() + public.level_in_force(points): THE level that bites — the hull's or
--     captain's level while `levels_bite` is on, 1 while it is off. Shipped OFF (dark): every effect
--     below is exactly its pre-image until the owner flips one UPDATE; XP accrues either way.
-- (5) Effects, each in its one home: world.ship_stats (+handling, +accuracy, +sighting per level
--     above 1; one hunk); world.ship_slots (NEW, the one reading of class_slots: rows with
--     min_level <= the level in force are open, the rest locked); public.mount_fitting (two hunks:
--     its slots from ship_slots, E_SLOT_LOCKED, item_kinds.min_level → E_SHIP_LEVEL in 0050's
--     shape); public.fleet_officer_bonus (one hunk: bonus_pct × captain_level_mult, under the cap).
-- (6) class_slots.min_level (PK → class_slot, slot, min_level) and the three unlock rows of
--     §6.2 for today's hulls (barca +1 lookout @3, carlat +1 hull @4, nau +1 weapon @6). Every
--     existing row keeps 1, so nothing mounted is ever in a locked slot. item_kinds.min_level, all 1.
-- (7) world.ship_view serves level, xp, xp_from, next_level_at, slots_locked (two hunks) — for
--     your hull and a merchant's card alike; world.officers serves a signed officer's level (one hunk).
-- (8) THE SEED, once: a player's hull and her posted officers get voyage_xp summed over her fleet's
--     reported voyages; every merchant company's hulls npc_fix_level.
--
-- ── WHAT IT DOES NOT DO ─────────────────────────────────────────────────────────────────────────
-- No cron, no job, no table scan on a beat. Nothing reads handling/accuracy/sighting yet (S4 / the
-- combat slice), so a level's stat gain is visible and inert even once lit. Hull build levels
-- (hull_recipes.min_level) are S5's.
--
-- ── ROLLBACK ────────────────────────────────────────────────────────────────────────────────────
-- First: it ships dark (`levels_bite` false). Full: one forward migration re-cutting the eight
-- bodies back — every OLD hunk is in this file verbatim (hunks_0127.old) and the self-assert proves
-- each live body reverses to its pre-image by them — then delete the three unlock rows, restore the
-- class_slots PK, drop the columns and the new functions.
--
-- SUPERSEDES: voyage.settle (0123 as live), world.ship_stats and world.ship_view (0124),
-- public.mount_fitting (0126), public.fleet_officer_bonus (0015), public.player_progress (0069),
-- world.officers (0027 as live), public.npc_found (0126 as live) — hunks sliced from the LIVE bodies,
-- each asserted to occur exactly once. Self-asserts hold AS FOUND; every probe rolls back. No new
-- entry point, no client write.
-- VERSION: 0127. Applies on 0124 + 0126. 0125 (merchants dock) touches none of these bodies.

do $guard$ begin perform set_config('statement_timeout', '20min', true); end $guard$;

-- ── 1. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0127 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl
  from unnest(array['voyage.settle(uuid, timestamptz)', 'world.ship_stats(uuid)', 'world.ship_view(uuid)',
                    'public.mount_fitting(uuid, text)', 'public.fleet_officer_bonus(uuid, text)',
                    'public.player_progress(uuid)', 'world.officers()', 'public.npc_found(jsonb)']) f(fn);

create temp table entry_points_before_0127 on commit drop as
select count(*) as n from public.client_rpc_entry_points();

-- every hull afloat, as the one builder and the one stat computation served her
create temp table hulls_before_0127 on commit drop as
select s.id as ship_id, p.is_npc, world.ship_view(s.id) as view, world.ship_stats(s.id) as stats
  from public.ships s join public.players p on p.id = s.player_id;

-- every fleet with an officer posted, the four bonuses
create temp table bonus_before_0127 on commit drop as
select f.id as fleet_id, sp.sp, public.fleet_officer_bonus(f.id, sp.sp) as b
  from public.fleets f
 cross join unnest(array['NAVIGATOR', 'QUARTERMASTER', 'SURGEON', 'PURSER']) sp(sp)
 where exists (select 1 from public.player_officers po where po.fleet_id = f.id);

-- every player's three tracks (and a handful of merchants')
create temp table progress_before_0127 on commit drop as
select p.id as player_id, p.is_npc, public.player_progress(p.id) as prog, clock_timestamp() as at
  from public.players p
 where not p.is_npc or p.id in (select id from public.players where is_npc order by id limit 20);

-- what the arrivals tick reads per hull — her speed and her hold — timed over every merchant hull.
create temp table reads_before_0127 (ms numeric) on commit drop;
do $$
declare
  v_t0 timestamptz := clock_timestamp();
begin
  perform voyage.ship_speed(hb.ship_id), public.ship_hold_capacity(hb.ship_id) from hulls_before_0127 hb where hb.is_npc;
  insert into reads_before_0127 values (round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1));
end $$;

-- ── 2. THE COLUMNS, THE UNLOCK ROWS, THE KNOBS ─────────────────────────────────────────────────
alter table public.ships add column if not exists xp numeric not null default 0 check (xp >= 0);
comment on column public.ships.xp is
  '0127: her experience in points (0069''s curve: public.level_from_points). A player''s: written only by '
  'voyage.settle''s arrival arm (public.voyage_xp). A merchant''s: fixed once by public.npc_fix_level.';
alter table public.player_officers add column if not exists xp numeric not null default 0 check (xp >= 0);
comment on column public.player_officers.xp is
  '0127: this SIGNING''s experience — the miles and fights of the fleet she is posted to, written only by '
  'voyage.settle''s arrival arm. A new signing starts at 0. A merchant''s officers stay at 0.';

alter table public.class_slots add column if not exists min_level int not null default 1
  check (min_level between 1 and 20);
alter table public.class_slots drop constraint class_slots_pkey;
alter table public.class_slots add constraint class_slots_pkey primary key (class_code, slot, min_level);
comment on column public.class_slots.min_level is
  '0127: the hull level that opens these slots (world.ship_slots). 1 = from the yard.';
insert into public.class_slots (class_code, slot, count, min_level) values
  ('barca', 'lookout', 1, 3), ('carlat', 'hull', 1, 4), ('nau', 'weapon', 1, 6)
on conflict (class_code, slot, min_level) do update set count = excluded.count;

alter table public.item_kinds add column if not exists min_level int not null default 1
  check (min_level between 1 and 20);
comment on column public.item_kinds.min_level is
  '0127: the SHIP level a fitting asks before it can be mounted (public.mount_fitting, E_SHIP_LEVEL).';

insert into public.world_config (key, value, description) values
  ('ship_xp_nm_per_point', to_jsonb(1000::numeric),
   '0127: sea miles per point of a hull''s (and her captains'') experience, on 0069''s one curve. 1,000 is the '
   'owner''s long grind: a hull running a route round the clock reaches level 10 in about a month, level 20 in '
   'about four and a half.'),
  ('xp_evaded_points', to_jsonb(5::numeric),
   '0127: points a voyage pays for each pirate EVADED — to her hulls and officers, and to the company''s combat track.'),
  ('xp_driven_off_points', to_jsonb(15::numeric),
   '0127: points a voyage pays for each pirate DRIVEN_OFF — to her hulls and officers, and to the combat track.'),
  ('ship_level_handling_per_level', to_jsonb(1::numeric),
   '0127: handling a hull gains per level above 1 (while levels_bite is on).'),
  ('ship_level_accuracy_per_level', to_jsonb(1.5::numeric),
   '0127: accuracy a hull gains per level above 1 (while levels_bite is on).'),
  ('ship_level_sighting_per_level', to_jsonb(0.15::numeric),
   '0127: sighting a hull gains per level above 1 (while levels_bite is on).'),
  ('captain_level_pct_per_level', to_jsonb(2::numeric),
   '0127: per cent an officer''s own bonus grows per level above 1 of her signing (still under officer_bonus_cap_pct).'),
  ('levels_bite', 'false'::jsonb,
   '0127: true = a hull''s and a captain''s level does something (stats, slots, gear, officer bonus). false = every '
   'effect is off and the world reads as before 0127 while experience still accrues. Shipped false (dark).')
on conflict (key) do nothing;

-- ── 3. THE NEW FUNCTIONS ───────────────────────────────────────────────────────────────────────
create or replace function public.levels_bite_on()
returns boolean
language sql
stable
as $$ select public.wc('levels_bite') = 'true'::jsonb $$;
comment on function public.levels_bite_on() is '0127: the levels switch (world_config levels_bite). Server-only.';
revoke all on function public.levels_bite_on() from public, anon, authenticated;

create or replace function public.level_points(p_level int)
returns numeric
language sql
stable
as $$
  -- 0127: THE INVERSE OF THE ONE CURVE — the points at which level L begins: (L-1)² × level_points_per_step.
  select ((greatest(p_level, 1) - 1) * (greatest(p_level, 1) - 1))::numeric * public.wc_num('level_points_per_step')
$$;
comment on function public.level_points(int) is
  '0127: the points level L begins at, on public.level_from_points''s curve. Server-only.';
revoke all on function public.level_points(int) from public, anon, authenticated;

create or replace function public.level_in_force(p_points numeric)
returns int
language sql
stable
as $$
  -- 0127: THE LEVEL THAT BITES — her level on the one curve while levels_bite is on, 1 while it is off.
  select case when public.levels_bite_on() then public.level_from_points(p_points) else 1 end
$$;
comment on function public.level_in_force(numeric) is
  '0127: the level every effect reads (ship_stats, ship_slots, mount_fitting, captain_level_mult). Server-only.';
revoke all on function public.level_in_force(numeric) from public, anon, authenticated;

create or replace function public.captain_level_mult(p_xp numeric)
returns numeric
language sql
stable
as $$
  -- 0127: an officer's own bonus × (1 + pct × (level − 1)) — exactly 1 at level 1 or while dark.
  select case when l.lvl <= 1 then 1
              else 1 + public.wc_num('captain_level_pct_per_level') / 100 * (l.lvl - 1) end
    from (select public.level_in_force(p_xp) as lvl) l
$$;
comment on function public.captain_level_mult(numeric) is
  '0127: what an officer signing''s level makes of her bonus. Read by public.fleet_officer_bonus. Server-only.';
revoke all on function public.captain_level_mult(numeric) from public, anon, authenticated;

create or replace function public.fight_points(p_outcome text)
returns numeric
language sql
stable
as $$
  -- 0127: WHAT A FIGHT IS WORTH — the one table, for a hull, her officers and the company's combat track.
  select case p_outcome when 'EVADED'     then public.wc_num('xp_evaded_points')
                        when 'DRIVEN_OFF' then public.wc_num('xp_driven_off_points')
                        else 0 end
$$;
comment on function public.fight_points(text) is
  '0127: points for a PIRATES outcome (EVADED, DRIVEN_OFF; nothing for paying or losing). Server-only.';
revoke all on function public.fight_points(text) from public, anon, authenticated;

create or replace function public.voyage_xp(p_voyage uuid)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0127: WHAT A VOYAGE TEACHES her hulls and officers: her miles, and the pirates she saw off.
  select v.total_nm / public.wc_num('ship_xp_nm_per_point')
         + coalesce((select sum(public.fight_points(ve.payload->>'outcome'))
                       from public.voyage_events ve
                      where ve.voyage_id = v.id and ve.kind = 'PIRATES'), 0)
    from public.voyages v where v.id = p_voyage
$$;
comment on function public.voyage_xp(uuid) is
  '0127: points one voyage pays (total_nm / ship_xp_nm_per_point + fight_points). Read by voyage.settle '
  'at arrival and by 0127''s seed. Server-only.';
revoke all on function public.voyage_xp(uuid) from public, anon, authenticated;

create or replace function world.ship_slots(p_ship uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0127: THE ONE READING OF class_slots. Rows whose min_level the hull's level IN FORCE has reached
  -- are `open` {kind: count}; the rest are `locked` {kind: {count, at_level}}. Null for no such ship.
  with h as (
    select c.code, public.level_in_force(s.xp) as lvl
      from public.ships s join public.ship_classes c on c.id = s.class_id
     where s.id = p_ship
  ), r as (
    select cs.slot, cs.count, cs.min_level, cs.min_level <= h.lvl as open
      from h join public.class_slots cs on cs.class_code = h.code
  )
  select jsonb_build_object(
           'open', coalesce((select jsonb_object_agg(x.slot, x.n)
                               from (select slot, sum(count) as n from r where open group by slot) x), '{}'::jsonb),
           'locked', coalesce((select jsonb_object_agg(x.slot, jsonb_build_object('count', x.n, 'at_level', x.at))
                                 from (select slot, sum(count) as n, min(min_level) as at
                                         from r where not open group by slot) x), '{}'::jsonb))
    from h
$$;
comment on function world.ship_slots(uuid) is
  '0127: THE one reading of a hull''s slots at her level (class_slots.min_level). Read by world.ship_view '
  'and public.mount_fitting. Server-only.';
revoke all on function world.ship_slots(uuid) from public, anon, authenticated;

create or replace function public.npc_fix_level(p_player uuid)
returns int
language plpgsql
security definer
set search_path = public, pg_temp
as $nl$
declare
  v_sum int;
  v_lvl int;
begin
  -- 0127: A MERCHANT'S HULLS CARRY A FIXED LEVEL (owner, 2026-10-15): 1 + floor(the company's four
  -- skill levels added / 3) — the number the city list already prints as her level. Written once,
  -- at founding; nothing raises a merchant's skills, so it never moves.
  if not exists (select 1 from public.players p where p.id = p_player and p.is_npc) then
    raise exception 'E_NOT_A_MERCHANT: npc_fix_level fixes a merchant company''s level, and % is not one', p_player
      using errcode = 'P0001';
  end if;
  select coalesce(sum(ps.level), 0) into v_sum from public.player_skills ps where ps.player_id = p_player;
  v_lvl := public.level_from_points(public.level_points(1 + v_sum / 3));
  update public.ships set xp = public.level_points(v_lvl) where player_id = p_player;
  return v_lvl;
end $nl$;
comment on function public.npc_fix_level(uuid) is
  '0127: the ONE writer of a merchant hull''s xp — the points of level 1 + floor(skill_sum / 3). Called by '
  'npc_found and 0127''s seed. Refuses a player''s company. Server-only.';
revoke all on function public.npc_fix_level(uuid) from public, anon, authenticated;

-- ── 4. THE HUNKS (old = verbatim from the live bodies; new = what replaces it) ─────────────────
create temp table hunks_0127 (fn text, n int, old text, new text) on commit drop;

insert into hunks_0127 values
('voyage.settle(uuid, timestamptz)', 1,
$h$    -- 0122: the leg's wages reach the HARBOUR she made (a sea place or open water has no purse).
$h$,
$h$    -- 0127: WHAT THE VOYAGE TAUGHT HER — public.voyage_xp (her miles, the pirates she saw off) to every
    -- hull in the fleet and every officer posted to it. THE ONE WRITER of a player's xp. A merchant's
    -- levels are constant (owner, 2026-10-15): one read of players.is_npc, and nothing is written.
    if not (select p.is_npc from public.players p where p.id = f.player_id) then
      update public.ships set xp = xp + public.voyage_xp(v.id) where fleet_id = p_fleet;
      update public.player_officers set xp = xp + public.voyage_xp(v.id) where fleet_id = p_fleet;
    end if;
    -- 0122: the leg's wages reach the HARBOUR she made (a sea place or open water has no purse).
$h$),

('world.ship_stats(uuid)', 1,
$h$                              b.base + coalesce(d.delta, 0)) end)
    from public.ships s
    join public.ship_classes c on c.id = s.class_id
$h$,
$h$                              b.base + coalesce(d.delta, 0)
                              -- 0127: A WORKED-UP SHIP. Per level above 1 — the level IN FORCE, 1
                              -- while levels_bite is off — handling, accuracy and sighting grow.
                              -- Exactly + 0 at level 1.
                              + case when l.lvl > 1 then (l.lvl - 1) * case b.stat
                                       when 'handling' then public.wc_num('ship_level_handling_per_level')
                                       when 'accuracy' then public.wc_num('ship_level_accuracy_per_level')
                                       when 'sighting' then public.wc_num('ship_level_sighting_per_level')
                                       else 0 end
                                     else 0 end) end)
    from public.ships s
    join public.ship_classes c on c.id = s.class_id
   -- 0127: a hull with no experience is level 1 whatever the switch says; the switch is read only for one with some.
   cross join lateral (select case when s.xp > 0 then public.level_in_force(s.xp) else 1 end as lvl) l
$h$),

('world.ship_view(uuid)', 1,
$h$           -- 0077: class_slots alone.
           'slots', (select coalesce(jsonb_object_agg(cs.slot, cs.count), '{}'::jsonb)
             from public.class_slots cs where cs.class_code = c.code),
$h$,
$h$           -- 0127: her slots AT HER LEVEL (world.ship_slots, the one reading of class_slots) and
           -- the ones a level opens later; her level on the one curve and the points toward the next.
           'slots', y.sl->'open',
           'slots_locked', y.sl->'locked',
           'level', z.lvl,
           'xp', floor(s.xp),
           'xp_from', public.level_points(z.lvl),
           'next_level_at', case when public.level_from_points(public.level_points(z.lvl + 1)) > z.lvl
                                 then public.level_points(z.lvl + 1) end,
$h$),

('world.ship_view(uuid)', 2,
$h$   cross join lateral (select world.ship_stats(s.id) as st) x
$h$,
$h$   cross join lateral (select world.ship_stats(s.id) as st) x
   cross join lateral (select world.ship_slots(s.id) as sl) y
   cross join lateral (select public.level_from_points(s.xp) as lvl) z
$h$),

('public.mount_fitting(uuid, text)', 1,
$h$  v_used  int;
begin
$h$,
$h$  v_used  int;
  v_open  jsonb;
  v_lvl   int;
begin
$h$),

('public.mount_fitting(uuid, text)', 2,
$h$  -- 0077: ONE TABLE FOR EVERY KIND OF SLOT, weapons included.
  select coalesce(cs.count, 0) into v_slots
    from public.ship_classes c
    left join public.class_slots cs on cs.class_code = c.code and cs.slot = k.slot
   where c.id = v_ship.class_id;
$h$,
$h$  -- 0127: GEAR ASKS A LEVEL OF HER (item_kinds.min_level), against her level IN FORCE (1 while dark).
  v_lvl := public.level_in_force(v_ship.xp);
  if k.min_level > v_lvl then
    perform cmd.refuse('E_SHIP_LEVEL',
      format('%s asks a level %s ship and %s is level %s', k.name, k.min_level, v_ship.name, v_lvl),
      cmd.figures(v_lvl, k.min_level, 'level'));
  end if;
  -- 0127: HER SLOTS OF THIS KIND AT HER LEVEL — world.ship_slots, the one reading of class_slots. A kind
  -- whose open slots are taken and which a level opens more of is LOCKED, not full.
  v_open  := world.ship_slots(v_ship.id);
  v_slots := coalesce((v_open->'open'->>k.slot)::int, 0);
  if v_open->'locked' ? k.slot
     and (select coalesce(sum(sf.qty), 0) from public.ship_fittings sf join public.item_kinds ik on ik.code = sf.item_code
           where sf.ship_id = v_ship.id and ik.slot = k.slot) >= v_slots then
    perform cmd.refuse('E_SLOT_LOCKED',
      format('%s opens another %s slot at level %s', v_ship.name, k.slot, v_open->'locked'->k.slot->>'at_level'),
      cmd.figures(v_lvl, (v_open->'locked'->k.slot->>'at_level')::int, 'level'));
  end if;
$h$),

('public.fleet_officer_bonus(uuid, text)', 1,
$h$           coalesce(sum(o.bonus_pct), 0),
$h$,
$h$           -- 0127: each signing's bonus × her level's multiplier (exactly 1 at level 1 or while dark).
           coalesce(sum(o.bonus_pct * public.captain_level_mult(po.xp)), 0),
$h$),

('public.player_progress(uuid)', 1,
$h$  v_explore   int;
begin
$h$,
$h$  v_explore   int;
  v_combat    numeric := 0;   -- 0127
begin
$h$),

('public.player_progress(uuid)', 2,
$h$  v_trade   := floor(v_turnover / nullif(v_per_ducat, 0))::int;
$h$,
$h$  -- 0127: THE COMBAT TRACK, derived like the other two: every PIRATES day of every voyage she
  -- reported, at public.fight_points (EVADED 5, DRIVEN_OFF 15). A merchant's levels are constant
  -- (owner, 2026-10-15): not derived, 0.
  if not exists (select 1 from public.players p where p.id = p_player and p.is_npc) then
    select coalesce(sum(public.fight_points(ve.payload->>'outcome')), 0) into v_combat
      from public.events e
      join public.voyage_events ve on ve.voyage_id = (e.payload->>'voyage_id')::uuid and ve.kind = 'PIRATES'
     where e.player_id = p_player
       and e.kind = 'VOYAGE_REPORT'
       and e.payload ? 'voyage_id';
  end if;

  v_trade   := floor(v_turnover / nullif(v_per_ducat, 0))::int;
$h$),

('public.player_progress(uuid)', 3,
$h$    -- HONESTLY ZERO. Migration 0035: "It adds no combat, no NPC, no exploration. A half-built
    -- combat system is worse than none." `playable` says so out loud so a screen can print the
    -- reason instead of a blank.
    'combat', jsonb_build_object('points', 0, 'level', 1, 'playable', false));
$h$,
$h$    -- 0127: PLAYABLE. The pirates she saw off, on the one curve.
    'combat', jsonb_build_object('points', floor(v_combat)::int,
                                 'level', public.level_from_points(floor(v_combat)), 'playable', true));
$h$),

('world.officers()', 1,
$h$               'fleet', f.name
$h$,
$h$               'fleet', f.name,
               -- 0127: the level of YOUR signing of her (per signing; null for one you have not signed).
               'level', case when po.id is not null then public.level_from_points(po.xp) end
$h$),

('public.npc_found(jsonb)', 1,
$h$    perform public.npc_fit_loadout(s.id) from public.ships s where s.fleet_id = v_fleet order by s.is_flagship desc, s.name;
$h$,
$h$    perform public.npc_fit_loadout(s.id) from public.ships s where s.fleet_id = v_fleet order by s.is_flagship desc, s.name;
    -- 0127: HER HULLS' LEVEL, FIXED ONCE from the company's skills (public.npc_fix_level); never moved.
    perform public.npc_fix_level(v_player);
$h$);

-- ── 5. THE RE-CUTS ─────────────────────────────────────────────────────────────────────────────
create or replace function pg_temp.recut_0127(p_fn text)
returns void
language plpgsql
as $$
declare
  v_def text := replace(pg_get_functiondef(p_fn::regprocedure), E'\r', '');
  h     record;
  v_n   int;
begin
  for h in select * from hunks_0127 where fn = p_fn order by n loop
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0127 self-assert FAIL: hunk % of % occurs % time(s), not once — the live body is not what this file was cut against',
        h.n, p_fn, v_n;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
end $$;

select pg_temp.recut_0127(fn) from defs_before_0127 order by fn;

-- ── 6. THE SEED, once ──────────────────────────────────────────────────────────────────────────
-- A player's hull, and every officer posted to her fleet: what her fleet's reported voyages taught.
create temp table seed_0127 on commit drop as
select v.fleet_id, sum(public.voyage_xp(v.id)) as xp
  from public.events e
  join public.players p on p.id = e.player_id and not p.is_npc
  join public.voyages v on v.id = (e.payload->>'voyage_id')::uuid
 where e.kind = 'VOYAGE_REPORT' and e.payload ? 'voyage_id'
 group by v.fleet_id;
update public.ships s set xp = sd.xp from seed_0127 sd where s.fleet_id = sd.fleet_id;
update public.player_officers po set xp = sd.xp from seed_0127 sd where po.fleet_id = sd.fleet_id;

-- what every player's hull and officer now carries, before the merchants are seeded
create temp table player_xp_0127 on commit drop as
select (select coalesce(md5(string_agg(s.id::text || ':' || s.xp, ',' order by s.id)), '')
          from public.ships s join public.players p on p.id = s.player_id where not p.is_npc) as ships_h,
       (select coalesce(md5(string_agg(po.id::text || ':' || po.xp, ',' order by po.id)), '')
          from public.player_officers po join public.players p on p.id = po.player_id where not p.is_npc) as officers_h;

-- every merchant company: her hulls' fixed level
create temp table npc_seed_0127 (companies bigint, ms numeric) on commit drop;
do $$
declare
  v_t0 timestamptz := clock_timestamp();
  v_n  bigint := 0;
  r    record;
begin
  for r in select p.id from public.players p where p.is_npc order by p.id loop
    perform public.npc_fix_level(r.id);
    v_n := v_n + 1;
  end loop;
  insert into npc_seed_0127 values (v_n, round(extract(epoch from clock_timestamp() - v_t0) * 1000));
end $$;

-- ── 7. SELF-ASSERT ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  c_uid      constant uuid := '00000000-0127-4000-8000-000000000001';
  c_new_keys constant text[] := array['slots_locked', 'level', 'xp', 'xp_from', 'next_level_at'];
  -- A LIVE WORLD MOVES UNDER THE APPLY: the arrivals tick commits between statements (read committed),
  -- so what she carries, her hull points, crew, stores and the speed her load allows are compared
  -- nowhere here. None of them is touched by 0127; what 0127 touches (the six stats, slots,
  -- fittings, cabins, the rated figures) is compared for every hull, and ship_stats whole.
  c_live     constant text[] := array['durability', 'crew', 'cargo', 'cargo_tuns', 'water_t', 'food_t', 'speed', 'hold'];
  v_fn       text;
  v_def      text;
  v_back     text;
  h          record;
  v_n        int;
  v_bad      bigint;
  v_writers  text[];
  v_err      text;
  v_detail   text;
  v_player   uuid;
  v_fleet    uuid;
  v_ship     uuid;
  v_port     uuid;
  v_lis      uuid;
  v_fnc      uuid;
  v_leg      jsonb;
  v_back_c   jsonb;
  v_voy      uuid;
  v_xp       numeric;
  v_st0      jsonb;
  v_st1      jsonb;
  v_view     jsonb;
  v_m        uuid;
  v_mfleet   uuid;
  v_mxp      text;
  v_off      uuid;
  v_b        numeric;
  v_t0       timestamptz;
  v_settle_p numeric;
  v_settle_m numeric;
  v_read_ms  numeric;
  v_seed_n   bigint;
  v_seed_xp  numeric;
  v_lvls     text;
  v_lit_n    bigint;
  v_lit_b    bigint;
begin
  -- (a) PARITY BY REVERSE SUBSTITUTION; ACLs unmoved; each hunk in its new body exactly once.
  for v_fn in select fn from defs_before_0127 loop
    v_def := replace(pg_get_functiondef(v_fn::regprocedure), E'\r', '');
    v_back := v_def;
    for h in select * from hunks_0127 where fn = v_fn order by n desc loop
      v_n := (length(v_back) - length(replace(v_back, h.new, ''))) / length(h.new);
      if v_n <> 1 then
        raise exception '0127 self-assert FAIL: hunk % of % is in the new body % time(s), not once', h.n, v_fn, v_n;
      end if;
      v_back := replace(v_back, h.new, h.old);
    end loop;
    if v_back <> (select def from defs_before_0127 where fn = v_fn) or v_def = v_back then
      raise exception '0127 self-assert FAIL: % is not its pre-image plus only 0127''s hunks', v_fn;
    end if;
    if coalesce((select p.proacl::text from pg_proc p where p.oid = v_fn::regprocedure), '')
       is distinct from (select acl from defs_before_0127 where fn = v_fn) then
      raise exception '0127 self-assert FAIL: the re-cut moved the ACL of %', v_fn;
    end if;
  end loop;

  -- (b) ONE WRITER OF EACH xp. Positive control: settle's new body carries the token the scan looks
  --     for. The live bodies that write xp are settle (a player's) and npc_fix_level (a merchant's).
  if strpos(pg_get_functiondef('voyage.settle(uuid, timestamptz)'::regprocedure), 'set xp') = 0 then
    raise exception '0127 self-assert FAIL: the scan''s positive control — settle does not write xp';
  end if;
  select array_agg(n.nspname || '.' || p.proname order by n.nspname || '.' || p.proname) into v_writers
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage')
     and strpos(lower(p.prosrc), 'set xp') > 0;
  if v_writers is distinct from array['public.npc_fix_level', 'voyage.settle'] then
    raise exception '0127 self-assert FAIL: the live writers of xp are %, not settle and npc_fix_level alone', v_writers;
  end if;
  -- the settle hunk tells a merchant by players.is_npc and by nothing else; no effect body reads is_npc.
  v_def := (select new from hunks_0127 where fn = 'voyage.settle(uuid, timestamptz)' and n = 1);
  if strpos(v_def, 'p.is_npc') = 0 or strpos(v_def, 'auth_uid') > 0 then
    raise exception '0127 self-assert FAIL: the settle hunk does not tell a merchant by players.is_npc alone';
  end if;
  foreach v_fn in array array['world.ship_stats(uuid)', 'world.ship_view(uuid)', 'public.mount_fitting(uuid, text)',
                              'world.ship_slots(uuid)', 'public.fleet_officer_bonus(uuid, text)'] loop
    if strpos(pg_get_functiondef(v_fn::regprocedure), 'is_npc') > 0 then
      raise exception '0127 self-assert FAIL: % reads is_npc — a level is read the same for everyone', v_fn;
    end if;
  end loop;
  -- ONE READING OF class_slots: ship_slots alone (positive control: ship_view's pre-image read it).
  if strpos((select def from defs_before_0127 where fn = 'world.ship_view(uuid)'), 'public.class_slots') = 0 then
    raise exception '0127 self-assert FAIL: the class_slots scan''s positive control';
  end if;
  select array_agg(n.nspname || '.' || p.proname order by n.nspname || '.' || p.proname) into v_writers
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and strpos(p.prosrc, 'public.class_slots') > 0;
  if v_writers is distinct from array['world.ship_slots'] then
    raise exception '0127 self-assert FAIL: the live readers of class_slots are %, not world.ship_slots alone', v_writers;
  end if;

  -- (c) THE WALL: every new function server-only; no new entry point; no client write.
  foreach v_fn in array array['public.levels_bite_on()', 'public.level_points(int)', 'public.level_in_force(numeric)',
                              'public.captain_level_mult(numeric)', 'public.fight_points(text)', 'public.voyage_xp(uuid)',
                              'world.ship_slots(uuid)', 'public.npc_fix_level(uuid)'] loop
    if has_function_privilege('anon', v_fn, 'execute') or has_function_privilege('authenticated', v_fn, 'execute') then
      raise exception '0127 self-assert FAIL: % is client-reachable', v_fn;
    end if;
  end loop;
  if (select count(*) from public.client_rpc_entry_points()) <> (select n from entry_points_before_0127)
     or exists (select 1 from public.client_rpc_entry_points() e
                 where e.fn is null or not has_function_privilege('authenticated', e.fn, 'execute'))
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0127 self-assert FAIL: the registry, the grant wall or the read wall';
  end if;

  -- (d) THE CURVE'S INVERSE, and the switch ships dark.
  for v_n in 1 .. 20 loop
    if public.level_from_points(public.level_points(v_n)) <> v_n
       or (v_n > 1 and public.level_from_points(public.level_points(v_n) - 0.001) <> v_n - 1) then
      raise exception '0127 self-assert FAIL: level_points(%) is not where the one curve starts level %', v_n, v_n;
    end if;
  end loop;
  if public.levels_bite_on() then
    raise exception '0127 self-assert FAIL: levels_bite must ship off (dark)';
  end if;

  -- (e) DARK = THE PRE-IMAGES, for every hull, every officer bonus, every company's two old tracks.
  select count(*) into v_bad from hulls_before_0127 b join public.ships s on s.id = b.ship_id
   where world.ship_stats(b.ship_id) is distinct from b.stats
      or (world.ship_view(b.ship_id) - c_new_keys - c_live) is distinct from (b.view - c_live);
  if v_bad > 0 then
    raise exception '0127 self-assert FAIL: % hull(s) read differently while levels_bite is off', v_bad;
  end if;
  select count(*) into v_bad from hulls_before_0127 b
   where not (world.ship_view(b.ship_id) ?& c_new_keys);
  if v_bad > 0 then
    raise exception '0127 self-assert FAIL: % hull(s) are not served their level', v_bad;
  end if;
  select count(*) into v_bad from bonus_before_0127 b where public.fleet_officer_bonus(b.fleet_id, b.sp) is distinct from b.b;
  if v_bad > 0 then
    raise exception '0127 self-assert FAIL: % officer bonus(es) moved while levels_bite is off', v_bad;
  end if;
  -- (a house that acted in the two minutes around the capture is skipped: her record moved under us)
  select count(*) into v_bad from progress_before_0127 b
   where ((public.player_progress(b.player_id) - 'combat') is distinct from (b.prog - 'combat')
          and not exists (select 1 from public.events e where e.player_id = b.player_id
                             and e.created_at > b.at - interval '2 minutes'))
      or (public.player_progress(b.player_id)->'combat'->>'playable') is distinct from 'true'
      or (b.is_npc and (public.player_progress(b.player_id)->'combat'->>'points')::int <> 0);
  if v_bad > 0 then
    raise exception '0127 self-assert FAIL: % company track(s) moved, or combat is not playable', v_bad;
  end if;

  -- (f) THE SEED: every player hull carries what her fleet's reports taught (recomputed here from the
  --     events, not from seed_0127); every merchant hull exactly level 1 + floor(skill_sum / 3); the
  --     merchant seed touched no player row.
  select count(*) into v_bad
    from public.ships s join public.players p on p.id = s.player_id and not p.is_npc
   where s.xp <> coalesce((select sum(v.total_nm / public.wc_num('ship_xp_nm_per_point')
                                      + coalesce((select sum(public.fight_points(ve.payload->>'outcome'))
                                                    from public.voyage_events ve where ve.voyage_id = v.id and ve.kind = 'PIRATES'), 0))
                             from public.events e join public.voyages v on v.id = (e.payload->>'voyage_id')::uuid
                            where e.player_id = p.id and e.kind = 'VOYAGE_REPORT' and e.payload ? 'voyage_id'
                              and v.fleet_id = s.fleet_id), 0);
  if v_bad > 0 then
    raise exception '0127 self-assert FAIL: % player hull(s) were not seeded with their fleet''s reported voyages', v_bad;
  end if;
  select count(*) into v_bad
    from public.ships s join public.players p on p.id = s.player_id and p.is_npc
   where public.level_from_points(s.xp)
         <> least(20, 1 + (select coalesce(sum(ps.level), 0) from public.player_skills ps where ps.player_id = p.id) / 3)
      or s.xp <> (public.level_from_points(s.xp) - 1) * (public.level_from_points(s.xp) - 1)
                  * public.wc_num('level_points_per_step');
  if v_bad > 0 then
    raise exception '0127 self-assert FAIL: % merchant hull(s) do not carry their company''s fixed level', v_bad;
  end if;
  if (select (x.ships_h, x.officers_h) from player_xp_0127 x) is distinct from
     ((select coalesce(md5(string_agg(s.id::text || ':' || s.xp, ',' order by s.id)), '')
         from public.ships s join public.players p on p.id = s.player_id where not p.is_npc),
      (select coalesce(md5(string_agg(po.id::text || ':' || po.xp, ',' order by po.id)), '')
         from public.player_officers po join public.players p on p.id = po.player_id where not p.is_npc)) then
    raise exception '0127 self-assert FAIL: the merchant seed touched a player''s row';
  end if;
  if exists (select 1 from public.player_officers po join public.players p on p.id = po.player_id
              where p.is_npc and po.xp <> 0) then
    raise exception '0127 self-assert FAIL: a merchant''s officer carries experience';
  end if;
  select count(*), coalesce(sum(s.xp), 0) into v_seed_n, v_seed_xp
    from public.ships s join public.players p on p.id = s.player_id and not p.is_npc where s.xp > 0;
  select string_agg(format('L%s ×%s', l, n), ', ' order by l) into v_lvls
    from (select public.level_from_points(s.xp) as l, count(*) as n
            from public.ships s join public.players p on p.id = s.player_id and p.is_npc group by 1) x;

  -- what the arrivals tick reads per hull (speed and hold), now through the level term: timed for all.
  v_t0 := clock_timestamp();
  perform voyage.ship_speed(hb.ship_id), public.ship_hold_capacity(hb.ship_id) from hulls_before_0127 hb where hb.is_npc;
  v_read_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);

  -- (g) THE PROBES, rolled back.
  select id into v_lis from public.ports where code = 'LIS';
  select id into v_fnc from public.ports where code = 'FNC';
  select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon),
                           jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
    into v_leg from public.sea_reaches a, public.sea_reaches b
   where a.port_id = v_lis and b.port_id = v_fnc;
  v_back_c := jsonb_build_array(v_leg->1, v_leg->0);
  begin
    update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled', 'standing_routes_enabled');

    -- A PLAYER'S ARRIVAL TEACHES HER HULL AND HER OFFICER — exactly public.voyage_xp, through settle.
    v_player := public.new_house(c_uid, 'Casa da Milha', 'PRT');
    select id, port_id into v_fleet, v_port from public.fleets where player_id = v_player;
    select s.id into v_ship from public.ships s where s.fleet_id = v_fleet order by s.is_flagship desc, s.name limit 1;
    perform public.credit(v_player, 'PROBE_0127', 1000000);
    select o.code into v_mxp from public.officers o where o.specialty = 'NAVIGATOR' order by o.bonus_pct, o.code limit 1;
    if not coalesce((public.sign_officer(v_player, v_mxp, v_fleet)->>'ok')::boolean, false) then
      raise exception '0127 self-assert FAIL: the probe could not sign an officer';
    end if;
    select po.id into v_off from public.player_officers po where po.player_id = v_player;
    v_voy := voyage.depart(v_fleet, voyage.segments_from_course(v_leg), v_lis, v_fnc, now() - interval '60 days');
    v_t0 := clock_timestamp();
    perform voyage.settle(v_fleet, now());
    v_settle_p := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
    if (select status from public.voyages where id = v_voy) <> 'ARRIVED' then
      raise exception '0127 self-assert FAIL: the probe voyage did not arrive';
    end if;
    v_xp := public.voyage_xp(v_voy);
    if v_xp <= 0 or (select xp from public.ships where id = v_ship) <> v_xp
       or (select xp from public.player_officers where id = v_off) <> v_xp then
      raise exception '0127 self-assert FAIL: an arrival did not teach her hull and officer exactly voyage_xp (%: hull %, officer %)',
        v_xp, (select xp from public.ships where id = v_ship), (select xp from public.player_officers where id = v_off);
    end if;
    if (world.ship_view(v_ship)->>'xp')::numeric <> floor(v_xp) or (world.ship_view(v_ship)->>'level')::int <> public.level_from_points(v_xp) then
      raise exception '0127 self-assert FAIL: ship_view does not serve her experience';
    end if;
    -- THE COMBAT TRACK: one EVADED day on her reported voyage is 5 points more.
    v_n := (public.player_progress(v_player)->'combat'->>'points')::int;
    insert into public.voyage_events (voyage_id, day_index, kind, payload, resolved_at)
    values (v_voy, 9127, 'PIRATES', jsonb_build_object('outcome', 'EVADED'), now());
    if (public.player_progress(v_player)->'combat'->>'points')::int <> v_n + 5
       or (public.player_progress(v_player)->'combat'->>'playable') <> 'true' then
      raise exception '0127 self-assert FAIL: an EVADED day did not read 5 combat points (% → %)',
        v_n, public.player_progress(v_player)->'combat';
    end if;

    -- A MERCHANT'S ARRIVAL MOVES NO xp; her hulls read 1 + floor(skill_sum / 3) from founding.
    v_m := public.npc_found(jsonb_build_object(
      'company', 'Casa da Lenta', 'alt_company', 'Casa da Calma', 'nation', 'PRT', 'ink', 'prt',
      'master', 'Capitao Constante',
      'blurb', 'A probe company founded so its fixed level can be seen not to move.',
      'capital', 40000, 'patience', 0.20, 'wares', '[]'::jsonb, 'roster_ord', 9127,
      'skills', jsonb_build_object('NAVIGATION', 3, 'SEAMANSHIP', 3),
      'fleets', jsonb_build_array(jsonb_build_object(
        'name', 'Constante', 'roster_ord', 9127, 'days', 12,
        'ships', jsonb_build_array(jsonb_build_object('class', 'barca', 'name', 'Constante')),
        'officers', '[]'::jsonb,
        'stops', jsonb_build_array(jsonb_build_object('port', 'LIS', 'course', v_leg),
                                   jsonb_build_object('port', 'FNC', 'course', v_back_c)),
        'alt_stops', jsonb_build_array(jsonb_build_object('port', 'LIS', 'course', v_leg),
                                       jsonb_build_object('port', 'FNC', 'course', v_back_c))))));
    select f.id into v_mfleet from public.fleets f where f.player_id = v_m;
    if (select public.level_from_points(s.xp) from public.ships s where s.fleet_id = v_mfleet) <> 3 then
      raise exception '0127 self-assert FAIL: a founded merchant with skills 3+3 is not level 3';
    end if;
    select string_agg(s.id::text || ':' || s.xp, ',' order by s.id) into v_mxp from public.ships s where s.fleet_id = v_mfleet;
    v_voy := voyage.depart(v_mfleet, voyage.segments_from_course(v_leg), v_lis, v_fnc, now() - interval '60 days');
    v_t0 := clock_timestamp();
    perform voyage.settle(v_mfleet, now());
    v_settle_m := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
    if (select status from public.voyages where id = v_voy) <> 'ARRIVED'
       or (select string_agg(s.id::text || ':' || s.xp, ',' order by s.id) from public.ships s where s.fleet_id = v_mfleet) <> v_mxp then
      raise exception '0127 self-assert FAIL: a merchant''s arrival moved her xp (or she did not arrive)';
    end if;
    begin
      perform public.npc_fix_level(v_player);
      raise exception '0127 self-assert FAIL: npc_fix_level wrote a player''s hull';
    exception when sqlstate 'P0001' then
      if sqlerrm not like 'E_NOT_A_MERCHANT:%' then raise; end if;
    end;

    -- LIT, AT LEVEL 1, EVERYTHING IS ITS PRE-IMAGE — read over every hull and every officered fleet
    -- that IS at level 1 as seeded (no live row is rewritten: a mass UPDATE of ships here would take
    -- row locks the arrivals tick wants).
    update public.world_config set value = 'true'::jsonb where key = 'levels_bite';
    select count(*), count(*) filter (where world.ship_stats(b.ship_id) is distinct from b.stats
                                         or (world.ship_view(b.ship_id) - c_new_keys - c_live) is distinct from (b.view - c_live))
      into v_lit_n, v_bad
      from hulls_before_0127 b join public.ships s on s.id = b.ship_id
     where public.level_from_points(s.xp) = 1;
    if v_bad > 0 or v_lit_n = 0 then
      raise exception '0127 self-assert FAIL: lit, % of % level-1 hull(s) read differently from before', v_bad, v_lit_n;
    end if;
    select count(*), count(*) filter (where public.fleet_officer_bonus(b.fleet_id, b.sp) is distinct from b.b)
      into v_lit_b, v_bad
      from bonus_before_0127 b
     where not exists (select 1 from public.player_officers po
                        where po.fleet_id = b.fleet_id and public.level_from_points(po.xp) > 1);
    if v_bad > 0 or v_lit_b = 0 then
      raise exception '0127 self-assert FAIL: lit, % of % level-1 officer bonus(es) moved', v_bad, v_lit_b;
    end if;

    -- LIT: 25,000 nm is level 2 and +1 handling, +1.5 accuracy, +0.15 sighting.
    update public.ships set xp = 0 where id = v_ship;
    v_st0 := world.ship_stats(v_ship);
    update public.ships set xp = 25 where id = v_ship;
    v_st1 := world.ship_stats(v_ship);
    if (world.ship_view(v_ship)->>'level')::int <> 2
       or (v_st1->>'handling')::numeric <> (v_st0->>'handling')::numeric + 1
       or (v_st1->>'accuracy')::numeric <> (v_st0->>'accuracy')::numeric + 1.5
       or (v_st1->>'sighting')::numeric <> (v_st0->>'sighting')::numeric + 0.15
       or (v_st1 - array['handling', 'accuracy', 'sighting']) <> (v_st0 - array['handling', 'accuracy', 'sighting']) then
      raise exception '0127 self-assert FAIL: a level-2 hull does not gain exactly the per-level stats (% → %)', v_st0, v_st1;
    end if;
    -- A LOCKED SLOT: her class's lookout opens at 3. Refused E_SLOT_LOCKED with figures at 2; mounted at 3.
    if (select c.code from public.ships s join public.ship_classes c on c.id = s.class_id where s.id = v_ship) <> 'barca' then
      raise exception '0127 self-assert FAIL: the probe house''s first hull is not a barca';
    end if;
    select port_id into v_port from public.fleets where id = v_fleet;
    insert into public.player_items (player_id, port_id, item_code, qty) values (v_player, v_port, 'crows-nest', 2)
    on conflict (player_id, port_id, item_code) do update set qty = excluded.qty;
    v_err := null;
    begin
      perform cmd.do_fit(v_fleet, jsonb_build_object('item', 'crows-nest'));
    exception when sqlstate 'P0001' then
      get stacked diagnostics v_err = message_text, v_detail = pg_exception_detail;
    end;
    if v_err is null or v_err not like 'E_SLOT_LOCKED:%' or v_detail::jsonb <> '{"have": 2, "need": 3, "unit": "level"}'::jsonb
       or (world.ship_view(v_ship)->'slots_locked'->'lookout'->>'at_level')::int <> 3 then
      raise exception '0127 self-assert FAIL: a level-2 barca''s lookout was not refused E_SLOT_LOCKED with figures (% / %)', v_err, v_detail;
    end if;
    update public.ships set xp = public.level_points(3) where id = v_ship;
    perform cmd.do_fit(v_fleet, jsonb_build_object('item', 'crows-nest'));
    if (select qty from public.ship_fittings where ship_id = v_ship and item_code = 'crows-nest') is distinct from 1
       or (world.ship_view(v_ship)->'slots'->>'lookout')::int <> 1 or world.ship_view(v_ship)->'slots_locked' ? 'lookout' then
      raise exception '0127 self-assert FAIL: a level-3 barca''s lookout did not open';
    end if;
    -- GEAR ASKS A LEVEL: a carronade-shaped probe (boarding gear asking level 5) on a level-3 hull.
    update public.item_kinds set min_level = 5 where code = 'boarding-gear';
    insert into public.player_items (player_id, port_id, item_code, qty) values (v_player, v_port, 'boarding-gear', 1)
    on conflict (player_id, port_id, item_code) do update set qty = excluded.qty;
    v_err := null;
    begin
      perform cmd.do_fit(v_fleet, jsonb_build_object('item', 'boarding-gear'));
    exception when sqlstate 'P0001' then
      get stacked diagnostics v_err = message_text, v_detail = pg_exception_detail;
    end;
    if v_err is null or v_err not like 'E_SHIP_LEVEL:%' or v_detail::jsonb <> '{"have": 3, "need": 5, "unit": "level"}'::jsonb then
      raise exception '0127 self-assert FAIL: gear asking level 5 was not refused E_SHIP_LEVEL with figures (% / %)', v_err, v_detail;
    end if;
    -- A CAPTAIN'S LEVEL: her bonus × (1 + 2 % × 9) at level 10, under the cap; served to her house.
    perform cmd.assume_identity(c_uid);
    update public.player_officers set xp = public.level_points(10) where id = v_off;
    select least(o.bonus_pct * (1 + public.wc_num('captain_level_pct_per_level') / 100 * 9),
                 public.wc_num('officer_bonus_cap_pct')) / 100.0
      into v_b from public.player_officers po join public.officers o on o.id = po.officer_id where po.id = v_off;
    if public.fleet_officer_bonus(v_fleet, 'NAVIGATOR') <> v_b
       or (select (x->>'level')::int from jsonb_array_elements(world.officers()->'officers') x
            where x->>'hired' = 'true') is distinct from 10 then
      raise exception '0127 self-assert FAIL: a level-10 navigator is not worth her bonus × 1.18, or her level is not served (% vs %)',
        public.fleet_officer_bonus(v_fleet, 'NAVIGATOR'), v_b;
    end if;
    -- DARK AGAIN: the same hull and officer read level 1 in every effect.
    update public.world_config set value = 'false'::jsonb where key = 'levels_bite';
    update public.ships set xp = 0 where id = v_ship;
    v_st0 := world.ship_stats(v_ship);
    update public.ships set xp = public.level_points(3) where id = v_ship;
    if world.ship_stats(v_ship) <> v_st0
       or public.fleet_officer_bonus(v_fleet, 'NAVIGATOR')
          <> (select least(o.bonus_pct, public.wc_num('officer_bonus_cap_pct')) / 100.0
                from public.player_officers po join public.officers o on o.id = po.officer_id where po.id = v_off)
       or world.ship_view(v_ship)->'slots_locked'->'lookout' is null then
      raise exception '0127 self-assert FAIL: switched off, a level still bites';
    end if;

    raise exception 'ROLLBACK_0127';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0127' then raise; end if;
  end;
  if exists (select 1 from public.players where auth_uid = c_uid)
     or exists (select 1 from public.npc_houses where roster_ord = 9127)
     or public.levels_bite_on()
     or (select min_level from public.item_kinds where code = 'boarding-gear') <> 1 then
    raise exception '0127 self-assert FAIL: the probe world was not rolled back';
  end if;

  raise notice '0127 self-assert ok: A SHIP LEARNS BY THE MILE. Eight bodies (settle, ship_stats, ship_view, mount_fitting, fleet_officer_bonus, player_progress, officers, npc_found) reverse to their pre-images hunk by hunk, ACLs unmoved; the live writers of xp are voyage.settle (a player''s, at arrival) and npc_fix_level (a merchant''s, fixed) alone — positive control first; the settle hunk tells a merchant by players.is_npc alone and no effect body reads is_npc; world.ship_slots is the only reader of class_slots; eight new functions server-only, no new entry point, no client write; level_points inverts the one curve at 1..20; levels_bite ships OFF. DARK = PRE-IMAGE for % hull(s) (stats and view less the five new keys), % officer bonus(es), % company track(s) (combat now derived and playable). SEED: % player hull(s) carry Σ % pts from their fleets'' reports; % merchant companies fixed in % ms (%); no player row touched, no merchant officer has experience. Speed + hold reads for every merchant hull % ms (before 0127: % ms). Probes: a player arrival taught hull and officer exactly voyage_xp (settle % ms); one EVADED day = +5 combat; a merchant founded at skills 3+3 is level 3 and her arrival moved no xp (settle % ms); npc_fix_level refuses a player. LIT: % level-1 hull(s) and % level-1 officer bonus(es) read their pre-images; level 2 = +1 handling, +1.5 accuracy, +0.15 sighting; a barca''s lookout refused E_SLOT_LOCKED {2,3} and opens at 3; gear asking level 5 refused E_SHIP_LEVEL {3,5}; a level-10 navigator is bonus × 1.18 and served level 10; switched off, nothing bites. Rolled back.',
    (select count(*) from hulls_before_0127), (select count(*) from bonus_before_0127), (select count(*) from progress_before_0127),
    v_seed_n, round(v_seed_xp, 1), (select companies from npc_seed_0127), (select ms from npc_seed_0127), coalesce(v_lvls, 'none'),
    v_read_ms, (select ms from reads_before_0127), v_settle_p, v_settle_m, v_lit_n, v_lit_b;
end $$;
