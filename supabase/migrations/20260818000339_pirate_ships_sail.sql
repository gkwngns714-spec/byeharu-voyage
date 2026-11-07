-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0339 — PIRATE SHIPS SAIL (W17): the Brethren's ships, built and paid from the hoard, cruising the seas round their homes; the frozen segment names the one that raids; plunder lands in her home's stock, a ransom in its purse. DARK
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER (docs/OWNER_REQUESTS.md row 284, 2026-11-05): "pirate headquarters with pirate cities, npcs that attack these ships as well as merchants"; "pirates are like countries - power, where they can also invest";
-- row 306 (2026-11-06): "use your recommended defaults for the rest"; 2026-11-07: "do it fast". The design is docs/WORLD_POWERS.md Part 5 (7.3 plunder really moves, 7.6 limits, 7.7 row W17, section 8 money kinds,
-- section 9 looks) on the base of docs/PIRATES_AND_HAVENS.md section 2.3 (position decides who raids). Step 2 of 4: W16 = 0338 (the nation, four free homes), THIS = W17, W18 = pirate merchants (0340), W19 = the navy hunts (0341).
-- THIS FILE IS W17 AND NOTHING ELSE: no pirate merchant and no investing, no navy hunting, no switch or knob flipped. The contract W18 and W19 build on is docs/dev-log/2026-11-07-pirate-ships-sail.md.
--
-- DARK: `pirates_bite` false, read by public.pirates_on() alone (which also needs the city purses lit, as public.navy_on does). Off: nothing is built or paid, a ship that exists sails home and is laid up, no departure's segment
-- names a raider (every raid is today's anonymous xebecs), nothing is stowed, no RANSOM moves, public.sea_pressure stays empty, the market regenerates as it does today. Every hunk below reads an empty table or a false
-- constant, so the sea reads BYTE-IDENTICAL: proved by scripts/ops/harness/pirate-ships-sail/dark-scene.sql before and after this file (the map's rows, a departure's frozen path, 960 raid days settled through the real
-- engine, the kinds, origins, wages and fees, the regen of a pirate home, the money figures), every line equal.
--
-- HOW A PIRATE SHIP EXISTS: as a navy ship (0331). A real fleets row with one hull of pirate_ship_class (`xebec`, the same hull fight_raider_class names, so a named raider and the anonymous raider are one hull), owned by a house
-- of her own (is_npc, nation PIR, purse 0), a row in public.pirate_ships, none in npc_houses or npc_fleets: never tended, invested, gifted or refunded (0308's table). The voyage engine takes her with no fork. Hands from the
-- quay and free stores at each departure (public.fleet_hands, public.fleet_stores), no wage, no dock fee (public.crown_house answers true for her house). Her kind is PIRATE (public.fleet_kind), her origin her home
-- (public.fleet_origin), so 0322's wreck and refit take her unchanged: REFIT from her home's purse, or patched free while the rule is dark.
-- SIZE: public.pirate_size_for(hoard) = least(pirate_max 30, pirate_min 4 + floor(hoard / pirate_hoard_unit 100 M)). The hoard is public.pirate_hoard(): Σ purses of the cities the Brethren hold (public.realm_purse, one copy).
-- THE HOARD PAYS, ONE WAY: public.pirate_pay. Whole or nothing: it refuses when the day's room (public.pirate_spend_room: pirate_spend_day_pct 0.5 % of the hoard a UTC day, less what was spent, public.pirate_spend_day) is short,
--   when the capital's surplus is short, or when the capital is busy. A hoard at 0 has no room and builds none. BUILD_NAVY the class's cost, capital to the nearest yard by sea (public.refit_yard; a pirate home has none);
--   NAVY_PAY navy_upkeep_day / 24 a ship an hour, capital to the harbour she lies at; paying herself at the capital moves nothing. Never a debt, never minted. W18's founding goes through the same payer (p_player).
-- THE CRUISE (public.pirate_ship_step): from her home she sails one stored merchant course (public.npc_courses, the way back required) to a HAUNT within navy_reach_nm, the harbour whose sea is the most dangerous as
--   authored (voyage.sea_danger at no moment), spread by ord; her `sea_id` is that sea WHILE SHE CRUISES OUT AND LIES AT HER HAUNT: THE POSITION FOR "WHO RAIDS" (public.pirate_ships_cruising, the one rule: at work, sea_id set,
--   free to fight, a hull left). On the home leg she is in no sea: she names nobody, adds no pressure, and W19's hunt cannot find her. In any port that is not her haunt (her home, a wreck's respawn, a stranding) the step clears
--   her position. At the haunt she lies pirate_haunt_hours, then sails home, is mended free, delivers nothing (below), and sails again. Off duty (switch off, unpaid, ord above the size) she sails straight home and is laid up: one path for all three.
-- POSITION DECIDES WHO RAIDS (docs/PIRATES_AND_HAVENS.md 2.3): voyage.depart freezes, beside each segment's danger, the pirate ship cruising that sea, if any (voyage.freeze_raiders, through public.pirate_ship_in_sea; a pirate
--   ship's own voyage is never given one). voyage.settle's PIRATES arm reads it (voyage.leg_raider): a named raider's strength is HER OWN hulls' figure (voyage.pirate_strength: attack / 10 + crew x 0.02 + tier x 3 a hull, by the
--   hull left), so the one fight engine builds her as hulls of fight_raider_class and no second path exists; an anonymous day is today's figure, to the digit. A voyage frozen lit and settled dark fights what it departed into
--   (DESIGN D.2), as W14 decided.
-- A PIRATE SHIP IN A SEA RAISES ITS DANGER: public.pirate_pressure_write, THE first and only writer of public.sea_pressure (0330): one row a sea with ships at work in it, pirate_pressure 0.5 a ship, refreshed each run so it
--   does not decay while she is there; a sea with none loses its row; off, the table empties. voyage.sea_danger reads it as 0330 wrote: more PIRATES days where she cruises (docs/WORLD_POWERS.md 7.6: "pressure +0.5").
-- PLUNDER REALLY MOVES (7.3), only when the raider is named: public.pirate_stow puts voyage.raid_takes's result into her home's stock, each good up to 2 x its stock_target, the rest lost; public.pirate_ransom moves
--   ransom_share (8 %, public.ransom_take, the one reader) of the cargo's cost basis (public.fleet_stock_at_cost) from the company's purse to her home's, kind RANSOM (new word, moved), what the purse cannot pay it does not pay;
--   public.pirate_loot_book takes the plundered share (voyage.plunder_share, lifted out of raid_takes so the goods' share and the gold's are one roll) of a cargo ship's funds aboard: the ship's book closes LOOTED (0327's row)
--   and the gold is her home's purse at once, kind LOOT (moved). A hoard at or above pirate_hoard_cap (2 B) takes no gold: RANSOM and LOOT pay 0, goods still stow.
-- REGEN OFF AT A PIRATE HOME (7.6): one condition in public.tick_market_drift, lit only: a free port's stock neither regenerates up nor decays down; plunder alone adds to it. Dark, one constant and no call per row.
-- A PLAYER MEETS HER: public.attack_for takes kind PIRATE (regard regard_pirate with the Brethren, reason ATTACK_PIRATE); public.attack_close writes no WANTED row for the pirates (they have no navy to answer). attack_enabled stays
--   false. She carries no book to loot (below).
-- THE JOB, BOUNDED FROM THE START: public.tick_pirates, pg_cron byeharu-voyage:pirates, every minute, never in the beat. At most navy_steps_per_run ships a run, turned by the minute; pressure, one ship added and one hour paid
--   only while lit. Dark: one knob read and one read of an empty table.
--
-- DECIDED BY DEFAULT (the owner may reverse any; the dev-log lists them all): a pirate ship carries NO BOOK: the gold she takes from a cargo ship is her home's the moment it is taken (the design's "delivered when she docks home"
--   needed a fifth book stage, two trigger hunks and three readers for the same money; W18 and W19 need none of it); a named raider fights with her own hulls at her own strength, whatever the day's magnitude; stow and RANSOM only
--   when the raider is named (an anonymous xebec has no home); the cruise is one stored course out and back, the most dangerous sea first; the hoard's purse is the pirate capital (Port Royal); the yard paid is the nearest by sea,
--   whoever holds it; the navy's knobs navy_upkeep_day, navy_build_hours, navy_reach_nm, navy_store_days and navy_steps_per_run are reused, not copied; regard_pirate -50.
--
-- THE RE-CUTS (hunks sliced from the LIVE bodies, read on the cached head world at 0338 (prod head 0337 + W16); each hunk occurs exactly once in the live body and reverses to its pre-image; ACL, volatility, definer, config
-- unmoved; this file supersedes those lines of): public.fleet_kind (0308, 0331), public.fleet_origin (0322, 0331), public.crown_house (0331), public.crown_nation (0333), public.sea_houses (0310, 0326, 0331),
-- public.fleet_wage (0154, 0328, 0331), public.cargo_figures (0310, 0331), public.client_rpc_entry_points (0331), voyage.raid_takes (0213), voyage.depart (0047, 0330, 0334), voyage.settle (0059, 0213, 0279, 0322, 0330, 0334),
-- public.attack_for (0327, 0333), public.attack_close (0327, 0333, 0334), public.tick_market_drift (0137, 0245, 0252, 0289). One new function per concept, listed in c_new_fns. NOT touched: any other function, table, switch or job.
--
-- SELF-ASSERT (this block): catalog, stable reads and arithmetic on probe figures only; never a game step and never a digest of live rows. Every hunk once and reversing; no other function, knob, word or job moved; the switch off;
-- no row written to the new tables but the one clock row; the size formula; the dark identity of the freeze; the readers stable and server-only; the card exactly authenticated-only and registered.
-- THE LIVE PATHS ARE PROVED IN CI: proof 46, scripts/db/proofs/46_pirate_ships_sail.sql (lit: build, pay, cruise, pressure, a real raid through voyage.settle with stow, RANSOM and LOOT, regen off, the switch off, W unchanged).
-- Red first, dark parity and mutation controls: scripts/ops/harness/pirate-ships-sail/proof-0339.mjs (local, cached world, nothing from zero).
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 90 s, lock_timeout 5 s first; the self-assert fails above 45 s.
-- ROLLBACK (forward, a NEW migration, owner only): `pirates_bite` false: nothing is built or paid, each ship finishes her leg, sails home and is laid up; no new departure names a raider; the sea's pressure empties. Hulls remain.
-- VERSION: 0339 = prod head 0337 + 0338 (W16, PR #552) + 1. If 0338 cuts a line of these hunks, this file refuses at "occurs 0 time(s)" and is rebased.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_t0   timestamptz := clock_timestamp();
  v_h    record;
  v_def  text;
  v_pre  text;
  v_n    int;
  v_fn_before    text;
  v_cfg_before   text;
  v_meta_before  text;
  v_words_before text;
  v_cron_before  text;
  v_cron_after   text;
  v_pressure_before int;
  v_class text;
  v_pir   uuid;
  v_probe jsonb;
  c_keys constant text[] := array['pirates_bite', 'pirate_ship_class', 'pirate_max', 'pirate_min', 'pirate_hoard_unit', 'pirate_hoard_cap', 'pirate_spend_day_pct', 'pirate_pressure', 'pirate_haunt_hours', 'regard_pirate'];
  c_words constant text[] := array['RANSOM'];
  c_new_fns constant text[] := array[
    'public.pirates_on()', 'public.pirate_nation()', 'public.pirate_capital()', 'public.pirate_hoard()', 'public.pirate_size_for(bigint)', 'public.pirate_size()', 'public.pirate_home_of(integer)',
    'public.pirate_spend_room(timestamp with time zone)', 'public.pirate_pay(text,bigint,timestamp with time zone,uuid,uuid)', 'public.pirate_ship_in_sea(uuid)',
    'voyage.pirate_strength(uuid)', 'voyage.freeze_raiders(jsonb,uuid)', 'voyage.leg_raider(jsonb)', 'voyage.plunder_share(uuid,integer,text)',
    'public.pirate_stow(uuid,jsonb)', 'public.pirate_ransom(uuid,uuid,bigint,uuid)', 'public.pirate_loot_book(uuid,uuid,numeric,uuid)', 'public.pirate_pressure_write(timestamp with time zone)',
    'public.pirate_haunt_of(uuid,integer)', 'public.pirate_commission(integer,uuid,uuid,timestamp with time zone)', 'public.pirate_add(timestamp with time zone)', 'public.pirate_pay_hour(timestamp with time zone)',
    'public.pirate_sail(uuid,uuid,jsonb,uuid,uuid,uuid,text,timestamp with time zone)', 'public.pirate_ship_step(uuid,timestamp with time zone)', 'public.tick_pirates(timestamp with time zone)',
    'world.pirate_ship_card(uuid)'];
  c_hunked constant text[] := array[
    'public.fleet_kind(uuid)', 'public.fleet_origin(uuid)', 'public.crown_house(uuid)', 'public.crown_nation(uuid)', 'public.sea_houses()', 'public.fleet_wage(uuid,boolean,integer)',
    'public.cargo_figures()', 'public.client_rpc_entry_points()', 'voyage.raid_takes(uuid,integer,uuid,text)', 'voyage.depart(uuid,jsonb,uuid,uuid,timestamp with time zone)',
    'voyage.settle(uuid,timestamp with time zone)', 'public.attack_for(uuid,uuid,uuid,integer,timestamp with time zone)', 'public.attack_close(uuid,jsonb,timestamp with time zone)',
    'public.tick_market_drift(timestamp with time zone,uuid)'];
begin
  perform set_config('statement_timeout', '90s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD: nothing of this file exists, and the premises it was cut against hold ──
  if to_regclass('public.pirate_ships') is not null or to_regclass('public.pirate_spend_day') is not null or to_regclass('public.pirate_clock') is not null
     or exists (select 1 from public.world_config c where c.key = any (c_keys))
     or exists (select 1 from public.stats_flow_words w where w.kind = any (c_words))
     or to_regprocedure('public.pirates_on()') is not null then
    raise exception '0339 refuses: something of it is already in this world';
  end if;
  if to_regprocedure('public.pirate_power(uuid)') is null or to_regprocedure('public.port_is_free(uuid)') is null or to_regclass('public.sea_pressure') is null
     or to_regprocedure('voyage.freeze_danger(jsonb,timestamp with time zone)') is null or to_regprocedure('public.navy_on()') is null or to_regprocedure('public.fleet_hands(uuid,uuid)') is null
     or to_regprocedure('public.fleet_stores(uuid,numeric)') is null or to_regprocedure('public.realm_purse(uuid)') is null or to_regprocedure('public.ransom_take(bigint)') is null
     or to_regprocedure('public.fleet_stock_at_cost(uuid)') is null or to_regprocedure('public.cargo_ship_aboard(uuid)') is null or to_regprocedure('public.convoy_book(text,uuid,uuid,uuid,bigint,bigint)') is null then
    raise exception '0339 refuses: 0213 / 0309 / 0322 / 0327 / 0328 / 0330 / 0331 / 0338 (the hoard, the quay, the danger, the book, the free port) are not all in this world';
  end if;
  select g.nation_id into v_pir from public.great_powers g where g.pirate;
  if v_pir is null or not exists (select 1 from public.port_allegiance a where a.nation_id = v_pir and a.home) then
    raise exception '0339 refuses: the Brethren (0338) have no home in this world';
  end if;
  v_class := (select c.value #>> '{}' from public.world_config c where c.key = 'fight_raider_class');
  if not exists (select 1 from public.ship_classes c where c.code = v_class and c.attack > 0 and c.crew_required > 0 and c.build_cost > 0) then
    raise exception '0339 refuses: fight_raider_class (%) is no armed class with a price', v_class;
  end if;
  if not exists (select 1 from public.stats_flow_words w where w.kind = 'LOOT' and w.side = 'moved') then
    raise exception '0339 refuses: LOOT (0327) is not a moved word in this world';
  end if;

  -- ── 1. THE PRE-IMAGES ──
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked) x));
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before
    from public.world_config c;
  select md5(string_agg(w.kind || ':' || w.side || ':' || w.word || ':' || w.ord, ',' order by w.kind)) into v_words_before
    from public.stats_flow_words w;
  select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
    into v_meta_before
    from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked) x));
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.command || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_cron_before;
  end if;
  v_pressure_before := (select count(*) from public.sea_pressure);

  -- ── 2. THE KNOBS AND THE WORD ──
  insert into public.world_config (key, value, description) values
    ('pirates_bite', 'false'::jsonb, '0339 (W17): THE switch of the pirates'' ships, read only through public.pirates_on() (which also needs the city purses lit). False: nothing is built or paid, a ship that exists sails home and is laid up, no departure names a raider, nothing is stowed, no RANSOM or LOOT moves, the sea''s pressure is empty, a pirate home''s market regenerates as any. Owner only; W18 reads the same switch.'),
    ('pirate_ship_class', to_jsonb(v_class), '0339: public.ship_classes.code of a pirate hull. Shipped equal to fight_raider_class, so a named raider and the anonymous raider are one hull. Her build cost is what the hoard pays (BUILD_NAVY).'),
    ('pirate_max', to_jsonb(30), '0339: the most pirate ships, whatever the hoard.'),
    ('pirate_min', to_jsonb(4), '0339: the ships the Brethren are allowed before the hoard counts (a hoard that cannot pay still builds none).'),
    ('pirate_hoard_unit', to_jsonb(100000000), '0339: ships = least(pirate_max, pirate_min + floor(hoard / this)) (public.pirate_size_for). The hoard is public.pirate_hoard().'),
    ('pirate_hoard_cap', to_jsonb(2000000000), '0339: a hoard at or above this takes no gold in: RANSOM and LOOT pay 0 (goods still stow). docs/WORLD_POWERS.md 7.6.'),
    ('pirate_spend_day_pct', to_jsonb(0.005), '0339: what the Brethren may spend in one UTC day, as a share of the hoard: THE one cap on every outflow from the hoard (public.pirate_spend_room, public.pirate_pay), ships and merchants alike.'),
    ('pirate_pressure', to_jsonb(0.5), '0339: what one pirate ship at work in a sea adds to that sea''s pressure (public.sea_pressure, read by voyage.sea_danger). docs/WORLD_POWERS.md 7.6: raids rise by half where a ship is present.'),
    ('pirate_haunt_hours', to_jsonb(12), '0339: how long a pirate ship lies at the haunt harbour of her cruise before she sails home.'),
    ('regard_pirate', to_jsonb(-50), '0339: the regard a player''s attack on a pirate ship costs with the Brethren (public.attack_for, reason ATTACK_PIRATE). The hunt''s regard with the ten is W19''s.');
  insert into public.stats_flow_words (kind, side, word, ord) values ('RANSOM', 'moved', 'Ransom', 54);

  -- ── 3. THE TABLES ──
  create table public.pirate_ships (
    fleet_id     uuid primary key references public.fleets(id) on delete cascade,
    player_id    uuid not null unique references public.players(id) on delete cascade,
    ord          integer not null unique check (ord >= 1),
    home_port    uuid not null references public.ports(id),
    sea_id       uuid references public.seas(id),
    mission      text not null default 'HOME' check (mission in ('HOME', 'CRUISE')),
    haunt_port   uuid references public.ports(id),
    haunt_since  timestamptz,
    last_port    uuid not null references public.ports(id),
    fought_at    timestamptz,
    unpaid_since timestamptz,
    laid_up_at   timestamptz,
    created_at   timestamptz not null default now(),
    unique (fleet_id, player_id)
  );
  create index pirate_ships_sea on public.pirate_ships (sea_id) where sea_id is not null and laid_up_at is null;
  comment on table public.pirate_ships is '0339: THE kind. A row here is a pirate ship of the Brethren. `sea_id` is the sea she is cruising (set as she leaves home, null when home): THE position for "who raids" (voyage.freeze_raiders) and for W19''s hunt. `fought_at` is W19''s to write. Laid up is never deleted. Server-only.';
  alter table public.pirate_ships enable row level security;
  revoke all on table public.pirate_ships from public, anon, authenticated;

  create view public.pirate_ships_at_work as
    select n.fleet_id, n.player_id, n.ord, n.home_port, n.sea_id, n.mission, n.haunt_port, n.haunt_since, n.last_port, n.fought_at, n.unpaid_since, n.created_at
      from public.pirate_ships n where n.laid_up_at is null;
  comment on view public.pirate_ships_at_work is '0339: THE ships at work: public.pirate_ships less the laid up. Server-only.';
  revoke all on table public.pirate_ships_at_work from public, anon, authenticated;

  create view public.pirate_ships_cruising as
    select n.fleet_id, n.player_id, n.ord, n.home_port, n.sea_id, n.haunt_port
      from public.pirate_ships n join public.fleets f on f.id = n.fleet_id
     where n.laid_up_at is null and n.sea_id is not null
       and f.status in ('SAILING', 'DOCKED', 'ANCHORED')
       and exists (select 1 from public.ships s where s.fleet_id = n.fleet_id and s.durability > 0);
  comment on view public.pirate_ships_cruising is '0339: THE ONE RULE of "she is in a sea": at work, cruising (sea_id set: out for her haunt or lying at it), free to fight (not in a battle, not a wreck, not under repair) and with a hull left. Read by public.pirate_ship_in_sea (the freeze, W19''s hunt) and public.pirate_pressure_write, and by nothing else. Server-only.';
  revoke all on table public.pirate_ships_cruising from public, anon, authenticated;

  create table public.pirate_spend_day (
    day   date primary key,
    spent bigint not null default 0 check (spent >= 0)
  );
  comment on table public.pirate_spend_day is '0339: what the hoard paid out on each UTC day (public.pirate_pay writes it). Read by public.pirate_spend_room only. Server-only.';
  alter table public.pirate_spend_day enable row level security;
  revoke all on table public.pirate_spend_day from public, anon, authenticated;

  create table public.pirate_clock (
    one      boolean primary key default true check (one),
    added_at timestamptz,
    paid_at  timestamptz
  );
  comment on table public.pirate_clock is '0339: one row: when the Brethren last added a ship (public.pirate_add) and last paid an hour (public.pirate_pay_hour). Server-only.';
  alter table public.pirate_clock enable row level security;
  revoke all on table public.pirate_clock from public, anon, authenticated;
  insert into public.pirate_clock (one) values (true);

  -- ── 4. THE NEW FUNCTIONS ──
  execute $f$
