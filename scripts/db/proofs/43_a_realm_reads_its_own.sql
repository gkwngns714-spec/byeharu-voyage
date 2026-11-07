-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 43 — A REALM READS ITS OWN HARBOURS  (migration 0336: a performance fix, no behaviour change)
--
--   0336's self-assert holds the new read of public.cargo_origins to the OLD body on a probe realm of its own. This proof holds it to 0324's statement, typed below as the reference, on the REAL world and on the same probe
--   scenes, on the real engine, and it counts what the fence is for: the calls public.crown_call_room receives. The lit arm is dark on prod (convoy_rich_enabled false); here the proof lights it inside its rolled-back
--   transaction and sets every purse by its own hand. Subjects are picked by code, and the proof checks it has them.
--
-- @pass OF_DARK    off: every great power's origins are its capital, whatever its cities hold
-- @pass OF_SAME    lit, the real world, spread purses, a tie, a bare realm, four limits: every great power's origins are 0324's statement's, the same harbours in the same order
-- @pass OF_SCENES  a probe realm: the most room first and the lower code on a tie; the limit cuts it; a harbour that is only the start of a course, only the end of one, or on none; no room (0 and 1); another realm's richer harbour; a sea place; the capital when nothing has room
-- @pass OF_FENCE   lit: public.crown_call_room is asked of the realm's own harbours and no other; 0324's statement asks it of the world's, so the count can tell the two apart
-- ════════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  v_prt   uuid;
  v_jos   uuid;
  v_esp   uuid;
  v_t1    uuid;
  v_t2    uuid;
  v_nat   uuid;
  v_nat2  uuid;
  v_n     int;
  v_lim   int;
  v_big   int;
  v_new   uuid[];
  v_ref   uuid[];
  v_x     jsonb;
  v_ids   uuid[];
  v_ids0  uuid[];
  v_own   int;
  g       record;
  s       record;
begin
  -- the proof owns its preconditions
  update public.world_config set value = 'true'::jsonb where key = 'convoys_enabled';
  update public.world_config set value = 'false'::jsonb where key = 'convoy_rich_enabled';
  update public.world_config set value = to_jsonb(0.10) where key = 'crown_call_share';
  update public.world_config set value = to_jsonb(20) where key = 'crown_call_cover';
  update public.world_config set value = to_jsonb(50000) where key = 'treasury_reserve_floor';
  update public.world_config set value = to_jsonb(3) where key = 'convoy_rich_ports';
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;

  -- 0324's statement, as it stood when the fence was cut: THE reference. It is not a second rule: nothing calls it but this proof, and it is held to the live body only by what it answers.
  execute $f$
create function pg_temp.origins_0324(p_nation uuid)
returns uuid[]
language sql
stable
security definer
set search_path = public, pg_temp
as $b$
  select case when public.rich_cities_on()
              then coalesce((select array_agg(y.id order by y.room desc, y.code)
                               from (select h.id, h.code, x.room
                                       from public.ports h
                                      cross join lateral (select public.crown_call_room(h.id) as room) x
                                      where h.kind = 'HARBOUR' and public.port_nation(h.id) = p_nation and x.room > 0
                                        and exists (select 1 from public.npc_courses c where c.from_port = h.id or c.to_port = h.id)
                                      order by x.room desc, h.code
                                      limit public.wc_int('convoy_rich_ports')) y),
                            array[public.realm_capital(p_nation)])
              else array[public.realm_capital(p_nation)] end
$b$
  $f$;
  execute $f$
create function pg_temp.codes(p_ids uuid[])
returns text[]
language sql
as $b$
  select array_agg(p.code order by o.n) from unnest(p_ids) with ordinality o(id, n) join public.ports p on p.id = o.id
