-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0485 - A FLEET THAT GROWS TO FIVE SHIPS  (dark: the owner's switch ship_roles_enabled, false; lit, her third to fifth hulls each open a
--        ROLE, a tag on the hull: a GUARD (a pirate hunting her waters must come closer to strike the fleet it sails with), a FAST hull
--        (+10 % speed: her jobs and contracts run sooner) and a BIG HOLD (+20 % cargo for the route). One press sets it on HQ's fleet row;
--        HQ's board names the best role for a new hull and the yard's card the role the next hull should fill; the goal card walks her up
--        the ladder: ships, then routes, then captains)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE DESIGN: docs/design/roadmap-2026-11-23.md slice 17 ("A fleet that grows to five ships"); docs/design/hq-command-2026-11-23.md (every
--   activity in HQ); docs/dev-log/2026-11-23-ship-roles.md.
--
-- WHY: the owner, 2026-11-23: "i want this game to be strategical game, where all the work(acitivities) are done in HQ - words with
--   graphics. choosing best options available, finding best options." Slice 17: "the third to fifth ships each open a role (a guard ship
--   that lowers raid odds, a fast ship for hold jobs, a big hold for the route), and the goal card walks her up the ladder (ships, routes,
--   captains). Uses room, armadas and convoys that exist."
--
-- WHAT (DECIDED BY DEFAULT; the owner may reverse any of it; every figure is a knob):
--   A ROLE IS A HULL TAG: public.ships.role ('guard' | 'fast' | 'hold' | null), a new nullable column (no default: no row is rewritten).
--     It stays with the hull whatever fleet she sails in. Only a company sets one (the door below), so every merchant, navy, pirate and
--     cargo hull is null for ever.
--   THE SLOTS: her ships beyond ship_roles_free_from - 1 (2) each open one, up to the three roles (ship_roles_fleet_max (5) ships: three
--     slots). Any hull may take any role; a role may repeat. Two ships: no slot, and the yard's card says what the third will be.
--   THE EFFECTS, each through the ONE place that already decides the thing (no second formula):
--     FAST  public.ship_base (THE one place a class meets a hull, 0276; one hunk): her speed x (1 + ship_roles_fast_pct (0.10)). Every
--           speed, ETA, trip quote, job plan and contract window reads it from there (voyage.ship_speed_parts -> world.ship_stats).
--     HOLD  public.ship_base (the same hunk): her hold x (1 + ship_roles_hold_pct (0.20)), floored as before. Every capacity, free hold
--           and buy cap reads it from there (public.ship_hold_capacity -> world.ship_stat 'hold').
--     GUARD public.raid_target (0427's choice of the merchant a hunting pirate sets upon; three hunks): a fleet with a guard hull aboard,
--           or sailing in an armada with one, has her miles weighed by ship_roles_guard_weight (2): she is struck only within half the
--           pirate's reach (a quarter of the water), and a nearer unguarded merchant is set upon first. The anonymous PIRATES day of a
--           voyage (voyage.hazard_roll) is NOT changed: it is a pure function of (voyage, day, secret) and must stay one.
--     A null role reads neither knob: `case when s.role = ...` is false and the expression is the pre-image's times 1.
--   ONE PRESS: cmd.set_ship_role(ship, role) (role null or '' takes it off). Her hull, her fleet in port (public.fleet_state 'port'), a
--     slot free for an untagged hull; a hull that would be over her hold after the change is refused (E_HOLD_FULL). Refusals: the envelope.
--   THE BEST ROLE (public.ship_role_pick): the role she has fewest of; among those, the one her own play asks most: GUARD by the raids her
--     fleets were in (the RAID battles still kept, raid_keep_hours), FAST by her standing jobs and carried contracts, HOLD by her standing
--     routes; ties guard, fast, hold. Its hull (public.ship_role_best_ship): her untagged hull in port with the most attack (guard), the
--     most speed (fast) or the most hold (hold), then by id.
--   HQ'S BOARD (public.hq_board_for, three hunks): a ROLE card (band 0, beside the yard) "Make <hull> a <role>" with the reason and the
--     gain, whose act is cmd.set_ship_role, while a slot is free (public.ship_role_moves); the yard's card stands until she has
--     ship_roles_fleet_max hulls (public.ship_roles_build_below; dark hq_board_build_below, as before) and carries `role`, what the next
--     hull should be (public.ship_role_yard). Dark: the moves as they were.
--   THE READ world.ship_roles() (STABLE, registered): dark {"on": false}; signed out {"on": true, "company": false}; lit her slots, each
--     hull's role, the pick, the next hull's role, the gains and THE LADDER (public.ship_role_ladder): ships (her hulls of
--     ship_roles_fleet_max), then routes (her fleets working by themselves: a standing route or job), then captains (her fleets with a
--     captain seated); the first step not done is the goal card's line.
-- ONE AUTHORITY EACH: the switch public.ship_roles_on; a role's factor public.ship_role_mult (read by public.ship_base alone); the guard
--   public.ship_role_guard (read by public.raid_target alone); the slots public.ship_role_slots; the pick public.ship_role_pick; the ladder
--   public.ship_role_ladder; the setter public.ship_role_set_for.
-- NOT CHANGED: any hull with no role (every hull today), a merchant, the hazard roll, the fight, the price of anything, anyone while dark.
-- ROWS. Dark: none. Lit: one ships row updated a press. No table, no cron job, no beat step.
-- COST. Dark: public.raid_target reads one knob a call (the pirates' minute job, at most pirate_strike_tries_per_run (8) calls a minute);
--   the board one knob read; public.ship_base nothing (a null role is not looked up). Lit: public.ship_base two knob reads for a TAGGED hull
--   only; raid_target one indexed probe of ships by fleet a candidate; a board or role read a handful of indexed reads of her own rows.
--   Nothing on the arrivals beat that was not there.
-- LOCKS: ALTER TABLE public.ships ADD COLUMN (nullable, no default: a catalog change under a brief ACCESS EXCLUSIVE, no rewrite) with its
--   CHECK (a scan of public.ships under that lock); CREATE FUNCTION x14; CREATE OR REPLACE x4 by hunks (public.ship_base,
--   public.raid_target, public.hq_board_for, public.client_rpc_entry_points); six knobs. TIME: a second. BUDGET: statement_timeout 60 s,
--   lock_timeout 5 s; fails above 45 s.
-- ROLLBACK (forward, owner only): QUICK, ship_roles_enabled false (every factor is 1, no guard is read, the board is its pre-image's, the
--   door refuses, the read is {"on": false}; the tags stay, inert). Full: a new migration reversing the eight hunks (OLD texts below
--   verbatim), dropping the functions, the column and the knobs.
-- SELF-ASSERT: the hunks once each and reversing; no other function moved; the hunked bodies' grants, volatility, definer, search path and
--   owner unmoved; the knobs; the reads STABLE; cmd.set_ship_role and world.ship_roles registered for authenticated alone; every core
--   server only (service_role too: prod's default ACL grants it). THE PROBE (rolled back; deterministic: no time-budgeted read is asked
--   (public.hq_board_for and world.best_sales never: the role card is asked of public.ship_role_moves), every comparison of two figures is
--   one SELECT, no clock is read): DARK the door refuses, the read is {"on": false}, no card, no yard role, the yard's ships-below is the
--   knob's, and a hull tagged by hand sails, holds and is guarded exactly as untagged; LIT two hulls no slot, a third one slot; a big hold
--   holds x1.2 and a fast hull sails x1.1 (her own ship_base against the class x her roll, one SELECT); a second tag refused for the slot;
--   off port refused; a guard weighs her fleet 2 and an armada mate 2, another fleet 1; a hold too full to lose its tag refused; the card
--   names the pick and its act; the ladder says ships 3 of 5. Proof 188 plays it further (raid_target itself, the board).
-- VERSION: 0485 = 0484 + 1 (prod head 0484; the board's and the registry's hunks are anchored on 0483's and 0484's own lines).
-- news: none (dark: nothing changes for a player until the owner lights ship_roles_enabled)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

set local statement_timeout = '60s';
set local lock_timeout = '5s';

-- ── 0. GUARD, AND THE PRE-IMAGE (every function this file does not hunk or create: it must not move) ──
do $g$
begin
  if exists (select 1 from public.world_config where key = 'ship_roles_enabled')
     or exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'ships' and column_name = 'role') then
    raise exception '0485 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.hq_board_for(uuid)') is null or to_regprocedure('public.nation_race_marks(uuid,jsonb)') is null
     or to_regprocedure('public.courier_moves(uuid,bigint)') is null or to_regprocedure('public.raid_target(uuid,timestamp with time zone)') is null
     or to_regprocedure('public.ship_base(uuid)') is null or to_regprocedure('public.fleet_state(uuid)') is null
     or to_regclass('public.fleet_jobs') is null or to_regclass('public.courier_contracts') is null or to_regclass('public.armada_fleets') is null then
    raise exception '0485 refuses: 0484, 0483, 0481, 0480, 0448, 0427, 0367 or 0276 is not in this world';
  end if;
  create temp table pre_0485 on commit drop as
    select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text)) as fns,
           (select md5(string_agg(q.oid::regprocedure::text || ':' || coalesce(q.proacl::text, '') || ':' || q.provolatile::text || q.prosecdef::text || coalesce(q.proconfig::text, '') || ':' || q.proowner::text, ',' order by q.oid::regprocedure::text))
              from pg_proc q
             where q.oid in ('public.ship_base(uuid)'::regprocedure, 'public.raid_target(uuid,timestamp with time zone)'::regprocedure,
                             'public.hq_board_for(uuid)'::regprocedure, 'public.client_rpc_entry_points()'::regprocedure)) as meta
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
       and p.oid not in ('public.ship_base(uuid)'::regprocedure, 'public.raid_target(uuid,timestamp with time zone)'::regprocedure,
                         'public.hq_board_for(uuid)'::regprocedure, 'public.client_rpc_entry_points()'::regprocedure);
  -- a hull's base as it is, kept for the probe's comparisons (a pg_temp copy, gone with the session)
  execute replace(replace(pg_get_functiondef('public.ship_base(uuid)'::regprocedure), E'\r', ''),
                  'FUNCTION public.ship_base(', 'FUNCTION pg_temp.ship_base_pre_0485(');
