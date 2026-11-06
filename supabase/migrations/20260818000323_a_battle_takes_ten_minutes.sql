-- ═══════════════════════════════════════════════════════════════════════════════
-- 0323 — A BATTLE TAKES TEN MINUTES: a fight is a row with a clock, and a ship in it stands still. DARK, PROBE ONLY
-- ═══════════════════════════════════════════════════════════════════════════════
-- Owner row 286, slice W10 of docs/WORLD_POWERS.md (section 5.2): *"if a fight is made in pacifics, it would need a longer time for the navy to defend ... how would we design this?"*
-- A battle takes `battle_seconds` real seconds. Nothing in this file lets a player attack anything: public.battle_open is no client door, it answers kind PROBE only, and `attack_enabled` is false.
-- The no-PvP law stands: a human defender is refused.
--
-- WHAT THIS FILE ADDS:
--   public.battles, public.battle_sides   A battle and who is on it. The sides are the one list of fleets: no fleet column on the battle, no seed column (the seed is the battle's id, round 1).
--   BATTLE in voyage_event_kinds, IN_BATTLE in fleets_status_check (with a check that such a fleet lies in a port or at an anchor).
--   voyage.hold            THE one writer of a hold: a BATTLE row on the voyage, recompute_eta, fleets.busy_until. A sailing fleet stays SAILING (voyage.assert_sailing_invariant).
--   voyage.hold_floor      Where the hold rows start in voyage_events.day_index.
--   voyage.hold_unserved   The part of a hold that has not yet passed at an instant: it is what stops the point.
--   voyage.holds_served    The holds of a voyage on the wire: {} with none, so a read of a voyage with no hold is byte for byte what it was.
--   voyage.fleet_hulls     A fleet as a side of a fight, cut from voyage.fight, which now composes it.
--   voyage.fight_round_line One round in words, cut from voyage.fight_resolve, which now composes it.
--   public.attack_on, public.battle_open, public.battle_words, public.battle_resolve, public.tick_battles, job byeharu-voyage:battles.
--
-- WHY NOT A PLAIN BATTLE ROW (the design's section 5.2 cannot work as written, and the row's plan is below):
--   voyage_events' key is (voyage_id, day_index) and every settled day already has a row, so a hold cannot take a day of its own. A delay also counts only from the NEXT day, and it counts whole at once:
--   voyage.progress_nm subtracts it, so a storm's point jumps back. A hold must do neither. So:
--   - A hold's row is at day_index voyage.hold_floor() + n, above any real day. Its payload is {delay_hours, from_day, held_from, held_until}; from_day is the day she was on.
--   - voyage.delay_before_day counts it from from_day on, so that day's end, each day after it and the arrival all move by exactly delay_hours (voyage.recompute_eta sums every row and needs no hunk).
--   - voyage.progress_nm adds back voyage.hold_unserved, so the point stands still while the hold runs and sails on from the same mile. Past held_until that term is 0.
--   - voyage.report_line prints from_day, not the row's index.
--   - voyage.settle runs BEFORE the hold, so no day boundary before the hold is left unsettled and none falls inside it. voyage.settle IS NOT TOUCHED by this file.
--
-- THE HUNKS, each occurs once and reverses to its pre-image: voyage.delay_before_day, voyage.progress_nm (2), voyage.report_line, voyage.fight, voyage.fight_resolve (2), cmd.divert, world.voyage_view (2),
--   world.sea_roster (2). 0321 hunks none of these. 0322 (W6) names voyage.settle, npc_tend_route and cargo_ship_step, none of them here; it was not pushed when this was cut, so its head must be re-read.
--
-- DARK IS BYTE-IDENTICAL: with no hold row the new terms are 0 or {} and no existing path takes a new branch. It costs each voyage.delay_before_day and voyage.progress_nm call one index probe of an empty
-- range, each roster row one more, and the job one read of a partial index a minute. Proof 31 compares the old bodies with the new on every voyage in the world.
--
-- CHECKED AGAINST THE HAND-OFF NOTES (2026-11-05, marked unchecked):
--   - cmd.divert did NOT refuse while busy_until is set: it reads no such thing. It does now (E_FLEET_BUSY), or a turn would cut a held voyage in two.
--   - The notes' job `0-6,8-33,41-59 * * * *` has no reason written anywhere in the repo, and it would leave a ten-minute battle up to 8 minutes late. It is `* * * * *`, as every minute job here.
--   - seaRoster.ts draws a merchant linearly from departure to eta, and a roster delta never re-serves a voyage whose eta moved. world.sea_roster now serves `holds` and re-serves a fleet with a busy_until.
--
-- DECIDED BY DEFAULT (owner may reverse):
--   - At time_compression 960 a 10-minute hold is 160 sim-hours, about 7 voyage days. As with a storm, those days stack at her arrival: stores drunk, wages owed, hazards rolled on each. A long battle costs a voyage that much.
--   - A fair wind may make up a hold's hours, as it makes up a storm's: it is bounded by voyage.delay_before_day, and a hold is a delay. A row of `arrival moves by the delay` is exact only until then.
--   - The battle's line in a voyage's report stands last, after the arrival days: it sorts by day_index, and re-sorting means a hunk in voyage.settle, which W6 is cutting. It reads its true day.
--   - No column for attacker, defender or seed on public.battles, against the design's sketch: a fact read two ways is two authorities.
--   - The fight writes hull on both sides in a probe, no crew, no gold, no goods, no regard: those are W11's table (section 4.3). A report says what the fight did and never promises loot.
--   - The report is written to a human ATTACKER only. A human defender is refused here; her voice comes with the first slice that lets one be attacked.
--   - An IN_BATTLE fleet whose flagship is at 0 comes out UNABLE_TO_SAIL, as voyage.settle's arrival arm says. That line is now in three bodies; a leaf belongs in the next slice that may cut voyage.settle.
--   - standing_route_state reads a fleet IN_BATTLE as 'blocked'. It is true while it lasts. Only a merchant at anchor in a probe could read it, and nothing opens a probe on prod.
--
-- SELF-ASSERT: the catalog only: hunks once and reversing; ACL, volatility and config unmoved; no other function, no existing knob, no row. THIS FILE RUNS NO GAME STEP, in every environment
-- (docs/OPS_HEALTH.md section 4). THE LIVE PATHS ARE PROVED IN CI: proof 31, scripts/db/proofs/31_battles.sql. Mutation controls: scripts/ops/harness/battles/proof-0323.mjs (local).
--
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 45 s, lock_timeout 5 s first. fleets_status_check is re-checked over public.fleets in it. Self-assert fails above 45 s.
-- ROLLBACK (forward, a NEW migration, owner only): `attack_enabled` false stops new battles and running ones finish. To remove: swap this file's old and new, unschedule the job, restore the check, drop what it created.
-- VERSION: 0323, after 0321 (#516) and 0322 (W6). Written against prod head 0320; shares no body with 0321. Prod head 0320 when cut.
-- ═══════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0   timestamptz := clock_timestamp();
  v_h    record;
  v_def  text;
  v_n    int;
  v_fn_before  text;
  v_cfg_before text;
  v_kinds_before text;
  v_meta_before  text;
  c_new_fns constant text[] := array[
    'public.attack_on()', 'voyage.hold_floor()', 'voyage.hold_unserved(uuid,integer,timestamp with time zone)', 'voyage.holds_served(uuid)',
    'voyage.hold(uuid,timestamp with time zone,timestamp with time zone)', 'voyage.fleet_hulls(uuid)', 'voyage.fight_round_line(jsonb,integer,text,jsonb,numeric,text)',
    'public.battle_open(text,uuid,uuid,timestamp with time zone)', 'public.battle_words(jsonb,jsonb)', 'public.battle_resolve(uuid,timestamp with time zone)',
    'public.tick_battles(timestamp with time zone)'];
  c_hunked constant text[] := array[
    'voyage.delay_before_day(uuid,integer)', 'voyage.progress_nm(uuid,timestamp with time zone)', 'voyage.report_line(integer,text,jsonb)',
    'voyage.fight(uuid,integer,uuid,numeric)', 'voyage.fight_resolve(uuid,integer,numeric,numeric,jsonb)', 'cmd.divert(uuid,uuid,jsonb,jsonb)',
    'world.voyage_view(uuid,boolean)', 'world.sea_roster(timestamp with time zone)'];
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regclass('public.battles') is not null or to_regprocedure('public.tick_battles(timestamp with time zone)') is not null
     or exists (select 1 from public.world_config c where c.key in ('battle_seconds', 'attack_enabled'))
     or exists (select 1 from public.voyage_event_kinds k where k.code = 'BATTLE') then
    raise exception '0323 refuses: something of it is already in this world';
  end if;
  if to_regprocedure('public.fight_sides(uuid,integer,jsonb,jsonb,jsonb)') is null then
    raise exception '0323 refuses: 0320 (public.fight_sides) is not in this world';
  end if;

  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked) x));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before
    from public.world_config c;
  select md5(string_agg(k.code || ':' || k.ordinal || ':' || k.prose, ',' order by k.code)) into v_kinds_before
    from public.voyage_event_kinds k;
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
    into v_meta_before
    from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked) x));

  -- ── 1. THE TABLES ──
  create table public.battles (
    id          uuid        primary key default gen_random_uuid(),
    kind        text        not null check (kind in ('PROBE')),
    site        jsonb       not null,
    started_at  timestamptz not null,
    resolves_at timestamptz not null,
    status      text        not null default 'FIGHTING' check (status in ('FIGHTING', 'RESOLVED', 'BROKEN_OFF')),
    result      jsonb,
    check (resolves_at > started_at)
  );
  comment on table public.battles is
    '0323 (docs/WORLD_POWERS.md 5.2): a timed battle. One writer: public.battle_open opens it, public.battle_resolve closes it, once. The fight is public.fight_sides seeded (battle id, 1); result is its answer. BROKEN_OFF has no writer before W11.';
  create index battles_due on public.battles (resolves_at) where status = 'FIGHTING';
  alter table public.battles enable row level security;
  revoke all on table public.battles from public, anon, authenticated;

  create table public.battle_sides (
    battle_id  uuid        not null references public.battles(id) on delete cascade,
    fleet_id   uuid        not null references public.fleets(id) on delete cascade,
    side       text        not null check (side in ('ATTACKER', 'DEFENDER')),
    joined_at  timestamptz not null,
    arrives_at timestamptz not null,
    primary key (battle_id, fleet_id)
  );
  comment on table public.battle_sides is
    '0323: who is in a battle, the one list. arrives_at is when a side is on the sheet; a reinforcement (W13) has it after joined_at, and in this file it is joined_at.';
  create index battle_sides_fleet on public.battle_sides (fleet_id);
  alter table public.battle_sides enable row level security;
  revoke all on table public.battle_sides from public, anon, authenticated;

  -- ── 2. THE STATUS: a fleet in port or at anchor; a sailing one stays SAILING ──
  alter table public.fleets drop constraint fleets_status_check,
    add constraint fleets_status_check check (status = any (array['DOCKED', 'ANCHORED', 'SAILING', 'REPAIRING', 'ADRIFT', 'UNABLE_TO_SAIL', 'IN_BATTLE'])),
    add constraint fleets_in_battle_lies_still check (status <> 'IN_BATTLE' or port_id is not null or lat is not null);

  -- ── 3. THE KNOBS AND THE KIND (all new; no existing key is touched) ──
  insert into public.world_config (key, value, description) values
    ('attack_enabled', 'false'::jsonb, '0323: THE switch of new battles. False: public.battle_open refuses E_NOT_YET. A battle already running finishes.'),
    ('battle_seconds', '600'::jsonb, '0323: how long a battle takes, in real seconds. Read when a battle opens, so a change never moves a running one.');
  insert into public.voyage_event_kinds (code, ordinal, prose, prose_keys, prose_fallbacks, is_rolled, in_sea_mix, note)
  select 'BATTLE', max(k.ordinal) + 1, 'We hove to and fought, and lost %s hours.', array['delay_hours'], array['some'], false, false,
         '0323. A CONDITION, never drawn: voyage.hold writes it when a sailing fleet is held by a battle. Its row stands above the voyage''s days (voyage.hold_floor), and its payload says what it held.'
    from public.voyage_event_kinds k;

  -- ── 4. THE LEAVES ──
  execute $f$
