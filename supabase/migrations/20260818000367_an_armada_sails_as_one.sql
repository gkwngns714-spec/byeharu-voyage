-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0367 - AN ARMADA: TWO TO SIX FLEETS AS ONE  (owner row 323; docs/ARMADA.md; the sailing and the raid: slice A1)
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
-- WHY: the owner, row 323 (2026-11-13): "with more than one fleet, max 6 fleet - an armada."
--   The lead's reading, decided by default: a named group of two to six of ONE company's fleets that act as one. They gather in one port, sail on one order at the slowest
--   fleet's speed and arrive together, and a raid meets all of them as one side. It changes nothing about how many ships a fleet holds, and no player fights a player.
--
-- WHAT (LIT at deploy: armada_enabled true; but see THE OWNER'S KNOBS below):
--   public.armadas, public.armada_fleets   the group and its fleets (a fleet is in one armada at most). Written by the three cores below only.
--   public.armada_voyages                  a voyage sailed in an armada names the armada's LEAD voyage (her flagship fleet's). No column is added to public.voyages.
--   public.armada_fights                   the one fight of an armada's raid day, kept once, so every fleet of hers reads the same fight whichever is settled first.
--   cmd.armada_form(fleets, name)          THE door to form one: 2 to armada_fleet_max fleets of hers, all docked in ONE port, each with a ship, none with an order waiting, none on a
--                                          trade route, none in an armada. The first fleet named is the flagship fleet. Paper: no ship, gold or cargo moves.
--   cmd.armada_disband(armada)             THE door to end one, anywhere, at any time. Fleets at sea sail on to the same port on the voyage they have.
--   cmd.armada_sail(armada, port, course, insured, dry)   THE one order (dry: the same order run and thrown away, for the figures before the press): every fleet through cmd.do_sail, the one mover (her own stores bought, her own gates, her own insurance), all or none.
--                                          A refusal names the fleet that was refused and carries her code and figures. Then the fleets are levelled to one schedule: one path,
--                                          one speed (the last reading, with every cask aboard), one arrival.
--   cmd.preview_armada_sail(...)           that order's dry run, by name, so the client's catalogue can call it without dropping its kept reads.
--   world.armadas()                        the read: {on, max, raid_scale, armadas [{id, name, flagship, fleets, speed_kn, state PORT / SEA / APART, port}]}. Totals are the client's sum of world.fleets().
--   voyage.fleet_speed_at                  THE speed of a fleet. A fleet of an armada sails at her armada's slowest fleet's speed; any other fleet: the figure it was, through
--                                          voyage.fleet_speed_alone_at, which IS the old body (moved by its header, as 0353 moved the skin). Stores, quotes, the gate and the
--                                          departure all read this one figure, so they agree.
--   voyage.hazard_roll (1 hunk)            a voyage sailed in an armada rolls the LEAD voyage's days: the same storm, calm, wind and raid on the same day for every fleet, so the
--                                          schedules stay equal and they arrive together. Any other voyage: one probe of a small table, and the roll it always had.
--   voyage.settle (2 hunks)                one variable; a PIRATES day of a voyage in an armada is fought ONCE with every hull of the armada still sailing on one side
--                                          (voyage.armada_fight -> voyage.raid_report -> public.fight_sides, the one engine). Each fleet then takes her own hulls' loss, her own
--                                          crew's loss, her own hold's plunder and her own insurance, by the arm that was already there. Any other voyage: one call that answers null.
--   cmd.do_sail, cmd.divert (1 hunk each)  a fleet of an armada sails on the armada's order only: E_IN_ARMADA.
--   knobs (NEW; no existing key is written): armada_enabled true, armada_fleet_max 6, armada_raid_scale 1.
--
-- THE OWNER'S KNOBS (not touched here): a company holds fleet_max 2 fleets while fleet_room_bite is off, and fleet_hard_max is 5. So an armada is 2 fleets today, 5 with the room lit,
--   and SIX only if the owner raises fleet_hard_max to 6. And while fleet_room_bite is off no player can start a second fleet at all (cmd.move_ship is dark with the room), so on prod
--   this file is reachable only by a company that already holds two fleets. Lighting the room is what brings armadas to players.
--
-- THE RAID, AND WHY IT IS NOT A FREE PASS (docs/ARMADA.md section 6; measured in docs/dev-log/2026-11-13-armada.md): the raiders of an anonymous raid are sized by the sea alone
--   (danger x 40 x (0.5 + magnitude)), not by what is carried. Six fleets against that one squadron would never lose. So an armada draws the raiders each of her fleets would have
--   drawn alone: strength x (1 + armada_raid_scale x (fleets - 1)), at 1 the same total a company meets sailing them apart. What she gains is that her warships fight for her
--   traders. A NAMED pirate ship is real hulls and is met as she is.
--
-- LEFT OUT (docs/ARMADA.md section 12): a battle she starts with all fleets on her side (0368, on top of 0357 and 0364, both still open), a fleet joining or leaving without
--   disbanding, a trade route for an armada, an armada bound for a point of open sea.
--
-- SUPERSEDES (re-cut): voyage.fleet_speed_at (0203; whole, body moved), voyage.hazard_roll (0334's body), voyage.settle (0353's body; the lines cut are 0339's `v_leg` and 0189's fight),
--   cmd.do_sail (0256's body), cmd.divert (0323's body), public.client_rpc_entry_points (0354's rows). Written against main at 0356 and checked against the open branches
--   0357, 0358, 0360, 0361, 0362 (which cuts voyage.settle three times: the `v_booked` line, the voyage.raid_takes line and the payload's first line), 0363 and 0364: none cuts a line this file anchors on.
-- COST: every fleet's speed: one more function call and one primary-key probe of public.armada_fleets. Every hazard roll: one primary-key probe of public.armada_voyages. Every
--   PIRATES day: one call that probes the same table and answers null. Every SAIL: one probe. All three tables are empty until a company forms an armada. Printed below.
-- SELF-ASSERT: ONE DO block, statement_timeout 45 s, lock_timeout 5 s first; fails above 40 s. The catalog (hunks once and reversing; ACL, volatility, definer and config unmoved;
--   no other function; no existing knob; the registry; the grants), speed and hazard parity against kept copies of the old bodies, bounded by the clock, then ONE probe of this file's
--   own rows rolled back by a raised sentinel. No table is counted or summed beyond the probe's own rows. The larger proof is CI's: scripts/db/proofs/68_armada.sql.
-- ROLLBACK (forward, owner only): armada_enabled false shuts forming and sailing at once (an armada already at sea finishes her voyage as one). The whole slice:
--   scripts/ops/harness/armada/rollback-0367.sql (disband all, swap the hunks back, put the speed body back, drop what this file made).
-- NEWS: public.news_update('0367', 'Armadas', '대함대') (0347's law).
-- LOCKS: four new tables referencing public.players, public.fleets and public.voyages (a brief SHARE ROW EXCLUSIVE on each, under lock_timeout 5 s).
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0          timestamptz := clock_timestamp();
  v_t           timestamptz;
  v_h           record;
  v_def         text;
  v_n           int;
  v_fn_before   text;
  v_cfg_before  text;
  v_meta_before text;
  v_speed_old   text;
  v_haz_old     text;
  v_lived       boolean := false;
  v_pl          uuid;
  v_other       uuid;
  v_f1          uuid;
  v_f2          uuid;
  v_f3          uuid;
  v_fo          uuid;
  v_lis         uuid;
  v_fnc         uuid;
  v_arm         uuid;
  v_r           jsonb;
  v_x           jsonb;
  v_y           jsonb;
  v_path        jsonb;
  v_pairs       int := 0;
  v_hz          int := 0;
  v_old_ms      numeric := 0;
  v_new_ms      numeric := 0;
  v_a           numeric;
  v_b           numeric;
  v_one         jsonb;
  c_uid   constant uuid := '00000000-0367-4000-8000-000000000001';
  c_uid2  constant uuid := '00000000-0367-4000-8000-000000000002';
  c_new_fns constant text[] := array[
    'public.armada_on()', 'public.armada_of(uuid)', 'voyage.fleet_speed_alone_at(uuid,numeric)', 'voyage.armada_side(uuid)',
    'voyage.armada_fight(uuid,integer,uuid,uuid,numeric)', 'public.armada_form_for(uuid,jsonb,text)', 'public.armada_disband_for(uuid,uuid)',
    'public.armada_sail_for(uuid,uuid,text,jsonb,boolean)', 'cmd.armada_form(jsonb,text)', 'cmd.armada_disband(uuid)', 'cmd.armada_sail(uuid,text,jsonb,boolean,boolean)', 'cmd.preview_armada_sail(uuid,text,jsonb,boolean)', 'world.armadas()'];
  c_doors constant text[] := array['cmd.armada_form(jsonb,text)', 'cmd.armada_disband(uuid)', 'cmd.armada_sail(uuid,text,jsonb,boolean,boolean)', 'cmd.preview_armada_sail(uuid,text,jsonb,boolean)', 'world.armadas()'];
  c_hunked constant text[] := array['voyage.hazard_roll(uuid,integer)', 'voyage.settle(uuid,timestamp with time zone)', 'cmd.do_sail(uuid,jsonb)', 'cmd.divert(uuid,uuid,jsonb,jsonb)',
                                    'public.client_rpc_entry_points()'];
  c_speed constant text := 'voyage.fleet_speed_at(uuid,numeric)';
  c_knobs constant text[] := array['armada_enabled', 'armada_fleet_max', 'armada_raid_scale'];
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regclass('public.armadas') is not null or to_regprocedure('world.armadas()') is not null or to_regprocedure('voyage.fleet_speed_alone_at(uuid,numeric)') is not null
     or exists (select 1 from public.world_config c where c.key = any (c_knobs)) then
    raise exception '0367 refuses: it has been applied once';
  end if;
  if to_regprocedure('voyage.raid_report(uuid,integer,numeric,numeric,jsonb,jsonb)') is null or to_regprocedure('voyage.raid_opts(uuid,integer,uuid)') is null
     or to_regprocedure('voyage.fleet_hulls(uuid)') is null or to_regprocedure('voyage.escort_score(uuid)') is null or to_regprocedure('public.combat_bite_on()') is null
     or to_regprocedure('cmd.do_sail(uuid,jsonb)') is null or to_regprocedure('cmd.refused_envelope(text,text)') is null or to_regprocedure('cmd.refuse(text,text,jsonb)') is null
     or to_regprocedure('public.news_update(text,text,text)') is null or to_regprocedure('public.form_fleet(uuid,text,uuid)') is null
     or to_regprocedure('public.fleet_totals(uuid,jsonb)') is null or to_regprocedure(c_speed) is null then
    raise exception '0367 refuses: a function this file calls is not in this world (0189 / 0323 / 0353 / 0354)';
  end if;

  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked || c_speed) x));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before
    from public.world_config c;
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
    into v_meta_before
    from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked || c_speed) x));
  v_speed_old := replace(pg_get_functiondef(c_speed::regprocedure), E'\r', '');
  v_haz_old := replace(pg_get_functiondef('voyage.hazard_roll(uuid,integer)'::regprocedure), E'\r', '');
  if (length(v_speed_old) - length(replace(v_speed_old, 'CREATE OR REPLACE FUNCTION voyage.fleet_speed_at(', ''))) / length('CREATE OR REPLACE FUNCTION voyage.fleet_speed_at(') <> 1 then
    raise exception '0367 slice: the header of voyage.fleet_speed_at does not occur exactly once';
  end if;

  -- ── 1. THE TABLES AND THE KNOBS ──
  create table public.armadas (
    id                uuid primary key default gen_random_uuid(),
    player_id         uuid not null references public.players(id) on delete cascade,
    name              text not null check (char_length(name) between 3 and 24 and name = btrim(name)),
    flagship_fleet_id uuid not null references public.fleets(id) on delete cascade,
    ordering          boolean not null default false,
    created_at        timestamptz not null default now()
  );
  create unique index armadas_player_name_unique on public.armadas (player_id, lower(name));
  comment on table public.armadas is
    '0367 (docs/ARMADA.md): an armada: a named group of 2 to armada_fleet_max fleets of ONE company that sail and meet a raid as one. `ordering` is true only inside cmd.armada_sail''s own transaction, so cmd.do_sail knows the armada''s order from a fleet''s own. Written by public.armada_form_for, public.armada_disband_for and public.armada_sail_for only. No client reads or writes it: world.armadas() serves it.';
  create table public.armada_fleets (
    fleet_id  uuid primary key references public.fleets(id) on delete cascade,
    armada_id uuid not null references public.armadas(id) on delete cascade,
    joined_at timestamptz not null default now()
  );
  create index armada_fleets_armada on public.armada_fleets (armada_id);
  comment on table public.armada_fleets is '0367: the fleets of an armada. A fleet is in one armada at most (the primary key). Empty until a company forms one, so every probe of it by a fleet of the world is one index miss.';
  create table public.armada_voyages (
    voyage_id      uuid primary key references public.voyages(id) on delete cascade,
    lead_voyage_id uuid not null references public.voyages(id) on delete cascade,
    armada_id      uuid not null,
    armada_name    text not null
  );
  create index armada_voyages_lead on public.armada_voyages (lead_voyage_id);
  comment on table public.armada_voyages is
    '0367: a voyage sailed in an armada, and the armada''s LEAD voyage (her flagship fleet''s; the lead names itself). voyage.hazard_roll rolls the lead''s days for it and voyage.armada_fight fights its raid as one side. It outlives the armada (no key to public.armadas), so an armada disbanded at sea still arrives as one. Written by public.armada_sail_for only.';
  create table public.armada_fights (
    voyage_id uuid not null references public.voyages(id) on delete cascade,
    day       int not null,
    answer    jsonb not null,
    primary key (voyage_id, day)
  );
  comment on table public.armada_fights is
    '0367: the one fight of an armada''s raid day, by her lead voyage and the day: {raider, escort, fleets, fight}. Written once by voyage.armada_fight (the first fleet of hers settled that day); every other fleet reads it, so all take the same fight.';
  alter table public.armadas enable row level security;
  alter table public.armada_fleets enable row level security;
  alter table public.armada_voyages enable row level security;
  alter table public.armada_fights enable row level security;
  revoke all on table public.armadas, public.armada_fleets, public.armada_voyages, public.armada_fights from public, anon, authenticated;

  insert into public.world_config (key, value, description) values
    ('armada_enabled', 'true'::jsonb,
     '0367: THE switch of armadas, read only through public.armada_on(). False: cmd.armada_form and cmd.armada_sail refuse E_NOT_IN_USE and world.armadas() answers {on: false}. Disbanding always works, and an armada already at sea finishes her voyage as one.'),
    ('armada_fleet_max', to_jsonb(6),
     '0367 (owner row 323: "max 6 fleet"): the most fleets in one armada. The least is 2. A company holds no more fleets than her own room (fleet_max, fleet_hard_max), so this is reached only when that room allows it.'),
    ('armada_raid_scale', to_jsonb(1),
     '0367: how much an anonymous raid grows for each fleet of an armada after the first: strength x (1 + this x (fleets - 1)). 1: she draws the raiders her fleets would have drawn sailing apart. 0: one squadron whatever her size (six fleets then never lose). A named pirate ship is met as she is. Read by voyage.armada_fight.');

  -- ── 2. THE LEAVES ──
  execute $f$
