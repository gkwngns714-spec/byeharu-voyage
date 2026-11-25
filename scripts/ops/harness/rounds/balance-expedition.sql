-- THE ROUNDS BALANCE: LOCAL ONLY, never production (it lights switches, founds houses and fills purses). docs/dev-log/2026-11-25-rounds-balance.md
do $$ begin if inet_server_addr() is not null then raise exception 'local PGlite world only: this scene writes'; end if; end $$;
do $$
declare v_pl uuid; f uuid; r record; k int; n int; c text; lv int; t jsonb; st numeric; hi numeric; o jsonb; b numeric; v_txt text;
begin
 update public.world_config set value='true' where key in ('rounds_enabled','expedition_rounds_enabled','city_treasury_enabled','ship_stores_separate','fleet_jobs_enabled','sea_courses_enabled','jobs_wait_enabled');
 insert into public.port_treasury (port_id, ducats) select p.id, 500000000 from public.ports p where p.kind='HARBOUR' on conflict (port_id) do update set ducats=500000000;
 alter table public.ships disable trigger user;
 foreach c in array array['barca','xebec','nau','galeao','sanmartin'] loop foreach n in array array[1,3] loop
  begin
  v_pl := public.new_house('00000000-0534-4000-8000-0000000000c1','Balanco','PRT');
  select x.id into f from public.fleets x where x.player_id=v_pl;
  update public.players set ducats=1000000 where id=v_pl;
  update public.ships set class_id=(select id from public.ship_classes where code=c) where fleet_id=f;
  for k in 2..n loop insert into public.ships select (jsonb_populate_record(null::public.ships, to_jsonb(s)||jsonb_build_object('id',gen_random_uuid(),'name','Nau '||k,'is_flagship',false))).* from public.ships s where s.fleet_id=f and is_flagship; end loop;
  update public.ships s set crew=(select sb.crew_max from public.ship_base(s.id) sb), durability=(select sb.durability from public.ship_base(s.id) sb), food_t=300, water_t=400 where s.fleet_id=f;
  perform cmd.assume_identity('00000000-0534-4000-8000-0000000000c1');
  v_txt := '';
  foreach lv in array array[1,8,15] loop
   insert into public.house_level_marks (player_id, track, level) values (v_pl,'exploration',lv) on conflict (player_id,track) do update set level=lv;
   t := public.round_terms(f,'expedition','{"days":0}');
   st := public.stores_cost(v_pl,(t->>'water')::numeric,(t->>'food')::numeric);
   hi := (t->>'crew')::numeric * coalesce((public.crew_hire_cost(f,10)->>'cost')::numeric,0)/10;
   v_txt := v_txt || format(' L%s: ' || (t->>'gold') || ' - stores %s - crew %s = %s/h;', lv, round(st,1), round(hi,1), round(((t->>'gold')::numeric-st-hi)*4));
  end loop;
  update public.ships s set crew=(select cc.crew_required from public.ship_classes cc where cc.id=s.class_id), food_t=5, water_t=8 where s.fleet_id=f;
  o := world.actions('fleet:'||f);
  select max((e->>'per_hour')::numeric) into b from jsonb_array_elements(o->'options') e where e->>'id' like 'sea:fixed%' and coalesce(e->>'end','sell')<>'store';
  raise notice '% x% exped:%  trade best %/h (top 3: %)', c, n, v_txt, b, (select string_agg((z.e->>'per_hour'),',') from (select e from jsonb_array_elements(o->'options') e where e->>'id' like 'sea:fixed%' order by (e->>'per_hour')::numeric desc nulls last limit 3) z);
  raise exception using errcode='ZZ001', message='x';
  exception when sqlstate 'ZZ001' then null; end;
 end loop; end loop;
end $$;
select 1;