end
$g$;

-- ── 1. THE KNOBS ──
insert into public.world_config (key, value, description) values
  ('ship_roles_enabled', 'false'::jsonb,
   '0485: THE SWITCH (the owner''s). true: a company''s hulls beyond the second each open a role (guard, fast, big hold) set in one press on HQ (cmd.set_ship_role); a fast hull sails and a big hold holds more (public.ship_base), a guard keeps hunting pirates further off the fleet it sails with (public.raid_target); HQ''s board names the best role and the yard the next hull''s; world.ship_roles() serves the slots and the ladder. false: no factor, no guard, the board as before, the door refuses, the read is {"on": false}.'),
  ('ship_roles_guard_weight', to_jsonb(2), '0485: a fleet with a guard hull (or in an armada with one) has her miles from a hunting pirate weighed by this (public.ship_role_guard, read by public.raid_target): 2 = struck only within half the reach.'),
  ('ship_roles_fast_pct', to_jsonb(0.10), '0485: a fast hull''s speed is (1 + this) times her own (public.ship_base).'),
  ('ship_roles_hold_pct', to_jsonb(0.20), '0485: a big hold holds (1 + this) times her own, floored (public.ship_base).'),
  ('ship_roles_fleet_max', to_jsonb(5), '0485: the ladder''s ships step (her hulls of this many), and lit, the yard''s card stands until she has this many.'),
  ('ship_roles_free_from', to_jsonb(3), '0485: her hull number this opens the first role slot; each further hull one more, up to the three roles.');

-- ── 2. THE TAG ──
alter table public.ships add column role text constraint ships_role_check check (role in ('guard', 'fast', 'hold'));
comment on column public.ships.role is
  '0485: the hull''s role (null, guard, fast, hold), set by public.ship_role_set_for alone (cmd.set_ship_role). Read by public.ship_base (fast, hold) and public.ship_role_guard (guard), only while ship_roles_enabled.';

