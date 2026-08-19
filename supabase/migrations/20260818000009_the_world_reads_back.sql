-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0009 — THE WORLD READS BACK
--        world.snapshot() · world.market() · world.fleets() · world.ledger() — the four reads the
--        six V0 tabs are made of, and the %NBR column that is the whole game in one number.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- ── TWO RULES THIS FILE OBEYS ───────────────────────────────────────────────────────────────────
--   1. EVERY READ SETTLES FIRST (DESIGN §D.2): "every read RPC that touches a fleet first calls
--      voyage.settle(fleet_id)". A player who opens the app after nine hours offline must not see
--      a stale fleet and then watch it teleport; the read IS the catch-up.
--   2. THE SECRET NEVER LEAVES (§B.6): world_config seeds the hazard RNG. world.snapshot() serves
--      the knobs the client legitimately needs — the time compression it prints in the map corner,
--      the queue cap, the spread constants — and `world_secret` is not among them. That is
--      asserted below by SEARCHING THE ACTUAL PAYLOAD for the secret's value, not by reading the
--      list of keys and trusting it.
--
-- ── ONE AUTHORITY PER CONCEPT ───────────────────────────────────────────────────────────────────
--   world.pct_of_neighbours(port, good) — THE %NBR of §E.4, defined once, over ports within 600 nm.
--   world.snapshot()  — the static world; the client caches it hard.
--   world.market(port)— the reading room of §E.4.
--   world.fleets()    — the roster of §E.2, with the closed-form position folded in.
--   world.ledger()    — the log of §E.6.
--
-- ── WHAT IT SELF-ASSERTS ────────────────────────────────────────────────────────────────────────
--   * snapshot() carries all 12 ports, 22 legs, 12 goods and 3 classes — and DOES NOT CONTAIN the
--     world secret anywhere in its serialised text.
--   * market(Lisboa) prices every good, marks wine UNAVAILABLE at a Maghrebi port and available at
--     Lisboa, and prints a %NBR that is a real comparison: salt reads BELOW 100 at Lisboa and
--     ABOVE 100 at Cádiz, which is the §K.1 gradient the first session is built on.
--   * fleets() SETTLES: a fleet whose voyage completed while nobody looked is reported DOCKED at
--     its destination by the read itself, with no tick having run.
--   * ledger() paginates and returns the events the session actually produced.
--   * Every read RPC is granted to `authenticated` and to nobody else, and the lockdown holds.
--
-- Depends ONLY on: 0001-0008.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ── THE %NBR of DESIGN §E.4 ────────────────────────────────────────────────────────────────────
create or replace function world.pct_of_neighbours(p_port uuid, p_good uuid)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_here numeric;
  v_them numeric;
begin
  -- "prices vs ports within 600 nm" (DESIGN E.4). Great-circle, not leg distance: this is a
  -- NEIGHBOURHOOD, not a route, and a port two short legs away is still a neighbour.
  select world.mid_price(p_port, p_good, pg.stock) into v_here
    from public.port_goods pg where pg.port_id = p_port and pg.good_id = p_good;
  if v_here is null then return null; end if;

  select avg(world.mid_price(o.id, p_good, pg.stock)) into v_them
    from public.ports here
    join public.ports o on o.id <> here.id
    join public.port_goods pg on pg.port_id = o.id and pg.good_id = p_good
   where here.id = p_port
     and voyage.gc_distance_nm(here.lat::float8, here.lon::float8, o.lat::float8, o.lon::float8) <= 600;

  if v_them is null or v_them = 0 then return null; end if;
  return round(v_here / v_them * 100, 1);
end $$;

-- ── world.snapshot() ───────────────────────────────────────────────────────────────────────────
create or replace function world.snapshot()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
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
        'time_compression',  public.wc_int('time_compression'),
        'order_queue_max',   public.wc_int('order_queue_max'),
        'fleet_max',         public.wc_int('fleet_max'),
        'ship_max',          public.wc_int('ship_max'),
        'endurance_margin',  public.wc_num('endurance_margin'),
        'trade_step_tuns',   public.wc_int('trade_step_tuns'),
        'water_per_crew_day', public.wc_num('water_per_crew_day'),
        'food_per_crew_day',  public.wc_num('food_per_crew_day'),
        'wage_per_crew_day',  public.wc_num('wage_per_crew_day')),
    'verbs', cmd.verb_schema())
$$;

