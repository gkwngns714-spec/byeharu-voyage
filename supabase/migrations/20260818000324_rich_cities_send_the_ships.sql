-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0324 — RICH CITIES SEND THE SHIPS: a cargo ship loads at a rich city of her realm, not at the capital, and no gold moves instantly. DARK
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- Owner row 282, slice W7 of docs/WORLD_POWERS.md (section 3.1): *"rich cities should send cargo ship (Gold carrying ships) to other low cities for support"*; *"not instantly. it should see on the map"*.
--
-- ITS OWN SWITCH, BECAUSE `convoys_enabled` IS ALREADY LIT. docs/WORLD_POWERS.md wrote W7 as dark when ships were dark. Since 2026-11-05 18:46 UTC ships sail, so a change behind
-- public.convoys_on() would change live play the minute it deployed. Everything here is behind `convoy_rich_enabled`, false, read by public.rich_cities_on() alone. Lighting it is W9, owner only.
-- OFF (today, and after this file): the capital draws on its realm by CROWN_CALL and loads at the capital. Same flows, same ships, same stops.
-- ON: no CROWN_CALL from public.crown_aid or public.capital_pays; a ship loads at her origin; a capital is a stop like any other.
-- WHEN THE OWNER KEEPS IT ON, the off arm of public.crown_aid and the call in public.capital_pays die in their own slice: this switch is a window, not a second way to run the game.
--
-- WHAT THIS FILE ADDS:
--   public.rich_cities_on    THE one reader of the switch. convoys_on() and the knob: with no ships, no ship can replace the call.
--   public.realm_capital     THE capital of a great power. public.cargo_circuit_plan's and public.cargo_ships_commission's own query, lifted.
--   public.cargo_origins     THE harbours a realm's ships are based at. Lit: the top convoy_rich_ports by public.crown_call_room, the capital if none has room. Off: the capital.
--   public.cargo_homes       The starts a realm needs a circuit for: its origins, and wherever a ship of it is based.
--   public.cargo_circuit_of  THE newest circuit of a realm from a start. Three bodies read it.
--   public.cargo_load_room   THE gold a ship may load at her home. Lit: public.crown_call_room, in her realm. Off: the capital's surplus, as 0309.
--   public.cargo_rebase_to   Where an idle ship should be based next, or null. Never with funds aboard.
--   public.cargo_rebase      The one sailed leg to it. Never a teleport.
--   cargo_circuits.start_port: where a circuit starts and ends. Existing rows take their last stop. cargo_ships.based_at: when the rule last based her. Null: never.
--
-- THE HUNKS, each occurs once and reverses to its pre-image:
--   public.crown_aid (3):      lit, the capital joins the roster, and the run returns the load before public.crown_call. The instant path is unreachable lit.
--   public.capital_pays (1):   lit, no call. A gift pays from what the capital holds, else {waiting} (GIFT_WAITING). A founding keeps p_must, the world's richest harbour: a sign-up never fails.
--   public.cargo_ships_load (6): any idle ship of the realm at her home, the most room first; a donor by public.treasury_try_lock, never waited for (0307's rule); at most public.cargo_load_room.
--   public.cargo_ship_step (4): city_capital(port) = home becomes port_nation(port) = her nation, so a capital is a stop; her circuit is by her home; an idle ship may rebase; a ship away with no lap sails home.
--   public.cargo_circuit_plan (6), public.cargo_circuit_build (4): a start, default the capital. p_to on the plan: one stop, the rebase leg.
--   public.cargo_ships_commission (6): round robin over public.cargo_origins. public.tick_cargo_ships (4): one (realm, start) a run. public.funds_on_way (1): by nation, so a capital can be told.
--
-- WHY OFF EQUALS TODAY: every live ship has home = her capital and every circuit starts there. Then port_nation(port) = nation and city_capital(port) = home are one test (public.city_capital IS
-- port_nation's capital), and the capital's own stop never reaches that line. public.cargo_origins is the capital, so public.cargo_homes is one row, public.cargo_circuit_of is the old read, a rebase answers
-- IDLE, and the roster is the old roster. Parity is proved, not argued: scripts/ops/harness/rich-cities/dark-scene.sql is run before and after this file, and its digests must be equal.
--
-- W6's CONSTRAINT: public.tg_convoy_cargo_closes wants a RETURNED row at the port the load left, and voyage.npc_wreck returns funds to public.fleet_origin from inside voyage.settle. So origin must stay the port
-- she loaded at. It does: a load is written only at home_port_id, and home_port_id moves only in public.cargo_rebase, which public.cargo_rebase_to refuses with funds aboard. Proved, wreck included: proof 32.
--
-- THE LIVE SHIPS. The design commissions at the origin and assumes no ship exists; 100 exist, all at capitals. So a ship never based by the rule (based_at null) is rebased at once when lit; after that only
-- when her home has left the top and she has lain idle convoy_rebase_idle_days. Off, every ship away from the capital sails back to it, at once: only the capital loads off.
--
-- DECIDED BY DEFAULT (owner may reverse): docs/dev-log/2026-11-06-rich-cities-send-the-ships.md lists them.
--
-- SELF-ASSERT: the catalog and stable reads only: hunks once and reversing; ACL, volatility and config unmoved; no other function, knob or job; the switch off; origins are the capital. THIS FILE RUNS NO GAME STEP, in every
-- environment (docs/OPS_HEALTH.md section 4). THE LIVE PATHS ARE PROVED IN CI: proof 32, scripts/db/proofs/32_rich_cities.sql. Mutation controls: scripts/ops/harness/rich-cities/proof-0324.mjs (local).
--
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 45 s, lock_timeout 5 s first. Self-assert fails above 45 s.
-- ROLLBACK (forward, a NEW migration, owner only): `convoy_rich_enabled` false is the switch; ships sail back to their capitals with nothing stranded. To remove: swap this file's old and new, then drop what it created.
-- VERSION: 0324 - prod head 0322 (2026-11-06). 0323 (#520) deploys first and touches none of these bodies.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0   timestamptz := clock_timestamp();
  v_h    record;
  v_def  text;
  v_pre  text;
  v_sig  text;
  v_n    int;
  v_fn_before  text;
  v_cfg_before text;
  v_meta_before text;
  v_cron_before text;
  v_cron_after  text;
  c_keys constant text[] := array['convoy_rich_enabled', 'convoy_rich_ports', 'convoy_rebase_idle_days'];
  c_new_fns constant text[] := array[
    'public.rich_cities_on()', 'public.realm_capital(uuid)', 'public.cargo_origins(uuid)', 'public.cargo_homes(uuid)', 'public.cargo_circuit_of(uuid,uuid)',
    'public.cargo_load_room(uuid,uuid)', 'public.cargo_rebase_to(uuid,timestamp with time zone)', 'public.cargo_rebase(uuid,uuid,timestamp with time zone,timestamp with time zone)'];
  c_hunked constant text[] := array[
    'public.crown_aid(uuid)', 'public.capital_pays(uuid,uuid,uuid,text,bigint,uuid,boolean,jsonb)', 'public.cargo_ships_load(jsonb)', 'public.cargo_ship_step(uuid,timestamp with time zone)',
    'public.cargo_ships_commission(uuid)', 'public.tick_cargo_ships(timestamp with time zone,uuid)', 'public.funds_on_way(uuid)'];
  c_resigned constant text[] := array['public.cargo_circuit_plan(uuid)', 'public.cargo_circuit_build(uuid)'];
  c_after    constant text[] := array['public.cargo_circuit_plan(uuid,uuid,uuid)', 'public.cargo_circuit_build(uuid,uuid)'];
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('public.rich_cities_on()') is not null or to_regprocedure('public.cargo_circuit_plan(uuid,uuid,uuid)') is not null
     or exists (select 1 from public.world_config c where c.key = any (c_keys)) then
    raise exception '0324 refuses: something of it is already in this world';
  end if;
  if to_regprocedure('public.fleet_origin(uuid)') is null or to_regprocedure('public.cargo_circuit_plan(uuid)') is null then
    raise exception '0324 refuses: 0309 / 0322 (the circuit, the origin) are not in this world';
  end if;

  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked || c_resigned) x));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before
    from public.world_config c;
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
    into v_meta_before
    from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked) x));
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.command || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_cron_before;
  end if;

  -- ── 1. THE KNOBS ──
  insert into public.world_config (key, value, description) values
    ('convoy_rich_enabled', 'false'::jsonb, '0324: THE switch of rich cities sending the ships. False: the capital draws on its realm and loads, as 0309. True, with convoys_enabled: no CROWN_CALL, ships load at their origins. Owner only.'),
    ('convoy_rich_ports', '3'::jsonb, '0324: how many harbours of a realm, the most public.crown_call_room first, its ships are based at while convoy_rich_enabled is on.'),
    ('convoy_rebase_idle_days', '7'::jsonb, '0324: real days a ship based by the rule lies idle, at a home that has left the top, before she sails to a new one. A ship never based by the rule goes at once.');

  -- ── 2. THE COLUMNS ──
  alter table public.cargo_circuits add column start_port uuid references public.ports(id);
  update public.cargo_circuits c
     set start_port = coalesce((select l.to_port from public.cargo_circuit_legs l where l.circuit_id = c.id order by l.ord desc limit 1),
                               (select p.id from public.nations n join public.ports p on p.code = n.capital_port_code and p.kind = 'HARBOUR' where n.id = c.nation_id));
  alter table public.cargo_circuits alter column start_port set not null;
  comment on column public.cargo_circuits.start_port is '0324: where this circuit starts and ends: her home. The newest of a (nation, start) is the current one (public.cargo_circuit_of).';
  alter table public.cargo_ships add column based_at timestamptz;
  comment on column public.cargo_ships.based_at is '0324: when the rich-city rule last based her. Null: it never has, or the rule is off. public.cargo_ships_commission and public.cargo_rebase alone write it.';
  comment on column public.cargo_ships.home_port_id is '0324: her origin, read by public.fleet_origin. The port she loads at and returns to, so it moves only with no funds aboard (public.cargo_rebase). A capital until convoy_rich_enabled.';

  -- ── 3. THE READERS ──
  execute $f$
