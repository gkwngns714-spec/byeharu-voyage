-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0308 — CARGO SHIPS EXIST: a crown's own ship and the book of what she carries, dark
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Owner, 2026-11-05: "transportation ship ... cargo ship ... with different graphics. npc like merchants but different." Step 3 of the REVIEW at the top of
-- docs/CITY_CONVOYS.md, slice V1. Words: Cargo ship, Funds, Shipment. Funds only: no goods run.
--
-- DARK: convoys_enabled is false, public.cargo_ships_commission makes nothing while it is, and nothing calls it. This file writes no row to players, fleets,
-- ships, npc_houses or npc_fleets on any world, so the game is byte for byte today's. Instant aid (public.crown_aid) stays the one aid loop; no live money path moves.
--
-- HOW A CARGO SHIP EXISTS (read on prod, docs/dev-log/2026-11-05-cargo-ships.md):
--   a real public.fleets row with one empty hull, owned by a house of her own (public.players, is_npc, purse 0), with a row in public.cargo_ships and NO row in
--   public.npc_houses or public.npc_fleets. Merchant logic walks those two tables, so she can never be tended, invested, gifted or refounded. A real fleet, so the
--   voyage engine (voyage.depart, voyage.settle, voyage.where_now) and compaction take her with no fork. One house a ship: assert_house_caps allows a house fleet_max (2)
--   fleets, and that cap is a live path this file does not touch. The hull has no crew: no wage, no stores, never dry.
--
-- WHAT THIS FILE DOES:
--   1. three knobs: convoys_enabled false, convoy_ships_per_nation 5, convoy_ship_class 'qpinnace'.
--   2. three flow kinds in public.stats_flow_words, all moved: CONVOY_LOAD, CONVOY_DELIVER, CONVOY_RETURN. None is written yet.
--   3. public.cargo_ships: THE kind. A row here is a cargo ship. Server-only.
--   4. public.convoy_cargo: the book of funds aboard, APPEND-ONLY (public.forbid_mutation, as public.capital_gifts). A LOADED row, then its closing rows, DELIVERED or
--      RETURNED, never more than was loaded (public.tg_convoy_cargo_closes), so one load serves several cities.
--   5. public.convoys_on(), public.fleet_kind(fleet), public.cargo_ships_commission(nation).
--
-- NOT TOUCHED: every existing function, table, trigger and knob. No hunk.
--
-- SELF-ASSERT (a probe nation of two rolled-back harbours; no real city, no real game step, per docs/OPS_HEALTH.md section 4): dark makes nothing; lit makes exactly the
-- knob's count, each DOCKED at the capital, one empty flagship, purse 0, no ledger or event row, a second call makes none; none in a merchant table or roster; a load is
-- closed by two kinds of row in the two purses and the sum of purses does not move; the book refuses an update, a delete, an over-closing, another fleet's closing;
-- nothing else moved; nothing of the probe survives. THE REAL VOYAGE ENGINE AND THE MAP ARE PROVED IN CI, not here: proof 18, scripts/db/proofs/18_cargo_ships.sql.
-- Mutation controls: scripts/ops/harness/cargo-ships/proof-0308.mjs (local).
--
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 45 s, lock_timeout 5 s first. Work: six rows, two tables, four functions, catalog reads, one probe.
--   Self-assert fails above 45 s.
-- ROLLBACK (forward, a NEW migration, owner only): nothing is lit, so none is needed; the knob stays false.
-- VERSION: 0308 - prod head 0307 (2026-11-05).
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_fn_before    text;
  v_cfg_before   text;
  v_word_before  text;
  v_trig_before  text;
  v_t0   timestamptz := clock_timestamp();
  v_mark bigint;
  v_nat  uuid;
  v_cap  uuid;
  v_city uuid;
  v_sum  bigint;
  v_fl   uuid;
  v_fl2  uuid;
  v_pl   uuid;
  v_pl2  uuid;
  v_class text;
  v_load bigint;
  v_all  jsonb;
  v_x    jsonb := '{}'::jsonb;
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('public.form_fleet(uuid,text,uuid)') is null or to_regprocedure('public.forbid_mutation()') is null
     or to_regclass('public.stats_flow_words') is null or to_regprocedure('public.crown_aid(uuid)') is null then
    raise exception '0308 refuses: 0096 / 0214 / 0306 (a fleet is formed, the words, the aid) are not in this world';
  end if;
  if to_regclass('public.cargo_ships') is not null or to_regclass('public.convoy_cargo') is not null
     or exists (select 1 from public.world_config c where c.key like 'convoy%')
     or exists (select 1 from public.stats_flow_words w where w.kind like 'CONVOY%') then
    raise exception '0308 refuses: it has been applied once';
  end if;
  if not exists (select 1 from public.ship_classes c where c.code = 'qpinnace') then
    raise exception '0308 refuses: no class qpinnace in this world';
  end if;

  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p');
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before from public.world_config c;
  select md5(string_agg(w.kind || ':' || w.side || ':' || w.word || ':' || w.ord, ',' order by w.kind)) into v_word_before from public.stats_flow_words w;
  select md5(string_agg(t.tgrelid::regclass::text || ':' || t.tgname || ':' || t.tgenabled::text, ',' order by t.tgrelid::regclass::text, t.tgname)) into v_trig_before
    from pg_trigger t where not t.tgisinternal;

  -- ── 1. THE KNOBS ──
  insert into public.world_config (key, value, description) values
    ('convoys_enabled', 'false'::jsonb,
     '0308: cargo ships. False: public.cargo_ships_commission makes nothing and the game is today''s. Owner only.'),
    ('convoy_ships_per_nation', to_jsonb(5),
     '0308: cargo ships a realm keeps. 5 keeps one passing every city about hourly on one circuit of the realm (docs/dev-log/2026-11-05-cargo-ships.md, the sizing).'),
    ('convoy_ship_class', to_jsonb('qpinnace'::text),
     '0308: public.ship_classes.code of a cargo ship''s hull, what she sails like. The map draws her by her kind (docs/CITY_CONVOYS.md section 2), not by this class.');

  -- ── 2. THE WORDS: funds move, none is made ──
  insert into public.stats_flow_words (kind, side, word, ord) values
    ('CONVOY_LOAD', 'moved', 'Funds loaded', 44),
    ('CONVOY_DELIVER', 'moved', 'Funds delivered', 45),
    ('CONVOY_RETURN', 'moved', 'Funds returned', 46);

  -- ── 3. THE KIND ──
  create table public.cargo_ships (
    fleet_id     uuid primary key references public.fleets(id) on delete cascade,
    player_id    uuid not null unique references public.players(id) on delete cascade,
    nation_id    uuid not null references public.great_powers(nation_id),
    home_port_id uuid not null references public.ports(id),
    ord          integer not null check (ord >= 1),
    created_at   timestamptz not null default now(),
    unique (nation_id, ord),
    unique (fleet_id, player_id)
  );
  comment on table public.cargo_ships is
    '0308 (docs/CITY_CONVOYS.md section 2): THE kind. A fleet with a row here is a cargo ship: a crown''s, based at home_port_id, her capital. Her house (player_id) is hers alone, '
    'is_npc, purse 0, and has no row in public.npc_houses, as her fleet has none in public.npc_fleets: no merchant logic can reach her. Written by public.cargo_ships_commission alone. Server-only.';
  alter table public.cargo_ships enable row level security;
  revoke all on table public.cargo_ships from public, anon, authenticated;

  -- ── 4. THE BOOK OF FUNDS ABOARD ──
  create table public.convoy_cargo (
    id         bigint generated always as identity primary key,
    stage      text   not null check (stage in ('LOADED', 'DELIVERED', 'RETURNED')),
    fleet_id   uuid   not null,
    player_id  uuid   not null,
    port_id    uuid   not null references public.ports(id),
    ducats     bigint not null check (ducats > 0),
    load_id    bigint references public.convoy_cargo(id),
    created_at timestamptz not null default now(),
    constraint convoy_cargo_a_load_has_no_load check ((stage = 'LOADED') = (load_id is null)),
    constraint convoy_cargo_is_a_ships foreign key (fleet_id, player_id) references public.cargo_ships(fleet_id, player_id)
  );
  create index convoy_cargo_fleet on public.convoy_cargo (fleet_id, id);
  create index convoy_cargo_load on public.convoy_cargo (load_id) where load_id is not null;
  comment on table public.convoy_cargo is
    '0308 (docs/CITY_CONVOYS.md section 3): the funds aboard a cargo ship. A LOADED row at the capital (port_id), then closing rows naming it (load_id): DELIVERED at a city, RETURNED at the capital where it was loaded. '
    'One load serves several cities. Aboard = a load less its closing rows. player_id is the ship''s own house (public.forbid_mutation reads it). APPEND-ONLY (public.forbid_mutation, as events, ledger and capital_gifts). Each row is one side of a CONVOY_* flow. Read by any signed-in player.';
  create trigger convoy_cargo_append_only
    before update or delete on public.convoy_cargo
    for each row execute function public.forbid_mutation();
  alter table public.convoy_cargo enable row level security;
  revoke all on table public.convoy_cargo from public, anon, authenticated;
  revoke all on sequence public.convoy_cargo_id_seq from public, anon, authenticated;
  grant select on table public.convoy_cargo to authenticated;
  create policy convoy_cargo_read on public.convoy_cargo for select to authenticated using (true);

  execute $f$
