-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0353 - A FIGHT KEEPS ITS LOG, AND A FLEET HAS A STANDING ORDER  (slices C1 + C2 of docs/COMBAT_LOG.md; owner row 315; docs/SUCCESS_PLAN.md section C)
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
--
-- WHY: the owner, row 315: "combat - like a log, with action that i choose to do such as when pressed fight, it keeps on
-- fighting, when flee, it tries to flee etc - showing logs, damages etc."
--
-- C1, THE LOG (live at once, display only): a raid on a HUMAN fleet keeps the numbers the engine already computes, as one
--   compact `log` (shape v 1, docs/COMBAT_LOG.md 1.1) in the day's payload (voyage_events.payload.fight.log: voyage.settle
--   already copies every extra key of the fight's answer, so the day needs no hunk) and in the VOYAGE_REPORT's fight entry,
--   with the day's losses. A merchant's, a cargo ship's, a navy's and a pirate's raid is byte for byte what it was
--   (voyage.raid_opts answers {} for them, and with {} the skin builds nothing). The English `rounds` stay in every payload.
-- C2, THE STANDING ORDER (dark: raid_orders_enabled false): Fight / Flee / Pay per fleet. No row is Fight.
--   public.fleet_raid_orders   the row (FLEE or PAY). No client reads or writes it.
--   cmd.raid_order(fleet, order)   THE door: {ok, order} or the refusal envelope (E_NO_HOUSE, E_NOT_IN_USE, E_NO_SUCH_FLEET, E_BAD_ORDER).
--   world.raid_read(fleet)         the read beside the picker: {on, order, guns, slip, pay, foes[{danger, word}]}. A read of the sides, never a forecast.
--   voyage.freeze_order            at departure each segment keeps `order`, beside `danger` (0330) and `raider` (0339). Off, or no row: the segments unchanged, byte for byte.
--   voyage.leg_order               THE one reading of a frozen order; null while the switch is off, so one knob write ignores every frozen order at once.
--   voyage.raid_opts               what the raid is fought with: {} for a merchant; {log: true} and her order for a company. Pay with nothing aboard or no payee is refused and she fights (`pay_refused`).
--   public.fight_sides             THE ENGINE, six hunks: two new options, `a_order` (FIGHT, FLEE, PAY; a word or a list a round) and `rounds` (fight no further; C3 uses it).
--                                  ABSENT = BYTE-IDENTICAL: the self-assert fights a pg_temp copy of the live body against the new one on 0320's matrix.
--                                  FLEE: her guns are silent each round, she takes that round's fire, then rolls to slip on a new stream ('fight:<g>:flee'):
--                                  fight_flee_base + lead x fight_evade_per_sighting, never under fight_flee_floor or over fight_evade_max. Away is EVADED with `fled`.
--                                  PAY: after the sizing-up and the first-sight slip, RANSOM with `paid`, no shot.
--   voyage.raid_report (6 args)    THE SKIN, moved here from voyage.fight_resolve's live text by hunks (the head, the options, the words of Flee and Pay, the three answers).
--   voyage.fight_resolve (5 args)  one line: voyage.raid_report(..., '{}'). Same name, same answer, word for word (proof 28 and two-sides/golden.sql hold it by name).
--   voyage.raid_extras             the skin's leaf: `paid`, `fled` and the log. Names no table.
--   public.raid_ransom, public.raid_payee, public.raid_price   Pay's money: a named raider through public.pirate_ransom as today; an anonymous raid to the Brethren's capital, kind RANSOM, under the same two guards.
--   voyage.settle                  three hunks: the paid branch (before 0339's named-raider ransom), `ransom_paid` on such a day only, the report's fight entry gains `log` and `loss`.
--   voyage.fight, voyage.depart, voyage.fight_round_line, public.client_rpc_entry_points   one hunk each.
--   knobs                          raid_orders_enabled false, fight_flee_base 0.15, fight_flee_floor 0.05. No existing key is written.
--
-- WHERE THIS FILE LEAVES docs/COMBAT_LOG.md (the code was followed; each is in docs/dev-log/2026-11-11-fight-log.md):
--   * the log is built by a leaf of the skin (voyage.raid_extras), not inline: the skin answers at three places, and one leaf serves all three and C3's battle report.
--   * three more helpers than the design names: public.raid_payee (who takes the ransom, read by the refusal and by the payment, so the two cannot disagree), public.raid_price
--     (what Pay costs, read by the refusal and by the figure shown) and public.fight_flee_chance (the flee rule for the read; the engine may name no function outside its allow-list, so it holds the same arithmetic and the self-assert holds the two equal).
--   * a hoard at pirate_hoard_cap is "no payee": public.pirate_ransom pays 0 there, and a Pay that costs nothing would be a free pass.
--   * `rounds` is clamped to at least 1, as the design's sentence says and its hunk text does not.
--   * a refused Pay is written in the log as `no_pay` (EMPTY or NO_PAYEE); world.raid_read answers `on` so the client hides the picker while dark; `foes` is one row a danger level 1 to 5,
--     the strongest sea of that level now (the read takes no course: the client knows the course's worst level from Waters ahead).
--   * the self-assert is the pure fights and the catalog, as designed, AND one small probe of the doors, rolled back by a raised sentinel.
--
-- COST: a merchant's raid: one function call (voyage.raid_opts: one probe of fleets and players) and two jsonb comparisons. A company's raid: one voyage.leg_at_day and the log's
--   assembly. A departure: one knob read; lit, one primary-key probe of a near-empty table. Measured by scripts/ops/harness/combat-log/proof-0353.mjs --cost (dev-log).
-- ROLLBACK (forward, owner only): orders: raid_orders_enabled false (voyage.leg_order answers null, the door refuses; rows and logs stay). The whole slice: a migration that swaps
--   this file's OLD and NEW, puts voyage.fight_resolve's body back (voyage.raid_report with its hunks reversed is that body), and drops what this file created. Old logs stay readable.
-- SELF-ASSERT: ONE DO block, statement_timeout 45 s, lock_timeout 5 s first; fails above 40 s. Pure fights and the catalog; no table is counted or summed; the probe of the doors writes
--   only its own rows and is rolled back. THE PURE FIGHTS ARE BOUNDED BY THE CLOCK (the first deploy, 2026-11-12, took 49 s on prod against 7.8 s locally and refused itself; nothing
--   was applied): engine parity 7 s, Flee / Pay / the prefix 4 s, skin parity 4 s, the words 1 s: 16 s at the most, on any machine. 0320's matrix is read day by day across every cell,
--   so the first fights cross every kind; each part fails under its least (200 engine pairs, 20 fights under the orders, 60 raids through the skins, every ending met) and never
--   passes on nothing. A notice prints the milliseconds of every part. THE WHOLE MATRIX, every time (3,320 engine pairs, 1,082 raids through the skins, Flee, Pay and every round
--   limit), is proof 56 in CI: scripts/db/proofs/56_combat_log.sql, with the real raid through voyage.settle. ON PROD byte-parity is held again by
--   scripts/ops/harness/two-sides/golden.sql before and after the deploy (digest 89ee59988714e9794df244ef70883257 over 1,080 fights, recorded before this deploy).
-- SUPERSEDES (re-cut): public.fight_sides (0320; six hunks: with no order and no round limit its answer is byte for byte what it was, proved on 0320's matrix),
--   voyage.fight_resolve (0189; re-cut 0202, 0204, 0213, 0276; whole 0320; 0323 x2): replaced whole by the one-line wrapper, its body moved to voyage.raid_report (same answer, proved by
--   answers), voyage.fight_round_line (0323), voyage.fight (0323's line), voyage.depart (0339's line), voyage.settle (0339's and 0189's lines, cut after 0352),
--   public.client_rpc_entry_points (0348). Each is a no-op when the new input is absent: no order row, the switch off, a ship of the world.
-- NEWS: this file posts its own UPDATE row, public.news_update('0353', 'Fight log', '전투 기록') (0347's law, tests/news.lint.spec.ts): the log is live at the deploy. Standing orders are
--   dark and are not announced; the file that lights raid_orders_enabled posts that news.
-- LOCKS: the new table references public.fleets (a brief SHARE ROW EXCLUSIVE on fleets, under lock_timeout 5 s).
-- VERSION: 0353, cut after 0352 (R1), which cut voyage.settle first. 0351 shares no function with this file.
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0         timestamptz := clock_timestamp();
  v_tp         timestamptz := clock_timestamp();   -- the part now running, for the split printed at the end
  v_tg         timestamptz;                        -- a bounded part's own start
  v_ms         jsonb := '{}'::jsonb;               -- milliseconds a part
  v_pairs      int := 0;
  v_ord_n      int := 0;
  v_skin_kinds jsonb := '{}'::jsonb;
  -- THE CLOCK BOUNDS OF THE PURE FIGHTS (2026-11-12: the first deploy took 49 s on prod against 7.8 s here and refused itself at its 40 s budget). Each part stops at its bound
  -- and fails under its least; together 16 s, whatever the machine. The whole matrix is proof 56's.
  c_guard_parity constant interval := interval '7 seconds';
  c_guard_orders constant interval := interval '4 seconds';
  c_guard_skin   constant interval := interval '4 seconds';
  c_guard_words  constant interval := interval '1 second';
  c_min_pairs    constant int := 200;   -- engine pairs compared as text
  c_min_orders   constant int := 20;    -- fights put under Flee, Pay and a round limit
  c_min_skin     constant int := 60;    -- raids through the old skin, the wrapper and the moved skin
  v_fn_before  text;
  v_cfg_before text;
  v_def        text;
  v_skin0      text;
  fd           record;
  h            record;
  v_p          record;
  v_x          record;
  v_n          int := 0;
  v_m          int;
  v_bad        int := 0;
  v_ex         jsonb;
  v_old        jsonb;
  v_new        jsonb;
  v_f          jsonb;
  v_g          jsonb;
  v_b          jsonb;
  v_row        jsonb;
  v_src        text;
  v_kinds      jsonb := '{}'::jsonb;
  v_skin_n     int := 0;
  v_pre_n      int := 0;
  v_open_n     int := 0;
  v_flee_n     int := 0;
  v_fled       int := 0;
  v_caught     int := 0;
  v_pay_n      int := 0;
  v_paid       int := 0;
  v_pf         numeric;
  v_lived      boolean := false;
  v_entry      int;
  v_pl         uuid;
  v_npc        uuid;
  v_fl         uuid;
  v_nfl        uuid;
  v_lis        uuid;
  v_voy        uuid;
  v_r          jsonb;
  v_segs       jsonb;
  v_purse      bigint;
  v_take       bigint;
  v_note       text := '';
  c_uid   constant uuid := '00000000-0353-4000-8000-000000000001';
  c_seed  constant uuid := '00000000-0353-4000-8000-0000000000ff';
  c_eng   constant text := 'public.fight_sides(uuid,integer,jsonb,jsonb,jsonb)';
  c_skin  constant text := 'voyage.fight_resolve(uuid,integer,numeric,numeric,jsonb)';
  c_rep   constant text := 'voyage.raid_report(uuid,integer,numeric,numeric,jsonb,jsonb)';
  c_cut_fns constant text[] := array[
    'public.fight_sides(uuid,integer,jsonb,jsonb,jsonb)', 'voyage.fight_round_line(jsonb,integer,text,jsonb,numeric,text)',
    'voyage.fight(uuid,integer,uuid,numeric)', 'voyage.depart(uuid,jsonb,uuid,uuid,timestamp with time zone)',
    'voyage.settle(uuid,timestamp with time zone)', 'public.client_rpc_entry_points()'];
  c_new_fns constant text[] := array[
    'voyage.raid_report(uuid,integer,numeric,numeric,jsonb,jsonb)', 'voyage.raid_extras(jsonb,jsonb,jsonb,jsonb)', 'voyage.raid_opts(uuid,integer,uuid)',
    'voyage.freeze_order(jsonb,uuid)', 'voyage.leg_order(jsonb)', 'public.raid_orders_on()', 'public.raid_payee(uuid)', 'public.raid_price(uuid)', 'public.raid_ransom(uuid,uuid,bigint)',
    'public.fight_flee_chance(numeric)', 'cmd.raid_order(uuid,text)', 'world.raid_read(uuid)'];
  c_doors constant text[] := array['cmd.raid_order(uuid,text)', 'world.raid_read(uuid)'];
  c_knobs constant text[] := array['raid_orders_enabled', 'fight_flee_base', 'fight_flee_floor'];
  -- 0320's own probe hulls (its matrix is the parity matrix)
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
  if to_regclass('public.fleet_raid_orders') is not null or to_regprocedure(c_rep) is not null
     or exists (select 1 from public.world_config c where c.key = any (c_knobs)) then
    raise exception '0353 refuses: it has been applied once';
  end if;
  if to_regprocedure(c_skin) is null or to_regprocedure('voyage.raider_hulls(numeric)') is null or to_regprocedure('voyage.leg_at_day(uuid,integer)') is null
     or to_regprocedure('voyage.leg_raider(jsonb)') is null or to_regprocedure('voyage.freeze_raiders(jsonb,uuid)') is null
     or to_regprocedure('public.pirate_ransom(uuid,uuid,bigint,uuid)') is null or to_regprocedure('public.pirate_capital()') is null
     or to_regprocedure('public.pirate_hoard()') is null or to_regprocedure('public.ransom_take(bigint)') is null
     or to_regprocedure('public.fleet_stock_at_cost(uuid)') is null or to_regprocedure('public.pay_city(uuid,uuid,text,bigint,uuid)') is null
     or to_regprocedure('public.city_treasury_on()') is null or to_regprocedure('public.attack_word(numeric,numeric)') is null
     or to_regprocedure('world.sea_danger()') is null or to_regprocedure('voyage.fleet_hulls(uuid)') is null
     or to_regprocedure('cmd.refuse(text,text,jsonb)') is null or to_regprocedure('cmd.refused_envelope(text,text)') is null
     or to_regprocedure('cmd.assume_identity(uuid)') is null or to_regprocedure('public.news_update(text,text,text)') is null or to_regprocedure('public.reputation_arrival(uuid,uuid)') is null
     or exists (select 1 from unnest(c_cut_fns) f where to_regprocedure(f) is null) then
    raise exception '0353 refuses: a function it calls or cuts is not in this world (0320 / 0323 / 0330 / 0339 / 0352)';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  create temp table defs_0353 on commit drop as
  select f.fn,
         replace(pg_get_functiondef(f.fn::regprocedure), E'\r', '') as def,
         coalesce((select p.proacl::text from pg_proc p where p.oid = f.fn::regprocedure), '') as acl,
         (select p.provolatile from pg_proc p where p.oid = f.fn::regprocedure) as vol,
         (select p.prosecdef from pg_proc p where p.oid = f.fn::regprocedure) as secdef,
         (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = f.fn::regprocedure) as cfg
    from unnest(c_cut_fns || c_skin) f(fn);
  select x.def into v_skin0 from defs_0353 x where x.fn = c_skin;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> all (select f::regprocedure::oid from unnest(c_cut_fns || c_skin) f);
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
    into v_cfg_before from public.world_config c;
  v_entry := (select count(*) from public.client_rpc_entry_points());

  -- the live engine and the live skin, kept for this transaction only, for the parity below
  execute replace((select x.def from defs_0353 x where x.fn = c_eng), 'CREATE OR REPLACE FUNCTION public.fight_sides(', 'CREATE FUNCTION pg_temp.fight_sides_old_0353(');
  execute replace(replace(v_skin0, 'CREATE OR REPLACE FUNCTION voyage.fight_resolve(', 'CREATE FUNCTION pg_temp.fight_resolve_old_0353('),
                  'public.fight_sides(p_voyage,', 'pg_temp.fight_sides_old_0353(p_voyage,');
  if to_regprocedure('pg_temp.fight_resolve_old_0353(uuid,integer,numeric,numeric,jsonb)') is null
     or (select p.prosrc from pg_proc p where p.oid = 'pg_temp.fight_resolve_old_0353(uuid,integer,numeric,numeric,jsonb)'::regprocedure) not like '%pg_temp.fight_sides_old_0353(p_voyage,%' then
    raise exception '0353 refuses: the kept copy of the skin does not call the kept copy of the engine';
  end if;

  v_ms := v_ms || jsonb_build_object('guard_and_pre_images', round(extract(epoch from clock_timestamp() - v_tp) * 1000)); v_tp := clock_timestamp();

  -- ── 2. THE HUNKS (each OLD text once in its live body; the rows under voyage.raid_report are cut on voyage.fight_resolve's live text) ──
  create temp table hunks_0353 (fn text, n int, old text, new text) on commit drop;
  insert into hunks_0353 (fn, n, old, new) values
    -- THE ENGINE (docs/COMBAT_LOG.md 2.3, E1 to E6)
    (c_eng, 1,
$o$  v_ratio  numeric;
begin
$o$,
$n$  v_ratio  numeric;
  -- 0353: her standing order (p_opts.a_order: FIGHT, FLEE or PAY, one word or a list with a word a round whose last stands for the rest) and the round the fight stops at (p_opts.rounds). Absent: the fight as it was.
  v_ord    jsonb := p_opts->'a_order';
  v_ao     text;
  v_cap    int := greatest(1, coalesce((p_opts->>'rounds')::int, 1000000));
  v_fled   boolean := false;
  v_paid   boolean := false;
  v_open   boolean := false;
  v_pf     numeric;
begin
$n$),
    (c_eng, 2,
$o$  for g in 1 .. jsonb_array_length(v_ranges) loop
    v_fought := g;
$o$,
$n$  for g in 1 .. jsonb_array_length(v_ranges) loop
    -- 0353: PAY ends it before a shot (RANSOM, `paid`); past p_opts.rounds the fight is left `open`
    v_ao := case jsonb_typeof(v_ord) when 'string' then v_ord #>> '{}'
                                     when 'array' then coalesce(v_ord ->> (g - 1), v_ord ->> -1) end;
    if g > v_cap or v_ao = 'PAY' then
      if g = 1 then v_la := v_h0a; v_lb := v_h0b; end if;
      if g > v_cap then v_open := true; else v_paid := true; v_outcome := 'RANSOM'; end if;
      exit;
    end if;
    v_fought := g;
$n$),
    (c_eng, 3,
$o$v_range, v_mult, g = 1 and v_first = 'B', v_k,
$o$,
$n$v_range, v_mult, (g = 1 and v_first = 'B') or coalesce(v_ao = 'FLEE', false), v_k,   -- 0353: a side that runs fires nothing
$n$),
    (c_eng, 4,
$o$      v_broke := true;
      exit;
    end if;
  end loop;
$o$,
$n$      v_broke := true;
      exit;
    end if;
    -- 0353: FLEE. She took this round's fire; now she rolls to slip, on her own stream. Away is EVADED with `fled`.
    if v_ao = 'FLEE' then
      v_pf := least(public.wc_num('fight_evade_max'), greatest(public.wc_num('fight_flee_floor'),
                public.wc_num('fight_flee_base') + (v_sa - v_sb) * public.wc_num('fight_evade_per_sighting')));
      v_rows := jsonb_set(v_rows, array[(g - 1)::text, 'flee'], to_jsonb(round(v_pf, 4)));
      if voyage.rng(p_seed, p_round, format('fight:%s:flee', g)) < v_pf then
        v_fled := true; v_outcome := 'EVADED'; exit;
      end if;
    end if;
  end loop;
$n$),
    (c_eng, 5,
$o$  if v_outcome is null then
    for i in 1 .. v_na loop
$o$,
$n$  if v_outcome is null and not v_open then
    for i in 1 .. v_na loop
$n$),
    (c_eng, 6,
$o$    'hits', jsonb_build_object('a', v_tot_a, 'b', v_tot_b));
$o$,
$n$    'hits', jsonb_build_object('a', v_tot_a, 'b', v_tot_b))
    -- 0353: said only when true, so a fight with no order and no round limit is the answer it was
    || case when v_fled then '{"fled": true}'::jsonb else '{}'::jsonb end
    || case when v_paid then '{"paid": true}'::jsonb else '{}'::jsonb end
    || case when v_open then '{"open": true}'::jsonb else '{}'::jsonb end;
$n$),
    -- THE ROUND IN WORDS
    ('voyage.fight_round_line(jsonb,integer,text,jsonb,numeric,text)', 1,
$o$  v_you := case when p_g = 1 and p_first = 'THEY' then 'you are caught unready'
$o$,
$n$  v_you := case when p_round ? 'flee' then 'you run before them'   -- 0353: a side that runs (public.fight_sides writes `flee` on such a round only)
                when p_g = 1 and p_first = 'THEY' then 'you are caught unready'
$n$),
    -- THE RAID'S CALL
    ('voyage.fight(uuid,integer,uuid,numeric)', 1,
$o$  return voyage.fight_resolve(p_voyage, p_day, p_raider, voyage.escort_score(p_fleet), voyage.fleet_hulls(p_fleet));   -- 0323: the side, cut to its own leaf
$o$,
$n$  return voyage.raid_report(p_voyage, p_day, p_raider, voyage.escort_score(p_fleet), voyage.fleet_hulls(p_fleet),   -- 0323: the side, cut to its own leaf
                            voyage.raid_opts(p_voyage, p_day, p_fleet));   -- 0353: {} for a merchant; a company's log and her frozen order
$n$),
    -- THE DEPARTURE
    ('voyage.depart(uuid,jsonb,uuid,uuid,timestamp with time zone)', 1,
$o$  values (p_fleet, v_player, voyage.freeze_raiders(voyage.freeze_danger(p_segments, p_at), p_fleet), v_total, v_profile, p_at,   -- 0330: each segment keeps the danger of its sea as she left; 0339: and the pirate ship cruising it, if any
$o$,
$n$  values (p_fleet, v_player, voyage.freeze_order(voyage.freeze_raiders(voyage.freeze_danger(p_segments, p_at), p_fleet), p_fleet), v_total, v_profile, p_at,   -- 0330: each segment keeps the danger of its sea as she left; 0339: and the pirate ship cruising it, if any; 0353: and her standing order, if she has one
$n$),
    -- THE DAY AND THE REPORT
    ('voyage.settle(uuid,timestamp with time zone)', 1,
$o$      if v_pirate is not null and v_outcome = 'RANSOM' then   -- 0339: paid off a named raider$o$,
$n$      if coalesce((v_fight->>'paid')::boolean, false) then   -- 0353: she chose to pay (her standing order): the same share, to the raider's home or, for an anonymous raid, the Brethren's capital (public.raid_ransom)
        v_ransom := public.raid_ransom(v_pirate, f.player_id, public.fleet_stock_at_cost(p_fleet));
      elsif v_pirate is not null and v_outcome = 'RANSOM' then   -- 0339: paid off a named raider$n$),
    ('voyage.settle(uuid,timestamp with time zone)', 2,
$o$                                                     'stowed', coalesce(v_stow, '{}'::jsonb), 'ransom', v_ransom, 'booked', v_booked)) end
$o$,
$n$                                                     'stowed', coalesce(v_stow, '{}'::jsonb), 'ransom', v_ransom, 'booked', v_booked)) end
                   -- 0353: what she paid by her standing order, on such a day only
                   || case when coalesce((v_fight->>'paid')::boolean, false) then jsonb_build_object('ransom_paid', v_ransom) else '{}'::jsonb end
$n$),
    ('voyage.settle(uuid,timestamp with time zone)', 3,
$o$                      else jsonb_build_object('fights', jsonb_agg(jsonb_build_object('line', z.n - 1, 'rounds', z.payload->'rounds')
$o$,
$n$                      else jsonb_build_object('fights', jsonb_agg(jsonb_build_object('line', z.n - 1, 'rounds', z.payload->'rounds')
                                                                  -- 0353: a day that kept a log (a company's raid) carries it, and what the day cost; any other entry is what it was
                                                                  || case when z.payload->'fight' ? 'log'
                                                                          then jsonb_build_object('log', z.payload->'fight'->'log',
                                                                                 'loss', jsonb_build_object('crew_before', z.payload->'crew_before', 'crew', z.payload->'crew_lost',
                                                                                           'cargo', coalesce(z.payload->'cargo_lost', '{}'::jsonb),
                                                                                           'ransom', coalesce(z.payload->'ransom_paid', z.payload->'pirate'->'ransom', '0'::jsonb)))
                                                                          else '{}'::jsonb end
$n$),
    -- THE DOORS
    ('public.client_rpc_entry_points()', 1,
$o$      ('world',       'pirate_ship_card',      'uuid'),
$o$,
$n$      ('world',       'pirate_ship_card',      'uuid'),
      -- 0353: a fleet's standing order when raiders close (Fight, Flee, Pay), and the read beside the picker.
      ('cmd',         'raid_order',            'uuid, text'),
      ('world',       'raid_read',             'uuid'),
$n$),
    -- THE SKIN, cut on voyage.fight_resolve's live text and created as voyage.raid_report
    (c_rep, 1,
$o$CREATE OR REPLACE FUNCTION voyage.fight_resolve(p_voyage uuid, p_day integer, p_raider numeric, p_escort numeric, p_ships jsonb)
$o$,
$n$CREATE OR REPLACE FUNCTION voyage.raid_report(p_voyage uuid, p_day integer, p_raider numeric, p_escort numeric, p_ships jsonb, p_opts jsonb)
$n$),
    (c_rep, 2,
$o$jsonb_build_object('a_score', p_escort, 'b_score', p_raider));
$o$,
$n$jsonb_build_object('a_score', p_escort, 'b_score', p_raider)
                     -- 0353: p_opts {order: FLEE or PAY, log, pay_refused, foe_ship} (voyage.raid_opts). {} is the raid as it was, word for word: voyage.fight_resolve passes it.
                     || case when p_opts->>'order' in ('FLEE', 'PAY') then jsonb_build_object('a_order', p_opts->>'order') else '{}'::jsonb end);
$n$),
    (c_rep, 3,
$o$                              'hits', jsonb_build_object('yours', 0, 'theirs', 0));
  end if;

  v_lines := v_lines || case when r_n < 0.75
$o$,
$n$                              'hits', jsonb_build_object('yours', 0, 'theirs', 0))
           || case when p_opts = '{}'::jsonb then '{}'::jsonb else voyage.raid_extras(p_ships, v_r, v_f, p_opts) end;   -- 0353
  end if;

  v_lines := v_lines || case when r_n < 0.75
$n$),
    (c_rep, 4,
$o$                              'hits', jsonb_build_object('yours', 0, 'theirs', 0));
  elsif v_first = 'YOU' then
$o$,
$n$                              'hits', jsonb_build_object('yours', 0, 'theirs', 0))
           || case when p_opts = '{}'::jsonb then '{}'::jsonb else voyage.raid_extras(p_ships, v_r, v_f, p_opts) end;   -- 0353
  elsif v_first = 'YOU' then
$n$),
    (c_rep, 5,
$o$  -- THE ROUNDS
  for g in 1 .. (v_f->>'rounds_fought')::int loop
$o$,
$n$  -- 0353: her standing order, in words
  if p_opts->>'pay_refused' = 'EMPTY' then
    v_lines := v_lines || 'You have nothing aboard to pay them with.'::text;
  elsif p_opts->>'pay_refused' = 'NO_PAYEE' then
    v_lines := v_lines || 'They will take no ransom.'::text;
  elsif p_opts->>'order' = 'FLEE' then
    v_lines := v_lines || 'You turn and run.'::text;
  end if;

  -- THE ROUNDS
  for g in 1 .. (v_f->>'rounds_fought')::int loop
$n$),
    (c_rep, 6,
$o$  -- HOW IT ENDED
  if (v_f->>'broke_off')::boolean then
$o$,
$n$  -- HOW IT ENDED
  if coalesce((v_f->>'paid')::boolean, false) then   -- 0353: Pay, before a shot
    v_lines := v_lines || 'You pay their price, and they let you pass.'::text;
    v_sentence := 'We paid their price and they let us pass.';
  elsif coalesce((v_f->>'fled')::boolean, false) then   -- 0353: Flee, and away
    v_lines := v_lines || 'You get clear of them.'::text;
    v_sentence := 'We ran, and got clear of them.';
  elsif (v_f->>'broke_off')::boolean then
$n$),
    (c_rep, 7,
$o$    'hits', jsonb_build_object('yours', (v_f->'hits'->>'a')::int, 'theirs', (v_f->'hits'->>'b')::int));
$o$,
$n$    'hits', jsonb_build_object('yours', (v_f->'hits'->>'a')::int, 'theirs', (v_f->'hits'->>'b')::int))
    || case when p_opts = '{}'::jsonb then '{}'::jsonb else voyage.raid_extras(p_ships, v_r, v_f, p_opts) end;   -- 0353: `paid`, `fled` and the log, for a company's raid only
