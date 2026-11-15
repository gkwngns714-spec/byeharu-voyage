-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0435 - A BATTLE IS FOUGHT TICK BY TICK  (a 0.6-second clock, guns on their own reload, abilities on cooldowns fed by Fury, the whole fight
--        computed once at the open and played back; slice 1 of docs/design/tick-combat.md)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-15: "the round it takes for a combat to happen i guess is 1 minute, i want the combat system resemble something like rs3"; and
--   "NO MORE 'wait a minute for a round, then wait more for the result' ... it plays tick by tick ... keep the total fight length modest, around
--   30-90 seconds". Genre mechanics only: no name, art, ability or number of any other game. No PvP, ever.
--
-- WHAT SAYS THE OPPOSITE, NAMED: public.battle_open / battle_sheet_freeze give a RAID battle_seconds (600 s) over 7 slots = 85 s a round, an ATTACK
--   battle_round_seconds (60 s) a round; public.battle_advance logs one round when the minute job (public.tick_battles) or a stance press reaches it.
--   So a raid is 10 minutes of one-minute waits.
-- WHAT THIS FILE DOES:
--   T1. THE ENGINE (new, pure, STABLE): public.tick_fight(seed, a, b, opts): 600 ms ticks (tick_ms), six windows of 20 ticks (tick_window) = the
--       six fight_ranges (72 s) and the boarding; every gun on her own reload (tick_reload_base + tier); one ability a side at a time (tick_gcd) from
--       tick_abilities (Broadside, Chain Shot, Rake, Grapeshot, Brace, Patch, Run, Pay) with cooldowns and the Fury bar; an AI rotation (FIGHT,
--       FLEE, PAY); crits (tick_crit, tick_crit_mult), armour as armour_turns_pct, Brace halving; 0320's break-off, sighting slip and boarding
--       arithmetic; 0353/0432's flee chance (a raid's `a_flee`) on each Run. N vs M; a ship comes up at her `from` tick. Every draw keyed by
--       (tick, side, place, what): a re-run with something new from tick T is the same fight before T. It answers the TIMELINE (section 9.3) with
--       `r` in public.fight_sides' shape (a window = a round: public.tick_row), so every reader of a battle's result reads it unchanged.
--   T2. THE WIRING: public.battle_sheet_freeze (one hunk) ends in public.tick_fight_open: for a kind in tick_fight_kinds (["RAID", "ATTACK"]) the
--       ships her country called go on the sheet with their tick, and public.tick_battle_run (THE one (re)run) writes battles.ticks (a new column),
--       the end (last tick + 2), the minute job's due time and every held side's busy_until. public.battle_fight (one hunk) answers the timeline's
--       result; public.battle_advance (one hunk) logs no rounds for it. public.battle_resolve, raid_close, attack_close, navy_close, the holds and
--       the peace (0432) are not touched: the result they read has the shape they read. Every side stays held to the end (0432), as before.
--   T3. THE DOORS: world.battle_ticks(battle) (the battle screen's read: timeline, clock, circle, sides, result) and cmd.battle_end(battle) (closes a
--       tick battle when its end has come, so the result does not wait for the minute job), both in public.client_rpc_entry_points (one hunk).
--   T4. THE MAP: public.fight_card (one hunk) serves `reach_nm` (battle_join_nm, 30) and `ticks` (a tick battle) on each ring.
-- NOT HERE: joining by choice (0436: cmd.battle_join, JOINED), a player's action bar (slice 2: cmd.battle_act). A player's side is fought by her
--   standing order (0353) meanwhile; cmd.battle_stance still answers but no stance after the open changes a tick battle.
-- LOAD: -- budget: no new rows: the timeline is a column of the battle row (~2-5 KB as text, TOASTed), written once at the open; a tick battle
--   writes no battle_rounds rows (the round battle wrote 7), so about -700 rows an hour at 100 battles. CPU: one engine call a battle at the open,
--   ~5 ms in PGlite (100 fights in 523 ms), ~0.5 s an hour at 100 battles. No job, no cron, no table. A closed RAID row (and its timeline) is
--   deleted after raid_keep_hours (48) by 0427's sweep: ~10 MB held at the ceiling.
-- RETENTION: battles.ticks lives and dies with its battle row (0427: a closed RAID deleted after raid_keep_hours; ATTACK rows as before).
-- LOCKS: ALTER TABLE public.battles ADD COLUMN ticks jsonb (no default: catalog only, a brief ACCESS EXCLUSIVE); CREATE OR REPLACE x5 by hunks;
--   CREATE FUNCTION x6. BUDGET: statement_timeout 45 s, lock_timeout 5 s; fails above 30 s.
-- ROLLBACK (forward, owner only): tick_fight_kinds [] (every NEW battle is the round engine at once; a running tick battle closes on its clock).
--   The whole file: scripts/ops/harness/tick-combat/rollback-0435.sql (a draft: the hunks reversed, the functions dropped, the column and knobs
--   kept harmless).
-- SELF-ASSERT: every hunk once and reversing; grants, volatility, definer, search path, owner of the hunked functions unmoved; no other function
--   moved; the two doors open to signed-in players only and the rest server-only; the knobs; THE ENGINE on a fixed sheet: twice the same text,
--   within the clock, its result in fight_sides' shape, its hull_lost the sum of its hits; THE PREFIX: a ship added from tick 60 leaves every
--   event before tick 60 as it was; THE PROBE, rolled back: a RAID sheet between two ships of the world is run at its open, its end within 75 s,
--   public.battle_fight answers the timeline's result and public.battle_advance logs nothing; the knob [] leaves a sheet to the rounds.
-- VERSION: 0435 = 0434 + 1 (0431 stats tabs, 0432 pirate flee, 0433 short server words, 0434 city people slot, queued ahead). Written on the chain to
--   0433; 0431 and 0434 touch none of these bodies.
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_hunked constant text[] := array[
    'public.battle_sheet_freeze(uuid,timestamp with time zone)', 'public.battle_fight(uuid,integer)', 'public.battle_advance(uuid,timestamp with time zone)',
    'public.fight_card(uuid,uuid)', 'public.client_rpc_entry_points()'];
  c_new constant text[] := array[
    'public.tick_row(integer,text,integer[],numeric[],numeric[],integer[],integer[],integer[],integer[],numeric[],numeric[],numeric[],numeric[],boolean[])',
    'public.tick_fight(uuid,jsonb,jsonb,jsonb)', 'public.tick_battle_run(uuid)', 'public.tick_fight_open(uuid,timestamp with time zone)',
    'world.battle_ticks(uuid)', 'cmd.battle_end(uuid)'];
  c_doors constant text[] := array['world.battle_ticks(uuid)', 'cmd.battle_end(uuid)'];
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
  v_hc        jsonb;
  v_f1        jsonb;
  v_f2        jsonb;
  v_f3        jsonb;
  v_sum       numeric;
  v_m1        uuid;
  v_m2        uuid;
  v_bat       uuid;
  v_b         public.battles%rowtype;
  v_ms_eng    numeric;
  v_note      text := '';
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if exists (select 1 from public.world_config where key = 'tick_ms') then
    raise exception '0435 refuses: it has been applied once';
  end if;
  if to_regprocedure('public.flee_bonus(uuid,uuid)') is null or to_regprocedure('public.fleet_peace_until(uuid)') is null
     or to_regprocedure('cmd.refused_envelope(text,text)') is null or to_regprocedure('public.news_update(text,text,text)') is null then
    raise exception '0435 refuses: 0432 (a raided ship may run) is not in this world';
  end if;

  -- ── 1. THE PRE-IMAGE ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
    into v_meta from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)));

  -- ── 2. THE COLUMN ──
  -- retention: battles.ticks lives and dies with its battle row (0427's raid_keep_hours sweep for a RAID)
  alter table public.battles add column ticks jsonb;
  comment on column public.battles.ticks is '0435: the timeline of a battle fought tick by tick (public.tick_fight via public.tick_battle_run; docs/design/tick-combat.md 9.3). Null: a round-by-round battle.';

  -- ── 3. THE KNOBS ──
  insert into public.world_config (key, value, description) values
    ('tick_ms', to_jsonb(600), '0435: one tick of a battle fought tick by tick, in milliseconds.'),
    ('tick_window', to_jsonb(20), '0435: ticks a window; the windows are fight_ranges (LONG x3, MEDIUM x2, CLOSE), then the boarding.'),
    ('tick_gcd', to_jsonb(3), '0435: ticks between two abilities of one side (the commander''s global cooldown).'),
    ('tick_reload_base', to_jsonb(4), '0435: a hull''s guns reload in this many ticks plus her tier.'),
    ('tick_auto_share', to_jsonb(0.5), '0435: the share of a full broadside a window that a hull''s own reload fire deals; the abilities deal about the rest.'),
    ('tick_crit', to_jsonb(0.10), '0435: the chance a hit is a crit.'),
    ('tick_crit_mult', to_jsonb(1.5), '0435: what a crit multiplies a hit by.'),
    ('tick_abilities', '{"BS": {"kind": "basic", "cd": 15, "gain": 10, "mult": 0.25},
                         "CH": {"kind": "basic", "cd": 25, "gain": 10, "mult": 0.15, "slow": 15},
                         "RK": {"kind": "threshold", "cd": 40, "cost": 50, "mult": 0.6, "acc": 15},
                         "GR": {"kind": "ultimate", "cd": 60, "cost": 100, "mult": 0.5, "crew": 0.15},
                         "BR": {"kind": "defence", "cd": 40, "for": 10, "cut": 0.5},
                         "PT": {"kind": "defence", "cd": 60, "cost": 50, "mend": 0.08},
                         "RN": {"kind": "flee", "cd": 20, "for": 20},
                         "PY": {"kind": "pay"}}'::jsonb,
     '0435: THE ability table (docs/design/tick-combat.md 4): cd ticks, Fury gain/cost, a volley''s mult of a full broadside and accuracy bonus, Chain Shot''s slow ticks, Grapeshot''s crew cut, Brace''s ticks and cut, Patch''s mend of her size, Run''s ticks before the roll.'),
    ('tick_fight_kinds', '["RAID", "ATTACK"]'::jsonb, '0435: the kinds of battle fought tick by tick from their open. []: every new battle is fought round by round (0357), the quick rollback.'),
    ('battle_join_nm', to_jsonb(30), '0435: the radius of a battle''s circle on the map, nautical miles round battles.site; a ship inside may join by choice (0436).');

  -- ── 4. THE NEW FUNCTIONS ──
  execute $f$
