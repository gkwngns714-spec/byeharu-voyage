-- ═══════════════════════════════════════════════════════════
-- PROOF 16 — A BROKE CITY IS SHORT  (migration 0306)
--
--   0306's own self-assert runs public.crown_aid over a probe realm alone (a migration never runs a real game step, docs/OPS_HEALTH.md section 4).
--   This proof runs the REAL public.city_day over the WHOLE world, at floor 0 and at the floor, each pass rolled back.
--
-- @pass FLOOR_ZERO_TODAY    floor 0: a broke city with a zero reserve gets nothing from city_day, a city under its reserve is topped up to it
-- @pass FLOOR_TOPS_UP       the floor: the broke city with zero outflow gets exactly floor - purse from its capital
-- @pass FLOOR_ANSWER        city_day answers 'aided' and 'aid' as numbers, equal to the CROWN_AID flows it wrote
-- @pass FLOOR_NO_MINT       the sum of every purse in the world is unchanged; CROWN_AID nets to zero
-- @pass FLOOR_SALE_UNMOVED  the broke city's reserve, bid factor and surplus before the aid are the same at both floors
-- ═══════════════════════════════════════════════════════════

do $$
declare
  c_floor constant bigint := 50000;
  x      record;
  v_last int := world.game_day() - 1;
  v_mark bigint := coalesce((select max(id) from public.treasury_flows), 0);
  v_bare jsonb; v_zero jsonb; v_full jsonb;
  v_r    jsonb;
begin
  -- a harbour with a capital that is not itself, and a second one of the same capital
  select p.id, p.code, public.city_capital(p.id) as cap,
         (select q.id from public.ports q where q.kind = 'HARBOUR' and q.id <> p.id and public.city_capital(q.id) = public.city_capital(p.id)
             and q.id <> public.city_capital(p.id) order by q.code limit 1) as other
    into x
    from public.ports p
   where p.kind = 'HARBOUR' and public.city_capital(p.id) is not null and public.city_capital(p.id) <> p.id
   order by (select count(*) from public.port_allegiance a where a.nation_id = public.port_nation(p.id)) desc, p.code limit 1;
  if x.other is null then
    raise exception 'PROOF 16 FAIL: no realm with two harbours besides its capital';
  end if;

  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed');
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set earned_day = v_last;                                 -- only the aid runs
  update public.port_treasury set ducats = 1000, reserve = 0 where port_id = x.id;     -- broke, no reserve
  update public.port_treasury set ducats = 100, reserve = 60000 where port_id = x.other;  -- under a reserve above the floor
  update public.port_treasury set ducats = 100000000000, reserve = 7777 where port_id = x.cap;

  if public.city_sell_outflow(x.id) <> 0 or public.treasury_balance(x.id) <> 1000 or public.treasury_balance(x.other) <> 100 then
    raise exception 'PROOF 16 FAIL: the planted purses are not what they should be';
  end if;

  update public.world_config set value = to_jsonb(0) where key = 'treasury_reserve_floor';
  v_bare := jsonb_build_array(public.city_bid_factor(x.id), public.city_surplus(x.id), public.treasury_reserve(x.id), public.city_bid_factor(x.other), public.city_surplus(x.other));

  begin
    v_r := public.city_day();
    raise exception using errcode = 'ZX316', message = (v_r || jsonb_build_object(
      'broke', (select coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.id > v_mark and f.port_id = x.id and f.kind = 'CROWN_AID'),
      'other', (select coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.id > v_mark and f.port_id = x.other and f.kind = 'CROWN_AID')))::text;
  exception when sqlstate 'ZX316' then
    v_zero := sqlerrm::jsonb;
  end;
  if (v_zero ->> 'broke')::bigint <> 0 or (v_zero ->> 'other')::bigint <> 59900 then
    raise exception 'PROOF 16 FAIL: floor 0 is not today: %', v_zero;
  end if;
  raise notice 'PASS: FLOOR_ZERO_TODAY — broke city 0, short city 59,900';

  update public.world_config set value = to_jsonb(c_floor) where key = 'treasury_reserve_floor';
  if jsonb_build_array(public.city_bid_factor(x.id), public.city_surplus(x.id), public.treasury_reserve(x.id), public.city_bid_factor(x.other), public.city_surplus(x.other)) is distinct from v_bare then
    raise exception 'PROOF 16 FAIL: the floor moved a bid, a surplus or a reserve: %', v_bare;
  end if;
  raise notice 'PASS: FLOOR_SALE_UNMOVED — %', v_bare;

  begin
    declare
      v_sum bigint := (select sum(public.treasury_balance(t.port_id)) from public.port_treasury t);
    begin
      v_r := public.city_day();
      raise exception using errcode = 'ZX316', message = (v_r || jsonb_build_object(
        'broke', (select coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.id > v_mark and f.port_id = x.id and f.kind = 'CROWN_AID'),
        'other', (select coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.id > v_mark and f.port_id = x.other and f.kind = 'CROWN_AID'),
        'cap',   (select coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.id > v_mark and f.port_id = x.cap and f.kind = 'CROWN_AID'),
        'in_n',  (select count(*) from public.treasury_flows f where f.id > v_mark and f.kind = 'CROWN_AID' and f.ducats > 0),
        'in_d',  (select coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.id > v_mark and f.kind = 'CROWN_AID' and f.ducats > 0),
        'net',   (select coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.id > v_mark and f.kind = 'CROWN_AID'),
        'moved', (select sum(public.treasury_balance(t.port_id)) from public.port_treasury t) - v_sum))::text;
    end;
  exception when sqlstate 'ZX316' then
    v_full := sqlerrm::jsonb;
  end;
  if (v_full ->> 'broke')::bigint <> c_floor - 1000 or (v_full ->> 'other')::bigint <> 59900 then
    raise exception 'PROOF 16 FAIL: the floor did not top up exactly: %', v_full;
  end if;
  raise notice 'PASS: FLOOR_TOPS_UP — the broke city got % of its capital''s %', v_full ->> 'broke', v_full ->> 'cap';

  if jsonb_typeof(v_full -> 'aided') <> 'number' or jsonb_typeof(v_full -> 'aid') <> 'number'
     or (v_full ->> 'aided')::bigint <> (v_full ->> 'in_n')::bigint or (v_full ->> 'aid')::bigint <> (v_full ->> 'in_d')::bigint then
    raise exception 'PROOF 16 FAIL: city_day''s answer is not its flows: %', v_full;
  end if;
  raise notice 'PASS: FLOOR_ANSWER — % cities, % d.', v_full ->> 'aided', v_full ->> 'aid';

  if (v_full ->> 'net')::bigint <> 0 or (v_full ->> 'moved')::bigint <> 0 then
    raise exception 'PROOF 16 FAIL: gold was made or lost: %', v_full;
  end if;
  raise notice 'PASS: FLOOR_NO_MINT — every purse summed, moved 0';
end
$$;
