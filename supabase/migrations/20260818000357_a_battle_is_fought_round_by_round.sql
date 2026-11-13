-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0357 - A BATTLE IS FOUGHT ROUND BY ROUND, AND SHE CHOOSES AS IT GOES  (slice C3 of docs/COMBAT_LOG.md, sections 3, 5.2 and 6; owner row 315)
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
-- WHY: the owner, row 315: "combat - like a log, with action that i choose to do such as when pressed fight, it keeps on fighting, when flee, it tries to flee etc - showing logs,
-- damages etc. system, engaging". C1 + C2 (0353) kept a raid's log and a standing order. This is the live half: the timed battle a player starts (cmd.attack) is fought one round at a
-- time on a clock, the log grows as it is fought, and her stance is a door: FIGHT keeps fighting, FLEE tries to slip each round and takes that round's fire.
--
-- EVERYTHING HERE IS DARK. A battle exists only behind `attack_enabled` (false; the owner's switch; this file does not write it, nor any existing key). With it false no body of this
-- file takes a new branch for any player or ship of the world: the self-assert holds the old bodies against the new ones with the switch off, and proof 60 sails a merchant's and a
-- company's ordinary voyage under old and new, byte for byte.
-- news: none
--   (nothing a player can see changes at this deploy; the news belongs to the step that lights attack_enabled, 0347's law)
--
-- WHAT IT ADDS
--   battles.sheet, round_seconds, rounds_done, next_round_at   the frozen sides, the round clock. An ATTACK has a sheet; a PROBE has none and is today's one call, untouched.
--   public.battle_rounds (battle_id, g, at, row)               THE GROWING LOG: one row a round, the engine's own row. Written by public.battle_advance only.
--   public.battle_stances (battle_id, fleet_id, set_at, stance)   append-only. A side's stance for round g is her latest row set BEFORE that round's instant; none is FIGHT.
--   public.battle_sheet_freeze   at the open: both sides' hulls as they are (voyage.fleet_hulls), once; the clock; a defender's opening stance from her standing order (0353).
--   public.battle_fight          THE ONE FIGHT OF A SHEET: public.fight_sides(battle id, 1, sheet.a, sheet.b, {a_order[], b_order[], rounds}). Stable. No per-round engine state is kept:
--                                round N is a re-run to N. DETERMINISM IS A PREFIX PROPERTY (docs/COMBAT_LOG.md 3.1): every draw is keyed (seed, round, 'fight:<g>:...'), so a run to N
--                                is the first N rows of a run to N + 1, as text. The self-assert and proof 60 prove it; so a round logged on time, a late catch-up and a re-run agree.
--   public.battle_advance        for each round due and not logged: a called ship that has come up joins (her hulls with `from` = that round), the fight is run to that round, its row
--                                is written. A fight that ended in a round (they broke, she got away, a ransom) ends the battle THERE: resolves_at is brought in to that instant.
--                                0333's join rule stands (on the sheet if arrives_at <= resolves_at): a ship that comes up after the last round is there for the boarding.
--   cmd.battle_stance(battle, stance)   THE DOOR: advances first (an act must not reason about a stale round), then keeps her stance from the next round on. FIGHT or FLEE for the
--                                side that attacked (PAY is not offered: she started it); FIGHT, FLEE, PAY for a side set upon. The same stance again writes nothing and still advances,
--                                which is how a watching client keeps the log on the clock between the minute job's runs.
--   world.battle(fleet)          THE READ the card polls (5 s, only while a battle card is open): her fleet's battle, the clock, her stance, the pre-fight word, the log so far
--                                (shape v 1, from her deck) and, closed, the result. Stable: it never advances.
--   public.battle_log            the log of a sheet's fight from the attacker's deck, through voyage.raid_extras (0353): ONE shape, ONE client component.
--   voyage.hold_free_hours, voyage.hold_cut   A HOLD THAT BURNS NOTHING, and a hold that ends when the battle does.
--   knob battle_round_seconds 60   one round a minute, in step with the minute job: six rounds and the boarding are 420 s. `battle_seconds` (600) is not written: it still times a
--                                PROBE, and it is the most an attack may take (the lesser of the two), so a world that shortens battle_seconds shortens an attack as it did.
--
-- SUPERSEDES, BY RE-CUT (hunks sliced from the live bodies: each OLD text once in its live body, each reversing; with attack_enabled off no re-cut body takes a new branch):
--   public.fight_sides (8)    `b_order` (the side that closes may run: silent guns, that round's fire, then a roll on her own stream 'fight:<g>:flee:b', the flee rule with the lead
--                             turned round; away is `b_fled` with broke_off) and a hull's `from` (a called ship is not on the sheet before her round). ABSENT = BYTE-IDENTICAL, proved
--                             on 0320's matrix against a kept copy of the live body, with every option 0353 added.
--   public.battle_open (2)    an ATTACK's clock is battle_round_seconds x (rounds + 1), never over battle_seconds; after the navy is called the sheet is frozen.
--   public.battle_resolve (5) a sheet's battle advances first; its fight is the sheet's, not a new reading of the hulls; BROKEN_OFF has its writer (her Flee got her away:
--                             docs/WORLD_POWERS.md 5.2); a hold that outlasts the battle is cut; the report carries the log.
--   public.tick_battles (1)   what is due is the next ROUND (coalesce(next_round_at, resolves_at)): one read of one partial index, LIMIT 50, SKIP LOCKED, as before.
--   public.battle_words (2)   a round she ran reads "you run before them"; the report's fight entry carries the log.
--   voyage.hold (1)           the row says `free`.
--   voyage.total_days, voyage.days_complete, voyage.arrival_at (1 each)   the day count leaves free hold hours out, never below the voyage's own days.
--   public.client_rpc_entry_points (1)   the two doors, anchored on 0327's `preview_attack` line.
--   public.attack_for and public.attack_close are NOT cut: neither needed it (a break-off already takes the beaten row of attack_crew_lost and no loot).
--
-- A HOLD THAT BURNS NOTHING (docs/COMBAT_LOG.md 3.5). Before: voyage.hold wrote the hold as delay hours, voyage.total_days counted them, and a 600 s hold at compression 960 added
-- about 7 voyage days of stores, wages and hazard rolls, stacked at her arrival. Now the row says `free`, and voyage.total_days, voyage.days_complete's cap and voyage.arrival_at's
-- day count subtract the free hours (never below 0): the day she was held on is longer by the hold, her arrival moves by the hold, and the count of days is the count of a voyage
-- never held. voyage.recompute_eta, voyage.delay_before_day and voyage.settle are not touched.
--
-- WHERE THIS FILE LEAVES docs/COMBAT_LOG.md (the code was followed; each is in docs/dev-log/2026-11-12-live-rounds.md):
--   * the read is keyed by HER FLEET, world.battle(fleet), not by the battle: the client knows the fleet (world.fleets is not cut and serves no battle id).
--   * public.battle_advance logs rounds; public.battle_resolve stays THE one closer and calls it first. So the job's hunk is its WHERE alone and it still calls battle_resolve.
--   * the read re-runs the sheet (public.battle_fight) instead of reading battle_rounds: the rows are the record, and the proof holds the two equal.
--   * a row of battle_rounds is the engine's own row, not C1's 14 cells: the after-check compares it with a re-run as text. The 14 cells are built by the read, for either deck.
--   * the clock is a new knob (battle_round_seconds 60, so 420 s; never over battle_seconds), not battle_seconds / (rounds + 1): no existing key is written, a round is in step
--     with the minute job, and the proofs that shorten battle_seconds still shorten an attack. Proof 49 lengthens a battle to a day and now raises both knobs.
--   * the side that closes rolls to get away BEFORE her losses are read (the hunk stands outside the text 0353 added, which proof 56 reverses whole): away is away either way.
--   * a fight that ends in a round ends the battle there and cuts the hold (voyage.hold_cut): the design closed "when the answer is not open" and did not say what the hold does.
--   * voyage.arrival_at carries the day count a third time (its fixed point), so it takes the same hunk as voyage.total_days and voyage.days_complete.
--   * a fair wind after a hold may still make up the hold's hours (voyage.settle is not cut): the day count is then that of the voyage never held, and she lands earlier by the gain.
--   * no human is ever set upon in a battle in this slice (public.battle_open refuses a human defender), so the standing order as an OPENING stance is proved on the leaf and on a
--     sheet written by the proof, and no door reaches it. The offline case a door does reach: her last stance stands, and the job fights on under it.
--
-- NO PLAYER FIGHTS A PLAYER, in every path: public.battle_open refuses a human defender (E_HUMAN_TARGET), public.attack_for refuses COMPANY (E_HUMAN_TARGET). Neither refusal is
-- touched; the self-assert holds both bodies' refusal lines and the probe presses both.
--
-- COST: dark, one index probe of an empty range on the day count (voyage.hold_free_hours) per voyage.total_days, voyage.days_complete and past-eta voyage.arrival_at call; the job is
-- one read of one partial index a minute, as before. Lit: a battle is at most 7 advances; round g re-runs the fight to g (21 round computations in all); each writes one
-- battle_rounds row (about 0.4 kB). NO ROUND RUNS IN THE ARRIVALS BEAT. Local timings: docs/dev-log/2026-11-12-live-rounds.md (the day count's probe was not measured).
-- ROLLBACK (forward, owner only): attack_enabled false stops new battles and the stance door; running ones finish under their last stance. The whole slice: a migration that swaps
--   this file's OLD and NEW and drops what it created (scripts/ops/harness/live-rounds/rollback-0357.sql is the draft).
-- SELF-ASSERT: ONE DO block, statement_timeout 45 s, lock_timeout 5 s first; fails above 40 s. THE PURE FIGHTS ARE BOUNDED BY THE CLOCK FROM THE START (0353's first deploy took 49 s
--   on prod against 7.8 s locally): engine parity 6 s, the prefix and the new options 4 s: each stops at its bound and FAILS under its least, never passes on nothing; a notice prints
--   the milliseconds of every part. The whole matrices, every time, are proof 60 (scripts/db/proofs/60_live_rounds.sql). On prod byte-parity is held again by
--   scripts/ops/harness/two-sides/golden.sql before and after the deploy. No table is counted or summed; the probes write only their own rows and are rolled back by a raised sentinel.
-- LOCKS: ALTER TABLE public.battles (no row on prod), two new tables referencing battles and fleets (a brief SHARE ROW EXCLUSIVE on fleets), under lock_timeout 5 s.
-- VERSION: 0357, cut on the bodies at head 0353. 0354 (fleet room), 0355 (captain skills) and 0356 (level-up) share no function with this file but the registry, where each
--   anchors on its own line (0354: ship_moves; 0355: promote_captain; this file: preview_attack).
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0         timestamptz := clock_timestamp();
  v_tp         timestamptz := clock_timestamp();
  v_tg         timestamptz;
  v_ms         jsonb := '{}'::jsonb;
  c_guard_parity constant interval := interval '6 seconds';
  c_guard_orders constant interval := interval '4 seconds';
  c_min_pairs    constant int := 200;   -- engine pairs compared as text
  c_min_orders   constant int := 20;    -- fights put under both stance lists and a round limit
  v_fn_before  text;
  v_cfg_before text;
  v_def        text;
  fd           record;
  h            record;
  v_p          record;
  v_x          record;
  v_n          int := 0;
  v_m          int;
  v_pairs      int := 0;
  v_ord_n      int := 0;
  v_pre_n      int := 0;
  v_open_n     int := 0;
  v_bfled      int := 0;
  v_bcaught    int := 0;
  v_from_n     int := 0;
  v_kinds      jsonb := '{}'::jsonb;
  v_old        jsonb;
  v_new        jsonb;
  v_f          jsonb;
  v_g          jsonb;
  v_b          jsonb;
  v_o          jsonb;
  v_src        text;
  v_pf         numeric;
  v_lived      boolean := false;
  v_lit        boolean;
  v_entry      int;
  v_pl         uuid;
  v_pl2        uuid;
  v_npc        uuid;
  v_fl         uuid;
  v_fl2        uuid;
  v_nfl        uuid;
  v_lis        uuid;
  v_voy        uuid;
  v_voy2       uuid;
  v_bat        uuid;
  v_r          jsonb;
  v_e1         text;
  v_e2         text;
  v_t          timestamptz;
  v_days       int;
  v_days_old   int;
  v_note       text := '';
  c_uid   constant uuid := '00000000-0357-4000-8000-000000000001';
  c_uid2  constant uuid := '00000000-0357-4000-8000-000000000002';
  c_seed  constant uuid := '00000000-0357-4000-8000-0000000000ff';
  c_eng   constant text := 'public.fight_sides(uuid,integer,jsonb,jsonb,jsonb)';
  c_cut_fns constant text[] := array[
    'public.fight_sides(uuid,integer,jsonb,jsonb,jsonb)', 'public.battle_open(text,uuid,uuid,timestamp with time zone)',
    'public.battle_resolve(uuid,timestamp with time zone)', 'public.tick_battles(timestamp with time zone)', 'public.battle_words(jsonb,jsonb)',
    'voyage.hold(uuid,timestamp with time zone,timestamp with time zone)', 'voyage.total_days(uuid)', 'voyage.days_complete(uuid,timestamp with time zone)',
    'voyage.arrival_at(uuid,timestamp with time zone)', 'public.client_rpc_entry_points()'];
  c_new_fns constant text[] := array[
    'voyage.hold_free_hours(uuid)', 'voyage.hold_cut(uuid,timestamp with time zone,timestamp with time zone)', 'public.battle_opening_stance(uuid)',
    'public.battle_stance_at(uuid,uuid,timestamp with time zone)', 'public.battle_sheet_freeze(uuid,timestamp with time zone)', 'public.battle_fight(uuid,integer)',
    'public.battle_advance(uuid,timestamp with time zone)', 'public.battle_log(jsonb,jsonb,text)', 'cmd.battle_stance(uuid,text)', 'world.battle(uuid)'];
  c_doors constant text[] := array['cmd.battle_stance(uuid,text)', 'world.battle(uuid)'];
  c_knobs constant text[] := array['battle_round_seconds'];
  -- 0320's own probe hulls (its matrix is the parity matrix, as in 0353)
  v_carlat jsonb := jsonb_build_array(jsonb_build_object('id', '00000000-0320-4000-8000-0000000000a1', 'name', 'Probe Carlat',
                      'tier', 1, 'hull', 550, 'maxd', 550, 'crew', 12, 'attack', 55, 'accuracy', 40, 'reach', 25, 'armour', 12,
                      'sighting', 10, 'gear', jsonb_build_array('Boarding Gear')));
  v_barca  jsonb := jsonb_build_array(jsonb_build_object('id', '00000000-0320-4000-8000-0000000000a2', 'name', 'Probe Barca',
                      'tier', 1, 'hull', 400, 'maxd', 400, 'crew', 8, 'attack', 35, 'accuracy', 0, 'reach', 0, 'armour', 5,
                      'sighting', 8));
  v_three  jsonb := jsonb_build_array(
                      jsonb_build_object('id', '00000000-0320-4000-8000-0000000000a3', 'name', 'Probe Nau', 'tier', 3, 'hull', 1500, 'maxd', 1800, 'crew', 90, 'attack', 180,
                        'accuracy', 55, 'reach', 60, 'armour', 30, 'sighting', 40, 'boarder_pct', 0.12, 'boarder', 'Probe Boarder', 'gunner', 'Probe Gunner', 'gear', jsonb_build_array('Swivel Guns', 'Boarding Gear')),
                      jsonb_build_object('id', '00000000-0320-4000-8000-0000000000a4', 'name', 'Probe Galion', 'tier', 4, 'hull', 2400, 'maxd', 2400, 'crew', 140, 'attack', 260,
                        'accuracy', 48, 'reach', 40, 'armour', 44, 'sighting', 22),
                      jsonb_build_object('id', '00000000-0320-4000-8000-0000000000a5', 'name', 'Probe Wreck', 'tier', 1, 'hull', 0, 'maxd', 500, 'crew', 6, 'attack', 40,
                        'accuracy', 40, 'reach', 90, 'armour', 0, 'sighting', 5));
  v_two    jsonb := jsonb_build_array(
                      jsonb_build_object('id', '00000000-0320-4000-8000-0000000000b1', 'name', 'Probe One', 'tier', 2, 'hull', 9000, 'maxd', 9000, 'crew', 40, 'attack', 120,
                        'accuracy', 60, 'reach', 50, 'armour', 20, 'sighting', 22),
                      jsonb_build_object('id', '00000000-0320-4000-8000-0000000000b2', 'name', 'Probe Two', 'tier', 2, 'hull', 9000, 'maxd', 9000, 'crew', 40, 'attack', 120,
                        'accuracy', 60, 'reach', 50, 'armour', 20, 'sighting', 22));
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regclass('public.battle_rounds') is not null or to_regclass('public.battle_stances') is not null or to_regprocedure('world.battle(uuid)') is not null
     or exists (select 1 from public.world_config c where c.key = any (c_knobs))
     or exists (select 1 from pg_attribute a where a.attrelid = 'public.battles'::regclass and a.attname = 'sheet' and not a.attisdropped) then
    raise exception '0357 refuses: it has been applied once';
  end if;
  if to_regprocedure('voyage.raid_extras(jsonb,jsonb,jsonb,jsonb)') is null or to_regprocedure('public.raid_orders_on()') is null or to_regclass('public.fleet_raid_orders') is null
     or to_regprocedure('public.fight_flee_chance(numeric)') is null or to_regprocedure('public.attack_on()') is null or to_regprocedure('voyage.fleet_hulls(uuid)') is null
     or to_regprocedure('public.battle_sides_come(uuid,timestamp with time zone)') is null or to_regprocedure('public.battle_stop(uuid,timestamp with time zone,timestamp with time zone)') is null
     or to_regprocedure('public.navy_call(uuid,uuid,timestamp with time zone,timestamp with time zone)') is null or to_regprocedure('public.attack_word(numeric,numeric)') is null
     or to_regprocedure('public.attack_for(uuid,uuid,uuid,integer,timestamp with time zone)') is null or to_regprocedure('public.attack_close(uuid,jsonb,timestamp with time zone)') is null
     or to_regprocedure('voyage.escort_score(uuid)') is null or to_regprocedure('voyage.hold_floor()') is null or to_regprocedure('voyage.recompute_eta(uuid)') is null
     or to_regprocedure('cmd.refuse(text,text,jsonb)') is null or to_regprocedure('cmd.refused_envelope(text,text)') is null or to_regprocedure('cmd.assume_identity(uuid)') is null
     or to_regprocedure('public.fleet_kind(uuid)') is null or to_regprocedure('public.wc_int(text)') is null
     or exists (select 1 from unnest(c_cut_fns) f where to_regprocedure(f) is null) then
    raise exception '0357 refuses: a function it calls or cuts is not in this world (0320 / 0323 / 0327 / 0333 / 0353)';
  end if;
  if public.attack_on() then
    raise exception '0357 refuses: attack_enabled is lit. This file is written to deploy dark; read docs/dev-log/2026-11-12-live-rounds.md before deploying it on a lit world.';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  create temp table defs_0357 on commit drop as
  select f.fn,
         replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
         coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
         (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
         (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
         (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
    from unnest(c_cut_fns) f(fn);
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (select f::regprocedure::oid from unnest(c_cut_fns) f);
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
    into v_cfg_before from public.world_config c;
  v_entry := (select count(*) from public.client_rpc_entry_points());

  -- the live bodies, kept for this transaction only, for the parity below: the engine, the day count's three readers, and the battle's bodies (each kept copy calls the kept copies)
  execute replace((select x.def from defs_0357 x where x.fn = c_eng), 'CREATE OR REPLACE FUNCTION public.fight_sides(', 'CREATE FUNCTION pg_temp.fight_sides_old_0357(');
  execute replace((select x.def from defs_0357 x where x.fn = 'voyage.total_days(uuid)'), 'CREATE OR REPLACE FUNCTION voyage.total_days(', 'CREATE FUNCTION pg_temp.total_days_old_0357(');
  execute replace((select x.def from defs_0357 x where x.fn = 'voyage.days_complete(uuid,timestamp with time zone)'), 'CREATE OR REPLACE FUNCTION voyage.days_complete(', 'CREATE FUNCTION pg_temp.days_complete_old_0357(');
  execute replace((select x.def from defs_0357 x where x.fn = 'voyage.arrival_at(uuid,timestamp with time zone)'), 'CREATE OR REPLACE FUNCTION voyage.arrival_at(', 'CREATE FUNCTION pg_temp.arrival_at_old_0357(');
  execute replace((select x.def from defs_0357 x where x.fn = 'public.battle_resolve(uuid,timestamp with time zone)'), 'CREATE OR REPLACE FUNCTION public.battle_resolve(', 'CREATE FUNCTION pg_temp.battle_resolve_old_0357(');
  execute replace(replace((select x.def from defs_0357 x where x.fn = 'public.tick_battles(timestamp with time zone)'), 'CREATE OR REPLACE FUNCTION public.tick_battles(', 'CREATE FUNCTION pg_temp.tick_battles_old_0357('),
                  'public.battle_resolve(r.id, p_now)', 'pg_temp.battle_resolve_old_0357(r.id, p_now)');
  execute replace((select x.def from defs_0357 x where x.fn = 'public.battle_open(text,uuid,uuid,timestamp with time zone)'), 'CREATE OR REPLACE FUNCTION public.battle_open(', 'CREATE FUNCTION pg_temp.battle_open_old_0357(');
  if (select p.prosrc from pg_proc p where p.oid = 'pg_temp.tick_battles_old_0357(timestamp with time zone)'::regprocedure) not like '%pg_temp.battle_resolve_old_0357(r.id, p_now)%' then
    raise exception '0357 refuses: the kept copy of the job does not call the kept copy of the closer';
  end if;

  v_ms := v_ms || jsonb_build_object('guard_and_pre_images', round(extract(epoch from clock_timestamp() - v_tp) * 1000)); v_tp := clock_timestamp();

  -- ── 2. THE HUNKS (each OLD text once in its live body) ──
  create temp table hunks_0357 (fn text, n int, old text, new text) on commit drop;
  insert into hunks_0357 (fn, n, old, new) values
    -- THE ENGINE: b_order and a hull's `from`
    (c_eng, 1,
$o$  c_they   numeric := 0;
  v_ratio  numeric;
$o$,
$n$  c_they   numeric := 0;
  -- 0357: the stance of the side that closes (p_opts.b_order: FIGHT or FLEE, one word or a list with a word a round whose last stands for the rest), and a hull's `from`: the first round a
  -- called ship of the side set upon is on the sheet (absent: 1). Absent: the fight as it was.
  v_bord   jsonb := p_opts->'b_order';
  v_bo     text;
  v_bfled  boolean := false;
  v_bpf    numeric;
  a_from   int[] := '{}';
  v_late   boolean := false;
  v_ratio  numeric;
$n$),
    (c_eng, 2,
$o$    a_shots[i] := greatest(1, coalesce((x->>'shots')::int, 1));
    v_sa       := greatest(v_sa, coalesce((x->>'sighting')::numeric, 0));
$o$,
$n$    a_shots[i] := greatest(1, coalesce((x->>'shots')::int, 1));
    a_from[i]  := greatest(1, coalesce((x->>'from')::int, 1));
    if a_from[i] > 1 then   -- 0357: a called ship: she is not seen, not struck and not counted before her round
      a_hull[i] := 0;
      v_late := true;
      continue;
    end if;
    v_sa       := greatest(v_sa, coalesce((x->>'sighting')::numeric, 0));
$n$),
    (c_eng, 3,
$o$    v_fought := g;
    v_range := v_ranges -> (g - 1) ->> 0;
$o$,
$n$    v_fought := g;
    -- 0357: a called ship comes on the sheet at her round, whole; and the stance of the side that closes for this round
    if v_late then
      for i in 1 .. v_na loop
        if a_from[i] > 1 and a_from[i] = g then   -- only a ship that was called: a hull of round 1 is counted where the sides are read
          a_hull[i] := a_hull0[i];
          v_h0a := v_h0a + a_hull0[i];
          v_sa := greatest(v_sa, coalesce((p_a -> (i - 1) ->> 'sighting')::numeric, 0));
          if a_att[i] > 0 and a_acc[i] > 0 then
            v_ba := greatest(v_ba, a_reach[i]);
          end if;
        end if;
      end loop;
    end if;
    v_bo := case jsonb_typeof(v_bord) when 'string' then v_bord #>> '{}'
                                      when 'array' then coalesce(v_bord ->> (g - 1), v_bord ->> -1) end;
    v_range := v_ranges -> (g - 1) ->> 0;
$n$),
    (c_eng, 4,
$o$v_range, v_mult, g = 1 and v_first = 'A', v_k,
$o$,
$n$v_range, v_mult, (g = 1 and v_first = 'A') or coalesce(v_bo = 'FLEE', false), v_k,   -- 0357: a side that runs fires nothing
$n$),
    (c_eng, 5,
$o$    if v_h0b - v_lb >= v_break * v_h0b then
$o$,
$n$    -- 0357: THE SIDE THAT CLOSES RUNS (docs/WORLD_POWERS.md 5.2, break off). She took this round's fire; now she rolls on her own stream, by the flee rule with the lead turned round.
    -- Away is a break-off said aloud (`b_fled`): no boarding. Not away, the round goes on as it would: her losses may still break her, and the side set upon may still run.
    if v_bo = 'FLEE' then
      v_bpf := least(public.wc_num('fight_evade_max'), greatest(public.wc_num('fight_flee_floor'),
                public.wc_num('fight_flee_base') + (v_sb - v_sa) * public.wc_num('fight_evade_per_sighting')));
      v_rows := jsonb_set(v_rows, array[(g - 1)::text, 'b_flee'], to_jsonb(round(v_bpf, 4)));
      if voyage.rng(p_seed, p_round, format('fight:%s:flee:b', g)) < v_bpf then
        v_bfled := true; v_broke := true;
        v_outcome := case when v_h0a - v_la = 0 then 'EVADED' else 'DRIVEN_OFF' end;
        exit;
      end if;
    end if;
    if v_h0b - v_lb >= v_break * v_h0b then
$n$),
    (c_eng, 6,
$o$    for i in 1 .. v_na loop
      c_you := c_you + a_crew[i];
$o$,
$n$    for i in 1 .. v_na loop
      continue when a_from[i] > v_fought + 1;   -- 0357: a called ship that never came up boards nobody
      if a_from[i] > v_fought then a_hull[i] := a_hull0[i]; end if;   -- 0357: one that came up after the last round is there for the boarding, whole
      c_you := c_you + a_crew[i];
$n$),
    (c_eng, 7,
$o$from generate_subscripts(a_id, 1) k where a_hull0[k] > a_hull[k]), '{}'::jsonb),
$o$,
$n$from generate_subscripts(a_id, 1) k where a_hull0[k] > a_hull[k] and a_from[k] <= v_fought), '{}'::jsonb),   -- 0357: a ship that never came up lost nothing
$n$),
    (c_eng, 8,
$o$  return jsonb_build_object(
    'outcome', v_outcome,$o$,
$n$  return case when v_bfled then '{"b_fled": true}'::jsonb else '{}'::jsonb end ||   -- 0357: said only when true
    jsonb_build_object(
    'outcome', v_outcome,$n$),
    -- THE OPEN
    ('public.battle_open(text,uuid,uuid,timestamp with time zone)', 1,
$o$  v_until := p_now + make_interval(secs => public.wc_num('battle_seconds')::double precision);
$o$,
$n$  -- 0357: an ATTACK is fought round by round: battle_round_seconds a round and one more for the boarding, and never longer than battle_seconds. A probe keeps battle_seconds.
  v_until := p_now + make_interval(secs => (case when p_kind = 'ATTACK' then least(public.wc_num('battle_seconds'), public.wc_num('battle_round_seconds') * (jsonb_array_length(public.wc('fight_ranges')) + 1))
                                                 else public.wc_num('battle_seconds') end)::double precision);
$n$),
    ('public.battle_open(text,uuid,uuid,timestamp with time zone)', 2,
$o$    perform public.navy_call(v_id, p_defender, v_until, p_now);
$o$,
$n$    perform public.navy_call(v_id, p_defender, v_until, p_now);
    perform public.battle_sheet_freeze(v_id, p_now);   -- 0357: both sides as they are, once; the round clock; a probe has no sheet and is one call at its end, as it was
$n$),
    -- THE CLOSE
    ('public.battle_resolve(uuid,timestamp with time zone)', 1,
$o$  select * into b from public.battles where id = p_battle for update;
$o$,
$n$  select * into b from public.battles where id = p_battle for update;
  if b.sheet is not null and b.status = 'FIGHTING' then   -- 0357: live rounds: every round due is fought and logged first; a fight that ended in a round brings resolves_at in
    perform public.battle_advance(p_battle, p_now);
    select * into b from public.battles where id = p_battle;
  end if;
$n$),
    ('public.battle_resolve(uuid,timestamp with time zone)', 2,
$o$  v_f := case when jsonb_array_length(v_a) = 0 or jsonb_array_length(v_b) = 0 then jsonb_build_object('outcome', 'NO_FIGHT')
$o$,
$n$  v_f := case when b.sheet is not null then public.battle_fight(p_battle, null)   -- 0357: the sheet's own fight under the stances kept: its rounds are the rows already logged
              when jsonb_array_length(v_a) = 0 or jsonb_array_length(v_b) = 0 then jsonb_build_object('outcome', 'NO_FIGHT')
$n$),
    ('public.battle_resolve(uuid,timestamp with time zone)', 3,
$o$  update public.battles set status = 'RESOLVED', result = v_f where id = p_battle;
$o$,
$n$  -- 0357: BROKEN_OFF has its writer: the side that attacked fled, and got away (docs/WORLD_POWERS.md 5.2)
  update public.battles set status = case when coalesce((v_f->>'b_fled')::boolean, false) then 'BROKEN_OFF' else 'RESOLVED' end, result = v_f where id = p_battle;
$n$),
    ('public.battle_resolve(uuid,timestamp with time zone)', 4,
$o$     where f.id = s.fleet_id;
    if s.status = 'IN_BATTLE' then
$o$,
$n$     where f.id = s.fleet_id;
    if b.sheet is not null and s.status = 'SAILING' then   -- 0357: a battle that ended before its clock ends her hold with it
      perform voyage.hold_cut(s.fleet_id, b.started_at, b.resolves_at);
    end if;
    if s.status = 'IN_BATTLE' then
$n$),
    ('public.battle_resolve(uuid,timestamp with time zone)', 5,
$o$      v_rep := public.battle_words(v_f, v_b);
$o$,
$n$      v_rep := public.battle_words(v_f || case when b.sheet is not null then jsonb_build_object('sheet', b.sheet) else '{}'::jsonb end, v_b);   -- 0357: with a sheet the report carries the log
$n$),
    -- THE JOB
    ('public.tick_battles(timestamp with time zone)', 1,
$o$            where b.status = 'FIGHTING' and b.resolves_at <= p_now
            order by b.resolves_at, b.id limit 50
$o$,
$n$            where b.status = 'FIGHTING' and coalesce(b.next_round_at, b.resolves_at) <= p_now   -- 0357: what is due is the next round (battles_round_due); a battle with no sheet is due at its end, as it was
            order by coalesce(b.next_round_at, b.resolves_at), b.id limit 50
$n$),
    -- THE REPORT
    ('public.battle_words(jsonb,jsonb)', 1,
$o$jsonb_build_object('range', x->'range', 'a', x->'b', 'b', x->'a'), g, v_first, p_ships, v_hull0, 'enemy');
$o$,
$n$jsonb_build_object('range', x->'range', 'a', x->'b', 'b', x->'a')
                                                      || case when x ? 'b_flee' then jsonb_build_object('flee', x->'b_flee') else '{}'::jsonb end,   -- 0357: a round she ran
                                                    g, v_first, p_ships, v_hull0, 'enemy');
$n$),
    ('public.battle_words(jsonb,jsonb)', 2,
$o$jsonb_build_object('line', 0, 'rounds', to_jsonb(v_rounds))));
$o$,
$n$jsonb_build_object('line', 0, 'rounds', to_jsonb(v_rounds))
    -- 0357: a sheet's battle carries its log, from her deck (public.battle_log), as a raid's entry does (0353)
    || case when p_fight ? 'sheet' then jsonb_build_object('log', public.battle_log(p_fight->'sheet', p_fight - 'sheet', 'ATTACKER')) else '{}'::jsonb end));