create function public.rich_cities_on()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0324: THE one reader of convoy_rich_enabled. It needs ships to sail: convoys off, the instant path stands, whatever this knob says.
  select public.convoys_on() and public.wc('convoy_rich_enabled') = 'true'::jsonb
$$
  $f$;

  execute $f$
create function public.realm_capital(p_nation uuid)
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0324: THE capital harbour of a great power, whoever holds it today. Null for any other nation. The query public.cargo_circuit_plan and public.cargo_ships_commission each held, lifted.
  select p.id
    from public.great_powers g join public.nations n on n.id = g.nation_id
    join public.ports p on p.code = n.capital_port_code and p.kind = 'HARBOUR'
   where g.nation_id = p_nation
$$
  $f$;

  execute $f$
create function public.cargo_origins(p_nation uuid)
returns uuid[]
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0324 (docs/WORLD_POWERS.md section 3.1): THE harbours a realm's ships are based at, the richest first. Lit: the top convoy_rich_ports of the realm by public.crown_call_room, the room that already keeps a donor
  -- above about an hour of payouts plus its reserve, each on a course (a harbour no course reaches cannot start a circuit). No room anywhere: the capital. Off: the capital.
  select case when public.rich_cities_on()
              then coalesce((select array_agg(y.id order by y.room desc, y.code)
                               from (select h.id, h.code, x.room
                                       from public.ports h
                                      cross join lateral (select public.crown_call_room(h.id) as room) x
                                      where h.kind = 'HARBOUR' and public.port_nation(h.id) = p_nation and x.room > 0
                                        and exists (select 1 from public.npc_courses c where c.from_port = h.id or c.to_port = h.id)
                                      order by x.room desc, h.code
                                      limit public.wc_int('convoy_rich_ports')) y),
                            array[public.realm_capital(p_nation)])
              else array[public.realm_capital(p_nation)] end
