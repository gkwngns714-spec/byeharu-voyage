-- ═══════════════════════════════════════════════════════════════════════════════
-- PROOF 144 - THE PAIR TABLE KEEPS STEP WITH THE COURSES  (migration 0442; docs/dev-log/2026-11-15-seas-memo.md; owner row 352)
--
--   public.sea_leg_asks says which seas lie between two harbours and what the leg asks; Trade's board and the server's pathfinder read it. 0440 moved
--   69 roadsteads and re-sailed the remembered courses and left the table as it was. FAILS BEFORE 0442: 18 remembered courses crossed a sea their
--   pair's row did not hold, Galle's own row named a sea its roadstead had left, and no function could mend a row.
--
-- @pass PT_OWN     every harbour's own row names exactly the sea its roadstead lies in (public.harbour_zone); Galle's among them
-- @pass PT_LANES   every course the world remembers (public.npc_courses) crosses only seas its pair's row holds, read through the merchants' memo and sampled afresh by the door's sampler: the same answer
-- @pass PT_ASKS    every row of the table asks the most its seas and its destination's own sea ask, wave and title
-- @pass PT_KEEP    public.sea_leg_asks_keep() mends a row broken three ways (a lane's row cut to one sea, a harbour's own row given another sea, what a row asks set to nothing), moves nothing on a table in step, and never takes a sea away
-- ═══════════════════════════════════════════════════════════════════════════════

do $$
declare
  v_bad   text;
  v_n     int;
  v_lane  record;
  v_port  uuid;
  v_zone  text;
  v_other text;
  v_res   jsonb;
  v_before text;