create function public.tg_convoy_cargo_closes()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0308: a closing row is true to its load: the same ship, a return to the port it left, and never more closed than was loaded. So funds can leave a ship only once.
declare
  l      public.convoy_cargo%rowtype;
  v_shut bigint;
begin
  if new.load_id is null then
    return new;
  end if;
  select * into l from public.convoy_cargo c where c.id = new.load_id for update;
  if l.stage <> 'LOADED' or l.fleet_id <> new.fleet_id or (new.stage = 'RETURNED' and new.port_id <> l.port_id) then
    raise exception 'E_CARGO_LOAD: this closing row is not true to load %', new.load_id using errcode = '23514';
  end if;
  select coalesce(sum(c.ducats), 0) into v_shut from public.convoy_cargo c where c.load_id = new.load_id;
  if v_shut + new.ducats > l.ducats then
    raise exception 'E_CARGO_OVER: load % carried %, % is closed, % more is too much', new.load_id, l.ducats, v_shut, new.ducats using errcode = '23514';
  end if;
  return new;
end
$body$
  $f$;
  revoke all on function public.tg_convoy_cargo_closes() from public, anon, authenticated;
  create trigger convoy_cargo_closes
    before insert on public.convoy_cargo
    for each row execute function public.tg_convoy_cargo_closes();

  -- ── 5. THE SWITCH, THE KIND, THE COMMISSION ──
  execute $f$
