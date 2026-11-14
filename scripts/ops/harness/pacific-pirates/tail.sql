-- LOCAL ONLY (tests/harness.guard.spec.ts): this file writes. It is a PART of the migration, not a prod check; gen-0414.mjs strips the guard line below, so the migration never carries it.
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;

  -- ── 3. THE HUBS, THE ROSTER, THE COLUMN, THE KNOBS ──
  create table public.pirate_hubs (
    port_id        uuid primary key references public.ports(id),
    ground         text not null,
    ground_name    text not null,
    ground_name_ko text not null,
    ships          integer not null check (ships >= 0),
    reach_nm       numeric not null check (reach_nm > 0)
  );
  comment on table public.pirate_hubs is '0414: one row a pirate hub: the ocean it is the haven of (`ground`; the Pacific has two), the SHIPS the owner ordered for it (the hulls of its rows in public.pirate_roster add up to it), and how far by a stored course its ships cruise for a haunt (public.pirate_haunt_of; a ship of a home that is no hub cruises navy_reach_nm). An ocean is where they mostly roam, not a fence. Server-only.';
  alter table public.pirate_hubs enable row level security;
  revoke all on table public.pirate_hubs from public, anon, authenticated;
  create table public.pirate_roster (
    ord           integer primary key check (ord > 1000),
    hub_port      uuid not null references public.pirate_hubs(port_id),
    house         integer not null check (house >= 1),
    house_name    text not null,
    house_name_ko text not null,
    fleet_name    text not null unique,
    fleet_name_ko text not null
  );
  comment on table public.pirate_roster is '0414: THE FLEETS THE PIRATES KEEP BEYOND public.pirate_size(), as data: one row a fleet. `ord` is her public.pirate_ships.ord (above 1000; 0339''s ships are 1 to pirate_size()); her home is `hub_port`; fleets of one (hub_port, house) sail for one house. Her hulls are public.pirate_roster_hulls. Built by public.pirate_commission_fleet, in public.pirate_next_ord''s order. Add, change or delete rows to tune the pirates: a deleted row''s fleet sails home and is laid up (public.pirate_ord_wanted). Server-only.';
  alter table public.pirate_roster enable row level security;
  revoke all on table public.pirate_roster from public, anon, authenticated;
  create table public.pirate_roster_hulls (
    ord   integer not null references public.pirate_roster(ord) on delete cascade,
    class text not null references public.ship_classes(code),
    n     integer not null check (n between 1 and 9),
    primary key (ord, class)
  );
  comment on table public.pirate_roster_hulls is '0414: the hulls of a roster fleet: n ships of a class (public.ship_classes.code). The dearest class is her lead ship. Read when she is built; a later change does not rebuild a fleet that sails. Server-only.';
  alter table public.pirate_roster_hulls enable row level security;
  revoke all on table public.pirate_roster_hulls from public, anon, authenticated;

  insert into public.pirate_hubs (port_id, ground, ground_name, ground_name_ko, ships, reach_nm)
  select p.id, v.ground, v.ground_name, v.ground_name_ko, v.ships, v.reach
    from (values
/*HUBROWS*/
    ) as v(code, ground, ground_name, ground_name_ko, ships, reach)
    join public.ports p on p.code = v.code;
  insert into public.pirate_roster (ord, hub_port, house, house_name, house_name_ko, fleet_name, fleet_name_ko)
  select v.ord, p.id, v.house, v.house_name, v.house_name_ko, v.fleet_name, v.fleet_name_ko
    from (values
/*ROSTER*/
    ) as v(ord, code, house, house_name, house_name_ko, fleet_name, fleet_name_ko)
    join public.ports p on p.code = v.code;
  insert into public.pirate_roster_hulls (ord, class, n) values
