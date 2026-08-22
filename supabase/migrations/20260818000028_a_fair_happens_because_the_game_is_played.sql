-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0028 — A FAIR HAPPENS BECAUSE THE GAME IS PLAYED, AND THE OTHER CLOCK FINALLY CROSSES THE WIRE
--        A world rule whose existence depends on one screen being looked at is not a world rule.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── WHAT THIS SUPERSEDES, AND WHY THE TWO MOVE TOGETHER ────────────────────────────────────────
--   world.fleets()    0009:149, re-cut 0017:650 — gains ONE statement: it winds the buff calendar.
--   world.snapshot()  0009:68,  re-cut 0019:622 — gains ONE served knob, `game_day_seconds`, and
--                     ONE served catalogue, `nations`.
--
-- The first two are one file because they are the two halves of one sentence the player reads. A
-- fair has to HAPPEN (0026's calendar, wound by a read the game actually makes) and the player has
-- to be able to be TOLD how long one lasts (the calendar clock, which until this file never
-- crossed the wire). Land the first alone and the catalogue still cannot print a duration; land
-- the second alone and the durations it prints describe fairs that only exist at ports somebody
-- opened. 0017:50-55's rule, applied: everything that must move together moves in one file.
--
-- The third rides here because it is the SAME DEFECT — a fact the server owns that never crossed
-- the wire, leaving a screen with nothing honest to print — and because it lands in the same
-- function, on the same allow-list, under the same byte-parity assert. See DEFECT 3.
--
-- Neither of these functions is otherwise touched. That is not a promise in this paragraph — the
-- self-assert takes `pg_get_functiondef` of BOTH before the replacement, strips exactly the lines
-- this file marks `0028 WIND`, and requires what is left to equal the old definition to the
-- character. If a single other byte moved, this migration does not apply.
--
-- ── DEFECT 1: A FAIR EXISTED ONLY IF ONE SCREEN WAS VISITED ────────────────────────────────────
-- 0026 gave the calendar ONE writer, `public.tick_buff_calendar()`, and reached it two ways:
-- pg_cron where the platform has one, and `world.buffs()` where it does not — "the read IS the
-- catch-up", 0009's idiom. PGlite has no pg_cron, and neither does a Supabase project until the
-- extension is enabled. So on this deployment the only thing in the entire world that ever drew a
-- fair ANYWHERE was `src/features/port/PortFair.tsx` mounting — a player opening the PORT tab.
--
-- Two consequences, and the second is the worse one:
--   * a player who never opens PORT lives in a world where no fair ever happens, at any port, for
--     anybody — including the ports other players are standing on;
--   * a future refactor that stops PORT calling it ("only fetch when a fair is on", "nothing
--     changed, so don't re-ask") switches a world rule off for everyone, silently, and the panel
--     stays perfectly correct while it does. PortFair.tsx carries a comment begging nobody to do
--     that. A rule defended by a comment is a rule with no owner.
--
-- ── WHY world.fleets() AND NOT world.snapshot() ────────────────────────────────────────────────
-- `world.snapshot()` was the obvious candidate and it is the WRONG one. The cadences, read off the
-- client rather than assumed:
--
--   src/live/worldStore.ts:237   open()     — calls world.snapshot() ONCE per session, then caches
--                                             it (0009:20, "the client caches it hard")
--   src/live/worldStore.ts:285   refresh()  — world.fleets() + world.ledger() + world.player()
--   src/app/AppShell.tsx:17,36   READ_INTERVAL_MS = 30 s, and again on every visibilitychange
--
-- Winding in `snapshot()` would move the fair from "a tab was opened" to "the app was launched" —
-- a smaller bug of exactly the same shape, and one that leaves a session running all evening on a
-- calendar frozen at boot. `world.fleets()` is the read that happens BECAUSE THE GAME IS BEING
-- PLAYED.
--
-- Three more facts settled it, and each is independently disqualifying for snapshot():
--   * `world.fleets()` ALREADY winds a clock — it calls `voyage.settle()` for every fleet, and it
--     is where 0009 put "the read is the catch-up" in the first place. The world's calendar beside
--     the fleet's is one concept in one place, not a second one.
--   * `world.fleets()` is already VOLATILE and already writes. `world.snapshot()` is
--     `language sql STABLE`, and PostgreSQL refuses a write inside a non-volatile function at
--     runtime — so winding there meant turning the game's one cached read into a writer.
--   * COST, measured rather than argued. PGlite (PostgreSQL 18.3 / PGlite 0.5.5), this machine, chain applied
--     through 0027, one founded house with one fleet, the calendar already settled for the slot so
--     that nothing is due. Timed INSIDE the server with clock_timestamp(), 200 calls x 15 batches, median batch; three independent runs agreed within 0.04 ms:
--
--         world.fleets()      1.455 ms  ->  1.695 ms   (+0.240 ms, +16.5 per cent)
--         world.snapshot()   16.820 ms  -> 17.015 ms   (+0.195 ms — the nations
--                                                        catalogue, not the wind; it is not a caller)
--         tick_buff_calendar() alone, settled slot:  0.185 ms
--
--     What the fleet read buys is one index probe on `active_buffs_calendar` (0026:226) and one
--     DELETE over the pruning window that matches nothing. Both are rounding errors beside the
--     per-fleet `voyage.settle()` the same function already runs on every call — and the whole
--     added cost is 0.240 ms once every thirty seconds, per player, against the 16.820 ms this
--     client already spends opening the world once.
--
-- ── WHAT IS NOT CHANGED, DELIBERATELY ──────────────────────────────────────────────────────────
--   * `world.buffs()` KEEPS WINDING. It is not superseded and not touched. It is a second CALLER
--     of one writer, not a second writer, and there is no ceiling on callers
--     (docs/NO_SPAGHETTI.md §1). The self-assert proves it still winds, from this file, after the
--     replacement — because "I did not touch it" is not evidence that it still works.
--   * `public.tick_buff_calendar()` is NOT re-cut. Not one line of when-a-fair-happens moves here.
--     If this file had needed to change the draw, it would have been the wrong fix.
--   * The pruning DELETE stays inside the tick rather than being moved under its short-circuit.
--     It is measured above as part of the added cost and it is not the part that costs; moving it
--     would be retuning 0026's writer to pay for a caller, which is backwards.
--
-- ── WHAT THIS DOES TO THE PROOFS, MEASURED AND STATED RATHER THAN DISCOVERED LATER ────────────
-- 0026 wrote down that scripts/db/proofs/04 and 05 measure a world in which public.active_buffs
-- is EMPTY, "because nothing in those files calls world.buffs() or the tick". HALF OF THAT
-- SENTENCE STOPS BEING TRUE HERE, and it is this file's job to say so:
--
--   proof 05  UNAFFECTED. It never calls world.fleets(). BALANCE_MEDIAN_IN_BAND — the pinned
--             measurement — therefore measures exactly what it measured before, which is the band
--             for the ORDINARY economy. Verified by reading the files rather than assumed: the
--             only occurrence of "world.fleets" anywhere under scripts/db/proofs/ is 04:363.
--   proof 04  NOW WINDS THE CALENDAR, at 04:363, where it settles the fleet home. Measured on a
--             fresh chain: the wind draws 22 fairs across 214 ports for the season, of which the
--             number LIVE at any one instant is about three on the arithmetic and read ZERO on
--             the run that was measured. The proof trades at two ports, so the chance of either
--             holding a live fair is small — and the effect is one-directional, because a fair
--             only makes a trade CHEAPER, so FIRST_SESSION_HOME_RICHER can only be helped by it.
--             Every other marker in that file is structural.
--
-- This file does NOT reach into the proofs to clear the table and make 04 fair-free again. That
-- would be a migration editing a test fixture to protect a number, and the number it would be
-- protecting is not pinned by anything. It is recorded here so that the next person who reads a
-- moved figure in proof 04 knows where to look first.
--
-- ── DEFECT 2: THE CLIENT COULD NOT HONESTLY PRINT HOW LONG A FAIR LASTS ────────────────────────
-- `world.buffs()` serves `duration_game_days`, `season_game_days` and `chance_per_season`. All
-- three are counted on the CALENDAR clock — `game_day_seconds` (0005:44) — and nothing on the wire
-- said how long a game-day is. `snapshot.config` carried `time_compression` alone, which is the
-- VOYAGE clock and a different rate, while `formatVoyageDays` (src/lib/format/time.ts:48) spells
-- voyage-days as plain "days" on FLEETS, COMMAND, MARKET and PORT. A catalogue printing "lasts 4
-- days" beside that roster would have been read on the wrong clock, so 0026's panel correctly
-- printed none of the three and wrote down why. This file serves the missing number and that
-- comment is deleted in the same change.
--
-- ── AND ARE THEY REALLY TWO CLOCKS? YES. THE ANSWER IS NOT "ONE CLOCK WITH TWO NAMES" ──────────
-- DESIGN D.1 authors two, with disjoint governance — the voyage clock over sailing, provisions,
-- wages and hazard checkpoints; the calendar clock over season, wind regime, ice closure, seasonal
-- goods and the investment season. They are two RATES because they must be: at one rate either a
-- passage costs the better part of an hour per day at sea, or a game year passes in an afternoon
-- and a season stops meaning anything. Collapsing them would be a design change, not a tidy-up,
-- and it would take the game with it.
--
-- What IS wrong — and it is a naming defect rather than a modelling one — is that both are called
-- "days" and only one of them ever crossed the wire. That is the whole of the confusion, and it is
-- what this file fixes: the wire now carries both rates, and the self-assert below MEASURES that a
-- client reading the fair's duration on the voyage clock would have been wrong, and by exactly
-- what factor. That factor is computed from the two served knobs and printed in the receipt rather
-- than written into this paragraph, because a number in a comment dies the day the knob moves.
--
-- ── DEFECT 3: A NATION CROSSED THE WIRE AS A CODE AND COULD NOT BE TURNED BACK INTO A NAME ────
-- `world.standings()` serves `nation` as a bare code — `PRT`, `ESP`, `NLD` (0025:326) — and so
-- does `world.snapshot().ports[].nation` (0009:78). The only place a nation's NAME has ever
-- crossed the wire is `world.player().nation_name`, and that is your OWN house's nation and
-- nobody else's. So the table of captains had a choice between printing a code at a player, in a
-- game where `portNameOf` exists precisely because "the server speaks in codes; a player has
-- never been shown one and should not be" (src/live/worldStore.ts:192-208), or growing a client-side
-- code -> name table. The second is the authority this repo has already deleted once: the port
-- fallback had been hand-written SEVEN times before it was folded (worldStore.ts:192-208).
--
-- TWO SHAPES WERE POSSIBLE AND THE OTHER ONE IS WORSE, stated rather than left implied:
--
--   nation_name ON THE BOARD ROW.  REJECTED. It fixes exactly one screen. `snapshot.ports[]`
--     would still carry an unresolvable code, so MAP and PORT would still have nothing — and the
--     wire would then hold THREE spellings of what a nation is called (`player.nation_name`, the
--     board's copy, and whatever the next surface adds), each on a payload fetched at a different
--     moment. Two sites that can print different answers to one question are two authorities even
--     while they agree (docs/NO_SPAGHETTI.md §1, question 3).
--
--   A CATALOGUE ON THE SNAPSHOT.  TAKEN. `public.nations` is authored static world data, exactly
--     like ports, goods and ship classes, and those three are already served here and cached hard.
--     One catalogue, one lookup, and every nation code in the game — the board's, the port's, and
--     any that a later read invents — resolves through it. `world.player().nation_name` is left
--     alone: it is a fact about YOUR house on a payload that already carries your house, and it is
--     asserted below to still agree with the catalogue, so the two cannot drift apart in silence.
--
-- ── GRANTS: THIS FILE GRANTS AND REVOKES NOTHING NEW. ──────────────────────────────────────────
-- Two existing entry points are re-cut. `create or replace` preserves an ACL, but 0017 and 0019
-- both re-issued theirs explicitly after a re-cut and so does this — an assumed grant is how a
-- read wall came down in 0018 and had to be rebuilt in 0023. No new function, no new table, no new
-- row in `public.client_rpc_entry_points()`.
--
-- Depends ONLY on: 0005 (game_day_seconds, world.game_day), 0009/0017 (world.fleets), 0009/0019
--                  (world.snapshot), 0026 (buff_kinds, active_buffs, tick_buff_calendar,
--                  buff_season_of, world.buffs), 0018/0023 (the grant authorities).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- THE PRE-IMAGES. The LIVE definitions and the LIVE payload, captured before a line of either
-- function moves, so "nothing else changed" is a comparison rather than a sentence — 0020's idiom
-- (capture the deployed schema, strip the one thing that is allowed to differ, require equality).
-- Scaffolding for two asserts; dropped at the foot of this file.
create temporary table fleets_def_before_0028 as
  select pg_get_functiondef('world.fleets()'::regprocedure) as src;

create temporary table snapshot_before_0028 as
  select world.snapshot()                                     as payload,
         pg_get_functiondef('world.snapshot()'::regprocedure) as src;

-- ── 1. SUPERSEDES 0017:650 — THE READ THAT IS THE CATCH-UP NOW CATCHES UP THE WORLD TOO ───────
create or replace function world.fleets()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_player uuid := public.current_player_id();
  r        record;
begin
  -- 0028 WIND: THE WORLD'S CALENDAR IS WOUND HERE, because this is the read that happens because
  -- 0028 WIND: the game is being PLAYED — every 30 s from AppShell and again whenever a tab regains
  -- 0028 WIND: focus — and a world rule that only happens when one screen is opened is not a world
  -- 0028 WIND: rule. There is still ONE writer of the calendar (public.tick_buff_calendar, 0026);
  -- 0028 WIND: this is a CALLER of it, beside pg_cron and world.buffs(). It is idempotent by
  -- 0028 WIND: construction, so every call after the first in a season costs one index probe.
  -- 0028 WIND: DO NOT make it conditional: a condition here switches fairs off for the whole world.
  perform public.tick_buff_calendar();  -- 0028 WIND
  if v_player is null then return '[]'::jsonb; end if;

  -- DESIGN D.2: the read is the catch-up. Nine hours offline resolve here, in order, before a
  -- single number is reported.
  for r in select id from public.fleets where player_id = v_player loop
    perform voyage.settle(r.id);
  end loop;

  return (select coalesce(jsonb_agg(jsonb_build_object(
    'id', f.id, 'name', f.name, 'status', f.status, 'version', f.version,
    'port', (select code from public.ports where id = f.port_id),
    'busy_until', f.busy_until,
    'speed_kn', voyage.fleet_speed(f.id),
    'endurance_days', round(voyage.endurance_days(f.id), 1),
    'free_hold', public.fleet_free_hold(f.id),
    'officer_pct', jsonb_build_object(
        'NAVIGATOR',     round(public.fleet_officer_bonus(f.id, 'NAVIGATOR')     * 100, 2),
        'QUARTERMASTER', round(public.fleet_officer_bonus(f.id, 'QUARTERMASTER') * 100, 2),
        'SURGEON',       round(public.fleet_officer_bonus(f.id, 'SURGEON')       * 100, 2),
        'PURSER',        round(public.fleet_officer_bonus(f.id, 'PURSER')        * 100, 2)),
    'voyage', (select jsonb_build_object(
                 'id', v.id, 'to', (select code from public.ports where id = v.dest_port_id),
                 'eta', v.eta, 'total_nm', v.total_nm,
                 'nm_done', voyage.progress_nm(v.id),
                 'position', (select to_jsonb(pos) from voyage.position(v.id) pos))
                 from public.voyages v where v.fleet_id = f.id and v.status = 'SAILING'),
    'ships', (select coalesce(jsonb_agg(jsonb_build_object(
                 'id', s.id, 'name', s.name, 'class', c.name, 'is_flagship', s.is_flagship,
                 'durability', s.durability, 'max_durability', c.durability,
                 'crew', s.crew, 'crew_required', c.crew_required, 'crew_max', c.crew_max,
                 'hold', public.ship_hold_capacity(s.id), 'hold_rated', c.hold,
                 'cargo', s.cargo, 'cargo_tuns', public.ship_cargo_tuns(s.id),
                 'water_t', s.water_t, 'food_t', s.food_t) order by s.is_flagship desc, s.name), '[]'::jsonb)
                 from public.ships s join public.ship_classes c on c.id = s.class_id
                where s.fleet_id = f.id),
    'queue', cmd.queue(f.id)) order by f.created_at), '[]'::jsonb)
    from public.fleets f where f.player_id = v_player);
end $$;

revoke all on function world.fleets() from public, anon;
grant execute on function world.fleets() to authenticated;

comment on function world.fleets() is
  'The roster of DESIGN E.2, and THE CATCH-UP READ. It settles every voyage this house has at sea '
  '(0009) and it winds the world''s buff calendar (0026, via public.tick_buff_calendar) — because '
  'this is the read the client makes on a timer for as long as the game is open, and a fair that '
  'only happens when somebody opens the PORT tab is not a rule of the world.';

-- ── 2. SUPERSEDES 0019:622 — THE WIRE CARRIES BOTH CLOCKS, AND WHAT A NATION IS CALLED ────────
-- One config key, which makes DESIGN D.1's second clock convertible on the client, and one
-- catalogue beside the three this read already serves. The allow-list shape of 0009:99 is
-- unchanged and world_config is still never served wholesale, so the assert below re-proves that
-- the world secret does not leave.
create or replace function world.snapshot()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    -- 0028 WIND: THE NATIONS, as a catalogue — the shape ports, goods and ship classes are already
    -- 0028 WIND: served in. Every payload in this game that mentions a nation says its CODE and
    -- 0028 WIND: only its code: snapshot.ports[].nation (0009:78) and world.standings().board[]
    -- 0028 WIND: .nation (0025:326). Nothing on the wire could turn one into a name, so a screen
    -- 0028 WIND: could only print "PRT" or grow its own code -> name table — which is exactly the
    -- 0028 WIND: second authority src/live/worldStore.ts:192-208 records having deleted once
    -- 0028 WIND: already, for ports, after it had been hand-written seven times. ONE catalogue,
    -- 0028 WIND: cached with the static world, resolves every nation code the game ever serves.
    'nations', (select coalesce(jsonb_agg(jsonb_build_object(                          -- 0028 WIND
        'id', n.id, 'code', n.code, 'name', n.name, 'flag_char', n.flag_char,          -- 0028 WIND
        'capital', n.capital_port_code) order by n.code), '[]'::jsonb)                 -- 0028 WIND
      from public.nations n),                                                          -- 0028 WIND
    'ports', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', p.id, 'code', p.code, 'name', p.name, 'country', p.country,
        'nation', n.code, 'lat', p.lat, 'lon', p.lon, 'sea', s.name, 'region', r.code,
        'culture', p.culture, 'size_tier', p.size_tier, 'max_draft', p.max_draft,
        'has_yard', p.has_yard, 'yard_tier', p.yard_tier, 'has_academy', p.has_academy,
        'is_ice_closed', p.is_ice_closed, 'tax_rate', p.tax_rate, 'crew_pool', p.crew_pool,
        'dev_industry', p.dev_industry, 'dev_commerce', p.dev_commerce, 'dev_military', p.dev_military)
        order by p.code), '[]'::jsonb)
      from public.ports p
      left join public.nations n on n.id = p.nation_id
      join public.seas s on s.id = p.sea_id
      join public.regions r on r.id = p.region_id),
    'legs', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', l.id, 'from', a.code, 'to', b.code, 'nm', l.distance_nm,
        'hazard_mult', l.hazard_mult, 'notes', l.notes) order by a.code, b.code), '[]'::jsonb)
      from public.legs l join public.ports a on a.id = l.from_port_id
                         join public.ports b on b.id = l.to_port_id),
    'goods', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', g.id, 'code', g.code, 'name', g.name, 'base_value', g.base_value,
        'bulk', g.bulk, 'category', g.category, 'perishable_pct_day', g.perishable_pct_day,
        'culture_mask', g.culture_mask) order by g.code), '[]'::jsonb) from public.goods g),
    'ship_classes', (select coalesce(jsonb_agg(to_jsonb(c) order by c.tier), '[]'::jsonb)
      from public.ship_classes c),
    -- The knobs the CLIENT legitimately needs, named one by one. Serving world_config wholesale
    -- would ship the hazard seed to every browser; an allow-list is the only safe shape.
    'config', jsonb_build_object(
        -- 0028 WIND: THE CALENDAR CLOCK (0005:44), beside the voyage clock it does NOT run at. Both
        -- 0028 WIND: are DESIGN D.1's, both are counted in "days", and until this line only one of
        -- 0028 WIND: them crossed the wire — so a client served a figure in game-days could print it
        -- 0028 WIND: on the wrong clock or not at all, and 0026's catalogue chose not at all.
        'game_day_seconds',  public.wc_num('game_day_seconds'),  -- 0028 WIND
        'time_compression',  public.wc_int('time_compression'),
        'order_queue_max',   public.wc_int('order_queue_max'),
        'fleet_max',         public.wc_int('fleet_max'),
        'ship_max',          public.wc_int('ship_max'),
        'endurance_margin',  public.wc_num('endurance_margin'),
        'trade_step_tuns',   public.wc_int('trade_step_tuns'),
        'water_per_crew_day', public.wc_num('water_per_crew_day'),
        'food_per_crew_day',  public.wc_num('food_per_crew_day'),
        'wage_per_crew_day',  public.wc_num('wage_per_crew_day'),
        -- 0019: the three numbers MARKET used to declare for itself.
        'neighbour_radius_nm', public.wc_num('neighbour_radius_nm'),
        'advice_buy_below',    public.wc_num('advice_buy_below'),
        'advice_sell_above',   public.wc_num('advice_sell_above')),
    'verbs', cmd.verb_schema())
