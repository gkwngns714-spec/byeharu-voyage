-- ═══════════════════════════════════════════════════════════════════════════════
-- PROOF 132 - THE STATS OPEN EVERY FLEET  (migration 0431; docs/dev-log/2026-11-15-stats-fleet-tabs.md)
--
--   A world with cargo ships of every realm, two navy ships and three pirate ships. Each moment the book is written at is driven through the game's
--   own function (a navy-pirate fight, an hour's pay of both, a load and a delivery, a cargo ship's gold looted, a ransom, a pirate wreck reborn, a
--   battle closing) and the fleet's book, lines, the Stats count's list and the page are read after. Rolled back by proof.mjs's transaction.
--
-- @pass FB_FIGHT   public.navy_fight books both ships: the navy's fights, won/lost and hull lost; the pirate's navy_fights and hull lost; a FIGHT line each naming the other
-- @pass FB_PAY     public.navy_pay books an hour's upkeep (navy_upkeep_day / 24) to every navy ship it paid and none to one it did not; public.pirate_pay_hour books what it paid each pirate ship
-- @pass FB_GOLD    public.convoy_book books a load and a delivery to the cargo ship; public.pirate_loot_book books the gold to the pirate (loot, gold, paid; a TAKE line naming the cargo ship) and the loss to the cargo ship (looted); public.pirate_ransom books a ransom
-- @pass FB_STOP    public.fleet_book_stop books a navy's stop of a merchant: the fight, won, the fine paid, the prize at base value; a fleet that is no navy ship is not booked
-- @pass FB_REFIT   public.pirate_reborn books the wreck's refit (refits 1, repairs the cost paid) with a REFIT line
-- @pass FB_BATTLE  a battle that closes (status out of FIGHTING) books every navy, pirate and cargo ship that came: the raider's raid lost, the cargo ship attacked and held, the navy's fight won, each her hull lost by ship; a ship that came late is not booked
-- @pass FB_LIST    the Stats count writes one public.stats_fleet_list row a kind (each fleet in one state, her 7 days; the kind's 24 h and 7 d) and lets book hours and lines older than 8 days go; world.stats_fleet_list reads it back
-- @pass FB_PAGE    world.stats_fleet serves a cargo ship's gold rows (from the load's city, how long after it) and her day, a navy ship's ships, day and lines; and refuses any other fleet
-- ═══════════════════════════════════════════════════════════════════════════════

do $p$
declare
  v_t     timestamptz := now();
  v_nat   uuid;
  v_code  text;
  v_capm  uuid;
  v_stn   uuid;
  v_n1    uuid;
  v_n2    uuid;
  v_p     uuid[] := '{}';
  v_cg    uuid;
  v_cgp   uuid;
  v_cgn   uuid;
  v_cap   uuid;
  v_to    uuid;
  v_load  bigint;
  v_f     jsonb;
  v_b     jsonb;
  v_slice bigint := round(public.wc_num('navy_upkeep_day') / 24);
  v_paid  bigint;
  v_take  bigint;
  v_res   text;
  v_bat   uuid := gen_random_uuid();
  v_cs    uuid;
  v_ps    uuid;
  v_merch uuid;
  v_r     jsonb;
  v_made  int := 0;
  o       int;
  r       record;