create function public.convoys_on()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0308: THE one reader of convoys_enabled.
  select public.wc('convoys_enabled') = 'true'::jsonb
$body$
  $f$;
  revoke all on function public.convoys_on() from public, anon, authenticated;

  execute $f$
create function public.fleet_kind(p_fleet uuid)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0308: THE answer to what a fleet is: CARGO_SHIP (public.cargo_ships), MERCHANT (public.npc_fleets), else COMPANY, a player's. Null for no such fleet.
  select case when exists (select 1 from public.cargo_ships c where c.fleet_id = f.id) then 'CARGO_SHIP'
              when exists (select 1 from public.npc_fleets n where n.fleet_id = f.id) then 'MERCHANT'
              else 'COMPANY' end
    from public.fleets f where f.id = p_fleet
$body$
  $f$;
  revoke all on function public.fleet_kind(uuid) from public, anon, authenticated;

  execute $f$
create function public.cargo_ships_commission(p_nation uuid)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $body$
-- 0308: THE one place a cargo ship is made: lit, the ships a great power is missing up to convoy_ships_per_nation, each DOCKED at its capital, by the hands every fleet
-- is made by (public.form_fleet, public.commission_ship). Dark, nothing. Answers how many it made. Moves no gold: her house's purse is 0 and no ledger row is written.
declare
  v_code   text;
  v_cap    uuid;
  v_player uuid;
  v_fleet  uuid;
  v_n      int;
  v_made   int := 0;
