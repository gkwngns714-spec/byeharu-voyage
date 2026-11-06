-- 0324 DARK PARITY SCENE: run by proof-0324.mjs on the world BEFORE the file and AFTER it, rolled back each time. It names only what existed before 0324, so it runs on both. Every SCENE line must be equal.
-- Off (`convoy_rich_enabled` false, the default): the same flows, purses, book, ships, stops and answers, with convoys off and with convoys lit as prod is. The sea is stubbed quiet. Times and row ids are left out.
do $$
declare
  v_last int := world.game_day() - 1;
  v_nat  uuid;
  v_cap  uuid;
  v_fl   uuid;
  v_s    uuid[];
  v_mark bigint;
  v_now  timestamptz := now();
  v_step text;
  v_seq  text[] := '{}';
  v_eta  timestamptz;
  v_id   uuid;
  v_g    int := 0;
  v_pl   uuid;
  v_r    jsonb;
begin
  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed');
  update public.world_config set value = to_jsonb(50000) where key = 'treasury_reserve_floor';
  update public.world_config set value = to_jsonb(0.1) where key = 'crown_call_share';
  update public.world_config set value = to_jsonb(20) where key = 'crown_call_cover';
  update public.world_config set value = to_jsonb(4) where key = 'convoy_ships_per_nation';
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set earned_day = v_last, ducats = 50000, reserve = 0;
  alter function voyage.hazard_roll(uuid, integer) rename to hazard_roll_real_scene;
  execute $f$
create function voyage.hazard_roll(p_voyage uuid, p_day integer)
returns table (occurred boolean, kind text, magnitude numeric, p_hazard numeric)
language sql stable
as $b$ select false, null::text, 0.5::numeric, 1::numeric $b$
  $f$;
  execute $f$
create function pg_temp.scene(p_tag text, p_mark bigint)
returns void
language plpgsql
as $b$
begin
  raise notice 'SCENE: % %', p_tag, jsonb_build_object(
    'flows', (select jsonb_agg(jsonb_build_array(f.kind, p.code, f.ducats) order by f.id) from public.treasury_flows f join public.ports p on p.id = f.port_id where f.id > p_mark),
    'purses', (select md5(string_agg(p.code || ':' || public.treasury_balance(p.id), ',' order by p.code)) from public.ports p join public.port_treasury t on t.port_id = p.id),
    'book', (select jsonb_agg(jsonb_build_array(k.stage, p.code, k.ducats) order by k.id) from public.convoy_cargo k join public.ports p on p.id = k.port_id),
    'ships', (select jsonb_agg(jsonb_build_array(n.code, c.ord, h.code, f.status, q.code, c.leg, c.out_load is not null) order by n.code, c.ord)
                from public.cargo_ships c join public.nations n on n.id = c.nation_id join public.ports h on h.id = c.home_port_id join public.fleets f on f.id = c.fleet_id left join public.ports q on q.id = f.port_id),
    'circuits', (select jsonb_agg(jsonb_build_array(n.code, k.left_out, (select count(*) from public.cargo_circuit_legs l where l.circuit_id = k.id)) order by n.code) from public.cargo_circuits k join public.nations n on n.id = k.nation_id));
