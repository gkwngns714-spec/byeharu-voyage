-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 240 - A RESTART OVER THE ROUNDS AND THE CAPTAINS  (0509 over 0518 to 0535; the batch's own proof, no file's)
--
-- @pass RR_TOGETHER  one company: a fleet on an expedition, a captain's gathering and a captain's raid out at once; the jobs' tick and the reads serve all three
-- @pass RR_CLOSED    she restarts with all three out: no run, kept fight, artifact, work, upgrade or party of hers is left; what stays is the retired row's own record
-- @pass RR_COIN      purses and cities' books together are the same before and after, to the coin
-- @pass RR_AFTER     the jobs' tick runs after it, and the new company starts with none of it
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
do $p$
declare
  c_u constant uuid := '00000000-0240-4000-8000-0000000000a1';
  v_me uuid; v_new uuid; v_f uuid; v_lis uuid; v_a text; v_b text; v_act text; r jsonb; w jsonb; t record; v_n bigint; v_left text := ''; s0 numeric; s1 numeric;
begin
  v_me := public.new_house(c_u, 'Casa Recomeco 240', 'PRT');
  select f.id, f.port_id into v_f, v_lis from public.fleets f where f.player_id = v_me;
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury z set ducats = 10000000;
  update public.world_config set value = 'true'::jsonb where key in ('rounds_enabled', 'fleet_jobs_enabled', 'sea_courses_enabled', 'ship_stores_separate', 'ammo_enabled', 'combat_rounds_enabled', 'wrecks_yield_enabled',
    'expedition_rounds_enabled', 'artifacts_enabled', 'land_enabled', 'captain_works_enabled', 'land_raids_enabled', 'land_expedition_enabled', 'honor_enabled', 'reputation_on', 'city_treasury_enabled', 'economy_closed', 'restart_enabled');
  update public.world_config set value = '[30, 2]'::jsonb where key = 'land_crew_cap';
  update public.players set ducats = 300000 where id = v_me;
  insert into public.ledger (player_id, kind, ducats_delta, balance_after) select v_me, 'PROBE_240', 300000 - coalesce(sum(l.ducats_delta), 0), 300000 from public.ledger l where l.player_id = v_me;
  update public.ports set crew_pool = 400 where id = v_lis;
  update public.ships s set crew = (select sb.crew_max from public.ship_base(s.id) sb), food_t = 30, water_t = 40 where s.fleet_id = v_f;
  perform cmd.assume_identity(c_u);
  select o.code into v_a from public.officers o order by o.code limit 1;
  select o.code into v_b from public.officers o order by o.code offset 1 limit 1;
  perform public.sign_officer(v_me, v_a, null);
  perform public.sign_officer(v_me, v_b, null);
  select a.code into v_act from public.land_actions a where a.skill = 'mining' and a.kind <> 'make' and a.level = 1 and jsonb_typeof(public.land_terms(v_me, a.code)->'short') = 'null'
   order by (public.land_terms(v_me, a.code)->>'trip')::numeric, a.code limit 1;
  r := cmd.land_expedition(v_a, jsonb_build_object('work', 'land_gather', 'target', v_act, 'crew', 20));
  if not (r->>'ok')::boolean then raise exception 'RR_TOGETHER: gather %', r; end if;
  r := cmd.land_expedition(v_b, '{"work": "land_raid", "target": "wolves", "crew": 30, "stop": {"rounds": 40}}');
  if not (r->>'ok')::boolean then raise exception 'RR_TOGETHER: raid %', r; end if;
  r := cmd.round_send(v_f, 'expedition', '{"rounds": 3, "days": 0}');
  if not (r->>'ok')::boolean then raise exception 'RR_TOGETHER: expedition %', r; end if;
  insert into public.fleet_artifacts (fleet_id, tier, qty) values (v_f, 'uncommon', 2);
  call public.tick_fleet_jobs(false);
  w := world.rounds(v_f);
  if (select count(*) from public.round_runs x where x.player_id = v_me and x.state = 'out') <> 3 or jsonb_array_length(w->'runs') <> 1 or jsonb_array_length(world.land_expedition()->'runs') <> 2
     or (select f.status from public.fleets f where f.id = v_f) <> 'ROUNDS' then
    raise exception 'RR_TOGETHER: % / %', w->'runs', world.land_expedition()->'runs';
  end if;
  raise notice 'PASS: RR_TOGETHER - three runs out of one company';

  s0 := (select sum(p.ducats) from public.players p) + (select sum(public.treasury_balance(p.id)) from public.ports p where p.kind = 'HARBOUR') + (select coalesce(sum(c.accrued), 0) from public.city_shares c);
  r := cmd.restart_company('Casa Recomeco 240', 'Casa Recomeco Nova 240', 'PRT');
  if not (r->>'ok')::boolean then raise exception 'RR_CLOSED: %', r; end if;
  s1 := (select sum(p.ducats) from public.players p) + (select sum(public.treasury_balance(p.id)) from public.ports p where p.kind = 'HARBOUR') + (select coalesce(sum(c.accrued), 0) from public.city_shares c);
  for t in select c.relname from pg_class c join pg_attribute a on a.attrelid = c.oid and a.attname = 'player_id' and not a.attisdropped
            where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and a.atttypid = 'uuid'::regtype order by 1 loop
    execute format('select count(*) from public.%I where player_id = $1', t.relname) into v_n using v_me;
    if v_n > 0 then v_left := v_left || t.relname || ' '; end if;
  end loop;
  for t in select c.relname from pg_class c join pg_attribute a on a.attrelid = c.oid and a.attname = 'fleet_id' and not a.attisdropped
            where c.relnamespace = 'public'::regnamespace and c.relkind = 'r' and a.atttypid = 'uuid'::regtype and c.relname not in ('ledger') order by 1 loop
    execute format('select count(*) from public.%I where fleet_id = $1', t.relname) into v_n using v_f;
    if v_n > 0 then raise exception 'RR_CLOSED: % still names her fleet (% rows)', t.relname, v_n; end if;
  end loop;
  if v_left ~ '(round_runs|captain_upgrades|captain_work_xp|land_parties|player_officers)' then raise exception 'RR_CLOSED: left %', v_left; end if;
  raise notice 'PASS: RR_CLOSED - the retired row keeps rows in: %', v_left;
  if s1 <> s0 then raise exception 'RR_COIN: % became %', s0, s1; end if;
  raise notice 'PASS: RR_COIN - % before and after', s0;

  call public.tick_fleet_jobs(false);
  select p.id into v_new from public.players p where p.auth_uid = c_u;
  if v_new is null or v_new = v_me or jsonb_array_length(coalesce(world.land_expedition()->'runs', '[]')) <> 0 or jsonb_array_length(coalesce(world.rounds(null)->'runs', '[]')) <> 0
     or exists (select 1 from public.round_runs x where x.player_id in (v_me, v_new)) then
    raise exception 'RR_AFTER: % % %', v_new, world.rounds(null)->'runs', world.land_expedition()->'runs';
  end if;
  raise notice 'PASS: RR_AFTER';
end $p$;
