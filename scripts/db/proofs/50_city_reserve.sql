-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 50 — THE DEFAULT CITY RESERVE  (migration 0343, owner row 281: "cities should have gold reserve as default", "capital comes first")
--
--   0343's self-assert reads the catalog and runs public.crown_aid over a probe realm alone (a migration never runs a real game step, docs/OPS_HEALTH.md section 4). This proof runs the REAL
--   public.city_day over the WHOLE world, the REAL public.crown_aid with rich cities sending the ships (0324, as prod runs), the REAL cargo job's commissioning, the REAL wind job's gate and the
--   REAL price terms, on real harbours of Portugal's realm, the pirates' harbours and a free city, every pass rolled back by proof.mjs. The economy is CLOSED and the purses lit, as on prod.
--
-- @pass RES_DARK    off: at every harbour the floor is the flat knob and the target is 0306's formula; the real city_day over the world is 0306's rule to the ducat (a broke city to 50,000, a city under a higher rolled reserve to it)
-- @pass RES_SIZE    lit: the size is tier x 100,000 at real harbours of tiers 2, 3 and 5, a capital's x 5 and the realm's largest, a pirate home and a free city sized as cities, a city that grows or shrinks reads its new size, the knobs move it
-- @pass RES_TARGET  lit: at every harbour the target is greatest(rolled reserve, size); the rolled reserve wins where it is higher
-- @pass RES_FILL    lit, the instant path (ships off): the real city_day tops the realm's short cities up to their sizes from the capital, exactly, the answer equal to its flows; a second run gives nothing; a poorer capital stops exactly at its rolled reserve
-- @pass RES_BROKE   lit: a capital under its rolled reserve with no donor lays nothing off, no error, on both paths (nothing instant, nothing loaded)
-- @pass RES_SHIPS   lit, rich cities send the ships (as prod runs): the roster holds the capital with its size, one ship loads the realm's whole need at the donor, the donor keeps its own size (crown_call_room), no CROWN_AID and no CROWN_CALL
-- @pass RES_PIRATE  the pirates' capital, a pirate home and a crown city the pirates took, all under their size: no aid, no load, no call reaches them on either path, the hoard does not move; the realm's own city is still aided
-- @pass RES_PRICE   never a price: world.price_terms, city_bid_factor, city_surplus and the rolled reserve are the same at both states for a city under its size, with and without a rolled reserve; a broke city's bid is 1 with no rolled reserve
-- @pass RES_WIND    the wind's gate: dark, a harbour at 49,999 posts no request and one at 50,000 is asked; lit, one at its size less 1 is left alone and one at its size is asked
-- @pass RES_MONEY   W (purses + companies + funds aboard) unchanged to the ducat across every aid pass above; the switch and the knobs end as the file shipped them
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  v_last  int := world.game_day() - 1;
  v_slot  int := (floor(extract(epoch from now()) / 60)::bigint % 1440)::int;
  v_nat   uuid;
  v_pir   uuid;
  v_cap   uuid;
  v_cit   uuid[];
  v_a     uuid;   -- a city of the realm, short
  v_b     uuid;   -- a city of the realm, short, with a small rolled reserve
  v_d     uuid;   -- the realm's donor
  v_t2    uuid; v_t3 uuid; v_t5 uuid;   -- crown cities of tiers 2, 3, 5, any realm
  v_por   uuid;   -- the pirates' capital
  v_home  uuid;   -- a pirate home that is not the capital
  v_taken uuid;   -- a crown city the pirates took
  v_free  uuid;   -- a harbour no country holds
  v_size_a bigint; v_size_b bigint; v_size_cap bigint; v_size_d bigint;
  v_w     numeric;
  v_w0    numeric;
  v_mark  bigint;
  v_r     jsonb;
  v_x     jsonb;
  v_y     jsonb;
  v_n     int;
  v_bad   int;
