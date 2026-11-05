-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0310 — CARGO SHIPS YOU CAN SEE: the map's reads serve her with her kind, her card, funds on the way in the hall, funds at sea in Stats, dark
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Owner, 2026-11-05: V4 of docs/CITY_CONVOYS.md, "cargo ship? with different graphics. npc like merchants but different." The server half; the hull is src/chart/glyphs.ts.
--
-- DARK: no ship exists, so every read this file touches answers its pre-image to the byte, self-asserted. convoys_enabled stays false and no ship is made by this file on any world.
--
-- WHAT V2 LEFT OPEN (docs/dev-log/2026-11-05-cargo-funds.md, 0308's items 3 and 4):
--   THE MAP. world.sea_traffic's `total` counted her and its rows did not. And the client has not read world.sea_traffic since 0118: it reads world.sea_roster, which never served her
--     either. Both reads now serve her row, so `total` and `omitted` are honest with no change to the count: she is a row of the same total. A row carries `kind` on a cargo ship ALONE,
--     so a merchant's row is what it always was.
--   THE COUNT. public.stats_live_track and public.stats_live_fold counted her in at_sea_merchants. She is not a merchant; both now leave her out, and she stays in at_sea: she is at sea.
--
-- ONE AUTHORITY: public.sea_houses is the one answer to "whose ships does the sea show, in what ink, of what kind": the merchants' houses, then the cargo ships'. Both reads join it
--   in the place of public.npc_houses, under the same alias. Her ink is her nation's merchants' ink (each great power has exactly one on prod); a nation with no merchant takes 'east'.
-- A SHIP'S ROSTER DELTA: a cargo ship has no standing route, whose updated_at tells the merchants' delta they docked. So a delta also carries a cargo ship whose last voyage has reached its
--   eta since p_since, or a ship idle at home would stay drawn as sailing until the next full read.
-- world.sea_traffic IS STILL CAPPED: sea_traffic_max can leave her out of its rows, and `omitted` says so. No client reads it; world.sea_roster has no cap.
--
-- NEW READS: world.cargo_ship_card(fleet), a tap read, as world.npc_fleet_card; refuses in the same words for anything else. public.funds_on_way, one term of world.town_hall, keyed `funds_on_way`,
--   served only when a ship carrying funds is bound for this city and it is short. public.cargo_figures, one term of world.stats_now, keys `cargo_ships` and `funds_at_sea`, served only while a ship exists.
--   So the hall and Stats need no new read, and dark neither answer has a new key.
--
-- SELF-ASSERT: dark, each read equals its pre-image on the real world (world.sea_traffic through one 12 by 8 window: its whole-world read costs seconds on prod). Lit, one probe nation of three
--   rolled-back harbours: her row, her kind, her card, funds on the way, the figures, her journal row. Every hunk reverses; nothing else moved. THE REAL FOLD AND A REAL ARRIVAL ARE PROVED IN CI:
--   proof 20, scripts/db/proofs/20_cargo_seen.sql. Mutation controls: scripts/ops/harness/cargo-ships/proof-0310.mjs (local).
--
-- BUDGET (docs/OPS_HEALTH.md section 4): ONE DO block, statement_timeout 45 s, lock_timeout 5 s first. Work: four functions, eleven hunks, catalog reads, about ten reads of the roster and one window. Self-assert fails above 45 s.
-- ROLLBACK (forward, a NEW migration, owner only): nothing is lit, so none is needed.
-- VERSION: 0310 - follows 0309 (#489), which must be deployed first.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $m$
declare
  v_fn    text[];
  v_old   text[];
  v_new   text[];
  v_oids  oid[];
  v_def0  jsonb := '{}'::jsonb;
  v_acl0  jsonb := '{}'::jsonb;
  v_cur   jsonb := '{}'::jsonb;
  v_def   text;
  v_i     int;
  v_n     int;
  v_fn_before   text;
  v_cfg_before  text;
  v_word_before text;
  v_trig_before text;
  v_t0    timestamptz := clock_timestamp();
  v_nat   uuid;
  v_cap   uuid;
  v_fl    uuid;
  v_s1    uuid;
  v_s2    uuid;
  v_port  uuid;
  v_day   timestamptz;
  v_view  jsonb := '{"south": 34, "north": 42, "west": -14, "east": -2}'::jsonb;
  v_near  jsonb := '{"south": 26, "north": 34, "west": -46, "east": -34}'::jsonb;
  v_a     jsonb;
  v_x     jsonb := '{}'::jsonb;
  v_ok    boolean;
begin
  perform set_config('statement_timeout', '45s', true);
  perform set_config('lock_timeout', '5s', true);

  -- ── 0. GUARD ──
  if to_regprocedure('public.funds_aboard()') is null or to_regclass('public.cargo_circuit_legs') is null then
    raise exception '0310 refuses: 0309 (the circuit, the funds) is not in this world';
  end if;
  if to_regprocedure('public.sea_houses()') is not null or to_regprocedure('world.cargo_ship_card(uuid)') is not null then
    raise exception '0310 refuses: it has been applied once';
  end if;
  if public.convoys_on() or exists (select 1 from public.cargo_ships) then
    raise exception '0310 refuses: it is cut for a dark world with no ship';
  end if;

  v_fn := array[
    'world.sea_traffic(jsonb)', 'world.sea_traffic(jsonb)', 'world.sea_traffic(jsonb)',
    'world.sea_roster(timestamp with time zone)', 'world.sea_roster(timestamp with time zone)', 'world.sea_roster(timestamp with time zone)',
    'public.stats_live_track()', 'public.stats_live_fold(timestamp with time zone,boolean)',
    'world.town_hall(uuid)', 'world.stats_now()', 'public.client_rpc_entry_points()'];

  select array_agg(p.oid) into v_oids
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid not in (select f::regprocedure::oid from unnest(v_fn) f);
  select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
    into v_fn_before from pg_proc p where p.oid = any (v_oids);
  select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) into v_cfg_before from public.world_config c;
  select md5(string_agg(w.kind || ':' || w.side || ':' || w.word || ':' || w.ord, ',' order by w.kind)) into v_word_before from public.stats_flow_words w;
  select md5(string_agg(t.tgrelid::regclass::text || ':' || t.tgname || ':' || t.tgenabled::text, ',' order by t.tgrelid::regclass::text, t.tgname)) into v_trig_before
    from pg_trigger t where not t.tgisinternal;
  for v_i in 1 .. array_length(v_fn, 1) loop
    v_def0 := v_def0 || jsonb_build_object(v_fn[v_i], replace(pg_get_functiondef(v_fn[v_i]::regprocedure), E'\r', ''));
    v_acl0 := v_acl0 || jsonb_build_object(v_fn[v_i], (select coalesce(p.proacl::text, '') || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '')
                                                         from pg_proc p where p.oid = v_fn[v_i]::regprocedure));
  end loop;
  v_cur := v_def0;

  -- ── 1. THE NEW READS ──
  execute $f$