$$
  $f$;

  execute $f$
create function public.cargo_homes(p_nation uuid)
returns table (port_id uuid, rank bigint)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0324: the starts a realm needs a circuit for: its origins, then wherever a ship of it is based today (a home that has left the top still sends her out). Off, with every ship at the capital: one row.
  select x.port_id, min(x.rank)::bigint
    from (select o.port_id, o.rank from unnest(public.cargo_origins(p_nation)) with ordinality o(port_id, rank)
          union all
          select c.home_port_id, 1000 + c.ord from public.cargo_ships c where c.nation_id = p_nation) x
   where x.port_id is not null
   group by x.port_id
$$
  $f$;

  execute $f$
create function public.cargo_circuit_of(p_nation uuid, p_start uuid)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0324: THE current circuit of a realm from a start: the newest. A ship out on an older one finishes it.
  select x.id from public.cargo_circuits x where x.nation_id = p_nation and x.start_port = p_start order by x.id desc limit 1
$$
  $f$;

  execute $f$
create function public.cargo_load_room(p_port uuid, p_nation uuid)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0324: THE gold a ship of p_nation may load at p_port this run. Lit: public.crown_call_room, the donor's own limit, at a harbour of her realm. Off: her capital's surplus, as 0309, and nothing anywhere else.
  select case when public.rich_cities_on()
              then case when public.port_nation(p_port) = p_nation then public.crown_call_room(p_port) else 0 end
              when p_port = public.realm_capital(p_nation) then greatest(0, public.city_surplus(p_port))
              else 0 end
$$
  $f$;

  execute $f$
create function public.cargo_rebase_to(p_fleet uuid, p_now timestamptz)
returns uuid
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0324: where a ship with no funds aboard should be based next, or null to stay. Answers null with funds aboard, always: origin is the port she loaded at (W6, public.tg_convoy_cargo_closes).
--   Away from her home with no lap: her home.
--   Lit and already based by the rule: she stays until she has lain idle convoy_rebase_idle_days. Idle is read from her last book row and based_at, so nothing here can disagree with them.
--   Her home is one of the realm's origins: she stays. Otherwise the origin her ord falls on, round robin. Off, that is the capital, at once.
declare
  c       public.cargo_ships%rowtype;
  v_port  uuid;
  v_since timestamptz;
  v_o     uuid[];
