-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 203 - CARGO AT COST  (migration 0501; docs/dev-log/2026-11-25-cargo-at-cost.md)
--
--   The lead, 2026-11-25: HQ's per hour reads a cargo BUY as a running loss until it is sold (Trading -38,869 with the cargo at
--   sea). This proof plays a company through the real doors: she buys at Lisbon (cmd.do_buy), sells part (cmd.do_sell), sails, and
--   runs dry so the real settle forces her home and her hold is lost (voyage.settle -> voyage.forced_home -> voyage.lose_hold).
--   Rolled back by proof.mjs.
--
-- @pass CC_DARK    dark, after a real buy: the rate is 0493's (the trade line is the ledger's, the buy a loss) and has no `cargo`
-- @pass CC_HELD    lit, bought and all of it still aboard: the trade line is 0, cargo.at_cost is what she paid = her cargo at cost
-- @pass CC_SALE    lit, part sold through cmd.do_sell: the trade line is the SOLD event's own `profit` (sale less its recorded cost),
--                  and cargo.at_cost is what is still aboard at cost
-- @pass CC_LOSS    she runs dry: the real settle writes the FORCED_HOME day with cargo_lost_cost = her cargo at cost before the loss;
--                  lit, that is the `cargo_lost` running line and cargo.at_cost is 0
-- @pass CC_SUMS    at every step lit: the running lines sum to net_24h, all_24h is her ledger's sum, and
--                  net_24h + one_time_24h + cargo.net_24h = all_24h
-- @pass CC_BODIES  voyage.settle's and voyage.navy_meets' payloads carry the key from the news' own expression; voyage.lose_hold,
--                  voyage.raid_takes and public.fleet_unload do not name it (the loss itself is not touched)
-- @pass CC_COST    what the record adds to a day that loses cargo: public.fleet_stock_at_cost, timed over 200 reads
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════

