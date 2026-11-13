-- volume-scene.sql — HOW MUCH NEWS THE MERCHANTS OF THE LOCAL WORLD WOULD MAKE: a LOCAL SCENE (it writes; proof-0362.mjs --volume runs it after the file and rolls it back).
-- The merchants of the local world trade through the real jobs, as proof 12 drives them: twelve beats, in each every merchant at sea arrives now and every rested merchant is due,
-- then the real arrivals beat (public.tick_arrivals) and the real lap-start pass (public.tick_lap_starts) run: her sales and buys go through cmd.do_sell and cmd.do_buy. The sea
-- is quiet (hazards off) so the count is of trades, not of luck. Printed: how many trades the merchants made, what they came to, how many reached news_big_trade, how many hours of sailing that was
-- (a real hour is a real hour: voyages.eta - departed_at), and what the cap let through. The local world is the chain's seed (purses, stocks and loops as migrations left them),
-- not prod's: the figures say how the knob sits against the merchants' trades, and the cap is what bounds prod whatever they are.
-- LOCAL PGlite WORLD ONLY (scripts/ops/harness/README.md): it writes. The first statement refuses a real server (inet_server_addr() is not null there, null on PGlite).
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;

do $v$
declare
  v_t0     timestamptz := clock_timestamp();
  v_mark   bigint := coalesce((select max(w.id) from public.world_news w), 0);
  v_start  timestamptz := now();
  r        record;
  v_fail   int := 0;
  v_done   int := 0;
  v_round  int;
  v_err    text;
  v_stat   record;
  v_hours  numeric;
  v_fleets int;
begin
  -- proof 12's own preconditions: a quiet sea, routes on, no lap rationing, the market pinned (scripts/db/market-fixture.mjs), and A SAMPLE of the roster started through the
  -- world's own lever (npc_fleet_max): the whole roster of 837 is the deploy's soak, not a local scene's (proof 12 says why)
  update public.world_config set value = to_jsonb(0.0) where key = 'hazard_p_max';
  update public.world_config set value = 'true'::jsonb where key = 'standing_routes_enabled';
  update public.world_config set value = to_jsonb(0) where key = 'npc_laps_per_game_day';
  perform proof.pin_market('00000000-0362-4000-8000-0000000000dd'::uuid, 'scene-0362-fixture', 's362u1:', 's362u2:');
  update public.world_config set value = to_jsonb(60) where key = 'npc_fleet_max';
  perform public.npc_traders_switch(true);
  select count(*) into v_fleets from public.standing_routes sr join public.players p on p.id = sr.player_id and p.is_npc where sr.fleet_id is not null;
  create temp table legs_v (voyage_id uuid primary key, hours numeric) on commit drop;
  for v_round in 1 .. 12 loop
    -- a leg's real length is kept before it is cut short: voyages.eta - departed_at, as the merchant would have sailed it
    insert into legs_v (voyage_id, hours)
    select o.id, extract(epoch from o.eta - o.departed_at) / 3600
      from public.voyages o join public.npc_fleets nf on nf.fleet_id = o.fleet_id where o.status = 'SAILING'
    on conflict (voyage_id) do nothing;
    -- proof 12's own beat: every merchant at sea arrives now, every rested merchant is due, the arrivals beat and the lap-start pass run (in this transaction)
    update public.voyages v set departed_at = v.departed_at - (v.eta - now()) - interval '1 minute', eta = now() - interval '1 minute'
      from public.fleets f join public.players p on p.id = f.player_id and p.is_npc
     where v.fleet_id = f.id and v.status = 'SAILING';
    update public.standing_routes sr set hold_until = now() - interval '1 second'
      from public.players p where p.id = sr.player_id and p.is_npc and sr.hold_until is not null;
    perform public.tick_arrivals(now());
    call public.tick_lap_starts(false);
    v_done := v_done + 1;
    exit when clock_timestamp() - v_t0 > interval '200 seconds';
  end loop;

  select count(*) as n, count(*) filter (where e.kind = 'SOLD') as sold, count(*) filter (where e.kind = 'BOUGHT') as bought,
         coalesce(percentile_cont(0.5) within group (order by (e.payload->>'total')::numeric), 0) as p50,
         coalesce(percentile_cont(0.9) within group (order by (e.payload->>'total')::numeric), 0) as p90,
         coalesce(percentile_cont(0.99) within group (order by (e.payload->>'total')::numeric), 0) as p99,
         coalesce(max((e.payload->>'total')::numeric), 0) as top,
         count(*) filter (where e.kind = 'SOLD' and (e.payload->>'total')::numeric >= public.wc_num('news_big_trade')) as big_sold,
         count(*) filter (where e.kind = 'BOUGHT' and (e.payload->>'total')::numeric >= public.wc_num('news_big_trade')) as big_bought,
         count(*) filter (where (e.payload->>'total')::numeric >= 100000) as over_100k,
         count(*) filter (where (e.payload->>'total')::numeric >= 50000) as over_50k
    into v_stat
    from public.events e join public.players p on p.id = e.player_id
   where p.is_npc and e.kind in ('SOLD', 'BOUGHT') and e.created_at >= v_start;
  select coalesce(sum(l.hours), 0) into v_hours from legs_v l join public.voyages o on o.id = l.voyage_id where o.status = 'ARRIVED';
  raise notice 'VOLUME the local world: % merchant fleets started (a sample of the roster), % beats run (% failed%), % merchant trades (% sold, % bought); totals p50 %, p90 %, p99 %, the largest %',
    v_fleets, v_done, v_fail, case when v_err is null then '' else ', the last: ' || left(v_err, 120) end, v_stat.n, v_stat.sold, v_stat.bought,
    round(v_stat.p50::numeric), round(v_stat.p90::numeric), round(v_stat.p99::numeric), round(v_stat.top);
  raise notice 'VOLUME at news_big_trade %: % sales and % buys reach it (of % trades); at 100,000 % would; at 50,000 % would',
    public.wc_num('news_big_trade'), v_stat.big_sold, v_stat.big_bought, v_stat.n, v_stat.over_100k, v_stat.over_50k;
  raise notice 'VOLUME those trades took % fleet-hours of sailing (% arrived voyages): with % fleets always at sea (no rest in port counted: an upper bound) that is one real hour every % trades, so at most about % big trade(s) a real hour before the cap',
    round(v_hours, 1), (select count(*) from legs_v l join public.voyages o on o.id = l.voyage_id where o.status = 'ARRIVED'),
    v_fleets, case when v_hours > 0 then round(v_stat.n / v_hours * v_fleets) else null end,
    case when v_hours > 0 then round((v_stat.big_sold + v_stat.big_bought) / v_hours * v_fleets, 2) else null end;
  raise notice 'VOLUME told in this scene (all of it inside one real hour, so the cap of % a kind binds): %; % ms',
    public.wc_int('news_merchant_hour'),
    coalesce((select string_agg(x.kind || ' ' || x.n, ', ' order by x.kind) from (select w.kind, count(*) as n from public.world_news w where w.id > v_mark group by w.kind) x), 'nothing'),
    round(extract(epoch from clock_timestamp() - v_t0) * 1000);
end
$v$;
