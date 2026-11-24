-- ══════════════════════════════════════════════════════════════════════════════════
-- PROOF 198 - DIVIDENDS ARE PAID EVERY HOUR  (migration 0495; docs/design/hq-corp-2026-11-24.md D6, economy file section 9)
--
--   The owner, row 373: "investing will give you dividends every hour". 0495's own self-assert runs public.city_coupons on a probe
--   place alone (a migration never runs a real game step). This proof runs the REAL public.tick_city over the WHOLE world: a house
--   that owns NO FLEET buys shares at Lisbon through the real door (public.invest_for), so no fleet of hers can ever arrive there;
--   a second fleetless house holds the owner's own 461,384 d. at a second harbour, a third the same at a harbour that loses money.
--   Rolled back by proof.mjs.
--
-- @pass DH_DARK       dark (as deployed): a real tick pays no purse, writes no DIVIDEND ledger row and no hourly state
-- @pass DH_NO_FLEET   lit: the house with no fleet is paid 1/24 of her day's coupon (public.coupon_day_of) straight to her purse by the tick
-- @pass DH_OWNER      lit: 461,384 d. of shares earn 346 d. an hour where the city's 24 hours cover it, and 0 where the city lost
-- @pass DH_ONCE       a second tick in the same real hour pays nothing, and neither does the rule called again by itself
-- @pass DH_CARRY      a holder the hour skipped (her row was held) is paid that hour with the next: an owed hour on the purse row makes
--                     the real tick pay her two hours' coupon, once, and clears it. The owed hour is written here by the proof: one
--                     session cannot hold a row against itself, so the SKIP LOCKED branch itself is not run by this proof
-- @pass DH_TRAILING   the next hour, with no profit of its own, pays again from the trailing 24 hours; after a loss bigger than the
--                     24 hours' profit that city pays 0 and the others go on
-- @pass DH_CLOSED     no coin is minted: what left the cities as DIVIDEND flows is what the ledger credited the holders, is the
--                     receipt's coupons_paid; and the world's sum (purses, city purses, flows, set aside) is the same before and after
-- @pass DH_ACCRUED    old `accrued` is not touched by the hourly ticks and is still collected by public.collect_coupons
-- @pass DH_COST       the tick's receipt has no error in any step; the step's ms and the rows of one lit hour are printed
-- ══════════════════════════════════════════════════════════════════════════════════

do $p$
declare
  v_now   timestamptz := now();
  v_rday  int := public.real_day(v_now);
  v_mark  bigint := coalesce((select max(id) from public.treasury_flows), 0);
  v_nat   uuid := (select g.nation_id from public.great_powers g order by g.nation_id limit 1);
  v_lis   uuid := (select h.id from public.ports h where h.code = 'LIS' and h.kind = 'HARBOUR');
  v_h2    uuid;
  v_h3    uuid;
  v_me    uuid;
  v_own   uuid;
  v_sad   uuid;
  v_kind  text;
  v_n     int;
  v_buy   jsonb;
  v_cost  bigint;
  v_due   bigint;
  v_r0    jsonb;
  v_r1    jsonb;
  v_r1b   jsonb;
  v_r2    jsonb;
  v_r3    jsonb;
  v_w0    numeric;
  v_w1    numeric;
  v_led0  bigint;
  v_led1  bigint;
  v_sl0   bigint;
  v_sl1   bigint;
  v_me1   bigint;
  v_own1  bigint;
  v_x     bigint;
