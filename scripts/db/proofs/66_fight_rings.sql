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
-- @pass RAID_RING       a real raid day of a voyage still at sea (voyage.settle, which 0364 does not cut): her own read serves it at once with the day's own log and cost, at her place at that day's end, sized by the raiders' ships; nobody else reads it; the read writes nothing; 300 s from the day's instant, through her arrival, then gone
-- @pass NAVY_KEPT       one navy fight under the body before 0364 and after it: answer, hulls, fleets, stamps, event, voyages, purses and ledger the same text; a failing keeper leaves the fight as it was; the real pass keeps the fight and every player reads it with its place, its ships and its log cut to nine keys; gone at 301 s
-- @pass FIGHTS_LIVE_COST the read with 75 navy rows, 5 of them recent, for a company at sea with a raid and for one in port, and the keeper's cost a navy fight, timed (printed, never judged)
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
  update public.world_config set value = 'false'::jsonb where key = 'combat_bite';
  if world.fights() - 'now' is distinct from '{"on": false, "keep_seconds": 60, "raid_seconds": 300, "fights": []}'::jsonb or world.fight(gen_random_uuid()) is distinct from '{"on": false}'::jsonb then
    raise exception 'PROOF 66 FAIL: dark, the reads: % and %', world.fights(), world.fight(gen_random_uuid());
  end if;
  if has_function_privilege('anon', 'world.fights()', 'execute') or has_function_privilege('anon', 'world.fight(uuid)', 'execute')
     or not has_function_privilege('authenticated', 'world.fights()', 'execute') or not has_function_privilege('authenticated', 'world.fight(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.fight_card(uuid,uuid)', 'execute') or has_function_privilege('anon', 'public.fight_card(uuid,uuid)', 'execute')
     or (select count(*) from public.client_rpc_entry_points() e where e.fn = any (array['world.fights()'::regprocedure, 'world.fight(uuid)'::regprocedure])) is distinct from 2 then
    raise exception 'PROOF 66 FAIL: the doors'' grants or registry rows';
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'combat_bite';
  if (world.fights() ->> 'on')::boolean is not true then
    raise exception 'PROOF 66 FAIL: with the fight at sea in use the read does not say on';
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
  if exists (select 1 from jsonb_object_keys(v_c) k where k <> all (array['id', 'kind', 'size', 'status', 'lat', 'lon', 'started_at', 'resolves_at', 'round_seconds', 'rounds', 'rounds_done', 'next_at', 'fleets', 'ships', 'mine', 'sides', 'end']))
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
  -- WHEN it ended is the dice's (a fight may end in its first round, which was 70 s ago by this battle's clock, or at the boarding, which is 290 s ahead): the map keeps it
  -- keep_seconds from its end, so its end is put 5 s ago (its own row) before the card is read. Under any dice it is then "just over".
  update public.battles b set started_at = now() - interval '10 minutes', resolves_at = now() - interval '5 seconds' where b.id = v_bat;
  update public.battle_sides bs set joined_at = now() - interval '10 minutes', arrives_at = now() - interval '10 minutes' where bs.battle_id = v_bat;   -- both were there from its start
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
  update public.battles b set resolves_at = now() - interval '59 seconds' where b.id = v_bat;
  if not exists (select 1 from jsonb_array_elements(world.fights() -> 'fights') e where e ->> 'id' = v_bat::text) then
    raise exception 'PROOF 66 FAIL: a battle over for 59 s is not on the map';
  end if;
  update public.battles b set resolves_at = now() - interval '61 seconds' where b.id = v_bat;
  v_r := world.fights();
  if exists (select 1 from jsonb_array_elements(v_r -> 'fights') e where e ->> 'id' = v_bat::text) or (v_r ->> 'on')::boolean is not true
     or world.fight(v_bat) -> 'log' ->> 'end' is distinct from v_c ->> 'end' then
    raise exception 'PROOF 66 FAIL: a battle over for 61 s is still on the map, or its log can no longer be read: %', v_r;
  end if;
  update public.world_config set value = 'false'::jsonb where key in ('attack_enabled', 'combat_bite');
  if (world.fights() ->> 'on')::boolean is not false then
    raise exception 'PROOF 66 FAIL: dark again and with nothing to serve, the read still says on';
  end if;
  update public.world_config set value = 'true'::jsonb where key in ('attack_enabled', 'combat_bite');
  raise notice 'PASS: FIGHTS_KEPT — closed by the real job (%): the card carries the ending and no fleet''s place, is on the map 59 s after its end and gone at 61 s (keep_seconds 60); its log can still be read; with every switch of a fight off and nothing to serve the read says on: false',
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