/*HULLS*/;
  -- a hub's quay holds the hands its own fleets need once (ports.crew_pool is seeded once, then the game's; 0338 seeded 160)
  update public.ports p
     set crew_pool = greatest(p.crew_pool, (select sum(x.n * c.crew_required) from public.pirate_roster r join public.pirate_roster_hulls x on x.ord = r.ord
                                              join public.ship_classes c on c.code = x.class where r.hub_port = p.id)::int)
   where p.id in (select port_id from public.pirate_hubs);

  alter table public.pirate_ships drop constraint pirate_ships_player_id_key;   -- 0414: a house may own several fleets (unique (fleet_id, player_id) stays)
  create index pirate_ships_player on public.pirate_ships (player_id);
  alter table public.pirate_ships add column wrecked_at timestamptz;
  comment on column public.pirate_ships.wrecked_at is '0414: when she was brought home a wreck (public.pirate_reborn, its one writer). She is mended pirate_respawn_minutes after it; null while she is whole.';

  insert into public.world_config (key, value, description) values
    ('pirate_respawn_minutes', to_jsonb(60), '0414: how long a pirate wreck lies at her home city before she is mended, manned, stored and sails again (public.pirate_reborn).'),
    ('pirate_add_minutes', to_jsonb(10), '0414: the pirates add at most one fleet in this many minutes (public.pirate_add). Before 0414 it was navy_build_hours (24 hours), which stays the navy''s.'),
    ('pirate_pressure_max', to_jsonb(1.0), '0414: the most the pirate fleets cruising one sea add to its pressure (public.pirate_pressure_write: least(this, pirate_pressure x fleets)). 1.0 is at most twice the sea''s authored danger. Before 0414 there was no cap (0.5 a ship; the most ever seen was one ship in a sea).');
  update public.world_config set value = to_jsonb(0.012), description = description || ' 0414: 0.005 -> 0.012 (the owner ordered 180 more ships; 121 fleets'' pay is 7.26 M a day of a 980 M hoard).'
   where key = 'pirate_spend_day_pct' and value = to_jsonb(0.005);

  -- ── 4. THE NEW FUNCTIONS ──
  execute $f$
create function public.pirate_ord_wanted(p_ord integer)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0414: THE one answer to "do the pirates keep a fleet of this ord": 0339's ships (1 to public.pirate_size()) and every row of public.pirate_roster. A fleet that is not wanted sails home and is laid up (public.pirate_ship_step).
  select coalesce(p_ord <= public.pirate_size(), false) or exists (select 1 from public.pirate_roster r where r.ord = p_ord)
$$
  $f$;

  execute $f$
