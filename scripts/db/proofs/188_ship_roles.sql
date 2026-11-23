-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 188 - A FLEET THAT GROWS TO FIVE SHIPS  (migration 0485; docs/design/roadmap-2026-11-23.md slice 17;
--   docs/dev-log/2026-11-23-ship-roles.md)
--
--   The migration's self-assert tags hulls and reads the factors. This proof plays the roles where they bite: a hunting pirate's own choice
--   (public.raid_target) between two merchants of hers at sea, one with a guard; a guarded fleet out of the guard's reach and the same
--   fleet unguarded; HQ's board with the role card and the yard's card naming the next hull's role; the ladder at five hulls; the cost
--   of a hull's base tagged and untagged. Rolled back by proof.mjs.
--   NO TIME-BUDGETED READ IS COMPARED WITH ANOTHER: public.hq_board_for is asked once, for a company that is not the caller (so no
--   world.best_sales runs inside it), and only its role and yard cards are read.
--   THE DAY: no clock is set or compared; the scenes are places at sea, not times, so none straddles a UTC midnight.
--
-- @pass SR_RAID_PICK   a pirate between two of her fleets at equal miles sets upon the unguarded one
-- @pass SR_RAID_REACH  a fleet at 150 miles (reach 240) is struck unguarded and passed over guarded (150 x 2 > 240); dark, struck again
-- @pass SR_BOARD       HQ's board: the role card (pick, hull, act) and, with a yard, the yard's card naming the next hull's role
-- @pass SR_LADDER      five hulls: three slots, the ladder's step routes; the pick moves on from a role she has
-- @pass SR_COST        a hull's base, untagged and tagged, 500 calls each; one raid_target lit
-- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  c_a     constant uuid := '00000000-0485-4000-8000-0000000001a1';
  v_lis   uuid := (select p.id from public.ports p where p.code = 'LIS' and p.kind = 'HARBOUR');
  v_a     uuid;
  v_f1    uuid;
  v_f2    uuid;
  v_s1    uuid;
  v_s2    uuid;
  v_s3    uuid;
  v_pir   uuid;
  v_pp    uuid;
  v_got   uuid;
  v_got2  uuid;
  v_hq    jsonb;
  v_card  jsonb;
  v_yard  jsonb;
  v_r     jsonb;
  v_t     timestamptz;
  v_ms    numeric;
  v_ms2   numeric;
  v_ms3   numeric;
  k       int;
  -- the open South Pacific: no harbour, no lane within the pirate's reach
  c_lat   constant numeric := -60;
  c_lon   constant numeric := -100;
