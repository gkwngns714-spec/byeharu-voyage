-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 133 - A RAIDED SHIP MAY RUN  (migration 0432; docs/dev-log/2026-11-15-pirate-flee.md; the owner, 2026-11-15: "pirates' main goal is to
--   attack other npcs, loot them. while attacking each ships cannot move until the battle is over ... running away is an option ... it will need
--   skills for higher probability. after it ran, the attacked ship will have 5 mins of peace time")
--
--   Lit as prod is, through the pirates' minute job (public.tick_pirates) and the battles' (public.tick_battles), rolled back with proof.mjs's
--   transaction. A hunting pirate at her haunt; a company's merchant 60 miles off and a PLAYER'S ship beside her. EVERY BUILT WORLD HAS ITS OWN
--   DICE: nothing here assumes whether a run succeeds; what is proved is the chance each round rolled on, and what follows either way.
--
-- @pass FL_FIRST   the pirate raids the world's merchant first, though a player's ship lies nearer
-- @pass FL_HELD    every side is held to the battle's end: both IN_BATTLE with its clock; a held player's ship cannot turn (E_FLEET_BUSY under sail, E_NOT_SAILING at anchor) nor be raided again
-- @pass FL_RUN     outgunned, the world's merchant opens with FLEE; each round she runs on raid_flee_floor..raid_flee_max of base + sighting + her frozen speed and handling bonus; ran away, nothing was taken
-- @pass FL_PLAYER  the player's ship set upon presses Flee on her card (cmd.battle_stance); from the next round she runs on the same rule
-- @pass FL_PEACE   a ship out of a battle she was set upon in is at peace for 5 minutes: no pirate chooses her, her fleet read says peace_until; after it she may be raided again
-- @pass FL_STATS   the Stats count's window counts the raids that ended with the ship gone (raids_fled), and world.stats_fleets serves fled_day
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

update public.world_config set value = case key when 'pirate_strike_from_port' then 'true'::jsonb else to_jsonb(720) end where key in ('pirate_strike_from_port', 'pirate_port_minutes');   -- 0445: this proof's pirate lies at her haunt and raids from it (0427's world, by 0445's two way-back knobs); the cruise and the raid under sail are proof 147's

update public.world_config set value = '[]'::jsonb where key = 'tick_fight_kinds';   -- 0435: this proof drives the round-by-round battle (the rollback's engine); a tick battle is proof 136's

create function pg_temp.lie_133(p_fleet uuid, p_lat numeric, p_lon numeric) returns void language sql as $f$
  update public.voyages v set status = 'ABORTED' where v.fleet_id = p_fleet and v.status = 'SAILING';
  update public.fleets f set status = 'ANCHORED', port_id = null, lat = p_lat, lon = p_lon, busy_until = null, ready_at = null, version = f.version + 1 where f.id = p_fleet;
$f$;

do $p$
declare
  t0      timestamptz := date_trunc('minute', now()) + interval '1 day';
  v_uid   uuid := '00000000-0432-4000-8000-000000000001';
  v_hub   uuid := (select p.id from public.ports p where p.code = 'TDC');
  v_pf    uuid;
  v_m     uuid;
  v_h     uuid;
  v_hp    uuid;
  v_lat   numeric;
  v_lon   numeric;
  v_r     jsonb;
  v_b1    public.battles%rowtype;
  v_b2    public.battles%rowtype;
  v_f     jsonb;
  v_x     jsonb;
  v_lo    numeric := public.wc_num('raid_flee_floor');
  v_hi    numeric := public.wc_num('raid_flee_max');
  v_e     text;
  r       record;
  v_t     timestamptz;
  g       int;
begin
  -- ── THE SCENE ──
  update public.world_config set value = 'true'::jsonb
   where key in ('city_treasury_enabled', 'economy_closed', 'pirates_bite', 'npc_refits_enabled', 'attack_enabled') and value is distinct from 'true'::jsonb;
  update public.world_config set value = 'false'::jsonb where key in ('navy_enabled', 'pirates_trade', 'convoys_enabled') and value is distinct from 'false'::jsonb;
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 5000000, reserve = 0;
  update public.port_treasury t set ducats = 900000000 where t.port_id = public.pirate_capital();
  update public.pirate_ships set laid_up_at = t0 where laid_up_at is null;
  update public.world_config set value = to_jsonb(0) where key = 'pirate_wakes_per_run';   -- the proof's pirate alone is at work
  update public.pirate_clock set added_at = t0 + interval '1 hour', paid_at = t0 + interval '1 hour';
  select q.ord into r from public.pirate_roster q where q.hub_port = v_hub and q.ord % 1000 = 6;   -- a squadron of four: she outguns a merchant
  v_pf := public.pirate_commission_fleet(r.ord, public.refit_yard(v_hub), t0);
  update public.ships s set crew = (select b.crew_max from public.ship_base(s.id) b) where s.fleet_id = v_pf;
  select h.port_id, h.sea_id into r from public.pirate_haunt_of(v_hub, (select x.ord from public.pirate_ships x where x.fleet_id = v_pf)) h;
  update public.fleets f set port_id = r.port_id, status = 'DOCKED', ready_at = null where f.id = v_pf;
  update public.pirate_ships x set sea_id = r.sea_id, mission = 'CRUISE', haunt_port = r.port_id, haunt_since = t0 where x.fleet_id = v_pf;
  select p.lat, p.lon into v_lat, v_lon from voyage.fleet_point(v_pf, t0) p;
  update public.voyages v set status = 'ABORTED' where v.status = 'SAILING';
  update public.fleets f set status = 'DOCKED', port_id = coalesce(f.port_id, v_hub), lat = null, lon = null, busy_until = null where f.status in ('SAILING', 'ANCHORED');
  select nf.fleet_id into v_m
    from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id join public.players pl on pl.id = f.player_id
   where pl.nation_id is distinct from public.pirate_nation() and exists (select 1 from public.ships s where s.fleet_id = nf.fleet_id and s.durability > 0)
   order by nf.fleet_id limit 1;
  perform pg_temp.lie_133(v_m, v_lat + 1, v_lon);   -- sixty miles north
  v_hp := public.new_house(v_uid, 'Casa Huida 133', 'PRT', 'LIS', 'Huida 133', 'galion', 'Huida 133', null, false);
  select f.id into v_h from public.fleets f where f.player_id = v_hp;
  update public.ships s set crew = (select b.crew_max from public.ship_base(s.id) b), cargo = '{}'::jsonb, cargo_basis = '{}'::jsonb where s.fleet_id = v_h;
  perform pg_temp.lie_133(v_h, v_lat, v_lon);   -- beside her

  -- ── FL_FIRST ──
  if public.raid_target(v_pf, t0) is distinct from v_m then
    raise exception 'PROOF 133 FAIL: the pirate chose % before the world''s merchant %', public.raid_target(v_pf, t0), v_m;
  end if;
  v_r := public.tick_pirates(t0);
  select b.* into v_b1 from public.battles b join public.battle_sides s on s.battle_id = b.id and s.fleet_id = v_m and s.side = 'DEFENDER';
  if v_b1.id is null or v_b1.kind <> 'RAID' then
    raise exception 'PROOF 133 FAIL: the job did not raid the world''s merchant: %', v_r;
  end if;
  raise notice 'PASS: FL_FIRST — the merchant 60 miles off before the player''s ship beside her';

  -- ── FL_RUN (at the open) ──
  if public.battle_stance_at(v_b1.id, v_m, 'infinity') <> 'FLEE' or not (v_b1.sheet ? 'a_flee')
     or (v_b1.sheet ->> 'a_flee')::numeric <> public.flee_bonus(v_m, v_pf) then
    raise exception 'PROOF 133 FAIL: the outgunned merchant opened with %, sheet a_flee %', public.battle_stance_at(v_b1.id, v_m, 'infinity'), v_b1.sheet -> 'a_flee';
  end if;

  -- ── FL_HELD ──
  if (select f.status from public.fleets f where f.id = v_pf) <> 'IN_BATTLE' or (select f.status from public.fleets f where f.id = v_m) <> 'IN_BATTLE'
     or (select f.busy_until from public.fleets f where f.id = v_pf) <> v_b1.resolves_at or (select f.busy_until from public.fleets f where f.id = v_m) <> v_b1.resolves_at then
    raise exception 'PROOF 133 FAIL: a side is not held to the battle''s clock';
  end if;
  v_r := public.tick_pirates(t0 + interval '6 minutes');   -- the pirate rests no more, but she is in a battle: she strikes nobody
  if (select count(*) from public.battles) <> 1 then
    raise exception 'PROOF 133 FAIL: a pirate in a battle struck again: %', v_r;
  end if;

  -- the merchant's battle to its end; each round she ran on the raid's rule
  perform public.tick_battles(v_b1.resolves_at);
  select * into v_b1 from public.battles b where b.id = v_b1.id;
  v_f := v_b1.result;
  if v_b1.status = 'FIGHTING' then
    raise exception 'PROOF 133 FAIL: the raid did not close at its clock';
  end if;
  for g in 1 .. coalesce((v_f ->> 'rounds_fought')::int, 0) loop
    v_x := v_f -> 'rounds' -> (g - 1);
    if not (v_x ? 'flee') or (v_x ->> 'flee')::numeric < v_lo or (v_x ->> 'flee')::numeric > v_hi
       or (v_x ->> 'flee')::numeric <> round(least(v_hi, greatest(v_lo, public.wc_num('fight_flee_base')
              + ((select max((e ->> 'sighting')::numeric) from jsonb_array_elements(v_b1.sheet -> 'a') e) - (select max((e ->> 'sighting')::numeric) from jsonb_array_elements(v_b1.sheet -> 'b') e))
                * public.wc_num('fight_evade_per_sighting') + (v_b1.sheet ->> 'a_flee')::numeric)), 4) then
      raise exception 'PROOF 133 FAIL: round % ran on %, not the raid''s rule (floor %, cap %, bonus %)', g, v_x -> 'flee', v_lo, v_hi, v_b1.sheet -> 'a_flee';
    end if;
  end loop;
  if coalesce((v_f ->> 'fled')::boolean, false) and coalesce((v_f #>> '{raid,taken}')::bigint, 0) <> 0 then
    raise exception 'PROOF 133 FAIL: she ran away and something was taken: %', v_f -> 'raid';
  end if;
  raise notice 'PASS: FL_RUN — opened FLEE, bonus %, % round(s) each run on % .. %; % (%)', v_b1.sheet -> 'a_flee', v_f ->> 'rounds_fought', v_lo, v_hi,
    v_f ->> 'outcome', case when coalesce((v_f ->> 'fled')::boolean, false) then 'she got away, nothing taken' else 'she did not get away' end;

  -- ── FL_PEACE (the merchant) and FL_PLAYER ──
  if public.fleet_peace_until(v_m) <> v_b1.resolves_at + interval '5 minutes' then
    raise exception 'PROOF 133 FAIL: her peace runs to %, not five minutes after the battle''s end %', public.fleet_peace_until(v_m), v_b1.resolves_at;
  end if;
  update public.ships s set durability = (select b.durability from public.ship_base(s.id) b), crew = (select b.crew_max from public.ship_base(s.id) b) where s.fleet_id = v_pf;
  update public.fleets f set status = 'DOCKED', busy_until = null where f.id = v_pf;
  v_t := greatest(v_b1.resolves_at, v_b1.started_at + interval '5 minutes') + interval '1 minute';
  if public.raid_target(v_pf, v_t) is distinct from v_h then
    raise exception 'PROOF 133 FAIL: inside the merchant''s peace the pirate chose %', public.raid_target(v_pf, v_t);
  end if;
  v_r := public.tick_pirates(v_t);
  select b.* into v_b2 from public.battles b join public.battle_sides s on s.battle_id = b.id and s.fleet_id = v_h and s.side = 'DEFENDER';
  if v_b2.id is null then
    raise exception 'PROOF 133 FAIL: the player''s ship was not raided: %', v_r;
  end if;
  perform cmd.assume_identity(v_uid);
  -- at anchor in a battle she is IN_BATTLE, not under way: the helm refuses her (E_NOT_SAILING; under sail it is E_FLEET_BUSY, 0323)
  if coalesce(cmd.divert(v_h, (select id from public.ports where code = 'LIS'), null, null) ->> 'error_code', '') not in ('E_FLEET_BUSY', 'E_NOT_SAILING')
     or (select f.status from public.fleets f where f.id = v_h) <> 'IN_BATTLE' then
    raise exception 'PROOF 133 FAIL: a held ship could turn: %', cmd.divert(v_h, (select id from public.ports where code = 'LIS'), null, null);
  end if;
  raise notice 'PASS: FL_HELD — pirate and merchant IN_BATTLE to the clock, the pirate struck nobody else, the held player''s ship cannot turn';
  -- she presses Flee before the first round (the door advances the battle at the wall clock: the press is written at the battle's open instant)
  update public.battles b set started_at = now() - interval '1 second', resolves_at = now() - interval '1 second' + (v_b2.resolves_at - v_b2.started_at),
                              next_round_at = now() - interval '1 second' + make_interval(secs => v_b2.round_seconds)
   where b.id = v_b2.id;
  update public.fleets f set busy_until = (select b.resolves_at from public.battles b where b.id = v_b2.id) where f.id in (v_pf, v_h);
  v_x := cmd.battle_stance(v_b2.id, 'FLEE');
  if not coalesce((v_x ->> 'ok')::boolean, false) or public.battle_stance_at(v_b2.id, v_h, 'infinity') <> 'FLEE' then
    raise exception 'PROOF 133 FAIL: the player could not press Flee: %', v_x;
  end if;
  select * into v_b2 from public.battles b where b.id = v_b2.id;
  perform public.tick_battles(v_b2.resolves_at);
  select * into v_b2 from public.battles b where b.id = v_b2.id;
  v_f := v_b2.result;
  if v_b2.status = 'FIGHTING' or not ((v_f -> 'rounds' -> (coalesce((v_f ->> 'rounds_fought')::int, 1) - 1)) ? 'flee') then
    raise exception 'PROOF 133 FAIL: after her press the rounds did not run: % %', v_b2.status, v_f -> 'rounds';
  end if;
  if not exists (select 1 from jsonb_array_elements(world.fleets()) e where e ->> 'id' = v_h::text and e ? 'peace_until') then
    raise exception 'PROOF 133 FAIL: her fleet read says no peace';
  end if;
  raise notice 'PASS: FL_PLAYER — Flee pressed on the card; her last round ran on %; %', v_f -> 'rounds' -> (coalesce((v_f ->> 'rounds_fought')::int, 1) - 1) -> 'flee', v_f ->> 'outcome';
  -- (a merchant the raid left at anchor with a hull; one it sank is at her home, and no pirate finds her there)
  if (select f.status from public.fleets f where f.id = v_m) = 'ANCHORED' and exists (select 1 from public.ships s where s.fleet_id = v_m and s.durability > 0)
     and public.raid_target(v_pf, v_b1.resolves_at + interval '5 minutes 1 second') is distinct from v_m then
    raise exception 'PROOF 133 FAIL: past her peace the merchant was not chosen again: %', public.raid_target(v_pf, v_b1.resolves_at + interval '5 minutes 1 second');
  end if;
  raise notice 'PASS: FL_PEACE — the merchant at peace to % (the player''s ship chosen instead), her fleet read serves peace_until, after it the merchant again', public.fleet_peace_until(v_m);

  -- ── FL_STATS ──
  v_x := public.stats_fleets_count(now() - interval '1 hour', t0 + interval '2 hours') -> 'win';
  if (v_x ->> 'raids_fled')::int is distinct from (select count(*) from public.battles b where b.kind = 'RAID' and coalesce((b.result ->> 'fled')::boolean, false)) then
    raise exception 'PROOF 133 FAIL: the window counts % fled: %', v_x ->> 'raids_fled', v_x;
  end if;
  delete from public.stats_fleets;
  insert into public.stats_fleets (slot, at, figures) values (public.drift_slot_of(now()), now(), public.stats_fleets_count(now() - interval '1 hour', t0 + interval '2 hours'));
  if not (world.stats_fleets() -> 'battles' ? 'fled_day') then
    raise exception 'PROOF 133 FAIL: world.stats_fleets serves no fled_day';
  end if;
  raise notice 'PASS: FL_STATS — raids_fled %, served fled_day %', v_x ->> 'raids_fled', world.stats_fleets() #> '{battles,fled_day}';
end
$p$;