create function public.pirates_on()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0339: THE one reader of the pirates' switch: pirates_bite, and the city purses lit (the hoard is the purses). Off: no ship is built or paid, no raider is named, nothing is stowed, no gold moves, no pressure stands.
  select coalesce(public.wc('pirates_bite') = 'true'::jsonb, false) and public.city_treasury_on()
$$
  $f$;

  execute $f$
create function public.pirate_nation()
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0339: the nation that is the pirates (public.great_powers.pirate, at most one: 0338). Null if none.
  select g.nation_id from public.great_powers g where g.pirate limit 1
$$
  $f$;

  execute $f$
create function public.pirate_capital()
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0339: THE purse the hoard pays from: the pirate nation's capital (nations.capital_port_code: Port Royal). Null if the pirates have no capital.
  select p.id from public.nations n join public.ports p on p.code = n.capital_port_code where n.id = public.pirate_nation()
$$
  $f$;

  execute $f$
create function public.pirate_hoard()
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0339: THE hoard reader (docs/WORLD_POWERS.md 7.1: the hoard is the sum of the pirates' city purses): public.realm_purse over the Brethren, one copy.
  select coalesce(public.realm_purse(public.pirate_nation()), 0)::bigint
$$
  $f$;

  execute $f$
create function public.pirate_size_for(p_hoard bigint)
returns integer
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0339: how many ships a hoard keeps (docs/WORLD_POWERS.md 7.3): least(pirate_max, pirate_min + floor(hoard / pirate_hoard_unit)). A hoard that cannot pay still builds none: that is public.pirate_pay's.
  select least(public.wc_int('pirate_max'), public.wc_int('pirate_min') + floor(greatest(coalesce(p_hoard, 0), 0)::numeric / public.wc_num('pirate_hoard_unit'))::integer)
$$
  $f$;

  execute $f$
create function public.pirate_size()
returns integer
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0339: the number the Brethren rest at today: public.pirate_size_for(public.pirate_hoard()).
  select public.pirate_size_for(public.pirate_hoard())
$$
  $f$;

  execute $f$
create function public.pirate_home_of(p_ord integer)
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0339: the home ship ord sails from: the capital first, then the other homes by code, wrapping. No home: null.
  with h as (
    select a.port_id, (a.port_id = public.pirate_capital()) as cap, p.code
      from public.port_allegiance a join public.great_powers g on g.nation_id = a.nation_id join public.ports p on p.id = a.port_id
     where a.home and g.pirate and p.kind = 'HARBOUR'
  )
  select h.port_id from h order by h.cap desc, h.code offset (greatest(p_ord, 1) - 1) % greatest(1, (select count(*) from h)) limit 1
$$
  $f$;

  execute $f$
create function public.pirate_spend_room(p_now timestamptz)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0339: THE one authority for "how much may the Brethren spend today" (docs/WORLD_POWERS.md 7.1, 7.4): pirate_spend_day_pct of the hoard, less what was paid out in the UTC day of p_now, never below 0.
  -- W17 (a hull, an hour's pay) and W18 (a founding, an investment) read it through public.pirate_pay and never pay more than it answers.
  select greatest(0, floor(public.pirate_hoard() * public.wc_num('pirate_spend_day_pct'))::bigint
                     - coalesce((select d.spent from public.pirate_spend_day d where d.day = (p_now at time zone 'UTC')::date), 0))::bigint
$$
  $f$;

  execute $f$
create function public.pirate_pay(p_kind text, p_amount bigint, p_now timestamptz, p_port uuid default null, p_player uuid default null)
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0339: THE ONE WAY THE HOARD PAYS. Whole or nothing: answers 0 and writes nothing when the day's room is short (public.pirate_spend_room), when the capital's surplus is short (public.city_surplus), or when the capital is busy
-- (public.treasury_try_lock, 0307's rule). Else the capital pays a harbour (two rows of a moved kind, public.treasury_post) or a house (public.city_pays), and the spend is written to the day. Never a debt, never minted.
-- Paying the capital itself moves nothing and costs no room. Answers the ducats moved.
declare
  v_cap uuid := public.pirate_capital();
begin
  if v_cap is null or coalesce(p_amount, 0) <= 0 or (p_port is null) = (p_player is null) then
    return 0;
  end if;
  if p_port = v_cap then
    return p_amount;
  end if;
  if public.pirate_spend_room(p_now) < p_amount or public.city_surplus(v_cap) < p_amount then
    return 0;
  end if;
  if not public.treasury_try_lock(v_cap) then
    return 0;
  end if;
  if public.city_surplus(v_cap) < p_amount then
    return 0;
  end if;
  if p_player is not null then
    perform public.city_pays(v_cap, p_player, p_kind, p_amount, null);
  else
    perform public.treasury_post(v_cap, p_kind, -p_amount, null, null);
    perform public.treasury_post(p_port, p_kind, p_amount, null, null);
  end if;
  insert into public.pirate_spend_day (day, spent) values ((p_now at time zone 'UTC')::date, p_amount)
  on conflict (day) do update set spent = public.pirate_spend_day.spent + excluded.spent;
  return p_amount;
end
$$
  $f$;

  execute $f$
create function public.pirate_ship_in_sea(p_sea uuid)
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0339: THE one reader of "which pirate ship is in this sea": the lowest-ord ship cruising it (public.pirate_ships_cruising: at work, sea_id set, free to fight, a hull left; so a wreck, a ship in a battle or under repair, and a
  -- hulk are never named). Null if none. Read by voyage.freeze_raiders, and by W19's hunt with a navy ship's own sea.
  select n.fleet_id from public.pirate_ships_cruising n where n.sea_id = p_sea order by n.ord limit 1
$$
  $f$;

  execute $f$
create function voyage.pirate_strength(p_fleet uuid)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0339: a pirate ship's strength as a raider figure for voyage.fight: the squadron rule of voyage.raider_hulls read the other way (attack / 10 + crew_required x 0.02 + tier x 3 a hull), by the hull she has left, so the one fight
  -- engine builds her as hulls of fight_raider_class (one whole hull for a whole xebec) and no second fight path exists. A hull with nothing left counts nothing.
  select coalesce(sum((c.attack / 10.0 + c.crew_required * 0.02 + c.tier * 3) * least(1, s.durability / nullif((select b.durability from public.ship_base(s.id) b), 0))), 0)
    from public.ships s join public.ship_classes c on c.id = s.class_id
   where s.fleet_id = p_fleet and s.durability > 0
$$
  $f$;

  execute $f$
create function voyage.freeze_raiders(p_segments jsonb, p_fleet uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0339 (docs/PIRATES_AND_HAVENS.md 2.3): beside each segment's frozen danger, the pirate ship cruising its sea as she left, if any (`raider`). Read by voyage.depart only.
  -- DARK, OR A PIRATE SHIP'S OWN VOYAGE: p_segments unchanged, byte for byte (pirates do not raid pirates; a merchant's path is what it was).
  select case when not public.pirates_on() or exists (select 1 from public.pirate_ships n where n.fleet_id = p_fleet) then p_segments
              else coalesce((select jsonb_agg(e.seg || case when r.fleet_id is null then '{}'::jsonb else jsonb_build_object('raider', r.fleet_id) end order by e.n)
                               from jsonb_array_elements(p_segments) with ordinality e(seg, n)
                               cross join lateral (select public.pirate_ship_in_sea((e.seg ->> 'sea_id')::uuid) as fleet_id) r), '[]'::jsonb) end
$$
  $f$;

  execute $f$
create function voyage.leg_raider(p_leg jsonb)
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0339: THE one reading of a segment's frozen raider: the pirate ship named as she left, or null for an anonymous day (every segment frozen before this file, and every one frozen dark).
  select (p_leg ->> 'raider')::uuid
$$
  $f$;

  execute $f$
create function voyage.plunder_share(p_voyage uuid, p_day integer, p_outcome text)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0339: THE share a raid takes, lifted out of voyage.raid_takes (0213) so the goods and a cargo ship's gold take one roll: STRIPPED all of it; PLUNDERED plunder_share_min + plunder_share_span x the day's own 'plunder' stream; else nothing.
  select case p_outcome when 'STRIPPED' then 1::numeric
                        when 'PLUNDERED' then public.wc_num('plunder_share_min') + public.wc_num('plunder_share_span') * voyage.rng(p_voyage, p_day, 'plunder')
                        else 0::numeric end
$$
  $f$;

  execute $f$
create function public.pirate_stow(p_fleet uuid, p_taken jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0339 (docs/WORLD_POWERS.md 7.3): WHAT A NAMED RAIDER STOWS: voyage.raid_takes's result ({good code: units}) into the stock of her home port, each good up to 2 x that row's stock_target; beyond that it is lost at sea.
-- Answers {good code: units stowed}. A good her home has no row for is lost. Read by voyage.settle's PIRATES arm alone.
declare
  n      public.pirate_ships%rowtype;
  r      record;
  v_s    numeric;
  v_t    numeric;
  v_in   numeric;
  v_out  jsonb := '{}'::jsonb;
begin
  select * into n from public.pirate_ships x where x.fleet_id = p_fleet;
  if n.fleet_id is null or p_taken is null or jsonb_typeof(p_taken) <> 'object' then
    return v_out;
  end if;
  for r in select e.key as code, (e.value)::text::numeric as qty from jsonb_each(p_taken) e
            where jsonb_typeof(e.value) = 'number' and (e.value)::text::numeric > 0 order by e.key loop
    select pg.stock, pg.stock_target into v_s, v_t
      from public.port_goods pg join public.goods g on g.id = pg.good_id where pg.port_id = n.home_port and g.code = r.code for update of pg;   -- the market row alone: never a lock on the goods catalogue inside the beat
    continue when v_s is null;
    v_in := greatest(0, least(r.qty, 2 * v_t - v_s));
    if v_in > 0 then
      update public.port_goods pg set stock = pg.stock + v_in, updated_at = now()
        from public.goods g where g.id = pg.good_id and pg.port_id = n.home_port and g.code = r.code;
    end if;
    v_out := v_out || jsonb_build_object(r.code, v_in);
  end loop;
  return v_out;
end
$$
  $f$;

  execute $f$
create function public.pirate_ransom(p_fleet uuid, p_company uuid, p_basis bigint, p_event uuid default null)
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0339 (docs/WORLD_POWERS.md 7.3): RANSOM, paid to a named raider: public.ransom_take (ransom_share of the cargo's cost basis) from the company's purse, player or merchant, to her home's purse, kind RANSOM, moved
-- (public.pay_city: the house's row first, the harbour second). A purse that cannot pay pays what it holds. Nothing moves with the purses dark (the hoard is the purses) or with the hoard at pirate_hoard_cap. Answers the ducats moved.
declare
  n       public.pirate_ships%rowtype;
  v_purse bigint;
  v_take  bigint;
begin
  select * into n from public.pirate_ships x where x.fleet_id = p_fleet;
  if n.fleet_id is null or p_company is null or not public.city_treasury_on() or public.pirate_hoard() >= public.wc_num('pirate_hoard_cap') then
    return 0;
  end if;
  select pl.ducats into v_purse from public.players pl where pl.id = p_company for update;
  v_take := least(public.ransom_take(p_basis), greatest(coalesce(v_purse, 0), 0));
  if v_take <= 0 then
    return 0;
  end if;
  perform public.pay_city(p_company, n.home_port, 'RANSOM', v_take, p_event);
  return v_take;
end
$$
  $f$;

  execute $f$
create function public.pirate_loot_book(p_fleet uuid, p_victim uuid, p_share numeric, p_event uuid default null)
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0339 (docs/WORLD_POWERS.md 7.3): A CARGO SHIP'S GOLD, taken by a named raider: the plundered share of her funds aboard (public.cargo_ship_aboard) leaves her book (public.convoy_book, stage LOOTED: 0327's row, set aside down,
-- no purse moves) and is her home's purse at once (public.treasury_post, kind LOOT, moved; p_always: funds aboard are city money already, 0309). Decided by default: no book of her own (the dev-log says why).
-- Only a cargo ship carries funds: any other victim answers 0. Nothing with the hoard at pirate_hoard_cap. The caller holds the victim's fleet row. Answers the ducats moved.
declare
  n       public.pirate_ships%rowtype;
  c       public.cargo_ships%rowtype;
  v_load  bigint;
  v_left  bigint;
  v_take  bigint;
begin
  select * into n from public.pirate_ships x where x.fleet_id = p_fleet;
  select * into c from public.cargo_ships x where x.fleet_id = p_victim;
  if n.fleet_id is null or c.fleet_id is null or coalesce(p_share, 0) <= 0 or public.pirate_hoard() >= public.wc_num('pirate_hoard_cap') then
    return 0;
  end if;
  select a.load_id, a.aboard into v_load, v_left from public.cargo_ship_aboard(p_victim) a;
  if v_load is null or coalesce(v_left, 0) <= 0 then
    return 0;
  end if;
  v_take := least(v_left, floor(v_left * least(p_share, 1)))::bigint;
  if v_take <= 0 then
    return 0;
  end if;
  perform public.convoy_book('LOOTED', p_victim, c.player_id, (select l.port_id from public.convoy_cargo l where l.id = v_load), v_take, v_load);
  perform public.treasury_post(n.home_port, 'LOOT', v_take, null, p_event, true);
  return v_take;
end
$$
  $f$;

  execute $f$
create function public.pirate_pressure_write(p_now timestamptz)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0339: THE first and only writer of public.sea_pressure (0330): lit, one row a sea with pirate ships cruising it (public.pirate_ships_cruising, the same rule that names a raider: a wreck or a hulk presses on nothing), pirate_pressure a
-- ship, refreshed to p_now each run so it does not decay while she is there; a sea with none loses its row; off, the table empties. voyage.sea_danger reads it as 0330 wrote, so a departure into her sea freezes a higher figure.
-- Answers the rows standing. Called by public.tick_pirates only.
declare
  v_lit boolean := public.pirates_on();
begin
  delete from public.sea_pressure sp where not v_lit or not exists (select 1 from public.pirate_ships_cruising x where x.sea_id = sp.sea_id);
  if v_lit then
    insert into public.sea_pressure (sea_id, value, updated_at)
    select x.sea_id, public.wc_num('pirate_pressure') * count(*), p_now from public.pirate_ships_cruising x group by x.sea_id
    on conflict (sea_id) do update set value = excluded.value, updated_at = excluded.updated_at;
  end if;
  return (select count(*) from public.sea_pressure);
end
$$
  $f$;

  execute $f$
create function public.pirate_haunt_of(p_home uuid, p_ord integer)
returns table (port_id uuid, sea_id uuid, course jsonb)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0339: WHERE SHIP ord OF THIS HOME CRUISES: a harbour one stored merchant course away (public.npc_courses, the way back required), within navy_reach_nm, not a pirate home, the most dangerous sea as authored first
  -- (voyage.sea_danger at no moment), ties by code, spread by ord. Her sea is the haunt's. No course: no row, and she lies at home.
  with h as (
    select c.to_port as port_id, p.sea_id, c.course, voyage.sea_danger(p.sea_id, null) as danger, p.code
      from public.npc_courses c join public.ports p on p.id = c.to_port
     where c.from_port = p_home and p.kind = 'HARBOUR' and c.nm <= public.wc_num('navy_reach_nm')
       and exists (select 1 from public.npc_courses b where b.from_port = c.to_port and b.to_port = p_home)
       and not exists (select 1 from public.port_allegiance a join public.great_powers g on g.nation_id = a.nation_id where a.port_id = p.id and a.home and g.pirate)
  )
  select h.port_id, h.sea_id, h.course from h order by h.danger desc, h.code offset (greatest(p_ord, 1) - 1) % greatest(1, (select count(*) from h)) limit 1
$$
  $f$;

  execute $f$
create function public.pirate_commission(p_ord integer, p_home uuid, p_yard uuid, p_now timestamptz)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0339: THE one place a pirate ship is made: the hoard pays the yard the class's build cost (public.pirate_pay BUILD_NAVY, whole or nothing: answers null and makes nothing when it cannot), and she is laid at her home by the hands
-- every fleet is made by (public.form_fleet, public.commission_ship), crewless: her first departure brings hands and stores. Her house's purse is 0 and no ledger row is written. Answers her fleet, or null.
declare
  v_class  text := public.wc_text('pirate_ship_class');
  v_cost   bigint := (select c.build_cost from public.ship_classes c where c.code = v_class);
  v_player uuid;
  v_fleet  uuid;
begin
  if public.pirate_pay('BUILD_NAVY', v_cost, p_now, p_yard, null) <= 0 then
    return null;
  end if;
  insert into public.players (company_name, nation_id, ducats, is_npc)
  values (format('Brethren ship %s', p_ord), public.pirate_nation(), 0, true)
  returning id into v_player;
  v_fleet := public.form_fleet(v_player, format('Pirate ship %s', p_ord), p_home);
  perform public.commission_ship(v_player, v_fleet, v_class, format('Pirate ship %s', p_ord), true, false);
  insert into public.pirate_ships (fleet_id, player_id, ord, home_port, last_port, created_at)
  values (v_fleet, v_player, p_ord, p_home, p_home, p_now);
  return v_fleet;
end
$$
  $f$;

  execute $f$
create function public.pirate_add(p_now timestamptz)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0339: at most one ship added a run, and one in navy_build_hours. The lowest ord inside public.pirate_size() that is not at work: laid up, she WAKES where she lies when the room and the capital's surplus cover her next
-- hour's slice; otherwise a new hull is BUILT, when a yard can be reached and the hoard pays (public.pirate_commission). A hoard that cannot pay just waits: nothing is written, and it is asked again next run. Answers BUILT, WOKEN or null.
declare
  v_size  int := public.pirate_size();
  v_slice bigint := round(public.wc_num('navy_upkeep_day') / 24);
  v_ord   int;
  v_up    boolean;
  v_home  uuid;
  v_yard  uuid;
  v_cap   uuid := public.pirate_capital();
begin
  if v_cap is null or (select c.added_at from public.pirate_clock c) > p_now - make_interval(hours => public.wc_int('navy_build_hours')) then
    return null;
  end if;
  select min(o) into v_ord from generate_series(1, v_size) o
   where not exists (select 1 from public.pirate_ships_at_work n where n.ord = o);
  if v_ord is null then
    return null;
  end if;
  v_up := exists (select 1 from public.pirate_ships n where n.ord = v_ord);
  if v_up then
    if public.pirate_spend_room(p_now) < v_slice or public.city_surplus(v_cap) < v_slice then
      return null;
    end if;
    update public.pirate_ships n set laid_up_at = null, unpaid_since = null where n.ord = v_ord;
  else
    v_home := public.pirate_home_of(v_ord);
    v_yard := public.refit_yard(v_home);
    if v_home is null or v_yard is null or public.pirate_commission(v_ord, v_home, v_yard, p_now) is null then
      return null;
    end if;
  end if;
  update public.pirate_clock set added_at = p_now;
  return case when v_up then 'WOKEN' else 'BUILT' end;
end
$$
  $f$;

  execute $f$
create function public.pirate_pay_hour(p_now timestamptz)
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0339: one hour of upkeep a run, once an hour: the hoard pays each ship at work navy_upkeep_day / 24, to the harbour she lies at or last called at, in order of ord, as far as public.pirate_pay allows (the day's room, the capital's
-- surplus). A ship it cannot pay is marked unpaid, and she goes home and is laid up (public.pirate_ship_step); paid again, she is marked paid. Never a debt: a missed hour is one slice. At the capital nothing moves. Answers the ducats moved.
declare
  r       record;
  v_slice bigint := round(public.wc_num('navy_upkeep_day') / 24);
  v_paid  bigint;
  v_total bigint := 0;
begin
  if (select c.paid_at from public.pirate_clock c) > p_now - interval '1 hour' then
    return 0;
  end if;
  for r in select n.fleet_id, coalesce(f.port_id, n.last_port) as to_port
             from public.pirate_ships_at_work n join public.fleets f on f.id = n.fleet_id order by n.ord loop
    v_paid := public.pirate_pay('NAVY_PAY', v_slice, p_now, r.to_port, null);
    update public.pirate_ships n set unpaid_since = case when v_paid > 0 then null else coalesce(n.unpaid_since, p_now) end where n.fleet_id = r.fleet_id;
    if r.to_port <> public.pirate_capital() then
      v_total := v_total + v_paid;
    end if;
  end loop;
  update public.pirate_clock set paid_at = p_now;
  return v_total;
end
$$
  $f$;

  execute $f$
create function public.pirate_sail(p_fleet uuid, p_port uuid, p_segments jsonb, p_to uuid, p_sea uuid, p_haunt uuid, p_mission text, p_now timestamptz)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0339: every leg of a pirate ship: her position first (sea_id: the sea she cruises, null on the way home; the haunt; the mission), then hands from the quay above its floor (public.fleet_hands), stores to navy_store_days,
-- then voyage.depart, as every ship. No gold: her upkeep is their price. A quay at its floor gives none and she sails short.
begin
  update public.pirate_ships n set sea_id = p_sea, haunt_port = p_haunt, haunt_since = null, mission = p_mission, last_port = p_port where n.fleet_id = p_fleet;
  perform public.fleet_hands(p_fleet, p_port);
  perform public.fleet_stores(p_fleet, public.wc_num('navy_store_days'));
  perform voyage.depart(p_fleet, p_segments, p_port, p_to, p_now);
  return 'SAILED';
end
$$
  $f$;

  execute $f$
create function public.pirate_ship_step(p_fleet uuid, p_now timestamptz default now())
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0339: what a pirate ship does in port, in one place. Answers BUSY, AWAY, WRECK, IN_PORT, HAUNT, IDLE, LAID_UP or SAILED.
--   A wreck: she waits for her home to pay (public.npc_refit_step), or, the refit rule dark, she is patched free where she lies (public.fleet_patched), as a navy ship.
--   ON DUTY means the switch is on, she is paid, and her ord is inside the Brethren's number. On duty at home she is mended free and sails for her haunt (public.pirate_haunt_of); at the haunt she lies pirate_haunt_hours,
--   then sails home by the stored course back. OFF DUTY she sails straight home, and there she is laid up: a ship above the number, an unpaid ship and every ship with the switch off end the same way, by one path.
declare
  f       public.fleets%rowtype;
  n       public.pirate_ships%rowtype;
  h       record;
  v_duty  boolean;
  v_course jsonb;
begin
  select * into f from public.fleets x where x.id = p_fleet for update skip locked;
  if f.id is null then
    return 'BUSY';
  end if;
  if f.status not in ('DOCKED', 'UNABLE_TO_SAIL') then
    return 'AWAY';
  end if;
  select * into n from public.pirate_ships x where x.fleet_id = p_fleet;
  if n.fleet_id is null then
    raise exception 'E_NOT_A_PIRATE_SHIP: fleet %', p_fleet using errcode = 'P0001';
  end if;
  -- IN A PORT THAT IS NOT HER HAUNT (her home, a wreck's respawn at it, a stranding) SHE IS IN NO SEA: her position is cleared before anything else, so a stale sea_id can name nobody and press on nothing
  if f.port_id is distinct from n.haunt_port and (n.sea_id is not null or n.haunt_port is not null or n.haunt_since is not null or n.mission <> 'HOME') then
    update public.pirate_ships x set sea_id = null, haunt_port = null, haunt_since = null, mission = 'HOME' where x.fleet_id = p_fleet;
    select * into n from public.pirate_ships x where x.fleet_id = p_fleet;
  end if;
  if public.npc_wrecked(p_fleet) then
    return 'WRECK';
  end if;
  if f.status = 'UNABLE_TO_SAIL' then
    f.ready_at := public.fleet_patched(p_fleet, p_now);
  end if;
  if f.ready_at is not null and f.ready_at > p_now then
    return 'IN_PORT';
  end if;
  v_duty := public.pirates_on() and n.unpaid_since is null and n.ord <= public.pirate_size();

  if f.port_id is distinct from n.home_port then
    if v_duty and n.mission = 'CRUISE' and f.port_id = n.haunt_port then
      if n.haunt_since is null then
        update public.pirate_ships x set haunt_since = p_now where x.fleet_id = p_fleet;
        return 'HAUNT';
      end if;
      if p_now < n.haunt_since + make_interval(hours => public.wc_int('pirate_haunt_hours')) then
        return 'HAUNT';
      end if;
    end if;
    select c.course into v_course from public.npc_courses c where c.from_port = f.port_id and c.to_port = n.home_port;
    if v_course is null then
      return 'IDLE';   -- no stored course home from here: she stays
    end if;
    return public.pirate_sail(p_fleet, f.port_id, voyage.segments_from_course(v_course), n.home_port, null, null, 'HOME', p_now);
  end if;

  if not v_duty then
    perform public.fleet_mend(p_fleet);
    update public.pirate_ships x set laid_up_at = p_now, sea_id = null, haunt_port = null, haunt_since = null, mission = 'HOME' where x.fleet_id = p_fleet;
    return 'LAID_UP';
  end if;
  perform public.fleet_mend(p_fleet);   -- home: the Brethren mend her free, as a navy ship at her station
  select * into h from public.pirate_haunt_of(n.home_port, n.ord);
  if h.port_id is null then
    return 'IDLE';   -- no haunt in reach of this home: she lies there
  end if;
  return public.pirate_sail(p_fleet, f.port_id, voyage.segments_from_course(h.course), h.port_id, h.sea_id, h.port_id, 'CRUISE', p_now);
end
$$
  $f$;

  execute $f$
create function public.tick_pirates(p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0339: pg_cron byeharu-voyage:pirates, every minute, never in the beat. Each ship not at sea and past her port time takes her step, in a block of her own, at most navy_steps_per_run a run, turned by the minute so none starves;
-- then the sea's pressure (presence, lit; emptied, off), and, lit, one ship added and one hour paid: the capital's lock is held only to the commit. No ship, no switch: one knob read and one read of an empty table.
-- Answers {steps, pressure, added, paid}.
declare
  r       record;
  v_lit   boolean := public.pirates_on();
  v_turn  bigint := floor(extract(epoch from p_now) / 60)::bigint;
  v_max   int := public.wc_int('navy_steps_per_run');
  v_n     int := 0;
  v_steps jsonb := '{}'::jsonb;
  v_s     text;
  v_press int := 0;
  v_add   text;
  v_paid  bigint := 0;
begin
  for r in select n.fleet_id, n.ord from public.pirate_ships_at_work n join public.fleets f on f.id = n.fleet_id
            where f.status <> 'SAILING' and (f.ready_at is null or f.ready_at <= p_now)
            order by (n.ord + v_turn) % greatest(1, v_max), n.ord loop
    exit when v_n >= v_max;
    v_n := v_n + 1;
    begin
      v_s := public.pirate_ship_step(r.fleet_id, p_now);
      v_steps := v_steps || jsonb_build_object(v_s, coalesce((v_steps ->> v_s)::int, 0) + 1);
    exception when others then
      raise warning 'tick_pirates: fleet % stayed (SQLSTATE %: %)', r.fleet_id, sqlstate, sqlerrm;
      v_steps := v_steps || jsonb_build_object('ERROR', coalesce((v_steps ->> 'ERROR')::int, 0) + 1);
    end;
  end loop;
  if v_lit or exists (select 1 from public.sea_pressure) then
    begin
      v_press := public.pirate_pressure_write(p_now);
    exception when others then
      raise warning 'tick_pirates: the pressure stayed (SQLSTATE %: %)', sqlstate, sqlerrm;
    end;
  end if;
  if v_lit then
    begin
      v_add := public.pirate_add(p_now);
    exception when others then
      raise warning 'tick_pirates: no ship was added (SQLSTATE %: %)', sqlstate, sqlerrm;
    end;
    begin
      v_paid := public.pirate_pay_hour(p_now);
    exception when others then
      raise warning 'tick_pirates: nobody was paid (SQLSTATE %: %)', sqlstate, sqlerrm;
    end;
  end if;
  return jsonb_build_object('steps', v_steps, 'pressure', v_press, 'added', v_add, 'paid', v_paid);
end
$$
  $f$;

  execute $f$
create function world.pirate_ship_card(p_fleet uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- 0339: EVERYTHING A PLAYER MAY KNOW ABOUT ONE PIRATE SHIP, read at a tap, as world.navy_ship_card. Refuses E_NOT_FOUND for any fleet that is not one. `home` her port; `haunt` the harbour of this cruise while she is out;
-- `to` and `eta` while she sails; `mission` the server's word (HOME, CRUISE); laid up: `laid_up` true; `attack` only while attacks are lit. No purse, no id of a voyage.
declare
  n public.pirate_ships%rowtype;
  f public.fleets%rowtype;
  w record;
begin
  select x.* into n from public.pirate_ships x where x.fleet_id = p_fleet;
  if n.fleet_id is null then
    raise exception 'E_NOT_FOUND: there is no such pirate ship' using errcode = 'P0001';
  end if;
  select x.* into f from public.fleets x where x.id = p_fleet;
  select * into w from voyage.where_now(p_fleet);
  return jsonb_build_object(
    'fleet', jsonb_build_object('id', f.id, 'name', f.name, 'status', w.status, 'port', (select p.code from public.ports p where p.id = w.port_id)),
    'nation_code', (select x.code from public.nations x where x.id = public.pirate_nation()),
    'home', (select p.code from public.ports p where p.id = n.home_port),
    'haunt', (select p.code from public.ports p where p.id = n.haunt_port and n.mission = 'CRUISE'),
    'mission', n.mission,
    'laid_up', n.laid_up_at is not null,
    'to', (select p.code from public.voyages v join public.ports p on p.id = v.dest_port_id where v.id = w.voyage_id),
    'eta', w.eta,
    'ships', (select coalesce(jsonb_agg(world.ship_view(s.id) - array['id', 'water_t', 'food_t'] order by s.is_flagship desc, s.name), '[]'::jsonb)
                from public.ships s where s.fleet_id = p_fleet))
    || case when public.attack_on() then '{"attack": true}'::jsonb else '{}'::jsonb end;
end
$$
  $f$;
  comment on function world.pirate_ship_card(uuid) is '0339: one pirate ship, read at a tap: her home, her haunt, her mission, where she is bound, her hull. Refuses E_NOT_FOUND for any other fleet.';

  revoke all on function public.pirates_on() from public, anon, authenticated;
  revoke all on function public.pirate_nation() from public, anon, authenticated;
  revoke all on function public.pirate_capital() from public, anon, authenticated;
  revoke all on function public.pirate_hoard() from public, anon, authenticated;
  revoke all on function public.pirate_size_for(bigint) from public, anon, authenticated;
  revoke all on function public.pirate_size() from public, anon, authenticated;
  revoke all on function public.pirate_home_of(integer) from public, anon, authenticated;
  revoke all on function public.pirate_spend_room(timestamptz) from public, anon, authenticated;
  revoke all on function public.pirate_pay(text, bigint, timestamptz, uuid, uuid) from public, anon, authenticated;
  revoke all on function public.pirate_ship_in_sea(uuid) from public, anon, authenticated;
  revoke all on function voyage.pirate_strength(uuid) from public, anon, authenticated;
  revoke all on function voyage.freeze_raiders(jsonb, uuid) from public, anon, authenticated;
  revoke all on function voyage.leg_raider(jsonb) from public, anon, authenticated;
  revoke all on function voyage.plunder_share(uuid, integer, text) from public, anon, authenticated;
  revoke all on function public.pirate_stow(uuid, jsonb) from public, anon, authenticated;
  revoke all on function public.pirate_ransom(uuid, uuid, bigint, uuid) from public, anon, authenticated;
  revoke all on function public.pirate_loot_book(uuid, uuid, numeric, uuid) from public, anon, authenticated;
  revoke all on function public.pirate_pressure_write(timestamptz) from public, anon, authenticated;
  revoke all on function public.pirate_haunt_of(uuid, integer) from public, anon, authenticated;
  revoke all on function public.pirate_commission(integer, uuid, uuid, timestamptz) from public, anon, authenticated;
  revoke all on function public.pirate_add(timestamptz) from public, anon, authenticated;
  revoke all on function public.pirate_pay_hour(timestamptz) from public, anon, authenticated;
  revoke all on function public.pirate_sail(uuid, uuid, jsonb, uuid, uuid, uuid, text, timestamptz) from public, anon, authenticated;
  revoke all on function public.pirate_ship_step(uuid, timestamptz) from public, anon, authenticated;
  revoke all on function public.tick_pirates(timestamptz) from public, anon, authenticated;
  revoke all on function world.pirate_ship_card(uuid) from public, anon;
  grant execute on function world.pirate_ship_card(uuid) to authenticated;

  -- ── 5. THE HUNKS (each occurs exactly once in the live body, and reverses) ──
  create temp table hunks_0339 (fn text, ord int, old text, new text) on commit drop;
  insert into hunks_0339 values
  ('public.fleet_kind(uuid)', 1,
$h$              when exists (select 1 from public.navy_ships n where n.fleet_id = f.id) then 'NAVY'
$h$,
$h$              when exists (select 1 from public.navy_ships n where n.fleet_id = f.id) then 'NAVY'
              when exists (select 1 from public.pirate_ships n where n.fleet_id = f.id) then 'PIRATE'   -- 0339: after the navy test, so every other read is what it was
$h$),
  ('public.fleet_origin(uuid)', 1,
$h$                  (select n.station_port from public.navy_ships n where n.fleet_id = p_fleet))
$h$,
$h$                  (select n.station_port from public.navy_ships n where n.fleet_id = p_fleet),
                  (select n.home_port from public.pirate_ships n where n.fleet_id = p_fleet))   -- 0339: a pirate ship's home
$h$),
  ('public.crown_house(uuid)', 1,
$h$  select exists (select 1 from public.cargo_ships c where c.player_id = p_player) or exists (select 1 from public.navy_ships n where n.player_id = p_player)
$h$,
$h$  select exists (select 1 from public.cargo_ships c where c.player_id = p_player) or exists (select 1 from public.navy_ships n where n.player_id = p_player)
      or exists (select 1 from public.pirate_ships x where x.player_id = p_player)   -- 0339: a pirate ship's house too: no dock fee, no wage, no merchant in the count
$h$),
  ('public.crown_nation(uuid)', 1,
$h$                  (select n.nation_id from public.navy_ships n where n.fleet_id = p_fleet))
$h$,
$h$                  (select n.nation_id from public.navy_ships n where n.fleet_id = p_fleet),
                  (select public.pirate_nation() from public.pirate_ships x where x.fleet_id = p_fleet))   -- 0339: a pirate ship sails for the Brethren
$h$),
  ('public.sea_houses()', 1,
$h$          select y.player_id, y.nation_id, 'NAVY' from public.navy_ships_in_service y) c
$h$,
$h$          select y.player_id, y.nation_id, 'NAVY' from public.navy_ships_in_service y
          union all
          select z.player_id, public.pirate_nation(), 'PIRATE' from public.pirate_ships_at_work z) c   -- 0339: a pirate ship's house, kind PIRATE (the chart draws the kind, not the ink)
$h$),
  ('public.fleet_wage(uuid,boolean,integer)', 1,
$h$  if v_crew > 0 and public.fleet_kind(p_fleet) in ('CARGO_SHIP', 'NAVY') then   -- 0331: a navy ship's hands are paid by her upkeep too (public.navy_pay)
$h$,
$h$  if v_crew > 0 and public.fleet_kind(p_fleet) in ('CARGO_SHIP', 'NAVY', 'PIRATE') then   -- 0331: a navy ship's hands are paid by her upkeep too (public.navy_pay); 0339: a pirate ship's by the hoard (public.pirate_pay_hour)
$h$),
  ('public.cargo_figures()', 1,
$h$                 then jsonb_build_object('navy_ships', (select count(*) from public.navy_ships_in_service)) else '{}'::jsonb end
$h$,
$h$                 then jsonb_build_object('navy_ships', (select count(*) from public.navy_ships_in_service)) else '{}'::jsonb end
         || case when exists (select 1 from public.pirate_ships_at_work)   -- 0339: the Codex's pirate entry. No ship: nothing, so the read is what it was
                 then jsonb_build_object('pirate_ships', (select count(*) from public.pirate_ships_at_work)) else '{}'::jsonb end
$h$),
  ('public.client_rpc_entry_points()', 1,
$h$      ('world',       'navy_ship_card',        'uuid'),
$h$,
$h$      ('world',       'navy_ship_card',        'uuid'),
      -- 0339: one pirate ship's card, read at a tap.
      ('world',       'pirate_ship_card',      'uuid'),
$h$),
  ('voyage.raid_takes(uuid,integer,uuid,text)', 1,
$h$  if p_outcome = 'STRIPPED' then
    v_share := 1;
  elsif p_outcome = 'PLUNDERED' then
    v_share := public.wc_num('plunder_share_min') + public.wc_num('plunder_share_span') * voyage.rng(p_voyage, p_day, 'plunder');
  else
    return v_out;
  end if;
$h$,
$h$  v_share := voyage.plunder_share(p_voyage, p_day, p_outcome);   -- 0339: the one share, lifted, so a cargo ship's gold takes the same roll (public.pirate_loot_book)
  if v_share <= 0 then
    return v_out;
  end if;
$h$),
  ('voyage.depart(uuid,jsonb,uuid,uuid,timestamp with time zone)', 1,
$h$  values (p_fleet, v_player, voyage.freeze_danger(p_segments, p_at), v_total, v_profile, p_at,   -- 0330: each segment keeps the danger of its sea as she left
$h$,
$h$  values (p_fleet, v_player, voyage.freeze_raiders(voyage.freeze_danger(p_segments, p_at), p_fleet), v_total, v_profile, p_at,   -- 0330: each segment keeps the danger of its sea as she left; 0339: and the pirate ship cruising it, if any
$h$),
  ('voyage.settle(uuid,timestamp with time zone)', 1,
$h$  v_home    jsonb;     -- 0279: the ran-dry day's forced home (voyage.forced_home); null when she is not dry
begin
$h$,
$h$  v_home    jsonb;     -- 0279: the ran-dry day's forced home (voyage.forced_home); null when she is not dry
  v_leg     jsonb;     -- 0339: the day's frozen segment, read once for its danger and its raider
  v_pirate  uuid;      -- 0339: the pirate ship the segment names (voyage.leg_raider); null for an anonymous raid
  v_stow    jsonb;     -- 0339: what her home stowed (public.pirate_stow)
  v_ransom  bigint;    -- 0339: the ransom her home took (public.pirate_ransom)
  v_booked  bigint;    -- 0339: the gold she took from a cargo ship (public.pirate_loot_book)
begin
$h$),
  ('voyage.settle(uuid,timestamp with time zone)', 2,
$h$      v_raider := voyage.leg_danger(voyage.leg_at_day(v.id, d)) * 40 * (0.5 + h.magnitude);   -- 0330: the danger she departed into, frozen on the leg
$h$,
$h$      v_leg := voyage.leg_at_day(v.id, d);
      v_pirate := voyage.leg_raider(v_leg);   -- 0339: the pirate ship the frozen segment names, if any (docs/WORLD_POWERS.md 7.3)
      v_stow := null; v_ransom := 0; v_booked := 0;
      v_raider := case when v_pirate is null then voyage.leg_danger(v_leg) * 40 * (0.5 + h.magnitude)   -- 0330: the danger she departed into, frozen on the leg
                       else voyage.pirate_strength(v_pirate) end;   -- 0339: a named raider fights with her own hulls
$h$),
  ('voyage.settle(uuid,timestamp with time zone)', 3,
$h$      select coalesce(sum(sh.crew), 0) into v_crew1
        from public.ships sh where sh.fleet_id = p_fleet;
$h$,
$h$      select coalesce(sum(sh.crew), 0) into v_crew1
        from public.ships sh where sh.fleet_id = p_fleet;
      if v_pirate is not null and v_outcome = 'RANSOM' then   -- 0339: paid off a named raider: ransom_share of the cargo's cost basis, from the company's purse to her home (docs/WORLD_POWERS.md 7.3)
        v_ransom := public.pirate_ransom(v_pirate, f.player_id, public.fleet_stock_at_cost(p_fleet), null);
      end if;
$h$),
  ('voyage.settle(uuid,timestamp with time zone)', 4,
$h$        perform public.insurance_claim(v.id, d, v_taken, v_outcome);
      end if;
$h$,
$h$        perform public.insurance_claim(v.id, d, v_taken, v_outcome);
        if v_pirate is not null then   -- 0339: a named raider stows the goods at her home and takes a cargo ship's gold there (docs/WORLD_POWERS.md 7.3)
          v_stow := public.pirate_stow(v_pirate, v_taken);
          v_booked := public.pirate_loot_book(v_pirate, p_fleet, voyage.plunder_share(v.id, d, v_outcome), null);
        end if;
      end if;
$h$),
  ('voyage.settle(uuid,timestamp with time zone)', 5,
$h$                   -- 0213: the units the raiders carried off, when they took any
                   || case when coalesce(v_taken, '{}'::jsonb) = '{}'::jsonb then '{}'::jsonb
                           else jsonb_build_object('cargo_lost', v_taken) end
$h$,
$h$                   -- 0213: the units the raiders carried off, when they took any
                   || case when coalesce(v_taken, '{}'::jsonb) = '{}'::jsonb then '{}'::jsonb
                           else jsonb_build_object('cargo_lost', v_taken) end
                   -- 0339: the pirate ship that raided, and what her home took; absent on an anonymous day, so that payload is what it was
                   || case when v_pirate is null then '{}'::jsonb
                           else jsonb_build_object('pirate', jsonb_build_object('fleet', v_pirate, 'name', (select f2.name from public.fleets f2 where f2.id = v_pirate),
                                                     'home', (select p2.code from public.pirate_ships n2 join public.ports p2 on p2.id = n2.home_port where n2.fleet_id = v_pirate),
                                                     'stowed', coalesce(v_stow, '{}'::jsonb), 'ransom', v_ransom, 'booked', v_booked)) end
$h$),
  ('public.attack_for(uuid,uuid,uuid,integer,timestamp with time zone)', 1,
$h$  if v_kind not in ('CARGO_SHIP', 'NAVY') then   -- 0333: owner: players may attack navy ships
$h$,
$h$  if v_kind not in ('CARGO_SHIP', 'NAVY', 'PIRATE') then   -- 0333: owner: players may attack navy ships; 0339: and pirate ships (docs/WORLD_POWERS.md 7.3)
$h$),
  ('public.attack_for(uuid,uuid,uuid,integer,timestamp with time zone)', 2,
$h$  perform public.regard_add(p_player, v_nation, public.wc_num(case when v_kind = 'NAVY' then 'regard_attack_navy' else 'regard_attack_cargo' end),
                             case when v_kind = 'NAVY' then 'ATTACK_NAVY' else 'ATTACK_CARGO' end);
$h$,
$h$  perform public.regard_add(p_player, v_nation, public.wc_num(case when v_kind = 'NAVY' then 'regard_attack_navy' when v_kind = 'PIRATE' then 'regard_pirate' else 'regard_attack_cargo' end),
                             case when v_kind = 'NAVY' then 'ATTACK_NAVY' when v_kind = 'PIRATE' then 'ATTACK_PIRATE' else 'ATTACK_CARGO' end);   -- 0339: with the Brethren, for a pirate ship
$h$),
  ('public.attack_close(uuid,jsonb,timestamp with time zone)', 1,
$h$  if v_out in ('PLUNDERED', 'RANSOM') or not public.navy_arrived(p_battle, c.nation_id, v_d) then
$h$,
$h$  if not public.pirate_power(c.nation_id) and (v_out in ('PLUNDERED', 'RANSOM') or not public.navy_arrived(p_battle, c.nation_id, v_d)) then   -- 0339: the pirates keep no wanted list: they have no navy to answer
$h$),
  ('public.tick_market_drift(timestamp with time zone,uuid)', 1,
$h$  v_n      int;
  v_regen  int;
begin
$h$,
$h$  v_n      int;
  v_regen  int;
  v_pir    boolean := public.pirates_on();   -- 0339: with the pirates lit, a pirate home's stock is plunder, not production (docs/WORLD_POWERS.md 7.6)
begin
$h$),
  ('public.tick_market_drift(timestamp with time zone,uuid)', 2,
$h$           public.depth_mult(po.id) as depth   -- 0252 (E5b): the day's max-stock multiple (null: the max as it stands)
      from public.ports po
$h$,
$h$           public.depth_mult(po.id) as depth,   -- 0252 (E5b): the day's max-stock multiple (null: the max as it stands)
           case when v_pir then public.port_is_free(po.id) else false end as held   -- 0339: a free port's stock is left alone while the pirates are lit; dark, one constant and no call
      from public.ports po
$h$),
  ('public.tick_market_drift(timestamp with time zone,uuid)', 3,
$h$         stock = case when pg.last_regen_day < v_day then public.depth_stock($h$,
$h$         stock = case when pg.last_regen_day < v_day and not f.held then public.depth_stock($h$);

  for v_h in select h.fn from hunks_0339 h group by h.fn order by h.fn loop
    v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
    v_pre := v_def;
    declare
      x record;
    begin
      for x in select * from hunks_0339 h where h.fn = v_h.fn order by h.ord loop
        v_n := (length(v_def) - length(replace(v_def, x.old, ''))) / length(x.old);
        if v_n <> 1 then
          raise exception '0339 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', x.ord, x.fn, v_n;
        end if;
        v_def := replace(v_def, x.old, x.new);
      end loop;
      execute v_def;
      v_def := replace(pg_get_functiondef(v_h.fn::regprocedure), E'\r', '');
      for x in select * from hunks_0339 h where h.fn = v_h.fn order by h.ord desc loop
        v_n := (length(v_def) - length(replace(v_def, x.new, ''))) / length(x.new);
        if v_n <> 1 then
          raise exception '0339 self-assert FAIL: hunk % of % is not in the new body once', x.ord, x.fn;
        end if;
        v_def := replace(v_def, x.new, x.old);
      end loop;
      if v_def <> v_pre then
        raise exception '0339 self-assert FAIL: % does not reverse to its pre-image', v_h.fn;
      end if;
    end;
  end loop;

  -- ── 6. THE JOB ──
  if to_regclass('cron.job') is not null then
    execute $q$select cron.schedule('byeharu-voyage:pirates', '* * * * *', 'select public.tick_pirates()')$q$;
  end if;

  -- ── 7. THE SELF-ASSERT: the catalog, stable reads and arithmetic. No game step, no live digest. ──
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid::regprocedure::text <> all (array(select x::regprocedure::text from unnest(c_hunked || c_new_fns) x))) <> v_fn_before then
    raise exception '0339 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key <> all (c_keys)) <> v_cfg_before then
    raise exception '0339 self-assert FAIL: a world_config row moved';
  end if;
  if (select md5(string_agg(w.kind || ':' || w.side || ':' || w.word || ':' || w.ord, ',' order by w.kind)) from public.stats_flow_words w where w.kind <> all (c_words)) <> v_words_before then
    raise exception '0339 self-assert FAIL: a flow word moved';
  end if;
  if (select count(*) from public.stats_flow_words w where w.kind = any (c_words) and w.side = 'moved') <> 1 then
    raise exception '0339 self-assert FAIL: RANSOM is not a moved word';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid::regprocedure::text = any (array(select x::regprocedure::text from unnest(c_hunked) x))) <> v_meta_before then
    raise exception '0339 self-assert FAIL: the ACL, volatility, definer or config of a hunked function moved';
  end if;
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.command || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j where j.jobname <> 'byeharu-voyage:pirates'$q$ into v_cron_after;
    if v_cron_after is distinct from v_cron_before then
      raise exception '0339 self-assert FAIL: another cron job moved';
    end if;
    execute $q$select count(*) from cron.job j where j.jobname = 'byeharu-voyage:pirates' and j.schedule = '* * * * *' and j.command = 'select public.tick_pirates()' and j.active$q$ into v_n;
    if v_n <> 1 then
      raise exception '0339 self-assert FAIL: the job is not scheduled';
    end if;
  end if;
  if (select c.value from public.world_config c where c.key = 'pirates_bite') <> 'false'::jsonb then
    raise exception '0339 self-assert FAIL: the switch is not off';
  end if;
  if exists (select 1 from public.pirate_ships) or exists (select 1 from public.pirate_spend_day)
     or (select count(*) from public.pirate_clock c where c.one and c.added_at is null and c.paid_at is null) <> 1 or (select count(*) from public.pirate_clock) <> 1
     or (select count(*) from public.sea_pressure) <> v_pressure_before then
    raise exception '0339 self-assert FAIL: a row was written dark';
  end if;
  v_class := (select c.value #>> '{}' from public.world_config c where c.key = 'pirate_ship_class');   -- from the table: the planner folds a STABLE read on this block's older snapshot
  if v_class is distinct from (select c.value #>> '{}' from public.world_config c where c.key = 'fight_raider_class')
     or not exists (select 1 from public.ship_classes k where k.code = v_class and k.attack > 0 and k.crew_required > 0 and k.build_cost > 0) then
    raise exception '0339 self-assert FAIL: pirate_ship_class is not the raider''s armed class with a price';
  end if;
  -- The formula on probe hoards, docs/WORLD_POWERS.md 7.3, with the knobs as they ship. Arithmetic only.
  if (select string_agg(public.pirate_size_for(x)::text, ',' order by x)
        from unnest(array[-5, 0, 99999999, 100000000, 993000000, 2600000000, 10000000000]::bigint[]) x) <> '4,4,4,5,13,30,30' then
    raise exception '0339 self-assert FAIL: the size formula: %', (select string_agg(public.pirate_size_for(x)::text, ',' order by x)
        from unnest(array[-5, 0, 99999999, 100000000, 993000000, 2600000000, 10000000000]::bigint[]) x);
  end if;
  -- Dark, the freeze is the identity: a probe path comes back byte for byte; a leg with no raider reads null; no sea has a ship; the lifted share is the old arithmetic on a probe voyage id
  v_probe := jsonb_build_array(jsonb_build_object('a', jsonb_build_array(1, 2), 'b', jsonb_build_array(3, 4), 'nm', 10, 'sea_id', (select s.id from public.seas s order by s.code limit 1), 'danger', 0.1234),
                               jsonb_build_object('a', jsonb_build_array(3, 4), 'b', jsonb_build_array(5, 6), 'nm', 20, 'sea_id', (select s.id from public.seas s order by s.code desc limit 1)));
  if voyage.freeze_raiders(v_probe, gen_random_uuid())::text <> v_probe::text or voyage.leg_raider(v_probe -> 0) is not null
     or voyage.leg_raider(jsonb_build_object('raider', '00000000-0339-4000-8000-000000000001')) <> '00000000-0339-4000-8000-000000000001'::uuid
     or (select count(*) from public.seas s where public.pirate_ship_in_sea(s.id) is not null) <> 0 then
    raise exception '0339 self-assert FAIL: dark, the freeze is not the identity or a reader answers a ship';
  end if;
  if voyage.plunder_share('00000000-0339-4000-8000-000000000002', 3, 'STRIPPED') <> 1 or voyage.plunder_share('00000000-0339-4000-8000-000000000002', 3, 'EVADED') <> 0
     or voyage.plunder_share('00000000-0339-4000-8000-000000000002', 3, 'PLUNDERED')
        <> public.wc_num('plunder_share_min') + public.wc_num('plunder_share_span') * voyage.rng('00000000-0339-4000-8000-000000000002', 3, 'plunder') then
    raise exception '0339 self-assert FAIL: voyage.plunder_share is not 0213''s arithmetic';
  end if;
  if public.pirate_spend_room(now()) <> greatest(0, floor(public.pirate_hoard() * public.wc_num('pirate_spend_day_pct')))::bigint or public.pirate_capital() is null or public.pirate_home_of(1) <> public.pirate_capital() then
    raise exception '0339 self-assert FAIL: the room, the capital or the first home';
  end if;
  if (select string_agg(p.provolatile::text, '' order by p.oid::regprocedure::text) from pg_proc p
       where p.oid = any (array['public.pirates_on()'::regprocedure, 'public.pirate_nation()'::regprocedure, 'public.pirate_capital()'::regprocedure, 'public.pirate_hoard()'::regprocedure,
                                'public.pirate_size_for(bigint)'::regprocedure, 'public.pirate_size()'::regprocedure, 'public.pirate_home_of(integer)'::regprocedure, 'public.pirate_spend_room(timestamptz)'::regprocedure,
                                'public.pirate_ship_in_sea(uuid)'::regprocedure, 'voyage.pirate_strength(uuid)'::regprocedure, 'voyage.freeze_raiders(jsonb,uuid)'::regprocedure, 'voyage.leg_raider(jsonb)'::regprocedure,
                                'voyage.plunder_share(uuid,integer,text)'::regprocedure, 'public.pirate_haunt_of(uuid,integer)'::regprocedure, 'world.pirate_ship_card(uuid)'::regprocedure]::oid[])) <> 'sssssssssssssss' then
    raise exception '0339 self-assert FAIL: a read is not stable';
  end if;
  if exists (select 1 from unnest(c_new_fns) f
              where f <> 'world.pirate_ship_card(uuid)' and (has_function_privilege('anon', f::regprocedure, 'execute') or has_function_privilege('authenticated', f::regprocedure, 'execute'))) then
    raise exception '0339 self-assert FAIL: a new function can be called from a client';
  end if;
  if not has_function_privilege('authenticated', 'world.pirate_ship_card(uuid)', 'execute') or has_function_privilege('anon', 'world.pirate_ship_card(uuid)', 'execute') then
    raise exception '0339 self-assert FAIL: the card is not exactly authenticated-only';
  end if;
  if (select count(*) from public.client_rpc_entry_points() e where e.function_name = 'pirate_ship_card' and e.fn is not null) <> 1 then
    raise exception '0339 self-assert FAIL: the card is not registered';
  end if;
  if has_table_privilege('authenticated', 'public.pirate_ships', 'select') or has_table_privilege('anon', 'public.pirate_ships', 'select')
     or has_table_privilege('authenticated', 'public.pirate_ships_at_work', 'select') or has_table_privilege('authenticated', 'public.pirate_spend_day', 'select')
     or has_table_privilege('authenticated', 'public.pirate_ships_cruising', 'select') or has_table_privilege('anon', 'public.pirate_ships_cruising', 'select') then
    raise exception '0339 self-assert FAIL: a client can read a pirate table';
  end if;
  -- the one rule of "she is in a sea" is read by exactly its two readers, and the stow locks the market row alone (never the goods catalogue, inside the beat)
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prosrc like '%pirate_ships_cruising%') <> 2
     or (select p.prosrc from pg_proc p where p.oid = 'public.pirate_stow(uuid,jsonb)'::regprocedure) !~ 'for update of pg;'
     or (select p.prosrc from pg_proc p where p.oid = 'public.pirate_stow(uuid,jsonb)'::regprocedure) ~ 'for update;' then
    raise exception '0339 self-assert FAIL: the cruising rule has a third reader, or the stow locks more than the market row';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0339 self-assert FAIL: the self-assert took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0339 self-assert ok: PIRATE SHIPS SAIL, dark behind pirates_bite. % hunks once each and reversing over % bodies; % new functions; % knobs and the word RANSOM; no other function, knob, word or job; no row written; no game step ran (proof 46 runs them in CI). % ms.',
    (select count(*) from hunks_0339), (select count(distinct h.fn) from hunks_0339 h), cardinality(c_new_fns), cardinality(c_keys), round(extract(epoch from clock_timestamp() - v_t0) * 1000);
  drop table hunks_0339;
end
$m$;