begin
  if not public.convoys_on() then
    return 0;
  end if;
  select n.code, p.id into v_code, v_cap
    from public.great_powers g
    join public.nations n on n.id = g.nation_id
    join public.ports p on p.code = n.capital_port_code and p.kind = 'HARBOUR'
   where g.nation_id = p_nation;
  if v_cap is null then
    raise exception 'E_NO_CAPITAL: nation % is not a great power with a harbour for a capital', p_nation using errcode = 'P0001';
  end if;
  for v_n in 1 .. public.wc_int('convoy_ships_per_nation') loop
    continue when exists (select 1 from public.cargo_ships c where c.nation_id = p_nation and c.ord = v_n);
    insert into public.players (company_name, nation_id, ducats, is_npc)
    values (format('Crown Cargo %s %s', v_code, v_n), p_nation, 0, true)
    returning id into v_player;
    v_fleet := public.form_fleet(v_player, format('Cargo ship %s', v_n), v_cap);
    perform public.commission_ship(v_player, v_fleet, public.wc_text('convoy_ship_class'), format('Cargo ship %s', v_n), true, false);
    insert into public.cargo_ships (fleet_id, player_id, nation_id, home_port_id, ord)
    values (v_fleet, v_player, p_nation, v_cap, v_n);
    v_made := v_made + 1;
  end loop;
  return v_made;
