-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0333 — THE NAVY COMES: a battle calls its country's ships, they sail for real, and they join only if they get there in time. DARK
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- Owner rows 285, 286, slice W13 of docs/WORLD_POWERS.md (5.2, 6.4): *"if a fight is made in pacifics, it would need a longer time for the navy to defend, which the fight whould be finished before arrival"*; owner: players may attack navy ships.
-- This slice opens nothing. It needs two switches the owner has not lit: `attack_enabled` (no battle of kind ATTACK opens without it) and `navy_enabled` (no ship exists without it).
--
-- THE CALL, at a battle's start (public.navy_call, from public.battle_open, kind ATTACK only). The country of the ship set upon answers:
--   ESCORT   A ship escorting that very ship is on the sheet at once (arrives_at = joined_at) and is held, as the two who started it (public.battle_stop).
--   CALLED   Her country's other ships on duty, the soonest first, at most navy_call_ships, make for the harbour nearest the site (public.harbour_nearest). If none can be there in time, the soonest one sails anyway: she is the late ship.
-- A CALL IS A REAL VOYAGE. A ship in port sails now, through public.navy_sail, as every leg of hers. A ship at sea FINISHES HER LEG and sails from there: nothing here turns a ship, so no voyage is cut and DESIGN D.2 holds.
--   public.navy_arrival is the one reading of when a called ship is there: at the call, and again when the battle closes.
-- THE JOIN RULE, one line: a side is on the sheet if arrives_at <= resolves_at. public.battle_sides_come re-reads every called ship at the close, after settling her, so a storm that delayed her counts and an estimate never does:
--   a ship a minute past the clock is not in the fight. She stays on public.battle_sides as the record of who came late, and she sails on.
-- AT THE END (public.navy_close, from public.battle_resolve): every called ship is freed, and the report says who came.
-- WANTED IS W14's, ALL OF IT: 0334 (branch `wanted`, read for this file) owns public.wanted, public.wanted_mark and the decision, its one hunk in public.attack_close: she won, or public.navy_arrived finds no ship in time. This file writes neither, and it fills what that reads:
--   a called ship's public.battle_sides line, arrives_at re-read at the close. To keep that hunk valid the `return` line of public.attack_close is left as it is, and c.nation_id is her country for a navy ship too, so a mark needs no second reading.
-- NO SHIP IS COUNTED TWICE. navy_ships.battle_id holds one battle, so she answers one call; a ship with a battle_id is not called, not escorted in, and cannot be attacked (E_FLEET_BUSY). public.battle_sides' key keeps her once on a sheet.
--
-- ESCORT (6.4): public.navy_escort_step. While funds are at sea, the last ship of a realm's line on duty (navy_escorts ships, default 1, so a capital's own first station stays manned) sails for the port the richest cargo ship of her country
--   is bound for, leg after leg, one leg behind. No such ship at sea: she goes back to patrol. She is mended free in her own country's harbours.
--
-- ATTACKING A NAVY SHIP (owner: yes. docs/WORLD_POWERS.md 4.2's build note left it for W13 or W14, W14's row does not own it, so it is here): public.attack_for takes kind NAVY. Regard regard_attack_navy, reason ATTACK_NAVY. Her limit is attack_ship_minutes,
--   not a lap: she has none. A navy ship carries no gold, so public.loot_take finds nothing. Her card serves `attack` while attacks are lit, as a cargo ship's does.
--
-- WHY ONE ATTACK CLOSE STILL NAMES ONE DEFENDER: gold and hands are the ship set upon's (`how` = OPENED). Hulls are the fight's, every side. A sink's regard and a wreck now run over every defender on the sheet.
--
-- THE RE-CUTS (hunks of the live bodies, read on the world at head 0331; 0332 cuts none of them), each occurs once and reverses to its pre-image; these supersede the same lines of 0323, 0327 and 0331:
--   public.battle_open (2):     the side's stop is lifted into public.battle_stop, same statements; kind ATTACK calls the navy.
--   public.battle_resolve (3):  the sides read are those on the sheet, after public.battle_sides_come; public.navy_close at an attack's end; the report takes the navy's line.
--   public.attack_for (6):      kind NAVY, public.crown_nation, her limit, her regard, what the preview says of the navy.
--   public.attack_close (4):    the ship set upon is `how` OPENED; her country is public.crown_nation; the sink runs over every defender on the sheet.
--   public.navy_ship_step (2):  on-duty lifted into public.navy_on_duty, same statement; a called ship and the escort step first.
--   world.navy_ship_card (1):   `attack`, while attacks are lit.
--   world.fleets (1):           `navy_at`, for a fleet in a battle a ship will reach. Absent otherwise, so every other fleet reads byte for byte as before.
--
-- NEW: battle_sides.how; navy_ships.battle_id, called_to, escort_of; missions ESCORT and REINFORCE. Knobs navy_call_ships, navy_escorts, regard_attack_navy, attack_ship_minutes.
--
-- DARK IS BYTE-IDENTICAL: kind PROBE never calls; every OPENED side has arrives_at = joined_at, so the sheet is the old list in the old order; public.navy_ships is empty, so public.navy_ship_step never runs; a free fleet reads {} in world.fleets without a query.
--   Parity is proved: scripts/ops/harness/navy-comes/dark-scene.sql beside the rich-cities, armed-cargo and navy scenes, before and after this file, every line equal.
--
-- DECIDED BY DEFAULT (owner may reverse): docs/dev-log/2026-11-06-the-navy-comes.md lists them all.
--
-- SELF-ASSERT: the catalog and stable reads only: hunks once and reversing; ACL, volatility and config unmoved; no other function, knob or job; the switches off; no row written.
-- THIS FILE RUNS NO GAME STEP, in every environment (docs/OPS_HEALTH.md section 4). THE LIVE PATHS ARE PROVED IN CI: proof 40, scripts/db/proofs/40_the_navy_comes.sql. Mutation controls: scripts/ops/harness/navy-comes/proof-0333.mjs (local).
--
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 45 s, lock_timeout 5 s first. Self-assert fails above 45 s.
-- ROLLBACK (forward, a NEW migration, owner only): `navy_enabled` false: a battle has no reinforcement, and a ship already called sails on and is freed at the close. `navy_escorts` 0: no escort. To remove: swap this file's old and new, then drop what it created.
-- VERSION: 0333 - follows 0332 (#538), which cuts world.snapshot and world.building_yard only. 0334 (W14) applies on top, its hunks unmoved: scripts/ops/harness/navy-comes/proof-0333.mjs --w14= applies both and runs proofs 40 and 41.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0   timestamptz := clock_timestamp();
  v_h    record;
  v_def  text;
  v_pre  text;
  v_n    int;
  v_fn_before    text;
  v_cfg_before   text;
  v_meta_before  text;
  v_cron_before  text;
  v_cron_after   text;
  c_keys constant text[] := array['navy_call_ships', 'navy_escorts', 'regard_attack_navy', 'attack_ship_minutes'];
  c_new_fns constant text[] := array[
    'public.crown_nation(uuid)', 'public.harbour_nearest(double precision,double precision)', 'public.navy_on_duty(uuid,integer,timestamp with time zone)',
    'public.navy_leg_seconds(uuid,uuid,uuid)', 'public.navy_arrival(uuid,uuid,timestamp with time zone,timestamp with time zone)', 'public.battle_stop(uuid,timestamp with time zone,timestamp with time zone)',
    'public.navy_reinforce(uuid,uuid,timestamp with time zone)', 'public.navy_call(uuid,uuid,timestamp with time zone,timestamp with time zone)', 'public.battle_sides_come(uuid,timestamp with time zone)',
    'public.navy_close(uuid,timestamp with time zone)', 'public.battle_navy_served(uuid)',
    'public.navy_escort_step(uuid,uuid,boolean,timestamp with time zone)'];
  c_hunked constant text[] := array[
    'public.battle_open(text,uuid,uuid,timestamp with time zone)', 'public.battle_resolve(uuid,timestamp with time zone)', 'public.attack_for(uuid,uuid,uuid,integer,timestamp with time zone)',
    'public.attack_close(uuid,jsonb,timestamp with time zone)', 'public.navy_ship_step(uuid,timestamp with time zone)', 'world.navy_ship_card(uuid)', 'world.fleets()'];
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('public.navy_call(uuid,uuid,timestamp with time zone,timestamp with time zone)') is not null
     or exists (select 1 from public.world_config c where c.key = any (c_keys))
     or exists (select 1 from pg_attribute a where a.attrelid = 'public.battle_sides'::regclass and a.attname = 'how') then
    raise exception '0333 refuses: something of it is already in this world';
  end if;
  if to_regclass('public.navy_ships') is null or to_regprocedure('public.attack_for(uuid,uuid,uuid,integer,timestamp with time zone)') is null then
    raise exception '0333 refuses: 0327 or 0331 is not in this world';
  end if;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked) x));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before
    from public.world_config c;
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
    into v_meta_before
    from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked) x));
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.command || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_cron_before;
  end if;

  -- ── 1. THE KNOBS AND THE COLUMNS (all new; no existing key is touched) ──
  insert into public.world_config (key, value, description) values
    ('navy_call_ships', to_jsonb(3), '0333: the most ships of a country that answer one battle''s call (public.navy_call). An escort on the ship set upon comes on top.'),
    ('navy_escorts', to_jsonb(1), '0333: ships of a realm on escort while funds are at sea, the last of its line on duty. 0: none (public.navy_escort_step).'),
    ('regard_attack_navy', to_jsonb(-250), '0333: regard with her country for attacking one of its navy ships (docs/WORLD_POWERS.md 4.2).'),
    ('attack_ship_minutes', to_jsonb(60), '0333: a ship that has no lap, as a navy ship, is attacked once in this many minutes (docs/WORLD_POWERS.md 4.2).');

  alter table public.battle_sides add column how text not null default 'OPENED' check (how in ('OPENED', 'ESCORT', 'CALLED'));
  comment on column public.battle_sides.how is '0333: how she came to the battle. OPENED: she started it or was set upon. ESCORT: she was escorting the ship set upon. CALLED: she was sent for, and arrives_at says when: public.battle_sides_come re-reads it at the close, ''infinity'' for a ship that never got there.';

  alter table public.navy_ships
    add column battle_id uuid references public.battles(id) on delete set null,
    add column called_to uuid references public.ports(id),
    add column escort_of uuid references public.fleets(id) on delete set null;
  comment on column public.navy_ships.battle_id is '0333: the one battle she is in or bound for. One column, so she answers one call. public.navy_close frees her.';
  comment on column public.navy_ships.called_to is '0333: the harbour a call sent her to, while mission is REINFORCE.';
  comment on column public.navy_ships.escort_of is '0333: the cargo ship she follows, while mission is ESCORT.';

  -- ── 2. THE NEW FUNCTIONS ──
  execute $f$
