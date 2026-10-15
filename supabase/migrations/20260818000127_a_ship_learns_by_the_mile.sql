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
-- (1) public.ship_xp (ship → points) and public.officer_xp (signing → points, aboard_since): NEW
--     side tables, so that no table the arrivals tick touches is ALTERed (an ADD COLUMN on ships or
--     player_officers holds ACCESS EXCLUSIVE until this file commits; a FK to them takes SHARE ROW
--     EXCLUSIVE — neither is taken: the ids are joined, a row left by a sunk hull is never read).
--     ONE writer of a player's: voyage.settle's arrival arm (ONE hunk, inserted just before the
--     `-- 0034 STANDING ORDER` comment, every line of 0122/0123 left as it is) credits
--     public.voyage_xp(voyage) to every hull in the fleet, and to every officer posted to it WHO WAS
--     ABOARD WHEN SHE DEPARTED (aboard_since — written by public.post_officer_to, one hunk — else
--     her signing's hired_at, <= departed_at): an officer moved onto a fleet at sea earns nothing
--     from that passage. A merchant fleet: ONE read of players.is_npc, nothing written.
--     ONE writer of a merchant's: public.npc_fix_level(company) — 1 + floor(skill_sum / 3), once
--     (this file's seed; npc_found's hunk for a company founded later), never moved.
-- (2) public.voyage_xp(voyage) — her miles / ship_xp_nm_per_point + public.fight_points per PIRATES
--     day (EVADED 5, DRIVEN_OFF 15), paid at arrival with the miles.
-- (3) public.levels_bite_on() + public.level_in_force(points): every effect reads the level IN FORCE
--     — her level while `levels_bite` is on, 1 while it is off. SHIPPED OFF (dark), and dark is the
--     pre-image everywhere: stats, slots, refusals, officer bonuses, the company's three tracks.
--     Only the DISPLAY is new while dark (a hull's level and xp; a signed officer's level).
-- (4) Effects, each in its one home: world.ship_stats (+handling/+accuracy/+sighting per level, one
--     hunk); world.ship_slots (NEW — the one reading of class_slots + public.class_slot_unlocks; a
--     locked slot is served only while lit); public.mount_fitting (two hunks: its slots from
--     ship_slots; E_SLOT_LOCKED and E_SHIP_LEVEL (public.item_level_asks) only while lit, so dark it
--     refuses E_NO_SLOT / E_SLOTS_FULL exactly as before); public.fleet_officer_bonus (one hunk:
--     bonus_pct × captain_level_mult(signing), exactly 1 while dark).
-- (5) public.player_progress — the combat track (3 hunks): while lit, the SAME scan that already
--     sums her reports' miles also sums the pirates they saw off (no second scan; dark adds no
--     work and serves the old honest zero, `playable` false). A merchant's stays 0.
-- (6) world.ship_view serves level, xp, xp_from, next_level_at, slots_locked (2 hunks);
--     world.officers a signed officer's level (1 hunk). public.class_slot_unlocks holds the §6.2
--     unlocks of today's hulls (barca +1 lookout @3, carlat +1 hull @4, nau +1 weapon @6).
-- (7) THE SEED, once, into the new tables only: a player's hull — her fleet's reported voyages; a
--     signing — the reported voyages of her fleet that departed after she signed; every merchant
--     company — npc_fix_level. No live row of ships or player_officers is written.
--
-- ── LOCKS ───────────────────────────────────────────────────────────────────────────────────────
-- lock_timeout 5 s. The only table locks beyond reads are the SHARE ROW EXCLUSIVE the two new FKs
-- take on the catalogue tables they reference — ship_classes, then item_kinds, in file order (reads
-- go on; nothing live writes them). No LOCK TABLE: db push runs this file as an implicit
-- transaction, where LOCK TABLE is refused (25P01). ships,
-- player_officers, class_slots and the arrivals tick's other tables are never locked beyond the
-- reads and the probe house's own rows. The arrivals clock need not be stopped for this push.
--
-- ── WHAT IT DOES NOT DO ─────────────────────────────────────────────────────────────────────────
-- No cron, no job, no scan on a beat. Nothing reads handling/accuracy/sighting yet (S4). Hull build
-- levels are S5's.
--
-- ── ROLLBACK ────────────────────────────────────────────────────────────────────────────────────
-- First: it ships dark. Full: one forward migration re-cutting the nine bodies back — every OLD hunk
-- is in this file verbatim (hunks_0127.old) and the self-assert proves each live body reverses to
-- its pre-image by them — then drop the four new tables and the new functions.
--
-- SUPERSEDES: voyage.settle (0123 as live), world.ship_stats and world.ship_view (0124),
-- public.mount_fitting (0126), public.fleet_officer_bonus (0015), public.player_progress (0069),
-- world.officers (0027 as live), public.npc_found (0126 as live), public.post_officer_to (0096) —
-- hunks sliced from the LIVE bodies, each asserted to occur exactly once. Self-asserts hold AS FOUND
-- (the arrivals tick runs during the apply); every probe rolls back and touches no live fleet. No
-- new entry point, no client write.
-- VERSION: 0127, on production head 0126 (0125 and 0126 both live). 0125 re-cut the four merchant
-- reads (sea_roster, port_merchants, npc_fleet_card, fleet_trades) — none of the nine bodies here.

do $guard$ begin
  perform set_config('statement_timeout', '20min', true);
  perform set_config('lock_timeout', '5s', true);
end $guard$;

-- ── 1. THE PRE-IMAGES ──────────────────────────────────────────────────────────────────────────
create temp table defs_before_0127 on commit drop as
select f.fn,
       replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
       coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl
  from unnest(array['voyage.settle(uuid, timestamptz)', 'world.ship_stats(uuid)', 'world.ship_view(uuid)',
                    'public.mount_fitting(uuid, text)', 'public.fleet_officer_bonus(uuid, text)',
                    'public.player_progress(uuid)', 'world.officers()', 'public.npc_found(jsonb)',
                    'public.post_officer_to(uuid, text, uuid)']) f(fn);

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

