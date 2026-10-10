-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0100 — THE WORLD RUNS TEN TIMES SLOWER
--        time_compression 9600 → 960. A voyage-day was 9 real seconds; it is 90.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE ASK ─────────────────────────────────────────────────────────────────────────────────────
-- The owner, 2026-10-10, watching the merchants on the map: *"change the speed of the ships half"*,
-- then *"change the speed of the ship at least 10 times slower"*. 0045 had made the world twenty
-- times FASTER explicitly "for faster testing" (its own words), and a voyage-day has been 9 real
-- seconds ever since — a hull crosses Iberia while you read her name. This is the testing speed
-- being handed back.
--
-- ── WHY THE CLOCK AND NOT THE KNOTS ─────────────────────────────────────────────────────────────
-- There are two ways to make a ship slower and only one of them is a speed:
--
--   * `voyage.ship_speed` (the hull's knots, 0006:325 as re-cut by 0074). Dividing it by ten
--     multiplies by ten the VOYAGE-DAYS every passage takes — and stores are consumed per
--     voyage-day, and `voyage.sail_refusal` refuses a sail the fleet cannot provision for the round
--     trip (0036:724). A Lisbon→Kochi leg of 11 voyage-days becomes 110, which no hold can carry
--     water and food for. Every ocean route in the game would refuse to sail. The owner asked for
--     this in the same hour as *"there are no trades seen between different continents"*, so a
--     change that makes intercontinental trade impossible is not the change they asked for.
--   * `time_compression` — how much voyage-time a real second buys. Dividing it by ten leaves
--     every in-world quantity exactly as it was (a passage is still 11 voyage-days, still wants 12
--     days of stores, still pays the same wages per day) and makes the player watch it for ten
--     times longer. That is what "the ships are slower" looks like on a map, and it breaks nothing.
--
-- So: the clock. The hull's knots are untouched and `data/ship-classes` still means what it says.
--
-- **THIS REACHES PRODUCTION ON THE NEXT DEPLOY.** As 0045 put it: if the live world should keep
-- 9-second days, this file is reverted by a superseding migration that sets it back — not by a flag.
--
-- ── THE SAME TRAP 0045 FOUND, FACING THE OTHER WAY ──────────────────────────────────────────────
-- A voyage's `eta` is STORED at departure and its day boundaries are RE-DERIVED on every read from
-- `departed_at + hours / time_compression` (0006:503-508). 0045 raised the knob and every fleet at
-- sea finished her remaining days at once while waiting on a stored arrival. LOWERING it is the
-- mirror: the derived boundaries now fall far in the FUTURE while the stored `eta` stays where the
-- old rate put it, so a fleet would arrive — `tick_arrivals` reads the stored eta — with days of
-- her passage unresolved, and the hazards of those days would never roll at all.
--
-- So every SAILING voyage is re-ETAd here through `voyage.recompute_eta`, the ONE ETA authority,
-- exactly as 0045 did. The past is untouched: `voyage_events` already written stay written and
-- `speed_profile` is not re-frozen. Only the arrival instant moves, and this time it moves LATER.
--
-- ── WHAT IS DELIBERATELY NOT TOUCHED ────────────────────────────────────────────────────────────
-- `game_day_seconds` (2880) — the calendar clock the market, the daily caps and the fairs run on
-- (0005:44). The owner asked for SHIPS to be slower, not for the economy to be re-timed. The two
-- clocks have drifted apart before and 0045 said so out loud when it left this one alone; saying it
-- again: a game-day was 320 voyage-days and is now 32. Prices still drift and caps still roll at
-- the same real-world rate, so a lap buys and sells against a market that moves as it always did —
-- there is simply more real time inside each lap. If the calendar should slow too, that is a second
-- decision and a second migration.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

update public.world_config
   set value = to_jsonb(960),
       description = 'DESIGN D.1. 1 real second = 0.27 voyage-hours; 1 voyage-day = 90 real seconds. '
                     'Was 9600 (0045, x20 "for faster testing"); the owner handed that speed back on '
                     '2026-10-10 (0100). The hull''s knots are not this knob: see 0100''s header.'
 where key = 'time_compression';

-- Every fleet already at sea keeps a coherent passage: the stored arrival and the derived day
-- boundaries must agree, or she arrives with days of her voyage unresolved.
do $$
declare
  v_id    uuid;
  v_moved int := 0;
begin
  for v_id in select id from public.voyages where status = 'SAILING' loop
    perform voyage.recompute_eta(v_id);
    v_moved := v_moved + 1;
  end loop;
  if v_moved > 0 then
    raise notice '0100: % voyage(s) at sea were re-ETAd through the one ETA authority', v_moved;
  end if;
end $$;

do $$
declare
  v_comp    numeric;
  v_secs    numeric;
  v_fleet   uuid;
  v_player  uuid;
  v_voy     uuid;
  v_eta_old timestamptz;
  v_eta_new timestamptz;
  v_eta_fast timestamptz;
  v_lis     uuid;
  v_dest    uuid;
  v_dep     timestamptz;
  v_course  jsonb;
  v_segs    jsonb;
  v_res     jsonb;
  f_probe   boolean := false;
  v_dest_code text;
  v_legs    int;
begin
  -- 1. THE KNOB MOVED, and to exactly a tenth of what it was.
  v_comp := public.wc_num('time_compression');
  if v_comp <> 960 then
    raise exception '0100 self-assert FAIL: time_compression is %, expected 960', v_comp;
  end if;
  if 9600 / v_comp <> 10 then
    raise exception '0100 self-assert FAIL: % is not a tenth of the 9600 it replaced', v_comp;
  end if;

  -- 2. A VOYAGE-DAY IS NINETY REAL SECONDS, derived from the knob and never retyped (0045's rule:
  --    a second copy of this arithmetic is how two clocks come to disagree).
  v_secs := 24 * 3600 / v_comp;
  if round(v_secs, 3) <> 90 then
    raise exception '0100 self-assert FAIL: a voyage-day is % real second(s), expected 90', v_secs;
  end if;

  -- 3. THE POSITIVE CONTROL. A fresh chain has no fleet at sea, so the re-ETA loop above would run
  --    zero times and prove nothing. A real house is put to sea inside a subtransaction and the
  --    arrival is required to follow the knob in BOTH directions — earlier at the old rate, later
  --    at the new one — then the whole probe is rolled back.
  begin
    select id into v_lis from public.ports where code = 'LIS';
    v_player := public.new_house('00000000-0000-4000-8000-000000000100'::uuid, 'Casa Lenta', 'PRT');
    select f.id into v_fleet from public.fleets f where f.player_id = v_player limit 1;

    -- LISBON → SETÚBAL, ROADSTEAD TO ROADSTEAD. 0045's probe asked public.legs for a neighbour and
    -- called voyage.route to plan the hop; 0047 dropped that mover and 0049 dropped that table, so
    -- copying the probe forward without reading what it stands on fails on a relation that has not
    -- existed for fifty migrations (this file did exactly that, once). The modern shape: a COURSE
    -- of verified water, measured into segments by the server's own authority, handed to depart.
    -- This pair is not a guess — 0085's own self-assert sailed a real house LIS → SET on the
    -- roadstead-to-roadstead line and walked it with the land guard — and it is one short hop,
    -- inside any fleet's stores by construction (the trap 0045's probe fell into first).
    select id into v_dest from public.ports where code = 'SET';
    v_dest_code := 'SET';
    select jsonb_build_array(
             jsonb_build_array(a.roadstead_lat, a.roadstead_lon),
             jsonb_build_array(b.roadstead_lat, b.roadstead_lon))
      into v_course
      from public.sea_reaches a, public.sea_reaches b
     where a.port_id = v_lis and b.port_id = v_dest;
    select count(*) into v_legs from public.sea_reaches where port_id in (v_lis, v_dest);
    if v_course is null or v_dest is null then
      raise exception '0100 self-assert FAIL: Lisbon or Setubal has no served roadstead to sail between (% row(s))', v_legs;
    end if;

    -- Departed through voyage.depart, not cmd.issue: a migration has no auth.uid() (0045's note).
    v_segs := voyage.segments_from_course(v_course);
    v_res := to_jsonb(voyage.depart(v_fleet, v_segs, v_lis, v_dest, now()));
    select id, eta, departed_at into v_voy, v_eta_old, v_dep
      from public.voyages where fleet_id = v_fleet and status = 'SAILING';

    if v_voy is not null then
      update public.world_config set value = to_jsonb(9600) where key = 'time_compression';
      v_eta_fast := voyage.recompute_eta(v_voy);
      if v_eta_fast >= v_eta_old then
        raise exception '0100 self-assert FAIL: at the OLD rate the arrival did not move earlier (% -> %)',
          v_eta_old, v_eta_fast;
      end if;
      update public.world_config set value = to_jsonb(960) where key = 'time_compression';
      v_eta_new := voyage.recompute_eta(v_voy);
      if v_eta_new <= v_eta_fast then
        raise exception '0100 self-assert FAIL: at the NEW rate the arrival did not go back out (% vs %)',
          v_eta_new, v_eta_fast;
      end if;
      -- AND THE PASSAGE IS TEN TIMES LONGER IN REAL TIME than the SAME passage at 9600 — the
      -- owner's own sentence, not a fact about a knob. The two instants are measured from the one
      -- departure, at the two rates, which is the only comparison that means anything here.
      if round(extract(epoch from v_eta_new - v_dep)
               / nullif(extract(epoch from v_eta_fast - v_dep), 0)) <> 10 then
        raise exception '0100 self-assert FAIL: the passage is % times as long, not ten (% vs %)',
          round(extract(epoch from v_eta_new - v_dep) / nullif(extract(epoch from v_eta_fast - v_dep), 0), 2),
          v_eta_new, v_eta_fast;
      end if;
      f_probe := true;
    end if;
    raise exception 'ROLLBACK_0100_PROBE';
  exception when others then
    if sqlerrm <> 'ROLLBACK_0100_PROBE' then raise; end if;
  end;

  if not f_probe then
    raise exception '0100 self-assert FAIL: the probe never got a fleet to sea (dest %, legs out of LIS %, depart said %) — nothing here was proven',
      coalesce(v_dest_code, '(none chosen)'), v_legs, left(coalesce(v_res::text, '(null)'), 200);
  end if;
  if v_eta_fast is null then
    raise exception '0100 self-assert FAIL: the probe never re-ETAd the voyage it put to sea';
  end if;

  -- 4. THE PROBE LEFT NOTHING BEHIND — a delta, never a count (production carries real houses).
  if exists (select 1 from public.players where auth_uid = '00000000-0000-4000-8000-000000000100'::uuid) then
    raise exception '0100 self-assert FAIL: the probe house survived the subtransaction';
  end if;

  raise notice '0100 self-assert ok: THE WORLD RUNS TEN TIMES SLOWER. time_compression is %, exactly '
    'a tenth of the 9600 that 0045 set "for faster testing", and a voyage-day is % real second(s) '
    'derived from the knob rather than retyped; every fleet already at sea was re-ETAd through '
    'voyage.recompute_eta, the one ETA authority, so no fleet arrives with days of her passage '
    'unresolved; proven on a real voyage put to sea and rolled back, whose arrival moved EARLIER '
    'when the knob was wound back to 9600 and LATER when it was returned to 960, and whose passage '
    'is ten times as long in real time at the new rate; the probe house left no row behind. The '
    'hull''s knots are untouched — stores, wages and refusals are all per voyage-day and are '
    'unchanged — and game_day_seconds (2880) is deliberately untouched, so the market drifts and '
    'the daily caps roll at the real-world rate they always did.',
    v_comp, round(v_secs, 3);
end $$;