create function public.attack_on()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  select coalesce((public.wc('attack_enabled'))::text::boolean, false)
$body$;
$f$;

  execute $f$
create function voyage.hold_floor()
returns integer
language sql
immutable
as $body$
  -- 0323: where the hold rows start in voyage_events.day_index, above any day a voyage can have. Below it a row is that day's; at or above it, a hold's, and its payload's from_day is its day.
  select 1000000
$body$;
$f$;

  execute $f$
create function voyage.hold_unserved(p_voyage uuid, p_day integer, p_at timestamptz)
returns numeric
language sql
stable
as $body$
  -- 0323: THE HOURS OF THIS VOYAGE'S HOLDS NOT YET PASSED AT p_at, of the holds voyage.delay_before_day counts for p_day. voyage.progress_nm adds them back, so a hold stops the point instead of throwing it
  -- back: delay_hours whole at held_from, 0 at held_until, in step with the clock between. It reads the row's own two instants and no knob. Plain SQL, called from a definer's body and inlined there.
  select coalesce(sum((ve.payload->>'delay_hours')::numeric
                      * (1 - least(1, greatest(0, extract(epoch from p_at - (ve.payload->>'held_from')::timestamptz)
                                                  / nullif(extract(epoch from (ve.payload->>'held_until')::timestamptz - (ve.payload->>'held_from')::timestamptz), 0))))), 0)
    from public.voyage_events ve
   where ve.voyage_id = p_voyage and ve.day_index >= voyage.hold_floor() and (ve.payload->>'from_day')::int <= p_day