create function public.pirate_next_ord()
returns integer
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- 0414: the next fleet the pirates add (public.pirate_add): the lowest of 0339's ords not at work, else the roster's, a hub at a time in turn (by the fleet's place in its hub, then the hub), so every ocean fills together.
  select o.ord
    from (select g.o as ord, 0 as turn from generate_series(1, public.pirate_size()) g(o)
          union all
          select r.ord, r.ord % 1000 from public.pirate_roster r) o
   where not exists (select 1 from public.pirate_ships_at_work n where n.ord = o.ord)
   order by o.turn, o.ord
   limit 1
$$
  $f$;

  execute $f$
create function public.pirate_refit_pay(p_fleet uuid, p_cost bigint, p_now timestamptz)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0414: WHO PAYS A PIRATE WRECK'S REFIT, in the owner's order (2026-11-14: "the pirate cities will fund those that have empty purse"): her own house's purse (SHIP); else her home city (HOME); else another city the pirates
-- hold, the richest first (CITY); else Port Royal's hoard through public.pirate_pay, inside the day's room (HOARD). Whole or nothing, to the yard public.refit_yard names for her home, kind REFIT, moved: never a debt,
-- never minted. A city pays only from its surplus (public.city_surplus) and only when its purse is free (public.treasury_try_lock). FREE: nothing to pay, no yard in reach, or the purses dark (0339's rule: patched free).
-- Null: nobody can pay now. Called by public.pirate_reborn alone.
declare
  n      public.pirate_ships%rowtype;
  v_yard uuid;
  v_cap  uuid := public.pirate_capital();
  v_have bigint;
  c      record;
begin
  select * into n from public.pirate_ships x where x.fleet_id = p_fleet;
  v_yard := public.refit_yard(n.home_port);
  if coalesce(p_cost, 0) <= 0 or v_yard is null or not public.city_treasury_on() then
    return 'FREE';
  end if;
  select pl.ducats into v_have from public.players pl where pl.id = n.player_id for update;
  if coalesce(v_have, 0) >= p_cost then
    perform public.pay_city(n.player_id, v_yard, 'REFIT', p_cost, null);
    return 'SHIP';
  end if;
  if n.home_port is not distinct from v_cap and public.pirate_pay('REFIT', p_cost, p_now, v_yard, null) > 0 then
    return 'HOME';   -- her home is the capital: Port Royal pays first, as any home does
  end if;
  for c in select a.port_id from public.port_allegiance a
            where a.nation_id = public.pirate_nation() and a.port_id is distinct from v_cap and a.port_id <> v_yard
            order by (a.port_id = n.home_port) desc, public.city_surplus(a.port_id) desc, a.port_id loop
    continue when public.city_surplus(c.port_id) < p_cost;
    continue when not public.treasury_try_lock(c.port_id);
    continue when public.city_surplus(c.port_id) < p_cost;
    perform public.treasury_post(c.port_id, 'REFIT', -p_cost, null, null);
    perform public.treasury_post(v_yard, 'REFIT', p_cost, null, null);
    insert into public.pirate_spend_day (day, spent) values ((p_now at time zone 'UTC')::date, p_cost)
    on conflict (day) do update set spent = public.pirate_spend_day.spent + excluded.spent;
    return case when c.port_id = n.home_port then 'HOME' else 'CITY' end;
  end loop;
  if n.home_port is distinct from v_cap and public.pirate_pay('REFIT', p_cost, p_now, v_yard, null) > 0 then
    return 'HOARD';
  end if;
  return null;
end
$$
  $f$;

  execute $f$
create function public.pirate_reborn(p_fleet uuid, p_now timestamptz)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0414: THE HOME RULE OF A PIRATE WRECK, every pirate ship's, old and new (the owner, 2026-11-14: "each pirate ship should have a home city ... and will be restock, rebased, fixed when they lose and their ships destroyed").
-- Called by public.pirate_ship_step for a fleet whose every hull is at 0; the caller holds her fleet row. She is at her home city at once (voyage.npc_wreck, 0322's respawn: the hold lost, UNABLE_TO_SAIL), lies
-- pirate_respawn_minutes from `wrecked_at`, then is paid for (public.pirate_refit_pay), mended (public.fleet_mend), manned from her home's quay (public.fleet_hands) and stored (public.fleet_stores, navy_store_days),
-- and may sail. Answers WRECK (she lies), WAITING (no pirate purse can pay now: a row in public.npc_refit_waits and one REFIT_WAITING a day; she is asked again at every step) or REBORN.
declare
  n       public.pirate_ships%rowtype;
  f       public.fleets%rowtype;
  v_cost  bigint;
  v_payer text;
begin
  select * into n from public.pirate_ships x where x.fleet_id = p_fleet;
  if n.fleet_id is null then
    raise exception 'E_NOT_A_PIRATE_SHIP: fleet %', p_fleet using errcode = 'P0001';
  end if;
  select * into f from public.fleets x where x.id = p_fleet;
  if f.status <> 'UNABLE_TO_SAIL' or f.port_id is distinct from n.home_port then
    perform voyage.npc_wreck(p_fleet);   -- a wreck no settled day brought home (the navy took her in port or at sea)
  end if;
  if n.wrecked_at is null then
    update public.pirate_ships x set wrecked_at = p_now, sea_id = null, haunt_port = null, haunt_since = null, mission = 'HOME' where x.fleet_id = p_fleet;
    return 'WRECK';
  end if;
  if p_now < n.wrecked_at + make_interval(mins => public.wc_int('pirate_respawn_minutes')) then
    return 'WRECK';
  end if;
  v_cost := public.npc_refit_cost(p_fleet);
  v_payer := public.pirate_refit_pay(p_fleet, v_cost, p_now);
  if v_payer is null then
    insert into public.npc_refit_waits as w (fleet_id, told_at) values (p_fleet, p_now)
    on conflict (fleet_id) do update set told_at = excluded.told_at where w.told_at <= p_now - interval '1 day';
    if found then
      perform public.emit_event(f.player_id, 'REFIT_WAITING', jsonb_build_object(
        'fleet', f.name, 'port', (select p.code from public.ports p where p.id = n.home_port), 'cost', v_cost, 'why', 'broke'));
    end if;
    return 'WAITING';
  end if;
  perform public.fleet_mend(p_fleet);
  perform public.fleet_hands(p_fleet, n.home_port);
  perform public.fleet_stores(p_fleet, public.wc_num('navy_store_days'));
  update public.fleets set status = 'DOCKED', ready_at = p_now, version = version + 1 where id = p_fleet;
  update public.pirate_ships x set wrecked_at = null where x.fleet_id = p_fleet;
  delete from public.npc_refit_waits w where w.fleet_id = p_fleet;
  perform public.emit_event(f.player_id, 'REFITTED', jsonb_build_object(
    'fleet', f.name, 'port', (select p.code from public.ports p where p.id = n.home_port),
    'yard', (select p.code from public.ports p where p.id = public.refit_yard(n.home_port)), 'cost', case when v_payer = 'FREE' then 0 else v_cost end, 'payer', v_payer));
  return 'REBORN';
end
$$
  $f$;

  execute $f$
create function public.pirate_commission_fleet(p_ord integer, p_yard uuid, p_now timestamptz)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- 0414: THE one place a ROSTER fleet is made (public.pirate_roster; 0339's lone xebecs stay public.pirate_commission's): the hoard pays the yard every hull's build cost in one payment (public.pirate_pay BUILD_NAVY,
-- whole or nothing: answers null and makes nothing when it cannot), and she is laid at her hub by the hands every fleet is made by (public.form_fleet, public.commission_ship), crewless: her first departure brings hands
-- and stores. Her house is her roster house's (made with the first of its fleets, purse 0, no ledger row); her lead ship is the dearest class. Answers her fleet, or null.
declare
  r        public.pirate_roster%rowtype;
  x        record;
  v_cost   bigint;
  v_player uuid;
  v_fleet  uuid;
  v_k      int := 0;
begin
  select * into r from public.pirate_roster q where q.ord = p_ord;
  if r.ord is null or exists (select 1 from public.pirate_ships n where n.ord = p_ord) then
    return null;
  end if;
  select sum(h.n * c.build_cost)::bigint into v_cost from public.pirate_roster_hulls h join public.ship_classes c on c.code = h.class where h.ord = p_ord;
  if coalesce(v_cost, 0) <= 0 or public.pirate_pay('BUILD_NAVY', v_cost, p_now, p_yard, null) <= 0 then
    return null;
  end if;
  select n.player_id into v_player
    from public.pirate_ships n join public.pirate_roster q on q.ord = n.ord
   where q.hub_port = r.hub_port and q.house = r.house limit 1;
  if v_player is null then
    insert into public.players (company_name, nation_id, ducats, is_npc)
    values (r.house_name, public.pirate_nation(), 0, true)
    returning id into v_player;
  end if;
  v_fleet := public.form_fleet(v_player, r.fleet_name, r.hub_port);
  for x in select h.class, g.i from public.pirate_roster_hulls h join public.ship_classes c on c.code = h.class cross join lateral generate_series(1, h.n) g(i)
            where h.ord = p_ord order by c.build_cost desc, h.class, g.i loop
    v_k := v_k + 1;
    perform public.commission_ship(v_player, v_fleet, x.class, case when v_k = 1 then r.fleet_name else format('%s %s', r.fleet_name, v_k) end, v_k = 1, false);
  end loop;
  insert into public.pirate_ships (fleet_id, player_id, ord, home_port, last_port, created_at)
  values (v_fleet, v_player, p_ord, r.hub_port, r.hub_port, p_now);
  return v_fleet;
end
$$
  $f$;

  revoke all on function public.pirate_ord_wanted(integer) from public, anon, authenticated;
  revoke all on function public.pirate_next_ord() from public, anon, authenticated;
  revoke all on function public.pirate_refit_pay(uuid, bigint, timestamptz) from public, anon, authenticated;
  revoke all on function public.pirate_reborn(uuid, timestamptz) from public, anon, authenticated;
  revoke all on function public.pirate_commission_fleet(integer, uuid, timestamptz) from public, anon, authenticated;

  -- ── 5. THE HUNKS ──
  create temp table hunk_0414 (ord int primary key, fn text, old text, new text) on commit drop;
  insert into hunk_0414 values
  (1, 'public.pirate_ship_step(uuid,timestamp with time zone)',
$h$  if public.npc_wrecked(p_fleet) then
    return 'WRECK';
  end if;
$h$,
$h$  if public.npc_wrecked(p_fleet) then
    return public.pirate_reborn(p_fleet, p_now);   -- 0414: THE HOME RULE: she is at her home city, lies pirate_respawn_minutes, and is mended, manned and stored; her own purse, her home, another pirate city or the hoard pays (WRECK, WAITING or REBORN)
  end if;
$h$),
  (2, 'public.pirate_ship_step(uuid,timestamp with time zone)',
$h$and n.ord <= public.pirate_size();$h$,
$h$and public.pirate_ord_wanted(n.ord);   -- 0414: 0339's ships and the roster's fleets (was n.ord <= public.pirate_size())$h$),
  (3, 'public.pirate_add(timestamp with time zone)',
$h$> p_now - make_interval(hours => public.wc_int('navy_build_hours')) then$h$,
$h$> p_now - make_interval(mins => public.wc_int('pirate_add_minutes')) then   -- 0414: the pirates' own pace (was navy_build_hours)$h$),
  (4, 'public.pirate_add(timestamp with time zone)',
$h$  select min(o) into v_ord from generate_series(1, v_size) o
   where not exists (select 1 from public.pirate_ships_at_work n where n.ord = o);
$h$,
$h$  v_ord := public.pirate_next_ord();   -- 0414: 0339's ships first, then the roster's fleets, a hub at a time in turn
$h$),
  (5, 'public.pirate_add(timestamp with time zone)',
$h$    v_home := public.pirate_home_of(v_ord);
    v_yard := public.refit_yard(v_home);
    if v_home is null or v_yard is null or public.pirate_commission(v_ord, v_home, v_yard, p_now) is null then
$h$,
$h$    v_home := coalesce((select r.hub_port from public.pirate_roster r where r.ord = v_ord), public.pirate_home_of(v_ord));   -- 0414: a roster fleet's home is her hub
    v_yard := public.refit_yard(v_home);
    if v_home is null or v_yard is null
       or (case when exists (select 1 from public.pirate_roster r where r.ord = v_ord) then public.pirate_commission_fleet(v_ord, v_yard, p_now)   -- 0414: her hulls by the roster
                else public.pirate_commission(v_ord, v_home, v_yard, p_now) end) is null then
$h$),
  (6, 'public.pirate_haunt_of(uuid,integer)',
$h$and c.nm <= public.wc_num('navy_reach_nm')$h$,
$h$and c.nm <= coalesce((select hb.reach_nm from public.pirate_hubs hb where hb.port_id = p_home), public.wc_num('navy_reach_nm'))   -- 0414: a hub's own reach (the mid-ocean islands lie farther out)$h$),
  (7, 'public.pirate_pressure_write(timestamp with time zone)',
$h$select x.sea_id, public.wc_num('pirate_pressure') * count(*), p_now from$h$,
$h$select x.sea_id, least(public.wc_num('pirate_pressure_max'), public.wc_num('pirate_pressure') * count(*)), p_now from   /* 0414: capped: a sea's pirates at most double its authored danger */$h$),
  (8, 'public.npc_refit_step(uuid,timestamp with time zone)',
$h$or not public.npc_wrecked(p_fleet) then$h$,
$h$or not public.npc_wrecked(p_fleet)
     or exists (select 1 from public.pirate_ships x where x.fleet_id = p_fleet) then   -- 0414: a pirate wreck is her own step's (public.pirate_reborn): never paid for twice$h$),
  (9, 'world.pirate_ship_card(uuid)',
$h$    'home', (select p.code from public.ports p where p.id = n.home_port),$h$,
$h$    'home', (select p.code from public.ports p where p.id = n.home_port),
    'name_ko', (select r.fleet_name_ko from public.pirate_roster r where r.ord = n.ord),   -- 0414: a roster fleet's names in Korean, and her house's (null for 0339's ships)
    'house', (select r.house_name from public.pirate_roster r where r.ord = n.ord),
    'house_ko', (select r.house_name_ko from public.pirate_roster r where r.ord = n.ord),$h$);
  for hk in select * from hunk_0414 order by ord loop
    v_def := replace(pg_get_functiondef(hk.fn::regprocedure), E'\r', '');
    v_n := (length(v_def) - length(replace(v_def, hk.old, ''))) / length(hk.old);
    if v_n <> 1 then
      raise exception '0414 self-assert FAIL: hunk % of % occurs % time(s), not once: the deployed body is not what this file was written against', hk.ord, hk.fn, v_n;
    end if;
    execute replace(v_def, hk.old, hk.new);
    v_def := replace(pg_get_functiondef(hk.fn::regprocedure), E'\r', '');
    if (length(v_def) - length(replace(v_def, hk.new, ''))) / length(hk.new) <> 1 then
      raise exception '0414 self-assert FAIL: hunk % of % is not in the new body once', hk.ord, hk.fn;
    end if;
    if (select coalesce(p.proacl::text, '') || ':' || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') || ':' || p.proowner::text
          from pg_proc p where p.oid = hk.fn::regprocedure) <> (select p.meta from pre_0414 p where p.fn = hk.fn) then
      raise exception '0414 self-assert FAIL: the grants, volatility, definer, search path or owner of % moved', hk.fn;
    end if;
  end loop;
  for hk in select p.fn, p.def from pre_0414 p loop
    v_def := replace(pg_get_functiondef(hk.fn::regprocedure), E'\r', '');
    for v_z in select x.old, x.new from hunk_0414 x where x.fn = hk.fn order by x.ord desc loop
      v_def := replace(v_def, v_z.new, v_z.old);
    end loop;
    if v_def <> hk.def then
      raise exception '0414 self-assert FAIL: % does not reverse to its pre-image', hk.fn;
    end if;
  end loop;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')) || ':' || coalesce(p.proacl::text, ''), ',' order by p.oid::regprocedure::text))
        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
         and not exists (select 1 from unnest(c_cut || c_new) f where f::regprocedure = p.oid)) <> v_fn_before then
    raise exception '0414 self-assert FAIL: another function moved';
  end if;

  -- ── 6. THE NEWS (0347's law) ──
  perform public.news_update('0414', 'Pirate havens in every ocean', '대양마다 해적 소굴');

  -- ── 7. THE SELF-ASSERT: this file's own rows, then a probe that rolls back ──
  if (select count(*) from public.pirate_hubs) <> 5 or (select count(*) from public.pirate_roster) <> /*NFLEETS*/
     or (select sum(x.n) from public.pirate_roster_hulls x) <> /*NSHIPS*/
     or exists (select 1 from public.pirate_hubs hb
                 where hb.ships <> (select coalesce(sum(x.n), 0) from public.pirate_roster r join public.pirate_roster_hulls x on x.ord = r.ord where r.hub_port = hb.port_id))
     or (select jsonb_object_agg(g.ground, g.s) from (select hb.ground, sum(hb.ships) as s from public.pirate_hubs hb group by 1) g)
        <> '{"PACIFIC": 70, "SOUTH_ATLANTIC": 40, "NORTH_ATLANTIC": 40, "INDIAN": 30}'::jsonb
     or exists (select 1 from public.pirate_roster r where not exists (select 1 from public.pirate_roster_hulls x where x.ord = r.ord)) then
    raise exception '0414 self-assert FAIL: the hubs and the roster are not the owner''s order (Pacific 70, South Atlantic 40, North Atlantic 40, Indian 30; % fleets)', /*NFLEETS*/;
  end if;
  if exists (select 1 from public.pirate_hubs hb where not exists (select 1 from public.pirate_haunt_of(hb.port_id, 1001)))
     or exists (select 1 from public.pirate_hubs hb join public.port_allegiance a on a.port_id = hb.port_id where a.nation_id is distinct from v_pir or a.home)
     or exists (select 1 from public.pirate_hubs hb where public.refit_yard(hb.port_id) is null) then
    raise exception '0414 self-assert FAIL: a hub has no haunt in its reach, no yard in reach, or is not held (and not a home) by the pirates';
  end if;
  if not public.pirate_ord_wanted(1) or not public.pirate_ord_wanted(1001) or public.pirate_ord_wanted(999) or public.pirate_ord_wanted(1000)
     or public.wc_num('pirate_pressure_max') <> 1.0 or public.wc_int('pirate_respawn_minutes') <> 60 or public.wc_int('pirate_add_minutes') <> 10
     or public.wc_num('pirate_spend_day_pct') <> 0.012 then
    raise exception '0414 self-assert FAIL: the wanted ords or the knobs are not this file''s';
  end if;

  -- THE PROBE, rolled back by a raised sentinel: the pirates lit and the capital able to pay INSIDE THE PROBE ONLY. A roster squadron is built (one house, four hulls), wrecked, and must be REBORN whole at her hub an
  -- hour on with the hub's purse at 0 (another purse pays); then with no pirate purse able to pay she must WAIT with a row in public.npc_refit_waits, never silently; a second fleet of her house joins the same house.
  begin
    update public.world_config set value = 'true'::jsonb where key in ('pirates_bite', 'city_treasury_enabled') and value is distinct from 'true'::jsonb;
    if public.pirates_on() then
      update public.port_treasury t set ducats = greatest(t.ducats, 500000000) where t.port_id = public.pirate_capital();
      delete from public.pirate_spend_day d where d.day = (v_now at time zone 'UTC')::date;
      select r.ord into v_n from public.pirate_roster r join public.pirate_roster_hulls x on x.ord = r.ord group by r.ord having sum(x.n) = 4 order by r.ord limit 1;
      v_fleet := public.pirate_commission_fleet(v_n, public.refit_yard((select r.hub_port from public.pirate_roster r where r.ord = v_n)), v_now);
      if v_fleet is null or (select count(*) from public.ships s where s.fleet_id = v_fleet) <> 4
         or (select count(*) from public.ships s where s.fleet_id = v_fleet and s.is_flagship) <> 1
         or public.fleet_kind(v_fleet) <> 'PIRATE' or public.fleet_origin(v_fleet) is distinct from (select r.hub_port from public.pirate_roster r where r.ord = v_n) then
        raise exception '0414 self-assert FAIL (probe): roster fleet % was not built as four hulls of one pirate fleet at her hub', v_n;
      end if;
      if public.pirate_commission_fleet(v_n - 1, public.refit_yard((select r.hub_port from public.pirate_roster r where r.ord = v_n)), v_now) is null
         or (select count(distinct n.player_id) from public.pirate_ships n where n.ord in (v_n - 1, v_n)) <> 1 then
        raise exception '0414 self-assert FAIL (probe): the second fleet of her house did not join the same house';
      end if;
      update public.ships s set durability = 0 where s.fleet_id = v_fleet;
      update public.fleets set status = 'UNABLE_TO_SAIL' where id = v_fleet;
      v_s := public.pirate_reborn(v_fleet, v_now);
      if v_s <> 'WRECK' or (select n.wrecked_at from public.pirate_ships n where n.fleet_id = v_fleet) is distinct from v_now then
        raise exception '0414 self-assert FAIL (probe): a fresh wreck answered %, not WRECK with her hour stamped', v_s;
      end if;
      if public.pirate_reborn(v_fleet, v_now + interval '59 minutes') <> 'WRECK' then
        raise exception '0414 self-assert FAIL (probe): she was mended before pirate_respawn_minutes';
      end if;
      v_s := public.pirate_reborn(v_fleet, v_now + interval '61 minutes');
      if v_s <> 'REBORN' or exists (select 1 from public.ships s where s.fleet_id = v_fleet and s.durability <= 0)
         or (select f.status from public.fleets f where f.id = v_fleet) <> 'DOCKED' or (select n.wrecked_at from public.pirate_ships n where n.fleet_id = v_fleet) is not null then
        raise exception '0414 self-assert FAIL (probe): with her hub''s purse at 0 she answered %, not REBORN whole and docked (another pirate purse must pay)', v_s;
      end if;
      update public.ships s set durability = 0 where s.fleet_id = v_fleet;
      update public.fleets set status = 'UNABLE_TO_SAIL' where id = v_fleet;
      update public.port_treasury t set ducats = 0 where t.port_id in (select a.port_id from public.port_allegiance a where a.nation_id = v_pir);
      perform public.pirate_reborn(v_fleet, v_now + interval '2 hours');
      v_s := public.pirate_reborn(v_fleet, v_now + interval '4 hours');
      if v_s <> 'WAITING' or not exists (select 1 from public.npc_refit_waits w where w.fleet_id = v_fleet)
         or exists (select 1 from public.ships s where s.fleet_id = v_fleet and s.durability > 0) then
        raise exception '0414 self-assert FAIL (probe): with every pirate purse at 0 she answered %, not WAITING with her row in public.npc_refit_waits and no hull restored unpaid', v_s;
      end if;
      if public.npc_refit_step(v_fleet, v_now + interval '4 hours') <> 'NOT_A_WRECK' then
        raise exception '0414 self-assert FAIL (probe): public.npc_refit_step still judges a pirate wreck';
      end if;
      v_note := format('the probe built roster squadron %s (four hulls) and her house''s second fleet, wrecked her, and she was REBORN at her hub an hour on with the hub''s purse at 0; with every pirate purse at 0 she WAITS in public.npc_refit_waits', v_n);
    end if;
    raise exception using errcode = 'ZP409', message = v_note;
  exception when sqlstate 'ZP409' then
    v_note := sqlerrm;
  end;
  if exists (select 1 from public.pirate_ships n where n.ord > 1000) then
    raise exception '0414 self-assert FAIL: the probe''s fleet was not rolled back';
  end if;

  if clock_timestamp() - v_t0 > interval '60 seconds' then
    raise exception '0414 self-assert FAIL: the file took % (budget 60 s)', clock_timestamp() - v_t0;
  end if;
  raise notice '0414 self-assert ok: PIRATES HAVE HOMES AND GROUNDS. Five harbours held by the pirates (PTC MWY TDC FLO DGA), purse 0, no money moved: %; five hubs and a roster of /*NFLEETS*/ fleets, /*NSHIPS*/ ships (Pacific 70, South Atlantic 40, North Atlantic 40, Indian 30); nine hunks over six bodies, each once and reversing; grants and volatility unmoved; no other function moved; %. % ms.',
    v_recv, v_note, round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$m$;
