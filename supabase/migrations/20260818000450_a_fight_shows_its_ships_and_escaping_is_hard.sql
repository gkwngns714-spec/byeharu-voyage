-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0450 - A FIGHT SHOWS ITS SHIPS, AND ESCAPING IS HARD  (every hull's card frozen on the battle sheet and served to the battle screen; a run's
--        chance low, moved by level, by a crippled hull or a short crew, and by every failed attempt; the map's card says each fleet's level)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-16: "in fight, i want to see levels, their stats, their crew state, equipments, etc. levels, escaping should be hard. and
--   fighting graphics (ships), make it smaller, and fight scene more wider." (docs/dev-log/2026-11-16-battle-stats.md)
--
-- WHAT IS THERE (read on the chain at 0444):
--   THE SHEET  public.battle_sheet_freeze freezes voyage.fleet_hulls once at the open: per hull id, name, tier, hull, maxd, crew, attack, accuracy,
--     reach, armour, sighting, boarder_pct, boarder, gunner, gear (only what works on a PIRATES day). No level, class, guns, crew she needs or may
--     carry, speed, handling, or what is fitted. world.battle_ticks serves the timeline (per ship: name, fleet, hull, max, tier, reload) and the sides.
--   THE LEVEL  a hull's level is her experience on the one curve (public.ship_xp, public.level_in_force: 1 while levels_bite is off). A merchant's is
--     fixed at her founding (0127), a crown's or a pirate's at npc_ship_level (0344). IT ALREADY FIGHTS: world.ship_stats adds, per level above 1,
--     ship_level_accuracy_per_level to her accuracy (her chance to hit), ship_level_sighting_per_level to her sighting (who sees first, and the
--     sighting term of a run) and ship_level_handling_per_level to her handling. So this file adds NO second to-hit or crit by level: it would count
--     a level twice.
--   THE RUN    public.tick_fight rolls, at the end of a Run's 20 silent ticks, for the side set upon in a RAID
--       clamp(raid_flee_floor 0.10, fight_flee_base 0.15 + sighting lead x 0.03 + a_flee (0432: speed -0.15..+0.25, handling 0..+0.25), raid_flee_max 0.80)
--     and for any other run 0357's clamp(fight_flee_floor 0.05, fight_flee_base 0.15 + sighting lead x 0.03, fight_evade_max 0.30). The same chance
--     every attempt, whatever her hull, and a ship that runs tries again every 20 ticks: five or six rolls a fight.
-- WHAT THIS FILE DOES:
--   S1. A HULL'S CARD (public.battle_hull_card, new; public.ship_level, new, the one reading of a hull's level): level, class, guns, the crew she
--       needs and may carry, speed and handling (world.ship_stats: gear, skills, captains), everything fitted (name, slot, wear), her captains
--       (name, combat level). public.tick_battle_run (one hunk) adds it to every hull of the sheet that has none, the first time she is run: at the
--       open for the ships that begin and the ships called, at her join for a ship that joins. Frozen: a re-run reads the sheet.
--   S2. THE SCREEN'S READ (world.battle_ticks, one hunk): `ships: {a: [...], b: [...]}`, each hull of the sheet in the timeline's order (less her id
--       and her boarder share). A battle opened before this file serves the hulls as they were frozen (no card): the screen draws what there is.
--   S3. ESCAPING IS HARD (public.tick_fight, five hunks). ONE formula for every run, computed each tick as the fight stands:
--         chance = clamp(floor, base + (her best sighting - theirs) x fight_evade_per_sighting + a_flee
--                              + clamp(-flee_level_max, (her best level - theirs) x flee_per_level, +flee_level_max)
--                              - flee_hurt_max x max(0, 1 - min(hull left / her size, crew / the crew she needs) / flee_hurt_under)
--                              - failed attempts x flee_per_try, cap)
--       the side set upon in a RAID: base raid_flee_base 0.10 (new), floor raid_flee_floor 0.03 (was 0.10), cap raid_flee_max 0.45 (was 0.80);
--       any other run: 0357's base, floor and cap, unmoved, with the three new terms. flee_per_level 0.03 (flee_level_max 0.15): a level of
--       advantage is +3 points, a level behind -3. flee_hurt_under 0.5, flee_hurt_max 0.20: under half her hull (or half the crew she needs) the
--       chance falls, by 20 points at nothing. flee_per_try 0.05: each failed roll of the same fight costs the next 5 points. Run keeps its 20
--       ticks of silent guns. The timeline serves `rc: {a: [[tick, pct], ...], b: [...]}`, the chance at each tick it changes, so the Run button
--       says what the roll would be now; the `X` event and the log say what it was, as before. Each ship of the timeline carries `lv`.
--   S4. THE MAP'S CARD (public.fight_card, two hunks): each side's `lv`, her fleet's best level (it already serves `ships`).
-- LEFT AS IT IS: public.fight_sides (the round engine, fought only when tick_fight_kinds is []) keeps 0432's formula; it reads the same floor and cap.
-- LOAD: -- budget: no new rows, no table, no job. At a battle's open: one world.ship_stats and four small indexed reads a hull (a raid is 2-4
--   hulls, ~100 raids an hour), and ~0.3-0.6 KB a hull more on the sheet and ~0.3 KB (`rc`) on the timeline, both columns of the battle row, deleted
--   with it (raid_keep_hours 48). The engine: two short loops a tick, knobs read once a fight (it read five knobs a roll). world.fights: one indexed
--   read of ships and ship_xp a side of a card.
-- RETENTION: nothing kept beyond the battle row.
-- LOCKS: CREATE OR REPLACE x4 by hunks; CREATE FUNCTION x2; world_config rows. BUDGET: statement_timeout 45 s, lock_timeout 5 s; fails above 30 s.
-- ROLLBACK (forward, owner only), THE KNOBS ALONE GIVE THE OLD CHANCE TO THE DIGIT (self-asserted below): raid_flee_floor 0.10, raid_flee_max 0.80,
--   raid_flee_base 0.15, flee_per_level 0, flee_hurt_max 0, flee_per_try 0. The whole file: scripts/ops/harness/battle-stats/rollback-0450.sql.
-- IN FLIGHT AT THE DEPLOY: a battle being fought keeps its timeline; if a join or an act re-runs it (within its ~75 s), the re-run is under the new rule.
-- SELF-ASSERT: every hunk once and reversing; grants, volatility, definer, search path, owner of the hunked functions unmoved; no other function
--   moved; the new functions server-only; the knobs; THE ENGINE on a fixed sheet: under the old knobs every event is the event it was before the
--   file; under the new, the chance at tick 0 is base + bonus, +3 points a level ahead, capped, lower with a crippled hull and with a short crew,
--   within floor and cap, and every failed roll is followed by a lower chance; THE PROBE, rolled back: a RAID between two ships of the world is run,
--   every hull of its sheet has her card (level, class, crew, speed, fitted), a second run moves no card, the map's card says each side's level.
-- VERSION: 0450 (0447 is unused; 0448 the Stats' one count deploys ahead and 0449 is the ship art's: neither touches these bodies, nor do 0445
--   pirates cruise the sea and 0446 the real straits). Written on the chain to 0444; its nine old texts read once each on prod at head 0446.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array[
    'public.tick_fight(uuid,jsonb,jsonb,jsonb)', 'public.tick_battle_run(uuid)', 'world.battle_ticks(uuid)', 'public.fight_card(uuid,uuid)'];
  c_new constant text[] := array['public.ship_level(uuid)', 'public.battle_hull_card(uuid)'];
  c_seed constant uuid := '00000000-0450-4000-8000-0000000000aa';
  v_t0        timestamptz := clock_timestamp();
  v_h         record;
  x           record;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_fn_before text;
  v_meta      text;
  v_ha        jsonb;
  v_hb        jsonb;
  v_opts      jsonb := '{"a_ai": "FLEE", "a_flee": 0.15}'::jsonb;
  v_f0        jsonb;
  v_f1        jsonb;
  v_f2        jsonb;
  v_p0        numeric;
  v_p1        numeric;
  v_prev      numeric;
  v_rolls     int := 0;
  v_m1        uuid;
  v_m2        uuid;
  v_bat       uuid;
  v_sheet     jsonb;
  v_card      jsonb;
  v_note      text := '';
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config where key = 'flee_per_level') then
    raise exception '0450 refuses: it has been applied once';
  end if;
  if to_regprocedure('cmd.battle_act(uuid,uuid,text,integer)') is null or to_regprocedure('world.battle_ticks(uuid)') is null
     or to_regprocedure('public.flee_bonus(uuid,uuid)') is null then
    raise exception '0450 refuses: 0432 (a raided ship may run), 0435 (tick combat) or 0439 (a player acts) is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGE ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  -- a fixed sheet (a merchant that runs from a raider she cannot outgun), fought BEFORE any hunk: the fight as it was
  v_ha := jsonb_build_array(jsonb_build_object('id', '00000000-0450-4000-8000-000000000001', 'name', 'a1', 'tier', 2, 'hull', 600, 'maxd', 600, 'crew', 12, 'crew_need', 12,
            'attack', 10, 'accuracy', 40, 'reach', 20, 'armour', 10, 'sighting', 8, 'boarder_pct', 0, 'lv', 3));
  v_hb := jsonb_build_array(jsonb_build_object('id', '00000000-0450-4000-8000-000000000002', 'name', 'b1', 'tier', 2, 'hull', 5000, 'maxd', 5000, 'crew', 60, 'crew_need', 40,
            'attack', 30, 'accuracy', 50, 'reach', 22, 'armour', 12, 'sighting', 8, 'boarder_pct', 0.1, 'lv', 3));
  v_f0 := public.tick_fight(c_seed, v_ha, v_hb, v_opts);

  -- ── 2. THE KNOBS ──
  insert into public.world_config (key, value, description) values
    ('raid_flee_base', to_jsonb(0.10), '0450: the base chance that a ship set upon in a RAID slips away when she runs, before sighting, speed and handling (a_flee), level, her state and her failed attempts. 0.15 = as before 0450.'),
    ('flee_per_level', to_jsonb(0.03), '0450: a run''s chance per level of her side''s best hull over the other side''s best (public.ship_level): each level ahead adds this, each level behind takes it. 0: levels do not move a run.'),
    ('flee_level_max', to_jsonb(0.15), '0450: the most the level difference adds to or takes from a run''s chance.'),
    ('flee_hurt_under', to_jsonb(0.5), '0450: a side whose hull left (of her size) or crew (of the crew she needs) is under this share runs worse: a crippled ship cannot run.'),
    ('flee_hurt_max', to_jsonb(0.20), '0450: what a run''s chance loses with her hull or crew at nothing; in proportion from flee_hurt_under down. 0: her state does not move a run.'),
    ('flee_per_try', to_jsonb(0.05), '0450: what each failed attempt to run in the same fight takes from the next. 0: every attempt rolls the same.');
  update public.world_config set value = to_jsonb(0.03),
         description = '0432, 0450: the least chance that a ship set upon in a RAID slips away when she runs (0450: 0.03, escaping is hard; it was 0.10).'
   where key = 'raid_flee_floor';
  update public.world_config set value = to_jsonb(0.45),
         description = '0432, 0450: the most chance that a ship set upon in a RAID slips away when she runs (0450: 0.45; it was 0.80).'
   where key = 'raid_flee_max';

  -- ── 3. THE NEW FUNCTIONS ──
  execute $f$
