-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 66 — A FIGHT SHOWS ON THE MAP  (migration 0364, owner row 321)
--
--   The migration's self-assert plays one probe battle between two barcas and closes it by hand. Here the game is real: a real company's gunned fleet, a real cargo ship at sea,
--   the REAL attack (cmd.attack), the REAL door (cmd.battle_stance), the REAL job (public.tick_battles) and close. The map's read (world.fights) and the watcher's read
--   (world.fight) are read by the company whose battle it is, by a neighbour, and by a caller with no house. Everything rolls back with proof.mjs's transaction; every switch this
--   proof needs it writes here.
--
-- @pass FIGHTS_DARK     attack_enabled false and no battle: a house reads {on: false, fights: []} and a battle that is none is {on: false}; anon may call neither door; the card is server-only; both doors are registered once
-- @pass FIGHTS_CARD     lit, a real attack: a neighbour reads the battle at the place the ship set upon was, its clock, both fleets with kind, company, country, ships and where each lies now; `mine` is the attacker's fleet for her and null for the neighbour; a called ship on her way is listed, not counted, and has no place; one that has come up is counted
-- @pass WATCH_LOG       the watcher's log is her own card's log key for key before the first round, after two rounds and closed; it carries only the keys 0364 names; her own card has the word, the stance, the loot and the hands, the watcher's read has none of them; a neighbour cannot set a stance
-- @pass FIGHTS_KEPT     closed by the real job: the card carries the ending and no fleet's place, stays for keep_seconds and then leaves the map; its log can still be read
-- @pass FIGHTS_STABLE   neither read writes or advances: with two rounds due and unfought, the battle's row, its rounds and its stances are the same text before and after both reads
-- @pass FIGHTS_COST     the read with 0, 1 and 20 battles being fought, timed (printed, never judged): 20 battles are served, oldest first
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $$
begin
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed', 'convoys_enabled', 'combat_bite');
  update public.world_config set value = 'false'::jsonb where key in ('attack_enabled', 'regard_enabled', 'npc_refits_enabled', 'navy_enabled', 'pirates_bite', 'raid_orders_enabled');
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 50000000, reserve = 0;

  -- a human company of Portugal, her one fleet in Lisbon, 100 hands, the best guns there are, her hold empty (proof 60's house)
  execute $f$
create function pg_temp.house_66(p_n int)
returns uuid
language plpgsql
as $b$
declare
  v_uid uuid := ('00000000-0364-4000-8000-' || lpad(p_n::text, 12, '0'))::uuid;
  v_p   uuid := public.new_house(v_uid, 'Casa Ronda ' || p_n, 'PRT', 'LIS', 'Ronda ' || p_n,
                                 (select c.code from public.ship_classes c order by c.attack desc, c.code limit 1), 'Ronda ' || p_n, null, false);
  v_f   uuid;
begin
  select id into v_f from public.fleets where player_id = v_p;
  update public.ships set crew = 100, cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb, water_t = 100000, food_t = 100000 where fleet_id = v_f;
  return v_f;
end
$b$
  $f$;

  -- the next cargo ship in port, not of Portugal, with p_ducats aboard, sailed at p_at and slowed so she is still at sea when the proof looks (proof 60's ship)
  execute $f$
create function pg_temp.ship_66(p_ducats bigint, p_at timestamptz)
returns uuid
language plpgsql
as $b$
declare
  c    public.cargo_ships%rowtype;
  v_st text;
begin
  select x.* into c
    from public.cargo_ships x join public.nations n on n.id = x.nation_id join public.fleets f on f.id = x.fleet_id
   where f.status = 'DOCKED' and x.out_load is null and n.code <> 'PRT'
     and not exists (select 1 from public.cargo_ship_aboard(x.fleet_id))
   order by n.code, x.ord limit 1;
  if c.fleet_id is null then
    raise exception 'PROOF 66 FAIL: no cargo ship left to sail';
  end if;
  update public.fleets set ready_at = null where id = c.fleet_id;
  perform public.convoy_book('LOADED', c.fleet_id, c.player_id, c.home_port_id, p_ducats);
  v_st := public.cargo_ship_step(c.fleet_id, p_at);
  if v_st <> 'SAILED' then
    raise exception 'PROOF 66 FAIL: the cargo ship did not sail: %', v_st;
  end if;
  update public.voyages vo set speed_profile = (select jsonb_agg(to_jsonb(e::text::numeric / 100) order by o) from jsonb_array_elements(vo.speed_profile) with ordinality t(e, o))
   where vo.fleet_id = c.fleet_id and vo.status = 'SAILING';
  perform voyage.recompute_eta((select vo.id from public.voyages vo where vo.fleet_id = c.fleet_id and vo.status = 'SAILING'));
  return c.fleet_id;
end
$b$
  $f$;

  -- lay a fleet at anchor p_north degrees north of her target's point
  execute $f$
create function pg_temp.lie_by_66(p_fleet uuid, p_target uuid, p_at timestamptz, p_north numeric default 0)
returns void
language sql
as $b$
  update public.fleets f set status = 'ANCHORED', port_id = null, lat = p.lat + p_north, lon = p.lon, version = f.version + 1
    from voyage.fleet_point(p_target, p_at) p where f.id = p_fleet
$b$
  $f$;

  -- every great power's ships and circuits
  declare
    v_nat uuid;
    v_n   int;
  begin
    for v_nat in select g.nation_id from public.great_powers g loop
      for v_n in 1 .. 3 loop
        perform public.tick_cargo_ships(now(), v_nat);
      end loop;
    end loop;
  end;
end
$$;

do $p$
declare
  c_uid   constant uuid := '00000000-0364-4000-8000-000000000001';
  c_uid2  constant uuid := '00000000-0364-4000-8000-000000000002';
  c_keys  constant text[] := array['v', 'atk', 'first', 'foe', 'you', 'r', 'board', 'after', 'end'];
  v_n     int := jsonb_array_length(public.wc('fight_ranges'));
  a       uuid;
  a2      uuid;
  d       uuid;
  x       uuid;
  v_bat   uuid;
  v_t     timestamptz;
  v_x     jsonb;
  v_r     jsonb;
  v_c     jsonb;
  v_w     jsonb;
  v_own   jsonb;
  v_site  jsonb;
  v_txt   text;
  v_i     int;
  v_tq    timestamptz;
  v_ms    numeric[] := '{}';
  v_k     int;
  v_called uuid;
  v_came   uuid;
begin
  a := pg_temp.house_66(1);
  a2 := pg_temp.house_66(2);

  -- ══ FIGHTS_DARK ══
  perform cmd.assume_identity(c_uid2);
  if world.fights() - 'now' is distinct from '{"on": false, "keep_seconds": 60, "fights": []}'::jsonb or world.fight(gen_random_uuid()) is distinct from '{"on": false}'::jsonb then
    raise exception 'PROOF 66 FAIL: dark, the reads: % and %', world.fights(), world.fight(gen_random_uuid());
  end if;
  if has_function_privilege('anon', 'world.fights()', 'execute') or has_function_privilege('anon', 'world.fight(uuid)', 'execute')
     or not has_function_privilege('authenticated', 'world.fights()', 'execute') or not has_function_privilege('authenticated', 'world.fight(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.fight_card(uuid,uuid)', 'execute') or has_function_privilege('anon', 'public.fight_card(uuid,uuid)', 'execute')
     or (select count(*) from public.client_rpc_entry_points() e where e.fn = any (array['world.fights()'::regprocedure, 'world.fight(uuid)'::regprocedure])) is distinct from 2 then
    raise exception 'PROOF 66 FAIL: the doors'' grants or registry rows';
  end if;
  raise notice 'PASS: FIGHTS_DARK — attack_enabled false and no battle: a house reads {on: false, fights: []}, a battle that is none is {on: false}; anon may call neither door, no client may call the card, both doors are registered once';

  -- ══ FIGHTS_CARD: the real attack, her fleet at anchor 0.3 degrees north of a cargo ship at sea ══
  update public.world_config set value = 'true'::jsonb where key = 'attack_enabled';
  d := pg_temp.ship_66(100000, now());
  perform pg_temp.lie_by_66(a, d, now(), 0.3);
  perform cmd.assume_identity(c_uid);
  v_x := cmd.attack(a, d);
  v_bat := (v_x ->> 'battle_id')::uuid;
  if (v_x ->> 'ok')::boolean is not true or v_bat is null then
    raise exception 'PROOF 66 FAIL: cmd.attack did not open the battle: %', v_x;
  end if;
  select b.site, b.started_at into v_site, v_t from public.battles b where b.id = v_bat;
  v_own := world.battle(a);
  select e into v_c from jsonb_array_elements(world.fights() -> 'fights') e where e ->> 'id' = v_bat::text;
  if v_c ->> 'mine' is distinct from a::text or world.fight(v_bat) ->> 'mine' is distinct from a::text then
    raise exception 'PROOF 66 FAIL: her own battle is not said to be hers: %', v_c;
  end if;
  perform cmd.assume_identity(c_uid2);
  v_r := world.fights();
  select e into v_c from jsonb_array_elements(v_r -> 'fights') e where e ->> 'id' = v_bat::text;
  if (v_r ->> 'on')::boolean is not true or jsonb_array_length(v_r -> 'fights') is distinct from 1 or v_c ->> 'status' is distinct from 'FIGHTING'
     or (v_c ->> 'lat')::numeric is distinct from (v_site ->> 'lat')::numeric or (v_c ->> 'lon')::numeric is distinct from (v_site ->> 'lon')::numeric
     or (v_c ->> 'fleets')::int is distinct from 2 or (v_c ->> 'ships')::int is distinct from (select count(*)::int from public.ships s where s.fleet_id in (a, d))
     or v_c -> 'mine' is distinct from 'null'::jsonb or (v_c ->> 'rounds')::int is distinct from v_n or (v_c ->> 'rounds_done')::int is distinct from 0
     or (v_c ->> 'round_seconds')::int is distinct from 60 or (v_c ->> 'next_at')::timestamptz is distinct from v_t + interval '60 seconds'
     or (v_c ->> 'resolves_at')::timestamptz is distinct from v_t + make_interval(secs => 60 * (v_n + 1)) or v_c ? 'end'
     or jsonb_array_length(v_c -> 'sides') is distinct from 2
     or (v_c -> 'sides' -> 0) - 'at' is distinct from jsonb_build_object('fleet', a, 'name', 'Ronda 1', 'side', 'ATTACKER', 'how', 'OPENED', 'kind', 'COMPANY', 'company', 'Casa Ronda 1', 'nation', 'PRT',
                                                        'ships', (select count(*)::int from public.ships s where s.fleet_id = a), 'here', true)
     or (v_c -> 'sides' -> 1) - 'at' is distinct from jsonb_build_object('fleet', d, 'name', (select f.name from public.fleets f where f.id = d), 'side', 'DEFENDER', 'how', 'OPENED', 'kind', 'CARGO_SHIP',
                                                        'company', null, 'nation', (select n.code from public.cargo_ships c join public.nations n on n.id = c.nation_id where c.fleet_id = d),
                                                        'ships', (select count(*)::int from public.ships s where s.fleet_id = d), 'here', true)
     -- where each lies now: her anchor, 0.3 degrees north of the place; the ship set upon is held at the place
     or (v_c -> 'sides' -> 0 -> 'at' ->> 0)::numeric is distinct from (v_site ->> 'lat')::numeric + 0.3 or (v_c -> 'sides' -> 0 -> 'at' ->> 1)::numeric is distinct from (v_site ->> 'lon')::numeric
     or abs((v_c -> 'sides' -> 1 -> 'at' ->> 0)::numeric - (v_site ->> 'lat')::numeric) > 0.01 or abs((v_c -> 'sides' -> 1 -> 'at' ->> 1)::numeric - (v_site ->> 'lon')::numeric) > 0.01 then
    raise exception 'PROOF 66 FAIL: the card a neighbour reads: % (site %)', v_c, v_site;
  end if;
  if exists (select 1 from jsonb_object_keys(v_c) k where k <> all (array['id', 'status', 'lat', 'lon', 'started_at', 'resolves_at', 'round_seconds', 'rounds', 'rounds_done', 'next_at', 'fleets', 'ships', 'mine', 'sides', 'end']))
     or exists (select 1 from jsonb_array_elements(v_c -> 'sides') s, jsonb_object_keys(s) k where k <> all (array['fleet', 'name', 'side', 'how', 'kind', 'company', 'nation', 'ships', 'here', 'at'])) then
    raise exception 'PROOF 66 FAIL: the card carries a key 0364 does not name: %', v_c;
  end if;
  -- two called ships, rows of this proof (no navy is lit here): one on her way, one that has come up
  v_called := pg_temp.ship_66(1000, now());
  v_came := pg_temp.ship_66(1000, now());
  insert into public.battle_sides (battle_id, fleet_id, side, joined_at, arrives_at, how) values
    (v_bat, v_called, 'DEFENDER', v_t, 'infinity', 'CALLED'), (v_bat, v_came, 'DEFENDER', v_t, v_t, 'CALLED');
  select e into v_r from jsonb_array_elements(world.fights() -> 'fights') e where e ->> 'id' = v_bat::text;
  if (v_r ->> 'fleets')::int is distinct from 3 or jsonb_array_length(v_r -> 'sides') is distinct from 4
     or (v_r ->> 'ships')::int is distinct from (select count(*)::int from public.ships s where s.fleet_id in (a, d, v_came))
     or not exists (select 1 from jsonb_array_elements(v_r -> 'sides') s where s ->> 'fleet' = v_called::text and (s ->> 'here')::boolean is false and not s ? 'at' and s ->> 'how' = 'CALLED')
     or not exists (select 1 from jsonb_array_elements(v_r -> 'sides') s where s ->> 'fleet' = v_came::text and (s ->> 'here')::boolean and s ? 'at' and s ->> 'side' = 'DEFENDER') then
    raise exception 'PROOF 66 FAIL: a called ship on her way was counted or placed, or one that came up was not: %', v_r;
  end if;
  delete from public.battle_sides bs where bs.battle_id = v_bat and bs.fleet_id in (v_called, v_came);
  raise notice 'PASS: FIGHTS_CARD — a neighbour reads another company''s battle: at the place of the ship set upon (%), its clock (round 0 of %, the next in 60 s), 2 fleets and % ships, the attacker a COMPANY of PRT with its company''s name, the other a CARGO_SHIP of % with none, each with where she lies now (her anchor 0.3 degrees north; the ship held at the place); `mine` is her fleet for the attacker and null for the neighbour; only the keys 0364 names; a called ship on her way is listed with here false, no place and counts for nothing, one that has come up makes it 3 fleets',
    v_site, v_n, v_c ->> 'ships', v_c -> 'sides' -> 1 ->> 'nation';

  -- ══ WATCH_LOG, FIGHTS_STABLE: the battle is moved back 130 s (its own rows), so two rounds are due and unfought ══
  v_t := clock_timestamp() - interval '130 seconds';
  update public.battles b set started_at = v_t, resolves_at = v_t + make_interval(secs => 60 * (v_n + 1)), next_round_at = v_t + interval '60 seconds' where b.id = v_bat;
  select md5((select to_jsonb(b)::text from public.battles b where b.id = v_bat) || coalesce((select string_agg(to_jsonb(r)::text, ',' order by r.g) from public.battle_rounds r where r.battle_id = v_bat), '')
             || coalesce((select string_agg(to_jsonb(s)::text, ',' order by s.set_at) from public.battle_stances s where s.battle_id = v_bat), '')
             || (select string_agg(to_jsonb(f)::text, ',' order by f.id) from public.fleets f where f.id in (a, d))) into v_txt;
  v_r := world.fights();
  v_w := world.fight(v_bat);
  if md5((select to_jsonb(b)::text from public.battles b where b.id = v_bat) || coalesce((select string_agg(to_jsonb(r)::text, ',' order by r.g) from public.battle_rounds r where r.battle_id = v_bat), '')
         || coalesce((select string_agg(to_jsonb(s)::text, ',' order by s.set_at) from public.battle_stances s where s.battle_id = v_bat), '')
         || (select string_agg(to_jsonb(f)::text, ',' order by f.id) from public.fleets f where f.id in (a, d))) is distinct from v_txt
     or (v_w ->> 'rounds_done')::int is distinct from 0 or v_w -> 'log' -> 'r' is distinct from '[]'::jsonb
     or (select p.provolatile from pg_proc p where p.oid = 'world.fights()'::regprocedure) is distinct from 's' or (select p.provolatile from pg_proc p where p.oid = 'world.fight(uuid)'::regprocedure) is distinct from 's' then
    raise exception 'PROOF 66 FAIL: a read wrote, or fought a round that was due: %', v_w;
  end if;
  raise notice 'PASS: FIGHTS_STABLE — with two rounds due and unfought, the battle''s row, its rounds, its stances and both fleets are the same text before and after world.fights() and world.fight(): neither writes nor advances (both STABLE)';

  -- before the first round: the watcher's read against her own card
  v_own := world.battle(a);   -- read as the neighbour: nothing
  if v_own is distinct from '{"on": false}'::jsonb or cmd.battle_stance(v_bat, 'FLEE') ->> 'error_code' is distinct from 'E_NOT_YOUR_BATTLE' then
    raise exception 'PROOF 66 FAIL: a neighbour read her own-battle card, or set a stance in her battle';
  end if;
  perform cmd.assume_identity(c_uid);
  v_own := world.battle(a);
  if (v_w ->> 'on')::boolean is not true or (v_w ->> 'watch')::boolean is not true or v_w -> 'mine' is distinct from 'null'::jsonb or v_w ->> 'side' is distinct from 'ATTACKER'
     or v_w ->> 'you' is distinct from 'Ronda 1' or v_w ->> 'foe' is distinct from (select f.name from public.fleets f where f.id = d) or v_w ->> 'next_range' is distinct from 'LONG'
     or v_w -> 'log' ? 'end' or v_w -> 'log' ? 'board' or (v_w -> 'log' ->> 'atk')::boolean is not true
     or exists (select 1 from unnest(c_keys) k where (v_own -> 'log' -> k) is distinct from (v_w -> 'log' -> k))
     or exists (select 1 from jsonb_object_keys(v_w -> 'log') k where k <> all (c_keys))
     or exists (select 1 from jsonb_object_keys(v_w) k where k <> all (array['on', 'battle', 'status', 'watch', 'side', 'you', 'foe', 'mine', 'started_at', 'resolves_at', 'now', 'round_seconds', 'rounds', 'rounds_done', 'next_at', 'next_range', 'log']))
     or not (v_own ? 'word' and v_own ? 'stance' and v_own ? 'may') then
    raise exception 'PROOF 66 FAIL: the watcher''s read before the first round: % against her card %', v_w, v_own;
  end if;
  -- her door fights the two rounds due; the watcher's log is her card's, two rounds, nothing told early
  v_x := cmd.battle_stance(v_bat, 'FIGHT');
  v_own := world.battle(a);
  perform cmd.assume_identity(c_uid2);
  v_w := world.fight(v_bat);
  select e into v_c from jsonb_array_elements(world.fights() -> 'fights') e where e ->> 'id' = v_bat::text;
  if v_own ->> 'status' = 'FIGHTING' and ((v_w ->> 'rounds_done')::int is distinct from 2 or jsonb_array_length(v_w -> 'log' -> 'r') is distinct from 2 or v_w -> 'log' ? 'end' or v_w -> 'log' ? 'board'
       or (v_c ->> 'rounds_done')::int is distinct from 2 or (v_c ->> 'next_at')::timestamptz is distinct from v_t + interval '180 seconds'
       or v_w ->> 'next_range' is distinct from (public.wc('fight_ranges') -> 2 ->> 0))
     or exists (select 1 from unnest(c_keys) k where (v_own -> 'log' -> k) is distinct from (v_w -> 'log' -> k))
     or exists (select 1 from jsonb_object_keys(v_w -> 'log') k where k <> all (c_keys)) then
    raise exception 'PROOF 66 FAIL: the watcher''s read after two rounds: % against her card %', v_w, v_own;
  end if;
  v_i := jsonb_array_length(v_w -> 'log' -> 'r');

  -- ══ FIGHTS_KEPT: to its end by the real job ══
  v_k := public.tick_battles(v_t + interval '1 hour');
  v_w := world.fight(v_bat);
  select e into v_c from jsonb_array_elements(world.fights() -> 'fights') e where e ->> 'id' = v_bat::text;
  perform cmd.assume_identity(c_uid);
  v_own := world.battle(a);
  perform cmd.assume_identity(c_uid2);
  if (select b.status from public.battles b where b.id = v_bat) not in ('RESOLVED', 'BROKEN_OFF')
     or coalesce(v_w -> 'log' ->> 'end', '') not in ('A_NONE', 'A_LOST', 'FLED', 'A_BROKE', 'A_THROWN', 'A_TERMS', 'A_TOOK')
     or exists (select 1 from unnest(c_keys) k where (v_own -> 'log' -> k) is distinct from (v_w -> 'log' -> k))
     or exists (select 1 from jsonb_object_keys(v_w -> 'log') k where k <> all (c_keys))
     or v_w ? 'loot' or v_w ? 'crew_lost' or v_w ? 'outcome' or v_w ? 'navy' or v_w ? 'word' or v_w ? 'stance' or v_w ? 'may' or v_w -> 'next_at' is distinct from 'null'::jsonb
     or not (v_own ? 'loot' and v_own ? 'crew_lost' and v_own ? 'outcome')
     or v_w::text ~* '"[a-z_]*(ducat|cargo|purse|funds|loot)[a-z_]*":' then   -- no KEY of that kind (a ship's name may say anything)
    raise exception 'PROOF 66 FAIL: the watcher''s read of a closed battle: % against her card %', v_w, v_own;
  end if;
  raise notice 'PASS: WATCH_LOG — the watcher''s log is her own card''s log key for key before the first round, after % round(s) through her door, and closed (%); it carries only (v, atk, first, foe, you, r, board, after, end); her card has the word, her stance, the loot (%) and the hands, the watcher''s read has none of them and no key naming a ducat, cargo, a purse, funds or loot; a neighbour reads nothing through world.battle and cannot set a stance (E_NOT_YOUR_BATTLE)',
    v_i, v_w -> 'log' ->> 'end', v_own ->> 'loot';

  if v_c is null or v_c ->> 'end' is distinct from v_w -> 'log' ->> 'end' or v_c ->> 'status' not in ('RESOLVED', 'BROKEN_OFF') or v_c -> 'next_at' is distinct from 'null'::jsonb
     or exists (select 1 from jsonb_array_elements(v_c -> 'sides') s where s ? 'at') or (v_c ->> 'fleets')::int is distinct from 2 then
    raise exception 'PROOF 66 FAIL: the card of a battle just over: %', v_c;
  end if;
  update public.battles b set started_at = now() - interval '10 minutes', resolves_at = now() - interval '59 seconds' where b.id = v_bat;
  if not exists (select 1 from jsonb_array_elements(world.fights() -> 'fights') e where e ->> 'id' = v_bat::text) then
    raise exception 'PROOF 66 FAIL: a battle over for 59 s is not on the map';
  end if;
  update public.battles b set resolves_at = now() - interval '61 seconds' where b.id = v_bat;
  v_r := world.fights();
  if exists (select 1 from jsonb_array_elements(v_r -> 'fights') e where e ->> 'id' = v_bat::text) or (v_r ->> 'on')::boolean is not true
     or world.fight(v_bat) -> 'log' ->> 'end' is distinct from v_c ->> 'end' then
    raise exception 'PROOF 66 FAIL: a battle over for 61 s is still on the map, or its log can no longer be read: %', v_r;
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'attack_enabled';
  if (world.fights() ->> 'on')::boolean is not false then
    raise exception 'PROOF 66 FAIL: dark again and with nothing to serve, the read still says on';
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'attack_enabled';
  raise notice 'PASS: FIGHTS_KEPT — closed by the real job (%): the card carries the ending and no fleet''s place, is on the map 59 s after its end and gone at 61 s (keep_seconds 60); its log can still be read; with the switch off again and nothing to serve the read says on: false',
    v_c ->> 'end';

  -- ══ FIGHTS_COST: the read with 0, 1 and 20 battles being fought (a measurement, printed) ══
  v_tq := clock_timestamp();
  for v_k in 1 .. 20 loop v_r := world.fights(); end loop;
  v_ms := v_ms || round(extract(epoch from clock_timestamp() - v_tq) * 1000 / 20, 2);
  if jsonb_array_length(v_r -> 'fights') is distinct from 0 then
    raise exception 'PROOF 66 FAIL: a battle is served before the cost scene opens one: %', v_r;
  end if;
  for v_k in 1 .. 20 loop
    x := pg_temp.house_66(100 + v_k);
    d := pg_temp.ship_66(100000, now());
    perform pg_temp.lie_by_66(x, d, now(), 0.1);
    perform public.battle_open('ATTACK', x, d, now());
    if v_k = 1 then
      v_tq := clock_timestamp();
      for v_i in 1 .. 20 loop v_r := world.fights(); end loop;
      v_ms := v_ms || round(extract(epoch from clock_timestamp() - v_tq) * 1000 / 20, 2);
      if jsonb_array_length(v_r -> 'fights') is distinct from 1 then
        raise exception 'PROOF 66 FAIL: one battle open, % served', jsonb_array_length(v_r -> 'fights');
      end if;
    end if;
  end loop;
  v_tq := clock_timestamp();
  for v_i in 1 .. 20 loop v_r := world.fights(); end loop;
  v_ms := v_ms || round(extract(epoch from clock_timestamp() - v_tq) * 1000 / 20, 2);
  if jsonb_array_length(v_r -> 'fights') is distinct from 20
     or exists (select 1 from jsonb_array_elements(v_r -> 'fights') with ordinality e(f, o)
                 join jsonb_array_elements(v_r -> 'fights') with ordinality g(f, o) on g.o = e.o + 1
                where (e.f ->> 'started_at')::timestamptz > (g.f ->> 'started_at')::timestamptz)
     or exists (select 1 from jsonb_array_elements(v_r -> 'fights') e where (e ->> 'fleets')::int is distinct from 2 or e -> 'mine' is distinct from 'null'::jsonb) then
    raise exception 'PROOF 66 FAIL: twenty battles: % served, or not oldest first', jsonb_array_length(v_r -> 'fights');
  end if;
  raise notice 'PASS: FIGHTS_COST — world.fights(), the mean of 20 calls on this machine: % ms with no battle, % ms with 1, % ms with 20 (each with 2 fleets, one of them a held voyage); 20 are served, oldest first',
    v_ms[1], v_ms[2], v_ms[3];
end
$p$;