create function public.crown_nation(p_fleet uuid)
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0333: THE country a crown's ship sails for: a cargo ship's or a navy ship's. Null for any other fleet.
  select coalesce((select c.nation_id from public.cargo_ships c where c.fleet_id = p_fleet),
                  (select n.nation_id from public.navy_ships n where n.fleet_id = p_fleet))
$$
  $f$;

  execute $f$
create function public.harbour_nearest(p_lat double precision, p_lon double precision)
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0333: the open harbour nearest a point of sea, as the crow flies, ties by code: where a call sends a ship. Only a harbour public.sea_reaches knows: a ship must be able to sail there.
  select p.id
    from public.ports p join public.sea_reaches r on r.port_id = p.id
   where p.kind = 'HARBOUR' and not p.is_ice_closed
   order by voyage.gc_distance_nm(p_lat, p_lon, p.lat, p.lon), p.code
   limit 1
$$
  $f$;

  execute $f$
create function public.navy_on_duty(p_nation uuid, p_ord integer, p_unpaid timestamptz)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0333: ON DUTY: the switch is on, she is paid, and her ord is inside her country's number. public.navy_ship_step's own line, lifted.
  select public.navy_on() and p_unpaid is null and p_ord <= public.navy_size_of(p_nation)
$$
  $f$;

  execute $f$
