-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- PROOF 52 — STORES HAVE THEIR OWN SPACE  (migration 0345, owner row 221: "separate cargo space so that provision is set differently by ship")
--
--   0345 proves in its own transaction that its hunks are byte-parity dark and that a hand-made probe hull keeps her stores apart lit. This proof walks the REAL paths a player walks: a house
--   founded by public.new_house, her hold brimmed with cargo, her SAIL issued through the client door (proof.sail, cmd.issue), a PROVISION FULL, her ship as world.ship_view serves it. Lit and
--   dark, in one transaction that proof.mjs rolls back. Every precondition is set here.
--
-- @pass STORES_SPACE_SAIL   lit: a hold brimmed with cargo and empty casks SAILs LIS -> CAD through the client door; the SAIL bought her stores into her stores space (never past it) and loaded no cargo off
-- @pass STORES_SPACE_DARK   dark: the same brimmed hold is refused E_ENDURANCE, nothing bought (the world before 0345), and the cargo room counts the stores again
-- @pass STORES_SPACE_ROOM   lit: her free hold is her hold less her cargo (the stores take none of it); her ship view serves stores_cap = public.ship_stores_space; dark serves no such key
-- @pass STORES_SPACE_FULL   lit: PROVISION FULL fills her stores space to the tun whatever her cargo; a second FULL is refused E_HOLD_FULL
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════

do $$
declare
  c_auth   constant uuid := '00000000-0f52-4000-8000-000000000221';
  c_auth2  constant uuid := '00000000-0f52-4000-8000-000000000222';
  v_player uuid;
  v_fleet  uuid;
  v_ship   uuid;
  v_gcode  text;
  v_res    jsonb;
  v_cargo0 numeric;
  v_cargo1 numeric;
  v_space  numeric;
  v_st     numeric;
  v_free   numeric;
  v_hold   numeric;
  v_view   jsonb;