create function public.sea_houses()
returns table(player_id uuid, ink text, kind text)
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0310: THE answer to whose ships the sea shows, in what ink, of what kind: every merchant house, kind null, and every cargo ship's house, kind CARGO_SHIP. A cargo ship wears her nation's
  -- merchants' ink. Her `kind` is the same word as public.fleet_kind. No ship: the merchants' houses and nothing else.
  select h.player_id, h.ink::text, null::text from public.npc_houses h
  union all
  select c.player_id,
         coalesce((select m.ink::text from public.npc_houses m join public.players o on o.id = m.player_id
                    where o.nation_id = c.nation_id group by m.ink order by count(*) desc, m.ink limit 1), 'east'),
         'CARGO_SHIP'
    from public.cargo_ships c
$body$
  $f$;
  revoke all on function public.sea_houses() from public, anon, authenticated;

  execute $f$
create function public.funds_on_way(p_port uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0310: one term of world.town_hall. What the nearest ship of this city's realm that carries funds would pay it: what she has, up to what the city lacks (the same top-up as public.cargo_ship_step).
  -- `stops` is how many stops she makes first; `eta` only while this is the very next one. A city not short, a capital, the switch off (she pays nobody), or no ship: {}. Bounded by a realm's ships.
  select coalesce((
    select jsonb_build_object('funds_on_way', jsonb_build_object('ducats', x.give, 'stops', x.stops, 'eta', x.eta))
      from (select least(a.aboard, public.city_aid_target(p_port) - public.treasury_balance(p_port)) as give,
                   l.ord - c.leg - (case when w.status = 'SAILING' then 0 else 1 end) as stops,
                   case when l.ord = c.leg then w.eta end as eta
              from public.cargo_ships c
              join public.cargo_circuit_legs l on l.circuit_id = c.circuit_id and l.to_port = p_port
              cross join lateral public.cargo_ship_aboard(c.fleet_id) a
              cross join lateral voyage.where_now(c.fleet_id) w
             where public.convoys_on()
               and c.home_port_id = public.city_capital(p_port) and c.home_port_id <> p_port
               and (l.ord > c.leg or (l.ord = c.leg and w.status = 'SAILING'))) x
     where x.give > 0
     order by x.stops, x.eta nulls last
     limit 1), '{}'::jsonb)
$body$
  $f$;
  revoke all on function public.funds_on_way(uuid) from public, anon, authenticated;

  execute $f$
create function public.cargo_figures()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $body$
  -- 0310: one term of world.stats_now: how many cargo ships exist and the funds aboard them. No ship: {}, so the read is what it was. funds_at_sea is already inside set_aside (0309): a part of it, not a new sum.
  select case when exists (select 1 from public.cargo_ships)
              then jsonb_build_object('cargo_ships', (select count(*) from public.cargo_ships), 'funds_at_sea', public.funds_aboard())
              else '{}'::jsonb end
$body$
  $f$;
  revoke all on function public.cargo_figures() from public, anon, authenticated;

  execute $f$
create function world.cargo_ship_card(p_fleet uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $body$
-- 0310: EVERYTHING A PLAYER MAY KNOW ABOUT ONE CARGO SHIP, read at a tap. Refuses E_NOT_FOUND for any fleet that is not one, in the same words as for a uuid that names nothing.
-- `to` and `eta` are her voyage's, while she sails. `funds` is what she carries now, `next` the stops after this one, five at most, in sailing order; `stops_left` how many there are. No id of a voyage or a load.
declare
  c public.cargo_ships%rowtype;
  f public.fleets%rowtype;
  w record;
begin
  select x.* into c from public.cargo_ships x where x.fleet_id = p_fleet;
  if c.fleet_id is null then
    raise exception 'E_NOT_FOUND: there is no such cargo ship' using errcode = 'P0001';
  end if;
  select x.* into f from public.fleets x where x.id = p_fleet;
  select * into w from voyage.where_now(p_fleet);
  return jsonb_build_object(
    'fleet', jsonb_build_object('id', f.id, 'name', f.name, 'status', w.status, 'port', (select p.code from public.ports p where p.id = w.port_id)),
    'nation_code', (select n.code from public.nations n where n.id = c.nation_id),
    'home', (select p.code from public.ports p where p.id = c.home_port_id),
    'funds', coalesce((select a.aboard from public.cargo_ship_aboard(p_fleet) a), 0),
    'to', (select p.code from public.voyages v join public.ports p on p.id = v.dest_port_id where v.id = w.voyage_id),
    'eta', w.eta,
    'next', (select coalesce(jsonb_agg(x.code order by x.ord), '[]'::jsonb)
               from (select p.code, l.ord from public.cargo_circuit_legs l join public.ports p on p.id = l.to_port
                      where l.circuit_id = c.circuit_id and l.ord > c.leg order by l.ord limit 5) x),
    'stops_left', (select count(*) from public.cargo_circuit_legs l where l.circuit_id = c.circuit_id and l.ord > c.leg),
    'ships', (select coalesce(jsonb_agg(world.ship_view(s.id) - array['id', 'water_t', 'food_t'] order by s.is_flagship desc, s.name), '[]'::jsonb)
                from public.ships s where s.fleet_id = p_fleet));
end
$body$
  $f$;
  comment on function world.cargo_ship_card(uuid) is '0310: one cargo ship, read at a tap: where she is bound, the funds aboard, her next stops, her hull. Refuses E_NOT_FOUND for any other fleet. Authenticated only.';
  revoke all on function world.cargo_ship_card(uuid) from public, anon;
  grant execute on function world.cargo_ship_card(uuid) to authenticated;

  -- ── 2. THE HUNKS: each occurs once ──
  v_old := array[
$h$p.company_name, nn.code as nation_code, h.ink, po.code as port_code,
$h$,
$h$      join public.npc_houses h on h.player_id = p.id
$h$,
$h$           'next_lap_at', case when pick.hold_until > now() then pick.hold_until end)
         order by pick.ord_nm, pick.roster_ord, pick.fleet_id), '[]'::jsonb)