$$;

revoke all on function world.snapshot() from public, anon;
grant execute on function world.snapshot() to authenticated;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_old_fleets   text;
  v_new_fleets   text;
  v_old_snap_src text;
  v_new_snap_src text;
  v_snap0        jsonb;
  v_snap1        jsonb;
  v_secret       text := public.wc_text('world_secret');
  v_kind         public.buff_kinds%rowtype;
  v_season       int;
  v_expect       int;
  v_wound1       int;
  v_digest1      text;
  v_digest2      text;
  v_wound2       int;
  v_again        int;
  v_bwound       int;
  v_starts       timestamptz;
  v_ends         timestamptz;
  v_window_s     numeric;
  v_cal_day_s    numeric;
  v_voy_day_s    numeric;
  v_client_s     numeric;
  v_wrong_s      numeric;
  v_ratio        numeric;
  v_writers      int;
  v_readers      int;
  v_callers      int;
  v_caller_names text;
  v_rows_before  int;
  v_rows_after   int;
  c_probe        constant uuid := '00000000-0028-4000-8000-000000000028';
  v_player       uuid;
  v_board        jsonb;
  v_nations      int;
  v_unres_ports  int;
  v_unres_board  int;
  v_named_ports  int;
  v_my_nation    text;
  v_cat_nation   text;
  v_houses       int;
  f_fleets_noop  boolean := false;
  f_snap_noop    boolean := false;
  f_secret       boolean := false;
  f_wind         boolean := false;
  f_idem         boolean := false;
  f_buffs        boolean := false;
  f_window       boolean := false;
  f_two_clocks   boolean := false;
  f_one_writer   boolean := false;
  f_nations      boolean := false;
  f_board        boolean := false;
  f_grant        boolean := false;
