-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 215 - THE SEAS BY CONTINENT  (migration 0510; docs/design/owner-spec-plan-2026-11-25.md 0.1; the owner, 2026-11-25: "continent wise",
--             and of the eight rungs: "GOOD")
--
--   Read from the world's own pair table (public.sea_leg_asks: the seas of the course really sailed between every two harbours). Companies are this
--   proof's own; the switch is thrown inside the proof and rolled back by proof.mjs. No price, die, real company or date is read.
--
-- @pass SC_TABLE     the 64 seas ask the level of the approved table, and the counts a rung are 15, 7, 6, 2, 8, 18, 2, 6; no wave figure moved
-- @pass SC_REACH     from each of six European capitals the harbours open in all, rung by rung, are 89, 117, 138, 144, 177, 225, 230, 254; every harbour's earliest
--                    rung is its own sea's; all 254 are reachable at the top rung, 230 without one sealed sea, also with no leg over 6,800 nm
-- @pass SC_LONG_WAY  Recife to Busan: refused its stored course below rung 6's seas, open at rung 6 the long way round, no sealed sea on it; level 5 does not reach it
-- @pass SC_GATE      one gate: level k is refused by exactly the seas above rung k (public.sea_refusal), and the level is the lower of Trading and Exploration
-- @pass SC_KEPT      what she could reach stays hers: a company founded before 0510 is not refused a sea its old level opened, one founded since is; a company of Japan
--                    founded before keeps her old home rank's seas her hull holds
-- @pass SC_PATHS     lit, the board's pathfinder (voyage.reach_passage) offers no harbour of a sea shut to her, and its seas are the door's (public.sea_gate), for every
--                    harbour it offers in one leg
-- @pass SC_MERCHANT  the merchants' switch lit, a merchant's feasible legs are the same with the new levels and with the old ones written back
-- @pass SC_DARK      dark, the passage gate says nothing about a sea, and the Arctic stays ice north of Russia
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

create function pg_temp.open215(p_from text, p_rung int, p_nm numeric) returns text[] language plpgsql as $f$
declare
  v text[] := array[p_from];
  n int := 0;
begin
  while cardinality(v) > n loop
    n := cardinality(v);
    select array_agg(distinct q.c) into v from (select unnest(v) as c union select l.b from leg215 l where l.a = any (v) and l.rung <= p_rung and l.nm <= p_nm) q;
  end loop;
  return v;
end $f$;

do $p$
declare
  v_cap text;
  v_open text[];
  v_prev text[];
  v_got int[];
  v_bad text;
  v_pl uuid; v_pn uuid; v_pj uuid; v_fl uuid; v_fn uuid; v_fj uuid;
  v_lis uuid := (select id from public.ports where code = 'LIS');
  v_r jsonb;
  v_n int;
  v_t timestamptz;
  v_ms numeric;
  v_ms2 numeric;
  a jsonb; b jsonb;
  k int;