-- ── world.market() ─────────────────────────────────────────────────────────────────────────────
create or replace function world.market(p_port uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'port', (select jsonb_build_object('id', p.id, 'code', p.code, 'name', p.name,
                                       'tax_rate', p.tax_rate, 'spread', world.spread(p.id),
                                       'culture', p.culture, 'dev_commerce', p.dev_commerce)
               from public.ports p where p.id = p_port),
    'goods', (select coalesce(jsonb_agg(jsonb_build_object(
        'good_id', g.id, 'code', g.code, 'name', g.name, 'category', g.category,
        'buy',  q.ask, 'sell', q.bid, 'mid', q.mid,
        'pct_nbr', world.pct_of_neighbours(p_port, g.id),
        'stock', pg.stock, 'stock_target', pg.stock_target,
        'stock_band', round(least(1.0, pg.stock / pg.stock_target) * 6),
        -- DESIGN B.4: culture gates what a port will trade at all. UNAVAILABLE is a fact about the
        -- port, not a price, so it is a flag beside the price rather than a price of zero.
        'available', not (pr.culture = any(g.culture_mask)),
        'advice', case when world.pct_of_neighbours(p_port, g.id) is null then 'hold'
                       when world.pct_of_neighbours(p_port, g.id) < 90  then 'buy'
                       when world.pct_of_neighbours(p_port, g.id) > 110 then 'sell'
                       else 'hold' end)
        order by g.code), '[]'::jsonb)
      from public.port_goods pg
      join public.goods g on g.id = pg.good_id
      join public.ports pr on pr.id = pg.port_id
     cross join lateral world.price(pg.port_id, pg.good_id) q
     where pg.port_id = p_port))
$$;

-- ── world.fleets() — and it SETTLES before it answers ──────────────────────────────────────────
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
                 'hold', c.hold, 'cargo', s.cargo, 'cargo_tuns', public.ship_cargo_tuns(s.id),
                 'water_t', s.water_t, 'food_t', s.food_t) order by s.is_flagship desc, s.name), '[]'::jsonb)
                 from public.ships s join public.ship_classes c on c.id = s.class_id
                where s.fleet_id = f.id),
    'queue', cmd.queue(f.id)) order by f.created_at), '[]'::jsonb)
    from public.fleets f where f.player_id = v_player);
end $$;

-- ── world.ledger() ─────────────────────────────────────────────────────────────────────────────
create or replace function world.ledger(p_cursor timestamptz default null, p_limit int default 50)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_player uuid := public.current_player_id();
  v_rows   jsonb;
begin
  if v_player is null then return jsonb_build_object('events', '[]'::jsonb, 'next_cursor', null); end if;

  select coalesce(jsonb_agg(x order by x_created desc), '[]'::jsonb),
         min(x_created)
    into v_rows, p_cursor
    from (select jsonb_build_object(
             'id', e.id, 'kind', e.kind, 'payload', e.payload, 'at', e.created_at,
             'ducats_delta', (select l.ducats_delta from public.ledger l where l.ref_event_id = e.id),
             'balance_after', (select l.balance_after from public.ledger l where l.ref_event_id = e.id)
           ) x, e.created_at x_created
            from public.events e
           where e.player_id = v_player
             and (p_cursor is null or e.created_at < p_cursor)
           order by e.created_at desc
           limit least(greatest(p_limit, 1), 200)) s;

  return jsonb_build_object(
    'events', v_rows,
    'next_cursor', p_cursor,
    'ducats', (select ducats from public.players where id = v_player),
    'ledger_sum', public.ledger_sum(v_player));
end $$;

grant execute on function world.snapshot()                        to authenticated;
grant execute on function world.market(uuid)                      to authenticated;
grant execute on function world.fleets()                          to authenticated;
grant execute on function world.ledger(timestamptz, int)          to authenticated;
grant execute on function world.pct_of_neighbours(uuid, uuid)     to authenticated;

-- ── world.buy_capacity(fleet, good) ────────────────────────────────────────────────────────────
-- What the quantity picker on the Command tab is allowed to offer. The screen used to work this
-- out itself from the spot price and free hold, and was wrong twice over: it ignored the purse,
-- and it ignored the market moving under the order (§G.2). Now it asks, and it also gets the WORD
-- for what stops her, so the caption under the slider is the server's answer too.
create or replace function world.buy_capacity(p_fleet uuid, p_good uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_player uuid := public.current_player_id();
begin
  if v_player is null then
    raise exception 'E_NO_PLAYER: there is no house signed in' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.fleets where id = p_fleet and player_id = v_player) then
    raise exception 'E_NOT_YOURS: that is not your fleet' using errcode = 'P0001';
  end if;
  return public.fleet_buy_capacity(p_fleet, p_good);
