-- ═══════════════════════════════════════════════════════════════════════════════════════════════════
-- 0341 — PIRATE MERCHANTS (W18): the Brethren's merchants. Founded from the hoard, routed among the pirate homes' waters, investing for the pirates. DARK behind 0339's one switch `pirates_bite`
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER (docs/OWNER_REQUESTS.md row 284, 2026-11-05): "pirates are like countries - power, where they can also invest. pirate merchants too. they will have pirate port that has no tax, cheaper products etc".
-- 2026-11-06 (row 306): "use your recommended defaults for the rest". 2026-11-07: "do it fast". The design is docs/WORLD_POWERS.md Part 5, sections 7.4 (pirate merchants and investing), 7.6 (the limits) and 7.7 (row W18:
-- "Founding, routes, investing, pirate_port_day_cap"; proof "Founded only from the hoard; spend_day_pct holds; daily count runs with 11"). Step 3 of 4 (W16 to W19). Built on 0338 (W16, the nation PIR, the four free homes)
-- and on 0339 (W17: THE switch public.pirates_on(), the hoard, the capital, THE one cap public.pirate_spend_room and THE one payer public.pirate_pay; its CONTRACT, docs/dev-log/2026-11-07-pirate-ships-sail.md).
-- THIS FILE IS W18 AND NOTHING ELSE: no pirate ship (W17), no navy hunting (W19), no switch or knob flipped (owner only). Dev-log: docs/dev-log/2026-11-07-pirate-merchants.md.
--
-- WHAT LANDS (everything behind public.pirates_on(); with it false the world reads byte for byte as before this file: nothing is founded, nothing is invested by the pirates, every quote and plan is what it was)
--   * A PIRATE MERCHANT is a merchant house (public.npc_houses) of nation PIR, founded through public.npc_found like the ten crowns' 821, with ONE difference, in ONE place: her starting money comes from the hoard through
--     public.pirate_pay (a hunk in public.founding_credit, the one place a company's starting money is paid), inside public.pirate_spend_room, as the new moved kind PIRATE_FOUND (public.stats_flow_words). A founding
--     the hoard cannot pay is refused WHOLE (E_HOARD_SHORT): nothing of her stays written. A company (a player) sailing for the pirates is paid as every founding is (0338 proved it): untouched.
--   * THE JOB public.tick_pirate_merchants (pg_cron byeharu-voyage:pirate-merchants, every 10 minutes, never in the beat): lit, at most ONE founding a run (public.pirate_found), and only when: fewer than
--     pirate_merchants_max (30) pirate merchants exist; the newest was founded pirate_found_hours (2) or more ago; the merchant roster has a berth (public.npc_fleets under npc_fleet_max, so she never lies paused 'dark');
--     and the Brethren may still spend today her capital AND what their ships are owed for the rest of the UTC day (pirate_size x navy_upkeep_day, pro rata), so a founding never starves 0339's hourly pay.
--     Her slot (the count of pirate merchants + 1) names her and her home: the capital first, then the homes by code, wrapping, the first of those with a known leg out (public.npc_known_legs). She sails
--     pirate_merchant_class (carlat, the lateen caravel of the Barbary corsairs: one of the three hulls a merchant loadout is authored for), is founded with pirate_merchant_capital (250,000 d.), Haggling 1, no officer, patience 0.30, wares none (the planner's "every good"),
--     in ink 'pir' (a ninth ink family: npc_houses.ink's check gains it; the chart draws it as the pirate merchant look of docs/WORLD_POWERS.md 9.3), with an out-and-back first loop to the nearest known harbour
--     of her home. From there she is a merchant like any: public.npc_tend plans, assigns and tends her, public.npc_plan re-plans her loops, she trades, pays wages and dock dues, and her hulls are refitted from her home's purse (0322).
--   * SHE INVESTS AND GIVES FOR THE PIRATES through the one pass (public.npc_invest, nothing changed there): her stake and gift land in public.port_influence under PIR, and the daily count (public.tick_influence) ranks
--     PIR with the ten as it ranks any nation: a city the pirates win flies the skull, keeps its own tax and dock fee (only the homes are free, 0338), and has no crown. While the pirates are dark she invests and gives nothing
--     (a hunk in public.npc_invest_roster). She is never gifted by the capital's pass (a hunk in public.capital_gift_roster): the hoard pays her founding and nothing after, decided by default.
--   * NOBODY INSURES HER (a hunk in public.insure_voyage): no city takes her premium, so no city pays for her cargo (7.4, decided by default). A pirate merchant may be attacked by navies (W19); regard is unaffected.
--   * THE LIMITS OF 7.6, lit WITH the pirates (plunder-filled stock makes arbitrage, 0339's pirate_stow): (a) the merchant route planner skips a PIRATE HOME as a destination unless the merchant's own home is that port
--     (three hunks in public.npc_loop_candidates through one reader, public.npc_legs_open: the only pirate home on a pirate merchant's loop is her own, since no course joins two homes, so "unless she is PIR" and
--     "except her way home" are the same rule and the cheaper one is kept); (b) pirate_port_day_cap: at a pirate home a company may trade a good up to 5 % of its most stock (twice the target, 0339's stow ceiling) a day
--     (one hunk in world.daily_cap_remaining, the one reader of the day cap, so the Buy and Sell doors, the fulfil order, the good's board and the merchant leg planner all read it).
--   * Nothing is minted: W (companies + merchants + purses + set aside + funds aboard) is unchanged by every move here (PIRATE_FOUND is a city paying a house: public.city_pays inside public.pirate_pay). mint_guard untouched.
--
-- THE CONSUMERS OF NPC MERCHANTS BY NATION, and what each does with a pirate merchant (the audit is in the dev-log; the server half in one line each): public.npc_tend / npc_tend_roster / npc_tend_route / npc_plan tend
--   her as any merchant (no nation read); public.npc_invest / npc_invest_one / npc_closest_race invest for her nation (PIR is a great power: port_influence's foreign key admits it); public.tick_influence ranks every
--   nation on the rows (11 or 10 alike), skips the homes, makes a mayor of her where PIR holds a city; public.population_signals reads her points at a crown city as war (PIR is at war with the ten: intended, 0338);
--   public.capital_gift_roster re-cut (no gift); public.insure_voyage re-cut (no insurer); public.sea_houses serves her ink 'pir' and no kind (she is a MERCHANT: public.fleet_kind unchanged, every engine read of
--   a merchant unchanged); world.sea_roster / sea_traffic serve nation_code PIR and the ink; world.npc_fleet_card, world.port_merchants, world.stats_merchants, stats_merchants_board, world.route_board join nations by
--   code and show The Brethren; public.fleet_origin answers her home (0322's wreck and refit from her home's purse); public.crown_house false (she pays dock fees and wages as a merchant; she is counted as one);
--   the regard list of world.levels leaves the pirates out (0338). NOT a consumer: public.npc_hull_for (no PIR line: she sails the class named), cargo_* / navy_* (the pirates have none).
--
-- THE RE-CUTS (hunks sliced from the LIVE bodies of the cached head after 0339; each hunk occurs exactly once in the live body and reverses to its pre-image; ACL, volatility, definer, config, parallel safety,
-- owner and language unmoved; this file supersedes those lines of): public.founding_credit (0234), public.capital_gift_roster (0267), public.npc_invest_roster (0267, 0313), public.insure_voyage (0213),
-- public.npc_loop_candidates (0120, 0186, 0264: three hunks), world.daily_cap_remaining (0318). New, one per concept: public.pirate_home (a pirate home), public.pirate_merchant (a merchant of the pirates),
-- public.npc_legs_open (the planner's rule), public.pirate_merchant_spec (her founding spec), public.pirate_found (the founding), public.tick_pirate_merchants (the job). Five knobs, one word, one ink, one cron job.
-- NOT touched: any other function, table, switch or job; 0339's functions are read, never re-cut.
--
-- ALL OR NOTHING. Prod's runner sends a file statement by statement (docs/OPS_HEALTH.md section 4), so the WHOLE file is ONE `do` block: a failure anywhere rolls back every row, constraint, function and the cron job
-- with it. statement_timeout 90 s and lock_timeout 5 s are its first act; the file's budget is 45 s on prod (locally about 1 s).
--
-- SELF-ASSERT (this block): catalog and cheap pure reads only, never a game step and never a digest of live rows. Every hunk once and reversing; no other function moved (md5 over every one); the six new functions
-- server-only, definer, search_path-pinned, of the declared volatility; only the five knobs added, as shipped; the one word, moved; the ink check with nine inks; pirate_home exactly the four homes; pirate_merchant false
-- for every house in the world; npc_legs_open the identity while dark and, with the switch flipped INSIDE A PROBE THAT ROLLS BACK, a pirate home stripped from a sample and the own home kept; the day cap at a pirate
-- home equal to the base while dark and bounded lit (the same probe); no new client door and the posture at zero; the cron job scheduled where cron exists; THE MONEY PROOF BY CONSTRUCTION: this transaction wrote no
-- row to players, npc_houses, npc_fleets, fleets, ships, treasury_flows, treasury_daybook, ledger, port_influence, events, trade_daily, insured_voyages or pirate_spend_day (pg_stat_xact_user_tables, with a positive
-- control on world_config). THE LIVE PATHS (a founding paid by Port Royal within the cap and refused whole without it; the pace, the max, the berth, the reserve for the ships; no gift, no insurer; her stake and gift
-- for PIR and the count flipping a city to the skull that keeps its tax; a crown merchant's planner skipping a pirate home and hers keeping her way home; the day cap at a home; dark parity; W unchanged to the ducat)
-- ARE PROVED IN CI: scripts/db/proofs/47_pirate_merchants.sql and the local harness scripts/ops/harness/pirate-merchants/proof-0341.mjs; the file says so in a printed notice in every environment.
--
-- ROLLBACK: the switch (pirates_bite false, owner only): nothing more is founded, the pirates invest nothing, the planner and the day cap are what they were; a pirate merchant already founded goes on trading as a
-- merchant (she is a merchant; laying her up is a decision for the owner). The rest, forward, a NEW migration, owner only: hunks are reversible (each OLD text is in this file); the knobs, the word and the cron job are data.
-- VERSION: 0341 = 0338 (W16, LIVE) + 0339 (W17) + 0340 (W19, ready first) + 1: the coordinator's numbering of 2026-11-07.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_fns        constant text[] := array['pirate_home', 'pirate_merchant', 'npc_legs_open', 'pirate_merchant_spec', 'pirate_found', 'tick_pirate_merchants'];
  c_knobs      constant text[] := array['pirate_merchants_max', 'pirate_merchant_capital', 'pirate_merchant_class', 'pirate_found_hours', 'pirate_port_day_cap'];
  c_homes      constant text[] := array['POR', 'LGA', 'GOT', 'DJE'];
  v_t0         timestamptz := clock_timestamp();
  v_ms         jsonb := '{}'::jsonb;
  v_pir        uuid;
  v_n          int;
  v_x          int;
  v_def        text;
  v_rev        text;
  v_fn_before  text;
  v_cfg_before text;
  v_cfg_probe  text;
  v_words      int;
  v_entry      int;
  v_cron       text;
  v_legs       jsonb;
  v_open       jsonb;
  v_cap        numeric;
  v_base       numeric;
  v_probe      uuid := '00000000-0341-4000-8000-000000000001';
  v_good       uuid;
  r_d          record;
  r_hk         record;
  r_x          record;
begin
  perform set_config('statement_timeout', '90s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD: nothing of this file exists, and the premises it was cut against hold (else NOTHING is applied) ──
  if to_regprocedure('public.pirate_home(uuid)') is not null or to_regprocedure('public.pirate_merchant(uuid)') is not null
     or to_regprocedure('public.npc_legs_open(jsonb, uuid)') is not null or to_regprocedure('public.pirate_merchant_spec(integer)') is not null
     or to_regprocedure('public.pirate_found(timestamp with time zone)') is not null or to_regprocedure('public.tick_pirate_merchants(timestamp with time zone)') is not null
     or exists (select 1 from public.world_config where key = any (c_knobs))
     or exists (select 1 from public.stats_flow_words w where w.kind = 'PIRATE_FOUND') then
    raise exception '0341 refuses: the pirate merchants are already in this world';
  end if;
  if to_regprocedure('public.pirate_power(uuid)') is null or to_regprocedure('public.port_is_free(uuid)') is null
     or to_regprocedure('public.pirates_on()') is null or to_regprocedure('public.pirate_nation()') is null or to_regprocedure('public.pirate_capital()') is null
     or to_regprocedure('public.pirate_hoard()') is null or to_regprocedure('public.pirate_size()') is null or to_regprocedure('public.pirate_home_of(integer)') is null
     or to_regprocedure('public.pirate_spend_room(timestamp with time zone)') is null
     or to_regprocedure('public.pirate_pay(text, bigint, timestamp with time zone, uuid, uuid)') is null
     or to_regprocedure('public.npc_found(jsonb)') is null or to_regprocedure('public.npc_known_legs(uuid)') is null
     or to_regprocedure('public.npc_leg_days(numeric, numeric)') is null or to_regprocedure('public.npc_traders_on()') is null
     or to_regclass('public.pirate_spend_day') is null or to_regclass('public.npc_houses') is null or to_regclass('public.trade_daily') is null
     or not exists (select 1 from public.world_config where key in ('pirates_bite', 'navy_upkeep_day', 'npc_fleet_max', 'skill_study_base_cost'))
     or not exists (select 1 from public.nations n where n.code = 'PIR' and n.capital_port_code = 'POR' and public.pirate_power(n.id))
     or not exists (select 1 from public.skills s where s.code = 'HAGGLING')
     or not exists (select 1 from public.ship_classes c join public.npc_loadouts l on l.class_code = c.code where c.code = 'carlat') then
    raise exception '0341 refuses: a function, table, knob, nation, skill or class this file reads is not in this world (0338 the Brethren, 0339 the pirate ships, 0097 the merchants, 0120 the planner, 0318 the day cap)';
  end if;
  if (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = 'public.npc_houses'::regclass and c.conname = 'npc_houses_ink_check')
     <> $c$CHECK ((ink = ANY (ARRAY['prt'::text, 'esp'::text, 'nld'::text, 'eng'::text, 'han'::text, 'ita'::text, 'ott'::text, 'east'::text])))$c$ then
    raise exception '0341 refuses: npc_houses.ink is not checked against the eight inks this file was cut against';
  end if;
  select n.id into v_pir from public.nations n where n.code = 'PIR';

  -- ── 1. THE PRE-IMAGES ──
  v_entry := (select count(*) from public.client_rpc_entry_points());   -- no new door: every new function is server-only (the job runs under cron)
  v_words := (select count(*) from public.stats_flow_words);
  create temp table defs_0341 on commit drop as
  select f.fn, f.ord, p.oid,
         replace(pg_get_functiondef(p.oid), E'\r', '') as def,
         coalesce(p.proacl::text, '') as acl, p.provolatile as vol, p.prosecdef as secdef,
         coalesce(p.proconfig::text, '') as cfg, p.proparallel as par, p.proowner as owner, l.lanname as lang
    from (values
      ('public.founding_credit(uuid, text, bigint, uuid)', 1),
      ('public.capital_gift_roster(timestamp with time zone, uuid)', 2),
      ('public.npc_invest_roster(uuid)', 3),
      ('public.insure_voyage(uuid, boolean)', 4),
      ('public.npc_loop_candidates(uuid, uuid, uuid, numeric, numeric)', 5),
      ('world.daily_cap_remaining(uuid, uuid, uuid)', 6)) f(fn, ord)
    join pg_proc p on p.oid = to_regprocedure(f.fn)
    join pg_language l on l.oid = p.prolang;
  if (select count(*) from defs_0341) <> 6 then
    raise exception '0341 self-assert FAIL: % of the 6 bodies this file re-cuts are in this world', (select count(*) from defs_0341);
  end if;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> all (select t.oid from defs_0341 t);
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before
    from public.world_config c;
  create temp table xact0_0341 on commit drop as
  select s.relname::text as relname, s.n_tup_ins, s.n_tup_upd, s.n_tup_del from pg_stat_xact_user_tables s;
  v_ms := v_ms || jsonb_build_object('pre', round(extract(epoch from clock_timestamp() - v_t0) * 1000));

  -- ── 2. THE KNOBS, THE WORD, THE INK ──
  insert into public.world_config (key, value, description) values
    ('pirate_merchants_max', '30'::jsonb, '0341 (W18, docs/WORLD_POWERS.md 7.4): the most merchant houses of the pirates that may exist. public.pirate_found founds none beyond it. Owner only.'),
    ('pirate_merchant_capital', '250000'::jsonb, '0341 (W18): the capital a pirate merchant is founded with, in ducats, paid from the hoard through public.pirate_pay (PIRATE_FOUND) inside pirate_spend_room. Her founding costs this plus her tuition (Haggling 1). Owner only.'),
    ('pirate_merchant_class', '"carlat"'::jsonb, '0341 (W18): ship_classes.code of the hull a pirate merchant is founded with: the lateen caravel of the Barbary corsairs. It must be a hull a merchant loadout is authored for (public.npc_loadouts: barca, carlat, nau), else public.npc_found refuses E_NO_LOADOUT and nothing is founded. No PIR line, so public.npc_hull_for lays this class itself. Owner only.'),
    ('pirate_found_hours', '2'::jsonb, '0341 (W18): hours between two foundings of pirate merchants (one a run of byeharu-voyage:pirate-merchants at most, and none inside this many hours of the newest). Owner only.'),
    ('pirate_port_day_cap', '0.05'::jsonb, '0341 (W18, docs/WORLD_POWERS.md 7.6): at a pirate home, while the pirates bite, the share of a good''s most stock (twice its target, 0339''s stow ceiling) one company may trade there in a day (world.daily_cap_remaining). Owner only.');
  insert into public.stats_flow_words (kind, side, word, ord)
  select 'PIRATE_FOUND', 'moved', 'Pirate founding', coalesce(max(w.ord), 0) + 1 from public.stats_flow_words w;
  alter table public.npc_houses drop constraint npc_houses_ink_check;
  alter table public.npc_houses add constraint npc_houses_ink_check check (ink = any (array['prt', 'esp', 'nld', 'eng', 'han', 'ita', 'ott', 'east', 'pir']));
  comment on constraint npc_houses_ink_check on public.npc_houses is '0098: the eight nation ink families a merchant hull is drawn in. 0341 (W18): and ''pir'', the Brethren''s own (the chart draws it as the pirate merchant look).';
  v_ms := v_ms || jsonb_build_object('data', round(extract(epoch from clock_timestamp() - v_t0) * 1000));

  -- ── 3. THE READERS AND THE FOUNDING ──
  execute $f$
create function public.pirate_home(p_port uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0341 (W18): THE one reader of "this harbour is a PIRATE HOME" (public.port_allegiance.home under the pirate power, 0338's data; public.port_is_free is this AND the lever pirate_ports_free). Plunder lands in a home's
  -- stock (0339's pirate_stow), so the planner's rule and the day cap of docs/WORLD_POWERS.md 7.6 read this, not the lever. A city the pirates WIN is not a home.
  select exists (select 1 from public.port_allegiance a join public.great_powers g on g.nation_id = a.nation_id where a.port_id = p_port and a.home and g.pirate)
$body$
  $f$;
  revoke all on function public.pirate_home(uuid) from public, anon, authenticated;
  comment on function public.pirate_home(uuid) is '0341 (W18): THE one reader of whether a harbour is a pirate home (plunder lands there). Server-only.';

  execute $f$
create function public.pirate_merchant(p_player uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0341 (W18): THE one reader of "this house is a MERCHANT OF THE PIRATES": a merchant house (public.npc_houses) whose company sails for the pirate power. A pirate SHIP's house (0339) has no npc_houses row and is
  -- not one; a company (a player) sailing for the pirates is not one. Read by public.insure_voyage (nobody insures her) and by the proofs.
  select exists (select 1 from public.npc_houses h join public.players pl on pl.id = h.player_id
                  where h.player_id = p_player and pl.is_npc and public.pirate_power(pl.nation_id))
$body$
  $f$;
  revoke all on function public.pirate_merchant(uuid) from public, anon, authenticated;
  comment on function public.pirate_merchant(uuid) is '0341 (W18): THE one reader of whether a house is a merchant of the pirates. Server-only.';

  execute $f$
create function public.npc_legs_open(p_legs jsonb, p_home uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0341 (W18, docs/WORLD_POWERS.md 7.6 "Merchants: cannot buy there: their route planner skips PIR ports unless she is PIR"): THE one rule, read by public.npc_loop_candidates on every set of feasible legs it
  -- builds. Dark: the legs, byte for byte. Lit: a PIRATE HOME is no destination, unless it is p_home (the merchant's own home: her way back). The only pirate home a pirate merchant's loop ever holds is her own,
  -- because no course joins two homes (public.npc_courses, 0338), so "unless she is PIR" and "except her own home" are one rule, and the cheaper one is kept: no read of the merchant, one read of the homes a call.
  select case when not public.pirates_on() then p_legs
              else coalesce((select jsonb_agg(t.x order by t.o)
                               from jsonb_array_elements(p_legs) with ordinality t(x, o)
                              where (t.x->>'port_id')::uuid = p_home
                                 or (t.x->>'port_id')::uuid not in (select a.port_id from public.port_allegiance a join public.great_powers g on g.nation_id = a.nation_id where a.home and g.pirate)),
                            '[]'::jsonb) end
$body$
  $f$;
  revoke all on function public.npc_legs_open(jsonb, uuid) from public, anon, authenticated;
  comment on function public.npc_legs_open(jsonb, uuid) is '0341 (W18): THE planner''s rule about pirate homes: dark, the legs unchanged; lit, a pirate home is no destination unless it is the merchant''s own home. Server-only.';

  execute $f$
create function public.pirate_merchant_spec(p_slot integer)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0341 (W18): THE founding spec of the pirate merchant of slot p_slot (the count of pirate merchants + 1), in the shape public.npc_found takes (0097, 0098's literal): company and alt_company, nation PIR,
-- ink 'pir', master, blurb, capital (pirate_merchant_capital), patience 0.30, wares none (the planner's "every good"), skills Haggling 1, roster_ord (the next free), ONE fleet of ONE hull
-- (pirate_merchant_class) at her home, no officer, stores for her first leg, and her first loop: out and back to the nearest known harbour of her home (public.npc_known_legs both ways; public.npc_plan
-- re-plans her at her first lap as it does every merchant's). HER HOME: the ring of 0339's one reader public.pirate_home_of(ord) (the capital for slot 1, then the other homes by code, wrapping), the first
-- from her slot's place with a known leg out; null when no home has a leg (said in the job's receipt). THE NAMES: thirty houses of the era's pirate coasts (the Caribbean, the Barbary coast, the wokou of
-- Kyushu, the lanun of the Strait), one a slot; past thirty the slot is appended. A plain read: nothing is written here.
declare
  v_class   text := public.wc_text('pirate_merchant_class');
  v_capital bigint := public.wc_int('pirate_merchant_capital');
  v_n       int;
  v_k       int;
  v_home    record;
  v_leg     record;
  v_back    jsonb;
  v_speed   numeric;
  v_name    text;
  v_master  text;
  v_ord     int;
  v_ford    int;
begin
  if p_slot is null or p_slot < 1 then
    return null;
  end if;
  select count(*) into v_n from public.ports p where p.kind = 'HARBOUR' and public.pirate_home(p.id);
  if v_n = 0 then
    return null;
  end if;
  select c.speed_kn into v_speed from public.ship_classes c where c.code = v_class;
  if v_speed is null then
    raise exception 'pirate_merchant_spec: pirate_merchant_class % is no ship class', v_class;
  end if;
  -- her home: the ring from her slot's place, the first with a known leg out, both ways
  for v_k in 0 .. v_n - 1 loop
    select p.id, p.code into v_home from public.ports p where p.id = public.pirate_home_of(p_slot + v_k);
    select l.to_port, l.code, l.course, l.nm into v_leg
      from public.npc_known_legs(v_home.id) l
      join public.ports p on p.id = l.to_port
     where p.kind = 'HARBOUR' and not p.is_ice_closed
       and exists (select 1 from public.npc_known_legs(l.to_port) b where b.to_port = v_home.id)
     order by l.nm, l.to_port
     limit 1;
    exit when v_leg.to_port is not null;
  end loop;
  if v_leg.to_port is null then
    return null;
  end if;
  select b.course into v_back from public.npc_known_legs(v_leg.to_port) b where b.to_port = v_home.id;
  select v.company, v.master into v_name, v_master
    from (values
      (1, 'Brethren of the Coast', 'Captain Pierre le Grand'),
      (2, 'Reis of Djerba', 'Turgut Reis'),
      (3, 'Goto Wako', 'Wang Zhi'),
      (4, 'Lingga Lanun', 'Raja Laut'),
      (5, 'Tortuga Freebooters', 'Captain Jean Fleury'),
      (6, 'Corsairs of Tunis', 'Uluj Ali Reis'),
      (7, 'Hirado Wako', 'Xu Hai'),
      (8, 'Riau Lanun', 'Panglima Raman'),
      (9, 'Windward Rovers', 'Captain Francois le Clerc'),
      (10, 'Barbary Rovers', 'Murat Reis'),
      (11, 'Kyushu Wako', 'Lin Feng'),
      (12, 'Bintan Lanun', 'Raja Hitam'),
      (13, 'Spanish Main Rovers', 'Captain Jacques de Sores'),
      (14, 'Rovers of Sale', 'Jan Janszoon Reis'),
      (15, 'Nagasaki Wako', 'Wu Ping'),
      (16, 'Singapura Lanun', 'Datuk Laut'),
      (17, 'Leeward Freebooters', 'Captain Pierre Belain'),
      (18, 'Dragut Corsairs', 'Dragut Reis'),
      (19, 'Tsushima Wako', 'Chen Dong'),
      (20, 'Johor Lanun', 'Orang Kaya Laut'),
      (21, 'Cayman Brethren', 'Captain Diego de los Reyes'),
      (22, 'Bizerte Corsairs', 'Ali Bitchin Reis'),
      (23, 'Matsura Wako', 'Ye Ma'),
      (24, 'Lingga Sea Rovers', 'Nakhoda Ragam'),
      (25, 'Jamaica Brethren', 'Captain Rok Brasiliano'),
      (26, 'Tripoli Corsairs', 'Hamza Reis'),
      (27, 'Fukue Wako', 'Deng Wenjun'),
      (28, 'Malacca Lanun', 'Panglima Hitam'),
      (29, 'Brethren of Tortuga', 'Captain Jean-David Nau'),
      (30, 'Corsairs of Algiers', 'Hayreddin Reis')) v(slot, company, master)
   where v.slot = 1 + ((p_slot - 1) % 30);
  if p_slot > 30 then
    v_name := v_name || ' ' || p_slot;
  end if;
  select coalesce(max(h.roster_ord), 0) + 1 into v_ord from public.npc_houses h;
  select coalesce(max(f.roster_ord), 0) + 1 into v_ford from public.npc_fleets f;
  return jsonb_build_object(
    'company', v_name, 'alt_company', v_name || ' II', 'nation', 'PIR', 'ink', 'pir', 'master', v_master,
    'blurb', format('A merchant of the Brethren out of %s, fencing what the sea gives.', (select p.name from public.ports p where p.id = v_home.id)),
    'capital', v_capital, 'patience', 0.30, 'wares', '[]'::jsonb, 'skills', jsonb_build_object('HAGGLING', 1),
    'roster_ord', greatest(v_ord, v_ford), 'slot', p_slot, 'home', v_home.code,
    'fleets', jsonb_build_array(jsonb_build_object(
      'name', left(v_name, 24), 'roster_ord', greatest(v_ord, v_ford), 'home', v_home.code,
      'days', greatest(2, public.npc_leg_days(v_leg.nm, v_speed)),
      'ships', jsonb_build_array(jsonb_build_object('class', v_class, 'name', left(v_name, 24))),
      'officers', '[]'::jsonb,
      'stops', jsonb_build_array(jsonb_build_object('port', v_home.code, 'course', v_leg.course),
                                 jsonb_build_object('port', v_leg.code, 'course', v_back)))));   -- no alt_stops key: npc_fleets.alt_loop stays SQL null (its check wants null or an array)
end $body$
  $f$;
  revoke all on function public.pirate_merchant_spec(integer) from public, anon, authenticated;
  comment on function public.pirate_merchant_spec(integer) is '0341 (W18): the founding spec (public.npc_found''s shape) of the pirate merchant of a slot: name, home in the ring of homes, the Brethren''s hull, her first out-and-back loop. A read. Server-only.';

  execute $f$
create function public.pirate_found(p_now timestamp with time zone)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $body$
-- 0341 (W18, docs/WORLD_POWERS.md 7.4): AT MOST ONE PIRATE MERCHANT IS FOUNDED, from the hoard, through public.npc_found (the one way a merchant is made) whose starting money public.founding_credit takes from
-- public.pirate_pay (THE one payer, inside THE one cap public.pirate_spend_room) as PIRATE_FOUND. The gates, in order, each a reason in the answer: dark (public.pirates_on() false, or the merchants dark);
-- full (pirate_merchants_max); paced (the newest founded inside pirate_found_hours); no berth (public.npc_fleets at npc_fleet_max: she would lie paused 'dark', 0105); no home with a known leg; the room
-- (pirate_spend_room under her capital PLUS what the ships are owed for the rest of the UTC day, pirate_size x navy_upkeep_day pro rata: a founding never starves 0339's hourly pay); then the founding, in a
-- sub-transaction of its own: a founding pirate_pay refuses (E_HOARD_SHORT, the exact amount judged there), a name taken, a route refused, roll back WHOLE and are said, never raised. Answers
-- {founded: her house or null, why, slot, company, home}.
declare
  v_pir     uuid := public.pirate_nation();
  v_n       int;
  v_last    timestamptz;
  v_spec    jsonb;
  v_player  uuid;
  v_reserve bigint;
  v_room    bigint;
begin
  if v_pir is null or not public.pirates_on() or not public.npc_traders_on() then
    return jsonb_build_object('founded', null, 'why', 'dark');
  end if;
  select count(*), max(h.created_at) into v_n, v_last
    from public.npc_houses h join public.players pl on pl.id = h.player_id
   where pl.nation_id = v_pir;
  if v_n >= public.wc_int('pirate_merchants_max') then
    return jsonb_build_object('founded', null, 'why', 'full', 'merchants', v_n);
  end if;
  if v_last is not null and v_last > p_now - make_interval(mins => round(public.wc_num('pirate_found_hours') * 60)::int) then
    return jsonb_build_object('founded', null, 'why', 'paced', 'merchants', v_n, 'newest', v_last);
  end if;
  if (select count(*) from public.npc_fleets) >= public.wc_int('npc_fleet_max') then
    return jsonb_build_object('founded', null, 'why', 'no_berth', 'merchants', v_n);
  end if;
  v_spec := public.pirate_merchant_spec(v_n + 1);
  if v_spec is null then
    return jsonb_build_object('founded', null, 'why', 'no_leg', 'merchants', v_n);
  end if;
  v_reserve := ceil(public.pirate_size() * public.wc_int('navy_upkeep_day')
                    * extract(epoch from (date_trunc('day', p_now at time zone 'UTC') + interval '1 day' - (p_now at time zone 'UTC'))) / 86400)::bigint;
  v_room := public.pirate_spend_room(p_now);
  if v_room < (v_spec->>'capital')::bigint + v_reserve then
    return jsonb_build_object('founded', null, 'why', 'room', 'merchants', v_n, 'room', v_room, 'reserve', v_reserve, 'capital', (v_spec->>'capital')::bigint);
  end if;
  begin
    v_player := public.npc_found(v_spec);
  exception when others then
    return jsonb_build_object('founded', null, 'why', 'refused', 'merchants', v_n, 'slot', v_spec->>'slot', 'company', v_spec->>'company', 'home', v_spec->>'home', 'error', sqlerrm);
  end;
  return jsonb_build_object('founded', v_player, 'why', 'founded', 'merchants', v_n + 1, 'slot', v_spec->>'slot', 'company', v_spec->>'company', 'home', v_spec->>'home');
end $body$
  $f$;
  revoke all on function public.pirate_found(timestamp with time zone) from public, anon, authenticated;
  comment on function public.pirate_found(timestamp with time zone) is '0341 (W18): at most one pirate merchant founded from the hoard (public.npc_found; the money through public.pirate_pay inside public.pirate_spend_room), with its gates said in the answer. Server-only.';

  execute $f$
create function public.tick_pirate_merchants(p_now timestamp with time zone default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $body$
-- 0341 (W18): THE JOB of the pirate merchants: pg_cron byeharu-voyage:pirate-merchants, every ten minutes, never in the beat. Dark: one knob read and nothing else. Lit: at most one founding (public.pirate_found).
-- Everything after a founding is the merchants' own machinery (public.npc_tend, hourly; the arrivals sweep): nothing of it lives here.
begin
  if not public.pirates_on() then
    return jsonb_build_object('enabled', false, 'at', p_now);
  end if;
  return jsonb_build_object('enabled', true, 'at', p_now) || public.pirate_found(p_now);
end $body$
  $f$;
  revoke all on function public.tick_pirate_merchants(timestamp with time zone) from public, anon, authenticated;
  comment on function public.tick_pirate_merchants(timestamp with time zone) is '0341 (W18): the pirate merchants'' job (cron, every ten minutes): dark nothing; lit at most one founding a run. Server-only.';
  v_ms := v_ms || jsonb_build_object('fns', round(extract(epoch from clock_timestamp() - v_t0) * 1000));

  -- ── 4. THE RE-CUTS: hunks sliced from the live bodies ──
  create temp table hunks_0341 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0341 values
  ('public.founding_credit(uuid, text, bigint, uuid)', 1,
$h$begin
  if not public.economy_closed() or not public.city_treasury_on() or coalesce(p_delta, 0) <= 0 then
$h$,
$h$begin
  -- 0341 (W18): A MERCHANT OF THE PIRATES is founded from the hoard through THE one payer, public.pirate_pay, inside THE one cap public.pirate_spend_room (docs/WORLD_POWERS.md 7.4), as PIRATE_FOUND,
  -- whatever the economy's state (a dark hoard pays nothing, so no pirate merchant is ever minted). 0 means the hoard cannot pay her now: the founding is refused WHOLE (E_HOARD_SHORT), so nothing of
  -- her stays written. A company (a player) sailing for the pirates is paid as every founding is, below.
  if coalesce(p_delta, 0) > 0 and exists (select 1 from public.players pl where pl.id = p_player and pl.is_npc and public.pirate_power(pl.nation_id)) then
    if public.pirate_pay('PIRATE_FOUND', p_delta, now(), p_player := p_player) < p_delta then
      raise exception 'E_HOARD_SHORT: the Brethren cannot pay % d. for a founding today', p_delta using errcode = 'P0001';
    end if;
    return (select pl.ducats from public.players pl where pl.id = p_player);
  end if;
  if not public.economy_closed() or not public.city_treasury_on() or coalesce(p_delta, 0) <= 0 then
$h$),
  ('public.capital_gift_roster(timestamp with time zone, uuid)', 1,
$h$     where (p_only is null or h.player_id = p_only)
       and pl.ducats < h.capital * v_pct               -- 0236: BROKE = her purse (cash) under the line; cargo aboard does not count
$h$,
$h$     where (p_only is null or h.player_id = p_only)
       and (h.human or not public.pirate_power(pl.nation_id))   -- 0341 (W18): a merchant of the pirates is never gifted: the hoard pays her founding and nothing after (docs/WORLD_POWERS.md 7.4, decided by default)
       and pl.ducats < h.capital * v_pct               -- 0236: BROKE = her purse (cash) under the line; cargo aboard does not count
$h$),
  ('public.npc_invest_roster(uuid)', 1,
$h$             where pl.ducats > h.capital * (select public.wc_num('npc_invest_above'))   -- 0313: read once, not once a row
$h$,
$h$             where pl.ducats > h.capital * (select public.wc_num('npc_invest_above'))   -- 0313: read once, not once a row
               and (pl.nation_id is distinct from (select public.pirate_nation()) or (select public.pirates_on()))   -- 0341 (W18): a merchant of the pirates invests and gives only while the pirates bite (both read once a query)
$h$),
  ('public.insure_voyage(uuid, boolean)', 1,
$h$  select f.name into v_fleet from public.fleets f where f.id = v.fleet_id;
  if po.id is null or po.kind <> 'HARBOUR' then
$h$,
$h$  select f.name into v_fleet from public.fleets f where f.id = v.fleet_id;
  if pl.is_npc and public.pirate_merchant(pl.id) then   -- 0341 (W18): NOBODY INSURES A MERCHANT OF THE PIRATES: no city takes her premium, so no city pays for her cargo (docs/WORLD_POWERS.md 7.4, decided by default)
    return jsonb_build_object('insured', false, 'why', 'pirate', 'value', 0, 'price', 0);
  end if;
  if po.id is null or po.kind <> 'HARBOUR' then
$h$),
  ('public.npc_loop_candidates(uuid, uuid, uuid, numeric, numeric)', 1,
$h$  v_legs := public.npc_feasible_legs(p_home, p_speed, v_days_cap);
$h$,
$h$  v_legs := public.npc_legs_open(public.npc_feasible_legs(p_home, p_speed, v_days_cap), p_home);   -- 0341 (W18): while the pirates bite a pirate home is no destination, unless it is hers (docs/WORLD_POWERS.md 7.6)
$h$),
  ('public.npc_loop_candidates(uuid, uuid, uuid, numeric, numeric)', 2,
$h$      v_cache := v_cache || jsonb_build_object(b->>'port_id',
                   public.npc_feasible_legs((b->>'port_id')::uuid, p_speed, v_days_cap));
$h$,
$h$      v_cache := v_cache || jsonb_build_object(b->>'port_id',
                   public.npc_legs_open(public.npc_feasible_legs((b->>'port_id')::uuid, p_speed, v_days_cap), p_home));   -- 0341 (W18): the same rule on every leg set
$h$),
  ('public.npc_loop_candidates(uuid, uuid, uuid, numeric, numeric)', 3,
$h$      v_cache := v_cache || jsonb_build_object(t->>'d', public.npc_feasible_legs((t->>'d')::uuid, p_speed, v_days_cap));
$h$,
$h$      v_cache := v_cache || jsonb_build_object(t->>'d', public.npc_legs_open(public.npc_feasible_legs((t->>'d')::uuid, p_speed, v_days_cap), p_home));   -- 0341 (W18): the same rule on every leg set
$h$),
  ('world.daily_cap_remaining(uuid, uuid, uuid)', 1,
$h$  select greatest(0,
           public.daily_cap_base(p_player, p_port) * pg.stock_target   -- 0318
$h$,
$h$  select greatest(0,
           case when public.pirates_on() and public.pirate_home(p_port)   -- 0341 (W18, docs/WORLD_POWERS.md 7.6): at a pirate home, while the pirates bite, a company trades a good up to pirate_port_day_cap x its most stock (twice the target: 0339's stow ceiling) a day
                then least(public.daily_cap_base(p_player, p_port) * pg.stock_target, public.wc_num('pirate_port_day_cap') * 2 * pg.stock_target)
                else public.daily_cap_base(p_player, p_port) * pg.stock_target end   -- 0318
$h$);

  -- every hunk is checked against its live body BEFORE anything is replaced; then the bodies are replaced
  if (select count(distinct h.fn) from hunks_0341 h) <> (select count(*) from defs_0341)
     or exists (select 1 from hunks_0341 h where h.fn not in (select t.fn from defs_0341 t)) then
    raise exception '0341 self-assert FAIL: a pre-imaged body has no hunk, or a hunk names a body not pre-imaged';
  end if;
  for r_d in select * from defs_0341 t order by t.ord loop
    v_def := r_d.def;
    for r_hk in select * from hunks_0341 h where h.fn = r_d.fn order by h.ord loop
      v_n := (length(v_def) - length(replace(v_def, r_hk.old, ''))) / length(r_hk.old);
      if v_n <> 1 then
        raise exception '0341 self-assert FAIL: hunk % of % occurs % time(s), not once: the live body is not what this file was cut against', r_hk.ord, r_hk.fn, v_n;
      end if;
      v_def := replace(v_def, r_hk.old, r_hk.new);
    end loop;
    execute v_def;
  end loop;
  v_ms := v_ms || jsonb_build_object('recut', round(extract(epoch from clock_timestamp() - v_t0) * 1000));

  -- ── 5. THE JOB: scheduled where cron exists (prod); the local chain has no cron and runs the job from the proofs ──
  if to_regclass('cron.job') is not null then
    execute $q$select cron.schedule('byeharu-voyage:pirate-merchants', '*/10 * * * *', 'select public.tick_pirate_merchants()')$q$;
  end if;

  -- ── 6. THE SELF-ASSERT: the catalog, then cheap pure reads, then probes that roll back ──
  -- 6a every re-cut reverses to its pre-image; attributes unmoved
  for r_d in select * from defs_0341 t order by t.ord loop
    v_rev := replace(pg_get_functiondef(r_d.oid), E'\r', '');
    for r_hk in select * from hunks_0341 h where h.fn = r_d.fn order by h.ord desc loop
      v_n := (length(v_rev) - length(replace(v_rev, r_hk.new, ''))) / length(r_hk.new);
      if v_n <> 1 then
        raise exception '0341 self-assert FAIL: % - the new text of hunk % is not in the live body exactly once', r_d.fn, r_hk.ord;
      end if;
      v_rev := replace(v_rev, r_hk.new, r_hk.old);
    end loop;
    if v_rev <> r_d.def then
      raise exception '0341 self-assert FAIL: % does not reverse to its pre-image', r_d.fn;
    end if;
    if (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = r_d.oid) <> r_d.acl
       or (select p.provolatile from pg_proc p where p.oid = r_d.oid) <> r_d.vol
       or (select p.prosecdef from pg_proc p where p.oid = r_d.oid) <> r_d.secdef
       or (select coalesce(p.proconfig::text, '') from pg_proc p where p.oid = r_d.oid) <> r_d.cfg
       or (select p.proparallel from pg_proc p where p.oid = r_d.oid) <> r_d.par
       or (select p.proowner from pg_proc p where p.oid = r_d.oid) <> r_d.owner
       or (select l.lanname from pg_proc p join pg_language l on l.oid = p.prolang where p.oid = r_d.oid) <> r_d.lang then
      raise exception '0341 self-assert FAIL: % - ACL, volatility, definer, config, parallel safety, owner or language moved', r_d.fn;
    end if;
  end loop;

  -- 6b no other function moved; the six new ones are server-only, definer, pinned, of the declared volatility; only the five knobs were added, as shipped; the one word; the ink
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and p.oid <> all (select t.oid from defs_0341 t)
         and not (n.nspname = 'public' and p.proname = any (c_fns))) is distinct from v_fn_before then
    raise exception '0341 self-assert FAIL: a function this file does not re-cut moved';
  end if;
  for r_x in select p.proname, p.provolatile, p.prosecdef, coalesce(p.proconfig::text, '') as cfg, p.oid
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname = any (c_fns) loop
    if r_x.provolatile <> (case when r_x.proname in ('pirate_found', 'tick_pirate_merchants') then 'v' else 's' end)
       or not r_x.prosecdef or r_x.cfg <> '{"search_path=public, pg_temp"}'
       or has_function_privilege('anon', r_x.oid, 'execute') or has_function_privilege('authenticated', r_x.oid, 'execute')
       or exists (select 1 from aclexplode(coalesce((select p.proacl from pg_proc p where p.oid = r_x.oid), acldefault('f', (select p.proowner from pg_proc p where p.oid = r_x.oid)))) a where a.grantee = 0) then
      raise exception '0341 self-assert FAIL: public.% is not of its declared volatility, definer, search_path-pinned and server-only', r_x.proname;
    end if;
  end loop;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = any (c_fns)) <> 6 then
    raise exception '0341 self-assert FAIL: the six new functions are not exactly six';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key <> all (c_knobs)) is distinct from v_cfg_before
     or (select md5(string_agg(c.key || ':' || c.value::text, ',' order by c.key)) from public.world_config c where c.key = any (c_knobs))
        is distinct from md5('pirate_found_hours:2,pirate_merchant_capital:250000,pirate_merchant_class:"carlat",pirate_merchants_max:30,pirate_port_day_cap:0.05') then
    raise exception '0341 self-assert FAIL: a knob moved, or the knobs are not shipped as planned (max 30, capital 250000, class carlat, hours 2, day cap 0.05)';
  end if;
  if (select count(*) from public.stats_flow_words) <> v_words + 1
     or not exists (select 1 from public.stats_flow_words w where w.kind = 'PIRATE_FOUND' and w.side = 'moved' and w.word = 'Pirate founding'
                      and w.ord = (select max(x.ord) from public.stats_flow_words x)) then
    raise exception '0341 self-assert FAIL: the word PIRATE_FOUND is not one moved word at the end of the list';
  end if;
  if (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = 'public.npc_houses'::regclass and c.conname = 'npc_houses_ink_check')
     <> $c$CHECK ((ink = ANY (ARRAY['prt'::text, 'esp'::text, 'nld'::text, 'eng'::text, 'han'::text, 'ita'::text, 'ott'::text, 'east'::text, 'pir'::text])))$c$ then
    raise exception '0341 self-assert FAIL: npc_houses.ink is not checked against the eight inks and ''pir''';
  end if;

  -- the posture (supabase/migrations/README.md section 3): no new door for a client, and both halves of the wall read zero
  if (select count(*) from public.client_rpc_entry_points()) <> v_entry
     or (select count(*) from public.client_write_grants()) <> 0
     or (select count(*) from public.client_executable_writers()) <> 0
     or (select count(*) from public.caller_evaluated_functions()) <> 0 then
    raise exception '0341 self-assert FAIL: the registry or a wall moved (no new door; the posture must read zero)';
  end if;
  if to_regclass('cron.job') is not null then
    execute $q$select count(*) from cron.job j where j.jobname = 'byeharu-voyage:pirate-merchants' and j.schedule = '*/10 * * * *' and j.command = 'select public.tick_pirate_merchants()' and j.active$q$ into v_n;
    if v_n <> 1 then
      raise exception '0341 self-assert FAIL: the cron job byeharu-voyage:pirate-merchants is not scheduled every ten minutes';
    end if;
  end if;

  -- 6c the readers on the world as it stands: the four homes and no other harbour; no house of the world is a pirate merchant; the switch is off, so the planner's rule is the identity and the day cap is the base
  if (select count(*) from public.ports p where p.kind = 'HARBOUR' and public.pirate_home(p.id)) <> 4
     or exists (select 1 from public.ports p where p.code = any (c_homes) and not public.pirate_home(p.id))
     or exists (select 1 from public.ports p where p.code in ('LIS', 'SVQ') and public.pirate_home(p.id)) then
    raise exception '0341 self-assert FAIL: pirate_home does not answer exactly the four homes';
  end if;
  if exists (select 1 from public.npc_houses h where public.pirate_merchant(h.player_id)) then
    raise exception '0341 self-assert FAIL: a house of this world already reads as a pirate merchant';
  end if;
  if public.pirates_on() then
    raise exception '0341 self-assert FAIL: pirates_bite is on while this file is applied (it is cut for a dark world; the owner lights the switch)';
  end if;
  select jsonb_build_array(jsonb_build_object('port_id', (select p.id from public.ports p where p.code = 'POR'), 'code', 'POR', 'nm', 10),
                           jsonb_build_object('port_id', (select p.id from public.ports p where p.code = 'LIS'), 'code', 'LIS', 'nm', 20),
                           jsonb_build_object('port_id', (select p.id from public.ports p where p.code = 'DJE'), 'code', 'DJE', 'nm', 30))
    into v_legs;
  if public.npc_legs_open(v_legs, (select p.id from public.ports p where p.code = 'LIS')) <> v_legs
     or public.npc_legs_open('[]'::jsonb, (select p.id from public.ports p where p.code = 'LIS')) <> '[]'::jsonb then
    raise exception '0341 self-assert FAIL: dark, npc_legs_open is not the identity';
  end if;
  select g.id into v_good from public.port_goods pg join public.goods g on g.id = pg.good_id join public.ports p on p.id = pg.port_id
   where p.code = 'POR' and pg.stock_target > 0 order by g.code limit 1;
  if v_good is null then
    raise exception '0341 self-assert FAIL: Port Royal has no market row with a target to read the day cap on';
  end if;
  v_base := world.daily_cap_remaining(v_probe, (select p.id from public.ports p where p.code = 'POR'), v_good);
  if v_base is distinct from (select greatest(0, public.daily_cap_base(v_probe, p.id) * pg.stock_target) from public.ports p join public.port_goods pg on pg.port_id = p.id and pg.good_id = v_good where p.code = 'POR') then
    raise exception '0341 self-assert FAIL: dark, the day cap at a pirate home is not the base (0318)';
  end if;
  v_cfg_probe := (select md5(string_agg(c.key || ':' || c.value::text, ',' order by c.key)) from public.world_config c);
  begin   -- the switch, lit INSIDE A PROBE THAT ROLLS BACK: a pirate home is stripped from a leg set and the own home kept; the day cap at a home is bounded by pirate_port_day_cap x twice the target
    -- 0339's pirates_on() is pirates_bite AND the city purses lit (on prod they are; a dark world lights them here, inside the probe, and the probe rolls both back)
    update public.world_config set value = 'true'::jsonb where key in ('pirates_bite', 'city_treasury_enabled');
    if not public.pirates_on() then
      raise exception '0341 self-assert FAIL: the probe lit pirates_bite and the purses, and pirates_on() still answers false';
    end if;
    v_open := public.npc_legs_open(v_legs, (select p.id from public.ports p where p.code = 'LIS'));
    if jsonb_array_length(v_open) <> 1 or v_open->0->>'code' <> 'LIS' then
      raise exception '0341 self-assert FAIL: lit, npc_legs_open kept % (two pirate homes should be stripped, LIS kept)', v_open;
    end if;
    v_open := public.npc_legs_open(v_legs, (select p.id from public.ports p where p.code = 'DJE'));
    if jsonb_array_length(v_open) <> 2 or v_open->0->>'code' <> 'LIS' or v_open->1->>'code' <> 'DJE' then
      raise exception '0341 self-assert FAIL: lit, npc_legs_open from Djerba kept % (Port Royal stripped, LIS and the own home kept, in order)', v_open;
    end if;
    v_cap := world.daily_cap_remaining(v_probe, (select p.id from public.ports p where p.code = 'POR'), v_good);
    if v_cap is distinct from (select greatest(0, least(public.daily_cap_base(v_probe, p.id) * pg.stock_target, 0.05 * 2 * pg.stock_target))
                                 from public.ports p join public.port_goods pg on pg.port_id = p.id and pg.good_id = v_good where p.code = 'POR')
       or v_cap > v_base then
      raise exception '0341 self-assert FAIL: lit, the day cap at Port Royal is % (base %), not the lesser of the base and 5 %% of twice the target', v_cap, v_base;
    end if;
    if world.daily_cap_remaining(v_probe, (select p.id from public.ports p where p.code = 'LIS'), v_good)
       is distinct from (select greatest(0, public.daily_cap_base(v_probe, p.id) * pg.stock_target) from public.ports p join public.port_goods pg on pg.port_id = p.id and pg.good_id = v_good where p.code = 'LIS') then
      raise exception '0341 self-assert FAIL: lit, the day cap at Lisbon moved';
    end if;
    raise exception 'PROBE_ROLLBACK_0341';
  exception when others then
    if sqlerrm <> 'PROBE_ROLLBACK_0341' then raise; end if;
  end;
  if public.pirates_on() or (select md5(string_agg(c.key || ':' || c.value::text, ',' order by c.key)) from public.world_config c) is distinct from v_cfg_probe then
    raise exception '0341 self-assert FAIL: the probe left pirates_bite on, or a knob changed';
  end if;

  -- 6d THE MONEY PROOF BY CONSTRUCTION: this transaction wrote no row to any table of money, houses, ships, books or events; the knobs are the positive control
  for r_x in select a.relname, a.n_tup_ins - coalesce(b.n_tup_ins, 0) as i, a.n_tup_upd - coalesce(b.n_tup_upd, 0) as u, a.n_tup_del - coalesce(b.n_tup_del, 0) as dl
             from pg_stat_xact_user_tables a left join xact0_0341 b on b.relname = a.relname
            where a.relname in ('players', 'npc_houses', 'npc_fleets', 'fleets', 'ships', 'treasury_flows', 'treasury_daybook', 'ledger', 'port_influence', 'events', 'trade_daily', 'insured_voyages', 'pirate_spend_day', 'standing_routes') loop
    if r_x.i <> 0 or r_x.u <> 0 or r_x.dl <> 0 then
      raise exception '0341 self-assert FAIL: this file wrote % row(s) to %, which it must never touch (ins %, upd %, del %)', r_x.i + r_x.u + r_x.dl, r_x.relname, r_x.i, r_x.u, r_x.dl;
    end if;
  end loop;
  select a.n_tup_ins - coalesce(b.n_tup_ins, 0) into v_n from pg_stat_xact_user_tables a left join xact0_0341 b on b.relname = a.relname where a.relname = 'world_config';
  select a.n_tup_ins - coalesce(b.n_tup_ins, 0) into v_x from pg_stat_xact_user_tables a left join xact0_0341 b on b.relname = a.relname where a.relname = 'stats_flow_words';
  if v_n <> 5 or v_x <> 1 then   -- the positive control: the counters DO see this block's writes (five knobs, one word)
    raise exception '0341 self-assert FAIL: the transaction counters saw % knobs and % words inserted, not 5 and 1 (the money proof would be vacuous)', v_n, v_x;
  end if;
  v_ms := v_ms || jsonb_build_object('assert', round(extract(epoch from clock_timestamp() - v_t0) * 1000));

  -- ── 7. RECEIPT ──
  raise notice '0341 NOTE: the live paths (a founding paid by Port Royal within the cap and refused whole without it; the pace, the max, the berth and the reserve for the ships; no gift and no insurer; her stake and gift for the pirates and the daily count flipping a city to the skull that keeps its tax; a crown merchant''s planner skipping a pirate home and hers keeping her way home; the day cap at a home; dark parity; W unchanged) are proved in CI by scripts/db/proofs/47_pirate_merchants.sql and locally by scripts/ops/harness/pirate-merchants/proof-0341.mjs, not in this block';
  raise notice '0341 timings ms (cumulative): %', v_ms;
  raise notice '0341 self-assert ok: PIRATE MERCHANTS - 6 bodies re-cut by 8 hunks (every hunk once, each reverses, attributes unmoved), no other function moved, 6 server-only functions, 5 knobs as shipped (max 30, capital 250000, class carlat, hours 2, day cap 0.05), the word PIRATE_FOUND moved, the ink pir, pirate_home exactly the 4 homes, no pirate merchant in the world, dark: the planner rule the identity and the day cap the base; lit (probe rolled back): a home stripped and the own home kept, the cap bounded; cron job scheduled where cron exists; no row written to players / houses / fleets / ships / flows / daybook / ledger / influence / events / trade_daily / insurance / spend book';
end
$m$;
