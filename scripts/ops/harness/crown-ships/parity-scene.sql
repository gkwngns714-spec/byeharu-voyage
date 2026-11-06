-- 0332 PARITY SCENE, local, run before and after the file by proof-0332.mjs. Every SCENE line must be equal: the two reads the file cuts, with the one new key taken off, byte for byte.
do $$
declare
  v_snap jsonb := world.snapshot();
  r record;
begin
  raise notice 'SCENE: snapshot, classes % %', jsonb_array_length(v_snap -> 'ship_classes'),
    md5((select jsonb_agg(s - 'crown' order by s ->> 'code')::text from jsonb_array_elements(v_snap -> 'ship_classes') s));
  raise notice 'SCENE: snapshot, the rest %', md5((v_snap - 'ship_classes')::text);
  for r in select b.port_id, p.code from public.port_buildings b join public.ports p on p.id = b.port_id where b.kind = 'building_yard' order by p.code loop
    raise notice 'SCENE: yard % %', r.code,
      md5((select jsonb_agg(s - 'crown' order by s ->> 'class')::text from jsonb_array_elements(world.building_yard(r.port_id) -> 'hulls') s));
  end loop;
end
$$;