-- ── 3. THE FUNCTIONS ──
create function public.ship_roles_on() returns boolean
language sql stable security definer set search_path = public, pg_temp as $body$
  -- 0485: THE SWITCH, the one reading of it
  select coalesce(public.wc('ship_roles_enabled') = 'true'::jsonb, false)
$body$;

create function public.ship_role_mult(p_role text) returns numeric
language sql stable security definer set search_path = public, pg_temp as $body$
  -- 0485: A ROLE'S FACTOR on the stat it moves (read by public.ship_base alone, and only for a hull whose role is that one): fast her speed,
  -- hold her hold. 1 while dark, so a tag left behind changes nothing.
  select case when not public.ship_roles_on() then 1::numeric
              when p_role = 'fast' then 1 + greatest(0, public.wc_num('ship_roles_fast_pct'))
              when p_role = 'hold' then 1 + greatest(0, public.wc_num('ship_roles_hold_pct'))
              else 1::numeric end
$body$;

create function public.ship_role_guard(p_fleet uuid) returns numeric
language sql stable security definer set search_path = public, pg_temp as $body$
  -- 0485: THE GUARD (read by public.raid_target alone): ship_roles_guard_weight when a guard hull with a hull left sails in this fleet, or
  -- in a fleet of her armada (they sail as one, 0367); else 1. 1 while dark.
  select case when public.ship_roles_on()
                   and exists (select 1 from public.ships s
                                where s.role = 'guard' and s.durability > 0
                                  and (s.fleet_id = p_fleet
                                       or s.fleet_id in (select m.fleet_id from public.armada_fleets a
                                                           join public.armada_fleets m on m.armada_id = a.armada_id
                                                          where a.fleet_id = p_fleet)))
              then greatest(1, public.wc_num('ship_roles_guard_weight')) else 1::numeric end
$body$;

create function public.ship_role_slots(p_player uuid) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $body$
  -- 0485: HER SLOTS: her hulls, the slots they open (each hull from ship_roles_free_from on, up to the three roles), the tags set, and each
  -- role's count.
  select jsonb_build_object(
           'ships', x.n,
           'slots', least(3, greatest(0, x.n - (public.wc_int('ship_roles_free_from') - 1))),
           'used', x.used, 'guard', x.g, 'fast', x.f, 'hold', x.h)
    from (select count(*)::int as n, count(s.role)::int as used,
                 (count(*) filter (where s.role = 'guard'))::int as g,
                 (count(*) filter (where s.role = 'fast'))::int as f,
                 (count(*) filter (where s.role = 'hold'))::int as h
            from public.ships s where s.player_id = p_player) x
$body$;

create function public.ship_role_pick(p_player uuid) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $body$
-- 0485: THE BEST ROLE FOR HER NEXT HULL: the role she has fewest of; among those the one her own play asks most (guard: the raids her
-- fleets were in, the RAID battles still kept; fast: her standing jobs and the contracts she carries; hold: her standing routes); ties
-- guard, fast, hold. {role, why, n}. Writes nothing.
declare
  v_s      jsonb := public.ship_role_slots(p_player);
  v_raids  int;
  v_jobs   int;
  v_routes int;
begin
  select count(distinct b.id) into v_raids
    from public.fleets f join public.battle_sides bs on bs.fleet_id = f.id join public.battles b on b.id = bs.battle_id and b.kind = 'RAID'
   where f.player_id = p_player;
  v_jobs := (select count(*) from public.fleet_jobs j where j.player_id = p_player)
          + (select count(*) from public.courier_contracts c where c.carrier_id = p_player and c.status = 'taken');
  v_routes := (select count(*) from public.standing_routes r where r.player_id = p_player);
  return (select jsonb_build_object('role', r.role, 'why', r.why, 'n', r.n)
            from (values ('guard', 'raids', v_raids, (v_s->>'guard')::int, 1),
                         ('fast', 'jobs', v_jobs, (v_s->>'fast')::int, 2),
                         ('hold', 'routes', v_routes, (v_s->>'hold')::int, 3)) r(role, why, n, have, ord)
           order by r.have, r.n desc, r.ord
           limit 1);
end
$body$;

create function public.ship_role_best_ship(p_player uuid, p_role text) returns uuid
language sql stable security definer set search_path = public, pg_temp as $body$
  -- 0485: THE HULL FOR A ROLE: her untagged hull with a hull left, whose fleet lies in port (public.fleet_state, the one rule), with the most
  -- attack (guard), speed (fast) or hold (hold), then by id. Null: none.
  select s.id
    from public.ships s
    join public.ship_classes c on c.id = s.class_id
   cross join lateral public.ship_base(s.id) sb
   where s.player_id = p_player and s.role is null and s.durability > 0 and s.fleet_id is not null
     and public.fleet_state(s.fleet_id) = 'port'
   order by case p_role when 'guard' then c.attack::numeric when 'fast' then sb.speed when 'hold' then sb.hold end desc nulls last, s.id
   limit 1
$body$;

create function public.ship_role_gain(p_role text) returns numeric
language sql stable security definer set search_path = public, pg_temp as $body$
  -- 0485: WHAT A ROLE GIVES, as the card and the read say it: the guard's weight, the fast hull's and the big hold's share
  select case p_role when 'guard' then public.wc_num('ship_roles_guard_weight')
                     when 'fast' then public.wc_num('ship_roles_fast_pct')
                     when 'hold' then public.wc_num('ship_roles_hold_pct') end
$body$;

create function public.ship_role_moves(p_player uuid) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $body$
-- 0485: HQ'S ROLE CARD (public.hq_board_for, one hunk): while a slot is free, "make <hull> a <role>": the pick, its hull, the reason and the
-- gain, committed by cmd.set_ship_role in one press. Band 0, beside the yard. '[]' dark, with no free slot or no hull in port.
declare
  v_s    jsonb;
  v_pick jsonb;
  v_ship uuid;
  r      record;