begin
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed', 'convoys_enabled');
  update public.world_config set value = 'false'::jsonb where key in ('convoy_rich_enabled', 'city_reserve_enabled', 'npc_refits_enabled');
  update public.world_config set value = to_jsonb(50000) where key = 'treasury_reserve_floor';
  update public.world_config set value = to_jsonb(100000) where key = 'city_reserve_per_tier';
  update public.world_config set value = to_jsonb(5) where key = 'city_reserve_capital_mult';
  update public.world_config set value = to_jsonb(0.1) where key = 'crown_call_share';
  update public.world_config set value = to_jsonb(20) where key = 'crown_call_cover';
  update public.world_config set value = to_jsonb(1) where key = 'convoy_idle_every';
  update public.world_config set value = to_jsonb(3) where key = 'convoy_rich_ports';
  update public.cargo_fleet_sizes set ships = 4, read_at = now();
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set earned_day = v_last, ducats = 10000000, reserve = 0;   -- only the aid runs; everyone above every size

  execute $f$
create function pg_temp.w()
returns numeric
language sql
as $b$
  select (select coalesce(sum(public.treasury_balance(t.port_id)), 0) from public.port_treasury t)::numeric
       + (select coalesce(sum(p.ducats), 0) from public.players p)::numeric + public.funds_aboard()::numeric
$b$
  $f$;
  execute $f$
create function pg_temp.purse(p_port uuid, p_d bigint)
returns void
language plpgsql
as $b$
declare
  v_by bigint := p_d - public.treasury_balance(p_port);
begin
  update public.port_treasury t set reserve = 0 where t.port_id = p_port;
  if v_by <> 0 then
    perform public.treasury_post(p_port, 'CROWN_CALL', v_by, null, null, true);   -- a probe's hand on a purse: every reader below takes its mark after this
  end if;
end
$b$
  $f$;
  execute $f$
create function pg_temp.flows(p_mark bigint)
returns jsonb
language sql
as $b$
  select coalesce(jsonb_object_agg(x.k, x.d), '{}'::jsonb)
    from (select p.code || ':' || f.kind as k, sum(f.ducats) as d from public.treasury_flows f join public.ports p on p.id = f.port_id where f.id > p_mark group by 1) x
$b$
  $f$;
  -- the wind on one harbour, one pass in this transaction: how many harbours it asked (0 or 1)
  execute $f$
create function pg_temp.wind(p_port uuid, p_slot int)
returns int
language plpgsql
as $b$
declare
  v int;
begin
  delete from public.contract_wind w where w.port_id = p_port;
  delete from public.contract_wind_runs r where r.slot = p_slot;
  call public.tick_contract_wind(false, p_port);
  select (r.receipt ->> 'tried')::int into v from public.contract_wind_runs r where r.slot = p_slot;
  return coalesce(v, -1);