create function public.armada_on()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0367: THE one reader of armada_enabled.
  select public.wc('armada_enabled') = 'true'::jsonb
$$
  $f$;

  execute $f$
create function public.armada_of(p_fleet uuid)
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0367: THE armada a fleet is in, or null. One primary-key probe.
  select af.armada_id from public.armada_fleets af where af.fleet_id = p_fleet
$$
  $f$;

  -- THE SPEED: the live body moves to voyage.fleet_speed_alone_at by its header (nothing else of it changes), and voyage.fleet_speed_at becomes the armada's reading of it.
  execute replace(v_speed_old, 'CREATE OR REPLACE FUNCTION voyage.fleet_speed_at(', 'CREATE OR REPLACE FUNCTION voyage.fleet_speed_alone_at(');
  execute $f$
create or replace function voyage.fleet_speed_at(p_fleet uuid, p_fill numeric)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0367 (docs/ARMADA.md section 4): THE SPEED OF A FLEET. A fleet of an armada sails at her armada's speed: the slowest of her fleets that has a ship. Any other fleet:
-- voyage.fleet_speed_alone_at, the formula as it was (0203), after one primary-key probe of public.armada_fleets. Every reader of a fleet's speed (the departure, the stores
-- a leg asks, the gate, the quotes) reads this, so they agree for a fleet of an armada too. A fleet with no ship raises E_NO_SHIPS as before.
declare
  v_arm uuid;
