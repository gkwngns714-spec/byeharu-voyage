-- THE ROUNDS BALANCE: LOCAL ONLY, never production (it lights switches, founds houses and fills purses). docs/dev-log/2026-11-25-rounds-balance.md
do $$
declare v_pl uuid; f uuid; i int; r record; v_tot numeric := 0; v_first numeric; v_last numeric; h0 numeric; w0 numeric; w1 numeric; cap uuid := public.pirate_capital(); nx int:=0;
begin
 update public.world_config set value='true' where key in ('rounds_enabled','combat_rounds_enabled','wrecks_yield_enabled','city_treasury_enabled');
 insert into public.port_treasury (port_id, ducats) select p.id, 50000 from public.ports p where p.kind='HARBOUR' on conflict (port_id) do update set ducats=50000;
 update public.port_treasury set ducats=895000000 where port_id=cap;
 raise notice 'hoard % room %', public.pirate_hoard(), public.pirate_spend_room(now());
 h0 := public.pirate_hoard();
 for i in 1..60 loop
  v_pl := public.new_house(('00000000-0536-4000-8000-'||lpad(i::text,12,'0'))::uuid,'Cap '||chr(64+(i-1)/26+1)||chr(65+(i-1)%26),'PRT');
  select x.id into f from public.fleets x where x.player_id=v_pl;
  insert into public.round_runs (fleet_id,player_id,work,sea_id,state,sent_at,stop_at,terms) select f,v_pl,'pirates',h.sea_id,'out',now()-interval '13 hours',now()-interval '1 hour',
   jsonb_build_object('seconds',600,'crew',0,'food',0,'water',0,'ammo',0,'most',72,'why','cap','strength',32,'kind','combat','fight',jsonb_build_object('l',(select jsonb_agg(0.075) from generate_series(1,72)),'c',(select jsonb_agg(0) from generate_series(1,72)),'w',(select jsonb_agg(1) from generate_series(1,72))))
   from public.fleets x join public.ports h on h.id=x.port_id where x.id=f;
  update public.fleets set status='ROUNDS', busy_until=now()-interval '1 hour' where id=f;
  perform public.round_settle(f, now());
  select coalesce((carry->>'gold')::numeric,0) into v_last from public.round_runs where fleet_id=f;
  v_tot := v_tot+v_last; if v_last < 240000 then nx := nx+1; end if;
  if i in (1,20,37,38,60) then raise notice 'company %: paid %, all %, room left %, hoard moved %', i, v_last, v_tot, public.pirate_spend_room(now()), h0-public.pirate_hoard(); end if;
 end loop;
end $$; select 1;