$body$;
$f$;

  execute $f$
create function voyage.holds_served(p_voyage uuid)
returns jsonb
language sql
stable
as $body$
  -- 0323: THE HOLDS OF A VOYAGE, as a read serves them: {holds: [{from, until}]}, or {} with none, so a voyage that was never held is served byte for byte as before. They let the client stand her still.
  select case when count(*) = 0 then '{}'::jsonb
              else jsonb_build_object('holds', jsonb_agg(jsonb_build_object('from', ve.payload->'held_from', 'until', ve.payload->'held_until') order by ve.day_index)) end
    from public.voyage_events ve
   where ve.voyage_id = p_voyage and ve.day_index >= voyage.hold_floor()
$body$;
$f$;

  execute $f$
create function voyage.hold(p_fleet uuid, p_until timestamptz, p_now timestamptz)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0323: HOLD A SAILING FLEET UNTIL p_until, the one writer. The hours are written as a delay on the voyage, the path a storm takes, so her position stays a pure function of the row and time (DESIGN D.2):
-- the row is voyage_events at voyage.hold_floor() + n, its payload {delay_hours, from_day, held_from, held_until}, and voyage.recompute_eta moves her eta. She stays SAILING; fleets.busy_until is her clock.
-- The caller has settled her to p_now (voyage.settle), so from_day is the day she is on and no boundary falls inside the hold: every day ahead moves by the whole hold, this one included.
declare
  v       public.voyages%rowtype;
  v_hours numeric;
begin
  select * into v from public.voyages where fleet_id = p_fleet and status = 'SAILING' for update;
  if v.id is null then
    raise exception 'E_NOT_SAILING: fleet % has no voyage to hold', p_fleet using errcode = 'P0001';
  end if;
  v_hours := trim_scale(round(extract(epoch from p_until - p_now) * public.wc_num('time_compression') / 3600, 4));
  insert into public.voyage_events (voyage_id, day_index, kind, payload, resolved_at)
  select v.id, voyage.hold_floor() + 1 + count(*)::int, 'BATTLE',
         jsonb_build_object('delay_hours', v_hours, 'from_day', v.last_settled_day + 1, 'held_from', p_now, 'held_until', p_until), p_now
    from public.voyage_events ve
   where ve.voyage_id = v.id and ve.day_index >= voyage.hold_floor();
  perform voyage.recompute_eta(v.id);
  update public.fleets set busy_until = p_until, version = version + 1 where id = p_fleet;
  return v.id;
end
$body$;
$f$;

  execute $f$