create function public.tick_row(p_w int, p_range text, p_side int[], p_wloss numeric[], p_maxd numeric[], p_idx int[], p_can int[], p_fired int[], p_hits int[],
                                p_raw numeric[], p_dealt numeric[], p_flee numeric[], p_hull numeric[], p_up boolean[])
returns jsonb
language sql
immutable
set search_path = public, pg_temp
as $body$
  -- 0435: ONE WINDOW OF A TICK FIGHT IN THE SHAPE OF A ROUND of public.fight_sides (0320): {round, range, a{can, fired, hits, raw, dealt, struck[[hull no., % of her size]], left}, b{...}},
  -- with `flee` / `b_flee` when that side ran in it. So public.battle_log, voyage.raid_extras and the client's FightLog read a tick fight's result as they read a round's.
  select jsonb_build_object('round', p_w + 1, 'range', p_range,
           'a', jsonb_build_object('can', p_can[1], 'fired', p_fired[1], 'hits', p_hits[1], 'raw', round(p_raw[1], 2), 'dealt', round(p_dealt[1], 2),
                  'struck', coalesce((select jsonb_agg(jsonb_build_array(p_idx[k] + 1, greatest(1, round(p_wloss[k] / p_maxd[k] * 100))) order by k)
                                        from generate_subscripts(p_side, 1) k where p_side[k] = 1 and p_wloss[k] > 0), '[]'::jsonb),
                  'left', (select coalesce(sum(p_hull[k]), 0) from generate_subscripts(p_side, 1) k where p_side[k] = 1 and p_up[k])),
           'b', jsonb_build_object('can', p_can[2], 'fired', p_fired[2], 'hits', p_hits[2], 'raw', round(p_raw[2], 2), 'dealt', round(p_dealt[2], 2),
                  'struck', coalesce((select jsonb_agg(jsonb_build_array(p_idx[k] + 1, greatest(1, round(p_wloss[k] / p_maxd[k] * 100))) order by k)
                                        from generate_subscripts(p_side, 1) k where p_side[k] = 2 and p_wloss[k] > 0), '[]'::jsonb),
                  'left', (select coalesce(sum(p_hull[k]), 0) from generate_subscripts(p_side, 1) k where p_side[k] = 2 and p_up[k])))
         || case when p_flee[1] is not null then jsonb_build_object('flee', p_flee[1]) else '{}'::jsonb end
         || case when p_flee[2] is not null then jsonb_build_object('b_flee', p_flee[2]) else '{}'::jsonb end
$body$;
$f$;

  execute $f$