begin
  select * into c from public.cargo_ships x where x.fleet_id = p_fleet;
  select f.port_id into v_port from public.fleets f where f.id = p_fleet;
  if c.fleet_id is null or v_port is null or exists (select 1 from public.cargo_ship_aboard(p_fleet)) then
    return null;
  end if;
  if v_port <> c.home_port_id then
    return c.home_port_id;
  end if;
  if c.based_at is not null and public.rich_cities_on() then
    v_since := greatest(c.based_at, (select b.created_at from public.convoy_cargo b where b.fleet_id = p_fleet order by b.id desc limit 1));
    if p_now < v_since + make_interval(secs => public.wc_num('convoy_rebase_idle_days')::double precision * 86400) then
      return null;
    end if;
  end if;
  v_o := public.cargo_origins(c.nation_id);
  if c.home_port_id = any (v_o) then
    return null;
  end if;
  return v_o[(c.ord - 1) % cardinality(v_o) + 1];
end
$$
  $f$;

  execute $f$
create function public.cargo_rebase(p_fleet uuid, p_port uuid, p_ready timestamptz, p_now timestamptz)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0324: one ship's move to a new home: one sailed leg, empty, seen on the map, through voyage.depart, as every leg. Never a teleport. Her home moves as she leaves, so a wreck on the way is at the home she
-- was bound for, and she closes nothing when she arrives. Called only with no load (public.cargo_ship_step). Answers IDLE, IN_PORT or SAILED. Off, for a ship at her capital: IDLE, three reads.
declare
  v_to  uuid := public.cargo_rebase_to(p_fleet, p_now);
  v_nat uuid;
  v_leg jsonb;
begin
  if v_to is null then
    return 'IDLE';
  end if;
  if p_ready is not null and p_ready > p_now then
    return 'IN_PORT';
  end if;
  select c.nation_id into v_nat from public.cargo_ships c where c.fleet_id = p_fleet;
  v_leg := public.cargo_circuit_plan(v_nat, p_port, v_to) #> '{legs,0}';
  if v_leg is null then
    return 'IDLE';   -- no course reaches it: she stays
  end if;
  perform voyage.depart(p_fleet, voyage.segments_from_course(v_leg -> 'course'), p_port, v_to, p_now);
  update public.cargo_ships x
     set home_port_id = v_to, based_at = case when public.rich_cities_on() then p_now end
   where x.fleet_id = p_fleet;
  return 'SAILED';