$h$,
$h$    join public.npc_houses h on h.player_id = p.id
$h$,
$h$           'next_lap_at', case when sr.hold_until > now() then sr.hold_until end)
         order by nf.roster_ord, f.id), '[]'::jsonb)
$h$,
$h$                  where v3.fleet_id = f.id and v3.status = 'SAILING' and v3.eta <= now());
$h$,
$h$      select p.is_npc into v_npc from public.players p
$h$,
$h$             where f.status = 'SAILING' and p.is_npc)::bigint as at_sea_merchants
$h$,
$h$    || public.town_hall_people(p_port);
$h$,
$h$'counted_at', l.counted_at, 'counted_through', l.counted_through, 'drift', l.drift)
$h$,
$h$      ('world'::text, 'port_merchants'::text,  'uuid'::text),
$h$];
  v_new := array[
$h$p.company_name, nn.code as nation_code, h.ink, h.kind, po.code as port_code,
$h$,
$h$      join public.sea_houses() h on h.player_id = p.id   -- 0310: the merchants' houses and the cargo ships'
$h$,
$h$           'next_lap_at', case when pick.hold_until > now() then pick.hold_until end)
           || case when pick.kind is null then '{}'::jsonb else jsonb_build_object('kind', pick.kind) end   -- 0310: on a cargo ship alone
         order by pick.ord_nm, pick.roster_ord, pick.fleet_id), '[]'::jsonb)
