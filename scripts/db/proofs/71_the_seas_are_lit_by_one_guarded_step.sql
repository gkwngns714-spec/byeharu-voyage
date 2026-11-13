-- ═══════════════════════════════════════════════════════════════════════════════
-- PROOF 71 - THE SEAS ARE LIT BY ONE GUARDED STEP  (migration 0378; owner rows 166 and 324)
--
--   0378 lights nothing: it installs public.sea_conditions_ready (the guards, as figures) and public.sea_conditions_light (the step). This proof runs the
--   step on a world it makes ready itself, breaks each guard in turn, lights, reads the wall and the news, and throws the switch back. All rolled back with
--   proof.mjs's transaction. The companies it reads are the chain's own (title 1, a barca or a barca and a caravel, some lying in far seas).
--
-- @pass SL_AS_SHIPPED   the chain's world is not ready (fleet room off, companies lying in far seas): the read says so, the step refuses naming those guards, the switch stays dark and no news row is written
-- @pass SL_GUARD_ROOM   everything else ready, fleet_room_bite off: refused, naming fleet room
-- @pass SL_GUARD_FLEET  a company's fleet lying in a sea her title does not open: refused, naming one fleet and her company; a fleet under way to such a harbour is counted the same
-- @pass SL_GUARD_HOME   a company whose country's capital lies in a sea her title does not open: refused, naming it
-- @pass SL_GUARD_ROUTE  a company's standing route with a leg into such a sea: refused, naming one leg
-- @pass SL_LIT          a ready world: the step lights sea_conditions_bite, posts exactly one news row (update:0378, English and Korean) and answers its figures; asked again it refuses (already lit) and posts nothing
-- @pass SL_WALL         lit: a title-1 barca at Lisbon may sail Funchal and is refused Las Palmas E_SEA_CLOSED by Macaronesia (title 2 asked, 1 held; 0376: the title is short, the wave is not); voyage.sail_refusal says the same at the door
-- @pass SL_BACK         the switch thrown back: the same passage is open again
-- ═══════════════════════════════════════════════════════════════════════════════

do $$
declare
  v_r      jsonb;
  v_g      jsonb;
  v_err    text;
  v_news   bigint;
  v_lis    uuid := (select p.id from public.ports p where p.code = 'LIS');
  v_fnc    uuid := (select p.id from public.ports p where p.code = 'FNC');
  v_lpa    uuid := (select p.id from public.ports p where p.code = 'LPA');
  v_acc    uuid := (select p.id from public.ports p where p.code = 'ACC');
  v_cf     jsonb;
  v_cl     jsonb;
  v_ca     jsonb;
  v_a      record;   -- a title-1 company with one barca
  v_route  uuid;
  v_jpn    uuid := (select n.id from public.nations n where n.code = 'JPN');
  v_was    uuid;