begin
  -- PT_OWN
  select string_agg(p.code || ':' || public.harbour_zone(p.id) || '/' || array_to_string(s.zones, '+'), ' '), count(*) into v_bad, v_n
    from public.ports p join public.sea_leg_asks s on s.from_port = p.id and s.to_port = p.id
   where p.kind = 'HARBOUR' and s.zones is distinct from array[public.harbour_zone(p.id)];
  if v_n > 0 then
    raise exception 'PROOF 144 FAIL: own row(s) not their roadstead''s sea: %', v_bad;
  end if;
  if (select count(*) from public.sea_leg_asks s where s.from_port = s.to_port) <> (select count(*) from public.ports p where p.kind = 'HARBOUR') then
    raise exception 'PROOF 144 FAIL: not one own row a harbour';
  end if;
  raise notice 'PASS: PT_OWN — % harbours, each own row its roadstead''s sea; Galle lies in %',
    (select count(*) from public.ports p where p.kind = 'HARBOUR'), (select public.harbour_zone(p.id) from public.ports p where p.code = 'GAL');

  -- PT_LANES
  select string_agg(a.code || '-' || b.code, ' '), count(*) into v_bad, v_n
    from public.npc_courses n join public.sea_leg_asks s on s.from_port = n.from_port and s.to_port = n.to_port
    join public.ports a on a.id = n.from_port join public.ports b on b.id = n.to_port
   where not s.zones @> public.npc_course_zones(n.course) or public.npc_course_zones(n.course) is distinct from public.course_zones(n.course);
  if v_n > 0 or (select count(*) from public.npc_courses) < 100 then
    raise exception 'PROOF 144 FAIL: % remembered course(s) cross a sea their row does not hold, or the memo is not the sampler''s answer: %', v_n, left(v_bad, 600);
  end if;
  raise notice 'PASS: PT_LANES — all % remembered courses cross only seas their pair''s row holds (memo and sampler agree)', (select count(*) from public.npc_courses);

  -- PT_ASKS
  select count(*) into v_n
    from public.sea_leg_asks s join public.sea_leg_asks own on own.from_port = s.to_port and own.to_port = s.to_port
   where (s.wave_min, s.title_min) is distinct from
         ((select max(z.wave_min) from public.sea_zones z where z.code = any (s.zones || own.zones))::int,
          (select max(z.title_min) from public.sea_zones z where z.code = any (s.zones || own.zones))::int);
  if v_n > 0 then
    raise exception 'PROOF 144 FAIL: % row(s) ask something other than the most their seas and their destination''s sea ask', v_n;
  end if;
  raise notice 'PASS: PT_ASKS — all % rows ask the most their seas and their destination''s own sea ask', (select count(*) from public.sea_leg_asks);

  -- PT_KEEP
  v_res := public.sea_leg_asks_keep();
  if v_res <> '{"own": 0, "lanes": 0, "asks": 0}'::jsonb then
    raise exception 'PROOF 144 FAIL: on a table in step the function moved rows: %', v_res;
  end if;
  select n.from_port, n.to_port, public.npc_course_zones(n.course) as zones into v_lane
    from public.npc_courses n where cardinality(public.npc_course_zones(n.course)) >= 2 order by n.from_port, n.to_port limit 1;
  select p.id, public.harbour_zone(p.id) into v_port, v_zone from public.ports p where p.kind = 'HARBOUR' and p.id not in (v_lane.from_port, v_lane.to_port) order by p.code limit 1;
  select z.code into v_other from public.sea_zones z where z.code <> v_zone order by z.code limit 1;
  select md5(string_agg(s.from_port::text || s.to_port::text || s.wave_min || ',' || s.title_min || array_to_string(s.zones, ' '), ';' order by s.from_port, s.to_port)) into v_before from public.sea_leg_asks s;
  update public.sea_leg_asks s set zones = v_lane.zones[1:1], wave_min = 0, title_min = 0 where s.from_port = v_lane.from_port and s.to_port = v_lane.to_port;
  update public.sea_leg_asks s set zones = array[v_other] where s.from_port = v_port and s.to_port = v_port;
  v_res := public.sea_leg_asks_keep();
  if (v_res ->> 'own')::int <> 1 or (v_res ->> 'lanes')::int <> 1 or (v_res ->> 'asks')::int < 1
     or not (select s.zones @> v_lane.zones from public.sea_leg_asks s where s.from_port = v_lane.from_port and s.to_port = v_lane.to_port)
     or (select s.zones from public.sea_leg_asks s where s.from_port = v_port and s.to_port = v_port) is distinct from array[v_zone] then
    raise exception 'PROOF 144 FAIL: the function did not mend the broken rows: %', v_res;
  end if;
  -- every other row is as it was: only the lane's row may differ from before (it holds its lane's seas; the seas of the plotted course it lost are the build's)
  if (select md5(string_agg(s.from_port::text || s.to_port::text || s.wave_min || ',' || s.title_min || array_to_string(s.zones, ' '), ';' order by s.from_port, s.to_port))
        from public.sea_leg_asks s) is distinct from v_before
     and (select count(*) from public.sea_leg_asks s where not (s.from_port = v_lane.from_port and s.to_port = v_lane.to_port)
            and (s.wave_min, s.title_min) is distinct from
                ((select max(z.wave_min) from public.sea_zones z where z.code = any (s.zones || (select o.zones from public.sea_leg_asks o where o.from_port = s.to_port and o.to_port = s.to_port)))::int,
                 (select max(z.title_min) from public.sea_zones z where z.code = any (s.zones || (select o.zones from public.sea_leg_asks o where o.from_port = s.to_port and o.to_port = s.to_port)))::int)) > 0 then
    raise exception 'PROOF 144 FAIL: mending the probe left another row out of step';
  end if;
  if has_function_privilege('authenticated', 'public.sea_leg_asks_keep()', 'execute') or has_function_privilege('anon', 'public.sea_leg_asks_keep()', 'execute') then
    raise exception 'PROOF 144 FAIL: a player may call public.sea_leg_asks_keep()';
  end if;
  raise notice 'PASS: PT_KEEP — a table in step: nothing moved; a lane''s row cut to one sea and a harbour''s own row given another: mended (%); no player may call it', v_res;
end
$$;
