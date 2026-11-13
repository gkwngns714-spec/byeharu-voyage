-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 73 — CROWN AND PIRATE HULLS FIGHT AT LEVEL FIVE, LIT  (migration 0372 lights npc_ship_level_enabled; 0344 built it)
--
--   Proof 51 proves the writer's rules in a world it sets dark and lights itself. This proof does NOT set the switch: it reads it as the chain left it (0372), makes a cargo ship,
--   a navy ship and a pirate ship by their REAL makers (public.cargo_ships_commission, public.navy_commission, public.pirate_commission) as the world's jobs do, runs the level job's
--   own command (select public.crown_hull_level_fix()), and reads each hull where a fight reads her (world.ship_stats, voyage.fleet_hulls). Then it measures the two things the
--   owner is told in the PR: a RAID on a company does not change with the level, and a fight that reads the crown hull itself does.
--
-- @pass LIT_BY_0372          the chain left npc_ship_level_enabled true and npc_ship_level 5, and 0372's news row is one row
-- @pass LIT_NEW_HULLS        a cargo, a navy and a pirate hull laid by their real makers AFTER the light hold no row until the job's command runs, and are level 5 after it; a second run writes 0
-- @pass LIT_STATS            with levels_bite on, each of the three reads +4 levels of handling, accuracy and sighting against her level-1 self, where the fight reads her; a merchant's hull and a company's are not written
-- @pass LIT_RAID_UNCHANGED   the pirate ship as a raider: voyage.pirate_strength, and 60 raid days of a company's barca against it through voyage.raid_report, are the same text at level 5 and at level 1
-- @pass LIT_HULLS_CHANGED    hull against hull (public.fight_sides, the way a battle reads her): the pirate hull's side carries her level-5 accuracy and sighting, and 200 fights differ from the level-1 fights
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  v_t      timestamptz := now();
  v_prt    uuid;
  v_lis    uuid;
  v_por    uuid;
  v_cargo  uuid;
  v_navy   uuid;
  v_pir    uuid;
  v_mer    uuid;
  v_hum    uuid;
  v_hfl    uuid;
  v_hsh    uuid;
  v_n      int;
  v_m      int;
  v_l1     jsonb;
  v_l5     jsonb;
  v_side5  jsonb;
  v_side1  jsonb;
  v_mxp    text;
  v_a      jsonb;
  v_esc    numeric;
  v_fig5   numeric;
  v_fig1   numeric;
  v_raid5  text;
  v_raid1  text;
  v_f5     text;
  v_f1     text;
  v_k      text;