end
$$
  $f$;

  revoke all on function public.rich_cities_on() from public, anon, authenticated;
  revoke all on function public.realm_capital(uuid) from public, anon, authenticated;
  revoke all on function public.cargo_origins(uuid) from public, anon, authenticated;
  revoke all on function public.cargo_homes(uuid) from public, anon, authenticated;
  revoke all on function public.cargo_circuit_of(uuid, uuid) from public, anon, authenticated;
  revoke all on function public.cargo_load_room(uuid, uuid) from public, anon, authenticated;
  revoke all on function public.cargo_rebase_to(uuid, timestamptz) from public, anon, authenticated;
  revoke all on function public.cargo_rebase(uuid, uuid, timestamptz, timestamptz) from public, anon, authenticated;

  -- ── 4. THE HUNKS ──
  create temp table hunks_0324 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0324 values
  -- crown_aid
  ('public.crown_aid(uuid)', 1,
$h$-- 0309: cargo ships lit, the same roster and the same call, then the capital loads a ship (public.cargo_ships_load) and this run pays nobody: one path per state of the switch.
$h$,
$h$-- 0309: cargo ships lit, the same roster and the same call, then the capital loads a ship (public.cargo_ships_load) and this run pays nobody: one path per state of the switch.
-- 0324: rich cities lit (public.rich_cities_on), the same roster with the capital in it, no call, and a ship loads at her origin. Nothing moves instantly.
$h$),
  ('public.crown_aid(uuid)', 2,
$h$   where x.cap is not null and x.cap <> x.port_id;
$h$,
$h$   where x.cap is not null and (x.cap <> x.port_id or public.rich_cities_on());   -- 0324: lit, a capital is a stop like any other
$h$),
  ('public.crown_aid(uuid)', 3,
$h$  v_call := public.crown_call(v_short);
  if public.convoys_on() then
$h$,
$h$  if public.rich_cities_on() then   -- 0324: above the call, so lit it never runs
    return jsonb_build_object('aided', 0, 'aid', 0, 'called', 0, 'donors', 0) || public.cargo_ships_load(v_short);
  end if;
  v_call := public.crown_call(v_short);
  if public.convoys_on() then
$h$),
  -- capital_pays: the second writer of CROWN_CALL
  ('public.capital_pays(uuid,uuid,uuid,text,bigint,uuid,boolean,jsonb)', 1,
$h$      if v_from is not null then
        perform public.treasury_lock(v_from);
$h$,
$h$      if v_from is not null and not public.rich_cities_on() then   -- 0324: lit, gold does not move instantly: {waiting}, or p_must and the world's richest harbour
        perform public.treasury_lock(v_from);
$h$),
  -- cargo_ships_load
  ('public.cargo_ships_load(jsonb)', 1,
$h$-- up to its surplus, onto one idle ship of its realm, the lowest ord. One ship a run. No idle ship, or nothing to send: nothing, and the next hourly run asks again. Answers {loaded, ships}.
$h$,
$h$-- up to its surplus, onto one idle ship of its realm, the lowest ord. One ship a run. No idle ship, or nothing to send: nothing, and the next hourly run asks again. Answers {loaded, ships}.
-- 0324: she loads at her home, up to public.cargo_load_room: the capital's surplus off, a rich city's room lit, the ship with the most room first. Lit, her home may be no city of the roster, so it is a donor:
-- public.treasury_try_lock, never waited for (0307), and a busy one is left to the next hour. The load is written at her home, and her home never moves with funds aboard (public.cargo_rebase_to).
$h$),
  ('public.cargo_ships_load(jsonb)', 2,
$h$  v_player uuid;
  v_a      bigint;
$h$,
$h$  v_player uuid;
  v_home   uuid;
  v_nat    uuid;
  v_a      bigint;
$h$),
  ('public.cargo_ships_load(jsonb)', 3,
$h$    select c.fleet_id, c.player_id into v_fleet, v_player
      from public.cargo_ships c join public.fleets f on f.id = c.fleet_id
     where c.home_port_id = k.cap and f.status = 'DOCKED' and f.port_id = k.cap and c.out_load is null
$h$,
$h$    select c.fleet_id, c.player_id, c.home_port_id, c.nation_id into v_fleet, v_player, v_home, v_nat
      from public.cargo_ships c join public.fleets f on f.id = c.fleet_id
     where public.realm_capital(c.nation_id) = k.cap and f.status = 'DOCKED' and f.port_id = c.home_port_id and c.out_load is null
$h$),
  ('public.cargo_ships_load(jsonb)', 4,
$h$                    where l.circuit_id = (select x.id from public.cargo_circuits x where x.nation_id = c.nation_id order by x.id desc limit 1))
     order by c.ord
     limit 1;
$h$,
$h$                    where l.circuit_id = public.cargo_circuit_of(c.nation_id, c.home_port_id))
     order by public.cargo_load_room(c.home_port_id, c.nation_id) desc, c.ord
     limit 1;