create function voyage.fleet_hulls(p_fleet uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0323: A FLEET AS A SIDE OF A FIGHT, as she is, cut from voyage.fight (0189), which composes it, as public.battle_resolve does. world.ship_stats, the one reading of a hull: her class, gear, company skills and
-- seated captains; her hull and crew. The share of a Boarder seated on each hull (public.crew_pct 'attack', K10's ship effect), the Boarder and the Gunner by name, and the gear that works on a PIRATES day
-- (item_use, 0158). Null for a fleet with no hull.
begin
  return (
    select jsonb_agg(jsonb_build_object(
             'id', s.id, 'name', s.name, 'tier', c.tier, 'hull', s.durability,
             -- 0276: her own rolled max — as a scalar subselect, because the jsonb_agg around this
             -- build_object is an aggregate and an aggregate cannot hold a set-returning call.
             'maxd', (select sb.durability from public.ship_base(s.id) sb), 'crew', s.crew,
             'attack', (x.st->>'attack')::numeric, 'accuracy', (x.st->>'accuracy')::numeric,
             'reach', (x.st->>'reach')::numeric, 'armour', (x.st->>'armour')::numeric,
             'sighting', (x.st->>'sighting')::numeric,
             'boarder_pct', public.crew_pct(p_fleet, s.id, 'attack'),
             'boarder', (select o.name from public.crew_terms(p_fleet) t join public.officers o on o.id = t.officer_id
                          where t.ship_id = s.id and t.effect = 'attack' and t.value_pct > 0
                          order by t.value_pct desc, o.name limit 1),
             'gunner', (select o.name from public.crew_terms(p_fleet) t join public.officers o on o.id = t.officer_id
                         where t.ship_id = s.id and t.effect in ('accuracy', 'reach') and t.value_pct > 0
                         order by t.value_pct desc, o.name limit 1),
             'gear', (select coalesce(jsonb_agg(distinct ik.name), '[]'::jsonb)
                        from public.fitted_units fu
                        join public.item_use iu on iu.item_code = fu.item_code and iu.trigger = 'PIRATES'
                        join public.item_kinds ik on ik.code = fu.item_code
                       where fu.ship_id = s.id))
           order by s.is_flagship desc, s.created_at, s.id)
      from public.ships s
      join public.ship_classes c on c.id = s.class_id
      cross join lateral (select world.ship_stats(s.id) as st) x
     where s.fleet_id = p_fleet);
end
$body$;
$f$;

  execute $f$
create function voyage.fight_round_line(p_round jsonb, p_g integer, p_first text, p_ships jsonb, p_foe_hull0 numeric, p_foe text)
returns text
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0323: ONE ROUND OF A FIGHT IN WORDS, cut from voyage.fight_resolve, which composes it, as public.battle_words does: the one telling of a round. p_round is a row of public.fight_sides' rounds with `a` the side
-- the report is written for; p_first YOU, THEY or BOTH; p_ships that side's hulls, for their names; p_foe_hull0 the other side's hull at the start; p_foe its word. Names no table.
declare
  v_a     jsonb := p_round->'a';
  v_b     jsonb := p_round->'b';
  h       jsonb;
  v_you   text;
  v_they  text;
  v_hit_on text;
  v_can   int := (v_a->>'can')::int;
  v_fired int := (v_a->>'fired')::int;
  v_hits  int := (v_a->>'hits')::int;
begin
  for h in select q.e from jsonb_array_elements(v_a->'struck') q(e) loop
    v_hit_on := coalesce(v_hit_on || ', ', '')
                || format('%s for %s%% damage', coalesce(p_ships->((h->>0)::int - 1)->>'name', 'Your ship'), h->>1);
  end loop;
  v_you := case when p_g = 1 and p_first = 'THEY' then 'you are caught unready'
                when v_can = 0 then 'you have no guns to answer with'
                when v_fired = 0 then 'your guns cannot reach them'
                when v_hits = 0 then format('you miss with %s shot%s', v_fired, case when v_fired = 1 then '' else 's' end)
                else format('you hit with %s of %s shot%s', v_hits, v_fired, case when v_fired = 1 then '' else 's' end) end;
  v_they := case when p_g = 1 and p_first = 'YOU' then 'they are caught unready'
                 when (v_b->>'fired')::int = 0 then 'their guns cannot reach you'
                 when (v_b->>'hits')::int = 0 then 'they miss'
                 else format('they hit %s', v_hit_on)
                      || case when (v_b->>'raw')::numeric > (v_b->>'dealt')::numeric + 0.005
                              then format(' (armour turned %s%%)', round((1 - (v_b->>'dealt')::numeric / (v_b->>'raw')::numeric) * 100)) else '' end end;
  return format('Round %s · %s range — %s; %s.', p_g, lower(p_round->>'range'), v_you, v_they)
         || case when v_hits > 0 then format(' The %s are %s%% damaged.', p_foe, round((1 - (v_b->>'left')::numeric / p_foe_hull0) * 100)) else '' end;
end
$body$;
$f$;

  -- ── 5. THE BATTLE ──
  execute $f$
create function public.battle_words(p_fight jsonb, p_ships jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0323: A BATTLE'S REPORT FOR THE ATTACKER, in the shape voyage.settle gives a voyage's: {lines[], fights[{line, rounds[]}]}, read by the History tray (payloadLines, payloadFights). p_fight is public.fight_sides'
-- answer, where a is the side set upon, so each round is turned round to read from the attacker's deck, and voyage.fight_round_line tells it. p_ships her hulls. Words of the outcome only: gold is W11's.
declare
  v_first text := case p_fight->>'first' when 'A' then 'THEY' when 'B' then 'YOU' else 'BOTH' end;
  v_hull0 numeric := greatest(1, coalesce((p_fight->'hull'->>'a_start')::numeric, 1));
  v_rounds text[] := '{}';
  v_line  text;
  x       jsonb;
  g       int;
begin
  v_line := case when p_fight->>'outcome' = 'NO_FIGHT' then 'There was no one left to fight.'
                 when (p_fight->>'stood_off')::boolean then 'We had nothing left to fight with.'
                 when (p_fight->>'slipped')::boolean then 'She saw us first and slipped away.'
                 when (p_fight->>'broke_off')::boolean then 'We broke off.'
                 when p_fight->>'outcome' = 'DRIVEN_OFF' then 'We came alongside and were thrown back.'
                 when p_fight->>'outcome' = 'RANSOM' then 'We came alongside and she offered terms.'
                 else 'We boarded her.' end;
  for g in 1 .. coalesce((p_fight->>'rounds_fought')::int, 0) loop
    x := p_fight->'rounds'->(g - 1);
    v_rounds := v_rounds || voyage.fight_round_line(jsonb_build_object('range', x->'range', 'a', x->'b', 'b', x->'a'), g, v_first, p_ships, v_hull0, 'enemy');
  end loop;
  return jsonb_build_object('lines', jsonb_build_array(v_line), 'fights', jsonb_build_array(jsonb_build_object('line', 0, 'rounds', to_jsonb(v_rounds))));
end
$body$;
$f$;

  execute $f$
create function public.battle_open(p_kind text, p_attacker uuid, p_defender uuid, p_now timestamptz default now())
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0323: OPEN A BATTLE, server side only: no client door, kind PROBE only, dark behind attack_enabled. Each fleet is settled first (an act must not reason about a stale position, D.2). A sailing fleet is held
-- (voyage.hold), one in port or at anchor goes IN_BATTLE and her orders wait in her queue, as in REPAIRING. Refuses a human defender (the no-PvP law) and a docked target. Each refusal is its own code.
declare
  a        public.fleets%rowtype;
  d        public.fleets%rowtype;
  v_until  timestamptz;
  v_site   jsonb;
  v_id     uuid;
  v_fleet  uuid;
begin
  if not public.attack_on() then
    raise exception 'E_NOT_YET: attack_enabled is off' using errcode = 'P0001';
  end if;
  if p_kind is distinct from 'PROBE' then
    raise exception 'E_BAD_KIND: % is not a kind of battle', coalesce(p_kind, '(null)') using errcode = 'P0001';
  end if;
  if p_attacker is not distinct from p_defender then
    raise exception 'E_BAD_TARGET: a fleet does not fight herself' using errcode = 'P0001';
  end if;
  foreach v_fleet in array array[least(p_attacker, p_defender), greatest(p_attacker, p_defender)] loop
    perform voyage.settle(v_fleet, p_now);
  end loop;
  select * into a from public.fleets where id = p_attacker for update;
  select * into d from public.fleets where id = p_defender for update;
  if a.id is null or d.id is null then
    raise exception 'E_NO_SUCH_FLEET: %', case when a.id is null then p_attacker else p_defender end using errcode = 'P0001';
  end if;
  if a.player_id = d.player_id then
    raise exception 'E_BAD_TARGET: % and % are one company', a.name, d.name using errcode = 'P0001';
  end if;
  if not (select p.is_npc from public.players p where p.id = d.player_id) then
    raise exception 'E_HUMAN_TARGET: no player fights another player' using errcode = 'P0001';
  end if;
  if d.status = 'DOCKED' then
    raise exception 'E_TARGET_DOCKED: % lies in port', d.name using errcode = 'P0001';
  end if;
  if a.status not in ('DOCKED', 'ANCHORED', 'SAILING') or d.status not in ('ANCHORED', 'SAILING')
     or a.busy_until is not null or d.busy_until is not null then
    raise exception 'E_FLEET_BUSY: % or % is not free to fight', a.name, d.name using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.ships s where s.fleet_id = p_attacker) or not exists (select 1 from public.ships s where s.fleet_id = p_defender) then
    raise exception 'E_NO_SHIPS: a fight needs at least one hull on each side' using errcode = 'P0001';
  end if;

  v_until := p_now + make_interval(secs => public.wc_num('battle_seconds')::double precision);
  v_site := case when d.status = 'SAILING'
                 then (select jsonb_build_object('lat', pos.lat, 'lon', pos.lon)
                         from public.voyages v cross join lateral voyage.position(v.id, p_now) pos
                        where v.fleet_id = p_defender and v.status = 'SAILING')
                 else jsonb_build_object('lat', d.lat, 'lon', d.lon) end;
  insert into public.battles (kind, site, started_at, resolves_at) values (p_kind, v_site, p_now, v_until) returning id into v_id;
  insert into public.battle_sides (battle_id, fleet_id, side, joined_at, arrives_at) values
    (v_id, p_attacker, 'ATTACKER', p_now, p_now), (v_id, p_defender, 'DEFENDER', p_now, p_now);
  foreach v_fleet in array array[p_attacker, p_defender] loop
    if (select f.status from public.fleets f where f.id = v_fleet) = 'SAILING' then
      perform voyage.hold(v_fleet, v_until, p_now);
    else
      update public.fleets set status = 'IN_BATTLE', busy_until = v_until, version = version + 1 where id = v_fleet;
    end if;
  end loop;
  return v_id;
end
$body$;
$f$;

  execute $f$
create function public.battle_resolve(p_battle uuid, p_now timestamptz default now())
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0323: RESOLVE A BATTLE, ONCE. Answers false, and does nothing, for a battle that is not due or not FIGHTING: the row's lock and its status are what make a retry harmless. One call of public.fight_sides,
-- every side present, seed (battle id, 1), a the side set upon. It writes what the fight did to the hulls, frees the fleets, runs the queue of each that was IN_BATTLE and reports to a human attacker.
declare
  b       public.battles%rowtype;
  s       record;
  v_a     jsonb := '[]'::jsonb;
  v_b     jsonb := '[]'::jsonb;
  v_h     jsonb;
  v_f     jsonb;
  v_was   text;
  v_rep   jsonb;
begin
  select * into b from public.battles where id = p_battle for update;
  if b.id is null or b.status <> 'FIGHTING' or b.resolves_at > p_now then
    return false;
  end if;

  for s in select bs.fleet_id, bs.side from public.battle_sides bs where bs.battle_id = p_battle order by bs.joined_at, bs.fleet_id loop
    v_h := coalesce(voyage.fleet_hulls(s.fleet_id), '[]'::jsonb);
    if s.side = 'DEFENDER' then v_a := v_a || v_h; else v_b := v_b || v_h; end if;
  end loop;
  v_f := case when jsonb_array_length(v_a) = 0 or jsonb_array_length(v_b) = 0 then jsonb_build_object('outcome', 'NO_FIGHT')
              else public.fight_sides(p_battle, 1, v_a, v_b) end;

  update public.ships sh set durability = greatest(0, sh.durability - l.lost)
    from (select x.key::uuid as id, x.value::numeric as lost from jsonb_each_text(coalesce(v_f->'hull_lost'->'a', '{}'::jsonb)) x
          union all
          select x.key::uuid, x.value::numeric from jsonb_each_text(coalesce(v_f->'hull_lost'->'b', '{}'::jsonb)) x) l
   where sh.id = l.id;
  update public.battles set status = 'RESOLVED', result = v_f where id = p_battle;

  for s in select bs.fleet_id, bs.side, f.name, f.player_id, f.status, p.is_npc
             from public.battle_sides bs
             join public.fleets f on f.id = bs.fleet_id
             join public.players p on p.id = f.player_id
            where bs.battle_id = p_battle order by bs.joined_at, bs.fleet_id loop
    update public.fleets f
       set status = case when f.status <> 'IN_BATTLE' then f.status
                         when (select sh.durability from public.ships sh where sh.fleet_id = f.id and sh.is_flagship) <= 0 then 'UNABLE_TO_SAIL'
                         when f.port_id is not null then 'DOCKED'
                         else 'ANCHORED' end,
           busy_until = null, version = version + 1
     where f.id = s.fleet_id;
    if s.status = 'IN_BATTLE' then
      perform cmd.advance(s.fleet_id, p_now);
    end if;
    if s.side = 'ATTACKER' and not s.is_npc then
      v_rep := public.battle_words(v_f, v_b);
      perform public.emit_event(s.player_id, 'BATTLE_REPORT', jsonb_build_object('fleet', s.name, 'battle_id', p_battle, 'outcome', v_f->>'outcome') || v_rep);
    end if;
  end loop;
  return true;
end
$body$;
$f$;

  execute $f$
create function public.tick_battles(p_now timestamptz default now())
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0323: THE BATTLES DUE, its own minute job (byeharu-voyage:battles). One read of a partial index when there are none. A bounded number a run; the next run takes the rest. SKIP LOCKED: two runs divide the work.
-- A battle that raises fails the run, loudly, in cron.job_run_details and in scripts/ops/health.sh's alert: a hold ends by its own clock, so nothing at sea waits on this.
declare
  r   record;
  v_n int := 0;
begin
  for r in select b.id from public.battles b
            where b.status = 'FIGHTING' and b.resolves_at <= p_now
            order by b.resolves_at, b.id limit 50
              for update skip locked loop
    if public.battle_resolve(r.id, p_now) then
      v_n := v_n + 1;
    end if;
  end loop;
  return v_n;
end
$body$;
$f$;

  revoke all on function public.attack_on() from public, anon, authenticated;
  revoke all on function voyage.hold_floor() from public, anon, authenticated;
  revoke all on function voyage.hold_unserved(uuid, integer, timestamptz) from public, anon, authenticated;
  revoke all on function voyage.holds_served(uuid) from public, anon, authenticated;
  revoke all on function voyage.hold(uuid, timestamptz, timestamptz) from public, anon, authenticated;
  revoke all on function voyage.fleet_hulls(uuid) from public, anon, authenticated;
  revoke all on function voyage.fight_round_line(jsonb, integer, text, jsonb, numeric, text) from public, anon, authenticated;
  revoke all on function public.battle_open(text, uuid, uuid, timestamptz) from public, anon, authenticated;
  revoke all on function public.battle_words(jsonb, jsonb) from public, anon, authenticated;
  revoke all on function public.battle_resolve(uuid, timestamptz) from public, anon, authenticated;
  revoke all on function public.tick_battles(timestamptz) from public, anon, authenticated;

  -- ── 6. THE HUNKS (each occurs exactly once in the live body, and reverses) ──
  create temp table hunks_0323 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0323 values
  ('voyage.delay_before_day(uuid,integer)', 1,
$h$   where ve.voyage_id = p_voyage and ve.day_index < p_day
  );$h$,
$h$   where ve.voyage_id = p_voyage and ve.day_index < p_day
  ) + (
  -- 0323: a hold's row stands above the days and counts from the day she was held on (voyage.hold)
  select coalesce(sum((ve.payload->>'delay_hours')::numeric), 0)
    from public.voyage_events ve
   where ve.voyage_id = p_voyage and ve.day_index >= voyage.hold_floor() and (ve.payload->>'from_day')::int <= p_day
  );$h$),
  ('voyage.progress_nm(uuid,timestamp with time zone)', 1,
$h$  v_leg_h   numeric;
begin$h$,
$h$  v_leg_h   numeric;
  v_day     int;     -- 0323: the day she is on at p_at
begin$h$),
  ('voyage.progress_nm(uuid,timestamp with time zone)', 2,
$h$  v_hours := greatest(0, extract(epoch from (p_at - v.departed_at))) * public.wc_num('time_compression') / 3600
           - voyage.delay_before_day(p_voyage, voyage.days_complete(p_voyage, p_at) + 1);$h$,
$h$  -- 0323: a hold's hours are in the delay from the day she was held on; those not yet passed are given back, so she stands still while it runs instead of jumping back as a storm's delay does.
  v_day   := voyage.days_complete(p_voyage, p_at) + 1;
  v_hours := greatest(0, extract(epoch from (p_at - v.departed_at))) * public.wc_num('time_compression') / 3600
           - voyage.delay_before_day(p_voyage, v_day) + voyage.hold_unserved(p_voyage, v_day, p_at);$h$),
  ('voyage.report_line(integer,text,jsonb)', 1,
$h$  return format('Day %s. ', p_day)$h$,
$h$  return format('Day %s. ', coalesce((p_payload->>'from_day')::int, p_day))   -- 0323: a hold's row stands above the days and names its own$h$),
  ('voyage.fight(uuid,integer,uuid,numeric)', 1,
$h$  return voyage.fight_resolve(p_voyage, p_day, p_raider, voyage.escort_score(p_fleet), (
    select jsonb_agg(jsonb_build_object(
             'id', s.id, 'name', s.name, 'tier', c.tier, 'hull', s.durability,
             -- 0276: her own rolled max — as a scalar subselect, because the jsonb_agg around this
             -- build_object is an aggregate and an aggregate cannot hold a set-returning call.
             'maxd', (select sb.durability from public.ship_base(s.id) sb), 'crew', s.crew,
             'attack', (x.st->>'attack')::numeric, 'accuracy', (x.st->>'accuracy')::numeric,
             'reach', (x.st->>'reach')::numeric, 'armour', (x.st->>'armour')::numeric,
             'sighting', (x.st->>'sighting')::numeric,
             'boarder_pct', public.crew_pct(p_fleet, s.id, 'attack'),
             'boarder', (select o.name from public.crew_terms(p_fleet) t join public.officers o on o.id = t.officer_id
                          where t.ship_id = s.id and t.effect = 'attack' and t.value_pct > 0
                          order by t.value_pct desc, o.name limit 1),
             'gunner', (select o.name from public.crew_terms(p_fleet) t join public.officers o on o.id = t.officer_id
                         where t.ship_id = s.id and t.effect in ('accuracy', 'reach') and t.value_pct > 0
                         order by t.value_pct desc, o.name limit 1),
             'gear', (select coalesce(jsonb_agg(distinct ik.name), '[]'::jsonb)
                        from public.fitted_units fu
                        join public.item_use iu on iu.item_code = fu.item_code and iu.trigger = 'PIRATES'
                        join public.item_kinds ik on ik.code = fu.item_code
                       where fu.ship_id = s.id))
           order by s.is_flagship desc, s.created_at, s.id)
      from public.ships s
      join public.ship_classes c on c.id = s.class_id
      cross join lateral (select world.ship_stats(s.id) as st) x
     where s.fleet_id = p_fleet));$h$,
$h$  return voyage.fight_resolve(p_voyage, p_day, p_raider, voyage.escort_score(p_fleet), voyage.fleet_hulls(p_fleet));   -- 0323: the side, cut to its own leaf$h$),
  ('voyage.fight_resolve(uuid,integer,numeric,numeric,jsonb)', 1,
$h$  x       jsonb;
  v_a     jsonb;
  v_b     jsonb;
  h       jsonb;
  g       int;
  v_you   text;
  v_they  text;
  v_hit_on text;
  v_can   int;
  v_fired int;
  v_hits  int;
  v_board jsonb := v_f->'board';$h$,
$h$  g       int;
  v_board jsonb := v_f->'board';$h$),
  ('voyage.fight_resolve(uuid,integer,numeric,numeric,jsonb)', 2,
$h$    x := v_f->'rounds'->(g - 1);
    v_a := x->'a';
    v_b := x->'b';
    v_can := (v_a->>'can')::int; v_fired := (v_a->>'fired')::int; v_hits := (v_a->>'hits')::int;
    v_hit_on := null;
    for h in select q.e from jsonb_array_elements(v_a->'struck') q(e) loop
      v_hit_on := coalesce(v_hit_on || ', ', '')
                  || format('%s for %s%% damage', coalesce(p_ships->((h->>0)::int - 1)->>'name', 'Your ship'), h->>1);
    end loop;
    v_you := case when g = 1 and v_first = 'THEY' then 'you are caught unready'
                  when v_can = 0 then 'you have no guns to answer with'
                  when v_fired = 0 then 'your guns cannot reach them'
                  when v_hits = 0 then format('you miss with %s shot%s', v_fired, case when v_fired = 1 then '' else 's' end)
                  else format('you hit with %s of %s shot%s', v_hits, v_fired, case when v_fired = 1 then '' else 's' end) end;
    v_they := case when g = 1 and v_first = 'YOU' then 'they are caught unready'
                   when (v_b->>'fired')::int = 0 then 'their guns cannot reach you'
                   when (v_b->>'hits')::int = 0 then 'they miss'
                   else format('they hit %s', v_hit_on)
                        || case when (v_b->>'raw')::numeric > (v_b->>'dealt')::numeric + 0.005
                                then format(' (armour turned %s%%)', round((1 - (v_b->>'dealt')::numeric / (v_b->>'raw')::numeric) * 100)) else '' end end;
    v_lines := v_lines || (format('Round %s · %s range — %s; %s.', g, lower(x->>'range'), v_you, v_they)
                           || case when v_hits > 0 then format(' The raiders are %s%% damaged.', round((1 - (v_b->>'left')::numeric / r_hull0) * 100)) else '' end);$h$,
$h$    v_lines := v_lines || voyage.fight_round_line(v_f->'rounds'->(g - 1), g, v_first, p_ships, r_hull0, 'raiders');   -- 0323: the one telling of a round$h$),
  ('cmd.divert(uuid,uuid,jsonb,jsonb)', 1,
$h$  if p_dest is not null then
    select code into v_dest_c from public.ports where id = p_dest;$h$,
$h$  -- 0323: a fleet held by a battle stands where she is: a turn would cut the voyage her hold is written on
  if f.busy_until is not null then
    return jsonb_build_object('ok', false, 'error_code', 'E_FLEET_BUSY',
      'error_message', format('%s is in battle and cannot turn.', f.name), 'fixes', '[]'::jsonb);
  end if;

  if p_dest is not null then
    select code into v_dest_c from public.ports where id = p_dest;$h$),
  ('world.voyage_view(uuid,boolean)', 1,
$h$                   from voyage.position(v.id) pos)) into v_full$h$,
$h$                   from voyage.position(v.id) pos))
                 || voyage.holds_served(v.id)   -- 0323: when she is held, served only then
                 into v_full$h$),
  ('world.voyage_view(uuid,boolean)', 2,
$h$                     then (v_full->'position') || jsonb_build_object('seg_index', 0) end);$h$,
$h$                     then (v_full->'position') || jsonb_build_object('seg_index', 0) end)
         || case when v_full ? 'holds' then jsonb_build_object('holds', v_full->'holds') else '{}'::jsonb end;   -- 0323$h$),
  ('world.sea_roster(timestamp with time zone)', 1,
$h$                         'eta', w.eta, 'total_nm', v.total_nm, 'departed_at', v.departed_at)
                        from public.voyages v where v.id = w.voyage_id),$h$,