create function public.navy_leg_seconds(p_fleet uuid, p_from uuid, p_to uuid)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0333: real seconds for this fleet from one harbour to another, by the sailed distance (voyage.reach_from, the figure every quote reads) at her speed and the clock's compression. 0 for the same harbour. Null beyond navy_reach_nm: out of a call's reach.
  select case when p_from = p_to then 0::numeric
              else (select r.nm from voyage.reach_from(p_from) r where r.port_id = p_to and r.nm <= public.wc_num('navy_reach_nm'))
                   / nullif(voyage.fleet_speed(p_fleet), 0) * 3600 / public.wc_num('time_compression') end
$$
  $f$;

  execute $f$
create function public.navy_arrival(p_fleet uuid, p_to uuid, p_since timestamptz, p_now timestamptz)
returns timestamptz
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0333: THE one reading of when a called ship is at p_to. Bound there: her voyage's eta. At sea for another port: she finishes her leg, then sails. In port elsewhere: she leaves when her port time ends. There already: when she came, or p_since if she lay
-- there all along. Null: she cannot get there (out of reach, a wreck, nowhere). The caller settles her first.
declare
  f  public.fleets%rowtype;
  v  public.voyages%rowtype;
  v_s numeric;
begin
  select * into f from public.fleets x where x.id = p_fleet;
  select * into v from public.voyages x where x.fleet_id = p_fleet and x.status = 'SAILING';
  if v.id is not null then
    if v.dest_port_id = p_to then
      return v.eta;
    end if;
    v_s := public.navy_leg_seconds(p_fleet, v.dest_port_id, p_to);
    return greatest(v.eta, p_now) + make_interval(secs => v_s::double precision);
  end if;
  if f.status not in ('DOCKED', 'IN_BATTLE') or f.port_id is null then
    return null;
  end if;
  if f.port_id = p_to then
    return coalesce((select max(x.eta) from public.voyages x where x.fleet_id = p_fleet and x.dest_port_id = p_to and x.status = 'ARRIVED' and x.eta >= p_since), p_since);
  end if;
  v_s := public.navy_leg_seconds(p_fleet, f.port_id, p_to);
  return greatest(p_now, coalesce(f.ready_at, p_now)) + make_interval(secs => v_s::double precision);
end
$$
  $f$;

  execute $f$
create function public.battle_stop(p_fleet uuid, p_until timestamptz, p_now timestamptz)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0333: A SIDE STOPS FOR A BATTLE: a sailing fleet is held (voyage.hold), one in port or at anchor goes IN_BATTLE. public.battle_open's own lines, lifted, so an escort stops as the two who started it do.
begin
  if (select f.status from public.fleets f where f.id = p_fleet) = 'SAILING' then
    perform voyage.hold(p_fleet, p_until, p_now);
  else
    update public.fleets set status = 'IN_BATTLE', busy_until = p_until, version = version + 1 where id = p_fleet;
  end if;
end
$$
  $f$;

  execute $f$
create function public.navy_reinforce(p_fleet uuid, p_port uuid, p_now timestamptz)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0333: A CALLED SHIP IN PORT. At the harbour she was sent to, she waits for the battle to close (CALLED). Elsewhere she sails there, through public.navy_sail, and her side's arrives_at becomes her voyage's eta (SAILED). No course reaches it: she is
-- freed and never gets there (IDLE). The caller holds her fleet row.
declare
  n      public.navy_ships%rowtype;
  v_leg  jsonb;
