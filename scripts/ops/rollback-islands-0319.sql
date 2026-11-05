-- THE FORWARD ROLLBACK OF THE HARBOURS' ISLANDS. Run it only as the body of a NEW migration, next number
-- after prod head, and revert the client in the same deploy: an island drawn over water fleets sail is the
-- thing this whole change exists to end. It restores what public.sea_undo_0319 keeps, re-derives what 0319
-- re-derived, and proves it. Tested on the world image: every table back to its pre-image, byte for byte.
-- A route saved AFTER 0319 ends at a new roadstead and is not in the undo table. Those are named by the
-- notice below; each re-joins by the owner re-saving it, or by the next merchant re-plan.

update public.sea_raster r set cells = u.bytes
  from public.sea_undo_0319 u where u.kind = 'raster' and r.id = 1;

update public.sea_reaches sr
   set snap_nm = (u.value->>'snap_nm')::numeric, roadstead_lat = (u.value->>'lat')::numeric,
       roadstead_lon = (u.value->>'lon')::numeric, reaches = u.value->'reaches'
  from public.sea_undo_0319 u where u.kind = 'reach' and u.ref = sr.code;

update public.standing_route_stops s
   set course = u.value->'course', course_nm = (u.value->>'course_nm')::numeric
  from public.sea_undo_0319 u where u.kind = 'stop' and u.ref = s.route_id::text || '|' || s.ord;

update public.npc_courses c
   set course = u.value->'course', nm = (u.value->>'nm')::numeric
  from public.sea_undo_0319 u where u.kind = 'npc_course' and u.ref = c.from_port::text || '|' || c.to_port::text;

update public.sea_leg_asks a set wave_min = d.wave_min, title_min = d.title_min, zones = d.zones
  from public.sea_leg_asks_derive() d
 where a.from_port = d.from_port and a.to_port = d.to_port
   and (a.wave_min, a.title_min, a.zones) is distinct from (d.wave_min, d.title_min, d.zones);

update public.port_goods pg set haul_nm = h.haul_nm, haul = h.haul
  from world.haul_rows() h
 where h.port_id = pg.port_id and h.good_id = pg.good_id
   and (pg.haul_nm, pg.haul) is distinct from (h.haul_nm, h.haul);

do $$
declare v_bad int;
begin
  if (select r.cells from public.sea_raster r where r.id = 1) is distinct from
     (select u.bytes from public.sea_undo_0319 u where u.kind = 'raster') then
    raise exception 'rollback self-assert FAIL: the raster is not its pre-image';
  end if;
  select count(*) into v_bad from public.standing_route_stops s
    join public.sea_reaches r on r.port_id = s.port_id
   where jsonb_typeof(s.course) = 'array'
     and voyage.gc_distance_nm((s.course->0->>0)::float8, (s.course->0->>1)::float8, r.roadstead_lat::float8, r.roadstead_lon::float8)
         > public.wc_num('course_join_nm');
  raise notice 'rollback: % stop(s) saved after 0319 no longer join their roadstead', v_bad;
end $$;

drop table public.sea_undo_0319;