$b$
  $f$;

  -- ── SUBJECTS ──
  select g2.nation_id into v_prt from public.great_powers g2 join public.nations n on n.id = g2.nation_id where n.code = 'PRT';
  select g2.nation_id into v_jos from public.great_powers g2 join public.nations n on n.id = g2.nation_id where n.code = 'JOS';
  select g2.nation_id into v_esp from public.great_powers g2 join public.nations n on n.id = g2.nation_id where n.code = 'ESP';
  v_t1 := (select p.id from public.ports p where p.kind = 'HARBOUR' and public.port_nation(p.id) = v_prt
              and exists (select 1 from public.npc_courses c where c.from_port = p.id or c.to_port = p.id) order by p.code limit 1);
  v_t2 := (select p.id from public.ports p where p.kind = 'HARBOUR' and public.port_nation(p.id) = v_prt and p.id <> v_t1
              and exists (select 1 from public.npc_courses c where c.from_port = p.id or c.to_port = p.id) order by p.code limit 1);
  if v_prt is null or v_jos is null or v_esp is null or v_t1 is null or v_t2 is null then
    raise exception 'PROOF 43 FAIL: this proof needs three great powers and two harbours of Portugal on a course: % % % % %', v_prt, v_jos, v_esp, v_t1, v_t2;
  end if;

  -- Every purse by hand: a third of the harbours hold nothing, the rest differ by their code and their reserve; Portugal's two first harbours on a course tie at the top; Joseon holds nothing at all.
  update public.port_treasury t
     set ducats = case when x.n % 3 = 0 then 0 else 3000000 + x.n * 1000 end, reserve = x.n % 50000
    from (select p.id, abs(hashtextextended(p.code, 0)) % 1000000 as n from public.ports p) x
   where x.id = t.port_id;
  update public.port_treasury t set ducats = 5000000000, reserve = 0 where t.port_id in (v_t1, v_t2);   -- the spread tops out near 1,000,000,000, so these two stand above every other purse
  update public.port_treasury t set ducats = 0, reserve = 0 where public.port_nation(t.port_id) = v_jos;

  -- ── OFF ──
  v_n := 0;
  for g in select gp.nation_id as id from public.great_powers gp order by gp.nation_id loop
    if public.rich_cities_on() or public.cargo_origins(g.id) is distinct from array[public.realm_capital(g.id)] then
      raise exception 'PROOF 43 FAIL: off, an origin is not the capital: %', pg_temp.codes(public.cargo_origins(g.id));
    end if;
    v_n := v_n + 1;
  end loop;
  if v_n < 3 then
    raise exception 'PROOF 43 FAIL: the off arm was read over % realms', v_n;
  end if;
  raise notice 'PASS: OF_DARK — % realms, the switch off, every origin the capital, with purses that would have said otherwise', v_n;

  -- ── LIT, THE REAL WORLD ──
  update public.world_config set value = 'true'::jsonb where key = 'convoy_rich_enabled';
  if not public.rich_cities_on() then
    raise exception 'PROOF 43 FAIL: the switch does not light the rule';
  end if;
  v_big := 0;
  for v_lim in select * from unnest(array[1, 2, 3, 5]) loop
    update public.world_config set value = to_jsonb(v_lim) where key = 'convoy_rich_ports';
    for g in select gp.nation_id as id from public.great_powers gp order by gp.nation_id loop
      v_new := public.cargo_origins(g.id);
      v_ref := pg_temp.origins_0324(g.id);
      if v_new is distinct from v_ref then
        raise exception 'PROOF 43 FAIL: limit %, % reads % where 0324 read %', v_lim, g.id, pg_temp.codes(v_new), pg_temp.codes(v_ref);
      end if;
      if cardinality(v_new) > v_lim or (g.id in (v_prt, v_esp) and cardinality(v_new) <> v_lim) then
        raise exception 'PROOF 43 FAIL: limit %, % has % origins: the limit is not read over a roster that exceeds it: %', v_lim, g.id, cardinality(v_new), pg_temp.codes(v_new);
      end if;
      if v_lim = 5 and cardinality(v_new) = 5 then
        v_big := v_big + 1;
      end if;
    end loop;
    v_new := public.cargo_origins(v_prt);
    if v_new[1] is distinct from v_t1 or (v_lim >= 2 and v_new[2] is distinct from v_t2) then
      raise exception 'PROOF 43 FAIL: limit %, Portugal''s tie is not broken by the lower code: %', v_lim, pg_temp.codes(v_new);
    end if;
  end loop;
  if public.cargo_origins(v_jos) <> array[public.realm_capital(v_jos)] then
    raise exception 'PROOF 43 FAIL: a realm with nothing to give is not answered by its capital: %', pg_temp.codes(public.cargo_origins(v_jos));
  end if;
  if v_big < 2 then
    raise exception 'PROOF 43 FAIL: only % realms filled five places, so the limit was not read over a roster', v_big;
  end if;
  raise notice 'PASS: OF_SAME — every great power, limits 1, 2, 3 and 5, the same harbours in the same order as 0324''s statement; % realms filled five places; Portugal''s tie broken by code; Joseon, with nothing, answered by its capital', v_big;

  -- ── A PROBE REALM ──
  update public.world_config set value = to_jsonb(3) where key = 'convoy_rich_ports';
  insert into public.nations (code, name, flag_char, capital_port_code) values ('QX6', 'Probe 0336', 'Z', 'QYA'), ('QX7', 'Probe 0336 B', 'Y', 'QYZ');
  insert into public.great_powers (nation_id) select n.id from public.nations n where n.code in ('QX6', 'QX7');
  select n.id into v_nat from public.nations n where n.code = 'QX6';
  select n.id into v_nat2 from public.nations n where n.code = 'QX7';
  insert into public.ports (code, name, country, lat, lon, sea_id, region_id, culture, size_tier, max_draft, kind, approach)
  select x.code, 'Probe ' || x.code, t.country, t.lat, t.lon, t.sea_id, t.region_id, t.culture, t.size_tier, t.max_draft, x.kind, x.approach
    from (values ('QYA', 'HARBOUR', null), ('QYB', 'HARBOUR', null), ('QYC', 'HARBOUR', null), ('QYD', 'HARBOUR', null), ('QYE', 'HARBOUR', null), ('QYF', 'HARBOUR', null), ('QYG', 'HARBOUR', null),
                 ('QYZ', 'HARBOUR', null), ('QYS', 'SEA_PLACE', 'a probe')) x(code, kind, approach)
   cross join (select * from public.ports where kind = 'HARBOUR' order by code limit 1) t;
  insert into public.port_allegiance (port_id, nation_id) select p.id, case when p.code = 'QYZ' then v_nat2 else v_nat end from public.ports p where p.code like 'QY_';
  insert into public.port_treasury (port_id, ducats, reserve) select p.id, 0, 0 from public.ports p where p.code like 'QY_';
  insert into public.npc_courses (from_port, to_port, course, nm)
  select a.id, b.id, '[[0, 0], [1, 1]]'::jsonb, 1
    from (values ('QYB', 'QYE'), ('QYC', 'QYD'), ('QYG', 'QYA'), ('QYZ', 'QYC'), ('QYS', 'QYG')) v(f, t)
    join public.ports a on a.code = v.f join public.ports b on b.code = v.t;

  -- A donor's room is 10 % of what stands above 50,000 (reserve 0): ducats = 50,000 + 10 x room. QYB stands at room 1, QYG 9 d. over the floor, so at room 0; QYF is the richest of the realm and on no course;
  -- QYZ, richer still, is another realm's; QYS, a sea place, is the realm's and richer than all but QYZ.
  for s in select * from (values
    ('dark', false, 9, '{"QYA": 5050000, "QYB": 50010, "QYC": 9050000, "QYD": 9050000, "QYE": 3050000, "QYF": 20050000, "QYG": 50009, "QYS": 25050000, "QYZ": 50050000}'::jsonb, '["QYA"]'::jsonb),
    ('all',  true,  9, '{"QYA": 5050000, "QYB": 50010, "QYC": 9050000, "QYD": 9050000, "QYE": 3050000, "QYF": 20050000, "QYG": 50009, "QYS": 25050000, "QYZ": 50050000}'::jsonb, '["QYC", "QYD", "QYA", "QYE", "QYB"]'::jsonb),
    ('cut3', true,  3, '{"QYA": 5050000, "QYB": 50010, "QYC": 9050000, "QYD": 9050000, "QYE": 3050000, "QYF": 20050000, "QYG": 50009, "QYS": 25050000, "QYZ": 50050000}'::jsonb, '["QYC", "QYD", "QYA"]'::jsonb),
    ('cut1', true,  1, '{"QYA": 5050000, "QYB": 50010, "QYC": 9050000, "QYD": 9050000, "QYE": 3050000, "QYF": 20050000, "QYG": 50009, "QYS": 25050000, "QYZ": 50050000}'::jsonb, '["QYC"]'::jsonb),
    ('none', true,  3, '{"QYA": 0, "QYB": 0, "QYC": 0, "QYD": 0, "QYE": 0, "QYF": 0, "QYG": 0, "QYS": 0, "QYZ": 0}'::jsonb, '["QYA"]'::jsonb)
  ) v(name, lit, ports, purses, want) loop
    update public.world_config set value = to_jsonb(s.lit) where key = 'convoy_rich_enabled';
    update public.world_config set value = to_jsonb(s.ports) where key = 'convoy_rich_ports';
    update public.port_treasury t set ducats = (s.purses ->> p.code)::bigint from public.ports p where p.id = t.port_id and s.purses ? p.code;
    if s.name = 'all' and (select jsonb_object_agg(p.code, public.crown_call_room(p.id)) from public.ports p where p.code like 'QY_')
                          is distinct from '{"QYA": 500000, "QYB": 1, "QYC": 900000, "QYD": 900000, "QYE": 300000, "QYF": 2000000, "QYG": 0, "QYS": 2500000, "QYZ": 5000000}'::jsonb then
      raise exception 'PROOF 43 FAIL: the probe purses are not the rooms the scenes were built on';
    end if;
    v_x := jsonb_build_object('lit', public.rich_cities_on(), 'new', to_jsonb(pg_temp.codes(public.cargo_origins(v_nat))), 'ref', to_jsonb(pg_temp.codes(pg_temp.origins_0324(v_nat))));
    if (v_x ->> 'lit')::boolean is distinct from s.lit or v_x -> 'ref' is distinct from s.want then
      raise exception 'PROOF 43 FAIL: scene % is not what it was built to ask: %', s.name, v_x;
    end if;
    if v_x -> 'new' is distinct from s.want then
      raise exception 'PROOF 43 FAIL: scene %: the realm reads %, wanted %', s.name, v_x -> 'new', s.want;
    end if;
  end loop;
  raise notice 'PASS: OF_SCENES — five scenes on a probe realm: off the capital; the most room first, the lower code on a tie; the limit cuts; a course at one end counts, none does not; room 1 counts, 0 does not; another realm and a sea place do not; no room, the capital';

  -- ── THE FENCE ──
  -- A STABLE wrapper that notes every harbour it is asked about (set_config is allowed in a stable function; an insert is not), so the planner sees the same kind of function as the real one.
  alter function public.crown_call_room(uuid) rename to crown_call_room_real_43;
  execute $f$