create function public.tick_fight(p_seed uuid, p_a jsonb, p_b jsonb, p_opts jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0435 (docs/design/tick-combat.md): THE FIGHT, TICK BY TICK. A pure function of its arguments, the fight_* and tick_* knobs, armour_turns_pct and the world secret:
-- the same (seed, sides, opts) is the same fight, event for event. p_a is the side set upon (and the ships called to her), p_b the side that closes, each a list of
-- hulls as voyage.fleet_hulls serves them, plus `from` (the tick a called ship comes up; absent 0) and `fleet_name`.
--   THE CLOCK   tick_ms (600) a tick. fight_ranges are the WINDOWS, tick_window (20) ticks each (LONG, LONG, LONG, MEDIUM, MEDIUM, CLOSE = 72 s), then the boarding.
--   AUTO FIRE   every hull with guns fires on her own reload, tick_reload_base + tier ticks, one shot (raiders: `shots`): hit on accuracy x the window's share (5-95 %),
--               on a hull of the other side picked by size, for attack / shots x fight_damage_per_attack x tick_auto_share x reload / tick_window x (0.75-1.25), a crit
--               (tick_crit) x tick_crit_mult, less her armour (armour_turns_pct). At LONG a hull out-reached by the other side's best does not fire (range decides, as 0320).
--   ABILITIES   tick_abilities: a side's commander uses one at a time, tick_gcd ticks apart, each on its own cooldown. Basics build Fury (0-100), heavier ones spend it.
--               A volley is one shot from every gun of the side at the ability's mult (and accuracy bonus). Brace halves what she takes; Patch mends her most hurt hull;
--               Run silences her guns and rolls to slip away at its end (0353/0432's flee rule, a raid's bonus `a_flee`); Pay ends it in a ransom.
--   THE AI      p_opts.a_ai / b_ai: FIGHT (a rotation: patch when low, brace under fire, ultimate at 100, threshold at 50, then the basics), FLEE (run, brace), PAY.
--   THE ENDS    the side that closes breaks off at fight_raider_break of its hull lost (EVADED untouched, else DRIVEN_OFF); a run that slips is EVADED (`fled`) or, hers,
--               `b_fled`; every hull of the side set upon at 0, or the windows run out: THE BOARDING, 0320's arithmetic (crew x hand value x boarder share + tier x 3,
--               x the share of hull left; grapeshot thins her crew), read against fight_board_bands.
--   DETERMINISM IS A PREFIX PROPERTY: every draw is keyed (tick, hull, what), so a fight re-run with something new from tick T is the same fight before T (slice 2).
-- Returns the TIMELINE {v, ms, w, n, first, gcd, ab, a[], b[], ai, e[], out, r}; `r` is public.fight_sides' answer shape (rounds = the windows), so every reader of a
-- battle's result reads it as it reads a round-by-round fight. Events: [t, side 0|1, kind, ...] (docs/design/tick-combat.md section 7).
declare
  v_ranges jsonb := public.wc('fight_ranges');
  v_nw     int := jsonb_array_length(public.wc('fight_ranges'));
  c_w      int := public.wc_int('tick_window');
  v_ab     jsonb := public.wc('tick_abilities');
  v_gcdn   int := public.wc_int('tick_gcd');
  v_rb     int := public.wc_int('tick_reload_base');
  v_auto   numeric := public.wc_num('tick_auto_share');
  v_crit   numeric := public.wc_num('tick_crit');
  v_critm  numeric := public.wc_num('tick_crit_mult');
  v_k      numeric := public.wc_num('fight_damage_per_attack');
  v_break  numeric := public.wc_num('fight_raider_break');
  v_bands  jsonb := public.wc('fight_board_bands');
  v_hand   numeric := public.wc_num('fight_hand_value');
  v_armk   numeric := public.wc_num('armour_turns_pct');
  v_sec    text := public.wc_text('world_secret');
  v_ai     text[] := array[coalesce(p_opts ->> 'a_ai', 'FIGHT'), coalesce(p_opts ->> 'b_ai', 'FIGHT')];
  c_codes  constant text[] := array['BS', 'CH', 'RK', 'GR', 'BR', 'PT', 'RN', 'PY'];
  v_na     int := coalesce(jsonb_array_length(p_a), 0);
  v_nb     int := coalesce(jsonb_array_length(p_b), 0);
  n        int;
  x        jsonb;
  i        int;
  j        int;
  q        int;
  s        int;
  o        int;
  t        int;
  w        int := -1;
  t_end    int;
  -- the hulls, both sides in one list: side 1 (a) first
  h_side   int[] := '{}';
  h_idx    int[] := '{}';
  h_id     uuid[] := '{}';
  h_att    numeric[] := '{}';
  h_acc    numeric[] := '{}';
  h_reach  numeric[] := '{}';
  h_arm    numeric[] := '{}';
  h_hull0  numeric[] := '{}';
  h_hull   numeric[] := '{}';
  h_maxd   numeric[] := '{}';
  h_crew   numeric[] := '{}';
  h_bpct   numeric[] := '{}';
  h_tier   numeric[] := '{}';
  h_shots  int[] := '{}';
  h_from   int[] := '{}';
  h_next   int[] := '{}';
  h_rel    int[] := '{}';
  h_up     boolean[] := '{}';
  h_wloss  numeric[] := '{}';
  v_meta   jsonb[] := array['[]'::jsonb, '[]'::jsonb];
  -- each side
  s_h0     numeric[] := array[0, 0];
  s_sight  numeric[] := array[0, 0];
  s_bar    numeric[] := array[0, 0];
  s_fury   numeric[] := array[0, 0];
  s_gcd    int[] := array[0, 2];   -- the side that closes answers: its commander's first act is 2 ticks after the other's
  s_brace  int[] := array[-1, -1];
  s_slow   int[] := array[-1, -1];
  s_run    int[] := array[-1, -1];
  s_crewm  numeric[] := array[1, 1];
  s_hit    int[] := array[-99, -99];
  s_unr    int[] := array[0, 0];
  s_save   boolean[] := array[false, false];
  s_hits   int[] := array[0, 0];
  s_ready  int[] := array_fill(0, array[16]);
  -- the window's figures
  w_can    int[] := array[0, 0];
  w_fired  int[] := array[0, 0];
  w_hits   int[] := array[0, 0];
  w_raw    numeric[] := array[0, 0];
  w_dealt  numeric[] := array[0, 0];
  w_flee   numeric[] := array[null, null]::numeric[];
  v_rows   jsonb := '[]'::jsonb;
  v_range  text;
  v_mult   numeric;
  v_ev     jsonb := '[]'::jsonb;
  -- this tick's guns
  f_ship   int[];
  f_code   text[];
  f_mult   numeric[];
  f_acc    numeric[];
  v_code   text;
  v_a      jsonb;
  v_size   numeric;
  v_pick   numeric;
  v_sum    numeric;
  v_tg     int;
  v_p      numeric;
  v_d      numeric;
  v_c      int;
  v_loss   numeric;
  v_share  numeric;
  v_canfire boolean;
  v_str    text;
  v_first  text;
  v_outcome text;
  v_fled   boolean := false;
  v_bfled  boolean := false;
  v_broke  boolean := false;
  v_paid   boolean := false;
  v_slip   boolean := false;
  v_board  jsonb;
  v_fought int := 0;
  p_you    numeric := 0;
  p_they   numeric := 0;
  c_you    numeric := 0;
  c_they   numeric := 0;
  v_ratio  numeric;
  v_lost   numeric[] := array[0, 0];
  v_left   numeric[] := array[0, 0];
  v_r      jsonb;