create function pg_temp.sums_203(p_r jsonb, p_player uuid) returns text language sql as $f$
  -- null when the three sums hold for a lit rate; else which one does not
  select case
    when (select coalesce(sum((e->>'total_24h')::numeric), 0) from jsonb_array_elements(p_r->'lines') e where not (e->>'one_time')::boolean)
         <> (p_r->>'net_24h')::numeric then 'the running lines do not sum to net_24h'
    when (p_r->>'all_24h')::numeric <> (select coalesce(sum(l.ducats_delta), 0) from public.ledger l
                                         where l.player_id = p_player and l.created_at > now() - interval '24 hours'
                                           and l.kind <> 'FOUNDING' and left(l.kind, 6) <> 'PROBE_') then 'all_24h is not the ledger''s sum'
    when (p_r->>'net_24h')::numeric + (p_r->>'one_time_24h')::numeric + (p_r #>> '{cargo,net_24h}')::numeric <> (p_r->>'all_24h')::numeric
      then 'net_24h + one_time_24h + cargo.net_24h is not all_24h'
    when (p_r #>> '{cargo,at_cost}')::numeric <> greatest(0, -(p_r #>> '{cargo,net_24h}')::numeric) then 'cargo.at_cost is not the reconciling figure floored at 0'
  end
$f$;

do $p$
declare
  c_a    constant uuid := '00000000-0501-4000-8000-0000000000a1';
  v_lis  uuid := (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR');
  v_a    uuid;
  v_fl   uuid;
  v_g    record;
  v_r    jsonb;
  v_ev   jsonb;
  v_buy  numeric;
  v_held numeric;
  v_voy  uuid;
  v_day  jsonb;
  v_t    timestamptz;
  v_ms   numeric;
  v_bad  text;
  i      int;
begin
  v_a := public.new_house(c_a, 'Casa da Carga A 203', 'PRT');
  select f.id into v_fl from public.fleets f where f.player_id = v_a limit 1;
  -- a good Lisbon sells ten of and bids for (the chain's own market: this proof runs on the chain's world, never on production)
  select g.id, g.code, g.name into v_g
    from public.goods g
   cross join lateral world.quote(v_lis, g.id, 10, 'buy', null, v_fl) qb
   cross join lateral world.quote(v_lis, g.id, 4, 'sell', null, v_fl) qs
   where public.port_offers(v_lis, g.id) and qb.units = 10 and qs.units = 4 and qb.total between 100 and 20000
   order by g.code limit 1;
  if v_g.id is null then
    raise exception 'PROOF 203 FAILED: Lisbon sells no good the scene can buy ten of';
  end if;
  perform cmd.do_buy(v_fl, jsonb_build_object('good', v_g.id::text, 'qty', 10));
  select -sum(l.ducats_delta) into v_buy from public.ledger l where l.player_id = v_a and l.kind = 'BUY';
  v_held := public.fleet_stock_at_cost(v_fl);
  if coalesce(v_buy, 0) <= 0 or abs(v_held - v_buy) > 1 then
    raise exception 'PROOF 203 FAILED: the buy wrote % and her cargo at cost is %', v_buy, v_held;
  end if;

  -- ── CC_DARK ──
  v_r := public.company_rate_for(v_a);
  if v_r ? 'cargo' or (select (e->>'total_24h')::numeric from jsonb_array_elements(v_r->'lines') e where e->>'line' = 'trade') <> -v_buy
     or exists (select 1 from jsonb_array_elements(v_r->'lines') e where e->>'line' = 'cargo_lost') then
    raise exception 'PROOF 203 FAILED: dark, the rate is not 0493''s: %', v_r;
  end if;
  raise notice 'PASS: CC_DARK - dark, % x10 bought for %: the trade line is -% (the buy a loss, as 0493 reads it), no cargo key', v_g.code, v_buy, v_buy;

  -- ── CC_HELD ──
  update public.world_config set value = 'true'::jsonb where key = 'cargo_at_cost_enabled';
  v_r := public.company_rate_for(v_a);
  v_bad := pg_temp.sums_203(v_r, v_a);
  if v_bad is not null or (select (e->>'total_24h')::numeric from jsonb_array_elements(v_r->'lines') e where e->>'line' = 'trade') <> 0
     or (v_r #>> '{cargo,at_cost}')::numeric <> v_buy or (v_r #>> '{cargo,bought}')::numeric <> v_buy
     or (v_r #>> '{cargo,cost_sold}')::numeric <> 0 or (v_r #>> '{cargo,lost}')::numeric <> 0 then
    raise exception 'PROOF 203 FAILED: lit, the held cargo is not served at cost (%): %', v_bad, v_r;
  end if;
  raise notice 'PASS: CC_HELD - lit, all ten still aboard: the trade line is 0, cargo.at_cost % = what she paid = her cargo at cost %', v_r #>> '{cargo,at_cost}', v_held;

  -- ── CC_SALE ──
  perform cmd.do_sell(v_fl, jsonb_build_object('good', v_g.id, 'qty', 4));
  select e.payload into v_ev from public.events e where e.player_id = v_a and e.kind = 'SOLD' order by e.created_at desc limit 1;
  v_held := public.fleet_stock_at_cost(v_fl);
  v_r := public.company_rate_for(v_a);
  v_bad := pg_temp.sums_203(v_r, v_a);
  if v_bad is not null or v_ev is null or (v_ev->>'cost') is null
     or (select (e->>'total_24h')::numeric from jsonb_array_elements(v_r->'lines') e where e->>'line' = 'trade') <> (v_ev->>'profit')::numeric
     or (v_r #>> '{cargo,cost_sold}')::numeric <> (v_ev->>'cost')::numeric
     or (v_r #>> '{cargo,at_cost}')::numeric <> v_buy - (v_ev->>'cost')::numeric
     or abs((v_r #>> '{cargo,at_cost}')::numeric - v_held) > 1 then
    raise exception 'PROOF 203 FAILED: lit, after the sale the trade line is not the sale''s own profit, or the cargo is not what is aboard (%): % / event % / aboard %', v_bad, v_r, v_ev, v_held;
  end if;
  raise notice 'PASS: CC_SALE - four sold for % (recorded cost %): the trade line is % = the SOLD event''s profit; cargo.at_cost % (aboard at cost: %)',
    v_ev->>'total', v_ev->>'cost', v_ev->>'profit', v_r #>> '{cargo,at_cost}', v_held;

  -- ── CC_COST (her six units aboard) ──
  v_t := clock_timestamp();
  for i in 1 .. 200 loop
    perform public.fleet_stock_at_cost(v_fl);
  end loop;
  v_ms := round(extract(epoch from clock_timestamp() - v_t) * 1000 / 200, 3);

  -- ── CC_LOSS: she sails with no water and no food; the day ends; the real settle forces her home and the hold is lost ──
  update public.ships s set durability = (select b.durability from public.ship_base(s.id) b), crew = 20, water_t = 0, food_t = 0 where s.fleet_id = v_fl;
  update public.fleets f set status = 'DOCKED', port_id = v_lis, lat = null, lon = null, busy_until = null, ready_at = null, version = f.version + 1 where f.id = v_fl;
  v_t := now() - make_interval(secs => (100.0 / 90 * 86400 / public.wc_num('time_compression'))::double precision);   -- ten ninths of a voyage-day ago (proof 66's clock)
  v_voy := voyage.depart(v_fl, (select jsonb_agg(jsonb_build_object('a', jsonb_build_array(38.5, -9.6 - (d - 1)), 'b', jsonb_build_array(38.5, -9.6 - d),
                                                                     'nm', voyage.fleet_speed(v_fl) * 24,
                                                                     'sea_id', (select p.sea_id from public.ports p where p.id = v_lis)) order by d)
                                  from generate_series(1, 3) d), v_lis, v_lis, v_t);
  perform voyage.settle(v_fl, now());
  select ve.payload into v_day from public.voyage_events ve where ve.voyage_id = v_voy and ve.kind = 'FORCED_HOME';
  if v_day is null or (v_day->>'cargo_lost_cost')::numeric is distinct from v_held or public.fleet_stock_at_cost(v_fl) <> 0
     or (v_day->'cargo_lost'->>v_g.code)::numeric is distinct from 6 then
    raise exception 'PROOF 203 FAILED: the settle did not force her home with the cost of her hold (% aboard at cost): day %, kinds %', v_held, v_day,
      (select jsonb_agg(jsonb_build_array(ve.day_index, ve.kind)) from public.voyage_events ve where ve.voyage_id = v_voy);
  end if;
  v_r := public.company_rate_for(v_a);
  v_bad := pg_temp.sums_203(v_r, v_a);
  if v_bad is not null
     or (select jsonb_build_array((e->>'total_24h')::numeric, (e->>'count')::int, (e->>'one_time')::boolean) from jsonb_array_elements(v_r->'lines') e where e->>'line' = 'cargo_lost')
          is distinct from jsonb_build_array(-v_held, 1, false)
     or (v_r #>> '{cargo,lost}')::numeric <> v_held or (v_r #>> '{cargo,at_cost}')::numeric <> 0
     or (select (e->>'total_24h')::numeric from jsonb_array_elements(v_r->'lines') e where e->>'line' = 'trade') <> (v_ev->>'profit')::numeric then
    raise exception 'PROOF 203 FAILED: lit, the lost hold is not a running loss at its cost (%): %', v_bad, v_r;
  end if;
  raise notice 'PASS: CC_LOSS - ran dry: the real settle wrote FORCED_HOME with cargo_lost % and cargo_lost_cost % (her hold at cost); lit: the cargo_lost line is -%, cargo.at_cost 0, the trade line still %',
    v_day->'cargo_lost', v_day->>'cargo_lost_cost', v_held, v_ev->>'profit';
  raise notice 'PASS: CC_SUMS - held, sold and lost, each lit: the running lines sum to net_24h (%), all_24h (%) is the ledger''s sum, and net + one time + cargo.net_24h (%) = all', v_r->>'net_24h', v_r->>'all_24h', v_r #>> '{cargo,net_24h}';

  -- ── CC_BODIES ──
  if position('''cargo_lost_cost'', v_hold0 - public.fleet_stock_at_cost(p_fleet)' in pg_get_functiondef('voyage.settle(uuid,timestamp with time zone)'::regprocedure)) = 0
     or position('v_hold0 := public.fleet_stock_at_cost(p_fleet);' in pg_get_functiondef('voyage.settle(uuid,timestamp with time zone)'::regprocedure)) = 0
     or position('else v_cost0 - public.fleet_stock_at_cost(p_fleet) end' in pg_get_functiondef('voyage.settle(uuid,timestamp with time zone)'::regprocedure)) = 0
     or position('''cargo_lost_cost'', v_cost0 - public.fleet_stock_at_cost(p_fleet)' in pg_get_functiondef('voyage.navy_meets(uuid,integer,uuid,uuid,timestamp with time zone)'::regprocedure)) = 0
     or exists (select 1 from pg_proc p where p.oid in ('voyage.lose_hold(uuid)'::regprocedure, 'voyage.raid_takes(uuid,integer,uuid,text)'::regprocedure,
                                                         'public.fleet_unload(uuid,text,numeric)'::regprocedure)
                   and (p.prosrc like '%cargo_lost_cost%' or p.prosrc like '%0501%')) then
    raise exception 'PROOF 203 FAILED: the raid''s payload does not carry the news'' own figure, or a loss function was touched';
  end if;
  raise notice 'PASS: CC_BODIES - voyage.settle and voyage.navy_meets write cargo_lost_cost = her cargo at cost before the raid less after (the news'' expression, 0362); lose_hold, raid_takes and fleet_unload do not name it';
  raise notice 'PASS: CC_COST - the record adds public.fleet_stock_at_cost to a day that loses cargo: % ms a read (200 reads, six units aboard); two reads on such a day, none on any other', v_ms;
end $p$;