begin
  if p_player is null or not public.ship_roles_on() then
    return '[]'::jsonb;
  end if;
  v_s := public.ship_role_slots(p_player);
  if (v_s->>'used')::int >= (v_s->>'slots')::int then
    return '[]'::jsonb;
  end if;
  v_pick := public.ship_role_pick(p_player);
  v_ship := public.ship_role_best_ship(p_player, v_pick->>'role');
  if v_ship is null then
    return '[]'::jsonb;
  end if;
  select s.id, coalesce(s.name, f.name) as ship_name, c.code as class_code, f.id as fid, f.name as fname, p.code as at into r
    from public.ships s join public.fleets f on f.id = s.fleet_id join public.ship_classes c on c.id = s.class_id
    left join public.ports p on p.id = f.port_id
   where s.id = v_ship;
  return jsonb_build_array(jsonb_build_object(
    'id', format('role:%s:%s', r.id, v_pick->>'role'), 'kind', 'role', 'band', 0,
    'fleet', r.fid, 'fleet_name', r.fname, 'at', r.at,
    'score', null, 'profit', null, 'seconds', null, 'risk', null,
    'needs', jsonb_build_object('ship', r.id, 'ship_name', r.ship_name, 'hull', r.class_code, 'role', v_pick->>'role',
                                'why', v_pick->>'why', 'n', (v_pick->>'n')::int, 'gain', public.ship_role_gain(v_pick->>'role'),
                                'slots', (v_s->>'slots')::int, 'used', (v_s->>'used')::int),
    'act', jsonb_build_object('rpc', 'cmd.set_ship_role', 'args', jsonb_build_object('ship', r.id, 'role', v_pick->>'role'))));
end
$body$;

create function public.ship_role_next(p_player uuid) returns text
language sql stable security definer set search_path = public, pg_temp as $body$
  -- 0485: THE ROLE HER NEXT HULL SHOULD FILL: the pick, when that hull opens a slot (her hulls + 1 >= ship_roles_free_from) and the ladder
  -- still wants ships; else null. Null while dark.
  select case when public.ship_roles_on()
                   and (x.s->>'ships')::int + 1 >= public.wc_int('ship_roles_free_from')
                   and (x.s->>'ships')::int < public.wc_int('ship_roles_fleet_max')
              then public.ship_role_pick(p_player)->>'role' end
    from (select public.ship_role_slots(p_player) as s) x
$body$;

create function public.ship_role_yard(p_player uuid) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $body$
  -- 0485: WHAT THE YARD'S CARD ADDS (public.hq_board_for, one hunk): {"role": <the next hull's>}, or '{}' (dark, or no role to name)
  select coalesce((select jsonb_build_object('role', n.r) from (select public.ship_role_next(p_player) as r) n where n.r is not null), '{}'::jsonb)
$body$;

create function public.ship_roles_build_below() returns integer
language sql stable security definer set search_path = public, pg_temp as $body$
  -- 0485: THE YARD'S CARD STANDS WHILE SHE HAS FEWER HULLS THAN THIS (public.hq_board_for, one hunk): lit ship_roles_fleet_max (the ladder's
  -- five); dark hq_board_build_below, exactly the pre-image's expression.
  select case when public.ship_roles_on() then public.wc_int('ship_roles_fleet_max')
              else coalesce(public.wc_int('hq_board_build_below'), 2) end
$body$;

create function public.ship_role_ladder(p_player uuid) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $body$
  -- 0485: THE LADDER (the goal card's line): ships (her hulls of ship_roles_fleet_max), then routes (her fleets with a hull working by
  -- themselves: a standing route or a standing job), then captains (her fleets with a hull and a captain seated). `step` is the first not
  -- done (null: all done), with its `have` and `of`.
  select jsonb_build_object(
           'step', case when x.ships < x.max then 'ships' when x.routes < x.fleets then 'routes' when x.capt < x.fleets then 'captains' end,
           'have', case when x.ships < x.max then x.ships when x.routes < x.fleets then x.routes when x.capt < x.fleets then x.capt end,
           'of', case when x.ships < x.max then x.max when x.routes < x.fleets or x.capt < x.fleets then x.fleets end,
           'ships', jsonb_build_object('have', x.ships, 'of', x.max),
           'routes', jsonb_build_object('have', x.routes, 'of', x.fleets),
           'captains', jsonb_build_object('have', x.capt, 'of', x.fleets))
    from (select (select count(*) from public.ships s where s.player_id = p_player)::int as ships,
                 public.wc_int('ship_roles_fleet_max') as max,
                 (select count(*) from public.fleets f where f.player_id = p_player and exists (select 1 from public.ships s where s.fleet_id = f.id))::int as fleets,
                 (select count(*) from public.fleets f
                   where f.player_id = p_player and exists (select 1 from public.ships s where s.fleet_id = f.id)
                     and (exists (select 1 from public.standing_routes r where r.fleet_id = f.id)
                          or exists (select 1 from public.fleet_jobs j where j.fleet_id = f.id)))::int as routes,
                 (select count(*) from public.fleets f
                   where f.player_id = p_player
                     and exists (select 1 from public.captain_seats cs join public.ships s on s.id = cs.ship_id where s.fleet_id = f.id))::int as capt) x
$body$;