begin
  select * into n from public.navy_ships x where x.fleet_id = p_fleet;
  if p_port = n.called_to then
    return 'CALLED';
  end if;
  v_leg := public.cargo_circuit_plan(n.nation_id, p_port, n.called_to) #> '{legs,0}';
  if v_leg is null then
    update public.battle_sides bs set arrives_at = 'infinity' where bs.battle_id = n.battle_id and bs.fleet_id = p_fleet;
    update public.navy_ships x set mission = 'PATROL', called_to = null, battle_id = null where x.fleet_id = p_fleet;
    return 'IDLE';
  end if;
  perform public.navy_sail(p_fleet, p_port, voyage.segments_from_course(v_leg -> 'course'), n.called_to, null, 0, p_now);
  update public.battle_sides bs set arrives_at = v.eta
    from public.voyages v
   where bs.battle_id = n.battle_id and bs.fleet_id = p_fleet and v.fleet_id = p_fleet and v.status = 'SAILING';
  return 'SAILED';
end
$$
  $f$;

  execute $f$
create function public.navy_call(p_battle uuid, p_defender uuid, p_until timestamptz, p_now timestamptz)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0333: A BATTLE CALLS HER COUNTRY'S SHIPS, once, at its start (docs/WORLD_POWERS.md 5.2, 6.4). The ship set upon, if she is a navy ship, takes the battle's id first, whatever the switch. Off: no call. Then her escort joins at once, then the soonest of the
-- ships on duty, at most navy_call_ships; past the clock, one ship only sails, the late one. Each ship is taken with SKIP LOCKED, so a press never waits on the job: a ship the job holds just does not answer. Settled before she is read (D.2). Answers the ships that answered.
declare
  v_nation uuid := public.crown_nation(p_defender);
  v_max    int := public.wc_int('navy_call_ships');
  v_to     uuid;
  v_at     timestamptz;
  v_n      int := 0;
  v_k      int := 0;
  v_f      public.fleets%rowtype;
  r        record;
begin
  update public.navy_ships n set battle_id = p_battle where n.fleet_id = p_defender;
  if v_nation is null or not public.navy_on() then
    return 0;
  end if;

  for r in select n.fleet_id
             from public.navy_ships n join public.fleets f on f.id = n.fleet_id
            where n.escort_of = p_defender and n.mission = 'ESCORT' and n.laid_up_at is null and n.battle_id is null
              and f.busy_until is null and f.status in ('DOCKED', 'SAILING')
            order by n.ord loop
    perform 1 from public.fleets x where x.id = r.fleet_id for update skip locked;
    continue when not found;
    perform voyage.settle(r.fleet_id, p_now);
    continue when (select x.status from public.fleets x where x.id = r.fleet_id) not in ('DOCKED', 'SAILING')
               or not exists (select 1 from public.ships s where s.fleet_id = r.fleet_id and s.durability > 0);
    perform public.battle_stop(r.fleet_id, p_until, p_now);
    insert into public.battle_sides (battle_id, fleet_id, side, joined_at, arrives_at, how) values (p_battle, r.fleet_id, 'DEFENDER', p_now, p_now, 'ESCORT');
    update public.navy_ships n set battle_id = p_battle where n.fleet_id = r.fleet_id;
    v_n := v_n + 1;
  end loop;

  v_to := (select public.harbour_nearest((b.site ->> 'lat')::double precision, (b.site ->> 'lon')::double precision) from public.battles b where b.id = p_battle);
  if v_to is null then
    return v_n;
  end if;
  for r in select n.fleet_id, n.ord, a.at
             from public.navy_ships n
             join public.fleets f on f.id = n.fleet_id
            cross join lateral (select public.navy_arrival(n.fleet_id, v_to, p_now, p_now) as at) a
            where n.nation_id = v_nation and n.laid_up_at is null and n.battle_id is null and a.at is not null
              and f.busy_until is null and f.status in ('DOCKED', 'SAILING')
              and public.navy_on_duty(n.nation_id, n.ord, n.unpaid_since)
              and exists (select 1 from public.ships s where s.fleet_id = n.fleet_id and s.durability > 0)
            order by a.at, n.ord loop
    exit when v_k >= v_max or (v_k > 0 and r.at > p_until);
    perform 1 from public.fleets x where x.id = r.fleet_id for update skip locked;
    continue when not found;
    perform voyage.settle(r.fleet_id, p_now);
    v_at := public.navy_arrival(r.fleet_id, v_to, p_now, p_now);
    continue when v_at is null;
    select * into v_f from public.fleets x where x.id = r.fleet_id;
    update public.navy_ships n set mission = 'REINFORCE', called_to = v_to, battle_id = p_battle where n.fleet_id = r.fleet_id;
    insert into public.battle_sides (battle_id, fleet_id, side, joined_at, arrives_at, how) values (p_battle, r.fleet_id, 'DEFENDER', p_now, v_at, 'CALLED');
    if v_f.status = 'DOCKED' and v_f.port_id <> v_to and (v_f.ready_at is null or v_f.ready_at <= p_now) then
      perform public.navy_reinforce(r.fleet_id, v_f.port_id, p_now);
    end if;
    v_k := v_k + 1;
  end loop;
  return v_n + v_k;
end
$$
  $f$;

  execute $f$
create function public.battle_sides_come(p_battle uuid, p_now timestamptz)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0333: WHO GOT THERE. At the close, each called ship is settled to the instant and her arrival read again, so a storm on the way counts and the call's estimate does not. 'infinity': she never will. After this, arrives_at is the join rule's one input.
declare
  s record;
