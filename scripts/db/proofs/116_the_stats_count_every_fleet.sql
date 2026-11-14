-- ═══════════════════════════════════════════════════════════════════════════════
-- PROOF 116 - THE STATS COUNT EVERY FLEET  (migration 0419; docs/dev-log/2026-11-15-stats-fleets.md)
--
--   A world with cargo ships of every realm, two navy ships and three pirate ships, each put in a known state; a navy fight and a pirate wreck inside the
--   count's window and one outside it; a ransom into a pirate city and a loot into a crown city. The Stats count (public.tick_stats) is run twice, a slot
--   apart, and the face's read (world.stats_fleets) is read after. Rolled back by proof.mjs's transaction.
--
-- @pass SF_COUNT  one count writes ONE public.stats_fleets row (its phase `fleets` in the receipt): every fleet of the three kinds in one state (laid up, wrecked, at sea, in port; the four add up), ships by kind, the navy by nation, the pirates by home, the cargo aboard in tuns; its window holds the one fight and the one pirate sunk inside it (not the one outside), the one wreck inside it, and the ransom into the pirate city only
-- @pass SF_KEEP   the next count finds the wreck reborn (reborn = lying before + wrecked since - lying now) and lets a row older than 26 hours go
-- @pass SF_READ   world.stats_fleets serves the newest row, the merchants in the same four states (they add up to their fleets) with their 24 h, and the two windows summed from the first one's start
-- ═══════════════════════════════════════════════════════════════════════════════

do $p$
declare
  v_t     timestamptz := now();
  v_t2    timestamptz;
  v_nat   uuid;
  v_code  text;
  v_capm  uuid;
  v_stn   uuid;
  v_n1    uuid;
  v_n2    uuid;
  v_p     uuid[];
  v_cg    uuid[];
  v_good  text;
  v_bulk  numeric;
  r       record;
  o       int;
  v_made  int := 0;
  v_ret   jsonb;
  v_f     jsonb;
  v_rd    jsonb;
  v_rcpt  jsonb;
