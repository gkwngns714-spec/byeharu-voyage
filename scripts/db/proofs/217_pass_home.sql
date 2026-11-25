-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 217 - PASS HOME  (migration 0513; docs/design/owner-spec-plan-2026-11-25.md 0.2; the owner: "A FLEET can always sail back home, even if it does not meet
--             the requirement")
--
--   Its own level-1 companies; the switch and the navigation figure are written here and rolled back by proof.mjs. The geography is the world's own (public.sea_leg_asks,
--   public.sea_reach_matrix); no price, die, real company or date is read.
--
-- @pass PH_ALL      from every one of the 254 harbours, for every capital a company can have and for legs of 1,700, 3,400 and 6,800 nm, a level-1 company whose hull holds nothing comes home
--                   on passes alone wherever she could with no seas asked; with 6,800 that is all 254
-- @pass PH_NARROW   a pass leads nearer home, or to the one harbour nearest home in reach; at home there is none; from a European capital's company, a pass out of a harbour
--                   of rung k enters no harbour above rung k but Fremantle's one, and none out of Europe leaves Europe
-- @pass PH_GATE     lit, at the real gate, a level-1 barca at Acapulco: home is open, Manila and Honolulu shut
-- @pass PH_SAMPLE   lit, the pathfinder (voyage.reach_passage) offers home from every far harbour of a spread (every eleventh), and every leg of the way it names is open at the
--                   gate when she lies at that leg's harbour
-- @pass PH_SEA      at anchor in the North Pacific she may make for the nearest harbour; a harbour further out stays shut
-- @pass PH_DARK     dark, the gate asks nothing; a merchant and nobody have no pass
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

create function pg_temp.home217(p_home text, p_reach float8, p_pass boolean) returns int language plpgsql as $f$
-- how many harbours come home: over the passes (true), or over every leg within the reach (false); each harbour is opened once
declare v uuid[]; f uuid[];
begin
  select array[p.id] into v from public.ports p where p.code = p_home;
  f := v;
  while cardinality(f) > 0 loop
    if p_pass then
      select array_agg(distinct x.from_port) into f from pass217 x join nm217 d on d.a = x.from_port and d.b = x.to_port
       where x.to_port = any (f) and d.nm <= p_reach and x.from_port <> all (v);
    else
      select array_agg(distinct d.a) into f from nm217 d where d.b = any (f) and d.nm <= p_reach and d.a <> all (v);
    end if;
    f := coalesce(f, '{}');
    v := v || f;
  end loop;
  return cardinality(v);
end $f$;

do $p$
declare
  v_me uuid; v_fl uuid; v_lis uuid := (select id from public.ports where code = 'LIS'); v_aca uuid := (select id from public.ports where code = 'ACA');
  r record; v_reach numeric; v_a int; v_b int; v_n int := 0; v_bad text; v_at uuid; v_stops text[]; v_hop int; v_x uuid; v_next text;
  v_t timestamptz; v_ms1 numeric; v_ms2 numeric; v_nm int; v_code text;