create function public.ship_role_set_for(p_player uuid, p_ship uuid, p_role text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $body$
-- 0485: THE CORE OF cmd.set_ship_role (server only): set her hull's role, or take it off (null or ''). Her hull; her fleet in port; a slot
-- free for an untagged hull; a hull that would hold more than her hold after the change is refused, and the tag stays as it was. Refusals
-- raise 'E_CODE: sentence' (the door makes the envelope). Writes the one ships row.
declare
  s       public.ships%rowtype;
  v_role  text := nullif(lower(btrim(coalesce(p_role, ''))), '');
  v_slots jsonb;
  v_cap   numeric;
  v_load  numeric;
begin
  if not public.ship_roles_on() then
    perform cmd.refuse('E_NOT_IN_USE', 'ship roles are not open yet');
  end if;
  if v_role is not null and v_role not in ('guard', 'fast', 'hold') then
    perform cmd.refuse('E_BAD_ORDER', 'a role is guard, fast or hold');
  end if;
  select * into s from public.ships x where x.id = p_ship for update;
  if s.id is null or s.player_id is distinct from p_player then
    perform cmd.refuse('E_NO_SUCH_SHIP', 'that ship is not yours');
  end if;
  if s.fleet_id is null or public.fleet_state(s.fleet_id) is distinct from 'port' then
    perform cmd.refuse('E_NOT_DOCKED', format('%s must lie in port to change her role', coalesce(s.name, 'she')));
  end if;
  if s.role is not distinct from v_role then
    return jsonb_build_object('ok', true, 'ship', s.id, 'role', v_role, 'was', s.role);
  end if;
  if s.role is null then
    v_slots := public.ship_role_slots(p_player);
    if (v_slots->>'used')::int >= (v_slots->>'slots')::int then
      perform cmd.refuse('E_NO_ROLE_SLOT', format('each ship from the %s on opens a role: %s of %s are set',
                                                  public.wc_int('ship_roles_free_from'), v_slots->>'used', v_slots->>'slots'));
    end if;
  end if;
  update public.ships set role = v_role where id = s.id;
  v_cap := public.ship_hold_capacity(s.id);
  v_load := public.ship_cargo_tuns(s.id) + public.stores_in_hold(s.water_t + s.food_t);
  if v_load > v_cap then
    update public.ships set role = s.role where id = s.id;
    perform cmd.refuse('E_HOLD_FULL', format('she carries %s tons and would hold %s; unload first', round(v_load), floor(v_cap)));
  end if;
  return jsonb_build_object('ok', true, 'ship', s.id, 'role', v_role, 'was', s.role);
end
$body$;

create function cmd.set_ship_role(p_ship uuid, p_role text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $body$
-- 0485: GIVE HER HULL A ROLE (guard | fast | hold), or take it off (null or ''); public.ship_role_set_for. A refusal is the envelope.
declare
  v_player uuid := public.current_player_id();
  v_det    text;
begin
  if v_player is null or coalesce((select p.is_npc from public.players p where p.id = v_player), true) then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_HOUSE', 'error_message', 'Found a house first.', 'fixes', '[]'::jsonb);
  end if;
  begin
    return public.ship_role_set_for(v_player, p_ship, p_role);
  exception when others then
    if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
    get stacked diagnostics v_det = pg_exception_detail;
    return cmd.refused_envelope(sqlerrm, v_det);
  end;
end
$body$;

create function world.ship_roles() returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $body$
-- 0485: HER HULLS' ROLES (dark {"on": false}; signed out or a merchant {"on": true, "company": false}): her slots, each hull's role and
-- whether it can change now (her fleet in port), the pick for a new hull, the role the next hull should fill, the gains, and the ladder.
-- A read: asked when HQ or the goal card opens and after a press, never on the beat.
declare
  v_player uuid := public.current_player_id();
begin
  if not public.ship_roles_on() then
    return '{"on": false}'::jsonb;
  end if;
  if v_player is null or coalesce((select p.is_npc from public.players p where p.id = v_player), true) then
    return '{"on": true, "company": false}'::jsonb;
  end if;
  return jsonb_build_object('on', true, 'company', true)
    || public.ship_role_slots(v_player)
    || jsonb_build_object(
         'max', public.wc_int('ship_roles_fleet_max'),
         'free_from', public.wc_int('ship_roles_free_from'),
         'gain', jsonb_build_object('guard', public.ship_role_gain('guard'), 'fast', public.ship_role_gain('fast'), 'hold', public.ship_role_gain('hold')),
         'hulls', coalesce((select jsonb_agg(jsonb_build_object('ship', s.id, 'fleet', s.fleet_id, 'name', coalesce(s.name, f.name), 'hull', c.code,
                                                                'role', s.role, 'can', public.fleet_state(s.fleet_id) = 'port')
                                             order by s.created_at, s.id)
                              from public.ships s join public.fleets f on f.id = s.fleet_id join public.ship_classes c on c.id = s.class_id
                             where s.player_id = v_player), '[]'::jsonb),
         'pick', public.ship_role_pick(v_player) || jsonb_build_object('ship', (select public.ship_role_best_ship(v_player, public.ship_role_pick(v_player)->>'role'))),
         'next', public.ship_role_next(v_player),
         'ladder', public.ship_role_ladder(v_player));
end
$body$;

revoke all on function public.ship_roles_on() from public, anon, authenticated, service_role;
revoke all on function public.ship_role_mult(text) from public, anon, authenticated, service_role;
revoke all on function public.ship_role_guard(uuid) from public, anon, authenticated, service_role;
revoke all on function public.ship_role_slots(uuid) from public, anon, authenticated, service_role;
revoke all on function public.ship_role_pick(uuid) from public, anon, authenticated, service_role;
revoke all on function public.ship_role_best_ship(uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.ship_role_gain(text) from public, anon, authenticated, service_role;
revoke all on function public.ship_role_moves(uuid) from public, anon, authenticated, service_role;
revoke all on function public.ship_role_next(uuid) from public, anon, authenticated, service_role;
revoke all on function public.ship_role_yard(uuid) from public, anon, authenticated, service_role;
revoke all on function public.ship_roles_build_below() from public, anon, authenticated, service_role;
revoke all on function public.ship_role_ladder(uuid) from public, anon, authenticated, service_role;
revoke all on function public.ship_role_set_for(uuid, uuid, text) from public, anon, authenticated, service_role;
revoke all on function cmd.set_ship_role(uuid, text) from public, anon;
grant execute on function cmd.set_ship_role(uuid, text) to authenticated;
revoke all on function world.ship_roles() from public, anon;
grant execute on function world.ship_roles() to authenticated;
comment on function cmd.set_ship_role(uuid, text) is
  '0485: give her hull a role (guard, fast, hold) or take it off (null). Dark E_NOT_IN_USE. Client door.';
comment on function world.ship_roles() is
  '0485: her hulls'' roles, slots, the pick for a new hull, the next hull''s role and the ladder (dark {"on": false}). A read. Client door.';

-- ── 4. THE HUNKS, THE SELF-ASSERT, THE PROBE ──
do $m$
declare
  c_hunked constant text[] := array['public.ship_base(uuid)', 'public.raid_target(uuid,timestamp with time zone)', 'public.hq_board_for(uuid)',
                                    'public.client_rpc_entry_points()'];
  c_new    constant text[] := array['public.ship_roles_on()', 'public.ship_role_mult(text)', 'public.ship_role_guard(uuid)', 'public.ship_role_slots(uuid)',
                                    'public.ship_role_pick(uuid)', 'public.ship_role_best_ship(uuid,text)', 'public.ship_role_gain(text)',
                                    'public.ship_role_moves(uuid)', 'public.ship_role_next(uuid)', 'public.ship_role_yard(uuid)',
                                    'public.ship_roles_build_below()', 'public.ship_role_ladder(uuid)', 'public.ship_role_set_for(uuid,uuid,text)',
                                    'cmd.set_ship_role(uuid,text)', 'world.ship_roles()'];
  c_ua     constant uuid := '00000000-0485-4000-8000-0000000000a1';
  v_t0        timestamptz := clock_timestamp();
  v_h         record;
  x           record;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_note      text := '';
  v_lived     boolean := false;
  v_lis       uuid;
  v_a         uuid;
  v_f1        uuid;
  v_f2        uuid;
  v_s1        uuid;
  v_s2        uuid;
  v_s3        uuid;
  v_arm       uuid;
  v_r         jsonb;
  v_moves     jsonb;
  v_good      text;
begin
  perform set_config('statement_timeout', '60s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── THE HUNKS (each occurs exactly once in the live body, and reverses) ──
  create temp table hunks_0485 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0485 values
  ('public.ship_base(uuid)', 1,
$h$  select floor(c.hold       * s.roll_hold),
         round(c.speed_kn   * s.roll_speed, 2),$h$,
$h$  -- 0485 (ship_roles_enabled): a big hold holds more and a fast hull sails faster (public.ship_role_mult; 1 dark; a hull with no role
  -- reads nothing: the case is false and the factor 1)
  select floor(c.hold       * s.roll_hold * case when s.role = 'hold' then public.ship_role_mult(s.role) else 1 end),
         round(c.speed_kn   * s.roll_speed * case when s.role = 'fast' then public.ship_role_mult(s.role) else 1 end, 2),$h$),
  ('public.raid_target(uuid,timestamp with time zone)', 1,
$h$  v_w     numeric := coalesce(public.wc_num('raid_company_weight'), 1);                        -- 0464: lit, a company's miles are weighed by this$h$,
$h$  v_w     numeric := coalesce(public.wc_num('raid_company_weight'), 1);                        -- 0464: lit, a company's miles are weighed by this
  v_roles boolean := public.ship_roles_on();                                                       -- 0485: lit, a guard hull weighs her fleet's miles$h$),
  ('public.raid_target(uuid,timestamp with time zone)', 2,
$h$              c.nm * case when v_lit and public.fleet_kind(c.id) = 'COMPANY' then v_w else 1 end, c.id$h$,
$h$              c.nm * case when v_lit and public.fleet_kind(c.id) = 'COMPANY' then v_w else 1 end
                   * case when v_roles then public.ship_role_guard(c.id) else 1 end, c.id   -- 0485: a guarded fleet is further off$h$),
  ('public.raid_target(uuid,timestamp with time zone)', 3,
$h$    if v_nm <= v_reach then$h$,
$h$    -- 0485 (ship_roles_enabled): a fleet with a guard (or in an armada with one) is struck only within reach / ship_roles_guard_weight
    if v_nm * (case when v_roles then public.ship_role_guard(r.id) else 1 end) <= v_reach then$h$),
  ('public.hq_board_for(uuid)', 1,
$h$  v_moves := v_moves || public.courier_moves(p_player, v_purse);$h$,
$h$  v_moves := v_moves || public.courier_moves(p_player, v_purse);

  -- 0485 (ship_roles_enabled): a free role slot: "make <hull> a <role>", the pick, one press (public.ship_role_moves); dark none
  v_moves := v_moves || public.ship_role_moves(p_player);$h$),
  ('public.hq_board_for(uuid)', 2,
$h$     and (select count(*) from public.ships sh where sh.player_id = p_player) < coalesce(public.wc_int('hq_board_build_below'), 2)$h$,
$h$     and (select count(*) from public.ships sh where sh.player_id = p_player) < public.ship_roles_build_below()   -- 0485: lit five; dark the knob as before$h$),
  ('public.hq_board_for(uuid)', 3,
$h$      v_moves := v_moves || jsonb_build_array(v_best);$h$,
$h$      v_moves := v_moves || jsonb_build_array(v_best || public.ship_role_yard(p_player));   -- 0485: lit, the role the next hull should fill$h$),
  ('public.client_rpc_entry_points()', 1,
$h$      ('world',       'nation_race',           ''),$h$,
$h$      ('world',       'nation_race',           ''),
      -- 0485: a hull's role (dark: the door E_NOT_IN_USE, the read {"on": false})
      ('cmd',         'set_ship_role',         'uuid, text'),
      ('world',       'ship_roles',            ''),$h$);

  for v_h in select h.fn from hunks_0485 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0485 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0485 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0485 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0485 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0485 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── SELF-ASSERT: the catalog, the knobs, the doors ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_new) u(q)))) is distinct from (select pre.fns from pre_0485 pre) then
    raise exception '0485 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(q.oid::regprocedure::text || ':' || coalesce(q.proacl::text, '') || ':' || q.provolatile::text || q.prosecdef::text || coalesce(q.proconfig::text, '') || ':' || q.proowner::text, ',' order by q.oid::regprocedure::text))
        from pg_proc q where q.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q))))
     is distinct from (select pre.meta from pre_0485 pre) then
    raise exception '0485 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked body moved';
  end if;
  if (select count(*) from pg_proc p
       where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_new) u(q)))
         and p.provolatile = 's') <> 13 then
    raise exception '0485 self-assert FAIL: a read is not STABLE (all but the setter and its door are reads)';
  end if;
  if public.wc('ship_roles_enabled') <> 'false'::jsonb or public.wc_num('ship_roles_guard_weight') <> 2 or public.wc_num('ship_roles_fast_pct') <> 0.10
     or public.wc_num('ship_roles_hold_pct') <> 0.20 or public.wc_int('ship_roles_fleet_max') <> 5 or public.wc_int('ship_roles_free_from') <> 3
     or (select count(*) from public.world_config c where c.key like 'ship\_roles\_%') <> 6 then
    raise exception '0485 self-assert FAIL: the knobs are not as written';
  end if;
  if (select count(*) from public.client_rpc_entry_points() e
       where (e.schema_name, e.function_name, e.arg_types) in (('cmd', 'set_ship_role', 'uuid, text'), ('world', 'ship_roles', ''))
         and e.fn is not null and has_function_privilege('authenticated', e.fn, 'execute') and not has_function_privilege('anon', e.fn, 'execute')) <> 2
     or exists (select 1 from unnest(c_new) u(q)
                 where u.q not in ('cmd.set_ship_role(uuid,text)', 'world.ship_roles()')
                   and (has_function_privilege('authenticated', u.q::regprocedure, 'execute') or has_function_privilege('anon', u.q::regprocedure, 'execute')
                        or has_function_privilege('service_role', u.q::regprocedure, 'execute')))
     or (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0485 self-assert FAIL: a door is not registered for authenticated alone, or a core is reachable by a client';
  end if;

  -- ── THE PROBE, rolled back by a raised sentinel (no time-budgeted read is asked; every comparison of two figures is one SELECT) ──
  begin
    select p.id into v_lis from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR';
    v_a := public.new_house(c_ua, 'Casa das Naus 0485', 'PRT');
    select f.id into v_f1 from public.fleets f where f.player_id = v_a;
    select s.id into v_s1 from public.ships s where s.fleet_id = v_f1;
    update public.fleets set status = 'DOCKED', port_id = v_lis where id = v_f1;
    v_f2 := public.form_fleet(v_a, 'Segunda 0485', v_lis);
    v_s2 := public.commission_ship(v_a, v_f2, 'barca', 'Segunda 0485', true, true);
    update public.fleets set status = 'DOCKED', port_id = v_lis where id = v_f2;
    perform cmd.assume_identity(c_ua);

    -- (a) DARK: the door refuses, the read is {"on": false}, no card, no yard role, the yard's ships-below the knob's; a hull tagged by hand
    -- holds, sails and is guarded exactly as untagged
    update public.ships set role = 'hold' where id = v_s1;
    update public.ships set role = 'guard' where id = v_s2;
    if world.ship_roles() is distinct from '{"on": false}'::jsonb
       or cmd.set_ship_role(v_s1, 'fast')->>'error_code' is distinct from 'E_NOT_IN_USE'
       or public.ship_role_moves(v_a) <> '[]'::jsonb or public.ship_role_yard(v_a) <> '{}'::jsonb
       or public.ship_roles_build_below() is distinct from coalesce(public.wc_int('hq_board_build_below'), 2)
       or public.ship_role_guard(v_f2) <> 1
       or exists (select 1 from public.ships s
                   cross join lateral public.ship_base(s.id) a cross join lateral pg_temp.ship_base_pre_0485(s.id) b
                   where s.id in (v_s1, v_s2) and (a.hold, a.speed, a.durability, a.crew_max, a.handling) is distinct from (b.hold, b.speed, b.durability, b.crew_max, b.handling)) then
      raise exception '0485 self-assert FAIL: dark, a role moved something (read %)', world.ship_roles();
    end if;
    update public.ships set role = null where id in (v_s1, v_s2);

    -- (b) LIT: two hulls, no slot; the third opens one
    update public.world_config set value = 'true'::jsonb where key = 'ship_roles_enabled';
    v_r := public.ship_role_set_for(v_a, v_s1, 'hold');
    raise exception 'unreachable';
  exception when sqlstate 'P0001' then
    if sqlerrm !~ '^E_NO_ROLE_SLOT:' then
      raise exception '0485 self-assert FAIL: lit with two hulls, a tag was not refused for the slot: %', sqlerrm;
    end if;
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0485 self-assert FAIL: the probe''s first half did not run';
  end if;
  v_lived := false;
  -- the first half's world is gone with its subtransaction (the sentinel above); the second builds it again
  begin
    select p.id into v_lis from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR';
    v_a := public.new_house(c_ua, 'Casa das Naus 0485', 'PRT');
    select f.id into v_f1 from public.fleets f where f.player_id = v_a;
    select s.id into v_s1 from public.ships s where s.fleet_id = v_f1;
    update public.fleets set status = 'DOCKED', port_id = v_lis where id = v_f1;
    v_f2 := public.form_fleet(v_a, 'Segunda 0485', v_lis);
    v_s2 := public.commission_ship(v_a, v_f2, 'barca', 'Segunda 0485', true, true);
    v_s3 := public.commission_ship(v_a, v_f2, 'barca', 'Terceira 0485', false, true);
    update public.fleets set status = 'DOCKED', port_id = v_lis where id = v_f2;
    update public.world_config set value = 'true'::jsonb where key = 'ship_roles_enabled';
    perform cmd.assume_identity(c_ua);

    v_r := world.ship_roles();
    if (v_r->>'ships')::int <> 3 or (v_r->>'slots')::int <> 1 or (v_r->>'used')::int <> 0
       or v_r->'ladder'->>'step' is distinct from 'ships' or (v_r->'ladder'->>'have')::int <> 3 or (v_r->'ladder'->>'of')::int <> 5
       or v_r->'pick'->>'role' is distinct from 'guard' or v_r->>'next' is distinct from 'guard'
       or public.ship_role_yard(v_a) is distinct from '{"role": "guard"}'::jsonb or public.ship_roles_build_below() <> 5 then
      raise exception '0485 self-assert FAIL: lit with three hulls, the read is not one slot, the pick guard and the ladder ships 3 of 5: %', v_r;
    end if;
    -- the card: the pick on her hull with the most attack (all barcas: the first by id), one press
    v_moves := public.ship_role_moves(v_a);
    if jsonb_array_length(v_moves) <> 1 or v_moves->0->>'kind' <> 'role' or v_moves->0->'needs'->>'role' <> 'guard'
       or v_moves->0->'act'->>'rpc' <> 'cmd.set_ship_role' or v_moves->0->'act'->'args'->>'role' <> 'guard'
       or (v_moves->0->'act'->'args'->>'ship')::uuid <> (select min(s.id::text)::uuid from public.ships s where s.player_id = v_a) then
      raise exception '0485 self-assert FAIL: the role card is not the pick on her first hull: %', v_moves;
    end if;

    -- (c) BIG HOLD x1.2 and FAST x1.1, against her class x her roll, one SELECT each
    v_r := cmd.set_ship_role(v_s1, 'hold');
    if not coalesce((v_r->>'ok')::boolean, false)
       or not exists (select 1 from public.ships s join public.ship_classes c on c.id = s.class_id cross join lateral public.ship_base(s.id) b
                       where s.id = v_s1 and b.hold = floor(c.hold * s.roll_hold * 1.20) and b.speed = round(c.speed_kn * s.roll_speed, 2)) then
      raise exception '0485 self-assert FAIL: a big hold does not hold x1.2: %', v_r;
    end if;
    -- a second tag: no slot
    if cmd.set_ship_role(v_s2, 'fast')->>'error_code' is distinct from 'E_NO_ROLE_SLOT' then
      raise exception '0485 self-assert FAIL: a second tag with one slot was not refused';
    end if;
    -- the same hull changes her role: fast (the slot is hers)
    v_r := cmd.set_ship_role(v_s1, 'fast');
    if not coalesce((v_r->>'ok')::boolean, false) or v_r->>'was' <> 'hold'
       or not exists (select 1 from public.ships s join public.ship_classes c on c.id = s.class_id cross join lateral public.ship_base(s.id) b
                       where s.id = v_s1 and b.speed = round(c.speed_kn * s.roll_speed * 1.10, 2) and b.hold = floor(c.hold * s.roll_hold)) then
      raise exception '0485 self-assert FAIL: a fast hull does not sail x1.1: %', v_r;
    end if;
    -- a big hold loaded past her own hold cannot lose the tag
    v_r := cmd.set_ship_role(v_s1, 'hold');
    select g.code into v_good from public.goods g where g.bulk > 0 order by g.bulk desc, g.code limit 1;
    update public.ships s set cargo = jsonb_build_object(v_good, ceil(public.ship_hold_capacity(s.id) / (select g.bulk from public.goods g where g.code = v_good))),
                              water_t = 0, food_t = 0
     where s.id = v_s1;
    if cmd.set_ship_role(v_s1, null)->>'error_code' is distinct from 'E_HOLD_FULL'
       or (select s.role from public.ships s where s.id = v_s1) is distinct from 'hold' then
      raise exception '0485 self-assert FAIL: a full big hold lost its tag';
    end if;
    update public.ships set cargo = '{}'::jsonb where id = v_s1;
    v_r := cmd.set_ship_role(v_s1, '');
    -- off port: refused
    update public.fleets set status = 'SAILING', port_id = null where id = v_f1;
    if cmd.set_ship_role(v_s1, 'guard')->>'error_code' is distinct from 'E_NOT_DOCKED'
       or cmd.set_ship_role(gen_random_uuid(), 'guard')->>'error_code' is distinct from 'E_NO_SUCH_SHIP'
       or cmd.set_ship_role(v_s3, 'admiral')->>'error_code' is distinct from 'E_BAD_ORDER' then
      raise exception '0485 self-assert FAIL: a hull at sea, not hers or a role that is none was not refused';
    end if;
    update public.fleets set status = 'DOCKED', port_id = v_lis where id = v_f1;

    -- (d) THE GUARD: her fleet 2, an armada mate 2, another fleet 1; dark again 1
    v_r := cmd.set_ship_role(v_s3, 'guard');
    insert into public.armadas (player_id, name, flagship_fleet_id) values (v_a, 'Armada 0485', v_f2) returning id into v_arm;
    if not coalesce((v_r->>'ok')::boolean, false) or public.ship_role_guard(v_f2) <> 2 or public.ship_role_guard(v_f1) <> 1 then
      raise exception '0485 self-assert FAIL: the guard does not weigh her fleet 2 and the other 1: %', v_r;
    end if;
    insert into public.armada_fleets (fleet_id, armada_id) values (v_f1, v_arm), (v_f2, v_arm);
    if public.ship_role_guard(v_f1) <> 2 or public.ship_role_moves(v_a) <> '[]'::jsonb then
      raise exception '0485 self-assert FAIL: an armada mate is not guarded, or a card stands with no slot free';
    end if;
    update public.world_config set value = 'false'::jsonb where key = 'ship_roles_enabled';
    if public.ship_role_guard(v_f1) <> 1 then
      raise exception '0485 self-assert FAIL: dark, the guard still weighs';
    end if;
    v_note := 'dark nothing; lit 3 hulls 1 slot, pick guard, ladder ships 3/5, hold x1.2, fast x1.1, a full hold kept its tag, guard 2 (armada 2)';

    -- (e) SIGNED OUT: no company
    update public.world_config set value = 'true'::jsonb where key = 'ship_roles_enabled';
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '{}', true);
    if world.ship_roles() is distinct from '{"on": true, "company": false}'::jsonb then
      raise exception '0485 self-assert FAIL: lit and signed out, the read is not {"on": true, "company": false}';
    end if;
    raise exception using errcode = 'ZX485', message = 'PROBE_ROLLBACK_0485';
  exception when sqlstate 'ZX485' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0485 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name like '% 0485' or p.auth_uid = c_ua)
     or exists (select 1 from public.ships s where s.role is not null)
     or public.wc('ship_roles_enabled') is distinct from 'false'::jsonb
     or public.current_player_id() is not null then
    raise exception '0485 self-assert FAIL: the probe left something behind';
  end if;

  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0485 self-assert FAIL: the file took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0485 self-assert ok: A FLEET THAT GROWS TO FIVE SHIPS (dark). % hunks once and reversing; grants and volatility unmoved; no other function moved; two doors registered for authenticated alone, every core server only; one column; six knobs (ship_roles_enabled false). Probe (rolled back): %. % ms.',
    (select count(*) from hunks_0485), v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