-- ── 2. THE NEW TABLES, THE UNLOCK ROWS, THE KNOBS ──────────────────────────────────────────────
-- No FK to ships / player_officers: a FK would lock the arrivals tick's tables (see LOCKS).
create table if not exists public.ship_xp (
  ship_id uuid    primary key,
  xp      numeric not null default 0 check (xp >= 0)
);
comment on table public.ship_xp is
  '0127: a hull''s experience in points (0069''s curve: public.level_from_points). A player''s: written only by '
  'voyage.settle''s arrival arm (public.voyage_xp). A merchant''s: fixed once by public.npc_fix_level. No row = 0.';
alter table public.ship_xp enable row level security;
revoke all on table public.ship_xp from public, anon, authenticated;

create table if not exists public.officer_xp (
  player_officer_id uuid        primary key,
  xp                numeric     not null default 0 check (xp >= 0),
  aboard_since      timestamptz
);
comment on table public.officer_xp is
  '0127: a SIGNING''s experience (player_officers.id: a new signing starts at 0) — written only by voyage.settle''s '
  'arrival arm, for a voyage she was aboard when it departed. aboard_since: when public.post_officer_to last posted '
  'her (null = since she signed, player_officers.hired_at). A merchant''s officers have no row.';
alter table public.officer_xp enable row level security;
revoke all on table public.officer_xp from public, anon, authenticated;

create table if not exists public.class_slot_unlocks (
  class_code text not null references public.ship_classes(code) on delete cascade,
  slot       text not null,
  count      int  not null check (count > 0),
  min_level  int  not null check (min_level between 2 and 20),
  primary key (class_code, slot, min_level)
);
comment on table public.class_slot_unlocks is
  '0127: slots a hull''s level opens beyond her class_slots (docs/SHIPS_AND_GEAR.md §6.2). Read only by world.ship_slots.';
alter table public.class_slot_unlocks enable row level security;
revoke all on table public.class_slot_unlocks from public, anon, authenticated;
insert into public.class_slot_unlocks (class_code, slot, count, min_level) values
  ('barca', 'lookout', 1, 3), ('carlat', 'hull', 1, 4), ('nau', 'weapon', 1, 6)
on conflict (class_code, slot, min_level) do update set count = excluded.count;

create table if not exists public.item_level_asks (
  item_code text primary key references public.item_kinds(code) on delete cascade,
  min_level int  not null check (min_level between 2 and 20)
);
comment on table public.item_level_asks is
  '0127: the SHIP level a fitting asks before it is mounted (public.mount_fitting, E_SHIP_LEVEL, while lit). '
  'No row = level 1. Empty today: the twelve fittings ask nothing.';
alter table public.item_level_asks enable row level security;
revoke all on table public.item_level_asks from public, anon, authenticated;