$n$);

  -- ── 3. THE TABLE AND THE KNOBS ──
  create table public.fleet_raid_orders (
    fleet_id   uuid primary key references public.fleets(id) on delete cascade,
    raid_order text not null check (raid_order in ('FLEE', 'PAY')),
    set_at     timestamptz not null default now()
  );
  comment on table public.fleet_raid_orders is
    '0353: a fleet''s standing order when raiders close: FLEE or PAY. NO ROW IS FIGHT. Written by cmd.raid_order only; frozen on a voyage''s segments at departure (voyage.freeze_order). No client reads or writes it.';
  alter table public.fleet_raid_orders enable row level security;
  revoke all on table public.fleet_raid_orders from public, anon, authenticated;

  insert into public.world_config (key, value, description) values
    ('raid_orders_enabled', 'false'::jsonb,
     '0353: THE switch of standing orders (Fight, Flee, Pay), read only through public.raid_orders_on(). False: cmd.raid_order refuses E_NOT_IN_USE, world.raid_read answers {on: false}, a departure freezes no order and voyage.leg_order answers null, so every frozen order is ignored at once.'),
    ('fight_flee_base', to_jsonb(0.15),
     '0353: a fleeing fleet''s chance to slip away at the end of a round, before the sighting lead (fight_evade_per_sighting a point). Read by public.fight_sides and public.fight_flee_chance.'),
    ('fight_flee_floor', to_jsonb(0.05),
     '0353: the least that chance is, whatever the lead. Its most is fight_evade_max. At 1.0 a fleeing fleet always gets away after one round''s fire.');

  -- ── 4. THE NEW LEAVES ──
  execute $f$
