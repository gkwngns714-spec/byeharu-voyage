-- ═══════════════════════════════════════════════════════════
-- PROOF 17 — A CAPITAL DRAWS ON ITS NATION  (migration 0307)
--
--   0307's own self-assert runs public.crown_aid over a probe nation alone (a migration never runs a real game step, docs/OPS_HEALTH.md section 4).
--   This proof runs the REAL public.city_day over the WHOLE world, at share 0 and at the share, each pass rolled back.
--
-- @pass CALL_ZERO_NONE    share 0: no CROWN_CALL is written, and the short city gets only what its capital holds
-- @pass CALL_EXACT        the share: the shortfall of the realm is called from its richest harbour, and the short city is topped up to its target
-- @pass CALL_ANSWER       city_day still answers 'aided' and 'aid' as numbers, equal to its CROWN_AID flows
-- @pass CALL_NO_MINT      the sum of every purse in the world is unchanged; CROWN_CALL and CROWN_AID each net to zero
-- @pass CALL_DONOR_SAFE   the donor stays above its target and its reserve, and its bid factor is 1
-- ═══════════════════════════════════════════════════════════

do $$
declare
  x      record;
  v_last int := world.game_day() - 1;
  v_mark bigint := coalesce((select max(id) from public.treasury_flows), 0);
  v_zero jsonb; v_full jsonb;
  v_r    jsonb;
  v_sum  bigint;
  v_need bigint;
begin
  -- a realm with a capital, a harbour to be short and a harbour to be the donor
  select p.id, public.city_capital(p.id) as cap,
         (select q.id from public.ports q where q.kind = 'HARBOUR' and q.id <> p.id and public.city_capital(q.id) = public.city_capital(p.id)
             and q.id <> public.city_capital(p.id) order by q.code limit 1) as donor
    into x
    from public.ports p
   where p.kind = 'HARBOUR' and public.city_capital(p.id) is not null and public.city_capital(p.id) <> p.id
   order by (select count(*) from public.port_allegiance a where a.nation_id = public.port_nation(p.id)) desc, p.code limit 1;
  if x.donor is null then
    raise exception 'PROOF 17 FAIL: no realm with two harbours besides its capital';
  end if;

  update public.world_config set value = 'true'::jsonb where key in ('city_treasury_enabled', 'economy_closed');
  update public.world_config set value = to_jsonb(50000) where key = 'treasury_reserve_floor';
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set earned_day = v_last;                                 -- only the aid runs
  -- every other city of this realm at the floor and its reserve 0, so this one short city is the realm's whole need and no third harbour outbids the donor
  update public.port_treasury t set ducats = 50000, reserve = 0
    from public.ports p where p.id = t.port_id and public.city_capital(t.port_id) = x.cap;
  update public.port_treasury set ducats = 1000, reserve = 0 where port_id = x.id;                -- broke: 49,000 short
  update public.port_treasury set ducats = 100000000000, reserve = 7777 where port_id = x.donor;  -- rich
  update public.port_treasury set ducats = 7777 + 5000, reserve = 7777 where port_id = x.cap;     -- 5,000 above its own reserve
  v_need := 49000 - 5000;

  update public.world_config set value = to_jsonb(0) where key = 'crown_call_share';
  begin
    v_r := public.city_day();
    raise exception using errcode = 'ZX317', message = (v_r || jsonb_build_object(
      'short', (select coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.id > v_mark and f.port_id = x.id and f.kind = 'CROWN_AID'),
      'calls', (select count(*) from public.treasury_flows f where f.id > v_mark and f.kind = 'CROWN_CALL')))::text;
  exception when sqlstate 'ZX317' then
    v_zero := sqlerrm::jsonb;
  end;
  if (v_zero ->> 'calls')::int <> 0 or (v_zero ->> 'short')::bigint <> 5000 then
    raise exception 'PROOF 17 FAIL: share 0 is not 0306: %', v_zero;
  end if;
  raise notice 'PASS: CALL_ZERO_NONE — no call, the short city got its capital''s 5,000';

  update public.world_config set value = to_jsonb(0.10) where key = 'crown_call_share';
  v_sum := (select sum(public.treasury_balance(t.port_id)) from public.port_treasury t);
  begin
    v_r := public.city_day();
    raise exception using errcode = 'ZX317', message = (v_r || jsonb_build_object(
      'short', (select coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.id > v_mark and f.port_id = x.id and f.kind = 'CROWN_AID'),
      'donor_call', (select coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.id > v_mark and f.port_id = x.donor and f.kind = 'CROWN_CALL'),
      'cap_after', public.treasury_balance(x.cap),
      'in_n', (select count(*) from public.treasury_flows f where f.id > v_mark and f.kind = 'CROWN_AID' and f.ducats > 0),
      'in_d', (select coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.id > v_mark and f.kind = 'CROWN_AID' and f.ducats > 0),
      'net_aid', (select coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.id > v_mark and f.kind = 'CROWN_AID'),
      'net_call', (select coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.id > v_mark and f.kind = 'CROWN_CALL'),
      'moved', (select sum(public.treasury_balance(t.port_id)) from public.port_treasury t) - v_sum,
      'donor_after', public.treasury_balance(x.donor),
      'donor_target', public.city_aid_target(x.donor),
      'donor_bid', public.city_bid_factor(x.donor)))::text;
  exception when sqlstate 'ZX317' then
    v_full := sqlerrm::jsonb;
  end;
  if (v_full ->> 'donor_call')::bigint <> -v_need or (v_full ->> 'short')::bigint <> 49000 or (v_full ->> 'cap_after')::bigint <> 7777 then
    raise exception 'PROOF 17 FAIL: the shortfall was not called exactly: %', v_full;
  end if;
  raise notice 'PASS: CALL_EXACT — % called, the short city got %', -(v_full ->> 'donor_call')::bigint, v_full ->> 'short';

  if jsonb_typeof(v_full -> 'aided') <> 'number' or jsonb_typeof(v_full -> 'aid') <> 'number'
     or (v_full ->> 'aided')::bigint <> (v_full ->> 'in_n')::bigint or (v_full ->> 'aid')::bigint <> (v_full ->> 'in_d')::bigint then
    raise exception 'PROOF 17 FAIL: city_day''s answer is not its flows: %', v_full;
  end if;
  raise notice 'PASS: CALL_ANSWER — % cities, % d.', v_full ->> 'aided', v_full ->> 'aid';

  if (v_full ->> 'net_aid')::bigint <> 0 or (v_full ->> 'net_call')::bigint <> 0 or (v_full ->> 'moved')::bigint <> 0 then
    raise exception 'PROOF 17 FAIL: gold was made or lost: %', v_full;
  end if;
  raise notice 'PASS: CALL_NO_MINT — every purse summed, moved 0';

  if (v_full ->> 'donor_after')::bigint < (v_full ->> 'donor_target')::bigint or (v_full ->> 'donor_bid')::numeric <> 1 then
    raise exception 'PROOF 17 FAIL: the donor was hurt: %', v_full;
  end if;
  raise notice 'PASS: CALL_DONOR_SAFE — the donor kept % d., bid %', v_full ->> 'donor_after', v_full ->> 'donor_bid';
end
$$;
