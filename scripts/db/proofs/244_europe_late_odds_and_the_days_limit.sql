-- PROOF 244 - A NEW COMPANY IS OF EUROPE (0512), A LATE BARGAIN CAN BE WON (0506), THE PREMIUM'S DAY LIMIT IS SERVED (0517)
-- @pass EU_LIST   snapshot's `foundable` is exactly the countries a restart serves, every one of them joinable; some joinable country is not foundable
-- @pass EU_DOOR   the founding door refuses a country outside Europe in words and founds one of Europe; nothing is written by the refusal
-- @pass EU_STAY   a company already of another country keeps it, plays and may change country as before
-- @pass OD_TENTH  the tenth try's chance is above nought and under the ninth's, in the odds the draw itself uses
-- @pass PM_LEFT   nothing made: the face says the city's day limit, not 0; what she can sell now is 0
do $p$
declare
  c_a constant uuid := '00000000-0512-4000-8000-000000000244';
  c_b constant uuid := '00000000-0512-4000-8000-000000000245';
  v_a uuid; v_b uuid; v_f uuid; v_lis uuid := (select p.id from public.ports p where p.code = 'LIS'); v_g uuid; r jsonb; v_n int; v_o numeric; v_prev numeric := 1; i int; v_cd text;
begin
  update public.world_config set value = 'true'::jsonb where key in ('restart_enabled', 'city_treasury_enabled');
  v_a := public.new_house(c_a, 'Casa Japonesa 244', 'JPN', (select n.capital_port_code from public.nations n where n.code = 'JPN'));
  perform cmd.assume_identity(c_a);
  r := world.snapshot()->'nations';
  if (select jsonb_agg(e->>'code' order by e->>'name') from jsonb_array_elements(r) e where (e->>'foundable')::boolean) is distinct from world.player() #> '{player,restart,nations}'
     and (select jsonb_agg(e->>'code' order by e->>'name') from jsonb_array_elements(r) e where (e->>'foundable')::boolean) is distinct from public.restart_card(v_a)->'nations' then
    raise exception 'EU_LIST: % against %', (select jsonb_agg(e->>'code') from jsonb_array_elements(r) e where (e->>'foundable')::boolean), public.restart_card(v_a)->'nations';
  end if;
  if exists (select 1 from jsonb_array_elements(r) e where (e->>'foundable')::boolean and not (e->>'joinable')::boolean)
     or not exists (select 1 from jsonb_array_elements(r) e where (e->>'joinable')::boolean and not (e->>'foundable')::boolean) then raise exception 'EU_LIST: %', r; end if;
  raise notice 'PASS: EU_LIST - %', public.restart_card(v_a)->'nations';

  perform cmd.assume_identity(c_b);
  select count(*) into v_n from public.players;
  for v_cd in select e->>'code' from jsonb_array_elements(r) e where (e->>'joinable')::boolean and not (e->>'foundable')::boolean loop
    r := cmd.found_house('Casa Nova 244', v_cd);
    if r->>'error_code' is distinct from 'E_NOT_EUROPE' or coalesce(r->>'error_message', '') = '' then raise exception 'EU_DOOR: % answered %', v_cd, r; end if;
  end loop;
  if (select count(*) from public.players) <> v_n then raise exception 'EU_DOOR: a refusal wrote a company'; end if;
  r := cmd.found_house('Casa Nova 244', 'NLD');
  if (r->>'ok')::boolean is not true then raise exception 'EU_DOOR: %', r; end if;
  raise notice 'PASS: EU_DOOR - refused in words, founded in Europe';

  perform cmd.assume_identity(c_a);
  if (world.player() #>> '{player,nation}') is distinct from 'JPN' then raise exception 'EU_STAY: %', world.player()->'player'; end if;
  r := cmd.change_country('MNG');
  if (r->>'ok')::boolean is not true then raise exception 'EU_STAY: %', r; end if;
  raise notice 'PASS: EU_STAY - Japan kept; changed to %', r->>'nation';

  update public.world_config set value = 'true'::jsonb where key = 'bargain_total_enabled';
  select f.id into v_f from public.fleets f join public.players p on p.id = f.player_id where p.auth_uid = c_b;
  select f.player_id into v_b from public.fleets f where f.id = v_f;
  select g.id into v_g from public.goods g where public.port_offers(v_lis, g.id) order by g.code limit 1;
  for i in 0 .. 9 loop
    delete from public.haggle_daily h where h.player_id = v_b;
    insert into public.haggle_daily (player_id, port_id, good_id, day, attempts, wins, concession, last_side) values (v_b, v_lis, v_g, public.real_day(now()), i, 0, 0, 'buy');
    v_o := public.haggle_odds(v_b, v_lis, v_g, v_f);
    if v_o <= 0 or v_o >= v_prev then raise exception 'OD_TENTH: try % is % after %', i + 1, v_o, v_prev; end if;
    v_prev := v_o;
  end loop;
  raise notice 'PASS: OD_TENTH - the tenth try: %', v_o;

  update public.world_config set value = 'true'::jsonb where key in ('premium_goods_enabled', 'economy_closed');
  perform cmd.assume_identity(c_b);
  select g.id into v_g from public.goods g join public.port_goods pg on pg.good_id = g.id and pg.port_id = g.premium_port_id where not public.port_offers(g.premium_port_id, g.id) order by g.code limit 1;
  insert into public.port_treasury (port_id) select g.premium_port_id from public.goods g where g.id = v_g on conflict (port_id) do nothing;
  update public.port_treasury t set ducats = 900000000 where t.port_id = (select g.premium_port_id from public.goods g where g.id = v_g);
  r := public.premium_face(v_g)->'premium';
  if (r->>'left')::numeric is distinct from public.wc_num('premium_day_units') or (r->>'made')::numeric <> 0 or (r->>'mine')::numeric <> 0 then raise exception 'PM_LEFT: %', r; end if;
  raise notice 'PASS: PM_LEFT - % left today, % hers', r->>'left', r->>'mine';
end $p$;
