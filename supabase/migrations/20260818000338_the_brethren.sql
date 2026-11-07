-- ═══════════════════════════════════════════════════════════════════════════════════════════════════
-- 0338 — THE BRETHREN (W16): the pirates, the 11th great power. Four free homes, war with the ten, three new harbours, a joining knob that ships FALSE. DARK for play except the four free ports (and they have a lever)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER (docs/OWNER_REQUESTS.md row 284, 2026-11-05): "pirate headquarters with pirate cities, npcs that attack these ships as well as merchants"; "pirates are like countries - power, where they can also invest.
-- pirate merchants too. they will have pirate port that has no tax, cheaper products etc". Answers, same day: a player MAY join the pirates ("yes they can"); a pirate player attacking other players' merchants:
-- "not for now" (the no-PvP law stands). 2026-11-06 (row 306): "use your recommended defaults for the rest". The design is docs/WORLD_POWERS.md Part 5 (section 7, build step W16 `the_brethren`; needs W15 = 0330,
-- LIVE); the base is docs/PIRATES_AND_HAVENS.md. THIS FILE IS W16 AND NOTHING ELSE: no pirate ship (W17), no pirate merchant and no investing (W18), no navy hunting (W19), no `pirates_bite`, no change to a raid.
--
-- WHAT LANDS
--   * the nation PIR "The Brethren" (flag: the skull), the 24th nation and the 11th great power. `public.great_powers.pirate` (new column, at most one row true: a unique index) says which great power has NO CROWN.
--     `public.pirate_power(nation)` is the one reader.
--   * its FOUR HOMES, authored in data/home-ports.json (the world guard holds the database equal to it): Port Royal (POR, the capital and the hoard: 993 M d. of its own money), and three NEW harbours, Lingga (LGA, the
--     Strait of Malacca), Goto (GOT, off Kyushu) and Djerba (DJE, the Barbary coast). They are claimed as homes by the file's own statements, with the home trigger disabled BY NAME inside the one atomic block and enabled again.
--   * WAR with all ten (data/relations.json, ten rows, each with a line of history): `public.power_stance` and every reader after it (the tariff factor, the dues line, the regard base) read war for a company at a pirate port.
--   * THE FREE PORT: `public.port_is_free(port)` is true for a pirate HOME and nothing else (and only while the knob `pirate_ports_free` is true). `world.tax_rate` answers 0 through it (ports.tax_rate itself is left as it is, so
--     the lever below restores the tax), `cmd.set_tax` refuses there (E_FREE_PORT), `public.port_fee` (the dock fee) answers 0 through it, `public.port_dues` serves factor 0 there, `public.depth_day` leaves a free port's depth
--     alone, and port_treasury.depth_mult is fixed at 0.5 on the four (the market there holds half as deep). A contested city the pirates win later keeps its own rate: only the homes are free (decided by default).
--   * THE LEVER `pirate_ports_free` (world_config, TRUE as shipped): the free ports change play at four ports the day this lands, so they have a one-write rollback. Set to false, port_is_free is false everywhere: the four ports
--     tax and charge as any city at war with a company does, and depth_day walks their depth back to the formula. Owner only (a knob write); it needs no migration either way.
--   * THE JOINING KNOB `pirates_joinable` (world_config, false): `public.nation_joinable(nation)` is THE one reader of "may a company sail for this country" (a great power; the pirates only when the knob is true).
--     cmd.found_house, cmd.change_country and the country picker (world.snapshot's new field `joinable`) read it and nothing else. The owner said a player MAY join; he has not said when. Shipped false, so he allows it in its
--     own window with no new migration. NOTHING ELSE changes when it is flipped: a company that founds under the pirates starts at Port Royal, paid its starting money by Port Royal (moved, from the hoard).
--   * NO CROWN: the pirates have no cargo ships, no navy and no aid from a capital: their purse is their cities' own (plunder funds it, W17). public.city_capital answers null for a pirate city (so no aid, no crown
--     tax share, no fine is paid at their capital), and the four loops over public.great_powers that make a crown's things skip the pirates: convoy_ships_wanted, tick_cargo_ships, navy_read, navy_plan_step.
--     world.levels leaves them out of the regard list. world.nation_standings keeps them (the Countries board shows The Brethren: 4 held, 4 home).
--
-- THE CHANGE FROM THE DESIGN, AND WHY (said plainly). The design names Sale (SAL) the HQ and says it has no holder. It has one: SPAIN won it at the 00:47 UTC count of 2026-11-06 (prod, read-only, 2026-11-07: ESP holds it,
-- 640 k influence points of NPC merchants of ESP / NLD / FRA, an NPC mayor of ESP, the city's 99 M d.). Taking it would hand a won city to the pirates, which docs/INFLUENCE.md D1 forbids in so many words (a home is topped
-- up from FREE cities "so nobody loses a city"). So Sale is NOT taken: the pirates' homes are Port Royal (free: no holder, 0 influence rows, no mayor, on prod 2026-11-07) and three NEW harbours, the capital
-- is Port Royal, and this file REFUSES (loudly, nothing applied) if Port Royal is held when it runs. Sale can become a home later, in a slice of its own, if the owner wants Spain to lose it. Decided by default.
--
-- DECIDED BY DEFAULT (the owner may reverse any; docs/dev-log/2026-11-07-the-brethren.md lists all)
--   * pirates_joinable false (above). * Port Royal's 993 M d. purse makes the pirates richer than four realms the day this lands (PIR is 5th of 11 by purse). It is a city's own money; no gold is made.
--     `pirate_spend_day_pct` 0.5 % a day (W17/W18) is what will cap what the power may spend. Removing the pirates later is a ONE-WAY DOOR (a flag is a city's fact). * Only the four homes are free ports.
--   * The flag clock does not move: the four homes' `since` is held at the newest flag change that existed before this file (public.tick_cargo_ships and public.navy_plan_step rebuild every realm's circuit and stations when
--     max(port_allegiance.since) moves; no realm's cities changed, so nothing is rebuilt for nothing). * The regard list leaves the pirates out; the dues line says factor 0 at a free port.
--
-- THE THREE HARBOURS are a DATA slice as 0217 was: Lingga, Goto and Djerba, small (tier 3, four existing goods each), purse 0, NO seed and NO gold made, a roadstead and sailed distances to and from every place (the
-- existing ones untouched), three merchant courses each way, a market row for every good, leg asks, hauls, buildings, tongue, works, population and a flag row with NO holder (this file claims them). Part (harbours) below.
--
-- THE CONSUMERS OF A NATION LIST, and what each does with an 11th power (the audit is in the dev-log; the server half in one line each)
--   great_powers loops: convoy_ships_wanted, tick_cargo_ships, navy_read, navy_plan_step SKIP the pirates (re-cut below); world.levels' regard list skips them (re-cut); world.nation_standings KEEPS them;
--   realm_capital / realm_purse / cargo_* / navy_* are reached only through those loops (the pirates are never in them). city_capital null for a pirate city (re-cut) stops crown_aid's roster, the tax share of
--   city_day, the donors of crown_donors and the fines of fine_for / regard_line at a pirate capital. power_stance / country_factor / regard_of / world.tax_rate read the ten war rows. tick_influence skips homes;
--   population_signals' WAR share reads foreign influence at a pirate home as war (intended). world.snapshot serves `great` (11) and `joinable` (10). port_countries / port_ruler: a pirate city has no ruler, its
--   people are PIR; no pirate home has a yard or an academy (tier 3), so yard_wrong_country and skill_taught_at never ask. Everything per-row (the cards, the stats, the inn) joins nations by code and shows The Brethren.
--
-- THE RE-CUTS (hunks sliced from the LIVE bodies, read on prod at head 0337; each hunk occurs exactly once in the live body and reverses to its pre-image; ACL, volatility, definer, config, parallel safety, owner and
-- language unmoved; this file supersedes those lines of): public.city_capital (0172), public.port_fee (0237), public.port_dues (0237, 0319), cmd.set_tax (0147), public.depth_day (0252),
-- public.convoy_ships_wanted (0326, 0331), public.tick_cargo_ships (0309, 0324, 0326), public.navy_read (0331), public.navy_plan_step (0331), world.levels (0325), world.snapshot (0028, 0187, 0332), world.tax_rate (0122, 0147, 0196, 0237, 0319),
-- cmd.found_house (0143, 0187), cmd.change_country (0143, 0187). One new function per concept: pirate_power, port_is_free, nation_joinable. NOT touched: any other function, table, switch or job.
--
-- ALL OR NOTHING. Prod's runner sends a file statement by statement (docs/OPS_HEALTH.md section 4), so the WHOLE file is ONE `do` block: a failure anywhere (a premise, a hunk, an assert) rolls back every row, column,
-- index, function and the trigger toggle with it. statement_timeout 90 s and lock_timeout 5 s are its first act; the file's budget is 45 s on prod (the clock stands still while it runs).
--
-- SELF-ASSERT (this block): catalog and cheap pure reads only, never a game step and never a digest of live rows. Every hunk once and reversing; no other function moved (md5 over every one); only the one knob added;
-- the homes, the tax, the depth, the wars, the unique pirate, the trigger enabled AND biting; the nation_joinable truth table (10 of 11 great powers, the knob flipped inside a rolled-back probe); port_is_free exactly
-- the four, and none with the lever off (a rolled-back probe); city_capital null at the four and unchanged elsewhere; THE MONEY PROOF BY CONSTRUCTION: this transaction wrote no row to players, treasury_flows, treasury_daybook, ledger, port_influence or events, and
-- the only purses it wrote are the three new ones, at 0 (pg_stat_xact_user_tables, with a positive control). THE LIVE PATHS (a lit cargo job and navy that never touch the pirates, a company at a free port, the tax
-- refusal, the doors with the knob false and true, the picker's ten, W unchanged across the claim, the influence book equal) ARE PROVED IN CI: scripts/db/proofs/45_the_brethren.sql and the local harness
-- scripts/ops/harness/the-brethren/proof-0338.mjs; the file says so in a printed notice in every environment.
--
-- ROLLBACK: the free ports at once, by the lever (pirate_ports_free false, one knob write, owner only). The rest, forward, a NEW migration, owner only: hunks are reversible (each OLD text is in this file); the knobs and the wars are data. The nation,
-- its four homes and the three harbours are a ONE-WAY DOOR once a city has been won, a company founded or a trade made there: do not remove them casually.
-- VERSION: 0338 = prod head 0337 + 1 (read 2026-11-07 09:09 UTC, no other migration PR open).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_homes constant text[] := array['POR', 'LGA', 'GOT', 'DJE'];
  v_t0         timestamptz := clock_timestamp();
  v_ms         jsonb := '{}'::jsonb;
  v_pir        uuid;
  v_since      timestamptz;
  v_n          int;
  v_x          int;
  v_def        text;
  v_rev        text;
  v_fn_before  text;
  v_cfg_before text;
  v_rel_before text;
  v_nations    int;
  v_entry      int;
  r_d          record;   -- named so that no SQL alias of an embedded part (the harbours block uses d, x, g, l) can be mistaken for them
  r_hk         record;
  r_x          record;
begin
  perform set_config('statement_timeout', '90s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD: nothing of this file exists, and the premises it was cut against hold (else NOTHING is applied) ──
  if to_regprocedure('public.pirate_power(uuid)') is not null or to_regprocedure('public.port_is_free(uuid)') is not null
     or to_regprocedure('public.nation_joinable(uuid)') is not null
     or exists (select 1 from public.nations where code = 'PIR')
     or exists (select 1 from public.world_config where key in ('pirates_joinable', 'pirate_ports_free'))
     or exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'great_powers' and column_name = 'pirate') then
    raise exception '0338 refuses: the Brethren are already in this world';
  end if;
  if exists (select 1 from public.ports where code in ('LGA', 'GOT', 'DJE')) then
    raise exception '0338 refuses: a harbour of Lingga, Goto or Djerba is already in this world';
  end if;
  select a.nation_id, a.home into r_x
    from public.ports p join public.port_allegiance a on a.port_id = p.id
   where p.code = 'POR' and p.kind = 'HARBOUR';
  if not found then
    raise exception '0338 refuses: Port Royal is not a harbour with a flag row in this world';
  end if;
  if r_x.nation_id is not null or r_x.home then
    raise exception '0338 refuses: Port Royal is held (by %); a pirate home is a FREE city, nobody loses a city (docs/INFLUENCE.md D1) - nothing is applied',
      (select n.code from public.nations n where n.id = r_x.nation_id);
  end if;
  if (select count(*) from public.great_powers g join public.nations n on n.id = g.nation_id
       where n.code in ('ENG', 'ESP', 'FRA', 'JOS', 'JPN', 'MNG', 'MUG', 'NLD', 'OTT', 'PRT')) <> 10 then
    raise exception '0338 refuses: the ten great powers are not all in this world';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  v_since := (select max(a.since) from public.port_allegiance a);   -- the newest flag change before this file (the four homes' flag clock is held here)
  v_nations := (select count(*) from public.nations);
  v_entry := (select count(*) from public.client_rpc_entry_points());   -- no new door: three readers, all server-only

  create temp table defs_0338 on commit drop as
  select f.fn, f.ord, p.oid,
         replace(pg_get_functiondef(p.oid), E'\r', '') as def,
         coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef,
         coalesce(p.proconfig::text, '') as cfg, p.proparallel as par, p.proowner as owner, l.lanname as lang
    from (values
      ('public.city_capital(uuid)', 1),
      ('public.port_fee(uuid, uuid, numeric)', 2),
      ('public.port_dues(uuid, uuid, numeric)', 3),
      ('cmd.set_tax(uuid, numeric)', 4),
      ('public.depth_day(integer)', 5),
      ('public.convoy_ships_wanted()', 6),
      ('public.tick_cargo_ships(timestamp with time zone, uuid)', 7),
      ('public.navy_read(timestamp with time zone)', 8),
      ('public.navy_plan_step(timestamp with time zone, uuid)', 9),
      ('world.levels()', 10),
      ('world.snapshot()', 11),
      ('cmd.found_house(text, text)', 12),
      ('cmd.change_country(text)', 13),
      ('world.tax_rate(uuid, uuid)', 14)) f(fn, ord)
    join pg_proc p on p.oid = to_regprocedure(f.fn)
    join pg_language l on l.oid = p.prolang;
  if (select count(*) from defs_0338) <> 14 then
    raise exception '0338 self-assert FAIL: % of the 14 bodies this file re-cuts are in this world', (select count(*) from defs_0338);
  end if;

  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> all (select t.oid from defs_0338 t);
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before
    from public.world_config c;
  select md5(coalesce(string_agg(r.a::text || r.b::text || r.stance || r.why, ',' order by r.a, r.b), '')) into v_rel_before from public.power_relations r;
  create temp table xact0_0338 on commit drop as
  select s.relname::text as relname, s.n_tup_ins, s.n_tup_upd, s.n_tup_del from pg_stat_xact_user_tables s;
  v_ms := v_ms || jsonb_build_object('pre', round(extract(epoch from clock_timestamp() - v_t0) * 1000));

  -- ── 2. THE THREE HARBOURS (part: harbours) ──
  -- ┌── THE HARBOURS BLOCK BEGINS (a nested plpgsql block; its own header says what it adds) ──
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0338 (harbours) — THREE NEW HARBOURS, AS A DATA SLICE: Lingga (LGA), Goto (GOT), Djerba (DJE)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- THE TEXT OF ONE PLPGSQL BLOCK (declare ... begin ... end;), to be embedded as a nested block in the one atomic do-block of
-- supabase/migrations/20260818000338_the_brethren.sql, FIRST, before anything of the pirate power exists. Pure plpgsql: static statements,
-- temp tables on commit drop (suffix _h), variables suffixed _h; no begin/commit, no set role, no statement_timeout, no dollar tag.
-- GENERATED 2026-11-07, not typed. The columns, offers, tongues and populations come from data/*.json through scripts/lib/world-derive.mjs; the
-- sea numbers (roadstead, sailed distances, courses) from a scratch copy of scripts/build-sea-migration.mjs with its ADDS_PLACES_ONLY rule (same
-- roadstead rule, same pathfinder, same refusals; it floods only the pairs that touch a new place, and a pair is measured by the flood from the
-- lower code, both ways), run against the head world restored from the prefix cache because the committed generator replays the chain from zero.
-- Neither scratch generator is committed; re-run them from the data, never hand-edit a literal.
--
-- WHAT IT ADDS (a DATA slice exactly as 0217 added eight harbours: small ones, tier 3, size 2, four existing goods each, NO new good)
--   LGA Lingga (Lingga island, Daik; Indonesia; South China Sea; Southeast Asia)  songket, star-anise, tamarind, zedoary
--   GOT Goto   (the Goto islands, Fukue; Japan; Korea Strait; Japan)              sea-cucumber, abalone, shark, squid
--   DJE Djerba (Houmt Souk; Tunisia; Mediterranean; Maghreb)                       sumac, maghreb-brass, saffian-leather, morocco-leather
--   * 12 offers; 5 city_production outputs (0280's rule: 1-2 a harbour, native, within the size ceiling, highest tier first; no function writes that table);
--   * a market row for EVERY good at each harbour (3 x the catalogue), priced with the head's own arithmetic: world.affinity_at over the nearest maker,
--     world.market_depth_at, 0303's public.good_stock_scale cut, world.demand_for (0185) and the sailed haul (0173: world.haul_at over public.sea_reaches);
--   * the roadstead of each (its own quay: all three stand on sailable water, snap 0) and its sailed distance to and from EVERY other place, in public.sea_reaches
--     (3 new rows of 262 keys; every existing row gains 3 keys and keeps every key it had); 18 merchant courses in public.npc_courses (each harbour to
--     and from its 3 nearest existing harbours BY SEA, the pathfinder's own course, so public.npc_known_legs offers them);
--   * 0089's buildings (public.furnish_harbours), 0122 the purse row at 0 ducats and its reserve (public.treasury_reserve), 0123 the four works at level 0,
--     0143 the flag row (NO holder, not home), 0156 the tongue, 0215/0222 the sea-condition leg asks, 0304 the population.
-- NO GOLD IS MADE. The three purses are 0. No seed is posted (public.city_seed_amount is not called; the switch is not touched), no treasury_flows /
-- treasury_daybook / ledger / players row is written (asserted below from pg_stat_xact_user_tables, with a positive control). seeded_at: section 7.
--
-- WHY THESE GOODS (said plainly). Every region's native goods already sit in three cities (the owner's 0065 law, checked by scripts/check-ports.mjs), so a
-- fourth offer of one is not allowed. Southeast Asia has exactly four goods with a free place (songket, star-anise, tamarind, zedoary): they are Lingga's.
-- Japan has none: its 45 rostered goods are all in three cities and its other 41 native goods are the raw and crafted goods of 0280 that NO roster holds
-- (they are made, not sold). Goto's four are the sea products among those: sea-cucumber, abalone, shark, squid. Each gains its FIRST roster maker, so the haul
-- of every other harbour's row of that good moves (1.0 to the sailed distance from Goto, 0173): 4 x 245 rows. Their existing affinities are left as 0280 seeded
-- them (from city_production, at depth 1); only a row of a good a roster holds follows world.affinity_for.
-- Goto's own rows of the four stand at the roster depth (market_depth), the other harbours' rows of them at 0280's depth 1. Djerba has seven free places
-- (the Maghreb); it takes sumac, maghreb-brass, saffian-leather and morocco-leather: the Barbary tanneries and brass.
--
-- WHAT IT CHANGES IN LIVE PLAY (the counts are the head world's, printed again in the receipt)
--   * 572 existing market rows of the eight rostered goods of Lingga and Djerba change affinity because a new maker is nearer: affinity, max stock and
--     production re-derived, the stock reset to the new max (what every growth since 0041 does), 0303's cut kept, 0252's base_target kept in step where set;
--   * 1,500 existing market rows change haul (any of the twelve goods): haul_nm / haul re-derived (0173) from the nearest maker's sailed distance.
--   Nothing else: no player row, no existing roadstead or distance, no sea zone, no switch, no knob, no function body.
-- ROLLBACK (forward, a NEW migration, owner only): delete the three harbours' rows from sea_leg_asks, npc_courses, port_population, port_language,
-- port_allegiance, city_works, port_treasury, port_buildings, port_goods, city_production, port_specialties and sea_reaches, remove the 3 new keys from every
-- sea_reaches.reaches, delete the three ports; re-derive the moved rows (world.affinity_at over the makers without the three; world.haul_rows()).
-- No fleet can be docked at a new harbour before players sail there.
-- TIME: the local PGlite world runs this block in about 9 s, 6 of them the assert (world.haul_rows() alone is 4 s); the receipt prints the ms of every group.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
declare
  v_t0_h        timestamptz := clock_timestamp();
  v_t_h         timestamptz := clock_timestamp();
  v_ms_h        jsonb := '{}'::jsonb;
  v_n_h         int;
  v_m_h         int;
  v_bad_h       int;
  v_seeded_h    boolean;
  v_since_h     timestamptz;
  v_xact0_h     bigint;
  v_xact1_h     bigint;
  v_ins_ports_h bigint;
  v_places_h    int;
  v_moved_h     int;
  v_hauled_h    int;
  v_newrows_h   int;
  v_asks_h      int;
begin
  -- ── 0. THE PREMISES: what this part reads must be in the world, and none of the three may be (a second apply refuses) ──
  if to_regprocedure('world.affinity_at(boolean,double precision,numeric,numeric,numeric,numeric,numeric)') is null
     or to_regprocedure('world.market_depth_at(integer,numeric,numeric)') is null
     or to_regprocedure('world.demand_for(uuid,uuid)') is null
     or to_regprocedure('world.haul_rows()') is null
     or to_regprocedure('world.haul_at(numeric,numeric,numeric,numeric,numeric)') is null
     or to_regprocedure('public.good_stock_scale(uuid)') is null
     or to_regprocedure('public.furnish_harbours()') is null
     or to_regprocedure('public.treasury_reserve(uuid)') is null
     or to_regprocedure('public.sea_leg_asks_derive(uuid)') is null
     or to_regprocedure('voyage.water_roadstead(numeric,numeric)') is null
     or to_regprocedure('voyage.segments_from_course(jsonb)') is null
     or to_regprocedure('voyage.path_refusal(jsonb,numeric,numeric,numeric,numeric,numeric,numeric,numeric)') is null
     or to_regclass('public.city_production') is null or to_regclass('public.port_population') is null
     or to_regclass('public.sea_leg_asks') is null or to_regclass('public.port_allegiance') is null then
    raise exception '0338 (harbours) refuses: a function or table this part reads is not in this world (0122, 0143, 0156, 0173, 0215, 0222, 0280, 0303 or 0304)';
  end if;
  if exists (select 1 from public.ports where code in ('LGA', 'GOT', 'DJE')) then
    raise exception '0338 (harbours) refuses: one of LGA GOT DJE already exists - this has been applied once';
  end if;
  -- the flag clock: public.tick_cargo_ships and public.navy_plan_step rebuild every realm's circuit and stations when max(port_allegiance.since) moves,
  -- so the three new flag rows carry the newest flag change that existed BEFORE this part (no realm's cities changed)
  select max(a.since) into v_since_h from public.port_allegiance a;
  -- the world's own record of whether its cities were ever seeded (0122; 0217 read it the same way): prod yes, a fresh chain no
  select exists (select 1 from public.port_treasury t where t.seeded_at is not null) into v_seeded_h;
  -- the money proof, by construction: this transaction's writes to the four money tables, before and after (pg_stat_xact_user_tables)
  select coalesce(sum(s.n_tup_ins + s.n_tup_upd + s.n_tup_del), 0) into v_xact0_h
    from pg_stat_xact_user_tables s where s.schemaname = 'public' and s.relname in ('players', 'treasury_flows', 'treasury_daybook', 'ledger');
  select coalesce(sum(s.n_tup_ins), 0) into v_ins_ports_h from pg_stat_xact_user_tables s where s.schemaname = 'public' and s.relname = 'ports';

  -- ── 1. THE HARBOURS (columns derived by scripts/lib/world-derive.mjs from data/ports.json; crew_pool seeded once, then the game's) ──
  insert into public.ports (code, name, country, nation_id, lat, lon, sea_id, region_id, culture,
                            size_tier, max_draft, has_yard, yard_tier, has_academy,
                            dev_industry, dev_commerce, dev_military, tax_rate, crew_pool)
  select v.code, v.name, v.country, n.id, v.lat, v.lon, s.id, r.id, v.culture,
         v.size_tier, v.max_draft, v.yard_tier > 0, v.yard_tier, v.academy,
         v.dev_i, v.dev_c, v.dev_m, 0.03, v.crew_pool
    from (values
      ('LGA', 'Lingga', 'Indonesia', null, -0.2, 104.62, 'SOA', 'SOU', 'malay', 2, 3, 0, false, 4, 9, 4, 160),
      ('GOT', 'Goto', 'Japan', 'JPN', 32.7, 128.84, 'KOR', 'JAP', 'japanese', 2, 3, 0, false, 4, 9, 4, 160),
      ('DJE', 'Djerba', 'Tunisia', 'OTT', 33.88, 10.86, 'MED', 'MAG', 'islamic', 2, 3, 0, false, 4, 9, 4, 160)
    ) as v(code, name, country, nation_code, lat, lon, sea_code, region_code, culture, size_tier, max_draft, yard_tier, academy, dev_i, dev_c, dev_m, crew_pool)
    join public.seas s on s.code = v.sea_code
    join public.regions r on r.code = v.region_code
    left join public.nations n on n.code = v.nation_code;
  get diagnostics v_n_h = row_count;
  if v_n_h <> 3 then
    raise exception '0338 (harbours) FAIL: % harbour(s) inserted, 3 expected (a sea, region or nation code is missing)', v_n_h;
  end if;
  create temp table new_h on commit drop as
    select p.id, p.code, p.lat, p.lon, p.size_tier from public.ports p where p.code in ('LGA', 'GOT', 'DJE');

  -- ── 2. THE OFFERS (the rosters of data/ports.json: four goods each, all existing, native, none in a fourth city) ──
  insert into public.port_specialties (port_id, good_id)
  select p.id, g.id
    from (values
      ('LGA', 'songket'),
      ('LGA', 'star-anise'),
      ('LGA', 'tamarind'),
      ('LGA', 'zedoary'),
      ('GOT', 'sea-cucumber'),
      ('GOT', 'abalone'),
      ('GOT', 'shark'),
      ('GOT', 'squid'),
      ('DJE', 'sumac'),
      ('DJE', 'maghreb-brass'),
      ('DJE', 'saffian-leather'),
      ('DJE', 'morocco-leather')
    ) as v(port_code, good_code)
    join public.ports p on p.code = v.port_code
    join public.goods g on g.code = v.good_code;
  get diagnostics v_n_h = row_count;
  if v_n_h <> 12 then
    raise exception '0338 (harbours) FAIL: % offer(s) inserted, 12 expected (a good code is missing)', v_n_h;
  end if;

  -- ── 3. WHAT EACH HARBOUR MAKES (0280's rule for a harbour founded after it; no function writes city_production, so this is the only writer) ──
  insert into public.city_production (port_id, good_id, rank)
  select p.id, g.id, v.rank
    from (values
      ('LGA', 'songket', 1),
      ('LGA', 'star-anise', 2),
      ('GOT', 'sea-cucumber', 1),
      ('GOT', 'abalone', 2),
      ('DJE', 'sumac', 1)
    ) as v(port_code, good_code, rank)
    join public.ports p on p.code = v.port_code
    join public.goods g on g.code = v.good_code;
  get diagnostics v_n_h = row_count;
  if v_n_h <> 5 then
    raise exception '0338 (harbours) FAIL: % production row(s) inserted, 5 expected', v_n_h;
  end if;
  v_ms_h := v_ms_h || jsonb_build_object('rows', round(extract(epoch from clock_timestamp() - v_t_h) * 1000));
  v_t_h := clock_timestamp();

  -- ── 4. THE WATER: each roadstead, its sailed distance to and from every place, and its merchant courses ──
  -- The numbers are scripts/build-sea-migration.mjs's own (ADDS_PLACES_ONLY): the roadstead rule and the one pathfinder, a pair measured by the flood
  -- from the lower code, both ways. The three new rows hold all 262 keys; the existing rows get the 3 new keys from them (symmetric by construction).
  create temp table reaches_before_h on commit drop as
    select sr.code, sr.snap_nm, sr.roadstead_lat, sr.roadstead_lon, sr.reaches from public.sea_reaches sr;
  insert into public.sea_reaches (port_id, code, snap_nm, roadstead_lat, roadstead_lon, reaches)
  select p.id, v.code, v.snap_nm::numeric, v.rlat::numeric, v.rlon::numeric, v.reaches::jsonb
    from (values
      ('LGA', 0.00, -0.200, 104.620, '{"ACA":9115.9,"ACC":8150.9,"ADE":3756.8,"AGA":10232.8,"ALE":12446.8,"ALG":11068.8,"AMB":1562,"AMS":11761.2,"ANC":12262.6,"ANG":10704.3,"ANT":12441.2,"ARI":9972.6,"ARK":13651.9,"ARP":11731.7,"AST":7048.1,"AUK":4757.3,"AYU":915.7,"BAB":3887.4,"BAN":696.1,"BAR":11159,"BAS":3459.7,"BEI":12665.4,"BEL":9832,"BER":12176,"BIL":11264.3,"BIS":11208.1,"BND":1647.1,"BNT":370.6,"BOR":11387.4,"BOS":12273.9,"BRI":10801.6,"BRS":11572.1,"BRU":11675.9,"BSR":3974.2,"BUE":8649.6,"BUS":2586,"BUV":10709.7,"CAD":10613.6,"CAG":11380,"CAL":8031.2,"CAP":8146.4,"CAR":11829.7,"CEB":1383.5,"CEU":10655.5,"CHE":1655.5,"CHI":1567.4,"CHS":12235.5,"CID":9328.1,"CLL":10099.2,"CLS":11622.8,"COL":1664.7,"CON":8889.7,"COP":12279.6,"COQ":9298.7,"COR":11963.8,"CPT":5540,"CRK":11387.7,"CSV":10547.8,"CUM":11008.7,"DAR":1754.8,"DBR":12101.1,"DIL":1360.5,"DIU":2664.9,"DJE":11670.1,"DLD":8784,"DOG":11829.2,"DRK":7562.4,"DUB":11516.9,"ELM":8146.4,"FAM":12619.9,"FEO":12820,"FNC":10199.6,"FRE":2073.7,"FUK":2497.2,"FUZ":1778,"GAL":1598.5,"GBK":11594.7,"GDA":12504.9,"GIB":10651.7,"GOA":11491.8,"GOR":9116.6,"GOT":2408.3,"GUA":1504,"GYE":10570.6,"HAD":3200.2,"HAG":2638.8,"HAM":12004.2,"HAN":1331,"HAV":12338.3,"HER":12152.8,"HIR":2489.4,"HLT":10627,"HNL":5917,"HOB":3905.1,"HOI":1066.1,"HON":1451.2,"HOO":1714.6,"HOR":3459.7,"HRN":11778,"HUA":9331.2,"INC":2583.8,"ISL":4159.8,"IST":12446,"IZM":12240.2,"JAF":1638.1,"JAK":372.6,"JAM":12370.5,"JED":4482.2,"JEJ":2381.5,"KAG":2398.2,"KAL":12547.4,"KAN":2083.3,"KAR":2978.8,"KHA":2682.9,"KIL":4142.5,"KIN":11798.7,"KOC":1952.2,"KOL":1888.7,"KOZ":2030.9,"KUP":1341.8,"LAG":8126.5,"LAR":11336.9,"LEH":11525.1,"LEI":11971.4,"LIS":10772.2,"LIV":11603.3,"LNG":13102.6,"LON":11783.7,"LPA":10048.4,"LUA":7258.1,"LUB":12481.5,"MAC":1442.1,"MAK":954.3,"MAL":204.7,"MAN":3746.4,"MAS":4117.6,"MAT":3156,"MCH":1694.5,"MES":11736.9,"MEZ":13672.6,"MID":11807.7,"MLE":1985.9,"MLG":10812.2,"MLN":4094.5,"MNG":2148.1,"MNL":1292.2,"MOC":3848.6,"MOG":3663.3,"MOK":2427,"MOM":4157.6,"MRS":11425.3,"MTY":7420.9,"MUM":2541.9,"MUS":3224.8,"MYE":909.2,"MZT":8671.6,"NAG":2426.4,"NAH":2072.5,"NAM":2621.1,"NAN":11474.2,"NAP":11702.1,"NAV":8894.2,"NEW":12361.6,"NIN":2107.8,"NUU":12486.4,"OLD":2322.1,"OPO":10920.2,"ORA":10965,"OSA":2693.8,"OUI":8323,"PAI":10504.2,"PAL":11649.9,"PAN":10489.8,"PAR":10546.4,"PAT":12039.9,"PLM":11191.8,"PLO":3474.1,"PLY":11504.5,"PON":10656.3,"POR":12070.9,"PRT":12218.9,"PTH":11615.9,"PTL":12287.2,"PTT":514.6,"PUL":1702.8,"PUS":13722.6,"QUA":1705.5,"QUE":12557.2,"REA":9836.3,"REC":8935.9,"REY":12202.6,"RHO":12373.9,"RIG":12849.7,"RIO":8684.4,"ROT":11829.7,"RRF":5221,"SAF":10437.9,"SAI":9298.2,"SAK":2693.8,"SAL":10594.3,"SAN":11484,"SAO":7877,"SDG":7748.1,"SET":10753.2,"SFR":7372.1,"SGO":11689.5,"SGS":11466.7,"SHI":2530.4,"SKC":6646.1,"SLV":8895.9,"SNL":10737.3,"SNT":11542.2,"SOF":4589,"SOG":10723.2,"SOH":3439,"SOM":309.3,"SOS":8764.4,"SOY":7397.6,"SPL":12253.9,"SRT":2662.8,"STA":12556.8,"STG":11824.7,"STJ":11807.2,"STO":12752.5,"SUA":4349.2,"SUE":5016,"SUR":646,"SVQ":10777.7,"SYD":4092,"TAI":1647.3,"TAL":12889.3,"TAN":10714,"TEN":10050,"TER":1602,"THA":1181.8,"THE":12392.2,"TID":1608.2,"TOK":2916.2,"TON":2493,"TOR":12122,"TOU":11441.7,"TRA":13078.7,"TRI":12769.3,"TRO":12558.1,"TRP":11834.8,"TSU":2489.5,"TUN":11518.3,"TUR":12860.8,"ULS":2569.4,"VAL":11118.5,"VAR":13253.6,"VEN":12439.5,"VER":13239.7,"VIS":12658.4,"VLL":11735.7,"VLP":9035.7,"WIL":11501,"WLG":4955.4,"XIA":1665.7,"YEO":2465.6,"ZAK":12025.2,"ZAN":4115.6}'),
      ('GOT', 0.00, 32.700, 128.840, '{"ACA":6778.6,"ACC":10462.4,"ADE":6044.4,"AGA":12544.3,"ALE":14758.3,"ALG":13380.3,"AMB":2218.2,"AMS":14072.7,"ANC":14574.1,"ANG":13015.8,"ANT":14752.7,"ARI":9505.1,"ARK":15963.4,"ARP":14043.2,"AST":4660.3,"AUK":4938.8,"AYU":2445.6,"BAB":6175,"BAN":2983.7,"BAR":13470.5,"BAS":5747.4,"BEI":14976.9,"BEL":12143.5,"BER":14487.5,"BIL":13575.8,"BIS":13519.6,"BND":2264.3,"BNT":2685.3,"BOR":13698.9,"BOS":14585.4,"BRI":13113.2,"BRS":13883.6,"BRU":13987.4,"BSR":6261.8,"BUE":10801.1,"BUS":148,"BUV":8157.4,"CAD":12925.1,"CAG":13691.5,"CAL":10342.7,"CAP":10457.9,"CAR":14141.2,"CEB":1454,"CEU":12967,"CHE":3943.1,"CHI":3855,"CHS":14547,"CID":11639.6,"CLL":8982.9,"CLS":13934.3,"COL":3952.3,"CON":9718.6,"COP":14591.1,"COQ":9896.2,"COR":14275.3,"CPT":7851.6,"CRK":13699.2,"CSV":12859.3,"CUM":13320.2,"DAR":2711.1,"DBR":14412.6,"DIL":2473,"DIU":4952.6,"DJE":13981.6,"DLD":11095.5,"DOG":14140.7,"DRK":9516.9,"DUB":13828.4,"ELM":10457.9,"FAM":14931.4,"FEO":15131.6,"FNC":12511.1,"FRE":4094,"FUK":93.1,"FUZ":642.8,"GAL":3886.2,"GBK":13906.2,"GDA":14816.4,"GIB":12963.2,"GOA":13803.3,"GOR":11428.2,"GUA":1097.8,"GYE":8456.5,"HAD":5471,"HAG":1446.3,"HAM":14405.5,"HAN":1474.7,"HAV":14795.1,"HER":14534.8,"HIR":48.7,"HLT":12980,"HNL":3982.7,"HOB":4961.3,"HOI":1494.8,"HON":1023.2,"HOO":4002.7,"HOR":5729.5,"HRN":14189.5,"HUA":6973.6,"INC":337.4,"ISL":6432.6,"IST":14823.9,"IZM":14618.8,"JAF":3960.9,"JAK":2661.6,"JAM":14663.1,"JED":6689.8,"JEJ":126.4,"KAG":91.8,"KAL":14973.2,"KAN":4353.2,"KAR":5249.4,"KHA":4952.8,"KIL":6415.8,"KIN":14210.7,"KOC":4220.9,"KOL":4158.5,"KOZ":4300.7,"KUP":2650.5,"LAG":10595.6,"LAR":13754.1,"LEH":13933.3,"LEI":14381.9,"LGA":2408.3,"LIS":13072.7,"LIV":13903.7,"LNG":15403,"LON":14084.1,"LPA":12348.8,"LUA":9558.5,"LUB":14781.9,"MAC":1055.7,"MAK":2399.3,"MAL":2492.9,"MAN":6019.5,"MAS":6390.7,"MAT":751.9,"MCH":3979.3,"MES":14037.3,"MEZ":15973,"MID":14108.1,"MLE":4270.7,"MLG":13112.6,"MLN":6379.3,"MNG":4421.2,"MNL":1254.7,"MOC":6121.8,"MOG":5948.1,"MOK":193.2,"MOM":6442.4,"MRS":13725.7,"MTY":5093.6,"MUM":4815,"MUS":5497.9,"MYE":3193.7,"MZT":6321.3,"NAG":39.9,"NAH":394.3,"NAM":442.9,"NAN":13774.6,"NAP":14002.6,"NAV":6481,"NEW":14662,"NIN":388.8,"NUU":14786.8,"OLD":4595.2,"OPO":13220.6,"ORA":13265.4,"OSA":456,"OUI":10623.5,"PAI":8479.7,"PAL":13950.3,"PAN":8028.2,"PAR":12846.8,"PAT":14340.3,"PLM":13492.2,"PLO":5774.5,"PLY":13804.9,"PON":12956.7,"POR":14371.3,"PRT":14519.3,"PTH":13916.4,"PTL":14587.6,"PTT":2225.4,"PUL":3987.6,"PUS":16023,"QUA":713.9,"QUE":14857.6,"REA":7409.1,"REC":11236.3,"REY":14503,"RHO":14674.3,"RIG":15150.1,"RIO":10984.8,"ROT":14130.1,"RRF":7521.4,"SAF":12738.3,"SAI":11598.7,"SAK":456,"SAL":12894.7,"SAN":13784.5,"SAO":10177.4,"SDG":5429,"SET":13053.6,"SFR":5036.2,"SGO":13989.9,"SGS":13767.1,"SHI":126.3,"SKC":8946.5,"SLV":11196.3,"SNL":13037.7,"SNT":13842.6,"SOF":6873.8,"SOG":13023.6,"SOH":5712.2,"SOM":2594,"SOS":11064.8,"SOY":9698.1,"SPL":14554.3,"SRT":4935.9,"STA":14857.2,"STG":14125.1,"STJ":14107.6,"STO":15052.9,"SUA":6622.3,"SUE":7289.1,"SUR":2670.9,"SVQ":13078.1,"SYD":4361.1,"TAI":767.1,"TAL":15189.7,"TAN":13014.4,"TEN":12350.4,"TER":1913.2,"THA":3466.3,"THE":14692.7,"TID":1928.2,"TOK":697.4,"TON":130.8,"TOR":14422.4,"TOU":13742.1,"TRA":15379.1,"TRI":15069.7,"TRO":14858.5,"TRP":14135.2,"TSU":92.8,"TUN":13818.7,"TUR":15161.2,"ULS":179.9,"VAL":13418.9,"VAR":15554,"VEN":14739.9,"VER":15540.1,"VIS":14958.8,"VLL":14036.1,"VLP":9938.6,"WIL":13801.5,"WLG":5125.9,"XIA":754.5,"YEO":125.2,"ZAK":14325.6,"ZAN":6400.3}'),
      ('DJE', 0.00, 33.880, 10.860, '{"ACA":12174.1,"ACC":3901.8,"ADE":10244.5,"AGA":1444,"ALE":961.8,"ALG":590.5,"AMB":12430.6,"AMS":2410.4,"ANC":855.2,"ANG":2061.9,"ANT":1027.4,"ARI":9905.1,"ARK":4343.9,"ARP":2381,"AST":14313.5,"AUK":11890.1,"AYU":12646.9,"BAB":10352.1,"BAN":11167.1,"BAR":683.5,"BAS":10868.8,"BEI":1217.4,"BEL":4301.4,"BER":2825.3,"BIL":1895.2,"BIS":1840.7,"BND":12482,"BNT":11274.8,"BOR":2023.4,"BOS":3995.9,"BRI":4223.3,"BRS":2216,"BRU":2325.1,"BSR":11378.5,"BUE":6312.8,"BUS":14176.8,"BUV":11321.2,"CAD":1069.8,"CAG":346.5,"CAL":4398,"CAP":3832,"CAR":5216.9,"CEB":12946,"CEU":1003.8,"CHE":10912,"CHI":11638.8,"CHS":804.1,"CID":2618,"CLL":10262.1,"CLS":2272,"COL":10581.5,"CON":8809.5,"COP":2928.9,"COQ":9215.6,"COR":556.4,"CPT":6114.4,"CRK":2095.7,"CSV":1210.1,"CUM":4516.3,"DAR":12225,"DBR":693.6,"DIL":12141.9,"DIU":10776.2,"DLD":3282.4,"DOG":2511.6,"DRK":7452.1,"DUB":2236,"ELM":3852,"FAM":1171.9,"FEO":1409.1,"FNC":1637.2,"FRE":10817.4,"FUK":14072.9,"FUZ":13355.1,"GAL":10515.8,"GBK":3142,"GDA":3204.2,"GIB":1009.6,"GOA":634.5,"GOR":2553.5,"GOT":13981.6,"GUA":13102.4,"GYE":10977.6,"HAD":9843.7,"HAG":13844.1,"HAM":2676.5,"HAN":12947.4,"HAV":5007.2,"HER":715.3,"HIR":14028.4,"HLT":2773.3,"HNL":13941.2,"HOB":11542.8,"HOI":12662.7,"HON":13044.1,"HOO":11590.6,"HOR":10853.4,"HRN":2460.5,"HUA":12222.3,"INC":14131.4,"ISL":8012.2,"IST":1015.5,"IZM":810.3,"JAF":10651.3,"JAK":11359.6,"JAM":4343.2,"JED":10839.2,"JEJ":13946.8,"KAG":13966.9,"KAL":3244.1,"KAN":10507.8,"KAR":10803.8,"KHA":10839.3,"KIL":8421.2,"KIN":2481.7,"KOC":10475.8,"KOL":10450.8,"KOZ":10500.6,"KUP":11960.9,"LAG":4128.6,"LAR":2009.4,"LEH":2203.9,"LEI":2652.9,"LGA":11670.1,"LIS":1316.6,"LIV":590.9,"LNG":3735.6,"LON":2355.1,"LPA":1727.8,"LUA":4930,"LUB":3052.9,"MAC":13038.9,"MAK":11973.9,"MAL":11708.6,"MAN":11142.1,"MAS":10540.1,"MAT":14760.2,"MCH":11048.5,"MES":413.8,"MEZ":4294.4,"MID":2379.1,"MLE":10168.5,"MLG":936.4,"MLN":8739.6,"MNG":10527,"MNL":12863.4,"MOC":10271.1,"MOG":9100,"MOK":14003.8,"MOM":8682.5,"MRS":656.6,"MTY":13791.5,"MUM":10720.5,"MUS":10616.3,"MYE":11600.5,"MZT":12847.6,"NAG":13996.6,"NAH":13631.8,"NAM":14196.2,"NAN":2026.7,"NAP":439.7,"NAV":12588,"NEW":4171.8,"NIN":13682.9,"NUU":3481.6,"OLD":10602.2,"OPO":1473.4,"ORA":796.8,"OSA":14251.4,"OUI":4058.5,"PAI":10758.9,"PAL":322.2,"PAN":11652.6,"PAR":4345.3,"PAT":548,"PLM":643.7,"PLO":8484.5,"PLY":2074.7,"PON":1993,"POR":4952.4,"PRT":5365.3,"PTH":2187.3,"PTL":3964.3,"PTT":12202.8,"PUL":10899.1,"PUS":4344.6,"QUA":13279.3,"QUE":4027.6,"REA":11890.8,"REC":4301.5,"REY":2935.9,"RHO":864.6,"RIG":3421,"RIO":5327.9,"ROT":2401,"RRF":6634,"SAF":1308.4,"SAI":2465.4,"SAK":14251.4,"SAL":1164.5,"SAN":4404.1,"SAO":4345.1,"SDG":13502.4,"SET":1283.9,"SFR":13868.7,"SGO":4621.5,"SGS":3800.5,"SHI":14111.6,"SKC":5214.1,"SLV":4674.9,"SNL":1110.5,"SNT":2112.9,"SOF":7617.7,"SOG":1024.6,"SOH":10836.1,"SOM":11598.1,"SOS":5532.1,"SOY":4838.5,"SPL":768,"SRT":10824,"STA":4753.1,"STG":3922.4,"STJ":3200,"STO":3323.8,"SUA":10771.7,"SUE":11438.5,"SUR":11733.7,"SVQ":1151,"SYD":12106.7,"TAI":13218.9,"TAL":3460.6,"TAN":1034.5,"TEN":1749.3,"TER":12577,"THA":11691.5,"THE":884.2,"TID":12564.2,"TOK":14493.8,"TON":14069,"TOR":2747.1,"TOU":646.4,"TRA":1570.7,"TRI":1228.1,"TRO":3173.2,"TRP":139.8,"TSU":14063.7,"TUN":239.8,"TUR":3432.1,"ULS":14146.8,"VAL":757,"VAR":3875.3,"VEN":953.6,"VER":5792.6,"VIS":3229.7,"VLL":216.8,"VLP":9039.8,"WIL":4769.6,"WLG":11636.6,"XIA":13238.7,"YEO":14041.2,"ZAK":535.4,"ZAN":8572.3}')
    ) as v(code, snap_nm, rlat, rlon, reaches)
    join public.ports p on p.code = v.code;
  get diagnostics v_n_h = row_count;
  if v_n_h <> 3 then
    raise exception '0338 (harbours) FAIL: % reach row(s) inserted, 3 expected', v_n_h;
  end if;
  update public.sea_reaches sr
     set reaches = sr.reaches || jsonb_build_object(
           'DJE', (select (d.reaches ->> sr.code)::numeric from public.sea_reaches d where d.code = 'DJE'),
           'GOT', (select (g.reaches ->> sr.code)::numeric from public.sea_reaches g where g.code = 'GOT'),
           'LGA', (select (l.reaches ->> sr.code)::numeric from public.sea_reaches l where l.code = 'LGA'))
   where sr.code not in ('LGA', 'GOT', 'DJE');
  get diagnostics v_places_h = row_count;
  -- the measure of a course is the save door's (0203): voyage.segments_from_course over the course itself
  insert into public.npc_courses (from_port, to_port, course, nm)
  select a.id, b.id, v.course::jsonb,
         (select sum((x ->> 'nm')::numeric) from jsonb_array_elements(voyage.segments_from_course(v.course::jsonb)) x)
    from (values
      ('LGA', 'MAL', '[[-0.2,104.62],[2.125,102.125]]'),
      ('MAL', 'LGA', '[[2.125,102.125],[-0.2,104.62]]'),
      ('LGA', 'BNT', '[[-0.2,104.62],[-3.125,106.375],[-5.875,106.125]]'),
      ('BNT', 'LGA', '[[-5.875,106.125],[-3.125,106.375],[-0.2,104.62]]'),
      ('LGA', 'JAK', '[[-0.2,104.62],[-3.125,106.375],[-5.875,106.875]]'),
      ('JAK', 'LGA', '[[-5.875,106.875],[-3.125,106.375],[-0.2,104.62]]'),
      ('GOT', 'NAG', '[[32.7,128.84],[32.625,129.625]]'),
      ('NAG', 'GOT', '[[32.625,129.625],[32.7,128.84]]'),
      ('GOT', 'HIR', '[[32.7,128.84],[33.375,129.375]]'),
      ('HIR', 'GOT', '[[33.375,129.375],[32.7,128.84]]'),
      ('GOT', 'KAG', '[[32.7,128.84],[31.625,130.125]]'),
      ('KAG', 'GOT', '[[31.625,130.125],[32.7,128.84]]'),
      ('DJE', 'TRP', '[[33.88,10.86],[32.875,13.375]]'),
      ('TRP', 'DJE', '[[32.875,13.375],[33.88,10.86]]'),
      ('DJE', 'VLL', '[[33.88,10.86],[35.9,14.51]]'),
      ('VLL', 'DJE', '[[35.9,14.51],[33.88,10.86]]'),
      ('DJE', 'TUN', '[[33.88,10.86],[36.875,11.375],[37.125,11.125],[36.875,10.375]]'),
      ('TUN', 'DJE', '[[36.875,10.375],[37.125,11.125],[36.875,11.375],[33.88,10.86]]')
    ) as v(from_code, to_code, course)
    join public.ports a on a.code = v.from_code
    join public.ports b on b.code = v.to_code;
  get diagnostics v_n_h = row_count;
  if v_n_h <> 18 then
    raise exception '0338 (harbours) FAIL: % merchant course(s) inserted, 18 expected', v_n_h;
  end if;
  v_ms_h := v_ms_h || jsonb_build_object('water', round(extract(epoch from clock_timestamp() - v_t_h) * 1000));
  v_t_h := clock_timestamp();

  -- ── 5. THE MARKET: a row for every good at each harbour, and the rows the three new makers move ──
  -- Affinity and haul of a row depend on the nearest maker of THAT good only, so only the goods the three offer are re-derived (never the whole
  -- market). Two maker tables, as the head has them: a good a ROSTER holds (port_specialties, 0005/0136: world.affinity_for's rule) and a good only
  -- city_production makes (0280 seeded the 64 of them from it, at depth 1). A row follows the table that holds its good AFTER this part.
  create temp table sc_h on commit drop as
    select g.id as good_id, public.good_stock_scale(g.id) as scale from public.goods g;
  create temp table mk_h on commit drop as
    select ps.good_id, p.id as port_id, p.lat, p.lon from public.port_specialties ps join public.ports p on p.id = ps.port_id;
  create temp table rg_h on commit drop as
    select distinct m.good_id from mk_h m;
  create temp table pm_h on commit drop as
    select cp.good_id, p.id as port_id, p.lat, p.lon from public.city_production cp join public.ports p on p.id = cp.port_id;
  create temp table nr_h on commit drop as
    select n.id as port_id, m.good_id, min(voyage.gc_distance_nm(n.lat, n.lon, m.lat, m.lon)) as nm, bool_or(m.port_id = n.id) as offers
      from new_h n join mk_h m on true group by n.id, m.good_id;
  create temp table np_h on commit drop as
    select n.id as port_id, m.good_id, min(voyage.gc_distance_nm(n.lat, n.lon, m.lat, m.lon)) as nm, bool_or(m.port_id = n.id) as makes
      from new_h n join pm_h m on true group by n.id, m.good_id;
  -- 0173: the sailed distance from the nearest roster maker to each new harbour (the maker's own reaches, keyed by the harbour's code)
  create temp table nh_h on commit drop as
    select n.id as port_id, m.good_id, min((sr.reaches ->> n.code)::numeric) as nm
      from new_h n join mk_h m on true join public.sea_reaches sr on sr.port_id = m.port_id group by n.id, m.good_id;
  create temp table nrows_h on commit drop as
  with knob as (
    select public.wc_num('affinity_producer') as producer, public.wc_num('affinity_home') as home, public.wc_num('affinity_span') as span,
           public.wc_num('affinity_reach_nm') as reach_nm, public.wc_num('affinity_curve') as curve, public.wc_num('market_depth') as depth,
           public.wc_num('stock_floor_units') as floor_units, public.wc_num('haul_max') as hmax, public.wc_num('haul_reach_nm') as hreach,
           public.wc_num('haul_curve') as hcurve, public.wc_num('haul_premium_share') as hshare
  ), base as (
    select n.id as port_id, n.size_tier, g.id as good_id, (rg.good_id is not null) as rostered, sc.scale,
           r.offers, r.nm as nm_roster, q.makes, q.nm as nm_prod, h.nm as haul_src
      from new_h n
     cross join public.goods g
      join sc_h sc on sc.good_id = g.id
      left join rg_h rg on rg.good_id = g.id
      left join nr_h r on r.port_id = n.id and r.good_id = g.id
      left join np_h q on q.port_id = n.id and q.good_id = g.id
      left join nh_h h on h.port_id = n.id and h.good_id = g.id
  ), aff as (
    select b.*, k.*,
           world.affinity_at(case when b.rostered then coalesce(b.offers, false) else coalesce(b.makes, false) end,
                             case when b.rostered then b.nm_roster else b.nm_prod end,
                             k.producer, k.home, k.span, k.reach_nm, k.curve) as affinity
      from base b cross join knob k
  ), cut as (
    select a.port_id, a.good_id, a.affinity, a.scale, a.floor_units, a.rostered, a.offers, a.haul_src, a.hmax, a.hreach, a.hcurve, a.hshare,
           md.stock_target as t0, md.production_rate as p0
      from aff a
     cross join lateral world.market_depth_at(a.size_tier, a.affinity, case when a.rostered then a.depth else 1 end) md
  )
  select c.port_id, c.good_id, c.affinity, c.t0, c.p0, c.scale,
         case when c.scale < 1 then least(1, greatest(c.floor_units, round(c.t0 * c.scale, 2)) / c.t0) else 1 end as r,
         case when c.rostered then (case when coalesce(c.offers, false) then 0::numeric else round(c.haul_src, 1) end) else null::numeric end as haul_nm,
         c.hmax, c.hreach, c.hcurve, c.hshare
    from cut c;
  -- 0303's cut on a new row, exactly the re-cut's arithmetic (r = new_base / old_base; stock_target, stock, production_rate x r)
  insert into public.port_goods (port_id, good_id, affinity, stock, stock_target, production_rate, demand, haul_nm, haul)
  select x.port_id, x.good_id, x.affinity,
         case when x.scale < 1 then round(x.t0 * x.r, 2) else x.t0 end,
         case when x.scale < 1 then greatest(0.01, round(x.t0 * x.r, 2)) else x.t0 end,
         case when x.scale < 1 then round(x.p0 * x.r, 2) else x.p0 end,
         world.demand_for(x.port_id, x.good_id),
         x.haul_nm,
         world.haul_at(x.haul_nm, x.hmax, x.hreach, x.hcurve, x.hshare)
    from nrows_h x;
  get diagnostics v_newrows_h = row_count;
  v_ms_h := v_ms_h || jsonb_build_object('new_rows', round(extract(epoch from clock_timestamp() - v_t_h) * 1000));
  v_t_h := clock_timestamp();

  -- the EXISTING rows a new maker moves, goods that had a roster maker before: affinity from the nearest maker with and without the three
  create temp table mv_h on commit drop as
  with gs as (
    select distinct ps.good_id from public.port_specialties ps join new_h n on n.id = ps.port_id
     where exists (select 1 from public.port_specialties o where o.good_id = ps.good_id and o.port_id not in (select id from new_h))
  ), knob as (
    select public.wc_num('affinity_producer') as producer, public.wc_num('affinity_home') as home, public.wc_num('affinity_span') as span,
           public.wc_num('affinity_reach_nm') as reach_nm, public.wc_num('affinity_curve') as curve, public.wc_num('market_depth') as depth,
           public.wc_num('stock_floor_units') as floor_units
  ), mkg as (
    select m.good_id, m.port_id, m.lat, m.lon, (m.port_id in (select id from new_h)) as is_new from mk_h m where m.good_id in (select good_id from gs)
  ), dd as (
    select h.id as port_id, h.size_tier, g.good_id,
           min(voyage.gc_distance_nm(h.lat, h.lon, m.lat, m.lon)) as nm_new,
           min(voyage.gc_distance_nm(h.lat, h.lon, m.lat, m.lon)) filter (where not m.is_new) as nm_old,
           bool_or(m.port_id = h.id) as offers
      from public.ports h cross join gs g join mkg m on m.good_id = g.good_id
     where h.kind = 'HARBOUR' and h.id not in (select id from new_h)
     group by h.id, h.size_tier, g.good_id
  ), d as (
    select dd.*, k.* from dd cross join knob k
  ), a as (
    select d.*, world.affinity_at(d.offers, d.nm_new, d.producer, d.home, d.span, d.reach_nm, d.curve) as aff_new,
                world.affinity_at(d.offers, d.nm_old, d.producer, d.home, d.span, d.reach_nm, d.curve) as aff_old
      from d
  )
  select a.port_id, a.good_id, a.aff_new, a.aff_old, md.stock_target as t0, md.production_rate as p0, sc.scale, a.floor_units
    from a
   cross join lateral world.market_depth_at(a.size_tier, a.aff_new, a.depth) md
    join sc_h sc on sc.good_id = a.good_id
   where a.aff_new is distinct from a.aff_old;
  -- ...re-derived, the stock reset to the new max (0217's rule), the 0303 cut kept, and base_target kept in step where 0252 has set one
  update public.port_goods pg
     set affinity        = x.aff_new,
         stock_target    = case when pg.base_target is null then x.t_new
                                else round(x.t_new * pg.stock_target / nullif(pg.base_target, 0), 2) end,
         base_target     = case when pg.base_target is null then null else x.t_new end,
         production_rate = x.p_new,
         stock           = case when pg.base_target is null then x.t_new
                                else round(x.t_new * pg.stock_target / nullif(pg.base_target, 0), 2) end,
         updated_at      = now()
    from (select m.port_id, m.good_id, m.aff_new,
                 case when m.scale < 1 then greatest(0.01, round(m.t0 * least(1, greatest(m.floor_units, round(m.t0 * m.scale, 2)) / m.t0), 2)) else m.t0 end as t_new,
                 case when m.scale < 1 then round(m.p0 * least(1, greatest(m.floor_units, round(m.t0 * m.scale, 2)) / m.t0), 2) else m.p0 end as p_new
            from mv_h m) x
   where pg.port_id = x.port_id and pg.good_id = x.good_id;
  get diagnostics v_moved_h = row_count;

  -- 0173: the sailed haul of every row of the twelve goods the three offer (the old makers' distances are unchanged; the new makers may be nearer)
  create temp table hl_h on commit drop as
  with gs as (select distinct ps.good_id from public.port_specialties ps join new_h n on n.id = ps.port_id),
  mk as (select m.good_id, m.port_id from mk_h m where m.good_id in (select good_id from gs)),
  tgt as (select p.id as port_id, p.code from public.ports p where p.kind = 'HARBOUR'),
  near as (
    select m.good_id, t.port_id, min((sr.reaches ->> t.code)::numeric) as nm
      from mk m join public.sea_reaches sr on sr.port_id = m.port_id cross join tgt t group by m.good_id, t.port_id
  )
  select t.port_id, g.good_id,
         case when exists (select 1 from mk where mk.good_id = g.good_id and mk.port_id = t.port_id) then 0::numeric else round(n.nm, 1) end as nm
    from tgt t cross join gs g left join near n on n.good_id = g.good_id and n.port_id = t.port_id;
  update public.port_goods pg
     set haul_nm = h.nm,
         haul = world.haul_at(h.nm, public.wc_num('haul_max'), public.wc_num('haul_reach_nm'), public.wc_num('haul_curve'), public.wc_num('haul_premium_share'))
    from hl_h h
   where pg.port_id = h.port_id and pg.good_id = h.good_id
     and (pg.haul_nm, pg.haul) is distinct from
         (h.nm, world.haul_at(h.nm, public.wc_num('haul_max'), public.wc_num('haul_reach_nm'), public.wc_num('haul_curve'), public.wc_num('haul_premium_share')));
  get diagnostics v_hauled_h = row_count;
  v_ms_h := v_ms_h || jsonb_build_object('moved_rows', round(extract(epoch from clock_timestamp() - v_t_h) * 1000));
  v_t_h := clock_timestamp();

  -- ── 6. THE BUILDINGS: 0089's one rule (public.furnish_harbours writes the rows a harbour lacks; here, only the three's) ──
  perform public.furnish_harbours();

  -- ── 7. A NEW HARBOUR IS A CITY LIKE THE OTHERS: purse, works, flag, tongue, people, and what the waters ask ──
  -- (1) the purse (0122): the row at 0 ducats and its reserve. NO SEED. seeded_at: no live function reads it to decide a seed (public.city_treasury_switch
  --     seeds when no SEED flow or daybook row exists, and writes seeded_at; world.town_hall only shows it). In a world whose cities were seeded (prod) it
  --     is set, so the record of a city whose seeding is closed reads the same for all 249 and 0217's "seeded world" test sees them as the rest; in a
  --     world never seeded (a fresh chain) it stays null like every other harbour there. Either way the purse is 0.
  insert into public.port_treasury (port_id, seeded_at)
  select n.id, case when v_seeded_h then now() else null end from new_h n;
  update public.port_treasury t set reserve = public.treasury_reserve(t.port_id), updated_at = now()
   where t.port_id in (select id from new_h);
  -- (2) the works (0123): the four, level 0
  insert into public.city_works (port_id, kind)
  select n.id, k.kind from new_h n cross join (values ('docks'), ('market'), ('production'), ('inn')) k(kind);
  -- (3) the flag (0143): NO holder, not a home (the pirate claim is the next part's); since = the flag clock as it stood
  insert into public.port_allegiance (port_id, nation_id, home, since)
  select n.id, null, false, v_since_h from new_h n;
  -- (4) the tongue (data/captains.generated.json, scripts/build-captains.mjs)
  insert into public.port_language (port_id, language)
  select p.id, v.language
    from (values
      ('LGA', 'MALAY'),
      ('GOT', 'JAPANESE'),
      ('DJE', 'TURKISH')
    ) as v(code, language)
    join public.ports p on p.code = v.code;
  -- (5) the people (data/port-population.json, scripts/build-population.mjs; 0304: the baseline is the starting population)
  insert into public.port_population (port_id, baseline, year, confidence, note, population)
  select p.id, v.baseline, v.year, v.confidence, v.note, v.baseline
    from (values
      ('LGA', 2000, 1650, 'C', 'the orang laut''s anchorage; Daik, the sultan''s seat from 1787, held ~3,000 by the 1830s'),
      ('GOT', 3000, 1650, 'C', 'Fukue, seat of the Goto clan; the islands held far more'),
      ('DJE', 3000, 1650, 'C', 'Houmt Souk beside the Borj el-Kebir, the corsairs'' island; the island held ~30,000')
    ) as v(code, baseline, year, confidence, note)
    join public.ports p on p.code = v.code;
  -- (6) what the waters ask (0215/0222): every leg out of and into a new harbour. The legs OUT of each new harbour (to every harbour, itself and the
  --     other two included) are the ONE derivation's own, asked per harbour (public.sea_leg_asks_derive(p_from) reads only the pairs that touch it: 0.1 s
  --     a harbour; the whole world's derivation is 6 s, and none of it is needed for a pair that does not touch a new harbour). The legs INTO a new harbour
  --     from an existing one are the same pair read the other way: the derivation measures a pair ONCE (the zones its straight line crosses, its
  --     crossed maximum) and asks of each direction the DESTINATION's own zone, so the way in is that maximum, read back from the way out's zones,
  --     with the new harbour's zone. Four existing harbours spread over the codes are asked of the derivation itself in the assert below.
  insert into public.sea_leg_asks (from_port, to_port, wave_min, title_min, zones)
  select d.from_port, d.to_port, d.wave_min, d.title_min, d.zones
    from new_h n cross join lateral public.sea_leg_asks_derive(n.id) d;
  get diagnostics v_asks_h = row_count;
  insert into public.sea_leg_asks (from_port, to_port, wave_min, title_min, zones)
  select o.to_port, o.from_port,
         greatest(coalesce((select max(z.wave_min) from public.sea_zones z where z.code = any (o.zones)), 0), zn.wave_min)::int,
         greatest(coalesce((select max(z.title_min) from public.sea_zones z where z.code = any (o.zones)), 1), zn.title_min)::int,
         o.zones
    from public.sea_leg_asks o
    join public.sea_zones zn on zn.code = public.harbour_zone(o.from_port)
   where o.from_port in (select id from new_h) and o.to_port not in (select id from new_h);
  get diagnostics v_n_h = row_count;
  v_asks_h := v_asks_h + v_n_h;
  v_ms_h := v_ms_h || jsonb_build_object('cities', round(extract(epoch from clock_timestamp() - v_t_h) * 1000));
  v_t_h := clock_timestamp();

  -- ══ SELF-ASSERT: its own rows only; catalog and cheap reads; never a digest of the live game ══════════════════════
  -- (a) the harbours equal the data, column for column, both ways
  create temp table want_ports_h on commit drop as
    select * from (values
      ('LGA', 'Lingga', 'Indonesia', '', -0.2, 104.62, 'SOA', 'SOU', 'malay', 2, 3, 0, false, 4, 9, 4),
      ('GOT', 'Goto', 'Japan', 'JPN', 32.7, 128.84, 'KOR', 'JAP', 'japanese', 2, 3, 0, false, 4, 9, 4),
      ('DJE', 'Djerba', 'Tunisia', 'OTT', 33.88, 10.86, 'MED', 'MAG', 'islamic', 2, 3, 0, false, 4, 9, 4)
    ) as w(code, name, country, nation_code, lat, lon, sea_code, region_code, culture, size_tier, max_draft, yard_tier, academy, dev_i, dev_c, dev_m);
  select count(*) into v_bad_h
    from want_ports_h w
    full join (select p.code, p.name, p.country, coalesce(n.code, '') as nation_code, p.lat, p.lon, s.code as sea_code, r.code as region_code, p.culture, p.size_tier,
                      p.max_draft, p.yard_tier, p.has_academy as academy, p.dev_industry as dev_i, p.dev_commerce as dev_c, p.dev_military as dev_m, p.kind, p.tax_rate, p.crew_pool, p.has_yard
                 from public.ports p join public.seas s on s.id = p.sea_id join public.regions r on r.id = p.region_id left join public.nations n on n.id = p.nation_id
                where p.code in ('LGA', 'GOT', 'DJE')) d on d.code = w.code
   where w.code is null or d.code is null
      or (w.name, w.country, w.nation_code, w.lat, w.lon, w.sea_code, w.region_code, w.culture, w.size_tier, w.max_draft, w.yard_tier, w.academy, w.dev_i, w.dev_c, w.dev_m)
         is distinct from (d.name, d.country, d.nation_code, d.lat, d.lon, d.sea_code, d.region_code, d.culture, d.size_tier, d.max_draft, d.yard_tier, d.academy, d.dev_i, d.dev_c, d.dev_m)
      or d.kind <> 'HARBOUR' or d.tax_rate <> 0.03 or d.crew_pool <> d.size_tier * 80 or d.has_yard <> (d.yard_tier > 0);
  if v_bad_h <> 0 then
    raise exception '0338 (harbours) self-assert FAIL: % harbour row(s) disagree with the data (data/ports.json through scripts/lib/world-derive.mjs)', v_bad_h;
  end if;
  -- the dev_* columns restate the roster (the derivation rule, asserted as a rule over these rows)
  select count(*) into v_bad_h
    from public.ports p
    join lateral (select count(*) as c from public.port_specialties s where s.port_id = p.id) sc on true
   where p.code in ('LGA', 'GOT', 'DJE')
     and (p.dev_commerce <> greatest(0, least(20, round(p.size_tier * 2.4 + sc.c)))
       or p.dev_industry <> greatest(0, least(20, round(p.size_tier * 2.0 + (select count(*) from public.port_specialties s2 join public.goods g2 on g2.id = s2.good_id where s2.port_id = p.id and g2.industry) * 1.5)))
       or p.dev_military <> greatest(0, least(20, round(p.size_tier * 1.8 + case when p.yard_tier > 0 then 2 else 0 end)))
       or sc.c <> 4);
  if v_bad_h <> 0 then
    raise exception '0338 (harbours) self-assert FAIL: % harbour(s) break the dev_* rule or the small harbour''s four offers', v_bad_h;
  end if;
  -- (b) the offers: exactly the data's, with a POSITIVE CONTROL (a planted bogus offer must be seen by the very query that certifies zero)
  create temp table want_offers_h on commit drop as
    select p.id as port_id, g.id as good_id
      from (values
      ('LGA', 'songket'),
      ('LGA', 'star-anise'),
      ('LGA', 'tamarind'),
      ('LGA', 'zedoary'),
      ('GOT', 'sea-cucumber'),
      ('GOT', 'abalone'),
      ('GOT', 'shark'),
      ('GOT', 'squid'),
      ('DJE', 'sumac'),
      ('DJE', 'maghreb-brass'),
      ('DJE', 'saffian-leather'),
      ('DJE', 'morocco-leather')
      ) as v(port_code, good_code) join public.ports p on p.code = v.port_code join public.goods g on g.code = v.good_code;
  insert into public.port_specialties (port_id, good_id)
  select n.id, g.id from new_h n cross join (select id from public.goods g0 where not exists (select 1 from want_offers_h w where w.good_id = g0.id) order by code limit 1) g
   where n.code = 'LGA';
  select count(*) into v_bad_h from public.port_specialties s where s.port_id in (select id from new_h)
     and not exists (select 1 from want_offers_h w where w.port_id = s.port_id and w.good_id = s.good_id);
  if v_bad_h <> 1 then
    raise exception '0338 (harbours) self-assert FAIL (positive control): one planted offer was seen % time(s), expected exactly 1 - the offers check is blind', v_bad_h;
  end if;
  delete from public.port_specialties s where s.port_id in (select id from new_h) and not exists (select 1 from want_offers_h w where w.port_id = s.port_id and w.good_id = s.good_id);
  select count(*) into v_bad_h from (
    select w.port_id, w.good_id from want_offers_h w except select s.port_id, s.good_id from public.port_specialties s where s.port_id in (select id from new_h)
    union all
    select s.port_id, s.good_id from public.port_specialties s where s.port_id in (select id from new_h) except select w.port_id, w.good_id from want_offers_h w) x;
  if v_bad_h <> 0 then
    raise exception '0338 (harbours) self-assert FAIL: the offers of the new harbours are not the data''s (% differ)', v_bad_h;
  end if;
  -- 0062's law (every offer native or a named entrepot) and 0065's (no good in a fourth city), over the twelve goods
  select count(*) into v_bad_h from want_offers_h w join public.ports p on p.id = w.port_id join public.regions r on r.id = p.region_id join public.goods g on g.id = w.good_id
   where not (r.code = any (g.origin_regions)) and not (p.code = any (g.entrepot_ports));
  if v_bad_h <> 0 then
    raise exception '0338 (harbours) self-assert FAIL: % offer(s) are neither native nor a named entrepot (0062)', v_bad_h;
  end if;
  select count(*) into v_bad_h from (select s.good_id from public.port_specialties s where s.good_id in (select good_id from want_offers_h) group by s.good_id having count(*) > 3) x;
  if v_bad_h <> 0 then
    raise exception '0338 (harbours) self-assert FAIL: % of the new offers put a good in a fourth city (0065)', v_bad_h;
  end if;
  -- (c) the production: within the size ceiling (size 2 -> tier 1), native, 1-2 outputs and a rank 1 each, every one a roster good of its harbour
  select count(*) into v_bad_h from new_h n
   where (select count(*) from public.city_production cp where cp.port_id = n.id) not between 1 and 2
      or not exists (select 1 from public.city_production cp where cp.port_id = n.id and cp.rank = 1)
      or exists (select 1 from public.city_production cp join public.goods g on g.id = cp.good_id join public.ports p on p.id = cp.port_id join public.regions r on r.id = p.region_id
                  where cp.port_id = n.id and (g.tier > case p.size_tier when 2 then 1 when 3 then 2 else 3 end or not (r.code = any (g.origin_regions))
                        or not exists (select 1 from public.port_specialties s where s.port_id = n.id and s.good_id = g.id)));
  if v_bad_h <> 0 then
    raise exception '0338 (harbours) self-assert FAIL: % harbour(s) break 0280''s production rule', v_bad_h;
  end if;
  -- (d) the water: the roadsteads are what the ONE SQL rule answers; each reaches every other place both ways, symmetric, never under the great circle;
  --     the existing rows kept every key they had (to the tenth) and gained exactly the three; the courses run roadstead to roadstead and cross no land
  select count(*) into v_bad_h from public.sea_reaches sr join public.ports p on p.id = sr.port_id cross join lateral voyage.water_roadstead(p.lat, p.lon) w
   where sr.code in ('LGA', 'GOT', 'DJE')
     and (w.lat is distinct from sr.roadstead_lat or w.lon is distinct from sr.roadstead_lon or abs(w.nm - sr.snap_nm) > 0.01
          or abs(voyage.gc_distance_nm(p.lat::float8, p.lon::float8, sr.roadstead_lat::float8, sr.roadstead_lon::float8) - sr.snap_nm) > 0.01);
  if v_bad_h <> 0 then
    raise exception '0338 (harbours) self-assert FAIL: % new roadstead(s) are not what voyage.water_roadstead answers', v_bad_h;
  end if;
  select count(*) into v_bad_h from public.sea_reaches a join public.sea_reaches b on b.code <> a.code
   where a.code in ('LGA', 'GOT', 'DJE')
     and ((a.reaches ->> b.code) is null or (b.reaches ->> a.code) is null or (a.reaches ->> b.code)::numeric <> (b.reaches ->> a.code)::numeric
          or (a.reaches ->> b.code)::numeric < voyage.gc_distance_nm(a.roadstead_lat::float8, a.roadstead_lon::float8, b.roadstead_lat::float8, b.roadstead_lon::float8) - 0.1);
  if v_bad_h <> 0 then
    raise exception '0338 (harbours) self-assert FAIL: % pair(s) with a new place are missing, one-way or under the great circle', v_bad_h;
  end if;
  select count(*) into v_bad_h from public.sea_reaches sr
   where sr.code in ('LGA', 'GOT', 'DJE') and (select count(*) from jsonb_object_keys(sr.reaches)) <> (select count(*) from public.ports) - 1;
  if v_bad_h <> 0 then
    raise exception '0338 (harbours) self-assert FAIL: % new row(s) do not reach every other place', v_bad_h;
  end if;
  select count(*) into v_bad_h from reaches_before_h b join public.sea_reaches sr on sr.code = b.code
   where (sr.snap_nm, sr.roadstead_lat, sr.roadstead_lon) is distinct from (b.snap_nm, b.roadstead_lat, b.roadstead_lon)
      or (sr.reaches - array['LGA', 'GOT', 'DJE']::text[]) is distinct from b.reaches
      or (select count(*) from jsonb_object_keys(sr.reaches) k where k in ('LGA', 'GOT', 'DJE')) <> 3
      or (select count(*) from jsonb_object_keys(sr.reaches)) <> (select count(*) from jsonb_object_keys(b.reaches)) + 3;
  if v_bad_h <> 0 then
    raise exception '0338 (harbours) self-assert FAIL: % existing sea_reaches row(s) changed beyond gaining the three new keys', v_bad_h;
  end if;
  -- POSITIVE CONTROL: bend one old key and the same check sees it exactly once; restore it
  update public.sea_reaches set reaches = jsonb_set(reaches, array['ACC'], '1'::jsonb) where code = 'ACA';
  select count(*) into v_bad_h from reaches_before_h b join public.sea_reaches sr on sr.code = b.code
   where (sr.reaches - array['LGA', 'GOT', 'DJE']::text[]) is distinct from b.reaches;
  if v_bad_h <> 1 then
    raise exception '0338 (harbours) self-assert FAIL: a bent distance was found % time(s), expected exactly 1 - the check cannot bite', v_bad_h;
  end if;
  update public.sea_reaches sr set reaches = (select b.reaches from reaches_before_h b where b.code = sr.code)
         || jsonb_build_object('DJE', (select (d.reaches ->> sr.code)::numeric from public.sea_reaches d where d.code = 'DJE'),
                               'GOT', (select (g.reaches ->> sr.code)::numeric from public.sea_reaches g where g.code = 'GOT'),
                               'LGA', (select (l.reaches ->> sr.code)::numeric from public.sea_reaches l where l.code = 'LGA'))
   where sr.code = 'ACA';
  select count(*) into v_bad_h from reaches_before_h b join public.sea_reaches sr on sr.code = b.code
   where (sr.reaches - array['LGA', 'GOT', 'DJE']::text[]) is distinct from b.reaches;
  if v_bad_h <> 0 then
    raise exception '0338 (harbours) self-assert FAIL: the bent control was not restored (% row(s))', v_bad_h;
  end if;
  select count(*) into v_n_h from public.npc_courses c join new_h a on a.id = c.from_port or a.id = c.to_port;
  if v_n_h <> 18 then
    raise exception '0338 (harbours) self-assert FAIL: % merchant course(s) touch a new harbour, 18 were emitted', v_n_h;
  end if;
  select count(*) into v_bad_h from public.npc_courses c
    join public.ports a on a.id = c.from_port join public.ports b on b.id = c.to_port
    join public.sea_reaches ra on ra.port_id = a.id join public.sea_reaches rb on rb.port_id = b.id
   where (a.code in ('LGA', 'GOT', 'DJE') or b.code in ('LGA', 'GOT', 'DJE'))
     and ((c.course -> 0 ->> 0)::numeric <> ra.roadstead_lat or (c.course -> 0 ->> 1)::numeric <> ra.roadstead_lon
          or (c.course -> -1 ->> 0)::numeric <> rb.roadstead_lat or (c.course -> -1 ->> 1)::numeric <> rb.roadstead_lon
          or c.nm < voyage.gc_distance_nm(ra.roadstead_lat::float8, ra.roadstead_lon::float8, rb.roadstead_lat::float8, rb.roadstead_lon::float8) - 0.1
          or c.nm > 1.10 * (ra.reaches ->> b.code)::numeric
          or voyage.path_refusal(c.course, ra.roadstead_lat, ra.roadstead_lon, rb.roadstead_lat, rb.roadstead_lon, public.wc_num('course_join_nm'), 25, 25) is not null);
  if v_bad_h <> 0 then
    raise exception '0338 (harbours) self-assert FAIL: % merchant course(s) do not run roadstead to roadstead, fall under the great circle or 10 per cent over the sea table, or cross land', v_bad_h;
  end if;
  -- and each new harbour has courses to AND from three existing harbours
  select count(*) into v_bad_h from new_h n
   where (select count(distinct c.to_port) from public.npc_courses c where c.from_port = n.id) <> 3
      or (select count(distinct c.from_port) from public.npc_courses c where c.to_port = n.id) <> 3;
  if v_bad_h <> 0 then
    raise exception '0338 (harbours) self-assert FAIL: % new harbour(s) lack three courses each way', v_bad_h;
  end if;
  -- (e) the market: exactly one row per (new harbour, good); stock at its max, no glut, no drift, no base_target; every row of the twelve goods and
  --     every row this part wrote carries the haul world.haul_rows() gives (the authority itself, read once)
  select count(*) into v_bad_h from new_h n cross join public.goods g
   where (select count(*) from public.port_goods pg where pg.port_id = n.id and pg.good_id = g.id) <> 1;
  if v_bad_h <> 0 then
    raise exception '0338 (harbours) self-assert FAIL: % (harbour, good) pair(s) lack exactly one market row', v_bad_h;
  end if;
  select count(*) into v_n_h from public.port_goods pg where pg.port_id in (select id from new_h);
  if v_n_h <> 3 * (select count(*) from public.goods) or v_n_h <> v_newrows_h then
    raise exception '0338 (harbours) self-assert FAIL: % market rows at the new harbours, % inserted, % expected', v_n_h, v_newrows_h, 3 * (select count(*) from public.goods);
  end if;
  select count(*) into v_bad_h from public.port_goods pg
   where pg.port_id in (select id from new_h)
     and (pg.stock <> pg.stock_target or pg.base_target is not null or pg.glut <> 0 or pg.drift <> 0 or pg.season_mod <> 0 or pg.stock_target <= 0
          or pg.affinity not between 0.25 and 3 or pg.demand <= 0);
  if v_bad_h <> 0 then
    raise exception '0338 (harbours) self-assert FAIL: % new market row(s) are not a seed row (stock = max, no glut/drift/base_target; demand is world.demand_for by construction)', v_bad_h;
  end if;
  -- the offered pairs are producers (affinity_producer, haul 0 / 1.0)
  select count(*) into v_bad_h from public.port_goods pg join public.port_specialties s on s.port_id = pg.port_id and s.good_id = pg.good_id
   where pg.port_id in (select id from new_h) and (pg.affinity <> public.wc_num('affinity_producer') or pg.haul_nm <> 0 or pg.haul <> 1);
  if v_bad_h <> 0 then
    raise exception '0338 (harbours) self-assert FAIL: % offered pair(s) are not producers at haul 0', v_bad_h;
  end if;
  -- the affinity of a sample of the new roster rows (every 12th good by code) is world.affinity_for's, the authority itself
  select count(*) into v_bad_h
    from (select pg.port_id, pg.good_id, pg.affinity, row_number() over (partition by pg.port_id order by g.code) as rn
            from public.port_goods pg join public.goods g on g.id = pg.good_id
           where pg.port_id in (select id from new_h) and exists (select 1 from mk_h m where m.good_id = pg.good_id)) s
   where s.rn % 12 = 1 and world.affinity_for(s.port_id, s.good_id) is distinct from s.affinity;
  if v_bad_h <> 0 then
    raise exception '0338 (harbours) self-assert FAIL: % sampled new roster row(s) differ from world.affinity_for', v_bad_h;
  end if;
  -- the hauls: the authority's rows for the new harbours and for every row of the twelve goods equal what is stored
  create temp table haul_auth_h on commit drop as
    select h.port_id, h.good_id, h.haul_nm, h.haul from world.haul_rows() h
     where h.port_id in (select id from new_h) or h.good_id in (select ps.good_id from public.port_specialties ps where ps.port_id in (select id from new_h));
  select count(*) into v_bad_h from haul_auth_h h join public.port_goods pg on pg.port_id = h.port_id and pg.good_id = h.good_id
   where (pg.haul_nm, pg.haul) is distinct from (h.haul_nm, h.haul);
  select count(*) into v_n_h from haul_auth_h;
  select count(*) into v_m_h from haul_auth_h h join public.port_goods pg on pg.port_id = h.port_id and pg.good_id = h.good_id;
  if v_bad_h <> 0 or v_m_h <> v_n_h
     or v_n_h <> 3 * (select count(*) from public.goods) + (select count(distinct s.good_id) from public.port_specialties s where s.port_id in (select id from new_h)) * ((select count(*) from public.ports p where p.kind = 'HARBOUR') - 3) then
    raise exception '0338 (harbours) self-assert FAIL: % row(s) of the new harbours or the twelve goods differ from world.haul_rows() (% compared)', v_bad_h, v_n_h;
  end if;
  -- POSITIVE CONTROL: the same comparison with one new row's haul bent sees exactly one more, then it is restored
  update public.port_goods pg set haul = pg.haul + 1 where (pg.port_id, pg.good_id) = (select h.port_id, h.good_id from haul_auth_h h where h.port_id in (select id from new_h) order by h.port_id, h.good_id limit 1);
  select count(*) into v_bad_h from haul_auth_h h join public.port_goods pg on pg.port_id = h.port_id and pg.good_id = h.good_id where (pg.haul_nm, pg.haul) is distinct from (h.haul_nm, h.haul);
  if v_bad_h <> 1 then
    raise exception '0338 (harbours) self-assert FAIL: a bent haul was seen % time(s), expected exactly 1 - the haul check is blind', v_bad_h;
  end if;
  update public.port_goods pg set haul = h.haul from haul_auth_h h where pg.port_id = h.port_id and pg.good_id = h.good_id and pg.haul is distinct from h.haul;
  -- (f) the per-harbour rows: buildings (the rule's own set), purse at 0 (reserve = the rule's, seeded_at as decided), works, flag, tongue, people, asks
  select count(*) into v_bad_h from new_h n
   where (select count(*) from public.port_buildings b where b.port_id = n.id) <> (select count(*) from public.harbour_buildings(n.id))
      or exists (select 1 from public.harbour_buildings(n.id) hb where not exists (select 1 from public.port_buildings b where b.port_id = n.id and b.kind = hb.kind and b.tier = hb.tier));
  if v_bad_h <> 0 then
    raise exception '0338 (harbours) self-assert FAIL: % new harbour(s) are not furnished by public.harbour_buildings', v_bad_h;
  end if;
  select count(*) into v_bad_h from new_h n left join public.port_treasury t on t.port_id = n.id
   where t.port_id is null or t.ducats <> 0 or t.reserve <> public.treasury_reserve(n.id) or t.profit <> 0 or t.tax_unshared <> 0
      or (v_seeded_h and t.seeded_at is null) or (not v_seeded_h and t.seeded_at is not null)
      or public.treasury_balance(n.id) <> 0;
  if v_bad_h <> 0 then
    raise exception '0338 (harbours) self-assert FAIL: % new harbour purse(s) are not a purse at 0 (reserve the rule''s, seeded_at as decided: seeded world %)', v_bad_h, v_seeded_h;
  end if;
  select count(*) into v_bad_h from new_h n
   where (select count(*) from public.city_works w where w.port_id = n.id and w.level = 0 and w.subscribed = 0 and w.kind in ('docks', 'market', 'production', 'inn')) <> 4
      or (select count(*) from public.city_works w where w.port_id = n.id) <> 4;
  if v_bad_h <> 0 then
    raise exception '0338 (harbours) self-assert FAIL: % new harbour(s) lack their four works at level 0', v_bad_h;
  end if;
  select count(*) into v_bad_h from new_h n left join public.port_allegiance a on a.port_id = n.id
   where a.port_id is null or a.nation_id is not null or a.home or a.since is distinct from v_since_h;
  if v_bad_h <> 0 then
    raise exception '0338 (harbours) self-assert FAIL: % new harbour(s) are not flagged "no holder, not home" at the flag clock as it stood', v_bad_h;
  end if;
  select count(*) into v_bad_h from public.port_language l join new_h n on n.id = l.port_id;
  if v_bad_h <> 3 then
    raise exception '0338 (harbours) self-assert FAIL: % new tongue(s), 3 expected', v_bad_h;
  end if;
  select count(*) into v_bad_h from public.port_population pp join new_h n on n.id = pp.port_id
   where pp.population <> pp.baseline or pp.slot is not null or pp.kind is not null or pp.paid_day is not null;
  select count(*) into v_n_h from public.port_population pp join new_h n on n.id = pp.port_id;
  if v_bad_h <> 0 or v_n_h <> 3 then
    raise exception '0338 (harbours) self-assert FAIL: % new population row(s) not at their baseline (% found, 3 expected)', v_bad_h, v_n_h;
  end if;
  select count(*) into v_n_h from public.sea_leg_asks a where a.from_port in (select id from new_h) or a.to_port in (select id from new_h);
  select count(*) into v_bad_h from (select a.from_port, a.to_port from public.sea_leg_asks a where a.from_port in (select id from new_h) or a.to_port in (select id from new_h)
                                      group by 1, 2 having count(*) > 1) x;
  if v_n_h <> v_asks_h or v_bad_h <> 0 or v_n_h <> 2 * 3 * (select count(*) from public.ports p where p.kind = 'HARBOUR') - 9 then
    raise exception '0338 (harbours) self-assert FAIL: % leg asks touch a new harbour (% inserted, % duplicated), expected 2 x 3 x harbours - 9', v_n_h, v_asks_h, v_bad_h;
  end if;
  -- the way in was read back from the way out: four existing harbours spread over the codes are asked of the ONE derivation itself, and every leg
  -- they have into a new harbour (4 x 3) equals what was inserted, wave, title and zones
  select count(*), count(*) filter (where (a.wave_min, a.title_min, a.zones) is distinct from (d.wave_min, d.title_min, d.zones)) into v_n_h, v_bad_h
    from (select s.id from (select x.id, row_number() over (order by x.code) as rn from public.ports x
                             where x.kind = 'HARBOUR' and x.id not in (select id from new_h)) s where s.rn % 70 = 1) pick
   cross join lateral public.sea_leg_asks_derive(pick.id) d
    join public.sea_leg_asks a on a.from_port = d.from_port and a.to_port = d.to_port
   where d.to_port in (select id from new_h);
  if v_bad_h <> 0 or v_n_h <> 12 then
    raise exception '0338 (harbours) self-assert FAIL: % of % sampled legs into a new harbour differ from public.sea_leg_asks_derive (12 expected)', v_bad_h, v_n_h;
  end if;
  -- (g) NO GOLD: this part wrote no row to players, treasury_flows, treasury_daybook or ledger, and the only purses it wrote are the three, at 0
  select coalesce(sum(s.n_tup_ins + s.n_tup_upd + s.n_tup_del), 0) into v_xact1_h
    from pg_stat_xact_user_tables s where s.schemaname = 'public' and s.relname in ('players', 'treasury_flows', 'treasury_daybook', 'ledger');
  if v_xact1_h <> v_xact0_h then
    raise exception '0338 (harbours) self-assert FAIL: this part wrote % row(s) to players / treasury_flows / treasury_daybook / ledger - no gold may be made', v_xact1_h - v_xact0_h;
  end if;
  -- the control is not vacuous: the same counter sees the rows this part DID write (ports +3, port_treasury +3)
  select count(*) into v_bad_h from pg_stat_xact_user_tables s
   where s.schemaname = 'public' and ((s.relname = 'ports' and s.n_tup_ins - v_ins_ports_h <> 3) or (s.relname = 'port_treasury' and s.n_tup_ins < 3) or (s.relname = 'port_goods' and s.n_tup_ins < 3 * (select count(*) from public.goods)));
  select count(*) into v_n_h from pg_stat_xact_user_tables s where s.schemaname = 'public' and s.relname in ('ports', 'port_treasury', 'port_goods');
  if v_bad_h <> 0 or v_n_h <> 3 then
    raise exception '0338 (harbours) self-assert FAIL (positive control): pg_stat_xact_user_tables does not show the rows this part wrote (% off, % tables)', v_bad_h, v_n_h;
  end if;
  v_ms_h := v_ms_h || jsonb_build_object('assert', round(extract(epoch from clock_timestamp() - v_t_h) * 1000), 'total', round(extract(epoch from clock_timestamp() - v_t0_h) * 1000));

  raise notice '0338 (harbours) self-assert ok: THREE HARBOURS (LGA GOT DJE) — % offers, % production outputs, % market rows (% new; % existing rows re-derived by a new maker, % existing hauls moved), % reach keys per new row and 3 new keys in % existing rows, % merchant courses, % leg asks, buildings % , purses 0 (seeded world: %), flag rows no holder at the flag clock %, no row written to players / treasury_flows / treasury_daybook / ledger; ms %',
    12, 5, v_newrows_h + v_moved_h, v_newrows_h, v_moved_h, v_hauled_h,
    262, v_places_h, 18, v_asks_h, (select count(*) from public.port_buildings b where b.port_id in (select id from new_h)), v_seeded_h, v_since_h, v_ms_h::text;
end;
  -- └── THE HARBOURS BLOCK ENDS ──
  v_ms := v_ms || jsonb_build_object('harbours', round(extract(epoch from clock_timestamp() - v_t0) * 1000));

  -- ── 3. THE NATION: the 24th, the 11th great power, the one without a crown ──
  insert into public.nations (code, name, flag_char, capital_port_code) values ('PIR', 'The Brethren', '☠', 'POR') on conflict (code) do nothing;
  select n.id into v_pir from public.nations n where n.code = 'PIR';

  alter table public.great_powers add column pirate boolean not null default false;
  create unique index great_powers_one_pirate on public.great_powers ((true)) where pirate;
  comment on column public.great_powers.pirate is
    '0338 (W16): true for the pirates, the one great power with NO crown: no cargo ships, no navy, no capital that aids, taxes or fines. At most one row (great_powers_one_pirate). Read through public.pirate_power. Authored in scripts/lib/world-derive.mjs PIRATE_POWER; the world guard holds it.';
  insert into public.great_powers (nation_id, pirate) values (v_pir, true);

  insert into public.world_config (key, value, description) values
    ('pirates_joinable', 'false'::jsonb, '0338 (W16): may a company sail for The Brethren. False (shipped): cmd.found_house and cmd.change_country refuse the pirates (E_MINOR_POWER) and the country picker does not list them. True: they are a country like the ten. Owner only; no migration is needed to flip it. Read through public.nation_joinable.'),
    ('pirate_ports_free', 'true'::jsonb, '0338 (W16): THE LEVER of the free ports. True (shipped): a pirate home asks no tax and no dock fee, no tax can be set there, and its depth stays at 0.5 (public.port_is_free). False: no port is free, every one taxes and charges as any city does. Owner only; one write, no migration.');

  execute $f$
create function public.pirate_power(p_nation uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0338: THE one reader of "is this the pirate power" (public.great_powers.pirate): the one great power with no crown. It keeps no capital that aids, taxes or fines (public.city_capital), no cargo ship and no navy
  -- (the loops over public.great_powers say `not g.pirate`), and a company may sail for it only when the owner sets pirates_joinable (public.nation_joinable).
  select exists (select 1 from public.great_powers g where g.nation_id = p_nation and g.pirate)
$body$
  $f$;
  revoke all on function public.pirate_power(uuid) from public, anon, authenticated;
  comment on function public.pirate_power(uuid) is '0338: THE one reader of whether a country is the pirates (the great power with no crown). Server-only.';

  execute $f$
create function public.port_is_free(p_port uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0338 (docs/WORLD_POWERS.md section 7.2): THE one reader of "this harbour is a FREE PORT": a pirate HOME, and nothing else, while the lever pirate_ports_free is true. A free port serves no tax (world.tax_rate answers 0 and
  -- cmd.set_tax refuses), charges no dock fee (public.port_fee) and keeps its depth (public.depth_day). A contested city the pirates win later keeps its own rate: only the four homes are free (decided by default).
  select coalesce(public.wc('pirate_ports_free') = 'true'::jsonb, false)
         and exists (select 1 from public.port_allegiance a join public.great_powers g on g.nation_id = a.nation_id
                      where a.port_id = p_port and a.home and g.pirate)
$body$
  $f$;
  revoke all on function public.port_is_free(uuid) from public, anon, authenticated;
  comment on function public.port_is_free(uuid) is '0338: THE one reader of whether a harbour is a free port (a pirate home). Server-only.';

  execute $f$
create function public.nation_joinable(p_nation uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0338: THE one reader of "may a company sail for this country": a great power, and the pirates only when the owner sets pirates_joinable. cmd.found_house, cmd.change_country and the country picker
  -- (world.snapshot's `joinable`) read this and nothing else.
  select public.great_power(p_nation) and (not public.pirate_power(p_nation) or coalesce(public.wc('pirates_joinable') = 'true'::jsonb, false))
$body$
  $f$;
  revoke all on function public.nation_joinable(uuid) from public, anon, authenticated;
  comment on function public.nation_joinable(uuid) is '0338: THE one reader of whether a company may sail for a country (a great power; the pirates only when pirates_joinable). Server-only.';

  -- the ten wars (data/relations.json holds the same ten rows; the world guard holds the table equal to it, both directions)
  insert into public.power_relations (a, b, stance, why)
  select least(v_pir, n.id), greatest(v_pir, n.id), 'war', w.why
    from (values
      ('ENG', 'English shipping was prey to Barbary corsairs and renegade captains, and the Crown hanged pirates at Execution Dock'),
      ('ESP', 'the treasure fleets and the Spanish Main were the prey of Drake and Hawkins and then of the buccaneers; Spain armed the Armada de Barlovento against them (1635)'),
      ('FRA', 'Barbary corsairs raided the Provencal and Languedoc coast for slaves and prizes, and Marseille armed galleys against them'),
      ('JOS', 'the wokou raided the Korean coast for two centuries, and the Joseon navy was built to hunt them'),
      ('JPN', 'the wokou sailed from Kyushu and the Goto islands, but Hideyoshi''s sea-ban edict of 1588 made piracy a crime and the daimyo hunted the crews'),
      ('MNG', 'the wokou raided the Ming coast for a century until Qi Jiguang broke them in the 1560s, and the court shut the sea trade'),
      ('MUG', 'Mughal pilgrim ships to Jeddah and the Gujarat trade were prey to the corsairs of the Arabian Sea and the Malabar coast'),
      ('NLD', 'Dutch merchantmen in the Mediterranean and the Indian Ocean were prey to Barbary and Malay corsairs, and the Republic convoyed its fleets'),
      ('OTT', 'Maltese, Uskok and renegade crews raided the Levant coast and the Red Sea pilgrim ships, and the Porte sent its galleys against them'),
      ('PRT', 'French, English and Barbary corsairs preyed on the Carreira da India and the Brazil ships, and Portugal armed escorts against them')
         ) w(code, why)
    join public.nations n on n.code = w.code;
  get diagnostics v_n = row_count;
  if v_n <> 10 then
    raise exception '0338 self-assert FAIL: % war rows written, the plan names 10', v_n;
  end if;
  v_ms := v_ms || jsonb_build_object('nation', round(extract(epoch from clock_timestamp() - v_t0) * 1000));

  -- ── 4. THE RE-CUTS: hunks sliced from the live bodies ──
  create temp table hunks_0338 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0338 values
  ('public.city_capital(uuid)', 1,
$h$   where n.id = public.port_nation(p_port)
$h$,
$h$   where n.id = public.port_nation(p_port)
     and not public.pirate_power(n.id)   -- 0338: the pirates keep no crown: no capital aids a city of theirs, takes its tax share, or is fined at
$h$),
  ('public.port_fee(uuid, uuid, numeric)', 1,
$h$     or public.crown_house(p_player)   -- 0309: a crown's ship docks free; she has no purse. 0331: a cargo ship's or a navy ship's
$h$,
$h$     or public.crown_house(p_player)   -- 0309: a crown's ship docks free; she has no purse. 0331: a cargo ship's or a navy ship's
     or public.port_is_free(p_port)   -- 0338: a pirate home charges no dock fee, to anyone (docs/WORLD_POWERS.md section 7.2)
$h$),
  ('public.port_dues(uuid, uuid, numeric)', 1,
$h$    'stance', v_stance, 'factor', public.country_factor(v_stance) * public.regard_factor(p_player, p_port),   -- 0319: the factor she really pays
$h$,
$h$    'stance', v_stance,
    'factor', case when public.port_is_free(p_port) then 0 else public.country_factor(v_stance) * public.regard_factor(p_player, p_port) end,   -- 0319: the factor she really pays; 0338: a pirate home asks no tax
$h$),
  ('cmd.set_tax(uuid, numeric)', 1,
$h$    select x.* into m from public.port_mayor x where x.port_id = p_port for update;
$h$,
$h$    if public.port_is_free(p_port) then   -- 0338: a pirate home has no tax to set, whoever holds the office (docs/WORLD_POWERS.md section 7.2)
      perform cmd.refuse('E_FREE_PORT', 'a pirate port has no tax: the Brethren charge none');
    end if;
    select x.* into m from public.port_mayor x where x.port_id = p_port for update;
$h$),
  ('public.depth_day(integer)', 1,
$h$           where t2.depth_day is distinct from p_day
$h$,
$h$           where t2.depth_day is distinct from p_day
             and not public.port_is_free(t2.port_id)   -- 0338: a pirate home keeps the depth it was given (0.5), whatever is invested there
$h$),
  ('public.convoy_ships_wanted()', 1,
$h$      from public.great_powers g
  ), b as (
$h$,
$h$      from public.great_powers g
     where not g.pirate   -- 0338: the pirates have no crown, so no cargo ships
  ), b as (
$h$),
  ('public.tick_cargo_ships(timestamp with time zone, uuid)', 1,
$h$     where (p_only_nation is null or g.nation_id = p_only_nation)
       and (k.built_at is null$h$,
$h$     where not g.pirate   -- 0338: the pirates have no crown, so no circuit and no cargo ship
       and (p_only_nation is null or g.nation_id = p_only_nation)
       and (k.built_at is null$h$),
  ('public.navy_read(timestamp with time zone)', 1,
$h$  with w as (select g.nation_id, public.realm_purse(g.nation_id) as purse from public.great_powers g),
$h$,
$h$  with w as (select g.nation_id, public.realm_purse(g.nation_id) as purse from public.great_powers g where not g.pirate),   -- 0338: the pirates keep no navy
$h$),
  ('public.navy_plan_step(timestamp with time zone, uuid)', 1,
$h$   where (p_only_nation is null or g.nation_id = p_only_nation)
     and (r.stations_at is null$h$,
$h$   where not g.pirate   -- 0338: the pirates keep no navy and no stations
     and (p_only_nation is null or g.nation_id = p_only_nation)
     and (r.stations_at is null$h$),
  ('world.levels()', 1,
$h$                          cross join lateral (select public.regard_of(v_id, n.id) as score) y) end);
$h$,
$h$                          cross join lateral (select public.regard_of(v_id, n.id) as score) y
                          where not g.pirate) end);   -- 0338: a company keeps no regard with the pirates; their ports charge nothing
$h$),
  ('world.snapshot()', 1,
$h$        'great', public.great_power(n.id)) order by n.code), '[]'::jsonb)   -- 0028 WIND; GP1: one of the ten great powers
$h$,
$h$        'great', public.great_power(n.id),
        'joinable', public.nation_joinable(n.id)) order by n.code), '[]'::jsonb)   -- 0028 WIND; GP1: one of the great powers; 0338: one a company may sail for
$h$),
  ('cmd.found_house(text, text)', 1,
$h$                  from public.nations where public.great_power(id)));   -- GP1: the ten
  end if;

  -- GP1: a company sails for one of the ten great powers; the thirteen others rule their own cities.
  if not public.great_power((select id from public.nations where code = v_nation)) then
    return jsonb_build_object(
      'ok', false, 'error_code', 'E_MINOR_POWER',
      'error_message', format('%s rules its own cities, but a company sails for one of the ten great powers.',
                              (select name from public.nations where code = v_nation)),
      'fixes', (select jsonb_agg(format('(sail under %s — %s)', code, name) order by code)
                  from public.nations where public.great_power(id)));
  end if;
$h$,
$h$                  from public.nations where public.nation_joinable(id)));   -- GP1: the ten; 0338: those a company may sail for
  end if;

  -- GP1: a company sails for one of the great powers it may join; the others take none (the thirteen rule their own cities; the pirates, until pirates_joinable).
  if not public.nation_joinable((select id from public.nations where code = v_nation)) then
    return jsonb_build_object(
      'ok', false, 'error_code', 'E_MINOR_POWER',
      'error_message', format('%s takes no companies: a company sails for one of the great powers it may join.',
                              (select name from public.nations where code = v_nation)),
      'fixes', (select jsonb_agg(format('(sail under %s — %s)', code, name) order by code)
                  from public.nations where public.nation_joinable(id)));
  end if;
$h$),
  ('world.tax_rate(uuid, uuid)', 1,
$h$begin
  if not public.city_treasury_on() then
    return v_col;
  end if;
$h$,
$h$begin
  if public.port_is_free(p_port) then   -- 0338: a pirate home asks no tax of anyone (docs/WORLD_POWERS.md section 7.2); ports.tax_rate stays as it was, so the lever pirate_ports_free restores it
    return 0;
  end if;
  if not public.city_treasury_on() then
    return v_col;
  end if;
$h$),
  ('cmd.change_country(text)', 1,
$h$    -- GP1: a company sails for one of the ten great powers; the thirteen others rule their own cities.
    if not public.great_power(v_to.id) then
      perform cmd.refuse('E_MINOR_POWER', format('%s rules its own cities, but a company sails for one of the ten great powers',
                                                 v_to.name));
    end if;
$h$,
$h$    -- GP1: a company sails for one of the great powers it may join; the others take none (the thirteen rule their own cities; the pirates, until pirates_joinable).
    if not public.nation_joinable(v_to.id) then
      perform cmd.refuse('E_MINOR_POWER', format('%s takes no companies: a company sails for one of the great powers it may join',
                                                 v_to.name));
    end if;
$h$);

  -- every hunk is checked against its live body BEFORE anything is replaced; then the bodies are replaced
  if (select count(distinct h.fn) from hunks_0338 h) <> (select count(*) from defs_0338)
     or exists (select 1 from hunks_0338 h where h.fn not in (select t.fn from defs_0338 t)) then
    raise exception '0338 self-assert FAIL: a pre-imaged body has no hunk, or a hunk names a body not pre-imaged';
  end if;
  for r_d in select * from defs_0338 t order by t.ord loop
    v_def := r_d.def;
    for r_hk in select * from hunks_0338 h where h.fn = r_d.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, r_hk.old, ''))) / length(r_hk.old);
      if v_n <> 1 then
        raise exception '0338 self-assert FAIL: hunk % of % occurs % time(s), not once: the live body is not what this file was cut against', r_hk.ord, r_hk.fn, v_n;
      end if;
      v_def := replace(v_def, r_hk.old, r_hk.new);
    end loop;
    execute v_def;
  end loop;
  v_ms := v_ms || jsonb_build_object('recut', round(extract(epoch from clock_timestamp() - v_t0) * 1000));

  -- ── 5. THE HOMES AND THE FREE PORTS: the trigger is disabled BY NAME for exactly this statement, inside this one atomic block, and enabled again ──
  alter table public.port_allegiance disable trigger port_allegiance_home_never_changes;
  update public.port_allegiance a
     set nation_id = v_pir, home = true, since = least(a.since, v_since)
    from public.ports p
   where p.id = a.port_id and p.code = any (c_homes) and a.nation_id is null and not a.home;
  get diagnostics v_n = row_count;
  alter table public.port_allegiance enable trigger port_allegiance_home_never_changes;
  if v_n <> 4 then
    raise exception '0338 self-assert FAIL: % pirate homes were claimed, the plan names 4 (Port Royal and the three new harbours must all be free cities)', v_n;
  end if;
  update public.port_treasury t set depth_mult = 0.5 from public.ports p where p.id = t.port_id and p.code = any (c_homes);
  get diagnostics v_x = row_count;
  if v_x <> 4 then
    raise exception '0338 self-assert FAIL: depth set on % homes (the plan names 4)', v_x;
  end if;
  v_ms := v_ms || jsonb_build_object('homes', round(extract(epoch from clock_timestamp() - v_t0) * 1000));

  -- ── 6. THE SELF-ASSERT: the catalog, then cheap pure reads, then probes that roll back ──
  -- 6a every re-cut reverses to its pre-image; attributes unmoved
  for r_d in select * from defs_0338 t order by t.ord loop
    v_rev := replace(pg_get_functiondef(r_d.oid), E'\r', '');
    for r_hk in select * from hunks_0338 h where h.fn = r_d.fn order by h.ord desc loop
      v_n := (length(v_rev) - length(replace(v_rev, r_hk.new, ''))) / length(r_hk.new);
      if v_n <> 1 then
        raise exception '0338 self-assert FAIL: % - the new text of hunk % is not in the live body exactly once', r_d.fn, r_hk.ord;
      end if;
      v_rev := replace(v_rev, r_hk.new, r_hk.old);
    end loop;
    if v_rev <> r_d.def then
      raise exception '0338 self-assert FAIL: % does not reverse to its pre-image', r_d.fn;
    end if;
    if (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = r_d.oid) <> r_d.acl
       or (select p.provolatile from pg_proc p where p.oid = r_d.oid) <> r_d.vol
       or (select p.prosecdef from pg_proc p where p.oid = r_d.oid) <> r_d.secdef
       or (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = r_d.oid) <> r_d.cfg
       or (select p.proparallel from pg_proc p where p.oid = r_d.oid) <> r_d.par
       or (select p.proowner from pg_proc p where p.oid = r_d.oid) <> r_d.owner
       or (select l.lanname from pg_proc p join pg_language l on l.oid = p.prolang where p.oid = r_d.oid) <> r_d.lang then
      raise exception '0338 self-assert FAIL: % - ACL, volatility, definer, config, parallel safety, owner or language moved', r_d.fn;
    end if;
  end loop;

  -- 6b no other function moved; the three new ones are server-only, stable, definer; only the one knob was added
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> all (select t.oid from defs_0338 t)
         and not (n.nspname = 'public' and p.proname in ('pirate_power', 'port_is_free', 'nation_joinable'))) is distinct from v_fn_before then
    raise exception '0338 self-assert FAIL: a function this file does not re-cut moved';
  end if;
  for r_x in select p.proname, p.provolatile, p.prosecdef, coalesce(p.proconfig::text, '') as cfg, p.oid
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname in ('pirate_power', 'port_is_free', 'nation_joinable') loop
    if r_x.provolatile <> 's' or not r_x.prosecdef or r_x.cfg <> '{"search_path=public, pg_temp"}'
       or has_function_privilege('anon', r_x.oid, 'execute') or has_function_privilege('authenticated', r_x.oid, 'execute')
       or exists (select 1 from aclexplode(coalesce((select p.proacl from pg_proc p where p.oid = r_x.oid), acldefault('f', (select p.proowner from pg_proc p where p.oid = r_x.oid)))) a where a.grantee = 0) then
      raise exception '0338 self-assert FAIL: public.% is not stable, definer, search_path-pinned and server-only', r_x.proname;
    end if;
  end loop;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname in ('pirate_power', 'port_is_free', 'nation_joinable')) <> 3 then
    raise exception '0338 self-assert FAIL: the three new readers are not exactly three functions';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key not in ('pirates_joinable', 'pirate_ports_free')) is distinct from v_cfg_before
     or (select md5(string_agg(c.key || ':' || c.value::text, ',' order by c.key)) from public.world_config c where c.key in ('pirates_joinable', 'pirate_ports_free'))
        is distinct from md5('pirate_ports_free:true,pirates_joinable:false') then
    raise exception '0338 self-assert FAIL: a knob moved, or the knobs are not shipped as planned (pirates_joinable false, pirate_ports_free true)';
  end if;

  -- the posture (supabase/migrations/README.md section 3): no new door for a client, and both halves of the wall read zero
  if (select count(*) from public.client_rpc_entry_points()) <> v_entry
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0338 self-assert FAIL: the registry or a wall moved (no new door; the posture must read zero)';
  end if;

  -- 6c the nation, the great powers, the one pirate, the wars
  if (select count(*) from public.nations) <> v_nations + 1
     or (select count(*) from public.great_powers) <> 11
     or (select count(*) from public.great_powers g where g.pirate) <> 1
     or not (select g.pirate from public.great_powers g where g.nation_id = v_pir)
     or (select n.flag_char || '|' || n.name || '|' || n.capital_port_code from public.nations n where n.id = v_pir) <> '☠|The Brethren|POR'
     or not exists (select 1 from public.ports p where p.code = 'POR' and p.kind = 'HARBOUR') then
    raise exception '0338 self-assert FAIL: the nation or its pirate flag is not as the plan says';
  end if;
  begin
    update public.great_powers set pirate = true where nation_id = (select n.id from public.nations n where n.code = 'PRT');
    raise exception '0338 self-assert FAIL: a second pirate power was accepted (great_powers_one_pirate does not bite)';
  exception when unique_violation then
    null;
  end;
  if (select count(*) from public.power_relations r where r.a = v_pir or r.b = v_pir) <> 10
     or exists (select 1 from public.power_relations r where (r.a = v_pir or r.b = v_pir) and r.stance <> 'war')
     or (select md5(coalesce(string_agg(r.a::text || r.b::text || r.stance || r.why, ',' order by r.a, r.b), ''))
           from public.power_relations r where r.a <> v_pir and r.b <> v_pir) is distinct from v_rel_before then
    raise exception '0338 self-assert FAIL: the pirates are not at war with exactly the ten, or another relation moved';
  end if;

  -- 6d the four homes: held by the pirates, home, flag clock not past the newest earlier change, tax quoted 0, depth 0.5 (that no other harbour became free is 6e's count of port_is_free; a mayor may set any city's tax to 0, so no count of zero quotes is asserted)
  select count(*) into v_n from public.port_allegiance a join public.ports p on p.id = a.port_id
   where a.home and a.nation_id = v_pir and p.code = any (c_homes) and a.since <= v_since;
  if v_n <> 4 or (select count(*) from public.port_allegiance a where a.nation_id = v_pir) <> 4
     or (select count(*) from public.port_allegiance a where a.home and a.nation_id = v_pir) <> 4 then
    raise exception '0338 self-assert FAIL: the pirates do not hold exactly their four homes, home, with the flag clock held';
  end if;
  if exists (select 1 from public.ports p where p.code = any (c_homes) and world.tax_rate(p.id) <> 0)
     or (select count(*) from public.port_treasury t join public.ports p on p.id = t.port_id where p.code = any (c_homes) and t.depth_mult = 0.5) <> 4 then
    raise exception '0338 self-assert FAIL: the four homes do not all quote tax 0 and hold depth 0.5';
  end if;
  if (select t.tgenabled from pg_trigger t where t.tgname = 'port_allegiance_home_never_changes' and t.tgrelid = 'public.port_allegiance'::regclass) <> 'O' then
    raise exception '0338 self-assert FAIL: the home guard trigger is not enabled again';
  end if;
  begin   -- and it BITES: a home city cannot be un-homed (the probe rolls back)
    update public.port_allegiance a set home = false from public.ports p where p.id = a.port_id and p.code = 'POR';
    raise exception '0338 self-assert FAIL: the home guard let a home city stop being home';
  exception when others then
    if sqlerrm !~ '^E_HOME_CITY' then raise; end if;
  end;

  -- 6e the readers: who is free, who has a crown, who may be joined
  if (select count(*) from public.ports p where p.kind = 'HARBOUR' and public.port_is_free(p.id)) <> 4
     or exists (select 1 from public.ports p where p.code = any (c_homes) and not public.port_is_free(p.id))
     or exists (select 1 from public.ports p where p.code = any (c_homes) and public.city_capital(p.id) is not null)
     or public.city_capital((select p.id from public.ports p where p.code = 'LIS')) is distinct from (select p.id from public.ports p where p.code = 'LIS')
     or public.city_capital((select p.id from public.ports p where p.code = 'SET')) is distinct from (select p.id from public.ports p where p.code = 'LIS')
     or public.realm_capital(v_pir) is distinct from (select p.id from public.ports p where p.code = 'POR')
     or not public.pirate_power(v_pir) or public.pirate_power((select n.id from public.nations n where n.code = 'PRT')) then
    raise exception '0338 self-assert FAIL: port_is_free, city_capital, realm_capital or pirate_power does not answer as the plan says';
  end if;
  select count(*) filter (where public.great_power(n.id)), count(*) filter (where public.nation_joinable(n.id)) into v_n, v_x from public.nations n;
  if v_n <> 11 or v_x <> 10 or public.nation_joinable(v_pir) or not public.nation_joinable((select n.id from public.nations n where n.code = 'PRT')) then
    raise exception '0338 self-assert FAIL: % great powers and % joinable, the plan names 11 and 10 (the pirates not)', v_n, v_x;
  end if;
  begin   -- the lever, flipped inside a probe that rolls back: no port is free, the four tax again (their stored rate), and nobody else changes
    update public.world_config set value = 'false'::jsonb where key = 'pirate_ports_free';
    if (select count(*) from public.ports p where p.kind = 'HARBOUR' and public.port_is_free(p.id)) <> 0
       or exists (select 1 from public.ports p where p.code = any (c_homes) and world.tax_rate(p.id) = 0) then
      raise exception '0338 self-assert FAIL: with pirate_ports_free false a port is still free or still quotes no tax';
    end if;
    raise exception 'PROBE_ROLLBACK_0338';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_0338' then raise; end if;
  end;
  if (select c.value from public.world_config c where c.key = 'pirate_ports_free') <> 'true'::jsonb then
    raise exception '0338 self-assert FAIL: the lever probe left pirate_ports_free changed';
  end if;
  begin   -- the knob, flipped inside a probe that rolls back: the pirates become joinable and nobody else changes
    update public.world_config set value = 'true'::jsonb where key = 'pirates_joinable';
    select count(*) filter (where public.nation_joinable(n.id)) into v_x from public.nations n;
    if v_x <> 11 or not public.nation_joinable(v_pir) then
      raise exception '0338 self-assert FAIL: with pirates_joinable true, % joinable (the plan names 11)', v_x;
    end if;
    raise exception 'PROBE_ROLLBACK_0338';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_0338' then raise; end if;
  end;
  if public.nation_joinable(v_pir) or (select c.value from public.world_config c where c.key = 'pirates_joinable') <> 'false'::jsonb then
    raise exception '0338 self-assert FAIL: the knob probe left pirates_joinable changed';
  end if;
  if (select count(*) from public.convoy_ships_wanted() w where w.nation_id = v_pir) <> 0
     or (select count(*) from public.convoy_ships_wanted()) <> 10 then
    raise exception '0338 self-assert FAIL: convoy_ships_wanted does not answer the ten crowns and not the pirates';
  end if;

  -- 6f THE MONEY PROOF BY CONSTRUCTION: this transaction wrote no money row except the three new purses, at 0; and it wrote no influence, no event
  for r_x in select a.relname, a.n_tup_ins - coalesce(b.n_tup_ins, 0) as i, a.n_tup_upd - coalesce(b.n_tup_upd, 0) as u, a.n_tup_del - coalesce(b.n_tup_del, 0) as dl
             from pg_stat_xact_user_tables a left join xact0_0338 b on b.relname = a.relname
            where a.relname in ('players', 'treasury_flows', 'treasury_daybook', 'ledger', 'port_influence', 'events', 'player_storage', 'fleets', 'ships') loop
    if r_x.i <> 0 or r_x.u <> 0 or r_x.dl <> 0 then
      raise exception '0338 self-assert FAIL: this file wrote % row(s) to %, which it must never touch (ins %, upd %, del %)', r_x.i + r_x.u + r_x.dl, r_x.relname, r_x.i, r_x.u, r_x.dl;
    end if;
  end loop;
  select a.n_tup_ins - coalesce(b.n_tup_ins, 0) into v_n from pg_stat_xact_user_tables a left join xact0_0338 b on b.relname = a.relname where a.relname = 'ports';
  select a.n_tup_ins - coalesce(b.n_tup_ins, 0) into v_x from pg_stat_xact_user_tables a left join xact0_0338 b on b.relname = a.relname where a.relname = 'port_treasury';
  if v_n <> 3 or v_x <> 3 then   -- the positive control: the counters DO see this block's writes (three harbours, three purses)
    raise exception '0338 self-assert FAIL: the transaction counters saw % ports and % purses inserted, not 3 and 3 (the money proof would be vacuous)', v_n, v_x;
  end if;
  if exists (select 1 from public.port_treasury t join public.ports p on p.id = t.port_id where p.code in ('LGA', 'GOT', 'DJE') and t.ducats <> 0)
     or exists (select 1 from public.treasury_flows f join public.ports p on p.id = f.port_id where p.code in ('LGA', 'GOT', 'DJE')) then
    raise exception '0338 self-assert FAIL: a new harbour holds gold, or a flow names one';
  end if;
  v_ms := v_ms || jsonb_build_object('assert', round(extract(epoch from clock_timestamp() - v_t0) * 1000));

  -- ── 7. RECEIPT ──
  raise notice '0338 NOTE: the live paths (a lit cargo job and navy that never touch the pirates, the dock fee and tax of a company at a free port, the tax refusal, the doors with the knob false and true, the picker''s ten, W and the influence book equal across the claim) are proved in CI by scripts/db/proofs/45_the_brethren.sql and locally by scripts/ops/harness/the-brethren/proof-0338.mjs, not in this block';
  raise notice '0338 timings ms (cumulative): %', v_ms;
  raise notice '0338 self-assert ok: THE BRETHREN - 14 bodies re-cut (every hunk once, each reverses, attributes unmoved), no other function moved, 3 server-only readers, 2 knobs (pirates_joinable false, pirate_ports_free true, the lever probed), 24 nations, 11 great powers (1 pirate), 10 wars, 4 homes held (since clock held at %), tax quoted 0 and depth 0.5 on all 4, home guard enabled and biting, joinable 10 of 11 (11 with the knob, probe rolled back), 3 harbours and 3 purses at 0, no row written to players / flows / daybook / ledger / influence / events',
    v_since;
end
$m$;