begin
  if to_regprocedure('public.sea_conditions_light()') is null then
    raise exception 'PROOF 71 FAIL: 0378 is not in this world';
  end if;
  select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b.roadstead_lat, b.roadstead_lon)) into v_cf
    from public.sea_reaches a, public.sea_reaches b where a.code = 'LIS' and b.code = 'FNC';
  select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b.roadstead_lat, b.roadstead_lon)) into v_cl
    from public.sea_reaches a, public.sea_reaches b where a.code = 'LIS' and b.code = 'LPA';
  select jsonb_build_array(jsonb_build_array(a.roadstead_lat, a.roadstead_lon), jsonb_build_array(b.roadstead_lat, b.roadstead_lon)) into v_ca
    from public.sea_reaches a, public.sea_reaches b where a.code = 'LPA' and b.code = 'ACC';
  select count(*) into v_news from public.world_news;

  -- ── SL_AS_SHIPPED ──
  v_r := public.sea_conditions_ready();
  if (v_r ->> 'lit')::boolean or (v_r ->> 'ready')::boolean or (v_r ->> 'fleet_room')::boolean or (v_r ->> 'fleets_in_closed_seas')::int < 1 then
    raise exception 'PROOF 71 FAIL: the chain''s world reads ready, lit, or with no company in a far sea: %', v_r;
  end if;
  begin
    perform public.sea_conditions_light();
    v_err := null;
  exception when sqlstate 'P0001' then v_err := sqlerrm;
  end;
  if v_err is null or v_err not like 'sea_conditions_light refuses: %' or v_err not like '%fleet_room_bite is off%' or v_err not like '%lie in, or sail to, a sea that would refuse them%'
     or public.sea_conditions_on() or (select count(*) from public.world_news) <> v_news then
    raise exception 'PROOF 71 FAIL: as shipped the step did not refuse naming fleet room and the fleets in far seas, or changed something: %', v_err;
  end if;
  raise notice 'PASS: SL_AS_SHIPPED - not ready (% fleets of companies in far seas, fleet room off): refused, the switch dark, no news', v_r ->> 'fleets_in_closed_seas';

  -- ── a ready world: fleet room on, every company's fleet home at Lisbon ──
  update public.world_config set value = 'true'::jsonb where key = 'fleet_room_bite';
  update public.fleets f set port_id = v_lis, status = 'DOCKED' from public.players p where p.id = f.player_id and not p.is_npc and f.port_id is distinct from v_lis;
  v_r := public.sea_conditions_ready();
  if not (v_r ->> 'ready')::boolean then
    raise exception 'PROOF 71 FAIL: fleet room on and every company at Lisbon, and the world is still not ready: %', v_r;
  end if;
  select p.id as player_id, p.company_name, f.id as fleet_id, f.name into v_a
    from public.players p join public.fleets f on f.player_id = p.id
   where not p.is_npc and public.title_level(p.id) = 1 and public.fleet_wave(f.id) = 12
   order by p.company_name limit 1;
  if v_a.fleet_id is null then
    raise exception 'PROOF 71 FAIL: the world has no title-1 company with a barca fleet';
  end if;

  -- ── SL_GUARD_ROOM ──
  update public.world_config set value = 'false'::jsonb where key = 'fleet_room_bite';
  begin
    perform public.sea_conditions_light();
    v_err := null;
  exception when sqlstate 'P0001' then v_err := sqlerrm;
  end;
  if v_err is null or v_err not like '%fleet_room_bite is off%' or v_err like '%lie in, or sail to%' or public.sea_conditions_on() then
    raise exception 'PROOF 71 FAIL: fleet room off alone was not the one guard named: %', v_err;
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'fleet_room_bite';
  raise notice 'PASS: SL_GUARD_ROOM - fleet room off alone: refused, naming it';

  -- ── SL_GUARD_FLEET ──
  update public.fleets set port_id = v_acc where id = v_a.fleet_id;
  begin
    perform public.sea_conditions_light();
    v_err := null;
  exception when sqlstate 'P0001' then v_err := sqlerrm;
  end;
  if v_err is null or v_err not like '%1 fleet(s) of companies lie in, or sail to, a sea that would refuse them%' or v_err not like '%' || v_a.company_name || ' / ' || v_a.name || ' at ACC%'
     or public.sea_conditions_on() then
    raise exception 'PROOF 71 FAIL: a fleet at Accra at title 1 was not the guard named: %', v_err;
  end if;
  -- under way to it: no port, a voyage whose harbour is Accra
  update public.fleets set port_id = null, status = 'SAILING' where id = v_a.fleet_id;
  insert into public.voyages (fleet_id, player_id, path, total_nm, speed_profile, departed_at, eta, status, origin_port_id, dest_port_id)
  values (v_a.fleet_id, v_a.player_id, '[]'::jsonb, 100, '[5]'::jsonb, now(), now() + interval '1 hour', 'SAILING', v_lis, v_acc);
  if (public.sea_conditions_ready() ->> 'fleets_in_closed_seas')::int <> 1 then
    raise exception 'PROOF 71 FAIL: a fleet under way to Accra is not counted: %', public.sea_conditions_ready();
  end if;
  delete from public.voyages where fleet_id = v_a.fleet_id and status = 'SAILING';
  update public.fleets set port_id = v_lis, status = 'DOCKED' where id = v_a.fleet_id;
  raise notice 'PASS: SL_GUARD_FLEET - a title-1 fleet at Accra, and the same under way to it: refused, naming her and her company';

  -- ── SL_GUARD_HOME ──
  select p.nation_id into v_was from public.players p where p.id = v_a.player_id;
  update public.players set nation_id = v_jpn where id = v_a.player_id;
  begin
    perform public.sea_conditions_light();
    v_err := null;
  exception when sqlstate 'P0001' then v_err := sqlerrm;
  end;
  if v_jpn is null or v_err is null or v_err not like '%1 company(ies) have a capital in a sea their title does not open%' or public.sea_conditions_on() then
    raise exception 'PROOF 71 FAIL: a title-1 company of Japan was not the guard named: %', v_err;
  end if;
  update public.players set nation_id = v_was where id = v_a.player_id;
  raise notice 'PASS: SL_GUARD_HOME - a title-1 company whose capital is Sakai: refused, naming it';

  -- ── SL_GUARD_ROUTE ──
  insert into public.standing_routes (player_id, name, fleet_id) values (v_a.player_id, 'Rota 0f71', v_a.fleet_id) returning id into v_route;
  insert into public.standing_route_stops (route_id, ord, port_id, course) values (v_route, 0, v_lis, v_cf), (v_route, 1, v_fnc, v_cl || '[]'::jsonb);
  -- stop 0: Lisbon to Funchal (open); stop 1's course is the Lisbon to Las Palmas line and its leg ends at stop 0 (Lisbon): it crosses Macaronesia
  begin
    perform public.sea_conditions_light();
    v_err := null;
  exception when sqlstate 'P0001' then v_err := sqlerrm;
  end;
  if v_err is null or v_err not like '%1 leg(s) of companies'' standing routes would be refused%' or public.sea_conditions_on() then
    raise exception 'PROOF 71 FAIL: a standing route with one leg through Macaronesia was not the guard named: %', v_err;
  end if;
  delete from public.standing_route_stops where route_id = v_route;
  delete from public.standing_routes where id = v_route;
  raise notice 'PASS: SL_GUARD_ROUTE - a standing route with one leg through Macaronesia at title 1: refused, naming the leg';

  -- ── SL_LIT ──
  v_g := public.sea_conditions_light();
  if not public.sea_conditions_on() or not (v_g ->> 'lit')::boolean
     or (select count(*) from public.world_news) <> v_news + 1
     or not exists (select 1 from public.world_news n where n.key = 'update:0378' and n.kind = 'UPDATE'
                      and n.detail -> 'words' -> 'title' ->> 'en' = 'Seas ask a title and a sturdy ship' and n.detail -> 'words' -> 'title' ->> 'ko' = '바다마다 작위와 내파 필요') then
    raise exception 'PROOF 71 FAIL: the step did not light a ready world with one news row in both languages: %', v_g;
  end if;
  begin
    perform public.sea_conditions_light();
    v_err := null;
  exception when sqlstate 'P0001' then v_err := sqlerrm;
  end;
  if v_err is distinct from 'sea_conditions_light refuses: the sea conditions are already lit' or (select count(*) from public.world_news) <> v_news + 1 then
    raise exception 'PROOF 71 FAIL: asked again the step did not refuse as already lit, or posted again: %', v_err;
  end if;
  raise notice 'PASS: SL_LIT - a ready world is lit by the step, with one news row (EN and KO); asked again it refuses and posts nothing';

  -- ── SL_WALL ──
  v_g := public.passage_gate(v_a.player_id, v_a.fleet_id, 1, v_lpa, v_cl);
  if public.passage_gate(v_a.player_id, v_a.fleet_id, 1, v_fnc, v_cf) is not null
     or v_g is null or v_g ->> 'code' <> 'E_SEA_CLOSED' or v_g -> 'figures' ->> 'zone' <> 'NOR-MAC'
     or (v_g -> 'figures' ->> 'needs_title')::int <> 2 or (v_g -> 'figures' ->> 'title')::int <> 1
     or (v_g -> 'figures' ->> 'needs_wave')::int <> 10 or (v_g -> 'figures' ->> 'wave')::numeric <> 12
     or (v_g -> 'figures' ? 'short_title' and (not (v_g -> 'figures' ->> 'short_title')::boolean or (v_g -> 'figures' ->> 'short_wave')::boolean)) then
    raise exception 'PROOF 71 FAIL: lit, a title-1 barca is not free to Funchal and refused Las Palmas by Macaronesia with its figures: %', v_g;
  end if;
  if voyage.sail_refusal(v_a.fleet_id, v_fnc, null, 1, v_cf) is not null
     or voyage.sail_refusal(v_a.fleet_id, v_lpa, null, 1, v_cl) ->> 'code' is distinct from 'E_SEA_CLOSED' then
    raise exception 'PROOF 71 FAIL: lit, the sail door does not say the same: Funchal %, Las Palmas %', voyage.sail_refusal(v_a.fleet_id, v_fnc, null, 1, v_cf), voyage.sail_refusal(v_a.fleet_id, v_lpa, null, 1, v_cl);
  end if;
  raise notice 'PASS: SL_WALL - lit, a title-1 barca at Lisbon may sail Funchal and is refused Las Palmas by Macaronesia (title 2 asked, 1 held; wave 10 asked, 12 held%); the sail door says the same',
    case when v_g -> 'figures' ? 'short_title' then '; the title is short, the wave is not' else '' end;

  -- ── SL_BACK ──
  update public.world_config set value = 'false'::jsonb where key = 'sea_conditions_bite';
  if public.passage_gate(v_a.player_id, v_a.fleet_id, 1, v_lpa, v_cl) is not null or public.sea_conditions_on() then
    raise exception 'PROOF 71 FAIL: the switch thrown back, Las Palmas is still refused';
  end if;
  raise notice 'PASS: SL_BACK - the switch thrown back: Las Palmas is open again';
end $$;