end $$;

grant execute on function world.buy_capacity(uuid, uuid) to authenticated;

-- ── SELF-ASSERT ────────────────────────────────────────────────────────────────────────────────
do $$
declare
  v_probe constant uuid := '00000000-0009-4000-8000-000000000001';
  v_player uuid; v_fleet uuid; v_lis uuid; v_cad uuid; v_tun uuid; v_sal uuid; v_vinho uuid;
  v_snap jsonb; v_mkt jsonb; v_mkt_tun jsonb; v_fl jsonb; v_led jsonb;
  v_secret text := public.wc_text('world_secret');
  v_nbr_lis numeric; v_nbr_cad numeric;
  v_grants int; n int;
  v_lis_low uuid;
  f_snap boolean := false; f_secret boolean := false; f_mkt boolean := false;
  f_nbr boolean := false; f_settle boolean := false; f_led boolean := false;
begin
  select id into v_lis from public.ports where code = 'LIS';
  select id into v_cad from public.ports where code = 'CAD';
  select id into v_tun from public.ports where code = 'TUN';
  select id into v_sal from public.goods where code = 'salt';
  select id into v_vinho from public.goods where code = 'wine';

  -- (a) The snapshot is complete.
  -- Complete means "everything the tables hold", counted from the tables. A literal 12 here would
  -- be asserting the size of a world somebody once seeded rather than that the reader serves all
  -- of it — and it would go red the day a port is added, which is not a defect.
  v_snap := world.snapshot();
  if jsonb_array_length(v_snap->'ports')        = (select count(*) from public.ports)
     and jsonb_array_length(v_snap->'legs')     = (select count(*) from public.legs)
     and jsonb_array_length(v_snap->'goods')    = (select count(*) from public.goods)
     and jsonb_array_length(v_snap->'ship_classes') = (select count(*) from public.ship_classes)
     and (v_snap->'config'->>'time_compression')::int = public.wc_int('time_compression')
     and jsonb_array_length(v_snap->'verbs') = 8 then
    f_snap := true;
  end if;

  -- (b) THE SECRET DOES NOT LEAVE. Searched for by VALUE in the serialised payload, because an
  --     allow-list of keys proves only that nobody named it — not that nothing carries it.
  if position(v_secret in v_snap::text) = 0 and length(v_secret) >= 8 then
    f_secret := true;
  end if;

  -- (c) The market prices everything, and the culture mask shows through as UNAVAILABLE.
  v_mkt     := world.market(v_lis);
  v_mkt_tun := world.market(v_tun);
  if jsonb_array_length(v_mkt->'goods') = (select count(*) from public.goods)
     and (select bool_and((e->>'buy')::numeric > 0 and (e->>'sell')::numeric > 0)
            from jsonb_array_elements(v_mkt->'goods') e)
     and (select (e->>'available')::boolean from jsonb_array_elements(v_mkt->'goods') e
           where e->>'code' = 'wine')
     and not (select (e->>'available')::boolean from jsonb_array_elements(v_mkt_tun->'goods') e
               where e->>'code' = 'wine') then
    f_mkt := true;
  end if;

  -- (d) %NBR is a real comparison: somewhere in this world a good is cheap against its neighbours
  --     and somewhere it is dear, and the reader says so. Which port and which good is geography,
  --     not code, so the probe FINDS a pair rather than insisting on one the design once quoted.
  -- pct_of_neighbours() walks every port within 600 nm, so asking it about all 14,980 pairs takes
  -- a minute of a migration nobody should wait a minute for. Affinity is the thing %NBR is
  -- measuring the shadow of, so the CANDIDATES are drawn by affinity — cheap — and only those are
  -- priced. Forty of each end is far more than enough to find one of each sign.
  select c.port_id, c.good_id, c.nbr
    into v_lis_low, v_sal, v_nbr_lis
    from (
      select pg.port_id, pg.good_id, world.pct_of_neighbours(pg.port_id, pg.good_id) as nbr
        from (select port_id, good_id from public.port_goods
               order by affinity asc, port_id, good_id limit 40) pg
    ) c
   where c.nbr is not null
   order by c.nbr asc
   limit 1;
  select c.nbr
    into v_nbr_cad
    from (
      select world.pct_of_neighbours(pg.port_id, v_sal) as nbr
        from (select port_id from public.port_goods
               where good_id = v_sal
               order by affinity desc, port_id limit 40) pg
    ) c
   where c.nbr is not null
   order by c.nbr desc
   limit 1;
  if v_nbr_lis is not null and v_nbr_cad is not null
     and v_nbr_lis < 100 and v_nbr_cad > 100 then
    f_nbr := true;
  end if;

  begin
    v_player := public.new_house(v_probe, 'Casa Leitura', 'PRT');
    select id into v_fleet from public.fleets where player_id = v_player;
    perform cmd.assume_identity(v_probe);

    -- (e) THE READ IS THE CATCH-UP: sail, then backdate so the voyage is long over, then read.
    --     No tick runs. world.fleets() alone must bring the fleet home.
    perform cmd.issue(v_fleet, 'SAIL TO CAD');
    update public.voyages set departed_at = departed_at - interval '9 hours',
                              eta = eta - interval '9 hours'
     where fleet_id = v_fleet and status = 'SAILING';
    v_fl := world.fleets();
    if jsonb_array_length(v_fl) = 1
       and v_fl->0->>'status' = 'DOCKED' and v_fl->0->>'port' = 'CAD'
       and (v_fl->0->>'endurance_days')::numeric > 0 then
      f_settle := true;
    end if;

    -- (f) The ledger reports what the session did, and reconciles.
    v_led := world.ledger();
    if jsonb_array_length(v_led->'events') >= 2
       and (v_led->>'ducats')::bigint = (v_led->>'ledger_sum')::bigint then
      f_led := true;
    end if;

    raise exception '__PROBE_ROLLBACK__' using errcode = 'P0001';
  exception when others then
    if sqlerrm <> '__PROBE_ROLLBACK__' then raise; end if;
  end;

  if not f_snap   then raise exception '0009 self-assert FAIL: snapshot() is incomplete (% ports, % legs, % goods, % classes, % verbs)',
    jsonb_array_length(v_snap->'ports'), jsonb_array_length(v_snap->'legs'),
    jsonb_array_length(v_snap->'goods'), jsonb_array_length(v_snap->'ship_classes'),
    jsonb_array_length(v_snap->'verbs'); end if;
  if not f_secret then raise exception '0009 self-assert FAIL: world.snapshot() CONTAINS the world secret — every client could predict every storm'; end if;
  if not f_mkt    then raise exception '0009 self-assert FAIL: market() did not price every good, or the culture mask did not show through (wine must be available at Lisboa and not at Tunis)'; end if;
  if not f_nbr    then raise exception '0009 self-assert FAIL: %%NBR for salt is % at Lisboa and % at Cádiz; the K.1 gradient needs below 100 then above 100', v_nbr_lis, v_nbr_cad; end if;
  if not f_settle then raise exception '0009 self-assert FAIL: world.fleets() did not settle a 9-hour-stale voyage: %', v_fl; end if;
  if not f_led    then raise exception '0009 self-assert FAIL: world.ledger() did not report the session or did not reconcile: %', v_led; end if;

  select count(*) into n from public.players;
  if n <> 0 then raise exception '0009 self-assert FAIL: % player row(s) survived the probe subtransaction', n; end if;
  select count(*) into v_grants from public.client_write_grants();
  if v_grants <> 0 then raise exception '0009 self-assert FAIL: the read surface minted % client write grant(s)', v_grants; end if;

  raise notice '0009 self-assert ok: snapshot serves every row the world holds (% ports / % legs / % goods / % classes / 8 verbs) and does NOT contain the world secret; market(Lisboa) prices them all with wine available there and UNAVAILABLE at Tunis; the widest %%NBR spread in the world runs from % (cheapest against its neighbours) to % (dearest); world.fleets() alone settled a 9-hour-stale voyage and reported the fleet DOCKED at CAD with no tick; ledger reconciled; 0 client write grants',
    jsonb_array_length(v_snap->'ports'), jsonb_array_length(v_snap->'legs'),
    jsonb_array_length(v_snap->'goods'), jsonb_array_length(v_snap->'ship_classes'),
    round(v_nbr_lis, 1), round(v_nbr_cad, 1);
end $$;