begin
  if v_lis is null then
    raise exception 'PROOF 198 FAIL: no Lisbon in this world';
  end if;
  select x.id into v_h2 from public.ports x where x.kind = 'HARBOUR' and x.id <> v_lis order by x.code limit 1;
  select x.id into v_h3 from public.ports x where x.kind = 'HARBOUR' and x.id not in (v_lis, v_h2) order by x.code limit 1;

  -- the purses lit, the rate as on prod (0.018 a real day), every harbour with a purse row and money, the books settled
  update public.world_config set value = 'true'::jsonb where key = 'city_treasury_enabled';
  update public.world_config set value = to_jsonb(0.018) where key = 'works_coupon_day';
  insert into public.port_treasury (port_id) select p.id from public.ports p where p.kind = 'HARBOUR' on conflict (port_id) do nothing;
  update public.port_treasury set coupon_day = v_rday, earned_day = world.game_day(v_now) - 1;
  perform public.treasury_post(v_lis, 'BUY', 10000000, null, null);
  perform public.treasury_post(v_h2, 'BUY', 10000000, null, null);
  perform public.treasury_post(v_h3, 'BUY', 10000000, null, null);
  perform public.tick_city(v_now);
  perform public.tick_city(v_now);

  -- THREE HOUSES WITH NO FLEET. `me` buys at Lisbon through the real door; the other two hold the owner's 461,384 d. (555 d. set aside from before).
  insert into public.players (company_name, nation_id, ducats, is_npc) values ('Proof 198 me', v_nat, 5000000, false) returning id into v_me;
  insert into public.players (company_name, nation_id, ducats, is_npc) values ('Proof 198 owner', v_nat, 0, false) returning id into v_own;
  insert into public.players (company_name, nation_id, ducats, is_npc) values ('Proof 198 sad', v_nat, 0, false) returning id into v_sad;
  select k.kind, least(public.city_offered(v_lis, k.kind), greatest(1, ceil(200000::numeric / public.works_share_price(coalesce(w.level, 0)))::int))
    into v_kind, v_n
    from unnest(array['docks', 'market', 'production', 'inn']) with ordinality k(kind, o)
    left join public.city_works w on w.port_id = v_lis and w.kind = k.kind
   where public.city_offered(v_lis, k.kind) > 0
   order by k.o limit 1;
  if v_kind is null then
    raise exception 'PROOF 198 FAIL: Lisbon offers no shares in any work';
  end if;
  v_buy  := public.invest_for(v_me, v_lis, v_kind, v_n);
  v_cost := (v_buy->>'cost')::bigint;
  v_due  := round(public.coupon_day_of(v_lis, v_me, v_cost) / 24)::bigint;
  if not coalesce((v_buy->>'ok')::boolean, false) or v_due < 1 then
    raise exception 'PROOF 198 FAIL: the buy did not go through, or its hourly coupon is nought: % (due %)', v_buy, v_due;
  end if;
  insert into public.city_shares (port_id, kind, player_id, shares, paid, accrued, accrued_day) values
    (v_h2, 'docks', v_own, 10, 461384, 555, world.game_day(v_now)),
    (v_h3, 'docks', v_sad, 10, 461384, 555, world.game_day(v_now));
  if exists (select 1 from public.fleets f where f.player_id in (v_me, v_own, v_sad)) then
    raise exception 'PROOF 198 FAIL: a proof house has a fleet';
  end if;
  update public.world_config set value = '0'::jsonb where key = 'works_level_max';   -- no city builds: a city's profit is what this proof posts

  -- the hour's trade: Lisbon and the second harbour earn 240,000 d. (10,000 an hour may be paid); the third loses 4,000
  perform public.tick_city(v_now);                                    -- the buy's SHARE flow rolled (capital, not profit)
  update public.port_treasury set profit = 0, coupon_day = v_rday;
  perform public.treasury_post(v_lis, 'BUY', 240000, null, null);
  perform public.treasury_post(v_h2, 'BUY', 240000, null, null);
  perform public.treasury_post(v_h3, 'BUY', 1000, null, null);
  perform public.treasury_post(v_h3, 'SELL', -5000, null, null);

  -- ── DARK: a real tick, as deployed ──
  begin
    v_r0 := public.tick_city(v_now);
    if v_r0->'errors' <> '{}'::jsonb
       or (select pl.ducats from public.players pl where pl.id = v_own) <> 0
       or exists (select 1 from public.ledger l where l.player_id in (v_me, v_own, v_sad) and l.kind = 'DIVIDEND')
       or exists (select 1 from public.port_treasury t where t.coupon_hour <> 0 or t.profit_hours <> '{}'::bigint[]) then
      raise exception 'PROOF 198 FAIL: dark, the tick paid a purse or wrote hourly state: %', v_r0;
    end if;
    raise exception using errcode = 'ZX198', message = v_r0::text;
  exception when sqlstate 'ZX198' then v_r0 := sqlerrm::jsonb;
  end;
  raise notice 'PASS: DH_DARK - a dark tick: coupons_paid %, no purse paid, no DIVIDEND ledger row, no hourly state', v_r0->>'coupons_paid';

  -- ── LIT ──
  update public.world_config set value = 'true'::jsonb where key = 'dividend_hourly_enabled';
  v_me1  := (select pl.ducats from public.players pl where pl.id = v_me);
  v_led0 := (select count(*) from public.ledger);
  v_sl0  := (select count(*) from public.stats_live_deltas);
  v_w0 := (select coalesce(sum(pl.ducats), 0) from public.players pl) + (select coalesce(sum(t.ducats), 0) from public.port_treasury t)
        + (select coalesce(sum(f.ducats), 0) from public.treasury_flows f) + (select coalesce(sum(cs.accrued), 0) from public.city_shares cs);
  v_r1 := public.tick_city(v_now);
  v_w1 := (select coalesce(sum(pl.ducats), 0) from public.players pl) + (select coalesce(sum(t.ducats), 0) from public.port_treasury t)
        + (select coalesce(sum(f.ducats), 0) from public.treasury_flows f) + (select coalesce(sum(cs.accrued), 0) from public.city_shares cs);
  v_led1 := (select count(*) from public.ledger);
  v_sl1  := (select count(*) from public.stats_live_deltas);
  if v_r1->'errors' <> '{}'::jsonb then
    raise exception 'PROOF 198 FAIL: the lit tick answered an error: %', v_r1;
  end if;
  if (select pl.ducats from public.players pl where pl.id = v_me) - v_me1 <> v_due
     or (select count(*) from public.ledger l where l.player_id = v_me and l.kind = 'DIVIDEND' and l.ducats_delta = v_due) <> 1 then
    raise exception 'PROOF 198 FAIL: the house with no fleet was not paid % d. to her purse: purse % -> %', v_due, v_me1,
      (select pl.ducats from public.players pl where pl.id = v_me);
  end if;
  raise notice 'PASS: DH_NO_FLEET - she bought % x% at Lisbon for % d., owns no fleet, and the tick paid her % d. (1/24 of %) to her purse',
    v_kind, v_n, v_cost, v_due, round(public.coupon_day_of(v_lis, v_me, v_cost));

  if (select pl.ducats from public.players pl where pl.id = v_own) <> 346 or (select pl.ducats from public.players pl where pl.id = v_sad) <> 0 then
    raise exception 'PROOF 198 FAIL: 461,384 d. earned % where the city earned and % where it lost (346 and 0 expected)',
      (select pl.ducats from public.players pl where pl.id = v_own), (select pl.ducats from public.players pl where pl.id = v_sad);
  end if;
  raise notice 'PASS: DH_OWNER - 461,384 d. of shares: 346 d. an hour where the city''s 24 hours cover it, 0 d. where the city lost 4,000';

  v_x := (select -coalesce(sum(f.ducats), 0) from public.treasury_flows f where f.id > v_mark and f.kind = 'DIVIDEND');
  if v_x <> v_due + 346 or (v_r1->>'coupons_paid')::bigint <> v_x
     or (select coalesce(sum(l.ducats_delta), 0) from public.ledger l where l.player_id in (v_me, v_own, v_sad) and l.kind = 'DIVIDEND') <> v_x
     or v_w1 <> v_w0 then
    raise exception 'PROOF 198 FAIL: coin was minted or lost: flows %, receipt %, expected %, the world % -> %', v_x, v_r1->>'coupons_paid', v_due + 346, v_w0, v_w1;
  end if;
  raise notice 'PASS: DH_CLOSED - % d. left two cities as DIVIDEND flows, the ledger credited the holders % d., the receipt says %; the world''s sum % before and after',
    v_x, v_x, v_r1->>'coupons_paid', v_w0;

  v_r1b := public.tick_city(v_now);
  if (v_r1b->>'coupons_paid')::bigint <> 0 or v_r1b->'errors' <> '{}'::jsonb
     or (public.city_coupons(v_h2, v_now)->>'paid')::bigint <> 0 or (public.city_coupon_hour(v_h2, v_now)->>'paid')::bigint <> 0
     or (select pl.ducats from public.players pl where pl.id = v_own) <> 346 then
    raise exception 'PROOF 198 FAIL: a second tick in the same hour paid: %', v_r1b;
  end if;
  raise notice 'PASS: DH_ONCE - the same hour again: coupons_paid %; the rule called again by itself paid 0', v_r1b->>'coupons_paid';

  -- the next hour: nothing earned in it; then Lisbon loses 300,000 d. (more than its 24 hours earned)
  v_r2 := public.tick_city(v_now + interval '1 hour');
  v_own1 := (select pl.ducats from public.players pl where pl.id = v_own);
  perform public.treasury_post(v_lis, 'SELL', -300000, null, null);
  v_r3 := public.tick_city(v_now + interval '2 hours');
  if v_r2->'errors' <> '{}'::jsonb or v_r3->'errors' <> '{}'::jsonb
     or (v_r2->>'coupons_paid')::bigint <> v_due + 346 or v_own1 <> 692
     or (v_r3->>'coupons_paid')::bigint <> 346
     or (select pl.ducats from public.players pl where pl.id = v_me) - v_me1 <> 2 * v_due
     or (select pl.ducats from public.players pl where pl.id = v_own) <> 3 * 346
     or (select pl.ducats from public.players pl where pl.id = v_sad) <> 0 then
    raise exception 'PROOF 198 FAIL: the trailing 24 hours: hour 2 %, hour 3 %', v_r2, v_r3;
  end if;
  raise notice 'PASS: DH_TRAILING - hour 2 earned nothing and paid % d. from the 24 hours; after Lisbon lost 300,000 d. hour 3 paid % d. (Lisbon 0, the other city 346)',
    v_r2->>'coupons_paid', v_r3->>'coupons_paid';

  -- THE CARRY: the hour before skipped her (written as the skipped run writes it); the real tick pays 2 x 346, once, and clears it
  update public.port_treasury t set coupon_owed = jsonb_build_object(v_own::text, 1) where t.port_id = v_h2;
  v_r3 := public.tick_city(v_now + interval '3 hours');
  v_r2 := public.tick_city(v_now + interval '3 hours');
  if v_r3->'errors' <> '{}'::jsonb or (v_r3->>'coupons_paid')::bigint <> 692 or (v_r2->>'coupons_paid')::bigint <> 0
     or (select pl.ducats from public.players pl where pl.id = v_own) <> 5 * 346
     or (select t.coupon_owed from public.port_treasury t where t.port_id = v_h2) <> '{}'::jsonb
     or exists (select 1 from public.port_treasury t where t.coupon_owed <> '{}'::jsonb) then
    raise exception 'PROOF 198 FAIL: the owed hour was not paid once with the next: % then %', v_r3, v_r2;
  end if;
  raise notice 'PASS: DH_CARRY - one owed hour: the tick paid her % d. (2 x 346), the same hour again %, and nothing is owed any more',
    v_r3->>'coupons_paid', v_r2->>'coupons_paid';

  if (select cs.accrued from public.city_shares cs where cs.port_id = v_h2 and cs.player_id = v_own) <> 555 then
    raise exception 'PROOF 198 FAIL: old accrued was touched by the hour';
  end if;
  v_x := public.collect_coupons(v_own, v_h2, null);
  if v_x <> 555 or (select pl.ducats from public.players pl where pl.id = v_own) <> 5 * 346 + 555 then
    raise exception 'PROOF 198 FAIL: old accrued was touched by the hour, or is no longer collected';
  end if;
  raise notice 'PASS: DH_ACCRUED - four lit hours left 555 d. set aside as it was; public.collect_coupons then paid it (purse %)', 5 * 346 + 555;

  raise notice 'PASS: DH_COST - no error in any tick. Step 6 ms (PGlite): dark % of %, lit % of %, lit same hour again % of %. One lit hour here: % ledger rows, % stats_live_deltas rows, % DIVIDEND flows, % purse rows of the ring',
    v_r0 #>> '{ms,coupons}', v_r0 #>> '{ms,total}', v_r1 #>> '{ms,coupons}', v_r1 #>> '{ms,total}', v_r1b #>> '{ms,coupons}', v_r1b #>> '{ms,total}',
    v_led1 - v_led0, v_sl1 - v_sl0, 2, (select count(*) from public.port_treasury);
  raise notice 'TIMING: tick_city step 6 dark % ms, lit % ms (total % -> % ms)', v_r0 #>> '{ms,coupons}', v_r1 #>> '{ms,coupons}', v_r0 #>> '{ms,total}', v_r1 #>> '{ms,total}';
end
$p$;
