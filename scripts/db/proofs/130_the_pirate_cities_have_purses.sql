-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 130 - THE PIRATE CITIES HAVE PURSES  (migration 0429; docs/dev-log/2026-11-15-pirate-purses.md; the owner, 2026-11-15: "raise the cap
--   more, pirates should never be laid up. allocate gold to pirate cities and hub, 10m each, port royal 30m. they should also have like 5 cargo
--   ship (pirates) to move gold to poorer pirate cities. port royal will be capital for pirates.")
--
--   Lit as prod is (the purses, the closed economy, the pirates, the cargo ships, the refit rule, attacks), rolled back with proof.mjs's transaction.
--   THE DAY'S ROOM IS SPENT in every scene that pays: before 0429 an hour's pay, a wake and a wreck's refit by the hoard all answered 0 then.
--
-- @pass PP_KNOBS    Port Royal is the pirates' capital; the knobs are 0429's (floor 100 M, a city's purse 10 M, Port Royal keeps 30 M, 5 cargo ships, 20 wakes a run)
-- @pass PP_PAY      the day's room spent, the hour's pay reaches every pirate fleet at work (none marked unpaid); with the hoard under its floor, the pay stops and they are marked unpaid
-- @pass PP_WAKE     the laid-up fleets the pirates keep are put back to work by the minute's step, at most pirate_wakes_per_run, while the hoard is above its floor
-- @pass PP_REFIT    the day's room spent and every other pirate purse dry, a pirate wreck's refit is paid by the hoard (HOARD), not left waiting for 00:00 UTC
-- @pass PP_ALLOT    every pirate harbour but Port Royal is topped up to 10 M from Port Royal, kind PIRATE_ALLOT, two rows a city; the world's money unmoved
-- @pass PP_CARGO    the step makes the pirate cargo ships at Port Royal (one a minute), builds their circuit, loads what the pirate cities lack; she sails, tops a city up to 10 M, and never takes a new home; the world's money unmoved
-- @pass PP_NEVER    never raided by pirates: a hunting pirate beside her finds no target, and a passage of hers names no pirate raider (a merchant's does)
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

create function pg_temp.w_130() returns numeric language sql as $f$
  select (select coalesce(sum(public.treasury_balance(t.port_id)), 0) from public.port_treasury t)::numeric
       + (select coalesce(sum(p.ducats), 0) from public.players p)::numeric + public.funds_aboard()::numeric
$f$;
-- a purse set to p_d whatever flows it holds
create function pg_temp.purse_130(p_port uuid, p_d bigint) returns void language sql as $f$
  update public.port_treasury t set ducats = p_d - coalesce((select sum(f.ducats) from public.treasury_flows f where f.port_id = p_port), 0) where t.port_id = p_port;
$f$;

do $p$
declare
  t0      timestamptz := date_trunc('day', now()) + interval '1 day 2 hours';
  v_cap   uuid;
  v_pir   uuid := public.pirate_nation();
  v_hub   uuid := (select p.id from public.ports p where p.code = 'TDC');
  v_city  uuid;
  v_f     uuid[] := '{}';
  v_x     uuid;
  v_s     text;
  v_r     jsonb;
  v_w0    numeric;
  v_b0    bigint;
  v_n     int;
  v_c     uuid;
  v_cp    uuid;
  v_seg   jsonb;
  v_m     uuid;
  r       record;
begin
  -- ── THE SCENE ──
  update public.world_config set value = 'true'::jsonb
   where key in ('city_treasury_enabled', 'economy_closed', 'pirates_bite', 'npc_refits_enabled', 'attack_enabled', 'convoys_enabled') and value is distinct from 'true'::jsonb;
  update public.world_config set value = 'false'::jsonb where key in ('pirates_trade', 'navy_enabled') and value is distinct from 'false'::jsonb;
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = 2000000, reserve = 0;
  v_cap := public.pirate_capital();
  perform pg_temp.purse_130(v_cap, 900000000);
  for r in select a.port_id from public.port_allegiance a where a.nation_id = v_pir and a.port_id <> v_cap loop
    perform pg_temp.purse_130(r.port_id, 0);
  end loop;
  if not public.pirates_on() or not public.convoys_on() or not public.economy_closed() or not public.npc_refits_on() then
    raise exception 'PROOF 130 FAIL: the pirates, the cargo ships, the refit rule or the closed economy could not be lit';
  end if;
  -- THE DAY'S ROOM IS SPENT
  insert into public.pirate_spend_day (day, spent) values ((t0 at time zone 'UTC')::date, 999999999999)
  on conflict (day) do update set spent = excluded.spent;
  update public.pirate_ships set laid_up_at = t0 where laid_up_at is null;   -- the proof's own fleets only are at work
  for r in select q.ord from public.pirate_roster q where q.hub_port = v_hub and q.ord % 1000 in (1, 4) order by q.ord loop
    v_x := public.pirate_commission_fleet(r.ord, public.refit_yard(v_hub), t0);
    if v_x is null then
      raise exception 'PROOF 130 FAIL: roster fleet % was not built', r.ord;
    end if;
    v_f := v_f || v_x;
  end loop;
  if public.pirate_spend_room(t0) <> 0 then
    raise exception 'PROOF 130 FAIL: the day''s room is not spent';
  end if;

  -- ── PP_KNOBS ──
  if (select p.code from public.ports p where p.id = v_cap) <> 'POR' or public.wc_int('pirate_hoard_floor') <> 100000000 or public.wc_int('pirate_city_purse') <> 10000000
     or public.wc_int('pirate_capital_purse') <> 30000000 or public.wc_int('pirate_cargo_ships') <> 5 or public.wc_int('pirate_wakes_per_run') <> 20 then
    raise exception 'PROOF 130 FAIL: the capital or the knobs are not 0429''s';
  end if;
  raise notice 'PASS: PP_KNOBS — capital POR, floor %, a city %, Port Royal keeps %, % cargo ships, % wakes a run', public.wc_int('pirate_hoard_floor'),
    public.wc_int('pirate_city_purse'), public.wc_int('pirate_capital_purse'), public.wc_int('pirate_cargo_ships'), public.wc_int('pirate_wakes_per_run');

  -- ── PP_PAY ──
  update public.pirate_clock set paid_at = t0 - interval '2 hours';
  v_b0 := public.pirate_pay_hour(t0);
  if exists (select 1 from public.pirate_ships n where n.fleet_id = any (v_f) and n.unpaid_since is not null) or v_b0 <= 0 then
    raise exception 'PROOF 130 FAIL: with the room spent the hour''s pay did not reach every fleet (paid %)', v_b0;
  end if;
  update public.world_config set value = to_jsonb(2000000000) where key = 'pirate_hoard_floor';
  update public.pirate_clock set paid_at = t0 - interval '2 hours';
  perform public.pirate_pay_hour(t0 + interval '1 hour');
  update public.world_config set value = to_jsonb(100000000) where key = 'pirate_hoard_floor';
  if exists (select 1 from public.pirate_ships n where n.fleet_id = any (v_f) and n.unpaid_since is null) then
    raise exception 'PROOF 130 FAIL: with the hoard under its floor a fleet was still paid';
  end if;
  raise notice 'PASS: PP_PAY — room 0: % paid to the fleets at work; under the floor: unpaid', v_b0;

  -- ── PP_WAKE ──
  update public.pirate_ships n set laid_up_at = t0 where n.fleet_id = any (v_f);
  update public.world_config set value = to_jsonb(0) where key = 'pirate_cargo_ships';   -- the cargo ships are PP_CARGO's
  update public.world_config set value = to_jsonb(1) where key = 'pirate_wakes_per_run';
  v_r := public.pirate_purse_step(t0 + interval '2 hours');
  v_n := (select count(*) from public.pirate_ships n where n.fleet_id = any (v_f) and n.laid_up_at is null and n.unpaid_since is null);
  update public.world_config set value = to_jsonb(20) where key = 'pirate_wakes_per_run';
  if (v_r ->> 'woke')::int <> 1 or v_n <> 1 then
    raise exception 'PROOF 130 FAIL: the step woke % (% of the proof''s), not the one a run allows: %', v_r ->> 'woke', v_n, v_r;
  end if;
  v_r := public.pirate_purse_step(t0 + interval '2 hours 1 minute');
  if exists (select 1 from public.pirate_ships n where n.fleet_id = any (v_f) and n.laid_up_at is not null) then
    raise exception 'PROOF 130 FAIL: a laid-up fleet the pirates keep was not woken: %', v_r;
  end if;
  update public.world_config set value = to_jsonb(5) where key = 'pirate_cargo_ships';
  raise notice 'PASS: PP_WAKE — one a run at a knob of 1, then the rest (%)', v_r ->> 'woke';

  -- ── PP_REFIT ──
  update public.ships s set durability = 0 where s.fleet_id = v_f[1];
  v_s := public.pirate_refit_pay(v_f[1], 100000, t0 + interval '3 hours');
  if v_s is distinct from 'HOARD' then
    raise exception 'PROOF 130 FAIL: the room spent and the pirate cities dry, the wreck''s refit answered % (wanted HOARD)', v_s;
  end if;
  raise notice 'PASS: PP_REFIT — the hoard paid the wreck''s refit with the day''s room spent';

  -- ── PP_ALLOT ──
  v_w0 := pg_temp.w_130();
  v_b0 := public.treasury_balance(v_cap);
  v_n := (select count(*) from public.treasury_flows f where f.kind = 'PIRATE_ALLOT');
  v_r := public.pirate_purses_allot(t0 + interval '3 hours');
  if exists (select 1 from public.port_allegiance a join public.ports p on p.id = a.port_id and p.kind = 'HARBOUR'
              where a.nation_id = v_pir and p.id <> v_cap and public.treasury_balance(p.id) <> 10000000)
     or v_b0 - public.treasury_balance(v_cap) <> (select sum(e.value::text::bigint) from jsonb_each(v_r) e)
     or (select count(*) from public.treasury_flows f where f.kind = 'PIRATE_ALLOT') - v_n <> 2 * (select count(*) from jsonb_object_keys(v_r))
     or pg_temp.w_130() <> v_w0 or v_r = '{}'::jsonb then
    raise exception 'PROOF 130 FAIL: the allotment: % (Port Royal gave %, money moved by %)', v_r, v_b0 - public.treasury_balance(v_cap), pg_temp.w_130() - v_w0;
  end if;
  raise notice 'PASS: PP_ALLOT — %, the world''s money unmoved', v_r;

  -- ── PP_CARGO ──
  -- pinned (0430): the pirates' cargo ships are their share of cargo_fleet_total once the fleet sizes carry their row (7 on this world); this
  -- scene is 0429's five, so their share is held at 5 (prod's, cargo_pirate_min). Before 0430 (no row) this touches nothing.
  update public.cargo_fleet_sizes s set ships = 5 where s.nation_id = v_pir;
  select p.id into v_city from public.port_allegiance a join public.ports p on p.id = a.port_id and p.kind = 'HARBOUR'
   where a.nation_id = v_pir and p.id <> v_cap order by p.code limit 1;
  perform public.treasury_post(v_city, 'PIRATE_ALLOT', -6000000, null, null);
  perform public.treasury_post(v_cap, 'PIRATE_ALLOT', 6000000, null, null);
  v_w0 := pg_temp.w_130();
  v_b0 := (select sum(greatest(0, 10000000 - public.treasury_balance(p.id))) from public.port_allegiance a join public.ports p on p.id = a.port_id and p.kind = 'HARBOUR'
            where a.nation_id = v_pir and p.id <> v_cap);   -- what the pirate cities lack: 6,000,000 at the poor city, and any odd ducat elsewhere
  v_r := public.pirate_purse_step(t0 + interval '4 hours');
  select c.fleet_id into v_c from public.cargo_ships c where c.nation_id = v_pir and c.ord = 1;
  if (v_r ->> 'made')::int <> 1 or (v_r ->> 'loaded')::bigint <> v_b0 or v_c is null
     or public.fleet_kind(v_c) <> 'CARGO_SHIP' or (select c.home_port_id from public.cargo_ships c where c.fleet_id = v_c) <> v_cap
     or (select a.aboard from public.cargo_ship_aboard(v_c) a) <> v_b0 or pg_temp.w_130() <> v_w0 then
    raise exception 'PROOF 130 FAIL: the first step: % (ship %, aboard %, status %/%, legs %, left_out %)', v_r, v_c, (select a.aboard from public.cargo_ship_aboard(v_c) a), (select f.status from public.fleets f where f.id = v_c), (select f.port_id = v_cap from public.fleets f where f.id = v_c), (select count(*) from public.cargo_circuit_legs l where l.circuit_id = public.cargo_circuit_of(v_pir, v_cap)), (select k.left_out from public.cargo_circuits k where k.id = public.cargo_circuit_of(v_pir, v_cap));
  end if;
  for v_n in 1 .. 6 loop
    perform public.pirate_purse_step(t0 + interval '4 hours' + make_interval(mins => v_n));
  end loop;
  if (select count(*) from public.cargo_ships c where c.nation_id = v_pir) <> 5 then
    raise exception 'PROOF 130 FAIL: % pirate cargo ships, not 5', (select count(*) from public.cargo_ships c where c.nation_id = v_pir);
  end if;
  if (select sum(a.aboard) from public.cargo_ships c cross join lateral public.cargo_ship_aboard(c.fleet_id) a where c.nation_id = v_pir) <> v_b0 then
    raise exception 'PROOF 130 FAIL: a second ship loaded for a need already aboard';
  end if;
  update public.fleets f set ready_at = null where f.id = v_c;
  v_s := public.cargo_ship_step(v_c, t0 + interval '5 hours');
  if v_s <> 'SAILED' then
    raise exception 'PROOF 130 FAIL: the loaded pirate cargo ship answered % (wanted SAILED)', v_s;
  end if;
  -- she comes in at the poor city (her voyage ended by hand: the proof is of what she does in port)
  update public.voyages set status = 'ABORTED' where fleet_id = v_c and status = 'SAILING';
  update public.fleets set status = 'DOCKED', port_id = v_city, lat = null, lon = null, ready_at = t0 + interval '9 hours' where id = v_c;
  v_s := public.cargo_ship_step(v_c, t0 + interval '6 hours');
  if public.treasury_balance(v_city) <> 10000000 or (select a.aboard from public.cargo_ship_aboard(v_c) a) is distinct from nullif(v_b0 - 6000000, 0) or pg_temp.w_130() <> v_w0 then
    raise exception 'PROOF 130 FAIL: at the city (%): its purse %, still aboard %, money moved %', v_s, public.treasury_balance(v_city),
      (select a.aboard from public.cargo_ship_aboard(v_c) a), pg_temp.w_130() - v_w0;
  end if;
  -- an idle one at home, with the rich-cities rule lit, takes no new home
  update public.world_config set value = 'true'::jsonb where key = 'convoy_rich_enabled';
  select c.fleet_id into v_cp from public.cargo_ships c join public.fleets f on f.id = c.fleet_id
   where c.nation_id = v_pir and c.fleet_id <> v_c and f.port_id = v_cap and not exists (select 1 from public.cargo_ship_aboard(c.fleet_id)) order by c.ord limit 1;
  update public.fleets f set ready_at = null where f.id = v_cp;
  v_s := public.cargo_ship_step(v_cp, t0 + interval '6 hours');
  update public.world_config set value = 'false'::jsonb where key = 'convoy_rich_enabled';
  if v_s <> 'IDLE' or (select c.home_port_id from public.cargo_ships c where c.fleet_id = v_cp) <> v_cap then
    raise exception 'PROOF 130 FAIL: an idle pirate cargo ship at home answered % (wanted IDLE, home Port Royal)', v_s;
  end if;
  raise notice 'PASS: PP_CARGO — 5 ships at POR, what the cities lack loaded once, the poor city topped up to 10 M, idle at home stays; money unmoved';

  -- ── PP_NEVER ── a hunting pirate (the first proof fleet, mended and lying at its haunt) and the pirate cargo ship at anchor beside her
  update public.ships s set durability = (select b.durability from public.ship_base(s.id) b), crew = (select b.crew_max from public.ship_base(s.id) b) where s.fleet_id = v_f[2];
  select h.port_id, h.sea_id into r from public.pirate_haunt_of(v_hub, (select x.ord from public.pirate_ships x where x.fleet_id = v_f[2])) h;
  update public.fleets f set port_id = r.port_id, status = 'DOCKED', ready_at = null, busy_until = null where f.id = v_f[2];
  update public.pirate_ships x set sea_id = r.sea_id, mission = 'CRUISE', haunt_port = r.port_id, haunt_since = t0, laid_up_at = null where x.fleet_id = v_f[2];
  update public.voyages v set status = 'ABORTED' where v.status = 'SAILING';
  update public.fleets f set status = 'DOCKED', port_id = coalesce(f.port_id, v_hub), lat = null, lon = null, busy_until = null where f.status in ('SAILING', 'ANCHORED');
  update public.fleets f set status = 'ANCHORED', port_id = null, lat = p.lat, lon = p.lon from voyage.fleet_point(v_f[2], t0) p where f.id = v_cp;
  if public.raid_target(v_f[2], t0) is not null then
    raise exception 'PROOF 130 FAIL: a hunting pirate chose % beside the pirates'' own cargo ship', public.raid_target(v_f[2], t0);
  end if;
  v_seg := jsonb_build_array(jsonb_build_object('sea_id', r.sea_id));
  select nf.fleet_id into v_m from public.npc_fleets nf join public.fleets f on f.id = nf.fleet_id join public.players pl on pl.id = f.player_id
   where pl.nation_id is distinct from v_pir order by nf.fleet_id limit 1;
  if voyage.freeze_raiders(v_seg, v_cp) <> v_seg or not (voyage.freeze_raiders(v_seg, v_m) -> 0 ? 'raider') then
    raise exception 'PROOF 130 FAIL: the freeze: hers %, a merchant''s %', voyage.freeze_raiders(v_seg, v_cp), voyage.freeze_raiders(v_seg, v_m);
  end if;
  raise notice 'PASS: PP_NEVER — no pirate target beside her; her passage names no raider, a merchant''s names %', voyage.freeze_raiders(v_seg, v_m) -> 0 ->> 'raider';
end
$p$;