$h$),
  ('public.cargo_ships_load(jsonb)', 5,
$h$    continue when v_fleet is null;
    v_a := least(k.need - (select coalesce(sum(a.aboard), 0)::bigint from public.cargo_ships c cross join lateral public.cargo_ship_aboard(c.fleet_id) a where c.home_port_id = k.cap),
                 greatest(0, public.city_surplus(k.cap)));
$h$,
$h$    continue when v_fleet is null or not public.treasury_try_lock(v_home);
    v_a := least(k.need - (select coalesce(sum(a.aboard), 0)::bigint from public.cargo_ships c cross join lateral public.cargo_ship_aboard(c.fleet_id) a where c.nation_id = v_nat),
                 public.cargo_load_room(v_home, v_nat));
$h$),
  ('public.cargo_ships_load(jsonb)', 6,
$h$    perform public.convoy_book('LOADED', v_fleet, v_player, k.cap, v_a);
$h$,
$h$    perform public.convoy_book('LOADED', v_fleet, v_player, v_home, v_a);
$h$),
  -- cargo_ship_step
  ('public.cargo_ship_step(uuid,timestamp with time zone)', 1,
$h$    if v_load is null then
      return 'IDLE';
    end if;
    v_cir := (select x.id from public.cargo_circuits x where x.nation_id = c.nation_id order by x.id desc limit 1);
$h$,
$h$    if v_load is null then
      return public.cargo_rebase(p_fleet, f.port_id, f.ready_at, p_now);   -- 0324: idle, she may be due a new home. Off at her capital: IDLE
    end if;
    v_cir := public.cargo_circuit_of(c.nation_id, c.home_port_id);   -- 0324: the circuit from her home
$h$),
  ('public.cargo_ship_step(uuid,timestamp with time zone)', 2,
$h$    if v_lit and v_left > 0 and public.city_capital(f.port_id) = c.home_port_id then
$h$,
$h$    if v_lit and v_left > 0 and public.port_nation(f.port_id) = c.nation_id then   -- 0324: every city of her realm, the capital too: her home alone is not a stop
$h$),
  ('public.cargo_ship_step(uuid,timestamp with time zone)', 3,
$h$    v_cir := c.circuit_id;
    v_leg := c.leg + 1;
$h$,
$h$    if c.circuit_id is null then
      return public.cargo_rebase(p_fleet, f.port_id, f.ready_at, p_now);   -- 0324: away with no lap (a leg to a new home turned back): she sails home. Only a rebase leaves her so
    end if;
    v_cir := c.circuit_id;
    v_leg := c.leg + 1;
$h$),
  ('public.cargo_ship_step(uuid,timestamp with time zone)', 4,
$h$--   The capital: back from a lap, she returns what is left and is mended. A load not yet gone sails if the switch is on, and comes straight back ashore if it is off.
$h$,
$h$--   The capital: back from a lap, she returns what is left and is mended. A load not yet gone sails if the switch is on, and comes straight back ashore if it is off.
--   0324: her home, the capital until convoy_rich_enabled. A capital that is not her home is a city like any other.
$h$),
  -- cargo_circuit_plan: a start, default the capital; p_to, one stop
  ('public.cargo_circuit_plan(uuid)', 1,
$h$CREATE OR REPLACE FUNCTION public.cargo_circuit_plan(p_nation uuid)
$h$,
$h$CREATE OR REPLACE FUNCTION public.cargo_circuit_plan(p_nation uuid, p_start uuid DEFAULT NULL::uuid, p_to uuid DEFAULT NULL::uuid)
$h$),
  ('public.cargo_circuit_plan(uuid)', 2,
$h$-- its courses. Answers {capital, nm, legs: [{to, code, nm, course}], left_out: [codes no course reaches]}; the last leg ends at the capital. A realm with no city has no legs.
$h$,
$h$-- its courses. Answers {capital, nm, legs: [{to, code, nm, course}], left_out: [codes no course reaches]}; the last leg ends at the capital. A realm with no city has no legs.
-- 0324: p_start, default the capital, is where it starts and ends; the capital is then one more stop. p_to: that one stop instead of the realm, so legs[0] is the one leg from p_start to it, and the graph has one walker.
$h$),
  ('public.cargo_circuit_plan(uuid)', 3,
$h$  v_cap   uuid;
  v_ids   uuid[];     -- vertex -> port
$h$,
$h$  v_cap   uuid;
  v_start uuid;
  v_ids   uuid[];     -- vertex -> port
$h$),
  ('public.cargo_circuit_plan(uuid)', 4,
$h$  select p.id into v_cap
    from public.great_powers g join public.nations n on n.id = g.nation_id
    join public.ports p on p.code = n.capital_port_code and p.kind = 'HARBOUR'
   where g.nation_id = p_nation;
  if v_cap is null then
$h$,
$h$  v_cap := public.realm_capital(p_nation);   -- 0324: the same query, lifted
  if v_cap is null then
$h$),
  ('public.cargo_circuit_plan(uuid)', 5,
$h$  select array_agg(x.id order by x.id) into v_ids
    from (select c.from_port as id from public.npc_courses c union select c.to_port from public.npc_courses c union select v_cap
          union select p.id from public.ports p where p.kind = 'HARBOUR' and public.city_capital(p.id) = v_cap) x;
$h$,
$h$  v_start := coalesce(p_start, v_cap);
  select array_agg(x.id order by x.id) into v_ids
    from (select c.from_port as id from public.npc_courses c union select c.to_port from public.npc_courses c union select v_start
          union select p.id from public.ports p where p.kind = 'HARBOUR' and (p.id = p_to or (p_to is null and public.city_capital(p.id) = v_cap))) x;
$h$),
  ('public.cargo_circuit_plan(uuid)', 6,
$h$  v_s := array[(v_ix ->> v_cap::text)::int]
         || array(select (v_ix ->> p.id::text)::int from public.ports p
                   where p.kind = 'HARBOUR' and p.id <> v_cap and public.city_capital(p.id) = v_cap order by p.code);
$h$,
$h$  v_s := array[(v_ix ->> v_start::text)::int]
         || array(select (v_ix ->> p.id::text)::int from public.ports p
                   where p.kind = 'HARBOUR' and p.id <> v_start and (p.id = p_to or (p_to is null and public.city_capital(p.id) = v_cap)) order by p.code);
$h$),
  -- cargo_circuit_build
  ('public.cargo_circuit_build(uuid)', 1,
$h$CREATE OR REPLACE FUNCTION public.cargo_circuit_build(p_nation uuid)
$h$,
$h$CREATE OR REPLACE FUNCTION public.cargo_circuit_build(p_nation uuid, p_start uuid DEFAULT NULL::uuid)
$h$),
  ('public.cargo_circuit_build(uuid)', 2,
$h$  v_plan jsonb := public.cargo_circuit_plan(p_nation);
$h$,
$h$  v_plan jsonb := public.cargo_circuit_plan(p_nation, p_start);
  v_start uuid := coalesce(p_start, public.realm_capital(p_nation));   -- 0324
$h$),
  ('public.cargo_circuit_build(uuid)', 3,
$h$  insert into public.cargo_circuits (nation_id, left_out) values (p_nation, v_plan -> 'left_out') returning id into v_id;
$h$,
$h$  insert into public.cargo_circuits (nation_id, left_out, start_port) values (p_nation, v_plan -> 'left_out', v_start) returning id into v_id;
$h$),
  ('public.cargo_circuit_build(uuid)', 4,
$h$   where c.nation_id = p_nation and c.id <> v_id
$h$,
$h$   where c.nation_id = p_nation and c.start_port = v_start and c.id <> v_id
$h$),
  -- cargo_ships_commission
  ('public.cargo_ships_commission(uuid)', 1,
$h$  v_cap    uuid;
  v_player uuid;
$h$,
$h$  v_cap    uuid;
  v_home   uuid;
  v_o      uuid[];
  v_player uuid;
$h$),
  ('public.cargo_ships_commission(uuid)', 2,
$h$  select n.code, p.id into v_code, v_cap
    from public.great_powers g
    join public.nations n on n.id = g.nation_id
    join public.ports p on p.code = n.capital_port_code and p.kind = 'HARBOUR'
   where g.nation_id = p_nation;
  if v_cap is null then
$h$,
$h$  select n.code into v_code from public.nations n where n.id = p_nation;
  v_cap := public.realm_capital(p_nation);   -- 0324: the same query, lifted
  if v_cap is null then
$h$),
  ('public.cargo_ships_commission(uuid)', 3,
$h$  for v_n in 1 .. public.wc_int('convoy_ships_per_nation') loop
$h$,
$h$  v_o := public.cargo_origins(p_nation);   -- 0324: read once, so one run's ships share one list
  for v_n in 1 .. public.wc_int('convoy_ships_per_nation') loop
$h$),
  ('public.cargo_ships_commission(uuid)', 4,
$h$    v_fleet := public.form_fleet(v_player, format('Cargo ship %s', v_n), v_cap);
$h$,
$h$    v_home := v_o[(v_n - 1) % cardinality(v_o) + 1];   -- 0324: round robin. Off, the capital
    v_fleet := public.form_fleet(v_player, format('Cargo ship %s', v_n), v_home);
$h$),
  ('public.cargo_ships_commission(uuid)', 5,
$h$    insert into public.cargo_ships (fleet_id, player_id, nation_id, home_port_id, ord)
    values (v_fleet, v_player, p_nation, v_cap, v_n);
$h$,
$h$    insert into public.cargo_ships (fleet_id, player_id, nation_id, home_port_id, ord, based_at)
    values (v_fleet, v_player, p_nation, v_home, v_n, case when public.rich_cities_on() then now() end);
$h$),
  ('public.cargo_ships_commission(uuid)', 6,
$h$-- is made by (public.form_fleet, public.commission_ship). Dark, nothing. Answers how many it made. Moves no gold: her house's purse is 0 and no ledger row is written.
$h$,
$h$-- is made by (public.form_fleet, public.commission_ship). Dark, nothing. Answers how many it made. Moves no gold: her house's purse is 0 and no ledger row is written.
-- 0324: at her origin (public.cargo_origins): the capital until convoy_rich_enabled.
$h$),
  -- tick_cargo_ships
  ('public.tick_cargo_ships(timestamp with time zone,uuid)', 1,
$h$  v_nat   uuid;
  v_built bigint;
$h$,
$h$  v_nat   uuid;
  v_start uuid;
  v_built bigint;
$h$),
  ('public.tick_cargo_ships(timestamp with time zone,uuid)', 2,
$h$    select g.nation_id into v_nat
      from public.great_powers g
      join public.nations n on n.id = g.nation_id
      join public.ports p on p.code = n.capital_port_code and p.kind = 'HARBOUR'
      left join lateral (select x.built_at from public.cargo_circuits x where x.nation_id = g.nation_id order by x.id desc limit 1) k on true
     where (p_only_nation is null or g.nation_id = p_only_nation)
$h$,
$h$    select g.nation_id, h.port_id into v_nat, v_start   -- 0324: a circuit from each start of a realm: one row off, the capital's
      from public.great_powers g
      join public.nations n on n.id = g.nation_id
      cross join lateral public.cargo_homes(g.nation_id) h
      left join lateral (select x.built_at from public.cargo_circuits x where x.id = public.cargo_circuit_of(g.nation_id, h.port_id)) k on true
     where (p_only_nation is null or g.nation_id = p_only_nation)
$h$),
  ('public.tick_cargo_ships(timestamp with time zone,uuid)', 3,
$h$     order by n.code
     limit 1;
$h$,
$h$     order by n.code, h.rank
     limit 1;
$h$),
  ('public.tick_cargo_ships(timestamp with time zone,uuid)', 4,
$h$        if not exists (select 1 from public.cargo_circuits x where x.nation_id = v_nat
                        and x.id = (select max(y.id) from public.cargo_circuits y where y.nation_id = v_nat)
                        and x.built_at >= (select max(a.since) from public.port_allegiance a)) then
          v_built := public.cargo_circuit_build(v_nat);
$h$,
$h$        if not exists (select 1 from public.cargo_circuits x where x.id = public.cargo_circuit_of(v_nat, v_start)
                        and x.built_at >= (select max(a.since) from public.port_allegiance a)) then
          v_built := public.cargo_circuit_build(v_nat, v_start);
$h$),
  -- funds_on_way
  ('public.funds_on_way(uuid)', 1,
$h$               and c.home_port_id = public.city_capital(p_port) and c.home_port_id <> p_port
$h$,
$h$               and c.nation_id = public.port_nation(p_port) and c.home_port_id <> p_port   -- 0324: her realm, as her step pays it; a capital that is not her home is a stop
$h$);

  for v_h in select h.fn from hunks_0324 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    declare
      x record;
    begin
      for x in select * from hunks_0324 h where h.fn = v_h.fn order by h.ord loop
        v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
        if v_n <> 1 then
          raise exception '0324 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
        end if;
        v_def := replace(v_def, x.old, x.new);
      end loop;
      v_sig := v_h.fn;
      if v_h.fn = any (c_resigned) then
        v_sig := c_after[array_position(c_resigned, v_h.fn)];
        execute 'drop function ' || v_h.fn;   -- a default argument is a new signature, and CREATE OR REPLACE would leave the old one beside it
      end if;
      execute v_def;
      v_def := replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '');
      for x in select * from hunks_0324 h where h.fn = v_h.fn order by h.ord desc loop
        v_n := (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new);
        if v_n <> 1 then
          raise exception '0324 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
        end if;
        v_def := replace(v_def, x.new, x.old);
      end loop;
      if v_def <> v_pre then
        raise exception '0324 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
      end if;
    end;
  end loop;
  revoke all on function public.cargo_circuit_plan(uuid, uuid, uuid) from public, anon, authenticated;
  revoke all on function public.cargo_circuit_build(uuid, uuid) from public, anon, authenticated;

  -- ── 5. THE SELF-ASSERT: the catalog and stable reads. No game step. ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked || c_after || c_new_fns) x))) <> v_fn_before then
    raise exception '0324 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key <> all (c_keys)) <> v_cfg_before then
    raise exception '0324 self-assert FAIL: a world_config row moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked) x))) <> v_meta_before then
    raise exception '0324 self-assert FAIL: the ACL, volatility, definer or config of a hunked function moved';
  end if;
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.command || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_cron_after;
    if v_cron_after is distinct from v_cron_before then
      raise exception '0324 self-assert FAIL: a cron job moved';
    end if;
  end if;
  if public.rich_cities_on() then
    raise exception '0324 self-assert FAIL: the rule is not dark';
  end if;
  if exists (select 1 from public.great_powers g where public.cargo_origins(g.nation_id) is distinct from array[public.realm_capital(g.nation_id)]) then
    raise exception '0324 self-assert FAIL: off, an origin is not the capital';
  end if;
  if to_regprocedure('public.cargo_circuit_plan(uuid)') is not null or to_regprocedure('public.cargo_circuit_build(uuid)') is not null then
    raise exception '0324 self-assert FAIL: an old signature stands beside the new one';
  end if;
  if (select string_agg(p.provolatile::text, '' order by p.oid::regprocedure::text) from pg_proc p
       where p.oid = any (array['public.cargo_circuit_plan(uuid,uuid,uuid)'::regprocedure, 'public.cargo_origins(uuid)'::regprocedure, 'public.cargo_rebase_to(uuid,timestamp with time zone)'::regprocedure,
                                'public.rich_cities_on()'::regprocedure, 'public.cargo_load_room(uuid,uuid)'::regprocedure]::oid[])) <> 'sssss' then
    raise exception '0324 self-assert FAIL: a read is not stable';
  end if;
  if exists (select 1 from unnest(c_new_fns || c_after) f
              where has_function_privilege('anon', f::regprocedure, 'execute') or has_function_privilege('authenticated', f::regprocedure, 'execute')) then
    raise exception '0324 self-assert FAIL: a new function can be called from a client';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0324 self-assert FAIL: the self-assert took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0324 self-assert ok: RICH CITIES SEND THE SHIPS, dark behind convoy_rich_enabled. % hunks once each and reversing; no other function, knob or job; no game step ran (proof 32 runs them in CI). % ms.',
    (select count(*) from hunks_0324), round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0324;
end
$m$;