$h$,
$h$    join public.sea_houses() h on h.player_id = p.id   -- 0310: the merchants' houses and the cargo ships'
$h$,
$h$           'next_lap_at', case when sr.hold_until > now() then sr.hold_until end)
           || case when h.kind is null then '{}'::jsonb else jsonb_build_object('kind', h.kind) end   -- 0310: on a cargo ship alone
         order by nf.roster_ord, f.id), '[]'::jsonb)
$h$,
$h$                  where v3.fleet_id = f.id and v3.status = 'SAILING' and v3.eta <= now())
      -- 0310: a cargo ship has no route to re-date, so a voyage that reached its eta since p_since says she docked.
      or (h.kind is not null and exists (select 1 from public.voyages v4 where v4.fleet_id = f.id and v4.eta >= p_since and v4.eta <= now()));
$h$,
$h$      select p.is_npc and not exists (select 1 from public.cargo_ships c where c.player_id = p.id) into v_npc from public.players p   -- 0310: a cargo ship is at sea, and no merchant
$h$,
$h$             where f.status = 'SAILING' and p.is_npc
               and not exists (select 1 from public.cargo_ships c where c.player_id = p.id))::bigint as at_sea_merchants   -- 0310: a cargo ship is at sea, and no merchant
$h$,
$h$    || public.town_hall_people(p_port)
    -- 0310: what a cargo ship is bringing this city, served only while one is.
    || public.funds_on_way(p_port);
$h$,
$h$'counted_at', l.counted_at, 'counted_through', l.counted_through, 'drift', l.drift)
         || public.cargo_figures()   -- 0310: cargo ships and funds at sea, served only while a ship exists
$h$,
$h$      ('world'::text, 'port_merchants'::text,  'uuid'::text),
      -- 0310: one cargo ship's card, read at a tap. At the head, as above.
      ('world',       'cargo_ship_card',       'uuid'),