begin
  update public.world_config set value = 'true'::jsonb
   where key in ('city_treasury_enabled', 'economy_closed', 'convoys_enabled', 'pirates_bite', 'npc_refits_enabled') and value is distinct from 'true'::jsonb;
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  if exists (select 1 from public.stats_world) or exists (select 1 from public.stats_fleets) then
    raise exception 'PROOF 116 FAIL: the world already holds a count';
  end if;

  -- CARGO SHIPS: five a realm; one at sea with a hold, one laid up
  update public.cargo_fleet_sizes set ships = 5, read_at = now();
  for r in select g.nation_id from public.great_powers g join public.nations n on n.id = g.nation_id
             join public.ports p on p.code = n.capital_port_code and p.kind = 'HARBOUR' where not g.pirate order by n.code loop
    v_made := v_made + public.cargo_ships_commission(r.nation_id);
  end loop;
  select array_agg(c.fleet_id order by c.nation_id, c.ord) into v_cg from public.cargo_ships c;
  if v_made < 10 or coalesce(array_length(v_cg, 1), 0) <> v_made then
    raise exception 'PROOF 116 FAIL: % cargo ships made', v_made;
  end if;
  select g.code, g.bulk into v_good, v_bulk from public.goods g where g.bulk > 0 order by g.code limit 1;
  update public.fleets set status = 'SAILING', port_id = null where id = v_cg[1];
  update public.ships set cargo = jsonb_build_object(v_good, 10) where fleet_id = v_cg[1];
  update public.cargo_ships set laid_up_at = v_t - interval '1 hour' where fleet_id = v_cg[2];

  -- THE NAVY: two ships of one realm; the first fought (and sank her pirate) ten minutes ago, the second two days ago
  select g.nation_id, public.realm_capital(g.nation_id), n.code into v_nat, v_capm, v_code from public.great_powers g join public.nations n on n.id = g.nation_id
   where not g.pirate and public.realm_capital(g.nation_id) is not null and public.port_nation(public.realm_capital(g.nation_id)) = g.nation_id order by g.nation_id limit 1;
  select a.port_id into v_stn from public.port_allegiance a
   where a.nation_id = v_nat and a.port_id <> v_capm and public.refit_yard(a.port_id) is not null order by a.port_id limit 1;
  update public.port_treasury t set ducats = 50000000 where t.port_id = v_capm;
  v_n1 := public.navy_commission(v_nat, 9001, v_capm, public.refit_yard(v_capm), v_stn, v_t - interval '3 days');
  v_n2 := public.navy_commission(v_nat, 9002, v_capm, public.refit_yard(v_capm), v_stn, v_t - interval '3 days');
  if v_n1 is null or v_n2 is null then
    raise exception 'PROOF 116 FAIL: no navy ship could be built';
  end if;
  update public.navy_ships set fought_at = v_t - interval '10 minutes', fought = jsonb_build_object('result', 'SUNK') where fleet_id = v_n1;
  update public.navy_ships set fought_at = v_t - interval '2 days', fought = jsonb_build_object('result', 'SUNK') where fleet_id = v_n2;
  update public.fleets set status = 'SAILING', port_id = null where id = v_n1;

  -- THE PIRATES: three of 0339's ships at their homes; the first wrecked twenty minutes ago, the second three hours ago, the third whole
  update public.port_treasury t set ducats = 975934180 where t.port_id = public.pirate_capital();
  for o in 1 .. 3 loop
    v_p := v_p || public.pirate_commission(o, public.pirate_home_of(o), public.refit_yard(public.pirate_home_of(o)), v_t - interval '2 days');
  end loop;
  if coalesce(array_length(v_p, 1), 0) <> 3 or exists (select 1 from unnest(v_p) x where x is null) then
    raise exception 'PROOF 116 FAIL: the pirate ships could not be built: %', v_p;
  end if;
  update public.ships set durability = 0 where fleet_id in (v_p[1], v_p[2]);
  update public.pirate_ships set wrecked_at = v_t - interval '20 minutes' where fleet_id = v_p[1];
  update public.pirate_ships set wrecked_at = v_t - interval '3 hours' where fleet_id = v_p[2];

  -- THE PLUNDER: a ransom into the pirates' capital, and a loot into a crown city (not the pirates')
  if public.port_nation(public.pirate_capital()) is distinct from public.pirate_nation() or public.port_nation(v_capm) = public.pirate_nation() then
    raise exception 'PROOF 116 FAIL: the pirates'' capital is not a pirate city in this world';
  end if;
  perform public.treasury_post(public.pirate_capital(), 'RANSOM', 1234, null, null, true);
  perform public.treasury_post(v_capm, 'LOOT', 999, null, null, true);

  -- ── SF_COUNT ──
  v_ret := public.tick_stats(v_t);
  select x.figures into v_f from public.stats_fleets x where x.slot = public.drift_slot_of(v_t);
  select r2.receipt into v_rcpt from public.stats_runs r2 where r2.at = v_t;
  if (v_ret ->> 'fleets')::int <> 1 or v_f is null or (select count(*) from public.stats_fleets) <> 1 or (v_rcpt -> 'phases' ->> 'fleets') is null then
    raise exception 'PROOF 116 FAIL: the count wrote no fleets row (return %, receipt %)', v_ret - 'day' - 'live' - 'fold', v_rcpt -> 'phases';
  end if;
  if (v_f -> 'navy' ->> 'fleets')::int <> 2 or (v_f -> 'navy' ->> 'sea')::int <> 1 or (v_f -> 'navy' ->> 'port')::int <> 1
     or (v_f -> 'navy' ->> 'ships')::int < 2 or v_f -> 'navy' -> 'nations' -> 0 ->> 0 <> v_code or (v_f -> 'navy' -> 'nations' -> 0 ->> 1)::int <> 2
     or (v_f -> 'pirates' ->> 'fleets')::int <> 3 or (v_f -> 'pirates' ->> 'wrecked')::int <> 2 or (v_f -> 'pirates' ->> 'port')::int <> 1 or (v_f -> 'pirates' ->> 'wrecked_rows')::int <> 2
     or (select coalesce(sum((h ->> 2)::int), 0) from jsonb_array_elements(v_f -> 'pirates' -> 'homes') h) <> 3
     or (v_f -> 'cargo' ->> 'fleets')::int <> v_made or (v_f -> 'cargo' ->> 'sea')::int <> 1 or (v_f -> 'cargo' ->> 'laid_up')::int <> 1
     or (v_f -> 'cargo' ->> 'port')::int <> v_made - 2 or (v_f -> 'cargo' ->> 'tuns')::numeric <> round(10 * v_bulk) or (v_f -> 'cargo' ->> 'tuns_at_sea')::numeric <> round(10 * v_bulk)
     or (v_f -> 'merchants' ->> 'ships')::int <> (select count(*) from public.npc_fleets nf join public.ships s on s.fleet_id = nf.fleet_id) then
    raise exception 'PROOF 116 FAIL: the count''s state is not the world''s: %', v_f - 'win';
  end if;
  if (v_f -> 'win' ->> 'navy_fights')::int <> 1 or (v_f -> 'win' ->> 'pirates_sunk')::int <> 1 or (v_f -> 'win' ->> 'pirate_wrecks')::int <> 1
     or (v_f -> 'win' ->> 'pirate_reborn')::int <> 0 or (v_f -> 'win' ->> 'plunder')::bigint <> 1234 or (v_f -> 'win' ->> 'raids_paid')::int <> 1 then
    raise exception 'PROOF 116 FAIL: the count''s window is not what happened in it: %', v_f -> 'win';
  end if;
  raise notice 'PASS: SF_COUNT — navy 2 (1 at sea, %), pirates 3 (2 wrecked), cargo % (1 at sea with % t, 1 laid up), merchants'' ships %; window: 1 fight, 1 sunk, 1 wreck, 1,234 d. plunder; the phase took % ms',
    v_code, v_made, round(10 * v_bulk), v_f -> 'merchants' ->> 'ships', v_rcpt -> 'phases' ->> 'fleets';

  -- ── SF_KEEP ──
  update public.pirate_ships set wrecked_at = null where fleet_id = v_p[2];
  update public.ships set durability = 100 where fleet_id = v_p[2];
  insert into public.stats_fleets (slot, at, figures) values (5, v_t - interval '27 hours', v_f);
  v_t2 := v_t + make_interval(secs => public.wc_num('drift_slot_seconds')::double precision + 1);
  v_ret := public.tick_stats(v_t2);
  select x.figures into v_f from public.stats_fleets x where x.slot = public.drift_slot_of(v_t2);
  if (v_ret ->> 'fleets')::int <> 1 or v_f is null or exists (select 1 from public.stats_fleets x where x.slot = 5) or (select count(*) from public.stats_fleets) <> 2
     or (v_f -> 'win' ->> 'pirate_reborn')::int <> 1 or (v_f -> 'win' ->> 'pirate_wrecks')::int <> 0 or (v_f -> 'win' ->> 'navy_fights')::int <> 0
     or (v_f -> 'pirates' ->> 'wrecked')::int <> 1 then
    raise exception 'PROOF 116 FAIL: the second count: return %, window %, rows %', v_ret - 'day' - 'live' - 'fold', v_f -> 'win', (select array_agg(x.slot) from public.stats_fleets x);
  end if;
  raise notice 'PASS: SF_KEEP — the second count: 1 reborn, 0 wrecked, no fight; the row 27 h old let go, two rows kept';

  -- ── SF_READ ──
  v_rd := world.stats_fleets();
  if (v_rd ->> 'counted_at')::timestamptz <> v_t2 or (v_rd ->> 'day_from')::timestamptz >= v_t
     or (v_rd -> 'navy' ->> 'fights_day')::int <> 1 or (v_rd -> 'navy' ->> 'sunk_day')::int <> 1 or (v_rd -> 'navy' ->> 'fleets')::int <> 2
     or (v_rd -> 'pirates' ->> 'wrecks_day')::int <> 1 or (v_rd -> 'pirates' ->> 'reborn_day')::int <> 1 or (v_rd -> 'pirates' ->> 'plunder_day')::bigint <> 1234
     or (v_rd -> 'pirates' ->> 'raids_paid_day')::int <> 1 or (v_rd -> 'pirates') ? 'wrecked_rows' or (v_rd -> 'cargo' ->> 'fleets')::int <> v_made
     or v_rd -> 'merchants' is null
     or (v_rd -> 'merchants' ->> 'fleets')::int <> (select count(*) from public.npc_fleets)
     or (v_rd -> 'merchants' ->> 'fleets')::int <> (v_rd -> 'merchants' ->> 'sea')::int + (v_rd -> 'merchants' ->> 'port')::int + (v_rd -> 'merchants' ->> 'laid_up')::int + (v_rd -> 'merchants' ->> 'wrecked')::int
     or (v_rd -> 'merchants' ->> 'profit_day') is null or (v_rd -> 'merchants' ->> 'ships')::int < 1 then
    raise exception 'PROOF 116 FAIL: the read: %', v_rd;
  end if;
  raise notice 'PASS: SF_READ — counted at the second count, the day from the first window''s start: 1 fight, 1 sunk, 1 wreck, 1 reborn, 1,234 d.; merchants % fleets in four states that add up', v_rd -> 'merchants' ->> 'fleets';
end $p$;