insert into public.world_config (key, value, description) values
  ('ship_xp_nm_per_point', to_jsonb(1000::numeric),
   '0127: sea miles per point of a hull''s (and her captains'') experience, on 0069''s one curve. 1,000 is the '
   'owner''s long grind: a hull running a route round the clock reaches level 10 in about a month, level 20 in '
   'about four and a half.'),
  ('xp_evaded_points', to_jsonb(5::numeric),
   '0127: points a voyage pays for each pirate EVADED — to her hulls and officers, and (lit) the combat track.'),
  ('xp_driven_off_points', to_jsonb(15::numeric),
   '0127: points a voyage pays for each pirate DRIVEN_OFF — to her hulls and officers, and (lit) the combat track.'),
  ('ship_level_handling_per_level', to_jsonb(1::numeric),
   '0127: handling a hull gains per level above 1 (while levels_bite is on).'),
  ('ship_level_accuracy_per_level', to_jsonb(1.5::numeric),
   '0127: accuracy a hull gains per level above 1 (while levels_bite is on).'),
  ('ship_level_sighting_per_level', to_jsonb(0.15::numeric),
   '0127: sighting a hull gains per level above 1 (while levels_bite is on).'),
  ('captain_level_pct_per_level', to_jsonb(2::numeric),
   '0127: per cent an officer''s own bonus grows per level above 1 of her signing (still under officer_bonus_cap_pct).'),
  ('levels_bite', 'false'::jsonb,
   '0127: true = levels do something (stats, slots, gear asks, officer bonus, the combat track). false = every '
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

create or replace function public.captain_level_mult(p_player_officer uuid)
returns numeric
language sql
stable
as $$
  -- 0127: an officer's own bonus × (1 + pct × (level − 1)) — exactly 1 at level 1, and while dark
  -- (nothing is read but the switch).
  select case when not public.levels_bite_on() then 1
              else (select case when l.lvl <= 1 then 1
                                else 1 + public.wc_num('captain_level_pct_per_level') / 100 * (l.lvl - 1) end
                      from (select public.level_from_points(coalesce(
                                     (select ox.xp from public.officer_xp ox where ox.player_officer_id = p_player_officer), 0)) as lvl) l)
         end
$$;
comment on function public.captain_level_mult(uuid) is
  '0127: what a signing''s level makes of her bonus. Read by public.fleet_officer_bonus. Server-only.';
revoke all on function public.captain_level_mult(uuid) from public, anon, authenticated;

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
  -- 0127: THE ONE READING OF A HULL'S SLOTS. Her class_slots are open from the yard; an unlock row
  -- is open once her level IN FORCE reaches it. `locked` {kind: {count, at_level}} is served only
  -- while levels_bite is on — dark, there is no level to wait for. Null for no such ship.
  with h as (
    select c.code, public.levels_bite_on() as bite,
           public.level_in_force(coalesce((select sx.xp from public.ship_xp sx where sx.ship_id = s.id), 0)) as lvl
      from public.ships s join public.ship_classes c on c.id = s.class_id
     where s.id = p_ship
  ), r as (
    select cs.slot, cs.count, 1 as min_level, true as open
      from h join public.class_slots cs on cs.class_code = h.code
    union all
    select u.slot, u.count, u.min_level, u.min_level <= h.lvl
      from h join public.class_slot_unlocks u on u.class_code = h.code
  )
  select jsonb_build_object(
           'open', coalesce((select jsonb_object_agg(x.slot, x.n)
                               from (select slot, sum(count) as n from r where open group by slot) x), '{}'::jsonb),
           'locked', case when h.bite then
                       coalesce((select jsonb_object_agg(x.slot, jsonb_build_object('count', x.n, 'at_level', x.at))
                                   from (select slot, sum(count) as n, min(min_level) as at
                                           from r where not open group by slot) x), '{}'::jsonb)
                     else '{}'::jsonb end)
    from h
$$;
comment on function world.ship_slots(uuid) is
  '0127: THE one reading of a hull''s slots at her level (class_slots + class_slot_unlocks). Read by '
  'world.ship_view and public.mount_fitting. Server-only.';
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
  insert into public.ship_xp (ship_id, xp)
  select s.id, public.level_points(v_lvl) from public.ships s where s.player_id = p_player
  on conflict (ship_id) do update set xp = excluded.xp;
  return v_lvl;
end $nl$;
comment on function public.npc_fix_level(uuid) is
  '0127: the ONE writer of a merchant hull''s experience — the points of level 1 + floor(skill_sum / 3). Called by '
  'npc_found and 0127''s seed. Refuses a player''s company. Server-only.';
revoke all on function public.npc_fix_level(uuid) from public, anon, authenticated;

-- ── 4. THE HUNKS (old = verbatim from the live bodies; new = what replaces it) ─────────────────
create temp table hunks_0127 (fn text, n int, old text, new text) on commit drop;

insert into hunks_0127 values
('voyage.settle(uuid, timestamptz)', 1,
$h$    -- 0034 STANDING ORDER: fires HERE, the one place a fleet makes port — after she docks,
$h$,
$h$    -- 0127: WHAT THE VOYAGE TAUGHT HER — public.voyage_xp (her miles, the pirates she saw off) to every
    -- hull in the fleet, and to every officer posted to it who was aboard when she departed
    -- (officer_xp.aboard_since, else her signing). THE ONE WRITER of a player's experience. A
    -- merchant's is constant (owner, 2026-10-15): one read of players.is_npc, and nothing is written.
    if not (select p.is_npc from public.players p where p.id = f.player_id) then
      insert into public.ship_xp (ship_id, xp)
      select sh.id, public.voyage_xp(v.id) from public.ships sh where sh.fleet_id = p_fleet
      on conflict (ship_id) do update set xp = public.ship_xp.xp + excluded.xp;
      insert into public.officer_xp (player_officer_id, xp)
      select po.id, public.voyage_xp(v.id) from public.player_officers po
       where po.fleet_id = p_fleet
         and coalesce((select ox.aboard_since from public.officer_xp ox where ox.player_officer_id = po.id),
                       po.hired_at) <= v.departed_at
      on conflict (player_officer_id) do update set xp = public.officer_xp.xp + excluded.xp;
    end if;
    -- 0034 STANDING ORDER: fires HERE, the one place a fleet makes port — after she docks,
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
    left join public.ship_xp sx on sx.ship_id = s.id
   -- 0127: a hull with no experience is level 1 whatever the switch says; the switch is read only for one with some.
   cross join lateral (select case when sx.xp > 0 then public.level_in_force(sx.xp) else 1 end as lvl) l
$h$),

('world.ship_view(uuid)', 1,
$h$           -- 0077: class_slots alone.
           'slots', (select coalesce(jsonb_object_agg(cs.slot, cs.count), '{}'::jsonb)
             from public.class_slots cs where cs.class_code = c.code),
$h$,
$h$           -- 0127: her slots AT HER LEVEL IN FORCE (world.ship_slots) and, while lit, the ones a level
           -- opens later; her level on the one curve and the points toward the next (shown dark too).
           'slots', y.sl->'open',
           'slots_locked', y.sl->'locked',
           'level', z.lvl,
           'xp', floor(coalesce(sx.xp, 0)),
           'xp_from', public.level_points(z.lvl),
           'next_level_at', case when public.level_from_points(public.level_points(z.lvl + 1)) > z.lvl
                                 then public.level_points(z.lvl + 1) end,
$h$),

('world.ship_view(uuid)', 2,
$h$   cross join lateral (select world.ship_stats(s.id) as st) x
$h$,
$h$   cross join lateral (select world.ship_stats(s.id) as st) x
    left join public.ship_xp sx on sx.ship_id = s.id
   cross join lateral (select world.ship_slots(s.id) as sl) y
   cross join lateral (select public.level_from_points(coalesce(sx.xp, 0)) as lvl) z
$h$),

('public.mount_fitting(uuid, text)', 1,
$h$  v_used  int;
begin
$h$,
$h$  v_used  int;
  v_open  jsonb;
  v_lvl   int;
  v_ask   int;
begin
$h$),

('public.mount_fitting(uuid, text)', 2,
$h$  -- 0077: ONE TABLE FOR EVERY KIND OF SLOT, weapons included.
  select coalesce(cs.count, 0) into v_slots
    from public.ship_classes c
    left join public.class_slots cs on cs.class_code = c.code and cs.slot = k.slot
   where c.id = v_ship.class_id;
$h$,
$h$  -- 0127: HER SLOTS OF THIS KIND AT HER LEVEL IN FORCE — world.ship_slots, the one reading of class_slots.
  -- While levels_bite is off nothing below refuses but 0077's E_NO_SLOT / E_SLOTS_FULL, as before.
  v_open  := world.ship_slots(v_ship.id);
  v_slots := coalesce((v_open->'open'->>k.slot)::int, 0);
  if public.levels_bite_on() then
    v_lvl := public.level_in_force(coalesce((select sx.xp from public.ship_xp sx where sx.ship_id = v_ship.id), 0));
    -- GEAR ASKS A LEVEL OF HER (public.item_level_asks; none = 1).
    v_ask := coalesce((select a.min_level from public.item_level_asks a where a.item_code = k.code), 1);
    if v_ask > v_lvl then
      perform cmd.refuse('E_SHIP_LEVEL',
        format('%s asks a level %s ship and %s is level %s', k.name, v_ask, v_ship.name, v_lvl),
        cmd.figures(v_lvl, v_ask, 'level'));
    end if;
    -- A kind whose open slots are taken and which a level opens more of is LOCKED, not full.
    if v_open->'locked' ? k.slot
       and (select coalesce(sum(sf.qty), 0) from public.ship_fittings sf join public.item_kinds ik on ik.code = sf.item_code
             where sf.ship_id = v_ship.id and ik.slot = k.slot) >= v_slots then
      perform cmd.refuse('E_SLOT_LOCKED',
        format('%s opens another %s slot at level %s', v_ship.name, k.slot, v_open->'locked'->k.slot->>'at_level'),
        cmd.figures(v_lvl, (v_open->'locked'->k.slot->>'at_level')::int, 'level'));
    end if;
  end if;
$h$),

('public.fleet_officer_bonus(uuid, text)', 1,
$h$           coalesce(sum(o.bonus_pct), 0),
$h$,
$h$           -- 0127: each signing's bonus × her level's multiplier (exactly 1 at level 1, and while dark).
           coalesce(sum(o.bonus_pct * public.captain_level_mult(po.id)), 0),
$h$),

('public.player_progress(uuid)', 1,
$h$  v_explore   int;
begin
$h$,
$h$  v_explore   int;
  v_bite      boolean := public.levels_bite_on();   -- 0127
  v_lit       boolean := false;                     -- 0127: lit, and not a merchant
  v_combat    numeric := 0;                         -- 0127
begin
$h$),

('public.player_progress(uuid)', 2,
$h$  select coalesce(sum((e.payload->>'total_nm')::numeric), 0) into v_nm
    from public.events e
   where e.player_id = p_player
     and e.kind = 'VOYAGE_REPORT'
     and e.payload ? 'total_nm';
$h$,
$h$  -- 0127: THE COMBAT TRACK rides THIS scan — while lit, each report's PIRATES days at fight_points
  -- (EVADED 5, DRIVEN_OFF 15); dark, the case below is never true and nothing more is read. A
  -- merchant's levels are constant (owner, 2026-10-15): never derived.
  if v_bite then
    v_lit := not exists (select 1 from public.players p where p.id = p_player and p.is_npc);
  end if;
  select coalesce(sum((e.payload->>'total_nm')::numeric), 0),
         coalesce(sum(case when v_lit and e.payload ? 'voyage_id' then
                        (select sum(public.fight_points(ve.payload->>'outcome')) from public.voyage_events ve
                          where ve.voyage_id = (e.payload->>'voyage_id')::uuid and ve.kind = 'PIRATES') end), 0)
    into v_nm, v_combat
    from public.events e
   where e.player_id = p_player
     and e.kind = 'VOYAGE_REPORT'
     and e.payload ? 'total_nm';
$h$),

('public.player_progress(uuid)', 3,
$h$    'combat', jsonb_build_object('points', 0, 'level', 1, 'playable', false));
$h$,
$h$    -- 0127: lit, the pirates she saw off on the one curve, PLAYABLE; dark, the honest zero above.
    'combat', case when v_bite
                   then jsonb_build_object('points', floor(v_combat)::int,
                                           'level', public.level_from_points(floor(v_combat)), 'playable', true)
                   else jsonb_build_object('points', 0, 'level', 1, 'playable', false) end);
