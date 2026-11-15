-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0432 - A RAIDED SHIP MAY RUN  (pirates raid the world's merchants first; every side of a battle is held to its end; a defender may run each
--        round, by her speed and her company's handling; a ship out of a battle has five minutes of peace)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-15: "pirates' main goal is to attack other npcs, loot them. while attacking each ships cannot move until the battle is over
--   (destroyed, ran away etc.) running away is an option (attempting to run away), but it will need skills for higher probability. after it ran,
--   the attacked ship will have 5 mins of peace time - no pirates or other npcs will be able to attack them." (row 349; docs/dev-log/2026-11-15-pirate-flee.md)
--
-- WHAT WAS ALREADY TRUE (read on the head world; proof 133 holds it):
--   HELD: public.battle_open stops EVERY side (public.battle_stop): a fleet under sail is held where she is (voyage.hold: her point stands still and
--     fleets.busy_until is the battle's clock), one in port or at anchor is IN_BATTLE. cmd.divert refuses a held fleet (E_FLEET_BUSY, 0323); an
--     IN_BATTLE fleet runs no order and takes no step (cmd.advance, public.pirate_ship_step, the merchants' and cargo ships' steps read DOCKED) until
--     public.battle_resolve frees her. The attacker is held the same way.
--   RUNNING: a side's stance FLEE (0353, 0357): her guns fall silent, she takes that round's fire and rolls to slip away (public.fight_sides);
--     away, the battle ends there (EVADED, `fled`), nothing more is taken. A player sets it on the battle card (cmd.battle_stance; world.battle
--     serves `may` FIGHT/FLEE/PAY to a defender). A failed roll costs the round: she was fired on and fired nothing.
-- WHAT THIS FILE ADDS:
--   F1. PIRATES RAID THE WORLD FIRST (public.raid_target, one hunk): among the merchants in reach, a ship of the world (MERCHANT, CARGO_SHIP) comes
--       before a player's ship, then the nearest. Players stay raidable (0427); no PvP.
--   F2. A RAIDED SHIP OF THE WORLD RUNS BY A RULE (public.battle_sheet_freeze, one hunk): set upon in a RAID, a MERCHANT or CARGO_SHIP opens with FLEE
--       when her side's strength (voyage.escort_score) is under the raider's x raid_flee_ratio (1.0); else she fights. A player's ship opens with
--       her standing order, as before, and may press Flee on the card each round.
--   F3. RUNNING NEEDS SKILL (public.flee_bonus; public.battle_sheet_freeze, battle_fight, fight_sides one hunk each): in a RAID the side set upon rolls
--         chance = clamp(raid_flee_floor 0.10, fight_flee_base 0.15 + (her best sighting - theirs) x fight_evade_per_sighting 0.03
--                        + speed term + handling term, raid_flee_max 0.80)
--         speed term    = clamp(-0.15, (her fleet's speed / the raider's - 1) x raid_flee_per_speed 0.30, +0.25)   (voyage.fleet_speed: hulls, gear, skills)
--         handling term = min(0.25, her company's `handling` skill % on her flagship (world.skill_pct) / 100 x raid_flee_per_handling 0.5)
--       frozen on the sheet at the open (`a_flee`), so every re-run of the fight is the same fight. An ATTACK keeps 0357's chance, to the digit.
--   F4. FIVE MINUTES OF PEACE (public.fleet_peace_until): a ship whose battle as the side set upon has ended (she ran, beat them off, was boarded,
--       or it broke off) is at peace for peace_after_flee_minutes (5): public.raid_target passes her over (one hunk; this replaces 0427's
--       attack_ship_minutes rest for raids). Her own fleet card says so (world.fleets, one hunk: `peace_until`, absent otherwise): "Peace 4:12".
--   F5. THE STATS COUNT RUNS (public.stats_fleets_count, world.stats_fleets, one hunk each): raids_fled; the Battles card's "Fled".
-- LOAD: -- budget: no new rows of its own: a FLEE stance row at a raid's open when a ship runs (~1 a raid, 2 a minute at most); one index probe of
--   battle_sides a candidate (8 a pirate asked) and one a player's fleet read; a sheet carries one more number. ~+2 rows a minute. No job, no table.
-- LOCKS: CREATE OR REPLACE x7 by hunks; CREATE FUNCTION x2. BUDGET: statement_timeout 45 s, lock_timeout 5 s; fails above 30 s.
-- ROLLBACK (forward, owner only): scripts/ops/harness/pirate-war/rollback-0432.sql (a draft: the hunks reversed, the two functions dropped, the knobs
--   deleted). Quick: raid_flee_ratio 0 (no ship of the world runs by the rule), peace_after_flee_minutes 0 (no peace).
-- SELF-ASSERT: every hunk once and reversing; grants, volatility, definer, search path, owner unmoved; no other function moved; the new functions
--   server-only; the knobs; arithmetic of public.fight_sides on a fixed sheet: with no a_flee the chance is 0357's, with one it is clamped to the
--   raid's floor and cap. THE PROBE, rolled back: a hunting pirate's strike (if any in this world), her target a ship of the world first.
-- VERSION: 0432 = 0431 + 1 (0430 cargo 100, 0431 stats tabs, queued ahead), after 0427 (#706) and 0429. Written on the chain to 0429.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array[
    'public.raid_target(uuid,timestamp with time zone)', 'public.battle_sheet_freeze(uuid,timestamp with time zone)', 'public.battle_fight(uuid,integer)',
    'public.fight_sides(uuid,integer,jsonb,jsonb,jsonb)', 'world.fleets()', 'public.stats_fleets_count(timestamp with time zone,timestamp with time zone)',
    'world.stats_fleets()'];
  c_new constant text[] := array['public.flee_bonus(uuid,uuid)', 'public.fleet_peace_until(uuid)'];
  v_t0        timestamptz := clock_timestamp();
  v_h         record;
  x           record;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_fn_before text;
  v_meta      text;
  v_hull      jsonb;
  v_f0        jsonb;
  v_f1        jsonb;
  v_f2        jsonb;
  v_note      text := 'no hunting pirate with a ship in reach in this world: proof 133 strikes one';
  v_p         uuid;
  v_t         uuid;
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config where key = 'peace_after_flee_minutes') then
    raise exception '0432 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.raid_target(uuid,timestamp with time zone)') is null or to_regprocedure('public.news_update(text,text,text)') is null
     or not exists (select 1 from public.world_config where key = 'pirate_city_purse') then
    raise exception '0432 refuses: 0427 (the raids) or 0429 (the pirate purses) is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGE ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  -- a fixed sheet for the arithmetic (one hull a side, the same figures): 0357's answer before any hunk
  v_hull := jsonb_build_array(jsonb_build_object('id', '00000000-0432-4000-8000-000000000001', 'name', 'a', 'tier', 2, 'hull', 100, 'maxd', 100, 'crew', 40,
              'attack', 10, 'accuracy', 0.5, 'reach', 1, 'armour', 0, 'sighting', 5, 'boarder_pct', 0));
  v_f0 := public.fight_sides('00000000-0432-4000-8000-0000000000aa'::uuid, 1, v_hull, v_hull, jsonb_build_object('a_order', 'FLEE'));

  -- ── 2. THE KNOBS ──
  insert into public.world_config (key, value, description) values
    ('peace_after_flee_minutes', to_jsonb(5), '0432: after a battle she was set upon in ends (ran, beat them off, boarded, broke off), a ship is at peace this many minutes: no pirate raids her (public.fleet_peace_until). 0: none.'),
    ('raid_flee_ratio', to_jsonb(1.0), '0432: a ship of the world set upon in a RAID opens with FLEE when her side''s voyage.escort_score is under the raider''s times this. 0: she always fights.'),
    ('raid_flee_floor', to_jsonb(0.10), '0432: the least chance a round that a ship set upon in a RAID slips away when she runs.'),
    ('raid_flee_max', to_jsonb(0.80), '0432: the most chance a round that a ship set upon in a RAID slips away when she runs.'),
    ('raid_flee_per_speed', to_jsonb(0.30), '0432: a raid''s flee chance per unit of (her fleet speed / the raider''s - 1), within -0.15..+0.25.'),
    ('raid_flee_per_handling', to_jsonb(0.5), '0432: a raid''s flee chance per unit of her company''s handling skill on her flagship (20 % = +0.10), at most +0.25.');

  -- ── 3. THE NEW FUNCTIONS ──
  execute $f$
create function public.flee_bonus(p_fleet uuid, p_foe uuid)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0432: WHAT HER SPEED AND HER COMPANY'S HANDLING ADD TO A RAID'S FLEE CHANCE (public.fight_sides adds it to 0353's base and sighting, then clamps
  -- to raid_flee_floor..raid_flee_max). Speed: (her fleet's speed / the raider's - 1) x raid_flee_per_speed, within -0.15..+0.25 (voyage.fleet_speed:
  -- hulls, gear, skills, the kind's own pace). Handling: her company's `handling` per cent on her flagship (world.skill_pct) / 100 x
  -- raid_flee_per_handling, at most +0.25. Read once, at the open, onto the sheet.
  select round(
           least(0.25, greatest(-0.15, (coalesce(voyage.fleet_speed(p_fleet), 0) / nullif(voyage.fleet_speed(p_foe), 0) - 1) * public.wc_num('raid_flee_per_speed')))
         + least(0.25, greatest(0, coalesce((select world.skill_pct(f.player_id, s.id, 'handling') from public.fleets f join public.ships s on s.fleet_id = f.id and s.is_flagship
                                              where f.id = p_fleet limit 1), 0) / 100 * public.wc_num('raid_flee_per_handling'))), 4)
$body$;
$f$;

  execute $f$
create function public.fleet_peace_until(p_fleet uuid)
returns timestamptz
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0432: UNTIL WHEN A SHIP IS AT PEACE: the end of the newest battle she was set upon in, once it is over, plus peace_after_flee_minutes. Null: never set
  -- upon, or none over. One probe of battle_sides by her fleet (battle_sides_fleet). Read by public.raid_target and world.fleets.
  select max(b.resolves_at) + make_interval(mins => coalesce(public.wc_int('peace_after_flee_minutes'), 0))
    from public.battle_sides bs join public.battles b on b.id = bs.battle_id
   where bs.fleet_id = p_fleet and bs.side = 'DEFENDER' and b.status <> 'FIGHTING'
$body$;
$f$;

  revoke all on function public.flee_bonus(uuid, uuid) from public, anon, authenticated;
  revoke all on function public.fleet_peace_until(uuid) from public, anon, authenticated;

  -- ── 4. THE HUNKS (each occurs exactly once in the live body, and reverses) ──
  create temp table hunks_0432 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0432 values
  ('public.raid_target(uuid,timestamp with time zone)', 1,
$h$     order by c.nm, c.id$h$,
$h$     order by public.fleet_kind(c.id) = 'COMPANY', c.nm, c.id   -- 0432: the world's merchants first ("pirates' main goal is to attack other npcs"), then a player's$h$),
  ('public.raid_target(uuid,timestamp with time zone)', 2,
$h$    continue when exists (select 1 from public.battle_sides bs join public.battles b on b.id = bs.battle_id
                           where bs.fleet_id = r.id and bs.side = 'DEFENDER' and b.started_at > p_now - make_interval(mins => v_rest));$h$,
$h$    continue when public.fleet_peace_until(r.id) > p_now;   -- 0432: five minutes of peace after a battle she was set upon in (was 0427's attack_ship_minutes rest)$h$),
  ('public.battle_sheet_freeze(uuid,timestamp with time zone)', 1,
$h$                   'word', public.attack_word(voyage.escort_score(v_att), voyage.escort_score(v_def))),$h$,
$h$                   'word', public.attack_word(voyage.escort_score(v_att), voyage.escort_score(v_def)))
                 -- 0432: a raid's flee bonus for the side set upon (public.flee_bonus), frozen with her hulls
                 || case when b.kind = 'RAID' then jsonb_build_object('a_flee', public.flee_bonus(v_def, v_att)) else '{}'::jsonb end,$h$),
  ('public.battle_sheet_freeze(uuid,timestamp with time zone)', 2,
$h$  v_st := public.battle_opening_stance(v_def);$h$,
$h$  -- 0432: a ship of the world set upon by a pirate runs when she is outgunned (her side's score under the raider's x raid_flee_ratio)
  v_st := case when b.kind = 'RAID' and public.fleet_kind(v_def) in ('MERCHANT', 'CARGO_SHIP')
                    and voyage.escort_score(v_def) < voyage.escort_score(v_att) * coalesce(public.wc_num('raid_flee_ratio'), 0) then 'FLEE'
               else public.battle_opening_stance(v_def) end;$h$),
  ('public.battle_fight(uuid,integer)', 1,
$h$  return public.fight_sides(p_battle, 1, b.sheet->'a', b.sheet->'b', v_opts);$h$,
$h$  if b.sheet ? 'a_flee' then
    v_opts := v_opts || jsonb_build_object('a_flee', b.sheet->'a_flee');   -- 0432: a raid's flee bonus, frozen on the sheet
  end if;
  return public.fight_sides(p_battle, 1, b.sheet->'a', b.sheet->'b', v_opts);$h$),
  ('public.fight_sides(uuid,integer,jsonb,jsonb,jsonb)', 1,
$h$      v_pf := least(public.wc_num('fight_evade_max'), greatest(public.wc_num('fight_flee_floor'),
                public.wc_num('fight_flee_base') + (v_sa - v_sb) * public.wc_num('fight_evade_per_sighting')));$h$,
$h$      -- 0432: a raid's flee bonus (p_opts.a_flee: her speed and her company's handling, public.flee_bonus) within raid_flee_floor..raid_flee_max; without one, 0357's chance
      v_pf := case when p_opts ? 'a_flee'
                   then least(public.wc_num('raid_flee_max'), greatest(public.wc_num('raid_flee_floor'),
                          public.wc_num('fight_flee_base') + (v_sa - v_sb) * public.wc_num('fight_evade_per_sighting') + (p_opts ->> 'a_flee')::numeric))
                   else least(public.wc_num('fight_evade_max'), greatest(public.wc_num('fight_flee_floor'),
                          public.wc_num('fight_flee_base') + (v_sa - v_sb) * public.wc_num('fight_evade_per_sighting'))) end;$h$),
  ('world.fleets()', 1,
$h$    || case when f.busy_until is not null then public.battle_navy_served(f.id) else '{}'::jsonb end   -- 0333: "Navy arrives 5:10" on the card of a fleet in a battle; absent otherwise$h$,
$h$    || case when f.busy_until is not null then public.battle_navy_served(f.id) else '{}'::jsonb end   -- 0333: "Navy arrives 5:10" on the card of a fleet in a battle; absent otherwise
    || coalesce((select jsonb_build_object('peace_until', x.u) from (select public.fleet_peace_until(f.id) as u) x where x.u > now()), '{}'::jsonb)   -- 0432: "Peace 4:12"; absent otherwise$h$),
  ('public.stats_fleets_count(timestamp with time zone,timestamp with time zone)', 1,
$h$      'attacks', (select count(*) from public.battles b where b.kind = 'ATTACK' and b.started_at > p_since and b.started_at <= p_now)))$h$,
$h$      'attacks', (select count(*) from public.battles b where b.kind = 'ATTACK' and b.started_at > p_since and b.started_at <= p_now),
      -- 0432: the raids that closed in the window with the side set upon gone (she ran and slipped away)
      'raids_fled', (select count(*) from public.battles b where b.kind = 'RAID' and b.status <> 'FIGHTING' and b.resolves_at > p_since and b.resolves_at <= p_now
                       and coalesce((b.result ->> 'fled')::boolean, false))))$h$),
  ('world.stats_fleets()', 1,
$h$                              coalesce(sum((x.figures -> 'win' ->> 'attacks')::int), 0) as b_attacks$h$,
$h$                              coalesce(sum((x.figures -> 'win' ->> 'attacks')::int), 0) as b_attacks,
                              coalesce(sum((x.figures -> 'win' ->> 'raids_fled')::int), 0) as b_fled   -- 0432$h$),
  ('world.stats_fleets()', 2,
$h$                                         'attacks_day', d.b_attacks, 'navy_fights_day', d.fights)) end$h$,
$h$                                         'attacks_day', d.b_attacks, 'navy_fights_day', d.fights, 'fled_day', d.b_fled)) end   -- 0432: fled_day$h$);

  for v_h in select h.fn from hunks_0432 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0432 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0432 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0432 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0432 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0432 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 5. SELF-ASSERT: the catalog, the knobs, the arithmetic ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_new) u(q)))) <> v_fn_before then
    raise exception '0432 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0432 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked function moved';
  end if;
  if exists (select 1 from unnest(c_new) f
              where has_function_privilege('anon', f::regprocedure, 'execute') or has_function_privilege('authenticated', f::regprocedure, 'execute'))
     or exists (select 1 from unnest(c_new) f join public.client_rpc_entry_points() e on e.fn = f::regprocedure) then
    raise exception '0432 self-assert FAIL: a function of this file is open to clients';
  end if;
  if public.wc_int('peace_after_flee_minutes') <> 5 or public.wc_num('raid_flee_floor') <> 0.10 or public.wc_num('raid_flee_max') <> 0.80 then
    raise exception '0432 self-assert FAIL: the knobs are not this file''s';
  end if;
  -- the fixed sheet: no a_flee is 0357's fight to the text; a_flee +5 caps at raid_flee_max, -5 floors at raid_flee_floor
  v_f1 := public.fight_sides('00000000-0432-4000-8000-0000000000aa'::uuid, 1, v_hull, v_hull, jsonb_build_object('a_order', 'FLEE'));
  if v_f1::text <> v_f0::text then
    raise exception '0432 self-assert FAIL: a fight with no a_flee moved';
  end if;
  v_f1 := public.fight_sides('00000000-0432-4000-8000-0000000000aa'::uuid, 1, v_hull, v_hull, jsonb_build_object('a_order', 'FLEE', 'a_flee', 5));
  v_f2 := public.fight_sides('00000000-0432-4000-8000-0000000000aa'::uuid, 1, v_hull, v_hull, jsonb_build_object('a_order', 'FLEE', 'a_flee', -5));
  if (v_f1 #>> '{rounds,0,flee}')::numeric is distinct from public.wc_num('raid_flee_max')
     or (v_f2 #>> '{rounds,0,flee}')::numeric is distinct from public.wc_num('raid_flee_floor') then
    raise exception '0432 self-assert FAIL: the raid''s flee chance is not clamped to its floor and cap: % / %', v_f1 #> '{rounds,0,flee}', v_f2 #> '{rounds,0,flee}';
  end if;

  -- ── 6. THE NEWS (0347's law) ──
  perform public.news_update('0432', 'A ship set upon by pirates may run; five minutes of peace after a fight',
                             '해적에게 습격당한 배는 도주할 수 있다; 전투 뒤 5분간 평화');

  -- ── 7. THE PROBE, rolled back by a raised sentinel: a hunting pirate's target, the world's ship first ──
  begin
    update public.world_config set value = 'true'::jsonb where key in ('attack_enabled', 'pirates_bite', 'city_treasury_enabled') and value is distinct from 'true'::jsonb;
    if public.attack_on() and public.pirates_on() then
      select c.fleet_id, public.raid_target(c.fleet_id, now()) into v_p, v_t
        from public.pirate_ships_cruising c join public.fleets f on f.id = c.fleet_id
       where f.busy_until is null and public.raid_target(c.fleet_id, now()) is not null
       order by c.ord limit 1;
      if v_t is not null then
        if public.fleet_peace_until(v_t) > now() then
          raise exception '0432 self-assert FAIL: a ship at peace was chosen';
        end if;
        v_note := 'a hunting pirate''s target is a ' || public.fleet_kind(v_t) || ', not at peace (rolled back)';
      end if;
    end if;
    raise exception sqlstate 'BV432';
  exception when sqlstate 'BV432' then null;
  end;
  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0432 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0432 self-assert ok: A RAIDED SHIP MAY RUN. % hunks once each and reversing; grants and volatility unmoved; no other function moved; 2 new functions, server-only; a fight with no a_flee unmoved, a raid''s chance within % .. %. Peace % min. Probe: %; % ms.',
    (select count(*) from hunks_0432), public.wc_num('raid_flee_floor'), public.wc_num('raid_flee_max'), public.wc_int('peace_after_flee_minutes'), v_note,
    round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0432;
end $m$;