-- ══ HER OWN RAID, AND THE NAVY'S FIGHT ══

-- THE SEA ON ONE SETTING (proofs 37, 38, 46, 56 and 60 stub it so): 'PIRATES' a raid every day, '' quiet
alter function voyage.hazard_roll(uuid, integer) rename to hazard_roll_real_66;
create function voyage.hazard_roll(p_voyage uuid, p_day integer)
returns table (occurred boolean, kind text, magnitude numeric, p_hazard numeric)
language plpgsql stable
as $b$
declare
  v_s text := coalesce(current_setting('byeharu.proof_sea', true), '');
begin
  return query select v_s <> '', case when v_s <> '' then v_s end, 0.5::numeric, 1::numeric;
end
$b$;

-- a navy ship of p_nation in service, lying at p_port, on duty, whole, with her hands (proof 48's)
create function pg_temp.navy_66(p_nation uuid, p_port uuid, p_at timestamptz)
returns uuid language plpgsql as $b$
declare
  v_cap uuid := public.realm_capital(p_nation);
  v_ord int := coalesce((select max(n.ord) from public.navy_ships n where n.nation_id = p_nation), 0) + 1;
  v_f   uuid;
begin
  insert into public.navy_realms (nation_id, ships, read_at) values (p_nation, v_ord + 24, p_at) on conflict (nation_id) do update set ships = v_ord + 24, read_at = p_at;
  v_f := public.navy_commission(p_nation, v_ord, v_cap, public.refit_yard(v_cap), p_port, p_at);
  update public.ships s set crew = c.crew_required from public.ship_classes c where c.id = s.class_id and s.fleet_id = v_f;
  return v_f;
end
$b$;

-- a pirate ship of the Brethren cruising sea p_sea, lying at p_port (proof 48's)
create function pg_temp.pirate_66(p_port uuid, p_sea uuid, p_at timestamptz)
returns uuid language plpgsql as $b$
declare
  v_pir  uuid := (select n.id from public.nations n where n.code = 'PIR');
  v_home uuid := (select p.id from public.ports p where p.code = 'POR');
  v_ord  int := coalesce((select max(x.ord) from public.pirate_ships x), 0) + 1;
  v_pl   uuid;
  v_f    uuid;
begin
  insert into public.players (company_name, nation_id, ducats, is_npc) values (format('Brethren %s', v_ord), v_pir, 0, true) returning id into v_pl;
  v_f := public.form_fleet(v_pl, format('Pirate ship %s', v_ord), p_port);
  perform public.commission_ship(v_pl, v_f, public.wc_text('pirate_ship_class'), format('Pirate ship %s', v_ord), true, false);
  update public.ships s set crew = c.crew_required from public.ship_classes c where c.id = s.class_id and s.fleet_id = v_f;
  insert into public.pirate_ships (fleet_id, player_id, ord, home_port, sea_id, mission, haunt_port, last_port, created_at)
  values (v_f, v_pl, v_ord, v_home, p_sea, 'CRUISE', p_port, p_port, p_at);
  return v_f;
end
$b$;

-- ONE NAVY FIGHT, in a subtransaction that is rolled back, under the body as it is or as it was before 0364 (the hunk reversed): everything it left, as jsonb
create function pg_temp.navy_fight_66(p_navy uuid, p_pirate uuid, p_at timestamptz, p_old boolean)
returns jsonb language plpgsql as $b$
declare
  c_new constant text := $h$  update public.pirate_ships x set fought_at = p_now where x.fleet_id = p_pirate;
  perform public.navy_fight_keep(p_navy, p_pirate, v_a, v_b, v_f, p_now);   -- 0364: the fight's log and its place, kept for the map (it never raises and moves nothing of the fight)
$h$;
  c_old constant text := $h$  update public.pirate_ships x set fought_at = p_now where x.fleet_id = p_pirate;
$h$;
  v_def text := replace(pg_get_functiondef('public.navy_fight(uuid,uuid,timestamp with time zone)'::regprocedure), E'\r', '');
  v_ev  uuid[] := array(select e.id from public.events e where e.kind = 'NAVY_FIGHT');
  v_r   jsonb;
  v_out jsonb;
begin
  begin
    if p_old then
      if (length(v_def) - length(replace(v_def, c_new, ''))) / length(c_new) is distinct from 1 then
        raise exception 'PROOF 66 FAIL: the hunk of 0364 is not in public.navy_fight exactly once';
      end if;
      execute replace(v_def, c_new, c_old);
    end if;
    perform voyage.settle(p_navy, p_at);
    perform voyage.settle(p_pirate, p_at);
    v_r := public.navy_fight(p_navy, p_pirate, p_at);
    v_out := jsonb_build_object(
      'answer', v_r - 'event',
      'ships', (select jsonb_agg(to_jsonb(s) order by s.id) from public.ships s where s.fleet_id in (p_navy, p_pirate)),
      'fleets', (select jsonb_agg(to_jsonb(f) order by f.id) from public.fleets f where f.id in (p_navy, p_pirate)),
      'navy', (select to_jsonb(n) from public.navy_ships n where n.fleet_id = p_navy),
      'pirate', (select to_jsonb(x) from public.pirate_ships x where x.fleet_id = p_pirate),
      'events', (select jsonb_agg(jsonb_build_object('kind', e.kind, 'player', e.player_id, 'payload', e.payload) order by e.payload::text) from public.events e where e.kind = 'NAVY_FIGHT' and e.id <> all (v_ev)),
      'voyages', (select jsonb_agg(to_jsonb(v) order by v.id) from public.voyages v where v.fleet_id in (p_navy, p_pirate)),
      'purses', (select sum(p.ducats) from public.players p)::text || ':' || (select sum(t.ducats) from public.port_treasury t)::text,
      'ledger', (select count(*) from public.ledger));
    if to_regclass('public.navy_fight_log') is not null then   -- (one scene takes the table away, to see the keeper fail)
      execute 'select to_jsonb(l) from public.navy_fight_log l where l.fleet_id = $1' into v_r using p_navy;
      v_out := v_out || jsonb_build_object('kept', v_r);
    else
      v_out := v_out || jsonb_build_object('kept', null);
    end if;
    raise exception using errcode = 'ZX366', message = 'SCENE_ROLLBACK_66';
  exception when sqlstate 'ZX366' then
    null;
  end;
  return v_out;
end
$b$;

do $p$
declare
  c_uid   constant uuid := '00000000-0364-4000-8000-000000000001';
  c_uid2  constant uuid := '00000000-0364-4000-8000-000000000002';
  c_keys  constant text[] := array['v', 'atk', 'first', 'foe', 'you', 'r', 'board', 'after', 'end'];
  a       uuid := (select f.id from public.fleets f join public.players p on p.id = f.player_id where p.auth_uid = c_uid);
  v_pl    uuid := (select p.id from public.players p where p.auth_uid = c_uid);
  v_lis   uuid := (select p.id from public.ports p where p.code = 'LIS');
  v_sea   uuid := (select p.sea_id from public.ports p where p.code = 'LIS');
  v_nat   uuid := (select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT');
  v_cap   uuid;
  v_voy   uuid;
  v_t     timestamptz;
  v_r     jsonb;
  v_c     jsonb;
  v_day   public.voyage_events%rowtype;
  v_pos   record;
  v_txt   text;
  v_new   jsonb;
  v_old   jsonb;
  n       uuid;
  p       uuid;
  v_k     int;
  v_i     int;
  v_tq    timestamptz;
  v_ms    numeric[] := '{}';
  v_raid_ms numeric;
  v_keep_ms numeric;
begin
  update public.world_config set value = 'false'::jsonb where key = 'attack_enabled';

  -- ══ RAID_RING: a real raid day. Her fleet back in Lisbon, whole, sails a three-day passage west that began ten ninths of a voyage-day ago (100 s at 960); day 1 is a raid; her own read settles it ══
  update public.fleets f set status = 'DOCKED', port_id = v_lis, lat = null, lon = null, busy_until = null, ready_at = null, version = f.version + 1 where f.id = a;
  update public.ships s set durability = (select b.durability from public.ship_base(s.id) b), crew = 100, water_t = 100000, food_t = 100000 where s.fleet_id = a;
  v_t := now() - make_interval(secs => (100.0 / 90 * 86400 / public.wc_num('time_compression'))::double precision);   -- 0412: ten ninths of a voyage-day ago at the clock's rate as it stands (100 s at 960)
  v_voy := voyage.depart(a, (select jsonb_agg(jsonb_build_object('a', jsonb_build_array(38.5, -9.6 - (d - 1)), 'b', jsonb_build_array(38.5, -9.6 - d), 'nm', voyage.fleet_speed(a) * 24, 'sea_id', v_sea, 'hazard_mult', 1000) order by d)
                           from generate_series(1, 3) d), v_lis, v_lis, v_t);
  perform cmd.assume_identity(c_uid);
  if exists (select 1 from jsonb_array_elements(world.fights() -> 'fights') e where e ->> 'kind' = 'RAID') then
    raise exception 'PROOF 66 FAIL: a raid is on her map before any day settled';
  end if;
  perform set_config('byeharu.proof_sea', 'PIRATES', true);
  v_tq := clock_timestamp();
  perform voyage.settle(a, now());
  v_raid_ms := round(extract(epoch from clock_timestamp() - v_tq) * 1000, 1);
  perform set_config('byeharu.proof_sea', '', true);
  select * into v_day from public.voyage_events ve where ve.voyage_id = v_voy and ve.day_index = 1;
  if v_day.kind is distinct from 'PIRATES' or not (v_day.payload -> 'fight' ? 'log') or (select count(*) from public.voyage_events ve where ve.voyage_id = v_voy) is distinct from 1
     or (select v.status from public.voyages v where v.id = v_voy) is distinct from 'SAILING' then
    raise exception 'PROOF 66 FAIL: day 1 is not a raid that kept its log while she is still at sea: %', to_jsonb(v_day);
  end if;
  -- the reads write nothing: her ships, her voyage, its days and her purse are the same text before and after
  select md5((select string_agg(to_jsonb(s)::text, ',' order by s.id) from public.ships s where s.fleet_id = a) || (select to_jsonb(v)::text from public.voyages v where v.id = v_voy)
             || (select string_agg(to_jsonb(ve)::text, ',' order by ve.day_index) from public.voyage_events ve where ve.voyage_id = v_voy) || (select to_jsonb(pl)::text from public.players pl where pl.id = v_pl)) into v_txt;
  v_r := world.fights();
  select e into v_c from jsonb_array_elements(v_r -> 'fights') e where e ->> 'kind' = 'RAID';
  select ps.lat, ps.lon into v_pos from voyage.position(v_voy, v_day.resolved_at) ps;
  if md5((select string_agg(to_jsonb(s)::text, ',' order by s.id) from public.ships s where s.fleet_id = a) || (select to_jsonb(v)::text from public.voyages v where v.id = v_voy)
         || (select string_agg(to_jsonb(ve)::text, ',' order by ve.day_index) from public.voyage_events ve where ve.voyage_id = v_voy) || (select to_jsonb(pl)::text from public.players pl where pl.id = v_pl)) is distinct from v_txt then
    raise exception 'PROOF 66 FAIL: world.fights() wrote something of hers';
  end if;
  if v_c is null or (select count(*) from jsonb_array_elements(v_r -> 'fights') e where e ->> 'kind' = 'RAID') is distinct from 1
     or v_c ->> 'id' is distinct from 'raid:' || v_voy || ':1' or v_c ->> 'status' is distinct from 'RESOLVED' or v_c ->> 'mine' is distinct from a::text
     or v_c -> 'log' is distinct from v_day.payload -> 'fight' -> 'log' or v_c ->> 'end' is distinct from v_day.payload -> 'fight' -> 'log' ->> 'end'
     or (v_c ->> 'lat')::numeric is distinct from v_pos.lat or (v_c ->> 'lon')::numeric is distinct from v_pos.lon
     -- one day west of Lisbon's roads: she is a degree along her course, not at either end of the voyage
     or (v_c ->> 'lat')::numeric is distinct from 38.5 or abs((v_c ->> 'lon')::numeric - (-10.6)) > 0.01
     or (v_c ->> 'started_at')::timestamptz is distinct from v_day.resolved_at or (v_c ->> 'until')::timestamptz is distinct from v_day.resolved_at + interval '300 seconds'
     or (v_c ->> 'size')::int is distinct from 1 + greatest(1, ceil((v_day.payload -> 'fight' -> 'log' -> 'foe' ->> 'k')::numeric))::int
     or (v_c -> 'sides' -> 0 ->> 'ships')::int is distinct from greatest(1, ceil((v_day.payload -> 'fight' -> 'log' -> 'foe' ->> 'k')::numeric))::int
     or v_c -> 'sides' -> 0 ->> 'kind' is distinct from 'PIRATE' or v_c -> 'sides' -> 0 ->> 'side' is distinct from 'ATTACKER'
     or v_c -> 'sides' -> 1 is distinct from jsonb_build_object('fleet', a, 'name', 'Ronda 1', 'side', 'DEFENDER', 'how', 'OPENED', 'kind', 'COMPANY', 'company', 'Casa Ronda 1', 'nation', 'PRT',
                                               'ships', (select count(*)::int from public.ships s where s.fleet_id = a), 'here', true)
     or v_c -> 'loss' is distinct from jsonb_build_object('crew_before', v_day.payload -> 'crew_before', 'crew', v_day.payload -> 'crew_lost', 'cargo', coalesce(v_day.payload -> 'cargo_lost', '{}'::jsonb),
                                         'ransom', coalesce(v_day.payload -> 'ransom_paid', v_day.payload -> 'pirate' -> 'ransom', '0'::jsonb))
     or (v_r ->> 'raid_seconds')::int is distinct from 300 or (v_r ->> 'on')::boolean is not true then
    raise exception 'PROOF 66 FAIL: her own raid on her map: % (the day: %, her place %)', v_c, to_jsonb(v_day), to_jsonb(v_pos);
  end if;
  -- nobody else reads it; a bigger raid is a bigger ring (the same day with five raiders' ships in its log: a row of this proof)
  perform cmd.assume_identity(c_uid2);
  if exists (select 1 from jsonb_array_elements(world.fights() -> 'fights') e where e ->> 'kind' = 'RAID') then
    raise exception 'PROOF 66 FAIL: a neighbour read her raid';
  end if;
  perform cmd.assume_identity(c_uid);
  update public.voyage_events ve set payload = jsonb_set(ve.payload, '{fight,log,foe,k}', '4.4'::jsonb) where ve.voyage_id = v_voy and ve.day_index = 1;
  select e into v_r from jsonb_array_elements(world.fights() -> 'fights') e where e ->> 'kind' = 'RAID';
  if (v_r ->> 'size')::int is distinct from 6 or (v_r ->> 'size')::int <= (v_c ->> 'size')::int and (v_c ->> 'size')::int < 6 then
    raise exception 'PROOF 66 FAIL: five raiders'' ships are not a size of six: %', v_r;
  end if;
  -- it stays raid_seconds from the day's own instant, and it is still there once she has arrived
  update public.voyage_events ve set resolved_at = now() - interval '299 seconds' where ve.voyage_id = v_voy and ve.day_index = 1;
  update public.voyages v set status = 'ARRIVED', eta = now() - interval '30 seconds' where v.id = v_voy;
  update public.fleets f set status = 'DOCKED', port_id = v_lis, version = f.version + 1 where f.id = a;
  if not exists (select 1 from jsonb_array_elements(world.fights() -> 'fights') e where e ->> 'kind' = 'RAID') then
    raise exception 'PROOF 66 FAIL: a raid 299 s old, of a voyage that has since arrived, is not on her map';
  end if;
  update public.voyage_events ve set resolved_at = now() - interval '301 seconds' where ve.voyage_id = v_voy and ve.day_index = 1;
  if exists (select 1 from jsonb_array_elements(world.fights() -> 'fights') e where e ->> 'kind' = 'RAID') then
    raise exception 'PROOF 66 FAIL: a raid 301 s old is still on her map';
  end if;
  if pg_get_functiondef('voyage.settle(uuid,timestamp with time zone)'::regprocedure) like '%0364%' then
    raise exception 'PROOF 66 FAIL: voyage.settle carries a line of 0364: it must not be cut';
  end if;
  raise notice 'PASS: RAID_RING — a real raid day (voyage.settle, uncut by 0364: no line of it names 0364) on a voyage still at sea: her own read serves it at once with the day''s own log and cost, at her place at that day''s end (38.5, % : one day west of Lisbon), sized 1 + the raiders'' ships (% here, 6 for five); her neighbour reads nothing; the read writes nothing of hers; it stays 300 s from the day''s instant, through her arrival, and is gone at 301 s. The settle of that raid day took % ms here',
    v_c ->> 'lon', v_c ->> 'size', v_raid_ms;

  -- ══ NAVY_KEPT: one navy ship and one pirate ship in Lisbon's sea. OLD AGAINST NEW, then the real pass ══
  update public.world_config set value = 'true'::jsonb where key in ('navy_enabled', 'pirates_bite');
  update public.ports set crew_pool = 2000;
  v_cap := public.realm_capital(v_nat);
  v_t := date_trunc('second', now()) - interval '20 seconds';
  n := pg_temp.navy_66(v_nat, v_cap, v_t);
  p := pg_temp.pirate_66(v_cap, (select x.sea_id from public.ports x where x.id = v_cap), v_t);
  -- where she lies BEFORE any fight: a fight that sinks her sends her home (voyage.npc_wreck), so the place is read now and never after
  select pt.lat, pt.lon into v_pos from voyage.fleet_point(n, v_t) pt;
  v_new := pg_temp.navy_fight_66(n, p, v_t, false);
  v_old := pg_temp.navy_fight_66(n, p, v_t, true);
  if v_new is null or v_old is null or (v_new - 'kept')::text is distinct from (v_old - 'kept')::text or v_old -> 'kept' is distinct from 'null'::jsonb or jsonb_typeof(v_new -> 'kept') is distinct from 'object'
     or jsonb_array_length(v_new -> 'events') is distinct from 1 or (v_new -> 'navy' ->> 'fought_at')::timestamptz is distinct from v_t then
    raise exception 'PROOF 66 FAIL: NAVY, OLD AGAINST NEW: % against %', v_old - 'kept', v_new - 'kept';
  end if;
  -- the keeper cannot hurt the fight: with its table gone (a subtransaction), the fight is the old fight and a warning
  begin
    alter table public.navy_fight_log rename to navy_fight_log_gone_66;
    v_r := pg_temp.navy_fight_66(n, p, v_t, false);
    if (v_r - 'kept')::text is distinct from (v_old - 'kept')::text then
      raise exception 'PROOF 66 FAIL: with the keeper failing the fight is not the old fight';
    end if;
    raise exception using errcode = 'ZX367', message = 'SCENE_ROLLBACK_66';
  exception when sqlstate 'ZX367' then
    null;
  end;
  -- THE REAL PASS (the minute job's own function): it fights, and the fight is kept
  v_k := public.navy_hunt_pass(v_t, v_nat);
  perform cmd.assume_identity(c_uid2);
  v_r := world.fights();
  select e into v_c from jsonb_array_elements(v_r -> 'fights') e where e ->> 'kind' = 'NAVY';
  if v_k is distinct from 1 or v_c is null or (select count(*) from jsonb_array_elements(v_r -> 'fights') e where e ->> 'kind' = 'NAVY') is distinct from 1
     or (select count(*) from public.navy_fight_log) is distinct from 1
     or v_c ->> 'status' is distinct from 'RESOLVED' or v_c -> 'mine' is distinct from 'null'::jsonb or v_c ? 'loss'
     or (v_c ->> 'started_at')::timestamptz is distinct from v_t or (v_c ->> 'until')::timestamptz is distinct from v_t + interval '300 seconds'
     or (v_c ->> 'lat')::numeric is distinct from v_pos.lat or (v_c ->> 'lon')::numeric is distinct from v_pos.lon or v_pos.lat is null
     or (v_c ->> 'size')::int is distinct from (select count(*)::int from public.ships s where s.fleet_id in (n, p)) or (v_c ->> 'ships')::int is distinct from (v_c ->> 'size')::int
     or v_c -> 'sides' -> 0 is distinct from jsonb_build_object('fleet', n, 'name', (select f.name from public.fleets f where f.id = n), 'side', 'ATTACKER', 'how', 'OPENED', 'kind', 'NAVY', 'company', null,
                                               'nation', 'PRT', 'ships', (select count(*)::int from public.ships s where s.fleet_id = n), 'here', true)
     or v_c -> 'sides' -> 1 is distinct from jsonb_build_object('fleet', p, 'name', (select f.name from public.fleets f where f.id = p), 'side', 'DEFENDER', 'how', 'OPENED', 'kind', 'PIRATE', 'company', null,
                                               'nation', null, 'ships', (select count(*)::int from public.ships s where s.fleet_id = p), 'here', true)
     or (v_c -> 'log' ->> 'v')::int is distinct from 1 or (v_c -> 'log' ->> 'atk')::boolean is not true
     or coalesce(v_c ->> 'end', '') not in ('A_NONE', 'A_LOST', 'FLED', 'A_BROKE', 'A_THROWN', 'A_TERMS', 'A_TOOK') or v_c -> 'log' ->> 'end' is distinct from v_c ->> 'end'
     or exists (select 1 from jsonb_object_keys(v_c -> 'log') k where k <> all (c_keys))
     -- the log is the fight that was fought: the same log the old-against-new scene kept, and its hull after is the hull she has
     or v_c -> 'log' is distinct from v_new -> 'kept' -> 'card' -> 'log'
     -- (what she lost by the log is what the fight's own answer took from her hulls: held on the answer, not on her ships, which a sinking sends home)
     or abs((select sum((e ->> 1)::numeric) from jsonb_array_elements(v_c -> 'log' -> 'you') e) - (select sum((e ->> 1)::numeric) from jsonb_array_elements(v_c -> 'log' -> 'after') e)
            - (select coalesce(sum(h.value::numeric), 0) from jsonb_each_text(coalesce(v_new -> 'answer' -> 'hull_lost' -> 'navy', '{}'::jsonb)) h)) > 0.1
     or v_c::text ~* '"[a-z_]*(ducat|cargo|purse|funds|loot)[a-z_]*":' then
    raise exception 'PROOF 66 FAIL: the navy''s fight on a neighbour''s map: % (pass %)', v_c, v_k;
  end if;
  update public.navy_fight_log set at = now() - interval '301 seconds';
  if exists (select 1 from jsonb_array_elements(world.fights() -> 'fights') e where e ->> 'kind' = 'NAVY') then
    raise exception 'PROOF 66 FAIL: a navy fight 301 s old is still on the map';
  end if;
  raise notice 'PASS: NAVY_KEPT — one navy fight under the body before 0364 and after it: the answer, both ships'' hulls, both fleets, the navy ship''s row and stamp, the pirate ship''s, the NAVY_FIGHT event, both voyages, every purse and the ledger are the same text; only the kept row differs. With the keeper''s table gone the fight is still that fight. The real pass (public.navy_hunt_pass) fights once and keeps it: every player reads it at the navy ship''s place, sized by the % ships, both ships named, the log (% round(s), %) cut to nine keys, and what she lost by it is what the answer took from her hulls; gone at 301 s',
    v_c ->> 'size', jsonb_array_length(v_c -> 'log' -> 'r'), v_c ->> 'end';

  -- ══ FIGHTS_LIVE_COST: the read as prod would ask it (a measurement, printed): 75 navy ships' rows of which 5 fought in the last 300 s, and her fleet at sea with one raid day in it ══
  -- (the twenty battles of FIGHTS_COST are put an hour in the past, rows of this proof: prod has none, attacks being dark)
  update public.battles b set status = 'RESOLVED', result = coalesce(b.result, '{"outcome": "NO_FIGHT"}'::jsonb), started_at = now() - interval '2 hours', resolves_at = now() - interval '1 hour' where b.status = 'FIGHTING';
  update public.navy_fight_log set at = now() - interval '10 seconds';
  insert into public.navy_fight_log (fleet_id, at, lat, lon, card)
  select f.id, now() - make_interval(secs => case when f.k <= 4 then 30 * f.k else 3600 end), 30 + f.k, -20, (select l.card from public.navy_fight_log l limit 1)
    from (select x.id, row_number() over (order by x.id) as k from public.fleets x where not exists (select 1 from public.navy_fight_log l where l.fleet_id = x.id) limit 74) f;
  update public.voyages v set status = 'SAILING', eta = now() + interval '3 minutes' where v.id = v_voy;
  update public.voyage_events ve set resolved_at = now() - interval '20 seconds' where ve.voyage_id = v_voy and ve.day_index = 1;
  perform cmd.assume_identity(c_uid);
  v_tq := clock_timestamp();
  for v_i in 1 .. 50 loop v_r := world.fights(); end loop;
  v_ms := v_ms || round(extract(epoch from clock_timestamp() - v_tq) * 1000 / 50, 2);
  if (select count(*) from jsonb_array_elements(v_r -> 'fights') e where e ->> 'kind' = 'NAVY') is distinct from 5 or (select count(*) from jsonb_array_elements(v_r -> 'fights') e where e ->> 'kind' = 'RAID') is distinct from 1
     or (select count(*) from public.navy_fight_log) is distinct from 75 then
    raise exception 'PROOF 66 FAIL: the cost scene: % navy, % raid, % rows', (select count(*) from jsonb_array_elements(v_r -> 'fights') e where e ->> 'kind' = 'NAVY'),
      (select count(*) from jsonb_array_elements(v_r -> 'fights') e where e ->> 'kind' = 'RAID'), (select count(*) from public.navy_fight_log);
  end if;
  perform cmd.assume_identity(c_uid2);
  v_tq := clock_timestamp();
  for v_i in 1 .. 50 loop v_r := world.fights(); end loop;
  v_ms := v_ms || round(extract(epoch from clock_timestamp() - v_tq) * 1000 / 50, 2);
  update public.navy_fight_log set at = now() - interval '1 hour';
  v_tq := clock_timestamp();
  for v_i in 1 .. 50 loop v_r := world.fights(); end loop;
  v_ms := v_ms || round(extract(epoch from clock_timestamp() - v_tq) * 1000 / 50, 2);
  -- the keeper's own cost, a fight
  v_tq := clock_timestamp();
  for v_i in 1 .. 20 loop
    perform public.navy_fight_keep(n, p, voyage.fleet_hulls(p), voyage.fleet_hulls(n), public.fight_sides(n, v_i, voyage.fleet_hulls(p), voyage.fleet_hulls(n), '{}'::jsonb), now());
  end loop;
  v_keep_ms := round(extract(epoch from clock_timestamp() - v_tq) * 1000 / 20, 2);
  v_tq := clock_timestamp();
  for v_i in 1 .. 20 loop
    perform voyage.fleet_hulls(p), voyage.fleet_hulls(n), public.fight_sides(n, v_i, voyage.fleet_hulls(p), voyage.fleet_hulls(n), '{}'::jsonb);
  end loop;
  v_keep_ms := v_keep_ms - round(extract(epoch from clock_timestamp() - v_tq) * 1000 / 20, 2);
  raise notice 'PASS: FIGHTS_LIVE_COST — world.fights() with 75 navy ships'' rows, the mean of 50 calls on this machine: % ms for a company at sea with one raid and 5 navy fights to serve, % ms for a company in port with the 5 navy fights, % ms with nothing to serve; the keeper adds about % ms to a navy fight',
    v_ms[1], v_ms[2], v_ms[3], v_keep_ms;
end
$p$;