$n$),
    -- THE HOLD
    ('voyage.hold(uuid,timestamp with time zone,timestamp with time zone)', 1,
$o$'held_from', p_now, 'held_until', p_until), p_now
$o$,
$n$'held_from', p_now, 'held_until', p_until, 'free', true), p_now   -- 0357: a battle's hold burns nothing (voyage.hold_free_hours)
$n$),
    ('voyage.total_days(uuid)', 1,
$o$                       + (select delay_hours from public.voyages where id = p_voyage)) / 24)::int)
$o$,
$n$                       + greatest(0, (select delay_hours from public.voyages where id = p_voyage) - voyage.hold_free_hours(p_voyage))) / 24)::int)   -- 0357: a free hold is no day
$n$),
    ('voyage.days_complete(uuid,timestamp with time zone)', 1,
$o$                             + (select delay_hours from public.voyages where id = p_voyage)) / 24)::int) + 1;
$o$,
$n$                             + greatest(0, (select delay_hours from public.voyages where id = p_voyage) - voyage.hold_free_hours(p_voyage))) / 24)::int) + 1;   -- 0357: a free hold is no day
$n$),
    ('voyage.arrival_at(uuid,timestamp with time zone)', 1,
$o$    exit when d > greatest(1, ceil((v_sim + v_delay) / 24)::int);
$o$,
$n$    exit when d > greatest(1, ceil((v_sim + greatest(0, v_delay - voyage.hold_free_hours(v.id))) / 24)::int);   -- 0357: a free hold is no day, as voyage.total_days counts
$n$),
    -- THE DOORS
    ('public.client_rpc_entry_points()', 1,
$o$      ('cmd',         'preview_attack',        'uuid, uuid'),
$o$,
$n$      ('cmd',         'preview_attack',        'uuid, uuid'),
      -- 0357: a battle fought round by round: her stance (Fight, Flee), and the read the battle card polls.
      ('cmd',         'battle_stance',         'uuid, text'),
      ('world',       'battle',                'uuid'),
$n$);

  -- ── 3. THE COLUMNS, THE TABLES, THE KNOB ──
  alter table public.battles
    add column sheet         jsonb,
    add column round_seconds integer,
    add column rounds_done   integer not null default 0,
    add column next_round_at timestamptz;
  comment on column public.battles.sheet is
    '0357: the two sides as they were at the open, {a (the side set upon), b, foe, you, word}; a called ship is appended to a with her round (`from`). Null: a battle with no rounds (a probe), fought in one call at its end.';
  comment on column public.battles.next_round_at is '0357: when the next round, or the close, is due. The job reads coalesce(next_round_at, resolves_at) on battles_round_due.';
  create index battles_round_due on public.battles ((coalesce(next_round_at, resolves_at))) where status = 'FIGHTING';

  create table public.battle_rounds (
    battle_id uuid        not null references public.battles(id) on delete cascade,
    g         integer     not null check (g >= 1),
    at        timestamptz not null,
    "row"     jsonb       not null,
    primary key (battle_id, g)
  );
  comment on table public.battle_rounds is
    '0357: A BATTLE''S LOG AS IT GROWS: one row a round, public.fight_sides'' own row, at the instant the round was due. Written by public.battle_advance only. A re-run of the sheet (public.battle_fight) gives the same rows, as text.';
  alter table public.battle_rounds enable row level security;
  revoke all on table public.battle_rounds from public, anon, authenticated;

  create table public.battle_stances (
    battle_id uuid        not null references public.battles(id) on delete cascade,
    fleet_id  uuid        not null references public.fleets(id) on delete cascade,
    set_at    timestamptz not null,
    stance    text        not null check (stance in ('FIGHT', 'FLEE', 'PAY')),
    primary key (battle_id, fleet_id, set_at)
  );
  comment on table public.battle_stances is
    '0357: what a side chose, and when. Append-only. Her stance for a round is her latest row set BEFORE that round''s instant (public.battle_stance_at); none is FIGHT. Written by cmd.battle_stance and, for a defender''s standing order, public.battle_sheet_freeze.';
  alter table public.battle_stances enable row level security;
  revoke all on table public.battle_stances from public, anon, authenticated;

  insert into public.world_config (key, value, description) values
    ('battle_round_seconds', '60'::jsonb,
     '0357: real seconds a round of a player''s attack takes; the battle is this times (the rounds of fight_ranges + 1, the boarding), and never longer than battle_seconds. Read when a battle opens, so a change never moves a running one. 60 is in step with the minute job. A probe keeps battle_seconds.');

  -- ── 4. THE NEW LEAVES ──
  execute $f$
