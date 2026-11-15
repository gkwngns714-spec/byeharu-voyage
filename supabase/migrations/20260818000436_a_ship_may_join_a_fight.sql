-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0436 - A SHIP MAY JOIN A FIGHT  (the Join door for a player's ship inside a battle's circle; navy and pirate ships nearby join by a rule;
--        merchants and every ship that does not join sail on through)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-15 (items 8-9, corrected): joining a battle is a CHOICE. Entering the red circle changes nothing; only a ship that joins
--   stops, and she is locked to the end. No PvP, ever. (docs/design/tick-combat.md sections 8 and 9.2: THE CONTRACT; dev-log 2026-11-15-battle-join.md)
--
-- WHAT WAS ALREADY TRUE (0435, the tick engine): a RAID or an ATTACK is one timeline (battles.ticks) run by public.tick_battle_run from the sheet's
--   hulls (sheet.a = the side set upon, DEFENDER; sheet.b = ATTACKER), each hull with `from` (the tick she comes up) and `fleet`. A re-run is the
--   same fight before any new `from` (draws keyed by tick and hull), and moves resolves_at and every side's busy_until to the new end.
-- WHAT THIS FILE ADDS:
--   J1. THE DOOR: cmd.battle_join(p_battle, p_fleet, p_side) -> {ok, battle, side, from_tick}; the core is public.battle_join_for (the NPC rule
--       uses the same core). Refusals: E_NO_HOUSE, E_BAD_SIDE (not ATTACKER/DEFENDER; or a player's ship on the pirates' side of a RAID),
--       E_NO_BATTLE, E_BATTLE_OVER (closed, an old round battle, or the next tick is past its last), E_NOT_YOUR_FLEET, E_FLEET_BUSY (held, in a
--       battle, in a yard, no hull left, or a merchant), E_AT_PEACE ("Wait 2 / 5 min", 0432's peace), E_HUMAN_TARGET (a player's ship on a side
--       whose other side has a player's fleet: no PvP), E_NOT_IN_REACH ("Range 30 / 42 miles": battle_join_nm of battles.site).
--       She joins at the NEXT tick (floor((now - started_at) / tick_ms) + 1: nothing a watcher has seen changes): a battle_sides row how JOINED,
--       her hulls appended to her side of the sheet with `from` = that tick (append only: indexes are positions), a navy ship tied to the battle
--       (navy_ships.battle_id, freed by public.navy_close), the timeline re-run (public.tick_battle_run), then she is stopped to the new end
--       (public.battle_stop: held under sail, IN_BATTLE at anchor or in port) and freed with every side by public.battle_resolve.
--   J2. THE NPC RULE (public.battle_npc_joins, from public.tick_pirates' tail, gated like the strikes; never raises): each run, the newest live tick
--       RAIDs (at most battle_join_battles_per_run 10); per battle, rolled on md5(battle, minute, kind): with battle_join_navy_chance (0.35) the
--       nearest free navy ship (PATROL or HUNT, any country; navy switch lit) joins the side set upon, with battle_join_pirate_chance (0.15) the
--       nearest free hunting pirate joins her own side. At most battle_join_per_battle (1) a battle a run, battle_join_per_side (2) JOINED a side,
--       battle_join_per_run (3) a run. A candidate is the nearest 4 by a sieve (rough place between her two harbours, reach + 120 miles) and is taken
--       SKIP LOCKED; the core then measures her exactly. MERCHANTS AND CARGO SHIPS NEVER JOIN (the finder never lists them; the core refuses them).
--   J3. NOTHING STOPS A SHIP THAT DOES NOT JOIN: no step, no route, no hold reads the circle. (Nothing written: it is the absence of a rule.)
--   J4. public.navy_close: a JOINED pirate is no navy ("The navy came up" counts navy ships only).
--   J5. battle_sides.how takes JOINED (the check rebuilt NOT VALID, then validated: no long lock).
-- LOAD: -- budget: ~0-3 joins a minute, each ~6 rows (1 battle_sides insert, 1 battles update, 1-2 fleets, 1 voyage_events, 1 navy_ships) = at most
--   ~18 rows a minute; reads: one index scan of the FIGHTING battles a minute and, only when a roll passes, one sieve of the navy or pirate fleets
--   (hundreds of rows, no write). No new job, no new table, no cron change. A join is one more tick_battle_run (~5 ms).
-- LOCKS: ALTER TABLE battle_sides (ADD CONSTRAINT NOT VALID: brief ACCESS EXCLUSIVE; VALIDATE: SHARE UPDATE EXCLUSIVE); CREATE OR REPLACE x3 by
--   hunks; CREATE FUNCTION x4. BUDGET: statement_timeout 45 s, lock_timeout 5 s; fails above 30 s.
-- ROLLBACK (forward, owner only): quick: battle_join_per_run 0 (no NPC joins); the door: revoke execute on cmd.battle_join from authenticated.
-- SELF-ASSERT: every hunk once and reversing; grants, volatility, definer, search path, owner unmoved; no other function moved; the door open to
--   clients and registered, the rest server-only; the knobs; the check. THE PROBE, rolled back (runs on every world, lit inside the probe): two
--   players' ships and a company's merchant; an ATTACK on the merchant; each refusal of the door; a player joins the attacker's side at the next
--   tick, her hulls on the sheet with `from`, the timeline re-run (k + 1), she is held to its end; the NPC step answers without raising.
-- VERSION: 0436 = 0435 + 1 (tick-combat). Written on the chain to 0435.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array['public.client_rpc_entry_points()', 'public.tick_pirates(timestamp with time zone)',
                                    'public.navy_close(uuid,timestamp with time zone)'];
  c_new    constant text[] := array['public.battle_join_for(uuid,uuid,uuid,text,timestamp with time zone)', 'cmd.battle_join(uuid,uuid,text)',
                                    'public.battle_join_near(uuid,text,timestamp with time zone)', 'public.battle_npc_joins(timestamp with time zone)'];
  v_t0        timestamptz := clock_timestamp();
  v_h         record;
  x           record;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_fn_before text;
  v_meta      text;
  -- the probe
  c_u1  constant uuid := '00000000-0436-4000-8000-000000000001';
  c_u2  constant uuid := '00000000-0436-4000-8000-000000000002';
  c_u3  constant uuid := '00000000-0436-4000-8000-000000000003';
  v_p1  uuid;
  v_p2  uuid;
  v_p3  uuid;
  v_f1  uuid;
  v_f2  uuid;
  v_f3  uuid;
  v_m   uuid;
  v_lat numeric;
  v_lon numeric;
  v_b   uuid;
  v_k0  int;
  v_nb  int;
  v_r   jsonb;
  v_bt  public.battles%rowtype;
  v_note text;
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config where key = 'battle_join_per_run') then
    raise exception '0436 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.tick_battle_run(uuid)') is null
     or not exists (select 1 from pg_attribute a where a.attrelid = 'public.battles'::regclass and a.attname = 'ticks' and not a.attisdropped)
     or not exists (select 1 from public.world_config where key = 'battle_join_nm') then
    raise exception '0436 refuses: 0435 (the tick engine, battles.ticks, battle_join_nm) is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGE ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));

  -- ── 2. THE KNOBS ──
  insert into public.world_config (key, value, description) values
    ('battle_join_navy_chance', to_jsonb(0.35), '0436: each NPC-join run, the chance a live tick RAID draws the nearest free navy ship within battle_join_nm to the side set upon (public.battle_npc_joins). 0: none.'),
    ('battle_join_pirate_chance', to_jsonb(0.15), '0436: each NPC-join run, the chance a live tick RAID draws the nearest free hunting pirate within battle_join_nm to the pirates'' side. 0: none.'),
    ('battle_join_per_battle', to_jsonb(1), '0436: the most NPC ships that join one battle in one run.'),
    ('battle_join_per_side', to_jsonb(2), '0436: the most NPC ships that join one side of one battle (how JOINED), all runs together.'),
    ('battle_join_per_run', to_jsonb(3), '0436: the most NPC ships that join any battle in one run. 0: NPCs never join (the quick rollback).'),
    ('battle_join_battles_per_run', to_jsonb(10), '0436: the most live battles one NPC-join run looks at, newest first.');

  -- ── 3. THE CHECK: battle_sides.how takes JOINED ──
  alter table public.battle_sides add constraint battle_sides_how_check_0436
    check (how = any (array['OPENED'::text, 'ESCORT'::text, 'CALLED'::text, 'ARMADA'::text, 'JOINED'::text])) not valid;
  alter table public.battle_sides drop constraint battle_sides_how_check;
  alter table public.battle_sides rename constraint battle_sides_how_check_0436 to battle_sides_how_check;
  alter table public.battle_sides validate constraint battle_sides_how_check;

  -- ── 4. THE NEW FUNCTIONS ──
  execute $f$