begin
  update public.world_config set value = 'false'::jsonb where key = 'sea_conditions_bite';
  v_me := public.new_house('00000000-0513-4000-8000-0000000002a1', 'Casa do Regresso 217', 'PRT');
  select id into v_fl from public.fleets where player_id = v_me;
  create temp table nm217 on commit drop as
    select m.ids[(u.o - 1) / cardinality(m.ids) + 1] as a, m.ids[(u.o - 1) % cardinality(m.ids) + 1] as b, u.v as nm
      from public.sea_reach_matrix m cross join lateral unnest(m.nm) with ordinality u(v, o) where m.id = 1 and u.v is not null;
  create index on nm217 (b, a); create index on nm217 (a, b); analyze nm217;
  create temp table pass217 (from_port uuid, to_port uuid, primary key (to_port, from_port)) on commit drop;

  -- ── PH_ALL and the narrowness of every set on the way ──
  for r in select distinct on (n.capital_port_code) n.id, n.code, n.capital_port_code as cap, z.title_min as rung
             from public.great_powers gp join public.nations n on n.id = gp.nation_id join public.ports p on p.code = n.capital_port_code and p.kind = 'HARBOUR'
             join public.sea_leg_asks o on o.from_port = p.id and o.to_port = p.id join public.sea_zones z on z.code = o.zones[1]
            order by n.capital_port_code, n.code loop
    update public.players set nation_id = r.id where id = v_me;
    foreach v_reach in array array[1700, 3400, 6800] loop
      update public.world_config set value = to_jsonb(v_reach) where key = 'nav_leg_nm_base';
      if public.passage_reach_nm(v_me) <> v_reach or public.title_level(v_me) <> 1 then
        raise exception 'PROOF 217 FAIL: the probe''s reach is % (want %), level %', public.passage_reach_nm(v_me), v_reach, public.title_level(v_me);
      end if;
      delete from pass217;
      insert into pass217 select x.from_port, x.to_port from public.sea_passes(v_me, null) x;
      analyze pass217;
      select p.id into v_x from public.ports p where p.code = r.cap;
      v_a := pg_temp.home217(r.cap, v_reach, false);
      v_b := pg_temp.home217(r.cap, v_reach, true);
      if v_a <> v_b or (v_reach = 6800 and v_b <> 254) then
        raise exception 'PROOF 217 FAIL: home % with legs of %: % harbours come home with no seas asked, % on passes', r.cap, v_reach, v_a, v_b;
      end if;
      if exists (select 1 from pass217 x join public.ports p on p.id = x.from_port where p.code = r.cap) then
        raise exception 'PROOF 217 FAIL: there is a pass out of home %', r.cap;
      end if;
      if r.rung = 1 then
        -- no pass goes up a rung, but the one out of a harbour with no other way (Fremantle, the shortest legs)
        select string_agg(a.code || '-' || b.code, ' '), count(*) into v_bad, v_hop
          from pass217 x join public.ports a on a.id = x.from_port join public.ports b on b.id = x.to_port
          join public.sea_leg_asks oa on oa.from_port = a.id and oa.to_port = a.id join public.sea_zones za on za.code = oa.zones[1]
          join public.sea_leg_asks ob on ob.from_port = b.id and ob.to_port = b.id join public.sea_zones zb on zb.code = ob.zones[1]
         where zb.title_min > za.title_min and not (a.code = 'FRE' and v_reach = 1700);
        if v_hop > 0 then
          raise exception 'PROOF 217 FAIL: home %, legs of %: passes that go up a rung: %', r.cap, v_reach, left(v_bad, 400);
        end if;
        -- away from home: only the one, out of a harbour none of whose passes nearer home is within her legs
        with pj as materialized (
          select x.from_port, x.to_port, hb.nm >= ha.nm as away, d.nm <= v_reach as within
            from pass217 x
            join nm217 d on d.a = x.from_port and d.b = x.to_port
            join nm217 ha on ha.a = x.from_port and ha.b = v_x
            join (select a, nm from nm217 where b = v_x union all select v_x, 0) hb on hb.a = x.to_port)
        select string_agg(q.from_port::text, ' '), count(*) into v_bad, v_hop
          from (select from_port from pj group by from_port having count(*) filter (where away) > 1 or (bool_or(away) and bool_or(within and not away))) q;
        if v_hop > 0 then
          raise exception 'PROOF 217 FAIL: home %, legs of %: passes away from home: %', r.cap, v_reach, left(v_bad, 400);
        end if;
      end if;
      v_n := v_n + 1;
    end loop;
  end loop;
  raise notice 'PASS: PH_ALL - % worlds (every capital a company can have, legs of 1,700, 3,400 and 6,800 nm): a level-1 company with no hull comes home on passes wherever the water lets her; with 6,800 from all 254', v_n;
  raise notice 'PASS: PH_NARROW - no pass out of home; none goes up a rung but Fremantle''s one with the shortest legs; none leads away from home while another way is open';

  -- ── PH_GATE ──
  update public.players set nation_id = (select id from public.nations where code = 'PRT') where id = v_me;
  update public.world_config set value = '6800'::jsonb where key = 'nav_leg_nm_base';
  update public.world_config set value = 'true'::jsonb where key = 'sea_conditions_bite';
  update public.fleets set port_id = v_aca where id = v_fl;
  if public.sea_gate(v_me, v_fl, v_lis, public.sea_course(v_aca, v_lis)) is not null
     or public.sea_gate(v_me, v_fl, (select id from public.ports where code = 'MNL'), null) is null
     or public.sea_gate(v_me, v_fl, (select id from public.ports where code = 'HNL'), null) is null then
    raise exception 'PROOF 217 FAIL: at Acapulco: home %, Manila %, Honolulu %', public.sea_gate(v_me, v_fl, v_lis, public.sea_course(v_aca, v_lis)),
      public.sea_gate(v_me, v_fl, (select id from public.ports where code = 'MNL'), null), public.sea_gate(v_me, v_fl, (select id from public.ports where code = 'HNL'), null);
  end if;
  raise notice 'PASS: PH_GATE - a level-1 barca at Acapulco: home open with its own course, Manila and Honolulu shut';

  -- ── PH_SAMPLE ── (every eleventh harbour above rung 1, by code; legs of 3,400 nm)
  update public.world_config set value = '3400'::jsonb where key = 'nav_leg_nm_base';
  v_n := 0; v_hop := 0;
  for r in select q.id, q.code from (select p.id, p.code, row_number() over (order by p.code) as k
                                       from public.ports p join public.sea_leg_asks o on o.from_port = p.id and o.to_port = p.id join public.sea_zones z on z.code = o.zones[1]
                                      where p.kind = 'HARBOUR' and z.title_min > 1) q where q.k % 11 = 0 order by q.code loop
    update public.fleets set port_id = r.id where id = v_fl;
    select x.stops || 'LIS'::text into v_stops from voyage.reach_passage(v_me, v_fl, r.id, null) x where x.code = 'LIS' and x.nm is not null;
    if v_stops is null then
      raise exception 'PROOF 217 FAIL: the pathfinder names no way home from %', r.code;
    end if;
    v_at := r.id;
    foreach v_next in array v_stops loop
      select p.id into v_x from public.ports p where p.code = v_next;
      if public.sea_gate(v_me, v_fl, v_x, public.sea_course(v_at, v_x)) is not null then
        raise exception 'PROOF 217 FAIL: on the way home from % the gate refuses the leg to % (%): %', r.code, v_next, v_stops, public.sea_gate(v_me, v_fl, v_x, public.sea_course(v_at, v_x));
      end if;
      update public.fleets set port_id = v_x where id = v_fl;
      v_at := v_x; v_hop := v_hop + 1;
    end loop;
    v_n := v_n + 1;
  end loop;
  if v_n < 12 then
    raise exception 'PROOF 217 FAIL: only % harbours were sampled', v_n;
  end if;
  raise notice 'PASS: PH_SAMPLE - from % far harbours the pathfinder names the way home and the gate opens each of its % legs to a level-1 barca', v_n, v_hop;

  -- ── PH_SEA ──
  update public.fleets set port_id = null, lat = 42, lon = -150, status = 'ANCHORED' where id = v_fl;
  v_x := public.harbour_nearest(42, -150);
  if public.sea_lies(v_fl) is distinct from v_x or public.sea_gate(v_me, v_fl, v_x, null) is not null
     or public.sea_gate(v_me, v_fl, (select p.id from public.ports p join public.sea_leg_asks o on o.from_port = p.id and o.to_port = p.id join public.sea_zones z on z.code = o.zones[1]
                                        where p.kind = 'HARBOUR' and z.title_min between 2 and 7 and not exists (select 1 from public.sea_passes(v_me, v_x) y where y.to_port = p.id)
                                        order by p.code limit 1), null) is null then
    raise exception 'PROOF 217 FAIL: at anchor in the North Pacific: nearest %, gate %', v_x, public.sea_gate(v_me, v_fl, v_x, null);
  end if;
  raise notice 'PASS: PH_SEA - at anchor in the North Pacific: the nearest harbour (%) is open, a harbour on no pass of hers is shut', (select code from public.ports where id = v_x);

  -- ── PH_DARK ──
  update public.fleets set port_id = v_aca, lat = null, lon = null, status = 'DOCKED' where id = v_fl;
  v_t := clock_timestamp(); perform public.sea_gate(v_me, v_fl, v_lis, null); v_ms1 := extract(epoch from clock_timestamp() - v_t) * 1000;
  v_t := clock_timestamp(); perform count(*) from voyage.reach_passage(v_me, v_fl, v_aca, null); v_ms2 := extract(epoch from clock_timestamp() - v_t) * 1000;
  raise notice 'TIMING: a refused leg at the gate, pass read: % ms; the pathfinder of a fleet beyond her rung: % ms', round(v_ms1, 1), round(v_ms2);
  update public.fleets set port_id = v_lis where id = v_fl;
  v_t := clock_timestamp(); perform count(*) from voyage.reach_passage(v_me, v_fl, v_lis, null); v_ms2 := extract(epoch from clock_timestamp() - v_t) * 1000;
  raise notice 'TIMING: the pathfinder of a fleet whose way home is open: % ms', round(v_ms2);
  update public.world_config set value = 'false'::jsonb where key = 'sea_conditions_bite';
  if public.sea_gate(v_me, v_fl, (select id from public.ports where code = 'MNL'), null) is not null or exists (select 1 from public.sea_passes_lit(v_me, v_fl))
     or exists (select 1 from public.sea_passes(null, v_aca)) or exists (select 1 from public.sea_passes((select nf.player_id from public.npc_fleets nf limit 1), v_aca)) then
    raise exception 'PROOF 217 FAIL: dark the gate asks, or a merchant or nobody has a pass';
  end if;
  raise notice 'PASS: PH_DARK - dark nothing is asked; no pass for a merchant or nobody';
end
$p$;