begin
  if v_na = 0 or v_nb = 0 then
    raise exception 'E_NO_SHIPS: a fight needs at least one hull' using errcode = 'P0001';
  end if;
  if jsonb_typeof(v_ranges) <> 'array' or v_nw = 0 or jsonb_typeof(v_bands) <> 'array' or jsonb_array_length(v_bands) <> 3 or c_w < 1 then
    raise exception 'E_FIGHT_KNOBS: fight_ranges, fight_board_bands and tick_window must be set' using errcode = 'P0001';
  end if;
  t_end := v_nw * c_w;

  -- ── THE HULLS ──
  n := 0;
  for s in 1 .. 2 loop
    for q in 1 .. case when s = 1 then v_na else v_nb end loop
      x := case when s = 1 then p_a else p_b end -> (q - 1);
      n := n + 1;
      h_side[n]  := s;
      h_idx[n]   := q - 1;
      h_id[n]    := (x ->> 'id')::uuid;
      h_att[n]   := greatest(0, coalesce((x ->> 'attack')::numeric, 0));
      h_acc[n]   := greatest(0, coalesce((x ->> 'accuracy')::numeric, 0));
      h_reach[n] := greatest(0, coalesce((x ->> 'reach')::numeric, 0));
      h_arm[n]   := greatest(0, coalesce((x ->> 'armour')::numeric, 0));
      h_hull0[n] := greatest(0, coalesce((x ->> 'hull')::numeric, 0));
      h_hull[n]  := h_hull0[n];
      h_maxd[n]  := greatest(1, coalesce((x ->> 'maxd')::numeric, 1));
      h_crew[n]  := greatest(0, coalesce((x ->> 'crew')::numeric, 0));
      h_bpct[n]  := greatest(0, coalesce((x ->> 'boarder_pct')::numeric, 0));
      h_tier[n]  := greatest(0, coalesce((x ->> 'tier')::numeric, 0));
      h_shots[n] := greatest(1, coalesce((x ->> 'shots')::int, 1));
      h_from[n]  := greatest(0, coalesce((x ->> 'from')::int, 0));   -- a ship called or joining comes up at her tick (0: there from the start)
      h_rel[n]   := greatest(2, v_rb + h_tier[n]::int);
      h_next[n]  := h_from[n] + 1 + floor(voyage.rng_raw(p_seed, 1, format('tick:load:%s.%s', s, q - 1), v_sec) * h_rel[n])::int;   -- guns are not all loaded at one instant
      h_up[n]    := false;
      h_wloss[n] := 0;
      v_meta[s]  := v_meta[s] || jsonb_build_array(jsonb_build_object('n', x ->> 'name', 'fl', x ->> 'fleet_name', 'h', h_hull0[n], 'm', h_maxd[n],
                      't', h_tier[n], 'r', h_rel[n], 'f', h_from[n], 'g', h_att[n] > 0 and h_acc[n] > 0));
      if h_from[n] = 0 then
        s_h0[s] := s_h0[s] + h_hull0[n];
        s_sight[s] := greatest(s_sight[s], coalesce((x ->> 'sighting')::numeric, 0));
      end if;
    end loop;
  end loop;

  v_first := case when s_sight[1] > s_sight[2] then 'A' when s_sight[1] < s_sight[2] then 'B' else 'BOTH' end;
  if v_first = 'A' then s_unr[2] := c_w; elsif v_first = 'B' then s_unr[1] := c_w; end if;   -- the side seen first is caught unready for the first window

  -- ── SIZING UP, SIGHTING, PAYING (before a shot, as 0320 and 0353) ──
  if s_h0[2] <= 0 then
    v_outcome := 'EVADED'; v_ev := v_ev || jsonb_build_array(jsonb_build_array(0, 1, 'O')); t := 0;
  elsif v_first = 'A' and voyage.rng_raw(p_seed, 1, 'tick:0:evade', v_sec) < least(public.wc_num('fight_evade_max'), (s_sight[1] - s_sight[2]) * public.wc_num('fight_evade_per_sighting')) then
    v_outcome := 'EVADED'; v_slip := true; v_ev := v_ev || jsonb_build_array(jsonb_build_array(0, 0, 'L')); t := 0;
  elsif v_ai[1] = 'PAY' then
    v_outcome := 'RANSOM'; v_paid := true; v_ev := v_ev || jsonb_build_array(jsonb_build_array(0, 0, 'U', 'PY', 0)); t := 0;
  end if;

  -- ── THE TICKS ──
  if v_outcome is null then
    t := 0;
    while t < t_end loop
      -- a window opens: its range; who can fire; the bar a hull must reach at LONG
      if t % c_w = 0 then
        if w >= 0 then
          v_rows := v_rows || public.tick_row(w, v_range, h_side, h_wloss, h_maxd, h_idx, w_can, w_fired, w_hits, w_raw, w_dealt, w_flee, h_hull, h_up);
        end if;
        w := t / c_w;
        v_range := v_ranges -> w ->> 0;
        v_mult := (v_ranges -> w ->> 1)::numeric;
        w_can := array[0, 0]; w_fired := array[0, 0]; w_hits := array[0, 0]; w_raw := array[0, 0]; w_dealt := array[0, 0]; w_flee := array[null, null]::numeric[];
        for i in 1 .. n loop h_wloss[i] := 0; end loop;
      end if;
      -- called ships come up
      for i in 1 .. n loop
        if h_from[i] = t and not h_up[i] then
          h_up[i] := true;
          if t > 0 then
            s_h0[h_side[i]] := s_h0[h_side[i]] + h_hull0[i];
            s_sight[h_side[i]] := greatest(s_sight[h_side[i]], coalesce(((case when h_side[i] = 1 then p_a else p_b end) -> h_idx[i] ->> 'sighting')::numeric, 0));
            v_ev := v_ev || jsonb_build_array(jsonb_build_array(t, h_side[i] - 1, 'J', h_idx[i]));
          end if;
        end if;
      end loop;
      if t % c_w = 0 or exists (select 1 from unnest(h_from) z where z = t and t > 0) then
        s_bar := array[0, 0];
        w_can := array[0, 0];
        for i in 1 .. n loop
          if h_up[i] and h_att[i] > 0 and h_acc[i] > 0 and h_hull[i] > 0 then
            s_bar[h_side[i]] := greatest(s_bar[h_side[i]], h_reach[i]);
            w_can[h_side[i]] := w_can[h_side[i]] + 1;
          end if;
        end loop;
      end if;

      f_ship := '{}'; f_code := '{}'; f_mult := '{}'; f_acc := '{}';
      -- ── THE COMMANDERS: one ability a side when the global cooldown allows ──
      for s in 1 .. 2 loop
        o := 3 - s;
        continue when t < s_gcd[s];
        v_share := (select coalesce(sum(h_hull[k]), 0) from generate_subscripts(h_side, 1) k where h_side[k] = s and h_up[k]) / nullif(s_h0[s], 0);
        v_canfire := t >= s_unr[s] and exists (select 1 from generate_subscripts(h_side, 1) k
                                                where h_side[k] = s and h_up[k] and h_hull[k] > 0 and h_att[k] > 0 and h_acc[k] > 0
                                                  and (v_range <> 'LONG' or h_reach[k] >= s_bar[o]));
        v_code := null;
        if v_ai[s] = 'FLEE' then
          if s_ready[(s - 1) * 8 + 7] <= t and s_run[s] < t then v_code := 'RN';
          elsif s_ready[(s - 1) * 8 + 5] <= t and s_hit[s] >= t - 5 then v_code := 'BR'; end if;
        elsif v_ai[s] in ('FIGHT', 'PAY') and s_run[s] < t then
          if coalesce(v_share, 0) < 0.5 and s_fury[s] >= coalesce((v_ab -> 'PT' ->> 'cost')::numeric, 50) and s_ready[(s - 1) * 8 + 6] <= t then v_code := 'PT';
          elsif coalesce(v_share, 0) < 0.8 and s_ready[(s - 1) * 8 + 5] <= t and s_hit[s] >= t - 5 then v_code := 'BR';
          elsif v_canfire then
            if s_fury[s] >= coalesce((v_ab -> 'GR' ->> 'cost')::numeric, 100) and s_ready[(s - 1) * 8 + 4] <= t then v_code := 'GR';
            elsif s_fury[s] >= coalesce((v_ab -> 'RK' ->> 'cost')::numeric, 50) and s_ready[(s - 1) * 8 + 3] <= t and not s_save[s] then v_code := 'RK';
            elsif s_ready[(s - 1) * 8 + 2] <= t then v_code := 'CH';
            elsif s_ready[(s - 1) * 8 + 1] <= t then v_code := 'BS';
            end if;
          end if;
        end if;
        continue when v_code is null;
        v_a := v_ab -> v_code;
        s_ready[(s - 1) * 8 + array_position(c_codes, v_code)] := t + coalesce((v_a ->> 'cd')::int, 0);
        s_gcd[s] := t + v_gcdn;
        s_fury[s] := least(100, greatest(0, s_fury[s] + coalesce((v_a ->> 'gain')::numeric, 0) - coalesce((v_a ->> 'cost')::numeric, 0)));
        v_ev := v_ev || jsonb_build_array(jsonb_build_array(t, s - 1, 'U', v_code, s_fury[s]));
        if v_code = 'RK' then s_save[s] := true; elsif v_code = 'GR' then s_save[s] := false; end if;
        if v_code in ('BS', 'CH', 'RK', 'GR') then
          for i in 1 .. n loop
            if h_side[i] = s and h_up[i] and h_hull[i] > 0 and h_att[i] > 0 and h_acc[i] > 0 and (v_range <> 'LONG' or h_reach[i] >= s_bar[o]) then
              f_ship := f_ship || i; f_code := f_code || v_code; f_mult := f_mult || coalesce((v_a ->> 'mult')::numeric, 0); f_acc := f_acc || coalesce((v_a ->> 'acc')::numeric, 0);
            end if;
          end loop;
          if v_code = 'CH' then s_slow[o] := t + coalesce((v_a ->> 'slow')::int, 0); end if;
          if v_code = 'GR' then s_crewm[o] := greatest(0.4, s_crewm[o] - coalesce((v_a ->> 'crew')::numeric, 0)); end if;
        elsif v_code = 'BR' then
          s_brace[s] := t + coalesce((v_a ->> 'for')::int, 0);
        elsif v_code = 'PT' then
          select k into j from generate_subscripts(h_side, 1) k
           where h_side[k] = s and h_up[k] and h_hull[k] > 0 and h_hull[k] < h_hull0[k] order by h_hull[k] / h_hull0[k], k limit 1;
          if j is not null then
            v_d := round(least(coalesce((v_a ->> 'mend')::numeric, 0) * h_maxd[j], h_hull0[j] - h_hull[j]), 1);
            h_hull[j] := h_hull[j] + v_d;
            v_ev := v_ev || jsonb_build_array(jsonb_build_array(t, s - 1, 'P', h_idx[j], v_d, round(h_hull[j], 1)));
          end if;
        elsif v_code = 'RN' then
          s_run[s] := t + coalesce((v_a ->> 'for')::int, c_w);
        end if;
      end loop;

      -- ── THE GUNS ON THEIR OWN RELOAD ──
      for i in 1 .. n loop
        s := h_side[i];
        continue when not h_up[i] or h_hull[i] <= 0 or h_att[i] <= 0 or h_acc[i] <= 0 or h_next[i] > t;
        h_next[i] := t + case when s_slow[s] >= t then ceil(h_rel[i] * 1.5)::int else h_rel[i] end;
        continue when t < s_unr[s] or s_run[s] >= t or (v_range = 'LONG' and h_reach[i] < s_bar[3 - s]);
        f_ship := f_ship || i; f_code := f_code || 'A'::text; f_mult := f_mult || (v_auto * h_rel[i] / c_w); f_acc := f_acc || 0::numeric;
      end loop;

      -- ── THE SHOTS: the guns that were ready when the tick began, each landing as it goes, on a hull still afloat ──
      for q in 1 .. coalesce(array_length(f_ship, 1), 0) loop
        i := f_ship[q];
        s := h_side[i];
        o := 3 - s;
        for c in 1 .. h_shots[i] loop
          v_str := format('tick:%s:%s.%s:%s:%s', t, s, h_idx[i], f_code[q], c);   -- keyed by the hull's side and place, never a counter: a joiner moves no other draw
          v_size := 0;
          for j in 1 .. n loop
            if h_side[j] = o and h_up[j] and h_hull[j] > 0 then v_size := v_size + h_maxd[j]; end if;
          end loop;
          exit when v_size <= 0;
          v_pick := voyage.rng_raw(p_seed, 1, v_str || ':at', v_sec) * v_size;
          v_sum := 0; v_tg := null;
          for j in 1 .. n loop
            continue when h_side[j] <> o or not h_up[j] or h_hull[j] <= 0;
            v_sum := v_sum + h_maxd[j];
            v_tg := j;
            exit when v_pick < v_sum;
          end loop;
          w_fired[s] := w_fired[s] + 1;
          v_p := least(0.95, greatest(0.05, h_acc[i] / 100.0 * v_mult + f_acc[q] / 100.0));
          if voyage.rng_raw(p_seed, 1, v_str || ':hit', v_sec) >= v_p then
            v_ev := v_ev || jsonb_build_array(jsonb_build_array(t, s - 1, f_code[q], h_idx[i], h_idx[v_tg], 0, 0, round(h_hull[v_tg], 1)));
            continue;
          end if;
          v_d := h_att[i] / h_shots[i] * v_k * f_mult[q] * (0.75 + 0.5 * voyage.rng_raw(p_seed, 1, v_str || ':dmg', v_sec));
          v_c := case when voyage.rng_raw(p_seed, 1, v_str || ':crit', v_sec) < v_crit then 1 else 0 end;
          if v_c = 1 then v_d := v_d * v_critm; end if;
          w_raw[s] := w_raw[s] + v_d;
          if v_armk > 0 then v_d := v_d * greatest(0, 1 - h_arm[v_tg] / 100.0 * v_armk); end if;
          if s_brace[o] >= t then v_d := v_d * (1 - coalesce((v_ab -> 'BR' ->> 'cut')::numeric, 0)); end if;
          v_d := round(v_d, 2);
          w_dealt[s] := w_dealt[s] + v_d;
          w_hits[s] := w_hits[s] + 1;
          s_hits[s] := s_hits[s] + 1;
          v_loss := least(v_d, h_hull[v_tg]);
          h_hull[v_tg] := h_hull[v_tg] - v_loss;
          h_wloss[v_tg] := h_wloss[v_tg] + v_loss;
          s_hit[o] := t;
          v_ev := v_ev || jsonb_build_array(jsonb_build_array(t, s - 1, f_code[q], h_idx[i], h_idx[v_tg], round(v_d, 1), v_c, round(h_hull[v_tg], 1)));
          if h_hull[v_tg] <= 0 and v_loss > 0 then
            v_ev := v_ev || jsonb_build_array(jsonb_build_array(t, o - 1, 'S', h_idx[v_tg]));
          end if;
        end loop;
      end loop;

      -- ── A RUN ENDS IN ITS ROLL ──
      for s in 1 .. 2 loop
        continue when s_run[s] <> t;
        o := 3 - s;
        v_p := case when s = 1 and p_opts ? 'a_flee'
                    then least(public.wc_num('raid_flee_max'), greatest(public.wc_num('raid_flee_floor'),
                           public.wc_num('fight_flee_base') + (s_sight[1] - s_sight[2]) * public.wc_num('fight_evade_per_sighting') + (p_opts ->> 'a_flee')::numeric))
                    else least(public.wc_num('fight_evade_max'), greatest(public.wc_num('fight_flee_floor'),
                           public.wc_num('fight_flee_base') + (s_sight[s] - s_sight[o]) * public.wc_num('fight_evade_per_sighting'))) end;
        w_flee[s] := round(v_p, 4);
        if voyage.rng_raw(p_seed, 1, format('tick:%s:run:%s', t, s), v_sec) < v_p then
          v_ev := v_ev || jsonb_build_array(jsonb_build_array(t, s - 1, 'X', round(v_p * 100), 1));
          if s = 1 then v_fled := true; v_outcome := 'EVADED';
          else v_bfled := true; v_broke := true; end if;
        else
          v_ev := v_ev || jsonb_build_array(jsonb_build_array(t, s - 1, 'X', round(v_p * 100), 0));
          s_run[s] := -1;
        end if;
      end loop;

      -- ── THE ENDS ──
      for s in 1 .. 2 loop
        v_lost[s] := s_h0[s] - (select coalesce(sum(h_hull[k]), 0) from generate_subscripts(h_side, 1) k where h_side[k] = s and h_up[k]);
      end loop;
      if v_outcome is null and (v_bfled or v_lost[2] >= v_break * s_h0[2]) then
        if not v_bfled then
          v_broke := true;
          v_ev := v_ev || jsonb_build_array(jsonb_build_array(t, 1, 'K'));
        end if;
        v_outcome := case when v_lost[1] = 0 then 'EVADED' else 'DRIVEN_OFF' end;
      end if;
      exit when v_outcome is not null;
      exit when not exists (select 1 from generate_subscripts(h_side, 1) k where h_side[k] = 1 and h_up[k] and h_hull[k] > 0)
                and not exists (select 1 from generate_subscripts(h_side, 1) k where h_side[k] = 1 and h_from[k] > t);   -- struck: the boarding, now
      t := t + 1;
    end loop;
    v_rows := v_rows || public.tick_row(w, v_range, h_side, h_wloss, h_maxd, h_idx, w_can, w_fired, w_hits, w_raw, w_dealt, w_flee, h_hull, h_up);
    v_fought := w + 1;
  end if;

  -- ── THE BOARDING ──
  if v_outcome is null then
    for i in 1 .. n loop
      continue when h_from[i] > t;
      if h_side[i] = 1 then
        c_you := c_you + h_crew[i] * s_crewm[1];
        p_you := p_you + (h_crew[i] * s_crewm[1] * v_hand * (1 + h_bpct[i]) + h_tier[i] * 3) * case when h_hull0[i] > 0 then h_hull[i] / h_hull0[i] else 0 end;
      elsif h_hull0[i] > 0 then
        c_they := c_they + h_crew[i] * s_crewm[2] * h_hull[i] / h_hull0[i];
        p_they := p_they + (h_crew[i] * s_crewm[2] * v_hand * (1 + h_bpct[i]) + h_tier[i] * 3) * h_hull[i] / h_hull0[i];
      end if;
    end loop;
    v_ratio := case when p_they <= 0 then 99 else round(p_you / p_they, 4) end;
    v_outcome := case when v_ratio >= (v_bands ->> 0)::numeric then 'DRIVEN_OFF' when v_ratio >= (v_bands ->> 1)::numeric then 'RANSOM' else 'PLUNDERED' end;
    v_board := jsonb_build_object('a_power', round(p_you, 2), 'b_power', round(p_they, 2), 'ratio', v_ratio, 'surrender', v_ratio < (v_bands ->> 2)::numeric,
                                  'a_crew', round(c_you), 'b_crew', round(c_they));
    v_ev := v_ev || jsonb_build_array(jsonb_build_array(t, -1, 'B', v_ratio, v_ratio < (v_bands ->> 2)::numeric));
  end if;
  v_ev := v_ev || jsonb_build_array(jsonb_build_array(t, -1, 'E', v_outcome));

  for s in 1 .. 2 loop
    v_left[s] := (select coalesce(sum(h_hull[k]), 0) from generate_subscripts(h_side, 1) k where h_side[k] = s and h_from[k] <= t);
  end loop;
  v_r := case when v_bfled then '{"b_fled": true}'::jsonb else '{}'::jsonb end || jsonb_build_object(
    'outcome', v_outcome, 'stood_off', s_h0[2] <= 0, 'slipped', v_slip, 'broke_off', v_broke, 'first', v_first, 'rounds_fought', v_fought, 'rounds', v_rows, 'board', v_board,
    'hull_lost', jsonb_build_object(
      'a', coalesce((select jsonb_object_agg(h_id[k]::text, round(h_hull0[k] - h_hull[k], 2)) from generate_subscripts(h_side, 1) k where h_side[k] = 1 and h_hull0[k] > h_hull[k] and h_from[k] <= t), '{}'::jsonb),
      'b', coalesce((select jsonb_object_agg(h_id[k]::text, round(h_hull0[k] - h_hull[k], 2)) from generate_subscripts(h_side, 1) k where h_side[k] = 2 and h_hull0[k] > h_hull[k]), '{}'::jsonb)),
    'hull', jsonb_build_object('a', v_left[1], 'b', v_left[2], 'a_start', s_h0[1], 'b_start', s_h0[2]),
    'hits', jsonb_build_object('a', s_hits[1], 'b', s_hits[2]), 'engine', 'tick', 'ticks', t)
    || case when v_fled then '{"fled": true}'::jsonb else '{}'::jsonb end
    || case when v_paid then '{"paid": true}'::jsonb else '{}'::jsonb end;

  return jsonb_build_object('v', 1, 'ms', public.wc_int('tick_ms'), 'w', c_w, 'n', t, 'first', v_first, 'gcd', v_gcdn,
    'ranges', v_ranges, 'ab', v_ab, 'a', v_meta[1], 'b', v_meta[2], 'ai', jsonb_build_object('a', v_ai[1], 'b', v_ai[2]),
    'e', v_ev, 'out', v_outcome, 'r', v_r);