create function public.ship_level(p_ship uuid)
returns integer
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0450: A HULL'S LEVEL, THE ONE READING for a battle's sheet and the map's card: her experience on the one curve (public.level_in_force: 1 while
  -- levels_bite is off), 1 with none. The level world.ship_stats adds accuracy, sighting and handling for (0127).
  select coalesce((select case when sx.xp > 0 then public.level_in_force(sx.xp) else 1 end from public.ship_xp sx where sx.ship_id = p_ship), 1)
$body$;
$f$;

  execute $f$
create function public.battle_hull_card(p_ship uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0450: WHAT A HULL IS, BESIDE WHAT voyage.fleet_hulls FREEZES, for the battle screen and the run's chance: `lv` her level (public.ship_level),
  -- `cls` her class, `guns` its guns, `crew_need` the crew her class needs and `crew_max` what she may carry (public.ship_base), `speed` and
  -- `handling` as she is (world.ship_stats: gear, skills, captains), `fit` everything fitted ({n name, s slot, w wear when worn}), `caps` her
  -- captains ({n name, lv combat level}). public.tick_battle_run adds it to a hull of the sheet once. A hull that is no ship of the world: level 1.
  select coalesce((
    select jsonb_build_object(
             'lv', public.ship_level(s.id), 'cls', c.name, 'guns', c.guns,
             'crew_need', c.crew_required, 'crew_max', (select sb.crew_max from public.ship_base(s.id) sb),
             'speed', (x.st ->> 'speed')::numeric, 'handling', (x.st ->> 'handling')::numeric,
             'fit', (select coalesce(jsonb_agg(jsonb_build_object('n', ik.name, 's', ik.slot)
                                                 || case when fu.wear > 0 then jsonb_build_object('w', fu.wear) else '{}'::jsonb end
                                               order by ik.slot, ik.name, fu.id), '[]'::jsonb)
                       from public.fitted_units fu join public.item_kinds ik on ik.code = fu.item_code
                      where fu.ship_id = s.id),
             'caps', (select coalesce(jsonb_agg(jsonb_build_object('n', o.name, 'lv', public.captain_level(po.id, 'combat')) order by cs.seat, o.name), '[]'::jsonb)
                        from public.captain_seats cs
                        join public.player_officers po on po.id = cs.player_officer_id
                        join public.officers o on o.id = po.officer_id
                       where cs.ship_id = s.id))
      from public.ships s
      join public.ship_classes c on c.id = s.class_id
     cross join lateral (select world.ship_stats(s.id) as st) x
     where s.id = p_ship), jsonb_build_object('lv', 1))
$body$;
$f$;

  revoke all on function public.ship_level(uuid) from public, anon, authenticated;
  revoke all on function public.battle_hull_card(uuid) from public, anon, authenticated;

  -- ── 4. THE HUNKS (each occurs exactly once in the live body, and reverses) ──
  create temp table hunks_0450 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0450 values
  ('public.tick_fight(uuid,jsonb,jsonb,jsonb)', 1,
$h$  v_act    jsonb;
begin$h$,
$h$  v_act    jsonb;
  -- 0450: ESCAPING IS HARD. Each hull's level and the crew she needs; each side's failed attempts; the chance a run would roll now and where it
  -- changed (`rc`); the knobs, read once a fight.
  h_lvl    numeric[] := '{}';
  h_need   numeric[] := '{}';
  s_try    int[] := array[0, 0];
  f_p      numeric[] := array[0, 0]::numeric[];
  f_last   numeric[] := array[null, null]::numeric[];
  f_lv     numeric[];
  f_hull   numeric;
  f_max    numeric;
  f_crew   numeric;
  f_need   numeric;
  v_rc     jsonb[] := array['[]'::jsonb, '[]'::jsonb];
  c_fbase  numeric := public.wc_num('fight_flee_base');
  c_ffloor numeric := public.wc_num('fight_flee_floor');
  c_emax   numeric := public.wc_num('fight_evade_max');
  c_psight numeric := public.wc_num('fight_evade_per_sighting');
  c_rbase  numeric := coalesce(public.wc_num('raid_flee_base'), public.wc_num('fight_flee_base'));
  c_rfloor numeric := public.wc_num('raid_flee_floor');
  c_rmax   numeric := public.wc_num('raid_flee_max');
  c_plv    numeric := coalesce(public.wc_num('flee_per_level'), 0);
  c_lvmax  numeric := coalesce(public.wc_num('flee_level_max'), 0);
  c_hurt   numeric := coalesce(public.wc_num('flee_hurt_max'), 0);
  c_under  numeric := coalesce(public.wc_num('flee_hurt_under'), 0);
  c_ptry   numeric := coalesce(public.wc_num('flee_per_try'), 0);
begin$h$),
  ('public.tick_fight(uuid,jsonb,jsonb,jsonb)', 2,
$h$      h_wloss[n] := 0;
      v_meta[s]  := v_meta[s] || jsonb_build_array(jsonb_build_object('n', x ->> 'name', 'fl', x ->> 'fleet_name', 'h', h_hull0[n], 'm', h_maxd[n],
                      't', h_tier[n], 'r', h_rel[n], 'f', h_from[n], 'g', h_att[n] > 0 and h_acc[n] > 0));$h$,
$h$      h_wloss[n] := 0;
      h_lvl[n]   := greatest(1, coalesce((x ->> 'lv')::numeric, 1));          -- 0450: her level (public.battle_hull_card on the sheet; none: 1)
      h_need[n]  := greatest(0, coalesce((x ->> 'crew_need')::numeric, 0));   -- 0450: the crew her class needs (none on the sheet: her crew is never short)
      v_meta[s]  := v_meta[s] || jsonb_build_array(jsonb_build_object('n', x ->> 'name', 'fl', x ->> 'fleet_name', 'h', h_hull0[n], 'm', h_maxd[n],
                      't', h_tier[n], 'r', h_rel[n], 'f', h_from[n], 'g', h_att[n] > 0 and h_acc[n] > 0, 'lv', h_lvl[n]));$h$),
  ('public.tick_fight(uuid,jsonb,jsonb,jsonb)', 3,
$h$      for s in 1 .. 2 loop
        continue when s_run[s] <> t;
        o := 3 - s;
        v_p := case when s = 1 and p_opts ? 'a_flee'
                    then least(public.wc_num('raid_flee_max'), greatest(public.wc_num('raid_flee_floor'),
                           public.wc_num('fight_flee_base') + (s_sight[1] - s_sight[2]) * public.wc_num('fight_evade_per_sighting') + (p_opts ->> 'a_flee')::numeric))
                    else least(public.wc_num('fight_evade_max'), greatest(public.wc_num('fight_flee_floor'),
                           public.wc_num('fight_flee_base') + (s_sight[s] - s_sight[o]) * public.wc_num('fight_evade_per_sighting'))) end;$h$,
$h$      -- 0450: THE CHANCE A RUN WOULD SLIP AWAY, each side, as the fight stands after this tick's shots. ONE formula (the roll below reads it, and
      -- `rc` serves it to the Run button): base + sighting lead + a raid's a_flee (speed, handling) + the level difference - a crippled hull or a
      -- short crew - her failed attempts, within the floor and the cap of its kind (a raid's side set upon; any other run 0357's).
      f_lv := array[1, 1];
      for i in 1 .. n loop
        if h_up[i] then f_lv[h_side[i]] := greatest(f_lv[h_side[i]], h_lvl[i]); end if;
      end loop;
      for s in 1 .. 2 loop
        o := 3 - s;
        f_hull := 0; f_max := 0; f_crew := 0; f_need := 0;
        for i in 1 .. n loop
          if h_side[i] = s and h_up[i] then
            f_hull := f_hull + h_hull[i]; f_max := f_max + h_maxd[i]; f_crew := f_crew + h_crew[i]; f_need := f_need + h_need[i];
          end if;
        end loop;
        v_p := case when s = 1 and p_opts ? 'a_flee' then c_rbase + (p_opts ->> 'a_flee')::numeric else c_fbase end
               + (s_sight[s] - s_sight[o]) * c_psight
               + least(c_lvmax, greatest(-c_lvmax, (f_lv[s] - f_lv[o]) * c_plv))
               - case when c_under > 0
                      then c_hurt * greatest(0, 1 - least(case when f_max > 0 then f_hull / f_max else 1 end,
                                                          case when f_need > 0 then f_crew / f_need else 1 end) / c_under)
                      else 0 end
               - s_try[s] * c_ptry;
        f_p[s] := case when s = 1 and p_opts ? 'a_flee' then least(c_rmax, greatest(c_rfloor, v_p)) else least(c_emax, greatest(c_ffloor, v_p)) end;
        if round(f_p[s] * 100) is distinct from f_last[s] then
          f_last[s] := round(f_p[s] * 100);
          v_rc[s] := v_rc[s] || jsonb_build_array(jsonb_build_array(t, f_last[s]));
        end if;
      end loop;
      for s in 1 .. 2 loop
        continue when s_run[s] <> t;
        o := 3 - s;
        v_p := f_p[s];$h$),
  ('public.tick_fight(uuid,jsonb,jsonb,jsonb)', 4,
$h$          s_run[s] := -1;$h$,
$h$          s_run[s] := -1;
          s_try[s] := s_try[s] + 1;   -- 0450: caught: her next attempt in this fight is flee_per_try worse$h$),
  ('public.tick_fight(uuid,jsonb,jsonb,jsonb)', 5,
$h$    'e', v_ev, 'out', v_outcome, 'r', v_r);$h$,
$h$    'e', v_ev, 'out', v_outcome, 'r', v_r,
    'rc', jsonb_build_object('a', v_rc[1], 'b', v_rc[2]));   -- 0450: each side's run chance, [tick, per cent] where it changes$h$),
  ('public.tick_battle_run(uuid)', 1,
$h$  select bs.fleet_id into v_att from public.battle_sides bs where bs.battle_id = p_battle and bs.side = 'ATTACKER' and bs.how = 'OPENED';$h$,
$h$  -- 0450: EVERY HULL'S CARD (public.battle_hull_card: level, class, guns, crew she needs and may carry, speed, handling, fitted, captains), added
  -- to a hull of the sheet that has none the first time she is run (the open; a joiner's join) and frozen there: a re-run reads the sheet.
  if exists (select 1 from jsonb_array_elements(coalesce(b.sheet -> 'a', '[]'::jsonb) || coalesce(b.sheet -> 'b', '[]'::jsonb)) e(h) where not (e.h ? 'lv')) then
    b.sheet := b.sheet || jsonb_build_object(
      'a', (select coalesce(jsonb_agg(case when e.h ? 'lv' then e.h else e.h || public.battle_hull_card((e.h ->> 'id')::uuid) end order by e.o), '[]'::jsonb)
              from jsonb_array_elements(coalesce(b.sheet -> 'a', '[]'::jsonb)) with ordinality e(h, o)),
      'b', (select coalesce(jsonb_agg(case when e.h ? 'lv' then e.h else e.h || public.battle_hull_card((e.h ->> 'id')::uuid) end order by e.o), '[]'::jsonb)
              from jsonb_array_elements(coalesce(b.sheet -> 'b', '[]'::jsonb)) with ordinality e(h, o)));
    update public.battles set sheet = b.sheet where id = p_battle;
  end if;
  select bs.fleet_id into v_att from public.battle_sides bs where bs.battle_id = p_battle and bs.side = 'ATTACKER' and bs.how = 'OPENED';$h$),
  ('world.battle_ticks(uuid)', 1,
$h$    'mine', v_mine,$h$,
$h$    'mine', v_mine,
    -- 0450: every hull of the sheet as it was frozen, in the timeline's order (a, b): what the fight fights with, and her card
    'ships', jsonb_build_object(
      'a', (select coalesce(jsonb_agg(e.h - 'id' - 'boarder_pct' order by e.o), '[]'::jsonb) from jsonb_array_elements(coalesce(b.sheet -> 'a', '[]'::jsonb)) with ordinality e(h, o)),
      'b', (select coalesce(jsonb_agg(e.h - 'id' - 'boarder_pct' order by e.o), '[]'::jsonb) from jsonb_array_elements(coalesce(b.sheet -> 'b', '[]'::jsonb)) with ordinality e(h, o))),$h$),
  ('public.fight_card(uuid,uuid)', 1,
$h$                'nation', x.nation, 'ships', x.ships, 'here', x.here)$h$,
$h$                'nation', x.nation, 'ships', x.ships, 'lv', x.lv, 'here', x.here)   -- 0450: lv, her fleet's best level$h$),
  ('public.fight_card(uuid,uuid)', 2,
$h$                    (select count(*) from public.ships sh where sh.fleet_id = f.id)::int as ships,$h$,
$h$                    (select count(*) from public.ships sh where sh.fleet_id = f.id)::int as ships,
                    (select coalesce(max(public.ship_level(sh.id)), 1) from public.ships sh where sh.fleet_id = f.id)::int as lv,   -- 0450$h$);

  for v_h in select h.fn from hunks_0450 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0450 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0450 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0450 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0450 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0450 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 5. SELF-ASSERT: the catalog, the grants, the knobs ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_new) u(q)))) <> v_fn_before then
    raise exception '0450 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0450 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked function moved';
  end if;
  if exists (select 1 from unnest(c_new) f
              where has_function_privilege('anon', f::regprocedure, 'execute') or has_function_privilege('authenticated', f::regprocedure, 'execute'))
     or exists (select 1 from unnest(c_new) f join public.client_rpc_entry_points() e on e.fn = f::regprocedure)
     or exists (select 1 from public.client_executable_writers()) then
    raise exception '0450 self-assert FAIL: a function of this file is open to clients';
  end if;
  if (select count(*) from public.world_config k
       where (k.key, k.value) in (('raid_flee_base', to_jsonb(0.10)), ('raid_flee_floor', to_jsonb(0.03)), ('raid_flee_max', to_jsonb(0.45)), ('flee_per_level', to_jsonb(0.03)),
                                  ('flee_level_max', to_jsonb(0.15)), ('flee_hurt_under', to_jsonb(0.5)), ('flee_hurt_max', to_jsonb(0.20)), ('flee_per_try', to_jsonb(0.05)))) <> 8 then
    raise exception '0450 self-assert FAIL: the knobs are not this file''s';
  end if;

  -- ── 6. THE ENGINE on the fixed sheet ──
  -- (a) UNDER THE NEW KNOBS: the chance at tick 0 (nobody hurt yet, nobody caught yet) is the formula's, term by term
  v_f1 := public.tick_fight(c_seed, v_ha, v_hb, v_opts);
  v_p0 := (v_f1 #>> '{rc,a,0,1}')::numeric;
  if (v_f1 #>> '{rc,a,0,0}')::int <> 0 or v_p0 <> 25 then
    raise exception '0450 self-assert FAIL: level with her foe and whole, she would run on % %% at tick %, not base 10 + bonus 15 = 25', v_p0, v_f1 #>> '{rc,a,0,0}';
  end if;
  v_p1 := (public.tick_fight(c_seed, jsonb_set(v_ha, '{0,lv}', '5'), v_hb, v_opts) #>> '{rc,a,0,1}')::numeric;
  if v_p1 <> 31 then
    raise exception '0450 self-assert FAIL: two levels ahead she would run on % %%, not 31', v_p1;
  end if;
  v_p1 := (public.tick_fight(c_seed, v_ha, jsonb_set(v_hb, '{0,lv}', '5'), v_opts) #>> '{rc,a,0,1}')::numeric;
  if v_p1 <> 19 then
    raise exception '0450 self-assert FAIL: two levels behind she would run on % %%, not 19', v_p1;
  end if;
  v_p1 := (public.tick_fight(c_seed, jsonb_set(v_ha, '{0,lv}', '20'), v_hb, v_opts) #>> '{rc,a,0,1}')::numeric;
  if v_p1 <> 40 then
    raise exception '0450 self-assert FAIL: seventeen levels ahead she would run on % %%, not 25 + the most 15 = 40', v_p1;
  end if;
  v_p1 := (public.tick_fight(c_seed, jsonb_set(v_ha, '{0,hull}', '150'), v_hb, v_opts) #>> '{rc,a,0,1}')::numeric;
  if v_p1 <> 15 then
    raise exception '0450 self-assert FAIL: at a quarter of her hull she would run on % %%, not 25 - 20 x (1 - 0.25 / 0.5) = 15', v_p1;
  end if;
  v_p1 := (public.tick_fight(c_seed, jsonb_set(v_ha, '{0,crew}', '3'), v_hb, v_opts) #>> '{rc,a,0,1}')::numeric;
  if v_p1 <> 15 then
    raise exception '0450 self-assert FAIL: with a quarter of the crew she needs she would run on % %%, not 15', v_p1;
  end if;
  if (public.tick_fight(c_seed, v_ha, v_hb, v_opts || '{"a_flee": 5}'::jsonb) #>> '{rc,a,0,1}')::numeric <> 45
     or (public.tick_fight(c_seed, v_ha, v_hb, v_opts || '{"a_flee": -5}'::jsonb) #>> '{rc,a,0,1}')::numeric <> 3 then
    raise exception '0450 self-assert FAIL: a raid''s run is not held between its floor 3 %% and its cap 45 %%';
  end if;
  -- every roll is the chance served for its tick, within the floor and the cap; a roll after a failed one is at least flee_per_try lower, or at the floor
  for x in select (e ->> 0)::int as t, (e ->> 3)::numeric as pct, (e ->> 4)::int as away
             from jsonb_array_elements(v_f1 -> 'e') with ordinality q(e, o) where e ->> 2 = 'X' and e ->> 1 = '0' order by o loop
    v_rolls := v_rolls + 1;
    if x.pct < 3 or x.pct > 45
       or x.pct is distinct from (select (c ->> 1)::numeric from jsonb_array_elements(v_f1 #> '{rc,a}') with ordinality r(c, o) where (c ->> 0)::int <= x.t order by o desc limit 1) then
      raise exception '0450 self-assert FAIL: the roll at tick % was on % %%, not the chance served for that tick within 3..45', x.t, x.pct;
    end if;
    if v_prev is not null and not (x.pct <= v_prev - 5 or x.pct = 3) then
      raise exception '0450 self-assert FAIL: after a failed roll on % %% the next was on % %%, not at least 5 points lower', v_prev, x.pct;
    end if;
    v_prev := x.pct;
  end loop;
  if v_rolls < 1 then
    raise exception '0450 self-assert FAIL: the ship that runs never rolled on the fixed sheet';
  end if;
  if exists (select 1 from jsonb_array_elements(v_f1 -> 'a') s where not (s ? 'lv')) or (v_f1 #>> '{a,0,lv}')::int <> 3 then
    raise exception '0450 self-assert FAIL: the timeline''s ships do not carry their level';
  end if;
  -- (b) UNDER THE OLD KNOBS (the rollback), rolled back: every event is the event it was before this file
  begin
    update public.world_config set value = to_jsonb(0.10) where key = 'raid_flee_floor';
    update public.world_config set value = to_jsonb(0.80) where key = 'raid_flee_max';
    update public.world_config set value = to_jsonb(0.15) where key = 'raid_flee_base';
    update public.world_config set value = to_jsonb(0) where key in ('flee_per_level', 'flee_hurt_max', 'flee_per_try');
    v_f2 := public.tick_fight(c_seed, v_ha, v_hb, v_opts);
    if (v_f2 -> 'e')::text <> (v_f0 -> 'e')::text or (v_f2 -> 'r')::text <> (v_f0 -> 'r')::text then
      raise exception '0450 self-assert FAIL: under the old knobs the fixed fight is not the fight it was before this file';
    end if;
    raise exception sqlstate 'BV450';
  exception when sqlstate 'BV450' then null;
  end;

  -- ── 7. THE NEWS (0347's law) ──
  perform public.news_update('0450', 'A battle shows each ship''s level, crew, guns and gear; running from a fight is harder',
                             '전투 화면에 각 배의 레벨, 선원, 포, 장비가 보인다; 전투에서 도주하기가 어려워졌다');

  -- ── 8. THE PROBE, rolled back by a raised sentinel: a RAID sheet between two ships of the world ──
  begin
    select f.id into v_m1 from public.fleets f where public.fleet_kind(f.id) = 'MERCHANT' and exists (select 1 from public.ships s where s.fleet_id = f.id and s.durability > 0) order by f.id limit 1;
    select f.id into v_m2 from public.fleets f where public.fleet_kind(f.id) = 'MERCHANT' and f.id <> v_m1 and f.player_id is distinct from (select g.player_id from public.fleets g where g.id = v_m1)
                                                 and exists (select 1 from public.ships s where s.fleet_id = f.id and s.durability > 0) order by f.id limit 1;
    if v_m2 is not null then
      insert into public.battles (kind, site, started_at, resolves_at, status, sheet, round_seconds, rounds_done, next_round_at)
      values ('RAID', '{"lat": 0, "lon": 0}'::jsonb, now(), now() + interval '600 seconds', 'FIGHTING',
              jsonb_build_object('a', voyage.fleet_hulls(v_m1), 'b', voyage.fleet_hulls(v_m2), 'foe', 'probe a', 'you', 'probe b', 'a_flee', 0.05), 85, 0, now() + interval '85 seconds')
      returning id into v_bat;
      insert into public.battle_sides (battle_id, fleet_id, side, joined_at, arrives_at) values (v_bat, v_m2, 'ATTACKER', now(), now()), (v_bat, v_m1, 'DEFENDER', now(), now());
      v_f1 := public.tick_battle_run(v_bat);   -- its own statement: the row it writes is read by the next one
      select b.sheet into v_sheet from public.battles b where b.id = v_bat;
      if exists (select 1 from jsonb_array_elements((v_sheet -> 'a') || (v_sheet -> 'b')) h
                  where not (h ?& array['lv', 'cls', 'guns', 'crew_need', 'crew_max', 'speed', 'handling', 'fit', 'caps'])
                     or (h ->> 'lv')::int < 1 or (h ->> 'crew_max')::numeric < (h ->> 'crew_need')::numeric or jsonb_typeof(h -> 'fit') <> 'array') then
        raise exception '0450 self-assert FAIL: a hull of the probe''s sheet has no card: %', v_sheet -> 'a' -> 0;
      end if;
      v_card := v_sheet -> 'a' -> 0;
      if (v_card ->> 'lv')::int <> public.ship_level((v_card ->> 'id')::uuid)
         or (v_card ->> 'cls') is distinct from (select c.name from public.ships s join public.ship_classes c on c.id = s.class_id where s.id = (v_card ->> 'id')::uuid)
         or jsonb_array_length(v_card -> 'fit') <> (select count(*) from public.fitted_units fu where fu.ship_id = (v_card ->> 'id')::uuid) then
        raise exception '0450 self-assert FAIL: the card is not her level, her class and what she has fitted: %', v_card;
      end if;
      if (v_f1 #>> '{a,0,lv}')::int <> (v_card ->> 'lv')::int or jsonb_typeof(v_f1 #> '{rc,a}') <> 'array' then
        raise exception '0450 self-assert FAIL: the timeline does not carry her level or the run''s chance';
      end if;
      -- frozen: she is worked up, and a second run reads the sheet, not the ship
      insert into public.ship_xp (ship_id, xp) values ((v_card ->> 'id')::uuid, 1000000) on conflict (ship_id) do update set xp = excluded.xp;
      v_f2 := public.tick_battle_run(v_bat);
      if (select b.sheet from public.battles b where b.id = v_bat)::text <> v_sheet::text or (v_f2 -> 'e')::text <> (v_f1 -> 'e')::text then
        raise exception '0450 self-assert FAIL: a second run moved the sheet or the fight';
      end if;
      if exists (select 1 from jsonb_array_elements(public.fight_card(v_bat, null) -> 'sides') sd where not (sd ? 'lv') or (sd ->> 'lv')::int < 1) then
        raise exception '0450 self-assert FAIL: the map''s card does not say each side''s level: %', public.fight_card(v_bat, null) -> 'sides';
      end if;
      v_note := format('a raid between two ships of the world: %s Lv %s (%s, crew %s/%s, %s fitted) against %s Lv %s; she would run on %s %% at the open; a second run moved nothing (rolled back)',
                       v_card ->> 'name', v_card ->> 'lv', v_card ->> 'cls', v_card ->> 'crew', v_card ->> 'crew_max', jsonb_array_length(v_card -> 'fit'),
                       v_sheet #>> '{b,0,name}', v_sheet #>> '{b,0,lv}', coalesce(v_f1 #>> '{rc,a,0,1}', '-'));
    end if;
    raise exception sqlstate 'BV450';
  exception when sqlstate 'BV450' then null;
  end;
  if v_note = '' then
    raise exception '0450 self-assert FAIL: the probe found no two ships of the world';
  end if;
  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0450 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0450 self-assert ok: A FIGHT SHOWS ITS SHIPS, AND ESCAPING IS HARD. % hunks once each and reversing; grants and volatility unmoved; no other function moved; 2 new functions, server-only; the fixed sheet: a run on 25 %%, 31 two levels ahead, 19 two behind, 40 at the most, 15 crippled, 15 short-handed, 3..45, % roll(s) each lower than the last; under the old knobs the fight it was. Probe: %; % ms.',
    (select count(*) from hunks_0450), v_rolls, v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0450;
end $m$;