end
$b$
  $f$;

  -- ── THE SUBJECTS, found by query ──
  select g.nation_id into v_nat from public.great_powers g join public.nations n on n.id = g.nation_id where n.code = 'PRT';
  v_pir := public.pirate_nation();
  v_cap := public.realm_capital(v_nat);
  v_cit := array(select p.id from public.ports p
                  where p.kind = 'HARBOUR' and p.id <> v_cap and public.port_nation(p.id) = v_nat
                    and exists (select 1 from public.npc_courses c where c.from_port = p.id or c.to_port = p.id)
                  order by p.code);
  if v_nat is null or v_pir is null or v_cap is null or cardinality(v_cit) < 5 then
    raise exception 'PROOF 50 FAIL: Portugal (% harbours on a course), its capital or the Brethren are missing', cardinality(v_cit);
  end if;
  v_d := v_cit[1]; v_a := v_cit[2]; v_b := v_cit[3]; v_taken := v_cit[4]; v_free := v_cit[5];
  -- a harbour no country holds (this world holds every harbour, so one of the realm's is set free here)
  delete from public.port_allegiance a where a.port_id = v_free;
  select p.id into v_t2 from public.ports p where p.kind = 'HARBOUR' and p.size_tier = 2 and public.city_capital(p.id) is not null and public.city_capital(p.id) <> p.id order by p.code limit 1;
  select p.id into v_t3 from public.ports p where p.kind = 'HARBOUR' and p.size_tier = 3 and public.city_capital(p.id) is not null and public.city_capital(p.id) <> p.id order by p.code limit 1;
  select p.id into v_t5 from public.ports p where p.kind = 'HARBOUR' and p.size_tier = 5 and public.city_capital(p.id) is not null and public.city_capital(p.id) <> p.id order by p.code limit 1;
  v_por := public.pirate_capital();
  select a.port_id into v_home from public.port_allegiance a where a.nation_id = v_pir and a.home and a.port_id <> v_por order by a.port_id limit 1;
  if v_t2 is null or v_t3 is null or v_t5 is null or v_por is null or v_home is null or v_free is null then
    raise exception 'PROOF 50 FAIL: a subject is missing (tiers % % %, pirate capital %, home %, free %)', v_t2, v_t3, v_t5, v_por, v_home, v_free;
  end if;
  -- a crown city of the realm falls to the pirates
  update public.port_allegiance set nation_id = v_pir where port_id = v_taken;
  if public.city_capital(v_taken) is not null or public.city_capital(v_por) is not null or public.city_capital(v_free) is not null or public.city_capital(v_a) <> v_cap then
    raise exception 'PROOF 50 FAIL: the crowns are not as planned';
  end if;

  -- ── RES_DARK: the flat rule, at every harbour and through the real city_day ──
  select count(*) into v_bad from public.ports p join public.port_treasury t on t.port_id = p.id
   where p.kind = 'HARBOUR' and (public.city_floor(p.id) <> 50000 or public.city_aid_target(p.id) <> greatest(t.reserve, 50000));
  if v_bad <> 0 then
    raise exception 'PROOF 50 FAIL: dark, % harbour(s) do not read the flat floor', v_bad;
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'convoys_enabled';   -- the instant path
  perform pg_temp.purse(v_a, 1000);
  perform pg_temp.purse(v_b, 100);
  update public.port_treasury set reserve = 60000 where port_id = v_b;
  perform pg_temp.purse(v_por, 100);
  perform pg_temp.purse(v_home, 100);
  perform pg_temp.purse(v_taken, 100);
  v_w := pg_temp.w();
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_r := public.city_day();
  v_x := pg_temp.flows(v_mark);
  if (v_x ->> ((select code from public.ports where id = v_a) || ':CROWN_AID'))::bigint is distinct from 49000
     or (v_x ->> ((select code from public.ports where id = v_b) || ':CROWN_AID'))::bigint is distinct from 59900
     or (v_x ->> ((select code from public.ports where id = v_cap) || ':CROWN_AID'))::bigint is distinct from -108900
     or (v_r ->> 'aided')::int <> 2 or (v_r ->> 'aid')::bigint <> 108900 or pg_temp.w() <> v_w then
    raise exception 'PROOF 50 FAIL: dark, the real city_day is not 0306''s rule: % %', v_r, v_x;
  end if;
  if exists (select 1 from public.treasury_flows f where f.id > v_mark and f.port_id in (v_por, v_home, v_taken)) then
    raise exception 'PROOF 50 FAIL: dark, a pirate harbour was touched: %', v_x;
  end if;
  raise notice 'PASS: RES_DARK — every harbour at the flat floor; city_day: the broke city 49,000, the city under a 60,000 reserve 59,900, the capital -108,900; W unchanged';

  -- ── RES_SIZE: the formula at real harbours ──
  update public.world_config set value = 'true'::jsonb where key = 'city_reserve_enabled';
  if not public.city_reserve_on() then
    raise exception 'PROOF 50 FAIL: the switch does not read';
  end if;
  v_size_cap := public.city_default_reserve(v_cap);
  v_size_a := public.city_default_reserve(v_a);
  v_size_b := public.city_default_reserve(v_b);
  v_size_d := public.city_default_reserve(v_d);
  if public.city_default_reserve(v_t2) <> 200000 or public.city_default_reserve(v_t3) <> 300000 or public.city_default_reserve(v_t5) <> 500000
     or v_size_cap <> (select p.size_tier from public.ports p where p.id = v_cap) * 100000 * 5
     or v_size_a <> (select p.size_tier from public.ports p where p.id = v_a) * 100000
     or v_size_cap <= (select max(public.city_default_reserve(p.id)) from public.ports p where p.kind = 'HARBOUR' and p.id <> v_cap and public.city_capital(p.id) = v_cap) then
    raise exception 'PROOF 50 FAIL: the size is not tier x 100,000, the capital x 5 and the realm''s largest: % % % cap % a %',
      public.city_default_reserve(v_t2), public.city_default_reserve(v_t3), public.city_default_reserve(v_t5), v_size_cap, v_size_a;
  end if;
  if public.city_default_reserve(v_por) <> (select p.size_tier from public.ports p where p.id = v_por) * 100000
     or public.city_default_reserve(v_home) <> (select p.size_tier from public.ports p where p.id = v_home) * 100000
     or public.city_default_reserve(v_taken) <> (select p.size_tier from public.ports p where p.id = v_taken) * 100000
     or public.city_default_reserve(v_free) <> (select p.size_tier from public.ports p where p.id = v_free) * 100000 then
    raise exception 'PROOF 50 FAIL: a harbour of no crown is not sized as a city of its tier';
  end if;
  update public.ports set size_tier = 5 where id = v_t2;
  v_n := public.city_default_reserve(v_t2);
  update public.ports set size_tier = 1 where id = v_t2;
  if v_n <> 500000 or public.city_default_reserve(v_t2) <> 100000 or public.city_floor(v_t2) <> 100000 then
    raise exception 'PROOF 50 FAIL: a city that grows or shrinks does not read its new size: % %', v_n, public.city_default_reserve(v_t2);
  end if;
  update public.ports set size_tier = 2 where id = v_t2;
  update public.world_config set value = to_jsonb(70000) where key = 'city_reserve_per_tier';
  update public.world_config set value = to_jsonb(3) where key = 'city_reserve_capital_mult';
  if public.city_default_reserve(v_t2) <> 140000 or public.city_default_reserve(v_cap) <> (select p.size_tier from public.ports p where p.id = v_cap) * 70000 * 3 then
    raise exception 'PROOF 50 FAIL: the knobs do not move the size';
  end if;
  update public.world_config set value = to_jsonb(100000) where key = 'city_reserve_per_tier';
  update public.world_config set value = to_jsonb(5) where key = 'city_reserve_capital_mult';
  raise notice 'PASS: RES_SIZE — tiers 2/3/5 = 200,000 / 300,000 / 500,000; the capital % (x5, the realm''s largest); the pirates'' capital, a pirate home, a taken city and a free city sized as cities; grown 500,000, shrunk 100,000; knobs 70,000 x 3 read', v_size_cap;

  -- ── RES_TARGET ──
  update public.port_treasury set reserve = 777777 where port_id = v_t2;   -- a rolled reserve above its size
  select count(*) into v_bad from public.ports p join public.port_treasury t on t.port_id = p.id
   where p.kind = 'HARBOUR' and (public.city_floor(p.id) <> public.city_default_reserve(p.id) or public.city_aid_target(p.id) <> greatest(t.reserve, public.city_default_reserve(p.id)));
  if v_bad <> 0 or public.city_aid_target(v_t2) <> 777777 or public.city_aid_target(v_b) <> v_size_b then
    raise exception 'PROOF 50 FAIL: lit, % harbour(s) do not read greatest(rolled, size); t2 %, b %', v_bad, public.city_aid_target(v_t2), public.city_aid_target(v_b);
  end if;
  update public.port_treasury set reserve = 0 where port_id = v_t2;
  raise notice 'PASS: RES_TARGET — every harbour at greatest(rolled reserve, size); a 777,777 rolled reserve wins over a 200,000 size';

  -- ── RES_FILL: the instant path through the real city_day (ships still off) ──
  -- v_a is at 1,000 + 49,000 = 50,000 and v_b at 60,000 after RES_DARK; the pirate harbours at 100
  v_w := pg_temp.w();
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_r := public.city_day();
  v_x := pg_temp.flows(v_mark);
  if (v_x ->> ((select code from public.ports where id = v_a) || ':CROWN_AID'))::bigint is distinct from v_size_a - 50000
     or (v_x ->> ((select code from public.ports where id = v_b) || ':CROWN_AID'))::bigint is distinct from v_size_b - 60000
     or (v_x ->> ((select code from public.ports where id = v_cap) || ':CROWN_AID'))::bigint is distinct from -(v_size_a - 50000 + v_size_b - 60000)
     or (v_r ->> 'aided')::int <> 2 or (v_r ->> 'aid')::bigint <> v_size_a - 50000 + v_size_b - 60000 or pg_temp.w() <> v_w
     or public.treasury_balance(v_a) <> v_size_a or public.treasury_balance(v_b) <> v_size_b then
    raise exception 'PROOF 50 FAIL: lit, the real city_day did not top the cities up to their sizes exactly: % %', v_r, v_x;
  end if;
  if exists (select 1 from public.treasury_flows f where f.id > v_mark and f.port_id in (v_por, v_home, v_taken)) then
    raise exception 'PROOF 50 FAIL: lit, a pirate harbour was aided: %', v_x;
  end if;
  v_r := public.city_day();
  if (v_r ->> 'aided')::int <> 0 or (v_r ->> 'aid')::bigint <> 0 or pg_temp.w() <> v_w then
    raise exception 'PROOF 50 FAIL: a second run gave more: %', v_r;
  end if;
  -- a poorer capital stops exactly at its rolled reserve (0306's rule stands: its own size is an aid target, not a lock); every other city of the realm exactly at its size, so no donor has room and nobody else is short
  perform pg_temp.purse(t.port_id, public.city_default_reserve(t.port_id)) from public.port_treasury t where public.city_capital(t.port_id) = v_cap and t.port_id <> v_cap;
  perform pg_temp.purse(v_cap, 7777 + 150000);
  update public.port_treasury set reserve = 7777 where port_id = v_cap;
  perform pg_temp.purse(v_a, 1000);
  v_w := pg_temp.w();
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_r := public.crown_aid(v_cap);
  if (v_r ->> 'aid')::bigint <> 150000 or public.treasury_balance(v_cap) <> 7777 or public.treasury_balance(v_a) <> 151000 or pg_temp.w() <> v_w then
    raise exception 'PROOF 50 FAIL: a poorer capital did not stop exactly at its rolled reserve: % cap % a %', v_r, public.treasury_balance(v_cap), public.treasury_balance(v_a);
  end if;
  raise notice 'PASS: RES_FILL — city_day: % to the broke city and % to the other, exactly to their sizes, the answer its flows; a second run 0; a capital with 150,000 above its reserve gave 150,000 and stopped at it', v_size_a - 50000, v_size_b - 60000;

  -- ── RES_BROKE: instant ──
  perform pg_temp.purse(v_cap, 1000);
  update public.port_treasury set reserve = 7777 where port_id = v_cap;
  perform pg_temp.purse(t.port_id, public.city_default_reserve(t.port_id)) from public.port_treasury t where public.city_capital(t.port_id) = v_cap and t.port_id <> v_cap;   -- every city exactly at its size: no donor, nobody else short
  perform pg_temp.purse(v_a, 1000);
  v_w := pg_temp.w();
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_r := public.crown_aid(v_cap);
  if (v_r ->> 'aided')::int <> 0 or (v_r ->> 'aid')::bigint <> 0 or (v_r ->> 'called')::bigint <> 0 or pg_temp.flows(v_mark) <> '{}'::jsonb or pg_temp.w() <> v_w then
    raise exception 'PROOF 50 FAIL: a broke capital laid something off, instant: % %', v_r, pg_temp.flows(v_mark);
  end if;

  -- ── RES_SHIPS: rich cities send the ships, as prod runs ──
  update public.world_config set value = 'true'::jsonb where key in ('convoys_enabled', 'convoy_rich_enabled');
  if not public.rich_cities_on() then
    raise exception 'PROOF 50 FAIL: rich cities did not light';
  end if;
  perform pg_temp.purse(v_d, 1000000000);
  perform pg_temp.purse(v_cap, 100000);
  update public.port_treasury set reserve = 0 where port_id = v_cap;
  perform pg_temp.purse(v_a, 1000);
  if public.crown_call_room(v_d) <> floor(0.1 * (1000000000 - v_size_d))::bigint then
    raise exception 'PROOF 50 FAIL: the donor does not keep its own size: room % size %', public.crown_call_room(v_d), v_size_d;
  end if;
  if (public.cargo_origins(v_nat))[1] <> v_d then
    raise exception 'PROOF 50 FAIL: the donor is not the realm''s first origin: %', public.cargo_origins(v_nat);
  end if;
  perform public.tick_cargo_ships(now(), v_nat);   -- the realm's ships are made at their origins
  if not exists (select 1 from public.cargo_ships c join public.fleets f on f.id = c.fleet_id where c.nation_id = v_nat and c.home_port_id = v_d and f.status = 'DOCKED' and f.port_id = v_d) then
    raise exception 'PROOF 50 FAIL: no idle ship at the donor';
  end if;
  v_w := pg_temp.w();
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_r := public.crown_aid(v_cap);
  v_x := pg_temp.flows(v_mark);
  if (v_r ->> 'loaded')::bigint <> (v_size_cap - 100000) + (v_size_a - 1000) or (v_r ->> 'ships')::int <> 1
     or (v_r ->> 'aided')::int <> 0 or (v_r ->> 'called')::bigint <> 0
     or (v_x ->> ((select code from public.ports where id = v_d) || ':CONVOY_LOAD'))::bigint is distinct from -((v_size_cap - 100000) + (v_size_a - 1000))
     or exists (select 1 from public.treasury_flows f where f.id > v_mark and f.kind in ('CROWN_AID', 'CROWN_CALL'))
     or pg_temp.w() <> v_w then
    raise exception 'PROOF 50 FAIL: the ship did not load the realm''s whole need (the capital''s size counted) at the donor: % %', v_r, v_x;
  end if;
  raise notice 'PASS: RES_SHIPS — one ship loaded % at the donor: the capital''s gap % (to its size %) and the city''s %; the donor''s room keeps its size; no CROWN_AID, no CROWN_CALL; W unchanged',
    v_r ->> 'loaded', v_size_cap - 100000, v_size_cap, v_size_a - 1000;

  -- ── RES_BROKE: lit with ships, no room anywhere ──
  perform public.convoy_book('RETURNED', c.fleet_id, c.player_id, c.home_port_id, a.aboard, a.load_id)
     from public.cargo_ships c cross join lateral public.cargo_ship_aboard(c.fleet_id) a where c.nation_id = v_nat and a.aboard > 0;   -- the load back ashore, so the realm's ships carry nothing
  perform pg_temp.purse(t.port_id, public.city_default_reserve(t.port_id)) from public.port_treasury t where public.city_capital(t.port_id) = v_cap and t.port_id <> v_cap;
  perform pg_temp.purse(v_cap, 1000);
  update public.port_treasury set reserve = 7777 where port_id = v_cap;
  perform pg_temp.purse(v_a, 1000);
  v_w := pg_temp.w();
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_r := public.crown_aid(v_cap);
  if (v_r ->> 'loaded')::bigint <> 0 or (v_r ->> 'ships')::int <> 0 or pg_temp.flows(v_mark) <> '{}'::jsonb or pg_temp.w() <> v_w then
    raise exception 'PROOF 50 FAIL: a broke realm loaded something: % %', v_r, pg_temp.flows(v_mark);
  end if;
  raise notice 'PASS: RES_BROKE — a capital under its rolled reserve with no donor: instant nothing (aided 0, called 0), ships nothing (loaded 0); no flow, no error, W unchanged';

  -- ── RES_PIRATE: nothing reaches the pirates on either path; the realm's city is still aided ──
  perform pg_temp.purse(v_d, 1000000000);
  perform pg_temp.purse(v_cap, 10000000);
  update public.port_treasury set reserve = 0 where port_id = v_cap;
  perform pg_temp.purse(v_a, 1000);
  v_y := jsonb_build_object('hoard', public.pirate_hoard(), 'por', public.treasury_balance(v_por), 'home', public.treasury_balance(v_home), 'taken', public.treasury_balance(v_taken));
  v_w := pg_temp.w();
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_r := public.crown_aid(null);   -- the real roster of the whole world, ships lit
  if (v_r ->> 'loaded')::bigint <> v_size_a - 1000 or exists (select 1 from public.treasury_flows f where f.id > v_mark and f.port_id in (v_por, v_home, v_taken))
     or public.pirate_hoard() <> (v_y ->> 'hoard')::bigint or pg_temp.w() <> v_w then
    raise exception 'PROOF 50 FAIL: lit with ships, the pirates were reached, or the realm''s city was not loaded for: % % %', v_r, pg_temp.flows(v_mark), v_y;
  end if;
  update public.world_config set value = 'false'::jsonb where key in ('convoys_enabled', 'convoy_rich_enabled');
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);
  v_r := public.city_day();   -- the instant path over the whole world
  if (v_r ->> 'aided')::int <> 1 or (v_r ->> 'aid')::bigint <> v_size_a - 1000 or exists (select 1 from public.treasury_flows f where f.id > v_mark and f.port_id in (v_por, v_home, v_taken))
     or public.treasury_balance(v_por) <> 100 or public.treasury_balance(v_home) <> 100 or public.treasury_balance(v_taken) <> 100 or public.pirate_hoard() <> (v_y ->> 'hoard')::bigint or pg_temp.w() <> v_w then
    raise exception 'PROOF 50 FAIL: instant, the pirates were reached, or the realm''s city was not aided: % % %', v_r, pg_temp.flows(v_mark), v_y;
  end if;
  raise notice 'PASS: RES_PIRATE — the pirates'' capital, a home and a taken city at 100 d. under their sizes: no flow on either path, the hoard % unmoved; the realm''s city aided % (ships: loaded for)', v_y ->> 'hoard', v_size_a - 1000;

  -- ── RES_PRICE: never a price ──
  perform pg_temp.purse(v_t3, 100);   -- under its size, no rolled reserve
  update public.port_treasury set reserve = 0 where port_id = v_t3;
  perform pg_temp.purse(v_t5, 400000);
  update public.port_treasury set reserve = 900000 where port_id = v_t5;   -- under its size and under a rolled reserve: a bid under 1
  update public.world_config set value = 'false'::jsonb where key = 'city_reserve_enabled';
  select jsonb_build_array(
           (select to_jsonb(t) from world.price_terms(v_t3) t), public.city_bid_factor(v_t3), public.city_surplus(v_t3), public.treasury_reserve(v_t3),
           (select to_jsonb(t) from world.price_terms(v_t5) t), public.city_bid_factor(v_t5), public.city_surplus(v_t5), public.treasury_reserve(v_t5)) into v_x;
  update public.world_config set value = 'true'::jsonb where key = 'city_reserve_enabled';
  select jsonb_build_array(
           (select to_jsonb(t) from world.price_terms(v_t3) t), public.city_bid_factor(v_t3), public.city_surplus(v_t3), public.treasury_reserve(v_t3),
           (select to_jsonb(t) from world.price_terms(v_t5) t), public.city_bid_factor(v_t5), public.city_surplus(v_t5), public.treasury_reserve(v_t5)) into v_y;
  if v_x <> v_y or (v_x ->> 1)::numeric <> 1 or (v_x ->> 5)::numeric >= 1 or (v_x ->> 5)::numeric <= 0 or public.city_floor(v_t3) <> 300000 then
    raise exception 'PROOF 50 FAIL: the reserve moved a price, a bid, a surplus or a rolled reserve: % %', v_x, v_y;
  end if;
  raise notice 'PASS: RES_PRICE — price terms, bid, surplus and rolled reserve identical at both states for a city at 100 d. (bid 1) and one at 400,000 under a 900,000 reserve (bid %)', v_x ->> 5;

  -- ── RES_WIND: the gate ──
  update public.world_config set value = to_jsonb(60000) where key = 'contract_wind_ms';
  update public.world_config set value = to_jsonb(1) where key = 'contract_wind_posts';
  update public.world_config set value = 'false'::jsonb where key = 'city_reserve_enabled';
  perform pg_temp.purse(v_t2, 49999);
  v_n := pg_temp.wind(v_t2, v_slot);
  perform pg_temp.purse(v_t2, 50000);
  if v_n <> 0 or pg_temp.wind(v_t2, v_slot) <> 1 then
    raise exception 'PROOF 50 FAIL: dark, the wind''s gate is not the flat floor (49,999 tried %, 50,000 tried %)', v_n, pg_temp.wind(v_t2, v_slot);
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'city_reserve_enabled';
  perform pg_temp.purse(v_t2, 199999);
  v_n := pg_temp.wind(v_t2, v_slot);
  perform pg_temp.purse(v_t2, 200000);
  if v_n <> 0 or pg_temp.wind(v_t2, v_slot) <> 1 then
    raise exception 'PROOF 50 FAIL: lit, the wind''s gate is not the city''s size (199,999 tried %, 200,000 tried %)', v_n, pg_temp.wind(v_t2, v_slot);
  end if;
  raise notice 'PASS: RES_WIND — dark: 49,999 left alone, 50,000 asked; lit: 199,999 left alone, 200,000 asked (a tier-2 city)';

  -- ── RES_MONEY ──
  if public.wc_num('city_reserve_per_tier') <> 100000 or public.wc_num('city_reserve_capital_mult') <> 5 or not public.city_reserve_on() then
    raise exception 'PROOF 50 FAIL: the knobs or the switch are not where this proof left them';
  end if;
  raise notice 'PASS: RES_MONEY — W unchanged to the ducat across every aid pass (asserted at each); knobs 100,000 x 5';
end $$;