end
$b$
  $f$;

  raise notice 'SCENE: plans %', (select jsonb_agg(md5(public.cargo_circuit_plan(g.nation_id)::text) order by g.nation_id) from public.great_powers g);

  select g.nation_id, public.city_capital(p.id), p.id into v_nat, v_cap
    from public.great_powers g join public.nations n on n.id = g.nation_id join public.ports p on p.code = n.capital_port_code where n.code = 'PRT';
  v_s := array(select p.id from public.ports p where p.kind = 'HARBOUR' and p.id <> v_cap and public.city_capital(p.id) = v_cap
                  and exists (select 1 from public.npc_courses c where c.from_port = p.id or c.to_port = p.id) order by p.code);
  update public.port_treasury t set ducats = 1000 where t.port_id = any (array[v_cap, v_s[1], v_s[2]]);
  update public.port_treasury t set ducats = 90000000 where t.port_id = v_s[3];
  update public.port_treasury t set ducats = 3000000 where t.port_id = v_s[4];
  v_mark := coalesce((select max(id) from public.treasury_flows), 0);

  -- convoys off
  begin
    v_r := public.tick_cargo_ships(now(), v_nat);
    raise notice 'SCENE: off_tick %', v_r ->> 'made';
    v_r := public.crown_aid(v_cap);
    raise notice 'SCENE: off_aid %', v_r;
    perform pg_temp.scene('off', v_mark);
    raise exception using errcode = 'ZX324';
  exception when sqlstate 'ZX324' then null; end;

  -- convoys lit, as prod is
  update public.world_config set value = 'true'::jsonb where key = 'convoys_enabled';
  v_r := public.tick_cargo_ships(now(), v_nat);
  raise notice 'SCENE: lit_tick %', (v_r - 'built') || jsonb_build_object('built', v_r ? 'built' and v_r ->> 'built' is not null);   -- a circuit's id is a sequence's, and a rollback does not rewind it
  v_r := public.tick_cargo_ships(now(), v_nat);
  raise notice 'SCENE: lit_tick2 %', v_r;
  v_r := public.crown_aid(v_cap);
  raise notice 'SCENE: lit_aid %', v_r;
  perform pg_temp.scene('lit_loaded', v_mark);
  raise notice 'SCENE: on_way %', public.funds_on_way(v_s[1]);
  raise notice 'SCENE: on_way_capital %', public.funds_on_way(v_cap);

  -- one whole lap of the loaded ship, and an idle one's step
  v_fl := (select c.fleet_id from public.cargo_ships c where c.nation_id = v_nat and c.ord = 1);
  raise notice 'SCENE: idle %', public.cargo_ship_step((select c.fleet_id from public.cargo_ships c where c.nation_id = v_nat and c.ord = 2), v_now);
  loop
    v_g := v_g + 1;
    exit when v_g > 500;
    v_step := public.cargo_ship_step(v_fl, v_now);
    exit when v_step = 'HOME';
    if v_step = 'SAILED' then
      select o.id, o.eta into v_id, v_eta from public.voyages o where o.fleet_id = v_fl and o.status = 'SAILING';
      v_seq := v_seq || (select p.code from public.voyages o join public.ports p on p.id = o.dest_port_id where o.id = v_id);
      loop
        perform voyage.settle(v_fl, v_eta);
        exit when (select f.status from public.fleets f where f.id = v_fl) <> 'SAILING';
        v_eta := (select o.eta from public.voyages o where o.id = v_id);
      end loop;
      v_now := v_eta;
    elsif v_step = 'IN_PORT' then
      v_now := v_now + interval '61 seconds';
    else
      raise exception 'scene: step %', v_step;
    end if;
  end loop;
  raise notice 'SCENE: lap % %', v_step, v_seq;
  perform pg_temp.scene('lit_lap', v_mark);

  -- a gift the capital must call for, then one it cannot
  insert into public.players (company_name, nation_id, ducats) values ('Scene 0324 house', v_nat, 0) returning id into v_pl;
  v_r := public.capital_pays(v_cap, v_nat, v_pl, 'CAPITAL_GIFT', 1000000, null, false);
  raise notice 'SCENE: gift %', v_r - 'event';
  update public.port_treasury t set ducats = 50000 where public.city_capital(t.port_id) = v_cap;
  v_r := public.capital_pays(v_cap, v_nat, v_pl, 'CAPITAL_GIFT', 9000000, null, false);
  raise notice 'SCENE: gift_waits %', v_r - 'event';

  raise exception using errcode = 'ZY324';
exception when sqlstate 'ZY324' then
  null;
end
$$;