$h$];
  for v_i in 1 .. array_length(v_old, 1) loop
    v_def := v_cur ->> v_fn[v_i];
    v_n := (length(v_def) - length(replace(v_def, v_old[v_i], ''))) / length(v_old[v_i]);
    if v_n <> 1 then
      raise exception '0310 self-assert FAIL: hunk % of % occurs % time(s), not once: the live body is not what this file was cut against', v_i, v_fn[v_i], v_n;
    end if;
    v_cur := v_cur || jsonb_build_object(v_fn[v_i], replace(v_def, v_old[v_i], v_new[v_i]));
  end loop;
  for v_i in 1 .. array_length(v_fn, 1) loop
    continue when v_i in (2, 3, 5, 6);    -- three hunks to a body: one write of each
    execute v_cur ->> v_fn[v_i];
  end loop;

  -- ── 3. THE SELF-ASSERT: hunks, grants, nothing else moved ──
  for v_i in 1 .. array_length(v_fn, 1) loop
    v_def := replace(pg_get_functiondef(v_fn[v_i]::regprocedure), E'\r', '');
    if v_def <> v_cur ->> v_fn[v_i] then
      raise exception '0310 self-assert FAIL: % is not the body this file wrote', v_fn[v_i];
    end if;
  end loop;
  for v_i in reverse array_length(v_old, 1) .. 1 loop
    v_def := v_cur ->> v_fn[v_i];
    if (length(v_def) - length(replace(v_def, v_new[v_i], ''))) / length(v_new[v_i]) <> 1 then
      raise exception '0310 self-assert FAIL: hunk % is not in the new body of % exactly once', v_i, v_fn[v_i];
    end if;
    v_cur := v_cur || jsonb_build_object(v_fn[v_i], replace(v_def, v_new[v_i], v_old[v_i]));
  end loop;
  if v_cur <> v_def0 then
    raise exception '0310 self-assert FAIL: a body does not reverse to its pre-image';
  end if;
  for v_i in 1 .. array_length(v_fn, 1) loop
    if (select coalesce(p.proacl::text, '') || p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '') from pg_proc p where p.oid = v_fn[v_i]::regprocedure) <> v_acl0 ->> v_fn[v_i] then
      raise exception '0310 self-assert FAIL: the grants or settings of % moved', v_fn[v_i];
    end if;
  end loop;
  if (select md5(string_agg(p.oid::regprocedure::text || ':' || md5(replace(pg_get_functiondef(p.oid), E'\r', '')), ',' order by p.oid::regprocedure::text))
        from pg_proc p where p.oid = any (v_oids)) <> v_fn_before then
    raise exception '0310 self-assert FAIL: another function moved';
  end if;
  if (select md5(string_agg(w.kind || ':' || w.side || ':' || w.word || ':' || w.ord, ',' order by w.kind)) from public.stats_flow_words w) <> v_word_before then
    raise exception '0310 self-assert FAIL: a word moved';
  end if;
  if (select md5(string_agg(t.tgrelid::regclass::text || ':' || t.tgname || ':' || t.tgenabled::text, ',' order by t.tgrelid::regclass::text, t.tgname))
        from pg_trigger t where not t.tgisinternal) <> v_trig_before then
    raise exception '0310 self-assert FAIL: a trigger moved';
  end if;
  if exists (select 1 from unnest(array['public.sea_houses()', 'public.funds_on_way(uuid)', 'public.cargo_figures()']) f
              where has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute')) then
    raise exception '0310 self-assert FAIL: a client can reach a helper';
  end if;
  if not has_function_privilege('authenticated', 'world.cargo_ship_card(uuid)', 'execute') or has_function_privilege('anon', 'world.cargo_ship_card(uuid)', 'execute') then
    raise exception '0310 self-assert FAIL: the card is not exactly authenticated-only';
  end if;
  if (select string_agg(p.provolatile::text, '' order by p.oid) from pg_proc p
       where p.oid in ('public.sea_houses()'::regprocedure, 'public.funds_on_way(uuid)'::regprocedure, 'public.cargo_figures()'::regprocedure, 'world.cargo_ship_card(uuid)'::regprocedure)) <> 'ssss' then
    raise exception '0310 self-assert FAIL: a read is not stable';
  end if;
  if (select count(*) from public.client_rpc_entry_points() e where e.function_name = 'cargo_ship_card' and e.fn is not null) <> 1 then
    raise exception '0310 self-assert FAIL: the card is not registered';
  end if;

  -- ── 4. DARK: each read against its pre-image, on the real world ──
  execute replace(replace(v_def0 ->> 'world.sea_traffic(jsonb)', 'FUNCTION world.sea_traffic(', 'FUNCTION pg_temp.sea_traffic_0309('), 'world.sea_traffic', 'pg_temp.sea_traffic_0309');
  execute replace(v_def0 ->> 'world.sea_roster(timestamp with time zone)', 'FUNCTION world.sea_roster(', 'FUNCTION pg_temp.sea_roster_0309(');
  execute replace(v_def0 ->> 'world.town_hall(uuid)', 'FUNCTION world.town_hall(', 'FUNCTION pg_temp.town_hall_0309(');
  execute replace(v_def0 ->> 'world.stats_now()', 'FUNCTION world.stats_now(', 'FUNCTION pg_temp.stats_now_0309(');

  v_port := (select p.id from public.ports p where p.kind = 'HARBOUR' order by p.code limit 1);
  begin
    update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled', 'standing_routes_enabled') and value is distinct from 'true'::jsonb;
    if world.sea_roster(null) is distinct from pg_temp.sea_roster_0309(null)
       or world.sea_roster(now() - interval '15 seconds') is distinct from pg_temp.sea_roster_0309(now() - interval '15 seconds') then
      raise exception '0310 self-assert FAIL: dark, world.sea_roster is not its pre-image';
    end if;
    if world.sea_traffic(v_view) is distinct from pg_temp.sea_traffic_0309(v_view) then
      raise exception '0310 self-assert FAIL: dark, world.sea_traffic is not its pre-image';
    end if;
    if world.town_hall(v_port) is distinct from pg_temp.town_hall_0309(v_port) then
      raise exception '0310 self-assert FAIL: dark, world.town_hall is not its pre-image';
    end if;
    if world.stats_now() is distinct from pg_temp.stats_now_0309() then
      raise exception '0310 self-assert FAIL: dark, world.stats_now is not its pre-image';
    end if;

    -- ── 5. LIT: a probe realm, every row rolled back ──
    update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed', 'convoys_enabled') and value is distinct from 'true'::jsonb;
    update public.world_config set value = to_jsonb(50000) where key = 'treasury_reserve_floor';
    insert into public.nations (code, name, flag_char, capital_port_code) values ('QX0', 'Probe 0310', 'Z', 'QVA') returning id into v_nat;
    insert into public.great_powers (nation_id) values (v_nat);
    insert into public.ports (code, name, country, lat, lon, sea_id, region_id, culture, size_tier, max_draft, kind)
    select x.code, 'Probe ' || x.code, t.country, t.lat, t.lon, t.sea_id, t.region_id, t.culture, t.size_tier, t.max_draft, 'HARBOUR'
      from (values ('QVA'), ('QVB'), ('QVC')) x(code)
     cross join (select * from public.ports where kind = 'HARBOUR' order by code limit 1) t;
    v_cap := (select p.id from public.ports p where p.code = 'QVA');
    insert into public.port_allegiance (port_id, nation_id) select p.id, v_nat from public.ports p where p.code like 'QV_';
    insert into public.port_treasury (port_id, ducats, reserve, earned_day) select p.id, 0, 0, world.game_day() from public.ports p where p.code like 'QV_';
    insert into public.npc_courses (from_port, to_port, course, nm)
    select a.id, b.id, x.course::jsonb, x.nm
      from (values ('QVA', 'QVB', '[[30,-40],[30.5,-40.5]]', 40.0), ('QVC', 'QVB', '[[31,-41],[30.5,-40.5]]', 41.0), ('QVC', 'QVA', '[[31,-41],[30,-40]]', 80.0)) x(f, t, course, nm)
      join public.ports a on a.code = x.f join public.ports b on b.code = x.t;

    perform public.tick_cargo_ships(now(), v_nat);
    v_fl := (select c.fleet_id from public.cargo_ships c where c.nation_id = v_nat and c.ord = 1);
    v_s1 := (select l.to_port from public.cargo_circuit_legs l join public.cargo_circuits k on k.id = l.circuit_id where k.nation_id = v_nat and l.ord = 1);
    v_s2 := (select l.to_port from public.cargo_circuit_legs l join public.cargo_circuits k on k.id = l.circuit_id where k.nation_id = v_nat and l.ord = 2);
    perform public.treasury_post(v_cap, 'CROWN_CALL', 1000000, null, null, true);
    perform public.treasury_post(v_s1, 'CROWN_CALL', 1000, null, null, true);
    perform public.treasury_post(v_s2, 'CROWN_CALL', 100, null, null, true);
    v_x := v_x || jsonb_build_object('aid', public.crown_aid(v_cap));
    v_day := clock_timestamp();
    v_x := v_x || jsonb_build_object('step', public.cargo_ship_step(v_fl));

    -- the sea: one row each, her kind on hers alone
    v_a := world.sea_roster(null);
    v_x := v_x || jsonb_build_object('roster_ships', (select count(*) from jsonb_array_elements(v_a -> 'fleets') e where e ->> 'kind' = 'CARGO_SHIP'),
      'roster_kinds', (select count(*) from jsonb_array_elements(v_a -> 'fleets') e where e ? 'kind'),
      'roster_row', (select e from jsonb_array_elements(v_a -> 'fleets') e where e ->> 'id' = v_fl::text),
      'roster_others', (select count(*) from jsonb_array_elements(pg_temp.sea_roster_0309(null) -> 'fleets') e)
                     = (select count(*) from jsonb_array_elements(v_a -> 'fleets') e where not e ? 'kind'));
    v_a := world.sea_roster(now());
    v_x := v_x || jsonb_build_object('delta_has_her', exists (select 1 from jsonb_array_elements(v_a -> 'fleets') e where e ->> 'id' = v_fl::text));
    v_a := world.sea_traffic(v_near);
    v_x := v_x || jsonb_build_object('traffic_kinds', (select count(*) from jsonb_array_elements(v_a -> 'fleets') e where e ->> 'kind' = 'CARGO_SHIP'),
      'traffic_total', (v_a ->> 'total')::int - (select count(*) from public.fleets f join public.players p on p.id = f.player_id and p.is_npc),
      'traffic_omitted', (v_a ->> 'total')::int - jsonb_array_length(v_a -> 'fleets') - (v_a ->> 'omitted')::int);
    v_x := v_x || jsonb_build_object('card', world.cargo_ship_card(v_fl));
    begin
      perform world.cargo_ship_card((select f.id from public.fleets f where not exists (select 1 from public.cargo_ships c where c.fleet_id = f.id) limit 1));
      v_x := v_x || '{"card_other":"answered"}';
    exception when others then v_x := v_x || jsonb_build_object('card_other', sqlerrm); end;
    perform public.treasury_post(v_cap, 'CROWN_CALL', -public.treasury_balance(v_cap), null, null, true);   -- a capital short as well is still told nothing: she pays it no aid
    v_x := v_x || jsonb_build_object('way_s1', public.funds_on_way(v_s1), 'way_s2', public.funds_on_way(v_s2), 'way_cap', public.funds_on_way(v_cap),
      'hall_way', world.town_hall(v_s1) -> 'funds_on_way', 'figures', world.stats_now() -> 'funds_at_sea', 'figures_ships', world.stats_now() -> 'cargo_ships', 'funds', public.funds_aboard(),
      'journal', (select jsonb_build_object('sea', coalesce(sum(d.at_sea), 0), 'merchants', coalesce(sum(d.at_sea_merchants), 0)) from public.stats_live_deltas d where d.at >= v_day));
    raise exception using errcode = 'ZX310', message = v_x::text;
  exception when sqlstate 'ZX310' then
    v_x := sqlerrm::jsonb;
  end;

  if v_x ->> 'step' <> 'SAILED' or (v_x #>> '{aid,loaded}')::bigint <= 0 then
    raise exception '0310 self-assert FAIL: the probe ship did not sail: %', v_x;
  end if;
  if (v_x ->> 'roster_ships')::int <> public.wc_int('convoy_ships_per_nation') or v_x ->> 'roster_kinds' <> v_x ->> 'roster_ships' or not (v_x ->> 'roster_others')::boolean then
    raise exception '0310 self-assert FAIL: world.sea_roster does not serve the ships and the merchants as they are: %', v_x;
  end if;
  if v_x #>> '{roster_row,ink}' is null or v_x #>> '{roster_row,voyage,to}' is null or v_x #>> '{roster_row,nation_code}' <> 'QX0' or jsonb_array_length(v_x #> '{roster_row,hulls}') <> 1 then
    raise exception '0310 self-assert FAIL: her row is not whole: %', v_x -> 'roster_row';
  end if;
  if not (v_x ->> 'delta_has_her')::boolean then
    raise exception '0310 self-assert FAIL: a delta does not carry her when she sails';
  end if;
  if (v_x ->> 'traffic_kinds')::int < 1 or (v_x ->> 'traffic_total')::int <> 0 or (v_x ->> 'traffic_omitted')::int <> 0 then
    raise exception '0310 self-assert FAIL: world.sea_traffic is not honest about her: %', v_x;
  end if;
  if v_x #>> '{card,funds}' is distinct from v_x ->> 'funds' or v_x #>> '{card,nation_code}' <> 'QX0' or v_x #>> '{card,home}' <> 'QVA'
     or v_x #>> '{card,to}' is null or (v_x #>> '{card,stops_left}')::int < 2 or jsonb_array_length(v_x #> '{card,ships}') <> 1 or v_x #> '{card,ships,0}' ? 'id' or v_x #> '{card,ships,0}' ? 'water_t' then
    raise exception '0310 self-assert FAIL: the card is not whole: %', v_x -> 'card';
  end if;
  if position('E_NOT_FOUND' in v_x ->> 'card_other') = 0 then
    raise exception '0310 self-assert FAIL: the card answered for another fleet: %', v_x ->> 'card_other';
  end if;
  if (v_x #>> '{way_s1,funds_on_way,ducats}')::bigint is distinct from 49000 or (v_x #>> '{way_s1,funds_on_way,stops}')::int is distinct from 0 or v_x #>> '{way_s1,funds_on_way,eta}' is null then
    raise exception '0310 self-assert FAIL: funds on the way at her next stop: %', v_x -> 'way_s1';
  end if;
  if (v_x #>> '{way_s2,funds_on_way,stops}')::int is distinct from 1 or v_x #>> '{way_s2,funds_on_way,eta}' is not null then
    raise exception '0310 self-assert FAIL: funds on the way at the stop after: %', v_x -> 'way_s2';
  end if;
  if v_x -> 'way_cap' <> '{}'::jsonb then
    raise exception '0310 self-assert FAIL: funds on the way at her own capital: %', v_x -> 'way_cap';
  end if;
  if v_x -> 'hall_way' is distinct from v_x #> '{way_s1,funds_on_way}' then
    raise exception '0310 self-assert FAIL: the hall does not serve funds on the way';
  end if;
  if v_x ->> 'figures' is distinct from v_x ->> 'funds' or (v_x ->> 'figures_ships')::int is distinct from public.wc_int('convoy_ships_per_nation') then
    raise exception '0310 self-assert FAIL: world.stats_now does not serve the figures: %', v_x;
  end if;
  if (v_x #>> '{journal,sea}')::int <> 1 or (v_x #>> '{journal,merchants}')::int <> 0 then
    raise exception '0310 self-assert FAIL: she was journalled as a merchant at sea: %', v_x -> 'journal';
  end if;

  if (select md5(string_agg(c.key || ':' || c.value::text || ':' || coalesce(c.description, '') || ':' || c.updated_at::text, ',' order by c.key)) from public.world_config c) <> v_cfg_before then
    raise exception '0310 self-assert FAIL: a world_config row moved';
  end if;
  if public.convoys_on() or exists (select 1 from public.cargo_ships) or exists (select 1 from public.convoy_cargo) or exists (select 1 from public.cargo_circuits) or public.funds_aboard() <> 0 then
    raise exception '0310 self-assert FAIL: this world is not dark and empty';
  end if;
  if clock_timestamp() - v_t0 > interval '45 seconds' then
    raise exception '0310 self-assert FAIL: over budget, %', clock_timestamp() - v_t0;
  end if;
  raise notice '0310 self-assert ok: dark, each read is its pre-image; lit, % ships served with their kind, % d. aboard, %, in %',
    v_x ->> 'roster_ships', v_x ->> 'funds', v_x -> 'way_s1', clock_timestamp() - v_t0;
end
$m$;