begin
  update public.world_config set value = to_jsonb(0.0) where key = 'hazard_p_max';
  v_player := public.new_house(c_auth, 'Casa dos Paiois', 'PRT');
  select id into v_fleet from public.fleets where player_id = v_player;
  select id into v_ship from public.ships where fleet_id = v_fleet;
  update public.players set ducats = 10000000 where id = v_player;
  v_gcode := (select g.code from public.goods g where g.bulk = 1 order by g.code limit 1);

  -- ── DARK FIRST: her hold brimmed with cargo, her casks empty: the SAIL is refused, nothing bought ──
  update public.world_config set value = 'false'::jsonb where key = 'ship_stores_separate';
  update public.ships set water_t = 0, food_t = 0 where fleet_id = v_fleet;
  perform public.fleet_load(v_fleet, v_gcode, 100000, 1);
  v_cargo0 := public.ship_cargo_tuns(v_ship);
  perform cmd.assume_identity(c_auth);
  v_res := proof.sail(v_fleet, 'CAD');
  if coalesce((v_res->>'ok')::boolean, false) or v_res::text not like '%E_ENDURANCE%'
     or exists (select 1 from public.ships s where s.fleet_id = v_fleet and s.water_t + s.food_t > 0) then
    raise exception 'PROOF 52 FAILED: dark, a brimmed hold was not refused E_ENDURANCE with nothing bought: %', v_res;
  end if;
  raise notice 'PASS: STORES_SPACE_DARK — dark, % t of cargo in a % t hold and empty casks: the SAIL LIS -> CAD is refused E_ENDURANCE and buys nothing', v_cargo0, public.ship_hold_capacity(v_ship);

  -- ── LIT: the same brimmed hold sails, its stores in their own space ──
  update public.world_config set value = 'true'::jsonb where key = 'ship_stores_separate';
  v_res := proof.sail(v_fleet, 'CAD');
  if coalesce((v_res->>'ok')::boolean, false) is not true then
    raise exception 'PROOF 52 FAILED: lit, a hold brimmed with cargo could not SAIL LIS -> CAD: %', v_res;
  end if;
  v_space  := public.ship_stores_space(v_ship);
  v_cargo1 := public.ship_cargo_tuns(v_ship);
  select s.water_t + s.food_t into v_st from public.ships s where s.id = v_ship;
  if v_st <= 0 or v_st > v_space + 0.01 or v_cargo1 <> v_cargo0 then
    raise exception 'PROOF 52 FAILED: lit, the SAIL bought % t of stores against a space of % t, cargo % -> %', v_st, v_space, v_cargo0, v_cargo1;
  end if;
  raise notice 'PASS: STORES_SPACE_SAIL — lit, the same % t of cargo SAILs LIS -> CAD; the SAIL bought % t of stores into a % t stores space, cargo untouched', v_cargo1, v_st, v_space;

  -- ── LIT: the room and the view (she lies at sea now; the readers do not care where she is) ──
  v_hold := public.ship_hold_capacity(v_ship);
  v_free := public.fleet_free_hold(v_fleet);
  v_view := world.ship_view(v_ship);
  if v_free <> greatest(0, v_hold - v_cargo1) or (v_view->>'stores_cap')::numeric is distinct from v_space or v_space <> floor(v_space) or v_space < 1 then
    raise exception 'PROOF 52 FAILED: lit, free hold % against hold % less cargo %, or stores_cap % against space %', v_free, v_hold, v_cargo1, v_view->'stores_cap', v_space;
  end if;
  update public.world_config set value = 'false'::jsonb where key = 'ship_stores_separate';
  if world.ship_view(v_ship) ? 'stores_cap' or public.fleet_free_hold(v_fleet) <> greatest(0, v_hold - v_cargo1 - v_st) then
    raise exception 'PROOF 52 FAILED: dark, the view still serves stores_cap, or the free hold does not count the stores again';
  end if;
  raise notice 'PASS: STORES_SPACE_ROOM — lit, free hold % = hold % less cargo %, stores_cap % t; dark, no stores_cap and the free hold counts the % t of stores again', v_free, v_hold, v_cargo1, v_space, v_st;

  -- ── LIT: PROVISION FULL fills the space, whatever the cargo (a second house, docked at Lisbon, brimmed) ──
  update public.world_config set value = 'true'::jsonb where key = 'ship_stores_separate';
  v_player := public.new_house(c_auth2, 'Casa dos Toneis', 'PRT');
  select id into v_fleet from public.fleets where player_id = v_player;
  select id into v_ship from public.ships where fleet_id = v_fleet;
  update public.players set ducats = 10000000 where id = v_player;
  update public.ships set water_t = 0, food_t = 0 where fleet_id = v_fleet;
  perform public.fleet_load(v_fleet, v_gcode, 100000, 1);
  v_cargo1 := public.ship_cargo_tuns(v_ship);
  v_space  := public.ship_stores_space(v_ship);
  v_res := cmd.do_provision(v_fleet, '{"mode": "FULL"}'::jsonb);
  select s.water_t + s.food_t into v_st from public.ships s where s.id = v_ship;
  if abs(v_st - v_space) > 0.01 then
    raise exception 'PROOF 52 FAILED: lit, FULL filled % t of a % t stores space: %', v_st, v_space, v_res;
  end if;
  begin
    v_res := cmd.do_provision(v_fleet, '{"mode": "FULL"}'::jsonb);
    raise exception 'PROOF 52 FAILED: lit, a second FULL into a full stores space bought more: %', v_res;
  exception when others then
    if sqlerrm not like '%E_HOLD_FULL%' then raise; end if;
  end;
  raise notice 'PASS: STORES_SPACE_FULL — lit, FULL filled % t into a % t stores space beside % t of cargo; a second FULL is refused E_HOLD_FULL', v_st, v_space, v_cargo1;
end $$;