create function voyage.hold_free_hours(p_voyage uuid)
returns numeric
language sql
stable
as $body$
  -- 0357: THE HOURS OF THIS VOYAGE'S HOLDS THAT ARE NO DAYS (voyage.hold writes `free`). voyage.total_days, voyage.days_complete and voyage.arrival_at take them out of the day count, so a
  -- battle's hold costs no stores, no wages and no hazard roll: the day she was held on is longer, and that is all. One probe of an empty range for a voyage never held.
  select coalesce(sum((ve.payload->>'delay_hours')::numeric), 0)
    from public.voyage_events ve
   where ve.voyage_id = p_voyage and ve.day_index >= voyage.hold_floor() and (ve.payload->>'free')::boolean
$body$;
$f$;
  comment on function voyage.hold_free_hours(uuid) is '0357: the hours of a voyage''s free holds: delay that is no day. Read by voyage.total_days, voyage.days_complete, voyage.arrival_at. Server-only.';

  execute $f$
create function voyage.hold_cut(p_fleet uuid, p_from timestamptz, p_at timestamptz)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0357: A HOLD ENDS WITH ITS BATTLE. The hold of this fleet's voyage that began at p_from and still runs past p_at ends at p_at: its hours and its end are rewritten and the eta follows
-- (voyage.recompute_eta). She has stood still from p_from to p_at and sails on from the same mile (voyage.hold_unserved is 0 from the row's own end). No hold running past p_at: nothing.
declare
  v_id uuid;
begin
  select v.id into v_id from public.voyages v where v.fleet_id = p_fleet and v.status = 'SAILING' for update;
  if v_id is null or p_at <= p_from then
    return;
  end if;
  update public.voyage_events ve
     set payload = ve.payload || jsonb_build_object('held_until', p_at,
                     'delay_hours', trim_scale(round(extract(epoch from p_at - p_from) * public.wc_num('time_compression') / 3600, 10)))   -- ten places: a cut may fall on any second, and the eta is read back from these hours
   where ve.voyage_id = v_id and ve.day_index >= voyage.hold_floor()
     and (ve.payload->>'held_from')::timestamptz = p_from and (ve.payload->>'held_until')::timestamptz > p_at;
  if found then
    perform voyage.recompute_eta(v_id);
  end if;
end
$body$;
$f$;
  comment on function voyage.hold_cut(uuid, timestamptz, timestamptz) is '0357: ends a running hold at an instant (a battle that ended before its clock). Called by public.battle_resolve. Server-only.';

  execute $f$
create function public.battle_opening_stance(p_fleet uuid)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0357 (docs/COMBAT_LOG.md 3.4): THE STANCE A SIDE SET UPON OPENS WITH: a company's standing order (0353: FLEE or PAY, while standing orders are in use), else FIGHT. A ship of the world
  -- always fights. So an offline player's fleet follows her standing order by construction. No door reaches it yet: public.battle_open refuses a human defender.
  select coalesce((select o.raid_order
                     from public.fleet_raid_orders o
                     join public.fleets f on f.id = o.fleet_id
                     join public.players p on p.id = f.player_id
                    where o.fleet_id = p_fleet and not p.is_npc and public.raid_orders_on()), 'FIGHT')
$body$;
$f$;
  comment on function public.battle_opening_stance(uuid) is '0357: a defender''s opening stance: her standing order (0353), else FIGHT. Read by public.battle_sheet_freeze. Server-only.';

  execute $f$
create function public.battle_stance_at(p_battle uuid, p_fleet uuid, p_at timestamptz)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0357: A SIDE'S STANCE FOR A ROUND DUE AT p_at: her latest row set BEFORE that instant; none is FIGHT. Strictly before: a stance is never read by a round already fought, so a
  -- late run of the job and a re-run read the same word.
  select coalesce((select s.stance from public.battle_stances s
                    where s.battle_id = p_battle and s.fleet_id = p_fleet and s.set_at < p_at
                    order by s.set_at desc limit 1), 'FIGHT')
$body$;
$f$;
  comment on function public.battle_stance_at(uuid, uuid, timestamptz) is '0357: a side''s stance for a round due at an instant: her latest row before it, else FIGHT. Server-only.';

  execute $f$
create function public.battle_sheet_freeze(p_battle uuid, p_now timestamptz)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0357 (docs/COMBAT_LOG.md 3.1): AT THE OPEN, ONCE: both sides' hulls as they are (voyage.fleet_hulls), in public.battle_resolve's own order, written to battles.sheet; the round clock
-- (the battle's own length over the rounds and the boarding); the pre-fight read in a word (public.attack_word: the word the preview printed); and a defender's opening stance.
-- Every later round is a re-run of this sheet: the hulls are read once, here.
declare
  b     public.battles%rowtype;
  s     record;
  v_a   jsonb := '[]'::jsonb;
  v_b   jsonb := '[]'::jsonb;
  v_att uuid;
  v_def uuid;
  v_rs  integer;
  v_st  text;
begin
  select * into b from public.battles where id = p_battle for update;
  for s in select bs.fleet_id, bs.side, bs.how from public.battle_sides bs
            where bs.battle_id = p_battle and bs.arrives_at <= p_now
            order by bs.joined_at, bs.how = 'CALLED', bs.how = 'ESCORT', bs.fleet_id loop
    if s.side = 'DEFENDER' then
      v_a := v_a || coalesce(voyage.fleet_hulls(s.fleet_id), '[]'::jsonb);
    else
      v_b := v_b || coalesce(voyage.fleet_hulls(s.fleet_id), '[]'::jsonb);
    end if;
    if s.how = 'OPENED' and s.side = 'DEFENDER' then v_def := s.fleet_id; end if;
    if s.how = 'OPENED' and s.side = 'ATTACKER' then v_att := s.fleet_id; end if;
  end loop;
  v_rs := greatest(1, floor(extract(epoch from b.resolves_at - b.started_at) / (jsonb_array_length(public.wc('fight_ranges')) + 1))::int);
  update public.battles
     set sheet = jsonb_build_object('a', v_a, 'b', v_b,
                   'foe', (select f.name from public.fleets f where f.id = v_def), 'you', (select f.name from public.fleets f where f.id = v_att),
                   'word', public.attack_word(voyage.escort_score(v_att), voyage.escort_score(v_def))),
         round_seconds = v_rs, rounds_done = 0, next_round_at = b.started_at + make_interval(secs => v_rs)
   where id = p_battle;
  v_st := public.battle_opening_stance(v_def);
  if v_st <> 'FIGHT' then
    insert into public.battle_stances (battle_id, fleet_id, set_at, stance) values (p_battle, v_def, b.started_at, v_st);
  end if;
end
$body$;
$f$;
  comment on function public.battle_sheet_freeze(uuid, timestamptz) is '0357: at a battle''s open: the two sides'' hulls frozen on battles.sheet, the round clock, a defender''s opening stance. Called by public.battle_open for an ATTACK. Server-only.';

  execute $f$
create function public.battle_fight(p_battle uuid, p_rounds integer)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0357 (docs/COMBAT_LOG.md 3.1): THE ONE FIGHT OF A SHEET, to round p_rounds (null: to its end). public.fight_sides seeded (battle id, 1), the sheet's two sides, and each side's stance
-- for every round (public.battle_stance_at at the round's own instant, never now()). NO ENGINE STATE IS KEPT BETWEEN ROUNDS: round N is this, run to N, and a run to N is the first N
-- rows of a run to N + 1, as text. So the job on time, the job late, the door and a re-run all tell one fight. A side that only ever fought passes no order: the answer it was.
declare
  b      public.battles%rowtype;
  v_n    int := jsonb_array_length(public.wc('fight_ranges'));
  v_to   int;
  v_att  uuid;
  v_def  uuid;
  v_ao   jsonb := '[]'::jsonb;
  v_bo   jsonb := '[]'::jsonb;
  v_opts jsonb := '{}'::jsonb;
  g      int;
begin
  select * into b from public.battles where id = p_battle;
  if b.id is null or b.sheet is null then
    return null;
  end if;
  v_to := least(v_n, coalesce(p_rounds, v_n));
  if exists (select 1 from public.battle_stances s where s.battle_id = p_battle) then
    select bs.fleet_id into v_att from public.battle_sides bs where bs.battle_id = p_battle and bs.side = 'ATTACKER' and bs.how = 'OPENED';
    select bs.fleet_id into v_def from public.battle_sides bs where bs.battle_id = p_battle and bs.side = 'DEFENDER' and bs.how = 'OPENED';
    for g in 1 .. v_to loop
      v_ao := v_ao || to_jsonb(public.battle_stance_at(p_battle, v_def, b.started_at + make_interval(secs => g * b.round_seconds)));
      v_bo := v_bo || to_jsonb(public.battle_stance_at(p_battle, v_att, b.started_at + make_interval(secs => g * b.round_seconds)));
    end loop;
    if exists (select 1 from jsonb_array_elements_text(v_ao) e where e <> 'FIGHT') then v_opts := v_opts || jsonb_build_object('a_order', v_ao); end if;
    if exists (select 1 from jsonb_array_elements_text(v_bo) e where e <> 'FIGHT') then v_opts := v_opts || jsonb_build_object('b_order', v_bo); end if;
  end if;
  if p_rounds is not null then
    v_opts := v_opts || jsonb_build_object('rounds', greatest(1, p_rounds));
  end if;
  return public.fight_sides(p_battle, 1, b.sheet->'a', b.sheet->'b', v_opts);
end
$body$;
$f$;
  comment on function public.battle_fight(uuid, integer) is '0357: the one fight of a battle''s sheet, to a round or to its end: public.fight_sides over the frozen sides and the stances kept. Stable. Read by public.battle_advance, public.battle_resolve, world.battle. Server-only.';

  execute $f$
create function public.battle_advance(p_battle uuid, p_now timestamptz default now())
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0357 (docs/COMBAT_LOG.md 3.1): THE ROUNDS DUE, FOUGHT AND LOGGED. Under the battle's lock, for each round whose instant (started_at + g x round_seconds, never past the battle's
-- end) has come and that has no row:
--   a called ship that has come up by that instant joins the sheet with `from` = this round (public.battle_sides_come has just read her arrival, as the close reads it);
--   the sheet is fought to this round (public.battle_fight); its row g is written to public.battle_rounds at the round's own instant.
-- A fight that ended in a round, or before one (stood off, slipped, they broke, a side got away, a ransom), ends the battle THERE: resolves_at is brought in to that instant and the
-- caller (public.battle_resolve, THE one closer) closes it. Otherwise the boarding waits for resolves_at, and a called ship that came up after the last round is there for it
-- (`from` = the rounds + 1): THE JOIN RULE IS 0333's, on the sheet if arrives_at <= resolves_at. It writes nothing for a battle with no sheet, or not FIGHTING.
-- Answers the rounds it logged. One round a call when the job is on time; every round missed, in order, when it is late: the same rows either way.
declare
  b       public.battles%rowtype;
  v_n     int := jsonb_array_length(public.wc('fight_ranges'));
  g       int;
  v_due   timestamptz;
  v_f     jsonb;
  v_done  int := 0;
  v_come  boolean := false;
  s       record;
  v_h     jsonb;
begin
  select * into b from public.battles where id = p_battle for update;
  if b.id is null or b.status <> 'FIGHTING' or b.sheet is null then
    return 0;
  end if;
  loop
    g := b.rounds_done + 1;
    exit when g > v_n + 1;
    v_due := case when g > v_n then b.resolves_at else least(b.started_at + make_interval(secs => g * b.round_seconds), b.resolves_at) end;
    exit when v_due > p_now;
    -- the ships called: read where they are once a call, then each joins at the first round she is there for (g = the rounds + 1 is the boarding)
    if exists (select 1 from public.battle_sides bs where bs.battle_id = p_battle and bs.how = 'CALLED'
                  and not exists (select 1 from jsonb_array_elements(b.sheet->'a') e where e->>'fleet' = bs.fleet_id::text)) then
      if not v_come then
        perform public.battle_sides_come(p_battle, p_now);
        v_come := true;
      end if;
      for s in select bs.fleet_id from public.battle_sides bs
                where bs.battle_id = p_battle and bs.how = 'CALLED' and bs.arrives_at <= v_due
                  and not exists (select 1 from jsonb_array_elements(b.sheet->'a') e where e->>'fleet' = bs.fleet_id::text)
                order by bs.arrives_at, bs.fleet_id loop
        select coalesce(jsonb_agg(e.h || jsonb_build_object('from', g, 'fleet', s.fleet_id) order by e.o), '[]'::jsonb) into v_h
          from jsonb_array_elements(coalesce(voyage.fleet_hulls(s.fleet_id), '[]'::jsonb)) with ordinality e(h, o);
        b.sheet := jsonb_set(b.sheet, '{a}', (b.sheet->'a') || v_h);
        update public.battles set sheet = b.sheet where id = p_battle;
      end loop;
    end if;
    exit when g > v_n;   -- the boarding's instant: who is there is on the sheet, and the close fights it
    v_f := public.battle_fight(p_battle, g);
    if (v_f->>'rounds_fought')::int >= g then
      insert into public.battle_rounds (battle_id, g, at, "row") values (p_battle, g, v_due, v_f->'rounds'->(g - 1));
      v_done := v_done + 1;
    end if;
    if coalesce((v_f->>'open')::boolean, false) then
      b.rounds_done := g;
      b.next_round_at := least(b.started_at + make_interval(secs => (g + 1) * b.round_seconds), b.resolves_at);
    elsif coalesce((v_f->>'stood_off')::boolean, false) or coalesce((v_f->>'slipped')::boolean, false) or coalesce((v_f->>'broke_off')::boolean, false)
          or coalesce((v_f->>'fled')::boolean, false) or coalesce((v_f->>'paid')::boolean, false) then
      b.rounds_done := g;
      b.resolves_at := least(b.resolves_at, v_due);   -- it ended here
      b.next_round_at := b.resolves_at;
      update public.battles set rounds_done = b.rounds_done, next_round_at = b.next_round_at, resolves_at = b.resolves_at where id = p_battle;
      exit;
    else
      b.rounds_done := v_n;                           -- every round fought: the boarding, at the clock's end
      b.next_round_at := b.resolves_at;
    end if;
    update public.battles set rounds_done = b.rounds_done, next_round_at = b.next_round_at where id = p_battle;
  end loop;
  return v_done;
end
$body$;
$f$;
  comment on function public.battle_advance(uuid, timestamptz) is '0357: fights and logs every round of a battle that is due and not yet logged; brings the clock in when the fight ended in a round. Called by public.battle_resolve. Server-only.';

  execute $f$
create function public.battle_log(p_sheet jsonb, p_fight jsonb, p_side text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0357: A BATTLE'S LOG FROM ONE SIDE'S DECK, in the one shape a raid's log has (voyage.raid_extras, shape v 1: 0353), so ONE client component draws both. p_fight is
-- public.fight_sides' answer, where a is the side set upon. FOR THE SIDE THAT ATTACKED it is turned round (her rounds, her hull, her slip chance, her crew at the boarding) and handed
-- to the same leaf, and `end` is how it ended FOR HER: A_NONE (no fight), A_LOST (the other got away), FLED (her Flee got her away), A_BROKE (she broke off under fire), A_THROWN
-- (thrown back at the boarding), A_TERMS (the other paid), A_TOOK (boarded); and the log says `atk` so a reader knows whose deck it is. FOR THE SIDE SET UPON it is a raid's log as it stands (no door opens such a battle on a company yet).
-- A fight still open has no `end`. Numbers only; names no table.
declare
  v_open  boolean := coalesce((p_fight->>'open')::boolean, false);
  v_board jsonb := p_fight->'board';
  v_t     jsonb;
  v_foe   jsonb;
  v_log   jsonb;
  v_end   text;
begin
  if coalesce(p_side, '') <> 'ATTACKER' then
    v_foe := jsonb_build_object('name', coalesce(p_sheet->>'you', 'Ship'), 'ships', jsonb_array_length(p_sheet->'b'),
               'crew', (select coalesce(sum((e->>'crew')::numeric), 0) from jsonb_array_elements(p_sheet->'b') e),
               'hull', (select coalesce(sum((e->>'hull')::numeric), 0) from jsonb_array_elements(p_sheet->'b') e));
    v_log := voyage.raid_extras(p_sheet->'a', v_foe, case when v_open then p_fight - 'board' else p_fight end, '{"log": true}'::jsonb) -> 'log';
    return case when v_open then v_log - 'end' else v_log end;
  end if;
  v_t := jsonb_build_object(
    'outcome', p_fight->'outcome', 'stood_off', false, 'slipped', false, 'broke_off', false,
    'first', case p_fight->>'first' when 'A' then 'B' when 'B' then 'A' else coalesce(p_fight->>'first', 'BOTH') end,
    'rounds_fought', coalesce(p_fight->'rounds_fought', '0'::jsonb),
    'rounds', (select coalesce(jsonb_agg(jsonb_build_object('round', x.e->'round', 'range', x.e->'range', 'a', x.e->'b', 'b', x.e->'a')
                                         || case when x.e ? 'b_flee' then jsonb_build_object('flee', x.e->'b_flee') else '{}'::jsonb end order by x.o), '[]'::jsonb)
                 from jsonb_array_elements(coalesce(p_fight->'rounds', '[]'::jsonb)) with ordinality x(e, o)),
    'board', case when not v_open and jsonb_typeof(v_board) = 'object'
                  then jsonb_build_object('a_crew', v_board->'b_crew', 'b_crew', v_board->'a_crew', 'surrender', false,
                         'ratio', case when (v_board->>'ratio')::numeric > 0 then round(1 / (v_board->>'ratio')::numeric, 2) else 99 end) end,
    'hull_lost', jsonb_build_object('a', coalesce(p_fight->'hull_lost'->'b', '{}'::jsonb), 'b', coalesce(p_fight->'hull_lost'->'a', '{}'::jsonb)));
  v_foe := jsonb_build_object('name', coalesce(p_sheet->>'foe', 'Ship'), 'ships', jsonb_array_length(p_sheet->'a'),
             'crew', (select coalesce(sum((e->>'crew')::numeric), 0) from jsonb_array_elements(p_sheet->'a') e),
             'hull', (select coalesce(sum((e->>'hull')::numeric), 0) from jsonb_array_elements(p_sheet->'a') e));
  v_log := voyage.raid_extras(p_sheet->'b', v_foe, v_t, '{"log": true}'::jsonb) -> 'log';
  v_end := case when v_open then null
                when p_fight->>'outcome' = 'NO_FIGHT' or coalesce((p_fight->>'stood_off')::boolean, false) then 'A_NONE'
                when coalesce((p_fight->>'slipped')::boolean, false) or coalesce((p_fight->>'fled')::boolean, false) then 'A_LOST'
                when coalesce((p_fight->>'b_fled')::boolean, false) then 'FLED'
                when coalesce((p_fight->>'broke_off')::boolean, false) then 'A_BROKE'
                when coalesce((p_fight->>'paid')::boolean, false) then 'A_TERMS'
                else case p_fight->>'outcome' when 'DRIVEN_OFF' then 'A_THROWN' when 'RANSOM' then 'A_TERMS' else 'A_TOOK' end end;
  return (v_log - 'end') || '{"atk": true}'::jsonb || case when v_end is null then '{}'::jsonb else jsonb_build_object('end', v_end) end;
end
$body$;
$f$;
  comment on function public.battle_log(jsonb, jsonb, text) is '0357: a battle''s log from one side''s deck (the attacker''s is turned round), in a raid log''s shape (v 1), through voyage.raid_extras. Read by world.battle and public.battle_words. Names no table. Server-only.';

  -- ── 5. THE DOORS ──
  execute $f$
create function cmd.battle_stance(p_battle uuid, p_stance text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0357 (docs/COMBAT_LOG.md 3.3): HER STANCE IN A BATTLE. It advances the battle first (an act must not reason about a stale round: every round due is fought and logged, and the battle
-- closes if it is over), then keeps the stance; it takes hold from the NEXT round. FIGHT keeps fighting. FLEE: her guns fall silent, she takes each round's fire and rolls to slip
-- (public.fight_sides); away, the side that attacked has BROKEN OFF. PAY is for a side set upon only: the side that attacked started it. The stance she already holds writes no row and
-- still advances. {ok, stance, round_next, next_at} or the refusal envelope: E_NO_HOUSE, E_NOT_IN_USE (the switch off), E_BAD_STANCE, E_NO_BATTLE, E_NOT_YOUR_BATTLE, E_BATTLE_OVER.
declare
  v_player uuid := public.current_player_id();
  b        public.battles%rowtype;
  v_fleet  uuid;
  v_side   text;
  v_now    timestamptz;
  v_det    text;
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_HOUSE', 'error_message', 'Found a house first.', 'fixes', '[]'::jsonb);
  end if;
  begin
    if not public.attack_on() then
      perform cmd.refuse('E_NOT_IN_USE', 'battles are not in use');
    end if;
    if p_stance is null or p_stance not in ('FIGHT', 'FLEE', 'PAY') then
      perform cmd.refuse('E_BAD_STANCE', 'a stance is FIGHT or FLEE');
    end if;
    select * into b from public.battles where id = p_battle for update;
    if b.id is null or b.sheet is null then
      perform cmd.refuse('E_NO_BATTLE', 'there is no such battle');
    end if;
    select bs.fleet_id, bs.side into v_fleet, v_side
      from public.battle_sides bs join public.fleets f on f.id = bs.fleet_id
     where bs.battle_id = p_battle and bs.how = 'OPENED' and f.player_id = v_player;
    if v_fleet is null then
      perform cmd.refuse('E_NOT_YOUR_BATTLE', 'that battle is not yours');
    end if;
    if p_stance = 'PAY' and v_side = 'ATTACKER' then
      perform cmd.refuse('E_BAD_STANCE', 'the side that attacked cannot pay its way out');
    end if;
  exception when others then
    if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
    get stacked diagnostics v_det = pg_exception_detail;
    return cmd.refused_envelope(sqlerrm, v_det);
  end;
  -- the clock is read AFTER the battle's lock is held: no round fought under this lock can be due later than the stance written here
  v_now := clock_timestamp();
  perform public.battle_resolve(p_battle, v_now);
  select * into b from public.battles where id = p_battle;
  if b.status <> 'FIGHTING' then
    return cmd.refused_envelope('E_BATTLE_OVER: that battle is over', null);
  end if;
  if public.battle_stance_at(p_battle, v_fleet, 'infinity') is distinct from p_stance then
    insert into public.battle_stances (battle_id, fleet_id, set_at, stance) values (p_battle, v_fleet, v_now, p_stance)
    on conflict (battle_id, fleet_id, set_at) do update set stance = excluded.stance;
  end if;
  return jsonb_build_object('ok', true, 'stance', p_stance, 'round_next', b.rounds_done + 1, 'next_at', coalesce(b.next_round_at, b.resolves_at));
end
$body$;
$f$;
  comment on function cmd.battle_stance(uuid, text) is
    '0357: her stance in a battle she is in: FIGHT or FLEE (PAY for a side set upon). Advances the battle first; takes hold from the next round. {ok, stance, round_next, next_at} or the refusal envelope. Dark: E_NOT_IN_USE.';
  revoke all on function cmd.battle_stance(uuid, text) from public, anon;
  grant execute on function cmd.battle_stance(uuid, text) to authenticated;

  execute $f$
create function world.battle(p_fleet uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0357 (docs/COMBAT_LOG.md 3.4, 6.1): THE READ THE BATTLE CARD POLLS, for the caller's own fleet: her latest battle fought round by round. It never advances: the minute job and the
-- stance door do. Not her fleet, or no such battle: {on: false}.
--   battle, status (FIGHTING, RESOLVED, BROKEN_OFF), side, foe (the fleet set upon), word (the pre-fight read: public.attack_word, as the preview printed it)
--   started_at, resolves_at, now, round_seconds, rounds, rounds_done, next_at (the next round, or the boarding), next_range (LONG, MEDIUM, CLOSE; null at the boarding)
--   stance (what the next round will be fought under), may (the stances the door takes from her)
--   log    the fight so far from her deck (public.battle_log, shape v 1). While FIGHTING it has no `end` and no boarding: nothing is told before its round.
--   closed: outcome, loot, crew_lost, navy (the line), as the report has them.
declare
  v_player uuid := public.current_player_id();
  b        public.battles%rowtype;
  v_side   text;
  v_f      jsonb;
  v_n      int := jsonb_array_length(public.wc('fight_ranges'));
begin
  if v_player is null then
    return jsonb_build_object('on', false);
  end if;
  select bt.* into b
    from public.battle_sides bs
    join public.battles bt on bt.id = bs.battle_id
    join public.fleets f on f.id = bs.fleet_id
   where bs.fleet_id = p_fleet and bs.how = 'OPENED' and f.player_id = v_player and bt.sheet is not null
   order by bt.started_at desc, bt.id limit 1;
  if b.id is null then
    return jsonb_build_object('on', false);
  end if;
  select bs.side into v_side from public.battle_sides bs where bs.battle_id = b.id and bs.fleet_id = p_fleet;
  if b.status = 'FIGHTING' then
    -- the fight to the rounds logged, and nothing past them: no boarding, no ending
    v_f := public.battle_fight(b.id, greatest(1, b.rounds_done)) - 'board';
    if b.rounds_done = 0 then
      v_f := v_f || jsonb_build_object('rounds', '[]'::jsonb, 'rounds_fought', 0, 'hull_lost', jsonb_build_object('a', '{}'::jsonb, 'b', '{}'::jsonb));
    end if;
    v_f := v_f || jsonb_build_object('open', true, 'outcome', null);
  else
    v_f := b.result;
  end if;
  return jsonb_build_object(
    'on', true, 'battle', b.id, 'status', b.status, 'side', v_side, 'foe', b.sheet->'foe', 'word', b.sheet->'word',
    'started_at', b.started_at, 'resolves_at', b.resolves_at, 'now', now(), 'round_seconds', b.round_seconds, 'rounds', v_n, 'rounds_done', b.rounds_done,
    'next_at', case when b.status = 'FIGHTING' then coalesce(b.next_round_at, b.resolves_at) end,
    'next_range', case when b.status = 'FIGHTING' and b.rounds_done < v_n and b.next_round_at is distinct from b.resolves_at then public.wc('fight_ranges') -> b.rounds_done ->> 0 end,
    'stance', public.battle_stance_at(b.id, p_fleet, 'infinity'),
    'may', case when v_side = 'ATTACKER' then '["FIGHT", "FLEE"]'::jsonb else '["FIGHT", "FLEE", "PAY"]'::jsonb end,
    'log', public.battle_log(b.sheet, v_f, v_side))
    || case when b.status = 'FIGHTING' then '{}'::jsonb
            else jsonb_build_object('outcome', b.result->'outcome', 'loot', coalesce(b.result->'loot', '0'::jsonb), 'crew_lost', coalesce(b.result->'crew_lost', '0'::jsonb),
                                    'navy', b.result #> '{navy,line}') end;
end
$body$;
$f$;
  comment on function world.battle(uuid) is
    '0357: the read a battle card polls, for the caller''s own fleet: her latest battle fought round by round: the clock, her stance, the pre-fight word, the log so far (shape v 1, her deck), and the result once closed. Stable; it never advances. Not hers, or none: {on: false}.';
  revoke all on function world.battle(uuid) from public, anon;
  grant execute on function world.battle(uuid) to authenticated;

  revoke all on function voyage.hold_free_hours(uuid) from public, anon, authenticated;
  revoke all on function voyage.hold_cut(uuid, timestamptz, timestamptz) from public, anon, authenticated;
  revoke all on function public.battle_opening_stance(uuid) from public, anon, authenticated;
  revoke all on function public.battle_stance_at(uuid, uuid, timestamptz) from public, anon, authenticated;
  revoke all on function public.battle_sheet_freeze(uuid, timestamptz) from public, anon, authenticated;
  revoke all on function public.battle_fight(uuid, integer) from public, anon, authenticated;
  revoke all on function public.battle_advance(uuid, timestamptz) from public, anon, authenticated;
  revoke all on function public.battle_log(jsonb, jsonb, text) from public, anon, authenticated;

  -- ── 6. THE RE-CUTS (each hunk once) ──
  for fd in select * from defs_0357 x order by x.fn loop
    v_def := fd.def;
    for h in select * from hunks_0357 x where x.fn = fd.fn order by x.n loop
      v_m := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
      if v_m <> 1 then
        raise exception '0357 slice: hunk % of % occurs % time(s), expected exactly 1: the deployed body is not what this migration was written against', h.n, fd.fn, v_m;
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    execute v_def;
  end loop;

  -- ── 7. THE SELF-ASSERT: the catalog ──
  for fd in select * from defs_0357 order by fn loop
    v_def := replace(pg_get_functiondef(fd.fn::regprocedure), E'\r', '');
    for h in select * from hunks_0357 x where x.fn = fd.fn order by x.n desc loop
      if (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new) is distinct from 1 then
        raise exception '0357 self-assert FAIL: hunk % of % is not in the new body exactly once', h.n, h.fn;
      end if;
      v_def := replace(v_def, h.new, h.old);
    end loop;
    if v_def is distinct from fd.def then
      raise exception '0357 self-assert FAIL: % does not reverse to its pre-image', fd.fn;
    end if;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef, coalesce(pr.proconfig::text, '') as cfg
      into v_p from pg_proc pr where pr.oid = fd.fn::regprocedure;
    if v_p.acl is distinct from fd.acl or v_p.vol is distinct from fd.vol or v_p.secdef is distinct from fd.secdef or v_p.cfg is distinct from fd.cfg then
      raise exception '0357 self-assert FAIL: % changed its ACL, volatility, definer or config', fd.fn;
    end if;
  end loop;
  if (select count(*) from hunks_0357) is distinct from 23 then
    raise exception '0357 self-assert FAIL: % hunks, not 23', (select count(*) from hunks_0357);
  end if;
  if exists (select 1 from hunks_0357 x where not exists (select 1 from defs_0357 d where d.fn = x.fn)) then
    raise exception '0357 self-assert FAIL: a hunk names a function this file does not cut';
  end if;

  v_ms := v_ms || jsonb_build_object('made_and_cut', round(extract(epoch from clock_timestamp() - v_tp) * 1000)); v_tp := clock_timestamp();

  -- ── 8. ENGINE PARITY, BOUNDED BY THE CLOCK: the kept copy of the live engine against the new one, as text, on 0320's matrix, read day by day across every cell (as 0353 read it).
  --    Five ways a fight: no option; the sizing-up; and, on the scored fights, 0353's own options (a_order FLEE, a_order PAY, a round limit). Then the new options said aloud and
  --    neutral (b_order FIGHT, every hull `from` 1) against the old answer. It FAILS under c_min_pairs or if an ending was not met. The whole matrix: proof 60. ──
  create temp table matrix_0357 on commit drop as
  with rh as materialized (select r.r, voyage.raider_hulls(r.r) as b from (values (6.0), (12.0), (18.0), (24.0), (10.0), (60.0), (120.0)) r(r))
  select row_number() over (order by m.d, m.k)::int as i, m.*
    from (select s.k * 10 + r.k as k, s.ships as a, (select rh.b from rh where rh.r = r.r) as b, s.esc, r.r, d
            from (values (1, v_carlat, 11.74::numeric), (2, v_barca, 6.66::numeric)) s(k, ships, esc)
           cross join (values (1, 6.0), (2, 12.0), (3, 18.0), (4, 24.0)) r(k, r)
           cross join generate_series(1, 120) d
          union all
          select 30 + r.k, v_three, (select rh.b from rh where rh.r = r.r), 30.5::numeric, r.r, d
            from (values (1, 10.0), (2, 24.0), (3, 60.0), (4, 120.0)) r(k, r)
           cross join generate_series(1, 30) d
          union all
          select 40, v_three, v_two, null::numeric, null::numeric, d from generate_series(1, 40) d) m;
  if (select count(*) from matrix_0357) is distinct from 1120 then
    raise exception '0357 self-assert FAIL: the matrix is % fights, not 1120', (select count(*) from matrix_0357);
  end if;

  v_tg := clock_timestamp();
  for v_x in select * from matrix_0357 m order by m.i loop
    exit when clock_timestamp() - v_tg > c_guard_parity;
    v_n := v_n + 1;
    v_b := case when v_x.r is null then '{}'::jsonb else jsonb_build_object('a_score', v_x.esc, 'b_score', v_x.r) end;
    foreach v_o in array array['{}'::jsonb, v_b, v_b || '{"a_order": "FLEE"}'::jsonb, v_b || '{"a_order": "PAY"}'::jsonb, v_b || jsonb_build_object('rounds', 1 + (v_x.i % 6))] loop
      v_old := pg_temp.fight_sides_old_0357(c_seed, v_x.d, v_x.a, v_x.b, v_o);
      v_new := public.fight_sides(c_seed, v_x.d, v_x.a, v_x.b, v_o);
      if v_old::text is distinct from v_new::text then
        raise exception '0357 self-assert FAIL: ENGINE PARITY: a fight changed (day %, options %): % against %', v_x.d, v_o, v_old, v_new;
      end if;
      v_pairs := v_pairs + 1;
      if v_o = v_b then
        v_kinds := jsonb_set(v_kinds, array[v_old ->> 'outcome'], to_jsonb(coalesce((v_kinds ->> (v_old ->> 'outcome'))::int, 0) + 1));
        -- the new options, said aloud and neutral, are the old answer
        v_f := public.fight_sides(c_seed, v_x.d,
                 (select jsonb_agg(e.h || '{"from": 1}'::jsonb order by e.o) from jsonb_array_elements(v_x.a) with ordinality e(h, o)),
                 v_x.b, v_o || '{"b_order": "FIGHT"}'::jsonb);
        if v_old::text is distinct from v_f::text then
          raise exception '0357 self-assert FAIL: ENGINE PARITY: b_order FIGHT and from 1, said aloud, changed a fight (day %): % against %', v_x.d, v_old, v_f;
        end if;
        v_pairs := v_pairs + 1;
      end if;
    end loop;
  end loop;
  if v_pairs < c_min_pairs then
    raise exception '0357 self-assert FAIL: ENGINE PARITY compared only % pair(s) in % (the least that proves anything is %): this database is too slow now, deploy it again', v_pairs, c_guard_parity, c_min_pairs;
  end if;
  if not (v_kinds ?& array['EVADED', 'DRIVEN_OFF', 'RANSOM', 'PLUNDERED']) then
    raise exception '0357 self-assert FAIL: the % fights compared met too few endings to prove anything: %', v_n, v_kinds;
  end if;
  v_ms := v_ms || jsonb_build_object('engine_parity', round(extract(epoch from clock_timestamp() - v_tp) * 1000)); v_tp := clock_timestamp();

  -- ── 8b. THE PREFIX WITH BOTH STANCE LISTS, THE SIDE THAT CLOSES RUNNING, AND `from`, bounded by c_guard_orders. The whole matrix and every limit: proof 60. ──
  v_tg := clock_timestamp();
  for v_x in select * from matrix_0357 m order by m.i loop
    exit when clock_timestamp() - v_tg > c_guard_orders;
    v_ord_n := v_ord_n + 1;
    v_b := case when v_x.r is null then '{}'::jsonb else jsonb_build_object('a_score', v_x.esc, 'b_score', v_x.r) end;
    v_new := public.fight_sides(c_seed, v_x.d, v_x.a, v_x.b, v_b);

    -- the side that closes runs from the first round
    v_f := public.fight_sides(c_seed, v_x.d, v_x.a, v_x.b, v_b || '{"b_order": "FLEE"}'::jsonb);
    if (v_new ->> 'stood_off')::boolean or (v_new ->> 'slipped')::boolean then
      if v_f::text is distinct from v_new::text then
        raise exception '0357 self-assert FAIL: b_order FLEE changed a day that never came to a round: %', v_f;
      end if;
    else
      v_pf := round(public.fight_flee_chance((select max((e ->> 'sighting')::numeric) from jsonb_array_elements(v_x.b) e)
                                             - (select max((e ->> 'sighting')::numeric) from jsonb_array_elements(v_x.a) e)), 4);
      if v_f -> 'hull_lost' -> 'a' is distinct from '{}'::jsonb or (v_f -> 'hits' ->> 'b')::int is distinct from 0
         or exists (select 1 from jsonb_array_elements(v_f -> 'rounds') e
                     where (e -> 'b' ->> 'fired')::int is distinct from 0
                        or (e ->> 'b_flee')::numeric is distinct from v_pf) then
        raise exception '0357 self-assert FAIL: a side that closes and runs fired, or a round''s b_flee is not the rule''s % : %', v_pf, v_f;
      end if;
      if coalesce((v_f ->> 'b_fled')::boolean, false) then
        v_bfled := v_bfled + 1;
        if (v_f ->> 'broke_off')::boolean is not true or v_f -> 'board' is distinct from 'null'::jsonb or coalesce(v_f ->> 'outcome', '') not in ('EVADED', 'DRIVEN_OFF') then
          raise exception '0357 self-assert FAIL: a break-off that got away is not broke_off with no boarding: %', v_f;
        end if;
      else
        v_bcaught := v_bcaught + 1;
        if v_f ? 'b_fled' or (not (v_f ->> 'broke_off')::boolean and jsonb_typeof(v_f -> 'board') is distinct from 'object') then
          raise exception '0357 self-assert FAIL: a side that ran and never got away was neither broken nor boarded: %', v_f;
        end if;
      end if;
    end if;

    -- the prefix: both sides hold a list a round (they change their minds), and a run to round N is the first N rows of the full run, as text
    v_g := v_b || jsonb_build_object('a_order', case v_x.i % 3 when 0 then '["FIGHT", "FLEE", "FLEE", "FIGHT"]'::jsonb when 1 then '["FLEE", "FIGHT"]'::jsonb else '["FIGHT"]'::jsonb end,
                                     'b_order', case v_x.i % 4 when 0 then '["FIGHT", "FIGHT", "FLEE"]'::jsonb when 1 then '["FLEE", "FIGHT", "FIGHT", "FLEE"]'::jsonb when 2 then '["FIGHT"]'::jsonb else '["FIGHT", "FLEE"]'::jsonb end);
    v_m := 1 + (v_x.i % 7);
    v_old := public.fight_sides(c_seed, v_x.d, v_x.a, v_x.b, v_g);
    v_f := public.fight_sides(c_seed, v_x.d, v_x.a, v_x.b, v_g || jsonb_build_object('rounds', v_m));
    v_pre_n := v_pre_n + 1;
    if (v_old ->> 'rounds_fought')::int > v_m then
      v_open_n := v_open_n + 1;
      if not coalesce((v_f ->> 'open')::boolean, false) or v_f -> 'outcome' is distinct from 'null'::jsonb or v_f -> 'board' is distinct from 'null'::jsonb or (v_f ->> 'rounds_fought')::int is distinct from v_m
         or (v_f -> 'rounds')::text is distinct from (select jsonb_agg(e order by o) from jsonb_array_elements(v_old -> 'rounds') with ordinality q(e, o) where o <= v_m)::text then
        raise exception '0357 self-assert FAIL: THE PREFIX: a run to round % is not the first % rows of the full run, left open: % against %', v_m, v_m, v_f, v_old;
      end if;
    elsif v_f::text is distinct from v_old::text then
      raise exception '0357 self-assert FAIL: THE PREFIX: a round limit the fight never reached changed it (limit %): % against %', v_m, v_f, v_old;
    end if;

    -- a called ship (the fights of real hulls): on the sheet from round 3, she is not struck and fires nothing before it; never come, she loses nothing and boards nobody
    if v_x.r is null then
      v_from_n := v_from_n + 1;
      v_g := jsonb_set(v_x.a, '{1,from}', '3'::jsonb);
      v_f := public.fight_sides(c_seed, v_x.d, v_g, v_x.b, '{}'::jsonb);
      if exists (select 1 from jsonb_array_elements(v_f -> 'rounds') e, jsonb_array_elements(e -> 'a' -> 'struck') st where (e ->> 'round')::int < 3 and (st ->> 0)::int = 2)
         or exists (select 1 from jsonb_array_elements(v_f -> 'rounds') e where (e ->> 'round')::int < 3 and (e -> 'a' ->> 'can')::int > 1)
         -- at her round she is there whole: the side's hull left is at least hers, less what that round took
         or exists (select 1 from jsonb_array_elements(v_f -> 'rounds') e where (e ->> 'round')::int = 3 and (e -> 'a' ->> 'left')::numeric + (e -> 'b' ->> 'dealt')::numeric < (v_g -> 1 ->> 'hull')::numeric - 0.01) then
        raise exception '0357 self-assert FAIL: a called ship fought before her round, or was not there at it: %', v_f;
      end if;
      -- the side's starting hull is each hull once: those there from the first round, and she from her own round if the fight came to it
      if (v_f -> 'hull' ->> 'a_start')::numeric is distinct from
           (select sum((e ->> 'hull')::numeric) from jsonb_array_elements(v_g) e where coalesce((e ->> 'from')::int, 1) <= greatest(1, (v_f ->> 'rounds_fought')::int)) then
        raise exception '0357 self-assert FAIL: with a called ship the side''s starting hull is not each hull once: % of %', v_f -> 'hull', v_g;
      end if;
      v_f := public.fight_sides(c_seed, v_x.d, jsonb_set(v_x.a, '{1,from}', '99'::jsonb), v_x.b, '{}'::jsonb);
      if v_f -> 'hull_lost' -> 'a' ? (v_x.a -> 1 ->> 'id') or (v_f -> 'board' ->> 'a_crew')::numeric > (v_x.a -> 0 ->> 'crew')::numeric + (v_x.a -> 2 ->> 'crew')::numeric then
        raise exception '0357 self-assert FAIL: a called ship that never came lost hull or boarded: %', v_f;
      end if;
    end if;
  end loop;
  if v_ord_n < c_min_orders or v_bfled = 0 or v_bcaught = 0 or v_open_n = 0 or v_open_n = v_pre_n or v_from_n = 0 then
    raise exception '0357 self-assert FAIL: in % the stances ran on % fight(s) (the least is %) and must meet a break-off away (%), one caught (%), an open and a finished prefix (% of %) and a called ship (%)',
      c_guard_orders, v_ord_n, c_min_orders, v_bfled, v_bcaught, v_open_n, v_pre_n, v_from_n;
  end if;
  v_ms := v_ms || jsonb_build_object('stances_prefix', round(extract(epoch from clock_timestamp() - v_tp) * 1000)); v_tp := clock_timestamp();

  -- ── 9. THE GUARDS ──
  -- 0320's own test on the new engine body, the same allow-list: it names no table
  select regexp_replace(p.prosrc, '--[^\n]*', '', 'g') into v_src from pg_proc p where p.oid = c_eng::regprocedure;
  if v_src ~* '\m(join|update|insert|delete|execute)\M' or v_src ~* '\mfrom\s+(?!generate_subscripts\(|public\.fight_volley\()' then
    raise exception '0357 self-assert FAIL: the engine names a table';
  end if;
  if exists (select 1 from regexp_matches(v_src, '\m((public|voyage|world|cmd)\.[a-z_]+)', 'g') w(a)
              where w.a[1] not in ('public.wc', 'public.wc_num', 'public.fight_volley', 'public.armour_soak', 'voyage.rng')) then
    raise exception '0357 self-assert FAIL: the engine reads through something that is not world_config';
  end if;
  select regexp_replace(p.prosrc, '--[^\n]*', '', 'g') into v_src from pg_proc p where p.oid = 'public.battle_log(jsonb,jsonb,text)'::regprocedure;
  if v_src ~* '\m(join|update|insert|delete|execute)\M' or v_src ~* '\mfrom\s+(?!jsonb_array_elements(_text)?\()' then
    raise exception '0357 self-assert FAIL: public.battle_log names a table';
  end if;
  -- NO PLAYER FIGHTS A PLAYER: the two refusals stand in the two live bodies, word for word; public.attack_for and public.attack_close are not cut at all (the digest below)
  if (select p.prosrc from pg_proc p where p.oid = 'public.battle_open(text,uuid,uuid,timestamp with time zone)'::regprocedure)
       not like '%if not (select p.is_npc from public.players p where p.id = d.player_id) then%raise exception ''E_HUMAN_TARGET: no player fights another player''%'
     or (select p.prosrc from pg_proc p where p.oid = 'public.attack_for(uuid,uuid,uuid,integer,timestamp with time zone)'::regprocedure)
       not like '%if v_kind = ''COMPANY'' then%perform cmd.refuse(''E_HUMAN_TARGET'', ''no player attacks another player'');%' then
    raise exception '0357 self-assert FAIL: a refusal of a human target is gone';
  end if;
  -- a sheet is written in one place, read through one fight; the rounds table has one writer; a stance two
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prosrc ~ 'insert into public\.battle_rounds'
                and p.oid is distinct from 'public.battle_advance(uuid,timestamp with time zone)'::regprocedure)
     or exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prosrc ~ 'insert into public\.battle_stances'
                   and p.oid <> all (array['cmd.battle_stance(uuid,text)'::regprocedure::oid, 'public.battle_sheet_freeze(uuid,timestamp with time zone)'::regprocedure::oid])) then
    raise exception '0357 self-assert FAIL: the log or a stance is written in another place';
  end if;
  -- the hold has one caller chain, and each link is behind the switch: voyage.hold <- public.battle_stop <- public.battle_open (attack_on) and public.navy_call <- public.battle_open
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname in ('public', 'cmd', 'world', 'voyage') and regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~ 'voyage\.hold\('
                and p.oid is distinct from 'public.battle_stop(uuid,timestamp with time zone,timestamp with time zone)'::regprocedure)
     or exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname in ('public', 'cmd', 'world', 'voyage') and regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~ 'public\.battle_stop\('
                   and p.oid <> all (array['public.battle_open(text,uuid,uuid,timestamp with time zone)'::regprocedure::oid, 'public.navy_call(uuid,uuid,timestamp with time zone,timestamp with time zone)'::regprocedure::oid]))
     or exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname in ('public', 'cmd', 'world', 'voyage') and regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~ 'public\.(navy_call|battle_sheet_freeze)\('
                   and p.oid is distinct from 'public.battle_open(text,uuid,uuid,timestamp with time zone)'::regprocedure) then
    raise exception '0357 self-assert FAIL: a hold, a call of the navy or a sheet has a caller that is not behind public.battle_open';
  end if;
  -- no client calls a new function but the two doors, each in the registry once
  if exists (select 1 from unnest(c_new_fns) f cross join unnest(array['anon', 'authenticated']) r(role)
              where has_function_privilege(r.role, f, 'execute') and not (r.role = 'authenticated' and f = any (c_doors))) then
    raise exception '0357 self-assert FAIL: a client may call a new function that is not a door, or anon may call a door';
  end if;
  if exists (select 1 from unnest(c_doors) f where not has_function_privilege('authenticated', f, 'execute'))
     or (select count(*) from public.client_rpc_entry_points()) is distinct from v_entry + 2
     or (select count(*) from public.client_rpc_entry_points() e where e.fn = any (array['cmd.battle_stance(uuid,text)'::regprocedure, 'world.battle(uuid)'::regprocedure])) is distinct from 2 then
    raise exception '0357 self-assert FAIL: the two doors are not granted to authenticated and registered once each';
  end if;
  if (select p.provolatile from pg_proc p where p.oid = 'world.battle(uuid)'::regprocedure) is distinct from 's'
     or (select p.provolatile from pg_proc p where p.oid = 'public.battle_fight(uuid,integer)'::regprocedure) is distinct from 's'
     or (select p.provolatile from pg_proc p where p.oid = 'voyage.hold_free_hours(uuid)'::regprocedure) is distinct from 's' then
    raise exception '0357 self-assert FAIL: a read is not STABLE';
  end if;
  if has_table_privilege('anon', 'public.battle_rounds', 'select,insert,update,delete') or has_table_privilege('authenticated', 'public.battle_rounds', 'select,insert,update,delete')
     or has_table_privilege('anon', 'public.battle_stances', 'select,insert,update,delete') or has_table_privilege('authenticated', 'public.battle_stances', 'select,insert,update,delete')
     or not (select c.relrowsecurity from pg_class c where c.oid = 'public.battle_rounds'::regclass)
     or not (select c.relrowsecurity from pg_class c where c.oid = 'public.battle_stances'::regclass)
     or (select count(*) from public.client_write_grants()) is distinct from 0 then
    raise exception '0357 self-assert FAIL: a client can read or write a new table, or it has no row level security';
  end if;
  if exists (select 1 from public.battle_rounds) or exists (select 1 from public.battle_stances) then
    raise exception '0357 self-assert FAIL: a round or a stance exists at the deploy';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (select f::regprocedure::oid from unnest(c_cut_fns || c_new_fns) f)) is distinct from v_fn_before then
    raise exception '0357 self-assert FAIL: a function this file does not name moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key <> all (c_knobs)) is distinct from v_cfg_before
     or (select count(*) from public.world_config c where c.key = any (c_knobs)) is distinct from array_length(c_knobs, 1)
     or public.attack_on() then
    raise exception '0357 self-assert FAIL: an existing world_config row moved, the knob of this file is missing, or attacks are not dark';
  end if;

  v_ms := v_ms || jsonb_build_object('guards', round(extract(epoch from clock_timestamp() - v_tp) * 1000)); v_tp := clock_timestamp();

  -- ── 10. THE PROBE, on this file's own rows, rolled back by a raised sentinel ──
  begin
    select p.id into v_lis from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR';
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values (c_uid, 'Casa da Ronda 0357', (select n.id from public.nations n where n.code = 'PRT'), 5000, false) returning id into v_pl;
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values (c_uid2, 'Casa Vizinha 0357', (select n.id from public.nations n where n.code = 'PRT'), 5000, false) returning id into v_pl2;
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values (null, 'Casa Mercante 0357', (select n.id from public.nations n where n.code = 'PRT'), 0, true) returning id into v_npc;
    v_fl := public.form_fleet(v_pl, 'Ronda', v_lis);
    perform public.commission_ship(v_pl, v_fl, 'barca', 'Ronda', true, true);
    v_fl2 := public.form_fleet(v_pl2, 'Vizinha', v_lis);
    perform public.commission_ship(v_pl2, v_fl2, 'barca', 'Vizinha', true, true);
    v_nfl := public.form_fleet(v_npc, 'Mercante', v_lis);
    perform public.commission_ship(v_npc, v_nfl, 'barca', 'Mercante', true, true);
    update public.fleets set status = 'ANCHORED', port_id = null, lat = 38.5, lon = -9.6 where id in (v_fl2, v_nfl);
    v_t := date_trunc('second', now());

    -- (a) DARK, OLD AGAINST NEW: the job, the closer and the open with the switch off; the two doors
    if public.tick_battles(v_t) is distinct from 0 or pg_temp.tick_battles_old_0357(v_t) is distinct from 0
       or public.battle_resolve(gen_random_uuid(), v_t) is not false or pg_temp.battle_resolve_old_0357(gen_random_uuid(), v_t) is not false
       or public.battle_advance(gen_random_uuid(), v_t) is distinct from 0 or public.battle_fight(gen_random_uuid(), null) is not null then
      raise exception '0357 self-assert FAIL: dark, the job, the closer or the advance did something';
    end if;
    begin perform public.battle_open('ATTACK', v_fl, v_nfl, v_t); v_e1 := 'opened'; exception when others then v_e1 := sqlerrm; end;
    begin perform pg_temp.battle_open_old_0357('ATTACK', v_fl, v_nfl, v_t); v_e2 := 'opened'; exception when others then v_e2 := sqlerrm; end;
    if v_e1 is distinct from v_e2 or v_e1 not like 'E_NOT_YET:%' then
      raise exception '0357 self-assert FAIL: dark, public.battle_open old and new: % against %', v_e2, v_e1;
    end if;
    begin perform public.attack_for(v_pl, v_fl, v_nfl, null, v_t); v_e1 := 'attacked'; exception when others then v_e1 := sqlerrm; end;
    if v_e1 not like 'E_NOT_IN_USE:%' then
      raise exception '0357 self-assert FAIL: dark, public.attack_for answered %', v_e1;
    end if;
    perform cmd.assume_identity(c_uid);
    if cmd.battle_stance(gen_random_uuid(), 'FLEE') ->> 'error_code' is distinct from 'E_NOT_IN_USE' or world.battle(v_fl) is distinct from '{"on": false}'::jsonb
       or exists (select 1 from public.battles b where b.sheet is not null)
       or exists (select 1 from public.battle_rounds) or exists (select 1 from public.battle_stances) then
      raise exception '0357 self-assert FAIL: dark, the stance door or the read did something';
    end if;

    -- (b) THE DAY COUNT, OLD AGAINST NEW, on a voyage never held (a stub row of this probe, with a calm's delay), at five instants
    v_voy := gen_random_uuid();
    insert into public.voyages (id, fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta, status, origin_port_id, dest_port_id)
    values (v_voy, v_fl, v_pl, jsonb_build_array(jsonb_build_object('nm', 600, 'sea_id', (select s.id from public.seas s order by s.code limit 1), 'danger', 0)),
            600, '[5]', v_t - interval '5 minutes', v_t + interval '5 minutes', 'ARRIVED', v_lis, v_lis);
    insert into public.voyage_events (voyage_id, day_index, kind, payload, resolved_at) values (v_voy, 1, 'CALM', jsonb_build_object('delay_hours', 36), v_t);
    perform voyage.recompute_eta(v_voy);
    v_days := voyage.total_days(v_voy);
    v_m := voyage.days_complete(v_voy, v_t + interval '1 day');
    if v_days is distinct from pg_temp.total_days_old_0357(v_voy) or voyage.hold_free_hours(v_voy) is distinct from 0::numeric
       or exists (select 1 from generate_series(0, 4) k
                   where voyage.days_complete(v_voy, v_t + make_interval(mins => k * 4 - 5)) is distinct from pg_temp.days_complete_old_0357(v_voy, v_t + make_interval(mins => k * 4 - 5))
                      or voyage.arrival_at(v_voy, v_t + make_interval(mins => k * 4 - 5)) is distinct from pg_temp.arrival_at_old_0357(v_voy, v_t + make_interval(mins => k * 4 - 5))) then
      raise exception '0357 self-assert FAIL: with no hold the day count moved: % days against %', v_days, pg_temp.total_days_old_0357(v_voy);
    end if;
    -- A HOLD THAT BURNS NOTHING: a hold's row as voyage.hold writes it, with and without `free`: the old count grows by the hold, the new one is the count of the voyage never held,
    -- and the eta moves by the hold either way
    insert into public.voyage_events (voyage_id, day_index, kind, payload, resolved_at)
    values (v_voy, voyage.hold_floor() + 1, 'BATTLE', jsonb_build_object('delay_hours', 160, 'from_day', 2, 'held_from', v_t, 'held_until', v_t + interval '10 minutes', 'free', true), v_t);
    perform voyage.recompute_eta(v_voy);
    v_days_old := pg_temp.total_days_old_0357(v_voy);
    if voyage.total_days(v_voy) is distinct from v_days or v_days_old is distinct from v_days + 7 or voyage.hold_free_hours(v_voy) is distinct from 160::numeric
       or voyage.days_complete(v_voy, v_t + interval '2 days') is distinct from v_m
       or (select v.delay_hours from public.voyages v where v.id = v_voy) is distinct from 196::numeric then
      raise exception '0357 self-assert FAIL: a free hold of 160 hours: % days new (% unheld), % old, free hours %', voyage.total_days(v_voy), v_days, v_days_old, voyage.hold_free_hours(v_voy);
    end if;
    v_note := format('a 160-hour hold: %s days before this file, %s after (the voyage never held: %s)', v_days_old, voyage.total_days(v_voy), v_days);

    -- (c) LIT (here only; rolled back). NO PLAYER FIGHTS A PLAYER, by either door.
    update public.world_config set value = 'true'::jsonb where key = 'attack_enabled';
    begin perform public.battle_open('ATTACK', v_fl, v_fl2, v_t); v_e1 := 'opened'; exception when others then v_e1 := sqlerrm; end;
    begin perform public.attack_for(v_pl, v_fl, v_fl2, null, v_t); v_e2 := 'attacked'; exception when others then v_e2 := sqlerrm; end;
    if v_e1 not like 'E_HUMAN_TARGET:%' or v_e2 not like 'E_HUMAN_TARGET:%' or exists (select 1 from public.battles) then
      raise exception '0357 self-assert FAIL: A PLAYER COULD FIGHT A PLAYER: battle_open %, attack_for %', v_e1, v_e2;
    end if;

    -- (d) A BATTLE ROUND BY ROUND: her barca against a merchant's at anchor. The sheet, the clock, the stance door, three rounds logged, each the re-run's row. It is not closed here
    --     (the close is public.attack_close's, on a real target: proof 60).
    v_bat := public.battle_open('ATTACK', v_fl, v_nfl, v_t);
    select to_jsonb(b) into v_r from public.battles b where b.id = v_bat;
    if jsonb_array_length(v_r -> 'sheet' -> 'a') is distinct from 1 or jsonb_array_length(v_r -> 'sheet' -> 'b') is distinct from 1
       or (v_r -> 'sheet' -> 'a')::text is distinct from voyage.fleet_hulls(v_nfl)::text or (v_r -> 'sheet' -> 'b')::text is distinct from voyage.fleet_hulls(v_fl)::text
       or (v_r ->> 'round_seconds')::int is distinct from 60 or (v_r ->> 'rounds_done')::int is distinct from 0
       or (v_r ->> 'resolves_at')::timestamptz is distinct from v_t + make_interval(secs => 60 * (jsonb_array_length(public.wc('fight_ranges')) + 1))
       or (v_r ->> 'next_round_at')::timestamptz is distinct from v_t + interval '60 seconds'
       or (select f.busy_until from public.fleets f where f.id = v_fl) is distinct from (v_r ->> 'resolves_at')::timestamptz
       or exists (select 1 from public.battle_stances) then
      raise exception '0357 self-assert FAIL: the sheet or the clock at the open: %', v_r;
    end if;
    -- with nobody choosing, the sheet's fight is the one call it was, as text
    if public.battle_fight(v_bat, null)::text is distinct from public.fight_sides(v_bat, 1, voyage.fleet_hulls(v_nfl), voyage.fleet_hulls(v_fl))::text
       or public.battle_fight(v_bat, null)::text is distinct from pg_temp.fight_sides_old_0357(v_bat, 1, voyage.fleet_hulls(v_nfl), voyage.fleet_hulls(v_fl))::text then
      raise exception '0357 self-assert FAIL: with every stance FIGHT the sheet''s fight is not the one call it was';
    end if;
    v_r := world.battle(v_fl);
    if (v_r ->> 'on')::boolean is not true or v_r ->> 'status' is distinct from 'FIGHTING' or v_r ->> 'side' is distinct from 'ATTACKER' or v_r ->> 'stance' is distinct from 'FIGHT'
       or v_r -> 'may' is distinct from '["FIGHT", "FLEE"]'::jsonb or v_r -> 'log' ? 'end' or v_r -> 'log' -> 'r' is distinct from '[]'::jsonb or (v_r -> 'log' ->> 'v')::int is distinct from 1
       or v_r ->> 'next_range' is distinct from (public.wc('fight_ranges') -> 0 ->> 0) or coalesce(v_r ->> 'word', '') not in ('weaker', 'even', 'stronger', 'far_stronger')
       or world.battle(v_nfl) is distinct from '{"on": false}'::jsonb or world.battle(v_fl2) is distinct from '{"on": false}'::jsonb then
      raise exception '0357 self-assert FAIL: the read before the first round: %', v_r;
    end if;
    -- the door: its refusals, then Flee; the clock has not reached the first round, so it logs nothing
    if cmd.battle_stance(v_bat, 'RUN') ->> 'error_code' is distinct from 'E_BAD_STANCE' or cmd.battle_stance(v_bat, 'PAY') ->> 'error_code' is distinct from 'E_BAD_STANCE'
       or cmd.battle_stance(gen_random_uuid(), 'FLEE') ->> 'error_code' is distinct from 'E_NO_BATTLE' or exists (select 1 from public.battle_stances) then
      raise exception '0357 self-assert FAIL: a bad stance, a Pay by the side that attacked or a battle that is none was taken';
    end if;
    perform cmd.assume_identity(c_uid2);
    if cmd.battle_stance(v_bat, 'FLEE') ->> 'error_code' is distinct from 'E_NOT_YOUR_BATTLE' or exists (select 1 from public.battle_stances) then
      raise exception '0357 self-assert FAIL: another company set a stance in her battle';
    end if;
    perform cmd.assume_identity(c_uid);
    -- round 1 under FIGHT (the stance she opened with), at its instant
    -- (the closer's answer is kept first: a statement does not see what a function it calls has just written)
    v_lit := public.battle_resolve(v_bat, v_t + interval '60 seconds');
    if v_lit is not false or (select count(*) from public.battle_rounds r where r.battle_id = v_bat) is distinct from 1 then
      raise exception '0357 self-assert FAIL: at the first round''s instant the closer closed the battle (%), or did not log exactly one row (%)',
        v_lit, (select count(*) from public.battle_rounds r where r.battle_id = v_bat);
    end if;
    if (select b.status from public.battles b where b.id = v_bat) = 'FIGHTING' then
      -- a stance written before round 2's instant is read by round 2 and not by round 1 (the row is this probe's own, at an instant of its choosing)
      insert into public.battle_stances (battle_id, fleet_id, set_at, stance) values (v_bat, v_fl, v_t + interval '90 seconds', 'FLEE');
      v_m := public.battle_advance(v_bat, v_t + interval '185 seconds');
      v_f := public.battle_fight(v_bat, (select b.rounds_done from public.battles b where b.id = v_bat));
      if exists (select 1 from public.battle_rounds r where r.battle_id = v_bat and r."row"::text is distinct from (v_f -> 'rounds' -> (r.g - 1))::text)
         or (select count(*) from public.battle_rounds r where r.battle_id = v_bat) is distinct from (v_f ->> 'rounds_fought')::int
         or exists (select 1 from public.battle_rounds r where r.battle_id = v_bat and r.at is distinct from v_t + make_interval(secs => r.g * 60))
         or exists (select 1 from public.battle_rounds r where r.battle_id = v_bat and r.g = 1 and r."row" ? 'b_flee')
         or exists (select 1 from public.battle_rounds r where r.battle_id = v_bat and r.g >= 2 and (not r."row" ? 'b_flee' or (r."row" -> 'b' ->> 'fired')::int is distinct from 0)) then
        raise exception '0357 self-assert FAIL: the rows logged are not the re-run''s rows, or Flee did not take hold from round 2: % rounds, %', v_m, v_f -> 'rounds';
      end if;
      v_r := world.battle(v_fl);
      if v_r ->> 'stance' is distinct from 'FLEE' or jsonb_array_length(v_r -> 'log' -> 'r') is distinct from (select count(*)::int from public.battle_rounds r where r.battle_id = v_bat)
         or (v_r ->> 'status' = 'FIGHTING' and v_r -> 'log' ? 'end') then
        raise exception '0357 self-assert FAIL: the read after the rounds: %', v_r;
      end if;
      v_note := v_note || format('; a probe battle: %s round(s) logged, each the re-run''s row, Flee from round 2', (select count(*) from public.battle_rounds r where r.battle_id = v_bat));
    else
      v_note := v_note || '; the probe battle ended at its first instant (no round came)';
    end if;
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);
    if cmd.battle_stance(v_bat, 'FLEE') ->> 'error_code' is distinct from 'E_NO_HOUSE' or world.battle(v_fl) is distinct from '{"on": false}'::jsonb then
      raise exception '0357 self-assert FAIL: a caller with no house set a stance or read a battle';
    end if;
    raise exception using errcode = 'ZX357', message = 'PROBE_ROLLBACK_0357';
  exception when sqlstate 'ZX357' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0357 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name like 'Casa % 0357' or p.auth_uid in (c_uid, c_uid2))
     or exists (select 1 from public.battle_rounds) or exists (select 1 from public.battle_stances) or public.attack_on() then
    raise exception '0357 self-assert FAIL: the probe left something behind';
  end if;
  if public.current_player_id() is not null then
    raise exception '0357 self-assert FAIL: the probe''s identity outlived its rollback';
  end if;
  execute 'drop function pg_temp.tick_battles_old_0357(timestamp with time zone)';
  execute 'drop function pg_temp.battle_resolve_old_0357(uuid, timestamp with time zone)';
  execute 'drop function pg_temp.battle_open_old_0357(text, uuid, uuid, timestamp with time zone)';
  execute 'drop function pg_temp.arrival_at_old_0357(uuid, timestamp with time zone)';
  execute 'drop function pg_temp.days_complete_old_0357(uuid, timestamp with time zone)';
  execute 'drop function pg_temp.total_days_old_0357(uuid)';
  execute 'drop function pg_temp.fight_sides_old_0357(uuid, integer, jsonb, jsonb, jsonb)';

  v_ms := v_ms || jsonb_build_object('probe', round(extract(epoch from clock_timestamp() - v_tp) * 1000)); v_tp := clock_timestamp();

  if extract(epoch from clock_timestamp() - v_t0) > 40 then
    raise exception '0357 self-assert FAIL: the file took % (budget 40 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0357 timings (ms a part): %; total % ms. Bounds: engine parity %, stances and prefix %.', v_ms, round(extract(epoch from clock_timestamp() - v_t0) * 1000), c_guard_parity, c_guard_orders;
  raise notice '0357 self-assert ok: A BATTLE IS FOUGHT ROUND BY ROUND (C3), dark. ENGINE PARITY, bounded by the clock: % pairs on % of the 1,120 fights of 0320''s matrix (the least is %), the kept live engine against the new one as text, with no option, the sizing-up, a_order FLEE, a_order PAY, a round limit, and b_order FIGHT with every hull from 1 said aloud: all equal (%). STANCES on % fights (the least is %): the side that closes running fired nothing, every round''s chance the rule''s, % away (broke off, no boarding), % never away; % round limits under both stance lists, % left open, each the first rows of the full run; % fights with a called ship. The whole matrix every time: proof 60. 23 hunks, each once and reversing; ACL, volatility, definer and config unmoved; the engine names no table; the two refusals of a human target stand; no other function and no existing knob moved; attacks are dark and no round or stance exists. The probe (rolled back): dark, the job, the closer and the open old against new; no player could fight a player; %. % ms.',
    v_pairs, v_n, c_min_pairs, v_kinds, v_ord_n, c_min_orders, v_bfled, v_bcaught, v_pre_n, v_open_n, v_from_n, v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
