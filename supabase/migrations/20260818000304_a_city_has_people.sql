-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0304 — A CITY HAS PEOPLE   (a real-world population per harbour; it grows, holds or shrinks every 10 minutes; it pays its city a daily tax)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── THE ORDERS (owner, 2026-11-04) ──────────────────────────────────────────────────────────────
--   1. "set population on cities, based on real life. Then with that population, they will provide gold to that city they reside in.
--      So the cities will create money on its own."
--   2. "the population will change too, every 10 minute it will grow, stay still, or diminish. grow - invested alot. stay still - nothing
--      unusual, diminish - war, famine, etc. Set up a mechanism of population and its growth rate."
--   Design, figures, prod measurements and the population table: docs/dev-log/2026-11-04-city-population.md.
--
-- ── WHAT THIS FILE ADDS ─────────────────────────────────────────────────────────────────────────
--   public.port_population (one row per harbour): the AUTHORED real-world figure c. 1650 (`baseline`, `year`, `confidence`, `note` — from
--     data/port-population.json, written by scripts/build-population.mjs; the world guard holds the two equal) and the STATE: `population`
--     (starts at baseline), the last 10-minute step (`slot`, `kind` GROW/HOLD/SHRINK, `reason`), and `paid_day` (the last UTC day its tax was paid).
--   public.population_log: one row per harbour per step, kept population_log_slots steps (a day), the trend's history. Trimmed every step.
--   public.population_signal_weights: THE weights of the signals, as rows (INVEST +1, FAMINE -1, WAR -1; PIRATES and STORM rows wait for a source).
--   Knobs (world_config): population_tax_per_1000, population_tax_exponent, population_step_base, population_step_max, population_hold_band,
--     population_floor_ratio, population_ceiling_ratio, population_invest_full, population_famine_stock_frac, population_staple_categories,
--     population_log_slots.
--   Functions (all server-only):
--     public.population_rule(pop, baseline, score)  THE growth rule: the next population and the step's kind. Reads the knobs, nothing else.
--     public.population_signals()                   THE signals, one row per (harbour, signal, value 0..1), from real game state only:
--                                                     INVEST  port_treasury.invested (0245's 72-hour-half-life stock of SHARE + DONATION)
--                                                             against population_invest_full x (population/1000)^exponent;
--                                                     FAMINE  the share of the harbour's staple goods (population_staple_categories) whose stock
--                                                             is under population_famine_stock_frac of its target;
--                                                     WAR     the share of the harbour's influence points held by nations at war with its holder
--                                                             (public.power_relations, port_allegiance, port_influence).
--                                                   PIRATES and STORM have weight rows but NO SOURCE YET (no live pirate pressure exists —
--                                                   docs/PIRATES_AND_HAVENS.md is design only — and voyage_events has no time index to read
--                                                   storms per city cheaply). A future file adds one UNION branch here; the weights already count it.
--     public.city_population_income(port)           THE daily tax: round(population_tax_per_1000 x (population/1000)^population_tax_exponent).
--     public.population_tick(now)                   THE 10-minute job: (1) the step, ONE set-based UPDATE over every harbour, idempotent per
--                                                   10-minute slot; (2) the log row per step and the trim; (3) once per UTC day, the tax, through
--                                                   public.treasury_post, kind POPULATION_TAX, reading the CURRENT population.
--     public.town_hall_people(port)                 the hall's `people` block: population, baseline, per_day, kind, reason, day_change.
--   The cron job byeharu-voyage:population at minutes 5,15,25,35,45,55 (its OWN job: nothing is added to the arrivals or other hot beats),
--   scheduled INACTIVE like every job since 0078; wind_the_clock() starts it.
--
-- ── NEW MONEY, AND THE ONE EXCEPTION IN THE GUARD (mirrors 0302) ─────────────────────────────────
--   The tax is new money, so it is a MINTED kind: stats_flow_words POPULATION_TAX, 'minted', 'New money: population tax', ord 9 — Stats shows
--   it as new money. The economy is closed on prod, so public.mint_guard would refuse it (E_NO_NEW_GOLD). It gains ONE exception, nothing else:
--   kind POPULATION_TAX passes while the transaction-local setting byeharu.population_tax = 'on'. Only public.population_tick sets it, around
--   its daily pay loop, and puts it back to 'off'. Every other minted kind stays refused whatever the setting; POPULATION_TAX stays refused
--   whenever the setting is not 'on'. The guard still takes THE MINT GATE (0268) before it judges. treasury_post and mint_guard are server-only,
--   so no client can reach the setting. The tax goes through public.treasury_post, the one writer of a purse; its 0224 hook moves the live
--   Stats 'cities' figure in the same transaction.
--
-- ── SUPERSEDES (two functions, by hunks; each occurs exactly once and reverses to its pre-image) ───────────
--   public.mint_guard   0302's body (md5 64b7dab34e750c340a41ccffd7d87143) + one comment line + one early return for POPULATION_TAX.
--   world.town_hall     0278's body (md5 09d21ee2e5c5e3270351c5dab0b53d66) + `|| public.town_hall_people(p_port)` at the end.
--   Both md5s were read from prod (head 0303) on 2026-11-04. Nothing else moves: every other function md5, every existing world_config row,
--   every existing cron job (asserted).
--
-- ── HOW TO TURN IT OFF (owner) ──────────────────────────────────────────────────────────────────
--   The tax:   update public.world_config set value = '0' where key = 'population_tax_per_1000';   (income 0: nothing is posted)
--   The steps: update public.world_config set value = '0' where key = 'population_step_base';      (every step HOLDs, population frozen)
--
-- ── BUDGET (docs/OPS_HEALTH.md section 4) ───────────────────────────────────────────────────────
--   ONE DO block (the runner is not a transaction block). statement_timeout 90 s, lock_timeout 5 s first. Work: 3 small tables, 246 seed rows,
--   12 knob rows, 7 functions, 2 hunked re-cuts, one cron row, catalog reads. The self-assert runs no game step and reads no live rows beyond
--   the seed: the rule is tested on literals, the tax formula on the seeded figures, the guard in a rolled-back probe. The tick itself — the
--   step, the slot, the floor and ceiling, the daily pay, the books — is proven in CI by scripts/db/proofs/14_city_population.sql.
--
-- ROLLBACK (forward, a NEW migration, owner only): the two knobs above to 0 stop everything without a migration. Removing it: unschedule the
--   job, reverse the two hunks, drop the five functions and three tables; the POPULATION_TAX flows are history and stay.
-- VERSION: 0304 - prod head 0303 (2026-11-04).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_guard_0302 constant text := '64b7dab34e750c340a41ccffd7d87143';  -- md5 of pg_get_functiondef(public.mint_guard), LF, as 0302 left it (prod head 0303)
  c_hall_0278  constant text := '09d21ee2e5c5e3270351c5dab0b53d66';  -- md5 of pg_get_functiondef(world.town_hall), LF, prod head 0303
  c_new_fns    constant text[] := array['public.population_rule(numeric,numeric,numeric)', 'public.population_signals()',
                                         'public.city_population_income(uuid)', 'public.population_tick(timestamp with time zone)',
                                         'public.town_hall_people(uuid)'];
  -- the hunks
  h_mg1_old constant text := $h$-- Every other minted kind is refused whatever the setting; OWNER_GRANT is refused whenever the setting is not 'on'.
$h$;
  h_mg1_new constant text := $h$-- Every other minted kind is refused whatever the setting; OWNER_GRANT is refused whenever the setting is not 'on'.
-- 0304: THE SECOND EXCEPTION (owner's order of 2026-11-04, a city's people pay it a tax): kind POPULATION_TAX passes while
-- byeharu.population_tax = 'on', a transaction-local setting that public.population_tick alone sets around its daily pay and puts back.
$h$;
  h_mg2_old constant text := $h$    if p_kind = 'OWNER_GRANT' and coalesce(current_setting('byeharu.owner_grant', true), '') = 'on' then
      return;
    end if;
$h$;
  h_mg2_new constant text := $h$    if p_kind = 'OWNER_GRANT' and coalesce(current_setting('byeharu.owner_grant', true), '') = 'on' then
      return;
    end if;
    if p_kind = 'POPULATION_TAX' and coalesce(current_setting('byeharu.population_tax', true), '') = 'on' then
      return;
    end if;
$h$;
  h_th_old constant text := $h$    || public.port_dues(p_port, v_player, null);
$h$;
  h_th_new constant text := $h$    || public.port_dues(p_port, v_player, null)
    -- 0304: the city's people — its population, its daily tax, the last 10-minute step and why (public.town_hall_people).
    || public.town_hall_people(p_port);
$h$;
  v_def           text;
  v_mg_before     text;
  v_th_before     text;
  v_acl_mg        text;
  v_acl_th        text;
  v_fn_before     text;
  v_cfg_before    text;
  v_cron_before   text;
  v_tp_before     text;
  v_n             int;
  v_total         bigint;
  v_tax           bigint;
  v_lon           bigint;
  v_closed        jsonb;
  v_lit           jsonb;
  r               record;
  v_errm          text;
  v_t0            timestamptz := clock_timestamp();
begin
  perform set_config('statement_timeout', '90s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD: not applied; the pieces are the ones this file was cut against ──
  if to_regprocedure('public.mint_guard(text,bigint)') is null or to_regprocedure('public.treasury_post(uuid,text,bigint,uuid,uuid,boolean)') is null
     or to_regprocedure('world.town_hall(uuid)') is null or to_regprocedure('public.port_dues(uuid,uuid,numeric)') is null
     or to_regclass('public.stats_flow_words') is null or to_regclass('public.port_treasury') is null or to_regclass('public.port_influence') is null
     or to_regclass('public.power_relations') is null or to_regclass('public.port_allegiance') is null
     or not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'port_treasury' and column_name = 'invested') then
    raise exception '0304 refuses: the purse, guard, hall, influence or invested machinery (0122 / 0144 / 0196 / 0240 / 0245 / 0302) is not in this world';
  end if;
  if to_regclass('public.port_population') is not null or exists (select 1 from public.stats_flow_words where kind = 'POPULATION_TAX')
     or exists (select 1 from public.world_config where key like 'population\_%') then
    raise exception '0304 refuses: it has been applied once';
  end if;
  v_mg_before := replace(pg_get_functiondef('public.mint_guard(text,bigint)'::regprocedure), E'\r', '');
  v_th_before := replace(pg_get_functiondef('world.town_hall(uuid)'::regprocedure), E'\r', '');
  if md5(v_mg_before) <> c_guard_0302 then
    raise exception '0304 refuses: the live public.mint_guard is not the body this file was cut against (md5 %)', md5(v_mg_before);
  end if;
  if md5(v_th_before) <> c_hall_0278 then
    raise exception '0304 refuses: the live world.town_hall is not the body this file was cut against (md5 %)', md5(v_th_before);
  end if;
  select coalesce(p.proacl::text, '') into v_acl_mg from pg_proc p where p.oid = 'public.mint_guard(text,bigint)'::regprocedure;
  select coalesce(p.proacl::text, '') into v_acl_th from pg_proc p where p.oid = 'world.town_hall(uuid)'::regprocedure;

  -- what must not move (read once, compared after)
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid not in ('public.mint_guard(text,bigint)'::regprocedure, 'world.town_hall(uuid)'::regprocedure);
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before from public.world_config c;
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j$q$ into v_cron_before;
  end if;
  v_tp_before := md5(replace(pg_get_functiondef('public.treasury_post(uuid,text,bigint,uuid,uuid,boolean)'::regprocedure), E'\r', ''));

  -- ── 1. THE TABLES ──
  create table public.port_population (
    port_id    uuid primary key references public.ports(id) on delete cascade,
    baseline   integer not null check (baseline > 0),
    year       integer not null check (year between 1400 and 1950),
    confidence text not null check (confidence in ('A', 'B', 'C', 'L', 'N')),
    note       text not null default '',
    population numeric(14, 3) not null check (population > 0),
    slot       bigint,
    kind       text check (kind in ('GROW', 'HOLD', 'SHRINK')),
    reason     text,
    paid_day   integer,
    updated_at timestamptz not null default now()
  );
  comment on table public.port_population is
    '0304: one row per harbour. AUTHORED: baseline (the real-world townspeople c. 1650, rounded), year, confidence (A count / B estimate / C thin / L later founding / N analogue), note — from data/port-population.json (scripts/build-population.mjs), held equal by the world guard. STATE: population (starts at baseline; moved only by public.population_tick, within population_floor_ratio..population_ceiling_ratio x baseline), the last 10-minute step (slot = epoch / 600, kind, reason) and paid_day (UTC day number of the last tax).';
  alter table public.port_population enable row level security;
  revoke all on table public.port_population from public, anon, authenticated;

  create table public.population_log (
    port_id    uuid not null references public.ports(id) on delete cascade,
    slot       bigint not null,
    population numeric(14, 3) not null,
    kind       text not null check (kind in ('GROW', 'HOLD', 'SHRINK')),
    reason     text,
    primary key (port_id, slot)
  );
  create index population_log_slot on public.population_log (slot);
  comment on table public.population_log is
    '0304: one row per harbour per 10-minute step (public.population_tick), kept population_log_slots steps; the trim is by slot (index population_log_slot). The hall reads the day''s change from it.';
  alter table public.population_log enable row level security;
  revoke all on table public.population_log from public, anon, authenticated;

  create table public.population_signal_weights (
    code   text primary key check (code ~ '^[A-Z_]+$'),
    weight numeric not null,
    source text not null check (length(source) > 12)
  );
  comment on table public.population_signal_weights is
    '0304: THE weight of each population signal (score = sum of weight x value, value 0..1 from public.population_signals). Positive grows, negative shrinks. A row whose signal has no source yet counts nothing until a source emits it.';
  alter table public.population_signal_weights enable row level security;
  revoke all on table public.population_signal_weights from public, anon, authenticated;

  insert into public.population_signal_weights (code, weight, source) values
    ('INVEST',   1.0, 'port_treasury.invested (0245: SHARE + DONATION, 72-hour half-life) / (population_invest_full x (population/1000)^population_tax_exponent), capped at 1'),
    ('FAMINE',  -1.0, 'share of the harbour''s staple goods (population_staple_categories) whose port_goods.stock is under population_famine_stock_frac x stock_target'),
    ('WAR',     -1.0, 'share of the harbour''s influence points (port_influence) held by nations at war with its holder (port_allegiance, power_relations)'),
    ('PIRATES', -1.0, 'NO SOURCE YET: no live pirate pressure exists (docs/PIRATES_AND_HAVENS.md is design only); a future branch of population_signals emits it'),
    ('STORM',   -0.5, 'NO SOURCE YET: voyage_events records storms but has no time index to read them per city cheaply; a future branch emits it');

  -- ── 2. THE SEED (data/port-population.json, by harbour code) ──
  insert into public.port_population (port_id, baseline, year, confidence, note, population)
  select p.id, v.pop, v.yr, v.conf, v.note, v.pop
    from (values
      ('ACA', 4000, 1650, 'B', 'galleon port; swelled several-fold during the Manila galleon fair'),
      ('ACC', 5000, 1650, 'C', 'Ga towns beside the European forts'),
      ('ADE', 10000, 1650, 'C', 'much shrunk since its medieval height'),
      ('AGA', 3000, 1650, 'C', 'Santa Cruz do Cabo, a small Saadian port after the Portuguese left (1541)'),
      ('ALE', 20000, 1650, 'B', 'Ottoman Alexandria in decline (estimates 8,000-50,000)'),
      ('ALG', 80000, 1650, 'B', 'the corsair capital at its height (estimates 60,000-100,000+)'),
      ('AMB', 6000, 1650, 'C', 'Dutch Fort Victoria and town'),
      ('AMS', 175000, 1650, 'A', ''),
      ('ANC', 20000, 1650, 'B', ''),
      ('ANG', 10000, 1650, 'B', 'the chief town of the Azores'),
      ('ANT', 10000, 1650, 'C', ''),
      ('ARP', 65000, 1650, 'A', 'down from 100,000 in 1560 after the Scheldt was closed'),
      ('ARI', 2000, 1650, 'C', 'silver port of Potosi'),
      ('ARK', 5000, 1650, 'C', 'Russia''s only sea port to the west'),
      ('AST', 150, 1813, 'L', 'Fort Astoria, founded 1811'),
      ('AUK', 3000, 1845, 'L', 'founded 1840'),
      ('AYU', 150000, 1650, 'B', 'Siam''s capital; estimates up to 200,000'),
      ('BAN', 50000, 1650, 'C', 'capital of the Aceh sultanate'),
      ('BND', 3000, 1650, 'C', 'Dutch perkenier settlement after the 1621 conquest'),
      ('BAS', 15000, 1650, 'C', 'Gombroon, Persia''s port after Hormuz fell (1622)'),
      ('BNT', 70000, 1650, 'C', 'the Banten sultanate''s pepper port'),
      ('BAR', 40000, 1650, 'B', ''),
      ('NAV', 200, 1650, 'C', 'the 1564 Legazpi departure port; little more than a landing by 1650'),
      ('BSR', 40000, 1650, 'C', 'Ottoman Basra'),
      ('BEI', 6000, 1650, 'C', ''),
      ('BEL', 2000, 1650, 'C', 'founded 1616'),
      ('BER', 14000, 1650, 'A', 'Norway''s largest town'),
      ('BIL', 10000, 1650, 'B', ''),
      ('BOR', 45000, 1650, 'B', ''),
      ('BOS', 3000, 1650, 'A', ''),
      ('BRI', 3000, 1650, 'C', 'the island of Barbados held ~40,000; its town far fewer'),
      ('BRS', 20000, 1650, 'B', ''),
      ('BRU', 30000, 1650, 'B', ''),
      ('BUV', 300, 1650, 'C', 'a river landing, abandoned and refounded more than once'),
      ('BUE', 4000, 1650, 'B', ''),
      ('BUS', 15000, 1650, 'C', 'Dongnae town and the Japan House (Waegwan)'),
      ('CAD', 30000, 1650, 'B', 'rising toward 40,000 by 1700'),
      ('CAG', 20000, 1650, 'B', ''),
      ('CAL', 5000, 1650, 'C', 'Efik towns of Old Calabar'),
      ('CLS', 8000, 1650, 'B', ''),
      ('CLL', 5000, 1650, 'B', 'the port alone; Lima (~25,000) lies inland'),
      ('CAP', 3000, 1650, 'C', ''),
      ('CPT', 1500, 1700, 'L', 'founded 1652 by the VOC'),
      ('CAR', 10000, 1650, 'B', ''),
      ('CEB', 3000, 1650, 'C', 'Spanish town and its Parian'),
      ('CEU', 4000, 1650, 'C', 'a garrison town'),
      ('CHE', 20000, 1650, 'C', 'Madras, founded 1639; ~40,000 by the 1670s'),
      ('CHS', 15000, 1650, 'C', 'the town; the island held more'),
      ('CHI', 20000, 1650, 'C', 'the Arakanese port'),
      ('CID', 2000, 1650, 'C', 'Ribeira Grande, in decline'),
      ('COL', 8000, 1650, 'C', 'Portuguese Colombo before the Dutch siege (1656)'),
      ('CON', 2000, 1650, 'C', 'at Penco'),
      ('COP', 30000, 1650, 'A', ''),
      ('COQ', 1000, 1650, 'C', 'La Serena and its anchorage'),
      ('COR', 12000, 1650, 'C', 'the Venetian town; the island held more'),
      ('CRK', 6000, 1650, 'B', ''),
      ('CUM', 2000, 1650, 'C', ''),
      ('DAR', 500, 1871, 'L', 'founded 1869 as Palmerston'),
      ('DIL', 1000, 1650, 'N', 'a small Timorese coastal settlement; analogue: Kupang'),
      ('DIU', 10000, 1650, 'C', 'Portuguese Diu'),
      ('DUB', 20000, 1650, 'B', 'after the 1650 plague; ~45,000 by 1680'),
      ('DBR', 6000, 1650, 'B', 'the city; the republic held ~30,000'),
      ('REA', 1000, 1650, 'C', ''),
      ('ELM', 12000, 1650, 'C', 'the town beside the castle'),
      ('FAM', 2000, 1650, 'C', 'much reduced under the Ottomans'),
      ('FEO', 40000, 1650, 'C', 'Ottoman Kefe; travellers'' figures run far higher'),
      ('FRE', 500, 1832, 'L', 'founded 1829'),
      ('FUK', 40000, 1650, 'C', 'Hakata and the Fukuoka castle town together'),
      ('FNC', 10000, 1650, 'B', ''),
      ('FUZ', 200000, 1650, 'C', 'Fujian''s provincial capital; estimates vary widely'),
      ('GAL', 5000, 1650, 'C', ''),
      ('GDA', 70000, 1650, 'A', ''),
      ('GOA', 75000, 1650, 'B', 'before the 1656 plague'),
      ('GIB', 4000, 1650, 'B', 'the Spanish town before 1704'),
      ('GOR', 500, 1650, 'C', ''),
      ('GUA', 400000, 1650, 'C', 'late-Ming Canton; sacked by the Qing in 1650'),
      ('GYE', 5000, 1650, 'C', ''),
      ('HAD', 500, 1650, 'N', 'the chief village of Socotra; analogue: other Arabian Sea island towns'),
      ('HAG', 1000, 1670, 'L', 'the Spanish mission town, founded 1668'),
      ('HAM', 75000, 1650, 'A', ''),
      ('HAN', 100000, 1650, 'C', 'Thang Long (Ke Cho); European visitors'' estimates'),
      ('HAV', 15000, 1650, 'B', '~26,000 by 1700'),
      ('HER', 20000, 1650, 'B', 'Venetian Candia, under siege 1648-1669'),
      ('HIR', 5000, 1650, 'C', 'in decline after the Dutch left for Dejima (1641)'),
      ('HOB', 1000, 1810, 'L', 'founded 1804'),
      ('HOI', 8000, 1650, 'C', 'Japanese and Chinese merchant quarters'),
      ('HON', 7000, 1841, 'L', 'the British count of the island, 1841; only villages before'),
      ('HNL', 6000, 1823, 'L', 'the Hawaiian town at the first missionary estimates'),
      ('HOO', 30000, 1650, 'C', 'the Mughal port that replaced the Portuguese town (1632)'),
      ('HRN', 15000, 1650, 'A', ''),
      ('HOR', 40000, 1600, 'B', 'before its fall (1622); deserted by 1650, so the 1600 figure is used'),
      ('HUA', 300, 1650, 'C', 'raided by Drake (1579) and Cavendish (1587)'),
      ('INC', 5000, 1650, 'N', 'Joseon Incheon-bu; analogue: other Joseon county towns'),
      ('IST', 700000, 1650, 'B', 'estimates 600,000-750,000'),
      ('IZM', 80000, 1650, 'B', 'the Levant''s rising entrepot'),
      ('JAF', 10000, 1650, 'C', ''),
      ('JAK', 30000, 1650, 'B', 'Batavia within and around the walls'),
      ('JAM', 500, 1650, 'B', 'the Virginia colony held ~15,000; the town a few hundred'),
      ('JED', 10000, 1650, 'C', ''),
      ('JEJ', 10000, 1650, 'C', 'Jeju town; the island held more'),
      ('KAG', 50000, 1650, 'C', 'the Satsuma castle town'),
      ('KAL', 40000, 1650, 'B', 'Konigsberg'),
      ('KAN', 10000, 1650, 'C', ''),
      ('KAR', 10000, 1800, 'L', 'founded c. 1729'),
      ('KHA', 50000, 1650, 'C', 'Cambay, silting and declining'),
      ('KIL', 4000, 1650, 'C', 'long past its height'),
      ('KIN', 7000, 1650, 'B', ''),
      ('KOC', 20000, 1650, 'C', 'Portuguese Cochin and Mattancherry, before the Dutch (1663)'),
      ('KOL', 10000, 1650, 'C', ''),
      ('KOZ', 50000, 1650, 'C', 'the Zamorin''s city'),
      ('KUP', 1000, 1650, 'C', ''),
      ('LAR', 15000, 1650, 'C', 'recovering after the 1628 siege'),
      ('LAG', 5000, 1650, 'C', 'Eko, a Benin outpost'),
      ('LPA', 8000, 1650, 'C', ''),
      ('LEH', 15000, 1650, 'C', ''),
      ('LEI', 5000, 1650, 'C', 'the port alone; Edinburgh (~30,000) lies inland'),
      ('LIS', 150000, 1650, 'B', ''),
      ('LIV', 20000, 1650, 'B', ''),
      ('LON', 400000, 1650, 'A', ''),
      ('LNG', 200, 1650, 'N', 'no town until 1906; analogue: the summer whaling station at Smeerenburg'),
      ('LUA', 6000, 1650, 'C', ''),
      ('LUB', 30000, 1650, 'B', ''),
      ('MAC', 30000, 1650, 'C', 'after the Japan trade was lost (1639); ~40,000 at its height'),
      ('MCH', 40000, 1650, 'C', 'Golconda''s great port'),
      ('MAK', 100000, 1650, 'C', 'Gowa-Tallo before the Dutch conquest (1669)'),
      ('MAL', 5000, 1678, 'A', 'the Dutch census of 1678; ~20,000 under the Portuguese before 1641'),
      ('MLG', 25000, 1650, 'B', 'after the 1649 plague'),
      ('MLE', 2000, 1650, 'C', ''),
      ('MLN', 3000, 1650, 'C', 'in decline after the Portuguese moved to Mombasa (1593)'),
      ('MAN', 2000, 1650, 'C', ''),
      ('MNG', 10000, 1650, 'C', ''),
      ('MNL', 40000, 1650, 'B', 'Intramuros with the Chinese Parian'),
      ('MRS', 65000, 1650, 'B', ''),
      ('MAS', 2000, 1650, 'C', ''),
      ('MAT', 10000, 1650, 'C', 'the Matsumae castle town'),
      ('MZT', 3000, 1830, 'L', 'a fishing village until the port opened in the 1820s'),
      ('MES', 80000, 1650, 'C', 'before the 1674 revolt; figures run 60,000-120,000'),
      ('MEZ', 1000, 1650, 'C', ''),
      ('MID', 25000, 1650, 'B', ''),
      ('MOC', 10000, 1650, 'C', 'the coffee port, rising'),
      ('MOG', 5000, 1650, 'C', ''),
      ('MOK', 1000, 1650, 'N', 'a Joseon naval post; analogue: Yeosu''s naval town, smaller'),
      ('MOM', 8000, 1650, 'C', 'under Fort Jesus'),
      ('MTY', 500, 1790, 'L', 'founded 1770'),
      ('ISL', 3000, 1650, 'C', ''),
      ('MUM', 10000, 1661, 'B', 'when ceded to England (1661)'),
      ('MUS', 8000, 1650, 'C', 'retaken from the Portuguese in 1650'),
      ('MYE', 5000, 1650, 'C', 'Mergui'),
      ('NAG', 40000, 1650, 'B', '25,000 in 1616, 64,500 by the 1696 count'),
      ('NAH', 10000, 1650, 'C', 'the port below Shuri'),
      ('NAM', 2000, 1650, 'N', 'no town of the name until 1900s; analogue: Joseon river-mouth towns below Pyongyang'),
      ('NAN', 40000, 1650, 'B', ''),
      ('NAP', 300000, 1650, 'B', 'before the 1656 plague killed about half'),
      ('NEW', 1000, 1650, 'A', 'New Amsterdam'),
      ('NIN', 150000, 1650, 'C', ''),
      ('NUU', 300, 1730, 'L', 'Godthab, founded 1728'),
      ('OLD', 40000, 1650, 'C', '~75,000 in 1600, ~20,000 by 1695'),
      ('ORA', 5000, 1650, 'C', 'a Spanish presidio'),
      ('OSA', 300000, 1650, 'B', ''),
      ('OUI', 10000, 1650, 'C', 'before the slave-trade boom of the 1670s'),
      ('PAI', 500, 1650, 'C', ''),
      ('PAL', 110000, 1650, 'B', ''),
      ('PLM', 25000, 1650, 'B', ''),
      ('PAN', 8000, 1650, 'B', 'old Panama, before the 1671 sack'),
      ('PAR', 1000, 1680, 'L', 'English settlement 1650, Dutch from 1667'),
      ('PAT', 8000, 1650, 'C', ''),
      ('PTT', 20000, 1650, 'C', ''),
      ('PLY', 8000, 1650, 'B', ''),
      ('PON', 8000, 1650, 'C', ''),
      ('PLO', 3000, 1740, 'L', 'founded 1735'),
      ('POR', 6500, 1680, 'L', 'English from 1655; the 1680 figure'),
      ('PTL', 500, 1680, 'L', 'Falmouth settlement'),
      ('OPO', 20000, 1650, 'B', ''),
      ('PRT', 1000, 1650, 'B', 'the permanent town; thousands more at the fair'),
      ('PTH', 5000, 1650, 'B', ''),
      ('PUL', 5000, 1650, 'C', 'Dutch Fort Geldria'),
      ('PUS', 500, 1650, 'C', ''),
      ('QUA', 100000, 1650, 'C', 'long past its Song height'),
      ('QUE', 500, 1666, 'A', 'the 1666 census of the town (547)'),
      ('REC', 8000, 1650, 'B', 'Dutch Mauritsstad and Recife'),
      ('REY', 200, 1786, 'L', 'a farm until the 1786 trading charter'),
      ('RHO', 10000, 1650, 'C', ''),
      ('RIG', 25000, 1650, 'B', ''),
      ('RIO', 4000, 1650, 'C', ''),
      ('ROT', 30000, 1650, 'B', ''),
      ('SAF', 5000, 1650, 'C', ''),
      ('SAI', 1000, 1700, 'L', 'founded 1659'),
      ('SNT', 15000, 1650, 'C', ''),
      ('SAK', 60000, 1650, 'C', ''),
      ('SAL', 15000, 1650, 'C', 'the corsair republic of Sale and Rabat'),
      ('SLV', 12000, 1650, 'C', 'the capital of Brazil'),
      ('SDG', 500, 1800, 'L', 'founded 1769'),
      ('SFR', 500, 1847, 'L', 'Yerba Buena, just before the gold rush'),
      ('SAN', 3000, 1650, 'C', ''),
      ('SNL', 15000, 1650, 'C', ''),
      ('TEN', 2000, 1650, 'C', 'La Laguna was the island''s capital'),
      ('SGO', 5000, 1650, 'C', ''),
      ('SOS', 1000, 1650, 'C', ''),
      ('SAO', 3000, 1650, 'C', ''),
      ('SET', 10000, 1650, 'C', ''),
      ('SVQ', 120000, 1646, 'B', 'before the 1649 plague killed about half'),
      ('SHI', 10000, 1650, 'C', 'Akamagaseki'),
      ('SOF', 1000, 1650, 'C', ''),
      ('SOY', 5000, 1650, 'C', 'Mbanza Soyo'),
      ('SPL', 5000, 1650, 'C', ''),
      ('STA', 1000, 1650, 'B', ''),
      ('STG', 1000, 1650, 'C', ''),
      ('STJ', 500, 1680, 'C', 'the winter residents'),
      ('STO', 40000, 1650, 'B', ''),
      ('SUA', 5000, 1650, 'C', ''),
      ('SUE', 2000, 1650, 'C', ''),
      ('SUR', 10000, 1650, 'C', 'after its conquest by Mataram (1625)'),
      ('SRT', 100000, 1650, 'B', 'the Mughal empire''s chief port; ~200,000 by 1700'),
      ('SYD', 2500, 1800, 'L', 'founded 1788'),
      ('TAI', 10000, 1650, 'C', 'Dutch Zeelandia and Saccam with the Chinese settlers'),
      ('TAL', 10000, 1650, 'B', ''),
      ('TAN', 5000, 1650, 'C', ''),
      ('TER', 8000, 1650, 'C', ''),
      ('THA', 10000, 1650, 'C', 'Syriam'),
      ('THE', 40000, 1650, 'B', ''),
      ('TID', 5000, 1650, 'C', ''),
      ('TOK', 500000, 1650, 'B', 'Edo; ~1,000,000 by 1720'),
      ('TON', 5000, 1650, 'C', 'the Joseon naval headquarters town'),
      ('TOR', 300, 1650, 'C', ''),
      ('TOU', 20000, 1650, 'C', ''),
      ('TRA', 15000, 1650, 'C', ''),
      ('TRI', 20000, 1650, 'C', ''),
      ('TRP', 15000, 1650, 'C', ''),
      ('TRO', 6000, 1650, 'B', ''),
      ('TSU', 10000, 1650, 'C', 'Fuchu, the So clan''s castle town'),
      ('TUN', 80000, 1650, 'C', ''),
      ('TUR', 5000, 1650, 'B', ''),
      ('ULS', 5000, 1650, 'C', ''),
      ('VAL', 50000, 1650, 'B', ''),
      ('VLL', 20000, 1650, 'B', 'the harbour towns together'),
      ('VLP', 500, 1650, 'C', ''),
      ('VAR', 300, 1650, 'C', ''),
      ('VEN', 140000, 1650, 'A', 'after the 1630 plague'),
      ('VER', 5000, 1650, 'C', ''),
      ('VIS', 3000, 1650, 'C', ''),
      ('WLG', 3000, 1842, 'L', 'founded 1840'),
      ('WIL', 2000, 1650, 'C', ''),
      ('XIA', 50000, 1650, 'C', 'Koxinga''s base in the 1650s'),
      ('YEO', 5000, 1650, 'C', 'the Jeolla left naval base'),
      ('ZAK', 15000, 1650, 'C', 'the Venetian town'),
      ('ZAN', 5000, 1650, 'C', '')
    ) v(code, pop, yr, conf, note)
    join public.ports p on p.code = v.code and p.kind = 'HARBOUR';
  get diagnostics v_n = row_count;
  if v_n <> (select count(*) from public.ports where kind = 'HARBOUR') or v_n <> 246 then
    raise exception '0304 FAIL: % population rows seeded, % harbours, the table names 246', v_n, (select count(*) from public.ports where kind = 'HARBOUR');
  end if;

  -- ── 3. THE KNOBS ──
  insert into public.world_config (key, value, description) values
    ('population_tax_per_1000', to_jsonb(4000),
     '0304: the daily tax (ducats a UTC day) a harbour of 1,000 people pays its city. A harbour of P pays round(this x (P/1000)^population_tax_exponent). 0 turns the tax off.'),
    ('population_tax_exponent', to_jsonb(0.75),
     '0304: how the tax (and the investment yardstick) scales with population: 1 = linear, below 1 = a big city pays less per head. 0.75 keeps the 23 capitals from swamping the rest (docs/dev-log/2026-11-04-city-population.md).'),
    ('population_step_base', to_jsonb(0.0001),
     '0304: the fraction a population moves in one 10-minute step at score 1 (1.0001^144 = +1.45 % a day). 0 freezes every population (every step HOLDs).'),
    ('population_step_max', to_jsonb(0.0002),
     '0304: the most one 10-minute step moves a population, whatever the score (+2.9 % a day at most).'),
    ('population_hold_band', to_jsonb(0.5),
     '0304: a score with |score| under this HOLDs: nothing unusual. At or above it the step GROWs (positive) or SHRINKs (negative).'),
    ('population_floor_ratio', to_jsonb(0.5),
     '0304: a population never falls under this x its real-world baseline.'),
    ('population_ceiling_ratio', to_jsonb(2),
     '0304: a population never rises over this x its real-world baseline.'),
    ('population_invest_full', to_jsonb(2400000),
     '0304: the INVEST signal is 1 when port_treasury.invested reaches this x (population/1000)^population_tax_exponent - 600 days of the default tax. Prod 2026-11-04: a quarter of harbours are over half of it.'),
    ('population_famine_stock_frac', to_jsonb(0.1),
     '0304: a staple good is short when its stock is under this x its stock_target; FAMINE is the share of a harbour''s staples that are short.'),
    ('population_staple_categories', '["food", "grain"]'::jsonb,
     '0304: the goods categories (public.goods.category) a harbour''s people eat; the FAMINE signal reads them.'),
    ('population_log_slots', to_jsonb(144),
     '0304: the 10-minute steps public.population_log keeps per harbour (144 = one day); older rows are trimmed every step.');

  -- ── 4. THE WORD (minted: the books show the tax as new money) ──
  insert into public.stats_flow_words (kind, side, word, ord) values ('POPULATION_TAX', 'minted', 'New money: population tax', 9);

  -- ── 5. THE FUNCTIONS ──
  execute $f1$
create function public.population_rule(p_pop numeric, p_baseline numeric, p_score numeric,
                                       out population numeric, out kind text, out at_bound boolean)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0304: THE growth rule. |score| under population_hold_band HOLDs; else the population moves by
-- least(population_step_max, population_step_base x |score|), up for a positive score, down for a negative one,
-- and is held inside [population_floor_ratio, population_ceiling_ratio] x baseline. A step the bound stops is a HOLD
-- (at_bound). population_step_base 0 HOLDs everything. Reads the knobs and nothing else.
declare
  v_base numeric := public.wc_num('population_step_base');
  v_max  numeric := public.wc_num('population_step_max');
  v_band numeric := public.wc_num('population_hold_band');
  v_lo   numeric := round(p_baseline * public.wc_num('population_floor_ratio'), 3);
  v_hi   numeric := round(p_baseline * public.wc_num('population_ceiling_ratio'), 3);
  v_s    numeric := coalesce(p_score, 0);
begin
  if v_base <= 0 or abs(v_s) < v_band then
    kind := 'HOLD';
    population := p_pop;
  else
    kind := case when v_s > 0 then 'GROW' else 'SHRINK' end;
    population := p_pop * (1 + sign(v_s) * least(v_max, v_base * abs(v_s)));
  end if;
  population := round(least(v_hi, greatest(v_lo, population)), 3);
  at_bound := kind <> 'HOLD' and population = round(p_pop, 3);
  if at_bound then
    kind := 'HOLD';
  end if;
end $body$;
$f1$;

  execute $f2$
create function public.population_signals()
returns table (port_id uuid, code text, value numeric)
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0304: THE population signals, one row per (harbour, signal), value 0..1, from real game state only. Weights:
  -- public.population_signal_weights. PIRATES and STORM have no source yet: a future branch below emits them.
  with k as (
    select public.wc_num('population_invest_full') as invest_full, public.wc_num('population_tax_exponent') as ex,
           public.wc_num('population_famine_stock_frac') as short_frac,
           array(select jsonb_array_elements_text(public.wc('population_staple_categories'))) as staples
  )
  -- INVEST: recent investment against a yardstick that scales with the city like its tax
  select t.port_id, 'INVEST'::text,
         least(1, t.invested::numeric / nullif(k.invest_full * power(pp.population / 1000.0, k.ex), 0))
    from public.port_treasury t join public.port_population pp on pp.port_id = t.port_id cross join k
   where t.invested > 0
  union all
  -- FAMINE: the share of the city's staples that are short
  select pg.port_id, 'FAMINE'::text,
         (count(*) filter (where pg.stock < k.short_frac * pg.stock_target))::numeric / count(*)
    from public.port_goods pg join public.goods g on g.id = pg.good_id cross join k
   where g.category = any (k.staples) and pg.stock_target > 0
     and exists (select 1 from public.port_population pp where pp.port_id = pg.port_id)
   group by pg.port_id
  union all
  -- WAR: the share of the city's influence held by nations at war with its holder
  select a.port_id, 'WAR'::text,
         coalesce(sum(i.points) filter (where r.stance = 'war'), 0) / sum(i.points)
    from public.port_allegiance a
    join public.port_influence i on i.port_id = a.port_id
    left join public.power_relations r on r.a = least(i.nation_id, a.nation_id) and r.b = greatest(i.nation_id, a.nation_id)
   where a.nation_id is not null and exists (select 1 from public.port_population pp where pp.port_id = a.port_id)
   group by a.port_id
  having sum(i.points) > 0
$body$;
$f2$;

  execute $f3$
create function public.city_population_income(p_port uuid)
returns bigint
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0304: THE daily tax a harbour's people pay its city, from its CURRENT population:
  -- round(population_tax_per_1000 x (population / 1000)^population_tax_exponent). 0 for a harbour with no population row.
  select coalesce((select round(public.wc_num('population_tax_per_1000')
                                * power(pp.population / 1000.0, public.wc_num('population_tax_exponent')))::bigint
                     from public.port_population pp where pp.port_id = p_port), 0)
$body$;
$f3$;

  execute $f4$
create function public.population_tick(p_now timestamptz default now())
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $body$
-- 0304: THE 10-minute job (cron byeharu-voyage:population, its own job). Never waits: one run at a time (advisory lock, a second
-- run returns busy), lock_timeout 2 s.
--   1. THE STEP: ONE set-based UPDATE over every harbour not yet stepped in this 10-minute slot (slot = epoch / 600): the score
--      (sum of weight x value of public.population_signals), public.population_rule, the reason (the signal that weighed most in the
--      step's direction; CEILING / FLOOR when a bound stopped it). The same statement writes the log row. A re-run in the slot steps nothing.
--   2. THE TRIM: population_log keeps population_log_slots steps.
--   3. THE TAX, once per UTC day while the purses are lit: each harbour not yet paid today is paid public.city_population_income (its
--      CURRENT population) through public.treasury_post, kind POPULATION_TAX, under byeharu.population_tax = 'on' (mint_guard's 0304
--      exception), put back to 'off' after. paid_day marks it: a re-run the same day pays nothing.
declare
  v_t0    timestamptz := clock_timestamp();
  v_slot  bigint := floor(extract(epoch from p_now) / 600)::bigint;
  v_day   int := floor(extract(epoch from p_now) / 86400)::int;
  v_steps int := 0;
  v_grow  int := 0;
  v_shrink int := 0;
  v_trim  int := 0;
  v_paid  int := 0;
  v_tax   bigint := 0;
  v_amt   bigint;
  v_ms    jsonb := '{}'::jsonb;
  r       record;
begin
  if not pg_try_advisory_xact_lock(hashtextextended('byeharu.population_tick', 304)) then
    return jsonb_build_object('busy', true, 'at', p_now);
  end if;
  perform set_config('lock_timeout', '2s', true);

  -- 1. THE STEP (one statement)
  with sig as (
    select s.port_id, s.code, s.value * w.weight as c
      from public.population_signals() s join public.population_signal_weights w on w.code = s.code
  ), agg as (
    select sig.port_id, sum(sig.c) as score,
           (array_agg(sig.code order by sig.c desc, sig.code) filter (where sig.c > 0))[1] as up_code,
           (array_agg(sig.code order by sig.c, sig.code) filter (where sig.c < 0))[1] as down_code
      from sig group by sig.port_id
  ), sc as (
    select pp.port_id, pp.population, pp.baseline, coalesce(agg.score, 0) as score, agg.up_code, agg.down_code
      from public.port_population pp left join agg on agg.port_id = pp.port_id
     where pp.slot is null or pp.slot < v_slot
  ), nx as (
    select sc.port_id, ru.population, ru.kind,
           case when ru.kind = 'GROW' then sc.up_code
                when ru.kind = 'SHRINK' then sc.down_code
                when ru.at_bound and sc.score > 0 then 'CEILING'
                when ru.at_bound then 'FLOOR' end as reason
      from sc cross join lateral public.population_rule(sc.population, sc.baseline, sc.score) ru
  ), up as (
    update public.port_population pp
       set population = nx.population, kind = nx.kind, reason = nx.reason, slot = v_slot, updated_at = p_now
      from nx
     where pp.port_id = nx.port_id and (pp.slot is null or pp.slot < v_slot)
    returning pp.port_id, pp.population, pp.kind, pp.reason
  ), lg as (
    insert into public.population_log (port_id, slot, population, kind, reason)
    select up.port_id, v_slot, up.population, up.kind, up.reason from up
    on conflict (port_id, slot) do nothing
    returning kind
  )
  select count(*), count(*) filter (where kind = 'GROW'), count(*) filter (where kind = 'SHRINK') into v_steps, v_grow, v_shrink from lg;
  v_ms := v_ms || jsonb_build_object('step', round(extract(epoch from clock_timestamp() - v_t0) * 1000));

  -- 2. THE TRIM
  delete from public.population_log l where l.slot <= v_slot - public.wc_int('population_log_slots');
  get diagnostics v_trim = row_count;

  -- 3. THE TAX (once per UTC day, purses lit)
  if public.city_treasury_on() and exists (select 1 from public.port_population pp where coalesce(pp.paid_day, -1) < v_day) then
    perform set_config('byeharu.population_tax', 'on', true);
    for r in select pp.port_id from public.port_population pp
              where coalesce(pp.paid_day, -1) < v_day order by pp.port_id
                for update of pp skip locked loop
      v_amt := public.city_population_income(r.port_id);
      if v_amt > 0 then
        perform public.treasury_post(r.port_id, 'POPULATION_TAX', v_amt, null, null);
        v_tax := v_tax + v_amt;
        v_paid := v_paid + 1;
      end if;
      update public.port_population set paid_day = v_day where port_id = r.port_id;
    end loop;
    perform set_config('byeharu.population_tax', 'off', true);
  end if;

  return jsonb_build_object('slot', v_slot, 'stepped', v_steps, 'grew', v_grow, 'shrank', v_shrink, 'trimmed', v_trim,
                            'day', v_day, 'paid', v_paid, 'tax', v_tax,
                            'ms', v_ms || jsonb_build_object('total', round(extract(epoch from clock_timestamp() - v_t0) * 1000)),
                            'at', p_now);
end $body$;
$f4$;

  execute $f5$
create function public.town_hall_people(p_port uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0304: world.town_hall's `people` block: the population now (rounded), its real-world baseline and year, the daily tax it pays
  -- (public.city_population_income), the last 10-minute step (kind, reason) and the change over the log's day (population now minus
  -- the oldest kept step). Absent ({}) for a harbour with no population row.
  select coalesce((
    select jsonb_build_object('people', jsonb_build_object(
             'population', round(pp.population)::bigint,
             'baseline', pp.baseline,
             'year', pp.year,
             'per_day', public.city_population_income(pp.port_id),
             'kind', coalesce(pp.kind, 'HOLD'),
             'reason', pp.reason,
             'day_change', round(pp.population - coalesce(
                 (select l.population from public.population_log l where l.port_id = pp.port_id order by l.slot limit 1), pp.population))::bigint))
      from public.port_population pp where pp.port_id = p_port), '{}'::jsonb)
$body$;
$f5$;

  revoke all on function public.population_rule(numeric, numeric, numeric) from public, anon, authenticated;
  revoke all on function public.population_signals() from public, anon, authenticated;
  revoke all on function public.city_population_income(uuid) from public, anon, authenticated;
  revoke all on function public.population_tick(timestamptz) from public, anon, authenticated;
  revoke all on function public.town_hall_people(uuid) from public, anon, authenticated;

  -- ── 6. THE HUNKS (mint_guard x2, town_hall x1): each occurs exactly once in the LIVE body ──
  if (length(v_mg_before) - length(replace(v_mg_before, h_mg1_old, ''))) / length(h_mg1_old) <> 1
     or (length(v_mg_before) - length(replace(v_mg_before, h_mg2_old, ''))) / length(h_mg2_old) <> 1
     or (length(v_th_before) - length(replace(v_th_before, h_th_old, ''))) / length(h_th_old) <> 1 then
    raise exception '0304 FAIL: a hunk does not occur exactly once in its live body';
  end if;
  execute replace(replace(v_mg_before, h_mg1_old, h_mg1_new), h_mg2_old, h_mg2_new);
  execute replace(v_th_before, h_th_old, h_th_new);

  -- ── 7. THE JOB (its own; scheduled INACTIVE, wind_the_clock() starts it) ──
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    execute $q$select cron.schedule('byeharu-voyage:population', '5,15,25,35,45,55 * * * *', 'select public.population_tick()')$q$;
    execute $q$select cron.alter_job(jobid, active := false) from cron.job where jobname = 'byeharu-voyage:population'$q$;
    raise notice '0304: pg_cron present - byeharu-voyage:population SCHEDULED BUT INACTIVE until wind_the_clock().';
  else
    raise notice '0304: pg_cron is not installed here (PGlite) - byeharu-voyage:population was NOT scheduled. Call public.population_tick() by hand.';
  end if;

  -- ── 8. SELF-ASSERT ──
  -- (a) the seed: every harbour once, at its baseline, unstepped, unpaid; the total is the data file's
  select count(*), sum(baseline) into v_n, v_total from public.port_population;
  if v_n <> (select count(*) from public.ports where kind = 'HARBOUR') or v_total <> 7442750
     or exists (select 1 from public.port_population where population <> baseline or slot is not null or kind is not null or paid_day is not null)
     or exists (select 1 from public.port_population pp join public.ports p on p.id = pp.port_id where p.kind <> 'HARBOUR') then
    raise exception '0304 self-assert FAIL: the seed is not every harbour once at its baseline (% rows, total %, data total 7442750)', v_n, v_total;
  end if;
  -- (b) the knobs and the weights
  if (select count(*) from public.world_config where key like 'population\_%') <> 11
     or public.wc_num('population_tax_per_1000') <> 4000 or public.wc_num('population_tax_exponent') <> 0.75
     or public.wc_num('population_step_base') <> 0.0001 or public.wc_num('population_step_max') <> 0.0002
     or public.wc_num('population_hold_band') <> 0.5 or public.wc_num('population_floor_ratio') <> 0.5
     or public.wc_num('population_ceiling_ratio') <> 2 or public.wc_num('population_invest_full') <> 2400000
     or public.wc_num('population_famine_stock_frac') <> 0.1 or public.wc_int('population_log_slots') <> 144
     or public.wc('population_staple_categories') <> '["food", "grain"]'::jsonb
     or (select string_agg(code || '=' || weight, ',' order by code) from public.population_signal_weights)
        <> 'FAMINE=-1.0,INVEST=1.0,PIRATES=-1.0,STORM=-0.5,WAR=-1.0' then
    raise exception '0304 self-assert FAIL: the knobs or the signal weights are not as written';
  end if;
  if (select count(*) from public.goods where category in ('food', 'grain')) = 0 then
    raise exception '0304 self-assert FAIL: no goods of the staple categories exist - FAMINE could never read anything';
  end if;
  -- (c) the rule, on literals (no live row): hold band, both directions, the step cap, the ceiling and the floor
  for r in select * from (values
      (10000::numeric, 10000::numeric,  0.49::numeric, 10000.000::numeric, 'HOLD',   false),
      (10000,          10000,           0.5,           10000.500,          'GROW',   false),
      (10000,          10000,           1,             10001.000,          'GROW',   false),
      (10000,          10000,          -1,              9999.000,          'SHRINK', false),
      (10000,          10000,           5,             10002.000,          'GROW',   false),   -- capped at population_step_max
      (10000,          10000,          -5,              9998.000,          'SHRINK', false),
      (20000,          10000,           1,             20000.000,          'HOLD',   true),    -- at the ceiling
      (19999.5,        10000,           1,             20000.000,          'GROW',   false),   -- reaches it, no further
      (5000,           10000,          -1,              5000.000,          'HOLD',   true),    -- at the floor
      (150,            150,             1,               150.015,          'GROW',   false)    -- a hamlet still moves (3 decimals)
    ) t(pop, base, score, want_pop, want_kind, want_bound) loop
    if (select x.population from public.population_rule(r.pop, r.base, r.score) x) <> r.want_pop
       or (select x.kind from public.population_rule(r.pop, r.base, r.score) x) <> r.want_kind
       or (select x.at_bound from public.population_rule(r.pop, r.base, r.score) x) <> r.want_bound then
      raise exception '0304 self-assert FAIL: population_rule(%, %, %) is not (%, %, %)', r.pop, r.base, r.score, r.want_pop, r.want_kind, r.want_bound;
    end if;
  end loop;
  -- (d) the tax, on the seed: each harbour round(4000 x (P/1000)^0.75); London is 4000 x 400^0.75
  select sum(public.city_population_income(port_id)) into v_tax from public.port_population;
  if exists (select 1 from public.port_population pp
              where public.city_population_income(pp.port_id) <> round(4000 * power(pp.baseline / 1000.0, 0.75))::bigint) then
    raise exception '0304 self-assert FAIL: city_population_income is not round(4000 x (P/1000)^0.75) on the seed';
  end if;
  select public.city_population_income(p.id) into v_lon from public.ports p where p.code = 'LON';
  if v_lon is distinct from round(4000 * power(400.0, 0.75))::bigint then
    raise exception '0304 self-assert FAIL: London''s tax is %, not 4000 x 400^0.75', v_lon;
  end if;
  -- (e) THE GUARD, closed and lit for this sub-block only, then rolled back by a sentinel exception
  v_closed := public.wc('economy_closed');
  v_lit := public.wc('city_treasury_enabled');
  begin
    update public.world_config set value = 'true'::jsonb where key in ('economy_closed', 'city_treasury_enabled');
    if not (public.economy_closed() and public.city_treasury_on()) then
      raise exception '0304 self-assert FAIL: the probe could not close and light the world';
    end if;
    -- (e1) POPULATION_TAX with the setting off: refused
    begin
      perform public.mint_guard('POPULATION_TAX', 1);
      raise exception '0304 self-assert FAIL: POPULATION_TAX passed the guard with the setting off';
    exception when others then
      get stacked diagnostics v_errm = message_text;
      if v_errm not like 'E_NO_NEW_GOLD:%' then raise; end if;
    end;
    perform set_config('byeharu.population_tax', 'on', true);
    -- (e2) every other minted kind, setting on: still refused (OWNER_GRANT too: its own setting is off)
    for r in select kind from public.stats_flow_words where side = 'minted' and kind <> 'POPULATION_TAX' loop
      begin
        perform public.mint_guard(r.kind, 1);
        raise exception '0304 self-assert FAIL: minted kind % passed the guard with the population setting on', r.kind;
      exception when others then
        get stacked diagnostics v_errm = message_text;
        if v_errm not like 'E_NO_NEW_GOLD:%' then raise; end if;
      end;
    end loop;
    -- (e3) POPULATION_TAX with it on: passes; 0302's exception is unchanged (OWNER_GRANT with ITS setting on passes)
    perform public.mint_guard('POPULATION_TAX', 1);
    perform set_config('byeharu.population_tax', 'off', true);
    perform set_config('byeharu.owner_grant', 'on', true);
    perform public.mint_guard('OWNER_GRANT', 1);
    perform set_config('byeharu.owner_grant', 'off', true);
    -- (e4) a negative post of any kind is never asked
    perform public.mint_guard('POPULATION_TAX', -1);
    raise exception 'PROBE_0304_ROLLBACK';
  exception when others then
    get stacked diagnostics v_errm = message_text;
    if v_errm <> 'PROBE_0304_ROLLBACK' then raise; end if;
  end;
  perform set_config('byeharu.population_tax', 'off', true);
  perform set_config('byeharu.owner_grant', 'off', true);
  if public.wc('economy_closed') is distinct from v_closed or public.wc('city_treasury_enabled') is distinct from v_lit then
    raise exception '0304 self-assert FAIL: the owner switches moved';
  end if;
  -- (f) the hunks reverse to their pre-images; ACL, volatility, definer as found; the hall serves `people`
  v_def := replace(pg_get_functiondef('public.mint_guard(text,bigint)'::regprocedure), E'\r', '');
  if (length(v_def) - length(replace(v_def, h_mg2_new, ''))) / length(h_mg2_new) <> 1
     or replace(replace(v_def, h_mg2_new, h_mg2_old), h_mg1_new, h_mg1_old) <> v_mg_before then
    raise exception '0304 self-assert FAIL: public.mint_guard does not reverse to its pre-image';
  end if;
  v_def := replace(pg_get_functiondef('world.town_hall(uuid)'::regprocedure), E'\r', '');
  if (length(v_def) - length(replace(v_def, h_th_new, ''))) / length(h_th_new) <> 1 or replace(v_def, h_th_new, h_th_old) <> v_th_before then
    raise exception '0304 self-assert FAIL: world.town_hall does not reverse to its pre-image';
  end if;
  if (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = 'public.mint_guard(text,bigint)'::regprocedure) <> v_acl_mg
     or (select coalesce(p.proacl::text, '') from pg_proc p where p.oid = 'world.town_hall(uuid)'::regprocedure) <> v_acl_th
     or (select p.provolatile::text || p.prosecdef::text from pg_proc p where p.oid = 'public.mint_guard(text,bigint)'::regprocedure) <> 'vtrue'
     or (select p.provolatile::text || p.prosecdef::text from pg_proc p where p.oid = 'world.town_hall(uuid)'::regprocedure) <> 'strue' then
    raise exception '0304 self-assert FAIL: a re-cut changed its ACL, volatility or definer';
  end if;
  if (world.town_hall((select id from public.ports where code = 'LON')) -> 'people' ->> 'per_day')::bigint <> v_lon
     or (world.town_hall((select id from public.ports where code = 'LON')) -> 'people' ->> 'population')::bigint <> 400000 then
    raise exception '0304 self-assert FAIL: the hall does not serve London''s people';
  end if;
  -- (g) the new pieces are server-only, with the volatility written
  for r in select f, v from unnest(c_new_fns, array['s', 's', 's', 'v', 's']) x(f, v) loop
    if to_regprocedure(r.f) is null
       or (select p.provolatile::text from pg_proc p where p.oid = to_regprocedure(r.f)) <> r.v
       or has_function_privilege('anon', to_regprocedure(r.f), 'execute') or has_function_privilege('authenticated', to_regprocedure(r.f), 'execute') then
      raise exception '0304 self-assert FAIL: % is not server-only with volatility %', r.f, r.v;
    end if;
  end loop;
  if has_table_privilege('anon', 'public.port_population', 'select') or has_table_privilege('authenticated', 'public.port_population', 'select')
     or has_table_privilege('anon', 'public.population_log', 'select') or has_table_privilege('authenticated', 'public.population_log', 'insert')
     or has_table_privilege('authenticated', 'public.population_signal_weights', 'update') then
    raise exception '0304 self-assert FAIL: a population table is reachable by a client';
  end if;
  -- (h) nothing else moved: every other function, every existing knob, the existing cron jobs, treasury_post
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid not in ('public.mint_guard(text,bigint)'::regprocedure, 'world.town_hall(uuid)'::regprocedure)
         and p.oid <> all (array(select to_regprocedure(x)::oid from unnest(c_new_fns) x))) <> v_fn_before then
    raise exception '0304 self-assert FAIL: a function other than mint_guard and town_hall changed';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key not like 'population\_%') <> v_cfg_before then
    raise exception '0304 self-assert FAIL: an existing world_config row moved';
  end if;
  if to_regclass('cron.job') is not null then
    execute $q$select md5(coalesce(string_agg(j.jobname || ':' || j.schedule || ':' || j.active::text, ',' order by j.jobname), '')) from cron.job j
                where j.jobname <> 'byeharu-voyage:population'$q$ into v_def;
    if v_def is distinct from v_cron_before then
      raise exception '0304 self-assert FAIL: an existing cron job moved';
    end if;
    execute $q$select count(*) from cron.job j where j.jobname = 'byeharu-voyage:population' and j.schedule = '5,15,25,35,45,55 * * * *'
                and j.command = 'select public.population_tick()' and not j.active$q$ into v_n;
    if v_n <> 1 then
      raise exception '0304 self-assert FAIL: byeharu-voyage:population is not scheduled once, inactive';
    end if;
  end if;
  if md5(replace(pg_get_functiondef('public.treasury_post(uuid,text,bigint,uuid,uuid,boolean)'::regprocedure), E'\r', '')) <> v_tp_before then
    raise exception '0304 self-assert FAIL: treasury_post changed';
  end if;

  raise notice '0304 self-assert ok: % harbours seeded at their real-world baseline (total % people); 11 knobs, 5 signal weights (PIRATES, STORM without a source yet); population_rule holds, grows, shrinks, caps the step and stops at the ceiling and floor on 10 literal cases; the daily tax at the seeded figures sums to % d. a day (London %); guard: POPULATION_TAX refused without its setting, every other minted kind refused with it, POPULATION_TAX passes with it, OWNER_GRANT''s exception unchanged; mint_guard and town_hall reverse to their pre-images; the hall serves people; the new pieces are server-only; nothing else moved. The tick is proven by scripts/db/proofs/14_city_population.sql. Printed, never asserted: % ms.',
    (select count(*) from public.port_population), v_total, v_tax, v_lon, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