begin
  -- AS THE CHAIN LEFT IT
  if public.wc('npc_ship_level_enabled') is distinct from 'true'::jsonb or public.wc_num('npc_ship_level') <> 5
     or (select count(*) from public.world_news w where w.key = 'update:0372') <> 1 then
    raise exception 'PROOF 73 FAIL: the chain did not leave npc_ship_level_enabled true, npc_ship_level 5 and one news row of 0372';
  end if;
  raise notice 'PASS: LIT_BY_0372 — npc_ship_level_enabled true, npc_ship_level 5, one news row "update:0372"';

  -- ── THE SCENE (proof 51's): the treasuries lit as on prod, one hull of each crown kind made by its real maker ──
  update public.world_config set value = 'true'::jsonb
   where key in ('city_treasury_enabled', 'economy_closed', 'convoys_enabled', 'navy_enabled', 'pirates_bite', 'levels_bite', 'combat_bite');
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  select g.nation_id, p.id into v_prt, v_lis
    from public.great_powers g join public.nations n on n.id = g.nation_id join public.ports p on p.code = n.capital_port_code and p.kind = 'HARBOUR' where n.code = 'PRT';
  v_por := public.pirate_capital();
  if v_prt is null or v_por is null then
    raise exception 'PROOF 73 FAIL: Portugal''s capital or the Brethren''s are not in this world';
  end if;
  update public.port_treasury t set reserve = 0 where t.port_id in (v_lis, v_por);
  perform public.treasury_post(v_lis, 'CROWN_CALL', 50000000, null, null, true);
  perform public.treasury_post(v_por, 'CROWN_CALL', 300000000, null, null, true);
  update public.cargo_fleet_sizes set ships = 1, read_at = v_t where nation_id = v_prt;
  if public.cargo_ships_commission(v_prt) < 1 then
    raise exception 'PROOF 73 FAIL: the real maker made no cargo ship';
  end if;
  v_cargo := (select c.fleet_id from public.cargo_ships c where c.nation_id = v_prt order by c.ord limit 1);
  insert into public.navy_realms (nation_id, ships, read_at) values (v_prt, 25, v_t) on conflict (nation_id) do update set ships = 25, read_at = v_t;
  v_navy := public.navy_commission(v_prt, 1 + coalesce((select max(n.ord) from public.navy_ships n where n.nation_id = v_prt), 0), v_lis, public.refit_yard(v_lis), v_lis, v_t);
  v_pir := public.pirate_commission(1 + coalesce((select max(x.ord) from public.pirate_ships x), 0), v_por, public.refit_yard(v_por), v_t);
  if v_navy is null or v_pir is null then
    raise exception 'PROOF 73 FAIL: the real makers made no navy ship (%) or pirate ship (%)', v_navy, v_pir;
  end if;
  v_mer := (select nf.fleet_id from public.npc_fleets nf order by nf.roster_ord limit 1);
  insert into public.players (company_name, nation_id, ducats) values ('Proof 73 house', v_prt, 300000) returning id into v_hum;
  v_hfl := public.form_fleet(v_hum, 'Proof 73 fleet', v_lis);
  v_hsh := public.commission_ship(v_hum, v_hfl, 'barca', 'Proof 73 barca', true, true);
  create temp table hulls_73 on commit drop as
    select s.id, s.fleet_id, f.kind from public.ships s
      join (values (v_cargo, 'cargo'), (v_navy, 'navy'), (v_pir, 'pirate')) f(fleet, kind) on f.fleet = s.fleet_id;
  if (select count(*) from hulls_73) <> 3 then
    raise exception 'PROOF 73 FAIL: the three kinds are not one hull each: %', (select count(*) from hulls_73);
  end if;
  v_mxp := (select md5(coalesce(string_agg(x.ship_id::text || ':' || x.xp::text, ',' order by x.ship_id), '')) from public.ship_xp x join public.ships s on s.id = x.ship_id where not public.crown_house(s.player_id));

  -- ── NEW HULLS, AFTER THE LIGHT: no row until the job's command runs ──
  if exists (select 1 from hulls_73 h join public.ship_xp x on x.ship_id = h.id) then
    raise exception 'PROOF 73 FAIL: a maker wrote a level row itself (the writer is public.crown_hull_level_fix alone)';
  end if;
  v_l1 := (select jsonb_object_agg(h.kind, world.ship_stats(h.id)) from hulls_73 h);
  v_side1 := voyage.fleet_hulls(v_pir);
  v_fig1 := voyage.pirate_strength(v_pir);
  v_n := public.crown_hull_level_fix();    -- the job's own command
  v_m := public.crown_hull_level_fix();
  if v_n < 3 or v_m <> 0
     or exists (select 1 from hulls_73 h left join public.ship_xp x on x.ship_id = h.id where x.xp is distinct from public.level_points(5) or public.level_from_points(x.xp) <> 5)
     or exists (select 1 from hulls_73 h where (world.ship_view(h.id) ->> 'level')::int is distinct from 5) then
    raise exception 'PROOF 73 FAIL: lit, the job''s command wrote % then %, or a new crown hull is not level 5', v_n, v_m;
  end if;
  raise notice 'PASS: LIT_NEW_HULLS — a cargo, a navy and a pirate hull laid after the light held no row; the job''s command wrote % row(s), each is level 5 (her card too); a second run wrote 0', v_n;

  -- ── THE STATS, WHERE THE FIGHT READS THEM ──
  v_l5 := (select jsonb_object_agg(h.kind, world.ship_stats(h.id)) from hulls_73 h);
  foreach v_k in array array['cargo', 'navy', 'pirate'] loop
    if (v_l5 -> v_k ->> 'handling')::numeric - (v_l1 -> v_k ->> 'handling')::numeric <> 4 * public.wc_num('ship_level_handling_per_level')
       or (v_l5 -> v_k ->> 'accuracy')::numeric - (v_l1 -> v_k ->> 'accuracy')::numeric <> 4 * public.wc_num('ship_level_accuracy_per_level')
       or (v_l5 -> v_k ->> 'sighting')::numeric - (v_l1 -> v_k ->> 'sighting')::numeric <> 4 * public.wc_num('ship_level_sighting_per_level')
       or ((v_l5 -> v_k) - 'handling' - 'accuracy' - 'sighting') <> ((v_l1 -> v_k) - 'handling' - 'accuracy' - 'sighting') then
      raise exception 'PROOF 73 FAIL: the % hull at level 5 against level 1: % against %', v_k, v_l5 -> v_k, v_l1 -> v_k;
    end if;
  end loop;
  v_side5 := voyage.fleet_hulls(v_pir);
  if (v_side5 -> 0 ->> 'accuracy')::numeric <> (v_l5 -> 'pirate' ->> 'accuracy')::numeric or (v_side5 -> 0 ->> 'sighting')::numeric <> (v_l5 -> 'pirate' ->> 'sighting')::numeric
     or (select md5(coalesce(string_agg(x.ship_id::text || ':' || x.xp::text, ',' order by x.ship_id), '')) from public.ship_xp x join public.ships s on s.id = x.ship_id where not public.crown_house(s.player_id)) <> v_mxp
     or exists (select 1 from public.ship_xp x where x.ship_id = v_hsh) then
    raise exception 'PROOF 73 FAIL: the fight''s side does not read the level-5 figures, or a merchant''s or a company''s row was written';
  end if;
  raise notice 'PASS: LIT_STATS — cargo, navy and pirate: handling +%, accuracy +%, sighting +% and nothing else; the pirate hull''s fight side reads accuracy % (level 1: %); no merchant''s or company''s row moved',
    4 * public.wc_num('ship_level_handling_per_level'), 4 * public.wc_num('ship_level_accuracy_per_level'), 4 * public.wc_num('ship_level_sighting_per_level'),
    v_side5 -> 0 ->> 'accuracy', v_side1 -> 0 ->> 'accuracy';

  -- ── A RAID DOES NOT READ THE LEVEL ──
  v_a := voyage.fleet_hulls(v_hfl);
  v_esc := voyage.escort_score(v_hfl);
  v_fig5 := voyage.pirate_strength(v_pir);
  select string_agg(voyage.raid_report(md5('proof73')::uuid, d, v_fig5, v_esc, v_a, '{}'::jsonb)::text, '|' order by d) into v_raid5 from generate_series(1, 60) d;
  select string_agg(voyage.raid_report(md5('proof73')::uuid, d, v_fig1, v_esc, v_a, '{}'::jsonb)::text, '|' order by d) into v_raid1 from generate_series(1, 60) d;
  if v_fig5 is distinct from v_fig1 or v_fig5 <= 0 or v_raid5 is distinct from v_raid1 then
    raise exception 'PROOF 73 FAIL: the pirate ship as a raider reads % at level 5 and % at level 1, or 60 raid days differ', v_fig5, v_fig1;
  end if;
  raise notice 'PASS: LIT_RAID_UNCHANGED — the pirate ship is a raid of % at level 5 and at level 1; 60 raid days of a company''s barca against it are the same text', round(v_fig5, 2);

  -- ── HULL AGAINST HULL DOES ──
  select string_agg((f ->> 'outcome') || ':' || (f -> 'hull' ->> 'a') || ':' || (f -> 'hull' ->> 'b'), '|' order by d) into v_f5
    from (select d, public.fight_sides(md5('proof73')::uuid, d, v_a, v_side5, '{}'::jsonb) as f from generate_series(1, 200) d) x;
  select string_agg((f ->> 'outcome') || ':' || (f -> 'hull' ->> 'a') || ':' || (f -> 'hull' ->> 'b'), '|' order by d) into v_f1
    from (select d, public.fight_sides(md5('proof73')::uuid, d, v_a, v_side1, '{}'::jsonb) as f from generate_series(1, 200) d) x;
  if v_f5 is not distinct from v_f1 or (v_side5 -> 0 ->> 'accuracy')::numeric <= (v_side1 -> 0 ->> 'accuracy')::numeric then
    raise exception 'PROOF 73 FAIL: hull against hull, 200 fights at level 5 are the level-1 fights';
  end if;
  raise notice 'PASS: LIT_HULLS_CHANGED — hull against hull the pirate hull shoots at accuracy % and sights at % (level 1: % and %), and 200 fights of a barca against her are not the level-1 fights',
    v_side5 -> 0 ->> 'accuracy', v_side5 -> 0 ->> 'sighting', v_side1 -> 0 ->> 'accuracy', v_side1 -> 0 ->> 'sighting';
end
$$;
