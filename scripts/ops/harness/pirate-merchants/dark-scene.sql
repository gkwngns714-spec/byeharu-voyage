-- 0340 PARITY SCENE: run by proof-0340.mjs on the world BEFORE the file and AFTER it, rolled back each time, with pirates_bite FALSE (as shipped). It names only what existed before 0340 and reads everything the
-- pirate merchants must NOT change while dark: the loops offered to the merchants whose homes touch a pirate home, the day cap at a pirate home and at a crown city, the gift roster, the invest roster, a crown
-- founding and the capital that pays it, the sea roster's inks and kinds, the flow words the client reads, and W. Every SCENE line must be equal, byte for byte, before and after.
-- (The pirate merchants' own changes, lit, are proved by scripts/db/proofs/47_pirate_merchants.sql; this scene is the other half of "a slice that cannot hurt a live world".)
do $$
declare
  v_prt  uuid := (select n.id from public.nations n where n.code = 'PRT');
  v_por  uuid := (select p.id from public.ports p where p.code = 'POR');
  v_lis  uuid := (select p.id from public.ports p where p.code = 'LIS');
  v_dje  uuid := (select p.id from public.ports p where p.code = 'DJE');
  v_a    uuid;
  v_m    uuid;
  v_txt  text;
  v_good uuid;
  v_uid  constant uuid := '00000000-0340-4000-8000-000000000001';
  v_voy  uuid;
begin
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'influence_enabled', 'economy_closed', 'npc_traders_enabled', 'standing_routes_enabled');
  -- a world with money in it, so a founding has a payer and "W unchanged" is measured on something
  update public.port_treasury t set ducats = 1000000 + abs(hashtext(p.code)) % 5000000 from public.ports p where p.id = t.port_id;
  insert into public.players (company_name, nation_id, ducats, is_npc) values ('Casa Cena 0340', v_prt, 5000000, false) returning id into v_a;
  update public.players set auth_uid = v_uid where id = v_a;
  select g.id into v_good from public.port_goods pg join public.goods g on g.id = pg.good_id where pg.port_id = v_por and pg.stock_target > 0 order by g.code limit 1;

  -- the loops offered to every merchant whose home has a known leg to a pirate home (the planner, dark: a pirate home is a destination like any)
  select md5(string_agg(x.line, ';' order by x.line)) into v_txt
    from (select h.roster_ord || ':' || coalesce((select string_agg(c.kind || '=' || (select string_agg(s->>'code', '>' order by o) from jsonb_array_elements(c.stops) with ordinality t(s, o)), ',' order by c.kind, c.stops::text)
                                                    from public.npc_loop_candidates(nf.route_id, nf.fleet_id, h.home_port_id, public.fleet_free_hold(nf.fleet_id), greatest(coalesce(voyage.fleet_speed_at(nf.fleet_id, 1), 0), 0.1)) c), '-') as line
            from public.npc_houses h join public.npc_fleets nf on nf.player_id = h.player_id
           where exists (select 1 from public.npc_known_legs(h.home_port_id) l join public.port_allegiance a on a.port_id = l.to_port join public.great_powers g on g.nation_id = a.nation_id where a.home and g.pirate)) x;
  raise notice 'SCENE: LOOPS %', v_txt;
  -- the day cap of a company at a pirate home, at a crown city, and at a second home
  raise notice 'SCENE: DAY_CAP % % %', world.daily_cap_remaining(v_a, v_por, v_good), world.daily_cap_remaining(v_a, v_lis, v_good), world.daily_cap_remaining(v_a, v_dje, v_good);
  -- the gift roster and the invest roster
  raise notice 'SCENE: ROSTERS % %', (select md5(coalesce(string_agg(g.player_id::text, ',' order by g.player_id), '')) from public.capital_gift_roster(now()) g),
    (select md5(coalesce(string_agg(r.player_id::text, ',' order by r.player_id), '')) from public.npc_invest_roster() r);
  -- a crown company founded closed: paid by Lisbon, as 0234 says (the founding path dark)
  v_m := public.new_house(null, 'Casa Fundada 0340', 'PRT', 'LIS', 'Fundada', 'barca', 'Fundada', 40000, false);
  raise notice 'SCENE: FOUNDING % % %', (select pl.ducats from public.players pl where pl.id = v_m),
    (select coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.port_id = v_lis and f.player_id = v_m),
    (select string_agg(l.kind || ':' || l.ducats_delta, ',' order by l.id) from public.ledger l where l.player_id = v_m);
  -- the sea's houses: every ink and kind served
  raise notice 'SCENE: SEA_HOUSES %', (select md5(string_agg(h.player_id::text || ':' || h.ink || ':' || coalesce(h.kind, '-'), ',' order by h.player_id) ) from public.sea_houses() h);
  -- the flow words the client reads (the kinds that existed: a new one at the end is this file's by design, so only the old rows are compared)
  raise notice 'SCENE: WORDS %', (select md5(string_agg(w.kind || ':' || w.side || ':' || w.word || ':' || w.ord, ',' order by w.ord)) from public.stats_flow_words w where w.kind <> 'PIRATE_FOUND');
  -- the money
  raise notice 'SCENE: W %', (select coalesce(sum(public.treasury_balance(t.port_id)), 0) from public.port_treasury t) + (select coalesce(sum(p.ducats), 0) from public.players p) + public.funds_aboard();
  -- the insurer's answer for a merchant's voyage at sea, if any sails in this world (the quote path dark); and the hunk-bearing readers' answers for a crown merchant
  select v.id into v_voy from public.voyages v join public.players p on p.id = v.player_id and p.is_npc where v.status = 'SAILING' order by v.departed_at limit 1;
  raise notice 'SCENE: INSURE %', case when v_voy is null then 'no merchant at sea' else (public.insure_voyage(v_voy, false))::text end;
end $$;
