-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 104 - A MERCHANT CARRIES ONLY WHAT THE CITY'S PURSE CAN PAY FOR  (migration 0410; docs/dev-log/2026-11-14-under-water.md)
--
--   On the world's own merchants, rolled back with proof.mjs's transaction; every plan below is also rolled back alone, so each merchant is planned
--   from the same state every time. The economy is closed and the purses lit, so the sale door judges a sale by the city's purse. No price and no
--   choice of the planner is asserted: each merchant's own numbers set her test. `due` of a stop is what the next harbour's purse would pay for
--   the BUY lines she wrote there, by the door's own measure (round(world.quote's sale total / haul), haul 1 while the economy is closed), and a
--   stop is `over` when that is more than the harbour's live purse (public.treasury_balance).
--
-- @pass CP_RICH    with every purse rich the probe merchants are planned, some write BUY lines (the proof is not vacuous) and no stop is over
-- @pass CP_SHORT   with every city's purse set to half of what her dearest stop's sale would take from it, no merchant writes a stop that is over: each carries less, wrote another loop or waits in port
-- @pass CP_EMPTY   with every city's rolled purse at nothing no merchant writes a stop that is over
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
create function pg_temp.plan_104(p_route uuid, p_purse bigint) returns jsonb language plpgsql as $f$
-- she is planned alone at her lap start with every city's rolled purse at p_purse; answers what she wrote and what its sales ask of the purses
declare
  v_r jsonb;
  v_n int;
begin
  update public.port_treasury set ducats = p_purse;
  v_r := public.npc_plan(now(), p_route);
  select count(*) into v_n from public.standing_route_stops s where s.route_id = p_route;
  return (
    with z as (
      select s2.port_id,
             sum(round((select q.total from world.quote(s2.port_id, l.good_id, l.qty, 'sell', null, null) q)
                       / case when public.economy_closed() then 1 else public.cargo_haul(s2.port_id, l.good_id) end)) as due,
             sum(l.qty) as qty
        from public.standing_route_lines l
        join public.standing_route_stops s2 on s2.route_id = l.route_id and s2.ord = (l.stop_ord + 1) % v_n
       where l.route_id = p_route and l.kind = 'BUY'
       group by l.stop_ord, s2.port_id)
    select jsonb_build_object(
      'planned', v_r->'planned', 'waiting', v_r->'waiting', 'failed', v_r->'failed',
      'paused', (select sr.paused_reason from public.standing_routes sr where sr.id = p_route),
      'buys', (select count(*) from public.standing_route_lines x where x.route_id = p_route and x.kind = 'BUY'),
      'loop', (select string_agg(p.code, '-' order by st.ord) from public.standing_route_stops st join public.ports p on p.id = st.port_id where st.route_id = p_route),
      'over', (select count(*) from z where z.due > greatest(public.treasury_balance(z.port_id), 0)),
      'max_due', (select coalesce(max(z.due), 0) from z),
      'qty', (select coalesce(sum(z.qty), 0) from z)));
end $f$;

do $p$
declare
  r        record;
  v        jsonb;
  v0       jsonb;
  v_buying int := 0;
  v_less   int := 0;
  v_other  int := 0;
  v_wait   int := 0;
  v_empty  int := 0;
