-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 156 - A RUN IS A CHASE  (migration 0453; docs/design/evasion-skill.md; docs/dev-log/2026-11-16-evasion.md; the owner, 2026-11-16: "number 5
--   needs a new skill, related to combat - evasion or something ... This skill will increase your chance of running away along with speed level
--   (or agility, you get the idea). Of course the success of evasion depends on both myself and the other ships condition, it has to be relative.")
--
--   Lit as prod is (levels_bite, the levels and their benefits on). A company of the game's own making (public.new_house) is set upon by a pirate of
--   the game's own making (public.form_fleet, public.commission_ship, public.crown_hull_level_fix) through public.battle_open and closed through public.battle_resolve; then the
--   engine itself (public.tick_fight) on fixed sheets, where each term of the chase is read alone against the knobs. Rolled back with proof.mjs's
--   transaction. Nothing here assumes who wins a fight.
--
-- @pass EV_PAGE      world.levels() serves eleven levels, Evasion last, kept by the book at 300 a day, its two activities (40 and 5) and nineteen steps of perk run
-- @pass EV_CARD      a raid's sheet carries each hull's Evasion: a company's ship her company's level and its steps' sum, a merchant's her hull's level, a pirate's npc_ship_level; frozen: a level gained after the open moves no card
-- @pass EV_EQUAL     equal sides roll chase_base at the open
-- @pass EV_RELATIVE  both sides scaled alike: the same chance; her skill, speed and handling each move it by the formula, the same terms on their side move it the other way
-- @pass EV_STATE     a hurt or short-handed runner sails by the sailing rule's two factors; a hurt pursuer raises her chance; the chance follows her hull tick by tick (it falls between her rolls as she is hit)
-- @pass EV_BOUNDS    never under chase_floor or over chase_cap; no speed on her sheet: the floor; nobody afloat to chase: the cap
-- @pass EV_TRIES     on a sheet that runs to the boarding: every roll is the chance served for its tick, each after a failed one flee_per_try lower, down to the floor
-- @pass EV_XP        a real raid on a company's fleet: run_try 5 for each failed roll and run_away 40 for the escape, once a battle; the day's limit holds
-- @pass EV_NO_FARM   a merchant set upon, a company that attacked and ran, and a second close grant nothing
-- @pass EV_OFF       chase_enabled false: 0450's chance on the same sheet; level_perks_on false: every hull's run is 0
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

-- the chance side a would run on at tick 0 (nobody hurt by a shot that counts yet, nobody caught yet)
create function pg_temp.open_156(p_a jsonb, p_b jsonb) returns numeric language sql as $f$
  select (public.tick_fight('00000000-0453-4000-8000-0000000156aa'::uuid, p_a, p_b, '{"a_ai": "FLEE", "a_flee": 0.15}'::jsonb) #>> '{rc,a,0,1}')::numeric;
$f$;

-- a hull's sailing by the knobs: speed x the hull's share x short-handed x handling
create function pg_temp.sail_156(p_speed numeric, p_handling numeric, p_hull_share numeric, p_short boolean) returns numeric language sql as $f$
  select p_speed * (public.wc_num('hull_speed_floor') + (1 - public.wc_num('hull_speed_floor')) * least(1, p_hull_share))
         * case when p_short then public.wc_num('crew_short_speed_mult') else 1 end * (1 + public.wc_num('chase_per_handling') * p_handling / 100);
$f$;

-- the chance by the formula, per cent as the timeline serves it
create function pg_temp.want_156(p_her numeric, p_her_run numeric, p_their numeric, p_their_run numeric, p_tries int default 0) returns numeric language sql as $f$
  select round(least(public.wc_num('chase_cap'), greatest(public.wc_num('chase_floor'),
           public.wc_num('chase_base') * power((p_her * (1 + p_her_run / 100)) / (p_their * (1 + p_their_run / 100)), public.wc_num('chase_power'))
           - p_tries * public.wc_num('flee_per_try'))) * 100);
$f$;

-- the server's tick now is p_tick: the battle began p_tick ticks ago (proof 140's clock)
create function pg_temp.at_tick_156(p_battle uuid, p_tick int) returns void language sql as $f$
  update public.battles b set started_at = clock_timestamp() - make_interval(secs => (p_tick * 600 + 300) / 1000.0),
                              resolves_at = clock_timestamp() - make_interval(secs => (p_tick * 600 + 300) / 1000.0) + make_interval(secs => ((b.ticks ->> 'n')::int + 2) * 0.6)
   where b.id = p_battle;
$f$;

do $p$
declare
  t0      timestamptz := date_trunc('minute', now()) + interval '1 day';
  v_uid   uuid := '00000000-0453-4000-8000-0000000156c1';
  v_hub   uuid := (select p.id from public.ports p where p.code = 'TDC');
  v_lis   uuid := (select p.id from public.ports p where p.code = 'LIS');
  v_pl    uuid;
  v_me    uuid;
  v_ms    uuid;
  v_pf    uuid;
  v_m     uuid;
  v_mp    uuid;
  v_bat   uuid;
  v_b     public.battles%rowtype;
  v_r     jsonb;
  v_x     jsonb;
  v_card  jsonb;
  v_ha    jsonb;
  v_hb    jsonb;
  v_f     jsonb;
  v_base  numeric;
  v_lo    numeric;
  v_hi    numeric;
  v_try   numeric;
  v_a     numeric;
  v_s     numeric;
  v_prev  numeric;
  v_n     int := 0;
  v_fail  int;
  v_fled  boolean;
  v_got   int;
  v_note  text := '';
  v_skip  int := 0;
  r       record;
begin
  -- ── THE SCENE: lit as prod is ──
  update public.world_config set value = 'true'::jsonb
   where key in ('pirates_bite', 'attack_enabled', 'levels_bite', 'level_skills_on', 'level_perks_on', 'raid_orders_enabled', 'npc_ship_level_enabled') and value is distinct from 'true'::jsonb;
  update public.world_config set value = 'false'::jsonb where key in ('navy_enabled', 'convoys_enabled') and value is distinct from 'false'::jsonb;
  update public.world_config set value = '["RAID", "ATTACK"]'::jsonb where key = 'tick_fight_kinds';
  if public.wc('chase_enabled') is distinct from 'true'::jsonb then
    raise exception 'PROOF 156 FAIL: chase_enabled is not lit in this world: %', public.wc('chase_enabled');
  end if;
  v_lo := round(public.wc_num('chase_floor') * 100);
  v_hi := round(public.wc_num('chase_cap') * 100);
  v_try := public.wc_num('flee_per_try') * 100;

  v_pl := public.new_house(v_uid, 'Casa Fuga 156', 'PRT', 'LIS', 'Fuga 156', 'carlat', 'Fuga 156', null, false);
  select f.id into v_me from public.fleets f where f.player_id = v_pl;
  select s.id into v_ms from public.ships s where s.fleet_id = v_me;
  -- a pirate of the Brethren's, made by the game's hands (public.form_fleet, public.commission_ship) and levelled by the one writer of a pirate hull's level
  insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc) values (null, 'Lobos 156', public.pirate_nation(), 0, true) returning id into v_mp;
  v_pf := public.form_fleet(v_mp, 'Lobos 156', v_hub);
  perform public.commission_ship(v_mp, v_pf, 'xebec', 'Lobos 156', true, true);
  insert into public.pirate_ships (fleet_id, player_id, ord, home_port, last_port) values (v_pf, v_mp, 900156, v_hub, v_hub);
  perform public.crown_hull_level_fix(v_mp);
  update public.ships s set crew = (select c.crew_required from public.ship_classes c where c.id = s.class_id), durability = (select b.durability from public.ship_base(s.id) b) where s.fleet_id = v_pf;
  update public.fleets f set status = 'DOCKED', port_id = v_hub, busy_until = null, ready_at = null where f.id = v_pf;
  select nf.fleet_id, f.player_id into v_m, v_mp
    from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id join public.players pl on pl.id = f.player_id
   where pl.is_npc and pl.nation_id is distinct from public.pirate_nation() and public.fleet_kind(nf.fleet_id) = 'MERCHANT'
     and exists (select 1 from public.ships s where s.fleet_id = nf.fleet_id and s.durability > 0)
   order by nf.fleet_id limit 1;

  -- ── EV_PAGE ──
  perform cmd.assume_identity(v_uid);
  v_r := world.levels() -> 'level_skills';
  v_x := (select e from jsonb_array_elements(v_r -> 'skills') e where e ->> 'code' = 'evasion');
  if jsonb_array_length(v_r -> 'skills') <> 11 or (v_r -> 'skills' -> 10 ->> 'code') <> 'evasion' or v_x is null
     or (v_x ->> 'kept') <> 'book' or (v_x ->> 'cap')::int <> 300 or (v_x ->> 'level')::int <> 1
     or (select string_agg((a ->> 'code') || ':' || (a ->> 'xp'), ',' order by a ->> 'code') from jsonb_array_elements(v_x -> 'activities') a) <> 'run_away:40,run_try:5'
     or (select count(*) from jsonb_array_elements(v_x -> 'benefits') b where b ->> 'kind' = 'perk' and b ->> 'perk' = 'run') <> 19
     or (select (b ->> 'total')::numeric from jsonb_array_elements(v_x -> 'benefits') b where b ->> 'kind' = 'perk' and (b ->> 'level')::int = 10) <> 90 then
    raise exception 'PROOF 156 FAIL: the page does not serve Evasion as the eleventh level with its two activities and nineteen steps: %', left(v_x::text, 500);
  end if;
  raise notice 'PASS: EV_PAGE — % levels, the last %: kept by the book, %/day, raised by % ; % steps of "run" (level 10: +% %%)',
    jsonb_array_length(v_r -> 'skills'), v_x ->> 'code', v_x ->> 'cap',
    (select string_agg((a ->> 'code') || ' ' || (a ->> 'xp'), ', ' order by a ->> 'code') from jsonb_array_elements(v_x -> 'activities') a),
    (select count(*) from jsonb_array_elements(v_x -> 'benefits') b where b ->> 'kind' = 'perk'),
    (select b ->> 'total' from jsonb_array_elements(v_x -> 'benefits') b where b ->> 'kind' = 'perk' and (b ->> 'level')::int = 10);

  -- ── EV_CARD: her company at Evasion 10, set upon at sea with a FLEE standing order ──
  -- her Evasion 10 as the book would hold it (a book row and the level row that names it: the book's own chain)
  insert into public.level_book (player_id, skill, seq, activity, xp, xp_after, key) values (v_pl, 'evasion', 1, 'run_away', public.level_points(10)::int, public.level_points(10)::int, 'proof156:seed');
  insert into public.level_xp (player_id, skill, xp, seq) values (v_pl, 'evasion', public.level_points(10)::int, 1);
  update public.fleets f set status = 'ANCHORED', port_id = null, lat = 36.5, lon = -12.0, busy_until = null, ready_at = null where f.id = v_me;
  insert into public.fleet_raid_orders (fleet_id, raid_order) values (v_me, 'FLEE') on conflict (fleet_id) do update set raid_order = excluded.raid_order;
  v_bat := public.battle_open('RAID', v_pf, v_me, t0);
  select b.* into v_b from public.battles b where b.id = v_bat;
  v_card := (select h from jsonb_array_elements(v_b.sheet -> 'a') h where (h ->> 'id')::uuid = v_ms);
  if v_card is null or (v_card ->> 'ev')::int <> 10 or (v_card ->> 'run')::numeric <> (select sum(k.amount) from public.level_perks k where k.perk = 'run' and k.level <= 10) then
    raise exception 'PROOF 156 FAIL: her ship is not on the sheet at her company''s Evasion 10: %', v_card;
  end if;
  for r in select h from jsonb_array_elements(v_b.sheet -> 'b') h loop
    if (r.h ->> 'ev')::int is distinct from public.ship_level((r.h ->> 'id')::uuid) or (r.h ->> 'ev')::int is distinct from public.wc_int('npc_ship_level')
       or (r.h ->> 'run')::numeric is distinct from (select coalesce(sum(k.amount), 0) from public.level_perks k where k.perk = 'run' and k.level <= (r.h ->> 'ev')::int) then
      raise exception 'PROOF 156 FAIL: a pirate''s hull is not on the sheet at her hull''s level, npc_ship_level: %', r.h;
    end if;
  end loop;
  -- frozen: she gains five levels after the open; the re-run reads the sheet
  update public.level_xp x set xp = public.level_points(15)::int where x.player_id = v_pl and x.skill = 'evasion';
  v_f := public.tick_battle_run(v_bat);
  if (select b.sheet from public.battles b where b.id = v_bat)::text <> v_b.sheet::text or (v_f -> 'e')::text <> (v_b.ticks -> 'e')::text then
    raise exception 'PROOF 156 FAIL: a level gained after the open moved her card or the fight';
  end if;
  update public.level_xp x set xp = public.level_points(10)::int where x.player_id = v_pl and x.skill = 'evasion';
  v_x := public.evasion_of((select s.id from public.ships s where s.fleet_id = v_m order by s.id limit 1));
  if (v_x ->> 'ev')::int is distinct from public.ship_level((select s.id from public.ships s where s.fleet_id = v_m order by s.id limit 1)) then
    raise exception 'PROOF 156 FAIL: a merchant does not sail with her hull''s level: %', v_x;
  end if;
  raise notice 'PASS: EV_CARD — her % Evasion % (+% %%), the pirate''s % Evasion % (+% %%), a merchant''s hull Evasion %; frozen at the open (a level gained after moved nothing)',
    v_card ->> 'cls', v_card ->> 'ev', v_card ->> 'run', v_b.sheet #>> '{b,0,cls}', v_b.sheet #>> '{b,0,ev}', v_b.sheet #>> '{b,0,run}', v_x ->> 'ev';

  -- ── EV_XP: closed through public.battle_resolve: 5 a failed roll, 40 for the escape, once ──
  v_fail := (select count(*) from jsonb_array_elements(v_b.ticks -> 'e') e where e ->> 2 = 'X' and e ->> 1 = '0' and e ->> 4 = '0');
  v_fled := coalesce((v_b.ticks #>> '{r,fled}')::boolean, false);
  if v_fail = 0 and not v_fled then
    raise exception 'PROOF 156 FAIL: with a FLEE order she never rolled (% in % ticks): nothing to prove', v_b.ticks ->> 'out', v_b.ticks ->> 'n';
  end if;
  perform public.battle_resolve(v_bat, v_b.resolves_at + interval '1 second');
  if (select coalesce(sum(b.xp), 0) from public.level_book b where b.player_id = v_pl and b.skill = 'evasion' and b.activity = 'run_try' and b.key = 'run_try:' || v_bat) <> 5 * v_fail
     or (select coalesce(sum(b.xp), 0) from public.level_book b where b.player_id = v_pl and b.skill = 'evasion' and b.activity = 'run_away' and b.key = 'run_away:' || v_bat) <> (case when v_fled then 40 else 0 end) then
    raise exception 'PROOF 156 FAIL: % failed roll(s), fled %: the book holds %', v_fail, v_fled,
      (select jsonb_agg(jsonb_build_array(b.activity, b.xp, b.key)) from public.level_book b where b.player_id = v_pl);
  end if;
  v_got := (select count(*) from public.level_book b where b.player_id = v_pl);
  perform public.battle_resolve(v_bat, v_b.resolves_at + interval '2 seconds');
  if (select count(*) from public.level_book b where b.player_id = v_pl) <> v_got then
    raise exception 'PROOF 156 FAIL: a second close granted again';
  end if;
  -- the day's limit: a run of a hundred failed rolls is held to what is left of the 300
  v_s := (select x.day_earned from public.level_xp x where x.player_id = v_pl and x.skill = 'evasion');
  v_n := public.level_grant(v_pl, 'run_try', 100, 'proof156:many');
  if (select x.day_earned from public.level_xp x where x.player_id = v_pl and x.skill = 'evasion') <> 300 or v_n <> 300 - v_s then
    raise exception 'PROOF 156 FAIL: the day''s limit did not hold: % before, % granted, % after', v_s, v_n, (select x.day_earned from public.level_xp x where x.player_id = v_pl and x.skill = 'evasion');
  end if;
  raise notice 'PASS: EV_XP — a raid on her: open % %%, % failed roll(s)%: run_try % and run_away % granted once (nothing on a second close); 100 more failed rolls the same day: % granted, the day at 300',
    v_b.ticks #>> '{rc,a,0,1}', v_fail, case when v_fled then ', got away' else '' end, 5 * v_fail, case when v_fled then 40 else 0 end, v_n;

  -- ── EV_NO_FARM ──
  -- (1) a merchant set upon earns nothing
  update public.fleets f set status = 'DOCKED', port_id = v_hub, busy_until = null where f.id = v_pf;
  update public.ships s set crew = (select c.crew_required from public.ship_classes c where c.id = s.class_id), durability = (select b.durability from public.ship_base(s.id) b) where s.fleet_id = v_pf;
  update public.voyages v set status = 'ABORTED' where v.fleet_id = v_m and v.status = 'SAILING';
  update public.fleets f set status = 'ANCHORED', port_id = null, lat = 36.6, lon = -12.0, busy_until = null, ready_at = null where f.id = v_m;
  v_bat := public.battle_open('RAID', v_pf, v_m, t0 + interval '2 hours');
  perform public.battle_resolve(v_bat, (select b.resolves_at from public.battles b where b.id = v_bat) + interval '1 second');
  if exists (select 1 from public.level_book b where b.player_id = v_mp) or exists (select 1 from public.level_xp x where x.player_id = v_mp) then
    raise exception 'PROOF 156 FAIL: a merchant set upon was granted a level';
  end if;
  -- (2) a company that attacks and then runs earns nothing: her ATTACK on the merchant, her Run pressed through cmd.battle_act
  v_got := (select count(*) from public.level_book b where b.player_id = v_pl);
  -- Every world numbers its merchants and rolls its dice anew (a fleet's id and a battle's id are random, and the battle's id is the fight's seed):
  -- a merchant with the better lookout may slip away at the open (n 0), or the fight may end before a Run pressed now could be rolled, and the
  -- door would then rightly refuse her (E_PAST_TICK, E_BATTLE_OVER). That is the fight, not the grant under proof (main's from-zero run,
  -- 2026-11-24: the merchant that world numbered first slipped at once). So she attacks merchants in turn, v_m first, each attack that ends too
  -- soon undone whole (the block's savepoint), until one is fought long enough for her Run to be rolled; no such fight in twenty-five is a red.
  v_bat := null;
  for r in select nf.fleet_id
             from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id join public.players pl on pl.id = f.player_id
            where pl.is_npc and pl.nation_id is distinct from public.pirate_nation() and public.fleet_kind(nf.fleet_id) = 'MERCHANT'
              and exists (select 1 from public.ships s where s.fleet_id = nf.fleet_id and s.durability > 0)
            order by (nf.fleet_id = v_m) desc, nf.fleet_id limit 25 loop
    begin
      update public.voyages v set status = 'ABORTED' where v.fleet_id = r.fleet_id and v.status = 'SAILING';
      update public.fleets f set status = 'ANCHORED', port_id = null, lat = 36.6, lon = -12.0, busy_until = null, ready_at = null where f.id in (v_me, r.fleet_id);
      update public.ships s set crew = (select c.crew_required from public.ship_classes c where c.id = s.class_id), durability = (select b.durability from public.ship_base(s.id) b) where s.fleet_id in (v_me, r.fleet_id);
      v_bat := public.battle_open('ATTACK', v_me, r.fleet_id, t0 + interval '4 hours');
      select b.* into v_b from public.battles b where b.id = v_bat;
      if v_b.ticks is null then
        raise exception 'PROOF 156 FAIL: her attack was not fought tick by tick';
      end if;
      if (v_b.ticks ->> 'n')::int < 26 then
        raise exception 'the fight ended at tick %', v_b.ticks ->> 'n' using errcode = 'PR156';
      end if;
      exit;
    exception when sqlstate 'PR156' then
      v_bat := null;
      v_skip := v_skip + 1;
    end;
  end loop;
  if v_bat is null then
    raise exception 'PROOF 156 FAIL: her attack on % merchant(s) in turn never lasted the 26 ticks a Run needs', v_skip;
  end if;
  v_n := least(10, (v_b.ticks ->> 'n')::int - 25);
  perform pg_temp.at_tick_156(v_bat, v_n);
  v_r := cmd.battle_act(v_bat, v_me, 'RN', v_n + 1);
  if not coalesce((v_r ->> 'ok')::boolean, false) then
    raise exception 'PROOF 156 FAIL: her Run in her own attack was refused: %', v_r - 'ticks';
  end if;
  if not exists (select 1 from jsonb_array_elements(v_r #> '{ticks,e}') e where e ->> 2 = 'X') then
    raise exception 'PROOF 156 FAIL: her Run in her own attack never rolled';
  end if;
  perform public.battle_resolve(v_bat, (select b.resolves_at from public.battles b where b.id = v_bat) + interval '1 second');
  if (select count(*) from public.level_book b where b.player_id = v_pl) <> v_got then
    raise exception 'PROOF 156 FAIL: a company that attacked and ran was granted Evasion';
  end if;
  raise notice 'PASS: EV_NO_FARM — a merchant set upon: no level row; her own attack (% merchant(s) before this one ended the fight too soon for a Run), Run pressed at tick % (% roll(s)): nothing; a second close: nothing (EV_XP)',
    v_skip, v_n + 1, (select count(*) from jsonb_array_elements(v_r #> '{ticks,e}') e where e ->> 2 = 'X');

  -- ── THE ENGINE ON FIXED SHEETS: two hulls so large nobody is hurt by tick 0, speed 18, handling 80, no Evasion benefit ──
  v_ha := jsonb_build_array(jsonb_build_object('id', '00000000-0453-4000-8000-000000015601', 'name', 'Lebre', 'tier', 2, 'hull', 100000, 'maxd', 100000, 'crew', 40, 'crew_need', 40,
            'attack', 6, 'accuracy', 50, 'reach', 20, 'armour', 0, 'sighting', 8, 'boarder_pct', 0, 'lv', 3, 'speed', 18, 'handling', 80, 'ev', 1, 'run', 0));
  v_hb := jsonb_build_array(jsonb_build_object('id', '00000000-0453-4000-8000-000000015602', 'name', 'Lobo', 'tier', 2, 'hull', 100000, 'maxd', 100000, 'crew', 60, 'crew_need', 40,
            'attack', 6, 'accuracy', 50, 'reach', 20, 'armour', 0, 'sighting', 8, 'boarder_pct', 0, 'lv', 3, 'speed', 18, 'handling', 80, 'ev', 1, 'run', 0));

  -- ── EV_EQUAL ──
  v_base := pg_temp.open_156(v_ha, v_hb);
  if v_base <> round(public.wc_num('chase_base') * 100) or v_base <> pg_temp.want_156(1, 0, 1, 0) then
    raise exception 'PROOF 156 FAIL: equal sides would run on % %%, not chase_base', v_base;
  end if;
  -- the sighting lead and the level are not in the chase
  if pg_temp.open_156(jsonb_set(jsonb_set(v_ha, '{0,sighting}', '20'), '{0,lv}', '9'), v_hb) <> v_base then
    raise exception 'PROOF 156 FAIL: a sighting lead or a level moved the chase';
  end if;
  raise notice 'PASS: EV_EQUAL — equal sides % %% at the open (chase_base %); a sighting lead of 12 and six levels ahead move nothing', v_base, public.wc_num('chase_base');

  -- ── EV_RELATIVE ──
  for r in select * from (values
      ('both twice as fast',     jsonb_set(v_ha, '{0,speed}', '36'), jsonb_set(v_hb, '{0,speed}', '36'), pg_temp.want_156(36 * 1.4, 0, 36 * 1.4, 0)),
      ('both skilled alike',     jsonb_set(v_ha, '{0,run}', '90'), jsonb_set(v_hb, '{0,run}', '90'), pg_temp.want_156(1, 90, 1, 90)),
      ('her skill 40',           jsonb_set(v_ha, '{0,run}', '40'), v_hb, pg_temp.want_156(1, 40, 1, 0)),
      ('their skill 40',         v_ha, jsonb_set(v_hb, '{0,run}', '40'), pg_temp.want_156(1, 0, 1, 40)),
      ('her speed 20',           jsonb_set(v_ha, '{0,speed}', '20'), v_hb, pg_temp.want_156(pg_temp.sail_156(20, 80, 1, false), 0, pg_temp.sail_156(18, 80, 1, false), 0)),
      ('their speed 20',         v_ha, jsonb_set(v_hb, '{0,speed}', '20'), pg_temp.want_156(pg_temp.sail_156(18, 80, 1, false), 0, pg_temp.sail_156(20, 80, 1, false), 0)),
      ('her handling 100',       jsonb_set(v_ha, '{0,handling}', '100'), v_hb, pg_temp.want_156(pg_temp.sail_156(18, 100, 1, false), 0, pg_temp.sail_156(18, 80, 1, false), 0)),
      ('their handling 100',     v_ha, jsonb_set(v_hb, '{0,handling}', '100'), pg_temp.want_156(pg_temp.sail_156(18, 80, 1, false), 0, pg_temp.sail_156(18, 100, 1, false), 0)),
      ('a Nau against a xebec',  jsonb_set(jsonb_set(v_ha, '{0,speed}', '13.2'), '{0,handling}', '45'), jsonb_set(jsonb_set(v_hb, '{0,speed}', '19.5'), '{0,handling}', '90'),
                                 pg_temp.want_156(pg_temp.sail_156(13.2, 45, 1, false), 0, pg_temp.sail_156(19.5, 90, 1, false), 0))) z(what, a, b, want) loop
    v_a := pg_temp.open_156(r.a, r.b);
    if v_a is distinct from r.want then
      raise exception 'PROOF 156 FAIL: % she would run on % %%, not % by the formula', r.what, v_a, r.want;
    end if;
    v_note := v_note || case when v_note = '' then '' else ', ' end || r.what || ' ' || v_a;
  end loop;
  if pg_temp.open_156(jsonb_set(v_ha, '{0,run}', '40'), v_hb) <= v_base or pg_temp.open_156(v_ha, jsonb_set(v_hb, '{0,run}', '40')) >= v_base
     or pg_temp.open_156(jsonb_set(v_ha, '{0,speed}', '20'), v_hb) <= v_base or pg_temp.open_156(v_ha, jsonb_set(v_hb, '{0,speed}', '20')) >= v_base then
    raise exception 'PROOF 156 FAIL: a better runner or a better pursuer does not move the chance the right way';
  end if;
  raise notice 'PASS: EV_RELATIVE — %', v_note;

  -- ── EV_STATE ──
  if pg_temp.open_156(jsonb_set(v_ha, '{0,hull}', '50000'), v_hb) <> pg_temp.want_156(pg_temp.sail_156(18, 80, 0.5, false), 0, pg_temp.sail_156(18, 80, 1, false), 0)
     or pg_temp.open_156(jsonb_set(v_ha, '{0,hull}', '25000'), v_hb) <> pg_temp.want_156(pg_temp.sail_156(18, 80, 0.25, false), 0, pg_temp.sail_156(18, 80, 1, false), 0)
     or pg_temp.open_156(jsonb_set(v_ha, '{0,crew}', '39'), v_hb) <> pg_temp.want_156(pg_temp.sail_156(18, 80, 1, true), 0, pg_temp.sail_156(18, 80, 1, false), 0)
     or pg_temp.open_156(jsonb_set(jsonb_set(v_ha, '{0,hull}', '25000'), '{0,crew}', '20'), v_hb) <> pg_temp.want_156(pg_temp.sail_156(18, 80, 0.25, true), 0, pg_temp.sail_156(18, 80, 1, false), 0)
     or pg_temp.open_156(v_ha, jsonb_set(v_hb, '{0,hull}', '50000')) <> pg_temp.want_156(pg_temp.sail_156(18, 80, 1, false), 0, pg_temp.sail_156(18, 80, 0.5, false), 0)
     or pg_temp.open_156(v_ha, jsonb_set(v_hb, '{0,hull}', '50000')) <= v_base then
    raise exception 'PROOF 156 FAIL: her state or theirs does not move the chase by the sailing rule: half % quarter % short % both % pursuer half %',
      pg_temp.open_156(jsonb_set(v_ha, '{0,hull}', '50000'), v_hb), pg_temp.open_156(jsonb_set(v_ha, '{0,hull}', '25000'), v_hb), pg_temp.open_156(jsonb_set(v_ha, '{0,crew}', '39'), v_hb),
      pg_temp.open_156(jsonb_set(jsonb_set(v_ha, '{0,hull}', '25000'), '{0,crew}', '20'), v_hb), pg_temp.open_156(v_ha, jsonb_set(v_hb, '{0,hull}', '50000'));
  end if;
  -- it follows her hull: a runner of 600 against a heavy pursuer is hit between her rolls, and the chance served falls at a tick that is no roll
  -- (the first of up to 40 seeds on which she is caught long enough to be hit between rolls: a fight she leaves at her first roll shows nothing)
  for r in select g from generate_series(1, 40) g loop
    v_f := public.tick_fight(('00000000-0453-4000-8000-0000001561' || lpad(r.g::text, 2, '0'))::uuid,
                             jsonb_set(jsonb_set(v_ha, '{0,hull}', '600'), '{0,maxd}', '600'),
                             jsonb_set(jsonb_set(v_hb, '{0,attack}', '40'), '{0,accuracy}', '90'), '{"a_ai": "FLEE", "a_flee": 0.15}'::jsonb);
    v_n := (select count(*) from jsonb_array_elements(v_f #> '{rc,a}') with ordinality q(c, o)
              join jsonb_array_elements(v_f #> '{rc,a}') with ordinality p(d, k) on k = o - 1
             where (c ->> 1)::numeric < (d ->> 1)::numeric
               and not exists (select 1 from jsonb_array_elements(v_f -> 'e') e where e ->> 2 = 'X' and e ->> 1 = '0' and (c ->> 0)::int - (e ->> 0)::int between 0 and 1));   -- a failed roll lowers the next tick's chance
    exit when v_n >= 1;
  end loop;
  if v_n < 1 then
    raise exception 'PROOF 156 FAIL: the chance never fell as she was hit (only at her failed rolls): %', v_f #> '{rc,a}';
  end if;
  raise notice 'PASS: EV_STATE — half her hull %, a quarter %, short-handed %, a quarter and short-handed %; the pursuer at half % (was %); hit: % (tick, %%; % fall(s) at a tick that is no roll)',
    pg_temp.open_156(jsonb_set(v_ha, '{0,hull}', '50000'), v_hb), pg_temp.open_156(jsonb_set(v_ha, '{0,hull}', '25000'), v_hb), pg_temp.open_156(jsonb_set(v_ha, '{0,crew}', '39'), v_hb),
    pg_temp.open_156(jsonb_set(jsonb_set(v_ha, '{0,hull}', '25000'), '{0,crew}', '20'), v_hb), pg_temp.open_156(v_ha, jsonb_set(v_hb, '{0,hull}', '50000')), v_base,
    (select string_agg(format('%s: %s', c ->> 0, c ->> 1), ', ') from jsonb_array_elements(v_f #> '{rc,a}') c), v_n;

  -- ── EV_BOUNDS ──
  if pg_temp.open_156(jsonb_set(v_ha, '{0,run}', '900'), v_hb) <> v_hi
     or pg_temp.open_156(v_ha, jsonb_set(v_hb, '{0,run}', '900')) <> v_lo
     or pg_temp.open_156(jsonb_build_array((v_ha -> 0) - 'speed'), v_hb) <> v_lo
     or pg_temp.open_156(jsonb_set(v_ha, '{0,speed}', '0'), jsonb_set(v_hb, '{0,run}', '-900')) <> v_lo
     or pg_temp.open_156(v_ha, jsonb_set(v_hb, '{0,speed}', '0')) <> v_hi then
    raise exception 'PROOF 156 FAIL: the chase is not held within % .. %: no speed % / nobody to chase %', v_lo, v_hi,
      pg_temp.open_156(jsonb_build_array((v_ha -> 0) - 'speed'), v_hb), pg_temp.open_156(v_ha, jsonb_set(v_hb, '{0,speed}', '0'));
  end if;
  -- a run that is not the side set upon in a raid (no a_flee) is the same chase
  if (public.tick_fight('00000000-0453-4000-8000-0000000156aa'::uuid, jsonb_set(v_ha, '{0,run}', '40'), v_hb, '{"a_ai": "FLEE"}'::jsonb) #>> '{rc,a,0,1}')::numeric <> pg_temp.want_156(1, 40, 1, 0) then
    raise exception 'PROOF 156 FAIL: a run outside a raid is not the same chase';
  end if;
  raise notice 'PASS: EV_BOUNDS — % .. % %%: a runner far ahead the cap, far behind the floor; no speed on her sheet the floor; nobody that sails to chase her the cap; a run outside a raid the same rule', v_lo, v_hi;

  -- ── EV_TRIES: the sheet runs to the boarding (proof 140's hulls); she runs again and again ──
  for r in select g from generate_series(1, 40) g loop
    v_f := public.tick_fight(('00000000-0453-4000-8000-0000001560' || lpad(r.g::text, 2, '0'))::uuid, v_ha, v_hb, '{"a_ai": "FLEE", "a_flee": 0.15}'::jsonb);
    exit when (select count(*) from jsonb_array_elements(v_f -> 'e') e where e ->> 2 = 'X' and e ->> 1 = '0' and e ->> 4 = '0') >= 3;
    v_f := null;
  end loop;
  if v_f is null then
    raise exception 'PROOF 156 FAIL: in 40 fights she was never caught three times';
  end if;
  v_prev := null; v_n := 0;
  for r in select (e ->> 0)::int as t, (e ->> 3)::numeric as pct, o from jsonb_array_elements(v_f -> 'e') with ordinality q(e, o) where e ->> 2 = 'X' and e ->> 1 = '0' order by o loop
    v_n := v_n + 1;
    if r.pct is distinct from (select (c ->> 1)::numeric from jsonb_array_elements(v_f #> '{rc,a}') with ordinality z(c, o) where (c ->> 0)::int <= r.t order by o desc limit 1)
       or r.pct not between v_lo and v_hi then
      raise exception 'PROOF 156 FAIL: the roll at tick % was on % %%, not the chance served for that tick', r.t, r.pct;
    end if;
    if v_prev is not null and r.pct <> greatest(v_lo, v_prev - v_try) then
      raise exception 'PROOF 156 FAIL: after a failed roll on % %% the next was on % %%, not % lower (floor %)', v_prev, r.pct, v_try, v_lo;
    end if;
    v_prev := r.pct;
  end loop;
  raise notice 'PASS: EV_TRIES — % roll(s): % (each the chance served, each % lower than the last, down to the floor %)',
    v_n, (select string_agg((e ->> 3) || ' %', ', ' order by o) from jsonb_array_elements(v_f -> 'e') with ordinality q(e, o) where e ->> 2 = 'X' and e ->> 1 = '0'), v_try, v_lo;

  -- ── EV_OFF ──
  update public.world_config set value = 'false'::jsonb where key = 'chase_enabled';
  v_a := pg_temp.open_156(jsonb_set(v_ha, '{0,run}', '190'), v_hb);
  if v_a <> least(round(public.wc_num('raid_flee_max') * 100), greatest(round(public.wc_num('raid_flee_floor') * 100), round((public.wc_num('raid_flee_base') + 0.15) * 100))) then
    raise exception 'PROOF 156 FAIL: with chase_enabled false she would run on % %%, not 0450''s raid_flee_base + her bonus', v_a;
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'chase_enabled';
  update public.world_config set value = 'false'::jsonb where key = 'level_perks_on';
  if (public.evasion_of(v_ms) ->> 'run')::numeric <> 0 or (public.battle_hull_card(v_ms) ->> 'run')::numeric <> 0 or (public.evasion_of(v_ms) ->> 'ev')::int <> 10 then
    raise exception 'PROOF 156 FAIL: with level_perks_on false her Evasion is still worth something: %', public.evasion_of(v_ms);
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'level_perks_on';
  raise notice 'PASS: EV_OFF — chase_enabled false: % %% at the open whatever her skill (0450''s raid_flee_base + her bonus); level_perks_on false: Evasion 10 worth 0', v_a;
end $p$;