create function public.crown_call_room(p_port uuid)
returns bigint
language plpgsql
stable
as $b$
begin
  perform set_config('byeharu.crc_43', coalesce(current_setting('byeharu.crc_43', true), '') || p_port::text || ',', true);
  return public.crown_call_room_real_43(p_port);
end
$b$
  $f$;
  update public.world_config set value = 'true'::jsonb where key = 'convoy_rich_enabled';
  update public.world_config set value = to_jsonb(3) where key = 'convoy_rich_ports';

  perform set_config('byeharu.crc_43', '', true);
  v_new := public.cargo_origins(v_esp);
  v_ids := string_to_array(rtrim(current_setting('byeharu.crc_43'), ','), ',')::uuid[];
  perform set_config('byeharu.crc_43', '', true);
  v_ref := pg_temp.origins_0324(v_esp);
  v_ids0 := string_to_array(rtrim(current_setting('byeharu.crc_43'), ','), ',')::uuid[];
  v_own := (select count(*) from public.ports p where p.kind = 'HARBOUR' and public.port_nation(p.id) = v_esp);
  if v_new is distinct from v_ref or cardinality(v_new) <> 3 then
    raise exception 'PROOF 43 FAIL: the fence scene is not a lit read of a rich realm: % against %', pg_temp.codes(v_new), pg_temp.codes(v_ref);
  end if;
  if not exists (select 1 from unnest(v_ids0) i where public.port_nation(i) is distinct from v_esp) then
    raise exception 'PROOF 43 FAIL: 0324''s statement was not seen asking about a harbour outside the realm, so this count cannot tell a fence from none (% calls)', cardinality(v_ids0);
  end if;
  if cardinality(v_ids) < v_own then
    raise exception 'PROOF 43 FAIL: the count saw % calls for a realm of % harbours: it is not seeing the reads', cardinality(v_ids), v_own;
  end if;
  if exists (select 1 from unnest(v_ids) i where public.port_nation(i) is distinct from v_esp) then
    raise exception 'PROOF 43 FAIL: public.crown_call_room was asked of a harbour outside the realm (% calls, % of them outside)', cardinality(v_ids), (select count(*) from unnest(v_ids) i where public.port_nation(i) is distinct from v_esp);
  end if;
  if cardinality(v_ids) > 2 * v_own then
    raise exception 'PROOF 43 FAIL: % calls for a realm of % harbours: more than twice each', cardinality(v_ids), v_own;
  end if;
  raise notice 'PASS: OF_FENCE — Spain, % harbours: the fenced read asked public.crown_call_room % times and never of another realm''s harbour; 0324''s statement asked % times, % of them of the others', v_own, cardinality(v_ids), cardinality(v_ids0), (select count(*) from unnest(v_ids0) i where public.port_nation(i) is distinct from v_esp);
end
$$;