end
$body$
  $f$;
  revoke all on function public.cargo_ships_commission(uuid) from public, anon, authenticated;

  -- ── 6. THE SELF-ASSERT: the catalog; nothing else moved ──
  if exists (select 1 from public.cargo_ships) or exists (select 1 from public.convoy_cargo) then
    raise exception '0308 self-assert FAIL: the new tables are not empty';
  end if;
  if public.convoys_on() or public.wc('convoys_enabled') <> 'false'::jsonb then
    raise exception '0308 self-assert FAIL: cargo ships are not dark';
  end if;
  if not (select c.relrowsecurity from pg_class c where c.oid = 'public.cargo_ships'::regclass)
     or not (select c.relrowsecurity from pg_class c where c.oid = 'public.convoy_cargo'::regclass) then
    raise exception '0308 self-assert FAIL: a new table has no row security';
  end if;
  if has_table_privilege('anon', 'public.cargo_ships', 'select') or has_table_privilege('authenticated', 'public.cargo_ships', 'select')
     or has_table_privilege('anon', 'public.convoy_cargo', 'select')
     or not has_table_privilege('authenticated', 'public.convoy_cargo', 'select')
     or has_table_privilege('authenticated', 'public.convoy_cargo', 'insert') or has_table_privilege('authenticated', 'public.convoy_cargo', 'update')
     or has_table_privilege('authenticated', 'public.convoy_cargo', 'delete') then
    raise exception '0308 self-assert FAIL: a client can reach what it should not';
  end if;
  if has_function_privilege('anon', 'public.cargo_ships_commission(uuid)', 'execute') or has_function_privilege('authenticated', 'public.cargo_ships_commission(uuid)', 'execute')
     or has_function_privilege('anon', 'public.fleet_kind(uuid)', 'execute') or has_function_privilege('authenticated', 'public.fleet_kind(uuid)', 'execute')
     or has_function_privilege('anon', 'public.convoys_on()', 'execute') or has_function_privilege('authenticated', 'public.convoys_on()', 'execute')
     or has_function_privilege('anon', 'public.tg_convoy_cargo_closes()', 'execute') or has_function_privilege('authenticated', 'public.tg_convoy_cargo_closes()', 'execute') then
    raise exception '0308 self-assert FAIL: a client can reach a new function';
  end if;
  if (select p.provolatile from pg_proc p where p.oid = 'public.fleet_kind(uuid)'::regprocedure) <> 's'
     or (select p.provolatile from pg_proc p where p.oid = 'public.convoys_on()'::regprocedure) <> 's' then
    raise exception '0308 self-assert FAIL: a read is not stable';
  end if;
  if (select count(*) from public.stats_flow_words w where w.kind in ('CONVOY_LOAD', 'CONVOY_DELIVER', 'CONVOY_RETURN') and w.side = 'moved') <> 3 then
    raise exception '0308 self-assert FAIL: a flow kind is not moved';
  end if;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and p.oid not in ('public.tg_convoy_cargo_closes()'::regprocedure, 'public.convoys_on()'::regprocedure, 'public.fleet_kind(uuid)'::regprocedure,
                           'public.cargo_ships_commission(uuid)'::regprocedure)) <> v_fn_before then
    raise exception '0308 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key))
        from public.world_config c where c.key not in ('convoys_enabled', 'convoy_ships_per_nation', 'convoy_ship_class')) <> v_cfg_before then
    raise exception '0308 self-assert FAIL: a world_config row moved';
  end if;
  if (select md5(string_agg(w.kind || ':' || w.side || ':' || w.word || ':' || w.ord, ',' order by w.kind))
        from public.stats_flow_words w where w.kind not like 'CONVOY%') <> v_word_before then
    raise exception '0308 self-assert FAIL: a word moved';
  end if;
  if (select md5(string_agg(t.tgrelid::regclass::text || ':' || t.tgname || ':' || t.tgenabled::text, ',' order by t.tgrelid::regclass::text, t.tgname))
        from pg_trigger t where not t.tgisinternal and t.tgrelid <> 'public.convoy_cargo'::regclass) <> v_trig_before then
    raise exception '0308 self-assert FAIL: a trigger moved on a table this file did not make';
  end if;

  -- ── 7. THE SELF-ASSERT: a probe nation, every row rolled back ──
  v_mark := coalesce((select max(f.id) from public.treasury_flows f), 0);
  begin
    update public.world_config set value = 'true'::jsonb
     where key in ('city_treasury_enabled', 'economy_closed', 'npc_traders_enabled', 'standing_routes_enabled') and value is distinct from 'true'::jsonb;
    insert into public.nations (code, name, flag_char, capital_port_code) values ('QX8', 'Probe 0308', 'Z', 'QZA') returning id into v_nat;
    insert into public.great_powers (nation_id) values (v_nat);
    insert into public.ports (code, name, country, lat, lon, sea_id, region_id, culture, size_tier, max_draft, kind)
    select x.code, 'Probe ' || x.code, t.country, t.lat, t.lon, t.sea_id, t.region_id, t.culture, t.size_tier, t.max_draft, 'HARBOUR'
      from (values ('QZA'), ('QZB')) x(code)
     cross join (select * from public.ports where kind = 'HARBOUR' order by code limit 1) t;
    v_cap  := (select p.id from public.ports p where p.code = 'QZA');
    v_city := (select p.id from public.ports p where p.code = 'QZB');
    insert into public.port_allegiance (port_id, nation_id) select p.id, v_nat from public.ports p where p.code like 'QZ_';
    insert into public.port_treasury (port_id, ducats, reserve, earned_day) values (v_cap, 100000, 0, world.game_day()), (v_city, 0, 0, world.game_day());
    v_sum := public.treasury_balance(v_cap) + public.treasury_balance(v_city);

    -- dark: nothing
    v_x := v_x || jsonb_build_object('dark_made', public.cargo_ships_commission(v_nat),
                                     'dark_rows', (select count(*) from public.cargo_ships c where c.nation_id = v_nat));

    -- lit: the knob's count, then none
    update public.world_config set value = 'true'::jsonb where key = 'convoys_enabled';
    v_class := public.wc_text('convoy_ship_class');
    v_x := v_x || jsonb_build_object('made', public.cargo_ships_commission(v_nat));
    v_x := v_x || jsonb_build_object('again', public.cargo_ships_commission(v_nat));
    v_fl  := (select c.fleet_id from public.cargo_ships c where c.nation_id = v_nat and c.ord = 1);
    v_fl2 := (select c.fleet_id from public.cargo_ships c where c.nation_id = v_nat and c.ord = 2);
    v_pl  := (select c.player_id from public.cargo_ships c where c.fleet_id = v_fl);
    v_pl2 := (select c.player_id from public.cargo_ships c where c.fleet_id = v_fl2);
    perform public.assert_ledger_reconciles(c.player_id) from public.cargo_ships c where c.nation_id = v_nat;

    v_x := v_x || jsonb_build_object(
      'kinds', (select count(*) from public.cargo_ships c where c.nation_id = v_nat and public.fleet_kind(c.fleet_id) = 'CARGO_SHIP'),
      'at_home', (select count(*) from public.cargo_ships c join public.fleets f on f.id = c.fleet_id
                   where c.nation_id = v_nat and c.home_port_id = v_cap and f.status = 'DOCKED' and f.port_id = v_cap and f.player_id = c.player_id),
      'bare_hulls', (select count(*) from public.cargo_ships c join public.ships s on s.fleet_id = c.fleet_id join public.ship_classes k on k.id = s.class_id
                      where c.nation_id = v_nat and s.is_flagship and s.crew = 0 and s.water_t = 0 and s.food_t = 0 and k.code = v_class),
      'hulls', (select count(*) from public.cargo_ships c join public.ships s on s.fleet_id = c.fleet_id where c.nation_id = v_nat),
      'houses_right', (select count(*) from public.cargo_ships c join public.players p on p.id = c.player_id
                        where c.nation_id = v_nat and p.is_npc and p.auth_uid is null and p.ducats = 0 and p.nation_id = v_nat),
      'ledger', (select count(*) from public.cargo_ships c join public.ledger l on l.player_id = c.player_id where c.nation_id = v_nat),
      'events', (select count(*) from public.cargo_ships c join public.events e on e.player_id = c.player_id where c.nation_id = v_nat),
      'routes', (select count(*) from public.cargo_ships c join public.standing_routes r on r.player_id = c.player_id where c.nation_id = v_nat),
      'flows_at_commission', (select count(*) from public.treasury_flows f where f.id > v_mark and f.created_at = now()),
      'in_merchant_tables', (select count(*) from public.cargo_ships c where c.nation_id = v_nat
                               and (exists (select 1 from public.npc_houses h where h.player_id = c.player_id)
                                    or exists (select 1 from public.npc_fleets n where n.fleet_id = c.fleet_id))),
      'in_tend', (select count(*) from public.npc_tend_roster() r where r.fleet_id = v_fl),
      'in_invest', (select count(*) from public.npc_invest_roster(v_pl)),
      'in_gifts', (select count(*) from public.capital_gift_roster(now(), v_pl)),
      'in_laps', (select count(*) from public.lap_starts_due() d where d.fleet_id = v_fl));

    -- a load serves two stops, one purse to another; the sum of the purses does not move
    perform public.treasury_post(v_cap, 'CONVOY_LOAD', -1000, null, null);
    insert into public.convoy_cargo (stage, fleet_id, player_id, port_id, ducats) values ('LOADED', v_fl, v_pl, v_cap, 1000) returning id into v_load;
    v_x := v_x || jsonb_build_object('sum_loaded', public.treasury_balance(v_cap) + public.treasury_balance(v_city) - v_sum);
    perform public.treasury_post(v_city, 'CONVOY_DELIVER', 400, null, null);
    insert into public.convoy_cargo (stage, fleet_id, player_id, port_id, ducats, load_id) values ('DELIVERED', v_fl, v_pl, v_city, 400, v_load);
    perform public.treasury_post(v_cap, 'CONVOY_RETURN', 600, null, null);
    insert into public.convoy_cargo (stage, fleet_id, player_id, port_id, ducats, load_id) values ('RETURNED', v_fl, v_pl, v_cap, 600, v_load);
    v_x := v_x || jsonb_build_object('purse_cap', public.treasury_balance(v_cap), 'purse_city', public.treasury_balance(v_city),
                                     'sum_moved', public.treasury_balance(v_cap) + public.treasury_balance(v_city) - v_sum,
                                     'flows', (select coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.id > v_mark and f.created_at = now() and f.kind like 'CONVOY%'));

    -- what the book refuses
    begin
      insert into public.convoy_cargo (stage, fleet_id, player_id, port_id, ducats, load_id) values ('DELIVERED', v_fl, v_pl, v_city, 1, v_load);
      v_x := v_x || '{"over":"passed"}';
    exception when check_violation then v_x := v_x || jsonb_build_object('over', sqlerrm); end;
    insert into public.convoy_cargo (stage, fleet_id, player_id, port_id, ducats) values ('LOADED', v_fl, v_pl, v_cap, 500) returning id into v_load;
    begin
      insert into public.convoy_cargo (stage, fleet_id, player_id, port_id, ducats, load_id) values ('DELIVERED', v_fl2, v_pl2, v_city, 1, v_load);
      v_x := v_x || '{"other":"passed"}';
    exception when check_violation then v_x := v_x || jsonb_build_object('other', sqlerrm); end;
    begin
      insert into public.convoy_cargo (stage, fleet_id, player_id, port_id, ducats, load_id) values ('RETURNED', v_fl, v_pl, v_city, 1, v_load);
      v_x := v_x || '{"away":"passed"}';
    exception when check_violation then v_x := v_x || jsonb_build_object('away', sqlerrm); end;
    begin
      insert into public.convoy_cargo (stage, fleet_id, player_id, port_id, ducats, load_id) values ('LOADED', v_fl, v_pl, v_cap, 1, v_load);
      v_x := v_x || '{"loaded_on":"passed"}';
    exception when check_violation then v_x := v_x || jsonb_build_object('loaded_on', sqlerrm); end;
    begin
      insert into public.convoy_cargo (stage, fleet_id, player_id, port_id, ducats) values ('DELIVERED', v_fl, v_pl, v_city, 1);
      v_x := v_x || '{"unloaded":"passed"}';
    exception when check_violation then v_x := v_x || jsonb_build_object('unloaded', sqlerrm); end;
    begin
      update public.convoy_cargo set ducats = 1 where id = v_load;
      v_x := v_x || '{"updated":"passed"}';
    exception when insufficient_privilege then v_x := v_x || jsonb_build_object('updated', sqlerrm); end;
    begin
      delete from public.convoy_cargo where id = v_load;
      v_x := v_x || '{"deleted":"passed"}';
    exception when insufficient_privilege then v_x := v_x || jsonb_build_object('deleted', sqlerrm); end;

    raise exception using errcode = 'ZX308', message = v_x::text;
  exception when sqlstate 'ZX308' then
    v_all := sqlerrm::jsonb;
  end;

  if (v_all ->> 'dark_made')::int <> 0 or (v_all ->> 'dark_rows')::int <> 0 then
    raise exception '0308 self-assert FAIL: dark, a cargo ship was made: %', v_all;
  end if;
  if (v_all ->> 'made')::int <> public.wc_int('convoy_ships_per_nation') or (v_all ->> 'again')::int <> 0 then
    raise exception '0308 self-assert FAIL: lit, the commission did not make the knob''s count once: %', v_all;
  end if;
  if (v_all ->> 'kinds')::int <> (v_all ->> 'made')::int then
    raise exception '0308 self-assert FAIL: a cargo ship does not read as her kind: %', v_all;
  end if;
  if (v_all ->> 'at_home')::int <> (v_all ->> 'made')::int then
    raise exception '0308 self-assert FAIL: a cargo ship is not docked at her capital: %', v_all;
  end if;
  if (v_all ->> 'bare_hulls')::int <> (v_all ->> 'made')::int or (v_all ->> 'hulls')::int <> (v_all ->> 'made')::int then
    raise exception '0308 self-assert FAIL: a cargo ship is not one empty hull of the knob''s class: %', v_all;
  end if;
  if (v_all ->> 'houses_right')::int <> (v_all ->> 'made')::int or (v_all ->> 'ledger')::int <> 0 or (v_all ->> 'flows_at_commission')::int <> 0 then
    raise exception '0308 self-assert FAIL: a cargo ship''s house is not a purse of 0 with no book: %', v_all;
  end if;
  if (v_all ->> 'events')::int <> 0 or (v_all ->> 'routes')::int <> 0 then
    raise exception '0308 self-assert FAIL: a commission left an event or a route: %', v_all;
  end if;
  if (v_all ->> 'in_merchant_tables')::int <> 0 or (v_all ->> 'in_tend')::int <> 0 or (v_all ->> 'in_invest')::int <> 0
     or (v_all ->> 'in_gifts')::int <> 0 or (v_all ->> 'in_laps')::int <> 0 then
    raise exception '0308 self-assert FAIL: a cargo ship entered merchant logic: %', v_all;
  end if;
  if (v_all ->> 'sum_loaded')::bigint <> -1000 or (v_all ->> 'sum_moved')::bigint <> 0 or (v_all ->> 'flows')::bigint <> 0
     or (v_all ->> 'purse_cap')::bigint <> 99600 or (v_all ->> 'purse_city')::bigint <> 400 then
    raise exception '0308 self-assert FAIL: the funds did not move purse to purse: %', v_all;
  end if;
  if v_all ->> 'over' not like '%E_CARGO_OVER%' then
    raise exception '0308 self-assert FAIL: the book let more out than was loaded: %', v_all;
  end if;
  if v_all ->> 'other' not like '%E_CARGO_LOAD%' or v_all ->> 'away' not like '%E_CARGO_LOAD%' then
    raise exception '0308 self-assert FAIL: a closing row was not true to its load: %', v_all;
  end if;
  if v_all ->> 'loaded_on' = 'passed' or v_all ->> 'unloaded' = 'passed' then
    raise exception '0308 self-assert FAIL: a row was neither a load nor a closing: %', v_all;
  end if;
  if v_all ->> 'updated' = 'passed' or v_all ->> 'deleted' = 'passed' then
    raise exception '0308 self-assert FAIL: the book is not append-only: %', v_all;
  end if;

  -- nothing of the probe survives; dark
  if exists (select 1 from public.ports p where p.code like 'QZ_') or exists (select 1 from public.nations n where n.code = 'QX8')
     or exists (select 1 from public.players p where p.company_name like 'Crown Cargo %')
     or exists (select 1 from public.cargo_ships) or exists (select 1 from public.convoy_cargo)
     or exists (select 1 from public.treasury_flows f where f.id > v_mark and f.created_at = now()) then
    raise exception '0308 self-assert FAIL: the probe left rows behind';
  end if;
  if public.convoys_on() then
    raise exception '0308 self-assert FAIL: the probe left the switch lit';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0308 self-assert FAIL: the self-assert took % (budget 45 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0308 self-assert ok: CARGO SHIPS EXIST, DARK. public.cargo_ships and public.convoy_cargo made and empty; three knobs, three moved flow kinds; no function, trigger, knob or word moved; no ship exists. Probe nation: dark made 0; lit made % ships, each one empty hull docked at her capital, purse 0, no ledger or event row, in no merchant table or roster; a second call made 0; a load closed by a delivery and a return, sum of purses moved 0; the book refused an over-closing, another ship''s closing, an update and a delete. The real voyage engine and the map: proof 18, in CI. Printed, never asserted: % ms.',
    v_all ->> 'made', round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
