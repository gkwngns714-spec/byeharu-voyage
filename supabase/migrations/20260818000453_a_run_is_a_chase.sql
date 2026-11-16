-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0453 - A RUN IS A CHASE  (a new level, Evasion / 회피, raised by running from a pirate's raid; a run's chance is her ship against theirs:
--        speed, handling, hull, hands and Evasion, hers over theirs)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-16: "number 5 needs a new skill, related to combat - evasion or something, like parley or speech or whatever. This skill
--   will increase your chance of running away along with speed level (or agility, you get the idea). Of course the success of evasion depends on
--   both myself and the other ships condition, it has to be relative." The design: docs/design/evasion-skill.md (written for 0452; 0452 is the
--   escort refit's, #752, which touches only public.npc_ladder_refit, so this file is 0453 and deploys after it).
--
-- WHAT IS THERE (read on the chain at 0451; the four live bodies read on prod at head 0451, 2026-11-16, byte-equal to the chain's):
--   THE RUN    public.tick_fight, 0450's one formula each tick: base + sighting lead + a raid's a_flee + 3 points a level ahead - up to 20 points
--     crippled or short-handed - 5 points a failed attempt, within a raid's 3..45 % (any other run 0357's 5..30 %). a_flee's speed term reads
--     voyage.fleet_speed, which counts a pirate 4.5 times as fast (0422): it sits on its floor for every runner, so a faster ship buys nothing.
--   THE LEVELS ten company levels (0411): public.level_skills, public.level_activities, public.level_grant (the one writer), public.level_perks
--     (0417, what a level gives; public.level_perk the one reading). No level is raised by a fight tick by tick.
-- WHAT THIS FILE DOES:
--   S1. THE LEVEL. Evasion, code `evasion`, the eleventh of public.level_skills, kept 'book', 300 a day, 1..20 on the one curve. Raised only as the
--       side set upon in a pirate's RAID that runs: `run_away` 40 for the run that got her away, `run_try` 5 for each roll of her run that failed,
--       once a battle (public.raid_close, inside its players-only block; the keys run_away:<battle>, run_try:<battle>). A merchant earns nothing.
--       It gives perk `run`, 10 % a level above 1 (19 steps of public.level_perks). public.level_perk_at (new) is the one sum of a perk's steps at
--       a level; public.level_perk reads a company's level into it (one hunk).
--   S2. THE CARD. public.evasion_of (new): `ev` the Evasion level a hull sails with (a company's ship: her company's; a ship of the world: her
--       hull's level, public.ship_level) and `run` what it is worth (per cent). public.battle_hull_card adds it (one hunk), so the sheet freezes it
--       at the open and world.battle_ticks serves it.
--   S3. THE CHASE (public.tick_fight, four hunks, behind the switch chase_enabled). ONE rule for every run, each tick, as the fight stands:
--         sailing(hull) = speed x (hull_speed_floor + (1 - hull_speed_floor) x hull left / her size) x (crew_short_speed_mult when short-handed)
--                           x (1 + chase_per_handling x handling / 100)
--         her sailing = the least among her hulls afloat that began the fight; theirs = the most among their hulls afloat that are up
--         skill = 1 + the best `run` among a side's hulls that are up / 100
--         chance = clamp(chase_floor, chase_base x (her sailing x her skill / (their sailing x their skill)) ^ chase_power - failed attempts x flee_per_try, chase_cap)
--       Equal sides 15 % a roll; floor 1 %, cap 50 %. The roll, `rc`, the `X` event and the failed-attempt count read f_p[s] as before.
--       chase_enabled false: 0450's chance, to the digit (asserted below; proof 152 proves that rule from now on).
--   KNOBS (new): chase_enabled true, chase_base 0.15, chase_power 2, chase_floor 0.01, chase_cap 0.50, chase_per_handling 0.5. Read, not moved:
--     hull_speed_floor 0.60, crew_short_speed_mult 0.70 (the sailing rule's own), flee_per_try 0.05.
-- NOT TOUCHED: public.fight_sides (the round engine; a voyage day's raid is still rolled there by 0357's rule), public.flee_bonus and sheet.a_flee
--   (the old rule's), public.battle_sheet_freeze, public.tick_battle_run, world.battle_ticks, public.level_grant, world.levels (it serves every row).
-- LOAD: -- budget: no table, no job, no cron, no index. Rows: at most 2 level_book rows and 1 level_xp row at the close of a RAID on a PLAYER'S ship
--   (public.level_grant), none for a ship of the world: under 1 row a minute at ~50 raids an hour (prod, 48 h to 2026-11-16: 2,339 raids, none on a
--   player's ship). A level crossed is one event and one Reputation row, 19 times ever a company. The sheet carries ~20 bytes more a hull (`ev`,
--   `run`); the timeline nothing more. The engine: one more loop over the hulls a tick, eight knobs read once a fight. At a battle's open: one more
--   indexed read a hull (players, level_xp or ship_xp, level_perks).
-- RETENTION: -- retention: none new. public.level_book is 0411's (append-only, bounded by the level's cap a day); the card lives and dies with its battle row.
-- LOCKS: CREATE OR REPLACE x4 by hunks; CREATE FUNCTION x2; rows of level_skills (1), level_activities (2), level_perks (19), world_config (6).
--   BUDGET: statement_timeout 45 s, lock_timeout 5 s; fails above 30 s.
-- ROLLBACK (forward, owner only): QUICK, chase_enabled false (every new roll and every re-run is 0450's chance to the digit; the level and what was
--   earned stay). WHOLE: scripts/ops/harness/evasion/rollback-0453.sql (a draft).
-- IN FLIGHT AT THE DEPLOY: a battle being fought keeps its timeline; a re-run by a join or a press (within its ~75 s) is under the new rule from
--   tick 0, with cards that have no `run`: both skills read 1 and the ships alone decide.
-- SELF-ASSERT: every hunk once and reversing; grants, volatility, definer, search path, owner of the four bodies unmoved; no other function moved;
--   the new functions server-only; the rows and knobs this file's; THE ENGINE on fixed sheets: chase_enabled false is the fight as it was before
--   the hunks; lit, equal sides 15, skill 40 against 0 29, 0 against 40 8, 190 against 40 the cap 50, half her hull 10, short-handed 7, a 13.2/45
--   ship against a 19.5/94 one 5, both sides twice as fast 15, no speed the floor 1; every roll is the chance served for its tick and each after a
--   failed one 5 lower or the floor; THE PROBE, rolled back: public.level_perk is the steps' sum at every level of every perk; public.evasion_of;
--   the sailing rule's two factors are voyage.ship_speed_at's; a pirate's RAID on a company's ship through public.battle_open and
--   public.battle_resolve: the cards carry ev and run, frozen; the book holds run_try x her failed rolls and run_away when she fled, once; a
--   second close grants nothing; a merchant set upon: no level row.
-- VERSION: 0453 (prod head 0452 at 01:36 UTC 2026-11-16: #752's escort refit, public.npc_ladder_refit only, which none of these bodies call).
--   Written on the chain to 0451; its seven old texts read once each on prod at head 0451 and again at head 0452.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array[
    'public.tick_fight(uuid,jsonb,jsonb,jsonb)', 'public.battle_hull_card(uuid)', 'public.raid_close(uuid,jsonb,timestamptz)', 'public.level_perk(uuid,text)'];
  c_new constant text[] := array['public.level_perk_at(text,integer)', 'public.evasion_of(uuid)'];
  c_seed constant uuid := '00000000-0453-4000-8000-0000000000aa';
  v_t0        timestamptz := clock_timestamp();
  v_h         record;
  x           record;
  r           record;
  v_def       text;
  v_pre       text;
  v_n         int;
  v_fn_before text;
  v_meta      text;
  v_ha        jsonb;
  v_hb        jsonb;
  v_ta        jsonb;
  v_tb        jsonb;
  v_opts      jsonb := '{"a_ai": "FLEE", "a_flee": 0.15}'::jsonb;
  v_f0        jsonb[];
  v_f1        jsonb;
  v_f2        jsonb;
  v_p         numeric;
  v_prev      numeric;
  v_rolls     int := 0;
  v_want      numeric;
  v_got       numeric;
  v_nat       uuid;
  v_port      uuid;
  v_me        uuid;
  v_mep       uuid;
  v_ms        uuid;
  v_pir       uuid;
  v_pirp      uuid;
  v_mer       uuid;
  v_merp      uuid;
  v_sh        uuid;
  v_bat       uuid;
  v_b         public.battles%rowtype;
  v_sheet     jsonb;
  v_card      jsonb;
  v_failed    int;
  v_fled      boolean;
  v_book      int;
  v_raids     int := 0;
  v_ran       int := 0;
  v_note      text := '';
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config where key = 'chase_enabled') then
    raise exception '0453 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.battle_hull_card(uuid)') is null or to_regprocedure('public.level_perk(uuid,text)') is null
     or not exists (select 1 from public.world_config where key = 'flee_per_try') then
    raise exception '0453 refuses: 0417 (what a level gives) or 0450 (a fight shows its ships) is not in this world';
  end if;
  if exists (select 1 from public.level_skills where ord = 11 or code = 'evasion') then
    raise exception '0453 refuses: public.level_skills already holds an eleventh level';
  end if;

  -- ── 1. THE PRE-IMAGE ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  -- fixed sheets with every key a card carries now and the two this file adds, fought BEFORE any hunk: the fights as they were
  --   (1) 0450's: a merchant that runs from a raider she cannot outgun (a raid's side set upon, with a_flee)
  --   (2) the same, the runner hurt and short-handed, against two pursuers, one hurt
  --   (3) the side that closed runs (no a_flee: 0357's base, floor and cap)
  v_ha := jsonb_build_array(jsonb_build_object('id', '00000000-0453-4000-8000-000000000001', 'name', 'a1', 'tier', 2, 'hull', 600, 'maxd', 600, 'crew', 12, 'crew_need', 12,
            'attack', 10, 'accuracy', 40, 'reach', 20, 'armour', 10, 'sighting', 8, 'boarder_pct', 0, 'lv', 3, 'speed', 18, 'handling', 75, 'ev', 3, 'run', 20));
  v_hb := jsonb_build_array(jsonb_build_object('id', '00000000-0453-4000-8000-000000000002', 'name', 'b1', 'tier', 2, 'hull', 5000, 'maxd', 5000, 'crew', 60, 'crew_need', 40,
            'attack', 30, 'accuracy', 50, 'reach', 22, 'armour', 12, 'sighting', 8, 'boarder_pct', 0.1, 'lv', 3, 'speed', 19.5, 'handling', 90, 'ev', 5, 'run', 40));
  v_f0 := array[
    public.tick_fight(c_seed, v_ha, v_hb, v_opts),
    public.tick_fight(c_seed, jsonb_set(jsonb_set(v_ha, '{0,hull}', '200'), '{0,crew}', '5'),
                      v_hb || jsonb_build_array((v_hb -> 0) || '{"id": "00000000-0453-4000-8000-000000000003", "name": "b2", "hull": 2000, "speed": 20.4, "handling": 92}'::jsonb), v_opts),
    public.tick_fight(c_seed, v_hb, v_ha, '{"a_ai": "FLEE"}'::jsonb)];

  -- ── 2. THE LEVEL, WHAT RAISES IT, WHAT IT GIVES; THE KNOBS ──
  insert into public.level_skills (code, ord, word, kept, day_cap) values ('evasion', 11, 'Evasion', 'book', 300);
  insert into public.level_activities (code, skill, ord, word, unit, xp, per, xp_knob, per_knob, most_xp, once, at_gain, voyage_nm) values
    ('run_away', 'evasion', 1, 'A pirate raid escaped by running',     'each', 40, 1, null, null, null, false, false, null),
    ('run_try',  'evasion', 2, 'A run from a pirate raid that failed', 'each', 5,  1, null, null, null, false, false, null);
  insert into public.level_perks (perk, level, skill, unit, amount, word)
  select 'run', g, 'evasion', 'pct_more', 10, 'Runs better' from generate_series(2, 20) g;
  insert into public.world_config (key, value, description) values
    ('chase_enabled', 'true'::jsonb, '0453: THE SWITCH of the chase. true: a run''s chance is her sailing and Evasion against theirs (public.tick_fight). false: 0450''s chance, to the digit (the rollback).'),
    ('chase_base', to_jsonb(0.15), '0453: a run''s chance between equal sides (the same sailing, the same Evasion): the one dial for harder or softer.'),
    ('chase_power', to_jsonb(2), '0453: how sharply a better or worse ratio of sailing x Evasion counts: the chance is chase_base x the ratio to this power.'),
    ('chase_floor', to_jsonb(0.01), '0453: the least chance a run rolls (a ship that cannot sail, or far slower than her pursuer).'),
    ('chase_cap', to_jsonb(0.50), '0453: the most chance a run rolls.'),
    ('chase_per_handling', to_jsonb(0.5), '0453: what a ship''s handling adds to her sailing in a chase: 1 + this x handling / 100 (handling 100 = +50 %).');

  -- ── 3. THE NEW FUNCTIONS ──
  execute $f$
create function public.level_perk_at(p_perk text, p_level int)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0453: WHAT A BENEFIT'S STEPS ARE WORTH AT A LEVEL (public.level_perks: the sum of the steps at or below it). 0 while level_perks_on is false.
  -- public.level_perk reads a company's level into it; public.evasion_of reads a hull's.
  select case when public.wc('level_perks_on') = 'true'::jsonb
              then coalesce((select sum(k.amount) from public.level_perks k where k.perk = p_perk and k.level <= p_level), 0)
              else 0 end
$body$;
$f$;

  execute $f$
create function public.evasion_of(p_ship uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0453: THE EVASION A HULL SAILS WITH, the one reading for a battle's sheet (public.battle_hull_card): ev the level, run what it is worth in a chase,
  -- per cent (public.level_perk_at 'run'). A company's ship: her company's Evasion level (public.level_xp on the one curve; 1 with no experience).
  -- A ship of the world (players.is_npc): her own hull's level (public.ship_level: a merchant 1 to 5 as founded, a crown's or a pirate's npc_ship_level),
  -- since the world's houses earn no experience (0411). No such ship: nothing.
  select coalesce((
    select jsonb_build_object('ev', z.ev, 'run', public.level_perk_at('run', z.ev))
      from (select case when p.is_npc then public.ship_level(s.id)
                        else coalesce((select public.level_from_points(x.xp) from public.level_xp x where x.player_id = s.player_id and x.skill = 'evasion'), 1) end as ev
              from public.ships s join public.players p on p.id = s.player_id where s.id = p_ship) z), '{}'::jsonb)
$body$;
$f$;

  revoke all on function public.level_perk_at(text, int) from public, anon, authenticated;
  revoke all on function public.evasion_of(uuid) from public, anon, authenticated;

  -- ── 4. THE HUNKS (each occurs exactly once in the live body, and reverses) ──
  create temp table hunks_0453 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0453 values
  ('public.tick_fight(uuid,jsonb,jsonb,jsonb)', 1,
$h$  c_ptry   numeric := coalesce(public.wc_num('flee_per_try'), 0);
begin$h$,
$h$  c_ptry   numeric := coalesce(public.wc_num('flee_per_try'), 0);
  -- 0453: THE CHASE. Each hull's speed and handling and what her Evasion level is worth (her card); each side's sailing as the fight stands; the knobs, once a fight.
  h_spd    numeric[] := '{}';
  h_hdl    numeric[] := '{}';
  h_run    numeric[] := '{}';
  f_slow   numeric[];
  f_fast   numeric[];
  f_skill  numeric[];
  f_one    numeric;
  c_chase  boolean := coalesce(public.wc('chase_enabled') = 'true'::jsonb, false);
  c_cbase  numeric := public.wc_num('chase_base');
  c_cpow   numeric := public.wc_num('chase_power');
  c_cfloor numeric := public.wc_num('chase_floor');
  c_ccap   numeric := public.wc_num('chase_cap');
  c_chdl   numeric := public.wc_num('chase_per_handling');
  c_hsf    numeric := public.wc_num('hull_speed_floor');
  c_csm    numeric := public.wc_num('crew_short_speed_mult');
begin$h$),
  ('public.tick_fight(uuid,jsonb,jsonb,jsonb)', 2,
$h$      h_need[n]  := greatest(0, coalesce((x ->> 'crew_need')::numeric, 0));   -- 0450: the crew her class needs (none on the sheet: her crew is never short)
$h$,
$h$      h_need[n]  := greatest(0, coalesce((x ->> 'crew_need')::numeric, 0));   -- 0450: the crew her class needs (none on the sheet: her crew is never short)
      h_spd[n]   := greatest(0, coalesce((x ->> 'speed')::numeric, 0));       -- 0453: her speed and handling (her card, 0450), and what her Evasion level is worth, per cent (her card's run)
      h_hdl[n]   := greatest(0, coalesce((x ->> 'handling')::numeric, 0));
      h_run[n]   := greatest(0, coalesce((x ->> 'run')::numeric, 0));
$h$),
  ('public.tick_fight(uuid,jsonb,jsonb,jsonb)', 3,
$h$      f_lv := array[1, 1];
      for i in 1 .. n loop
        if h_up[i] then f_lv[h_side[i]] := greatest(f_lv[h_side[i]], h_lvl[i]); end if;
      end loop;
$h$,
$h$      f_lv := array[1, 1];
      for i in 1 .. n loop
        if h_up[i] then f_lv[h_side[i]] := greatest(f_lv[h_side[i]], h_lvl[i]); end if;
      end loop;
      -- 0453: EACH SIDE'S SAILING, as the fight stands. A hull afloat sails at her speed x what her hull leaves of it (hull_speed_floor, the sailing rule's own knob) x
      -- crew_short_speed_mult when she is short-handed x (1 + chase_per_handling x her handling / 100). To RUN a side sails as her slowest hull that began the fight;
      -- to CHASE, as her fastest hull that is up. Her skill is the best Evasion benefit among her hulls that are up.
      f_slow := array[null, null]::numeric[]; f_fast := array[0, 0]::numeric[]; f_skill := array[0, 0]::numeric[];
      for i in 1 .. n loop
        continue when not h_up[i];
        f_skill[h_side[i]] := greatest(f_skill[h_side[i]], h_run[i]);
        continue when h_hull[i] <= 0;
        f_one := h_spd[i] * (c_hsf + (1 - c_hsf) * least(1, h_hull[i] / h_maxd[i])) * case when h_crew[i] < h_need[i] then c_csm else 1 end * (1 + c_chdl * h_hdl[i] / 100);
        f_fast[h_side[i]] := greatest(f_fast[h_side[i]], f_one);
        if h_from[i] = 0 then f_slow[h_side[i]] := least(coalesce(f_slow[h_side[i]], f_one), f_one); end if;
      end loop;
$h$),
  ('public.tick_fight(uuid,jsonb,jsonb,jsonb)', 4,
$h$        f_p[s] := case when s = 1 and p_opts ? 'a_flee' then least(c_rmax, greatest(c_rfloor, v_p)) else least(c_emax, greatest(c_ffloor, v_p)) end;
$h$,
$h$        f_p[s] := case when s = 1 and p_opts ? 'a_flee' then least(c_rmax, greatest(c_rfloor, v_p)) else least(c_emax, greatest(c_ffloor, v_p)) end;
        -- 0453: THE CHASE (chase_enabled; false: the chance above, 0450's, to the digit). ONE rule for every run:
        --   chance = clamp(chase_floor, chase_base x (her sailing x (1 + her skill %) / (their sailing x (1 + their skill %))) ^ chase_power - failed attempts x flee_per_try, chase_cap)
        -- A side with no hull afloat that began (or no speed on her sheet) cannot run: the floor. Nobody afloat to chase her: the cap.
        if c_chase then
          f_p[s] := case when coalesce(f_slow[s], 0) <= 0 then c_cfloor
                         when f_fast[o] <= 0 then c_ccap
                         else least(c_ccap, greatest(c_cfloor,
                                c_cbase * power((f_slow[s] * (1 + f_skill[s] / 100)) / (f_fast[o] * (1 + f_skill[o] / 100)), c_cpow) - s_try[s] * c_ptry)) end;
        end if;
$h$),
  ('public.battle_hull_card(uuid)', 1,
$h$                       where cs.ship_id = s.id))
$h$,
$h$                       where cs.ship_id = s.id))
           || public.evasion_of(s.id)   -- 0453: `ev` her Evasion level, `run` what it is worth in a chase (per cent)