begin
  -- ══════════════════════════════════════════════════════════════════════════════════════════════
  -- (a) world.fleets() GAINED EXACTLY THE MARKED LINES AND NOTHING ELSE. Strip every line this
  --     file marked `0028 WIND` out of the LIVE definition and what is left must be the definition
  --     that was live a moment ago, to the character. The second term is the positive control: if
  --     the strip removed nothing the first term would pass vacuously on an unchanged function.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════
  select src into v_old_fleets from fleets_def_before_0028;
  v_new_fleets := pg_get_functiondef('world.fleets()'::regprocedure);
  if regexp_replace(v_new_fleets, E'[^\n]*0028 WIND[^\n]*\n', '', 'g') = v_old_fleets
     and v_new_fleets <> v_old_fleets
     and position('perform public.tick_buff_calendar()' in v_new_fleets) > 0
     and position('tick_buff_calendar' in v_old_fleets) = 0 then
    f_fleets_noop := true;
  end if;

  -- ══════════════════════════════════════════════════════════════════════════════════════════════
  -- (b) world.snapshot() GAINED EXACTLY ONE CONFIG KEY AND ONE CATALOGUE, AND NOTHING ELSE MOVED.
  --     Proven on the PAYLOAD, not on the source: every other section of the served world must be
  --     identical jsonb, the config object must be identical once the new key is removed, and both
  --     additions must have been ABSENT before — otherwise "it gained a key" would be true of a
  --     file that changed nothing. The source comparison sits beside it as corroboration, the way
  --     0018's catalogue read does beside its behavioural probe.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════
  select payload, src into v_snap0, v_old_snap_src from snapshot_before_0028;
  v_snap1        := world.snapshot();
  v_new_snap_src := pg_get_functiondef('world.snapshot()'::regprocedure);
  v_cal_day_s    := public.wc_num('game_day_seconds');
  if (v_snap1 - 'config' - 'nations') = (v_snap0 - 'config' - 'nations')
     and ((v_snap1->'config') - 'game_day_seconds') = (v_snap0->'config')
     and not ((v_snap0->'config') ? 'game_day_seconds')
     and not (v_snap0 ? 'nations')
     and (v_snap1->'config'->>'game_day_seconds')::numeric = v_cal_day_s
     and regexp_replace(v_new_snap_src, E'[^\n]*0028 WIND[^\n]*\n', '', 'g') = v_old_snap_src then
    f_snap_noop := true;
  end if;

  -- (b2) THE CATALOGUE IS COMPLETE AND IT ACTUALLY RESOLVES WHAT THE WIRE CARRIES. Complete means
  --      "every row the table holds", COUNTED FROM THE TABLE — a literal here would be asserting
  --      the size of a world somebody once seeded (0009:277-279). And the point of the catalogue
  --      is not that it exists: it is that EVERY nation code any payload serves is in it. Both
  --      port codes and, below, board codes are swept. v_named_ports is the positive control:
  --      a world where no port named a nation would make the zero above meaningless.
  select count(*) into v_nations from jsonb_array_elements(v_snap1->'nations');
  select count(*) into v_named_ports
    from jsonb_array_elements(v_snap1->'ports') p where p->>'nation' is not null;
  select count(*) into v_unres_ports
    from jsonb_array_elements(v_snap1->'ports') p
   where p->>'nation' is not null
     and not exists (select 1 from jsonb_array_elements(v_snap1->'nations') n
                      where n->>'code' = p->>'nation');
  if v_nations = (select count(*) from public.nations)
     and v_nations > 0
     and v_named_ports > 0
     and v_unres_ports = 0
     and (select bool_and(coalesce(length(n->>'name'), 0) > 1 and n->>'code' is not null)
            from jsonb_array_elements(v_snap1->'nations') n) then
    f_nations := true;
  end if;

  -- (c) AND THE SECRET STILL DOES NOT LEAVE. 0009 (b) re-run, because this file edited the very
  --     allow-list that assert exists to police. Searched for by VALUE in the serialised payload.
  if position(v_secret in v_snap1::text) = 0 and length(v_secret) >= 8 then
    f_secret := true;
  end if;

  select * into v_kind from public.buff_kinds where code = 'FAIR';
  if v_kind.code is null or v_kind.season_game_days is null then
    raise exception '0028 self-assert FAIL: there is no calendar-driven FAIR kind, so every winding and duration test below would be vacuous';
  end if;
  v_voy_day_s := 86400.0 / (v_snap1->'config'->>'time_compression')::numeric;
  v_client_s  := v_kind.duration_game_days * v_cal_day_s;
  v_wrong_s   := v_kind.duration_game_days * v_voy_day_s;

  select count(*) into v_rows_before from public.active_buffs;

  begin
    -- ── inside the throwaway subtransaction ────────────────────────────────────────────────────
    -- This file deploys onto a live world that may already be holding fairs, so every row it
    -- writes or clears is rolled away and the rollback is asserted afterwards.

    v_season := public.buff_season_of(now(), v_kind.season_game_days);
    select count(*) into v_expect
      from public.ports p
     where voyage.rng(p.id, v_season, 'buff:' || v_kind.code) < v_kind.chance_per_season;
    if v_expect = 0 then
      raise exception '0028 self-assert FAIL: season % drew no % at any of the world''s ports, so the winding tests below would be vacuous. This is not random — it is voyage.rng over (port, season, world secret) — so it is a fact about this season and this secret', v_season, v_kind.code;
    end if;

    -- (d) THE WIND, FROM THE READ THE GAME ACTUALLY MAKES. NO identity is assumed and NO quay is
    --     opened: world.fleets() answers '[]' to a caller with no house, and must STILL have wound
    --     the world on its way to saying so. The count is not "more than zero" — it is the exact
    --     set voyage.rng draws for this season, re-derived here, so a tick that wrote a fair for
    --     everybody or for the wrong ports fails just as loudly as one that wrote nothing.
    delete from public.active_buffs;
    perform world.fleets();
    select count(*), md5(coalesce(string_agg(ab.id::text, ',' order by ab.id), ''))
      into v_wound1, v_digest1
      from public.active_buffs ab where ab.kind_code = v_kind.code and ab.season = v_season;
    f_wind := (v_wound1 = v_expect);

    -- (e) AND IT IS STILL IDEMPOTENT FROM THE NEW CALLER. 0026 asserts this of the tick; the claim
    --     that matters now is that the read which runs every thirty seconds does not walk the
    --     calendar again on every one of them. Both directions: the second read moves no row, and
    --     the writer itself reports having written none.
    perform world.fleets();
    select count(*), md5(coalesce(string_agg(ab.id::text, ',' order by ab.id), ''))
      into v_wound2, v_digest2
      from public.active_buffs ab where ab.kind_code = v_kind.code and ab.season = v_season;
    v_again := public.tick_buff_calendar(now());
    -- ROW IDENTITY, not a row COUNT. active_buffs.id is a gen_random_uuid() default, so a writer
    -- that cleared its season and drew it again would leave the same NUMBER of fairs with entirely
    -- different ids — and a count comparison would call that idempotent. It is not: it is a write
    -- on every read, and on a live world it would restart every running fair's row thirty seconds
    -- at a time. Found by break-testing this very assert, which passed the first break aimed at it.
    f_idem := (v_wound2 = v_wound1 and v_digest2 = v_digest1 and v_again = 0);

    -- (f) 0026'S CALLER STILL WINDS. This file does not touch world.buffs(), and "I did not touch
    --     it" is not evidence that it works. Cleared and re-wound through the OTHER door.
    delete from public.active_buffs;
    perform world.buffs(null::uuid);
    select count(*) into v_bwound
      from public.active_buffs where kind_code = v_kind.code and season = v_season;
    f_buffs := (v_bwound = v_expect);

    -- (g) THE SEAM — the reason `game_day_seconds` is on the wire at all. Take a fair the writer
    --     actually drew, and require that the catalogue figure the client is served, multiplied by
    --     the clock the client is now served, reproduces the real window the server wrote, to the
    --     second. That is the whole claim "a client can honestly print how long a fair lasts",
    --     measured end to end rather than asserted about a knob. The subject is picked by port
    --     CODE, so it is the same fair on every replay and never a heap-order lottery (0014:248).
    select ab.starts_at, ab.ends_at into v_starts, v_ends
      from public.active_buffs ab
      join public.ports p on p.id = ab.subject_id
     where ab.kind_code = v_kind.code and ab.season = v_season
     order by p.code
     limit 1;
    v_window_s := extract(epoch from (v_ends - v_starts));
    f_window   := (v_window_s = v_client_s);

    -- (h) AND THE OTHER CLOCK WOULD HAVE BEEN WRONG. The negative control for this whole file: if
    --     the voyage clock reproduced the same window, `time_compression` was already enough and
    --     the served key is decoration. It does not, and the factor is printed rather than pinned.
    f_two_clocks := (v_voy_day_s <> v_cal_day_s) and (v_wrong_s <> v_window_s);
    v_ratio      := round(v_cal_day_s / v_voy_day_s, 4);

    -- (j) THE SEAM THE CATALOGUE EXISTS FOR. A REAL house on a REAL board, read through
    --     world.standings(), and every nation code that board serves must resolve in the
    --     catalogue world.snapshot() serves. A catalogue that is complete against its own table
    --     but misses the spelling another read uses would be a lookup that quietly returns
    --     nothing, which is how a screen ends up printing "PRT" anyway. And world.player()'s own
    --     nation_name — the one name that already crossed the wire — must AGREE with the
    --     catalogue's, or the two spellings have already drifted.
    v_player := public.new_house(c_probe, 'Casa da Bandeira', 'PRT');
    perform cmd.assume_identity(c_probe);
    v_board  := world.standings(10);
    select count(*) into v_unres_board
      from jsonb_array_elements(v_board->'board') r
     where not exists (select 1 from jsonb_array_elements(v_snap1->'nations') n
                        where n->>'code' = r->>'nation');
    v_my_nation  := world.player()->'player'->>'nation_name';
    select n->>'name' into v_cat_nation
      from jsonb_array_elements(v_snap1->'nations') n
     where n->>'code' = (world.player()->'player'->>'nation');
    f_board := (jsonb_array_length(v_board->'board') >= 1
                and v_unres_board = 0
                and v_my_nation is not null
                and v_cat_nation = v_my_nation);
    perform set_config('request.jwt.claim.sub', '', true);
    perform set_config('request.jwt.claims', '', true);

    raise exception '__PROBE_ROLLBACK_0028__' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> '__PROBE_ROLLBACK_0028__' then raise; end if;
  end;
  -- ── the subtransaction is gone; the findings survived it, because plpgsql variables are not
  --    transactional (0026's shape). ───────────────────────────────────────────────────────────

  -- (i) ONE WRITER, N CALLERS — the guard against the fix this file was NOT allowed to be. If
  --     anybody ever answers "a fair does not happen often enough" by writing a second function
  --     that draws one, this goes red and names it. `v_readers` is the positive control: the same
  --     catalogue scan must be able to SEE functions that merely read the table, or the count of
  --     one writer is a scan that found nothing.
  select count(*) into v_writers
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'world', 'cmd', 'voyage')
     and (position('insert into public.active_buffs' in p.prosrc) > 0
       or position('delete from public.active_buffs' in p.prosrc) > 0);
  select count(*) into v_readers
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'world', 'cmd', 'voyage')
     and position('public.active_buffs' in p.prosrc) > 0;
  select count(*), string_agg(n.nspname || '.' || p.proname, ', ' order by n.nspname, p.proname)
    into v_callers, v_caller_names
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'world', 'cmd', 'voyage')
     and position('tick_buff_calendar' in p.prosrc) > 0;
  f_one_writer := (v_writers = 1 and v_readers >= 3
                   and v_callers = 2 and v_caller_names = 'world.buffs, world.fleets');

  if not f_fleets_noop then
    raise exception '0028 self-assert FAIL: world.fleets() is not its 0017 definition plus exactly the lines this file marked 0028 WIND. Stripping them left % character(s) against the % the pre-image holds, so something else in that function moved', length(regexp_replace(v_new_fleets, E'[^\n]*0028 WIND[^\n]*\n', '', 'g')), length(v_old_fleets);
  end if;
  if not f_snap_noop then
    raise exception '0028 self-assert FAIL: world.snapshot() did not gain exactly one config key. It serves % key(s) against the % it served before, game_day_seconds reads % against the knob''s %, or a section outside config moved', (select count(*) from jsonb_object_keys(v_snap1->'config')), (select count(*) from jsonb_object_keys(v_snap0->'config')), v_snap1->'config'->>'game_day_seconds', v_cal_day_s;
  end if;
  if not f_secret then
    raise exception '0028 self-assert FAIL: world.snapshot() CONTAINS the world secret — this file edited the allow-list and the allow-list leaked';
  end if;
  if not f_wind then
    raise exception '0028 self-assert FAIL: world.fleets() wound % fair(s) where voyage.rng draws % for season % — the read that happens because the game is being played did not draw the calendar, or drew the wrong ports', v_wound1, v_expect, v_season;
  end if;
  if not f_idem then
    raise exception '0028 self-assert FAIL: a second world.fleets() took the calendar from % row(s) to %, the writer then reported % more, and the row ids digested % against % — the read that runs every thirty seconds is walking the calendar every time, or re-drawing the same fairs as brand new rows, which is a write on every read either way', v_wound1, v_wound2, v_again, v_digest2, v_digest1;
  end if;
  if not f_buffs then
    raise exception '0028 self-assert FAIL: world.buffs() wound % fair(s) against the % it drew before this file — 0026''s caller was supposed to be untouched, and a second caller of one writer is only safe while both still work', v_bwound, v_expect;
  end if;
  if not f_window then
    raise exception '0028 self-assert FAIL: a % of % game-day(s) actually runs for % second(s), but the figures now on the wire (duration_game_days x game_day_seconds) say % — a client doing that arithmetic would print a duration this server does not keep', v_kind.code, v_kind.duration_game_days, v_window_s, v_client_s;
  end if;
  if not f_two_clocks then
    raise exception '0028 self-assert FAIL: the calendar clock (% s/day) and the voyage clock (% s/day) are the same rate, or the voyage clock already reproduced the fair''s % second window from % game-days — in which case time_compression was always enough and this file served a key nothing needed', v_cal_day_s, v_voy_day_s, v_window_s, v_kind.duration_game_days;
  end if;
  if not f_nations then
    raise exception '0028 self-assert FAIL: world.snapshot() serves % nation(s) against the % public.nations holds, % of % port(s) that name a nation cannot resolve it in the catalogue, or a served nation carries no name — a catalogue that cannot answer the codes the wire already carries is not a fix, it is a second thing to look in', v_nations, (select count(*) from public.nations), v_unres_ports, v_named_ports;
  end if;
  if not f_board then
    raise exception '0028 self-assert FAIL: % of the % board row(s) world.standings() serves carry a nation code that is not in the served catalogue, or world.player() reports nation_name "%" where the catalogue says "%" — the two spellings of what a nation is called have drifted, which is the reason there is supposed to be one', v_unres_board, jsonb_array_length(v_board->'board'), coalesce(v_my_nation, '(null)'), coalesce(v_cat_nation, '(null)');
  end if;
  if not f_one_writer then
    raise exception '0028 self-assert FAIL: % function(s) write public.active_buffs (exactly 1 may), % read it (the scan must see at least 3, or it is finding nothing), and tick_buff_calendar is called by % function(s): [%]. Expected exactly world.buffs and world.fleets — one writer, two callers, and pg_cron', v_writers, v_readers, v_callers, coalesce(v_caller_names, '(none)');
  end if;

  -- THE ROLLBACK REALLY ROLLED BACK. Not "the table is empty" — a live world may legitimately be
  -- holding fairs — but "the table is exactly as many rows as it was before this probe emptied it
  -- twice and re-drew it three times". On a fresh chain both counts are zero and this is the
  -- assertion that the probe committed nothing; on a live world it is the assertion that it
  -- destroyed nothing.
  select count(*) into v_rows_after from public.active_buffs;
  if v_rows_after <> v_rows_before then
    raise exception '0028 self-assert FAIL: public.active_buffs held % row(s) before the probe and holds % after it — the subtransaction did not roll back', v_rows_before, v_rows_after;
  end if;
  select count(*) into v_houses from public.players where auth_uid = c_probe;
  if v_houses <> 0 then
    raise exception '0028 self-assert FAIL: % probe house(s) survived the subtransaction', v_houses;
  end if;

  -- POSTURE. Two re-cut entry points, both still exactly where 0018 and 0023 left them, and the
  -- machinery this file composes onto still unreachable by any client.
  if has_function_privilege('authenticated', 'world.fleets()', 'execute')
     and not has_function_privilege('anon', 'world.fleets()', 'execute')
     and has_function_privilege('authenticated', 'world.snapshot()', 'execute')
     and not has_function_privilege('anon', 'world.snapshot()', 'execute')
     and not has_function_privilege('authenticated', 'public.tick_buff_calendar(timestamptz)', 'execute')
     and not has_function_privilege('anon', 'public.tick_buff_calendar(timestamptz)', 'execute')
     and has_function_privilege('service_role', 'public.tick_buff_calendar(timestamptz)', 'execute')
     and not has_table_privilege('authenticated', 'public.active_buffs', 'select')
     and (select count(*) from public.client_write_grants()) = 0
     and (select count(*) from public.client_executable_writers()) = 0
     and (select count(*) from public.client_rpc_entry_points() e where e.fn is null) = 0
     and (select count(*) from public.caller_evaluated_functions()) = 0 then
    f_grant := true;
  end if;
  if not f_grant then
    raise exception '0028 self-assert FAIL: a re-cut read lost or widened its grant — world.fleets and world.snapshot must be executable by authenticated and not by anon, tick_buff_calendar by service_role only, active_buffs unreadable by a client, with 0 client write grants, 0 client-executable writers, 0 read-wall gaps and every catalogued entry point resolving';
  end if;

  raise notice '0028 self-assert ok: A FAIR NOW HAPPENS BECAUSE THE GAME IS BEING PLAYED. world.fleets() — the read AppShell makes every thirty seconds and on every tab focus — wound % fair(s) with NO house signed in and NO quay opened, and % is exactly the set voyage.rng draws for season % from (port, season, world secret), so it drew the right quays and not merely some; a second read moved % further row(s) and the writer then reported % more, so the thirty-second cadence costs one index probe; world.buffs() still winds through its own door (% row(s)), because there is still ONE writer of the calendar — % function(s) write public.active_buffs, % read it, and tick_buff_calendar has exactly % callers [%] beside pg_cron; world.fleets() is its 0017 definition plus ONLY the lines marked 0028 WIND, proven by stripping them out of pg_get_functiondef and matching the pre-image character for character, and world.snapshot() gained EXACTLY one config key and one catalogue on an otherwise byte-identical payload, with the world secret still absent from it; a NATION is no longer a code nobody can read — % nation(s) are served beside the ports, every one of the % port(s) that names a nation resolves in it, every row of a real world.standings() board resolves in it (% unresolved), and world.player()''s own nation_name still says the very same word the catalogue does ("%"); and the wire finally carries BOTH of DESIGN D.1''s clocks — a % lasts % game-day(s), which the served game_day_seconds (%) turns into % real second(s), the very window this server wrote, while the voyage clock (% s/day, time_compression %) would have made it % second(s): the two clocks differ by a factor of % and that is exactly how wrong a client printing game-days as "days" would have been',
    v_wound1, v_expect, v_season,
    v_wound2 - v_wound1, v_again,
    v_bwound,
    v_writers, v_readers, v_callers, coalesce(v_caller_names, '(none)'),
    v_nations, v_named_ports, v_unres_board, v_cat_nation,
    v_kind.code, v_kind.duration_game_days, v_cal_day_s, v_window_s,
    v_voy_day_s, (v_snap1->'config'->>'time_compression'), v_wrong_s, v_ratio;
end $$;

drop table fleets_def_before_0028;
drop table snapshot_before_0028;