begin
  -- ── THE SCENE: closed, the purses lit, the merchants lit, every one on her route where she lies ──
  update public.world_config set value = 'true'::jsonb where key in ('npc_traders_enabled', 'standing_routes_enabled', 'economy_closed', 'city_treasury_enabled');
  if not public.npc_traders_on() or not public.economy_closed() or not public.city_treasury_on() then
    raise exception 'proof 104: the closed economy, the purses or the merchants cannot be lit in this world';
  end if;
  if exists (select 1 from public.ports p where not exists (select 1 from public.port_treasury t where t.port_id = p.id)) then
    insert into public.port_treasury (port_id) select p.id from public.ports p where not exists (select 1 from public.port_treasury t where t.port_id = p.id);
  end if;
  update public.standing_routes sr set fleet_id = nf.fleet_id, lap_id = null, paused_reason = null, hold_until = null
    from public.npc_fleets nf where nf.route_id = sr.id;
  create temp table cp104 on commit drop as
  select nf.fleet_id, nf.route_id, nf.player_id, row_number() over (order by nf.roster_ord) as i
    from public.npc_fleets nf
    join public.players pl on pl.id = nf.player_id and not public.pirate_power(pl.nation_id)
    join public.fleets f on f.id = nf.fleet_id and f.status = 'DOCKED'
    join public.standing_routes sr on sr.id = nf.route_id
    join public.standing_route_stops s on s.route_id = sr.id and s.ord = 0 and s.port_id = f.port_id
   where nf.roster_ord <= public.wc_int('npc_fleet_max')
     and not exists (select 1 from public.orders o where o.fleet_id = nf.fleet_id and o.status in ('pending', 'failed'))
     and not exists (select 1 from public.ships sh where sh.fleet_id = nf.fleet_id and public.ship_cargo_tuns(sh.id) > 0)
   order by nf.roster_ord limit 6;
  if (select count(*) from cp104) < 6 then
    raise exception 'proof 104: only % merchants lie in port at their first stop with an empty hold; 6 are wanted', (select count(*) from cp104);
  end if;

  for r in select * from cp104 order by i loop
    -- every purse rich
    begin
      v0 := pg_temp.plan_104(r.route_id, 1000000000000);
      raise exception sqlstate 'CP104';
    exception when sqlstate 'CP104' then null;
    end;
    if (v0->>'planned')::int <> 1 or (v0->>'failed')::int <> 0 then raise exception 'proof 104: merchant % was not planned: %', r.i, v0; end if;
    if (v0->>'over')::int <> 0 then raise exception 'CP_RICH: with every purse rich merchant % wrote a stop its harbour cannot pay for: %', r.i, v0; end if;

    -- every rolled purse at nothing
    begin
      v := pg_temp.plan_104(r.route_id, 0);
      raise exception sqlstate 'CP104';
    exception when sqlstate 'CP104' then null;
    end;
    if (v->>'planned')::int <> 1 or (v->>'failed')::int <> 0 then raise exception 'proof 104: merchant % was not planned with the purses at nothing: %', r.i, v; end if;
    if (v->>'over')::int <> 0 then raise exception 'CP_EMPTY: with every purse at nothing merchant % wrote a stop its harbour cannot pay for: %', r.i, v; end if;
    v_empty := v_empty + 1;

    -- her own threshold: half of what her dearest stop's sale takes from a purse
    continue when (v0->>'buys')::int = 0 or (v0->>'max_due')::numeric < 200;
    v_buying := v_buying + 1;
    begin
      v := pg_temp.plan_104(r.route_id, floor((v0->>'max_due')::numeric / 2)::bigint);
      raise exception sqlstate 'CP104';
    exception when sqlstate 'CP104' then null;
    end;
    if (v->>'planned')::int <> 1 or (v->>'failed')::int <> 0 then raise exception 'proof 104: merchant % was not planned with short purses: %', r.i, v; end if;
    if (v->>'over')::int <> 0 then
      raise exception 'CP_SHORT: merchant %''s dearest stop takes % from a purse; with every purse at half of that she wrote a stop its harbour cannot pay for: %', r.i, v0->>'max_due', v;
    end if;
    if v->>'paused' = 'laid_up' or (v->>'buys')::int = 0 then v_wait := v_wait + 1;
    elsif v->>'loop' is distinct from v0->>'loop' then v_other := v_other + 1;
    else v_less := v_less + 1;
    end if;
  end loop;

  if v_buying < 2 then
    raise exception 'CP_RICH: only % of the 6 probe merchants write a BUY with every purse rich: the proof would be vacuous', v_buying;
  end if;
  raise notice 'PASS: CP_RICH with every purse rich all 6 merchants are planned, % write BUY lines and no stop is past its harbour''s purse', v_buying;
  raise notice 'PASS: CP_SHORT with every purse at half of what her dearest stop takes, none of % writes a stop past its harbour''s purse: % kept her loop with what the purse covers, % wrote another loop, % wait in port or sail without a BUY', v_buying, v_less, v_other, v_wait;
  raise notice 'PASS: CP_EMPTY with every rolled purse at nothing none of % merchants writes a stop past its harbour''s purse', v_empty;
end $p$;
