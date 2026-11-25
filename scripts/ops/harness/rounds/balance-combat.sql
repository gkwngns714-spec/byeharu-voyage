-- THE ROUNDS' BALANCE (local only, never production: lights switches and refills fleets). Combat: gold, wrecks, repair, crew and stores, ammo an hour, by class, ships and sea strength.
create temp table bal(kind text, fleet text, sea numeric, ships int, rounds numeric, mins numeric, gold numeric, costs numeric, salv numeric, hull numeric, rep numeric, sto numeric, amm numeric, crew numeric, why text);
do $$
declare v_pl uuid; f uuid; v_sea uuid; c record; n int; d numeric; i int; r record; g0 numeric; g1 numeric; k int; v_ship uuid; t jsonb; rep int; sv numeric; am numeric; crewc numeric; gold numeric; mins numeric; rounds numeric; hull numeric; whys text; rc numeric; sc numeric; done int;
begin
 update public.world_config set value='true' where key in ('rounds_enabled','combat_rounds_enabled','expedition_rounds_enabled','wrecks_yield_enabled','artifacts_enabled','city_treasury_enabled','reputation_on','ship_stores_separate','ammo_enabled','level_perks_on');
 update public.world_config set value='1' where key='pirate_spend_day_pct';
 update public.world_config set value='100000000' where key='loot_per_company_day';
 insert into public.port_treasury (port_id, ducats) select p.id, 500000000 from public.ports p where p.kind='HARBOUR' on conflict (port_id) do update set ducats=500000000;
 update public.port_goods pg set stock=100000 from public.goods g where g.id=pg.good_id and public.pirate_home(pg.port_id) and g.code in ('planks','timber','cordage','canvas-duck','iron','tar');
 v_pl := public.new_house('00000000-0534-4000-8000-0000000000b1','Balanco','PRT');
 select x.id, h.sea_id into f, v_sea from public.fleets x join public.ports h on h.id=x.port_id where x.player_id=v_pl;
 update public.players set ducats=1000000000 where id=v_pl;
 delete from public.sea_pressure where sea_id=v_sea;
 alter table public.ships disable trigger user;
 for c in select * from public.ship_classes where code in ('xebec','nau','galleon','galeao','sanmartin') order by attack loop
 foreach n in array array[1,3] loop
  delete from public.ships where fleet_id=f and not is_flagship;
  select id into v_ship from public.ships where fleet_id=f limit 1;
  update public.ships set class_id=c.id where id=v_ship;
  for k in 2..n loop insert into public.ships select (jsonb_populate_record(null::public.ships, to_jsonb(s)||jsonb_build_object('id',gen_random_uuid(),'name','Nau '||k,'is_flagship',false))).* from public.ships s where s.id=v_ship; end loop;
  foreach d in array array[0.05,0.1,0.2,0.4,0.8] loop
   update public.seas set piracy_index=d where id=v_sea;
   gold:=0; mins:=0; rounds:=0; hull:=0; whys:=''; sv:=0; rc:=0; sc:=0; am:=0; done:=0;
   for rep in 1..4 loop
    update public.ships s set crew=(select sb.crew_max from public.ship_base(s.id) sb), durability=(select sb.durability from public.ship_base(s.id) sb), food_t=500, water_t=500, cargo='{}', cargo_basis='{}' where s.fleet_id=f;
    perform public.fleet_load(f,'gunpowder',20,1); perform public.fleet_load(f,'shot-and-ball',20,1);
    begin
     perform public.round_send_for(v_pl,f,'pirates','{"days":0}', now() + make_interval(secs=>rep*7));
    exception when sqlstate 'P0001' then whys:=whys||' '||left(sqlerrm,14); continue; end;
    select * into r from public.round_runs where fleet_id=f;
    k := (r.terms->>'most')::int; done:=done+1;
    perform public.round_settle(f, now()+interval '20 hours');
    select * into r from public.round_runs where fleet_id=f;
    gold := gold + coalesce((r.carry->>'gold')::numeric,0); rounds:=rounds+k; mins:=mins+k*10; hull:=hull+public.fleet_damage_pct(f); whys:=whys||' '||r.ended;
    sv := sv + coalesce((select sum(e.value::numeric*g.base_value) from jsonb_each_text(coalesce(r.carry->'salvage','{}')) e join public.goods g on g.code=e.key),0);
    rc := rc + coalesce(public.fleet_repair_cost(f,(select sum(sb.durability - s.durability) from public.ships s cross join lateral public.ship_base(s.id) sb where s.fleet_id=f),null),0);
    sc := sc + coalesce(public.stores_cost(v_pl,(r.terms->>'water')::numeric*k,(r.terms->>'food')::numeric*k),0) + coalesce((public.crew_hire_cost(f,greatest(0,(select sum(sb.crew_max - s.crew)::int from public.ships s cross join lateral public.ship_base(s.id) sb where s.fleet_id=f)))->>'cost')::numeric,0);
    am := am + floor((r.terms->>'ammo')::numeric*k)*878;
   end loop;
   if done>0 then insert into bal values('combat',c.code,d*40,n,round(rounds/done,1),round(mins/done),round(gold/done),round((rc+sc+am)/done),round(sv/done),round(hull/done),round(rc/done),round(sc/done),round(am/done),0,trim(whys)); else insert into bal values('combat',c.code,d*40,n,0,0,0,0,0,0,0,0,0,0,trim(whys)); end if;
  end loop;
 end loop; end loop;
end $$;
select json_agg(b) from bal b;
