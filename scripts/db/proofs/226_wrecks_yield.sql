-- ══════════════════════════════════════════════════════════════════════════════════
-- PROOF 226 - WHAT A WON ROUND GIVES  (migration 0522; docs/design/rounds-2026-11-25.md section 7)
--
--   A run of four rounds, three won, written here (no dice of a fight); its own company. Rolled back by proof.mjs.
--
-- @pass WY_MOVED  the gold is the hoard's loss to the coin (every company and every city: the sum moves 0); the salvage left the pirate homes' stock unit for unit
-- @pass WY_CAPS   the day's cap bounds it; a hoard with no room pays nothing, and it is not owed; an empty stock gives no salvage
-- @pass WY_HOLD   no more salvage than her hold takes
-- @pass WY_RP     Reputation for the rounds won, in the day's cap
-- ══════════════════════════════════════════════════════════════════════════════════
do $p$
declare
  c_a constant uuid := '00000000-0226-4000-8000-0000000000a1';
  v_a uuid; v_f uuid; v_lis uuid; s0 numeric; s1 numeric; h0 numeric; h1 numeric; v_c jsonb; k int; v_ab numeric; v_txt text := ''; v_d bigint; v_out jsonb := '{}';
begin
  v_a := public.new_house(c_a, 'Casa da Prova 226', 'PRT');
  select f.id, f.port_id into v_f, v_lis from public.fleets f where f.player_id = v_a;
  update public.world_config set value = 'true'::jsonb where key in ('rounds_enabled', 'city_treasury_enabled', 'reputation_on', 'ship_stores_separate', 'wrecks_yield_enabled');
  update public.world_config set value = to_jsonb(1) where key = 'pirate_spend_day_pct';
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set ducats = ducats + 100000000 where port_id = public.pirate_capital();
  for k in 1 .. 4 loop
    begin
      if k = 2 then update public.world_config set value = to_jsonb(100) where key = 'loot_per_company_day'; end if;
      if k = 3 then
        update public.world_config set value = to_jsonb(0) where key = 'pirate_spend_day_pct';
        update public.port_goods pg set stock = 0 where public.pirate_home(pg.port_id);
      end if;
      if k = 4 then perform public.fleet_load(v_f, 'iron-bars', floor(public.fleet_free_hold(v_f) / 0.8) - 2, 1); end if;
      insert into public.round_runs (fleet_id, player_id, work, sea_id, state, sent_at, stop_at, terms)
      values (v_f, v_a, 'pirates', (select h.sea_id from public.ports h where h.id = v_lis), 'out', now(), now() + interval '2400 seconds',
              '{"seconds": 600, "crew": 0, "food": 0, "water": 0, "ammo": 0, "most": 4, "why": "rounds", "strength": 10, "kind": "combat", "fight": {"l": [0.075, 0.03, 0.15, 0.1], "c": [0, 0, 0, 0], "w": [1, 1, 0, 1]}}');
      update public.fleets set status = 'ROUNDS', busy_until = now() + interval '2400 seconds' where id = v_f;
      s0 := (select sum(p.ducats) from public.players p) + (select sum(public.treasury_balance(p.id)) from public.ports p where p.kind = 'HARBOUR');
      h0 := (select sum(pg.stock) from public.port_goods pg where public.pirate_home(pg.port_id));
      v_d := (select p.ducats from public.players p where p.id = v_a);
      perform public.round_settle(v_f, now() + interval '3000 seconds');
      s1 := (select sum(p.ducats) from public.players p) + (select sum(public.treasury_balance(p.id)) from public.ports p where p.kind = 'HARBOUR');
      h1 := (select sum(pg.stock) from public.port_goods pg where public.pirate_home(pg.port_id));
      v_c := (select zr.carry from public.round_runs zr where zr.fleet_id = v_f);
      v_ab := (select coalesce(sum(public.fleet_cargo_qty(v_f, e.key)), 0) from jsonb_object_keys(v_c->'salvage') e(key));
      raise exception using errcode = 'ZP226', message = jsonb_build_object('moved', s1 - s0, 'gold', (select p.ducats from public.players p where p.id = v_a) - v_d, 'stock', h0 - h1, 'aboard', v_ab, 'carry', v_c,
        'free', public.fleet_free_hold(v_f))::text;
    exception when sqlstate 'ZP226' then v_out := v_out || jsonb_build_object(k::text, sqlerrm::jsonb);
    end;
  end loop;
  if (v_out #>> '{1,moved}')::numeric <> 0 or (v_out #>> '{1,gold}')::bigint <= 0 or (v_out #>> '{1,stock}')::numeric <> (v_out #>> '{1,aboard}')::numeric or (v_out #>> '{1,aboard}')::numeric < 3 then
    raise exception 'WY_MOVED: %', v_out->'1';
  end if;
  raise notice 'PASS: WY_MOVED - % gold, the sum moved 0; % units of salvage off the pirate homes'' stock, % aboard', v_out #>> '{1,gold}', v_out #>> '{1,stock}', v_out #>> '{1,aboard}';
  if (v_out #>> '{2,gold}')::bigint <> 100 or (v_out #>> '{3,gold}')::bigint <> 0 or (v_out #>> '{3,aboard}')::numeric <> 0 or (v_out #>> '{3,moved}')::numeric <> 0 then
    raise exception 'WY_CAPS: % / %', v_out->'2', v_out->'3';
  end if;
  raise notice 'PASS: WY_CAPS - a day''s cap of 100 pays 100; an empty hoard and empty homes pay nothing';
  if (v_out #>> '{4,free}')::numeric < 0 or (v_out #>> '{4,stock}')::numeric <> (v_out #>> '{4,aboard}')::numeric or (v_out #>> '{4,aboard}')::numeric > 3 then
    raise exception 'WY_HOLD: %', v_out->'4';
  end if;
  raise notice 'PASS: WY_HOLD - a nearly full hold took %', v_out #>> '{4,aboard}';
  if (v_out #>> '{1,carry,rp}')::int <> 6 then raise exception 'WY_RP: %', v_out->'1'; end if;
  raise notice 'PASS: WY_RP - 3 rounds won: 6 Reputation';
end $p$;