$h$),
  ('public.raid_close(uuid,jsonb,timestamptz)', 1,
$h$  if v_human then
    v_line := case when v_out = 'NO_FIGHT' then 'Pirates came up, and there was no fight.'
$h$,
$h$  if v_human then
    -- 0453: EVASION, raised by doing (public.level_grant; a merchant never comes here): each roll of her run that failed, and the run that got her away,
    -- once a battle. The rolls are the result's own: a window (a round) she ran in carries `flee`.
    perform public.level_grant(v_dp, 'run_try', (select count(*) from jsonb_array_elements(coalesce(p_fight -> 'rounds', '[]'::jsonb)) r where r ? 'flee')
                                                - case when coalesce((p_fight ->> 'fled')::boolean, false) then 1 else 0 end, 'run_try:' || p_battle);
    perform public.level_grant(v_dp, 'run_away', case when coalesce((p_fight ->> 'fled')::boolean, false) then 1 else 0 end, 'run_away:' || p_battle);
    v_line := case when v_out = 'NO_FIGHT' then 'Pirates came up, and there was no fight.'
$h$),
  ('public.level_perk(uuid,text)', 1,
$h$  return coalesce((select sum(k.amount) from public.level_perks k
                    where k.perk = p_perk and k.level <= public.level_from_points(v_xp)), 0);
$h$,
$h$  return public.level_perk_at(p_perk, public.level_from_points(v_xp));   -- 0453: the one sum of a benefit's steps at a level
$h$);

  for v_h in select h.fn from hunks_0453 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0453 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0453 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0453 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0453 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0453 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 5. SELF-ASSERT: the catalog, the grants, the rows and the knobs ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_new) u(q)))) <> v_fn_before then
    raise exception '0453 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0453 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked function moved';
  end if;
  if exists (select 1 from unnest(c_new) f
              where has_function_privilege('anon', f::regprocedure, 'execute') or has_function_privilege('authenticated', f::regprocedure, 'execute'))
     or exists (select 1 from unnest(c_new) f join public.client_rpc_entry_points() e on e.fn = f::regprocedure)
     or exists (select 1 from public.client_executable_writers())
     or exists (select 1 from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_new) u(q))) and (p.provolatile <> 's' or not p.prosecdef)) then
    raise exception '0453 self-assert FAIL: a function of this file is open to clients, or is not stable and definer';
  end if;
  if (select count(*) from public.world_config k
       where (k.key, k.value) in (('chase_enabled', 'true'::jsonb), ('chase_base', to_jsonb(0.15)), ('chase_power', to_jsonb(2)), ('chase_floor', to_jsonb(0.01)),
                                  ('chase_cap', to_jsonb(0.50)), ('chase_per_handling', to_jsonb(0.5)))) <> 6
     or (select count(*) from public.level_perks k where k.perk = 'run' and k.skill = 'evasion' and k.amount = 10 and k.unit = 'pct_more') <> 19
     or (select count(*) from public.level_activities a where a.skill = 'evasion') <> 2
     or (select count(*) from public.level_activity_terms() t where t.code in ('run_away', 'run_try')) <> 2
     or (select s.ord from public.level_skills s where s.code = 'evasion') <> (select max(s.ord) from public.level_skills s) then
    raise exception '0453 self-assert FAIL: the rows and the knobs are not this file''s';
  end if;

  -- ── 6. THE ENGINE ──
  -- (a) THE SWITCH OFF IS THE FIGHT AS IT WAS (rolled back): every event, the result and the chances served, as fought before the hunks
  begin
    update public.world_config set value = 'false'::jsonb where key = 'chase_enabled';
    for v_n in 1 .. 3 loop
      v_f2 := case v_n
                when 1 then public.tick_fight(c_seed, v_ha, v_hb, v_opts)
                when 2 then public.tick_fight(c_seed, jsonb_set(jsonb_set(v_ha, '{0,hull}', '200'), '{0,crew}', '5'),
                                              v_hb || jsonb_build_array((v_hb -> 0) || '{"id": "00000000-0453-4000-8000-000000000003", "name": "b2", "hull": 2000, "speed": 20.4, "handling": 92}'::jsonb), v_opts)
                else public.tick_fight(c_seed, v_hb, v_ha, '{"a_ai": "FLEE"}'::jsonb) end;
      if (v_f2 -> 'e')::text <> (v_f0[v_n] -> 'e')::text or (v_f2 -> 'r')::text <> (v_f0[v_n] -> 'r')::text or (v_f2 -> 'rc')::text <> (v_f0[v_n] -> 'rc')::text then
        raise exception '0453 self-assert FAIL: with chase_enabled false fixed fight % is not the fight it was before this file', v_n;
      end if;
    end loop;
    raise exception sqlstate 'BV453';
  exception when sqlstate 'BV453' then null;
  end;
  if (public.tick_fight(c_seed, v_ha, v_hb, v_opts) -> 'rc')::text = (v_f0[1] -> 'rc')::text then
    raise exception '0453 self-assert FAIL: lit, the chase served the chances 0450 served';
  end if;
  -- (b) LIT, THE CHASE ON A SHEET SO LARGE NOBODY IS HURT AT TICK 0: two hulls of speed 18 and handling 80, the chance at the open term by term
  v_ta := jsonb_build_array(jsonb_build_object('id', '00000000-0453-4000-8000-000000000011', 'name', 'Lebre', 'tier', 2, 'hull', 100000, 'maxd', 100000, 'crew', 40, 'crew_need', 40,
            'attack', 6, 'accuracy', 50, 'reach', 20, 'armour', 0, 'sighting', 8, 'boarder_pct', 0, 'lv', 3, 'speed', 18, 'handling', 80, 'run', 0));
  v_tb := jsonb_build_array(jsonb_build_object('id', '00000000-0453-4000-8000-000000000012', 'name', 'Lobo', 'tier', 2, 'hull', 100000, 'maxd', 100000, 'crew', 60, 'crew_need', 40,
            'attack', 6, 'accuracy', 50, 'reach', 20, 'armour', 0, 'sighting', 8, 'boarder_pct', 0, 'lv', 3, 'speed', 18, 'handling', 80, 'run', 0));
  for r in select * from (values
      (1, 'equal sides',                         v_ta, v_tb, 15),
      (2, 'her skill 40 against 0',              jsonb_set(v_ta, '{0,run}', '40'), v_tb, 29),
      (3, 'her skill 0 against 40',              v_ta, jsonb_set(v_tb, '{0,run}', '40'), 8),
      (4, 'her skill 190 against 40 (the cap)',  jsonb_set(v_ta, '{0,run}', '190'), jsonb_set(v_tb, '{0,run}', '40'), 50),
      (5, 'half her hull',                       jsonb_set(v_ta, '{0,hull}', '50000'), v_tb, 10),
      (6, 'short-handed',                        jsonb_set(v_ta, '{0,crew}', '39'), v_tb, 7),
      (7, 'a 13.2 / 45 ship against 19.5 / 94',  jsonb_set(jsonb_set(v_ta, '{0,speed}', '13.2'), '{0,handling}', '45'), jsonb_set(jsonb_set(v_tb, '{0,speed}', '19.5'), '{0,handling}', '94'), 5),
      (8, 'both sides twice as fast',            jsonb_set(v_ta, '{0,speed}', '36'), jsonb_set(v_tb, '{0,speed}', '36'), 15),
      (9, 'no speed on her sheet (the floor)',   jsonb_build_array((v_ta -> 0) - 'speed'), v_tb, 1),
      (10, 'a pursuer hurt to half (x 1.56)',    v_ta, jsonb_set(v_tb, '{0,hull}', '50000'), 23)) z(k, what, a, b, want) loop
    v_p := (public.tick_fight(c_seed, r.a, r.b, v_opts) #>> '{rc,a,0,1}')::numeric;
    if v_p is distinct from r.want then
      raise exception '0453 self-assert FAIL: % she would run on % %% at the open, not %', r.what, v_p, r.want;
    end if;
  end loop;
  -- every roll is the chance served for its tick, within the floor and the cap; a roll after a failed one is flee_per_try lower or at the floor.
  -- THE DICE ARE PINNED (rolled back): every draw of public.tick_fight is voyage.rng_raw(seed, stream, world_secret), and each world has its own
  -- secret. On prod's the first roll of this sheet (tick 20, 15 %) draws 0.0379 and she gets away at once (the deploy of 2026-11-16 02:32 failed so);
  -- on the chain's it draws 0.2704. Under this file's own secret the fight is the same on every world: five rolls, 15, 10, 5, 1, 1, every one caught.
  begin
    update public.world_config set value = to_jsonb('0453-fixed-dice-of-the-self-assert-of-a-run-is-a-chase-020000000'::text) where key = 'world_secret';
    if not found then
      raise exception '0453 self-assert FAIL: this world has no world_secret to pin';
    end if;
    v_f1 := public.tick_fight(c_seed, v_ta, v_tb, v_opts);
    for x in select (e ->> 0)::int as t, (e ->> 3)::numeric as pct
               from jsonb_array_elements(v_f1 -> 'e') with ordinality q(e, o) where e ->> 2 = 'X' and e ->> 1 = '0' order by o loop
      v_rolls := v_rolls + 1;
      if x.pct < 1 or x.pct > 50
         or x.pct is distinct from (select (c ->> 1)::numeric from jsonb_array_elements(v_f1 #> '{rc,a}') with ordinality z(c, o) where (c ->> 0)::int <= x.t order by o desc limit 1) then
        raise exception '0453 self-assert FAIL: the roll at tick % was on % %%, not the chance served for that tick within 1..50', x.t, x.pct;
      end if;
      if v_prev is not null and x.pct <> greatest(1, v_prev - 5) then
        raise exception '0453 self-assert FAIL: after a failed roll on % %% the next was on % %%, not 5 lower or the floor', v_prev, x.pct;
      end if;
      v_prev := x.pct;
    end loop;
    if v_rolls <> 5 or (select string_agg(e ->> 3, ',' order by o) from jsonb_array_elements(v_f1 -> 'e') with ordinality q(e, o) where e ->> 2 = 'X' and e ->> 1 = '0') <> '15,10,5,1,1' then
      raise exception '0453 self-assert FAIL: under the pinned dice the ship that runs rolled % time(s) (%), not five on 15, 10, 5, 1, 1', v_rolls,
        (select string_agg(e ->> 3, ',' order by o) from jsonb_array_elements(v_f1 -> 'e') with ordinality q(e, o) where e ->> 2 = 'X' and e ->> 1 = '0');
    end if;
    raise exception sqlstate 'BV453';
  exception when sqlstate 'BV453' then null;
  end;

  -- ── 7. THE NEWS (0347's law) ──
  perform public.news_update('0453', 'New level, Evasion: running from a fight now takes skill, speed and handling, yours against theirs',
                             '새 레벨 회피: 전투에서 도주는 이제 내 기술, 속도, 조종성을 상대와 견준다');

  -- ── 8. THE PROBE, rolled back by a raised sentinel ──
  begin
    update public.world_config set value = 'true'::jsonb where key in ('attack_enabled', 'pirates_bite', 'raid_orders_enabled', 'levels_bite', 'level_skills_on', 'level_perks_on') and value is distinct from 'true'::jsonb;
    update public.world_config set value = 'false'::jsonb where key = 'navy_enabled' and value is distinct from 'false'::jsonb;
    update public.world_config set value = '["RAID", "ATTACK"]'::jsonb where key = 'tick_fight_kinds';
    select n.id into v_nat from public.nations n where n.code = 'PRT';
    select p.id into v_port from public.ports p where p.code = 'LIS';
    -- the company, a merchant and a pirate, by the game's own hands (public.form_fleet, public.commission_ship)
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc) values ('00000000-0453-4000-8000-0000000000c1', 'Casa Fuga 0453', v_nat, 0, false) returning id into v_mep;
    v_me := public.form_fleet(v_mep, 'Fuga 0453', v_port);
    v_ms := public.commission_ship(v_mep, v_me, 'carlat', 'Fuga 0453', true, true);
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc) values (null, 'Casa Mercante 0453', v_nat, 0, true) returning id into v_merp;
    v_mer := public.form_fleet(v_merp, 'Mercante 0453', v_port);
    v_sh := public.commission_ship(v_merp, v_mer, 'carlat', 'Mercante 0453', true, true);
    insert into public.ship_xp (ship_id, xp) values (v_sh, public.level_points(2)) on conflict (ship_id) do update set xp = excluded.xp;
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc) values (null, 'Lobos 0453', public.pirate_nation(), 0, true) returning id into v_pirp;
    v_pir := public.form_fleet(v_pirp, 'Lobos 0453', v_port);
    v_sh := public.commission_ship(v_pirp, v_pir, 'xebec', 'Lobos 0453', true, true);
    insert into public.ship_xp (ship_id, xp) values (v_sh, public.level_points(5)) on conflict (ship_id) do update set xp = excluded.xp;
    insert into public.pirate_ships (fleet_id, player_id, ord, home_port, last_port)
    values (v_pir, v_pirp, 900000 + (select count(*) from public.pirate_ships), v_port, v_port);
    update public.ships s set durability = (select b.durability from public.ship_base(s.id) b), crew = (select c.crew_required from public.ship_classes c where c.id = s.class_id)
     where s.fleet_id in (v_me, v_mer, v_pir);

    -- public.level_perk after its hunk: the steps' sum at every level of every perk
    for r in select distinct k.perk, k.skill from public.level_perks k loop
      for v_n in 1 .. 20 loop
        insert into public.level_xp (player_id, skill, xp) values (v_mep, r.skill, public.level_points(v_n)::int) on conflict (player_id, skill) do update set xp = excluded.xp;
        if public.level_perk(v_mep, r.perk) <> (select coalesce(sum(k.amount), 0) from public.level_perks k where k.perk = r.perk and k.level <= v_n) then
          raise exception '0453 self-assert FAIL: public.level_perk(%) at level % is %, not the steps'' sum', r.perk, v_n, public.level_perk(v_mep, r.perk);
        end if;
      end loop;
    end loop;
    delete from public.level_xp lx where lx.player_id = v_mep;   -- this probe's own rows, written above, inside this rolled-back block

    -- public.evasion_of: a company with no Evasion 1; at Evasion 10 her level and its steps' sum; a merchant her hull's level; a pirate npc_ship_level's
    if public.evasion_of(v_ms) <> '{"ev": 1, "run": 0}'::jsonb then
      raise exception '0453 self-assert FAIL: a company with no Evasion sails with %', public.evasion_of(v_ms);
    end if;
    insert into public.level_book (player_id, skill, seq, activity, xp, xp_after, key) values (v_mep, 'evasion', 1, 'run_away', public.level_points(10)::int, public.level_points(10)::int, 'probe:0453');
    insert into public.level_xp (player_id, skill, xp, seq) values (v_mep, 'evasion', public.level_points(10)::int, 1);
    if public.evasion_of(v_ms) <> '{"ev": 10, "run": 90}'::jsonb
       or public.evasion_of((select s.id from public.ships s where s.fleet_id = v_mer)) <> '{"ev": 2, "run": 10}'::jsonb
       or (public.evasion_of((select s.id from public.ships s where s.fleet_id = v_pir)) ->> 'ev')::int <> public.ship_level((select s.id from public.ships s where s.fleet_id = v_pir))
       or public.evasion_of('00000000-0453-4000-8000-0000000000ff') <> '{}'::jsonb then
      raise exception '0453 self-assert FAIL: public.evasion_of is not her company''s level, a merchant''s hull level, a pirate''s: % / % / %', public.evasion_of(v_ms),
        public.evasion_of((select s.id from public.ships s where s.fleet_id = v_mer)), public.evasion_of((select s.id from public.ships s where s.fleet_id = v_pir));
    end if;

    -- the sailing rule's two factors are voyage.ship_speed_at's: her ship at a share of her hull and short-handed, with an empty hold
    update public.ships s set durability = floor((select b.durability from public.ship_base(s.id) b) * 0.55), crew = (select c.crew_required from public.ship_classes c where c.id = s.class_id) - 1
     where s.id = v_ms;
    v_card := (select h from jsonb_array_elements(voyage.fleet_hulls(v_me)) h where (h ->> 'id')::uuid = v_ms) || public.battle_hull_card(v_ms);
    v_want := (public.wc_num('hull_speed_floor') + (1 - public.wc_num('hull_speed_floor')) * least(1, (v_card ->> 'hull')::numeric / (v_card ->> 'maxd')::numeric))
              * case when (v_card ->> 'crew')::numeric < (v_card ->> 'crew_need')::numeric then public.wc_num('crew_short_speed_mult') else 1 end;
    v_got := voyage.ship_speed_at(v_ms, 0) / ((v_card ->> 'speed')::numeric * public.wc_num('wind_mult_v0'));
    if abs(v_got - v_want) > 0.001 or v_want >= 0.8 then
      raise exception '0453 self-assert FAIL: the chase''s sailing factor % is not voyage.ship_speed_at''s % for a ship at % of % hull, crew % of %', v_want, v_got,
        v_card ->> 'hull', v_card ->> 'maxd', v_card ->> 'crew', v_card ->> 'crew_need';
    end if;
    update public.ships s set durability = (select b.durability from public.ship_base(s.id) b), crew = (select c.crew_required from public.ship_classes c where c.id = s.class_id) where s.id = v_ms;

    -- A PIRATE'S RAID ON HER, through public.battle_open and public.battle_resolve; she has a FLEE standing order. Up to three raids, ten minutes apart.
    update public.fleets f set status = 'ANCHORED', port_id = null, lat = 36.5, lon = -12.0, busy_until = null, ready_at = null where f.id = v_me;
    insert into public.fleet_raid_orders (fleet_id, raid_order) values (v_me, 'FLEE') on conflict (fleet_id) do update set raid_order = excluded.raid_order;
    for v_n in 1 .. 3 loop
      v_bat := public.battle_open('RAID', v_pir, v_me, now() + make_interval(mins => v_n * 10));
      select b.* into v_b from public.battles b where b.id = v_bat;
      v_raids := v_raids + 1;
      v_sheet := v_b.sheet;
      v_card := (select h from jsonb_array_elements(v_sheet -> 'a') h where (h ->> 'id')::uuid = v_ms);
      if v_card is null or (v_card ->> 'ev')::int <> 10 or (v_card ->> 'run')::numeric <> 90
         or exists (select 1 from jsonb_array_elements(coalesce(v_sheet -> 'a', '[]'::jsonb) || coalesce(v_sheet -> 'b', '[]'::jsonb)) h
                     where not (h ?& array['ev', 'run']) or (h -> 'ev') <> (public.evasion_of((h ->> 'id')::uuid) -> 'ev')) then
        raise exception '0453 self-assert FAIL: the raid''s sheet does not carry each hull''s Evasion: %', v_sheet;
      end if;
      -- frozen: she gains a level after the open; a re-run reads the sheet
      update public.level_xp lx set xp = public.level_points(15)::int where lx.player_id = v_mep and lx.skill = 'evasion';
      v_f2 := public.tick_battle_run(v_bat);
      if (select b.sheet from public.battles b where b.id = v_bat)::text <> v_sheet::text or (v_f2 -> 'e')::text <> (v_b.ticks -> 'e')::text then
        raise exception '0453 self-assert FAIL: a re-run after she gained a level moved her card or the fight';
      end if;
      update public.level_xp lx set xp = public.level_points(10)::int where lx.player_id = v_mep and lx.skill = 'evasion';
      v_failed := (select count(*) from jsonb_array_elements(v_b.ticks -> 'e') e where e ->> 2 = 'X' and e ->> 1 = '0' and e ->> 4 = '0');
      v_fled := coalesce((v_b.ticks #>> '{r,fled}')::boolean, false);
      v_book := (select count(*) from public.level_book b where b.player_id = v_mep);
      perform public.battle_resolve(v_bat, v_b.resolves_at + interval '1 second');
      if (select coalesce(sum(b.xp), 0) from public.level_book b where b.player_id = v_mep and b.key = 'run_try:' || v_bat) <> 5 * v_failed
         or (select coalesce(sum(b.xp), 0) from public.level_book b where b.player_id = v_mep and b.key = 'run_away:' || v_bat) <> (case when v_fled then 40 else 0 end)
         or (select count(*) from public.level_book b where b.player_id = v_mep) <> v_book + (case when v_failed > 0 then 1 else 0 end) + (case when v_fled then 1 else 0 end) then
        raise exception '0453 self-assert FAIL: raid % (% failed roll(s), fled %) granted %', v_n, v_failed, v_fled,
          (select jsonb_agg(jsonb_build_array(b.activity, b.xp, b.key)) from public.level_book b where b.player_id = v_mep and b.seq > 1);
      end if;
      v_book := (select count(*) from public.level_book b where b.player_id = v_mep);
      perform public.battle_resolve(v_bat, v_b.resolves_at + interval '2 seconds');
      if (select count(*) from public.level_book b where b.player_id = v_mep) <> v_book then
        raise exception '0453 self-assert FAIL: a second close of raid % granted again', v_n;
      end if;
      v_note := v_note || format('%sraid %s: open %s %%, %s failed roll(s)%s', case when v_n > 1 then '; ' else '' end, v_n, coalesce(v_b.ticks #>> '{rc,a,0,1}', '-'), v_failed,
                                 case when v_fled then ', got away' else '' end);
      if v_failed > 0 or v_fled then
        v_ran := v_ran + 1;
        exit;
      end if;
      update public.fleets f set status = 'ANCHORED', port_id = null, lat = 36.5, lon = -12.0, busy_until = null where f.id = v_me;
      update public.fleets f set status = 'DOCKED', port_id = v_port, busy_until = null where f.id = v_pir;
      update public.ships s set durability = (select b.durability from public.ship_base(s.id) b), crew = (select c.crew_required from public.ship_classes c where c.id = s.class_id)
       where s.fleet_id in (v_me, v_pir);
    end loop;
    if v_ran = 0 then
      raise exception '0453 self-assert FAIL: in % raid(s) she never ran: nothing was granted or compared (%)', v_raids, v_note;
    end if;
    -- a merchant set upon earns nothing
    update public.fleets f set status = 'DOCKED', port_id = v_port, busy_until = null where f.id = v_pir;
    update public.ships s set durability = (select b.durability from public.ship_base(s.id) b), crew = (select c.crew_required from public.ship_classes c where c.id = s.class_id) where s.fleet_id = v_pir;
    update public.fleets f set status = 'ANCHORED', port_id = null, lat = 36.6, lon = -12.0, busy_until = null, ready_at = null where f.id = v_mer;
    v_bat := public.battle_open('RAID', v_pir, v_mer, now() + interval '3 hours');
    perform public.battle_resolve(v_bat, (select b.resolves_at from public.battles b where b.id = v_bat) + interval '1 second');
    if exists (select 1 from public.level_xp lx where lx.player_id = v_merp) or exists (select 1 from public.level_book b where b.player_id = v_merp) then
      raise exception '0453 self-assert FAIL: a merchant set upon earned a level row';
    end if;
    raise exception sqlstate 'BV453';
  exception when sqlstate 'BV453' then null;
  end;
  if v_note = '' then
    raise exception '0453 self-assert FAIL: the probe raided nobody';
  end if;
  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0453 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0453 self-assert ok: A RUN IS A CHASE. % hunks once each and reversing; grants and volatility unmoved; no other function moved; 2 new functions, server-only; switch off: three fixed fights as before; lit: 15 equal, 29 / 8 by skill, the cap 50, 10 half hull, 7 short-handed, 5 slow, 15 both doubled, 1 no speed, 23 a hurt pursuer; % roll(s) each 5 lower. Probe: level_perk the steps'' sum; evasion_of 1 / 10 / a merchant 2; the sailing factors voyage.ship_speed_at''s; % (granted once, nothing on a second close; a merchant nothing; rolled back); % ms.',
    (select count(*) from hunks_0453), v_rolls, v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0453;
end $m$;