create function public.raid_orders_on()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0353: THE one reader of the standing orders' switch.
  select coalesce(public.wc('raid_orders_enabled') = 'true'::jsonb, false)
$body$;
$f$;
  comment on function public.raid_orders_on() is '0353: the one reader of raid_orders_enabled. Server-only.';

  execute $f$
create function public.fight_flee_chance(p_lead numeric)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0353: THE FLEE RULE, for a read: a fleeing fleet's chance to slip away at the end of a round, by her sighting lead (her best sighting less theirs). public.fight_sides holds the same arithmetic
  -- (the engine names no function outside its allow-list); 0353's self-assert holds every round's `flee` equal to this.
  select least(public.wc_num('fight_evade_max'), greatest(public.wc_num('fight_flee_floor'),
           public.wc_num('fight_flee_base') + coalesce(p_lead, 0) * public.wc_num('fight_evade_per_sighting')))
$body$;
$f$;
  comment on function public.fight_flee_chance(numeric) is '0353: the flee rule by sighting lead, for world.raid_read. Server-only.';

  execute $f$
create function voyage.freeze_order(p_segments jsonb, p_fleet uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0353 (docs/COMBAT_LOG.md 2.2): beside each segment's frozen danger and raider, the fleet's standing order as she left (`order`: FLEE or PAY). Read by voyage.depart only.
  -- THE SWITCH OFF, OR NO ROW (Fight; every merchant): p_segments unchanged, byte for byte.
  select case when not public.raid_orders_on() then p_segments
              else coalesce((select (select jsonb_agg(e.seg || jsonb_build_object('order', o.raid_order) order by e.n)
                                       from jsonb_array_elements(p_segments) with ordinality e(seg, n))
                               from public.fleet_raid_orders o where o.fleet_id = p_fleet), p_segments) end
$body$;
$f$;
  comment on function voyage.freeze_order(jsonb, uuid) is
    '0353: a departure''s segments with the fleet''s standing order frozen on each; unchanged with the switch off or no row. Read by voyage.depart. Server-only.';

  execute $f$
create function voyage.leg_order(p_leg jsonb)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0353: THE one reading of a segment's frozen order: FLEE, PAY, or null (Fight). Null while the switch is off, so one knob write ignores every frozen order at once.
  select case when public.raid_orders_on() then p_leg ->> 'order' end
$body$;
$f$;
  comment on function voyage.leg_order(jsonb) is '0353: the one reading of a segment''s frozen standing order; null with the switch off. Server-only.';

  execute $f$
create function public.raid_payee(p_pirate uuid)
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0353 (docs/COMBAT_LOG.md 2.4): THE HARBOUR THAT TAKES A RANSOM SHE CHOSE TO PAY: a named raider's home, else the Brethren's capital. Null (no payee, and she fights) with the city purses dark or the
  -- hoard at pirate_hoard_cap: public.pirate_ransom's own two guards, read here once so the refusal (voyage.raid_opts) and the payment (public.raid_ransom) cannot disagree.
  select case when not public.city_treasury_on() or public.pirate_hoard() >= public.wc_num('pirate_hoard_cap') then null
              when p_pirate is not null then (select n.home_port from public.pirate_ships n where n.fleet_id = p_pirate)
              else public.pirate_capital() end
$body$;
$f$;
  comment on function public.raid_payee(uuid) is '0353: the harbour that takes a chosen ransom, or null. Read by voyage.raid_opts and public.raid_ransom. Server-only.';

  execute $f$
create function public.raid_price(p_fleet uuid)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0353: WHAT PAY COSTS THIS FLEET NOW: public.ransom_take (ransom_share, its one reader) of the cargo aboard at cost. 0 with an empty hold. Read by voyage.raid_opts (the refusal) and world.raid_read (the figure shown).
  select public.ransom_take(public.fleet_stock_at_cost(p_fleet))
$body$;
$f$;
  comment on function public.raid_price(uuid) is '0353: what Pay costs a fleet now: ransom_share of her cargo at cost. Server-only.';

  execute $f$
create function public.raid_ransom(p_pirate uuid, p_company uuid, p_basis bigint)
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0353 (docs/COMBAT_LOG.md 2.4): PAY. The ransom a fleet pays by her standing order: public.ransom_take of the cargo at cost (ransom_share, its one reader). A named raider: public.pirate_ransom, as a boarding's
-- ransom is paid today. An anonymous raid: from the company's purse to the Brethren's capital (public.raid_payee), kind RANSOM, moved (public.pay_city). A purse that cannot pay pays what it holds
-- (public.pirate_ransom's own rule): the outcome never depends on the purse, only the sum does. Answers the ducats moved. Read by voyage.settle's PIRATES arm on a `paid` day.
declare
  v_port  uuid;
  v_purse bigint;
  v_take  bigint;
begin
  if p_pirate is not null then
    return public.pirate_ransom(p_pirate, p_company, p_basis, null);
  end if;
  v_port := public.raid_payee(null);
  if v_port is null or p_company is null then
    return 0;
  end if;
  select pl.ducats into v_purse from public.players pl where pl.id = p_company for update;
  v_take := least(public.ransom_take(p_basis), greatest(coalesce(v_purse, 0), 0));
  if v_take <= 0 then
    return 0;
  end if;
  perform public.pay_city(p_company, v_port, 'RANSOM', v_take, null);
  return v_take;
end
$body$;
$f$;
  comment on function public.raid_ransom(uuid, uuid, bigint) is
    '0353: the ransom a fleet pays by her standing order: a named raider through public.pirate_ransom, an anonymous raid to the Brethren''s capital, kind RANSOM. Answers the ducats moved. Server-only.';

  execute $f$
create function voyage.raid_opts(p_voyage uuid, p_day int, p_fleet uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0353: WHAT A RAID ON THIS FLEET IS FOUGHT WITH, for voyage.raid_report. A MERCHANT (any ship of the world): {} after one probe, so her raid is the raid it was, byte for byte. A COMPANY: {log: true}, the named
-- raider's name for the log (`foe_ship`), and her standing order as frozen on the day's segment (voyage.leg_order): FLEE, or PAY when there is something to pay with and someone to pay
-- (public.raid_price above 0; public.raid_payee). A Pay that cannot be paid is refused BEFORE the fight and she fights: `pay_refused` EMPTY or NO_PAYEE, so the log can say why.
-- A voyage that is no row (a simulation's seed) has no segment: the log only.
declare
  v_player uuid;
  v_npc    boolean;
  v_leg    jsonb;
  v_pirate uuid;
  v_order  text;
  v_out    jsonb := '{"log": true}'::jsonb;
begin
  select f.player_id, p.is_npc into v_player, v_npc from public.fleets f join public.players p on p.id = f.player_id where f.id = p_fleet;
  if v_player is null or v_npc then
    return '{}'::jsonb;
  end if;
  if not exists (select 1 from public.voyages v where v.id = p_voyage) then
    return v_out;
  end if;
  v_leg := voyage.leg_at_day(p_voyage, p_day);
  v_pirate := voyage.leg_raider(v_leg);
  if v_pirate is not null then
    v_out := v_out || coalesce((select jsonb_build_object('foe_ship', f2.name) from public.fleets f2 where f2.id = v_pirate), '{}'::jsonb);
  end if;
  v_order := voyage.leg_order(v_leg);
  if v_order = 'FLEE' then
    return v_out || '{"order": "FLEE"}'::jsonb;
  elsif v_order = 'PAY' then
    if public.raid_price(p_fleet) <= 0 then
      return v_out || '{"pay_refused": "EMPTY"}'::jsonb;
    elsif public.raid_payee(v_pirate) is null then
      return v_out || '{"pay_refused": "NO_PAYEE"}'::jsonb;
    end if;
    return v_out || '{"order": "PAY"}'::jsonb;
  end if;
  return v_out;
end
$body$;
$f$;
  comment on function voyage.raid_opts(uuid, int, uuid) is
    '0353: what a raid on this fleet is fought with: {} for a merchant; {log, order, pay_refused, foe_ship} for a company. Read by voyage.fight. Server-only.';

  execute $f$
create function voyage.raid_extras(p_ships jsonb, p_foe jsonb, p_f jsonb, p_opts jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0353 (docs/COMBAT_LOG.md 1.1): WHAT A COMPANY'S RAID KEEPS BESIDE ITS WORDS, the leaf of voyage.raid_report: `paid` and `fled` when true (voyage.settle reads `paid`), and, when p_opts.log, the LOG:
-- the engine's own numbers (p_f, public.fight_sides' answer), compact, shape v 1. p_ships is her side, p_foe the raiders' squadron hull (voyage.raider_hulls). Numbers only; names no table.
--   {v, order (absent = Fight), no_pay (a refused Pay: EMPTY, NO_PAYEE), first (YOU, THEY, BOTH), foe {n, k, crew, hull, ship}, you [[name, hull, full hull, crew]],
--    r [[round, range L M C, you can, fired, hits, damage dealt, them can, fired, hits, damage dealt, her hull left, their hull left, her ships struck [[index, % of her size]], slip chance or null]],
--    end (STOOD, SLIP, BROKE, THREW, TERMS, TAKEN, GAVE, FLED, PAID), board [her crew, their crew, ratio] when boarded, after [[name, hull after the shot]]}
declare
  v_paid  boolean := coalesce((p_f->>'paid')::boolean, false);
  v_fled  boolean := coalesce((p_f->>'fled')::boolean, false);
  v_board jsonb := p_f->'board';
  v_out   jsonb := '{}'::jsonb;
  v_end   text;
begin
  if v_paid then v_out := v_out || '{"paid": true}'::jsonb; end if;
  if v_fled then v_out := v_out || '{"fled": true}'::jsonb; end if;
  if not coalesce((p_opts->>'log')::boolean, false) then
    return v_out;
  end if;
  v_end := case when (p_f->>'stood_off')::boolean then 'STOOD'
                when (p_f->>'slipped')::boolean then 'SLIP'
                when v_paid then 'PAID'
                when v_fled then 'FLED'
                when (p_f->>'broke_off')::boolean then 'BROKE'
                when (v_board->>'surrender')::boolean then 'GAVE'
                else case p_f->>'outcome' when 'DRIVEN_OFF' then 'THREW' when 'RANSOM' then 'TERMS' else 'TAKEN' end end;
  return v_out || jsonb_build_object('log', jsonb_strip_nulls(jsonb_build_object(
    'v', 1,
    'order', case when p_opts->>'order' in ('FLEE', 'PAY') then p_opts->>'order' end,
    'no_pay', p_opts->>'pay_refused',
    'first', case p_f->>'first' when 'A' then 'YOU' when 'B' then 'THEY' else 'BOTH' end,
    'foe', jsonb_build_object('n', p_foe->>'name', 'k', round((p_foe->>'ships')::numeric, 2), 'crew', round((p_foe->>'crew')::numeric),
                              'hull', round((p_foe->>'hull')::numeric, 1), 'ship', p_opts->>'foe_ship'),
    'you', (select coalesce(jsonb_agg(jsonb_build_array(s.e->>'name', (s.e->>'hull')::numeric, (s.e->>'maxd')::numeric, (s.e->>'crew')::numeric) order by s.o), '[]'::jsonb)
              from jsonb_array_elements(p_ships) with ordinality s(e, o)),
    'r', (select coalesce(jsonb_agg(jsonb_build_array(
                   (x.e->>'round')::int, left(x.e->>'range', 1),
                   (x.e->'a'->>'can')::int, (x.e->'a'->>'fired')::int, (x.e->'a'->>'hits')::int, round((x.e->'a'->>'dealt')::numeric, 1),
                   (x.e->'b'->>'can')::int, (x.e->'b'->>'fired')::int, (x.e->'b'->>'hits')::int, round((x.e->'b'->>'dealt')::numeric, 1),
                   round((x.e->'a'->>'left')::numeric, 1), round((x.e->'b'->>'left')::numeric, 1),
                   x.e->'a'->'struck', x.e->'flee') order by x.o), '[]'::jsonb)
            from jsonb_array_elements(p_f->'rounds') with ordinality x(e, o)),
    'end', v_end,
    'board', case when v_board is not null and jsonb_typeof(v_board) = 'object'
                  then jsonb_build_array(round((v_board->>'a_crew')::numeric), round((v_board->>'b_crew')::numeric), round((v_board->>'ratio')::numeric, 2)) end,
    'after', (select coalesce(jsonb_agg(jsonb_build_array(s.e->>'name',
                       round(greatest(0, (s.e->>'hull')::numeric - coalesce((p_f->'hull_lost'->'a'->>(s.e->>'id'))::numeric, 0)), 2)) order by s.o), '[]'::jsonb)
                from jsonb_array_elements(p_ships) with ordinality s(e, o)))));
end
$body$;
$f$;
  comment on function voyage.raid_extras(jsonb, jsonb, jsonb, jsonb) is
    '0353: what a company''s raid keeps beside its words: `paid`, `fled` and the compact log (shape v 1, docs/COMBAT_LOG.md 1.1). The leaf of voyage.raid_report. Names no table. Server-only.';

  -- ── 5. THE SKIN MOVES: voyage.raid_report from voyage.fight_resolve's live text, then the one-line wrapper ──
  v_def := v_skin0;
  for h in select * from hunks_0353 x where x.fn = c_rep order by x.n loop
    v_m := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_m <> 1 then
      raise exception '0353 slice: hunk % of the skin occurs % time(s) in voyage.fight_resolve, expected exactly 1: the deployed body is not what this migration was written against', h.n, v_m;
    end if;
    v_def := replace(v_def, h.old, h.new);
  end loop;
  execute v_def;
  comment on function voyage.raid_report(uuid, int, numeric, numeric, jsonb, jsonb) is
    '0189 / 0202 / 0320 / 0353: a raid, in words: the skin of public.fight_sides over voyage.raider_hulls, with p_opts (voyage.raid_opts): her standing order, and a company''s log. {} is the raid as it always was. Read by voyage.fight and voyage.fight_resolve. Server-only.';

  execute $f$
create or replace function voyage.fight_resolve(p_voyage uuid, p_day int, p_raider numeric, p_escort numeric, p_ships jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0189 / 0320 / 0353: A RAID, in words, with no order and no log: voyage.raid_report with {}. Same arguments, same answer, word for word, as before 0353 moved the skin's body there (its self-assert:
-- 1,080 fights and two empty seas against a kept copy of the old body and the old engine). Kept by name: proof 28, scripts/ops/harness/two-sides/golden.sql and raid/sim.mjs call it.
begin
  return voyage.raid_report(p_voyage, p_day, p_raider, p_escort, p_ships, '{}'::jsonb);
end $body$;
$f$;

  -- ── 6. THE DOORS ──
  execute $f$
create function cmd.raid_order(p_fleet uuid, p_order text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0353 (docs/COMBAT_LOG.md 2.1): A FLEET'S STANDING ORDER WHEN RAIDERS CLOSE: FIGHT (no row), FLEE or PAY. It may change at any time, in any state; it takes hold at her next departure
-- (voyage.freeze_order), and a turn at sea is a departure. {ok, order} or the refusal envelope: E_NO_HOUSE, E_NOT_IN_USE (the switch off), E_NO_SUCH_FLEET, E_BAD_ORDER.
declare
  v_player uuid := public.current_player_id();
  v_det    text;
begin
  if v_player is null then
    return jsonb_build_object('ok', false, 'error_code', 'E_NO_HOUSE', 'error_message', 'Found a house first.', 'fixes', '[]'::jsonb);
  end if;
  begin
    if not public.raid_orders_on() then
      perform cmd.refuse('E_NOT_IN_USE', 'standing orders are not in use yet');
    end if;
    if not exists (select 1 from public.fleets f where f.id = p_fleet and f.player_id = v_player) then
      perform cmd.refuse('E_NO_SUCH_FLEET', 'no such fleet of yours');
    end if;
    if p_order is null or p_order not in ('FIGHT', 'FLEE', 'PAY') then
      perform cmd.refuse('E_BAD_ORDER', 'an order is FIGHT, FLEE or PAY');
    end if;
    if p_order = 'FIGHT' then
      delete from public.fleet_raid_orders o where o.fleet_id = p_fleet;
    else
      insert into public.fleet_raid_orders (fleet_id, raid_order) values (p_fleet, p_order)
      on conflict (fleet_id) do update set raid_order = excluded.raid_order, set_at = now();
    end if;
    return jsonb_build_object('ok', true, 'order', p_order);
  exception when others then
    if sqlerrm !~ '^E_[A-Z0-9_]+:' then raise; end if;
    get stacked diagnostics v_det = pg_exception_detail;
    return cmd.refused_envelope(sqlerrm, v_det);
  end;
end
$body$;
$f$;
  comment on function cmd.raid_order(uuid, text) is
    '0353: sets a fleet''s standing order when raiders close: FIGHT (no row), FLEE or PAY. Takes hold at her next departure. {ok, order} or the refusal envelope. Dark: E_NOT_IN_USE.';
  revoke all on function cmd.raid_order(uuid, text) from public, anon;
  grant execute on function cmd.raid_order(uuid, text) to authenticated;

  execute $f$
create function world.raid_read(p_fleet uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0353 (docs/COMBAT_LOG.md 6.2): THE READ BESIDE THE ORDER'S PICKER, for the caller's own fleet. A read of the two sides as they are; never a forecast, and no day's roll is in it.
--   on     the switch. False (or not her fleet): {on: false} and nothing else, so the client shows no picker.
--   order  FIGHT, FLEE or PAY: what a departure now would freeze.
--   guns   whether any hull of hers can fire (attack, accuracy and hull left: public.fight_volley's own test).
--   slip   poor, fair or good: public.fight_flee_chance of her best sighting against the raider class's, under 0.10, under 0.20, above.
--   pay    what Pay would cost now (public.raid_price). 0 is nothing aboard, and a Pay is then refused.
--   foes   one row a danger level on the sea now (world.sea_danger's level): the raiders' word, public.attack_word(her escort score, the strongest sea of that level x 40: the mid roll).
declare
  v_player uuid := public.current_player_id();
  v_hulls  jsonb;
  v_sa     numeric;
  v_pf     numeric;
  v_esc    numeric;
begin
  if not public.raid_orders_on() or v_player is null
     or not exists (select 1 from public.fleets f where f.id = p_fleet and f.player_id = v_player) then
    return jsonb_build_object('on', false);
  end if;
  v_hulls := coalesce(voyage.fleet_hulls(p_fleet), '[]'::jsonb);
  v_sa := coalesce((select max((e->>'sighting')::numeric) from jsonb_array_elements(v_hulls) e), 0);
  v_pf := public.fight_flee_chance(v_sa - coalesce((voyage.raider_hulls(1) -> 0 ->> 'sighting')::numeric, 0));
  v_esc := voyage.escort_score(p_fleet);
  return jsonb_build_object(
    'on', true,
    'order', coalesce((select o.raid_order from public.fleet_raid_orders o where o.fleet_id = p_fleet), 'FIGHT'),
    'guns', exists (select 1 from jsonb_array_elements(v_hulls) e
                     where (e->>'attack')::numeric > 0 and (e->>'accuracy')::numeric > 0 and (e->>'hull')::numeric > 0),
    'slip', case when v_pf < 0.10 then 'poor' when v_pf < 0.20 then 'fair' else 'good' end,
    'pay', public.raid_price(p_fleet),
    'foes', coalesce((select jsonb_agg(jsonb_build_object('danger', q.level, 'word', public.attack_word(v_esc, q.danger * 40)) order by q.level)
                        from (select (e->>'level')::int as level, max(voyage.sea_danger(s.id, now())) as danger
                                from jsonb_array_elements(world.sea_danger()) e
                                join public.seas s on s.code = e->>'sea_code'
                               group by 1) q), '[]'::jsonb));
end
$body$;
$f$;
  comment on function world.raid_read(uuid) is
    '0353: the read beside a fleet''s standing-order picker: {on, order, guns, slip, pay, foes[{danger, word}]}. The sides as they are, never a forecast. Dark, or not the caller''s fleet: {on: false}.';
  revoke all on function world.raid_read(uuid) from public, anon;
  grant execute on function world.raid_read(uuid) to authenticated;

  revoke all on function voyage.raid_report(uuid, int, numeric, numeric, jsonb, jsonb) from public, anon, authenticated;
  revoke all on function voyage.raid_extras(jsonb, jsonb, jsonb, jsonb) from public, anon, authenticated;
  revoke all on function voyage.raid_opts(uuid, int, uuid) from public, anon, authenticated;
  revoke all on function voyage.freeze_order(jsonb, uuid) from public, anon, authenticated;
  revoke all on function voyage.leg_order(jsonb) from public, anon, authenticated;
  revoke all on function public.raid_orders_on() from public, anon, authenticated;
  revoke all on function public.raid_payee(uuid) from public, anon, authenticated;
  revoke all on function public.raid_price(uuid) from public, anon, authenticated;
  revoke all on function public.raid_ransom(uuid, uuid, bigint) from public, anon, authenticated;
  revoke all on function public.fight_flee_chance(numeric) from public, anon, authenticated;

  -- ── 7. THE RE-CUTS (each hunk once) ──
  for fd in select * from defs_0353 x where x.fn <> c_skin order by x.fn loop
    v_def := fd.def;
    for h in select * from hunks_0353 x where x.fn = fd.fn order by x.n loop
      v_m := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
      if v_m <> 1 then
        raise exception '0353 slice: hunk % of % occurs % time(s), expected exactly 1: the deployed body is not what this migration was written against', h.n, fd.fn, v_m;
      end if;
      v_def := replace(v_def, h.old, h.new);
    end loop;
    execute v_def;
  end loop;

  -- ── 8. THE SELF-ASSERT: the catalog ──
  for fd in select * from defs_0353 order by fn loop
    -- the skin's pre-image is voyage.raid_report with its hunks reversed; every other body reverses in place
    v_def := replace(pg_get_functiondef((case when fd.fn = c_skin then c_rep else fd.fn end)::regprocedure), E'\r', '');
    for h in select * from hunks_0353 x where x.fn = (case when fd.fn = c_skin then c_rep else fd.fn end) order by x.n desc loop
      if (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new) is distinct from 1 then
        raise exception '0353 self-assert FAIL: hunk % of % is not in the new body exactly once', h.n, h.fn;
      end if;
      v_def := replace(v_def, h.new, h.old);
    end loop;
    if v_def is distinct from fd.def then
      raise exception '0353 self-assert FAIL: % does not reverse to its pre-image', fd.fn;
    end if;
    select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef, coalesce(pr.proconfig::text, '') as cfg
      into v_p from pg_proc pr where pr.oid = fd.fn::regprocedure;
    if v_p.acl is distinct from fd.acl or v_p.vol is distinct from fd.vol or v_p.secdef is distinct from fd.secdef or v_p.cfg is distinct from fd.cfg then
      raise exception '0353 self-assert FAIL: % changed its ACL, volatility, definer or config', fd.fn;
    end if;
  end loop;
  -- the moved skin carries the old skin's ACL, volatility, definer and config
  select coalesce(pr.proacl::text, '') as acl, pr.provolatile as vol, pr.prosecdef as secdef, coalesce(pr.proconfig::text, '') as cfg
    into v_p from pg_proc pr where pr.oid = c_rep::regprocedure;
  select * into fd from defs_0353 x where x.fn = c_skin;
  if v_p.vol is distinct from fd.vol or v_p.secdef is distinct from fd.secdef or v_p.cfg is distinct from fd.cfg then
    raise exception '0353 self-assert FAIL: voyage.raid_report is not stable, definer and configured as the skin was';
  end if;
  if (select count(*) from hunks_0353) is distinct from 20 then
    raise exception '0353 self-assert FAIL: % hunks, not 20', (select count(*) from hunks_0353);
  end if;

  v_ms := v_ms || jsonb_build_object('made_and_cut', round(extract(epoch from clock_timestamp() - v_tp) * 1000)); v_tp := clock_timestamp();

  -- ── 9. ENGINE PARITY, BOUNDED BY THE CLOCK: the kept copy of the live engine against the new one, as text, on 0320's matrix, three ways ──
  -- The matrix is 0320's 1,120 fights, read DAY BY DAY across every cell (both probe hulls x four raids, the convoy x four raids, three real hulls against two), so the first
  -- fights already cross every kind of fight. It runs until it ends or until c_guard_parity has passed, whichever is first, and FAILS if fewer than c_min_pairs pairs were
  -- compared or an ending was not met: it never passes on nothing. The whole matrix, every time, is proof 56's (CI), and prod's byte-parity is held again by
  -- scripts/ops/harness/two-sides/golden.sql before and after the deploy.
  create temp table matrix_0353 on commit drop as
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
  if (select count(*) from matrix_0353) is distinct from 1120 then
    raise exception '0353 self-assert FAIL: the matrix is % fights, not 1120', (select count(*) from matrix_0353);
  end if;

  v_tg := clock_timestamp();
  for v_x in select * from matrix_0353 m order by m.i loop
    exit when clock_timestamp() - v_tg > c_guard_parity;
    v_n := v_n + 1;
    -- (i) no options
    v_old := pg_temp.fight_sides_old_0353(c_seed, v_x.d, v_x.a, v_x.b, '{}'::jsonb);
    v_new := public.fight_sides(c_seed, v_x.d, v_x.a, v_x.b, '{}'::jsonb);
    if v_old::text is distinct from v_new::text then
      raise exception '0353 self-assert FAIL: ENGINE PARITY: with no option a fight changed (day %): % against %', v_x.d, v_old, v_new;
    end if;
    v_pairs := v_pairs + 1;
    v_kinds := jsonb_set(v_kinds, array[v_old ->> 'outcome'], to_jsonb(coalesce((v_kinds ->> (v_old ->> 'outcome'))::int, 0) + 1));
    if v_x.r is not null then
      -- (ii) the sizing-up; (iii) and a_order FIGHT said aloud
      v_old := pg_temp.fight_sides_old_0353(c_seed, v_x.d, v_x.a, v_x.b, jsonb_build_object('a_score', v_x.esc, 'b_score', v_x.r));
      v_new := public.fight_sides(c_seed, v_x.d, v_x.a, v_x.b, jsonb_build_object('a_score', v_x.esc, 'b_score', v_x.r));
      v_f   := public.fight_sides(c_seed, v_x.d, v_x.a, v_x.b, jsonb_build_object('a_score', v_x.esc, 'b_score', v_x.r, 'a_order', 'FIGHT'));
      if v_old::text is distinct from v_new::text or v_old::text is distinct from v_f::text then
        raise exception '0353 self-assert FAIL: ENGINE PARITY: with the sizing-up, or with a_order FIGHT said, a fight changed (day %, raid %): % against % and %', v_x.d, v_x.r, v_old, v_new, v_f;
      end if;
      v_pairs := v_pairs + 2;
      v_kinds := jsonb_set(v_kinds, array[v_old ->> 'outcome'], to_jsonb(coalesce((v_kinds ->> (v_old ->> 'outcome'))::int, 0) + 1));
    else
      v_f := public.fight_sides(c_seed, v_x.d, v_x.a, v_x.b, jsonb_build_object('a_order', 'FIGHT'));
      if v_old::text is distinct from v_f::text then
        raise exception '0353 self-assert FAIL: ENGINE PARITY: with a_order FIGHT said a fight of real hulls changed (day %): % against %', v_x.d, v_old, v_f;
      end if;
      v_pairs := v_pairs + 1;
    end if;
  end loop;
  if v_pairs < c_min_pairs then
    raise exception '0353 self-assert FAIL: ENGINE PARITY compared only % pair(s) in % (the least that proves anything is %): this database is too slow now, deploy it again', v_pairs, c_guard_parity, c_min_pairs;
  end if;
  if not (v_kinds ?& array['EVADED', 'DRIVEN_OFF', 'RANSOM', 'PLUNDERED']) then
    raise exception '0353 self-assert FAIL: the % fights compared met too few endings to prove anything: %', v_n, v_kinds;
  end if;
  v_ms := v_ms || jsonb_build_object('engine_parity', round(extract(epoch from clock_timestamp() - v_tp) * 1000)); v_tp := clock_timestamp();

  -- ── 9b. FLEE, PAY AND THE PREFIX, on the same matrix in the same order, bounded by c_guard_orders. The whole matrix: proof 56. ──
  v_tg := clock_timestamp();
  for v_x in select * from matrix_0353 m order by m.i loop
    exit when clock_timestamp() - v_tg > c_guard_orders;
    v_ord_n := v_ord_n + 1;
    v_b := case when v_x.r is null then '{}'::jsonb else jsonb_build_object('a_score', v_x.esc, 'b_score', v_x.r) end;
    -- the fight as it is with no order (with the sizing-up where there is one): the base of what follows
    v_new := public.fight_sides(c_seed, v_x.d, v_x.a, v_x.b, v_b);

    -- ── FLEE ──
    v_f := public.fight_sides(c_seed, v_x.d, v_x.a, v_x.b, v_b || '{"a_order": "FLEE"}'::jsonb);
    v_flee_n := v_flee_n + 1;
    if (v_new ->> 'stood_off')::boolean or (v_new ->> 'slipped')::boolean then
      if v_f::text is distinct from v_new::text then
        raise exception '0353 self-assert FAIL: Flee changed a day that never came to a round: %', v_f;
      end if;
    else
      v_pf := round(public.fight_flee_chance((select max((e ->> 'sighting')::numeric) from jsonb_array_elements(v_x.a) e)
                                             - (select max((e ->> 'sighting')::numeric) from jsonb_array_elements(v_x.b) e)), 4);
      if v_f -> 'hull_lost' -> 'b' is distinct from '{}'::jsonb or (v_f -> 'hits' ->> 'a')::int is distinct from 0 or jsonb_array_length(v_f -> 'rounds') is distinct from (v_f ->> 'rounds_fought')::int
         or exists (select 1 from jsonb_array_elements(v_f -> 'rounds') e
                     where (e -> 'a' ->> 'fired')::int is distinct from 0 or (e ->> 'flee')::numeric is distinct from v_pf) then
        raise exception '0353 self-assert FAIL: a fleeing side fired, or a round''s flee is not the rule''s % : %', v_pf, v_f;
      end if;
      if coalesce((v_f ->> 'fled')::boolean, false) then
        v_fled := v_fled + 1;
        if v_f ->> 'outcome' is distinct from 'EVADED' or v_f -> 'board' is distinct from 'null'::jsonb or (v_f ->> 'broke_off')::boolean is not false then
          raise exception '0353 self-assert FAIL: a flight that got away is not EVADED with no boarding: %', v_f;
        end if;
      else
        v_caught := v_caught + 1;
        if jsonb_typeof(v_f -> 'board') is distinct from 'object' or (v_f ->> 'rounds_fought')::int is distinct from jsonb_array_length(public.wc('fight_ranges'))
           or coalesce(v_f ->> 'outcome', '') not in ('DRIVEN_OFF', 'RANSOM', 'PLUNDERED') then
          raise exception '0353 self-assert FAIL: a flight that was caught was not boarded after every round: %', v_f;
        end if;
      end if;
    end if;

    -- ── PAY ──
    v_f := public.fight_sides(c_seed, v_x.d, v_x.a, v_x.b, v_b || '{"a_order": "PAY"}'::jsonb);
    v_pay_n := v_pay_n + 1;
    if (v_new ->> 'stood_off')::boolean or (v_new ->> 'slipped')::boolean then
      if v_f::text is distinct from v_new::text then
        raise exception '0353 self-assert FAIL: Pay changed a day that stood off or that she slipped: %', v_f;
      end if;
    else
      v_paid := v_paid + 1;
      if v_f ->> 'outcome' is distinct from 'RANSOM' or not coalesce((v_f ->> 'paid')::boolean, false) or (v_f ->> 'rounds_fought')::int is distinct from 0 or v_f -> 'rounds' is distinct from '[]'::jsonb
         or v_f -> 'hull_lost' is distinct from '{"a": {}, "b": {}}'::jsonb or v_f -> 'board' is distinct from 'null'::jsonb
         or (v_f -> 'hull' ->> 'a')::numeric is distinct from (v_f -> 'hull' ->> 'a_start')::numeric
         or (v_f -> 'hull' ->> 'b')::numeric is distinct from (v_f -> 'hull' ->> 'b_start')::numeric then
        raise exception '0353 self-assert FAIL: a Pay is not RANSOM, paid, no round, no hull: %', v_f;
      end if;
    end if;

    -- ── PREFIX (docs/COMBAT_LOG.md 3.1): a run to round N is the first N rows of the full run; open exactly when the full run went further. One limit a fight here (the
    --    limit turns with the fight, 1 to 7), with no order and under Flee; every limit on every fight of twelve days is proof 56's. ──
    v_m := 1 + (v_x.i % 7);
    foreach v_g in array array[v_b, v_b || '{"a_order": "FLEE"}'::jsonb] loop
      v_old := public.fight_sides(c_seed, v_x.d, v_x.a, v_x.b, v_g);
      v_f := public.fight_sides(c_seed, v_x.d, v_x.a, v_x.b, v_g || jsonb_build_object('rounds', v_m));
      v_pre_n := v_pre_n + 1;
      if (v_old ->> 'rounds_fought')::int > v_m then
        v_open_n := v_open_n + 1;
        if not coalesce((v_f ->> 'open')::boolean, false) or v_f -> 'outcome' is distinct from 'null'::jsonb or v_f -> 'board' is distinct from 'null'::jsonb or (v_f ->> 'rounds_fought')::int is distinct from v_m
           or (v_f -> 'rounds')::text is distinct from (select jsonb_agg(e order by o) from jsonb_array_elements(v_old -> 'rounds') with ordinality q(e, o) where o <= v_m)::text then
          raise exception '0353 self-assert FAIL: a run to round % is not the first % rows of the full run, left open: % against %', v_m, v_m, v_f, v_old;
        end if;
      elsif v_f::text is distinct from v_old::text then
        raise exception '0353 self-assert FAIL: a round limit the fight never reached changed it (limit %): % against %', v_m, v_f, v_old;
      end if;
    end loop;
  end loop;
  if v_ord_n < c_min_orders or v_fled = 0 or v_caught = 0 or v_paid = 0 or v_open_n = 0 or v_open_n = v_pre_n then
    raise exception '0353 self-assert FAIL: in % the orders ran on % fight(s) (the least is %) and must meet a flight away (%), a flight caught (%), a Pay (%) and both an open and a finished prefix (% of %)',
      c_guard_orders, v_ord_n, c_min_orders, v_fled, v_caught, v_paid, v_open_n, v_pre_n;
  end if;
  v_ms := v_ms || jsonb_build_object('orders', round(extract(epoch from clock_timestamp() - v_tp) * 1000)); v_tp := clock_timestamp();

  -- ── 10. SKIN PARITY, BOUNDED BY c_guard_skin: the kept copy of the live skin (over the kept engine) against the wrapper and against voyage.raid_report with {}, as text.
  --    The two empty seas first, then the scored fights of the matrix in its order. All 1,082: proof 56. ──
  v_tg := clock_timestamp();
  for v_x in
    select q.ships, q.esc, q.r, q.d
      from (select 0 as i, v_carlat as ships, 5::numeric as esc, 0::numeric as r, 7 as d
            union all select 0, v_carlat, null::numeric, null::numeric, 7
            union all select m.i, m.a, m.esc, m.r, m.d from matrix_0353 m where m.r is not null) q
     order by q.i, q.r nulls last
  loop
    exit when clock_timestamp() - v_tg > c_guard_skin;
    v_old := pg_temp.fight_resolve_old_0353(c_seed, v_x.d, v_x.r, v_x.esc, v_x.ships);
    v_new := voyage.fight_resolve(c_seed, v_x.d, v_x.r, v_x.esc, v_x.ships);
    v_f   := voyage.raid_report(c_seed, v_x.d, v_x.r, v_x.esc, v_x.ships, '{}'::jsonb);
    v_skin_n := v_skin_n + 1;
    if v_old::text is distinct from v_new::text or v_old::text is distinct from v_f::text then
      raise exception '0353 self-assert FAIL: SKIN PARITY: a raid changed (day %, raid %): % against % and %', v_x.d, v_x.r, v_old, v_new, v_f;
    end if;
    v_skin_kinds := jsonb_set(v_skin_kinds, array[v_old ->> 'outcome'], 'true'::jsonb);
    -- and the log leaves the words alone: with {log} the English rounds, the sentence and every old key are the old body's; the log's rounds are the fight's
    if v_x.r > 0 then
      v_g := voyage.raid_report(c_seed, v_x.d, v_x.r, v_x.esc, v_x.ships, '{"log": true}'::jsonb);
      if (v_g - 'log')::text is distinct from v_old::text or (v_g -> 'log' ->> 'v')::int is distinct from 1
         or jsonb_array_length(v_g -> 'log' -> 'r') is distinct from (v_old ->> 'rounds_fought')::int
         or jsonb_array_length(v_g -> 'log' -> 'you') is distinct from jsonb_array_length(v_x.ships) or jsonb_array_length(v_g -> 'log' -> 'after') is distinct from jsonb_array_length(v_x.ships)
         or v_g -> 'log' ? 'order' or coalesce(v_g -> 'log' ->> 'end', '') not in ('STOOD', 'SLIP', 'BROKE', 'THREW', 'TERMS', 'TAKEN', 'GAVE')
         or (select coalesce(sum((y ->> 1)::numeric), 0) from jsonb_array_elements(v_g -> 'log' -> 'you') y)
            - (select coalesce(sum((y ->> 1)::numeric), 0) from jsonb_array_elements(v_g -> 'log' -> 'after') y)
            is distinct from (select coalesce(sum(hl.value::numeric), 0) from jsonb_each_text(v_old -> 'hull_lost') hl) then
        raise exception '0353 self-assert FAIL: a log moved the words, or is not the fight''s own numbers: %', v_g;
      end if;
    end if;
  end loop;
  if v_skin_n < c_min_skin or not (v_skin_kinds ?& array['EVADED', 'DRIVEN_OFF', 'RANSOM', 'PLUNDERED']) then
    raise exception '0353 self-assert FAIL: SKIN PARITY compared only % raid(s) in % (the least is %), or met too few endings (%)', v_skin_n, c_guard_skin, c_min_skin, v_skin_kinds;
  end if;
  v_ms := v_ms || jsonb_build_object('skin_parity', round(extract(epoch from clock_timestamp() - v_tp) * 1000)); v_tp := clock_timestamp();

  -- the words of Flee and Pay through the skin: a paid day and a day she got away, each by its sentence, its flag and its log. It stops when both were met and c_guard_words has passed.
  v_m := 0; v_bad := 0;
  v_tg := clock_timestamp();
  for v_x in select d from generate_series(1, 60) d loop
    exit when v_m > 0 and v_bad > 0 and clock_timestamp() - v_tg > c_guard_words;
    v_f := voyage.raid_report(c_seed, v_x.d, 12, 6.66, v_barca, '{"log": true, "order": "PAY"}'::jsonb);
    v_g := voyage.raid_report(c_seed, v_x.d, 12, 6.66, v_barca, '{"log": true, "order": "FLEE"}'::jsonb);
    if (v_f ->> 'paid')::boolean then
      v_m := v_m + 1;
      if v_f ->> 'outcome' is distinct from 'RANSOM' or v_f ->> 'sentence' is distinct from 'We paid their price and they let us pass.' or v_f -> 'log' ->> 'end' is distinct from 'PAID' or v_f -> 'log' ->> 'order' is distinct from 'PAY'
         or v_f -> 'hull_lost' is distinct from '{}'::jsonb or v_f -> 'log' -> 'r' is distinct from '[]'::jsonb then
        raise exception '0353 self-assert FAIL: a paid raid in words: %', v_f;
      end if;
    end if;
    if (v_g ->> 'fled')::boolean then
      v_bad := v_bad + 1;
      if v_g ->> 'outcome' is distinct from 'EVADED' or v_g ->> 'sentence' is distinct from 'We ran, and got clear of them.' or v_g -> 'log' ->> 'end' is distinct from 'FLED' or v_g -> 'log' ->> 'order' is distinct from 'FLEE'
         or not exists (select 1 from jsonb_array_elements_text(v_g -> 'rounds') t where t like '%you run before them%')
         or exists (select 1 from jsonb_array_elements(v_g -> 'log' -> 'r') e where jsonb_typeof(e -> 13) is distinct from 'number' or jsonb_array_length(e) is distinct from 14) then
        raise exception '0353 self-assert FAIL: a flight in words: %', v_g;
      end if;
    end if;
  end loop;
  if v_m = 0 or v_bad = 0 then
    raise exception '0353 self-assert FAIL: 60 days met no paid raid (%) or no flight away (%)', v_m, v_bad;
  end if;
  v_f := voyage.raid_report(c_seed, 3, 12, 6.66, v_barca, '{"log": true, "pay_refused": "EMPTY"}'::jsonb);
  if v_f ? 'paid' or v_f -> 'log' ->> 'no_pay' is distinct from 'EMPTY' or v_f -> 'log' ? 'order'
     or (v_f - 'log' - 'rounds')::text is distinct from (voyage.fight_resolve(c_seed, 3, 12, 6.66, v_barca) - 'rounds')::text then
    raise exception '0353 self-assert FAIL: a refused Pay is not the fight she would have had, with the reason in the log: %', v_f;
  end if;
  v_ms := v_ms || jsonb_build_object('words', round(extract(epoch from clock_timestamp() - v_tp) * 1000)); v_tp := clock_timestamp();

  -- ── 11. THE GUARDS ──
  -- 0320's own test on the new engine body, the same allow-list: it names no table
  select regexp_replace(p.prosrc, '--[^\n]*', '', 'g') into v_src from pg_proc p where p.oid = c_eng::regprocedure;
  if v_src ~* '\m(join|update|insert|delete|execute)\M' or v_src ~* '\mfrom\s+(?!generate_subscripts\(|public\.fight_volley\()' then
    raise exception '0353 self-assert FAIL: the engine names a table';
  end if;
  if exists (select 1 from regexp_matches(v_src, '\m((public|voyage|world|cmd)\.[a-z_]+)', 'g') w(a)
              where w.a[1] not in ('public.wc', 'public.wc_num', 'public.fight_volley', 'public.armour_soak', 'voyage.rng')) then
    raise exception '0353 self-assert FAIL: the engine reads through something that is not world_config';
  end if;
  -- the skin, its leaf and the round line read no table
  for v_x in select unnest(array[c_rep, c_skin, 'voyage.raid_extras(jsonb,jsonb,jsonb,jsonb)', 'voyage.fight_round_line(jsonb,integer,text,jsonb,numeric,text)']) f loop
    select regexp_replace(p.prosrc, '--[^\n]*', '', 'g') into v_src from pg_proc p where p.oid = v_x.f::regprocedure;
    if v_src ~* '\m(join|update|insert|delete|execute)\M' or v_src ~* '\mfrom\s+(?!jsonb_array_elements(_text)?\()' then
      raise exception '0353 self-assert FAIL: % names a table', v_x.f;
    end if;
    if exists (select 1 from regexp_matches(v_src, '\m((public|voyage|world|cmd)\.[a-z_]+)', 'g') w(a)
                where w.a[1] not in ('voyage.raider_hulls', 'public.fight_sides', 'voyage.fight_round_line', 'voyage.raid_extras', 'voyage.raid_report')) then
      raise exception '0353 self-assert FAIL: % reads through something that is not the fight', v_x.f;
    end if;
  end loop;
  if (select p.prosrc from pg_proc p where p.oid = c_rep::regprocedure) ~ 'ship_classes|fight:|voyage\.rng'
     or (select p.prosrc from pg_proc p where p.oid = c_skin::regprocedure) ~ 'ship_classes|fight:|voyage\.rng|fight_sides' then
    raise exception '0353 self-assert FAIL: a skin fights';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prosrc like '%wc_text(''fight_raider_class'')%'
                and p.oid is distinct from 'voyage.raider_hulls(numeric)'::regprocedure) then
    raise exception '0353 self-assert FAIL: raiders are built in a second place';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prosrc ~ 'fleet_raid_orders'
                and p.oid <> all (array['voyage.freeze_order(jsonb,uuid)'::regprocedure::oid, 'cmd.raid_order(uuid,text)'::regprocedure::oid, 'world.raid_read(uuid)'::regprocedure::oid])) then
    raise exception '0353 self-assert FAIL: the order table is read or written in a fourth place';
  end if;
  -- no client calls a new function but the two doors, each in the registry once
  if exists (select 1 from unnest(c_new_fns) f cross join unnest(array['anon', 'authenticated']) r(role)
              where has_function_privilege(r.role, f, 'execute') and not (r.role = 'authenticated' and f = any (c_doors))) then
    raise exception '0353 self-assert FAIL: a client may call a new function that is not a door, or anon may call a door';
  end if;
  if exists (select 1 from unnest(c_doors) f where not has_function_privilege('authenticated', f, 'execute'))
     or (select count(*) from public.client_rpc_entry_points()) is distinct from v_entry + 2
     or (select count(*) from public.client_rpc_entry_points() e where e.fn = any (array['cmd.raid_order(uuid,text)'::regprocedure, 'world.raid_read(uuid)'::regprocedure])) is distinct from 2 then
    raise exception '0353 self-assert FAIL: the two doors are not granted to authenticated and registered once each';
  end if;
  if (select p.provolatile from pg_proc p where p.oid = 'world.raid_read(uuid)'::regprocedure) is distinct from 's'
     or (select p.provolatile from pg_proc p where p.oid = 'voyage.raid_opts(uuid,integer,uuid)'::regprocedure) is distinct from 's'
     or (select p.provolatile from pg_proc p where p.oid = 'voyage.freeze_order(jsonb,uuid)'::regprocedure) is distinct from 's' then
    raise exception '0353 self-assert FAIL: a read is not STABLE';
  end if;
  if has_table_privilege('anon', 'public.fleet_raid_orders', 'select,insert,update,delete')
     or has_table_privilege('authenticated', 'public.fleet_raid_orders', 'select,insert,update,delete')
     or not (select c.relrowsecurity from pg_class c where c.oid = 'public.fleet_raid_orders'::regclass)
     or (select count(*) from public.client_write_grants()) is distinct from 0 then
    raise exception '0353 self-assert FAIL: a client can read or write the order table, or it has no row level security';
  end if;
  if exists (select 1 from public.fleet_raid_orders) then
    raise exception '0353 self-assert FAIL: an order row exists at the deploy';
  end if;
  execute 'drop function pg_temp.fight_resolve_old_0353(uuid, integer, numeric, numeric, jsonb)';
  execute 'drop function pg_temp.fight_sides_old_0353(uuid, integer, jsonb, jsonb, jsonb)';
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid <> all (select f::regprocedure::oid from unnest(c_cut_fns || c_skin || c_new_fns) f)) is distinct from v_fn_before then
    raise exception '0353 self-assert FAIL: a function this file does not name moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key <> all (c_knobs)) is distinct from v_cfg_before
     or (select count(*) from public.world_config c where c.key = any (c_knobs)) is distinct from array_length(c_knobs, 1)
     or public.raid_orders_on() then
    raise exception '0353 self-assert FAIL: an existing world_config row moved, a knob of this file is missing, or the switch is not off';
  end if;

  v_ms := v_ms || jsonb_build_object('guards', round(extract(epoch from clock_timestamp() - v_tp) * 1000)); v_tp := clock_timestamp();

  -- ── 12. THE DOORS, on a probe of this file's own rows, rolled back ──
  begin
    select p.id into v_lis from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR';
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values (c_uid, 'Casa da Ordem 0353', (select n.id from public.nations n where n.code = 'PRT'), 5000, false) returning id into v_pl;
    insert into public.players (auth_uid, company_name, nation_id, ducats, is_npc)
    values (null, 'Casa Mercante 0353', (select n.id from public.nations n where n.code = 'PRT'), 0, true) returning id into v_npc;
    v_fl := public.form_fleet(v_pl, 'Ordem', v_lis);
    perform public.commission_ship(v_pl, v_fl, 'barca', 'Ordem', true, true);
    v_nfl := public.form_fleet(v_npc, 'Mercante', v_lis);
    perform public.commission_ship(v_npc, v_nfl, 'barca', 'Mercante', true, true);
    v_segs := jsonb_build_array(jsonb_build_object('nm', 100, 'sea_id', (select s.id from public.seas s order by s.code limit 1), 'danger', 0.2),
                                jsonb_build_object('nm', 50, 'sea_id', (select s.id from public.seas s order by s.code limit 1), 'danger', 0.2));
    perform cmd.assume_identity(c_uid);

    -- (a) DARK: the door refuses, the read says off, a departure's segments are its input, a frozen order is not read
    v_r := cmd.raid_order(v_fl, 'FLEE');
    if v_r ->> 'error_code' is distinct from 'E_NOT_IN_USE' or world.raid_read(v_fl) is distinct from '{"on": false}'::jsonb
       or voyage.freeze_order(v_segs, v_fl)::text is distinct from v_segs::text or voyage.freeze_order(v_segs, v_nfl)::text is distinct from v_segs::text
       or voyage.freeze_order(v_segs, null)::text is distinct from v_segs::text
       or voyage.leg_order('{"order": "FLEE"}'::jsonb) is not null or exists (select 1 from public.fleet_raid_orders) then
      raise exception '0353 self-assert FAIL: dark, the door, the read or the freeze did something: %', v_r;
    end if;
    -- a merchant's raid is fought with {}; a company's with a log and no order
    if voyage.raid_opts(c_seed, 1, v_nfl) is distinct from '{}'::jsonb or voyage.raid_opts(c_seed, 1, v_fl) is distinct from '{"log": true}'::jsonb or voyage.raid_opts(c_seed, 1, null) is distinct from '{}'::jsonb then
      raise exception '0353 self-assert FAIL: a merchant''s raid is not fought with {}, or a company''s not with a log alone';
    end if;

    -- (b) LIT (here only; rolled back)
    update public.world_config set value = 'true'::jsonb where key = 'raid_orders_enabled';
    v_r := cmd.raid_order(v_fl, 'FLEE');
    if v_r is distinct from '{"ok": true, "order": "FLEE"}'::jsonb or (select o.raid_order from public.fleet_raid_orders o where o.fleet_id = v_fl) is distinct from 'FLEE'
       or voyage.freeze_order(v_segs, v_fl)::text is distinct from jsonb_build_array(v_segs -> 0 || '{"order": "FLEE"}'::jsonb, v_segs -> 1 || '{"order": "FLEE"}'::jsonb)::text
       or voyage.freeze_order(v_segs, v_nfl)::text is distinct from v_segs::text
       or voyage.leg_order(voyage.freeze_order(v_segs, v_fl) -> 1) is distinct from 'FLEE' or voyage.leg_order(v_segs -> 0) is not null then
      raise exception '0353 self-assert FAIL: Flee was not kept, or not frozen on each segment of her fleet alone: %', v_r;
    end if;
    v_r := world.raid_read(v_fl);
    if (v_r ->> 'on')::boolean is not true or v_r ->> 'order' is distinct from 'FLEE' or (v_r ->> 'guns')::boolean is not false or coalesce(v_r ->> 'slip', '') not in ('poor', 'fair', 'good')
       or (v_r ->> 'pay')::bigint is distinct from 0 or coalesce(jsonb_array_length(v_r -> 'foes'), 0) < 1
       or exists (select 1 from jsonb_array_elements(v_r -> 'foes') e where coalesce(e ->> 'word', '') not in ('weaker', 'even', 'stronger', 'far_stronger') or coalesce((e ->> 'danger')::int, 0) not between 1 and 5) then
      raise exception '0353 self-assert FAIL: the read of a gunless, empty barca under Flee: %', v_r;
    end if;
    v_r := cmd.raid_order(v_fl, 'PAY');
    if v_r is distinct from '{"ok": true, "order": "PAY"}'::jsonb or (select o.raid_order from public.fleet_raid_orders o where o.fleet_id = v_fl) is distinct from 'PAY' then
      raise exception '0353 self-assert FAIL: Pay did not replace Flee: %', v_r;
    end if;
    if cmd.raid_order(v_fl, 'RUN') ->> 'error_code' is distinct from 'E_BAD_ORDER' or cmd.raid_order(v_fl, null) ->> 'error_code' is distinct from 'E_BAD_ORDER'
       or cmd.raid_order(v_nfl, 'FLEE') ->> 'error_code' is distinct from 'E_NO_SUCH_FLEET' or cmd.raid_order(gen_random_uuid(), 'FLEE') ->> 'error_code' is distinct from 'E_NO_SUCH_FLEET'
       or world.raid_read(v_nfl) is distinct from '{"on": false}'::jsonb
       or (select o.raid_order from public.fleet_raid_orders o where o.fleet_id = v_fl) is distinct from 'PAY' or exists (select 1 from public.fleet_raid_orders o where o.fleet_id is distinct from v_fl) then
      raise exception '0353 self-assert FAIL: a bad order or another company''s fleet was taken';
    end if;

    -- (c) THE ORDER REACHES THE RAID through a frozen segment (a stub voyage row of this probe; the real passage is proof 56)
    v_voy := gen_random_uuid();
    insert into public.voyages (id, fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta, status, origin_port_id, dest_port_id)
    values (v_voy, v_fl, v_pl, voyage.freeze_order(v_segs, v_fl), 150, '[5, 5]', now() - interval '10 minutes', now() - interval '1 minute', 'ARRIVED', v_lis, v_lis);
    v_r := voyage.raid_opts(v_voy, 1, v_fl);
    if v_r is distinct from '{"log": true, "pay_refused": "EMPTY"}'::jsonb then
      raise exception '0353 self-assert FAIL: Pay with an empty hold is not refused as EMPTY: %', v_r;
    end if;
    update public.ships s set cargo = '{"probe_0353": 10}'::jsonb, cargo_basis = '{"probe_0353": 1000}'::jsonb where s.fleet_id = v_fl;
    v_take := public.raid_price(v_fl);
    v_r := voyage.raid_opts(v_voy, 1, v_fl);
    if v_take is distinct from floor(10000 * public.wc_num('ransom_share'))
       or v_r is distinct from (case when public.raid_payee(null) is null then '{"log": true, "pay_refused": "NO_PAYEE"}'::jsonb else '{"log": true, "order": "PAY"}'::jsonb end)
       or (world.raid_read(v_fl) ->> 'pay')::bigint is distinct from v_take then
      raise exception '0353 self-assert FAIL: Pay with 10,000 d. aboard: take %, opts % (payee %)', v_take, v_r, public.raid_payee(null);
    end if;
    -- the money, where this world has a payee (purses lit, a capital, the hoard under its cap); where it has none, nothing moves
    select pl.ducats into v_purse from public.players pl where pl.id = v_pl;
    v_m := public.raid_ransom(null, v_pl, public.fleet_stock_at_cost(v_fl));
    if public.raid_payee(null) is null then
      v_note := 'no payee in this world (purses dark, no capital, or the hoard at its cap): Pay is refused and nothing moved';
      if v_m is distinct from 0 or (select pl.ducats from public.players pl where pl.id = v_pl) is distinct from v_purse then
        raise exception '0353 self-assert FAIL: with no payee a ransom moved %', v_m;
      end if;
    else
      v_note := format('a payee: a ransom of %s moved from the probe''s purse', v_m);
      if v_m is distinct from least(v_take, v_purse) or (select pl.ducats from public.players pl where pl.id = v_pl) is distinct from v_purse - v_m then
        raise exception '0353 self-assert FAIL: a ransom of % did not leave the purse (% before)', v_m, v_purse;
      end if;
    end if;
    update public.voyages set path = jsonb_build_array(v_segs -> 0 || '{"order": "FLEE"}'::jsonb) where id = v_voy;
    if voyage.raid_opts(v_voy, 1, v_fl) is distinct from '{"log": true, "order": "FLEE"}'::jsonb then
      raise exception '0353 self-assert FAIL: a frozen Flee did not reach the raid';
    end if;
    update public.world_config set value = 'false'::jsonb where key = 'raid_orders_enabled';
    if voyage.raid_opts(v_voy, 1, v_fl) is distinct from '{"log": true}'::jsonb then
      raise exception '0353 self-assert FAIL: with the switch off a frozen order was still read';
    end if;
    update public.world_config set value = 'true'::jsonb where key = 'raid_orders_enabled';

    -- (d) FIGHT is no row
    v_r := cmd.raid_order(v_fl, 'FIGHT');
    if v_r is distinct from '{"ok": true, "order": "FIGHT"}'::jsonb or exists (select 1 from public.fleet_raid_orders o where o.fleet_id = v_fl)
       or voyage.freeze_order(v_segs, v_fl)::text is distinct from v_segs::text or world.raid_read(v_fl) ->> 'order' is distinct from 'FIGHT' then
      raise exception '0353 self-assert FAIL: Fight left a row, or a departure froze an order';
    end if;
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);
    if cmd.raid_order(v_fl, 'FLEE') ->> 'error_code' is distinct from 'E_NO_HOUSE' or world.raid_read(v_fl) is distinct from '{"on": false}'::jsonb then
      raise exception '0353 self-assert FAIL: a caller with no house set an order or read one';
    end if;
    raise exception using errcode = 'ZX353', message = 'PROBE_ROLLBACK_0353';
  exception when sqlstate 'ZX353' then
    v_lived := true;
  end;
  if not v_lived then
    raise exception '0353 self-assert FAIL: the probe did not run to its end';
  end if;
  if exists (select 1 from public.players p where p.company_name like 'Casa % 0353' or p.auth_uid = c_uid)
     or exists (select 1 from public.fleet_raid_orders) or public.raid_orders_on() then
    raise exception '0353 self-assert FAIL: the probe left something behind';
  end if;
  if public.current_player_id() is not null then
    raise exception '0353 self-assert FAIL: the probe''s identity outlived its rollback';
  end if;

  v_ms := v_ms || jsonb_build_object('doors_probe', round(extract(epoch from clock_timestamp() - v_tp) * 1000)); v_tp := clock_timestamp();

  -- ── 13. THE NEWS (0347's law): C1 is live at the deploy and is news. C2 is dark and is not announced here: its news belongs to the file that lights raid_orders_enabled. ──
  perform public.news_update('0353', 'Fight log', '전투 기록');

  if extract(epoch from clock_timestamp() - v_t0) > 40 then
    raise exception '0353 self-assert FAIL: the file took % (budget 40 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0353 timings (ms a part): %; total % ms. Bounds: engine parity %, orders %, skin %, words %.', v_ms, round(extract(epoch from clock_timestamp() - v_t0) * 1000), c_guard_parity, c_guard_orders, c_guard_skin, c_guard_words;
  raise notice '0353 self-assert ok: A FIGHT KEEPS ITS LOG, AND A FLEET HAS A STANDING ORDER (C1 + C2). ENGINE PARITY, bounded by the clock: % pairs on % of the 1,120 fights of 0320''s matrix (the least is %), the kept live engine against the new one as text, with no option, with the sizing-up and with a_order FIGHT said: all equal (%). SKIN PARITY: % raids of 1,082 (the least is %), the kept live skin against voyage.fight_resolve and voyage.raid_report with {}: all equal, and a log moves no word. ORDERS on % fights (the least is %): Flee, no shot of hers, every round''s chance the rule''s, % away, % caught and boarded; Pay, % RANSOM before a shot, the rest stood off or slipped unchanged; % round limits, % left open, each the first rows of the full run. The whole matrix every time: proof 56. 20 hunks, each once and reversing; ACL, volatility, definer and config unmoved; the engine names no table; no other function and no existing knob moved; the switch is off and no order row exists. The doors (probe, rolled back): %. % ms.',
    v_pairs, v_n, c_min_pairs, v_kinds, v_skin_n, c_min_skin, v_ord_n, c_min_orders, v_fled, v_caught, v_paid, v_pre_n, v_open_n, v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
