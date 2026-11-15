-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0431 - THE STATS OPEN EVERY FLEET  (Stats faces Navy, Pirates and Cargo: a list of every fleet, and a press opens one fleet's page)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- THE OWNER, 2026-11-15, verbatim: "in stats, i would like to have a separate tab for navy, pirates, and cargoships like merchants. and by
--   clicking on navy, i should be able to see how much damage it took, how much money = loot it took, fixing fees, and so much more. same for
--   pirates as well. for cargoships i want to see from what city to what city it delivered, and so much more."
--   docs/dev-log/2026-11-15-stats-fleet-tabs.md has the reasoning and the measurements.
--
-- WHAT WAS RECORDED BEFORE THIS FILE, A FLEET AT A TIME (read on the local chain at head 0426; the queue's 0427-0430 hunk none of this file's bodies):
--   cargo ships: EVERYTHING that moves gold (public.convoy_cargo: LOADED, DELIVERED, RETURNED, LOOTED, by fleet, never deleted, index (fleet_id, id)).
--   navy and pirates: only the LAST fight (navy_ships.fought, public.navy_fight_log) and the NAVY_FIGHT event (no index by fleet). Their upkeep
--   (NAVY_PAY), refits (REFIT), fines (FINE), ransoms (RANSOM) and loot (LOOT) are written to the CITIES' books (treasury_flows) with no fleet;
--   their voyages and own events are cut after npc_retention_hours (3) by the compactor. So "how much did this navy ship cost, take, lose" is
--   recorded nowhere. This file adds the smallest record that answers it.
--
-- WHAT THIS FILE DOES:
--   1. public.fleet_book (NEW): one row a fleet an HOUR, `figs` a jsonb of numbers added up (upkeep, repairs, refits, fights, won, lost, sunk, hull,
--      wrecks, stops, fines, prizes, raids, raids_won, raids_lost, loot, ransom, gold, paid, navy_fights, attacked, held, loaded, delivered,
--      returned, looted and their *_n counts). Kept 8 days (tick_stats deletes older hours).
--   2. public.fleet_lines (NEW): a fleet's last 12 things that happened (FIGHT, STOP, BATTLE, RAID, TAKE, REFIT), each a small jsonb; kept 12 a
--      fleet (trimmed at each write) and 8 days.
--   3. public.fleet_book_add (NEW, the ONE writer of both): adds numbers to her hour and, with a kind, writes a line. IT NEVER RAISES: anything that
--      goes wrong is a warning and the game goes on as it was (public.navy_fight_keep's rule, 0364). Five bookers call it, one per kind of moment:
--      fleet_book_fight (navy against pirate), fleet_book_stop (a navy stops a merchant: the fine and the prize), fleet_book_refit (a wreck's refit
--      paid), fleet_book_take (a pirate's ransom or a cargo ship's gold), and the trigger fleet_book_battle on public.battles (a battle closes:
--      0427's raids and players' attacks; every navy, pirate and cargo ship on its sides).
--   4. NINE HUNKS, each ONE line added beside a line that already moves the money or fights, in bodies none of the queue (0427-0430) cuts:
--      navy_fight, voyage.navy_meets, navy_pay, pirate_pay_hour, npc_refit_step, pirate_reborn, pirate_ransom, pirate_loot_book, convoy_book.
--   5. public.stats_fleet_list (NEW, one row a kind: NAVY, PIRATE, CARGO) written by the Stats count (tick_stats, one hunk, with the 8-day deletes):
--      every fleet of the kind (name, country, home, ships, state, her 7 days) and the kind's 24 h and 7 d totals (public.stats_fleet_list_rows).
--   6. TWO READS (STABLE, granted to authenticated, two registry rows): world.stats_fleet_list(kind), the face's list (one row by key), and
--      world.stats_fleet(fleet), one fleet's page: where she is and what she does, her ships, her 24 h and 7 d, her last lines and, for a cargo
--      ship, her last 12 gold rows (from city -> to city, how much, how long after the load) and what she carries now.
--
-- LOAD (the database budget, docs/DATABASE_BUDGET.md): the book writes about one row a fleet an hour that something happened to her: every
--   navy and pirate ship at work is paid each hour (~40 + ~90 upserts an hour), and cargo gold moves, fights, stops, raids and refits add a few a
--   minute. Expected +3 to +8 rows a minute (upserts and 12-line trims), ~45,000 book rows and ~2,000 lines at most (~8 MB with their indexes).
--   The Stats count (4 an hour) reads the 7 days of the book once (~45,000 small rows, ~40 ms), writes 3 rows, deletes the hours past 8 days.
--   The reads: one row by key; one fleet's <=192 hours, 12 lines, 12 gold rows, by index.
-- LOCKS: CREATE TABLE x3, CREATE FUNCTION x9, CREATE TRIGGER on public.battles (a share row exclusive lock, held to the end), CREATE OR REPLACE x10
--   by hunks. BUDGET: statement_timeout 30 s, lock_timeout 5 s; fails above 15 s.
-- SELF-ASSERT: each hunk once and reversing; grants, volatility, definer, search path, owner unmoved; no other function moved; the new functions
--   server-only, the reads STABLE and granted to authenticated alone; then a probe in a rolled-back sub-transaction: a fleet's hour summed, her
--   lines trimmed to 12, a broken booking only warned, the list built, and (where the world has one) a navy ship's page read.
-- ROLLBACK (forward, owner only): scripts/ops/harness/fleet-tabs/rollback-0431.sql, a draft (the hunks reversed, the reads, bookers, trigger and
--   tables dropped). The face then says its figures did not load until the client is reverted too.
-- VERSION: 0431 = 0430 + 1 (the queue: 0427 pirates strike, 0428 db room, 0429 pirate cities gold, 0430 cargo 100; production head 0426 on
--   2026-11-15 at writing).
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  c_cut constant text[] := array[
    'public.navy_fight(uuid,uuid,timestamp with time zone)', 'voyage.navy_meets(uuid,integer,uuid,uuid,timestamp with time zone)',
    'public.navy_pay(timestamp with time zone,uuid)', 'public.pirate_pay_hour(timestamp with time zone)',
    'public.npc_refit_step(uuid,timestamp with time zone)', 'public.pirate_reborn(uuid,timestamp with time zone)',
    'public.pirate_ransom(uuid,uuid,bigint,uuid)', 'public.pirate_loot_book(uuid,uuid,numeric,uuid)',
    'public.convoy_book(text,uuid,uuid,uuid,bigint,bigint)', 'public.tick_stats(timestamp with time zone)',
    'public.client_rpc_entry_points()'];
  c_new constant text[] := array[
    'public.fleet_figs_add(jsonb,jsonb)', 'public.fleet_book_add(uuid,timestamp with time zone,jsonb,text,jsonb)',
    'public.fleet_book_fight(uuid,uuid,text,jsonb,boolean,boolean,timestamp with time zone)',
    'public.fleet_book_stop(uuid,uuid,text,jsonb,bigint,jsonb,timestamp with time zone)',
    'public.fleet_book_refit(uuid,bigint,timestamp with time zone)', 'public.fleet_book_take(uuid,text,bigint,uuid,uuid,timestamp with time zone)',
    'public.fleet_book_battle()', 'public.stats_fleet_list_rows(text,timestamp with time zone)',
    'world.stats_fleet_list(text)', 'world.stats_fleet(uuid)'];
  v_t0        timestamptz := clock_timestamp();
  v_tp        timestamptz;
  h           record;
  v_z         record;
  v_def       text;
  v_n         int;
  v_fn_before text;
  v_fleet     uuid;
  v_r         jsonb;
  v_ms        numeric;
  v_note      text := 'not run';
begin
  perform set_config('statement_timeout', '30s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regclass('public.fleet_book') is not null or to_regprocedure('world.stats_fleet(uuid)') is not null then
    raise exception '0431 refuses: it has been applied once';
  end if;
  if to_regclass('public.stats_fleets') is null or to_regclass('public.battles') is null or to_regclass('public.battle_sides') is null
     or to_regclass('public.convoy_cargo') is null or to_regclass('public.navy_ships_in_service') is null
     or to_regprocedure('public.news_update(text,text,text)') is null or to_regprocedure('voyage.where_now(uuid,timestamp with time zone)') is null then
    raise exception '0431 refuses: the Stats count''s fleets row, the battles, the cargo book or the news are not in this world';
  end if;
  if exists (select 1 from unnest(c_cut) f where to_regprocedure(f) is null) then
    raise exception '0431 refuses: a body it cuts is not in this world: %', (select array_agg(f) from unnest(c_cut) f where to_regprocedure(f) is null);
  end if;

  -- ── 1. THE PRE-IMAGES ──
  create temp table pre_0431 (fn text primary key, def text, meta text) on commit drop;
  insert into pre_0431
  select f, replace(pg_get_functiondef(f::regprocedure), E'\r', ''),
         (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
            from pg_proc p where p.oid = f::regprocedure)
    from unnest(c_cut) f;
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p') and not exists (select 1 from unnest(c_cut) f where f::regprocedure = p.oid);

  -- ── 2. THE TABLES ──
  -- retention: rows older than 8 days are deleted by public.tick_stats at each count (one row a fleet an hour that something happened to her)
  create table public.fleet_book (
    fleet_id uuid not null,
    hour     timestamptz not null,
    figs     jsonb not null,
    primary key (fleet_id, hour)
  );
  create index fleet_book_hour on public.fleet_book (hour);
  comment on table public.fleet_book is
    '0431: what happened to one navy, pirate or cargo ship in one hour, as numbers added up (figs). Written by public.fleet_book_add alone; read by public.stats_fleet_list_rows and world.stats_fleet. Kept 8 days (public.tick_stats). No foreign key on purpose: a key share lock on fleets would wait behind the beat''s fleet locks; a fleet''s rows go with the 8 days.';
  alter table public.fleet_book enable row level security;
  revoke all on table public.fleet_book from public, anon, authenticated;

  -- retention: none, bounded by construction: a fleet keeps her newest 12 lines (public.fleet_book_add trims at each write); and lines older than 8 days are deleted by public.tick_stats
  create table public.fleet_lines (
    id       bigint generated always as identity primary key,
    fleet_id uuid not null,
    at       timestamptz not null,
    kind     text not null check (kind in ('FIGHT', 'STOP', 'BATTLE', 'RAID', 'TAKE', 'REFIT')),
    line     jsonb not null
  );
  create index fleet_lines_fleet on public.fleet_lines (fleet_id, id desc);
  create index fleet_lines_at on public.fleet_lines (at);
  comment on table public.fleet_lines is
    '0431: the last 12 things that happened to one navy, pirate or cargo ship (FIGHT, STOP, BATTLE, RAID, TAKE, REFIT). Written by public.fleet_book_add alone; read by world.stats_fleet. Trimmed to 12 a fleet at each write; lines older than 8 days deleted by public.tick_stats.';
  alter table public.fleet_lines enable row level security;
  revoke all on table public.fleet_lines from public, anon, authenticated;

  -- retention: none, bounded by construction: one row a kind (NAVY, PIRATE, CARGO), replaced at each Stats count
  create table public.stats_fleet_list (
    kind    text primary key check (kind in ('NAVY', 'PIRATE', 'CARGO')),
    at      timestamptz not null,
    figures jsonb not null
  );
  comment on table public.stats_fleet_list is
    '0431: the Stats faces Navy, Pirates and Cargo: every fleet of the kind and the kind''s 24 h and 7 d, as the newest Stats count built them (public.stats_fleet_list_rows). One row a kind, replaced by public.tick_stats; read by world.stats_fleet_list alone.';
  alter table public.stats_fleet_list enable row level security;
  revoke all on table public.stats_fleet_list from public, anon, authenticated;

  -- ── 3. THE WRITER ──
  execute $f$
create function public.fleet_figs_add(a jsonb, b jsonb)
returns jsonb
language sql
immutable
set search_path = public, pg_temp
as $body$
  -- 0431: two bags of numbers added key by key ({"fights": 1} + {"fights": 2, "hull": 40} = {"fights": 3, "hull": 40}). A key that is not a number counts 0.
  select coalesce(jsonb_object_agg(k.key, coalesce(case when jsonb_typeof(a -> k.key) = 'number' then (a ->> k.key)::numeric end, 0)
                                        + coalesce(case when jsonb_typeof(b -> k.key) = 'number' then (b ->> k.key)::numeric end, 0)), '{}'::jsonb)
    from (select jsonb_object_keys(case when jsonb_typeof(a) = 'object' then a else '{}'::jsonb end) as key
          union
          select jsonb_object_keys(case when jsonb_typeof(b) = 'object' then b else '{}'::jsonb end)) k
$body$
  $f$;

  execute $f$
create function public.fleet_book_add(p_fleet uuid, p_at timestamptz, p_add jsonb, p_kind text default null, p_line jsonb default null)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0431: THE ONE WRITER of public.fleet_book and public.fleet_lines. Adds p_add's numbers (zeros and non-numbers left out) to her hour (the UTC hour
-- of p_at), and with p_kind writes one line and keeps her newest 12. IT NEVER RAISES: whatever goes wrong (a lock it could not take, a deadlock) is
-- a warning, its sub-transaction alone is undone, and the fight, the pay or the delivery that called it stands as it was (0364's rule).
declare
  v_add jsonb;
begin
  if p_fleet is null or p_at is null then
    return;
  end if;
  select coalesce(jsonb_object_agg(e.key, e.value), '{}'::jsonb) into v_add
    from jsonb_each(case when jsonb_typeof(p_add) = 'object' then p_add else '{}'::jsonb end) e
   where jsonb_typeof(e.value) = 'number' and (e.value)::text::numeric <> 0;
  if v_add <> '{}'::jsonb then
    insert into public.fleet_book as b (fleet_id, hour, figs)
    values (p_fleet, to_timestamp(floor(extract(epoch from p_at) / 3600) * 3600), v_add)
    on conflict (fleet_id, hour) do update set figs = public.fleet_figs_add(b.figs, excluded.figs);
  end if;
  if p_kind is not null then
    insert into public.fleet_lines (fleet_id, at, kind, line) values (p_fleet, p_at, p_kind, coalesce(jsonb_strip_nulls(p_line), '{}'::jsonb));
    delete from public.fleet_lines l
     where l.fleet_id = p_fleet
       and l.id <= (select x.id from public.fleet_lines x where x.fleet_id = p_fleet order by x.id desc offset 12 limit 1);
  end if;
exception when others then
  raise warning 'fleet_book_add: fleet % was not booked (SQLSTATE %: %)', p_fleet, sqlstate, sqlerrm;
end
$body$
  $f$;

  -- ── 4. THE BOOKERS ──
  execute $f$
create function public.fleet_book_fight(p_navy uuid, p_pirate uuid, p_res text, p_f jsonb, p_sunk_n boolean, p_sunk_p boolean, p_now timestamptz)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0431: A NAVY SHIP FOUGHT A PIRATE SHIP (public.navy_fight, after the hulls are written). p_res is the navy's (SUNK, WON, LOST, DREW). Each ship's
-- hour gets the fight, her side of it and her hull lost (the fight's hull_lost: b the navy, a the pirate); each a line. The lower fleet id is booked
-- first (one lock order for every two-fleet booking). Never raises.
declare
  v_hn  numeric;
  v_hp  numeric;
  v_nn  text;
  v_pn  text;
  v_nat text;
  v_sea text := (select n.fought ->> 'sea' from public.navy_ships n where n.fleet_id = p_navy);
  v_nw  text := case when p_res in ('SUNK', 'WON') then 'WON' when p_res = 'LOST' then 'LOST' else 'DREW' end;
  v_pw  text := case when p_res in ('SUNK', 'WON') then 'LOST' when p_res = 'LOST' then 'WON' else 'DREW' end;
  x     record;
begin
  select coalesce(sum(h.value::numeric), 0) into v_hn from jsonb_each_text(case when jsonb_typeof(p_f -> 'hull_lost' -> 'b') = 'object' then p_f -> 'hull_lost' -> 'b' else '{}'::jsonb end) h;
  select coalesce(sum(h.value::numeric), 0) into v_hp from jsonb_each_text(case when jsonb_typeof(p_f -> 'hull_lost' -> 'a') = 'object' then p_f -> 'hull_lost' -> 'a' else '{}'::jsonb end) h;
  select f.name into v_nn from public.fleets f where f.id = p_navy;
  select f.name into v_pn from public.fleets f where f.id = p_pirate;
  select na.code into v_nat from public.navy_ships n join public.nations na on na.id = n.nation_id where n.fleet_id = p_navy;
  for x in select * from (values
             (p_navy, jsonb_build_object('fights', 1, 'won', (v_nw = 'WON')::int, 'lost', (v_nw = 'LOST')::int, 'sunk', (p_res = 'SUNK')::int,
                                         'hull', round(v_hn, 1), 'wrecks', coalesce(p_sunk_n, false)::int),
              'FIGHT', jsonb_build_object('foe', v_pn, 'foe_kind', 'PIRATE', 'result', v_nw, 'sank', p_res = 'SUNK', 'wrecked', coalesce(p_sunk_n, false), 'hull', round(v_hn, 1), 'sea', v_sea)),
             (p_pirate, jsonb_build_object('navy_fights', 1, 'won', (v_pw = 'WON')::int, 'lost', (v_pw = 'LOST')::int, 'sunk', coalesce(p_sunk_n, false)::int,
                                           'hull', round(v_hp, 1), 'wrecks', coalesce(p_sunk_p, false)::int),
              'FIGHT', jsonb_build_object('foe', v_nn, 'foe_kind', 'NAVY', 'nation', v_nat, 'result', v_pw, 'sank', coalesce(p_sunk_n, false), 'wrecked', coalesce(p_sunk_p, false), 'hull', round(v_hp, 1), 'sea', v_sea))
           ) v(fleet, figs, kind, line) order by v.fleet loop
    perform public.fleet_book_add(x.fleet, p_now, x.figs, x.kind, x.line);
  end loop;
exception when others then
  raise warning 'fleet_book_fight: % against % was not booked (SQLSTATE %: %)', p_navy, p_pirate, sqlstate, sqlerrm;
end
$body$
  $f$;

  execute $f$
create function public.fleet_book_stop(p_navy uuid, p_company uuid, p_out text, p_f jsonb, p_fine bigint, p_taken jsonb, p_at timestamptz)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0431: A NAVY SHIP STOPPED A MERCHANT (voyage.navy_meets, the navy the side b). Her hour gets the stop and the fight in it (won: PLUNDERED or RANSOM;
-- lost: DRIVEN_OFF; EVADED neither), her hull lost, the fine her country took (what the purse paid) and the prize (the cargo seized for her capital,
-- at its base value). One line. A meeting with no navy ship named (p_navy null) is not booked. Never raises.
declare
  v_hull  numeric;
  v_prize numeric;
begin
  if p_navy is null or not exists (select 1 from public.navy_ships n where n.fleet_id = p_navy) then
    return;
  end if;
  select coalesce(sum(h.value::numeric), 0) into v_hull from jsonb_each_text(case when jsonb_typeof(p_f -> 'hull_lost' -> 'b') = 'object' then p_f -> 'hull_lost' -> 'b' else '{}'::jsonb end) h;
  select coalesce(sum((e.value)::text::numeric * g.base_value), 0) into v_prize
    from jsonb_each(case when jsonb_typeof(p_taken) = 'object' then p_taken else '{}'::jsonb end) e join public.goods g on g.code = e.key
   where jsonb_typeof(e.value) = 'number';
  perform public.fleet_book_add(p_navy, p_at,
    jsonb_build_object('stops', 1, 'fights', (p_out <> 'EVADED')::int, 'won', (p_out in ('PLUNDERED', 'RANSOM'))::int, 'lost', (p_out = 'DRIVEN_OFF')::int,
                       'hull', round(v_hull, 1), 'fines', coalesce(p_fine, 0), 'prizes', round(v_prize)),
    'STOP', jsonb_build_object('foe', (select pl.company_name from public.players pl where pl.id = p_company), 'outcome', p_out,
                               'result', case when p_out in ('PLUNDERED', 'RANSOM') then 'WON' when p_out = 'DRIVEN_OFF' then 'LOST' else 'DREW' end,
                               'fine', coalesce(p_fine, 0), 'prize', round(v_prize), 'hull', round(v_hull, 1)));
exception when others then
  raise warning 'fleet_book_stop: % was not booked (SQLSTATE %: %)', p_navy, sqlstate, sqlerrm;
end
$body$
  $f$;

  execute $f$
create function public.fleet_book_refit(p_fleet uuid, p_cost bigint, p_now timestamptz)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0431: A WRECK'S REFIT WAS PAID (public.npc_refit_step for a navy or cargo ship, public.pirate_reborn for a pirate). Her hour gets the refit and its
-- cost (repairs; 0 when free); one line with her home. A merchant's or a player's fleet is not booked. Never raises.
declare
  v_home uuid;
begin
  select coalesce((select n.station_port from public.navy_ships n where n.fleet_id = p_fleet),
                  (select p.home_port from public.pirate_ships p where p.fleet_id = p_fleet),
                  (select c.home_port_id from public.cargo_ships c where c.fleet_id = p_fleet)) into v_home;
  if v_home is null and not exists (select 1 from public.navy_ships n where n.fleet_id = p_fleet)
     and not exists (select 1 from public.pirate_ships p where p.fleet_id = p_fleet) and not exists (select 1 from public.cargo_ships c where c.fleet_id = p_fleet) then
    return;
  end if;
  perform public.fleet_book_add(p_fleet, p_now, jsonb_build_object('refits', 1, 'repairs', greatest(coalesce(p_cost, 0), 0)),
    'REFIT', jsonb_build_object('cost', greatest(coalesce(p_cost, 0), 0), 'port', (select p.code from public.ports p where p.id = public.fleet_origin(p_fleet))));
exception when others then
  raise warning 'fleet_book_refit: % was not booked (SQLSTATE %: %)', p_fleet, sqlstate, sqlerrm;
end
$body$
  $f$;

  execute $f$
create function public.fleet_book_take(p_pirate uuid, p_kind text, p_amount bigint, p_victim_fleet uuid, p_victim_company uuid, p_at timestamptz)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0431: A PIRATE SHIP WAS PAID (public.pirate_ransom: a RANSOM from a company's purse; public.pirate_loot_book: a cargo ship's gold, LOOT), the gold
-- now her home's. Her hour gets loot (the sum of both), ransom or gold, and paid (one); one line naming the victim. Never raises.
begin
  if coalesce(p_amount, 0) <= 0 then
    return;
  end if;
  perform public.fleet_book_add(p_pirate, p_at,
    jsonb_build_object('loot', p_amount, case when p_kind = 'RANSOM' then 'ransom' else 'gold' end, p_amount, 'paid', 1),
    'TAKE', jsonb_build_object('how', p_kind, 'amount', p_amount,
                               'victim', coalesce((select f.name from public.fleets f where f.id = p_victim_fleet), (select pl.company_name from public.players pl where pl.id = p_victim_company)),
                               'victim_kind', case when p_victim_fleet is not null then public.fleet_kind(p_victim_fleet) end));
exception when others then
  raise warning 'fleet_book_take: % was not booked (SQLSTATE %: %)', p_pirate, sqlstate, sqlerrm;
end
$body$
  $f$;

  execute $f$
create function public.fleet_book_battle()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0431: A BATTLE CLOSED (the trigger fleet_book_battle on public.battles, when its status leaves FIGHTING: 0427's raids and players' attacks). Every
-- navy, pirate and cargo ship on its sides that came in time is booked, the lower fleet id first: the pirate that opened a raid gets raids /
-- raids_won / raids_lost, a cargo ship set upon attacked / held, any other fights / won / lost; each her hull lost (the result's hull_lost: a the
-- defenders, b the attackers, by ship) and a wreck if no hull of hers is above 0. One line each, naming the other side's opener. Never raises.
declare
  v_out  text := new.result ->> 'outcome';
  v_aw   boolean := (new.result ->> 'outcome') in ('PLUNDERED', 'RANSOM');   -- the side that attacked won
  v_dw   boolean := (new.result ->> 'outcome') = 'DRIVEN_OFF';               -- the side set upon held
  v_atk  text;
  v_def  text;
  s      record;
  v_kind text;
  v_hull numeric;
  v_won  boolean;
  v_lost boolean;
  v_wr   boolean;
begin
  select f.name into v_atk from public.battle_sides bs join public.fleets f on f.id = bs.fleet_id where bs.battle_id = new.id and bs.side = 'ATTACKER' and bs.how = 'OPENED' limit 1;
  select f.name into v_def from public.battle_sides bs join public.fleets f on f.id = bs.fleet_id where bs.battle_id = new.id and bs.side = 'DEFENDER' and bs.how = 'OPENED' limit 1;
  for s in select bs.fleet_id, bs.side, bs.how from public.battle_sides bs
            where bs.battle_id = new.id and (bs.arrives_at is null or bs.arrives_at <= new.resolves_at) order by bs.fleet_id loop
    v_kind := case when exists (select 1 from public.navy_ships n where n.fleet_id = s.fleet_id) then 'NAVY'
                   when exists (select 1 from public.pirate_ships n where n.fleet_id = s.fleet_id) then 'PIRATE'
                   when exists (select 1 from public.cargo_ships n where n.fleet_id = s.fleet_id) then 'CARGO' end;
    continue when v_kind is null;
    select coalesce(sum(h.value::numeric), 0) into v_hull
      from jsonb_each_text(case when jsonb_typeof(new.result -> 'hull_lost' -> (case when s.side = 'DEFENDER' then 'a' else 'b' end)) = 'object'
                                then new.result -> 'hull_lost' -> (case when s.side = 'DEFENDER' then 'a' else 'b' end) else '{}'::jsonb end) h
      join public.ships sh on sh.id = (case when h.key ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then h.key end)::uuid and sh.fleet_id = s.fleet_id;
    v_won := (s.side = 'ATTACKER' and v_aw) or (s.side = 'DEFENDER' and v_dw);
    v_lost := (s.side = 'ATTACKER' and v_dw) or (s.side = 'DEFENDER' and v_aw);
    v_wr := exists (select 1 from public.ships sh where sh.fleet_id = s.fleet_id) and not exists (select 1 from public.ships sh where sh.fleet_id = s.fleet_id and sh.durability > 0);
    perform public.fleet_book_add(s.fleet_id, coalesce(new.resolves_at, now()),
      case when v_kind = 'PIRATE' and s.side = 'ATTACKER' and s.how = 'OPENED' then jsonb_build_object('raids', 1, 'raids_won', v_won::int, 'raids_lost', v_lost::int)
           when v_kind = 'CARGO' and s.side = 'DEFENDER' then jsonb_build_object('attacked', 1, 'held', v_won::int)
           else jsonb_build_object('fights', 1, 'won', v_won::int, 'lost', v_lost::int) end
      || jsonb_build_object('hull', round(v_hull, 1), 'wrecks', v_wr::int),
      case when v_kind = 'PIRATE' and s.side = 'ATTACKER' and s.how = 'OPENED' then 'RAID' else 'BATTLE' end,
      jsonb_build_object('battle', new.kind, 'side', s.side, 'how', s.how, 'outcome', v_out,
                         'result', case when v_won then 'WON' when v_lost then 'LOST' else 'DREW' end,
                         'foe', case when s.side = 'ATTACKER' then v_def else v_atk end, 'hull', round(v_hull, 1), 'wrecked', v_wr));
  end loop;
  return null;
exception when others then
  raise warning 'fleet_book_battle: battle % was not booked (SQLSTATE %: %)', new.id, sqlstate, sqlerrm;
  return null;
end
$body$
  $f$;
  create trigger fleet_book_battle after update of status on public.battles
    for each row when (old.status = 'FIGHTING' and new.status is distinct from 'FIGHTING')
    execute function public.fleet_book_battle();

  -- ── 5. THE LIST (the Stats count's) ──
  execute $f$
create function public.stats_fleet_list_rows(p_kind text, p_now timestamptz)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0431: THE LIST OF ONE KIND (NAVY, PIRATE, CARGO) as the Stats count builds it: every fleet (name, Korean name for a roster pirate, country, home
  -- or station, ships, state by 0419's rule: laid up, else wrecked, else at sea, else in port) with her 7 days, and the kind's states and its
  -- 24 h and 7 d totals; `since` is the book's first hour inside the 7 days (the book starts with 0431). Reads the kind's ship table, their
  -- fleets and ships by key, and the book's 7 days (~45,000 small rows at most). Writes nothing.
  with f as (
    select n.fleet_id as id, n.nation_id as nat, n.station_port as home, n.laid_up_at as laid, null::timestamptz as wreck, null::int as ord
      from public.navy_ships n where p_kind = 'NAVY'
    union all
    select p.fleet_id, public.pirate_nation(), p.home_port, p.laid_up_at, p.wrecked_at, p.ord from public.pirate_ships p where p_kind = 'PIRATE'
    union all
    select c.fleet_id, c.nation_id, c.home_port_id, c.laid_up_at, null::timestamptz, null::int from public.cargo_ships c where p_kind = 'CARGO'),
  s as (
    select f.id, fl.name, f.ord, na.code as nation, po.code as home, x.ships,
           case when f.laid is not null then 'laid_up' when f.wreck is not null or not x.alive then 'wrecked' when fl.status = 'SAILING' then 'sea' else 'port' end as state
      from f join public.fleets fl on fl.id = f.id
      left join public.nations na on na.id = f.nat
      left join public.ports po on po.id = f.home
      cross join lateral (select count(*)::int as ships, coalesce(bool_or(sh.durability > 0), false) as alive from public.ships sh where sh.fleet_id = f.id) x),
  bk as (select fb.fleet_id, fb.hour, fb.figs from public.fleet_book fb join f on f.id = fb.fleet_id where fb.hour >= p_now - interval '7 days'),
  b as (
    select bk.fleet_id, e.key, sum((e.value)::numeric) as w, coalesce(sum((e.value)::numeric) filter (where bk.hour >= p_now - interval '24 hours'), 0) as d
      from bk cross join lateral jsonb_each_text(bk.figs) e
     group by bk.fleet_id, e.key),
  -- a fleet's row carries only what the list shows and sorts by (the headline, the hull lost, the costs): her page has the rest
  w as (select b.fleet_id, jsonb_object_agg(b.key, b.w) as week from b where b.key in ('fights', 'sunk', 'loot', 'raids', 'delivered', 'delivered_n', 'hull', 'upkeep', 'repairs')
         group by b.fleet_id),
  t as (select b.key, sum(b.d) as d, sum(b.w) as w from b group by b.key)
  select jsonb_build_object(
    'kind', p_kind,
    'fleets', (select count(*) from s), 'ships', (select coalesce(sum(s.ships), 0) from s),
    'sea', (select count(*) from s where s.state = 'sea'), 'port', (select count(*) from s where s.state = 'port'),
    'laid_up', (select count(*) from s where s.state = 'laid_up'), 'wrecked', (select count(*) from s where s.state = 'wrecked'),
    'day', (select coalesce(jsonb_object_agg(t.key, t.d), '{}'::jsonb) from t),
    'week', (select coalesce(jsonb_object_agg(t.key, t.w), '{}'::jsonb) from t),
    'since', (select min(bk.hour) from bk),
    'list', coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                        'id', s.id, 'name', s.name, 'name_ko', (select r.fleet_name_ko from public.pirate_roster r where r.ord = s.ord),
                        'nation', s.nation, 'home', s.home, 'ships', s.ships, 'state', s.state, 'week', coalesce(w.week, '{}'::jsonb)))
                        order by s.name, s.id)
                        from s left join w on w.fleet_id = s.id), '[]'::jsonb))
$body$
  $f$;
  revoke all on function public.fleet_figs_add(jsonb, jsonb) from public, anon, authenticated;
  revoke all on function public.fleet_book_add(uuid, timestamptz, jsonb, text, jsonb) from public, anon, authenticated;
  revoke all on function public.fleet_book_fight(uuid, uuid, text, jsonb, boolean, boolean, timestamptz) from public, anon, authenticated;
  revoke all on function public.fleet_book_stop(uuid, uuid, text, jsonb, bigint, jsonb, timestamptz) from public, anon, authenticated;
  revoke all on function public.fleet_book_refit(uuid, bigint, timestamptz) from public, anon, authenticated;
  revoke all on function public.fleet_book_take(uuid, text, bigint, uuid, uuid, timestamptz) from public, anon, authenticated;
  revoke all on function public.fleet_book_battle() from public, anon, authenticated;
  revoke all on function public.stats_fleet_list_rows(text, timestamptz) from public, anon, authenticated;

  -- ── 6. THE READS ──
  execute $f$
create function world.stats_fleet_list(p_kind text)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0431 (the owner, 2026-11-15: "a separate tab for navy, pirates, and cargoships like merchants"): the Stats face of one kind, NAVY, PIRATE or
  -- CARGO: the newest count's list (public.stats_fleet_list, one row by key). Before the first count, `counted_at` null. Public.
  select coalesce((select x.figures || jsonb_build_object('at', now(), 'counted_at', x.at) from public.stats_fleet_list x where x.kind = upper(p_kind)),
                  jsonb_build_object('at', now(), 'kind', upper(p_kind), 'counted_at', null))
$body$
  $f$;
  revoke all on function world.stats_fleet_list(text) from public, anon;
  grant execute on function world.stats_fleet_list(text) to authenticated;

  execute $f$
create function world.stats_fleet(p_fleet uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0431 (the owner, 2026-11-15: "by clicking on navy, i should be able to see how much damage it took, how much money = loot it took, fixing fees,
-- and so much more ... for cargoships i want to see from what city to what city it delivered"): ONE navy, pirate or cargo ship's Stats page, read at
-- a press and each second while open. Where she is and what she does (voyage.where_now, her voyage's from, to, departure and arrival), her ships
-- (hull, crew), her last 24 h and 7 days (public.fleet_book, <=192 rows by key), her last 12 lines (public.fleet_lines), and for a cargo ship her
-- last 12 gold rows (public.convoy_cargo by its fleet index: where, how much, from which city it was loaded, how long after the load) and what she
-- carries now. Refuses E_NOT_FOUND for any fleet that is not one of the three. Public: each is already on the map's cards.
declare
  v_kind  text;
  v_nat   uuid;
  v_home  uuid;
  v_mis   text;
  v_laid  timestamptz;
  v_wreck timestamptz;
  v_ord   int;
  f       public.fleets%rowtype;
  w       record;
  v       public.voyages%rowtype;
  v_alive boolean;
  v_out   jsonb;
begin
  select 'NAVY', n.nation_id, n.station_port, n.mission, n.laid_up_at, null::timestamptz, null::int into v_kind, v_nat, v_home, v_mis, v_laid, v_wreck, v_ord
    from public.navy_ships n where n.fleet_id = p_fleet;
  if v_kind is null then
    select 'PIRATE', public.pirate_nation(), p.home_port, p.mission, p.laid_up_at, p.wrecked_at, p.ord into v_kind, v_nat, v_home, v_mis, v_laid, v_wreck, v_ord
      from public.pirate_ships p where p.fleet_id = p_fleet;
  end if;
  if v_kind is null then
    select 'CARGO', c.nation_id, c.home_port_id, null::text, c.laid_up_at, null::timestamptz, null::int into v_kind, v_nat, v_home, v_mis, v_laid, v_wreck, v_ord
      from public.cargo_ships c where c.fleet_id = p_fleet;
  end if;
  if v_kind is null then
    raise exception 'E_NOT_FOUND: there is no such navy, pirate or cargo ship' using errcode = 'P0001';
  end if;
  select x.* into f from public.fleets x where x.id = p_fleet;
  select * into w from voyage.where_now(p_fleet);
  select x.* into v from public.voyages x where x.id = w.voyage_id;
  v_alive := exists (select 1 from public.ships sh where sh.fleet_id = p_fleet and sh.durability > 0);
  v_out := jsonb_strip_nulls(jsonb_build_object(
    'at', now(), 'kind', v_kind, 'id', f.id, 'name', f.name,
    'name_ko', (select r.fleet_name_ko from public.pirate_roster r where r.ord = v_ord),
    'house', (select r.house_name from public.pirate_roster r where r.ord = v_ord),
    'house_ko', (select r.house_name_ko from public.pirate_roster r where r.ord = v_ord),
    'nation', (select na.code from public.nations na where na.id = v_nat),
    'home', (select p.code from public.ports p where p.id = v_home),
    'mission', v_mis,
    'state', case when v_laid is not null then 'laid_up' when v_wreck is not null or not v_alive then 'wrecked' when f.status = 'SAILING' then 'sea' else 'port' end,
    'status', w.status, 'port', (select p.code from public.ports p where p.id = w.port_id),
    'from', (select p.code from public.ports p where p.id = v.origin_port_id), 'to', (select p.code from public.ports p where p.id = v.dest_port_id),
    'departed', v.departed_at, 'eta', w.eta))
  || jsonb_build_object(
    'ships', (select coalesce(jsonb_agg(jsonb_build_object('name', sh.name, 'class', c.name, 'class_code', c.code, 'flagship', sh.is_flagship,
                                                         'hull', sh.durability, 'hull_max', (select b.durability from public.ship_base(sh.id) b), 'crew', sh.crew)
                                       order by sh.is_flagship desc, sh.name), '[]'::jsonb)
                from public.ships sh join public.ship_classes c on c.id = sh.class_id where sh.fleet_id = p_fleet),
    'day', (select coalesce(jsonb_object_agg(z.key, z.n), '{}'::jsonb) from (select e.key, sum((e.value)::numeric) as n from public.fleet_book fb cross join lateral jsonb_each_text(fb.figs) e
                                                                            where fb.fleet_id = p_fleet and fb.hour >= now() - interval '24 hours' group by e.key) z),
    'week', (select coalesce(jsonb_object_agg(z.key, z.n), '{}'::jsonb) from (select e.key, sum((e.value)::numeric) as n from public.fleet_book fb cross join lateral jsonb_each_text(fb.figs) e
                                                                             where fb.fleet_id = p_fleet and fb.hour >= now() - interval '7 days' group by e.key) z),
    'since', (select min(fb.hour) from public.fleet_book fb where fb.fleet_id = p_fleet and fb.hour >= now() - interval '7 days'),
    'book_from', (select min(fb.hour) from public.fleet_book fb where fb.hour >= now() - interval '7 days'),
    'lines', (select coalesce(jsonb_agg(jsonb_build_object('at', l.at, 'kind', l.kind) || l.line order by l.id desc), '[]'::jsonb)
                from (select x.* from public.fleet_lines x where x.fleet_id = p_fleet order by x.id desc limit 12) l));
  if v_kind = 'CARGO' then
    v_out := v_out || jsonb_build_object('cargo', jsonb_build_object(
      'aboard', coalesce((select a.aboard from public.cargo_ship_aboard(p_fleet) a), 0),
      'load', (select jsonb_build_object('port', p.code, 'ducats', l.ducats, 'at', l.created_at)
                 from public.cargo_ship_aboard(p_fleet) a join public.convoy_cargo l on l.id = a.load_id join public.ports p on p.id = l.port_id),
      'rows', (select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object('at', c.created_at, 'stage', c.stage, 'port', p.code, 'ducats', c.ducats,
                                                                         'from', lp.code, 'after', round(extract(epoch from c.created_at - l.created_at))))
                                         order by c.id desc), '[]'::jsonb)
                 from (select x.* from public.convoy_cargo x where x.fleet_id = p_fleet order by x.id desc limit 12) c
                 join public.ports p on p.id = c.port_id
                 left join public.convoy_cargo l on l.id = c.load_id
                 left join public.ports lp on lp.id = l.port_id)));
  end if;
  return v_out;
end
$body$
  $f$;
  revoke all on function world.stats_fleet(uuid) from public, anon;
  grant execute on function world.stats_fleet(uuid) to authenticated;
  comment on function world.stats_fleet_list(text) is '0431: the Stats faces Navy, Pirates and Cargo: the newest Stats count''s list of the kind (public.stats_fleet_list). A read.';
  comment on function world.stats_fleet(uuid) is '0431: one navy, pirate or cargo ship''s Stats page: where she is, her ships, her 24 h and 7 d (public.fleet_book), her last lines (public.fleet_lines), a cargo ship''s gold rows. A read.';

  -- ── 7. THE HUNKS ──
  create temp table hunk_0431 (ord int primary key, fn text, old text, new text) on commit drop;
  insert into hunk_0431 values
  (1, c_cut[1],
$h$  v_ev := public.emit_event(null, 'NAVY_FIGHT', jsonb_build_object(
$h$,
$h$  perform public.fleet_book_fight(p_navy, p_pirate, v_res, v_f, v_sunk_n, v_sunk_p, p_now);   -- 0431: each ship's book and line (it never raises)
  v_ev := public.emit_event(null, 'NAVY_FIGHT', jsonb_build_object(
$h$),
  (2, c_cut[2],
$h$  perform public.navy_fine(p_player, h.nation_id, v_fine, p_at);
$h$,
$h$  perform public.fleet_book_stop(h.fleet_id, p_player, v_out, v_f, public.navy_fine(p_player, h.nation_id, v_fine, p_at), v_taken, p_at);   -- 0431: the fine as paid, booked to the navy ship (it never raises)
$h$),
  (3, c_cut[3],
$h$  select coalesce(array_agg(p.to_port) filter (where p.k <= v_can and p.to_port <> v_cap), '{}') into v_to from p;
$h$,
$h$  select coalesce(array_agg(p.to_port) filter (where p.k <= v_can and p.to_port <> v_cap), '{}') into v_to from p;
  perform public.fleet_book_add(n.fleet_id, p_now, jsonb_build_object('upkeep', v_slice)) from public.navy_ships_in_service n where n.nation_id = v_nat and n.unpaid_since is null;   -- 0431: each ship paid, her hour's upkeep
$h$),
  (4, c_cut[4],
$h$    update public.pirate_ships n set unpaid_since = case when v_paid > 0 then null else coalesce(n.unpaid_since, p_now) end where n.fleet_id = r.fleet_id;
$h$,
$h$    update public.pirate_ships n set unpaid_since = case when v_paid > 0 then null else coalesce(n.unpaid_since, p_now) end where n.fleet_id = r.fleet_id;
    if v_paid > 0 then perform public.fleet_book_add(r.fleet_id, p_now, jsonb_build_object('upkeep', v_paid)); end if;   -- 0431: her hour's upkeep
$h$),
  (5, c_cut[5],
$h$  perform public.fleet_mend(p_fleet);

  -- A merchant's hands$h$,
$h$  perform public.fleet_mend(p_fleet);
  perform public.fleet_book_refit(p_fleet, v_cost, p_now);   -- 0431: a navy or cargo ship's refit, booked (a merchant's is not; it never raises)

  -- A merchant's hands$h$),
  (6, c_cut[6],
$h$  perform public.fleet_mend(p_fleet);
  perform public.fleet_hands(p_fleet, n.home_port);
$h$,
$h$  perform public.fleet_mend(p_fleet);
  perform public.fleet_book_refit(p_fleet, case when v_payer = 'FREE' then 0 else v_cost end, p_now);   -- 0431: her refit, booked (it never raises)
  perform public.fleet_hands(p_fleet, n.home_port);
$h$),
  (7, c_cut[7],
$h$  perform public.pay_city(p_company, n.home_port, 'RANSOM', v_take, p_event);
$h$,
$h$  perform public.pay_city(p_company, n.home_port, 'RANSOM', v_take, p_event);
  perform public.fleet_book_take(p_fleet, 'RANSOM', v_take, null, p_company, now());   -- 0431: booked to the pirate ship (it never raises)
$h$),
  (8, c_cut[8],
$h$  perform public.treasury_post(n.home_port, 'LOOT', v_take, null, p_event, true);
$h$,
$h$  perform public.treasury_post(n.home_port, 'LOOT', v_take, null, p_event, true);
  perform public.fleet_book_take(p_fleet, 'LOOT', v_take, p_victim, c.player_id, now());   -- 0431: booked to the pirate ship (it never raises)
$h$),
  (9, c_cut[9],
$h$  returning id into v_id;
$h$,
$h$  returning id into v_id;
  perform public.fleet_book_add(p_fleet, now(), jsonb_build_object(lower(p_stage), p_ducats, lower(p_stage) || '_n', 1));   -- 0431: the cargo ship's hour (it never raises)
$h$),
  (10, c_cut[10],
$h$  delete from public.stats_fleets x where x.at < p_now - interval '26 hours';
$h$,
$h$  delete from public.stats_fleets x where x.at < p_now - interval '26 hours';
  -- 0431: THE NAVY, PIRATES AND CARGO FACES (the owner, 2026-11-15: "a separate tab for navy, pirates, and cargoships like merchants"): one row a
  -- kind, replaced (public.stats_fleet_list_rows); and the fleets' book and lines kept 8 days.
  -- budget: 3 rows written a count; the book's hours older than 8 days deleted (about what one hour wrote 8 days ago: ~130-250 rows) and lines past 8 days (a few rows); ~45,000 small book rows read
  insert into public.stats_fleet_list (kind, at, figures)
  select k.kind, p_now, public.stats_fleet_list_rows(k.kind, p_now) from (values ('NAVY'), ('PIRATE'), ('CARGO')) k(kind)
  on conflict (kind) do update set at = excluded.at, figures = excluded.figures;
  delete from public.fleet_book b where b.hour < p_now - interval '8 days';
  delete from public.fleet_lines l where l.at < p_now - interval '8 days';
$h$),
  (11, c_cut[11],
$h$      ('world',       'stats_fleets',          ''),
$h$,
$h$      ('world',       'stats_fleets',          ''),
      -- 0431: the Stats faces Navy, Pirates and Cargo: the list of a kind, and one fleet's page.
      ('world',       'stats_fleet_list',      'text'),
      ('world',       'stats_fleet',           'uuid'),
$h$);
  for h in select * from hunk_0431 order by ord loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    v_n := (length(v_def) - length(replace(v_def, h.old, ''))) / length(h.old);
    if v_n <> 1 then
      raise exception '0431 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', h.ord, h.fn, v_n;
    end if;
    execute replace(v_def, h.old, h.new);
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    if (length(v_def) - length(replace(v_def, h.new, ''))) / length(h.new) <> 1 then
      raise exception '0431 self-assert FAIL: hunk % of % is not in the new body once', h.ord, h.fn;
    end if;
    if (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
          from pg_proc p where p.oid = h.fn::regprocedure) <> (select p.meta from pre_0431 p where p.fn = h.fn) then
      raise exception '0431 self-assert FAIL: the grants, volatility, definer, search path or owner of % moved', h.fn;
    end if;
  end loop;
  for h in select p.fn, p.def from pre_0431 p loop
    v_def := replace(pg_get_functiondef(h.fn::regprocedure), E'\r', '');
    for v_z in select x.old, x.new from hunk_0431 x where x.fn = h.fn order by x.ord desc loop
      v_def := replace(v_def, v_z.new, v_z.old);
    end loop;
    if v_def <> h.def then
      raise exception '0431 self-assert FAIL: % does not reverse to its pre-image', h.fn;
    end if;
  end loop;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and not exists (select 1 from unnest(c_cut) f where f::regprocedure = p.oid)
         and not exists (select 1 from unnest(c_new) f where f::regprocedure = p.oid)) <> v_fn_before then
    raise exception '0431 self-assert FAIL: another function moved';
  end if;
  if exists (select 1 from unnest(c_new) f where f like 'public.%' and (has_function_privilege('authenticated', f, 'execute') or has_function_privilege('anon', f, 'execute'))) then
    raise exception '0431 self-assert FAIL: a server-only function is open to a client';
  end if;
  if exists (select 1 from unnest(array['world.stats_fleet_list(text)', 'world.stats_fleet(uuid)']) f
              where not has_function_privilege('authenticated', f, 'execute') or has_function_privilege('anon', f, 'execute')
                 or (select p.provolatile from pg_proc p where p.oid = f::regprocedure) <> 's')
     or (select p.provolatile from pg_proc p where p.oid = 'public.stats_fleet_list_rows(text,timestamptz)'::regprocedure) <> 's'
     or (select count(*) from public.client_rpc_entry_points() e where e.schema_name = 'world' and e.function_name in ('stats_fleet_list', 'stats_fleet') and e.fn is not null) <> 2
     or not exists (select 1 from pg_trigger t where t.tgrelid = 'public.battles'::regclass and t.tgname = 'fleet_book_battle' and t.tgenabled = 'O') then
    raise exception '0431 self-assert FAIL: a read is not STABLE, not in the registry or not granted to authenticated alone; or the battle trigger is not there';
  end if;

  -- ── 8. THE PROBE, rolled back: a fleet's hour summed, her lines trimmed to 12, a broken booking only warned, the lists built, a navy ship's page ──
  begin
    select x.id into v_fleet from public.fleets x order by x.id limit 1;
    if v_fleet is not null then
      perform public.fleet_book_add(v_fleet, now(), jsonb_build_object('fights', 1, 'hull', 12.5, 'nothing', 0, 'word', 'x'));
      perform public.fleet_book_add(v_fleet, now(), jsonb_build_object('fights', 2, 'upkeep', 40));
      for v_n in 1 .. 14 loop
        perform public.fleet_book_add(v_fleet, now(), null, 'FIGHT', jsonb_build_object('n', v_n, 'gone', null));
      end loop;
      perform public.fleet_book_add(v_fleet, now(), '{"fights": 1}'::jsonb, 'NO_SUCH_KIND', null);   -- a line that cannot be written: a warning, and her hour unmoved
      if (select x.figs from public.fleet_book x where x.fleet_id = v_fleet) <> '{"fights": 3, "hull": 12.5, "upkeep": 40}'::jsonb
         or (select count(*) from public.fleet_book x where x.fleet_id = v_fleet) <> 1
         or (select count(*) from public.fleet_lines x where x.fleet_id = v_fleet) <> 12
         or (select min((x.line ->> 'n')::int) from public.fleet_lines x where x.fleet_id = v_fleet) <> 3
         or exists (select 1 from public.fleet_lines x where x.fleet_id = v_fleet and x.line ? 'gone') then
        raise exception '0431 self-assert FAIL: the book did not add up or trim: %, % lines', (select x.figs from public.fleet_book x where x.fleet_id = v_fleet), (select count(*) from public.fleet_lines x where x.fleet_id = v_fleet);
      end if;
    end if;
    v_tp := clock_timestamp();
    v_r := public.stats_fleet_list_rows('NAVY', now()) || jsonb_build_object('p', public.stats_fleet_list_rows('PIRATE', now()), 'c', public.stats_fleet_list_rows('CARGO', now()));
    v_ms := round(extract(epoch from clock_timestamp() - v_tp) * 1000);
    if v_ms > 3000 then
      raise exception '0431 self-assert FAIL: the three lists took % ms (budget 3,000)', v_ms;
    end if;
    if jsonb_typeof(v_r -> 'list') <> 'array' or jsonb_typeof(v_r -> 'p' -> 'list') <> 'array' or jsonb_typeof(v_r -> 'c' -> 'list') <> 'array'
       or (v_r ->> 'fleets')::int <> (v_r ->> 'sea')::int + (v_r ->> 'port')::int + (v_r ->> 'laid_up')::int + (v_r ->> 'wrecked')::int
       or (v_r -> 'c' ->> 'fleets')::int <> (select count(*) from public.cargo_ships) then
      raise exception '0431 self-assert FAIL: the lists are not whole: %', v_r - 'list';
    end if;
    if (world.stats_fleet_list('navy') ->> 'counted_at') is not null then
      raise exception '0431 self-assert FAIL: an empty list read a count';
    end if;
    insert into public.stats_fleet_list (kind, at, figures) values ('NAVY', now(), v_r - 'p' - 'c');
    if (world.stats_fleet_list('navy') ->> 'counted_at')::timestamptz <> now() or jsonb_typeof(world.stats_fleet_list('NAVY') -> 'list') <> 'array' then
      raise exception '0431 self-assert FAIL: the list was not read back';
    end if;
    select n.fleet_id into v_fleet from public.navy_ships n order by n.fleet_id limit 1;
    if v_fleet is not null then
      perform public.fleet_book_add(v_fleet, now(), '{"upkeep": 50}'::jsonb, 'REFIT', '{"cost": 7}'::jsonb);
      v_r := world.stats_fleet(v_fleet);
      if v_r ->> 'kind' <> 'NAVY' or (v_r -> 'day' ->> 'upkeep')::numeric < 50 or v_r -> 'lines' -> 0 ->> 'kind' <> 'REFIT' or jsonb_typeof(v_r -> 'ships') <> 'array' then
        raise exception '0431 self-assert FAIL: a navy ship''s page: %', v_r;
      end if;
      v_note := format('the book adds, trims to 12 and only warns; the three lists in %s ms; a navy ship''s page read (%s ships)', v_ms, jsonb_array_length(v_r -> 'ships'));
    else
      v_note := format('the book adds, trims to 12 and only warns; the three lists in %s ms; no navy ship in this world to read a page of', v_ms);
    end if;
    begin
      perform world.stats_fleet(gen_random_uuid());
      raise exception '0431 self-assert FAIL: a fleet that is none of the three was read';
    exception when sqlstate 'P0001' then
      if sqlerrm not like 'E_NOT_FOUND%' then raise; end if;
    end;
    raise exception sqlstate 'BV431';
  exception when sqlstate 'BV431' then null;
  end;
  if exists (select 1 from public.fleet_book) or exists (select 1 from public.fleet_lines) or exists (select 1 from public.stats_fleet_list) then
    raise exception '0431 self-assert FAIL: the probe was not rolled back';
  end if;
  if v_note not like 'the book%' then
    raise exception '0431 self-assert FAIL: the probe did not run to its end';
  end if;

  perform public.news_update('0431', 'Stats: navy, pirates, cargo', '통계: 해군, 해적, 화물선');
  if clock_timestamp() - v_t0 > interval '15 seconds' then
    raise exception '0431 self-assert FAIL: the file took % (budget 15 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0431 self-assert ok: THE STATS OPEN EVERY FLEET. Eleven hunks over eleven bodies, each once and reversing; grants and volatility unmoved; no other function moved; public.fleet_book, public.fleet_lines, public.stats_fleet_list, the writer, five bookers (one a trigger on public.battles), the list, world.stats_fleet_list and world.stats_fleet (registry, authenticated). Probe: %; % ms.',
    v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end $m$;
