-- THE ROUNDS BALANCE: LOCAL ONLY, never production (it lights switches, founds houses and fills purses). docs/dev-log/2026-11-25-rounds-balance.md
create temp table bal(fleet text, sea numeric, n int, rounds numeric, gold numeric, salv numeric, rep numeric, sto numeric, amm numeric, net numeric, why text);
do $$
declare v_pl uuid; f uuid; v_sea uuid; c record; n int; d numeric; r record; k int; rep int; u uuid; v_out text; o jsonb; rc numeric; sc numeric; am numeric; sv numeric; h numeric; v_code text;
 a_r numeric; a_g numeric; a_s numeric; a_rc numeric; a_sc numeric; a_am numeric; a_h numeric; whys text; v_def text; v_dmg numeric;
begin
 update public.world_config set value='true' where key in ('rounds_enabled','combat_rounds_enabled','wrecks_yield_enabled','city_treasury_enabled','reputation_on','ship_stores_separate','ammo_enabled','fleet_jobs_enabled','sea_courses_enabled','jobs_wait_enabled');
 insert into public.port_treasury (port_id, ducats) select p.id, 50000 from public.ports p where p.kind='HARBOUR' on conflict (port_id) do update set ducats=50000;
 update public.port_treasury set ducats=895000000 where port_id=public.pirate_capital();
 update public.port_goods pg set stock=100000 from public.goods g where g.id=pg.good_id and public.pirate_home(pg.port_id) and g.code in ('planks','timber','cordage','canvas-duck','iron','tar');
 alter table public.ships disable trigger user;
 for c in select * from public.ship_classes where code in ('xebec','nau','galeao','sanmartin') order by attack loop
 foreach n in array array[1,3] loop
 foreach d in array array[0.1,0.2,0.4,0.8] loop
  a_r:=0;a_g:=0;a_s:=0;a_rc:=0;a_sc:=0;a_am:=0;a_h:=0;whys:='';
  for rep in 1..4 loop
   begin
   u := ('00000000-0535-4000-8000-'||lpad((rep*7)::text,12,'0'))::uuid;
   v_pl := public.new_house(u,'Balanco '||rep,'PRT');
   select x.id, h.sea_id, h.code into f, v_sea, v_code from public.fleets x join public.ports h on h.id=x.port_id where x.player_id=v_pl;
   update public.players set ducats=100000000 where id=v_pl;
   delete from public.sea_pressure where sea_id=v_sea;
   update public.seas set piracy_index=d where id=v_sea;
   update public.ships set class_id=c.id where fleet_id=f;
   for k in 2..n loop insert into public.ships select (jsonb_populate_record(null::public.ships, to_jsonb(s)||jsonb_build_object('id',gen_random_uuid(),'name','Nau '||k,'is_flagship',false))).* from public.ships s where s.fleet_id=f and s.is_flagship; end loop;
   update public.ships s set crew=(select sb.crew_max from public.ship_base(s.id) sb), durability=(select sb.durability from public.ship_base(s.id) sb), food_t=500, water_t=500, cargo='{}', cargo_basis='{}' where s.fleet_id=f;
   perform public.fleet_load(f,'gunpowder',20,1); perform public.fleet_load(f,'shot-and-ball',20,1);
   perform cmd.assume_identity(u);
   perform cmd.set_fleet_job(f,'round',jsonb_build_object('work','pirates','base',v_code,'stop','{"days":0}'::jsonb,'then','home'));
   call public.tick_fleet_jobs(false);
   select * into r from public.round_runs where fleet_id=f;
   if r.fleet_id is null then raise exception using errcode='ZZ001', message='{"why":"nosend"}'; end if;
   k := (r.terms->>'most')::int;
   update public.round_runs set sent_at=sent_at-interval '20 hours', stop_at=stop_at-interval '20 hours' where fleet_id=f;
   update public.fleet_jobs set since=since-interval '21 hours' where fleet_id=f;
   update public.fleets set busy_until=busy_until-interval '20 hours' where id=f;
   call public.tick_fleet_jobs(false);
   select * into r from public.round_runs where fleet_id=f;
   if r.state='out' then raise notice '% x% % %: out % status % busy % most %', c.code,n,d,rep,r.stop_at-now(),(select status from public.fleets where id=f),(select busy_until-now() from public.fleets where id=f), k; begin perform public.round_settle(f,now()); select * into r from public.round_runs where fleet_id=f; raise notice 'direct %',r.state; exception when others then raise notice 'ERR %',sqlerrm; end; end if;
   select sum(sb.durability - s.durability), max(sb.durability) into rc, v_dmg from public.ships s cross join lateral public.ship_base(s.id) sb where s.fleet_id=f;
   v_dmg := 100*(select coalesce(sum(q.v::numeric),0) from jsonb_array_elements_text(r.terms#>'{fight,l}') q(v)); rc := coalesce(public.fleet_repair_cost(f,(select sum(sb.durability) from public.ships s cross join lateral public.ship_base(s.id) sb where s.fleet_id=f)*v_dmg/100,null),0);
   sv := coalesce((select sum(e.value::numeric*g.base_value) from jsonb_each_text(coalesce(r.carry->'salvage','{}')) e join public.goods g on g.code=e.key),0);
   sc := coalesce(public.stores_cost(v_pl,(r.terms->>'water')::numeric*k,(r.terms->>'food')::numeric*k),0) + coalesce((public.crew_hire_cost(f,greatest(0,(select sum(sb.crew_max - s.crew)::int from public.ships s cross join lateral public.ship_base(s.id) sb where s.fleet_id=f)))->>'cost')::numeric,0);
   am := floor((r.terms->>'ammo')::numeric*k)*878;
   raise exception using errcode='ZZ001', message=jsonb_build_object('k',k,'g',coalesce((r.carry->>'gold')::numeric,0),'s',sv,'rc',rc,'sc',sc,'am',am,'h',k/6.0+coalesce(v_dmg,0)*0.4/192,'why',r.ended)::text;
   exception when sqlstate 'ZZ001' then o := sqlerrm::jsonb; end;
   whys := whys||' '||coalesce(o->>'why','?');
   a_r:=a_r+coalesce((o->>'k')::numeric,0);a_g:=a_g+coalesce((o->>'g')::numeric,0);a_s:=a_s+coalesce((o->>'s')::numeric,0);a_rc:=a_rc+coalesce((o->>'rc')::numeric,0);a_sc:=a_sc+coalesce((o->>'sc')::numeric,0);a_am:=a_am+coalesce((o->>'am')::numeric,0);a_h:=a_h+coalesce((o->>'h')::numeric,0);
  end loop;
  insert into bal values (c.code||' x'||n,d*40,n,round(a_r/4,1),round(a_g/nullif(a_h,0)),round(a_s/nullif(a_h,0)),round(a_rc/nullif(a_h,0)),round(a_sc/nullif(a_h,0)),round(a_am/nullif(a_h,0)),round((a_g+a_s-a_rc-a_sc-a_am)/nullif(a_h,0)),trim(whys));
 end loop; end loop; end loop;
end $$;
select json_agg(b) from bal b;