$h$                         'eta', w.eta, 'total_nm', v.total_nm, 'departed_at', v.departed_at)
                        || voyage.holds_served(v.id)   -- 0323: the frozen facts of a hold, so she is placed standing still
                        from public.voyages v where v.id = w.voyage_id),$h$),
  ('world.sea_roster(timestamp with time zone)', 2,
$h$      or (h.kind is not null and exists (select 1 from public.voyages v4 where v4.fleet_id = f.id and v4.eta >= p_since and v4.eta <= now()));$h$,
$h$      or (h.kind is not null and exists (select 1 from public.voyages v4 where v4.fleet_id = f.id and v4.eta >= p_since and v4.eta <= now()))
      -- 0323: a hold moved her eta: she is served again while she is held, or the kept row would place her on the old one
      or f.busy_until >= p_since;$h$);

  for v_h in select h.fn from hunks_0323 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    declare
      x record;
      v_pre text := v_def;
    begin
      for x in select * from hunks_0323 h where h.fn = v_h.fn order by h.ord loop
        v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
        if v_n <> 1 then
          raise exception '0323 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
        end if;
        v_def := replace(v_def, x.old, x.new);
      end loop;
      execute v_def;
      v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
      for x in select * from hunks_0323 h where h.fn = v_h.fn order by h.ord desc loop
        v_n := (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new);
        if v_n <> 1 then
          raise exception '0323 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
        end if;
        v_def := replace(v_def, x.new, x.old);
      end loop;
      if v_def <> v_pre then
        raise exception '0323 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
      end if;
    end;
  end loop;

  -- ── 7. THE JOB: its own, not in the beat ──
  if to_regclass('cron.job') is not null then
    execute $q$select cron.schedule('byeharu-voyage:battles', '* * * * *', 'select public.tick_battles()')$q$;
  end if;

  -- ── 8. SELF-ASSERT: the catalog only ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked) x))
         and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_new_fns) x))) <> v_fn_before then
    raise exception '0323 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key not in ('attack_enabled', 'battle_seconds')) <> v_cfg_before then
    raise exception '0323 self-assert FAIL: a world_config row moved';
  end if;
  if (select md5(string_agg(k.code || ':' || k.ordinal || ':' || k.prose, ',' order by k.code))
        from public.voyage_event_kinds k where k.code <> 'BATTLE') <> v_kinds_before then
    raise exception '0323 self-assert FAIL: a voyage event kind moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked) x))) <> v_meta_before then
    raise exception '0323 self-assert FAIL: the ACL, volatility, definer or config of a hunked function moved';
  end if;
  if public.attack_on() then
    raise exception '0323 self-assert FAIL: new battles are not dark';
  end if;
  if exists (select 1 from public.battles) or exists (select 1 from public.battle_sides) then
    raise exception '0323 self-assert FAIL: a row stands in public.battles';
  end if;
  if (select k.is_rolled or k.in_sea_mix from public.voyage_event_kinds k where k.code = 'BATTLE') then
    raise exception '0323 self-assert FAIL: BATTLE may never be drawn';
  end if;
  if exists (select 1 from unnest(c_new_fns) f
              where has_function_privilege('anon', f::regprocedure, 'execute') or has_function_privilege('authenticated', f::regprocedure, 'execute')) then
    raise exception '0323 self-assert FAIL: a function of this file is open to clients';
  end if;
  if exists (select 1 from unnest(c_new_fns) f
              join public.client_rpc_entry_points() e on e.fn = f::regprocedure) then
    raise exception '0323 self-assert FAIL: a function of this file is in the client registry';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0323 self-assert FAIL: the self-assert took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0323 self-assert ok: A BATTLE TAKES TEN MINUTES, dark. % hunks once each and reversing; no other function, no existing knob or kind, no row; no game step ran (proof 31 runs them in CI). % ms.',
    (select count(*) from hunks_0323), round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0323;
end
$m$;