begin
  select af.armada_id into v_arm from public.armada_fleets af where af.fleet_id = p_fleet;
  if v_arm is null then
    return voyage.fleet_speed_alone_at(p_fleet, p_fill);
  end if;
  return least(voyage.fleet_speed_alone_at(p_fleet, p_fill),
               (select min(voyage.fleet_speed_alone_at(m.fleet_id, p_fill))
                  from public.armada_fleets m
                 where m.armada_id = v_arm and m.fleet_id <> p_fleet
                   and exists (select 1 from public.ships s where s.fleet_id = m.fleet_id)));
end $$
  $f$;

  execute $f$
create function voyage.armada_side(p_lead uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0367 (docs/ARMADA.md section 6): AN ARMADA AS ONE SIDE OF A FIGHT: the hulls of every fleet whose voyage sails under this lead voyage and is still sailing, as they stand
-- (voyage.fleet_hulls, the one reading of a fleet as a side), the lead's fleet first. `fleets` is [[name, hulls]] in that order, `escort` the sum of voyage.escort_score, `n` the fleets.
declare
  r        record;
  v_ships  jsonb := '[]'::jsonb;
  v_fleets jsonb := '[]'::jsonb;
  v_esc    numeric := 0;
  v_n      int := 0;
  v_h      jsonb;
begin
  for r in select f.id, f.name
             from public.armada_voyages av
             join public.voyages v on v.id = av.voyage_id and v.status = 'SAILING'
             join public.fleets f on f.id = v.fleet_id and f.status = 'SAILING'
            where av.lead_voyage_id = p_lead
            order by (av.voyage_id = p_lead) desc, f.created_at, f.id loop
    v_h := coalesce(voyage.fleet_hulls(r.id), '[]'::jsonb);
    continue when jsonb_array_length(v_h) = 0;
    v_ships := v_ships || v_h;
    v_fleets := v_fleets || jsonb_build_array(jsonb_build_array(r.name, jsonb_array_length(v_h)));
    v_esc := v_esc + voyage.escort_score(r.id);
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('ships', v_ships, 'fleets', v_fleets, 'escort', v_esc, 'n', v_n);
end $$
  $f$;

  execute $f$
create function voyage.armada_fight(p_voyage uuid, p_day int, p_fleet uuid, p_pirate uuid, p_raider numeric)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0367 (docs/ARMADA.md section 6): THE RAID DAY OF A VOYAGE SAILED IN AN ARMADA, fought ONCE. Null for any other voyage (one primary-key probe), and null when she is the only
-- fleet of hers still sailing: voyage.settle then runs the day as it always did. Else {raider, escort, fleets, fight}:
--   raider   an anonymous raid grows by armada_raid_scale for each fleet after the first; a named pirate ship (p_pirate) is met as she is
--   escort   the sum of her fleets' escort scores
--   fight    while combat_bite is on: voyage.raid_report, the skin every raid is fought through, seeded by the LEAD voyage, with every hull of hers on one side and her flagship
--            fleet's standing order; its log names the fleets (`fleets` [[name, hulls]], in the order of `you`). Absent while combat_bite is off.
-- The first fleet settled that day fights it and keeps it (public.armada_fights); the others read the kept answer, so every fleet takes the SAME fight.
declare
  v_lead  uuid;
  v_ans   jsonb;
  v_side  jsonb;
  v_n     int;
  v_r     numeric;
  v_fight jsonb;
  v_lf    uuid;
begin
  select av.lead_voyage_id into v_lead from public.armada_voyages av where av.voyage_id = p_voyage;
  if v_lead is null then
    return null;
  end if;
  select g.answer into v_ans from public.armada_fights g where g.voyage_id = v_lead and g.day = p_day;
  if v_ans is not null then
    return v_ans;
  end if;
  v_side := voyage.armada_side(v_lead);
  v_n := (v_side ->> 'n')::int;
  if v_n < 2 then
    return null;
  end if;
  v_r := case when p_pirate is not null then p_raider
              else p_raider * (1 + greatest(0, public.wc_num('armada_raid_scale')) * (v_n - 1)) end;
  if public.combat_bite_on() then
    select v.fleet_id into v_lf from public.voyages v where v.id = v_lead;
    v_fight := voyage.raid_report(v_lead, p_day, v_r, (v_side ->> 'escort')::numeric, v_side -> 'ships', voyage.raid_opts(v_lead, p_day, v_lf));
    if v_fight ? 'log' then
      v_fight := jsonb_set(v_fight, '{log,fleets}', v_side -> 'fleets');
    end if;
  end if;
  v_ans := jsonb_build_object('raider', v_r, 'escort', (v_side ->> 'escort')::numeric, 'fleets', v_n)
        || case when v_fight is null then '{}'::jsonb else jsonb_build_object('fight', v_fight) end;
  insert into public.armada_fights (voyage_id, day, answer) values (v_lead, p_day, v_ans) on conflict (voyage_id, day) do nothing;
  return (select g.answer from public.armada_fights g where g.voyage_id = v_lead and g.day = p_day);
end $$
  $f$;

  -- ── 3. THE CORES ──
  execute $f$
create function public.armada_form_for(p_player uuid, p_fleets jsonb, p_name text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0367 (docs/ARMADA.md section 2): THE one way an armada is formed. Paper at the quay: no ship, cargo or gold moves. p_fleets is a list of her fleet ids; the first is the flagship fleet.
-- Refuses before anything is written; each refusal is its own code.
declare
  v_name  text := btrim(coalesce(p_name, ''));
  v_ids   uuid[];
  v_npc   boolean;
  v_max   int := public.wc_int('armada_fleet_max');
  v_port  uuid;
  v_id    uuid;
  r       record;
begin
  if not public.armada_on() then
    perform cmd.refuse('E_NOT_IN_USE', 'armadas are not in use yet');
  end if;
  select p.is_npc into v_npc from public.players p where p.id = p_player;
  if v_npc is null then
    perform cmd.refuse('E_NO_HOUSE', 'there is no such company');
  end if;
  if v_npc then
    perform cmd.refuse('E_NOT_IN_USE', 'a merchant forms no armada');
  end if;
  if p_fleets is null or jsonb_typeof(p_fleets) <> 'array' then
    perform cmd.refuse('E_PARSE', 'name the fleets of the armada');
  end if;
  begin
    select array_agg(x.id order by x.ord) into v_ids
      from (select distinct on (e.value) e.value::uuid as id, e.ord from jsonb_array_elements_text(p_fleets) with ordinality e(value, ord) order by e.value, e.ord) x;
  exception when invalid_text_representation then
    perform cmd.refuse('E_PARSE', 'name the fleets of the armada');
  end;
  if coalesce(array_length(v_ids, 1), 0) < 2 then
    perform cmd.refuse('E_ARMADA_SIZE', format('an armada is 2 to %s fleets', v_max), cmd.figures(coalesce(array_length(v_ids, 1), 0), 2, 'fleets'));
  end if;
  if array_length(v_ids, 1) > v_max then   -- no figures: cmd.figures is have-short-of-need, and this is too many
    perform cmd.refuse('E_ARMADA_SIZE', format('an armada is 2 to %s fleets and you named %s', v_max, array_length(v_ids, 1)));
  end if;
  if (select count(*) from public.fleets f where f.id = any (v_ids) and f.player_id = p_player) <> array_length(v_ids, 1) then
    perform cmd.refuse('E_NO_SUCH_FLEET', 'there is no such fleet of yours');
  end if;
  -- what has landed, lands first; then the fleets are locked in id order, as every verb locks them
  for r in select f.id from public.fleets f where f.id = any (v_ids) order by f.id loop
    perform voyage.settle(r.id);
  end loop;
  perform 1 from public.fleets f where f.id = any (v_ids) order by f.id for update;
  select f.port_id into v_port from public.fleets f where f.id = v_ids[1];
  for r in select f.*, (select code from public.ports p where p.id = f.port_id) as port_code
             from public.fleets f join unnest(v_ids) with ordinality u(id, ord) on u.id = f.id order by u.ord loop
    if exists (select 1 from public.armada_fleets af where af.fleet_id = r.id) then
      perform cmd.refuse('E_IN_ARMADA', format('%s is in an armada already', r.name));
    end if;
    if r.status <> 'DOCKED' then
      perform cmd.refuse('E_NOT_DOCKED', format('%s is %s and an armada gathers in port', r.name, lower(replace(r.status, '_', ' '))));
    end if;
    if r.port_id is distinct from v_port then
      perform cmd.refuse('E_NOT_SAME_PORT', format('%s lies at %s; an armada gathers in one port', r.name, r.port_code));
    end if;
    if not exists (select 1 from public.ships s where s.fleet_id = r.id) then
      perform cmd.refuse('E_FLEET_EMPTY', format('%s has no ships', r.name));
    end if;
    if r.busy_until is not null or exists (select 1 from public.orders o where o.fleet_id = r.id and o.status in ('pending', 'active')) then
      perform cmd.refuse('E_FLEET_BUSY', format('%s has orders waiting', r.name));
    end if;
    if exists (select 1 from public.standing_routes sr where sr.fleet_id = r.id) then
      perform cmd.refuse('E_ARMADA_ROUTE', format('%s runs a trade route; take her off it first', r.name));
    end if;
  end loop;
  begin
    insert into public.armadas (player_id, name, flagship_fleet_id) values (p_player, v_name, v_ids[1]) returning id into v_id;
  exception
    when check_violation then
      perform cmd.refuse('E_BAD_NAME', 'an armada is named in 3 to 24 letters');
    when unique_violation then
      perform cmd.refuse('E_NAME_TAKEN', format('you already keep an armada called %s', v_name));
  end;
  insert into public.armada_fleets (fleet_id, armada_id) select u.id, v_id from unnest(v_ids) u(id);
  perform public.emit_event(p_player, 'ARMADA_FORMED', jsonb_build_object('armada', v_name, 'fleets',
            (select jsonb_agg(f.name order by u.ord) from public.fleets f join unnest(v_ids) with ordinality u(id, ord) on u.id = f.id)));
  return jsonb_build_object('ok', true, 'armada_id', v_id, 'name', v_name, 'fleets', to_jsonb(v_ids));
end $$
  $f$;

  execute $f$
create function public.armada_disband_for(p_player uuid, p_armada uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0367 (docs/ARMADA.md section 2): THE one way an armada ends. Anywhere, at any time, and with the switch off. Her fleets are each their own again; those at sea sail on to the
-- port they were bound for, on the schedule they share (public.armada_voyages stays).
declare
  a public.armadas%rowtype;
begin
  select x.* into a from public.armadas x where x.id = p_armada and x.player_id = p_player for update;
  if a.id is null then
    perform cmd.refuse('E_NO_SUCH_ARMADA', 'there is no such armada of yours');
  end if;
  delete from public.armadas where id = a.id;
  perform public.emit_event(p_player, 'ARMADA_DISBANDED', jsonb_build_object('armada', a.name));
  return jsonb_build_object('ok', true, 'armada_id', a.id, 'name', a.name);
end $$
  $f$;

  execute $f$
create function public.armada_sail_for(p_player uuid, p_armada uuid, p_dest text, p_path jsonb, p_insured boolean)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0367 (docs/ARMADA.md section 4): THE ARMADA'S ONE ORDER. Every fleet of hers leaves through cmd.do_sail, the one mover: her own stores bought, her own gates, her own insurance.
-- ALL OR NONE: the first fleet refused refuses the armada, under that fleet's name, code and figures; the caller's door rolls the rest back. Then the fleets are levelled to one
-- schedule: the lead's path (her flagship fleet's, with what was frozen on it), and the LAST fleet's speed and arrival, read with every fleet's casks aboard (the slowest it gets).
declare
  a        public.armadas%rowtype;
  v_dest   uuid;
  v_port   uuid;
  v_ids    uuid[];
  r        record;
  v_args   jsonb;
  v_res    jsonb;
  v_det    text;
  v_voys   uuid[] := '{}';
  v_out    jsonb := '[]'::jsonb;
  v_lead   uuid;
  v_last   uuid;
  v_eta    timestamptz;
begin
  if not public.armada_on() then
    perform cmd.refuse('E_NOT_IN_USE', 'armadas are not in use yet');
  end if;
  select x.* into a from public.armadas x where x.id = p_armada and x.player_id = p_player for update;
  if a.id is null then
    perform cmd.refuse('E_NO_SUCH_ARMADA', 'there is no such armada of yours');
  end if;
  select p.id into v_dest from public.ports p where p.code = upper(btrim(coalesce(p_dest, '')));
  if v_dest is null then
    perform cmd.refuse('E_NO_SUCH_PORT', 'there is no such port');
  end if;
  select array_agg(f.id order by (f.id = a.flagship_fleet_id) desc, f.created_at, f.id) into v_ids
    from public.armada_fleets af join public.fleets f on f.id = af.fleet_id where af.armada_id = a.id;
  for r in select f.id from public.fleets f where f.id = any (v_ids) order by f.id loop
    perform voyage.settle(r.id);
  end loop;
  perform 1 from public.fleets f where f.id = any (v_ids) order by f.id for update;
  select f.port_id into v_port from public.fleets f where f.id = v_ids[1];
  for r in select f.*, (select code from public.ports p where p.id = f.port_id) as port_code
             from public.fleets f join unnest(v_ids) with ordinality u(id, ord) on u.id = f.id order by u.ord loop
    if r.status <> 'DOCKED' or r.port_id is distinct from v_port then
      perform cmd.refuse('E_ARMADA_APART', format('%s is %s; the armada sails from one port', r.name,
                         case when r.status = 'DOCKED' then 'at ' || r.port_code else lower(replace(r.status, '_', ' ')) end));
    end if;
    if not exists (select 1 from public.ships s where s.fleet_id = r.id) then
      perform cmd.refuse('E_FLEET_EMPTY', format('%s has no ships', r.name));
    end if;
    if r.busy_until is not null or exists (select 1 from public.orders o where o.fleet_id = r.id and o.status in ('pending', 'active')) then
      perform cmd.refuse('E_FLEET_BUSY', format('%s has orders waiting', r.name));
    end if;
  end loop;

  v_args := jsonb_build_object('dest', v_dest, 'insured', coalesce(p_insured, false))
         || case when p_path is not null and jsonb_typeof(p_path) = 'array' then jsonb_build_object('path', p_path) else '{}'::jsonb end;
  update public.armadas set ordering = true where id = a.id;
  for r in select f.id, f.name from public.fleets f join unnest(v_ids) with ordinality u(id, ord) on u.id = f.id order by u.ord loop
    begin
      v_res := cmd.do_sail(r.id, v_args);
    exception when others then
      if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
      get stacked diagnostics v_det = pg_exception_detail;
      raise exception '%', regexp_replace(sqlerrm, '^(E_[A-Z0-9_]+): ', '\1: ' || replace(r.name, '\', '\\') || ': ')
        using errcode = 'P0001', detail = coalesce(v_det, '');
    end;
    v_last := (v_res ->> 'voyage_id')::uuid;
    v_lead := coalesce(v_lead, v_last);
    v_voys := v_voys || v_last;
    v_out := v_out || jsonb_build_array(jsonb_build_object('fleet_id', r.id, 'fleet', r.name, 'voyage_id', v_last, 'total_nm', v_res -> 'total_nm', 'insurance', v_res -> 'insurance')
                   || case when v_res ? 'on_credit' then jsonb_build_object('on_credit', v_res -> 'on_credit') else '{}'::jsonb end);
  end loop;
  update public.armadas set ordering = false where id = a.id;

  -- ONE SCHEDULE: the lead's path, the last reading of the speed (every cask is aboard by then, so it is the slowest), one arrival.
  update public.voyages v
     set path = l.path, speed_profile = z.speed_profile, eta = z.eta
    from public.voyages l, public.voyages z
   where l.id = v_lead and z.id = v_last and v.id = any (v_voys);
  select v.eta into v_eta from public.voyages v where v.id = v_last;
  insert into public.armada_voyages (voyage_id, lead_voyage_id, armada_id, armada_name)
  select u.id, v_lead, a.id, a.name from unnest(v_voys) u(id);
  perform public.emit_event(p_player, 'ARMADA_SAILED', jsonb_build_object('armada', a.name, 'fleets', jsonb_array_length(v_out),
            'dest', (select p.code from public.ports p where p.id = v_dest), 'eta', v_eta));
  return jsonb_build_object('ok', true, 'armada_id', a.id, 'name', a.name, 'eta', v_eta,
                            'speed_kn', (select (v.speed_profile ->> 0)::numeric from public.voyages v where v.id = v_last),
                            'lead_voyage_id', v_lead, 'voyages', v_out);
end $$
  $f$;

  -- ── 4. THE DOORS AND THE READ ──
  execute $f$
create function cmd.armada_form(p_fleets jsonb, p_name text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0367: the caller's company forms an armada of her fleets. The core is public.armada_form_for.
declare
  v_player uuid := public.current_player_id();
  v_det    text;
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_HOUSE',
                              'error_message', 'Found a house first.', 'fixes', '[]'::jsonb);
  end if;
  begin
    return public.armada_form_for(v_player, p_fleets, p_name);
  exception when others then
    if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
    get stacked diagnostics v_det = pg_exception_detail;
    return cmd.refused_envelope(sqlerrm, v_det);
  end;
end $$
  $f$;

  execute $f$
create function cmd.armada_disband(p_armada uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0367: the caller's company disbands an armada of hers. The core is public.armada_disband_for.
declare
  v_player uuid := public.current_player_id();
  v_det    text;
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_HOUSE',
                              'error_message', 'Found a house first.', 'fixes', '[]'::jsonb);
  end if;
  begin
    return public.armada_disband_for(v_player, p_armada);
  exception when others then
    if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
    get stacked diagnostics v_det = pg_exception_detail;
    return cmd.refused_envelope(sqlerrm, v_det);
  end;
end $$
  $f$;

  execute $f$
create function cmd.armada_sail(p_armada uuid, p_dest text, p_path jsonb default null, p_insured boolean default false, p_dry boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0367: the caller's company sends an armada of hers to a port, on one order. The core is public.armada_sail_for; a refusal leaves every fleet where she was.
-- `cost` is what the order costs her (every fleet's stores and insurance): what left her purse plus `on_credit`, the part of it left owed where credit is lit. p_dry: THE SAME ORDER, run and thrown away (as cmd.preview
-- does for one fleet), so what the screen shows before the press is what the press does.
declare
  v_player uuid := public.current_player_id();
  v_det    text;
  v_purse  bigint;
  v_out    jsonb;
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_HOUSE',
                              'error_message', 'Found a house first.', 'fixes', '[]'::jsonb);
  end if;
  select p.ducats into v_purse from public.players p where p.id = v_player;
  begin
    v_out := public.armada_sail_for(v_player, p_armada, p_dest, p_path, p_insured);
    v_out := v_out || jsonb_build_object('on_credit', (select coalesce(sum((x.value ->> 'on_credit')::bigint), 0) from jsonb_array_elements(v_out -> 'voyages') x));
    v_out := v_out || jsonb_build_object('dry', coalesce(p_dry, false),
               'cost', v_purse - (select p.ducats from public.players p where p.id = v_player) + (v_out ->> 'on_credit')::bigint);
    if coalesce(p_dry, false) then
      raise exception using errcode = 'ZD367', message = '__ARMADA_DRY_RUN__';
    end if;
    return v_out;
  exception
    when sqlstate 'ZD367' then
      return v_out;
    when others then
      if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
      get stacked diagnostics v_det = pg_exception_detail;
      return cmd.refused_envelope(sqlerrm, v_det);
  end;
end $$
  $f$;

  execute $f$
create function cmd.preview_armada_sail(p_armada uuid, p_dest text, p_path jsonb default null, p_insured boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0367: what cmd.armada_sail would do, for the figures before the press: the real order, run and thrown away (cmd.armada_sail with p_dry). Keeps nothing.
begin
  return cmd.armada_sail(p_armada, p_dest, p_path, p_insured, true);
end $$
  $f$;

  execute $f$
create function world.armadas()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0367 (docs/ARMADA.md section 9): THE CALLER'S ARMADAS. `fleets` are her fleet ids, the flagship fleet first: their names, ships and totals are world.fleets()'s, which the
  -- client already holds. `state`: PORT (all docked in one port: she may be sent), SEA (all at sea) or APART (anything else: disband and form again). `speed_kn` is the armada's.
  -- A merchant or a signed-out caller reads no armadas.
  select jsonb_build_object(
    'on', public.armada_on(), 'max', public.wc_int('armada_fleet_max'), 'raid_scale', public.wc_num('armada_raid_scale'),
    'armadas', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', a.id, 'name', a.name, 'flagship', a.flagship_fleet_id, 'fleets', m.ids,
               'state', case when m.n = m.docked and m.ports = 1 then 'PORT' when m.n = m.sailing then 'SEA' else 'APART' end,
               'port', case when m.n = m.docked and m.ports = 1 then (select p.code from public.ports p where p.id = m.port) end,
               'speed_kn', case when exists (select 1 from public.ships s where s.fleet_id = a.flagship_fleet_id) then voyage.fleet_speed(a.flagship_fleet_id) else 0 end)
             order by a.created_at, a.id)
        from public.armadas a
       cross join lateral (
         select jsonb_agg(f.id order by (f.id = a.flagship_fleet_id) desc, f.created_at, f.id) as ids, count(*) as n,
                count(*) filter (where f.status = 'DOCKED') as docked, count(*) filter (where f.status = 'SAILING') as sailing,
                count(distinct f.port_id) as ports, (array_agg(f.port_id))[1] as port
           from public.armada_fleets af join public.fleets f on f.id = af.fleet_id
          where af.armada_id = a.id) m
       where a.player_id = public.current_player_id()), '[]'::jsonb))
$$
  $f$;

  revoke all on function public.armada_on() from public, anon, authenticated;
  revoke all on function public.armada_of(uuid) from public, anon, authenticated;
  revoke all on function voyage.fleet_speed_alone_at(uuid, numeric) from public, anon, authenticated;
  revoke all on function voyage.armada_side(uuid) from public, anon, authenticated;
  revoke all on function voyage.armada_fight(uuid, int, uuid, uuid, numeric) from public, anon, authenticated;
  revoke all on function public.armada_form_for(uuid, jsonb, text) from public, anon, authenticated;
  revoke all on function public.armada_disband_for(uuid, uuid) from public, anon, authenticated;
  revoke all on function public.armada_sail_for(uuid, uuid, text, jsonb, boolean) from public, anon, authenticated;
  revoke all on function cmd.armada_form(jsonb, text) from public, anon;
  grant execute on function cmd.armada_form(jsonb, text) to authenticated;
  revoke all on function cmd.armada_disband(uuid) from public, anon;
  grant execute on function cmd.armada_disband(uuid) to authenticated;
  revoke all on function cmd.armada_sail(uuid, text, jsonb, boolean, boolean) from public, anon;
  grant execute on function cmd.armada_sail(uuid, text, jsonb, boolean, boolean) to authenticated;
  revoke all on function cmd.preview_armada_sail(uuid, text, jsonb, boolean) from public, anon;
  grant execute on function cmd.preview_armada_sail(uuid, text, jsonb, boolean) to authenticated;
  revoke all on function world.armadas() from public, anon;
  grant execute on function world.armadas() to authenticated;

  -- ── 5. THE HUNKS (each occurs exactly once in the live body, and reverses) ──
  create temp table hunks_0367 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0367 values
  ('voyage.hazard_roll(uuid,integer)', 1,
$h$  v_leg := voyage.leg_at_day(p_voyage, p_day);
  v_sea := (v_leg->>'sea_id')::uuid;
$h$,
$h$  -- 0367 (docs/ARMADA.md section 4): a voyage sailed in an armada rolls her LEAD voyage's days, so every fleet of hers meets the same sea on the same day and they arrive together.
  -- Any other voyage: one primary-key probe of a small table, and the roll it always had.
  p_voyage := coalesce((select av.lead_voyage_id from public.armada_voyages av where av.voyage_id = p_voyage), p_voyage);
  v_leg := voyage.leg_at_day(p_voyage, p_day);
  v_sea := (v_leg->>'sea_id')::uuid;
$h$),
  ('voyage.settle(uuid,timestamp with time zone)', 1,
$h$  v_leg     jsonb;     -- 0339: the day's frozen segment, read once for its danger and its raider
$h$,
$h$  v_leg     jsonb;     -- 0339: the day's frozen segment, read once for its danger and its raider
  v_arm     jsonb;     -- 0367: an armada's one fight of the day (voyage.armada_fight); null for a voyage in no armada
$h$),
  ('voyage.settle(uuid,timestamp with time zone)', 2,
$h$      v_fight := case when public.combat_bite_on() then voyage.fight(v.id, d, p_fleet, v_raider) end;
$h$,
$h$      -- 0367 (docs/ARMADA.md section 6): a voyage sailed in an armada meets the raid with every hull of the armada on one side, against the raiders all her fleets draw; the
      -- fight is fought once and every fleet of hers reads it (voyage.armada_fight). Below, each fleet takes her own hulls', crew's and hold's share as ever. Null: the day it always was.
      v_arm := voyage.armada_fight(v.id, d, p_fleet, v_pirate, v_raider);
      if v_arm is not null then
        v_raider := (v_arm->>'raider')::numeric;
        v_escort := (v_arm->>'escort')::numeric;
        v_fight := v_arm->'fight';
      else
      v_fight := case when public.combat_bite_on() then voyage.fight(v.id, d, p_fleet, v_raider) end;
      end if;
$h$),
  ('cmd.do_sail(uuid,jsonb)', 1,
$h$  select * into f from public.fleets where id = p_fleet;

  -- the gates that need no distance, first (status, crew, flagship, and the berth facts)
$h$,
$h$  select * into f from public.fleets where id = p_fleet;

  -- 0367 (docs/ARMADA.md section 4): a fleet of an armada sails on the armada's order only (cmd.armada_sail, which marks its own transaction on the armada's row).
  if exists (select 1 from public.armada_fleets af join public.armadas a on a.id = af.armada_id where af.fleet_id = p_fleet and not a.ordering) then
    raise exception 'E_IN_ARMADA: % sails with her armada; send the armada, or disband it', f.name using errcode = 'P0001';
  end if;

  -- the gates that need no distance, first (status, crew, flagship, and the berth facts)
$h$),
  ('cmd.divert(uuid,uuid,jsonb,jsonb)', 1,
$h$  -- Catch up first: an act must not reason about a stale position (D.2).
  perform voyage.settle(p_fleet, v_now);
$h$,
$h$  -- 0367 (docs/ARMADA.md section 4): a fleet of an armada does not turn alone.
  if public.armada_of(p_fleet) is not null then
    return jsonb_build_object('ok', false, 'error_code', 'E_IN_ARMADA',
      'error_message', format('%s sails with her armada; disband it to turn her alone.', f.name), 'fixes', '[]'::jsonb);
  end if;

  -- Catch up first: an act must not reason about a stale position (D.2).
  perform voyage.settle(p_fleet, v_now);
$h$),
  ('public.client_rpc_entry_points()', 1,
$h$      ('cmd',         'rename_fleet',          'uuid, text'),
$h$,
$h$      ('cmd',         'rename_fleet',          'uuid, text'),
      -- 0367: an armada: the read, and the doors to form, disband and send one (and the send's dry run).
      ('world',       'armadas',               ''),
      ('cmd',         'armada_form',           'jsonb, text'),
      ('cmd',         'armada_disband',        'uuid'),
      ('cmd',         'armada_sail',           'uuid, text, jsonb, boolean, boolean'),
      ('cmd',         'preview_armada_sail',   'uuid, text, jsonb, boolean'),
$h$);

  for v_h in select h.fn from hunks_0367 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    declare
      x record;
      v_pre text := v_def;
    begin
      for x in select * from hunks_0367 h where h.fn = v_h.fn order by h.ord loop
        v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
        if v_n <> 1 then
          raise exception '0367 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
        end if;
        v_def := replace(v_def, x.old, x.new);
      end loop;
      execute v_def;
      v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
      for x in select * from hunks_0367 h where h.fn = v_h.fn order by h.ord desc loop
        v_n := (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new);
        if v_n <> 1 then
          raise exception '0367 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
        end if;
        v_def := replace(v_def, x.new, x.old);
      end loop;
      if v_def <> v_pre then
        raise exception '0367 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
      end if;
    end;
  end loop;
  if (select count(*) from hunks_0367) <> 6 then
    raise exception '0367 self-assert FAIL: % hunks, not 6', (select count(*) from hunks_0367);
  end if;
  -- the speed's body reverses by its header: voyage.fleet_speed_alone_at under the old name IS the pre-image
  if replace(replace(pg_get_functiondef('voyage.fleet_speed_alone_at(uuid,numeric)'::regprocedure), E'\r', ''),
             'CREATE OR REPLACE FUNCTION voyage.fleet_speed_alone_at(', 'CREATE OR REPLACE FUNCTION voyage.fleet_speed_at(') <> v_speed_old then
    raise exception '0367 self-assert FAIL: voyage.fleet_speed_alone_at is not the old body of voyage.fleet_speed_at';
  end if;

  -- ── 6. SELF-ASSERT: the catalog ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked || c_speed || c_new_fns) x))) <> v_fn_before then
    raise exception '0367 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key <> all (c_knobs)) <> v_cfg_before
     or (select count(*) from public.world_config c where c.key = any (c_knobs)) <> 3 then
    raise exception '0367 self-assert FAIL: an existing world_config row moved, or the three new knobs are not there';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked || c_speed) x))) <> v_meta_before then
    raise exception '0367 self-assert FAIL: the ACL, volatility, definer or config of a re-cut function moved';
  end if;
  if not public.armada_on() or public.wc_int('armada_fleet_max') <> 6 or public.wc_num('armada_raid_scale') <> 1 then
    raise exception '0367 self-assert FAIL: the knobs are not lit, 6 and 1';
  end if;
  if exists (select 1 from unnest(c_new_fns) f
              where has_function_privilege('anon', f::regprocedure, 'execute')
                 or (has_function_privilege('authenticated', f::regprocedure, 'execute') <> (f = any (c_doors)))) then
    raise exception '0367 self-assert FAIL: the grants are not the contract: only the read and the four doors, only to authenticated';
  end if;
  if (select count(*) from public.client_rpc_entry_points() e where e.function_name in ('armadas', 'armada_form', 'armada_disband', 'armada_sail', 'preview_armada_sail') and e.fn is not null) <> 5 then
    raise exception '0367 self-assert FAIL: the read or a door is not in the client registry';
  end if;
  if (select count(*) from public.client_write_grants()) <> 0 then
    raise exception '0367 self-assert FAIL: % client write grant(s)', (select count(*) from public.client_write_grants());
  end if;
  if exists (select 1 from pg_class c where c.oid in ('public.armadas'::regclass, 'public.armada_fleets'::regclass, 'public.armada_voyages'::regclass, 'public.armada_fights'::regclass)
                and not c.relrowsecurity) then
    raise exception '0367 self-assert FAIL: a new table has no row level security';
  end if;
  if (select string_agg(p.provolatile::text, '' order by p.oid::regprocedure::text) from pg_proc p
       where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(array['world.armadas()', 'voyage.armada_side(uuid)', 'voyage.fleet_speed_alone_at(uuid,numeric)', 'public.armada_of(uuid)', 'public.armada_on()']) x))) <> 'sssss' then
    raise exception '0367 self-assert FAIL: a read is not STABLE';
  end if;

  -- ── 7. SELF-ASSERT: OLD = NEW for every fleet in no armada (which is every fleet of this world), bounded by the clock ──
  execute replace(replace(v_speed_old, 'CREATE OR REPLACE FUNCTION voyage.fleet_speed_at(', 'CREATE FUNCTION pg_temp.fleet_speed_old_0367('), 'SECURITY DEFINER', '');
  execute replace(replace(v_haz_old, 'CREATE OR REPLACE FUNCTION voyage.hazard_roll(', 'CREATE FUNCTION pg_temp.hazard_roll_old_0367('), 'SECURITY DEFINER', '');
  v_t := clock_timestamp();
  for v_h in select f.id from public.fleets f where exists (select 1 from public.ships s where s.fleet_id = f.id) order by md5(f.id::text) loop
    exit when clock_timestamp() - v_t > interval '4 seconds';
    v_a := pg_temp.fleet_speed_old_0367(v_h.id, null); v_b := voyage.fleet_speed_at(v_h.id, null);
    if v_a is distinct from v_b or pg_temp.fleet_speed_old_0367(v_h.id, 1) is distinct from voyage.fleet_speed_at(v_h.id, 1)
       or voyage.fleet_speed(v_h.id) is distinct from v_a then
      raise exception '0367 self-assert FAIL: the speed of fleet % moved (% against %)', v_h.id, v_a, v_b;
    end if;
    v_pairs := v_pairs + 1;
  end loop;
  if v_pairs < 1 then
    raise exception '0367 self-assert FAIL: no fleet was there to hold the speed equal on';
  end if;
  -- the cost of the probe, OLD against NEW, interleaved on the fleets just read
  v_n := 0;
  for v_h in select f.id from public.fleets f where exists (select 1 from public.ships s where s.fleet_id = f.id) order by md5(f.id::text) limit 60 loop
    v_t := clock_timestamp(); perform pg_temp.fleet_speed_old_0367(v_h.id, null); v_old_ms := v_old_ms + extract(epoch from clock_timestamp() - v_t) * 1000;
    v_t := clock_timestamp(); perform voyage.fleet_speed_at(v_h.id, null);        v_new_ms := v_new_ms + extract(epoch from clock_timestamp() - v_t) * 1000;
    v_n := v_n + 1;
  end loop;

  -- ── 8. SELF-ASSERT: one probe of this file's own rows, rolled back by the sentinel ──
  begin
    select p.id into v_lis from public.ports p where p.code = 'LIS';
    select p.id into v_fnc from public.ports p where p.code = 'FNC';
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values (c_uid, 'Casa da Armada 0367', (select n.id from public.nations n where n.code = 'PRT'), 500000, false) returning id into v_pl;
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values (c_uid2, 'Casa Vizinha 0367', (select n.id from public.nations n where n.code = 'PRT'), 0, false) returning id into v_other;
    v_f1 := public.form_fleet(v_pl, 'Armada Um 0367', v_lis);
    v_f2 := public.form_fleet(v_pl, 'Armada Dois 0367', v_lis);
    v_fo := public.form_fleet(v_other, 'Vizinha 0367', v_lis);
    perform public.commission_ship(v_pl, v_f1, 'barca', 'Um 0367', true, true);
    perform public.commission_ship(v_pl, v_f2, 'barca', 'Dois 0367', true, true);
    perform public.commission_ship(v_other, v_fo, 'barca', 'Tres 0367', true, true);
    perform set_config('request.jwt.claim.sub', c_uid::text, true);
    perform set_config('request.jwt.claims', json_build_object('sub', c_uid)::text, true);
    if public.current_player_id() is distinct from v_pl then
      raise exception '0367 self-assert FAIL: the probe is not signed in as its house';
    end if;
    select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b.roadstead_lat, b.roadstead_lon)) into v_path
      from public.sea_reaches a, public.sea_reaches b where a.port_id = v_lis and b.port_id = v_fnc;

    -- (a) the read with no armada; every refusal of forming, each leaving nothing
    v_r := world.armadas();
    if not (v_r ->> 'on')::boolean or (v_r ->> 'max')::int <> 6 or v_r -> 'armadas' <> '[]'::jsonb then
      raise exception '0367 self-assert FAIL: the read of a company with no armada: %', v_r;
    end if;
    for v_h in select * from (values
        (jsonb_build_array(v_f1), 'Uma So 0367', 'E_ARMADA_SIZE'), (jsonb_build_array(v_f1, v_f1), 'Dobrada 0367', 'E_ARMADA_SIZE'),
        (jsonb_build_array(v_f1, v_fo), 'Alheia 0367', 'E_NO_SUCH_FLEET'), (jsonb_build_array(v_f1, v_f2), 'ab', 'E_BAD_NAME'),
        (jsonb_build_array(v_f1, v_f2), repeat('x', 25), 'E_BAD_NAME'), ('"nada"'::jsonb, 'Nada 0367', 'E_PARSE'),
        (jsonb_build_array('nao-e-uuid', v_f2), 'Torta 0367', 'E_PARSE')) t(fl, nm, want) loop
      v_r := cmd.armada_form(v_h.fl, v_h.nm);
      if v_r ->> 'error_code' is distinct from v_h.want or exists (select 1 from public.armadas a where a.player_id = v_pl) then
        raise exception '0367 self-assert FAIL: forming "%" answered % and not %', v_h.nm, v_r, v_h.want;
      end if;
    end loop;

    -- (b) formed: the read, the speed of both is the slower's, a fleet of hers does not sail alone
    v_one := jsonb_build_object('f1', voyage.fleet_speed(v_f1), 'f2', voyage.fleet_speed(v_f2));
    v_r := cmd.armada_form(jsonb_build_array(v_f1, v_f2), '  Grande Armada 0367 ');
    v_arm := (v_r ->> 'armada_id')::uuid;
    if not coalesce((v_r ->> 'ok')::boolean, false) or v_arm is null or (select a.name from public.armadas a where a.id = v_arm) <> 'Grande Armada 0367'
       or (select count(*) from public.armada_fleets af where af.armada_id = v_arm) <> 2
       or (select count(*) from public.events e where e.player_id = v_pl and e.kind = 'ARMADA_FORMED') <> 1 then
      raise exception '0367 self-assert FAIL: the armada was not formed: %', v_r;
    end if;
    v_r := world.armadas() -> 'armadas' -> 0;
    if v_r ->> 'state' <> 'PORT' or v_r ->> 'port' <> 'LIS' or v_r -> 'fleets' <> jsonb_build_array(v_f1, v_f2) or (v_r ->> 'flagship')::uuid <> v_f1
       or (v_r ->> 'speed_kn')::numeric <> least((v_one ->> 'f1')::numeric, (v_one ->> 'f2')::numeric) then
      raise exception '0367 self-assert FAIL: the read of the armada in port: %', v_r;
    end if;
    update public.ships set durability = durability * 0.5 where fleet_id = v_f2;   -- the second fleet is the slower now
    if voyage.fleet_speed(v_f1) <> voyage.fleet_speed(v_f2) or voyage.fleet_speed(v_f1) <> voyage.fleet_speed_alone_at(v_f2, null)
       or voyage.fleet_speed_alone_at(v_f1, null) <= voyage.fleet_speed_alone_at(v_f2, null) then
      raise exception '0367 self-assert FAIL: both fleets of an armada do not sail at the slower fleet''s speed';
    end if;
    if cmd.armada_form(jsonb_build_array(v_f1, v_f2), 'Outra 0367') ->> 'error_code' is distinct from 'E_IN_ARMADA' then
      raise exception '0367 self-assert FAIL: a fleet joined a second armada';
    end if;
    v_r := cmd.issue(v_f1, 'SAIL TO FNC', null, v_path);
    if v_r ->> 'error_code' is distinct from 'E_IN_ARMADA' or (select f.status from public.fleets f where f.id = v_f1) <> 'DOCKED' then
      raise exception '0367 self-assert FAIL: a fleet of an armada sailed alone: %', v_r;
    end if;
    perform cmd.clear(v_f1, true);

    -- (c) the one order: refused whole under the fleet's name, then sailed: one path, one speed, one arrival, the lead named
    update public.ships set crew = 0 where fleet_id = v_f2;
    v_r := cmd.armada_sail(v_arm, 'FNC', v_path, false);
    if v_r ->> 'error_code' is distinct from 'E_CREW_SHORT' or v_r ->> 'error_message' not like '%Armada Dois 0367%'
       or exists (select 1 from public.voyages v where v.player_id = v_pl) or exists (select 1 from public.fleets f where f.player_id = v_pl and f.status <> 'DOCKED')
       or (select a.ordering from public.armadas a where a.id = v_arm) then
      raise exception '0367 self-assert FAIL: a refused fleet did not refuse the whole armada under her name: %', v_r;
    end if;
    update public.ships s set crew = c.crew_required from public.ship_classes c where c.id = s.class_id and s.fleet_id = v_f2;
    if cmd.armada_sail(v_arm, 'XXQ', v_path, false) ->> 'error_code' is distinct from 'E_NO_SUCH_PORT'
       or cmd.armada_sail(gen_random_uuid(), 'FNC', v_path, false) ->> 'error_code' is distinct from 'E_NO_SUCH_ARMADA' then
      raise exception '0367 self-assert FAIL: no such port or no such armada is not refused';
    end if;
    v_x := cmd.preview_armada_sail(v_arm, 'FNC', v_path, false);
    if not coalesce((v_x ->> 'ok')::boolean, false) or not (v_x ->> 'dry')::boolean or (v_x ->> 'cost')::bigint < 0
       or exists (select 1 from public.voyages v where v.player_id = v_pl) or exists (select 1 from public.fleets f where f.player_id = v_pl and f.status <> 'DOCKED')
       or (select p.ducats from public.players p where p.id = v_pl) <> 500000 or exists (select 1 from public.armada_voyages) then
      raise exception '0367 self-assert FAIL: a dry run left something, or did not answer: %', v_x;
    end if;
    v_r := cmd.armada_sail(v_arm, 'FNC', v_path, false);
    if (v_r ->> 'cost')::bigint is distinct from (v_x ->> 'cost')::bigint or (v_r ->> 'speed_kn') is distinct from (v_x ->> 'speed_kn')
       or 500000 - (select p.ducats from public.players p where p.id = v_pl) + (v_r ->> 'on_credit')::bigint <> (v_r ->> 'cost')::bigint then
      raise exception '0367 self-assert FAIL: the dry run and the order disagree, or the cost is not what left the purse and what was left owed: % / %', v_x, v_r;
    end if;
    if not coalesce((v_r ->> 'ok')::boolean, false) or jsonb_array_length(v_r -> 'voyages') <> 2
       or (select count(*) from public.voyages v where v.player_id = v_pl and v.status = 'SAILING') <> 2
       or (select count(distinct (v.path::text, v.speed_profile::text, v.eta, v.departed_at, v.total_nm)) from public.voyages v where v.player_id = v_pl) <> 1
       or (select count(*) from public.armada_voyages av where av.lead_voyage_id = (v_r ->> 'lead_voyage_id')::uuid) <> 2
       or (select v.fleet_id from public.voyages v where v.id = (v_r ->> 'lead_voyage_id')::uuid) <> v_f1
       or (select a.ordering from public.armadas a where a.id = v_arm)
       or (v_r ->> 'speed_kn')::numeric <> voyage.fleet_speed_alone_at(v_f2, null) then
      raise exception '0367 self-assert FAIL: the armada did not leave as one: %', v_r;
    end if;
    if world.armadas() -> 'armadas' -> 0 ->> 'state' <> 'SEA' then
      raise exception '0367 self-assert FAIL: an armada at sea does not read SEA';
    end if;
    -- (d) the same sea for both: the sister's roll IS the lead's, every day; and the lead's is what the old body rolls for her
    for v_h in select d, l.id as lead, s.id as sis from generate_series(1, 12) d,
                      (select v.id from public.voyages v where v.fleet_id = v_f1) l, (select v.id from public.voyages v where v.fleet_id = v_f2) s loop
      if (select to_jsonb(x) from voyage.hazard_roll(v_h.sis, v_h.d) x) is distinct from (select to_jsonb(x) from voyage.hazard_roll(v_h.lead, v_h.d) x)
         or (select to_jsonb(x) from voyage.hazard_roll(v_h.lead, v_h.d) x) is distinct from (select to_jsonb(x) from pg_temp.hazard_roll_old_0367(v_h.lead, v_h.d) x) then
        raise exception '0367 self-assert FAIL: day % does not roll the lead''s day for the sister, or the lead''s roll moved', v_h.d;
      end if;
      v_hz := v_hz + 1;
    end loop;
    -- (e) a raid day, fought once, both fleets' hulls on one side against twice the raiders; kept; a named raider is met as she is
    v_x := voyage.armada_fight((select v.id from public.voyages v where v.fleet_id = v_f2), 1, v_f2, null, 10);
    v_y := voyage.armada_fight((select v.id from public.voyages v where v.fleet_id = v_f1), 1, v_f1, null, 10);
    if v_x is null or v_x is distinct from v_y or (v_x ->> 'raider')::numeric <> 20 or (v_x ->> 'fleets')::int <> 2
       or (v_x ->> 'escort')::numeric <> voyage.escort_score(v_f1) + voyage.escort_score(v_f2)
       or (public.combat_bite_on() and (jsonb_array_length(v_x -> 'fight' -> 'log' -> 'you') <> 2 or v_x -> 'fight' -> 'log' -> 'fleets' <> '[["Armada Um 0367", 1], ["Armada Dois 0367", 1]]'::jsonb
                                        or not (v_x -> 'fight' ? 'outcome')))
       or (select count(*) from public.armada_fights g where g.voyage_id = (v_r ->> 'lead_voyage_id')::uuid) <> 1 then
      raise exception '0367 self-assert FAIL: the armada''s raid day is not one fight of both fleets, kept once: % / %', v_x, v_y;
    end if;
    if (voyage.armada_fight((select v.id from public.voyages v where v.fleet_id = v_f1), 2, v_f1, v_fo, 10) ->> 'raider')::numeric <> 10 then
      raise exception '0367 self-assert FAIL: a named raider grew with the armada';
    end if;
    if voyage.armada_fight(gen_random_uuid(), 1, v_fo, null, 10) is not null then
      raise exception '0367 self-assert FAIL: a voyage in no armada was answered a fight';
    end if;
    -- (f) she does not turn alone; disbanded at sea she keeps her schedule and her lead; her fleets are their own again
    if cmd.divert(v_f2, v_lis, null, null) ->> 'error_code' is distinct from 'E_IN_ARMADA' then
      raise exception '0367 self-assert FAIL: a fleet of an armada turned alone';
    end if;
    v_r := cmd.armada_disband(v_arm);
    if not coalesce((v_r ->> 'ok')::boolean, false) or exists (select 1 from public.armadas a where a.player_id = v_pl) or exists (select 1 from public.armada_fleets af where af.fleet_id in (v_f1, v_f2))
       or (select count(*) from public.armada_voyages av join public.voyages v on v.id = av.voyage_id where v.player_id = v_pl) <> 2
       or voyage.fleet_speed(v_f1) <> voyage.fleet_speed_alone_at(v_f1, null)
       or cmd.armada_disband(v_arm) ->> 'error_code' is distinct from 'E_NO_SUCH_ARMADA' then
      raise exception '0367 self-assert FAIL: disbanding at sea: %', v_r;
    end if;
    -- (g) the switch off: forming and sailing refuse
    update public.world_config set value = 'false'::jsonb where key = 'armada_enabled';
    if cmd.armada_form(jsonb_build_array(v_f1, v_f2), 'Escura 0367') ->> 'error_code' is distinct from 'E_NOT_IN_USE' or (world.armadas() ->> 'on')::boolean then
      raise exception '0367 self-assert FAIL: with the switch off an armada can be formed';
    end if;
    raise exception using errcode = 'ZX367', message = 'PROBE_ROLLBACK_0367';
  exception when sqlstate 'ZX367' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0367 self-assert FAIL: the probe did not run to its end';
  end if;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  execute 'drop function pg_temp.fleet_speed_old_0367(uuid, numeric)';
  execute 'drop function pg_temp.hazard_roll_old_0367(uuid, integer)';
  if exists (select 1 from public.players p where p.company_name like 'Casa % 0367' or p.auth_uid in (c_uid, c_uid2))
     or not public.armada_on() or exists (select 1 from public.armadas) or exists (select 1 from public.armada_fleets)
     or exists (select 1 from public.armada_voyages) or exists (select 1 from public.armada_fights) then
    raise exception '0367 self-assert FAIL: the probe left something behind';
  end if;
  if public.current_player_id() is not null then
    raise exception '0367 self-assert FAIL: the probe''s identity outlived its rollback';
  end if;
  -- THE NEWS (0347's law): one UPDATE row, outside the probe, idempotent by its number.
  perform public.news_update('0367', 'Armadas', '대함대');
  if clock_timestamp() - v_t0 > interval '40 seconds' then
    raise exception '0367 self-assert FAIL: the file took % (budget 40 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0367 cost: a fleet''s speed, OLD and NEW interleaved on % fleets of this world: OLD % ms a read, NEW % ms a read.',
    v_n, case when v_n > 0 then round(v_old_ms / v_n, 3) end, case when v_n > 0 then round(v_new_ms / v_n, 3) end;
  raise notice '0367 self-assert ok: AN ARMADA SAILS AS ONE, lit. 13 functions (1 read and 4 doors for a client), 4 tables, 3 new knobs and no old one moved; % hunks once each and reversing, and the speed''s body moved whole; speed held equal on % fleets in no armada; % days rolled the lead''s day; the probe formed, sailed, fought as one side, disbanded and rolled back. No other function moved. % ms.',
    (select count(*) from hunks_0367), v_pairs, v_hz, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0367;
end
$m$;