begin
  v_a := public.new_house(c_a, 'Casa das Naus 188', 'PRT');
  select f.id into v_f1 from public.fleets f where f.player_id = v_a;
  select s.id into v_s1 from public.ships s where s.fleet_id = v_f1;
  v_f2 := public.form_fleet(v_a, 'Segunda 188', v_lis);
  v_s2 := public.commission_ship(v_a, v_f2, 'barca', 'Segunda 188', true, true);
  v_s3 := public.commission_ship(v_a, v_f2, 'barca', 'Terceira 188', false, true);
  update public.fleets set status = 'DOCKED', port_id = v_lis, lat = null, lon = null where id in (v_f1, v_f2);
  update public.world_config set value = 'true'::jsonb where key = 'ship_roles_enabled';
  -- the company is set upon as any merchant is (the beginner's peace and the merchants-first order are 0464's, not this file's)
  update public.world_config set value = 'false'::jsonb where key = 'raid_companies_enabled';

  -- a pirate ship (proof 119's hands: public.pirate_commission's), anchored in the open sea
  insert into public.players (company_name, nation_id, ducats, is_npc) values ('Proof 188 Pirate', public.pirate_nation(), 0, true) returning id into v_pp;
  v_pir := public.form_fleet(v_pp, 'Proof 188 pirate ship', v_lis);
  perform public.commission_ship(v_pp, v_pir, public.wc_text('pirate_ship_class'), 'Proof 188 pirate ship', true, false);
  insert into public.pirate_ships (fleet_id, player_id, ord, home_port, last_port) values (v_pir, v_pp, 2000000188, v_lis, v_lis);
  if public.fleet_kind(v_pir) <> 'PIRATE' then
    raise exception 'SR_RAID_PICK: the pirate is a %', public.fleet_kind(v_pir);
  end if;
  update public.fleets set status = 'ANCHORED', port_id = null, lat = c_lat, lon = c_lon, busy_until = null where id = v_pir;

  -- SR_RAID_PICK: her two fleets anchored 100 miles east and west of the pirate (60 S: a degree of longitude is 30 miles); a guard in the
  -- second
  perform public.ship_role_set_for(v_a, v_s3, 'guard');
  update public.fleets set status = 'ANCHORED', port_id = null, lat = c_lat, lon = c_lon + 100.0 / 30 where id = v_f1;
  update public.fleets set status = 'ANCHORED', port_id = null, lat = c_lat, lon = c_lon - 100.0 / 30 where id = v_f2;
  v_got := public.raid_target(v_pir, now());
  if v_got is distinct from v_f1 then
    raise exception 'SR_RAID_PICK: the pirate set upon % (the unguarded fleet is %, the guarded %)', v_got, v_f1, v_f2;
  end if;
  raise notice 'PASS: SR_RAID_PICK — two of her fleets 100 miles either side of a pirate: the unguarded one is set upon (the guarded weighs 200)';

  -- SR_RAID_REACH: the guarded fleet alone at 150 miles (the other docked at Lisbon): passed over; her guard off, struck; dark, struck
  update public.fleets set status = 'DOCKED', port_id = v_lis, lat = null, lon = null where id = v_f1;
  update public.fleets set lat = c_lat, lon = c_lon - 150.0 / 30 where id = v_f2;
  v_got := public.raid_target(v_pir, now());
  update public.world_config set value = 'false'::jsonb where key = 'ship_roles_enabled';
  v_got2 := public.raid_target(v_pir, now());
  update public.world_config set value = 'true'::jsonb where key = 'ship_roles_enabled';
  if v_got is not null or v_got2 is distinct from v_f2 then
    raise exception 'SR_RAID_REACH: guarded at 150 miles % (expected none), dark % (expected %)', v_got, v_got2, v_f2;
  end if;
  update public.fleets set status = 'DOCKED', port_id = v_lis, lat = null, lon = null where id = v_f2;
  perform public.ship_role_set_for(v_a, v_s3, null);
  update public.fleets set status = 'ANCHORED', port_id = null, lat = c_lat, lon = c_lon - 150.0 / 30 where id = v_f2;
  v_got := public.raid_target(v_pir, now());
  if v_got is distinct from v_f2 then
    raise exception 'SR_RAID_REACH: unguarded at 150 miles she was not set upon (%)', v_got;
  end if;
  raise notice 'PASS: SR_RAID_REACH — at 150 miles (reach 240): guarded passed over (150 x 2 = 300), unguarded struck, dark struck';
  update public.fleets set status = 'DOCKED', port_id = v_lis, lat = null, lon = null where id = v_f2;

  -- SR_BOARD: HQ's board for her (not the caller: no trade run is priced), the yard taking orders and her purse full
  update public.players p set ducats = 50000000 where p.id = v_a;
  update public.world_config set value = 'true'::jsonb where key = 'yard_order_enabled';
  v_hq := public.hq_board_for(v_a);
  select m.e into v_card from jsonb_array_elements(v_hq->'moves') m(e) where m.e->>'kind' = 'role';
  select m.e into v_yard from jsonb_array_elements(v_hq->'moves') m(e) where m.e->>'kind' = 'yard';
  if v_card is null or v_card->'needs'->>'role' <> 'guard' or v_card->'act'->>'rpc' <> 'cmd.set_ship_role'
     or (v_card->'needs'->>'gain')::numeric <> 2 or (v_card->>'band')::int <> 0
     or (v_yard is not null and v_yard->>'role' is distinct from 'guard') then
    raise exception 'SR_BOARD: the role card % / the yard card %', v_card, v_yard;
  end if;
  raise notice 'PASS: SR_BOARD — role card: make % a % (why % = %, gain %); yard card: %', v_card->'needs'->>'ship_name', v_card->'needs'->>'role',
    v_card->'needs'->>'why', v_card->'needs'->>'n', v_card->'needs'->>'gain',
    coalesce(format('%s at %s for %s, next hull %s', v_yard->'needs'->>'hull', v_yard->>'at', v_yard->'needs'->>'cost', v_yard->>'role'), 'none at Lisbon');

  -- SR_LADDER: five hulls; a guard set; the pick moves on to fast; the ladder's step is routes (her fleets work by hand)
  -- the room for them (a fleet sails fleet_ship_base hulls plus what she earned: the proof gives her five, by the flat rule)
  update public.world_config set value = 'false'::jsonb where key = 'fleet_room_bite';
  update public.world_config set value = to_jsonb(5) where key in ('fleet_ship_max', 'fleet_ship_base');
  perform public.commission_ship(v_a, v_f2, 'barca', 'Quarta 188', false, true);
  perform public.commission_ship(v_a, v_f2, 'barca', 'Quinta 188', false, true);
  perform public.ship_role_set_for(v_a, v_s1, 'guard');
  v_r := public.ship_role_slots(v_a);
  if (v_r->>'ships')::int <> 5 or (v_r->>'slots')::int <> 3 or (v_r->>'used')::int <> 1
     or public.ship_role_pick(v_a)->>'role' <> 'fast' or public.ship_role_next(v_a) is not null
     or public.ship_role_ladder(v_a)->>'step' <> 'routes' or (public.ship_role_ladder(v_a)->>'of')::int <> 2 then
    raise exception 'SR_LADDER: slots %, pick %, next %, ladder %', v_r, public.ship_role_pick(v_a), public.ship_role_next(v_a), public.ship_role_ladder(v_a);
  end if;
  raise notice 'PASS: SR_LADDER — five hulls: 3 slots (1 set), pick fast, no next hull to name, ladder % ', public.ship_role_ladder(v_a);

  -- SR_COST: a hull's base untagged and tagged (fast), 500 calls each; one lit raid_target
  perform public.ship_role_set_for(v_a, v_s2, 'fast');
  v_t := clock_timestamp();
  for k in 1..500 loop perform public.ship_base(v_s3); end loop;
  v_ms := round(extract(epoch from clock_timestamp() - v_t) * 1000, 1);
  v_t := clock_timestamp();
  for k in 1..500 loop perform public.ship_base(v_s2); end loop;
  v_ms2 := round(extract(epoch from clock_timestamp() - v_t) * 1000, 1);
  update public.fleets set status = 'ANCHORED', port_id = null, lat = c_lat, lon = c_lon - 100.0 / 30 where id = v_f2;
  v_t := clock_timestamp();
  perform public.raid_target(v_pir, now());
  v_ms3 := round(extract(epoch from clock_timestamp() - v_t) * 1000, 1);
  raise notice 'PASS: SR_COST — ship_base x500 untagged % ms, tagged % ms; raid_target lit % ms', v_ms, v_ms2, v_ms3;
end
$p$;
