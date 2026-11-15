-- ═══════════════════════════════════════════════════════════════════════════════
-- PROOF 150 - THE STATS COUNT ONCE  (migration 0448; docs/STATS_ONE_COUNT.md; docs/dev-log/2026-11-16-stats-one.md)
--
--   The owner, 2026-11-16: "stats is messed up. the ships at sea, in port, laid up, wrecked are all different numbers. i want you to make it so
--   that this error does not happen again." A world with merchants, cargo ships of every realm, two navy ships and three pirate ships, with EVERY
--   state present: fleets at sea, in port, in a battle (held under sail, and IN_BATTLE in a harbour), laid up, wrecked (no hull, a pirate's wreck
--   lying, UNABLE_TO_SAIL), and a HIDDEN fleet (a retired cargo ship). Then the Stats count runs and every face is read.
--   Rolled back by proof.mjs's transaction.
--
-- @pass ONE_STATE     every fleet is in the census once, in one of the five states; each planted fleet reads the state its facts give, by the one order (laid_up, wrecked, battle, sea, port); a retired cargo ship reads laid_up and is not counted
-- @pass ONE_IDENTITY  for every kind, fleets = sea + port + battle + laid_up + wrecked and ships = the sum of ships_by; every one of the five states is present in the world; the retired cargo ship is in no figure
-- @pass ONE_COUNT     after the Stats count: the Ships face's card of every kind equals that kind's own face (the Navy, Pirates and Cargo lists' headers, the Merchants face), figure for figure, with one counted time; each list's rows by state are its header
-- @pass ONE_PAGE      a fleet's own page (world.stats_fleet) says public.fleet_state's word, for a navy ship in a battle, a wrecked pirate and a cargo ship at sea
-- @pass ONE_RULE      no function of the game but public.fleet_state_of chooses one of the five words in a `case`, and the Stats' bodies read public.fleet_tally / public.fleet_census: a second rule cannot come back unseen
-- ═══════════════════════════════════════════════════════════════════════════════

do $p$
declare
  c_states constant text[] := array['sea', 'port', 'battle', 'laid_up', 'wrecked'];
  v_t     timestamptz := now();
  v_nat   uuid;
  v_capm  uuid;
  v_stn   uuid;
  v_n1    uuid;
  v_n2    uuid;
  v_p     uuid[] := '{}';
  v_cg    uuid[];
  v_m     uuid[];
  v_bat   uuid;
  v_made  int := 0;
  v_ta    jsonb;
  v_r     jsonb;
  v_l     jsonb;
  v_s     jsonb;
  v_k     text;
  v_bad   text;
  o       int;
  r       record;
begin
  update public.world_config set value = 'true'::jsonb
   where key in ('city_treasury_enabled', 'economy_closed', 'convoys_enabled', 'pirates_bite', 'npc_refits_enabled') and value is distinct from 'true'::jsonb;
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;

  -- ── THE WORLD (proof 132's): cargo ships of every realm, two navy ships, three pirate ships, and the chain's own merchants ──
  update public.cargo_fleet_sizes set ships = 5, read_at = now();
  for r in select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id
             join public.ports p on p.code = n.capital_port_code and p.kind = 'HARBOUR' where not g.pirate order by n.code loop
    v_made := v_made + public.cargo_ships_commission(r.nation_id);
  end loop;
  select g.nation_id, public.realm_capital(g.nation_id) into v_nat, v_capm from public.great_powers g
   where not g.pirate and public.realm_capital(g.nation_id) is not null and public.port_nation(public.realm_capital(g.nation_id)) = g.nation_id
     and exists (select 1 from public.cargo_ships c where c.nation_id = g.nation_id) order by g.nation_id limit 1;
  select a.port_id into v_stn from public.port_allegiance a
   where a.nation_id = v_nat and a.port_id <> v_capm and public.refit_yard(a.port_id) is not null order by a.port_id limit 1;
  update public.port_treasury t set ducats = 50000000 where t.port_id = v_capm;
  v_n1 := public.navy_commission(v_nat, 9001, v_capm, public.refit_yard(v_capm), v_stn, v_t - interval '3 days');
  v_n2 := public.navy_commission(v_nat, 9002, v_capm, public.refit_yard(v_capm), v_stn, v_t - interval '3 days');
  update public.port_treasury t set ducats = 975934180 where t.port_id = public.pirate_capital();
  for o in 1 .. 3 loop
    v_p := v_p || public.pirate_commission(o, public.pirate_home_of(o), public.refit_yard(public.pirate_home_of(o)), v_t - interval '2 days');
  end loop;
  select array_agg(z.fleet_id) into v_cg from (select c.fleet_id from public.cargo_ships c order by c.fleet_id limit 4) z;
  select array_agg(z.fleet_id) into v_m
    from (select nf.fleet_id from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id
           where nf.route_id is not null and f.status = 'DOCKED' and exists (select 1 from public.ships s where s.fleet_id = nf.fleet_id and s.durability > 0)
           order by nf.fleet_id limit 6) z;
  if v_made < 10 or v_n1 is null or v_n2 is null or coalesce(array_length(v_p, 1), 0) <> 3 or exists (select 1 from unnest(v_p) x where x is null)
     or coalesce(cardinality(v_cg), 0) <> 4 or coalesce(cardinality(v_m), 0) <> 6 then
    raise exception 'PROOF 150 FAIL: the world could not be built: % cargo ships, navy % %, pirates %, % merchants', v_made, v_n1, v_n2, v_p, cardinality(v_m);
  end if;
  if exists (select 1 from public.fleet_census() c where c.kind <> 'OTHER' and c.counted and c.state <> 'port') then
    raise exception 'PROOF 150 FAIL: the fresh world is not all in port: %', (select jsonb_agg(distinct c.state) from public.fleet_census() c where c.counted);
  end if;

  -- ── EVERY STATE, PLANTED ──
  -- at sea: a merchant, a cargo ship, the second pirate
  update public.fleets f set status = 'SAILING', port_id = null where f.id in (v_m[1], v_cg[1], v_p[2]);
  -- laid up: a merchant (her route paused), the first navy ship; and laid up AND wrecked AND in a battle (the third merchant): laid up comes first
  update public.standing_routes x set paused_reason = 'laid_up' where x.id in (select nf.route_id from public.npc_fleets nf where nf.fleet_id in (v_m[2], v_m[3]));
  update public.navy_ships n set laid_up_at = v_t where n.fleet_id = v_n1;
  update public.ships s set durability = 0 where s.fleet_id = v_m[3];
  -- wrecked: a merchant with no hull, a merchant UNABLE_TO_SAIL, a cargo ship with no hull, the first pirate's wreck lying at home
  update public.ships s set durability = 0 where s.fleet_id in (v_m[4], v_cg[2]);
  update public.fleets f set status = 'UNABLE_TO_SAIL' where f.id = v_m[5];
  update public.pirate_ships n set wrecked_at = v_t where n.fleet_id = v_p[1];
  -- in a battle: the second navy ship in a harbour (IN_BATTLE), the third pirate held under sail (SAILING, on a side), the sixth merchant on a side
  insert into public.battles (kind, site, started_at, resolves_at, status)
  values ('RAID', '{"lat": 0, "lon": 0}'::jsonb, v_t, v_t + interval '1 minute', 'FIGHTING') returning id into v_bat;
  insert into public.battle_sides (battle_id, fleet_id, side, joined_at, arrives_at) values
    (v_bat, v_p[3], 'ATTACKER', v_t, v_t), (v_bat, v_m[6], 'DEFENDER', v_t, v_t), (v_bat, v_m[3], 'DEFENDER', v_t, v_t);
  update public.fleets f set status = 'SAILING', port_id = null where f.id = v_p[3];
  update public.fleets f set status = 'IN_BATTLE' where f.id = v_n2;
  -- hidden: a retired cargo ship (0326 / 0437), wrecked too; and a battle that is over holds nobody
  update public.cargo_ships c set laid_up_at = v_t where c.fleet_id in (v_cg[3], v_cg[4]);
  update public.ships s set durability = 0 where s.fleet_id = v_cg[4];
  insert into public.battles (kind, site, started_at, resolves_at, status)
  values ('RAID', '{"lat": 0, "lon": 0}'::jsonb, v_t - interval '10 minutes', v_t - interval '9 minutes', 'RESOLVED') returning id into v_bat;
  insert into public.battle_sides (battle_id, fleet_id, side, joined_at, arrives_at) values (v_bat, v_m[1], 'DEFENDER', v_t, v_t);

  -- ── ONE_STATE ──
  if exists (select 1 from public.fleet_census() c group by c.fleet_id having count(*) > 1)
     or (select count(*) from public.fleet_census()) <> (select count(*) from public.fleets)
     or exists (select 1 from public.fleet_census() c where c.state is null or c.state <> all (c_states)) then
    raise exception 'PROOF 150 FAIL: the census is not one row a fleet in one of the five states';
  end if;
  select string_agg(format('%s: %s, wanted %s', x.who, coalesce(public.fleet_state(x.id), 'null'), x.want), '; ') into v_bad
    from (values ('a merchant under sail', v_m[1], 'sea'), ('a merchant laid up', v_m[2], 'laid_up'), ('a merchant laid up, wrecked and in a battle', v_m[3], 'laid_up'),
                 ('a merchant with no hull', v_m[4], 'wrecked'), ('a merchant UNABLE_TO_SAIL', v_m[5], 'wrecked'), ('a merchant on a side', v_m[6], 'battle'),
                 ('a navy ship laid up', v_n1, 'laid_up'), ('a navy ship IN_BATTLE', v_n2, 'battle'),
                 ('a pirate wreck lying', v_p[1], 'wrecked'), ('a pirate under sail', v_p[2], 'sea'), ('a pirate held under sail in a battle', v_p[3], 'battle'),
                 ('a cargo ship under sail', v_cg[1], 'sea'), ('a cargo ship with no hull', v_cg[2], 'wrecked'),
                 ('a retired cargo ship', v_cg[3], 'laid_up'), ('a retired cargo ship with no hull', v_cg[4], 'laid_up')) x(who, id, want)
   where public.fleet_state(x.id) is distinct from x.want;
  if v_bad is not null then
    raise exception 'PROOF 150 FAIL: %', v_bad;
  end if;
  if exists (select 1 from public.fleet_census() c where c.fleet_id in (v_cg[3], v_cg[4]) and c.counted)
     or exists (select 1 from public.fleet_census() c where c.kind <> 'CARGO' and c.kind <> 'OTHER' and not c.counted)
     or exists (select 1 from public.fleet_census() c where c.kind = 'OTHER' and c.counted)
     or public.fleet_state(gen_random_uuid()) is not null then
    raise exception 'PROOF 150 FAIL: who is counted: a retired cargo ship is, a ship in service is not, or a player''s fleet is';
  end if;
  raise notice 'PASS: ONE_STATE — % fleets, one row and one state each; 15 planted fleets read their state (laid up before wrecked before battle before sea); 2 retired cargo ships read laid_up and are not counted',
    (select count(*) from public.fleet_census());

  -- ── ONE_IDENTITY ──
  v_ta := public.fleet_tally();
  foreach v_k in array array['MERCHANT', 'NAVY', 'PIRATE', 'CARGO'] loop
    if (v_ta -> v_k ->> 'fleets')::int <> (select sum((v_ta -> v_k ->> s)::int) from unnest(c_states) s)
       or (v_ta -> v_k ->> 'ships')::int <> (select sum((v_ta -> v_k -> 'ships_by' ->> s)::int) from unnest(c_states) s)
       or (v_ta -> v_k ->> 'fleets')::int = 0 then
      raise exception 'PROOF 150 FAIL: the tally of % is not whole: %', v_k, v_ta -> v_k;
    end if;
  end loop;
  if (v_ta -> 'MERCHANT') - 'ships' - 'ships_by' - 'port' <> jsonb_build_object('fleets', (select count(*) from public.npc_fleets), 'sea', 1, 'battle', 1, 'laid_up', 2, 'wrecked', 2)
     or (v_ta -> 'NAVY') - 'ships' - 'ships_by' <> '{"fleets": 2, "sea": 0, "port": 0, "battle": 1, "laid_up": 1, "wrecked": 0}'::jsonb
     or (v_ta -> 'PIRATE') - 'ships' - 'ships_by' <> '{"fleets": 3, "sea": 1, "port": 0, "battle": 1, "laid_up": 0, "wrecked": 1}'::jsonb
     or (v_ta -> 'CARGO') - 'ships' - 'ships_by' - 'port' <> jsonb_build_object('fleets', (select count(*) from public.cargo_ships c where c.laid_up_at is null), 'sea', 1, 'battle', 0, 'laid_up', 0, 'wrecked', 1)
     or (v_ta #>> '{CARGO,ships}')::int <> (select count(*) from public.ships s join public.cargo_ships c on c.fleet_id = s.fleet_id where c.laid_up_at is null)
     or (v_ta #>> '{MERCHANT,ships}')::int <> (select count(*) from public.ships s join public.npc_fleets nf on nf.fleet_id = s.fleet_id) then
    raise exception 'PROOF 150 FAIL: the tally is not the planted world: %', v_ta;
  end if;
  if exists (select 1 from unnest(c_states) s where (select sum((v_ta -> k ->> s)::int) from unnest(array['MERCHANT', 'NAVY', 'PIRATE', 'CARGO']) k) = 0) then
    raise exception 'PROOF 150 FAIL: a state is in no kind of this world, so the proof would not see it: %', v_ta;
  end if;
  raise notice 'PASS: ONE_IDENTITY — merchants % = % at sea + % in port + % in battle + % laid up + % wrecked; navy 2, pirates 3, cargo % in service (2 retired in no figure); ships = ships_by for all four',
    v_ta #>> '{MERCHANT,fleets}', v_ta #>> '{MERCHANT,sea}', v_ta #>> '{MERCHANT,port}', v_ta #>> '{MERCHANT,battle}', v_ta #>> '{MERCHANT,laid_up}', v_ta #>> '{MERCHANT,wrecked}',
    v_ta #>> '{CARGO,fleets}';

  -- ── ONE_COUNT ── the Stats count, then every face
  perform public.tick_stats(v_t);
  v_r := world.stats_fleets();
  if (v_r ->> 'counted_at')::timestamptz is distinct from v_t then
    raise exception 'PROOF 150 FAIL: the Stats count did not write the fleets'' row: %', v_r - 'navy' - 'pirates' - 'cargo' - 'merchants';
  end if;
  for r in select * from (values ('MERCHANT', 'merchants'), ('NAVY', 'navy'), ('PIRATE', 'pirates'), ('CARGO', 'cargo')) k(kind, key) loop
    -- the Ships face's card is the tally (nothing moved since)
    if exists (select 1 from unnest(c_states || array['fleets', 'ships', 'ships_by']) s where (v_r -> r.key -> s) is distinct from (v_ta -> r.kind -> s)) then
      raise exception 'PROOF 150 FAIL: the Ships face''s % card is not the tally: % against %', r.key, v_r -> r.key, v_ta -> r.kind;
    end if;
    if r.kind = 'MERCHANT' then
      v_l := world.stats_merchants(null);
    else
      v_l := world.stats_fleet_list(r.kind);
      select coalesce(jsonb_object_agg(z.st, z.n), '{}'::jsonb) into v_s
        from (select e ->> 'state' as st, count(*) as n from jsonb_array_elements(v_l -> 'list') e group by 1) z;
      if exists (select 1 from unnest(c_states) s where (v_l ->> s)::int <> coalesce((v_s ->> s)::int, 0))
         or jsonb_array_length(v_l -> 'list') <> (v_l ->> 'fleets')::int
         or (select sum((e ->> 'ships')::int) from jsonb_array_elements(v_l -> 'list') e) <> (v_l ->> 'ships')::int then
        raise exception 'PROOF 150 FAIL: the % list''s rows are not its header: header %, rows %', r.kind, v_l - 'list' - 'day' - 'week', v_s;
      end if;
    end if;
    if (v_l ->> 'counted_at')::timestamptz is distinct from v_t
       or exists (select 1 from unnest(c_states || array['fleets', 'ships', 'ships_by']) s where (v_l -> s) is null or (v_l -> s) <> (v_r -> r.key -> s))
       or (v_l ->> 'fleets')::int <> (select sum((v_l ->> s)::int) from unnest(c_states) s) then
      raise exception 'PROOF 150 FAIL: the % face is not the Ships face''s card: % against %', r.kind, v_l - 'list' - 'series' - 'top' - 'bottom' - 'day' - 'week', v_r -> r.key;
    end if;
  end loop;
  if exists (select 1 from jsonb_array_elements(world.stats_fleet_list('CARGO') -> 'list') e where (e ->> 'id')::uuid in (v_cg[3], v_cg[4]))
     or world.stats_merchants(null) ?| array['sailing', 'docked', 'repairing', 'unable']
     or (v_r #>> '{merchants,houses}')::int <> (select count(*) from public.npc_houses) then
    raise exception 'PROOF 150 FAIL: a retired cargo ship is listed, or the Merchants face still serves a state of its own';
  end if;
  -- the count's merchants row (the charts): the same figures, in its columns
  if not exists (select 1 from public.stats_merchants m where m.at = v_t and m.fleets = (v_ta #>> '{MERCHANT,fleets}')::int and m.sailing = (v_ta #>> '{MERCHANT,sea}')::int
                    and m.docked = (v_ta #>> '{MERCHANT,port}')::int and m.unable = (v_ta #>> '{MERCHANT,wrecked}')::int and m.laid_up = (v_ta #>> '{MERCHANT,laid_up}')::int
                    and m.fleets = m.sailing + m.docked + m.repairing + m.unable + m.laid_up + (v_ta #>> '{MERCHANT,battle}')::int) then
    raise exception 'PROOF 150 FAIL: the count''s merchants row is not the tally: %', (select to_jsonb(m) - 'day' - 'top' - 'bottom' from public.stats_merchants m where m.at = v_t);
  end if;
  raise notice 'PASS: ONE_COUNT — counted once at %: Ships card = own face for merchants (%), navy (%), pirates (%) and cargo (%), each figure and ships_by; every list''s rows are its header; the retired cargo ships are in no list',
    v_t, v_r #>> '{merchants,fleets}', v_r #>> '{navy,fleets}', v_r #>> '{pirates,fleets}', v_r #>> '{cargo,fleets}';

  -- ── ONE_PAGE ──
  select string_agg(format('%s: page %s, state %s', x.who, world.stats_fleet(x.id) ->> 'state', public.fleet_state(x.id)), '; ') into v_bad
    from (values ('the navy ship in a battle', v_n2, 'battle'), ('the laid-up navy ship', v_n1, 'laid_up'), ('the pirate wreck', v_p[1], 'wrecked'),
                 ('the pirate in a battle', v_p[3], 'battle'), ('the cargo ship at sea', v_cg[1], 'sea'), ('the retired cargo ship', v_cg[3], 'laid_up')) x(who, id, want)
   where world.stats_fleet(x.id) ->> 'state' is distinct from x.want or public.fleet_state(x.id) is distinct from x.want;
  if v_bad is not null then
    raise exception 'PROOF 150 FAIL: a fleet''s page: %', v_bad;
  end if;
  raise notice 'PASS: ONE_PAGE — six pages say public.fleet_state''s word: battle, laid_up, wrecked, battle, sea, laid_up';

  -- ── ONE_RULE ── the guard: a state is chosen in ONE function
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v_bad
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('public', 'cmd', 'world', 'voyage') and p.prokind in ('f', 'p')
     and p.oid <> 'public.fleet_state_of(boolean,boolean,boolean,boolean)'::regprocedure
     -- THE TWO KNOWN OTHERS, neither a count nor a Stats figure, named so that a third is seen: public.merchant_doing_at (0097: what ONE merchant is
     -- doing, a sentence on her map card: `laid_up` there is any pause of her route) and world.report (a bug report's place: `port` or the open sea)
     and (n.nspname, p.proname) not in (('public', 'merchant_doing_at'), ('world', 'report'))
     and p.prosrc ~ $re$then\s+'(sea|port|battle|laid_up|wrecked)'$re$;
  if v_bad is not null then
    raise exception 'PROOF 150 FAIL: a second rule: % choose(s) a fleet''s state in a `case` of its own. A state is chosen in public.fleet_state_of alone (docs/STATS_ONE_COUNT.md)', v_bad;
  end if;
  if exists (select 1 from unnest(array['public.stats_fleets_count(timestamptz,timestamptz)', 'public.stats_fleet_list_rows(text,timestamptz)', 'public.stats_merchant_fleets()']) f
              where (select p.prosrc from pg_proc p where p.oid = f::regprocedure) not like '%public.fleet_tally()%')
     or (select p.prosrc from pg_proc p where p.oid = 'world.stats_fleet(uuid)'::regprocedure) not like '%public.fleet_state(p_fleet)%'
     or (select p.prosrc from pg_proc p where p.oid = 'world.stats_merchants(text)'::regprocedure) like '%:= public.stats_merchant_fleets()%'
     or (select p.prosrc from pg_proc p where p.oid = 'public.fleet_tally()'::regprocedure) not like '%public.fleet_census()%'
     or (select p.prosrc from pg_proc p where p.oid = 'public.fleet_state(uuid)'::regprocedure) not like '%public.fleet_census(p_fleet)%'
     or (select count(*) from regexp_matches((select p.prosrc from pg_proc p where p.oid = 'public.tick_stats(timestamptz)'::regprocedure),
                                             'insert into public\.stats_fleets \(|insert into public\.stats_fleet_list \(', 'g')) <> 2
     or (select p.prosrc from pg_proc p where p.oid = 'public.tick_stats(timestamptz)'::regprocedure)
          !~ 'with l as \(\s+insert into public\.stats_fleet_list [^;]*insert into public\.stats_fleets \(' then
    raise exception 'PROOF 150 FAIL: a Stats body does not read the one count, or the count writes the fleets'' row and the lists in two statements';
  end if;
  raise notice 'PASS: ONE_RULE — no function but public.fleet_state_of chooses a state; the count, the lists, the merchants'' row and the page read the tally / the census; the count writes the row and the lists in one statement';
end $p$;