begin
  update public.world_config set value = 'true'::jsonb
   where key in ('city_treasury_enabled', 'economy_closed', 'convoys_enabled', 'pirates_bite', 'npc_refits_enabled') and value is distinct from 'true'::jsonb;
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  if exists (select 1 from public.fleet_book) or exists (select 1 from public.fleet_lines) or exists (select 1 from public.stats_fleet_list) then
    raise exception 'PROOF 132 FAIL: the world already holds a book';
  end if;

  -- CARGO SHIPS: five a realm
  update public.cargo_fleet_sizes set ships = 5, read_at = now();
  for r in select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id
             join public.ports p on p.code = n.capital_port_code and p.kind = 'HARBOUR' where not g.pirate order by n.code loop
    v_made := v_made + public.cargo_ships_commission(r.nation_id);
  end loop;
  if v_made < 10 then
    raise exception 'PROOF 132 FAIL: % cargo ships made', v_made;
  end if;

  -- THE NAVY: two ships of one realm, at work
  select g.nation_id, public.realm_capital(g.nation_id), n.code into v_nat, v_capm, v_code from public.great_powers g join public.nations n on n.id = g.nation_id
   where not g.pirate and public.realm_capital(g.nation_id) is not null and public.port_nation(public.realm_capital(g.nation_id)) = g.nation_id
     and exists (select 1 from public.cargo_ships c where c.nation_id = g.nation_id) order by g.nation_id limit 1;
  select a.port_id into v_stn from public.port_allegiance a
   where a.nation_id = v_nat and a.port_id <> v_capm and public.refit_yard(a.port_id) is not null order by a.port_id limit 1;
  update public.port_treasury t set ducats = 50000000 where t.port_id = v_capm;
  v_n1 := public.navy_commission(v_nat, 9001, v_capm, public.refit_yard(v_capm), v_stn, v_t - interval '3 days');
  v_n2 := public.navy_commission(v_nat, 9002, v_capm, public.refit_yard(v_capm), v_stn, v_t - interval '3 days');
  if v_n1 is null or v_n2 is null then
    raise exception 'PROOF 132 FAIL: no navy ship could be built';
  end if;

  -- THE PIRATES: three of 0339's ships at their homes
  update public.port_treasury t set ducats = 975934180 where t.port_id = public.pirate_capital();
  for o in 1 .. 3 loop
    v_p := v_p || public.pirate_commission(o, public.pirate_home_of(o), public.refit_yard(public.pirate_home_of(o)), v_t - interval '2 days');
  end loop;
  if coalesce(array_length(v_p, 1), 0) <> 3 or exists (select 1 from unnest(v_p) x where x is null) then
    raise exception 'PROOF 132 FAIL: the pirate ships could not be built: %', v_p;
  end if;

  -- ── FB_FIGHT ──
  v_f := public.navy_fight(v_n1, v_p[1], v_t);
  select b.figs into v_b from public.fleet_book b where b.fleet_id = v_n1;
  if v_b is null or (v_b ->> 'fights')::int <> 1 or coalesce((v_b ->> 'won')::int, 0) + coalesce((v_b ->> 'lost')::int, 0) <> (v_f ->> 'result' <> 'DREW')::int
     or coalesce((v_b ->> 'sunk')::int, 0) <> (v_f ->> 'result' = 'SUNK')::int
     or coalesce((v_b ->> 'hull')::numeric, 0) <> round((select coalesce(sum(h.value::numeric), 0) from jsonb_each_text(coalesce(v_f -> 'hull_lost' -> 'navy', '{}'::jsonb)) h), 1) then
    raise exception 'PROOF 132 FAIL: the navy''s book after the fight: % (the fight %)', v_b, v_f;
  end if;
  select b.figs into v_b from public.fleet_book b where b.fleet_id = v_p[1];
  if v_b is null or (v_b ->> 'navy_fights')::int <> 1
     or coalesce((v_b ->> 'hull')::numeric, 0) <> round((select coalesce(sum(h.value::numeric), 0) from jsonb_each_text(coalesce(v_f -> 'hull_lost' -> 'pirate', '{}'::jsonb)) h), 1)
     or (select l.line ->> 'foe' from public.fleet_lines l where l.fleet_id = v_n1 and l.kind = 'FIGHT') is distinct from (select f.name from public.fleets f where f.id = v_p[1])
     or (select l.line ->> 'foe' from public.fleet_lines l where l.fleet_id = v_p[1] and l.kind = 'FIGHT') is distinct from (select f.name from public.fleets f where f.id = v_n1)
     or (select l.line ->> 'nation' from public.fleet_lines l where l.fleet_id = v_p[1] and l.kind = 'FIGHT') <> v_code then
    raise exception 'PROOF 132 FAIL: the pirate''s book or the lines after the fight: %', v_b;
  end if;
  raise notice 'PASS: FB_FIGHT — the navy %: fights 1, hull % lost; the pirate: navy_fights 1, hull % lost; a FIGHT line each naming the other', v_f ->> 'result',
    (select b.figs ->> 'hull' from public.fleet_book b where b.fleet_id = v_n1), v_b ->> 'hull';

  -- ── FB_PAY ── (the fight's hour stamps are cleared so each ship is plainly at work)
  insert into public.navy_realms as r2 (nation_id) values (v_nat) on conflict (nation_id) do update set paid_at = null;
  v_paid := public.navy_pay(v_t, v_nat);
  if not exists (select 1 from public.navy_ships n where n.nation_id = v_nat and n.unpaid_since is null)
     or (select r2.paid_at from public.navy_realms r2 where r2.nation_id = v_nat) is distinct from v_t then
    raise exception 'PROOF 132 FAIL: the navy pay paid no ship (moved %)', v_paid;
  end if;
  if exists (select 1 from public.navy_ships_in_service n left join public.fleet_book b on b.fleet_id = n.fleet_id
              where n.nation_id = v_nat and n.unpaid_since is null and coalesce((b.figs ->> 'upkeep')::bigint, 0) <> v_slice)
     or exists (select 1 from public.navy_ships_in_service n join public.fleet_book b on b.fleet_id = n.fleet_id
                 where n.nation_id = v_nat and n.unpaid_since is not null and b.figs ? 'upkeep') then
    raise exception 'PROOF 132 FAIL: the navy''s upkeep is not booked a ship paid: %', (select jsonb_agg(jsonb_build_object('u', n.unpaid_since, 'b', b.figs)) from public.navy_ships_in_service n left join public.fleet_book b on b.fleet_id = n.fleet_id where n.nation_id = v_nat);
  end if;
  update public.pirate_clock set paid_at = null;
  perform public.pirate_pay_hour(v_t);
  if exists (select 1 from public.pirate_ships_at_work n left join public.fleet_book b on b.fleet_id = n.fleet_id
              where (n.unpaid_since is null) <> (coalesce((b.figs ->> 'upkeep')::bigint, 0) > 0))
     or not exists (select 1 from public.fleet_book b join public.pirate_ships n on n.fleet_id = b.fleet_id where b.figs ? 'upkeep') then
    raise exception 'PROOF 132 FAIL: the pirates'' upkeep is not booked a ship paid: %', (select jsonb_agg(jsonb_build_object('u', n.unpaid_since, 'b', b.figs)) from public.pirate_ships n left join public.fleet_book b on b.fleet_id = n.fleet_id);
  end if;
  raise notice 'PASS: FB_PAY — % navy ship(s) paid, % d. an hour each, booked; % pirate ship(s) paid, booked what each was paid',
    (select count(*) from public.navy_ships n where n.nation_id = v_nat and n.unpaid_since is null), v_slice,
    (select count(*) from public.fleet_book b join public.pirate_ships n on n.fleet_id = b.fleet_id where b.figs ? 'upkeep');

  -- ── FB_GOLD ── a cargo ship of the navy's realm loads 5,000 at her home, delivers 2,000 at another city of her realm; a pirate loots half the rest
  select c.fleet_id, c.player_id, c.home_port_id into v_cg, v_cgp, v_cap from public.cargo_ships c where c.nation_id = v_nat order by c.ord limit 1;
  select a.port_id into v_to from public.port_allegiance a where a.nation_id = v_nat and a.port_id <> v_cap order by a.port_id limit 1;
  update public.port_treasury t set ducats = greatest(t.ducats, 1000000) where t.port_id = v_cap;
  v_load := public.convoy_book('LOADED', v_cg, v_cgp, v_cap, 5000);
  perform public.convoy_book('DELIVERED', v_cg, v_cgp, v_to, 2000, v_load);
  select b.figs into v_b from public.fleet_book b where b.fleet_id = v_cg;
  if (v_b ->> 'loaded')::bigint <> 5000 or (v_b ->> 'loaded_n')::int <> 1 or (v_b ->> 'delivered')::bigint <> 2000 or (v_b ->> 'delivered_n')::int <> 1 then
    raise exception 'PROOF 132 FAIL: the cargo ship''s book after a load and a delivery: %', v_b;
  end if;
  v_take := public.pirate_loot_book(v_p[3], v_cg, 0.5, null);
  if v_take <> 1500 then
    raise exception 'PROOF 132 FAIL: the loot took % (want 1,500 of 3,000 aboard)', v_take;
  end if;
  select b.figs into v_b from public.fleet_book b where b.fleet_id = v_p[3];
  if (v_b ->> 'loot')::bigint <> 1500 or (v_b ->> 'gold')::bigint <> 1500 or (v_b ->> 'paid')::int <> 1
     or (select b.figs ->> 'looted' from public.fleet_book b where b.fleet_id = v_cg)::bigint <> 1500
     or (select l.line ->> 'victim' from public.fleet_lines l where l.fleet_id = v_p[3] and l.kind = 'TAKE') is distinct from (select f.name from public.fleets f where f.id = v_cg)
     or (select l.line ->> 'victim_kind' from public.fleet_lines l where l.fleet_id = v_p[3] and l.kind = 'TAKE') <> 'CARGO_SHIP' then
    raise exception 'PROOF 132 FAIL: the loot''s book: pirate %, cargo %', v_b, (select b.figs from public.fleet_book b where b.fleet_id = v_cg);
  end if;
  select nf.player_id into v_merch from public.npc_fleets nf join public.players pl on pl.id = nf.player_id where pl.ducats > 100000 order by nf.fleet_id limit 1;
  v_take := public.pirate_ransom(v_p[3], v_merch, 100000, null);
  if v_take <= 0 or (select (b.figs ->> 'ransom')::bigint from public.fleet_book b where b.fleet_id = v_p[3]) <> v_take
     or (select (b.figs ->> 'loot')::bigint from public.fleet_book b where b.fleet_id = v_p[3]) <> 1500 + v_take
     or (select (b.figs ->> 'paid')::int from public.fleet_book b where b.fleet_id = v_p[3]) <> 2 then
    raise exception 'PROOF 132 FAIL: the ransom (% d.) is not booked: %', v_take, (select b.figs from public.fleet_book b where b.fleet_id = v_p[3]);
  end if;
  raise notice 'PASS: FB_GOLD — the cargo ship loaded 5,000, delivered 2,000, lost 1,500 to the pirate; the pirate: loot % (gold 1,500, ransom %), paid 2, a TAKE line naming the cargo ship',
    1500 + v_take, v_take;

  -- ── FB_STOP ──
  perform public.fleet_book_stop(v_n2, v_merch, 'PLUNDERED', jsonb_build_object('hull_lost', jsonb_build_object('b', jsonb_build_object(gen_random_uuid()::text, 7.5))),
                                 321, (select jsonb_build_object(g.code, 2) from public.goods g where g.base_value > 0 order by g.code limit 1), v_t);
  perform public.fleet_book_stop(v_cg, v_merch, 'PLUNDERED', '{}'::jsonb, 999, null, v_t);
  select b.figs into v_b from public.fleet_book b where b.fleet_id = v_n2;
  if (v_b ->> 'stops')::int <> 1 or (v_b ->> 'won')::int <> 1 or (v_b ->> 'fines')::bigint <> 321 or (v_b ->> 'hull')::numeric <> 7.5
     or (v_b ->> 'prizes')::numeric <> (select round(2 * g.base_value) from public.goods g where g.base_value > 0 order by g.code limit 1)
     or (select b.figs ? 'fines' from public.fleet_book b where b.fleet_id = v_cg) then
    raise exception 'PROOF 132 FAIL: the stop''s book: %', v_b;
  end if;
  raise notice 'PASS: FB_STOP — a stop booked to the navy ship: fight won, fine 321, prize %, hull 7.5; a cargo ship''s "stop" not booked', v_b ->> 'prizes';

  -- ── FB_REFIT ── the first pirate (wrecked or not by the fight) is a wreck past her respawn wait, and is reborn
  update public.ships set durability = 0 where fleet_id = v_p[2];
  update public.pirate_ships set wrecked_at = v_t - interval '1 day' where fleet_id = v_p[2];
  update public.fleets set status = 'UNABLE_TO_SAIL', port_id = (select n.home_port from public.pirate_ships n where n.fleet_id = v_p[2]) where id = v_p[2];
  v_res := public.pirate_reborn(v_p[2], v_t);
  if v_res <> 'REBORN' or (select (b.figs ->> 'refits')::int from public.fleet_book b where b.fleet_id = v_p[2]) <> 1
     or (select coalesce((b.figs ->> 'repairs')::bigint, 0) from public.fleet_book b where b.fleet_id = v_p[2]) <>
        (select coalesce((e.payload ->> 'cost')::bigint, 0) from public.events e where e.kind = 'REFITTED' and e.player_id = (select n.player_id from public.pirate_ships n where n.fleet_id = v_p[2]) order by e.created_at desc limit 1)
     or not exists (select 1 from public.fleet_lines l where l.fleet_id = v_p[2] and l.kind = 'REFIT') then
    raise exception 'PROOF 132 FAIL: the refit: % / book %', v_res, (select b.figs from public.fleet_book b where b.fleet_id = v_p[2]);
  end if;
  raise notice 'PASS: FB_REFIT — the pirate wreck reborn, booked refits 1, repairs %, a REFIT line', coalesce((select b.figs ->> 'repairs' from public.fleet_book b where b.fleet_id = v_p[2]), '0 (free)');

  -- ── FB_BATTLE ── a battle: the third pirate opens on a cargo ship of another realm; the navy's second ship called in time, its first too late; the cargo ship holds
  select c.fleet_id into v_cgn from public.cargo_ships c where c.nation_id <> v_nat order by c.ord, c.fleet_id limit 1;
  select s.id into v_cs from public.ships s where s.fleet_id = v_cgn order by s.id limit 1;
  select s.id into v_ps from public.ships s where s.fleet_id = v_p[3] order by s.id limit 1;
  insert into public.battles (id, kind, site, started_at, resolves_at, status)
  values (v_bat, 'ATTACK', '{}'::jsonb, v_t - interval '10 minutes', v_t, 'FIGHTING');
  insert into public.battle_sides (battle_id, fleet_id, side, joined_at, arrives_at, how) values
    (v_bat, v_p[3], 'ATTACKER', v_t - interval '10 minutes', v_t - interval '10 minutes', 'OPENED'),
    (v_bat, v_cgn, 'DEFENDER', v_t - interval '10 minutes', v_t - interval '10 minutes', 'OPENED'),
    (v_bat, v_n2, 'DEFENDER', v_t - interval '8 minutes', v_t - interval '2 minutes', 'CALLED'),
    (v_bat, v_n1, 'DEFENDER', v_t - interval '8 minutes', v_t + interval '5 minutes', 'CALLED');
  update public.battles set status = 'RESOLVED',
         result = jsonb_build_object('outcome', 'DRIVEN_OFF', 'hull_lost', jsonb_build_object('a', jsonb_build_object(v_cs::text, 10), 'b', jsonb_build_object(v_ps::text, 30)))
   where id = v_bat;
  if (select b.figs ->> 'raids' from public.fleet_book b where b.fleet_id = v_p[3])::int <> 1 or (select b.figs ->> 'raids_lost' from public.fleet_book b where b.fleet_id = v_p[3])::int <> 1
     or (select b.figs ->> 'hull' from public.fleet_book b where b.fleet_id = v_p[3])::numeric <> 30
     or (select b.figs ->> 'attacked' from public.fleet_book b where b.fleet_id = v_cgn)::int <> 1 or (select b.figs ->> 'held' from public.fleet_book b where b.fleet_id = v_cgn)::int <> 1
     or (select b.figs ->> 'hull' from public.fleet_book b where b.fleet_id = v_cgn)::numeric <> 10
     or (select b.figs ->> 'fights' from public.fleet_book b where b.fleet_id = v_n2)::int <> 2 or (select b.figs ->> 'won' from public.fleet_book b where b.fleet_id = v_n2)::int <> 2   -- the stop and this one, both won
     or (select b.figs ->> 'fights' from public.fleet_book b where b.fleet_id = v_n1)::int <> 1   -- the fight alone: she came too late
     or (select l.line ->> 'foe' from public.fleet_lines l where l.fleet_id = v_p[3] and l.kind = 'RAID') is distinct from (select f.name from public.fleets f where f.id = v_cgn) then
    raise exception 'PROOF 132 FAIL: the battle''s book: pirate %, cargo %, navy %', (select b.figs from public.fleet_book b where b.fleet_id = v_p[3]),
      (select b.figs from public.fleet_book b where b.fleet_id = v_cgn), (select b.figs from public.fleet_book b where b.fleet_id = v_n2);
  end if;
  raise notice 'PASS: FB_BATTLE — the raider: raids 1, lost 1, hull 30; the cargo ship: attacked 1, held 1, hull 10; the navy ship called in time: a fight won; the late one not booked';

  -- ── FB_LIST ── an hour and a line older than 8 days, then the Stats count
  insert into public.fleet_book (fleet_id, hour, figs) values (v_n1, to_timestamp(floor(extract(epoch from v_t - interval '9 days') / 3600) * 3600), '{"fights": 50}');
  insert into public.fleet_lines (fleet_id, at, kind, line) values (v_n1, v_t - interval '9 days', 'FIGHT', '{"old": true}');
  perform public.tick_stats(v_t);
  if (select count(*) from public.stats_fleet_list) <> 3 or exists (select 1 from public.fleet_book b where b.hour < v_t - interval '8 days')
     or exists (select 1 from public.fleet_lines l where l.at < v_t - interval '8 days') then
    raise exception 'PROOF 132 FAIL: the count wrote % list rows, or left the old book', (select count(*) from public.stats_fleet_list);
  end if;
  v_r := world.stats_fleet_list('navy');
  select x into v_b from jsonb_array_elements(v_r -> 'list') x where x ->> 'id' = v_n1::text;
  if (v_r ->> 'counted_at')::timestamptz <> v_t or (v_r ->> 'fleets')::int <> (v_r ->> 'sea')::int + (v_r ->> 'port')::int + (v_r ->> 'laid_up')::int + (v_r ->> 'wrecked')::int
     or (v_r ->> 'fleets')::int <> (select count(*) from public.navy_ships) or v_b is null or v_b ->> 'nation' <> v_code
     or (v_b -> 'week' ->> 'fights')::int <> 1 or (v_r -> 'day' ->> 'fights')::int <> 3 or (v_r -> 'week' ->> 'upkeep')::bigint < v_slice then
    raise exception 'PROOF 132 FAIL: the navy list: %', v_r - 'list' || jsonb_build_object('n1', v_b);
  end if;
  v_r := world.stats_fleet_list('PIRATE');
  if jsonb_array_length(v_r -> 'list') <> 3 or (v_r -> 'week' ->> 'raids')::int <> 1 or (v_r -> 'week' ->> 'loot')::bigint < 1500
     or (world.stats_fleet_list('cargo') ->> 'fleets')::int <> v_made or (world.stats_fleet_list('cargo') -> 'week' ->> 'delivered')::bigint <> 2000 then
    raise exception 'PROOF 132 FAIL: the pirate or cargo list: %', v_r - 'list';
  end if;
  raise notice 'PASS: FB_LIST — three rows (pirates %, cargo %); the first navy ship''s week 1 fight (the 9-day-old hour not in it), the navy''s day 3 (the fight, the stop, the battle); the 9-day-old hour and line let go',
    v_r ->> 'fleets', v_made;

  -- ── FB_PAGE ──
  v_r := world.stats_fleet(v_cg);
  if v_r ->> 'kind' <> 'CARGO' or v_r ->> 'nation' <> v_code or (v_r -> 'day' ->> 'delivered')::bigint <> 2000 or (v_r -> 'week' ->> 'looted')::bigint <> 1500
     or (v_r -> 'cargo' ->> 'aboard')::bigint <> 1500 or v_r -> 'cargo' -> 'load' ->> 'port' <> (select p.code from public.ports p where p.id = v_cap)
     or jsonb_array_length(v_r -> 'cargo' -> 'rows') <> 3
     or not exists (select 1 from jsonb_array_elements(v_r -> 'cargo' -> 'rows') x where x ->> 'stage' = 'DELIVERED'
                      and x ->> 'port' = (select p.code from public.ports p where p.id = v_to) and x ->> 'from' = (select p.code from public.ports p where p.id = v_cap)
                      and (x ->> 'ducats')::bigint = 2000 and (x ->> 'after')::numeric >= 0) then
    raise exception 'PROOF 132 FAIL: the cargo ship''s page: %', v_r;
  end if;
  v_r := world.stats_fleet(v_n2);
  if v_r ->> 'kind' <> 'NAVY' or jsonb_array_length(v_r -> 'ships') < 1 or (v_r -> 'ships' -> 0 ->> 'hull_max') is null
     or (v_r -> 'day' ->> 'fines')::bigint <> 321 or jsonb_array_length(v_r -> 'lines') <> 2 or v_r -> 'lines' -> 0 ->> 'kind' <> 'BATTLE' or v_r ->> 'state' is null then
    raise exception 'PROOF 132 FAIL: the navy ship''s page: %', v_r;
  end if;
  begin
    perform world.stats_fleet((select nf.fleet_id from public.npc_fleets nf order by nf.fleet_id limit 1));
    raise exception 'PROOF 132 FAIL: a merchant''s fleet was read as a page';
  exception when sqlstate 'P0001' then
    if sqlerrm not like 'E_NOT_FOUND%' then raise; end if;
  end;
  raise notice 'PASS: FB_PAGE — the cargo ship: 3 gold rows, the delivery from % to % 2,000, 1,500 aboard; the navy ship: % ship(s), fine 321, 2 lines (the battle first); a merchant refused',
    (select p.code from public.ports p where p.id = v_cap), (select p.code from public.ports p where p.id = v_to), jsonb_array_length(v_r -> 'ships');
end $p$;