end
$body$;
$f$;

  execute $f$
create function public.tick_battle_run(p_battle uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0435: THE ONE (RE)RUN OF A TICK BATTLE: its sheet (every hull, each with its `from`) through public.tick_fight, seeded by the battle's id, under the
-- stances kept (the side set upon: her opening stance, 0432's rule or her standing order, FIGHT / FLEE / PAY; the side that closes FIGHT, or FLEE
-- if she said so) and the raid's flee bonus. Writes battles.ticks (k = how many times it was run, 0 at the open), the battle's end (the last tick
-- + 2), the minute job's due time (= the end), a window as round_seconds, and every held side's busy_until to the end. A joiner (0436) and an act
-- (slice 2) change the sheet and call this: the past is the same fight by construction (public.tick_fight keys every draw by tick and hull).
declare
  b       public.battles%rowtype;
  v_att   uuid;
  v_def   uuid;
  v_opts  jsonb;
  v_a     jsonb;
  v_b     jsonb;
  v_tl    jsonb;
  v_ms    int := public.wc_int('tick_ms');
  v_until timestamptz;
begin
  select * into b from public.battles where id = p_battle for update;
  if b.id is null or b.sheet is null then
    return null;
  end if;
  select bs.fleet_id into v_att from public.battle_sides bs where bs.battle_id = p_battle and bs.side = 'ATTACKER' and bs.how = 'OPENED';
  select bs.fleet_id into v_def from public.battle_sides bs where bs.battle_id = p_battle and bs.side = 'DEFENDER' and bs.how = 'OPENED';
  v_opts := jsonb_build_object('a_ai', public.battle_stance_at(p_battle, v_def, 'infinity'),
                               'b_ai', case when public.battle_stance_at(p_battle, v_att, 'infinity') = 'FLEE' then 'FLEE' else 'FIGHT' end);
  if b.sheet ? 'a_flee' then
    v_opts := v_opts || jsonb_build_object('a_flee', b.sheet -> 'a_flee');
  end if;
  select coalesce(jsonb_agg(e.h || jsonb_build_object('fleet_name', f.name) order by e.o), '[]'::jsonb) into v_a
    from jsonb_array_elements(coalesce(b.sheet -> 'a', '[]'::jsonb)) with ordinality e(h, o)
    left join public.ships sh on sh.id = (e.h ->> 'id')::uuid left join public.fleets f on f.id = sh.fleet_id;
  select coalesce(jsonb_agg(e.h || jsonb_build_object('fleet_name', f.name) order by e.o), '[]'::jsonb) into v_b
    from jsonb_array_elements(coalesce(b.sheet -> 'b', '[]'::jsonb)) with ordinality e(h, o)
    left join public.ships sh on sh.id = (e.h ->> 'id')::uuid left join public.fleets f on f.id = sh.fleet_id;
  v_tl := public.tick_fight(p_battle, v_a, v_b, v_opts) || jsonb_build_object('k', coalesce((b.ticks ->> 'k')::int + 1, 0));
  v_until := b.started_at + make_interval(secs => ((v_tl ->> 'n')::int + 2) * v_ms / 1000.0);
  update public.battles
     set ticks = v_tl, resolves_at = v_until, next_round_at = v_until, rounds_done = 0,
         round_seconds = greatest(1, round((v_tl ->> 'w')::int * v_ms / 1000.0))::int
   where id = p_battle;
  update public.fleets f set busy_until = v_until, version = f.version + 1
   where f.id in (select bs.fleet_id from public.battle_sides bs where bs.battle_id = p_battle)
     and f.busy_until is not null and f.busy_until is distinct from v_until;
  return v_tl;
end
$body$;
$f$;

  execute $f$
create function public.tick_fight_open(p_battle uuid, p_now timestamptz)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0435: AT THE OPEN (public.battle_sheet_freeze's last act), for a kind in tick_fight_kinds: the ships her country called (0333: battle_sides CALLED,
-- arrives_at) go on the sheet on their side, each with `from` = the tick she comes up and `fleet`, if she comes up before the boarding; then the
-- whole fight is run once (public.tick_battle_run). Any other kind, or the knob empty: nothing (the round-by-round battle, as it was).
declare
  b      public.battles%rowtype;
  s      record;
  v_h    jsonb;
  v_from int;
  v_ms   int := public.wc_int('tick_ms');
  v_end  int := jsonb_array_length(public.wc('fight_ranges')) * public.wc_int('tick_window');
  v_key  text;
begin
  select * into b from public.battles where id = p_battle for update;
  if b.id is null or b.sheet is null or b.ticks is not null or not (coalesce(public.wc('tick_fight_kinds'), '[]'::jsonb) ? b.kind) then
    return;
  end if;
  for s in select bs.fleet_id, bs.side, bs.arrives_at from public.battle_sides bs
            where bs.battle_id = p_battle and bs.how = 'CALLED' order by bs.arrives_at, bs.fleet_id loop
    v_from := greatest(1, ceil(extract(epoch from s.arrives_at - b.started_at) * 1000.0 / v_ms)::int);
    continue when v_from >= v_end;
    v_key := case when s.side = 'DEFENDER' then 'a' else 'b' end;
    select coalesce(jsonb_agg(e.h || jsonb_build_object('from', v_from, 'fleet', s.fleet_id) order by e.o), '[]'::jsonb) into v_h
      from jsonb_array_elements(coalesce(voyage.fleet_hulls(s.fleet_id), '[]'::jsonb)) with ordinality e(h, o);
    b.sheet := jsonb_set(b.sheet, array[v_key], coalesce(b.sheet -> v_key, '[]'::jsonb) || v_h);
  end loop;
  update public.battles set sheet = b.sheet where id = p_battle;
  perform public.tick_battle_run(p_battle);
end
$body$;
$f$;

  execute $f$
create function world.battle_ticks(p_battle uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0435 (docs/design/tick-combat.md 9.2): THE BATTLE SCREEN'S READ, any battle with a sheet, for any signed-in player: the clock (`now` is the server's),
-- the timeline (null for a round-by-round battle: the client draws it with the round view), the circle, every side, her own fleet in it, and closed,
-- the result. What a side lost or took (taken, loot, crew_lost) is served to her own battle, or to everyone when no player's fleet is in it.
-- Stable: it never advances and never closes (cmd.battle_end does). No house, no such battle, or a probe: {on: false}.
declare
  v_player uuid := public.current_player_id();
  b        public.battles%rowtype;
  v_mine   uuid;
  v_open   boolean;
begin
  if v_player is null then
    return jsonb_build_object('on', false);
  end if;
  select * into b from public.battles where id = p_battle and sheet is not null;
  if b.id is null then
    return jsonb_build_object('on', false);
  end if;
  select bs.fleet_id into v_mine from public.battle_sides bs join public.fleets f on f.id = bs.fleet_id
   where bs.battle_id = b.id and f.player_id = v_player order by bs.how <> 'OPENED', bs.fleet_id limit 1;
  v_open := v_mine is not null or not exists (select 1 from public.battle_sides bs join public.fleets f on f.id = bs.fleet_id join public.players p on p.id = f.player_id
                                               where bs.battle_id = b.id and not p.is_npc);
  return jsonb_build_object(
    'on', true, 'battle', b.id, 'kind', b.kind, 'status', b.status, 'started_at', b.started_at, 'resolves_at', b.resolves_at, 'now', now(),
    'ticks', b.ticks, 'site', b.site, 'reach_nm', public.wc_num('battle_join_nm'),
    'sides', (select coalesce(jsonb_agg(jsonb_build_object(
                'fleet', x.fleet_id, 'name', x.name, 'side', x.side, 'how', x.how, 'kind', x.kind, 'nation', x.nation,
                'company', case when x.kind in ('COMPANY', 'MERCHANT') then x.company end, 'mine', x.player_id = v_player)
                order by x.side, x.joined_at, x.fleet_id), '[]'::jsonb)
                from (select bs.fleet_id, bs.side, bs.how, bs.joined_at, f.name, f.player_id, public.fleet_kind(f.id) as kind, pl.company_name as company,
                             (select n.code from public.nations n where n.id = coalesce(public.crown_nation(f.id), pl.nation_id)) as nation
                        from public.battle_sides bs join public.fleets f on f.id = bs.fleet_id join public.players pl on pl.id = f.player_id
                       where bs.battle_id = b.id) x),
    'mine', v_mine,
    'result', case when b.status = 'FIGHTING' then null else jsonb_build_object(
                'outcome', b.result -> 'outcome', 'fled', coalesce(b.result -> 'fled', 'false'::jsonb), 'b_fled', coalesce(b.result -> 'b_fled', 'false'::jsonb),
                'paid', coalesce(b.result -> 'paid', 'false'::jsonb),
                'taken', case when v_open then b.result #> '{raid,taken}' end, 'loot', case when v_open then b.result -> 'loot' end,
                'crew_lost', case when v_open then b.result -> 'crew_lost' end, 'navy', b.result #> '{navy,line}') end);
end
$body$;
$f$;

  execute $f$
create function cmd.battle_end(p_battle uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0435 (docs/design/tick-combat.md 6, 9.2): A TICK BATTLE CLOSES AT ITS END, not at the minute job's next run: any signed-in reader whose playback has
-- reached the end asks, and public.battle_resolve (THE one closer, under the battle's lock: a second ask, or the job, finds it closed) closes it if
-- its end has come. Before the end, or a round-by-round battle: nothing is done. {ok, status, resolves_at}; E_NO_HOUSE, E_NO_BATTLE.
declare
  v_player uuid := public.current_player_id();
  b        public.battles%rowtype;
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_HOUSE', 'error_message', 'Found a house first.', 'fixes', '[]'::jsonb);
  end if;
  select * into b from public.battles where id = p_battle;
  if b.id is null or b.sheet is null then
    return cmd.refused_envelope('E_NO_BATTLE: there is no such battle', null);
  end if;
  if b.status = 'FIGHTING' and b.ticks is not null and b.resolves_at <= clock_timestamp() then
    perform public.battle_resolve(p_battle, clock_timestamp());
    select * into b from public.battles where id = p_battle;
  end if;
  return jsonb_build_object('ok', true, 'status', b.status, 'resolves_at', b.resolves_at);
end
$body$;
$f$;

  revoke all on function public.tick_row(integer, text, integer[], numeric[], numeric[], integer[], integer[], integer[], integer[], numeric[], numeric[], numeric[], numeric[], boolean[]) from public, anon, authenticated;
  revoke all on function public.tick_fight(uuid, jsonb, jsonb, jsonb) from public, anon, authenticated;
  revoke all on function public.tick_battle_run(uuid) from public, anon, authenticated;
  revoke all on function public.tick_fight_open(uuid, timestamptz) from public, anon, authenticated;
  revoke all on function world.battle_ticks(uuid) from public, anon;
  grant execute on function world.battle_ticks(uuid) to authenticated;
  revoke all on function cmd.battle_end(uuid) from public, anon;
  grant execute on function cmd.battle_end(uuid) to authenticated;

  -- ── 5. THE HUNKS (each occurs exactly once in the live body, and reverses) ──
  create temp table hunks_0435 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0435 values
  ('public.battle_sheet_freeze(uuid,timestamp with time zone)', 1,
$h$    insert into public.battle_stances (battle_id, fleet_id, set_at, stance) values (p_battle, v_def, b.started_at, v_st);
  end if;$h$,
$h$    insert into public.battle_stances (battle_id, fleet_id, set_at, stance) values (p_battle, v_def, b.started_at, v_st);
  end if;
  perform public.tick_fight_open(p_battle, p_now);   -- 0435: a kind in tick_fight_kinds is fought tick by tick: the whole fight, once, now$h$),
  ('public.battle_fight(uuid,integer)', 1,
$h$  if b.id is null or b.sheet is null then
    return null;
  end if;$h$,
$h$  if b.id is null or b.sheet is null then
    return null;
  end if;
  if b.ticks is not null then
    return b.ticks -> 'r';   -- 0435: a battle fought tick by tick: its timeline's result (public.fight_sides' shape), whole from the open
  end if;$h$),
  ('public.battle_advance(uuid,timestamp with time zone)', 1,
$h$  if b.id is null or b.status <> 'FIGHTING' or b.sheet is null then$h$,
$h$  if b.id is null or b.status <> 'FIGHTING' or b.sheet is null or b.ticks is not null then   -- 0435: a tick battle has no rounds to log$h$),
  ('public.fight_card(uuid,uuid)', 1,
$h$           'started_at', b.started_at, 'resolves_at', b.resolves_at, 'round_seconds', b.round_seconds,$h$,
$h$           'started_at', b.started_at, 'resolves_at', b.resolves_at, 'round_seconds', b.round_seconds,
           'reach_nm', public.wc_num('battle_join_nm'), 'ticks', b.ticks is not null,   -- 0435: the circle's radius; a battle fought tick by tick$h$),
  ('public.client_rpc_entry_points()', 1,
$h$      ('world',       'fight',                 'uuid'),$h$,
$h$      ('world',       'fight',                 'uuid'),
      -- 0435: a battle fought tick by tick: its timeline for the battle screen, and the close at its end.
      ('world',       'battle_ticks',          'uuid'),
      ('cmd',         'battle_end',            'uuid'),$h$);

  for v_h in select h.fn from hunks_0435 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    for x in select * from hunks_0435 h where h.fn = v_h.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
      if v_n <> 1 then
        raise exception '0435 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
      end if;
      v_def := replace(v_def, x.old, x.new);
    end loop;
    execute v_def;
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    for x in select * from hunks_0435 h where h.fn = v_h.fn order by h.ord desc loop
      if (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new) <> 1 then
        raise exception '0435 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
      end if;
      v_def := replace(v_def, x.new, x.old);
    end loop;
    if v_def <> v_pre then
      raise exception '0435 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
    end if;
  end loop;

  -- ── 6. SELF-ASSERT: the catalog, the grants, the knobs ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))
         and p.oid <> all (array(select u.q::regprocedure::oid from unnest(c_new) u(q)))) <> v_fn_before then
    raise exception '0435 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text, ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (array(select u.q::regprocedure::oid from unnest(c_hunked) u(q)))) <> v_meta then
    raise exception '0435 self-assert FAIL: the grants, volatility, definer, search path or owner of a hunked function moved';
  end if;
  if exists (select 1 from unnest(c_new) f where not (f = any (c_doors))
              and (has_function_privilege('anon', f::regprocedure, 'execute') or has_function_privilege('authenticated', f::regprocedure, 'execute')))
     or exists (select 1 from unnest(c_doors) f where has_function_privilege('anon', f::regprocedure, 'execute') or not has_function_privilege('authenticated', f::regprocedure, 'execute'))
     or (select count(*) from public.client_rpc_entry_points() e where e.fn = any (array(select u.q::regprocedure from unnest(c_doors) u(q)))) <> 2
     or exists (select 1 from public.client_rpc_entry_points() e where e.fn = any (array(select u.q::regprocedure from unnest(c_new) u(q))) and not (e.fn::text = any (array(select u.q::regprocedure::text from unnest(c_doors) u(q)))))
     or exists (select 1 from public.client_executable_writers()) then
    raise exception '0435 self-assert FAIL: the doors are not the two signed-in doors, or a server function is open to clients';
  end if;
  if public.wc_int('tick_ms') <> 600 or public.wc_int('tick_window') <> 20 or not (public.wc('tick_fight_kinds') ? 'RAID') or jsonb_typeof(public.wc('tick_abilities')) <> 'object'
     or (select count(*) from jsonb_object_keys(public.wc('tick_abilities'))) <> 8 then
    raise exception '0435 self-assert FAIL: the knobs are not this file''s';
  end if;

  -- ── 7. THE ENGINE on a fixed sheet (two hulls against one, the same figures) ──
  v_ha := jsonb_build_array(jsonb_build_object('id', '00000000-0435-4000-8000-000000000001', 'name', 'a1', 'tier', 2, 'hull', 300, 'maxd', 300, 'crew', 40,
            'attack', 40, 'accuracy', 55, 'reach', 20, 'armour', 10, 'sighting', 8, 'boarder_pct', 0));
  v_hb := jsonb_build_array(jsonb_build_object('id', '00000000-0435-4000-8000-000000000002', 'name', 'b1', 'tier', 2, 'hull', 280, 'maxd', 280, 'crew', 60,
            'attack', 60, 'accuracy', 50, 'reach', 22, 'armour', 12, 'sighting', 8, 'boarder_pct', 0.1));
  v_hc := v_ha || jsonb_build_array(jsonb_build_object('id', '00000000-0435-4000-8000-000000000003', 'name', 'a2', 'tier', 3, 'hull', 400, 'maxd', 400, 'crew', 80,
            'attack', 70, 'accuracy', 60, 'reach', 26, 'armour', 15, 'sighting', 9, 'from', 60));
  v_ms_eng := extract(epoch from clock_timestamp()) * 1000;
  v_f1 := public.tick_fight('00000000-0435-4000-8000-0000000000aa'::uuid, v_ha, v_hb, '{}'::jsonb);
  v_ms_eng := round(extract(epoch from clock_timestamp()) * 1000 - v_ms_eng, 1);
  v_f2 := public.tick_fight('00000000-0435-4000-8000-0000000000aa'::uuid, v_ha, v_hb, '{}'::jsonb);
  if v_f1::text <> v_f2::text then
    raise exception '0435 self-assert FAIL: the same fight twice is not the same text';
  end if;
  if (v_f1 ->> 'n')::int > jsonb_array_length(public.wc('fight_ranges')) * public.wc_int('tick_window') or (v_f1 ->> 'out') not in ('EVADED', 'DRIVEN_OFF', 'RANSOM', 'PLUNDERED')
     or (v_f1 -> 'r' ->> 'outcome') is distinct from (v_f1 ->> 'out') or jsonb_typeof(v_f1 -> 'r' -> 'rounds') <> 'array'
     or (v_f1 -> 'r' ->> 'rounds_fought')::int <> jsonb_array_length(v_f1 -> 'r' -> 'rounds') or (v_f1 -> 'e' -> -1 ->> 2) <> 'E' then
    raise exception '0435 self-assert FAIL: the fight is not a whole timeline in the result''s shape: n %, out %, r %', v_f1 -> 'n', v_f1 -> 'out', v_f1 -> 'r' -> 'outcome';
  end if;
  -- what side a lost is what the timeline says her hull came to: the last event that names her hull (a shot at her, or her Patch)
  select coalesce((select case when e ->> 2 = 'P' then (e ->> 5)::numeric else (e ->> 7)::numeric end
                     from jsonb_array_elements(v_f1 -> 'e') with ordinality q(e, o)
                    where ((e ->> 1)::int = 1 and e ->> 2 in ('A', 'BS', 'CH', 'RK', 'GR') and (e ->> 4)::int = 0) or ((e ->> 1)::int = 0 and e ->> 2 = 'P' and (e ->> 3)::int = 0)
                    order by o desc limit 1), 300) into v_sum;
  if abs((300 - v_sum) - coalesce((v_f1 -> 'r' -> 'hull_lost' -> 'a' ->> '00000000-0435-4000-8000-000000000001')::numeric, 0)) > 0.1 then
    raise exception '0435 self-assert FAIL: side a lost % but her timeline ends at % hull', v_f1 -> 'r' -> 'hull_lost' -> 'a', v_sum;
  end if;
  -- THE PREFIX: a ship that comes up at tick 60 changes nothing before it
  v_f3 := public.tick_fight('00000000-0435-4000-8000-0000000000aa'::uuid, v_hc, v_hb, '{}'::jsonb);
  if (select coalesce(jsonb_agg(e order by o), '[]'::jsonb) from jsonb_array_elements(v_f1 -> 'e') with ordinality q(e, o) where (e ->> 0)::int < least(60, (v_f1 ->> 'n')::int))::text
     <> (select coalesce(jsonb_agg(e order by o), '[]'::jsonb) from jsonb_array_elements(v_f3 -> 'e') with ordinality q(e, o) where (e ->> 0)::int < least(60, (v_f1 ->> 'n')::int))::text then
    raise exception '0435 self-assert FAIL: a ship joining at tick 60 changed the fight before it';
  end if;
  if (v_f1 ->> 'n')::int > 60 and not exists (select 1 from jsonb_array_elements(v_f3 -> 'e') e where e ->> 2 = 'J' and (e ->> 0)::int = 60) then
    raise exception '0435 self-assert FAIL: the ship that comes up at tick 60 did not join';
  end if;

  -- ── 8. THE NEWS (0347's law) ──
  perform public.news_update('0435', 'Battles are fought tick by tick, about a minute from first shot to the end',
                             '전투는 틱 단위로 진행된다: 첫 포격부터 끝까지 약 1분');

  -- ── 9. THE PROBE, rolled back by a raised sentinel: a RAID sheet between two ships of the world ──
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
      perform public.tick_fight_open(v_bat, now());
      select * into v_b from public.battles where id = v_bat;
      if v_b.ticks is null or v_b.resolves_at > v_b.started_at + interval '75 seconds' or v_b.next_round_at <> v_b.resolves_at or (v_b.ticks ->> 'k')::int <> 0 then
        raise exception '0435 self-assert FAIL: the probe raid was not run at its open: ticks %, ends %', v_b.ticks is not null, v_b.resolves_at - v_b.started_at;
      end if;
      if public.battle_fight(v_bat, null)::text <> (v_b.ticks -> 'r')::text or public.battle_advance(v_bat, now() + interval '1 hour') <> 0 then
        raise exception '0435 self-assert FAIL: battle_fight / battle_advance do not read the timeline';
      end if;
      v_f2 := public.tick_battle_run(v_bat);   -- its own statement: the row it writes is read by the next one
      if (v_f2 -> 'e')::text <> (v_b.ticks -> 'e')::text or (select (b.ticks ->> 'k')::int from public.battles b where b.id = v_bat) <> 1 then
        raise exception '0435 self-assert FAIL: a re-run of the same sheet is not the same fight';
      end if;
      if not ((public.fight_card(v_bat, null)) ? 'reach_nm') or (public.fight_card(v_bat, null) ->> 'ticks')::boolean is not true then
        raise exception '0435 self-assert FAIL: the ring does not say its circle';
      end if;
      update public.world_config set value = '[]'::jsonb where key = 'tick_fight_kinds';
      update public.battles set ticks = null where id = v_bat;
      perform public.tick_fight_open(v_bat, now());
      if (select b.ticks from public.battles b where b.id = v_bat) is not null then
        raise exception '0435 self-assert FAIL: the knob [] still fought a battle tick by tick';
      end if;
      v_note := format('a raid between two ships of the world: %s in %s ticks (%s events), run at its open and again the same (rolled back)',
                       v_b.ticks ->> 'out', v_b.ticks ->> 'n', jsonb_array_length(v_b.ticks -> 'e'));
    end if;
    raise exception sqlstate 'BV435';
  exception when sqlstate 'BV435' then null;
  end;
  if v_note = '' then
    raise exception '0435 self-assert FAIL: the probe found no two ships of the world';
  end if;
  if clock_timestamp() - v_t0 > interval '30 seconds' then
    raise exception '0435 self-assert FAIL: the file took % (budget 30 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0435 self-assert ok: A BATTLE IS FOUGHT TICK BY TICK. % hunks once each and reversing; grants and volatility unmoved; no other function moved; 6 new functions, 2 signed-in doors; the fixed sheet: % in % ticks, twice the same, hulls by its hits, a ship from tick 60 moves nothing before it (% ms a fight). Probe: %; % ms.',
    (select count(*) from hunks_0435), v_f1 ->> 'out', v_f1 ->> 'n', v_ms_eng, v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0435;
end $m$;