create function public.battle_join_for(p_player uuid, p_battle uuid, p_fleet uuid, p_side text, p_now timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0436 (docs/design/tick-combat.md 8, 9.2): A SHIP JOINS A BATTLE, the one writer. p_player: the company that asks (cmd.battle_join), or null for
-- the NPC rule (public.battle_npc_joins). p_now null: the clock is read once the battle's row is held. Raises the refusals 'E_CODE: sentence'
-- (cmd.refuse). She joins at the NEXT tick: a battle_sides row how JOINED; her hulls appended to her side of the sheet (a = DEFENDER, b =
-- ATTACKER) with `from` and `fleet`; a navy ship tied to the battle; the timeline re-run (public.tick_battle_run: the past unchanged, every side's
-- busy_until to the new end); then she is stopped to that end (public.battle_stop). Answers {ok, battle, side, from_tick}.
declare
  b       public.battles%rowtype;
  f       public.fleets%rowtype;
  v_now   timestamptz;
  v_ms    numeric;
  v_reach numeric;
  v_peace int;
  v_until timestamptz;
  v_tick  int;
  v_npc   boolean;
  v_kind  text;
  v_nm    numeric;
  v_key   text;
  v_hulls jsonb;
begin
  v_ms := public.wc_num('tick_ms');
  v_reach := public.wc_num('battle_join_nm');
  v_peace := coalesce(public.wc_int('peace_after_flee_minutes'), 0);
  if p_side is null or p_side not in ('ATTACKER', 'DEFENDER') then
    perform cmd.refuse('E_BAD_SIDE', 'a side is ATTACKER or DEFENDER');
  end if;
  select * into b from public.battles where id = p_battle for update;
  if b.id is null or b.kind not in ('RAID', 'ATTACK') then
    perform cmd.refuse('E_NO_BATTLE', 'there is no such battle');
  end if;
  v_now := coalesce(p_now, clock_timestamp());
  v_tick := greatest(1, floor(extract(epoch from v_now - b.started_at) * 1000 / v_ms)::int + 1);   -- the next tick; never tick 0 (the open's)
  if b.status <> 'FIGHTING' or b.ticks is null or v_now >= b.resolves_at or v_tick > (b.ticks ->> 'n')::int then
    perform cmd.refuse('E_BATTLE_OVER', 'that battle is over');
  end if;
  select * into f from public.fleets where id = p_fleet;
  if f.id is null or (p_player is not null and f.player_id is distinct from p_player) then
    perform cmd.refuse('E_NOT_YOUR_FLEET', 'that fleet is not yours');
  end if;
  v_kind := public.fleet_kind(p_fleet);
  if v_kind in ('MERCHANT', 'CARGO_SHIP') then
    perform cmd.refuse('E_FLEET_BUSY', format('%s: a merchant does not join a battle', f.name));
  end if;
  perform voyage.settle(p_fleet, v_now);   -- D.2: where she is now, before she is read
  select * into f from public.fleets where id = p_fleet for update;
  if f.busy_until is not null or f.status not in ('SAILING', 'ANCHORED', 'DOCKED') or (f.status = 'DOCKED' and f.ready_at > v_now)
     or exists (select 1 from public.battle_sides s where s.battle_id = p_battle and s.fleet_id = p_fleet)
     or not exists (select 1 from public.ships s where s.fleet_id = p_fleet and s.durability > 0) then
    perform cmd.refuse('E_FLEET_BUSY', format('%s is not free to fight', f.name));
  end if;
  v_until := public.fleet_peace_until(p_fleet);
  if v_until > v_now and v_peace > 0 then
    perform cmd.refuse('E_AT_PEACE', format('%s: %s', f.name, cmd.refusal_line('E_AT_PEACE',
                         cmd.figures(greatest(0, v_peace - ceil(extract(epoch from v_until - v_now) / 60)), v_peace, 'minutes'))),
                       cmd.figures(greatest(0, v_peace - ceil(extract(epoch from v_until - v_now) / 60)), v_peace, 'minutes'));
  end if;
  select p.is_npc into v_npc from public.players p where p.id = f.player_id;
  if not coalesce(v_npc, false) then
    -- NO PVP: a player's ship joins only against the world's ships. In a raid she may join only the side set upon (against the pirates).
    if b.kind = 'RAID' and p_side = 'ATTACKER' then
      perform cmd.refuse('E_BAD_SIDE', 'in a raid she may join only the ship set upon');
    end if;
    if exists (select 1 from public.battle_sides s join public.fleets o on o.id = s.fleet_id join public.players p on p.id = o.player_id
                where s.battle_id = p_battle and s.side <> p_side and not p.is_npc) then
      perform cmd.refuse('E_HUMAN_TARGET', 'no player fights another player');
    end if;
  end if;
  select voyage.gc_distance_nm((b.site ->> 'lat')::float8, (b.site ->> 'lon')::float8, pt.lat::float8, pt.lon::float8)::numeric into v_nm
    from voyage.fleet_point(p_fleet, v_now) pt;
  if v_nm is null or v_nm > v_reach then
    perform cmd.refuse('E_NOT_IN_REACH', format('%s is %s miles off the fight, and the circle is %s', f.name, round(coalesce(v_nm, 0)), round(v_reach)),
                       cmd.figures(v_reach, greatest(v_reach, coalesce(round(v_nm, 1), v_reach)), 'miles'));
  end if;

  insert into public.battle_sides (battle_id, fleet_id, side, joined_at, arrives_at, how) values (p_battle, p_fleet, p_side, v_now, v_now, 'JOINED');
  v_key := case p_side when 'DEFENDER' then 'a' else 'b' end;
  select coalesce(jsonb_agg(h || jsonb_build_object('from', v_tick, 'fleet', p_fleet) order by o), '[]'::jsonb) into v_hulls
    from jsonb_array_elements(coalesce(voyage.fleet_hulls(p_fleet), '[]'::jsonb)) with ordinality x(h, o);
  update public.battles set sheet = jsonb_set(sheet, array[v_key], coalesce(sheet -> v_key, '[]'::jsonb) || v_hulls) where id = p_battle;
  update public.navy_ships n set battle_id = p_battle where n.fleet_id = p_fleet;   -- freed (and her mission reset) by public.navy_close
  perform public.tick_battle_run(p_battle);
  select resolves_at into v_until from public.battles where id = p_battle;
  perform public.battle_stop(p_fleet, v_until, v_now);
  return jsonb_build_object('ok', true, 'battle', p_battle, 'side', p_side, 'from_tick', v_tick);
end
$body$;
$f$;
  revoke all on function public.battle_join_for(uuid, uuid, uuid, text, timestamptz) from public, anon, authenticated;

  execute $f$
create function cmd.battle_join(p_battle uuid, p_fleet uuid, p_side text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0436 (docs/design/tick-combat.md 9.2): THE JOIN DOOR. A fleet of the signed-in company, inside a battle's circle and free, joins a side
-- (ATTACKER or DEFENDER) from the next tick. The core is public.battle_join_for; a refusal is the envelope, as every cmd door.
-- {ok, battle, side, from_tick} or E_NO_HOUSE, E_BAD_SIDE, E_NO_BATTLE, E_BATTLE_OVER, E_NOT_YOUR_FLEET, E_FLEET_BUSY, E_AT_PEACE, E_HUMAN_TARGET, E_NOT_IN_REACH.
declare
  v_player uuid := public.current_player_id();
  v_det    text;
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_HOUSE', 'error_message', 'Found a house first.', 'fixes', '[]'::jsonb);
  end if;
  begin
    return public.battle_join_for(v_player, p_battle, p_fleet, p_side, null);
  exception when others then
    if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
    get stacked diagnostics v_det = pg_exception_detail;
    return cmd.refused_envelope(sqlerrm, v_det);
  end;
end
$body$;
$f$;
  revoke all on function cmd.battle_join(uuid, uuid, text) from public, anon;
  grant execute on function cmd.battle_join(uuid, uuid, text) to authenticated;
  comment on function cmd.battle_join(uuid, uuid, text) is
    '0436: the door of public.battle_join_for for the signed-in company (a refusal is the envelope, as every cmd door).';

  execute $f$
create function public.battle_join_near(p_battle uuid, p_kind text, p_now timestamptz)
returns table (fleet_id uuid, nm numeric)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0436: THE NPC SHIPS THAT MIGHT JOIN A BATTLE, nearest first, at most 4: p_kind NAVY (in service, PATROL or HUNT, not tied to a battle) or PIRATE
-- (public.pirate_ships_cruising), free (busy_until null, out of her port time). A sieve, as public.raid_target's: a sailing ship placed roughly
-- between her two harbours by the clock, one at anchor at her anchor, one in port at her harbour; within battle_join_nm + 120 miles. The core
-- (public.battle_join_for) measures her exactly. Never a merchant or a cargo ship.
declare
  v_lat   float8;
  v_lon   float8;
  v_reach numeric;
begin
  v_reach := public.wc_num('battle_join_nm');
  select (b.site ->> 'lat')::float8, (b.site ->> 'lon')::float8 into v_lat, v_lon from public.battles b where b.id = p_battle;
  if v_lat is null or v_reach is null or p_kind not in ('NAVY', 'PIRATE') then
    return;
  end if;
  return query
    select c.id, c.nm
      from (select s.id, s.nm
              from (select f.id, voyage.gc_distance_nm(v_lat, v_lon, (a.lat + (z.lat - a.lat) * w.k)::float8, (a.lon + (z.lon - a.lon) * w.k)::float8)::numeric as nm
                      from public.voyages v
                      join public.fleets f on f.id = v.fleet_id
                      join public.ports a on a.id = v.origin_port_id
                      join public.ports z on z.id = v.dest_port_id
                     cross join lateral (select least(1, greatest(0, extract(epoch from p_now - v.departed_at)
                                                                   / nullif(extract(epoch from v.eta - v.departed_at), 0)))::numeric as k) w
                     where v.status = 'SAILING' and f.status = 'SAILING' and f.busy_until is null
                       and f.id in (select n.fleet_id from public.navy_ships n
                                     where p_kind = 'NAVY' and n.laid_up_at is null and n.battle_id is null and n.mission in ('PATROL', 'HUNT')
                                    union all
                                    select q.fleet_id from public.pirate_ships_cruising q where p_kind = 'PIRATE')
                    union all
                    select f.id, voyage.gc_distance_nm(v_lat, v_lon, coalesce(f.lat, p.lat)::float8, coalesce(f.lon, p.lon)::float8)::numeric
                      from public.fleets f left join public.ports p on p.id = f.port_id
                     where f.status in ('ANCHORED', 'DOCKED') and f.busy_until is null and (f.ready_at is null or f.ready_at <= p_now)
                       and coalesce(f.lat, p.lat) is not null
                       and f.id in (select n.fleet_id from public.navy_ships n
                                     where p_kind = 'NAVY' and n.laid_up_at is null and n.battle_id is null and n.mission in ('PATROL', 'HUNT')
                                    union all
                                    select q.fleet_id from public.pirate_ships_cruising q where p_kind = 'PIRATE')) s
             where s.nm <= v_reach + 120
             offset 0) c
     order by c.nm, c.id
     limit 4;
end
$body$;
$f$;
  revoke all on function public.battle_join_near(uuid, text, timestamptz) from public, anon, authenticated;

  execute $f$
create function public.battle_npc_joins(p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0436 (docs/design/tick-combat.md 8): THE NPC JOIN RULE, once a minute from public.tick_pirates (after its strikes; never behind a trade's locks).
-- Joining is a choice: a ship in the circle is never pulled in. For each live tick RAID (newest first, at most battle_join_battles_per_run), rolled
-- on md5(battle, minute, kind): NAVY with battle_join_navy_chance (the navy switch lit) joins the side set upon, PIRATE with
-- battle_join_pirate_chance joins the pirates' side; at most battle_join_per_battle a battle a run, battle_join_per_side JOINED a side, and
-- battle_join_per_run a run. A battle is taken SKIP LOCKED, a candidate (public.battle_join_near) SKIP LOCKED; each try in a block of its own
-- (public.battle_join_for; a refusal passes to the next). Merchants never join. Never raises. Answers {NAVY: n, PIRATE: n} (only those that joined).
declare
  v_navy_p    numeric;
  v_pir_p     numeric;
  v_per_b     int;
  v_per_side  int;
  v_per_run   int;
  v_battles   int;
  v_navy_on   boolean;
  v_turn      text := floor(extract(epoch from p_now) / 60)::bigint::text;
  v_n         int := 0;
  v_k         int;
  v_kind      text;
  v_side      text;
  v_ok        boolean;
  v_out       jsonb := '{}'::jsonb;
  b           record;
  c           record;
begin
  v_navy_p := coalesce(public.wc_num('battle_join_navy_chance'), 0);
  v_pir_p := coalesce(public.wc_num('battle_join_pirate_chance'), 0);
  v_per_b := coalesce(public.wc_int('battle_join_per_battle'), 0);
  v_per_side := coalesce(public.wc_int('battle_join_per_side'), 0);
  v_per_run := coalesce(public.wc_int('battle_join_per_run'), 0);
  v_battles := coalesce(public.wc_int('battle_join_battles_per_run'), 0);
  begin
    if v_per_run <= 0 or v_per_b <= 0 or v_battles <= 0 or not public.attack_on() then
      return v_out;
    end if;
    v_navy_on := public.navy_on();
    for b in select x.id from public.battles x
              where x.status = 'FIGHTING' and x.kind = 'RAID' and x.ticks is not null and x.resolves_at > p_now
              order by x.started_at desc, x.id limit v_battles loop
      exit when v_n >= v_per_run;
      v_k := 0;
      foreach v_kind in array array['NAVY', 'PIRATE'] loop
        exit when v_k >= v_per_b or v_n >= v_per_run;
        continue when v_kind = 'NAVY' and not v_navy_on;
        continue when ('x' || substr(md5(b.id::text || ':' || v_turn || ':' || v_kind), 1, 8))::bit(32)::bigint / 4294967296.0
                      >= case v_kind when 'NAVY' then v_navy_p else v_pir_p end;
        v_side := case v_kind when 'NAVY' then 'DEFENDER' else 'ATTACKER' end;
        continue when (select count(*) from public.battle_sides s where s.battle_id = b.id and s.side = v_side and s.how = 'JOINED') >= v_per_side;
        perform 1 from public.battles x where x.id = b.id and x.status = 'FIGHTING' for update skip locked;
        continue when not found;
        v_ok := false;
        for c in select j.fleet_id from public.battle_join_near(b.id, v_kind, p_now) j loop
          perform 1 from public.fleets f where f.id = c.fleet_id for update skip locked;
          continue when not found;
          begin
            perform public.battle_join_for(null, b.id, c.fleet_id, v_side, p_now);
            v_ok := true;
          exception when others then
            if sqlerrm !~ '^E_[A-Z0-9_]+:' then
              raise warning 'battle_npc_joins: fleet % did not join % (SQLSTATE %: %)', c.fleet_id, b.id, sqlstate, sqlerrm;
            end if;
          end;
          exit when v_ok;
        end loop;
        if v_ok then
          v_k := v_k + 1;
          v_n := v_n + 1;
          v_out := v_out || jsonb_build_object(v_kind, coalesce((v_out ->> v_kind)::int, 0) + 1);
        end if;
      end loop;
    end loop;
  exception when others then
    raise warning 'battle_npc_joins: the run stopped (SQLSTATE %: %)', sqlstate, sqlerrm;
    v_out := v_out || jsonb_build_object('ERROR', 1);
  end;
  return v_out;
end
$body$;
$f$;
  revoke all on function public.battle_npc_joins(timestamptz) from public, anon, authenticated;

  -- ── 5. THE HUNKS (each occurs exactly once in the live body, and reverses) ──
  create temp table hunks_0436 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0436 values
  ('public.client_rpc_entry_points()', 1,
$h$      ('cmd',         'battle_stance',         'uuid, text'),
$h$,
$h$      ('cmd',         'battle_stance',         'uuid, text'),
      -- 0436: a fleet inside a battle's circle joins a side (docs/design/tick-combat.md 9.2).
      ('cmd',         'battle_join',           'uuid, uuid, text'),
$h$),
  ('public.tick_pirates(timestamp with time zone)', 1,
$h$         || case when v_lit and current_setting('byeharu.pirate_traded', true) is distinct from 'on' then jsonb_build_object('purses', public.pirate_purse_step(p_now)) else '{}'::jsonb end;$h$,
$h$         || case when v_lit and current_setting('byeharu.pirate_traded', true) is distinct from 'on' then jsonb_build_object('purses', public.pirate_purse_step(p_now)) else '{}'::jsonb end
         -- 0436: navy and pirate ships nearby may join a live raid (public.battle_npc_joins, which never raises), after the strikes, as they are
         || case when v_lit and current_setting('byeharu.pirate_traded', true) is distinct from 'on' then jsonb_build_object('joined', public.battle_npc_joins(p_now)) else '{}'::jsonb end;$h$),
  ('public.navy_close(uuid,timestamp with time zone)', 1,
$h$  select count(*) filter (where bs.how not in ('OPENED', 'ARMADA') and bs.arrives_at <= b.resolves_at),   -- 0395: her own armada is no navy$h$,
$h$  select count(*) filter (where bs.how not in ('OPENED', 'ARMADA') and (bs.how <> 'JOINED' or n.fleet_id is not null) and bs.arrives_at <= b.resolves_at),   -- 0395: her own armada is no navy; 0436: nor a pirate that joined$h$),
  ('public.navy_close(uuid,timestamp with time zone)', 2,
$h$         bool_or(bs.how not in ('OPENED', 'ARMADA') and bs.arrives_at <= b.resolves_at or (bs.how = 'OPENED' and bs.side = 'DEFENDER' and n.fleet_id is not null))$h$,
$h$         bool_or(bs.how not in ('OPENED', 'ARMADA') and (bs.how <> 'JOINED' or n.fleet_id is not null) and bs.arrives_at <= b.resolves_at or (bs.how = 'OPENED' and bs.side = 'DEFENDER' and n.fleet_id is not null))$h$);

  for v_h in select h.fn from hunks_0436 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0436 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0436 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0436 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0436 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0436 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 6. SELF-ASSERT: the catalog, the door, the knobs, the check ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_new) u(q)))) <> v_fn_before then
    raise exception '0436 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0436 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked function moved';
  end if;
  if exists (select 1 from unnest(c_new) f
              where f <> 'cmd.battle_join(uuid,uuid,text)'
                and (has_function_privilege('anon', f::regprocedure, 'execute') or has_function_privilege('authenticated', f::regprocedure, 'execute')
                     or exists (select 1 from public.client_rpc_entry_points() e where e.fn = f::regprocedure))) then
    raise exception '0436 self-assert FAIL: a server-only function of this file is open to clients';
  end if;
  if not has_function_privilege('authenticated', 'cmd.battle_join(uuid,uuid,text)'::regprocedure, 'execute')
     or has_function_privilege('anon', 'cmd.battle_join(uuid,uuid,text)'::regprocedure, 'execute')
     or not exists (select 1 from public.client_rpc_entry_points() e
                     where e.schema_name = 'cmd' and e.function_name = 'battle_join' and e.arg_types = 'uuid, uuid, text' and e.fn is not null) then
    raise exception '0436 self-assert FAIL: the door is not open to a signed-in player, or not registered';
  end if;
  if (select count(*) from public.world_config w where w.key like 'battle_join\_%' and w.key <> 'battle_join_nm') <> 6 then
    raise exception '0436 self-assert FAIL: the knobs are not this file''s';
  end if;
  if (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = 'public.battle_sides'::regclass and c.conname = 'battle_sides_how_check') not like '%JOINED%'
     or not (select c.convalidated from pg_constraint c where c.conrelid = 'public.battle_sides'::regclass and c.conname = 'battle_sides_how_check') then
    raise exception '0436 self-assert FAIL: battle_sides.how does not take JOINED, or the check is not validated';
  end if;

  -- ── 7. THE NEWS (0347's law) ──
  perform public.news_update('0436', 'A ship may join a fight in its circle; navy and pirate ships nearby sometimes do',
                             '전투 원 안의 배는 싸움에 합류할 수 있다; 근처의 해군과 해적도 때때로 합류한다');

  -- ── 8. THE PROBE, rolled back by a raised sentinel (lit inside it, so it runs on every world) ──
  begin
    update public.world_config set value = 'true'::jsonb where key = 'attack_enabled' and value is distinct from 'true'::jsonb;
    update public.world_config set value = '["RAID", "ATTACK"]'::jsonb where key = 'tick_fight_kinds';
    select nf.fleet_id into v_m
      from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id
     where exists (select 1 from public.ships s where s.fleet_id = nf.fleet_id and s.durability > 0)
     order by nf.fleet_id limit 1;
    if v_m is null then
      raise exception '0436 self-assert FAIL: no company merchant with a hull in this world to probe on';
    end if;
    select p.lat, p.lon into v_lat, v_lon from public.ports p where p.code = 'LIS';
    v_lat := v_lat + 0.3;
    v_lon := v_lon - 0.6;
    v_p1 := public.new_house(c_u1, 'Casa Uno 0436', 'PRT', 'LIS', 'Uno 0436', 'galion', 'Uno 0436', null, false);
    v_p2 := public.new_house(c_u2, 'Casa Dos 0436', 'PRT', 'LIS', 'Dos 0436', 'galion', 'Dos 0436', null, false);
    v_p3 := public.new_house(c_u3, 'Casa Tres 0436', 'PRT', 'LIS', 'Tres 0436', 'galion', 'Tres 0436', null, false);
    select f.id into v_f1 from public.fleets f where f.player_id = v_p1;
    select f.id into v_f2 from public.fleets f where f.player_id = v_p2;
    select f.id into v_f3 from public.fleets f where f.player_id = v_p3;
    update public.voyages v set status = 'ABORTED' where v.fleet_id in (v_m, v_f1, v_f2, v_f3) and v.status = 'SAILING';
    update public.fleets f set status = 'ANCHORED', port_id = null, busy_until = null, ready_at = null, version = f.version + 1,
                               lat = case when f.id = v_f3 then v_lat + 2 else v_lat end, lon = v_lon
     where f.id in (v_m, v_f1, v_f2, v_f3);
    update public.ships s set crew = (select b.crew_max from public.ship_base(s.id) b), durability = (select b.durability from public.ship_base(s.id) b)
     where s.fleet_id in (v_m, v_f1, v_f2, v_f3);
    v_b := public.battle_open('ATTACK', v_f1, v_m, clock_timestamp());
    -- the battle starts now, on the wall clock: the door reads clock_timestamp()
    update public.battles bt set resolves_at = clock_timestamp() + (bt.resolves_at - bt.started_at), started_at = clock_timestamp() where bt.id = v_b;
    select * into v_bt from public.battles bt where bt.id = v_b;
    if v_bt.ticks is null then
      raise exception '0436 self-assert FAIL: an ATTACK under tick_fight_kinds has no timeline';
    end if;
    v_k0 := coalesce((v_bt.ticks ->> 'k')::int, 0);
    v_nb := jsonb_array_length(v_bt.sheet -> 'b');

    perform cmd.assume_identity(c_u2);
    v_r := cmd.battle_join(v_b, v_f2, 'NAVY');
    if v_r ->> 'error_code' is distinct from 'E_BAD_SIDE' then raise exception '0436 self-assert FAIL: a bad side: %', v_r; end if;
    v_r := cmd.battle_join(gen_random_uuid(), v_f2, 'ATTACKER');
    if v_r ->> 'error_code' is distinct from 'E_NO_BATTLE' then raise exception '0436 self-assert FAIL: no battle: %', v_r; end if;
    v_r := cmd.battle_join(v_b, v_f1, 'ATTACKER');
    if v_r ->> 'error_code' is distinct from 'E_NOT_YOUR_FLEET' then raise exception '0436 self-assert FAIL: not her fleet: %', v_r; end if;
    v_r := cmd.battle_join(v_b, v_f2, 'DEFENDER');   -- against the player who attacked: no PvP
    if v_r ->> 'error_code' is distinct from 'E_HUMAN_TARGET' then raise exception '0436 self-assert FAIL: a player joined against a player: %', v_r; end if;
    perform cmd.assume_identity(c_u3);
    v_r := cmd.battle_join(v_b, v_f3, 'ATTACKER');   -- 120 miles off
    if v_r ->> 'error_code' is distinct from 'E_NOT_IN_REACH' or v_r ->> 'error_message' not like 'Range % / % miles' then
      raise exception '0436 self-assert FAIL: out of the circle: %', v_r;
    end if;
    v_note := v_r ->> 'error_message';

    perform cmd.assume_identity(c_u2);
    v_r := cmd.battle_join(v_b, v_f2, 'ATTACKER');
    if not coalesce((v_r ->> 'ok')::boolean, false) or (v_r ->> 'from_tick')::int < 1 then
      raise exception '0436 self-assert FAIL: a free player''s ship in the circle could not join: %', v_r;
    end if;
    select * into v_bt from public.battles bt where bt.id = v_b;
    if not exists (select 1 from public.battle_sides s where s.battle_id = v_b and s.fleet_id = v_f2 and s.side = 'ATTACKER' and s.how = 'JOINED')
       or jsonb_array_length(v_bt.sheet -> 'b') <= v_nb
       or exists (select 1 from jsonb_array_elements(v_bt.sheet -> 'b') with ordinality e(h, o)
                   where o > v_nb and ((e.h ->> 'from')::int is distinct from (v_r ->> 'from_tick')::int or e.h ->> 'fleet' is distinct from v_f2::text))
       or coalesce((v_bt.ticks ->> 'k')::int, 0) <> v_k0 + 1 then
      raise exception '0436 self-assert FAIL: the join is not on the sheet with its tick, or the timeline was not re-run (k % -> %)', v_k0, v_bt.ticks ->> 'k';
    end if;
    if (select f.busy_until from public.fleets f where f.id = v_f2) is distinct from v_bt.resolves_at
       or (select f.status from public.fleets f where f.id = v_f2) <> 'IN_BATTLE' then
      raise exception '0436 self-assert FAIL: the ship that joined is not held to the battle''s end';
    end if;
    v_r := cmd.battle_join(v_b, v_f2, 'ATTACKER');
    if v_r ->> 'error_code' is distinct from 'E_FLEET_BUSY' then raise exception '0436 self-assert FAIL: joined twice: %', v_r; end if;
    begin
      perform public.battle_join_for(null, v_b, v_m, 'ATTACKER', null);
      raise exception '0436 self-assert FAIL: a merchant joined a battle';
    exception when others then
      if sqlerrm not like 'E_FLEET_BUSY:%' then raise; end if;
    end;
    perform cmd.assume_identity(c_u3);
    update public.fleets f set lat = v_lat where f.id = v_f3;
    update public.battles bt set status = 'RESOLVED' where bt.id = v_b;
    v_r := cmd.battle_join(v_b, v_f3, 'ATTACKER');
    if v_r ->> 'error_code' is distinct from 'E_BATTLE_OVER' then raise exception '0436 self-assert FAIL: joined a battle that is over: %', v_r; end if;
    v_r := public.battle_npc_joins(clock_timestamp());
    if v_r ? 'ERROR' then
      raise exception '0436 self-assert FAIL: the NPC join step raised: %', v_r;
    end if;
    raise exception sqlstate 'BV436';
  exception when sqlstate 'BV436' then null;
  end;
  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0436 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0436 self-assert ok: A SHIP MAY JOIN A FIGHT. % hunks once each and reversing; no other function moved; the door open and registered, 3 functions server-only; 6 knobs; how takes JOINED. Probe (rolled back): every refusal (out of the circle: %), a player joined at the next tick, re-run k+1, held to the end; the NPC step answered; % ms.',
    (select count(*) from hunks_0436), v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0436;
end $m$;