begin
  update public.world_config set value = 'false'::jsonb where key in ('sea_conditions_bite', 'sea_conditions_bite_npc');

  -- ── SC_TABLE ──
  select string_agg(q.code, ' ') into v_bad
    from (select z.code from public.sea_zones z
            left join (values (1, 'MED NEA NOR-EU BAL AEG BAY ENG ADR SEA ION IRI BLA NRW WHI BAR'), (2, 'NOR-MAC GUL SOU-ANG MOZ IND-EAF SOU-CAPE IND-S'),
                              (3, 'GCO CAR NOR-AM GCE NOR-ICE NOR-MID'), (4, 'SOU-BRA NOR-DOL'), (5, 'PER RED ARA LAC GLF GAN BYF IND-E'),
                              (6, 'SET GND YEL STR GIN KOR SOA EAS TAI JAV VIS AND MAK MOL PHI-JP NRT-JP BAN SFJ'), (7, 'TIM TAS'),
                              (8, 'NRT-AM STH-AM ARC PHI NRT-OPEN STH-OPEN')) t(rung, codes) on z.code = any (string_to_array(t.codes, ' '))
           where t.rung is distinct from z.title_min) q;
  select array_agg(q.n order by q.title_min) into v_got from (select z.title_min, count(*)::int as n from public.sea_zones z group by 1) q;
  if v_bad is not null or v_got <> array[15, 7, 6, 2, 8, 18, 2, 6] then
    raise exception 'PROOF 215 FAIL: the table: %, counts %', v_bad, v_got;
  end if;
  if (select array_agg(z.code || z.wave_min order by z.code) from public.sea_zones z where z.wave_min > 16)
     <> (select array_agg(u.x order by u.x) from unnest(string_to_array('ARC20 IND-E40 IND-S44 NOR-DOL24 NOR-ICE20 NOR-MID30 NRT-OPEN70 PHI50 SOU-CAPE44 STH-OPEN70 TAS56', ' ')) u(x)) then
    raise exception 'PROOF 215 FAIL: a wave figure over 16 moved: %', (select array_agg(z.code || z.wave_min order by z.code) from public.sea_zones z where z.wave_min > 16);
  end if;
  raise notice 'PASS: SC_TABLE - 64 seas on their rungs (%), the wave figures as they were', v_got;

  -- ── SC_REACH ──
  create temp table leg215 on commit drop as
  select a.code as a, b.code as b, s.title_min as rung, (ra.reaches ->> b.code)::numeric as nm
    from public.sea_leg_asks s
    join public.ports a on a.id = s.from_port and a.kind = 'HARBOUR' join public.ports b on b.id = s.to_port and b.kind = 'HARBOUR'
    join public.sea_reaches ra on ra.port_id = a.id
   where a.id <> b.id;
  create index on leg215 (a, rung);
  analyze leg215;
  foreach v_cap in array array['LIS', 'SVQ', 'LON', 'AMS', 'MRS', 'IST'] loop
    v_got := '{}'; v_prev := '{}';
    for k in 1 .. 8 loop
      v_open := pg_temp.open215(v_cap, k, 100000);
      v_got := v_got || cardinality(v_open);
      -- what this rung adds is exactly the harbours whose own sea is on it
      select string_agg(p.code, ' ') into v_bad
        from public.ports p join public.sea_leg_asks o on o.from_port = p.id and o.to_port = p.id join public.sea_zones z on z.code = o.zones[1]
       where p.kind = 'HARBOUR' and (z.title_min = k) <> (p.code = any (v_open) and not p.code = any (v_prev));
      if v_bad is not null then
        raise exception 'PROOF 215 FAIL: from % rung % does not add the harbours of its own seas: %', v_cap, k, v_bad;
      end if;
      v_prev := v_open;
    end loop;
    if v_got <> array[89, 117, 138, 144, 177, 225, 230, 254] then
      raise exception 'PROOF 215 FAIL: from % the rungs open %', v_cap, v_got;
    end if;
  end loop;
  if cardinality(pg_temp.open215('LIS', 8, 6800)) <> 254 or cardinality(pg_temp.open215('LIS', 7, 6800)) <> 230 then
    raise exception 'PROOF 215 FAIL: with no leg over 6,800 nm the top rung opens %, the rung under it %', cardinality(pg_temp.open215('LIS', 8, 6800)), cardinality(pg_temp.open215('LIS', 7, 6800));
  end if;
  raise notice 'PASS: SC_REACH - from six capitals % harbours rung by rung, each at its own sea''s rung; 254 at the top rung and 230 without a sealed sea, also with no leg over 6,800 nm', v_got;

  -- ── SC_LONG_WAY ──
  if not 'BUS' = any (pg_temp.open215('REC', 6, 100000)) or 'BUS' = any (pg_temp.open215('REC', 5, 100000)) then
    raise exception 'PROOF 215 FAIL: Recife to Busan is not open at rung 6 and shut at rung 5';
  end if;
  raise notice 'PASS: SC_LONG_WAY - Recife to Busan is open at rung 6 by harbours joined through seas of rung 6 and below, and shut at rung 5';

  -- ── SC_GATE ──
  for k in 1 .. 8 loop
    select string_agg(z.code, ' ') into v_bad from public.sea_zones z where (public.sea_refusal(k, null, array[z.code]) is not null) <> (z.title_min > k);
    if v_bad is not null then
      raise exception 'PROOF 215 FAIL: level % and the rule: %', k, v_bad;
    end if;
  end loop;
  v_pl := public.new_house('00000000-0510-4000-8000-0000000002a1', 'Casa Antes 215', 'PRT');
  v_pn := public.new_house('00000000-0510-4000-8000-0000000002a2', 'Casa Depois 215', 'PRT');
  select id into v_fl from public.fleets where player_id = v_pl;
  select id into v_fn from public.fleets where player_id = v_pn;
  v_r := public.player_progress(v_pl);
  if public.title_level(v_pl) <> least((v_r->'trading'->>'level')::int, (v_r->'exploration'->>'level')::int) then
    raise exception 'PROOF 215 FAIL: the level is not the lower of the two: % of %', public.title_level(v_pl), v_r;
  end if;
  raise notice 'PASS: SC_GATE - level k is refused by exactly the seas above rung k; the level is the lower of Trading and Exploration (%)', public.title_level(v_pl);

  -- ── SC_KEPT ──
  update public.players set created_at = (public.wc('seas_by_continent_at') #>> '{}')::timestamptz - interval '1 day' where id = v_pl;
  update public.players set created_at = (public.wc('seas_by_continent_at') #>> '{}')::timestamptz + interval '1 day' where id = v_pn;
  v_pj := public.new_house('00000000-0510-4000-8000-0000000002a3', 'Casa Seto 215', 'JPN');
  select id into v_fj from public.fleets where player_id = v_pj;
  update public.players set created_at = (public.wc('seas_by_continent_at') #>> '{}')::timestamptz - interval '1 day' where id = v_pj;
  -- Japan's old home rank was 7: Bengal (now 5) held her barca's wave and is kept; the Pacific's 8 never was hers
  if public.seas_kept(v_fl) <> '{}' or public.seas_kept(v_fn) <> '{}'
     or not 'BYF' = any (public.seas_kept(v_fj)) or public.seas_kept(v_fj) && array['PHI', 'NRT-OPEN', 'MED'] or 'TIM' = any (public.seas_kept(v_fj)) then
    raise exception 'PROOF 215 FAIL: kept: level 1 %, since %, Japan %', public.seas_kept(v_fl), public.seas_kept(v_fn), public.seas_kept(v_fj);
  end if;
  update public.world_config set value = 'true'::jsonb where key = 'sea_conditions_bite';
  if public.sea_gate(v_pj, v_fj, (select p.id from public.ports p join public.sea_leg_asks o on o.from_port = p.id and o.to_port = p.id where o.zones[1] = 'BYF' order by p.code limit 1), null) is not null then
    raise exception 'PROOF 215 FAIL: the kept sea refuses her at the door';
  end if;
  -- the Arctic, the one sea that asks more: its old 3 is planted at 1 (a level cannot be given), its waves at 0
  update public.sea_zones set title_was = 1, wave_min = 0 where code = 'ARC';
  select p.id into v_pj from public.ports p join public.sea_leg_asks o on o.from_port = p.id and o.to_port = p.id where o.zones[1] = 'ARC' order by p.code limit 1;
  if public.sea_gate(v_pl, v_fl, v_pj, null) is not null or (public.sea_gate(v_pn, v_fn, v_pj, null)->'figures'->>'zone') is distinct from 'ARC' then
    raise exception 'PROOF 215 FAIL: the Arctic: before %, since %', public.sea_gate(v_pl, v_fl, v_pj, null), public.sea_gate(v_pn, v_fn, v_pj, null);
  end if;
  update public.sea_zones set title_was = 3, wave_min = 20 where code = 'ARC';
  raise notice 'PASS: SC_KEPT - a company founded before keeps the sea its old level opened, one founded since is refused it; Japan keeps %', public.seas_kept(v_fj);

  -- ── SC_PATHS ──
  v_t := clock_timestamp();
  perform count(*) from voyage.reach_passage(v_pn, v_fn, v_lis, null);
  v_ms := round(extract(epoch from clock_timestamp() - v_t) * 1000);
  v_prev := public.sea_closed(v_pn, v_fn);
  select string_agg(r.code, ' '), count(*) into v_bad, v_n
    from voyage.reach_passage(v_pn, v_fn, v_lis, null) r
    join public.sea_leg_asks o on o.from_port = r.port_id and o.to_port = r.port_id
   where r.nm is not null and o.zones && v_prev;
  if v_n > 0 then
    raise exception 'PROOF 215 FAIL: the pathfinder offers harbours of shut seas: %', v_bad;
  end if;
  select string_agg(r.code, ' '), count(*) into v_bad, v_n
    from voyage.reach_passage(v_pn, v_fn, v_lis, null) r
   where r.nm is not null and r.stops = '{}' and public.sea_gate(v_pn, v_fn, r.port_id, public.sea_course(v_lis, r.port_id)) is not null;
  if v_n > 0 then
    raise exception 'PROOF 215 FAIL: the pathfinder offers a leg the door refuses: %', v_bad;
  end if;
  select count(*) into v_n from voyage.reach_passage(v_pn, v_fn, v_lis, null) r where r.nm is not null;
  if v_n < 60 then
    raise exception 'PROOF 215 FAIL: a new company''s pathfinder offers only % harbours', v_n;
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'sea_conditions_bite';
  v_t := clock_timestamp();
  perform count(*) from voyage.reach_passage(v_pn, v_fn, v_lis, null);
  v_ms2 := round(extract(epoch from clock_timestamp() - v_t) * 1000);
  update public.world_config set value = 'true'::jsonb where key = 'sea_conditions_bite';
  raise notice 'PASS: SC_PATHS - lit, a new barca company at Lisbon is offered % harbours, none in a shut sea, every one-leg one open at the door', v_n;
  raise notice 'TIMING: the pathfinder from Lisbon: lit % ms, dark % ms', v_ms, v_ms2;
  v_t := clock_timestamp();
  for k in 1 .. 20 loop perform public.seas_kept(v_fl); end loop;
  raise notice 'TIMING: public.seas_kept % ms a read (what a lit departure adds)', round((extract(epoch from clock_timestamp() - v_t) * 50)::numeric, 2);

  -- ── SC_MERCHANT ──
  update public.world_config set value = 'true'::jsonb where key = 'sea_conditions_bite_npc';
  select jsonb_object_agg(q.fleet_id, q.j) into a
    from (select nf.fleet_id, public.npc_feasible_legs(f.port_id, nf.fleet_id, 5, 400) as j
            from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id where f.port_id is not null order by nf.roster_ord limit 60) q;
  begin
    update public.sea_zones set title_min = title_was;
    select jsonb_object_agg(q.fleet_id, q.j) into b
      from (select nf.fleet_id, public.npc_feasible_legs(f.port_id, nf.fleet_id, 5, 400) as j
              from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id where f.port_id is not null order by nf.roster_ord limit 60) q;
    raise exception using errcode = 'ZY215', message = 'ROLLBACK';
  exception when sqlstate 'ZY215' then null;
  end;
  if a is null or a is distinct from b then
    raise exception 'PROOF 215 FAIL: a merchant''s legs moved with the continents';
  end if;
  raise notice 'PASS: SC_MERCHANT - % merchant fleets, the merchants'' rule lit: the same legs with the new levels and with the old', (select count(*) from jsonb_object_keys(a));

  -- ── SC_DARK ──
  update public.world_config set value = 'false'::jsonb where key in ('sea_conditions_bite', 'sea_conditions_bite_npc');
  if exists (select 1 from public.ports p where p.kind = 'HARBOUR' and public.passage_gate(v_pn, v_fn, 100, p.id, null) is not null)
     or exists (select 1 from generate_series(70, 80, 2) la cross join generate_series(80, 170, 10) lo where voyage.sea_at(la, lo) is not null) then
    raise exception 'PROOF 215 FAIL: dark, a harbour is refused, or there is water north of Russia';
  end if;
  raise notice 'PASS: SC_DARK - dark, no sea refuses; the Arctic stays ice north of Russia';
end
$p$;