$h$),

('world.officers()', 1,
$h$               'fleet', f.name
$h$,
$h$               'fleet', f.name,
               -- 0127: the level of YOUR signing of her (per signing; null for one you have not signed).
               'level', case when po.id is not null then public.level_from_points(coalesce(
                          (select ox.xp from public.officer_xp ox where ox.player_officer_id = po.id), 0)) end
$h$),

('public.npc_found(jsonb)', 1,
$h$    perform public.npc_fit_loadout(s.id) from public.ships s where s.fleet_id = v_fleet order by s.is_flagship desc, s.name;
$h$,
$h$    perform public.npc_fit_loadout(s.id) from public.ships s where s.fleet_id = v_fleet order by s.is_flagship desc, s.name;
    -- 0127: HER HULLS' LEVEL, FIXED ONCE from the company's skills (public.npc_fix_level); never moved.
    perform public.npc_fix_level(v_player);
$h$),

('public.post_officer_to(uuid, text, uuid)', 1,
$h$  return jsonb_build_object('ok', true, 'officer', v_code, 'fleet', p_fleet);
$h$,
$h$  -- 0127: WHEN SHE CAME ABOARD. A voyage teaches only the officers aboard when it departed
  -- (voyage.settle reads this): moved onto a fleet at sea, she earns nothing from that passage.
  insert into public.officer_xp (player_officer_id, aboard_since)
  select po.id, now() from public.player_officers po where po.player_id = v_player and po.officer_id = v_off
  on conflict (player_officer_id) do update set aboard_since = excluded.aboard_since;

  return jsonb_build_object('ok', true, 'officer', v_code, 'fleet', p_fleet);
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

-- ── 6. THE SEED, once, into the new tables only ────────────────────────────────────────────────
-- A player's hull: what her fleet's reported voyages taught.
insert into public.ship_xp (ship_id, xp)
select s.id, sum(public.voyage_xp(v.id))
  from public.events e
  join public.players p on p.id = e.player_id and not p.is_npc
  join public.voyages v on v.id = (e.payload->>'voyage_id')::uuid
  join public.ships s on s.fleet_id = v.fleet_id
 where e.kind = 'VOYAGE_REPORT' and e.payload ? 'voyage_id'
 group by s.id
on conflict (ship_id) do nothing;
-- A signing: the reported voyages of the fleet she is posted to that departed after she signed.
insert into public.officer_xp (player_officer_id, xp)
select po.id, sum(public.voyage_xp(v.id))
  from public.events e
  join public.players p on p.id = e.player_id and not p.is_npc
  join public.voyages v on v.id = (e.payload->>'voyage_id')::uuid
  join public.player_officers po on po.fleet_id = v.fleet_id and po.hired_at <= v.departed_at
 where e.kind = 'VOYAGE_REPORT' and e.payload ? 'voyage_id'
 group by po.id
on conflict (player_officer_id) do nothing;

create temp table player_xp_0127 on commit drop as
select (select coalesce(md5(string_agg(x.ship_id::text || ':' || x.xp, ',' order by x.ship_id)), '')
          from public.ship_xp x) as ships_h;

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
  v_m        uuid;
  v_mfleet   uuid;
  v_mxp      text;
  v_off      uuid;
  v_off2     uuid;
  v_code1    text;
  v_code2    text;
  v_b        numeric;
  v_t0       timestamptz;
  v_settle_p numeric;
  v_settle_m numeric;
  v_read_ms  numeric;
  v_seed_n   bigint;
  v_seed_xp  numeric;
  v_seed_o   bigint;
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

  -- (b) ONE WRITER OF EACH: experience — settle (a player's) and npc_fix_level (a merchant's), positive
  --     control first; aboard_since — post_officer_to, the only body that posts an officer.
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
  select array_agg(n.nspname || '.' || p.proname order by n.nspname || '.' || p.proname) into v_writers
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage')
     and (strpos(p.prosrc, 'update public.player_officers set fleet_id') > 0 or strpos(p.prosrc, 'aboard_since =') > 0);
  if v_writers is distinct from array['public.post_officer_to'] then
    raise exception '0127 self-assert FAIL: officers are posted / marked aboard by %, not post_officer_to alone', v_writers;
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
  -- NO TABLE THE TICK TOUCHES WAS ALTERED: ships and player_officers carry no xp column, and the
  -- new tables carry no FK to them.
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name in ('ships', 'player_officers', 'class_slots', 'item_kinds')
                and column_name in ('xp', 'min_level'))
     or exists (select 1 from pg_constraint c where c.contype = 'f'
                 and c.conrelid in ('public.ship_xp'::regclass, 'public.officer_xp'::regclass)) then
    raise exception '0127 self-assert FAIL: a hot table was altered, or a side table references it';
  end if;

  -- (c) THE WALL: every new function and table server-only; no new entry point; no client write.
  foreach v_fn in array array['public.levels_bite_on()', 'public.level_points(int)', 'public.level_in_force(numeric)',
                              'public.captain_level_mult(uuid)', 'public.fight_points(text)', 'public.voyage_xp(uuid)',
                              'world.ship_slots(uuid)', 'public.npc_fix_level(uuid)'] loop
    if has_function_privilege('anon', v_fn, 'execute') or has_function_privilege('authenticated', v_fn, 'execute') then
      raise exception '0127 self-assert FAIL: % is client-reachable', v_fn;
    end if;
  end loop;
  foreach v_fn in array array['public.ship_xp', 'public.officer_xp', 'public.class_slot_unlocks', 'public.item_level_asks'] loop
    if has_table_privilege('anon', v_fn, 'select') or has_table_privilege('authenticated', v_fn, 'select') then
      raise exception '0127 self-assert FAIL: % is client-readable', v_fn;
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

  -- (e) DARK = THE PRE-IMAGES, for every hull, every officer bonus, every company's three tracks; a
  --     hull's slots_locked is empty while dark.
  select count(*) into v_bad from hulls_before_0127 b join public.ships s on s.id = b.ship_id
   where world.ship_stats(b.ship_id) is distinct from b.stats
      or (world.ship_view(b.ship_id) - c_new_keys - c_live) is distinct from (b.view - c_live)
      or world.ship_view(b.ship_id)->'slots_locked' <> '{}'::jsonb
      or not (world.ship_view(b.ship_id) ?& c_new_keys);
  if v_bad > 0 then
    raise exception '0127 self-assert FAIL: % hull(s) read differently while levels_bite is off', v_bad;
  end if;
  select count(*) into v_bad from bonus_before_0127 b where public.fleet_officer_bonus(b.fleet_id, b.sp) is distinct from b.b;
  if v_bad > 0 then
    raise exception '0127 self-assert FAIL: % officer bonus(es) moved while levels_bite is off', v_bad;
  end if;
  -- (a house that acted in the two minutes around the capture is skipped: her record moved under us)
  select count(*) into v_bad from progress_before_0127 b
   where public.player_progress(b.player_id) is distinct from b.prog
     and not exists (select 1 from public.events e where e.player_id = b.player_id
                        and e.created_at > b.at - interval '2 minutes');
  if v_bad > 0 then
    raise exception '0127 self-assert FAIL: % company track(s) moved while levels_bite is off', v_bad;
  end if;

  -- (f) THE SEED: every player hull and signing carries what her fleet's reports taught — the signing
  --     only for voyages that departed after she signed (recomputed here, not from the seed); every
  --     merchant hull exactly level 1 + floor(skill_sum / 3); the merchant seed touched no player row.
  select count(*) into v_bad
    from public.ships s join public.players p on p.id = s.player_id and not p.is_npc
   where coalesce((select x.xp from public.ship_xp x where x.ship_id = s.id), 0)
         <> coalesce((select sum(public.voyage_xp(v.id))
                        from public.events e join public.voyages v on v.id = (e.payload->>'voyage_id')::uuid
                       where e.player_id = p.id and e.kind = 'VOYAGE_REPORT' and e.payload ? 'voyage_id'
                         and v.fleet_id = s.fleet_id), 0);
  if v_bad > 0 then
    raise exception '0127 self-assert FAIL: % player hull(s) were not seeded with their fleet''s reported voyages', v_bad;
  end if;
  select count(*) into v_bad
    from public.player_officers po join public.players p on p.id = po.player_id and not p.is_npc
   where coalesce((select x.xp from public.officer_xp x where x.player_officer_id = po.id), 0)
         <> coalesce((select sum(public.voyage_xp(v.id))
                        from public.events e join public.voyages v on v.id = (e.payload->>'voyage_id')::uuid
                       where e.player_id = p.id and e.kind = 'VOYAGE_REPORT' and e.payload ? 'voyage_id'
                         and v.fleet_id = po.fleet_id and v.departed_at >= po.hired_at), 0);
  if v_bad > 0 then
    raise exception '0127 self-assert FAIL: % signing(s) were not seeded with only the voyages since they signed', v_bad;
  end if;
  select count(*) into v_bad
    from public.ships s join public.players p on p.id = s.player_id and p.is_npc
    left join public.ship_xp x on x.ship_id = s.id
   where x.ship_id is null
      or public.level_from_points(x.xp)
         <> least(20, 1 + (select coalesce(sum(ps.level), 0) from public.player_skills ps where ps.player_id = p.id) / 3)
      or x.xp <> (public.level_from_points(x.xp) - 1) * (public.level_from_points(x.xp) - 1)
                  * public.wc_num('level_points_per_step');
  if v_bad > 0 then
    raise exception '0127 self-assert FAIL: % merchant hull(s) do not carry their company''s fixed level', v_bad;
  end if;
  if (select ships_h from player_xp_0127) is distinct from
     (select coalesce(md5(string_agg(x.ship_id::text || ':' || x.xp, ',' order by x.ship_id)), '')
        from public.ship_xp x
       where not exists (select 1 from public.ships s join public.players p on p.id = s.player_id
                          where s.id = x.ship_id and p.is_npc)) then
    raise exception '0127 self-assert FAIL: the merchant seed touched a player''s row';
  end if;
  if exists (select 1 from public.officer_xp ox join public.player_officers po on po.id = ox.player_officer_id
               join public.players p on p.id = po.player_id where p.is_npc) then
    raise exception '0127 self-assert FAIL: a merchant''s officer carries experience';
  end if;
  select count(*), coalesce(sum(x.xp), 0) into v_seed_n, v_seed_xp
    from public.ship_xp x join public.ships s on s.id = x.ship_id
    join public.players p on p.id = s.player_id and not p.is_npc where x.xp > 0;
  select count(*) into v_seed_o from public.officer_xp where xp > 0;
  select string_agg(format('L%s ×%s', l, n), ', ' order by l) into v_lvls
    from (select public.level_from_points(x.xp) as l, count(*) as n
            from public.ship_xp x join public.ships s on s.id = x.ship_id
            join public.players p on p.id = s.player_id and p.is_npc group by 1) y;

  -- what the arrivals tick reads per hull (speed and hold), now through the level term: timed for all.
  v_t0 := clock_timestamp();
  perform voyage.ship_speed(hb.ship_id), public.ship_hold_capacity(hb.ship_id) from hulls_before_0127 hb where hb.is_npc;
  v_read_ms := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);

  -- (g) THE PROBES — a probe house and a probe company of their own, never a live fleet; rolled back.
  select id into v_lis from public.ports where code = 'LIS';
  select id into v_fnc from public.ports where code = 'FNC';
  select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon),
                           jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
    into v_leg from public.sea_reaches a, public.sea_reaches b
   where a.port_id = v_lis and b.port_id = v_fnc;
  v_back_c := jsonb_build_array(v_leg->1, v_leg->0);
  begin
    -- A PLAYER'S ARRIVAL TEACHES HER HULL AND THE OFFICER ABOARD SINCE DEPARTURE — exactly
    -- public.voyage_xp, through settle; an officer posted to her AT SEA earns nothing.
    v_player := public.new_house(c_uid, 'Casa da Milha', 'PRT');
    select id, port_id into v_fleet, v_port from public.fleets where player_id = v_player;
    select s.id into v_ship from public.ships s where s.fleet_id = v_fleet order by s.is_flagship desc, s.name limit 1;
    perform public.credit(v_player, 'PROBE_0127', 1000000);
    select o.code into v_code1 from public.officers o where o.specialty = 'NAVIGATOR' order by o.bonus_pct, o.code limit 1;
    select o.code into v_code2 from public.officers o where o.specialty = 'SURGEON' order by o.bonus_pct, o.code limit 1;
    if not coalesce((public.sign_officer(v_player, v_code1, v_fleet)->>'ok')::boolean, false)
       or not coalesce((public.sign_officer(v_player, v_code2, null)->>'ok')::boolean, false) then
      raise exception '0127 self-assert FAIL: the probe could not sign its officers';
    end if;
    select po.id into v_off from public.player_officers po join public.officers o on o.id = po.officer_id
     where po.player_id = v_player and o.code = v_code1;
    select po.id into v_off2 from public.player_officers po join public.officers o on o.id = po.officer_id
     where po.player_id = v_player and o.code = v_code2;
    -- the probe's voyage departs 60 days ago; her navigator signed before it, the surgeon is posted after.
    update public.player_officers set hired_at = now() - interval '61 days' where player_id = v_player;
    v_voy := voyage.depart(v_fleet, voyage.segments_from_course(v_leg), v_lis, v_fnc, now() - interval '60 days');
    if not coalesce((public.post_officer_to(v_player, v_code2, v_fleet)->>'ok')::boolean, false) then
      raise exception '0127 self-assert FAIL: the probe could not post an officer to its fleet at sea';
    end if;
    v_t0 := clock_timestamp();
    perform voyage.settle(v_fleet, now());
    v_settle_p := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
    if (select status from public.voyages where id = v_voy) <> 'ARRIVED' then
      raise exception '0127 self-assert FAIL: the probe voyage did not arrive';
    end if;
    v_xp := public.voyage_xp(v_voy);
    if v_xp <= 0 or (select xp from public.ship_xp where ship_id = v_ship) is distinct from v_xp
       or (select xp from public.officer_xp where player_officer_id = v_off) is distinct from v_xp
       or coalesce((select xp from public.officer_xp where player_officer_id = v_off2), 0) <> 0 then
      raise exception '0127 self-assert FAIL: an arrival did not teach exactly voyage_xp to her hull and the officer aboard since departure, and nothing to the one posted at sea (%: hull %, aboard %, posted at sea %)',
        v_xp, (select xp from public.ship_xp where ship_id = v_ship),
        (select xp from public.officer_xp where player_officer_id = v_off), (select xp from public.officer_xp where player_officer_id = v_off2);
    end if;
    if (world.ship_view(v_ship)->>'xp')::numeric <> floor(v_xp) or (world.ship_view(v_ship)->>'level')::int <> public.level_from_points(v_xp) then
      raise exception '0127 self-assert FAIL: ship_view does not serve her experience';
    end if;
    -- DARK: one EVADED day reads no combat points; her barca's lookout is refused in 0077's words.
    insert into public.voyage_events (voyage_id, day_index, kind, payload, resolved_at)
    values (v_voy, 9127, 'PIRATES', jsonb_build_object('outcome', 'EVADED'), now());
    if public.player_progress(v_player)->'combat' <> '{"points": 0, "level": 1, "playable": false}'::jsonb then
      raise exception '0127 self-assert FAIL: dark, the combat track moved: %', public.player_progress(v_player)->'combat';
    end if;
    if (select c.code from public.ships s join public.ship_classes c on c.id = s.class_id where s.id = v_ship) <> 'barca' then
      raise exception '0127 self-assert FAIL: the probe house''s first hull is not a barca';
    end if;
    select port_id into v_port from public.fleets where id = v_fleet;
    insert into public.player_items (player_id, port_id, item_code, qty) values (v_player, v_port, 'crows-nest', 2)
    on conflict (player_id, port_id, item_code) do update set qty = excluded.qty;
    insert into public.ship_xp (ship_id, xp) values (v_ship, public.level_points(3))
    on conflict (ship_id) do update set xp = excluded.xp;
    v_err := null;
    begin
      perform cmd.do_fit(v_fleet, jsonb_build_object('item', 'crows-nest'));
    exception when sqlstate 'P0001' then
      v_err := sqlerrm;
    end;
    if v_err is null or v_err not like 'E_NO_SLOT: a % has nowhere to put a %' then
      raise exception '0127 self-assert FAIL: dark, a level-3 barca''s lookout was not refused E_NO_SLOT as before (%)', v_err;
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
    if (select public.level_from_points(x.xp) from public.ships s join public.ship_xp x on x.ship_id = s.id
         where s.fleet_id = v_mfleet) is distinct from 3 then
      raise exception '0127 self-assert FAIL: a founded merchant with skills 3+3 is not level 3';
    end if;
    select string_agg(s.id::text || ':' || x.xp, ',' order by s.id) into v_mxp
      from public.ships s join public.ship_xp x on x.ship_id = s.id where s.fleet_id = v_mfleet;
    v_voy := voyage.depart(v_mfleet, voyage.segments_from_course(v_leg), v_lis, v_fnc, now() - interval '60 days');
    v_t0 := clock_timestamp();
    perform voyage.settle(v_mfleet, now());
    v_settle_m := round(extract(epoch from clock_timestamp() - v_t0) * 1000, 1);
    if (select status from public.voyages where id = v_voy) <> 'ARRIVED'
       or (select string_agg(s.id::text || ':' || x.xp, ',' order by s.id)
             from public.ships s join public.ship_xp x on x.ship_id = s.id where s.fleet_id = v_mfleet) <> v_mxp then
      raise exception '0127 self-assert FAIL: a merchant''s arrival moved her xp (or she did not arrive)';
    end if;
    begin
      perform public.npc_fix_level(v_player);
      raise exception '0127 self-assert FAIL: npc_fix_level wrote a player''s hull';
    exception when sqlstate 'P0001' then
      if sqlerrm not like 'E_NOT_A_MERCHANT:%' then raise; end if;
    end;

    -- LIT (inside this rolled-back block only). At level 1 every hull and bonus is its pre-image —
    -- read over the live level-1 hulls and officered fleets as seeded; no live row is written.
    update public.world_config set value = 'true'::jsonb where key = 'levels_bite';
    select count(*), count(*) filter (where world.ship_stats(b.ship_id) is distinct from b.stats
                                         or (world.ship_view(b.ship_id) - c_new_keys - c_live) is distinct from (b.view - c_live))
      into v_lit_n, v_bad
      from hulls_before_0127 b join public.ships s on s.id = b.ship_id
     where public.level_from_points(coalesce((select x.xp from public.ship_xp x where x.ship_id = s.id), 0)) = 1;
    if v_bad > 0 or v_lit_n = 0 then
      raise exception '0127 self-assert FAIL: lit, % of % level-1 hull(s) read differently from before', v_bad, v_lit_n;
    end if;
    select count(*), count(*) filter (where public.fleet_officer_bonus(b.fleet_id, b.sp) is distinct from b.b)
      into v_lit_b, v_bad
      from bonus_before_0127 b
     where not exists (select 1 from public.player_officers po join public.officer_xp ox on ox.player_officer_id = po.id
                        where po.fleet_id = b.fleet_id and public.level_from_points(ox.xp) > 1);
    if v_bad > 0 or v_lit_b = 0 then
      raise exception '0127 self-assert FAIL: lit, % of % level-1 officer bonus(es) moved', v_bad, v_lit_b;
    end if;
    -- LIT: the EVADED day is 5 combat points more, and the track is playable.
    if (public.player_progress(v_player)->'combat'->>'points')::int
         <> (select floor(sum(public.fight_points(ve.payload->>'outcome')))::int from public.voyage_events ve
              join public.voyages v on v.id = ve.voyage_id where v.fleet_id = v_fleet and ve.kind = 'PIRATES')
       or (public.player_progress(v_player)->'combat'->>'points')::int < 5
       or (public.player_progress(v_player)->'combat'->>'playable') <> 'true' then
      raise exception '0127 self-assert FAIL: lit, the EVADED day did not read on the combat track: %', public.player_progress(v_player)->'combat';
    end if;
    -- LIT: 25,000 nm is level 2 and +1 handling, +1.5 accuracy, +0.15 sighting.
    update public.ship_xp set xp = 0 where ship_id = v_ship;
    v_st0 := world.ship_stats(v_ship);
    update public.ship_xp set xp = 25 where ship_id = v_ship;
    v_st1 := world.ship_stats(v_ship);
    if (world.ship_view(v_ship)->>'level')::int <> 2
       or (v_st1->>'handling')::numeric <> (v_st0->>'handling')::numeric + 1
       or (v_st1->>'accuracy')::numeric <> (v_st0->>'accuracy')::numeric + 1.5
       or (v_st1->>'sighting')::numeric <> (v_st0->>'sighting')::numeric + 0.15
       or (v_st1 - array['handling', 'accuracy', 'sighting']) <> (v_st0 - array['handling', 'accuracy', 'sighting']) then
      raise exception '0127 self-assert FAIL: a level-2 hull does not gain exactly the per-level stats (% → %)', v_st0, v_st1;
    end if;
    -- LIT: a locked slot — her lookout opens at 3. Refused E_SLOT_LOCKED with figures at 2; mounted at 3.
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
    update public.ship_xp set xp = public.level_points(3) where ship_id = v_ship;
    perform cmd.do_fit(v_fleet, jsonb_build_object('item', 'crows-nest'));
    if (select qty from public.ship_fittings where ship_id = v_ship and item_code = 'crows-nest') is distinct from 1
       or (world.ship_view(v_ship)->'slots'->>'lookout')::int <> 1 or world.ship_view(v_ship)->'slots_locked' ? 'lookout' then
      raise exception '0127 self-assert FAIL: a level-3 barca''s lookout did not open';
    end if;
    -- LIT: gear asks a level — a carronade-shaped probe (boarding gear asking level 5) on a level-3 hull.
    insert into public.item_level_asks (item_code, min_level) values ('boarding-gear', 5);
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
    -- LIT: a captain's level — her bonus × (1 + 2 % × 9) at level 10, under the cap; served to her house.
    perform cmd.assume_identity(c_uid);
    update public.officer_xp set xp = public.level_points(10) where player_officer_id = v_off;
    select least(o.bonus_pct * (1 + public.wc_num('captain_level_pct_per_level') / 100 * 9),
                 public.wc_num('officer_bonus_cap_pct')) / 100.0
      into v_b from public.player_officers po join public.officers o on o.id = po.officer_id where po.id = v_off;
    if public.fleet_officer_bonus(v_fleet, 'NAVIGATOR') <> v_b
       or (select (x->>'level')::int from jsonb_array_elements(world.officers()->'officers') x
            where x->>'code' = v_code1) is distinct from 10 then
      raise exception '0127 self-assert FAIL: a level-10 navigator is not worth her bonus × 1.18, or her level is not served (% vs %)',
        public.fleet_officer_bonus(v_fleet, 'NAVIGATOR'), v_b;
    end if;
    -- DARK AGAIN: the same hull and officer read level 1 in every effect, and nothing is locked.
    update public.world_config set value = 'false'::jsonb where key = 'levels_bite';
    update public.ship_xp set xp = 0 where ship_id = v_ship;
    v_st0 := world.ship_stats(v_ship);
    update public.ship_xp set xp = public.level_points(3) where ship_id = v_ship;
    if world.ship_stats(v_ship) <> v_st0
       or public.fleet_officer_bonus(v_fleet, 'NAVIGATOR')
          <> (select least(o.bonus_pct, public.wc_num('officer_bonus_cap_pct')) / 100.0
                from public.player_officers po join public.officers o on o.id = po.officer_id where po.id = v_off)
       or world.ship_view(v_ship)->'slots_locked' <> '{}'::jsonb then
      raise exception '0127 self-assert FAIL: switched off, a level still bites';
    end if;

    raise exception 'ROLLBACK_0127';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0127' then raise; end if;
  end;
  if exists (select 1 from public.players where auth_uid = c_uid)
     or exists (select 1 from public.npc_houses where roster_ord = 9127)
     or public.levels_bite_on()
     or exists (select 1 from public.item_level_asks) then
    raise exception '0127 self-assert FAIL: the probe world was not rolled back';
  end if;

  raise notice '0127 self-assert ok: A SHIP LEARNS BY THE MILE. Nine bodies (settle, ship_stats, ship_view, mount_fitting, fleet_officer_bonus, player_progress, officers, npc_found, post_officer_to) reverse to their pre-images hunk by hunk, ACLs unmoved; the live writers of experience are voyage.settle (a player''s, at arrival) and npc_fix_level (a merchant''s, fixed) alone — positive control first; post_officer_to alone posts an officer and marks her aboard; the settle hunk tells a merchant by players.is_npc alone and no effect body reads is_npc; world.ship_slots is the only reader of class_slots; no hot table altered, no FK to one; new functions and tables server-only, no new entry point, no client write; level_points inverts the one curve at 1..20; levels_bite ships OFF. DARK = PRE-IMAGE for % hull(s) (less the five new display keys, nothing locked), % officer bonus(es), % company track(s) (combat still the honest zero). SEED: % player hull(s) carry Σ % pts from their fleets'' reports, % signing(s) only voyages since signing; % merchant companies fixed in % ms (%); no player row touched, no merchant officer has experience. Speed + hold reads for every merchant hull % ms (before 0127: % ms). Probes (own house, own company): a player arrival taught her hull and the officer aboard since departure exactly voyage_xp, the officer posted at sea nothing (settle % ms); dark, an EVADED day is no combat and a level-3 barca''s lookout refuses E_NO_SLOT as before; a merchant founded at skills 3+3 is level 3 and her arrival moved no xp (settle % ms); npc_fix_level refuses a player. LIT: % level-1 hull(s) and % level-1 officer bonus(es) read their pre-images; the EVADED day is +5 combat, playable; level 2 = +1 handling, +1.5 accuracy, +0.15 sighting; E_SLOT_LOCKED {2,3}, opens at 3; E_SHIP_LEVEL {3,5}; a level-10 navigator is bonus × 1.18 and served level 10; switched off, nothing bites. Rolled back.',
    (select count(*) from hulls_before_0127), (select count(*) from bonus_before_0127), (select count(*) from progress_before_0127),
    v_seed_n, round(v_seed_xp, 1), v_seed_o, (select companies from npc_seed_0127), (select ms from npc_seed_0127), coalesce(v_lvls, 'none'),
    v_read_ms, (select ms from reads_before_0127), v_settle_p, v_settle_m, v_lit_n, v_lit_b;
end $$;