begin
  for s in select bs.fleet_id, bs.joined_at from public.battle_sides bs where bs.battle_id = p_battle and bs.how = 'CALLED' order by bs.fleet_id loop
    perform voyage.settle(s.fleet_id, p_now);
    update public.battle_sides bs
       set arrives_at = coalesce(public.navy_arrival(s.fleet_id, n.called_to, s.joined_at, p_now), 'infinity')
      from public.navy_ships n
     where bs.battle_id = p_battle and bs.fleet_id = s.fleet_id and n.fleet_id = s.fleet_id and n.battle_id = p_battle;
  end loop;
end
$$
  $f$;

  execute $f$
create function public.navy_close(p_battle uuid, p_now timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0333: WHAT THE NAVY DID, at a battle's end, under its lock. Frees every ship tied to the battle, the late ones too: they sail on. Answers {navy: {came, late, line}}, which the battle's result and the report take. WANTED is 0334's, from the same lines of public.battle_sides.
declare
  v_came int;
  v_late int;
  v_here boolean;
begin
  select count(*) filter (where bs.how <> 'OPENED' and bs.arrives_at <= b.resolves_at),
         count(*) filter (where bs.how = 'CALLED' and bs.arrives_at > b.resolves_at),
         bool_or(bs.how <> 'OPENED' and bs.arrives_at <= b.resolves_at or (bs.how = 'OPENED' and bs.side = 'DEFENDER' and n.fleet_id is not null))
    into v_came, v_late, v_here
    from public.battle_sides bs join public.battles b on b.id = bs.battle_id
    left join public.navy_ships n on n.fleet_id = bs.fleet_id
   where bs.battle_id = p_battle;
  update public.navy_ships n set mission = case when n.escort_of is not null then 'ESCORT' else 'PATROL' end, called_to = null, battle_id = null where n.battle_id = p_battle;
  return jsonb_build_object('navy', jsonb_build_object('came', v_came, 'late', v_late,
    'line', case when v_came > 0 then 'The navy came up before it ended.'
                 when v_late > 0 then 'The navy came too late.'
                 when v_here then 'Her country''s ship fought alone.'
                 else 'No navy came.' end));
end
$$
  $f$;

  execute $f$
create function public.battle_navy_served(p_fleet uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0333: FOR A FLEET THAT STARTED A BATTLE: when the first help reaches the other side in time, or {} with none. Read by world.fleets (the card's clock) and public.attack_for (the preview).
  select coalesce((select jsonb_build_object('navy_at', min(o.arrives_at))
                     from public.battle_sides me
                     join public.battles b on b.id = me.battle_id and b.status = 'FIGHTING'
                     join public.battle_sides o on o.battle_id = b.id and o.how <> 'OPENED' and o.arrives_at <= b.resolves_at
                    where me.fleet_id = p_fleet and me.side = 'ATTACKER'
                   having count(*) > 0), '{}'::jsonb)
$$
  $f$;

  execute $f$
create function public.navy_escort_step(p_fleet uuid, p_port uuid, p_duty boolean, p_now timestamptz)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0333: ESCORT, what the last ship of a realm's line does in port (docs/WORLD_POWERS.md 6.4). While a cargo ship of her country is at sea with funds, she sails for the port the richest one is bound for: one leg behind. The caller holds her fleet row.
-- Answers ESCORT, or null when she is no escort: public.navy_ship_step then goes on with her patrol. She is mended free in her own country's harbours: she may not see her station.
declare
  n       public.navy_ships%rowtype;
  v_ward  uuid;
  v_to    uuid;
  v_leg   jsonb;
begin
  select * into n from public.navy_ships x where x.fleet_id = p_fleet;
  if p_duty and n.ord > coalesce((select max(x.ord) from public.navy_ships x
                                   where x.nation_id = n.nation_id and x.laid_up_at is null and public.navy_on_duty(x.nation_id, x.ord, x.unpaid_since)), 0) - public.wc_int('navy_escorts') then
    select c.fleet_id, v.dest_port_id into v_ward, v_to
      from public.cargo_ships_in_service c
      join public.voyages v on v.fleet_id = c.fleet_id and v.status = 'SAILING' and v.dest_port_id is not null
     cross join lateral public.cargo_ship_aboard(c.fleet_id) a
     where c.nation_id = n.nation_id
     order by a.aboard desc, c.fleet_id
     limit 1;
  end if;
  if v_ward is not null and v_to <> p_port then
    v_leg := public.cargo_circuit_plan(n.nation_id, p_port, v_to) #> '{legs,0}';
  end if;
  if v_ward is null or (v_to <> p_port and v_leg is null) then
    if n.mission = 'ESCORT' then
      update public.navy_ships x set mission = 'PATROL', escort_of = null where x.fleet_id = p_fleet;
    end if;
    return null;
  end if;
  if coalesce(public.port_nation(p_port) = n.nation_id, false) then
    perform public.fleet_mend(p_fleet);
  end if;
  update public.navy_ships x set mission = 'ESCORT', escort_of = v_ward where x.fleet_id = p_fleet;
  if v_leg is not null then
    perform public.navy_sail(p_fleet, p_port, voyage.segments_from_course(v_leg -> 'course'), v_to, null, 0, p_now);
  end if;
  return 'ESCORT';
end
$$
  $f$;

  revoke all on function public.crown_nation(uuid) from public, anon, authenticated;
  revoke all on function public.harbour_nearest(double precision, double precision) from public, anon, authenticated;
  revoke all on function public.navy_on_duty(uuid, integer, timestamptz) from public, anon, authenticated;
  revoke all on function public.navy_leg_seconds(uuid, uuid, uuid) from public, anon, authenticated;
  revoke all on function public.navy_arrival(uuid, uuid, timestamptz, timestamptz) from public, anon, authenticated;
  revoke all on function public.battle_stop(uuid, timestamptz, timestamptz) from public, anon, authenticated;
  revoke all on function public.navy_reinforce(uuid, uuid, timestamptz) from public, anon, authenticated;
  revoke all on function public.navy_call(uuid, uuid, timestamptz, timestamptz) from public, anon, authenticated;
  revoke all on function public.battle_sides_come(uuid, timestamptz) from public, anon, authenticated;
  revoke all on function public.navy_close(uuid, timestamptz) from public, anon, authenticated;
  revoke all on function public.battle_navy_served(uuid) from public, anon, authenticated;
  revoke all on function public.navy_escort_step(uuid, uuid, boolean, timestamptz) from public, anon, authenticated;

  -- ── 3. THE HUNKS (each occurs exactly once in the live body, and reverses) ──
  create temp table hunks_0333 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0333 values
  ('public.battle_open(text,uuid,uuid,timestamp with time zone)', 1,
$h$    if (select f.status from public.fleets f where f.id = v_fleet) = 'SAILING' then
      perform voyage.hold(v_fleet, v_until, p_now);
    else
      update public.fleets set status = 'IN_BATTLE', busy_until = v_until, version = version + 1 where id = v_fleet;
    end if;
$h$,
$h$    perform public.battle_stop(v_fleet, v_until, p_now);   -- 0333: lifted, so an escort stops the same way
$h$),
  ('public.battle_open(text,uuid,uuid,timestamp with time zone)', 2,
$h$  end loop;
  return v_id;
$h$,
$h$  end loop;
  if p_kind = 'ATTACK' then   -- 0333: her country answers; a probe calls nobody
    perform public.navy_call(v_id, p_defender, v_until, p_now);
  end if;
  return v_id;
$h$),
  ('public.battle_resolve(uuid,timestamp with time zone)', 1,
$h$  for s in select bs.fleet_id, bs.side from public.battle_sides bs where bs.battle_id = p_battle order by bs.joined_at, bs.fleet_id loop
$h$,
$h$  -- 0333: THE JOIN RULE: on the sheet if arrives_at <= resolves_at, and public.battle_sides_come has just read that for every called ship. A late ship stays on the list as the record, out of the fight.
  perform public.battle_sides_come(p_battle, p_now);
  for s in select bs.fleet_id, bs.side from public.battle_sides bs where bs.battle_id = p_battle and bs.arrives_at <= b.resolves_at order by bs.joined_at, bs.how = 'CALLED', bs.how = 'ESCORT', bs.fleet_id loop
$h$),
  ('public.battle_resolve(uuid,timestamp with time zone)', 2,
$h$    v_spoils := public.attack_close(p_battle, v_f, p_now);
$h$,
$h$    v_spoils := public.attack_close(p_battle, v_f, p_now) || public.navy_close(p_battle, p_now);   -- 0333: the ships called are freed, and the report says who came
$h$),
  ('public.battle_resolve(uuid,timestamp with time zone)', 3,
$h$      v_rep := public.battle_words(v_f, v_b);
$h$,
$h$      v_rep := public.battle_words(v_f, v_b);
      if v_spoils ? 'navy' then   -- 0333: the report says who came
        v_rep := jsonb_set(v_rep, '{lines}', (v_rep -> 'lines') || (v_spoils #> '{navy,line}'));
      end if;
$h$),
  ('public.attack_for(uuid,uuid,uuid,integer,timestamp with time zone)', 1,
$h$  v_battle uuid;
begin$h$,
$h$  v_battle uuid;
  v_nation uuid;   -- 0333: public.crown_nation: a cargo ship's or a navy ship's
begin$h$),
  ('public.attack_for(uuid,uuid,uuid,integer,timestamp with time zone)', 2,
$h$  if v_kind <> 'CARGO_SHIP' then$h$,
$h$  if v_kind not in ('CARGO_SHIP', 'NAVY') then   -- 0333: owner: players may attack navy ships$h$),
  ('public.attack_for(uuid,uuid,uuid,integer,timestamp with time zone)', 3,
$h$  select * into c from public.cargo_ships x where x.fleet_id = p_target;

  if c.nation_id is not distinct from (select pl.nation_id from public.players pl where pl.id = p_player) then$h$,
$h$  select * into c from public.cargo_ships x where x.fleet_id = p_target;
  v_nation := public.crown_nation(p_target);

  if v_nation is not distinct from (select pl.nation_id from public.players pl where pl.id = p_player) then$h$),
  ('public.attack_for(uuid,uuid,uuid,integer,timestamp with time zone)', 4,
$h$  if d.status = 'IN_BATTLE' or d.busy_until is not null then$h$,
$h$  if d.status = 'IN_BATTLE' or d.busy_until is not null
     or exists (select 1 from public.navy_ships n where n.fleet_id = p_target and n.battle_id is not null) then   -- 0333: a ship answering a call answers one thing$h$),
  ('public.attack_for(uuid,uuid,uuid,integer,timestamp with time zone)', 5,
$h$  if c.last_attacked_lap is not distinct from coalesce(c.out_load, 0) then
    perform cmd.refuse('E_SHIP_FOUGHT_THIS_LAP', format('%s has fought this lap', d.name));
  end if;$h$,
$h$  if v_kind = 'CARGO_SHIP' and c.last_attacked_lap is not distinct from coalesce(c.out_load, 0) then
    perform cmd.refuse('E_SHIP_FOUGHT_THIS_LAP', format('%s has fought this lap', d.name));
  end if;
  if v_kind = 'NAVY' and exists (select 1 from public.battle_sides bs join public.battles b on b.id = bs.battle_id
                                  where bs.fleet_id = p_target and bs.side = 'DEFENDER' and b.kind = 'ATTACK'
                                    and bs.joined_at > p_now - make_interval(mins => public.wc_int('attack_ship_minutes'))) then
    perform cmd.refuse('E_SHIP_FOUGHT_THIS_LAP', format('%s fought within %s minutes', d.name, public.wc_int('attack_ship_minutes')));   -- 0333: she has no lap
  end if;$h$),
  ('public.attack_for(uuid,uuid,uuid,integer,timestamp with time zone)', 6,
$h$  perform public.regard_add(p_player, c.nation_id, public.wc_num('regard_attack_cargo'), 'ATTACK_CARGO');
  return jsonb_build_object('battle_id', v_battle, 'fleet', a.name, 'target', d.name, 'nm', round(v_nm),
    'nation', (select n.code from public.nations n where n.id = c.nation_id),$h$,
$h$  perform public.regard_add(p_player, v_nation, public.wc_num(case when v_kind = 'NAVY' then 'regard_attack_navy' else 'regard_attack_cargo' end),
                             case when v_kind = 'NAVY' then 'ATTACK_NAVY' else 'ATTACK_CARGO' end);
  return coalesce((select jsonb_build_object('navy_minutes', greatest(1, ceil(extract(epoch from (public.battle_navy_served(p_fleet) ->> 'navy_at')::timestamptz - p_now) / 60)))
                    where public.battle_navy_served(p_fleet) ? 'navy_at'), '{}'::jsonb)   -- 0333: "Navy arrives in about 6 min", when one would
    || jsonb_build_object('battle_id', v_battle, 'fleet', a.name, 'target', d.name, 'nm', round(v_nm),
    'nation', (select n.code from public.nations n where n.id = v_nation),$h$),
  ('public.attack_close(uuid,jsonb,timestamp with time zone)', 1,
$h$  v_lost    bigint := 0;
begin$h$,
$h$  v_lost    bigint := 0;
  v_s       uuid;      -- 0333: each defender on the sheet
begin$h$),
  ('public.attack_close(uuid,jsonb,timestamp with time zone)', 2,
$h$  select bs.fleet_id into v_d from public.battle_sides bs where bs.battle_id = p_battle and bs.side = 'DEFENDER';
$h$,
$h$  select bs.fleet_id into v_d from public.battle_sides bs where bs.battle_id = p_battle and bs.side = 'DEFENDER' and bs.how = 'OPENED';   -- 0333: the ship set upon: others may have joined
$h$),
  ('public.attack_close(uuid,jsonb,timestamp with time zone)', 3,
$h$  select * into c from public.cargo_ships x where x.fleet_id = v_d;

  if v_out in ('PLUNDERED', 'RANSOM') then$h$,
$h$  select * into c from public.cargo_ships x where x.fleet_id = v_d;
  c.nation_id := public.crown_nation(v_d);   -- 0333: a navy ship's country too: every line below reads c

  if v_out in ('PLUNDERED', 'RANSOM') then$h$),
  ('public.attack_close(uuid,jsonb,timestamp with time zone)', 4,
$h$  if exists (select 1 from public.ships s where s.fleet_id = v_d)
     and not exists (select 1 from public.ships s where s.fleet_id = v_d and s.durability > 0) then
    perform public.regard_add(v_a.player_id, c.nation_id, public.wc_num('regard_sink'), 'SINK_CARGO');
    if public.npc_wrecked(v_d) then
      select * into v_voyage from public.voyages v where v.fleet_id = v_d and v.status = 'SAILING';
      perform voyage.npc_wreck(v_d, v_voyage.id, v_voyage.last_settled_day + 1);
    end if;
  end if;
$h$,
$h$  -- 0333: every defender on the sheet. A ship sunk in port has no voyage: her step finds her there, as any wreck in port.
  for v_s in select bs.fleet_id from public.battle_sides bs join public.battles b on b.id = bs.battle_id
              where bs.battle_id = p_battle and bs.side = 'DEFENDER' and bs.arrives_at <= b.resolves_at order by bs.fleet_id loop
    if exists (select 1 from public.ships s where s.fleet_id = v_s)
       and not exists (select 1 from public.ships s where s.fleet_id = v_s and s.durability > 0) then
      perform public.regard_add(v_a.player_id, c.nation_id, public.wc_num('regard_sink'), case when public.fleet_kind(v_s) = 'NAVY' then 'SINK_NAVY' else 'SINK_CARGO' end);
      if public.npc_wrecked(v_s) then
        select * into v_voyage from public.voyages v where v.fleet_id = v_s and v.status = 'SAILING';
        if v_voyage.id is not null then
          perform voyage.npc_wreck(v_s, v_voyage.id, v_voyage.last_settled_day + 1);
        end if;
      end if;
    end if;
  end loop;
$h$),
  ('public.navy_ship_step(uuid,timestamp with time zone)', 1,
$h$  v_leg   jsonb;
begin$h$,
$h$  v_leg   jsonb;
  v_esc   text;   -- 0333
begin$h$),
  ('public.navy_ship_step(uuid,timestamp with time zone)', 2,
$h$  v_duty := public.navy_on() and n.unpaid_since is null and n.ord <= public.navy_size_of(n.nation_id);
$h$,
$h$  v_duty := public.navy_on_duty(n.nation_id, n.ord, n.unpaid_since);
  -- 0333: a ship a battle has called answers it first; then the escort's step, which answers null for every other ship
  if n.mission = 'REINFORCE' then
    return public.navy_reinforce(p_fleet, f.port_id, p_now);
  end if;
  v_esc := public.navy_escort_step(p_fleet, f.port_id, v_duty, p_now);
  if v_esc is not null then
    return v_esc;
  end if;
$h$),
  ('world.navy_ship_card(uuid)', 1,
$h$    'ships', (select coalesce(jsonb_agg(world.ship_view(s.id) - array['id', 'water_t', 'food_t'] order by s.is_flagship desc, s.name), '[]'::jsonb)
                from public.ships s where s.fleet_id = p_fleet));$h$,
$h$    'ships', (select coalesce(jsonb_agg(world.ship_view(s.id) - array['id', 'water_t', 'food_t'] order by s.is_flagship desc, s.name), '[]'::jsonb)
                from public.ships s where s.fleet_id = p_fleet))
    || case when public.attack_on() then '{"attack": true}'::jsonb else '{}'::jsonb end;   -- 0333: as a cargo ship's card: the key is served only while attacks are lit$h$),
  ('world.fleets()', 1,
$h$    || case when f.ready_at > now() then jsonb_build_object('ready_at', f.ready_at) else '{}'::jsonb end
$h$,
$h$    || case when f.ready_at > now() then jsonb_build_object('ready_at', f.ready_at) else '{}'::jsonb end
    || case when f.busy_until is not null then public.battle_navy_served(f.id) else '{}'::jsonb end   -- 0333: "Navy arrives 5:10" on the card of a fleet in a battle; absent otherwise
$h$);

  for v_h in select h.fn from hunks_0333 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    declare
      x record;
    begin
      for x in select * from hunks_0333 h where h.fn = v_h.fn order by h.ord loop
        v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
        if v_n <> 1 then
          raise exception '0333 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
        end if;
        v_def := replace(v_def, x.old, x.new);
      end loop;
      execute v_def;
      v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
      for x in select * from hunks_0333 h where h.fn = v_h.fn order by h.ord desc loop
        v_n := (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new);
        if v_n <> 1 then
          raise exception '0333 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
        end if;
        v_def := replace(v_def, x.new, x.old);
      end loop;
      if v_def <> v_pre then
        raise exception '0333 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
      end if;
    end;
  end loop;

  -- ── 4. THE SELF-ASSERT: the catalog and stable reads. No game step, no row. ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked || c_new_fns) x))) <> v_fn_before then
    raise exception '0333 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key <> all (c_keys)) <> v_cfg_before then
    raise exception '0333 self-assert FAIL: a world_config row moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked) x))) <> v_meta_before then
    raise exception '0333 self-assert FAIL: the ACL, volatility, definer or config of a hunked function moved';
  end if;
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.command || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_cron_after;
    if v_cron_after is distinct from v_cron_before then
      raise exception '0333 self-assert FAIL: a cron job moved';
    end if;
  end if;
  if (select c.value from public.world_config c where c.key = 'navy_enabled') <> 'false'::jsonb or (select c.value from public.world_config c where c.key = 'attack_enabled') <> 'false'::jsonb then
    raise exception '0333 self-assert FAIL: a switch is not off';
  end if;
  if exists (select 1 from public.navy_ships) or exists (select 1 from public.battles b where b.kind = 'ATTACK') or exists (select 1 from public.battle_sides bs where bs.how <> 'OPENED') then
    raise exception '0333 self-assert FAIL: a row was written dark';
  end if;
  if (select string_agg(p.provolatile::text, '' order by p.oid::regprocedure::text) from pg_proc p
       where p.oid = any (array['public.crown_nation(uuid)'::regprocedure, 'public.harbour_nearest(double precision,double precision)'::regprocedure, 'public.navy_on_duty(uuid,integer,timestamp with time zone)'::regprocedure,
                                'public.navy_leg_seconds(uuid,uuid,uuid)'::regprocedure, 'public.navy_arrival(uuid,uuid,timestamp with time zone,timestamp with time zone)'::regprocedure, 'public.battle_navy_served(uuid)'::regprocedure]::oid[])) <> 'ssssss' then
    raise exception '0333 self-assert FAIL: a read is not stable';
  end if;
  if exists (select 1 from unnest(c_new_fns) f where has_function_privilege('anon', f::regprocedure, 'execute') or has_function_privilege('authenticated', f::regprocedure, 'execute')) then
    raise exception '0333 self-assert FAIL: a new function can be called from a client';
  end if;
  if not exists (select 1 from public.ports p where p.id = public.harbour_nearest(38.7, -9.1) and p.kind = 'HARBOUR') then
    raise exception '0333 self-assert FAIL: no harbour is nearest the mouth of the Tagus';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0333 self-assert FAIL: the self-assert took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0333 self-assert ok: THE NAVY COMES, dark. % hunks once each and reversing; no other function, knob or job; no row written; no game step ran (proof 40 runs them in CI). % ms.',
    (select count(*) from hunks_0333), round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0333;
end
$m$;
